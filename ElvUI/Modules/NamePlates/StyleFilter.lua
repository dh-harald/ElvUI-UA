local E, L, V, P, G = unpack(ElvUI)
local NP = E:GetModule("NamePlates")

-- Style filters -- real ElvUI's trigger/action rules for nameplates
-- (ElvUI-vanilla Modules/NamePlates/StyleFilter.lua). A filter lives in
-- `E.global.nameplates.filters`, its on/off switch per profile in
-- `E.db.nameplates.filters[name].triggers.enable`.
--
-- Real ElvUI applies each passing filter's actions to the widgets and undoes
-- them when the filter stops passing. Here the actions of all passing filters
-- merge into one `frame.style` table the plate's elements read while they lay
-- out, so a change of the passing set is an ordinary re-layout. Filters run
-- from the highest priority number down and later ones overwrite earlier
-- ones: priority 1 wins.
--
-- The client reports no plate events, so filters are evaluated on the plate's
-- update loop: at once on any layout-relevant change, otherwise every 0.1 s.
--
-- Trigger sources, all reachable without a unit token:
-- - casts: the combat-log tracker, by caster name, so same-named units share
--   them; whether a cast can be interrupted is unknown, and channels are not
--   reported;
-- - auras: the lists the plate keeps (see UpdateAuras). Only what the plate's
--   own aura filters let through counts, the lists are read while the plate
--   is the target or under the mouse, and a hidden or name-only plate stops
--   reading them, so an aura with no known time is matched from its last read;
-- - instance difficulty does not exist on this client and is not checked.
--
-- A hostile unit's buffs are invisible without Detect Magic.

local Compat = ElvUI.Compat
local getn = Compat.getn

-- Cooldowns up to this long count as the global cooldown. It is 1.5 s, but
-- GetSpellCooldown reports float values slightly above that on Unreal
-- Azeroth.
local GCD = 1.9

NP.StyleFilterList = {}

-- Fills what a stored or imported filter leaves out; real ElvUI's saved
-- filters are sparse.
local function FillDefaults(dest, src)
	local key, value
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dest[key]) ~= "table" then dest[key] = {} end
			FillDefaults(dest[key], value)
		elseif dest[key] == nil then
			dest[key] = value
		end
	end
end

local function ByPriority(a, b)
	if a.priority ~= b.priority then return a.priority > b.priority end
	return a.name < b.name
end

-- Rebuilds the list of enabled filters; NP:ConfigureAll calls this.
function NP:StyleFilterConfigure()
	local list = {}
	local enabled = self.db.filters
	local name, filter
	for name, filter in pairs(E.global.nameplates.filters) do
		FillDefaults(filter, E.StyleFilterDefaults)
		local switch = enabled[name]
		if switch and switch.triggers and switch.triggers.enable then
			table.insert(list, { name = name, priority = filter.triggers.priority })
		end
	end
	table.sort(list, ByPriority)
	self.StyleFilterList = list
end

-- ---------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------

-- Whether `name` is ticked in `names`; nil when nothing is ticked, which
-- leaves the trigger out of the decision.
local function MatchName(names, name)
	local ticked = false
	local entry, value
	for entry, value in pairs(names) do
		if value == true then
			if entry == name then return true end
			ticked = true
		end
	end
	if ticked then return false end
	return nil
end

local function InThreshold(value, max, under, over)
	local perc = 0
	if max > 0 then perc = value / max end
	return (under ~= 0 and under > perc) or (over ~= 0 and over < perc)
end

-- Spellbook index by spell name, the highest rank; GetSpellCooldown takes no
-- names on this client.
local bookIndex = {}

function NP:SPELLS_CHANGED()
	bookIndex = {}
end

local function BookIndex(spell)
	local index = bookIndex[spell]
	if index == nil then
		index = false
		local i = 1
		while i <= 1024 do
			local ok, name = pcall(GetSpellName, i, "spell")
			if not ok or not name then break end
			if name == spell then index = i end
			i = i + 1
		end
		bookIndex[spell] = index
	end
	return index
end

-- Spells set to ONCD pass while on cooldown, OFFCD ones while ready; a spell
-- missing from the spellbook passes neither. nil when no spell is set.
local function CheckCooldowns(names, mustHaveAll)
	local total, count = 0, 0
	local name, value
	for name, value in pairs(names) do
		if value == "ONCD" or value == "OFFCD" then
			total = total + 1
			local index = BookIndex(name)
			if index then
				local start, duration = GetSpellCooldown(index, "spell")
				local cooling = (tonumber(start) or 0) > 0 and (tonumber(duration) or 0) > GCD
				if cooling == (value == "ONCD") then count = count + 1 end
			end
		end
	end
	if total == 0 then return nil end
	return (mustHaveAll and total == count) or (not mustHaveAll and count > 0)
end

local function HasAura(cache, name, minLeft, maxLeft, now)
	local i
	for i = 1, getn(cache) do
		local aura = cache[i]
		local left = aura.expiration and (aura.expiration - now)
		if aura.name == name and (not left or left > 0)
			and (minLeft == 0 or (left and left > minLeft))
			and (maxLeft == 0 or (left and left < maxLeft)) then
			return true
		end
	end
	return false
end

-- Real ElvUI's aura trigger on a plate's kept list; nil when no name is
-- ticked.
local function CheckAuras(names, cache, db)
	local total, count = 0, 0
	local now = GetTime()
	local name, value
	for name, value in pairs(names) do
		if value == true then
			total = total + 1
			if HasAura(cache, name, db.minTimeLeft, db.maxTimeLeft, now) then count = count + 1 end
		end
	end
	if total == 0 then return nil end
	if db.missing then
		if db.mustHaveAll then return total ~= count end
		return count == 0
	end
	if db.mustHaveAll then return total == count end
	return count > 0
