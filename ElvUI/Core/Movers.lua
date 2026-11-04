-- ElvUI Movers: lets the user drag a registered frame to a new position and
-- persists it, plus arrow-key nudging with a live coordinate readout for
-- pixel-precise placement.
--
-- STORAGE FORMAT DELIBERATELY MATCHES REAL ELVUI EXACTLY (
-- ElvUI-vanilla/ElvUI/Core/movers.lua) -- this is a hard project
-- requirement, not a style choice: a real ElvUI SavedVariables profile
-- must eventually be droppable into this addon as-is. Real ElvUI stores
-- `E.db.movers[name] = "point,anchorName,secondaryPoint,x,y"` (a single
-- comma-joined STRING, via `format("%s,%s,%s,%d,%d", point,
-- anchor:GetName(), secondaryPoint, E:Round(x), E:Round(y))`) -- this
-- file uses the exact same table name, key shape (a mover "name" string,
-- e.g. ActionBars uses "ElvAB_"..id, matching real ElvUI's own
-- ActionBars.lua exactly) and string format, NOT a custom table shape.
-- One known gap, not fixable here: real ElvUI anchors everything to its
-- own custom `E.UIParent` frame, which this project doesn't have -- a
-- real profile's saved anchor name "ElvUIParent" will not resolve on
-- this addon and falls back to plain UIParent (see ParsePositionString
-- below) rather than erroring.
--
-- The drag itself and the alignment grid come from LibSnapGrid-1.0 (see the
-- "Dragging" and "Alignment grid" sections below): the frame snaps to the
-- grid lines, the screen edges and the screen's centre lines, which real
-- ElvUI approximates with LibSimpleSticky-1.0.
--
-- Pixel-precise nudging (arrow keys + a live coordinate readout while
-- dragging) is the IDEA from real ElvUI's own mover system (there: mouse
-- wheel + a "nudge window") ported to a mechanism actually reliable on
-- UA -- mouse wheel input is unreliable on UA.
--
-- Feature set: drag handle with grid/edge/centre snapping, save/restore
-- position (real-ElvUI-format), arrow-key nudge, live coordinate readout
-- while dragging, quadrant-relative anchoring (see CalculateMoverPoint
-- below -- ported from real ElvUI's own CalculateMoverPoints), an
-- edit-mode overlay panel with two buttons (`CreateMoverPanel` -- and
-- unlike either reference, DRAGGABLE), and an alignment grid (real
-- ElvUI's own `E.db.gridSize` divisor convention). Deliberately NOT
-- ported: magnet/snap-to-other-movers.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local Compat = ElvUI.Compat

E.movers = E.movers or {}
E.moverOrder = E.moverOrder or {}
E.moversUnlocked = E.moversUnlocked or false
E.activeMover = E.activeMover or nil

-- Modules that HIDE their own frame under some condition need to know
-- when move mode toggles, so they can keep it visible while unlocked --
-- otherwise the frame takes its own drag handle down with it (the handle
-- is created as a CHILD of the frame it moves, see CreateHandle below)
-- and can never be positioned at all. A module could instead poll
-- `E.moversUnlocked` (UnitFrames.lua's PetTarget does), but that means a
-- visible lag for a module on a slower poll (DataBars polls every 2s).
--
-- A plain callback list rather than a hardcoded call into a specific
-- module, so Core/ stays unaware of which modules care.
E.moverStateCallbacks = E.moverStateCallbacks or {}

--- func  called with no arguments every time movers are unlocked or
---       locked, AFTER E.moversUnlocked has been updated (so the
---       callback can just read it).
function E:RegisterMoverStateCallback(func)
	if type(func) ~= "function" then return end
	table.insert(self.moverStateCallbacks, func)
end

local function FireMoverStateCallbacks()
	local i
	for i = 1, table.getn(E.moverStateCallbacks) do
		pcall(E.moverStateCallbacks[i])
	end
end

-- ===========================================================================
-- Anchor capture/apply, real-ElvUI-format
--
-- On UA, frame:GetPoint() returns the relative frame as a NAME STRING rather
-- than a frame object, so the name is resolved defensively below and stored;
-- ApplyPositionString looks it back up in _G.
--
-- Y needs no sign correction on either client: GetPoint's offset can be
-- handed straight back to SetPoint for the same visual position. UA reports a
-- different sign here than the real 1.12.1 client does, but it is
-- self-consistent, which is all a save/restore round-trip needs.
--
-- Never recapture a point and immediately clear/re-apply it (UnrealUI's own
-- documented failed approach) -- a drop is captured and stored, and the frame
-- is left exactly where the user released it.
-- ===========================================================================

local function CaptureFramePositionParts(frame)
	if not frame or not frame.GetPoint then return nil end
	local ok, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
	if not ok or type(point) ~= "string" then return nil end

	local relativeName = "UIParent"
	if type(relative) == "string" then
		relativeName = relative
	elseif type(relative) == "table" and relative.GetName then
		local okName, name = pcall(relative.GetName, relative)
		if okName and name then relativeName = name end
	end

	x = tonumber(x) or 0
	y = tonumber(y) or 0

	return point, relativeName, relativePoint or point, E:Round(x), E:Round(y)
end

-- Real-ElvUI-format string: "point,anchorName,secondaryPoint,x,y".
local function CaptureFramePosition(frame)
	local point, relativeName, relativePoint, x, y = CaptureFramePositionParts(frame)
	if not point then return nil end
	return string.format("%s,%s,%s,%d,%d", point, relativeName, relativePoint, x, y)
end

local function ParsePositionString(str)
	if type(str) ~= "string" then return nil end
	local parts = {}
	local s
	for s in Compat.gmatch(str, "[^,]+") do
		table.insert(parts, s)
	end
	local point, relativeName, relativePoint = parts[1], parts[2], parts[3]
	if not point then return nil end
	return point, relativeName, relativePoint or point, tonumber(parts[4]) or 0, tonumber(parts[5]) or 0
end

-- Applies a real-ElvUI-format position string via SetPoint. x/y are already in
-- SetPoint's own convention, whether they came from
-- CaptureFramePositionParts or ParsePositionString, so nothing is adjusted
-- here. `relativeName` falls back to UIParent if it doesn't
-- resolve to a real frame (covers a real ElvUI profile's "ElvUIParent",
-- which doesn't exist in this project -- see the file header).
local function ApplyPositionString(frame, str)
	local point, relativeName, relativePoint, x, y = ParsePositionString(str)
	if not point then return false end
	local relativeFrame = _G[relativeName] or UIParent
	local ok = pcall(function()
		frame:ClearAllPoints()
		frame:SetPoint(point, relativeFrame, relativePoint, x, y)
	end)
	return ok
end

-- ===========================================================================
-- Quadrant-relative anchor (nearest-edge/corner instead of a single fixed
-- point)
--
-- Instead of always saving an offset from horizontal CENTER (which can
-- turn into a huge absolute offset from an edge on a wide screen), this
-- picks whichever screen edge/corner the frame is actually closest to and
-- stores a SMALL offset from THAT. Doesn't fully solve a UI-scale change
-- (real ElvUI doesn't either), but a small edge-relative offset drifts far
-- less across a resolution change than a large offset from a single fixed
-- point would.
--
-- Ported from real ElvUI's own E:CalculateMoverPoints
-- (ElvUI-vanilla/ElvUI/Core/movers.lua:244-306) -- same horizontal
-- thirds, same GetCenter/GetLeft/GetRight/GetTop/GetBottom reads. One
-- deliberate difference: real ElvUI splits the screen vertically into
-- halves (TOP/BOTTOM only), this splits it into thirds like the
-- horizontal axis, so a frame in the middle third is anchored to the
-- vertical centre (LEFT, CENTER, RIGHT). Otherwise a centred frame keeps a
-- large offset from the top or bottom edge and drifts off centre whenever
-- the screen height in UI units changes (a UI scale or resolution change).
-- The stored string stays in real ElvUI's format; LEFT/CENTER/RIGHT are
-- ordinary anchor points real ElvUI also loads.
-- Deliberately NOT using GetPoint() here at all (unlike
-- CaptureFramePositionParts above): GetCenter/GetLeft/GetRight/GetTop/
-- GetBottom are measured against UIParent, so the point they produce is
-- independent of whatever anchor the frame currently carries. Real
-- ElvUI's own version also carries `nudgeX`/`nudgeY` params and a
-- `positionOverride` branch (their equivalent of a mover forcibly
-- anchored to another frame, e.g. a bar's own container) -- neither
-- ported, not needed here.
local function CalculateMoverPoint(frame)
	local okCenter, cx, cy = pcall(frame.GetCenter, frame)
	if not okCenter or not cx or not cy then return nil end

	local okRight, screenWidth = pcall(UIParent.GetRight, UIParent)
	local okTop, screenHeight = pcall(UIParent.GetTop, UIParent)
	if not okRight or not okTop or not screenWidth or not screenHeight then return nil end

	local LEFT = screenWidth / 3
	local RIGHT = screenWidth * 2 / 3
	local TOP = screenHeight * 2 / 3
	local BOTTOM = screenHeight / 3

	local point, x, y

	if cy >= TOP then
		point = "TOP"
		local okFrameTop, frameTop = pcall(frame.GetTop, frame)
		y = -(screenHeight - (okFrameTop and frameTop or cy))
	elseif cy <= BOTTOM then
		point = "BOTTOM"
		local okBottom, bottom = pcall(frame.GetBottom, frame)
		y = okBottom and bottom or cy
	else
		point = ""
		y = cy - screenHeight / 2
	end

	if cx >= RIGHT then
		point = point.."RIGHT"
		local okFrameRight, frameRight = pcall(frame.GetRight, frame)
		x = (okFrameRight and frameRight or cx) - screenWidth
	elseif cx <= LEFT then
		point = point.."LEFT"
		local okLeft, left = pcall(frame.GetLeft, frame)
		x = okLeft and left or cx
	else
		x = cx - screenWidth / 2
	end

	if point == "" then point = "CENTER" end

	return point, E:Round(x), E:Round(y)
end

-- Real-ElvUI-format string using the quadrant-relative point above,
-- always relative to UIParent (matches this project's convention
-- throughout -- see the file header).
local function CaptureMoverPosition(frame)
	local point, x, y = CalculateMoverPoint(frame)
	if not point then return nil end
	return string.format("%s,UIParent,%s,%d,%d", point, point, x, y), point, x, y
end

-- ===========================================================================
-- Dragging
--
-- The drag is LibSnapGrid-1.0's (`AttachDrag` on the handle): the frame is
-- re-anchored TOPLEFT to UIParent's BOTTOMLEFT from the cursor on every
-- frame (never through StartMoving), its nearer edge snaps onto a grid line
-- or screen edge and its centre onto the screen's centre lines (a red guide
-- line shows while centred), Shift drags freely, and it is kept on screen.
-- The library also owns the per-client start/stop detection: OnDragStart on
-- 1.12.1, OnMouseDown plus a screen-wide hit rectangle on Unreal Azeroth.
--
-- On release the position is converted to this file's quadrant-relative
-- anchor (CaptureMoverPosition), stored, and re-applied, so the live anchor
-- is the stored one rather than the library's temporary TOPLEFT anchor.
--
-- The library is looked up on first use rather than at file load, so a copy
-- registered by an addon that loads after this one is found as well.
-- ===========================================================================
local SnapGrid

local function GetSnapGrid()
	if not SnapGrid and LibStub then
		SnapGrid = LibStub("LibSnapGrid-1.0", true)
	end
	return SnapGrid
end

local dragTimerHandle

local function UpdateDragReadout()
	local entry = E.activeMover
	if not entry or not entry.dragging or not entry.handle or not entry.handle.label then return end
	local point, x, y = CalculateMoverPoint(entry.frame)
	if point then
		pcall(entry.handle.label.SetText, entry.handle.label,
			string.format("%s\n%s  %d, %d", entry.label, point, x, y))
	end
end

-- The library places the frame in UIParent's units, which is only correct
-- for a frame drawn at UIParent's scale. A disabled bar is shrunk to a
-- near-zero scale instead of being hidden, and dragging it is refused.
local function HasUIParentScale(frame)
	local okFrame, frameScale = pcall(frame.GetEffectiveScale, frame)
	local okParent, parentScale = pcall(UIParent.GetEffectiveScale, UIParent)
	frameScale, parentScale = tonumber(frameScale), tonumber(parentScale)
	if not okFrame or not okParent or not frameScale or not parentScale then return true end
	return math.abs(frameScale - parentScale) < 0.001
end

-- LibSnapGrid onStart: returning false refuses the drag.
local function BeginDrag(entry)
	if not HasUIParentScale(entry.frame) then return false end
	E.activeMover = entry
	entry.dragging = true
	if not dragTimerHandle then
		dragTimerHandle = E:ScheduleRepeatingTimer(UpdateDragReadout, 0.1)
	end
	return true
end

-- LibSnapGrid onStop. Idempotent: HideHandle may also call it.
local function EndDrag(entry)
	if not entry.dragging then return end
	entry.dragging = false

	if dragTimerHandle then
		E:CancelTimer(dragTimerHandle)
		dragTimerHandle = nil
	end
	if entry.handle and entry.handle.label then
		pcall(entry.handle.label.SetText, entry.handle.label, entry.label)
	end

	local str = CaptureMoverPosition(entry.frame)
	if not str then return end
	E.db.movers[entry.id] = str
	ApplyPositionString(entry.frame, str)
end

-- Arrow-key nudging for pixel-precise placement. Real ElvUI's own
-- equivalent is the mouse wheel, which is unreliable on UA -- this ports
-- the IDEA, not the mechanism. A shown, keyboard-enabled plain Frame with
-- OnKeyDown is reliable on UA (matches UnrealUI's own edit-mode key
-- frame, UnrealUI/core/mover.lua -- must be a plain Frame, not a
-- Button, and must use OnKeyDown, not OnKeyUp).
-- Nudges by applying the raw pixel delta to whatever anchor the frame
-- currently has, then RECOMPUTES the quadrant-relative point fresh
-- (CalculateMoverPoint) before saving -- not just adding dx/dy to the
-- last-saved x/y under the OLD point, since a big enough nudge can push
-- the frame across a quadrant boundary (e.g. from the middle third into
-- the right third), and the stored anchor needs to follow that.
local function NudgeActiveMover(dx, dy)
	local entry = E.activeMover
	if not entry or entry.dragging then return false end

	local point, relativeName, relativePoint, x, y
	local saved = E.db.movers[entry.id]
	if saved then
		point, relativeName, relativePoint, x, y = ParsePositionString(saved)
	end
	if not point then
		point, relativeName, relativePoint, x, y = CaptureFramePositionParts(entry.frame)
	end
	if not point then return false end

	local relativeFrame = _G[relativeName] or UIParent
	pcall(function()
		entry.frame:ClearAllPoints()
		entry.frame:SetPoint(point, relativeFrame, relativePoint, x + dx, y + dy)
	end)

	local newStr, newPoint, newX, newY = CaptureMoverPosition(entry.frame)
	if not newStr then return false end
	E.db.movers[entry.id] = newStr

	if entry.handle and entry.handle.label then
		pcall(entry.handle.label.SetText, entry.handle.label,
			string.format("%s\n%s  %d, %d", entry.label, newPoint, newX, newY))
	end
	return true
end

-- Same dual-signature defensiveness as everywhere else keyboard/mouse args
-- are read in this project -- modern clients may pass the key as a
-- function argument, 1.12.1-style ones may only expose the implicit
-- global `arg1`.
local function ResolveKey(a, b)
	if type(a) == "string" then return a end
	if type(b) == "string" then return b end
	local legacy = _G.arg1
	if type(legacy) == "string" then return legacy end
	return nil
end

local keyFrame

local function CreateKeyFrame()
	local ok, frame = pcall(CreateFrame, "Frame", "ElvUIMoverKeys", UIParent)
	if not ok or not frame then return nil end
	pcall(frame.SetAllPoints, frame, UIParent)
	pcall(frame.SetFrameStrata, frame, "FULLSCREEN_DIALOG")
	pcall(frame.EnableKeyboard, frame, true)
	pcall(frame.EnableMouse, frame, false)

	frame:SetScript("OnKeyDown", function(a, b)
		local key = ResolveKey(a, b)
		local step = 1
		if IsShiftKeyDown and IsShiftKeyDown() then step = 10 end
		if key == "LEFT" then
			NudgeActiveMover(-step, 0)
		elseif key == "RIGHT" then
			NudgeActiveMover(step, 0)
		elseif key == "UP" then
			NudgeActiveMover(0, step)
		elseif key == "DOWN" then
			NudgeActiveMover(0, -step)
		elseif key == "ESCAPE" then
			-- Best-effort only -- see CreateMoverPanel below for the
			-- actual guaranteed way out.
			E:LockMovers()
		end
	end)

	frame:Hide()
	return frame
end

-- On Unreal Azeroth the key frame's OnKeyDown does not stop an arrow key from
-- also running its key binding, so every nudge would move or turn the
-- character too (UP/DOWN/LEFT/RIGHT are movement keys by default). The legacy
-- client consumes the key in the frame and needs none of this.
--
-- The chords are unbound for the duration of move mode and rebound on exit.
-- SaveBindings is never called, so the change stays in the live key map only
-- and never reaches the player's saved binding set. The removed commands are
-- recorded in `E.global.moverBindings` rather than a local, so a /reload or
-- disconnect while move mode is open still gets them back at the next login
-- (RestoreArrowBindings below, run as an initial module).
local ARROW_CHORDS = {
	"UP", "DOWN", "LEFT", "RIGHT",
	"SHIFT-UP", "SHIFT-DOWN", "SHIFT-LEFT", "SHIFT-RIGHT",
}

local function SuppressArrowBindings()
	if not Compat.isUA then return end
	if type(GetBindingAction) ~= "function" or type(SetBinding) ~= "function" then return end
	if not E.global then return end
	E.global.moverBindings = E.global.moverBindings or {}
	local store = E.global.moverBindings

	local i
	for i = 1, table.getn(ARROW_CHORDS) do
		local chord = ARROW_CHORDS[i]
		-- A chord already recorded is still unbound from an earlier unlock
		-- that never got its matching lock; reading it again would record
		-- "" and lose the real command.
		if not store[chord] then
			local ok, action = pcall(GetBindingAction, chord)
			if ok and type(action) == "string" and action ~= "" then
				store[chord] = action
				pcall(SetBinding, chord)
			end
		end
	end
end

-- Rebinds only chords that are still empty: if the client reloaded its saved
-- binding set in the meantime, the chord already carries its command and is
-- left alone.
local function RestoreArrowBindings()
	local store = E.global and E.global.moverBindings
	if type(store) ~= "table" then return end
	if type(GetBindingAction) ~= "function" or type(SetBinding) ~= "function" then return end

	local chord, action
	for chord, action in pairs(store) do
		local ok, current = pcall(GetBindingAction, chord)
		if ok and (current == nil or current == "") then
			pcall(SetBinding, chord, action)
		end
	end
	E.global.moverBindings = {}
end

E:RegisterInitialModule("MoverBindings", RestoreArrowBindings)

-- ===========================================================================
-- Mover control panel
--
-- A proper draggable window with two buttons (Lock Movers, Reset All),
-- replacing two loose screen-pinned buttons. Real ElvUI has
-- `ElvUIMoverPopupWindow`; `UnrealUI/core/mover.lua` has
-- `CreateEditPanel` (title + three hint lines + a Save/Exit and a Reset
-- button). This panel follows UnrealUI's own layout, with one addition
-- neither reference has: it is DRAGGABLE, so it can be moved out of the
-- way of whatever it happens to be covering.
--
-- WHY THE PANEL IS NOT ITSELF A MOVER: it belongs to the MODE, not to the
-- layout -- UnrealUI's own comment makes the same call. Registering it
-- would put it in `E.db.movers`, which has to stay format-compatible with
-- a real ElvUI profile, under a key real ElvUI doesn't have. Its position
-- is remembered in `E.global` instead (this addon's own store, never part
-- of the profile) -- same reasoning as the Auras module's own migration
-- marker.
--
-- A MOUSE-clickable exit must always exist: a shown, keyboard-enabled
-- frame on UA swallows ALL keyboard input while active, chat included --
-- so a player stuck in move mode with no clickable exit can't even type
-- `/moveui` to get back out. "Lock Movers" below is that guaranteed way
-- out, regardless of whether ESCAPE reaches CreateKeyFrame at all.

local moverPanel

local PANEL_WIDTH = 300
local PANEL_HEIGHT = 132

local function SaveMoverPanelPosition()
	if not moverPanel then return end
	local okPoint, point, _, relativePoint, x, y = pcall(moverPanel.GetPoint, moverPanel, 1)
	if not okPoint or not point then return end
	-- Deliberately NOT routed through this file's own CaptureMoverPosition/
	-- quadrant logic: that exists to keep a HUD element anchored sensibly
	-- across resolution changes, which is irrelevant for a panel that only
	-- exists while move mode is open. A plain point/offset pair is enough,
	-- and keeps the stored shape obviously distinct from `E.db.movers`.
	if not E.global then return end
	E.global.moverPanel = E.global.moverPanel or {}
	local store = E.global.moverPanel
	store.point = point
	store.relativePoint = relativePoint
	store.x = tonumber(x) or 0
	store.y = tonumber(y) or 0
end

local function ApplyMoverPanelPosition()
	if not moverPanel then return end
	local store = E.global and E.global.moverPanel
	pcall(moverPanel.ClearAllPoints, moverPanel)
	if store and store.point then
		pcall(moverPanel.SetPoint, moverPanel, store.point, UIParent,
			store.relativePoint or store.point, store.x or 0, store.y or 0)
	else
		pcall(moverPanel.SetPoint, moverPanel, "TOP", UIParent, "TOP", 0, -120)
	end
end

-- Same low-level drag recipe as Skins.lua's `S:MakeDraggable` (the panel
-- is not snapped to the grid): a throwaway StartMoving/StopMovingOrSizing
-- pair before the real StartMoving, and OnMouseDown to begin rather than
-- OnDragStart (`RegisterForDrag` only fires after 15px of cursor travel on
-- UA and doesn't match the pressed button against the registered list).
-- Both handlers are registered anyway, since whichever fires first simply
-- wins and the second is a no-op.
local function MoverPanelStartDrag()
	if not moverPanel then return end
	if not pcall(moverPanel.SetMovable, moverPanel, true) then return end
	if pcall(moverPanel.StartMoving, moverPanel) then
		pcall(moverPanel.StopMovingOrSizing, moverPanel)
	end
	pcall(moverPanel.StartMoving, moverPanel)
end

local function MoverPanelStopDrag()
	if not moverPanel then return end
	pcall(moverPanel.StopMovingOrSizing, moverPanel)
	SaveMoverPanelPosition()
end

local function CreatePanelButton(parent, name, label, width, onClick)
	local ok, button = pcall(CreateFrame, "Button", name, parent)
	if not ok or not button then return nil end
	pcall(button.SetWidth, button, width)
	pcall(button.SetHeight, button, 24)
	pcall(button.EnableMouse, button, true)

	-- Above the panel's own full-size drag handle (see CreateMoverPanel):
	-- the mouse goes to the topmost mouse-enabled frame under the cursor,
	-- so a higher level here is what lets a click on a BUTTON be a click
	-- rather than the start of a panel drag.
	local okLevel, level = pcall(parent.GetFrameLevel, parent)
	pcall(button.SetFrameLevel, button, (okLevel and tonumber(level) or 1) + 10)

	pcall(button.SetBackdrop, button, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(button.SetBackdropColor, button, 0.15, 0.15, 0.15, 1)
	pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 1)

	local okLabel, text = pcall(button.CreateFontString, button, nil, "OVERLAY", "GameFontNormal")
	if okLabel and text then
		pcall(text.SetPoint, text, "CENTER", button, "CENTER", 0, 0)
		pcall(text.SetText, text, label)
		pcall(text.SetTextColor, text, 1, 0.82, 0)
		button.label = text
	end

	button:SetScript("OnEnter", function()
		pcall(button.SetBackdropBorderColor, button, 1, 0.82, 0, 1)
	end)
	button:SetScript("OnLeave", function()
		pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 1)
	end)
	button:SetScript("OnClick", onClick)

	return button
end

local function CreateMoverPanel()
	local ok, panel = pcall(CreateFrame, "Frame", "ElvUIMoverPanel", UIParent)
	if not ok or not panel then return nil end
	moverPanel = panel

	pcall(panel.SetWidth, panel, PANEL_WIDTH)
	pcall(panel.SetHeight, panel, PANEL_HEIGHT)
	pcall(panel.SetFrameStrata, panel, "FULLSCREEN_DIALOG")
	pcall(panel.SetFrameLevel, panel, 200)
	pcall(panel.EnableMouse, panel, true)
	pcall(panel.SetClampedToScreen, panel, true)

	-- Same panel recipe every skinned window in this addon uses
	-- (Modules/Skins: WHITE8x8 fill + 1px WHITE8x8 edge, 0.05 grey at 0.95
	-- alpha, pure black border) instead of the old buttons' red/orange
	-- blocks, so move mode looks like part of the same UI.
	pcall(panel.SetBackdrop, panel, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(panel.SetBackdropColor, panel, 0.05, 0.05, 0.05, 0.95)
	pcall(panel.SetBackdropBorderColor, panel, 0, 0, 0, 1)

	local okTitle, title = pcall(panel.CreateFontString, panel, nil, "OVERLAY", "GameFontNormal")
	if okTitle and title then
		pcall(title.SetPoint, title, "TOP", panel, "TOP", 0, -10)
		pcall(title.SetText, title, L["Move UI"])
		pcall(title.SetTextColor, title, 1, 0.82, 0)
	end

	-- Three separately placed lines, so a translation keeps each one short
	-- enough for the panel width.
	local hints = {
		L["Drag a highlighted frame to move it."],
		L["Click one, then use the arrow keys"],
		L["to nudge it (hold Shift for 10px)."],
	}
	local i
	for i = 1, 3 do
		local okHint, hint = pcall(panel.CreateFontString, panel, nil, "OVERLAY", "GameFontNormalSmall")
		if okHint and hint then
			pcall(hint.SetPoint, hint, "TOP", panel, "TOP", 0, -30 - (i - 1) * 14)
			pcall(hint.SetText, hint, hints[i])
			pcall(hint.SetTextColor, hint, 0.7, 0.7, 0.7)
		end
	end

	-- Full-panel drag handle, deliberately at a LOWER frame level than the
	-- two buttons above it: dragging by the whole body (not just a title
	-- strip) is more convenient, and the level split is what keeps the
	-- buttons clickable, since the mouse always goes to the topmost
	-- mouse-enabled frame under the cursor.
	local okHandle, handle = pcall(CreateFrame, "Button", nil, panel)
	if okHandle and handle then
		pcall(handle.SetAllPoints, handle, panel)
		pcall(handle.EnableMouse, handle, true)
		pcall(handle.RegisterForDrag, handle, "LeftButton")
		pcall(handle.SetFrameLevel, handle, 201)
		handle:SetScript("OnMouseDown", MoverPanelStartDrag)
		handle:SetScript("OnDragStart", MoverPanelStartDrag)
		handle:SetScript("OnMouseUp", MoverPanelStopDrag)
		handle:SetScript("OnDragStop", MoverPanelStopDrag)
	end

	panel.lockButton = CreatePanelButton(panel, "ElvUIMoverLockButton", L["Lock Movers"], 130,
		function() E:LockMovers() end)
	if panel.lockButton then
		pcall(panel.lockButton.SetPoint, panel.lockButton, "BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
	end

	-- A mouse-clickable reset that's ALWAYS reachable regardless of where a
	-- mover's own handle currently is -- an off-screen mover's handle is,
	-- by definition, off-screen too and can't be clicked to fix itself.
	panel.resetButton = CreatePanelButton(panel, "ElvUIMoverResetButton", L["Reset All"], 130,
		function() E:ResetAllMovers() end)
	if panel.resetButton then
		pcall(panel.resetButton.SetPoint, panel.resetButton, "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
	end

	ApplyMoverPanelPosition()
	panel:Hide()
	return panel
end

-- ===========================================================================
-- Alignment grid, shown during move mode: LibSnapGrid-1.0's, which follows
-- real ElvUI's `E:Grid_Create` convention -- the screen's width divided into
-- `E.db.gridSize` COLUMNS (a divisor, not a pixel size; default 64, clamped
-- to 4..256 by the library), square cells, drawn outwards from the centre
-- with the two centre lines red. `gridSize` is a real profile field, so an
-- imported profile drives it. The grid lines are also the snap lines of the
-- drag, and the library rebuilds the grid when the column count or the
-- screen size changed since it was built.
-- ===========================================================================

local function ShowGrid()
	local lib = GetSnapGrid()
	if lib then pcall(lib.ShowGrid, lib, tonumber(E.db.gridSize) or 64) end
end

local function HideGrid()
	local lib = GetSnapGrid()
	if lib then pcall(lib.HideGrid, lib) end
end

local HANDLE_LEVEL_OFFSET = 100

local function RaiseHandle(entry)
	if not entry.handle then return end
	local ok, level = pcall(entry.frame.GetFrameLevel, entry.frame)
	if ok and tonumber(level) then
		pcall(entry.handle.SetFrameLevel, entry.handle, level + HANDLE_LEVEL_OFFSET)
	end
end

-- The handle is a Button parented to the frame it moves and covering it
-- (SetAllPoints), raised by frame level rather than strata (UnrealUI's mover
-- recipe). Its OnMouseDown, OnMouseUp, OnHide, OnDragStart and OnDragStop
-- belong to LibSnapGrid-1.0; OnClick, OnEnter and OnLeave stay here.
local function CreateHandle(entry)
	local ok, handle = pcall(CreateFrame, "Button", "ElvUIMoverHandle"..entry.id, entry.frame)
	if not ok or not handle then return nil end

	pcall(handle.SetAllPoints, handle, entry.frame)
	pcall(handle.EnableMouse, handle, true)

	pcall(handle.SetBackdrop, handle, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(handle.SetBackdropColor, handle, 0, 0.6, 1, 0.35)
	pcall(handle.SetBackdropBorderColor, handle, 0, 0.6, 1, 1)

	local okLabel, label = pcall(handle.CreateFontString, handle, nil, "OVERLAY", "GameFontNormal")
	if okLabel and label then
		-- Real ElvUI's mover label: the UI font at its defaults.
		E:FontTemplate(label)
		pcall(label.SetPoint, label, "CENTER", handle, "CENTER", 0, 0)
		pcall(label.SetJustifyH, label, "CENTER")
		pcall(label.SetText, label, entry.label)
		handle.label = label
	end

	local lib = GetSnapGrid()
	if lib then
		lib:AttachDrag(handle, {
			frame = entry.frame,
			onStart = function() return BeginDrag(entry) end,
			onStop = function() EndDrag(entry) end,
		})
	end
	handle:SetScript("OnClick", function()
		E.activeMover = entry
	end)
	handle:SetScript("OnEnter", function()
		pcall(handle.SetBackdropBorderColor, handle, 1, 1, 0, 1)
	end)
	handle:SetScript("OnLeave", function()
		pcall(handle.SetBackdropBorderColor, handle, 0, 0.6, 1, 1)
	end)

	entry.handle = handle
	RaiseHandle(entry)
	return handle
end

local function ShowHandle(entry)
	if not entry.handle then CreateHandle(entry) end
	if not entry.handle then return end
	RaiseHandle(entry)
	pcall(entry.handle.Show, entry.handle)
end

local function HideHandle(entry)
	if not entry.handle then return end
	if entry.dragging then
		local lib = GetSnapGrid()
		if lib then lib:StopDrag() end
		EndDrag(entry)
	end
	pcall(entry.handle.Hide, entry.handle)
end

-- ===========================================================================
-- Public API
-- ===========================================================================

-- frame  the frame the user drags (a Frame/Button -- not a Texture/
--        FontString -- drawn at UIParent's scale, see HasUIParentScale)
-- name   stable string key, ALSO the E.db.movers[name] key -- matches real
--        ElvUI's own naming exactly where a real-profile-compatible name
--        is known (e.g. ActionBars uses "ElvAB_"..id, see
--        Modules/ActionBars.lua)
-- label  short text shown on the drag handle
--
-- No `default` parameter, unlike an earlier draft of this file -- matches
-- real ElvUI's own CreateMover exactly: if nothing is saved yet, the
-- frame is simply left wherever the CALLER already anchored it (via its
-- own normal SetPoint call before registering the mover), and THAT
-- position is captured as the reset target, rather than requiring a
-- separately hand-authored default here.
--
-- KNOWN BUG, unresolved: on the real 1.12.1 client the `default` captured
-- here can come back with its Y sign flipped -- X is correct and the
-- magnitude is exact, only Y's sign is wrong -- for a mover created this
-- early in load. The same frame queried later returns the correct sign, yet
-- this is not a settling-time issue: re-capturing a tick later and deferring
-- the whole capture to PLAYER_ENTERING_WORLD both produce the identical wrong
-- value, so delaying cannot fix it and neither is done here. Resetting such a
-- mover puts the frame at the mirrored Y.
function E:CreateMover(frame, name, label)
	if type(name) ~= "string" or not frame then return nil end
	if self.movers[name] then return self.movers[name] end

	pcall(frame.SetMovable, frame, true)

	-- `default` MUST be captured BEFORE applying the saved position below --
	-- capturing it after would mean a corrupted saved position becomes the
	-- "default" too, and Reset would just reapply the same corruption.
	-- Matches real ElvUI's own CreateMover (ElvUI-vanilla/ElvUI/
	-- Core/movers.lua: `E.CreatedMovers[name].point = GetPoint(parent)` runs
	-- BEFORE the saved-position restore, not after) -- capture the caller's
	-- own hardcoded starting position (from its own SetPoint call just
	-- before this) as the TRUE reset target, before any saved data can
	-- touch it.
	local default = CaptureFramePosition(frame)

	local saved = E.db.movers[name]
	if saved then
		ApplyPositionString(frame, saved)
	end

	local entry = {
		id = name,
		frame = frame,
		label = label or name,
		default = default,
		dragging = false,
	}

	self.movers[name] = entry
	table.insert(self.moverOrder, name)

	if self.moversUnlocked then ShowHandle(entry) end
	return entry
end

-- Live re-apply for a mover whose `E.db.movers[name]` string was set by
-- CODE (not a drag) -- e.g. the Install Wizard picking a resolution
-- preset. Falls back to the mover's own captured `default` position when
-- the saved string was cleared (set to `nil`), matching what a
-- never-touched mover shows -- `ApplyPositionString(frame, nil)` alone
-- would just no-op and leave the frame at its CURRENT position instead
-- of reverting.
function E:ApplyMoverPosition(name)
	local entry = self.movers[name]
	if not entry or not entry.frame then return end
	local str = E.db.movers[name] or entry.default
	if str then
		ApplyPositionString(entry.frame, str)
	end
end

function E:UnlockMovers()
	self.moversUnlocked = true
	if not keyFrame then keyFrame = CreateKeyFrame() end
	if keyFrame then pcall(keyFrame.Show, keyFrame) end
	SuppressArrowBindings()
	if not moverPanel then CreateMoverPanel() end
	if moverPanel then
		-- Re-applied on every unlock, not just at creation: a resolution or
		-- UI-scale change between sessions can leave a stored offset pointing
		-- off-screen, and this is the cheapest place to re-clamp it.
		ApplyMoverPanelPosition()
		pcall(moverPanel.Show, moverPanel)
	end
	ShowGrid()

	-- Fired BEFORE the ShowHandle loop on purpose: a module that keeps an
	-- otherwise-hidden frame visible during move mode has to have done so
	-- before its handle is created/shown, since the handle is a child of
	-- that frame.
	FireMoverStateCallbacks()

	local i
	for i = 1, table.getn(self.moverOrder) do
		ShowHandle(self.movers[self.moverOrder[i]])
	end
	self:Print(L["Movers unlocked -- see the Move UI panel (drag it out of the way if it covers something). 'Lock Movers' there, or /moveui again, exits."])
end

function E:LockMovers()
	self.moversUnlocked = false
	self.activeMover = nil
	if keyFrame then pcall(keyFrame.Hide, keyFrame) end
	RestoreArrowBindings()
	if moverPanel then pcall(moverPanel.Hide, moverPanel) end
	HideGrid()

	local i
	for i = 1, table.getn(self.moverOrder) do
		HideHandle(self.movers[self.moverOrder[i]])
	end
	FireMoverStateCallbacks()
	self:Print(L["Movers locked."])
end

function E:ToggleMoveMode()
	if self.moversUnlocked then
		self:LockMovers()
	else
		self:UnlockMovers()
	end
end

-- Drops the saved position for one mover and re-applies the position it
-- had when CreateMover first ran (its own captured `default`, matching
-- real ElvUI's own ResetMovers behavior).
function E:ResetMoverPosition(name)
	local entry = self.movers[name]
	if not entry then return false end
	E.db.movers[name] = nil
	if not entry.default then return false end
	return ApplyPositionString(entry.frame, entry.default)
end

-- Resets every registered mover, not just one -- the reachable fallback
-- for "something ended up off-screen and I can't click its handle to
-- fix it individually" (its handle is off-screen right along with it).
function E:ResetAllMovers()
	local i, count = nil, 0
	for i = 1, table.getn(self.moverOrder) do
		if self:ResetMoverPosition(self.moverOrder[i]) then
			count = count + 1
		end
	end
	self:Print(string.format(L["Reset %d mover position(s)."], count))
	return count
end
