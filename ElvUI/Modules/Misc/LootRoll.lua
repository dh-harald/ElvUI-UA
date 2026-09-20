-- Misc > LootRoll -- group loot Need/Greed/Pass as one horizontal bar per item
-- under a movable holder, replacing the native GroupLootFrame1-4. Port of real
-- ElvUI's Modules/Misc/LootRoll.lua (source/ElvUI-vanilla). Switch:
-- E.private.general.lootRoll; auto-greed: E.db.general.autoRoll.
--
-- A bar shows the item icon (tooltip, Ctrl dress-up, Shift link to chat), the
-- need/greed/pass buttons with a count of the rolls other players announce in
-- chat (CHAT_MSG_LOOT, per-locale patterns), BoP/BoE, the item name, and the
-- time left as a fill in the item's quality colour. It closes on
-- CANCEL_LOOT_ROLL.
--
-- Where it differs from real ElvUI:
--   * The native window is suppressed by replacing the global
--     GroupLootFrame_OpenNewFrame, which UIParent's START_LOOT_ROLL handler
--     calls by name (FrameXML UIParent.lua), and neutering GroupLootFrame1-4's
--     Show. Real ElvUI unregisters the events from UIParent, which does not
--     take effect on UA; the unregister is still attempted for the legacy
--     client.
--   * The timer is a texture sized to the time left, not a StatusBar.
--   * A bar also closes once GetLootRollTimeLeft reports no time left, a
--     second after it opened, in case CANCEL_LOOT_ROLL does not arrive.
--   * No highlight texture on the roll buttons: on UA a highlight texture
--     renders constantly, not only on hover.
--   * Bars stack under the holder. Real ElvUI-vanilla also re-anchors each new
--     bar to the centre of the screen, which undoes its own stacking.
--   * The item tooltip is GameTooltip:SetLootRollItem(rollID); Shift-click
--     inserts into ChatFrameEditBox (1.12 has no ChatEdit_InsertLink).
--   * Event payloads are read from the arg1/arg2 globals: this project's
--     AceEvent copy passes none.
--   * The BoP/BoE label is measured and given that width on every roll, and
--     the name keeps real ElvUI's anchor on the label's right edge. Left
--     unsized, as in real ElvUI, the label's right edge is no usable anchor on
--     UA: the name started at the label's left and wrote over it. Anchoring
--     the name to the pass button instead fixes that but leaves it a few
--     pixels higher than the label.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Misc")

local find = string.find
local getn = ElvUI.Compat.getn

local FRAME_WIDTH, FRAME_HEIGHT = 328, 28
local BUTTON_SIZE = FRAME_HEIGHT - 4
local FILL_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local PASS_UP = "Interface\\AddOns\\ElvUI\\Media\\Textures\\UI-GroupLoot-Pass-Up"
local CLOSE_GRACE = 1
-- BoP/BoE label: written against a wide region so it is not truncated, then
-- trimmed to its drawn width plus a pad; the name starts a gap past it.
local LABEL_MEASURE_WIDTH = 100
local LABEL_PAD = 2
local LABEL_GAP = 4

local ROLL_NAMES = { [1] = "need", [2] = "greed", [0] = "pass" }

local locale = GetLocale()
local ROLL_PATTERNS = locale == "deDE" and {
	["(.*) würfelt nicht für: (.+|r)$"] = "pass",
	["(.*) hat für (.+) 'Gier' ausgewählt"] = "greed",
	["(.*) hat für (.+) 'Bedarf' ausgewählt"] = "need",
} or locale == "frFR" and {
	["(.*) a passé pour : (.+)"] = "pass",
	["(.*) a choisi Cupidité pour : (.+)"] = "greed",
	["(.*) a choisi Besoin pour : (.+)"] = "need",
} or locale == "zhTW" and {
	["(.*)放棄了:(.+)"] = "pass",
	["(.*)選擇了貪婪:(.+)"] = "greed",
	["(.*)選擇了需求:(.+)"] = "need",
} or locale == "ruRU" and {
	["(.*) отказывается от предмета (.+)%."] = "pass",
	["Разыгрывается: (.+)%. (.*): \"Не откажусь\""] = "greed",
	["Разыгрывается: (.+)%. (.*): \"Мне это нужно\""] = "need",
} or locale == "koKR" and {
	["(.*)님이 주사위 굴리기를 포기했습니다: (.+)"] = "pass",
	["(.*)님이 차비를 선택했습니다: (.+)"] = "greed",
	["(.*)님이 입찰을 선택했습니다: (.+)"] = "need",
} or (locale == "esES" or locale == "esMX") and {
	["^(.*) pasó de: (.+|r)$"] = "pass",
	["(.*) eligió Codicia para: (.+)"] = "greed",
	["(.*) eligió Necesidad para: (.+)"] = "need",
} or {
	["^(.*) passed on: (.+|r)$"] = "pass",
	["(.*) has selected Greed for: (.+)"] = "greed",
	["(.*) has selected Need for: (.+)"] = "need",
}

M.RollBars = M.RollBars or {}
local cancelledRolls = {}

