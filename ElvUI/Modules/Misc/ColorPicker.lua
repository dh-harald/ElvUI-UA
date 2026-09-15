-- Colour picker replacement, a file of the Misc module.
--
-- Real ElvUI extends the stock ColorPickerFrame in place
-- (Modules/Blizzard/ColorPicker.lua). That frame is unusable on Unreal
-- Azeroth: the ColorSelect wheel and value bar neither draw nor take clicks
-- (also found by UnrealUI core/widgets.lua and LibConfig-1.0), and
-- ColorSelect:GetColorRGB() always returns 0, 0, 0, so every stock swatch
-- callback, which reads the colour back from the picker, writes black.
--
-- Callers keep opening the stock frame, through
-- UIDropDownMenuButton_OpenColorPicker or their own ShowUIPanel. An OnShow
-- hook hides it at once and opens this dialog, fed from the fields the
-- caller left on ColorPickerFrame (func, opacityFunc, cancelFunc,
-- previousValues, hasOpacity, opacity). The stock opener has already run
-- func once before showing the frame (SetColorRGB fires OnColorSelect),
-- which on UA wrote black, so opening re-applies the starting colour.
--
-- How a colour reaches its target:
--   * The chat window menu's callbacks are recognised and replaced by the
--     calls they make themselves (ChangeChatColor, FCF_SetWindowColor,
--     FCF_SetWindowAlpha), because they read the colour from the picker.
--     Chat type colours go through Util.ChangeChatColor, which handles UA's
--     0-255 channel scale and missing UPDATE_CHAT_COLOR.
--   * Any other callback gets the colour pushed into the stock frame:
--     ColorPickerFrame:SetColorRGB fires OnColorSelect -> func, and
--     OpacitySliderFrame:SetValue fires OnValueChanged -> opacityFunc.
--     Correct on the 1.12.1 client; on UA it inherits the stock breakage.
-- Opacity follows the stock convention: the slider value is 1 - alpha.
--
-- Changes preview live, like the stock picker, throttled to APPLY_INTERVAL.
-- Cancel, Escape and any other close restore the starting colour; clicking
-- the lower (old colour) swatch reverts without closing.
--
-- Built only from primitives that work on UA: WHITE8x8 textures tinted with
-- SetVertexColor/SetGradientAlpha (a VERTICAL gradient's first stop is the
-- TOP edge on UA and the BOTTOM edge on 1.12.1, UnrealUI core/widgets.lua),
-- and a cursor-driven drag started from OnMouseDown. On UA a frame receives
-- OnMouseUp only while the cursor is over it, so for the duration of a drag
-- the pressed area's hit rectangle is expanded over the whole screen and its
-- GetButtonState() is polled as a second release signal (LibConfig-1.0
-- AttachThumbDrag). An expanded hit rectangle corrupts mouse focus on a
-- Blizzard client, so that part is UA-only. Hiding a frame does not hide its
-- children on UA, so every child frame and region is shown and hidden
-- explicitly.

local E, L, V, P, G = unpack(ElvUI)
local M = E:GetModule("Misc")
local Compat = ElvUI.Compat
local isUA = Compat and Compat.isUA

local WHITE = "Interface\\Buttons\\WHITE8x8"
-- Above the chat frames and the DIALOG-strata windows a picker can be
-- opened from.
local STRATA = "FULLSCREEN_DIALOG"
local APPLY_INTERVAL = 0.1
local DRAG_CAPTURE_INSET = -4000
-- A drag that never saw its release must not keep a screen-wide hit
-- rectangle alive.
local DRAG_MAX_SECONDS = 60
local DRAG_LEVEL_RAISE = 50

local PAD = 10
local SQUARE_W, SQUARE_H = 170, 130
local STRIP_H = 12
local STRIP_GAP = 8
local SWATCH_W, SWATCH_H = 50, 40
local BUTTON_H = 20
local TITLE_H = 28
local DIALOG_W = PAD + SQUARE_W + PAD + SWATCH_W + PAD
local DIALOG_H = TITLE_H + SQUARE_H + STRIP_GAP + STRIP_H + STRIP_GAP + STRIP_H + 12 + BUTTON_H + PAD

