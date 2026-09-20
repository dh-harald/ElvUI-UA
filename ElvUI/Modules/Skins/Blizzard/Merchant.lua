-- Skins > Blizzard > Merchant -- reskins the native MerchantFrame (vendor
-- window) in place. Same recipe family as Gossip.lua/Quest.lua: strip the
-- native chrome, draw an elvBackground child frame (never SetBackdrop the
-- native frame itself), let the automatic sweep pick up whatever generic
-- control this server might add on top of vanilla.
--
-- Real 1.12.1 structure, per `FrameXML/MerchantFrame.xml`/`.lua`. Not yet
-- verified against the live client.
--
-- - **No text-colour problem here**, unlike the whole Quest/Gossip/
--   Greeting family: `MerchantNameText`/`MerchantPageText` inherit
--   `GameFontNormal` -- gold, `(1, 0.82, 0)`, byte-for-byte this project's
--   own `S.ACCENT_COLOR` -- and `MerchantRepairText`/every item's
--   `$parentName` inherit `GameFontHighlightSmall`/`GameFontNormalSmall`
--   (white/gold). `Fonts.xml`'s defaults here, not `QuestFont`'s black.
--   Nothing in this file recolours a single FontString, only chrome.
-- - `MerchantFrame` itself carries one portrait (`MerchantFramePortrait`)
--   plus four corner BORDER textures, four Buyback-tab-only ARTWORK
--   corner textures, and two OVERLAY bottom-border textures -- ALL direct
--   Texture regions of `MerchantFrame` itself (unlike the rest of this
--   window's family, where the portrait lives on the OUTER frame and only
--   a SUB-panel gets stripped, leaving the portrait needing its own
--   `S:Kill`), so ONE non-recursive strip of `MerchantFrame` clears most
--   of them, portrait included -- no separate kill needed for that one.
--   The bottom-border pair (OVERLAY) and the Buyback corner four
--   (ARTWORK) are exceptions, for the SAME reason: `MerchantFrame.lua`
--   explicitly re-`Show()`s both sets by global name on every merchant/
--   buyback update, and a per-object `Hide()` does not survive that. Each
--   set therefore needs a STANDING property the reassert cannot undo --
--   `SetAlpha(0)` for the OVERLAY pair (whose layer also carries this
--   file's own promoted panel text, so the layer itself must stay live),
--   `DisableDrawLayer("ARTWORK")` for the Buyback four (that layer holds
--   nothing else, native or ours). NEVER by zeroing a region's size:
--   `SetWidth(0)` clears the explicit dimension rather than setting it,
--   and these singly-anchored regions then fall back to the parent
--   frame's own size -- ordinary WoW sizing, and the actual origin of the
--   "2-2.5x the window's width" report.
-- - **Each of the 12 `MerchantItem<n>` slots (both tabs reuse the same 12
--   physical frames) splits cleanly by frame, unlike QuestFrame's item
--   buttons**: the decorative `$parentSlotTexture`/`$parentNameFrame` are
--   direct Texture regions of the CONTAINER (`MerchantItem<n>`), while the
--   functional icon lives on a separate CHILD FRAME
--   (`$parentItemButton`, `ItemButtonTemplate`) that a non-recursive strip
--   of the container never reaches. So the container gets a plain
--   `S:StripTextures(item, false)` (clears the two decorative pieces,
--   leaves the child untouched), and the item button gets
--   `Util.SkinItemButton` (`Core/Util.lua`) -- the exact same native slot
--   shape (`ItemButtonTemplate`'s `UI-Quickslot2` NormalTexture + icon)
--   the bag/bank grid already uses (`Modules/Bags/Bags.lua`), promoted to
--   `Util` once this became a second consumer -- see that function's own
--   header for why `Util` and not `Skins.lua` (load order:
--   `Load_Bags.xml` loads before `Load_Skins.xml`, `Util.lua` before
--   both). `MerchantBuyBackItem` is the same shape as one more slot and
--   gets identical treatment.
-- - Native quality/usability tinting (`SetItemButtonTextureVertexColor`/
--   `SetItemButtonNormalTextureVertexColor`, red when unaffordable/
--   unusable, grey when out of stock) still shows through the ICON half
--   of that pair -- `Util.SkinItemButton` never touches
--   `$parentIconTexture`, only blanks the NATIVE border art. The border
--   half of the tint is lost (same trade-off the bag grid itself already
--   ships with), not the signal itself.
-- - `MerchantFrameTab1`/`Tab2` inherit `CharacterFrameTabButtonTemplate`
--   -- the exact same tab family `S:StyleTab` already handles for
--   Character/Friends/SpellBook. Styled by name (a fixed vanilla pair,
--   never customised) rather than left to the sweep's structural
--   fingerprint, matching most other windows in this project.
-- - `MerchantPrevPageButton`/`NextPageButton` are the exact same
--   `UI-SpellbookIcon-{Prev,Next}Page-*` shape as `SpellBook.lua`'s own
--   page arrows and `ItemTextFrame`'s (not yet built) -- same
--   `S:StyleSquareIconButton(button, "LEFT"/"RIGHT", 0.5)` +
--   `S:KillButtonLabel` pair, second real consumer of both (see each
--   helper's own header in `Skins.lua`).
-- - `MerchantRepairAllButton`/`RepairItemButton` are a genuinely different
--   shape from every other icon button in this project: their
--   `NormalTexture` is `file=""` -- EMPTY, no native border art at all --
--   so there is nothing to strip. Their icon is a BORDER-layer region
--   holding one cell of the `UI-Merchant-RepairIcons` sprite sheet, and
--   that sprite has an ornate gold frame baked into its own pixels, so it
--   needs a crop, not just a reposition. Both are handled identically:
--   suppress the native BORDER layer, add `Util.CreateButtonBorder`, and
--   draw our own cropped texture on a child holder frame -- see
--   `StyleRepairButton` for why reaching the native region is not an
--   option on either button.
-- - No native function needs wrapping and no OnShow-driven text reassert
--   is needed (see the very first point) -- the ENTIRE chrome pass is
--   still re-run on every `MerchantFrame` OnShow anyway, matching this
--   project's standing convention, but every piece of it
--   (`S:CreatePanel`/`S:StripTextures`/`Util.SkinItemButton`/`Util.
--   CreateButtonBorder`) already idempotent-guards its own one-time work,
--   so the repeat runs cost a few checks, not a redo.
--
-- SCOPE: outer chrome, panel background, drag handle, close button, both
-- tabs, both page-nav buttons, both repair buttons, all 12 item slots plus
-- the buyback slot. Deliberately NOT done: mouse-wheel paging (real
-- ElvUI's own `Merchant.lua` adds this as a convenience feature, not a
-- skin fix -- functional addition, out of scope for a visual pass).

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Native `HitRectInsets` (right=35, bottom=61) already sit almost exactly
-- where the panel needs to end: bottom=61 is the boundary Blizzard's own
-- layout drew between the window's clickable content and the tab row
-- hanging below it (`MerchantFrameTab1` centers at y=46 from the true
-- bottom, native tab height leaves its own top edge around 61-62) -- same
-- "tabs hang below the panel" shape as Character/Friends/SpellBook, so the
-- panel must stop there, not cover the tabs. Left/top (10, -11) are real
-- ElvUI's own numbers for this window (`Blizzard/Merchant.lua`,
-- `source/ElvUI-vanilla`) -- pure padding choices, not measured
-- boundaries, safely clear of the portrait (7,-6) and the first item slot
-- (24,-80). No hit-rect fix needed, unlike QuestLogFrame: the discrepancy
-- between the native hit rect and this inset is only a few px on two
-- edges, not a wide dead zone.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -11, -35, 61

local ITEM_SLOT_COUNT = 12

-- FontStrings sitting DIRECTLY on `MerchantFrame`. `elvBackground` is a
-- child frame pinned to the frame's own base level, and at equal frame
-- levels draw order falls back to draw LAYER -- so the panel covers these
-- unless they are promoted. Same fix already proven on QuestLogFrame,
-- KeyBindingFrame and PetPaperDollFrame (`docs/skins/general.md` -> "A
-- base level csak a GYEREK FRAME-eket menti meg, a szülő SAJÁT régióit
-- nem").
local PANEL_TEXTS = {
	"MerchantNameText",
	"MerchantPageText",
	"MerchantRepairText",
}

local function PromotePanelText()
	local i
	for i = 1, table.getn(PANEL_TEXTS) do
		local fs = _G[PANEL_TEXTS[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end
end

local function StyleItemSlot(item, itemButton)
	if not item then return end
	S:StripTextures(item, false)

	-- `$parentName` is a direct region of THIS container, not of
	-- `MerchantFrame` -- confirmed live that it needed the exact same
	-- OVERLAY promotion as the frame-level texts above (icon and price,
	-- both on separate CHILD FRAMES of the container, were never
	-- affected; only the container's own direct region went dark).
	--
	-- Repositioned too, close to the icon instead of the wide native gap:
	-- native anchors both `$parentName` and `$parentMoneyFrame` relative
	-- to `$parentNameFrame` -- the decorative parchment strip this file
	-- kills above -- so once that strip vanished, the name/price kept
	-- their old native spacing (sized for a 128px-wide decorative label
	-- backdrop) with nothing left to visually justify the gap.
	--
	-- ⚠ Anchor BOTH by their LEFT point, never by TOPLEFT. `$parentName`'s
	-- native XML `<Size>` is 100x30 -- room for a wrapped 2-3 line name --
	-- and a FontString's default vertical justification is MIDDLE, so a
	-- short one-line name renders in the MIDDLE of that box, roughly 9px
	-- below wherever TOPLEFT was pinned. A TOPLEFT anchor therefore
	-- positions the BOX, not the glyphs, and any offset picked by looking
	-- at the rendered text is off by that dead space: measured live, a
	-- `TOPLEFT ... -2` name and a `TOPLEFT ... -16` price put the two text
	-- lines only ~8px apart, i.e. overlapping for a ~12px line height.
	-- Shrinking the name box to force a tight fit was rejected -- it would
	-- CLIP a genuinely long, wrapping name.
	--
	-- LEFT/LEFT sidesteps the box height entirely: with MIDDLE
	-- justification the anchor's own y IS the text's vertical centre, for
	-- the name box and for the 13px-tall `SmallMoneyFrameTemplate` alike.
	-- Placed symmetrically ±8 around the 37px icon's own vertical centre,
	-- which leaves ~4px of clear air between the two lines and keeps the
	-- price inside the field drawn below.
	local okName, itemName = pcall(item.GetName, item)
	if okName and itemName then
		local nameText = _G[itemName.."Name"]
		if nameText then
			pcall(nameText.SetDrawLayer, nameText, "OVERLAY")
			if itemButton then
				pcall(nameText.ClearAllPoints, nameText)
				pcall(nameText.SetPoint, nameText, "LEFT", itemButton, "RIGHT", 8, 8)
			end
		end

		local moneyFrame = _G[itemName.."MoneyFrame"]
		if moneyFrame and itemButton then
			pcall(moneyFrame.ClearAllPoints, moneyFrame)
			pcall(moneyFrame.SetPoint, moneyFrame, "LEFT", itemButton, "RIGHT", 8, -8)
		end
	end

	if itemButton and ElvUI.Util and ElvUI.Util.SkinItemButton then
		ElvUI.Util.SkinItemButton(itemButton)
	end

	-- One step lighter than the panel (`S.WIDGET_COLOR`, the same tone
	-- every skinned edit box/dropdown uses) under the name/price text,
	-- NOT under the icon -- user-requested design call after seeing it on
	-- `MerchantBuyBackItem` alone. First attempt covered the container's
	-- FULL 153x44 footprint, which is both wider AND taller than the
	-- 37x37 icon -- read as one oversized block with the icon awkwardly
	-- sitting in its top-left corner, not the intended "field beside the
	-- icon" look. Inset instead to start just past the icon (width 37 plus
	-- a 4px gap; the name/price text itself sits at x=8, so the field
	-- carries 4px of its own left padding under them by design)
	-- and to the icon's own height (37, not the container's 44 -- the
	-- container is taller than the icon by design, for native spacing
	-- between rows).
	S:CreateField(item, 41, 0, 0, 7)
end

-- `MerchantRepairAllButton` and `MerchantRepairItemButton` are structurally
-- IDENTICAL in the FrameXML: same 36x36 size, `NormalTexture file=""`
-- (empty, no native border art to strip), a `UI-Quickslot-Depress`
-- PushedTexture, a `ButtonHilight-Square` HighlightTexture, and exactly ONE
-- BORDER-layer `<Texture>` region holding the icon itself, cropped out of
-- the shared `UI-Merchant-RepairIcons` sprite sheet. The ONLY difference is
-- that RepairAll's icon carries a global name (`MerchantRepairAllIcon`) and
-- RepairItem's does not.
--
-- That single naming difference is why BOTH buttons are handled here by
-- suppressing the native icon layer wholesale and drawing our own texture
-- instead of trying to reach the native region: the unnamed one cannot be
-- resolved by name, and enumeration is not a usable substitute on this
-- client -- `GetRegions()` on a native Button was measured to return ZERO
-- regions (`docs/api-diffs/widgets-frames.md`), so any "walk the regions
-- and crop the one icon" approach silently finds nothing and leaves the
-- native icon rendering untouched, sprite-baked ornate frame and all.
-- `DisableDrawLayer` is the right tool for the suppression half: a standing
-- FRAME property, per-instance and immune to a native re-`Show()`, and the
-- icon is the only thing on either button's BORDER layer.
-- `Util.CreateButtonBorder`'s own surface is a child FRAME with a backdrop,
-- not a region of the button, so it is unaffected.
--
-- `HighlightTexture` AND `PushedTexture` are BOTH blanked here, unlike
-- `Util.CreateButtonBorder`'s other consumers that deliberately leave
-- native state textures alone -- confirmed live that
-- `MerchantRepairItemButton`'s `PushedTexture` (`UI-Quickslot-Depress`)
-- renders permanently, not just while actually pressed
-- (`GetPushedTexture():IsShown()` returned `true` at rest). Matches the
-- already-documented, general client fact
-- (`docs/api-diffs/widgets-frames.md` -> "`SetHighlightTexture` UA-n
-- FOLYAMATOSAN renderel"): highlight/pushed/checked state textures all
-- ignore their normal show-only-while-active gating on this client, so
-- any that would otherwise READ as a persistent extra border/tint have to
-- be blanked outright rather than left to native state gating.
--
-- The crops below are the native XML TexCoords (each a 0.28125 x 0.5625
-- cell: RepairItem = (0,0.28125, 0,0.5625), RepairAll = (0.28125,0.5625,
-- 0,0.5625)) pulled in by ~15% on every edge, to trim off the ornate
-- gold frame the sprite carries baked into its own pixels. Same ballpark
-- as real ElvUI's (0.04,0.24, 0.06,0.5) and pfUI's (.03,.25, .07,.50) for
-- the same two icons; the RepairAll crop is live-confirmed correct.
local REPAIR_ALL_TEXCOORDS = { 0.3235, 0.5203, 0.0844, 0.4781 }
local REPAIR_ITEM_TEXCOORDS = { 0.0422, 0.2391, 0.0844, 0.4781 }
local REPAIR_ICON_ASSET = "Interface\\MerchantFrame\\UI-Merchant-RepairIcons"

local function StyleRepairButton(button, texCoords)
	if not button then return end
	pcall(button.SetPushedTexture, button, "")
	pcall(button.SetHighlightTexture, button, "")
	pcall(button.DisableDrawLayer, button, "BORDER")
	if ElvUI.Util and ElvUI.Util.CreateButtonBorder then
		ElvUI.Util.CreateButtonBorder(button)
	end

	if button.elvIcon then return end
	local okLevel, level = pcall(button.GetFrameLevel, button)
	local buttonLevel = (okLevel and tonumber(level)) or 4
	local okHolder, holder = pcall(CreateFrame, "Frame", nil, button)
	if not okHolder or not holder then return end
	pcall(holder.SetPoint, holder, "TOPLEFT", button, "TOPLEFT", 1, -1)
	pcall(holder.SetPoint, holder, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	pcall(holder.EnableMouse, holder, false)
	pcall(holder.SetFrameLevel, holder, buttonLevel + 1)
	local okNewIcon, newIcon = pcall(holder.CreateTexture, holder, nil, "ARTWORK")
	if not okNewIcon or not newIcon then return end
	pcall(newIcon.SetAllPoints, newIcon, holder)
	pcall(newIcon.SetTexture, newIcon, REPAIR_ICON_ASSET)
	if texCoords then
		pcall(newIcon.SetTexCoord, newIcon, texCoords[1], texCoords[2], texCoords[3], texCoords[4])
	end
	button.elvIcon = newIcon
end

local function ApplyMerchantChrome(frame)
	S:StripTextures(frame, false)

	-- `MerchantFrameBottomLeftBorder`/`BottomRightBorder` (the ornate
	-- horizontal divider above the repair row) are direct OVERLAY-layer
	-- regions of `MerchantFrame`, so the strip above already reaches them
	-- once -- but confirmed STILL VISIBLE live afterwards, and confirmed
	-- back again after simply closing and reopening the window.
	-- `MerchantFrame_UpdateMerchantInfo` calls `:Show()` on both by global
	-- name on every merchant update, and `/run
	-- print(MerchantFrameBottomLeftBorder.Show == ElvUI[1].noop)` printed
	-- `false` right after a fresh open -- so the strip's `Show = E.noop`
	-- override is simply not in place on the object the native code
	-- reaches, whether because it never stuck or because something put a
	-- real function back. Either way a per-object override is the wrong
	-- tool here; what is needed is a STANDING property the reassert
	-- cannot touch.
	--
	-- NOT fixed with `DisableDrawLayer("OVERLAY")` -- tried live, and it
	-- took `PromotePanelText`'s own `MerchantNameText` down WITH it: that
	-- function promotes the frame's direct-region texts onto this SAME
	-- OVERLAY layer so they survive the panel underneath (see its own
	-- comment below), so disabling the whole layer un-does that override
	-- too.
	--
	-- NEVER fix this by zeroing the region's size. Both these regions (and
	-- the four Buyback ones below) declare an explicit `<Size>` plus a
	-- SINGLE anchor point in the XML, and `SetWidth(0)`/`SetHeight(0)`
	-- does not mean "shrink to nothing" -- it CLEARS the explicit
	-- dimension, after which an unsized, singly-anchored Texture falls
	-- back to its parent frame's own dimensions. Measured here as exactly
	-- 384x512 = `MerchantFrame`'s size; two such regions side by side is
	-- what once read as "2-2.5x wider than the window itself". This is
	-- ordinary WoW region sizing, not a client quirk.
	--
	-- `SetAlpha(0)` instead: alpha is a standing property that a native
	-- `:Show()` does not reset, so it survives the reassert without
	-- needing the whole OVERLAY layer (which also carries
	-- `PromotePanelText`'s promoted texts -- see below).
	local bl, br = _G.MerchantFrameBottomLeftBorder, _G.MerchantFrameBottomRightBorder
	if bl then pcall(bl.SetAlpha, bl, 0) end
	if br then pcall(br.SetAlpha, br, 0) end

	-- `BuybackFrameTopLeft`/`TopRight`/`BotLeft`/`BotRight` -- the mottled
	-- stone-look art `MerchantFrame_UpdateBuybackInfo` shows behind the
	-- Buyback tab's item grid -- are the ONLY things on `MerchantFrame`'s
	-- own ARTWORK layer (confirmed from `FrameXML/MerchantFrame.xml`), and
	-- nothing this file draws lives there: the panel, the drag handle and
	-- every button border are child FRAMES, and `PromotePanelText` targets
	-- OVERLAY. So the whole layer can go, which is the one mechanism the
	-- native `MerchantFrame_UpdateBuybackInfo:Show()` calls cannot undo --
	-- `DisableDrawLayer` is a standing frame property, not per-object
	-- state (same reasoning as `Modules/DataBars/ReputationBar.lua`).
	pcall(frame.DisableDrawLayer, frame, "ARTWORK")

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	PromotePanelText()

	local i
	for i = 1, ITEM_SLOT_COUNT do
		StyleItemSlot(_G["MerchantItem"..i], _G["MerchantItem"..i.."ItemButton"])
	end
	StyleItemSlot(_G.MerchantBuyBackItem, _G.MerchantBuyBackItemItemButton)

	StyleRepairButton(_G.MerchantRepairAllButton, REPAIR_ALL_TEXCOORDS)
	StyleRepairButton(_G.MerchantRepairItemButton, REPAIR_ITEM_TEXCOORDS)

	S:StyleTab(_G.MerchantFrameTab1)
	S:StyleTab(_G.MerchantFrameTab2)

	-- Unlike SpellBook's own page arrows, these two ALSO carry a plain
	-- BACKGROUND-layer `UI-Buttons-PageButton-Background` Texture (a
	-- direct region, not one of the four native texture SLOTS
	-- `S:StyleSquareIconButton` replaces) -- stripped first so the native
	-- square doesn't keep showing behind our own border.
	S:StripTextures(_G.MerchantPrevPageButton, false)
	S:StripTextures(_G.MerchantNextPageButton, false)
	S:StyleSquareIconButton(_G.MerchantPrevPageButton, "LEFT", 0.5)
	S:StyleSquareIconButton(_G.MerchantNextPageButton, "RIGHT", 0.5)
	S:KillButtonLabel(_G.MerchantPrevPageButton)
	S:KillButtonLabel(_G.MerchantNextPageButton)

	S:StyleCloseButton(_G.MerchantFrameCloseButton)
	-- Re-anchored to the PANEL, not left on the frame: the native anchor
	-- (`TOPRIGHT -30,-8`) sits further out than this panel's own corner
	-- (`PANEL_RIGHT,PANEL_TOP` = `-35,-11`), so the button floated in the
	-- margin outside the visible dark panel instead of sitting on its
	-- corner -- same fix as `QuestLogFrame`'s own close button.
	local close = _G.MerchantFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all -- picks up anything this server adds beyond vanilla
	-- (real addons on real vanilla have shipped a "Guild Bank Repair"
	-- button on this exact frame on other rule sets; not confirmed to
	-- exist here, hence no named handling for it, just this net).
	S:SkinChildren(frame)
end

local merchantSkinApplied = false
local function ApplyMerchantSkin()
	if merchantSkinApplied then return end
	local frame = _G.MerchantFrame
	if not frame then return end
	merchantSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere, same gap
	-- as every other window in this family.
	local handle = S:MakeDraggable(frame)
	if handle then
		pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT, 0)
	end
	pcall(frame.SetUserPlaced, frame, true)

	ApplyMerchantChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyMerchantChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyMerchantSkin()
end

S:AddBlizzardSkin("merchant", LoadSkin)
