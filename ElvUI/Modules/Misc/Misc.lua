-- Misc module -- the catch-all real ElvUI keeps for small features that
-- don't earn a module of their own (source/ElvUI-vanilla/ElvUI/Modules/
-- Misc/). Ported so far: the solo loot window and the raid marker ring; the
-- rest of that folder's surface (auto repair, interrupt announce, enhanced
-- PvP messages, auto invite, error-frame toggle, forced CVars, AFK screen,
-- chat bubbles, group loot rolls) is not. Each feature is its own file beside
-- Loot.lua, defining one M:Load*() that Initialize below calls -- the same
-- arrangement real ElvUI's own Misc.lua uses.
--
-- Files under Modules/Misc/ do NOT create modules of their own: they attach
-- to this one with E:GetModule("Misc"), the way Modules/Skins/Blizzard/*
-- attaches to Skins. This is real ElvUI's own arrangement, and it matches
-- how these features are configured -- every one of them is a leaf in the
-- shared general config tree, not a category of its own.

local E, L, V, P, G = unpack(ElvUI)
local M = E:NewModule("Misc", "AceEvent-3.0")
E.Misc = M

function M:Initialize()
	self:LoadLoot()
	self:LoadRaidMarker()
end

E:RegisterInitialModule(M:GetName(), function() M:Initialize() end)
