-- Bags module -- one merged ElvUI window replacing the native container
-- windows (ContainerFrame1-12) and, later, the bank.
--
-- CONSTRUCTION PRINCIPLE, measured on both clients: the native item and
-- bag-slot buttons are BORROWED (SetParent into our own grid), never
-- recreated. Two independent reasons:
--
--   * A freshly created bag-slot button cannot identify the equipped bag on
--     UA: GetInventoryItemLink returns nothing for bag slots there (only for
--     equipment slots), and several different bags share both slot count and
--     icon, so the texture alone doesn't identify one either. The native
--     CharacterBag0Slot-CharacterBag3Slot / MainMenuBarBackpackButton /
--     BankFrameBag1-6 buttons were created by FrameXML with the right name
--     and id, so they know their own contents -- reparenting touches neither
--     their id nor their scripts, and their tooltip keeps naming the bag.
--   * ContainerFrame_Update() looks its item buttons up by GLOBAL NAME
--     (getglobal(name.."Item"..i)), so it keeps filling them after a
--     reparent -- no separate refresh path has to be written or maintained.
--
-- Three consequences that are easy to get wrong:
--
--   * ContainerFrame_Update is called DIRECTLY from this module's own event
--     handler, never left to ContainerFrame_OnEvent -- that one refreshes a
--     frame only while it IsShown(), and the lending containers are parked
--     off-screen and faded out for good.
--   * Every native global that reaches ContainerFrame_GenerateFrame has to be
--     taken over (see NATIVE_TOGGLES): that function re-anchors a container's
--     buttons back into the native window's own layout, which would scatter
--     our grid.
--   * A borrowed button needs SetAlpha(1) + Show() after the reparent, and
--     its NormalTexture hidden as an OBJECT rather than blanked: it comes
--     from main-bar chrome this addon itself fades to alpha 0
--     (Modules/ActionBars/ActionBars.lua), and both the fade and the native
--     slot art travel with the button.
--
-- Scope of this file so far: the window shell and its movers, the takeover of
-- the native bag entry points, the merged item grid, the equipped-bag strip,
-- the keyring, the money display, the search filter, the bank, and selling
-- gray items at a merchant (see B:InitializeVendorGrays). The sort button and
-- the manual vendor-grays header button attach to the same frames afterwards.
--
-- The bank works the same way, with one structural difference: its generic
-- rows (BankFrameItem1-24) are borrowed from the native BankFrame rather than
-- from a lending ContainerFrame, and they keep themselves filled from their
-- own event registrations -- so the native BankFrame's own OnEvent is the one
-- thing that must be silenced, and CloseBankFrame() has to be sent on every
-- path that closes our window.

local E, L, V, P, G = unpack(ElvUI)
local B = E:NewModule("Bags", "AceEvent-3.0", "AceTimer-3.0")
local Util = ElvUI.Util

E.Bags = B

-- Settings: `V.bags` (Settings/Private.lua), `P.bags`
-- (Settings/Profile.lua).

-- Backpack + the four carried bag slots. The bank list is bag -1 (the bank's
-- own generic slots) plus the six purchasable bank bags -- NUM_BANKBAGSLOTS
-- is 6 here, so real ElvUI's own 5..11 list carries one container id that
-- never exists.
B.BagIDs = { 0, 1, 2, 3, 4 }
B.BankIDs = { -1, 5, 6, 7, 8, 9, 10 }

local NATIVE_CONTAINER_COUNT = 12

local Skins

