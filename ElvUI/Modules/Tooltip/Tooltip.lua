-- Tooltip module -- port of real ElvUI's Modules/Tooltip/Tooltip.lua
-- (ElvUI-vanilla/), rebuilt around hook points that work on both
-- clients.
--
-- Real ElvUI drives the unit rewrite from SecureHook(GameTooltip, "SetUnit")
-- and its item additions from the other GameTooltip setters. On UA none of
-- GameTooltip's content setters can be hooked: neither AceHook's
-- object+method SecureHook nor replacing the method takes effect
-- (UnrealUI/modules/itemprice.lua measured a replaced setter never
-- running). This file uses only:
--   * UPDATE_MOUSEOVER_UNIT for world units. Measured on UA: it fires on
--     every mouseover-unit change, including a sweep between two overlapping
--     NPC models where GameTooltip never hides (so its OnShow does not fire),
--     and GameTooltip is already filled with the new unit when it arrives.
--   * a direct call from UnitFrames' own ShowUnitTooltip for frame units.
--   * a post-hook on the GameTooltip_SetDefaultAnchor global for placement.
--     Measured on UA: the client calls it for world units, unit frames and
--     action buttons alike, BEFORE the tooltip is filled, and a position set
--     there holds -- but for world units only while GameTooltip has NO
--     OnTooltipSetDefaultAnchor handler (UA ships none; a handler replaces the
--     global call). Never set that script. Bag items call SetOwner directly
--     and are not placed here, same as in real ElvUI.
--   * a post-hook on the SetItemRef global, measured on UA to be called
--     through the Lua global on a chat link click.
--   * a per-frame re-check while GameTooltip is shown (TT:HookRefill). On UA
--     the client re-fills a shown unit tooltip's text in combat with no
--     event, OnShow or status bar change reliably marking it.
--
-- Item tooltips get sell price, item count and item id lines (TT:AddItemLines)
-- from GameTooltip setter wrappers on the legacy client and from per-surface
-- hover hooks on UA -- see "Item hover sources". The same item, while Shift is
-- held, gets the equipped item(s) of its slot shown beside GameTooltip -- see
-- "Item comparison".
--
-- Visibility (TT:IsSuppressed / TT:ApplyVisibility) hides a tooltip by owner
-- category unless the chosen modifier is held, or always while in combat:
--   * unitFrames: checked by UnitFrames' own ShowUnitTooltip before it fills
--     the tooltip. Its 0.25s refresh re-checks, so pressing or releasing the
--     modifier over a unit frame shows or hides the tooltip on both clients.
--   * bags: the bag and bank hover post-hooks, on both clients. While the
--     cursor stays on the item, pressing or releasing the modifier shows or
--     hides the tooltip (TT:OnModifierStateChanged, LibModifierState-1.0).
--   * actionbars and combat for default-anchored tooltips: the
--     GameTooltip_SetDefaultAnchor post-hook, which also remembers the owner.
--     Measured: a Hide there holds on the legacy client, but not on UA, where
--     the client shows the tooltip after filling it. On UA the check runs
--     again from GameTooltip's OnShow for the remembered owner (a Hide there
--     holds, measured), and from UPDATE_MOUSEOVER_UNIT for combat, which also
--     covers the sweep between two overlapping NPCs where OnShow does not
--     fire. Action and pet buttons get the same live modifier toggle as bag
--     items.
--
-- Profile keys read: cursorAnchor, targetInfo, playerTitles, guildRanks,
-- spellID, itemPrice, itemCount, useCustomFactionColors, factionColors,
-- healthBar.{text, height,
-- font, fontSize, fontOutline, statusPosition},
-- visibility.{actionbars, bags, unitFrames, combat}; colorAlpha is read by the
-- tooltip skin; private: enable. The rest of P.tooltip is declared for
-- profile compatibility only.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local TT = E:NewModule("Tooltip", "AceHook-3.0", "AceEvent-3.0")

local getn = ElvUI.Compat.getn
local format = string.format
local find = string.find

local LMS = LibStub("LibModifierState-1.0", true)

local TAPPED_COLOR = { r = 0.6, g = 0.6, b = 0.6 }
local WHITE = { r = 1, g = 1, b = 1 }

-- Global strings with their 1.12.1 GlobalStrings.lua values as fallback; the
-- UA Lua API docs do not cover GlobalStrings.
local LEVEL_TEXT = LEVEL or L["Level"]
local PVP_TEXT = HELPFRAME_HOME_ISSUE3_HEADER or "PvP"
local TARGET_TEXT = TARGET or L["Target"]
local ID_TEXT = ID or "ID"

local CLASSIFICATION = {
	worldboss = format("|cffAF5050 %s|r", BOSS or L["Boss"]),
	rareelite = format("|cffAF5050+ %s|r", ITEM_QUALITY3_DESC or L["Rare"]),
	elite = "|cffAF5050+|r",
	rare = format("|cffAF5050 %s|r", ITEM_QUALITY3_DESC or L["Rare"]),
}

-- Real 1.12.1 FrameXML QuestDifficultyColor values (QuestLogFrame.lua), kept
-- locally: that table and GetDifficultyColor are FrameXML-side and not part
-- of UA's documented API.
local DIFFICULTY_COLORS = {
	impossible = { r = 1.00, g = 0.10, b = 0.10 },
	verydifficult = { r = 1.00, g = 0.50, b = 0.25 },
	difficult = { r = 1.00, g = 1.00, b = 0.00 },
	standard = { r = 0.25, g = 0.75, b = 0.25 },
	trivial = { r = 0.50, g = 0.50, b = 0.50 },
}

local function GetDifficultyColor(level)
	-- A level of 0 or less is the client's "??" level: the most dangerous case.
	if not level or level <= 0 then return DIFFICULTY_COLORS.impossible end

	local diff = level - (UnitLevel("player") or 1)
	if diff >= 5 then
		return DIFFICULTY_COLORS.impossible
	elseif diff >= 3 then
		return DIFFICULTY_COLORS.verydifficult
	elseif diff >= -2 then
		return DIFFICULTY_COLORS.difficult
	end

	local greenRange = 0
	if type(GetQuestGreenRange) == "function" then
		greenRange = GetQuestGreenRange() or 0
	end
	if -diff <= greenRange then
		return DIFFICULTY_COLORS.standard
	end
	return DIFFICULTY_COLORS.trivial
end

local function Hex(color)
	return E:RGBToHex(color.r, color.g, color.b)
end

local function ClassColor(class)
	local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	return class and colors and colors[class]
end

-- Plain UnitReaction, as in real ElvUI: it reports the player's standing with
-- the unit's faction, so an NPC of a faction the player is only Neutral with
-- is coloured neutral even when UnitIsFriend() is true.
-- FACTION_BAR_COLORS can be missing on UA; the profile palette carries real
-- ElvUI's defaults for all eight standings and stands in for it.
local function ReactionColor(unit)
	local reaction = UnitReaction(unit, "player")
	if not reaction then return nil end

	local db = TT.db
	if not db.useCustomFactionColors and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction] then
		return FACTION_BAR_COLORS[reaction]
	end
	return db.factionColors[reaction]
end

-- ---------------------------------------------------------------------------
-- Tooltip line helpers
--
-- Real ElvUI hides unwanted lines in place. On a GameTooltip, NumLines()
-- stops at the first hidden left line and AddLine() fills the first unused
-- index (UA GameTooltip docs), so a hidden line in the middle would cut off
-- everything below it. Lines are shifted instead, keeping the shown block
-- contiguous.
-- ---------------------------------------------------------------------------

local function LeftText(i)
	return _G["GameTooltipTextLeft" .. i]
end

local function RightText(i)
	return _G["GameTooltipTextRight" .. i]
end

local function CopyFontString(dst, src)
	dst:SetText(src:GetText() or "")
	local r, g, b = src:GetTextColor()
	if r then dst:SetTextColor(r, g, b) end
	if src:IsShown() then dst:Show() else dst:Hide() end
end

local function RemoveLine(tt, index)
	local n = tt:NumLines()
	if index < 1 or index > n then return end

	local i
	for i = index, n - 1 do
		CopyFontString(LeftText(i), LeftText(i + 1))
		CopyFontString(RightText(i), RightText(i + 1))
	end
	LeftText(n):SetText("")
	LeftText(n):Hide()
	RightText(n):Hide()
end

local function InsertLine(tt, index, text)
	local before = tt:NumLines()
	tt:AddLine(" ")
	local n = tt:NumLines()
	-- AddLine does nothing once every line slot is in use.
	if n == before or index > n then return end

	local i
	for i = n, index + 1, -1 do
		CopyFontString(LeftText(i), LeftText(i - 1))
		CopyFontString(RightText(i), RightText(i - 1))
	end
	LeftText(index):SetText(text)
	LeftText(index):SetTextColor(1, 1, 1)
	LeftText(index):Show()
	RightText(index):Hide()
end

local function FindLine(tt, fromIndex, needle)
	local i
	for i = fromIndex, tt:NumLines() do
		local text = LeftText(i):GetText()
		if text and find(text, needle, 1, true) then
			return i
		end
	end
end

local function RemoveTrashLines(tt)
	local i
	for i = tt:NumLines(), 2, -1 do
		local text = LeftText(i):GetText()
		if text == PVP_TEXT or text == FACTION_ALLIANCE or text == FACTION_HORDE then
			RemoveLine(tt, i)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Unit tooltip rewrite
-- ---------------------------------------------------------------------------

