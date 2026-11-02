local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- UnderCut (auction addon): its Sell and Search tabs in the look of the skinned
-- native tabs (Blizzard/AuctionHouse.lua), its native Auctions tab buttons, and
-- its price box under the GameTooltip.
--
-- The two tabs reuse the native window coordinates: Sell sits on the Auctions
-- art, Search on the Browse art, so both get the panes of their native
-- counterpart. A tab's content is built on its first activation; the wrapped
-- `OnShow` of the tab definition runs right after that build and before the
-- auction skin's own sweep, so it can style what that sweep would misread: the
-- column headers carry the tab fingerprint of `S:SkinChildren`.
--
-- UnderCut shows and hides its frames through a visibility tree (`ucKids`),
-- because on UA hiding a frame leaves its children on screen. The frames this
-- module and `S:SkinChildren` add are registered in that tree, or they would
-- stay behind when a tab closes. For the same reason they are built while the
-- list scroll frames are shown: a widget created under a hidden frame does not
-- draw on UA.
--
-- Contract with UnderCut: `UnderCut.UI`, `UnderCut.sellTab`/`searchTab`, the
-- Sell module's `item`, the UNDERCUT_SELL_CHANGED message and the frame names
-- used below. If one changes, the skin skips that part silently.

local SELL_HEADERS, SEARCH_HEADERS = 4, 6
local DURATIONS = 3
local ICON_CROP = 0.08

-- ElvUI frames that hang off a styled widget.
local SKIN_PARTS = {
	"elvBackground", "elvBackdrop", "elvCheckHolder", "elvCheckPatch",
	"elvTrackBG", "elvThumbBG", "elvIconHolder",
}

local SCROLL_FRAMES = {
	"UnderCutSellListScrollFrame", "UnderCutSearchListScrollFrame",
	"UnderCutSearchHistoryScrollFrame",
}

-- The native scrollbar groove UnderCut draws on the Slider itself, as two
-- unnamed regions.
local RAIL_ART = "ui-character-scrollbar"

-- The search row, on the numbers of the skinned Browse row
-- (Blizzard/AuctionHouse.lua): name field at the left edge of the filter pane,
-- every field 22 tall and centred on one line, labels 2 above the fields, the
-- search button in the top-right corner.
local NAME_X, NAME_Y, NAME_WIDTH = 20, -56, 152
local FIELD_GROW, LABEL_GAP = 3, 2
local MONEY_X, MONEY_Y = 192, -54
local MONEY_FIELD_GROW = 1
local MONEY_FIELD_RIGHT = -12
local PERCENT_X = 380
local SEARCH_BUTTON_X, SEARCH_BUTTON_Y = 25, -30

local MONEY_BOXES = { "Gold", "Silver", "Copper" }

-- The two price rows of the Sell form. The fields are 4 taller than the native
-- art's, so they get the spacing of the skinned Auctions tab: a label, 15 below
-- it the field, and 41 from row to row.
local PRICE_LABEL_X, PRICE_FIELD_X = 28, 31
local BID_LABEL_Y, BID_FIELD_Y = -274, -289
local BUYOUT_LABEL_Y, BUYOUT_FIELD_Y = -315, -330

local function Reanchor(region, point, relativeTo, relativePoint, x, y)
	if not region or not relativeTo then return end
	pcall(region.ClearAllPoints, region)
	pcall(region.SetPoint, region, point, relativeTo, relativePoint, x, y)
end

-- First region of this type, optionally with this exact text.
local function FindRegion(frame, regionType, text)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return nil end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, found = pcall(region.GetObjectType, region)
		if okType and found == regionType then
			if not text then return region end
			local okText, value = pcall(region.GetText, region)
			if okText and value == text then return region end
		end
	end
	return nil
end

local function AdoptSkinParts(node)
	local UI = _G.UnderCut.UI
	local i
	for i = 1, table.getn(SKIN_PARTS) do
		local part = node[SKIN_PARTS[i]]
		if part and not part.ucNode then UI:Adopt(node, part) end
	end
	local kids = node.ucKids
	if kids then
		for i = 1, table.getn(kids) do
			AdoptSkinParts(kids[i])
		end
	end
end

local function AddPane(panel, key, tlRef, tlPoint, tlX, tlY, brRef, brPoint, brX, brY)
	local pane = S:CreatePane(panel, key, tlRef, tlPoint, tlX, tlY, brRef, brPoint, brX, brY)
	if pane and not pane.ucNode then _G.UnderCut.UI:Adopt(panel, pane) end
	return pane
end

local function StyleHeaders(prefix, count)
	local i
	for i = 1, count do
		S:StyleColumnHeader(_G[prefix..i], true)
	end
end

