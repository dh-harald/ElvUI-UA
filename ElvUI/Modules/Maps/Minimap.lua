-- Minimap module.
--
-- Repositions/resizes the Blizzard Minimap into a plain square ElvUI-style
-- holder with a border, hides the default chrome (border textures, zoom
-- buttons, toggle button), adds a PvP-colored zone text header above the
-- map, repositions the calendar/mail/battlefield-queue icons, persists/
-- restores zoom level, and switches to mouse-wheel zoom (+/- buttons as a
-- fallback). Ported from real ElvUI's Modules/Maps/Minimap.lua
-- (source/ElvUI-vanilla), scoped down -- deliberately NOT included: the
-- right-click menu, Farm Mode.
--
-- Settings coverage, against real ElvUI's actual config table
-- (source/ElvUI-vanilla/ElvUI_Config/Maps.lua's `minimap` group):
--   - size, locationText (SHOW/HIDE/MOUSEOVER), resetZoom (enable+time),
--     icons (calendar/mail/battlefield position/scale/offset + calendar's
--     private hideCalendar toggle) -> IMPLEMENTED below, all live (no
--     /reload needed) via M:UpdateSettings(), matching real ElvUI's own
--     MM:UpdateSettings().
--   - locationFont/locationFontSize/locationFontOutline (LSM font picker
--     + size + outline) -> NOT implemented. Font family/size are a
--     confirmed no-op via SetFont on UA regardless, so wiring a picker for
--     a value that can't visibly change isn't worth it.
--   - `enable` itself stays reload-required (private, one-shot Initialize
--     check) -- matches real ElvUI's own design (the PRIVATE_RL/
--     StaticPopup call in its `set`), not a limitation introduced here.
--
-- UA note: UnrealUI's own minimap.lua (source/UnrealUI/modules/minimap.lua)
-- documents that the native Minimap renders in a special pass *beneath*
-- ordinary frames on this engine -- any frame placed on top of the map
-- surface ends up hidden behind it. The border holder sits BEHIND Minimap
-- (Minimap is reparented onto it, not the other way around), and the zone
-- text header lives ABOVE the map in its own strip (Minimap is anchored to
-- the BOTTOM of the now-taller holder), not overlapping the map surface --
-- both stay clear of that quirk on purpose. The wheel-catcher frame below
-- IS spatially on top of the map, but it's a purely invisible event
-- catcher (no texture/content), so even if UA's render-layer quirk hides
-- it visually, that doesn't matter -- only input capture needs to work.
--
-- Never call MinimapZoomIn:Click()/MinimapZoomOut:Click() -- Button:Click()
-- is confirmed broken on UA. Minimap:SetZoom/:GetZoom are used directly
-- instead.
--
-- Note: SetSize() doesn't exist on the 1.12.1 API -- SetWidth/SetHeight
-- only (see Core/GameMenu.lua, which already avoids it).
--
-- SetMaskTexture leaving the map circular on UA is a no-op, not a bug --
-- left as-is intentionally, don't try to fix. The wheel catcher below is a
-- `CreateFrame("ScrollFrame", ...)`, not a plain Frame: OnMouseWheel only
-- fires on a ScrollFrame on this client, matching
-- source/LibConfig-1.0/LibConfig-1.0.lua:456-457's own dropdown-menu
-- workaround for the same limitation. Explicit +/- buttons are kept
-- alongside the wheel catcher rather than relying on the wheel alone, same
-- as LibConfig-1.0's own scrollable widgets.

local E, L, V, P, G = unpack(ElvUI)
local M = E:NewModule("Minimap", "AceEvent-3.0")
E.Minimap = M

-- Settings: `V.general.minimap` / `P.general.minimap`
-- (Settings/Private.lua, Settings/Profile.lua).

