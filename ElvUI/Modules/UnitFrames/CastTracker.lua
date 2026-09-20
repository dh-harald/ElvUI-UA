-- Casts of other units, reconstructed from the combat log. The 1.12 API has
-- no UnitCastingInfo and no UNIT_SPELLCAST_* events (both arrived in 2.0.1);
-- SPELLCAST_* only ever describes the player's own cast. What the client does
-- send for everyone else is the localized combat-log line
-- "<caster> begins to cast <spell>." (SPELLCASTOTHERSTART) or
-- "<caster> begins to perform <spell>." (SPELLPERFORMOTHERSTART) on the
-- CHAT_MSG_SPELL_* events. The line carries no duration and no icon, so both
-- come from the spell table in CastSpells\ (pfUI's database); a spell missing
-- from it is not shown rather than shown with an invented duration.
--
-- Method after pfUI's libcast (Shagu, MIT). The templates are matched with
-- LibDeformat-2.0, which also handles locales that number their arguments
-- ("%2$s ... %1$s").
--
-- A cast ends early on the lines listed in BREAK_LINES (an interrupt line,
-- or an interrupting spell from CastSpells\ hitting or landing on the
-- caster); the target bar then shows "Interrupted" for a moment.
--
-- Limits of the source, not bugs:
--   * Casts are keyed by the caster's NAME; the line has no unit id or GUID.
--     Several nearby units sharing one name (mobs of the same kind) cannot be
--     told apart, so the target's bar may show a same-named neighbour's cast,
--     and interrupting one of them ends the bar whichever one it showed.
--   * Channels of other units print no start line and are not tracked.
--   * The player's own casts use SPELLCAST_* (the player castbar), not this.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local UF = E.UnitFrames

local Deformat = LibStub("LibDeformat-2.0", true)

-- caster name -> { spell, startTime, endTime, icon }, times in GetTime()
-- seconds. Entries are dropped once they end.
local casts = {}

-- The events that carry the start lines, as registered by pfUI's libcast.
local COMBATLOG_EVENTS = {
	"CHAT_MSG_SPELL_SELF_DAMAGE",
	"CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
	"CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
	"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS",
	"CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
	"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
	"CHAT_MSG_SPELL_PARTY_DAMAGE",
	"CHAT_MSG_SPELL_PARTY_BUFF",
	"CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS",
	"CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
}

local function PurgeEnded(now)
	local name, cast
	for name, cast in pairs(casts) do
		if cast.endTime <= now then casts[name] = nil end
	end
end

local function AddCast(caster, spell)
	if not caster or not spell then return end
	local info = UF.castSpells and UF.castSpells[spell]
	if not info or not info.t then return end

	local now = GetTime()
	PurgeEnded(now)
	casts[caster] = {
		spell = spell,
		startTime = now,
		endTime = now + info.t / 1000,
		icon = info.icon and ("Interface\\Icons\\"..info.icon) or nil,
	}

	if caster == UnitName("target") then UF:UpdateTargetCastbar() end
end

-- Ends `caster`'s cast early. `spell` is what hit or landed on it; nil
-- means an explicit interrupt line, which always ends the cast.
local function BreakCast(caster, spell)
	if not caster or not casts[caster] then return end
	if spell and not (UF.castInterrupts and UF.castInterrupts[spell]) then return end

	casts[caster] = nil
	if caster == UnitName("target") then UF:InterruptTargetCastbar() end
end

local function Pick(index, a, b, c)
	if index == 1 then return a elseif index == 2 then return b end
	return c
end

-- Lines that end a cast before its time, as matched by pfUI's libcast:
-- the caster gains or is afflicted by an interrupting effect, is hit by an
-- interrupting spell (own or anyone's, normal or crit), or an explicit
-- "interrupt" line names it. Each entry: template global, capture index of
-- the caster, capture index of the spell (nil = explicit interrupt).
local BREAK_LINES = {
	{"AURAADDEDOTHERHELPFUL", 1, 2},    -- %s gains %s.
	{"AURAADDEDOTHERHARMFUL", 1, 2},    -- %s is afflicted by %s.
	{"SPELLLOGSELFOTHER", 2, 1},        -- Your %s hits %s for %d.
	{"SPELLLOGCRITSELFOTHER", 2, 1},    -- Your %s crits %s for %d.
	{"SPELLLOGOTHEROTHER", 3, 2},       -- %s's %s hits %s for %d.
	{"SPELLLOGCRITOTHEROTHER", 3, 2},   -- %s's %s crits %s for %d.
	{"SPELLINTERRUPTSELFOTHER", 1},     -- You interrupt %s's %s.
	{"SPELLINTERRUPTOTHEROTHER", 2},    -- %s interrupts %s's %s.
}

-- Every template is tried, not just the first match: "%s gains %s." also
-- matches lines of other shapes, and must not hide a later, exact one.
local function MatchBreakLine(message)
	local i
	for i = 1, table.getn(BREAK_LINES) do
		local line = BREAK_LINES[i]
		local template = _G[line[1]]
		local a, b, c
		if template then a, b, c = Deformat(message, template) end
		if a then
			BreakCast(Pick(line[2], a, b, c), line[3] and Pick(line[3], a, b, c))
		end
	end
end

local function OnCombatLog()
	local message = arg1
	if type(message) ~= "string" then return end

	local caster, spell
	if SPELLCASTOTHERSTART then
		caster, spell = Deformat(message, SPELLCASTOTHERSTART)
	end
	if not caster and SPELLPERFORMOTHERSTART then
		caster, spell = Deformat(message, SPELLPERFORMOTHERSTART)
	end
	if caster then
		AddCast(caster, spell)
		return
	end

	-- Nothing to break while no cast is tracked; skips the eight template
	-- matches on most combat-log traffic.
	if next(casts) then MatchBreakLine(message) end
end

-- The cast `unit` is in the middle of, as far as the combat log told:
-- spell, startTime, endTime (GetTime() seconds), icon path or nil.
function UF:GetUnitCast(unit)
	local name = UnitName(unit)
	local cast = name and casts[name]
	if not cast then return nil end

	if cast.endTime <= GetTime() or UnitIsDeadOrGhost(unit) then
		casts[name] = nil
		return nil
	end
	return cast.spell, cast.startTime, cast.endTime, cast.icon
end

-- Plain frames rather than the module's AceEvent registrations: UF already
-- owns a PLAYER_TARGET_CHANGED handler there, and AceEvent keeps one handler
-- per event and object. One frame per handler, so neither needs the `event`
-- global to tell the events apart.
function UF:InitializeCastTracker()
	if self.castTrackerFrame or not Deformat then return end

	local combatLog = CreateFrame("Frame")
	local i
	for i = 1, table.getn(COMBATLOG_EVENTS) do
		combatLog:RegisterEvent(COMBATLOG_EVENTS[i])
	end
	combatLog:SetScript("OnEvent", OnCombatLog)

	local targetChanged = CreateFrame("Frame")
	targetChanged:RegisterEvent("PLAYER_TARGET_CHANGED")
	targetChanged:SetScript("OnEvent", function() UF:UpdateTargetCastbar() end)

	self.castTrackerFrame = combatLog
end
