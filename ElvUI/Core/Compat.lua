-- ElvUI.Compat: Lua 5.0 / 5.1 shim layer.
--
-- WoW 1.12.1 runs Lua 5.0. Unreal Azeroth (UA) runs Lua 5.1. Every helper
-- below prefers the native 5.1 function when it exists and only falls back
-- to a 5.0-safe implementation when it's missing. Nothing here touches the
-- global `string`/`table` libraries -- everything lives under ElvUI.Compat,
-- hung off the addon's own engine table, so we never risk clobbering
-- another addon's environment.
--
-- IMPORTANT -- two bits of Lua 5.1 syntax do not exist in the Lua 5.0
-- parser at all, so using them is a *parse-time* error on the 1.12.1
-- client even in an unreachable/guarded branch. Never write either of
-- these in any file that has to load on both clients:
--
--   1. `...` as an expression (`return ...`, `f(...)`, `select('#', ...)`).
--      Lua 5.0 only allows `...` in a function's parameter list, where it
--      auto-populates the implicit local `arg` table (arg[1].. arg.n).
--      Declare vararg functions as `function(...)` (valid in both), then
--      read `arg` directly. Use Compat.argCount/Compat.argUnpack below
--      instead of `select` or `...`-forwarding.
--
--   2. The `#` length operator. Lua 5.0 has no `#`; use table.getn(t) /
--      string.len(s) (routed through Compat.getn below for tables).
--
-- Grow this file as real breakage turns up during dual-client testing --
-- don't try to pre-empt every possible 5.0/5.1 difference speculatively.

ElvUI = ElvUI or {}
ElvUI.Compat = ElvUI.Compat or {}

local Compat = ElvUI.Compat
local _G = _G or getfenv()

-- Diagnostic only -- don't branch feature code on this, feature-detect the
-- specific function you need instead.
Compat.isLua50 = (string.match == nil)

-- WHICH CLIENT, not which Lua. Feature-detection is still the rule for
-- anything that is a missing/extra FUNCTION -- this flag is only for the
-- handful of places where the SAME working API has to be driven
-- differently on the two clients, and where getting it wrong breaks the
-- OTHER client (so a one-sided workaround can't just be applied
-- everywhere). The known case, confirmed on both clients: mouse-drag
-- capture -- UA needs an expanded hit rect to keep delivering the
-- release, while a real Blizzard client is broken by that same expansion.
--
-- Probe borrowed verbatim from LibConfig-1.0's own `DetectUA`: `GetUECvar`
-- is the Unreal engine's own cvar accessor and exists on no Blizzard
-- client, and 5875 is UA's interface number. Only valid while this addon
-- ships to exactly these two clients (a 3.3.5 client is Lua 5.1 too, but
-- has neither of these two markers, so it would correctly read as
-- "not UA").
Compat.isUA = false
if GetUECvar then
	Compat.isUA = true
elseif type(GetBuildInfo) == "function" then
	local okBuild, _, _, _, tocversion = pcall(GetBuildInfo)
	if okBuild and tonumber(tocversion) == 5875 then
		Compat.isUA = true
	end
end

-- string.match: absent in Lua 5.0, native from 5.1 on.
-- Fallback adapted from LibConfig-1.0's Compat/Lua50.lua (DeepSeek).
if string.match then
	Compat.match = string.match
else
	function Compat.match(str, pattern, index)
		if type(str) ~= "string" then
			error(string.format("bad argument #1 to 'match' (string expected, got %s)", type(str)), 2)
		end

		local results = { string.find(str, pattern, index) }
		local start, finish = results[1], results[2]
		if not start then
			return nil
		end

		if results[3] == nil then
			return string.sub(str, start, finish)
		end

		table.remove(results, 1) -- start
		table.remove(results, 1) -- finish
		return unpack(results)
	end
end

-- string.gmatch: absent in Lua 5.0, which has string.gfind instead
-- (same behavior for the common case).
Compat.gmatch = string.gmatch or string.gfind

-- table.getn/# both work in 5.0 and 5.1 for arrays; table.getn is
-- deprecated (but present under LUA_COMPAT_GETN) in 5.1 and gone in 5.2+.
-- Route through here rather than depending on either directly at call
-- sites. The fallback below deliberately avoids `#` (see note above).
Compat.getn = table.getn or function(t)
	local n = 0
	while t[n + 1] ~= nil do
		n = n + 1
	end
	return n
end

