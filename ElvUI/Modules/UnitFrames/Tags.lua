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
local _G = _G or getfenv()
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

-- Hunter pet tags (retail ElvUI's Classic set). All of them are empty on any
-- unit but the player's own hunter pet (UF.PetHappiness). `happiness:icon` is
-- an icon tag (below); retail's `happiness:discord` is left out, it needs
-- ElvUI's chat emoji textures.
Methods["happiness:full"] = function(unit)
	local happiness = UF.PetHappiness(unit)
	return happiness and _G["PET_HAPPINESS" .. happiness] or ""
end

Methods["happiness:color"] = function(unit)
	local happiness = UF.PetHappiness(unit)
	local c = happiness and E.db.unitframe.colors.happiness[happiness]
	return c and Hex(c.r, c.g, c.b) or ""
end

-- The digit of GetPetLoyalty()'s "(Loyalty Level 6) Best Friend"; a text
-- without one is shown whole.
Methods["loyalty"] = function(unit)
	if not UF.PetHappiness(unit) then return "" end
	local ok, loyalty = pcall(GetPetLoyalty)
	if not ok or type(loyalty) ~= "string" then return "" end
	return (string.gsub(loyalty, ".-(%d).*", "%1"))
end

-- The first food type the pet eats, as retail's tag shows it.
Methods["diet"] = function(unit)
	if not UF.PetHappiness(unit) then return "" end
	local ok, food = pcall(GetPetFoodTypes)
	return (ok and type(food) == "string") and food or ""
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

-- ---------------------------------------------------------------------
-- Icon tags
-- ---------------------------------------------------------------------
-- Retail draws an icon tag as a texture escape inside the text (`|T...|t`),
-- which neither client renders. Here the tag's place in the text becomes a
-- gap of spaces, and a real texture is laid over that gap: the text before
-- the tag is measured (GetStringWidth), and the texture is anchored to the
-- FontString's left edge by that width. Unit frame texts are anchored by a
-- single point, so the FontString is exactly as wide as its text and its
-- left edge is where the text starts, whatever the justification. Only the
-- first icon tag of a text becomes an icon; the icon is as tall as the font.
--
-- An icon tag answers the texture path and its {left, right, top, bottom}
-- crop, or nil to show nothing (the gap is left out too).

local IconTags = {}
UF.IconTags = IconTags

-- Retail's crops of the 128x64 sheet: unhappy, content, happy.
local HAPPINESS_TEXTURE = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local HAPPINESS_COORDS = {
	{ 48 / 128, 72 / 128, 0, 23 / 64 },
	{ 24 / 128, 48 / 128, 0, 23 / 64 },
	{ 0, 24 / 128, 0, 23 / 64 },
}

IconTags["happiness:icon"] = function(unit)
	local happiness = UF.PetHappiness(unit)
	if happiness then
		return HAPPINESS_TEXTURE, HAPPINESS_COORDS[happiness]
	end
end

-- The first icon tag in `formatStr`: its start, end, name, prefix and
-- suffix (`[prefix>tag<suffix]`, see ApplyTags in UnitFrames.lua).
local function FindIconTag(formatStr)
	local pos = 1
	while true do
		local s, e, inner = string.find(formatStr, "%[([^%]]+)%]", pos)
		if not s then return nil end
		local name, prefix, suffix = UF.SplitTag(inner)
		if IconTags[name] then return s, e, name, prefix, suffix end
		pos = e + 1
	end
end

local function StringWidth(fontString, text)
	fontString:SetText(text)
	local ok, width = pcall(fontString.GetStringWidth, fontString)
	return (ok and tonumber(width)) or 0
end

local function FontSize(fontString, fallback)
	local ok, _, size = pcall(fontString.GetFont, fontString)
	size = ok and tonumber(size)
	if size and size > 0 then return size end
	return fallback or 12
end

-- Width of one space in this FontString's font, measured between two
-- letters (a text of spaces alone may be measured as empty), cached per font.
local spaceWidths = {}
local function SpaceWidth(fontString, size)
	local ok, path, _, flags = pcall(fontString.GetFont, fontString)
	local key = tostring(ok and path) .. size .. tostring(ok and flags)
	local width = spaceWidths[key]
	if not width then
		width = StringWidth(fontString, "i i") - StringWidth(fontString, "ii")
		if width <= 0 then width = size * 0.3 end
		spaceWidths[key] = width
	end
	return width
end

-- Sets `fontString` to `formatStr` with `tags` substituted, drawing the
-- first icon tag as a texture. `fontSize` is the size the text was given,
-- used when the font cannot be read back.
function UF:SetTagText(fontString, formatStr, tags, unit, fontSize)
	local icon = fontString.elvTagIcon
	local s, e, name, prefix, suffix, texture, coords
	if formatStr and formatStr ~= "" then
		s, e, name, prefix, suffix = FindIconTag(formatStr)
		if s then
			texture, coords = IconTags[name](unit)
		end
	end

	if not texture then
		if icon then icon:Hide() end
		-- An icon tag with nothing to show resolves to "" like any unknown tag.
		fontString:SetText(UF.ApplyTags(formatStr, tags))
		return
	end

	-- The icon's prefix/suffix go through ApplyTags for their '||' escapes.
	local before = UF.ApplyTags(string.sub(formatStr, 1, s - 1) .. prefix, tags)
	local after = UF.ApplyTags(suffix .. string.sub(formatStr, e + 1), tags)
	local size = FontSize(fontString, fontSize)
	local spaceWidth = SpaceWidth(fontString, size)
	local count = math.ceil(size / spaceWidth)
	local beforeWidth = (before ~= "") and StringWidth(fontString, before) or 0

	fontString:SetText(before .. string.rep(" ", count) .. after)

	if not icon then
		local okParent, parent = pcall(fontString.GetParent, fontString)
		if not okParent or not parent then return end
		icon = parent:CreateTexture(nil, "OVERLAY")
		fontString.elvTagIcon = icon
	end
	icon:SetTexture(texture)
	icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	icon:SetWidth(size)
	icon:SetHeight(size)
	icon:ClearAllPoints()
	icon:SetPoint("LEFT", fontString, "LEFT", beforeWidth + (count * spaceWidth - size) / 2, 0)
	icon:Show()
end

-- Hides a FontString's icon together with it (the texture is not its child).
function UF:HideTagIcon(fontString)
	if fontString.elvTagIcon then
		fontString.elvTagIcon:Hide()
	end
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
	for name in pairs(IconTags) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end
