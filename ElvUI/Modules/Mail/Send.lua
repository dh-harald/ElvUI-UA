-- Send side of the Mail module: an attachment grid that holds up to twelve
-- items and sends them in one go.
--
-- This client carries ONE attachment per mail -- `SendMailPackageButton` is a
-- single slot -- so twelve queued items become twelve mails, numbered in the
-- subject. The cap is twelve to match the attachments a later WoW allows on
-- one mail; here that number is a queue length, not a mail's capacity.
--
-- A SLOT NEVER HOLDS THE ITEM. It remembers where the item lives (bag, slot)
-- and draws its icon; the item stays in the bag until its own mail goes out.
-- That is what lifts the one-slot limit: the native slot is filled and
-- emptied once per mail, from the queue. (Recipe from Postal.)
--
-- The grid takes its room from the letter body, which is the only part of
-- this window with height to spare.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Mail")
local Compat = ElvUI.Compat
local getn = Compat.getn

local SLOT_COUNT = 12
local SLOTS_PER_ROW = 6
local SLOT_SIZE = 32
local SLOT_GAP = 4
local GRID_MARGIN = 8

local slots = {}
local gridHeight = 0

local function GridHeight()
	local rows = SLOT_COUNT / SLOTS_PER_ROW
	return rows * SLOT_SIZE + (rows - 1) * SLOT_GAP + GRID_MARGIN * 2
end

-- What the queue is, in send order: the filled slots, gaps skipped.
local function Attachments()
	local list = {}
	local i
	for i = 1, SLOT_COUNT do
		local slot = slots[i]
		if slot and slot.elvBag then
			table.insert(list, { bag = slot.elvBag, slot = slot.elvSlot })
		end
	end
	return list
end

local function SlotIcon(bag, slot)
	if not bag then return nil, nil end
	local texture, count = GetContainerItemInfo(bag, slot)
	return texture, count
end

local function RefreshSlot(i)
	local slot = slots[i]
	if not slot then return end

	local texture, count = SlotIcon(slot.elvBag, slot.elvSlot)

	-- An item that left its bag slot (sold, moved, sent) cannot be attached
	-- any more, so the reference is dropped rather than kept pointing at
	-- whatever moved in.
	if slot.elvBag and not texture then
		slot.elvBag, slot.elvSlot = nil, nil
	end

	if texture then
		pcall(slot.elvIcon.SetTexture, slot.elvIcon, texture)
		pcall(slot.elvIcon.Show, slot.elvIcon)
		if count and count > 1 then
			pcall(slot.elvCount.SetText, slot.elvCount, count)
			pcall(slot.elvCount.Show, slot.elvCount)
		else
			pcall(slot.elvCount.Hide, slot.elvCount)
		end
	else
		pcall(slot.elvIcon.Hide, slot.elvIcon)
		pcall(slot.elvCount.Hide, slot.elvCount)
	end
end

-- Repaints the open bags through their own update path, so a slot that was
-- just filled or cleared greys or ungreys its bag item at once instead of
-- waiting for the next inventory event.
local function RefreshBagFrames()
	if not _G.ContainerFrame_Update then return end
	local i
	for i = 1, 11 do
		local frame = _G["ContainerFrame"..i]
		if frame then
			local okShown, shown = pcall(frame.IsVisible, frame)
			if okShown and shown then pcall(_G.ContainerFrame_Update, frame) end
		end
	end
end

function M:RefreshAttachments()
	local i
	for i = 1, SLOT_COUNT do RefreshSlot(i) end
	RefreshBagFrames()
end

-- True once the grid holds anything, which is also what decides whether a
-- click on Send goes through this module at all.
function M:HasAttachments()
	return getn(Attachments()) > 0
end

local function FirstFreeSlot()
	local i
	for i = 1, SLOT_COUNT do
		local slot = slots[i]
		if slot and not slot.elvBag then return i end
	end
	return nil
end

-- A bag slot is "queued" while the grid points at it, and while a send that
-- has already read the grid is still working through its list. Both have to
-- count: the item must stay put until its own mail is out.
local function AlreadyQueued(bag, slot)
	local i
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s and s.elvBag == bag and s.elvSlot == slot then return true end
	end
	if M.sendQueue then
		for i = 1, getn(M.sendQueue) do
			local item = M.sendQueue[i]
			if item.bag == bag and item.slot == slot then return true end
		end
	end
	return false
