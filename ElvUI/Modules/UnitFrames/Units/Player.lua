-- Player unit frame -- the first (and so far only) unit built on top of
-- UnitFrames.lua's shared Construct_* helpers. See that file's own header
-- comment for the overall architecture and what this pass does/doesn't
-- cover.

local E, L, V, P, G = unpack(ElvUI)
local UF = E.UnitFrames

-- Settings: `P.unitframe.units.player` (Settings/Profile.lua).
-- `health.text_format`/`power.text_format`/`name.text_format` go through
-- UnitFrames.lua's own small tag substitution engine (NOT real ElvUI's tag
-- DSL) -- see that file's header comment for the exact tag list.
-- `orientation` is stored for schema fidelity but not read. `portrait.*` is
-- read by the per-client portrait files (PortraitUA.lua/PortraitLegacy.lua).

-- Hides the native PlayerFrame the same way ActionBars.lua's own
-- HideFrame() hides Blizzard chrome: UnregisterAllEvents (harmless even
-- though it's a confirmed no-op on UA) + nil the OnEvent/OnUpdate handlers (the CONFIRMED
-- working substitute on UA) + Hide() + a permanent Show=noop override so
-- nothing can bring it back later.
local function HideNativePlayerFrame()
	local frame = PlayerFrame
	if not frame then return end
	pcall(frame.UnregisterAllEvents, frame)
	pcall(frame.SetScript, frame, "OnEvent", nil)
	pcall(frame.SetScript, frame, "OnUpdate", nil)
	pcall(frame.Hide, frame)
	pcall(frame.SetAlpha, frame, 0)
	frame.Show = E.noop
end

-- Native BuffFrame/TemporaryEnchantFrame killing moved to the separate
-- Modules/Auras/Auras.lua module -- matches real ElvUI's
-- own module boundary (its Auras module owns hiding the native frame,
-- not UnitFrames) now that a genuinely standalone player-buff/debuff
-- display exists there. See that file's own header comment.

local function Construct_PlayerFrame()
	local settings = E.db.unitframe.units.player

	local frame = CreateFrame("Button", "ElvUF_Player", UIParent)
	frame:SetWidth(settings.width)
	frame:SetHeight(settings.height)
	frame:SetPoint("CENTER", UIParent, "CENTER", -300, -150)
	frame:SetFrameStrata("LOW")
	frame.unit = "player"

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

	-- Parented to Health's own raised text layer, NOT `frame` directly --
	-- see Construct_StateIcon's own comment (UnitFrames.lua) for why a
	-- texture on `frame` itself would render behind the health/power
	-- bars.
	frame.RestingIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
	frame.CombatIndicator = UF:Construct_StateIcon(frame.Health.textLayer)
	UF:Construct_Auras(frame, "buff")
	UF:Construct_Auras(frame, "debuff")
	frame.InfoPanel = UF:Construct_InfoPanel(frame)
	UF:Construct_CustomTexts(frame)

	local castSettings = E.db.unitframe.units.player.castbar
	if castSettings.enable then
		local castbar = UF:Construct_Castbar(frame)
		castbar:SetWidth(castSettings.width)
		castbar:SetHeight(castSettings.height)
		-- Independent of Player Frame's own position (only a starting
		-- point -- E:CreateMover below captures this as its reset
		-- default, then owns the bar's actual position from here on,
		-- same convention as every other mover in this project): real
		-- ElvUI does NOT glue the castbar directly to
		-- the bottom of the Player Frame, it sits on its own,
		-- screen-center-ish, roughly between where Player and Target
		-- frames are. Previously anchored to `frame`'s own bottom edge.
		castbar:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
		E:CreateMover(castbar, "ElvUF_PlayerCastbar", "Player Castbar")
		UF:InitializeCastbar()
	end

	UF:EnableUnitMouse(frame)
	HideNativePlayerFrame()
	E:CreateMover(frame, "ElvUF_Player", "Player Frame")

	return frame
end

UF:RegisterUnit("player", Construct_PlayerFrame)
