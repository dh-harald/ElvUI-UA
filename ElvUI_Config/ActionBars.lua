local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local getn = ElvUI.Compat.getn

local function UpdateActionBar(id)
	if E.ActionBars and E.ActionBars.UpdateBar then
		E.ActionBars:UpdateBar(id)
	end
end

-- For the MODULE-WIDE settings in the "General" group (keybind/macro text and
-- their placement): those live on `E.db.actionbar` itself, not per bar, so every
-- bar has to be re-styled, not just one. StyleButton is idempotent, so this is
-- safe to call from any setter.
local NUM_BARS = 5
local function UpdateAllActionBars()
	local i
	for i = 1, NUM_BARS do
		UpdateActionBar(i)
	end
end

-- Shared per-bar args for the "Bar 1".."Bar 5" tabs -- ported from real
-- ElvUI_Config/ActionBars.lua's own `for i = 1, 5 do ... end` block, minus
-- the fields that need infrastructure this project doesn't have (anchor
-- point, width/height multiplier, backdrop spacing, mouseover-fade,
-- restorePosition/movers -- see Modules/ActionBars.lua's file header for
-- the full skip list). `enabled` is reload-required (enabling/disabling a
-- bar reparents or releases its native buttons, which UpdateBar doesn't
-- do live) -- every other field applies live via E.ActionBars:UpdateBar(id).
local function BarArgs(id)
	local key = "bar"..id

	return {
		-- Real ElvUI opens every bar group with its own header and separates the
		-- enable row from the layout rows with a blank description.
		info = {
			type = "header",
			name = L["Bar "]..id,
			order = 1,
		},
		spacer = {
			type = "description",
			name = " ",
			order = 4,
		},
		enabled = {
			type = "toggle",
			name = L["Enable"],
			desc = L["Requires /reload to take effect."],
			order = 2,
			get = function() return E.db.actionbar[key].enabled end,
			-- Genuinely reload-bound BY DESIGN, not an oversight: disabling a bar
			-- routes through HideDisabledBar -> HideFrame, which permanently
			-- overwrites button.Show as a defence against the native code
			-- re-asserting it (docs/modules/actionbars.md). That is
			-- irreversible within a session, so the popup is the honest answer.
			set = function(_, value)
				E.db.actionbar[key].enabled = value
				E:RequestReload()
			end,
		},
		buttons = {
			type = "range",
			name = L["Buttons"],
			desc = L["The amount of buttons to display."],
			order = 10,
			min = 1,
			max = 12,
			step = 1,
			get = function() return E.db.actionbar[key].buttons end,
			set = function(_, value)
				E.db.actionbar[key].buttons = value
				UpdateActionBar(id)
			end,
			disabled = function() return not E.db.actionbar[key].enabled end,
		},
		buttonsPerRow = {
			type = "range",
			name = L["Buttons Per Row"],
			desc = L["The amount of buttons to display per row."],
			order = 11,
			min = 1,
			max = 12,
			step = 1,
			get = function() return E.db.actionbar[key].buttonsPerRow end,
			set = function(_, value)
				E.db.actionbar[key].buttonsPerRow = value
				UpdateActionBar(id)
			end,
			disabled = function() return not E.db.actionbar[key].enabled end,
		},
		buttonsize = {
			type = "range",
			name = L["Button Size"],
			desc = L["The size of the action buttons."],
			order = 12,
			min = 20,
			max = 50,
			step = 1,
			get = function() return E.db.actionbar[key].buttonsize end,
			set = function(_, value)
				E.db.actionbar[key].buttonsize = value
				UpdateActionBar(id)
			end,
			disabled = function() return not E.db.actionbar[key].enabled end,
		},
		buttonspacing = {
			type = "range",
			name = L["Button Spacing"],
			desc = L["The spacing between buttons."],
			order = 12,
			min = 0,
			max = 20,
			step = 1,
			get = function() return E.db.actionbar[key].buttonspacing end,
			set = function(_, value)
				E.db.actionbar[key].buttonspacing = value
				UpdateActionBar(id)
			end,
			disabled = function() return not E.db.actionbar[key].enabled end,
		},
		-- `backdropSpacing`: real ElvUI's own key and order (13, right after
		-- buttonspacing at 12 -- ours sat on 13, which is why it moved down one).
		-- Zero new runtime code: `ElvUI.Util.BarPadding` was ALREADY reading this
		-- field (falling back to buttonspacing when absent), so it was an
		-- implemented setting that simply had no default and no control.
		backdropSpacing = {
			type = "range",
			name = L["Backdrop Spacing"],
			desc = L["The spacing between the backdrop and the buttons."],
			order = 13,
			min = 0,
			max = 10,
			step = 1,
			get = function() return E.db.actionbar[key].backdropSpacing end,
			set = function(_, value)
				E.db.actionbar[key].backdropSpacing = value
				UpdateActionBar(id)
			end,
			disabled = function()
				return not E.db.actionbar[key].enabled or not E.db.actionbar[key].backdrop
			end,
		},
		backdrop = {
			type = "toggle",
			name = L["Backdrop"],
			desc = L["Toggles the display of the actionbar's backdrop."],
			order = 5,
			get = function() return E.db.actionbar[key].backdrop end,
			set = function(_, value)
				E.db.actionbar[key].backdrop = value
				UpdateActionBar(id)
			end,
			disabled = function() return not E.db.actionbar[key].enabled end,
		},
		showGrid = {
			type = "toggle",
			name = L["Show Empty Buttons"],
			order = 6,
			get = function() return E.db.actionbar[key].showGrid end,
			set = function(_, value)
				E.db.actionbar[key].showGrid = value
				UpdateActionBar(id)
			end,
			disabled = function() return not E.db.actionbar[key].enabled end,
		},
		alpha = {
			type = "range",
			name = L["Alpha"],
			order = 14,
			min = 0,
			max = 1,
			step = 0.01,
			get = function() return E.db.actionbar[key].alpha end,
			set = function(_, value)
				E.db.actionbar[key].alpha = value
				UpdateActionBar(id)
			end,
			disabled = function() return not E.db.actionbar[key].enabled end,
		},
	}
