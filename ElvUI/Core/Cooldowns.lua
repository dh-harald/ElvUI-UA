-- Numeric cooldown-countdown text overlay for native Cooldown frames.
--
-- Vanilla 1.12.1 has no built-in cooldown TEXT -- only the native radial
-- swipe animation, which already shows automatically without any of our
-- own code (Blizzard's own cooldown-swipe logic keeps running regardless
-- of how ActionBars.lua/PetBar.lua reparent the buttons). The NUMERIC
-- countdown ("5s", "2m", ...) is an added ElvUI/OmniCC-style feature.
--
-- Ported from real ElvUI's own Core/Cooldowns.lua (145 lines), but NOT a
-- line-for-line copy of its architecture: that version drives one
-- OnUpdate script PER active cooldown frame, throttled by GetTimeInfo's
-- own returned nextUpdate value. A child-frame OnUpdate is unreliable on
-- UA, so this instead drives ALL active cooldowns off a single shared
-- E:ScheduleRepeatingTimer(0.1s). Its icon-size-based font sizing IS
-- ported (`ApplyCooldownFont`). What IS ported faithfully is the actual TEXT
-- FORMATTING: E:GetTimeInfo/E.TimeFormats (Core/Util.lua, ported
-- verbatim from real ElvUI's Core/math.lua) decide the bracket
-- (days/hours/minutes/seconds/expiring) and the exact format string,
-- rather than this file hand-rolling its own threshold comparisons.
--
-- Works globally: hooks Blizzard's own `CooldownFrame_SetTimer` function
-- ONCE, so it fires for ANY native Cooldown frame across the whole UI
-- (ActionBars, PetBar, anything else using the stock Cooldown template),
-- not just frames this addon knows about directly.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()

-- Settings: `V.cooldown` / `P.cooldown` (Settings/Private.lua,
-- Settings/Profile.lua). This module reads `E.db.cooldown.threshold`, the
-- 5 day/hour/minute/second/expiring colors, and the two duration-format
-- thresholds -- nothing else.
--
-- Real ElvUI's `reverse`/`checkSeconds`/`hhmmColor`/`mmssColor`/
-- `hhmmThreshold`/`mmssThreshold` field names ALSO appear under
-- P["bags"]["cooldown"], P["nameplates"]["cooldown"] and
-- P["auras"]["cooldown"] (bag-slot/nameplate-icon/buff-icon cooldown text).
-- Those are separate, unrelated per-module sub-tables and are NOT read
-- here: this is the global CooldownFrame_SetTimer hook.

-- 1.5 (real ElvUI's own value, matches vanilla's standard GCD duration
-- exactly) is meant to filter the GCD swipe out via `duration >
-- MIN_DURATION`, but that alone isn't enough on UA: the GCD swipe gets a
-- number too, meaning whatever duration UA reports for it isn't reliably
-- <= 1.5 the way real vanilla's is. Bumped to 1.9 as a safety margin
-- (deliberately short of a full 2s, in case some real ability has an
-- exactly-2s cooldown), giving room for UA's GCD duration reporting to be
-- slightly off from the exact 1.5 real vanilla uses. Unverified whether
-- 1.9 is enough -- if the GCD still shows a number, print the actual
-- UA-reported GCD duration from inside the hook rather than guessing a
-- higher threshold blind.
local MIN_DURATION = 1.9

-- formatid (E:GetTimeInfo's 2nd return value) -> which E.db.cooldown
-- color field applies. Matches real ElvUI's own TimeColors index
-- convention (ElvUI-vanilla/ElvUI/Core/Cooldowns.lua:16-22,
-- 131-146) exactly: 0=days, 1=hours, 2=minutes, 3=whole seconds (above
-- threshold), 4=decimal seconds ("expiring", below threshold). 5/6
-- (mmss/hhmm) never occur here since nothing calls E:GetTimeInfo with
-- the optional hhmm/mmss args in this module.
local FORMAT_COLOR_KEYS = {
	[0] = "daysColor",
	[1] = "hoursColor",
	[2] = "minutesColor",
	[3] = "secondsColor",
	[4] = "expiringColor",
	-- 5/6 are reachable once mmssThreshold/hhmmThreshold are passed to
	-- E:GetTimeInfo. Real ElvUI's own field names for these two
	-- (Settings/Profile.lua).
	[5] = "mmssColor",
	[6] = "hhmmColor",
}

-- Returns the display string plus an r,g,b color, reading live from
-- E.db.cooldown (matches this project's established "read the live
-- profile table directly, no caching" convention -- real ElvUI instead
-- caches into a local TimeColors table via E:UpdateCooldownSettings(),
-- not needed here since this file has no equivalent hot loop that would
-- make a live table read expensive). Uses the real E:GetTimeInfo/
-- E.TimeFormats (Core/Util.lua) rather than hand-rolled thresholds, so
-- the day/hour/minute/second/expiring bracket boundaries and rounding
-- match real ElvUI exactly, including `threshold`'s documented -1
-- "never turn red" sentinel (GetTimeInfo's own `s >= threshhold` check
-- is then always true for s>=0, so it never takes the expiring branch).
local function FormatRemain(remain)
	local settings = E.db.cooldown

	-- -1 is real ElvUI's own "off" sentinel for both; E:GetTimeInfo wants
	-- nil, not a negative number, or every duration would take the mm:ss
	-- branch (`s < mmss` is false for a negative mmss, so a negative is
	-- actually harmless here -- but nil is the honest way to say "off" and
	-- keeps the intent readable).
	local hhmm = tonumber(settings.hhmmThreshold)
	local mmss = tonumber(settings.mmssThreshold)
	if not hhmm or hhmm < 0 then hhmm = nil end
	if not mmss or mmss < 0 then mmss = nil end

	-- The 4th return is the SECOND component, and it's only produced for
	-- format ids 5/6 -- `E.TimeFormats[5][2]`/`[6][2]` are `"%d:%02d"`, two
	-- placeholders needing two arguments. Real ElvUI's own call sites pass
	-- one value and would error here; they get away with it only because
	-- they never pass hhmm/mmss and so never reach those formats.
	local timervalue, formatid, _, second = E:GetTimeInfo(remain, settings.threshold, hhmm, mmss)
	local color = settings[FORMAT_COLOR_KEYS[formatid]] or settings.secondsColor
	local text
	if formatid == 5 or formatid == 6 then
		text = string.format(E.TimeFormats[formatid][2], timervalue, second or 0)
	else
		text = string.format(E.TimeFormats[formatid][2], timervalue)
	end
	return text, color.r, color.g, color.b
end

-- Shared with countdowns drawn without a Cooldown frame (Modules/Misc/
-- Totems.lua), so they format and colour exactly like this text.
E.FormatCooldownRemain = FormatRemain

local activeTimers = {}
local timerHandle

local function UpdateAllTimers()
	-- Turning the feature OFF has to be handled HERE, not only in the
	-- CooldownFrame_SetTimer wrapper: the wrapper's own enable check gates new
	-- timers, but a cooldown already being tracked keeps its text written by
	-- this ticker until it expires. Checking here is what makes the config
	-- toggle live in BOTH directions, and it covers every disabling path
	-- (config, profile switch), not just the one setter.
	if not E.private.cooldown.enable then
		local cd, entry
		for cd, entry in pairs(activeTimers) do
			pcall(entry.text.SetText, entry.text, "")
			activeTimers[cd] = nil
		end
		if timerHandle then
			E:CancelTimer(timerHandle)
			timerHandle = nil
		end
		return
	end

	local now = GetTime()
	local cd, entry
	for cd, entry in pairs(activeTimers) do
		local remain = entry.duration - (now - entry.start)
		if remain <= 0.05 then
			pcall(entry.text.SetText, entry.text, "")
			activeTimers[cd] = nil
		else
			local str, r, g, b = FormatRemain(remain)
			pcall(entry.text.SetText, entry.text, str)
			pcall(entry.text.SetTextColor, entry.text, r, g, b)
		end
	end

	local hasAny = false
	local k
	for k in pairs(activeTimers) do
		hasAny = true
		break
	end
	if not hasAny and timerHandle then
		E:CancelTimer(timerHandle)
		timerHandle = nil
	end
end

-- Real ElvUI's `E:Cooldown_OnSizeChanged`: the text is 20 at a 36px icon and
-- scales with the cooldown frame's width, outlined; below half that scale no
-- text is shown. The width comes from the frame's edges, because the legacy
-- client reports GetWidth of an anchor-sized frame multiplied by the UI scale.
local ICON_SIZE = 36
local FONT_SIZE = 20
local MIN_SCALE = 0.5

local function CooldownWidth(cd)
	local okLeft, left = pcall(cd.GetLeft, cd)
	local okRight, right = pcall(cd.GetRight, cd)
	if okLeft and okRight and tonumber(left) and tonumber(right) then
		return right - left
	end
	local ok, width = pcall(cd.GetWidth, cd)
	return (ok and tonumber(width)) or nil
end

-- Returns false when the icon is too small to carry text.
local function ApplyCooldownFont(cd, text)
	local width = CooldownWidth(cd)
	local scale = 1
	if width and width > 0 then
		scale = math.floor(width + 0.5) / ICON_SIZE
	end
	if scale < MIN_SCALE then return false end

	if text.elvFontScale ~= scale then
		text.elvFontScale = scale
		E:FontTemplate(text, nil, scale * FONT_SIZE, "OUTLINE")
	end
	return true
end

local function GetOrCreateText(cd)
	if cd.elvCooldownText then return cd.elvCooldownText end
	local ok, text = pcall(cd.CreateFontString, cd, nil, "OVERLAY", "GameFontNormal")
	if not ok or not text then return nil end
	pcall(text.SetPoint, text, "CENTER", cd, "CENTER", 0, 1)
	pcall(text.SetJustifyH, text, "CENTER")
	cd.elvCooldownText = text
	return text
end

local hooked = false

local function InstallCooldownHook()
	if hooked then return end
	local original = _G.CooldownFrame_SetTimer
	if type(original) ~= "function" then return end

	_G.CooldownFrame_SetTimer = function(cd, start, duration, enable)
		original(cd, start, duration, enable)

		if not E.private.cooldown.enable then return end
		if not cd then return end

		if start and start > 0 and duration and duration > MIN_DURATION and enable and enable > 0 then
			local text = GetOrCreateText(cd)
			if text and ApplyCooldownFont(cd, text) then
				activeTimers[cd] = { start = start, duration = duration, text = text }
				if not timerHandle then
					timerHandle = E:ScheduleRepeatingTimer(UpdateAllTimers, 0.1)
				end
			end
		else
			if cd.elvCooldownText then
				pcall(cd.elvCooldownText.SetText, cd.elvCooldownText, "")
			end
			activeTimers[cd] = nil
		end
	end

	hooked = true
end

InstallCooldownHook()
