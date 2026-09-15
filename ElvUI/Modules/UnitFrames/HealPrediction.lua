-- Heal prediction for the player's own heals. A segment the size of the healing
-- still to come is drawn on the target's health bar, in
-- E.db.unitframe.colors.healPrediction.personal (real ElvUI's healPrediction
-- keys). It starts at the end of the health fill and runs outward; the part
-- past the bar's right edge is the overheal, shown up to maxOverflow bar widths
-- beyond it, so a heal on a unit at full health is visible too. The amount is
-- the heal being cast plus the ticks still to come from the player's
-- heal-over-time spells on that unit, so a HoT's share shrinks tick by tick.
--
-- The 1.12 API has no incoming-heal query (UnitGetIncomingHeals is a Wrath
-- API), so the number is rebuilt the way pfUI's libs/libpredict.lua does on
-- vanilla, without its HealComm addon channel:
--   * Amounts are learned from the player's own heal messages and kept per
--     character in ElvCharacterDB.healPrediction, per spell AND rank
--     ("<spell>@<rank>"). A direct heal comes from CHAT_MSG_SPELL_SELF_BUFF
--     (the HEALEDSELF* / HEALEDCRITSELF* templates); a HoT tick from the
--     periodic events (PERIODICAURAHEALSELFSELF / PERIODICAURAHEALSELFOTHER),
--     stored under "<spell>@<rank>#tick". The client sends no tick message
--     while the unit is at full health, so a tick amount is only learned on a
--     damaged unit. The best non-critical value seen is kept; a critical heal
--     counts as 2/3 of its value until a normal one replaces it. A gear, talent
--     or new-spell change, and every login, flags every amount stale, and the
--     next landed heal of that key overwrites it instead of raising it.
--   * Which spell, rank and target a cast is comes from the call that started
--     it. UseAction, CastSpellByName and CastSpell are replaced with
--     pass-through wrappers that note the spell before calling the original:
--     UseAction reads name and rank from the slot's tooltip (first line, left
--     and right; there is no GetActionInfo), CastSpellByName parses
--     "Name(Rank N)", CastSpell asks GetSpellName. On Unreal Azeroth the action
--     button measurably calls the UseAction global, and a macro's /cast
--     measurably reaches the CastSpellByName wrapper, in combat too. A macro
--     slot is skipped in UseAction, since its tooltip names whatever the macro
--     shows, not what it casts; its /cast reaches CastSpellByName instead.
--   * SPELLCAST_START (name, cast time in ms) opens a direct heal's prediction
--     on the noted target; SPELLCAST_STOP, _INTERRUPTED and _FAILED close it,
--     _DELAYED pushes it back, and it also expires shortly after the cast time
--     on its own, in case no closing event arrives.
--   * A HoT starts at SPELLCAST_STOP: for an instant cast (Rejuvenation, Renew)
--     from the noted spell that raised no SPELLCAST_START, for Regrowth from
--     the cast that just ended without _INTERRUPTED or _FAILED. Its remaining
--     ticks are counted from that start with the fixed duration and interval in
--     HOT_SPELLS, and each tick message re-aligns the start. Recasting restarts
--     it. A HoT removed early (dispelled, overwritten, the unit died) keeps
--     predicting until its duration runs out, and set bonuses that lengthen a
--     HoT are not detected.
-- A key with no learned amount falls back to the same spell learned without a
-- rank, and otherwise predicts nothing. Other players' heals would need the
-- HealComm channel and are not handled. The message templates are matched as
-- the client defines them, with the English text as the fallback.

local E, L, V, P, G = unpack(ElvUI)
local UF = E:GetModule("UnitFrames")
local Compat = ElvUI.Compat

local SCAN_TOOLTIP = "ElvUIHealPredictScanTooltip"
-- Seconds a noted spell stays valid for the cast event that follows it.
local PENDING_WINDOW = 2
-- Seconds past the cast time or HoT duration before a prediction expires by itself.
local EXPIRY_GRACE = 0.5
-- Suffix of a learned HoT tick amount's key.
local TICK_SUFFIX = "#tick"

