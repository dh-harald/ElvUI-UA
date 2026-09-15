-- Skins > Blizzard > Friends -- reskins the native FriendsFrame ("Social"
-- window) IN PLACE. Same recipe as Blizzard/Character.lua: strip native
-- chrome, SetBackdrop on a separate `elvBackground` child frame (never
-- directly on the native frame -- see Skins.lua's own StripTextures
-- comment for why), ElvUI.Util.CreateButtonBorder for anything
-- button-shaped, S:StyleTab/S:StyleCloseButton/S:StyleUIPanelButton/
-- S:MakeDraggable (hoisted from Character.lua this same round, see
-- Skins.lua's own comments on each).
--
-- Real 1.12.1 FrameXML confirmed (source/wow-ui-source/FrameXML/
-- FriendsFrame.xml): FriendsFrame has exactly 4 outer tabs --
-- FriendsFrameTab1-4, text FRIENDS/WHO/GUILD/RAID. Each inherits FriendsFrameTabTemplate ->
-- CharacterFrameTabButtonTemplate, the SAME 6-piece Left/Middle/Right(+
-- Disabled) BACKGROUND-layer template Character's own tabs use -- so
-- S:StyleTab (hoisted FROM that exact tab) applies unchanged. The FRIENDS
-- tab's own content frame (FriendsListFrame) has a further internal
-- Friends/Ignore toggle (FriendsFrameToggleTab1/2, IgnoreFrameToggleTab1/2)
-- using the plain `TabButtonTemplate` (UIPanelTemplates.xml:303-402) --
-- checked structurally identical too (same 6-piece BACKGROUND layout,
-- same $parentText/HighlightTexture naming), so S:StyleTab covers these
-- as well, no separate recipe needed.
--
-- SCOPE, first pass: Guild/Raid explicitly deferred as hard to test at
-- the time. This file styles:
-- the outer FriendsFrame chrome (strip/backdrop/title/close button/
-- draggable) and all 4 outer tabs (so switching tabs doesn't look broken
-- even before Who/Guild/Raid get their own content pass) -- PLUS the
-- Friends tab's own full content: the Friends/Ignore sub-tabs, both
-- scrollframes+scrollbars, and all 6 action buttons (Add Friend, Remove
-- Friend, Send Message, Group Invite, Ignore Player, Stop Ignore).
-- Deliberately NOT touched this pass: WhoFrame/GuildFrame/RaidFrame
-- content (explicit scope cut, not an oversight).
--
-- ******************************************************************
-- source/UnrealUI crash claims -- LIVE-TESTED, READ FIRST
-- ******************************************************************
-- source/UnrealUI/modules/friends.lua (an existing, independently-coded
-- UA addon that already skins this exact frame) documents crash claims
-- for touching two things this file also touches. Both were tested live
-- on the real build instead of taken on faith (UnrealUI has separately
-- claimed a crash -- 3D portrait -- that did NOT reproduce elsewhere):
--
-- 1. Friend/ignore list ROWS (`FriendsFrameFriendButton<i>`/
--    `FriendsFrameIgnoreButton<i>`) -- UnrealUI claims TWO
--    USER_CONFIRMED_INGAME crashes here. Live test used a DIFFERENT,
--    lighter recipe than UnrealUI's own (`S:HandleButtonHighlight`,
--    ported from real ElvUI -- no reanchor, no SetHeight). Result: did
--    NOT crash the client, but a real, different regression appeared --
--    a friend went permanently grey and could no longer be SELECTED, so
--    Remove Friend had nothing to act on. REVERTED below; full writeup
--    in `Skins.lua`'s own `S:HandleButtonHighlight` comment. Rows are
--    once again left fully native.
-- 2. `WhoFrameEditBox` -- UnrealUI claims mutating it crashes at login.
--    The `S.stripSkipNames` exemption that would prevent
--    `S:StripTextures(FriendsFrame, true)` from reaching it (WhoFrame is
--    a direct child of FriendsFrame) was deliberately left OUT. No crash
--    observed through normal login/window use so far -- tentatively
--    fine, not re-added. If a crash traces back here, restore
--    `S.stripSkipNames["WhoFrameEditBox"] = true`.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

local ACCENT_COLOR = S.ACCENT_COLOR