-- select(): cannot be shimmed as a generic vararg-forwarding function on
-- Lua 5.0 (see the vararg note above). Use these against an already
-- captured `arg` table instead of ever writing `select(...)`.
function Compat.argCount(argTable)
	return argTable.n or Compat.getn(argTable)
end

function Compat.argUnpack(argTable, i, j)
	return unpack(argTable, i or 1, j or Compat.argCount(argTable))
end

-- The `%` operator fails to PARSE on this project's Lua 5.0.3 build
-- ("unexpected symbol near '%'"). Same severity class as `#`/`...` above --
-- never write `%` as an operator anywhere in a file loaded on both
-- clients, not even in an unreachable/guarded branch; the 5.0 parser
-- rejects the syntax before any code runs. Real ElvUI-vanilla's own
-- source avoids it the same way (several of its files cache
-- `local mod = math.mod` at the top). math.mod may not exist on 5.1
-- (deprecated there in favor of math.fmod), hence the fallback.
Compat.mod = math.mod or function(a, b)
	return a - math.floor(a / b) * b
end

-- math.modf: present on UA (5.1), MISSING on the real 1.12.1 client -- its
-- Lua 5.0 build ships a trimmed math library (no modf/fmod/huge/cosh/sinh/
-- tanh). ElvUI-vanilla only works there because its !Compatibility addon
-- installs a global polyfill; we ship no such addon, so route every call
-- through here. Truncates toward zero, like the real function: returns the
-- integer part and the signed fractional remainder. Infinities are not
-- special-cased (math.huge does not exist on 1.12.1 either).
Compat.modf = math.modf or function(value)
	value = tonumber(value)
	if type(value) ~= "number" then
		error("bad argument #1 to 'modf' (number expected)", 2)
	end

	local int = value >= 0 and math.floor(value) or math.ceil(value)

	return int, value - int
end

-- Boolean-flag API returns, normalized to a real boolean by VALUE, not by
-- client: nil, false and 0 -> false; anything else -> true.
--
-- The two clients report the same yes/no state in different shapes: the
-- legacy 1.12.1 client returns 1/nil from most flag getters and 1/0 from
-- some (`Button:IsEnabled()` -- measured; FrameXML itself compares
-- `IsEnabled() == 0`), while UA returns true/false. Plain truthiness breaks
-- on the 0 (`not 0` is false in Lua), `== 1` breaks on UA's true, and
-- `== nil` breaks on UA's false.
--
-- ONLY for yes/no flags. Never for:
--   * numbers that are values (counts, indices, levels, scales) -- 0 is a
--     real value there;
--   * tri-state returns where nil and 0 mean different things, e.g.
--     `IsActionInRange` (1 in range, 0 out of range, nil = no range);
--   * strings: `GetCVar` returns "0"/"1", and "0" is truthy -- compare the
--     string instead.
function Compat.bool(value)
	return value ~= nil and value ~= false and value ~= 0
end

-- BetterDate: a Blizzard wrapper around date() added in a later expansion
-- (2.0.1+). Real vanilla 1.12.1 has it natively; missing/erroring on UA.
-- Always uses this own reimplementation rather than the native global on
-- either client -- one code path, nothing to fall back from. Deliberately
-- namespaced under Compat rather than defined as a bare global polyfill --
-- patching missing globals project-wide proved fragile, so only the
-- functions actually consumed (this one and GetInventoryItemDurability
-- below) get a targeted replacement here, never touching the global table.
-- Callers: Compat.BetterDate(fmt, t) — Modules/DataTexts/Time.lua,
-- Modules/Chat/Chat.lua.
function Compat.BetterDate(formatString, timeVal)
	local dateTable = date("*t", timeVal)
	local amString = (dateTable.hour >= 12) and "PM" or "AM"

	formatString = string.gsub(formatString, "^%%p", amString)
	formatString = string.gsub(formatString, "([^%%])%%p", "%1"..amString)

	return date(formatString, timeVal)
end

-- GetInventoryItemDurability: vanilla has no direct API for this on either
-- client. Scans a hidden tooltip's text and pulls the numbers back out of
-- the localized "X / Y" durability line via a pattern derived from the
-- native DURABILITY_TEMPLATE string. See the BetterDate comment above for
-- why this lives here (Compat.GetInventoryItemDurability) instead of as a
-- bare global polyfill. Only caller: Modules/DataTexts/Durability.lua.
local durabilityPattern
local durabilityScanTooltip

