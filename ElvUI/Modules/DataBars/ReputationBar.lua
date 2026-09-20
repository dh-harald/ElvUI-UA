-- Reputation Bar -- the "Reputation" sub-feature of real ElvUI's DataBars
-- module (ElvUI-vanilla/ElvUI/Modules/DataBars/Reputation.lua).
-- Named ReputationBar.lua rather than Reputation.lua to match this
-- folder's own XPBar.lua naming, but the module OBJECT is the shared
-- `E.DataBars` from DataBars.lua, exactly like XPBar.lua.
--
-- WHAT THIS FIXES: the Character panel's Reputation tab has a
-- per-faction detail popup (ReputationDetailFrame) with three checkboxes
-- -- "At War", "Move to Inactive" and "Show as Experience Bar". The first
-- two are pure API calls and work natively all along; the third one
-- (ReputationDetailMainScreenCheckBox) calls
-- `SetWatchedFactionIndex(GetSelectedFaction())` and then
-- `ReputationWatchBar_Update()`, which brings up Blizzard's OWN native
-- watch bar (`ReputationWatchBar`, parented to `MainMenuBar`), switching
-- the original bar back on.
--
-- Two separate root causes, both handled here:
--   1. NOTHING REPLACED IT. `ReputationWatchBar` was only ever listed in
--      Modules/ActionBars/ActionBars.lua's generic CHROME_TO_HIDE, with
--      no ElvUI-styled bar of its own -- the exact same mistake already
--      found and fixed once for the XP bar (see XPBar.lua's header).
--      That name is now REMOVED from CHROME_TO_HIDE; this module owns
--      hiding it, right before building its own replacement. Don't
--      re-add it there.
--   2. HIDING THE PARENT ISN'T ENOUGH ON UA. `ReputationWatchBar:Hide()`
--      does not reliably hide its children on this client. So the native
--      watch bar's fill StatusBar, its 8 chrome textures
--      and its DIALOG-strata text overlay could all keep rendering even
--      with the parent frame hidden. SuppressNativeWatchBar below
--      therefore walks EVERY named piece individually, and additionally
--      uses DisableDrawLayer -- a standing FRAME PROPERTY, immune to a
--      later native redraw -- which is this project's own established
--      reliable mechanism for native art (see the Skins module's whole
--      history).
--
-- Construction/settings split is identical to XPBar.lua's: frame shape
-- from DataBars.lua's own M:CreateBar (UnrealUI's proven-on-UA
-- backdrop-anchor + inset-StatusBar technique), everything else -- field
-- names, defaults, event list, tooltip, the 7 text-format modes -- from
-- real ElvUI's own Reputation.lua.
--
-- Settings: `P.databars.reputation` (Settings/Profile.lua), where the
-- deviations from real ElvUI's own values are listed. `enable` defaults to
-- TRUE here (real ElvUI: false) because this bar is the ONLY thing that
-- makes the "Show as Experience Bar" checkbox do anything visible at all --
-- the native bar it used to drive is hidden. Costs nothing when unused:
-- with no watched faction, GetWatchedFactionInfo returns nil and the bar
-- hides itself.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E.DataBars

-- Real 1.12.1's own FACTION_BAR_COLORS (FrameXML/ReputationFrame.lua) as
-- a LOCAL fallback table. The global of the same name is a FrameXML
-- definition, and several FrameXML globals simply don't exist on UA
-- (ReputationFrame_Update/SkillFrame_UpdateSkills/
-- PaperDollItemSlotButton_Update all come back nil there) -- so the
-- global is read first and this is used whenever it isn't there.
local FALLBACK_BAR_COLORS = {
	[1] = { r = 0.8, g = 0.3, b = 0.22 },
	[2] = { r = 0.8, g = 0.3, b = 0.22 },
	[3] = { r = 0.75, g = 0.27, b = 0 },
	[4] = { r = 0.9, g = 0.7, b = 0 },
	[5] = { r = 0, g = 0.6, b = 0.1 },
	[6] = { r = 0, g = 0.6, b = 0.1 },
	[7] = { r = 0, g = 0.6, b = 0.1 },
	[8] = { r = 0, g = 0.6, b = 0.1 },
}

