-- Exact start times for the auras the player applies, the cast-hook layer
-- of pfUI's libdebuff (Shagu, MIT). LibVanillaDurations-1.0 on its own
-- stamps a debuff when a scan finds it, so a re-cast before expiry keeps
-- the old start and another player's copy of the same spell looks like
-- ours. Here the player's own casts are caught when they happen:
--   * wrappers around UseAction / CastSpell / CastSpellByName queue the
--     spell, its rank, the target's name and the duration (rank, combo
--     points and talents applied) BEFORE the cast leaves the client;
--   * SPELLCAST_START confirms a cast-time spell, SPELLCAST_STOP commits it
--     (an instant spell sends SPELLCAST_STOP too, and a cast that fails
--     sends only SPELLCAST_FAILED);
--   * a miss/resist/immune line of the player's own combat log drops a
--     queued cast, or puts back the stamp a just committed cast replaced.
-- A commit is kept here (UF:GetOwnAuraTimeLeft, buffs and debuffs alike)
-- and also stamped into LibVanillaDurations-1.0 with `mine`, so the target
-- frame's debuff timers use the exact start as well. The library drops a
-- stamp whose debuff a scan no longer finds, which is also why the own
-- table exists: buffs are never in its scans. Only spells with a duration
-- in the library's table are tracked.
--
-- Limits:
--   * Stamps are keyed by the target's NAME (no GUID on 1.12): same-named
--     units share one timer per spell.
--   * An aura's caster is not visible on 1.12, so "mine" means "the player
--     cast this spell on a unit of this name and it was not resisted";
--     whether the aura is still on the unit must be checked separately
--     (UF:TargetHasAura).
--   * A spell cast by clicking a unit after picking it (spell cursor) is
--     not tracked.
--   * Duration table and talent names are English only.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local UF = E.UnitFrames

local Compat = ElvUI.Compat
local Deformat = LibStub("LibDeformat-2.0", true)
local LVD = LibStub("LibVanillaDurations-1.0", true)

local find = string.find

-- An instant cast that sees no SPELLCAST_STOP within this many seconds did
-- not happen. A cast-time spell is kept until its own end time plus this.
local QUEUE_TTL = 1
-- A miss/resist line this soon after a commit undoes it (projectiles land
-- after SPELLCAST_STOP).
local REVERT_WINDOW = 3
-- Target aura names are re-read at most this often without an event.
local SCAN_INTERVAL = 1
local MAX_AURAS = 16

-- Durations that depend on combo points or talents, after pfUI's
-- libdebuff. `perPoint` seconds per combo point; `talent` looked up by
-- name in the talent tree, `perRank` seconds (or `percent` of the base
-- duration) per point spent.
local MODIFIERS = {
	["Rupture"] = { perPoint = 2 },
	["Kidney Shot"] = { perPoint = 1 },
	["Shadow Word: Pain"] = { talent = "Improved Shadow Word: Pain", perRank = 3 },
	["Frostbolt"] = { talent = "Permafrost", perRank = 1 },
	["Gouge"] = { talent = "Improved Gouge", perRank = 0.5 },
	["Demoralizing Shout"] = { talent = "Booming Voice", percent = 10 },
}

-- The player's own miss/resist/immune lines, CHAT_MSG_SPELL_SELF_DAMAGE.
-- The spell is one of the captures; IMMUNEDAMAGECLASSSELFOTHER has it
-- second, the others first.
local FAIL_TEMPLATES = {
	"SPELLRESISTSELFOTHER", "SPELLMISSSELFOTHER", "SPELLEVADEDSELFOTHER",
	"SPELLDODGEDSELFOTHER", "SPELLPARRIEDSELFOTHER", "SPELLDEFLECTEDSELFOTHER",
	"SPELLREFLECTSELFOTHER", "SPELLLOGABSORBSELFOTHER", "SPELLIMMUNESELFOTHER",
	"IMMUNEDAMAGECLASSSELFOTHER",
}

local queued      -- pressed, not yet started or stopped
local casting     -- confirmed by SPELLCAST_START, waiting for SPELLCAST_STOP
local lastCommit  -- { target, effect, time, previous, libPrevious }

-- ownStamps[unitName][effect] = { start, duration }
local ownStamps = {}
local maxRanks = {}

-- Seconds, or nil for a spell without a known duration.
local function KnownDuration(effect, rank)
	return effect and LVD and LVD:GetDuration(effect, rank)
end

local function RankNumber(text)
	if type(text) ~= "string" then return nil end
	local _, _, n = find(text, "(%d+)")
	return tonumber(n)
end

