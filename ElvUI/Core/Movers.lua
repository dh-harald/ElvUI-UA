-- ElvUI Movers: lets the user drag a registered frame to a new position and
-- persists it, plus arrow-key nudging with a live coordinate readout for
-- pixel-precise placement.
--
-- STORAGE FORMAT DELIBERATELY MATCHES REAL ELVUI EXACTLY (source/
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
-- The actual drag MECHANICS (handle type, the StartMoving/
-- StopMovingOrSizing throwaway pair, GetPoint's UA-specific quirks) are
-- modeled on UnrealUI's proven mover code instead of real ElvUI's own
-- (which assumes real-vanilla-correct GetPoint/StartMoving behavior) --
-- see the "Anchor capture" and "Dragging" sections below for exactly
-- which UA-specific findings this reuses.
--
-- Pixel-precise nudging (arrow keys + a live coordinate readout while
-- dragging) is the IDEA from real ElvUI's own mover system (there: mouse
-- wheel + a "nudge window", backed by LibSimpleSticky-1.0) ported to a
-- mechanism actually reliable on UA -- mouse wheel input is unreliable
-- on UA, and LibSimpleSticky-1.0 isn't vendored here.
--
-- Feature set: drag handle, save/restore position (real-ElvUI-format),
-- arrow-key nudge, live coordinate readout while dragging,
-- quadrant-relative anchoring (see CalculateMoverPoint below -- ported
-- from real ElvUI's own CalculateMoverPoints), an edit-mode overlay panel
-- with two buttons (`CreateMoverPanel` -- and unlike either reference,
-- DRAGGABLE), and an alignment grid (`CreateGrid`, real ElvUI's own
-- `E.db.gridSize` divisor convention). Deliberately NOT ported: a
-- center-alignment-guide overlay, magnet/snap-to-other-movers,
-- LibSimpleSticky sticky-edge snapping.

local E, L, V, P, G = unpack(ElvUI)
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
-- Anchor capture/apply, UA-quirk-safe, real-ElvUI-format
--
-- CONFIRMED via source/UnrealUI/core/compat.lua:367-392 (their own
-- "knowledge.json / frames.getpoint_relative_name_y_inverted", marked
-- BEHAVIOR_VERIFIED): on UA, frame:GetPoint() returns the relative frame
-- as a NAME STRING (not a frame object) and reports Y with the OPPOSITE
-- sign from what SetPoint expects for the same visual position.
-- UA_Y_INVERTED gates the sign-flip via ElvUI.Compat.isLua50 (true only
-- on the real 1.12.1 client, which runs Lua 5.0 -- UA runs 5.1) since
-- this specific bug was only ever confirmed on UA; blindly applying it on
-- real 1.12.1 too could introduce a NEW bug there if that client's
-- GetPoint is not actually broken this way. **Unverified on real
-- 1.12.1** -- confirm this assumption there before trusting saved
-- mover positions on that client.
--
-- Per the same UnrealUI reference: never recapture a point and
-- immediately clear/re-apply it (a documented failed approach) -- a drop
-- is captured and stored, and the frame is left exactly where the user
-- released it.
-- ===========================================================================
local UA_Y_INVERTED = not Compat.isLua50

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
	if UA_Y_INVERTED then y = -y end

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

-- Applies a real-ElvUI-format position string via SetPoint. Takes x/y in
-- SetPoint's OWN convention (not GetPoint's UA-inverted one) -- callers
-- always get x/y from CaptureFramePositionParts/ParsePositionString
-- above, which already normalize away the UA quirk, so no further sign
-- flip happens here. `relativeName` falls back to UIParent if it doesn't
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
-- Ported directly from real ElvUI's own E:CalculateMoverPoints
-- (source/ElvUI-vanilla/ElvUI/Core/movers.lua:244-306) -- same thirds/
-- halves thresholds, same GetCenter/GetLeft/GetRight/GetTop/GetBottom
-- reads. Deliberately NOT using GetPoint() here at all (unlike
-- CaptureFramePositionParts above) -- GetCenter/GetLeft/GetRight/GetTop/
-- GetBottom are a different API surface than GetPoint, and the UA
-- Y-inversion quirk this file works around elsewhere was specifically
-- confirmed for GetPoint's return values, not these -- **unverified
-- whether these are also affected on UA, watch for a sign issue here
-- specifically if positions still drift after this change**. Real
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
	local TOP = screenHeight / 2

	local point, x, y

	if cy >= TOP then
		point = "TOP"
		local okFrameTop, frameTop = pcall(frame.GetTop, frame)
		y = -(screenHeight - (okFrameTop and frameTop or cy))
	else
		point = "BOTTOM"
		local okBottom, bottom = pcall(frame.GetBottom, frame)
		y = okBottom and bottom or cy
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
-- Matches UnrealUI's proven recipe exactly (source/UnrealUI/core/
-- mover.lua:230-256, their own summary of what actually works on UA vs.
-- their first, failed attempt) -- deliberately NOT real ElvUI's own drag
-- handling, which assumes real-vanilla-correct StartMoving/GetPoint:
--   * the handle is a Button, not a plain Frame -- Buttons take mouse
--     input without EnableMouse, and Button is the only widget type
--     confirmed to deliver OnDragStart on this client.
--   * the handle is parented to the frame it moves and covers it via
--     SetAllPoints, not floating separately as a UIParent child.
--   * raised via SetFrameLevel, not a strata change.
--   * SetMovable is applied immediately before each drag, not only once
--     at registration.
--   * StartMoving is called once, thrown away with an immediate
--     StopMovingOrSizing (collapses a multi-point anchor down to the
--     single point the client will actually move), THEN called again for
--     the real drag.
--   * OnMouseDown starts the move immediately; a later OnDragStart is
--     treated as confirmation, not a restart -- StartDrag is idempotent.
-- ===========================================================================
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

