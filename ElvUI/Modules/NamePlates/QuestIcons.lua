local E, L, V, P, G = unpack(ElvUI)
local NP = E:GetModule("NamePlates")

-- Quest icons -- retail ElvUI's nameplate quest objective markers
-- (Game/Shared/Modules/Nameplates/Plugins/QuestIcons.lua): a skull for a
-- unit the player still has to kill and a yellow "!" for a unit that drops
-- an item the player still has to collect, each with the remaining count
-- when more than one is left.
--
-- Retail reads the quest lines the client adds to a unit's tooltip; the
-- 1.12.1 client adds none, so the objectives come from the quest log
-- instead, by unit name (plates carry no unit token):
-- - kill objectives name their unit in the objective text itself
--   (QUEST_MONSTERS_KILLED, "%s slain: %d/%d"), so they need no database;
-- - item objectives name only the item; which units drop it comes from a
--   quest source, an add-on database registered with NP:RegisterQuestSource
--   (QuestSourcePfQuest.lua). Without one, item objectives show nothing.
--
-- Same-named units share their markers. Quests under a collapsed quest log
-- header are not listed by the client and show nothing. When two quests
-- want the same unit, the larger remaining count is shown. Retail's item
-- texture (the quest's usable item) and talk bubble have no source on this
-- client.
--
-- On the side the icons sit, the target arrow moves out past them (see
-- NP:QuestIconReach and PlaceGlows in NamePlates.lua).

local LSM = LibStub("LibSharedMedia-3.0", true)
local Compat = ElvUI.Compat
local getn = Compat.getn

local SKULL = "Interface\\AddOns\\ElvUI\\Media\\Textures\\skullIcon"
local BANG = "Interface\\GossipFrame\\AvailableQuestIcon"

-- The objective types, closest to the plate first, with their icon (retail
-- ElvUI's icon names) and texture.
local ICONS = {
	{ kind = "KILL", icon = "Skull", texture = SKULL },
	{ kind = "ITEM", icon = "Default", texture = BANG },
}

-- [unit name] = { KILL = remaining, ITEM = remaining }
local objectives = {}
NP.questVersion = 0
NP.QuestSources = {}

local function Fetch(mediaType, name)
	return LSM and name and LSM:Fetch(mediaType, name)
end

-- A Lua pattern from a quest objective format string: "%s" captures the
-- name, "%d" a number; positional forms ("%1$s") are accepted but their
-- captures stay in text order.
local function ObjectivePattern(format)
	local pattern = string.gsub(format, "%%%d*%$?s", "\001")
	pattern = string.gsub(pattern, "%%%d*%$?d", "\002")
	pattern = string.gsub(pattern, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	pattern = string.gsub(pattern, "\001", "(.-)")
	pattern = string.gsub(pattern, "\002", "(%%d+)")
	return "^" .. pattern .. "$"
end

local KILL_PATTERN = ObjectivePattern(QUEST_MONSTERS_KILLED or "%s slain: %d/%d")
local ITEM_PATTERN = ObjectivePattern(QUEST_OBJECTS_FOUND or "%s: %d/%d")

-- The name and the remaining count of an objective text, or nil.
local function ParseObjective(text, pattern)
	local _, _, name, have, need = string.find(text, pattern)
	have, need = tonumber(have), tonumber(need)
	if not name or not have or not need or need <= have then return nil end
	return name, need - have
end

local function AddObjective(name, kind, remaining)
	local entry = objectives[name]
	if not entry then
		entry = {}
		objectives[name] = entry
	end
	if not entry[kind] or entry[kind] < remaining then entry[kind] = remaining end
end

-- A quest source: { name = "...", IsAvailable = function(self) ... end,
-- GetItemDroppers = function(self, questTitle, itemName) ... end }, the
-- latter returning a table keyed by the names of the units that drop the
-- item (or nil). Every available source is asked, and their answers add up.
function NP:RegisterQuestSource(source)
	table.insert(self.QuestSources, source)
	self.questDirty = true
end

local function AddItemObjective(title, itemName, remaining)
	local sources = NP.QuestSources
	local i
	for i = 1, getn(sources) do
		local source = sources[i]
		local ok, available = pcall(source.IsAvailable, source)
		if ok and available then
			local okNames, names = pcall(source.GetItemDroppers, source, title, itemName)
			if okNames and type(names) == "table" then
				local unitName
				for unitName in pairs(names) do
					AddObjective(unitName, "ITEM", remaining)
				end
			end
		end
	end
end

-- Rebuilds the unit name table from the quest log; the plates pick the new
-- version up on their next update.
function NP:BuildQuestObjectives()
	self.questDirty = nil
	Compat.wipe(objectives)
	local count = GetNumQuestLogEntries() or 0
	local index
	for index = 1, count do
		local title, _, _, isHeader = GetQuestLogTitle(index)
		if title and not Compat.bool(isHeader) then
			local boards = GetNumQuestLeaderBoards(index) or 0
			local j
			for j = 1, boards do
				local text, kind, finished = GetQuestLogLeaderBoard(j, index)
				-- Unreal Azeroth reports item objectives as "Item" (kills as
				-- "monster"); the 1.12.1 client uses lower case for both.
				kind = type(kind) == "string" and string.lower(kind) or kind
				if text and not Compat.bool(finished) then
					if kind == "monster" then
						local name, remaining = ParseObjective(text, KILL_PATTERN)
						if name then AddObjective(name, "KILL", remaining) end
					elseif kind == "item" then
						local name, remaining = ParseObjective(text, ITEM_PATTERN)
						if name then AddItemObjective(title, name, remaining) end
					end
				end
			end
		end
	end
	self.questVersion = self.questVersion + 1
end

function NP:QUEST_LOG_UPDATE()
	self.questDirty = true
end

-- One icon: its own frame, filled by the texture (Unreal Azeroth does not
-- draw the part of a texture past its parent frame's right or bottom edge),
-- with the count on it.
local function ConstructIcon(element, texture)
	local icon = CreateFrame("Frame", nil, element)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints(icon)
	icon.texture:SetTexture(texture)
	icon.Text = icon:CreateFontString(nil, "OVERLAY")
	icon:Hide()
	return icon
end

function NP:ConstructQuestIcons(frame)
	local element = CreateFrame("Frame", nil, frame)
	element.icons = {}
	local i
	for i = 1, getn(ICONS) do
		local icon = ConstructIcon(element, ICONS[i].texture)
		element[ICONS[i].icon] = icon
		element.icons[i] = icon
	end
	element:Hide()
	frame.QuestIcons = element
end

local function QuestDB(frame)
	local unitDB = NP.db.units[frame.UnitType]
	local db = unitDB and unitDB.questIcon
	if db and db.enable then return db end
	return nil
end

-- Horizontal position of a point on a box `size` wide, from its left edge.
local function PointX(point, size)
	if string.find(point, "RIGHT") then return size end
	if string.find(point, "LEFT") then return 0 end
	return size / 2
end

-- Real ElvUI's Update_QuestIcons: the element `size` square, its inner edge
-- on the plate's `position` side; the icons are laid out in NP:UpdateQuestIcons.
-- The plate is the health bar, or the name on a plate without one.
function NP:ConfigureQuestIcons(frame)
	local element = frame.QuestIcons
	element.key = nil
	local db = QuestDB(frame)
	if not db then
		element:Hide()
		self:UpdateQuestIcons(frame)
		return
	end
	local anchor = frame.healthShown and frame.HealthBar or frame.Name
	local position = db.position or "RIGHT"
	element:ClearAllPoints()
	element:SetPoint(E.InversePoints[position] or "LEFT", anchor, position, db.xOffset or 0, db.yOffset or 0)
	element:SetWidth(db.size)
	element:SetHeight(db.size)
	local font = Fetch("font", db.font)
	local i
	for i = 1, getn(element.icons) do
		local icon = element.icons[i]
		icon:SetWidth(db.size)
		icon:SetHeight(db.size)
		icon.texture:SetAlpha(db.hideIcon and 0 or 1)
		E:FontTemplate(icon.Text, font, db.fontSize, db.fontOutline)
		-- White, as in real ElvUI; a new font string here starts out yellow.
		icon.Text:SetTextColor(1, 1, 1)
		icon.Text:SetJustifyH("CENTER")
		icon.Text:ClearAllPoints()
		icon.Text:SetPoint("CENTER", icon, db.textPosition or "BOTTOMRIGHT", db.textXOffset or 0, db.textYOffset or 0)
	end
	element:Show()
	self:UpdateQuestIcons(frame)
end

-- How far past the health bar's edge on `side` ("LEFT" or "RIGHT") the shown
-- quest icons and the outer one's count reach; 0 when none sit there.
local function Reach(frame, db, shown, outer)
	local position = db.position or "RIGHT"
	if shown == 0 or not frame.healthShown or (position ~= "LEFT" and position ~= "RIGHT") then
		return nil, 0
	end
	local size, spacing = db.size, db.spacing or 0
	local span = (shown - 1) * (size + spacing) + size
	local overhang = 0
	local text = outer.Text
	if text:GetText() and text:GetText() ~= "" then
		local ok, width = pcall(text.GetWidth, text)
		if not ok or type(width) ~= "number" then width = 0 end
		local center = PointX(db.textPosition or "BOTTOMRIGHT", size) + (db.textXOffset or 0)
		if position == "RIGHT" then
			overhang = center + width / 2 - size
		else
			overhang = width / 2 - center
		end
		if overhang < 0 then overhang = 0 end
	end
	local offset = db.xOffset or 0
	if position == "LEFT" then offset = -offset end
	local reach = offset + span + overhang
	if reach < 0 then reach = 0 end
	return position, reach
end

-- Real ElvUI's QuestIcons update: one icon per objective type, stacked
-- outwards from the plate `spacing` apart, the count shown above 1.
function NP:UpdateQuestIcons(frame)
	frame.questVersion = self.questVersion
	local element = frame.QuestIcons
	local db = QuestDB(frame)
	local entry = db and objectives[frame.UnitName]
	local key = ""
	if entry then key = (entry.KILL or 0) .. ":" .. (entry.ITEM or 0) end
	if key == element.key then return end
	element.key = key

	local shown, outer = 0, nil
	local i
	for i = 1, getn(element.icons) do
		element.icons[i]:Hide()
		element.icons[i].Text:SetText("")
	end
	if entry then
		local position = db.position or "RIGHT"
		local inner = E.InversePoints[position] or "LEFT"
		for i = 1, getn(ICONS) do
			local remaining = entry[ICONS[i].kind]
			if remaining and remaining > 0 then
				local icon = element.icons[i]
				local offset = shown * ((db.spacing or 0) + db.size)
				if position == "LEFT" then offset = -offset end
				icon:ClearAllPoints()
				icon:SetPoint(inner, element, inner, offset, 0)
				if remaining > 1 then icon.Text:SetText(tostring(remaining)) end
				icon:Show()
				shown = shown + 1
				outer = icon
			end
		end
	end

	local side, reach = nil, 0
	if db then side, reach = Reach(frame, db, shown, outer) end
	if side ~= frame.questSide or reach ~= frame.questReach then
		frame.questSide, frame.questReach = side, reach
		frame.glowKey = false
		self:UpdateGlow(frame)
	end
end

-- The distance the quest icons take up past the health bar's `side` edge,
-- for the target arrow on that side.
function NP:QuestIconReach(frame, side)
	if frame.questSide == side then return frame.questReach or 0 end
	return 0
end

function NP:InitializeQuestIcons()
	self.questDirty = true
	self:RegisterEvent("QUEST_LOG_UPDATE")
end
