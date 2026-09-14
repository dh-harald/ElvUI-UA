-- Small generic helpers shared across Core/Modules. Not Lua-5.0/5.1 specific
-- (see Compat.lua for that) -- just plain utility functions every module
-- ends up needing.

ElvUI = ElvUI or {}
ElvUI.Util = ElvUI.Util or {}

local Util = ElvUI.Util

local function DeepCopy(src)
	local copy = {}
	local k, v
	for k, v in pairs(src) do
		if type(v) == "table" then
			copy[k] = DeepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

-- Recursively overlays src's keys onto dst (in place) and returns dst.
-- Where both sides have a table at the same key, merges into it instead of
-- replacing it wholesale -- this is what lets a saved profile overlay a
-- defaults table without losing default values for keys the saved profile
-- doesn't have (e.g. an option added in a newer version than the saved
-- profile was written with).
--
-- When `dst[k]` is NOT already a table but `v` (src's value) IS, this
-- DeepCopy()s rather than doing a bare `dst[k] = v` reference assignment.
-- Init.lua's first merge call, `self.db = Merge({}, self.DF.profile)`,
-- starts `dst` as a brand new EMPTY table -- so without the copy, every
-- table-valued key in the defaults (P) would end up as the EXACT SAME
-- TABLE OBJECT on `dst` as on `P` (`self.db.actionbar` aliasing
-- `P.actionbar`, etc.), and any later runtime write to
-- `E.db.actionbar.barN.xxx` would ALSO mutate the supposedly-pure,
-- module-load-time-only defaults table directly -- polluting it with one
-- character's live/saved values for the rest of the Lua session, visible
-- to anything (including a second character's relog) that reads P
-- expecting pure defaults. DeepCopy() ensures `dst` never ends up sharing
-- a nested table BY REFERENCE with `src`; the recursive-overlay behavior
-- for keys that already exist on both sides is unchanged.
function Util.MergeTable(dst, src)
	local k, v
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) == "table" then
				Util.MergeTable(dst[k], v)
			else
				dst[k] = DeepCopy(v)
			end
		else
			dst[k] = v
		end
	end
	return dst
end

-- Matches real ElvUI's own E:Round exactly (source/ElvUI-vanilla/ElvUI/
-- Core/math.lua:94) -- attached directly to the AddOn object (not under
-- ElvUI.Util) since that's where real ElvUI itself puts it and other
-- code may call E:Round(...) expecting it there.
local E = ElvUI[1]
function E:Round(num, idp)
	if idp and idp > 0 then
		local mult = 10 ^ idp
		return math.floor(num * mult + 0.5) / mult
	end
	return math.floor(num + 0.5)
end

-- Matches real ElvUI's own E:RGBToHex exactly (source/ElvUI-vanilla/ElvUI/
-- Core/math.lua:106-111).
function E:RGBToHex(r, g, b)
	r = r <= 1 and r >= 0 and r or 1
	g = g <= 1 and g >= 0 and g or 1
	b = b <= 1 and b >= 0 and b or 1
	return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Matches real ElvUI's own E:ColorGradient exactly (source/ElvUI-vanilla/
-- ElvUI/Core/math.lua:79-92) -- Modules/DataTexts/Durability.lua uses this
-- to color its tooltip lines by durability percent (red -> yellow -> green).
function E:ColorGradient(perc, r1, g1, b1, r2, g2, b2, r3, g3, b3)
	if perc >= 1 then
		return r3, g3, b3
	elseif perc <= 0 then
		return r1, g1, b1
	end

	local segment, relperc = math.modf(perc)
	if segment > 0 then
		r1, g1, b1, r2, g2, b2 = r2, g2, b2, r3, g3, b3
	end

	return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
end

-- Real ElvUI's own E.InversePoints (its Core/core.lua:58-68), verbatim. Used
-- wherever a setting names the point on the PARENT and the child has to attach by
-- its opposite corner, so the child grows AWAY from the parent -- that is exactly
-- how upstream's aura `anchorPoint` works (UnitFrames' UpdateAuras).
E.InversePoints = {
	TOP = "BOTTOM",
	BOTTOM = "TOP",
	TOPLEFT = "BOTTOMLEFT",
	TOPRIGHT = "BOTTOMRIGHT",
	LEFT = "RIGHT",
	RIGHT = "LEFT",
	BOTTOMLEFT = "TOPLEFT",
	BOTTOMRIGHT = "TOPRIGHT",
	CENTER = "CENTER",
}

-- Abbreviates a number the way real ElvUI's own `E:ShortValue` does
-- (source/ElvUI-vanilla/ElvUI/Core/math.lua:15-73): 1700 -> "1.7K". Driven by
-- two profile fields, `E.db.general.numberPrefixStyle` (which prefix set) and
-- `decimalLength` (how many decimals), both real ElvUI keys with real ElvUI
-- defaults.
--
-- Prefix sets and their cut points are upstream's verbatim, including that
-- CHINESE/KOREAN break at 1e4/1e8 rather than 1e3/1e6 (10k / 100M are the
-- natural units there, not thousand / million). Anything below the smallest cut
-- point prints as a plain integer, so small values are never decorated.
--
-- Sign handling matches upstream: the CUT is chosen from the absolute value, but
-- the printed number keeps its sign, so -1700 becomes "-1.7K".
--
-- Deliberate deviation: `decimalLength` 0 turns abbreviation off and prints the
-- full integer (1762), where upstream would print "2K". A value with no
-- decimals left carries so little information that the full number is the more
-- useful reading. 1 and up behave exactly as upstream.
--
-- No `%` operator anywhere in here -- it does not parse on Lua 5.0.3 (CLAUDE.md).
-- `string.format`'s own "%%.%df" is a format LITERAL, which is unaffected.
local SHORT_VALUE_PREFIXES = {
	METRIC  = { { 1e12, "T" }, { 1e9, "G" },   { 1e6, "M" },   { 1e3, "k" } },
	ENGLISH = { { 1e12, "T" }, { 1e9, "B" },   { 1e6, "M" },   { 1e3, "K" } },
	GERMAN  = { { 1e12, "Bio" }, { 1e9, "Mrd" }, { 1e6, "Mio" }, { 1e3, "Tsd" } },
	CHINESE = { { 1e8, "Y" }, { 1e4, "W" } },
	KOREAN  = { { 1e8, "\236\150\181" }, { 1e4, "\235\167\140" }, { 1e3, "\236\178\156" } },
}

