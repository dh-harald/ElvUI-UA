local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn
local MediaValues = E.ConfigShared.MediaValues

-- NamePlates, real ElvUI's tree (ElvUI-vanilla ElvUI_Config/Nameplates.lua):
-- `enable` on the root, a `generalGroup` with tabs, and one group per unit
-- type with health, cast bar, debuff, level and name tabs. Only controls for
-- settings the module reads are present; motion type and click settings come
-- with their features, and StyleFilters.lua adds the Style Filter page. The
-- shortcut buttons are left out: LibConfig-1.0 has no way to select a group
-- from a button.
--
-- Settings apply live through NP:ConfigureAll(), which re-lays every plate
-- on its next update.

local function ConfigureAll()
	if E.NamePlates then E.NamePlates:ConfigureAll() end
end

local function NotRunning()
	return not E.NamePlates
end

-- Real ElvUI's "Personal Auras" toggle, kept as the "Personal" token of the
-- filters' priority string: that string is the real profile key the module
-- reads. Any entry that lets personal auras through counts, with or
-- without a "Friendly:" / "Enemy:" / "allow" prefix ("blockPersonal" does
-- not); switching off removes those entries, switching on appends a plain
-- "Personal" when none is left.
local function ShowsPersonal(token)
	local real, _, _, block = E.UnitFrames:GetFilterNameInfo(token)
	return real == "Personal" and not block
end

local function HasPersonal(filters)
	local tokens = E.ConfigShared.SplitPriority(filters.priority)
	local i
	for i = 1, getn(tokens) do
		if ShowsPersonal(tokens[i]) then return true end
	end
	return false
end

local function SetPersonal(filters, value)
	if value and HasPersonal(filters) then return end
	local all = E.ConfigShared.SplitPriority(filters.priority)
	local tokens = {}
	local i
	for i = 1, getn(all) do
		if not ShowsPersonal(all[i]) then table.insert(tokens, all[i]) end
	end
	if value then table.insert(tokens, "Personal") end
	filters.priority = table.concat(tokens, ",")
end

local COMBAT_TOGGLES = {
	["DISABLED"] = L["Disabled"],
	["TOGGLE_ON"] = L["Toggle On While In Combat"],
	["TOGGLE_OFF"] = L["Toggle Off While In Combat"],
}

-- Retail ElvUI's arrow picker: every arrow of ElvUI/Media/Arrows, as the
-- texture escape LibConfig draws as a picture (retail E:TextureString).
local ARROW_TEXTURES = {}
do
	local names = { "ArrowBracket", "ArrowRed" }
	local i
	for i = 0, 72 do table.insert(names, "Arrow" .. i) end
	for i = 1, getn(names) do
		ARROW_TEXTURES[names[i]] = "|TInterface\\AddOns\\ElvUI\\Media\\Arrows\\" .. names[i] .. ":32:32|t"
	end
end

local GLOW_STYLES = {
	["none"] = L["None"],
	["style1"] = L["Border Glow"],
	["style2"] = L["Background Glow"],
	["style3"] = L["Top Arrow"],
	["style4"] = L["Side Arrows"],
	["style5"] = L["Border Glow"] .. " + " .. L["Top Arrow"],
	["style6"] = L["Background Glow"] .. " + " .. L["Top Arrow"],
	["style7"] = L["Border Glow"] .. " + " .. L["Side Arrows"],
	["style8"] = L["Background Glow"] .. " + " .. L["Side Arrows"],
}

