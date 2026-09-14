-- ElvUI_Config bootstrap.
--
-- Registers the AceConfig-format options table with LibConfig-1.0 (not
-- AceGUI-3.0/AceConfigDialog-3.0 -- those are known broken on Unreal
-- Azeroth, see source/LibConfig-1.0/README.md). Every option `name`/`desc`
-- goes through AceLocale (`L["..."]`, English text as the key), declared in
-- ElvUI_Config/Locales/enUS.lua under the same "ElvUI" application as the core
-- addon's strings; only English is shipped, but a translation file is a
-- drop-in addition rather than a sweep.
--
-- "Map" section: a `childGroups = "tab"` group with two tabs,
-- "Map" and "Minimap". This is the first real exercise of LibConfig-1.0's
-- tab support.
--
-- The "Map" tab's checkbox is a DELIBERATE placeholder: there is no
-- WorldMap module yet (only Minimap exists so far, see
-- target/ElvUI/Modules/Minimap.lua), so its get/set are dummy -- it
-- renders and can be clicked, but doesn't read or change anything real
-- yet. Wire it to a real DB key once a WorldMap module exists.
--
-- "Minimap" is ITSELF childGroups="tab" (nested tab-in-tab, matching real
-- ElvUI's own Maps.lua structure exactly): a `guiInline = true` "General"
-- section (Enable + Size, rendered in place, not a tab) plus three actual
-- tabs, "Location Text", "Reset Zoom", and "Minimap Buttons" (calendar/
-- mail/PvP-queue icon position/scale/offset). Real ElvUI's own `icons`
-- group does NOT set childGroups="tab" -- in real AceConfigDialog,
-- Calendar/Mail/PvP Queue instead show up as a local list embedded INSIDE
-- the "Minimap Buttons" pane (its own little nested-tree widget, separate
-- from the main sidebar -- confirmed against a screenshot of a real
-- working ElvUI installation). LibConfig-1.0 has no such embedded-
-- list widget, so `iconsGroup` here DOES set childGroups="tab" -- Calendar/
-- Mail/PvP Queue render as a third-level nested tab strip instead. Not a
-- pixel match (horizontal buttons vs. a vertical list), but the same
-- practical result the screenshot showed: navigable locally within this
-- tab, NOT scattered into the global sidebar (an earlier version of this
-- file left `iconsGroup` as plain "tree", which WOULD have leaked them
-- into the global sidebar -- wrong, fixed). Every `set` here that isn't
-- `enable` calls E.Minimap:UpdateSettings() so the change is live, no
-- /reload needed -- matches real ElvUI's own config (its `set` functions
-- call MM:UpdateSettings() the same way).

local LC = LibStub("LibConfig-1.0")
local E, L = ElvUI[1], ElvUI[2]

-- Cross-file helpers. Each option file under this addon is its own Lua chunk, so
-- a file-local is invisible to the others -- only the genuinely SHARED items
-- live here, and everything else stays local to the file that uses it.
-- Parked on the engine table the same way real ElvUI parks `E.Options`.
E.ConfigShared = E.ConfigShared or {}
local Shared = E.ConfigShared

Shared.POSITION_VALUES = {
	LEFT = L["Left"],
	RIGHT = L["Right"],
	TOP = L["Top"],
	BOTTOM = L["Bottom"],
	CENTER = L["Center"],
	TOPLEFT = L["Top Left"],
	TOPRIGHT = L["Top Right"],
	BOTTOMLEFT = L["Bottom Left"],
	BOTTOMRIGHT = L["Bottom Right"],
}

function Shared.UpdateMinimapSettings()
	if E.Minimap and E.Minimap.UpdateSettings then
		E.Minimap:UpdateSettings()
	end
end

-- The options table itself. Registered HERE, before the per-module files load:
-- LibConfig-1.0 stores it by reference, so every `E.Options.args.<module> = ...`
-- those files add afterwards is picked up without re-registering.
E.Options = {
	name = L["ElvUI"],
	type = "group",
	args = {},
}

LC:RegisterOptionsTable("ElvUI", "ElvUI", E.Options)

-- Root-page action buttons, at real ElvUI's own keys and orders (its
-- ElvUI_Config/Core.lua:55-75). These are LEAF args of the root group, so
-- LibConfig-1.0 renders them on the root page's content area rather than as
-- sidebar rows -- the module groups' own orders (1-11) do not interleave with
-- them, which is why upstream's 4/5/6 can be kept verbatim.
--
-- Upstream also has `ElvUI_Header` (needs an E.version this project does not
-- define), `LoginMessage` (the DB field exists but nothing reads it -- a control
-- there would be an invented setting, see docs/config.md rule 5) and
-- `ToggleTutorial` (no tutorials module here). Those three stay out.
--
-- Both toggles CLOSE the config, which upstream's Install button also does:
-- the wizard is a full-screen frame the config would sit on top of, and mover
-- handles cannot be dragged from behind the options window.
E.Options.args.Install = {
	order = 4,
	type = "execute",
	name = L["Install"],
	desc = L["Run the installation process."],
	func = function()
		LC:Close()
		E:ToggleInstallWizard()
	end,
}

