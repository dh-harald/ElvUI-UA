-- Profile defaults -- `P` (Engine[4]), the per-profile settings table.
--
-- THE ONE AND ONLY place a `P.*` key may be declared. Module files read
-- `E.db.*` (the live merged table Init.lua builds) and never assign to `P`:
-- a default declared next to the code that consumes it cannot be diffed
-- against real ElvUI's own schema, which is what
-- `scripts/check-config.lua` exists to do.
--
-- Field names and shapes follow real ElvUI's own
-- source/ElvUI-vanilla/ElvUI/Settings/Profile.lua. That matters more than
-- the values: AceDB-3.0 omits any field equal to its registered default
-- when writing SavedVariables, so an imported real profile is SPARSE, and
-- every key we spell differently silently falls back to our own value.
-- Deliberate value deviations are noted inline and registered in
-- `scripts/config-exceptions.lua`.
--
-- Loads before Core/ and Modules/ (ElvUI.toc), so every module sees a
-- fully populated table at its own file-load time.

local E, L, V, P, G = unpack(ElvUI)

P.gridSize = 64

-- Per-mover saved positions, keyed by mover name. Filled at runtime by
-- Core/Movers.lua; empty here so `E.db.movers` always exists.
P.movers = {}

-- DELIBERATELY NOT DECLARED HERE, matching real ElvUI exactly: the Install
-- Wizard's own bookkeeping fields live directly on `E.db` / `E.private`
-- WITHOUT a default (real ElvUI's Core/install.lua writes `E.db.lowresolutionset`,
-- `E.db.layoutSet`, `E.private.install_complete` and `E.private.theme` the same
-- way, and declares none of them). `nil` is the intended initial state and is
-- falsy exactly where the code tests it, so declaring `false` bought nothing and
-- only registered as an invented key against the real schema. Waived in
-- scripts/config-exceptions.lua's `reads` table where the code reads one back.

-- ---------------------------------------------------------------------
-- General
-- ---------------------------------------------------------------------

