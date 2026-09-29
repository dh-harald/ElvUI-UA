-- Watch the faction whose reputation just rose (general.autoTrackReputation),
-- as retail ElvUI's Misc does. Trigger: COMBAT_TEXT_UPDATE of type
-- "FACTION"; the faction name and the amount arrive in the globals arg2 and
-- arg3 (the handler's own arguments are empty on Unreal Azeroth).
--
-- Only a gain switches the watch, and only to a faction other than the one
-- already watched. SetWatchedFactionIndex takes an index among the VISIBLE
-- rows of the reputation list, so collapsed headers are expanded for the
-- search and collapsed again afterwards (retail leaves them open); the watch
-- is kept per faction, so collapsing again does not undo it. Skipped while
-- the Reputation frame is open, where the list would visibly jump.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Misc")
local Compat = ElvUI.Compat

-- Upper bound for the list walks; the whole list is well below it.
local MAX_ROWS = 300

local function NumFactions()
	local ok, n = pcall(GetNumFactions)
	return (ok and tonumber(n)) or 0
end

-- name, isHeader, isCollapsed of list row `i`.
local function FactionRow(i)
	local ok, name, _, _, _, _, _, _, _, isHeader, isCollapsed = pcall(GetFactionInfo, i)
	if not ok then return nil end
	return name, Compat.bool(isHeader), Compat.bool(isCollapsed)
end

-- Expands every collapsed header; returns the set of their names. Expanding
-- inserts rows below the header, so the count is re-read on every step.
local function ExpandAll()
	local expanded = {}
	local i = 1
	while i <= NumFactions() and i <= MAX_ROWS do
		local name, isHeader, isCollapsed = FactionRow(i)
		if isHeader and isCollapsed and name then
			pcall(ExpandFactionHeader, i)
			expanded[name] = true
		end
		i = i + 1
	end
	return expanded
end

-- Collapses the headers ExpandAll opened, bottom up so the indices above
-- stay valid.
local function CollapseAgain(expanded)
	local i
	for i = math.min(NumFactions(), MAX_ROWS), 1, -1 do
		local name, isHeader, isCollapsed = FactionRow(i)
		if isHeader and not isCollapsed and name and expanded[name] then
			pcall(CollapseFactionHeader, i)
		end
	end
end

local function WatchFaction(faction)
	local expanded = ExpandAll()
	local i
	for i = 1, math.min(NumFactions(), MAX_ROWS) do
		local name, isHeader = FactionRow(i)
		if name == faction and not isHeader then
			pcall(SetWatchedFactionIndex, i)
			break
		end
	end
	CollapseAgain(expanded)
end

local function OnCombatText()
	if arg1 ~= "FACTION" then return end
	if not (E.db.general and E.db.general.autoTrackReputation) then return end

	local faction, amount = arg2, tonumber(arg3)
	if type(faction) ~= "string" or faction == "" or not amount or amount <= 0 then return end

	local ok, watched = pcall(GetWatchedFactionInfo)
	if ok and watched == faction then return end

	local rep = _G.ReputationFrame
	if rep and rep.IsVisible and Compat.bool(rep:IsVisible()) then return end

	pcall(WatchFaction, faction)
end

function M:LoadAutoTrackReputation()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("COMBAT_TEXT_UPDATE")
	frame:SetScript("OnEvent", OnCombatText)
end
