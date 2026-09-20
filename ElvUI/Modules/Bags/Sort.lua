-- Bag sorting: the sort button in the header of the bag and bank windows.
--
-- ENGINE: Bagzen's (source/Bagzen/Sort.lua), not real ElvUI's. Real ElvUI
-- plans every move up front against a simulated copy of the bags and then
-- replays that fixed list, so a single move the client refuses or resolves
-- differently (a partial stack merge, a container rejecting the item) leaves
-- the rest of the list working on bags that no longer exist. It also depends
-- on API neither client here has (GetItemFamily, bit.band, table.wipe,
-- LibItemSearch-1.2, an equipped bag's item link on UA). This engine issues
-- ONE move at a time and reads the bags back before the next one: a move
-- counts as done only once its destination holds the expected item.
--
-- Two phases, as in both Bagzen and real ElvUI: partial stacks of the same
-- item are merged first, then the items are rearranged.
--
-- ORDER, Bagzen's keys: the Hearthstone, quest items (starters and quest items
-- exactly as the slot decoration classifies them, B.ClassifyItem), quality
-- high to low, item type, subtype, equip slot, name, item id high to low,
-- stack size low to high. Gray items sort in place under the same keys; they
-- are not collected at the end of the bags. Type and subtype are compared by
-- their English names, as Bagzen does, so on a non-English client those two
-- keys fall through to the equip slot and the name.
--
-- P.bags.sortInverted (real ElvUI, default on) mirrors every pool: the first
-- item of the order lands in the LAST slot and the free space collects at the
-- start -- the layout real ElvUI's ReverseSort produces.
--
-- POOLS: the general-purpose bags of one window form one continuous run of
-- slots. A specialty bag (quiver, ammo pouch, soul bag) is a pool of its own
-- that takes only the items it accepts and is filled before the general pool;
-- what does not fit spills into the general pool. A bag whose kind cannot be
-- established as general or one of those three (a herb or enchanting bag, an
-- unrecognised specialty) is left out of the sort entirely.
--
-- Bag kind, in order of evidence (ClassifyBag):
--   * the backpack and the bank's own slots are general;
--   * the equipped bag's item link and its subtype (real 1.12.1 client);
--   * GetInventoryItemLink returns nothing for bag slots on UA, so there the
--     bag button's icon path (QUIVER / AMMO; HERB / ENCHANT are left out) and
--     then the bag's contents (only ammunition, only Soul Shards) decide;
--   * otherwise general, but UNTRUSTED: when a move into or out of such a bag
--     is refused, the bag is taken out of the pool and the plan rebuilt.
--
-- UA MAIN BANK PANE (bag -1), measured by UnrealUI (core/compat.lua, its
-- bankmove/bankinv probes): it is written through the inventory API --
-- PickupInventoryItem(BankButtonIDToInvSlotID(slot)) -- and NO call pair
-- moves an item from one main-pane slot to another. Such a move is made in two
-- legal steps through a bank bag slot instead (StageSlot). The real 1.12.1
-- client takes PickupContainerItem(-1, slot) in every direction.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local B = E:GetModule("Bags")
local Util = ElvUI.Util
local Compat = ElvUI.Compat
local getn = Compat.getn

local SORT_ICON = "Interface\\AddOns\\ElvUI\\Media\\Textures\\INV_Pet_Broom"

local BANK_BAG = -1
local HEARTHSTONE = 6948
local SOUL_SHARD = 6265

-- Bag-family bits, in the client's own ItemFamily numbering. 0 is general.
local FAMILY_QUIVER = 1
local FAMILY_AMMO_POUCH = 2
local FAMILY_SOUL = 4

local TICK_INTERVAL = 0.05
-- A move not visible in its destination this long after the slots unlocked
-- was refused by the client.
local MOVE_TIMEOUT = 1.0
-- A slot the server keeps locked longer than this ends the run.
local LOCK_TIMEOUT = 3.0
-- The player holding an item on the cursor this long ends the run.
local CURSOR_TIMEOUT = 10
local MAX_REPLANS = 4
local MAX_MOVES = 500