local generalTab = {
	order = 1,
	type = "group",
	name = L["General"],
	args = {
		statusbar = {
			order = 0,
			type = "select",
			dialogControl = "LSM30_Statusbar",
			name = L["StatusBar Texture"],
			values = MediaValues("statusbar"),
		},
		lowHealthThreshold = {
			order = 2,
			type = "range",
			name = L["Low Health Threshold"],
			desc = L["Make the unitframe glow yellow when it is below this percent of health, it will glow red when the health value is half of this value."],
			isPercent = true,
			min = 0, max = 1, step = 0.01,
		},
		showEnemyCombat = {
			order = 10,
			type = "select",
			name = L["Enemy Combat Toggle"],
			desc = L["Control enemy nameplates toggling on or off when in combat."],
			values = COMBAT_TOGGLES,
			set = function(info, value)
				E.db.nameplates[ info[getn(info)] ] = value
				if E.NamePlates then E.NamePlates:PLAYER_REGEN_ENABLED() end
			end,
		},
		showFriendlyCombat = {
			order = 11,
			type = "select",
			name = L["Friendly Combat Toggle"],
			desc = L["Control friendly nameplates toggling on or off when in combat."],
			values = COMBAT_TOGGLES,
			set = function(info, value)
				E.db.nameplates[ info[getn(info)] ] = value
				if E.NamePlates then E.NamePlates:PLAYER_REGEN_ENABLED() end
			end,
		},
		comboPoints = {
			order = 12,
			type = "toggle",
			name = L["Combobar"],
		},
		nameColoredGlow = {
			order = 13,
			type = "toggle",
			name = L["Name Colored Glow"],
			desc = L["Use the Name Color of the unit for the Name Glow."],
		},
		targetedNamePlate = {
			order = 14,
			type = "group",
			guiInline = true,
			name = L["Targeted Nameplate"],
			args = {
				useTargetScale = {
					order = 1,
					type = "toggle",
					name = L["Use Target Scale"],
					desc = L["Enable/Disable the scaling of targetted nameplates."],
				},
				targetScale = {
					order = 2,
					type = "range",
					isPercent = true,
					name = L["Target Scale"],
					desc = L["Scale of the nameplate that is targetted."],
					min = 0.3, max = 2, step = 0.01,
					disabled = function() return NotRunning() or E.db.nameplates.useTargetScale ~= true end,
				},
				nonTargetTransparency = {
					order = 3,
					type = "range",
					isPercent = true,
					name = L["Non-Target Transparency"],
					desc = L["Set the transparency level of nameplates that are not the target nameplate."],
					min = 0, max = 1, step = 0.01,
				},
				spacer1 = {
					order = 4,
					type = "description",
					name = " ",
				},
				glowColor = {
					order = 5,
					type = "color",
					name = L["Target Indicator Color"],
					hasAlpha = true,
					get = function()
						local t = E.db.nameplates.colors.glowColor
						return t.r, t.g, t.b, t.a
					end,
					set = function(_, r, g, b, a)
						local t = E.db.nameplates.colors.glowColor
						t.r, t.g, t.b, t.a = r, g, b, a
						ConfigureAll()
					end,
				},
				-- Retail ElvUI's target indicator settings (units.TARGET): the
				-- style in ElvUI-vanilla's place, the arrow ones under it.
				glowStyle = {
					order = 6,
					type = "select",
					name = L["Target Indicator"],
					values = GLOW_STYLES,
					get = function() return E.db.nameplates.units.TARGET.glowStyle end,
					set = function(_, value)
						E.db.nameplates.units.TARGET.glowStyle = value
						ConfigureAll()
					end,
				},
				targetArrows = {
					order = 20,
					type = "group",
					name = L["Arrow Texture"],
					guiInline = true,
					get = function(info) return E.db.nameplates.units.TARGET[ info[getn(info)] ] end,
					set = function(info, value)
						E.db.nameplates.units.TARGET[ info[getn(info)] ] = value
						ConfigureAll()
					end,
					args = {
						arrowScale = {
							order = 1,
							type = "range",
							name = L["Arrow Scale"],
							isPercent = true,
							min = 0.2, max = 2, step = 0.01,
						},
						arrowSpacing = {
							order = 2,
							type = "range",
							name = L["Arrow Spacing"],
							min = -60, max = 60, step = 1,
						},
						arrow = {
							order = 3,
							type = "multiselect",
							name = L["Arrow Texture"],
							values = ARROW_TEXTURES,
							get = function(_, key) return E.db.nameplates.units.TARGET.arrow == key end,
							set = function(_, key)
								E.db.nameplates.units.TARGET.arrow = key
								ConfigureAll()
							end,
						},
					},
				},
				alwaysShowTargetHealth = {
					order = 7,
					type = "toggle",
					name = L["Always Show Target Health"],
				},
			},
		},
	},
}