-- Friends/Ignore sub-tabs + both scrollframes/scrollbars + the 6 action
-- buttons -- all of `FriendsListFrame`'s own content. Positions ported
-- from real ElvUI's own Modules/Skins/Blizzard/Friends.lua where it
-- repositions anything at all; native
-- anchors kept as-is everywhere else (WoW's own anchor chain is live, so
-- e.g. SendMessageButton -- anchored relative to AddFriendButton natively
-- -- follows AddFriendButton's new position automatically without this
-- file touching it directly).
local function ApplyFriendsListChrome()
	if not FriendsListFrame then return end

	S:StyleTab(FriendsFrameToggleTab1)
	S:StyleTab(FriendsFrameToggleTab2)
	S:StyleTab(IgnoreFrameToggleTab1)
	S:StyleTab(IgnoreFrameToggleTab2)

	-- Row highlights -- REVERTED, live-tested and CONFIRMED BROKEN:
	-- `S:HandleButtonHighlight` on FriendsFrameFriendButton<i> didn't
	-- crash the client (the claim this was testing), but a friend's row
	-- went permanently grey and could no longer be selected at all -- no
	-- selection meant Remove Friend had nothing to act on. Back to
	-- leaving every row fully native. Full writeup: `Skins.lua`'s own
	-- `S:HandleButtonHighlight` comment.

	if FriendsFrameFriendsScrollFrame then
		S:StripTextures(FriendsFrameFriendsScrollFrame, false)
		S:HandleScrollBar(FriendsFrameFriendsScrollFrameScrollBar)
	end
	if FriendsFrameIgnoreScrollFrame then
		S:StripTextures(FriendsFrameIgnoreScrollFrame, false)
		S:HandleScrollBar(FriendsFrameIgnoreScrollFrameScrollBar)
	end

	-- Every one of these rows is a descendant of `FriendsFrame`, so the
	-- auto-skin sweep at the end of `LoadSkin` recognises and styles them
	-- by their template's own art -- no per-button `S:StyleUIPanelButton`
	-- calls needed here. Only geometry the sweep has no opinion about
	-- (the repositioning below) stays in this file.
	if FriendsFrameAddFriendButton then
		pcall(FriendsFrameAddFriendButton.ClearAllPoints, FriendsFrameAddFriendButton)
		pcall(FriendsFrameAddFriendButton.SetPoint, FriendsFrameAddFriendButton, "BOTTOMLEFT", FriendsFrame, "BOTTOMLEFT", 17, 102)
	end

	if FriendsFrameRemoveFriendButton and FriendsFrameAddFriendButton then
		pcall(FriendsFrameRemoveFriendButton.ClearAllPoints, FriendsFrameRemoveFriendButton)
		pcall(FriendsFrameRemoveFriendButton.SetPoint, FriendsFrameRemoveFriendButton, "TOP", FriendsFrameAddFriendButton, "BOTTOM", 0, -2)
	end

	if FriendsFrameGroupInviteButton and FriendsFrameSendMessageButton then
		pcall(FriendsFrameGroupInviteButton.ClearAllPoints, FriendsFrameGroupInviteButton)
		pcall(FriendsFrameGroupInviteButton.SetPoint, FriendsFrameGroupInviteButton, "TOP", FriendsFrameSendMessageButton, "BOTTOM", 0, -2)
	end
end

-- ---------------------------------------------------------------------
-- Who tab: scrollbar + dropdown + column-sort-click. Ported structurally
-- from real ElvUI's own Modules/Skins/Blizzard/Friends.lua Who-frame
-- block, rebuilt on this project's own primitives. `WhoFrameButton<i>`
-- rows ARE touched directly here (Level/Class/Name text re-anchored, see
-- LayoutWhoRows) -- unlike Friends/Ignore rows, source/UnrealUI never
-- claimed a crash for these, and repositions the same three regions itself. Deliberately NOT calling `S:HandleButtonHighlight` on
-- these rows though -- that's not an UnrealUI claim, it's this project's
-- own live-confirmed regression (permanently-grey, unselectable rows on
-- FriendsFrameFriendButton, see this file's own top-of-file history and
-- `Skins.lua`'s own comment on that function) -- reusing a technique
-- already proven broken in this exact codebase isn't "an UnrealUI issue
-- to ignore", it's a known dead end, so it's skipped here too.
-- ---------------------------------------------------------------------

-- This file does not build a reverse lookup from localized class NAME
-- back to class FILE NAME via `LOCALIZED_CLASS_NAMES_MALE`/`_FEMALE`, for
-- a class-icon-crop + class-color feature real ElvUI's own Friends.lua
-- has: both globals do not exist ANYWHERE in real 1.12.1 at all
-- (confirmed: zero hits in the entire source/wow-ui-source tree; traced
-- to patch 10.1.7, Dragonflight) -- real vanilla's own `WhoList_Update`
-- (FrameXML/FriendsFrame.lua:253-325) never shows a class icon at all,
-- just plain text. Class-color for the Who tab is picked up separately,
-- reusing whatever mechanism `Modules/DataTexts/Friends.lua` already
-- uses (already class-colors the Friends datatext live in this project)
-- rather than reinventing a hardcoded name table here.

local WHOS_TO_DISPLAY = _G.WHOS_TO_DISPLAY or 17

-- WhoFrameColumnHeaderTemplate -- a plain 3-piece Left/Middle/Right
-- BACKGROUND-layer sprite (`WhoFrame-ColumnTabs`, confirmed via the
-- FrameXML), NOT the 6-piece CharacterFrameTabButtonTemplate `S:StyleTab`
-- handles -- no Enable/Disable-driven "selected" variant here, so no
-- separate Disabled-piece kill and no `IsEnabled` check needed. Local to
-- this file for now (only one consumer, the Who tab) -- hoist to
-- Skins.lua if/when the Guild tab's own identical `GuildFrameColumnHeaderTemplate`
-- columns are picked up later, matching this project's established
-- "hoist on 2nd consumer" policy.
local function StyleColumnHeader(header)
	if not header then return end
	S:StripTextures(header, false)
	-- 2px horizontal inset for the same reason `S:StyleTab` has one (see
	-- Skins.lua): consecutive column headers are anchored `LEFT` to the
	-- previous one's `RIGHT` at x=-2, so full-footprint border boxes would
	-- overlap by 4px and their edge lines would fight -- the same defect
	-- that produced the Friends Who/Guild tab seam, just 4px wide instead
	-- of 16. At 2px the boxes end up exactly touching, keeping the
	-- continuous header-strip look with no overlap left to render
	-- ambiguously.
	ElvUI.Util.CreateButtonBorder(header, 2, 0, 0)
	local okText, text = pcall(header.GetFontString, header)
	if okText and text then
		pcall(text.SetTextColor, text, ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3])
	end