-- Bagzen's rank tables, keyed by lower-case English names.
local TYPE_RANK = {
	["consumable"] = 0,
	["container"] = 1,
	["weapon"] = 2,
	["armor"] = 3,
	["gem"] = 4,
	["reagent"] = 5,
	["projectile"] = 6,
	["trade goods"] = 7,
	["item enhancement"] = 8,
	["recipe"] = 9,
	["money"] = 10,
	["quiver"] = 11,
	["quest"] = 12,
	["key"] = 13,
	["permanent"] = 14,
	["miscellaneous"] = 15,
	["glyph"] = 16,
	["profession"] = 16,
}

local SUBTYPE_RANK = {
	["trade goods"] = 1,
	["parts"] = 2,
	["devices"] = 3,
	["jewelcrafting"] = 4,
	["cloth"] = 5,
	["leather"] = 6,
	["metal & stone"] = 7,
	["cooking"] = 8,
	["herb"] = 9,
	["elemental"] = 10,
}

local EQUIP_RANK = {
	["INVTYPE_HEAD"] = 1,
	["INVTYPE_NECK"] = 2,
	["INVTYPE_SHOULDER"] = 3,
	["INVTYPE_BODY"] = 4,
	["INVTYPE_CHEST"] = 5,
	["INVTYPE_ROBE"] = 5,
	["INVTYPE_WAIST"] = 6,
	["INVTYPE_LEGS"] = 7,
	["INVTYPE_FEET"] = 8,
	["INVTYPE_WRIST"] = 9,
	["INVTYPE_HAND"] = 10,
	["INVTYPE_FINGER"] = 11,
	["INVTYPE_TRINKET"] = 13,
	["INVTYPE_CLOAK"] = 15,
	["INVTYPE_RANGED"] = 16,
	["INVTYPE_RANGEDRIGHT"] = 16,
	["INVTYPE_THROWN"] = 16,
	["INVTYPE_WEAPON"] = 16,
	["INVTYPE_WEAPONMAINHAND"] = 16,
	["INVTYPE_SHIELD"] = 17,
	["INVTYPE_HOLDABLE"] = 17,
	["INVTYPE_WEAPONOFFHAND"] = 18,
	["INVTYPE_TABARD"] = 19,
}

-- Specialty bag subtypes (English), for the item-link path.
local SPECIAL_BAG_SUBTYPES = {
	["quiver"] = FAMILY_QUIVER,
	["ammo pouch"] = FAMILY_AMMO_POUCH,
	["soul bag"] = FAMILY_SOUL,
}

-- Book pages whose names end in a bare number ("... - Page 9"), zero-padded
-- so page 9 sorts before page 10. Bagzen's SortItemNameHelper.
local PAGED_NAMES = {
	"Shredder Operating Manual - Page ",
	"Green Hills of Stranglethorn - Page ",
}

local function SortName(name)
	local i
	for i = 1, getn(PAGED_NAMES) do
		local prefix = PAGED_NAMES[i]
		local length = string.len(prefix)
		if string.len(name) > length and string.sub(name, 1, length) == prefix then
			local page = tonumber(string.sub(name, length + 1))
			if page then return prefix..string.format("%02d", page) end
		end
	end
	return name
end

local function SharesFamily(a, b)
	local bit = 1
	while bit <= FAMILY_SOUL do
		if Compat.mod(math.floor(a / bit), 2) == 1 and Compat.mod(math.floor(b / bit), 2) == 1 then
			return true
		end
		bit = bit * 2
	end
	return false
end

local function LinkID(link)
	if not link then return nil end
	local _, _, id = string.find(link, "item:(%d+)")
	return tonumber(id)
end

-- Identity of a slot's contents: the item string (id, enchant, suffix) plus
-- the stack size. Two slots with equal keys are interchangeable, so a slot
-- already holding an equal item never needs a move.
local function SlotKey(pos)
	local link = GetContainerItemLink(pos.bag, pos.slot)
	if not link then return nil end

	local _, _, itemString = string.find(link, "(item:[%-%d:]+)")
	local _, count = GetContainerItemInfo(pos.bag, pos.slot)
	return (itemString or link).."#"..(tonumber(count) or 1)
