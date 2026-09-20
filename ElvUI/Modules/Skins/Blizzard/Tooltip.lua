-- Tooltip skin -- real ElvUI's Modules/Skins/Blizzard/Tooltip.lua
-- (ElvUI-vanilla/): a flat "Transparent" body with a 1px border on every
-- GameTooltip-type frame, and an ElvUI status bar texture with its own
-- backdrop on GameTooltipStatusBar.
--
-- Deliberate exception to this project's "never colour a native backdrop"
-- rule, limited to this frame family and to colour calls only (no backdrop
-- table swap):
--   * DisableDrawLayer("BACKGROUND")/("BORDER") has no visible effect on
--     GameTooltip on UA, so the native backdrop cannot be switched off;
--   * on UA a backdrop colour set on GameTooltip also lands on ItemRefTooltip
--     (the <Backdrop> is shared per template) but was measured not to reach
--     DropDownList, so the spill stays inside the tooltip family, which is
--     skinned the same way anyway. The legacy client applies it per frame.
--     Side effect on UA: a GameTooltipTemplate tooltip of another addon, not
--     in TOOLTIPS, loses its fill as well.
--
-- Both native backdrop colours get alpha 0. The visible body is a child frame
-- placed one frame level BELOW the tooltip: the lines are the tooltip's own
-- regions, and a child at a lower level draws under them (measured on UA),
-- whereas one at the default child level would cover the text. It carries
-- backdropfadecolor at tooltip.colorAlpha plus the 1px border, 4 units inside
-- the frame edge (the native fill starts 5 in, GameTooltipTemplate
-- BackgroundInsets; the lines start 10 in). The native fill texture cannot
-- serve as the body: it has an alpha of its own, so even colorAlpha 1 leaves
-- it see-through. A tooltip at level 0 is raised to 1 so there is room below.
--
-- Colours and the level are re-applied on OnShow, and on the frame AFTER any
-- of these tooltips hides. The native GameTooltip_OnHide resets both backdrop
-- colours, and on UA that reset reaches every tooltip of the template: hiding
-- GameTooltip brings the native look back on an open ItemRefTooltip. A colour
-- set from an OnHide hook of the same frame does not hold against that reset
-- on UA (measured), one set on the next frame does, with no visible flicker.
-- On the legacy client the reset stays on the hiding tooltip, which OnShow
-- covers anyway.
--
-- Height, anchoring and text of the status bar belong to the Tooltip module
-- (TT:SetupHealthBar), as in real ElvUI.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "WorldMapTooltip" }

local BACKDROP_INSET = 4

local FLAT_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}

local function BorderColor()
	local c = E.db.general and E.db.general.bordercolor
	if c then return c.r, c.g, c.b end
	return 0, 0, 0
end

local function PlaceBackdrop(tt)
	local backdrop = tt.elvTooltipBackdrop
	if not backdrop then return end

	local okLevel, level = pcall(tt.GetFrameLevel, tt)
	level = (okLevel and tonumber(level)) or 1
	if level < 1 then
		pcall(tt.SetFrameLevel, tt, 1)
		level = 1
	end
	pcall(backdrop.SetFrameLevel, backdrop, level - 1)
end

local function ApplyColors(tt)
	local fill = E.db.general and E.db.general.backdropfadecolor
	local r, g, b = 0.06, 0.06, 0.06
	if fill then r, g, b = fill.r, fill.g, fill.b end
	local alpha = (E.db.tooltip and E.db.tooltip.colorAlpha) or 0.8

	pcall(tt.SetBackdropColor, tt, r, g, b, 0)
	pcall(tt.SetBackdropBorderColor, tt, 0, 0, 0, 0)

	local backdrop = tt.elvTooltipBackdrop
	if backdrop then
		pcall(backdrop.SetBackdropColor, backdrop, r, g, b, alpha)
		local br, bg, bb = BorderColor()
		pcall(backdrop.SetBackdropBorderColor, backdrop, br, bg, bb, 1)
	end

	PlaceBackdrop(tt)
end

