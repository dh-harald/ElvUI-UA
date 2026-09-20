-- Inbox side of the Mail module: a checkbox on every inbox row, the two
-- buttons that empty mail in bulk (Open All / Open Selected), the expiry
-- warning that marks mail facing deletion rather than return, and the money
-- total printed at the end of a bulk run.
--
-- Mail is processed HIGHEST INDEX FIRST. Emptying a mail can remove it from
-- the inbox, which renumbers everything after it; walking down means every
-- index still waiting in the queue is below the one being worked on, so no
-- renumbering can reach it. (Postal walks up instead and adjusts the whole
-- queue after each removal.)
--
-- One mail can need two passes, money then item, in that order: money never
-- empties a mail that still has an item on it, so the index survives the
-- first pass, and the item -- the take that can remove the mail -- is always
-- the last thing done to an index. C.O.D. mail is always skipped: taking it
-- charges the player.
--
-- Mail that has nothing attached is LEFT IN THE INBOX, deliberately: it may
-- be a letter someone wrote, and the mailbox is where it can still be read.
--
-- The rows are shifted right and narrowed to make room for the checkbox
-- column, the same layout change Postal makes. Expire time keeps its place
-- relative to the (now narrower) row.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Mail")
local Compat = ElvUI.Compat
local getn = Compat.getn

local CHECK_SIZE = 20
-- Three buttons share the row width plus the checkbox column (302), with a
-- 7px gap between them. Long translations overflow a 96px button rather than
-- wrap, which is cosmetic only.
local BUTTON_WIDTH = 96
local BUTTON_HEIGHT = 22
local ROW_INDENT = 48
local ROW_WIDTH = 280

local checkBoxes = {}
local openAllButton, openSelectedButton, returnSelectedButton

M.selected = {}

local function RowCount()
	return tonumber(_G.INBOXITEMS_TO_DISPLAY) or 7
end

local function AbsoluteIndex(row)
	local page = tonumber(_G.InboxFrame and _G.InboxFrame.pageNum) or 1
	return row + (page - 1) * RowCount()
end

-- Makes room on the left of every row for the checkbox column.
local function ReflowRows()
	local first = _G.MailItem1
	if not first then return end

	pcall(first.ClearAllPoints, first)
	pcall(first.SetPoint, first, "TOPLEFT", _G.InboxFrame, "TOPLEFT", ROW_INDENT, -80)

	-- Only the width changes; the expire time keeps its native anchor to the
	-- row's own right edge and follows it in.
	for i = 1, RowCount() do
		local row = _G["MailItem"..i]
		if row then pcall(row.SetWidth, row, ROW_WIDTH) end
	end
end

-- The client colours a row's expiry by TIME LEFT only -- green above a day, a
-- red countdown below (`MailFrame.lua:143-147`) -- so a mail that will be
-- DELETED when it runs out looks exactly like one that goes back to its
-- sender, right up to the last day. `InboxItemCanDelete` is the client's own
-- answer to which of the two a mail faces; the native code already uses it,
-- but only for the row's tooltip (`MailFrame.lua:151`).
--
-- Recolouring means rewriting the string: the native text carries its colour
-- baked in as an escape sequence, which `SetTextColor` cannot override. The
-- text is re-read rather than rebuilt so the localized day wording stays
-- whatever the client produced.
local EXPIRY_WARNING = "|cffff8000"

local function MarkExpiry(row, index)
	if not (E.global and E.global.mail and E.global.mail.expiryWarning) then return end
	if not InboxItemCanDelete then return end

	local expire = _G["MailItem"..row.."ExpireTime"]
	if not expire then return end

	local okDelete, canDelete = pcall(InboxItemCanDelete, index)
	if not (okDelete and Compat.bool(canDelete)) then return end

	-- Under a day the native countdown is already red; a second warning
	-- colour there would only make the urgent case stand out less.
	local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(index)
	if (tonumber(daysLeft) or 0) < 1 then return end

	local okText, text = pcall(expire.GetText, expire)
	if not (okText and text) then return end
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	pcall(expire.SetText, expire, EXPIRY_WARNING..text.."|r")
end

local function SetMarkShown(box, shown)
	if not box or not box.elvMark then return end
	if shown then
		pcall(box.elvMark.Show, box.elvMark)
	else
		pcall(box.elvMark.Hide, box.elvMark)
	end
end

local function OnCheckBoxClick(box)
	local index = AbsoluteIndex(box.elvRow)

	-- A bulk run owns the selection while it lasts, so a click during one
	-- only re-asserts what is on screen.
	if M.running then
		pcall(box.SetChecked, box, nil)
		SetMarkShown(box, false)
		return
	end

	local ok, checked = pcall(box.GetChecked, box)
	checked = ok and Compat.bool(checked)
	if checked then
		M.selected[index] = true
	else
		M.selected[index] = nil
	end
	SetMarkShown(box, checked)
