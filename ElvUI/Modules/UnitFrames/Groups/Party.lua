-- Party frames -- 4 separate unit frames (party1..party4), NOT a secure
-- group header (real ElvUI's own Groups/Party.lua wraps oUF:SpawnHeader,
-- a SecureGroupHeaderTemplate-driven system that dynamically spawns/
-- despawns frames as party membership changes -- since oUF is gone, and
-- this project's other frames aren't secure-templated either, that
-- whole mechanism is skipped in favor of 4 always-existing frames that
-- simply Hide() via the existing UnitExists check when a slot is empty,
-- matching this module's own established "custom, not oUF" approach).
--
-- First real use of `frame.unitDBKey` (UnitFrames.lua) -- real ElvUI's
-- own schema configures every party member UNIFORMLY
-- (`E.db.unitframe.units.party`, ONE table, not `.party1`.."party4"
-- separately, confirmed via ElvUI-vanilla/ElvUI_Config/
-- UnitFrames.lua's `GetOptionsTable_Portrait(..., "party")` call) --
-- but each frame still needs its OWN distinct unit token (`party1`
-- .."party4") to read its own live unit data. `frame.unit` stays the
-- real per-slot token; `frame.unitDBKey = "party"` is the shared
-- settings lookup key.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local UF = E.UnitFrames

-- Settings: `P.unitframe.units.party` (Settings/Profile.lua) -- ONE shared
-- table for all 4 members, not `.party1`..`.party4`.

-- Vertical spacing between stacked party member frames.
local PARTY_GAP = 6

local nativeHidden = {}

-- Same technique as Units/Player.lua's own HideNativePlayerFrame, for
-- one native PartyMemberFrame<index>.
local function HideNativePartyFrame(index)
	local frame = _G["PartyMemberFrame"..index]
	if not frame then return end
	nativeHidden[index] = true
	pcall(frame.UnregisterAllEvents, frame)
	pcall(frame.SetScript, frame, "OnEvent", nil)
	pcall(frame.SetScript, frame, "OnUpdate", nil)
	pcall(frame.Hide, frame)
	pcall(frame.SetAlpha, frame, 0)
	frame.Show = E.noop
end

-- Unreal Azeroth shows the native party frames again from outside Lua (a
-- member going offline does it, with no event left registered on the frame
-- and Show replaced), and its SetAlpha(0) does not carry over to the children:
-- the name, portrait, leader icon and bar borders reappear. Hide() on the root
-- does take the children along, so a watcher re-hides any of the ones this
-- module replaced that is shown.
local nativeWatcher = CreateFrame("Frame")
local nativeElapsed = 0
nativeWatcher:SetScript("OnUpdate", function()
	nativeElapsed = nativeElapsed + arg1
	if nativeElapsed < 0.2 then return end
	nativeElapsed = 0
	local i
	for i = 1, 4 do
		local native = nativeHidden[i] and _G["PartyMemberFrame"..i]
		if native and native:IsShown() then native:Hide() end
	end
end)

-- Returns a Construct function bound to one party slot (1-4) -- each
-- slot's own frame is fully independent (own health/power/name/
-- portrait/combat icon, own mover), only the SETTINGS are shared.
local function Construct_PartyMemberFrame(index)
	return function()
		local settings = E.db.unitframe.units.party

		local frame = CreateFrame("Button", "ElvUF_Party"..index, UIParent)
		frame:SetWidth(settings.width)
		frame:SetHeight(settings.height)
		-- Vertical stack, top-left area of the screen (clear of Player/
		-- Target/Pet/TargetTarget/PetTarget's own default positions,
		-- which all sit lower/more central).
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -220 - (index - 1) * (settings.height + PARTY_GAP))
		frame:SetFrameStrata("LOW")
		frame.unit = "party"..index
		frame.unitDBKey = "party"

		local healthHeight = settings.height
		if settings.power and settings.power.enable then
			healthHeight = settings.height - settings.power.height - 1
		end

		UF:Construct_HealthBar(frame, healthHeight)
		if settings.power and settings.power.enable then
			UF:Construct_PowerBar(frame, settings.power.height)
		end
		UF:Construct_NameText(frame)
		UF:Construct_Portrait(frame, settings.portrait and settings.portrait.width or 28)

		frame.CombatIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
		frame.RaidTargetIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
		frame.ResurrectIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
		UF:Construct_Auras(frame, "buff")
		UF:Construct_Auras(frame, "debuff")

		UF:EnableUnitMouse(frame)
		HideNativePartyFrame(index)
		E:CreateMover(frame, "ElvUF_Party"..index, string.format(L["Party %d Frame"], index))

		return frame
	end
end

UF:RegisterUnit("party1", Construct_PartyMemberFrame(1))
UF:RegisterUnit("party2", Construct_PartyMemberFrame(2))
UF:RegisterUnit("party3", Construct_PartyMemberFrame(3))
UF:RegisterUnit("party4", Construct_PartyMemberFrame(4))