local HUE_STOPS = {
	{ 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 },
	{ 0, 1, 1 }, { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 },
}

local dialog, ticker
-- Every child frame and region of the dialog, shown and hidden with it.
local parts = {}
-- The opacity strip, shown only when the caller asked for opacity.
local alphaParts = {}
-- The open request: start = {r, g, b, a}, hasOpacity, apply(r, g, b, a),
-- cancel().
local session
-- HSV is the working representation: RGB alone cannot keep the hue of a
-- colour dragged into the grey edge of the square and back out again.
local hsv = { h = 0, s = 0, v = 1 }
local alpha = 1
local dirty, lastApply = false, 0
local activeDrag

local function Now()
	return (type(GetTime) == "function" and tonumber(GetTime())) or 0
end

local function Clamp01(v)
	v = tonumber(v) or 0
	if v < 0 then return 0 end
	if v > 1 then return 1 end
	return v
end

local function WrapHue(h)
	while h < 0 do h = h + 360 end
	while h >= 360 do h = h - 360 end
	return h
end

local function HSVtoRGB(h, s, v)
	h, s, v = WrapHue(h), Clamp01(s), Clamp01(v)
	if s <= 0 then return v, v, v end

	local sector = h / 60
	local i = math.floor(sector)
	local f = sector - i
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local t = v * (1 - s * (1 - f))

	if i == 0 then return v, t, p end
	if i == 1 then return q, v, p end
	if i == 2 then return p, v, t end
	if i == 3 then return p, q, v end
	if i == 4 then return t, p, v end
	return v, p, q
end

local function RGBtoHSV(r, g, b)
	r, g, b = Clamp01(r), Clamp01(g), Clamp01(b)
	local max = math.max(r, math.max(g, b))
	local min = math.min(r, math.min(g, b))
	local d = max - min

	local h = 0
	if d > 0 then
		if max == r then
			h = (g - b) / d
			if h < 0 then h = h + 6 end
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h = h * 60
	end

	local s = 0
	if max > 0 then s = d / max end
	return WrapHue(h), s, max
end

local function CurrentRGB()
	return HSVtoRGB(hsv.h, hsv.s, hsv.v)
end

-- Redraws everything that depends on the current colour.
local function Refresh()
	local r, g, b = CurrentRGB()
	local hr, hg, hb = HSVtoRGB(hsv.h, 1, 1)

	dialog.hueFill:SetVertexColor(hr, hg, hb)
	dialog.newColor:SetVertexColor(r, g, b)
	pcall(dialog.alphaFill.SetGradientAlpha, dialog.alphaFill, "HORIZONTAL", r, g, b, 0, r, g, b, 1)

	dialog.squareMarker:ClearAllPoints()
	dialog.squareMarker:SetPoint("CENTER", dialog.square, "TOPLEFT", hsv.s * SQUARE_W, -(1 - hsv.v) * SQUARE_H)
	dialog.hueThumb:ClearAllPoints()
	dialog.hueThumb:SetPoint("CENTER", dialog.hue, "LEFT", (hsv.h / 360) * SQUARE_W, 0)
	dialog.alphaThumb:ClearAllPoints()
	dialog.alphaThumb:SetPoint("CENTER", dialog.alpha, "LEFT", alpha * SQUARE_W, 0)
end

local function Changed()
	Refresh()
	dirty = true
end

local function SetColor(r, g, b, a)
	local h, s, v = RGBtoHSV(r, g, b)
	-- A colour without saturation carries no hue; keep the previous one.
	if s > 0 then hsv.h = h end
	hsv.s, hsv.v = s, v
	alpha = Clamp01(a)
	Changed()
end

local function FlushApply()
	dirty = false
	lastApply = Now()
	if not session then return end
	local r, g, b = CurrentRGB()
	session.apply(r, g, b, alpha)
end

local function SetLevelOffset(frame, delta)
	local ok, level = pcall(frame.GetFrameLevel, frame)
	if ok and tonumber(level) then
		pcall(frame.SetFrameLevel, frame, level + delta)
	end
end