local function UpdatePlayerLines(tt, unit, db, name, level, levelText)
	local localeClass, class = UnitClass(unit)
	local color = ClassColor(class)

	local displayName = name
	if db.playerTitles then
		displayName = UnitPVPName(unit) or name
	end
	LeftText(1):SetText(Hex(color or WHITE) .. displayName)

	local guildName, guildRank = GetGuildInfo(unit)
	if guildName and guildName ~= "" then
		local guildText
		-- UA returns "" as the rank name when it is unknown to the client.
		if db.guildRanks and guildRank and guildRank ~= "" then
			guildText = format("<|cff00ff10%s|r> [|cff00ff10%s|r]", guildName, guildRank)
		else
			guildText = format("<|cff00ff10%s|r>", guildName)
		end

		local guildLine = FindLine(tt, 2, guildName)
		if guildLine then
			LeftText(guildLine):SetText(guildText)
		else
			InsertLine(tt, 2, guildText)
		end
	end

	local levelLine = FindLine(tt, 2, LEVEL_TEXT)
	if levelLine then
		local diff = GetDifficultyColor(level)
		LeftText(levelLine):SetText(format("%s%s|r %s %s%s|r",
			Hex(diff), levelText, UnitRace(unit) or "", Hex(color or WHITE), localeClass or ""))
		LeftText(levelLine):SetTextColor(1, 1, 1)
	end

	return color
end

local function UpdateCreatureLines(tt, unit, name, level, levelText)
	local color
	if UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit) then
		color = TAPPED_COLOR
	else
		color = ReactionColor(unit)
	end
	LeftText(1):SetText(Hex(color or WHITE) .. name)

	local levelLine = FindLine(tt, 2, LEVEL_TEXT)
	if levelLine then
		local diff = GetDifficultyColor(level)
		local pvpFlag = ""
		if UnitIsPVP(unit) then
			pvpFlag = format(" (%s)", PVP_TEXT)
		end
		LeftText(levelLine):SetText(format("%s%s|r%s %s%s",
			Hex(diff), levelText, CLASSIFICATION[UnitClassification(unit)] or "",
			UnitCreatureType(unit) or "", pvpFlag))
		LeftText(levelLine):SetTextColor(1, 1, 1)
	end

	return color
end

-- The unit token for `unit`'s own target. UA resolves "targettarget" but not
-- other "<unit>target" chains ("mouseovertarget", "pettarget" return no unit
-- there, measured), so a hovered unit that is also the player's target falls
-- back to "targettarget". Any other hovered unit's target is unknown on UA.
local function UnitTargetToken(unit)
	local token = unit .. "target"
	if UnitExists(token) then return token end
	if UnitIsUnit(unit, "target") and UnitExists("targettarget") then
		return "targettarget"
	end
end

local function AddTargetLines(tt, unit)
	local unitTarget = UnitTargetToken(unit)
	if unitTarget then
		local targetColor
		if UnitIsPlayer(unitTarget) then
			local _, class = UnitClass(unitTarget)
			targetColor = ClassColor(class)
		else
			targetColor = ReactionColor(unitTarget)
		end
		tt:AddDoubleLine(format("%s:", TARGET_TEXT),
			format("%s%s|r", Hex(targetColor or WHITE), UnitName(unitTarget) or ""))
	end

	local numRaid = GetNumRaidMembers() or 0
	local numParty = GetNumPartyMembers() or 0
	if numRaid == 0 and numParty == 0 then return end

	local list = {}
	local count = numRaid > 0 and numRaid or numParty
	local i
	for i = 1, count do
		local groupUnit = numRaid > 0 and ("raid" .. i) or ("party" .. i)
		if UnitIsUnit(groupUnit .. "target", unit) and not UnitIsUnit(groupUnit, "player") then
			local _, class = UnitClass(groupUnit)
			table.insert(list, Hex(ClassColor(class) or WHITE) .. (UnitName(groupUnit) or "") .. "|r")
		end
	end

	local numList = getn(list)
	if numList > 0 then
		tt:AddLine(format("%s (|cffffffff%d|r): %s", L["Targeted By:"], numList, table.concat(list, ", ")), nil, nil, nil, true)
	end
end

-- Rewrites GameTooltip in place after the client filled it for `unit`.
--
-- UPDATE_MOUSEOVER_UNIT and a unit frame's own call can both reach the same
-- fill, and the lines added here must not be added twice. The colour escapes
-- written below cannot mark a fill as done: on UA FontString:GetText()
-- returns the text with its escapes stripped, so a rewritten name reads back
-- exactly like the native one. The level line is the marker instead -- the
-- native fill writes the LEVEL word, the rewrite drops it. No level line left
-- AND an unchanged line count mean this fill is already done.
function TT:UpdateUnitTooltip(unit)
	local tt = GameTooltip
	if not unit or not tt or not tt:IsShown() or not UnitExists(unit) then return end

	local name = UnitName(unit)
	local current = LeftText(1):GetText()
	if not name or not current or not find(current, name, 1, true) then return end
	self.currentUnit = unit
	if not FindLine(tt, 2, LEVEL_TEXT) and tt:NumLines() == self.lastNumLines then return end

	local db = self.db
	local level = UnitLevel(unit) or 0
	local levelText = level > 0 and level or "??"

	RemoveTrashLines(tt)

	local color
	if UnitIsPlayer(unit) then
		color = UpdatePlayerLines(tt, unit, db, name, level, levelText)
	else
		color = UpdateCreatureLines(tt, unit, name, level, levelText)
	end

	if db.targetInfo and not UnitIsUnit(unit, "player") then
		AddTargetLines(tt, unit)
	end

	local bar = GameTooltipStatusBar
	if bar then
		local c = color or TAPPED_COLOR
		bar:SetStatusBarColor(c.r, c.g, c.b)
	end

	-- A FontString:SetText on a shown tooltip does not resize it on UA, and
	-- Show() on an already shown tooltip does not either (a longer rewritten
	-- line came out truncated to "..."). A changed SetMinimumWidth value
	-- re-runs the layout immediately (measured on UA; ClearLines resets it to
	-- 0 on every fill), so it is stepped to 1 and back to 0 to leave no
	-- minimum behind. Show() is kept for the legacy client, which re-lays out
	-- on it.
	tt:SetMinimumWidth(1)
	tt:SetMinimumWidth(0)
	tt:Show()

	self.lastNumLines = tt:NumLines()
	self:UpdateHealthText()
end

-- ---------------------------------------------------------------------------
-- Health bar
-- ---------------------------------------------------------------------------

local DEAD_TEXT = DEAD or L["Dead"]

-- The native bar hangs 2 units in and 1 unit below the frame's bottom edge
-- (GameTooltipTemplate, the same measured on UA). With the tooltip skin the
-- visible body ends 4 units inside the frame (its border), so the bar moves
-- 5 units in and 2 units up to sit one unit below that border, its own
-- 1-unit backdrop included. statusPosition "TOP" mirrors it above.
function TT:AnchorHealthBar()
	local bar, tt = GameTooltipStatusBar, GameTooltip
	if not bar or not tt then return end

	local skins = E.private.skins and E.private.skins.blizzard
	local skinned = skins and skins.enable and skins.tooltip
	local x = skinned and 5 or 2
	local y = skinned and 2 or -1

	pcall(bar.ClearAllPoints, bar)
	if self.db.healthBar.statusPosition == "TOP" then
		pcall(bar.SetPoint, bar, "BOTTOMLEFT", tt, "TOPLEFT", x, -y)
		pcall(bar.SetPoint, bar, "BOTTOMRIGHT", tt, "TOPRIGHT", -x, -y)
	else
		pcall(bar.SetPoint, bar, "TOPLEFT", tt, "BOTTOMLEFT", x, y)
		pcall(bar.SetPoint, bar, "TOPRIGHT", tt, "BOTTOMRIGHT", -x, y)
	end
end

-- The text is read from ElvUI.Util.UnitHealth (UnitHealth/UnitHealthMax, or
-- the LibMobHealth-4.0 estimate for hostile units) of the unit last rewritten,
-- not from the bar: on UA the bar's own GetValue/GetMinMaxValues report a
-- fixed 0-100 range (UnrealUI/modules/tooltip.lua). It is anchored by a
-- single CENTER point, because FontString:SetJustifyV does nothing on UA.
-- SetFont is a no-op on UA and applies on the legacy client.
function TT:SetupHealthBar()
	local bar = GameTooltipStatusBar
	if not bar then return end

	local holder = CreateFrame("Frame", nil, bar)
	holder:SetAllPoints(bar)

	local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER", bar, "CENTER", 0, 0)
	self.healthText = text

	self:ApplyHealthBarSettings()
end

-- Height, position and font of the health bar from E.db.tooltip.healthBar;
-- called again by the options page so a change applies without a reload.
function TT:ApplyHealthBarSettings()
	local bar = GameTooltipStatusBar
	if not bar then return end
	local db = self.db.healthBar

	pcall(bar.SetHeight, bar, db.height)
	self:AnchorHealthBar()

	local text = self.healthText
	if not text then return end

	local LSM = LibStub("LibSharedMedia-3.0", true)
	local path = LSM and LSM:Fetch("font", db.font)
	if path then
		local outline = db.fontOutline
		if outline == "NONE" then outline = "" end
		pcall(text.SetFont, text, path, db.fontSize, outline)
	end

	self.lastHealthText = nil
	self:UpdateHealthText()
end

function TT:UpdateHealthText()
	local text = self.healthText
	if not text then return end

	local unit = self.currentUnit
	local value = ""
	if unit and self.db.healthBar.text and UnitExists(unit) then
		local cur, max = ElvUI.Util.UnitHealth(unit)
		cur, max = cur or 0, max or 0
		if cur <= 0 then
			value = DEAD_TEXT
		elseif max > 0 then
			value = E:ShortValue(cur) .. " / " .. E:ShortValue(max)
		end
	end

	if value ~= self.lastHealthText then
		text:SetText(value)
		self.lastHealthText = value
	end
