-- Misc > Totems -- real ElvUI's Totem Tracker (Modules/Misc/TotemTracker.lua):
-- one button per totem element showing the active totem's icon and time
-- left. Switch: E.private.general.totemTracker; layout: E.db.general.totems.
-- Shamans only: for every other class nothing is built.
--
-- The 1.12 client has no totem API (no GetTotemInfo, no PLAYER_TOTEM_UPDATE),
-- so the totem state is tracked here, the way pfUI's libtotem and
-- TotemTimers do it:
--   * A totem is recognised by its spell icon (locale independent) and put
--     into its element slot with a duration from the table below.
--   * Two independent sources report a cast; either one is enough, and when
--     both fire for the same cast within MERGE_WINDOW they count once:
--       - wrappers around UseAction / CastSpell / CastSpellByName queue the
--         totem (they also know the rank), and SPELLCAST_STOP commits it;
--         SPELLCAST_FAILED / SPELLCAST_INTERRUPTED drop the queue;
--       - the player's combat log line "You cast X on X." / "You cast X."
--         (SPELLCASTGOSELFTARGETTED / SPELLCASTGOSELF on
--         CHAT_MSG_SPELL_SELF_BUFF), which only appears for a cast that
--         succeeded. Unreal Azeroth writes the targeted form, the totem
--         itself being the target.
--   * A totem ends when its time runs out, when "X is destroyed." / "X dies."
--     arrives on CHAT_MSG_COMBAT_FRIENDLY_DEATH (matched by name, so another
--     shaman's totem of the same name also clears it), on death and on a
--     loading screen. The state is not saved: after /reload the bar stays
--     empty until the next cast.
--
-- Additions over real ElvUI, each behind its own switch:
--   * tickTimer: time to the totem's next pulse, from TotemTimers' pulse
--     intervals, counted from the cast.
--   * twistTimer: after Windfury Totem is replaced by another air totem,
--     the air button counts down the rest of the 10 seconds after the
--     Windfury cast (TotemTimers' model of the Windfury buff window), so
--     the next Windfury drop can be timed.
--
-- Where it differs from real ElvUI: the time left is text, not a cooldown
-- spiral, formatted and coloured like the cooldown text (E.db.cooldown);
-- the bar's cross-axis size follows the button height rather than the
-- width; and there is no right-click to destroy a totem, which the 1.12
-- client cannot do.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Misc")

local Compat = ElvUI.Compat
local Deformat = LibStub("LibDeformat-2.0", true)

local find, lower, gsub = string.find, string.lower, string.gsub
local floor = math.floor

local FIRE, EARTH, WATER, AIR = 1, 2, 3, 4
local NUM_SLOTS = 4
-- Button order, first to last: earth, fire, water, air -- real ElvUI's
-- Classic Era order (slots 1 and 2 swapped).
local BUTTON_SLOTS = { EARTH, FIRE, WATER, AIR }

-- Queue and merge windows, seconds. Totems are instant casts, so a queued
-- cast that sees no SPELLCAST_STOP within QUEUE_TTL did not happen.
local QUEUE_TTL = 1
local MERGE_WINDOW = 1.5
-- A destroyed/dies line this soon after a cast belongs to the totem the
-- cast replaced, not to the new one.
local DEATH_GRACE = 1
local RESCAN_THROTTLE = 1
local UPDATE_INTERVAL = 0.1

local WINDFURY = "spell_nature_windfury"
local FIRE_NOVA = "spell_fire_sealoffire"

local TWIST_COLOR = { 0.4, 0.8, 1 }

-- Keyed by the lower-cased icon file name. `duration` in seconds;
-- `durations` by rank where it differs per rank; `tick` is the pulse
-- interval. Durations: pfUI libtotem / UnrealUI auradata; pulses:
-- TotemTimers-Enhanced TotemTimersData.lua.
local TOTEMS = {
	-- Fire
	[FIRE_NOVA] = { slot = FIRE, duration = 5 },
	["spell_nature_guardianward"] = { slot = FIRE, duration = 120, tick = 5 }, -- Flametongue
	["spell_frostresistancetotem_01"] = { slot = FIRE, duration = 120 },
	["spell_fire_selfdestruct"] = { slot = FIRE, duration = 20, tick = 2 }, -- Magma
	["spell_fire_searingtotem"] = { slot = FIRE, duration = 55, durations = { 30, 35, 40, 45, 50, 55 } },
	-- Earth
	["spell_nature_strengthofearthtotem02"] = { slot = EARTH, duration = 45, tick = 3 }, -- Earthbind
	["spell_nature_stoneclawtotem"] = { slot = EARTH, duration = 15, tick = 1.5 },
	["spell_nature_stoneskintotem"] = { slot = EARTH, duration = 120 },
	["spell_nature_earthbindtotem"] = { slot = EARTH, duration = 120 }, -- Strength of Earth
	["spell_nature_tremortotem"] = { slot = EARTH, duration = 120, tick = 4 },
	-- Water
	["spell_nature_diseasecleansingtotem"] = { slot = WATER, duration = 120, tick = 5 },
	["spell_fireresistancetotem_01"] = { slot = WATER, duration = 120 },
	["inv_spear_04"] = { slot = WATER, duration = 60 }, -- Healing Stream
	["spell_nature_manaregentotem"] = { slot = WATER, duration = 60 }, -- Mana Spring
	["spell_frost_summonwaterelemental"] = { slot = WATER, duration = 12, tick = 3 }, -- Mana Tide
	["spell_nature_poisoncleansingtotem"] = { slot = WATER, duration = 120, tick = 5 },
	-- Air
	["spell_nature_invisibilitytotem"] = { slot = AIR, duration = 120 }, -- Grace of Air
	["spell_nature_groundingtotem"] = { slot = AIR, duration = 45 },
	["spell_nature_natureresistancetotem"] = { slot = AIR, duration = 120 },
	["spell_nature_brilliance"] = { slot = AIR, duration = 120 }, -- Tranquil Air
	[WINDFURY] = { slot = AIR, duration = 120, tick = 10 },
	["spell_nature_earthbind"] = { slot = AIR, duration = 120 }, -- Windwall
	["spell_nature_removecurse"] = { slot = AIR, duration = 300 }, -- Sentry
}

local active = {}        -- slot -> { key, name, icon, rank, rankExact, start, duration }
local queue = {}         -- key, rank, time
local spellsByKey = {}   -- icon key -> { name, icon, rank = highest known }
local keysByName = {}    -- spell name -> icon key
local lastScan = 0
local twistEnd           -- GetTime() at which the Windfury window closes
local fireNovaReduction = 0
local bar

-- Folds an icon path to its leaf name. The legacy client returns
-- "Interface\Icons\Name"; Unreal Azeroth returns
-- "/Game/Interface/Icons/Name_TEX" from GetSpellTexture and GetActionTexture.
-- Both separators, any file extension and the "_TEX" suffix are dropped
-- (same folding as UnrealUI's U.IconKey).
local function IconKey(icon)
	if type(icon) ~= "string" then return nil end
	local key = lower(gsub(icon, "^.*[\\/]", ""))
	key = gsub(key, "%.[a-z0-9]+$", "")
	key = gsub(key, "_tex$", "")
	if TOTEMS[key] then return key end
	return nil
end

local function RankNumber(rank)
	if type(rank) ~= "string" then return nil end
	local _, _, number = find(rank, "(%d+)")
	return tonumber(number)
end

-- Improved Fire Nova Totem shortens the Fire Nova delay by 1 second per
-- point (TotemTimers). The talent is looked up by icon, expected to be the
-- Fire Nova Totem spell icon, so the lookup works in every locale; when no
-- talent carries that icon no reduction is applied.
local function ScanTalents()
	fireNovaReduction = 0
	if type(GetNumTalentTabs) ~= "function" then return end
	local tab, index
	for tab = 1, (GetNumTalentTabs() or 0) do
		for index = 1, (GetNumTalents(tab) or 0) do
			local _, icon, _, _, rank = GetTalentInfo(tab, index)
			if IconKey(icon) == FIRE_NOVA then
				fireNovaReduction = tonumber(rank) or 0
				return
			end
		end
	end
end

local function ScanSpellbook()
	lastScan = GetTime()
	spellsByKey = {}
	keysByName = {}
	local i = 1
	while i <= 1024 do
		local name, rankText = GetSpellName(i, "spell")
		if not name then break end
		local icon = GetSpellTexture(i, "spell")
		local key = IconKey(icon)
		if key then
			local rank = RankNumber(rankText)
			local known = spellsByKey[key]
			if not known then
				spellsByKey[key] = { name = name, icon = icon, rank = rank }
			elseif rank and (not known.rank or rank > known.rank) then
				known.rank = rank
			end
			keysByName[name] = key
		end
		i = i + 1
	end
	ScanTalents()
end

-- Every spell's cast line passes through here, so a name that is not a
-- totem must not trigger a rescan; the spellbook events keep the table
-- current.
local function KeyForName(name)
	if not name then return nil end
	return keysByName[name]
end

local function TotemDuration(key, rank)
	local data = TOTEMS[key]
	local duration = data.duration
	if data.durations and rank and data.durations[rank] then
		duration = data.durations[rank]
	end
	if key == FIRE_NOVA then
		duration = duration - fireNovaReduction
	end
	return duration
end

-- Records a cast. A second report of the same cast inside MERGE_WINDOW only
-- replaces an assumed rank (the highest known) with the cast's own.
local function Commit(key, rank)
	local data = TOTEMS[key]
	if not data then return end
	local slot = data.slot
	local now = GetTime()
	local spell = spellsByKey[key]
	if not spell and GetTime() - lastScan > RESCAN_THROTTLE then
		ScanSpellbook()
		spell = spellsByKey[key]
	end

	local existing = active[slot]
	if existing and existing.key == key and now - existing.start < MERGE_WINDOW then
		if rank and not existing.rankExact then
			existing.rank = rank
			existing.rankExact = true
			existing.duration = TotemDuration(key, rank)
		end
		return
	end

	local rankExact = rank ~= nil
	rank = rank or (spell and spell.rank)

	if slot == AIR then
		if key == WINDFURY then
			twistEnd = nil
		elseif existing and existing.key == WINDFURY then
			twistEnd = existing.start + TOTEMS[WINDFURY].tick
		end
	end

	active[slot] = {
		key = key,
		name = spell and spell.name,
		icon = spell and spell.icon or ("Interface\\Icons\\" .. key),
		rank = rank,
		rankExact = rankExact,
		start = now,
		duration = TotemDuration(key, rank),
	}
end

local function Queue(key, rank)
	if not key then return end
	queue.key = key
	queue.rank = rank
	queue.time = GetTime()
end

local function ClearQueue()
	queue.key = nil
	queue.rank = nil
	queue.time = nil
end

local function ClearAll()
	local slot
	for slot = 1, NUM_SLOTS do active[slot] = nil end
	twistEnd = nil
	ClearQueue()
end

-- A cast on cooldown or without mana never leaves the client, so it is not
-- queued.
local function CaptureAction(slot)
	local key = IconKey(GetActionTexture(slot))
	if not key then return end
	local start = GetActionCooldown(slot)
	if (tonumber(start) or 0) > 0 then return end
	local usable, noMana = IsUsableAction(slot)
	if not Compat.bool(usable) or Compat.bool(noMana) then return end
	Queue(key)
end

local function CaptureSpell(id, book)
	local key = IconKey(GetSpellTexture(id, book))
	if not key then return end
	local start = GetSpellCooldown(id, book)
	if (tonumber(start) or 0) > 0 then return end
	local _, rankText = GetSpellName(id, book)
	Queue(key, RankNumber(rankText))
end

-- "Name(Rank N)" or "Name".
local function CaptureSpellByName(text)
	if type(text) ~= "string" then return end
	local _, _, name, rankText = find(text, "^(.-)%((.*)%)$")
	if not name then name = text end
	Queue(KeyForName(name), RankNumber(rankText))
end

-- Plain global replacement: Unreal Azeroth has no hooksecurefunc. Each
-- wrapper records first and always calls through.
local function InstallCastWrappers()
	local origUseAction = UseAction
	if type(origUseAction) == "function" then
		UseAction = function(slot, checkCursor, onSelf)
			pcall(CaptureAction, slot)
			return origUseAction(slot, checkCursor, onSelf)
		end
	end

	local origCastSpell = CastSpell
	if type(origCastSpell) == "function" then
		CastSpell = function(id, book)
			pcall(CaptureSpell, id, book)
			return origCastSpell(id, book)
		end
	end

	local origCastSpellByName = CastSpellByName
	if type(origCastSpellByName) == "function" then
		CastSpellByName = function(text, onSelf)
			pcall(CaptureSpellByName, text)
			return origCastSpellByName(text, onSelf)
		end
	end
end

local CAST_TARGETED = _G.SPELLCASTGOSELFTARGETTED or "You cast %s on %s."
local CAST_SELF = _G.SPELLCASTGOSELF or "You cast %s."
local UNIT_DESTROYED = _G.UNITDESTROYEDOTHER or "%s is destroyed."
local UNIT_DIES = _G.UNITDIESOTHER or "%s dies."

local function OnCastLine(text)
	local spell = Deformat(text, CAST_TARGETED)
	if not spell then spell = Deformat(text, CAST_SELF) end
	local key = KeyForName(spell)
	if key then Commit(key) end
end

-- The unit name may carry a rank numeral after the spell name
-- ("Searing Totem III").
local function OnDeathLine(text)
	local unit = Deformat(text, UNIT_DESTROYED)
	if not unit then unit = Deformat(text, UNIT_DIES) end
	if not unit then return end
	local now = GetTime()
	local slot
	for slot = 1, NUM_SLOTS do
		local totem = active[slot]
		if totem and totem.name and now - totem.start > DEATH_GRACE
			and (unit == totem.name or find(unit, totem.name .. " ", 1, true) == 1) then
			active[slot] = nil
		end
	end
end

local function OnEvent()
	if event == "SPELLCAST_STOP" then
		if queue.key and GetTime() - queue.time <= QUEUE_TTL then
			Commit(queue.key, queue.rank)
		end
		ClearQueue()
	elseif event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
		ClearQueue()
	elseif event == "CHAT_MSG_SPELL_SELF_BUFF" then
		if type(arg1) == "string" then OnCastLine(arg1) end
	elseif event == "CHAT_MSG_COMBAT_FRIENDLY_DEATH" then
		if type(arg1) == "string" then OnDeathLine(arg1) end
	elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
		ClearAll()
	elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB"
		or event == "CHARACTER_POINTS_CHANGED" then
		ScanSpellbook()
	end
end

local function TenthsText(value)
	return string.format("%.1f", floor(value * 10) / 10)
end

local function UpdateButton(button, totem, now)
	if button.shownIcon ~= totem.icon then
		button.shownIcon = totem.icon
		button.icon:SetTexture(totem.icon)
	end

	local text, r, g, b = E.FormatCooldownRemain(totem.start + totem.duration - now)
	button.time:SetText(text)
	button.time:SetTextColor(r, g, b)

	local db = E.db.general.totems
	local tick = TOTEMS[totem.key].tick
	if tick and db.tickTimer then
		button.tick:SetText(TenthsText(tick - Compat.mod(now - totem.start, tick)))
	else
		button.tick:SetText("")
	end

	if button.slot == AIR and db.twistTimer and twistEnd and now < twistEnd and totem.key ~= WINDFURY then
		button.twist:SetText(TenthsText(twistEnd - now))
	else
		button.twist:SetText("")
	end
end

local function UpdateAll()
	local now = GetTime()
	local i
	for i = 1, NUM_SLOTS do
		local button = bar.buttons[i]
		local totem = active[button.slot]
		if totem and now >= totem.start + totem.duration then
			active[button.slot] = nil
			totem = nil
		end
		if totem then
			UpdateButton(button, totem, now)
			if not button:IsShown() then button:Show() end
		elseif button:IsShown() then
			button:Hide()
		end
	end
end

local function CreateText(button, point, y)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint(point, button, point, 0, y)
	text:SetJustifyH("CENTER")
	text:SetTextColor(1, 1, 1)
	return text
end

local function ShowTooltip(button)
	local totem = active[button.slot]
	if not totem or not totem.name then return end
	GameTooltip:SetOwner(button, "ANCHOR_TOPLEFT")
	GameTooltip:SetText(totem.name)
	GameTooltip:Show()
end

local function CreateButton(index)
	local button = CreateFrame("Button", "ElvUI_TotemTrackerTotem" .. index, bar)
	button.slot = BUTTON_SLOTS[index]
	E:SetTemplate(button, "Default")
	button:Hide()

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.icon = icon

	button.time = CreateText(button, "CENTER", 0)
	button.tick = CreateText(button, "BOTTOM", 2)
	button.twist = CreateText(button, "TOP", -2)
	button.twist:SetTextColor(TWIST_COLOR[1], TWIST_COLOR[2], TWIST_COLOR[3])

	button:EnableMouse(true)
	button:SetScript("OnEnter", function() ShowTooltip(button) end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

local function AnchorButton(button, prev, db)
	local spacing = db.spacing
	local ascending = db.sortDirection ~= "DESCENDING"
	if db.growthDirection == "HORIZONTAL" then
		if ascending then
			if prev then button:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
			else button:SetPoint("LEFT", bar, "LEFT", spacing, 0) end
		else
			if prev then button:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
			else button:SetPoint("RIGHT", bar, "RIGHT", -spacing, 0) end
		end
	else
		if ascending then
			if prev then button:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
			else button:SetPoint("TOP", bar, "TOP", 0, -spacing) end
		else
			if prev then button:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
			else button:SetPoint("BOTTOM", bar, "BOTTOM", 0, spacing) end
		end
	end
end

-- Real ElvUI's TM:PositionAndSize. Font sizes follow the button, on the
-- cooldown text's scale (20 at 36 pixels).
function M:PositionTotems()
	if not bar then return end
	local db = E.db.general.totems
	local width = db.size
	local height = db.keepSizeRatio and db.size or db.height
	local short = math.min(width, height)
	local i
	for i = 1, NUM_SLOTS do
		local button = bar.buttons[i]
		button:SetWidth(width)
		button:SetHeight(height)
		button:ClearAllPoints()
		AnchorButton(button, bar.buttons[i - 1], db)
		E:FontTemplate(button.time, nil, floor(short * 20 / 36 + 0.5), "OUTLINE")
		E:FontTemplate(button.tick, nil, math.max(8, floor(short * 0.3 + 0.5)), "OUTLINE")
		E:FontTemplate(button.twist, nil, math.max(8, floor(short * 0.3 + 0.5)), "OUTLINE")
	end

	local spacing = db.spacing
	if db.growthDirection == "HORIZONTAL" then
		bar:SetWidth(width * NUM_SLOTS + spacing * (NUM_SLOTS + 1))
		bar:SetHeight(height + spacing * 2)
	else
		bar:SetWidth(width + spacing * 2)
		bar:SetHeight(height * NUM_SLOTS + spacing * (NUM_SLOTS + 1))
	end
end

local EVENTS = {
	"SPELLCAST_STOP", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED",
	"CHAT_MSG_SPELL_SELF_BUFF", "CHAT_MSG_COMBAT_FRIENDLY_DEATH",
	"PLAYER_DEAD", "PLAYER_ENTERING_WORLD",
	"SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "CHARACTER_POINTS_CHANGED",
}

function M:LoadTotems()
	if bar or not E.private.general.totemTracker or not Deformat then return end
	local _, class = UnitClass("player")
	if class ~= "SHAMAN" then return end

	bar = CreateFrame("Frame", "ElvUI_TotemTracker", UIParent)
	bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 490, 4)
	bar.buttons = {}
	local i
	for i = 1, NUM_SLOTS do
		bar.buttons[i] = CreateButton(i)
	end
	self:PositionTotems()
	E:CreateMover(bar, "TotemTrackerMover", L["Totem Tracker"])

	ScanSpellbook()
	InstallCastWrappers()

	local events = CreateFrame("Frame")
	for i = 1, Compat.getn(EVENTS) do
		events:RegisterEvent(EVENTS[i])
	end
	events:SetScript("OnEvent", OnEvent)

	E:ScheduleRepeatingTimer(UpdateAll, UPDATE_INTERVAL)
end
