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
--      once per chrome pass -- `RECOLOR_*` below.
--   2. The objective lines and the required-money line go dark again
--      whenever the client rebuilds the detail pane -- on every quest
--      selection and on a header toggle. They are re-asserted from a poll;
--      `ReassertObjectiveColors` records what else was tried, why it does
--      not work, and what the real fix would be.
--
-- Fonts themselves are left completely alone, on purpose. `SetFont` is a
-- confirmed no-op on this client and the `SetFontObject` route makes text
-- vanish outright (`docs/api-diffs/media.md`; `source/UnrealUI` measured
-- the same independently and also ships with the inherited native font as
-- its default). `SetTextColor` is a different call and does work, so
-- colour is the entire lever available here. Nothing in this file depends
-- on font family or size, which keeps a later font pass separable.
--
-- SCOPE: outer chrome, the panel and hit rect, a drag handle, both scroll
-- frames and their scrollbars, the close button, text visibility, and the
-- collapse glyphs on the header rows and the "All" button.
--
-- Deliberately NOT done, each its own pass: the reward item buttons
-- (`QuestLogItem1..10` -- their icon is a Texture region of the Button
-- itself, so they need the targeted "keep the icon, border the button"
-- recipe rather than a strip), the `Track Quest` control (not part of real
-- 1.12.1 at all -- this client adds it), and real ElvUI's own layout
-- surgery (resizing the window to 685x490, re-anchoring both scroll frames,
-- `QUESTS_DISPLAYED = 25` with nineteen extra row buttons, and its
-- replacement Track button).

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- `QuestLogFrame` is 384x512 with `HitRectInsets right=35 bottom=75`, and
-- those insets are the honest description of where the VISIBLE dialog ends:
-- the frame's own bounds run 35px further right and 75px further down than
-- anything it draws. Real ElvUI's own numbers for this window (BOTTOMRIGHT
-- -1,8) assume its layout pass has already resized the frame to 685x490;
-- without that resize they leave a wide empty slab to the right of the
-- content with the two scrollbars stranded in it, and a second one below
-- the button row. These are measured off the native frame instead.
--
-- The bottom stops just under `QuestLogFrameAbandonButton` (anchored
-- BOTTOMLEFT +17,+54, height 21, so its top edge is at 75).
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -12, -35, 46

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

-- The two tones the client's own black/near-black pair is remapped onto.
-- Completed stays deliberately dimmer than incomplete, preserving the
-- distinction the native colours carry.
local OBJECTIVE_COLOR = {1, 1, 1}
local OBJECTIVE_DONE_COLOR = {0.55, 0.55, 0.55}
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
			origUpdate()
			pcall(UpdateRowGlyphs)
		end
	end

	local origDetails = _G.QuestLog_UpdateQuestDetails
	if type(origDetails) == "function" then
		_G.QuestLog_UpdateQuestDetails = function(doNotScroll)
			origDetails(doNotScroll)
			pcall(ReassertObjectiveColors)
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
			ReassertObjectiveColors()
		end
	end, 0.2)
end

local function ApplyQuestLogChrome(frame)
	S:StripTextures(frame, false)

	local i
	for i = 1, table.getn(STRIP_CHILDREN) do
		S:StripTextures(_G[STRIP_CHILDREN[i]], false)
	end

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	PromotePanelText()
	S:RecolorNames(RECOLOR_HEADINGS, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	S:RecolorNames(RECOLOR_BODY, 1, 1, 1)

	ReassertObjectiveColors()

	-- ONLY the detail pane gets a field surface. The quest list must not:
	-- `QuestLogTitle1..n` are children of `QuestLogFrame`, NOT of
	-- `QuestLogListScrollFrame` (`QuestLogFrame.xml` -- the FauxScrollFrame
	-- there only drives the scrollbar, the rows are siblings laid over it),
	-- so a surface parented to the scroll frame sits at that frame's own
	-- level with nothing of the scroll frame's own above it, and covers the
	-- entire list. Live symptom: an empty box where the quests should be.
	-- The detail pane is safe for the exact opposite reason -- its content
	-- lives in `QuestLogDetailScrollChildFrame`, a real child of the scroll
	-- frame, so it draws above the surface.
	--
	-- General form of this, worth remembering before adding a field to any
	-- scroll frame: `S:CreateSurface` goes below the PARENT's children, and
	-- a FauxScrollFrame's visible rows are typically not its children.
	S:CreateField(_G.QuestLogDetailScrollFrame)

	S:HandleScrollBar(_G.QuestLogListScrollFrameScrollBar)
	S:HandleScrollBar(_G.QuestLogDetailScrollFrameScrollBar)

	StyleRowGlyphs()
	UpdateRowGlyphs()

	-- Re-anchored to the PANEL, not left on the frame: the native anchor is
	-- TOPRIGHT -30 against a frame whose right edge is 35px past the visible
	-- dialog, so the skinned button would sit outside the panel entirely.
	S:StyleCloseButton(_G.QuestLogFrameCloseButton)
	local close = _G.QuestLogFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all pass -- picks up QuestLogFrameAbandonButton,
	-- QuestFramePushQuestButton and QuestFrameExitButton, all three plain
	-- UIPanelButtonTemplate (`QuestLogFrameAbandonButton`'s native art is
	-- already confirmed present and correctly shaped on UA, see
	-- `docs/api-diffs/widgets-frames.md`).
	S:SkinChildren(frame)
end

local questLogSkinApplied = false
local function ApplyQuestLogSkin()
	if questLogSkinApplied then return end
	local frame = _G.QuestLogFrame
	if not frame then return end
	questLogSkinApplied = true

	-- The frame's own bounds run 35px right and 75px below anything it
	-- draws, and it is `enableMouse="true"` and toplevel -- so without this
	-- that dead area stays an invisible click-eater beside and under the
	-- window. Matched to the panel. (Same fix as KeyBindingFrame.)
	pcall(frame.SetHitRectInsets, frame, PANEL_LEFT, -PANEL_RIGHT, -PANEL_TOP, PANEL_BOTTOM)

	-- `movable="true"` in the XML but with no drag script anywhere, so the
	-- native window cannot actually be moved. The handle is pulled in to
	-- the panel's right edge for the same reason as the hit rect above.
	local handle = S:MakeDraggable(frame)
	if handle then
		pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT, 0)
	end
	pcall(frame.SetUserPlaced, frame, true)

	WrapQuestLogUpdate()
	ApplyQuestLogChrome(frame)
	StartGlyphPoll()

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyQuestLogChrome(frame) end)
	if not ok then E:Print("Skins (quest): QuestLogFrame OnShow hook failed to install") end
end

local function LoadSkin()
	ApplyQuestLogSkin()
end

-- `quest`, real ElvUI's own flag name: its Skins/Blizzard/Quest.lua covers the
-- quest log AND the quest dialog under one `quest` key. This file is the quest
-- log half of that scope, so it shares the flag rather than inventing one --
-- an imported profile's `quest = false` then disables it as the user expects.
S:AddBlizzardSkin("quest", LoadSkin)