end

local function SlotLocked(pos)
	local _, _, locked = GetContainerItemInfo(pos.bag, pos.slot)
	return locked and true or false
end

local function CursorBusy()
	return type(CursorHasItem) == "function" and CursorHasItem() and true or false
end

-- GetItemInfo in the 1.12.1 return order (name, link, rarity, minLevel, type,
-- subType, stackCount, equipLoc), cached for the length of one run.
local function GetInfo(run, id)
	local info = run.info[id]
	if info then return info end

	local ok, name, _, rarity, _, itemType, subType, stack, equipLoc = pcall(GetItemInfo, id)
	info = {
		name = (ok and type(name) == "string") and name or "",
		rarity = (ok and tonumber(rarity)) or 0,
		itemType = (ok and type(itemType) == "string") and itemType or "",
		subType = (ok and type(subType) == "string") and subType or "",
		stack = (ok and tonumber(stack)) or 1,
		equipLoc = (ok and type(equipLoc) == "string") and equipLoc or "",
	}
	run.info[id] = info
	return info
end

-- Which specialty bags accept an item: 0 for none. Ammunition of a subtype
-- that is not recognised (a non-English client) is allowed into both kinds of
-- ammunition bag.
local function ItemFamily(id, info)
	if id == SOUL_SHARD then return FAMILY_SOUL end
	if info.equipLoc ~= "INVTYPE_AMMO" then return 0 end

	local subType = string.lower(info.subType)
	if subType == "arrow" then return FAMILY_QUIVER end
	if subType == "bullet" then return FAMILY_AMMO_POUCH end
	return FAMILY_QUIVER + FAMILY_AMMO_POUCH
end

-- The family every item in a bag shares, or nil when the bag is empty or holds
-- anything a specialty bag would not take.
local function ContentFamily(run, bagID)
	local family
	local slot
	for slot = 1, B:GetSlotCount(bagID) do
		local id = LinkID(GetContainerItemLink(bagID, slot))
		if id then
			local itemFamily = ItemFamily(id, GetInfo(run, id))
			if itemFamily == 0 then return nil end
			if family and family ~= itemFamily then return nil end
			family = itemFamily
		end
	end
	return family
end

-- The equipped bag's icon, read from the client's own bag slot button: those
-- buttons know their contents on both clients, where the inventory API does
-- not on UA.
local function BagTexture(bagID)
	local numBagSlots = NUM_BAG_SLOTS or 4
	local name
	if bagID <= numBagSlots then
		name = "CharacterBag"..(bagID - 1).."Slot"
	else
		name = "BankFrameBag"..(bagID - numBagSlots)
	end

	local icon = _G[name.."IconTexture"]
	if icon and icon.GetTexture then
		local ok, texture = pcall(icon.GetTexture, icon)
		if ok and type(texture) == "string" then return texture end
	end

	local okSlot, invSlot = pcall(ContainerIDToInventoryID, bagID)
	if okSlot and invSlot then
		local okTexture, texture = pcall(GetInventoryItemTexture, "player", invSlot)
		if okTexture and type(texture) == "string" then return texture end
	end

	return nil
end

-- Returns the bag's family (0 general, a family bit for a specialty bag, or
-- false to leave the bag out of the sort) and whether that verdict is trusted.
local function ClassifyBag(run, bagID)
	if bagID == 0 or bagID == BANK_BAG then return 0, true end

	local link
	local okSlot, invSlot = pcall(ContainerIDToInventoryID, bagID)
	if okSlot and invSlot then
		local okLink, bagLink = pcall(GetInventoryItemLink, "player", invSlot)
		if okLink and type(bagLink) == "string" then link = bagLink end
	end

	if link then
		local id = LinkID(link)
		if id then
			local info = GetInfo(run, id)
			local subType = string.lower(info.subType)
			if (INVTYPE_BAG and info.subType == INVTYPE_BAG) or subType == "bag" then
				return 0, true
			end
			if SPECIAL_BAG_SUBTYPES[subType] then
				return SPECIAL_BAG_SUBTYPES[subType], true
			end
		end
		return ContentFamily(run, bagID) or false, true
	end

	local texture = BagTexture(bagID)
	if texture then
		texture = string.upper(texture)
		if string.find(texture, "QUIVER", 1, true) then return FAMILY_QUIVER, true end
		if string.find(texture, "AMMO", 1, true) then return FAMILY_AMMO_POUCH, true end
		if string.find(texture, "HERB", 1, true) or string.find(texture, "ENCHANT", 1, true) then
			return false, true
		end
	end

	local family = ContentFamily(run, bagID)
	if family then return family, true end

	return 0, false
