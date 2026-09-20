-- Skins > Blizzard > TradeSkill -- reskins the native profession window
-- (TradeSkillFrame) in place. Same chrome-removal family as every other
-- window in this project, but the ONLY one so far that also RESIZES the
-- native frame and relayouts it into a two-pane ("doublewide") window --
-- porting real ElvUI's own `Blizzard/TradeSkill.lua`, which does the same
-- thing on real vanilla.
--
-- Real 1.12.1 structure, per `AddOns/Blizzard_TradeSkillUI/
-- Blizzard_TradeSkillUI.xml`/`.lua`, plus the shared
-- `FrameXML/ClassTrainerFrameTemplates.xml` templates this window's list
-- row/detail scroll frame both inherit (shared with the not-yet-skinned
-- Trainer window). Not yet verified against the live client.
--
-- - **`## LoadOnDemand: 1`** (`Blizzard_TradeSkillUI.toc`) -- the FOURTH
--   such window (after Macro/Binding/Talent): `S:WaitForGlobal` owns the
--   wait.
-- - **Resized to 720x508 ("doublewide"), matching real ElvUI exactly.**
--   Native is 384x512, single column (list stacked ABOVE the detail
--   pane), and its stock `UIPanelWindows` entry is
--   `{area = "left", pushable = 3}`. Real ElvUI's own override
--   (`{area = "doublewide", pushable = 0, whileDead = 1}`) is taken over
--   verbatim, so the native panel manager reserves the wider footprint
--   the other doublewide windows use instead of a "left" slot the frame
--   no longer fits.
-- - **Both scroll frames have to be MOVED AND RESIZED, not just backed
--   by a panel.** The native ones are stacked VERTICALLY (list at
--   `TOPRIGHT -67,-96` sized 296x130, detail at `TOPLEFT 20,-234` sized
--   297x176), which inside a 720-wide frame leaves the detail pane in the
--   lower LEFT corner, overlapping the list, instead of forming the
--   right-hand column -- and leaves the list clipped to 8 rows' worth of
--   height while 25 rows are being displayed. Real ElvUI's own numbers
--   for the two-column layout are used (`LIST_SCROLL_*`/`DETAIL_SCROLL_*`).
-- - **No field surface on `TradeSkillDetailScrollFrame`.** The recipe
--   name, requirement line and reagent label are FontStrings belonging to
--   `TradeSkillDetailScrollChildFrame`, and a scroll child renders at its
--   scroll frame's OWN frame level -- so a surface created on the scroll
--   frame afterwards draws over them and the detail pane comes out blank
--   except for its child BUTTONS (recipe icon, reagent slots), which sit
--   a level higher. The detail pane's background is the separate
--   `elvDetailPane` host on `TradeSkillFrame`, exactly as real ElvUI's
--   own `bg2` is.
-- - **Reagent slots use the shared `S:StyleQuestItemSlot`** (Skins.lua):
--   the merchant window's item-slot look -- bordered icon, name beside it,
--   field surface behind the name, no border around the slot and no
--   quality tint.
-- - **`TradeSkillListScrollFrame` is a `FauxScrollFrameTemplate`.** Its
--   visible rows (`TradeSkillSkill1-25`) are NOT its children -- they are
--   siblings, direct children of `TradeSkillFrame` itself, merely
--   POSITIONED to overlap it (confirmed straight from the FrameXML: the
--   `<Button name="TradeSkillSkill1">` block sits under `TradeSkillFrame`'s
--   own `<Frames>`, not inside the scroll frame's `<ScrollChild>`, because
--   a Faux scroll frame has no `<ScrollChild>` at all). Same trap
--   `QuestLogFrame` already hit: a field
--   surface placed directly on the scroll frame would sit ABOVE the scroll
--   frame's own base level but BELOW these sibling row buttons only by
--   accident, and would visibly cover them the moment that accident
--   doesn't hold. Fixed the documented way: the list-pane background is a
--   frame parented to `TradeSkillFrame` itself (the actual common
--   ancestor), sized to the visual footprint real ElvUI's own numbers
--   give it, not attached to the scroll frame at all.
-- - **`TradeSkillDetailScrollFrame` is a real `UIPanelScrollFrameTemplate`
--   with a genuine `<ScrollChild>`** (`TradeSkillDetailScrollChildFrame`)
--   -- safe for `S:CreateField` directly, the other half of the same rule.
-- - **`TRADE_SKILLS_DISPLAYED` bumped from vanilla's own default (8) to
--   25, and `TradeSkillSkill9-25` created at runtime** the same way native
--   `TradeSkillFrame_Update` itself would if this constant were ever
--   raised -- real ElvUI does the exact same thing, and the list pane's
--   own height (bg1, below) was already sized against 25 rows of 16px by
--   that same reference. One-time, not re-run on every OnShow.
-- - **The native "SetNormalTexture per row" plus/minus-glyph recipe real
--   ElvUI uses (`hooksecurefunc(button, "SetNormalTexture", fn)`,
--   `hooksecurefunc(TradeSkillCollapseAllButton, "SetNormalTexture", fn)`)
--   CANNOT be ported as-is.** Two independent, already-documented UA
--   facts both apply here: `hooksecurefunc` is not even a global function
--   on this client at all, AND even
--   its AceHook-3.0 replacement's OBJECT+METHOD 3-arg overload
--   (`:SecureHook(obj, "method", handler)`, the shape this recipe needs)
--   is a separately-confirmed dead end. Replaced with this project's own
--   established substitute for exactly this situation: `S:StylePlusMinusButton`
--   / `S:SetGlyphShown` / `S:SetGlyphExpanded` (already built for
--   Reputation/Skill/QuestLog headers -- same 293x16-class native row
--   shape) plus a periodic poll reading `GetTradeSkillInfo` state
--   directly, never trusting a hook to fire at all. This window is also
--   what forced `S:StylePlusMinusButton` to noop the button's own
--   `SetNormalTexture`/highlight `SetTexture`: `TradeSkillFrame_Update`
--   re-assigns the native plus/minus art on EVERY list update, so merely
--   hiding the texture object leaves the native glyph back beside our own
--   on the first refresh.
-- - **`movable="true"` in the XML with no drag script anywhere**, the same
--   gap as every other window in this family, so `S:MakeDraggable`. The
--   native hit rect (`right=34, bottom=75`) is calibrated for the 384x512
--   frame and is re-cut to the panel after the resize.
-- - **`TradeSkillRankFrameBorder` is a BUTTON, and no `S:StripTextures`
--   call can clear it** -- that walk covers `GetRegions()` only and never
--   descends into a Button, while this border's art
--   (`UI-Character-Skills-BarBorder`, the same 281x32 art
--   `SkillFrame.xml`'s own bar template uses) lives in its NormalTexture.
--   Left drawn, it is narrower than the resized 420px bar and pinned to
--   its LEFT edge, so the whole rank bar reads as left-aligned and
--   off-centre. `S:StripButtonArt` exists for this shape. The bar's own
--   fill colour also has to be re-asserted on every selection, since
--   `TradeSkillFrame_SetSelection` sets its own half-alpha blue each time.
-- - **`TradeSkillFrame_SetSelection` IS safely hookable** -- it's a bare
--   GLOBAL FUNCTION, the confirmed-working half of the hook story
--   (`S:SecureHook("TradeSkillFrame_SetSelection", handler)`, same shape
--   already proven for SpellBook/Friends). Used for both the recipe-icon
--   re-crop and the reagent/recipe item-quality border colouring, exactly
--   like real ElvUI's own single hook does.
-- - **`TradeSkillReagent1-8` (`TradeSkillItemTemplate`, inherits
--   `QuestItemTemplate`)** have no Normal/Pushed texture, only a bare
--   `$parentIconTexture` and a decorative `$parentNameFrame`, so
--   `Util.SkinItemButton` (built for `ItemButtonTemplate`) does not apply;
--   `S:StyleQuestItemSlot` covers that shape.
-- - `TradeSkillSkillIcon` is a bare `Button` with NO inherited template at
--   all -- its icon is native code calling `SetNormalTexture` directly on
--   selection change, so (unlike every other icon in this project) its
--   NormalTexture region IS the content, not decoration, and must never
--   be blanket-stripped.
--
-- SCOPE: outer chrome, doublewide resize, list/detail panel backgrounds,
-- rank bar, both filter dropdowns, quantity stepper, create/create-all/
-- cancel buttons, close button, collapse-all + per-row expand glyphs,
-- recipe icon + item-quality border colouring, all 8 reagent slots.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")
local Compat = ElvUI.Compat

local FRAME_WIDTH, FRAME_HEIGHT = 720, 508
local TRADE_SKILL_ROW_COUNT = 25
local REAGENT_COUNT = 8

-- Real ElvUI's own numbers for this window (`Blizzard/TradeSkill.lua`,
-- `ElvUI-vanilla`), already tuned against the SAME 720x508 resize
-- and 25-row list.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -12, -34, 0
local LIST_LEFT, LIST_TOP, LIST_RIGHT, LIST_BOTTOM = 14, -92, -367, 4
local DETAIL_RIGHT, DETAIL_BOTTOM = -38, 4
-- The two native scroll frames' own geometry in the two-column layout.
-- The list height is 25 rows of `TRADE_SKILL_HEIGHT` plus a little slack;
-- the detail frame is pinned from the frame's TOPRIGHT so it fills the
-- right-hand column.
local LIST_SCROLL_WIDTH, LIST_SCROLL_HEIGHT = 310, 405
local LIST_SCROLL_X, LIST_SCROLL_Y = 17, -95
local DETAIL_SCROLL_WIDTH, DETAIL_SCROLL_HEIGHT = 300, 381
local DETAIL_SCROLL_X, DETAIL_SCROLL_Y = -60, -95
local DETAIL_CHILD_WIDTH, DETAIL_CHILD_HEIGHT = 300, 150
local REAGENT_WIDTH, REAGENT_HEIGHT = 143, 40
-- Real ElvUI's own rank-bar fill colour for this window.
local RANK_BAR_COLOR = { 0.13, 0.28, 0.85 }