end

-- Row text of a Who or guild roster list in the header order this file sets
-- up (Level, Class, Name, then the zone column), at real ElvUI's own offsets:
-- level at `levelX`, name at x=85 and 100 wide. Real ElvUI puts a class ICON
-- in between, which needs globals 1.12.1 does not have (see above), so the
-- native Class text takes that column instead, narrowed to it. The zone text
-- (`$parentVariable` on Who, `$parentZone` on the guild roster) keeps its
-- native anchor to the name's right edge, which lands it under the zone
-- header. Natively both rows run Name, Zone, Level, Class -- left that way
-- under reordered headers, the level numbers sit under the zone header.
--
-- Called again from each list's update hook: source/UnrealUI records that on
-- UA WhoList_Update puts the native row anchors back on every refresh.
local function LayoutClassRows(prefix, count, levelX)
	local i
	for i = 1, count do
		local row = _G[prefix..i]
		local level = _G[prefix..i.."Level"]
		local class = _G[prefix..i.."Class"]
		local name = _G[prefix..i.."Name"]
		if row and level and class and name then
			pcall(level.ClearAllPoints, level)
			pcall(level.SetPoint, level, "TOPLEFT", row, "TOPLEFT", levelX, -3)
			pcall(class.ClearAllPoints, class)
			pcall(class.SetPoint, class, "LEFT", level, "RIGHT", 8, 0)
			pcall(class.SetWidth, class, 44)
			pcall(name.ClearAllPoints, name)
			pcall(name.SetPoint, name, "TOPLEFT", row, "TOPLEFT", 85, -3)
			pcall(name.SetWidth, name, 100)
		end
	end
end

local function LayoutWhoRows()
	LayoutClassRows("WhoFrameButton", WHOS_TO_DISPLAY, 12)
end