end

-- Every slot of every bag this run may touch, in bag order.
local function BuildPositions(run)
	local positions = {}
	local i
	for i = 1, getn(run.bagIDs) do
		local bagID = run.bagIDs[i]
		if not run.excluded[bagID] then
			local family, trusted = ClassifyBag(run, bagID)
			if family then
				local slot
				for slot = 1, B:GetSlotCount(bagID) do
					table.insert(positions, { bag = bagID, slot = slot, family = family, trusted = trusted })
				end
			end
		end
	end
	return positions
end

local function SortRecord(run, pos, key, index)
	local id = LinkID(GetContainerItemLink(pos.bag, pos.slot)) or 0
	local info = GetInfo(run, id)
	local _, count = GetContainerItemInfo(pos.bag, pos.slot)

	local isQuestItem, isQuestStarter, invalidQuestItem
	if B.ClassifyItem then
		isQuestItem, isQuestStarter, invalidQuestItem = B.ClassifyItem(tostring(id))
	end

	return {
		key = key,
		index = index,
		family = ItemFamily(id, info),
		priority = (id == HEARTHSTONE) and 1 or 100,
		quest = (isQuestStarter or (isQuestItem and not invalidQuestItem)) and 0 or 1,
		quality = info.rarity,
		typeRank = TYPE_RANK[string.lower(info.itemType)] or 100,
		subRank = SUBTYPE_RANK[string.lower(info.subType)] or 100,
		equipRank = EQUIP_RANK[string.upper(info.equipLoc)] or 100,
		name = SortName(info.name),
		id = id,
		count = tonumber(count) or 1,
	}
end

-- A strict total order: every field is always set, and the slot the item was
-- read from breaks the last tie. table.sort raises "invalid order function"
-- on a comparator that is not consistent.
local function ItemBefore(a, b)
	if a.priority ~= b.priority then return a.priority < b.priority end
	if a.quest ~= b.quest then return a.quest < b.quest end
	if a.quality ~= b.quality then return a.quality > b.quality end
	if a.typeRank ~= b.typeRank then return a.typeRank < b.typeRank end
	if a.subRank ~= b.subRank then return a.subRank < b.subRank end
	if a.equipRank ~= b.equipRank then return a.equipRank < b.equipRank end
	if a.name ~= b.name then return a.name < b.name end
	if a.id ~= b.id then return a.id > b.id end
	if a.count ~= b.count then return a.count < b.count end
	return a.index < b.index
end

-- Specialty pools first, general last.
local function FamilyBefore(a, b)
	if a == 0 then return false end
	if b == 0 then return true end
	return a < b
end

-- Builds run.positions (specialty pools, then the general pool) and
-- run.desired[i], the item key that belongs at positions[i] (nil: empty).
-- Returns false when the items cannot be placed.
local function Plan(run)
	local positions = BuildPositions(run)
	local pools, families, records = {}, {}, {}

	local i
	for i = 1, getn(positions) do
		local pos = positions[i]
		if not pools[pos.family] then
			pools[pos.family] = {}
			table.insert(families, pos.family)
		end
		table.insert(pools[pos.family], pos)

		local key = SlotKey(pos)
		if key then table.insert(records, SortRecord(run, pos, key, i)) end
	end

	table.sort(records, ItemBefore)
	table.sort(families, FamilyBefore)

	local placed, lists = {}, {}
	local f
	for f = 1, getn(families) do
		local family = families[f]
		local capacity = getn(pools[family])
		local list = {}
		local r
		for r = 1, getn(records) do
			if not placed[r] and getn(list) < capacity then
				local rec = records[r]
				if family == 0 or (rec.family ~= 0 and SharesFamily(rec.family, family)) then
					table.insert(list, rec.key)
					placed[r] = true
				end
			end
		end
		lists[family] = list
	end

	for i = 1, getn(records) do
		if not placed[i] then return false end
	end

	local planPositions, desired = {}, {}
	for f = 1, getn(families) do
		local pool = pools[families[f]]
		local list = lists[families[f]]
		local size = getn(pool)
		local s
		for s = 1, size do
			table.insert(planPositions, pool[s])
			if run.inverted then
				desired[getn(planPositions)] = list[size + 1 - s]
			else
				desired[getn(planPositions)] = list[s]
			end
		end
	end

	run.positions = planPositions
	run.desired = desired
	run.index = 1
	return true