E.Options.args.ToggleAnchors = {
	order = 5,
	type = "execute",
	name = L["Toggle Anchors"],
	desc = L["Unlock various elements of the UI to be repositioned."],
	func = function()
		LC:Close()
		E:ToggleMoveMode()
	end,
}

-- Popup entries added from THIS addon. `E.PopupDialogs` is created by
-- ElvUI/Core/StaticPopups.lua, which always loads first (RequiredDeps), but the
-- `or {}` keeps this file independent of that ordering -- and the show function
-- re-copies the registry on every call precisely so late entries like these
-- still reach Blizzard's own table.
E.PopupDialogs = E.PopupDialogs or {}

-- Confirmed through a popup rather than fired straight off the click: this drops
-- every saved mover position at once, and it sits one row under a button that
-- merely unlocks them. Upstream guards its own equivalent the same way (its
-- E:ResetUI shows a static popup).
E.PopupDialogs["RESET_ALL_MOVERS"] = {
	text = L["Reset every frame to its original position? All saved mover positions will be lost."],
	button1 = E.PopupAccept,
	button2 = E.PopupCancel,
	OnAccept = function() E:ResetAllMovers() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = true,
}

E.Options.args.ResetAllMovers = {
	order = 6,
	type = "execute",
	name = L["Reset Anchors"],
	desc = L["Reset all frames to their original positions."],
	func = function() E:StaticPopup_Show("RESET_ALL_MOVERS") end,
}

-- Last-generated export text, empty until the "Generate Export" button
-- is actually clicked. The export field's own `get` used to
-- call E:ExportProfile() live, meaning simply OPENING the Profiles page
-- re-serialized the entire profile table on every render -- surprising
-- (an unasked-for wall of text appearing immediately) and wasteful
-- (Util.TableToLuaString does a full recursive walk + string
-- concatenation, not cheap to redo on every page visit). Real ElvUI's
-- own export is button-triggered too, not continuously live -- matched
-- here.
local exportText = ""

-- Every profile EXCEPT this character's own -- AceDBOptions-3.0 calls this
-- `arg = "nocurrent"` and uses it for Copy From and Delete, where the active
-- profile is never a sensible target.
local function ProfileValues()
	local list = E:GetProfileList()
	list[E:GetProfileKey()] = nil
	return list
end

-- Every profile INCLUDING this character's own -- for the "Existing Profiles"
-- switcher, which shows the current one as the selected entry.
local function AllProfileValues()
	return E:GetProfileList()
end

-- Scratch state for the two "pick a target, then confirm" controls. Neither can
-- act on selection alone: Copy replaces this character's whole profile and
-- Delete destroys another one, so both go through a confirm popup, and the popup
-- needs to know what was picked. Not persisted -- LibConfig re-renders the group
-- on every visit.
local copySource, deleteTarget

-- Confirmations use the static-popup system (ElvUI/Core/StaticPopups.lua), NOT
-- an option-table `confirm`/`confirmText` field: LibConfig-1.0 carries `confirm`
-- in its inherited-member list but does not render a confirmation dialog for it,
-- so relying on it would silently fire the action with no prompt at all.
E.PopupDialogs["PROFILE_COPY"] = {
	text = L["Replace this character's entire profile with an independent copy of the selected one?"],
	button1 = E.PopupAccept,
	button2 = E.PopupCancel,
	OnAccept = function()
		if copySource then
			E:CopyProfile(copySource)
			E:RequestReload()
		end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = true,
}

E.PopupDialogs["PROFILE_RESET"] = {
	text = L["Reset this character's profile back to its default values? Every setting you have changed on this profile will be lost."],
	button1 = E.PopupAccept,
	button2 = E.PopupCancel,
	OnAccept = function()
		E:ResetProfile()
		E:RequestReload()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = true,
}

E.PopupDialogs["PROFILE_DELETE"] = {
	text = L["Are you sure you want to delete the selected profile?"],
	button1 = E.PopupAccept,
	button2 = E.PopupCancel,
	OnAccept = function()
		if deleteTarget then
			E:DeleteProfile(deleteTarget)
			deleteTarget = nil
		end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = true,
}

