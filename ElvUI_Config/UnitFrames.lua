local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn
-- Cross-file helpers, created in Core.lua: each option file is its own
-- Lua chunk, so a file-local cannot be seen from another file.
local Shared = E.ConfigShared

-- Shared text_format/position/xOffset/yOffset arg set -- Health/Power/
-- Name tabs of the "UnitFrames" category all have this same 4-field
-- shape (matches real ElvUI's own field names for each). `getTable`
-- returns the live sub-table (e.g. `E.db.unitframe.units.player.health`)
-- fresh on every call, not captured once, so it stays correct across a
-- profile switch. All 4 fields are read live by UnitFrames.lua's own
-- 0.2s poll -- no /reload needed for any of these.
local function UnitTextArgs(getTable, order)
	return {
		text_format = {
			type = "input",
			name = L["Text Format"],
			desc = L["Tag substitution (not the full real-ElvUI tag DSL): [healthcolor] [powercolor] [health:current] [health:max] [health:current-percent] [health:percent] [power:current] [power:max] [power:percent] [name] [level], plus any plain text. Empty = no text."],
			order = order,
			width = "full",
			get = function() return getTable().text_format end,
			set = function(_, value) getTable().text_format = value end,
		},
		-- `attachTextTo`, real ElvUI's own field: which ELEMENT the text sits on,
		-- not just where on it. Upstream's own value set; the default is "Health"
		-- for all three texts, power included, and nil resolves there too (see
		-- UF:ResolveTextAnchor on why nil has to mean the same as the default).
		attachTextTo = {
			type = "select",
			name = L["Attach Text To"],
			order = order + 4,
			values = {
				["Health"] = L["Health"],
				["Power"] = L["Power"],
				["InfoPanel"] = L["Information Panel"],
				["Frame"] = L["Frame"],
			},
			get = function() return getTable().attachTextTo or "Health" end,
			set = function(_, value) getTable().attachTextTo = value end,
		},
		position = {
			type = "select",
			name = L["Position"],
			order = order + 1,
			values = Shared.POSITION_VALUES,
			get = function() return getTable().position end,
			set = function(_, value) getTable().position = value end,
		},
		xOffset = {
			type = "range",
			name = L["X Offset"],
			order = order + 2,
			min = -50, max = 50, step = 1,
			get = function() return getTable().xOffset end,
			set = function(_, value) getTable().xOffset = value end,
		},
		yOffset = {
			type = "range",
			name = L["Y Offset"],
			order = order + 3,
			min = -50, max = 50, step = 1,
			get = function() return getTable().yOffset end,
			set = function(_, value) getTable().yOffset = value end,
		},
	}
end

-- Shared enable/color/anchor/size arg set -- RestIcon/CombatIcon tabs of
-- the "UnitFrames" category. All fields read live (UpdateStateIcon,
-- UnitFrames.lua) -- no /reload needed.
local function StateIconArgs(getTable, order)
	return {
		enable = {
			type = "toggle",
			name = L["Enable"],
			order = order,
			get = function() return getTable().enable end,
			set = function(_, value) getTable().enable = value end,
		},
		defaultColor = {
			type = "toggle",
			name = L["Default (White) Color"],
			order = order + 1,
			get = function() return getTable().defaultColor end,
			set = function(_, value) getTable().defaultColor = value end,
		},
		color = {
			type = "color",
			name = L["Color"],
			desc = L["Used when Default Color is off."],
			hasAlpha = true,
			order = order + 2,
			get = function()
				local c = getTable().color
				return c.r, c.g, c.b, c.a
			end,
			set = function(_, r, g, b, a)
				local c = getTable().color
				c.r, c.g, c.b, c.a = r, g, b, a
			end,
		},
		anchorPoint = {
			type = "select",
			name = L["Anchor Point"],
			desc = L["Corner of the health bar this icon is centered on."],
			order = order + 3,
			values = Shared.POSITION_VALUES,
			get = function() return getTable().anchorPoint end,
			set = function(_, value) getTable().anchorPoint = value end,
		},
		xOffset = {
			type = "range",
			name = L["X Offset"],
			order = order + 4,
			min = -30, max = 30, step = 1,
			get = function() return getTable().xOffset end,
			set = function(_, value) getTable().xOffset = value end,
		},
		yOffset = {
			type = "range",
			name = L["Y Offset"],
			order = order + 5,
			min = -30, max = 30, step = 1,
			get = function() return getTable().yOffset end,
			set = function(_, value) getTable().yOffset = value end,
		},
		size = {
			type = "range",
			name = L["Size"],
			order = order + 6,
			min = 8, max = 40, step = 1,
			get = function() return getTable().size end,
			set = function(_, value) getTable().size = value end,
		},
		-- `texture`/`customTexture`, real ElvUI's own pair. Only two of its four
		-- values: RESTING and RESTING1 name ITS OWN bundled artwork, which this
		-- project does not ship. nil reads as DEFAULT.
		texture = {
			type = "select",
			name = L["Texture"],
			order = order + 7,
			values = {
				["DEFAULT"] = L["Default"],
				["CUSTOM"] = L["Custom"],
			},
			get = function() return getTable().texture or "DEFAULT" end,
			set = function(_, value) getTable().texture = value end,
		},
		customTexture = {
			type = "input",
			name = L["Custom Texture"],
			desc = L["A texture path, e.g. Interface\\Icons\\Spell_Nature_Sleep. Empty falls back to the default icon."],
			order = order + 8,
			width = "full",
			disabled = function() return getTable().texture ~= "CUSTOM" end,
			get = function() return getTable().customTexture or "" end,
			set = function(_, value)
				getTable().customTexture = (value ~= "" and value) or nil
			end,
		},
	}
end

-- Shared Buffs/Debuffs arg set -- real ElvUI field names
-- (enable/perrow/xOffset/yOffset/minDuration/maxDuration); `size` is a
-- project addition (real ElvUI derives icon size from `fontSize`, this
-- project just sets it directly). `minDuration`/`maxDuration` only
-- filter auras this project can actually MEASURE a duration for (see
-- UnitFrames.lua's own "Buffs/Debuffs" header comment on the 3 duration
-- tiers) -- an aura with no known duration always passes through
-- regardless of these, same as real ElvUI's own behavior.
local function AuraArgs(getTable, order)
	return {
		enable = {
			type = "toggle",
			name = L["Enable"],
			order = order,
			get = function() return getTable().enable end,
			set = function(_, value) getTable().enable = value end,
		},
		perrow = {
			type = "range",
			name = L["Per Row"],
			order = order + 1,
			min = 1, max = 16, step = 1,
			get = function() return getTable().perrow end,
			set = function(_, value) getTable().perrow = value end,
		},
		-- Position: real ElvUI's own two fields. `attachTo` picks what the grid
		-- hangs off, `anchorPoint` the point ON that thing -- the container
		-- attaches by the inverse point, so the grid always grows away from it
		-- (see UF:UpdateAuras). BUFFS/DEBUFFS let the two grids stack on each
		-- other, which is upstream's own default for the player's buffs.
		attachTo = {
			type = "select",
			name = L["Attach To"],
			desc = L["What the aura grid hangs off. Buffs/Debuffs stacks it on the other aura grid instead of on the frame."],
			order = order + 15,
			values = {
				["FRAME"] = L["Frame"],
				["HEALTH"] = L["Health"],
				["POWER"] = L["Power"],
				["BUFFS"] = L["Buffs"],
				["DEBUFFS"] = L["Debuffs"],
			},
			get = function() return getTable().attachTo end,
			set = function(_, value) getTable().attachTo = value end,
		},
		anchorPoint = {
			type = "select",
			name = L["Anchor Point"],
			desc = L["Which point of the attach-to frame the grid sits on, and therefore which way it grows."],
			order = order + 16,
			values = Shared.POSITION_VALUES,
			get = function() return getTable().anchorPoint end,
			set = function(_, value) getTable().anchorPoint = value end,
		},
		numrows = {
			type = "range",
			name = L["Num Rows"],
			desc = L["Maximum rows of icons. Together with Per Row this caps how many auras can ever show; 0 means no cap."],
			order = order + 17,
			min = 0, max = 6, step = 1,
			get = function() return getTable().numrows end,
			set = function(_, value) getTable().numrows = value end,
		},
		clickThrough = {
			type = "toggle",
			name = L["Click Through"],
			desc = L["Ignore mouse events, so clicks land on the unit frame underneath instead of on the icon. Also disables the icon's own tooltip."],
			order = order + 18,
			get = function() return getTable().clickThrough end,
			set = function(_, value) getTable().clickThrough = value end,
		},
		-- `sizeOverride`, real ElvUI's own field name (it was `size` here until
		-- the rename). Upstream declares no default and treats 0 as "derive the
		-- size from the font size"; this project has no such formula, so 0 falls
		-- back to a fixed 20 at runtime (UF:UpdateAuras) and the declared default
		-- is a real number instead of 0.
		sizeOverride = {
			type = "range",
			name = L["Size Override"],
			desc = L["Icon edge length. 0 falls back to the built-in default size."],
			order = order + 2,
			min = 0, max = 60, step = 1,
			get = function() return getTable().sizeOverride end,
			set = function(_, value) getTable().sizeOverride = value end,
		},
		-- Sorting. Only the two methods this project can actually answer are
		-- offered: INDEX (the order the client hands the auras back) and
		-- TIME_REMAINING. Upstream also lists DURATION, NAME and PLAYER --
		-- deliberately left out rather than shown broken: we track remaining time
		-- but not total duration, have no aura-name lookup for buffs (only
		-- debuffs, via the tooltip scan), and no caster information at all.
		sortMethod = {
			type = "select",
			name = L["Sort By"],
			desc = L["Method to sort by. Auras with no measurable duration always sort last."],
			order = order + 19,
			values = {
				["TIME_REMAINING"] = L["Time Remaining"],
				["INDEX"] = L["Index"],
			},
			get = function() return getTable().sortMethod end,
			set = function(_, value) getTable().sortMethod = value end,
		},
		sortDirection = {
			type = "select",
			name = L["Sort Direction"],
			order = order + 20,
			values = {
				["ASCENDING"] = L["Ascending"],
				["DESCENDING"] = L["Descending"],
			},
			get = function() return getTable().sortDirection end,
			set = function(_, value) getTable().sortDirection = value end,
		},
		xOffset = {
			type = "range",
			name = L["X Offset"],
			order = order + 3,
			min = -50, max = 50, step = 1,
			get = function() return getTable().xOffset end,
			set = function(_, value) getTable().xOffset = value end,
		},
		yOffset = {
			type = "range",
			name = L["Y Offset"],
			order = order + 4,
			min = -50, max = 50, step = 1,
			get = function() return getTable().yOffset end,
			set = function(_, value) getTable().yOffset = value end,
		},
		minDuration = {
			type = "range",
			name = L["Min Duration"],
			desc = L["Only show an aura if its remaining duration is at least this many seconds. 0 = no minimum. Has no effect on an aura with no known duration."],
			order = order + 5,
			min = 0, max = 300, step = 1,
			get = function() return getTable().minDuration end,
			set = function(_, value) getTable().minDuration = value end,
		},
		maxDuration = {
			type = "range",
			name = L["Max Duration"],
			desc = L["Only show an aura if its remaining duration is at most this many seconds. 0 = no maximum. Has no effect on an aura with no known duration."],
			order = order + 6,
			min = 0, max = 600, step = 1,
			get = function() return getTable().maxDuration end,
			set = function(_, value) getTable().maxDuration = value end,
		},
	}