function E:ShortValue(v)
	v = tonumber(v)
	if not v then return "" end

	local general = E.db and E.db.general
	local style = (general and general.numberPrefixStyle) or "ENGLISH"
	local dec = (general and general.decimalLength) or 1
	if dec <= 0 then
		return string.format("%.0f", v)
	end

	local set = SHORT_VALUE_PREFIXES[style] or SHORT_VALUE_PREFIXES.ENGLISH
	local decFormat = string.format("%%.%df", dec)

	local value = (v < 0) and -v or v
	local i
	for i = 1, table.getn(set) do
		local cut, suffix = set[i][1], set[i][2]
		if value >= cut then
			return string.format(decFormat .. suffix, v / cut)
		end
	end

	return string.format("%.0f", v)
end

-- Matches real ElvUI's own E:FormatMoney exactly (source/ElvUI-vanilla/
-- ElvUI/Core/math.lua:383-450), except the copper/silver/gold abbreviation
-- strings are hardcoded here instead of read from AceLocale (the MODULES
-- still use inline literals -- only ElvUI_Config's option text goes through
-- `L[...]` so far, see Locales/enUS.lua's header).
--
-- The values are real ElvUI's own English_UI.lua ones VERBATIM, colour codes
-- included -- gold `ffd700`, silver `c7c7cf`, copper `eda55f`. An earlier
-- version here stripped those codes on the grounds that "Gold.lua already
-- colors the whole string via other means"; it does not, and the result was a
-- flat white money string where every other ElvUI shows coin-coloured
-- denominations. Every consumer (the Gold data text's panel label and
-- tooltip, the bag gold label and the vendor-cost tooltip line) is plain
-- display text, so the embedded codes are safe in all of them.
function E:FormatMoney(amount, style)
	local coppername, silvername, goldname = "|cffeda55fc|r", "|cffc7c7cfs|r", "|cffffd700g|r"

	local val = math.abs(amount)
	local gold = math.floor(val / 10000)
	local silver = math.floor(ElvUI.Compat.mod(val / 100, 100))
	local copper = math.floor(ElvUI.Compat.mod(val, 100))

	if not style or style == "SMART" then
		local str = ""
		if gold > 0 then
			str = string.format("%d%s%s", gold, goldname, (silver > 0 or copper > 0) and " " or "")
		end
		if silver > 0 then
			str = string.format("%s%d%s%s", str, silver, silvername, copper > 0 and " " or "")
		end
		if copper > 0 or val == 0 then
			str = string.format("%s%d%s", str, copper, coppername)
		end
		return str
	end

	if style == "FULL" then
		if gold > 0 then
			return string.format("%d%s %d%s %d%s", gold, goldname, silver, silvername, copper, coppername)
		elseif silver > 0 then
			return string.format("%d%s %d%s", silver, silvername, copper, coppername)
		else
			return string.format("%d%s", copper, coppername)
		end
	elseif style == "SHORT" then
		if gold > 0 then
			return string.format("%.1f%s", amount / 10000, goldname)
		elseif silver > 0 then
			return string.format("%.1f%s", amount / 100, silvername)
		else
			return string.format("%d%s", amount, coppername)
		end
	elseif style == "SHORTINT" then
		if gold > 0 then
			return string.format("%d%s", gold, goldname)
		elseif silver > 0 then
			return string.format("%d%s", silver, silvername)
		else
			return string.format("%d%s", copper, coppername)
		end
	elseif style == "CONDENSED" then
		if gold > 0 then
			return string.format("%d.%02d.%02d", gold, silver, copper)
		elseif silver > 0 then
			return string.format("%d.%02d", silver, copper)
		else
			return string.format("%d", copper)
		end
	elseif style == "BLIZZARD" then
		if gold > 0 then
			return string.format("%d%s %d%s %d%s", gold, goldname, silver, silvername, copper, coppername)
		elseif silver > 0 then
			return string.format("%d%s %d%s", silver, silvername, copper, coppername)
		else
			return string.format("%d%s", copper, coppername)
		end
	end

	return E:FormatMoney(amount, "SMART")
end

-- Matches real ElvUI's own E:Delay PUBLIC BEHAVIOR (schedule `func` to run
-- once, `delay` seconds from now) but not its internal mechanism -- real
-- ElvUI (source/ElvUI-vanilla/ElvUI/Core/math.lua) hand-rolls a
-- "wait table" driven by a raw `OnUpdate` script; this project avoids raw
-- `OnUpdate` project-wide (unreliable on UA) in favor of AceTimer-3.0
-- (`E:ScheduleTimer`, already vendored and proven throughout this
-- project) -- simpler and consistent with everything else here. No `...`
-- forwarding (real ElvUI's own signature is `E:Delay(delay, func, ...)`)
-- since nothing in this project's own DataText ports actually needs extra
-- args passed through -- every caller uses a zero-arg closure.
function E:Delay(delay, func)
	if type(delay) ~= "number" or type(func) ~= "function" then
		return false
	end
	return E:ScheduleTimer(func, delay)
end

-- Matches real ElvUI's own E.TimeFormats/E:GetTimeInfo exactly (source/
-- ElvUI-vanilla/ElvUI/Core/math.lua) -- Core/Cooldowns.lua uses this to
-- format a cooldown's remaining time. [x][1] is real ElvUI's own longer/
-- tooltip-style variant; [x][2] (what Cooldowns.lua actually uses) is the
-- compact form. Indices 5/6 (mmss/hhmm) back the optional hhmm/mmss args
-- Cooldowns.lua passes for its duration-format thresholds. Real ElvUI's
-- own global Cooldown Text defaults (P["cooldown"]) have no hhmm/mmss
-- fields at all, only threshold + the 5 colors -- those field names exist
-- there only on separate, unrelated per-module cooldown sub-tables
-- (P["bags"]["cooldown"], P["auras"]["cooldown"], for per-icon bag/aura
-- cooldown text).
E.TimeFormats = {
	[0] = {"%dd", "%dd"},
	[1] = {"%dh", "%dh"},
	[2] = {"%dm", "%dm"},
	[3] = {"%ds", "%d"},
	[4] = {"%.1fs", "%.1f"},
	[5] = {"%d:%02d", "%d:%02d"}, --mmss
	[6] = {"%d:%02d", "%d:%02d"}, --hhmm
}