-- Feeds the cursor position inside the dragged area, as 0..1 on each axis
-- (clamped, so dragging past an edge pins the value), to its onMove.
-- Cursor coordinates are divided by the effective scale to match
-- GetLeft()/GetTop().
local function TrackCursor(drag)
	if type(GetCursorPosition) ~= "function" then return end
	local area = drag.area
	local okCursor, cx, cy = pcall(GetCursorPosition)
	local okScale, scale = pcall(area.GetEffectiveScale, area)
	local okLeft, left = pcall(area.GetLeft, area)
	local okTop, top = pcall(area.GetTop, area)
	if not (okCursor and okScale and okLeft and okTop) then return end
	cx, cy, scale = tonumber(cx), tonumber(cy), tonumber(scale)
	left, top = tonumber(left), tonumber(top)
	if not (cx and cy and scale and left and top) or scale <= 0 then return end

	drag.onMove(Clamp01((cx / scale - left) / area.pickWidth), Clamp01((top - cy / scale) / area.pickHeight))
end

local function StopDrag(track)
	local drag = activeDrag
	if not drag then return end
	activeDrag = nil
	if track then TrackCursor(drag) end

	if drag.captured then
		local area = drag.area
		pcall(area.SetHitRectInsets, area, 0, 0, 0, 0)
		SetLevelOffset(area, -DRAG_LEVEL_RAISE)
		SetLevelOffset(area.pickMarker, -DRAG_LEVEL_RAISE)
	end
end

-- A press anywhere in `area` jumps the value there and keeps following the
-- cursor until release. RegisterForDrag is deliberately not used: on UA a
-- non-empty drag registration suppresses both OnDragStop and OnMouseUp.
local function AttachAreaDrag(area, onMove)
	pcall(area.EnableMouse, area, true)

	-- No mouse-button filter: the global arg1 is not reliably the pressed
	-- button on UA, and a stale value would swallow every press.
	area:SetScript("OnMouseDown", function()
		StopDrag(false)

		local drag = { area = area, onMove = onMove, armed = false, startedAt = Now() }
		if isUA then
			pcall(area.SetHitRectInsets, area, DRAG_CAPTURE_INSET, DRAG_CAPTURE_INSET, DRAG_CAPTURE_INSET, DRAG_CAPTURE_INSET)
			-- The expanded rectangle only receives the release where nothing
			-- sits above it, and the dialog's buttons and drag handle do.
			-- The marker is raised with it so it stays visible.
			SetLevelOffset(area, DRAG_LEVEL_RAISE)
			SetLevelOffset(area.pickMarker, DRAG_LEVEL_RAISE)
			drag.captured = true
		end

		activeDrag = drag
		TrackCursor(drag)
	end)

	area:SetScript("OnMouseUp", function()
		if activeDrag and activeDrag.area == area then StopDrag(true) end
	end)
end

local function ShowParts(shown)
	local i
	for i = 1, table.getn(parts) do
		if shown then parts[i]:Show() else parts[i]:Hide() end
	end
	local showAlpha = shown and session and session.hasOpacity
	for i = 1, table.getn(alphaParts) do
		if showAlpha then alphaParts[i]:Show() else alphaParts[i]:Hide() end
	end
end

-- Ends the open request without touching the dialog's visibility.
local function Finish(accept)
	StopDrag(false)
	local current = session
	if not current then return end
	if accept then FlushApply() else current.cancel() end
	session = nil
	dirty = false
end

local function Close(accept)
	Finish(accept)
	ShowParts(false)
	ticker:Hide()
	pcall(dialog.Hide, dialog)
end

local function OnTick()
	local drag = activeDrag
	if drag then
		TrackCursor(drag)

		if drag.captured then
			-- Only a definite "PUSHED" counts as held: UA reports "UNKNOWN"
			-- right after a release. Armed only after one PUSHED reading, so
			-- a client that never reports it falls back to OnMouseUp alone.
			local ok, state = pcall(drag.area.GetButtonState, drag.area)
			if ok and state == "PUSHED" then
				drag.armed = true
			elseif ok and type(state) == "string" and drag.armed then
				StopDrag(true)
			end
		end

		if activeDrag and Now() - drag.startedAt > DRAG_MAX_SECONDS then
			StopDrag(false)
		end
	end

	if dirty and session and Now() - lastApply >= APPLY_INTERVAL then
		FlushApply()
	end
