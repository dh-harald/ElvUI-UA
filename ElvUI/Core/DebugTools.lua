-- DebugTools: an ElvUI-styled Lua error window, the counterpart of real
-- ElvUI's DebugTools module together with its "Debug Tools" skin
-- (ElvUI-vanilla/ElvUI/Modules/Misc/DebugTools.lua and
-- Modules/Skins/Blizzard/Debug.lua). Real ElvUI-vanilla ships a separately
-- packaged backport of Blizzard_DebugTools and styles its ScriptErrorsFrame;
-- here the whole window is built from frames this file creates, so no
-- native frame is touched.
--
-- Capture: the handler is installed with seterrorhandler when this file
-- loads, before any module initializes, so initialization errors are caught
-- as well; until Initialize runs they are only recorded. The handler that
-- was in place before (geterrorhandler, or FrameXML's _ERRORMESSAGE where
-- geterrorhandler does not exist) is kept. With the "Debug Tools" skin flag
-- (E.private.skins.blizzard.debug) off, that handler is reinstalled at
-- Initialize and the recorded errors are handed to it, leaving the client's
-- own error display in charge. With the flag on, this window replaces it.
--
-- Identical messages are merged into one entry with a repeat count, so a
-- script failing on every frame yields one entry. The Unreal Azeroth client
-- already includes the stack traceback in the message; where the message
-- has none, debugstack is appended.
--
-- Automatic opening can be switched off with "/elvui errors off"
-- (E.global.debugTools.autoOpen, takes effect at once): errors are still
-- recorded, and the first new one prints a single chat line pointing to
-- "/elvui errors"; that line repeats only after the window has been opened.
--
-- In combat the window stays closed (real ElvUI's behaviour): one chat line
-- announces the error, and the window opens when combat ends.
-- "/elvui errors" reopens it at any time. Real ElvUI's "ShowErrors" CVar
-- check is not ported: Unreal Azeroth's GetCVar returns "0" for a CVar name
-- it does not register (this one included), which would read as "errors
-- off" and suppress every automatic opening.
--
-- The text sits in a multi-line EditBox, so it can be selected and copied
-- with Ctrl+C. It is not scrollable: Unreal Azeroth has no GetStringHeight to
-- size a scroll child to the text. The area fits a typical message with its
-- traceback; a longer one does not fit.

local E, L = ElvUI[1], ElvUI[2]
local D = E:NewModule("DebugTools", "AceEvent-3.0")
E.DebugTools = D

local getn = ElvUI.Compat.getn

local FRAME_NAME = "ElvUI_ScriptErrorsFrame"
local WINDOW_WIDTH, WINDOW_HEIGHT = 600, 380
-- Distinct messages kept; repeats of a kept message still count.
local MAX_ENTRIES = 100
-- Minimum seconds between repaints caused only by a repeat count changing.
local COUNT_REFRESH_INTERVAL = 0.25

D.entries = {}
D.index = 0
local byMessage = {}

local previousHandler
if type(geterrorhandler) == "function" then
	local ok, handler = pcall(geterrorhandler)
	if ok and type(handler) == "function" then
		previousHandler = handler
	end
end
if not previousHandler and type(_ERRORMESSAGE) == "function" then
	previousHandler = _ERRORMESSAGE
end

local function CallPrevious(message)
	if previousHandler then
		pcall(previousHandler, message)
	end
end

-- Returns the entry and whether it was newly created; nil once MAX_ENTRIES
-- distinct messages are kept.
local function Record(message, stack)
	local entry = byMessage[message]
	if entry then
		entry.count = entry.count + 1
		return entry, false
	end
	if getn(D.entries) >= MAX_ENTRIES then
		return nil, false
	end

	local text = message
	if stack then
		text = message .. "\nstack traceback:\n" .. stack
	end
	entry = { message = message, text = text, count = 1 }
	table.insert(D.entries, entry)
	byMessage[message] = entry
	return entry, true
end

local inHandler = false
local function Handler(message)
	message = tostring(message)
	if inHandler then
		CallPrevious(message)
		return message
	end

	-- Taken here, before any further call, so level 2 is the code that
	-- raised the error rather than this file's own frames.
	local stack
	if not string.find(message, "stack traceback:", 1, true) and type(debugstack) == "function" then
		local okStack, result = pcall(debugstack, 2)
		if okStack and type(result) == "string" and result ~= "" then
			stack = result
		end
	end

	inHandler = true
	local ok, err = pcall(D.OnError, D, message, stack)
	inHandler = false
	if not ok then
		-- The window failed; the error must still reach the player.
		CallPrevious(message)
		CallPrevious(tostring(err))
	end
	return message
end

if type(seterrorhandler) == "function" then
	seterrorhandler(Handler)
end

function D:OnError(message, stack)
	local entry, isNew = Record(message, stack)
	if not entry or not self.initialized then return end

	if isNew then
		self:Announce(getn(self.entries))
	elseif self.frame and self.frame:IsShown() then
		self:RefreshThrottled()
	end
end

-- An open window is only repainted (its "n / total" label grows), never
-- moved to the new entry, so the message being read stays in place.
function D:Announce(index)
	if self.frame and self.frame:IsShown() then
		self:UpdateWindow()
		return
	end

	if not self:GetAutoOpen() then
		if not self.recordedNoticePrinted then
			E:Print(L["Lua error recorded. Type /elvui errors to view it."])
			self.recordedNoticePrinted = true
		end
		return
	end

	if self.inCombat then
		if not self.messagePrinted then
			E:Print(L["|cFFE30000Lua error recieved. You can view the error message when you exit combat."])
			self.messagePrinted = true
		end
		if not self.pendingIndex then
			self.pendingIndex = index
		end
		return
	end

	self:ShowEntry(index)
end

function D:RefreshThrottled()
	local now = GetTime()
	if self.lastRefresh and now - self.lastRefresh < COUNT_REFRESH_INTERVAL then return end
	self.lastRefresh = now
	self:UpdateWindow()
end

-- Same recipe as Core/Install.lua's CreateWizardButton. Enabled state is
-- tracked in a field and shown by label colour, instead of Button:Disable.
local function CreateWindowButton(parent, label, width, onClick)
	local ok, button = pcall(CreateFrame, "Button", nil, parent)
	if not ok or not button then return nil end

	pcall(button.SetWidth, button, width)
	pcall(button.SetHeight, button, 22)
	pcall(button.EnableMouse, button, true)

	-- Above the panel surface S:CreatePanel pins to the parent's own level.
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
		pcall(text.SetText, text, label or "")
		pcall(text.SetTextColor, text, 1, 0.82, 0)
		button.label = text
	end

	button.elvEnabled = true
	button:SetScript("OnEnter", function()
		if button.elvEnabled then
			pcall(button.SetBackdropBorderColor, button, 1, 0.82, 0, 1)
		end
	end)
	button:SetScript("OnLeave", function()
		pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 1)
	end)
	button:SetScript("OnClick", function()
		if button.elvEnabled then onClick() end
	end)

	return button
