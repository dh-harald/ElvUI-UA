-- Gold DataText -- faithful port of real ElvUI's own Gold.lua
-- (source/ElvUI-vanilla/ElvUI/Modules/DataTexts/Gold.lua), assigned to
-- RightChatDataPanel by default there (a panel this project doesn't
-- build, see DataTexts.lua's own header) -- still ported since it's a
-- generic, independently-selectable widget, usable on this project's own
-- Minimap panels via config regardless of its real default location.

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts

local Profit = 0
local Spent = 0

local function OnEvent(self)
	local NewMoney = GetMoney()
	ElvDB = ElvDB or {}
	ElvDB.gold = ElvDB.gold or {}
	ElvDB.gold[E.myrealm] = ElvDB.gold[E.myrealm] or {}
	ElvDB.gold[E.myrealm][E.myname] = ElvDB.gold[E.myrealm][E.myname] or NewMoney

	ElvDB.class = ElvDB.class or {}
	ElvDB.class[E.myrealm] = ElvDB.class[E.myrealm] or {}
	ElvDB.class[E.myrealm][E.myname] = E.myclass

	local OldMoney = ElvDB.gold[E.myrealm][E.myname] or NewMoney

	local Change = NewMoney - OldMoney
	if OldMoney > NewMoney then
		Spent = Spent - Change
	else
		Profit = Profit + Change
	end

	self.text:SetText(E:FormatMoney(NewMoney, E.db.datatexts.goldFormat or "BLIZZARD"))

	ElvDB.gold[E.myrealm][E.myname] = NewMoney
end

local function OnClick(self)
	if arg1 == "RightButton" and IsShiftKeyDown() then
		ElvDB.gold = nil
		OnEvent(self)
		GameTooltip:Hide()
	else
		pcall(OpenAllBags)
	end
end

local function OnEnter(self)
	DT:SetupTooltip(self)

	local style = E.db.datatexts.goldFormat or "BLIZZARD"

	GameTooltip:AddLine(L["Session:"])
	GameTooltip:AddDoubleLine(L["Earned:"], E:FormatMoney(Profit, style), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Spent:"], E:FormatMoney(Spent, style), 1, 1, 1, 1, 1, 1)

	if Profit < Spent then
		GameTooltip:AddDoubleLine(L["Deficit:"], E:FormatMoney(Profit - Spent, style), 1, 0, 0, 1, 1, 1)
	elseif (Profit - Spent) > 0 then
		GameTooltip:AddDoubleLine(L["Profit:"], E:FormatMoney(Profit - Spent, style), 0, 1, 0, 1, 1, 1)
	end

	GameTooltip:AddLine(" ")

	if ElvDB and ElvDB.gold and ElvDB.gold[E.myrealm] then
		local totalGold = 0
		GameTooltip:AddLine(L["Character: "])

		local k
		for k in pairs(ElvDB.gold[E.myrealm]) do
			local amount = ElvDB.gold[E.myrealm][k]
			if amount then
				local class = (ElvDB.class and ElvDB.class[E.myrealm] and ElvDB.class[E.myrealm][k]) or "PRIEST"
				local color = RAID_CLASS_COLORS[class] or RAID_CLASS_COLORS.PRIEST
				GameTooltip:AddDoubleLine(k, E:FormatMoney(amount, style), color.r, color.g, color.b, 1, 1, 1)
				totalGold = totalGold + amount
			end
		end

		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Server: "])
		GameTooltip:AddDoubleLine(L["Total: "], E:FormatMoney(totalGold, style), 1, 1, 1, 1, 1, 1)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffaaaaaa"..L["Reset Data: Hold Shift + Right Click"].."|r")

	GameTooltip:Show()
end

DT:RegisterDatatext("Gold", {"PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "SEND_MAIL_MONEY_CHANGED", "SEND_MAIL_COD_CHANGED", "PLAYER_TRADE_MONEY", "TRADE_MONEY_CHANGED"}, OnEvent, nil, OnClick, OnEnter, nil, L["Gold"])