-- Real ElvUI's own `E.TimeColors` (source/ElvUI-vanilla/ElvUI/Core/
-- math.lua), converted from its colour-escape strings to plain r/g/b so
-- this project's `SetTextColor` call sites can use it directly.
--
-- These are HARDCODED in real ElvUI and have NO config anywhere -- both
-- its Auras module and its unit-frame auras index this table directly.
-- Only the COOLDOWN SPIRAL text is configurable there (`E.db.cooldown.*Color`,
-- a separate file-local table in its own Core/Cooldowns.lua). Aura text
-- reads these fixed values instead of a per-profile config field, so it
-- matches real ElvUI exactly with no invented setting a real profile
-- could never drive.
--   |cffeeeeee = 238/255 for days/hours/minutes/seconds
--   |cfffe0000 = 254/255 red for "expiring"
--   |cff909090 / |cff707070 for the optional mm:ss / hh:mm formats
E.TimeColors = {
	[0] = { 238/255, 238/255, 238/255 },
	[1] = { 238/255, 238/255, 238/255 },
	[2] = { 238/255, 238/255, 238/255 },
	[3] = { 238/255, 238/255, 238/255 },
	[4] = { 254/255, 0, 0 },
	[5] = { 144/255, 144/255, 144/255 }, --mmss
	[6] = { 112/255, 112/255, 112/255 }, --hhmm
}

local Compat = ElvUI.Compat
local DAY, HOUR, MINUTE = 86400, 3600, 60
local DAYISH, HOURISH, MINUTEISH = HOUR * 23.5, MINUTE * 59.5, 59.5
local HALFDAYISH, HALFHOURISH, HALFMINUTEISH = DAY / 2 + 0.5, HOUR / 2 + 0.5, MINUTE / 2 + 0.5

-- Routed through Compat.mod, not a cached `math.mod` local like real
-- ElvUI's own file does -- math.mod doesn't exist on UA's Lua 5.1 (see
-- Compat.lua's own note on this).
function E:GetTimeInfo(s, threshhold, hhmm, mmss)
	local mod = Compat.mod
	if s < MINUTE then
		if s >= threshhold then
			return math.floor(s), 3, 0.51
		else
			return s, 4, 0.051
		end
	elseif s < HOUR then
		if mmss and s < mmss then
			return s / MINUTE, 5, 0.51, mod(s, MINUTE)
		else
			local minutes = math.floor((s / MINUTE) + .5)
			if hhmm and s < (hhmm * MINUTE) then
				return s / HOUR, 6, minutes > 1 and (s - (minutes * MINUTE - HALFMINUTEISH)) or (s - MINUTEISH), mod(minutes, MINUTE)
			else
				return math.ceil(s / MINUTE), 2, minutes > 1 and (s - (minutes * MINUTE - HALFMINUTEISH)) or (s - MINUTEISH)
			end
		end
	elseif s < DAY then
		if mmss and s < mmss then
			return s / MINUTE, 5, 0.51, mod(s, MINUTE)
		elseif hhmm and s < (hhmm * MINUTE) then
			local minutes = math.floor((s / MINUTE) + .5)
			return s / HOUR, 6, minutes > 1 and (s - (minutes * MINUTE - HALFMINUTEISH)) or (s - MINUTEISH), mod(minutes, MINUTE)
		else
			local hours = math.floor((s / HOUR) + .5)
			return math.ceil(s / HOUR), 1, hours > 1 and (s - (hours * HOUR - HALFHOURISH)) or (s - HOURISH)
		end
	else
		local days = math.floor((s / DAY) + .5)
		return math.ceil(s / DAY), 0, days > 1 and (s - (days * DAY - HALFDAYISH)) or (s - DAYISH)
	end
