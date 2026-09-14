-- Skins > Blizzard > Trade -- reskins the native TradeFrame (player-to-player
-- trade window) in place. Same recipe family as Merchant.lua: strip the
-- native chrome, draw an elvBackground child frame (never SetBackdrop the
-- native frame itself), style the item slots, let the automatic sweep pick
-- up the rest.
--
-- Real 1.12.1 structure, per `FrameXML/TradeFrame.xml`/`.lua`:
--
-- - `TradeFrame` (384x512) carries two portraits (`TradeFramePlayerPortrait`,
--   `TradeFrameRecipientPortrait`) as the ONLY regions on its BACKGROUND
--   layer, four unnamed corner textures plus four FontStrings (both names,
--   both "Will not be traded" labels) on ARTWORK. The texts are promoted to
--   OVERLAY first, after which both layers hold nothing but chrome and are
--   disabled wholesale -- the standing frame property survives
--   `TradeFrame_Update`'s `SetPortraitTexture` on every trade update, which
--   a per-region strip does not reliably do.
-- - Each of the 14 slots (`TradePlayerItem1-7`, `TradeRecipientItem1-7`)
--   is the merchant slot shape: a 153x37 container whose decorative
--   `$parentSlotTexture`/`$parentNameFrame` AND the `$parentName` label are
--   BACKGROUND regions of the container, and slot 7 (the enchant slot) adds
--   an unnamed ARTWORK `UI-TradeFrame-EnchantIcon`. The icon is a separate
--   child `$parentItemButton` (`ItemButtonTemplate`) that
--   `Util.SkinItemButton` handles.
-- - The four `TradeHighlight*` frames are the "this side accepted" glow,
--   shown/hidden as whole frames by `TradeFrame_SetAcceptState`. Their three
--   BACKGROUND pieces are native gold art; they get their layer disabled and
--   one flat green texture of our own instead.
-- - `TradePlayerInputMoneyFrame` is a `MoneyInputFrameTemplate`: see
--   `StyleMoneyInputFrame` for why the shared edit-box recipe alone would
--   delete its coin icons.
--
-- Deliberately NOT done: real ElvUI's quality-coloured slot border and
-- name. It hooks `TradeFrame_UpdatePlayerItem`/`UpdateTargetItem`, and bare
-- global hooks are not available on UA; on top of that
-- `GetTradePlayerItemInfo` returns no quality on this API vintage (real
-- ElvUI-vanilla reads its `isUsable` return as quality).

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- Native `HitRectInsets` are right=35/bottom=72, which would leave the
-- Trade/Cancel row (bottom edge 55 above the frame's bottom) outside the
-- clickable window. Left/top are real ElvUI's (10, -11); right keeps the
-- same 16px margin past the recipient column (x 195-348) as the player
-- column has from the left edge; bottom leaves ~15px under the buttons.
-- The hit rect is set to the same insets so the whole visible panel accepts
-- item drops (`TradeFrame_OnMouseUp`) and clicks.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -11, -20, 40

local TRADE_SLOT_COUNT = 7

-- Width of the gap between the icon and the field drawn beside it, and
-- where the name starts inside that field. Same numbers as Merchant.lua.
local ICON_SIZE = 37
local FIELD_LEFT = ICON_SIZE + 4
local NAME_GAP = 8

local PANEL_TEXTS = {
	"TradeFramePlayerNameText",
	"TradeFrameRecipientNameText",
	"TradeFramePlayerEnchantText",
	"TradeFrameRecipientEnchantText",
}

local HIGHLIGHT_FRAMES = {
	"TradeHighlightPlayer",
	"TradeHighlightRecipient",
	"TradeHighlightPlayerEnchant",
	"TradeHighlightRecipientEnchant",
}

-- `UI-MoneyIcons` cells, per `FrameXML/MoneyInputFrame.xml`, with each
-- coin's native anchor offset from its own edit box's RIGHT edge.
local COINS = {
	{ suffix = "Gold",   left = 0,    right = 0.25, x = 2 },
	{ suffix = "Silver", left = 0.25, right = 0.5,  x = -8 },
	{ suffix = "Copper", left = 0.5,  right = 0.75, x = -8 },
}
local COIN_SIZE = 13
local COIN_ASSET = "Interface\\MoneyFrame\\UI-MoneyIcons"

local function PromotePanelText()
	local i
	for i = 1, table.getn(PANEL_TEXTS) do
		local fs = _G[PANEL_TEXTS[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end
end

-- Both names sit right of a portrait that no longer exists (x=75 / x=245).
-- Moved to the left edge of their own item column, left-justified, and
-- widened to the column so a long name is not truncated by the native
-- 80/100px box.
local function PlaceNameText(fs, x)
	if not fs then return end
	pcall(fs.ClearAllPoints, fs)
	pcall(fs.SetPoint, fs, "TOPLEFT", _G.TradeFrame, "TOPLEFT", x, -17)
	pcall(fs.SetWidth, fs, 150)
	pcall(fs.SetJustifyH, fs, "LEFT")
end

local function StyleTradeSlot(item)
	if not item then return end
	local okName, itemName = pcall(item.GetName, item)
	if not okName or not itemName then return end
	local itemButton = _G[itemName.."ItemButton"]

	-- The label is a BACKGROUND region of the container, so it has to leave
	-- that layer before the layer is disabled; OVERLAY also keeps it above
	-- the field surface, which sits at the container's own frame level.
	-- Anchored by LEFT so the 90x30 box's MIDDLE justification centres the
	-- text on the icon (see Merchant.lua `StyleItemSlot` for the TOPLEFT
	-- pitfall).
	local nameText = _G[itemName.."Name"]
	if nameText then
		pcall(nameText.SetDrawLayer, nameText, "OVERLAY")
		if itemButton then
			pcall(nameText.ClearAllPoints, nameText)
			pcall(nameText.SetPoint, nameText, "LEFT", itemButton, "RIGHT", NAME_GAP, 0)
		end
	end

	S:StripTextures(item, false)
	pcall(item.DisableDrawLayer, item, "BACKGROUND")
	pcall(item.DisableDrawLayer, item, "ARTWORK")

	if itemButton and ElvUI.Util and ElvUI.Util.SkinItemButton then
		ElvUI.Util.SkinItemButton(itemButton)
	end

	-- Container is exactly icon-tall (37), so the field needs no bottom inset.
	S:CreateField(item, FIELD_LEFT, 0, 0, 0)
end

-- The accept glow. Raised one level above the slot containers so the tint
-- lies over the fields beside the icons (which sit at the container's own
-- level) but under the item buttons (`ItemButtonTemplate` OnLoad adds +2).
-- Flat green at 20% -- real ElvUI's colour for the same four frames.
local function StyleHighlight(frame, level)
	if not frame then return end
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
	if level then pcall(frame.SetFrameLevel, frame, level) end
	if frame.elvGlow then return end
	local okTex, tex = pcall(frame.CreateTexture, frame, nil, "ARTWORK")
	if not okTex or not tex then return end
	pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8x8")
	pcall(tex.SetVertexColor, tex, 0, 1, 0, 0.2)
	pcall(tex.SetAllPoints, tex, frame)
	frame.elvGlow = tex
end

-- `MoneyInputFrameTemplate`'s three edit boxes carry their coin icon as an
-- UNNAMED BACKGROUND region, the same layer as the input-border art.
-- `S:StyleEditBox` disables that whole layer (the only durable way to clear
-- the border), which takes the coins with it -- and `S:SkinChildren` applies
-- that recipe to every EditBox it finds anyway. So the boxes get the
-- standard recipe, and each one gets a fresh coin texture on ARTWORK at the
-- native size, crop and anchor.
local function StyleMoneyInputFrame(moneyFrame)
	if not moneyFrame then return end
	local okName, name = pcall(moneyFrame.GetName, moneyFrame)
	if not okName or not name then return end
	local i
	for i = 1, table.getn(COINS) do
		local coin = COINS[i]
		local box = _G[name..coin.suffix]
		if box then
			S:StyleEditBox(box)
			if not box.elvCoin then
				local okTex, tex = pcall(box.CreateTexture, box, nil, "ARTWORK")
				if okTex and tex then
					pcall(tex.SetTexture, tex, COIN_ASSET)
					pcall(tex.SetTexCoord, tex, coin.left, coin.right, 0, 1)
					pcall(tex.SetWidth, tex, COIN_SIZE)
					pcall(tex.SetHeight, tex, COIN_SIZE)
					pcall(tex.SetPoint, tex, "LEFT", box, "RIGHT", coin.x, 0)
					box.elvCoin = tex
				end
			end
		end
	end
end

local function ApplyTradeChrome(frame)
	PromotePanelText()
	S:StripTextures(frame, false)
	S:Kill(_G.TradeFramePlayerPortrait)
	S:Kill(_G.TradeFrameRecipientPortrait)
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
	pcall(frame.DisableDrawLayer, frame, "ARTWORK")

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	pcall(frame.SetHitRectInsets, frame, PANEL_LEFT, -PANEL_RIGHT, -PANEL_TOP, PANEL_BOTTOM)

	PlaceNameText(_G.TradeFramePlayerNameText, 26)
	PlaceNameText(_G.TradeFrameRecipientNameText, 195)

	local i
	for i = 1, TRADE_SLOT_COUNT do
		StyleTradeSlot(_G["TradePlayerItem"..i])
		StyleTradeSlot(_G["TradeRecipientItem"..i])
	end

	local glowLevel
	local firstSlot = _G.TradePlayerItem1
	if firstSlot then
		local okLevel, level = pcall(firstSlot.GetFrameLevel, firstSlot)
		if okLevel and tonumber(level) then glowLevel = tonumber(level) + 1 end
	end
	for i = 1, table.getn(HIGHLIGHT_FRAMES) do
		StyleHighlight(_G[HIGHLIGHT_FRAMES[i]], glowLevel)
	end

	StyleMoneyInputFrame(_G.TradePlayerInputMoneyFrame)

	S:StyleUIPanelButton(_G.TradeFrameTradeButton)
	S:StyleUIPanelButton(_G.TradeFrameCancelButton)

	S:StyleCloseButton(_G.TradeFrameCloseButton)
	-- The native anchor (TOPRIGHT -25,-8) lies outside this panel's corner.
	local close = _G.TradeFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	S:SkinChildren(frame)
end

local tradeSkinApplied = false
local function ApplyTradeSkin()
	if tradeSkinApplied then return end
	local frame = _G.TradeFrame
	if not frame then return end
	tradeSkinApplied = true

	-- `movable="true"` in the XML but no drag script. The handle stops at
	-- the close button so it never swallows its clicks.
	S:MakeDraggable(frame, _G.TradeFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyTradeChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyTradeChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyTradeSkin()
end

S:AddBlizzardSkin("trade", LoadSkin)