local whoListUpdateHooked = false
local function ApplyWhoChrome()
	if not WhoFrame then return end

	-- Column order is Level/Class/Name/Zone (header3/4/1/2), NOT 1/2/3/4
	-- left-to-right -- matches real ElvUI's own exact reordering, and
	-- independently matches source/UnrealUI's own structurally-different
	-- implementation reaching the same order -- strong cross-validated
	-- signal this is the correct native anchor chain, not a guess.
	if WhoFrameColumnHeader3 then
		pcall(WhoFrameColumnHeader3.ClearAllPoints, WhoFrameColumnHeader3)
		pcall(WhoFrameColumnHeader3.SetPoint, WhoFrameColumnHeader3, "TOPLEFT", WhoFrame, "TOPLEFT", 20, -70)
	end
	if WhoFrameColumnHeader4 and WhoFrameColumnHeader3 then
		pcall(WhoFrameColumnHeader4.ClearAllPoints, WhoFrameColumnHeader4)
		pcall(WhoFrameColumnHeader4.SetPoint, WhoFrameColumnHeader4, "LEFT", WhoFrameColumnHeader3, "RIGHT", -2, 0)
		pcall(WhoFrameColumnHeader4.SetWidth, WhoFrameColumnHeader4, 48)
	end
	if WhoFrameColumnHeader1 and WhoFrameColumnHeader4 then
		pcall(WhoFrameColumnHeader1.ClearAllPoints, WhoFrameColumnHeader1)
		pcall(WhoFrameColumnHeader1.SetPoint, WhoFrameColumnHeader1, "LEFT", WhoFrameColumnHeader4, "RIGHT", -2, 0)
		pcall(WhoFrameColumnHeader1.SetWidth, WhoFrameColumnHeader1, 105)
	end
	if WhoFrameColumnHeader2 and WhoFrameColumnHeader1 then
		pcall(WhoFrameColumnHeader2.ClearAllPoints, WhoFrameColumnHeader2)
		pcall(WhoFrameColumnHeader2.SetPoint, WhoFrameColumnHeader2, "LEFT", WhoFrameColumnHeader1, "RIGHT", -2, 0)
	end

	StyleColumnHeader(WhoFrameColumnHeader1)
	StyleColumnHeader(WhoFrameColumnHeader2)
	StyleColumnHeader(WhoFrameColumnHeader3)
	StyleColumnHeader(WhoFrameColumnHeader4)

	S:StyleDropDownBox(WhoFrameDropDown)

	-- 17 search-result rows: text re-anchored to the header order, no class
	-- icon (see LayoutWhoRows and the class-name note above it). Selection
	-- (`button:LockHighlight()`/`UnlockHighlight()`, driven by
	-- `WhoFrame.selectedWho`) is untouched.
	LayoutWhoRows()

	if WhoListScrollFrame then
		S:StripTextures(WhoListScrollFrame, false)
		S:HandleScrollBar(WhoListScrollFrameScrollBar)
	end

	-- Real ElvUI's position; the width is 10 narrower than its 339, which
	-- would run past the panel's right edge (x=351, see ApplyOuterChrome).
	if WhoFrameEditBox then
		S:StyleEditBox(WhoFrameEditBox)
		pcall(WhoFrameEditBox.ClearAllPoints, WhoFrameEditBox)
		pcall(WhoFrameEditBox.SetPoint, WhoFrameEditBox, "BOTTOMLEFT", FriendsFrame, "BOTTOMLEFT", 17, 108)
		pcall(WhoFrameEditBox.SetWidth, WhoFrameEditBox, 329)
		pcall(WhoFrameEditBox.SetHeight, WhoFrameEditBox, 18)
	end

	if WhoFrameWhoButton then
		pcall(WhoFrameWhoButton.ClearAllPoints, WhoFrameWhoButton)
		pcall(WhoFrameWhoButton.SetPoint, WhoFrameWhoButton, "BOTTOMLEFT", FriendsFrame, "BOTTOMLEFT", 16, 82)
	end

	if WhoFrameAddFriendButton and WhoFrameWhoButton and WhoFrameGroupInviteButton then
		pcall(WhoFrameAddFriendButton.ClearAllPoints, WhoFrameAddFriendButton)
		pcall(WhoFrameAddFriendButton.SetPoint, WhoFrameAddFriendButton, "LEFT", WhoFrameWhoButton, "RIGHT", 3, 0)
		pcall(WhoFrameAddFriendButton.SetPoint, WhoFrameAddFriendButton, "RIGHT", WhoFrameGroupInviteButton, "LEFT", -3, 0)
	end

	-- Live level-difficulty color + zone/guild/race green-highlight --
	-- BOTH genuinely vanilla-compatible (no class-name resolution needed,
	-- unlike the removed icon/class-color feature above). Native
	-- `WhoList_Update` re-fills all 17 rows' text on every search refresh,
	-- so this has to reapply every time, not just once. Bare
	-- `hooksecurefunc` doesn't exist on UA (confirmed project-wide) --
	-- `S:SecureHook` (AceHook-3.0's bare-global-name overload, already
	-- mixed into this module) is the established replacement.
	if not whoListUpdateHooked then
		local ok, err = pcall(function()
			S:SecureHook("WhoList_Update", function()
				LayoutWhoRows()

				local okOffset, whoOffset = pcall(FauxScrollFrame_GetOffset, WhoListScrollFrame)
				whoOffset = (okOffset and whoOffset) or 0

				local playerZone = GetRealZoneText()
				local playerGuild = GetGuildInfo("player")
				local okRace, playerRace = pcall(UnitRace, "player")
				playerRace = okRace and playerRace or nil

				local j
				for j = 1, WHOS_TO_DISPLAY do
					local index = whoOffset + j
					local nameText = _G["WhoFrameButton"..j.."Name"]
					local classText = _G["WhoFrameButton"..j.."Class"]
					local levelText = _G["WhoFrameButton"..j.."Level"]
					local variableText = _G["WhoFrameButton"..j.."Variable"]

					local okInfo, _, guild, level, race, class, zone = pcall(GetWhoInfo, index)
					if okInfo and level then
						-- Class color -- same proven recipe already live in
						-- this project's own `Modules/DataTexts/Friends.lua`:
						-- `RAID_CLASS_COLORS` is keyed by class FILE NAME,
						-- and on this client `string.upper(class)` on the
						-- plain display string IS the file name for every
						-- one of vanilla's 9 (single-word) classes -- no
						-- lookup table needed at all, unlike the
						-- LOCALIZED_CLASS_NAMES_MALE/FEMALE dead end. Colors
						-- both the name AND the (still-visible, native)
						-- Class column text.
						if class then
							local classColor = RAID_CLASS_COLORS[string.upper(class)]
							if classColor then
								if nameText then
									pcall(nameText.SetTextColor, nameText, classColor.r, classColor.g, classColor.b)
								end
								if classText then
									pcall(classText.SetTextColor, classText, classColor.r, classColor.g, classColor.b)
								end
							end
						end

						local okDiffColor, levelColor = pcall(GetQuestDifficultyColor, level)
						if levelText and okDiffColor and levelColor then
							pcall(levelText.SetTextColor, levelText, levelColor.r, levelColor.g, levelColor.b)
						end

						if variableText then
							local displayZone = zone
							local displayGuild = guild
							local displayRace = race
							if zone == playerZone then displayZone = "|cff00ff00"..tostring(zone) end
							if guild == playerGuild then displayGuild = "|cff00ff00"..tostring(guild) end
							if playerRace and race == playerRace then displayRace = "|cff00ff00"..tostring(race) end

							local okId, selectedId = pcall(UIDropDownMenu_GetSelectedID, WhoFrameDropDown)
							local columns = { displayZone, displayGuild, displayRace }
							pcall(variableText.SetText, variableText, (okId and columns[selectedId]) or displayZone)
						end
					end
				end
			end)
		end)
		if ok then
			whoListUpdateHooked = true
		else
			S:ReportSkinProblem()
		end
	end
