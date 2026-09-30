-- Skins > Blizzard > Bags -- reskins the native bag windows
-- (`ContainerFrame1..12`, which also serve the keyring and the bank bags) and
-- the native `BankFrame` in place. Real ElvUI's Blizzard/Bags.lua, gated the
-- same way: `E.private.skins.blizzard.bags`, and only while the Bags module is
-- off. The module replaces both windows with its own (and borrows the native
-- item buttons for it), so with the module on there is nothing native left to
-- skin -- the config toggle is greyed out then.
--
-- Native structure (FrameXML ContainerFrame.xml / BankFrame.xml):
--
-- - A container's art is its own ARTWORK regions (`$parentBackgroundTop`,
--   `Middle1-2`, `Bottom`) plus the BACKGROUND `$parentPortrait`.
--   `ContainerFrame_GenerateFrame` re-textures AND re-`Show()`s the art by
--   global name every time a bag opens, which a per-region `Show = noop` does
--   not reliably survive on this client (Merchant.lua, same finding). Both
--   layers are therefore disabled as a standing frame property. The bag name
--   (`$parentName`) shares the ARTWORK layer, so it is promoted to OVERLAY
--   first. Nothing is anchored to the disabled regions except each other.
-- - The frames are reused: `GenerateFrame` hands any free ContainerFrame to
--   whichever bag opens and resizes it, so all twelve are styled up front,
--   with every one of their 36 item buttons.
-- - `BankFrame` carries one ARTWORK texture (the whole window art), three
--   FontStrings on that same layer (title, "Item Slots", "Bag Slots"; two of
--   them unnamed) and the BACKGROUND `BankPortraitTexture`. Same treatment:
--   every FontString promoted, both layers disabled.
-- - Every item slot is `ItemButtonTemplate`-shaped, so `Util.SkinItemButton`
--   applies unchanged (as in the Bags module and on the merchant window).
--
-- Quality borders, as in real ElvUI: an item of uncommon quality or better
-- gets its quality colour on the slot border, everything else the default
-- border. Recoloured on every `ContainerFrame_Update` (bag contents, lock and
-- cooldown changes) and on every open, since `GenerateFrame` fills the slots
-- without calling it; bank slots on every `BankFrameItemButton_OnUpdate` and
-- on every bank open.
--
-- No `S:SkinChildren` sweep: every widget of both windows is named in the
-- FrameXML and handled below, and the item grids are the only bulk.
--
-- Deliberately NOT done: real ElvUI's two grouping boxes around the bank's
-- item grid and bag row. A child frame always draws above its parent's own
-- regions, and the box around the grid would reach up to the "Item Slots"
-- label that sits just above the first row.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

local NUM_CONTAINERS = _G.NUM_CONTAINER_FRAMES or 12
local MAX_ITEMS = _G.MAX_CONTAINER_ITEMS or 36
local NUM_BANK_SLOTS = _G.NUM_BANKGENERIC_SLOTS or 24
local NUM_BANK_BAGS = _G.NUM_BANKBAGSLOTS or 6
local BANK_CONTAINER_ID = _G.BANK_CONTAINER or -1

-- Real ElvUI's own insets for both windows. A container's art leaves a
-- transparent margin on the left and top; the bank art leaves a wide one on
-- the right and a tall one at the bottom (the native HitRectInsets are
-- right=30, bottom=70).
local CONTAINER_LEFT, CONTAINER_TOP, CONTAINER_RIGHT, CONTAINER_BOTTOM = 9, -4, -4, 2
local BANK_LEFT, BANK_TOP, BANK_RIGHT, BANK_BOTTOM = 10, -11, -26, 93

-- Border colour for the item behind `link`: its quality colour from uncommon
-- up, the default border otherwise. The rarity comes from GetItemInfo, not
-- from GetContainerItemInfo, whose quality return is not reliable on this
-- client generation (the Bags module reads it the same way).
local function SlotBorderColor(link)
	local border = ElvUI.Util.BORDER_COLOR
	if not link then return border[1], border[2], border[3] end

	local _, _, idText = string.find(link, "item:(%d+)")
	local itemID = tonumber(idText)
	if not itemID then return border[1], border[2], border[3] end

	local okInfo, _, _, rarity = pcall(GetItemInfo, itemID)
	if okInfo and rarity and rarity > 1 then
		local okColor, r, g, b = pcall(GetItemQualityColor, rarity)
		if okColor and r then return r, g, b end
	end
	return border[1], border[2], border[3]
end