-- `bordercolor`/`backdropcolor`/`backdropfadecolor`/`valuecolor` are
-- named-key `{r=,g=,b=}` tables, matching real ElvUI's own
-- `E:GetColor` shape (Core/Install.lua's `E:SetupTheme` is the only
-- writer) -- NOT the positional `{[1],[2],[3],[4]}` shape
-- `Core/Util.lua`'s `Util.BORDER_COLOR`/`BACKDROP_COLOR` use internally;
-- those two stay positional (many existing call sites index them that
-- way) and get their `[1..3]` slots written FROM these named fields by
-- `E:SetupTheme`, not the other way around.
--
-- `bordercolor`/`backdropcolor` default to this project's CURRENT
-- shipped tone (matching `Util.BORDER_COLOR`/`BACKDROP_COLOR`'s own
-- defaults exactly) so a profile that never runs the Theme step renders
-- identically to before this field existed. All three color fields are
-- read by `E:SetTemplate` (Core/Util.lua).
--
-- `backdropfadecolor` is real ElvUI's own default value. It used to carry
-- the "dark" THEME preset's .054 instead, which was harmless only while
-- nothing read the field -- `E:SetTemplate` reads it now, so the drift
-- would have been visible on every transparent panel. The theme presets
-- themselves (`E:SetupTheme`, Core/Install.lua) keep real ElvUI's own
-- per-preset values, dark included.
--
-- Only `backdropfadecolor` carries an `a` key, because that is the only one
-- real ElvUI gives an alpha to and the only one whose alpha anything reads
-- (`E:SetTemplate`'s "Transparent" branch). The other three used to declare
-- `a = 1`, which no code ever looked at and which registered as three invented
-- keys against the real schema.
--
-- `valuecolor` is real ElvUI's UI ACCENT color, and the value below is its own
-- default -- the colour before any install-wizard theme is applied. Read here
-- by every data text's VALUE half, through `E.valueColorUpdateFuncs`
-- (`Init.lua`), and re-derived by `E:UpdateValueColor`.
--
-- An earlier note here stated it does NOT colour datatext values. That was
-- wrong, and the reason it looked that way is worth keeping: a data text never
-- NAMES this field, it registers a callback that receives the hex, so a grep
-- for `valuecolor` finds every other consumer (movers, chat tab text, skin
-- mouseover borders, Microbar and Bags highlights) but none of the data texts.
-- Full account in docs/roadmap.md.
--
-- `bottomPanel` is the Layout module's bottom screen strip. There is
-- deliberately NO `topPanel` key: real ElvUI does not declare one either,
-- so nil is the intended "off" default and declaring it would be an EXTRA
-- key. Waived in scripts/config-exceptions.lua's `reads` table.
P.general = {
	bordercolor = { r = 0, g = 0, b = 0 },
	backdropcolor = { r = 0.1, g = 0.1, b = 0.1 },
	backdropfadecolor = { r = 0.06, g = 0.06, b = 0.06, a = 0.8 },
	valuecolor = { r = 254/255, g = 123/255, b = 44/255 },
	autoRoll = false,
	bottomPanel = true,

	-- Number abbreviation, read by `E:ShortValue` (Core/Util.lua): how a value
	-- like 1700 is shortened, and to how many decimals. Real ElvUI's own
	-- defaults and value set.
	numberPrefixStyle = "ENGLISH",
	decimalLength = 1,
	minimap = {
		size = 176,
		locationText = "MOUSEOVER",
		resetZoom = { enable = false, time = 3 },
		icons = {
			calendar = { position = "TOPRIGHT", scale = 1, xOffset = 0, yOffset = 0 },
			mail = { position = "TOPRIGHT", scale = 1, xOffset = 3, yOffset = 4 },
			battlefield = { position = "BOTTOMRIGHT", scale = 1, xOffset = 3, yOffset = 0 },
		},
	},
}

-- ---------------------------------------------------------------------
-- Cooldown text
-- ---------------------------------------------------------------------
-- Real ElvUI's own top-level `P["cooldown"]` field set: threshold plus the
-- five day/hour/minute/second/expiring colors. Core/Cooldowns.lua reads
-- nothing else from here.
--
-- The duration-format fields below reuse real ElvUI's field NAMES but sit
-- on this top-level table rather than on its per-module `bags`/
-- `nameplates`/`auras` `cooldown` sub-tables, where they are inert
-- leftovers (its own `E:GetTimeInfo` is never called with the 3rd/4th
-- argument). Here they ARE wired up: `E:GetTimeInfo` (Core/Util.lua)
-- accepts optional `hhmm`/`mmss` args and returns format ids 5 (`M:SS`)
-- and 6 (`H:MM`).
--
-- Semantics come from `E:GetTimeInfo` itself:
--   mmssThreshold  SECONDS. While remaining < this, show `M:SS`
--                  (a 30-minute buff reads `30:00` instead of `30m`).
--   hhmmThreshold  MINUTES. While remaining < this many minutes, show `H:MM`.
--   -1             disabled (real ElvUI's own sentinel for both).
-- `checkSeconds` is stored for round-tripping but NOT read and NOT exposed
-- in the config: nothing in the reference tree consumes it, so its exact
-- meaning can't be verified.
P.cooldown = {
	threshold = 3,
	expiringColor = { r = 1, g = 0, b = 0 },
	secondsColor = { r = 1, g = 1, b = 0 },
	minutesColor = { r = 1, g = 1, b = 1 },
	hoursColor = { r = 0.4, g = 1, b = 1 },
	daysColor = { r = 0.4, g = 0.4, b = 1 },

	checkSeconds = false,
	hhmmThreshold = -1,
	mmssThreshold = -1,
	hhmmColor = { r = 1, g = 1, b = 1 },
	mmssColor = { r = 1, g = 1, b = 1 },
}

-- ---------------------------------------------------------------------
-- Mirror timers (breath / fatigue / feign death)
-- ---------------------------------------------------------------------
-- Real ElvUI has no top-level `mirrortimers` table -- there the feature is
-- a SKIN flag (`V.skins.blizzard.mirrorTimers`). These two size fields are
-- a project extension, whitelisted in scripts/config-exceptions.lua.
P.mirrortimers = {
	width = 222,
	height = 18,
}

-- ---------------------------------------------------------------------
-- ActionBars
-- ---------------------------------------------------------------------
-- "MONOCHROMEOUTLINE" (not an empty string) is real ElvUI's own sentinel
-- domain for outlines; ActionBars.lua's ApplyFont translates "NONE" to ""
-- before calling SetFont, so the SAVED value domain stays identical to a
-- real profile's (NONE/OUTLINE/MONOCHROMEOUTLINE/THICKOUTLINE).
P.actionbar = {
	hotkeytext = true,

	-- Where the keybind text sits on a button, real ElvUI's own three fields
	-- and values. `hotkeyTextXOffset` is 0 upstream; this project used to
	-- hardcode -2, so the text shifts 2px right on a fresh profile.
	hotkeyTextPosition = "TOPRIGHT",
	hotkeyTextXOffset = 0,
	hotkeyTextYOffset = -3,
	macrotext = false,
	lockActionBars = true,
	font = "Homespun",
	fontSize = 10,
	fontOutline = "MONOCHROMEOUTLINE",
}

-- Per-bar defaults copied from real ElvUI's own bar1..bar5, which are NOT
-- uniform: bar3/bar5 are a 6-button single row, bar4 is a 12-button single
-- COLUMN (buttonsPerRow=1, a portrait bar), bar2 ships disabled, and only
-- bar4 defaults its bar-level backdrop panel to visible.
--
-- `showGrid` is a genuine real-ElvUI per-bar option here (Show Empty
-- Buttons), NOT a project addition -- ported straight from its own
-- Settings/Profile.lua, which declares `showGrid = true` for bar1-5
-- exactly like this. (barPet's own `showGrid` below IS a project
-- addition -- real ElvUI hardcodes the pet bar's grid unconditionally on
-- with no per-bar toggle at all; see scripts/config-exceptions.lua.)
P.actionbar.bar1 = {
	enabled = true,
	buttons = 12,
	buttonsPerRow = 12,
	buttonsize = 32,
	buttonspacing = 2,
	backdrop = false,
	alpha = 1,
	showGrid = true,
	backdropSpacing = 2,
}

P.actionbar.bar2 = {
	enabled = false,
	buttons = 12,
	buttonsPerRow = 12,
	buttonsize = 32,
	buttonspacing = 2,
	backdrop = false,
	alpha = 1,
	showGrid = true,
	backdropSpacing = 2,
}

P.actionbar.bar3 = {
	enabled = true,
	buttons = 6,
	buttonsPerRow = 6,
	buttonsize = 32,
	buttonspacing = 2,
	backdrop = false,
	alpha = 1,
	showGrid = true,
	backdropSpacing = 2,
}

P.actionbar.bar4 = {
	enabled = true,
	buttons = 12,
	buttonsPerRow = 1,
	buttonsize = 32,
	buttonspacing = 2,
	backdrop = true,
	alpha = 1,
	showGrid = true,
	backdropSpacing = 2,
}

P.actionbar.bar5 = {
	enabled = true,
	buttons = 6,
	buttonsPerRow = 6,
	buttonsize = 32,
	buttonspacing = 2,
	backdrop = false,
	alpha = 1,
	showGrid = true,
	backdropSpacing = 2,
}

-- `buttonsPerRow = 1` (a single vertical column) is real ElvUI's own
-- default here. Real ElvUI's `mouseover`/`point`/`widthMult`/`heightMult`/
-- `inheritGlobalFade` are deliberately not declared: Util.MergeTable copies
-- whatever keys a saved profile carries regardless, so omitting an
-- unimplemented field costs nothing for import fidelity. `backdropSpacing`
-- IS declared now -- `ElvUI.Util.BarPadding` was already reading it, so it
-- was an implemented field with no default and no control.
-- `showGrid` (project addition, see the bar1 comment above and
-- scripts/config-exceptions.lua) -- real ElvUI's pet bar always shows
-- empty slots with no way to turn it off; this project makes it a live
-- toggle, matching bar1-5's own UX instead of a silent exception to it.
P.actionbar.barPet = {
	enabled = true,
	buttons = _G.NUM_PET_ACTION_SLOTS or 10,
	buttonsPerRow = 1,
	buttonsize = 28,
	buttonspacing = 2,
	backdrop = true,
	alpha = 1,
	showGrid = true,
	backdropSpacing = 2,
}

-- `style` drives the active-stance highlight (the entire point of this
-- bar); the omitted fields are the same set as barPet's.
P.actionbar.barShapeShift = {
	enabled = true,
	style = "darkenInactive",
	buttons = _G.NUM_SHAPESHIFT_SLOTS or 10,
	buttonsPerRow = _G.NUM_SHAPESHIFT_SLOTS or 10,
	buttonsize = 32,
	buttonspacing = 2,
	backdrop = false,
	alpha = 1,
	backdropSpacing = 2,
}

-- ---------------------------------------------------------------------
-- Auras (the standalone BuffFrame replacement, not unit-frame auras)
-- ---------------------------------------------------------------------
-- This module's vocabulary is entirely different from a unit frame's aura
-- table: `wrapAfter`/`maxWraps`/`horizontalSpacing`/`verticalSpacing`, not
-- `perrow`/`xOffset`/`yOffset`.
--
--   size              icon edge length
--   wrapAfter         icons per row before wrapping
--   maxWraps          max number of rows -- together with wrapAfter this
--                     defines the MAXIMUM area the display can occupy,
--                     which is what the mover handle shows
--   horizontalSpacing gap between columns
--   verticalSpacing   gap between rows (16 because the duration text hangs
--                     BELOW each icon in this module)
--   growthDirection   STORED, NOT READ -- buffs grow left+down from
--                     TOPRIGHT, debuffs left+up from BOTTOMRIGHT
--   seperateOwn       STORED, NOT READ (real ElvUI's own spelling, typo
--                     included) -- every aura here is the player's own
--   sortMethod/sortDir  implemented (INDEX/TIME)
--
-- font/fontSize/fontOutline are STORED ONLY (`SetFont` is a no-op on UA)
-- and deliberately absent from the config UI, where they would read as
-- broken controls.
--
-- There is deliberately NO aura-text color setting: real ElvUI-vanilla has
-- none either -- its `E.TimeColors` is a hardcoded table, and this project
-- carries the same one (Core/Util.lua), read by `FormatRemain`.
--
-- The 8x4 / 8x2 grids deviate from real ElvUI's 12x3 / 12x1 (whitelisted).
-- The client's own buff index is 0-47, slots 0-31 helpful and 32-47 harmful
-- (source/UnrealAzeroth_LuaAPI/en/globals/Buff.md), so 32 buff and 16
-- debuff cells cover every slot that can exist while keeping both displays
-- narrow (8*32 + 7*6 = 298px) instead of one enormous row.
P.auras = {
	fadeThreshold = 5,

	font = "Homespun",
	fontSize = 10,
	fontOutline = "MONOCHROMEOUTLINE",
	countXOffset = 0,
	countYOffset = 0,
	timeXOffset = 0,
	timeYOffset = 0,

	buffs = {
		size = 32,
		growthDirection = "LEFT_DOWN",
		wrapAfter = 8,
		maxWraps = 4,
		horizontalSpacing = 6,
		verticalSpacing = 16,
		sortMethod = "TIME",
		sortDir = "-",
		seperateOwn = 1,
	},
	debuffs = {
		size = 32,
		growthDirection = "LEFT_DOWN",
		wrapAfter = 8,
		maxWraps = 2,
		horizontalSpacing = 6,
		verticalSpacing = 16,
		sortMethod = "TIME",
		sortDir = "-",
		seperateOwn = 1,
	},
}

-- ---------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------
-- Taken verbatim from real ElvUI's own `P["bags"]`
-- (source/ElvUI-vanilla/ElvUI/Settings/Profile.lua:101-165), including keys
-- nothing reads yet. Two deliberate exceptions, both marked below:
-- `split.bag11` and the `cooldown` sub-table.
P.bags = {
	sortInverted = true,
	bagSize = 34,
	bankSize = 34,
	bagWidth = 406,
	bankWidth = 406,
	moneyFormat = "SMART",
	moneyCoins = true,
	junkIcon = false,
	ignoredItems = {},
	itemLevel = true,
	itemLevelThreshold = 1,
	itemLevelFont = "Homespun",
	itemLevelFontSize = 10,
	itemLevelFontOutline = "MONOCHROMEOUTLINE",
	itemLevelCustomColorEnable = false,
	itemLevelCustomColor = { r = 1, g = 1, b = 1 },
	countFont = "Homespun",
	countFontSize = 10,
	countFontOutline = "MONOCHROMEOUTLINE",
	countFontColor = { r = 1, g = 1, b = 1 },
	reverseSlots = false,
	clearSearchOnClose = false,
	disableBagSort = false,
	disableBankSort = false,
	strata = "DIALOG",
	colors = {
		profession = {
			quiver = { r = 1, g = 0.56, b = 0.73 },
			ammoPouch = { r = 1, g = 0.56, b = 0.73 },
			soulBag = { r = 0.47, g = 0.26, b = 1 },
			leatherworking = { r = 0.88, g = 0.73, b = 0.29 },
			herbs = { r = 0.07, g = 0.71, b = 0.13 },
			enchanting = { r = 0.76, g = 0.02, b = 0.8 },
			engineering = { r = 0.91, g = 0.46, b = 0.18 },
			gems = { r = 0.03, g = 0.71, b = 0.81 },
			mining = { r = 0.54, g = 0.40, b = 0.04 },
		},
		items = {
			questStarter = { r = 1, g = 1, b = 0 },
			questItem = { r = 1, g = 0.30, b = 0.30 },
		},
	},
	vendorGrays = {
		enable = false,
		interval = 0.2,
		details = false,
		progressBar = true,
	},
	split = {
		bagSpacing = 5,
		player = false,
		bank = false,
		bag1 = false,
		bag2 = false,
		bag3 = false,
		bag4 = false,
		bag5 = false,
		bag6 = false,
		bag7 = false,
		bag8 = false,
		bag9 = false,
		bag10 = false,
		-- Real ElvUI also declares `bag11`. Left out: NUM_BANKBAGSLOTS is 6
		-- on both clients here (bags 5-10), so bag11 would name a container
		-- that cannot exist.
	},
	-- Carried for profile fidelity only. Real ElvUI never reads this
	-- sub-table either; bag-slot cooldown TEXT comes from this project's
	-- Core/Cooldowns.lua and the top-level `P.cooldown` above.
	cooldown = {
		threshold = 4,
		override = false,
		reverse = false,
		expiringColor = { r = 1, g = 0, b = 0 },
		secondsColor = { r = 1, g = 1, b = 1 },
		minutesColor = { r = 1, g = 1, b = 1 },
		hoursColor = { r = 1, g = 1, b = 1 },
		daysColor = { r = 1, g = 1, b = 1 },
		checkSeconds = false,
		hhmmColor = { r = 1, g = 1, b = 1 },
		mmssColor = { r = 1, g = 1, b = 1 },
		hhmmThreshold = -1,
		mmssThreshold = -1,
		fonts = {
			enable = false,
			font = "PT Sans Narrow",
			fontOutline = "OUTLINE",
			fontSize = 18,
		},
	},
	bagBar = {
		growthDirection = "VERTICAL",
		sortDirection = "ASCENDING",
		size = 30,
		spacing = 4,
		backdropSpacing = 4,
		showBackdrop = false,
		mouseover = false,
		visibility = "",
	},
}

-- ---------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------
-- Real ElvUI's own `P["chat"]`. `whisperSound` is the one deliberate value
-- deviation: sound PLAYBACK is unverified on UA, so the alert ships silent
-- ("None") rather than as real ElvUI's "ElvUI Aska". The media itself is
-- registered and shipped, and Chat.lua does call PlaySoundFile for it.
P.chat = {
	lockPositions = true,
	url = true,
	shortChannels = true,
	hyperlinkHover = true,
	throttleInterval = 45,
	scrollDownInterval = 15,
	fade = true,
	font = "PT Sans Narrow",
	fontOutline = "NONE",
	sticky = true,
	keywordSound = "None",
	whisperSound = "None",
	noAlertInCombat = false,
	chatHistory = true,
	timeStampFormat = "NONE",
	keywords = "%MYNAME%, ElvUI",
	separateSizes = false,
	panelWidth = 412,
	panelHeight = 180,
	panelWidthRight = 412,
	panelHeightRight = 180,
	panelBackdropNameLeft = "",
	panelBackdropNameRight = "",
	panelBackdrop = "SHOWBOTH",
	panelTabBackdrop = false,
	panelTabTransparency = false,
	editBoxPosition = "BELOW_CHAT",
	fadeUndockedTabs = true,
	fadeTabsNoBackdrop = true,
	useAltKey = false,
	numAllowedCombatRepeat = 3,
	useCustomTimeColor = true,
	customTimeColor = { r = 0.7, g = 0.7, b = 0.7 },
	numScrollMessages = 3,
	tabFont = "PT Sans Narrow",
	tabFontSize = 12,
	tabFontOutline = "NONE",
	panelColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.8 },
}

-- ---------------------------------------------------------------------
-- DataBars (Experience, Reputation)
-- ---------------------------------------------------------------------
-- `width`/`height`/`orientation`/`font` and `enable = true` all deviate
-- from real ElvUI's values (whitelisted -- see docs/modules/databars.md).
-- "PT Sans Narrow" isn't registered in this project's trimmed
-- LibSharedMedia, and both bars ship visible because the native watch bars
-- they replace are hidden outright.
P.databars = {
	experience = {
		enable = true,
		width = 200,
		height = 14,
		textFormat = "NONE",
		textSize = 11,
		font = "PT Sans Narrow",
		fontOutline = "NONE",
		mouseover = false,
		orientation = "HORIZONTAL",
		hideAtMaxLevel = true,
		hideInCombat = false,
	},
	reputation = {
		enable = true,
		width = 200,
		height = 14,
		textFormat = "NONE",
		textSize = 11,
		font = "PT Sans Narrow",
		fontOutline = "NONE",
		mouseover = false,
		orientation = "HORIZONTAL",
		hideInCombat = false,
	},
}

-- ---------------------------------------------------------------------
-- DataTexts
-- ---------------------------------------------------------------------
-- Panels this project doesn't build (BottomMiniPanel, TopLeftMiniPanel,
-- ... -- all empty "" in real ElvUI too) are omitted; a real profile's own
-- entries for them merge in as extra keys regardless.
P.datatexts = {
	font = "PT Sans Narrow",
	fontSize = 12,
	fontOutline = "OUTLINE",
	panels = {
		LeftMiniPanel = "Guild",
		RightMiniPanel = "Friends",
		LeftChatDataPanel = {
			left = "Armor",
			middle = "Durability",
			right = "Avoidance",
		},
		RightChatDataPanel = {
			left = "System",
			middle = "Time",
			right = "Gold",
		},
	},
	timeFormat = "%I:%M",
	dateFormat = "",
	panelTransparency = false,
	panelBackdrop = true,
	goldFormat = "BLIZZARD",
	friends = {
		hideAFK = false,
		hideDND = false,
	},
	minimapPanels = true,
	leftChatPanel = true,
	rightChatPanel = true,
}