local function CreateBackdrop(tt)
	if tt.elvTooltipBackdrop then return end

	local ok, backdrop = pcall(CreateFrame, "Frame", nil, tt)
	if not ok or not backdrop then return end

	pcall(backdrop.SetPoint, backdrop, "TOPLEFT", tt, "TOPLEFT", BACKDROP_INSET, -BACKDROP_INSET)
	pcall(backdrop.SetPoint, backdrop, "BOTTOMRIGHT", tt, "BOTTOMRIGHT", -BACKDROP_INSET, BACKDROP_INSET)
	pcall(backdrop.SetBackdrop, backdrop, FLAT_BACKDROP)
	pcall(backdrop.EnableMouse, backdrop, false)
	backdrop.elvSurface = true

	tt.elvTooltipBackdrop = backdrop
end

local function ReapplyAll()
	local i
	for i = 1, table.getn(TOOLTIPS) do
		local tt = _G[TOOLTIPS[i]]
		if tt and tt.elvTooltipBackdrop then
			ApplyColors(tt)
		end
	end
end

-- A hidden frame whose OnUpdate hides it again and re-applies every skinned
-- tooltip's colours, so each Show() yields exactly one pass on the next frame.
local reapplyFrame

local function ScheduleReapply()
	if not reapplyFrame then
		local ok, frame = pcall(CreateFrame, "Frame")
		if not ok or not frame then return end
		frame:Hide()
		frame:SetScript("OnUpdate", function()
			frame:Hide()
			ReapplyAll()
		end)
		reapplyFrame = frame
	end
	reapplyFrame:Show()
end

local function SkinTooltip(tt)
	CreateBackdrop(tt)
	ApplyColors(tt)

	local okShow = S:TryHookScript(tt, "OnShow", function() ApplyColors(tt) end)
	local okHide = S:TryHookScript(tt, "OnHide", ScheduleReapply)
	if not okShow or not okHide then
		S:ReportSkinProblem()
	end
end

-- The bar's own backdrop sits one unit outside the bar, one frame level
-- below it, so the fill texture draws on top of it.
local function SkinStatusBar()
	local bar = _G.GameTooltipStatusBar
	if not bar then return end

	pcall(bar.SetStatusBarTexture, bar, (E.media and E.media.normTex) or "Interface\\Buttons\\WHITE8x8")

	if bar.elvBackdrop then return end
	local ok, backdrop = pcall(CreateFrame, "Frame", nil, bar)
	if not ok or not backdrop then return end

	pcall(backdrop.SetPoint, backdrop, "TOPLEFT", bar, "TOPLEFT", -1, 1)
	pcall(backdrop.SetPoint, backdrop, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	local okLevel, level = pcall(bar.GetFrameLevel, bar)
	level = (okLevel and tonumber(level)) or 1
	if level > 0 then
		pcall(backdrop.SetFrameLevel, backdrop, level - 1)
	end
	pcall(backdrop.EnableMouse, backdrop, false)
	E:SetTemplate(backdrop, "Transparent")
	backdrop.elvSurface = true

	bar.elvBackdrop = backdrop
end

-- ItemRefTooltip's close button, as real ElvUI's S:HandleCloseButton does:
-- the shared ElvUI close button (20x20, bordered "X"). The native anchor is
-- TOPRIGHT (+1, 0), which would put the smaller button on the frame edge,
-- outside the flat body that starts BACKDROP_INSET units in, so it is moved
-- inside it (pfUI uses the same -6, -6).
local function SkinItemRefCloseButton()
	local button = _G.ItemRefCloseButton
	local tooltip = _G.ItemRefTooltip
	if not button or not tooltip then return end

	S:StyleCloseButton(button)
	pcall(button.ClearAllPoints, button)
	pcall(button.SetPoint, button, "TOPRIGHT", tooltip, "TOPRIGHT", -6, -6)
end

local function LoadSkin()
	local i
	for i = 1, table.getn(TOOLTIPS) do
		local tt = _G[TOOLTIPS[i]]
		if tt then
			SkinTooltip(tt)
		end
	end

	SkinStatusBar()
	SkinItemRefCloseButton()
end

S:AddBlizzardSkin("tooltip", LoadSkin)