-- LibDBIcon-1.0 (and everything else that places things around the
-- minimap) asks this global for the minimap's shape on EVERY reposition;
-- it defaults to "ROUND" when nobody defines it, which is why third-party
-- minimap buttons ride an invisible circle around our square map. The
-- library already handles "SQUARE" fully -- see its own `minimapShapes`
-- table -- so nothing needs patching in it, this declaration IS the fix.
-- Real ElvUI does exactly the same thing (source/ElvUI-vanilla/ElvUI/
-- Modules/Maps/Minimap.lua:42), also at file scope: LibDBIcon defers its
-- initial pass to PLAYER_LOGIN specifically to "let any GetMinimapShape
-- addons load up", and file scope runs long before that, so icons come up
-- square on the very first frame rather than snapping over later.
--
-- Deliberately NOT unconditional, unlike real ElvUI's: if this module is
-- switched off the Minimap stays round, and claiming otherwise would push
-- everyone's buttons onto a square that isn't there. E.private is empty at
-- file-load time but populated long before anything calls this.
function GetMinimapShape()
	if E.private and E.private.general and E.private.general.minimap
		and E.private.general.minimap.enable then
		return "SQUARE"
	end
	return "ROUND"
end

local HEADER_HEIGHT = 20

-- Zone-PvP-status coloring. friendly/hostile/contested RGB values copied
-- from real ElvUI-vanilla's own GetLocTextColor (source/ElvUI-vanilla/
-- ElvUI/Modules/Maps/Minimap.lua:46-57) -- only these three exist at this
-- API vintage (no sanctuary/arena, those are later-client pvpTypes).
--
-- `default` deliberately does NOT match that reference (which falls to
-- the same red as hostile for anything else) -- confirmed wrong in-game:
-- Bloodhoof Village, an ordinary home-faction starting town, showed red
-- for a Tauren character. Root cause, per UA's own API docs
-- (source/UnrealAzeroth_LuaAPI/en/functions.md and .../globals/
-- Location.md): GetZonePVPInfo() is a STUB on UA -- "Currently always
-- returns three nil values" -- so on UA this `default` entry isn't just a
-- sane fallback for unflagged zones, it's the ONLY color this module will
-- ever show there, period; real PvP-status coloring is simply unavailable
-- on this client (may still work on real 1.12.1, where the API isn't
-- stubbed). Plain white for `default` rather than friendly-green -- green
-- would falsely claim "safe" for a status we can't actually determine on
-- UA; white reads as neutral/unknown instead. Also means that if UA ever
-- stops stubbing GetZonePVPInfo(), coloring starts working on its own --
-- friendly/hostile/contested already return real colors today, only the
-- fallback needed to stop pretending to know.
local ZONE_COLORS = {
	friendly = { 0.05, 0.85, 0.03 },
	hostile = { 0.84, 0.03, 0.03 },
	contested = { 0.9, 0.85, 0.05 },
	default = { 1, 1, 1 },
}

local CHROME_TO_HIDE = {
	"MinimapBorder",
	"MinimapBorderTop",
	"MinimapToggleButton",
	"MinimapZoomIn",
	"MinimapZoomOut",
}

local function HideChrome()
	for _, name in ipairs(CHROME_TO_HIDE) do
		local frame = _G[name]
		if frame then
			pcall(frame.Hide, frame)
		end
	end
end

-- Debounced: a single physical wheel notch appears to fire OnMouseWheel
-- more than once on UA (matches other "input event spam" quirks already
-- seen on this engine elsewhere in the project), which turned one notch
-- into several zoom-level jumps -- collapse anything within DEBOUNCE
-- seconds of the last accepted step into a no-op. Best-effort theory,
-- unconfirmed -- needs an in-game retest to know if this actually fixes
-- it or if the jump is really just "1 zoom level is a big visual change
-- at this minimap size."
local ZOOM_DEBOUNCE = 0.15
local lastZoomTime = 0