-- Casting a spell without a rank casts its highest learned rank.
local function MaxKnownRank(name)
	if maxRanks[name] ~= nil then return maxRanks[name] or nil end
	local best = false
	local i = 1
	while i <= 1024 do
		local ok, spell, rankText = pcall(GetSpellName, i, "spell")
		if not ok or not spell then break end
		if spell == name then
			local rank = RankNumber(rankText)
			if rank and (not best or rank > best) then best = rank end
		end
		i = i + 1
	end
	maxRanks[name] = best
	return best or nil
end

local function TalentRank(talentName)
	local okTabs, tabs = pcall(GetNumTalentTabs)
	if not okTabs or not tabs then return 0 end
	local tab
	for tab = 1, tabs do
		local okNum, num = pcall(GetNumTalents, tab)
		local i
		for i = 1, (okNum and num or 0) do
			local ok, name, _, _, _, rank = pcall(GetTalentInfo, tab, i)
			if ok and name == talentName then return tonumber(rank) or 0 end
		end
	end
	return 0
end

local function ComboPoints()
	local ok, points = pcall(GetComboPoints)
	if ok and tonumber(points) then return tonumber(points) end
	ok, points = pcall(GetComboPoints, "player", "target")
	return (ok and tonumber(points)) or 0
end

-- Unknown rank falls back to the table's rank 0 entry, then its highest.
local function Duration(effect, rank)
	local duration = KnownDuration(effect, rank)
	if not duration then return 0 end

	local mod = MODIFIERS[effect]
	if mod then
		if mod.perPoint then
			duration = duration + ComboPoints() * mod.perPoint
		elseif mod.talent then
			local points = TalentRank(mod.talent)
			if mod.percent then
				duration = duration + duration * points * mod.percent / 100
			else
				duration = duration + points * mod.perRank
			end
		end
	end
	return duration
end

local function Queue(effect, rank, onSelf)
	if not KnownDuration(effect) then return end
	rank = rank or MaxKnownRank(effect)
	local duration = Duration(effect, rank)
	if duration <= 0 then return end

	local target
	if onSelf ~= 1 and Compat.bool(UnitExists("target")) then
		target = UnitName("target")
	else
		target = UnitName("player")
	end
	if not target then return end

	queued = { effect = effect, target = target, duration = duration, time = GetTime() }
end

local function Commit(entry)
	local stamps = ownStamps[entry.target]
	if not stamps then
		stamps = {}
		ownStamps[entry.target] = stamps
	end
	local now = GetTime()
	local libPrevious
	if LVD then
		local start, duration, mine, estimated = LVD:GetStamp(entry.target, entry.effect)
		if start then
			libPrevious = { start = start, duration = duration, mine = mine, estimated = estimated }
		end
		LVD:SetStamp(entry.target, entry.effect, now, entry.duration, true)
	end
	lastCommit = {
		target = entry.target,
		effect = entry.effect,
		time = now,
		previous = stamps[entry.effect],
		libPrevious = libPrevious,
	}
	stamps[entry.effect] = { start = now, duration = entry.duration }
end

-- A resisted cast: the own stamp goes back to what it was. The library's
-- stamp is put back only when there was one; a new stamp whose debuff
-- never lands is dropped by the library's next scan.
local function Revert(commit)
	local stamps = ownStamps[commit.target]
	if stamps then stamps[commit.effect] = commit.previous end
	local p = commit.libPrevious
	if LVD and p then
		LVD:SetStamp(commit.target, commit.effect, p.start, p.duration, p.mine, p.estimated)
	end
end

-- Scan tooltip, one for every lookup here: action slots and unit auras.
local scanTip
local function ScanTip()
	if scanTip then return scanTip end
	local ok, tip = pcall(CreateFrame, "GameTooltip", "ElvUIOwnAuraScanTooltip", nil, "GameTooltipTemplate")
	if not ok or not tip then return nil end
	scanTip = tip
	return tip
end

-- Calls tip[method](tip, a1, a2) and returns the first line's left and
-- right text. The tooltip is hidden again: a filled GameTooltip stays
-- visible on screen otherwise. Hiding drops the owner, and on the 1.12
-- client an unowned tooltip is not filled by its Set calls, so the owner
-- is set again on every scan.
local function ScanLine(method, a1, a2)
	local tip = ScanTip()
	if not tip then return nil end
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	tip:ClearLines()
	local ok = pcall(tip[method], tip, a1, a2)
	local left, right
	if ok then
		local l = _G["ElvUIOwnAuraScanTooltipTextLeft1"]
		local r = _G["ElvUIOwnAuraScanTooltipTextRight1"]
		left = l and l:GetText()
		right = r and Compat.bool(r:IsShown()) and r:GetText()
	end
	pcall(tip.Hide, tip)
	return left, right