end

-- ===========================================================================
-- Shared action-button styling, used by both Modules/ActionBars.lua and
-- Modules/PetBar.lua, which need the identical construction. A single
-- place means a fix (like the missing-edgeFile bug below) only needs to
-- happen once.
-- ===========================================================================

-- Colors below are a PIXEL MEASUREMENT of real ElvUI's action bars, not a
-- read of its source: sampling scanlines across both UIs side by side gave
--
--   real ElvUI, bar backdrop panel fill  RGB 26,26,26   (flat)
--   real ElvUI, button border            RGB  0, 0, 0   (1px, all round)
--   real ElvUI, button fill              RGB 19,19,19 at the top,
--                                            17,17,17 at the bottom
--
-- 26/255 = 0.102 = `E.media.backdropcolor` {.1,.1,.1} exactly. The button's
-- vertical 19->17 falloff is NOT a second color: real ElvUI builds action
-- buttons with `E:CreateBackdrop(button, "Default", true)` (their
-- Modules/ActionBars/ActionBars.lua), whose third argument is `glossTex`
-- -- so the SAME {.1,.1,.1} tint is applied to `Media/Textures/
-- normTex2.tga` instead of a flat white pixel, and that file is a 256x32
-- vertical gradient running 190 (top) -> 168 (bottom). 25.5 * 190/255 =
-- 19.0 and 25.5 * 168/255 = 16.8 -- i.e. the measured 19->17 to the byte.
-- That is the whole recipe; there is no third tone.
--
-- A THREE-concentric-frame construction (an outer 1px near-black ring, a
-- 2px MID-GRAY ring at 0.18/RGB 46, and a 0.1 fill) does NOT match the
-- reference: real ElvUI has no gray ring at all, and its fill is DARKER
-- than the bar panel behind it (17 vs 26) rather than the same 0.1 as the
-- panel -- matching that shade relationship is what makes buttons read as
-- "dark holes punched into a panel" instead of "gray outlines drawn on a
-- panel".
--
-- Real ElvUI's `E:SetTemplate` (Core/toolkit.lua) with the default
-- `pixelPerfect = true` (their Settings/Private.lua) is a SINGLE frame
-- with one backdrop -- the extra `iborder`/`oborder` frames in that
-- function only exist on the non-pixel-perfect path, which is not the
-- default and not what this recipe matches.
-- EXPORTED so the Skins module can point its own `S.WIDGET_COLOR`/
-- `S.BORDER_COLOR` design tokens straight at these tables instead of
-- restating the numbers. A skinned edit box, dropdown box and button then
-- cannot drift apart by construction (see Modules/Skins/Skins.lua's own
-- "DESIGN TOKENS" block). Kept HERE, not there, because this file is the
-- lower layer: ActionBars/PetBar/Auras all use these without the Skins
-- module necessarily being loaded.
Util.BORDER_COLOR = { 0, 0, 0, 1 }          -- real: E.media.bordercolor
Util.BACKDROP_COLOR = { 0.1, 0.1, 0.1, 1 }  -- real: E.media.backdropcolor
local BORDER_COLOR = Util.BORDER_COLOR
local BACKDROP_COLOR = Util.BACKDROP_COLOR

-- Real ElvUI resolves this through LSM from the PRIVATE `V.general.glossTex`
-- ("ElvUI Norm" by default) into `E.media.glossTex`; Init.lua does the same
-- for us. Fallback path is the same file, spelled out literally, for the
-- case where this runs before OnInitialize (or LSM is missing) -- the file
-- is vendored at `target/ElvUI/Media/Textures/normTex2.tga`, and custom
-- addon textures render fine on UA.
local GLOSS_TEX_FALLBACK = "Interface\\AddOns\\ElvUI\\Media\\Textures\\normTex2"

local function GlossTexture()
	local E = ElvUI and ElvUI[1]
	if E and E.media and E.media.glossTex then return E.media.glossTex end
	return GLOSS_TEX_FALLBACK
end