end

-- ---------------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------------

local function ScreenQuadrant(frame)
	local ok, x, y = pcall(frame.GetCenter, frame)
	if not ok or not x or not y then return "BOTTOMRIGHT" end

	local vertical = (y > UIParent:GetHeight() / 2) and "TOP" or "BOTTOM"
	local horizontal = (x > UIParent:GetWidth() / 2) and "RIGHT" or "LEFT"
	return vertical .. horizontal
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

local MODIFIER_GETTERS = {
	SHIFT = "IsShiftKeyDown",
	CTRL = "IsControlKeyDown",
	ALT = "IsAltKeyDown",
}

-- Owner name pattern -> hover kind, checked in order: "^PetActionButton%d"
-- comes before "ActionButton%d", which also matches BonusActionButton.
local OWNER_PATTERNS = {
	{ "^PetActionButton%d", "pet" },
	{ "^ShapeshiftButton%d", "stance" },
	{ "ActionButton%d", "action" },
	{ "^MultiBar%a+Button%d", "action" },
}

local KIND_CATEGORY = {
	bag = "bags",
	bank = "bags",
	action = "actionbars",
	pet = "actionbars",
	stance = "actionbars",
}

local function OwnerKind(owner)
	if not owner or type(owner.GetName) ~= "function" then return nil end
	local ok, name = pcall(owner.GetName, owner)
	if not ok or type(name) ~= "string" then return nil end

	local i
	for i = 1, getn(OWNER_PATTERNS) do
		if find(name, OWNER_PATTERNS[i][1]) then
			return OWNER_PATTERNS[i][2]
		end
	end
	return nil
end

-- True when the tooltip of `category` ("actionbars", "bags", "unitFrames", or
-- nil for no category) must not show right now. A mode is "NONE" (never
-- hide), "ALL" (always hide) or a modifier the user must hold to see it.
-- The key getters return 1/nil on the legacy client, true/false on UA.
function TT:IsSuppressed(category)
	local visibility = self.db and self.db.visibility
	if not visibility then return false end

	if visibility.combat and UnitAffectingCombat("player") then
		return true
	end

	local mode = category and visibility[category]
	if not mode or mode == "NONE" then return false end
	if mode == "ALL" then return true end

	local getter = MODIFIER_GETTERS[mode] and _G[MODIFIER_GETTERS[mode]]
	if type(getter) ~= "function" then return false end
	if getter() then return false end
	return true
end

function TT:ApplyVisibility(tt, category)
	if not tt or not self:IsSuppressed(category) then return false end
	pcall(tt.Hide, tt)
	return true
end

-- UA only: the client shows a default-anchored tooltip after filling it, so a
-- Hide from the anchor hook does not hold there. GameTooltip's OnShow runs
-- after the fill, and a Hide from it holds (measured); it re-checks the owner
-- the anchor hook remembered, if that owner still owns the tooltip.
function TT:OnTooltipShow()
	local owner = self.anchorOwner
	if not owner then return end
	local okOwned, owned = pcall(GameTooltip.IsOwned, GameTooltip, owner)
	if not okOwned or not owned then return end
	self:ApplyVisibility(GameTooltip, KIND_CATEGORY[OwnerKind(owner)])
end

