local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn
-- Cross-file helpers, created in Core.lua: each option file is its own
-- Lua chunk, so a file-local cannot be seen from another file.
local Shared = E.ConfigShared

-- DataTexts panel-assignment select -- lists whatever's actually in
-- `E.DataTexts.RegisteredDataTexts` (populated by DataTexts/*.lua's own
-- `DT:RegisterDatatext` calls at file-load time) rather than a hardcoded
-- values table, so this never drifts out of sync with what widgets exist.
-- Calls `DT:LoadDataTexts()` on change, matching real ElvUI's own
-- PanelLayoutOptions set-functions exactly.
local function PanelDataTextArgs(panelKey, order, label)
	return {
		type = "select",
		name = label,
		order = order,
		values = function()
			local list = { [""] = "None" }
			if E.DataTexts then
				local name
				for name in pairs(E.DataTexts.RegisteredDataTexts) do
					list[name] = name
				end
			end
			return list
		end,
		get = function() return E.db.datatexts.panels[panelKey] end,
		set = function(_, value)
			E.db.datatexts.panels[panelKey] = value
			if E.DataTexts and E.DataTexts.LoadDataTexts then
				E.DataTexts:LoadDataTexts()
			end
		end,
	}
end

-- 3-widget (left/middle/right) variant for LeftChatDataPanel/
-- RightChatDataPanel -- `E.db.datatexts.panels[panelKey]` is a
-- `{left=,middle=,right=}` table for these two panels specifically
-- (Modules/DataTexts/DataTexts.lua's own P.datatexts.panels defaults),
-- unlike the bare-string shape the Minimap panels use.
local function ChatPanelDataTextArgs(panelKey, order, label)
	local function PointArgs(pointKey, pointOrder, pointLabel)
		return {
			type = "select",
			name = pointLabel,
			order = pointOrder,
			values = function()
				local list = { [""] = "None" }
				if E.DataTexts then
					local name
					for name in pairs(E.DataTexts.RegisteredDataTexts) do
						list[name] = name
					end
				end
				return list
			end,
			get = function() return E.db.datatexts.panels[panelKey][pointKey] end,
			set = function(_, value)
				E.db.datatexts.panels[panelKey][pointKey] = value
				if E.DataTexts and E.DataTexts.LoadDataTexts then
					E.DataTexts:LoadDataTexts()
				end
			end,
		}
	end

	return {
		type = "group",
		name = label,
		order = order,
		guiInline = true,
		args = {
			left = PointArgs("left", 1, "Left"),
			middle = PointArgs("middle", 2, "Middle"),
			right = PointArgs("right", 3, "Right"),
		},
	}
end

-- DataTexts (Modules/DataTexts/*.lua) -- real ElvUI's
-- own top-level category (E.Options.args.datatexts,
-- source/ElvUI-vanilla/ElvUI_Config/DataTexts.lua). Scoped down to
-- what this project actually has: minimapTop/
-- minimapTopLeft/etc. (real ElvUI has 8 possible minimap-adjacent
-- panel slots -- this project only builds LeftMiniPanel/
-- RightMiniPanel, matching real ElvUI's own DEFAULT two-panel
-- layout) and battleground/noCombatClick/noCombatHover are left out
-- rather than stubbed. `panelTransparency`/`panelBackdrop` ARE wired --
-- the Layout module's SetDataPanelStyle is their consumer -- and so are
-- `leftChatPanel`/`rightChatPanel`, since Modules/Chat/Chat.lua creates
-- LeftChatDataPanel/RightChatDataPanel. `font` follows the same
-- plain-LSM-select pattern as ActionBars'/DataBars' own font
-- fields (no LSM30_Font AceGUI widget, see those fields' own
-- comments) -- font size/outline are confirmed UA no-ops but wired
-- anyway, same as every other font field in this project (e.g.
-- ActionBars' Fonts group). Panel widget-assignment selects list `E.DataTexts
-- .RegisteredDataTexts` dynamically (Gold/Time/System/Durability/
-- Armor/Attack Power/Avoidance/Guild/Friends -- whatever's actually
-- registered, so this list never drifts out of sync with the
-- widget files) instead of a hardcoded values table.
E.Options.args.datatexts = {
	type = "group",
	name = L["DataTexts"],
	order = 5,
	childGroups = "tab",
	args = {
		intro = {
			order = 1,
			type = "description",
			name = L["Small information panels; each slot can show a different datatext."],
		},
		spacer = {
			order = 2,
			type = "description",
			name = L["\n"],
		},
		general = {
			type = "group",
			name = L["General"],
			order = 1,
			args = {
				-- No manual header here (unlike this file's other tabs,
				-- Panels/Time/Friends) -- generalGroup right below is
				-- guiInline and ALSO named "General"; LibConfig-1.0
				-- auto-titles an inline group from its own `name`
				-- (matching real AceConfigDialog-3.0's inline-group
				-- behavior), so a manual header here would repeat it
				-- verbatim. See UnitFrames.lua's generalOptionsGroup for
				-- the fuller writeup of this LibConfig-1.0 rendering rule.
				--
				-- Real ElvUI wraps this in a `generalGroup`; orders 1-5 there
				-- are battleground/panelTransparency/panelBackdrop/
				-- noCombatClick/noCombatHover. Orders 1, 4 and 5 stay free
				-- (not implemented); 2 and 3 are wired to the Layout
				-- module's SetDataPanelStyle.
				generalGroup = {
					type = "group",
					name = L["General"],
					guiInline = true,
					order = 2,
					args = {
					panelTransparency = {
						type = "toggle",
						name = L["Panel Transparency"],
						desc = L["Use the transparent backdrop for the datatext panels instead of the solid one."],
						order = 2,
						get = function() return E.db.datatexts.panelTransparency end,
						set = function(_, value)
							E.db.datatexts.panelTransparency = value
							E:GetModule("Layout"):SetDataPanelStyle()
						end,
					},
					panelBackdrop = {
						type = "toggle",
						name = L["Backdrop"],
						desc = L["Draw a backdrop behind the chat datatext panels. Turning this off leaves them functional but invisible."],
						order = 3,
						get = function() return E.db.datatexts.panelBackdrop end,
						set = function(_, value)
							E.db.datatexts.panelBackdrop = value
							E:GetModule("Layout"):SetDataPanelStyle()
						end,
					},
					goldFormat = {
						type = "select",
						name = L["Gold Format"],
						desc = L["The display format of the money text shown in the gold datatext and its tooltip."],
						order = 6,
						values = {
							["SMART"] = L["Smart"],
							["FULL"] = L["Full"],
							["SHORT"] = L["Short"],
							["SHORTINT"] = L["Short (Whole Numbers)"],
							["CONDENSED"] = L["Condensed"],
							["BLIZZARD"] = L["Blizzard Style"],
						},
						get = function() return E.db.datatexts.goldFormat end,
						set = function(_, value) E.db.datatexts.goldFormat = value end,
					},
					},
				},
				fontGroup = {
					type = "group",
					name = L["Fonts"],
					guiInline = true,
					order = 4,
					args = {
						font = {
							type = "select",
							name = L["Font"],
							dialogControl = "LSM30_Font",
							order = 1,
							values = function()
								local LSM = LibStub("LibSharedMedia-3.0", true)
								local list = {}
								if LSM then
									local names = LSM:List("font")
									local i
									for i = 1, table.getn(names) do
										list[names[i]] = names[i]
									end
								end
								return list
							end,
							get = function() return E.db.datatexts.font end,
							set = function(_, value) E.db.datatexts.font = value end,
						},
						fontSize = {
							type = "range",
							name = L["Font Size"],
							desc = L["Currently a no-op on UA (SetFont doesn't apply size there) -- kept for real 1.12.1 and in case UA fixes this."],
							order = 2,
							min = 4,
							max = 22,
							step = 1,
							get = function() return E.db.datatexts.fontSize end,
							set = function(_, value) E.db.datatexts.fontSize = value end,
						},
						fontOutline = {
							type = "select",
							name = L["Font Outline"],
							order = 3,
							values = {
								["NONE"] = L["None"],
								["OUTLINE"] = L["Outline"],
								["MONOCHROMEOUTLINE"] = L["Monochrome Outline"],
								["THICKOUTLINE"] = L["Thick Outline"],
							},
							get = function() return E.db.datatexts.fontOutline end,
							set = function(_, value) E.db.datatexts.fontOutline = value end,
						},
					},
				},
			},
		},
		panels = {
			type = "group",
			name = L["Panels"],
			order = 2,
			args = {
				header = {
					type = "header",
					name = L["Panels"],
					order = 1,
				},
				-- Both of these drive the Layout module, as in real ElvUI
				-- (its ElvUI_Config/DataTexts.lua:189-218). Upstream also
				-- re-runs its HideLeftChat()/HideRightChat() here to re-settle
				-- a collapsed panel after the toggle button moves;
				-- deliberately not copied -- ours recomputes the button's
				-- anchors inside UpdateDataPanelVisibility anyway, and
				-- upstream's version is wrapped in a guard that reads as a
				-- no-op (`if E.db.LeftChatPanelFaded then E.db
				-- .LeftChatPanelFaded = true`).
				leftChatPanel = {
					type = "toggle",
					name = L["Datatext Panel (Left)"],
					desc = L["Display a data panel below the left chat frame, used for datatexts."],
					order = 2,
					get = function() return E.db.datatexts.leftChatPanel end,
					set = function(_, value)
						E.db.datatexts.leftChatPanel = value
						E:GetModule("Layout"):ToggleChatPanels()
					end,
				},
				rightChatPanel = {
					type = "toggle",
					name = L["Datatext Panel (Right)"],
					desc = L["Display a data panel below the right chat frame, used for datatexts."],
					order = 3,
					get = function() return E.db.datatexts.rightChatPanel end,
					set = function(_, value)
						E.db.datatexts.rightChatPanel = value
						E:GetModule("Layout"):ToggleChatPanels()
					end,
				},
				-- Real ElvUI keeps `minimapPanels` here, in `panels` -- ours used
				-- to sit under `general`.
				minimapPanels = {
					type = "toggle",
					name = L["Minimap Panels"],
					desc = L["Display minimap panels below the minimap, used for datatexts."],
					order = 4,
					get = function() return E.db.datatexts.minimapPanels end,
					set = function(_, value)
						E.db.datatexts.minimapPanels = value
						Shared.UpdateMinimapSettings()
					end,
				},
				-- Orders 5-10 are real ElvUI's six minimap CORNER panel toggles
				-- (minimapTop/TopLeft/TopRight/Bottom/BottomLeft/BottomRight).
				-- This project doesn't build those frames, so the numbers are
				-- left free rather than closed up.
				spacer = {
					type = "description",
					name = " ",
					order = 11,
				},
				-- The per-panel datatext selectors live in their own
				-- `smallPanels` group, as in real ElvUI. Ours used to hang
				-- directly off `panels`.
				smallPanels = {
					type = "group",
					name = L["Small Panels"],
					guiInline = true,
					order = 12,
					args = {
						LeftMiniPanel = PanelDataTextArgs("LeftMiniPanel", 1, "Left Minimap Panel"),
						RightMiniPanel = PanelDataTextArgs("RightMiniPanel", 2, "Right Minimap Panel"),
					},
				},
				LeftChatDataPanel = ChatPanelDataTextArgs("LeftChatDataPanel", 13, "Left Chat Panel"),
				RightChatDataPanel = ChatPanelDataTextArgs("RightChatDataPanel", 14, "Right Chat Panel"),
			},
		},
		time = {
			type = "group",
			name = L["Time"],
			order = 3,
			args = {
				header = {
					type = "header",
					name = L["Time"],
					order = 1,
				},
				timeFormat = {
					type = "select",
					name = L["Time Format"],
					order = 2,
					values = {
						[""] = "None",
						["%I:%M"] = "03:27",
						["%I:%M:%S"] = "03:27:32",
						["%I:%M %p"] = "03:27 PM",
						["%I:%M:%S %p"] = "03:27:32 PM",
						["%H:%M"] = "15:27",
						["%H:%M:%S"] = "15:27:32",
					},
					get = function() return E.db.datatexts.timeFormat end,
					set = function(_, value) E.db.datatexts.timeFormat = value end,
				},
				dateFormat = {
					type = "select",
					name = L["Date Format"],
					order = 3,
					values = {
						[""] = "None",
						["%d/%m/%y "] = "DD/MM/YY",
						["%m/%d/%y "] = "MM/DD/YY",
						["%y/%m/%d "] = "YY/MM/DD",
						["%d.%m.%y "] = "DD.MM.YY",
						["%m.%d.%y "] = "MM.DD.YY",
						["%y.%m.%d "] = "YY.MM.DD",
					},
					get = function() return E.db.datatexts.dateFormat end,
					set = function(_, value) E.db.datatexts.dateFormat = value end,
				},
			},
		},
		friends = {
			type = "group",
			name = L["Friends"],
			order = 4,
			args = {
				header = {
					type = "header",
					name = L["Friends"],
					order = 1,
				},
				hideGroup = {
					type = "group",
					name = L["Hide"],
					guiInline = true,
					order = 2,
					args = {
						hideAFK = {
							type = "toggle",
							name = L["Away"],
							order = 1,
							get = function() return E.db.datatexts.friends.hideAFK end,
							set = function(_, value) E.db.datatexts.friends.hideAFK = value end,
						},
						hideDND = {
							type = "toggle",
							name = L["Busy"],
							order = 2,
							get = function() return E.db.datatexts.friends.hideDND end,
							set = function(_, value) E.db.datatexts.friends.hideDND = value end,
						},
					},
				},
			},
		},
	},
}
