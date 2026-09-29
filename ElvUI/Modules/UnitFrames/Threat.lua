-- Threat display: real ElvUI's `threatStyle` (Elements/Threat.lua).
--
-- The 1.12 client has no threat API (no UnitThreatSituation), so the only
-- state is LibBanzai-1.0's "has aggro": a hostile unit that a group member
-- targets is itself targeting this unit. It is shown the way real ElvUI
-- shows threat status 3 (securely tanking), in that status' red. A unit is
-- looked up by name, so a friendly target / target-of-target frame shows
-- the aggro of the group member it points at; a unit outside the group
-- (any hostile unit) never has aggro. A mob that nobody in the group
-- targets is not seen.
--
-- Styles, as real ElvUI draws them:
--   GLOW             the glow texture 3px around the whole frame;
--   BORDERS          the frame's border (and the info panel's, when shown);
--   HEALTHBORDER     a 1px line around the health bar;
--   INFOPANELBORDER  the info panel's border, when the panel is shown;
--   ICON<point>      an 8px square at that point of the health bar;
--   NONE             nothing.
--
-- UF:UpdateFrame calls UF:UpdateThreat on every poll pass. Parts are built
-- on first use and every part is hidden on its own: on Unreal Azeroth a
-- parent's Hide does not hide its children.

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

local Banzai = LibStub("LibBanzai-1.0", true)
local LSM = LibStub("LibSharedMedia-3.0", true)

local WHITE = "Interface\\Buttons\\WHITE8x8"
local GLOW_TEXTURE = "Interface\\AddOns\\ElvUI\\Media\\Textures\\glowTex"
local GLOW_SIZE = 3
local ICON_SIZE = 8
-- GetThreatStatusColor(3) of later clients.
local AGGRO_R, AGGRO_G, AGGRO_B = 1, 0, 0

local ICON_POINTS = {
	ICONTOPLEFT = "TOPLEFT",
	ICONTOPRIGHT = "TOPRIGHT",
	ICONBOTTOMLEFT = "BOTTOMLEFT",
	ICONBOTTOMRIGHT = "BOTTOMRIGHT",
	ICONLEFT = "LEFT",
	ICONRIGHT = "RIGHT",
	ICONTOP = "TOP",
	ICONBOTTOM = "BOTTOM",
}

local function HasAggro(unit)
	if not Banzai then return false end
	local ok, name = pcall(UnitName, unit)
	if not ok or not name then return false end
	return Banzai:GetUnitAggroByUnitName(name) == true
end

local function BorderColor()
	local c = E.db and E.db.general and E.db.general.bordercolor
	if not c then return 0, 0, 0, 1 end
	return c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0, c.a or c[4] or 1
end

local function InfoPanelShown(frame)
	local panel = frame.InfoPanel
	return panel and ElvUI.Compat.bool(panel:IsShown()) and panel or nil
end

local function GetGlow(threat, frame)
	if threat.glow then return threat.glow end
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
	glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
	local edge = (LSM and LSM:Fetch("border", "ElvUI GlowBorder", true)) or GLOW_TEXTURE
	pcall(glow.SetBackdrop, glow, { edgeFile = edge, edgeSize = GLOW_SIZE })
	glow:Hide()
	threat.glow = glow
	return glow
end

local function GetHealthBorder(threat, frame)
	if threat.healthBorder then return threat.healthBorder end
	local border = CreateFrame("Frame", nil, frame.Health)
	border:SetPoint("TOPLEFT", frame.Health, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", frame.Health, "BOTTOMRIGHT", 1, -1)
	pcall(border.SetBackdrop, border, { edgeFile = WHITE, edgeSize = 1 })
	border:Hide()
	threat.healthBorder = border
	return border
end

-- On the health bar's text layer, so it draws above the bar's fill.
local function GetIcon(threat, frame)
	if threat.icon then return threat.icon end
	local parent = frame.Health.textLayer or frame.Health
	local icon = parent:CreateTexture(nil, "OVERLAY")
	icon:SetTexture(WHITE)
	icon:SetWidth(ICON_SIZE)
	icon:SetHeight(ICON_SIZE)
	icon:Hide()
	threat.icon = icon
	return icon
end

-- Undoes whatever the style shown last put on the frame.
local function Clear(threat, frame)
	local style = threat.shown
	if not style then return end
	threat.shown = nil

	if threat.glow then threat.glow:Hide() end
	if threat.healthBorder then threat.healthBorder:Hide() end
	if threat.icon then threat.icon:Hide() end
	if style == "BORDERS" or style == "INFOPANELBORDER" then
		local r, g, b, a = BorderColor()
		if style == "BORDERS" then
			pcall(frame.SetBackdropBorderColor, frame, r, g, b, a)
		end
		if frame.InfoPanel then
			pcall(frame.InfoPanel.SetBackdropBorderColor, frame.InfoPanel, r, g, b, a)
		end
	end
end

local function Show(threat, frame, style)
	if style == "GLOW" then
		local glow = GetGlow(threat, frame)
		pcall(glow.SetBackdropBorderColor, glow, AGGRO_R, AGGRO_G, AGGRO_B, 1)
		glow:Show()
	elseif style == "BORDERS" then
		pcall(frame.SetBackdropBorderColor, frame, AGGRO_R, AGGRO_G, AGGRO_B, 1)
		local panel = InfoPanelShown(frame)
		if panel then pcall(panel.SetBackdropBorderColor, panel, AGGRO_R, AGGRO_G, AGGRO_B, 1) end
	elseif style == "HEALTHBORDER" then
		if not frame.Health then return end
		local border = GetHealthBorder(threat, frame)
		pcall(border.SetBackdropBorderColor, border, AGGRO_R, AGGRO_G, AGGRO_B, 1)
		border:Show()
	elseif style == "INFOPANELBORDER" then
		local panel = InfoPanelShown(frame)
		if not panel then return end
		pcall(panel.SetBackdropBorderColor, panel, AGGRO_R, AGGRO_G, AGGRO_B, 1)
	elseif ICON_POINTS[style] then
		if not frame.Health then return end
		local icon = GetIcon(threat, frame)
		local point = ICON_POINTS[style]
		icon:ClearAllPoints()
		icon:SetPoint(point, frame.Health, point)
		icon:SetVertexColor(AGGRO_R, AGGRO_G, AGGRO_B, 1)
		icon:Show()
	else
		return
	end
	threat.shown = style
end

-- `exists`: the frame's unit exists (the frame is shown for it).
function UF:UpdateThreat(frame, unit, settings, exists)
	local style = settings and settings.threatStyle
	local active = exists and style and style ~= "NONE" and HasAggro(unit)

	local threat = frame.ThreatIndicator
	if not threat then
		if not active then return end
		threat = {}
		frame.ThreatIndicator = threat
	end

	if not active then return Clear(threat, frame) end
	if threat.shown == style then return end
	Clear(threat, frame)
	Show(threat, frame, style)
end
