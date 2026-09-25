-- Global defaults -- `G` (Engine[5]), stored in `ElvDB.global`: one shared
-- copy per ACCOUNT, outside the profile system entirely.
--
-- THE ONE AND ONLY place a `G.*` key may be declared -- see Profile.lua's
-- header for why defaults live centrally rather than next to their
-- consumers.
--
-- This is also where anything that is NOT profile data belongs: UI state
-- and one-shot bookkeeping markers must stay out of `E.db`, which is the
-- table meant to remain format-compatible with a real ElvUI profile.

local E, L, V, P, G = unpack(ElvUI)

G.general = {
	smallerWorldMap = true,
	WorldMapCoordinates = {
		enable = true,
		position = "BOTTOMLEFT",
		xOffset = 0,
		yOffset = 0,
	},
}

-- One-shot migration markers for the standalone Auras module -- see
-- `A:MigrateAuraFields`. Global rather than per-profile because a marker key
-- in `E.db` would be exactly the kind of invented field that breaks real
-- profile compatibility.
G.auras = {
	gridDefaultsCorrected = false,
}

-- Mail module (`Modules/Mail/`): bulk inbox handling and multi-item sending
-- on the native mailbox. Global rather than profile because real ElvUI has
-- no such module and `E.db` has to stay real-profile compatible.
--
-- `enable` also decides which look the mailbox gets, in the direction that
-- is easy to get backwards: with the module ON the window is ALWAYS skinned,
-- because the module draws its own controls in this UI's style and pulls the
-- skin in itself (`Modules/Skins/Blizzard/Mail.lua`, `S:ApplyMailSkin`).
-- The per-window skin toggle therefore only decides anything while the
-- module is off, and the options tree disables it accordingly.
--
-- `expiryWarning`, `moneySummary` and `express` are read fresh on the next
-- inbox refresh, bulk run and row click, so none of them needs a reload.
-- `express` is a toggle rather than always-on because Ctrl-clicking a row
-- sends that mail away with no confirmation and no undo.
G.mail = {
	enable = true,
	expiryWarning = true,
	moneySummary = true,
	express = true,
	cleanEmptied = true,
	autoComplete = true,
}

-- Saved position of the `/moveui` control panel. Project-only UI state,
-- filled at runtime by Core/Movers.lua.
G.moverPanel = {}

-- Arrow-key bindings removed while `/moveui` is open on Unreal Azeroth, keyed
-- by chord, so they are rebound even after a /reload inside move mode.
-- Project-only UI state, filled and emptied at runtime by Core/Movers.lua.
G.moverBindings = {}

-- Whether the Lua error window (Core/DebugTools.lua) opens by itself on a new
-- error; errors are recorded either way. Toggled with "/elvui errors on|off".
-- Project-only UI state, so global rather than profile.
G.debugTools = {
	autoOpen = true,
}
