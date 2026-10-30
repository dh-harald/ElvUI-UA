-- Skins > Blizzard > Help -- reskins the native HelpFrame in place (GM ticket
-- and support window, `ToggleHelpFrame`). Strips the outer art, draws an
-- elvBackground child frame and leaves the page contents to the sweep.
--
-- Real 1.12.1 structure, per `FrameXML/HelpFrame.xml`:
--
-- - `HelpFrame` carries six `HelpFrame-*` quadrants (BACKGROUND) and
--   `HelpFrameHeader` (ARTWORK) as direct regions, so a non-recursive strip
--   clears them. The window title is an unnamed FontString anchored to that
--   header, so it is found by type and moved to the panel: a widget anchored to
--   a hidden texture does not reliably keep its place on Unreal Azeroth. The
--   text itself comes from the client's strings and differs per server.
-- - The pages are child frames with `setAllPoints` (`HelpFrameHome`, `HelpFrameGM`,
--   `HelpFrameOpenTicket`, `HelpFrameGeneral`, `HelpFrameHarassment`,
--   `HelpFrameStuck`, `HelpFrameBug`), swapped by `HelpFrame_ShowFrame`. Their
--   texts are the light Game fonts, fine on a dark panel. The bullet textures in
--   `HelpFrameBulletPointTemplate` and `HelpFrameHomeButtonTemplate` stay.
-- - `HelpFrameDividerTemplate` frames only hold art. They are stripped and not
--   hidden, because other widgets are anchored to them.
-- - Each page's Back or Submit button touches its Cancel button, which only
--   suits the native button art.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's numbers for this frame.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 6, -2, -45, 14
local TITLE_OFFSET = -8
local BUTTON_GAP = 3

local BUTTONS = {
	"HelpFrameHomeIssues", "HelpFrameHomeCancel",
	"HelpFrameGMBack", "HelpFrameGMCancel",
	"HelpFrameOpenTicketSubmit", "HelpFrameOpenTicketCancel",
	"HelpFrameGeneralButton", "HelpFrameGeneralButton2",
	"HelpFrameGeneralBack", "HelpFrameGeneralCancel",
	"HelpFrameVerbalHarassmentButton", "HelpFramePhysicalHarassmentButton",
	"HelpFrameHarassmentBack", "HelpFrameHarassmentCancel",
	"HelpFrameStuckStuck", "HelpFrameStuckBack", "HelpFrameStuckCancel",
}

-- { button, the Cancel button it sits left of }
local BUTTON_PAIRS = {
	{ "HelpFrameGMBack", "HelpFrameGMCancel" },
	{ "HelpFrameOpenTicketSubmit", "HelpFrameOpenTicketCancel" },
	{ "HelpFrameGeneralBack", "HelpFrameGeneralCancel" },
	{ "HelpFrameHarassmentBack", "HelpFrameHarassmentCancel" },
	{ "HelpFrameStuckBack", "HelpFrameStuckCancel" },
}

local DIVIDERS = {
	"HelpFrameOpenTicketDivider",
	"HelpFrameHarassmentDivider",
	"HelpFrameHarassmentDivider2",
	"HelpFrameBugDivider",
}

local SCROLL_FRAMES = {
	"HelpFrameGMScrollFrame",
	"HelpFrameOpenTicketScrollFrame",
}

local function MoveTitle(frame)
	local panel = frame.elvBackground
	if not panel then return end
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "FontString" then
			pcall(region.ClearAllPoints, region)
			pcall(region.SetPoint, region, "TOP", panel, "TOP", 0, TITLE_OFFSET)
			return
		end
	end
end

local function StyleButtons()
	local i
	for i = 1, table.getn(BUTTONS) do
		local button = _G[BUTTONS[i]]
		if button then S:StyleUIPanelButton(button) end
	end
	for i = 1, table.getn(BUTTON_PAIRS) do
		local button = _G[BUTTON_PAIRS[i][1]]
		local cancel = _G[BUTTON_PAIRS[i][2]]
		if button and cancel then
			pcall(button.ClearAllPoints, button)
			pcall(button.SetPoint, button, "RIGHT", cancel, "LEFT", -BUTTON_GAP, 0)
		end
	end
end

local function StyleScrollFrames()
	local i
	for i = 1, table.getn(SCROLL_FRAMES) do
		local name = SCROLL_FRAMES[i]
		S:StripTextures(_G[name], false)
		S:HandleScrollBar(_G[name.."ScrollBar"])
	end
	-- The ticket text has nothing behind it once the frame art is gone.
	S:CreateField(_G.HelpFrameOpenTicketScrollFrame, -4, 4, 4, 0)
end

local function ApplyHelpChrome(frame)
	S:StripTextures(frame, false)
	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	MoveTitle(frame)

	local i
	for i = 1, table.getn(DIVIDERS) do
		S:StripTextures(_G[DIVIDERS[i]], false)
	end

	StyleScrollFrames()
	StyleButtons()

	S:StyleCloseButton(_G.HelpFrameCloseButton)
	local close = _G.HelpFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	S:SkinChildren(frame)
end

local helpSkinApplied = false
local function ApplyHelpSkin()
	if helpSkinApplied then return end
	local frame = _G.HelpFrame
	if not frame then return end
	helpSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere. The handle stops
	-- at the close button, which it would otherwise cover.
	S:MakeDraggable(frame, _G.HelpFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyHelpChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyHelpChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyHelpSkin()
end

S:AddBlizzardSkin("help", LoadSkin)
