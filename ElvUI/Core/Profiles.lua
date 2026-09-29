-- Profile management -- create/switch/copy/reset/delete which saved profile a
-- character uses.
--
-- The operation set and its semantics follow AceDBOptions-3.0's own profile
-- panel (new / choose / copyfrom / reset / delete), because that is the panel
-- every Ace3 addon shows and therefore the one a user already knows. The
-- LIBRARY itself is not used -- it is deliberately not vendored here, and
-- it only knows how to drive a real AceDB database
-- object, which this project does not have (below).
--
-- NOT built on AceDB-3.0's own runtime API (`:New()`/`:SetProfile()`/
-- `:CopyProfile()`), even though the library is vendored -- Init.lua
-- never calls `LibStub("AceDB-3.0"):New(...)`, it hand-rolls the same
-- profile-keyed-by-character-name scheme directly against ElvDB/
-- ElvPrivateDB (`profileKeys`/`profiles`, see Init.lua's own header
-- comment). These functions operate on that same hand-rolled scheme, not
-- on an AceDB database object.
--
-- Deliberately reload-required, matching this project's established
-- convention for anything structurally significant (several modules
-- cache a direct reference to a E.db sub-table once at Initialize time,
-- e.g. DataBars.lua's `M.db = E.db.databars` -- reassigning E.db live
-- wouldn't reach those, so this doesn't try; it only ever mutates
-- ElvDB/ElvPrivateDB, which OnInitialize re-reads from scratch on the
-- next load).

local E, L, V, P, G = unpack(ElvUI)

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

local function CharKey()
	return E.myname.." - "..E.myrealm
end

-- The profile key this character is currently pointed at.
function E:GetProfileKey()
	return ElvDB.profileKeys[CharKey()]
end

-- Every known profile key (both ElvDB and ElvPrivateDB, unioned -- a
-- profile can exist in one without the other, e.g. right after a fresh
-- E:UseProfile call that only had a match on one side), as a
-- value->value table (LibConfig-1.0's "select" `values` expects
-- value->displayText, and a profile key IS its own display text here).
function E:GetProfileList()
	local list = {}
	local key
	for key in pairs(ElvDB.profiles) do
		list[key] = key
	end
	for key in pairs(ElvPrivateDB.profiles) do
		list[key] = key
	end
	return list
end

-- Replaces THIS character's own profile (both ElvDB and ElvPrivateDB)
-- with an independent deep copy of `sourceKey`'s data. Afterward the two
-- profiles are separate -- editing one doesn't touch the other.
function E:CopyProfile(sourceKey)
	if type(sourceKey) ~= "string" or sourceKey == "" then return end

	local myKey = self:GetProfileKey()
	if sourceKey == myKey then return end

	if ElvDB.profiles[sourceKey] then
		ElvDB.profiles[myKey] = DeepCopy(ElvDB.profiles[sourceKey])
	end
	if ElvPrivateDB.profiles[sourceKey] then
		ElvPrivateDB.profiles[ElvPrivateDB.profileKeys[CharKey()]] = DeepCopy(ElvPrivateDB.profiles[sourceKey])
	end

	self:Print(string.format(L["Copied profile '%s' onto this character. /reload to apply."], sourceKey))
end

-- Repoints this character at an EXISTING profile key going forward
-- (shared, not copied -- editing it on either character changes both,
-- same semantics as real AceDB's own SetProfile).
function E:UseProfile(targetKey)
	if type(targetKey) ~= "string" or targetKey == "" then return end

	local charKey = CharKey()
	if targetKey == ElvDB.profileKeys[charKey] then return end

	ElvDB.profileKeys[charKey] = targetKey
	ElvPrivateDB.profileKeys[charKey] = targetKey

	self:Print(string.format(L["Now using profile '%s'. /reload to apply."], targetKey))
end

-- Creates a NEW, empty profile under `name` and points this character at it.
-- Empty means "no stored keys at all", which is exactly what a fresh profile is
-- under this scheme: Init.lua merges the defaults over whatever the profile
-- holds, so an empty table renders as pure defaults.
--
-- Matches AceDBOptions-3.0's own `new` behaviour (its handler calls SetProfile
-- with a name that does not exist yet, and AceDB creates it on demand). Refuses
-- a name that is already taken, rather than silently switching to it -- the
-- "Existing Profiles" control is for that, and a silent switch here would look
-- like a successful creation while quietly discarding nothing.
function E:CreateProfile(name)
	if type(name) ~= "string" then return false end
	name = string.gsub(name, "^%s*(.-)%s*$", "%1")
	if name == "" then return false end

	if ElvDB.profiles[name] or ElvPrivateDB.profiles[name] then
		self:Print(string.format(L["A profile named '%s' already exists -- pick another name, or switch to it under Existing Profiles."], name))
		return false
	end

	local charKey = CharKey()
	ElvDB.profiles[name] = {}
	ElvPrivateDB.profiles[name] = {}
	ElvDB.profileKeys[charKey] = name
	ElvPrivateDB.profileKeys[charKey] = name

	self:Print(string.format(L["Created profile '%s' and switched to it. /reload to apply."], name))
	return true