-- ---------------------------------------------------------------------
-- NamePlates
-- ---------------------------------------------------------------------
-- The subset of real ElvUI's `P["nameplates"]` this module reads. Its much
-- larger `units[UNIT_TYPE].{healthbar,castbar,buffs,debuffs,comboPoints,
-- name}` per-unit-type tree is NOT ported.
--
-- `width`/`healthHeight` are project additions -- this module's own
-- simplified bar geometry.
P.nameplates = {
	font = "PT Sans Narrow",
	fontSize = 11,
	fontOutline = "OUTLINE",
	healthFont = "PT Sans Narrow",
	healthFontSize = 11,
	healthFontOutline = "OUTLINE",
	useTargetScale = true,
	targetScale = 1.15,
	nonTargetTransparency = 0.40,
	lowHealthThreshold = 0.4,
	showLevel = true,
	showHealthText = true,
	width = 150,
	healthHeight = 10,
	-- Real ElvUI's own default reaction palette
	-- (source/ElvUI-vanilla/ElvUI/Settings/Profile.lua:239-245), verbatim.
	reactions = {
		friendlyPlayer = {r = 0.31, g = 0.45, b = 0.63},
		tapped = {r = 0.6, g = 0.6, b = 0.6},
		good = {r = 75/255, g = 175/255, b = 76/255},
		neutral = {r = 218/255, g = 197/255, b = 92/255},
		bad = {r = 0.78, g = 0.25, b = 0.25},
	},
}

