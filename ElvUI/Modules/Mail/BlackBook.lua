-- Recipient completion for the Send Mail tab: Tab fills in a name from the
-- people this character can plausibly write to.
--
-- Three sources, merged and de-duplicated: this account's own characters,
-- the friend list, and the guild roster. Nothing is stored for it. Mail
-- RECIPIENTS are deliberately not remembered.
--
-- The account's own characters come from `ElvDB.profileKeys`, whose keys are
-- `"Name - Realm"` and which gains an entry for every character that logs in
-- (`Init.lua:119-126`) -- so the list this addon already keeps for profiles
-- doubles as the list no game API offers. Filtered to the current realm,
-- because a name means a different person on another one.
--
-- A DROPPED-DOWN LIST, not an inline completion: the usual "write the rest of
-- the name and select it" trick needs `HighlightText`, which selects nothing
-- on Unreal Azeroth -- typed characters would land after the completion
-- instead of replacing it. Legacy would take it, but a completion that
-- behaves differently per client is worse than one that behaves the same on
-- both, so neither gets it. (The same call is avoided in the bag search box
-- for the same reason.)
--
-- Typing therefore opens a short list under the field: click a name, or press
-- Tab to take the first. With nothing to offer, Tab does what it natively
-- does and moves on to the subject field.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Mail")
local Compat = ElvUI.Compat
local getn = Compat.getn

-- `E.myrealm` rather than `GetRealmName()`: the profile keys are built from
-- that one (`Init.lua:119`), so matching against anything else risks never
-- lining up.
local function Realm()
	if E.myrealm and E.myrealm ~= "" then return E.myrealm end
	local ok, realm = pcall(GetRealmName)
	if ok and realm and realm ~= "" then return realm end
	return "Unknown"
end

-- Own name never enters the list, from ANY source: the guild roster carries
-- it too, and the client refuses mail addressed to yourself.
local function AddName(list, seen, name)
	if type(name) ~= "string" or name == "" then return end
	if E.myname and name == E.myname then return end
	local key = string.lower(name)
	if seen[key] then return end
	seen[key] = true
	table.insert(list, name)
end

local function OwnCharacters(list, seen)
	local db = _G.ElvDB
	local keys = db and db.profileKeys
	if type(keys) ~= "table" then return end

	local realm = Realm()
	for key in pairs(keys) do
		local _, _, name, keyRealm = string.find(key, "^(.+) %- (.+)$")
		if name and keyRealm == realm then AddName(list, seen, name) end
	end
end

local function Candidates()
	local list, seen = {}, {}

	OwnCharacters(list, seen)

	local okFriends, count = pcall(GetNumFriends)
	if okFriends and count then
		local i
		for i = 1, count do
			local okName, name = pcall(GetFriendInfo, i)
			if okName then AddName(list, seen, name) end
		end
	end

	local okGuild, inGuild = pcall(IsInGuild)
	if okGuild and Compat.bool(inGuild) then
		local okCount, members = pcall(GetNumGuildMembers)
		if okCount and members then
			local i
			for i = 1, members do
				local okName, name = pcall(GetGuildRosterInfo, i)
				if okName then AddName(list, seen, name) end
			end
		end
	end

	return list
end

local function Matches(prefix)
	local wanted = string.lower(prefix)
	local length = string.len(wanted)
	local all = Candidates()
	local hits = {}
	local i
	for i = 1, getn(all) do
		if string.lower(string.sub(all[i], 1, length)) == wanted then
			table.insert(hits, all[i])
		end
	end
	return hits
end

-- At most five rows: a completion list is a shortcut, and a longer one asks
-- to be read rather than glanced at.
local MAX_ROWS = 5
local ROW_HEIGHT = 14
local PADDING = 3

local popup
local rows = {}

local function HidePopup()
	if popup then pcall(popup.Hide, popup) end
end

local function Accept(box, name)
	if not name then return end
	pcall(box.SetText, box, name)
	-- Remembered so the SetText above, which fires OnTextChanged, does not
	-- immediately reopen the list on the name it just accepted.
	M.acAccepted = name
	HidePopup()
end