local fontTab = {
	order = 100,
	type = "group",
	name = L["Fonts"],
	args = {
		font = {
			order = 4,
			type = "select",
			dialogControl = "LSM30_Font",
			name = L["Font"],
			values = MediaValues("font"),
		},
		fontSize = {
			order = 5,
			type = "range",
			name = L["Font Size"],
			min = 4, max = 34, step = 1,
		},
		fontOutline = {
			order = 6,
			type = "select",
			name = L["Font Outline"],
			desc = L["Set the font outline."],
			values = {
				["NONE"] = L["None"],
				["OUTLINE"] = "OUTLINE",
				["MONOCHROMEOUTLINE"] = "MONOCROMEOUTLINE",
				["THICKOUTLINE"] = "THICKOUTLINE",
			},
		},
	},
}

-- Real ElvUI's threatGroup (hidden in ElvUI-vanilla, which reads none of
-- it), with the settings read here: no tanked-by-a-tank colour. The
-- transition colours show only with LibVanillaThreat-1.0 loaded.
local threatTab = {
	order = 150,
	type = "group",
	name = L["Threat"],
	get = function(info)
		local t = E.db.nameplates.threat[ info[getn(info)] ]
		return t.r, t.g, t.b
	end,
	set = function(info, r, g, b)
		local t = E.db.nameplates.threat[ info[getn(info)] ]
		t.r, t.g, t.b = r, g, b
		ConfigureAll()
	end,
	args = {
		useThreatColor = {
			order = 1,
			type = "toggle",
			name = L["Use Threat Color"],
			get = function() return E.db.nameplates.threat.useThreatColor end,
			set = function(_, value)
				E.db.nameplates.threat.useThreatColor = value
				ConfigureAll()
			end,
		},
		goodColor = {
			order = 2,
			type = "color",
			name = L["Good Color"],
			hasAlpha = false,
			disabled = function() return NotRunning() or not E.db.nameplates.threat.useThreatColor end,
		},
		badColor = {
			order = 3,
			type = "color",
			name = L["Bad Color"],
			hasAlpha = false,
			disabled = function() return NotRunning() or not E.db.nameplates.threat.useThreatColor end,
		},
		goodTransition = {
			order = 4,
			type = "color",
			name = L["Good Transition Color"],
			hasAlpha = false,
			disabled = function() return NotRunning() or not E.db.nameplates.threat.useThreatColor end,
		},
		badTransition = {
			order = 5,
			type = "color",
			name = L["Bad Transition Color"],
			hasAlpha = false,
			disabled = function() return NotRunning() or not E.db.nameplates.threat.useThreatColor end,
		},
		goodScale = {
			order = 8,
			type = "range",
			name = L["Good Scale"],
			isPercent = true,
			min = 0.3, max = 2, step = 0.01,
			get = function(info) return E.db.nameplates.threat[ info[getn(info)] ] end,
			set = function(info, value)
				E.db.nameplates.threat[ info[getn(info)] ] = value
				ConfigureAll()
			end,
		},
		badScale = {
			order = 9,
			type = "range",
			name = L["Bad Scale"],
			isPercent = true,
			min = 0.3, max = 2, step = 0.01,
			get = function(info) return E.db.nameplates.threat[ info[getn(info)] ] end,
			set = function(info, value)
				E.db.nameplates.threat[ info[getn(info)] ] = value
				ConfigureAll()
			end,
		},
	},
}

