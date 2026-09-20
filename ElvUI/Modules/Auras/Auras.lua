-- Auras -- the SEPARATE, standalone replacement for the native BuffFrame/
-- DebuffFrame, matching real ElvUI's own actual architecture
-- (source/ElvUI-vanilla/ElvUI/Modules/Auras/Auras.lua, `E:NewModule
-- ("Auras", ...)`). This is a genuinely DIFFERENT thing from
-- UnitFrames.lua's own Construct_Auras/UpdateAuras (which attach a small
-- icon grid to a specific unit frame, including the player's) -- real
-- ElvUI runs BOTH simultaneously: Player's own unit frame carries a
-- (buffs.enable=false / debuffs.enable=true by default) attached grid,
-- AND this module builds two independently-movable frames near the
-- minimap ("ElvUIPlayerBuffs"/"ElvUIPlayerDebuffs") that are the PRIMARY
-- classic-buff-frame replacement.
--
-- This module's icons show duration text, in place of the original
-- buff/debuff frame (unlike UnitFrames.lua's own player-frame icons,
-- which deliberately suppress it for that one).
--
-- Reuses UnitFrames.lua's own icon pooling + tooltip wiring
-- (UF:GetOrCreateAuraIcon/UF:GetAuraInfo, both promoted from local to
-- public methods for exactly this reuse) rather than duplicating that
-- code -- the tooltip technique (GameTooltip:SetPlayerBuff, `this`-
-- wrapped OnEnter/OnLeave) is already correct there.
--
-- Deliberate scope cuts from the real module:
--   - No weapon-enchant (temporary weapon buff) icons -- `self.offset`/
--     `GetWeaponEnchantInfo` branch, a whole separate code path.
--   - No 8-direction `growthDirection` system (DOWN_RIGHT/UP_LEFT/etc.)
--     -- reuses the same simple row/perrow grid already established for
--     every unit frame's own aura grid (UnitFrames.lua), just anchored
--     from the container's outer corner so icons grow AWAY from the
--     minimap instead of toward it.
--   - `sortMethod`/`sortDir` ARE implemented (INDEX/TIME, matching real
--     ElvUI's own two most useful values and default "TIME"/"-"); NO
--     "NAME" sort (no cheap per-aura name lookup for the player's own
--     buffs the way DebuffDurations.lua's tooltip-scan gets one for
--     other units' debuffs) and no `seperateOwn` (every aura here is
--     already the player's own by definition -- that field only means
--     something for a raid-frame-style multi-caster aura list).
--   - No right-click-to-cancel (`CancelPlayerBuff`) -- not requested.
-- Every one of these is a "nothing breaks, just less polish" cut, not a
-- correctness risk -- can be revisited if asked for specifically.
--
-- Fade threshold + text color + expiring-icon flash. Real ElvUI has this
-- field (`E.db.auras.fadeThreshold`, real default 5, source/
-- ElvUI-vanilla/ElvUI/Settings/Profile.lua) and its config description
-- literally says the icon fades as the duration nears the threshold --
-- BUT the actual flash CALLS in real Modules/Auras/Auras.lua are
-- commented out in that reference tree (`--E:StopFlash(self)`/
-- `--E:Flash(self, 1)`), i.e. real ElvUI's own shipped vanilla port
-- doesn't actually flash despite the config text promising it. This
-- implements a real (if simplified) sine-pulse alpha flash instead of
-- leaving the same dead code path.
--
-- Text color reads the SHARED, non-configurable `E.TimeColors`
-- (Core/Util.lua), exactly like real ElvUI does -- not a set of
-- project-invented per-color config fields, since inventing settings no
-- real profile can drive is worse than matching the reference. The only
-- configurable part is real ElvUI's own `auras.fadeThreshold`, plus the
-- duration FORMAT thresholds shared with the Cooldown Text module.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local A = E:NewModule("Auras", "AceEvent-3.0")
local UF = E.UnitFrames

local ICON_SPACING = 2
-- Extra vertical gap for the countdown text now rendering BELOW each
-- icon -- same reasoning/value as UnitFrames.lua's own AURA_ROW_SPACING.
local ICON_ROW_SPACING = 14

-- Settings: `V.auras` (Settings/Private.lua), `P.auras`
-- (Settings/Profile.lua), `G.auras` (Settings/Global.lua -- one-shot
-- migration markers, see `A:MigrateAuraFields`).
--
-- This module's field vocabulary is real ElvUI's own standalone-Auras one
-- (`wrapAfter`/`maxWraps`/`horizontalSpacing`/`verticalSpacing`), NOT the
-- per-unit aura vocabulary UnitFrames.lua uses (`perrow`/`xOffset`/
-- `yOffset`). The two are unrelated despite covering the same ground; see
-- Settings/Profile.lua for the per-field meanings.
--
-- There is deliberately no per-buffs/debuffs `enable`, no per-type
-- `minDuration`/`maxDuration`, and no aura-text color setting -- real
-- ElvUI's `P["auras"]` has none of those either. The horizontal/vertical
-- spacing settings replace what used to be the ICON_SPACING/
-- ICON_ROW_SPACING file-locals above.

-- One-time migration off the old (wrong) field names, so a profile saved
-- under those doesn't silently lose its per-row setting.
--
-- HOW THE ONE-SHOT WORKS, because the obvious version doesn't: `E.db` is
-- built as `Merge({}, defaults)` and THEN `Merge(db, saved)` (Init.lua's
-- OnInitialize), so every key present in the new defaults is ALWAYS
-- non-nil by the time this runs -- a `if db.wrapAfter == nil` guard would
-- never fire. The reliable signal is the reverse one: `perrow` is NOT in
-- the new defaults, so its presence means, and only means, "this profile
-- predates the rename". `wrapAfter` is therefore still guaranteed to be
-- the fresh default at that moment, so copying over it is always correct.
-- Deleting `perrow` afterwards is what makes it run exactly once.
--
-- `xOffset`/`yOffset` are deliberately NOT migrated to
-- horizontal/verticalSpacing despite looking like the obvious
-- counterparts: the old layout code never read them at all (it used two
-- file-local ICON_SPACING/ICON_ROW_SPACING constants), so every saved
-- profile carries the 0 default -- migrating them would collapse all icon
-- spacing to zero. They're just dropped.
function A:MigrateAuraFields()
	local auras = E.db.auras
	auras.expiringColor = nil
	auras.secondsColor = nil
	auras.minutesColor = nil
	auras.hoursColor = nil
	auras.daysColor = nil

	local which
	for which = 1, 2 do
		local db = auras[(which == 1) and "buffs" or "debuffs"]
		if db then
			if db.perrow ~= nil then
				if tonumber(db.perrow) then db.wrapAfter = db.perrow end
				db.perrow = nil
				db.xOffset = nil
				db.yOffset = nil
			end
			-- Unconditional cleanup of project-invented fields. No trigger
			-- condition needed: none of these is in the defaults any more,
			-- so if one is present it can only be stale saved data.
			-- Nothing reads them, so this is tidiness rather than
			-- correctness -- but leaving dead keys in a profile that is
			-- meant to round-trip with real ElvUI's own format is exactly
			-- the kind of drift worth not accumulating.
			db.enable = nil
			db.minDuration = nil
			db.maxDuration = nil
		end
	end

	-- ONE-SHOT GRID CORRECTION. This is the SAME merge-order trap the
	-- `perrow` migration above already documents, from the other
	-- direction. `E.db` is `Merge({}, defaults)` then `Merge(db, saved)`
	-- (Init.lua's OnInitialize), so once a value has been WRITTEN to a
	-- saved profile it wins over any later change to the defaults,
	-- forever -- a profile that already has a 12/3 and 12/1 grid saved
	-- would never pick up the corrected 8/4 and 8/2 defaults on its own.
	--
	-- Gated on a marker in the GLOBAL db, not the profile: `E.db` is the
	-- table that has to round-trip with a real ElvUI profile, and a
	-- project-invented bookkeeping key does not belong in it (that is
	-- exactly what was just deleted from `P.auras`). `E.global` is this
	-- addon's own store and never leaves it.
	--
	-- Why a marker at all instead of just overwriting: real ElvUI's OWN
	-- defaults are 12/3 and 12/1, so "looks like the old defaults" is
	-- indistinguishable from "an imported real ElvUI profile". Running
	-- unconditionally would silently clobber an import every login --
	-- precisely the thing this whole line of work exists to protect.
	if E.global and E.global.auras and not E.global.auras.gridDefaultsCorrected then
		E.global.auras.gridDefaultsCorrected = true

		local buffs, debuffs = auras.buffs, auras.debuffs
		if buffs and buffs.wrapAfter == 12 and buffs.maxWraps == 3 then
			buffs.wrapAfter, buffs.maxWraps = 8, 4
		end
		if debuffs and debuffs.wrapAfter == 12 and debuffs.maxWraps == 1 then
			debuffs.wrapAfter, debuffs.maxWraps = 8, 2
		end
	end
end

-- Colours come from the SHARED, NON-CONFIGURABLE `E.TimeColors`
-- (Core/Util.lua) now, exactly like real ElvUI's own Auras.lua:83 does --
-- see the defaults block above for why the five configurable colour fields
-- that used to live here were removed.
--
-- The mm:ss / hh:mm formats (ids 5 and 6) ARE reachable here: the optional
-- 3rd/4th args of `E:GetTimeInfo` switch a duration into `30:00` instead of
-- `30m`, and they're driven by the real ElvUI field names
-- `mmssThreshold`/`hhmmThreshold`. Those live on `E.db.cooldown` (see
-- Core/Cooldowns.lua's own note on where real ElvUI keeps them), so the two
-- countdown displays in this addon stay in one format regime rather than
-- drifting apart. The THRESHOLD for "expiring" stays `auras.fadeThreshold`,
-- matching real ElvUI's own split exactly.
local function FormatRemain(remain)
	local cooldownDB = E.db.cooldown
	local hhmm = tonumber(cooldownDB and cooldownDB.hhmmThreshold)
	local mmss = tonumber(cooldownDB and cooldownDB.mmssThreshold)
	-- -1 is real ElvUI's own "disabled" sentinel for both (Settings/
	-- Profile.lua) -- `E:GetTimeInfo` expects nil, not a negative.
	if not hhmm or hhmm < 0 then hhmm = nil end
	if not mmss or mmss < 0 then mmss = nil end

	-- The 4th return matters and is easy to miss: for the mm:ss and hh:mm
	-- formats `E:GetTimeInfo` returns the SECOND component separately
	-- (`mod(s, MINUTE)` for id 5, `mod(minutes, MINUTE)` for id 6), because
	-- `E.TimeFormats[5][2]`/`[6][2]` are `"%d:%02d"` -- two placeholders,
	-- two arguments. Real ElvUI's own Auras.lua formats with the single
	-- value only and would error here; it gets away with it purely because
	-- it never passes hhmm/mmss and so never reaches format 5 or 6.
	local timervalue, formatid, _, second = E:GetTimeInfo(remain, E.db.auras.fadeThreshold, hhmm, mmss)
	local color = E.TimeColors[formatid] or E.TimeColors[3]
	local text
	if formatid == 5 or formatid == 6 then
		text = string.format(E.TimeFormats[formatid][2], timervalue, second or 0)
	else
		text = string.format(E.TimeFormats[formatid][2], timervalue)
	end
	return text, color[1], color[2], color[3], formatid
end

-- Real ElvUI's own `timeXOffset`/`timeYOffset`/`countXOffset`/
-- `countYOffset` (P["auras"], Settings/Profile.lua) -- these move the
-- duration text and the stack-count text relative to their default
-- spots. Applied ON TOP of the anchors UF:GetOrCreateAuraIcon already
-- sets (count at the icon's BOTTOMRIGHT, duration centered under the
-- icon), so 0/0 reproduces exactly the previous layout.
--
-- Cached per icon and only re-pointed when a value actually changed --
-- this runs for every visible icon on a 0.1s tick, and a needless
-- ClearAllPoints/SetPoint pair 10x/second per icon causes a visible cost.
--
-- The sibling real fields `font`/`fontSize`/`fontOutline` are NOT applied:
-- `SetFont` is a no-op on UA. They stay in the defaults for profile
-- round-tripping only.
local function ApplyTextOffsets(icon)
	local db = E.db.auras
	local timeX = db.timeXOffset or 0
	local timeY = db.timeYOffset or 0
	local countX = db.countXOffset or 0
	local countY = db.countYOffset or 0

	if icon.cooldown and (icon.elvTimeX ~= timeX or icon.elvTimeY ~= timeY) then
		icon.elvTimeX, icon.elvTimeY = timeX, timeY
		pcall(icon.cooldown.ClearAllPoints, icon.cooldown)
		pcall(icon.cooldown.SetPoint, icon.cooldown, "TOP", icon, "BOTTOM", timeX, -2 + timeY)
	end
	if icon.count and (icon.elvCountX ~= countX or icon.elvCountY ~= countY) then
		icon.elvCountX, icon.elvCountY = countX, countY
		pcall(icon.count.ClearAllPoints, icon.count)
		pcall(icon.count.SetPoint, icon.count, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1 + countX, countY)
	end
end

-- Same technique as every other HideNative* function in this project
-- (Player.lua's own HideNativeBuffFrame did this before -- moved here to
-- match real ElvUI's own module boundary: the Auras module owns killing
-- BuffFrame, not UnitFrames).
local function KillNativeBuffFrame()
	local frame = BuffFrame
	if frame then
		pcall(frame.UnregisterAllEvents, frame)
		pcall(frame.SetScript, frame, "OnEvent", nil)
		pcall(frame.SetScript, frame, "OnUpdate", nil)
		pcall(frame.Hide, frame)
		frame.Show = E.noop
	end

	-- `Buff1..32`/`Debuff1..16` DO NOT EXIST in real 1.12.1 -- the buff
	-- frame's own buttons are `BuffButton1..23` in one continuous run:
	-- 1-16 helpful (`BuffButtonTemplate`) and 17-23 harmful
	-- (`BuffButtonHarmful`, `DEBUFF_MAX_DISPLAY = 7`), confirmed in
	-- source/wow-ui-source/FrameXML/BuffFrame.xml / BuffFrame.lua. Parent
	-- visibility does NOT reliably propagate to children on UA, so this
	-- loop over the real button names, not just `BuffFrame:Hide()` above,
	-- is what actually covers every child on this client.
	--
	-- NOTE, because it's an easy trap: 16 + 7 is what the NATIVE FRAME can
	-- DISPLAY, not how many auras a character can have. The actual cap is
	-- 32 buffs + 16 debuffs (Buff.md) -- see the defaults block above.
	local i
	for i = 1, 23 do
		local button = _G["BuffButton"..i]
		if button then
			pcall(button.Hide, button)
			button.Show = E.noop
		end
	end

	local enchant = TemporaryEnchantFrame
	if enchant then
		pcall(enchant.Hide, enchant)
		enchant.Show = E.noop
	end
end

-- Comparator factory for the "TIME" sort -- nil timeLeft (no known
-- duration) sorts as if it were effectively infinite, so auras with an
-- unknown duration land at whichever end represents "longest remaining"
-- for the chosen direction, instead of erroring on a nil comparison.
-- 1e9 as a "no known duration" sentinel instead of math.huge -- avoids
-- relying on an unverified global on the real 1.12.1 (Lua 5.0.3) client;
-- large enough that no real aura duration ever approaches it.
local NO_DURATION_SENTINEL = 1000000000

local function TimeComparator(ascending)
	if ascending then
		return function(a, b) return (a.timeLeft or NO_DURATION_SENTINEL) < (b.timeLeft or NO_DURATION_SENTINEL) end
	end
	return function(a, b) return (a.timeLeft or NO_DURATION_SENTINEL) > (b.timeLeft or NO_DURATION_SENTINEL) end
end

local function SortAuras(list, sortMethod, sortDir)
	if sortMethod == "TIME" then
		table.sort(list, TimeComparator(sortDir == "+"))
	elseif sortDir == "-" then
		table.sort(list, function(a, b) return a.index > b.index end)
	end
	-- INDEX + "+" needs no sort -- collection order already IS ascending
	-- index order.
end

-- `auraType` is "buff"/"debuff" (matches UnitFrames.lua's own
-- convention), NOT real ElvUI's "HELPFUL"/"HARMFUL" filter strings --
-- converted at the UF:GetAuraInfo call site, same as everywhere else.
function A:UpdateHeader(header, auraType)
	-- E.db, not P -- this runs at runtime (after OnInitialize deep-copies
	-- P into E.db), and must see whatever the config UI actually wrote,
	-- not the frozen defaults. Same class of bug just caught in the
	-- config file itself (P/V there vs E.db/E.private) -- this is the
	-- module-side half of the same mistake.
	local settings = E.db.auras[(auraType == "buff") and "buffs" or "debuffs"]
	-- No per-type enable check any more -- that field was removed with the
	-- rest of the project-invented settings (see the defaults block).
	-- `E.private.auras.enable`, checked once in A:Initialize, is the real
	-- switch; if it's off this module never builds these headers at all.
	header:Show()

	local size = settings.size or 32
	local perRow = settings.wrapAfter or 8
	if perRow < 1 then perRow = 1 end
	local maxWraps = settings.maxWraps or 1
	if maxWraps < 1 then maxWraps = 1 end
	local hSpacing = settings.horizontalSpacing or ICON_SPACING
	local vSpacing = settings.verticalSpacing or ICON_ROW_SPACING
	local fadeThreshold = E.db.auras.fadeThreshold or 5
	-- `wrapAfter * maxWraps` is real ElvUI's own definition of the hard
	-- ceiling for this display -- past it, extra auras simply aren't shown
	-- (its own header code stops laying out at the same point). Without
	-- this cap an extra aura would be drawn outside the area the mover
	-- advertises.
	local maxIcons = perRow * maxWraps

	-- Buffs grow left+down from the header's own TOPRIGHT corner (the
	-- corner nearest the minimap); debuffs grow left+up from BOTTOMRIGHT
	-- -- a simplified stand-in for real ElvUI's default growth direction
	-- (see the header comment's scope-cut list), not pixel-matched.
	local anchor = (auraType == "buff") and "TOPRIGHT" or "BOTTOMRIGHT"
	local rowSign = (auraType == "buff") and -1 or 1

	-- Pass 1: collect. Sorting (by remaining time, matching real ElvUI's
	-- own default) needs every entry gathered up front -- it can't be done
	-- inline while walking GetPlayerBuff's own fixed enumeration order.
	--
	-- No min/max duration filter any more: those field names are real
	-- ElvUI's, but they belong under `buffs.filters` on the UNITFRAME and
	-- NAMEPLATE aura tables, never on `P["auras"]` (see the defaults block).
	local list = {}
	local i
	for i = 1, 32 do
		local texture, count, timeLeft = UF:GetAuraInfo("player", auraType, i)
		if not texture then break end
		table.insert(list, { index = i, texture = texture, count = count, timeLeft = timeLeft })
	end

	SortAuras(list, settings.sortMethod or "TIME", settings.sortDir or "-")

	-- Pass 2: render in sorted order, up to the wrapAfter*maxWraps ceiling.
	local shown = 0
	for i = 1, table.getn(list) do
		if shown >= maxIcons then break end
		local aura = list[i]
		shown = shown + 1
		local icon = UF:GetOrCreateAuraIcon(header, shown)
		icon:SetWidth(size)
		icon:SetHeight(size)
		pcall(icon.texture.SetTexture, icon.texture, aura.texture)
		icon.count:SetText((aura.count and aura.count > 1) and tostring(aura.count) or "")

		if aura.timeLeft then
			local text, r, g, b = FormatRemain(aura.timeLeft)
			icon.cooldown:SetText(text)
			pcall(icon.cooldown.SetTextColor, icon.cooldown, r, g, b)
		else
			icon.cooldown:SetText("")
		end

		-- Flash -- see this file's own header comment on why this is a
		-- real (if simplified) implementation rather than porting the
		-- reference's own dead/commented-out E:Flash calls. Sine-pulse
		-- alpha, only while the aura is actually within the fade window
		-- (fadeThreshold -1 = disabled, matching E:GetTimeInfo's own
		-- "-1 = never" sentinel already established by Cooldowns.lua).
		if aura.timeLeft and fadeThreshold >= 0 and aura.timeLeft <= fadeThreshold then
			pcall(icon.SetAlpha, icon, 0.4 + 0.6 * math.abs(math.sin(GetTime() * 4)))
		else
			pcall(icon.SetAlpha, icon, 1)
		end

		icon.tooltipUnit = "player"
		icon.tooltipIndex = aura.index
		icon.tooltipFilter = (auraType == "buff") and "HELPFUL" or "HARMFUL"

		ApplyTextOffsets(icon)

		local row = math.floor((shown - 1) / perRow)
		local col = (shown - 1) - row * perRow
		icon:ClearAllPoints()
		icon:SetPoint(anchor, header, anchor, -col * (size + hSpacing), rowSign * row * (size + vSpacing))
		icon:Show()
	end

	local j
	for j = shown + 1, table.getn(header.icons) do
		header.icons[j]:Hide()
	end

	-- HEADER SIZE IS ALWAYS THE FULL wrapAfter x maxWraps GRID -- never the
	-- current aura count. Two separate reasons, and the second one is a
	-- real bug this fixes:
	--
	-- 1. The drag handle is `SetAllPoints`'d to this frame
	--    (Core/Movers.lua's CreateHandle), so header size IS mover size --
	--    the /moveui outline shows the maximum area the display can ever
	--    occupy.
	-- 2. **A content-sized header makes the icons wander.** With a
	--    single buff up, dragging the header and then reloading/closing
	--    would leave that one icon drifted to the wrong side of the
	--    area. Root cause: the mover's own `CalculateMoverPoint` re-anchors
	--    a dragged frame
	--    from whichever screen corner is nearest, so after a drag the
	--    header is typically anchored by its LEFT edge -- while the icons
	--    are anchored to its RIGHT edge (TOPRIGHT for buffs). Resizing the
	--    frame down to "one buff wide" then moves its right edge leftwards,
	--    and the icon follows it. A fixed-size frame has no such coupling.
	--    A first attempt sized to the full grid only while movers were
	--    unlocked, which is precisely what created the jump at lock time.
	--
	-- This also matches real ElvUI, whose own aura header is sized from the
	-- config, never from how many auras happen to be up.
	local rows, cols = maxWraps, perRow
	header:SetWidth(cols * size + (cols - 1) * hSpacing)
	header:SetHeight(rows * size + (rows - 1) * vSpacing)
end

function A:CreateAuraHeader(name, auraType)
	local header = CreateFrame("Frame", name, UIParent)
	header.icons = {}
	pcall(header.SetClampedToScreen, header, true)
	header.auraType = auraType

	-- Matches real ElvUI's own trigger event exactly
	-- (source/ElvUI-vanilla/ElvUI/Modules/Auras/Auras.lua:
	-- `header:RegisterEvent("PLAYER_AURAS_CHANGED")`). `this`, not a
	-- passed `self` -- vanilla script-handler convention, established
	-- project-wide.
	header:RegisterEvent("PLAYER_AURAS_CHANGED")
	header:SetScript("OnEvent", function()
		A:UpdateHeader(this, this.auraType)
	end)

	self:UpdateHeader(header, auraType)
	return header
end

function A:Initialize()
	-- E.private, not V -- same reasoning as E.db vs P above. Single flag
	-- (matches ActionBars.lua's own `M:Initialize` shape exactly): if
	-- we're not building our own replacement, leave Blizzard's alone.
	if not E.private.auras.enable then return end

	A:MigrateAuraFields()

	KillNativeBuffFrame()

	local mmHolder = _G["ElvUIMinimapHolder"]

	self.BuffFrame = self:CreateAuraHeader("ElvUIPlayerBuffs", "buff")
	if mmHolder then
		self.BuffFrame:SetPoint("TOPRIGHT", mmHolder, "TOPLEFT", -8, -4)
	else
		self.BuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -4)
	end
	E:CreateMover(self.BuffFrame, "BuffsMover", L["Player Buffs"])

	self.DebuffFrame = self:CreateAuraHeader("ElvUIPlayerDebuffs", "debuff")
	if mmHolder then
		self.DebuffFrame:SetPoint("BOTTOMRIGHT", mmHolder, "BOTTOMLEFT", -8, 4)
	else
		self.DebuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -240)
	end
	E:CreateMover(self.DebuffFrame, "DebuffsMover", L["Player Debuffs"])

	-- Periodic refresh alongside the event trigger -- matches this
	-- project's established preference for a shared repeating timer over
	-- relying on a single event to always fire reliably on UA (same
	-- reasoning as Cooldowns.lua's own countdown-text timer), since a
	-- buff's remaining time changes continuously, not just on
	-- PLAYER_AURAS_CHANGED. 0.1s (not 1s) -- needed for the expiring-icon
	-- flash to actually read as a smooth pulse rather than a once-a-
	-- second jump; matches Cooldowns.lua's own interval exactly.
	E:ScheduleRepeatingTimer(function()
		if A.BuffFrame then A:UpdateHeader(A.BuffFrame, "buff") end
		if A.DebuffFrame then A:UpdateHeader(A.DebuffFrame, "debuff") end
	end, 0.1)

	-- NO mover-state callback here, deliberately: resizing the header
	-- between "content size" and "full grid" as /moveui toggles is what
	-- makes a single buff jump to the wrong side of the frame on lock
	-- (see A:UpdateHeader's own HEADER SIZE note). The header is a fixed,
	-- config-sized frame now, and it is never hidden, so there is nothing
	-- left for a mover-state callback to do.
end

E:RegisterInitialModule(A:GetName(), function() A:Initialize() end)
