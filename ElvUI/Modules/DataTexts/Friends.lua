-- Friends DataText -- SIMPLIFIED port of real ElvUI's own Friends.lua
-- (source/ElvUI-vanilla/ElvUI/Modules/DataTexts/Friends.lua).
-- Deliberately dropped: the right-click invite/whisper/set-AFK-DND
-- dropdown menu (same reasoning as Guild.lua -- needs
-- `L_UIDropDownMenuTemplate`/`L_EasyMenu`, untested on UA, a nice-to-have
-- shortcut) -- right-click here just opens the native Friends frame.
-- Roster building, the online-count display, and the tooltip breakdown
-- (respecting `E.db.datatexts.friends.hideAFK`/`hideDND`, matched to
-- real ElvUI's own field names exactly) are all kept.
-- Real ElvUI's own default assignment for this widget is
-- P["datatexts"]["panels"]["RightMiniPanel"] = "Friends" -- matches this
-- project's own default (Settings/Profile.lua's P.datatexts.panels).

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts

local friendTable = {}

-- Accent-coloured VALUE half -- see Armor.lua's own note on why this is a
-- rebuilt format string and not a per-update format call.
local displayString = "Friends: %d"

local function ValueColorUpdate(hex)
	displayString = "Friends: "..hex.."%d|r"
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

local function GetNumberFriends()
	local numFriends = GetNumFriends()
	local onlineFriends = 0
	local i
	for i = 1, numFriends do
		local _, _, _, _, online = GetFriendInfo(i)
		if online then onlineFriends = onlineFriends + 1 end
	end
	return numFriends, onlineFriends
end

local function SortByName(a, b)
	if a and b then
		return a[1] < b[1]
	end
end

local function BuildFriendTable(total)
	friendTable = {}
	local i
	for i = 1, total do
		local name, level, class, area, connected, status = GetFriendInfo(i)
		if connected then
			table.insert(friendTable, { name, level, class and string.upper(class), area, connected, status })
		end
	end
	table.sort(friendTable, SortByName)
end

local function OnEvent(self)
	local _, onlineFriends = GetNumberFriends()
	self.text:SetText(string.format(displayString, onlineFriends))
end

local function OnClick()
	pcall(ToggleFriendsFrame, 1)
end

local function OnEnter(self)
	DT:SetupTooltip(self)

	local numberOfFriends, onlineFriends = GetNumberFriends()
	GameTooltip:AddDoubleLine("Friends List", "Online: "..onlineFriends.."/"..numberOfFriends, 0.4, 0.78, 1, 0.4, 0.78, 1)

	if onlineFriends > 0 then
		BuildFriendTable(numberOfFriends)
		local i
		for i = 1, table.getn(friendTable) do
			local info = friendTable[i]
			local status = info[6] or ""
			local hideAFK = E.db.datatexts.friends and E.db.datatexts.friends.hideAFK
			local hideDND = E.db.datatexts.friends and E.db.datatexts.friends.hideDND
			local isAFK = string.find(status, "AFK") ~= nil
			local isDND = string.find(status, "DND") ~= nil
			if not ((isAFK and hideAFK) or (isDND and hideDND)) then
				local class = info[3]
				local classColor = (class and RAID_CLASS_COLORS[class]) or RAID_CLASS_COLORS.PRIEST
				local zoneColor = (GetRealZoneText() == info[4]) and { r = 0.3, g = 1, b = 0.3 } or { r = 0.65, g = 0.65, b = 0.65 }
				GameTooltip:AddDoubleLine(info[1].." ("..info[2]..") "..status, info[4] or "", classColor.r, classColor.g, classColor.b, zoneColor.r, zoneColor.g, zoneColor.b)
			end
		end
	end

	GameTooltip:Show()
end

DT:RegisterDatatext("Friends", {"PLAYER_LOGIN", "FRIENDLIST_UPDATE"}, OnEvent, nil, OnClick, OnEnter, nil, "Friends")