end

-- ActionBars: private `enable` (reload-required, one-shot
-- Initialize check, same reasoning as Minimap's own enable).
-- size/spacing are profile settings, applied live via
-- AB:PositionBar() -- see Modules/ActionBars.lua. First pass only
-- covers bar1 (the 12 main action buttons); no bar2-5, pet/stance
-- bars, hotkey/macro text, or cooldown text yet.
E.Options.args.actionbar = {
	type = "group",
	name = L["ActionBars"],
	order = 2,
	-- "tree" (LibConfig-1.0's default, but explicit here for
	-- clarity), NOT "tab" -- matches real ElvUI's own
	-- E.Options.args.actionbar (source/ElvUI-vanilla/
	-- ElvUI_Config/ActionBars.lua:773: `childGroups = "tree"`):
	-- Bar 1-5/General sit as separate sidebar rows under
	-- "ActionBars" in a real install, not as tabs on one page.
	childGroups = "tree",
	args = {
		intro = {
			order = 2,
			type = "description",
			name = L["Action bar layout, sizing and text. Each bar is configured on its own tab."],
		},
		-- Module-wide, private, reload-required -- rendered on
		-- the "ActionBars" page itself (a group's own leaf args
		-- always render above/alongside its child list,
		-- regardless of tree vs tab).
		enable = {
			type = "toggle",
			name = L["Enable"],
			desc = L["Requires /reload to take effect -- checked once at login, no live toggle."],
			order = 1,
			get = function() return E.private.actionbar.enable end,
			set = function(_, value)
				E.private.actionbar.enable = value
				E:RequestReload("private")
			end,
		},
		-- "General" first, then Bar 1-5 (matches real ElvUI's own
		-- default order too). Sidebar rows, not tabs.
		general = {
			type = "group",
			name = L["General"],
			order = 2,
			args = {
				info = {
					type = "header",
					name = L["General Options"],
					order = 1,
				},
				hotkeytext = {
					type = "toggle",
					name = L["Keybind Text"],
					desc = L["Display bind names on action buttons."],
					order = 1,
					get = function() return E.db.actionbar.hotkeytext end,
					set = function(_, value) E.db.actionbar.hotkeytext = value end,
				},
				macrotext = {
					type = "toggle",
					name = L["Macro Text"],
					desc = L["Display macro names on action buttons."],
					order = 2,
					get = function() return E.db.actionbar.macrotext end,
					set = function(_, value) E.db.actionbar.macrotext = value end,
				},
				lockActionBars = {
					type = "toggle",
					name = L["Lock Action Bars"],
					desc = L["Prevent dragging spells and items off the action bars."],
					order = 3,
					get = function() return E.db.actionbar.lockActionBars end,
					-- Applies live because the native `LOCK_ACTIONBAR` global is
					-- re-read on every drag attempt and never cached (both the
					-- stock ActionBarFrame/PetActionBarFrame code and this
					-- project's own pickup guards in Modules/ActionBars/
					-- ActionBars.lua test it fresh). Writing only the DB left
					-- the global at whatever M:Initialize last set, which is
					-- what made this look reload-bound. Both branches are
					-- explicit, as in M:Initialize -- setting just the "1" side
					-- would never clear a stale lock.
					set = function(_, value)
						E.db.actionbar.lockActionBars = value
						if value then
							_G.LOCK_ACTIONBAR = "1"
						else
							_G.LOCK_ACTIONBAR = "0"
						end
					end,
				},
				-- The real ElvUI reference (source/ElvUI-vanilla/
				-- ElvUI_Config/ActionBars.lua:41-46) does NOT
				-- duplicate the Cooldown Text settings here --
				-- it's just an "execute"-type shortcut button
				-- that jumps to General > Cooldown Text
				-- (`ACD:SelectGroup("ElvUI", "general",
				-- "cooldown")`). The real settings now live
				-- there too (see the new top-level "general"
				-- category below) -- not duplicated here.
				-- LibConfig-1.0 has no cross-page-navigation API
				-- yet (only Open/OpenToCategory/Close), so the
				-- jump-shortcut itself isn't reproduced -- a
				-- lower-value nicety, not settings data.
				-- Ported from real ElvUI's own "Fonts" group
				-- (source/ElvUI-vanilla/ElvUI_Config/
				-- ActionBars.lua:158-185), even though font size is
				-- already a confirmed no-op via SetFont on UA --
				-- wired up anyway since it costs nothing and may
				-- start working if UA's font handling improves.
				-- `font` is a plain "select" reading
				-- LibSharedMedia-3.0's registered font names
				-- (Media/SharedMedia.lua) -- NOT the LSM30_Font
				-- AceGUI widget real ElvUI uses, since AceGUI
				-- isn't vendored in this project. Field renamed
				-- from an earlier `fontFamily` --
				-- real ElvUI's actual field is `font`
				-- (P["actionbar"].font); the old name would have
				-- silently dropped a real saved profile's value.
				-- Real ElvUI keeps the font settings in their own
				-- `fontGroup` inside `general`, not flat alongside the
				-- toggles. Ours used to be flat, so all three sat at a
				-- tree path the original does not have.
				fontGroup = {
					order = 20,
					type = "group",
					name = L["Fonts"],
					guiInline = true,
					args = {
					textPosition = {
						order = 8,
						type = "group",
						name = L["Text Position"],
						guiInline = true,
						args = {
					-- Keybind text placement. Real ElvUI nests these in
					-- `fontGroup.textPosition` (its own order 8), NOT directly under
					-- `general` -- the same 'right setting, wrong place' trap the rest
					-- of this refactor keeps finding. Live: the position is part of
					-- StyleButton's re-apply signature.
						hotkeyTextPosition = {
							type = "select",
							name = L["Hotkey Text Position"],
							order = 4,
							values = {
								["TOPLEFT"] = "TOPLEFT",
								["TOP"] = "TOP",
								["TOPRIGHT"] = "TOPRIGHT",
								["BOTTOMLEFT"] = "BOTTOMLEFT",
								["BOTTOM"] = "BOTTOM",
								["BOTTOMRIGHT"] = "BOTTOMRIGHT",
							},
							get = function() return E.db.actionbar.hotkeyTextPosition end,
							set = function(_, value)
								E.db.actionbar.hotkeyTextPosition = value
								UpdateAllActionBars()
							end,
						},
						hotkeyTextXOffset = {
							type = "range",
							name = L["Hotkey Text X-Offset"],
							order = 5,
							min = -10, max = 10, step = 1,
							get = function() return E.db.actionbar.hotkeyTextXOffset end,
							set = function(_, value)
								E.db.actionbar.hotkeyTextXOffset = value
								UpdateAllActionBars()
							end,
						},
						hotkeyTextYOffset = {
							type = "range",
							name = L["Hotkey Text Y-Offset"],
							order = 6,
							min = -10, max = 10, step = 1,
							get = function() return E.db.actionbar.hotkeyTextYOffset end,
							set = function(_, value)
								E.db.actionbar.hotkeyTextYOffset = value
								UpdateAllActionBars()
							end,
						},
						},
					},
					font = {
						type = "select",
						name = L["Font"],
						dialogControl = "LSM30_Font",
						order = 4,
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
						get = function() return E.db.actionbar.font end,
						set = function(_, value) E.db.actionbar.font = value end,
					},
					fontSize = {
						type = "range",
						name = L["Font Size"],
						desc = L["Applies to keybind and macro text. Currently a no-op on UA (SetFont doesn't apply size there) -- kept for real 1.12.1 and in case UA fixes this."],
						order = 5,
						min = 4,
						max = 32,
						step = 1,
						get = function() return E.db.actionbar.fontSize end,
						set = function(_, value) E.db.actionbar.fontSize = value end,
					},
					-- Values matched to real ElvUI's own domain exactly
					-- (source/ElvUI-vanilla/ElvUI_Config/
					-- ActionBars.lua:174-185): NONE/OUTLINE/
					-- MONOCHROMEOUTLINE/THICKOUTLINE -- NOT a bare
					-- "MONOCHROME" (an earlier version of this list
					-- had that instead of MONOCHROMEOUTLINE, which
					-- isn't one of real ElvUI's 4 actual choices).
					-- "NONE" (not "") matches the real stored
					-- sentinel -- Modules/ActionBars.lua's ApplyFont()
					-- translates it to "" before calling SetFont.
					fontOutline = {
						type = "select",
						name = L["Font Outline"],
						order = 6,
						values = {
							["NONE"] = L["None"],
							["OUTLINE"] = L["Outline"],
							["MONOCHROMEOUTLINE"] = L["Monochrome Outline"],
							["THICKOUTLINE"] = L["Thick Outline"],
						},
						get = function() return E.db.actionbar.fontOutline end,
						set = function(_, value) E.db.actionbar.fontOutline = value end,
					},
					},
				},
			},
		},
		bar1 = { type = "group", name = L["Bar "]..1, order = 3, args = BarArgs(1) },
		bar2 = { type = "group", name = L["Bar "]..2, order = 4, args = BarArgs(2) },
		bar3 = { type = "group", name = L["Bar "]..3, order = 5, args = BarArgs(3) },
		bar4 = { type = "group", name = L["Bar "]..4, order = 6, args = BarArgs(4) },
		bar5 = { type = "group", name = L["Bar "]..5, order = 7, args = BarArgs(5) },
		-- Nested under "actionbar", NOT a separate top-level
		-- category -- matches real ElvUI's own structure exactly
		-- (source/ElvUI-vanilla/ElvUI_Config/ActionBars.lua:280:
		-- `group["barPet"] = {...}` inside the SAME `group =
		-- E.Options.args.actionbar.args` table as general/bar1-5),
		-- Pet Bar lives under ActionBars, below Bar 5, matching
		-- not just the config UI structure but the real DATA
		-- location too -- see Modules/PetBar.lua's own
		-- header. `enabled` is a live profile field, no
		-- reload-required desc, matching real ElvUI's own
		-- barPet.enabled (unlike the module-wide ActionBars
		-- "Enable" toggle above, which IS private/reload-required).
		barPet = {
			type = "group",
			name = L["Pet Bar"],
			order = 8,
			args = {
				info = {
					type = "header",
					name = L["Pet Bar"],
					order = 1,
				},
				enabled = {
					type = "toggle",
					name = L["Enable"],
					order = 1,
					get = function() return E.db.actionbar.barPet.enabled end,
					set = function(_, value)
						E.db.actionbar.barPet.enabled = value
						E.PetBar:UpdateBar()
					end,
				},
				buttons = {
					type = "range",
					name = L["Buttons"],
					order = 2,
					min = 1,
					max = 10,
					step = 1,
					get = function() return E.db.actionbar.barPet.buttons end,
					set = function(_, value)
						E.db.actionbar.barPet.buttons = value
						E.PetBar:UpdateBar()
					end,
				},
				buttonsPerRow = {
					type = "range",
					name = L["Buttons Per Row"],
					order = 3,
					min = 1,
					max = 10,
					step = 1,
					get = function() return E.db.actionbar.barPet.buttonsPerRow end,
					set = function(_, value)
						E.db.actionbar.barPet.buttonsPerRow = value
						E.PetBar:UpdateBar()
					end,
				},
				buttonsize = {
					type = "range",
					name = L["Button Size"],
					order = 4,
					min = 15,
					max = 60,
					step = 1,
					get = function() return E.db.actionbar.barPet.buttonsize end,
					set = function(_, value)
						E.db.actionbar.barPet.buttonsize = value
						E.PetBar:UpdateBar()
					end,
				},
				buttonspacing = {
					type = "range",
					name = L["Button Spacing"],
					order = 5,
					min = 0,
					max = 20,
					step = 1,
					get = function() return E.db.actionbar.barPet.buttonspacing end,
					set = function(_, value)
						E.db.actionbar.barPet.buttonspacing = value
						E.PetBar:UpdateBar()
					end,
				},
				alpha = {
					type = "range",
					name = L["Alpha"],
					order = 6,
					min = 0,
					max = 1,
					step = 0.05,
					get = function() return E.db.actionbar.barPet.alpha end,
					set = function(_, value)
						E.db.actionbar.barPet.alpha = value
						E.PetBar:UpdateBar()
					end,
				},
				backdrop = {
					type = "toggle",
					name = L["Backdrop"],
					order = 7,
					get = function() return E.db.actionbar.barPet.backdrop end,
					set = function(_, value)
						E.db.actionbar.barPet.backdrop = value
						E.PetBar:UpdateBar()
					end,
				},
				-- Project addition -- real ElvUI's pet bar has no such
				-- toggle at all (always shows empty slots, unconditionally);
				-- see scripts/config-exceptions.lua,
				-- P.actionbar.barPet.showGrid.
				showGrid = {
					type = "toggle",
					name = L["Show Empty Buttons"],
					order = 8,
					get = function() return E.db.actionbar.barPet.showGrid end,
					set = function(_, value)
						E.db.actionbar.barPet.showGrid = value
						E.PetBar:UpdateBar()
					end,
				},
			},
		},
		-- Same nesting/data-location convention as barPet above --
		-- matches real ElvUI's own `E.db.actionbar.barShapeShift`
		-- exactly (source/ElvUI-vanilla/ElvUI/Settings/
		-- Profile.lua:2823). `enabled` is a live profile field
		-- here too, no reload needed.
		-- `stanceBar`, not `barShapeShift`: real ElvUI's own CONFIG key
		-- (ElvUI_Config/ActionBars.lua:408). The DB key it drives stays
		-- `E.db.actionbar.barShapeShift` on both sides.
		stanceBar = {
			type = "group",
			name = L["Stance Bar"],
			order = 9,
			args = {
				info = {
					type = "header",
					name = L["Stance Bar"],
					order = 1,
				},
				enabled = {
					type = "toggle",
					name = L["Enable"],
					order = 1,
					get = function() return E.db.actionbar.barShapeShift.enabled end,
					set = function(_, value)
						E.db.actionbar.barShapeShift.enabled = value
						E.StanceBar:UpdateBar()
					end,
				},
				style = {
					type = "select",
					name = L["Style"],
					desc = L["Not yet implemented on this project -- real ElvUI's own darkenInactive behavior recolors the button's native CheckedTexture, the same kind of call already found tinting gold-wrong on UA elsewhere (see Modules/ActionBars/ActionBars.lua's own StyleButton comment). Currently only the active stance is highlighted, others are left at their native unchecked look, regardless of this setting. Schema-only for now."],
					order = 2,
					values = {
						["darkenInactive"] = L["Darken Inactive"],
						["normal"] = L["Normal"],
					},
					get = function() return E.db.actionbar.barShapeShift.style end,
					set = function(_, value) E.db.actionbar.barShapeShift.style = value end,
				},
				buttons = {
					type = "range",
					name = L["Buttons"],
					order = 3,
					min = 1,
					max = 10,
					step = 1,
					get = function() return E.db.actionbar.barShapeShift.buttons end,
					set = function(_, value)
						E.db.actionbar.barShapeShift.buttons = value
						E.StanceBar:UpdateBar()
					end,
				},
				buttonsPerRow = {
					type = "range",
					name = L["Buttons Per Row"],
					order = 4,
					min = 1,
					max = 10,
					step = 1,
					get = function() return E.db.actionbar.barShapeShift.buttonsPerRow end,
					set = function(_, value)
						E.db.actionbar.barShapeShift.buttonsPerRow = value
						E.StanceBar:UpdateBar()
					end,
				},
				buttonsize = {
					type = "range",
					name = L["Button Size"],
					order = 5,
					min = 15,
					max = 60,
					step = 1,
					get = function() return E.db.actionbar.barShapeShift.buttonsize end,
					set = function(_, value)
						E.db.actionbar.barShapeShift.buttonsize = value
						E.StanceBar:UpdateBar()
					end,
				},
				buttonspacing = {
					type = "range",
					name = L["Button Spacing"],
					order = 6,
					min = 0,
					max = 20,
					step = 1,
					get = function() return E.db.actionbar.barShapeShift.buttonspacing end,
					set = function(_, value)
						E.db.actionbar.barShapeShift.buttonspacing = value
						E.StanceBar:UpdateBar()
					end,
				},
				alpha = {
					type = "range",
					name = L["Alpha"],
					order = 7,
					min = 0,
					max = 1,
					step = 0.05,
					get = function() return E.db.actionbar.barShapeShift.alpha end,
					set = function(_, value)
						E.db.actionbar.barShapeShift.alpha = value
						E.StanceBar:UpdateBar()
					end,
				},
				backdrop = {
					type = "toggle",
					name = L["Backdrop"],
					order = 8,
					get = function() return E.db.actionbar.barShapeShift.backdrop end,
					set = function(_, value)
						E.db.actionbar.barShapeShift.backdrop = value
						E.StanceBar:UpdateBar()
					end,
				},
			},
		},
	},
}
