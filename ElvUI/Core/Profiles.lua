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

-- Export/Import -- lets a real ElvUI-vanilla profile (exported via ITS OWN
-- "Export as Lua Table" option, ElvUI-vanilla/ElvUI/Core/
-- distributor.lua's `exportFormat == "luaTable"` branch) be pasted into
-- this addon. Deliberately the SIMPLE plain-Lua-table format, not real
-- ElvUI's OTHER "text" export option (AceSerializer+LibCompress+
-- LibBase64) -- neither library is vendored here, and this project's goal
-- is specifically loading a plain-table SavedVariables profile as-is, not
-- the compressed format.
--
-- Exports `ElvDB.profiles[key]` directly -- the SAME table object as
-- `E.db` for the CURRENT character (Init.lua assigns it by reference),
-- so this always reflects live, current settings. Unlike real ElvUI's
-- own export, this does NOT strip values that match the defaults first
-- (`E:RemoveTableDuplicates`) -- simpler, at the cost of a longer export
-- string; add that trimming later if the size becomes a real problem.
function E:ExportProfile()
	local key = self:GetProfileKey()
	local data = key and ElvDB.profiles[key]
	if not data then return "" end
	return ElvUI.Util.TableToLuaString(data)
end

-- Parses a plain Lua table string back into a table and installs it as
-- THIS character's own profile -- reload-required, same as CopyProfile/
-- UseProfile above (this project's own established pattern; nothing
-- here calls a live AceDB SetProfile, there isn't one -- see this file's
-- own header comment).
--
-- Tries the pasted text AS-IS first (covers this addon's own export, or
-- a hand-copied plain table with no wrapper). If that fails to parse,
-- strips a trailing "::profileType::profileKey" suffix (real ElvUI's
-- own Distributor wraps its export this way,
-- `D:CreateProfileExport`/`D:Decode`) and un-escapes "||" back to "|"
-- (real ElvUI escapes it for safe display in a chat-style edit box) and
-- retries once -- covers pasting a real ElvUI-vanilla "Export as Lua
-- Table" string directly.
function E:ImportProfile(dataString)
	if type(dataString) ~= "string" or dataString == "" then return end

	local function TryParse(text)
		local chunk = loadstring("return "..text)
		if not chunk then return nil end
		local ok, result = pcall(chunk)
		if not ok or type(result) ~= "table" then return nil end
		return result
	end

	local parsed = TryParse(dataString)
	if not parsed then
		local stripped = string.gsub(dataString, "::[^:]*::[^:]*$", "")
		stripped = string.gsub(stripped, "\124\124", "\124")
		parsed = TryParse(stripped)
	end

	if not parsed then
		self:Print(L["Import failed -- couldn't parse the pasted text as a Lua table."])
		return
	end

	local key = self:GetProfileKey()
	if not key then return end
	ElvDB.profiles[key] = parsed

	self:Print(L["Profile imported. /reload to apply."])
end
