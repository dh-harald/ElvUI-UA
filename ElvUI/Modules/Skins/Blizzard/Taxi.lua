-- Skins > Blizzard > Taxi -- reskins the native TaxiFrame (flight master
-- map) in place. Same recipe family as Merchant.lua/Gossip.lua: strip the
-- native chrome, draw an elvBackground child frame (never SetBackdrop the
-- native frame itself), leave the functional flight-path map/nodes alone.
--
-- Real 1.12.1 structure, per `FrameXML/TaxiFrame.xml`/`.lua`. Not yet
-- verified against the live client.
--
-- - `TaxiFrame` itself carries five direct Texture regions: `TaxiPortrait`
--   (BACKGROUND), four unnamed `UI-TaxiFrame-{TopLeft,TopRight,BotLeft,
--   BotRight}` corner pieces (ARTWORK), and one NAMED OVERLAY region,
--   `TaxiMap` -- the actual continent map image `SetTaxiMap` repaints on
--   every TAXIMAP_OPENED, not decorative chrome. A blanket
--   `S:StripTextures` blanks every direct Texture region regardless of
--   name, so this file walks `GetRegions()` itself instead and skips that
--   one name.
-- - `TaxiPortrait` is `S:Kill`'d, not left to the strip above: same
--   portrait class as `GossipFramePortrait`/`CharacterFramePortrait`, fed
--   via `SetPortraitTexture` on every TAXIMAP_OPENED, which this project
--   has already found never stays cleared by a plain `SetTexture(nil)`.
-- - `TaxiMerchant` (the flight master's name) is an ARTWORK FontString
--   directly on `TaxiFrame`, promoted to OVERLAY so the panel background
--   (parked on the frame's own base level) doesn't draw over it -- same
--   fix as Merchant.lua's `PromotePanelText`.
-- - `TaxiRouteMap` (a `TaxiRouteFrame`, native custom widget type) draws
--   the actual flight nodes and route lines as its OWN dynamically-created
--   children (`TaxiButton<n>` buttons, `TaxiRoute<n>` line textures --
--   `FrameXML/TaxiFrame.lua`), never as regions of `TaxiFrame` itself --
--   so the non-recursive strip above never reaches them. Excluded from the
--   end-of-pass sweep via `S.autoSkinSkipNames` too, matching real ElvUI's
--   own scope: it never skins the nodes or lines, only the outer chrome.
-- - `TaxiCloseButton` inherits `UIPanelCloseButton`, same as every other
--   window in this family.
--
-- SCOPE: outer chrome, panel background, drag handle, close button.
-- Deliberately NOT done: node icons / route lines (functional map content,
-- not chrome).

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- Real ElvUI's own numbers for this window (`Blizzard/Taxi.lua`,
-- `source/ElvUI-vanilla`) -- pure padding choices against the real 1.12.1
-- FrameXML geometry (384x512, map at `TOP -13,-75` sized 316x352), which
-- this window doesn't customise server-side.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 11, -12, -34, 75

-- Never skin the flight-node/route-line frame -- see file header.
S.autoSkinSkipNames["TaxiRouteMap"] = true

local function PromotePanelText()
	local fs = _G.TaxiMerchant
	if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
end

-- Manual strip, not `S:StripTextures`: that helper blanks every direct
-- Texture region including named ones, and `TaxiMap` (the continent map
-- image) must survive.
local function StripChrome(frame)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "Texture" then
			local okName, name = pcall(region.GetName, region)
			if not (okName and name == "TaxiMap") then
				pcall(region.SetTexture, region, nil)
				pcall(region.Hide, region)
				region.Show = E.noop
			end
		end
	end
end

local function ApplyTaxiChrome(frame)
	StripChrome(frame)
	S:Kill(_G.TaxiPortrait)

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	PromotePanelText()

	S:StyleCloseButton(_G.TaxiCloseButton)
	-- Native anchor (`TOPRIGHT -29,-8`) sits slightly outside this panel's
	-- own corner (PANEL_RIGHT,PANEL_TOP = -34,-12) -- same class of gap
	-- already fixed on MerchantFrame's/GossipFrame's identically-anchored
	-- close buttons.
	local close = _G.TaxiCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all -- picks up anything this server adds beyond vanilla.
	S:SkinChildren(frame)
end

local taxiSkinApplied = false
local function ApplyTaxiSkin()
	if taxiSkinApplied then return end
	local frame = _G.TaxiFrame
	if not frame then return end
	taxiSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere, same gap as
	-- every other window in this family.
	local handle = S:MakeDraggable(frame)
	if handle then
		pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT, 0)
	end
	pcall(frame.SetUserPlaced, frame, true)

	ApplyTaxiChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyTaxiChrome(frame) end)
	if not ok then E:Print("Skins (taxi): TaxiFrame OnShow hook failed to install") end
end

local function LoadSkin()
	ApplyTaxiSkin()
end

S:AddBlizzardSkin("taxi", LoadSkin)
