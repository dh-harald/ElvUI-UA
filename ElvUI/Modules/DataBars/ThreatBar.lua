-- Threat Bar -- the "Threat" sub-feature of real ElvUI's DataBars module
-- (retail Modules/DataBars/Threat.lua; ElvUI-vanilla has no such bar). The
-- module OBJECT is the shared `E.DataBars`, like XPBar.lua.
--
-- Shows the player's threat on the current target, in combat, with a pet or
-- in a group. Until its mover is moved it covers RightChatDataPanel, and the
-- datatexts come back as soon as it hides.
--
-- Neither client has a threat API: the numbers come from LibVanillaThreat-1.0,
-- whose UnitDetailedThreatSituation has Blizzard's semantics. The library only
-- knows the units running a copy of it. It treats a mob target with unknown
-- threat as having none, which would show a damage dealer as the tank at
-- 100%, so the bar stays hidden while the mob's target is such a unit.
--
-- Settings: `P.databars.threat` (Settings/Profile.lua).

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E.DataBars
local Compat = ElvUI.Compat

local THREAT_MOVER = "ThreatBarMover"
local THREAT_MOVER_POINT = "BOTTOMRIGHT,RightChatDataPanel,BOTTOMRIGHT,0,0"
-- The mob's target can change without any event.
local THREAT_POLL = 0.5
local OTHER_COLOR = { r = 194 / 255, g = 194 / 255, b = 194 / 255 }