-- Same reasoning as FALLBACK_BAR_COLORS: FACTION_STANDING_LABEL1..8 are
-- GlobalStrings entries; these locale strings stand in only on a client that
-- does not define them.
local FALLBACK_STANDING_LABELS = {
	L["Hated"], L["Hostile"], L["Unfriendly"], L["Neutral"],
	L["Friendly"], L["Honored"], L["Revered"], L["Exalted"],
}

local function StandingColor(reaction)
	local id = tonumber(reaction) or 0
	local colors = _G.FACTION_BAR_COLORS
	local color = colors and colors[id]
	if not color then color = FALLBACK_BAR_COLORS[id] end
	if not color then color = FALLBACK_BAR_COLORS[4] end
	return color.r, color.g, color.b
end

local function StandingLabel(reaction)
	local id = tonumber(reaction) or 0
	local label = _G["FACTION_STANDING_LABEL"..id]
	if not label then label = FALLBACK_STANDING_LABELS[id] end
	return label or (_G.UNKNOWN or L["Unknown"])
end

-- Every named piece of Blizzard's native reputation watch bar, from the
-- real 1.12.1 FrameXML (wow-ui-source/FrameXML/
-- ReputationFrame.xml). Listed INDIVIDUALLY, parent first, because Hide() on the
-- parent doesn't reliably take its children down on UA (see this file's
-- header):
--   * ReputationWatchBar            -- the container (parent: MainMenuBar)
--   * ReputationWatchStatusBar      -- the actual fill bar
--   * ReputationWatchBarTexture0-3  -- the "below max level" chrome frame
--   * ReputationXPBarTexture0-3     -- the "at max level" chrome frame
--     (native code swaps between these two sets in ReputationWatchBar_Update)
--   * ReputationWatchStatusBarBackground -- its dark backing texture
--   * ReputationWatchBarOverlayFrame     -- a DIALOG-strata overlay ...
--   * ReputationWatchStatusBarText       -- ... holding the value text
local NATIVE_WATCH_PIECES = {
	"ReputationWatchBar",
	"ReputationWatchStatusBar",
	"ReputationWatchStatusBarBackground",
	"ReputationWatchBarTexture0",
	"ReputationWatchBarTexture1",
	"ReputationWatchBarTexture2",
	"ReputationWatchBarTexture3",
	"ReputationXPBarTexture0",
	"ReputationXPBarTexture1",
	"ReputationXPBarTexture2",
	"ReputationXPBarTexture3",
	"ReputationWatchBarOverlayFrame",
	"ReputationWatchStatusBarText",
}

-- Frames whose whole DRAW LAYERS get switched off, on top of the
-- per-object hiding above. DisableDrawLayer is a standing frame
-- PROPERTY: anything drawn to that layer LATER (including by a native
-- redraw we never see) stays hidden, without needing to win a race
-- against native code. This is the single mechanism that reliably worked
-- across the entire Skins/Character saga where SetTexture(nil)/Hide()
-- alone kept losing to native re-asserts -- applied here proactively
-- rather than after another round of "it came back".
--   * ReputationWatchStatusBar: its own fill is drawLayer="ARTWORK", the
--     8 chrome textures are OVERLAY, the dark backing is BACKGROUND.
--   * ReputationWatchBarOverlayFrame: the value FontString is ARTWORK.
local WATCH_LAYER_KILLS = {
	{ frame = "ReputationWatchStatusBar", layers = { "ARTWORK", "OVERLAY", "BACKGROUND" } },
	{ frame = "ReputationWatchBarOverlayFrame", layers = { "ARTWORK", "OVERLAY" } },
}