-- Live modifier toggle for bag, bank, action and pet button tooltips. The
-- hover hooks remember the hovered button and its kind; while that kind's
-- visibility mode waits on a modifier, a LibModifierState-1.0 callback shows
-- the tooltip when the modifier goes down and hides it when it goes up, as
-- long as the cursor is still on that button. The cursor test is geometric
-- (FrameXML's MouseIsOver) because no leave signal reaches these hooks, so
-- the remembered button outlives the hover (measured: without the test, a
-- modifier press after leaving re-showed the old item's tooltip).
--
-- A button is re-shown through the Lua global its XML handler calls, which
-- runs the native fill and this module's hooks again: RESHOW_GLOBALS below.
-- GetScript("OnEnter") is no alternative: it returns nil for XML-defined
-- buttons on UA (measured). A bank item has no such global (its handler is
-- inline XML), so its native fill is repeated here; stance buttons (inline
-- XML as well) get no live toggle.
--
-- Known gap on UA: on pet COMMAND buttons (Attack, Follow, Stay, Aggressive,
-- Defensive, Passive) the live toggle only works when the cursor arrived on
-- the button with the modifier already held; arriving without it, a later
-- modifier press shows nothing. The pet spell buttons are not affected.

local function IsModifierMode(mode)
	return mode ~= nil and MODIFIER_GETTERS[mode] ~= nil
end

local function CursorOver(frame)
	if not frame:IsVisible() then return false end
	local x, y = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	if not x or not y or not scale or scale == 0 then return false end
	x = x / scale
	y = y / scale

	local left, right = frame:GetLeft(), frame:GetRight()
	local top, bottom = frame:GetTop(), frame:GetBottom()
	if not left or not right or not top or not bottom then return false end
	return x >= left and x <= right and y >= bottom and y <= top
end

function TT:TrackHover(button, kind)
	self.hoverButton = button
	self.hoverKind = kind

	local visibility = self.db and self.db.visibility
	if LMS and not self.modifierTracking and visibility and IsModifierMode(visibility[KIND_CATEGORY[kind]]) then
		LMS.RegisterCallback(self, "MODIFIER_STATE_CHANGED", "OnModifierStateChanged")
		self.modifierTracking = true
	end
end

function TT:StopHoverTracking()
	self.hoverButton = nil
	self.hoverKind = nil
	if LMS and self.modifierTracking then
		LMS.UnregisterCallback(self, "MODIFIER_STATE_CHANGED")
		self.modifierTracking = nil
	end
end

local RESHOW_GLOBALS = {
	bag = "ContainerFrameItemButton_OnEnter",
	action = "ActionButton_SetTooltip",
	pet = "PetActionButton_OnEnter",
}

function TT:ReshowHover(button, kind)
	local globalName = RESHOW_GLOBALS[kind]
	if globalName then
		local handler = _G[globalName]
		if type(handler) ~= "function" then return end
		local previous = this
		this = button
		pcall(handler, button)
		this = previous
		return
	end
	if kind ~= "bank" then return end

	local okSlot, slot = pcall(BankButtonIDToInvSlotID, button:GetID())
	if not okSlot or not slot then return end
	pcall(GameTooltip.SetOwner, GameTooltip, button, "ANCHOR_RIGHT")
	pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", slot)
	pcall(GameTooltip.Show, GameTooltip)
	pcall(TT.OnBankItemEnter, TT, button)
end

function TT:OnModifierStateChanged()
	local button, kind = self.hoverButton, self.hoverKind
	local category = KIND_CATEGORY[kind]
	local visibility = self.db and self.db.visibility
	local okOver, over = false, false
	if button then
		okOver, over = pcall(CursorOver, button)
	end
	if not okOver or not over or not visibility or not category or not IsModifierMode(visibility[category]) then
		self:StopHoverTracking()
		return
	end

	if self:IsSuppressed(category) then
		local okOwned, owned = pcall(GameTooltip.IsOwned, GameTooltip, button)
		if GameTooltip:IsShown() and (not okOwned or owned) then
			pcall(GameTooltip.Hide, GameTooltip)
		end
	elseif not GameTooltip:IsShown() then
		self:ReshowHover(button, kind)
	end
end

-- ---------------------------------------------------------------------------
-- Default anchor
-- ---------------------------------------------------------------------------

function TT:SetDefaultAnchor(tt, parent)
	if not tt then return end

	local ok, anchorType = pcall(tt.GetAnchorType, tt)
	if ok and anchorType and anchorType ~= "ANCHOR_NONE" then return end

	local kind = OwnerKind(parent)
	if tt == GameTooltip then
		self.anchorOwner = parent
		if kind and kind ~= "stance" then
			self:TrackHover(parent, kind)
		end
	end
	if self:ApplyVisibility(tt, KIND_CATEGORY[kind]) then return end

	if parent and self.db.cursorAnchor then
		tt:SetOwner(parent, "ANCHOR_CURSOR")
		return
	end

	tt:ClearAllPoints()

	if not E.db.movers.TooltipMover then
		local bags = _G.ElvUI_ContainerFrame
		local chat = _G.RightChatPanel
		if bags and bags:IsShown() then
			tt:SetPoint("BOTTOMRIGHT", bags, "TOPRIGHT", 0, 18)
		elseif chat and chat:IsShown() and chat:GetAlpha() == 1 then
			tt:SetPoint("BOTTOMRIGHT", chat, "TOPRIGHT", 0, 18)
		elseif chat then
			tt:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT", 0, 18)
		else
			tt:SetPoint("BOTTOMRIGHT", self.anchor, "BOTTOMRIGHT", 0, 0)
		end
	else
		local point = ScreenQuadrant(self.anchor)
		tt:SetPoint(point, self.anchor, point, 0, 0)
	end
end

local function CreateAnchor()
	local anchor = CreateFrame("Frame", "ElvUI_TooltipAnchor", UIParent)
	anchor:SetWidth(130)
	anchor:SetHeight(20)

	local chat = _G.RightChatPanel
	if chat then
		anchor:SetPoint("BOTTOMRIGHT", chat, "TOPRIGHT", 0, 18)
	else
		anchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 18)
	end
	return anchor
end

-- ---------------------------------------------------------------------------
-- Item extras: sell price, item count, item id
-- ---------------------------------------------------------------------------

local function StripEscapes(text)
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	return text
end

local ID_PREFIX = ID_TEXT .. " "

local function IsIDLine(text)
	if not text then return false end
	text = StripEscapes(text)
	local prefixLength = string.len(ID_PREFIX)
	return string.sub(text, 1, prefixLength) == ID_PREFIX
		and find(string.sub(text, prefixLength + 1), "^%d+$") ~= nil
end

local BANK_KEY = BANK_CONTAINER or -1

-- True for a line this module appends to an item tooltip. Compared on
-- escape-stripped text: on UA FontString:GetText() returns it without colour
-- escapes, the legacy client returns them.
local function IsExtraLine(text)
	if not text then return false end
	if IsIDLine(text) then return true end
	text = StripEscapes(text)
	return text == L["Sell Price:"] or text == L["Count"] or text == L["Bank"]
end

-- Hides every appended line at the end of `tip`. A repeated fill of an open
-- tooltip (a chat link clicked again; on UA a setter refilling the item's own
-- lines) leaves the lines added after them in place. Only trailing lines are
-- hidden: NumLines() stops at the first hidden line, so hiding from the end
-- keeps the rest intact.
local function StripTrailingExtras(tip)
	local name = tip:GetName()
	if not name then return end

	local n = tip:NumLines()
	while n > 1 do
		local left = _G[name .. "TextLeft" .. n]
		if not left or not IsExtraLine(left:GetText()) then break end
		left:SetText("")
		left:Hide()
		local right = _G[name .. "TextRight" .. n]
		if right then right:Hide() end
		n = n - 1
	end
end

-- Number of `id` in one container, read from the container API: GetItemCount
-- exists on neither client. Bank containers report no links until the client
-- holds the bank's contents.
local function CountInBag(bag, id)
	local total = 0
	local slots = GetContainerNumSlots(bag) or 0
	local slot
	for slot = 1, slots do
		local link = GetContainerItemLink(bag, slot)
		if link then
			local _, _, linkId = find(link, "item:(%d+)")
			if tonumber(linkId) == id then
				local _, count = GetContainerItemInfo(bag, slot)
				total = total + (tonumber(count) or 1)
			end
		end
	end
	return total
end

local function CountItem(id, withBags, withBank)
	local bags, bank = 0, 0
	local bag
	if withBags then
		for bag = 0, NUM_BAG_SLOTS or 4 do
			bags = bags + CountInBag(bag, id)
		end
	end
	if withBank then
		bank = CountInBag(BANK_KEY, id)
		local first = (NUM_BAG_SLOTS or 4) + 1
		for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do
			bank = bank + CountInBag(bag, id)
		end
	end
	return bags, bank
end

-- Appends sell price, item count and item id (real ElvUI's itemPrice,
-- itemCount, spellID) to an item tooltip the client has just filled for
-- `link`. The price is skipped while a merchant window is open, as in real
-- ElvUI: the client shows the sale price there itself. Prices come from
-- LibItemPrice-1.1 by numeric id; no price API exists on either client.
--
-- Only a shown tooltip is touched: addons also fill a hidden GameTooltip to
-- read item text, and appending there would show it.
function TT:AddItemLines(tip, link, count)
	if not tip or type(link) ~= "string" or not tip:IsShown() then return end
	local _, _, idText = find(link, "item:(%d+)")
	local id = tonumber(idText)
	if not id then return end

	StripTrailingExtras(tip)

	local db = self.db
	local added = false

	if db.itemPrice and not (MerchantFrame and MerchantFrame:IsShown()) then
		local LIP = LibStub("ItemPrice-1.1", true)
		local price = LIP and LIP:GetPriceById(id)
		if price and price > 0 then
			-- Our own string, not the client's SALE_PRICE_COLON ("Sale Price:").
			tip:AddDoubleLine(L["Sell Price:"], E:FormatMoney(price * (tonumber(count) or 1), "BLIZZARD"),
				nil, nil, nil, 1, 1, 1)
			added = true
		end
	end

	local mode = db.itemCount
	if mode == "BAGS_ONLY" or mode == "BANK_ONLY" or mode == "BOTH" then
		local bags, bank = CountItem(id, mode ~= "BANK_ONLY", mode ~= "BAGS_ONLY")
		if mode == "BAGS_ONLY" and bags > 0 then
			tip:AddDoubleLine(L["Count"], tostring(bags), nil, nil, nil, 1, 1, 1)
			added = true
		elseif mode == "BANK_ONLY" and bank > 0 then
			tip:AddDoubleLine(L["Bank"], tostring(bank), nil, nil, nil, 1, 1, 1)
			added = true
		elseif mode == "BOTH" and bags + bank > 0 then
			tip:AddDoubleLine(L["Count"], format("%d (%d)", bags, bank), nil, nil, nil, 1, 1, 1)
			added = true
		end
	end

	if db.spellID then
		tip:AddLine(format("|cFFCA3C3C%s|r %d", ID_TEXT, id))
		added = true
	end

	-- AddLine re-runs the layout of a shown tooltip on UA; Show() does it on
	-- the legacy client.
	if added then
		tip:Show()
	end
end

-- For a hover path that is not a GameTooltip setter (our own loot slots).
-- Skipped where the setters are hooked, which already covered that fill.
function TT:AddItemLinesForSurface(tip, link, count)
	if self.itemSettersHooked then return end
	self:AddItemLines(tip, link, count)
	self:SetCompareItem(link)
end

-- FrameXML's SetItemRef inserts the link into the edit box on Shift and opens
-- the dressing room on Ctrl, showing no tooltip in either case.
function TT:SetItemRef(link)
	if type(link) ~= "string" then return end
	if IsShiftKeyDown() or IsControlKeyDown() then return end

	local tip = _G.ItemRefTooltip
	if not tip or not tip:IsShown() then return end

	self:AddItemLines(tip, link, 1)
end

-- ---------------------------------------------------------------------------
-- Item comparison
--
-- While Shift is held over an equippable item, the equipped item of each
-- matching slot is shown in ShoppingTooltip1/2 beside GameTooltip; rings and
-- trinkets show both slots. The 1.12 client has no such comparison for bag
-- items (only the Auction House fills these frames natively), and real ElvUI
-- relies on the retail client's own. This follows pfUI's eqcompare, with
-- UnrealUI's INVTYPE -> slot map. Each comparison frame closes with the stat
-- change replacing that equipped piece would make (see "Stat difference").
--
-- The hovered item is the one GameTooltip's item lines were added for (see
-- "Item hover sources"). It is remembered until GameTooltip hides, so pressing
-- or releasing Shift while the tooltip stays up shows or hides the comparison;
-- LibModifierState-1.0 is subscribed only while an item is remembered.
-- ---------------------------------------------------------------------------

local COMPARE_SLOTS = {
	INVTYPE_HEAD = { "HeadSlot" },
	INVTYPE_NECK = { "NeckSlot" },
	INVTYPE_SHOULDER = { "ShoulderSlot" },
	INVTYPE_BODY = { "ShirtSlot" },
	INVTYPE_CHEST = { "ChestSlot" },
	INVTYPE_ROBE = { "ChestSlot" },
	INVTYPE_WAIST = { "WaistSlot" },
	INVTYPE_LEGS = { "LegsSlot" },
	INVTYPE_FEET = { "FeetSlot" },
	INVTYPE_WRIST = { "WristSlot" },
	INVTYPE_HAND = { "HandsSlot" },
	INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
	INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
	INVTYPE_CLOAK = { "BackSlot" },
	INVTYPE_WEAPON = { "MainHandSlot", "SecondaryHandSlot" },
	INVTYPE_2HWEAPON = { "MainHandSlot" },
	INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
	INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
	INVTYPE_SHIELD = { "SecondaryHandSlot" },
	INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
	INVTYPE_RANGED = { "RangedSlot" },
	INVTYPE_RANGEDRIGHT = { "RangedSlot" },
	INVTYPE_THROWN = { "RangedSlot" },
	INVTYPE_RELIC = { "RangedSlot" },
	INVTYPE_TABARD = { "TabardSlot" },
}

local COMPARE_TOOLTIPS = { "ShoppingTooltip1", "ShoppingTooltip2" }

-- The tooltip skin draws each flat body 4 units inside its frame edge, so two
-- frames overlapping by 6 leave 2 units between the bodies.
local COMPARE_OVERLAP = 6

-- A callback owner of its own: CallbackHandler keeps one callback per owner
-- and event, and TT already holds the visibility toggle's.
local compareCallbacks = {}

-- The INVTYPE_* token is matched by its prefix instead of a fixed position:
-- the GetItemInfo return lists of 1.12-derived clients differ (UA documents
-- minLevel 4th and equipLoc 8th; clients that also return an item level shift
-- every later value by one).
local function EquipLoc(id)
	if not id then return nil end
	local info = { pcall(GetItemInfo, id) }
	if not info[1] then return nil end
	local i
	for i = 2, 12 do
		local value = info[i]
		if type(value) == "string" and find(value, "^INVTYPE_") then
			return value
		end
	end
	return nil
end

-- Setter fills that get no comparison: the player's own equipped item, and
-- auction listings, which the Auction House compares natively.
local function IsComparedFill(name, unit, slot)
	if name == "SetAuctionItem" then return false end
	if name == "SetInventoryItem" then
		return not (unit == "player" and type(slot) == "number" and slot < 20)
	end
	return true
end

