-- Skins > Blizzard > AuctionHouse -- reskins the native auction window
-- (`AuctionFrame` + `AuctionDressUpFrame`) in place. The FIFTH LoadOnDemand
-- window (`Blizzard_AuctionUI`, after Macro/Binding/Talent/TradeSkill), so
-- `S:WaitForGlobal` owns the wait.
--
-- This window is deliberately the most SWEEP-DRIVEN skin in the project: the
-- named work below is only what the sweep provably cannot recognise, and
-- everything built from a stock template (panel buttons, checkboxes, edit
-- boxes, scrollbars, the rarity dropdown, the three tabs) is left to
-- `S:SkinChildren`. An auction addon's own TAB is a real `AuctionFrame` child
-- and is picked up by the same pass with no list to maintain here; its PANEL
-- usually is not (measured: one such addon parents its panel to `UIParent`),
-- and no foreign frame is named in this file.
--
-- Real 1.12.1 structure, per `AddOns/Blizzard_AuctionUI/*`:
--
-- - **832x447, natively `area = "doublewide"`** (`Blizzard_AuctionUI.lua`),
--   so it is the case `S:CloseOtherDoublewidePanels` was written for: a
--   doublewide panel does not replace another doublewide panel, it only
--   takes over the reference, leaving two stacked windows.
-- - All six window art pieces (`$parentTopLeft` .. `$parentBotRight`) are
--   ARTWORK regions of `AuctionFrame` itself and the portrait is its only
--   BACKGROUND one, so a NON-recursive strip plus disabling both layers
--   covers the whole outer frame. The recursion is deliberately not used:
--   it would walk into the four money-input frames and permanently hide the
--   coin textures `S:StyleMoneyInputFrame` puts back, on the second open.
-- - Three tab panels (`AuctionFrameBrowse`, `AuctionFrameBid`,
--   `AuctionFrameAuctions`) share the frame, each 758x447 pinned to its
--   TOPLEFT. Their labels are FontStrings on the PANEL ITSELF, so they are
--   promoted to OVERLAY before the column panes are drawn -- a pane sits at
--   its host's own frame level, where only the draw layer separates them.
-- - **Column panes come from real ElvUI's own numbers** for this window
--   (`bg1`/`bg2` per tab): they are already tuned to the native 832x447
--   layout, which is not resized here.
-- - `BrowseFilterScrollFrame`/`BrowseScrollFrame`/`BidScrollFrame`/
--   `AuctionsScrollFrame` are `FauxScrollFrameTemplate`s: their visible rows
--   are NOT their children but siblings on the tab panel, which is why the
--   panes are parented to the panel and never to a scroll frame.
-- - `AuctionSortButtonTemplate` (15 sort headers) is the Who-frame column
--   header shape, down to the same `WhoFrame-ColumnTabs` asset ->
--   `S:StyleColumnHeader`. It must be called by NAME, before the sweep: the
--   sweep's tab branch fingerprints on `_G[name.."Middle"]`, which these
--   headers also carry, and `S:StyleTab` would blank the button's
--   NormalTexture -- which here is the SORT ARROW, not decoration.
-- - `AuctionClassButtonTemplate` (15 filter rows) draws its hierarchy with a
--   `$parentNormalTexture` whose ALPHA native code sets per level (class 1.0,
--   subclass 0.4, invtype 0.0) plus a `$parentLines` indent glyph. Both are
--   killed; the text indent native code also applies (4/12/20px) carries the
--   hierarchy on its own, as it does in real ElvUI.
-- - Every list row's icon is a `$parentItem` child button whose icon region
--   is `$parentItemIconTexture` -- exactly `Util.SkinItemButton`'s shape.
--   The row itself is a plain Button whose "name plate" art is three
--   BACKGROUND textures.
-- - `AuctionsItemButton` (the sell slot) is a bare Button with no template:
--   native code puts the item icon straight into its NormalTexture, so that
--   region IS the content and must never be blanket-stripped --
--   `S:CreateIconEdges`, the same treatment the trade skill recipe icon gets.
-- - The six page buttons are 32x32 spellbook-style arrows ->
--   `S:StyleSquareIconButton` at the same 0.5 icon scale SpellBook uses.
--
-- Item QUALITY colouring is a poll, not a hook: real ElvUI drives it from
-- `hooksecurefunc(name, "SetVertexColor", ...)` per row, and neither bare
-- `hooksecurefunc` nor AceHook's object+method overload works on UA. The
-- poll reads `GetAuctionItemInfo`/`GetAuctionSellItemInfo` directly, which is
-- the same state native code reads, and needs nothing to fire.
--
-- Deliberately NOT done: the row highlight is left native, following the
-- Friends-row finding that touching a native list row's highlight is a real
-- regression risk. The filter list's highlight is a marker rather than
-- decoration too (`LockHighlight` shows the selected category), so it is
-- only TINTED, never replaced -- see `TintFilterHighlight`.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's own backdrop inset for this window.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -11, 0, 4