-- The player's heal-over-time spells, by localized name (names from pfUI's
-- libs/libpredict.lua). Duration and tick interval in seconds; the first tick
-- lands one interval after the aura (measured on Unreal Azeroth for
-- Rejuvenation: 4 ticks, 3 seconds apart).
local HOT_SPELLS = {
	{ duration = 12, interval = 3, names = {
		deDE = "Verjüngung", enUS = "Rejuvenation", esES = "Rejuvenecimiento", frFR = "Récupération",
		koKR = "회복", ruRU = "Омоложение", zhCN = "回春术",
	} },
	{ duration = 15, interval = 3, names = {
		deDE = "Erneuerung", enUS = "Renew", esES = "Renovar", frFR = "Rénovation",
		koKR = "소생", ruRU = "Обновление", zhCN = "恢复",
	} },
	{ duration = 21, interval = 3, names = {
		deDE = "Nachwachsen", enUS = "Regrowth", esES = "Recrecimiento", frFR = "Rétablissement",
		koKR = "재생", ruRU = "Восстановление", zhCN = "愈合",
	} },
}

local HOTS = {}
do
	local locale = (type(GetLocale) == "function" and GetLocale()) or "enUS"
	local i
	for i = 1, table.getn(HOT_SPELLS) do
		local spec = HOT_SPELLS[i]
		local name = spec.names[locale] or spec.names.enUS
		HOTS[name] = { duration = spec.duration, interval = spec.interval }
	end
end

-- The direct heal in flight: { target = name, amount = hp, expires = time }.
local active
-- The spell noted by the last cast call: { name, rank, target, time }.
local pending
-- The last spell that started casting: { name, rank, key, target, casting }.
-- The heal message after it credits its key; its end may start a HoT.
local lastCast
-- Set when the current cast raised _INTERRUPTED or _FAILED.
local castFailed
-- The player's HoTs: hots[targetName][spellName] = { start, duration, interval, rank }.
local hots = {}

-- ---------------------------------------------------------------------------
-- Learned amounts
-- ---------------------------------------------------------------------------

local function Amounts()
	if type(ElvCharacterDB) ~= "table" then return nil end
	if type(ElvCharacterDB.healPrediction) ~= "table" then
		ElvCharacterDB.healPrediction = {}
	end
	return ElvCharacterDB.healPrediction
end

local function SpellKey(name, rank)
	if type(rank) ~= "string" then rank = "" end
	return name .. "@" .. rank
end

-- entry = { amount, stale }
local function Learn(key, heal, crit)
	local amounts = Amounts()
	heal = tonumber(heal)
	if not amounts or not key or not heal then return end

	local entry = amounts[key]
	if not entry or entry[2] then
		entry = entry or {}
		entry[1] = crit and heal * 2 / 3 or heal
		entry[2] = crit and true or nil
		amounts[key] = entry
	elseif not crit and entry[1] < heal then
		entry[1] = heal
		entry[2] = nil
	end
end

local function LearnedAmount(name, rank, suffix)
	local amounts = Amounts()
	if not amounts then return nil end
	suffix = suffix or ""
	local entry = amounts[SpellKey(name, rank) .. suffix]
	if not entry and rank and rank ~= "" then
		entry = amounts[SpellKey(name, "") .. suffix]
	end
	return entry and tonumber(entry[1])
end

local function FlagStale()
	local amounts = Amounts()
	if not amounts then return end
	local key, entry
	for key, entry in pairs(amounts) do
		if type(entry) == "table" then entry[2] = true end
	end
end

local gearString
local function GearChanged()
	if type(GetInventoryItemLink) ~= "function" then return false end
	local gear = ""
	local slot
	for slot = 1, 18 do
		local ok, link = pcall(GetInventoryItemLink, "player", slot)
		gear = gear .. ((ok and link) or "")
	end
	if gear == gearString then return false end
	gearString = gear
	return true
end

-- ---------------------------------------------------------------------------
-- Heal messages
-- ---------------------------------------------------------------------------

