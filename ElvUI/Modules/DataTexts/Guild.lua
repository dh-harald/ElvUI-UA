-- Guild DataText -- SIMPLIFIED port of real ElvUI's own Guild.lua
-- (source/ElvUI-vanilla/ElvUI/Modules/DataTexts/Guild.lua). Deliberately
-- dropped: the right-click invite/whisper dropdown menu (needs
-- `L_UIDropDownMenuTemplate`/`L_EasyMenu`, untested on UA, and is a
-- nice-to-have interaction shortcut, not core display functionality) --
-- right-click here just opens the native Guild frame instead, matching
-- the real version's own ELSE branch. Roster building/sorting, the
-- tooltip breakdown, and the member-count display are all kept.
-- Real ElvUI's own default assignment for this widget is
-- P["datatexts"]["panels"]["LeftMiniPanel"] = "Guild" -- matches this
-- project's own default (Settings/Profile.lua's P.datatexts.panels).

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts

local guildTable = {}
local guildMotD = ""

-- Accent-coloured VALUE half -- see Armor.lua's own note on why this is a
-- rebuilt format string and not a per-update format call. The no-guild text
-- has no value half at all, so it takes the accent WHOLE, matching real
-- ElvUI's own `noGuildString`.
local displayString = "Guild: %d"
local noGuildString = "No Guild"

local function ValueColorUpdate(hex)
	displayString = "Guild: "..hex.."%d|r"
	noGuildString = hex.."No Guild|r"
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

local function SortByName(a, b)
	if a and b then
		return a[1] < b[1]
	end
end

local function BuildGuildTable()
	guildTable = {}
	local totalMembers = GetNumGuildMembers()
	local i
	for i = 1, totalMembers do
		local name, rank, rankIndex, level, class, zone, note, officernote, connected = GetGuildRosterInfo(i)
		if not name then break end
		if connected then
			table.insert(guildTable, { name, rank, level, zone, note, officernote, connected, class and string.upper(class), rankIndex })
		end
	end
	table.sort(guildTable, SortByName)
end

local function OnEvent(self, event)
	if not IsInGuild() then
		self.text:SetText(noGuildString)
		return
	end

	if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" or event == "ELVUI_FORCE_RUN" then
		pcall(GuildRoster)
		BuildGuildTable()
		guildMotD = GetGuildRosterMOTD() or ""
	end

	self.text:SetText(string.format(displayString, table.getn(guildTable)))
end

local function OnClick()
	pcall(ToggleFriendsFrame, 3)
end

local function OnEnter(self)
	if not IsInGuild() then return end
	DT:SetupTooltip(self)

	local online, total = 0, GetNumGuildMembers(true)
	local i
	for i = 0, total do
		-- Positional capture, not `select(9, ...)`: `select` does not exist
		-- on the legacy client's Lua 5.0 at all. The 9th return is the
		-- online flag, same field `BuildGuildTable` above names `connected`.
		local _, _, _, _, _, _, _, _, connected = GetGuildRosterInfo(i)
		if connected then online = online + 1 end
	end
	if table.getn(guildTable) == 0 then BuildGuildTable() end

	local guildName, guildRank = GetGuildInfo("player")
	if guildName and guildRank then
		GameTooltip:AddDoubleLine(guildName, "Guild: "..online.."/"..total, 0.4, 0.78, 1, 0.4, 0.78, 1)
		GameTooltip:AddLine(guildRank, 0.4, 0.78, 1)
	end

	if guildMotD ~= "" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("MOTD |cffaaaaaa- |cffffffff"..guildMotD, 0.75, 0.9, 1, 1)
	end

	GameTooltip:AddLine(" ")
	local shown = 0
	for i = 1, table.getn(guildTable) do
		if shown >= 30 then break end
		local info = guildTable[i]
		local class = info[8]
		local classColor = (class and RAID_CLASS_COLORS[class]) or RAID_CLASS_COLORS.PRIEST
		local zoneColor = (GetRealZoneText() == info[4]) and { r = 0.3, g = 1, b = 0.3 } or { r = 0.65, g = 0.65, b = 0.65 }
		GameTooltip:AddDoubleLine(info[1].." ("..info[3]..")", info[4] or "", classColor.r, classColor.g, classColor.b, zoneColor.r, zoneColor.g, zoneColor.b)
		shown = shown + 1
	end

	GameTooltip:Show()
end

DT:RegisterDatatext("Guild", {"PLAYER_LOGIN", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE"}, OnEvent, nil, OnClick, OnEnter, nil, "Guild")