end

local function AddPart(list, part)
	table.insert(list, part)
	return part
end

local function NewTexture(frame, layer, list)
	local tex = frame:CreateTexture(nil, layer)
	tex:SetTexture(WHITE)
	return AddPart(list or parts, tex)
end

local function InsetTexture(frame, layer, list)
	local tex = NewTexture(frame, layer, list)
	tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	return tex
end

-- Strata is set on every child explicitly rather than trusted to inherit.
local function NewFrame(frameType, name, parent, levelOffset, list)
	local frame = CreateFrame(frameType, name, parent)
	pcall(frame.SetFrameStrata, frame, STRATA)
	local ok, level = pcall(dialog.GetFrameLevel, dialog)
	if ok and tonumber(level) then
		pcall(frame.SetFrameLevel, frame, level + levelOffset)
	end
	return AddPart(list or parts, frame)
end

-- Border-only outline; never takes the mouse, so presses reach the area.
local function NewMarker(parent, width, height, list)
	local marker = NewFrame("Frame", nil, parent, 4, list)
	marker:SetWidth(width)
	marker:SetHeight(height)
	pcall(marker.SetBackdrop, marker, { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	pcall(marker.SetBackdropColor, marker, 0, 0, 0, 0)
	pcall(marker.SetBackdropBorderColor, marker, 1, 1, 1, 1)
	return marker
end

local function NewPickArea(anchor, relativePoint, yOffset, height, list)
	local area = NewFrame("Button", nil, dialog, 2, list)
	area:SetWidth(SQUARE_W)
	area:SetHeight(height)
	area:SetPoint("TOPLEFT", anchor, relativePoint, 0, yOffset)
	E:SetTemplate(area, "Default")
	area.pickWidth, area.pickHeight = SQUARE_W, height
	return area
end

local function NewButton(name, text, onClick)
	local button = NewFrame("Button", name, dialog, 2)
	button:SetWidth((DIALOG_W - 3 * PAD) / 2)
	button:SetHeight(BUTTON_H)
	E:SetTemplate(button, "Default")

	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("CENTER", button, "CENTER", 0, 0)
	label:SetText(text or "")
	AddPart(parts, label)

	button:SetScript("OnEnter", function()
		local color = E.db and E.db.general and E.db.general.valuecolor
		if color then
			pcall(button.SetBackdropBorderColor, button, color.r, color.g, color.b, 1)
		end
	end)
	button:SetScript("OnLeave", function()
		E:SetTemplate(button, "Default")
	end)
	button:SetScript("OnClick", onClick)
	return button
end

-- The dialog is built by several small functions rather than one: Lua 5.0
-- allows a function at most 32 upvalues, closures nested in it included.

-- Saturation (x) / value (y) square: flat hue, white fading out to the
-- right, black fading out towards the top.
local function BuildSquare()
	local square = NewFrame("Button", nil, dialog, 2)
	square:SetWidth(SQUARE_W)
	square:SetHeight(SQUARE_H)
	square:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -TITLE_H)
	E:SetTemplate(square, "Default")
	square.pickWidth, square.pickHeight = SQUARE_W, SQUARE_H
	dialog.square = square

	dialog.hueFill = InsetTexture(square, "BACKGROUND")
	local satFill = InsetTexture(square, "ARTWORK")
	pcall(satFill.SetGradientAlpha, satFill, "HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 0)
	local valFill = InsetTexture(square, "OVERLAY")
	if isUA then
		pcall(valFill.SetGradientAlpha, valFill, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 1)
	else
		pcall(valFill.SetGradientAlpha, valFill, "VERTICAL", 0, 0, 0, 1, 0, 0, 0, 0)
	end

	dialog.squareMarker = NewMarker(square, 7, 7)
	square.pickMarker = dialog.squareMarker
	AttachAreaDrag(square, function(fx, fy)
		hsv.s, hsv.v = fx, 1 - fy
		Changed()
	end)
	return square
end

-- Hue strip (six gradients between neighbouring pure hues) and the opacity
-- strip below it (the current colour fading in from the left).
local function BuildStrips(square)
	local hue = NewPickArea(square, "BOTTOMLEFT", -STRIP_GAP, STRIP_H)
	dialog.hue = hue
	local segmentWidth = (SQUARE_W - 2) / 6
	local i
	for i = 1, 6 do
		local segment = NewTexture(hue, "ARTWORK")
		segment:SetWidth(segmentWidth)
		segment:SetHeight(STRIP_H - 2)
		segment:SetPoint("TOPLEFT", hue, "TOPLEFT", 1 + (i - 1) * segmentWidth, -1)
		local from, to = HUE_STOPS[i], HUE_STOPS[i + 1]
		pcall(segment.SetGradientAlpha, segment, "HORIZONTAL", from[1], from[2], from[3], 1, to[1], to[2], to[3], 1)
	end

	dialog.hueThumb = NewMarker(hue, 4, STRIP_H + 4)
	hue.pickMarker = dialog.hueThumb
	AttachAreaDrag(hue, function(fx)
		-- 360 would wrap to 0 and throw the thumb back to the left end.
		hsv.h = math.min(fx * 360, 359.9)
		Changed()
	end)

	local alphaStrip = NewPickArea(hue, "BOTTOMLEFT", -STRIP_GAP, STRIP_H, alphaParts)
	dialog.alpha = alphaStrip
	dialog.alphaFill = InsetTexture(alphaStrip, "ARTWORK", alphaParts)
	dialog.alphaThumb = NewMarker(alphaStrip, 4, STRIP_H + 4, alphaParts)
	alphaStrip.pickMarker = dialog.alphaThumb
	AttachAreaDrag(alphaStrip, function(fx)
		alpha = fx
		Changed()
	end)
end

-- New colour above, starting colour below; clicking the lower one reverts.
local function BuildSwatches(square)
	local newSwatch = NewFrame("Frame", nil, dialog, 2)
	newSwatch:SetWidth(SWATCH_W)
	newSwatch:SetHeight(SWATCH_H)
	newSwatch:SetPoint("TOPLEFT", square, "TOPRIGHT", PAD, 0)
	E:SetTemplate(newSwatch, "Default")
	dialog.newColor = InsetTexture(newSwatch, "ARTWORK")

	local oldSwatch = NewFrame("Button", nil, dialog, 2)
	oldSwatch:SetWidth(SWATCH_W)
	oldSwatch:SetHeight(SWATCH_H)
	oldSwatch:SetPoint("TOPLEFT", newSwatch, "BOTTOMLEFT", 0, -6)
	E:SetTemplate(oldSwatch, "Default")
	dialog.oldColor = InsetTexture(oldSwatch, "ARTWORK")
	oldSwatch:SetScript("OnClick", function()
		if not session then return end
		local start = session.start
		SetColor(start.r, start.g, start.b, start.a)
	end)
end

-- Okay/Cancel and the header drag handle.
local function BuildControls()
	local okay = NewButton("ElvUI_ColorPickerOkay", OKAY, function() Close(true) end)
	okay:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", PAD, PAD)
	local cancel = NewButton("ElvUI_ColorPickerCancel", CANCEL, function() Close(false) end)
	cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -PAD, PAD)

	local S = E:GetModule("Skins")
	local handle = S:MakeDraggable(dialog)
	if handle then
		pcall(handle.SetFrameStrata, handle, STRATA)
		AddPart(parts, handle)
	end
end

local function EnsureDialog()
	if dialog then return end

	dialog = CreateFrame("Frame", "ElvUI_ColorPicker", UIParent)
	dialog:SetWidth(DIALOG_W)
	dialog:SetHeight(DIALOG_H)
	dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	pcall(dialog.SetFrameStrata, dialog, STRATA)
	pcall(dialog.SetClampedToScreen, dialog, true)
	pcall(dialog.EnableMouse, dialog, true)
	E:SetTemplate(dialog, "Transparent")
	dialog:Hide()

	local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", dialog, "TOP", 0, -8)
	title:SetText(COLOR_PICKER or "")
	AddPart(parts, title)

	local square = BuildSquare()
	BuildStrips(square)
	BuildSwatches(square)
	BuildControls()

	ticker = CreateFrame("Frame", nil, UIParent)
	ticker:Hide()
	ticker:SetScript("OnUpdate", OnTick)

	dialog:SetScript("OnHide", function()
		Finish(false)
		ShowParts(false)
		ticker:Hide()
	end)

	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "ElvUI_ColorPicker")
	end
