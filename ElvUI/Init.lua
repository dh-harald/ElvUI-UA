-- ElvUI core bootstrap.
--
-- Creates the global ElvUI engine table and the positional Engine[1..5]
-- slots (AddOn, Locale, private-defaults, profile-defaults, global-defaults)
-- that ElvUI modules/plugins traditionally consume via
-- `local E, L, V, P, G = unpack(ElvUI)` (V=private, P=profile -- confirmed
-- against real ElvUI's own Modules/Maps/Minimap.lua source, which labels
-- position 3/4 this way). This mirrors the original ElvUI's Init.lua so existing
-- plugin code, and eventually a straight ElvDB / ElvPrivateDB
-- SavedVariables copy from a real ElvUI install, stay compatible.
--
-- Deliberately minimal for now: this only proves the addon loads and the
-- AceAddon lifecycle fires on both the 1.12.1 client and Unreal Azeroth.
-- Real profile loading (ElvDB.profiles / ElvPrivateDB.profiles copy-in)
-- lands as its own next step once this loads clean on both.

ElvUI = ElvUI or {}

local AddOnName = "ElvUI"
local Engine = ElvUI

local AddOn = LibStub("AceAddon-3.0"):NewAddon(AddOnName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")
AddOn.callbacks = AddOn.callbacks or LibStub("CallbackHandler-1.0"):New(AddOn)

-- Matches real ElvUI's own E.noop -- a shared no-op used e.g. to overwrite
-- a Blizzard method that would otherwise silently re-apply a look we just
-- removed (see Modules/ActionBars.lua's SetNormalTexture override).
AddOn.noop = AddOn.noop or function() end

-- Heading of ElvUI's commands in the stock Key Bindings window; Bindings.xml
-- declares them under header="ELVUI".
BINDING_HEADER_ELVUI = "ElvUI"

-- The defaults tables themselves. Their CONTENT lives in
-- Settings/{Profile,Global,Private}.lua, which the .toc loads immediately
-- after this file -- those files reach them through the Engine[3..5]
-- bindings below, so the tables have to exist first.
AddOn.DF = { profile = {}, global = {} }
AddOn.privateVars = { profile = {} }

-- Real ElvUI's own value-colour registry (`Core/core.lua`'s
-- `E.valueColorUpdateFuncs`). The UI ACCENT colour (`E.db.general.valuecolor`)
-- is what every data text paints the VALUE half of its label with -- "Armor: "
-- in the font colour, the number in the accent. A consumer registers a
-- `function(hex, r, g, b)` here AT FILE LOAD TIME (`E.valueColorUpdateFuncs[fn]
-- = true`) and rebuilds whatever format string it holds; `E:ValueFuncCall`
-- then drives all of them, both at init and whenever the colour changes.
--
-- The indirection exists because the accent is a live setting and the strings
-- are built once, not per frame -- there is no way to re-colour an already
-- formatted `|cffRRGGBB...|r` string after the fact.
AddOn.valueColorUpdateFuncs = AddOn.valueColorUpdateFuncs or {}

-- Client-language pass of the core translations; OnInitialize repeats it once
-- the "Addon Language" SavedVariable is loaded (Locales/Locales.lua).
Engine.ApplyLocale()

local Locale = LibStub("AceLocale-3.0"):GetLocale(AddOnName, true)

Engine[1] = AddOn
Engine[2] = Locale
Engine[3] = AddOn.privateVars.profile
Engine[4] = AddOn.DF.profile
Engine[5] = AddOn.DF.global

_G[AddOnName] = Engine

-- Shaman's class color, corrected in the GLOBAL table rather than per consumer.
-- Vanilla ships Shaman in the same pink range as Paladin, which leaves the two
-- indistinguishable in health bars, name text and chat colors; the blue below is
-- the value Blizzard settled on later, and the one UnrealUI uses on this engine
-- (source/UnrealUI/core/media.lua:352).
--
-- MUTATED IN PLACE, not replaced: several callers here hold `RAID_CLASS_COLORS`
-- or one of its entries as a local (Modules/UnitFrames/UnitFrames.lua,
-- Modules/DataTexts/{Guild,Gold,Friends}.lua, Modules/Skins/Blizzard/Friends.lua,
-- Core/Install.lua's GetClassColor), so swapping the table object would leave
-- them pointing at the old one. Every one of those reads r/g/b at call time, so
-- an in-place edit reaches all of them with no further wiring.
--
-- Deliberately ONLY Shaman. Real ElvUI carries a whole class-color/role
-- apparatus (its Core/core.lua: E.ClassRole, E.PriestColors, a CUSTOM_CLASS_COLORS
-- integration); none of that is ported -- this is the single value that is
-- actually wrong for a player to look at.
if type(RAID_CLASS_COLORS) == "table" and type(RAID_CLASS_COLORS.SHAMAN) == "table" then
	RAID_CLASS_COLORS.SHAMAN.r = 0.00
	RAID_CLASS_COLORS.SHAMAN.g = 0.44
	RAID_CLASS_COLORS.SHAMAN.b = 0.87
end

function AddOn:OnInitialize()
	-- First: GAME_LOCALE is loaded by now, and everything after this line reads
	-- L[] in the chosen language -- the print below, the datatext strings
	-- UpdateValueColor rebuilds, every module's init. ElvUI_Config applies it
	-- itself as well, as its files may load before this runs.
	ElvUI.ApplyLocale()

	if not ElvCharacterDB then
		ElvCharacterDB = {}
	end

	self.myname, self.myrealm = UnitName("player"), GetRealmName()
	-- Matches real ElvUI's own E.myclass/E.myrace exactly (the ENGLISH/
	-- locale-independent token, e.g. "WARRIOR" -- UnitClass/UnitRace's
	-- SECOND return value, not the localized display name) -- several
	-- DataText widgets (Modules/DataTexts/AttackPower.lua, Avoidance.lua)
	-- branch on these directly.
	local _, myclass = UnitClass("player")
	local _, myrace = UnitRace("player")
	self.myclass = myclass
	self.myrace = myrace
	local charKey = self.myname.." - "..self.myrealm
	local Merge = ElvUI.Util.MergeTable

	ElvDB = ElvDB or {}
	ElvDB.profileKeys = ElvDB.profileKeys or {}
	ElvDB.profiles = ElvDB.profiles or {}
	local profileKey = ElvDB.profileKeys[charKey] or charKey
	ElvDB.profileKeys[charKey] = profileKey

	-- self.db/self.global/self.private are the LIVE tables modules read/
	-- write at runtime; Engine[3..5] (V/P/G) stay pure defaults for options
	-- code to reference. Each starts as a fresh defaults-copy, has any saved
	-- data overlaid on top (so a key missing from an old saved profile still
	-- gets its default instead of nil), then gets written BACK into
	-- ElvDB/ElvPrivateDB *by reference* -- so from here on, mutating
	-- self.db/self.private (e.g. a config-UI checkbox's `set` function) IS
	-- the persistence, no separate save step needed.
	self.global = Merge({}, self.DF.global)
	if ElvDB.global then
		Merge(self.global, ElvDB.global)
	end
	ElvDB.global = self.global

	self.db = Merge({}, self.DF.profile)
	if ElvDB.profiles[profileKey] then
		Merge(self.db, ElvDB.profiles[profileKey])
	end
	ElvDB.profiles[profileKey] = self.db

	ElvPrivateDB = ElvPrivateDB or {}
	ElvPrivateDB.profileKeys = ElvPrivateDB.profileKeys or {}
	ElvPrivateDB.profiles = ElvPrivateDB.profiles or {}
	local privateProfileKey = ElvPrivateDB.profileKeys[charKey] or charKey
	ElvPrivateDB.profileKeys[charKey] = privateProfileKey

	self.private = Merge({}, self.privateVars.profile)
	if ElvPrivateDB.profiles[privateProfileKey] then
		Merge(self.private, ElvPrivateDB.profiles[privateProfileKey])
	end
	ElvPrivateDB.profiles[privateProfileKey] = self.private

	-- E.media.normTex -- resolved ONCE here (matches real ElvUI's own
	-- Core/core.lua:220 exactly, same field name/timing), not recomputed
	-- live -- this is a PRIVATE/reload-required setting by design (same
	-- as real ElvUI's own), so a config change to it takes effect on
	-- next /reload, consistent with every other V.*/E.private.* setting
	-- in this project. See Settings/Private.lua for the "ElvUI Blank"
	-- default reasoning.
	local LSM = LibStub("LibSharedMedia-3.0", true)
	self.media = self.media or {}
	self.media.normTex = (LSM and LSM:Fetch("statusbar", self.private.general.normTex)) or "Interface\\Buttons\\WHITE8x8"
	-- Same resolve-once treatment for the gloss texture (real ElvUI's own
	-- Core/core.lua:221). Consumed by Core/Util.lua's `CreateButtonBorder`
	-- as every button backdrop's `bgFile`; the literal fallback there is
	-- the same file, for calls that land before this line runs.
	self.media.glossTex = (LSM and LSM:Fetch("statusbar", self.private.general.glossTex))
		or "Interface\\AddOns\\ElvUI\\Media\\Textures\\normTex2"

	-- Runs here, not in a module: every consumer registers its own update
	-- function at FILE LOAD time, and the client has loaded every `.toc`
	-- entry before `ADDON_LOADED` (which is what drives `OnInitialize`), so
	-- the registry is already complete and `self.db` exists. Unlike
	-- `normTex`/`glossTex` above, this one is NOT reload-bound -- the config
	-- control re-runs it live.
	self:UpdateValueColor()

	self:Print(Locale["Core initialized."])
end

-- Is this colour some OTHER class's class colour? Real ElvUI's own
-- `E:CheckClassColor` (`Core/core.lua`), rounded to two decimals the same way,
-- and the test behind the class-colour re-anchoring in `UpdateValueColor`
-- below. The local character's own class is skipped, so an accent that is
-- already correct never matches.
--
-- `CUSTOM_CLASS_COLORS`/`E.PriestColors` are part of upstream's own lookup and
-- are deliberately left out: neither exists in this project (`RAID_CLASS_COLORS`
-- is the single source, with Shaman corrected in place at the top of this file).
function AddOn:CheckClassColor(r, g, b)
	if not (r and g and b) or type(RAID_CLASS_COLORS) ~= "table" then return false end

	local function Round2(v) return math.floor(v * 100 + 0.5) / 100 end
	r, g, b = Round2(r), Round2(g), Round2(b)

	local class, colorTable
	for class, colorTable in pairs(RAID_CLASS_COLORS) do
		if class ~= self.myclass and type(colorTable) == "table" then
			if Round2(colorTable.r) == r and Round2(colorTable.g) == g and Round2(colorTable.b) == b then
				return true
			end
		end
	end

	return false
end

-- The UI accent colour, derived from `E.db.general.valuecolor` into the two
-- shapes consumers need: a `|cffRRGGBB` prefix for text, and raw r/g/b for
-- anything that takes a colour directly. Same field names as real ElvUI's own
-- `E:UpdateMedia` (`E.media.hexvaluecolor`/`rgbvaluecolor`), so ported code
-- reads unchanged.
--
-- The class-colour re-anchoring is upstream's too, and it is what makes the
-- install wizard's "class" theme keep working after a profile moves: the theme
-- writes the CHARACTER's class colour into the profile, so the same profile
-- opened on a different class would otherwise show the first character's class
-- colour forever. Whenever the stored accent is recognisably some other class's
-- colour, it is re-anchored to this character's own -- and written back, since
-- `E.db` IS the persistence here (see the `OnInitialize` note above).
--
-- It can only ever fire on a colour that exactly equals a class colour, so a
-- hand-picked accent is never touched.
function AddOn:UpdateValueColor()
	local value = self.db and self.db.general and self.db.general.valuecolor
	if not value then return end

	if self:CheckClassColor(value.r, value.g, value.b) then
		local classColor = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[self.myclass]
		if classColor then
			value.r, value.g, value.b = classColor.r, classColor.g, classColor.b
		end
	end

	self.media = self.media or {}
	self.media.rgbvaluecolor = { value.r, value.g, value.b }
	self.media.hexvaluecolor = self:RGBToHex(value.r, value.g, value.b)

	self:ValueFuncCall()
end

-- pcall per consumer, unlike real ElvUI's bare call: one widget's bad format
-- string must not stop every later-registered one from being re-coloured.
function AddOn:ValueFuncCall()
	if not (self.media and self.media.hexvaluecolor) then return end
	local rgb = self.media.rgbvaluecolor
	local func
	for func in pairs(self.valueColorUpdateFuncs) do
		pcall(func, self.media.hexvaluecolor, rgb[1], rgb[2], rgb[3])
	end
end

AddOn.InitialModules = AddOn.InitialModules or {}

-- Mirrors real ElvUI's E:RegisterInitialModule. A module file calls this
-- at load time (Modules\Load_Modules.xml loads before ADDON_LOADED fires,
-- so this just queues initFunc); AddOn:OnEnable below runs every queued
-- initFunc, in registration order, once self.db/self.private/self.global
-- are already built. Order within this tier just follows Load_Modules.xml's
-- <Script> order; a module that must run after all of them registers into
-- the second tier below (AddOn:RegisterModule) instead.
function AddOn:RegisterInitialModule(name, initFunc)
	table.insert(self.InitialModules, { name = name, init = initFunc })
end

AddOn.Modules = AddOn.Modules or {}

-- The SECOND init tier, mirroring real ElvUI's own two-stage
-- E:InitializeInitialModules() -> E:InitializeModules() split. Everything
-- registered here runs AFTER every InitialModule, so a module may depend on
-- frames another module built in its own Initialize().
--
-- Layout is the reason this exists: `Layout\Load_Layout.xml` sits BEFORE
-- `Modules\Load_Modules.xml` in the .toc (matching real ElvUI's file order),
-- so with a single tier it would initialize first -- before the Minimap
-- holder, the chat panels and DataTexts exist, all of which it touches.
--
-- Registration after OnEnable has already run (a module file loaded late,
-- e.g. an on-demand plugin) initializes immediately instead of queuing into
-- a list nothing will drain again.
function AddOn:RegisterModule(name, initFunc)
	if self.modulesInitialized then
		initFunc()
		return
	end
	table.insert(self.Modules, { name = name, init = initFunc })
end

function AddOn:OnEnable()
	for _, entry in ipairs(self.InitialModules) do
		entry.init()
	end

	for _, entry in ipairs(self.Modules) do
		entry.init()
	end

	self.modulesInitialized = true
end
