-- Durability DataText -- faithful port of real ElvUI's own Durability.lua
-- (source/ElvUI-vanilla/ElvUI/Modules/DataTexts/Durability.lua).

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts
local Compat = ElvUI.Compat

local totalDurability = 100
local invDurability = {}

-- Accent-coloured VALUE half -- see Armor.lua's own note on why this is a
-- rebuilt format string and not a per-update format call.
local displayString = L["Durability"]..": %d%%"

local function ValueColorUpdate(hex)
	displayString = L["Durability"]..": "..hex.."%d%%|r"
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true
local slots = {
	"RangedSlot",
	"SecondaryHandSlot",
	"MainHandSlot",
	"FeetSlot",
	"LegsSlot",
	"HandsSlot",
	"WristSlot",
	"WaistSlot",
	"ChestSlot",
	"ShoulderSlot",
	"HeadSlot",
}

local function OnEvent(self)
	totalDurability = 100

	local i
	for i = 1, table.getn(slots) do
		local value = slots[i]
		-- Per-slot pcall: this whole eventFunc call is itself wrapped in a
		-- pcall by DataTexts.lua's AssignPanelToDataText, which silently
		-- swallows any error -- guarding per-slot means one bad slot can't
		-- block the rest, or the final SetText call below.
		local ok, current, max = pcall(function()
			local slot = GetInventorySlotInfo(value)
			return Compat.GetInventoryItemDurability(slot)
		end)

		if ok and current and max and max > 0 then
			local pct = (current / max) * 100
			invDurability[value] = pct
			if pct < totalDurability then
				totalDurability = pct
			end
		end
	end

	self.text:SetText(string.format(displayString, totalDurability))
end

local function OnClick()
	pcall(ToggleCharacter, "PaperDollFrame")
end

local function OnEnter(self)
	DT:SetupTooltip(self)

	-- Same reasoning as OnEvent above: this whole handler runs unprotected
	-- (DataTexts.lua's AssignPanelToDataText wires OnEnter with no pcall),
	-- so an error partway through the loop used to abort before
	-- GameTooltip:Show() ever ran -- leaving no visible tooltip at all, not
	-- even a blank one. Guarded per-slot so Show() always fires.
	local slot, durability
	for slot, durability in pairs(invDurability) do
		local ok, r, g, b = pcall(E.ColorGradient, E, durability * 0.01, 1, 0, 0, 1, 1, 0, 0, 1, 0)
		if ok then
			local label = _G[string.upper(slot)] or slot
			GameTooltip:AddDoubleLine(label, string.format("%d%%", durability), 1, 1, 1, r, g, b)
		end
	end

	GameTooltip:Show()
end

DT:RegisterDatatext("Durability", {"PLAYER_LOGIN", "UPDATE_INVENTORY_ALERTS", "MERCHANT_SHOW"}, OnEvent, nil, OnClick, OnEnter, nil, L["Durability"])