end

-- Pick up from, or drop the cursor into, one slot.
local function Pickup(pos)
	if pos.bag == BANK_BAG and Compat.isUA and type(BankButtonIDToInvSlotID) == "function" then
		local ok, invSlot = pcall(BankButtonIDToInvSlotID, pos.slot)
		if ok and invSlot then
			pcall(PickupInventoryItem, invSlot)
			return
		end
	end
	pcall(PickupContainerItem, pos.bag, pos.slot)
end

local function CanExchange(a, b)
	return not (Compat.isUA and a.bag == BANK_BAG and b.bag == BANK_BAG)
end

-- Lift, drop, and put whatever the drop left on the cursor back into the
-- source slot. A refused drop leaves the LIFTED item there and that same last
-- step returns it, so this cannot tell a swap from a refusal -- the caller
-- finds out by reading the destination back.
local function Move(run, src, dst)
	run.holding = src
	Pickup(src)
	if not CursorBusy() then
		run.holding = nil
		return false
	end

	Pickup(dst)
	if CursorBusy() then Pickup(src) end
	if CursorBusy() then return false end

	run.holding = nil
	return true
end

local function ReleaseCursor(run)
	if CursorBusy() and run.holding then Pickup(run.holding) end
	if CursorBusy() then pcall(ClearCursor) end
	run.holding = nil
end

local function Confused()
	B:FinishSort(L["Confused.. Try Again!"])
end

-- One clock per kind of wait (identified by its limit), so a long wait for the
-- cursor does not count against the shorter one for a lock that follows it.
local function Wait(run, now, limit)
	if run.waitLimit ~= limit or not run.waitSince then
		run.waitSince = now
		run.waitLimit = limit
	end
	if now - run.waitSince > limit then Confused() end
end

local function Replan(run)
	run.replans = run.replans + 1
	if run.replans > MAX_REPLANS or not Plan(run) then
		Confused()
		return false
	end
	return true
end

-- A move that could not even be issued: the item is dropped from merging in
-- the stack phase, and the plan is rebuilt in the sort phase.
local function GiveUp(run, itemID)
	if run.phase == "stack" then
		run.noStack[itemID or 0] = true
	else
		Replan(run)
	end
end

-- kind "stack": landed once either slot changed. Otherwise: landed once the
-- destination holds `key`.
local function IssueMove(run, src, dst, kind, key, itemID)
	run.waitSince = nil

	if run.moves >= MAX_MOVES then
		Confused()
		return
	end

	local srcKey, dstKey = SlotKey(src), SlotKey(dst)
	if not Move(run, src, dst) then
		ReleaseCursor(run)
		GiveUp(run, itemID)
		return
	end

	run.moves = run.moves + 1
	run.pending = {
		kind = kind,
		src = src,
		dst = dst,
		key = key,
		srcKey = srcKey,
		dstKey = dstKey,
		itemID = itemID,
		at = GetTime(),
	}
end