-- Left of GameTooltip while it sits in the right half of the screen, right of
-- it otherwise. Top-aligned, so the heading grows the frame downwards, away
-- from the edge it shares with GameTooltip.
local function CompareOnLeft(owner)
	local okCenter, x = pcall(owner.GetCenter, owner)
	if not okCenter or not x then return true end
	local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return x * scale > UIParent:GetWidth() / 2
end

-- "Currently Equipped" heading above a comparison tooltip's lines, as the
-- native merchant and auction comparison setters add it; SetInventoryItem adds
-- none. ShoppingTooltipTemplate is laid out for that heading: line 1 is
-- GameFontNormalSmall, line 2 GameFontNormal, line 3 onwards smaller fonts, so
-- after SetInventoryItem the item name sits on the small line and the second
-- row on the large one.
--
-- No line's text is ever copied to another line. On UA FontString:GetTextColor
-- returns the colour of the line's font object, not the line's own colour, so
-- a row copied one line down (the pfUI/UnrealUI technique) loses its
-- item-quality, green "Equip:" or red requirement colour. Instead, measured on
-- UA:
--   * line 1 is re-anchored one heading lower; every other line hangs off the
--     one above it, so the whole list follows with its colours intact;
--   * lines 1 and 2 swap font sizes and are re-measured. SetFontObject alone
--     keeps a line's colour, but the name comes out white once it is written
--     again, so line 1 is recoloured from the equipped item's link. Line 2 is
--     the binding text, white natively;
--   * the frame is sized by hand to its last line, one frame after the
--     fill (ScheduleFit): calling Show() again to make it re-layout collapses
--     it to zero width;
--   * the heading is a FontString of this module's own in the freed space.
-- Everything is undone before the frame is hidden, so the next fill, and the
-- Auction House's own comparison in the same frames, start from native.
--
-- Text follows UnrealUI's measured rules for tooltip lines on UA
-- (modules/tooltip.lua): text is truncated to the width its region has when
-- SetText runs and a font change does not re-measure it, so a line is widened,
-- written blank and then with its text, and trimmed to its drawn width plus the
-- 5 units every native line carries. When the widest re-measured text exceeds
-- the frame's content, the frame is widened and every right-hand line
-- re-anchored: a right line hangs off its row's left line by the content width
-- and does not follow a resized frame.
local HEADER_TEXT = CURRENTLY_EQUIPPED or L["Currently Equipped"]
local HEADER_SHIFT = 14
local LINE_INSET = 10
local LINE_PAD = 5
local LINE_MEASURE_WIDTH = 512

local function DrawnWidth(label)
	if not label or not label:IsShown() then return 0 end
	local text = label:GetText()
	if not text or text == "" then return 0 end
	return label:GetStringWidth() or 0
end

-- A second point is dropped if SetPoint added one instead of replacing the
-- existing anchor; the line is not cleared first, so a failing SetPoint cannot
-- leave it unanchored.
local function AnchorRightLine(right, leftName, content)
	right:SetPoint("RIGHT", leftName, "LEFT", content, 0)
	if right:GetNumPoints() > 1 then
		right:ClearAllPoints()
		right:SetPoint("RIGHT", leftName, "LEFT", content, 0)
	end
end

-- Native position of line 1 is TOPLEFT 10,-10 (GameTooltipTemplate).
local function AnchorFirstLine(tip, name, shift)
	local first = _G[name .. "TextLeft1"]
	if not first then return end
	first:ClearAllPoints()
	first:SetPoint("TOPLEFT", tip, "TOPLEFT", LINE_INSET, -(LINE_INSET + shift))
end

-- Writes a label's text again so it is measured against its current font and
-- trimmed like a native line; returns the new width.
local function Remeasure(label, text)
	label:SetWidth(LINE_MEASURE_WIDTH)
	label:SetText("")
	label:SetText(text)
	local width = (label:GetStringWidth() or 0) + LINE_PAD
	label:SetWidth(width)
	return width
end

local function SetLineFont(label, font)
	if not label or not font then return 0 end
	label:SetFontObject(font)
	local text = label:GetText()
	if not label:IsShown() or not text or text == "" then return 0 end
	return Remeasure(label, text)
end

-- Quality colour from an item link's own |cAARRGGBB prefix.
local function LinkColor(link)
	if type(link) ~= "string" then return nil end
	local _, _, rr, gg, bb = find(link, "^|c%x%x(%x%x)(%x%x)(%x%x)")
	if not rr then return nil end
	return tonumber(rr, 16) / 255, tonumber(gg, 16) / 255, tonumber(bb, 16) / 255
end

-- The height is measured rather than the heading's height added, so the
-- swapped fonts' line heights need not be known: the frame reaches from its top
-- to the last line's bottom plus the inset line 1 natively has from the top.
-- +HEADER_SHIFT only when no position can be read.
-- On UA a shown comparison frame can report NumLines() == 0 one frame after
-- its fill, so the line count taken at fill time (elvCompareLines) is used
-- when it is larger.
local function CompareLineCount(tip)
	local count = tip:NumLines() or 0
	local stored = tip.elvCompareLines or 0
	if stored > count then count = stored end
	return count
end

local function FitCompareTooltip(tip)
	local name = tip:GetName()
	if not name then return end

	local lines = CompareLineCount(tip)
	local top = tip:GetTop()
	local last = _G[name .. "TextLeft" .. lines]
	local bottom = last and last:GetBottom()
	if top and bottom then
		tip:SetHeight(top - bottom + LINE_INSET)
	elseif not tip.elvCompareFallback then
		-- Once per fill: the fit repeats every frame.
		tip.elvCompareFallback = true
		tip:SetHeight((tip:GetHeight() or 0) + HEADER_SHIFT)
	end

	local widest = tip.elvCompareWidest or 0
	local content = (tip:GetWidth() or 0) - LINE_INSET * 2
	if widest > content then
		tip:SetWidth(widest + LINE_INSET * 2)
		local i
		for i = 1, lines do
			local right = _G[name .. "TextRight" .. i]
			if DrawnWidth(right) > 0 then
				AnchorRightLine(right, name .. "TextLeft" .. i, widest)
			end
		end
	end
end

-- Sizing runs on every frame from the one after the fill until the comparison
-- is hidden, reading the positions the lines have once line 1 is re-anchored
-- and the fonts are swapped. Measured on UA: on a frame refilled after an
-- earlier comparison the lines still report their pre-shift positions a frame
-- after the fill and move later, so a single fit leaves the frame one heading
-- short; a newly filled frame is settled by the next frame.
local pendingFits = {}
local fitFrame

local function RunPendingFits()
	local any = false
	local pending
	for pending in pairs(pendingFits) do
		if pending.elvCompareHeaderShown and pending:IsShown() then
			pcall(FitCompareTooltip, pending)
			any = true
		else
			pendingFits[pending] = nil
		end
	end
	if not any then fitFrame:Hide() end
end

local function ScheduleFit(tip)
	pendingFits[tip] = true
	if not fitFrame then
		fitFrame = CreateFrame("Frame")
		fitFrame:Hide()
		fitFrame:SetScript("OnUpdate", RunPendingFits)
	end
	fitFrame:Show()
end

-- `minWidest` is the widest line already re-measured by the caller (the stat
-- difference rows), so the frame is widened for those too.
local function AddCompareHeader(tip, slot, minWidest)
	local name = tip:GetName()
	if not name or tip.elvCompareHeaderShown then return end
	-- Set first, so a failure part-way through is still undone on hide.
	tip.elvCompareHeaderShown = true

	local header = tip.elvCompareHeader
	if not header then
		header = tip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header:SetJustifyH("LEFT")
		header:SetPoint("TOPLEFT", tip, "TOPLEFT", LINE_INSET, -LINE_INSET)
		tip.elvCompareHeader = header
	end
	local widest = Remeasure(header, HEADER_TEXT)
	if minWidest and minWidest > widest then widest = minWidest end
	header:SetTextColor(0.5, 0.5, 0.5)
	header:Show()

	local first = _G[name .. "TextLeft1"]
	local nameWidth = SetLineFont(first, GameFontNormal)
	if nameWidth > widest then widest = nameWidth end
	local r, g, b = LinkColor(GetInventoryItemLink("player", slot))
	if first and r then first:SetTextColor(r, g, b) end
	SetLineFont(_G[name .. "TextLeft2"], GameFontHighlightSmall)

	AnchorFirstLine(tip, name, HEADER_SHIFT)
	tip.elvCompareWidest = widest
	ScheduleFit(tip)
end

-- Native anchor and fonts back (ShoppingTooltipTemplate: line 1
-- GameFontNormalSmall, line 2 GameFontNormal). Line widths and the frame size
-- are recomputed by the next fill.
local function RemoveCompareHeader(tip)
	if not tip.elvCompareHeaderShown then return end
	tip.elvCompareHeaderShown = nil
	tip.elvCompareLines = nil
	tip.elvCompareFallback = nil
	if tip.elvCompareHeader then tip.elvCompareHeader:Hide() end
	local name = tip:GetName()
	if not name then return end
	AnchorFirstLine(tip, name, 0)
	local first, second = _G[name .. "TextLeft1"], _G[name .. "TextLeft2"]
	if first then first:SetFontObject(GameFontNormalSmall) end
	if second then second:SetFontObject(GameFontNormal) end
end

