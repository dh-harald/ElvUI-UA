-- Unit frame tags beyond the ones UF:UpdateFrame fills itself from its own
-- health/power values (health:current, health:current-percent,
-- health:percent, health:deficit, health:max, healthcolor, power:current,
-- power:max, power:percent, powercolor, name, level).
--
-- Real ElvUI renders `text_format` through oUF's tag system; this addon has
-- no oUF, so a text is built by replacing every [tag] from one table per
-- frame update (ApplyTags in UnitFrames.lua). UF:ExtendTags puts a
-- metatable on that table: a tag below is computed only when a text asks
-- for it, then cached for the rest of the update. A tag with no value, or
-- an unknown one, gives "".
--
-- Tag names and results follow ElvUI-vanilla (Modules/UnitFrames/Tags.lua
-- and its oUF), plus the retail names of the same values that a retail
-- profile uses (the `:shortvalue` forms, `classcolor`).

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames
local Compat = ElvUI.Compat

local Methods = {}
UF.TagMethods = Methods

local function Hex(r, g, b)
	return E:RGBToHex(r, g, b)
end

-- Retail's `:shortvalue` tags. Ours already shorten through E:ShortValue,
-- so each is the plain tag under a second name.
local function Alias(name)
	return function(unit, tags)
		return tags[name]
	end
end
Methods["health:current:shortvalue"] = Alias("health:current")
Methods["health:current-percent:shortvalue"] = Alias("health:current-percent")
Methods["health:max:shortvalue"] = Alias("health:max")
Methods["health:deficit:shortvalue"] = Alias("health:deficit")
Methods["power:current:shortvalue"] = Alias("power:current")
Methods["power:max:shortvalue"] = Alias("power:max")

-- A player's class colour, an NPC's reaction colour: the same colour the
-- health bar uses. Retail calls it `classcolor`; `namecolor` is the
-- ElvUI-vanilla name, kept by retail as a deprecated alias.
Methods["classcolor"] = function(unit)
	local r, g, b = UF.UnitColor(unit)
	return Hex(r, g, b)
end
Methods["namecolor"] = Methods["classcolor"]

local function ShortName(length)
	return function(unit, tags)
		return E:ShortenString(tags["name"], length)
	end
end
Methods["name:veryshort"] = ShortName(5)
Methods["name:short"] = ShortName(10)
Methods["name:medium"] = ShortName(15)
Methods["name:long"] = ShortName(20)

local function UnitLevelNumber(unit)
	local ok, level = pcall(UnitLevel, unit)
	return ok and tonumber(level) or nil
end

-- ElvUI-vanilla's colours for the level difference (not the client's quest
-- difficulty colours retail uses). An unknown level (-1) is red. Unlike
-- vanilla, whose test is `level > 1`, a level-1 unit is coloured as well.
Methods["difficultycolor"] = function(unit)
	local level = UnitLevelNumber(unit)
	local playerLevel = UnitLevelNumber("player")
	local r, g, b = 0.69, 0.31, 0.31
	if level and level > 0 and playerLevel then
		local diff = level - playerLevel
		if diff >= 5 then
			r, g, b = 0.69, 0.31, 0.31
		elseif diff >= 3 then
			r, g, b = 0.71, 0.43, 0.27
		elseif diff >= -2 then
			r, g, b = 0.84, 0.75, 0.65
		else
			local greenRange = 0
			if type(GetQuestGreenRange) == "function" then
				local ok, range = pcall(GetQuestGreenRange)
				greenRange = ok and tonumber(range) or 0
			end
			if -diff <= greenRange then
				r, g, b = 0.33, 0.59, 0.33
			else
				r, g, b = 0.55, 0.57, 0.61
			end
		end
	end
	return Hex(r, g, b)
end

-- Empty for a unit of the player's own level, "??" for an unknown one.
Methods["smartlevel"] = function(unit)
	local level = UnitLevelNumber(unit)
	if level and level == UnitLevelNumber("player") then
		return ""
	elseif level and level > 0 then
		return tostring(level)
	end
	return "??"
end

local SHORT_CLASSIFICATION = { rare = "R", rareelite = "R+", elite = "+", worldboss = "B" }

Methods["shortclassification"] = function(unit)
	local ok, classification = pcall(UnitClassification, unit)
	return ok and SHORT_CLASSIFICATION[classification] or ""
end

-- The player's combo points on the target, whatever frame shows the tag
-- (oUF's `cpoints`); empty at 0. The 1.12.1 API takes no arguments, later
-- clients want the units.
Methods["cpoints"] = function()
	local ok, points = pcall(GetComboPoints)
	if not (ok and tonumber(points)) then
		ok, points = pcall(GetComboPoints, "player", "target")
	end
	points = ok and tonumber(points) or 0
	return (points > 0) and tostring(points) or ""
end

-- "PvP" while the unit is flagged. The countdown needs GetPVPTimer
-- (milliseconds left; 301000 or -1 while the flag is not counting down),
-- which only a client that has it gets, and only for the player's own
-- frame: it is the player's timer.
Methods["pvptimer"] = function(unit)
	local okFFA, ffa = pcall(UnitIsPVPFreeForAll, unit)
	local okPvP, pvp = pcall(UnitIsPVP, unit)
	if not ((okFFA and Compat.bool(ffa)) or (okPvP and Compat.bool(pvp))) then
		return ""
	end

	local label = PVP or L["PvP"]
	if unit == "player" and type(GetPVPTimer) == "function" then
		local ok, timer = pcall(GetPVPTimer)
		timer = ok and tonumber(timer)
		if timer and timer >= 0 and timer ~= 301000 then
			local seconds = math.floor(timer / 1000)
			return string.format("%s (%d:%02d)", label, math.floor(seconds / 60), Compat.mod(seconds, 60))
		end
	end
	return label
end

-- A table key no [tag] can reach: the unit the table was built for.
local UNIT_KEY = {}

local TAGS_META = {
	__index = function(tags, name)
		local method = Methods[name]
		if not method then return nil end
		local value = method(rawget(tags, UNIT_KEY), tags) or ""
		rawset(tags, name, value)
		return value
	end,
}

-- Lets `tags` (built by UF:UpdateFrame for `unit`) answer every tag above.
function UF:ExtendTags(tags, unit)
	rawset(tags, UNIT_KEY, unit)
	return setmetatable(tags, TAGS_META)
end

-- The tags UF:UpdateFrame fills itself.
local BASE_TAGS = {
	"health:current", "health:current-percent", "health:percent", "health:deficit",
	"health:max", "healthcolor", "power:current", "power:max", "power:percent",
	"powercolor", "name", "level",
}

-- Every tag name a text_format can use, sorted (the options window lists them).
function UF:GetTagNames()
	local names = {}
	local i
	for i = 1, table.getn(BASE_TAGS) do
		table.insert(names, BASE_TAGS[i])
	end
	local name
	for name in pairs(Methods) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end