end

local function CurrentChatFrame()
	if type(FCF_GetCurrentChatFrame) ~= "function" then return nil end
	local ok, frame = pcall(FCF_GetCurrentChatFrame)
	if ok and type(frame) == "table" then return frame end
	return nil
end

-- Reads the request the caller left on ColorPickerFrame. Callback identity
-- is compared once here, while UIDROPDOWNMENU_MENU_VALUE and the current
-- drop-down still describe the menu entry that opened the picker.
local function BuildSession(picker)
	local previous = picker.previousValues
	local r, g, b
	if type(previous) == "table" and tonumber(previous.r) then
		r, g, b = previous.r, previous.g, previous.b
	else
		local ok
		ok, r, g, b = pcall(picker.GetColorRGB, picker)
		if not ok then r, g, b = 1, 1, 1 end
	end

	local opacity = (type(previous) == "table" and tonumber(previous.opacity)) or tonumber(picker.opacity) or 0
	local request = {
		start = { r = tonumber(r) or 1, g = tonumber(g) or 1, b = tonumber(b) or 1, a = Clamp01(1 - opacity) },
		hasOpacity = Compat.bool(picker.hasOpacity),
	}

	local func, opacityFunc, cancelFunc = picker.func, picker.opacityFunc, picker.cancelFunc
	local applyColor, applyAlpha
	local useNativeCancel = false

	if func ~= nil and func == FCF_SetChatTypeColor then
		local chatType = UIDROPDOWNMENU_MENU_VALUE
		applyColor = function(cr, cg, cb)
			ElvUI.Util.ChangeChatColor(chatType, cr, cg, cb)
		end
	elseif func ~= nil and func == FCF_SetChatWindowBackGroundColor then
		local frame = CurrentChatFrame()
		applyColor = function(cr, cg, cb)
			if frame then pcall(FCF_SetWindowColor, frame, cr, cg, cb) end
		end
	elseif func ~= nil then
		useNativeCancel = true
		applyColor = function(cr, cg, cb)
			pcall(picker.SetColorRGB, picker, cr, cg, cb)
		end
	end

	if request.hasOpacity and opacityFunc ~= nil then
		if opacityFunc == FCF_SetChatWindowOpacity then
			local frame = CurrentChatFrame()
			applyAlpha = function(a)
				if frame then pcall(FCF_SetWindowAlpha, frame, a) end
			end
		elseif OpacitySliderFrame then
			useNativeCancel = true
			applyAlpha = function(a)
				pcall(OpacitySliderFrame.SetValue, OpacitySliderFrame, 1 - a)
			end
		end
	end

	request.apply = function(cr, cg, cb, a)
		if applyColor then applyColor(cr, cg, cb) end
		if applyAlpha then applyAlpha(a) end
	end
	request.cancel = function()
		local start = request.start
		request.apply(start.r, start.g, start.b, start.a)
		if useNativeCancel and type(cancelFunc) == "function" then
			pcall(cancelFunc, previous)
		end
	end
	return request
end

local function Open(request)
	EnsureDialog()
	if session then Close(false) end

	session = request
	local start = request.start
	dialog.oldColor:SetVertexColor(start.r, start.g, start.b)
	SetColor(start.r, start.g, start.b, start.a)

	dialog:Show()
	ShowParts(true)
	ticker:Show()
	FlushApply()
end

function M:LoadColorPicker()
	if not ColorPickerFrame then return end

	local S = E:GetModule("Skins")
	S:TryHookScript(ColorPickerFrame, "OnShow", function()
		pcall(ColorPickerFrame.Hide, ColorPickerFrame)
		Open(BuildSession(ColorPickerFrame))
	end)
end