end

-- Resets THIS character's profile back to defaults, by emptying its stored
-- table -- see CreateProfile above on why empty == defaults. The profile KEY and
-- this character's pointer to it are untouched, matching AceDBOptions' own
-- `reset`, which resets the current profile rather than deleting it.
function E:ResetProfile()
	local key = self:GetProfileKey()
	if not key then return false end

	ElvDB.profiles[key] = {}
	local privateKey = ElvPrivateDB.profileKeys[CharKey()]
	if privateKey then
		ElvPrivateDB.profiles[privateKey] = {}
	end

	self:Print(string.format(L["Profile '%s' reset to defaults. /reload to apply."], key))
	return true
end

-- Deletes a profile outright. Refuses the profile this character is CURRENTLY
-- using -- AceDBOptions hides the active one from its own delete list for the
-- same reason (`arg = "nocurrent"`), and allowing it would leave this character
-- pointing at a key with no data behind it.
--
-- Other characters pointing at the deleted key are deliberately NOT repointed:
-- their `profileKeys` entry survives, so on their next login the merge finds no
-- stored data and they come up on defaults under the same name -- the same
-- outcome AceDB produces, and less surprising than silently moving someone
-- else's character onto a profile they never chose.
function E:DeleteProfile(key)
	if type(key) ~= "string" or key == "" then return false end
	if key == self:GetProfileKey() then
		self:Print(L["Refusing to delete the profile this character is using -- switch to another one first."])
		return false
	end

	ElvDB.profiles[key] = nil
	ElvPrivateDB.profiles[key] = nil

	self:Print(string.format(L["Deleted profile '%s'."], key))
	return true
end

-- Profile data written by earlier versions of this addon, by ElvUI-vanilla or
-- by retail ElvUI, moved onto the current keys. Runs on the live profile at
-- login (Init.lua) and on every imported profile before it is cleaned
-- (E:ImportProfile).
--
-- Each step is triggered by something our defaults never contain: an old key
-- of ours, another ElvUI's name for one of our keys, or another ElvUI's
-- value or table shape for one of them. A stored profile carries every
-- default too (Init.lua merges them in and saves the result), so only such a
-- key or value marks data to migrate, and replacing it makes the step run
-- once.

-- Copies every value of `src` into `dst`, descending into tables both sides
-- have, so keys only `dst` has survive.
local function MergeInto(dst, src)
	local k, v
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			MergeInto(dst[k], v)
		else
			dst[k] = v
		end
	end
end