local FILTER_COUNT = 15

-- Gap between the max-level field and the rarity dropdown's box; see
-- `ApplyBrowseChrome` for why that anchor is ours and not the template's.
local DROPDOWN_GAP = 10

-- Icon crop shared by every icon this file re-frames, matching
-- `Util.SkinItemButton`.
local ICON_CROP = 0.08

-- FontStrings that belong to a TAB PANEL rather than to a child frame: they
-- have to leave BACKGROUND/ARTWORK for OVERLAY or the panel's own column
-- panes, which sit at the same frame level, draw over them.
local PANEL_TEXTS = {
	"BrowseTitle", "BrowseTabText", "BrowseNameText", "BrowseLevelText",
	"BrowseBidText", "BrowseIsUsableText", "BrowseShowOnCharacterText",
	"BrowseSearchCountText", "BrowseNoResultsText", "BrowseSearchDotsText",
	"BidTitle", "BidBidText", "BidSearchCountText",
	"AuctionsTitle", "AuctionsTabText", "AuctionsItemText", "AuctionsPriceText",
	"AuctionsDurationText", "AuctionsBuyoutText", "AuctionsBuyoutErrorText",
	"AuctionsDepositText", "AuctionsSearchCountText",
}

local SORT_BUTTONS = {
	"BrowseQualitySort", "BrowseLevelSort", "BrowseDurationSort",
	"BrowseHighBidderSort", "BrowseCurrentBidSort",
	"BidQualitySort", "BidLevelSort", "BidDurationSort", "BidBuyoutSort",
	"BidStatusSort", "BidBidSort",
	"AuctionsQualitySort", "AuctionsDurationSort", "AuctionsHighBidderSort",
	"AuctionsBidSort",
}

local SCROLL_FRAMES = {
	"BrowseFilterScrollFrame", "BrowseScrollFrame", "BidScrollFrame",
	"AuctionsScrollFrame",
}

local MONEY_FRAMES = { "BrowseBidPrice", "BidBidPrice", "StartPrice", "BuyoutPrice" }

local DURATION_RADIOS = {
	"AuctionsShortAuctionButton", "AuctionsMediumAuctionButton",
	"AuctionsLongAuctionButton",
}

-- A row's "Buyout"/"Your Bid" caption is a 10x11 Button whose FontString the
-- template anchors by its TOPRIGHT. On UA that lands the caption a few pixels
-- ABOVE the money digits it labels (on the legacy client it comes out
-- centred). Re-anchoring the FontString by its RIGHT edge centres it on the
-- button -- and therefore on the money frame the button is anchored to --
-- which is what the legacy client already shows, so both clients end up the
-- same without a per-client branch. The FontString is ANONYMOUS in all three
-- row templates, hence the region walk.
local ROW_CAPTIONS = { "YourBidText", "BuyoutText" }

