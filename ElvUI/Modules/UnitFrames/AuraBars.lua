-- Aura bars on the player and target frames: real ElvUI's `aurabar`
-- element (retail ElvUI Elements/AuraBars.lua on top of oUF_AuraBars;
-- ElvUI-vanilla dropped it). Each aura with a known time is a row: its
-- icon on the left, a status bar that drains with the time left, the
-- aura's name (with "[n] " for stacks) on the left of the bar and the time
-- left on its right. Rows stack up (ABOVE) or down (BELOW) from what
-- `attachTo` names: the frame, or its buff or debuff icon grid while that
-- grid is shown.
--
-- Settings: units.<unit>.aurabar and unitframe.colors.auraBarBuff /
-- auraBarDebuff / auraBarByType (Settings/Profile.lua).
--
-- A friendly unit shows `friendlyAuraType` auras, a hostile one
-- `enemyAuraType` (HELPFUL / HARMFUL), as real ElvUI does. The 1.12 client
-- reports no aura caster and, apart from the player's own auras, no time,
-- so each source is:
--   * the player (on either frame): GetPlayerBuff* gives the exact time
--     left. The full duration is the time left when the aura appeared
--     between two reads; an aura already there at the first read takes
--     LibVanillaDurations-1.0's duration (or its current time left).
--   * another unit's debuffs: LibVanillaDurations-1.0, and only the
--     player's own (its stamp is `mine`, from Modules/UnitFrames/
--     OwnAuras.lua) -- real ElvUI's default "Personal" filter.
--   * another unit's buffs: only the player's own casts, timed by
--     UF:GetOwnAuraTimeLeft (OwnAuras.lua).
-- Auras without a time are left out (real ElvUI's "blockNoDuration").
-- minDuration / maxDuration compare the full duration (0 = no limit).
--
-- UF:UpdateFrame calls UF:UpdateAuraBars on every poll pass (0.2s), after
-- the aura icon grids have been placed; a shared 0.05s timer moves the
-- bars and time texts in between. Every row is hidden on its own: on
-- Unreal Azeroth a parent's Hide does not hide its children.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local UF = E.UnitFrames
local Util = ElvUI.Util
local Compat = ElvUI.Compat

local LSM = LibStub("LibSharedMedia-3.0", true)
local LVD = LibStub("LibVanillaDurations-1.0", true)

local MAX_BUFFS = 32
local MAX_DEBUFFS = 16
-- Space between the icon and the bar, and between the bars and what they
-- are attached to.
local ICON_GAP = 2
local ATTACH_GAP = 4
-- Background of the unfilled part: the bar colour times this.
local BG_MULT = 0.25
local VALUE_INTERVAL = 0.05
-- A player aura missing from a read at most this old, and present in the
-- next one, is taken as just applied.
local SEEN_WINDOW = 1

local SCAN_TIP = "ElvUIAuraBarScanTooltip"

-- ---------------------------------------------------------------------
-- Aura names (tooltip scan)
-- ---------------------------------------------------------------------

local scanTip

-- First line of the tooltip that tip[method](tip, a1, a2) fills. The owner
-- is set on every scan: the Hide at the end clears it, and on the 1.12
-- client an unowned tooltip is not filled.
local function ScanName(method, a1, a2)
	if not scanTip then
		local ok, tip = pcall(CreateFrame, "GameTooltip", SCAN_TIP, nil, "GameTooltipTemplate")
		if not ok or not tip then return nil end
		scanTip = tip
	end
	pcall(scanTip.SetOwner, scanTip, UIParent, "ANCHOR_NONE")
	pcall(scanTip.ClearLines, scanTip)
	local name
	if pcall(scanTip[method], scanTip, a1, a2) then
		local line = _G[SCAN_TIP.."TextLeft1"]
		name = line and line:GetText()
	end
	pcall(scanTip.Hide, scanTip)
	if name == "" then name = nil end
	return name
end

-- Names per slot, re-scanned only when the slot's texture changes.
-- names[cacheKey][index] = { texture, name }
local names = {}

local function CachedName(cacheKey, index, texture, method, a1, a2)
	local cache = names[cacheKey]
	if not cache then
		cache = {}
		names[cacheKey] = cache
	end
	local slot = cache[index]
	if not slot or slot.texture ~= texture then
		slot = { texture = texture, name = ScanName(method, a1, a2) }
		cache[index] = slot
	end
	return slot.name
end

-- ---------------------------------------------------------------------
-- Aura sources
-- ---------------------------------------------------------------------

-- Per filter (HELPFUL / HARMFUL): seen[key] = { duration, left, read },
-- `read` being the read that last saw the aura.
local playerState = {}

local function PlayerState(filter)
	local state = playerState[filter]
	if not state then
		state = { seen = {}, reads = 0 }
		playerState[filter] = state
	end
	return state
end

local function PlayerDuration(state, key, name, left, recent)
	local s = state.seen[key]
	if not s then
		local duration = left
		if not recent then
			local known = name and LVD and LVD:GetDuration(name)
			if known and known >= left then duration = known end
		end
		s = { duration = duration }
		state.seen[key] = s
	elseif left > s.left + 0.5 then
		-- Re-applied: the full duration starts again.
		s.duration = left
	end
	if left > s.duration then s.duration = left end
	s.left = left
	s.read = state.reads
	return s.duration
end

-- Auras are tracked by texture. One whose time left is already past
-- maxDuration is only tracked, without a name lookup: its full duration can
-- only be longer, and keeping it tracked stops it from counting as newly
-- applied once its time left drops under the limit.
local function AddPlayerAuras(list, filter, maxDuration)
	local state = PlayerState(filter)
	local now = GetTime()
	local recent = state.last and now - state.last <= SEEN_WINDOW
	state.reads = state.reads + 1
	state.last = now

	local i
	for i = 1, MAX_BUFFS do
		local ok, buffIndex = pcall(GetPlayerBuff, i - 1, filter)
		if not ok or not buffIndex or buffIndex < 0 then break end
		local _, left = pcall(GetPlayerBuffTimeLeft, buffIndex)
		left = tonumber(left)
		local _, texture = pcall(GetPlayerBuffTexture, buffIndex)
		local key = tostring(texture)
		if left and left > 0 and maxDuration > 0 and left > maxDuration then
			PlayerDuration(state, key, nil, left, recent)
		elseif left and left > 0 then
			local _, count = pcall(GetPlayerBuffApplications, buffIndex)
			local name = CachedName("player"..filter, buffIndex, texture, "SetPlayerBuff", buffIndex)
			local debuffType
			if filter == "HARMFUL" then
				local _, t = pcall(GetPlayerBuffDispelType, buffIndex)
				debuffType = t
			end
			table.insert(list, {
				index = i, buffIndex = buffIndex, filter = filter, name = name or "",
				texture = texture, count = tonumber(count), debuffType = debuffType,
				duration = PlayerDuration(state, key, name, left, recent),
				expiration = now + left,
			})
		end
	end

	local key, s
	for key, s in pairs(state.seen) do
		if s.read ~= state.reads then state.seen[key] = nil end
	end
end

-- The player's own debuffs on another unit (LibVanillaDurations-1.0).
-- Every slot is read: on Unreal Azeroth a debuff can follow an empty one.
local function AddUnitDebuffs(list, unit)
	if not LVD then return end
	local unitName = UnitName(unit)
	local now = GetTime()
	local i
	for i = 1, MAX_DEBUFFS do
		local ok, texture, count, debuffType = pcall(UnitDebuff, unit, i)
		if ok and texture then
			local name, left, duration = LVD:GetDebuff(unit, i)
			local _, _, mine = LVD:GetStamp(unitName, name)
			if name and mine and left and left > 0 and duration then
				table.insert(list, {
					index = i, filter = "HARMFUL", name = name, texture = texture,
					count = tonumber(count), debuffType = debuffType,
					duration = duration, expiration = now + left,
				})
			end
		end
	end
end

-- The player's own buffs on another unit (OwnAuras.lua).
local function AddUnitBuffs(list, unit)
	if not UF.GetOwnAuraTimeLeft then return end
	local unitName = UnitName(unit)
	local now = GetTime()
	local i
	for i = 1, MAX_BUFFS do
		local ok, texture, count = pcall(UnitBuff, unit, i)
		if not ok or not texture then break end
		local name = CachedName(unit, i, texture, "SetUnitBuff", unit, i)
		local left, duration = UF:GetOwnAuraTimeLeft(unitName, name)
		if name and left then
			table.insert(list, {
				index = i, filter = "HELPFUL", name = name, texture = texture,
				count = tonumber(count), duration = duration, expiration = now + left,
			})
		end
	end
end

local function Collect(unit, db)
	local list = {}
	local friendly = Compat.bool(UnitIsFriend("player", unit))
	local filter = friendly and db.friendlyAuraType or db.enemyAuraType
	if filter ~= "HARMFUL" then filter = "HELPFUL" end

	if Compat.bool(UnitIsUnit(unit, "player")) then
		AddPlayerAuras(list, filter, tonumber(db.maxDuration) or 0)
	elseif filter == "HARMFUL" then
		AddUnitDebuffs(list, unit)
	else
		AddUnitBuffs(list, unit)
	end
	return list
end

-- ---------------------------------------------------------------------
-- Filtering and sorting
-- ---------------------------------------------------------------------

local SORT_KEYS = {
	TIME_REMAINING = "expiration",
	DURATION = "duration",
	NAME = "name",
	INDEX = "index",
}

local function FilterAndSort(list, db)
	local minDuration = tonumber(db.minDuration) or 0
	local maxDuration = tonumber(db.maxDuration) or 0
	local kept = {}
	local i
	for i = 1, Compat.getn(list) do
		local aura = list[i]
		if (minDuration <= 0 or aura.duration >= minDuration)
			and (maxDuration <= 0 or aura.duration <= maxDuration) then
			table.insert(kept, aura)
		end
	end

	local key = SORT_KEYS[db.sortMethod] or "expiration"
	local ascending = db.sortDirection == "ASCENDING"
	table.sort(kept, function(a, b)
		if a[key] == b[key] then return a.index < b.index end
		if ascending then return a[key] < b[key] end
		return a[key] > b[key]
	end)
	return kept
end

-- ---------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------

local function BarTexture()
	return (LSM and LSM:Fetch("statusbar", E.db.unitframe.statusbar)) or "Interface\\Buttons\\WHITE8x8"
end

local function ApplyFont(text)
	local db = E.db.unitframe
	local font = (LSM and LSM:Fetch("font", db.font)) or "Fonts\\FRIZQT__.TTF"
	local outline = db.fontOutline
	if outline == "NONE" then outline = "" end
	pcall(text.SetFont, text, font, db.fontSize, outline)
end

local function Row_OnEnter()
	local aura = this.aura
	if not aura or not Compat.bool(this:IsVisible()) then return end
	GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
	if aura.buffIndex then
		pcall(GameTooltip.SetPlayerBuff, GameTooltip, aura.buffIndex)
	elseif aura.filter == "HELPFUL" then
		pcall(GameTooltip.SetUnitBuff, GameTooltip, this.unit, aura.index)
	else
		pcall(GameTooltip.SetUnitDebuff, GameTooltip, this.unit, aura.index)
	end
	GameTooltip:Show()
end

local function Row_OnLeave()
	GameTooltip:Hide()
end

-- Right-click cancels one of the player's own buffs, like the aura icons.
local function Row_OnMouseUp()
	local aura = this.aura
	if arg1 ~= "RightButton" or not aura or not aura.buffIndex or aura.filter ~= "HELPFUL" then return end
	pcall(CancelPlayerBuff, aura.buffIndex)
end

local function CreateRow(holder)
	local row = CreateFrame("Frame", nil, holder)
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", Row_OnLeave)
	row:SetScript("OnMouseUp", Row_OnMouseUp)

	local iconFrame = CreateFrame("Frame", nil, row)
	E:SetTemplate(iconFrame, "Default")
	local icon = iconFrame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local barFrame = CreateFrame("Frame", nil, row)
	E:SetTemplate(barFrame, "Default")
	local bar = Util.CreateStatusBar(barFrame, { texture = BarTexture() })
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -1, 1)

	local spark = bar:CreateTexture(nil, "OVERLAY")
	spark:SetTexture("Interface\\Buttons\\WHITE8x8")
	spark:SetVertexColor(0.9, 0.9, 0.9, 0.6)
	spark:SetWidth(2)
	spark:SetPoint("TOPRIGHT", bar.barFillTexture, "TOPRIGHT", 0, 0)
	spark:SetPoint("BOTTOMRIGHT", bar.barFillTexture, "BOTTOMRIGHT", 0, 0)

	-- Text on its own raised layer: the fill texture is redrawn on every
	-- value change and could otherwise cover text on the same frame.
	local textLayer = CreateFrame("Frame", nil, bar)
	textLayer:SetAllPoints(bar)
	local ok, level = pcall(bar.GetFrameLevel, bar)
	if ok and tonumber(level) then pcall(textLayer.SetFrameLevel, textLayer, level + 5) end

	local timeText = textLayer:CreateFontString(nil, "OVERLAY")
	ApplyFont(timeText)
	timeText:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
	timeText:SetJustifyH("RIGHT")

	local nameText = textLayer:CreateFontString(nil, "OVERLAY")
	ApplyFont(nameText)
	nameText:SetPoint("LEFT", bar, "LEFT", 2, 0)
	nameText:SetPoint("RIGHT", timeText, "LEFT", -2, 0)
	nameText:SetJustifyH("LEFT")

	row.iconFrame, row.icon = iconFrame, icon
	row.barFrame, row.bar, row.spark = barFrame, bar, spark
	row.nameText, row.timeText = nameText, timeText
	return row