-- Native code shows/repositions this SHARED highlight bar under whichever
-- list row is hovered/selected -- a real, if minor, UX affordance. Left
-- unprotected, the top-level recursive strip below would Hide()+noop its
-- one Texture permanently, since it is a plain Frame (not a Button) and
-- therefore not exempt from that walk.
S.stripSkipNames["TradeSkillHighlightFrame"] = true

local function PromotePanelText()
	local fs = _G.TradeSkillFrameTitleText
	if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
end

-- Real ElvUI's own rank-bar fill colour. Has to be re-asserted on every
-- selection, not just at styling time: the native
-- `TradeSkillFrame_SetSelection` sets its own half-alpha pure blue
-- (`0, 0, 1, 0.5`) each time a recipe is picked.
local function SetRankBarColor()
	local bar = _G.TradeSkillRankFrame
	if bar then pcall(bar.SetStatusBarColor, bar, RANK_BAR_COLOR[1], RANK_BAR_COLOR[2], RANK_BAR_COLOR[3]) end
end

-- `TradeSkillFrame_SetSelection` is a bare global function -- the
-- confirmed-safe hook shape on this client. Re-crops
-- the recipe icon (a bare Button with no inherited border template) and
-- colours its border by the crafted item's quality. Reagent slots keep the
-- merchant-style black border (`S:StyleQuestItemSlot`).
local function ApplySelectionChrome(id)
	SetRankBarColor()

	local icon = _G.TradeSkillSkillIcon
	if icon then
		S:CreateIconEdges(icon)
		local okNormal, normalTexture = pcall(icon.GetNormalTexture, icon)
		if okNormal and normalTexture then
			pcall(icon.SetAlpha, icon, 1)
			pcall(normalTexture.SetTexCoord, normalTexture, 0.08, 0.92, 0.08, 0.92)
			pcall(normalTexture.ClearAllPoints, normalTexture)
			pcall(normalTexture.SetPoint, normalTexture, "TOPLEFT", icon, "TOPLEFT", 1, -1)
			pcall(normalTexture.SetPoint, normalTexture, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
		else
			pcall(icon.SetAlpha, icon, 0)
		end

		local okLink, skillLink = pcall(GetTradeSkillItemLink, id)
		local quality
		if okLink and skillLink then
			local itemId = Compat.match(skillLink, "item:(%d+)")
			if itemId then
				local okInfo, _, _, q = pcall(GetItemInfo, itemId)
				if okInfo then quality = q end
			end
		end
		local okColor, r, g, b = false
		if quality then okColor, r, g, b = pcall(GetItemQualityColor, quality) end
		if okColor then
			S:SetIconEdgeColor(icon, r, g, b)
		else
			S:SetIconEdgeColor(icon)
		end
	end

end

-- Periodic glyph sync -- see file header for why this replaces real
-- ElvUI's own `SetNormalTexture` hook. Reads native state directly
-- (`GetTradeSkillInfo`) instead of trying to observe what native code
-- assigns to a texture slot.
local rowGlyphPollStarted = false
local function PollRowGlyphs()
	local frame = _G.TradeSkillFrame
	if not frame then return end
	local okShown, shown = pcall(frame.IsVisible, frame)
	if not (okShown and shown) then return end

	local okOffset, offset = pcall(FauxScrollFrame_GetOffset, _G.TradeSkillListScrollFrame)
	offset = (okOffset and tonumber(offset)) or 0

	local anyExpanded = false
	local i
	for i = 1, TRADE_SKILL_ROW_COUNT do
		local button = _G["TradeSkillSkill" .. i]
		local okRowShown, rowShown = false, false
		if button then okRowShown, rowShown = pcall(button.IsShown, button) end
		if button and okRowShown and rowShown then
			local okInfo, _, itemType, _, isExpanded = pcall(GetTradeSkillInfo, offset + i)
			if okInfo and itemType == "header" then
				S:SetGlyphShown(button, true)
				S:SetGlyphExpanded(button, isExpanded and true or false)
				if isExpanded then anyExpanded = true end
			else
				S:SetGlyphShown(button, false)
			end
		end
	end

	-- The "All" button toggles between expand-all/collapse-all; there is
	-- no native getter for its own intended state, so its glyph mirrors
	-- whether ANY header is currently expanded -- matches what the button
	-- actually does when clicked (collapses everything if something is
	-- open, expands everything otherwise).
	S:SetGlyphExpanded(_G.TradeSkillCollapseAllButton, anyExpanded)
end

-- Native anchors already chain 3/5/7 off 1/3/5 (BOTTOMLEFT); only the
-- horizontal gap in each pair needs tightening for the new sizing.
local function RepositionReagentPair(a, b)
	local left, right = _G["TradeSkillReagent" .. a], _G["TradeSkillReagent" .. b]
	if left and right then
		pcall(right.ClearAllPoints, right)
		pcall(right.SetPoint, right, "LEFT", left, "RIGHT", 3, 0)
	end
end

local function ApplyTradeSkillChrome(frame)
	S:StripTextures(frame, true)
	S:Kill(_G.TradeSkillFramePortrait)

	-- The selection highlight sits 3 units low against the row text.
	S:ShiftRegionInFrame(_G.TradeSkillHighlight, _G.TradeSkillHighlightFrame, 0, 3)

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	PromotePanelText()

	-- Two independent panel hosts (not two calls to `S:CreatePanel` on the
	-- SAME frame -- `S:CreateSurface`'s one-elvBackground-per-frame guard
	-- would just hand back the first one). Matches real ElvUI's own
	-- `bg1`/`bg2` split: a visible seam between the list and detail panes.
	if not frame.elvListPane then
		local okPane, pane = pcall(CreateFrame, "Frame", nil, frame)
		if okPane and pane then
			local okLevel, level = pcall(frame.GetFrameLevel, frame)
			pcall(pane.SetFrameLevel, pane, (okLevel and tonumber(level)) or 0)
			pcall(pane.SetPoint, pane, "TOPLEFT", frame, "TOPLEFT", LIST_LEFT, LIST_TOP)
			pcall(pane.SetPoint, pane, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
			S:CreateSurface(pane, S.PANEL_COLOR)
			frame.elvListPane = pane
		end
	end
	if frame.elvListPane and not frame.elvDetailPane then
		local okPane, pane = pcall(CreateFrame, "Frame", nil, frame)
		if okPane and pane then
			local okLevel, level = pcall(frame.GetFrameLevel, frame)
			pcall(pane.SetFrameLevel, pane, (okLevel and tonumber(level)) or 0)
			pcall(pane.SetPoint, pane, "TOPLEFT", frame.elvListPane, "TOPRIGHT", 3, 0)
			pcall(pane.SetPoint, pane, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", DETAIL_RIGHT, DETAIL_BOTTOM)
			S:CreateSurface(pane, S.PANEL_COLOR)
			frame.elvDetailPane = pane
		end
	end

	-- Rank bar. `$parentBorder` is a BUTTON, and its native 281x32
	-- `UI-Character-Skills-BarBorder` art lives in its NormalTexture, which
	-- no `S:StripTextures` call can reach (that walk covers `GetRegions()`
	-- only, and never descends into a Button). Left drawn, that art is
	-- narrower than the resized 420px bar and sits at its LEFT edge, so the
	-- whole bar reads as left-aligned and off-centre. `S:StripButtonArt`
	-- is the tool for exactly this shape.
	local rankFrame = _G.TradeSkillRankFrame
	S:StripButtonArt(_G.TradeSkillRankFrameBorder)
	-- The native half-alpha white wash the client re-tints on every
	-- selection (`TradeSkillRankFrameBackground:SetVertexColor`) -- the
	-- recessed well `S:StyleStatusBar` builds is the replacement.
	S:Kill(_G.TradeSkillRankFrameBackground)
	S:StyleStatusBar(rankFrame)
	SetRankBarColor()
	pcall(rankFrame.SetWidth, rankFrame, 420)
	pcall(rankFrame.SetHeight, rankFrame, 18)
	pcall(rankFrame.ClearAllPoints, rankFrame)
	-- Real ElvUI's own offset here is -10. -12 is the EXACT centre of the
	-- panel this bar sits on: the panel spans 10 .. -34, so its midpoint is
	-- 12px left of the frame's own.
	pcall(rankFrame.SetPoint, rankFrame, "TOP", frame, "TOP", -12, -38)
	local skillName = _G.TradeSkillRankFrameSkillName
	if skillName then pcall(skillName.Hide, skillName) end
	local skillRank = _G.TradeSkillRankFrameSkillRank
	if skillRank then
		-- Reparented off the (now hidden) skill-name FontString it is
		-- natively chained to, so the rank text keeps a live anchor.
		pcall(skillRank.SetParent, skillRank, rankFrame)
		pcall(skillRank.ClearAllPoints, skillRank)
		-- Real ElvUI offsets this by +58, which is where it lands next to
		-- the skill-name text it hides anyway. Centred instead, since the
		-- rank is then the bar's only label.
		-- `justifyH` rather than a zero width: the FontString keeps its
		-- native 128px box, centred on the bar, and centres the text inside
		-- it -- natively the box is LEFT-justified, which put the text
		-- 64px left of wherever it was anchored.
		pcall(skillRank.SetPoint, skillRank, "CENTER", rankFrame, "CENTER", 0, 0)
		pcall(skillRank.SetJustifyH, skillRank, "CENTER")
	end

	-- The two-column relayout. Both native scroll frames are stacked
	-- vertically in the 384-wide window and have to be moved/resized, or
	-- the detail pane lands in the lower left, on top of the list.
	local listScroll = _G.TradeSkillListScrollFrame
	if listScroll then
		S:StripTextures(listScroll, false)
		pcall(listScroll.SetWidth, listScroll, LIST_SCROLL_WIDTH)
		pcall(listScroll.SetHeight, listScroll, LIST_SCROLL_HEIGHT)
		pcall(listScroll.ClearAllPoints, listScroll)
		pcall(listScroll.SetPoint, listScroll, "TOPLEFT", frame, "TOPLEFT", LIST_SCROLL_X, LIST_SCROLL_Y)
	end

	local detailScroll = _G.TradeSkillDetailScrollFrame
	if detailScroll then
		S:StripTextures(detailScroll, false)
		pcall(detailScroll.SetWidth, detailScroll, DETAIL_SCROLL_WIDTH)
		pcall(detailScroll.SetHeight, detailScroll, DETAIL_SCROLL_HEIGHT)
		pcall(detailScroll.ClearAllPoints, detailScroll)
		pcall(detailScroll.SetPoint, detailScroll, "TOPRIGHT", frame, "TOPRIGHT", DETAIL_SCROLL_X, DETAIL_SCROLL_Y)
	end

	local detailChild = _G.TradeSkillDetailScrollChildFrame
	if detailChild then
		S:StripTextures(detailChild, false)
		pcall(detailChild.SetWidth, detailChild, DETAIL_CHILD_WIDTH)
		pcall(detailChild.SetHeight, detailChild, DETAIL_CHILD_HEIGHT)
	end

	S:StyleDropDownBox(_G.TradeSkillInvSlotDropDown)
	pcall(_G.TradeSkillInvSlotDropDown.ClearAllPoints, _G.TradeSkillInvSlotDropDown)
	pcall(_G.TradeSkillInvSlotDropDown.SetPoint, _G.TradeSkillInvSlotDropDown, "RIGHT", rankFrame, "RIGHT", 9, -30)

	S:StyleDropDownBox(_G.TradeSkillSubClassDropDown)
	pcall(_G.TradeSkillSubClassDropDown.ClearAllPoints, _G.TradeSkillSubClassDropDown)
	pcall(_G.TradeSkillSubClassDropDown.SetPoint, _G.TradeSkillSubClassDropDown, "RIGHT", _G.TradeSkillInvSlotDropDown, "LEFT", 10, 0)

	-- List pane: collapse-all control + expand-tab chrome. The native
	-- expand tab's art is stripped, and the button is re-seated on the
	-- (now invisible) tab's own anchor -- a hidden texture still anchors --
	-- with real ElvUI's own offsets, which centre the replacement glyph
	-- where the native tab art used to frame it.
	S:StripTextures(_G.TradeSkillExpandButtonFrame, false)
	S:StylePlusMinusButton(_G.TradeSkillCollapseAllButton, true)
	local collapseAll = _G.TradeSkillCollapseAllButton
	if collapseAll and _G.TradeSkillExpandTabLeft then
		pcall(collapseAll.ClearAllPoints, collapseAll)
		pcall(collapseAll.SetPoint, collapseAll, "LEFT", _G.TradeSkillExpandTabLeft, "RIGHT", -8, 5)
	end

	local i
	for i = 1, TRADE_SKILL_ROW_COUNT do
		S:StylePlusMinusButton(_G["TradeSkillSkill" .. i], true)
	end

	-- Detail pane. NO field surface on the scroll frame itself -- see the
	-- file header; it would draw over the scroll child's own text.
	-- Always show the scrollbar rather than auto-hiding when content
	-- fits -- matches real ElvUI's own explicit choice here.
	_G.TradeSkillDetailScrollFrame.scrollBarHideable = nil
	local detailBar = _G.TradeSkillDetailScrollFrameScrollBar
	if detailBar then
		S:HandleScrollBar(detailBar)
		pcall(detailBar.ClearAllPoints, detailBar)
		pcall(detailBar.SetPoint, detailBar, "TOPLEFT", _G.TradeSkillDetailScrollFrame, "TOPRIGHT", 3, -16)
	end
	local listBar = _G.TradeSkillListScrollFrameScrollBar
	if listBar then S:HandleScrollBar(listBar) end

	pcall(_G.TradeSkillCancelButton.ClearAllPoints, _G.TradeSkillCancelButton)
	pcall(_G.TradeSkillCancelButton.SetPoint, _G.TradeSkillCancelButton, "TOPRIGHT", _G.TradeSkillDetailScrollFrame, "BOTTOMRIGHT", 19, -3)
	S:StyleUIPanelButton(_G.TradeSkillCancelButton)

	pcall(_G.TradeSkillCreateButton.ClearAllPoints, _G.TradeSkillCreateButton)
	pcall(_G.TradeSkillCreateButton.SetPoint, _G.TradeSkillCreateButton, "TOPRIGHT", _G.TradeSkillCancelButton, "TOPLEFT", -3, 0)
	S:StyleUIPanelButton(_G.TradeSkillCreateButton)

	pcall(_G.TradeSkillCreateAllButton.ClearAllPoints, _G.TradeSkillCreateAllButton)
	pcall(_G.TradeSkillCreateAllButton.SetPoint, _G.TradeSkillCreateAllButton, "TOPLEFT", _G.TradeSkillDetailScrollFrame, "BOTTOMLEFT", 0, -3)
	S:StyleUIPanelButton(_G.TradeSkillCreateAllButton)

	-- Quantity stepper: [-] [box] [+] chained left to right, 3px gaps,
	-- inside the 76px gap between Create All (detail left edge + 80) and
	-- Create (detail right edge - 144). The native layout anchors
	-- Create All to Create and the increment button to Create
	-- independently; once Create All is re-seated on the detail pane's
	-- left edge, those two chains no longer agree, and the increment
	-- button (native 23x22, still anchored to Create) lands under the
	-- input box, which then swallows its clicks. So every stepper piece
	-- is chained off the previous one and sized to fit: 16px arrows
	-- (icon 13px, real ElvUI's `HandleNextPrevButton` icon size) and a
	-- 32px box. Button size is set BEFORE styling, because
	-- `StyleSquareIconButton` sizes a scaled icon from the current size.
	local decrement, increment = _G.TradeSkillDecrementButton, _G.TradeSkillIncrementButton
	local inputBox = _G.TradeSkillInputBox
	if decrement then
		pcall(decrement.SetWidth, decrement, 16)
		pcall(decrement.SetHeight, decrement, 16)
		pcall(decrement.ClearAllPoints, decrement)
		pcall(decrement.SetPoint, decrement, "LEFT", _G.TradeSkillCreateAllButton, "RIGHT", 3, 0)
	end
	if increment then
		pcall(increment.SetWidth, increment, 16)
		pcall(increment.SetHeight, increment, 16)
	end
	S:StyleSquareIconButton(decrement, "LEFT", 0.8)
	S:StyleSquareIconButton(increment, "RIGHT", 0.8)

	S:StyleEditBox(inputBox)
	pcall(inputBox.SetWidth, inputBox, 32)
	pcall(inputBox.SetHeight, inputBox, 16)
	pcall(inputBox.ClearAllPoints, inputBox)
	pcall(inputBox.SetPoint, inputBox, "LEFT", decrement, "RIGHT", 3, 0)
	if increment then
		pcall(increment.ClearAllPoints, increment)
		pcall(increment.SetPoint, increment, "LEFT", inputBox, "RIGHT", 3, 0)
	end

	-- Recipe icon: a bare Button, no inherited template, so its
	-- NormalTexture IS the content (native `SetNormalTexture` on
	-- selection change) -- never blanket-stripped. Sizing/position only
	-- here; the border/crop/quality-colour happen in
	-- `ApplySelectionChrome`, since they need to reapply every selection.
	local skillIcon = _G.TradeSkillSkillIcon
	if skillIcon then
		pcall(skillIcon.SetWidth, skillIcon, 47)
		pcall(skillIcon.SetHeight, skillIcon, 47)
		pcall(skillIcon.ClearAllPoints, skillIcon)
		pcall(skillIcon.SetPoint, skillIcon, "TOPLEFT", 1, -3)
	end
	local skillNameFS = _G.TradeSkillSkillName
	if skillNameFS then
		pcall(skillNameFS.ClearAllPoints, skillNameFS)
		pcall(skillNameFS.SetPoint, skillNameFS, "TOPLEFT", 55, -3)
	end
	local reqLabel = _G.TradeSkillRequirementLabel
	if reqLabel then pcall(reqLabel.SetTextColor, reqLabel, 1, 0.80, 0.10) end

	for i = 1, REAGENT_COUNT do
		S:StyleQuestItemSlot(_G["TradeSkillReagent" .. i], REAGENT_WIDTH, REAGENT_HEIGHT)
	end
	local reagentLabel = _G.TradeSkillReagentLabel
	if reagentLabel and skillIcon then
		pcall(reagentLabel.ClearAllPoints, reagentLabel)
		pcall(reagentLabel.SetPoint, reagentLabel, "TOPLEFT", skillIcon, "BOTTOMLEFT", 5, -10)
	end
	local firstReagent = _G.TradeSkillReagent1
	if firstReagent and reagentLabel then
		pcall(firstReagent.ClearAllPoints, firstReagent)
		pcall(firstReagent.SetPoint, firstReagent, "TOPLEFT", reagentLabel, "BOTTOMLEFT", -3, -3)
	end
	RepositionReagentPair(1, 2)
	RepositionReagentPair(3, 4)
	RepositionReagentPair(5, 6)
	RepositionReagentPair(7, 8)

	S:StyleCloseButton(_G.TradeSkillFrameCloseButton)
	local close = _G.TradeSkillFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all -- picks up anything this server adds beyond vanilla.
	S:SkinChildren(frame)
end

local tradeSkillSkinApplied = false
local function ApplyTradeSkillSkin()
	if tradeSkillSkinApplied then return end
	local frame = _G.TradeSkillFrame
	if not frame then return end
	tradeSkillSkinApplied = true

	pcall(function() _G.TRADE_SKILLS_DISPLAYED = TRADE_SKILL_ROW_COUNT end)
	pcall(function()
		UIPanelWindows["TradeSkillFrame"] = { area = "doublewide", pushable = 0, whileDead = 1 }
	end)

	pcall(frame.SetWidth, frame, FRAME_WIDTH)
	pcall(frame.SetHeight, frame, FRAME_HEIGHT)

	-- The native hit rect (`right=34, bottom=75`) is cut for the 384x512
	-- window's own art; after the resize the bottom 75px is live panel, and
	-- the frame is `enableMouse="true"` and toplevel, so an uncut rect
	-- leaves an invisible click-eater. Re-cut to the panel, same as
	-- QuestLog/KeyBindings.
	pcall(frame.SetHitRectInsets, frame, PANEL_LEFT, -PANEL_RIGHT, -PANEL_TOP, PANEL_BOTTOM)

	-- `movable="true"` in the XML but no drag script anywhere, same gap as
	-- every other window in this family. The close button is passed so the
	-- handle stops at its left edge instead of covering it -- the handle
	-- sits 50 frame levels above the window.
	S:MakeDraggable(frame, _G.TradeSkillFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	-- Extra rows beyond vanilla's own native 8, one-time -- native
	-- `TradeSkillFrame_Update` reads `_G["TradeSkillSkill"..i]` by name up
	-- to `TRADE_SKILLS_DISPLAYED`, so simply raising that global and
	-- creating the missing buttons (identical template + anchor chain
	-- native code would use) is enough for it to start populating them.
	local i
	for i = 9, TRADE_SKILL_ROW_COUNT do
		if not _G["TradeSkillSkill" .. i] then
			local okBtn, btn = pcall(CreateFrame, "Button", "TradeSkillSkill" .. i, frame, "TradeSkillSkillButtonTemplate")
			if okBtn and btn then
				pcall(btn.SetPoint, btn, "TOPLEFT", _G["TradeSkillSkill" .. (i - 1)], "BOTTOMLEFT")
			end
		end
	end

	ApplyTradeSkillChrome(frame)

	-- The doublewide override means an open craft or auction window is no
	-- longer replaced by the panel manager: closed here instead.
	local ok = S:TryHookScript(frame, "OnShow", function()
		ApplyTradeSkillChrome(frame)
		S:CloseOtherDoublewidePanels(frame)
	end)
	if not ok then S:ReportSkinProblem() end

	local hookOk = pcall(function() S:SecureHook("TradeSkillFrame_SetSelection", ApplySelectionChrome) end)
	if not hookOk then S:ReportSkinProblem() end

	if not rowGlyphPollStarted then
		rowGlyphPollStarted = true
		E:ScheduleRepeatingTimer(PollRowGlyphs, 0.3)
	end
end

local function LoadSkin()
	S:WaitForGlobal("TradeSkillFrame", ApplyTradeSkillSkin)
end

S:AddBlizzardSkin("tradeskill", LoadSkin)