local function ColorSlot(button, containerID)
	if not button or not button.elvBackdrop then return end
	local okSlot, slot = pcall(button.GetID, button)
	if not okSlot then return end
	local okLink, link = pcall(GetContainerItemLink, containerID, slot)
	local r, g, b = SlotBorderColor(okLink and link or nil)
	pcall(button.elvBackdrop.SetBackdropBorderColor, button.elvBackdrop, r, g, b, 1)
end

local function ColorContainerFrame(frame)
	if not frame then return end
	local okID, id = pcall(frame.GetID, frame)
	local okName, name = pcall(frame.GetName, frame)
	if not okID or not okName or not name then return end

	local size = tonumber(frame.size) or 0
	local j
	for j = 1, size do
		ColorSlot(_G[name.."Item"..j], id)
	end
end

local function ColorBankFrame()
	local i
	for i = 1, NUM_BANK_SLOTS do
		ColorSlot(_G["BankFrameItem"..i], BANK_CONTAINER_ID)
	end
end

local function StyleSlot(button)
	if not button then return end
	ElvUI.Util.SkinItemButton(button)
	-- The item cooldown is a child one level above the button's ORIGINAL
	-- level; SkinItemButton raises the button past it.
	ElvUI.Util.RaiseCooldown(button)
end

-- Promotes every FontString directly on `frame` to OVERLAY, so the layer it
-- came from can be disabled without taking the text with it, and so the panel
-- (a child frame at the frame's own level) does not cover it.
local function PromoteFontStrings(frame)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "FontString" then
			pcall(region.SetDrawLayer, region, "OVERLAY")
		end
	end
end

-- The native close buttons sit in the art's own corner, outside the panel's
-- insets; pinned to the panel corner instead.
local function StyleClose(button, frame)
	if not button then return end
	S:StyleCloseButton(button)
	if frame.elvBackground then
		pcall(button.ClearAllPoints, button)
		pcall(button.SetPoint, button, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end
end

local function SkinContainerFrame(index)
	local frame = _G["ContainerFrame"..index]
	if not frame or frame.elvBagSkinned then return true end

	local name = "ContainerFrame"..index
	local nameText = _G[name.."Name"]
	if nameText then pcall(nameText.SetDrawLayer, nameText, "OVERLAY") end
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
	pcall(frame.DisableDrawLayer, frame, "ARTWORK")

	S:CreatePanel(frame, CONTAINER_LEFT, CONTAINER_TOP, CONTAINER_RIGHT, CONTAINER_BOTTOM)
	StyleClose(_G[name.."CloseButton"], frame)

	local k
	for k = 1, MAX_ITEMS do
		StyleSlot(_G[name.."Item"..k])
	end

	frame.elvBagSkinned = true
	return S:TryHookScript(frame, "OnShow", function() ColorContainerFrame(frame) end)
end

local function SkinBankFrame()
	local frame = _G.BankFrame
	if not frame then return true end

	PromoteFontStrings(frame)
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
	pcall(frame.DisableDrawLayer, frame, "ARTWORK")

	S:CreatePanel(frame, BANK_LEFT, BANK_TOP, BANK_RIGHT, BANK_BOTTOM)
	StyleClose(_G.BankCloseButton, frame)

	local i
	for i = 1, NUM_BANK_SLOTS do
		StyleSlot(_G["BankFrameItem"..i])
	end
	for i = 1, NUM_BANK_BAGS do
		StyleSlot(_G["BankFrameBag"..i])
	end

	if _G.BankFramePurchaseButton then
		S:StyleUIPanelButton(_G.BankFramePurchaseButton)
	end

	return S:TryHookScript(frame, "OnShow", ColorBankFrame)
end

local function LoadSkin()
	if E.private.bags and E.private.bags.enable then return end

	local ok = true
	local i
	for i = 1, NUM_CONTAINERS do
		ok = SkinContainerFrame(i) and ok
	end
	ok = SkinBankFrame() and ok

	-- `ContainerFrame_Update(frame)` is called with the frame as its argument;
	-- `this` is the same frame when it runs from the container's OnEvent.
	local updateOk = pcall(function()
		S:SecureHook("ContainerFrame_Update", function(frame) ColorContainerFrame(frame or _G.this) end)
	end)
	-- Runs with `this` set to the bank slot being refreshed. Bank BAG slots
	-- hold bags, not bank items, and keep the default border.
	local bankOk = pcall(function()
		S:SecureHook("BankFrameItemButton_OnUpdate", function()
			local slot = _G.this
			if slot and not slot.isBag then ColorSlot(slot, BANK_CONTAINER_ID) end
		end)
	end)

	if not (ok and updateOk and bankOk) then S:ReportSkinProblem() end
end

S:AddBlizzardSkin("bags", LoadSkin)