end

-- ---------------------------------------------------------------------
-- Guild tab. UNTESTABLE right now (not currently in a guild) -- ported as
-- closely as possible to the Who tab's own already-live-tested shape
-- specifically so it inherits that confidence, rather than improvising
-- something new and unverified.
--
-- SCOPE CUT, matching source/UnrealUI's own precedent for this exact
-- window (its own comment: the Guild Control rank/permission editor
-- popup is left native as a separate admin/raid subsystem, not the
-- roster itself): `GuildControlPopupFrame` (rank/permission editor,
-- ~30 sub-widgets: dropdown, +/- rank buttons, 13 checkboxes) is NOT
-- implemented here -- same reasoning, a rarely-used admin feature,
-- meaningfully riskier to guess at blind. `GuildMemberDetailFrame` (side
-- panel for a selected member) and `GuildInfoFrame` (MOTD editor) are
-- ALSO deferred this round -- unlike Who, Guild has no equivalent
-- side-panel/editor in this file yet, so there's nothing to mirror
-- confidence from; picking them up needs their own dedicated look, not a
-- rushed extension here. This file's own core roster tab (headers, rows,
-- scrollbar, 3 main buttons) IS the part that's genuinely "99% like Who"
-- -- implemented in full.
-- ---------------------------------------------------------------------

local GUILDMEMBERS_TO_DISPLAY = _G.GUILDMEMBERS_TO_DISPLAY or 13

-- Roster view rows (`GuildFrameButton<i>`) only: the status view's own header
-- row keeps its native order, as in real ElvUI. Level at real ElvUI's x=10.
local function LayoutGuildRows()
	LayoutClassRows("GuildFrameButton", GUILDMEMBERS_TO_DISPLAY, 10)
end