-- ---------------------------------------------------------------------------
-- Stat difference
--
-- Below each equipped item's lines: the net change of replacing that piece
-- with the hovered item, green for a gain and red for a loss, in the hovered
-- item's line order, then what only the equipped piece carries. Each frame
-- states its own swap, so two rings or trinkets stay unambiguous (UnrealUI's
-- "If you replace this item" summary; pfUI eqcompare's basestats).
--
-- Both sides are parsed from the text their tooltips show, not from item
-- links: UA's SetHyperlink drops the random-suffix field, so "... of the Owl"
-- would lose its stats. Bonus lines ("+10 Stamina", "Equip: ...") go through
-- LibItemBonusLib-1.0's line parser (AddBonusInfo), which recognises bonuses
-- only. Base armour and weapon DPS are matched here, from the client's own
-- ARMOR_TEMPLATE / DPS_TEMPLATE. Parsing stops at the set name line: set
-- bonuses depend on the other pieces worn and are left out. A two-hander
-- compared with a main hand ignores what the off hand gives.
--
-- Rows are added with AddLine before the frame's first Show, so the native
-- layout already includes them; each is then re-measured like the heading's
-- lines, and the frame sizing in FitCompareTooltip covers the rest.
-- ---------------------------------------------------------------------------

local LIB = LibStub("LibItemBonusLib-1.0", true)

local DIFF_MAX_ROWS = 12
local DIFF_GAIN = { 0.53, 1, 0.53 }
local DIFF_LOSS = { 1, 0.53, 0.53 }
local DIFF_TITLE = { 1, 0.82, 0 }

-- Bonus keys whose value is a percentage.
local PERCENT_KEYS = {
	CRIT = true, RANGEDCRIT = true, SPELLCRIT = true, HOLYCRIT = true,
	NATURECRIT = true, TOHIT = true, SPELLTOHIT = true, DODGE = true,
	PARRY = true, BLOCK = true,
}

-- A GlobalStrings format ("%d Armor", "(%.1f damage per second)") as an
-- anchored Lua pattern capturing its one number.
local function FormatPattern(fmt)
	if type(fmt) ~= "string" then return nil end
	fmt = string.gsub(fmt, "%%%d*%$?%.?%d*[dfs]", "\001")
	fmt = string.gsub(fmt, "([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
	fmt = string.gsub(fmt, "\001", "([%%d%%.,]+)")
	return "^" .. fmt .. "$"
end

local basePatterns, setPattern

local function BuildPatterns()
	if basePatterns then return end
	basePatterns = {
		{ key = "BASEARMOR", pattern = FormatPattern(ARMOR_TEMPLATE or "%d Armor") },
		{ key = "DPS", pattern = FormatPattern(DPS_TEMPLATE or "(%.1f damage per second)") },
	}
	setPattern = FormatPattern(ITEM_SET_NAME or "%s (%d/%d)")
	-- The set line has three fields; only its shape matters here.
	if setPattern then setPattern = string.gsub(setPattern, "%(%[%%d%%%.,%]%+%)", ".+") end
end

local function ToNumber(text)
	return tonumber((string.gsub(text, ",", ".")))
end

local function AddStat(stats, order, key, value)
	value = tonumber(value)
	if not value or value == 0 then return end
	if not stats[key] then table.insert(order, key) end
	stats[key] = (stats[key] or 0) + value
end

local function MatchBaseStat(stats, order, text)
	local i
	for i = 1, getn(basePatterns) do
		local p = basePatterns[i]
		if p.pattern then
			local _, _, value = find(text, p.pattern)
			if value then
				AddStat(stats, order, p.key, ToNumber(value))
				return true
			end
		end
	end
	return false
end

-- Stats of the item a tooltip shows, from line 2 to the set name line;
-- returns the value map and the keys in line order.
local function ParseItemStats(tip)
	BuildPatterns()
	local stats, order = {}, {}
	local name = tip:GetName()
	if not name then return stats, order end
	local i
	for i = 2, tip:NumLines() do
		local left = _G[name .. "TextLeft" .. i]
		local text = left and left:IsShown() and left:GetText()
		if text and text ~= "" and not IsExtraLine(text) then
			text = StripEscapes(text)
			if setPattern and find(text, setPattern) then break end
			if not MatchBaseStat(stats, order, text) then
				local found = {}
				pcall(LIB.AddBonusInfo, LIB, found, text)
				local key, value
				for key, value in pairs(found) do
					AddStat(stats, order, key, value)
				end
			end
		end
	end
	return stats, order
end

local function DiffLabel(key)
	if key == "BASEARMOR" then return L["Armor"] end
	if key == "DPS" then return L["DPS"] end
	return LIB:GetBonusFriendlyName(key)
end

-- "+12", "-3.5", "+1%"; DPS keeps one decimal, like its tooltip line.
local function FormatDelta(key, delta)
	local size = math.floor(math.abs(delta) * 10 + 0.5) / 10
	local text
	if size == math.floor(size) then
		text = format("%d", size)
	else
		text = format("%.1f", size)
	end
	if PERCENT_KEYS[key] then text = text .. "%" end
	return ((delta > 0) and "+" or "-") .. text
end

local function DiffRows(hovered, hoveredOrder, worn, wornOrder)
	local rows, seen = {}, {}
	local sources = { hoveredOrder, wornOrder }
	local s, i
	for s = 1, 2 do
		local order = sources[s]
		for i = 1, getn(order) do
			local key = order[i]
			if not seen[key] then
				seen[key] = true
				local delta = (hovered[key] or 0) - (worn[key] or 0)
				if math.abs(delta) >= 0.05 and getn(rows) < DIFF_MAX_ROWS then
					table.insert(rows, {
						text = FormatDelta(key, delta) .. " " .. DiffLabel(key),
						color = (delta > 0) and DIFF_GAIN or DIFF_LOSS,
					})
				end
			end
		end
	end
	return rows
end

-- Appends the rows (a blank separator and the title first) and returns the
-- line indices that took them. A frame whose line count does not grow gets
-- no further rows.
local function AppendDiffRows(tip, rows)
	local added = {}
	if getn(rows) == 0 then return added end
	table.insert(rows, 1, { text = L["If you replace this item:"], color = DIFF_TITLE })
	table.insert(rows, 1, { text = " ", color = DIFF_TITLE })
	local i
	for i = 1, getn(rows) do
		local before = tip:NumLines()
		local row = rows[i]
		local ok = pcall(tip.AddLine, tip, row.text, row.color[1], row.color[2], row.color[3])
		if not ok or tip:NumLines() <= before then break end
		table.insert(added, { line = tip:NumLines(), row = row })
	end
	return added
end

-- After the frame is shown: every added row is written again at full width,
-- recoloured (SetText can reset the colour on UA) and trimmed; returns the
-- widest row.
local function RemeasureDiffRows(tip, added)
	local name = tip:GetName()
	local widest = 0
	if not name then return widest end
	local i
	for i = 1, getn(added) do
		local label = _G[name .. "TextLeft" .. added[i].line]
		if label then
			local row = added[i].row
			local width = Remeasure(label, row.text)
			label:SetTextColor(row.color[1], row.color[2], row.color[3])
			if width > widest then widest = width end
		end
	end
	return widest
end

-- Hides only what this module showed: the Auction House fills the same frames.
-- Hiding fires their OnHide, which on UA leaves the `this` global changed.
function TT:HideCompare()
	if not self.compareShown then return end
	self.compareShown = nil
	local caller = this
	local i
	for i = 1, getn(COMPARE_TOOLTIPS) do
		local tip = _G[COMPARE_TOOLTIPS[i]]
		if tip then
			pcall(RemoveCompareHeader, tip)
			pcall(tip.Hide, tip)
		end
	end
	this = caller
end

-- Each frame is anchored before it is filled, to GameTooltip or to the
-- previous comparison, so no size has to be measured. An empty slot is skipped
-- and the next equipped one takes its frame.
function TT:ShowCompare()
	self:HideCompare()

	local owner = GameTooltip
	local link = self.compareLink
	if not link or not owner:IsShown() then return end
	local _, _, idText = find(link, "item:(%d+)")
	local slots = COMPARE_SLOTS[EquipLoc(tonumber(idText)) or ""]
	if not slots then return end

	local hovered, hoveredOrder
	if LIB then
		local okParse, stats, order = pcall(ParseItemStats, owner)
		if okParse then hovered, hoveredOrder = stats, order end
	end

	local onLeft = CompareOnLeft(owner)
	local vertical = "TOP"
	local caller = this
	local previous = owner
	local used = 0
	local i
	for i = 1, getn(slots) do
		local okSlot, slot = pcall(GetInventorySlotInfo, slots[i])
		local tip = _G[COMPARE_TOOLTIPS[used + 1]]
		if tip and okSlot and slot and GetInventoryItemLink("player", slot) then
			pcall(tip.SetOwner, tip, owner, "ANCHOR_NONE")
			pcall(tip.ClearAllPoints, tip)
			if onLeft then
				pcall(tip.SetPoint, tip, vertical .. "RIGHT", previous, vertical .. "LEFT", COMPARE_OVERLAP, 0)
			else
				pcall(tip.SetPoint, tip, vertical .. "LEFT", previous, vertical .. "RIGHT", -COMPARE_OVERLAP, 0)
			end
			local okFill, hasItem = pcall(tip.SetInventoryItem, tip, "player", slot)
			if okFill and hasItem then
				local added
				if hovered then
					local okParse, worn, wornOrder = pcall(ParseItemStats, tip)
					local okRows, rows
					if okParse then
						okRows, rows = pcall(DiffRows, hovered, hoveredOrder, worn, wornOrder)
					end
					if okRows then
						local okAdd, lines = pcall(AppendDiffRows, tip, rows)
						if okAdd then added = lines end
					end
				end
				local okCount, count = pcall(tip.NumLines, tip)
				tip.elvCompareLines = okCount and count or nil
				pcall(tip.Show, tip)
				local widest = 0
				if added then
					local okWidth, width = pcall(RemeasureDiffRows, tip, added)
					if okWidth then widest = width end
				end
				pcall(AddCompareHeader, tip, slot, widest)
				self.compareShown = true
				previous = tip
				used = used + 1
			else
				pcall(tip.Hide, tip)
			end
		end
	end
	this = caller
end

function compareCallbacks:OnModifierStateChanged()
	if not TT.compareLink or not GameTooltip:IsShown() then return end
	if IsShiftKeyDown() then
		pcall(TT.ShowCompare, TT)
	else
		pcall(TT.HideCompare, TT)
	end
end

-- Called with the item GameTooltip has just been filled for.
-- A bag button re-runs its OnEnter every frame while it owns GameTooltip
-- (FrameXML ContainerFrameItemButton_OnUpdate, its throttle commented out), and
-- the legacy client's setter wrappers see the same per-frame refill. Showing
-- the comparison again refills its frames at native size and throws away the
-- heading's layout, so an item already being compared is left alone; Shift
-- presses reach OnModifierStateChanged through LibModifierState instead.
function TT:SetCompareItem(link)
	if type(link) ~= "string" or not GameTooltip:IsShown() then return end
	if link == self.compareLink then return end
	self.compareLink = link
	if LMS and not self.compareTracking then
		LMS.RegisterCallback(compareCallbacks, "MODIFIER_STATE_CHANGED", "OnModifierStateChanged")
		self.compareTracking = true
	end
	compareCallbacks:OnModifierStateChanged()
end

function TT:ClearCompareItem()
	self.compareLink = nil
	self:HideCompare()
	if LMS and self.compareTracking then
		LMS.UnregisterCallback(compareCallbacks, "MODIFIER_STATE_CHANGED")
		self.compareTracking = nil
	end
end

-- ---------------------------------------------------------------------------
-- Item hover sources
--
-- Legacy client: real ElvUI's approach, the GameTooltip item setters are
-- wrapped, so every surface calling them is covered. On UA replacing those
-- methods does not take effect (see the file header), so the item is resolved
-- from the hovered surface instead: FrameXML hover globals where the native
-- button calls one (bags, character slots), a chained OnEnter script where the
-- handler is inline XML (bank, merchant, quest rewards, trade window, trade
-- skill and craft reagents), a post-hook on the AuctionFrameItem_OnEnter
-- global for auction rows, and a direct call from our own loot window. The
-- trade skill, craft and auction buttons come from load-on-demand addons and
-- are hooked once those have loaded. Action buttons are not covered on UA: no
-- API returns the item of an action slot.
-- ---------------------------------------------------------------------------

local ITEM_SETTERS = {
	SetBagItem = function(bag, slot)
		local _, count = GetContainerItemInfo(bag, slot)
		return GetContainerItemLink(bag, slot), count
	end,
	SetInventoryItem = function(unit, slot)
		if type(slot) ~= "number" or slot < 0 then return end
		local count = 1
		if slot < 20 or (slot > 39 and slot < 68) then
			count = GetInventoryItemCount(unit, slot)
		end
		return GetInventoryItemLink(unit, slot), count
	end,
	SetLootItem = function(slot)
		local _, _, count = GetLootSlotInfo(slot)
		return GetLootSlotLink(slot), count
	end,
	SetLootRollItem = function(rollID)
		local _, _, count = GetLootRollItemInfo(rollID)
		return GetLootRollItemLink(rollID), count
	end,
	SetMerchantItem = function(slot)
		local _, _, _, count = GetMerchantItemInfo(slot)
		return GetMerchantItemLink(slot), count
	end,
	SetQuestItem = function(questType, slot)
		local _, _, count = GetQuestItemInfo(questType, slot)
		return GetQuestItemLink(questType, slot), count
	end,
	SetQuestLogItem = function(questType, index)
		local _, _, count = GetQuestLogRewardInfo(index)
		return GetQuestLogItemLink(questType, index), count
	end,
	SetTradeSkillItem = function(skill, slot)
		if slot then
			local _, _, count = GetTradeSkillReagentInfo(skill, slot)
			return GetTradeSkillReagentItemLink(skill, slot), count
		end
		return GetTradeSkillItemLink(skill), 1
	end,
	SetCraftItem = function(skill, slot)
		if slot then
			local _, _, count = GetCraftReagentInfo(skill, slot)
			return GetCraftReagentItemLink(skill, slot), count
		end
		return GetCraftItemLink(GetCraftSelectionIndex()), 1
	end,
	SetTradePlayerItem = function(index)
		local _, _, count = GetTradePlayerItemInfo(index)
		return GetTradePlayerItemLink(index), count
	end,
	SetTradeTargetItem = function(index)
		local _, _, count = GetTradeTargetItemInfo(index)
		return GetTradeTargetItemLink(index), count
	end,
	SetAuctionItem = function(auctionType, index)
		local _, _, count = GetAuctionItemInfo(auctionType, index)
		return GetAuctionItemLink(auctionType, index), count
	end,
	SetHyperlink = function(link)
		return link, 1
	end,
}

local function WrapSetter(tt, name, resolve)
	local original = tt[name]
	if type(original) ~= "function" then return end

	tt[name] = function(self, a, b, c, d)
		local r1, r2, r3 = original(self, a, b, c, d)
		local ok, link, count = pcall(resolve, a, b, c, d)
		if ok and link then
			pcall(TT.AddItemLines, TT, self, link, count)
			if self == GameTooltip and IsComparedFill(name, a, b) then
				pcall(TT.SetCompareItem, TT, link)
			end
		end
		return r1, r2, r3
	end
end

function TT:HookItemSetters()
	local tt = GameTooltip
	if not tt then return end

	local name, resolve
	for name, resolve in pairs(ITEM_SETTERS) do
		WrapSetter(tt, name, resolve)
	end
	self.itemSettersHooked = true
end

-- Chains `handler(frame)` after the frame's existing script, keeping the
-- original. An inline XML handler reads the `this` global; on UA a script
-- handler fired synchronously inside it leaves `this` changed, so it is put
-- back after the original and after the handler.
local function PostHookScript(frame, scriptName, handler)
	local okGet, original = pcall(frame.GetScript, frame, scriptName)
	if not okGet then return false end
	return pcall(frame.SetScript, frame, scriptName, function(a1, a2, a3, a4)
		local caller = this
		if original then original(a1, a2, a3, a4) end
		this = caller
		pcall(handler, frame)
		this = caller
	end)
end

local function TooltipShown()
	return GameTooltip and GameTooltip:IsShown()
end

function TT:OnContainerItemEnter(button)
	if not button or not TooltipShown() then return end
	self:TrackHover(button, "bag")
	if self:ApplyVisibility(GameTooltip, "bags") then return end
	if not ElvUI.Compat.isUA then return end
	local bag = button:GetParent():GetID()
	if bag == KEYRING_CONTAINER then return end
	local slot = button:GetID()
	local _, count = GetContainerItemInfo(bag, slot)
	local link = GetContainerItemLink(bag, slot)
	self:AddItemLines(GameTooltip, link, count)
	self:SetCompareItem(link)
end

function TT:OnInventorySlotEnter(button)
	if not button or not TooltipShown() then return end
	local slot = button:GetID()
	self:AddItemLines(GameTooltip, GetInventoryItemLink("player", slot), 1)
end

function TT:OnBankItemEnter(button)
	if not TooltipShown() then return end
	self:TrackHover(button, "bank")
	if self:ApplyVisibility(GameTooltip, "bags") then return end
	if not ElvUI.Compat.isUA then return end
	local slot = button:GetID()
	local _, count = GetContainerItemInfo(BANK_KEY, slot)
	local link = GetContainerItemLink(BANK_KEY, slot)
	self:AddItemLines(GameTooltip, link, count)
	self:SetCompareItem(link)
end

function TT:OnMerchantItemEnter(button)
	if not TooltipShown() or not MerchantFrame or MerchantFrame.selectedTab ~= 1 then return end
	local index = button:GetID()
	local _, _, _, count = GetMerchantItemInfo(index)
	local link = GetMerchantItemLink(index)
	self:AddItemLines(GameTooltip, link, count)
	self:SetCompareItem(link)
end

-- A hovered button whose item `resolve(button)` returns as link, count. The
-- resolvers reuse ITEM_SETTERS with the arguments the native OnEnter passes to
-- the matching setter.
function TT:OnSurfaceItemEnter(button, resolve)
	if not button or not TooltipShown() then return end
	local link, count = resolve(button)
	if not link then return end
	self:AddItemLines(GameTooltip, link, count)
	self:SetCompareItem(link)
end

local function HookSurfaceButton(name, resolve)
	local button = _G[name]
	if not button then return end
	PostHookScript(button, "OnEnter", function(frame) TT:OnSurfaceItemEnter(frame, resolve) end)
end

-- QuestFrame.lua and QuestLogFrame.lua store the list on the button (`type`:
-- "choice", "reward" or "required") and, for rewards, its kind (`rewardType`:
-- "item" or "spell"). Required items get no rewardType.
local function QuestItemLink(button)
	if button.rewardType == "spell" then return end
	return ITEM_SETTERS.SetQuestItem(button.type, button:GetID())
end

local function QuestLogItemLink(button)
	if button.rewardType ~= "item" then return end
	return ITEM_SETTERS.SetQuestLogItem(button.type, button:GetID())
end

local function TradeSkillProductLink()
	local index = GetTradeSkillSelectionIndex()
	if not index or index == 0 then return end
	return ITEM_SETTERS.SetTradeSkillItem(index)
end

local function TradeSkillReagentLink(button)
	return ITEM_SETTERS.SetTradeSkillItem(GetTradeSkillSelectionIndex(), button:GetID())
end

-- The craft window's own icon shows the craft spell, not an item.
local function CraftReagentLink(button)
	return ITEM_SETTERS.SetCraftItem(GetCraftSelectionIndex(), button:GetID())
end

function TT:HookQuestSurfaces()
	local i
	for i = 1, 10 do
		HookSurfaceButton("QuestDetailItem" .. i, QuestItemLink)
		HookSurfaceButton("QuestRewardItem" .. i, QuestItemLink)
		HookSurfaceButton("QuestLogItem" .. i, QuestLogItemLink)
	end
	for i = 1, 6 do
		HookSurfaceButton("QuestProgressItem" .. i, QuestItemLink)
	end
end

-- The trade slot index is the item frame's id; it is taken from the frame name
-- rather than from GetParent() on the button.
function TT:HookTradeSurfaces()
	local i
	for i = 1, 7 do
		local id = i
		HookSurfaceButton("TradePlayerItem" .. i .. "ItemButton",
			function() return ITEM_SETTERS.SetTradePlayerItem(id) end)
		HookSurfaceButton("TradeRecipientItem" .. i .. "ItemButton",
			function() return ITEM_SETTERS.SetTradeTargetItem(id) end)
	end
end

function TT:HookTradeSkillSurfaces()
	HookSurfaceButton("TradeSkillSkillIcon", TradeSkillProductLink)
	local i
	for i = 1, 8 do
		HookSurfaceButton("TradeSkillReagent" .. i, TradeSkillReagentLink)
	end
end

function TT:HookCraftSurfaces()
	local i
	for i = 1, 8 do
		HookSurfaceButton("CraftReagent" .. i, CraftReagentLink)
	end
end

-- AuctionFrameItem_OnEnter fills the native auction comparison itself, so only
-- the item lines are added.
function TT:OnAuctionItemEnter(auctionType, index)
	if not TooltipShown() then return end
	local link, count = ITEM_SETTERS.SetAuctionItem(auctionType, index)
	self:AddItemLines(GameTooltip, link, count)
end

function TT:HookAuctionSurfaces()
	pcall(function()
		TT:SecureHook("AuctionFrameItem_OnEnter", function(auctionType, index)
			local caller = this
			pcall(TT.OnAuctionItemEnter, TT, auctionType, index)
			this = caller
		end)
	end)
end

-- Runs `hook` once the global `name` exists: Skins' WaitForGlobal, which
-- checks on ADDON_LOADED and on a short poll until the load-on-demand addon
-- defining it has loaded.
local function WhenGlobalExists(name, hook)
	local S = E:GetModule("Skins", true)
	if S and type(S.WaitForGlobal) == "function" then
		S:WaitForGlobal(name, hook)
	elseif _G[name] then
		pcall(hook)
	end
end

-- The bag and bank hooks run on both clients: they carry the visibility
-- check everywhere, and the item lines only on UA (the legacy client gets
-- those from the setter wrappers). Every other surface hook exists for the
-- item lines alone, so those are installed on UA only.
function TT:HookItemSurfaces()
	pcall(function()
		TT:SecureHook("ContainerFrameItemButton_OnEnter", function(button)
			local caller = this
			pcall(TT.OnContainerItemEnter, TT, button or caller)
			this = caller
		end)
	end)

	local i
	for i = 1, NUM_BANKGENERIC_SLOTS or 24 do
		local button = _G["BankFrameItem" .. i]
		if button then
			PostHookScript(button, "OnEnter", function(frame) TT:OnBankItemEnter(frame) end)
		end
	end

	if not ElvUI.Compat.isUA then return end

	pcall(function()
		TT:SecureHook("PaperDollItemSlotButton_OnEnter", function()
			local caller = this
			pcall(TT.OnInventorySlotEnter, TT, caller)
			this = caller
		end)
	end)
	for i = 1, 12 do
		local button = _G["MerchantItem" .. i .. "ItemButton"]
		if button then
			PostHookScript(button, "OnEnter", function(frame) TT:OnMerchantItemEnter(frame) end)
		end
	end

	self:HookQuestSurfaces()
	self:HookTradeSurfaces()
	WhenGlobalExists("TradeSkillFrame", function() TT:HookTradeSkillSurfaces() end)
	WhenGlobalExists("CraftFrame", function() TT:HookCraftSurfaces() end)
	WhenGlobalExists("AuctionFrameItem_OnEnter", function() TT:HookAuctionSurfaces() end)
end

function TT:HookItemSources()
	self:HookItemSurfaces()
	if not ElvUI.Compat.isUA then
		self:HookItemSetters()
	end
end

-- ---------------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------------

-- Tooltip text fonts from E.db.tooltip, real ElvUI's `TT:SetTooltipFonts`: set
-- on the three shared Font objects the tooltip lines inherit (line 1 the
-- header font, the other lines the text font, the comparison tooltips' lower
-- lines the small text font). Called again by the options page so a change
-- applies without a reload.
--
-- Real ElvUI also sets a font per FontString on ShoppingTooltip1/2 lines 1-4
-- and on the money frame texts. Not ported: `ShowCompare` swaps the Font
-- object of comparison lines 1-2 (`SetLineFont`), which would compete with a
-- per-string font, and the money texts stay on their native font.
function TT:SetTooltipFonts()
	local db = self.db
	local LSM = LibStub("LibSharedMedia-3.0", true)
	local path = LSM and LSM:Fetch("font", db.font)
	if not path then return end

	local outline = db.fontOutline
	if outline == "NONE" then outline = "" end

	local objects = {
		{ _G.GameTooltipHeaderText, db.headerFontSize },
		{ _G.GameTooltipText, db.textFontSize },
		{ _G.GameTooltipTextSmall, db.smallTextFontSize },
	}
	local i
	for i = 1, table.getn(objects) do
		local obj, size = objects[i][1], objects[i][2]
		if obj and obj.SetFont then
			pcall(obj.SetFont, obj, path, size, outline)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------

function TT:Initialize()
	self.db = E.db.tooltip
	if not E.private.tooltip.enable then return end
	E.Tooltip = self

	self.anchor = CreateAnchor()
	E:CreateMover(self.anchor, "TooltipMover", L["Tooltip"])

	-- Every handler runs inside pcall: these hooks sit in the middle of
	-- native tooltip code paths, and an error here must not stop the
	-- original caller from finishing its own tooltip.
	--
	-- Every hook also puts the `this` global back before returning. On UA a
	-- script handler that runs synchronously inside another one (the OnHide
	-- fired by a visibility Hide in here, for example) leaves `this` pointing
	-- at its own frame (measured), and native callers keep using `this` after
	-- GameTooltip_SetDefaultAnchor returns: PetActionButton_OnEnter reads
	-- this.tooltipName, ActionButton_SetTooltip writes this.updateTooltip.
	pcall(function()
		TT:SecureHook("GameTooltip_SetDefaultAnchor", function(tt, parent)
			local caller = this
			pcall(TT.SetDefaultAnchor, TT, tt, parent)
			this = caller
		end)
	end)
	pcall(function()
		TT:SecureHook("SetItemRef", function(link)
			pcall(TT.SetItemRef, TT, link)
		end)
	end)
	self:HookItemSources()

	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
		if ElvUI.Compat.isUA and TT:ApplyVisibility(GameTooltip, nil) then return end
		pcall(TT.UpdateUnitTooltip, TT, "mouseover")
	end)
	if ElvUI.Compat.isUA then
		PostHookScript(GameTooltip, "OnShow", function() TT:OnTooltipShow() end)
	end

	self:SetupHealthBar()
	self:SetTooltipFonts()
	self:HookRefill()
end

-- On UA the client re-fills a shown unit tooltip's TEXT in combat with
-- neither OnShow nor UPDATE_MOUSEOVER_UNIT firing, so a one-time rewrite
-- flips back to the native text. Neither those nor the status bar's
-- OnValueChanged mark every refill (measured on UA: rewriting on the value
-- change still left the tooltip alternating). A frame-exact check is needed;
-- a timer would leave the native text on screen for up to its interval.
--
-- The check lives on a child of GameTooltip, so its OnUpdate only runs while
-- the tooltip is shown, and it only acts while a unit was rewritten during
-- that showing (`self.currentUnit`, dropped when the tooltip hides). For an
-- already rewritten fill UpdateUnitTooltip stops after a name and a level
-- line comparison. The unit is the one last rewritten, because a unit frame's
-- tooltip is filled for its own token ("target", "party1", ...), not for
-- "mouseover".
--
-- The same child's OnHide drops the remembered comparison item and hides the
-- comparison tooltips when GameTooltip hides.
--
-- The status bar's OnValueChanged is cleared, as real ElvUI does: the legacy
-- client's HealthBar_OnValueChanged would repaint the bar with a health
-- gradient over the reaction/class colour. UA ships no handler there.
function TT:HookRefill()
	local refresh = CreateFrame("Frame", nil, GameTooltip)
	refresh:SetScript("OnUpdate", function()
		if TT.currentUnit then
			pcall(TT.UpdateUnitTooltip, TT, TT.currentUnit)
			pcall(TT.UpdateHealthText, TT)
		end
	end)
	refresh:SetScript("OnHide", function()
		TT.currentUnit = nil
		pcall(TT.ClearCompareItem, TT)
	end)

	local bar = GameTooltipStatusBar
	if bar then
		pcall(bar.SetScript, bar, "OnValueChanged", nil)
	end
end

E:RegisterInitialModule(TT:GetName(), function() TT:Initialize() end)