local castTab = {
	order = 175,
	type = "group",
	name = L["Cast Bar"],
	args = {
		castColor = {
			order = 1,
			type = "color",
			name = L["Cast Color"],
			hasAlpha = false,
			get = function()
				local t = E.db.nameplates.castColor
				return t.r, t.g, t.b
			end,
			set = function(_, r, g, b)
				local t = E.db.nameplates.castColor
				t.r, t.g, t.b = r, g, b
				ConfigureAll()
			end,
		},
	},
}

local reactionsTab = {
	order = 200,
	type = "group",
	name = L["Reaction Colors"],
	get = function(info)
		local t = E.db.nameplates.reactions[ info[getn(info)] ]
		return t.r, t.g, t.b
	end,
	set = function(info, r, g, b)
		local t = E.db.nameplates.reactions[ info[getn(info)] ]
		t.r, t.g, t.b = r, g, b
		ConfigureAll()
	end,
	args = {
		bad = { order = 1, type = "color", name = L["Enemy"], hasAlpha = false },
		neutral = { order = 2, type = "color", name = L["Neutral"], hasAlpha = false },
		good = { order = 3, type = "color", name = L["Friendly NPC"], hasAlpha = false },
		tapped = { order = 4, type = "color", name = L["Tagged NPC"], hasAlpha = false },
		friendlyPlayer = { order = 5, type = "color", name = L["Friendly Player"], hasAlpha = false },
	},
}

-- Real ElvUI's GetUnitSettings, health / level / name tabs only. Level and
-- name keep real ElvUI's `enable` entries backed by `showLevel` / `showName`.
-- Real ElvUI's buffsGroup / debuffsGroup. Its `filter` select is retail's
-- "Add Regular Filter" of the priority editor: ElvUI-vanilla's wrote
-- `filters.filter`, which nothing reads; the lists take effect through the
-- priority string. Maximum Duration starts at 0 (real ElvUI: 5), which means
-- no limit. ElvUI-vanilla's FRIENDLY_PLAYER buffs have no baseHeight; the
-- module uses 18.
local function AuraGroup(unit, key, order, name)
	local function AuraDB() return E.db.nameplates.units[unit][key] end
	local function Disabled() return NotRunning() or not E.db.nameplates.units[unit].healthbar.enable end
	local group = {
		order = order,
		type = "group",
		name = name,
		get = function(info) return AuraDB()[ info[getn(info)] ] end,
		set = function(info, value)
			AuraDB()[ info[getn(info)] ] = value
			ConfigureAll()
		end,
		disabled = Disabled,
		args = {
			header = { order = 0, type = "header", name = name },
			enable = { order = 1, type = "toggle", name = L["Enable"] },
			numAuras = {
				order = 2,
				type = "range",
				name = L["# Displayed Auras"],
				desc = L["Controls how many auras are displayed, this will also affect the size of the auras."],
				min = 1, max = 8, step = 1,
			},
			baseHeight = {
				order = 3,
				type = "range",
				name = L["Icon Base Height"],
				desc = L["Base Height for the Aura Icon"],
				min = 6, max = 60, step = 1,
				get = function() return AuraDB().baseHeight or 18 end,
			},
			filtersGroup = {
				order = 4,
				type = "group",
				name = L["Filters"],
				guiInline = true,
				get = function(info) return AuraDB().filters[ info[getn(info)] ] end,
				set = function(info, value)
					AuraDB().filters[ info[getn(info)] ] = value
					ConfigureAll()
				end,
				args = {
					personal = {
						order = 1,
						type = "toggle",
						name = L["Personal Auras"],
						get = function() return HasPersonal(AuraDB().filters) end,
						set = function(_, value)
							SetPersonal(AuraDB().filters, value)
							ConfigureAll()
						end,
					},
					-- Retail ElvUI's control; ElvUI-vanilla declares the key
					-- without one. 0 = no minimum.
					minDuration = {
						order = 1.5,
						type = "range",
						name = L["Minimum Duration"],
						min = 0, max = 3000, step = 1,
					},
					maxDuration = {
						order = 2,
						type = "range",
						name = L["Maximum Duration"],
						min = 0, max = 3000, step = 1,
					},
				},
			},
		},
	}
	local editor = E.ConfigShared.FilterPriorityArgs(
		"nameplates." .. unit .. "." .. key,
		function() return AuraDB().filters end,
		function() return P.nameplates.units[unit][key].filters.priority end,
		ConfigureAll,
		Disabled,
		3)
	local filterArgs = group.args.filtersGroup.args
	local option, entry
	for option, entry in pairs(editor) do filterArgs[option] = entry end
	return group