end

-- The name inside an item link, which is the only place a bag slot offers
-- one: `GetContainerItemInfo` returns a texture and a count, never a name.
local function BagItemName(bag, slot)
	local okLink, link = pcall(GetContainerItemLink, bag, slot)
	if not (okLink and link) then return nil end
	local _, _, name = string.find(link, "%[(.+)%]")
	return name
end

-- Mirrors what the client does with its own single slot: attaching an item
-- names the mail after it, and the Send button only enables once the subject
-- is non-empty (`MailFrame.lua:521-528`, `:576`). Without this the queue
-- never touches the native slot, so the subject would stay empty and Send
-- would stay dead. A subject the player typed is left alone, tracked the
-- same way the native code tracks `SendMailFrame.previousItem`.
local function FillSubject(bag, slot)
	local box = _G.SendMailSubjectEditBox
	if not box then return end

	local okText, current = pcall(box.GetText, box)
	if not okText then return end
	if current ~= "" and current ~= M.subjectAutoFill then return end

	local name = BagItemName(bag, slot)
	if not name then return end

	local _, count = GetContainerItemInfo(bag, slot)
	if count and count > 1 then name = name.." ("..count..")" end

	pcall(box.SetText, box, name)
	M.subjectAutoFill = name
end

function M:AttachBagItem(bag, slot)
	if AlreadyQueued(bag, slot) then return true end

	local index = FirstFreeSlot()
	if not index then
		E:Print(L["The attachment list is full."])
		return true
	end

	slots[index].elvBag = bag
	slots[index].elvSlot = slot
	FillSubject(bag, slot)
	RefreshSlot(index)
	RefreshBagFrames()
	return true
end

-- Public: a bag addon drawing its own item buttons can ask whether a slot is
-- spoken for, and grey it out itself. The greying this file does reaches the
-- stock container frames only (see the `SetItemButtonDesaturated` hook), and
-- the block on picking the item up is API-level, so a replacement bag will
-- find the item immovable either way -- this is what makes it LOOK immovable
-- there too.
function M:IsMailAttachment(bag, slot)
	return AlreadyQueued(bag, slot)
end

local function OnSlotClick(index)
	local slot = slots[index]
	if not slot then return end

	-- Dropping an item that is being dragged: the cursor is put back where
	-- it came from, because the queue only ever needs the bag coordinates.
	if CursorHasItem() and M.cursorBag then
		if not AlreadyQueued(M.cursorBag, M.cursorSlot) then
			slot.elvBag = M.cursorBag
			slot.elvSlot = M.cursorSlot
			FillSubject(slot.elvBag, slot.elvSlot)
		end
		ClearCursor()
		M.cursorBag, M.cursorSlot = nil, nil
		RefreshSlot(index)
		RefreshBagFrames()
		return
	end

	-- Clicking a filled slot takes the item out of the queue. The item never
	-- left the bag, so this is the whole of "putting it back": the bag slot
	-- unfreezes and stops being grey.
	slot.elvBag, slot.elvSlot = nil, nil
	RefreshSlot(index)
	RefreshBagFrames()

	-- Emptying the grid takes the auto-filled subject with it, the way the
	-- native code drops its own when the slot is cleared
	-- (`MailFrame.lua:532-533`).
	if not M:HasAttachments() then M:ClearAutoSubject() end
end

function M:ClearAutoSubject()
	local box = _G.SendMailSubjectEditBox
	if box and self.subjectAutoFill then
		local okText, current = pcall(box.GetText, box)
		if okText and current == self.subjectAutoFill then pcall(box.SetText, box, "") end
	end
	self.subjectAutoFill = nil
end