local function BuildPopup(box)
	local parent = box:GetParent() or _G.SendMailFrame
	popup = CreateFrame("Frame", "ElvUI_MailRecipientList", parent)
	E:SetTemplate(popup, "Default")
	-- Above everything this window draws, text included: the list overlaps the
	-- subject field and the letter body by design, and at the mail frame's own
	-- strata those would draw over it instead.
	pcall(popup.SetFrameStrata, popup, "TOOLTIP")
	pcall(popup.SetFrameLevel, popup, 100)
	pcall(popup.SetToplevel, popup, true)
	pcall(popup.SetPoint, popup, "TOPLEFT", box, "BOTTOMLEFT", 0, -2)
	local okWidth, width = pcall(box.GetWidth, box)
	pcall(popup.SetWidth, popup, (okWidth and width) or 120)
	popup:Hide()

	local i
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, popup)
		local offset = PADDING + (i - 1) * ROW_HEIGHT
		pcall(row.SetHeight, row, ROW_HEIGHT)
		pcall(row.SetPoint, row, "TOPLEFT", popup, "TOPLEFT", PADDING, -offset)
		pcall(row.SetPoint, row, "TOPRIGHT", popup, "TOPRIGHT", -PADDING, -offset)

		local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		pcall(text.SetPoint, text, "LEFT", row, "LEFT", 2, 0)
		pcall(text.SetJustifyH, text, "LEFT")
		row.elvText = text

		-- The skin's own accent, NOT the profile's value colour: that one is
		-- class-coloured in most profiles, which reads as a different kind of
		-- control here. Same choice as the checkbox ticks in the inbox.
		row:SetScript("OnEnter", function()
			local S = E:GetModule("Skins")
			local accent = S and S.ACCENT_COLOR
			if accent then pcall(text.SetTextColor, text, accent[1], accent[2], accent[3]) end
		end)
		row:SetScript("OnLeave", function() pcall(text.SetTextColor, text, 1, 1, 1) end)
		row:SetScript("OnClick", function() Accept(box, row.elvName) end)

		rows[i] = row
	end
end

-- Rebuilt on every keystroke: the sources are cheap to read and always
-- current, so there is nothing to cache and nothing to go stale.
local function Refresh(box)
	if not popup then return end

	local okText, text = pcall(box.GetText, box)
	if not (okText and text) or text == "" or text == M.acAccepted then
		return HidePopup()
	end

	local hits = Matches(text)
	local shown = getn(hits)
	if shown > MAX_ROWS then shown = MAX_ROWS end
	if shown == 0 then return HidePopup() end

	local i
	for i = 1, MAX_ROWS do
		local row = rows[i]
		if i <= shown then
			row.elvName = hits[i]
			pcall(row.elvText.SetText, row.elvText, hits[i])
			pcall(row.elvText.SetTextColor, row.elvText, 1, 1, 1)
			row:Show()
		else
			row.elvName = nil
			row:Hide()
		end
	end

	pcall(popup.SetHeight, popup, shown * ROW_HEIGHT + PADDING * 2)
	popup:Show()
end

function M:LoadBlackBook()
	local box = _G.SendMailNameEditBox
	if not box or box.elvBlackBook then return end
	box.elvBlackBook = true

	BuildPopup(box)

	local previousTab = box:GetScript("OnTabPressed")
	box:SetScript("OnTabPressed", function()
		if popup and popup:IsShown() and rows[1] and rows[1].elvName then
			return Accept(box, rows[1].elvName)
		end
		if previousTab then previousTab() end
	end)

	local previousChanged = box:GetScript("OnTextChanged")
	box:SetScript("OnTextChanged", function()
		if E.global and E.global.mail and E.global.mail.autoComplete then
			Refresh(box)
		else
			HidePopup()
		end
		if previousChanged then previousChanged() end
	end)

	-- The list belongs to the field, so it goes away with it: leaving the
	-- field, sending, or switching tabs all end up here.
	local previousFocus = box:GetScript("OnEditFocusLost")
	box:SetScript("OnEditFocusLost", function()
		-- Clicking a row takes focus off the field, which lands here BEFORE
		-- the row's own click runs -- hiding the list then would swallow the
		-- very choice being made. So the list survives while the pointer is
		-- on it, and the click closes it a moment later.
		local over = _G.MouseIsOver and popup and _G.MouseIsOver(popup)
		if not over then HidePopup() end
		if previousFocus then previousFocus() end
	end)
	M:SecureHook("SendMailFrame_Reset", function() HidePopup() end)
end
