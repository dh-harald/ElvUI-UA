-- XP Bar -- the "Experience" sub-feature of real ElvUI's DataBars module
-- (source/ElvUI-vanilla/ElvUI/Modules/DataBars/Experience.lua). Named
-- XPBar.lua rather than Experience.lua, but the module OBJECT is the
-- shared `E.DataBars` from DataBars.lua in this same folder, matching
-- real ElvUI's actual structure (both files extend the same module).
--
-- BUG THIS FIXES: when Modules/ActionBars.lua's chrome-hiding was
-- written, `MainMenuExpBar` (the native XP bar) and `ExhaustionTick`
-- (its rested-XP tick mark) were added to that module's generic
-- CHROME_TO_HIDE list and hidden with no replacement -- appropriate for
-- chrome that's genuinely just clutter (the default bar's art frame,
-- the stance bar, ...), but wrong for the XP bar specifically, which
-- real ElvUI replaces with its own styled bar rather than just deleting.
-- Both names are REMOVED from ActionBars.lua's CHROME_TO_HIDE (this
-- module now owns hiding them, right before building its own
-- replacement) -- see Modules/ActionBars.lua's own note at that spot.
--
-- Construction technique (the backdrop-anchor + inset-StatusBar shape,
-- built via DataBars.lua's own M:CreateBar) is UnrealUI's, not real
-- ElvUI's, matching its own proven-on-UA xpbar.lua (source/UnrealUI/
-- modules/xpbar.lua). Real ElvUI's own construction (E:CreateBar in its
-- DataBars.lua) needs E:SetInside/E:RegisterStatusBar/E.UIParent/
-- E.media.normTex -- a Skins-module infrastructure this project doesn't
-- have (same gap already noted for WorldMap/ActionBars). Of that set only
-- E:SetTemplate exists here (Core/Util.lua); this bar predates it and is
-- not worth re-plumbing for one backdrop.
--
-- EVERYTHING ELSE -- field names, the event list, the tooltip, the 7
-- text-format modes, the settings themselves -- comes from real ElvUI
-- instead.
--
-- Settings: `P.databars.experience` (Settings/Profile.lua). Real ElvUI
-- defaults this bar to a thin VERTICAL 10x180 anchored beside its own
-- LeftChatPanel; here it is a horizontal 200x14 placed by the mover system
-- (E:CreateMover, drag/nudge via /moveui) -- the deviation and the rest are
-- listed there.

local E, L, V, P, G = unpack(ElvUI)
local M = E.DataBars

-- The "hide once, then permanently neuter Show()" recipe lives in
-- DataBars.lua's own M:HideNativeFrame, shared with ReputationBar.lua's
-- identical need for the native reputation watch bar -- one shared
-- implementation instead of two drifting copies. The shared version also
-- tolerates being handed a Texture/FontString rather than a Frame.
local function HideNativeFrame(frame)
	M:HideNativeFrame(frame)
end

function M:ExperienceBar_OnEnter()
	local settings = self.db.experience
	if settings.mouseover then
		-- M:SetBarAlpha, not a bare bar:SetAlpha -- alpha does not cascade
		-- to child frames on UA, see DataBars.lua's own comment there.
		M:SetBarAlpha(self.expBar, 1)
	end

	local cur = tonumber(UnitXP("player")) or 0
	local max = tonumber(UnitXPMax("player")) or 0
	if max <= 0 then max = 1 end

	local rested = 0
	if type(GetXPExhaustion) == "function" then
		local ok, value = pcall(GetXPExhaustion)
		if ok then rested = tonumber(value) or 0 end
	end

	GameTooltip:SetOwner(self.expBar, "ANCHOR_CURSOR", 0, -4)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(L["Experience"])
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["XP:"], string.format("%d / %d (%d%%)", cur, max, cur / max * 100), 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Remaining:"], string.format("%d (%d%%)", max - cur, (max - cur) / max * 100), 1, 1, 1)
	if rested > 0 then
		GameTooltip:AddDoubleLine(L["Rested:"], string.format("+%d (%d%%)", rested, rested / max * 100), 1, 1, 1)
	end
	GameTooltip:Show()
end

function M:ExperienceBar_OnLeave()
	local settings = self.db.experience
	if settings.mouseover then
		M:SetBarAlpha(self.expBar, 0)
	end
	GameTooltip:Hide()
end