local function HideRail(bar)
	if not bar then return end
	local ok, regions = pcall(function() return { bar:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		local okPath, path = pcall(regions[i].GetTexture, regions[i])
		if okPath and type(path) == "string"
			and string.find(string.lower(path), RAIL_ART, 1, true) then
			S:Kill(regions[i])
		end
	end
end

-- The sweep and everything it adds, for one tab panel.
local function FinishPanel(panel)
	local UI = _G.UnderCut.UI
	local wanted = {}
	local i
	for i = 1, table.getn(SCROLL_FRAMES) do
		local scroll = _G[SCROLL_FRAMES[i]]
		if scroll then
			wanted[i] = scroll.ucWanted ~= false
			UI:SetShown(scroll, true)
		end
	end

	S:SkinChildren(panel)

	for i = 1, table.getn(SCROLL_FRAMES) do
		HideRail(_G[SCROLL_FRAMES[i].."ScrollBar"])
	end
	AdoptSkinParts(panel)

	-- Pushes the wanted state down to the frames adopted above.
	for i = 1, table.getn(SCROLL_FRAMES) do
		local scroll = _G[SCROLL_FRAMES[i]]
		if scroll then UI:SetShown(scroll, wanted[i]) end
	end
end

local function SyncSellItem()
	local button = _G.UnderCutSellItemButton
	if not (button and button.elvSellIcon) then return end
	local item = _G.UnderCut:GetModule("Sell").item
	local r, g, b
	if item then
		pcall(button.elvSellIcon.Show, button.elvSellIcon)
		if item.quality then
			local ok, cr, cg, cb = pcall(GetItemQualityColor, item.quality)
			if ok and cr then r, g, b = cr, cg, cb end
		end
	else
		-- The bag-slot art UnderCut shows while empty: the native sell slot is
		-- an empty framed square here.
		pcall(button.elvSellIcon.Hide, button.elvSellIcon)
	end
	S:SetIconEdgeColor(button, r, g, b)
end

function S:OnUnderCutSellChanged()
	pcall(SyncSellItem)
end

-- The sell slot of the native tab: a cropped icon inside 1px edges. The icon is
-- an unnamed region, the only one the button has before the edges are added.
local function StyleSellItem()
	local button = _G.UnderCutSellItemButton
	if not button or button.elvSellIcon then return end
	local icon = FindRegion(button, "Texture")
	if not icon then return end
	pcall(icon.SetTexCoord, icon, ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	pcall(icon.ClearAllPoints, icon)
	pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
	pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	button.elvSellIcon = icon
	S:CreateIconEdges(button)
	SyncSellItem()
end

-- The labels are unnamed FontStrings of the panel, found by their text.
local function LayoutPriceRows(panel)
	local text = _G.UnderCut.L
	Reanchor(FindRegion(panel, "FontString", text["Bid / stack:"]),
		"TOPLEFT", panel, "TOPLEFT", PRICE_LABEL_X, BID_LABEL_Y)
	Reanchor(_G.UnderCutSellBid, "TOPLEFT", panel, "TOPLEFT", PRICE_FIELD_X, BID_FIELD_Y)
	Reanchor(FindRegion(panel, "FontString", text["Buyout / stack:"]),
		"TOPLEFT", panel, "TOPLEFT", PRICE_LABEL_X, BUYOUT_LABEL_Y)
	Reanchor(_G.UnderCutSellBuyout, "TOPLEFT", panel, "TOPLEFT", PRICE_FIELD_X, BUYOUT_FIELD_Y)
end

local function StyleSellTab(panel)
	local frame = _G.AuctionFrame
	local form = AddPane(panel, "elvFormPane",
		panel, "TOPLEFT", 15, -72, panel, "BOTTOMRIGHT", -545, 40)
	AddPane(panel, "elvListPane",
		form, "TOPRIGHT", 3, 0, frame, "BOTTOMRIGHT", -8, 40)

	StyleHeaders("UnderCutSellListHeader", SELL_HEADERS)
	S:StyleMoneyInputFrame(_G.UnderCutSellBid)
	S:StyleMoneyInputFrame(_G.UnderCutSellBuyout)
	LayoutPriceRows(panel)
	local i
	for i = 1, DURATIONS do
		S:StyleRadioButton(_G["UnderCutSellDuration"..i])
	end
	StyleSellItem()

	FinishPanel(panel)
end

local function GrowField(box)
	if not box then return end
	S:StyleEditBox(box)
	local field = box.elvBackground
	if not field then return end
	pcall(field.ClearAllPoints, field)
	pcall(field.SetPoint, field, "TOPLEFT", box, "TOPLEFT", 0, FIELD_GROW)
	pcall(field.SetPoint, field, "BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, -FIELD_GROW)
end

-- The money boxes are 20 tall against the 16 of the other two fields.
local function FitMoneyField(moneyName)
	S:StyleMoneyInputFrame(_G[moneyName])
	local i
	for i = 1, table.getn(MONEY_BOXES) do
		local box = _G[moneyName..MONEY_BOXES[i]]
		local field = box and box.elvBackground
		if field then
			pcall(field.ClearAllPoints, field)
			pcall(field.SetPoint, field, "TOPLEFT", box, "TOPLEFT", 0, MONEY_FIELD_GROW)
			pcall(field.SetPoint, field, "BOTTOMRIGHT", box, "BOTTOMRIGHT",
				MONEY_FIELD_RIGHT, -MONEY_FIELD_GROW)
		end
	end
end

-- The labels are unnamed FontStrings of the panel, found by their text.
local function LayoutSearchRow(panel)
	local text = _G.UnderCut.L
	local name, money, percent = _G.UnderCutSearchName, _G.UnderCutSearchMaxUnit, _G.UnderCutSearchMaxPercent

	Reanchor(name, "TOPLEFT", panel, "TOPLEFT", NAME_X, NAME_Y)
	if name then pcall(name.SetWidth, name, NAME_WIDTH) end
	Reanchor(money, "TOPLEFT", panel, "TOPLEFT", MONEY_X, MONEY_Y)
	Reanchor(percent, "TOPLEFT", panel, "TOPLEFT", PERCENT_X, NAME_Y)
	GrowField(name)
	GrowField(percent)
	FitMoneyField("UnderCutSearchMaxUnit")

	local nameLabel = FindRegion(panel, "FontString", text["Name"])
	Reanchor(nameLabel, "BOTTOMLEFT", name, "TOPLEFT", 0, FIELD_GROW + LABEL_GAP)
	Reanchor(FindRegion(panel, "FontString", text["Max unit price"]),
		"BOTTOMLEFT", nameLabel, "BOTTOMLEFT", MONEY_X - NAME_X, 0)
	Reanchor(FindRegion(panel, "FontString", text["Max % of value"]),
		"BOTTOMLEFT", nameLabel, "BOTTOMLEFT", PERCENT_X - NAME_X, 0)

	Reanchor(_G.UnderCutSearchButton, "TOPRIGHT", panel, "TOPRIGHT", SEARCH_BUTTON_X, SEARCH_BUTTON_Y)
end

local function StyleSearchTab(panel)
	local frame = _G.AuctionFrame
	local filter = AddPane(panel, "elvFilterPane",
		panel, "TOPLEFT", 20, -103, panel, "BOTTOMRIGHT", -575, 40)
	AddPane(panel, "elvListPane",
		filter, "TOPRIGHT", 4, 0, frame, "BOTTOMRIGHT", -8, 40)

	-- The lighter field UnderCut draws behind its history list: the filter
	-- pane does that here.
	S:Kill(_G.UnderCutSearchHistoryField)

	StyleHeaders("UnderCutSearchListHeader", SEARCH_HEADERS)
	LayoutSearchRow(panel)

	FinishPanel(panel)
end

-- The native Auctions tab's extra buttons. They live under a tree root of their
-- own, built on the first opening of the auction window, and are styled while
-- it is shown; the state is put back in the same tick.
local function StyleAuctionsBar()
	local UI = _G.UnderCut.UI
	local bar = _G.UnderCutAuctionsBar
	local wanted = bar.ucWanted ~= false
	UI:SetShown(bar, true)
	S:StyleUIPanelButton(_G.UnderCutCancelUndercutButton)
	S:StyleUIPanelButton(_G.UnderCutAuctionsScanButton)
	AdoptSkinParts(bar)
	UI:SetShown(bar, wanted)
end

-- The price box. On UA it comes with a frame of its own that UnderCut shows and
-- hides together with the box, which then carries the flat body; on the legacy
-- client it has none and gets the usual child.
local function StyleTooltip()
	S:AddSkinnedTooltip("UnderCutTooltip", _G.UnderCutTooltipBackdrop)
end

local function WrapTab(def, style)
	if not def then return end
	local onShow = def.OnShow
	local styled = false
	def.OnShow = function(panel)
		if onShow then onShow(panel) end
		if styled or not def.created then return end
		if pcall(style, panel) then
			styled = true
		else
			S:ReportSkinProblem()
		end
	end
end

local function LoadSkin()
	local addon = _G.UnderCut
	if type(addon) ~= "table" or not addon.UI then return end

	S:WaitForGlobal("UnderCutTooltip", StyleTooltip)

	local flags = E.private.skins.blizzard
	if not (flags.enable and flags.auctionhouse) then return end

	WrapTab(addon.sellTab, StyleSellTab)
	WrapTab(addon.searchTab, StyleSearchTab)
	S:RegisterMessage("UNDERCUT_SELL_CHANGED", "OnUnderCutSellChanged")
	S:WaitForGlobal("UnderCutAuctionsBar", StyleAuctionsBar)
end

S:AddAddOnSkin("UnderCut", LoadSkin)