end

local function SetButtonEnabled(button, enabled)
	if not button then return end
	button.elvEnabled = enabled
	if not enabled then
		pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 1)
	end
	if button.label then
		if enabled then
			pcall(button.label.SetTextColor, button.label, 1, 0.82, 0)
		else
			pcall(button.label.SetTextColor, button.label, 0.5, 0.5, 0.5)
		end
	end
end

function D:BuildWindow()
	if self.frame then return self.frame end

	local ok, frame = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent)
	if not ok or not frame then return nil end
	frame:Hide()

	pcall(frame.SetWidth, frame, WINDOW_WIDTH)
	pcall(frame.SetHeight, frame, WINDOW_HEIGHT)
	pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 0)
	pcall(frame.SetFrameStrata, frame, "FULLSCREEN_DIALOG")
	pcall(frame.SetFrameLevel, frame, 150)
	pcall(frame.EnableMouse, frame, true)
	pcall(frame.SetClampedToScreen, frame, true)

	-- Resolved at build time, after every module file has loaded.
	local S = E.Skins
	if S and S.CreatePanel then
		pcall(S.CreatePanel, S, frame)
	end

	local okClose, closeButton = pcall(CreateFrame, "Button", nil, frame)
	if okClose and closeButton then
		pcall(closeButton.SetWidth, closeButton, 20)
		pcall(closeButton.SetHeight, closeButton, 20)
		pcall(closeButton.SetFrameLevel, closeButton, 160)
		pcall(closeButton.SetPoint, closeButton, "TOPRIGHT", frame, "TOPRIGHT", -8, -8)
		closeButton:SetScript("OnClick", function() pcall(frame.Hide, frame) end)
		if S and S.StyleCloseButton then
			pcall(S.StyleCloseButton, S, closeButton)
		end
	end

	local okTitle, title = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontNormalLarge")
	if okTitle and title then
		pcall(title.SetPoint, title, "TOPLEFT", frame, "TOPLEFT", 14, -12)
		pcall(title.SetText, title, L["Lua Error"])
		pcall(title.SetTextColor, title, 1, 0.82, 0)
	end

	-- Ctrl+A is the reliable way to copy the whole message: a mouse
	-- selection's extent is not drawn past the first line on Unreal Azeroth.
	local okHint, hint = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontDisableSmall")
	if okHint and hint then
		if okTitle and title then
			pcall(hint.SetPoint, hint, "LEFT", title, "RIGHT", 12, 0)
		else
			pcall(hint.SetPoint, hint, "TOPLEFT", frame, "TOPLEFT", 14, -16)
		end
		pcall(hint.SetText, hint, L["To copy: click the text, then Ctrl+A and Ctrl+C."])
	end

	local okIndex, indexLabel = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontNormal")
	if okIndex and indexLabel then
		pcall(indexLabel.SetPoint, indexLabel, "TOPRIGHT", frame, "TOPRIGHT", -36, -14)
		pcall(indexLabel.SetJustifyH, indexLabel, "RIGHT")
		frame.indexLabel = indexLabel
	end

	-- Field well behind the text; the text sits on a child one level up so
	-- it draws over the well's own surface frame.
	local okArea, area = pcall(CreateFrame, "Frame", nil, frame)
	if okArea and area then
		pcall(area.SetPoint, area, "TOPLEFT", frame, "TOPLEFT", 12, -40)
		pcall(area.SetPoint, area, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 40)
		local okLevel, level = pcall(frame.GetFrameLevel, frame)
		local areaLevel = (okLevel and tonumber(level) or 1) + 2
		pcall(area.SetFrameLevel, area, areaLevel)
		if S and S.CreateField then
			pcall(S.CreateField, S, area)
		end

		-- Measured on Unreal Azeroth: a CreateFrame multi-line EditBox renders
		-- line breaks, and a mouse drag selects text across lines, which
		-- Ctrl+C copies; the selection highlight is drawn on the first line
		-- only, so the extent of a selection is not visible. HighlightText is
		-- not registered there, so nothing is selected up front.
		--
		-- Keyboard input is enabled only while the box has focus: a visible
		-- keyboard-enabled frame on Unreal Azeroth swallows every key, which
		-- would block movement while the window is open. Focus is taken on
		-- click and released on Escape, on a click elsewhere in the window,
		-- and when the window hides (Hide does not reliably blur a child
		-- EditBox on this client), so the close button is a mouse-only way
		-- out of it.
		local okEdit, edit = pcall(CreateFrame, "EditBox", nil, area)
		if okEdit and edit then
			pcall(edit.SetWidth, edit, WINDOW_WIDTH - 40)
			pcall(edit.SetHeight, edit, WINDOW_HEIGHT - 96)
			pcall(edit.SetPoint, edit, "TOPLEFT", area, "TOPLEFT", 8, -8)
			pcall(edit.SetFrameLevel, edit, areaLevel + 2)
			pcall(edit.SetMultiLine, edit, true)
			pcall(edit.SetAutoFocus, edit, false)
			pcall(edit.SetFontObject, edit, GameFontHighlightSmall or ChatFontNormal)
			pcall(edit.EnableMouse, edit, true)
			pcall(edit.EnableKeyboard, edit, false)

			local function ReleaseKeyboard()
				pcall(edit.ClearFocus, edit)
				pcall(edit.EnableKeyboard, edit, false)
			end
			edit:SetScript("OnMouseDown", function()
				pcall(edit.EnableKeyboard, edit, true)
				pcall(edit.SetFocus, edit)
			end)
			edit:SetScript("OnEscapePressed", ReleaseKeyboard)
			edit:SetScript("OnEditFocusLost", function()
				pcall(edit.EnableKeyboard, edit, false)
			end)
			frame:SetScript("OnMouseDown", ReleaseKeyboard)
			frame:SetScript("OnHide", ReleaseKeyboard)

			frame.text = edit
		end
	end

	frame.reload = CreateWindowButton(frame, L["Reload UI"], 90, function() ReloadUI() end)
	if frame.reload then
		pcall(frame.reload.SetPoint, frame.reload, "BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
	end

	frame.previous = CreateWindowButton(frame, L["Previous"], 70, function() D:ShowEntry(D.index - 1) end)
	if frame.previous then
		pcall(frame.previous.SetPoint, frame.previous, "BOTTOMRIGHT", frame, "BOTTOM", -2, 10)
	end
	frame.first = CreateWindowButton(frame, L["First"], 60, function() D:ShowEntry(1) end)
	if frame.first and frame.previous then
		pcall(frame.first.SetPoint, frame.first, "RIGHT", frame.previous, "LEFT", -4, 0)
	end
	frame.next = CreateWindowButton(frame, L["Next"], 70, function() D:ShowEntry(D.index + 1) end)
	if frame.next then
		pcall(frame.next.SetPoint, frame.next, "BOTTOMLEFT", frame, "BOTTOM", 2, 10)
	end
	frame.last = CreateWindowButton(frame, L["Last"], 60, function() D:ShowEntry(getn(D.entries)) end)
	if frame.last and frame.next then
		pcall(frame.last.SetPoint, frame.last, "LEFT", frame.next, "RIGHT", 4, 0)
	end

	frame.clear = CreateWindowButton(frame, L["Clear"], 80, function() D:ClearErrors() end)
	if frame.clear then
		pcall(frame.clear.SetPoint, frame.clear, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
	end

	-- Escape closes it, as with the other standalone windows (Bags, Loot).
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, FRAME_NAME)
	end

	self.frame = frame
	return frame
end

function D:UpdateWindow()
	local frame = self.frame
	if not frame then return end

	local total = getn(self.entries)
	if self.index > total then self.index = total end
	if self.index < 1 and total > 0 then self.index = 1 end

	local entry = self.entries[self.index]
	if frame.text then
		local message = ""
		if entry then
			-- A literal "|" would start an escape sequence in a FontString.
			message = string.gsub(entry.text, "|", "||")
		end
		pcall(frame.text.SetText, frame.text, message)
	end

	if frame.indexLabel then
		local label = string.format("%d / %d", self.index, total)
		if entry and entry.count > 1 then
			label = label .. string.format("  (x%d)", entry.count)
		end
		pcall(frame.indexLabel.SetText, frame.indexLabel, label)
	end

	SetButtonEnabled(frame.first, self.index > 1)
	SetButtonEnabled(frame.previous, self.index > 1)
	SetButtonEnabled(frame.next, self.index < total)
	SetButtonEnabled(frame.last, self.index < total)
	SetButtonEnabled(frame.clear, total > 0)
end

function D:ShowEntry(index)
	local total = getn(self.entries)
	if total == 0 then return end
	if index < 1 then index = 1 end
	if index > total then index = total end
	self.index = index

	local frame = self:BuildWindow()
	if not frame then return end
	self:UpdateWindow()
	frame:Show()
	self.recordedNoticePrinted = nil
end

function D:ShowErrors()
	if getn(self.entries) == 0 then
		E:Print(L["No Lua errors recorded."])
		return
	end
	if self.index < 1 then
		self.index = getn(self.entries)
	end
	self:ShowEntry(self.index)
end

function D:GetAutoOpen()
	local settings = E.global and E.global.debugTools
	return not settings or settings.autoOpen ~= false
end

function D:SetAutoOpen(enabled)
	if E.global then
		E.global.debugTools = E.global.debugTools or {}
		E.global.debugTools.autoOpen = enabled and true or false
	end
	if enabled then
		E:Print(L["Lua error window: opens automatically."])
	else
		E:Print(L["Lua error window: does not open automatically. /elvui errors shows recorded errors."])
	end
end

function D:ClearErrors()
	self.entries = {}
	byMessage = {}
	self.index = 0
	self.pendingIndex = nil
	if self.frame then
		self.frame:Hide()
	end
end

function D:PLAYER_REGEN_DISABLED()
	self.inCombat = true
	if self.frame and self.frame:IsShown() then
		self.frame:Hide()
		self.reopenAfterCombat = true
	end
end

function D:PLAYER_REGEN_ENABLED()
	self.inCombat = nil
	self.messagePrinted = nil
	local index = self.pendingIndex
	if not index and self.reopenAfterCombat then
		index = self.index
	end
	self.pendingIndex = nil
	self.reopenAfterCombat = nil
	if index then
		self:ShowEntry(index)
	end
end

-- Errors recorded before login are shown once the world is entered, after
-- every module (Skins included) has initialized.
function D:PLAYER_ENTERING_WORLD()
	if self.loginShown then return end
	self.loginShown = true
	if getn(self.entries) > 0 then
		self:Announce(1)
	end
end

function D:Initialize()
	self.initialized = true

	local blizzard = E.private and E.private.skins and E.private.skins.blizzard
	local enabled = blizzard and blizzard.enable and blizzard.debug
	-- Without a previous handler there is nothing to hand errors back to,
	-- so the window stays in charge regardless of the flag.
	if not enabled and previousHandler and type(seterrorhandler) == "function" then
		seterrorhandler(previousHandler)
		local i
		for i = 1, getn(self.entries) do
			CallPrevious(self.entries[i].text)
		end
		return
	end

	if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then
		self.inCombat = true
	end
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

E:RegisterInitialModule(D:GetName(), function() D:Initialize() end)