-- GetThreatStatusColor of later clients, by threat status.
local THREAT_COLORS = {
	[0] = { 0.69, 0.69, 0.69 },
	[1] = { 1, 1, 0.47 },
	[2] = { 1, 0.6, 0 },
	[3] = { 1, 0, 0 },
}
-- A tank wants the opposite of a damage dealer (retail's tankStatus).
local TANK_STATUS = { [0] = 3, [1] = 2, [2] = 1, [3] = 0 }

local THREAT_EVENTS = {
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_TARGET_CHANGED",
}

local threatList = {}
local inCombat = false

-- Looked up on use: another addon's copy may be the one that loads.
local function ThreatLib()
	local lib = LibStub("LibVanillaThreat-1.0", true)
	if lib and lib.playerName then return lib end
	return nil
end

local function IsTank()
	local NP = E:GetModule("NamePlates", true)
	if not NP then return false end
	if not NP.role then NP:CheckRole() end
	return NP.role == "Tank"
end

-- The role follows talents, which change out of combat, and NamePlates only
-- tracks them while that module runs.
local function OnCombatChange(now)
	if now == inCombat then return end
	inCombat = now
	local NP = E:GetModule("NamePlates", true)
	if now and NP then NP:CheckRole() end
end

-- The player's threat on the target, or nil when there is nothing to show.
local function ReadThreat(lib)
	if not Compat.bool(UnitExists("pet")) and (GetNumPartyMembers() or 0) == 0
		and (GetNumRaidMembers() or 0) == 0 then
		return nil
	end
	if not Compat.bool(UnitExists("target")) then return nil end
	local mob = UnitName("target")
	if not mob then return nil end
	if Compat.bool(UnitExists("targettarget"))
		and not lib:GetThreat(UnitName("targettarget"), mob) then
		return nil
	end
	local _, status, percent = lib:UnitDetailedThreatSituation("player", "target")
	if percent then return mob, status, percent end
	-- No percent for a threat of zero, but the player is on the mob's list as
	-- soon as the pet is: retail shows 0% there.
	if lib:GetThreat(lib.playerName, mob) == 0 then return mob, 0, 0 end
	return nil
end

-- The highest threat share below the player's, and its holder's unit id.
local function LargestOther(lib, mob)
	lib:GetMobThreat(mob, threatList)
	local largest, largestUnit = 0, nil
	local name
	for name in pairs(threatList) do
		local unit = name ~= lib.playerName and lib:GetUnitByName(name)
		if unit then
			local _, _, percent = lib:UnitDetailedThreatSituation(unit, "target")
			if percent and percent > largest then
				largest, largestUnit = percent, unit
			end
		end
	end
	return largest, largestUnit
end

local function UnitColor(unit)
	if Compat.bool(UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then return color end
	end
	return OTHER_COLOR
end

-- Covers the datatext panel while the mover is unmoved, whatever the panel's
-- size. Not while movers are unlocked, so a drag is never fought.
local function PlaceThreatBar(bar)
	if E.moversUnlocked or E.db.movers[THREAT_MOVER] then return end
	local panel = _G.RightChatDataPanel
	if not panel then return end
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
end

function M:UpdateThreat()
	local bar = self.threatBar
	if not bar then return end
	local settings = self.db.threat

	OnCombatChange(Compat.bool(UnitAffectingCombat("player")))

	if not settings.enable then
		bar:Hide()
		return
	end

	-- A hidden bar would take its own mover handle down with it.
	if E.moversUnlocked then
		bar:Show()
		bar.statusBar:SetValue(0)
		bar.text:SetText("")
		return
	end

	local lib = inCombat and ThreatLib()
	local mob, status, percent
	if lib then mob, status, percent = ReadThreat(lib) end
	if not mob then
		bar:Hide()
		return
	end

	local isTank = IsTank()
	local value = percent
	local text = string.format("%s: %.0f%%", mob, percent)
	if percent == 100 then
		local largest, unit = LargestOther(lib, mob)
		if unit and percent > largest then
			local lead = percent - largest
			local color = UnitColor(unit)
			text = string.format(L["ABOVE_THREAT_FORMAT"], mob, percent, lead,
				math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255),
				UnitName(unit) or "")
			if isTank then value = lead end
		end
	end

	local colorStatus = status
	if isTank and settings.tankStatus then colorStatus = TANK_STATUS[status] end
	local color = THREAT_COLORS[colorStatus]

	if not bar:IsShown() then PlaceThreatBar(bar) end
	bar:Show()
	pcall(bar.statusBar.SetStatusBarColor, bar.statusBar, color[1], color[2], color[3], 0.8)
	bar.statusBar:SetValue(value)
	bar.text:SetText(settings.displayText and text or "")
end

function M:UpdateThreatDimensions()
	local bar = self.threatBar
	if not bar then return end
	local settings = self.db.threat

	pcall(bar.SetWidth, bar, settings.width)
	pcall(bar.SetHeight, bar, settings.height)

	local LSM = LibStub("LibSharedMedia-3.0", true)
	local path = LSM and LSM:Fetch("font", settings.font)
	if path then
		local outline = settings.fontOutline
		if outline == "NONE" or outline == "SHADOW" then outline = "" end
		pcall(bar.text.SetFont, bar.text, path, settings.fontSize, outline)
	end

	PlaceThreatBar(bar)
end

function M:LoadThreatBar()
	-- The fill colour comes from the threat status.
	self.threatBar = self:CreateBar("ElvUI_ThreatBar", { 0.69, 0.69, 0.69, 0.8 })
	local bar = self.threatBar
	bar.statusBar:SetMinMaxValues(0, 100)

	-- Retail's own default; once the chat exists PlaceThreatBar takes over.
	bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -4, 4)
	local mover = E:CreateMover(bar, THREAT_MOVER, L["Threat Bar"])
	if mover then mover.default = THREAT_MOVER_POINT end

	self:UpdateThreatDimensions()

	-- A frame of its own: AceEvent keeps one handler per event for this
	-- module, and the XP and reputation bars use these events as well.
	local i
	for i = 1, table.getn(THREAT_EVENTS) do
		bar:RegisterEvent(THREAT_EVENTS[i])
	end
	bar:SetScript("OnEvent", function() M:UpdateThreat() end)

	E:ScheduleRepeatingTimer(function() M:UpdateThreat() end, THREAT_POLL)
	self:UpdateThreat()
end