-- True: the last move is settled and the run may issue the next one this
-- tick. False: still waiting, or the run was replanned or finished.
local function CheckPending(run, now)
	local p = run.pending

	local landed
	if p.kind == "stack" then
		landed = SlotKey(p.src) ~= p.srcKey or SlotKey(p.dst) ~= p.dstKey
	else
		landed = SlotKey(p.dst) == p.key
	end

	if landed then
		run.pending = nil
		return true
	end

	if SlotLocked(p.src) or SlotLocked(p.dst) then
		if now - p.at > LOCK_TIMEOUT then Confused() end
		return false
	end

	if now - p.at < MOVE_TIMEOUT then return false end

	-- Refused.
	run.pending = nil
	ReleaseCursor(run)

	if run.phase == "stack" then
		run.noStack[p.itemID or 0] = true
		return true
	end

	local suspect
	if not p.dst.trusted then
		suspect = p.dst.bag
	elseif not p.src.trusted then
		suspect = p.src.bag
	end

	if not suspect then
		Confused()
		return false
	end

	run.excluded[suspect] = true
	Replan(run)
	return false
end

-- A slot to carry an item through when the client will not move it directly
-- (UA: main bank pane to main bank pane): a general-purpose slot outside that
-- pane, a free one preferred. An occupied one works as well -- its item is
-- swapped into the source slot and sorted from there like any other.
-- `usable(i)` rules out slots the caller must not disturb.
local function StageSlot(positions, usable, requireFree)
	local occupied
	local i
	for i = 1, getn(positions) do
		local pos = positions[i]
		if pos.bag ~= BANK_BAG and pos.family == 0 and usable(i) then
			if not SlotKey(pos) then return pos end
			occupied = occupied or pos
		end
	end
	if requireFree then return nil end
	return occupied
end

local function AnySlot()
	return true
end

-- Merge one pair of partial stacks of the same item, or move toward one.
local function StackStep(run, now)
	local positions = run.stackPositions
	local byItem, order = {}, {}

	local i
	for i = 1, getn(positions) do
		local pos = positions[i]
		local id = LinkID(GetContainerItemLink(pos.bag, pos.slot))
		if id and not run.noStack[id] then
			local _, count = GetContainerItemInfo(pos.bag, pos.slot)
			if (tonumber(count) or 1) < GetInfo(run, id).stack then
				if not byItem[id] then
					byItem[id] = {}
					table.insert(order, id)
				end
				table.insert(byItem[id], pos)
			end
		end
	end

	for i = 1, getn(order) do
		local id = order[i]
		local list = byItem[id]
		local n = getn(list)
		if n >= 2 then
			local src, dst
			local a
			for a = n - 1, 1, -1 do
				local b
				for b = n, a + 1, -1 do
					if not src and CanExchange(list[a], list[b]) then
						src, dst = list[a], list[b]
					end
				end
			end

			if src then
				if SlotLocked(src) or SlotLocked(dst) then
					Wait(run, now, LOCK_TIMEOUT)
					return
				end
				IssueMove(run, src, dst, "stack", nil, id)
				return
			end

			-- Every partial stack of this item is in the UA main bank pane:
			-- carry one out so the next pass can merge it back in.
			local stage = StageSlot(positions, AnySlot, true)
			if stage then
				local from = list[n - 1]
				if SlotLocked(from) or SlotLocked(stage) then
					Wait(run, now, LOCK_TIMEOUT)
					return
				end
				IssueMove(run, from, stage, "move", SlotKey(from), id)
				return
			end

			run.noStack[id] = true
		end
	end

	run.phase = "sort"
	if not Plan(run) then Confused() end
end

-- Walk the plan: every position before run.index that has a desired item
-- already holds it; bring the next missing one in.
local function SortStep(run, now)
	local positions, desired = run.positions, run.desired
	local total = getn(positions)

	while run.index <= total do
		local index = run.index
		local pos = positions[index]
		local want = desired[index]

		if want == nil or SlotKey(pos) == want then
			run.index = index + 1
		else
			local source, fallback
			local j
			for j = 1, total do
				if j ~= index and (j > index or desired[j] == nil) and SlotKey(positions[j]) == want then
					if CanExchange(positions[j], pos) then
						source = positions[j]
						break
					end
					fallback = fallback or positions[j]
				end
			end

			if source then
				if SlotLocked(source) or SlotLocked(pos) then
					Wait(run, now, LOCK_TIMEOUT)
					return
				end
				IssueMove(run, source, pos, "move", want)
				return
			end

			if not fallback then
				-- The bags no longer hold what the plan expects.
				Replan(run)
				return
			end

			local stage = StageSlot(positions, function(k)
				return k > index or desired[k] == nil
			end, false)

			if not stage then
				B:FinishSort(L["Sorting the bank needs at least one bank bag."])
				return
			end

			if SlotLocked(fallback) or SlotLocked(stage) then
				Wait(run, now, LOCK_TIMEOUT)
				return
			end
			IssueMove(run, fallback, stage, "move", want)
			return
		end
	end

	B:FinishSort()
