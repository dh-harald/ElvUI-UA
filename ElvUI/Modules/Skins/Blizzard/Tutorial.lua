-- Skins > Blizzard > Tutorial -- reskins the native TutorialFrame and its alert
-- buttons (`TutorialFrameAlertButton1-10`, the pulsing "!" markers).
--
-- Real 1.12.1 structure, per `FrameXML/TutorialFrame.xml`:
--
-- - `TutorialFrame` has a native `<Backdrop>` and no art regions, and resizes
--   itself to its text in `TutorialFrame_Update`, so the panel covers the whole
--   frame. It moves through its own `<TitleRegion>`, so no drag handle.
-- - `TutorialFrameOkayButton` is built from the dialog button textures, not from
--   `UIPanelButtonTemplate`, so the sweep's fingerprint does not reach it.
-- - The alert buttons are created at load, stay around and only Show/Hide, so
--   styling them once is enough. Their icon is one cell of a sprite sheet;
--   the crop is real ElvUI's.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

local ALERT_WIDTH, ALERT_HEIGHT = 35, 45
local ALERT_ICON_INSET = 2

local function StyleAlertButton(button)
	pcall(button.SetWidth, button, ALERT_WIDTH)
	pcall(button.SetHeight, button, ALERT_HEIGHT)
	ElvUI.Util.CreateButtonBorder(button)

	local okNormal, normal = pcall(button.GetNormalTexture, button)
	if okNormal and normal then
		pcall(normal.SetTexCoord, normal, 0.09, 0.40, 0.11, 0.56)
		pcall(normal.ClearAllPoints, normal)
		pcall(normal.SetPoint, normal, "TOPLEFT", button, "TOPLEFT", ALERT_ICON_INSET, -ALERT_ICON_INSET)
		pcall(normal.SetPoint, normal, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -ALERT_ICON_INSET, ALERT_ICON_INSET)
	end

	local okHighlight, highlight = pcall(button.GetHighlightTexture, button)
	if okHighlight and highlight then
		pcall(highlight.SetTexture, highlight, 1, 1, 1, 0.3)
		pcall(highlight.ClearAllPoints, highlight)
		if okNormal and normal then
			pcall(highlight.SetAllPoints, highlight, normal)
		end
	end
end

local function StyleAlertButtons()
	local count = tonumber(_G.MAX_TUTORIAL_ALERTS) or 10
	local i
	for i = 1, count do
		local button = _G["TutorialFrameAlertButton"..i]
		if button then StyleAlertButton(button) end
	end
end

local function ApplyTutorialChrome(frame)
	S:StripTextures(frame, false)
	S:CreatePanel(frame)
	S:StyleCheckBox(_G.TutorialFrameCheckButton)
	S:StyleUIPanelButton(_G.TutorialFrameOkayButton)
end

local tutorialSkinApplied = false
local function ApplyTutorialSkin()
	if tutorialSkinApplied then return end
	local frame = _G.TutorialFrame
	if not frame then return end
	tutorialSkinApplied = true

	StyleAlertButtons()
	ApplyTutorialChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyTutorialChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyTutorialSkin()
end

S:AddBlizzardSkin("tutorial", LoadSkin)