-- The filter list's highlight is the SELECTED-category marker
-- (`AuctionFrameFilters_UpdateClasses` calls `LockHighlight()` on it), not
-- decoration, so it cannot simply be removed -- and it cannot be replaced
-- either: a flat-colour `SetHighlightTexture`, which is real ElvUI's own
-- `E:StyleButton` recipe, renders nothing at all on UA (measured). What does
-- apply on this client is `SetVertexColor` on the region already there.
--
-- That MULTIPLIES rather than replaces: the result is the native asset's own
-- blue-cyan gradient times this tint, never the tint itself. Tinting with the
-- accent gold therefore came out GREEN (gold's blue component is 0, which
-- zeroes the asset's strongest channel), so the tint is a plain dim grey
-- instead -- the same bar, quiet enough to read as a selection marker rather
-- than as the loud native blue. A hue of our own is not reachable this way at
-- all; only the region's replacement would give that, and that is the half
-- that does not work here.
--
-- What the dim tint ends up giving is the LEGACY look on both clients, and
-- that is the accepted result: the bar reads as almost nothing, and the
-- selection is marked by the TEXT instead, which the native highlight FONT
-- already does here (collapsed class rows gold `GameFontNormalSmall`, the
-- selected class white `GameFontHighlightSmall` via `LockHighlight`, its
-- subclasses white from the `HIGHLIGHT_FONT_COLOR_CODE` the native
-- `FilterButton_SetType` embeds).
--
-- A reading of `1 1 1` from `AuctionFilterButton1NormalText:GetTextColor()`
-- was briefly taken as proof that UA ignores that font state and paints every
-- label white. It does not: row 1 simply happened to be the SELECTED class,
-- which is white by definition. A state-dependent value has to be read off an
-- instance whose state is known.
--
-- A standing texture property, so it survives every Lock/UnlockHighlight the
-- native list update does.
local FILTER_HIGHLIGHT_TINT = 0.35

local function TintFilterHighlight(button)
	local ok, highlight = pcall(button.GetHighlightTexture, button)
	if not ok or not highlight then return end
	pcall(highlight.SetVertexColor, highlight,
		FILTER_HIGHLIGHT_TINT, FILTER_HIGHLIGHT_TINT, FILTER_HIGHLIGHT_TINT)
end

local function CenterRowCaption(button)
	if not button or button.elvCaptionCentered then return end
	local ok, regions = pcall(function() return { button:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "FontString" then
			pcall(region.ClearAllPoints, region)
			pcall(region.SetPoint, region, "RIGHT", button, "RIGHT", 0, 0)
			button.elvCaptionCentered = true
		end
	end
end

-- `iconName` is the crop from this project's own square-button sheet.
local PAGE_BUTTONS = {
	{ name = "BrowsePrevPageButton",   icon = "LEFT" },
	{ name = "BrowseNextPageButton",   icon = "RIGHT" },
	{ name = "BidPrevPageButton",      icon = "LEFT" },
	{ name = "BidNextPageButton",      icon = "RIGHT" },
	{ name = "AuctionsPrevPageButton", icon = "LEFT" },
	{ name = "AuctionsNextPageButton", icon = "RIGHT" },
}

-- One entry per list: the row prefix and count native code uses, the scroll
-- frame that supplies the offset, and the `GetAuctionItemInfo` list type.
-- The counts are vanilla's own `NUM_*_TO_DISPLAY` values, read from the live
-- globals where they exist so a server that changes them stays covered.
local LISTS = {
	{ prefix = "BrowseButton",   count = 8, global = "NUM_BROWSE_TO_DISPLAY",
	  host = "AuctionFrameBrowse",   scroll = "BrowseScrollFrame",   listType = "list" },
	{ prefix = "BidButton",      count = 9, global = "NUM_BIDS_TO_DISPLAY",
	  host = "AuctionFrameBid",      scroll = "BidScrollFrame",      listType = "bidder" },
	{ prefix = "AuctionsButton", count = 9, global = "NUM_AUCTIONS_TO_DISPLAY",
	  host = "AuctionFrameAuctions", scroll = "AuctionsScrollFrame", listType = "owner" },
}

local function RowCount(spec)
	return tonumber(_G[spec.global]) or spec.count
end

local function PromotePanelText()
	local i
	for i = 1, table.getn(PANEL_TEXTS) do
		local fs = _G[PANEL_TEXTS[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end
end

-- Column background. A separate host frame per column, because
-- `S:CreateSurface` keeps ONE surface per frame -- the same split real
-- ElvUI's own `bg1`/`bg2` uses, and the same shape `TradeSkillFrame`'s two
-- panes already have. The host sits at its parent's OWN frame level, which
-- puts it behind every child frame of that parent (the rows, the buttons,
-- the scroll bars) while still covering the window panel underneath.
local function EnsurePane(host, key, tlRef, tlPoint, tlX, tlY, brRef, brPoint, brX, brY)
	if not host or not tlRef or not brRef then return nil end
	if host[key] then return host[key] end

	local okPane, pane = pcall(CreateFrame, "Frame", nil, host)
	if not okPane or not pane then return nil end
	local okLevel, level = pcall(host.GetFrameLevel, host)
	pcall(pane.SetFrameLevel, pane, (okLevel and tonumber(level)) or 0)
	pcall(pane.SetPoint, pane, "TOPLEFT", tlRef, tlPoint, tlX, tlY)
	pcall(pane.SetPoint, pane, "BOTTOMRIGHT", brRef, brPoint, brX, brY)
	S:CreateSurface(pane, S.PANEL_COLOR)
	host[key] = pane
	return pane
end

-- Icon that lives in a button's own NormalTexture (the sell slot): cropped
-- and pulled 1px inside the button so the edge strips stay visible.
local function CropNormalTextureIcon(button)
	local okNormal, normalTexture = pcall(button.GetNormalTexture, button)
	if not (okNormal and normalTexture) then return end
	pcall(normalTexture.SetTexCoord, normalTexture, ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	pcall(normalTexture.ClearAllPoints, normalTexture)
	pcall(normalTexture.SetPoint, normalTexture, "TOPLEFT", button, "TOPLEFT", 1, -1)
	pcall(normalTexture.SetPoint, normalTexture, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
end

local function StyleListRows(spec)
	local host = _G[spec.host]
	if not host then return end
	local count = RowCount(spec)
	local i
	for i = 1, count do
		-- Only the three "name plate" textures have to go. The row's own
		-- BACKGROUND layer is NOT disabled: it also carries the row's
		-- name/level/bidder FontStrings. Those need no promotion either --
		-- a row is a child frame of the tab panel, so it sits a level ABOVE
		-- the column pane and draws over it whatever its layer. The row's
		-- HighlightTexture is a button texture slot rather than a region, so
		-- the native hover/selection feedback survives the strip.
		S:StripTextures(_G[spec.prefix..i], false)
		if ElvUI.Util and ElvUI.Util.SkinItemButton then
			ElvUI.Util.SkinItemButton(_G[spec.prefix..i.."Item"])
		end
		local j
		for j = 1, table.getn(ROW_CAPTIONS) do
			CenterRowCaption(_G[spec.prefix..i..ROW_CAPTIONS[j]])
		end
	end
end

-- Quality border of every visible row icon. Native code colours the row's
-- NAME by quality; the border here mirrors that, read from the same
-- `GetAuctionItemInfo` call native code makes, at the same index
-- (`FauxScrollFrame_GetOffset` + row).
local function ColorListQuality(spec)
	local host = _G[spec.host]
	if not host then return end
	local okShown, shown = pcall(host.IsVisible, host)
	if not (okShown and shown) then return end

	local okOffset, offset = pcall(FauxScrollFrame_GetOffset, _G[spec.scroll])
	offset = (okOffset and tonumber(offset)) or 0

	local count = RowCount(spec)
	local i
	for i = 1, count do
		local item = _G[spec.prefix..i.."Item"]
		if item and item.elvBackdrop then
			local r, g, b = 0, 0, 0
			local okInfo, itemName, _, _, quality = pcall(GetAuctionItemInfo, spec.listType, offset + i)
			if okInfo and itemName and quality then
				local okColor, cr, cg, cb = pcall(GetItemQualityColor, quality)
				if okColor and cr then r, g, b = cr, cg, cb end
			end
			pcall(item.elvBackdrop.SetBackdropBorderColor, item.elvBackdrop, r, g, b, 1)
		end
	end
end

-- The sell slot. Native code assigns its icon on `NEW_AUCTION_UPDATE` only,
-- so the crop has to be re-asserted after each assignment; polling it costs
-- one call and removes the need to observe that event at all.
local function ColorSellSlot()
	local button = _G.AuctionsItemButton
	if not (button and button.elvIconEdges) then return end

	local okInfo, itemName, _, _, quality = pcall(GetAuctionSellItemInfo)
	if okInfo and itemName then
		CropNormalTextureIcon(button)
		local okColor, r, g, b = false
		if quality then okColor, r, g, b = pcall(GetItemQualityColor, quality) end
		if okColor and r then
			S:SetIconEdgeColor(button, r, g, b)
		else
			S:SetIconEdgeColor(button)
		end
	else
		S:SetIconEdgeColor(button)
	end
end

local function PollAuctionQuality()
	local frame = _G.AuctionFrame
	if not frame then return end
	local okShown, shown = pcall(frame.IsVisible, frame)
	if not (okShown and shown) then return end

	local i
	for i = 1, table.getn(LISTS) do
		ColorListQuality(LISTS[i])
	end
	ColorSellSlot()
end

-- Browse tab: filter column on the left, results on the right.
local function ApplyBrowseChrome()
	local host = _G.AuctionFrameBrowse
	if not host then return end

	local filterPane = EnsurePane(host, "elvFilterPane",
		host, "TOPLEFT", 20, -103, host, "BOTTOMRIGHT", -575, 40)
	if filterPane then
		EnsurePane(host, "elvListPane",
			filterPane, "TOPRIGHT", 4, 0, _G.AuctionFrame, "BOTTOMRIGHT", -8, 40)
	end

	-- The rarity dropdown is natively anchored to the "Level Range" LABEL's
	-- BOTTOMRIGHT (`BrowseLevelText`), so where its box starts depends on how
	-- wide that string happens to render -- and at the widths this client
	-- produces the box lands ON TOP of the max-level edit box, hiding it
	-- completely (measured live on both clients). The native art got away
	-- with the same overlap because the template's 25px left cap is mostly
	-- transparent; an opaque surface does not.
	--
	-- Re-anchored to the FIELD instead of the label, which is locale-proof:
	-- the box starts a fixed gap right of it whatever the label's width.
	-- (Real ElvUI solves the same collision differently -- it moves the whole
	-- level-range group left and insets its own backdrop by 20px -- which
	-- this project's dropdown surface deliberately does not do, because that
	-- inset is measured wrong on UA where the art is displaced.)
	local dropDown, maxLevel = _G.BrowseDropDown, _G.BrowseMaxLevel
	if dropDown and maxLevel then
		pcall(dropDown.ClearAllPoints, dropDown)
		pcall(dropDown.SetPoint, dropDown, "LEFT", maxLevel, "RIGHT", DROPDOWN_GAP, 0)
	end

	local i
	for i = 1, FILTER_COUNT do
		local button = _G["AuctionFilterButton"..i]
		if button then
			-- `$parentLines` (the indent glyph) is a region; the level shading
			-- is the NormalTexture's alpha, which native code re-asserts on
			-- every list update -- so it needs `S:Kill`'s permanent hide, not
			-- a blank.
			S:StripTextures(button, false)
			S:Kill(_G["AuctionFilterButton"..i.."NormalTexture"])
			TintFilterHighlight(button)
		end
	end

	StyleListRows(LISTS[1])
end

local function ApplyBidChrome()
	local host = _G.AuctionFrameBid
	if not host then return end
	EnsurePane(host, "elvListPane",
		host, "TOPLEFT", 20, -72, _G.AuctionFrame, "BOTTOMRIGHT", -8, 40)
	StyleListRows(LISTS[2])
end

-- Auctions tab: the create-auction form on the left, own auctions on the
-- right.
local function ApplyAuctionsChrome()
	local host = _G.AuctionFrameAuctions
	if not host then return end

	local formPane = EnsurePane(host, "elvFormPane",
		host, "TOPLEFT", 15, -72, host, "BOTTOMRIGHT", -545, 40)
	if formPane then
		EnsurePane(host, "elvListPane",
			formPane, "TOPRIGHT", 3, 0, _G.AuctionFrame, "BOTTOMRIGHT", -8, 40)
	end

	local i
	for i = 1, table.getn(DURATION_RADIOS) do
		S:StyleRadioButton(_G[DURATION_RADIOS[i]])
	end

	-- The sell slot's NormalTexture IS the item icon, so it gets edge strips
	-- rather than a bordered surface, and is never stripped.
	local sellSlot = _G.AuctionsItemButton
	if sellSlot then
		S:CreateIconEdges(sellSlot)
		CropNormalTextureIcon(sellSlot)
		local sellName = _G.AuctionsItemButtonName
		if sellName then pcall(sellName.SetDrawLayer, sellName, "OVERLAY") end
	end

	StyleListRows(LISTS[3])
end

local function ApplyAuctionChrome(frame)
	PromotePanelText()
	S:StripTextures(frame, false)
	S:Kill(_G.AuctionPortraitTexture)
	-- Standing frame properties: BACKGROUND carries only the portrait and
	-- ARTWORK only the six window art pieces, and neither layer holds
	-- anything of this frame's own worth keeping.
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
	pcall(frame.DisableDrawLayer, frame, "ARTWORK")

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	local i
	for i = 1, table.getn(SCROLL_FRAMES) do
		S:StripTextures(_G[SCROLL_FRAMES[i]], false)
	end
	for i = 1, table.getn(SORT_BUTTONS) do
		S:StyleColumnHeader(_G[SORT_BUTTONS[i]])
	end
	for i = 1, table.getn(MONEY_FRAMES) do
		S:StyleMoneyInputFrame(_G[MONEY_FRAMES[i]])
	end
	for i = 1, table.getn(PAGE_BUTTONS) do
		S:StyleSquareIconButton(_G[PAGE_BUTTONS[i].name], PAGE_BUTTONS[i].icon, 0.5)
	end

	ApplyBrowseChrome()
	ApplyBidChrome()
	ApplyAuctionsChrome()

	S:StyleCloseButton(_G.AuctionFrameCloseButton)
	local close = _G.AuctionFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Everything else: the three tabs, ten panel buttons, two checkboxes,
	-- the rarity dropdown, three search edit boxes, four scroll bars -- plus
	-- whatever an auction addon has added to this frame.
	S:SkinChildren(frame)
end

-- Re-sweep after a tab switch: a widget created lazily on the click (a native
-- list row on first display, or anything an addon adds to its own auction tab)
-- does not exist yet when `AuctionFrame`'s OnShow ran, so it would otherwise
-- stay unskinned until the window is reopened. `AuctionFrameTab_OnClick` is a
-- bare global function -- the hook shape that works on this client -- and
-- addons that add an auction tab replace it, chaining to the previous one, so
-- this stays in the chain whichever order the two install in.
--
-- This reaches only what is a CHILD of `AuctionFrame`. A foreign auction
-- addon's panel typically is not: one measured here declares its own with
-- `parent="UIParent"` and never reparents it, so no sweep of this window can
-- see it, however the sweep is written -- while its TAB, a real child, is
-- picked up normally. Skinning such a panel would mean hardcoding another
-- addon's frame names here, which this file deliberately does not carry.
local function OnTabClick()
	local frame = _G.AuctionFrame
	if frame then S:SkinChildren(frame) end
end

-- Separate toplevel frame (parent `UIParent`), so it needs its own chrome
-- pass and its own sweep.
local function ApplyDressUpChrome()
	local frame = _G.AuctionDressUpFrame
	if not frame then return end

	-- Both the window art and the race/class backdrop `SetAuctionDressUpBackground`
	-- picks are direct regions of the frame; the model is a child, so it keeps
	-- drawing over the panel.
	S:StripTextures(frame, false)
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
	pcall(frame.DisableDrawLayer, frame, "ARTWORK")
	S:CreatePanel(frame)

	S:StyleModelRotateButtons(_G.AuctionDressUpModelRotateLeftButton,
		_G.AuctionDressUpModelRotateRightButton)

	-- The close button carries the frame's own corner ornament as a region of
	-- its own, which `S:StyleCloseButton` does not reach.
	S:StripTextures(_G.AuctionDressUpFrameCloseButton, false)
	S:StyleCloseButton(_G.AuctionDressUpFrameCloseButton)
	local close = _G.AuctionDressUpFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	S:SkinChildren(frame)
end

local auctionSkinApplied = false
local qualityPollStarted = false
local function ApplyAuctionSkin()
	if auctionSkinApplied then return end
	local frame = _G.AuctionFrame
	if not frame then return end
	auctionSkinApplied = true

	-- No `movable="true"` in the XML and no drag script -- `S:MakeDraggable`
	-- sets the flag itself. The close button is passed so the handle stops at
	-- its left edge instead of swallowing its clicks.
	S:MakeDraggable(frame, _G.AuctionFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyAuctionChrome(frame)
	ApplyDressUpChrome()

	if type(_G.AuctionFrameTab_OnClick) == "function" then
		local okHook = pcall(function() S:SecureHook("AuctionFrameTab_OnClick", OnTabClick) end)
		if not okHook then S:ReportSkinProblem() end
	end

	local ok = S:TryHookScript(frame, "OnShow", function()
		ApplyAuctionChrome(frame)
		-- This frame is natively doublewide, so an open trade skill or craft
		-- window would otherwise stay open underneath it.
		S:CloseOtherDoublewidePanels(frame)
	end)
	if not ok then S:ReportSkinProblem() end

	local dressUp = _G.AuctionDressUpFrame
	if dressUp then
		local okDressUp = S:TryHookScript(dressUp, "OnShow", ApplyDressUpChrome)
		if not okDressUp then S:ReportSkinProblem() end
	end

	if not qualityPollStarted then
		qualityPollStarted = true
		E:ScheduleRepeatingTimer(PollAuctionQuality, 0.3)
	end
end

local function LoadSkin()
	S:WaitForGlobal("AuctionFrame", ApplyAuctionSkin)
end

S:AddBlizzardSkin("auctionhouse", LoadSkin)