end

-- Information Panel tab -- real ElvUI field/default verbatim
-- (E.db.unitframe.units[dbKey].infoPanel = {enable, height,
-- transparent}). A bare strip below Health/Power with no text of its
-- own -- see UnitFrames.lua's Construct_InfoPanel comment.
local function InfoPanelArgs(getTable, order)
	return {
		enable = {
			type = "toggle",
			name = L["Enable"],
			order = order,
			get = function() return getTable().enable end,
			set = function(_, value) getTable().enable = value end,
		},
		height = {
			type = "range",
			name = L["Height"],
			order = order + 1,
			min = 8, max = 60, step = 1,
			get = function() return getTable().height end,
			set = function(_, value) getTable().height = value end,
		},
		transparent = {
			type = "toggle",
			name = L["Transparent"],
			order = order + 2,
			get = function() return getTable().transparent end,
			set = function(_, value) getTable().transparent = value end,
		},
	}
end

-- Custom Texts -- real ElvUI's own user-extensible text list (see
-- UnitFrames.lua's own Construct_CustomTexts/UpdateCustomTexts comment
-- for the render side and the full "why" -- this is what lets a real
-- profile put e.g. current AND max power as two separate texts on one
-- bar). `E.db.unitframe.units[dbKey].customTexts` is a plain table keyed
-- by NAME (matches real ElvUI's own schema exactly, for eventual real-
-- profile compatibility) -- this builds ONE LibConfig-1.0 sidebar group
-- PER EXISTING ENTRY, plus a "Create Custom Text" field that adds a new
-- one, mirroring real ElvUI's OWN dynamic-group-per-entry technique
-- (ElvUI_Config/UnitFrames.lua's CreateCustomTextGroup) rather than a
-- fixed-slot approximation -- LibConfig-1.0's tree-building code derives
-- child pages fresh from the live options table each time
-- (BuildRootPage/its own Walk helper re-reads `args` on every render,
-- not a one-time snapshot), so mutating this closure's own `args` table
-- in place is expected to reach the sidebar without any extra "refresh"
-- call -- untested in-game, flag if a new entry doesn't appear until
-- navigating away and back.
local function CustomTextArgs(dbKey)
	local args = {
		intro = {
			type = "description",
			order = 1,
			name = L["Extra text elements, each independently positioned/attached. Uses this addon's own tag list (same as Health/Power/Name's own Text Format field: [healthcolor] [powercolor] [health:current] [health:max] [health:current-percent] [health:percent] [power:current] [power:max] [power:percent] [name] [level]) -- NOT real ElvUI's full tag DSL."],
		},
	}

	local function FieldGetTable(name)
		return function()
			local settings = E.db.unitframe.units[dbKey]
			return settings.customTexts and settings.customTexts[name]
		end
	end

	local function AddCustomTextGroup(name)
		local getTable = FieldGetTable(name)
		args[name] = {
			type = "group",
			name = name,
			args = {
				header = {
					type = "header",
					name = name,
					order = 1,
				},
				delete = {
					type = "execute",
					name = L["Delete"],
					order = 2,
					func = function()
						local settings = E.db.unitframe.units[dbKey]
						if settings.customTexts then settings.customTexts[name] = nil end
						args[name] = nil
					end,
				},
				enable = {
					type = "toggle",
					name = L["Enable"],
					order = 3,
					get = function() return getTable().enable end,
					set = function(_, value) getTable().enable = value end,
				},
				text_format = {
					type = "input",
					name = L["Text Format"],
					width = "full",
					order = 4,
					get = function() return getTable().text_format end,
					set = function(_, value) getTable().text_format = value end,
				},
				attachTextTo = {
					type = "select",
					name = L["Attach To"],
					order = 5,
					values = {
						["Health"] = L["Health"],
						["Power"] = L["Power"],
						["InfoPanel"] = L["Information Panel"],
						["Frame"] = L["Frame"],
					},
					get = function() return getTable().attachTextTo end,
					set = function(_, value) getTable().attachTextTo = value end,
				},
				justifyH = {
					type = "select",
					name = L["Justify"],
					order = 6,
					values = {["CENTER"] = L["Center"], ["LEFT"] = L["Left"], ["RIGHT"] = L["Right"]},
					get = function() return getTable().justifyH end,
					set = function(_, value) getTable().justifyH = value end,
				},
				xOffset = {
					type = "range",
					name = L["X Offset"],
					order = 7,
					min = -400, max = 400, step = 1,
					get = function() return getTable().xOffset end,
					set = function(_, value) getTable().xOffset = value end,
				},
				yOffset = {
					type = "range",
					name = L["Y Offset"],
					order = 8,
					min = -400, max = 400, step = 1,
					get = function() return getTable().yOffset end,
					set = function(_, value) getTable().yOffset = value end,
				},
				size = {
					type = "range",
					name = L["Font Size"],
					order = 9,
					min = 4, max = 32, step = 1,
					get = function() return getTable().size end,
					set = function(_, value) getTable().size = value end,
				},
				fontOutline = {
					type = "select",
					name = L["Font Outline"],
					order = 10,
					values = {
						["NONE"] = L["None"],
						["OUTLINE"] = L["Outline"],
						["MONOCHROMEOUTLINE"] = L["Monochrome Outline"],
						["THICKOUTLINE"] = L["Thick Outline"],
					},
					get = function() return getTable().fontOutline end,
					set = function(_, value) getTable().fontOutline = value end,
				},
			},
		}
	end

	args.createCustomText = {
		type = "input",
		name = L["Create Custom Text"],
		desc = L["Type a unique name and press Enter to add a new custom text below."],
		width = "full",
		order = 2,
		get = function() return "" end,
		set = function(_, value)
			if not value or value == "" then return end
			local settings = E.db.unitframe.units[dbKey]
			settings.customTexts = settings.customTexts or {}
			if settings.customTexts[value] then
				E:Print(string.format(L["A custom text named '%s' already exists."], value))
				return
			end
			settings.customTexts[value] = {
				enable = true,
				text_format = "",
				attachTextTo = "Health",
				justifyH = "CENTER",
				xOffset = 0,
				yOffset = 0,
				size = E.db.unitframe.fontSize,
				fontOutline = E.db.unitframe.fontOutline,
			}
			AddCustomTextGroup(value)
		end,
	}

	-- NOT an eager E.db read here (that's the bug this replaced --
	-- symptom: "ElvUI_Config/Core.lua 848 db (nil value)"): this
	-- whole function runs at FILE-LOAD time, building the static options
	-- table, and ElvUI_Config loads eagerly (not LoadOnDemand) -- E.db doesn't exist yet at that point,
	-- unlike every other field in this file, which only ever touches
	-- E.db from inside a get/set closure (deferred until the config UI
	-- is actually opened, by which point E.db is long since built).
	-- Deferred via E:RegisterInitialModule instead -- the same "run
	-- after self.db/self.private/self.global are built" hook every real
	-- module in this addon already uses (see Init.lua's own comment on
	-- it), reused here even though this isn't a module, just because
	-- it's the addon's own established, guaranteed-correctly-timed
	-- mechanism for this exact problem.
	E:RegisterInitialModule("ElvUI_Config_CustomTexts_"..dbKey, function()
		local settings = E.db.unitframe.units[dbKey]
		if settings and settings.customTexts then
			local name
			for name in pairs(settings.customTexts) do
				AddCustomTextGroup(name)
			end
		end
	end)

	return args
end

-- Full per-unit tab set (General/Health/Power/Name/Portrait/Resting
-- Icon/Combat Icon) for one E.db.unitframe.units[dbKey] -- shared by
-- "UnitFrames > Player" and "UnitFrames > Target" so the two don't
-- duplicate ~150 lines of near-identical args tables. "Colors" is
-- deliberately NOT included here -- it's a single top-level tab shared
-- by every unit (E.db.unitframe.colors has no per-unit split in real
-- ElvUI either), not repeated per unit.
-- `hasRestIcon`: RestIcon (`IsResting()`) is inherently player-only --
-- no unit argument, an inn/city rest state that doesn't exist as a
-- concept for an arbitrary unit -- so it's omitted entirely for units
-- other than Player, rather than shown as a tab full of toggles that
-- would do nothing (Target never builds a RestingIndicator, see
-- Units/Target.lua). A rest icon and a combat icon on a target frame
-- would be a real mistake, not schema fidelity.
-- `hasDebuffs`/`hasBuffs`: only units that actually call
-- UF:Construct_Auras for that type get the matching tab -- same "don't
-- show controls that do nothing" reasoning as hasRestIcon. ALL SIX units
-- now build both containers, so both flags are set everywhere; an earlier
-- version of this comment said "only Player has real buffs", which stopped
-- being true once the missing containers were added.
-- `hasHappiness`: Pet-only, same "don't show controls that do nothing"
-- reasoning as hasRestIcon -- `HasPetUI()`'s own isHunterPet return only
-- ever means anything for the "pet" unit specifically (see UnitFrames.lua's
-- own Construct_Happiness comment).
-- `hasCastbar`: player and target, the units with a bar
-- (UnitFrames.lua's Castbar section: the player's from SPELLCAST_*, the
-- target's rebuilt from the combat log).
-- `hasRaidIcon`: the units real ElvUI declares `raidicon` settings for among
-- the ones this project builds -- player, target, targettarget and party; pet
-- and pettarget have none upstream.
-- The units this project builds, as a `values` table for the per-unit "Copy
-- From" control. Real ElvUI reads its own `UF.units` list here; ours is static
-- because the set is fixed by which Units/*.lua files exist.
local COPY_FROM_UNITS = {
	player = L["Player"],
	target = L["Target"],
	targettarget = L["Target of Target"],
	pet = L["Pet"],
	pettarget = L["Pet Target"],
	party = L["Party"],
}

-- Which unit "Restore Defaults" was clicked for -- the popup needs it, and a
-- popup body cannot take arguments. Not persisted.
local resetUnitTarget

E.PopupDialogs["RESET_UF_UNIT"] = {
	text = L["Reset this unit frame's settings to their defaults? Everything you have changed for this unit will be lost."],
	button1 = E.PopupAccept,
	button2 = E.PopupCancel,
	OnAccept = function()
		if resetUnitTarget and E.UnitFrames and E.UnitFrames.ResetUnitSettings then
			if E.UnitFrames:ResetUnitSettings(resetUnitTarget) then
				E:RequestReload()
			end
		end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = true,
}

local function UnitFrameArgs(dbKey, hasRestIcon, hasDebuffs, hasBuffs, hasHappiness, hasCastbar, hasRaidIcon)
	local function unitTable() return E.db.unitframe.units[dbKey] end

	local args = {
		-- `generalGroup`, not `general`: real ElvUI's own key for this per-unit
		-- group. Every OTHER subgroup name in here already matched upstream
		-- (health/power/name/portrait/RestIcon/CombatIcon/buffs/debuffs/castbar/
		-- infoPanel/customText) -- this one was the last odd one out, and because
		-- its leaves are `enable`/`width`/`height` (names that occur many times
		-- in both trees) the mismatch never showed up as MOVED, only as MISSING.
		-- See docs/config.md on why a MOVED of 0 is not proof on its own.
		generalGroup = {
			type = "group",
			name = L["General"],
			order = 1,
			args = {
				enable = {
					type = "toggle",
					name = L["Enable"],
					desc = L["Requires /reload to take effect."],
					order = 2,
					get = function() return unitTable().enable end,
					set = function(_, value)
						unitTable().enable = value
						E:RequestReload()
					end,
				},
				-- `copyFrom`/`resetSettings`: real ElvUI's own keys and orders (3/4,
				-- between enable and width). Both replace the unit's whole settings
				-- table, which includes build-time-only fields, so both ask for a
				-- reload -- see UF:MergeUnitSettings' own comment.
				copyFrom = {
					type = "select",
					name = L["Copy From"],
					desc = L["Select a unit to copy settings from."],
					order = 3,
					values = function()
						local list = {}
						local k, v
						for k, v in pairs(COPY_FROM_UNITS) do
							if k ~= dbKey then list[k] = v end
						end
						return list
					end,
					get = function() return nil end,
					set = function(_, value)
						if E.UnitFrames and E.UnitFrames:MergeUnitSettings(value, dbKey) then
							E:RequestReload()
						end
					end,
				},
				resetSettings = {
					type = "execute",
					name = L["Restore Defaults"],
					desc = L["Reset every setting for this unit back to its default."],
					order = 4,
					func = function()
						resetUnitTarget = dbKey
						E:StaticPopup_Show("RESET_UF_UNIT")
					end,
				},
				width = {
					type = "range",
					name = L["Width"],
					order = 6,
					min = 100, max = 400, step = 1,
					get = function() return unitTable().width end,
					set = function(_, value)
						unitTable().width = value
						if E.UnitFrames then E.UnitFrames:ResizeUnit(dbKey, value) end
					end,
				},
				height = {
					type = "range",
					name = L["Height"],
					order = 7,
					min = 20, max = 100, step = 1,
					get = function() return unitTable().height end,
					-- Live, same route as Width above: UF:UpdateFrame re-derives
					-- the Health/Power bar heights from this value on every pass
					-- (with the unit's own construction formula), so only the
					-- outer frame's SetHeight was ever missing.
					set = function(_, value)
						unitTable().height = value
						if E.UnitFrames then E.UnitFrames:ResizeUnit(dbKey, nil, value) end
					end,
				},
				colorOverride = {
					type = "select",
					name = L["Color Override"],
					desc = L["Force On always uses class/reaction color; Force Off never does, regardless of the Colors tab toggles (that tab is shared by every unit)."],
					order = 8,
					width = "full",
					values = {
						["USE_DEFAULT"] = L["Use Default"],
						["FORCE_ON"] = L["Force Class Color On"],
						["FORCE_OFF"] = L["Force Class Color Off"],
					},
					get = function() return unitTable().colorOverride end,
					set = function(_, value) unitTable().colorOverride = value end,
				},
			},
		},
		health = {
			type = "group",
			name = L["Health"],
			order = 2,
			args = (function()
				local args = UnitTextArgs(function() return unitTable().health end, 1)
				-- Real ElvUI's own key and order, on the health group only (the
				-- shared UnitTextArgs is used by power and name too, which have no
				-- background of their own). Live via UF:UpdateFrame.
				args.bgUseBarTexture = {
					type = "toggle",
					name = L["Use Health Texture Backdrop"],
					desc = L["Draw the bar background with the statusbar texture instead of a flat fill."],
					order = 7,
					get = function() return unitTable().health.bgUseBarTexture end,
					set = function(_, value) unitTable().health.bgUseBarTexture = value end,
				}
				return args
			end)(),
		},
		power = {
			type = "group",
			name = L["Power"],
			order = 3,
			args = (function()
				local args = UnitTextArgs(function() return unitTable().power end, 3)
				args.enable = {
					type = "toggle",
					name = L["Enable"],
					desc = L["Requires /reload to take effect."],
					order = 1,
					get = function() return unitTable().power.enable end,
					set = function(_, value)
						unitTable().power.enable = value
						E:RequestReload()
					end,
				}
				args.height = {
					type = "range",
					name = L["Height"],
					order = 2,
					min = 4, max = 40, step = 1,
					get = function() return unitTable().power.height end,
					-- Live: UF:UpdateFrame re-derives both bar heights from this
					-- and the frame height, so no outer resize is needed -- the
					-- ResizeUnit call is just to apply it now rather than on the
					-- next 0.2s poll.
					set = function(_, value)
						unitTable().power.height = value
						if E.UnitFrames then E.UnitFrames:ResizeUnit(dbKey) end
					end,
				}
				return args
			end)(),
		},
		name = {
			type = "group",
			name = L["Name"],
			order = 4,
			args = UnitTextArgs(function() return unitTable().name end, 1),
		},
		portrait = {
			type = "group",
			name = L["Portrait"],
			order = 5,
			args = {
				intro = {
					type = "description",
					order = 1,
					name = L["Only real ElvUI's own fields (Enable/Style/Size/Overlay) -- see CLAUDE.md's \"UnitFrames\" section for the UA-specific research (SetCamera, etc.) behind why 3D looks right without any extra project-only knobs."],
				},
				enable = {
					type = "toggle",
					name = L["Enable"],
					order = 2,
					get = function() return unitTable().portrait.enable end,
					set = function(_, value) unitTable().portrait.enable = value end,
				},
				style = {
					type = "select",
					name = L["Style"],
					order = 3,
					values = {["2D"] = "2D", ["3D"] = "3D"},
					get = function() return unitTable().portrait.style end,
					set = function(_, value) unitTable().portrait.style = value end,
				},
				width = {
					type = "range",
					name = L["Size"],
					desc = L["Only used when Overlay is off."],
					order = 4,
					min = 20, max = 100, step = 1,
					get = function() return unitTable().portrait.width end,
					set = function(_, value) unitTable().portrait.width = value end,
				},
				overlay = {
					type = "toggle",
					name = L["Overlay"],
					desc = L["The portrait overlays the Health bar instead of sitting beside it."],
					order = 5,
					get = function() return unitTable().portrait.overlay end,
					set = function(_, value) unitTable().portrait.overlay = value end,
				},
			},
		},
		-- `CombatIcon`/`RestIcon`, capitalised: real ElvUI's own CONFIG keys
		-- (its UnitFrames.lua:2896 for RestIcon). The DB fields were already
		-- capitalised on both sides -- only these entry names were lowercase,
		-- which put every one of them at a different tree path than the
		-- original.
		CombatIcon = {
			type = "group",
			name = L["Combat Icon"],
			order = 7,
			args = StateIconArgs(function() return unitTable().CombatIcon end, 1),
		},
		infoPanel = {
			type = "group",
			name = L["Information Panel"],
			order = 10,
			args = InfoPanelArgs(function() return unitTable().infoPanel end, 1),
		},
		-- `childGroups = "tab"` -- live-reported (screenshot): each Custom
		-- Text entry was showing up as its own SIDEBAR node under this
		-- unit (e.g. "Player" > "Player_health" as a tree row), cluttering
		-- the sidebar as more get added. A real vanilla
		-- ElvUI screenshot shows these as a two-pane master-detail list
		-- (name list + detail fields) INSIDE the "Custom Texts" TAB --
		-- LibConfig-1.0 has no such master-detail widget, but does
		-- already support nested tab-in-tab (RenderGroup, confirmed by
		-- reading it: a `childGroups="tab"` group's own GROUP-type
		-- children become tabs on ITS OWN page via RenderTabStrip,
		-- while its plain leaf fields like `createCustomText` still
		-- render inline on that same page) -- this reuses that already-
		-- proven mechanism instead of building a new widget: every
		-- Custom Text entry now becomes a TAB within "Custom Texts"
		-- rather than its own sidebar row. Not a pixel match to the
		-- real client's master-detail list, but solves the reported
		-- sidebar-clutter problem with zero new widget code.
		customText = {
			type = "group",
			name = L["Custom Texts"],
			order = 11,
			childGroups = "tab",
			args = CustomTextArgs(dbKey),
		},
	}

	if hasRestIcon then
		args.RestIcon = {
			type = "group",
			name = L["Resting Icon"],
			order = 6,
			args = StateIconArgs(function() return unitTable().RestIcon end, 1),
		}
	end

	-- Every field is read live by UnitFrames.lua's poll (UpdateRaidIcon).
	if hasRaidIcon then
		args.raidicon = {
			type = "group",
			name = L["Raid Icon"],
			order = 14,
			get = function(info) return unitTable().raidicon[ info[getn(info)] ] end,
			set = function(info, value) unitTable().raidicon[ info[getn(info)] ] = value end,
			args = {
				enable = {
					type = "toggle",
					name = L["Enable"],
					order = 1,
				},
				attachTo = {
					type = "select",
					name = L["Position"],
					order = 2,
					values = Shared.POSITION_VALUES,
				},
				attachToObject = {
					type = "select",
					name = L["Attach To"],
					order = 3,
					values = {
						["Health"] = L["Health"],
						["Power"] = L["Power"],
						["InfoPanel"] = L["Information Panel"],
						["Frame"] = L["Frame"],
					},
				},
				size = {
					type = "range",
					name = L["Size"],
					order = 4,
					min = 8, max = 60, step = 1,
				},
				xOffset = {
					type = "range",
					name = L["X Offset"],
					order = 5,
					min = -300, max = 300, step = 1,
				},
				yOffset = {
					type = "range",
					name = L["Y Offset"],
					order = 6,
					min = -300, max = 300, step = 1,
				},
			},
		}
	end

	if hasBuffs then
		args.buffs = {
			type = "group",
			name = L["Buffs"],
			order = 8,
			args = (function()
				local buffArgs = AuraArgs(function() return unitTable().buffs end, 2)
				buffArgs.intro = {
					type = "description",
					order = 1,
					name = dbKey == "player"
						and L["Real, exact duration -- read directly from the native GetPlayerBuff* API. Positioned above the frame."]
						or L["Icon + stack count only, no duration text -- no per-unit equivalent of the native GetPlayerBuff* API exists (that family only ever describes the player's own buffs). Positioned above the frame."],
				}
				return buffArgs
			end)(),
		}
	end

	if hasDebuffs then
		args.debuffs = {
			type = "group",
			name = L["Debuffs"],
			order = 9,
			args = (function()
				local debuffArgs = AuraArgs(function() return unitTable().debuffs end, 2)
				debuffArgs.intro = {
					type = "description",
					order = 1,
					name = dbKey == "player"
						and L["Real, exact duration -- read directly from the native GetPlayerBuff* API. Positioned below the frame."]
						or L["Duration is an APPROXIMATION (ported from pfUI's own libdebuff data + a stamp-on-first-observation timer, not the real vanilla application moment) -- see DebuffDurations.lua's own header comment. Positioned below the frame."],
				}
				return debuffArgs
			end)(),
		}
	end

	if hasHappiness then
		args.happiness = {
			type = "group",
			name = L["Happiness"],
			order = 12,
			args = {
				intro = {
					type = "description",
					order = 1,
					name = L["Hunter-pet-only loyalty indicator (HasPetUI()'s own isHunterPet flag) -- stays hidden for any other pet, e.g. a Warlock's. A narrow bar stuck out past Health's own left edge -- see UnitFrames.lua's own Construct_Happiness comment for why this doesn't reflow Health/Power's width the way real ElvUI does."],
				},
				enable = {
					type = "toggle",
					name = L["Enable"],
					order = 2,
					get = function() return unitTable().happiness.enable end,
					set = function(_, value) unitTable().happiness.enable = value end,
				},
				autoHide = {
					type = "toggle",
					name = L["Auto Hide When Happy"],
					order = 3,
					get = function() return unitTable().happiness.autoHide end,
					set = function(_, value) unitTable().happiness.autoHide = value end,
				},
				width = {
					type = "range",
					name = L["Width"],
					order = 4,
					min = 4, max = 30, step = 1,
					get = function() return unitTable().happiness.width end,
					set = function(_, value) unitTable().happiness.width = value end,
				},
			},
		}
	end

	if hasCastbar then
		args.castbar = {
			type = "group",
			name = L["Castbar"],
			order = 13,
			args = {
				intro = {
					type = "description",
					order = 1,
					name = dbKey == "target"
						and L["Requires /reload to take effect (enable only). Built from the combat log: only spells with a known cast time are shown, and units sharing a name cannot be told apart."]
						or L["Requires /reload to take effect (enable only). Player-only -- the classic vanilla cast events only ever describe your own cast."],
				},
				enable = {
					type = "toggle",
					name = L["Enable"],
					order = 2,
					get = function() return unitTable().castbar.enable end,
					set = function(_, value) unitTable().castbar.enable = value end,
				},
				width = {
					type = "range",
					name = L["Width"],
					order = 3,
					min = 50, max = 500, step = 1,
					get = function() return unitTable().castbar.width end,
					set = function(_, value)
						unitTable().castbar.width = value
						if E.UnitFrames then E.UnitFrames:ResizeCastbar(unitTable().castbar.width, unitTable().castbar.height, dbKey) end
					end,
				},
				height = {
					type = "range",
					name = L["Height"],
					order = 4,
					min = 8, max = 60, step = 1,
					get = function() return unitTable().castbar.height end,
					set = function(_, value)
						unitTable().castbar.height = value
						if E.UnitFrames then E.UnitFrames:ResizeCastbar(unitTable().castbar.width, unitTable().castbar.height, dbKey) end
					end,
				},
				icon = {
					type = "toggle",
					name = L["Show Icon"],
					order = 5,
					get = function() return unitTable().castbar.icon end,
					set = function(_, value) unitTable().castbar.icon = value end,
				},
				spark = {
					type = "toggle",
					name = L["Show Spark"],
					order = 6,
					get = function() return unitTable().castbar.spark end,
					set = function(_, value) unitTable().castbar.spark = value end,
				},
				format = {
					type = "select",
					name = L["Time Format"],
					order = 7,
					values = {
						["CURRENT"] = L["Current"],
						["CURRENTMAX"] = L["Current / Max"],
						["REMAINING"] = L["Remaining"],
					},
					get = function() return unitTable().castbar.format end,
					set = function(_, value) unitTable().castbar.format = value end,
				},
			},
		}
	end

	-- Real ElvUI's key and order; only on the units whose profile table has
	-- the field (player, target, pet, party).
	if P.unitframe.units[dbKey] and P.unitframe.units[dbKey].healPrediction ~= nil then
		args.generalGroup.args.healPrediction = {
			type = "toggle",
			name = L["Heal Prediction"],
			desc = L["Show an incoming heal prediction bar on the unitframe. Also display a slightly different colored bar for incoming overheals."],
			order = 9,
			get = function() return unitTable().healPrediction end,
			set = function(_, value) unitTable().healPrediction = value end,
		}
	end

	return args
end

E.Options.args.unitframe = {
	type = "group",
	name = L["UnitFrames"],
	order = 7,
	-- "tree" (a real sidebar-nested dropdown), not "tab": the
	-- general/player/pet/target/target-of-target/pet-target
	-- sections live under UnitFrame's own dropdown menu, matching
	-- the original layout. Matches real
	-- ElvUI's own top-level unitframe category exactly
	-- (source/ElvUI-vanilla/ElvUI_Config/UnitFrames.lua:1606:
	-- `childGroups = "tree"`) -- Colors/Player/Target/Pet/Target
	-- of Target/Pet Target/Party (and the new General node just
	-- below) become their own SIDEBAR nodes under "UnitFrames"
	-- instead of tabs across one page. Each of THEIR OWN internal
	-- sub-sections (Player's own General/Health/Power/etc.) is
	-- unaffected -- those still use `childGroups = "tab"` at
	-- their own level, matching what's already there.
	childGroups = "tree",
	args = {
		intro = {
			order = 2,
			type = "description",
			name = L["Custom-built unit frames (Player, Target, Pet, Target of Target, Pet Target, Party). Per-unit settings live in their own sidebar sections; the shared colours and the statusbar texture are under General."],
		},
		-- `generalOptionsGroup`, with `generalGroup` and `allColorsGroup`
		-- inside it: real ElvUI's own shape. Ours used to have a flat
		-- `general` and a flat `colors` group directly under `unitframe`,
		-- so every colour control and the statusbar picker sat at a tree
		-- path the original does not have.
		-- order=1, ahead of player/target/pet/etc. (order 2-7 below): real
		-- ElvUI's own order=26 for this group only sorts first THERE because
		-- its sibling shortcut-button entries sit at 1-25 while the actual
		-- player/target/party groups carry much higher orders (300/400/
		-- .../1200, declared separately later in its own file) -- copying
		-- just the 26 without matching those left this group sorting LAST
		-- against our own much lower 2-7 siblings instead of first.
		--
		-- Display name is real ElvUI's own "General Options", NOT a shortened
		-- "General". An earlier version shortened it for consistency with other
		-- modules' top-level "General" groups, and that shortening is what
		-- forced `generalGroup` to be flattened away (two groups both named
		-- "General", one nested in the other, rendered a literal duplicate
		-- title) -- which in turn put `barGroup` at a tree path real ElvUI does
		-- not have. Keeping upstream's distinct label removes the collision at
		-- its root and lets the real nesting stand.
		--
		-- Every `guiInline = true` group below (generalGroup/allColorsGroup/
		-- healthGroup/powerGroup/reactionGroup) had its own real-ElvUI-copied
		-- `header` leaf entry removed -- LibConfig-1.0's RenderGroup already
		-- auto-renders an inline group's own `name` as a section header+rule
		-- (LibConfig-1.0.lua, matching real AceConfigDialog-3.0's own
		-- `GroupContainer:SetTitle(name)` for inline groups), so the
		-- hand-added header duplicated it verbatim. Invisible on the real
		-- client because AceGUI's InlineGroup renders as a bordered box with
		-- a small corner title, visually distinct from a full-width header
		-- strip -- LibConfig-1.0 renders both the auto-title and a manual
		-- header the same way (big label + full-width rule), so here the
		-- two stack as an obvious literal duplicate instead.
		generalOptionsGroup = {
			order = 1,
			type = "group",
			name = L["General Options"],
			childGroups = "tab",
			args = {
				-- `generalGroup` is real ElvUI's own wrapper and, like
				-- `allColorsGroup` beside it, a TAB rather than an inline box
				-- (the parent carries childGroups = "tab", and upstream sets no
				-- guiInline on either) -- so its own name is rendered as a tab
				-- label, never as a heading stacked on top of the page title.
				-- Upstream's orders 2-19 in here are settings this project does
				-- not implement (targetOnMouseDown, auraBlacklistModifier,
				-- fontGroup, ...); barGroup keeps 20 so they can land in place.
				generalGroup = {
					order = 1,
					type = "group",
					name = L["General"],
					args = {
				barGroup = {
					order = 20,
					type = "group",
					name = L["Bars"],
					guiInline = true,
					args = {
					statusbar = {
						type = "select",
						name = L["Statusbar Texture"],
						dialogControl = "LSM30_Statusbar",
						desc = L["Applies live, no /reload needed. Custom addon-shipped textures don't render on UA -- only native paths (like the default) actually show anything."],
						order = 3,
						values = function()
							local LSM = LibStub("LibSharedMedia-3.0", true)
							local list = {}
							if LSM then
								local names = LSM:List("statusbar")
								local i
								for i = 1, table.getn(names) do
									list[names[i]] = names[i]
								end
							end
							return list
						end,
						get = function() return E.db.unitframe.statusbar end,
						set = function(_, value) E.db.unitframe.statusbar = value end,
					},
					},
				},
					},
				},
				allColorsGroup = {
					order = 3,
					type = "group",
					name = L["Colors"],
					guiInline = true,
					args = {
					healthGroup = {
						order = 2,
						type = "group",
						name = L["Health"],
						guiInline = true,
						args = {
						healthclass = {
							type = "toggle",
							name = L["Color Health By Class"],
							order = 2,
							get = function() return E.db.unitframe.colors.healthclass end,
							set = function(_, value) E.db.unitframe.colors.healthclass = value end,
						},
						colorhealthbyvalue = {
							type = "toggle",
							name = L["Color Health By Value"],
							desc = L["Gradient from red to green (or, combined with Color Health By Class, red to the class/reaction color) as health drops, instead of a flat color."],
							order = 4,
							get = function() return E.db.unitframe.colors.colorhealthbyvalue end,
							set = function(_, value) E.db.unitframe.colors.colorhealthbyvalue = value end,
						},
						customhealthbackdrop = {
							type = "toggle",
							name = L["Custom Health Backdrop Color"],
							order = 5,
							get = function() return E.db.unitframe.colors.customhealthbackdrop end,
							set = function(_, value) E.db.unitframe.colors.customhealthbackdrop = value end,
						},
						transparentHealth = {
							type = "toggle",
							name = L["Transparent Health"],
							desc = L["Dims the health bar (fill and background) so something behind it -- e.g. an overlay portrait -- shows through. Simplified from real ElvUI's own texture-masking technique to a uniform alpha reduction, see UnitFrames.lua's own comment."],
							order = 7,
							get = function() return E.db.unitframe.colors.transparentHealth end,
							set = function(_, value) E.db.unitframe.colors.transparentHealth = value end,
						},
						useDeadBackdrop = {
							type = "toggle",
							name = L["Use Dead Backdrop Color"],
							order = 8,
							get = function() return E.db.unitframe.colors.useDeadBackdrop end,
							set = function(_, value) E.db.unitframe.colors.useDeadBackdrop = value end,
						},
						health = {
							type = "color",
							name = L["Base Health Color"],
							desc = L["Used when Color Health By Class and Color Health By Value are both off."],
							order = 9,
							get = function()
								local c = E.db.unitframe.colors.health
								return c.r, c.g, c.b
							end,
							set = function(_, r, g, b)
								local c = E.db.unitframe.colors.health
								c.r, c.g, c.b = r, g, b
							end,
						},
						health_backdrop = {
							type = "color",
							name = L["Health Backdrop Color"],
							order = 10,
							get = function()
								local c = E.db.unitframe.colors.health_backdrop
								return c.r, c.g, c.b
							end,
							set = function(_, r, g, b)
								local c = E.db.unitframe.colors.health_backdrop
								c.r, c.g, c.b = r, g, b
							end,
						},
						health_backdrop_dead = {
							type = "color",
							name = L["Dead Backdrop Color"],
							order = 14,
							get = function()
								local c = E.db.unitframe.colors.health_backdrop_dead
								return c.r, c.g, c.b
							end,
							set = function(_, r, g, b)
								local c = E.db.unitframe.colors.health_backdrop_dead
								c.r, c.g, c.b = r, g, b
							end,
						},
						},
					},
					powerGroup = {
						order = 3,
						type = "group",
						name = L["Power"],
						guiInline = true,
						args = {
						powerclass = {
							type = "toggle",
							name = L["Color Power By Class"],
							order = 2,
							get = function() return E.db.unitframe.colors.powerclass end,
							set = function(_, value) E.db.unitframe.colors.powerclass = value end,
						},
						transparentPower = {
							type = "toggle",
							name = L["Transparent Power"],
							desc = L["Same as Transparent Health, for the power bar."],
							order = 3,
							get = function() return E.db.unitframe.colors.transparentPower end,
							set = function(_, value) E.db.unitframe.colors.transparentPower = value end,
						},
						},
					},
					reactionGroup = {
						order = 4,
						type = "group",
						name = L["Reaction"],
						guiInline = true,
						args = {
						BAD = {
							type = "color",
							name = L["Reaction: Hostile"],
							desc = L["Used for a non-player unit's class/reaction color (e.g. Target) when it's hostile."],
							order = 2,
							get = function()
								local c = E.db.unitframe.colors.reaction.BAD
								return c.r, c.g, c.b
							end,
							set = function(_, r, g, b)
								local c = E.db.unitframe.colors.reaction.BAD
								c.r, c.g, c.b = r, g, b
							end,
						},
						NEUTRAL = {
							type = "color",
							name = L["Reaction: Neutral"],
							order = 3,
							get = function()
								local c = E.db.unitframe.colors.reaction.NEUTRAL
								return c.r, c.g, c.b
							end,
							set = function(_, r, g, b)
								local c = E.db.unitframe.colors.reaction.NEUTRAL
								c.r, c.g, c.b = r, g, b
							end,
						},
						GOOD = {
							type = "color",
							name = L["Reaction: Friendly"],
							order = 4,
							get = function()
								local c = E.db.unitframe.colors.reaction.GOOD
								return c.r, c.g, c.b
							end,
							set = function(_, r, g, b)
								local c = E.db.unitframe.colors.reaction.GOOD
								c.r, c.g, c.b = r, g, b
							end,
						},
						},
					},
					-- Real ElvUI's group, keys and order. The two colours share a
					-- group-level get/set, so each entry's name is its DB key.
					healPrediction = {
						order = 6,
						type = "group",
						name = L["Heal Prediction"],
						guiInline = true,
						get = function(info)
							local t = E.db.unitframe.colors.healPrediction[ info[getn(info)] ]
							local d = P.unitframe.colors.healPrediction[ info[getn(info)] ]
							return t.r, t.g, t.b, t.a, d.r, d.g, d.b, d.a
						end,
						set = function(info, r, g, b, a)
							local t = E.db.unitframe.colors.healPrediction[ info[getn(info)] ]
							t.r, t.g, t.b, t.a = r, g, b, a
						end,
						args = {
						-- Real ElvUI's header, kept for the tree path but hidden:
						-- here the group is an inline box that already shows
						-- the same title.
						header = {
							order = 1,
							type = "header",
							name = L["Heal Prediction"],
							hidden = true,
						},
						personal = {
							order = 2,
							type = "color",
							name = L["Personal"],
							hasAlpha = true,
						},
						others = {
							order = 3,
							type = "color",
							name = L["Others"],
							hasAlpha = true,
						},
						maxOverflow = {
							order = 4,
							type = "range",
							name = L["Max Overflow"],
							desc = L["Max amount of overflow allowed to extend past the end of the health bar."],
							isPercent = true,
							min = 0, max = 1, step = 0.01,
							get = function() return E.db.unitframe.colors.healPrediction.maxOverflow end,
							set = function(_, value) E.db.unitframe.colors.healPrediction.maxOverflow = value end,
						},
						},
					},
					},
				},
			},
		},
		player = {
			type = "group",
			name = L["Player"],
			order = 2,
			childGroups = "tab",
			args = UnitFrameArgs("player", true, true, true, nil, true, true),
		},
		target = {
			type = "group",
			name = L["Target"],
			order = 3,
			childGroups = "tab",
			args = UnitFrameArgs("target", nil, true, true, nil, true, true),
		},
		pet = {
			type = "group",
			name = L["Pet"],
			order = 4,
			childGroups = "tab",
			args = UnitFrameArgs("pet", nil, true, true, true),
		},
		targettarget = {
			type = "group",
			name = L["Target of Target"],
			order = 5,
			childGroups = "tab",
			args = UnitFrameArgs("targettarget", nil, true, true, nil, nil, true),
		},
		pettarget = {
			type = "group",
			name = L["Pet Target"],
			order = 6,
			childGroups = "tab",
			args = UnitFrameArgs("pettarget", nil, true, true),
		},
		party = {
			type = "group",
			name = L["Party"],
			order = 7,
			childGroups = "tab",
			args = UnitFrameArgs("party", nil, true, true, nil, nil, true),
		},
	},
}