local function CreateRollButton(bar, normal, pushed, rollType, tipText)
	local button = CreateFrame("Button", nil, bar)
	button:SetWidth(BUTTON_SIZE)
	button:SetHeight(BUTTON_SIZE)
	button:SetNormalTexture(normal)
	if pushed then button:SetPushedTexture(pushed) end

	button:SetScript("OnClick", function()
		if bar.rollID then RollOnLoot(bar.rollID, rollType) end
	end)
	button:SetScript("OnEnter", function()
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText(tipText)
		local name, choice
		for name, choice in pairs(bar.rolls) do
			if choice == ROLL_NAMES[rollType] then GameTooltip:AddLine(name, 1, 1, 1) end
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Real ElvUI's roll counts, bind text and item name: the UI font at its
	-- default size, outlined.
	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	E:FontTemplate(count, nil, nil, "OUTLINE")
	local nudge = 0
	if rollType == 2 then nudge = 1 elseif rollType == 0 then nudge = -1 end
	count:SetPoint("CENTER", button, "CENTER", 0, nudge)
	return button, count
end

local function CreateRollBar()
	local bar = CreateFrame("Frame", nil, UIParent)
	bar:SetWidth(FRAME_WIDTH)
	bar:SetHeight(FRAME_HEIGHT)
	E:SetTemplate(bar, "Default")
	bar:Hide()
	bar.rolls = {}

	bar:RegisterEvent("CANCEL_LOOT_ROLL")
	bar:SetScript("OnEvent", function()
		if not arg1 then return end
		cancelledRolls[arg1] = true
		if bar.rollID == arg1 then
			bar.rollID = nil
			bar:Hide()
		end
	end)

	local item = CreateFrame("Button", nil, bar)
	item:SetWidth(FRAME_HEIGHT - 2)
	item:SetHeight(FRAME_HEIGHT - 2)
	item:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	E:SetTemplate(item, "Default")
	local icon = item:CreateTexture(nil, "OVERLAY")
	icon:SetPoint("TOPLEFT", item, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	item.icon = icon
	-- The roll's own setter first; when it fills nothing, the item link (real
	-- ElvUI's source). Show() on a tooltip with no lines collapses it to a
	-- zero-width frame, so an empty one stays hidden.
	item:SetScript("OnEnter", function()
		if not bar.rollID then return end
		GameTooltip:SetOwner(item, "ANCHOR_TOPLEFT")
		pcall(GameTooltip.SetLootRollItem, GameTooltip, bar.rollID)
		if GameTooltip:NumLines() == 0 and bar.link then
			local _, _, itemString = find(bar.link, "(item:%d+:%d+:%d+:%d+)")
			if itemString then pcall(GameTooltip.SetHyperlink, GameTooltip, itemString) end
		end
		if GameTooltip:NumLines() > 0 then
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end)
	item:SetScript("OnLeave", function() GameTooltip:Hide() end)
	item:SetScript("OnClick", function()
		if not bar.link then return end
		if IsControlKeyDown() then
			pcall(DressUpItemLink, bar.link)
		elseif IsShiftKeyDown() and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
			ChatFrameEditBox:Insert(bar.link)
		end
	end)
	bar.item = item

	local fill = bar:CreateTexture(nil, "BORDER")
	fill:SetTexture(FILL_TEXTURE)
	fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
	fill:SetWidth(FRAME_WIDTH - 2)
	bar.fill = fill

	local spark = bar:CreateTexture(nil, "OVERLAY")
	spark:SetTexture(SPARK_TEXTURE)
	spark:SetBlendMode("ADD")
	spark:SetWidth(14)
	spark:SetHeight(FRAME_HEIGHT)
	bar.spark = spark

	local need, needCount = CreateRollButton(bar, "Interface\\Buttons\\UI-GroupLoot-Dice-Up", "Interface\\Buttons\\UI-GroupLoot-Dice-Highlight", 1, NEED)
	need:SetPoint("LEFT", item, "RIGHT", 5, -1)
	local greed, greedCount = CreateRollButton(bar, "Interface\\Buttons\\UI-GroupLoot-Coin-Up", "Interface\\Buttons\\UI-GroupLoot-Coin-Highlight", 2, GREED)
	greed:SetPoint("LEFT", need, "RIGHT", 0, -1)
	-- Pass-Up doubles as the pushed texture. On UA, Pass-Down as the pushed
	-- texture renders as a black square, and with no pushed texture the button
	-- shows nothing while held. Real ElvUI uses Pass-Down as the highlight,
	-- which is left out here.
	local pass, passCount = CreateRollButton(bar, PASS_UP, PASS_UP, 0, PASS)
	pass:SetPoint("LEFT", greed, "RIGHT", 0, 2)
	bar.counts = { need = needCount, greed = greedCount, pass = passCount }
	bar.passButton = pass

	local bind = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	E:FontTemplate(bind, nil, nil, "OUTLINE")
	bind:SetPoint("LEFT", pass, "RIGHT", 3, 1)
	bar.bind = bind

	local name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	E:FontTemplate(name, nil, nil, "OUTLINE")
	name:SetPoint("LEFT", bind, "RIGHT", 0, 0)
	name:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
	name:SetHeight(10)
	name:SetJustifyH("LEFT")
	bar.name = name

	bar:SetScript("OnUpdate", function()
		if not bar.rollID then return end
		local okLeft, left = pcall(GetLootRollTimeLeft, bar.rollID)
		left = okLeft and tonumber(left) or 0
		if left > 1000000000 or (left <= 0 and GetTime() - bar.shownAt > CLOSE_GRACE) then
			bar.rollID = nil
			bar:Hide()
			return
		end
		local width = (FRAME_WIDTH - 2) * left / bar.time
		if width < 1 then width = 1 end
		if width > FRAME_WIDTH - 2 then width = FRAME_WIDTH - 2 end
		fill:SetWidth(width)
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", bar, "LEFT", 1 + width, 0)
	end)

	return bar
end

local function GetRollBar()
	local count = getn(M.RollBars)
	local i
	for i = 1, count do
		if not M.RollBars[i].rollID then return M.RollBars[i] end
	end
	local bar = CreateRollBar()
	local anchor = M.RollHolder
	if count > 0 then anchor = M.RollBars[count] end
	bar:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
	M.RollBars[count + 1] = bar
	return bar
end

function M:START_LOOT_ROLL()
	local rollID, rollTime = arg1, tonumber(arg2)
	if not rollID or cancelledRolls[rollID] then return end

	local bar = GetRollBar()
	bar.rollID = rollID
	bar.time = (rollTime and rollTime > 0) and rollTime or 60000
	bar.shownAt = GetTime()
	local key
	for key in pairs(bar.rolls) do bar.rolls[key] = nil end
	bar.counts.need:SetText(0)
	bar.counts.greed:SetText(0)
	bar.counts.pass:SetText(0)

	local texture, name, _, quality, bindOnPickUp = GetLootRollItemInfo(rollID)
	bar.item.icon:SetTexture(texture)
	bar.link = GetLootRollItemLink(rollID)
	bar.bind:SetWidth(LABEL_MEASURE_WIDTH)
	bar.bind:SetText("")
	bar.bind:SetText(bindOnPickUp and L["BoP"] or L["BoE"])
	local bindWidth = (bar.bind:GetStringWidth() or 0) + LABEL_PAD
	bar.bind:SetWidth(bindWidth)
	if bindOnPickUp then
		bar.bind:SetTextColor(1, 0.3, 0.1)
	else
		bar.bind:SetTextColor(0.3, 1, 0.3)
	end
	bar.name:ClearAllPoints()
	bar.name:SetPoint("LEFT", bar.bind, "RIGHT", LABEL_GAP, 0)
	bar.name:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
	bar.name:SetText(name)
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		bar.fill:SetVertexColor(color.r, color.g, color.b, 0.7)
	else
		bar.fill:SetVertexColor(0.8, 0.8, 0.8, 0.7)
	end
	bar:Show()

	if E.db.general.autoRoll and UnitLevel("player") == (MAX_PLAYER_LEVEL or 60) and quality == 2 and not bindOnPickUp then
		RollOnLoot(rollID, 2)
	end
end

local function ParseRollChoice(msg)
	local pattern, choice
	for pattern, choice in pairs(ROLL_PATTERNS) do
		local _, _, playerName, itemName = find(msg, pattern)
		if locale == "ruRU" and (choice == "greed" or choice == "need") then
			playerName, itemName = itemName, playerName
		end
		if playerName and itemName and playerName ~= "Everyone" then
			return playerName, itemName, choice
		end
	end
end

function M:CHAT_MSG_LOOT()
	if type(arg1) ~= "string" then return end
	local playerName, itemName, choice = ParseRollChoice(arg1)
	if not choice then return end
	local i
	for i = 1, getn(M.RollBars) do
		local bar = M.RollBars[i]
		if bar.rollID and bar.link == itemName and not bar.rolls[playerName] then
			bar.rolls[playerName] = choice
			local text = bar.counts[choice]
			text:SetText((tonumber(text:GetText()) or 0) + 1)
			return
		end
	end
end

function M:LoadLootRoll()
	if not E.private.general.lootRoll or self.RollHolder then return end

	local holder = CreateFrame("Frame", "AlertFrameHolder", UIParent)
	holder:SetWidth(250)
	holder:SetHeight(20)
	holder:SetPoint("TOP", UIParent, "TOP", 0, -18)
	self.RollHolder = holder
	E:CreateMover(holder, "AlertFrameMover", L["Loot / Alert Frames"])

	self:RegisterEvent("START_LOOT_ROLL")
	self:RegisterEvent("CHAT_MSG_LOOT")

	pcall(UIParent.UnregisterEvent, UIParent, "START_LOOT_ROLL")
	pcall(UIParent.UnregisterEvent, UIParent, "CANCEL_LOOT_ROLL")
	GroupLootFrame_OpenNewFrame = E.noop
	local i
	for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
		local frame = _G["GroupLootFrame" .. i]
		if frame then
			pcall(frame.Hide, frame)
			frame.Show = E.noop
		end
	end
end
