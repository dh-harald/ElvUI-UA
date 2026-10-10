-- Pet action cooldowns, emulated from the combat log.
--
-- Unreal Azeroth reports no pet ability cooldowns: GetPetActionCooldown(i)
-- gives only the pet's 1.5 s global cooldown and GetSpellCooldown(i, "pet")
-- nothing, so the native pet bar and pet spellbook show no ability swipe.
-- What the client does send is a combat-log line whenever the pet uses an
-- ability, autocast included: every ability on CHAT_MSG_SPELL_PET_DAMAGE
-- ("<pet>'s Bite hits ..."), some self buffs (Charge) additionally on
-- CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS.
--
--   * Start: the moment such a line arrives (GetTime()).
--   * Length: read once per spell and rank from the pet action tooltip
--     ("10 sec cooldown"), matched with the client's own localized
--     SPELL_RECAST_TIME_SEC / SPELL_RECAST_TIME_MIN templates, then cached.
--     A spell whose tooltip has no such line has no cooldown.
--   * Matching a line to a slot is locale independent: the line must contain
--     the pet's name, and of the spells currently on the pet bar the one
--     whose name stands nearest to the pet's name wins (the target's name,
--     further away, may contain another spell name: "Zhevra Charger").
--     Occurrences inside the pet's name itself do not count (a pet called
--     "Charger" must not match Charge); on equal distance the longer name
--     wins.
--
-- Timers are kept by spell name, not slot, so rearranging the pet bar keeps
-- them; they are dropped when a pet with another name appears.
--
-- PetActionBar_UpdateCooldowns is replaced: per slot, a native cooldown wins,
-- otherwise the emulated one, otherwise the native global cooldown. The
-- first time the client reports a cooldown longer than the global cooldown
-- (the legacy 1.12.1 client always does), emulation turns itself off for
-- the session and the original function takes over.
--
-- Limits of the source:
--   * A line of another unit that contains both the pet's name and a pet
--     spell name (a mob sharing the pet's name) can start a timer.
--   * A line that repeats during the cooldown (several targets hit, a
--     periodic tick) is ignored unless the running timer is almost over;
--     the "almost over" window lets the next real cast restart a timer whose
--     start lagged slightly behind the server.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local Compat = ElvUI.Compat
local M = E.PetBar

local find, sub, gsub, len = string.find, string.sub, string.gsub, string.len

local NUM_PET_ACTION_SLOTS = _G.NUM_PET_ACTION_SLOTS or 10
local SCAN_TIP = "ElvUIPetCooldownScanTooltip"
local SCAN_LINES = 10

-- A repeated line within this many seconds of a timer's end is taken as a
-- new cast; earlier ones are duplicates of the running cooldown.
local RECAST_WINDOW = 1.5

-- Native pet cooldowns up to this many seconds are the global cooldown.
local NATIVE_MIN_DURATION = 2

local COMBATLOG_EVENTS = {
	"CHAT_MSG_SPELL_PET_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
}

-- spell name -> { start, duration }
local timers = {}
local timerPet
-- "name\rank" -> seconds, or false for "no cooldown"
local durations = {}
local nativeWorks = false
local originalUpdate

-- Lua pattern for one SPELL_RECAST_TIME_* template: the format specifier
-- becomes a number capture, everything else is matched literally.
local function TemplatePattern(template)
	if type(template) ~= "string" then return nil end
	local s, e = find(template, "%%[%d%.]*[gfd]")
	if not s then return nil end
	local function Escape(text)
		return (gsub(text, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
	end
	return Escape(sub(template, 1, s - 1)).."([%d%.,]+)"..Escape(sub(template, e + 1))
end

local recastPatterns
local function RecastPatterns()
	if recastPatterns then return recastPatterns end
	recastPatterns = {}
	local secs = TemplatePattern(_G.SPELL_RECAST_TIME_SEC or "%.3g sec cooldown")
	local mins = TemplatePattern(_G.SPELL_RECAST_TIME_MIN or "%.3g min cooldown")
	if secs then table.insert(recastPatterns, { secs, 1 }) end
	if mins then table.insert(recastPatterns, { mins, 60 }) end
	return recastPatterns
end

local scanTip
local function ScanTip()
	if scanTip then return scanTip end
	local ok, tip = pcall(CreateFrame, "GameTooltip", SCAN_TIP, nil, "GameTooltipTemplate")
	if not ok or not tip then return nil end
	scanTip = tip
	return tip
end

-- Seconds from one tooltip line, or nil.
local function ParseRecast(text)
	if type(text) ~= "string" then return nil end
	local patterns = RecastPatterns()
	local i
	for i = 1, Compat.getn(patterns) do
		local _, _, number = find(text, patterns[i][1])
		if number then
			local value = tonumber((gsub(number, ",", ".")))
			if value then return value * patterns[i][2] end
		end
	end
	return nil
end

-- Only shown font strings count: a hidden one can keep the text of an
-- earlier scan.
local function LineRecast(fontString)
	if not fontString or not Compat.bool(fontString:IsShown()) then return nil end
	return ParseRecast(fontString:GetText())
end

-- Cooldown length of pet bar slot `slot` from its tooltip: seconds, false
-- when the tooltip has no cooldown line, nil when the tooltip could not be
-- built (not cached, tried again on the next cast). The tooltip is hidden
-- again: a filled GameTooltip stays visible otherwise. Hiding drops the
-- owner, and on the 1.12 client an unowned tooltip is not filled by its Set
-- calls, so the owner is set on every scan.
local function ScanDuration(slot)
	local tip = ScanTip()
	if not tip then return nil end
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	tip:ClearLines()
	local ok = pcall(tip.SetPetAction, tip, slot)
	local result
	if ok and _G[SCAN_TIP.."TextLeft1"] and _G[SCAN_TIP.."TextLeft1"]:GetText() then
		result = false
		local i
		for i = 1, SCAN_LINES do
			local left = _G[SCAN_TIP.."TextLeft"..i]
			local right = _G[SCAN_TIP.."TextRight"..i]
			local value = LineRecast(right) or LineRecast(left)
			if value then
				result = value
				break
			end
		end
	end
	pcall(tip.Hide, tip)
	return result
end

local function SpellDuration(slot, name, rank)
	local key = name.."\r"..(rank or "")
	local cached = durations[key]
	if cached ~= nil then return cached end
	local value = ScanDuration(slot)
	if value ~= nil then durations[key] = value end
	return value
end

-- Spell name and rank in a pet bar slot, nil for empty and command/stance
-- slots.
local function SlotSpell(slot)
	local ok, name, rank, _, isToken = pcall(GetPetActionInfo, slot)
	if not ok or type(name) ~= "string" or Compat.bool(isToken) then return nil end
	return name, rank
end

local function ApplySlot(slot)
	local cooldown = _G["PetActionButton"..slot.."Cooldown"]
	if not cooldown then return end

	-- A native cooldown counts only when it is longer than the global
	-- cooldown: Unreal Azeroth reports the pet's 1.5 s global cooldown here,
	-- but not the ability's own cooldown.
	local ok, start, duration, enable = pcall(GetPetActionCooldown, slot)
	if ok and start and start > 0 and duration and duration > NATIVE_MIN_DURATION then
		nativeWorks = true
		pcall(CooldownFrame_SetTimer, cooldown, start, duration, enable)
		return
	end

	local name = SlotSpell(slot)
	-- Applied on every call, not only when it changed: a swipe that other
	-- pet bar updates stopped in the meantime comes back on the next call.
	-- A running emulated cooldown wins over the native global cooldown.
	local timer = name and timers[name]
	if timer and GetTime() < timer.start + timer.duration then
		pcall(CooldownFrame_SetTimer, cooldown, timer.start, timer.duration, 1)
		return
	end

	pcall(CooldownFrame_SetTimer, cooldown, start or 0, duration or 0, enable or 0)
end

local function UpdateCooldowns()
	if nativeWorks then
		if originalUpdate then pcall(originalUpdate) end
		return
	end
	local i
	for i = 1, NUM_PET_ACTION_SLOTS do
		ApplySlot(i)
	end
	if nativeWorks then
		for i in pairs(timers) do timers[i] = nil end
	end
end

local function CheckPet()
	local name = UnitName("pet")
	if name ~= timerPet then
		for k in pairs(timers) do timers[k] = nil end
		timerPet = name
	end
	return name
end

-- Characters between the pet's name (at s..e in the message) and the nearest
-- occurrence of `name` outside it, or nil. The spell sits next to the pet's
-- name in the pet's own lines, the target's name further away, so the nearest
-- spell name is the one the line is about ("Bendo's Bite hits Zhevra
-- Charger." is Bite, not Charge).
local function SpellGap(message, name, s, e)
	local best
	local init = 1
	while true do
		local a, b = find(message, name, init, true)
		if not a then break end
		local gap
		if a > e then
			gap = a - e
		elseif b < s then
			gap = s - b
		end
		if gap and (not best or gap < best) then best = gap end
		init = a + 1
	end
	return best
end

local function OnCombatLog()
	if nativeWorks then return end
	local message = arg1
	if type(message) ~= "string" then return end
	local petName = CheckPet()
	if not petName or petName == "" then return end

	local s, e = find(message, petName, 1, true)
	if not s then return end

	local slot, spell, rank, best
	local i
	for i = 1, NUM_PET_ACTION_SLOTS do
		local name, r = SlotSpell(i)
		local gap = name and SpellGap(message, name, s, e)
		if gap and (not best or gap < best or (gap == best and len(name) > len(spell))) then
			slot, spell, rank, best = i, name, r, gap
		end
	end
	if not slot then return end

	local now = GetTime()
	local timer = timers[spell]
	if timer and now < timer.start + timer.duration - RECAST_WINDOW then return end

	local duration = SpellDuration(slot, spell, rank)
	if not duration or duration <= 0 then return end

	timers[spell] = { start = now, duration = duration }
	ApplySlot(slot)
end

function M:InitializePetCooldowns()
	if self.petCooldownFrame then return end

	if type(_G.PetActionBar_UpdateCooldowns) == "function" then
		originalUpdate = _G.PetActionBar_UpdateCooldowns
	end
	_G.PetActionBar_UpdateCooldowns = UpdateCooldowns

	local frame = CreateFrame("Frame")
	local i
	for i = 1, Compat.getn(COMBATLOG_EVENTS) do
		frame:RegisterEvent(COMBATLOG_EVENTS[i])
	end
	frame:SetScript("OnEvent", OnCombatLog)
	self.petCooldownFrame = frame
end
