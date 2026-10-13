-- Skins > Blizzard > QuestLog -- reskins the native QuestLogFrame in place.
-- Same recipe family as Binding.lua/MainMenu.lua: strip the native chrome,
-- draw an elvBackground child frame (never SetBackdrop the native frame
-- itself), let the automatic sweep pick up the generic controls.
--
-- Real 1.12.1 structure, per `FrameXML/QuestLogFrame.xml`. Not yet verified
-- against the live client -- if a name below never resolves, that is the
-- first thing to check, not a mechanism failure.
--
-- - The window's decorative art is DIRECT regions of `QuestLogFrame`:
--   `UI-QuestLog-BookIcon` on BACKGROUND, the four `UI-QuestLog-{TopLeft,
--   TopRight,BotLeft,BotRight}` quadrants on ARTWORK, and the three
--   `QuestLogCount{Left,Middle,Right}` input-border pieces on OVERLAY. A
--   plain NON-recursive `S:StripTextures` reaches all of them.
-- - **Recursion is deliberately NOT used here.** Three of this window's
--   child frames carry Textures that are FUNCTION, not decoration, and a
--   blanket strip would take them out: `QuestLogHighlightFrame`
--   (`QuestLogSkillHighlight`, the selected-row highlight),
--   `QuestLogTrack` (its two `UI-RadioButton` states, the tracking
--   indicator) and the two `MoneyFrameTemplate` frames in the detail pane
--   (the gold/silver/copper coin icons). The frames that DO need stripping
--   are stripped by name instead. That is cheaper and safer than a
--   recursive pass plus a three-entry `S.stripSkipNames` list.
-- - **The sort-tab art around "All" is on the BUTTON, not on
--   `QuestLogExpandButtonFrame`.** Despite the names,
--   `QuestLogExpandTabLeft`/`Middle` and the unnamed right cap are
--   `<Layer>` regions inside the `<Button>` element, and `S:StripTextures`
--   never descends into a Button by design -- so stripping the parent
--   frame alone leaves the native tab drawn. `QuestLogCollapseAllButton`
--   is therefore stripped explicitly, in `StyleRowGlyphs`.
-- - No `DisableDrawLayer`: every layer on this frame also carries text
--   (`QuestLogTitleText` on ARTWORK, `QuestLogQuestCount` on OVERLAY,
--   `QuestLogDummyText` on BACKGROUND). `S:StripTextures` only touches
--   Texture regions, so FontStrings survive it.
--
-- **Text colour is the load-bearing part of this window, not the chrome.**
-- Every quest FontString inherits a font object designed for Blizzard's
-- parchment: `QuestTitleFont` and `QuestFont` are pure black `(0,0,0)`,
-- `QuestFontNormalSmall` is dark brown `(0.30,0.18,0)` (`FrameXML/
-- Fonts.xml`). On a dark panel all of it is invisible. Two separate
-- problems follow from that, and they need different answers:
--
--   1. Static text (titles, captions, the description body) is recoloured
--      on every chrome pass AND after every detail-pane rebuild --
--      `RECOLOR_*` below. The rebuild runs the native
--      `QuestFrameItems_Update`, which recolours the reward section's
--      captions (`QuestLogRewardTitleText`, `QuestLogItemReceiveText`, ...)
--      back to the parchment tones, the same native recolouring
--      Skins/Blizzard/Quest.lua undoes for the quest dialog.
--   2. The objective lines and the required-money line go dark again
--      whenever the client rebuilds the detail pane -- on every quest
--      selection and on a header toggle. They are re-asserted from a poll;
--      `ReassertObjectiveColors` records what else was tried, why it does
--      not work, and what the real fix would be.
--
-- Fonts themselves are left completely alone, on purpose. `SetFont` is a
-- confirmed no-op on this client and the `SetFontObject` route makes text
-- vanish outright (`UnrealUI` measured the same independently and
-- also ships with the inherited native font as
-- its default). `SetTextColor` is a different call and does work, so
-- colour is the entire lever available here. Nothing in this file depends
-- on font family or size, which keeps a later font pass separable.
--
-- **Two-pane layout** (real ElvUI's): the native window stacks the quest list
-- (6 rows) above the detail pane, both 300 wide. Here the two columns sit side
-- by side in a 685x490 frame, the list showing `QUEST_ROW_COUNT` rows. The
-- frame becomes a "doublewide" UI panel, like the profession and trainer
-- windows. `QuestLog_Update` reads the `QUESTS_DISPLAYED` global for both its
-- row loop and its FauxScrollFrame window, and addresses rows by name
-- (`QuestLogTitle<i>`), so the extra rows are created from the native
-- `QuestLogTitleButtonTemplate` (also done by `UnrealUI`
-- modules/questlogextended.lua on UA). Both scroll frames get an explicit
-- height: UA derives the scroll range from the set height, not from anchors.
--
-- SCOPE: outer chrome, the two-pane resize, the panel and hit rect, a drag
-- handle, both scroll frames and their scrollbars, the bottom button row, the
-- close button, text visibility, the collapse glyphs on the header rows and
-- the "All" button, and the reward item slots.
--
-- Deliberately NOT done: the `Track Quest` control (`QuestLogTrack`) stays the
-- native one, in its native spot in the header. Real ElvUI replaces it with a
-- "Track" button in the bottom row.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's frame size and outer panel for this window.
local FRAME_WIDTH, FRAME_HEIGHT = 685, 490
local PANEL = { left = 10, top = -12, right = -1, bottom = 8 }

-- Real ElvUI's row count. 25 rows of the 16-high template overlapping by 1
-- take 376, which the 375-high list scroll frame holds.
local QUEST_ROW_COUNT = 25

-- Two adjacent pane surfaces 3 apart, each holding its scroll frame and that
-- frame's scrollbar, as in TradeSkill.lua/Trainer.lua. The list pane spans
-- x 14..345: rows and scroll frame from 19 (the native row position), 300
-- wide, scrollbar at the template's native +6 to the right. The detail pane
-- spans 348..680, its scroll frame from 352. Both panes end 36 above the
-- frame bottom, just over the button row.
local LIST_PANE = { left = 14, top = -71, right = -340, bottom = 36 }
local DETAIL_PANE_RIGHT, DETAIL_PANE_BOTTOM = -5, 36
local SCROLL_TOP, SCROLL_WIDTH, SCROLL_HEIGHT = -75, 300, 375
local LIST_SCROLL_X, DETAIL_SCROLL_X = 19, 352

-- Bottom row: Abandon and Share under the list pane, Exit under the detail
-- pane's right edge.
local BUTTON_LEFT, BUTTON_RIGHT, BUTTON_BOTTOM, BUTTON_GAP = 14, -5, 12, 3

-- Header row: the "All" button lines up with the list rows' glyphs; the quest
-- count sits at the same height at the detail pane's right edge. The native
-- count anchors to `QuestLogCountRight`, an input-border texture the strip
-- hides, so it is re-anchored to the frame.
local COLLAPSE_ALL_X, COLLAPSE_ALL_Y = LIST_SCROLL_X, -44
local QUEST_COUNT_X, QUEST_COUNT_Y = -14, -55

-- Child frames whose own art is purely decorative. Everything else nested
-- in this window carries Textures that mean something -- see the header.
local STRIP_CHILDREN = {
	"QuestLogExpandButtonFrame",
	"EmptyQuestLogFrame",
}

-- FontStrings sitting DIRECTLY on `QuestLogFrame`. `elvBackground` is a
-- child frame pinned to the frame's own level, and at equal frame levels
-- draw order falls back to draw LAYER -- so the panel covers these unless
-- they are promoted. Same fix already proven on KeyBindingFrame and
-- PetPaperDollFrame.
local PANEL_TEXTS = {
	"QuestLogTitleText",
	"QuestLogQuestCount",
}

-- Static text, recoloured once per chrome pass. Headings take the shared
-- accent (matching every other skinned window's title), body text white.
local RECOLOR_HEADINGS = {
	"QuestLogTitleText",
	"QuestLogQuestTitle",
	"QuestLogObjectivesText",
	"QuestLogDescriptionTitle",
	"QuestLogRewardTitleText",
}

local RECOLOR_BODY = {
	"QuestLogQuestCount",
	"QuestLogQuestDescription",
	"QuestLogItemChooseText",
	"QuestLogItemReceiveText",
	"QuestLogSpellLearnText",
	"QuestLogNoQuestsText",
	"QuestLogTimerText",
}

-- The two tones the client's own black/near-black objective pair is remapped
-- onto: real ElvUI's own (Skins/Blizzard/Quest.lua `QuestObjectiveTextColor`),
-- a completed objective gold, an incomplete one grey.
local OBJECTIVE_COLOR = {0.6, 0.6, 0.6}
local OBJECTIVE_DONE_COLOR = {1, 0.80, 0.10}
local MONEY_COLOR = {1, 0.80, 0.10}
local MONEY_SHORT_COLOR = {0.6, 0.6, 0.6}

local MAX_OBJECTIVES = 10

local function PromotePanelText()
	local i
	for i = 1, table.getn(PANEL_TEXTS) do
		local fs = _G[PANEL_TEXTS[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end
end

-- Polled, and this is the ONLY mechanism available -- the two better-looking
-- alternatives are both measured dead ends, recorded so neither is tried
-- again:
--
--  * **Recolour the shared font OBJECT** (`QuestFontNormalSmall:
--    SetTextColor(...)`), which is how real ElvUI does it and would leave
--    nothing to revert TO: impossible here. On this client a Font is not a
--    Region and text colour is not registered on it at all -- the call is
--    simply absent (`Font` exposes only `GetFontObject`/`GetSpacing`/
--    `SetFont`/`SetFontObject`), confirmed live with
--    "attempt to call method 'SetTextColor' (a nil value)".
--  * **Intercept the write** by shadowing `SetTextColor` on the FontString:
--    never fires. A shadow that only printed, installed live on
--    `QuestLogObjective1`, produced nothing across quest switches or header
--    toggles -- this client rebuilds the detail pane rather than recolouring
--    it, and a rebuilt FontString simply falls back to its font object's
--    colour, which for `QuestFontNormalSmall` is the parchment brown.
--
-- So the colour has to be re-applied per FontString after every rebuild,
-- and the completed/incomplete state is read from the QUEST API rather than
-- from the text colour. That matters on this client specifically:
-- `FontString:GetTextColor` reads the FONT OBJECT's colour, not a
-- per-string override, so colour cannot be used to carry state back --
-- every objective would have read as one and the same state.
local function ReassertObjectiveColors()
	local i
	for i = 1, MAX_OBJECTIVES do
		local fs = _G["QuestLogObjective"..i]
		if fs then
			local ok, _, _, finished = pcall(GetQuestLogLeaderBoard, i)
			local c = (ok and finished) and OBJECTIVE_DONE_COLOR or OBJECTIVE_COLOR
			pcall(fs.SetTextColor, fs, c[1], c[2], c[3])
		end
	end

	local money = _G.QuestLogRequiredMoneyText
	if money then
		local c = MONEY_COLOR
		local okReq, required = pcall(GetQuestLogRequiredMoney)
		local okHave, have = pcall(GetMoney)
		if okReq and okHave and required and have and required > have then
			c = MONEY_SHORT_COLOR
		end
		pcall(money.SetTextColor, money, c[1], c[2], c[3])
	end
end

-- Everything a detail-pane rebuild can turn dark again: the static captions
-- (the reward section's among them) and the objective/money lines.
local function ReassertDetailText()
	S:RecolorNames(RECOLOR_HEADINGS, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	S:RecolorNames(RECOLOR_BODY, 1, 1, 1)
	ReassertObjectiveColors()
end

-- Reward item slots (`QuestLogItem1..10`, `QuestLogRewardItemTemplate`, which
-- inherits `QuestItemTemplate`): the merchant window's item-slot look through
-- the shared `S:StyleQuestItemSlot`, same as the trade skill reagents. Real
-- ElvUI borders the whole slot instead; this keeps every item slot in the
-- project on one look. The native 147x41 size is kept, since the client's own
-- item layout positions the slots.
local function StyleRewardItems()
	local count = tonumber(_G.MAX_NUM_ITEMS) or 10
	local i
	for i = 1, count do
		S:StyleQuestItemSlot(_G["QuestLogItem" .. i])
	end
end

local function RowCount()
	return tonumber(_G.QUESTS_DISPLAYED) or 6
end

-- Every row and the "All" button use `QuestLogTitleButtonTemplate`, whose
-- NormalTexture IS the collapse glyph (`UI-MinusButton-UP` in the XML).
-- `keepTextColor` is passed: a row's label colour is the quest's DIFFICULTY
-- colour, set by the client on every update -- overwriting it with the
-- accent would throw that information away. The Reputation/Skill headers
-- this recipe came from have no such meaning and do take the accent.
-- Forward-declared: the styling pass below hands this to
-- `S:StylePlusMinusButton` as the click refresh, and it is defined further
-- down because it depends on the state helpers between here and there. The
-- upvalue is assigned long before any of this runs.
local UpdateRowGlyphs

local function StyleRowGlyphs()
	-- The sort-tab art (`QuestLogExpandTabLeft/Middle` plus an unnamed
	-- right cap) hangs off the BUTTON, not off `QuestLogExpandButtonFrame`
	-- as its name suggests -- they are `<Layer>` regions inside the
	-- `<Button>` element in `QuestLogFrame.xml`. `S:StripTextures` never
	-- descends into a Button by design, so stripping the parent frame left
	-- the tab drawn. Stripped by name here instead, and BEFORE the glyph is
	-- created, so the fresh glyph is not stripped with it.
	S:StripTextures(_G.QuestLogCollapseAllButton, false)

	S:StylePlusMinusButton(_G.QuestLogCollapseAllButton, true, UpdateRowGlyphs)

	local i
	for i = 1, RowCount() do
		S:StylePlusMinusButton(_G["QuestLogTitle"..i], true, UpdateRowGlyphs)
	end
end

-- The expanded/collapsed state is NOT in a field here, unlike
-- Reputation's `.isCollapsed` and Skill's `.isExpanded`: the client encodes
-- it in the row's NormalTexture PATH, swapping between `UI-MinusButton-UP`
-- (expanded header), `UI-PlusButton-UP` (collapsed header) and `""` (a
-- plain quest row, which gets no glyph at all). Real ElvUI reads the same
-- signal, via `hooksecurefunc(row, "SetNormalTexture", ...)`; this polls
-- for it instead, because a bare `hooksecurefunc` does not exist on UA.
--
-- That path is NOT readable after styling: `S:StylePlusMinusButton` hides
-- the native region, blanks its path AND noops the button's own
-- `SetNormalTexture`, so the client can no longer write a new path into it.
-- Which is why the state is read from the quest API below, not from the
-- texture -- see `GlyphStateOf`.
-- Returns isHeader, isExpanded. The two are kept apart rather than folded
-- into one nullable value: "collapsed" and "not a header" are different
-- states, and conflating them hides the glyph instead of switching it.
-- Row -> quest log index, the same mapping the client's own code uses
-- (`QuestLogFrame.lua`: `questIndex = i + FauxScrollFrame_GetOffset(
-- QuestLogListScrollFrame)`).
local function QuestIndexForRow(row)
	local ok, offset = pcall(FauxScrollFrame_GetOffset, _G.QuestLogListScrollFrame)
	if not ok or not offset then offset = 0 end
	return row + offset
end

-- Read from the QUEST API, not from the row's texture.
--
-- An earlier version inferred the state from the button's NormalTexture
-- path (`UI-MinusButton-UP` / `UI-PlusButton-UP` / `""`), mirroring what
-- real ElvUI hooks. It was correct but always one step behind: the texture
-- is a RESULT of the rebuild, so the glyph could only change after the list
-- had finished rearranging, which reads as the icon lagging the click.
-- `GetQuestLogTitle` reflects the new state as soon as the click toggles
-- it, before anything is redrawn.
--
-- Same lesson as the objective colours in this file: on this client, ask
-- the API for state, never the rendering. There the colour could not be
-- read back at all; here it could, just too late.
local function GlyphStateOf(row)
	local ok, _, _, _, isHeader, isCollapsed = pcall(GetQuestLogTitle, QuestIndexForRow(row))
	if not ok or not isHeader then return false, false end
	return true, not isCollapsed
end

local function ApplyGlyphState(button, row)
	if not button then return end
	local isHeader, isExpanded = GlyphStateOf(row)
	S:SetGlyphShown(button, isHeader)
	if isHeader then S:SetGlyphExpanded(button, isExpanded) end
end

function UpdateRowGlyphs()
	-- The "All" button is not a quest log row, so it has no index to ask
	-- about. It carries its own state instead, in a plain field the client
	-- maintains alongside the icon it sets (`QuestLogCollapseAllButton
	-- .collapsed`, QuestLogFrame.lua) -- the same kind of field the
	-- Reputation and Skill headers expose. It is always a header, so it is
	-- only ever toggled, never hidden.
	local all = _G.QuestLogCollapseAllButton
	if all then
		S:SetGlyphShown(all, true)
		S:SetGlyphExpanded(all, not all.collapsed)
	end

	local i
	for i = 1, RowCount() do
		ApplyGlyphState(_G["QuestLogTitle"..i], i)
	end
end

-- One timer for both of the things this window cannot be told about: the
-- collapse state (signalled by swapping a texture path, not by any call)
-- and the objective colours (see `ReassertObjectiveColors`). 0.2s is short
-- enough that the dark frame after a rebuild reads as a slight delay rather
-- than a flash.
-- The glyph and the objective colours have to change IN the same call that
-- rebuilds them, not one poll tick later.
--
-- The client swaps a row's collapse icon synchronously while handling the
-- click, so the native icon flips the instant the list expands or
-- collapses. A replacement driven only by a timer visibly lags behind that
-- -- the list finishes rearranging and the glyph changes afterwards, which
-- reads as the window being out of sync with itself.
--
-- The same call chain explains why the quest log repaints when a REPUTATION
-- header is collapsed, which looks like a coupling between two unrelated
-- windows: `QuestLogFrame` registers `UPDATE_FACTION` and rebuilds itself
-- on it (`QuestLog_OnLoad`/`QuestLog_OnEvent`, FrameXML). That is stock
-- Blizzard behaviour, confirmed from a live `debugstack` -- no addon in the
-- chain -- and there is nothing to fix about it; it just has to be
-- repainted like any other rebuild.
--
-- Wrapped and called through, NOT replaced -- the difference matters. This
-- module already owns one outright replacement of a global
-- (`FauxScrollFrame_Update`, see `S:HandleScrollBar`), which is the
-- project's one knowingly risky intervention because it drops the original
-- body. A wrapper composes instead: pfQuest wraps this very function on
-- this client, and both wrappers run.
--
-- Only OUR additions are pcall'd. An error inside the original should
-- behave exactly as it would with no addon present, rather than being
-- swallowed here.
-- TWO functions are wrapped, not one, and which repaint hangs off which is
-- load-bearing. `QuestLog_OnEvent` runs them in this order:
--
--     QuestLog_Update();                    -- rebuilds the ROW list
--     QuestWatch_Update();
--     if visible then QuestLog_UpdateQuestDetails(1); end   -- rebuilds the
--                                                           -- DETAIL pane
--
-- so recolouring the objectives from `QuestLog_Update` would run BEFORE the
-- pane that holds them is rebuilt, and be undone immediately. The glyphs
-- belong to the first (that is what sets the row textures), the objective
-- colours to the second.
local questLogWrapped = false
local function WrapQuestLogUpdate()
	if questLogWrapped then return end
	questLogWrapped = true

	local origUpdate = _G.QuestLog_Update
	if type(origUpdate) == "function" then
		_G.QuestLog_Update = function()
			-- The native file sets QUESTS_DISPLAYED = 6 at load; asserted
			-- here so nothing that resets it shrinks the list.
			_G.QUESTS_DISPLAYED = QUEST_ROW_COUNT
			origUpdate()
			pcall(UpdateRowGlyphs)
		end
	end

	local origDetails = _G.QuestLog_UpdateQuestDetails
	if type(origDetails) == "function" then
		_G.QuestLog_UpdateQuestDetails = function(doNotScroll)
			origDetails(doNotScroll)
			pcall(ReassertDetailText)
		end
	end
end

-- Backstop for whatever the wrapper above does not cover: this client's
-- quest code is not the stock one, so there is no guarantee every path that
-- changes a row also goes through `QuestLog_Update`. Cheap enough to leave
-- running, and it costs nothing visible once the wrapper is doing the work.
local glyphPollStarted = false
local function StartGlyphPoll()
	if glyphPollStarted then return end
	glyphPollStarted = true
	E:ScheduleRepeatingTimer(function()
		local frame = _G.QuestLogFrame
		if frame and frame:IsShown() then
			UpdateRowGlyphs()
			ReassertDetailText()
		end
	end, 0.2)
end

-- A plain child frame at QuestLogFrame's own level, so the rows (siblings of
-- the list scroll frame, one level up) and both scroll frames draw above it.
local function CreatePane(frame, key)
	if frame[key] then return frame[key] end
	local okPane, pane = pcall(CreateFrame, "Frame", nil, frame)
	if not okPane or not pane then return nil end
	local okLevel, level = pcall(frame.GetFrameLevel, frame)
	pcall(pane.SetFrameLevel, pane, (okLevel and tonumber(level)) or 0)
	frame[key] = pane
	return pane
end

-- The list's surface is NOT parented to `QuestLogListScrollFrame`:
-- `QuestLogTitle1..n` are children of `QuestLogFrame`, not of the
-- FauxScrollFrame (which only drives the scrollbar), so a surface on the
-- scroll frame would sit above the rows and cover the whole list.
local function ApplyPanels(frame)
	S:CreatePanel(frame, PANEL.left, PANEL.top, PANEL.right, PANEL.bottom)

	if not frame.elvListPane then
		local pane = CreatePane(frame, "elvListPane")
		if pane then
			pcall(pane.SetPoint, pane, "TOPLEFT", frame, "TOPLEFT", LIST_PANE.left, LIST_PANE.top)
			pcall(pane.SetPoint, pane, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", LIST_PANE.right, LIST_PANE.bottom)
			S:CreateSurface(pane, S.PANEL_COLOR)
		end
	end
	if frame.elvListPane and not frame.elvDetailPane then
		local pane = CreatePane(frame, "elvDetailPane")
		if pane then
			pcall(pane.SetPoint, pane, "TOPLEFT", frame.elvListPane, "TOPRIGHT", 3, 0)
			pcall(pane.SetPoint, pane, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", DETAIL_PANE_RIGHT, DETAIL_PANE_BOTTOM)
			S:CreateSurface(pane, S.PANEL_COLOR)
		end
	end
end

local function PlaceScrollFrame(scroll, frame, x)
	if not scroll then return end
	pcall(scroll.ClearAllPoints, scroll)
	pcall(scroll.SetPoint, scroll, "TOPLEFT", frame, "TOPLEFT", x, SCROLL_TOP)
	pcall(scroll.SetWidth, scroll, SCROLL_WIDTH)
	pcall(scroll.SetHeight, scroll, SCROLL_HEIGHT)
end

-- The detail frame is natively anchored below the list; both are pinned to
-- the frame instead, side by side.
local function ApplyScrollFrames(frame)
	PlaceScrollFrame(_G.QuestLogListScrollFrame, frame, LIST_SCROLL_X)
	local detail = _G.QuestLogDetailScrollFrame
	PlaceScrollFrame(detail, frame, DETAIL_SCROLL_X)
	if detail then pcall(detail.UpdateScrollChildRect, detail) end

	S:HandleScrollBar(_G.QuestLogListScrollFrameScrollBar)
	S:HandleScrollBar(_G.QuestLogDetailScrollFrameScrollBar)
end

local function Reanchor(region, point, relativeTo, relativePoint, x, y)
	if not region or not relativeTo then return end
	pcall(region.ClearAllPoints, region)
	pcall(region.SetPoint, region, point, relativeTo, relativePoint, x, y)
end

local function ApplyHeaderAndButtons(frame)
	Reanchor(_G.QuestLogCollapseAllButton, "TOPLEFT", frame, "TOPLEFT", COLLAPSE_ALL_X, COLLAPSE_ALL_Y)
	Reanchor(_G.QuestLogQuestCount, "RIGHT", frame, "TOPRIGHT", QUEST_COUNT_X, QUEST_COUNT_Y)
	-- Natively placed relative to the title text, which now sits over the
	-- middle of the doublewide frame, between the panes.
	Reanchor(_G.QuestLogNoQuestsText, "CENTER", frame.elvListPane, "CENTER", 0, 0)

	local abandon = _G.QuestLogFrameAbandonButton
	Reanchor(abandon, "BOTTOMLEFT", frame, "BOTTOMLEFT", BUTTON_LEFT, BUTTON_BOTTOM)
	-- Natively hangs off the Exit button's left edge.
	Reanchor(_G.QuestFramePushQuestButton, "LEFT", abandon, "RIGHT", BUTTON_GAP, 0)
	Reanchor(_G.QuestFrameExitButton, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", BUTTON_RIGHT, BUTTON_BOTTOM)
end

-- The XML defines `QuestLogTitle1..6`; the rest are built from the same
-- template, chained below the previous row exactly like the native ones.
local function CreateExtraRows(frame)
	local i
	for i = 2, QUEST_ROW_COUNT do
		if not _G["QuestLogTitle" .. i] then
			local okBtn, btn = pcall(CreateFrame, "Button", "QuestLogTitle" .. i, frame, "QuestLogTitleButtonTemplate")
			if okBtn and btn then
				pcall(btn.SetID, btn, i)
				pcall(btn.Hide, btn)
				pcall(btn.SetPoint, btn, "TOPLEFT", _G["QuestLogTitle" .. (i - 1)], "BOTTOMLEFT", 0, 1)
			end
		end
	end
	_G.QUESTS_DISPLAYED = QUEST_ROW_COUNT
end

local function ApplyQuestLogChrome(frame)
	S:StripTextures(frame, false)

	local i
	for i = 1, table.getn(STRIP_CHILDREN) do
		S:StripTextures(_G[STRIP_CHILDREN[i]], false)
	end

	ApplyPanels(frame)

	PromotePanelText()
	ReassertDetailText()
	StyleRewardItems()

	ApplyScrollFrames(frame)
	ApplyHeaderAndButtons(frame)

	StyleRowGlyphs()
	UpdateRowGlyphs()

	-- Re-anchored to the PANEL: the native anchor (TOPRIGHT -30,-8) was cut
	-- for the 384-wide parchment art.
	S:StyleCloseButton(_G.QuestLogFrameCloseButton)
	local close = _G.QuestLogFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all pass -- picks up QuestLogFrameAbandonButton,
	-- QuestFramePushQuestButton and QuestFrameExitButton, all three plain
	-- UIPanelButtonTemplate (`QuestLogFrameAbandonButton`'s native art is
	-- already confirmed present and correctly shaped on UA).
	S:SkinChildren(frame)
end

local questLogSkinApplied = false
local function ApplyQuestLogSkin()
	if questLogSkinApplied then return end
	local frame = _G.QuestLogFrame
	if not frame then return end
	questLogSkinApplied = true

	-- Natively a "left" panel; at twice the width it takes the left and
	-- centre slots, like the profession and trainer windows.
	pcall(function()
		UIPanelWindows["QuestLogFrame"] = { area = "doublewide", pushable = 0, whileDead = 1 }
	end)

	pcall(frame.SetWidth, frame, FRAME_WIDTH)
	pcall(frame.SetHeight, frame, FRAME_HEIGHT)
	-- `enableMouse="true"` and toplevel, so any part of the frame outside the
	-- panel would be an invisible click-eater. Matched to the panel.
	pcall(frame.SetHitRectInsets, frame, PANEL.left, -PANEL.right, -PANEL.top, PANEL.bottom)

	-- `movable="true"` in the XML but with no drag script anywhere, so the
	-- native window cannot actually be moved.
	S:MakeDraggable(frame, _G.QuestLogFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	CreateExtraRows(frame)
	WrapQuestLogUpdate()
	ApplyQuestLogChrome(frame)
	StartGlyphPoll()

	-- The doublewide override means an open profession or trainer window is
	-- no longer replaced by the panel manager: closed here instead.
	local ok = S:TryHookScript(frame, "OnShow", function()
		ApplyQuestLogChrome(frame)
		S:CloseOtherDoublewidePanels(frame)
	end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyQuestLogSkin()
end

-- `quest`, real ElvUI's own flag name: its Skins/Blizzard/Quest.lua covers the
-- quest log AND the quest dialog under one `quest` key. This file is the quest
-- log half of that scope, so it shares the flag rather than inventing one --
-- an imported profile's `quest = false` then disables it as the user expects.
S:AddBlizzardSkin("quest", LoadSkin)