local guildStatusUpdateHooked = false
local function ApplyGuildChrome()
	if not GuildFrame then return end

	-- Same Level/Class/Name/Zone reorder as Who, PLUS an explicit Zone
	-- width (real ElvUI sets one here but not on Who's own Zone column --
	-- ported exactly as-is rather than "fixing" an asymmetry that might
	-- be intentional).
	if GuildFrameColumnHeader3 then
		pcall(GuildFrameColumnHeader3.ClearAllPoints, GuildFrameColumnHeader3)
		pcall(GuildFrameColumnHeader3.SetPoint, GuildFrameColumnHeader3, "TOPLEFT", GuildFrame, "TOPLEFT", 20, -70)
	end
	if GuildFrameColumnHeader4 and GuildFrameColumnHeader3 then
		pcall(GuildFrameColumnHeader4.ClearAllPoints, GuildFrameColumnHeader4)
		pcall(GuildFrameColumnHeader4.SetPoint, GuildFrameColumnHeader4, "LEFT", GuildFrameColumnHeader3, "RIGHT", -2, 0)
		pcall(GuildFrameColumnHeader4.SetWidth, GuildFrameColumnHeader4, 48)
	end
	if GuildFrameColumnHeader1 and GuildFrameColumnHeader4 then
		pcall(GuildFrameColumnHeader1.ClearAllPoints, GuildFrameColumnHeader1)
		pcall(GuildFrameColumnHeader1.SetPoint, GuildFrameColumnHeader1, "LEFT", GuildFrameColumnHeader4, "RIGHT", -2, 0)
		pcall(GuildFrameColumnHeader1.SetWidth, GuildFrameColumnHeader1, 105)
	end
	if GuildFrameColumnHeader2 and GuildFrameColumnHeader1 then
		pcall(GuildFrameColumnHeader2.ClearAllPoints, GuildFrameColumnHeader2)
		pcall(GuildFrameColumnHeader2.SetPoint, GuildFrameColumnHeader2, "LEFT", GuildFrameColumnHeader1, "RIGHT", -2, 0)
		pcall(GuildFrameColumnHeader2.SetWidth, GuildFrameColumnHeader2, 127)
	end

	-- Two independent header ROWS exist -- the roster list view
	-- (`GuildFrameColumnHeader<i>`) and the summary/status view
	-- (`GuildFrameGuildStatusColumnHeader<i>`), matching the native
	-- dual-mode toggle (`FriendsFrame.playerStatusFrame`) the update hook
	-- below also branches on. Real ElvUI styles both sets but only
	-- repositions the first -- matched exactly, not "fixed" into
	-- repositioning both without evidence the second needs it.
	local i
	for i = 1, 4 do
		StyleColumnHeader(_G["GuildFrameColumnHeader"..i])
		StyleColumnHeader(_G["GuildFrameGuildStatusColumnHeader"..i])
	end

	LayoutGuildRows()

	if GuildListScrollFrame then
		S:StripTextures(GuildListScrollFrame, false)
		S:HandleScrollBar(GuildListScrollFrameScrollBar)
	end

	-- "Show Player Status" / "Show Guild Status" view toggle: a bare 32x32
	-- Button with only the four native slots (`UI-SpellbookIcon-NextPage-*`),
	-- no extra background region -- the same shape as Merchant's page
	-- arrows, so the same recipe (real ElvUI: `S:HandleNextPrevButton`). The
	-- label is the button's own ButtonText, anchored natively to the left
	-- of the arrow, and is left untouched; `GuildStatus_Update` re-anchors
	-- the button itself, which the child-frame icon follows.
	S:StyleSquareIconButton(GuildFrameGuildListToggleButton, "RIGHT", 0.5)

	-- Live class-color (name + the still-visible native Class text) +
	-- level-difficulty color + zone green-highlight -- same recipe as
	-- Who's own `WhoList_Update` hook, ported to Guild's dual-mode update
	-- function. `GetGuildRosterInfo` signature CONFIRMED against
	-- `source/UnrealAzeroth_LuaAPI/en/globals/Guild.md`:
	-- name, rankName, rankIndex, level, class, zone, publicNote,
	-- officerNote, online, status -- matches real ElvUI's own destructure
	-- exactly (it just doesn't capture the trailing `status`).
	-- `button.guildIndex` is a native-set field (same idea as
	-- `WhoFrameButton<i>.whoIndex`, already relied on natively) mapping a
	-- row to its roster index -- not independently verified on UA, but
	-- it's how real ElvUI's own reference does this, and every native
	-- call here is `pcall`-wrapped regardless.
	if not guildStatusUpdateHooked then
		local ok, err = pcall(function()
			S:SecureHook("GuildStatus_Update", function()
				local playerZone = GetRealZoneText()
				local j

				if FriendsFrame and FriendsFrame.playerStatusFrame then
					LayoutGuildRows()

					for j = 1, GUILDMEMBERS_TO_DISPLAY do
						local button = _G["GuildFrameButton"..j]
						local nameText = _G["GuildFrameButton"..j.."Name"]
						local classText = _G["GuildFrameButton"..j.."Class"]
						local levelText = _G["GuildFrameButton"..j.."Level"]
						local zoneText = _G["GuildFrameButton"..j.."Zone"]

						local okInfo, _, _, _, level, class, zone, _, _, online =
							pcall(GetGuildRosterInfo, button and button.guildIndex)
						if okInfo and online and class then
							local classColor = RAID_CLASS_COLORS[string.upper(class)]
							if classColor then
								if nameText then pcall(nameText.SetTextColor, nameText, classColor.r, classColor.g, classColor.b) end
								if classText then pcall(classText.SetTextColor, classText, classColor.r, classColor.g, classColor.b) end
							end
							local okDiffColor, levelColor = pcall(GetQuestDifficultyColor, level)
							if levelText and okDiffColor and levelColor then
								pcall(levelText.SetTextColor, levelText, levelColor.r, levelColor.g, levelColor.b)
							end
							if zoneText and zone == playerZone then
								pcall(zoneText.SetTextColor, zoneText, 0, 1, 0)
							end
						end
					end
				else
					for j = 1, GUILDMEMBERS_TO_DISPLAY do
						local button = _G["GuildFrameGuildStatusButton"..j]
						local nameText = _G["GuildFrameGuildStatusButton"..j.."Name"]
						local onlineText = _G["GuildFrameGuildStatusButton"..j.."Online"]

						local okInfo, _, _, _, _, class, _, _, _, online =
							pcall(GetGuildRosterInfo, button and button.guildIndex)
						if okInfo and online and class then
							local classColor = RAID_CLASS_COLORS[string.upper(class)]
							if classColor and nameText then
								pcall(nameText.SetTextColor, nameText, classColor.r, classColor.g, classColor.b)
							end
							if onlineText then
								pcall(onlineText.SetTextColor, onlineText, 1, 1, 1)
							end
						end
					end
				end
			end)
		end)
		if ok then
			guildStatusUpdateHooked = true
		else
			S:ReportSkinProblem()
		end
	end
end

-- ---------------------------------------------------------------------
-- Raid tab: a base only, to be tested and extended later. `RaidFrame`
-- confirmed a genuine child of FriendsFrame
-- (`source/wow-ui-source/FrameXML/RaidFrame.xml:40`,
-- `parent="FriendsFrame"` explicit, even though declared in its own
-- file) -- same SUB_FRAMES shape as Who/Guild, already reached by the
-- outer recursive strip.
--
-- SCOPE, deliberately a "base" only: `RaidFrameConvertToRaidButton`/
-- `RaidFrameRaidInfoButton` (always exist, direct children of RaidFrame)
-- and `RaidInfoFrame` (saved-instance/lockout popup, nested inside
-- RaidFrame, own native `<Backdrop>` + close button + scrollbar --
-- structurally the same shape already handled for StaticPopup1-4).
--
-- DELIBERATELY NOT ATTEMPTED: the actual raid ROSTER GRID
-- (`RaidGroupButton<i>`, `RaidGroup<i>` + its 5 member slots). Confirmed
-- via `source/wow-ui-source/AddOns/Blizzard_RaidUI/Blizzard_RaidUI.toc`
-- (`LoadOnDemand: 1`) that this is a GENUINELY SEPARATE, lazily-loaded
-- addon -- its own templates (`RaidGroupButtonTemplate`/
-- `RaidGroupTemplate`) are virtual, only instantiated by native code once
-- the player is actually in a raid. Neither "wait for the addon to load"
-- nor "wait for the dynamic instances to exist" has an established
-- pattern in this project yet, and this needs both. Real ElvUI's own
-- reference doesn't handle the lazy-load boundary explicitly either (it
-- assumes the globals already exist); source/UnrealUI's own version uses
-- its own `HookAddonOrVariable("Blizzard_RaidUI", ...)` helper, which
-- this project has no equivalent of. Picking this up needs its own
-- dedicated investigation (how/when do `RaidGroupButton1`-style globals
-- actually appear on THIS client -- addon-load event, or only once
-- `GetNumRaidMembers() > 0`, or both), not a guess bolted onto this
-- round. `GetRaidRosterInfo` IS already confirmed against
-- `source/UnrealAzeroth_LuaAPI/en/globals/Raid.md` for whenever this is
-- picked up -- notably it returns the class FILE NAME directly (5th
-- value), no `string.upper()` trick needed there unlike Who/Guild.
-- ---------------------------------------------------------------------

