-- Skins > Blizzard > Trainer -- reskins the native class/profession trainer
-- window (ClassTrainerFrame) in place, resized to a two-pane "doublewide"
-- layout like TradeSkill.lua and Craft.lua. Port of real ElvUI's
-- `Blizzard/Trainer.lua` (ElvUI-vanilla); its numbers are used unless
-- noted otherwise.
--
-- Structure per `AddOns/Blizzard_TrainerUI/Blizzard_TrainerUI.xml`/`.lua` and
-- `FrameXML/ClassTrainerFrameTemplates.xml`. The mechanisms shared with the
-- profession windows (FauxScrollFrame rows as siblings of the list scroll
-- frame, no surface on a scroll frame with a ScrollChild, glyph poll instead
-- of SetNormalTexture hooks, the icon's NormalTexture being its content) are
-- documented in TradeSkill.lua. Trainer-specific points:
--
-- - **`## LoadOnDemand: 1`** (`Blizzard_TrainerUI`): `S:WaitForGlobal`.
-- - **Row count is reset on every update.** `ClassTrainerFrame_Update` calls
--   `ClassTrainer_SetToClassTrainer` / `ClassTrainer_SetToTradeSkillTrainer`,
--   which set `CLASS_TRAINER_SKILLS_DISPLAYED` back to 11/10 and resize both
--   scroll frames, before the row loop reads the constant. Both globals are
--   post-hooked to restore `TRAINER_ROW_COUNT` and to write both scroll
--   heights back. Real ElvUI instead noops the scroll frames' `SetHeight`,
--   which does not hold on UA. Anchoring a scroll frame top and bottom is not
--   enough either: UA derives the vertical scroll range from the explicitly
--   set height, not the anchored one (detail frame drawn 280 tall with the
--   native 119 set, child 150 -> range 31, so a short description scrolled),
--   hence the explicit height plus `UpdateScrollChildRect`.
-- - **Every direct region of ClassTrainerFrame is chrome except the NPC name
--   and greeting FontStrings**: those are raised to OVERLAY, then the
--   BACKGROUND/BORDER/ARTWORK layers are disabled. The portrait (BACKGROUND)
--   is reloaded by `SetPortraitTexture` on every update, which the strip
--   alone does not hold.
-- - **`ClassTrainerSkillIcon` carries an unnamed 64x64 `UI-EmptySlot` frame
--   texture** besides its NormalTexture (the spell icon itself). Only that
--   texture is hidden, identified by path or size; the NormalTexture is never
--   stripped.
-- - **The collapse-all button is anchored to the frame**, not to
--   `ClassTrainerExpandTabLeft`: that texture is stripped, and a widget
--   anchored to a hidden region does not reliably re-resolve its position on
--   this client. The offset is the same point real ElvUI's anchor resolves to.
-- - **`ClassTrainerMoneyFrame`** (the player's money) sits left of the
--   Train/Exit buttons at the bottom of the detail pane; real ElvUI's spot
--   overlaps the lower edge of the detail text.
-- - Gap between the two panes is 3 (real ElvUI: 1), matching TradeSkill.lua
--   and Craft.lua.
--
-- SCOPE: outer chrome, doublewide resize, list/detail panel backgrounds, NPC
-- name/greeting, filter dropdown, both scrollbars, train/exit buttons, money
-- frame, close button, collapse-all + per-row expand glyphs, skill icon.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")
local Compat = ElvUI.Compat

local FRAME_WIDTH, FRAME_HEIGHT = 710, 470
local TRAINER_ROW_COUNT = 19

-- Real ElvUI's numbers for this window.
local PANEL = { left = 15, top = -11, right = -34, bottom = 74 }
local LIST_PANE = { left = 18, top = -77, right = -367, bottom = 77 }
local DETAIL_PANE_RIGHT, DETAIL_PANE_BOTTOM = -38, 77
-- Both scroll frames are pinned top AND bottom (`bottom` is the offset above
-- the frame's bottom edge) and also get the matching explicit height, which
-- native ClassTrainer_SetTo*Trainer (184/168, 119/135) overwrites on every
-- update. The detail frame ends just above the button row at the bottom of
-- the detail pane.
local LIST_SCROLL = { x = 17, y = -85, width = 300, bottom = 85 }
local DETAIL_SCROLL = { x = -64, y = -85, width = 295, bottom = 105 }
LIST_SCROLL.height = FRAME_HEIGHT + LIST_SCROLL.y - LIST_SCROLL.bottom
DETAIL_SCROLL.height = FRAME_HEIGHT + DETAIL_SCROLL.y - DETAIL_SCROLL.bottom
local BUTTON_INSET = 3
local DETAIL_CHILD_WIDTH, DETAIL_CHILD_HEIGHT = 295, 150
-- ClassTrainerExpandTabLeft's RIGHT point (frame TOPLEFT 23,-86) plus real
-- ElvUI's 5,20 offset.
local COLLAPSE_ALL_X, COLLAPSE_ALL_Y = 28, -66

-- The shared selection highlight bar: a plain Frame, so the recursive strip
-- would otherwise hide its texture for good.
S.stripSkipNames["ClassTrainerSkillHighlightFrame"] = true

-- Post-hook on ClassTrainer_SetToClassTrainer/SetToTradeSkillTrainer, which
-- run inside ClassTrainerFrame_Update before its row loop.
local function RestoreTrainerLayout()
	_G.CLASS_TRAINER_SKILLS_DISPLAYED = TRAINER_ROW_COUNT
	local listScroll = _G.ClassTrainerListScrollFrame
	if listScroll then pcall(listScroll.SetHeight, listScroll, LIST_SCROLL.height) end
	local detailScroll = _G.ClassTrainerDetailScrollFrame
	if detailScroll then
		pcall(detailScroll.SetHeight, detailScroll, DETAIL_SCROLL.height)
		pcall(detailScroll.UpdateScrollChildRect, detailScroll)
	end
end

-- Hides the skill icon's decorative empty-slot frame. Runs once, at skin time,
-- before native code has ever called SetNormalTexture on the button: on the
-- legacy client the spell icon NormalTexture itself reports 64x64 as well, so
-- a later pass would take the icon for the slot art.
local function HideSkillIconSlotArt(icon)
	if icon.elvSlotArtHidden then return end
	icon.elvSlotArtHidden = true
	local okRegions, regions = pcall(function() return { icon:GetRegions() } end)
	if not okRegions or not regions then return end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "Texture" then
			local okPath, path = pcall(region.GetTexture, region)
			local okWidth, width = pcall(region.GetWidth, region)
			local isSlot = okPath and type(path) == "string"
				and string.find(string.lower(path), "emptyslot", 1, true)
			if isSlot or (okWidth and tonumber(width) == 64) then
				pcall(region.SetAlpha, region, 0)
				pcall(region.Hide, region)
				region.Show = E.noop
			end
		end
	end
end

-- Post-hook on the ClassTrainer_SetSelection global: re-crops the skill icon,
-- whose NormalTexture native code sets on every selection.
local function ApplySelectionChrome()
	local icon = _G.ClassTrainerSkillIcon
	if not icon then return end
	S:CreateIconEdges(icon)
	local okNormal, normalTexture = pcall(icon.GetNormalTexture, icon)
	if okNormal and normalTexture then
		pcall(normalTexture.SetTexCoord, normalTexture, 0.08, 0.92, 0.08, 0.92)
		pcall(normalTexture.ClearAllPoints, normalTexture)
		pcall(normalTexture.SetPoint, normalTexture, "TOPLEFT", icon, "TOPLEFT", 1, -1)
		pcall(normalTexture.SetPoint, normalTexture, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
	end
end

-- Periodic +/- glyph sync from GetTrainerServiceInfo (serviceType 3rd,
-- isExpanded 4th): the native SetNormalTexture calls cannot be hooked on UA.
local rowGlyphPollStarted = false
local function PollRowGlyphs()
	local frame = _G.ClassTrainerFrame
	if not frame then return end
	local okShown, shown = pcall(frame.IsVisible, frame)
	if not (okShown and shown) then return end

	local okOffset, offset = pcall(FauxScrollFrame_GetOffset, _G.ClassTrainerListScrollFrame)
	offset = (okOffset and tonumber(offset)) or 0

	local anyExpanded = false
	local i
	for i = 1, TRAINER_ROW_COUNT do
		local button = _G["ClassTrainerSkill" .. i]
		local okRowShown, rowShown = false, false
		if button then okRowShown, rowShown = pcall(button.IsShown, button) end
		if button and okRowShown and rowShown then
			local okInfo, _, _, serviceType, isExpanded = pcall(GetTrainerServiceInfo, offset + i)
			if okInfo and serviceType == "header" then
				local expanded = Compat.bool(isExpanded)
				S:SetGlyphShown(button, true)
				S:SetGlyphExpanded(button, expanded)
				if expanded then anyExpanded = true end
			else
				S:SetGlyphShown(button, false)
			end
		end
	end

	S:SetGlyphExpanded(_G.ClassTrainerCollapseAllButton, anyExpanded)
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

-- FontStrings placed directly on ClassTrainerFrame; raised to OVERLAY so they
-- survive the frame's disabled lower layers and draw above the panel surface.
local function ApplyHeaderText(frame)
	local nameText = _G.ClassTrainerNameText
	if nameText then
		pcall(nameText.SetDrawLayer, nameText, "OVERLAY")
		if frame.elvBackground then
			pcall(nameText.ClearAllPoints, nameText)
			pcall(nameText.SetPoint, nameText, "TOP", frame.elvBackground, "TOP", 0, -6)
		end
	end
	local greeting = _G.ClassTrainerGreetingText
	if greeting then pcall(greeting.SetDrawLayer, greeting, "OVERLAY") end
end

local function ApplyScrollFrames(frame)
	local listScroll = _G.ClassTrainerListScrollFrame
	if listScroll and not listScroll.elvSized then
		S:StripTextures(listScroll, false)
		pcall(listScroll.SetWidth, listScroll, LIST_SCROLL.width)
		pcall(listScroll.ClearAllPoints, listScroll)
		pcall(listScroll.SetPoint, listScroll, "TOPLEFT", frame, "TOPLEFT", LIST_SCROLL.x, LIST_SCROLL.y)
		pcall(listScroll.SetPoint, listScroll, "BOTTOMLEFT", frame, "BOTTOMLEFT", LIST_SCROLL.x, LIST_SCROLL.bottom)
		listScroll.elvSized = true
	end

	local detailScroll = _G.ClassTrainerDetailScrollFrame
	if detailScroll and not detailScroll.elvSized then
		S:StripTextures(detailScroll, false)
		pcall(detailScroll.SetWidth, detailScroll, DETAIL_SCROLL.width)
		pcall(detailScroll.ClearAllPoints, detailScroll)
		pcall(detailScroll.SetPoint, detailScroll, "TOPRIGHT", frame, "TOPRIGHT", DETAIL_SCROLL.x, DETAIL_SCROLL.y)
		pcall(detailScroll.SetPoint, detailScroll, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", DETAIL_SCROLL.x, DETAIL_SCROLL.bottom)
		-- Keeps the scrollbar shown on short descriptions, as real ElvUI does.
		detailScroll.scrollBarHideable = nil
		detailScroll.elvSized = true
	end
	RestoreTrainerLayout()

	local detailChild = _G.ClassTrainerDetailScrollChildFrame
	if detailChild then
		pcall(detailChild.SetWidth, detailChild, DETAIL_CHILD_WIDTH)
		pcall(detailChild.SetHeight, detailChild, DETAIL_CHILD_HEIGHT)
	end

	local detailBar = _G.ClassTrainerDetailScrollFrameScrollBar
	if detailBar then
		S:HandleScrollBar(detailBar)
		pcall(detailBar.ClearAllPoints, detailBar)
		pcall(detailBar.SetPoint, detailBar, "TOPLEFT", detailScroll, "TOPRIGHT", 3, -16)
		pcall(detailBar.SetPoint, detailBar, "BOTTOMLEFT", detailScroll, "BOTTOMRIGHT", 3, 16)
	end
	local listBar = _G.ClassTrainerListScrollFrameScrollBar
	if listBar then S:HandleScrollBar(listBar) end
end

local function ApplyListRows(frame)
	S:StripTextures(_G.ClassTrainerExpandButtonFrame, false)
	local collapseAll = _G.ClassTrainerCollapseAllButton
	S:StylePlusMinusButton(collapseAll, true)
	if collapseAll then
		pcall(collapseAll.ClearAllPoints, collapseAll)
		pcall(collapseAll.SetPoint, collapseAll, "LEFT", frame, "TOPLEFT", COLLAPSE_ALL_X, COLLAPSE_ALL_Y)
	end

	local i
	for i = 1, TRAINER_ROW_COUNT do
		S:StylePlusMinusButton(_G["ClassTrainerSkill" .. i], true)
	end

	-- The selection highlight sits 3 units low against the row text (same row
	-- template as TradeSkill's, which inherits ClassTrainerSkillButtonTemplate).
	S:ShiftRegionInFrame(_G.ClassTrainerSkillHighlight, _G.ClassTrainerSkillHighlightFrame, 0, 3)

	local filter = _G.ClassTrainerFrameFilterDropDown
	if filter then
		S:StyleDropDownBox(filter)
		pcall(filter.ClearAllPoints, filter)
		pcall(filter.SetPoint, filter, "TOPRIGHT", frame, "TOPRIGHT", -55, -40)
	end
end

local function ApplyDetailPane(frame)
	local icon = _G.ClassTrainerSkillIcon
	if icon then
		HideSkillIconSlotArt(icon)
		pcall(icon.SetWidth, icon, 47)
		pcall(icon.SetHeight, icon, 47)
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", _G.ClassTrainerDetailScrollChildFrame, "TOPLEFT", 2, -1)
	end
	local skillName = _G.ClassTrainerSkillName
	if skillName then
		pcall(skillName.ClearAllPoints, skillName)
		pcall(skillName.SetPoint, skillName, "TOPLEFT", _G.ClassTrainerDetailScrollChildFrame, "TOPLEFT", 55, 0)
	end

	-- The button row sits at the bottom of the detail pane itself, not under
	-- the detail scroll frame, so it stays put whatever that frame's height.
	local cancel = _G.ClassTrainerCancelButton
	if cancel and frame.elvDetailPane then
		pcall(cancel.ClearAllPoints, cancel)
		pcall(cancel.SetPoint, cancel, "BOTTOMRIGHT", frame.elvDetailPane, "BOTTOMRIGHT", -BUTTON_INSET, BUTTON_INSET)
		S:StyleUIPanelButton(cancel)
	end
	local train = _G.ClassTrainerTrainButton
	if train and cancel then
		pcall(train.ClearAllPoints, train)
		pcall(train.SetPoint, train, "TOPRIGHT", cancel, "TOPLEFT", -3, 0)
		S:StyleUIPanelButton(train)
	end

	local money = _G.ClassTrainerMoneyFrame
	if money and frame.elvDetailPane then
		pcall(money.ClearAllPoints, money)
		pcall(money.SetPoint, money, "LEFT", frame.elvDetailPane, "BOTTOMLEFT", 6, 14)
	end

	local close = _G.ClassTrainerFrameCloseButton
	S:StyleCloseButton(close)
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end
end

local function ApplyTrainerChrome(frame)
	S:StripTextures(frame, true)
	S:Kill(_G.ClassTrainerFramePortrait)

	ApplyPanels(frame)
	ApplyHeaderText(frame)
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
	pcall(frame.DisableDrawLayer, frame, "BORDER")
	pcall(frame.DisableDrawLayer, frame, "ARTWORK")

	ApplyScrollFrames(frame)
	ApplyListRows(frame)
	ApplyDetailPane(frame)

	S:SkinChildren(frame)
end

local trainerSkinApplied = false
local function ApplyTrainerSkin()
	if trainerSkinApplied then return end
	local frame = _G.ClassTrainerFrame
	if not frame then return end
	trainerSkinApplied = true

	RestoreTrainerLayout()
	pcall(function()
		UIPanelWindows["ClassTrainerFrame"] = { area = "doublewide", pushable = 0, whileDead = 1 }
	end)

	pcall(frame.SetWidth, frame, FRAME_WIDTH)
	pcall(frame.SetHeight, frame, FRAME_HEIGHT)
	-- The native hit rect (right 34, bottom 75) is cut for the 384x512 art;
	-- after the resize it is re-cut to the panel.
	pcall(frame.SetHitRectInsets, frame, PANEL.left, -PANEL.right, -PANEL.top, PANEL.bottom)

	S:MakeDraggable(frame, _G.ClassTrainerFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	-- ClassTrainerFrame_Update addresses rows by name up to
	-- CLASS_TRAINER_SKILLS_DISPLAYED; the XML defines 11.
	local first = _G.ClassTrainerSkill1
	if first then
		pcall(first.ClearAllPoints, first)
		pcall(first.SetPoint, first, "TOPLEFT", frame, "TOPLEFT", 22, -80)
	end
	local i
	for i = 12, TRAINER_ROW_COUNT do
		if not _G["ClassTrainerSkill" .. i] then
			local okBtn, btn = pcall(CreateFrame, "Button", "ClassTrainerSkill" .. i, frame, "ClassTrainerSkillButtonTemplate")
			if okBtn and btn then
				pcall(btn.SetPoint, btn, "TOPLEFT", _G["ClassTrainerSkill" .. (i - 1)], "BOTTOMLEFT")
			end
		end
	end

	ApplyTrainerChrome(frame)

	-- The doublewide override means an open profession or auction window is
	-- no longer replaced by the panel manager: closed here instead.
	local ok = S:TryHookScript(frame, "OnShow", function()
		ApplyTrainerChrome(frame)
		S:CloseOtherDoublewidePanels(frame)
	end)
	if not ok then S:ReportSkinProblem() end

	local selectionOk = pcall(function() S:SecureHook("ClassTrainer_SetSelection", ApplySelectionChrome) end)
	if not selectionOk then S:ReportSkinProblem() end

	local rowsOk = pcall(function()
		S:SecureHook("ClassTrainer_SetToClassTrainer", RestoreTrainerLayout)
		S:SecureHook("ClassTrainer_SetToTradeSkillTrainer", RestoreTrainerLayout)
	end)
	if not rowsOk then S:ReportSkinProblem() end

	if not rowGlyphPollStarted then
		rowGlyphPollStarted = true
		E:ScheduleRepeatingTimer(PollRowGlyphs, 0.3)
	end
end

local function LoadSkin()
	S:WaitForGlobal("ClassTrainerFrame", ApplyTrainerSkin)
end

S:AddBlizzardSkin("trainer", LoadSkin)
