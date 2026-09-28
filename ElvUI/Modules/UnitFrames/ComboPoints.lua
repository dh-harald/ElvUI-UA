-- Combo point bar on the target frame: real ElvUI's `combobar`
-- (Elements/ComboPoints.lua), without its detached/mover mode.
--
-- Settings: `P.unitframe.units.target.combobar` and
-- `P.unitframe.colors.classResources` (Settings/Profile.lua).
--
-- The two `fill` modes follow real ElvUI's layouts:
--   "fill"   five segments across the bar area at the top of the frame,
--            1px apart; the health bar moves down by the bar's height.
--   "spaced" five separately bordered pips, 4/5 of the bar width, centred
--            on the health bar's top edge; health moves down by half the
--            height.
-- UF:UpdateFrame asks UF:UpdateComboPoints for that offset on every pass, so
-- a bar hidden by `autoHide` (0 points) gives its room back to the health
-- bar, as real ElvUI's ToggleResourceBar does.
--
-- Shown for a Rogue, and for a Druid whose power is energy (Cat Form). Real
-- ElvUI tests GetBonusBarOffset() == 1 for the druid; the power type gives
-- the same answer without depending on the stance bar.

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

local MAX_COMBO_POINTS = 5
-- Fill alpha of a segment the player has not built yet (real ElvUI: 0.2).
local INACTIVE_ALPHA = 0.2
-- Distance between neighbouring segments: 1px in "fill" mode, and in
-- "spaced" mode real ElvUI's 5px plus the two 1px pip borders.
local FILL_GAP = 1
local SPACED_GAP = 7
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- 1.12.1 and UA both take no arguments here. The two-argument form of later
-- clients is only a fallback for a client that rejects the bare call.
local function ReadComboPoints()
	local ok, points = pcall(GetComboPoints)
	if ok and tonumber(points) then return tonumber(points) end
	ok, points = pcall(GetComboPoints, "player", "target")
	return (ok and tonumber(points)) or 0
end

local function CanHaveComboPoints()
	if E.myclass == "ROGUE" then return true end
	if E.myclass == "DRUID" then
		return UF.PowerToken and UF.PowerToken("player") == "ENERGY"
	end
	return false
end

-- A pip is three textures on one frame: a black ring 1px outside the pip
-- (textures may draw past their frame's edge; shown in "spaced" mode only),
-- the classResources background, and the point's own colour on top.
local function CreatePip(parent)
	local pip = CreateFrame("Frame", nil, parent)

	local border = pip:CreateTexture(nil, "BACKGROUND")
	border:SetTexture(WHITE)
	border:SetVertexColor(0, 0, 0, 1)
	border:SetPoint("TOPLEFT", pip, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", 1, -1)
	pip.border = border

	local bg = pip:CreateTexture(nil, "BORDER")
	bg:SetTexture(WHITE)
	bg:SetAllPoints(pip)
	pip.bg = bg

	local fill = pip:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(WHITE)
	fill:SetAllPoints(pip)
	pip.fill = fill

	return pip
end

-- Five levels above the frame: over the health bar (frame + 2), which the
-- "spaced" pips overlap, and under its text layer (health + 10).
function UF:Construct_ComboPoints(frame)
	local bar = CreateFrame("Frame", nil, frame)
	local ok, level = pcall(frame.GetFrameLevel, frame)
	if ok and tonumber(level) then
		pcall(bar.SetFrameLevel, bar, level + 5)
	end

	local i
	for i = 1, MAX_COMBO_POINTS do
		bar[i] = CreatePip(bar)
	end
	bar:Hide()

	-- Makes a new point show at once; the 0.2s unit frame poll still covers
	-- a client that never fires this event.
	pcall(bar.RegisterEvent, bar, "PLAYER_COMBO_POINTS")
	bar:SetScript("OnEvent", function() UF:UpdateFrame(frame) end)

	frame.ComboPoints = bar
	return bar
end

-- Lays out and colours the bar. `barLeft`/`barWidth` are the health bar's
-- horizontal extent, so a portrait keeps its full height beside it.
-- Returns how far the health bar has to move down (0 while hidden).
function UF:UpdateComboPoints(frame, settings, barLeft, barWidth)
	local bar = frame.ComboPoints
	if not bar then return 0 end

	local db = settings.combobar
	local shown = db and db.enable and CanHaveComboPoints()
	local points = 0
	if shown then
		points = ReadComboPoints()
		if points == 0 and db.autoHide then shown = false end
	end
	if not shown then
		bar:Hide()
		return 0
	end

	local height = db.height or 10
	local spaced = db.fill == "spaced"
	local gap, width, offset
	bar:ClearAllPoints()
	if spaced then
		gap = SPACED_GAP
		width = barWidth * (MAX_COMBO_POINTS - 1) / MAX_COMBO_POINTS
		bar:SetPoint("CENTER", frame.Health, "TOP", 0, 0)
		offset = math.floor(height / 2)
	else
		gap = FILL_GAP
		width = barWidth
		bar:SetPoint("TOPLEFT", frame, "TOPLEFT", barLeft, -UF.INSET)
		offset = height + 1
	end
	bar:SetWidth(width)
	bar:SetHeight(height)

	local pipWidth = (width - gap * (MAX_COMBO_POINTS - 1)) / MAX_COMBO_POINTS
	local colors = E.db.unitframe.colors.classResources
	local bg = colors.bgColor
	local i
	for i = 1, MAX_COMBO_POINTS do
		local pip = bar[i]
		pip:ClearAllPoints()
		if i == 1 then
			pip:SetPoint("LEFT", bar, "LEFT", 0, 0)
		else
			pip:SetPoint("LEFT", bar[i - 1], "RIGHT", gap, 0)
		end
		pip:SetWidth(pipWidth)
		pip:SetHeight(height)

		local c = colors.comboPoints[i]
		pip.bg:SetVertexColor(bg.r, bg.g, bg.b, 1)
		pip.fill:SetVertexColor(c.r, c.g, c.b, (i <= points) and 1 or INACTIVE_ALPHA)
		if spaced then pip.border:Show() else pip.border:Hide() end
	end

	bar:Show()
	return offset
end