-- Matches real ElvUI's own UpdateExperience (Experience.lua)
-- format-mode-for-format-mode, `E:ShortValue` included -- an earlier version
-- here used a plain "%d" and reasoned that the helper was "not worth porting:
-- 1.12.1's XP values are always small". Both halves were wrong: per-level XP
-- reaches ~200k near the cap, and the helper now exists (Core/Util.lua) for the
-- unit frames anyway. BOTH branches below (rested and not) abbreviate, so the
-- text does not change shape the moment rested XP runs out.
function M:UpdateExperience()
	local bar = self.expBar
	if not bar then return end

	local settings = self.db.experience
	if not settings.enable then
		bar:Hide()
		return
	end

-- Not in real ElvUI's own UpdateExperience despite the setting existing
	-- there (source/ElvUI-vanilla/ElvUI_Config/DataBars.lua wires up a
	-- "Hide in Combat" toggle that calls UpdateExperience() on change, but
	-- the real UpdateExperience never actually checks it -- a real
	-- incompleteness in the reference, not a deliberate feature).
	-- Implemented properly here instead, since the point of exposing a
	-- setting is for it to work.
	if settings.hideInCombat and UnitAffectingCombat("player") then
		bar:Hide()
		return
	end

	local cur = tonumber(UnitXP("player")) or 0
	local max = tonumber(UnitXPMax("player")) or 0

	-- UnitXPMax reports 0 once there's no more XP to track -- used here
	-- as the actual "nothing to show" signal, INSTEAD of real ElvUI's
	-- own hardcoded `UnitLevel("player") == 60` check
	-- (Experience.lua:27,133). A fixed level-cap constant is a worse
	-- signal for a project that doesn't get to assume every server caps
	-- at exactly 60 -- max<=0 already means "no more XP to gain," which
	-- is exactly what hideAtMaxLevel is meant to catch, with no
	-- assumption about what the cap actually is. Confirmed as the right
	-- signal by UnrealUI's own xpbar.lua (source/UnrealUI/modules/
	-- xpbar.lua:181-185), which uses the identical check.
	-- STAY VISIBLE WHILE /moveui IS UNLOCKED: Core/Movers.lua parents a
	-- mover's drag HANDLE as a CHILD of the frame it moves, so a
	-- self-hiding frame takes its own handle down with it and can't be
	-- positioned. This only bites a max-level character, where this bar
	-- is hidden permanently and so could never be repositioned at all --
	-- same fix and reasoning as the Reputation bar's own equivalent case.
	-- Scoped to this condition only: `enable = false` and `hideInCombat`
	-- above still hide unconditionally, same reasoning as the rep bar.
	if settings.hideAtMaxLevel and max <= 0 and not E.moversUnlocked then
		bar:Hide()
		return
	end

	bar:Show()
	if max <= 0 then max = 1 end
	bar.statusBar:SetMinMaxValues(0, max)
	bar.statusBar:SetValue(cur)

	local rested = 0
	if type(GetXPExhaustion) == "function" then
		local ok, value = pcall(GetXPExhaustion)
		if ok then rested = tonumber(value) or 0 end
	end

	local text = ""
	local textFormat = settings.textFormat

	if rested > 0 then
		local restedMax = cur + rested
		if restedMax > max then restedMax = max end
		bar.rested:SetMinMaxValues(0, max)
		bar.rested:SetValue(restedMax)

		if textFormat == "PERCENT" then
			text = string.format("%d%% R:%d%%", cur / max * 100, rested / max * 100)
		elseif textFormat == "CURMAX" then
			text = string.format("%s - %s R:%s", E:ShortValue(cur), E:ShortValue(max), E:ShortValue(rested))
		elseif textFormat == "CURPERC" then
			text = string.format("%s - %d%% R:%s [%d%%]", E:ShortValue(cur), cur / max * 100, E:ShortValue(rested), rested / max * 100)
		elseif textFormat == "CUR" then
			text = string.format("%s R:%s", E:ShortValue(cur), E:ShortValue(rested))
		elseif textFormat == "REM" then
			text = string.format("%s R:%s", E:ShortValue(max - cur), E:ShortValue(rested))
		elseif textFormat == "CURREM" then
			text = string.format("%s - %s R:%s", E:ShortValue(cur), E:ShortValue(max - cur), E:ShortValue(rested))
		elseif textFormat == "CURPERCREM" then
			text = string.format("%s - %d%% (%s) R:%s", E:ShortValue(cur), cur / max * 100, E:ShortValue(max - cur), E:ShortValue(rested))
		end
	else
		bar.rested:SetMinMaxValues(0, 1)
		bar.rested:SetValue(0)

		if textFormat == "PERCENT" then
			text = string.format("%d%%", cur / max * 100)
		elseif textFormat == "CURMAX" then
			text = string.format("%s - %s", E:ShortValue(cur), E:ShortValue(max))
		elseif textFormat == "CURPERC" then
			text = string.format("%s - %d%%", E:ShortValue(cur), cur / max * 100)
		elseif textFormat == "CUR" then
			text = E:ShortValue(cur)
		elseif textFormat == "REM" then
			text = E:ShortValue(max - cur)
		elseif textFormat == "CURREM" then
			text = string.format("%s - %s", E:ShortValue(cur), E:ShortValue(max - cur))
		elseif textFormat == "CURPERCREM" then
			text = string.format("%s - %d%% (%s)", E:ShortValue(cur), cur / max * 100, E:ShortValue(max - cur))
		end
	end

	bar.text:SetText(text)