end

function B:SortTick()
	local run = self.sortRun
	if not run then
		if self.SortDriver then self.SortDriver:Hide() end
		return
	end

	local now = GetTime()
	if now < run.nextTick then return end
	run.nextTick = now + TICK_INTERVAL

	-- The bank's slots stop being writable the moment the banker session
	-- ends; the closed window is its own explanation, so no message.
	if run.isBank and not (self.BankFrame and self.BankFrame:IsShown()) then
		self:FinishSort()
		return
	end

	if run.pending then
		if not CheckPending(run, now) then return end
		if self.sortRun ~= run then return end
	end

	if CursorBusy() then
		Wait(run, now, CURSOR_TIMEOUT)
		return
	end

	if run.phase == "stack" then
		StackStep(run, now)
	else
		SortStep(run, now)
	end
end

-- One run at a time for both windows: there is one cursor.
function B:SortBags(isBank)
	local db = E.db.bags

	if self.sortRun then
		E:Print(L["Already Running.. Bailing Out!"])
		return
	end

	if isBank then
		if db.disableBankSort or not (self.BankFrame and self.BankFrame:IsShown()) then return end
	elseif db.disableBagSort then
		return
	end

	-- Sorting drives the cursor; an item already on it would be dropped into
	-- the first slot the run touches.
	if CursorBusy() then return end

	if not self.SortDriver then
		self.SortDriver = CreateFrame("Frame", nil, UIParent)
		self.SortDriver:Hide()
		self.SortDriver:SetScript("OnUpdate", function() B:SortTick() end)
	end

	local run = {
		isBank = isBank,
		bagIDs = isBank and self.BankIDs or self.BagIDs,
		inverted = db.sortInverted and true or false,
		excluded = {},
		info = {},
		noStack = {},
		phase = "stack",
		moves = 0,
		replans = 0,
		nextTick = 0,
	}
	run.stackPositions = BuildPositions(run)

	self.sortRun = run
	self.SortDriver:Show()
end

-- message: printed to chat, or nil to end silently.
function B:FinishSort(message)
	local run = self.sortRun
	if not run then return end

	self.sortRun = nil
	if self.SortDriver then self.SortDriver:Hide() end
	ReleaseCursor(run)

	if message then E:Print(message) end
end

function B:ApplySortButtonState(f)
	local button = f and f.sortButton
	if not button then return end

	local disabled
	if f.isBank then
		disabled = E.db.bags.disableBankSort
	else
		disabled = E.db.bags.disableBagSort
	end

	if disabled then button:Disable() else button:Enable() end
	if button.icon then
		pcall(button.icon.SetDesaturated, button.icon, disabled and true or false)
	end
end

-- Config entry point, real ElvUI's name.
function B:ToggleSortButtonState(isBank)
	self:ApplySortButtonState(self:GetContainerFrame(isBank))
end

-- Called from B:ConstructContainerFrame at the point in the header chain where
-- real ElvUI has the sort button: right of the keyring button on the bag
-- window, right of the bags button on the bank window.
function B:ConstructSortButton(f, name, isBank)
	local button = CreateFrame("Button", name.."SortButton", f)
	button:SetWidth(18)
	button:SetHeight(18)
	button:SetNormalTexture(SORT_ICON)

	local icon = button:GetNormalTexture()
	if icon then
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
	end
	button.icon = icon

	Util.CreateButtonBorder(button)
	self:AnchorHeaderButton(f, button)

	button:SetScript("OnClick", function() B:SortBags(isBank) end)
	button:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Sort Bags"])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	f.sortButton = button
	self:ApplySortButtonState(f)
end