end

-- Slash commands that cast: the client's own (localized) SLASH_CAST1..n
-- globals, plus the English form.
local castCommands
local function CastCommands()
	if castCommands then return castCommands end
	castCommands = { ["/cast"] = true }
	local i
	for i = 1, 9 do
		local cmd = _G["SLASH_CAST"..i]
		if type(cmd) == "string" then castCommands[string.lower(cmd)] = true end
	end
	return castCommands
end

local function StripRank(name)
	local _, _, base = find(name, "^(.-)%s*%(.*%)$")
	return base or name
end

-- The first spell with a known aura duration that a macro body casts, by
-- `/cast Name` or `CastSpellByName("Name")`. nil when there is none.
local function MacroSpell(body)
	if type(body) ~= "string" then return nil end
	local commands = CastCommands()
	local line
	for line in Compat.gmatch(body, "[^\n]+") do
		local _, _, cmd, rest = find(line, "^%s*(/%S+)%s+(.-)%s*$")
		if cmd and commands[string.lower(cmd)] then
			local name = StripRank(rest)
			if KnownDuration(name) then return name end
		end
		local quoted
		for quoted in Compat.gmatch(line, "CastSpellByName%(%s*[\"']([^\"']+)[\"']") do
			local name = StripRank(quoted)
			if KnownDuration(name) then return name end
		end
	end
	return nil
end

-- Spell name and rank of an action slot; nil for an empty slot. A macro
-- slot gives nil, or with `includeMacros` the spell its body casts (no
-- rank): the macro's name is all the action slot tells, its body comes
-- from the macro list.
function UF:GetActionSpell(slot, includeMacros)
	if not Compat.bool(HasAction(slot)) then return nil end
	local macroName = GetActionText(slot)
	if macroName then
		if not includeMacros then return nil end
		local index = GetMacroIndexByName(macroName)
		if not tonumber(index) or index <= 0 then return nil end
		local _, _, body = GetMacroInfo(index)
		return MacroSpell(body)
	end
	local name, rankText = ScanLine("SetAction", slot)
	if not name or name == "" then return nil end
	return name, RankNumber(rankText)
end

-- A press on cooldown or without mana never leaves the client.
local function CaptureAction(slot, onSelf)
	queued = nil
	local start = GetActionCooldown(slot)
	if (tonumber(start) or 0) > 0 then return end
	local usable, noMana = IsUsableAction(slot)
	if not Compat.bool(usable) or Compat.bool(noMana) then return end
	local name, rank = UF:GetActionSpell(slot)
	Queue(name, rank, onSelf)
end

local function CaptureSpell(id, book)
	queued = nil
	local name, rankText = GetSpellName(id, book)
	Queue(name, RankNumber(rankText))
end

-- "Name(Rank N)" or "Name".
local function CaptureSpellByName(text, onSelf)
	queued = nil
	if type(text) ~= "string" then return end
	local _, _, name, rankText = find(text, "^(.-)%((.*)%)$")
	if not name then name = text end
	Queue(name, RankNumber(rankText), onSelf)
end

-- A cast that ends in a spell cursor goes to whatever is clicked next.
local function DropIfTargeting()
	if queued and Compat.bool(SpellIsTargeting()) then queued = nil end
end

-- Plain global replacement: Unreal Azeroth has no hooksecurefunc. Each
-- wrapper records first and always calls through.
local function InstallCastWrappers()
	local origUseAction = UseAction
	if type(origUseAction) == "function" then
		UseAction = function(slot, checkCursor, onSelf)
			pcall(CaptureAction, slot, onSelf)
			local a, b, c = origUseAction(slot, checkCursor, onSelf)
			pcall(DropIfTargeting)
			return a, b, c
		end
	end

	local origCastSpell = CastSpell
	if type(origCastSpell) == "function" then
		CastSpell = function(id, book)
			pcall(CaptureSpell, id, book)
			local a, b, c = origCastSpell(id, book)
			pcall(DropIfTargeting)
			return a, b, c
		end
	end

	local origCastSpellByName = CastSpellByName
	if type(origCastSpellByName) == "function" then
		CastSpellByName = function(text, onSelf)
			pcall(CaptureSpellByName, text, onSelf)
			local a, b, c = origCastSpellByName(text, onSelf)
			pcall(DropIfTargeting)
			return a, b, c
		end
	end
end

