local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn
local Shared = E.ConfigShared
local Trim = Shared.Trim

-- Editor for the nameplate style filters (E.global.nameplates.filters, read by
-- ElvUI's Modules/NamePlates/StyleFilter.lua), real ElvUI's Style Filter page.
-- A filter is account-wide, its on/off switch per profile
-- (E.db.nameplates.filters). The shipped filters cannot be deleted: the saved
-- global table is merged over the defaults at every login, so a deleted default
-- would come back. The lists of names are `{ [name] = true / false }` tables;
-- a name set to false stays listed and is not checked.
--
-- Left out because the clients have nothing behind them: `casting.interruptible`,
-- `instanceDifficulty`, the arena instance type.

local selected

local function Filters()
	return E.global.nameplates.filters
end

local function Selected()
	return selected and Filters()[selected]
end

local function NoFilter()
	return not Selected()
end

local function NotRunning()
	return not E.NamePlates
end

local function Removable()
	return Selected() and not G.nameplates.filters[selected]
end

local function Triggers()
	return Selected().triggers
end

local function Actions()
	return Selected().actions
end

local function Changed()
	if E.NamePlates then E.NamePlates:ConfigureAll() end
end

-- Group-level get / set on `tableOf()`; the option key is the field name.
local function Bind(group, tableOf)
	group.get = function(info) return tableOf()[ info[getn(info)] ] end
	group.set = function(info, value)
		tableOf()[ info[getn(info)] ] = value
		Changed()
	end
	return group
end

local function Switch(order, name, desc)
	return { order = order, type = "toggle", name = name, desc = desc }
end

local function Keys(list)
	local values = {}
	local name
	for name in pairs(list) do values[name] = name end
	return values
end

-- A list of names, each with a checkbox, with a box to add one and a dropdown
-- to remove one.
local function NameList(order, name, listOf, addName, removeName)
	return {
		order = order,
		type = "group",
		name = name,
		guiInline = true,
		args = {
			add = {
				order = 1,
				type = "input",
				name = addName,
				get = function() return "" end,
				set = function(_, value)
					local entry = Trim(value)
					if entry == "" then return end
					listOf()[entry] = true
					Changed()
				end,
			},
			remove = {
				order = 2,
				type = "select",
				name = removeName,
				hidden = function() return not next(listOf()) end,
				values = function() return Keys(listOf()) end,
				get = function() return nil end,
				set = function(_, value)
					listOf()[value] = nil
					Changed()
				end,
			},
			entries = {
				order = 3,
				type = "multiselect",
				name = name,
				hidden = function() return not next(listOf()) end,
				values = function() return Keys(listOf()) end,
				get = function(_, key) return listOf()[key] == true end,
				set = function(_, key, checked)
					listOf()[key] = checked
					Changed()
				end,
			},
		},
	}
end

local function NamesTab()
	return NameList(1, L["Name"], function() return Triggers().names end, L["Add Name"], L["Remove Name"])
end

local function CastingTab()
	return NameList(2, L["Casting"], function() return Triggers().casting.spells end,
		L["Add Spell Name"], L["Remove Spell"])
end

-- One checkbox list per state; the stored value is the state's name or
-- "DISABLED", so a spell is in at most one of the two lists.
local function CooldownState(order, name, state)
	local function Cooldowns() return Triggers().cooldowns.names end
	return {
		order = order,
		type = "multiselect",
		name = name,
		hidden = function() return not next(Cooldowns()) end,
		values = function() return Keys(Cooldowns()) end,
		get = function(_, key) return Cooldowns()[key] == state end,
		set = function(_, key, checked)
			Cooldowns()[key] = checked and state or "DISABLED"
			Changed()
		end,
	}
end

local function CooldownsTab()
	local function Cooldowns() return Triggers().cooldowns.names end
	return Bind({
		order = 3,
		type = "group",
		name = L["Cooldowns"],
		guiInline = true,
		args = {
			mustHaveAll = Switch(1, L["Require All"],
				L["If enabled then it will require all cooldowns to activate the filter. Otherwise it will only require any one of the cooldowns to activate it."]),
			add = {
				order = 2,
				type = "input",
				name = L["Add Spell Name"],
				get = function() return "" end,
				set = function(_, value)
					local entry = Trim(value)
					if entry == "" then return end
					Cooldowns()[entry] = "ONCD"
					Changed()
				end,
			},
			remove = {
				order = 3,
				type = "select",
				name = L["Remove Spell"],
				hidden = function() return not next(Cooldowns()) end,
				values = function() return Keys(Cooldowns()) end,
				get = function() return nil end,
				set = function(_, value)
					Cooldowns()[value] = nil
					Changed()
				end,
			},
			onCooldown = CooldownState(4, L["On Cooldown"], "ONCD"),
			offCooldown = CooldownState(5, L["Off Cooldown"], "OFFCD"),
		},
	}, function() return Triggers().cooldowns end)
end

local function AuraTab(order, name, key, minDesc, maxDesc)
	local function Aura() return Triggers()[key] end
	return Bind({
		order = order,
		type = "group",
		name = name,
		guiInline = true,
		args = {
			mustHaveAll = Switch(1, L["Require All"],
				L["If enabled then it will require all auras to activate the filter. Otherwise it will only require any one of the auras to activate it."]),
			missing = Switch(2, L["Missing"], L["If enabled then it checks if auras are missing instead of being present on the unit."]),
			minTimeLeft = {
				order = 3,
				type = "range",
				name = L["Minimum Time Left"],
				desc = minDesc,
				min = 0, max = 10800, softMax = 300, step = 1,
			},
			maxTimeLeft = {
				order = 4,
				type = "range",
				name = L["Maximum Time Left"],
				desc = maxDesc,
				min = 0, max = 10800, softMax = 300, step = 1,
			},
			names = NameList(5, name, function() return Aura().names end, L["Add Spell Name"], L["Remove Spell"]),
		},
	}, Aura)
end

local function Threshold(order, name, desc, off)
	return {
		order = order,
		type = "range",
		name = name,
		desc = desc,
		min = 0, max = 1, step = 0.01,
		isPercent = true,
		disabled = off,
	}
end

local function HealthTab()
	local function Off() return not Triggers().healthThreshold end
	return Bind({
		order = 6,
		type = "group",
		name = L["Health Threshold"],
		guiInline = true,
		args = {
			healthThreshold = Switch(1, L["Enable"]),
			healthUsePlayer = {
				order = 2,
				type = "toggle",
				name = L["Player Health"],
				desc = L["Enabling this will check your health amount."],
				disabled = Off,
			},
			underHealthThreshold = Threshold(3, L["Under Health Threshold"],
				L["If this threshold is used then the health of the unit needs to be lower than this value in order for the filter to activate. Set to 0 to disable."], Off),
			overHealthThreshold = Threshold(4, L["Over Health Threshold"],
				L["If this threshold is used then the health of the unit needs to be higher than this value in order for the filter to activate. Set to 0 to disable."], Off),
		},
	}, Triggers)
end

-- The player's power: the clients report none for a plate's unit.
local function PowerTab()
	local function Off() return not Triggers().powerThreshold end
	return Bind({
		order = 7,
		type = "group",
		name = L["Power Threshold"],
		guiInline = true,
		args = {
			intro = { order = 1, type = "description", name = L["Enabling this will check your power amount."] },
			powerThreshold = Switch(2, L["Enable"]),
			underPowerThreshold = Threshold(3, L["Under Power Threshold"], nil, Off),
			overPowerThreshold = Threshold(4, L["Over Power Threshold"], nil, Off),
		},
	}, Triggers)
end

local function LevelRange(order, name, desc, min)
	return {
		order = order,
		type = "range",
		name = name,
		desc = desc,
		min = min, max = 63, step = 1,
		disabled = function() return not Triggers().level end,
	}
end

local function LevelTab()
	return Bind({
		order = 8,
		type = "group",
		name = L["Level"],
		guiInline = true,
		args = {
			level = Switch(1, L["Enable"]),
			mylevel = {
				order = 2,
				type = "toggle",
				name = L["Match Player Level"],
				desc = L["If enabled then the filter will only activate if the level of the unit matches your own."],
				disabled = function() return not Triggers().level end,
			},
			curlevel = LevelRange(3, L["Current Level"], L["If enabled then the filter will only activate if the level of the unit matches this value."], -1),
			minlevel = LevelRange(4, L["Minimum Level"], L["If enabled then the filter will only activate if the level of the unit is equal to or higher than this value."], 0),
			maxlevel = LevelRange(5, L["Maximum Level"], L["If enabled then the filter will only activate if the level of the unit is equal to or lower than this value."], 0),
		},
	}, Triggers)
end

local function CombatTab()
	return Bind({
		order = 9,
		type = "group",
		name = L["Combat"],
		guiInline = true,
		args = {
			inCombat = Switch(1, L["Player in Combat"], L["If enabled then the filter will only activate when you are in combat."]),
			outOfCombat = Switch(2, L["Player Out of Combat"], L["If enabled then the filter will only activate when you are out of combat."]),
			isTarget = Switch(3, L["Is Targeted"], L["If enabled then the filter will only activate when you are targeting the unit."]),
			notTarget = Switch(4, L["Not Targeted"], L["If enabled then the filter will only activate when you are not targeting the unit."]),
		},
	}, Triggers)
end

local function Dependent(order, name, enabledOf)
	return {
		order = order,
		type = "toggle",
		name = name,
		disabled = function() return not enabledOf().enable end,
	}
end

local function UnitTypeTab()
	local function Types() return Triggers().nameplateType end
	local function Reactions() return Triggers().reactionType end
	return {
		order = 10,
		type = "group",
		name = L["Unit Type"],
		guiInline = true,
		args = {
			nameplateType = Bind({
				order = 1,
				type = "group",
				name = L["Unit Type"],
				guiInline = true,
				args = {
					enable = Switch(1, L["Enable"]),
					friendlyPlayer = Dependent(2, L["FRIENDLY_PLAYER"], Types),
					friendlyNPC = Dependent(3, L["FRIENDLY_NPC"], Types),
					enemyPlayer = Dependent(4, L["ENEMY_PLAYER"], Types),
					enemyNPC = Dependent(5, L["ENEMY_NPC"], Types),
				},
			}, Types),
			reactionType = Bind({
				order = 2,
				type = "group",
				name = L["Reaction Type"],
				guiInline = true,
				args = {
					enable = Switch(1, L["Enable"]),
					hostile = Dependent(2, L["Hostile"], Reactions),
					neutral = Dependent(3, L["Neutral"], Reactions),
					friendly = Dependent(4, L["Friendly"], Reactions),
				},
			}, Reactions),
		},
	}
end

local function RoleTab()
	return Bind({
		order = 11,
		type = "group",
		name = L["Role"],
		guiInline = true,
		args = {
			tank = Switch(1, L["Tank"]),
			healer = Switch(2, L["Healer"]),
			damager = Switch(3, L["Damage"]),
		},
	}, function() return Triggers().role end)
end

local function InstanceTab()
	return Bind({
		order = 12,
		type = "group",
		name = L["Instance Type"],
		guiInline = true,
		args = {
			none = Switch(1, L["None"]),
			party = Switch(2, L["Party"]),
			raid = Switch(3, L["Raid"]),
			pvp = Switch(4, L["Battleground"]),
		},
	}, function() return Triggers().instanceType end)
end

-- Every inline group above takes a page of its own here.
local function Tab(group)
	group.guiInline = nil
	return group
end

local function TriggersTab()
	return {
		order = 10,
		type = "group",
		name = L["Triggers"],
		childGroups = "tab",
		hidden = NoFilter,
		args = {
			names = Tab(NamesTab()),
			casting = Tab(CastingTab()),
			cooldowns = Tab(CooldownsTab()),
			buffs = Tab(AuraTab(4, L["Buffs"], "buffs",
				L["Apply this filter if a buff has remaining time greater than this. Set to zero to disable."],
				L["Apply this filter if a buff has remaining time less than this. Set to zero to disable."])),
			debuffs = Tab(AuraTab(5, L["Debuffs"], "debuffs",
				L["Apply this filter if a debuff has remaining time greater than this. Set to zero to disable."],
				L["Apply this filter if a debuff has remaining time less than this. Set to zero to disable."])),
			health = Tab(HealthTab()),
			power = Tab(PowerTab()),
			level = Tab(LevelTab()),
			combat = Tab(CombatTab()),
			unitType = Tab(UnitTypeTab()),
			role = Tab(RoleTab()),
			instanceType = Tab(InstanceTab()),
		},
	}
end

local function ColorOption(order, name, tableOf, key, hasAlpha)
	return {
		order = order,
		type = "color",
		name = name,
		hasAlpha = hasAlpha,
		get = function()
			local c = tableOf()[key]
			return c.r, c.g, c.b, c.a or 1
		end,
		set = function(_, r, g, b, a)
			local c = tableOf()[key]
			c.r, c.g, c.b, c.a = r, g, b, a or 1
			Changed()
		end,
	}
end

local function ColorsGroup()
	local function Colors() return Actions().color end
	return Bind({
		order = 5,
		type = "group",
		name = L["Color"],
		guiInline = true,
		args = {
			health = Switch(1, L["Health"]),
			healthColor = ColorOption(2, L["Health Color"], Colors, "healthColor", true),
			border = Switch(3, L["Border"]),
			borderColor = ColorOption(4, L["Border Color"], Colors, "borderColor", true),
			name = Switch(5, L["Name"]),
			nameColor = ColorOption(6, L["Name Color"], Colors, "nameColor", true),
		},
	}, Colors)
end

local function TextureGroup()
	local function Texture() return Actions().texture end
	return Bind({
		order = 6,
		type = "group",
		name = L["Texture"],
		guiInline = true,
		args = {
			enable = Switch(1, L["Enable"]),
			texture = {
				order = 2,
				type = "select",
				name = L["Texture"],
				dialogControl = "LSM30_Statusbar",
				values = Shared.MediaValues("statusbar"),
				disabled = function() return not Texture().enable end,
			},
		},
	}, Texture)
end

local function FlashGroup()
	local function Flash() return Actions().flash end
	return Bind({
		order = 7,
		type = "group",
		name = L["Flash"],
		guiInline = true,
		args = {
			enable = Switch(1, L["Enable"]),
			color = ColorOption(2, L["Color"], Flash, "color", true),
			speed = {
				order = 3,
				type = "range",
				name = L["Speed"],
				min = 1, max = 10, step = 1,
			},
		},
	}, Flash)
end

local function ActionsTab()
	return Bind({
		order = 20,
		type = "group",
		name = L["Actions"],
		hidden = NoFilter,
		args = {
			hide = Switch(1, L["Hide Frame"]),
			nameOnly = Switch(2, L["Name Only"]),
			scale = {
				order = 3,
				type = "range",
				name = L["Scale"],
				min = 0.5, max = 1.5, step = 0.01,
			},
			alpha = {
				order = 4,
				type = "range",
				name = L["Alpha"],
				desc = L["Change the alpha level of the frame."],
				min = -1, max = 100, step = 1,
			},
			color = ColorsGroup(),
			texture = TextureGroup(),
			flash = FlashGroup(),
		},
	}, Actions)
end

E.Options.args.nameplate.args.filters = {
	order = 15,
	type = "group",
	name = L["Style Filter"],
	childGroups = "tab",
	disabled = NotRunning,
	args = {
		createFilter = {
			order = 1,
			type = "input",
			name = L["Create Filter"],
			get = function() return "" end,
			set = function(_, value)
				local name = Trim(value)
				if name == "" then return end
				if Filters()[name] then
					E:Print(L["Filter already exists!"])
					return
				end
				Filters()[name] = { triggers = {}, actions = {} }
				E.db.nameplates.filters[name] = { triggers = { enable = true } }
				selected = name
				Changed()
			end,
		},
		selectFilter = {
			order = 2,
			type = "select",
			name = L["Select Filter"],
			values = function() return Keys(Filters()) end,
			get = function() return selected end,
			set = function(_, value) selected = value end,
		},
		deleteFilter = {
			order = 3,
			type = "execute",
			name = L["Delete Filter"],
			disabled = function() return not Removable() end,
			confirm = function() return string.format(L["Delete Filter - %s"], selected or "") end,
			func = function()
				if not Removable() then return end
				Filters()[selected] = nil
				E.db.nameplates.filters[selected] = nil
				selected = nil
				Changed()
			end,
		},
		enable = {
			order = 4,
			type = "toggle",
			name = L["Enable"],
			desc = L["Use this filter."],
			hidden = NoFilter,
			get = function()
				local switch = E.db.nameplates.filters[selected]
				return switch and switch.triggers and switch.triggers.enable
			end,
			set = function(_, value)
				local switches = E.db.nameplates.filters
				if not (switches[selected] and switches[selected].triggers) then
					switches[selected] = { triggers = {} }
				end
				switches[selected].triggers.enable = value
				Changed()
			end,
		},
		priority = {
			order = 5,
			type = "range",
			name = L["Priority"],
			desc = L["Lower numbers mean a higher priority. Filters are processed in order from 1 to 100."],
			min = 1, max = 100, step = 1,
			hidden = NoFilter,
			get = function() return Triggers().priority end,
			set = function(_, value)
				Triggers().priority = value
				Changed()
			end,
		},
		resetFilter = {
			order = 6,
			type = "execute",
			name = L["Reset Filter"],
			desc = L["Return filter to its default state."],
			hidden = NoFilter,
			confirm = function() return string.format(L["Reset Filter - %s"], selected or "") end,
			func = function()
				local default = G.nameplates.filters[selected]
				if default then
					Filters()[selected] = ElvUI.Util.MergeTable({}, default)
				else
					Filters()[selected] = { triggers = {}, actions = {} }
				end
				Changed()
			end,
		},
		triggers = TriggersTab(),
		actions = ActionsTab(),
	},
}