-- Moves t[from] to t[to]. A present `from` always wins: nothing here writes
-- it any more, so it holds what the user chose (in another ElvUI) or sees
-- now (under this addon's earlier name), while t[to] may be no more than a
-- merged-in default. A table is merged key by key rather than replaced: a
-- saved or exported table holds only the values that differ from its own
-- defaults, and the defaults already merged into t[to] must stay.
local function RenameKey(t, from, to)
	local value = t[from]
	if value == nil then return end
	if type(value) == "table" and type(t[to]) == "table" then
		MergeInto(t[to], value)
	else
		t[to] = value
	end
	t[from] = nil
end

local ACTIONBAR_RENAMES = {
	buttonSize = "buttonsize",
	buttonSpacing = "buttonspacing",
}

-- Mover keys: the names this addon used before it took real ElvUI's, and
-- retail's pet bar name (ElvUI-vanilla, and this addon, use "ElvBar_Pet").
local MOVER_RENAMES = {
	ElvUF_Player = "ElvUF_PlayerMover",
	ElvUF_Target = "ElvUF_TargetMover",
	ElvUF_TargetTarget = "ElvUF_TargetTargetMover",
	ElvUF_Pet = "ElvUF_PetMover",
	ElvUF_PetTarget = "ElvUF_PetTargetMover",
	ElvUF_PlayerCastbar = "ElvUF_PlayerCastbarMover",
	ElvUF_TargetCastbar = "ElvUF_TargetCastbarMover",
	ElvBar_StanceBar = "ShiftAB",
	PetAB = "ElvBar_Pet",
}

-- Retail's "SHADOW" (no outline, drop shadow) and "SHADOWOUTLINE" are not
-- font flags this addon can draw; every key named *outline gets the nearest
-- flag it can.
local OUTLINE_VALUES = { SHADOW = "NONE", SHADOWOUTLINE = "OUTLINE" }

local function TranslateOutlines(t)
	local k, v
	for k, v in pairs(t) do
		if type(v) == "table" then
			TranslateOutlines(v)
		elseif type(k) == "string" and OUTLINE_VALUES[v] and string.find(string.lower(k), "outline$") then
			t[k] = OUTLINE_VALUES[v]
		end
	end
end

-- Retail names the tooltip visibility modes SHOW / HIDE, ElvUI-vanilla (and
-- this addon) NONE / ALL; the modifier modes are the same on both.
local VISIBILITY_VALUES = { SHOW = "NONE", HIDE = "ALL" }

-- Retail keeps these as tables where this addon keeps a single value. A
-- retail table carries only what differs from retail's own defaults, so a
-- missing field is read as retail's default.
local function ConvertHealPrediction(units)
	local unit, db
	for unit, db in pairs(units) do
		if type(db) == "table" and type(db.healPrediction) == "table" then
			local enable = db.healPrediction.enable
			if type(enable) ~= "boolean" then
				local default = P.unitframe.units[unit]
				enable = type(default) == "table" and default.healPrediction or nil
			end
			db.healPrediction = enable
		end
	end
end

local function ConvertItemCount(tooltip)
	local count = tooltip.itemCount
	if type(count) ~= "table" then return end
	local bags, bank = count.bags ~= false, count.bank == true
	if bags and bank then
		tooltip.itemCount = "BOTH"
	elseif bags then
		tooltip.itemCount = "BAGS_ONLY"
	elseif bank then
		tooltip.itemCount = "BANK_ONLY"
	else
		tooltip.itemCount = "NONE"
	end
end

function E:MigrateProfileData(profile)
	if type(profile) ~= "table" then return end

	TranslateOutlines(profile)

	local tooltip = profile.tooltip
	if type(tooltip) == "table" then
		if type(tooltip.visibility) == "table" then
			local k, v
			for k, v in pairs(tooltip.visibility) do
				if VISIBILITY_VALUES[v] then tooltip.visibility[k] = VISIBILITY_VALUES[v] end
			end
		end
		ConvertItemCount(tooltip)
	end

	-- Retail ElvUI's stance bar table and camel-case action bar keys ->
	-- ElvUI-vanilla's (ours). Every bar table is visited, so bars without a
	-- counterpart here are renamed too and left for the import cleaner to
	-- drop.
	local actionbar = profile.actionbar
	if type(actionbar) == "table" then
		RenameKey(actionbar, "stanceBar", "barShapeShift")
		local _, bar, from, to
		for _, bar in pairs(actionbar) do
			if type(bar) == "table" then
				for from, to in pairs(ACTIONBAR_RENAMES) do
					RenameKey(bar, from, to)
				end
			end
		end
	end

	if type(profile.movers) == "table" then
		local from, to
		for from, to in pairs(MOVER_RENAMES) do
			RenameKey(profile.movers, from, to)
		end
	end

	local units = type(profile.unitframe) == "table" and profile.unitframe.units
	if type(units) == "table" then ConvertHealPrediction(units) end
	local pet = type(units) == "table" and units.pet

	-- ElvUI-vanilla's separate pet happiness bar -> retail's happiness colour
	-- on the pet health bar. An enabled bar keeps happiness shown; a disabled
	-- one cannot be told apart from the untouched default, so it leaves
	-- retail's default (on). `autoHide` and `width` have no counterpart.
	if type(pet) == "table" and pet.happiness ~= nil then
		if type(pet.happiness) == "table" and pet.happiness.enable == true then
			if pet.health == nil then pet.health = {} end
			if type(pet.health) == "table" then
				pet.health.colorHappiness = true
			end
		end
		pet.happiness = nil
	end
end

-- Migrations that must look at a profile as it was STORED, before Init.lua
-- merges the defaults in (after the merge every key is present and the
-- steps below could no longer tell an old profile from a new one).
--
-- Unit frame aura bars arrived with `aurabar.enable = true` (real ElvUI's
-- default), and at the same time `attachTo = "BUFFS"/"DEBUFFS"` started to
-- stack the aura grids; before, those values drew on the frame. A profile
-- from before would therefore change its look on first load. It gets what
-- the installer's "Icons Only" sets instead (without resetting the rest).
--
-- Such a profile is recognised by Init.lua's full save: it carries the
-- player's complete buff table but no `aurabar`. An imported profile holds
-- only what differs from the defaults and lacks those keys.
local function IsPreAuraBarProfile(stored)
	local unitframe = type(stored) == "table" and stored.unitframe
	local units = type(unitframe) == "table" and unitframe.units
	local player = type(units) == "table" and units.player
	if type(player) ~= "table" or player.aurabar ~= nil then return false end
	local buffs = player.buffs
	return type(buffs) == "table" and buffs.enable ~= nil and buffs.attachTo ~= nil
		and buffs.anchorPoint ~= nil and buffs.perrow ~= nil
end

function E:MigrateStoredProfile(stored)
	if not IsPreAuraBarProfile(stored) then return end
	local units = stored.unitframe.units
	local player = units.player
	player.aurabar = { enable = false }
	player.buffs.enable = true
	player.buffs.attachTo = "FRAME"
	if type(player.debuffs) ~= "table" then player.debuffs = {} end
	player.debuffs.attachTo = "BUFFS"
	if type(units.target) ~= "table" then units.target = {} end
	local target = units.target
	target.aurabar = { enable = false }
	if type(target.buffs) ~= "table" then target.buffs = {} end
	target.buffs.attachTo = "FRAME"
	if type(target.debuffs) ~= "table" then target.debuffs = {} end
	target.debuffs.enable = true
	target.debuffs.attachTo = "BUFFS"
end

-- Export / Import
--
-- Two formats, both ending in real ElvUI's "::type::key" / "::type" suffix
-- (retail Distributor.lua `D:CreateProfileExport`):
--   "text"      the "!E2!" string of current ElvUI (Core/ProfileCodec.lua)
--   "luaTable"  a plain Lua table literal on one line
-- Types: "profile" (this character's profile, suffixed with its name) and
-- "private" (this character's private settings: module switches, skins,
-- textures). Real ElvUI also exports "global" and "filters"; an import of
-- those is declined with a message. An import additionally reads
-- ElvUI-vanilla's "text" export (Base64 without a prefix).
--
-- An export holds only what differs from this addon's defaults (retail
-- `E:RemoveTableDuplicates`), without the keys retail never exports
-- (`D.blacklistedKeys`), plus the marker `elvuiUA = { version = ... }` at the
-- top level. The marker identifies a string from this addon: its values are
-- relative to OUR defaults, and its version lets an older copy of the addon
-- refuse it. A string without the marker came from another ElvUI.
--
-- An import is migrated (E:MigrateProfileData), then a string from another
-- ElvUI has the keys it left at that ElvUI's defaults filled with those
-- defaults (E.ImportDefaults, Settings/ImportDefaults.lua), then everything
-- is cleaned against our defaults before it is stored: unknown keys and
-- values of the wrong type are dropped and counted. Init.lua merges our
-- defaults back in at the next load, which is why every import ends in a
-- reload request.

local Codec = ElvUI.ProfileCodec
local EXPORT_MARKER = "elvuiUA"

local DEFAULTS = { profile = P, private = V }

-- Keys written at runtime without a default that are exported anyway
-- (retail `D.GeneratedKeys`). An EMPTY default table is open without being
-- listed here: its children are user data (movers, custom texts).
local GENERATED = {
	profile = {},
	private = { installComplete = true, theme = true },
}

-- Keys that are never exported or imported (the entries of retail
-- `D.blacklistedKeys` this addon has): screen- and language-specific.
local BLACKLIST = {
	profile = { gridSize = true, general = { numberPrefixStyle = true } },
	private = {},
}

local function CountLeaves(value)
	if type(value) ~= "table" then return 1 end
	local n = 0
	local k, v
	for k, v in pairs(value) do
		n = n + CountLeaves(v)
	end
	return n
end

-- A copy of `data` reduced to what differs from `defaults`. A key with no
-- default is dropped unless `generated` names it; a value whose type differs
-- from its default's is dropped; blacklisted keys are left out. Returns the
-- copy and the number of dropped leaf values (blacklisted ones not counted).
local function CleanTable(data, defaults, generated, blacklist)
	local out, dropped = {}, 0
	local k, v
	for k, v in pairs(data) do
		local default = defaults[k]
		local black = blacklist and blacklist[k]
		if black == true then
			-- never carried
		elseif default == nil then
			if generated and generated[k] then
				out[k] = type(v) == "table" and DeepCopy(v) or v
			else
				dropped = dropped + CountLeaves(v)
			end
		elseif type(v) ~= type(default) then
			dropped = dropped + CountLeaves(v)
		elseif type(v) == "table" then
			if next(default) == nil then
				if next(v) ~= nil then out[k] = DeepCopy(v) end
			else
				local subGenerated = generated and generated[k]
				if type(subGenerated) ~= "table" then subGenerated = nil end
				if type(black) ~= "table" then black = nil end
				local sub, subDropped = CleanTable(v, default, subGenerated, black)
				dropped = dropped + subDropped
				if next(sub) ~= nil then out[k] = sub end
			end
		elseif v ~= default then
			out[k] = v
		end
	end
	return out, dropped
end

-- The stored table and its key for one export type of this character.
local function StoredData(dataType)
	local charKey = CharKey()
	local key
	if dataType == "profile" then
		key = ElvDB.profileKeys[charKey]
		return key, key and ElvDB.profiles[key]
	elseif dataType == "private" then
		key = ElvPrivateDB.profileKeys[charKey]
		return key, key and ElvPrivateDB.profiles[key]
	end
end

-- The .toc "## Version:" the packager fills in from the release tag.
local function AddonVersion()
	local version = GetAddOnMetadata and GetAddOnMetadata("ElvUI", "Version")
	if type(version) ~= "string" or version == "" then return "unknown" end
	return version
end

-- major, minor, patch of a "v0.8.0" / "0.8.0-3-gabc123" style version, or
-- nil when it has none (an unpackaged development copy).
local function ParseVersion(version)
	if type(version) ~= "string" then return nil end
	local _, _, major, minor, patch = string.find(version, "^v?(%d+)%.(%d+)%.?(%d*)")
	if not major then return nil end
	return tonumber(major), tonumber(minor), tonumber(patch) or 0
end

-- Is `theirs` a later release than `mine`? False when either is unparsable.
local function IsNewerVersion(theirs, mine)
	local a1, a2, a3 = ParseVersion(theirs)
	local b1, b2, b3 = ParseVersion(mine)
	if not a1 or not b1 then return false end
	if a1 ~= b1 then return a1 > b1 end
	if a2 ~= b2 then return a2 > b2 end
	return a3 > b3
end

-- Returns the export string of `dataType` ("profile" / "private") in
-- `exportFormat` ("text" / "luaTable"), or nil.
function E:ExportProfile(dataType, exportFormat)
	local key, stored = StoredData(dataType)
	if not stored then return nil end

	local data = CleanTable(stored, DEFAULTS[dataType], GENERATED[dataType], BLACKLIST[dataType])
	data[EXPORT_MARKER] = { version = AddonVersion() }

	if exportFormat == "text" then
		return Codec.Encode(dataType, key, data)
	end

	-- One line: shorter to carry and safe in any one-line field. The table
	-- writer escapes newlines inside strings, so only layout is removed.
	local text = string.gsub(ElvUI.Util.TableToLuaString(data), "\n%s*", " ")
	text = text.."::"..dataType
	if dataType == "profile" then
		text = text.."::"..key
	end
	return text
end

local function ParseTable(text)
	local chunk = loadstring("return "..text)
	if not chunk then return nil end
	local ok, result = pcall(chunk)
	if ok and type(result) == "table" then return result end
end

-- A Lua table literal with an optional "::type::key" / "::type" suffix: this
-- addon's own "luaTable" export, real ElvUI's (vanilla and retail), or a bare
-- table. Real ElvUI doubles every "|" for display in its edit box and retail
-- expects the closing brace to be missing, so both repairs are tried.
local function DecodeTable(text)
	local body, dataType, key = text
	local _, _, b, t, k = string.find(text, "^(.*)::([^:]-)::(.-)$")
	if b and Codec.TYPES[t] then
		body, dataType, key = b, t, k
	else
		_, _, b, t = string.find(text, "^(.*)::([^:]-)$")
		if b and Codec.TYPES[t] then
			body, dataType = b, t
		end
	end

	local unescaped = string.gsub(body, "\124\124", "\124")
	local data = ParseTable(body) or ParseTable(body.."}")
		or ParseTable(unescaped) or ParseTable(unescaped.."}")
	if not data then return nil end
	if dataType ~= "profile" then key = nil end
	if key == "" then key = nil end
	return dataType or "profile", key, data
end

-- Retail ElvUI writes these into a profile itself (its data conversions and
-- camel-case action bar keys); ElvUI-vanilla has none of them.
local function LooksRetail(data)
	if data.dbConverted ~= nil or data.convertPages ~= nil then return true end
	local actionbar = data.actionbar
	if type(actionbar) ~= "table" then return false end
	if actionbar.stanceBar ~= nil then return true end
	local _, bar
	for _, bar in pairs(actionbar) do
		if type(bar) == "table" and (bar.buttonSize ~= nil or bar.buttonSpacing ~= nil) then
			return true
		end
	end
	return false
end

-- Sets every value of `defaults` that `data` leaves out; returns how many.
local function FillMissing(data, defaults)
	local n, k, v = 0
	for k, v in pairs(defaults) do
		local current = data[k]
		if type(v) == "table" then
			if current == nil then
				current = {}
				data[k] = current
			end
			if type(current) == "table" then n = n + FillMissing(current, v) end
		elseif current == nil then
			data[k] = v
			n = n + 1
		end
	end
	return n
end

-- Decodes an import string without storing anything. Returns dataType, key
-- (nil for a type without one, or a bare table), data, the exporting version
-- of this addon (nil for a string from another ElvUI), and the other ElvUI
-- it came from ("retail" or "vanilla", a key of E.ImportDefaults; nil for
-- this addon's own); or nil and a message for the player.
function E:DecodeProfileString(text)
	if type(text) ~= "string" then return nil, L["Error decoding data. Import string may be corrupted!"] end
	local _, _, body = string.find(text, "^%s*(.-)%s*$")

	local dataType, key, data, source
	local first = string.sub(body, 1, 1)
	if first == "!" then
		source = "retail"
		dataType, key, data = Codec.Decode(body)
		if not dataType then
			if key == "old" then
				return nil, L["This import string uses an older ElvUI format (!E1!) that is no longer supported. Export it again from a current ElvUI."]
			end
			return nil, L["Error decoding data. Import string may be corrupted!"]
		end
	elseif first == "{" then
		dataType, key, data = DecodeTable(body)
		if not dataType then
			return nil, L["Import failed -- couldn't parse the pasted text as a Lua table."]
		end
	else
		-- ElvUI-vanilla's "text" export: bare Base64, no prefix.
		source = "vanilla"
		dataType, key, data = Codec.DecodeVanilla(body)
		if not dataType then
			return nil, L["Error decoding data. Import string may be corrupted!"]
		end
	end

	local marker = data[EXPORT_MARKER]
	data[EXPORT_MARKER] = nil
	local version
	if type(marker) == "table" then
		version = tostring(marker.version or "unknown")
		source = nil
	elseif first == "{" then
		source = LooksRetail(data) and "retail" or "vanilla"
	end
	return dataType, key, data, version, source
end

-- An unused profile name "<base> (2)", "<base> (3)", ...
local function FreeProfileKey(base)
	local n = 2
	local candidate = base.." (2)"
	while ElvDB.profiles[candidate] or ElvPrivateDB.profiles[candidate] do
		n = n + 1
		candidate = base.." ("..n..")"
	end
	return candidate
end

-- Stores an imported profile under `key` and points this character's
-- PROFILE at it. The private settings key is left as it is, as in retail's
-- import: a profile import must not reset the character's module switches.
-- From here the two keys may differ, which Init.lua supports (it resolves
-- each through its own `profileKeys`).
-- The reload request after an import carries the import's summary: chat
-- output does not survive the reload, the popup is read before it.
E.PopupDialogs["IMPORT_RL"] = {
	button1 = E.PopupAccept,
	button2 = E.PopupCancel,
	OnAccept = ReloadUI,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = false,
}

-- `notes`: lines to show before the summary ("" for none).
local function RequestImportReload(notes, summary, reloadText)
	E:Print(summary)
	E.PopupDialogs["IMPORT_RL"].text = notes .. summary .. "\n\n" .. reloadText
	E:StaticPopup_Show("IMPORT_RL")
end

local function StoreProfile(key, data, count, dropped, notes)
	ElvDB.profiles[key] = data
	ElvDB.profileKeys[CharKey()] = key
	RequestImportReload(notes or "",
		string.format(L["Imported profile '%s': %d settings, %d unknown settings skipped."], key, count, dropped),
		L["One or more of the changes you have made require a ReloadUI."])
end

-- The import waiting on the name-clash popup below.
local pendingImport

-- A name clash offers overwrite or keep-both rather than a rename box: the
-- native popup's edit box is not reliable on every client this addon
-- supports. Escape is disabled so the dialog always ends in one of the two.
E.PopupDialogs["IMPORT_PROFILE_EXISTS"] = {
	OnAccept = function()
		local p = pendingImport
		pendingImport = nil
		if p then StoreProfile(p.key, p.data, p.count, p.dropped, p.notes) end
	end,
	OnCancel = function()
		local p = pendingImport
		pendingImport = nil
		if p then StoreProfile(FreeProfileKey(p.key), p.data, p.count, p.dropped, p.notes) end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = false,
}

-- Imports an export string (see the section header). Reload-required.
function E:ImportProfile(text)
	local dataType, key, data, version, source = self:DecodeProfileString(text)
	if not dataType then
		self:Print(key)
		return
	end

	if version and IsNewerVersion(version, AddonVersion()) then
		self:Print(string.format(L["This string was exported by a newer version of ElvUI (%s, you have %s). Update ElvUI, then import it again."], version, AddonVersion()))
		return
	end

	if not DEFAULTS[dataType] then
		self:Print(string.format(L["Importing '%s' settings is not supported yet."], dataType))
		return
	end

	if dataType == "profile" then
		self:MigrateProfileData(data)
	end
	-- A foreign string omits whatever sat at ITS ElvUI's defaults; those keys
	-- get that ElvUI's values, or ours would show where theirs did.
	local notes = ""
	local sourceDefaults = source and E.ImportDefaults and E.ImportDefaults[source]
	if sourceDefaults and sourceDefaults[dataType] then
		local filled = FillMissing(data, sourceDefaults[dataType])
		local message = string.format(L["This string was exported by another ElvUI: %d settings it left at that ElvUI's defaults were set to those defaults."], filled)
		self:Print(message)
		notes = message .. "\n\n"
	end
	local clean, dropped = CleanTable(data, DEFAULTS[dataType], GENERATED[dataType], BLACKLIST[dataType])
	local count = CountLeaves(clean)

	if dataType == "private" then
		local privateKey = ElvPrivateDB.profileKeys[CharKey()]
		if not privateKey then return end
		ElvPrivateDB.profiles[privateKey] = clean
		RequestImportReload(notes,
			string.format(L["Imported private (character) settings: %d settings, %d unknown settings skipped."], count, dropped),
			L["A setting you have changed will change an option for this character only. This setting that you have changed will be uneffected by changing user profiles. Changing this setting requires that you reload your User Interface."])
		return
	end

	key = key or self:GetProfileKey()
	if not key then return end
	-- Only ElvDB counts: every character has private settings under its own
	-- name, and a profile import does not touch them.
	if ElvDB.profiles[key] then
		pendingImport = { key = key, data = clean, count = count, dropped = dropped, notes = notes }
		local dialog = E.PopupDialogs["IMPORT_PROFILE_EXISTS"]
		dialog.text = string.format(L["A profile named '%s' already exists. Overwrite it, or keep both and import this one as '%s'?"], key, FreeProfileKey(key))
		dialog.button1 = L["Overwrite"]
		dialog.button2 = L["Keep Both"]
		self:StaticPopup_Show("IMPORT_PROFILE_EXISTS")
		return
	end

	StoreProfile(key, clean, count, dropped, notes)
end