local function BuildSlot(i)
	local button = CreateFrame("Button", "ElvUI_MailAttach"..i, _G.SendMailFrame)
	button:SetWidth(SLOT_SIZE)
	button:SetHeight(SLOT_SIZE)
	E:SetTemplate(button, "Default")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:Hide()
	button.elvIcon = icon

	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
	count:Hide()
	button.elvCount = count

	button:SetScript("OnClick", function() OnSlotClick(i) end)
	button:SetScript("OnReceiveDrag", function() OnSlotClick(i) end)
	button:SetScript("OnEnter", function()
		local accent = E.db and E.db.general and E.db.general.valuecolor
		if accent then
			pcall(button.SetBackdropBorderColor, button, accent.r, accent.g, accent.b, 1)
		end
	end)
	button:SetScript("OnLeave", function() E:SetTemplate(button, "Default") end)

	return button
end

-- The letter body gives up the grid's height. Both the scroll frame and the
-- box inside it have to shrink: the compose box is ours (see the Mail skin)
-- and was built at the native body's size.
local function MakeRoom()
	local scroll = _G.SendMailScrollFrame
	if not scroll or scroll.elvGridShrunk then return end

	local okHeight, height = pcall(scroll.GetHeight, scroll)
	if not (okHeight and height and height > gridHeight + 40) then return end

	pcall(scroll.SetHeight, scroll, height - gridHeight)
	scroll.elvGridShrunk = true

	local child = _G.SendMailScrollChildFrame
	if child then
		local okChild, childHeight = pcall(child.GetHeight, child)
		if okChild and childHeight then pcall(child.SetHeight, child, childHeight - gridHeight) end
	end

	local body = _G.ElvUI_MailBody or _G.SendMailBodyEditBox
	if body then
		local okBody, bodyHeight = pcall(body.GetHeight, body)
		if okBody and bodyHeight then pcall(body.SetHeight, body, bodyHeight - gridHeight) end
	end
end