E.Options.args.profiles = {
	type = "group",
	name = L["Profiles"],
	order = 11,
	args = {
		-- Entry KEYS, labels, descriptions and relative order all follow
		-- AceDBOptions-3.0's own profile panel (its optionsTable: desc /
		-- descreset / reset / current / choosedesc / new / choose / copydesc /
		-- copyfrom / deldesc / delete) -- that is the panel every Ace3 addon
		-- shows, so it is the one a user has already learned. Its own order
		-- numbers (1, 9, 10, 11, 20, 30, 40, 50, 60, 70, 80) are kept verbatim,
		-- which leaves room between blocks and puts Export/Import after all of
		-- them at 90+.
		--
		-- This section is NOT part of the tree-fidelity comparison against real
		-- ElvUI (scripts/check-options.lua excludes it): real ElvUI hands the
		-- whole thing to AceDBOptions, which the checker's stub environment
		-- cannot build. Matching the LIBRARY's shape is therefore the closest
		-- thing to "same place as the original" available here.
		desc = {
			type = "description",
			order = 1,
			name = L["You can change the active database profile, so you can have different settings for every character.\n\nProfiles are shared account-wide by name. Switching points this character at an existing profile, sharing it going forward -- editing it on either character then changes both. Copying takes an independent snapshot instead. Every action here requires a reload to take effect."],
		},
		descreset = {
			type = "description",
			order = 9,
			name = L["\nReset the current profile back to its default values, in case your configuration is broken, or you simply want to start over."],
		},
		reset = {
			type = "execute",
			name = L["Reset Profile"],
			desc = L["Reset the current profile to the default"],
			order = 10,
			func = function() E:StaticPopup_Show("PROFILE_RESET") end,
		},
		current = {
			type = "description",
			order = 11,
			name = function() return "Current Profile: "..(E:GetProfileKey() or "?") end,
		},
		choosedesc = {
			type = "description",
			order = 20,
			name = L["\nYou can either create a new profile by entering a name in the editbox, or choose one of the already existing profiles."],
		},
		-- An `input`, as in AceDBOptions: typing a name and confirming creates
		-- that profile and switches to it. `get` returns "" rather than being
		-- omitted so the box always renders empty and never shows the last
		-- name typed as though it were stored state.
		new = {
			type = "input",
			name = L["New"],
			desc = L["Create a new empty profile."],
			order = 30,
			get = function() return "" end,
			set = function(_, value)
				if E:CreateProfile(value) then
					E:RequestReload()
				end
			end,
		},
		-- Switching is the one action that needs no confirmation: it destroys
		-- nothing, and switching back is a second pick from the same list.
		choose = {
			type = "select",
			name = L["Existing Profiles"],
			desc = L["Select one of your currently available profiles."],
			order = 40,
			values = AllProfileValues,
			get = function() return E:GetProfileKey() end,
			set = function(_, value)
				E:UseProfile(value)
				E:RequestReload()
			end,
		},
		copydesc = {
			type = "description",
			order = 50,
			name = L["\nCopy the settings from one existing profile into the currently active profile."],
		},
		copyfrom = {
			type = "select",
			name = L["Copy From"],
			desc = L["Copy the settings from one existing profile into the currently active profile."],
			order = 60,
			values = ProfileValues,
			get = function() return copySource end,
			set = function(_, value)
				copySource = value
				E:StaticPopup_Show("PROFILE_COPY")
			end,
			-- Nothing to copy from when this character's profile is the only one.
			disabled = function() return not next(ProfileValues()) end,
		},
		deldesc = {
			type = "description",
			order = 70,
			name = L["\nDelete existing and unused profiles from the database to save space, and cleanup the SavedVariables file."],
		},
		delete = {
			type = "select",
			name = L["Delete a Profile"],
			desc = L["Deletes a profile from the database."],
			order = 80,
			values = ProfileValues,
			get = function() return deleteTarget end,
			set = function(_, value)
				deleteTarget = value
				E:StaticPopup_Show("PROFILE_DELETE")
			end,
			disabled = function() return not next(ProfileValues()) end,
		},
		exportHeader = {
			type = "header",
			name = L["Export / Import"],
			order = 90,
		},
		exportIntro = {
			type = "description",
			order = 91,
			name = L["A plain Lua table -- NOT the compressed/encoded format some addons use. Click Generate, then select all (Ctrl+A) and copy from the box below to export this character's current profile as text. A profile exported from real ElvUI-vanilla's own \"Export as Lua Table\" option can be pasted into the Import box as-is."],
		},
		generateExport = {
			type = "execute",
			name = L["Generate Export"],
			desc = L["(Re)computes the export text below from this character's current profile."],
			order = 92,
			func = function()
				-- Flattened to ONE line -- live-reported (screenshot):
				-- the multi-line text (Util.TableToLuaString inserts a
				-- real "\n" + indentation between every table entry)
				-- rendered completely unclipped in the small "input"
				-- EditBox, sprawling across and behind the entire
				-- options window instead of staying confined to its
				-- own box. This vintage client has no SetClipsChildren
				-- to fall back on, and a real clipped multi-line view
				-- would need a ScrollFrame-backed widget this project
				-- doesn't have yet -- stripping the newlines/indentation
				-- entirely removes the cause instead (whitespace
				-- doesn't matter to loadstring on import either way).
				local text = E:ExportProfile()
				text = string.gsub(text, "\n%s*", " ")
				exportText = text
			end,
		},
		export = {
			type = "input",
			name = L["Export (read from here)"],
			width = "full",
			order = 93,
			get = function() return exportText end,
			set = function() end,
		},
		import = {
			type = "input",
			name = L["Import (paste here, press Enter)"],
			width = "full",
			order = 94,
			get = function() return "" end,
			set = function(_, value) E:ImportProfile(value) end,
		},
	},
}