local function SuppressNativeWatchBar()
	local i
	for i = 1, table.getn(NATIVE_WATCH_PIECES) do
		M:HideNativeFrame(_G[NATIVE_WATCH_PIECES[i]])
	end

	for i = 1, table.getn(WATCH_LAYER_KILLS) do
		local entry = WATCH_LAYER_KILLS[i]
		local frame = _G[entry.frame]
		if frame then
			local j
			for j = 1, table.getn(entry.layers) do
				pcall(frame.DisableDrawLayer, frame, entry.layers[j])
			end
		end
	end
end
M.SuppressNativeWatchBar = SuppressNativeWatchBar

-- FULL REPLACEMENT of the native global ReputationWatchBar_Update.
--
-- This is deliberate and is the actual fix for the symptom, not
-- a nicety: `ReputationDetailMainScreenCheckBox`'s own OnClick calls this
-- function BY NAME the moment "Show as Experience Bar" is ticked
-- (FrameXML/ReputationFrame.xml:825-833), and the native implementation's
-- entire job is to Show() the native watch bar plus its chrome, and to
-- Show()/Hide() MainMenuExpBar and MainMenuBarMaxLevelBar around it. All
-- four of those are frames this project replaces with its own -- so
-- letting the native version run at all is exactly what brought the
-- original bar back. Replacing the function outright means that code
-- path never executes, instead of being fought after the fact.
--
-- Precedent for owning a native global rather than hooking it:
-- Modules/Skins/Skins.lua's ReplaceFauxScrollFrameUpdate, where a
-- wrap-and-call-through was tried first and confirmed NOT sufficient.
-- Same acknowledged tradeoff applies: any other addon calling this global
-- gets our version. Accepted -- its only purpose is driving a bar that is
-- permanently hidden here, and `hooksecurefunc` isn't available on UA
-- anyway.
--
-- Also covers the OPPOSITE case: if this global doesn't exist on UA at
-- all (several of its FrameXML siblings confirmed don't), the native
-- OnClick would throw "attempt to call a nil value" right after setting
-- the watched faction. Defining it removes that error either way.
local function ReplaceReputationWatchBarUpdate()
	_G.ReputationWatchBar_Update = function()
		SuppressNativeWatchBar()
		M:UpdateReputation()
	end
end

function M:ReputationBar_OnEnter()
	local settings = self.db.reputation
	if settings.mouseover then
		-- M:SetBarAlpha, not a bare bar:SetAlpha -- alpha does not cascade
		-- to child frames on UA, see DataBars.lua's own comment there.
		M:SetBarAlpha(self.repBar, 1)
	end

	local name, reaction, min, max, value = GetWatchedFactionInfo()
	if not name then return end

	min = tonumber(min) or 0
	max = tonumber(max) or 0
	value = tonumber(value) or 0

	-- Real ElvUI normalizes by subtracting `min` (the standing band's
	-- absolute floor -- UA's own Faction.md documents these as absolute
	-- scores that "the default UI subtracts barMin before drawing").
	local cur = value - min
	local total = max - min
	if total <= 0 then total = 1 end

	GameTooltip:SetOwner(self.repBar, "ANCHOR_CURSOR", 0, -4)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Standing:"], StandingLabel(reaction), 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Reputation:"], string.format("%d / %d (%d%%)", cur, total, cur / total * 100), 1, 1, 1)
	GameTooltip:Show()
end

function M:ReputationBar_OnLeave()
	local settings = self.db.reputation
	if settings.mouseover then
		M:SetBarAlpha(self.repBar, 0)
	end
	GameTooltip:Hide()
end

-- Real ElvUI's own ReputationBar_OnClick (Reputation.lua) opens the
-- Character panel's Reputation tab. Wired via OnMouseUp rather than
-- OnClick because M:CreateBar builds a plain Frame, not a Button (same as
-- the XP bar) -- and this project has separately confirmed Button:Click()
-- is broken on UA anyway, so nothing is lost by not being a Button here.
function M:ReputationBar_OnClick()
	pcall(ToggleCharacter, "ReputationFrame")
end