end

-- Controls are built in this UI's own style directly, not from the native
-- templates: while this module runs the window is skinned too (see
-- M:EnsureWindowSkin), so there is never a native-looking mailbox for a
-- native-looking control to match. Building them styled also keeps them
-- independent of the skin sweep's widget recognition.
local function SetButtonText(button, text)
	button.elvLabel:SetText(text)
end

local function BuildCheckBox(row, i)
	local S = E:GetModule("Skins")

	local box = CreateFrame("CheckButton", "ElvUI_MailSelect"..i, row)
	box:SetWidth(CHECK_SIZE)
	box:SetHeight(CHECK_SIZE)
	box:SetPoint("RIGHT", row, "LEFT", -2, 0)
	E:SetTemplate(box, "Default")
	box.elvRow = i

	-- Same tick as every skinned checkbox in the UI: a filled square in the
	-- skin accent, NOT the profile's own value colour (which is class-
	-- coloured in many profiles and would read as a different control).
	local mark = box:CreateTexture(nil, "OVERLAY")
	mark:SetPoint("TOPLEFT", box, "TOPLEFT", S.CHECKMARK_INSET, -S.CHECKMARK_INSET)
	mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -S.CHECKMARK_INSET, S.CHECKMARK_INSET)
	mark:SetTexture("Interface\\Buttons\\WHITE8x8")
	mark:SetVertexColor(S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	mark:Hide()
	box.elvMark = mark

	box:SetScript("OnClick", function() OnCheckBoxClick(box) end)
	return box
end

-- Accent text on the widget fill, and a border recolour on hover.
--
-- NOT `S:HandleButtonHighlight`: its gradient textures are drawn on the
-- HIGHLIGHT layer, which this client renders CONSTANTLY on a frame that has
-- no native highlight texture of its own -- the button then reads as a
-- washed-out grey slab instead of a flat one. Same client behaviour that
-- keeps `Util.SkinItemButton` from applying real ElvUI's hover overlay.
local function BuildButton(name, text, onClick)
	local S = E:GetModule("Skins")

	local button = CreateFrame("Button", name, _G.InboxFrame)
	button:SetWidth(BUTTON_WIDTH)
	button:SetHeight(BUTTON_HEIGHT)
	E:SetTemplate(button, "Default")

	local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER", button, "CENTER", 0, 0)
	label:SetTextColor(S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	label:SetText(text)
	button.elvLabel = label

	button:SetScript("OnEnter", function()
		local accent = E.db and E.db.general and E.db.general.valuecolor
		if accent then
			pcall(button.SetBackdropBorderColor, button, accent.r, accent.g, accent.b, 1)
		end
	end)
	button:SetScript("OnLeave", function() E:SetTemplate(button, "Default") end)
	button:SetScript("OnClick", onClick)
	return button
end

local function BuildWidgets()
	for i = 1, RowCount() do
		local row = _G["MailItem"..i]
		if row and not checkBoxes[i] then
			checkBoxes[i] = BuildCheckBox(row, i)
		end
	end

	if not openAllButton then
		openAllButton = BuildButton("ElvUI_MailOpenAll", L["Open All"], function() M:OpenMail(true) end)
		openAllButton:SetPoint("BOTTOMLEFT", _G.MailItem1, "TOPLEFT", -CHECK_SIZE - 2, 6)
	end
	-- Middle of the three: the span runs from the checkbox column's left edge
	-- to the row's right edge, so its centre sits half the checkbox column
	-- left of the row's own centre.
	if not openSelectedButton then
		openSelectedButton = BuildButton("ElvUI_MailOpenSelected", L["Open Selected"], function() M:OpenMail(false) end)
		openSelectedButton:SetPoint("BOTTOM", _G.MailItem1, "TOP", -(CHECK_SIZE + 2) / 2, 6)
	end
	if not returnSelectedButton then
		returnSelectedButton = BuildButton("ElvUI_MailReturnSelected", L["Return Selected"], function() M:ReturnMail() end)
		returnSelectedButton:SetPoint("BOTTOMRIGHT", _G.MailItem1, "TOPRIGHT", 0, 6)
	end
end

-- While a run is going the two buttons become one way to stop it, so a run
-- that is taking longer than expected never has to be waited out.
function M:UpdateButtons()
	local text = self.running and L["Stop"] or nil
	if openAllButton then
		SetButtonText(openAllButton, text or L["Open All"])
	end
	if openSelectedButton then
		SetButtonText(openSelectedButton, text or L["Open Selected"])
	end
	if returnSelectedButton then
		SetButtonText(returnSelectedButton, text or L["Return Selected"])
	end
end

-- Runs after every native inbox refresh: page turns, mail arriving, and
-- each step of a bulk run.
function M:UpdateInbox()
	local count = GetInboxNumItems() or 0

	-- Selection is by inbox index, so anything that renumbers the inbox
	-- from outside a run (mail arriving, a mail opened by hand) would leave
	-- the checkboxes pointing at different mail than the player ticked.
	if not self.running and self.lastCount and count ~= self.lastCount then
		self.selected = {}
	end
	self.lastCount = count

	for i = 1, RowCount() do
		local box = checkBoxes[i]
		if box then
			local index = AbsoluteIndex(i)
			if index <= count then
				local checked = self.selected[index] and true or nil
				pcall(box.SetChecked, box, checked)
				SetMarkShown(box, checked)
				box:Show()
				MarkExpiry(i, index)
			else
				pcall(box.SetChecked, box, nil)
				SetMarkShown(box, false)
				box:Hide()
			end
		end
	end
end

-- Opening a mail by hand mid-run would compete with the run for the same
-- mail request slot, so row clicks are swallowed until it finishes.
--
-- Express: a held modifier turns a row click into the action itself, without
-- opening the mail -- Shift empties that one mail, Ctrl sends it back. Both
-- go through the ordinary run machinery with a one-mail queue, so a click
-- cannot race a bulk run and clears the ticks the same way one does. The
-- mouse wheel, which Postal also binds, is deliberately left out: this
-- client delivers wheel events on ScrollFrames only, and an inbox row is not
-- one.
function M:InboxClick(index)
	if self.running then
		local caller = this
		if caller and caller.SetChecked then pcall(caller.SetChecked, caller, nil) end
		this = caller
		return
	end

	if E.global and E.global.mail and E.global.mail.express then
		if IsShiftKeyDown() then
			return self:BeginRun("open", { index })
		elseif IsControlKeyDown() then
			return self:BeginRun("return", { index })
		end
	end

	return self.hooks["InboxFrame_OnClick"](index)
end

-- Highest index first, always: removing a mail renumbers everything ABOVE
-- it, so a descending queue can never be invalidated by its own work.
local function BuildQueue(all, count, selected)
	local queue = {}
	if all then
		local i
		for i = 1, count do table.insert(queue, i) end
	else
		for index in pairs(selected) do
			if index <= count then table.insert(queue, index) end
		end
	end
	table.sort(queue, function(a, b) return a > b end)
	return queue
end

function M:BeginRun(mode, queue)
	self.running = true
	self.mode = mode
	self.queue = queue
	self.current = nil
	self.currentTag = nil
	self.skippedCOD = 0
	self.skippedReturn = 0
	self.cleanup = {}
	self.cleaned = 0
	self.rakeTotal = 0
	self.rakeCount = 0
	-- Indices shift as mail is removed, so a leftover tick would point at
	-- different mail by the time the run ends.
	self.selected = {}

	self.tick = function() M:Step() end
	self:UpdateButtons()
	pcall(InboxFrame_Update)
end

function M:OpenMail(all)
	if self.running then
		return self:StopOpening(self:StopMessage())
	end

	local count = GetInboxNumItems() or 0
	local queue = BuildQueue(all, count, self.selected)
	if getn(queue) == 0 then
		E:Print(all and L["The mailbox is empty."] or L["No mail selected."])
		return
	end

	self:BeginRun("open", queue)
end

function M:ReturnMail()
	if self.running then
		return self:StopOpening(self:StopMessage())
	end

	local count = GetInboxNumItems() or 0
	local queue = BuildQueue(false, count, self.selected)
	if getn(queue) == 0 then
		E:Print(L["No mail selected."])
		return
	end

	self:BeginRun("return", queue)
end

function M:StopMessage()
	if self.mode == "return" then return L["Stopped returning mail."] end
	return L["Stopped opening mail."]
end

-- Identifies the mail currently sitting at an index. Emptying a mail removes
-- it from the inbox unless it carries letter text, and everything above it
-- then shifts down one -- so an index alone does not name a mail across a
-- take. The inbox SIZE cannot stand in for this: it does not drop at the
-- moment the attachment disappears, so a step that compares counts right
-- after a successful take still sees the old number and happily re-reads an
-- index that now points at the next mail. Comparing sender+subject is
-- immediate and needs no timing assumption.
local function MailTag(index)
	local _, _, sender, subject = GetInboxHeaderInfo(index)
	return tostring(sender or "").."\t"..tostring(subject or "")
end

-- Remembers a mail this run took something from, as a candidate for the
-- cleanup phase at the end. Identity, not index: indices shift as mail
-- leaves the inbox.
local function RecordEmptied(tag)
	M.cleanup = M.cleanup or {}
	local i
	for i = 1, getn(M.cleanup) do
		if M.cleanup[i] == tag then return end
	end
	table.insert(M.cleanup, tag)
end

-- Money is taken BEFORE the item on purpose: money is never the attachment
-- that removes a mail while an item is still on it, so the mail is
-- guaranteed to survive that first take and the same index stays valid for
-- the second pass. The item goes last, and the index is released right
-- after it -- there is never a reason to re-read an index whose mail may
-- have just been removed.
function M:Step()
	if not self.running then return end

	local index = self.current
	if not index then
		index = table.remove(self.queue, 1)
		if not index then return self:FinishOpening() end
		self.current = index
		self.currentTag = nil
	end

	local count = GetInboxNumItems() or 0
	if index > count then
		self.current = nil
		return
	end

	-- Second and later passes over one mail: anything but the mail this run
	-- started on is a mail the player never picked.
	local tag = MailTag(index)
	if self.currentTag and self.currentTag ~= tag then
		self.current = nil
		return
	end
	self.currentTag = tag

	if self.mode == "return" then return self:StepReturn(index, tag) end

	local _, _, _, _, money, cod, _, hasItem = GetInboxHeaderInfo(index)
	money = tonumber(money) or 0
	cod = tonumber(cod) or 0

	if cod > 0 then
		self.skippedCOD = self.skippedCOD + 1
		self.current = nil
		return
	end

	hasItem = Compat.bool(hasItem)

	if money > 0 then
		TakeInboxMoney(index)
		self:WaitFor(function()
			local _, _, _, _, moneyLeft = GetInboxHeaderInfo(index)
			return (tonumber(moneyLeft) or 0) == 0 or MailTag(index) ~= tag
		end, function()
			E:Print(string.format(L["Received %s."], E:FormatMoney(money, "SMART")))
			RecordEmptied(tag)
			M.rakeTotal = (M.rakeTotal or 0) + money
			M.rakeCount = (M.rakeCount or 0) + 1
			-- With no item left behind, the money WAS the last attachment.
			if not hasItem then M.current = nil end
		end, function()
			E:Print(L["Could not take everything from one mail -- skipped it."])
			M.current = nil
		end)
		return
	end

	if hasItem then
		if self:FreeBagSlots() <= 0 then
			return self:StopOpening(L["Your bags are full -- stopped opening mail."])
		end

		local name, _, stack = GetInboxItem(index)
		TakeInboxItem(index)
		self:WaitFor(function()
			local _, _, _, _, _, _, _, stillHasItem = GetInboxHeaderInfo(index)
			return not Compat.bool(stillHasItem) or MailTag(index) ~= tag
		end, function()
			if name then
				E:Print(string.format(L["Received %s (x%d)."], name, tonumber(stack) or 1))
			end
			RecordEmptied(tag)
			M.current = nil
		end, function()
			-- The item is still attached: most often the player already
			-- carries the maximum of a unique item.
			E:Print(L["Could not take everything from one mail -- skipped it."])
			M.current = nil
		end)
		return
	end

	self.current = nil
end

-- Returning is a single shot per mail and the mail ALWAYS leaves the inbox
-- afterwards -- letter text does not keep it, the way it does for a mail that
-- was merely emptied. So there is no second pass and no reason to look at the
-- inbox size: the index is done as soon as a different mail sits at it.
--
-- `InboxItemCanDelete` is the client's own answer to whether a mail can go
-- back: where it is true the native window offers DELETE instead of RETURN
-- (`MailFrame.lua:417-421`), and this module never deletes mail.
function M:StepReturn(index, tag)
	local okDelete, canDelete = pcall(InboxItemCanDelete, index)
	if okDelete and Compat.bool(canDelete) then
		self.skippedReturn = self.skippedReturn + 1
		self.current = nil
		return
	end

	local _, _, sender = GetInboxHeaderInfo(index)
	ReturnInboxItem(index)
	self:WaitFor(function()
		return MailTag(index) ~= tag
	end, function()
		E:Print(string.format(L["Returned mail to %s."], tostring(sender or "")))
		M.current = nil
	end, function()
		E:Print(L["Could not return one mail -- skipped it."])
		M.current = nil
	end)
end

-- Cleanup phase: removes the mails THIS RUN emptied, so a bulk open does not
-- leave a row of empty mails behind. Everything about it is built to make
-- deleting the wrong mail impossible.
--
-- The test for "disposable" is the client's OWN rule, not one of ours: the
-- native window deletes a mail on closing it when `money == 0 and not itemID
-- and textCreated` (`MailFrame.lua:264-268`). MEASURED, because the field
-- name misleads: `textCreated` is FALSE while a letter is still there to
-- read, and TRUE once there is nothing left to create -- either the letter
-- was taken as an item, or the mail never carried one. A mail someone wrote
-- therefore never clears this guard.
--
-- On top of that: only mails this run actually took something from are
-- candidates, they are found again by sender+subject rather than by a
-- remembered index (indices shift as mail leaves), and every condition is
-- re-checked at the moment of deletion. A candidate the client already
-- removed is simply not found, and nothing happens.
--
-- The phase runs AFTER the main queue, never between two takes, because an
-- index is least trustworthy right after a take.
local function FindMailByTag(tag)
	local count = GetInboxNumItems() or 0
	local i
	for i = 1, count do
		if MailTag(i) == tag then return i end
	end
	return nil
end

local function IsDisposable(index)
	local _, _, _, _, money, cod, _, hasItem, _, _, textCreated = GetInboxHeaderInfo(index)
	if (tonumber(money) or 0) > 0 then return false end
	if (tonumber(cod) or 0) > 0 then return false end
	if Compat.bool(hasItem) then return false end
	return Compat.bool(textCreated)
end

function M:StepCleanup()
	if not self.running then return end

	local tag = table.remove(self.cleanup, 1)
	if not tag then return self:FinishRun() end

	local index = FindMailByTag(tag)
	if not index then return end
	if not IsDisposable(index) then return end

	DeleteInboxItem(index)
	self:WaitFor(function()
		return FindMailByTag(tag) == nil
	end, function()
		M.cleaned = (M.cleaned or 0) + 1
	end, nil)
end

function M:FinishOpening()
	-- Hand over to the cleanup phase first, unless this IS the cleanup phase
	-- or the mailbox is already gone.
	if self.running and self.mode ~= "cleanup"
		and E.global and E.global.mail and E.global.mail.cleanEmptied
		and self.cleanup and getn(self.cleanup) > 0 then
		self.mode = "cleanup"
		self.current = nil
		self.currentTag = nil
		self.queue = {}
		self:ClearWait()
		self.tick = function() M:StepCleanup() end
		return
	end

	return self:FinishRun()
end

function M:FinishRun()
	self.running = nil
	self.tick = nil
	self.current = nil
	self.currentTag = nil
	self.queue = {}
	self.cleanup = nil
	self:ClearWait()

	if self.cleaned and self.cleaned > 0 then
		E:Print(string.format(L["Removed %d emptied mail(s)."], self.cleaned))
	end
	self.cleaned = 0

	-- Only worth a total when it adds something the per-mail lines did not:
	-- one money mail already printed its own amount.
	if E.global and E.global.mail and E.global.mail.moneySummary
		and self.rakeCount and self.rakeCount > 1 and self.rakeTotal and self.rakeTotal > 0 then
		E:Print(string.format(L["Collected %s."], E:FormatMoney(self.rakeTotal, "SMART")))
	end
	self.rakeTotal = 0
	self.rakeCount = 0

	if self.skippedCOD and self.skippedCOD > 0 then
		E:Print(string.format(L["Skipped %d C.O.D. mail(s)."], self.skippedCOD))
	end
	self.skippedCOD = 0

	if self.skippedReturn and self.skippedReturn > 0 then
		E:Print(string.format(L["Skipped %d mail(s) that cannot be returned."], self.skippedReturn))
	end
	self.skippedReturn = 0
	self.mode = nil

	self:UpdateButtons()
	pcall(InboxFrame_Update)
end

function M:StopOpening(message)
	if message then E:Print(message) end
	-- Stop means stop: no cleanup phase, so a run the player interrupted
	-- never deletes anything on its way out.
	self:FinishRun()
end

function M:OnMailClosed()
	-- Straight to the end, never into the cleanup phase: with the mailbox
	-- shut there is nothing to delete against.
	if self.running then self:FinishRun() end
	self.selected = {}
	self.lastCount = nil
end

function M:LoadInbox()
	if not _G.InboxFrame or not _G.MailItem1 then return end

	ReflowRows()
	BuildWidgets()
	self:UpdateInbox()

	self:SecureHook("InboxFrame_Update", function() M:UpdateInbox() end)
	self:RawHook("InboxFrame_OnClick", function(index) return M:InboxClick(index) end)
end
