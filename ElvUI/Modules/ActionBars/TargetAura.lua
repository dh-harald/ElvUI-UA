-- ActionBars > Target Aura -- real ElvUI's target aura cooldowns
-- (LibActionButton-1.0 "Active Aura Cooldowns for Target", Classic
-- flavours only). An action button whose spell has put the player's own
-- aura on the current target shows that aura's time left, in place of the
-- cooldown text, while the button itself has no cooldown longer than the
-- global cooldown.
--
-- Real ElvUI's rules, kept here:
--   * only the player's own aura counts, matched by the aura name being the
--     button's spell name;
--   * a hostile target is checked for debuffs, a friendly one for buffs;
--   * a cooldown longer than the GCD on the button wins over the aura;
--   * text only, no spiral; one colour (colors.text), font sizing of the
--     action bar cooldown text;
--   * `threshold`: below this many seconds (and from one minute up) the
--     time reads M:SS, above it the abbreviated form (5m); 0 = never M:SS;
--   * `minDuration` (milliseconds): auras with a shorter full duration show
--     nothing.
-- Settings: E.db.cooldown.targetaura (enable, threshold, minDuration,
-- colors.text).
--
-- The 1.12 client has no aura caster or duration, so both come from
-- Modules/UnitFrames/OwnAuras.lua (the player's casts, stamped when they
-- happen). A macro button stands for the first spell with a known aura
-- duration that its body casts (`/cast` or CastSpellByName), in the
-- spirit of real ElvUI's GetMacroSpell.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E.ActionBars
-- E.UnitFrames is read at call time: the ActionBars folder loads before
-- the UnitFrames one, so it does not exist yet when this file runs.

local Compat = ElvUI.Compat

local UPDATE_INTERVAL = 0.1
-- Longest cooldown still treated as the GCD. Matches Core/Cooldowns.lua,
-- which also allows for Unreal Azeroth reporting the GCD above 1.5 s.
local GCD = 1.9

-- slot -> spell name, or false for a slot without a trackable spell.
local slotSpells = {}
-- spell name -> spellbook index of its highest rank, or false.
local bookIndex = {}
local timer

local function ClearSlotCache()
	local k
	for k in pairs(slotSpells) do slotSpells[k] = nil end
	for k in pairs(bookIndex) do bookIndex[k] = nil end
end

local function SlotSpell(slot)
	local name = slotSpells[slot]
	if name == nil then
		name = E.UnitFrames:GetActionSpell(slot, true) or false
		slotSpells[slot] = name
	end
	return name or nil
end

local function GetText(button)
	if button.elvTargetAuraText then return button.elvTargetAuraText end
	local name = button:GetName()
	local cooldown = name and _G[name.."Cooldown"]
	if not cooldown then return nil end

	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints(button)
	local okLevel, level = pcall(cooldown.GetFrameLevel, cooldown)
	if okLevel and tonumber(level) then
		holder:SetFrameLevel(level + 1)
	end

	local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("CENTER", cooldown, "CENTER", 0, 1)
	text:SetJustifyH("CENTER")
	text.elvCooldown = cooldown
	button.elvTargetAuraText = text
	return text
end

local function HideText(button)
	local text = button.elvTargetAuraText
	if text then pcall(text.SetText, text, "") end
end

-- M:SS below `threshold` seconds (from one minute up), otherwise the
-- abbreviated cooldown forms.
local function FormatTime(remain, threshold)
	local mmss = tonumber(threshold)
	if not mmss or mmss <= 0 then mmss = nil end
	local value, formatId, _, second = E:GetTimeInfo(remain, 0, nil, mmss)
	if formatId == 5 or formatId == 6 then
		return string.format(E.TimeFormats[formatId][2], value, second or 0)
	end
	return string.format(E.TimeFormats[formatId][2], value)
end

local function BookIndex(spell)
	local index = bookIndex[spell]
	if index == nil then
		index = false
		local i = 1
		while i <= 1024 do
			local ok, name = pcall(GetSpellName, i, "spell")
			if not ok or not name then break end
			if name == spell then index = i end
			i = i + 1
		end
		bookIndex[spell] = index
	end
	return index or nil
end

local function IsLongCooldown(start, duration)
	return (tonumber(start) or 0) > 0 and (tonumber(duration) or 0) > GCD
end

-- A macro slot reports no cooldown of its own, so a macro's spell is
-- looked up in the spellbook.
local function HasCooldown(slot, spell)
	if GetActionText(slot) then
		local index = BookIndex(spell)
		if not index then return false end
		return IsLongCooldown(GetSpellCooldown(index, "spell"))
	end
	return IsLongCooldown(GetActionCooldown(slot))
end

local function UpdateButton(button, targetName, db)
	if not Compat.bool(button:IsVisible()) then return HideText(button) end
	local slot = ActionButton_GetPagedID(button)
	local spell = slot and SlotSpell(slot)
	if not spell then return HideText(button) end

	local UF = E.UnitFrames
	local left, duration = UF:GetOwnAuraTimeLeft(targetName, spell)
	if not left or duration * 1000 < (tonumber(db.minDuration) or 0)
		or HasCooldown(slot, spell) or not UF:TargetHasAura(spell) then
		return HideText(button)
	end

	local text = GetText(button)
	if not text then return end
	if not E.ApplyCooldownFont(text.elvCooldown, text) then
		return pcall(text.SetText, text, "")
	end
	local c = db.colors.text
	text:SetTextColor(c.r, c.g, c.b)
	text:SetText(FormatTime(left, db.threshold))
end

local function ForEachButton(func, a1, a2)
	if not M.bars then return end
	for _, bar in pairs(M.bars) do
		for _, button in pairs(bar.buttons) do
			pcall(func, button, a1, a2)
		end
	end
end

local function Update()
	local db = E.db.cooldown.targetaura
	if not db.enable then
		ForEachButton(HideText)
		if timer then
			E:CancelTimer(timer)
			timer = nil
		end
		return
	end

	local targetName = Compat.bool(UnitExists("target")) and UnitName("target")
	if not targetName then return ForEachButton(HideText) end
	ForEachButton(UpdateButton, targetName, db)
end

-- Starts the ticker when the feature is on; the ticker stops itself and
-- clears the text when it is turned off.
function M:UpdateTargetAura()
	if not self.bars then return end
	if E.db.cooldown.targetaura.enable and not timer then
		timer = E:ScheduleRepeatingTimer(Update, UPDATE_INTERVAL)
	end
	Update()
end

function M:InitTargetAura()
	local events = CreateFrame("Frame")
	events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("UPDATE_MACROS")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function()
		if event == "ACTIONBAR_SLOT_CHANGED" and tonumber(arg1) and arg1 > 0 then
			slotSpells[arg1] = nil
		else
			ClearSlotCache()
		end
	end)
	self:UpdateTargetAura()
end