-- "Your %s heals %s for %d." -> "^Your (.+) heals (.+) for (%d+)%.$"
local function TemplateToPattern(template)
	local pattern = string.gsub(template, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	pattern = string.gsub(pattern, "%%s", "(.+)")
	pattern = string.gsub(pattern, "%%d", "(%%d+)")
	return "^" .. pattern .. "$"
end

-- Capture positions within each template: spell, amount, and target (absent
-- when the target is the player). Critical templates come first: the plain
-- "heals" pattern also matches a critical message, with "critically"
-- swallowed into the spell name.
local HEAL_TEMPLATES = {
	{ global = "HEALEDCRITSELFSELF",  english = "Your %s critically heals you for %d.", spell = 1, amount = 2, crit = true },
	{ global = "HEALEDCRITSELFOTHER", english = "Your %s critically heals %s for %d.",  spell = 1, target = 2, amount = 3, crit = true },
	{ global = "HEALEDSELFSELF",      english = "Your %s heals you for %d.",            spell = 1, amount = 2 },
	{ global = "HEALEDSELFOTHER",     english = "Your %s heals %s for %d.",             spell = 1, target = 2, amount = 3 },
}

-- "You gain %d health from %s." also matches another player's HoT on the
-- player ("... from John's Rejuvenation."); that spell text is no HOTS name,
-- so it is ignored by the caller.
local TICK_TEMPLATES = {
	{ global = "PERIODICAURAHEALSELFSELF",  english = "You gain %d health from %s.",      amount = 1, spell = 2 },
	{ global = "PERIODICAURAHEALSELFOTHER", english = "%s gains %d health from your %s.", target = 1, amount = 2, spell = 3 },
}

local function CompileTemplates(specs)
	local compiled = {}
	local i
	for i = 1, table.getn(specs) do
		local spec = specs[i]
		local template = _G[spec.global]
		-- Positional templates ("%1$s") are not converted; the English text
		-- stands in for them.
		if type(template) ~= "string" or string.find(template, "$", 1, true) then
			template = spec.english
		end
		table.insert(compiled, {
			pattern = TemplateToPattern(template),
			spell = spec.spell, amount = spec.amount, target = spec.target, crit = spec.crit,
		})
	end
	return compiled
end

local healPatterns, tickPatterns

-- Returns spell, amount, target (nil when it is the player), crit.
local function MatchMessage(patterns, message)
	if type(message) ~= "string" then return nil end
	local i
	for i = 1, table.getn(patterns) do
		local spec = patterns[i]
		local found = { string.find(message, spec.pattern) }
		if found[1] then
			-- found[1], found[2] are positions; captures start at found[3].
			local target = spec.target and found[2 + spec.target]
			return found[2 + spec.spell], found[2 + spec.amount], target, spec.crit
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Cast tracking
-- ---------------------------------------------------------------------------

local function Refresh()
	if UF.UpdateAll then pcall(UF.UpdateAll, UF) end
end

local function CastTarget(onSelf)
	if not onSelf and UnitExists("target") and UnitCanAssist("player", "target") then
		return UnitName("target")
	end
	return UnitName("player")
end

local function Note(name, rank, target)
	if type(name) ~= "string" or name == "" then return end
	pending = { name = name, rank = rank, target = target, time = GetTime() }
end

local scanTooltip
local function ActionSpell(slot)
	if type(GetActionText) == "function" then
		local ok, macro = pcall(GetActionText, slot)
		if ok and type(macro) == "string" and macro ~= "" then return nil end
	end

	if not scanTooltip then
		local ok, tip = pcall(CreateFrame, "GameTooltip", SCAN_TOOLTIP, nil, "GameTooltipTemplate")
		if not ok or not tip then return nil end
		scanTooltip = tip
	end

	pcall(scanTooltip.SetOwner, scanTooltip, UIParent, "ANCHOR_NONE")
	pcall(scanTooltip.ClearLines, scanTooltip)
	local okSet = pcall(scanTooltip.SetAction, scanTooltip, slot)
	local left = _G[SCAN_TOOLTIP .. "TextLeft1"]
	local right = _G[SCAN_TOOLTIP .. "TextRight1"]
	local name = okSet and left and left:GetText()
	local rank = okSet and right and right:GetText()
	-- A scan tooltip left shown stays on screen (see DebuffDurations.lua).
	pcall(scanTooltip.Hide, scanTooltip)

	if type(name) ~= "string" or name == "" then return nil end
	if type(rank) ~= "string" then rank = nil end
	return name, rank
end

local function OnUseAction(slot, checkCursor, onSelf)
	slot = tonumber(slot)
	if not slot then return end
	local name, rank = ActionSpell(slot)
	Note(name, rank, CastTarget(Compat.bool(onSelf)))
end

local function OnCastSpellByName(text, onSelf)
	if type(text) ~= "string" then return end
	local _, _, name, rank = string.find(text, "^%s*(.-)%s*%((.-)%)%s*$")
	if not name then name = string.gsub(text, "^%s*(.-)%s*$", "%1") end
	Note(name, rank, CastTarget(Compat.bool(onSelf)))
end

local function OnCastSpell(id, bookType)
	if type(GetSpellName) ~= "function" then return end
	local ok, name, rank = pcall(GetSpellName, id, bookType)
	if ok then Note(name, rank, CastTarget(false)) end
end

-- The wrapper never lets the note-taking disturb the cast itself.
local function WrapGlobal(globalName, before)
	local original = _G[globalName]
	if type(original) ~= "function" then return end
	_G[globalName] = function(a1, a2, a3)
		pcall(before, a1, a2, a3)
		return original(a1, a2, a3)
	end
end

WrapGlobal("UseAction", OnUseAction)
-- Both documented protected on Unreal Azeroth; a macro's /cast through this
-- wrapper still casts there, in and out of combat, and delivers the rank.
WrapGlobal("CastSpellByName", OnCastSpellByName)
WrapGlobal("CastSpell", OnCastSpell)

local function StartHot(target, name, rank)
	local spec = HOTS[name]
	if not spec or type(target) ~= "string" or target == "" then return end
	hots[target] = hots[target] or {}
	hots[target][name] = { start = GetTime(), duration = spec.duration, interval = spec.interval, rank = rank }
	Refresh()
end

local function OnCastStart(name, castTime)
	if type(name) ~= "string" or name == "" then return end

	local rank, target
	if pending and pending.name == name and GetTime() - pending.time <= PENDING_WINDOW then
		rank, target = pending.rank, pending.target
	end
	pending = nil
	castFailed = false
	target = target or CastTarget(false)
	lastCast = { name = name, rank = rank, key = SpellKey(name, rank), target = target, casting = true }

	local amount = LearnedAmount(name, rank)
	local seconds = tonumber(castTime)
	if not amount or amount <= 0 or not seconds or seconds <= 0 or not target then return end

	active = { target = target, amount = amount, expires = GetTime() + seconds / 1000 + EXPIRY_GRACE }
	Refresh()
end

local function OnCastStop()
	if pending and HOTS[pending.name] and GetTime() - pending.time <= PENDING_WINDOW then
		-- An instant HoT: noted, never raised SPELLCAST_START.
		StartHot(pending.target, pending.name, pending.rank)
	elseif lastCast and lastCast.casting and not castFailed and HOTS[lastCast.name] then
		-- A HoT with a cast time (Regrowth) that finished.
		StartHot(lastCast.target, lastCast.name, lastCast.rank)
	end
	pending = nil
	if lastCast then lastCast.casting = false end
	if active then
		active = nil
		Refresh()
	end
end

local function OnCastFailed()
	castFailed = true
	pending = nil
	if active then
		active = nil
		Refresh()
	end
end

local function OnCastDelayed(delay)
	delay = tonumber(delay)
	if not active or not delay or delay <= 0 then return end
	active.expires = active.expires + delay / 1000
end

local function OnHealMessage(message)
	healPatterns = healPatterns or CompileTemplates(HEAL_TEMPLATES)
	local spell, heal, _, crit = MatchMessage(healPatterns, message)
	if spell and lastCast and lastCast.name == spell then
		Learn(lastCast.key, heal, crit)
	end
end

local function OnTickMessage(message)
	tickPatterns = tickPatterns or CompileTemplates(TICK_TEMPLATES)
	local spell, heal, target = MatchMessage(tickPatterns, message)
	if not spell or not HOTS[spell] then return end
	target = target or UnitName("player")

	local list = hots[target]
	local hot = list and list[spell]
	if not hot then
		Learn(SpellKey(spell, "") .. TICK_SUFFIX, heal, false)
		return
	end

	Learn(SpellKey(spell, hot.rank) .. TICK_SUFFIX, heal, false)
	-- Re-align the start on the tick that just landed.
	local now = GetTime()
	local ticks = math.floor((now - hot.start) / hot.interval + 0.5)
	if ticks < 1 then ticks = 1 end
	hot.start = now - ticks * hot.interval
end

local eventFrame = CreateFrame("Frame")
local EVENTS = {
	"SPELLCAST_START", "SPELLCAST_STOP", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED",
	"SPELLCAST_DELAYED", "CHAT_MSG_SPELL_SELF_BUFF",
	"CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
	"CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
	"PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED", "CHARACTER_POINTS_CHANGED",
	"LEARNED_SPELL_IN_TAB",
}
do
	local i
	for i = 1, table.getn(EVENTS) do
		eventFrame:RegisterEvent(EVENTS[i])
	end
end

local function OnEvent(eventName, a1, a2)
	if eventName == "SPELLCAST_START" then
		OnCastStart(a1, a2)
	elseif eventName == "SPELLCAST_STOP" then
		OnCastStop()
	elseif eventName == "SPELLCAST_FAILED" or eventName == "SPELLCAST_INTERRUPTED" then
		OnCastFailed()
	elseif eventName == "SPELLCAST_DELAYED" then
		OnCastDelayed(a1)
	elseif eventName == "CHAT_MSG_SPELL_SELF_BUFF" then
		OnHealMessage(a1)
	elseif eventName == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" or eventName == "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS"
		or eventName == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS" then
		OnTickMessage(a1)
	elseif eventName == "UNIT_INVENTORY_CHANGED" then
		if (a1 == nil or a1 == "player") and GearChanged() then FlagStale() end
	elseif eventName == "PLAYER_ENTERING_WORLD" then
		-- The gear of the previous session is unknown, so amounts learned
		-- then are treated as stale once per login.
		if not gearString then
			GearChanged()
			FlagStale()
		end
	elseif eventName == "CHARACTER_POINTS_CHANGED" or eventName == "LEARNED_SPELL_IN_TAB" then
		FlagStale()
	end
end

eventFrame:SetScript("OnEvent", function()
	pcall(OnEvent, event, arg1, arg2)
end)

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Healing still to come from the player's HoTs on the unit named `name`:
-- remaining ticks times the learned tick amount, per HoT.
local function HotHeal(name)
	local list = hots[name]
	if not list then return 0 end

	local now, total = GetTime(), 0
	local spell, hot
	for spell, hot in pairs(list) do
		local elapsed = now - hot.start
		if elapsed >= hot.duration + EXPIRY_GRACE then
			list[spell] = nil
		else
			local remaining = math.floor(hot.duration / hot.interval + 0.001) - math.floor(elapsed / hot.interval)
			local tick = remaining > 0 and LearnedAmount(spell, hot.rank, TICK_SUFFIX)
			if tick then total = total + remaining * tick end
		end
	end
	return total
end

local function IncomingHeal(unit)
	local name = UnitName(unit)
	if not name then return 0 end

	local amount = 0
	if active then
		if GetTime() >= active.expires then
			active = nil
		elseif name == active.target then
			amount = active.amount
		end
	end
	return amount + HotHeal(name)
end

-- The segment lives on its own child frame six levels above the health bar.
-- Relative to Health, an overlay portrait sits at +1 (its model at +2) and
-- the layer that re-draws the health state above it at +5 (the mirrored fill
-- in PortraitUA.lua, the missing-health cover in PortraitLegacy.lua); the
-- bar's text layer is at +10. Anything below +5 is darkened by that layer.
local function CreateSegment(bar)
	local holder = CreateFrame("Frame", nil, bar)
	holder:SetAllPoints(bar)
	local ok, level = pcall(bar.GetFrameLevel, bar)
	if ok and tonumber(level) then
		pcall(holder.SetFrameLevel, holder, level + 6)
	end
	local texture = holder:CreateTexture(nil, "ARTWORK")
	texture:Hide()
	bar.healPredictionSegment = texture
	return texture
end

function UF:UpdateHealPrediction(frame, unit, dbKey, health, healthMax, dead, texturePath)
	local bar = frame and frame.Health
	if not bar then return end

	local settings = E.db.unitframe.units[dbKey or unit]
	local amount = 0
	if settings and settings.healPrediction and not dead and healthMax and healthMax > 0 then
		amount = IncomingHeal(unit)
	end

	local segment = bar.healPredictionSegment
	if amount <= 0 then
		if segment then segment:Hide() end
		return
	end
	segment = segment or CreateSegment(bar)

	local colors = E.db.unitframe.colors.healPrediction
	local color = colors and colors.personal
	local maxOverflow = tonumber(colors and colors.maxOverflow) or 0

	-- From the end of the health fill outward for the heal's size, past the
	-- bar's right edge where it overheals, but no further than maxOverflow bar
	-- widths beyond that edge.
	local width = tonumber(bar:GetWidth()) or 0
	local healthWidth = width * health / healthMax
	if healthWidth > width then healthWidth = width end
	local healWidth = width * amount / healthMax
	local room = width * (1 + maxOverflow) - healthWidth
	if healWidth > room then healWidth = room end
	local start = healthWidth
	if healWidth < 1 then
		segment:Hide()
		return
	end

	if texturePath then pcall(segment.SetTexture, segment, texturePath) end
	if color then
		segment:SetVertexColor(color.r or 0, color.g or 1, color.b or 0.5, color.a or 0.25)
	end
	segment:ClearAllPoints()
	segment:SetPoint("TOPLEFT", bar, "TOPLEFT", start, 0)
	segment:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", start, 0)
	segment:SetWidth(healWidth)
	segment:Show()
end