end

local function GetUnitSettings(unit, name)
	return {
		order = 100,
		type = "group",
		name = name,
		childGroups = "tab",
		disabled = NotRunning,
		args = {
			healthGroup = {
				order = 1,
				type = "group",
				name = L["Health"],
				get = function(info) return E.db.nameplates.units[unit].healthbar[ info[getn(info)] ] end,
				set = function(info, value)
					E.db.nameplates.units[unit].healthbar[ info[getn(info)] ] = value
					ConfigureAll()
				end,
				args = {
					header = { order = 0, type = "header", name = L["Health"] },
					enable = { order = 1, type = "toggle", name = L["Enable"] },
					height = { order = 2, type = "range", name = L["Height"], min = 4, max = 20, step = 1 },
					width = { order = 3, type = "range", name = L["Width"], min = 50, max = 200, step = 1 },
					textGroup = {
						order = 100,
						type = "group",
						name = L["Text"],
						guiInline = true,
						get = function(info) return E.db.nameplates.units[unit].healthbar.text[ info[getn(info)] ] end,
						set = function(info, value)
							E.db.nameplates.units[unit].healthbar.text[ info[getn(info)] ] = value
							ConfigureAll()
						end,
						args = {
							enable = { order = 1, type = "toggle", name = L["Enable"] },
							format = {
								order = 2,
								type = "select",
								name = L["Format"],
								values = {
									["CURRENT"] = L["Current"],
									["CURRENT_MAX"] = L["Current / Max"],
									["CURRENT_PERCENT"] = L["Current - Percent"],
									["CURRENT_MAX_PERCENT"] = L["Current - Max | Percent"],
									["PERCENT"] = L["Percent"],
									["DEFICIT"] = L["Deficit"],
								},
							},
						},
					},
				},
			},
			-- Real ElvUI's castGroup without channelTimeFormat: other units'
			-- channels are not reported, so nothing reads it.
			castGroup = {
				order = 3,
				type = "group",
				name = L["Cast Bar"],
				get = function(info) return E.db.nameplates.units[unit].castbar[ info[getn(info)] ] end,
				set = function(info, value)
					E.db.nameplates.units[unit].castbar[ info[getn(info)] ] = value
					ConfigureAll()
				end,
				args = {
					header = { order = 0, type = "header", name = L["Cast Bar"] },
					enable = { order = 1, type = "toggle", name = L["Enable"] },
					hideSpellName = { order = 2, type = "toggle", name = L["Hide Spell Name"] },
					hideTime = { order = 3, type = "toggle", name = L["Hide Time"] },
					height = { order = 4, type = "range", name = L["Height"], min = 4, max = 20, step = 1 },
					offset = { order = 5, type = "range", name = L["Offset"], min = 0, max = 30, step = 1 },
					castTimeFormat = {
						order = 6,
						type = "select",
						name = L["Cast Time Format"],
						values = {
							["CURRENT"] = L["Current"],
							["CURRENT_MAX"] = L["Current / Max"],
							["REMAINING"] = L["Remaining"],
						},
					},
					timeToHold = {
						order = 8,
						type = "range",
						name = L["Time To Hold"],
						desc = L["How many seconds the castbar should stay visible after the cast failed or was interrupted."],
						min = 0, max = 4, step = 0.1,
					},
				},
			},
			buffsGroup = AuraGroup(unit, "buffs", 4, L["Buffs"]),
			debuffsGroup = AuraGroup(unit, "debuffs", 5, L["Debuffs"]),
			levelGroup = {
				order = 6,
				type = "group",
				name = L["Level"],
				args = {
					header = { order = 0, type = "header", name = L["Level"] },
					enable = {
						order = 1,
						type = "toggle",
						name = L["Enable"],
						get = function() return E.db.nameplates.units[unit].showLevel end,
						set = function(_, value)
							E.db.nameplates.units[unit].showLevel = value
							ConfigureAll()
						end,
					},
				},
			},
			nameGroup = {
				order = 7,
				type = "group",
				name = L["Name"],
				args = {
					header = { order = 0, type = "header", name = L["Name"] },
					enable = {
						order = 1,
						type = "toggle",
						name = L["Enable"],
						get = function() return E.db.nameplates.units[unit].showName end,
						set = function(_, value)
							E.db.nameplates.units[unit].showName = value
							ConfigureAll()
						end,
					},
				},
			},
		},
	}