end

local function HideRow(row)
	row.aura = nil
	row:Hide()
	row.iconFrame:Hide()
	row.barFrame:Hide()
	row.bar:Hide()
	row.spark:Hide()
	row.nameText:Hide()
	row.timeText:Hide()
end

local function ShowRow(row)
	row:Show()
	row.iconFrame:Show()
	row.barFrame:Show()
	row.bar:Show()
	row.spark:Show()
	row.nameText:Show()
	row.timeText:Show()
end

local function BarColor(aura)
	local colors = E.db.unitframe.colors
	if aura.filter ~= "HARMFUL" then return colors.auraBarBuff end
	local typeColors = _G.DebuffTypeColor
	if colors.auraBarByType and aura.debuffType and typeColors and typeColors[aura.debuffType] then
		return typeColors[aura.debuffType]
	end
	return colors.auraBarDebuff
end

local function UpdateValue(row, now)
	local aura = row.aura
	if not aura then return end
	local left = aura.expiration - now
	if left < 0 then left = 0 end
	row.bar:SetValue(left)
	row.timeText:SetText(UF:FormatDebuffTimeLeft(left))
end

local function FillRow(row, aura, unit, height, db)
	row.aura = aura
	row.unit = unit
	row.iconFrame:SetWidth(height)
	row.iconFrame:SetHeight(height)
	pcall(row.icon.SetTexture, row.icon, aura.texture)

	local text = aura.name
	if aura.count and aura.count > 1 then text = "["..aura.count.."] "..text end
	row.nameText:SetText(text)

	local c = BarColor(aura)
	Util.SetStatusBarTexture(row.bar, BarTexture())
	Util.SetStatusBarColor(row.bar, c.r, c.g, c.b)
	Util.SetStatusBarBackgroundColor(row.bar, c.r * BG_MULT, c.g * BG_MULT, c.b * BG_MULT)
	row.bar:SetMinMaxValues(0, aura.duration)
	pcall(row.EnableMouse, row, not db.clickThrough)
	ShowRow(row)
	UpdateValue(row, GetTime())
