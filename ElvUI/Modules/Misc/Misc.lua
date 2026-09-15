-- Misc module -- the catch-all real ElvUI keeps for small features that
-- don't earn a module of their own (source/ElvUI-vanilla/ElvUI/Modules/
-- Misc/). Ported so far: the solo loot window, the raid marker ring, the
-- group loot roll bars and auto repair, plus the colour picker replacement
-- (real ElvUI keeps that one in Modules/Blizzard/, a module this project
-- does not have); the rest of that folder's surface
-- (interrupt announce, enhanced PvP messages, auto invite, error-frame toggle,
-- forced CVars, AFK screen, chat bubbles) is not. Each feature is its own file beside
-- Loot.lua, defining one M:Load*() that Initialize below calls -- the same
-- arrangement real ElvUI's own Misc.lua uses. Auto repair is the exception:
-- real ElvUI keeps it in Misc.lua itself, and so does this file.
--
-- Files under Modules/Misc/ do NOT create modules of their own: they attach
-- to this one with E:GetModule("Misc"), the way Modules/Skins/Blizzard/*
-- attaches to Skins. This is real ElvUI's own arrangement, and it matches
-- how these features are configured -- every one of them is a leaf in the
-- shared general config tree, not a category of its own.

local E, L, V, P, G = unpack(ElvUI)
local M = E:NewModule("Misc", "AceEvent-3.0")
E.Misc = M

-- Repairs everything on opening a repair-capable merchant (real ElvUI's
-- general.autoRepair, with its checks and messages). Holding Shift while the
-- merchant opens skips it. A "GUILD" value from an imported profile repairs
-- from the player's own money: guild bank repair does not exist on this
-- client version, and RepairAllItems takes no argument here.
--
-- Gray items are sold by the Bags module on the same event
-- (B:InitializeVendorGrays); the two do not depend on each other's order.
function M:AutoRepair()
	local mode = E.db.general.autoRepair
	if not mode or mode == "NONE" or IsShiftKeyDown() then return end
	if type(CanMerchantRepair) ~= "function" or not CanMerchantRepair() then return end

	local cost, possible = GetRepairAllCost()
	cost = tonumber(cost) or 0
	if not possible or cost <= 0 then return end

	if (GetMoney() or 0) < cost then
		E:Print(L["You don't have enough money to repair."])
		return
	end

	pcall(RepairAllItems)
	E:Print(L["Your items have been repaired for: "]..E:FormatMoney(cost, "BLIZZARD"))
end

function M:Initialize()
	self:LoadLoot()
	self:LoadRaidMarker()
	self:LoadLootRoll()
	self:LoadColorPicker()

	-- AceEvent passes no event arguments on UA; none are needed.
	self:RegisterEvent("MERCHANT_SHOW", function() M:AutoRepair() end)
end

E:RegisterInitialModule(M:GetName(), function() M:Initialize() end)
