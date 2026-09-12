-- Pet's Target unit frame -- mirrors Units/TargetTarget.lua's own
-- construction, same shared UnitFrames.lua Construct_*/Update code.
-- Real unit token `"pettarget"` (`UnitExists("pettarget")` etc.) works
-- as a normal unit, no special casing needed anywhere in the shared
-- code. Real ElvUI's own reference tree has a `PetTarget.lua` in its
-- `Units/` folder too, matching this.

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

-- Settings: `P.unitframe.units.pettarget` (Settings/Profile.lua).

local function Construct_PetTargetFrame()
	local settings = E.db.unitframe.units.pettarget

	local frame = CreateFrame("Button", "ElvUF_PetTarget", UIParent)
	frame:SetWidth(settings.width)
	frame:SetHeight(settings.height)
	-- Beside Pet's own default (-300, -220) -- same vertical position,
	-- to the right, so the two don't default-overlap.
	frame:SetPoint("CENTER", UIParent, "CENTER", -140, -220)
	frame:SetFrameStrata("LOW")
	frame.unit = "pettarget"

	local healthHeight = settings.height
	if settings.power and settings.power.enable then
		healthHeight = settings.height - settings.power.height - 1
	end

	UF:Construct_HealthBar(frame, healthHeight)
	if settings.power and settings.power.enable then
		UF:Construct_PowerBar(frame, settings.power.height)
	end
	UF:Construct_NameText(frame)
	UF:Construct_Portrait(frame, settings.portrait and settings.portrait.width or 24)

	frame.CombatIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
	UF:Construct_Auras(frame, "buff")
	UF:Construct_Auras(frame, "debuff")
	frame.InfoPanel = UF:Construct_InfoPanel(frame)
	UF:Construct_CustomTexts(frame)

	-- No native-frame hide call here, unlike every other Units/*.lua --
	-- Blizzard's default UI has no native "pet's target" frame at all to
	-- hide (unlike PlayerFrame/TargetFrame/PetFrame/TargetFrameToT,
	-- which all exist as real native frames on at least one client).
	UF:EnableUnitMouse(frame)
	E:CreateMover(frame, "ElvUF_PetTarget", "Pet Target Frame")

	return frame
end

UF:RegisterUnit("pettarget", Construct_PetTargetFrame)
