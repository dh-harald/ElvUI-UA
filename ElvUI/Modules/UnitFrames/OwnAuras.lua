-- Exact start times for the auras the player applies, the precision layer
-- of pfUI's libdebuff (Shagu, MIT) that DebuffDurations.lua on its own does
-- not have. That file stamps an aura the first time it is seen, so a
-- re-cast before expiry keeps the old start and another player's copy of
-- the same spell looks like ours. Here the player's own casts are caught
-- when they happen:
--   * wrappers around UseAction / CastSpell / CastSpellByName queue the
--     spell, its rank, the target's name and the duration (rank, combo
--     points and talents applied) BEFORE the cast leaves the client;
--   * SPELLCAST_START confirms a cast-time spell, SPELLCAST_STOP commits it
--     (an instant spell sends SPELLCAST_STOP too, and a cast that fails
--     sends only SPELLCAST_FAILED);
--   * a miss/resist/immune line of the player's own combat log drops a
--     queued cast, or puts back the stamp a just committed cast replaced.
-- A commit writes into UF.debuffStamps (DebuffDurations.lua) with
-- `mine = true`, so the target frame's aura timers use the exact start as
-- well. Only spells with an entry in UF.DebuffDurations are tracked.
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
--   * Duration table and talent names are English only, like
--     DebuffDurations.lua.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local UF = E.UnitFrames

local Compat = ElvUI.Compat
local Deformat = LibStub("LibDeformat-2.0", true)

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
local lastCommit  -- { target, effect, time, previous }

local maxRanks = {}

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
	local ranks = UF.DebuffDurations and UF.DebuffDurations[effect]
	if not ranks then return 0 end
	local duration = rank and ranks[rank]
	if not duration then duration = ranks[0] end
	if not duration then duration = UF:GetDebuffDuration(effect) end
	duration = duration or 0

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
	if not effect then return end
	if not (UF.DebuffDurations and UF.DebuffDurations[effect]) then return end
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
	local stamps = UF.debuffStamps[entry.target]
	if not stamps then
		stamps = {}
		UF.debuffStamps[entry.target] = stamps
	end
	local now = GetTime()
	lastCommit = {
		target = entry.target,
		effect = entry.effect,
		time = now,
		previous = stamps[entry.effect],
	}
	stamps[entry.effect] = { start = now, duration = entry.duration, mine = true }
end

-- Scan tooltip, one for every lookup here: action slots and unit auras.
local scanTip
local function ScanTip()
	if scanTip then return scanTip end
	local ok, tip = pcall(CreateFrame, "GameTooltip", "ElvUIOwnAuraScanTooltip", nil, "GameTooltipTemplate")
	if not ok or not tip then return nil end
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTip = tip
	return tip
end

-- Calls tip[method](tip, a1, a2) and returns the first line's left and
-- right text. The tooltip is hidden again: a filled GameTooltip stays
-- visible on screen otherwise.
local function ScanLine(method, a1, a2)
	local tip = ScanTip()
	if not tip then return nil end
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
			if UF.DebuffDurations[name] then return name end
		end
		local quoted
		for quoted in Compat.gmatch(line, "CastSpellByName%(%s*[\"']([^\"']+)[\"']") do
			local name = StripRank(quoted)
			if UF.DebuffDurations[name] then return name end
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
					local stamps = UF.debuffStamps[lastCommit.target]
					if stamps then stamps[lastCommit.effect] = lastCommit.previous end
					lastCommit = nil
				end
				return
			end
		end
	end
end

-- Target aura names, read through the scan tooltip: 1.12's UnitDebuff and
-- UnitBuff return no name. Hostile targets are read for debuffs, friendly
-- ones for buffs, as real ElvUI's target aura filter does.
local targetAuras = {}
local targetDirty = true
local lastScan = 0

local function ScanTargetAuras()
	targetDirty = false
	lastScan = GetTime()
	local k
	for k in pairs(targetAuras) do targetAuras[k] = nil end
	if not Compat.bool(UnitExists("target")) then return end

	local friendly = Compat.bool(UnitIsFriend("player", "target"))
	local query = friendly and UnitBuff or UnitDebuff
	local method = friendly and "SetUnitBuff" or "SetUnitDebuff"
	local i
	for i = 1, MAX_AURAS do
		local ok, texture = pcall(query, "target", i)
		if not ok or not texture then break end
		local name = ScanLine(method, "target", i)
		if name and name ~= "" then targetAuras[name] = true end
	end
end

function UF:TargetHasAura(effect)
	if targetDirty or GetTime() - lastScan > SCAN_INTERVAL then
		ScanTargetAuras()
	end
	return targetAuras[effect] == true
end

-- Seconds left and total duration of the player's own `effect` on the unit
-- named `unitName`; nil when there is no such stamp or it has run out.
function UF:GetOwnAuraTimeLeft(unitName, effect)
	local stamps = unitName and UF.debuffStamps[unitName]
	local stamp = stamps and stamps[effect]
	if not stamp or not stamp.mine then return nil end
	local left = stamp.start + stamp.duration - GetTime()
	if left <= 0 then return nil end
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
		targetDirty = true
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
		if arg1 == "target" then targetDirty = true end
	elseif event == "PLAYER_TARGET_CHANGED" then
		targetDirty = true
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