end

local function CheckLevel(trigger, level)
	return (trigger.curlevel ~= 0 and trigger.curlevel == level)
		or (trigger.minlevel ~= 0 and trigger.minlevel <= level)
		or (trigger.maxlevel ~= 0 and trigger.maxlevel >= level)
		or (trigger.mylevel and level == UnitLevel("player"))
end

local UNIT_TYPE_KEYS = {
	FRIENDLY_PLAYER = "friendlyPlayer",
	FRIENDLY_NPC = "friendlyNPC",
	ENEMY_PLAYER = "enemyPlayer",
	ENEMY_NPC = "enemyNPC",
}

local function CheckReaction(types, reaction)
	if reaction == 4 then return types.neutral end
	if reaction == 5 then return types.friendly end
	return types.hostile
end

local function CheckRole(role)
	local mine = NP.playerRole
	return (role.tank and mine == "TANK") or (role.healer and mine == "HEALER")
		or (role.damager and mine == "DAMAGER")
end

local function CheckInstance(kinds)
	local ok, _, kind = pcall(IsInInstance)
	return ok and kinds[kind or "none"]
end

-- The triggers that read the plate's unit.
local function CheckUnit(frame, trigger, failed)
	local result = MatchName(trigger.names, frame.UnitName)
	if result ~= nil then failed = not result end

	if not failed and next(trigger.casting.spells) then
		local UF = E.UnitFrames
		local spell = UF and UF:GetCastByName(frame.UnitName)
		result = MatchName(trigger.casting.spells, spell)
		if result ~= nil then failed = not result end
	end

	if not failed and trigger.healthThreshold then
		local value, max
		if trigger.healthUsePlayer then
			value, max = UnitHealth("player"), UnitHealthMax("player")
		else
			value, max = NP:ReadHealth(frame)
		end
		failed = not InThreshold(value, max, trigger.underHealthThreshold, trigger.overHealthThreshold)
	end

	if not failed and (trigger.isTarget or trigger.notTarget) then
		failed = not ((trigger.isTarget and frame.isTarget) or (trigger.notTarget and not frame.isTarget))
	end

	if not failed and trigger.level then
		failed = not CheckLevel(trigger, NP:ReadLevel(frame))
	end

	if not failed and trigger.nameplateType.enable then
		failed = not trigger.nameplateType[UNIT_TYPE_KEYS[frame.UnitType]]
	end

	if not failed and trigger.reactionType.enable then
		failed = not CheckReaction(trigger.reactionType, frame.UnitReaction)
	end

	if not failed and next(trigger.buffs.names) then
		result = CheckAuras(trigger.buffs.names, frame.Buffs.cache, trigger.buffs)
		if result ~= nil then failed = not result end
	end

	if not failed and next(trigger.debuffs.names) then
		result = CheckAuras(trigger.debuffs.names, frame.Debuffs.cache, trigger.debuffs)
		if result ~= nil then failed = not result end
	end

	return failed
end

-- The triggers that read the player and the world.
local function CheckPlayer(trigger, failed)
	if not failed and trigger.powerThreshold then
		failed = not InThreshold(UnitMana("player"), UnitManaMax("player"),
			trigger.underPowerThreshold, trigger.overPowerThreshold)
	end

	if not failed and (trigger.inCombat or trigger.outOfCombat) then
		local inCombat = Compat.bool(UnitAffectingCombat("player"))
		failed = not ((trigger.inCombat and inCombat) or (trigger.outOfCombat and not inCombat))
	end

	local role = trigger.role
	if not failed and (role.tank or role.healer or role.damager) then
		failed = not CheckRole(role)
	end

	local kinds = trigger.instanceType
	if not failed and (kinds.none or kinds.party or kinds.raid or kinds.arena or kinds.pvp) then
		failed = not CheckInstance(kinds)
	end

	if not failed and next(trigger.cooldowns.names) then
		local result = CheckCooldowns(trigger.cooldowns.names, trigger.cooldowns.mustHaveAll)
		if result ~= nil then failed = not result end
	end

	return failed
end

-- `failed` stays nil for a filter with no active trigger, which does not pass.
local function Passes(frame, trigger)
	return CheckPlayer(trigger, CheckUnit(frame, trigger, nil)) == false
end

-- ---------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------
local function MergeActions(style, actions)
	local color = actions.color
	if color.health then style.healthColor = color.healthColor end
	if color.border then style.borderColor = color.borderColor end
	if color.name then style.nameColor = color.nameColor end
	if actions.texture.enable then style.texture = actions.texture.texture end
	if actions.flash.enable then style.flash = actions.flash end
	if actions.scale ~= 1 then style.scale = actions.scale end
	if actions.alpha ~= -1 then style.alpha = actions.alpha / 100 end
	if actions.nameOnly then style.nameOnly = true end
	if actions.hide then style.hide = true end
end

local passed = {}

-- Re-evaluates the filters on a plate; true when `frame.style` changed and
-- the plate needs a new layout.
function NP:UpdateStyle(frame)
	local list = self.StyleFilterList
	local filters = E.global.nameplates.filters
	local count, key = 0, ""
	local i
	for i = 1, getn(list) do
		local filter = filters[list[i].name]
		if filter and Passes(frame, filter.triggers) then
			count = count + 1
			passed[count] = filter.actions
			key = key .. i .. ","
		end
	end
	if key == (frame.styleKey or "") then return false end
	frame.styleKey = key
	local style
	if count > 0 then
		style = {}
		for i = 1, count do MergeActions(style, passed[i]) end
	end
	frame.style = style
	return true
end
