-- Skins > Blizzard > Craft -- reskins the native craft window (CraftFrame:
-- Enchanting, and a hunter's Beast Training) in place, resized to the same
-- two-pane "doublewide" layout as TradeSkill.lua. Port of real ElvUI's
-- `Blizzard/Craft.lua` (source/ElvUI-vanilla), which is that window's
-- TradeSkill skin minus the controls CraftFrame does not have (filter
-- dropdowns, Create All, quantity stepper).
--
-- Structure per `AddOns/Blizzard_CraftUI/Blizzard_CraftUI.xml`/`.lua`. Every
-- mechanism below is the one TradeSkill.lua uses and documents at length; only
-- what differs is noted here:
--
-- - **Gated by the `tradeskill` flag.** Real ElvUI-vanilla's Craft skin reads
--   `E.private.skins.blizzard.craft`, a key its own defaults and options never
--   declare, so there is no upstream key to inherit; both profession windows
--   follow the one real toggle.
-- - **`## LoadOnDemand: 1`** (`Blizzard_CraftUI`): `S:WaitForGlobal`.
-- - **`CraftIcon` shows the craft SPELL** (`SetNormalTexture(GetCraftIcon(id))`,
--   tooltip `SetCraftSpell`), and `GetCraftItemLink` returns an `enchant:` link
--   for Enchanting, so the icon border is not quality-coloured.
-- - **Reagent slots use the shared `S:StyleQuestItemSlot`** (Skins.lua), the
--   merchant window's item-slot look, same as TradeSkill.lua.
-- - **`CraftSkillBorderLeft`/`Right`** (the thin line under the native rank
--   bar) are re-`Show()`n by `CraftFrame_Update` on every update, past the
--   strip's `Show = noop`; their alpha is set to 0, which `Show()` keeps.
-- - **`CraftReagent7` is natively anchored below `CraftReagent6`**, the
--   right-hand slot of the third row, so slots 7-8 would continue in the right
--   column. It is re-anchored below `CraftReagent5`.
-- - **The rank bar colour is reset in `CraftFrame_Update`**, not in the
--   selection function (TradeSkill resets it on selection), so that global is
--   hooked for it.
-- - **`CraftFramePointsText`/`Label`** (pet training points, shown whenever the
--   player has any) are natively anchored 86 units above the frame's bottom
--   left, which after the resize is inside the list pane, over its rows. They
--   are moved under the rank bar, into the header strip that TradeSkill's
--   filter dropdowns occupy.
--
-- SCOPE: outer chrome, doublewide resize, list/detail panel backgrounds, rank
-- bar, training points text, create/cancel buttons, close button,
-- collapse-all + per-row expand glyphs, recipe icon, all 8 reagent slots.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

local FRAME_WIDTH, FRAME_HEIGHT = 720, 508
local CRAFT_ROW_COUNT = 25
local REAGENT_COUNT = 8

-- Real ElvUI's numbers, identical to its TradeSkill skin.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -12, -34, 0
local LIST_LEFT, LIST_TOP, LIST_RIGHT, LIST_BOTTOM = 14, -92, -367, 4
local DETAIL_RIGHT, DETAIL_BOTTOM = -38, 4
local LIST_SCROLL_WIDTH, LIST_SCROLL_HEIGHT = 310, 405
local LIST_SCROLL_X, LIST_SCROLL_Y = 17, -95
local DETAIL_SCROLL_WIDTH, DETAIL_SCROLL_HEIGHT = 300, 381
local DETAIL_SCROLL_X, DETAIL_SCROLL_Y = -60, -95
local DETAIL_CHILD_WIDTH, DETAIL_CHILD_HEIGHT = 300, 150
local REAGENT_WIDTH, REAGENT_HEIGHT = 143, 40
local RANK_BAR_COLOR = { 0.13, 0.28, 0.85 }

-- The shared selection highlight bar: a plain Frame, so the recursive strip
-- would otherwise hide its texture for good.
S.stripSkipNames["CraftHighlightFrame"] = true

-- FontStrings placed directly on CraftFrame draw below the panel surface at the
-- same frame level unless raised to OVERLAY.
local function PromotePanelText()
	local names = { "CraftFrameTitleText", "CraftFramePointsText", "CraftFramePointsLabel" }
	local i
	for i = 1, table.getn(names) do
		local fs = _G[names[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end
end

local function SetRankBarColor()
	local bar = _G.CraftRankFrame
	if bar then pcall(bar.SetStatusBarColor, bar, RANK_BAR_COLOR[1], RANK_BAR_COLOR[2], RANK_BAR_COLOR[3]) end
end

-- Post-hook on the CraftFrame_SetSelection global: re-crops the recipe icon,
-- whose NormalTexture native code sets on every selection.
local function ApplySelectionChrome()
	local icon = _G.CraftIcon
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
	end

end

-- Periodic +/- glyph sync from GetCraftInfo (craftType 3rd, isExpanded 5th),
-- for the same reason as TradeSkill.lua's: the native SetNormalTexture calls
-- cannot be hooked on UA.
local rowGlyphPollStarted = false
local function PollRowGlyphs()
	local frame = _G.CraftFrame
	if not frame then return end
	local okShown, shown = pcall(frame.IsVisible, frame)
	if not (okShown and shown) then return end

	local okOffset, offset = pcall(FauxScrollFrame_GetOffset, _G.CraftListScrollFrame)
	offset = (okOffset and tonumber(offset)) or 0

	local anyExpanded = false
	local i
	for i = 1, CRAFT_ROW_COUNT do
		local button = _G["Craft" .. i]
		local okRowShown, rowShown = false, false
		if button then okRowShown, rowShown = pcall(button.IsShown, button) end
		if button and okRowShown and rowShown then
			local okInfo, _, _, craftType, _, isExpanded = pcall(GetCraftInfo, offset + i)
			if okInfo and craftType == "header" then
				S:SetGlyphShown(button, true)
				S:SetGlyphExpanded(button, isExpanded and true or false)
				if isExpanded then anyExpanded = true end
			else
				S:SetGlyphShown(button, false)
			end
		end
	end

	S:SetGlyphExpanded(_G.CraftCollapseAllButton, anyExpanded)
end

local function RepositionReagentPair(a, b)
	local left, right = _G["CraftReagent" .. a], _G["CraftReagent" .. b]
	if left and right then
		pcall(right.ClearAllPoints, right)
		pcall(right.SetPoint, right, "LEFT", left, "RIGHT", 3, 0)
	end
end

local function CreatePane(frame, key)
	if frame[key] then return frame[key] end
	local okPane, pane = pcall(CreateFrame, "Frame", nil, frame)
	if not okPane or not pane then return nil end
	local okLevel, level = pcall(frame.GetFrameLevel, frame)
	pcall(pane.SetFrameLevel, pane, (okLevel and tonumber(level)) or 0)
	frame[key] = pane
	return pane
end

local function ApplyCraftChrome(frame)
	S:StripTextures(frame, true)
	S:Kill(_G.CraftFramePortrait)

	local borderLeft, borderRight = _G.CraftSkillBorderLeft, _G.CraftSkillBorderRight
	if borderLeft then pcall(borderLeft.SetAlpha, borderLeft, 0) end
	if borderRight then pcall(borderRight.SetAlpha, borderRight, 0) end

	-- The selection highlight sits 3 units low against the row text.
	S:ShiftRegionInFrame(_G.CraftHighlight, _G.CraftHighlightFrame, 0, 3)

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	PromotePanelText()

	if not frame.elvListPane then
		local pane = CreatePane(frame, "elvListPane")
		if pane then
			pcall(pane.SetPoint, pane, "TOPLEFT", frame, "TOPLEFT", LIST_LEFT, LIST_TOP)
			pcall(pane.SetPoint, pane, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
			S:CreateSurface(pane, S.PANEL_COLOR)
		end
	end
	if frame.elvListPane and not frame.elvDetailPane then
		local pane = CreatePane(frame, "elvDetailPane")
		if pane then
			pcall(pane.SetPoint, pane, "TOPLEFT", frame.elvListPane, "TOPRIGHT", 3, 0)
			pcall(pane.SetPoint, pane, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", DETAIL_RIGHT, DETAIL_BOTTOM)
			S:CreateSurface(pane, S.PANEL_COLOR)
		end
	end

	-- Rank bar: the border is a Button whose art is its NormalTexture, and the
	-- background wash is re-tinted by native code on every update.
	local rankFrame = _G.CraftRankFrame
	S:StripButtonArt(_G.CraftRankFrameBorder)
	S:Kill(_G.CraftRankFrameBackground)
	S:StyleStatusBar(rankFrame)
	SetRankBarColor()
	pcall(rankFrame.SetWidth, rankFrame, 420)
	pcall(rankFrame.SetHeight, rankFrame, 18)
	pcall(rankFrame.ClearAllPoints, rankFrame)
	pcall(rankFrame.SetPoint, rankFrame, "TOP", frame, "TOP", -12, -38)
	local skillName = _G.CraftRankFrameSkillName
	if skillName then pcall(skillName.Hide, skillName) end
	local skillRank = _G.CraftRankFrameSkillRank
	if skillRank then
		pcall(skillRank.SetParent, skillRank, rankFrame)
		pcall(skillRank.ClearAllPoints, skillRank)
		pcall(skillRank.SetPoint, skillRank, "CENTER", rankFrame, "CENTER", 0, 0)
		pcall(skillRank.SetJustifyH, skillRank, "CENTER")
	end

	-- The label stays natively anchored to the left of the value.
	local pointsText = _G.CraftFramePointsText
	if pointsText then
		pcall(pointsText.ClearAllPoints, pointsText)
		pcall(pointsText.SetPoint, pointsText, "TOPRIGHT", rankFrame, "BOTTOMRIGHT", 0, -10)
	end

	local listScroll = _G.CraftListScrollFrame
	if listScroll then
		S:StripTextures(listScroll, false)
		pcall(listScroll.SetWidth, listScroll, LIST_SCROLL_WIDTH)
		pcall(listScroll.SetHeight, listScroll, LIST_SCROLL_HEIGHT)
		pcall(listScroll.ClearAllPoints, listScroll)
		pcall(listScroll.SetPoint, listScroll, "TOPLEFT", frame, "TOPLEFT", LIST_SCROLL_X, LIST_SCROLL_Y)
	end

	local detailScroll = _G.CraftDetailScrollFrame
	if detailScroll then
		S:StripTextures(detailScroll, false)
		pcall(detailScroll.SetWidth, detailScroll, DETAIL_SCROLL_WIDTH)
		pcall(detailScroll.SetHeight, detailScroll, DETAIL_SCROLL_HEIGHT)
		pcall(detailScroll.ClearAllPoints, detailScroll)
		pcall(detailScroll.SetPoint, detailScroll, "TOPRIGHT", frame, "TOPRIGHT", DETAIL_SCROLL_X, DETAIL_SCROLL_Y)
	end

	local detailChild = _G.CraftDetailScrollChildFrame
	if detailChild then
		S:StripTextures(detailChild, false)
		pcall(detailChild.SetWidth, detailChild, DETAIL_CHILD_WIDTH)
		pcall(detailChild.SetHeight, detailChild, DETAIL_CHILD_HEIGHT)
	end

	S:StripTextures(_G.CraftExpandButtonFrame, false)
	S:StylePlusMinusButton(_G.CraftCollapseAllButton, true)
	local collapseAll = _G.CraftCollapseAllButton
	if collapseAll and _G.CraftExpandTabLeft then
		pcall(collapseAll.ClearAllPoints, collapseAll)
		pcall(collapseAll.SetPoint, collapseAll, "LEFT", _G.CraftExpandTabLeft, "RIGHT", -8, 5)
	end

	local i
	for i = 1, CRAFT_ROW_COUNT do
		S:StylePlusMinusButton(_G["Craft" .. i], true)
	end

	local detailBar = _G.CraftDetailScrollFrameScrollBar
	if detailBar then
		S:HandleScrollBar(detailBar)
		pcall(detailBar.ClearAllPoints, detailBar)
		pcall(detailBar.SetPoint, detailBar, "TOPLEFT", _G.CraftDetailScrollFrame, "TOPRIGHT", 3, -16)
	end
	local listBar = _G.CraftListScrollFrameScrollBar
	if listBar then S:HandleScrollBar(listBar) end

	local cancel = _G.CraftCancelButton
	if cancel then
		pcall(cancel.ClearAllPoints, cancel)
		pcall(cancel.SetPoint, cancel, "TOPRIGHT", _G.CraftDetailScrollFrame, "BOTTOMRIGHT", 19, -3)
		S:StyleUIPanelButton(cancel)
	end
	local create = _G.CraftCreateButton
	if create and cancel then
		pcall(create.ClearAllPoints, create)
		pcall(create.SetPoint, create, "TOPRIGHT", cancel, "TOPLEFT", -3, 0)
		S:StyleUIPanelButton(create)
	end

	-- Recipe icon: its NormalTexture is the content, never stripped; border and
	-- crop are applied per selection.
	local craftIcon = _G.CraftIcon
	if craftIcon then
		pcall(craftIcon.SetWidth, craftIcon, 47)
		pcall(craftIcon.SetHeight, craftIcon, 47)
		pcall(craftIcon.ClearAllPoints, craftIcon)
		pcall(craftIcon.SetPoint, craftIcon, "TOPLEFT", 1, -3)
	end
	local craftName = _G.CraftName
	if craftName then
		pcall(craftName.ClearAllPoints, craftName)
		pcall(craftName.SetPoint, craftName, "TOPLEFT", 55, -3)
	end
	local requirements = _G.CraftRequirements
	if requirements then pcall(requirements.SetTextColor, requirements, 1, 0.80, 0.10) end

	for i = 1, REAGENT_COUNT do
		S:StyleQuestItemSlot(_G["CraftReagent" .. i], REAGENT_WIDTH, REAGENT_HEIGHT)
	end
	-- The reagent label stays on its native anchor: CraftFrame_SetSelection
	-- re-anchors it below the description on every selection.
	local firstReagent = _G.CraftReagent1
	if firstReagent and _G.CraftReagentLabel then
		pcall(firstReagent.ClearAllPoints, firstReagent)
		pcall(firstReagent.SetPoint, firstReagent, "TOPLEFT", _G.CraftReagentLabel, "BOTTOMLEFT", -3, -3)
	end
	local seventh, fifth = _G.CraftReagent7, _G.CraftReagent5
	if seventh and fifth then
		pcall(seventh.ClearAllPoints, seventh)
		pcall(seventh.SetPoint, seventh, "TOPLEFT", fifth, "BOTTOMLEFT", 0, -2)
	end
	RepositionReagentPair(1, 2)
	RepositionReagentPair(3, 4)
	RepositionReagentPair(5, 6)
	RepositionReagentPair(7, 8)

	S:StyleCloseButton(_G.CraftFrameCloseButton)
	local close = _G.CraftFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	S:SkinChildren(frame)
end

local craftSkinApplied = false
local function ApplyCraftSkin()
	if craftSkinApplied then return end
	local frame = _G.CraftFrame
	if not frame then return end
	craftSkinApplied = true

	pcall(function() _G.CRAFTS_DISPLAYED = CRAFT_ROW_COUNT end)
	pcall(function()
		UIPanelWindows["CraftFrame"] = { area = "doublewide", pushable = 0, whileDead = 1 }
	end)

	pcall(frame.SetWidth, frame, FRAME_WIDTH)
	pcall(frame.SetHeight, frame, FRAME_HEIGHT)
	-- The native hit rect (right 34, bottom 75) is cut for the 384x512 art; after
	-- the resize the bottom strip is live panel, so it is re-cut to the panel.
	pcall(frame.SetHitRectInsets, frame, PANEL_LEFT, -PANEL_RIGHT, -PANEL_TOP, PANEL_BOTTOM)

	S:MakeDraggable(frame, _G.CraftFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	-- CraftFrame_Update addresses rows by name up to CRAFTS_DISPLAYED.
	local i
	for i = 9, CRAFT_ROW_COUNT do
		if not _G["Craft" .. i] then
			local okBtn, btn = pcall(CreateFrame, "Button", "Craft" .. i, frame, "CraftButtonTemplate")
			if okBtn and btn then
				pcall(btn.SetPoint, btn, "TOPLEFT", _G["Craft" .. (i - 1)], "BOTTOMLEFT")
			end
		end
	end

	ApplyCraftChrome(frame)

	-- The doublewide override means an open trade skill or auction window is
	-- no longer replaced by the panel manager: closed here instead.
	local ok = S:TryHookScript(frame, "OnShow", function()
		ApplyCraftChrome(frame)
		S:CloseOtherDoublewidePanels(frame)
	end)
	if not ok then S:ReportSkinProblem() end

	local selectionOk = pcall(function() S:SecureHook("CraftFrame_SetSelection", ApplySelectionChrome) end)
	if not selectionOk then S:ReportSkinProblem() end

	local updateOk = pcall(function() S:SecureHook("CraftFrame_Update", SetRankBarColor) end)
	if not updateOk then S:ReportSkinProblem() end

	if not rowGlyphPollStarted then
		rowGlyphPollStarted = true
		E:ScheduleRepeatingTimer(PollRowGlyphs, 0.3)
	end
end

local function LoadSkin()
	S:WaitForGlobal("CraftFrame", ApplyCraftSkin)
end

S:AddBlizzardSkin("tradeskill", LoadSkin)
