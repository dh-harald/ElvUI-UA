-- Skins > Blizzard > Battlefield -- reskins the native BattlefieldFrame in place
-- (the Battlemaster's instance list and queue window). Strips the native
-- chrome, draws an elvBackground child frame and leaves the buttons to the
-- sweep.
--
-- Real 1.12.1 structure, per `FrameXML/BattlefieldFrame.xml`:
--
-- - `BattlefieldFramePortrait` is the only BACKGROUND region of the frame. The
--   four `UI-Battlefield-*` quadrants share the BORDER layer with the three
--   FontStrings, so only the textures go and the layer has to stay on. The
--   FontStrings move to OVERLAY, above the panel that sits on the frame's own
--   base level.
-- - `BattlefieldFrameFrameLabel` holds the map name and is rewritten by
--   `BattlefieldFrame_Update`, which leaves its colour and anchor alone. It is
--   centred on the full 384px frame natively and on the panel here.
-- - `BattlefieldFrameNameHeader` sits right of the portrait natively. With the
--   portrait gone it moves over the list it labels (pfUI's spot).
-- - `BattlefieldFrameZoneDescription` is `GameFontBlack`, invisible on a dark
--   panel.
-- - `BattlefieldZone1-12` keep their native gold `UI-Listbox-Highlight2`: the
--   selected row is marked through `LockHighlight`, so the highlight carries
--   state.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's numbers for this frame.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 11, -12, -34, 74
local BUTTON_GAP = 2

local TEXTS = {
	"BattlefieldFrameFrameLabel",
	"BattlefieldFrameNameHeader",
	"BattlefieldFrameZoneDescription",
}

local function Reanchor(widget, point, relative, relativePoint, x, y)
	if not widget then return end
	pcall(widget.ClearAllPoints, widget)
	pcall(widget.SetPoint, widget, point, relative, relativePoint, x, y)
end

local function StyleTexts(frame)
	local i
	for i = 1, table.getn(TEXTS) do
		local text = _G[TEXTS[i]]
		if text then pcall(text.SetDrawLayer, text, "OVERLAY") end
	end

	local description = _G.BattlefieldFrameZoneDescription
	if description then pcall(description.SetTextColor, description, 1, 1, 1) end

	if frame.elvBackground then
		Reanchor(_G.BattlefieldFrameFrameLabel, "TOP", frame.elvBackground, "TOP", 0, -6)
	end
	Reanchor(_G.BattlefieldFrameNameHeader, "BOTTOMLEFT", _G.BattlefieldZone1, "TOPLEFT", 5, 6)
end

local function StyleButtons()
	local cancel = _G.BattlefieldFrameCancelButton
	local join = _G.BattlefieldFrameJoinButton
	local group = _G.BattlefieldFrameGroupJoinButton
	S:StyleUIPanelButton(cancel)
	S:StyleUIPanelButton(join)
	S:StyleUIPanelButton(group)
	Reanchor(group, "RIGHT", join, "LEFT", -BUTTON_GAP, 0)
end

local function ApplyBattlefieldChrome(frame)
	S:StripTextures(frame, false)
	S:Kill(_G.BattlefieldFramePortrait)
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	StyleTexts(frame)

	S:StripTextures(_G.BattlefieldListScrollFrame, false)
	S:HandleScrollBar(_G.BattlefieldListScrollFrameScrollBar)

	StyleButtons()

	S:StyleCloseButton(_G.BattlefieldFrameCloseButton)
	if frame.elvBackground then
		Reanchor(_G.BattlefieldFrameCloseButton, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	S:SkinChildren(frame)
end

local battlefieldSkinApplied = false
local function ApplyBattlefieldSkin()
	if battlefieldSkinApplied then return end
	local frame = _G.BattlefieldFrame
	if not frame then return end
	battlefieldSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere. The handle stops
	-- at the close button, which it would otherwise cover.
	S:MakeDraggable(frame, _G.BattlefieldFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyBattlefieldChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyBattlefieldChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyBattlefieldSkin()
end

S:AddBlizzardSkin("battlefield", LoadSkin)
