local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn

-- Shared `desc` for every per-window skin toggle -- real ElvUI uses one
-- localised string (L["TOGGLESKIN_DESC"]) for all of them rather than repeating
-- a per-window sentence.
local SKIN_DESC = L["Requires /reload to take effect."]

E.Options.args.skins = {
	type = "group",
	name = L["Skins"],
	order = 1,
	childGroups = "tree",
	args = {
		intro = {
			order = 1,
			type = "description",
			name = L["Reskins native Blizzard windows in place -- same frame, same functionality, just restyled to match this UI. Individually toggleable per window."],
		},
		-- `blizzardEnable`, not `enable`: real ElvUI's own key for this master
		-- toggle, so the entry sits at the same place in the tree. It still
		-- writes `E.private.skins.blizzard.enable`, the DB field on both sides.
		blizzardEnable = {
			order = 2,
			type = "toggle",
			name = L["Blizzard"],
			desc = L["Master switch for every Blizzard window skin below. Requires /reload to take effect."],
			get = function() return E.private.skins.blizzard.enable end,
			set = function(_, value)
				E.private.skins.blizzard.enable = value
				E:RequestReload("private")
			end,
		},
		-- Per-window toggles live under their own `blizzard` group, matching
		-- real ElvUI exactly -- ours used to sit one level shallower, directly
		-- under `skins`.
		--
		-- GROUP-LEVEL get/set/disabled, and the children carry none of the
		-- three: each entry's own KEY names the DB field, resolved through
		-- `info[getn(info)]`. That coupling is the point -- a mistyped entry
		-- name becomes a visibly broken control instead of a silently dead
		-- closure. Requires LibConfig-1.0 >= 15 (member inheritance).
		--
		-- The children also carry no `order`, because real ElvUI leaves them
		-- unordered so they sort alphabetically by display name. Requires
		-- LibConfig-1.0 >= 16 (order tie-break on name).
		blizzard = {
			order = 100,
			type = "group",
			name = L["Blizzard"],
			guiInline = true,
			get = function(info) return E.private.skins.blizzard[ info[getn(info)] ] end,
			-- One group-level setter covers all 9 per-window toggles, popup
			-- included. A skin is applied once at S:Initialize and has no
			-- teardown path, so every one of these is genuinely reload-bound.
			set = function(info, value)
				E.private.skins.blizzard[ info[getn(info)] ] = value
				E:RequestReload("private")
			end,
			disabled = function() return not E.private.skins.blizzard.enable end,
			args = {
				-- Display names copied from real ElvUI's own Skins.lua, so the
				-- alphabetical ordering lands identically.
				character = { type = "toggle", name = "Character Frame", desc = SKIN_DESC },
				friends = { type = "toggle", name = "Friends", desc = SKIN_DESC },
				spellbook = { type = "toggle", name = "Spellbook", desc = SKIN_DESC },
				macro = { type = "toggle", name = "Macros", desc = SKIN_DESC },
				binding = { type = "toggle", name = "Key Binding", desc = SKIN_DESC },
				-- Windows real ElvUI-vanilla does not skin at all, so there is no
				-- upstream key to inherit. Its own `BlizzardOptions` looks like a
				-- candidate for the options windows, but is a DEAD flag upstream:
				-- declared and shown in its config, read by nothing.
				mainmenu = { type = "toggle", name = "Main Menu", desc = SKIN_DESC },
				sound = { type = "toggle", name = "Sound Options", desc = SKIN_DESC },
				uioptions = { type = "toggle", name = "Interface Options", desc = SKIN_DESC },
				video = { type = "toggle", name = "Video Options", desc = SKIN_DESC },
				quest = { type = "toggle", name = "Quest Frames", desc = SKIN_DESC },
				gossip = { type = "toggle", name = "Gossip Frame", desc = SKIN_DESC },
				greeting = { type = "toggle", name = "Greeting Frame", desc = SKIN_DESC },
				merchant = { type = "toggle", name = "Merchant", desc = SKIN_DESC },
				taxi = { type = "toggle", name = "Taxi Frame", desc = SKIN_DESC },
				inspect = { type = "toggle", name = "Inspect", desc = SKIN_DESC },
				stable = { type = "toggle", name = "Stable", desc = SKIN_DESC },
				talent = { type = "toggle", name = "Talents", desc = SKIN_DESC },
				tradeskill = { type = "toggle", name = "Tradeskills", desc = SKIN_DESC },
				tooltip = { type = "toggle", name = "Tooltip", desc = SKIN_DESC },
			},
		},
	},
}