end

-- ---------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------

-- What the bars hang off, and whether they line up with its right edge.
-- An icon grid counts only while it is shown; an empty one falls back to
-- the frame.
local function AttachTarget(frame, db)
	local key = (db.attachTo == "DEBUFFS" and "debuffs") or (db.attachTo == "BUFFS" and "buffs")
	local grid = (key == "debuffs" and frame.Debuffs) or (key == "buffs" and frame.Buffs)
	if grid and Compat.bool(grid:IsShown()) then
		local settings = E.db.unitframe.units[frame.unitDBKey or frame.unit]
		local point = settings and settings[key] and settings[key].anchorPoint
		return grid, point and string.find(point, "RIGHT") and "RIGHT" or "LEFT"
	end
	return frame, "LEFT"
end

local function LayoutRows(holder, count, height, spacing, below)
	local i
	for i = 1, count do
		local row = holder.rows[i]
		local offset = (i - 1) * (height + spacing)
		row:ClearAllPoints()
		if below then
			row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset)
			row:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -offset)
		else
			row:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, offset)
			row:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, offset)
		end
		row:SetHeight(height)
		row.iconFrame:ClearAllPoints()
		row.iconFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.barFrame:ClearAllPoints()
		row.barFrame:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", ICON_GAP, 0)
		row.barFrame:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	end
