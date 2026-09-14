-- Solo loot replacement window, a file of the Misc module -- ported from
-- real ElvUI's own Modules/Misc/Loot.lua (source/ElvUI-vanilla/), itself
-- already Lua-5.0/1.12.1-clean: bare `arg1`/`arg2` globals instead of event
-- payload args, `table.getn` instead of `#`, no `...`/`%` anywhere.
--
-- Attaches to Misc rather than being its own module, matching real ElvUI:
-- Misc.lua owns the module and calls M:LoadLoot() from its Initialize.
--
-- Frame CONSTRUCTION translated to this project's available primitives --
-- no E:Point/E:Size/E:FontTemplate/E.UIParent/E.TexCoords
-- (a whole Skins-module/profile-font infrastructure this project doesn't
-- have, same gap already noted in Modules/DataBars/XPBar.lua): plain
-- SetPoint/SetWidth/SetHeight, a pcall-wrapped WHITE8x8 backdrop (same
-- recipe as DataBars.lua's own M:CreateBar), stock virtual font templates
-- (GameFontNormal/NumberFontNormal) instead of a profile-driven font, and
-- a hardcoded 0.08/0.92 icon TexCoord inset (real ElvUI's own E.TexCoords
-- default, confirmed elsewhere in this project e.g. ActionBars.lua).
-- EVERYTHING ELSE -- field names/defaults, the event list, the native-
-- suppression target, the master-loot dropdown override -- comes from
-- real ElvUI instead.
--
-- `V.general.loot`/`V.general.lootUnderMouse` match real ElvUI's own
-- Settings/Private.lua field names and default values exactly.
--
-- Dropped from the vanilla source as genuinely dead: the OnClick handler
-- there also wrote `LootFrame.selectedQuality`/`selectedItemName`/
-- `selectedSlot`/`selectedLootButton` (native LootFrame's own fields) --
-- unread by anything, because this same file overrides both of their only
-- native consumers (`GroupLootDropDown_GiveLoot` below, and the dropdown-
-- opening `OPEN_MASTER_LOOT_LIST` handler) to use its own `sq`/`sn`/`ss`
-- locals instead.

local E, L, V, P, G = unpack(ElvUI)
local M = E:GetModule("Misc")
local Compat = ElvUI.Compat
local isUA = Compat and Compat.isUA

-- Settings: `V.general.loot` / `V.general.lootUnderMouse`
-- (Settings/Private.lua).

local lootFrame, lootFrameHolder
local iconSize = 30

-- The highest strata below TOOLTIP, set explicitly on the holder, the window
-- and every slot rather than left to inheritance, so the loot window stays
-- above the bag and bank windows (DIALOG) a disenchant is started from.
-- TOOLTIP itself would put the window level with GameTooltip, and the item
-- tooltip over a slot could then draw beneath it.
local LOOT_STRATA = "FULLSCREEN_DIALOG"

-- Selected slot/quality/name for the master-loot give-loot popup below --
-- fed by each slot's OnClick, read by the overridden
-- GroupLootDropDown_GiveLoot and OPEN_MASTER_LOOT_LIST.
local sq, ss, sn

local function ApplyPanelBackdrop(frame, bg, border)
	pcall(frame.SetBackdrop, frame, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(frame.SetBackdropColor, frame, bg[1], bg[2], bg[3], bg[4] or 1)
	pcall(frame.SetBackdropBorderColor, frame, border[1], border[2], border[3], border[4] or 1)
end

local function OnSlotEnter()
	local slot = this:GetID()
	if LootSlotIsItem(slot) then
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetLootItem(slot)
		-- Price/count/id lines. On the legacy client the Tooltip module's
		-- SetLootItem wrapper adds them and this call is a no-op.
		if E.Tooltip then
			local _, _, quantity = GetLootSlotInfo(slot)
			pcall(E.Tooltip.AddItemLinesForSurface, E.Tooltip, GameTooltip, GetLootSlotLink(slot), quantity)
		end
		CursorUpdate(this)
	end

	this.drop:Show()
	this.drop:SetVertexColor(1, 1, 0)
end

local function OnSlotLeave()
	if this.quality and this.quality > 1 then
		local color = ITEM_QUALITY_COLORS[this.quality]
		this.drop:SetVertexColor(color.r, color.g, color.b)
	else
		this.drop:Hide()
	end

	GameTooltip:Hide()
	ResetCursor()
end

-- Deliberately does NOT call LootSlot(). Picking the item up is the engine's
-- own response to a real mouse click on a LootButton whose slot was bound
-- with Button:SetSlot -- no scripted call triggers it. On UA LootSlot() is
-- not a pickup call at all: it only confirms an ALREADY-PENDING bind-on-
-- pickup prompt for that slot, and does nothing otherwise. This handler
-- exists purely to record which slot was clicked, for the master-loot
-- dropdown and its confirmation popup below.
local function OnSlotClick()
	StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
	ss = this:GetID()
	sq = this.quality
	sn = this.name:GetText()
end

local function OnSlotShow()
	if GameTooltip:IsOwned(this) then
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetLootItem(this:GetID())
		CursorOnUpdate(this)
	end
end

local function anchorSlots(self)
	local shownSlots = 0
	local i
	for i = 1, table.getn(self.slots) do
		local frame = self.slots[i]
		if frame:IsShown() then
			shownSlots = shownSlots + 1
			-- No ClearAllPoints here -- this only ever needs to (re)set the
			-- TOP point. WoW frames support multiple independent anchor
			-- points at once (TOP for vertical + LEFT/RIGHT for horizontal
			-- don't conflict), so the LEFT/RIGHT pair from createSlot
			-- (which define the slot's width against lootFrame, and must
			-- keep tracking it every time lootFrame is resized on
			-- LOOT_OPENED) has to stay in place, not get cleared here.
			frame:SetPoint("TOP", lootFrame, "TOP", 4, (-8 + iconSize) - (shownSlots * iconSize))
		end
	end

	local height = shownSlots * iconSize + 16
	if height < 20 then height = 20 end
	self:SetHeight(height)
end

-- Blanks one of a button's three state faces. The getters are used rather
-- than SetNormalTexture("")/SetTexture(nil), neither of which reliably
-- clears a texture on UA; alpha 0 on the region object always does.
local function hideButtonFace(frame, getter)
	if not getter then return end

	local ok, tex = pcall(getter, frame)
	if ok and tex then
		pcall(tex.SetAlpha, tex, 0)
	end
end

-- The slot has to be a genuine "LootButton" widget, and the player's click
-- has to be a genuine mouse click: picking the item up is engine behavior
-- bound to that widget type through Button:SetSlot, reachable from Lua by
-- no other route. Button:Click() does not substitute -- it only runs the
-- OnClick script without going through the engine's mouse path.
--
-- The two clients construct one differently:
--   legacy: CreateFrame("LootButton", ...), the same call real ElvUI and
--           pfUI use -- the type is in that client's CreateFrame list.
--   UA:     that exact call returns nil (LootButton exists there only as an
--           XML type), but inheriting Blizzard's own LootButtonTemplate
--           from a "Button" call yields a real one -- GetObjectType() on
--           the result reports "LootButton", measured live, and clicking it
--           loots.
--
-- On UA the template also drags in the whole stock look and behavior, laid
-- out icon-LEFT/text-RIGHT -- the mirror image of ElvUI's own text-LEFT/
-- icon-RIGHT row, with different spacing besides. All of it is switched off
-- again below and the row rebuilt from this module's own regions, which are
-- kept either on child frames (immune to the parent's DisableDrawLayer) or
-- on the layers left enabled (BACKGROUND, OVERLAY):
--   BORDER   ItemButtonTemplate's $parentIconTexture/$parentCount/$parentStock
--   ARTWORK  LootButtonTemplate's UI-QuestItemNameFrame plate and $parentText
--   faces    ItemButtonTemplate's Quickslot2 border, its pressed state and
--            its square highlight
--   OnUpdate the template's CursorOnUpdate() ticker (the other inherited
--            scripts are all replaced outright further down)
local function createSlot(id)
	local frame
	if isUA then
		frame = CreateFrame("Button", "ElvLootSlot"..id, lootFrame, "LootButtonTemplate")

		frame:DisableDrawLayer("BORDER")
		frame:DisableDrawLayer("ARTWORK")

		hideButtonFace(frame, frame.GetNormalTexture)
		hideButtonFace(frame, frame.GetPushedTexture)
		hideButtonFace(frame, frame.GetHighlightTexture)

		frame:SetScript("OnUpdate", nil)
	else
		frame = CreateFrame("LootButton", "ElvLootSlot"..id, lootFrame)
	end
	frame:SetFrameStrata(LOOT_STRATA)

	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:SetPoint("LEFT", lootFrame, "LEFT", 8, 0)
	frame:SetPoint("RIGHT", lootFrame, "RIGHT", -8, 0)
	frame:SetHeight(iconSize - 2)
	frame:SetID(id)

	frame:SetScript("OnEnter", OnSlotEnter)
	frame:SetScript("OnLeave", OnSlotLeave)
	frame:SetScript("OnClick", OnSlotClick)
	frame:SetScript("OnShow", OnSlotShow)

	local iconFrame = CreateFrame("Frame", nil, frame)
	iconFrame:SetWidth(iconSize - 2)
	iconFrame:SetHeight(iconSize - 2)
	iconFrame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
	ApplyPanelBackdrop(iconFrame, {0, 0, 0, 1}, {0, 0, 0, 1})
	frame.iconFrame = iconFrame

	local icon = iconFrame:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
	frame.icon = icon

	local count = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetJustifyH("RIGHT")
	count:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
	count:SetText("1")
	frame.count = count

	local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetJustifyH("LEFT")
	name:SetPoint("LEFT", frame, "LEFT", 0, 0)
	name:SetPoint("RIGHT", icon, "LEFT", 0, 0)
	pcall(name.SetNonSpaceWrap, name, true)
	frame.name = name

	-- BACKGROUND, not ARTWORK: this is the full-row quality glow that has to
	-- sit under everything anyway, and on UA the button's ARTWORK layer is
	-- disabled outright to kill the inherited template art.
	local drop = frame:CreateTexture(nil, "BACKGROUND")
	drop:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
	drop:SetAllPoints(frame)
	drop:SetAlpha(0.3)
	frame.drop = drop

	lootFrame.slots[id] = frame
	return frame
end

local function LootSlotCleared()
	if not lootFrame:IsShown() then return end

	lootFrame.slots[arg1]:Hide()
	anchorSlots(lootFrame)
end

local function LootClosed()
	StaticPopup_Hide("LOOT_BIND")
	lootFrame:Hide()

	local _, v
	for _, v in pairs(lootFrame.slots) do
		v:Hide()
	end
end

local function OpenMasterLootList()
	ToggleDropDownMenu(1, nil, GroupLootDropDown, lootFrame.slots[ss], 0, 0)
end

local function UpdateMasterLootList()
	UIDropDownMenu_Refresh(GroupLootDropDown)
end

local function LootOpened()
	lootFrame:Show()

	if not lootFrame:IsShown() then
		CloseLoot(arg2 == 0)
	end

	local items = GetNumLootItems()

	if IsFishingLoot() then
		lootFrame.title:SetText(L["Fishy Loot"])
	elseif not UnitIsFriend("player", "target") and UnitIsDead("target") then
		lootFrame.title:SetText(UnitName("target"))
	else
		lootFrame.title:SetText(LOOT)
	end

	if E.private.general.lootUnderMouse then
		local x, y = GetCursorPosition()
		local scale = lootFrame:GetEffectiveScale()
		x = x / scale
		y = y / scale

		lootFrame:ClearAllPoints()
		lootFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 40, y + 20)
		lootFrame:Raise()
	else
		lootFrame:ClearAllPoints()
		lootFrame:SetPoint("TOPLEFT", lootFrameHolder, "TOPLEFT", 0, 0)
	end

	local maxQuality, width = 0, 0
	local titleWidth = lootFrame.title:GetStringWidth()

	if items > 0 then
		local i
		for i = 1, items do
			local slot = lootFrame.slots[i] or createSlot(i)
			local texture, item, quantity, quality = GetLootSlotInfo(i)
			local color = ITEM_QUALITY_COLORS[quality]

			if LootSlotIsCoin(i) then
				item = string.gsub(item, "\n", ", ")
			end

			if quantity and quantity > 1 then
				slot.count:SetText(quantity)
				slot.count:Show()
			else
				slot.count:Hide()
			end

			if quality and quality > 1 then
				slot.drop:SetVertexColor(color.r, color.g, color.b)
				slot.drop:Show()
			else
				slot.drop:Hide()
			end

			slot.quality = quality
			slot.name:SetText(item)
			if color then
				slot.name:SetTextColor(color.r, color.g, color.b)
			end
			slot.icon:SetTexture(texture)

			if quality then
				maxQuality = math.max(maxQuality, quality)
			end
			width = math.max(width, slot.name:GetStringWidth())

			slot:SetID(i)
			-- Binds the loot slot to the widget at engine level. Without
			-- this the button is inert on click, whatever its type.
			if slot.SetSlot then
				slot:SetSlot(i)
			end

			slot:Enable()
			slot:Show()
		end
	else
		local slot = lootFrame.slots[1] or createSlot(1)
		local color = ITEM_QUALITY_COLORS[0]

		slot.name:SetText(L["Empty Slot"])
		if color then
			slot.name:SetTextColor(color.r, color.g, color.b)
		end
		slot.icon:SetTexture("Interface\\Icons\\INV_Misc_Herb_AncientLichen")

		width = math.max(width, slot.name:GetStringWidth())

		slot.count:Hide()
		slot.drop:Hide()
		slot:Disable()
		slot:Show()
	end
	anchorSlots(lootFrame)

	width = width + 60
	titleWidth = titleWidth + 5

	local color = ITEM_QUALITY_COLORS[maxQuality]
	pcall(lootFrame.SetBackdropBorderColor, lootFrame, color.r, color.g, color.b, 0.8)
	lootFrame:SetWidth(math.max(width, titleWidth))
end

function M:LoadLoot()
	if not E.private.general.loot then return end

	lootFrameHolder = CreateFrame("Frame", "ElvLootFrameHolder", UIParent)
	lootFrameHolder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 36, -195)
	lootFrameHolder:SetWidth(150)
	lootFrameHolder:SetHeight(22)
	lootFrameHolder:SetFrameStrata(LOOT_STRATA)

	lootFrame = CreateFrame("Button", "ElvLootFrame", lootFrameHolder)
	lootFrame:SetClampedToScreen(true)
	lootFrame:SetPoint("TOPLEFT", lootFrameHolder, "TOPLEFT", 0, 0)
	lootFrame:SetWidth(256)
	lootFrame:SetHeight(64)
	ApplyPanelBackdrop(lootFrame, {0.05, 0.05, 0.05, 0.8}, {0, 0, 0, 1})
	lootFrame:SetFrameStrata(LOOT_STRATA)
	lootFrame:SetToplevel(true)

	local title = lootFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("BOTTOMLEFT", lootFrame, "TOPLEFT", 0, 1)
	lootFrame.title = title
	lootFrame.slots = {}

	lootFrame:SetScript("OnHide", function()
		StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
		CloseLoot()
	end)
	lootFrame:Hide()

	self:RegisterEvent("LOOT_OPENED", LootOpened)
	self:RegisterEvent("LOOT_SLOT_CLEARED", LootSlotCleared)
	self:RegisterEvent("LOOT_CLOSED", LootClosed)
	self:RegisterEvent("OPEN_MASTER_LOOT_LIST", OpenMasterLootList)
	self:RegisterEvent("UPDATE_MASTER_LOOT_LIST", UpdateMasterLootList)

	E:CreateMover(lootFrameHolder, "LootFrameMover", L["Loot Frame"])

	-- Permanently suppress the native loot window. UnregisterAllEvents
	-- alone does not stop a frame from re-Show()ing itself on UA -- a frame
	-- that Show()s itself from an "unregistered" event keeps doing so on
	-- this client -- so the OnEvent handler is nilled and Show itself is
	-- neutered too, same recipe as DataBars.lua's own M:HideNativeFrame.
	pcall(LootFrame.UnregisterAllEvents, LootFrame)
	pcall(LootFrame.SetScript, LootFrame, "OnEvent", nil)
	pcall(LootFrame.Hide, LootFrame)
	if LootFrame.Show then LootFrame.Show = E.noop end

	table.insert(UISpecialFrames, "ElvLootFrame")

	-- Overrides Blizzard's own global handler (FrameXML/LootFrame.lua) to
	-- give from our own selected-slot locals (ss/sq/sn) instead of the
	-- native LootFrame's selectedSlot/selectedQuality fields, which our
	-- own slot OnClick never populates.
	function _G.GroupLootDropDown_GiveLoot()
		if sq and sq >= (MASTER_LOOT_THREHOLD or 4) then
			local dialog = StaticPopup_Show("CONFIRM_LOOT_DISTRIBUTION", ITEM_QUALITY_COLORS[sq].hex..sn..FONT_COLOR_CODE_CLOSE, this:GetText())
			if dialog then
				dialog.data = this.value
			end
		else
			GiveMasterLoot(ss, this.value)
		end
		CloseDropDownMenus()
	end

	-- Retargets Blizzard's own native "CONFIRM_LOOT_DISTRIBUTION" popup
	-- (FrameXML/StaticPopup.lua) at the same ss local, rather than
	-- defining a whole new popup -- this project has no E.PopupDialogs
	-- registry (real ElvUI's own custom StaticPopup reimplementation), so
	-- the native StaticPopupDialogs table is used and overridden directly.
	local confirmDistribution = StaticPopupDialogs["CONFIRM_LOOT_DISTRIBUTION"]
	if confirmDistribution then
		confirmDistribution.OnAccept = function(data)
			GiveMasterLoot(ss, data)
		end
		confirmDistribution.preferredIndex = 3
	end
end
