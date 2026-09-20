local E, L, V, P, G = unpack(ElvUI)

-- Buffs/Debuffs args for the STANDALONE "Auras" module only -- a separate
-- helper from `AuraArgs` above because the two use genuinely
-- different real-ElvUI vocabularies, and mixing them is exactly what went
-- wrong before: `AuraArgs`' `perrow`/`xOffset`/`yOffset` are the correct
-- real names for `P.unitframe.units.X.buffs`, but the standalone module's
-- own `P["auras"].buffs` uses `wrapAfter`/`maxWraps`/`horizontalSpacing`/
-- `verticalSpacing` (verified against
-- ElvUI-vanilla/ElvUI/Settings/Profile.lua:504-536 and its own
-- ElvUI_Config/Auras.lua). Ranges/labels/descs follow real ElvUI's own
-- Auras config file.
--
-- `growthDirection` and `seperateOwn` are intentionally absent: both are
-- stored in the DB for profile round-tripping but not read by this
-- project's layout code yet, and a control that visibly does nothing is
-- worse than no control (see Modules/Auras/Auras.lua's own note).
local function StandaloneAuraArgs(getTable, order, label)
	return {
		-- Real ElvUI opens both the buffs and the debuffs group with a header.
		header = {
			type = "header",
			name = label,
			order = 1,
		},
		size = {
			type = "range",
			name = L["Size"],
			desc = L["Set the size of the individual auras."],
			order = order + 1,
			min = 16, max = 60, step = 2,
			get = function() return getTable().size end,
			set = function(_, value) getTable().size = value end,
		},
		wrapAfter = {
			type = "range",
			name = L["Wrap After"],
			desc = L["Begin a new row after this many auras."],
			order = order + 2,
			min = 1, max = 32, step = 1,
			get = function() return getTable().wrapAfter end,
			set = function(_, value) getTable().wrapAfter = value end,
		},
		maxWraps = {
			type = "range",
			name = L["Max Wraps"],
			desc = L["Limit the number of rows. Wrap After x Max Wraps is the most auras this display will ever show -- and the area the /moveui handle outlines."],
			order = order + 3,
			min = 1, max = 32, step = 1,
			get = function() return getTable().maxWraps end,
			set = function(_, value) getTable().maxWraps = value end,
		},
		horizontalSpacing = {
			type = "range",
			name = L["Horizontal Spacing"],
			order = order + 4,
			min = 0, max = 50, step = 1,
			get = function() return getTable().horizontalSpacing end,
			set = function(_, value) getTable().horizontalSpacing = value end,
		},
		verticalSpacing = {
			type = "range",
			name = L["Vertical Spacing"],
			desc = L["Larger than you might expect by default (16) because the duration text hangs below each icon."],
			order = order + 5,
			min = 0, max = 50, step = 1,
			get = function() return getTable().verticalSpacing end,
			set = function(_, value) getTable().verticalSpacing = value end,
		},
	}
end

-- Adds sortMethod/sortDir into an existing args table (mutates and
-- returns it) -- only the standalone "Auras" category's Buffs/Debuffs
-- tabs use this, NOT the per-unit UnitFrames tabs (Target/Pet/etc's own
-- debuff grid has no equivalent real ElvUI sort concept for a single
-- attached icon row -- see Modules/Auras/Auras.lua's own header comment
-- on this scope split). Real ElvUI field names/values verbatim
-- ("INDEX"/"TIME", "+"/"-") -- NO "NAME" (no cheap name lookup for the
-- player's own buffs) or seperateOwn (meaningless for a single-caster
-- list) -- see that file's own comment for the full reasoning.
local function AuraSortArgs(args, getTable, order)
	args.sortMethod = {
		type = "select",
		name = L["Sort Method"],
		order = order,
		values = {
			["INDEX"] = L["Index"],
			["TIME"] = L["Time Remaining"],
		},
		get = function() return getTable().sortMethod end,
		set = function(_, value) getTable().sortMethod = value end,
	}
	args.sortDir = {
		type = "select",
		name = L["Sort Direction"],
		order = order + 1,
		values = {
			["+"] = L["Ascending"],
			["-"] = L["Descending"],
		},
		get = function() return getTable().sortDir end,
		set = function(_, value) getTable().sortDir = value end,
	}
	return args
end

E.Options.args.auras = {
	type = "group",
	name = L["Auras"],
	order = 8,
	childGroups = "tab",
	args = {
		intro = {
			order = 1,
			type = "description",
			name = L["Player buffs and debuffs, shown next to the minimap instead of Blizzard's own BuffFrame."],
		},
		-- Real ElvUI keeps this toggle at the SECTION root, not inside
		-- `general`. It also has a separate `disableBlizzard` next to it;
		-- ours is collapsed into this one flag (see
		-- scripts/config-exceptions.lua).
		enable = {
			type = "toggle",
			name = L["Enable"],
			desc = L["Also disables the native Blizzard buff/debuff frame -- there's no separate toggle for that, matching every other module in this addon (ActionBars, Minimap, etc.): enabling our own replacement always hides the original. Requires /reload to take effect."],
			order = 2,
			get = function() return E.private.auras.enable end,
			set = function(_, value)
				E.private.auras.enable = value
				E:RequestReload("private")
			end,
		},
		general = {
			type = "group",
			name = L["General"],
			order = 1,
			args = {
				intro = {
					type = "description",
					order = 1,
					name = L["The player's own buff/debuff display, in the ORIGINAL Blizzard buff-frame location (near the minimap) -- separate from the small icon grid attached directly to the Player unit frame under UnitFrames > Player > Buffs/Debuffs. Matches real ElvUI's own separate 'Auras' module, which runs both at once."],
				},
				fadeThreshold = {
					type = "range",
					name = L["Fade Threshold"],
					desc = L["Seconds remaining before the countdown text switches to the Expiring color and decimal form, and the icon starts flashing. Set to -1 to disable both. Real ElvUI field name: auras.fadeThreshold."],
					order = 3,
					min = -1, max = 30, step = 1,
					get = function() return E.db.auras.fadeThreshold end,
					set = function(_, value) E.db.auras.fadeThreshold = value end,
				},
				-- The 5 aura text colors that used to sit here were
				-- REMOVED: real ElvUI has no such
				-- setting at all -- its aura text colors are the
				-- hardcoded `E.TimeColors`, which this project now
				-- mirrors in Core/Util.lua. See
				-- Modules/Auras/Auras.lua's own defaults block.
				-- Duration FORMAT (30m vs 30:00) is configured
				-- under General > Cooldown Text and applies to both
				-- displays.
				-- Real ElvUI field names verbatim (P["auras"],
				-- Settings/Profile.lua:509-512). Its sibling
				-- font/fontSize/fontOutline fields are stored in the
				-- DB for profile round-tripping but deliberately NOT
				-- exposed here: SetFont is a confirmed no-op on UA,
				-- so they would be dead controls.
				timeXOffset = {
					type = "range",
					name = L["Time X Offset"],
					desc = L["Horizontal offset of the duration text, relative to its default spot under the icon."],
					order = 9,
					min = -30, max = 30, step = 1,
					get = function() return E.db.auras.timeXOffset end,
					set = function(_, value) E.db.auras.timeXOffset = value end,
				},
				timeYOffset = {
					type = "range",
					name = L["Time Y Offset"],
					order = 10,
					min = -30, max = 30, step = 1,
					get = function() return E.db.auras.timeYOffset end,
					set = function(_, value) E.db.auras.timeYOffset = value end,
				},
				countXOffset = {
					type = "range",
					name = L["Count X Offset"],
					desc = L["Horizontal offset of the stack-count text."],
					order = 11,
					min = -30, max = 30, step = 1,
					get = function() return E.db.auras.countXOffset end,
					set = function(_, value) E.db.auras.countXOffset = value end,
				},
				countYOffset = {
					type = "range",
					name = L["Count Y Offset"],
					order = 12,
					min = -30, max = 30, step = 1,
					get = function() return E.db.auras.countYOffset end,
					set = function(_, value) E.db.auras.countYOffset = value end,
				},
			},
		},
		buffs = {
			type = "group",
			name = L["Buffs"],
			order = 2,
			args = AuraSortArgs(StandaloneAuraArgs(function() return E.db.auras.buffs end, 1, L["Buffs"]), function() return E.db.auras.buffs end, 10),
		},
		debuffs = {
			type = "group",
			name = L["Debuffs"],
			order = 3,
			args = AuraSortArgs(StandaloneAuraArgs(function() return E.db.auras.debuffs end, 1, L["Debuffs"]), function() return E.db.auras.debuffs end, 10),
		},
	},
}
