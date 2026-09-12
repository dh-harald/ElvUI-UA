-- Pet unit frame -- mirrors Units/Target.lua's own construction (which
-- itself mirrors Units/Player.lua), same shared UnitFrames.lua
-- Construct_*/Update code, no per-unit copy of that logic needed.

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

-- Settings: `P.unitframe.units.pet` (Settings/Profile.lua).

-- Same technique as Units/Player.lua's own HideNativePlayerFrame, for
-- the native PetFrame instead.
local function HideNativePetFrame()
	local frame = PetFrame
	if not frame then return end
	pcall(frame.UnregisterAllEvents, frame)
	pcall(frame.SetScript, frame, "OnEvent", nil)
	pcall(frame.SetScript, frame, "OnUpdate", nil)
	pcall(frame.Hide, frame)
	pcall(frame.SetAlpha, frame, 0)
	frame.Show = E.noop
end

local function Construct_PetFrame()
	local settings = E.db.unitframe.units.pet

	local frame = CreateFrame("Button", "ElvUF_Pet", UIParent)
	frame:SetWidth(settings.width)
	frame:SetHeight(settings.height)
	-- Below Player's own default (-300, -150) -- same horizontal side,
	-- lower, so the two don't default-overlap.
	frame:SetPoint("CENTER", UIParent, "CENTER", -300, -220)
	frame:SetFrameStrata("LOW")
	frame.unit = "pet"

	local healthHeight = settings.height
	if settings.power and settings.power.enable then
		healthHeight = settings.height - settings.power.height - 1
	end

	UF:Construct_HealthBar(frame, healthHeight)
	if settings.power and settings.power.enable then
		UF:Construct_PowerBar(frame, settings.power.height)
	end
	UF:Construct_NameText(frame)
	UF:Construct_Portrait(frame, settings.portrait and settings.portrait.width or 32)

	frame.CombatIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
	UF:Construct_Auras(frame, "buff")
	UF:Construct_Auras(frame, "debuff")
	frame.InfoPanel = UF:Construct_InfoPanel(frame)
	UF:Construct_CustomTexts(frame)
	UF:Construct_Happiness(frame)

	HideNativePetFrame()
	UF:EnableUnitMouse(frame)
	E:CreateMover(frame, "ElvUF_Pet", "Pet Frame")

	return frame
end

UF:RegisterUnit("pet", Construct_PetFrame)