end

local function NoClassCache()
	return not E.private.general.classCache
end

-- Real ElvUI's player-only class colour toggles (health bar and name).
local function AddClassColorToggles(group, unit)
	group.args.healthGroup.args.useClassColor = {
		order = 4,
		type = "toggle",
		name = L["Use Class Color"],
		desc = L["Depends on Class Caching module!"],
		disabled = NoClassCache,
	}
	group.args.nameGroup.get = function(info) return E.db.nameplates.units[unit].name[ info[getn(info)] ] end
	group.args.nameGroup.set = function(info, value)
		E.db.nameplates.units[unit].name[ info[getn(info)] ] = value
		ConfigureAll()
	end
	group.args.nameGroup.args.useClassColor = {
		order = 3,
		type = "toggle",
		name = L["Use Class Color"],
		desc = L["Depends on Class Caching module!"],
		disabled = NoClassCache,
	}
	return group
end

-- Key `nameplate`, singular, as real ElvUI's options arg; the DB key is the
-- plural `nameplates`.
E.Options.args.nameplate = {
	order = 2,
	type = "group",
	name = L["NamePlates"],
	childGroups = "tree",
	get = function(info) return E.db.nameplates[ info[getn(info)] ] end,
	set = function(info, value)
		E.db.nameplates[ info[getn(info)] ] = value
		ConfigureAll()
	end,
	args = {
		enable = {
			order = 1,
			type = "toggle",
			name = L["Enable"],
			desc = L["Requires /reload to take effect."],
			get = function() return E.private.nameplates.enable end,
			set = function(_, value)
				E.private.nameplates.enable = value
				E:RequestReload("private")
			end,
		},
		intro = {
			order = 2,
			type = "description",
			name = L["NAMEPLATE_DESC"],
		},
		generalGroup = {
			order = 14,
			type = "group",
			name = L["General"],
			childGroups = "tab",
			disabled = NotRunning,
			args = {
				general = generalTab,
				fontGroup = fontTab,
				threatGroup = threatTab,
				castGroup = castTab,
				reactions = reactionsTab,
			},
		},
		friendlyPlayerGroup = AddClassColorToggles(GetUnitSettings("FRIENDLY_PLAYER", L["Friendly Player Frames"]), "FRIENDLY_PLAYER"),
		enemyPlayerGroup = AddClassColorToggles(GetUnitSettings("ENEMY_PLAYER", L["Enemy Player Frames"]), "ENEMY_PLAYER"),
		friendlyNPCGroup = GetUnitSettings("FRIENDLY_NPC", L["Friendly NPC Frames"]),
		enemyNPCGroup = GetUnitSettings("ENEMY_NPC", L["Enemy NPC Frames"]),
	},
}