local function ScanDurability(slot)
	durabilityScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	durabilityScanTooltip:ClearLines()
	durabilityScanTooltip:SetInventoryItem("player", slot)

	local i
	for i = 4, durabilityScanTooltip:NumLines() do
		local region = _G["ElvUICompat_DurabilityScanTooltipTextLeft"..i]
		local text = region and region:GetText()
		if text then
			local current, maximum
			for current, maximum in Compat.gmatch(text, durabilityPattern) do
				return tonumber(current), tonumber(maximum)
			end
		end
	end
end

-- SetInventoryItem shows the scan tooltip, and with ANCHOR_NONE it stays
-- drawn at the bottom-left screen corner, so it is hidden after every scan.
-- Hiding drops the owner and an unowned tooltip is not filled by its Set
-- calls, hence the SetOwner inside ScanDurability on every call. The scan is
-- pcall'd so the tooltip is hidden even when a Set call errors.
function Compat.GetInventoryItemDurability(slot)
	if not GetInventoryItemTexture("player", slot) then return end

	if not durabilityPattern then
		durabilityPattern = string.gsub(DURABILITY_TEMPLATE, "%%d / %%d", "(%%d+) / (%%d+)")
	end

	if not durabilityScanTooltip then
		local ok
		ok, durabilityScanTooltip = pcall(CreateFrame, "GameTooltip", "ElvUICompat_DurabilityScanTooltip", nil, "ShoppingTooltipTemplate")
		if not ok or not durabilityScanTooltip then
			durabilityScanTooltip = nil
			return
		end
	end

	local ok, current, maximum = pcall(ScanDurability, slot)
	durabilityScanTooltip:Hide()
	if ok then
		return current, maximum
	end
end

-- GetWeaponEnchants: the player's temporary weapon enchants (shaman weapon
-- imbues, rogue poisons, sharpening stones, oils) as buff-like entries. On
-- both clients these are not auras -- UnitBuff/GetPlayerBuff never list
-- them, and GetWeaponEnchantInfo reports only presence, time and charges,
-- with no name or icon. Returns a list, main hand first, of:
--   slot      16 (main hand) or 17 (off hand), for SetInventoryItem
--   texture   the enchanting spell's icon when the enchant is known to
--             ENCHANT_ICONS below, otherwise the weapon's own icon (real
--             ElvUI's Auras module always shows the weapon)
--   isWeaponIcon  true when `texture` is the weapon's icon
--   name      the enchant's name from the weapon tooltip ("Rockbiter 2"),
--             nil when no tooltip line matched
--   timeLeft  seconds remaining, or nil
--   charges   charges remaining (0 for an enchant without charges)
-- An enchant is left out when the player already has a buff of the same
-- name, with or without its trailing rank number, so a client that lists
-- weapon enchants among the buffs itself does not show them twice.
--
-- GetWeaponEnchantInfo's time is in milliseconds (fractional on UA), and its
-- "has" flags are 1/nil on the 1.12 client, hence Compat.bool.
--
-- Tooltip scans are cached, since the Auras module asks ten times a second:
-- the enchant name is re-read only when the weapon changes, when an enchant
-- appears, or when its time or charges jump upwards (a re-application,
-- possibly of a different poison); a buff name only when the buff at that
-- index changes texture.
local ENCHANT_SCAN_TOOLTIP = "ElvUICompat_EnchantScanTooltip"
local WEAPON_SLOTS = { 16, 17 }
-- The weapon tooltip's green enchant line, "<name> (<n> <unit>)".
local ENCHANT_TIME_FORMATS = {
	"ITEM_ENCHANT_TIME_LEFT_SEC",
	"ITEM_ENCHANT_TIME_LEFT_MIN",
	"ITEM_ENCHANT_TIME_LEFT_HOURS",
	"ITEM_ENCHANT_TIME_LEFT_HOURS_P1",
	"ITEM_ENCHANT_TIME_LEFT_DAYS",
	"ITEM_ENCHANT_TIME_LEFT_DAYS_P1",
}
local MAX_PLAYER_BUFFS = 32

-- Icon of the spell behind an enchant, keyed by the enchant's name as the
-- weapon tooltip shows it with the rank stripped ("Rockbiter 2" ->
-- "Rockbiter", "Instant Poison III" -> "Instant Poison"). Icons from pfUI's
-- spell table (env/locales_enUS.lua). English names only: on another client
-- language, and for enchants not listed (sharpening stones, weightstones,
-- oils), the entry keeps the weapon's icon.
local ENCHANT_ICONS = {
	["Rockbiter"] = "Spell_Nature_RockBiter",
	["Flametongue"] = "Spell_Fire_FlameTounge",
	["Frostbrand"] = "Spell_Frost_FrostBrand",
	["Windfury"] = "Spell_Nature_Cyclone",
	["Windfury Totem"] = "Spell_Nature_Windfury",
	["Flametongue Totem"] = "Spell_Nature_GuardianWard",
	["Instant Poison"] = "Ability_Poisons",
	["Deadly Poison"] = "Ability_Rogue_DualWeild",
	["Crippling Poison"] = "Ability_PoisonSting",
	["Mind-numbing Poison"] = "Spell_Nature_NullifyDisease",
	["Wound Poison"] = "INV_Misc_Herb_16",
}

