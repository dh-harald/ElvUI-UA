-- Skins > Blizzard > DressingRoom -- reskins the native DressUpFrame
-- (Ctrl+click item preview) in place. Same recipe family as Taxi.lua:
-- strip the native chrome, draw an elvBackground child frame (never
-- SetBackdrop the native frame itself), keep the functional content.
--
-- Real 1.12.1 structure, per `FrameXML/DressUpFrame.xml`/`.lua`:
--
-- - `DressUpFrame` itself carries all of its art as direct regions:
--   `DressUpFramePortrait` (BACKGROUND), four unnamed `UI-Character-General`/
--   `SkillFrame-Bot*` corner pieces (ARTWORK), and four NAMED OVERLAY
--   regions, `DressUpBackground{TopLeft,TopRight,BotLeft,BotRight}` -- the
--   race-specific backdrop behind the model, textured once by
--   `SetDressUpBackground()` from the frame's OnLoad. A blanket
--   `S:StripTextures` would blank those too and nothing would ever repaint
--   them, so this file walks `GetRegions()` itself and skips them.
-- - The race backdrop is desaturated, as in real ElvUI, so the coloured
--   art does not clash with the dark panel.
-- - `DressUpFramePortrait` is `S:Kill`'d: the frame's OnShow refills it
--   with `SetPortraitTexture` on every open.
-- - `DressUpFrameTitleText`/`DescriptionText` are ARTWORK FontStrings
--   directly on the frame, promoted to OVERLAY so the panel background
--   (parked on the frame's own base level) does not draw over them. The
--   race backdrop starts below the description, so the two OVERLAY
--   groups never overlap.
-- - `DressUpModel` is a child frame, so it keeps drawing above both the
--   panel and the frame's own OVERLAY backdrop.
-- - `DressUpModelRotateLeftButton`/`RightButton` are the same 35x35
--   Normal/Pushed/Highlight-only shape as the Character/Stable rotate
--   buttons -- `S:StyleModelRotateButtons`.
--
-- SCOPE: outer chrome, panel background, drag handle, close button,
-- rotate buttons, Close/Reset buttons, race backdrop tint.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's own numbers for this window (`Blizzard/DressingRoom.lua`,
-- `ElvUI-vanilla`; pfUI uses 10,-10,-32,72) against the 384x512 FrameXML
-- geometry. The right/bottom insets sit close to the native
-- `<HitRectInsets>` (right=30, bottom=45) plus the button row.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -12, -33, 73

local BACKGROUND_NAMES = {
	DressUpBackgroundTopLeft = true,
	DressUpBackgroundTopRight = true,
	DressUpBackgroundBotLeft = true,
	DressUpBackgroundBotRight = true,
}

local PANEL_TEXTS = { "DressUpFrameTitleText", "DressUpFrameDescriptionText" }

-- Manual strip, not `S:StripTextures`: that helper blanks every direct
-- Texture region including named ones, and the race backdrop must survive.
local function StripChrome(frame)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "Texture" then
			local okName, name = pcall(region.GetName, region)
			if not (okName and name and BACKGROUND_NAMES[name]) then
				pcall(region.SetTexture, region, nil)
				pcall(region.Hide, region)
				region.Show = E.noop
			end
		end
	end
end

local function TintBackground()
	local name
	for name in pairs(BACKGROUND_NAMES) do
		local tex = _G[name]
		if tex then pcall(tex.SetDesaturated, tex, true) end
	end
end

local function PromotePanelText()
	local i
	for i = 1, table.getn(PANEL_TEXTS) do
		local fs = _G[PANEL_TEXTS[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end

	-- Native offset (+10) centres the text on the full 384px frame; -5
	-- centres it on the narrower panel instead (real ElvUI's value).
	local desc, title = _G.DressUpFrameDescriptionText, _G.DressUpFrameTitleText
	if desc and title then
		pcall(desc.ClearAllPoints, desc)
		pcall(desc.SetPoint, desc, "CENTER", title, "BOTTOM", -5, -22)
	end
end

local function StyleRotateButtons(frame)
	local left, right = _G.DressUpModelRotateLeftButton, _G.DressUpModelRotateRightButton
	S:StyleModelRotateButtons(left, right)

	-- The styled buttons shrink to 21x21; real ElvUI's anchors tuck them
	-- inside the backdrop's top-left corner with a gap between the borders.
	if left then
		pcall(left.ClearAllPoints, left)
		pcall(left.SetPoint, left, "TOPLEFT", frame, "TOPLEFT", 25, -79)
	end
	if right and left then
		pcall(right.ClearAllPoints, right)
		pcall(right.SetPoint, right, "TOPLEFT", left, "TOPRIGHT", 3, 0)
	end
end

local function StyleButtons(frame)
	local cancel, reset = _G.DressUpFrameCancelButton, _G.DressUpFrameResetButton
	S:StyleUIPanelButton(cancel)
	S:StyleUIPanelButton(reset)

	-- Natively the two buttons touch; with borders they need a gap.
	if cancel then
		pcall(cancel.ClearAllPoints, cancel)
		pcall(cancel.SetPoint, cancel, "CENTER", frame, "TOPLEFT", 306, -423)
	end
	if reset and cancel then
		pcall(reset.ClearAllPoints, reset)
		pcall(reset.SetPoint, reset, "RIGHT", cancel, "LEFT", -3, 0)
	end
end

local function ApplyDressUpChrome(frame)
	StripChrome(frame)
	S:Kill(_G.DressUpFramePortrait)
	TintBackground()

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	PromotePanelText()

	StyleRotateButtons(frame)
	StyleButtons(frame)

	S:StyleCloseButton(_G.DressUpFrameCloseButton)
	-- The native anchor (`CENTER` at `TOPRIGHT -46,-25`) is relative to the
	-- 384px frame, not to this panel; pinned to the panel corner instead,
	-- same inset as every other window in this family.
	local close = _G.DressUpFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all -- picks up anything this server adds beyond vanilla.
	S:SkinChildren(frame)
end

local dressUpSkinApplied = false
local function ApplyDressUpSkin()
	if dressUpSkinApplied then return end
	local frame = _G.DressUpFrame
	if not frame then return end
	dressUpSkinApplied = true

	-- Not `movable` in the XML; `S:MakeDraggable` sets the flag itself. The
	-- close button is passed so the handle stops at its left edge instead
	-- of swallowing its clicks.
	S:MakeDraggable(frame, _G.DressUpFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyDressUpChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyDressUpChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyDressUpSkin()
end

S:AddBlizzardSkin("dressingroom", LoadSkin)
