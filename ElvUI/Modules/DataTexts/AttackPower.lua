-- Attack Power DataText -- faithful port of real ElvUI's own
-- AttackPower.lua (source/ElvUI-vanilla/ElvUI/Modules/DataTexts/
-- AttackPower.lua).

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts

local base, posBuff, negBuff = 0, 0, 0
local pwr = 0

-- Accent-coloured VALUE half -- see Armor.lua's own note on why this is a
-- rebuilt format string and not a per-update format call.
local displayString = "AP: %d"

local function ValueColorUpdate(hex)
	displayString = "AP: "..hex.."%d|r"
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

local function OnEvent(self)
	if E.myclass == "HUNTER" then
		local Rbase, RposBuff, RnegBuff = UnitRangedAttackPower("player")
		pwr = (Rbase or 0) + (RposBuff or 0) + (RnegBuff or 0)
	else
		base, posBuff, negBuff = UnitAttackPower("player")
		base, posBuff, negBuff = base or 0, posBuff or 0, negBuff or 0
		pwr = base + posBuff + negBuff
	end

	self.text:SetText(string.format(displayString, pwr))
end

local function OnEnter(self)
	DT:SetupTooltip(self)

	if E.myclass == "HUNTER" then
		GameTooltip:AddDoubleLine("Ranged Attack Power", pwr, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine("Melee Attack Power", pwr, 1, 1, 1)
	end

	GameTooltip:Show()
end

DT:RegisterDatatext("Attack Power", {"UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER"}, OnEvent, nil, nil, OnEnter, nil, "Attack Power")
