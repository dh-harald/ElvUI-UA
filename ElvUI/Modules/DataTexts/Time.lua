-- Time DataText -- ported from real ElvUI's own Time.lua
-- (source/ElvUI-vanilla/ElvUI/Modules/DataTexts/Time.lua), with a
-- DIFFERENT refresh strategy. `onUpdate` is driven by DataTexts.lua's own
-- periodic 1-second timer, not a raw OnUpdate script (see that file's
-- header for why), so one second is the finest tick available here.
--
-- REFRESH IS CHANGE-DRIVEN, NOT COUNTDOWN-DRIVEN. Upstream counts real
-- seconds down (`int = int - t`, re-armed at 1) and repaints whenever the
-- counter expires. A fixed period is wrong for this widget whichever
-- period is picked, because the format is a user setting and the needed
-- granularity changes with it:
--
--   * a period LONGER than the displayed granularity leaves stale digits
--     (`%H:%M:%S` on a 5-second period visibly jumps in fives -- that was
--     this port's own first bug here);
--   * a period EQUAL to the granularity still has an arbitrary PHASE. A
--     60-second repaint of `%H:%M` started at second 55 flips the minute
--     at :55 every time, never at :00.
--
-- So the format is rendered every tick -- one `date()` call plus two
-- string ops, cheap -- and `SetText` is called ONLY when the rendered
-- string differs from what the FontString ALREADY HOLDS (read back with
-- `GetText`, not remembered in an upvalue -- see `OnUpdate` for why that
-- distinction cost the panel its first draw). That is correct at every
-- granularity with no configuration: a seconds format changes every second
-- and repaints every second, a minutes format changes only when the
-- wall-clock minute rolls over and repaints on the first tick at or after
-- that boundary.

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts
local Compat = ElvUI.Compat

local instanceFormat = "%s |cffaaaaaa(%s)"
local enteredFrame = false

-- Time has no "label: value" split, so the accent goes on the SEPARATORS --
-- real ElvUI's own choice here (`timeDisplayFormat`/`dateDisplayFormat`),
-- reproduced including the asymmetry: the hour/minute colon is coloured and
-- CLOSED (`|r`), while the space before the date is coloured and left OPEN,
-- so the date itself carries the accent through to the end of the string.
-- The reason these are rebuilt rather than formatted per update is the same
-- as everywhere else -- see Armor.lua's own note.
--
-- The substitution happens on the FORMAT string handed to `BetterDate`, so
-- the colour codes must not contain anything `date()` would treat as a
-- specifier. `|cffRRGGBB`/`|r` are safe: no `%`.
local timeSeparator = ":"
local dateSeparator = " "

-- The panel this widget last drew into, so a colour change can repaint it
-- immediately instead of waiting for the next tick (upstream keeps the same
-- upvalue for the same reason).
local lastPanel

local function OnLeave()
	GameTooltip:Hide()
	enteredFrame = false
end

local function OnEnter(self)
	DT:SetupTooltip(self)
	enteredFrame = true

	local okRaid, oneraid = pcall(GetNumSavedInstances)
	if okRaid then
		local i
		for i = 1, oneraid do
			local ok, name, id, reset = pcall(GetSavedInstanceInfo, i)
			if ok and name then
				GameTooltip:AddDoubleLine(string.format(instanceFormat, name, id), SecondsToTime(reset, true), 1, 1, 1, 0.8, 0.8, 0.8)
			end
		end
	end

	local okTime, hour, minute = pcall(GetGameTime)
	if okTime then
		GameTooltip:AddDoubleLine(L["Realm Time:"], string.format("%02d:|r%02d", hour, minute), 1, 1, 1, 0.8, 0.8, 0.8)
	end

	GameTooltip:Show()
end

local function OnEvent(self, event)
	if event == "UPDATE_INSTANCE_INFO" and enteredFrame then
		OnEnter(self)
	end
end

-- The stored formats carry a PLAIN ":" (`%I:%M`); swapping it for the
-- accent-coloured one here keeps the saved setting in real ElvUI's own
-- format-string shape instead of storing colour codes in the profile. Safe
-- as a gsub REPLACEMENT string because a colour code contains no `%`, the
-- only character gsub treats specially there.
local function BuildDisplayFormat()
	local timeFormat = E.db.datatexts.timeFormat or "%I:%M"
	local dateFormat = E.db.datatexts.dateFormat or ""

	local displayFormat = string.gsub(timeFormat, ":", timeSeparator)
	if dateFormat ~= "" then
		-- Only separate when there IS a time half to separate from --
		-- "None" is a real choice for the time format, and a leading
		-- coloured space in front of a bare date would be visible.
		if timeFormat ~= "" then
			displayFormat = displayFormat..dateSeparator
		end
		displayFormat = displayFormat..dateFormat
	end
	return displayFormat
end

local function OnUpdate(self)
	-- The tooltip is rebuilt on every tick while the cursor is on the
	-- widget, independently of the text gate below: its contents (saved
	-- instance timers, realm time) move on their own schedule, and it only
	-- costs anything while actually hovered.
	if enteredFrame then
		OnEnter(self)
	end

	lastPanel = self

	local ok, text = pcall(Compat.BetterDate, BuildDisplayFormat(), time())
	if not ok or type(text) ~= "string" then return end

	-- The change gate -- see the file header. What it compares against is
	-- the FontString's ACTUAL current text, deliberately, not a remembered
	-- copy: `DT:LoadDataTexts` blanks every panel (`text:SetText(nil)`)
	-- before re-assigning its widget, and it runs more than once (module
	-- init AND PLAYER_ENTERING_WORLD). A remembered copy survives that
	-- blanking, so the immediate first call after a re-assign compared
	-- equal, wrote nothing, and left the panel EMPTY until the clock next
	-- changed -- up to a full minute on a minute-granularity format.
	-- Reading the widget back cannot go stale that way.
	local okCur, current = pcall(self.text.GetText, self.text)
	if not okCur or current ~= text then
		self.text:SetText(text)
	end
end

local function ValueColorUpdate(hex)
	timeSeparator = hex..":|r"
	dateSeparator = hex.." "

	-- Forced repaint: the new colour changes the rendered string, so the
	-- change gate passes on its own -- but only on the next tick. Re-running
	-- now makes the config control feel immediate.
	if lastPanel then
		OnUpdate(lastPanel)
	end
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

DT:RegisterDatatext("Time", {"UPDATE_INSTANCE_INFO"}, OnEvent, OnUpdate, nil, OnEnter, OnLeave, L["Time"])