-- ---------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------
-- Real ElvUI's `P["tooltip"]` verbatim
-- (source/ElvUI-vanilla/ElvUI/Settings/Profile.lua:631). Keys the module
-- does not read yet are still declared, so an imported profile keeps them.
-- The font keys cannot take effect on UA, where SetFont is a no-op.
P.tooltip = {
	cursorAnchor = false,
	targetInfo = true,
	playerTitles = true,
	guildRanks = true,
	inspectInfo = true,
	itemPrice = true,
	itemCount = "BAGS_ONLY",
	spellID = true,
	itemLevel = true,
	font = "PT Sans Narrow",
	fontOutline = "NONE",
	headerFontSize = 12,
	textFontSize = 12,
	smallTextFontSize = 12,
	colorAlpha = 0.8,
	visibility = {
		unitFrames = "NONE",
		bags = "NONE",
		actionbars = "NONE",
		combat = false,
	},
	healthBar = {
		text = true,
		height = 7,
		font = "Homespun",
		fontSize = 10,
		fontOutline = "OUTLINE",
		statusPosition = "BOTTOM",
	},
	useCustomFactionColors = false,
	factionColors = {
		[1] = {r = 0.8, g = 0.3, b = 0.22},
		[2] = {r = 0.8, g = 0.3, b = 0.22},
		[3] = {r = 0.75, g = 0.27, b = 0},
		[4] = {r = 0.9, g = 0.7, b = 0},
		[5] = {r = 0, g = 0.6, b = 0.1},
		[6] = {r = 0, g = 0.6, b = 0.1},
		[7] = {r = 0, g = 0.6, b = 0.1},
		[8] = {r = 0, g = 0.6, b = 0.1},
	},
}

