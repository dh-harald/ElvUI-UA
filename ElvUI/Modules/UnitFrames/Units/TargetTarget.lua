-- Target-of-Target unit frame -- mirrors Units/Target.lua's own
-- construction, same shared UnitFrames.lua Construct_*/Update code.
-- Real WoW's `UnitExists("targettarget")`/`UnitHealth
-- ("targettarget")` etc. all work as a normal unit token, no special
-- casing needed anywhere in the shared code for this to just work.

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

-- Settings: `P.unitframe.units.targettarget` (Settings/Profile.lua).

-- Same technique as Units/Player.lua's own HideNativePlayerFrame, for
-- the native TargetFrameToT instead. This frame is a later-expansion
-- addition (didn't exist in real 1.12.1 at all) -- if it's genuinely
-- absent as a global on either client, this just returns immediately,
-- same as every other HideNative* function here when its target frame
-- doesn't exist.
local function HideNativeTargetTargetFrame()
	local frame = TargetFrameToT
	if not frame then return end
	pcall(frame.UnregisterAllEvents, frame)
	pcall(frame.SetScript, frame, "OnEvent", nil)
	pcall(frame.SetScript, frame, "OnUpdate", nil)
	pcall(frame.Hide, frame)
	pcall(frame.SetAlpha, frame, 0)
	frame.Show = E.noop
end

local function Construct_TargetTargetFrame()
	local settings = E.db.unitframe.units.targettarget

	local frame = CreateFrame("Button", "ElvUF_TargetTarget", UIParent)
	frame:SetWidth(settings.width)
	frame:SetHeight(settings.height)
	-- Below Target's own default (100, -150) -- same horizontal side,
	-- lower, so the two don't default-overlap.
	frame:SetPoint("CENTER", UIParent, "CENTER", 100, -220)
	frame:SetFrameStrata("LOW")
	frame.unit = "targettarget"

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
	frame.RaidTargetIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
	-- BOTH aura types, as on every other unit. Only the debuff container used
	-- to be built here, which left `buffs` a dead settings branch on this unit
	-- alone -- UF:UpdateAuras itself is entirely unit-independent.
	UF:Construct_Auras(frame, "buff")
	UF:Construct_Auras(frame, "debuff")
	frame.InfoPanel = UF:Construct_InfoPanel(frame)
	UF:Construct_CustomTexts(frame)

	HideNativeTargetTargetFrame()
	UF:EnableUnitMouse(frame)
	E:CreateMover(frame, "ElvUF_TargetTarget", L["Target of Target Frame"])

	return frame
end

UF:RegisterUnit("targettarget", Construct_TargetTargetFrame)
