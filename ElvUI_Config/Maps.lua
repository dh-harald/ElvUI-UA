local E, L, V, P, G = unpack(ElvUI)
-- Cross-file helpers, created in Core.lua: each option file is its own
-- Lua chunk, so a file-local cannot be seen from another file.
local Shared = E.ConfigShared

-- Shared position/scale/xOffset/yOffset args for one icons.<key> entry
-- (E.db.general.minimap.icons[key]) -- calendar/mail/battlefield in real
-- ElvUI's Maps.lua are these same 4 fields verbatim, differing only by
-- key and (calendar only) an extra private Hide toggle, so this factors
-- out the copy-paste rather than repeating it 3 times.
local function IconArgs(key, label, includeHide)
	local disabledFn
	if includeHide then
		disabledFn = function() return E.private.general.minimap.hideCalendar end
	end

	local args = {
		-- Each icon group carries its own header, matching real ElvUI.
		header = {
			type = "header",
			name = label,
			order = 0,
		},
		position = {
			type = "select",
			name = L["Position"],
			order = 2,
			values = Shared.POSITION_VALUES,
			get = function() return E.db.general.minimap.icons[key].position end,
			set = function(_, value)
				E.db.general.minimap.icons[key].position = value
				Shared.UpdateMinimapSettings()
			end,
			disabled = disabledFn,
		},
		scale = {
			type = "range",
			name = L["Scale"],
			order = 3,
			min = 0.5,
			max = 2,
			step = 0.05,
			get = function() return E.db.general.minimap.icons[key].scale end,
			set = function(_, value)
				E.db.general.minimap.icons[key].scale = value
				Shared.UpdateMinimapSettings()
			end,
			disabled = disabledFn,
		},
		xOffset = {
			type = "range",
			name = L["X Offset"],
			order = 4,
			min = -50,
			max = 50,
			step = 1,
			get = function() return E.db.general.minimap.icons[key].xOffset end,
			set = function(_, value)
				E.db.general.minimap.icons[key].xOffset = value
				Shared.UpdateMinimapSettings()
			end,
			disabled = disabledFn,
		},
		yOffset = {
			type = "range",
			name = L["Y Offset"],
			order = 5,
			min = -50,
			max = 50,
			step = 1,
			get = function() return E.db.general.minimap.icons[key].yOffset end,
			set = function(_, value)
				E.db.general.minimap.icons[key].yOffset = value
				Shared.UpdateMinimapSettings()
			end,
			disabled = disabledFn,
		},
	}

	if includeHide then
		args.hideCalendar = {
			type = "toggle",
			name = L["Hide"],
			desc = L["Note: the calendar icon was invisible near the minimap on UA (a frame-stacking issue, see CLAUDE.md) -- a fix was applied 2026-08-31 but isn't yet confirmed in-game."],
			order = 1,
			get = function() return E.private.general.minimap.hideCalendar end,
			set = function(_, value)
				E.private.general.minimap.hideCalendar = value
				Shared.UpdateMinimapSettings()
			end,
		}
		-- Real ElvUI separates the calendar's hide toggle from the position row
		-- with a blank description; only the calendar group has one.
		args.spacer = {
			type = "description",
			name = " ",
			order = 1.5,
		}
	end

	return args
end