-- Painted from the Skins module's own design tokens, never from literals, so
-- this window carries exactly the tone every other skinned window in this
-- addon does. The fallbacks only matter if the Skins module is unavailable.
local function ApplyPanelBackdrop(frame)
	local bg = (Skins and Skins.PANEL_COLOR) or { 0.05, 0.05, 0.05, 0.95 }
	local border = (Skins and Skins.BORDER_COLOR) or { 0, 0, 0, 1 }

	pcall(frame.SetBackdrop, frame, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(frame.SetBackdropColor, frame, bg[1], bg[2], bg[3], bg[4] or 1)
	pcall(frame.SetBackdropBorderColor, frame, border[1], border[2], border[3], border[4] or 1)
end

-- Invisible, off-screen and mouse-dead, but NOT killed: the frame is still
-- the object ContainerFrame_Update is called with, and it still owns the
-- global button names that function looks its buttons up by.
local function NeuterNativeContainer(frame)
	if not frame then return end

	pcall(frame.EnableMouse, frame, false)
	pcall(frame.SetAlpha, frame, 0)
	pcall(frame.SetClampedToScreen, frame, false)
	pcall(frame.ClearAllPoints, frame)
	pcall(frame.SetPoint, frame, "TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
end

function B:NeuterNativeContainers()
	local i
	for i = 1, NATIVE_CONTAINER_COUNT do
		NeuterNativeContainer(_G["ContainerFrame"..i])
	end
end

-- A mover's drag handle is a CHILD of the holder it moves, and E:CreateMover's
-- own RaiseHandle only raises the handle's frame LEVEL -- which decides
-- nothing across two different stratas. The window itself sits at the bags'
-- configured strata (DIALOG by default), so a holder left at the default
-- strata would have its handle painted over by the very window it moves.
-- Same reason real ElvUI pushes its own bag/bank holders up (+400 levels).
function B:RaiseHolder(holder, strata)
	if not holder then return end

	pcall(holder.SetFrameStrata, holder, strata)

	local ok, level = pcall(holder.GetFrameLevel, holder)
	if ok and tonumber(level) then
		pcall(holder.SetFrameLevel, holder, level + 400)
	end
end

function B:GetContainerFrame(isBank)
	if isBank then return self.BankFrame end
	return self.BagFrame
end

-- Header controls walk LEFTWARDS from the label at the right edge (the money
-- text on the bag window, the "Bank" caption on the bank one), which is real
-- ElvUI's own arrangement. Each button is chained onto the previous one
-- through f.headerLeftmost instead of naming its neighbour, so a control that
-- does not exist yet slots in purely by being CREATED in the right place and
-- nothing else has to be re-anchored. Real ElvUI's full order, right to left:
--   bag window   money, sort, keyring, bags, vendor-grays, search
--   bank window  "Bank", sort, bags, purchase, search
-- Missing here: sort on both (belongs with sorting itself) and vendor-grays.
function B:AnchorHeaderButton(f, button)
	button:ClearAllPoints()
	button:SetPoint("RIGHT", f.headerLeftmost, "LEFT", -5, 0)
	f.headerLeftmost = button
end

-- The window itself: a Button (not a Frame) so it can take the same
-- shift-drag / ctrl-right-click-reset gestures real ElvUI puts on it.
function B:ConstructContainerFrame(name, isBank)
	local holder = isBank and self.BankHolder or self.BagHolder

	local f = CreateFrame("Button", name, UIParent)
	f.isBank = isBank
	f.BagIDs = isBank and self.BankIDs or self.BagIDs
	f.Bags = {}
	f.holder = holder

	f:SetFrameStrata(E.db.bags.strata or "DIALOG")
	f:SetWidth(isBank and E.db.bags.bankWidth or E.db.bags.bagWidth)
	f:SetHeight(200)
	ApplyPanelBackdrop(f)
	self:AnchorToHolder(f)

	f:SetMovable(true)
	f:RegisterForDrag("LeftButton", "RightButton")
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnDragStart", function()
		if IsShiftKeyDown() then this:StartMoving() end
	end)
	f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	f:SetScript("OnClick", function()
		-- Also the search box's main mouse-only way out: clicking the window
		-- body gives the keyboard back (see B:ConstructSearchBox).
		B:ClearSearchFocus()
		if IsControlKeyDown() then B:ResetPosition(this) end
	end)
	f:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT", 0, 4)
		GameTooltip:ClearLines()
		GameTooltip:AddDoubleLine(L["Hold Shift + Drag:"], L["Temporary Move"], 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Hold Control + Right Click:"], L["Reset Position"], 1, 1, 1)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- pcall'd creation: an unknown template is a hard error, and losing the
	-- close button must not take the whole window down with it -- Escape
	-- (UISpecialFrames) and the bag key still close it.
	local okClose, closeButton = pcall(CreateFrame, "Button", name.."CloseButton", f, "UIPanelCloseButton")
	if okClose and closeButton then
		f.closeButton = closeButton
		closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
		closeButton:SetScript("OnClick", function()
			if isBank then B:CloseBank() else B:CloseBags() end
		end)
		if Skins then Skins:StyleCloseButton(closeButton) end
	end

	-- The grid's own parent: the item rows live inside this, inset from the
	-- window edges, so the header row and the bottom padding stay clear.
	f.holderFrame = CreateFrame("Frame", nil, f)
	f.holderFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, isBank and -45 or -50)
	f.holderFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

	-- The bag-slot strip's container: hidden until the "Bags" toggle asks
	-- for it, and anchored above the window so it never overlaps the grid.
	f.ContainerHolder = CreateFrame("Frame", name.."ContainerHolder", f)
	f.ContainerHolder:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 1)
	f.ContainerHolder:SetHeight(10)
	f.ContainerHolder:SetWidth(10)
	-- Painted on a CHILD surface, not on the holder itself: on UA a frame's
	-- own backdrop is drawn OVER the buttons parented into it (measured -- the
	-- borrowed bag icons went from veiled to crisp the moment this backdrop's
	-- alpha was set to 0), while the same paint on a child frame sits behind
	-- them the way it does on the real client.
	if Skins and Skins.CreatePanel then
		Skins:CreatePanel(f.ContainerHolder)
	else
		ApplyPanelBackdrop(f.ContainerHolder)
	end
	f.ContainerHolder:Hide()

	if not isBank then
		-- Header strip, laid out right to left exactly as real ElvUI does:
		-- money at the right edge, the buttons walking leftwards from it.
		f.goldText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.goldText:SetPoint("BOTTOMRIGHT", f.holderFrame, "TOPRIGHT", -10, 4)
		f.goldText:SetJustifyH("RIGHT")
		f.headerLeftmost = f.goldText

		-- Hangs off the window's left edge, exactly where real ElvUI puts it.
		-- Background on a child surface for the same reason the bag-slot
		-- strip needs one: on UA a frame's own backdrop is drawn over the
		-- buttons parented into it.
		f.keyFrame = CreateFrame("Frame", name.."KeyFrame", f)
		f.keyFrame:SetPoint("TOPRIGHT", f, "TOPLEFT", -1, 0)
		f.keyFrame:SetWidth(10)
		f.keyFrame:SetHeight(10)
		if Skins and Skins.CreatePanel then
			Skins:CreatePanel(f.keyFrame)
		else
			ApplyPanelBackdrop(f.keyFrame)
		end
		f.keyFrame:Hide()

		f.keyButton = CreateFrame("Button", name.."KeyButton", f)
		f.keyButton:SetWidth(18)
		f.keyButton:SetHeight(18)
		f.keyButton:SetNormalTexture("Interface\\ICONS\\INV_Misc_Key_14")
		local keyIcon = f.keyButton:GetNormalTexture()
		if keyIcon then
			pcall(keyIcon.SetTexCoord, keyIcon, 0.08, 0.92, 0.08, 0.92)
		end
		Util.CreateButtonBorder(f.keyButton)
		self:AnchorHeaderButton(f, f.keyButton)
		f.keyButton:SetScript("OnClick", function() B:ToggleKeyRing() end)
		f.keyButton:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(BINDING_NAME_TOGGLEKEYRING or L["Toggle Keyring"])
			GameTooltip:Show()
		end)
		f.keyButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

		f.bagsButton = CreateFrame("Button", name.."BagsButton", f)
		f.bagsButton:SetWidth(18)
		f.bagsButton:SetHeight(18)
		self:AnchorHeaderButton(f, f.bagsButton)
		f.bagsButton:SetNormalTexture("Interface\\Buttons\\Button-Backpack-Up")
		local bagsIcon = f.bagsButton:GetNormalTexture()
		if bagsIcon then
			pcall(bagsIcon.SetTexCoord, bagsIcon, 0.08, 0.92, 0.08, 0.92)
		end
		Util.CreateButtonBorder(f.bagsButton)
		f.bagsButton:SetScript("OnClick", function()
			if f.ContainerHolder:IsShown() then
				f.ContainerHolder:Hide()
				-- Hiding the strip out from under a hovered button means its
				-- OnLeave never fires, which would leave the grid dimmed.
				B:ResetSlotAlphaForBags(f)
			else
				B:LayoutBagSlotStrip(f)
				f.ContainerHolder:Show()
			end
		end)
		f.bagsButton:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Toggle Bags"])
			GameTooltip:Show()
		end)
		f.bagsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

		self:ConstructSearchBox(f, name)
	else
		-- The bank window has no money display: the caption takes the same
		-- top-right spot and anchors the header chain, exactly as real ElvUI
		-- does it.
		f.bagText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.bagText:SetPoint("BOTTOMRIGHT", f.holderFrame, "TOPRIGHT", -10, 4)
		f.bagText:SetJustifyH("RIGHT")
		f.bagText:SetText(L["Bank"])
		f.headerLeftmost = f.bagText

		f.bagsButton = CreateFrame("Button", name.."BagsButton", f)
		f.bagsButton:SetWidth(18)
		f.bagsButton:SetHeight(18)
		self:AnchorHeaderButton(f, f.bagsButton)
		f.bagsButton:SetNormalTexture("Interface\\Buttons\\Button-Backpack-Up")
		local bankBagsIcon = f.bagsButton:GetNormalTexture()
		if bankBagsIcon then
			pcall(bankBagsIcon.SetTexCoord, bankBagsIcon, 0.08, 0.92, 0.08, 0.92)
		end
		Util.CreateButtonBorder(f.bagsButton)
		f.bagsButton:SetScript("OnClick", function()
			if f.ContainerHolder:IsShown() then
				f.ContainerHolder:Hide()
				B:ResetSlotAlphaForBags(f)
			else
				B:LayoutBagSlotStrip(f)
				f.ContainerHolder:Show()
			end
		end)
		f.bagsButton:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Toggle Bank Bags"])
			GameTooltip:Show()
		end)
		f.bagsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

		f.purchaseButton = CreateFrame("Button", name.."PurchaseButton", f)
		f.purchaseButton:SetWidth(18)
		f.purchaseButton:SetHeight(18)
		self:AnchorHeaderButton(f, f.purchaseButton)
		f.purchaseButton:SetNormalTexture("Interface\\ICONS\\INV_Misc_Coin_01")
		local purchaseIcon = f.purchaseButton:GetNormalTexture()
		if purchaseIcon then
			pcall(purchaseIcon.SetTexCoord, purchaseIcon, 0.08, 0.92, 0.08, 0.92)
		end
		Util.CreateButtonBorder(f.purchaseButton)
		f.purchaseButton:SetScript("OnClick", function()
			local _, full = GetNumBankSlots()
			if full then
				E:Print(L["Every bank bag slot has already been purchased."])
				return
			end

			-- The client's own confirmation dialog reads the price from
			-- BankFrame.nextSlotCost, which only the native UpdateBagSlotStatus
			-- writes -- and that runs off the BankFrame event handler this
			-- module silences, so it has to be driven here first.
			B:UpdateBankSlotStatus()
			pcall(StaticPopup_Show, "CONFIRM_BUY_BANK_SLOT")
		end)
		f.purchaseButton:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Purchase Bank Bag Slot"])
			local slots, full = GetNumBankSlots()
			if full then
				GameTooltip:AddLine(L["All slots purchased."], 1, 1, 1)
			else
				local cost = GetBankSlotCost and GetBankSlotCost(slots or 0)
				if cost then
					GameTooltip:AddLine(E:FormatMoney(cost, B.db.moneyFormat), 1, 1, 1)
				end
			end
			GameTooltip:Show()
		end)
		f.purchaseButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

		self:ConstructSearchBox(f, name)
	end

	-- Dropping the keyboard here as well as on every mouse-only exit path:
	-- the window can also be closed by Escape (UISpecialFrames) or a keybind,
	-- neither of which passes through the close button.
	--
	-- CloseBankFrame() belongs here rather than in one close path, for the
	-- same reason: however the window went away, the server has to be told the
	-- interaction ended, or it keeps believing the bank is open. Real ElvUI
	-- puts it on this same script.
	f:SetScript("OnHide", function()
		if not f.ready then return end

		B:ClearSearchFocus()
		if B.db and B.db.clearSearchOnClose then B:ResetSearch() end
		if isBank then pcall(CloseBankFrame) end
	end)

	-- Set only AFTER this Hide(): the bank window is constructed while the
	-- bank is being opened, so the constructor's own Hide would otherwise fire
	-- the handler above and close the interaction before the window has ever
	-- been seen.
	f:Hide()
	f.ready = true

	return f
end

-- The window grows AWAY from the nearest screen edge: anchored by whichever
-- corner of the holder faces the middle of the screen, so a holder parked at
-- the bottom right grows up and to the left instead of off-screen. Ported
-- from real ElvUI's own PostBagMove, but evaluated every time the window is
-- laid out or shown rather than only after a drag -- this project's movers
-- have no post-drag callback, and a position restored from a saved profile
-- has to land the same way a dragged one does.
function B:AnchorToHolder(f)
	if not f or not f.holder then return end

	local x, y = f.holder:GetCenter()
	if not x or not y then return end

	local screenWidth = UIParent:GetRight()
	local screenHeight = UIParent:GetTop()
	if not screenWidth or not screenHeight then return end

	local point
	if y > (screenHeight / 2) then
		point = (x > (screenWidth / 2)) and "TOPRIGHT" or "TOPLEFT"
	else
		point = (x > (screenWidth / 2)) and "BOTTOMRIGHT" or "BOTTOMLEFT"
	end

	f:ClearAllPoints()
	f:SetPoint(point, f.holder, point, 0, 0)