end

function M:UpdateExperienceDimensions()
	local bar = self.expBar
	if not bar then return end
	local settings = self.db.experience

	pcall(bar.SetWidth, bar, settings.width)
	pcall(bar.SetHeight, bar, settings.height)
	pcall(bar.statusBar.SetOrientation, bar.statusBar, settings.orientation)
	pcall(bar.rested.SetOrientation, bar.rested, settings.orientation)

	-- Font family/size are a confirmed no-op via SetFont on UA -- wired up
	-- anyway, same as every other font field in this project.
	local LSM = LibStub("LibSharedMedia-3.0", true)
	local path = LSM and LSM:Fetch("font", settings.font)
	if path then
		local outline = settings.fontOutline
		if outline == "NONE" then outline = "" end
		pcall(bar.text.SetFont, bar.text, path, settings.textSize, outline)
	end

	if settings.mouseover then
		M:SetBarAlpha(bar, 0)
	else
		M:SetBarAlpha(bar, 1)
	end
end

-- Real ElvUI's own name for this ("EnableDisable_ExperienceBar") is
-- kept for parity, but the IMPLEMENTATION differs: real ElvUI dynamically
-- registers/unregisters events depending on the enable state --
-- frame:UnregisterEvent/UnregisterAllEvents do not work on UA, so every
-- event is registered ONCE in M:LoadExperienceBar and left registered
-- forever; M:UpdateExperience (which every event calls) is what actually
-- gates on `settings.enable` and Hide()s the bar -- exactly
-- mirroring how real ElvUI's OWN UpdateExperience already starts with
-- `if not mod.db.experience.enable then return end` regardless, so this
-- is a strict subset of what real ElvUI already does, not a new
-- mechanism.
function M:EnableDisable_ExperienceBar()
	self:UpdateExperience()
end

local XP_EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"PLAYER_XP_UPDATE",
	"DISABLE_XP_GAIN",
	"ENABLE_XP_GAIN",
	"UPDATE_EXHAUSTION",
	"PLAYER_LEVEL_UP",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
}

