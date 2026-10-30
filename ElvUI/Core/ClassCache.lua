local E, L, V, P, G = unpack(ElvUI)
local CC = E:NewModule("ClassCache", "AceEvent-3.0")

-- Class Cache -- real ElvUI's (ElvUI-vanilla Core/ClassCache.lua): player
-- name -> class file name ("WARRIOR"), for displays that know a name but no
-- unit, such as the nameplates. Gated by `E.private.general.classCache`;
-- stored in `E.global.classCache[realm]` while
-- `E.db.general.classCacheStoreInDB` is on, otherwise kept for the session.
--
-- Sources: the target and mouseover, party and raid members (UnitClass,
-- already a file name), the friends list, the guild roster, the
-- battleground score board and /who results (the player's own and the
-- lookups below). All but the first give the class as display text, turned
-- into the file name by ClassFromText.
--
-- `classCacheRequestInfo` (real ElvUI's LibWho option): a chat sender not
-- in the cache is looked up with a silent /who (Core/Who.lua); a name with
-- no answer is not asked again for NOT_FOUND_RETRY seconds.

local Compat = ElvUI.Compat

local NOT_FOUND_RETRY = 600

local sessionCache = {}
local notFound = {}   -- name -> GetTime() before which it is not asked again
local requested = {}  -- names with a lookup waiting for its answer

-- Localized class name -> file name, learned from UnitClass (which returns
-- both) on every unit cached; this is what makes the display-text sources
-- work on a non-English client. 1.12 has no LOCALIZED_CLASS_NAMES table.
local classTokens = {}

local function ClassFromText(text)
	if type(text) ~= "string" then return nil end
	if classTokens[text] then return classTokens[text] end
	local class = string.upper(text)
	if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then return class end
	return nil
end

function CC:GetCacheTable()
	if E.db.general.classCacheStoreInDB then
		return E.global.classCache
	end
	return sessionCache
end

function CC:GetClassByName(name)
	if not name or name == "" or not E.private.general.classCache then return nil end
	local realm = self:GetCacheTable()[E.myrealm]
	return realm and realm[name]
end

function CC:CachePlayer(name, class)
	if not name or name == "" or not class then return end
	local cache = self:GetCacheTable()
	cache[E.myrealm] = cache[E.myrealm] or {}
	cache[E.myrealm][name] = class
end

local function CacheUnit(unit)
	if not Compat.bool(UnitExists(unit)) or not Compat.bool(UnitIsPlayer(unit)) then return end
	local localized, class = UnitClass(unit)
	if class then
		if localized then classTokens[localized] = class end
		CC:CachePlayer(UnitName(unit), class)
	end
end

-- Every row of the last /who answer, from the Social frame's list, a chat
-- /who or a Core/Who.lua lookup alike.
function CC:CacheWhoResults()
	local i
	for i = 1, (GetNumWhoResults() or 0) do
		local name, _, _, _, class = GetWhoInfo(i)
		self:CachePlayer(name, ClassFromText(class))
	end
end

function CC:WHO_LIST_UPDATE()
	self:CacheWhoResults()
end

-- Looks up a name the cache does not know yet, when `classCacheRequestInfo`
-- is on. The answer only lands in the cache: whatever was already drawn
-- with the name stays as it was.
function CC:RequestClass(name)
	if not name or name == "" or not E.private.general.classCache then return end
	if not E.db.general.classCacheRequestInfo or not E.Who then return end
	if self:GetClassByName(name) then return end
	if notFound[name] and GetTime() < notFound[name] then return end
	if requested[name] then return end
	requested[name] = true
	E.Who:Query(name, function(result)
		requested[name] = nil
		local class = result and ClassFromText(result.class)
		if class then
			CC:CachePlayer(name, class)
		else
			notFound[name] = GetTime() + NOT_FOUND_RETRY
		end
	end)
end

function CC:PLAYER_TARGET_CHANGED()
	CacheUnit("target")
end

function CC:UPDATE_MOUSEOVER_UNIT()
	CacheUnit("mouseover")
end

function CC:PARTY_MEMBERS_CHANGED()
	local i
	for i = 1, GetNumPartyMembers() do
		CacheUnit("party" .. i)
	end
end

function CC:RAID_ROSTER_UPDATE()
	local i
	for i = 1, GetNumRaidMembers() do
		CacheUnit("raid" .. i)
	end
end

function CC:FRIENDLIST_UPDATE()
	local i
	for i = 1, GetNumFriends() do
		local name, _, class = GetFriendInfo(i)
		self:CachePlayer(name, ClassFromText(class))
	end
end

function CC:GUILD_ROSTER_UPDATE()
	if not Compat.bool(IsInGuild()) then return end
	local i
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, class = GetGuildRosterInfo(i)
		self:CachePlayer(name, ClassFromText(class))
	end
end

function CC:UPDATE_BATTLEFIELD_SCORE()
	local i
	for i = 1, (GetNumBattlefieldScores() or 0) do
		local name, _, _, _, _, _, _, _, class = GetBattlefieldScore(i)
		self:CachePlayer(name, ClassFromText(class))
	end
end

local EVENTS = {
	"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PARTY_MEMBERS_CHANGED",
	"RAID_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE",
	"UPDATE_BATTLEFIELD_SCORE", "WHO_LIST_UPDATE",
}

-- Event by event: UnregisterAllEvents does not work on Unreal Azeroth.
function CC:ToggleModule()
	local enable = E.private.general.classCache
	local i
	for i = 1, Compat.getn(EVENTS) do
		if enable then
			self:RegisterEvent(EVENTS[i])
		else
			self:UnregisterEvent(EVENTS[i])
		end
	end
	if enable then
		self:CachePlayer(E.myname, E.myclass)
		CacheUnit("player")
		self:PARTY_MEMBERS_CHANGED()
		self:RAID_ROSTER_UPDATE()
	end
end

-- Moves the entries into the store the setting now selects.
function CC:SwitchCacheType()
	local from = E.db.general.classCacheStoreInDB and sessionCache or E.global.classCache
	local to = self:GetCacheTable()
	local realm, names, name, class
	for realm, names in pairs(from) do
		to[realm] = to[realm] or {}
		for name, class in pairs(names) do
			to[realm][name] = class
		end
	end
end

function CC:GetCacheSize(global)
	local cache = global and E.global.classCache or sessionCache
	local size = 0
	local realm, names
	for realm, names in pairs(cache) do
		local name
		for name in pairs(names) do size = size + 1 end
	end
	return size
end

function CC:WipeCache(global)
	local cache = global and E.global.classCache or sessionCache
	local realm
	for realm in pairs(cache) do cache[realm] = nil end
	if global then
		E:Print(L["Class DB cache wiped."])
	else
		E:Print(L["Class session cache wiped."])
	end
	if E.private.general.classCache then self:CachePlayer(E.myname, E.myclass) end
end

function CC:Initialize()
	E.ClassCache = self
	self:ToggleModule()
end

E:RegisterInitialModule(CC:GetName(), function() CC:Initialize() end)
