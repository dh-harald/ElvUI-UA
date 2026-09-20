-- Avoidance DataText -- faithful port of real ElvUI's own Avoidance.lua
-- (ElvUI-vanilla/ElvUI/Modules/DataTexts/Avoidance.lua).

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts
local Compat = ElvUI.Compat

local AVD_DECAY_RATE = 0.2
local targetlv, playerlv = 0, 0
local dodge, parry, block, baseMissChance, avoidance, unhittable = 0, 0, 0, 0, 0, 0

-- Accent-coloured VALUE half -- see Armor.lua's own note on why this is a
-- rebuilt format string and not a per-update format call.
local displayString = L["Defense"]..": %.2f%%"

local function ValueColorUpdate(hex)
	displayString = L["Defense"]..": "..hex.."%.2f%%|r"
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

local function IsWearingShield()
	local slotID = GetInventorySlotInfo("SecondaryHandSlot")
	local itemLink = GetInventoryItemLink("player", slotID)
	if itemLink then
		local id = Compat.match(itemLink, "item:(%d+)")
		if not id then return nil end
		-- Positional capture, not `select(9, ...)`: `select` does not exist
		-- on the legacy client's Lua 5.0 at all. The 9th return is the
		-- equip slot, which upstream compares against "INVTYPE_SHIELD"
		-- rather than treating as a boolean -- kept identical below.
		local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(tonumber(id))
		return equipSlot
	end
end

local function OnEvent(self)
	targetlv, playerlv = UnitLevel("target") or 0, UnitLevel("player") or 0

	baseMissChance = E.myrace == "NightElf" and 7 or 5
	local levelDifference
	if targetlv == -1 then
		levelDifference = 3
	elseif targetlv > 0 then
		levelDifference = targetlv - playerlv
	else
		levelDifference = 0
	end

	if levelDifference >= 0 then
		dodge = GetDodgeChance() - levelDifference * AVD_DECAY_RATE
		parry = GetParryChance() - levelDifference * AVD_DECAY_RATE
		block = GetBlockChance() - levelDifference * AVD_DECAY_RATE
		baseMissChance = baseMissChance - levelDifference * AVD_DECAY_RATE
	else
		dodge = GetDodgeChance() + math.abs(levelDifference * AVD_DECAY_RATE)
		parry = GetParryChance() + math.abs(levelDifference * AVD_DECAY_RATE)
		block = GetBlockChance() + math.abs(levelDifference * AVD_DECAY_RATE)
		baseMissChance = baseMissChance + math.abs(levelDifference * AVD_DECAY_RATE)
	end

	if dodge <= 0 then dodge = 0 end
	if parry <= 0 then parry = 0 end
	if block <= 0 then block = 0 end

	if E.myclass == "DRUID" and GetBonusBarOffset() == 3 then
		parry = 0
	end

	if IsWearingShield() ~= "INVTYPE_SHIELD" then
		block = 0
	end

	avoidance = dodge + parry + block + baseMissChance
	unhittable = avoidance - 102.4

	self.text:SetText(string.format(displayString, avoidance))
end

local function OnEnter(self)
	DT:SetupTooltip(self)

	if targetlv > 1 then
		GameTooltip:AddDoubleLine(L["Avoidance Breakdown"], " ("..L["lvl"].." "..targetlv..")")
	elseif targetlv == -1 then
		GameTooltip:AddDoubleLine(L["Avoidance Breakdown"], " ("..L["Boss"]..")")
	else
		GameTooltip:AddDoubleLine(L["Avoidance Breakdown"], " ("..L["lvl"].." "..playerlv..")")
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Dodge Chance"], string.format("%.2f%%", dodge), 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Parry Chance"], string.format("%.2f%%", parry), 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Block Chance"], string.format("%.2f%%", block), 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Miss Chance"], string.format("%.2f%%", baseMissChance), 1, 1, 1)
	GameTooltip:AddLine(" ")

	if unhittable > 0 then
		GameTooltip:AddDoubleLine(L["Unhittable:"], "+"..string.format("%.2f%%", unhittable), 1, 1, 1, 0, 1, 0)
	else
		GameTooltip:AddDoubleLine(L["Unhittable:"], string.format("%.2f%%", unhittable), 1, 1, 1, 1, 0, 0)
	end

	GameTooltip:Show()
end

DT:RegisterDatatext("Avoidance", {"COMBAT_RATING_UPDATE", "PLAYER_TARGET_CHANGED"}, OnEvent, nil, nil, OnEnter, nil, L["Avoidance"])