function M:LoadSend()
	if not _G.SendMailFrame or not _G.SendMailScrollFrame then return end
	if slots[1] then return end

	gridHeight = GridHeight()
	MakeRoom()

	local i
	for i = 1, SLOT_COUNT do
		local button = BuildSlot(i)
		local row = math.floor((i - 1) / SLOTS_PER_ROW)
		local column = i - 1 - row * SLOTS_PER_ROW
		button:SetPoint("TOPLEFT", _G.SendMailScrollFrame, "BOTTOMLEFT",
			column * (SLOT_SIZE + SLOT_GAP),
			-(GRID_MARGIN + row * (SLOT_SIZE + SLOT_GAP)))
		slots[i] = button
	end

	-- A QUEUED bag slot is frozen: it cannot be picked up, used or clicked
	-- until its mail has gone out, because the item has to still be there
	-- when its turn comes. Three entry points reach a bag item, and all
	-- three are blocked the same way. (Recipe from Postal.)
	--
	-- `PickupContainerItem` doubles as the source of the cursor's origin:
	-- this client cannot be asked what the cursor is carrying.
	self:RawHook("PickupContainerItem", function(bag, slot)
		if AlreadyQueued(bag, slot) then return end
		M.cursorBag, M.cursorSlot = bag, slot
		return M.hooks["PickupContainerItem"](bag, slot)
	end)

	-- A bag click while the Send tab is open queues the item instead of using
	-- it -- the same shortcut Postal adds. Modifier clicks are left alone:
	-- they are the client's own split/link gestures.
	self:RawHook("UseContainerItem", function(bag, slot, onSelf)
		if AlreadyQueued(bag, slot) then return end
		if _G.SendMailFrame and _G.SendMailFrame:IsVisible() and not CursorHasItem()
			and not (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then
			if M:AttachBagItem(bag, slot) then return end
		end
		return M.hooks["UseContainerItem"](bag, slot, onSelf)
	end)

	if _G.ContainerFrameItemButton_OnClick then
		self:RawHook("ContainerFrameItemButton_OnClick", function(button, ignoreModifiers)
			local holder = this
			local okBag, bag = pcall(function() return holder:GetParent():GetID() end)
			local okSlot, slot = pcall(holder.GetID, holder)
			this = holder
			if okBag and okSlot and AlreadyQueued(bag, slot) then return end
			return M.hooks["ContainerFrameItemButton_OnClick"](button, ignoreModifiers)
		end)
	end

	-- The greying. The container frame calls this on every refresh, so
	-- forcing it here keeps a queued slot grey without a repaint of our own.
	if _G.SetItemButtonDesaturated then
		self:RawHook("SetItemButtonDesaturated", function(itemButton, desaturated)
			-- This helper serves every item button in the UI, and a bag
			-- coordinate pair is only meaningful for a container's own
			-- buttons -- without the name check a merchant or loot button
			-- whose ids happened to match a queued pair would grey out too.
			local okParent, parentName = pcall(function() return itemButton:GetParent():GetName() end)
			local isBag = okParent and parentName and string.find(parentName, "^ContainerFrame%d")
			local okBag, bag = pcall(function() return itemButton:GetParent():GetID() end)
			local okSlot, slot = pcall(itemButton.GetID, itemButton)
			if isBag and okBag and okSlot and AlreadyQueued(bag, slot) then
				return M.hooks["SetItemButtonDesaturated"](itemButton, true)
			end
			return M.hooks["SetItemButtonDesaturated"](itemButton, desaturated)
		end)
	end

	-- Single funnel for every send: the button's own handler has already
	-- attached money or C.O.D. by the time this runs (`StaticPopup.lua` for
	-- money, `MailFrame.lua` for C.O.D.), so the first mail carries them
	-- without anything extra here.
	self:RawHook("SendMailFrame_SendMail", function()
		if M:HasAttachments() then return M:SendQueued() end
		return M.hooks["SendMailFrame_SendMail"]()
	end)

	self:RegisterEvent("MAIL_SEND_SUCCESS", function() M.sendAcked = true end)

	self:SecureHook("SendMailFrame_Update", function() M:RefreshAttachments() end)
	self:RefreshAttachments()
end

-- One mail per queued item, so everything the native boxes hold is read ONCE,
-- here: the first send clears them (`SendMailFrame_Reset`), and every mail
-- after that would otherwise go out blank.
function M:SendQueued()
	if self.running then return end

	self.sendQueue = Attachments()
	self.sendTotal = getn(self.sendQueue)
	self.sendIndex = 0
	self.sendTo = _G.SendMailNameEditBox and _G.SendMailNameEditBox:GetText() or ""
	self.sendSubject = _G.SendMailSubjectEditBox and _G.SendMailSubjectEditBox:GetText() or ""
	self.sendBody = _G.ElvUI_MailBody and _G.ElvUI_MailBody:GetText() or ""

	if self.sendTo == "" then
		E:Print(L["No recipient."])
		return
	end

	local i
	for i = 1, SLOT_COUNT do
		if slots[i] then
			slots[i].elvBag, slots[i].elvSlot = nil, nil
		end
	end
	self:RefreshAttachments()

	self.subjectAutoFill = nil

	self.running = true
	self.mode = "send"
	self.sendAcked = false
	self.tick = function() M:SendStep() end
end

function M:SendStep()
	if not self.running then return end

	local item = table.remove(self.sendQueue, 1)
	if not item then return self:FinishSending() end

	self.sendIndex = self.sendIndex + 1

	-- Clear whatever is in the native slot first: a leftover attachment would
	-- ride along with the wrong mail.
	ClearCursor()
	ClickSendMailItemButton()
	ClearCursor()

	PickupContainerItem(item.bag, item.slot)
	ClickSendMailItemButton()

	local attached = GetSendMailItem()
	if not attached then
		ClearCursor()
		E:Print(L["Could not attach one item -- skipped it."])
		return
	end

	local subject = self.sendSubject
	if self.sendTotal > 1 then
		subject = string.format(L["%s (%d of %d)"], subject, self.sendIndex, self.sendTotal)
	end

	self.sendAcked = false
	SendMail(self.sendTo, subject, self.sendBody)
	self:WaitFor(function()
		return M.sendAcked
	end, function()
		E:Print(string.format(L["Sent %s."], attached))
	end, function()
		E:Print(L["One mail was not accepted -- stopped sending."])
		M:FinishSending()
	end)
end

function M:FinishSending()
	self.running = nil
	self.tick = nil
	self.mode = nil
	self.sendQueue = nil
	self:ClearWait()

	if self.sendTotal and self.sendTotal > 1 then
		E:Print(string.format(L["Sent %d mails."], self.sendIndex or 0))
	end
	self.sendTotal = nil
	self.sendIndex = nil

	pcall(SendMailFrame_Update)
end
