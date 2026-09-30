-- Skins > Blizzard > Mirror Timers -- real ElvUI's MirrorTimers skin
-- (`E.private.skins.blizzard.mirrorTimers`): the native breath/feign-death/
-- exhaustion bars restyled in place at real ElvUI's fixed 222x18, with the
-- same `MirrorTimer<i>Mover` movers.
--
-- The styling itself lives in Core/MirrorTimers.lua, shared with the Mirror
-- Timers module. The module takes precedence: while
-- `E.private.mirrortimers.enable` is on it has already styled the bars at its
-- own configurable size, so this skin stands down.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

local function LoadSkin()
	if E.private.mirrortimers and E.private.mirrortimers.enable then return end
	E:SkinMirrorTimers()
end

S:AddBlizzardSkin("mirrorTimers", LoadSkin)
