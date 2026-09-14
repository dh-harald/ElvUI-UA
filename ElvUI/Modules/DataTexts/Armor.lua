-- Armor DataText -- faithful port of real ElvUI's own Armor.lua
-- (source/ElvUI-vanilla/ElvUI/Modules/DataTexts/Armor.lua).

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts

local effectiveArmor = 0

-- The VALUE half is painted in the UI accent colour, label left in the font
-- colour -- real ElvUI's own shape for every data text
-- (`join("", "%s: ", hex, "%d|r")`). Rebuilt from `E.valueColorUpdateFuncs`
-- rather than formatted per update, because a `|cff...|r` string cannot be
-- re-coloured once built. Starts uncoloured so a call that lands before the
-- registry is driven still prints a value.
local displayString = L["Armor"]..": %d"

local function ValueColorUpdate(hex)
	displayString = L["Armor"]..": "..hex.."%d|r"
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

local function PaperDollFrame_GetArmorReduction(armor, attackerLevel)
	local levelModifier = attackerLevel
	if levelModifier > 59 then
		levelModifier = levelModifier + (4.5 * (levelModifier - 59))
	end
	local temp = 0.1 * armor / (8.5 * levelModifier + 40)
	temp = temp / (1 + temp)

	if temp > 0.75 then return 75 end
	if temp < 0 then return 0 end

	return temp * 100
end

local function OnEvent(self)
	local _, armor = UnitArmor("player")
	effectiveArmor = armor or 0

	self.text:SetText(string.format(displayString, effectiveArmor))
end

local function OnEnter(self)
	DT:SetupTooltip(self)

	GameTooltip:AddLine(L["Mitigation By Level: "])
	GameTooltip:AddLine(" ")

	local playerLevel = UnitLevel("player") + 3
	local i
	for i = 1, 4 do
		local armorReduction = PaperDollFrame_GetArmorReduction(effectiveArmor, playerLevel)
		GameTooltip:AddDoubleLine(playerLevel, string.format("%.2f%%", armorReduction), 1, 1, 1)
		playerLevel = playerLevel - 1
	end

	local targetLevel = UnitLevel("target")
	if targetLevel and targetLevel > 0 and (targetLevel > playerLevel + 3 or targetLevel < playerLevel) then
		local armorReduction = PaperDollFrame_GetArmorReduction(effectiveArmor, targetLevel)
		GameTooltip:AddDoubleLine(targetLevel, string.format("%.2f%%", armorReduction), 1, 1, 1)
	end

	GameTooltip:Show()
end

DT:RegisterDatatext("Armor", {"UNIT_RESISTANCES"}, OnEvent, nil, nil, OnEnter, nil, L["Armor"])