end

local function PlaceHolder(holder, frame, db, count, height, spacing)
	local ref, side = AttachTarget(frame, db)
	local below = db.anchorPoint == "BELOW"
	local gap = ATTACH_GAP + (tonumber(db.yOffset) or 0)
	holder:ClearAllPoints()
	if below then
		holder:SetPoint("TOP"..side, ref, "BOTTOM"..side, 0, -gap)
	else
		holder:SetPoint("BOTTOM"..side, ref, "TOP"..side, 0, gap)
	end
	holder:SetWidth(frame:GetWidth())
	holder:SetHeight(count * height + (count - 1) * spacing)
	LayoutRows(holder, count, height, spacing, below)
end

local function HideHolder(holder)
	local i
	for i = 1, Compat.getn(holder.rows) do
		HideRow(holder.rows[i])
	end
	holder.active = 0
	holder:Hide()
end

-- ---------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------

local valueTimer

local function UpdateAllValues()
	local now = GetTime()
	local _, frame
	for _, frame in pairs(UF.Frames) do
		local holder = frame.AuraBars
		if holder and holder.active and holder.active > 0 then
			local i
			for i = 1, holder.active do
				UpdateValue(holder.rows[i], now)
			end
		end
	end
end

local function GetHolder(frame)
	if frame.AuraBars then return frame.AuraBars end
	local holder = CreateFrame("Frame", nil, frame)
	local ok, level = pcall(frame.GetFrameLevel, frame)
	if ok and tonumber(level) then pcall(holder.SetFrameLevel, holder, level + 5) end
	holder.rows = {}
	holder.active = 0
	frame.AuraBars = holder
	if not valueTimer then
		valueTimer = E:ScheduleRepeatingTimer(UpdateAllValues, VALUE_INTERVAL)
	end
	return holder
end

function UF:HideAuraBars(frame)
	if frame.AuraBars then HideHolder(frame.AuraBars) end
end

-- `settings`: the frame's unit settings table (units.<unit>).
function UF:UpdateAuraBars(frame, unit, settings)
	local db = settings and settings.aurabar
	if not db or not db.enable then return self:HideAuraBars(frame) end

	local auras = FilterAndSort(Collect(unit, db), db)
	local count = Compat.getn(auras)
	local maxBars = tonumber(db.maxBars) or 6
	if count > maxBars then count = maxBars end
	if count == 0 then return self:HideAuraBars(frame) end

	local holder = GetHolder(frame)
	local height = tonumber(db.height) or 20
	local spacing = tonumber(db.spacing) or 0
	local i
	for i = 1, count do
		if not holder.rows[i] then holder.rows[i] = CreateRow(holder) end
		FillRow(holder.rows[i], auras[i], unit, height, db)
	end
	for i = count + 1, Compat.getn(holder.rows) do
		HideRow(holder.rows[i])
	end
	holder.active = count
	PlaceHolder(holder, frame, db, count, height, spacing)
	holder:Show()
end
