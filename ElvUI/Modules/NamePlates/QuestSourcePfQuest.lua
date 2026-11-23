local E, L, V, P, G = unpack(ElvUI)
local NP = E:GetModule("NamePlates")

-- pfQuest as a quest source for the nameplate quest icons (QuestIcons.lua):
-- which units drop a quest item, from pfQuest's database (shagu/pfQuest,
-- the `pfDB` global). Used only when pfQuest is loaded.
--
-- The item is looked up among the quest's own item objectives (pfDB quest
-- `obj.I`, the quest found by title in pfQuest's own quest log table),
-- else by name over the whole item database. Its droppers are the units of
-- its loot (`U`) and of its reference loot tables (`R`) at or above
-- pfQuest's own minimum drop chance setting (`mindropchance`, percent,
-- default 1), the same units pfQuest marks on its map. Answers are kept
-- for the session: the database does not change.

local cache = {}
local idsByName = {}

local source = { name = "pfQuest" }

function source:IsAvailable()
	return type(pfDB) == "table" and type(pfDB.items) == "table" and type(pfDB.items.data) == "table"
		and type(pfDB.items.loc) == "table" and type(pfDB.units) == "table" and type(pfDB.units.loc) == "table"
end

-- The ids of the items pfQuest's quest `title` asks for under `itemName`.
local function QuestItemIDs(title, itemName)
	local ids = {}
	local log = type(pfQuest) == "table" and pfQuest.questlog
	local quests = type(pfDB.quests) == "table" and pfDB.quests.data
	if type(log) ~= "table" or type(quests) ~= "table" then return ids end
	local questID, data
	for questID, data in pairs(log) do
		local quest = tonumber(questID) and quests[tonumber(questID)]
		local items = type(data) == "table" and data.title == title and type(quest) == "table"
			and type(quest.obj) == "table" and quest.obj.I
		if type(items) == "table" then
			local _, itemID
			for _, itemID in pairs(items) do
				if pfDB.items.loc[itemID] == itemName then table.insert(ids, itemID) end
			end
		end
	end
	return ids
end

-- The ids of every item named `itemName`.
local function ItemIDsByName(itemName)
	local ids = idsByName[itemName]
	if ids then return ids end
	ids = {}
	local itemID, name
	for itemID, name in pairs(pfDB.items.loc) do
		if name == itemName then table.insert(ids, itemID) end
	end
	idsByName[itemName] = ids
	return ids
end

local function AddDroppers(names, itemID, minChance)
	local item = pfDB.items.data[itemID]
	if type(item) ~= "table" then return end
	local units = pfDB.units.loc
	local unit, chance
	if type(item.U) == "table" then
		for unit, chance in pairs(item.U) do
			if chance >= minChance and units[unit] then names[units[unit]] = true end
		end
	end
	local refloot = type(pfDB.refloot) == "table" and pfDB.refloot.data
	if type(item.R) == "table" and type(refloot) == "table" then
		local ref
		for ref, chance in pairs(item.R) do
			local loot = refloot[ref]
			if chance >= minChance and type(loot) == "table" and type(loot.U) == "table" then
				for unit in pairs(loot.U) do
					if units[unit] then names[units[unit]] = true end
				end
			end
		end
	end
end

function source:GetItemDroppers(title, itemName)
	local minChance = tonumber(type(pfQuest_config) == "table" and pfQuest_config.mindropchance) or 1
	local key = title .. "\001" .. itemName .. "\001" .. minChance
	if cache[key] then return cache[key] end
	local ids = QuestItemIDs(title, itemName)
	if ids[1] == nil then ids = ItemIDsByName(itemName) end
	local names = {}
	local i
	for i = 1, ElvUI.Compat.getn(ids) do
		AddDroppers(names, ids[i], minChance)
	end
	cache[key] = names
	return names
end

NP:RegisterQuestSource(source)