end

-- Ctrl + right click on the window: drop the temporary shift-drag position
-- and snap back onto the mover, which is where the saved position lives.
function B:ResetPosition(frame)
	if not frame or not frame.holder then return end

	pcall(frame.StopMovingOrSizing, frame)
	self:AnchorToHolder(frame)
end

-- Which native container lends its item buttons to which bag. A fixed map,
-- not ContainerFrame_GetOpenFrame()'s dynamic assignment: the borrowed
-- buttons stay in our grid permanently, so the bag they belong to must never
-- change under them. 12 native containers cover every id this client has --
-- 5 bags, the keyring, and 6 bank bags.
local BAG_CONTAINER_INDEX = {
	[0] = 1, [1] = 2, [2] = 3, [3] = 4, [4] = 5,
	[5] = 7, [6] = 8, [7] = 9, [8] = 10, [9] = 11, [10] = 12,
}

-- The keyring is a container like any other, with a fixed negative id on this
-- API vintage; it lends from the sixth native container. Written as a literal
-- rather than read from KEYRING_CONTAINER so the mapping above cannot depend
-- on a global's load order.
local KEYRING_BAG = -2
BAG_CONTAINER_INDEX[KEYRING_BAG] = 6

-- The bank's own generic slots are NOT a container in this sense: they have no
-- lending ContainerFrame, their buttons are the statically named
-- BankFrameItem1-24, and their count is fixed by the client rather than by an
-- equipped bag. Deliberately absent from BAG_CONTAINER_INDEX -- everything
-- that walks native containers has to skip this id.
local BANK_BAG = -1
local BANK_GENERIC_SLOTS = 24

local KEYRING_COLUMNS = 2

local SLOT_SPACING = 4
local WINDOW_PADDING = 8

function B:GetNativeContainer(bagID)
	local index = BAG_CONTAINER_INDEX[bagID]
	if not index then return nil end

	return _G["ContainerFrame"..index]
end