local function StartDrag(entry)
	if entry.dragging then return true end
	local frame = entry.frame

	if not pcall(frame.SetMovable, frame, true) then return false end

	if pcall(frame.StartMoving, frame) then
		pcall(frame.StopMovingOrSizing, frame)
	end
	if not pcall(frame.StartMoving, frame) then return false end

	entry.dragging = true
	if not dragTimerHandle then
		dragTimerHandle = E:ScheduleRepeatingTimer(UpdateDragReadout, 0.1)
	end
	return true
end

local function CapturePosition(entry)
	local str = CaptureMoverPosition(entry.frame)
	if not str then return false end
	E.db.movers[entry.id] = str
	return true
end

local function StopDrag(entry)
	if not entry.dragging then return false end
	entry.dragging = false

	if dragTimerHandle then
		E:CancelTimer(dragTimerHandle)
		dragTimerHandle = nil
	end
	if entry.handle and entry.handle.label then
		pcall(entry.handle.label.SetText, entry.handle.label, entry.label)
	end

	pcall(entry.frame.StopMovingOrSizing, entry.frame)
	return CapturePosition(entry)
end

-- Arrow-key nudging for pixel-precise placement. Real ElvUI's own
-- equivalent is the mouse wheel, which is unreliable on UA -- this ports
-- the IDEA, not the mechanism. A shown, keyboard-enabled plain Frame with
-- OnKeyDown is reliable on UA (matches UnrealUI's own edit-mode key
-- frame, source/UnrealUI/core/mover.lua -- must be a plain Frame, not a
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

-- ===========================================================================
-- Mover control panel
--
-- A proper draggable window with two buttons (Lock Movers, Reset All),
-- replacing two loose screen-pinned buttons. Real ElvUI has
-- `ElvUIMoverPopupWindow`; `source/UnrealUI/core/mover.lua` has
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

-- Same low-level drag recipe as this file's own StartDrag/StopDrag and as
-- Skins.lua's `S:MakeDraggable`: a throwaway StartMoving/StopMovingOrSizing
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
		pcall(title.SetText, title, "Move UI")
		pcall(title.SetTextColor, title, 1, 0.82, 0)
	end

	local hints = {
		"Drag a highlighted frame to move it.",
		"Click one, then use the arrow keys",
		"to nudge it (hold Shift for 10px).",
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

	panel.lockButton = CreatePanelButton(panel, "ElvUIMoverLockButton", "Lock Movers", 130,
		function() E:LockMovers() end)
	if panel.lockButton then
		pcall(panel.lockButton.SetPoint, panel.lockButton, "BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
	end

	-- A mouse-clickable reset that's ALWAYS reachable regardless of where a
	-- mover's own handle currently is -- an off-screen mover's handle is,
	-- by definition, off-screen too and can't be clicked to fix itself.
	panel.resetButton = CreatePanelButton(panel, "ElvUIMoverResetButton", "Reset All", 130,
		function() E:ResetAllMovers() end)
	if panel.resetButton then
		pcall(panel.resetButton.SetPoint, panel.resetButton, "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
	end

	ApplyMoverPanelPosition()
	panel:Hide()
	return panel
end

-- ===========================================================================
-- Alignment grid, shown during move mode. Both references have one, with
-- different conventions:
--   * real ElvUI (`E:Grid_Create`, Core/config.lua:100-150) divides the
--     screen into `E.db.gridSize` COLUMNS -- a divisor, not a pixel size --
--     default 64, with the two centre lines drawn red.
--   * `source/UnrealUI/core/mover.lua:505-536` uses a fixed 20 PIXEL step
--     with a distinct centre-axis colour.
-- Real ElvUI's convention wins here, because `gridSize` is a real
-- top-level profile field name and an imported profile will drive it --
-- which is the whole point (64 columns on a 2560-wide screen lands at
-- 40px cells).
--
-- Cells are kept SQUARE: real ElvUI gets this via a width/height ratio
-- trick on its horizontal step; computing `hStep = wStep` directly is the
-- same result with less indirection.

local grid

local function CreateGridLine(parent, isVertical, offset, isCentre)
	local ok, tex = pcall(parent.CreateTexture, parent, nil, "BACKGROUND")
	if not ok or not tex then return end

	if isCentre then
		pcall(tex.SetTexture, tex, 1, 0, 0, 0.7)
	else
		pcall(tex.SetTexture, tex, 0, 0, 0, 0.5)
	end

	pcall(tex.ClearAllPoints, tex)
	if isVertical then
		pcall(tex.SetWidth, tex, 1)
		pcall(tex.SetPoint, tex, "TOPLEFT", parent, "TOPLEFT", offset, 0)
		pcall(tex.SetPoint, tex, "BOTTOMLEFT", parent, "BOTTOMLEFT", offset, 0)
	else
		pcall(tex.SetHeight, tex, 1)
		pcall(tex.SetPoint, tex, "TOPLEFT", parent, "TOPLEFT", 0, -offset)
		pcall(tex.SetPoint, tex, "TOPRIGHT", parent, "TOPRIGHT", 0, -offset)
	end
end

local function CreateGrid()
	local ok, frame = pcall(CreateFrame, "Frame", "ElvUIGrid", UIParent)
	if not ok or not frame then return nil end
	grid = frame

	pcall(frame.SetAllPoints, frame, UIParent)
	pcall(frame.SetFrameStrata, frame, "BACKGROUND")
	-- Decoration only -- it must never eat a click meant for a mover handle.
	-- (UnrealUI's own grid comment makes the same point.)
	pcall(frame.EnableMouse, frame, false)

	local okW, width = pcall(UIParent.GetWidth, UIParent)
	local okH, height = pcall(UIParent.GetHeight, UIParent)
	width = (okW and tonumber(width)) or 1024
	height = (okH and tonumber(height)) or 768

	-- Clamped at both ends. Below 4 the "grid" stops being one; above 256 a
	-- 2560-wide screen would mean ~10px cells and 400+ Texture regions on a
	-- single frame -- created once, but a large synchronous loop building
	-- that many native objects risks a client crash, so it gets a ceiling
	-- rather than trusting whatever a profile happens to carry.
	local divisions = tonumber(E.db.gridSize) or 64
	if divisions < 4 then divisions = 4 end
	if divisions > 256 then divisions = 256 end

	local step = width / divisions
	if step < 4 then step = 4 end

	local centreX = width / 2
	local centreY = height / 2

	-- Drawn outwards from the centre in both directions rather than from the
	-- left edge, so the centre lines land EXACTLY on the middle regardless
	-- of whether `divisions` divides evenly -- being able to trust the
	-- centre line is most of the point of an alignment grid.
	local offset = 0
	while offset <= centreX do
		local isCentre = (offset == 0)
		CreateGridLine(frame, true, centreX + offset, isCentre)
		if not isCentre then CreateGridLine(frame, true, centreX - offset, false) end
		offset = offset + step
	end

	offset = 0
	while offset <= centreY do
		local isCentre = (offset == 0)
		CreateGridLine(frame, false, centreY + offset, isCentre)
		if not isCentre then CreateGridLine(frame, false, centreY - offset, false) end
		offset = offset + step
	end

	frame.builtFor = divisions
	frame:Hide()
	return frame
end

-- Rebuilt rather than reused when `gridSize` changed since it was built --
-- the lines are plain Textures with no cheap way to re-lay-out in place,
-- and this only ever runs on a /moveui toggle, never in a hot path.
local function ShowGrid()
	local divisions = tonumber(E.db.gridSize) or 64
	if divisions < 4 then divisions = 4 end
	if divisions > 256 then divisions = 256 end
	if grid and grid.builtFor ~= divisions then
		pcall(grid.Hide, grid)
		pcall(grid.SetParent, grid, nil)
		grid = nil
	end
	if not grid then grid = CreateGrid() end
	if grid then pcall(grid.Show, grid) end
end

local function HideGrid()
	if grid then pcall(grid.Hide, grid) end
end

local HANDLE_LEVEL_OFFSET = 100

local function RaiseHandle(entry)
	if not entry.handle then return end
	local ok, level = pcall(entry.frame.GetFrameLevel, entry.frame)
	if ok and tonumber(level) then
		pcall(entry.handle.SetFrameLevel, entry.handle, level + HANDLE_LEVEL_OFFSET)
	end
end

-- Right-clicking a handle can shift the frame by ~1px, as if a drag had
-- started -- root cause: OnMouseDown/OnMouseUp fire for EVERY mouse
-- button on a Button widget, not just the one `RegisterForDrag
-- ("LeftButton")` was scoped to (that only governs OnDragStart/
-- OnDragStop). A right-click triggers the full StartDrag
-- throwaway-StartMoving/StopMovingOrSizing pair for nothing, and that
-- pair alone can nudge the frame slightly even with no real drag. Matches
-- UnrealUI's own `IsLeftMouseButton` guard (source/UnrealUI/core/
-- mover.lua), including its fallback reasoning: some scripts on this
-- client expose no direct arguments and no `arg1`, and since this handle
-- is only ever registered for left-button dragging, an unresolvable
-- button is safely treated as left rather than blocked.
local function IsLeftMouseButton(a, b)
	local button
	if type(a) == "string" then
		button = a
	elseif type(b) == "string" then
		button = b
	else
		button = _G.arg1
	end
	return button == nil or button == "LeftButton"
end

local function CreateHandle(entry)
	local ok, handle = pcall(CreateFrame, "Button", "ElvUIMoverHandle"..entry.id, entry.frame)
	if not ok or not handle then return nil end

	pcall(handle.SetAllPoints, handle, entry.frame)
	pcall(handle.RegisterForDrag, handle, "LeftButton")
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
		pcall(label.SetPoint, label, "CENTER", handle, "CENTER", 0, 0)
		pcall(label.SetJustifyH, label, "CENTER")
		pcall(label.SetText, label, entry.label)
		handle.label = label
	end

	handle:SetScript("OnMouseDown", function(a, b)
		if not IsLeftMouseButton(a, b) then return end
		E.activeMover = entry
		StartDrag(entry)
	end)
	handle:SetScript("OnMouseUp", function(a, b)
		if not IsLeftMouseButton(a, b) then return end
		StopDrag(entry)
	end)
	handle:SetScript("OnDragStart", function()
		E.activeMover = entry
		StartDrag(entry)
	end)
	handle:SetScript("OnDragStop", function()
		StopDrag(entry)
	end)
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
	if entry.dragging then StopDrag(entry) end
	pcall(entry.handle.Hide, entry.handle)
end

-- ===========================================================================
-- Public API
-- ===========================================================================

-- frame  the frame the user drags (needs SetMovable/StartMoving, i.e. a
--        Frame/Button -- not a Texture/FontString)
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
-- KNOWN BUG, unresolved -- see docs/modules/movers.md and docs/roadmap.md
-- ("`entry.default` hibás előjelű Y"): on the real 1.12.1 client, the
-- `default` captured here can have its Y sign flipped (same signature as
-- the already-known UA_Y_INVERTED quirk) for a mover created this early.
-- Two mitigations were tried and BOTH measured to fail live (a same-tick
-- `ScheduleTimer(fn, 0)` re-capture, and deferring the whole capture to
-- `PLAYER_ENTERING_WORLD`) -- neither changed the captured value at all,
-- so whatever causes this is not a settling-time issue this file can
-- wait out. Reverted to the simple, original form below rather than
-- carry that extra complexity for two fixes that measurably did nothing.
function E:CreateMover(frame, name, label)
	if type(name) ~= "string" or not frame then return nil end
	if self.movers[name] then return self.movers[name] end

	pcall(frame.SetMovable, frame, true)

	-- `default` MUST be captured BEFORE applying the saved position below --
	-- capturing it after would mean a corrupted saved position becomes the
	-- "default" too, and Reset would just reapply the same corruption.
	-- Matches real ElvUI's own CreateMover (source/ElvUI-vanilla/ElvUI/
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