function M:LoadExperienceBar()
	-- {0, 0.4, 1, 0.8} / {1, 0, 1, 0.2} are real ElvUI's own exact
	-- expBar/rested colors (Experience.lua:154,159) -- kept for visual
	-- fidelity even though the CONSTRUCTION technique below is
	-- UnrealUI's, not real ElvUI's.
	self.expBar = self:CreateBar("ElvUI_ExperienceBar", { 0, 0.4, 1, 0.8 })
	local bar = self.expBar

	-- Rested overlay: a second StatusBar, sibling to (not child of)
	-- bar.statusBar, explicitly placed BEHIND it via frame level so it
	-- reads as an extension past the current XP rather than an overlay
	-- covering it -- ported from UnrealUI's own proven-on-UA technique
	-- for this exact composite (source/UnrealUI/modules/xpbar.lua:118-132),
	-- since relying on creation-order z-stacking alone is less explicit.
	local rested = CreateFrame("StatusBar", nil, bar)
	rested:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
	rested:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
	-- E.media.normTex -- see DataBars.lua's own CreateBar comment.
	pcall(rested.SetStatusBarTexture, rested, E.media and E.media.normTex or "Interface\\Buttons\\WHITE8x8")
	rested:SetStatusBarColor(1, 0, 1, 0.2)
	rested:SetMinMaxValues(0, 1)
	rested:SetValue(0)
	bar.rested = rested

	local ok, barLevel = pcall(bar.statusBar.GetFrameLevel, bar.statusBar)
	if ok and tonumber(barLevel) then
		pcall(rested.SetFrameLevel, rested, barLevel)
		pcall(bar.statusBar.SetFrameLevel, bar.statusBar, barLevel + 1)
	end

	-- Wired onto bar.statusBar/rested TOO, not just the outer `bar`:
	-- `bar.statusBar`/`rested` are CHILD StatusBar frames sitting at a
	-- HIGHER frame level than `bar` (see the level pinning just above) --
	-- on this client they swallow mouse input over their own visible area
	-- even without EnableMouse set on themselves, instead of letting it
	-- pass through to the lower-level parent the way standard WoW frame
	-- semantics normally would. Without this, the tooltip would only
	-- trigger on the outer frame's border, not on the visible bar itself.
	-- Same general "mouse/frame-level behavior differs on UA" pattern
	-- found elsewhere in this project -- explicitly wiring the same
	-- handlers onto every layer sidesteps needing to pin down the exact
	-- mechanism.
	local function OnEnter() M:ExperienceBar_OnEnter() end
	local function OnLeave() M:ExperienceBar_OnLeave() end
	local hoverRegions = { bar, bar.statusBar, rested }
	local i
	for i = 1, table.getn(hoverRegions) do
		local region = hoverRegions[i]
		if region then
			pcall(region.EnableMouse, region, true)
			region:SetScript("OnEnter", OnEnter)
			region:SetScript("OnLeave", OnLeave)
		end
	end

	-- First-run-only starting position -- E:CreateMover captures this as
	-- its reset default, then owns the bar's actual position from here
	-- on (drag/nudge via /moveui), same pattern as every other bar this
	-- project has built (ActionBars/PetBar/Minimap). Real ElvUI anchors
	-- to its own LeftChatPanel instead (see this file's header) -- not
	-- available here, so bottom-center of the screen is used as a
	-- reasonable stand-in, roughly where the native XP bar used to sit.
	--
	-- y=250 clears the WHOLE ActionBars bar1-5 stack (which spans roughly
	-- y=4 to y=204, Modules/ActionBars.lua's own DEFAULT_Y_OFFSET),
	-- including the Pet Bar (its own default sits at y=204,
	-- Modules/PetBar.lua:138, typically ~28-32px tall for a single row) --
	-- a lower offset would render behind one of those bars, visually
	-- indistinguishable from it.
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 250)
	E:CreateMover(bar, "ExperienceBarMover", L["Experience Bar"])

	HideNativeFrame(_G.MainMenuExpBar)
	HideNativeFrame(_G.ExhaustionTick)
	-- The native `ReputationWatchBar_Update` Show()s `MainMenuBarMaxLevelBar`
	-- (the "no more XP to earn" replacement strip) whenever the player is
	-- at max level with no watched faction (FrameXML/ReputationFrame.lua:
	-- 232-240) -- the same class of native chrome `MainMenuExpBar` itself
	-- is. Belongs to THIS module for the same reason MainMenuExpBar does:
	-- it's the XP bar's own native max-level variant, not reputation
	-- chrome.
	HideNativeFrame(_G.MainMenuBarMaxLevelBar)

	self:UpdateExperienceDimensions()

	local i
	for i = 1, table.getn(XP_EVENTS) do
		self:RegisterEvent(XP_EVENTS[i], "UpdateExperience")
	end

	-- Fallback poll, matching UnrealUI's own xpbar.lua reasoning
	-- (source/UnrealUI/modules/xpbar.lua:279-285): none of
	-- UnitXP/UnitXPMax/GetXPExhaustion/PLAYER_XP_UPDATE/UPDATE_EXHAUSTION
	-- have a confirmed runtime record on UA, so this polls every 2s
	-- alongside the event registrations above as a safety net -- also
	-- doubles as this module's own periodic native-chrome resweep
	-- (ExhaustionTick was separately confirmed lazily-created well after
	-- login during the ActionBars work, same class of frame that needs
	-- more than a one-time hide at Initialize()).
	E:ScheduleRepeatingTimer(function()
		HideNativeFrame(_G.MainMenuExpBar)
		HideNativeFrame(_G.ExhaustionTick)
		HideNativeFrame(_G.MainMenuBarMaxLevelBar)
		M:UpdateExperience()
	end, 2)

	self:UpdateExperience()
end