-- Real ElvUI's frame-template API (its Core/toolkit.lua `E:SetTemplate`),
-- narrowed to what this project can honor. Three template names, and they
-- are the vocabulary the DB speaks in -- `E.db.datatexts.panelTransparency`
-- and `panelBackdrop` are stored as booleans precisely because upstream maps
-- them onto these names:
--
--   "Transparent"  fill = E.db.general.backdropfadecolor (alpha honored)
--   "Default"      fill = E.db.general.backdropcolor, alpha forced to 1
--   "NoBackdrop"   no backdrop at all
--
-- Border is always `E.db.general.bordercolor` (theme-driven, written by
-- E:SetupTheme). `glossTex` swaps the flat fill texture for the gloss one,
-- as upstream does for its "Default" panels.
--
-- ONLY EVER CALL THIS ON A FRAME WE CREATED OURSELVES. On a native Blizzard
-- frame, SetBackdrop/SetBackdropColor is not per-instance on UA -- the XML
-- <Backdrop> is a template-level shared resource, so one call can visibly
-- alter an unrelated, untouched window (measured: a Sound Options slider
-- wiped the trough off both Interface Options sliders). The per-instance
-- tool for a native frame is DisableDrawLayer("BACKGROUND")/("BORDER").
--
-- Deliberately NOT ported from upstream: the E.mult/pixelPerfect branch and
-- the iborder/oborder child frames (no pixel-perfect system here), and the
-- E.frames registry used for live re-coloring (this project re-reads colors
-- on /reload like everywhere else). `bgFile` is always paired with
-- `edgeFile`+`edgeSize`: an incomplete backdrop table renders gold/tan on
-- UA, see Util.CreateButtonBorder below.
function E:SetTemplate(frame, template, glossTex)
	if not frame then return end

	frame.template = template

	if template == "NoBackdrop" then
		pcall(frame.SetBackdrop, frame, nil)
		return
	end

	pcall(frame.SetBackdrop, frame, {
		bgFile = glossTex and GlossTexture() or "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})

	local general = E.db and E.db.general
	local fill = general and (template == "Transparent" and general.backdropfadecolor or general.backdropcolor)
	local border = general and general.bordercolor

	if fill then
		pcall(frame.SetBackdropColor, frame, fill.r, fill.g, fill.b,
			template == "Transparent" and (fill.a or 0.8) or 1)
	else
		pcall(frame.SetBackdropColor, frame, BACKDROP_COLOR[1], BACKDROP_COLOR[2], BACKDROP_COLOR[3], 1)
	end

	if border then
		pcall(frame.SetBackdropBorderColor, frame, border.r, border.g, border.b, 1)
	else
		pcall(frame.SetBackdropBorderColor, frame, BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], 1)
	end
end

-- Builds real ElvUI's button backdrop (gloss-textured {.1,.1,.1} fill +
-- 1px black border) directly on `button` -- idempotent (checks
-- `button.elvBackdrop`), safe to call on every periodic resweep pass,
-- same guard convention the rest of this project's button styling
-- already uses.
--
-- `button.elvBackdrop` stays the name of the one frame this creates, so
-- the existing consumers that recolor it (Skins/Blizzard/Character.lua's
-- item-quality slot borders, Skins.lua's `S:DumpTabs`) keep working --
-- and now they recolor the SAME single border real ElvUI recolors,
-- instead of an extra outer ring that only existed here.
--
-- `bgFile` is ALWAYS paired with `edgeFile`+`edgeSize` in the backdrop
-- below -- a `SetBackdrop` call passing only `bgFile` renders every
-- button (icons, empty slots, hotkey text background) as a uniform
-- GOLD/tan color on UA instead of the intended dark tones, consistent
-- with `SetBackdrop` falling back to some default/placeholder appearance
-- when given an incomplete table on this client. The backdrop table is
-- kept to the exact {bgFile, edgeFile, edgeSize} shape proven on UA --
-- real ElvUI additionally passes `tile`/`tileSize`/`insets`, deliberately
-- not copied here, since an untested table shape is precisely what causes
-- the gold-tint bug.
--
-- OPTIONAL INSETS (for `S:StyleTab`): by default the border wraps the
-- button's FULL footprint (`insetX`/`insetTop`/`insetBottom` all 0 --
-- byte-identical geometry to every existing call site). Native TAB
-- buttons need something different: their footprint is
-- much wider/taller than the visible tab, and consecutive tabs deliberately
-- OVERLAP each other (FriendsFrameTab<i> is anchored `LEFT` to the previous
-- tab's `RIGHT` at x=-14, SpellBookFrameTabButton2 at x=-20), so a
-- full-footprint border makes neighbouring tabs' boxes collide -- exactly
-- what produced the Who/Guild seam. Real ElvUI's own `S:HandleTab` solves
-- this by insetting the backdrop instead (`E:Point(tab.backdrop, "TOPLEFT",
-- 10, -1)` / `"BOTTOMRIGHT", -10, 3`), which is what these parameters
-- exist for. `insetBottom` defaults to `insetTop`.
function Util.CreateButtonBorder(button, insetX, insetTop, insetBottom)
	if not button or button.elvBackdrop then return end

	insetX = tonumber(insetX) or 0
	insetTop = tonumber(insetTop) or 0
	insetBottom = tonumber(insetBottom) or insetTop

	local okLevel, level = pcall(button.GetFrameLevel, button)
	local buttonLevel = (okLevel and tonumber(level)) or 1
	-- The backdrop only needs ONE level of headroom below the button now
	-- (it used to need three), but the >= 4 clamp is kept exactly as it
	-- was: several skins anchor their own extra frames relative to a
	-- button's level and were tuned against this floor -- lowering it is
	-- a separate, unrelated change with its own regression surface.
	if buttonLevel < 4 then
		pcall(button.SetFrameLevel, button, 4)
		buttonLevel = 4
	end

	local okBackdrop, backdrop = pcall(CreateFrame, "Frame", nil, button)
	if okBackdrop and backdrop then
		-- Real ElvUI: `button.backdrop:SetAllPoints()` -- the backdrop
		-- covers the button's exact footprint, and the 1px black edge sits
		-- ON that footprint (nothing sticks out). Written as the explicit
		-- 2-point form so the tab insets above still apply.
		pcall(backdrop.SetPoint, backdrop, "TOPLEFT", button, "TOPLEFT", insetX, -insetTop)
		pcall(backdrop.SetPoint, backdrop, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -insetX, insetBottom)
		pcall(backdrop.SetFrameLevel, backdrop, buttonLevel - 1)
		pcall(backdrop.SetBackdrop, backdrop, {
			bgFile = GlossTexture(),
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		pcall(backdrop.SetBackdropColor, backdrop, BACKDROP_COLOR[1], BACKDROP_COLOR[2], BACKDROP_COLOR[3], 1)
		pcall(backdrop.SetBackdropBorderColor, backdrop, BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], 1)
		button.elvBackdrop = backdrop
	end
end

-- TexCoords (left, right, top, bottom) of raid target marks 1-8 on a 4x4 icon
-- sheet: the grid FrameXML's SetRaidTargetIconTexture computes
-- (TargetFrame.lua), identical to the unit menu's tCoord values. Used for the
-- native UI-RaidTargetingIcons and for ElvUI's own Media/Textures/raidicons,
-- which real ElvUI crops with that same function. That global is not in UA's
-- API documentation, hence a table. Shared by Misc/RaidMarker.lua and the unit
-- frames' raid icon.
Util.RAID_TARGET_COORDS = {
	{ 0, 0.25, 0, 0.25 },
	{ 0.25, 0.5, 0, 0.25 },
	{ 0.5, 0.75, 0, 0.25 },
	{ 0.75, 1, 0, 0.25 },
	{ 0, 0.25, 0.25, 0.5 },
	{ 0.25, 0.5, 0.25, 0.5 },
	{ 0.5, 0.75, 0.25, 0.5 },
	{ 0.75, 1, 0.25, 0.5 },
}

-- Reskins a native `ItemButtonTemplate`-shaped slot in place: blanks the
-- gold "quickslot" NormalTexture and puts `CreateButtonBorder`'s own
-- bordered surface under the icon. Shared by the bag/bank grid
-- (`Modules/Bags/Bags.lua`) and `MerchantFrame`'s vendor/buyback slots
-- (`Modules/Skins/Blizzard/Merchant.lua`) -- the exact same native
-- template, same fix. Lives here rather than in either module's own file,
-- or in `Skins.lua`, because of load order:
-- `Modules\Bags\Load_Bags.xml` loads BEFORE `Modules\Skins\Load_Skins.xml`
-- (`Modules/Load_Modules.xml`), so a Skins-module home would force Bags
-- into a lazy per-call `E:GetModule("Skins")` lookup -- `Core/Util.lua`
-- loads before every module (`ElvUI.toc`) and is already a dependency of
-- both (both already call `Util.CreateButtonBorder` directly).
--
-- Deliberately does NOT touch the pushed/highlight textures: those are
-- this project's prime suspect for the gold tint seen across every button
-- on UA, and a bag grid alone is over a hundred buttons of exposure.
function Util.SkinItemButton(button)
	if not button or button.elvSkinned then return end
	button.elvSkinned = true

	-- Blanking the normal texture is not enough on UA: the native slot art
	-- survives an empty SetNormalTexture (same family as the unreliable
	-- SetTexture(nil) there) and keeps drawing over the icon, which reads
	-- as a dimmed, washed-out button. Hiding the texture OBJECT is the
	-- instance-level tool that works on both clients.
	pcall(button.SetNormalTexture, button, "")
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then
		pcall(normal.SetAlpha, normal, 0)
		pcall(normal.Hide, normal)
	end

	local icon = _G[button:GetName().."IconTexture"]
	if icon then
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	end

	Util.CreateButtonBorder(button)

	-- Real ElvUI's own hover look (E:StyleButton) is NOT applied here. Its
	-- white 30% overlay, handed to SetHighlightTexture, renders CONSTANTLY
	-- on UA rather than only while the mouse is over the button: every
	-- slot in the grid turned into a washed-out grey square. The native
	-- highlight is left in place instead. Don't retry without a
	-- client-side change.
end

-- Hover/pushed/checked textures -- matches real ElvUI's own
-- E:StyleButton (source/ElvUI-vanilla/ElvUI/Core/toolkit.lua:290-321)
-- exactly, including its solid-color SetTexture(r,g,b,a) shorthand (no
-- file needed for a flat color -- a different API than SetBackdrop, not
-- subject to the missing-edgeFile bug above).
--
-- NOT CALLED from either Modules/ActionBars.lua or Modules/PetBar.lua --
-- prime suspect for a gold/tan tint that appeared across every button on
-- UA (both modules, since both shared this call) once it reached that
-- client. The PUSHED texture's color, `{0.9, 0.8, 0.1, 0.3}`, is a literal
-- gold/yellow tone, matching the symptom exactly -- theory: on UA, the
-- pushed (and/or hover/checked) texture isn't gated to its normal
-- interaction state and instead renders constantly. Hover-highlight
-- effects are believed to work on UA elsewhere, if unconfirmed here --
-- if that holds up, SetHighlightTexture specifically is less suspect than
-- SetPushedTexture/SetCheckedTexture, and would be the first one worth
-- re-testing in isolation. Left defined here (not deleted) in case the
-- real cause turns out to be something else entirely -- don't re-wire the
-- calls back in without confirming which specific texture (if any) was
-- actually responsible.
function Util.CreateButtonHoverTextures(button)
	if not button then return end

	if button.SetHighlightTexture and not button.elvHoverStyled then
		local ok, hover = pcall(button.CreateTexture, button)
		if ok and hover then
			pcall(hover.SetTexture, hover, 1, 1, 1, 0.3)
			pcall(hover.SetPoint, hover, "TOPLEFT", button, "TOPLEFT", 1, -1)
			pcall(hover.SetPoint, hover, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
			pcall(button.SetHighlightTexture, button, hover)
			button.elvHoverStyled = true
		end
	end
	if button.SetPushedTexture and not button.elvPushedStyled then
		local ok, pushed = pcall(button.CreateTexture, button)
		if ok and pushed then
			pcall(pushed.SetTexture, pushed, 0.9, 0.8, 0.1, 0.3)
			pcall(pushed.SetPoint, pushed, "TOPLEFT", button, "TOPLEFT", 1, -1)
			pcall(pushed.SetPoint, pushed, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
			pcall(button.SetPushedTexture, button, pushed)
			button.elvPushedStyled = true
		end
	end
	if button.SetCheckedTexture and not button.elvCheckedStyled then
		local ok, checked = pcall(button.CreateTexture, button)
		if ok and checked then
			pcall(checked.SetTexture, checked, 1, 1, 1)
			pcall(checked.SetAlpha, checked, 0.3)
			pcall(checked.SetPoint, checked, "TOPLEFT", button, "TOPLEFT", 1, -1)
			pcall(checked.SetPoint, checked, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
			pcall(button.SetCheckedTexture, button, checked)
			button.elvCheckedStyled = true
		end
	end
end

-- Matches real ElvUI's own per-bar container padding formula exactly
-- (`AB:PositionAndSizeBar`, source/ElvUI-vanilla/ElvUI/Modules/
-- ActionBars/ActionBars.lua:74-75): `(backdrop and (E.Border +
-- backdropSpacing) or E.Spacing) * 2`, i.e. NOT one flat padding value
-- for every bar -- it depends on the bar's OWN `backdrop` setting.
-- `ELVUI_SPACING`/`ELVUI_BORDER` approximate real ElvUI's own
-- `E.Spacing`/`E.Border` (`Core/pixelperfect.lua:61-63`: `E.mult =
-- 768/height/scale`, which computes out to exactly 1 for most real
-- resolutions with `autoScale` on, since the two `768/height` terms
-- cancel) as FIXED constants -- NOT computed from the user's actual
-- resolution/UI scale, since this project has no pixel-perfect system
-- of its own; may be off on an unusual resolution/scale combination.
local ELVUI_SPACING = 1
local ELVUI_BORDER = 2

function Util.BarPadding(barSettings)
	if barSettings.backdrop then
		local backdropSpacing = barSettings.backdropSpacing or barSettings.buttonspacing
		return ELVUI_BORDER + backdropSpacing
	end
	return ELVUI_SPACING
end

-- Runs `fn` every `interval` seconds, up to `maxRuns` times total, then
-- cancels itself -- for the "periodic resweep" pattern used throughout
-- this project (Modules/ActionBars.lua's HideChrome/StyleButton,
-- Modules/PetBar.lua's own StyleButton resweep, Modules/Minimap.lua's
-- UpdateIcons) to catch native frames Blizzard creates or resets LAZILY
-- after login (ExhaustionTick, ActionButton NormalTexture, GameTimeFrame's
-- strata reset, ...). Bounded rather than an indefinite
-- `E:ScheduleRepeatingTimer(fn, 3)`, since the native resets being caught
-- only ever happen once, in a short window after login -- 10 runs at a 3s
-- interval (30s total) is the default every call site uses; not doing
-- unnecessary work forever, not fixing a visible bug.
function Util.ScheduleLimitedSweep(fn, interval, maxRuns)
	local runs = 0
	local handle
	handle = E:ScheduleRepeatingTimer(function()
		runs = runs + 1
		fn()
		if runs >= maxRuns then
			E:CancelTimer(handle)
		end
	end, interval)
	return handle
end

-- Hand-rolled status bar -- a plain Frame plus two textures (background +
-- fill), NOT the native `CreateFrame("StatusBar", ...)` widget. Ported
-- from source/UnrealUI/modules/unitframes.lua's own `U.CreateStatusBar`,
-- for the UnitFrames module (the native oUF framework had to be abandoned
-- there over a UA incompatibility). UnrealUI's own header comment
-- documents WHY they don't trust the native widget on this client: their
-- first unit frames built one, handed the fill texture to
-- SetStatusBarTexture, and the result on screen was a fixed-size block
-- hanging outside the frame's own bounds instead of a bar that grows/
-- shrinks with SetValue -- the fill was never laid out from the bar's
-- value at all. This project's own DataBars/XPBar.lua DOES use the native
-- StatusBar widget successfully -- so this isn't a blanket "native
-- StatusBar is broken" claim, just the safer, already-proven choice for a
-- brand new, high-risk module like UnitFrames.
--
-- Methods (SetMinMaxValues/GetMinMaxValues/SetValue/GetValue/
-- SetOrientation) are plain FUNCTION-FIELD ASSIGNMENTS on the frame table
-- returned by CreateFrame -- e.g. `bar.SetValue = BarSetValue` -- never a
-- metatable swap. This is deliberate, not incidental: swapping an
-- existing frame object's metatable to point `__index` at another frame
-- is exactly the kind of operation that turned out to be broken on UA for
-- oUF -- a plain field assignment on an already-live table has no such
-- risk, on either client.
--
-- options: width/height (numbers), background/color ({r,g,b,a} arrays,
-- default near-black / opaque white), texture (a file path, defaults to
-- a flat white pixel so SetStatusBarColor-equivalent tinting works),
-- orientation ("VERTICAL" or default horizontal), name (optional frame
-- name).
local function UpdateStatusBarFill(bar)
	local fill = bar.barFillTexture
	if not fill then return end

	local size
	if bar.barVertical then
		size = tonumber(bar:GetHeight())
	else
		size = tonumber(bar:GetWidth())
	end
	size = size or 0

	local range = (bar.barMax or 0) - (bar.barMin or 0)
	local extent = 0
	if range > 0 and size > 0 then
		extent = size / range * ((bar.barValue or 0) - (bar.barMin or 0))
	end

	if extent < 0 then extent = 0 end
	if extent > size then extent = size end

	if extent <= 0 then
		fill:Hide()
		return
	end

	fill:ClearAllPoints()
	if bar.barVertical then
		fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(size - extent))
		fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	else
		fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
		fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -(size - extent), 0)
	end
	fill:Show()
end

local function BarSetMinMaxValues(self, minimum, maximum)
	minimum = tonumber(minimum) or 0
	maximum = tonumber(maximum) or 0
	if self.barMin == minimum and self.barMax == maximum then return end
	self.barMin = minimum
	self.barMax = maximum
	UpdateStatusBarFill(self)
end

local function BarGetMinMaxValues(self)
	return self.barMin, self.barMax
end

local function BarSetValue(self, value)
	value = tonumber(value) or 0
	if self.barValue == value then return end
	self.barValue = value
	UpdateStatusBarFill(self)
end

local function BarGetValue(self)
	return self.barValue
end

local function BarSetOrientation(self, mode)
	local vertical = (type(mode) == "string" and string.upper(mode) == "VERTICAL")
	if self.barVertical == vertical then return end
	self.barVertical = vertical
	UpdateStatusBarFill(self)
end

function Util.CreateStatusBar(parent, options)
	options = options or {}

	local bar = CreateFrame("Frame", options.name, parent or UIParent)
	bar:SetWidth(options.width or 100)
	bar:SetHeight(options.height or 12)

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Buttons\\WHITE8x8")
	bg:SetAllPoints(bar)
	local bgColor = options.background or {0.1, 0.1, 0.1, 1}
	bg:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
	bar.barBgTexture = bg

	local fill = bar:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(options.texture or "Interface\\Buttons\\WHITE8x8")
	local fillColor = options.color or {1, 1, 1, 1}
	fill:SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 1)
	bar.barFillTexture = fill

	bar.barMin, bar.barMax, bar.barValue = 0, 1, 1
	bar.barVertical = (options.orientation == "VERTICAL")

	bar.SetMinMaxValues = BarSetMinMaxValues
	bar.GetMinMaxValues = BarGetMinMaxValues
	bar.SetValue = BarSetValue
	bar.GetValue = BarGetValue
	bar.SetOrientation = BarSetOrientation

	UpdateStatusBarFill(bar)
	return bar
end

function Util.SetStatusBarColor(bar, r, g, b, a)
	if not bar or not bar.barFillTexture then return end
	bar.barFillTexture:SetVertexColor(r, g, b, a or 1)
end

-- Live texture setter -- CreateStatusBar's own `options.texture` only ever
-- applied at CONSTRUCTION time, no way to change it afterward. Backs the
-- LSM statusbar-texture config option (UnitFrames/Castbar/MirrorTimers),
-- mirroring how font selection is wired in project-wide even though
-- custom fonts don't render on UA either: LSM/SetTexture themselves work
-- fine, only EXTERNAL addon-shipped asset FILES fail to load on this
-- client, so this is expected to be no better than the current flat look
-- for any CUSTOM entry, but "ElvUI Blank" -- a NATIVE
-- Interface\BUTTONS\WHITE8x8 path -- works, and is this setting's default.
function Util.SetStatusBarTexture(bar, path)
	if not bar or not bar.barFillTexture or not path then return end
	pcall(bar.barFillTexture.SetTexture, bar.barFillTexture, path)
end

function Util.SetStatusBarBackgroundColor(bar, r, g, b, a)
	if not bar or not bar.barBgTexture then return end
	bar.barBgTexture:SetVertexColor(r, g, b, a or 1)
end

-- Ported verbatim from real ElvUI's own E:TableToLuaString
-- (source/ElvUI-vanilla/ElvUI/Core/core.lua) -- a plain, readable
-- Lua table LITERAL string, NOT the compressed/AceSerializer+LibCompress+
-- LibBase64 "text" export format real ElvUI's own Distributor also
-- offers (this project doesn't vendor either of those libraries, and the
-- plain-table format is the one that matters for loading a plain-table
-- SavedVariables profile as-is). Deliberately matches real ElvUI's own
-- output shape exactly
-- (same `["key"] = value,` / nested-brace layout, same string escaping)
-- so a profile exported from THIS addon and one exported from real
-- ElvUI-vanilla's own "Export as Lua Table" option are interchangeable
-- as plain Lua source -- Core/Profiles.lua's own ImportProfile can
-- `loadstring` either one back into a table.
function Util.TableToLuaString(inTable)
	if type(inTable) ~= "table" then return nil end

	local ret = "{\n"
	local function recurse(t, level)
		local i, v
		for i, v in pairs(t) do
			ret = ret..string.rep("    ", level).."["
			if type(i) == "string" then
				ret = ret.."\""..i.."\""
			else
				ret = ret..i
			end
			ret = ret.."] = "

			if type(v) == "number" then
				ret = ret..v..",\n"
			elseif type(v) == "string" then
				ret = ret.."\""..string.gsub(string.gsub(string.gsub(v, "\\", "\\\\"), "\n", "\\n"), "\"", "\\\"").."\",\n"
			elseif type(v) == "boolean" then
				ret = ret..(v and "true," or "false,").."\n"
			elseif type(v) == "table" then
				ret = ret.."{\n"
				recurse(v, level + 1)
				ret = ret..string.rep("    ", level).."},\n"
			else
				ret = ret.."\""..tostring(v).."\",\n"
			end
		end
	end

	recurse(inTable, 1)
	ret = ret.."}"
	return ret
end