-- Hands one native container's item buttons to our own grid.
--
-- ContainerFrame_Update() needs exactly three things from the frame it is
-- given: its id (the bag), its `size` field (how many buttons to walk) and
-- its NAME (it looks every button up as name.."Item"..j). All three are set
-- here directly, which is why ContainerFrame_GenerateFrame -- the function
-- that would re-anchor every button back into the native window's own layout
-- on each open -- never has to run at all.
--
-- The per-bag parent carries the bag id because the native code reads it back
-- as itemButton:GetParent():GetID() for tooltips and the merchant sell
-- cursor.
function B:BorrowSlots(f, bagID, numSlots, host)
	-- Where this bag's buttons come from. The bank's generic rows are the
	-- statically named BankFrameItem1-24 and have no lending container at all:
	-- they keep themselves filled from their own events (their handler reads
	-- the button's GetInventorySlot(), with no parent or visibility check), so
	-- ContainerFrame_Update never has to be pointed at them.
	local prefix
	if bagID == BANK_BAG then
		prefix = "BankFrameItem"
	else
		local native = self:GetNativeContainer(bagID)
		if not native then return nil end

		pcall(native.SetID, native, bagID)
		native.size = numSlots
		prefix = native:GetName().."Item"
	end

	local parent = f.Bags[bagID]
	if not parent then
		parent = CreateFrame("Frame", f:GetName().."Bag"..bagID, host or f.holderFrame)
		parent:SetWidth(1)
		parent:SetHeight(1)
		parent:SetPoint("TOPLEFT", host or f.holderFrame, "TOPLEFT", 0, 0)
		parent.slots = {}
		f.Bags[bagID] = parent
	end
	parent:SetID(bagID)

	local j
	for j = 1, numSlots do
		local button = _G[prefix..j]
		if button then
			button:SetID(j)
			button:SetParent(parent)
			self:PinBorrowedButton(button, parent, f)
			-- Both are needed after the reparent: the native containers are
			-- faded and parked off-screen, and that state travels with the
			-- button until it is undone here.
			button:SetAlpha(1)
			button:Show()
			parent.slots[j] = button
		end
	end

	-- A smaller bag replaced a bigger one: the buttons past the new end stay
	-- ours, they just have nothing to show.
	local stale = numSlots + 1
	while parent.slots[stale] do
		parent.slots[stale]:Hide()
		parent.slots[stale] = nil
		stale = stale + 1
	end

	return parent
end

-- SetParent moves a frame in the hierarchy but does NOT make it re-inherit
-- the new parent's frame strata, and strata beats frame level: a button that
-- kept the main bar's strata renders underneath a window that sits at DIALOG,
-- however high its level. Both are pinned explicitly here, and our own border
-- backdrop is kept one level below the button it belongs to.
-- The reference is the WINDOW, never the button's immediate parent. The window
-- paints its panel backdrop on ITSELF, so a borrowed button has to sit above
-- the window's own level to be visible at all -- and the per-bag parent frames
-- are created at different moments (the bank's during its first open, after
-- the window's strata was already set), so their reported level does not
-- reliably place a child above it. Measured as a bank grid that stayed blank
-- for a second or two after the first open of a session while its buttons were
-- shown, positioned and carrying the right icon texture the whole time -- and
-- that filled in instantly when their frame level was raised by hand.
function B:PinBorrowedButton(button, parent, window)
	if not button or not parent then return end

	local reference = window or parent

	local okStrata, strata = pcall(reference.GetFrameStrata, reference)
	if okStrata and strata then pcall(button.SetFrameStrata, button, strata) end

	local okLevel, level = pcall(reference.GetFrameLevel, reference)
	if okLevel and tonumber(level) then
		pcall(button.SetFrameLevel, button, level + 4)
		if button.elvBackdrop then
			pcall(button.elvBackdrop.SetFrameLevel, button.elvBackdrop, level + 3)
		end
	end
end

-- Native slot styling itself moved to `Util.SkinItemButton` (`Core/
-- Util.lua`) once `Modules/Skins/Blizzard/Merchant.lua` needed the exact
-- same recipe for MerchantFrame's vendor slots -- same reasoning as every
-- other helper in this project promoted on a second real consumer, except
-- the shared home is `Util` rather than `Skins.lua`: see that function's
-- own header for why (load order between `Load_Bags.xml` and
-- `Load_Skins.xml`). Every call site below now reads `Util.SkinItemButton`
-- directly instead of `self:SkinSlot`.

-- Undoes the dimmed/disabled state a borrowed button can arrive in: the main
-- bar fades and disables its own bag buttons, and on UA that reaches the icon
-- REGION, which a button-level SetAlpha(1) does not undo.
--
-- Deliberately NOT part of Util.SkinItemButton's one-time styling: the chrome-hiding
-- sweep in Modules/ActionBars/ActionBars.lua keeps running for the first 30
-- seconds after login, so a button skinned before that finishes could be
-- dimmed again afterwards. Idempotent, and ContainerFrame_Update re-applies
-- the real per-item desaturation on top of it.
function B:UndimSlot(button)
	if not button then return end

	if button.Enable then pcall(button.Enable, button) end
	pcall(button.SetAlpha, button, 1)

	local icon = _G[button:GetName().."IconTexture"]
	if icon then
		pcall(icon.SetAlpha, icon, 1)
		pcall(icon.SetVertexColor, icon, 1, 1, 1)
		pcall(icon.SetDesaturated, icon, false)
	end
end

-- The equipped-bag row, in the order the native UI numbers them. These are
-- BORROWED, never rebuilt: a button created from BagSlotButtonTemplate cannot
-- work out which bag it holds on UA (see this file's header), while these
-- were built by FrameXML with the id and name that make their own icon,
-- tooltip and bag-swapping click work.
-- Each button is returned paired with the bag id it holds, because the two
-- rows number themselves differently: carried bags are the backpack (0)
-- followed by CharacterBag0-3 (1-4), while the bank's own BankFrameBag1-6 are
-- bags 5-10 -- the same ids their FrameXML declaration carries.
local function GetBagSlotButtons(isBank)
	local buttons, bagIDs = {}, {}

	if isBank then
		local i
		for i = 1, (NUM_BANKBAGSLOTS or 6) do
			local button = _G["BankFrameBag"..i]
			if button then
				table.insert(buttons, button)
				table.insert(bagIDs, (NUM_BAG_SLOTS or 4) + i)
			end
		end

		return buttons, bagIDs
	end

	local backpack = _G["MainMenuBarBackpackButton"]
	if backpack then
		table.insert(buttons, backpack)
		table.insert(bagIDs, 0)
	end

	local i
	for i = 0, (NUM_BAG_FRAMES or 4) - 1 do
		local button = _G["CharacterBag"..i.."Slot"]
		if button then
			table.insert(buttons, button)
			table.insert(bagIDs, i + 1)
		end
	end

	return buttons, bagIDs
end

-- The strip lives above the window and is toggled by the header's bags
-- button, the way real ElvUI's own ContainerHolder does.
function B:LayoutBagSlotStrip(f)
	local holder = f.ContainerHolder
	if not holder then return end

	local buttons = holder.buttons
	if not buttons then
		buttons, holder.bagIDs = GetBagSlotButtons(f.isBank)
		holder.buttons = buttons
	end

	local size = self:GetSlotSize(f.isBank)
	local count = table.getn(buttons)
	if count == 0 then
		holder:Hide()
		return
	end

	local i
	for i = 1, count do
		local button = buttons[i]
		button:SetParent(holder)
		B:PinBorrowedButton(button, holder, holder)
		-- Needed for the same reason the item buttons need it: these come
		-- from main-bar chrome that is faded out, and the fade travels with
		-- the button.
		button:SetAlpha(1)
		button:Show()
		Util.SkinItemButton(button)
		B:PinBorrowedButton(button, holder, holder)
		self:UndimSlot(button)
		button:SetWidth(size)
		button:SetHeight(size)
		button:ClearAllPoints()
		button:SetPoint("LEFT", holder, "LEFT",
			WINDOW_PADDING + ((i - 1) * (size + SLOT_SPACING)), 0)
		self:InstallBagHover(f, button, holder.bagIDs[i])
		if f.isBank then
			self:InstallBankSlotPurchase(button, holder.bagIDs[i])
		end

		-- Bank slots only: the native "this bag's own window is open"
		-- highlight has nothing to mean in a merged window, and the check
		-- that drives it (UpdateBagButtonHighlight) tests whether a lending
		-- ContainerFrame is visible -- ours all are, permanently, so it would
		-- simply stay lit on every purchased slot.
		local highlight = _G[button:GetName().."HighlightFrameTexture"]
		if highlight then
			pcall(highlight.Hide, highlight)
			highlight.Show = E.noop
		end
	end

	holder:SetWidth((count * (size + SLOT_SPACING)) - SLOT_SPACING + (WINDOW_PADDING * 2))
	holder:SetHeight(size + (SLOT_SPACING * 2))

	-- Bank only, and it has to be LAST: the client marks a not-yet-purchased
	-- bag slot by tinting its icon red (SetItemButtonTextureVertexColor from
	-- UpdateBagSlotStatus), and UndimSlot above resets exactly that vertex
	-- colour to white while taking the button over. Without this the whole row
	-- reads as bought until something else happens to re-run the status pass.
	if f.isBank then
		self:UpdateBankSlotStatus()
	end
end

-- The keyring: the same borrowed-button machinery as the grid, in its own
-- panel hanging off the window's left edge, which is where real ElvUI puts it
-- too. Filled top-down in a narrow grid rather than as another bag row --
-- keys are not inventory and do not belong in the merged count.
function B:LayoutKeyRing(f)
	local keyFrame = f.keyFrame
	if not keyFrame then return end

	local numKeys = 0
	if GetKeyRingSize then
		local ok, size = pcall(GetKeyRingSize)
		if ok then numKeys = tonumber(size) or 0 end
	end

	-- Keys hang off the bag window, so they follow the bag slot size.
	local size = self:GetSlotSize(false)
	local parent = self:BorrowSlots(f, KEYRING_BAG, numKeys, keyFrame)
	if not parent or numKeys == 0 then
		keyFrame:Hide()
		return
	end

	local column, row = 0, 0
	local i
	for i = 1, numKeys do
		local button = parent.slots[i]
		if button then
			Util.SkinItemButton(button)
			self:PinBorrowedButton(button, parent, keyFrame)
			self:UndimSlot(button)
			button:SetWidth(size)
			button:SetHeight(size)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", keyFrame, "TOPLEFT",
				WINDOW_PADDING + (column * (size + SLOT_SPACING)),
				-(WINDOW_PADDING + (row * (size + SLOT_SPACING))))

			column = column + 1
			if column >= KEYRING_COLUMNS then
				column = 0
				row = row + 1
			end
		end
	end

	local rows = row
	if column > 0 then rows = rows + 1 end
	if rows < 1 then rows = 1 end

	local columns = numKeys
	if columns > KEYRING_COLUMNS then columns = KEYRING_COLUMNS end

	keyFrame:SetWidth((columns * (size + SLOT_SPACING)) - SLOT_SPACING + (WINDOW_PADDING * 2))
	keyFrame:SetHeight((rows * (size + SLOT_SPACING)) - SLOT_SPACING + (WINDOW_PADDING * 2))

	self:UpdateBag(KEYRING_BAG)

	if self:IsSearching() then self:RefreshSearch() end
end

function B:ToggleKeyRing()
	local f = self.BagFrame
	if not f or not f.keyFrame then return end

	if f.keyFrame:IsShown() then
		f.keyFrame:Hide()
	else
		self:LayoutKeyRing(f)
		f.keyFrame:Show()
	end
end

-- Hovering a bag in the strip dims every slot that does NOT belong to it.
--
-- Ported from real ElvUI's own SetSlotAlphaForBag/ResetSlotAlphaForBags, and
-- deliberately alpha-based rather than a highlight texture: alpha demonstrably
-- reaches these borrowed native buttons on both clients, while highlight/
-- pushed textures are this project's standing suspect on UA.
function B:SetSlotAlphaForBag(f, bagID)
	local i
	for i = 1, table.getn(f.BagIDs) do
		local id = f.BagIDs[i]
		local parent = f.Bags[id]
		if parent and parent.slots then
			local alpha = 0.1
			if id == bagID then alpha = 1 end

			local j
			for j = 1, self:GetSlotCount(id) do
				if parent.slots[j] then
					pcall(parent.slots[j].SetAlpha, parent.slots[j], alpha)
				end
			end
		end
	end
end

function B:ResetSlotAlphaForBags(f)
	-- An active search owns the slot alpha: restoring everything to 1 here
	-- would wipe the filter the moment the cursor left a bag button.
	if self:IsSearching() then
		self:RefreshSearch()
		return
	end

	local i
	for i = 1, table.getn(f.BagIDs) do
		local id = f.BagIDs[i]
		local parent = f.Bags[id]
		if parent and parent.slots then
			local j
			for j = 1, self:GetSlotCount(id) do
				if parent.slots[j] then
					pcall(parent.slots[j].SetAlpha, parent.slots[j], 1)
				end
			end
		end
	end
end

-- The item name is dug out of the LINK: on this API vintage
-- GetContainerItemInfo returns texture, count, locked and quality but no
-- name, and the link is the only place the name is available without a
-- tooltip scan. Link shape:
-- |cff9d9d9d|Hitem:3299:0:0:0|h[Fractured Canine]|h|r
--
-- A plain lowercase substring match, deliberately: real ElvUI hands this to
-- LibItemSearch-1.2 (type/quality/slot operators and all), which this project
-- does not vendor -- that library and its CustomSearch-1.0 parser are
-- Lua 5.1-only (string.match/gmatch, select), so they cannot be used as
-- shipped on the 5.0 client, and its richest filters read item tooltips
-- through a scanner frame.
local function SlotMatchesSearch(bagID, slotID, needle)
	local link = GetContainerItemLink(bagID, slotID)
	if not link then return false end

	local _, _, itemName = string.find(link, "%[(.-)%]")
	if not itemName then return false end

	return string.find(string.lower(itemName), needle, 1, true) ~= nil
end

-- Alpha carries the state, desaturation only decorates it: alpha is measured
-- to reach these borrowed native buttons on both clients, while SetDesaturated
-- is not verified on UA. A miss stays readable and still takes clicks -- this
-- dims, it never hides.
local function SetSlotSearchState(button, matched)
	pcall(button.SetAlpha, button, matched and 1 or 0.3)

	local icon = _G[button:GetName().."IconTexture"]
	if icon then
		pcall(icon.SetDesaturated, icon, not matched)
	end
end

function B:IsSearching()
	return (self.searchString or "") ~= ""
end

-- Walks f.Bags rather than f.BagIDs so the keyring -- which is borrowed the
-- same way but is not part of the merged bag list -- is filtered too.
function B:ApplySearchToFrame(f, needle, empty)
	if not f then return end

	for bagID, parent in pairs(f.Bags) do
		if parent.slots then
			local j = 1
			while parent.slots[j] do
				SetSlotSearchState(parent.slots[j],
					empty or SlotMatchesSearch(bagID, j, needle))
				j = j + 1
			end
		end
	end
end

-- One search string across both windows, which is real ElvUI's behaviour too:
-- the bank is just more slots to filter, and typing in either box filters
-- everything that is open.
function B:SetSearch(query)
	local needle = string.lower(query or "")
	local empty = (string.gsub(needle, " ", "") == "")

	self:ApplySearchToFrame(self.BagFrame, needle, empty)
	self:ApplySearchToFrame(self.BankFrame, needle, empty)
end

function B:RefreshSearch()
	self:SetSearch(self.searchString or "")
end

function B:UpdateSearch(box)
	local text = box:GetText() or ""

	if box.placeholder then
		if text == "" then box.placeholder:Show() else box.placeholder:Hide() end
	end

	if text == (self.searchString or "") then return end

	self.searchString = text
	self:RefreshSearch()
end

local function ForEachSearchBox(module, func)
	local frames = { module.BagFrame, module.BankFrame }

	local i
	for i = 1, 2 do
		local f = frames[i]
		if f and f.editBox then func(f.editBox) end
	end
end

function B:ClearSearchFocus()
	ForEachSearchBox(self, function(box)
		pcall(box.ClearFocus, box)
		pcall(box.EnableKeyboard, box, false)
	end)
end

function B:ResetSearch()
	ForEachSearchBox(self, function(box) pcall(box.SetText, box, "") end)

	self:ClearSearchFocus()
	self.searchString = ""
	self:RefreshSearch()
end

-- Search field, built from a bare EditBox rather than a Blizzard template:
-- the templates carry chrome that would only have to be stripped again, and a
-- CreateFrame'd EditBox needs the same two explicit enables LibConfig-1.0
-- found necessary on this client -- without them typing adds no characters at
-- all and the last one cannot be deleted.
--
-- The KEYBOARD is enabled only while the box is actually being edited. A
-- visible, keyboard-enabled frame swallows every key on UA, movement keys
-- included, and this window stays open for minutes at a time. Ways back out,
-- all mouse-only or non-typing: clicking the window body, closing the window
-- (which also covers Escape and the bag keybind, via OnHide), Enter, Escape.
function B:ConstructSearchBox(f, name)
	local box = CreateFrame("EditBox", name.."EditBox", f)
	f.editBox = box

	box:SetHeight(18)
	box:SetPoint("BOTTOMLEFT", f.holderFrame, "TOPLEFT", 0, 4)
	box:SetPoint("RIGHT", f.headerLeftmost or f.goldText, "LEFT", -5, 0)

	pcall(box.SetAutoFocus, box, false)
	pcall(box.SetJustifyH, box, "LEFT")
	pcall(box.SetFontObject, box, GameFontHighlightSmall)
	pcall(box.SetTextColor, box, 1, 1, 1)
	pcall(box.SetMaxLetters, box, 30)
	pcall(box.EnableMouse, box, true)

	if Skins and Skins.StyleEditBox then
		Skins:StyleEditBox(box)
	end
	-- After the skin, which sets its own symmetric insets: the left one has
	-- to clear the magnifier icon.
	pcall(box.SetTextInsets, box, 20, 4, 0, 0)

	box.icon = box:CreateTexture(nil, "OVERLAY")
	box.icon:SetTexture("Interface\\AddOns\\ElvUI\\Media\\Textures\\UI-Searchbox-Icon")
	box.icon:SetWidth(14)
	box.icon:SetHeight(14)
	box.icon:SetPoint("LEFT", box, "LEFT", 3, 0)

	-- A separate placeholder string rather than real ElvUI's trick of leaving
	-- the word "Search" in the box and comparing against it: that one relies
	-- on HighlightText() to wipe itself on the first keypress, which is not
	-- verified on UA, and it makes an item that happens to be named like the
	-- placeholder unsearchable. Here an empty box simply means "not
	-- searching", which is also what B:IsSearching reads.
	-- Greyed by a per-FontString SetTextColor, not by inheriting a "disabled"
	-- font object: colour lives on the FontString on this client, and font
	-- objects have no SetTextColor at all.
	box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.placeholder:SetPoint("LEFT", box, "LEFT", 20, 0)
	box.placeholder:SetText(SEARCH or L["Search"])
	pcall(box.placeholder.SetTextColor, box.placeholder, 0.6, 0.6, 0.6)

	box:SetScript("OnMouseDown", function()
		pcall(box.EnableKeyboard, box, true)
		pcall(box.SetFocus, box)
	end)
	box:SetScript("OnEditFocusGained", function()
		pcall(box.EnableKeyboard, box, true)
	end)
	box:SetScript("OnEditFocusLost", function()
		pcall(box.EnableKeyboard, box, false)
	end)
	box:SetScript("OnEnterPressed", function() B:ClearSearchFocus() end)
	box:SetScript("OnEscapePressed", function() B:ResetSearch() end)
	box:SetScript("OnTextChanged", function() B:UpdateSearch(box) end)
	box:SetScript("OnChar", function() B:UpdateSearch(box) end)

	return box
end

-- Adds to a script instead of replacing it: these buttons are the client's
-- own, and their existing handlers are what show the bag tooltip and drive
-- the bag swap.
local function ChainScript(frame, scriptName, extra)
	local original = frame:GetScript(scriptName)

	frame:SetScript(scriptName, function(a1, a2, a3, a4)
		if original then original(a1, a2, a3, a4) end
		extra()
	end)
end

function B:InstallBagHover(f, button, bagID)
	if button.elvBagHover then return end
	button.elvBagHover = true

	ChainScript(button, "OnEnter", function() B:SetSlotAlphaForBag(f, bagID) end)
	ChainScript(button, "OnLeave", function() B:ResetSlotAlphaForBags(f) end)
end

-- Clicking a bank bag slot the player has not bought yet does nothing at all
-- on this client: the native handler is PutItemInBag followed by ToggleBag,
-- and buying a slot lives on a separate button entirely. The confirmation
-- dialog is offered from the slot itself here, which is where a player looks
-- for it -- the coin button in the header still works the same way.
--
-- Chained onto the button's own handler rather than replacing it, so the same
-- click keeps swapping a bag into an already-bought slot, and skipped while
-- the cursor is carrying something: that click was meant for the swap.
function B:InstallBankSlotPurchase(button, bagID)
	if button.elvBankPurchase then return end
	button.elvBankPurchase = true

	local slotIndex = bagID - (NUM_BAG_SLOTS or 4)

	ChainScript(button, "OnClick", function()
		if type(CursorHasItem) == "function" and CursorHasItem() then return end
		if slotIndex <= (GetNumBankSlots() or 0) then return end

		-- The dialog reads its price from BankFrame.nextSlotCost, which only
		-- the native status pass writes.
		B:UpdateBankSlotStatus()
		pcall(StaticPopup_Show, "CONFIRM_BUY_BANK_SLOT")
	end)
end

function B:UpdateGoldText()
	local f = self.BagFrame
	if not f or not f.goldText then return end

	f.goldText:SetText(E:FormatMoney(GetMoney() or 0, self.db.moneyFormat))
end

-- Single place the slot count is read, so a client-specific correction has
-- exactly one home if one turns out to be needed.
--
-- An earlier version of this function treated a zero as untrustworthy and
-- kept the last non-zero count until BAG_CLOSED named that bag. That was
-- WRONG on the real 1.12.1 client: the grid then only ever grew, because the
-- shrink signal it waited for did not arrive the way it assumed. Do not
-- re-introduce a sticky count without measuring the actual event/count
-- sequence first.
-- Single place the slot EDGE is read, for the same reason GetSlotCount is:
-- the bank has its own setting, and real ElvUI's defaults for the two happen
-- to be identical, which hides a mix-up until a profile sets them apart.
function B:GetSlotSize(isBank)
	if isBank then return self.db.bankSize or 34 end

	return self.db.bagSize or 34
end

function B:GetSlotCount(bagID)
	-- The bank's generic rows are a fixed set of client-owned buttons
	-- (BankFrameItem1-24), not slots that come and go with an equipped bag,
	-- and GetContainerNumSlots reports them as 0 whenever the player is not
	-- standing at the banker -- which would empty the window mid-layout.
	if bagID == BANK_BAG then
		return NUM_BANKGENERIC_SLOTS or BANK_GENERIC_SLOTS
	end

	return GetContainerNumSlots(bagID) or 0
end

function B:HideBorrowedSlots(f)
	local maxItems = MAX_CONTAINER_ITEMS or 36

	local i
	for i = 1, table.getn(f.BagIDs) do
		local native = self:GetNativeContainer(f.BagIDs[i])
		if native then
			local nativeName = native:GetName()
			local j
			for j = 1, maxItems do
				local button = _G[nativeName.."Item"..j]
				if button then pcall(button.Hide, button) end
			end
		end
	end
end

-- One continuous grid across every bag, in bag/slot order -- the merged
-- "OneBag" layout, not one block per bag.
function B:Layout(isBank)
	local f = self:GetContainerFrame(isBank)
	if not f then return end

	-- Slot size and window width are both per-window settings in real ElvUI,
	-- and its own defaults happen to be equal (34/34, 406/406) -- so reading
	-- the bag value for both windows looks correct until an imported profile
	-- sets them apart.
	local size = self:GetSlotSize(isBank)
	local width = (isBank and self.db.bankWidth or self.db.bagWidth) or 406
	local usable = width - (WINDOW_PADDING * 2)
	local columns = math.floor((usable + SLOT_SPACING) / (size + SLOT_SPACING))
	if columns < 1 then columns = 1 end

	-- Everything we lend from goes dark first, then only what this pass
	-- actually places is shown again. Without it a slot count that shrank --
	-- or was read while the client still reported the old one -- leaves
	-- orphaned buttons sitting in the grid, which reads as the window
	-- counting a bag that is no longer there.
	self:HideBorrowedSlots(f)

	local column, row = 0, 0
	local i
	for i = 1, table.getn(f.BagIDs) do
		local bagID = f.BagIDs[i]
		local numSlots = self:GetSlotCount(bagID)
		local parent = self:BorrowSlots(f, bagID, numSlots)

		if parent then
			local j
			for j = 1, numSlots do
				local button = parent.slots[j]
				if button then
					Util.SkinItemButton(button)
					-- Re-pinned AFTER skinning: Util.SkinItemButton is what
					-- creates the button's border frame, so this is the
					-- first moment its level can be put one step below the
					-- button's own.
					self:PinBorrowedButton(button, parent, f)
					self:UndimSlot(button)
					button:SetWidth(size)
					button:SetHeight(size)
					button:ClearAllPoints()
					button:SetPoint("TOPLEFT", f.holderFrame, "TOPLEFT",
						column * (size + SLOT_SPACING),
						-(row * (size + SLOT_SPACING)))

					column = column + 1
					if column >= columns then
						column = 0
						row = row + 1
					end
				end
			end
		end
	end

	-- A partly filled last row still occupies one.
	local rows = row
	if column > 0 then rows = rows + 1 end
	if rows < 1 then rows = 1 end

	local topOffset = isBank and 45 or 50
	f:SetWidth(width)
	f:SetHeight(topOffset + (rows * (size + SLOT_SPACING)) - SLOT_SPACING + WINDOW_PADDING)

	self:UpdateAllSlots(isBank)

	-- Only re-laid out while visible: taking the native buttons over while the
	-- strip is hidden would pull them out of wherever they currently sit for
	-- no visible gain.
	if f.ContainerHolder and f.ContainerHolder:IsShown() then
		self:LayoutBagSlotStrip(f)
	end

	if not isBank then
		self:UpdateGoldText()
		if f.keyFrame and f.keyFrame:IsShown() then
			self:LayoutKeyRing(f)
		end
	end

	-- Last, because everything above it -- UndimSlot in particular -- puts
	-- every slot back to full alpha.
	if self:IsSearching() then self:RefreshSearch() end
end

-- The whole point of borrowing: Blizzard's own updater fills icon, count,
-- lock state and cooldown for us. It is called directly rather than left to
-- ContainerFrame_OnEvent, which only runs while the native window IsShown().
-- The bank's generic rows, filled from the container API rather than left to
-- the native buttons' own event pass.
--
-- Measured on UA: GetContainerItemInfo(-1, slot) answers at ALL times -- far
-- from a banker and straight after login -- while those buttons only repaint
-- inside their own BANKFRAME_OPENED / PLAYERBANKSLOTS_CHANGED handlers, and on
-- the FIRST open of this window that pass has demonstrably not run by the time
-- they are borrowed: the first open showed an empty grid, every later one was
-- correct, with both APIs already returning the item the whole time.
--
-- Deliberately written through the client's own SetItemButton* helpers and
-- limited to icon and count: those are the fields the native pass writes too,
-- so the two cannot disagree once it does run. Lock state stays entirely the
-- client's (ITEM_LOCK_CHANGED), and desaturation stays the search filter's.
function B:UpdateBankGenericSlots()
	local f = self.BankFrame
	if not f then return end

	local parent = f.Bags[BANK_BAG]
	if not parent or not parent.slots then return end

	local hasTexture = (type(SetItemButtonTexture) == "function")
	local hasCount = (type(SetItemButtonCount) == "function")

	local j = 1
	while parent.slots[j] do
		local texture, count = GetContainerItemInfo(BANK_BAG, j)

		if hasTexture then pcall(SetItemButtonTexture, parent.slots[j], texture) end
		if hasCount then pcall(SetItemButtonCount, parent.slots[j], count) end

		j = j + 1
	end
end

function B:UpdateBag(bagID)
	if bagID == BANK_BAG then
		self:UpdateBankGenericSlots()
		return
	end

	local native = self:GetNativeContainer(bagID)
	if not native or not native.size then return end

	pcall(ContainerFrame_Update, native)
end

function B:UpdateAllSlots(isBank)
	local f = self:GetContainerFrame(isBank)
	if not f then return end

	local i
	for i = 1, table.getn(f.BagIDs) do
		self:UpdateBag(f.BagIDs[i])
	end
end

-- Any bag event.
--
-- Icons/counts are refreshed immediately, but the LAYOUT decision is always
-- deferred, because slot counts lag the events that announce them. Measured
-- on the real 1.12.1 client, moving a bag from slot 3 to slot 4 logs:
--
--     BAG_CLOSED:3   bag3 still reports 6
--     BAG_UPDATE:4   bag4 still reports 0
--     BAG_UPDATE:1   only now do the counts match reality
--
-- So GetContainerNumSlots is one event behind: acting on what an event can
-- see at the instant it fires produces a grid that grows a bag it no longer
-- has, or drops one it just received. A settled pass shortly afterwards sees
-- the real numbers. UA does not show the lag, and is unaffected by the wait.
function B:BagsUpdated()
	local touched = false

	if self.BagFrame and self.BagFrame:IsShown() then
		self:UpdateAllSlots(false)
		touched = true
	end

	if self.BankFrame and self.BankFrame:IsShown() then
		self:UpdateAllSlots(true)
		touched = true
	end

	if not touched then return end

	-- ContainerFrame_Update repaints the icons, which loses the search dim on
	-- every slot it touched.
	if self:IsSearching() then self:RefreshSearch() end
	self:ScheduleSettledLayout()
end

function B:ScheduleSettledLayout()
	if self.pendingLayout then return end
	self.pendingLayout = true

	E:Delay(0.2, function()
		B.pendingLayout = nil
		B:RelayoutIfChanged()
	end)
end

-- The bank's own generic rows are skipped by construction: they have no
-- lending container, and their count never changes.
function B:FrameNeedsRelayout(f)
	if not f or not f:IsShown() then return false end

	local i
	for i = 1, table.getn(f.BagIDs) do
		local bagID = f.BagIDs[i]
		local native = self:GetNativeContainer(bagID)
		if native and native.size ~= self:GetSlotCount(bagID) then
			return true
		end
	end

	return false
end

function B:RelayoutIfChanged()
	local changed = false

	if self:FrameNeedsRelayout(self.BagFrame) then
		self:Layout(false)
		changed = true
	end

	if self:FrameNeedsRelayout(self.BankFrame) then
		self:Layout(true)
		changed = true
	end

	if not changed then return end

	-- One more settled pass after a real change: a second swap made while the
	-- first was still settling would otherwise leave the last one unseen,
	-- since nothing further is guaranteed to fire.
	self:ScheduleSettledLayout()
end

function B:OpenBags()
	if not self.BagFrame then return end

	self.BagFrame:Show()
	self:AnchorToHolder(self.BagFrame)
	self:Layout()
	PlaySound("igBackPackOpen")
end

function B:CloseBags()
	if not self.BagFrame then return end

	self.BagFrame:Hide()
	if self.BankFrame then self.BankFrame:Hide() end
	PlaySound("igBackPackClose")
end

function B:ToggleBags(id)
	if not self.BagFrame then return end

	-- Guard ported from real ElvUI, whose own comment names exactly this
	-- case: putting a bag into an EMPTY slot ends in BagSlotButton_OnClick
	-- calling ToggleBag(id) (PutItemInBag swapped nothing, so the native
	-- handler falls through to the toggle), and the just-inserted container
	-- still reports 0 slots at that instant. Without this, swapping a bag
	-- between slots toggles the whole window shut -- observed on the real
	-- 1.12.1 client only; UA never makes that call.
	if id and (GetContainerNumSlots(id) or 0) == 0 then return end

	-- A bank bag slot button falls through to ToggleBag(id) the same way a
	-- carried one does (BankFrameItemButtonBag_OnClick, after PutItemInBag
	-- swapped nothing), and in a merged window toggling "that one bag" can
	-- only mean toggling everything -- which is not what clicking a bank slot
	-- asks for. Inert for bank ids, for the same reason CloseBag is inert.
	if id and id > (NUM_BAG_SLOTS or 4) then return end

	if self.BagFrame:IsShown() then
		self:CloseBags()
	else
		self:OpenBags()
	end
end

-- The bank window is built on the first BANKFRAME_OPENED rather than at login:
-- until the player has stood at a banker once, nothing in it can be filled
-- anyway, and the native buttons it borrows are better left where they are.
function B:OpenBank()
	if not self.BankFrame then
		self.BankFrame = self:ConstructContainerFrame("ElvUI_BankContainerFrame", true)
		table.insert(UISpecialFrames, "ElvUI_BankContainerFrame")
	end

	self.BankFrame:Show()
	self:AnchorToHolder(self.BankFrame)
	self:UpdateBankSlotStatus()
	self:Layout(true)

	-- Real ElvUI opens the bags alongside the bank, and moving items between
	-- the two is the whole reason for standing at a banker.
	self:OpenBags()
end

-- Hiding is all this does: the frame's own OnHide is what tells the server the
-- interaction ended, so every path that closes the window -- this one, the
-- close button, CloseBags, Escape -- ends it exactly once.
function B:CloseBank()
	if self.BankFrame then self.BankFrame:Hide() end
end

-- The native UpdateBagSlotStatus is still needed for three things: it tints
-- the not-yet-purchased bank bag slots red, sets their tooltip text, and
-- writes BankFrame.nextSlotCost, which the client's own purchase dialog reads
-- for its money frame. Its usual caller is the BankFrame event handler, which
-- this module silences, so it is driven from here instead.
function B:UpdateBankSlotStatus()
	if type(UpdateBagSlotStatus) ~= "function" then return end

	pcall(UpdateBagSlotStatus)
end

function B:BankBagSlotsChanged()
	self:UpdateBankSlotStatus()

	if self.BankFrame and self.BankFrame:IsShown() then
		self:Layout(true)
	end
end

-- The native bank window must not run its own event handler. On
-- BANKFRAME_OPENED that handler calls ShowUIPanel(BankFrame) and then, if the
-- frame did not actually become visible, CloseBankFrame() -- so leaving it
-- alive while keeping the window hidden would end the bank interaction the
-- instant it started.
--
-- Only the window frame is silenced. Its item buttons carry their own event
-- registrations (BANKFRAME_OPENED, PLAYERBANKSLOTS_CHANGED, ITEM_LOCK_CHANGED),
-- and those are what keep BankFrameItem1-24 filled after they are borrowed
-- into our grid -- there is no ContainerFrame_Update equivalent for them.
function B:NeuterNativeBankFrame()
	local frame = _G["BankFrame"]
	if not frame then return end

	-- UnregisterAllEvents does not work on UA; clearing the script is the
	-- mechanism that works on both clients, and both are cheap.
	pcall(frame.UnregisterAllEvents, frame)
	pcall(frame.SetScript, frame, "OnEvent", nil)
	pcall(frame.Hide, frame)
	frame.Show = E.noop
end

-- Every native entry point into the bag UI, routed to our own window.
-- Overwritten rather than hooked: these are plain FrameXML globals, and a
-- hook would still leave Blizzard's own body running and re-showing the
-- native windows underneath.
-- ToggleBag, ToggleBackpack, OpenBag and ToggleKeyRing all end in
-- ContainerFrame_GenerateFrame(ContainerFrame_GetOpenFrame(), ...), which
-- would hand one of our lending containers to a different bag and re-anchor
-- its buttons back into the native window's layout -- i.e. scatter the grid.
-- Every one of them has to be taken over, not just the ones a keybind hits.
local NATIVE_TOGGLES = {
	"ToggleBag",
	"ToggleBackpack",
	"OpenBag",
	"CloseBag",
	"OpenBackpack",
	"CloseBackpack",
	"OpenAllBags",
	"CloseAllBags",
	"ToggleKeyRing",
}

function B:TakeOverNativeToggles()
	local handlers = {
		ToggleBag = function(id) B:ToggleBags(id) end,
		ToggleBackpack = function() B:ToggleBags() end,
		OpenBag = function() B:OpenBags() end,
		-- Inert, NOT a close: the client calls CloseBag(id) for a single
		-- container -- swapping a bag between slots does exactly that on the
		-- real 1.12.1 client -- and in a merged window closing one bag can
		-- only mean closing everything, which is not what the caller asked
		-- for. The native body still must not run: it would hand a lending
		-- container back to the native layout.
		CloseBag = function() end,
		OpenBackpack = function() B:OpenBags() end,
		CloseBackpack = function() B:CloseBags() end,
		OpenAllBags = function() B:ToggleBags() end,
		CloseAllBags = function() B:CloseBags() end,
		ToggleKeyRing = function() B:ToggleKeyRing() end,
	}

	local missing = {}
	local i
	for i = 1, table.getn(NATIVE_TOGGLES) do
		local name = NATIVE_TOGGLES[i]
		if type(_G[name]) == "function" then
			_G[name] = handlers[name]
		else
			table.insert(missing, name)
		end
	end

	-- Silence rather than a hard failure: a missing global means one entry
	-- point still opens a native window, which is worth telling the player
	-- rather than leaving as an unexplained "sometimes the old bag opens".
	-- The message names the effect, not the missing function names.
	if table.getn(missing) > 0 then
		E:Print(L["Some bag shortcuts may still open the default bag window."])
	end
end

-- Vendor grays: at a merchant, every poor-quality item in the carried bags is
-- sold one at a time (real ElvUI's P.bags.vendorGrays). Independent of the bag
-- window -- real ElvUI sells grays with its Bags module disabled too.
--
-- THROTTLED on two conditions, and both must hold before the next
-- UseContainerItem: the configured interval has passed since the previous
-- sale, AND that sale has been confirmed -- its slot no longer holds the item.
-- The server answers every sale asynchronously, so a fixed interval alone
-- keeps firing requests while earlier ones are still unanswered. A sale that
-- is never confirmed (the merchant refused the item) is given up after
-- SELL_CONFIRM_TIMEOUT seconds and not counted.
--
-- "Gray" is read from the link colour, the same test pfUI's autovendor uses:
-- GetItemInfo needs the item cache, and GetContainerItemInfo's quality return
-- is not measured on either client here. An item is only queued with a known
-- sell price above zero (LibItemPrice-1.1), as in real ElvUI, which keeps
-- items without a vendor value out of the queue.
--
-- pfUI and UnrealUI clear the cursor before each sale; this waits instead
-- while the cursor carries an item, so an item the player is moving is never
-- taken off the cursor.
local GRAY_LINK_COLOR = "ff9d9d9d"
local MIN_SELL_INTERVAL = 0.1
local SELL_CONFIRM_TIMEOUT = 3

local function GetSellPrice(link)
	local LIP = LibStub("ItemPrice-1.1", true)
	if not LIP then return nil end

	local _, _, idText = string.find(link, "item:(%d+)")
	local id = tonumber(idText)
	if not id then return nil end

	return LIP:GetPriceById(id)
end

function B:CollectGrays()
	local list = {}

	local bag
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local slot
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local link = GetContainerItemLink(bag, slot)
			if link and string.find(string.lower(link), GRAY_LINK_COLOR, 1, true) then
				local price = GetSellPrice(link)
				if price and price > 0 then
					table.insert(list, { bag = bag, slot = slot, link = link, price = price })
				end
			end
		end
	end

	return list
end

function B:GetSellInterval()
	local interval = tonumber(E.db.bags.vendorGrays.interval) or 0.2
	if interval < MIN_SELL_INTERVAL then interval = MIN_SELL_INTERVAL end

	return interval
end

-- The progress window and the frame that drives the queue are separate: the
-- driver's OnUpdate has to run whether or not the progress bar is enabled, and
-- a hidden frame gets no OnUpdate at all.
function B:CreateSellFrame()
	local sell = CreateFrame("Frame", "ElvUIVendorGraysFrame", UIParent)
	sell:SetWidth(200)
	sell:SetHeight(40)
	sell:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	sell:SetFrameStrata("DIALOG")
	E:SetTemplate(sell, "Transparent")
	sell:Hide()

	sell.title = sell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sell.title:SetPoint("TOP", sell, "TOP", 0, -4)
	sell.title:SetText(L["Vendoring Grays"])

	sell.statusbar = Util.CreateStatusBar(sell, {
		name = "ElvUIVendorGraysFrameStatusbar",
		width = 180,
		height = 16,
		color = { 1, 0, 0, 1 },
		texture = E.media and E.media.normTex,
	})
	sell.statusbar:SetPoint("BOTTOM", sell, "BOTTOM", 0, 5)
	-- Above the window's own level: on UA a frame's own backdrop is drawn over
	-- children that do not sit above it (see B:PinBorrowedButton).
	local okLevel, level = pcall(sell.GetFrameLevel, sell)
	if okLevel and tonumber(level) then
		pcall(sell.statusbar.SetFrameLevel, sell.statusbar, level + 2)
	end

	sell.statusbar.ValueText = sell.statusbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sell.statusbar.ValueText:SetPoint("CENTER", sell.statusbar, "CENTER", 0, 0)

	sell.driver = CreateFrame("Frame", nil, UIParent)
	sell.driver:Hide()
	sell.driver:SetScript("OnUpdate", function() B:VendorGraysTick() end)

	self.SellFrame = sell
end

-- Live config: the progress window follows the toggle even mid-run. The
-- interval needs no push, it is read on every sale.
function B:UpdateSellFrameSettings()
	local sell = self.SellFrame
	if not sell then return end

	if sell.active and E.db.bags.vendorGrays.progressBar then
		sell:Show()
	else
		sell:Hide()
	end
end

function B:UpdateSellProgress()
	local sell = self.SellFrame
	if not sell or not sell.active then return end

	local remaining = sell.total - sell.processed
	sell.statusbar:SetValue(sell.processed)
	sell.statusbar.ValueText:SetText(string.format("%d / %d ( %.1fs )",
		sell.processed, sell.total, remaining * self:GetSellInterval()))
end

function B:VendorGrays()
	local sell = self.SellFrame
	if not sell or sell.active or not self.merchantOpen then return end

	local list = self:CollectGrays()
	local total = table.getn(list)
	if total == 0 then return end

	sell.itemList = list
	sell.index = 1
	sell.total = total
	sell.processed = 0
	sell.goldGained = 0
	sell.pending = nil
	sell.nextTick = 0
	sell.active = true

	sell.statusbar:SetMinMaxValues(0, total)
	self:UpdateSellProgress()
	self:UpdateSellFrameSettings()
	sell.driver:Show()
end

function B:FinishVendorGrays()
	local sell = self.SellFrame
	if not sell or not sell.active then return end

	sell.active = nil
	sell.driver:Hide()
	sell:Hide()
	sell.itemList = nil
	sell.pending = nil

	if sell.goldGained > 0 then
		E:Print(string.format(L["Vendored gray items for: %s"],
			E:FormatMoney(sell.goldGained, E.db.bags.moneyFormat)))
	end
end

local function SkipQueuedItem(module, sell)
	sell.index = sell.index + 1
	sell.processed = sell.processed + 1
	module:UpdateSellProgress()
end

function B:VendorGraysTick()
	local sell = self.SellFrame
	if not sell or not sell.active then return end

	local now = GetTime()
	if now < sell.nextTick then return end

	-- MERCHANT_CLOSED ends the run too; this covers a close that raced the
	-- driver's last frame.
	if not self.merchantOpen then
		self:FinishVendorGrays()
		return
	end

	local pending = sell.pending
	if pending then
		if GetContainerItemLink(pending.bag, pending.slot) == pending.link then
			if now - pending.sentAt < SELL_CONFIRM_TIMEOUT then return end
		else
			sell.goldGained = sell.goldGained + pending.value
			if E.db.bags.vendorGrays.details then
				E:Print(string.format("%s|cFF00DDDDx%d|r %s", pending.link, pending.count,
					E:FormatMoney(pending.value, E.db.bags.moneyFormat)))
			end
		end

		sell.pending = nil
		sell.processed = sell.processed + 1
		self:UpdateSellProgress()
	end

	local item = sell.itemList[sell.index]
	if not item then
		self:FinishVendorGrays()
		return
	end

	if type(CursorHasItem) == "function" and CursorHasItem() then return end

	-- The queue was built when the merchant opened; the player may have moved,
	-- sold or destroyed the item since.
	if GetContainerItemLink(item.bag, item.slot) ~= item.link then
		SkipQueuedItem(self, sell)
		return
	end

	local _, count, locked = GetContainerItemInfo(item.bag, item.slot)
	if locked then
		item.lockedSince = item.lockedSince or now
		if now - item.lockedSince >= SELL_CONFIRM_TIMEOUT then
			SkipQueuedItem(self, sell)
		end
		return
	end

	count = tonumber(count) or 1
	sell.index = sell.index + 1
	sell.pending = {
		bag = item.bag,
		slot = item.slot,
		link = item.link,
		count = count,
		value = item.price * count,
		sentAt = now,
	}
	sell.nextTick = now + self:GetSellInterval()

	pcall(UseContainerItem, item.bag, item.slot)
end

-- The merchant state is tracked from the events rather than read from
-- MerchantFrame:IsShown(), so a skin or another addon hiding that window does
-- not stop a run. AceEvent passes no event arguments on UA; none are needed.
function B:InitializeVendorGrays()
	self:CreateSellFrame()

	self:RegisterEvent("MERCHANT_SHOW", function()
		B.merchantOpen = true
		if E.db.bags.vendorGrays.enable then B:VendorGrays() end
	end)
	self:RegisterEvent("MERCHANT_CLOSED", function()
		B.merchantOpen = nil
		B:FinishVendorGrays()
	end)
end

function B:Initialize()
	-- Before the enable guard below, and independent of it: vendoring grays
	-- does not need the bag window. pcall'd for the same reason that guard
	-- exists.
	pcall(self.InitializeVendorGrays, self)

	-- Guarded rather than a bare E.private.bags.enable: AddOn:OnEnable runs
	-- every module's Initialize in one unprotected loop, so an error raised
	-- here would also stop every module registered after this one.
	if not (E.private.bags and E.private.bags.enable) then return end

	-- Same reason as the guard above: a module lookup that raises would take
	-- the rest of the init loop down with it, and the close button's skin is
	-- not worth that.
	local okSkins, skinsModule = pcall(E.GetModule, E, "Skins")
	Skins = okSkins and skinsModule or nil

	self.db = E.db.bags
	self.searchString = ""

	-- Both holders are plain, always-shown anchor frames: the window itself
	-- hides and shows, and a mover handle is a CHILD of the frame it moves,
	-- so hanging the mover on the window would take the handle down with it.
	-- Default anchors match real ElvUI's own (bag bottom-right of the right
	-- chat panel, bank bottom-left of the left chat panel).
	local strata = E.db.bags.strata or "DIALOG"

	self.BagHolder = CreateFrame("Frame", "ElvUIBagHolder", UIParent)
	self.BagHolder:SetWidth(200)
	self.BagHolder:SetHeight(22)
	self.BagHolder:SetPoint("BOTTOMRIGHT", RightChatPanel or UIParent, "BOTTOMRIGHT", 0, 22)
	self:RaiseHolder(self.BagHolder, strata)

	self.BankHolder = CreateFrame("Frame", "ElvUIBankHolder", UIParent)
	self.BankHolder:SetWidth(200)
	self.BankHolder:SetHeight(22)
	self.BankHolder:SetPoint("BOTTOMLEFT", LeftChatPanel or UIParent, "BOTTOMLEFT", 0, 22)
	self:RaiseHolder(self.BankHolder, strata)

	-- Mover NAMES are real ElvUI's own, so a saved position from a real
	-- profile lands on the right frame.
	E:CreateMover(self.BagHolder, "ElvUIBagMover", L["Bag Mover"])
	E:CreateMover(self.BankHolder, "ElvUIBankMover", L["Bank Mover"])

	self.BagFrame = self:ConstructContainerFrame("ElvUI_ContainerFrame")

	table.insert(UISpecialFrames, "ElvUI_ContainerFrame")

	self:NeuterNativeContainers()
	-- Done at login rather than on the first bank open: the native handler
	-- would otherwise get BANKFRAME_OPENED before this module does (it
	-- registered at load) and flash its own window once.
	self:NeuterNativeBankFrame()
	self:TakeOverNativeToggles()

	self:Layout()

	-- BAG_CLOSED is the only event that authoritatively says a container is
	-- gone; see B:GetSlotCount. The bag id arrives in the `arg1` GLOBAL, not
	-- as a handler argument -- AceEvent does not pass event arguments through
	-- on UA.
	self:RegisterEvent("BAG_CLOSED", function() B:BagsUpdated() end)

	local function onBagEvent() B:BagsUpdated() end
	self:RegisterEvent("BAG_UPDATE", onBagEvent)
	self:RegisterEvent("BAG_UPDATE_COOLDOWN", onBagEvent)
	self:RegisterEvent("ITEM_LOCK_CHANGED", onBagEvent)
	self:RegisterEvent("ITEM_UNLOCKED", onBagEvent)

	-- The bank's generic rows refill themselves from their own buttons'
	-- events; this one is still needed so an active search filter is
	-- re-applied over whatever they just repainted.
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", onBagEvent)

	self:RegisterEvent("BANKFRAME_OPENED", function() B:OpenBank() end)
	self:RegisterEvent("BANKFRAME_CLOSED", function() B:CloseBank() end)
	self:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", function() B:BankBagSlotsChanged() end)

	local function onMoneyEvent() B:UpdateGoldText() end
	self:RegisterEvent("PLAYER_MONEY", onMoneyEvent)
	self:RegisterEvent("PLAYER_TRADE_MONEY", onMoneyEvent)
	self:RegisterEvent("TRADE_MONEY_CHANGED", onMoneyEvent)

	-- Bag sizes aren't reliably readable the instant this runs at login, and
	-- a wrong slot count here would leave the grid short until the first bag
	-- event; the delayed pass is what the real module does for the same
	-- reason.
	E:Delay(2, function() B:Layout() end)

	-- Native containers are created at load, but their position and alpha
	-- are re-asserted by Blizzard's own code in the first seconds after
	-- login; a bounded resweep is this project's standard answer.
	Util.ScheduleLimitedSweep(function() B:NeuterNativeContainers() end, 3, 10)
end

E:RegisterInitialModule(B:GetName(), function() B:Initialize() end)