local raidInfoFrameHooked = false
local function ApplyRaidInfoChrome()
	if not RaidInfoFrame then return end

	S:StripTextures(RaidInfoFrame, false)

	S:CreatePanel(RaidInfoFrame)

	S:StyleCloseButton(RaidInfoCloseButton)

	if RaidInfoScrollFrame then
		S:StripTextures(RaidInfoScrollFrame, false)
		S:HandleScrollBar(RaidInfoScrollFrameScrollBar)
	end

	if not raidInfoFrameHooked then
		if S:TryHookScript(RaidInfoFrame, "OnShow", ApplyRaidInfoChrome) then
			raidInfoFrameHooked = true
		end
	end
end

local function ApplyRaidChrome()
	if not RaidFrame then return end

	-- RaidInfoFrame toggles independently (its own OnClick on
	-- RaidFrameRaidInfoButton just Shows/Hides it -- not tied to
	-- RaidFrame's own OnShow at all), so it needs styling applied here
	-- too on first entry to the tab, not only from its own OnShow hook.
	ApplyRaidInfoChrome()
end

-- The four outer tabs' border + text colour.
--
-- Tab 3 (Guild) gets an EXPLICIT disabled state instead of letting
-- `S:StyleTab` infer one: it intermittently came back gold while not
-- in a guild, reliably reproduced by (open Social, close, open
-- SpellBook, close, open Social). Root cause is in `S:StyleTab`'s own note: the
-- widget's enabled bit is OVERLOADED by `PanelTemplates_SelectTab`/
-- `_DeselectTab` to also mean "selected", so it churns on unrelated
-- native updates and can be read mid-flight.
--
-- `IsInGuild()` is the authoritative test, and not a guess: it is the
-- exact one Blizzard's own `ToggleFriendsFrame` uses to make this tab a
-- no-op ("If not in a guild don't do anything when they try to toggle
-- the guild tab" -- source/wow-ui-source/FrameXML/FriendsFrame.lua:750),
-- and the one `InGuildCheck()` drives `PanelTemplates_DisableTab` from.
-- pcall'd like every native call in this project; if it ever failed we
-- fall back to `S:StyleTab`'s own inference rather than forcing a state.
local function StyleOuterTabs()
	local okGuild, inGuild = pcall(IsInGuild)
	local guildTabDisabled = okGuild and not inGuild

	local i
	for i = 1, 4 do
		S:StyleTab(_G["FriendsFrameTab"..i], nil, nil, nil, (i == 3) and guildTabDisabled or nil)
	end
end

-- Re-colours the tabs whenever the native code re-evaluates guild
-- membership. `IsInGuild()` returns false for a while after login even for a
-- guild member (measured on the legacy 1.12.1 client), so the first Social
-- window opened after login greys the Guild tab; the native
-- `PLAYER_GUILD_UPDATE` handler then calls `InGuildCheck()` again, which
-- re-enables the tab, while the colour set on OnShow would stay grey until
-- the window is reopened. `InGuildCheck` is also what native OnShow and
-- `PLAYER_GUILD_UPDATE` (only while the window is visible) run, so every
-- native state change of this tab passes through it.
local inGuildCheckHooked = false
local function HookInGuildCheck()
	if inGuildCheckHooked then return end
	-- Not on UA: `InGuildCheck` also runs on every Social tab click (via
	-- `FriendsFrame_OnShow`), and recolouring after a tab state change fights
	-- UA's own state font -- see `InstallTabStateHooks` in Skins.lua.
	if ElvUI.Compat.isUA then
		inGuildCheckHooked = true
		return
	end
	-- A client whose FrameXML has no such global keeps the OnShow-only
	-- colouring instead of reporting a skin problem on every open.
	if type(_G.InGuildCheck) ~= "function" then
		inGuildCheckHooked = true
		return
	end
	local ok = pcall(function() S:SecureHook("InGuildCheck", StyleOuterTabs) end)
	if ok then
		inGuildCheckHooked = true
	else
		S:ReportSkinProblem()
	end
end

local raidFrameHooked = false
local guildFrameHooked = false
local whoFrameHooked = false
local friendsListHooked = false
local function ApplyOuterChrome(frame)
	S:StripTextures(frame, true)

	-- Separate elvBackground child, pinned to the frame's own BASE frame
	-- level (below every child) -- same recipe, same insets as real
	-- ElvUI's own reference Friends.lua (E:Point(backdrop, "TOPLEFT", 10,
	-- -12) / ("BOTTOMRIGHT", -33, 76)), which are themselves nearly
	-- identical to Character.lua's own confirmed-working CharacterFrame
	-- insets (11,-12 / -32,76) -- both frames share the same
	-- PaperDollInfoFrame-style outer art proportions. Pinning to the
	-- BASE level (not a "+N" guess) is the fix Character.lua's own
	-- PetPaperDollFrame saga already found the hard way: a later-created
	-- sibling frame at the SAME auto-assigned level draws on top and can
	-- bury other native content, so the backdrop belongs strictly below
	-- everything.
	S:CreatePanel(frame, 10, -12, -33, 76)

	local title = _G["FriendsFrameTitleText"]
	if title then
		pcall(title.SetTextColor, title, ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3])
	end

	S:StyleCloseButton(FriendsFrameCloseButton)

	-- Inside the panel's top-right corner. The native anchor (TOPRIGHT
	-- -30,-8) is laid out for the native 32x32 art; at the 20x20 of
	-- S:StyleCloseButton it would overhang the panel's right edge (-33).
	if FriendsFrameCloseButton and frame.elvBackground then
		pcall(FriendsFrameCloseButton.ClearAllPoints, FriendsFrameCloseButton)
		pcall(FriendsFrameCloseButton.SetPoint, FriendsFrameCloseButton, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	StyleOuterTabs()
	HookInGuildCheck()

	ApplyFriendsListChrome()
	ApplyWhoChrome()
	ApplyGuildChrome()
	ApplyRaidChrome()

	-- FriendsListFrame/WhoFrame/GuildFrame/RaidFrame's own OnShow -- native
	-- tab-switch logic shows/hides these subframes independently of
	-- FriendsFrame's own OnShow (matches Character.lua's own established
	-- SUB_FRAMES pattern: a subframe that can be shown without the OUTER
	-- frame re-firing OnShow needs its own hook, or its native re-render
	-- between tab switches goes un-restyled).
	if not friendsListHooked and FriendsListFrame then
		if S:TryHookScript(FriendsListFrame, "OnShow", ApplyFriendsListChrome) then
			friendsListHooked = true
		end
	end
	if not whoFrameHooked and WhoFrame then
		if S:TryHookScript(WhoFrame, "OnShow", ApplyWhoChrome) then
			whoFrameHooked = true
		end
	end
	if not guildFrameHooked and GuildFrame then
		if S:TryHookScript(GuildFrame, "OnShow", ApplyGuildChrome) then
			guildFrameHooked = true
		end
	end
	if not raidFrameHooked and RaidFrame then
		if S:TryHookScript(RaidFrame, "OnShow", ApplyRaidChrome) then
			raidFrameHooked = true
		end
	end

	-- Catch-all pass -- see `S:SkinChildren` (Skins.lua).
	-- Runs LAST so every bespoke recipe above has already claimed its own
	-- widgets. Notably it does NOT touch `FriendsFrameFriendButton<i>`:
	-- those rows carry no `UI-Panel-Button` art, and the sweep only skins
	-- what it can positively identify -- which is exactly the guard this
	-- file needs, given the confirmed regression from touching them (see
	-- `S:HandleButtonHighlight`).
	S:SkinChildren(frame)
	if RaidInfoFrame then S:SkinChildren(RaidInfoFrame) end
end

local function LoadSkin()
	local frame = FriendsFrame
	if not frame then return end

	-- Movability -- real Blizzard's own FriendsFrame has none, same gap
	-- Character.lua already found and fixed for CharacterFrame. Runs once
	-- (MakeDraggable creates a fresh handle per call). SetUserPlaced
	-- applied proactively for the same reason it was required for
	-- CharacterFrame (a UIPanelWindows-managed frame silently gets a
	-- second, conflicting anchor point if never marked user-placed) --
	-- not independently confirmed for FriendsFrame specifically yet, but
	-- cheap and idempotent, so applied the same way rather than waiting
	-- for a live repro of the same bug class.
	S:MakeDraggable(frame, FriendsFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyOuterChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyOuterChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

S:AddBlizzardSkin("friends", LoadSkin)
