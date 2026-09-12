local E, L, V, P, G = unpack(ElvUI)

-- "nameplate" category commented out -- the module behind it is a
-- confirmed dead end on this client (native nameplates aren't Lua UI
-- Frames at all here -- see Modules/NamePlates/NamePlates.lua's own
-- top-of-file banner comment for the full investigation). Left in
-- place, commented, rather than deleted -- it can't be turned on, but
-- the config stays visible as commented-out too.
--
-- The key is `nameplate`, SINGULAR: that is real ElvUI's own options
-- arg (its ElvUI_Config/Nameplates.lua:510), even though the DB key on
-- both sides is the plural `nameplates`. Renamed here while it is
-- inert, so re-enabling it lands at the right tree path instead of
-- needing the move later.
--[[
E.Options.args.nameplate = {
	type = "group",
	name = L["NamePlates"],
	order = 9,
	args = {
		intro = {
			type = "description",
			order = 1,
			name = L["First pass -- name/level/health only, colored by unit reaction. Discovers native plates by scanning WorldFrame's children (no per-plate unit token exists on this API vintage) and mutes their native art. Real ElvUI's own per-unit-type (Friendly Player/Enemy Player/NPC/...) health bar sizing, castbar, buffs/debuffs, combo points, and threat coloring are NOT implemented."],
		},
		enable = {
			type = "toggle",
			name = L["Enable"],
			desc = L["Replaces the native nameplate name/level/health display. Requires /reload to take effect."],
			order = 2,
			get = function() return E.private.nameplates.enable end,
			set = function(_, value) E.private.nameplates.enable = value end,
		},
		showLevel = {
			type = "toggle",
			name = L["Show Level"],
			order = 3,
			get = function() return E.db.nameplates.showLevel end,
			set = function(_, value) E.db.nameplates.showLevel = value end,
		},
		showHealthText = {
			type = "toggle",
			name = L["Show Health Percentage"],
			order = 4,
			get = function() return E.db.nameplates.showHealthText end,
			set = function(_, value) E.db.nameplates.showHealthText = value end,
		},
		useTargetScale = {
			type = "toggle",
			name = L["Scale Target Plate"],
			order = 5,
			get = function() return E.db.nameplates.useTargetScale end,
			set = function(_, value) E.db.nameplates.useTargetScale = value end,
		},
		targetScale = {
			type = "range",
			name = L["Target Scale"],
			order = 6,
			min = 1, max = 2, step = 0.05,
			get = function() return E.db.nameplates.targetScale end,
			set = function(_, value) E.db.nameplates.targetScale = value end,
		},
		nonTargetTransparency = {
			type = "range",
			name = L["Non-Target Transparency"],
			order = 7,
			min = 0, max = 1, step = 0.05,
			get = function() return E.db.nameplates.nonTargetTransparency end,
			set = function(_, value) E.db.nameplates.nonTargetTransparency = value end,
		},
	},
}
]]
