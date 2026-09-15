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

function Compat.GetInventoryItemDurability(slot)
	if not GetInventoryItemTexture("player", slot) then return end

	if not durabilityPattern then
		durabilityPattern = string.gsub(DURABILITY_TEMPLATE, "%%d / %%d", "(%%d+) / (%%d+)")
	end

	if not durabilityScanTooltip then
		local ok
		ok, durabilityScanTooltip = pcall(CreateFrame, "GameTooltip", "ElvUICompat_DurabilityScanTooltip", nil, "ShoppingTooltipTemplate")
		if not ok or not durabilityScanTooltip then return end
		durabilityScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	end

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
