-- Target unit frame -- mirrors Units/Player.lua's own construction
-- almost exactly, built on the same UnitFrames.lua shared Construct_*
-- helpers. Shares the SAME shared-code paths
-- Player uses for update/color/text resolution (UnitFrames.lua's
-- ResolveHealthColor/UpdateFrame etc. read `E.db.unitframe.units[unit]`
-- generically, not a hardcoded `.player`, specifically so this file
-- didn't need its own copy of that logic -- see UnitFrames.lua's own
-- comments on that generalization).

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

-- Settings: `P.unitframe.units.target` (Settings/Profile.lua).

-- Same technique as Units/Player.lua's own HideNativePlayerFrame, for
-- the native TargetFrame instead.
local function HideNativeTargetFrame()
	local frame = TargetFrame
	if not frame then return end
	pcall(frame.UnregisterAllEvents, frame)
	pcall(frame.SetScript, frame, "OnEvent", nil)
	pcall(frame.SetScript, frame, "OnUpdate", nil)
	pcall(frame.Hide, frame)
	pcall(frame.SetAlpha, frame, 0)
	frame.Show = E.noop
end

local function Construct_TargetFrame()
	local settings = E.db.unitframe.units.target

	local frame = CreateFrame("Button", "ElvUF_Target", UIParent)
	frame:SetWidth(settings.width)
	frame:SetHeight(settings.height)
	-- Mirrored to the right of Player's own default (-300, -150) --
	-- same vertical position, opposite horizontal side, so the two
	-- don't default-overlap.
	frame:SetPoint("CENTER", UIParent, "CENTER", 300, -150)
	frame:SetFrameStrata("LOW")
	frame.unit = "target"

	local healthHeight = settings.height
	if settings.power and settings.power.enable then
		healthHeight = settings.height - settings.power.height - 1
	end

	UF:Construct_HealthBar(frame, healthHeight)
	if settings.power and settings.power.enable then
		UF:Construct_PowerBar(frame, settings.power.height)
	end
	UF:Construct_NameText(frame)
	UF:Construct_Portrait(frame, settings.portrait and settings.portrait.width or 40)

	-- No RestingIndicator -- `IsResting()` takes no unit argument, so rest
	-- state is a player-only concept (see Settings/Profile.lua's per-unit
	-- notes).
	frame.CombatIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
	frame.RaidTargetIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
	UF:Construct_Auras(frame, "buff")
	UF:Construct_Auras(frame, "debuff")
	frame.InfoPanel = UF:Construct_InfoPanel(frame)
	UF:Construct_CustomTexts(frame)

	HideNativeTargetFrame()
	UF:EnableUnitMouse(frame)
	E:CreateMover(frame, "ElvUF_Target", L["Target Frame"])

	return frame
end

UF:RegisterUnit("target", Construct_TargetFrame)
