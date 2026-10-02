-- Energy / mana regeneration tick on the player's power bar: retail ElvUI
-- Classic's `power.EnergyManaRegen` (its oUF_EnergyManaRegen plugin and
-- UF:Construct_EnergyManaRegen), with the spend detection of pfUI's
-- energytick module.
--
-- A thin spark runs across the power bar:
--   white   time since the last regeneration tick, wrapping every TICK_DELAY
--           seconds (energy always, mana while not full);
--   yellow  after mana was spent, the time left of the five-second rule
--           (no spirit-based mana regeneration), running right to left.
--
-- Retail starts the five-second rule from UNIT_SPELLCAST_SUCCEEDED and
-- GetSpellPowerCost, neither of which exists on 1.12. Here any drop of the
-- player's mana starts it (pfUI), so an enemy mana drain does too. Any rise
-- of the player's power re-syncs the tick clock; a mana potion or Life Tap
-- shifts it until the next real tick puts it right.
--
-- Both clients fire UNIT_MANA/UNIT_ENERGY once per server tick carrying the
-- whole jump (no client-side smoothing); on Unreal Azeroth the ticks arrive
-- about 2.03s apart.
--
-- Setting: `P.unitframe.units.player.power.EnergyManaRegen`
-- (Settings/Profile.lua). Never shown for a Warrior: rage has no tick.

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

-- Average spacing of the server's regeneration ticks (retail's value; the
-- ticks arrive slightly later than every 2 seconds).
local TICK_DELAY = 2.025
local FIVE_SECOND_RULE = 5
local SPARK_WIDTH = 2
local WHITE = "Interface\\Buttons\\WHITE8x8"

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "UNIT_DISPLAYPOWER", "UNIT_MANA", "UNIT_ENERGY",
	"UNIT_MAXMANA", "UNIT_MAXENERGY",
}

local function ReadPower()
	local ok, value = pcall(UnitMana, "player")
	local okMax, maxValue = pcall(UnitManaMax, "player")
	return (ok and tonumber(value)) or 0, (okMax and tonumber(maxValue)) or 0
end

-- Runs while the element is hidden too (events reach hidden frames), so the
-- tick clock is already in sync when the option is switched on.
local function OnPowerEvent(element)
	if event ~= "PLAYER_ENTERING_WORLD" and arg1 ~= "player" then return end

	local token = UF.PowerToken("player")
	local value, maxValue = ReadPower()
	element.maxValue = maxValue
	if event == "UNIT_MAXMANA" or event == "UNIT_MAXENERGY" then return end

	local isTick = event == "UNIT_MANA" or event == "UNIT_ENERGY"
	if not isTick or token ~= element.token or not element.lastValue then
		-- Login, zoning or a shapeshift: the value jumps without a tick.
		element.token = token
		element.lastValue = value
		element.fsrEnd = nil
		return
	end

	local now = GetTime()
	if value > element.lastValue then
		element.lastTick = now
	elseif value < element.lastValue and token == "MANA" then
		element.fsrEnd = now + FIVE_SECOND_RULE
	end
	element.lastValue = value
end

local function OnUpdate(element, power)
	local token = element.token
	local spark = element.spark
	if (token ~= "MANA" and token ~= "ENERGY") or not element.lastTick then
		spark:Hide()
		return
	end

	local now = GetTime()
	local maxValue = element.maxValue or 0
	if token == "MANA" and (element.lastValue or 0) >= maxValue then
		spark:Hide()
		return
	end

	-- Between real ticks (full energy, or a missed event) the clock keeps
	-- its phase, as the server's ticks do.
	if now >= element.lastTick + TICK_DELAY then
		element.lastTick = element.lastTick
			+ math.floor((now - element.lastTick) / TICK_DELAY) * TICK_DELAY
	end

	local progress
	if element.fsrEnd and element.fsrEnd > now then
		progress = (element.fsrEnd - now) / FIVE_SECOND_RULE
		spark:SetVertexColor(1, 1, 0, 1)
	else
		element.fsrEnd = nil
		progress = (now - element.lastTick) / TICK_DELAY
		spark:SetVertexColor(1, 1, 1, 1)
	end

	local width = tonumber(power:GetWidth()) or 0
	local x = width * progress - SPARK_WIDTH / 2
	if x < 0 then x = 0 end
	if x > width - SPARK_WIDTH then x = width - SPARK_WIDTH end
	spark:ClearAllPoints()
	spark:SetPoint("TOPLEFT", power, "TOPLEFT", x, 0)
	spark:SetPoint("BOTTOMLEFT", power, "BOTTOMLEFT", x, 0)
	spark:Show()
end

-- One level above the power bar's fill, under its text layer (power + 10).
function UF:Construct_EnergyManaRegen(frame)
	local power = frame.Power
	if not power then return end

	local element = CreateFrame("Frame", nil, power)
	element:SetAllPoints(power)
	local ok, level = pcall(power.GetFrameLevel, power)
	if ok and tonumber(level) then
		pcall(element.SetFrameLevel, element, level + 1)
	end

	local spark = element:CreateTexture(nil, "OVERLAY")
	spark:SetTexture(WHITE)
	spark:SetWidth(SPARK_WIDTH)
	spark:SetBlendMode("ADD")
	spark:Hide()
	element.spark = spark

	local i
	for i = 1, ElvUI.Compat.getn(EVENTS) do
		pcall(element.RegisterEvent, element, EVENTS[i])
	end
	element:SetScript("OnEvent", function() OnPowerEvent(element) end)
	element:SetScript("OnUpdate", function() OnUpdate(element, power) end)
	element:Hide()

	frame.EnergyManaRegen = element
	return element
end

-- Called from UF:UpdateFrame on every pass, so the option applies live.
function UF:UpdateEnergyManaRegen(frame, settings)
	local element = frame.EnergyManaRegen
	if not element then return end

	local db = settings.power
	if db and db.enable and db.EnergyManaRegen and E.myclass ~= "WARRIOR" then
		if not element.token then
			element.token = UF.PowerToken("player")
			element.lastValue, element.maxValue = ReadPower()
		end
		element:Show()
	else
		element:Hide()
	end
end