E.Options.args.maps = {
	type = "group",
	name = L["Map"],
	order = 3,
	childGroups = "tab",
	args = {
		-- `worldMap`, not `map`, and split into `generalGroup` +
		-- `coordinatesGroup`: real ElvUI's own shape. Ours used to be one
		-- flat group named `map`, which put every one of these controls at a
		-- different tree path than the original.
		worldMap = {
			type = "group",
			name = L["World Map"],
			order = 1,
			args = {
				header = {
					order = 0,
					type = "header",
					name = L["World Map"],
				},
				generalGroup = {
					order = 1,
					type = "group",
					name = L["General"],
					guiInline = true,
					args = {
						-- Global and reload-required (a one-shot Initialize check),
						-- same as real ElvUI's own GLOBAL_RL popup on this setting.
						-- Untested -- see Modules/Maps/WorldMap.lua's
						-- ApplySmallerWorldMap.
						smallerWorldMap = {
							order = 1,
							type = "toggle",
							name = L["Smaller World Map"],
							desc = L["Opens the World Map as a normal panel instead of a fullscreen, input-blocking window. Requires /reload -- untested."],
							get = function() return E.global.general.smallerWorldMap end,
							set = function(_, value)
								E.global.general.smallerWorldMap = value
								E:RequestReload("global")
							end,
						},
					},
				},
				spacer = {
					order = 2,
					type = "description",
					name = L["\n"],
				},
				-- WorldMapCoordinates is GLOBAL, not profile, matching real
				-- ElvUI's own Settings/Global.lua. `enable` is reload-required
				-- (checked once at Initialize, same reason as Minimap's own
				-- enable); position/offsets apply live via WM:PositionCoords().
				coordinatesGroup = {
					order = 3,
					type = "group",
					name = L["World Map Coordinates"],
					guiInline = true,
					disabled = function() return not E.global.general.WorldMapCoordinates.enable end,
					args = {
						enable = {
							order = 1,
							type = "toggle",
							name = L["Enable"],
							desc = L["Puts coordinates on the world map. Requires /reload to take effect -- checked once at login, no live toggle."],
							get = function() return E.global.general.WorldMapCoordinates.enable end,
							set = function(_, value)
								E.global.general.WorldMapCoordinates.enable = value
								E:RequestReload("global")
							end,
							-- The group-level `disabled` would grey this out as soon
							-- as coordinates are off, leaving no way to switch them
							-- back on. A leaf's own value overrides the group's.
							disabled = false,
						},
						spacer = {
							order = 2,
							type = "description",
							name = " ",
						},
						position = {
							order = 3,
							type = "select",
							name = L["Position"],
							values = Shared.POSITION_VALUES,
							get = function() return E.global.general.WorldMapCoordinates.position end,
							set = function(_, value)
								E.global.general.WorldMapCoordinates.position = value
								if E.WorldMap and E.WorldMap.PositionCoords then E.WorldMap:PositionCoords() end
							end,
						},
						xOffset = {
							order = 4,
							type = "range",
							name = L["X-Offset"],
							min = -50,
							max = 50,
							step = 1,
							get = function() return E.global.general.WorldMapCoordinates.xOffset end,
							set = function(_, value)
								E.global.general.WorldMapCoordinates.xOffset = value
								if E.WorldMap and E.WorldMap.PositionCoords then E.WorldMap:PositionCoords() end
							end,
						},
						yOffset = {
							order = 5,
							type = "range",
							name = L["Y-Offset"],
							min = -50,
							max = 50,
							step = 1,
							get = function() return E.global.general.WorldMapCoordinates.yOffset end,
							set = function(_, value)
								E.global.general.WorldMapCoordinates.yOffset = value
								if E.WorldMap and E.WorldMap.PositionCoords then E.WorldMap:PositionCoords() end
							end,
						},
					},
				},
			},
		},
		minimap = {
			type = "group",
			name = L["Minimap"],
			order = 2,
			childGroups = "tab",
			args = {
				header = {
					type = "header",
					name = L["Minimap"],
					order = 0,
				},
				generalGroup = {
					type = "group",
					name = L["General"],
					guiInline = true,
					order = 1,
					args = {
						enable = {
							type = "toggle",
							name = L["Enable"],
							desc = L["Requires /reload to take effect -- checked once at login, no live toggle."],
							order = 1,
							get = function() return E.private.general.minimap.enable end,
							set = function(_, value)
								E.private.general.minimap.enable = value
								E:RequestReload("private")
							end,
						},
						size = {
							type = "range",
							name = L["Size"],
							desc = L["Adjust the size of the minimap. Takes effect immediately."],
							order = 2,
							min = 120,
							max = 250,
							step = 1,
							get = function() return E.db.general.minimap.size end,
							set = function(_, value)
								E.db.general.minimap.size = value
								Shared.UpdateMinimapSettings()
							end,
							disabled = function() return not E.private.general.minimap.enable end,
						},
					},
				},
				locationTextGroup = {
					type = "group",
					name = L["Location Text"],
					order = 2,
					args = {
						header = {
							type = "header",
							name = L["Location Text"],
							order = 0,
						},
						locationText = {
							type = "select",
							name = L["Location Text"],
							desc = L["Change when the zone name above the minimap is shown."],
							order = 1,
							values = {
								MOUSEOVER = L["Minimap Mouseover"],
								SHOW = L["Always Display"],
								HIDE = L["Hide"],
							},
							get = function() return E.db.general.minimap.locationText end,
							set = function(_, value)
								E.db.general.minimap.locationText = value
								Shared.UpdateMinimapSettings()
							end,
							disabled = function() return not E.private.general.minimap.enable end,
						},
					},
				},
				zoomResetGroup = {
					type = "group",
					name = L["Reset Zoom"],
					order = 3,
					args = {
						header = {
							type = "header",
							name = L["Reset Zoom"],
							order = 0,
						},
						-- `enableZoomReset`/`zoomResetTime`, not `enable`/`time`:
						-- real ElvUI's own entry names. The DB fields they drive
						-- stay `resetZoom.enable`/`resetZoom.time`, so the get/set
						-- pair is explicit here rather than key-derived.
						enableZoomReset = {
							type = "toggle",
							name = L["Reset Zoom"],
							desc = L["Automatically zoom back out after a period of no zoom activity."],
							order = 1,
							get = function() return E.db.general.minimap.resetZoom.enable end,
							set = function(_, value)
								E.db.general.minimap.resetZoom.enable = value
								Shared.UpdateMinimapSettings()
							end,
							disabled = function() return not E.private.general.minimap.enable end,
						},
						zoomResetTime = {
							type = "range",
							name = L["Seconds"],
							order = 2,
							min = 1,
							max = 15,
							step = 1,
							get = function() return E.db.general.minimap.resetZoom.time end,
							set = function(_, value) E.db.general.minimap.resetZoom.time = value end,
							disabled = function()
								return (not E.db.general.minimap.resetZoom.enable) or (not E.private.general.minimap.enable)
							end,
						},
					},
				},
				icons = {
					type = "group",
					name = L["Minimap Buttons"],
					order = 4,
					-- Real ElvUI's own `icons` group does NOT set this -- it
					-- relies on AceConfigDialog's embedded nested-tree widget
					-- (a local list INSIDE the tab pane) for Calendar/Mail/PvP
					-- Queue, which LibConfig-1.0 doesn't have. Setting
					-- childGroups="tab" here instead reuses our already-working
					-- tab strip to get the same practical result -- Calendar/
					-- Mail/PvP Queue navigable LOCALLY within this tab, not
					-- scattered into the global sidebar -- just as a horizontal
					-- button row instead of a vertical list.
					childGroups = "tab",
					args = {
						header = {
							type = "header",
							name = L["Minimap Buttons"],
							order = 0,
						},

						calendar = {
							type = "group",
							name = L["Time Info"],
							order = 1,
							args = IconArgs("calendar", "Time Info", true),
						},
						mail = {
							type = "group",
							name = L["Mail"],
							order = 2,
							args = IconArgs("mail", "Mail", false),
						},
						battlefield = {
							type = "group",
							name = L["PvP Queue"],
							order = 3,
							args = IconArgs("battlefield", "PvP Queue", false),
						},
					},
				},
			},
		},
	},
}