-- Matches real ElvUI's own UpdateReputation (Reputation.lua)
-- format-mode-for-format-mode, with plain "%d" instead of E:ShortValue
-- (a number-abbreviation helper this project doesn't have -- same call
-- already made in XPBar.lua) and `reaction` used directly as the standing
-- id instead of re-deriving it by looping GetNumFactions/GetFactionInfo
-- looking for a name match. That loop is pure redundancy in the
-- reference: UA's own Faction.md states outright that
-- GetWatchedFactionInfo's `reaction` IS "the same standing id as
-- GetFactionInfo", and real 1.12.1's own FrameXML uses it that way too
-- (ReputationFrame.lua, FACTION_BAR_COLORS[reaction]).
function M:UpdateReputation()
	local bar = self.repBar
	if not bar then return end

	local settings = self.db.reputation
	if not settings.enable then
		bar:Hide()
		return
	end

	-- Not checked by real ElvUI's own UpdateReputation either, despite
	-- the setting existing and being wired into its config -- the exact
	-- same incompleteness already found and fixed for the XP bar's own
	-- hideInCombat (see XPBar.lua). Implemented properly here too.
	if settings.hideInCombat and UnitAffectingCombat("player") then
		bar:Hide()
		return
	end

	local name, reaction, min, max, value = GetWatchedFactionInfo()
	if not name then
		-- STAY VISIBLE WHILE /moveui IS UNLOCKED. Same latent bug, same
		-- fix, as UnitFrames.lua's own PetTarget case (see its
		-- UpdateFrame comment): Core/Movers.lua parents a mover's drag
		-- HANDLE as a CHILD of the frame it moves, so a frame that
		-- Hide()s itself takes its own handle down with it and can never
		-- be positioned. The bar has no watched faction most of the time,
		-- so for this bar that's the normal state, not an edge case.
		-- Matches real ElvUI's own "stay visible for positioning while
		-- unlocked" mover/test-mode behaviour.
		--
		-- Deliberately scoped to THIS condition only: `enable = false` and
		-- `hideInCombat` above still hide the bar unconditionally. A bar
		-- turned off via config shouldn't reappear in move mode (real
		-- ElvUI goes further and disables its mover outright), and
		-- hideInCombat is trivially worked around by positioning out of
		-- combat.
		if not E.moversUnlocked then
			bar:Hide()
			return
		end

		-- Placeholder state for the move-mode preview. The drag handle
		-- itself renders over the whole frame (blue fill + label), so this
		-- only needs to leave the bar in a clean, non-stale state rather
		-- than fake a faction.
		bar:Show()
		bar.statusBar:SetMinMaxValues(0, 1)
		bar.statusBar:SetValue(0)
		bar.text:SetText("")
		return
	end

	min = tonumber(min) or 0
	max = tonumber(max) or 0
	value = tonumber(value) or 0

	bar:Show()

	local r, g, b = StandingColor(reaction)
	pcall(bar.statusBar.SetStatusBarColor, bar.statusBar, r, g, b)
	bar.statusBar:SetMinMaxValues(min, max)
	bar.statusBar:SetValue(value)

	local cur = value - min
	local total = max - min
	-- Prevent a division by zero (real ElvUI's own guard, same spot).
	if total <= 0 then total = 1 end

	local standingLabel = StandingLabel(reaction)
	local text = ""
	local textFormat = settings.textFormat

	if textFormat == "PERCENT" then
		text = string.format("%s: %d%% [%s]", name, cur / total * 100, standingLabel)
	elseif textFormat == "CURMAX" then
		text = string.format("%s: %s - %s [%s]", name, E:ShortValue(cur), E:ShortValue(total), standingLabel)
	elseif textFormat == "CURPERC" then
		text = string.format("%s: %s - %d%% [%s]", name, E:ShortValue(cur), cur / total * 100, standingLabel)
	elseif textFormat == "CUR" then
		text = string.format("%s: %s [%s]", name, E:ShortValue(cur), standingLabel)
	elseif textFormat == "REM" then
		text = string.format("%s: %s [%s]", name, E:ShortValue(total - cur), standingLabel)
	elseif textFormat == "CURREM" then
		text = string.format("%s: %s - %s [%s]", name, E:ShortValue(cur), E:ShortValue(total - cur), standingLabel)
	elseif textFormat == "CURPERCREM" then
		text = string.format("%s: %s - %d%% (%s) [%s]", name, E:ShortValue(cur), cur / total * 100, E:ShortValue(total - cur), standingLabel)
	end

	bar.text:SetText(text)
end

function M:UpdateReputationDimensions()
	local bar = self.repBar
	if not bar then return end
	local settings = self.db.reputation

	pcall(bar.SetWidth, bar, settings.width)
	pcall(bar.SetHeight, bar, settings.height)
	pcall(bar.statusBar.SetOrientation, bar.statusBar, settings.orientation)

	-- Font family/size are a confirmed no-op via SetFont on UA -- wired
	-- up anyway, same as every other font field in this project.
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

-- Real ElvUI's own name kept for parity; the IMPLEMENTATION differs the
-- same way M:EnableDisable_ExperienceBar's does -- events are registered
-- once and never unregistered (UnregisterEvent doesn't work on UA), with
-- M:UpdateReputation gating on `settings.enable` instead.
function M:EnableDisable_ReputationBar()
	self:UpdateReputation()
end

local REPUTATION_EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"UPDATE_FACTION",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
}

function M:LoadReputationBar()
	-- Placeholder fill color only -- UpdateReputation immediately
	-- overwrites it with the watched faction's own standing color, the
	-- same way real ElvUI does (its CreateBar has no per-bar color at
	-- all, this project's M:CreateBar requires one).
	self.repBar = self:CreateBar("ElvUI_ReputationBar", { 0, 0.6, 0.1, 0.8 })
	local bar = self.repBar

	-- OnEnter/OnLeave wired onto the inner statusBar too, not just the
	-- outer frame: a higher-level child StatusBar swallows mouse input
	-- over its own area on this client, so the tooltip would otherwise
	-- only trigger on the outer border (same issue the XP bar's own
	-- construction already accounts for). Same fix applied up front here.
	local function OnEnter() M:ReputationBar_OnEnter() end
	local function OnLeave() M:ReputationBar_OnLeave() end
	local function OnMouseUp() M:ReputationBar_OnClick() end
	local hoverRegions = { bar, bar.statusBar }
	local i
	for i = 1, table.getn(hoverRegions) do
		local region = hoverRegions[i]
		if region then
			pcall(region.EnableMouse, region, true)
			region:SetScript("OnEnter", OnEnter)
			region:SetScript("OnLeave", OnLeave)
			region:SetScript("OnMouseUp", OnMouseUp)
		end
	end

	-- First-run-only position: directly BELOW the XP bar (which sits at
	-- BOTTOM y=250 with a default height of 14), so the two read as one
	-- stack out of the box. E:CreateMover owns the position from here on
	-- (drag/nudge via /moveui), independently of the XP bar -- matching
	-- real ElvUI, where these are two fully separate movable bars.
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 232)
	E:CreateMover(bar, "ReputationBarMover", L["Reputation Bar"])

	SuppressNativeWatchBar()
	ReplaceReputationWatchBarUpdate()

	self:UpdateReputationDimensions()

	for i = 1, table.getn(REPUTATION_EVENTS) do
		self:RegisterEvent(REPUTATION_EVENTS[i], "UpdateReputation")
	end

	-- Fallback poll, same reasoning as XPBar.lua's own: UPDATE_FACTION
	-- has no confirmed runtime record on UA (the client's Lua API docs
	-- document no events at all), so a 2s poll backs the event
	-- registrations up -- and doubles as the periodic native-chrome
	-- resweep this project needs everywhere, since the native watch bar's
	-- pieces are shown lazily by native code long after login (same class
	-- of frame as ExhaustionTick/GameTimeFrame elsewhere here).
	E:ScheduleRepeatingTimer(function()
		SuppressNativeWatchBar()
		M:UpdateReputation()
	end, 2)

	self:UpdateReputation()
end