-- Reset Zoom + zoom persistence: ported from real ElvUI's actual logic
-- (source/ElvUI-vanilla/ElvUI/Modules/Maps/Minimap.lua:93-114), not just
-- the config option -- a `hooksecurefunc` on Minimap:SetZoom catches
-- EVERY zoom change, not only ours (wheel/buttons below), but also
-- Blizzard's own native auto-zoom (e.g. entering an instance auto-zooms
-- the minimap in). Exact real-ElvUI semantics, not a debounce: the FIRST
-- zoom change while idle starts a single `time`-second countdown back to
-- zoomed-out (level 0); further zoom changes during that window neither
-- restart nor cancel it (matches the reference's `not isResetting` guard
-- -- deliberately not "rolling" like the wheel-notch debounce above,
-- which is a different, UA-specific problem). When Reset Zoom is OFF,
-- every zoom change is instead persisted into the private DB
-- (`zoomLevel`), and MINIMAP_UPDATE_ZOOM re-applies it whenever something
-- else (Blizzard) changes the zoom out from under us -- this is what
-- makes the minimap "remember" its zoom level across zone transitions
-- and relogs. E (not M) is used for ScheduleTimer/CancelTimer since only
-- E has AceTimer-3.0 mixed in (from Init.lua's NewAddon call).
local isResetting = false
local resetZoomTimerHandle

local function CancelZoomResetTimer()
	if resetZoomTimerHandle then
		E:CancelTimer(resetZoomTimerHandle)
		resetZoomTimerHandle = nil
	end
	isResetting = false
end

local function OnMinimapSetZoom(_, zoomLevel)
	local resetZoom = E.db.general.minimap.resetZoom
	if resetZoom and resetZoom.enable then
		if not isResetting then
			isResetting = true
			resetZoomTimerHandle = E:ScheduleTimer(function()
				resetZoomTimerHandle = nil
				-- Order matters: SetZoom(0) FIRST, isResetting=false AFTER --
				-- matches real ElvUI's exact ResetZoom() ordering.
				-- PollMinimapZoom (below) also calls OnMinimapSetZoom
				-- directly whenever it observes a zoom change; keeping
				-- isResetting true across this SetZoom(0) call means a poll
				-- tick landing on the new zoom==0 value falls through as a
				-- no-op instead of `not isResetting` being true and
				-- immediately scheduling ANOTHER reset countdown forever.
				pcall(Minimap.SetZoom, Minimap, 0)
				isResetting = false
			end, resetZoom.time or 3)
		end
	else
		E.private.general.minimap.zoomLevel = zoomLevel
	end
end

local function OnMinimapUpdateZoom()
	local saved = E.private.general.minimap.zoomLevel
	if saved and Minimap:GetZoom() ~= saved then
		pcall(Minimap.SetZoom, Minimap, saved)
	end
end

-- `hooksecurefunc(Minimap, "SetZoom", ...)` -- the OBJECT+METHOD 3-arg
-- form -- never fires on this client: bare `hooksecurefunc` isn't a
-- global function here at all, and AceHook-3.0's `:SecureHook(obj,
-- method, handler)` object+method overload is independently confirmed
-- broken elsewhere in this project too, so neither variant works for this
-- call shape. Actual zooming isn't affected either way -- `StepZoom`
-- below calls `Minimap:SetZoom()` directly, a real native API call that
-- works regardless of any hook -- only the SIDE EFFECTS that would run
-- via a hook (persisting the zoom level, the auto-reset timer) would be
-- silently inert.
--
-- Polling (this project's own established fallback for exactly this
-- class of problem) is used instead of any hook variant -- deliberately
-- NOT scoped to only our own StepZoom-triggered changes, since the whole
-- point is to also catch Blizzard's own native auto-zoom (e.g. entering
-- an instance), something a direct call from StepZoom alone could never
-- observe.
local lastKnownZoom

local function PollMinimapZoom()
	local ok, zoom = pcall(Minimap.GetZoom, Minimap)
	if ok and zoom and zoom ~= lastKnownZoom then
		lastKnownZoom = zoom
		OnMinimapSetZoom(nil, zoom)
	end
end

local function StepZoom(step)
	local now = GetTime()
	if now - lastZoomTime < ZOOM_DEBOUNCE then
		return
	end

	local ok, zoom = pcall(Minimap.GetZoom, Minimap)
	if not ok then
		return
	end

	lastZoomTime = now
	local newZoom = zoom + step
	pcall(Minimap.SetZoom, Minimap, newZoom)
	-- Instant response for our OWN zoom changes, not waiting on the next
	-- poll tick -- the poll (above) still exists as the catch-all for
	-- any OTHER source of a zoom change.
	lastKnownZoom = newZoom
	OnMinimapSetZoom(nil, newZoom)
end

-- Defensive arg reading, matching LibConfig-1.0's own OnMouseWheel handler
-- (LibConfig-1.0.lua:531-536) -- delta can arrive as the global `arg1`
-- instead of a normal function argument depending on client/invocation
-- path, so check both rather than trusting one.
local function OnMouseWheel(a1, a2)
	local delta = arg1
	if type(a1) == "number" then delta = a1 end
	if type(a2) == "number" then delta = a2 end
	if type(delta) ~= "number" then delta = 0 end

	if delta ~= 0 then
		StepZoom(delta > 0 and 1 or -1)
	end
end

local function CreateZoomButton(parent, label, anchorPoint, xOff, step)
	local size = HEADER_HEIGHT - 4

	local btn = CreateFrame("Button", nil, parent)
	btn:SetWidth(size)
	btn:SetHeight(size)
	btn:SetPoint(anchorPoint, parent, anchorPoint, xOff, -2)
	pcall(btn.SetBackdrop, btn, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(btn.SetBackdropColor, btn, 0.15, 0.15, 0.15, 1)
	pcall(btn.SetBackdropBorderColor, btn, 0, 0, 0, 1)

	local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("CENTER", btn, "CENTER", 0, 0)
	text:SetText(label)

	btn:SetScript("OnClick", function() StepZoom(step) end)

	return btn
end

-- "Minimap Buttons": calendar/mail/battlefield are pre-existing native
-- Blizzard frames already parented to Minimap -- we just reposition/
-- rescale them, matching real ElvUI's Minimap.lua (source/ElvUI-vanilla/
-- ElvUI/Modules/Maps/Minimap.lua:209-235), minus its `E:Point` wrapper
-- (no such core helper exists in this project yet -- plain SetPoint is
-- equivalent for our purposes, just without whatever pixel-perfect
-- scaling adjustment E:Point additionally does).
local ICON_FRAMES = {
	calendar = "GameTimeFrame",
	mail = "MiniMapMailFrame",
	battlefield = "MiniMapBattlefieldFrame",
}

-- Icon frames (GameTimeFrame/MiniMapMailFrame/MiniMapBattlefieldFrame)
-- are pre-existing native Blizzard children of Minimap; repositioning
-- them here needs both a frame-strata and frame-level fix below to avoid
-- being visually occluded by the reparented Minimap frame (see
-- UpdateIcons' own comment on that).

function M:UpdateIcons()
	local icons = E.db.general.minimap.icons
	if not icons then return end

	for key, frameName in pairs(ICON_FRAMES) do
		local frame = _G[frameName]
		if frame then
			if key == "calendar" and E.private.general.minimap.hideCalendar then
				pcall(frame.Hide, frame)
			else
				local cfg = icons[key] or {}
				local pos = cfg.position or "TOPRIGHT"
				pcall(frame.ClearAllPoints, frame)
				pcall(frame.SetPoint, frame, pos, Minimap, pos, cfg.xOffset or 0, cfg.yOffset or 0)
				pcall(frame.SetScale, frame, cfg.scale or 1)

				-- `Minimap` is REPARENTED onto `holder` in M:Initialize
				-- (`Minimap:SetParent(holder)`) -- reparenting changes a
				-- frame's PARENT, not its own STRATA, so `Minimap` still
				-- carries whatever strata it had as an original
				-- `MinimapCluster` child, while these icon frames are never
				-- touched and keep their own original strata. STRATA takes
				-- priority over LEVEL in WoW's own compositing order -- a
				-- frame in a LOWER strata can never render above one in a
				-- HIGHER strata, at ANY frame level -- so an icon whose
				-- strata ends up below Minimap's gets visually occluded by
				-- the square Minimap frame wherever they overlap, and
				-- bumping its frame LEVEL alone (which only matters WITHIN
				-- one strata) can't fix that. Explicitly copying `Minimap`'s
				-- own current strata onto each icon guarantees they share a
				-- strata with it, making the frame-level bump below
				-- meaningful.
				local okStrata, minimapStrata = pcall(Minimap.GetFrameStrata, Minimap)
				if okStrata and minimapStrata then
					pcall(frame.SetFrameStrata, frame, minimapStrata)
				end

				-- Bumping the icon's level above Minimap's current level --
				-- same technique used for wheelCatcher below -- puts it
				-- back on top regardless of what reparenting changed the
				-- ordering to. Applied to all three icons for consistency,
				-- even though only the calendar icon was ever confirmed
				-- affected.
				local okLevel, minimapLevel = pcall(Minimap.GetFrameLevel, Minimap)
				pcall(frame.SetFrameLevel, frame, (okLevel and minimapLevel or 0) + 5)

				-- Real ElvUI only force-Shows the calendar icon (tied to
				-- hideCalendar above) -- mail/battlefield are deliberately
				-- left alone here, still governed by Blizzard's own native
				-- visibility logic (new-mail flag / BG-queue-pop): a
				-- blanket Show() on all three would make the mail icon
				-- appear with no unread mail, and a PvP-queue icon appear
				-- unqueued. Repositioning/rescaling a currently-hidden icon
				-- here is harmless -- SetPoint/SetScale don't affect
				-- Show/Hide state, so it's already correctly positioned for
				-- whenever Blizzard's own code does decide to show it.
				if key == "calendar" then
					pcall(frame.Show, frame)
				end
			end
		end
	end
end

-- Location Text visibility (SHOW/HIDE/MOUSEOVER) -- purely a Show()/Hide()
-- decision, no font involved, so unlike locationFont/Size/Outline this is
-- fully implementable regardless of UA's font limitations.
function M:ApplyLocationText()
	if not self.zoneText then return end

	local mode = E.db.general.minimap.locationText or "MOUSEOVER"
	if mode == "HIDE" then
		self.zoneText:Hide()
	elseif mode == "SHOW" then
		self.zoneText:Show()
	else -- MOUSEOVER: hidden by default, shown by the OnEnter/OnLeave hook
		-- set up once in Initialize below.
		if not self.mouseOver then
			self.zoneText:Hide()
		end
	end
end

-- Live-appliable settings (size, locationText, resetZoom) -- called once
-- at the end of Initialize and again from ElvUI_Config whenever one of
-- these changes, so none of them need a /reload (matches real ElvUI's own
-- MM:UpdateSettings, called directly from its config `set` functions).
-- `enable` is NOT here -- see the file-header note on why that one stays
-- reload-required.
-- Nudge LibDBIcon-1.0 into re-placing every minimap button it owns.
--
-- Needed twice: once at Initialize (in case an icon was positioned before
-- GetMinimapShape above could be consulted -- e.g. a library copy that had
-- already passed its PLAYER_LOGIN pass), and again whenever the minimap is
-- RESIZED, since the buttons are anchored by a computed CENTER offset and
-- do not follow the map's new edge on their own.
--
-- SetButtonRadius(lib.radius) is a no-op re-set of the current radius whose
-- side effect is exactly the loop we want -- updatePosition for every
-- button -- without reaching into the library's internals. ElvUI does not
-- vendor LibDBIcon; this is a purely optional lookup, so everything here is
-- guarded and silently does nothing when no such library is loaded.
function M:UpdateMinimapButtons()
	if type(LibStub) ~= "function" and type(LibStub) ~= "table" then return end
	local ok, lib = pcall(LibStub, "LibDBIcon-1.0", true)
	if not ok or not lib or not lib.SetButtonRadius then return end
	pcall(lib.SetButtonRadius, lib, lib.radius or 5)
end

function M:UpdateSettings()
	if not self.holder then return end -- module disabled, nothing built

	local size = E.db.general.minimap.size or 176
	self.holder:SetWidth(size + 8)
	self.holder:SetHeight(size + 8 + HEADER_HEIGHT)
	pcall(Minimap.SetWidth, Minimap, size)
	pcall(Minimap.SetHeight, Minimap, size)
	if self.zoneText then
		self.zoneText:SetWidth(size - 32)
	end

	self:ApplyLocationText()
	self:UpdateIcons()
	self:UpdateMinimapButtons()

	-- E.db.datatexts.minimapPanels -- matches real ElvUI's own
	-- ElvUI_Config/DataTexts.lua "Minimap Panels" toggle
	-- (`E:GetModule("Minimap"):UpdateSettings()` is literally its own
	-- set-function target, same call site convention followed here).
	-- Resolved by global name, as real ElvUI does: the frames are built by the
	-- Layout module, which initializes AFTER this one, so the first call from
	-- Initialize() legitimately finds nothing -- Layout applies the same
	-- setting itself once the panels exist.
	local lminipanel, rminipanel = _G.LeftMiniPanel, _G.RightMiniPanel
	if E.db.datatexts and not E.db.datatexts.minimapPanels then
		if lminipanel then lminipanel:Hide() end
		if rminipanel then rminipanel:Hide() end
	else
		if lminipanel then lminipanel:Show() end
		if rminipanel then rminipanel:Show() end
	end

	if not (E.db.general.minimap.resetZoom and E.db.general.minimap.resetZoom.enable) then
		CancelZoomResetTimer()
	end
end

function M:Initialize()
	if not E.private.general.minimap.enable then
		return
	end

	local size = E.db.general.minimap.size or 176

	local holder = CreateFrame("Frame", "ElvUIMinimapHolder", UIParent)
	holder:SetWidth(size + 8)
	holder:SetHeight(size + 8 + HEADER_HEIGHT)
	holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -4, -4)

	-- Movable via /moveui (Core/Movers.lua) -- real ElvUI registers its own
	-- Minimap holder as a mover too (source/ElvUI-vanilla/ElvUI/Modules/
	-- Maps/Minimap.lua:317: `E:CreateMover(MMHolder, "MinimapMover",
	-- MINIMAP_LABEL, ...)`). Same mover name ("MinimapMover") as real
	-- ElvUI for profile-format compatibility.
	E:CreateMover(holder, "MinimapMover", "Minimap")

	pcall(holder.SetBackdrop, holder, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(holder.SetBackdropColor, holder, 0.1, 0.1, 0.1, 1)
	pcall(holder.SetBackdropBorderColor, holder, 0, 0, 0, 1)

	pcall(Minimap.SetParent, Minimap, holder)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("BOTTOM", holder, "BOTTOM", 0, 4)
	pcall(Minimap.SetWidth, Minimap, size)
	pcall(Minimap.SetHeight, Minimap, size)
	pcall(Minimap.SetMaskTexture, Minimap, "Interface\\ChatFrame\\ChatFrameBackground")

	HideChrome()

	-- Zone text -- header strip ABOVE the map, not overlaid on it (see the
	-- UA note at the top of this file for why).
	local zoneText = holder:CreateFontString("ElvUIMinimapZoneText", "OVERLAY", "GameFontNormal")
	zoneText:SetPoint("TOP", holder, "TOP", 0, -4)
	zoneText:SetWidth(size - 32)
	zoneText:SetJustifyH("CENTER")
	self.zoneText = zoneText

	-- MOUSEOVER visibility: hooked (not SetScript) so we don't clobber
	-- whatever native OnEnter/OnLeave the Minimap widget already has (e.g.
	-- its own tooltip). AceHook-3.0's own :HookScript refuses Minimap here
	-- (its :HasScript("OnEnter"/"OnLeave") wrongly returns false on this
	-- client even though :GetScript/:SetScript both work fine on the same
	-- frame+script) -- same binding-level bug already seen on HonorFrame.
	-- Use Skins' fallback-aware S:TryHookScript instead of a bare
	-- E:HookScript: it tries AceHook first, then falls back to a manual
	-- native :SetScript chain that preserves any existing handler.
	local S = E:GetModule("Skins")
	S:TryHookScript(Minimap, "OnEnter", function()
		self.mouseOver = true
		if E.db.general.minimap.locationText == "MOUSEOVER" and self.zoneText then
			self.zoneText:Show()
		end
	end)
	S:TryHookScript(Minimap, "OnLeave", function()
		self.mouseOver = false
		if E.db.general.minimap.locationText == "MOUSEOVER" and self.zoneText then
			self.zoneText:Hide()
		end
	end)

	local function UpdateZoneText()
		local ok, zoneName = pcall(GetMinimapZoneText)
		if not ok or not zoneName or zoneName == "" then
			ok, zoneName = pcall(GetZoneText)
		end
		zoneText:SetText((ok and zoneName) or "")

		local okPvp, pvpType = pcall(GetZonePVPInfo)
		local color = (okPvp and ZONE_COLORS[pvpType]) or ZONE_COLORS.default
		zoneText:SetTextColor(color[1], color[2], color[3])
	end

	UpdateZoneText()
	M:RegisterEvent("ZONE_CHANGED", UpdateZoneText)
	M:RegisterEvent("ZONE_CHANGED_INDOORS", UpdateZoneText)
	M:RegisterEvent("ZONE_CHANGED_NEW_AREA", UpdateZoneText)
	M:RegisterEvent("PLAYER_ENTERING_WORLD", UpdateZoneText)

	-- Zoom: wheel via a ScrollFrame-type catcher (see the UA test results
	-- note at the top of this file for why ScrollFrame specifically), plus
	-- small +/- buttons in the header strip as a guaranteed fallback.
	local wheelCatcher = CreateFrame("ScrollFrame", "ElvUIMinimapWheelCatcher", holder)
	wheelCatcher:SetAllPoints(Minimap)
	pcall(wheelCatcher.SetFrameLevel, wheelCatcher, (Minimap:GetFrameLevel() or 0) + 5)
	pcall(wheelCatcher.EnableMouseWheel, wheelCatcher, true)
	wheelCatcher:SetScript("OnMouseWheel", OnMouseWheel)

	CreateZoomButton(holder, "-", "TOPLEFT", 2, -1)
	CreateZoomButton(holder, "+", "TOPRIGHT", -2, 1)

	-- Polling replaces the confirmed-broken hooksecurefunc(Minimap,
	-- "SetZoom", ...) -- see PollMinimapZoom's own header comment for the
	-- full reasoning. Initialize lastKnownZoom to the CURRENT zoom first,
	-- so the very first poll tick doesn't misfire OnMinimapSetZoom for a
	-- "change" that never actually happened.
	local okInitZoom, initZoom = pcall(Minimap.GetZoom, Minimap)
	lastKnownZoom = okInitZoom and initZoom or nil
	E:ScheduleRepeatingTimer(PollMinimapZoom, 0.3)
	M:RegisterEvent("MINIMAP_UPDATE_ZOOM", OnMinimapUpdateZoom)

	self.holder = holder
	self.wheelCatcher = wheelCatcher

	-- LeftMiniPanel/RightMiniPanel are NOT created here: real ElvUI builds
	-- them in its Layout module, and so do we (ElvUI/Layout/Layout.lua's
	-- LO:CreateMinimapPanels), which runs in the second init tier, i.e. after
	-- this function has published `self.holder`. This module keeps what real
	-- ElvUI's Minimap module also keeps: their show/hide (UpdateSettings) and
	-- the size they are derived from (E.db.general.minimap.size).

	-- Applies locationText's initial visibility (zoneText was created
	-- already-shown above; MOUSEOVER mode hides it here until hovered).
	self:UpdateSettings()

	-- PERIODIC RESWEEP: the GameTimeFrame strata/level fix (see
	-- UpdateIcons above) only runs once here, at the end of Initialize(),
	-- early in the login sequence. If Blizzard's own GameTimeFrame_Update
	-- (or equivalent, likely tied to calendar data becoming available,
	-- which may not be ready yet at that point) resets its strata/level
	-- sometime AFTER that single call, the fix is silently undone with
	-- nothing to reapply it -- same class of bug as ActionBars/PetBar
	-- buttons (Blizzard's own code re-asserting some native default AFTER
	-- a one-time fix at login, undone again by the NEXT native update --
	-- ExhaustionTick, ActionButton NormalTexture). Re-running the
	-- (idempotent, cheap) icon sweep periodically catches whatever native
	-- reset happens after the one-shot pass, same reasoning/pattern as
	-- ActionBars.lua's own HideChrome/StyleButton resweep.
	-- Capped at 10 runs (30s total at this 3s interval) -- see
	-- ElvUI.Util.ScheduleLimitedSweep (Core/Util.lua): whatever native
	-- reset this is catching happens once, in a short window after login,
	-- not indefinitely.
	ElvUI.Util.ScheduleLimitedSweep(function() M:UpdateIcons() end, 3, 10)
end

E:RegisterInitialModule(M:GetName(), function() M:Initialize() end)