-- "Rockbiter 2" -> "Rockbiter", "Instant Poison III" -> "Instant Poison".
local function StripRank(name)
	local base = string.gsub(name, "%s+%d+$", "")
	base = string.gsub(base, "%s+[IVX]+$", "")
	return base
end

local function EnchantIcon(name)
	local icon = name and ENCHANT_ICONS[StripRank(name)]
	return icon and ("Interface\\Icons\\"..icon) or nil
end

local enchantScanTooltip
local enchantPatterns
local enchantCache = {}
local buffNameCache = {}

-- "%s (%d min)" -> "^(.+) %(%d+ min%)$": every pattern character escaped,
-- then %s captures the name and %d matches the number.
local function FormatToPattern(fmt)
	local pattern = string.gsub(fmt, "([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
	pattern = string.gsub(pattern, "%%%%s", "(.+)")
	pattern = string.gsub(pattern, "%%%%d", "%%d+")
	return "^"..pattern.."$"
end

-- Fills the scan tooltip through tip[method](tip, a1, a2) and returns it, or
-- nil. The owner is set on every scan: Hide clears it, and on the 1.12 client
-- an unowned tooltip is not filled. The caller hides it again, because with
-- ANCHOR_NONE a filled tooltip stays drawn in the bottom-left corner.
local function FillScanTooltip(method, a1, a2)
	if not enchantScanTooltip then
		local ok, tip = pcall(CreateFrame, "GameTooltip", ENCHANT_SCAN_TOOLTIP, nil, "GameTooltipTemplate")
		if not ok or not tip then return nil end
		enchantScanTooltip = tip
	end
	local tip = enchantScanTooltip
	pcall(tip.SetOwner, tip, UIParent, "ANCHOR_NONE")
	pcall(tip.ClearLines, tip)
	if not pcall(tip[method], tip, a1, a2) then
		pcall(tip.Hide, tip)
		return nil
	end
	return tip
end

local function ScanEnchantName(slot)
	if not enchantPatterns then
		enchantPatterns = {}
		local i
		for i = 1, table.getn(ENCHANT_TIME_FORMATS) do
			local fmt = _G[ENCHANT_TIME_FORMATS[i]]
			if type(fmt) == "string" then
				table.insert(enchantPatterns, FormatToPattern(fmt))
			end
		end
	end

	local tip = FillScanTooltip("SetInventoryItem", "player", slot)
	if not tip then return nil end

	local name
	local okLines, numLines = pcall(tip.NumLines, tip)
	local line
	for line = 2, (okLines and tonumber(numLines)) or 0 do
		local region = _G[ENCHANT_SCAN_TOOLTIP.."TextLeft"..line]
		local text = region and region:GetText()
		if text then
			local p
			for p = 1, table.getn(enchantPatterns) do
				local _, _, captured = string.find(text, enchantPatterns[p])
				if captured then
					name = captured
					break
				end
			end
		end
		if name then break end
	end
	pcall(tip.Hide, tip)
	return name
end

local function PlayerBuffName(buffIndex, texture)
	local entry = buffNameCache[buffIndex]
	if entry and entry.texture == texture then return entry.name end

	local name
	local tip = FillScanTooltip("SetPlayerBuff", buffIndex)
	if tip then
		local region = _G[ENCHANT_SCAN_TOOLTIP.."TextLeft1"]
		name = region and region:GetText()
		pcall(tip.Hide, tip)
	end
	buffNameCache[buffIndex] = { texture = texture, name = name }
	return name
end

local function HasBuffNamed(name)
	local base = StripRank(name)
	local i
	for i = 0, MAX_PLAYER_BUFFS - 1 do
		local okIdx, buffIndex = pcall(GetPlayerBuff, i, "HELPFUL")
		if not okIdx or not buffIndex or buffIndex < 0 then return false end
		local okTex, texture = pcall(GetPlayerBuffTexture, buffIndex)
		if not okTex or not texture then return false end
		local buffName = PlayerBuffName(buffIndex, texture)
		if buffName and (buffName == name or buffName == base) then return true end
	end
	return false
end

function Compat.GetWeaponEnchants()
	local list = {}
	local ok, hasMain, mainLeft, mainCharges, hasOff, offLeft, offCharges = pcall(GetWeaponEnchantInfo)
	if not ok then return list end

	local info = {
		{ hasMain, mainLeft, mainCharges },
		{ hasOff, offLeft, offCharges },
	}

	local w
	for w = 1, 2 do
		local slot = WEAPON_SLOTS[w]
		local texture = GetInventoryItemTexture("player", slot)
		if Compat.bool(info[w][1]) and texture then
			local left = tonumber(info[w][2])
			local charges = tonumber(info[w][3]) or 0
			local cached = enchantCache[slot]
			if not cached or cached.texture ~= texture
				or (left and cached.left and left > cached.left + 1000)
				or (cached.charges and charges > cached.charges) then
				cached = { texture = texture, name = ScanEnchantName(slot) }
				enchantCache[slot] = cached
			end
			cached.left, cached.charges = left, charges

			if not (cached.name and HasBuffNamed(cached.name)) then
				local spellIcon = EnchantIcon(cached.name)
				table.insert(list, {
					slot = slot,
					texture = spellIcon or texture,
					isWeaponIcon = not spellIcon,
					name = cached.name,
					timeLeft = left and (left / 1000) or nil,
					charges = charges,
				})
			end
		else
			enchantCache[slot] = nil
		end
	end
	return list
end

-- UnitIsAFK: absent on both clients (the 1.12.1 FrameXML never calls it).
-- The native function is used where a client has it; otherwise the player's
-- own AFK flag is tracked from CHAT_MSG_SYSTEM: any "You are now AFK"
-- (MARKED_AFK_MESSAGE, whatever the away text) sets it, CLEARED_AFK clears
-- it. Other units cannot be tracked and read as nil. The tracked flag starts
-- false, so after a /reload while away it reads false until the next AFK
-- message.
--
-- Compat.ClearAFK clears the flag. The only way on these clients is the AFK
-- chat command, which toggles, so it is sent only while the flag is set.
-- Should the flag have been cleared without a message (the "now AFK" reply
-- then shows the command set it instead), the command is sent once more,
-- so the end result is always cleared. Unreal Azeroth needs this more than
-- the legacy client: it never clears the flag on movement or input.
local AFK_CLEAR_WINDOW = 5
local afkState = { flag = false, clearSent = nil, retried = false }

-- "AFK" for a "now AFK" message, "CLEARED" for the "no longer AFK" one, nil
-- for anything else.
function Compat.AFKMessage(msg)
	if type(msg) ~= "string" then return nil end
	if msg == _G.CLEARED_AFK then return "CLEARED" end
	local fmt = _G.MARKED_AFK_MESSAGE
	if type(fmt) ~= "string" then return nil end
	local at = string.find(fmt, "%s", 1, true)
	if not at or at < 2 then return nil end
	local prefix = string.sub(fmt, 1, at - 1)
	if string.sub(msg, 1, string.len(prefix)) == prefix then return "AFK" end
	return nil
end

local function SendAFKCommand(retry)
	afkState.clearSent = GetTime()
	afkState.retried = retry
	pcall(SendChatMessage, "", "AFK")
end

-- True while a "now AFK" message may be the reply to Compat.ClearAFK's own
-- command rather than the player going away.
function Compat.IsClearingAFK()
	return afkState.clearSent ~= nil and GetTime() - afkState.clearSent < AFK_CLEAR_WINDOW
end

local afkListener = CreateFrame("Frame")
afkListener:RegisterEvent("CHAT_MSG_SYSTEM")
afkListener:SetScript("OnEvent", function()
	local kind = Compat.AFKMessage(arg1)
	if kind == "CLEARED" then
		afkState.flag = false
		afkState.clearSent = nil
	elseif kind == "AFK" then
		afkState.flag = true
		if Compat.IsClearingAFK() and not afkState.retried then
			SendAFKCommand(true)
		end
	end
end)

function Compat.UnitIsAFK(unit)
	if type(UnitIsAFK) == "function" then
		local ok, value = pcall(UnitIsAFK, unit)
		if ok then return Compat.bool(value) end
	end
	if unit == "player" then return afkState.flag end
	return nil
end

function Compat.ClearAFK()
	if Compat.UnitIsAFK("player") then SendAFKCommand(false) end
end
