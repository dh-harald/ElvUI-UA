-- Real ElvUI's aura filtering by a `filters.priority` string (retail ElvUI
-- UnitFrames/Elements/Auras.lua: UF:ConvertFilters, UF:CheckFilter,
-- UF:AuraDuration), matching auras by NAME: neither client reports spell
-- IDs, and the lists in E.global.unitframe.aurafilters are keyed by name.
--
-- A priority string is a comma-separated list of aura list names and
-- special filters, each optionally prefixed with "block" or "allow" and then
-- "Friendly:" or "Enemy:" (e.g. "blockNoDuration", "Enemy:CCDebuffs").
-- The entries are tried in order and the first one that matches decides: a
-- "block" entry hides the aura, any other entry shows it, except that an
-- unprefixed list of type "Blacklist" hides it. An aura that no entry
-- matches is hidden. A string with no known entry shows every aura the
-- duration limits let through. The duration limits (`minDuration`,
-- `maxDuration`, 0 = off) apply before the entries; an aura without a known
-- duration passes them.
--
-- Special filters: "Personal" / "NonPersonal" (whether the player applied
-- the aura, as far as the own-cast stamps know it: UnitFrames/OwnAuras.lua,
-- LibVanillaDurations-1.0), "NoDuration", and "Dispellable" /
-- "NotDispellable" (a debuff whose type the player's class can remove,
-- E:IsDispellableByMe; a buff never counts as dispellable, as in retail
-- without Spellsteal). Retail's other special filters need data these
-- clients do not report (caster unit, boss and mount auras) and are left
-- out, so they match nothing.

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

local Compat = ElvUI.Compat
local getn = Compat.getn

local SPECIAL = {
	Personal = true,
	NonPersonal = true,
	NoDuration = true,
	Dispellable = true,
	NotDispellable = true,
}
-- Older spellings retail ElvUI still accepts.
local OLD_NAMES = {
	nonPersonal = "NonPersonal",
	notDispellable = "NotDispellable",
}

-- priority string -> entry list, or false when it has no known entry.
local converted = {}

local function Strip(text, prefix)
	local _, _, rest = string.find(text, "^" .. prefix .. "(.*)$")
	return rest
end

local function Trim(text)
	local _, _, inner = string.find(text, "^%s*(.-)%s*$")
	return inner or text
end

-- Retail's UF:GetFilterNameInfo.
local function NameInfo(token)
	local block = Strip(token, "block")
	local allow = Strip(token, "allow")
	local name = block or allow or token
	local friend = Strip(name, "Friendly:")
	local enemy = Strip(name, "Enemy:")
	return friend or enemy or name, friend ~= nil, enemy ~= nil, block ~= nil, allow ~= nil
end

-- real name, friend, enemy, block, allow of one priority string entry.
function UF:GetFilterNameInfo(token)
	return NameInfo(Trim(token))
end

local function Lists()
	local unitframe = E.global and E.global.unitframe
	return unitframe and unitframe.aurafilters or {}
end

-- The entries of a priority string, or nil when it has none.
function UF:ConvertFilters(priority)
	if type(priority) ~= "string" or priority == "" then return nil end
	local list = converted[priority]
	if list == nil then
		list = {}
		local lists = Lists()
		local token
		for token in Compat.gmatch(priority, "[^,]+") do
			local real, friend, enemy, block, allow = NameInfo(Trim(token))
			local name = OLD_NAMES[real] or real
			if SPECIAL[name] or lists[real] then
				table.insert(list, {
					name = name,
					custom = lists[real] and real or nil,
					friend = friend,
					enemy = enemy,
					block = block,
					allow = allow,
				})
			end
		end
		if getn(list) == 0 then list = false end
		converted[priority] = list
	end
	return list or nil
end

-- Called after a list is added, removed or renamed.
function UF:ClearAuraFilterCache()
	local k
	for k in pairs(converted) do converted[k] = nil end
end

-- noDuration, allowDuration (retail's UF:AuraDuration).
function UF:AuraDuration(filters, duration)
	local noDuration = not duration or duration == 0
	if noDuration then return true, true end
	local maxDuration, minDuration = filters.maxDuration, filters.minDuration
	local allow = duration > 0
		and (not maxDuration or maxDuration == 0 or duration <= maxDuration)
		and (not minDuration or minDuration == 0 or duration >= minDuration)
	return false, allow and true or false
end

-- pass, priority for an aura called `name` against an entry list from
-- UF:ConvertFilters. `isPlayer`: the player applied it; `isFriend`: it is on
-- a friendly unit; `canDispel`: the player can remove it.
function UF:CheckFilter(list, name, isPlayer, isFriend, noDuration, canDispel)
	local lists = Lists()
	local i
	for i = 1, getn(list) do
		local data = list[i]
		if not ((data.friend and not isFriend) or (data.enemy and isFriend)) then
			if data.custom then
				local custom = lists[data.custom]
				local spell = custom and custom.spells and name and custom.spells[name]
				if spell and spell.enable then
					if not data.allow and not data.block then
						return custom.type ~= "Blacklist", spell.priority
					end
					return not data.block, spell.priority
				end
			elseif (data.name == "Personal" and isPlayer)
				or (data.name == "NonPersonal" and not isPlayer)
				or (data.name == "NoDuration" and noDuration)
				or (data.name == "Dispellable" and canDispel)
				or (data.name == "NotDispellable" and not canDispel) then
				return not data.block
			end
		end
	end
	return false
end

-- Whether an aura passes `filters` (a db table with `priority`,
-- `minDuration`, `maxDuration`), and its list priority. `canDispel` may be
-- left out for buffs.
function UF:AuraPasses(filters, name, isPlayer, isFriend, duration, canDispel)
	local noDuration, allowDuration = self:AuraDuration(filters, duration)
	if not allowDuration then return false end
	local list = self:ConvertFilters(filters.priority)
	if not list then return true end
	return self:CheckFilter(list, name, isPlayer, isFriend, noDuration, canDispel)
end