-- ---------------------------------------------------------------------
-- UnitFrames
-- ---------------------------------------------------------------------
P.unitframe = {
	font = "Homespun",
	fontSize = 10,
	fontOutline = "MONOCHROMEOUTLINE",
	statusbar = "ElvUI Norm",
}

-- transparentHealth/transparentPower are real ElvUI field names, but its
-- own implementation clears the bar's fill texture and repositions the
-- background to cover only the UNFILLED portion
-- (Elements/Health.lua's `ToggleTransparentStatusBar`) -- per-texture
-- control this project's hand-rolled Util.CreateStatusBar doesn't have.
-- Here they reduce alpha uniformly on background AND fill instead: same
-- practical purpose (let an overlay portrait show through), simpler
-- mechanism.
P.unitframe.colors = {
	power = {
		MANA = {r = 0.31, g = 0.45, b = 0.63},
		RAGE = {r = 0.78, g = 0.25, b = 0.25},
		FOCUS = {r = 0.71, g = 0.43, b = 0.27},
		ENERGY = {r = 0.65, g = 0.63, b = 0.35},
	},
	healthclass = false,
	forcehealthreaction = false,
	colorhealthbyvalue = true,
	customhealthbackdrop = false,
	useDeadBackdrop = false,
	powerclass = false,
	-- Read by UnitFrames.lua's castbar colouring. Real ElvUI's default is
	-- `false`, which is also what the undeclared `nil` resolved to before this
	-- was declared -- so this completes the schema without changing behaviour.
	castClassColor = false,
	transparentHealth = false,
	transparentPower = false,
	health = {r = 0.31, g = 0.31, b = 0.31},
	health_backdrop = {r = 0.8, g = 0.01, b = 0.01},
	health_backdrop_dead = {r = 0.8, g = 0.01, b = 0.01},
	-- Unused by Player (always UnitIsPlayer, reaction never applies there).
	reaction = {
		BAD = {r = 0.78, g = 0.25, b = 0.25},
		NEUTRAL = {r = 218/255, g = 197/255, b = 92/255},
		GOOD = {r = 75/255, g = 175/255, b = 76/255},
	},
}

P.unitframe.units = {}

-- Per-unit notes that apply to EVERY unit table below, so they aren't
-- repeated on each one:
--
--   portrait.style   "3D" is real ElvUI's own unconditional default for
--                    every unit. It has to match, because real ElvUI's
--                    profile EXPORT strips any field still equal to its
--                    default (`E:RemoveTableDuplicates`,
--                    Core/distributor.lua) -- a profile using the default
--                    3D portrait carries no `style` key at all, so a
--                    different default here silently wins.
--   buffs/debuffs    `perrow`/`xOffset`/`yOffset`/`minDuration`/
--                    `maxDuration` are real ElvUI field names (0 = no
--                    filter on that side). `size` is a project addition --
--                    real ElvUI derives icon size from the frame width.
--                    Frame-attached auras ship DISABLED where real ElvUI
--                    disables them (player, pet): the standalone Auras
--                    module already shows the player's own buffs, so
--                    enabling both draws them twice. `UF:UpdateAuras`
--                    hides the container when `enable` is false, so this
--                    is a real switch, not just a stored value.
--   text_format      An empty string means "no text", and that is what real
--                    ElvUI ships for health/power on the compact frames
--                    (pet, pettarget, targettarget) -- only the name shows
--                    there. The tag engine handles "" as a no-op, same as
--                    the player frame's own empty `name.text_format`.
--   RestIcon         PLAYER ONLY. `IsResting()` takes no unit argument;
--                    an inn/city rest state doesn't exist as a concept for
--                    an arbitrary unit. CombatIcon by contrast DOES
--                    generalize (UnitAffectingCombat takes any unit), so
--                    every unit has one.
--   infoPanel        Real ElvUI field/default verbatim -- a bare strip
--                    below Health/Power, purely a mounting surface for
--                    Custom Text.
--   customTexts      Real ElvUI schema: a plain table KEYED BY NAME, not
--                    an array. Populated live via the config UI.

P.unitframe.units.player = {
	enable = true,
	width = 270,
	height = 54,
	orientation = "LEFT",
	colorOverride = "USE_DEFAULT",
	health = {
		text_format = "[healthcolor][health:current-percent]",
		position = "LEFT",
		xOffset = 2,
		yOffset = 0,
		attachTextTo = "Health",
	},
	power = {
		enable = true,
		height = 10,
		text_format = "[powercolor][power:current]",
		position = "RIGHT",
		xOffset = -2,
		yOffset = 0,
		attachTextTo = "Health",
	},
	name = {
		text_format = "",
		position = "CENTER",
		xOffset = 0,
		yOffset = 0,
		attachTextTo = "Health",
	},
	-- Real ElvUI's own exact field set for a portrait: enable/width/style/
	-- overlay (source/ElvUI-vanilla/ElvUI_Config/UnitFrames.lua's
	-- GetOptionsTable_Portrait) -- no alpha/model-scale fields, the working
	-- overlay on UA needs SetCamera(0), not extra settings.
	portrait = {
		enable = false,
		width = 45,
		style = "3D",
		overlay = false,
	},
	RestIcon = {
		enable = true,
		defaultColor = true,
		color = {r = 1, g = 1, b = 1, a = 1},
		anchorPoint = "TOPLEFT",
		xOffset = -3,
		yOffset = 6,
		size = 22,
		texture = "DEFAULT",
	},
	CombatIcon = {
		enable = true,
		defaultColor = true,
		color = {r = 1, g = 0.2, b = 0.2, a = 1},
		anchorPoint = "CENTER",
		xOffset = 0,
		yOffset = 0,
		size = 20,
	},
	raidicon = {
		enable = true,
		size = 18,
		attachTo = "TOP",
		attachToObject = "Frame",
		xOffset = 0,
		yOffset = 8,
	},
	-- Player's own buffs/debuffs are the only ones with REAL duration --
	-- the native GetPlayerBuff* family takes no unit argument.
	buffs = {
		enable = false,
		perrow = 8,
		sizeOverride = 20,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
		numrows = 1,
		attachTo = "DEBUFFS",
		anchorPoint = "TOPLEFT",
		clickThrough = false,
	},
	debuffs = {
		enable = true,
		perrow = 8,
		sizeOverride = 20,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
		numrows = 1,
		attachTo = "FRAME",
		anchorPoint = "TOPLEFT",
		clickThrough = false,
	},
	infoPanel = {
		enable = false,
		height = 20,
		transparent = false,
	},
	customTexts = {},
	-- `enable`/`width`/`height`/`icon`/`format`/`spark` are read (see
	-- UnitFrames.lua's Castbar section). `latency` is schema-only -- real
	-- ElvUI's "safe zone" latency overlay isn't implemented. Also not
	-- declared: ticks/displayTarget/iconSize/iconAttached/insideInfoPanel/
	-- iconAttachedTo/iconPosition/iconXOffset/iconYOffset/tickWidth/
	-- tickColor/strataAndLevel (its pixel-perfect icon-attachment and
	-- tick-mark system).
	castbar = {
		enable = true,
		width = 270,
		height = 18,
		icon = true,
		latency = true,
		format = "REMAINING",
		spark = true,
	},
}

P.unitframe.units.target = {
	enable = true,
	width = 270,
	height = 54,
	orientation = "RIGHT",
	colorOverride = "USE_DEFAULT",
	health = {
		text_format = "[healthcolor][health:current-percent]",
		position = "RIGHT",
		xOffset = -2,
		yOffset = 0,
		attachTextTo = "Health",
	},
	power = {
		enable = true,
		height = 10,
		text_format = "[powercolor][power:current]",
		position = "LEFT",
		xOffset = 2,
		yOffset = 0,
		attachTextTo = "Health",
	},
	name = {
		text_format = "[name]",
		position = "CENTER",
		xOffset = 0,
		yOffset = 0,
		attachTextTo = "Health",
	},
	portrait = {
		enable = false,
		width = 45,
		style = "3D",
		overlay = false,
	},
	CombatIcon = {
		enable = true,
		defaultColor = true,
		color = {r = 1, g = 0.2, b = 0.2, a = 1},
		anchorPoint = "CENTER",
		xOffset = 0,
		yOffset = 0,
		size = 20,
	},
	raidicon = {
		enable = true,
		size = 18,
		attachTo = "TOP",
		attachToObject = "Frame",
		xOffset = 0,
		yOffset = 8,
	},
	-- Duration source here is tier 3 (icon + stack count only, no timer) --
	-- there is no per-unit equivalent of GetPlayerBuff.
	buffs = {
		enable = true,
		perrow = 8,
		sizeOverride = 20,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
		numrows = 1,
		attachTo = "FRAME",
		anchorPoint = "TOPRIGHT",
		clickThrough = false,
	},
	debuffs = {
		enable = true,
		perrow = 8,
		sizeOverride = 20,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
		numrows = 1,
		attachTo = "BUFFS",
		anchorPoint = "TOPRIGHT",
		clickThrough = false,
	},
	infoPanel = {
		enable = false,
		height = 20,
		transparent = false,
	},
	customTexts = {},
}

P.unitframe.units.targettarget = {
	enable = true,
	width = 130,
	height = 36,
	orientation = "MIDDLE",
	colorOverride = "USE_DEFAULT",
	health = {
		text_format = "",
		position = "RIGHT",
		xOffset = -2,
		yOffset = 0,
	},
	-- `power.enable = true` is real ElvUI's own default: it really does show
	-- target-of-target's power bar out of the box.
	power = {
		enable = true,
		height = 7,
		text_format = "",
		position = "LEFT",
		xOffset = 2,
		yOffset = 0,
	},
	name = {
		text_format = "[name]",
		position = "CENTER",
		xOffset = 0,
		yOffset = 0,
		attachTextTo = "Health",
	},
	portrait = {
		enable = false,
		width = 45,
		style = "3D",
		overlay = false,
	},
	CombatIcon = {
		enable = true,
		defaultColor = true,
		color = {r = 1, g = 0.2, b = 0.2, a = 1},
		anchorPoint = "CENTER",
		xOffset = 0,
		yOffset = 0,
		size = 14,
	},
	raidicon = {
		enable = true,
		size = 18,
		attachTo = "TOP",
		attachToObject = "Frame",
		xOffset = 0,
		yOffset = 8,
	},
	debuffs = {
		enable = true,
		perrow = 5,
		sizeOverride = 16,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
		numrows = 1,
		attachTo = "FRAME",
		anchorPoint = "BOTTOMRIGHT",
		clickThrough = false,
	},
	infoPanel = {
		enable = false,
		height = 14,
		transparent = false,
	},
	customTexts = {},
	buffs = {
		enable = false,
		perrow = 7,
		numrows = 1,
		sizeOverride = 20,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		attachTo = "FRAME",
		anchorPoint = "BOTTOMLEFT",
		clickThrough = false,
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
	},
}

P.unitframe.units.pet = {
	enable = true,
	width = 130,
	height = 36,
	orientation = "MIDDLE",
	colorOverride = "USE_DEFAULT",
	health = {
		text_format = "",
		position = "RIGHT",
		xOffset = -2,
		yOffset = 0,
	},
	power = {
		enable = true,
		height = 7,
		text_format = "",
		position = "LEFT",
		xOffset = 2,
		yOffset = 0,
	},
	name = {
		text_format = "[name]",
		position = "CENTER",
		xOffset = 0,
		yOffset = 0,
	},
	portrait = {
		enable = false,
		width = 45,
		style = "3D",
		overlay = false,
	},
	CombatIcon = {
		enable = true,
		defaultColor = true,
		color = {r = 1, g = 0.2, b = 0.2, a = 1},
		anchorPoint = "CENTER",
		xOffset = 0,
		yOffset = 0,
		size = 16,
	},
	buffs = {
		enable = false,
		perrow = 7,
		sizeOverride = 16,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
		numrows = 1,
		attachTo = "FRAME",
		anchorPoint = "BOTTOMLEFT",
		clickThrough = false,
	},
	debuffs = {
		enable = false,
		perrow = 5,
		sizeOverride = 16,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
		numrows = 1,
		attachTo = "FRAME",
		anchorPoint = "BOTTOMRIGHT",
		clickThrough = false,
	},
	infoPanel = {
		enable = false,
		height = 12,
		transparent = false,
	},
	customTexts = {},
	-- Real ElvUI field/default verbatim (Settings/Profile.lua:1593),
	-- `enable = false` included. Hunter-only at runtime -- see
	-- UnitFrames.lua's Construct_Happiness. `autoHide` is a project
	-- addition.
	happiness = {
		enable = false,
		autoHide = false,
		width = 10,
	},
}

-- `enable = true` deviates from real ElvUI's own `false` (whitelisted).
-- Flipping it to match would silently remove the frame on a fresh install,
-- where it is a working, tested feature.
P.unitframe.units.pettarget = {
	enable = true,
	width = 130,
	height = 26,
	orientation = "MIDDLE",
	colorOverride = "USE_DEFAULT",
	health = {
		text_format = "",
		position = "RIGHT",
		xOffset = -2,
		yOffset = 0,
	},
	power = {
		enable = false,
		height = 7,
		text_format = "",
		position = "LEFT",
		xOffset = 2,
		yOffset = 0,
	},
	name = {
		text_format = "[name]",
		position = "CENTER",
		xOffset = 0,
		yOffset = 0,
	},
	portrait = {
		enable = false,
		width = 45,
		style = "3D",
		overlay = false,
	},
	CombatIcon = {
		enable = true,
		defaultColor = true,
		color = {r = 1, g = 0.2, b = 0.2, a = 1},
		anchorPoint = "CENTER",
		xOffset = 0,
		yOffset = 0,
		size = 14,
	},
	infoPanel = {
		enable = false,
		height = 12,
		transparent = false,
	},
	customTexts = {},
	buffs = {
		enable = false,
		perrow = 7,
		numrows = 1,
		sizeOverride = 20,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		attachTo = "FRAME",
		anchorPoint = "BOTTOMLEFT",
		clickThrough = false,
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
	},
	debuffs = {
		enable = false,
		perrow = 5,
		numrows = 1,
		sizeOverride = 20,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		attachTo = "FRAME",
		anchorPoint = "BOTTOMRIGHT",
		clickThrough = false,
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
	},
}

P.unitframe.units.party = {
	enable = true,
	width = 184,
	height = 54,
	orientation = "LEFT",
	colorOverride = "USE_DEFAULT",
	health = {
		text_format = "[healthcolor][health:current-percent]",
		position = "LEFT",
		xOffset = 2,
		yOffset = 0,
		attachTextTo = "Health",
	},
	power = {
		enable = true,
		height = 7,
		text_format = "[powercolor][power:current]",
		position = "RIGHT",
		xOffset = -2,
		yOffset = 0,
		attachTextTo = "Health",
	},
	name = {
		text_format = "[name]",
		position = "CENTER",
		xOffset = 0,
		yOffset = 0,
		attachTextTo = "Health",
	},
	portrait = {
		enable = false,
		width = 45,
		style = "3D",
		overlay = false,
	},
	CombatIcon = {
		enable = true,
		defaultColor = true,
		color = {r = 1, g = 0.2, b = 0.2, a = 1},
		anchorPoint = "CENTER",
		xOffset = 0,
		yOffset = 0,
		size = 16,
	},
	raidicon = {
		enable = true,
		size = 18,
		attachTo = "TOP",
		attachToObject = "Frame",
		xOffset = 0,
		yOffset = 8,
	},
	buffs = {
		enable = false,
		perrow = 3,
		numrows = 1,
		sizeOverride = 20,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		attachTo = "FRAME",
		anchorPoint = "LEFT",
		clickThrough = false,
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
	},
	debuffs = {
		enable = true,
		perrow = 3,
		numrows = 1,
		sizeOverride = 52,
		sortMethod = "TIME_REMAINING",
		sortDirection = "DESCENDING",
		attachTo = "FRAME",
		anchorPoint = "RIGHT",
		clickThrough = false,
		xOffset = 0,
		yOffset = 0,
		minDuration = 0,
		maxDuration = 0,
	},
}
