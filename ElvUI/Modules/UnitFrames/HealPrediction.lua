-- Heal prediction: the healing still to come on a unit, drawn on its health
-- bar as two segments, the player's own (E.db.unitframe.colors.healPrediction
-- .personal) and everyone else's (.others), real ElvUI's healPrediction keys.
-- They start at the end of the health fill and run outward; the part past the
-- bar's right edge is the overheal, shown up to maxOverflow bar widths beyond it,
-- so a heal on a unit at full health is visible too.
--
-- The amounts come from LibHealComm-1.0 (Libraries\): the heals being cast on
-- the unit (its Heals / GrpHeals tables, the player's own computed from the
-- spell, other players' from the HealComm addon channel) plus the healing still
-- to come from heal-over-time spells on it (getHotHeal). HealComm tracks players
-- by name, so a unit that is not a player (a pet, an NPC) gets no prediction.
-- The bar is redrawn on every unit frame update (UnitFrames.lua polls every
-- 0.2 s and on UNIT_HEALTH), which also follows the HoT ticks.

local E, L, V, P, G = unpack(ElvUI)
local UF = E:GetModule("UnitFrames")

local HealComm = LibStub("LibHealComm-1.0", true)

-- ElvCharacterDB.healPrediction is no longer read; it is dropped from the
-- SavedVariables once they are loaded.
do
	local cleanup = CreateFrame("Frame")
	cleanup:RegisterEvent("PLAYER_ENTERING_WORLD")
	cleanup:SetScript("OnEvent", function()
		if type(ElvCharacterDB) == "table" then ElvCharacterDB.healPrediction = nil end
	end)
end

-- The player's own direct heal on `name`, and everyone's.
local function DirectHeals(name, me)
	local own = 0
	local heals = HealComm.Heals[name]
	if heals and heals[me] then own = heals[me].amount or 0 end
	local grp = HealComm.GrpHeals[me]
	if grp and grp.targets then
		local i
		for i = 1, table.getn(grp.targets) do
			if grp.targets[i] == name then own = own + (grp.amount or 0) end
		end
	end
	return own, HealComm:getHeal(name)
end

-- Own and others' healing still to come on `unit`.
local function IncomingHeals(unit)
	if not HealComm then return 0, 0 end
	local name = UnitName(unit)
	if not name then return 0, 0 end
	local me = UnitName("player")
	local ownDirect, allDirect = DirectHeals(name, me)
	local ownHot = HealComm:getHotHeal(name, me)
	local allHot = HealComm:getHotHeal(name)
	local own = ownDirect + ownHot
	local others = allDirect + allHot - own
	if others < 0 then others = 0 end
	return own, others
end

-- The segments live on their own child frame six levels above the health bar.
-- Relative to Health, an overlay portrait sits at +1 (its model at +2) and
-- the layer that re-draws the health state above it at +5 (the mirrored fill
-- in PortraitUA.lua, the missing-health cover in PortraitLegacy.lua); the
-- bar's text layer is at +10. Anything below +5 is darkened by that layer.
local function CreateSegments(bar)
	local holder = CreateFrame("Frame", nil, bar)
	holder:SetAllPoints(bar)
	local ok, level = pcall(bar.GetFrameLevel, bar)
	if ok and tonumber(level) then
		pcall(holder.SetFrameLevel, holder, level + 6)
	end
	local own = holder:CreateTexture(nil, "ARTWORK")
	own:Hide()
	local others = holder:CreateTexture(nil, "ARTWORK")
	others:Hide()
	bar.healPredictionOwn, bar.healPredictionOthers = own, others
	return own, others
end

-- Places `segment` from `start` for `width`, or hides it.
local function PlaceSegment(segment, bar, start, width, color, texturePath)
	if width < 1 then
		segment:Hide()
		return
	end
	if texturePath then pcall(segment.SetTexture, segment, texturePath) end
	if color then
		segment:SetVertexColor(color.r or 0, color.g or 1, color.b or 0.5, color.a or 0.25)
	end
	segment:ClearAllPoints()
	segment:SetPoint("TOPLEFT", bar, "TOPLEFT", start, 0)
	segment:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", start, 0)
	segment:SetWidth(width)
	segment:Show()
end

function UF:UpdateHealPrediction(frame, unit, dbKey, health, healthMax, dead, texturePath)
	local bar = frame and frame.Health
	if not bar then return end

	local settings = E.db.unitframe.units[dbKey or unit]
	local own, others = 0, 0
	if settings and settings.healPrediction and not dead and healthMax and healthMax > 0 then
		own, others = IncomingHeals(unit)
	end

	if own <= 0 and others <= 0 then
		if bar.healPredictionOwn then
			bar.healPredictionOwn:Hide()
			bar.healPredictionOthers:Hide()
		end
		return
	end
	local ownSegment, othersSegment = bar.healPredictionOwn, bar.healPredictionOthers
	if not ownSegment then ownSegment, othersSegment = CreateSegments(bar) end

	local colors = E.db.unitframe.colors.healPrediction
	local maxOverflow = tonumber(colors and colors.maxOverflow) or 0

	-- From the end of the health fill outward, own heals first, then the
	-- others', past the bar's right edge where they overheal, but no further
	-- than maxOverflow bar widths beyond that edge.
	local width = tonumber(bar:GetWidth()) or 0
	local healthWidth = width * health / healthMax
	if healthWidth > width then healthWidth = width end
	local limit = width * (1 + maxOverflow)

	local ownWidth = width * own / healthMax
	if healthWidth + ownWidth > limit then ownWidth = limit - healthWidth end
	local othersStart = healthWidth + ownWidth
	local othersWidth = width * others / healthMax
	if othersStart + othersWidth > limit then othersWidth = limit - othersStart end

	PlaceSegment(ownSegment, bar, healthWidth, ownWidth, colors and colors.personal, texturePath)
	PlaceSegment(othersSegment, bar, othersStart, othersWidth, colors and colors.others, texturePath)
end