local function OnFailLine(text)
	if not Deformat then return end
	local i
	for i = 1, Compat.getn(FAIL_TEMPLATES) do
		local template = _G[FAIL_TEMPLATES[i]]
		if template then
			local a, b = Deformat(text, template)
			if a then
				local now = GetTime()
				if queued and (a == queued.effect or b == queued.effect) then
					queued = nil
				elseif casting and (a == casting.effect or b == casting.effect) then
					casting = nil
				elseif lastCommit and (a == lastCommit.effect or b == lastCommit.effect)
					and now - lastCommit.time <= REVERT_WINDOW then
					Revert(lastCommit)
					lastCommit = nil
				end
				return
			end
		end
	end
end

-- Target aura names: 1.12's UnitDebuff and UnitBuff return no name.
-- Hostile targets are read for debuffs, friendly ones for buffs, as real
-- ElvUI's target aura filter does. Debuff names come from
-- LibVanillaDurations-1.0 (its scan cache is shared with the target
-- frame); buff names from the scan tooltip here.
local targetBuffs = {}
local buffsDirty = true
local lastScan = 0

local function ScanTargetBuffs()
	buffsDirty = false
	lastScan = GetTime()
	local k
	for k in pairs(targetBuffs) do targetBuffs[k] = nil end
	if not Compat.bool(UnitExists("target")) then return end

	local i
	for i = 1, MAX_AURAS do
		local ok, texture = pcall(UnitBuff, "target", i)
		if not ok or not texture then break end
		local name = ScanLine("SetUnitBuff", "target", i)
		if name and name ~= "" then targetBuffs[name] = true end
	end
end

-- Every debuff slot is checked: on Unreal Azeroth a debuff can follow an
-- empty slot.
local function TargetHasDebuff(effect)
	if not LVD then return false end
	local i
	for i = 1, MAX_AURAS do
		if LVD:GetDebuffName("target", i) == effect then return true end
	end
	return false
end

function UF:TargetHasAura(effect)
	if not Compat.bool(UnitExists("target")) then return false end
	if not Compat.bool(UnitIsFriend("player", "target")) then
		return TargetHasDebuff(effect)
	end
	if buffsDirty or GetTime() - lastScan > SCAN_INTERVAL then
		ScanTargetBuffs()
	end
	return targetBuffs[effect] == true
end

-- Seconds left and total duration of the player's own `effect` on the unit
-- named `unitName`; nil when there is no such stamp or it has run out.
function UF:GetOwnAuraTimeLeft(unitName, effect)
	local stamps = unitName and ownStamps[unitName]
	local stamp = stamps and stamps[effect]
	if not stamp then return nil end
	local left = stamp.start + stamp.duration - GetTime()
	if left <= 0 then
		stamps[effect] = nil
		return nil
	end
	return left, stamp.duration
end

local function OnEvent()
	if event == "SPELLCAST_START" then
		if queued and arg1 == queued.effect then
			casting = queued
			casting.endTime = GetTime() + (tonumber(arg2) or 0) / 1000
		else
			casting = nil
		end
		queued = nil
	elseif event == "SPELLCAST_DELAYED" then
		if casting then casting.endTime = casting.endTime + (tonumber(arg1) or 0) / 1000 end
	elseif event == "SPELLCAST_STOP" then
		local now = GetTime()
		if casting and now <= casting.endTime + QUEUE_TTL then
			Commit(casting)
		elseif queued and now - queued.time <= QUEUE_TTL then
			Commit(queued)
		end
		casting = nil
		queued = nil
		buffsDirty = true
	elseif event == "SPELLCAST_FAILED" then
		-- A failed press while a cast is running belongs to the press, not
		-- to the running cast.
		queued = nil
	elseif event == "SPELLCAST_INTERRUPTED" then
		queued = nil
		casting = nil
	elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
		if type(arg1) == "string" then OnFailLine(arg1) end
	elseif event == "UNIT_AURA" then
		if arg1 == "target" then buffsDirty = true end
	elseif event == "PLAYER_TARGET_CHANGED" then
		buffsDirty = true
	elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
		local k
		for k in pairs(maxRanks) do maxRanks[k] = nil end
	end
end

local EVENTS = {
	"SPELLCAST_START", "SPELLCAST_DELAYED", "SPELLCAST_STOP",
	"SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED", "CHAT_MSG_SPELL_SELF_DAMAGE",
	"UNIT_AURA", "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
}

do
	local events = CreateFrame("Frame")
	local i
	for i = 1, Compat.getn(EVENTS) do
		pcall(events.RegisterEvent, events, EVENTS[i])
	end
	events:SetScript("OnEvent", OnEvent)
	InstallCastWrappers()
end
