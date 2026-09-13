-- Private defaults -- `V` (Engine[3]), stored in `ElvPrivateDB` per
-- CHARACTER, independent of the selected profile. Reload-required by
-- nature: every consumer reads `E.private.*` once at initialize time, and
-- nothing here is re-applied live.
--
-- THE ONE AND ONLY place a `V.*` key may be declared -- see Profile.lua's
-- header for why defaults live centrally rather than next to their
-- consumers.

local E, L, V, P, G = unpack(ElvUI)

-- `normTex` / `glossTex` are real ElvUI's TWO shared statusbar textures,
-- resolved once at OnInitialize into `E.media.normTex` / `E.media.glossTex`
-- (Init.lua, matching real ElvUI's own Core/core.lua:220-221). Anything
-- without its OWN more specific override reads them directly:
-- `unitframe.statusbar` and `nameplates.statusbar` are the only two
-- PROFILE-level per-feature overrides real ElvUI has, everything else
-- funnels through these.
--
-- Both keep real ElvUI's own "ElvUI Norm" default. That entry points at a
-- custom addon-shipped file (Media/Textures/normTex2), and custom
-- addon-shipped textures DO render on UA as long as the path's character case
-- matches the file exactly -- a mis-cased path is the silent UA-only failure
-- that was once mistaken for "custom textures don't render there". See
-- docs/api-diffs/media.md.
--
-- `glossTex` is additionally what `E:SetTemplate`'s third argument switches a
-- backdrop's `bgFile` over to, and where every action-button backdrop's subtle
-- top-to-bottom falloff comes from (Core/Util.lua's `CreateButtonBorder`).
--
-- `zoomLevel` is a project addition -- persisted minimap zoom.
V.general = {
	normTex = "ElvUI Norm",
	glossTex = "ElvUI Norm",
	loot = true,
	lootUnderMouse = false,
	minimap = {
		enable = true,
		hideCalendar = true,
		zoomLevel = 0,
	},
}

-- `installComplete` and `theme` are DELIBERATELY NOT DECLARED, matching real
-- ElvUI, which writes `E.private.install_complete` and `E.private.theme` from
-- Core/install.lua and declares neither.
--
-- `installComplete` is set once the wizard's own "Finished" button is clicked
-- and read once at RegisterInitialModule time to decide whether to auto-open
-- the wizard on login; `nil` is falsy there, which is exactly the "not yet
-- installed" answer a fresh profile needs. ReloadUI() always follows that
-- write, so the next login's read is never stale. Waived in
-- scripts/config-exceptions.lua's `reads` table.
--
-- `theme` records which Theme button `E:SetupTheme` last applied. Nothing reads
-- it back out, so a default would be pure noise against the real schema.

V.actionbar = { enable = true }

-- Single enable flag, no separate `disableBlizzard` toggle. Real ElvUI has
-- both, but nothing else in this project splits them (ActionBars'
-- `V.actionbar.enable` alone gates BOTH building the replacement and
-- hiding the native chrome), and two flags only invites "enabled but
-- Blizzard's still showing too".
V.auras = { enable = true }

V.bags = {
	enable = true,
	bagBar = false,
}

V.chat = { enable = true }

V.cooldown = { enable = true }

-- Real ElvUI has no top-level `mirrortimers` -- there the feature is a skin
-- flag (`V.skins.blizzard.mirrorTimers`). Project extension, whitelisted in
-- scripts/config-exceptions.lua.
V.mirrortimers = { enable = true }

-- Default `false` matches the module's permanently disabled state; the flag
-- no longer gates anything, NP:Initialize() hard-disables regardless.
V.nameplates = { enable = false }

V.tooltip = { enable = true }

-- A master enable plus one flag per skinned window, matching real ElvUI's
-- own `E.private.skins.blizzard.*` layout and config grouping.
V.skins = {
	blizzard = {
		enable = true,
		character = true,
		friends = true,
		spellbook = true,
		macro = true,
		mainmenu = true,
		sound = true,
		uioptions = true,
		video = true,
		binding = true,
		quest = true,
		gossip = true,
		greeting = true,
		merchant = true,
		trade = true,
		taxi = true,
		inspect = true,
		stable = true,
		talent = true,
		tradeskill = true,
		tooltip = true,
	},
}
