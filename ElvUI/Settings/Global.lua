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

-- Saved position of the `/moveui` control panel. Project-only UI state,
-- filled at runtime by Core/Movers.lua.
G.moverPanel = {}

-- Whether the Lua error window (Core/DebugTools.lua) opens by itself on a new
-- error; errors are recorded either way. Toggled with "/elvui errors on|off".
-- Project-only UI state, so global rather than profile.
G.debugTools = {
	autoOpen = true,
}
