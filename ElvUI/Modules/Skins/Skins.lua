-- Skins module -- shared scaffolding for reskinning native Blizzard
-- windows in place. Mirrors real ElvUI's own file LAYOUT (a shared
-- "Skins" module, one file per Blizzard window under Skins/Blizzard/,
-- source/ElvUI-vanilla/ElvUI/Modules/Skins/{Skins,Blizzard/*}.lua) -- but
-- NOT its actual generic API (E:StripTextures/E:CreateBackdrop/
-- E:StyleButton/S:HandleButton/S:HandleTab/S:HandleCheckBox/
-- ... dozens of functions that don't exist here). Only the couple of helpers actually shared by
-- more than one skin file live here; each skin file is otherwise
-- self-contained, built from primitives already proven elsewhere in this
-- project (ElvUI.Util.CreateButtonBorder, the SetBackdrop bgFile+edgeFile+
-- edgeSize=1 pattern, Chat.lua's own Kill()/tab-recolor recipe).

local E, L, V, P, G = unpack(ElvUI)
-- AceHook-3.0 -- a skin file's own OnShow re-apply hook (see Blizzard/
-- Character.lua's own note on why one is needed) must go through
-- :HookScript, not a bare HookScript call -- no reliably-present bare
-- global HookScript exists on this client, so this routes through
-- AceHook-3.0's :HookScript instead, established project-wide.
-- AceEvent-3.0 is for `S:WaitForGlobal`'s own ADDON_LOADED registration
-- (LoadOnDemand windows -- see that function). Payloads are deliberately
-- never read from it; this project's copy doesn't forward them.
local S = E:NewModule("Skins", "AceHook-3.0", "AceEvent-3.0")
E.Skins = S

-- Settings: `V.skins.blizzard.*` (Settings/Private.lua) -- a master enable
-- plus one flag per skinned window, matching real ElvUI's own
-- `E.private.skins.blizzard` layout.

-- ===================================================================
-- `S:StylePlusMinusButton` / `S:SetGlyphExpanded` -- collapse glyphs
-- ===================================================================
-- The expand/collapse control every native list header uses: Reputation
-- categories, Skill type labels, and the Quest Log's own header rows and
-- its "All" button all inherit the same 16x16 native icon anchored at the
-- button's LEFT edge with a 3px offset -- identical geometry in all three
-- FrameXMLs, which is why one recipe covers them.
--
-- The native icon is Hide()+noop'd rather than SetTexture(nil)'d: the round
-- red native +/- can stay fully visible next to a replacement even after
-- its path has been cleared. And the replacement is a brand-NEW Texture on
-- a NEW child frame, not the native slot re-pointed -- modifying an
-- existing native region is the unreliable half of this client's behaviour,
-- creating new objects is the reliable half.
--
-- The child frame matters for a second reason: these buttons are the FULL
-- WIDE ROW (302x13 for Reputation, 300x16 for a Quest Log row), so
-- bordering the button itself produces a border the width of the row rather
-- than an icon.
S.PLUS_MINUS_TEXTURE = "Interface\\AddOns\\ElvUI\\Media\\Textures\\PlusMinusButton"

-- `keepTextColor` is for rows whose label colour carries INFORMATION the
-- native code owns and re-asserts -- Quest Log rows are coloured by quest
-- difficulty. Reputation/Skill headers have no such meaning and take the
-- accent, which is also what makes Skill's own plain-white label match
-- Reputation's already-yellow one.
-- `refresh` is optional and, when given, is installed as an OnClick
-- post-hook on the button. It belongs HERE rather than at each call site:
-- a replacement glyph driven only by a timer visibly settles after the list
-- has already expanded, and every window that styles one of these needs the
-- same treatment -- so a caller should not be able to forget it, and adding
-- a button somewhere should not mean remembering to hook it separately.
-- By the time a post-hook runs the native handler has already toggled
-- whatever state the refresh reads.
function S:StylePlusMinusButton(button, keepTextColor, refresh)
	if button and refresh and not button.elvGlyphClickHooked then
		if S:TryHookScript(button, "OnClick", refresh) then
			button.elvGlyphClickHooked = true
		end
	end

	if not button or button.elvGlyph then return end

	local okNormal, normalTexture = pcall(button.GetNormalTexture, button)
	pcall(button.SetNormalTexture, button, "")
	if okNormal and normalTexture then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		pcall(normalTexture.Hide, normalTexture)
		normalTexture.Show = E.noop
	end
	-- Hiding the region is not enough where native code RE-ASSIGNS the
	-- glyph art on every list refresh (`TradeSkillFrame_Update` does, on
	-- all 25 rows plus the collapse-all button): a fresh
	-- `SetNormalTexture(path)` puts the native plus/minus back beside our
	-- own replacement. The setter is noop'd the way real ElvUI's own
	-- version of this recipe does it. Safe for every consumer here because
	-- none of them read the state back off the texture any more -- they all
	-- ask the API (`GetQuestLogTitle`, `GetTradeSkillInfo`) or a native
	-- state field (`.isCollapsed`/`.isExpanded`).
	button.SetNormalTexture = E.noop
	local okHighlight, highlight = pcall(button.GetHighlightTexture, button)
	if okHighlight and highlight then
		pcall(highlight.SetTexture, highlight, nil)
		pcall(highlight.Hide, highlight)
		highlight.Show = E.noop
		highlight.SetTexture = E.noop
	end

	local holder = CreateFrame("Frame", nil, button)
	holder:SetWidth(16)
	holder:SetHeight(16)
	pcall(holder.SetPoint, holder, "LEFT", button, "LEFT", 3, 0)
	ElvUI.Util.CreateButtonBorder(holder)
	button.elvGlyphHolder = holder

	local icon = holder:CreateTexture(nil, "ARTWORK")
	pcall(icon.SetTexture, icon, S.PLUS_MINUS_TEXTURE)
	pcall(icon.SetPoint, icon, "TOPLEFT", holder, "TOPLEFT", 2, -2)
	pcall(icon.SetPoint, icon, "BOTTOMRIGHT", holder, "BOTTOMRIGHT", -2, 2)
	button.elvGlyph = icon

	if keepTextColor then return end

	-- `button:GetFontString()` rather than a guessed global name: it works
	-- whether or not the underlying region has an explicit XML name.
	local okText, text = pcall(button.GetFontString, button)
	if okText and text then
		pcall(text.SetTextColor, text, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	end
end

-- Whether this row shows a glyph AT ALL, border included. Separate from
-- the expanded/collapsed state below, and deliberately so: the Quest Log
-- uses one row template for both category headers and plain quest rows and
-- switches between them by blanking the icon, so it needs to hide the whole
-- glyph -- but "collapsed" arrives as a plain `nil` from Blizzard's own
-- state fields (`SkillTypeLabel<i>.isExpanded` is nil, not false, for a
-- collapsed category), so `nil` cannot also mean "no glyph". Overloading
-- the two cost the Skill tab its plus sign while leaving the click target
-- in place.
function S:SetGlyphShown(button, shown)
	if not button then return end
	local holder = button.elvGlyphHolder
	if not holder then return end

	if shown then
		pcall(holder.Show, holder)
	else
		pcall(holder.Hide, holder)
	end
end

-- Minus (expanded) and Plus (collapsed) are two crops of the SAME sprite
-- sheet; TexCoords ported verbatim from real ElvUI. Any falsy `expanded`
-- (`false` OR `nil`) means collapsed.
function S:SetGlyphExpanded(button, expanded)
	if not button or not button.elvGlyph then return end

	if expanded then
		pcall(button.elvGlyph.SetTexCoord, button.elvGlyph, 0.545, 0.975, 0.085, 0.925)
	else
		pcall(button.elvGlyph.SetTexCoord, button.elvGlyph, 0.045, 0.475, 0.085, 0.925)
	end
end

-- Permanently hides a decorative native region/frame -- Hide() alone
-- isn't durable against native code re-Show()ing it later (established
-- project-wide, e.g. Chat.lua's own identical Kill()), so Show is also
-- permanently noop'd.
function S:Kill(frame)
	if not frame then return end
	pcall(frame.Hide, frame)
	frame.Show = E.noop
end

-- Generic name-list recolour -- reapplies one colour to a fixed set of
-- global FontStrings by name. Hoisted from QuestLog.lua once Quest.lua
-- became a second consumer of the exact same helper: both windows recolour
-- native FontStrings whose font OBJECT is black/near-black by default and
-- whose only working lever is per-instance `SetTextColor` (font objects
-- have no `SetTextColor` method at all on this client -- see QuestLog.lua's
-- own header for the confirmed dead end).
function S:RecolorNames(names, r, g, b)
	local i
	for i = 1, table.getn(names) do
		local fs = _G[names[i]]
		if fs then pcall(fs.SetTextColor, fs, r, g, b) end
	end
end

-- Shared gold accent -- tabs, close-button labels, and generic
-- UIPanelButtonTemplate text across every skin file use this same color,
-- matching real ElvUI's own look. Was a Blizzard/Character.lua-local
-- constant; promoted here alongside the 3 helpers below once Friends.lua
-- became a second consumer.
S.ACCENT_COLOR = S.ACCENT_COLOR or { 1, 0.82, 0 }
-- Plain grey for a DISABLED tab's text -- see `S:StyleTab`'s own note
-- below on why this exists: some tabs (FriendsFrameTab3
-- "Guild") are natively `:Disable()`'d based on real game state (not in a
-- guild) and need to keep looking disabled, not always gold.
S.ACCENT_COLOR_DISABLED = S.ACCENT_COLOR_DISABLED or { 0.5, 0.5, 0.5 }
-- Tab fill -- deliberately LIGHTER than the panel a tab sits on, so the
-- tab strip reads as a separate row of controls instead of melting into
-- the window.
--
-- Why 0.2 and not the 0.1 every other button uses: `CreateButtonBorder`
-- fills with a GLOSS texture, and the gloss halves the colour that
-- reaches the screen. Measured off the live screenshot -- the 0.1
-- `BACKDROP_COLOR` came out as #0D0D0D (0.051), right next to the panel's
-- own #0D0C0B. 0.2 therefore lands at roughly 0.1 on screen, i.e. twice
-- the panel, which is the contrast this was supposed to have all along.
S.TAB_COLOR = S.TAB_COLOR or { 0.2, 0.2, 0.2, 1 }

-- ===================================================================
-- DESIGN TOKENS -- the ONE place every skinned surface's color lives
-- ===================================================================
-- Every skin file used to re-declare the SAME literal
-- `0.05, 0.05, 0.05, 0.95` backdrop table inline (8 copies across 5
-- files) and every edit box got its own bespoke treatment, so a single
-- design change meant editing every window. Nothing below changes the
-- panel look -- the values ARE the ones already in use everywhere; they
-- just have one home now.
--
-- The two-tone split is real ElvUI's own, not invented here:
--   * PANEL  -- `E:CreateBackdrop(f, "Transparent")` -> `backdropfadecolor`
--     `{.06,.06,.06,.8}` (source/ElvUI-vanilla/ElvUI/Core/Media.lua) for
--     WINDOWS. This project's own already-tuned equivalent is .05/.95.
--   * WIDGET -- `E:CreateBackdrop(f, "Default")` -> `backdropcolor`
--     `{.1,.1,.1,1}` for the CONTROLS that sit ON a window (edit boxes,
--     dropdown boxes, buttons). `S:HandleEditBox`
--     (source/ElvUI-vanilla/ElvUI/Modules/Skins/Skins.lua:258-274) is
--     literally just `E:CreateBackdrop(frame, "Default")`.
-- So in real ElvUI an edit box is ALREADY exactly one step lighter than
-- the window it sits on (26/255 vs 15/255), and byte-identical to a
-- button's fill. `WIDGET_COLOR`
-- is deliberately the same {.1,.1,.1} `Core/Util.lua`'s own
-- `BACKDROP_COLOR` already feeds `Util.CreateButtonBorder`, so a button
-- and an edit box cannot drift apart.
S.PANEL_COLOR = S.PANEL_COLOR or { 0.05, 0.05, 0.05, 0.95 }
-- Pointed straight at `Core/Util.lua`'s own tables (the ones
-- `Util.CreateButtonBorder` already feeds every skinned BUTTON), not a
-- copy of the numbers -- a copy is exactly how a unified design decays
-- back into per-file drift. Falls back to a literal only if this
-- somehow loads before Core/Util.lua.
S.WIDGET_COLOR = S.WIDGET_COLOR or (ElvUI.Util and ElvUI.Util.BACKDROP_COLOR) or { 0.1, 0.1, 0.1, 1 }
S.BORDER_COLOR = S.BORDER_COLOR or (ElvUI.Util and ElvUI.Util.BORDER_COLOR) or { 0, 0, 0, 1 }
-- Recessed surfaces that must read as a HOLE, not a control: scrollbar
-- tracks, the closed-state dropdown box. Kept at its existing value.
S.TRACK_COLOR = S.TRACK_COLOR or { 0, 0, 0, 0.4 }
-- The same recessed tone, but OPAQUE -- for a track that has to HIDE
-- something rather than just sit on the panel. Only the horizontal option
-- slider needs it so far: `DisableDrawLayer` clears every other native
-- `<Backdrop>` on UA but demonstrably NOT a Slider's: that rounded metal
-- center can come back on a slider even after DisableDrawLayer, and
-- the transparent `TRACK_COLOR` lets that rounded metal read straight
-- through. See `S:StyleOptionsSlider`.
S.TRACK_COLOR_OPAQUE = S.TRACK_COLOR_OPAQUE or { 0.03, 0.03, 0.03, 1 }
-- The only deliberately LIGHT surface: a scrollbar thumb has to read as
-- the one grabbable thing on a dark track. Kept at its existing value.
S.THUMB_COLOR = S.THUMB_COLOR or { 0.6, 0.6, 0.6, 1 }
-- A GROUPING sub-panel inside a window (Sound Options' own "Voice Chat
-- Settings" box, live name `OptionsVoiceChat`) -- a slightly lighter
-- background for a box whose native light-grey background was removed.
--
-- Deliberately BETWEEN `PANEL_COLOR` (.05) and `WIDGET_COLOR` (.1) rather
-- than reusing either: a group box painted at the widget tone would be
-- byte-identical to the fill of every button and edit box sitting ON it
-- (the "Test Microphone" button lives inside this very box), so those
-- controls would dissolve into their own background. This is the only
-- value in this block that isn't lifted from real ElvUI -- real ElvUI has
-- no third tone because it has no grouped sub-panel of this shape here.
S.GROUP_COLOR = S.GROUP_COLOR or { 0.075, 0.075, 0.075, 1 }

-- The shared backdrop TABLE for every flat surface in this module, so it
-- belongs with the colors, not with one consumer. Deliberately only
-- `{bgFile, edgeFile, edgeSize}`: `bgFile` MUST always come with
-- `edgeFile`+`edgeSize` on this client (a table missing them is what
-- causes the gold-tint bug).
S.PLAIN_BACKDROP = S.PLAIN_BACKDROP or {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}

-- THE shared surface primitive -- a brand-new child Frame that DRAWS,
-- never a `SetBackdrop` on the native frame itself.
--
-- This is not a style preference, it's this project's single most repeated
-- hard-won lesson: calling `SetBackdrop(frame, nil)` and then
-- `SetBackdrop(frame, {...})` on a native frame does NOT reliably replace
-- its backdrop on this client. It cost three rounds on
-- `ReputationDetailFrame`, three more on `DropDownList1-3` (measured: RGB
-- 57 -> RGB 58 after two "fixes"), and it is the reason
-- `MacroFrameTextBackground` came out light grey despite the code asking
-- for 0.05. Every caller goes through here now so the mistake can't be
-- made a fifth time.
--
-- `l/t/r/b` are raw anchor offsets against the frame's own TOPLEFT/
-- BOTTOMRIGHT; omit all four for a plain full-footprint surface.
-- The default is to pin the surface to its PARENT's own base level, i.e.
-- behind every child frame in the window -- what a backmost background
-- should always be, and the fix for two separate live-reported bugs
-- (ReputationDetailFrame's invisible checkboxes, PetPaperDollFrame's
-- missing header texts). `keepDefaultLevel` skips that call for the
-- callers that need to place the surface themselves afterwards
-- (`S:StyleEditBox`/`S:StyleDropDownBox` put it one level BELOW the
-- control, so the control's own text still renders on top).
function S:CreateSurface(frame, color, l, t, r, b, keepDefaultLevel)
	if not frame then return nil end
	if frame.elvBackground then return frame.elvBackground end

	local okBg, bg = pcall(CreateFrame, "Frame", nil, frame)
	if not okBg or not bg then return nil end

	if l or t or r or b then
		pcall(bg.SetPoint, bg, "TOPLEFT", frame, "TOPLEFT", tonumber(l) or 0, tonumber(t) or 0)
		pcall(bg.SetPoint, bg, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", tonumber(r) or 0, tonumber(b) or 0)
	else
		pcall(bg.SetAllPoints, bg, frame)
	end

	pcall(bg.SetBackdrop, bg, S.PLAIN_BACKDROP)
	pcall(bg.SetBackdropColor, bg, color[1], color[2], color[3], color[4] or 1)
	pcall(bg.SetBackdropBorderColor, bg, S.BORDER_COLOR[1], S.BORDER_COLOR[2], S.BORDER_COLOR[3], S.BORDER_COLOR[4])
	-- Never swallow a click meant for whatever sits on top of it.
	pcall(bg.EnableMouse, bg, false)
	-- Marks this as OUR frame so `S:StripTextures`' recursive walk skips it
	-- -- see that function's own note. Every skinned window calls
	-- `S:StripTextures(frame, true)` on every re-apply, and a surface
	-- created here is an unnamed direct child of exactly that frame, so
	-- without this flag the second OnShow would walk straight into it and
	-- `SetBackdrop(nil)` our own background away.
	bg.elvSurface = true
	-- Remembered so anything that later needs to blend INTO this surface can
	-- ask what it was painted with, instead of assuming the window tone --
	-- see `S:SurfaceColorFor`.
	bg.elvColor = color

	if not keepDefaultLevel then
		local okLevel, level = pcall(frame.GetFrameLevel, frame)
		pcall(bg.SetFrameLevel, bg, (okLevel and tonumber(level)) or 1)
	end

	frame.elvBackground = bg
	return bg
end

-- Window/panel surface (the dark slab a skinned window is drawn on).
function S:CreatePanel(frame, l, t, r, b, keepDefaultLevel)
	return S:CreateSurface(frame, S.PANEL_COLOR, l, t, r, b, keepDefaultLevel)
end

-- Field surface -- one step lighter than the panel, for an INPUT-shaped
-- area that has to read as a field rather than as part of the window:
-- multi-line text areas, list wells, anything an edit box scrolls inside.
-- Same tone as every skinned button, by construction (see WIDGET_COLOR).
function S:CreateField(frame, l, t, r, b, keepDefaultLevel)
	return S:CreateSurface(frame, S.WIDGET_COLOR, l, t, r, b, keepDefaultLevel)
end

-- Item slot in the QuestItemTemplate shape (trade skill and craft reagents),
-- styled like the merchant window's item slots (Blizzard/Merchant.lua): a
-- 37x37 icon with the shared 1px button border, the name beside it, and a
-- field surface from just past the icon to the slot's right edge, as tall as
-- the icon. No border around the whole slot, no quality tint.
--
-- Unlike a merchant slot, the icon and name are regions of the slot button
-- itself, and the field is a child frame at the button's own level, which
-- draws over the button's BACKGROUND/ARTWORK regions; the name is raised to
-- OVERLAY. So is the icon, which then covers the count text (`$parentCount`,
-- natively ARTWORK) -- the count is raised to OVERLAY too, AFTER the icon,
-- the order confirmed live to draw it on top. The icon border is
-- a holder frame pinned to the slot's level BEFORE Util.CreateButtonBorder,
-- which puts its backdrop one level below its target: a holder at the default
-- child level would put that backdrop above the icon.
--
-- `width`/`height` resize the slot (native QuestItemTemplate: 147x41).
local QUEST_ITEM_ICON_SIZE = 37
local QUEST_ITEM_FIELD_GAP = 4
local QUEST_ITEM_TEXT_GAP = 8

function S:StyleQuestItemSlot(slot, width, height)
	if not slot then return end
	local okName, name = pcall(slot.GetName, slot)
	if not okName or not name then return end

	if width then pcall(slot.SetWidth, slot, width) end
	if height then pcall(slot.SetHeight, slot, height) end
	S:Kill(_G[name .. "NameFrame"])

	if not slot.elvIconHolder then
		local okHolder, holder = pcall(CreateFrame, "Frame", nil, slot)
		if okHolder and holder then
			pcall(holder.SetWidth, holder, QUEST_ITEM_ICON_SIZE)
			pcall(holder.SetHeight, holder, QUEST_ITEM_ICON_SIZE)
			pcall(holder.SetPoint, holder, "TOPLEFT", slot, "TOPLEFT", 0, 0)
			local okLevel, level = pcall(slot.GetFrameLevel, slot)
			pcall(holder.SetFrameLevel, holder, (okLevel and tonumber(level)) or 4)
			if ElvUI.Util and ElvUI.Util.CreateButtonBorder then
				ElvUI.Util.CreateButtonBorder(holder)
			end
			slot.elvIconHolder = holder
		end
	end
	local holder = slot.elvIconHolder

	if not slot.elvBackground then
		local okHeight, slotHeight = pcall(slot.GetHeight, slot)
		local bottom = ((okHeight and tonumber(slotHeight)) or QUEST_ITEM_ICON_SIZE) - QUEST_ITEM_ICON_SIZE
		if bottom < 0 then bottom = 0 end
		S:CreateField(slot, QUEST_ITEM_ICON_SIZE + QUEST_ITEM_FIELD_GAP, 0, 0, bottom)
	end

	local icon = _G[name .. "IconTexture"]
	if icon and holder then
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", holder, "TOPLEFT", 1, -1)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
		pcall(icon.SetDrawLayer, icon, "OVERLAY")
	end

	local count = _G[name .. "Count"]
	if count then pcall(count.SetDrawLayer, count, "OVERLAY") end

	local label = _G[name .. "Name"]
	if label and holder then
		pcall(label.ClearAllPoints, label)
		pcall(label.SetPoint, label, "LEFT", holder, "RIGHT", QUEST_ITEM_TEXT_GAP, 0)
		pcall(label.SetDrawLayer, label, "OVERLAY")
	end
end

-- Doublewide panels (UIPanelWindows area "doublewide") do not replace each
-- other: FrameXML's SetDoublewideFrame hides the open left and center panels
-- but not a doublewide panel that is already open -- it only takes over the
-- reference -- so two of them open on top of each other. Called from a
-- doublewide window's OnShow, this hides every other shown doublewide panel.
-- A plain Hide() is enough, since the panel manager no longer references the
-- older frame; its own OnHide closes its session (CloseTradeSkill/CloseCraft)
-- without affecting the window that stays open (measured on UA, both ways).
-- Hiding fires that OnHide, which on UA leaves the `this` global changed.
function S:CloseOtherDoublewidePanels(frame)
	if not frame or type(UIPanelWindows) ~= "table" then return end
	local okName, keep = pcall(frame.GetName, frame)
	if not okName or not keep then return end

	local caller = this
	local name, info
	for name, info in pairs(UIPanelWindows) do
		if name ~= keep and type(info) == "table" and info.area == "doublewide" then
			local other = _G[name]
			local okShown, shown = false, false
			if other then okShown, shown = pcall(other.IsShown, other) end
			if okShown and shown then pcall(other.Hide, other) end
		end
	end
	this = caller
end

-- Re-anchors a region to fill `frame` shifted by (x, y). For a native list's
-- selection highlight: native code only re-anchors the highlight FRAME onto
-- the selected row and recolours its texture, so an offset on the texture
-- itself persists across list updates.
function S:ShiftRegionInFrame(region, frame, x, y)
	if not region or not frame then return end
	pcall(region.ClearAllPoints, region)
	pcall(region.SetPoint, region, "TOPLEFT", frame, "TOPLEFT", x or 0, y or 0)
	pcall(region.SetPoint, region, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", x or 0, y or 0)
end

-- What colour is this widget actually SITTING on? Walks up the parent chain
-- to the nearest frame this module has already drawn a surface on and
-- returns that surface's own colour, falling back to the window tone.
--
-- Needed by anything that has to blend into its background rather than
-- stand out on it -- currently the checkbox patch that covers the native
-- tick (`S:InstallCheckMark`), which would read as a visible slab if it
-- always assumed `PANEL_COLOR`: two of Sound Options' checkboxes live
-- inside the "Voice Chat Settings" box, which is deliberately a shade
-- lighter (`GROUP_COLOR`).
function S:SurfaceColorFor(frame)
	local current = frame
	local guard = 0
	while current and guard < 10 do
		local bg = current.elvBackground
		if bg and bg.elvColor then return bg.elvColor end
		local ok, parent = pcall(current.GetParent, current)
		if not ok then break end
		current = parent
		guard = guard + 1
	end
	return S.PANEL_COLOR
end

-- Shared with Blizzard/Character.lua's own tabs -- `FriendsFrameTabTemplate`
-- inherits `CharacterFrameTabButtonTemplate` directly (confirmed via the
-- FrameXML), so this is structurally the same 6-texture-piece tab template
-- Character's own tabs use, not a coincidental lookalike.
--
-- THE ONE TAB RECIPE for this project -- every tab family in
-- every skinned window goes through here now, with only the insets
-- differing (see `TAB_INSET_*` below). Previously SpellBook.lua's own
-- book-type tabs went through `S:StyleUIPanelButton` + a bespoke
-- resize/re-anchor instead, which is what made the windows look
-- inconsistent (and broke clicking outright -- see SpellBook.lua).
--
-- INSET BACKDROP -- this is the piece the project was missing,
-- and the root cause of the Who/Guild seam. A native tab's BUTTON footprint
-- is much wider than the tab looks, and consecutive tabs deliberately
-- OVERLAP (`LEFT` anchored to the previous tab's `RIGHT` at x=-14 for
-- CharacterFrame/FriendsFrame, x=-20 for SpellBook -- confirmed in the
-- FrameXML) so their curved native side art blends. Bordering the FULL
-- footprint therefore made neighbouring tabs' border boxes physically
-- overlap by ~16px, leaving which box's edge line wins undefined -- which
-- is why 3 of the 4 Friends junctions blended and one showed a hard seam.
-- Real ElvUI never borders the footprint: `S:HandleTab`
-- (source/ElvUI-vanilla/ElvUI/Modules/Skins/Skins.lua:163-183) insets its
-- backdrop by 10px horizontally, and its own SpellBook.lua overrides that
-- to 14/17/19 for the bigger book-type tabs. Ported here 1:1 via
-- `Util.CreateButtonBorder`'s new inset parameters. With a 10px inset and a
-- 14px overlap the boxes end up ~6px APART instead of ~16px overlapped, so
-- the collision can't happen at all any more -- each tab is its own island,
-- which is also exactly how real ElvUI's tab strips look.
S.TAB_INSET_X = 10
S.TAB_INSET_TOP = 1
S.TAB_INSET_BOTTOM = 3

function S:StyleTab(tab, insetX, insetTop, insetBottom, forceDisabled)
	if not tab then return end
	pcall(tab.SetBackdrop, tab, nil)
	pcall(tab.DisableDrawLayer, tab, "BACKGROUND")

	local okName, name = pcall(tab.GetName, tab)
	if okName and name then
		S:Kill(_G[name.."Left"])
		S:Kill(_G[name.."Middle"])
		S:Kill(_G[name.."Right"])
		S:Kill(_G[name.."LeftDisabled"])
		S:Kill(_G[name.."MiddleDisabled"])
		S:Kill(_G[name.."RightDisabled"])
	end

	local okNormal, normalTexture = pcall(tab.GetNormalTexture, tab)
	if okNormal and normalTexture then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		pcall(normalTexture.Hide, normalTexture)
		normalTexture.Show = E.noop
	end
	pcall(tab.SetNormalTexture, tab, "")

	local okHighlight, highlight = pcall(tab.GetHighlightTexture, tab)
	if okHighlight and highlight then
		pcall(highlight.SetTexture, highlight, nil)
		pcall(highlight.Hide, highlight)
		highlight.Show = E.noop
	end

	-- DisabledTexture -- the CharacterFrame/Friends tab templates have none
	-- (their "selected" look is the `...Disabled` BACKGROUND pieces killed
	-- above), but SpellBookFrameTabButton1-3 each carry a per-instance
	-- `UI-SpellBook-Tab{1,3}-Selected` DisabledTexture, and `Disable()` is
	-- how Blizzard marks the CURRENTLY SELECTED book -- so without this the
	-- selected spellbook tab kept its full native art. Setter-only (no
	-- `Hide()` recipe) because `GetDisabledTexture()` is confirmed missing
	-- on UA entirely -- see `S:StyleUIPanelButton`'s own note. Harmless
	-- no-op on the tab templates that never had one.
	pcall(tab.SetDisabledTexture, tab, "")

	-- Some tabs are natively `:Disable()`'d based on real game state (Guild,
	-- when not in a guild -- see `FriendsFrameTab3`'s own OnLoad,
	-- `InGuildCheck()`), always-enabled on Character.lua's own 5 tabs -- an
	-- unconditional gold recolor would make a natively `:Disable()`'d tab
	-- look identical to an enabled one, losing the native "you can't click
	-- this" grey signal entirely. Fixed: check `IsEnabled()` and use
	-- `S.ACCENT_COLOR_DISABLED` when it reports disabled. Re-evaluated
	-- every time chrome re-applies (every OnShow), same as every other
	-- per-tab styling call in this project -- not a live poll, so a state
	-- change WHILE the window is already open (e.g. joining a guild
	-- mid-session) won't recolor until the next open/close.
	--
	-- **`IsEnabled()` ALONE IS THE WRONG SOURCE OF TRUTH.** The Guild tab
	-- can intermittently come back GOLD despite the player not being in a
	-- guild, reliably reproduced by (open Social, close, open SpellBook,
	-- close, open Social). Reading the real FrameXML explains why that
	-- predicate could never be reliable: `Enable()`/`Disable()` are
	-- OVERLOADED on these tabs. `PanelTemplates_SelectTab` calls
	-- `tab:Disable()` to mark the CURRENTLY SELECTED tab, and
	-- `PanelTemplates_DeselectTab` calls `tab:Enable()` on every other one
	-- -- both fired from `PanelTemplates_UpdateTabs`, which runs on every
	-- tab switch and every `FriendsFrame_Update`
	-- (source/wow-ui-source/FrameXML/UIPanelTemplates.lua:15-29,107-133).
	-- So the widget's enabled bit means "selected or unusable", churns on
	-- unrelated native updates, and can be read mid-flight.
	--
	-- The flag Blizzard actually maintains for "this tab is UNUSABLE" is
	-- the plain Lua field **`tab.isDisabled`** (`PanelTemplates_DisableTab`
	-- sets it, `PanelTemplates_EnableTab` clears it, and
	-- `PanelTemplates_UpdateTabs` checks it FIRST, before either overload
	-- above). Reading a plain field the native code already maintains,
	-- instead of trusting a widget getter, is this project's own
	-- established answer to exactly this class of problem -- the same move
	-- `PollPlusMinusGlyphs` made for `.isCollapsed`/`.isExpanded`.
	--
	-- The predicate is deliberately ADDITIVE (`isDisabled` OR the old
	-- `IsEnabled()` check OR an explicit caller override): every term can
	-- only ever make a tab grey, never gold. The reported failure is
	-- "should be grey, went gold", so a strictly-more-disabling predicate
	-- cannot regress it in the other direction, and tab families where
	-- `isDisabled` is never set behave exactly as before.
	--
	-- `forceDisabled` lets a caller supply the authoritative answer where
	-- one exists. Friends.lua passes `not IsInGuild()` for tab 3 -- the
	-- SAME test Blizzard's own `ToggleFriendsFrame` uses to make that tab
	-- a no-op (FriendsFrame.lua:750) -- so the Guild tab is correct even
	-- if neither `isDisabled` nor `IsEnabled()` is trustworthy on this
	-- client.
	-- `$parentText` is the CharacterFrame/Friends tab templates' own named
	-- FontString, but `SpellBookFrameTabButtonTemplate`'s `<ButtonText>` is
	-- declared WITHOUT a name -- fall back to the widget-level getter so
	-- the accent color reaches those tabs too (same fallback
	-- `StyleColumnHeader` already uses in Friends.lua).
	local text = okName and name and _G[name.."Text"]
	if not text then
		local okFS, fontString = pcall(tab.GetFontString, tab)
		text = okFS and fontString or nil
	end
	if text then
		local disabled = false
		if forceDisabled then
			disabled = true
		elseif tab.isDisabled then
			disabled = true
		else
			local okEnabled, enabled = pcall(tab.IsEnabled, tab)
			if okEnabled and not enabled then disabled = true end
		end
		local color = disabled and S.ACCENT_COLOR_DISABLED or S.ACCENT_COLOR
		pcall(text.SetTextColor, text, color[1], color[2], color[3])
	end

	ElvUI.Util.CreateButtonBorder(tab,
		tonumber(insetX) or S.TAB_INSET_X,
		tonumber(insetTop) or S.TAB_INSET_TOP,
		tonumber(insetBottom) or S.TAB_INSET_BOTTOM)

	-- Lift the fill off the panel tone -- see `S.TAB_COLOR`. Done here
	-- rather than in `CreateButtonBorder` because that helper backs every
	-- ordinary button in the UI, and those are meant to stay at the widget
	-- tone; only tabs sit directly ON a panel and need to separate from it.
	if tab.elvBackdrop then
		pcall(tab.elvBackdrop.SetBackdropColor, tab.elvBackdrop,
			S.TAB_COLOR[1], S.TAB_COLOR[2], S.TAB_COLOR[3], S.TAB_COLOR[4] or 1)
	end

	-- Marks the tab as ours WITHOUT guarding the function -- callers still
	-- re-apply on every OnShow, which is what keeps the text colour correct
	-- after a native tab switch. The flag exists purely so `S:SkinChildren`'s
	-- own tab branch can tell an ALREADY-styled tab from
	-- a fresh one and leave it alone.
	--
	-- That distinction matters for exactly one reason: `forceDisabled`.
	-- Friends.lua passes `not IsInGuild()` for its Guild tab -- the
	-- authoritative answer on a client where neither `isDisabled` nor
	-- `IsEnabled()` is trustworthy -- and a later, argument-less sweep call
	-- would recolour that tab gold again, re-opening a bug this project has
	-- already fixed once. (The border itself is safe either way:
	-- `CreateButtonBorder` returns early when `elvBackdrop` exists, so the
	-- per-window insets can't be overwritten.)
	tab.elvStyled = true
end

-- A tab-seam collision is NOT a frame-level issue: giving each tab an
-- explicit, widely-spaced frame level before `CreateButtonBorder` runs
-- does not fix a visible seam between tabs, and can introduce the same
-- kind of visible gap into windows that were previously fine (tested and
-- disproven -- spacing out the levels made things worse, not better).
--
-- The seam IS a box-collision, just not a frame-level one: neighbouring
-- tabs' border boxes physically overlap by ~16px because the box wraps
-- the tab's full BUTTON footprint while the tabs themselves are anchored
-- to overlap by 14px. Fixed structurally in `S:StyleTab` above by
-- adopting real ElvUI's own inset backdrop, so no two tab boxes touch at
-- all any more. The resulting gaps between tabs are the INTENDED look
-- (matching real ElvUI's own tab strips), uniform across all 4 windows.
-- Measure before theorising if anything still looks off: `S:DumpTabs`
-- (bottom of this file) prints every tab's real edges/size/level on UA.

-- Pixel-level diagnostics for a tab-seam issue: this exists so a
-- diagnosis starts from real numbers off the live client instead of a
-- screenshot alone. Usage (both tab families):
--   /run ElvUI[1]:GetModule("Skins"):DumpTabs("FriendsFrameTab", 4)
--   /run ElvUI[1]:GetModule("Skins"):DumpTabs("CharacterFrameTab", 5)
--   /run ElvUI[1]:GetModule("Skins"):DumpTabs("SpellBookFrameTabButton", 3)
function S:DumpTabs(prefix, count)
	if not prefix then return end
	count = tonumber(count) or 4

	local i
	for i = 1, count do
		local tab = _G[prefix .. i]
		if not tab then
			E:Print(string.format("%s%d: MISSING", prefix, i))
		else
			local function get(method)
				local ok, value = pcall(tab[method], tab)
				if ok and tonumber(value) then return string.format("%.1f", value) end
				return tostring(ok and value)
			end
			local okShown, shown = pcall(tab.IsShown, tab)
			local okEnabled, enabled = pcall(tab.IsEnabled, tab)
			E:Print(string.format("%s%d: L=%s R=%s T=%s B=%s w=%s h=%s lvl=%s shown=%s enabled=%s",
				prefix, i,
				get("GetLeft"), get("GetRight"), get("GetTop"), get("GetBottom"),
				get("GetWidth"), get("GetHeight"), get("GetFrameLevel"),
				tostring(okShown and shown), tostring(okEnabled and enabled)))

			-- STATE line, for the Guild-tab "sometimes gold, should be
			-- grey" bug class. Prints the three things
			-- that decide the text color, so a repeat can be settled with
			-- one command instead of another theory: `isDisabled` (the
			-- plain field Blizzard's own PanelTemplates maintains, and what
			-- `S:StyleTab` now reads), the widget's own enabled bit above
			-- (overloaded to also mean "selected" -- see `S:StyleTab`), and
			-- the color actually ON the FontString right now. `r=1.00` with
			-- `isDisabled=1` is the exact failure signature.
			local stateText = _G[prefix .. i .. "Text"]
			if not stateText then
				local okFS, fontString = pcall(tab.GetFontString, tab)
				stateText = okFS and fontString or nil
			end
			local r, g, b = nil, nil, nil
			if stateText then
				local okColor, cr, cg, cb = pcall(stateText.GetTextColor, stateText)
				if okColor then r, g, b = cr, cg, cb end
			end
			E:Print(string.format("    state: isDisabled=%s color=%s/%s/%s",
				tostring(tab.isDisabled),
				(tonumber(r) and string.format("%.2f", r)) or tostring(r),
				(tonumber(g) and string.format("%.2f", g)) or tostring(g),
				(tonumber(b) and string.format("%.2f", b)) or tostring(b)))

			local box = tab.elvBackdrop
			if box then
				local function boxGet(method)
					local ok, value = pcall(box[method], box)
					if ok and tonumber(value) then return string.format("%.1f", value) end
					return tostring(ok and value)
				end
				E:Print(string.format("    box: L=%s R=%s T=%s B=%s lvl=%s",
					boxGet("GetLeft"), boxGet("GetRight"), boxGet("GetTop"),
					boxGet("GetBottom"), boxGet("GetFrameLevel")))
			else
				E:Print("    box: none (S:StyleTab never ran on this tab)")
			end
		end
	end
end

-- Spell-button overlay diagnostic. Exists because a screenshot alone
-- couldn't distinguish between two candidate fixes for a pet auto-cast
-- marker that wasn't scaling with its button (the `$parentAutoCast`
-- model's frame level, vs. re-anchoring `$parentAutoCastable` outside the
-- button) -- at which point the rule is: MEASURE, don't produce a third
-- theory.
--
-- There are FOUR separate overlays stacked on a `SpellButtonTemplate`
-- (source/wow-ui-source/FrameXML/SpellBookFrame.xml:74-201), and the
-- screenshot cannot tell them apart:
--   * `$parentAutoCastable` -- gold corner flares, shown when auto-cast is
--     ALLOWED. Fixed 60x60 CENTER natively; this skin re-anchors it.
--   * `$parentAutoCast` -- the rotating shine Model, shown when auto-cast
--     is currently ON. 36x36 CENTER, scale 1.22.
--   * `$parentHighlight` -- `ButtonHilight-Square`, which this skin's own
--     `SpellButton_UpdateButton` hook repaints to a flat white 0.3 alpha.
--   * the **CheckedTexture** -- `CheckButtonHilight`, a pale square, driven
--     by the native `this:SetChecked(...)`. It is declared WITHOUT A NAME
--     in the template, so there is no `_G` lookup for it and this project
--     has never touched it. Prime suspect for a white square that no
--     amount of `$parentAutoCastable` work changes.
--
-- Usage, with the PET spellbook open on a spell that shows the marker:
--   /run ElvUI[1]:GetModule("Skins"):DumpSpellButton(1)
-- (the index is the SpellButton number, 1-12, counting down the page).
-- Generalised from a spellbook-only version: "several textures stacked on
-- one native Button, and the screenshot can't tell them apart" is simply
-- a recurring shape in this project, so the tool takes a name now.
--
--   /run ElvUI[1]:GetModule("Skins"):DumpButton("MacroFrameSelectedMacroButton")
--   /run ElvUI[1]:GetModule("Skins"):DumpButton("SpellButton1")
--
-- Prints, for the button and every overlay it can reach: shown, real edges,
-- size, alpha and texture path -- plus `IsChecked()`. Note which slots this
-- client will and won't hand back (all measured): `GetNormalTexture`/
-- `GetHighlightTexture` work, `GetCheckedTexture`/`GetDisabledTexture` do
-- not, and a CheckedTexture does not appear in `GetRegions()` either -- so
-- a missing "CheckedTexture" line is NOT proof that no checked texture is
-- rendering.
function S:DumpButton(name, extraSuffixes)
	if not name then return end
	local button = _G[name]
	if not button then E:Print(tostring(name) .. ": MISSING") return end

	local function geom(obj, label)
		if not obj then E:Print(string.format("  %s: nil", label)) return end
		local function get(method)
			local ok, value = pcall(obj[method], obj)
			if ok and tonumber(value) then return string.format("%.1f", value) end
			return tostring(ok and value)
		end
		local okShown, shown = pcall(obj.IsShown, obj)
		local okTex, tex = pcall(obj.GetTexture, obj)
		local okAlpha, alpha = pcall(obj.GetAlpha, obj)
		E:Print(string.format("  %s: shown=%s L=%s R=%s T=%s B=%s w=%s h=%s a=%s",
			label, tostring(okShown and shown),
			get("GetLeft"), get("GetRight"), get("GetTop"), get("GetBottom"),
			get("GetWidth"), get("GetHeight"),
			(okAlpha and tonumber(alpha)) and string.format("%.2f", alpha) or tostring(alpha)))
		if okTex and tex then E:Print(string.format("      tex=%s", tostring(tex))) end
	end

	local okChecked, checked = pcall(button.IsChecked, button)
	E:Print(string.format("%s: checked=%s", name, tostring(okChecked and checked)))
	geom(button, "button")

	-- Named children, by convention across the templates this project
	-- skins. A caller can add more via `extraSuffixes`.
	local SUFFIXES = { "IconTexture", "Icon", "NormalTexture", "Background",
		"Highlight", "AutoCastable", "AutoCast", "Name" }
	local s
	for s = 1, table.getn(SUFFIXES) do
		local child = _G[name .. SUFFIXES[s]]
		if child then geom(child, SUFFIXES[s]) end
	end
	if type(extraSuffixes) == "table" then
		for s = 1, table.getn(extraSuffixes) do
			local child = _G[name .. extraSuffixes[s]]
			if child then geom(child, extraSuffixes[s]) end
		end
	end

	-- Slot textures reachable by getter (the two that work on UA).
	local okNT, normalTex = pcall(button.GetNormalTexture, button)
	if okNT and normalTex then geom(normalTex, "GetNormalTexture()") end
	local okHT, hlTex = pcall(button.GetHighlightTexture, button)
	if okHT and hlTex then geom(hlTex, "GetHighlightTexture()") end

	-- EVERY Texture region, unfiltered. This is the part that matters for a
	-- "where is that leftover frame coming from" hunt: an overlay with no
	-- global name and no working getter can still show up here, and its
	-- texture PATH names the culprit outright.
	local okAll, allRegions = pcall(function() return { button:GetRegions() } end)
	if okAll and type(allRegions) == "table" then
		local r
		for r = 1, table.getn(allRegions) do
			local region = allRegions[r]
			local okRType, rType = pcall(region.GetObjectType, region)
			if okRType and rType == "Texture" then
				geom(region, "region " .. r)
			end
		end
	end

	-- CheckedTexture: no name in the templates, and no working getter on
	-- this client -- so if the unfiltered region walk above didn't list it
	-- either, it is INVISIBLE to Lua here, not absent. Say so explicitly,
	-- because "the dump didn't show it" is exactly the kind of line a later
	-- session would misread as proof.
	local okCheckTex, checkTex = pcall(button.GetCheckedTexture, button)
	if okCheckTex and checkTex then
		geom(checkTex, "CheckedTexture(getter)")
	else
		E:Print("  CheckedTexture: no getter on this client -- if it is not in the")
		E:Print("    region list above either, it is UNREACHABLE from Lua, NOT absent.")
		E:Print("    Clear it blind with SetCheckedTexture(btn, \"\") to test.")
	end
end

-- Thin wrapper kept so the spellbook docs' own copy-paste line still works.
function S:DumpSpellButton(index)
	S:DumpButton("SpellButton" .. (tonumber(index) or 1))
end

-- Shared with Blizzard/Character.lua's own close button, same reason as
-- `S:StyleTab` above -- Friends.lua needs an identical close button
-- (strip native X art, fixed 20x20, bordered, plain "X" glyph) for
-- `FriendsFrameCloseButton`.
function S:StyleCloseButton(button)
	if not button then return end
	pcall(button.SetNormalTexture, button, "")
	pcall(button.SetPushedTexture, button, "")
	pcall(button.SetHighlightTexture, button, "")
	pcall(button.SetWidth, button, 20)
	pcall(button.SetHeight, button, 20)
	ElvUI.Util.CreateButtonBorder(button)

	if not button.elvCloseText then
		local text = button:CreateFontString(nil, "OVERLAY")
		pcall(text.SetFont, text, "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		pcall(text.SetText, text, "X")
		pcall(text.SetPoint, text, "CENTER", button, "CENTER", 0, 0)
		button.elvCloseText = text
	end
end

-- Ported from real ElvUI's own `S:HandleButtonHighlight`
-- (source/ElvUI-vanilla/ElvUI/Modules/Skins/Skins.lua:85-101) -- a lighter
-- touch than it might look: blanks the native HighlightTexture slot, then
-- ADDS two brand-new HIGHLIGHT-layer gradient textures as children (never
-- modifies the row Button's own existing regions beyond that one setter
-- call). `E.media.blankTex` (real ElvUI's own media token) has no
-- equivalent in this project -- substituted with the plain white texture
-- already used everywhere else in this file (`Interface\Buttons\WHITE8x8`).
--
-- **CONFIRMED BROKEN on FriendsFrameFriendButton<i> -- DO NOT call this
-- on Friends/Ignore rows without new evidence, and think twice before
-- any other native LIST ROW too.** Added as a deliberate live test of
-- source/UnrealUI's own crash claim for touching these rows (see
-- Friends.lua's own history) -- it did NOT crash the client, but a real,
-- different regression appeared instead: a friend's row went from its
-- normal color to a permanent grey, and the row could no longer be
-- SELECTED at all (so Remove Friend had nothing to act on).
-- Most likely cause, not yet independently confirmed: `SetGradientAlpha`
-- is unverified on this client and may be silently failing (pcall-
-- swallowed) or behaving differently, leaving the plain
-- `Interface\Buttons\WHITE8x8` fill fully opaque and PERMANENTLY shown
-- rather than only during hover/selection -- i.e. the HIGHLIGHT draw
-- layer's usual "only visible while highlighted" semantics may not hold
-- here, matching this whole project's repeated finding that native
-- layer/state semantics often don't transfer 1:1 to UA. Reverted in
-- Friends.lua; this function itself is kept (not deleted) as a documented
-- dead end.
function S:HandleButtonHighlight(frame)
	if not frame then return end
	pcall(frame.SetHighlightTexture, frame, "")

	if frame.elvHighlight then return end
	frame.elvHighlight = true

	local okW, w = pcall(frame.GetWidth, frame)
	local okH, h = pcall(frame.GetHeight, frame)
	w = (okW and tonumber(w)) or 0
	h = (okH and tonumber(h)) or 0

	local okLeft, leftGrad = pcall(frame.CreateTexture, frame, nil, "HIGHLIGHT")
	if okLeft and leftGrad then
		pcall(leftGrad.SetWidth, leftGrad, w * 0.5)
		pcall(leftGrad.SetHeight, leftGrad, h * 0.95)
		pcall(leftGrad.SetPoint, leftGrad, "LEFT", frame, "CENTER")
		pcall(leftGrad.SetTexture, leftGrad, "Interface\\Buttons\\WHITE8x8")
		pcall(leftGrad.SetGradientAlpha, leftGrad, "Horizontal", 0.9, 0.9, 0.9, 0.35, 0.9, 0.9, 0.9, 0)
	end

	local okRight, rightGrad = pcall(frame.CreateTexture, frame, nil, "HIGHLIGHT")
	if okRight and rightGrad then
		pcall(rightGrad.SetWidth, rightGrad, w * 0.5)
		pcall(rightGrad.SetHeight, rightGrad, h * 0.95)
		pcall(rightGrad.SetPoint, rightGrad, "RIGHT", frame, "CENTER")
		pcall(rightGrad.SetTexture, rightGrad, "Interface\\Buttons\\WHITE8x8")
		pcall(rightGrad.SetGradientAlpha, rightGrad, "Horizontal", 0.9, 0.9, 0.9, 0, 0.9, 0.9, 0.9, 0.35)
	end
end

-- Shared with Blizzard/Character.lua's own action buttons, same reason as
-- the two above -- Friends.lua's own `UIPanelButtonTemplate` action buttons (Add
-- Friend, Remove Friend, Send Message, Group Invite, ...) need the
-- identical recipe (strip native Normal/Pushed/Highlight, border, accent
-- text) Character.lua's own Reputation/Skill accept/cancel buttons use.
-- A panel button's label. `<name>Text` is what the FrameXML templates
-- name it (`<ButtonText name="$parentText"/>`), but an ANONYMOUS button --
-- exactly what an addon injecting a row into a native window tends to
-- create -- has no such global, and the label would silently keep its
-- native colour on an otherwise fully skinned button. `Button:GetFontString`
-- works on UA (Button.md) and needs no name at all, so it is the fallback.
local function ButtonLabel(button)
	local okName, name = pcall(button.GetName, button)
	if okName and name then
		local text = _G[name.."Text"]
		if text then return text end
	end
	local okFS, fontString = pcall(button.GetFontString, button)
	if okFS and fontString then return fontString end
	return nil
end

function S:StyleUIPanelButton(button)
	if not button then return end
	if button.elvStyled then
		-- Text can stay the NATIVE color on one tab while another correctly
		-- shows the accent color (SpellBook.lua's own outer book-type
		-- tabs). Root cause: native code
		-- (`SpellBookFrame_SetTabType`) calls `tabButton:SetText(...)` on
		-- EVERY update, unconditionally -- which resets the FontString's
		-- color back to whatever font object (Normal/Disabled) currently
		-- applies, discarding a one-time `SetTextColor` the moment the
		-- button's text is next reassigned. Same root cause class as
		-- `S:StyleTab`'s own already-fixed Guild-tab color bug (native
		-- re-asserts after a one-time style). Fixed the same way: text
		-- color re-applies on EVERY call now, not gated by `elvStyled` --
		-- the strip/border work below still only runs once (cheap to skip
		-- on repeat calls, no flicker risk since nothing there changes).
		local text = ButtonLabel(button)
		if text then
			pcall(text.SetTextColor, text, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
		end
		return
	end
	button.elvStyled = true

	local okNormal, normalTexture = pcall(button.GetNormalTexture, button)
	if okNormal and normalTexture then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		pcall(normalTexture.Hide, normalTexture)
		normalTexture.Show = E.noop
	end
	local okPushed, pushedTexture = pcall(button.GetPushedTexture, button)
	if okPushed and pushedTexture then
		pcall(pushedTexture.SetTexture, pushedTexture, nil)
		pcall(pushedTexture.Hide, pushedTexture)
		pushedTexture.Show = E.noop
	end
	local okHighlight, highlightTexture = pcall(button.GetHighlightTexture, button)
	if okHighlight and highlightTexture then
		pcall(highlightTexture.SetTexture, highlightTexture, nil)
		pcall(highlightTexture.Hide, highlightTexture)
		highlightTexture.Show = E.noop
	end

	-- DisabledTexture -- NOT reachable via the same Hide()+noop recipe as
	-- the 3 slots above: `GetDisabledTexture()` is confirmed missing on UA
	-- entirely (see `S:StyleSquareIconButton`'s own note above), so there
	-- is no texture OBJECT to grab and hide here, only the SETTER.
	-- `FriendsFrameStopIgnoreButton`, disabled at the time (empty ignore
	-- list), still showed full native art -- unlike Normal/Pushed/Highlight,
	-- this button's DISABLED slot was never touched at all until now, so
	-- the original XML-assigned native texture was still exactly what
	-- rendered while disabled. First attempt at a fix: the SETTER-only
	-- call, blanking the slot the same way `S:HandleButtonHighlight`
	-- blanks HighlightTexture via `SetHighlightTexture(button, "")` rather
	-- than needing the getter.
	-- The setter-only blank is kept, but the region itself is also
	-- located via `S:GetDisabledTexture` (which
	-- works around the missing getter by walking `button:GetRegions()` --
	-- see its own note) and given the exact same Hide()+noop treatment as
	-- the three slots above, so this no longer depends on a setter-only
	-- clear actually stopping the render. `UIPanelButtonTemplate`'s own
	-- disabled art is `Interface\Buttons\UI-Panel-Button-Disabled`, so the
	-- lookup's primary path match applies here.
	-- Lookup FIRST -- the blank below overwrites the very asset path the
	-- lookup matches on.
	local disabledTexture = S:GetDisabledTexture(button)
	if disabledTexture then
		pcall(disabledTexture.SetTexture, disabledTexture, nil)
		pcall(disabledTexture.Hide, disabledTexture)
		disabledTexture.Show = E.noop
	end
	pcall(button.SetDisabledTexture, button, "")

	-- `UIPanelButtonTemplate2` (source/wow-ui-source/FrameXML/
	-- UIPanelTemplates.xml:28+) has NO Normal/Pushed/Highlight/Disabled
	-- slot at all: it draws the same `UI-Panel-Button` art as three NAMED
	-- BACKGROUND regions, `$parentLeft`/`$parentMiddle`/`$parentRight`, and
	-- its own OnMouseDown/OnMouseUp re-assign the `-Down`/`-Up` asset to
	-- all three on every press. The four texture slots above therefore find
	-- nothing to clear on such a button and it keeps its full native art,
	-- with our own border frame hidden UNDER it (`Util.CreateButtonBorder`
	-- sits one frame level below the button, i.e. below the button's own
	-- regions) -- which is exactly how KeyBindingFrame's 34 key buttons
	-- rendered: untouched native art with a barely visible box around it.
	--
	-- `S:Kill` rather than `SetTexture(nil)` specifically because of those
	-- two scripts: a permanently noop'd `Show` survives the native
	-- reassignment, so the button needs no OnMouseDown/OnMouseUp override
	-- of its own (which is what pfUI resorts to on this same window).
	-- Same three regions `S:StyleTab` and `S:StyleEditBox` already kill for
	-- their own templates.
	local okChromeName, chromeName = pcall(button.GetName, button)
	if okChromeName and chromeName then
		S:Kill(_G[chromeName.."Left"])
		S:Kill(_G[chromeName.."Middle"])
		S:Kill(_G[chromeName.."Right"])
	end

	ElvUI.Util.CreateButtonBorder(button)

	local text = ButtonLabel(button)
	if text then
		pcall(text.SetTextColor, text, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	end
end

-- Shared square-icon-button recipe, ported from real ElvUI's own
-- `S:HandleNextPrevButton`/`S:SquareButton_SetIcon`
-- (source/ElvUI-vanilla/ElvUI/Modules/Skins/Skins.lua:24-37, 185-241).
-- Hoisted here (not left local to Blizzard/Character.lua, where it was
-- first written) once a SECOND consumer (scrollbar up/down arrows, see
-- `S:HandleScrollBar` below) needed the identical recipe -- matches
-- this file's own stated policy of only sharing what's ACTUALLY used by
-- more than one skin file.
--
-- Real ElvUI's own icon is a FIXED 13x13 texture, always CENTERED in the
-- button regardless of the button's own outer size -- NOT an inset that
-- scales with the button. A growing inset alone has no visible size
-- effect -- the actual missing piece was that the
-- BUTTON's own width/height also needs to be resized by the caller
-- (real ElvUI does this per call site, e.g. `E:Size(button, 24)` for
-- Skill Detail's own Unlearn button) -- this helper only handles the
-- icon; resizing the button itself is the caller's job.

-- WORKAROUND for UA's missing `Button:GetDisabledTexture()`.
-- The setter works, the getter doesn't exist -- which until now meant the
-- DISABLED slot could be REASSIGNED but never CROPPED (no object to call
-- `SetTexCoord` on), so feeding it a sprite sheet rendered the full
-- uncropped atlas. That's what forced the earlier "never touch the disabled
-- slot at all" compromise, and it only held up where the button never
-- actually gets disabled (the scrollbar arrows, thanks to
-- `ReplaceFauxScrollFrameUpdate`). SpellBook's own page arrows blow that
-- assumption apart: `SpellBook_UpdatePageArrows` (FrameXML) calls
-- `:Disable()`/`:Enable()` on them on literally every page change and
-- window open, and both are disabled outright on a single-page book -- so
-- both arrows show full native art.
--
-- The getter isn't the only way to reach the region though: the texture
-- object is a plain REGION of the button, so `button:GetRegions()` returns
-- it like any other. Identified primarily by its asset PATH (every native
-- disabled texture in this game generation is named `...-Disabled`, e.g.
-- `Interface\Buttons\UI-SpellbookIcon-PrevPage-Disabled` -- confirmed in
-- the FrameXML), with elimination against the three slots that DO have
-- working getters as a fallback for a button whose disabled art isn't
-- named that way. Cached on the button, so it survives our own later
-- reassignment of the texture (after which the path no longer matches).
function S:GetDisabledTexture(button)
	if not button then return nil end
	if button.elvDisabledTexture then return button.elvDisabledTexture end

	-- Prefer the real getter on any client that DOES implement it -- this
	-- helper is a fallback, not a replacement.
	local okNative, nativeTexture = pcall(button.GetDisabledTexture, button)
	if okNative and nativeTexture then
		button.elvDisabledTexture = nativeTexture
		return nativeTexture
	end

	local okRegions, regions = pcall(function() return { button:GetRegions() } end)
	if not okRegions or type(regions) ~= "table" then return nil end
	local regionCount = table.getn(regions)

	local i
	local function isTexture(region)
		local okType, regionType = pcall(region.GetObjectType, region)
		return okType and regionType == "Texture"
	end

	-- PASS 1: asset path. Deliberately does NOT consult the known-slot set
	-- below -- frame/region identity comparison is itself unreliable on
	-- this client (a stored reference and a freshly-queried reference to
	-- the same frame can compare unequal), and the path is decisive on
	-- its own.
	for i = 1, regionCount do
		local region = regions[i]
		if isTexture(region) then
			local okPath, path = pcall(region.GetTexture, region)
			if okPath and type(path) == "string" and string.find(string.lower(path), "disabled") then
				button.elvDisabledTexture = region
				return region
			end
		end
	end

	-- PASS 2: elimination against the three slots whose getters DO work.
	-- This is the path that suffers if region identity misbehaves -- and it
	-- degrades safely, because an unmatched Normal/Pushed/Highlight just
	-- pushes the candidate count above 1 and the guard below bails out.
	local known = {}
	local slot
	for slot = 1, 3 do
		local getter = (slot == 1 and button.GetNormalTexture)
			or (slot == 2 and button.GetPushedTexture)
			or button.GetHighlightTexture
		local okSlot, texture = pcall(getter, button)
		if okSlot and texture then known[texture] = true end
	end

	local candidate, candidateCount = nil, 0
	for i = 1, regionCount do
		local region = regions[i]
		if isTexture(region) and not known[region] then
			if not candidate then candidate = region end
			candidateCount = candidateCount + 1
		end
	end

	-- Elimination is only trusted when it's UNAMBIGUOUS. With two or more
	-- unaccounted-for Texture regions there's no way to tell the disabled
	-- art from a decorative region, and guessing wrong would overwrite
	-- something visible with an arrow -- exactly the class of "modified a
	-- pre-existing native region and broke it" bug this project keeps
	-- hitting. Better to leave the disabled art native than to clobber the
	-- wrong region.
	if candidateCount == 1 then
		button.elvDisabledTexture = candidate
		return candidate
	end
	return nil
end

-- A page-nav button's PREV/NEXT (or similar) label is a BACKGROUND-layer
-- FontString declared directly on the button itself, with no global name
-- of its own to hand to `S:Kill` -- walk the button's own regions and kill
-- every FontString found. Safe to be blanket about it: this project's
-- page-nav buttons (SpellBook, Merchant, and any future one built the same
-- way) carry no other text. Hoisted from `SpellBook.lua`'s own
-- file-local copy once Merchant.lua became a second consumer.
function S:KillButtonLabel(button)
	if not button or button.elvLabelKilled then return end
	button.elvLabelKilled = true

	local ok, regions = pcall(function() return { button:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end

	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "FontString" then
			pcall(region.SetText, region, "")
			S:Kill(region)
		end
	end
end

S.SQUARE_BUTTON_TEXTURE = "Interface\\AddOns\\ElvUI\\Media\\Textures\\SquareButtonTextures"
S.SQUARE_BUTTON_TEXCOORDS = {
	UP = { 0.453125, 0.640625, 0.015625, 0.203125 },
	DOWN = { 0.453125, 0.640625, 0.203125, 0.015625 },
	LEFT = { 0.234375, 0.421875, 0.015625, 0.203125 },
	RIGHT = { 0.421875, 0.234375, 0.015625, 0.203125 },
	DELETE = { 0.015625, 0.203125, 0.015625, 0.203125 },
}

-- Feeds the SAME ElvUI arrow (with the correct TexCoord crop) to all 4 of
-- the button's own real texture slots via the standard
-- `SetNormalTexture`/`SetPushedTexture`/`SetDisabledTexture`/
-- `SetHighlightTexture` API, exactly like every other native Button in
-- this game does it, rather than fighting `Button:Enable()`/`Disable()` --
-- a NATIVE, engine-level mechanism that automatically swaps which of the
-- button's own texture SLOTS is shown -- with a separate, manually-managed
-- overlay texture. Native Enable()/Disable() then swaps between OUR
-- textures automatically and correctly, the same way it's always
-- correctly swapped between Blizzard's own.
--
-- The four native slots alone are NOT sufficient though, so an own icon
-- layer is used too:
--   * "feed the native mechanism our own asset" only works for slots whose
--     texture object can be retrieved and cropped. The DISABLED slot's
--     can't (no `GetDisabledTexture` on UA), and reaching its region the
--     long way round (`S:GetDisabledTexture`, above) then reassigning it
--     renders NOTHING -- the standard "modifying a pre-existing native
--     region silently fails" outcome.
--   * An overlay icon parented to the button directly is NOT doomed by
--     native `Disable()` breaking it, as might be assumed: what
--     `Disable()` manipulates is the button's own texture REGIONS; child
--     FRAMES are untouched -- `CreateButtonBorder`'s border frames stay
--     fully visible on a disabled button. An overlay parented to a child
--     frame is therefore immune, and needs no polling to stay alive.
function S:StyleSquareIconButton(button, iconName, iconScale)
	if not button then return end

	local coords = S.SQUARE_BUTTON_TEXCOORDS[iconName]
	button.elvIconName = iconName

	if ElvUI.Util and ElvUI.Util.CreateButtonBorder then
		ElvUI.Util.CreateButtonBorder(button)
	end

	-- OWN, ALWAYS-ON ICON -- the state-independent layer. Pointing
	-- `SetTexture`/`SetTexCoord` at a PRE-EXISTING native texture region
	-- frequently does not apply on this client (this project's single
	-- most-repeated finding), while a brand-new region created by us
	-- always works -- same fix that made the Character sheet's resistance
	-- icons work.
	--
	-- Parented to a child FRAME, not to the button directly: child FRAMES
	-- demonstrably survive `Disable()` on this client -- the border boxes
	-- built by `CreateButtonBorder` stay perfectly visible on a disabled
	-- button -- whereas a texture REGION owned by the button itself is
	-- exactly what `Disable()` manipulates. So the icon lives on a frame
	-- the native state machine has no reason to touch. Confirmed working
	-- live: a disabled button still renders this icon, which is also
	-- independent proof the child-frame reasoning above is right.
	--
	-- `iconScale` (optional, default 1 = fill the button, byte-identical to
	-- the previous behaviour for every existing call site) shrinks the icon
	-- inside the same button/border footprint. Real ElvUI's own
	-- `S:HandleNextPrevButton` uses a FIXED 13x13 icon centered in whatever
	-- size the button is; a scale factor is used here instead so the
	-- already-accepted scrollbar-arrow and Unlearn-button sizes don't move
	-- while SpellBook's own 32x32 page arrows can be toned down.
	if not button.elvIcon then
		local okLevel, level = pcall(button.GetFrameLevel, button)
		local buttonLevel = (okLevel and tonumber(level)) or 4

		local okHolder, holder = pcall(CreateFrame, "Frame", nil, button)
		if okHolder and holder then
			pcall(holder.SetAllPoints, holder, button)
			pcall(holder.EnableMouse, holder, false)
			pcall(holder.SetFrameLevel, holder, buttonLevel + 1)

			local okIcon, icon = pcall(holder.CreateTexture, holder, nil, "ARTWORK")
			if okIcon and icon then
				button.elvIconHolder = holder
				button.elvIcon = icon
			end
		end
	end
	if button.elvIcon then
		local icon = button.elvIcon
		pcall(icon.SetTexture, icon, S.SQUARE_BUTTON_TEXTURE)
		if coords then
			pcall(icon.SetTexCoord, icon, coords[1], coords[2], coords[3], coords[4])
		end

		local scale = tonumber(iconScale)
		if not scale or scale >= 1 then
			-- Anchor-based, so it tracks the button even if a caller
			-- resizes the button AFTER styling it (StyleUnlearnButton does
			-- exactly that).
			pcall(icon.ClearAllPoints, icon)
			pcall(icon.SetAllPoints, icon, button.elvIconHolder)
		else
			-- Explicit size, re-asserted on every call (this whole function
			-- re-runs on each window OnShow) so a later button resize is
			-- picked up on the next re-apply.
			local okW, w = pcall(button.GetWidth, button)
			local okH, h = pcall(button.GetHeight, button)
			w = (okW and tonumber(w)) or 0
			h = (okH and tonumber(h)) or 0
			if w > 0 and h > 0 then
				pcall(icon.ClearAllPoints, icon)
				pcall(icon.SetWidth, icon, w * scale)
				pcall(icon.SetHeight, icon, h * scale)
				pcall(icon.SetPoint, icon, "CENTER", button.elvIconHolder, "CENTER", 0, 0)
			end
		end
	end

	-- ALL FOUR native slots are now BLANKED, not fed our own asset.
	-- Assigning the arrow to Normal/Pushed made sense while
	-- they were the only thing drawing it; now that `button.elvIcon` above
	-- is the icon in every state, leaving them assigned would draw a
	-- SECOND, full-button-sized copy underneath -- which is what made
	-- `iconScale` impossible (halving the overlay would just reveal the
	-- full-size native-slot arrow behind it) and would also have made the
	-- enabled state slightly bolder than the disabled one. This is also
	-- what real ElvUI's own `S:HandleNextPrevButton` does: nil out all four
	-- slots, then draw a single icon texture it owns.
	pcall(button.SetNormalTexture, button, "")
	local okNormal, normalTexture = pcall(button.GetNormalTexture, button)
	if okNormal and normalTexture then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		pcall(normalTexture.Hide, normalTexture)
		normalTexture.Show = E.noop
	end

	pcall(button.SetPushedTexture, button, "")
	local okPushed, pushedTexture = pcall(button.GetPushedTexture, button)
	if okPushed and pushedTexture then
		pcall(pushedTexture.SetTexture, pushedTexture, nil)
		pcall(pushedTexture.Hide, pushedTexture)
		pushedTexture.Show = E.noop
	end

	-- `GetDisabledTexture()` is not implemented on UA at all.
	-- `SetDisabledTexture` (the SETTER) very likely still succeeds -- but
	-- with no way to get the resulting texture object back, `SetTexCoord`
	-- can never be applied to it, so the DISABLED slot would show the
	-- FULL, UNCROPPED sprite sheet (all 5 icons squished together) --
	-- matching exactly the "completely different icon" symptom (first a
	-- diamond/gem-looking blob, then a "][" bracket-looking one -- both
	-- just different visual interpretations of the same uncropped-atlas
	-- render, not two different bugs). An initial fix left the DISABLED
	-- slot untouched entirely, on the theory that a Button with no
	-- DisabledTexture assigned keeps showing its NormalTexture when
	-- disabled.
	--
	-- That only holds when the button never actually gets disabled --
	-- true for the scrollbar arrows (thanks to
	-- `ReplaceFauxScrollFrameUpdate` below), but not in general: leaving
	-- the slot alone does NOT clear a DisabledTexture the XML already
	-- assigned, and a button that DOES get natively `:Disable()`d with one
	-- assigned (e.g. `SpellBookPrevPageButton`/`NextPageButton`, disabled
	-- on a single-page book) shows full native art.
	--
	-- Fixed properly by reaching the region WITHOUT the missing getter --
	-- `S:GetDisabledTexture` (above) finds it among `button:GetRegions()`
	-- by asset path -- which finally makes the crop possible, so the
	-- disabled slot can carry the same cropped ElvUI arrow as the other
	-- three. The setter-only blank is kept as a belt-and-braces first
	-- step for any button whose disabled region can't be located at all.
	--
	-- Assigning the ElvUI sheet to the located native disabled REGION and
	-- cropping it in place produces an empty box -- the reassignment
	-- silently doesn't render, the pre-existing-native-region failure mode
	-- this project has hit over and over. So the disabled slot is no
	-- longer used to CARRY the icon at all: `button.elvIcon` above (a
	-- texture we created ourselves, on a child frame) is the icon in every
	-- state now, and this block's only job is to make sure no native
	-- disabled art renders underneath it. Both mechanisms are used, since
	-- neither is individually guaranteed on this client: the Hide()+noop
	-- recipe on the located region, and the setter-only blank.
	local disabledTexture = S:GetDisabledTexture(button)
	if disabledTexture then
		pcall(disabledTexture.SetTexture, disabledTexture, nil)
		pcall(disabledTexture.Hide, disabledTexture)
		disabledTexture.Show = E.noop
	end
	pcall(button.SetDisabledTexture, button, "")

	-- Highlight blanked too, for the same reason as Normal/Pushed above: a
	-- highlight slot still carrying the arrow would draw a full-button-sized
	-- copy on hover, right through a scaled-down icon. Real ElvUI's own
	-- `S:HandleNextPrevButton` nils this slot as well and gives these
	-- buttons no hover tint at all (only a 1px OnMouseDown nudge), so this
	-- matches the reference -- but it IS a deliberate loss of hover
	-- feedback compared to the previous pass. If it's wanted back, the
	-- right shape is an OnEnter/OnLeave `SetVertexColor` on `elvIcon` (our
	-- OWN texture), never a native slot.
	pcall(button.SetHighlightTexture, button, "")
	local okHighlight, highlightTexture = pcall(button.GetHighlightTexture, button)
	if okHighlight and highlightTexture then
		pcall(highlightTexture.SetTexture, highlightTexture, nil)
		pcall(highlightTexture.Hide, highlightTexture)
		highlightTexture.Show = E.noop
	end
end

-- 3D model rotate buttons (`CharacterModelFrameRotateLeftButton`/
-- `RightButton`, `PetModelFrameRotateLeftButton`/`RightButton`,
-- `PetStableModelRotateLeftButton`/`RightButton` -- all the same 35x35
-- Normal/Pushed/Highlight-only shape, no DisabledTexture at all). HOISTED
-- from Character.lua once PetStable.lua became a second consumer of the
-- identical recipe.
--
-- The native rotate-arrow GLYPH stays (a curved rotation icon, not a
-- generic triangle), just re-cropped/zoomed in place and given a small
-- bordered background -- NOT swapped for one of this project's own
-- `SQUARE_BUTTON_TEXCOORDS` icons (a LEFT/RIGHT triangle would be the wrong
-- SHAPE, not just the wrong size). Matches real ElvUI's own
-- `S:HandleRotateButton` closely: re-crops the EXISTING native
-- NormalTexture/PushedTexture in place, isolating just the arrow glyph
-- from a circular background baked into the same native asset.
-- `GetNormalTexture()`/`GetPushedTexture()`/`GetHighlightTexture()` are all
-- documented on this client (only `GetDisabledTexture` is confirmed
-- missing), so reaching them directly is safe -- unlike the scroll arrows'
-- DISABLED slot, these buttons are never disabled at all.
--
-- Real ElvUI's own crop is an 8-value `SetTexCoord` (4 UV corner pairs) --
-- ported verbatim first, and confirmed live to render as an identical,
-- garbled diagonal smear on both buttons regardless of which button. Real
-- ElvUI's own 8 values turned out to be a perfectly ordinary axis-aligned
-- box written in the 8-value form (UL=(0.3,0.29), LL=(0.3,0.65),
-- UR=(0.69,0.29), LR=(0.69,0.65) => minX=0.3, maxX=0.69, minY=0.29,
-- maxY=0.65), mathematically identical to the plain 4-value crop already
-- proven reliable everywhere else in this file. Switching to the
-- equivalent 4-value `SetTexCoord(0.3, 0.69, 0.29, 0.65)` fixed it --
-- confirming the 8-value `SetTexCoord` overload itself (never used
-- anywhere else in this project) is unreliable on this client, independent
-- of the actual crop coordinates.
function S:StyleModelRotateButton(btn)
	if not btn then return end

	if ElvUI.Util and ElvUI.Util.CreateButtonBorder then
		ElvUI.Util.CreateButtonBorder(btn)
	end
	pcall(btn.SetWidth, btn, 21)
	pcall(btn.SetHeight, btn, 21)

	local okNormal, normalTexture = pcall(btn.GetNormalTexture, btn)
	if okNormal and normalTexture then
		pcall(normalTexture.SetTexCoord, normalTexture, 0.3, 0.69, 0.29, 0.65)
		pcall(normalTexture.ClearAllPoints, normalTexture)
		pcall(normalTexture.SetPoint, normalTexture, "TOPLEFT", btn, "TOPLEFT", 2, -2)
		pcall(normalTexture.SetPoint, normalTexture, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
	end

	local okPushed, pushedTexture = pcall(btn.GetPushedTexture, btn)
	if okPushed and pushedTexture then
		pcall(pushedTexture.SetTexCoord, pushedTexture, 0.3, 0.69, 0.29, 0.65)
		if okNormal and normalTexture then
			pcall(pushedTexture.SetAllPoints, pushedTexture, normalTexture)
		end
	end

	local okHighlight, highlightTexture = pcall(btn.GetHighlightTexture, btn)
	if okHighlight and highlightTexture then
		pcall(highlightTexture.SetTexture, highlightTexture, 1, 1, 1, 0.3)
		if okNormal and normalTexture then
			pcall(highlightTexture.SetAllPoints, highlightTexture, normalTexture)
		end
	end
end

function S:StyleModelRotateButtons(leftBtn, rightBtn)
	S:StyleModelRotateButton(leftBtn)
	S:StyleModelRotateButton(rightBtn)
end

-- Pet happiness icon (`PetPaperDollPetInfo` on the Character sheet's Pet
-- tab, `PetStablePetInfo` on the Stable Master window) -- a small Frame
-- holding one BACKGROUND Texture cut from
-- `Interface\PetPaperDollFrame\UI-PetHappiness`. Vanilla's own FrameXML
-- bakes in a single fixed crop and never updates it (`FrameXML/
-- PetStable.lua`'s own `PetStable_Update` never touches this region at
-- all) -- the live happiness-state icon is a feature real ElvUI itself
-- adds via `hooksecurefunc`, not a native behaviour being restyled.
-- HOISTED from Character.lua's own `StylePetDietIcon`/`UpdatePetDietIcon`
-- once `PetStable.lua` became a second consumer of the identical element.
--
-- Real ElvUI's own re-crop values, one rectangle per happiness level, cut
-- from the same sprite sheet as the XML's own default cell:
--   happiness 3 (happy)   -> 0.04, 0.15,  0.06, 0.30
--   happiness 2 (content) -> 0.22, 0.345, 0.06, 0.30
--   happiness 1 (unhappy) -> 0.41, 0.53,  0.06, 0.30
-- Not applied via `SetTexCoord` on the EXISTING native region the way real
-- ElvUI does -- this project has repeatedly found that not to apply on
-- this client for a plain `GetRegions()`-reachable region (the
-- resistance-icon saga). Used instead: `Hide()`+noop the native region,
-- CREATE a new Texture with the same asset path and the ElvUI crop --
-- identical to `StyleResistFrame`'s own recipe.
S.PET_HAPPINESS_TEXCOORDS = {
	{ 0.41, 0.53,  0.06, 0.30 },  -- 1, unhappy
	{ 0.22, 0.345, 0.06, 0.30 },  -- 2, content
	{ 0.04, 0.15,  0.06, 0.30 },  -- 3, happy
}

local function UpdatePetHappinessIcon(frame)
	if not frame or not frame.elvIcon then return end

	-- Warlock/other non-hunter pets have no happiness at all -- real ElvUI
	-- bails out entirely there and leaves whatever crop is currently up.
	-- Kept: the XML's own default is the happy cell, which is what a
	-- non-hunter pet shows natively too, so falling back to index 3
	-- matches native behavior instead of blanking the icon.
	local okHappy, happiness = pcall(GetPetHappiness)
	local coords = (okHappy and S.PET_HAPPINESS_TEXCOORDS[happiness]) or S.PET_HAPPINESS_TEXCOORDS[3]
	pcall(frame.elvIcon.SetTexCoord, frame.elvIcon, coords[1], coords[2], coords[3], coords[4])
end

-- One shared list + one shared timer for every registered happiness icon
-- (both windows' own, once both are skinned), matching this project's
-- standing "one poll, not one per window" preference.
local happinessPollFrames = {}
local happinessPollStarted = false

-- `levelRefFrame` is the model viewport this icon sits beside (e.g.
-- `PetModelFrame`/`PetStableModel`) -- matches real ElvUI's own explicit
-- level (model frame + 2) so the icon can't end up behind it. Frame level
-- is set BEFORE `CreateButtonBorder`, since that helper derives its own 3
-- layers from whatever level the frame has at call time.
function S:StylePetHappinessIcon(frame, levelRefFrame)
	if not frame then return end

	if not frame.elvIcon then
		if levelRefFrame then
			local okLevel, level = pcall(levelRefFrame.GetFrameLevel, levelRefFrame)
			if okLevel and tonumber(level) then
				pcall(frame.SetFrameLevel, frame, level + 2)
			end
		end

		local ok, regions = pcall(function() return { frame:GetRegions() } end)
		if ok and type(regions) == "table" then
			local i
			for i = 1, table.getn(regions) do
				local region = regions[i]
				local okType, rType = pcall(region.GetObjectType, region)
				if okType and rType == "Texture" then
					pcall(region.Hide, region)
					region.Show = E.noop
				end
			end
		end

		pcall(frame.SetWidth, frame, 24)
		pcall(frame.SetHeight, frame, 24)

		local okIcon, icon = pcall(frame.CreateTexture, frame, nil, "ARTWORK")
		if okIcon and icon then
			pcall(icon.SetTexture, icon, "Interface\\PetPaperDollFrame\\UI-PetHappiness")
			pcall(icon.SetPoint, icon, "TOPLEFT", frame, "TOPLEFT", 3, -3)
			pcall(icon.SetPoint, icon, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
			frame.elvIcon = icon
		end

		if ElvUI.Util and ElvUI.Util.CreateButtonBorder then
			ElvUI.Util.CreateButtonBorder(frame)
		end

		table.insert(happinessPollFrames, frame)
	end

	UpdatePetHappinessIcon(frame)

	-- Happiness can change while the panel is open (feeding the pet).
	-- Real ElvUI keeps it in sync via `RegisterEvent("UNIT_HAPPINESS")` +
	-- `SetScript("OnEvent", ...)`; this project's own established
	-- preference is a shared repeating timer over trusting event/hook
	-- delivery on this client. Gated on `IsVisible()` (true only while the
	-- icon's own window is actually shown), so it costs one check per
	-- registered icon per tick the rest of the time -- generic across
	-- both windows' own icons, unlike checking one hardcoded window name.
	if not happinessPollStarted then
		happinessPollStarted = true
		E:ScheduleRepeatingTimer(function()
			local i
			for i = 1, table.getn(happinessPollFrames) do
				local f = happinessPollFrames[i]
				local okShown, shown = pcall(f.IsVisible, f)
				if f.elvIcon and okShown and shown then
					UpdatePetHappinessIcon(f)
				end
			end
		end, 0.5)
	end
end

-- A WRAP (call the real `FauxScrollFrame_Update`, re-asserting a no-op
-- `Enable`/`Disable` override on the up/down buttons immediately before
-- calling through) STILL breaks the disabled-state icon even wrapping the
-- exact function that calls `:Disable()` -- don't try to
-- override/intercept what `Disable()`/`Enable()` DO (every such attempt
-- has failed); instead, for OUR OWN buttons, never CALL them at all. A
-- full reimplementation, not a wrap, is the only way to skip a few
-- specific lines in the middle of someone else's function body.
--
-- Ported near-verbatim from real 1.12.1's own `FauxScrollFrame_Update`
-- (source/wow-ui-source/FrameXML/UIPanelTemplates.lua:160-226) -- this
-- REPLACES the global function outright (affects every OTHER addon/
-- native list that also calls it, not just this project's own frames --
-- a real, acknowledged tradeoff, but functionally IDENTICAL to the
-- original for everything except the one skip-condition below, which is
-- itself scoped to only this project's own reskinned scrollbars via
-- `S.protectedFauxScrollBars`). The ONLY
-- change from the original: the "Arrow button handling" block is
-- skipped entirely (not overridden, not intercepted -- simply never
-- reached) for a registered frame.
S.protectedFauxScrollBars = S.protectedFauxScrollBars or {}

local function ReplaceFauxScrollFrameUpdate()
	if S.fauxScrollFrameUpdateReplaced then return end
	if type(_G.FauxScrollFrame_Update) ~= "function" then return end
	S.fauxScrollFrameUpdateReplaced = true

	_G.FauxScrollFrame_Update = function(frame, numItems, numToDisplay, valueStep, button, smallWidth, bigWidth, highlightFrame, smallHighlightWidth, bigHighlightWidth)
		local frameName = frame:GetName()
		local scrollBar = _G[frameName.."ScrollBar"]
		local showScrollBar
		if numItems > numToDisplay then
			frame:Show()
			showScrollBar = 1
		else
			scrollBar:SetValue(0)
			frame:Hide()
		end
		if frame:IsVisible() then
			local scrollChildFrame = _G[frameName.."ScrollChildFrame"]
			local scrollUpButton = _G[frameName.."ScrollBarScrollUpButton"]
			local scrollDownButton = _G[frameName.."ScrollBarScrollDownButton"]
			local scrollFrameHeight = 0
			local scrollChildHeight = 0

			if numItems > 0 then
				scrollFrameHeight = (numItems - numToDisplay) * valueStep
				scrollChildHeight = numItems * valueStep
				if scrollFrameHeight < 0 then
					scrollFrameHeight = 0
				end
				scrollChildFrame:Show()
			else
				scrollChildFrame:Hide()
			end
			scrollBar:SetMinMaxValues(0, scrollFrameHeight)
			scrollBar:SetValueStep(valueStep)
			scrollChildFrame:SetHeight(scrollChildHeight)

			-- Arrow button handling -- SKIPPED entirely (never called,
			-- not overridden) for this project's own reskinned
			-- scrollbars.
			if not S.protectedFauxScrollBars[frameName.."ScrollBar"] then
				if scrollBar:GetValue() == 0 then
					scrollUpButton:Disable()
				else
					scrollUpButton:Enable()
				end
				if (scrollBar:GetValue() - scrollFrameHeight) == 0 then
					scrollDownButton:Disable()
				else
					scrollDownButton:Enable()
				end
			end

			-- Shrink because scrollbar is shown
			if highlightFrame then
				highlightFrame:SetWidth(smallHighlightWidth)
			end
			if button then
				local i
				for i = 1, numToDisplay do
					_G[button..i]:SetWidth(smallWidth)
				end
			end
		else
			-- Widen because scrollbar is hidden
			if highlightFrame then
				highlightFrame:SetWidth(bigHighlightWidth)
			end
			if button then
				local i
				for i = 1, numToDisplay do
					_G[button..i]:SetWidth(bigWidth)
				end
			end
		end
		return showScrollBar
	end
end

-- Ported from real ElvUI's own `S:HandleScrollBar`
-- (source/ElvUI-vanilla/ElvUI/Modules/Skins/Skins.lua:103-151), adapted
-- to this project's own primitives (no E:Point/E:Size/
-- E:Height generic helpers here -- inlined SetBackdrop bgFile+edgeFile+
-- edgeSize=1 pairing and explicit SetPoint/SetWidth/SetHeight calls
-- instead, matching every other skin file in this project). Handles a
-- classic vanilla `UIPanelScrollBarTemplate`-shaped scrollbar: clears its
-- own BG/Track/Top/Bottom/Middle chrome textures, restyles the up/down
-- buttons via `S:StyleSquareIconButton`, adds a thin track backdrop
-- behind them, and (if the slider has a thumb texture) clears it and
-- adds a small backdrop-styled thumb replacement.
function S:HandleScrollBar(frame)
	if not frame then return end
	local okName, name = pcall(frame.GetName, frame)
	if not (okName and name) then return end

	local bg = _G[name.."BG"]
	if bg then pcall(bg.SetTexture, bg, nil) end
	local track = _G[name.."Track"]
	if track then pcall(track.SetTexture, track, nil) end
	local top = _G[name.."Top"]
	if top then pcall(top.SetTexture, top, nil) end
	local bottom = _G[name.."Bottom"]
	if bottom then pcall(bottom.SetTexture, bottom, nil) end
	local middle = _G[name.."Middle"]
	if middle then pcall(middle.SetTexture, middle, nil) end

	local upBtn = _G[name.."ScrollUpButton"]
	local downBtn = _G[name.."ScrollDownButton"]
	if upBtn and downBtn then
		S:StyleSquareIconButton(upBtn, "UP")
		S:StyleSquareIconButton(downBtn, "DOWN")

		-- Harmless to register even for a non-FauxScrollFrame scrollbar
		-- (e.g. SkillDetailScrollFrame, which uses UIPanelScrollFrameTemplate's
		-- own separate inline script, not FauxScrollFrame_Update at all) --
		-- the replaced function simply never runs for that frame.
		S.protectedFauxScrollBars[name] = true
		ReplaceFauxScrollFrameUpdate()

		-- Both arrows can show up DISABLED by default, not just the one
		-- that should legitimately start that way. Root cause: `ScrollFrame_OnLoad` (inherited from
		-- `UIPanelScrollFrameTemplate`, which `FauxScrollFrameTemplate`
		-- itself inherits) unconditionally `Disable()`s BOTH buttons the
		-- moment the scroll frame first loads
		-- (`source/wow-ui-source/FrameXML/UIPanelTemplates.lua:244-246`)
		-- -- normally `FauxScrollFrame_Update`'s own "Arrow button
		-- handling" block re-`Enable()`s whichever one shouldn't be
		-- disabled, the FIRST time real data populates the list. Since
		-- that whole block is now skipped for our own registered
		-- scrollbars (see `ReplaceFauxScrollFrameUpdate` above), nothing
		-- ever undoes `ScrollFrame_OnLoad`'s own initial Disable() call
		-- anymore. Fixed with a bounded resweep (matches this project's
		-- own established pattern for "native code does something once,
		-- possibly after our own styling code already ran" --
		-- ActionBars/PetBar/Minimap/MirrorTimers/Chat all use the same
		-- `(fn, 3, 10)` shape) forcing both buttons back to Enabled.
		pcall(upBtn.Enable, upBtn)
		pcall(downBtn.Enable, downBtn)
		ElvUI.Util.ScheduleLimitedSweep(function()
			pcall(upBtn.Enable, upBtn)
			pcall(downBtn.Enable, downBtn)
		end, 3, 10)

		if not frame.elvTrackBG then
			local okTrackBG, trackbg = pcall(CreateFrame, "Frame", nil, frame)
			if okTrackBG and trackbg then
				pcall(trackbg.SetPoint, trackbg, "TOPLEFT", upBtn, "BOTTOMLEFT", 0, -1)
				pcall(trackbg.SetPoint, trackbg, "BOTTOMRIGHT", downBtn, "TOPRIGHT", 0, 1)
				pcall(trackbg.SetBackdrop, trackbg, {
					bgFile = "Interface\\Buttons\\WHITE8x8",
					edgeFile = "Interface\\Buttons\\WHITE8x8",
					edgeSize = 1,
				})
				pcall(trackbg.SetBackdropColor, trackbg, S.TRACK_COLOR[1], S.TRACK_COLOR[2], S.TRACK_COLOR[3], S.TRACK_COLOR[4])
				pcall(trackbg.SetBackdropBorderColor, trackbg, S.BORDER_COLOR[1], S.BORDER_COLOR[2], S.BORDER_COLOR[3], S.BORDER_COLOR[4])
				frame.elvTrackBG = trackbg
			end
		end
	end

	local okThumb, thumb = pcall(frame.GetThumbTexture, frame)
	if okThumb and thumb then
		-- `SetTexture(nil)` only, NEVER `Hide()`+noop, on the thumb: a
		-- THUMB is fundamentally different from every other texture this
		-- file Hide()s -- it's the actual widget the Slider's own native
		-- drag mechanics track, not a purely decorative or click-target
		-- texture. Hiding it breaks actual dragging (jumpy, can't drag to
		-- the extremes). Real ElvUI's OWN reference `S:HandleScrollBar`
		-- deliberately calls ONLY `SetTexture(nil)` on the thumb, matching
		-- that exactly here -- the gem-icon-at-the-extremes visual bug
		-- (still unresolved) needs a DIFFERENT fix that doesn't touch the
		-- thumb's own Show/Hide state at all.
		pcall(thumb.SetTexture, thumb, nil)
		if not frame.elvThumbBG then
			pcall(thumb.SetHeight, thumb, 24)
			local okThumbBG, thumbbg = pcall(CreateFrame, "Frame", nil, frame)
			if okThumbBG and thumbbg then
				pcall(thumbbg.SetPoint, thumbbg, "TOPLEFT", thumb, "TOPLEFT", 2, -3)
				pcall(thumbbg.SetPoint, thumbbg, "BOTTOMRIGHT", thumb, "BOTTOMRIGHT", -2, 3)
				pcall(thumbbg.SetBackdrop, thumbbg, {
					bgFile = "Interface\\Buttons\\WHITE8x8",
					edgeFile = "Interface\\Buttons\\WHITE8x8",
					edgeSize = 1,
				})
				pcall(thumbbg.SetBackdropColor, thumbbg, S.THUMB_COLOR[1], S.THUMB_COLOR[2], S.THUMB_COLOR[3], S.THUMB_COLOR[4])
				pcall(thumbbg.SetBackdropBorderColor, thumbbg, S.BORDER_COLOR[1], S.BORDER_COLOR[2], S.BORDER_COLOR[3], S.BORDER_COLOR[4])
				if frame.elvTrackBG then
					local okLevel, level = pcall(frame.elvTrackBG.GetFrameLevel, frame.elvTrackBG)
					if okLevel then pcall(thumbbg.SetFrameLevel, thumbbg, level + 1) end
				end
				frame.elvThumbBG = thumbbg
			end
		end
	end
end

-- Horizontal `OptionsSliderTemplate`-style slider (real 1.12.1
-- `SoundOptionsFrameSlider1-4`, and any other volume/generic slider built
-- from the same template): a native-`<Backdrop>`-bearing Slider with a
-- `GetThumbTexture()` thumb, NO `ScrollUpButton`/`ScrollDownButton`
-- children -- structurally distinct from `S:HandleScrollBar`'s `*ScrollBar`
-- sliders, detected the same template-fixed way (never by name: only the
-- FrameXML is used to recognise the TEMPLATE, never a hardcoded
-- variable/frame name, since a window's FrameXML can be customised on
-- the server and real vanilla's own naming isn't guaranteed to still
-- apply). `S:SkinChildren`'s old `Slider` branch only ever handled the
-- `*ScrollBar` case, so a plain volume slider (Sound Options'
-- Master/Sound/Music/Ambience + the Voice Chat box's own
-- Volume/Gain/Sensitivity) fell through untouched.
-- Drag-capture constants, lifted verbatim from LibConfig-1.0's own
-- `AttachThumbDrag` -- the one drag recipe this project has
-- live-confirmed on UA. UA ONLY: on a real Blizzard client an expanded
-- hit rect actively BREAKS the widget it is applied to.
local SLIDER_DRAG_CAPTURE_INSET = -4000
local SLIDER_DRAG_MAX_SECONDS = 60

-- Fallback granularity for the drag when the client won't say what the
-- slider's real step is -- see `SetValueFromCursor`'s own note. Derived
-- from the slider's OWN min/max, never a fixed value, so it stays correct
-- whatever range a slider happens to carry.
local SLIDER_FALLBACK_STEPS = 10

-- How far the groove-covering surface stops short of the slider's bottom
-- edge, so it can't clip the `Low`/`High` labels. Derived from the
-- template, not tuned by eye -- see the call site.
local SLIDER_TRACK_BOTTOM_INSET = 4

function S:StyleOptionsSlider(slider)
	if not slider then return end

	-- The native `<Backdrop>` bgFile+edgeFile IS the whole track -- exactly
	-- the "never SetBackdrop a native frame, draw a child surface instead"
	-- case. No separate holder frame needed the way `S:HandleScrollBar`'s
	-- vertical track (anchored between two sibling buttons, which this
	-- template doesn't have) does.
	--
	-- The groove is COVERED, not cleared: `SetBackdrop(nil)` doesn't clear
	-- a native backdrop here at all, and swapping in a replacement table
	-- does hide it but takes the slider's thumb with it (see
	-- `S:ClearNativeBackdrop`). A cover surface stays at the slider's OWN
	-- frame level, not one level up: on this client the slider's own
	-- "Low"/"High" FontStrings sit INSIDE the frame's rect (unlike real
	-- vanilla, where they hang below it), so a cover raised one level up
	-- (which would otherwise correctly render in front of the parent's
	-- art) eats the bottom half of both labels. At the slider's own level
	-- the FontStrings (parent art) win over the cover, and the groove
	-- itself is handled by the alpha-0 RECOLOR in `S:ClearNativeBackdrop`
	-- instead.
	--
	-- OUR OWN STRIP MUST NOT EAT THE DISABLED SIGNAL. A slider's handle can
	-- render in `ACCENT_COLOR_DISABLED` {.5,.5,.5} instead of `THUMB_COLOR`
	-- {.6,.6,.6} on legacy while showing correctly (accent gold) on UA --
	-- i.e. every slider on legacy reads as disabled. `ShowHandleState`
	-- reads the one signal vanilla itself uses for a disabled slider -- a
	-- HIDDEN thumb, `OptionsFrame_DisableSlider` calls `Thumb:Hide()` --
	-- while `S:StripTextures` two lines below hides every Texture region
	-- it walks and permanently noops its `Show`. The thumb is one of those
	-- regions. On legacy, where `Hide()`/`SetTexture(nil)` genuinely take
	-- effect, that flips the answer to "disabled" for every slider in the
	-- window; on UA it doesn't take, which is the only reason the handle
	-- reads correctly there. General rule: **before reading a property off
	-- a native widget, ask whether our own strip has already changed it.**
	--
	-- The repair is deliberately CONDITIONAL, not an unconditional re-show:
	-- it only undoes a state change the strip itself just made (shown before,
	-- hidden after). A slider the CLIENT disabled was already hidden before
	-- the strip ran, so it stays hidden and keeps reading as disabled -- and
	-- on UA, where the strip changes nothing here, this does nothing at all,
	-- so the live-accepted look on that client cannot regress. Restoring
	-- `Show` (the strip noops it) is what hands the live signal back: from
	-- here on the client's own `Hide()`/`Show()` on the thumb work again, so
	-- a slider that becomes disabled while the window is open still greys.
	-- The thumb is fetched once, here, and reused by the disabled-state check
	-- further down. Protecting it from the strip is NOT done here any more --
	-- it lives inside `S:StripTextures` itself, because the strip that hides
	-- it is the skin file's own window-level recursive one, which runs long
	-- before the sweep ever reaches this slider.
	local okThumb, thumb = pcall(slider.GetThumbTexture, slider)

	S:StripTextures(slider, false)

	-- THE TRACK COVERS THE NATIVE GROOVE -- it does not rely on the groove
	-- being gone. Ruled out: `SetBackdrop(nil)` doesn't clear a native
	-- backdrop here; a replacement backdrop TABLE hides it but kills the
	-- thumb and leaks onto every other native frame built from the same
	-- template; `DisableDrawLayer("BACKGROUND"/"BORDER")` (the current
	-- `S:ClearNativeBackdrop` mechanism, confirmed working on every OTHER
	-- native backdrop in the UI) is confirmed NOT working on a Slider's --
	-- consistent with the table swap also uniquely destroying its thumb,
	-- since a Slider's backdrop is special on this client in a second way
	-- too. So the groove is covered instead: OPAQUE fill, one frame level
	-- ABOVE the slider, this project's documented rule for winning over a
	-- parent's own art.
	--
	-- ⚠ A full-footprint opaque cover eats the bottom half of the
	-- `Low`/`High` labels: `Dump` reports `regions: tex=0 fontstrings=3`
	-- on a live slider (the labels are reachable), and they sit BELOW the
	-- track box rather than inside it. If they get clipped, the fix is not
	-- to shrink this surface by guesswork but to push the BOTTOM-anchored
	-- FontStrings down, which is what real ElvUI's own
	-- `S:HandleSliderFrame` does (source/ElvUI-vanilla/ElvUI/Modules/Skins/
	-- Skins.lua:434).
	-- UA ONLY, and for the same reason the drag below is: on the LEGACY
	-- client `S:ClearNativeBackdrop` still runs its alpha-0 recolor, that
	-- recolor does remove the groove there, and it leaks onto nothing --
	-- so legacy needs no cover at all. Raising an opaque surface over a
	-- slider that is already correct could only reintroduce the clipped
	-- `Low`/`High` labels on the one client where every slider currently
	-- works. Same rule as everywhere else in this file: never re-engineer
	-- the working client to fix the broken one.
	local coverGroove = ElvUI.Compat and ElvUI.Compat.isUA
	local track
	if coverGroove then
		-- THE 4px BOTTOM INSET IS NOT A GUESS. It comes straight out of the
		-- template:
		--   * `$parentLow`/`$parentHigh` anchor TOPLEFT/TOPRIGHT to the
		--     slider's BOTTOM corners at y **+3**, i.e. they poke exactly
		--     3px INTO the frame's own rect
		--     (source/wow-ui-source/FrameXML/OptionsFrameTemplates.xml:92-108)
		--     -- which is what this project's older "the labels sit inside
		--     the rect on this client" note was really seeing;
		--   * the groove that has to be covered is the backdrop's bgFile,
		--     and its `<BackgroundInsets>` are top/bottom **6**, so it only
		--     occupies the middle band of a 17px slider (ibid. :81-83).
		-- 4 therefore clears the labels with a pixel to spare while still
		-- covering the groove twice over. Only the bgFile needs covering at
		-- all: the edgeFile border DID go with `DisableDrawLayer("BORDER")`
		-- -- the live report was specifically about the rounded MIDDLES.
		track = S:CreateSurface(slider, S.TRACK_COLOR_OPAQUE, 0, 0, 0, SLIDER_TRACK_BOTTOM_INSET)
		if track then
			local okSliderLevel, sliderLevel = pcall(slider.GetFrameLevel, slider)
			if okSliderLevel and tonumber(sliderLevel) then
				pcall(track.SetFrameLevel, track, sliderLevel + 1)
			end
		end
	else
		track = S:CreateSurface(slider, S.TRACK_COLOR)
	end

	-- THE HANDLE IS NOT ANCHORED TO THE THUMB TEXTURE: measured, not
	-- theorized. `S.autoSkinDebug` reported, for all 7 sliders:
	--   size=128x17 thumb=yes thumbSize=12x32 bg=yes bgSize=8x13
	--   bgShown=true bgLevel=2 trackLevel=1
	-- i.e. the handle frame EXISTS, has exactly the right size, is shown,
	-- and sits one level above the track -- and still nothing renders. The
	-- only property that measurement can't see is WHERE it ended up, and
	-- there is a known reason for it to be nowhere: the handle was anchored
	-- to the thumb TEXTURE, and `S:StripTextures` (called two lines above)
	-- `Hide()`s every texture region it walks. Querying a hidden object is
	-- already on record as unreliable on this client (same class of issue
	-- as the CharacterFrame background-inset case), so a two-point anchor
	-- against one can resolve to a sane SIZE and a useless POSITION.
	--
	-- `S:HandleScrollBar` gets away with the same anchor because it never
	-- strips its scrollbar -- its thumb stays a shown (if blank) region.
	--
	-- So the handle is driven from the slider's own VALUE instead, and
	-- anchored to the SLIDER, which is a frame, is visible, and whose rect
	-- is not in question. That also makes the recipe independent of whether
	-- the client hands back a thumb texture at all.
	-- `okThumb`/`thumb` come from the pre-strip fetch above -- re-fetching
	-- here would be a second chance to get a different object on a client
	-- where a freshly queried reference can compare unequal to a stored one,
	-- and the two blocks must act on the same texture.
	if okThumb and thumb then
		-- Still cleared, and still `SetTexture(nil)` rather than `Hide()`:
		-- a hidden thumb breaks this client's native drag tracking
		-- (live-confirmed regression on the scrollbar). Narrowed to 12 on
		-- the along-travel axis so the grab area matches the visible handle.
		pcall(thumb.SetTexture, thumb, nil)
		pcall(thumb.SetWidth, thumb, 12)
	end

	-- THE HANDLE IS A TEXTURE ON THE TRACK, not a child frame.
	-- Four builds in a row produced a handle FRAME that measured perfectly
	-- (`bg=yes bgSize=8x13 bgLevel=2 bgShown=true`) and drew nothing, across
	-- three different anchor schemes -- so the frame is not the thing to fix
	-- for a fifth time. This project's rule for that situation is to stop
	-- varying the parameter and change the MECHANISM to one already proven
	-- on this client, and there are two such primitives right here:
	--   * `track` (an `S:CreateSurface` frame) demonstrably renders -- it is
	--     the groove the user can see in every screenshot;
	--   * textures on OUR OWN frames demonstrably render -- the dropdown
	--     arrow glyph and the checkbox mark are both exactly that.
	-- So the handle becomes a texture on the track: both halves proven,
	-- nothing new assumed. It also drops a frame, a frame level and a
	-- backdrop from the recipe.
	local HANDLE_WIDTH = 8
	if track and not slider.elvThumbTex then
		local okTex, handleTex = pcall(track.CreateTexture, track, nil, "OVERLAY")
		if okTex and handleTex then
			pcall(handleTex.SetTexture, handleTex, "Interface\\Buttons\\WHITE8x8")
			-- ACCENT, not `THUMB_COLOR`: the grey reads as plain white on
			-- the dark track. `THUMB_COLOR` stays
			-- what it is -- it is the SCROLLBAR thumb's colour and those
			-- are already live-accepted; this handle is a different control
			-- and the one the user actually looks for on the bar.
			pcall(handleTex.SetVertexColor, handleTex, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3], 1)
			pcall(handleTex.SetWidth, handleTex, HANDLE_WIDTH)
			local okSH, sliderHeight = pcall(slider.GetHeight, slider)
			sliderHeight = (okSH and tonumber(sliderHeight)) or 17
			if sliderHeight > 20 then sliderHeight = 20 end
			pcall(handleTex.SetHeight, handleTex, sliderHeight - 4)
			-- Anchored once, unconditionally, at the left end. The value
			-- maths below only ever MOVES it: an earlier build put the only
			-- `SetPoint` inside the positioning function, which returns
			-- early if any getter fails -- and an unanchored object renders
			-- nothing, silently.
			pcall(handleTex.SetPoint, handleTex, "LEFT", track, "LEFT", 0, 0)
			slider.elvThumbTex = handleTex

			-- Mirrors the DISABLED state onto the handle, using the same
			-- hidden-thumb signal `SetValueFromCursor` refuses drags on --
			-- an accent-gold handle on a slider that cannot be moved would
			-- read as a live control despite being disabled. Vanilla hides its
			-- thumb outright here (`OptionsFrame_DisableSlider`); greying is
			-- kept instead so the VALUE stays readable, matching how this
			-- project already greys disabled tabs (`S.ACCENT_COLOR_DISABLED`).
			-- Only recolors on an actual change: `PositionHandle` runs 20x a
			-- second.
			local handleGreyed = nil
			local function ShowHandleState()
				-- `_G[name.."Thumb"]` was tried as a second source here and
				-- MEASURED to be the same object as the getter's on this client
				-- ("named=nil" in the live debug line), so the getter is the
				-- whole story and that branch is gone.
				if not thumb then return end
				local okThumbShown, thumbShown = pcall(thumb.IsShown, thumb)
				if not okThumbShown then return end
				local greyed = not thumbShown
				if greyed == handleGreyed then return end
				handleGreyed = greyed
				local color = greyed and S.ACCENT_COLOR_DISABLED or S.ACCENT_COLOR
				pcall(handleTex.SetVertexColor, handleTex, color[1], color[2], color[3], 1)
			end

			local function PositionHandle()
				ShowHandleState()
				local okRange, minValue, maxValue = pcall(slider.GetMinMaxValues, slider)
				local okValue, value = pcall(slider.GetValue, slider)
				local okWidth, width = pcall(slider.GetWidth, slider)
				minValue, maxValue = tonumber(minValue), tonumber(maxValue)
				value, width = tonumber(value), tonumber(width)
				if not (okRange and okValue and okWidth and minValue and maxValue and value and width) then return end
				local span = maxValue - minValue
				if span <= 0 or width <= HANDLE_WIDTH then return end
				local fraction = (value - minValue) / span
				if fraction < 0 then fraction = 0 end
				if fraction > 1 then fraction = 1 end
				pcall(handleTex.ClearAllPoints, handleTex)
				pcall(handleTex.SetPoint, handleTex, "LEFT", track, "LEFT",
					fraction * (width - HANDLE_WIDTH), 0)
			end

			PositionHandle()

			-- === DRAGGING IT -- UA ONLY ==================
			-- On the REAL 1.12.1 client these sliders are FUNCTIONALLY
			-- FINE as skinned (only the handle's colour differs); on UA
			-- some can't be dragged at all -- the standing UA widget gap:
			-- native `Slider` widget unreliable/broken, use a drag-thumb
			-- Button instead. Everything below is therefore gated on
			-- `Compat.isUA`: the legacy client keeps its own working
			-- native drag, untouched, and never grows a mouse-enabled
			-- overlay it doesn't need.
			--
			-- ⚠ NOT THE CAUSE: `S:StripTextures` (top of this function)
			-- `Hide()`ing the slider's thumb region -- `$parentThumb` is a
			-- declared `<ThumbTexture>`, source/wow-ui-source/FrameXML/
			-- OptionsFrameTemplates.xml:127 -- even though a hidden thumb
			-- breaking native drag tracking is already on record here (the
			-- scrollbar regression noted above). The SAME strip runs on the
			-- legacy client, where dragging works. So the hidden thumb is
			-- not what breaks it, and un-hiding it (which would hand back
			-- the metal thumb art) would not fix anything.
			--
			-- Recipe: LibConfig-1.0's `AttachThumbDrag`, in miniature --
			-- press starts it, an OnUpdate follows the cursor, and the
			-- expanded hit rect + `GetButtonState()` polling is what makes
			-- the RELEASE arrive on this client at all.
			local isUA = ElvUI.Compat and ElvUI.Compat.isUA
			local grab, dragging, armed, dragStartedAt, restoreLevel = nil, false, false, nil, nil

			-- Cursor X in the same coordinate space as `GetLeft()` --
			-- screen pixels over the frame's own effective scale.
			local function CursorX()
				if type(GetCursorPosition) ~= "function" then return nil end
				local okCursor, cx = pcall(GetCursorPosition)
				local okScale, scale = pcall(track.GetEffectiveScale, track)
				cx, scale = tonumber(cx), tonumber(scale)
				if not (okCursor and okScale and cx and scale) or scale <= 0 then return nil end
				return cx / scale
			end

			local function SetValueFromCursor()
				-- A disabled slider must stay unmovable -- the overlay
				-- bypasses the widget's own "Disable skips mouse hits",
				-- which would otherwise let a disabled slider (e.g. Voice
				-- Activity Sensitivity while auto-detect is on) still be
				-- dragged.
				--
				-- TWO signals, because the obvious one is unavailable here:
				--  1. `IsEnabled()` -- UA's Slider has no such method at all
				--     (source/UnrealAzeroth_LuaAPI/en/widgets/Slider.md), so
				--     only an EXPLICIT disabled answer counts; a getter that
				--     doesn't answer must not freeze every slider.
				--  2. **A HIDDEN THUMB**, which is what actually catches it
				--     on this window. Vanilla's own helper hides it:
				--     `OptionsFrame_DisableSlider` does
				--     `getglobal(name.."Thumb"):Hide()` plus greying the
				--     three labels (FrameXML/OptionsFrame.lua:481). The live
				--     Voice Chat section demonstrably follows that same
				--     helper's pattern -- its labels ARE greyed in the
				--     screenshots -- so the thumb's shown state is a real
				--     state signal here, not an inference about ours.
				--     Safe to read: this function only ever CLEARS the
				--     thumb's texture (`SetTexture(nil)`), never hides it,
				--     and `S:StripTextures` can't touch it either (measured:
				--     a slider reports `regions: tex=0`, the thumb is not
				--     enumerable). So a hidden thumb is always the client's
				--     doing.
				local okEnabled, enabled = pcall(slider.IsEnabled, slider)
				if okEnabled and (enabled == 0 or enabled == false) then return end
				if thumb then
					local okThumbShown, thumbShown = pcall(thumb.IsShown, thumb)
					if okThumbShown and not thumbShown then return end
				end

				local cx = CursorX()
				local okLeft, left = pcall(track.GetLeft, track)
				local okWidth, width = pcall(track.GetWidth, track)
				local okRange, minValue, maxValue = pcall(slider.GetMinMaxValues, slider)
				left, width = tonumber(left), tonumber(width)
				minValue, maxValue = tonumber(minValue), tonumber(maxValue)
				if not (cx and okLeft and okWidth and okRange and left and width and minValue and maxValue) then return end
				local usable = width - HANDLE_WIDTH
				local span = maxValue - minValue
				if usable <= 0 or span <= 0 then return end

				-- The handle's CENTRE follows the cursor, so a click
				-- anywhere on the track jumps there -- what the native
				-- control does too.
				local offset = cx - left - HANDLE_WIDTH / 2
				if offset < 0 then offset = 0 end
				if offset > usable then offset = usable end

				local value = minValue + (offset / usable) * span

				-- STEP SNAPPING. The native drag snaps to `SetValueStep`, so the legacy
				-- client -- still on its own drag -- DOES step, and this
				-- overlay has to match it or the two clients drift apart.
				-- `SetValue` does not snap by itself.
				--
				-- Ask first, guess second:
				--  * `GetValueStep()` if the client has it. MEASURED absent
				--    on UA (`Dump` prints `step=ERR`), which is what its own
				--    docs claim -- asked anyway, because this project's rule
				--    is to verify those docs rather than trust them, and one
				--    pcall is the whole cost. Keep the call: a client update
				--    that adds the getter then fixes this for free.
				--  * otherwise `SLIDER_FALLBACK_STEPS` divisions of the
				--    slider's OWN range. Not a hardcoded 0.1 -- for the
				--    0..1 volume sliders it happens to land exactly on the
				--    native 0.1 (measured: a native click snapped to
				--    `0.1000`), and for any other range it stays
				--    proportionate. The client DOES know the real step
				--    internally, it just won't hand it over; recovering it
				--    for real would mean harvesting every `SetValueStep`
				--    call in the UI, which is explicitly out of scope for
				--    now. If a slider ever turns out to need a
				--    finer step than a tenth, that is the moment to
				--    revisit -- not before.
				--
				-- `math.floor(x + 0.5)` rather than the `%` operator: `%`
				-- as an arithmetic op does not PARSE on Lua 5.0.3 and this
				-- file has to load on the legacy client too.
				local okStep, step = pcall(slider.GetValueStep, slider)
				step = okStep and tonumber(step)
				if not (step and step > 0) then
					step = span / SLIDER_FALLBACK_STEPS
				end
				if step > 0 then
					value = minValue + math.floor((value - minValue) / step + 0.5) * step
					if value < minValue then value = minValue end
					if value > maxValue then value = maxValue end
				end

				-- `SetValue` is what APPLIES the setting: changing a
				-- slider's value runs its own `OnValueChanged`
				-- (source/UnrealAzeroth_LuaAPI/en/widgets/Slider.md, in so
				-- many words), which for this window is
				-- `SoundOptionsSlider_OnValueChanged` -> `SetCVar`. We
				-- never call that script by hand and never put a script ON
				-- the native slider.
				pcall(slider.SetValue, slider, value)
				PositionHandle()
			end

			local function StopDrag()
				if not dragging then return end
				dragging, armed = false, false
				if grab then
					pcall(grab.SetHitRectInsets, grab, 0, 0, 0, 0)
					if restoreLevel then
						pcall(grab.SetFrameLevel, grab, restoreLevel)
						restoreLevel = nil
					end
				end
				PositionHandle()
			end

			local function StartDrag()
				if dragging or not grab then return end
				dragging, armed = true, false
				dragStartedAt = (type(GetTime) == "function" and GetTime()) or nil
				-- Without this the button un-pushes the instant the cursor
				-- leaves its 17px-tall footprint, and every drag would end
				-- on its first tick.
				pcall(grab.SetHitRectInsets, grab, SLIDER_DRAG_CAPTURE_INSET, SLIDER_DRAG_CAPTURE_INSET,
					SLIDER_DRAG_CAPTURE_INSET, SLIDER_DRAG_CAPTURE_INSET)
				local okLevel, level = pcall(grab.GetFrameLevel, grab)
				if okLevel and tonumber(level) then
					restoreLevel = level
					pcall(grab.SetFrameLevel, grab, level + 50)
				end
			end

			if isUA then
				local okGrab, grabButton = pcall(CreateFrame, "Button", nil, track)
				if okGrab and grabButton then
					grab = grabButton
					slider.elvSliderGrab = grabButton
					pcall(grab.SetAllPoints, grab, track)
					pcall(grab.EnableMouse, grab, true)
					pcall(grab.SetScript, grab, "OnMouseDown", function()
						-- OnMouseDown reports the button in `arg1` on a
						-- client that passes it; "no idea" is treated as
						-- left so this still works if it doesn't. Same
						-- defensive shape as LibDBIcon-1.0's `pressDrag`.
						if type(arg1) == "string" and arg1 ~= "LeftButton" then return end
						SetValueFromCursor()
						StartDrag()
					end)
					pcall(grab.SetScript, grab, "OnMouseUp", StopDrag)
					-- Hidden mid-drag (window closed) must never leave a
					-- screen-wide hit rect behind.
					pcall(grab.SetScript, grab, "OnHide", StopDrag)
					-- The overlay swallows the slider's own hover, so its
					-- tooltip is re-served here instead of being lost --
					-- this window sets `slider.tooltipText` on every slider
					-- (SoundOptionsFrame.lua's `SoundOptionsFrame_Load`),
					-- and the template's own OnEnter is exactly this.
					pcall(grab.SetScript, grab, "OnEnter", function()
						if not (slider.tooltipText and GameTooltip) then return end
						pcall(GameTooltip.SetOwner, GameTooltip, slider, "ANCHOR_RIGHT")
						pcall(GameTooltip.SetText, GameTooltip, slider.tooltipText, nil, nil, nil, nil, 1)
						if slider.tooltipRequirement then
							pcall(GameTooltip.AddLine, GameTooltip, slider.tooltipRequirement, "", 1, 1, 1)
						end
						pcall(GameTooltip.Show, GameTooltip)
					end)
					pcall(grab.SetScript, grab, "OnLeave", function()
						if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
					end)
				end
			end

			-- ONE OnUpdate for both jobs -- it drives the drag while one is
			-- running and otherwise just keeps the handle on the value.
			-- Polled on the TRACK (our own frame), never on the native
			-- slider -- a script on that is how a working control gets
			-- broken. 20/sec is imperceptible for the idle case; the drag
			-- case is deliberately NOT throttled.
			pcall(track.SetScript, track, "OnUpdate", function()
				if dragging and grab then
					SetValueFromCursor()
					-- Second opinion only, and only meaningful while the
					-- expanded hit rect keeps the cursor "on" the button.
					-- `armed` waits for an actual PUSHED reading first,
					-- because this client returns "UNKNOWN" both for a
					-- released button AND for a plain hover (LibDBIcon-1.0's
					-- own measurement) -- an unconditional poll would end
					-- every drag on its first tick.
					local okState, state = pcall(grab.GetButtonState, grab)
					if okState and state == "PUSHED" then
						armed = true
					elseif okState and armed then
						StopDrag()
						return
					end
					if dragStartedAt and type(GetTime) == "function" then
						local now = GetTime()
						if tonumber(now) and now - dragStartedAt > SLIDER_DRAG_MAX_SECONDS then
							StopDrag()
						end
					end
					return
				end

				local now = GetTime()
				if track.elvNextMove and now < track.elvNextMove then return end
				track.elvNextMove = now + 0.05
				PositionHandle()
			end)
		end
	end

	-- COLLECTED, not printed here: the sweep's own
	-- summary block is printed after every slider has been styled, so a
	-- print from inside this function lands ABOVE it -- and the chat frame
	-- on this setup only keeps the last handful of lines, which is exactly
	-- how the first run of this measurement came back unreadable. The sweep
	-- flushes `S.sliderDebugLines` LAST, so these end up at the bottom.
	if S.autoSkinDebug then
		S.sliderDebugLines = S.sliderDebugLines or {}
		local okName, sliderName = pcall(slider.GetName, slider)
		local okW, sw = pcall(slider.GetWidth, slider)
		local okH, sh = pcall(slider.GetHeight, slider)
		local okValue, value = pcall(slider.GetValue, slider)

		-- POSITIONS this round, not just sizes. The previous run proved the
		-- handle exists, is the right size, is shown and is above the track,
		-- which leaves exactly one unmeasured property: where it actually
		-- sits. `GetLeft`/`GetBottom` are screen coordinates, so comparing
		-- the handle's against the slider's own answers it outright -- a
		-- handle inside the slider's span is a rendering problem, one at 0,0
		-- or far away is the anchor problem this rewrite assumes.
		local function Corner(object)
			if not object then return "nil" end
			local okL, left = pcall(object.GetLeft, object)
			local okB, bottom = pcall(object.GetBottom, object)
			return string.format("%d,%d", (okL and tonumber(left)) or -9999, (okB and tonumber(bottom)) or -9999)
		end

		local bg = slider.elvThumbTex
		local bgw, bgh, bgLevel, bgShown, bgVisible, bgAlpha = 0, 0, -1, false, false, -1
		if bg then
			local okBW, v = pcall(bg.GetWidth, bg); bgw = (okBW and tonumber(v)) or 0
			local okBH, v2 = pcall(bg.GetHeight, bg); bgh = (okBH and tonumber(v2)) or 0
			local okBS, v4 = pcall(bg.IsShown, bg); bgShown = (okBS and v4) and true or false
			local okBV, v5 = pcall(bg.IsVisible, bg); bgVisible = (okBV and v5) and true or false
			local okBA, v6 = pcall(bg.GetAlpha, bg); bgAlpha = (okBA and tonumber(v6)) or -1
		end
		local trackLevel = -1
		if track then
			local okTL, v = pcall(track.GetFrameLevel, track); trackLevel = (okTL and tonumber(v)) or -1
			-- The track is now the handle's PARENT, so its own visibility is
			-- the first thing that would explain a missing handle.
			local okTV, tv = pcall(track.IsVisible, track)
			if not (okTV and tv) then trackLevel = -99 end
		end

		-- The range comes along too: if `GetMinMaxValues` is the
		-- getter that doesn't answer here, the handle can still render (it
		-- has a fixed anchor now) but will never MOVE -- and only this line
		-- can tell those two apart.
		local okRange, minValue, maxValue = pcall(slider.GetMinMaxValues, slider)
		local rangeText = okRange and (tostring(tonumber(minValue)).."-"..tostring(tonumber(maxValue))) or "ERR"

		-- `thumb=` is the disabled signal the handle greys off: `true` means
		-- the slider reads as enabled (gold handle), `false` as disabled
		-- (grey). It is what turns "legacy still shows the slider as grey"
		-- from a guess into a measurement, and it stays because it is one
		-- word and it is the only externally invisible input to the handle's
		-- colour.
		local okThumbShown, thumbNowShown = pcall(thumb and thumb.IsShown or E.noop, thumb)
		table.insert(S.sliderDebugLines, string.format("  slider %s: %dx%d val=%s range=%s at=%s | handle %dx%d lvl=%d shown=%s vis=%s a=%.1f at=%s track=%d | thumb=%s",
			tostring(okName and sliderName or "<unnamed>"),
			(okW and tonumber(sw)) or 0, (okH and tonumber(sh)) or 0,
			tostring((okValue and tonumber(value)) or "?"), rangeText, Corner(slider),
			bgw, bgh, bgLevel, tostring(bgShown), tostring(bgVisible), bgAlpha, Corner(bg), trackLevel,
			tostring(thumb and okThumbShown and thumbNowShown or false)))
	end
end

-- A BUTTON whose Normal/Highlight textures are pure decoration, not
-- content or state -- `S:StripTextures` cannot reach either of them,
-- because it walks `GetRegions()` and a Button's Normal/Highlight
-- textures are NOT regions. That is not an oversight in the strip: for
-- every icon-carrying slot in this project the NormalTexture IS the
-- content, which is exactly why `S:StripTextures` never descends into a
-- Button at all.
--
-- The live case this exists for is the vanilla "status bar border" shape:
-- a bar's `$parentBorder` is not a Texture region but a separate 281x32
-- Button carrying `UI-Character-Skills-BarBorder` in its NormalTexture
-- (`SkillFrame.xml`'s `SkillStatusBarTemplate`, and `TradeSkillRankFrame`
-- shares the identical art). Its native art is NARROWER than the bar
-- after an ElvUI resize, so leaving it drawn makes the bar read as
-- left-aligned and off-centre rather than as the flat ElvUI meter it
-- should be -- the symptom that found this.
--
-- `S:StripTextures(button, false)` on such a button looks like it should
-- handle it and does nothing at all; call this instead (or as well, for
-- the button's own plain regions).
function S:StripButtonArt(button)
	if not button then return end

	local getters = { "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetDisabledTexture" }
	local i
	for i = 1, table.getn(getters) do
		local getter = button[getters[i]]
		if getter then
			local ok, texture = pcall(getter, button)
			if ok and texture then
				pcall(texture.SetTexture, texture, nil)
				pcall(texture.Hide, texture)
				texture.Show = E.noop
			end
		end
	end
	S:Kill(button)
end

-- Generic `StatusBar` -- a level/progress meter that isn't any window's own
-- named bar, such as Sound Options' microphone level meter next to the
-- "Test Microphone" button, which the sweep had NO branch for at all --
-- so the recursive strip blanked its art on the way in and nothing ever
-- drew it again.
--
-- Same shape as the per-window bar recipes this project already has live
-- (`StyleSkillRankBar`, `StylePetExpBar` -- Blizzard/Character.lua): flat
-- `normTex` fill on a recessed dark well. Those stay where they are; they
-- do window-specific work (killing named border/background siblings) that
-- can't be done without knowing the names.
--
-- NO `elvStyled` latch, deliberately -- same reasoning as
-- `StyleDropDownBackdrop`: every window re-runs `S:StripTextures` on each
-- OnShow, so a one-shot styling would render on the first open and be
-- undone on the second. Everything here is idempotent and cheap.
function S:StyleStatusBar(bar)
	if not bar then return end

	S:ClearNativeBackdrop(bar)
	pcall(bar.SetStatusBarTexture, bar, (E.media and E.media.normTex) or "Interface\\Buttons\\WHITE8x8")

	-- UN-KILL the fill. `S:StripTextures` blanket-`Hide()`s every Texture
	-- region it walks AND permanently noops its `Show` -- correct for
	-- decorative chrome, fatal for the one region that IS this widget's
	-- content. Clearing the shadowing field restores the real method
	-- underneath rather than leaving a permanently invisible bar. Only ever
	-- undoes THIS module's own noop, never a native one.
	local okTex, tex = pcall(bar.GetStatusBarTexture, bar)
	if okTex and tex then
		if tex.Show == E.noop then tex.Show = nil end
		pcall(tex.Show, tex)
	end

	-- The well goes at the bar's OWN frame level, which puts it UNDER the
	-- bar's own fill region: measured on the slider track, where the native
	-- backdrop rendered on top of exactly such a same-level child surface.
	S:CreateSurface(bar, S.TRACK_COLOR)
end

-- Shared with Blizzard/Character.lua's own always-draggable header handle
-- for FriendsFrame (toggle-
-- open/close windows need this instead of E:CreateMover, which requires
-- entering /moveui's global unlock mode first -- wrong UX here). Same
-- low-level recipe proven working on UA multiple times (LibConfig-1.0's
-- own header drag handle, the range slider thumb, the color-picker
-- marker): a Button (not a plain Frame -- only a Button reliably delivers
-- OnDragStart on this client), SetMovable immediately before each drag, a
-- throwaway StartMoving/StopMovingOrSizing pair before the real
-- StartMoving. Spans the header strip from `frame`'s own left edge to
-- `closeButton`'s left edge (auto-excludes it regardless of its exact
-- size) at a fixed 24px height (shrunk from an initial 60px guess after
-- live-confirmed via `S:DumpMouseFocus()` that the taller handle was
-- swallowing clicks meant for controls below the header strip -- see
-- Character.lua's own original comment history if this needs revisiting).
-- No position persistence across sessions.
-- `onStop` (optional) runs after every drag ends -- for a window that has
-- to re-assert its own position later, such as Interface Options: the
-- legacy client's `SetupFullscreenScale` (a built-in, called from that
-- window's own OnShow) puts the frame back where it wants it, so the skin
-- has to remember where the user dragged it to and restore that on every
-- show.
function S:MakeDraggable(frame, closeButton, onStop)
	local handle = CreateFrame("Button", nil, frame)
	handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	if closeButton then
		handle:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", 0, 0)
	else
		handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	end
	handle:SetHeight(24)
	pcall(handle.EnableMouse, handle, true)
	pcall(handle.RegisterForDrag, handle, "LeftButton")

	-- Raised well above the frame's own header content -- without this,
	-- whatever native header element sits at a higher level intercepts the
	-- mouse first and the handle never receives OnMouseDown/OnDragStart.
	local okLevel, level = pcall(frame.GetFrameLevel, frame)
	pcall(handle.SetFrameLevel, handle, (okLevel and tonumber(level) or 1) + 50)

	local function StartDrag()
		if not pcall(frame.SetMovable, frame, true) then return end
		if pcall(frame.StartMoving, frame) then
			pcall(frame.StopMovingOrSizing, frame)
		end
		pcall(frame.StartMoving, frame)
	end
	local function StopDrag()
		pcall(frame.StopMovingOrSizing, frame)
		if onStop then pcall(onStop) end
	end

	handle:SetScript("OnMouseDown", StartDrag)
	handle:SetScript("OnDragStart", StartDrag)
	handle:SetScript("OnMouseUp", StopDrag)
	handle:SetScript("OnDragStop", StopDrag)

	return handle
end

-- CONFIRMED UA binding bug, not a per-frame fluke -- AceHook-3.0's own
-- `:HookScript` refuses certain otherwise-perfectly-valid frames with
-- "You can only hook a script on a frame object" -- first hit on
-- `HonorFrame` in Blizzard/Character.lua.
-- The exact mechanism was found already documented and independently
-- fixed by a completely different real library vendored in this project,
-- `Libraries/LibDBIcon-1.0/LibDBIcon-1.0.lua:441-447`, hitting the SAME
-- bug on `Minimap`: AceHook-3.0's own validation calls
-- `frame:HasScript(method)` before allowing the hook, and on THIS
-- client `:HasScript()` incorrectly returns `false` for some frames even
-- though `:GetScript()`/`:SetScript()` both work completely normally on
-- the exact same frame+script -- a genuine client-level binding bug in
-- `:HasScript()` itself, confirmed by two independent real libraries
-- hitting it on two unrelated frames (`Minimap`, `HonorFrame`), not
-- something fixable from addon Lua. This is exactly the kind of
-- "modifying/querying a pre-existing native object sometimes silently
-- misbehaves" pattern already established throughout this project, one
-- level deeper than usual (inside a VENDORED LIBRARY's own validation,
-- not this project's own code).
--
-- `S:TryHookScript` is a drop-in, safer alternative to a bare
-- `S:HookScript` call anywhere in this project: tries the normal,
-- preferred AceHook-3.0 path first (still the right default -- proven
-- reliable for the vast majority of frames), and ONLY for the specific
-- targets where that fails, falls back to a manual native `:SetScript`
-- chain that preserves whatever OnShow (or other script) the frame
-- already had -- the same fallback LibDBIcon-1.0 itself uses for
-- `Minimap`. No `...` vararg forwarding to the wrapped handler (`...` as
-- an expression does not parse on Lua 5.0.3) -- matches every OnShow
-- handler already written in this project, none of which ever needed
-- script arguments.
function S:TryHookScript(frame, scriptName, handler)
	if not frame then return false end
	local okAce = pcall(self.HookScript, self, frame, scriptName, handler)
	if okAce then return true end

	local okOrig, orig = pcall(frame.GetScript, frame, scriptName)
	local original = (okOrig and type(orig) == "function") and orig or nil
	local okNative = pcall(frame.SetScript, frame, scriptName, function()
		if original then pcall(original) end
		handler()
	end)
	return okNative
end

-- ===================================================================
-- `S:ResolveWidget(widget)` -- undo UA's degraded enumeration wrappers
-- ===================================================================
-- MEASURED, not theorised (via a one-off SavedVariables dump rig since
-- removed; `S:WhyNotSkinned` is what remains of it):
--
--   [2] name=GameMenuButtonOptions enumerated=<no getter>
--       global=Interface/Buttons/UI-Panel-Button-Up same=false
--   child 2: type=Button name=GameMenuButtonOptions shown=true
--       GetNormalTexture: no such method
--
-- On UA, `frame:GetChildren()` returns, for an XML-created native widget,
-- a DIFFERENT Lua object than the one its global name refers to -- and a
-- CRIPPLED one: `GetObjectType`, `GetName` and `IsShown` work, but the
-- type-specific methods (`GetNormalTexture`, `GetPushedTexture`,
-- `GetHighlightTexture`, ...) are not even present as fields. This is the
-- sharp edge of the already-known "a stored reference and a freshly
-- queried reference can compare unequal" finding: the enumerated object
-- is not merely a different handle to the same widget, it is missing its
-- own API.
--
-- It cost this project a full window: the auto-skin sweep walked
-- `GetChildren()`, asked each Button for its NormalTexture, got nothing on
-- all 10 rows of the Main Menu and skinned none of them -- while the very
-- same call on `_G[name]` returned the texture perfectly, which is why
-- styling a button by hand always worked.
--
-- So: ANY code that enumerates children on this client and then calls a
-- type-specific method must re-resolve through the global name first.
-- Lua-created frames are unaffected (they come back as themselves --
-- `GeneratedLuaUIObject_413`, our own panel, reported `same=true`), and an
-- unnamed widget has no global to resolve to, so it is returned as-is.
function S:ResolveWidget(widget)
	if not widget then return widget end
	local okName, name = pcall(widget.GetName, widget)
	if okName and type(name) == "string" and name ~= "" then
		local resolved = _G[name]
		if resolved then return resolved end
	end
	return widget
end

-- `SetBackdrop(frame, nil)` DOES NOT CLEAR a native `<Backdrop>` on this
-- client -- measured, not theorised:
--   * the sweep's own debug probe printed `Frame with native chrome still
--     present: GeneratedLuaUIObject_3006 (backdrop=true texture=false)`
--     AFTER `SoundOptions.lua`'s own `S:StripTextures(frame, true)` had
--     already walked into that frame and called `SetBackdrop(nil)` on it --
--     i.e. `GetBackdrop()` still hands back a live table afterwards;
--   * and a screenshot from the same run shows all 7 volume
--     sliders still wearing the `OptionsSliderTemplate` rounded metal
--     groove (`UI-SliderBar-Border`, a `<Backdrop>` in the FrameXML, not a
--     Texture region) ON TOP of the flat track surface this module had
--     already drawn underneath it.
-- So every "strip" this project has ever done only ever removed TEXTURE
-- REGIONS; native backdrops survived silently everywhere, and were merely
-- invisible in the windows whose chrome happens to be regions.
--
-- What DOES work is the mechanism `StyleSkillRankBar` (Blizzard/
-- Character.lua) and `StyleDropDownBackdrop` below have both had live-
-- confirmed for a while: hand SetBackdrop a REAL table and then paint it
-- with alpha 0 -- an "alpha = 0, separately, a working pattern" case,
-- distinct from the never-SetBackdrop-a-native-frame-with-a-visible-fill
-- rule -- no fill is ever painted here, the frame is left
-- fully transparent and this module's own child surface still draws the
-- actual look. Both halves are attempted (replace the table AND recolor to
-- alpha 0) because either one alone is enough to make the chrome vanish,
-- and neither is trusted on its own on this client.
--
-- Only runs when the plain clear demonstrably failed, so on every frame
-- where `SetBackdrop(nil)` does work this is exactly as before.
function S:ClearNativeBackdrop(frame)
	if not frame then return end

	-- DID THIS FRAME CARRY A NATIVE BACKDROP AT ALL? Asked BEFORE the
	-- removal, and kept as its own flag, because it answers a different
	-- question from `elvBackdropNeutralized` below -- and the difference is
	-- client-visible.
	--
	-- `elvBackdropNeutralized` records that removal FAILED and the fallback
	-- had to run. On UA `SetBackdrop(nil)` never works, so it is always set;
	-- on the legacy client it works, so it is NEVER set. Anything using it
	-- to mean "this is a group box" therefore silently did nothing on
	-- legacy -- which is exactly what happened to Blizzard/UIOptions.lua:
	-- no lighter box surfaces, and its panel fell back to covering the whole
	-- 1024x768 page (fixed height) instead of wrapping the boxes.
	local okBefore, backdropBefore = pcall(frame.GetBackdrop, frame)
	if okBefore and backdropBefore then frame.elvHadNativeBackdrop = true end

	pcall(frame.SetBackdrop, frame, nil)

	local ok, backdrop = pcall(frame.GetBackdrop, frame)
	if not (ok and backdrop) then return end

	-- 🔴 ON UA THESE CALLS ARE NOT LOCAL TO `frame` -- PROVEN.
	-- One line, run by hand on a client with EVERY ElvUI skin off:
	--     /run SoundOptionsFrameSlider1:SetBackdropColor(0,0,0,0)
	-- and the groove vanished from BOTH sliders of the native, untouched
	-- Interface Options window ("Mouse Sensitivity" AND "Mouse Look
	-- Speed"). So a `SetBackdropColor` / `SetBackdrop` on a NATIVE frame
	-- reaches every other native frame built from the same template or
	-- client-side helper -- which is why turning the Sound Options skin on
	-- stripped the backdrops out of a window this addon never touches.
	--
	-- `DisableDrawLayer` instead: a standing FRAME property, per-instance,
	-- and already this project's most reliable tool against native art it
	-- cannot delete. A `<Backdrop>`
	-- draws on BACKGROUND (bgFile) + BORDER (edgeFile); a ThumbTexture and
	-- the Low/High FontStrings are ARTWORK, so they survive -- which
	-- matters because the legacy client's native drag still needs its
	-- thumb.
	--
	-- GATED, and deliberately so: the recolor path is what the legacy
	-- client has been running all along, live-accepted across every skinned
	-- window, and the leak does not happen there (user-confirmed twice).
	-- Swapping a working mechanism on a working client to fix the other
	-- one's bug is how a fix turns into two bugs.
	if ElvUI.Compat and ElvUI.Compat.isUA then
		-- The layer switch takes every region on it, not only the backdrop:
		-- FontStrings the XML put on BACKGROUND/BORDER would vanish with it
		-- while still reporting `IsShown() == true` (measured on UA:
		-- `CharacterLevelText`/`InspectLevelText` share `PaperDollFrame`'s /
		-- `InspectPaperDollFrame`'s BACKGROUND layer with the quadrant art,
		-- and this frame reports a backdrop here). Moving them to OVERLAY
		-- first keeps them drawn; the textures on those layers are left in
		-- place, since they are the art being suppressed. `GetDrawLayer`/
		-- `SetDrawLayer` both work on the region objects `GetRegions()`
		-- returns on this client (measured).
		local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
		if okRegions and type(regions) == "table" then
			local i
			for i = 1, table.getn(regions) do
				local region = regions[i]
				local okType, regionType = pcall(region.GetObjectType, region)
				if okType and regionType == "FontString" then
					local okLayer, layer = pcall(region.GetDrawLayer, region)
					if okLayer and (layer == "BACKGROUND" or layer == "BORDER") then
						pcall(region.SetDrawLayer, region, "OVERLAY")
					end
				end
			end
		end
		pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
		pcall(frame.DisableDrawLayer, frame, "BORDER")
	else
		-- SLIDERS ARE EXEMPT FROM THE TABLE SWAP: handing a Slider a
		-- replacement backdrop table makes the THUMB stop existing
		-- (`GetThumbTexture()` no longer yields anything to anchor to), so
		-- all 7 Sound Options sliders would come back with a groove and
		-- nothing to drag.
		local okType, objType = pcall(frame.GetObjectType, frame)
		if not (okType and objType == "Slider") then
			pcall(frame.SetBackdrop, frame, S.PLAIN_BACKDROP)
		end
		pcall(frame.SetBackdropColor, frame, 0, 0, 0, 0)
		pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
	end
	-- Marks "this frame's `GetBackdrop()` is non-nil because WE put an
	-- invisible one there", so the sweep's own native-chrome probe doesn't
	-- report our own neutralised backdrop as surviving native chrome.
	frame.elvBackdropNeutralized = true
end

-- Clears every Texture region directly ON `frame` (its own regions), and
-- -- when `recurse` is true -- on every descendant too, EXCEPT Button
-- children (item slots, close buttons, tabs, ... -- anything interactive
-- enough to have its own meaningful icon, always styled by its own
-- dedicated function instead, never blanket-stripped). A non-recursive
-- strip on CharacterFrame removes nothing at all: its own corner/border
-- art isn't drawn as direct regions of CharacterFrame itself, it lives on
-- nested child (non-Button) frames. Matches real ElvUI's own call shape
-- exactly (`E:StripTextures(CharacterFrame, true)` -- source/ElvUI-
-- vanilla's own second "recurse into children" argument), just rebuilt
-- from this project's own primitives. FontStrings are always left alone,
-- at every level.
--
-- Also clears the frame's own NATIVE BACKDROP, not just its Texture
-- regions: the stat panel and resistance readouts stay fully
-- native-boxed even under the recursive strip otherwise. CharacterFrame's
-- own border/corner art is exactly this case (a `<Backdrop>`, not
-- enumerable via GetRegions() at all -- see Blizzard/Character.lua's own
-- note on why it needed a SEPARATE inset child frame rather than
-- SetBackdrop directly on CharacterFrame) -- other native sub-panels very
-- likely use the same convention. Passing `nil` to `SetBackdrop` does NOT
-- reliably remove it on this client (standard WoW API behavior notwith-
-- standing) -- see `S:ClearNativeBackdrop` just above for the evidence
-- and for what the strip actually does now.
--
-- On this client, `SetTexture(nil)` clears a texture's readable path but
-- does NOT stop it from rendering: `/run
-- ElvUI[1].Skins:Dump("PaperDollFrame")` on the 4 unnamed
-- BACKGROUND-layer quadrant textures that make up this client's ornate
-- window chrome (UI-Character-CharacterTab-L1/R1/BottomLeft/BottomRight,
-- source/wow-ui-source/FrameXML/PaperDollFrame.xml:130-173) comes back
-- `tex=4 ... shownWithSize=4` -- ALL FOUR still fully rendering at real
-- size, even though `paths={}` proves their file reference WAS
-- successfully cleared. Hide()+permanently-noop'd Show
-- (`S:Kill(CharacterFramePortrait)`-style) is the fix that actually
-- works for a generic, UNNAMED region like this, added below alongside
-- the existing SetTexture(nil) call, not instead of it.
--
-- A SLIDER'S THUMB IS NOT ORDINARY ART -- IT IS STATE.
--
-- Two things in this project read a slider's thumb rather than look at it:
--   * native drag tracking stops working on a HIDDEN thumb (live-confirmed
--     regression on the scrollbar, see `S:StyleOptionsSlider`);
--   * vanilla marks a slider DISABLED by hiding it and nothing else
--     (`OptionsFrame_DisableSlider` -> `Thumb:Hide()`,
--     source/wow-ui-source/FrameXML/OptionsFrame.lua:483), which is the
--     signal `S:StyleOptionsSlider`'s handle greys off.
-- So hiding it here is not "removing native art", it is overwriting a state
-- flag that other code depends on.
--
-- WHY THIS LIVES HERE AND NOT IN `S:StyleOptionsSlider` (where it was tried
-- first, and failed). The live debug line settled it:
--
--   slider OptionsFrameSlider7: ... | thumb get=false/false named=nil/nil
--
-- `get=false/false` -- the thumb was ALREADY hidden when the slider recipe
-- began, so a repair scoped to that recipe's own strip could never see the
-- change it was meant to undo. The strip that actually hid it is the
-- WINDOW-level `S:StripTextures(frame, true)` the skin file runs first, which
-- recurses into every Slider long before `S:SkinChildren` reaches one. Same
-- lesson as the dropdown case, one level further out: the strip that broke a
-- property is not necessarily the one next to the code that reads it, so the
-- protection belongs in the strip itself.
--
-- `named=nil/nil` closed a sub-theory at the same time: `_G[name.."Thumb"]`
-- and `slider:GetThumbTexture()` are the SAME object here (the flag is only
-- set when they differ), so the "the client hides one and we repair the
-- other" idea is dead and the code that chased it has been removed.
--
-- Conditional, so a slider the CLIENT disabled stays disabled: only a thumb
-- that was shown BEFORE this pass is put back. Restoring `Show` (`= nil`, so
-- the metatable's own method comes back) is what hands the live signal over
-- to the client again.
local function PreserveThumb(frame)
	local okType, objType = pcall(frame.GetObjectType, frame)
	if not (okType and objType == "Slider") then return nil, false end
	local okThumb, thumb = pcall(frame.GetThumbTexture, frame)
	if not (okThumb and thumb) then return nil, false end
	local okShown, shown = pcall(thumb.IsShown, thumb)
	return thumb, (okShown and shown) and true or false
end

local function RestoreThumb(thumb, wasShown)
	if not (thumb and wasShown) then return end
	local okShown, shown = pcall(thumb.IsShown, thumb)
	if not okShown or shown then return end
	if thumb.Show == E.noop then thumb.Show = nil end
	pcall(thumb.Show, thumb)
end

function S:StripTextures(frame, recurse)
	if not frame then return end
	S:ClearNativeBackdrop(frame)
	local thumb, thumbWasShown = PreserveThumb(frame)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if ok and type(regions) == "table" then
		local i
		for i = 1, table.getn(regions) do
			local region = regions[i]
			local okType, regionType = pcall(region.GetObjectType, region)
			if okType and regionType == "Texture" then
				pcall(region.SetTexture, region, nil)
				pcall(region.Hide, region)
				region.Show = E.noop
			end
		end
	end
	RestoreThumb(thumb, thumbWasShown)

	if not recurse then return end
	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	if not okKids or type(kids) ~= "table" then return end
	local j
	for j = 1, table.getn(kids) do
		-- Re-resolved: an enumerated native child is a crippled wrapper on
		-- this client, and `SetTexture`/`Hide` on ITS regions would not be
		-- acting on the widget the rest of the UI sees. See `S:ResolveWidget`.
		local kid = self:ResolveWidget(kids[j])
		local okType, kidType = pcall(kid.GetObjectType, kid)
		local okName, kidName = pcall(kid.GetName, kid)
		local skip = okName and kidName and self.stripSkipNames and self.stripSkipNames[kidName]
		-- NEVER strip our OWN surfaces. `S:CreateSurface`
		-- flags every background/field frame it builds with `elvSurface`,
		-- and those are unnamed direct children of the very frame each
		-- window re-strips on every OnShow -- so this walk would otherwise
		-- reach in and `SetBackdrop(nil)` the window's own background away
		-- on the SECOND open, with the `if not frame.elvBackground` guard
		-- above making sure it never came back. `stripSkipNames` can't
		-- cover them: it matches on NAME, and these frames deliberately
		-- have none.
		if not skip and kid.elvSurface then skip = true end
		-- This exemption checks for BOTH "Button" and "CheckButton": a
		-- recursive strip from an ancestor (e.g.
		-- `S:StripTextures(SpellBookFrame, true)`) would otherwise descend
		-- INTO `SpellButton<i>`/`SpellBookSkillLineTab<i>` (both
		-- CheckButton, inherits CheckButton not Button) and blanket-Hide()
		-- +noop EVERY Texture region on them, including their own
		-- IconTexture/NormalTexture -- permanently blanking spell/skill-line
		-- icons before SpellBook.lua's own targeted, icon-preserving
		-- styling functions ever get a chance to run. CheckButton is
		-- conceptually the exact same "always styled by its own dedicated
		-- function, never blanket-stripped" category as Button.
		if okType and kidType ~= "Button" and kidType ~= "CheckButton" and not skip then
			self:StripTextures(kid, true)
		end
	end
end

-- Named children to never recurse into, even though they're not Buttons:
-- stripping `CharacterResistanceFrame`
-- (Blizzard/Character.lua) would take the resistance icons down WITH the
-- chrome, because `MagicResistanceFrameTemplate` has NO separate chrome
-- texture at all (confirmed via the FrameXML) -- the icon IS the only
-- Texture region there, so there's nothing to strip without also
-- stripping the icon itself. A skin file populates this by name (not by
-- object reference, since the recursive walk only has names to match
-- against cheaply) BEFORE calling StripTextures.
S.stripSkipNames = S.stripSkipNames or {}

-- Shared with Blizzard/Character.lua's own `StyleReputationCheckbox`
-- recipe -- unchanged, it just has one home now so the
-- auto-skin sweep below can reach it and so a second window with
-- checkboxes doesn't get a fourth private copy.
S.CHECKBOX_INSET = 4

function S:StyleCheckBox(checkbox)
	if not checkbox or checkbox.elvStyled then return end
	checkbox.elvStyled = true

	local okNormal, normalTexture = pcall(checkbox.GetNormalTexture, checkbox)
	if okNormal and normalTexture then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		pcall(normalTexture.Hide, normalTexture)
		normalTexture.Show = E.noop
	end
	local okPushed, pushedTexture = pcall(checkbox.GetPushedTexture, checkbox)
	if okPushed and pushedTexture then
		pcall(pushedTexture.SetTexture, pushedTexture, nil)
		pcall(pushedTexture.Hide, pushedTexture)
		pushedTexture.Show = E.noop
	end
	local okHighlight, highlightTexture = pcall(checkbox.GetHighlightTexture, checkbox)
	if okHighlight and highlightTexture then
		pcall(highlightTexture.SetTexture, highlightTexture, nil)
		pcall(highlightTexture.Hide, highlightTexture)
		highlightTexture.Show = E.noop
	end
	-- Setter only -- `GetDisabledTexture` is missing on UA (see
	-- `S:GetDisabledTexture`); clearing the slot is exactly the state that
	-- avoids ever needing the getter.
	pcall(checkbox.SetDisabledTexture, checkbox, nil)

	-- Raise the CHECKBOX first so the border (always placed at target
	-- level - 1) lands BELOW the checkbox's own CheckedTexture, which has
	-- to stay visible. Floor computed RELATIVE to the parent, never a flat
	-- constant -- a hardcoded value would silently push the checkbox below
	-- its own window's `elvBackground` on any client where that window
	-- happens to sit at a higher level.
	local okLevel, level = pcall(checkbox.GetFrameLevel, checkbox)
	local checkboxLevel = (okLevel and tonumber(level)) or 1

	local minLevel = 4
	local okParent, parent = pcall(checkbox.GetParent, checkbox)
	if okParent and parent then
		local okParentLevel, parentLevel = pcall(parent.GetFrameLevel, parent)
		if okParentLevel and tonumber(parentLevel) then
			minLevel = parentLevel + 4
		end
	end
	if checkboxLevel < minLevel then
		pcall(checkbox.SetFrameLevel, checkbox, minLevel)
		checkboxLevel = minLevel
	end

	-- The border goes on a dedicated INSET holder frame rather than on the
	-- checkbox itself: that's how real ElvUI's 4px inset is achieved
	-- without resizing the checkbox (resizing would shrink its clickable
	-- area too). EnableMouse(false) so the holder can never swallow a
	-- click meant for the checkbox above it.
	local okHolder, holder = pcall(CreateFrame, "Frame", nil, checkbox)
	if okHolder and holder then
		pcall(holder.SetPoint, holder, "TOPLEFT", checkbox, "TOPLEFT", S.CHECKBOX_INSET, -S.CHECKBOX_INSET)
		pcall(holder.SetPoint, holder, "BOTTOMRIGHT", checkbox, "BOTTOMRIGHT", -S.CHECKBOX_INSET, S.CHECKBOX_INSET)
		pcall(holder.SetFrameLevel, holder, checkboxLevel)
		pcall(holder.EnableMouse, holder, false)
		ElvUI.Util.CreateButtonBorder(holder)
		checkbox.elvCheckHolder = holder
	end

	S:InstallCheckMark(checkbox)
end

-- OUR OWN "checked" mark, replacing the native one.
--
-- Measured from paired screenshots (skinned vs. addon
-- disabled): everything this function's caller does DOES land -- the native
-- rounded bevel box is gone and the flat inset border is there -- but the
-- CheckedTexture is untouched by all of it and is what still reads as
-- Blizzard: on this client it's an oversized gold tick that spills well
-- outside the box it's supposed to sit in.
--
-- Note this is a DELIBERATE divergence from real ElvUI, which keeps the
-- native tick (`S:HandleCheckBox`, source/ElvUI-vanilla/ElvUI/Modules/
-- Skins/Skins.lua:309 -- it only clears Normal/Pushed/Highlight/Disabled
-- and adds the inset backdrop). That works there because real 1.12.1's own
-- tick actually fits its box; this client's doesn't.
--
-- Mechanism is this project's own already-live-confirmed dropdown-list
-- recipe (`StyleDropDownCheck`), not a new invention: clear the native
-- art, draw our own accent square, and MIRROR the native state rather than
-- trying to own it.
--
-- GUARDED, and this matters: the takeover only happens if `GetChecked` is
-- actually callable on this client. If it isn't, the native tick is left
-- completely alone -- the failure mode of getting this wrong is a checkbox
-- that can never show as checked at all, which is far worse than an ugly
-- tick. `SetCheckedTexture(cb, "")` is the project's own established idiom
-- for clearing the slot and, unlike the
-- getter, is on record as a working SETTER.
S.CHECKMARK_INSET = 4
S.CHECKMARK_POLL = 0.1

local function SyncCheckMark(checkbox)
	if not checkbox or not checkbox.elvCheck then return end
	local ok, checked = pcall(checkbox.GetChecked, checkbox)
	if ok and checked then
		pcall(checkbox.elvCheck.Show, checkbox.elvCheck)
	else
		pcall(checkbox.elvCheck.Hide, checkbox.elvCheck)
	end
end

function S:InstallCheckMark(checkbox)
	local holder = checkbox and checkbox.elvCheckHolder
	if not holder or checkbox.elvCheck then return end

	-- The probe AND the guard in one call: a missing getter fails the pcall.
	local okGetter = pcall(checkbox.GetChecked, checkbox)
	if not okGetter then return end

	-- `SetCheckedTexture(cb, "")` DOES NOT CLEAR IT on this client --
	-- measured: with our own mark already drawn, the native tick
	-- was still there, its corners sticking out around the square.
	-- That's the second time this setter has been credited
	-- with a removal it didn't perform (the first was
	-- `MacroFrameSelectedMacroButton`, where a transient button resize
	-- turned out to be what actually hid the art) -- so it is NOT tried a
	-- third time as the mechanism. Kept only as a harmless first attempt.
	pcall(checkbox.SetCheckedTexture, checkbox, "")

	-- `checkbox:SetAlpha(0)` WAS THE PREVIOUS ATTEMPT HERE, AND IT FAILED --
	-- measured, and worth stating precisely because the result is
	-- odd: the native tick rendered exactly as before, while the checkbox's
	-- own LABEL FontString disappeared (the "Enable Voice Chat" row lost its
	-- text). So alpha does reach that widget's ordinary regions, and the
	-- CheckedTexture is not among them -- it is not just missing a getter
	-- and missing from `GetRegions()`, it does not respond to the widget's
	-- alpha either. Reverted; do not try alpha here again.
	--
	-- Which leaves the mechanism this project reaches for whenever a native
	-- element can't be modified: COVER IT. An opaque patch over the
	-- checkbox's whole footprint, one frame level UP -- documented to render
	-- in front of the parent's own art -- and painted with whatever surface this checkbox actually sits on,
	-- so it disappears into its background instead of reading as a slab.
	-- The visible box (`elvCheckHolder`, inset 4) and the mark then sit on
	-- top of the patch. Mouse stays disabled on it, so the checkbox itself
	-- keeps the whole footprint as its click target.
	local okPatch, patch = pcall(CreateFrame, "Frame", nil, checkbox)
	if okPatch and patch then
		-- INSET BY 2, not the full footprint: a full-footprint patch clips
		-- the first letter of the label. The label FontString starts a couple of
		-- pixels INSIDE this frame's own rect on this client, and nothing
		-- used to be drawn there, so it never showed before. Two pixels is
		-- enough to clear the text and still cover the tick, which reaches
		-- at most ~2px past the visible box (`elvCheckHolder`, itself inset
		-- 4) -- measured off the zoomed screenshot that showed its tips
		-- sticking out around our mark.
		-- SQUARE, anchored to the LEFT edge, side = the checkbox's own
		-- height. A checkbox's art is always the square box at its left;
		-- if this client's frame is WIDER than tall (which the clipped
		-- letter suggests -- the rect would then reach under the label),
		-- a full-footprint patch necessarily eats into the text, while a
		-- square one cannot, whatever the frame's width turns out to be.
		-- On a genuinely square checkbox this is identical to insetting the
		-- whole rect by 2. Falls back to the plain inset rect only if the
		-- height can't be read.
		pcall(patch.SetPoint, patch, "TOPLEFT", checkbox, "TOPLEFT", 2, -2)
		local okBoxH, boxH = pcall(checkbox.GetHeight, checkbox)
		boxH = okBoxH and tonumber(boxH)
		if boxH and boxH > 6 then
			pcall(patch.SetWidth, patch, boxH - 4)
			pcall(patch.SetHeight, patch, boxH - 4)
		else
			pcall(patch.SetPoint, patch, "BOTTOMRIGHT", checkbox, "BOTTOMRIGHT", -2, 2)
		end
		pcall(patch.EnableMouse, patch, false)
		pcall(patch.SetBackdrop, patch, S.PLAIN_BACKDROP)
		local c = S:SurfaceColorFor(checkbox)
		pcall(patch.SetBackdropColor, patch, c[1], c[2], c[3], 1)
		pcall(patch.SetBackdropBorderColor, patch, c[1], c[2], c[3], 1)
		patch.elvSurface = true

		-- Three levels, in draw order: patch (erases the native art), then
		-- the BORDER, then the holder carrying the mark.
		--
		-- The border needs its own explicit level or the box vanishes,
		-- rendering as bare text with no box at all. `Util.CreateButtonBorder` puts
		-- its frame at `holderLevel - 1` computed AT CREATION TIME
		-- (Core/Util.lua), i.e. below where the holder was before this
		-- function raised it -- so the patch, being higher, painted straight
		-- over it.
		local okLevel, level = pcall(checkbox.GetFrameLevel, checkbox)
		local base = (okLevel and tonumber(level)) or 1
		pcall(patch.SetFrameLevel, patch, base + 1)
		if holder.elvBackdrop then
			pcall(holder.elvBackdrop.SetFrameLevel, holder.elvBackdrop, base + 2)
		end
		pcall(holder.SetFrameLevel, holder, base + 3)
		checkbox.elvCheckPatch = patch
	end

	local okMark, mark = pcall(holder.CreateTexture, holder, nil, "OVERLAY")
	if not okMark or not mark then return end
	pcall(mark.SetPoint, mark, "TOPLEFT", holder, "TOPLEFT", S.CHECKMARK_INSET, -S.CHECKMARK_INSET)
	pcall(mark.SetPoint, mark, "BOTTOMRIGHT", holder, "BOTTOMRIGHT", -S.CHECKMARK_INSET, S.CHECKMARK_INSET)
	pcall(mark.SetTexture, mark, "Interface\\Buttons\\WHITE8x8")
	pcall(mark.SetVertexColor, mark, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	checkbox.elvCheck = mark
	SyncCheckMark(checkbox)

	-- POLLING, not a hook, and on purpose: `hooksecurefunc` doesn't exist
	-- here and AceHook's `:HookScript` is partly broken on this client,
	-- while the state can change from
	-- places no per-checkbox OnClick would ever see anyway (the window's own
	-- "Defaults" button, a master checkbox re-driving its dependants). The
	-- timer is read from `GetTime()` rather than the OnUpdate elapsed
	-- argument -- `arg1` is the 1.12-era idiom and a `tonumber(arg1) or 0`
	-- fallback would silently accumulate ZERO and never fire if this client
	-- passed it any other way. Only runs while the checkbox is on screen.
	pcall(holder.SetScript, holder, "OnUpdate", function()
		local now = GetTime()
		if holder.elvNextCheck and now < holder.elvNextCheck then return end
		holder.elvNextCheck = now + S.CHECKMARK_POLL
		SyncCheckMark(checkbox)
	end)
end

-- ===================================================================
-- AUTO-SKIN SWEEP -- `S:SkinChildren(frame)`
-- ===================================================================
-- **Why this is a sweep and not literally a template edit.** A WoW XML
-- `virtual="true"` template (`UIPanelButtonTemplate`, `InputBoxTemplate`,
-- `OptionsCheckButtonTemplate`, ...) is consumed by the client at frame
-- CREATION time; there is no live template object in Lua to recolor, and
-- every native window's widgets are already created (from XML, not via
-- `CreateFrame`, so hooking `CreateFrame` would catch none of them). The
-- achievable equivalent is to recognise a widget BY ITS TEMPLATE'S OWN
-- ART and apply the one matching recipe -- which gets the same practical
-- result the user asked for: a new window's buttons/fields/checkboxes are
-- skinned without anyone enumerating them by name.
--
-- **Deliberately conservative -- it only touches what it can POSITIVELY
-- identify.** Every dispatch below requires a native template's own
-- texture path (`UI-Panel-Button-*`, `UI-CheckBox-*`) or an unambiguous
-- widget type (EditBox, `*ScrollBar` Slider). It does NOT skin a Button
-- just for being a Button -- that would walk straight into
-- `FriendsFrameFriendButton<i>`, where touching native list rows is
-- CONFIRMED to have caused a real regression (rows went permanently grey
-- and stopped being selectable -- see `S:HandleButtonHighlight`), and
-- into every icon-carrying action/spell/macro slot, whose NormalTexture
-- IS the icon. Those keep their own dedicated styling functions.
--
-- **Not a full-tree walk.** A caller passes ONE window. `UIParent`-wide
-- enumeration is confirmed to crash this client outright -- never call
-- this on UIParent or WorldFrame.
-- Cost per window is the same order as `S:StripTextures(frame, true)`,
-- which every skin file already runs on every OnShow.
S.autoSkinSkipNames = S.autoSkinSkipNames or {}

-- Lowercased fragments of the native templates' own art paths. A path is
-- matched with a PLAIN find (never a Lua pattern -- `-` is a quantifier).
local PANEL_BUTTON_ART = "ui-panel-button"
local CHECKBOX_ART = "ui-checkbox"
-- `UIDropDownMenuTemplate`'s own Left/Middle/Right box art
-- (`Interface\Glues\CharacterCreate\CharacterCreate-LabelFrame`, confirmed
-- via `source/wow-ui-source/FrameXML/UIDropDownMenuTemplates.xml`) --
-- needed for the Sound Options sweep, where the FrameXML is
-- customised so no dropdown's global name can be hardcoded up front.
local DROPDOWN_ART = "charactercreate-labelframe"

local function TexturePath(texture)
	if not texture then return nil end
	local ok, path = pcall(texture.GetTexture, texture)
	if not ok or type(path) ~= "string" then return nil end
	-- An empty string means "no texture", and must never become a matchable
	-- value: the probe below builds a SET of paths, and an empty key would
	-- match every blanked slot on every widget in the window.
	if string.len(path) == 0 then return nil end
	-- Normalised, because a path is compared against paths from OTHER
	-- sources: lowercased (the FrameXML's own casing is inconsistent, and
	-- UA is not case-sensitive about asset names either) and separator-
	-- folded. The separator matters: a native button on UA
	-- can report `Interface/Buttons...` with FORWARD slashes, while
	-- the FrameXML and everything this project writes uses backslashes --
	-- so an exact comparison between a probe's path and a native widget's
	-- path would fail on the separator alone. (`\` is not a Lua pattern
	-- metacharacter, so the gsub pattern is safe as written.)
	path = string.gsub(string.lower(path), "\\", "/")
	return path
end

local function PathMatches(texture, fragment)
	local path = TexturePath(texture)
	if path and string.find(path, fragment, 1, true) then return true end
	return false
end

-- ===================================================================
-- SELF-CALIBRATING TEMPLATE ART
-- ===================================================================
-- "Can't we just use the widget's `inherits=`?" -- no: **no client in this
-- family exposes a widget's template chain to Lua.** `GetObjectType`/
-- `IsObjectType` answer the WIDGET TYPE only ("a CheckButton is also a
-- Button", UA's UIObject.md), and there is no `GetTemplate`. A template is
-- consumed at frame-creation time and leaves no queryable trace, which is
-- why identification has to go through the art in the first place.
--
-- What CAN be used is the OTHER direction: `CreateFrame(type, name, parent,
-- template)` does take a virtual template name on UA (globals/Frame.md), so
-- the client can be ASKED what a given template's art looks like -- build
-- one throwaway widget from the template, read back every texture path it
-- reports, and match native widgets against exactly those strings. That
-- makes the sweep self-calibrating: if UA serves `UI-Panel-Button-Up` under
-- some other name (a UE5-side asset path, say), the probe reports that name
-- and recognition still works, with no hardcoded fragment to keep in sync.
--
-- The hardcoded fragment stays as the primary, cheap test; the probe set is
-- the fallback. If the probe comes back EMPTY, that is itself the answer to
-- "does the client register the inherited texture at all" -- it says
-- identification-by-art cannot work here -- so it reports itself once
-- instead of failing silently, the way the original bug did.
-- Several templates per art family, because a window's buttons are often
-- built from a DERIVED template (`GameMenuButtonTemplate` inherits
-- `UIPanelButtonTemplate`) and a reimplemented client may well give the
-- derived one its own art -- which is precisely the Main Menu's shape:
-- its rows render in custom red art, not the stock tan `UI-Panel-Button`.
-- Probing the derived templates too means the client itself tells us what
-- those rows look like, with nothing hardcoded about Emberveil.
local ART_TEMPLATES = {}
ART_TEMPLATES[PANEL_BUTTON_ART] = { widget = "Button", templates = {
	"UIPanelButtonTemplate", "UIPanelButtonTemplate2", "GameMenuButtonTemplate",
	"OptionsButtonTemplate" } }
ART_TEMPLATES[CHECKBOX_ART] = { widget = "CheckButton", templates = {
	"UICheckButtonTemplate", "OptionsCheckButtonTemplate" } }

local templateArtCache = {}

local function CollectTexturePaths(widget, into)
	local GETTERS = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }
	local i
	for i = 1, table.getn(GETTERS) do
		local ok, texture = pcall(widget[GETTERS[i]], widget)
		if ok then
			local path = TexturePath(texture)
			if path then into[path] = true end
		end
	end

	local okRegions, regions = pcall(function() return { widget:GetRegions() } end)
	if okRegions and type(regions) == "table" then
		for i = 1, table.getn(regions) do
			local path = TexturePath(regions[i])
			if path then into[path] = true end
		end
	end
end

local function TemplateArt(fragment)
	local cached = templateArtCache[fragment]
	if cached then return cached end

	local paths = {}
	templateArtCache[fragment] = paths -- cache first: one probe per session, success or not

	local spec = ART_TEMPLATES[fragment]
	if not spec then return paths end

	-- Template-backed CreateFrame is not guaranteed to succeed on UA --
	-- hence the pcall. A probe is
	-- parented to UIParent and hidden immediately; frames can't be
	-- destroyed on this client, so they stay around, inert, forever (one
	-- per template, once per session).
	local i
	for i = 1, table.getn(spec.templates) do
		local ok, probe = pcall(CreateFrame, spec.widget, nil, UIParent, spec.templates[i])
		if ok and probe then
			pcall(probe.Hide, probe)
			CollectTexturePaths(probe, paths)
		end
	end

	-- No readable art in the whole family: the sweep cannot recognise these
	-- widgets on this client, so they stay unstyled.
	if not next(paths) then
		S:ReportSkinProblem()
	end

	return paths
end

-- Plain-find on the hardcoded fragment first, then exact-match against
-- whatever the client itself says the template's art is.
local function MatchesTemplateArt(texture, fragment)
	local path = TexturePath(texture)
	if not path then return false end
	if string.find(path, fragment, 1, true) then return true end
	if TemplateArt(fragment)[path] then return true end
	return false
end

-- True only for a widget carrying the named template's own art. Every
-- shape the FrameXML actually uses is checked, because ONE of them going
-- unreadable on UA must not make the whole sweep a silent no-op (that is
-- exactly what happened to `GameMenuFrame`'s buttons):
--
--  1. **State slots.** `UIPanelButtonTemplate` (and everything inheriting
--     it, e.g. `GameMenuButtonTemplate`) assigns Normal/Pushed/Disabled/
--     Highlight. All four of its assets share the `UI-Panel-Button` stem
--     (`-Up`/`-Down`/`-Disabled`/`-Highlight`), so ANY readable slot
--     identifies the template -- the first version only looked at Normal.
--     This matters on UA specifically: the template declares its slots as
--     `<NormalTexture inherits="UIPanelButtonUpTexture"/>`, i.e. the asset
--     path lives in a VIRTUAL `<Texture>`, and `Button:GetNormalTexture`
--     is documented to return nil "if none has been set" -- an unresolved
--     `inherits=` plausibly reads as "not set" here.
--  2. **Named background regions.** `UIPanelButtonTemplate2`
--     (UIPanelTemplates.xml:28+) has NO NormalTexture at all and draws the
--     same asset as three `$parentLeft/Middle/Right` BACKGROUND regions.
--  3. **Every region on the widget.** The catch-all, and the one that does
--     NOT depend on any texture getter or on `$parent`-naming: the art is
--     an ordinary region, so `GetRegions()` returns it -- the same
--     already-proven route `S:GetDisabledTexture` uses to work around the
--     missing `GetDisabledTexture` getter. This also covers a button that
--     starts life disabled (its Normal slot may hold nothing useful) and
--     an anonymous button built from `UIPanelButtonTemplate2`.
--
-- Every one of those three goes through `MatchesTemplateArt`, so each also
-- accepts whatever path the CLIENT ITSELF reports for the template (see
-- "SELF-CALIBRATING TEMPLATE ART" above), not just the hardcoded fragment.
--
-- Pass 3 replaced the old opt-in `S:GetDisabledTexture` probe, which was
-- deliberately not run for checkboxes (that helper's elimination pass
-- would have cached a CheckButton's CheckedTexture as its "disabled"
-- texture). Scanning regions here caches nothing, so it is safe for every
-- widget type and the special case is gone.
local NAMED_CHROME_SUFFIXES = { "Left", "Middle", "Right" }

-- Is this Button one of Blizzard's TAB buttons?
--
-- Structural, never by name -- the same kind of template fingerprint the
-- dropdown branch uses. Every tab template in this UI builds its background
-- from a named three-piece strip, `$parentLeft` / `$parentMiddle` /
-- `$parentRight` (plus the `...Disabled` set that renders the SELECTED
-- state) -- confirmed in the FrameXML for both families this project has
-- already skinned by hand (`CharacterFrameTabButtonTemplate`,
-- `UIOptionsFrameTab1`, source/wow-ui-source/FrameXML/UIOptionsFrame.xml
-- :1238-1298). Nothing else in these windows carries that trio.
--
-- `$parentMiddle` alone is the test: `Left`/`Right` are common enough
-- suffixes to risk a collision, `Middle` is not, and requiring all three
-- would make the check fail on any tab whose template names only two.
-- Deliberately NOT a texture-path check: this window's tabs use
-- `HelpFrameTab-*` art while CharacterFrame's use `CharacterFrameTab-*`,
-- and a server-added tab may well use a third -- the NAMING is the stable
-- part, the art isn't.
local function IsTabButton(button, name)
	if not button or not name then return false end
	return _G[name .. "Middle"] and true or false
end

local function HasNativeArt(button, fragment)
	if not button then return false end

	local okNormal, normalTexture = pcall(button.GetNormalTexture, button)

	-- VETO before any of the widened checks below: a slot/icon button whose
	-- NormalTexture IS the icon must never be skinned as a panel button --
	-- `S:StyleUIPanelButton` hides that slot, i.e. it would erase the icon.
	-- Widening identification to Pushed/Highlight and to every region made
	-- this reachable in theory (a button could carry a generic panel
	-- highlight over an icon), so the guard is stated once, up front,
	-- rather than being implied by the old Normal-only check.
	-- (`TexturePath` folds separators to `/`, so the fragment is written
	-- that way too -- a backslash form would never match on UA.)
	if okNormal and PathMatches(normalTexture, "interface/icons") then return false end

	if okNormal and MatchesTemplateArt(normalTexture, fragment) then return true end
	local okPushed, pushedTexture = pcall(button.GetPushedTexture, button)
	if okPushed and MatchesTemplateArt(pushedTexture, fragment) then return true end
	local okHighlight, highlightTexture = pcall(button.GetHighlightTexture, button)
	if okHighlight and MatchesTemplateArt(highlightTexture, fragment) then return true end

	local okName, name = pcall(button.GetName, button)
	if okName and name then
		local i
		for i = 1, table.getn(NAMED_CHROME_SUFFIXES) do
			if MatchesTemplateArt(_G[name..NAMED_CHROME_SUFFIXES[i]], fragment) then return true end
		end
	end

	local okRegions, regions = pcall(function() return { button:GetRegions() } end)
	if okRegions and type(regions) == "table" then
		local i
		for i = 1, table.getn(regions) do
			if MatchesTemplateArt(regions[i], fragment) then return true end
		end
	end

	return false
end

-- Opt-in tracing for "the sweep ran but nothing got skinned" (the
-- GameMenuFrame case). Turn on in-game, then re-open the window:
--   /run ElvUI[1]:GetModule("Skins").autoSkinDebug = true
-- Prints one line per top-level sweep with what it FOUND vs. what it
-- SKINNED, so an empty enumeration and an unrecognised template are
-- distinguishable from each other without touching any code.
S.autoSkinDebug = false
local sweepStats
local sweepTabInsetX

local function SweepCount(key)
	if sweepStats then sweepStats[key] = (sweepStats[key] or 0) + 1 end
end

-- "Seen but not (newly) skinned" is ambiguous by itself: it covers both
-- "never recognised at all" (a real bug) AND "recognised and styled on an
-- EARLIER pass, so its own native art is already gone and can't match
-- again" (expected, harmless -- every style function clears the very
-- texture slots `HasNativeArt` keys on). A screenshot can't tell those
-- apart, and neither can a live `/run` probe on THIS window specifically:
-- it's keyboard-enabled and swallows all input while open, so the only channel that works while it's actually
-- shown is this debug print itself -- it has to carry the disambiguation,
-- not a follow-up command. `elvStyled`/`elvBackground`/`elvThumbBG` are
-- the one-shot latches this project already sets everywhere a widget gets
-- run through once (Button/CheckButton set `elvStyled`; anything ever
-- built via `S:CreateSurface` -- panels, fields, dropdown boxes, option
-- sliders -- sets `elvBackground`; the scrollbar/slider thumb recipe sets
-- `elvThumbBG`), so their presence means "this project's own code ran on
-- this widget before", independent of what the live art probe says now.
local function HadRun(widget)
	return (widget.elvStyled or widget.elvBackground or widget.elvThumbBG) and true or false
end

function S:SkinChildren(frame, depth)
	if not frame then return end
	depth = tonumber(depth) or 0
	if depth == 0 then
		sweepStats = self.autoSkinDebug and {} or nil
		-- Per-window tab spacing, read once from the TOP frame (the sweep
		-- recurses, so `frame` stops being the window after depth 0). A
		-- window sets `elvTabInsetX` before calling the sweep when its tab
		-- strip needs different spacing from the project default -- see
		-- Blizzard/UIOptions.lua, whose tabs sit apart instead of
		-- overlapping. nil means "use `S.TAB_INSET_X`".
		sweepTabInsetX = tonumber(frame.elvTabInsetX)
	end
	-- Every window skinned so far is at most ~5 levels deep; the cap is
	-- pure insurance against a cyclic/absurd hierarchy, not a tuning knob.
	if depth > 8 then return end

	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	if not okKids or type(kids) ~= "table" then return end

	-- LOUD when enumeration under-reports. This sweep's two
	-- failure modes were both SILENT, which is how a whole window's buttons
	-- came out unskinned with nothing in the log.
	-- `GetNumChildren` is documented to match `GetChildren`'s value count on UA, and
	-- `GameMenuFrame:GetChildren()` is on record as sometimes coming back
	-- empty -- so a disagreement
	-- between the two is exactly the case where no amount of per-widget
	-- identification can help, and it must not pass unnoticed. Deliberately
	-- only a report: no _G-wide "find frames whose parent is this one"
	-- fallback is written until this is seen to actually fire, since that
	-- would be an unverified mechanism against a client where full frame
	-- enumeration is already known to be dangerous.
	-- Reported once per frame, not once per OnShow -- the sweep re-runs on
	-- every show and this would otherwise spam the chat frame forever.
	local kidCount = table.getn(kids)
	local okNum, numKids = pcall(frame.GetNumChildren, frame)
	if okNum and type(numKids) == "number" and numKids > kidCount and not frame.elvSweepWarned then
		frame.elvSweepWarned = true
		S:ReportSkinProblem()
	end

	local i
	for i = 1, kidCount do
		-- THE fix for "the sweep recognised 0 of 10 buttons":
		-- an enumerated native child has no `GetNormalTexture` at all on
		-- this client, so every art check silently failed. Resolve to the
		-- real widget FIRST, then identify and style. See `S:ResolveWidget`.
		local kid = self:ResolveWidget(kids[i])
		local okType, kidType = pcall(kid.GetObjectType, kid)
		local okName, kidName = pcall(kid.GetName, kid)
		local skip = okName and kidName and self.autoSkinSkipNames[kidName]
		-- Our own surfaces have nothing to skin and nothing worth walking.
		if not skip and kid.elvSurface then skip = true end

		-- Set by the Frame branch below when a dropdown box is recognised --
		-- the recursion guard at the bottom must skip its own art/button
		-- children the same way it already skips Button/CheckButton.
		local isDropDown = false

		if okType and not skip then
			if kidType == "EditBox" then
				-- ...but NOT one that lives inside a ScrollFrame. A scrolled
				-- edit box (`MacroFrameText`, multiLine, inside
				-- `MacroFrameScrollFrame`) has no fixed footprint: it grows
				-- with its content and slides under the scroll frame's clip
				-- rect, so a backdrop on it would be a light slab that
				-- scrolls with the text instead of a field. Blizzard always
				-- pairs such a box with a separate holder frame that DOES
				-- have the field's geometry (`MacroFrameTextBackground`) --
				-- that's what gets `S:CreateField`, at the call site that
				-- knows about it.
				local okParent, parent = pcall(kid.GetParent, kid)
				local okPType, pType = false, nil
				if okParent and parent then okPType, pType = pcall(parent.GetObjectType, parent) end
				if not (okPType and pType == "ScrollFrame") then
					S:StyleEditBox(kid)
				end
			elseif kidType == "Button" and IsTabButton(kid, okName and kidName) then
				-- TABS, recognised STRUCTURALLY -- must come BEFORE the
				-- generic Button branch, which would otherwise style a tab
				-- as an ordinary panel button (needed for Interface
				-- Options).
				--
				-- Why the sweep and not a per-name call like every earlier
				-- window: this window's tab set is not vanilla's. The live
				-- measurement found `UIOptionsFrameTab1/2/3` where real
				-- 1.12.1 has two -- the third (`DiscordPrivacyOptions`) is
				-- this server's own addition -- and nothing says a fourth
				-- won't appear. A hardcoded count is exactly what can't
				-- survive that; the `$parentMiddle` fingerprint can.
				SweepCount("tabsSeen")
				if HadRun(kid) then
					SweepCount("tabsAlready")
				else
					SweepCount("tabsNew")
					S:StyleTab(kid, sweepTabInsetX)
				end
			elseif kidType == "Button" then
				SweepCount("buttonsSeen")
				local hadRun = HadRun(kid)
				if HasNativeArt(kid, PANEL_BUTTON_ART) then
					SweepCount("buttonsNew")
					S:StyleUIPanelButton(kid)
				elseif hadRun then
					SweepCount("buttonsAlready")
				else
					SweepCount("buttonsUnrecognized")
				end
			elseif kidType == "CheckButton" then
				SweepCount("checkBoxesSeen")
				-- Debug-only capability probe for the one assumption
				-- `S:InstallCheckMark` rests on: our own
				-- accent-square mark MIRRORS `GetChecked()`, so a getter
				-- that exists but always answers nil would leave every
				-- checkbox looking permanently unchecked. Counting the
				-- checked ones here means a single debug screenshot
				-- settles it -- the numbers must match what the window
				-- visibly shows.
				if sweepStats then
					local okChecked, isChecked = pcall(kid.GetChecked, kid)
					if not okChecked then
						SweepCount("checkBoxesNoGetter")
					elseif isChecked then
						SweepCount("checkBoxesChecked")
					end
					-- Is the frame square, or does it reach under its own
					-- label? That decides how far the tick-covering patch
					-- may extend (`S:InstallCheckMark`), and it was guessed
					-- at once already -- one number settles it.
					if not sweepStats.cbSize then
						local okCW, cw = pcall(kid.GetWidth, kid)
						local okCH, ch = pcall(kid.GetHeight, kid)
						sweepStats.cbSize = string.format("%dx%d",
							(okCW and tonumber(cw)) or 0, (okCH and tonumber(ch)) or 0)
					end
				end
				local hadRun = HadRun(kid)
				if HasNativeArt(kid, CHECKBOX_ART) then
					SweepCount("checkBoxesNew")
					S:StyleCheckBox(kid)
				elseif hadRun then
					SweepCount("checkBoxesAlready")
				else
					SweepCount("checkBoxesUnrecognized")
				end
			elseif kidType == "Slider" then
				-- Two DIFFERENT slider templates share the `Slider` widget
				-- type, told apart structurally, not by name: this project
				-- can't trust a given window's FrameXML names once the
				-- window turns out to be customised, so the template is
				-- detected rather than a variable/frame name hardcoded.
				-- `FauxScrollFrameTemplate`'s scrollbar has
				-- `$parentScrollUpButton`/`$parentScrollDownButton`
				-- children; a plain `OptionsSliderTemplate` volume/generic
				-- slider has neither. The `ScrollBar`-in-the-name check
				-- stays as a cheap first hit (every scrollbar skinned so
				-- far matches it), the structural check is what actually
				-- decides when a window doesn't name it that way.
				SweepCount("slidersSeen")
				local hadRun = HadRun(kid)
				local hasScrollButtons = okName and kidName
					and (_G[kidName.."ScrollUpButton"] or _G[kidName.."ScrollDownButton"])
				if hasScrollButtons or (okName and kidName and string.find(kidName, "ScrollBar", 1, true)) then
					S:HandleScrollBar(kid)
				else
					S:StyleOptionsSlider(kid)
				end
				if hadRun then SweepCount("slidersAlready") else SweepCount("slidersNew") end
			elseif kidType == "StatusBar" then
				-- No template identification needed, unlike Button/
				-- CheckButton: the widget TYPE alone says what this is, and
				-- every window that wants a bar styled differently already
				-- calls its own named function before the sweep ever runs.
				SweepCount("barsSeen")
				local hadRun = HadRun(kid)
				S:StyleStatusBar(kid)
				if hadRun then SweepCount("barsAlready") else SweepCount("barsNew") end
			elseif kidType == "Frame" then
				-- A closed dropdown box (`UIDropDownMenuTemplate`) is an
				-- ordinary Frame, not a distinct widget type. Gated on BOTH
				-- the template's own box art (direct regions, so this reads
				-- even on an unnamed dropdown) AND a `$parentButton` Button
				-- child actually existing -- the art alone isn't enough,
				-- since the same label-frame asset is also used by plain,
				-- non-interactive decorative boxes elsewhere, which must be
				-- left alone rather than mis-skinned as a dropdown.
				--
				-- SECOND FINGERPRINT -- and it is what makes
				-- this branch work on the LEGACY client at all.
				--
				-- On legacy (Video Options), dropdown arrows fail to skin.
				-- Measured from the screenshot rather
				-- than guessed: the dropdown's text is pure white (255,255,255)
				-- there and `ACCENT_COLOR` (255,209,0) on UA -- i.e. it is not
				-- the arrow that is missing, `S:StyleDropDownBox` never ran on
				-- that client at all.
				--
				-- The mechanism follows from the differential, with no theory
				-- left over: buttons, checkboxes and sliders in the SAME window
				-- are correctly skinned on legacy, and they are identified by
				-- exactly the same `HasNativeArt` call. The one thing that
				-- separates a dropdown from all of them is its TYPE -- it is a
				-- plain `Frame`, and `S:StripTextures` walks into Frames while
				-- deliberately never descending into a Button/CheckButton. So
				-- by the time the sweep asks a dropdown what art it carries,
				-- THIS MODULE has already cleared it -- on legacy, where
				-- `SetTexture(nil)` genuinely works. On UA it does not, which is
				-- the only reason the art check has ever matched there.
				--
				-- The fix is not to reorder the strip (its recursion into
				-- Frames is load-bearing for every group box and nested panel)
				-- but to add a fingerprint the strip cannot destroy: the
				-- template's own NAME SHAPE. `UIDropDownMenuTemplate` always
				-- builds `$parentButton` + `$parentText` + `$parentMiddle`, and
				-- names survive everything. Same reasoning as `IsTabButton`'s
				-- `$parentMiddle` test -- naming is the stable part, art isn't.
				--
				-- The art path stays as the OTHER alternative, not a
				-- replacement: a dropdown built from the client's own Lua
				-- rather than from the XML template may name only its button
				-- (Sound Options' microphone box is exactly that, and it is
				-- live-accepted), and that one is still caught by its art.
				local ddNamed = okName and kidName and _G[kidName.."Button"]
				local ddShape = ddNamed and _G[kidName.."Text"] and _G[kidName.."Middle"]
				if ddShape or (ddNamed and HasNativeArt(kid, DROPDOWN_ART)) then
					SweepCount("dropdownsSeen")
					local hadRun = HadRun(kid)
					S:StyleDropDownBox(kid)
					if hadRun then SweepCount("dropdownsAlready") else SweepCount("dropdownsNew") end
					isDropDown = true
				elseif sweepStats then
					-- Debug-only (Sound Options "Voice Chat Settings" box
					-- class of frame): a plain Frame that ISN'T a
					-- recognised dropdown might still be a grouping
					-- sub-panel carrying native chrome of its own --
					-- exactly the "never SetBackdrop a native frame"
					-- situation every other window has hit, just not
					-- identified by name yet. Reported here, unprompted,
					-- because a live `/run` probe (`S:DumpMouseFocus`)
					-- can't reach a keyboard-enabled modal window while
					-- it's actually shown -- this debug print is the only
					-- channel that works while the window is open. Checks
					-- BOTH known ways native chrome survives on this
					-- client: a `<Backdrop>` tag (what `S:StripTextures`
					-- clears unconditionally, so seeing one here means its
					-- OWN recursive walk never reached this frame -- a
					-- real bug worth chasing) and a still-visible Texture
					-- region (the `CharacterFrame` gold-ring case -- art
					-- that was never a `<Backdrop>` at all, so clearing
					-- one wouldn't have helped regardless).
					-- `elvBackdropNeutralized` (see `S:ClearNativeBackdrop`):
					-- a frame whose uncleanable native backdrop was
					-- REPLACED with this module's own fully-transparent
					-- one still answers `GetBackdrop()` with a table, so
					-- without this it would report itself as native chrome
					-- forever. Reported on its own line instead, since
					-- "the fallback had to run here" is still worth seeing.
					local okBackdrop, backdrop = pcall(kid.GetBackdrop, kid)
					local hasBackdrop = okBackdrop and backdrop and not kid.elvBackdropNeutralized and true or false
					if kid.elvBackdropNeutralized then
						E:Print(string.format("  Frame native backdrop neutralised (SetBackdrop(nil) did nothing): %s",
							tostring(okName and kidName or "<unnamed>")))
					end

					local hasVisibleTexture = false
					local okRegions, regions = pcall(function() return { kid:GetRegions() } end)
					if okRegions and type(regions) == "table" then
						local ri
						for ri = 1, table.getn(regions) do
							local okRType, rType = pcall(regions[ri].GetObjectType, regions[ri])
							if okRType and rType == "Texture" then
								local okShown, shown = pcall(regions[ri].IsShown, regions[ri])
								if okShown and shown and TexturePath(regions[ri]) then
									hasVisibleTexture = true
								end
							end
						end
					end

					if hasBackdrop or hasVisibleTexture then
						SweepCount("framesWithBackdrop")
						E:Print(string.format("  Frame with native chrome still present: %s (backdrop=%s texture=%s)",
							tostring(okName and kidName or "<unnamed>"), tostring(hasBackdrop), tostring(hasVisibleTexture)))
					end
				end
			end
		end

		-- Same recursion policy as `S:StripTextures`: never descend into a
		-- Button/CheckButton (their insides belong to their own dedicated
		-- styling function), and honour the skip list. A scrolled EditBox
		-- IS still walked (its own children, if any, are ordinary widgets)
		-- -- only its own backdrop was skipped above.
		if okType and kidType ~= "Button" and kidType ~= "CheckButton" and not isDropDown and not skip then
			S:SkinChildren(kid, depth + 1)
		end
	end

	if depth == 0 and sweepStats then
		local okName, frameName = pcall(frame.GetName, frame)
		-- `new` = matched a recognised native template THIS run (just
		-- styled). `already` = seen, didn't match, but this project's own
		-- code touched it on an earlier pass (harmless -- its own native
		-- art is already gone, see `HadRun`'s own comment). `unrecog` =
		-- seen, didn't match, NEVER touched before -- the one number that
		-- actually means "still native, sweep doesn't know what this is".
		E:Print(string.format("Skins sweep %s: children=%d", tostring(okName and frameName or "<unnamed>"), kidCount))
		E:Print(string.format("  buttons new=%d already=%d unrecog=%d seen=%d",
			sweepStats.buttonsNew or 0, sweepStats.buttonsAlready or 0,
			sweepStats.buttonsUnrecognized or 0, sweepStats.buttonsSeen or 0))
		E:Print(string.format("  checkboxes new=%d already=%d unrecog=%d seen=%d",
			sweepStats.checkBoxesNew or 0, sweepStats.checkBoxesAlready or 0,
			sweepStats.checkBoxesUnrecognized or 0, sweepStats.checkBoxesSeen or 0))
		E:Print(string.format("  dropdowns new=%d already=%d seen=%d",
			sweepStats.dropdownsNew or 0, sweepStats.dropdownsAlready or 0, sweepStats.dropdownsSeen or 0))
		E:Print(string.format("  sliders new=%d already=%d seen=%d",
			sweepStats.slidersNew or 0, sweepStats.slidersAlready or 0, sweepStats.slidersSeen or 0))
		E:Print(string.format("  statusbars new=%d already=%d seen=%d",
			sweepStats.barsNew or 0, sweepStats.barsAlready or 0, sweepStats.barsSeen or 0))
		E:Print(string.format("  tabs new=%d already=%d seen=%d",
			sweepStats.tabsNew or 0, sweepStats.tabsAlready or 0, sweepStats.tabsSeen or 0))
		E:Print(string.format("  checkbox state: checked=%d nogetter=%d size=%s",
			sweepStats.checkBoxesChecked or 0, sweepStats.checkBoxesNoGetter or 0,
			tostring(sweepStats.cbSize or "?")))
		-- Flushed LAST so the per-slider measurements are the lines still
		-- on screen when the chat frame scrolls -- see their own note in
		-- `S:StyleOptionsSlider`.
		if S.sliderDebugLines then
			local si
			for si = 1, table.getn(S.sliderDebugLines) do
				E:Print(S.sliderDebugLines[si])
			end
			S.sliderDebugLines = nil
		end
		sweepStats = nil
	end
end

-- ===================================================================
-- `S:WhyNotSkinned(name)` -- the ONE command for an odd-looking widget
-- ===================================================================
--   /run ElvUI[1]:GetModule("Skins"):WhyNotSkinned("GameMenuButtonQuit")
--
-- Since the sweep now does the skinning everywhere, the only question
-- worth asking in game is "why did it skip THIS one" -- so that is the
-- only thing this prints, in four short lines: what the widget is, what
-- the sweep can read off it, whether that adds up to a recognised
-- template, and whether the widget is reachable the way the sweep reaches
-- it (through `GetChildren()`, which on this client hands back a crippled
-- object -- see `S:ResolveWidget`).
--
-- Deliberately replaces the SavedVariables dump that found the original
-- bug: that was a one-off measuring rig, and this file already carries
-- more debug surface than it should. `S:DumpButton(name)` remains for the
-- rarer "several textures stacked on one button" hunt.
function S:WhyNotSkinned(name)
	local widget = _G[name]
	if not widget then E:Print(tostring(name)..": no such global") return end

	local okType, widgetType = pcall(widget.GetObjectType, widget)
	widgetType = (okType and widgetType) or "?"
	E:Print(string.format("%s: type=%s alreadyStyled=%s", tostring(name),
		tostring(widgetType), tostring(widget.elvStyled and true or false)))

	local function slot(getter)
		local ok, texture = pcall(widget[getter], widget)
		if not ok then return "no-method" end
		if not texture then return "nil" end
		local okPath, path = pcall(texture.GetTexture, texture)
		if not okPath or type(path) ~= "string" or string.len(path) == 0 then return "no-path" end
		return path
	end
	E:Print("  normal="..slot("GetNormalTexture").." pushed="..slot("GetPushedTexture"))
	E:Print("  highlight="..slot("GetHighlightTexture"))

	local fragment = PANEL_BUTTON_ART
	if widgetType == "CheckButton" then fragment = CHECKBOX_ART end
	if HasNativeArt(widget, fragment) then
		E:Print("  recognised as "..fragment.." -> the sweep WILL style it")
	else
		E:Print("  NOT recognised as "..fragment..". This client says that family is:")
		local path
		for path in pairs(TemplateArt(fragment)) do E:Print("    "..path) end
	end

	-- The trap that cost this project a whole window: what the sweep gets
	-- from the parent's enumeration is not necessarily this object.
	local okParent, parent = pcall(widget.GetParent, widget)
	if okParent and parent then
		local okKids, kids = pcall(function() return { parent:GetChildren() } end)
		local found = "not in parent's GetChildren()"
		if okKids and type(kids) == "table" then
			local i
			for i = 1, table.getn(kids) do
				local okKidName, kidName = pcall(kids[i].GetName, kids[i])
				if okKidName and kidName == name then
					found = "enumerated same-object="..tostring(kids[i] == widget)
						.." resolved="..tostring(self:ResolveWidget(kids[i]) == widget)
					break
				end
			end
		end
		local okPName, parentName = pcall(parent.GetName, parent)
		E:Print("  parent="..tostring(okPName and parentName or "<unnamed>").." "..found)
	end
end

-- Registry -- a skin file calls S:AddBlizzardSkin("character", LoadSkin)
-- at load time instead of running immediately, matching real ElvUI's own
-- S:AddCallback shape (the key doubles as the E.private.skins.blizzard[key]
-- lookup), simplified to just what's needed here (no dependency-ordering,
-- no re-apply-on-event -- add if a future skin actually needs it).
--
-- Each key holds a LIST of functions, not one: real ElvUI's own `quest`
-- flag covers both `QuestLogFrame` and `QuestFrame` from a single file,
-- but this project split them into `QuestLog.lua` and `Quest.lua` while
-- keeping the one shared flag (so an imported profile's `quest` toggle
-- still means the same thing) -- so two different files register under
-- the same key, and a plain single-slot table would let the second
-- registration silently replace the first, dropping that window's skin
-- entirely with no error. A list keeps every registrant.
S.blizzardSkins = S.blizzardSkins or {}
function S:AddBlizzardSkin(key, func)
	local list = self.blizzardSkins[key]
	if not list then
		list = {}
		self.blizzardSkins[key] = list
	end
	list[table.getn(list) + 1] = func
end

-- ===================================================================
-- `S:WaitForGlobal(name, func)` -- LoadOnDemand windows without the flash
-- ===================================================================
-- The Macro window flashed unskinned for 1-2 seconds before the design
-- applied. Root cause was not the skin at all -- it was WHEN it ran.
-- `Blizzard_MacroUI` is `## LoadOnDemand: 1`,
-- so `MacroFrame` doesn't exist at login; Macro.lua waited for it with a
-- plain `E:ScheduleRepeatingTimer(..., 1)`. Blizzard's own `MacroFrame_LoadUI`
-- loads the addon and then IMMEDIATELY `ShowUIPanel()`s the frame in the
-- same call, so the native window is on screen for up to a full second
-- before the next poll tick even looks at it. The delay WAS the poll
-- interval.
--
-- Two mechanisms, deliberately, because either one alone is a guess about
-- this client:
--
--  1. **`ADDON_LOADED`** -- fires DURING `LoadAddOn`, i.e. synchronously
--     BEFORE the native code gets to `ShowUIPanel`, so the skin is already
--     applied by the time the window is first drawn: no flash at all, not
--     just a shorter one. This is also real ElvUI's own mechanism
--     (`S:ADDON_LOADED` + `S:AddCallbackForAddon`,
--     source/ElvUI-vanilla/ElvUI/Modules/Skins/Skins.lua:480,529,633).
--     Note what this deliberately does NOT do: real ElvUI keys off the
--     `arg1` payload to find out WHICH addon loaded. This project has a
--     standing finding that its AceEvent-3.0 copy forwards no event
--     payload, so relying on that would
--     be building on the one thing already known to be missing. Instead
--     every pending entry is simply re-checked on ANY ADDON_LOADED -- the
--     check is a `_G[name]` lookup, so the cost of not knowing is nil.
--  2. **A 0.1s poll** as the backstop, for the real possibility that UA
--     doesn't fire `ADDON_LOADED` for on-demand addons the way real
--     vanilla does -- exactly this project's established "periodic
--     re-check over trusting event delivery" pattern. It self-cancels the
--     moment the last pending entry resolves, so it is not a standing
--     per-tick cost.
--
-- The callback fires exactly once per registration and is `pcall`'d, so a
-- failing skin can't take the dispatcher (or the other pending entries)
-- down with it.
S.pendingGlobals = S.pendingGlobals or {}

local pendingPollHandle = nil
local addonLoadedRegistered = false

-- Player-facing notice for any window skin that failed to install. Printed
-- at most once per session: several windows can fail for the same underlying
-- reason, and the message names the visible effect, not the technical cause.
local skinProblemReported = false
function S:ReportSkinProblem()
	if skinProblemReported then return end
	skinProblemReported = true
	E:Print(L["Some windows could not be restyled and keep their default look."])
end

local function FlushPendingGlobals()
	-- Walk BACKWARDS: entries are removed in place as they resolve, and a
	-- forward loop would skip the element that slides into the freed slot.
	local i
	for i = table.getn(S.pendingGlobals), 1, -1 do
		local entry = S.pendingGlobals[i]
		if entry and _G[entry.name] then
			table.remove(S.pendingGlobals, i)
			local ok = pcall(entry.func)
			if not ok then
				S:ReportSkinProblem()
			end
		end
	end

	if pendingPollHandle and table.getn(S.pendingGlobals) == 0 then
		E:CancelTimer(pendingPollHandle)
		pendingPollHandle = nil
	end
end

-- AceEvent-3.0 callback. Ignores every argument on purpose -- see above.
function S:OnAddonLoaded()
	pcall(FlushPendingGlobals)
end

function S:WaitForGlobal(name, func)
	if not name or type(func) ~= "function" then return end

	-- Already there (a non-LoadOnDemand window, or a second caller after
	-- the addon loaded): run it now, don't wait a tick for no reason.
	if _G[name] then
		local ok = pcall(func)
		if not ok then S:ReportSkinProblem() end
		return
	end

	table.insert(S.pendingGlobals, { name = name, func = func })

	if not addonLoadedRegistered then
		-- pcall'd, and the latch only set on SUCCESS: a throwing
		-- registration must not abort the rest of this function (that
		-- would take the poll backstop below down with it), and a failed
		-- attempt must stay retryable -- the "guard latches only on
		-- success" rule this project already had to learn the hard way.
		local ok = pcall(function() S:RegisterEvent("ADDON_LOADED", "OnAddonLoaded") end)
		if ok then addonLoadedRegistered = true end
	end

	if not pendingPollHandle then
		pendingPollHandle = E:ScheduleRepeatingTimer(FlushPendingGlobals, 0.1)
	end
end

-- Generic native dropdown-menu skin, alongside
-- the Title dropdown (`Blizzard/Character.lua`'s own
-- `StylePlayerTitleDropDown`): the dropdown's own list items need
-- templating too. `DropDownList1`/`2`/`3` (matches
-- `UIDROPDOWNMENU_MAXLEVELS`) is the SAME shared, generic list frame
-- used by EVERY dropdown menu in the whole game -- not specific to the
-- Title dropdown at all, so this is a global skin, matching real ElvUI's
-- own actual scope for this exact feature (confirmed via
-- `source/ElvUI-vanilla/ElvUI/Modules/Skins/Blizzard/Misc.lua:64-95`,
-- which hooks `UIDropDownMenu_Initialize` -- a GLOBAL function, 2-arg
-- bare-name `hooksecurefunc` overload, the SAME form already confirmed
-- reliable elsewhere in this project e.g. Castbar's own icon-capture
-- hook on `CastSpell` -- unlike the object-method 3-arg overload, which
-- is confirmed broken on UA). Real names cross-checked against the
-- actual FrameXML (`UIDropDownMenu.xml`/`UIDropDownMenuTemplates.xml`):
-- `DropDownList<i>Backdrop`/`MenuBackdrop` (two backdrop child frames),
-- `DropDownList<i>Button<j>` (up to `UIDROPDOWNMENU_MAXBUTTONS` = 32
-- entries per level) and each button's own `...Highlight` region.
--
-- The global dropdown-menu design (a transparent frame with a thin black
-- border and a light grey item list) needed to match this project's own
-- design instead of the native one. Three separate problems, all in the
-- ORIGINAL version of this function:
--
-- 1. **The whole styling pass could silently never run.** The hook body
--    opened with `for i = 1, UIDROPDOWNMENU_MAXLEVELS do`. That global is
--    FrameXML-defined, and this project has repeatedly found FrameXML
--    globals missing on UA (`ReputationFrame_Update`,
--    `SkillFrame_UpdateSkills`, `hooksecurefunc` itself...). If it is nil
--    here, `for i = 1, nil` raises immediately, and since the hook body
--    itself was never `pcall`'d, EVERY call died on line one with no
--    message -- the exact "an unguarded call kills the whole chain"
--    failure this project has already been burned by twice. Fixed:
--    literal fallbacks (3 / 32, the real vanilla values) and a `pcall`
--    around the body.
-- 2. **It only ever ran from the hook.** `DropDownList1-3` are persistent
--    global frames created by FrameXML at startup -- exactly like
--    `StaticPopup1-4`, which this file already skins with a ONE-TIME
--    load-time pass for precisely this reason. So the pass now runs once
--    at load as well, and the hook only exists to catch frames/buttons
--    that get created or reset later. If the hook can't be installed at
--    all, the menu is still skinned.
-- 3. **The native art was replaced but never cleared.** `SetBackdrop`
--    with a new table is the only thing that used to happen; anything the
--    native backdrop drew outside that table's own bounds (the dialog
--    frame's 32px tiled edge, the menu variant's tooltip border) had
--    nothing telling it to stop. Now the native backdrop is explicitly
--    nil'd first, and the insets are zeroed, so what renders is only ours.
local dropDownMenuSkinInstalled = false

-- Backdrop tuned to match this project's own panel recipe verbatim (the
-- `elvBackground` child frame every skinned window uses: WHITE8x8 bg +
-- 1px WHITE8x8 edge, 0.05 grey at 0.95 alpha, pure black border) so a
-- dropdown reads as part of the same UI as the windows behind it. Real
-- ElvUI reaches the same look through `E:SetTemplate(frame,
-- "Transparent")`. That helper now exists here too (Core/Util.lua), but it
-- reads the GENERAL backdrop colors, whereas a dropdown has to match the
-- Skins module's own panel tone -- hence the explicit recipe below.
local function StyleDropDownBackdrop(frame)
	if not frame then return end

	-- Clear FIRST. `UIDropDownListTemplate` declares real backdrops in XML
	-- (`UI-DialogBox-Background`/`-Border` with a 32px edge and 11/12px
	-- insets for `$parentBackdrop`, `UI-Tooltip-Background`/`-Border` with
	-- a 16px edge for `$parentMenuBackdrop` -- both confirmed in
	-- source/wow-ui-source/FrameXML/UIDropDownMenuTemplates.xml:157-190),
	-- and a fresh SetBackdrop that doesn't mention insets inherits nothing
	-- but also guarantees nothing about what the old one left behind.
	pcall(frame.SetBackdrop, frame, nil)
	-- Exactly the 3-key shape every other SetBackdrop in this project uses
	-- (bgFile + edgeFile + edgeSize, never bgFile alone). No `insets` key:
	-- it would be more "complete", but it is an UNTESTED table shape on
	-- this client, and `SetBackdrop` is the one call already known to fall
	-- back to a gold/tan placeholder here when handed a table it doesn't
	-- like (Core/Util.lua's own CreateButtonBorder history). Not worth the
	-- risk on a frame this global -- the native insets go away with the
	-- old table anyway, since it's replaced wholesale.
	pcall(frame.SetBackdrop, frame, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(frame.SetBackdropColor, frame, S.PANEL_COLOR[1], S.PANEL_COLOR[2], S.PANEL_COLOR[3], S.PANEL_COLOR[4])
	pcall(frame.SetBackdropBorderColor, frame, S.BORDER_COLOR[1], S.BORDER_COLOR[2], S.BORDER_COLOR[3], S.BORDER_COLOR[4])
end

-- The whole per-frame pass, split out of the hook body so the one-time
-- load-time call and the hook can share it. Idempotent throughout
-- (`elvStyled` guards on the backdrops, the button work is cheap and
-- value-identical on repeat), so calling it on every
-- `UIDropDownMenu_Initialize` costs nothing.
-- A change of MECHANISM, not a tweak to the same one. **CONFIRMED WORKING
-- LIVE.** Measured: the menu background is RGB 57,57,57 before a plain
-- `SetBackdropColor` fix and RGB 58,58,58 after it. The intended colour is
-- 0.05 grey = RGB 13. So calling `SetBackdrop`/`SetBackdropColor` on the
-- native frame has literally ZERO effect on this widget -- a fact, not an
-- impression.
--
-- What that approach has in common with every other failure of this
-- shape: it MODIFIES a pre-existing native frame. That is this project's
-- single most-repeated failure mode, and its documented answer is not a
-- better modification -- it is to CREATE something new and let that be
-- what renders (same arc as the `button.elvIcon` fix for the SpellBook
-- page arrows: reassigning native texture slots does nothing, an own
-- texture on an own child frame works immediately).
--
-- So: an `elvBackground` child frame on the list itself, the same recipe
-- every skinned window in this addon uses, layered ABOVE whatever the list
-- draws for itself and BELOW the buttons. If the grey is painted by the
-- native backdrop children, killing them (below) removes it; if it is
-- painted by the list frame itself or by something on the UA side that Lua
-- can't reach, the new frame covers it. Both cases are handled without
-- needing to know which one is true -- which is the point, since three
-- rounds have not established that.
local function StyleDropDownList(list)
	if not list then return end

	local okLevel, level = pcall(list.GetFrameLevel, list)
	local listLevel = (okLevel and tonumber(level)) or 1

	-- OPEN QUESTION being measured here, not guessed at: the Sound Options
	-- microphone dropdown's own menu can fail to open at all -- clicking
	-- the arrow appears to do nothing. Two candidate
	-- causes, and this one print separates them without any code change on
	-- the next round: if a line shows up when the arrow is clicked, the menu
	-- IS initialising and the problem is purely that it renders behind the
	-- window; if nothing prints, the click never reaches the button (or this
	-- client's own custom dropdown doesn't route through
	-- `UIDropDownMenu_Initialize` at all, in which case none of this
	-- module's list styling has ever applied to it either).
	-- Gated on IsShown: this function also runs on
	-- the one-time install sweep over `DropDownList1-3`, and printing there
	-- put SIX uninteresting lines into the chat frame on every window open --
	-- enough to push the actually useful measurements off the top of a chat
	-- frame that can't be scrolled back reliably here. A hidden list says
	-- nothing; a SHOWN one is the whole question.
	if S.autoSkinDebug then
		local okShown, shown = pcall(list.IsShown, list)
		if okShown and shown then
			local okName, listName = pcall(list.GetName, list)
			local okStrata, strata = pcall(list.GetFrameStrata, list)
			E:Print(string.format("  DropDownList init (SHOWN): %s strata=%s level=%d",
				tostring(okName and listName or "<unnamed>"),
				tostring(okStrata and strata or "?"), listLevel))
		end
	end

	-- LIKELY FIX for the same report, shipped alongside the measurement
	-- because it is cheap and self-limiting. `UIDropDownListTemplate` sits
	-- at `DIALOG` strata (UIDropDownMenuTemplates.xml:157) -- the SAME
	-- strata as `SoundOptionsFrame` (SoundOptionsFrame.xml:18, and it is
	-- `toplevel="true"` on top of that, so it actively raises its own level
	-- within the strata when clicked). Between equal strata this project's
	-- own rule applies: at the same frame level, the LATER-CREATED frame
	-- renders on top -- and every surface this module draws is created at runtime, i.e. later
	-- than any native list. A menu is a popup and belongs above dialogs
	-- regardless; `FULLSCREEN_DIALOG` is where later WoW versions put these
	-- exact frames. Only ever raises a list still sitting at plain DIALOG,
	-- so anything another addon has deliberately placed elsewhere is left
	-- alone.
	local okStrata, strata = pcall(list.GetFrameStrata, list)
	if okStrata and strata == "DIALOG" then
		pcall(list.SetFrameStrata, list, "FULLSCREEN_DIALOG")
	end

	if not list.elvBackground then
		local okBG, bg = pcall(CreateFrame, "Frame", nil, list)
		if okBG and bg then
			pcall(bg.SetAllPoints, bg, list)
			pcall(bg.EnableMouse, bg, false)
			bg.elvSurface = true
			list.elvBackground = bg
		end
	end

	local bg = list.elvBackground
	if bg then
		-- Re-asserted every pass, not once: same reasoning as the backdrops
		-- below, and the level in particular has to be re-applied because
		-- `ToggleDropDownMenu` re-parents/re-levels list frames per menu.
		pcall(bg.SetFrameLevel, bg, listLevel + 1)
		-- Colors from the shared tokens; the FRAME itself is
		-- still built inline here rather than via `S:CreateSurface`,
		-- because unlike every other surface in this file it has to
		-- RE-ASSERT its backdrop and level on every pass (see the note
		-- above -- `ToggleDropDownMenu` re-parents and re-levels these list
		-- frames per menu), which is exactly what CreateSurface's
		-- create-once guard is designed not to do.
		pcall(bg.SetBackdrop, bg, S.PLAIN_BACKDROP)
		pcall(bg.SetBackdropColor, bg, S.PANEL_COLOR[1], S.PANEL_COLOR[2], S.PANEL_COLOR[3], S.PANEL_COLOR[4])
		pcall(bg.SetBackdropBorderColor, bg, S.BORDER_COLOR[1], S.BORDER_COLOR[2], S.BORDER_COLOR[3], S.BORDER_COLOR[4])
		pcall(bg.Show, bg)
	end

	return listLevel
end

-- The selected-entry marker: the selected dropdown item should not be
-- marked with the Blizzard checkmark, but with something matching this
-- project's own design instead.
--
-- Checked: real ElvUI-vanilla's own dropdown block
-- (Modules/Skins/Blizzard/Misc.lua:64-95) handles the button, the
-- highlight and the colour swatch, and leaves `$parentCheck` completely
-- untouched -- there is no reference answer to port. So this is a
-- deliberate choice in this addon's own visual language rather than a
-- port: a small square in the accent gold already used for every tab
-- label, close button and panel title here. Say the word and it becomes
-- something else -- it's two numbers and a colour.
--
-- Mechanism matters as much as the look. `$parentCheck` is a plain
-- ARTWORK-layer Texture that Blizzard's own `UIDropDownMenu_AddButton`
-- Show/Hide's per entry, so its SHOWN STATE is the source of truth for
-- "this is the selected one". That state is read, then the native texture
-- is made invisible WITHOUT noop'ing its `Show` (doing that would destroy
-- the very signal being read), and our own texture mirrors it.
local function StyleDropDownCheck(button, checkTexture, buttonLevel)
	if not button or not checkTexture then return end

	local okShown, checked = pcall(checkTexture.IsShown, checkTexture)
	checked = okShown and checked

	pcall(checkTexture.SetTexture, checkTexture, nil)
	pcall(checkTexture.SetAlpha, checkTexture, 0)

	if not button.elvCheckHolder then
		local okHolder, holder = pcall(CreateFrame, "Frame", nil, button)
		if okHolder and holder then
			pcall(holder.SetAllPoints, holder, button)
			pcall(holder.EnableMouse, holder, false)
			local okMark, mark = pcall(holder.CreateTexture, holder, nil, "OVERLAY")
			if okMark and mark then
				pcall(mark.SetTexture, mark, "Interface\\Buttons\\WHITE8x8")
				pcall(mark.SetWidth, mark, 6)
				pcall(mark.SetHeight, mark, 6)
				pcall(mark.SetPoint, mark, "LEFT", holder, "LEFT", 6, 0)
				pcall(mark.SetVertexColor, mark, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
				button.elvCheckHolder = holder
				button.elvCheck = mark
			end
		end
	end

	if button.elvCheckHolder then
		pcall(button.elvCheckHolder.SetFrameLevel, button.elvCheckHolder, buttonLevel + 1)
	end
	if button.elvCheck then
		if checked then
			pcall(button.elvCheck.Show, button.elvCheck)
		else
			pcall(button.elvCheck.Hide, button.elvCheck)
		end
	end
end

function S:ApplyDropDownMenuChrome()
	-- Literal fallbacks, see point 1 in this section's header comment.
	local maxLevels = tonumber(_G.UIDROPDOWNMENU_MAXLEVELS) or 3
	local maxButtons = tonumber(_G.UIDROPDOWNMENU_MAXBUTTONS) or 32

	local i
	for i = 1, maxLevels do
		local list = _G["DropDownList"..i]
		local listLevel = StyleDropDownList(list) or 1

		local backdrop = _G["DropDownList"..i.."Backdrop"]
		local menuBackdrop = _G["DropDownList"..i.."MenuBackdrop"]

		-- The native backdrop frames are now KILLED outright rather than
		-- re-backdropped: `list.elvBackground` above is what draws the panel,
		-- so anything these two still render can only be the lighter grey
		-- showing through. `S:Kill`'s permanently-noop'd `Show` is correct
		-- here -- `ToggleDropDownMenu` calls `:Show()` on whichever one the
		-- current displayMode selects, on every single open.
		S:Kill(backdrop)
		S:Kill(menuBackdrop)

		-- Kept as a belt-and-braces second mechanism, no longer the primary
		-- one, and with NO `elvStyled` one-time latch:
		-- `$parentMenuBackdrop`'s own XML `<OnLoad>` calls
		-- `SetBackdropColor`/`SetBackdropBorderColor` on itself
		-- (UIDropDownMenuTemplates.xml:184-189), so it demonstrably belongs
		-- to the "re-asserts its own look on show" family, and a one-time
		-- assignment would be undone. Costs 6 SetBackdrop calls per open.
		StyleDropDownBackdrop(backdrop)
		StyleDropDownBackdrop(menuBackdrop)

		-- Buttons sit above `list.elvBackground` (listLevel + 1), never
		-- again relative to the native backdrop frames -- those are killed
		-- now, and a level derived from a hidden frame is not a level worth
		-- trusting.
		local buttonLevel = listLevel + 3

		local j
		for j = 1, maxButtons do
			local button = _G["DropDownList"..i.."Button"..j]
			local highlight = _G["DropDownList"..i.."Button"..j.."Highlight"]
			local check = _G["DropDownList"..i.."Button"..j.."Check"]
			if button then
				pcall(button.SetFrameLevel, button, buttonLevel)
				StyleDropDownCheck(button, check, buttonLevel)
			end
			-- Flat white-alpha fill, matching real ElvUI's own exact
			-- trick here (and already reused this same session for
			-- the model rotate buttons' own highlight) instead of a
			-- separate highlight asset.
			--
			-- `$parentHighlight` is NOT a HighlightTexture slot despite
			-- the name -- it's a plain BACKGROUND-layer Texture declared
			-- `hidden="true"`, which Blizzard's own UIDropDownMenu.lua
			-- Shows/Hides by hand from the button's OnEnter/OnLeave
			-- (confirmed in UIDropDownMenuTemplates.xml:7-10). So none of
			-- the "HIGHLIGHT draw layer semantics don't hold on UA"
			-- problem that broke `S:HandleButtonHighlight` on the Friends
			-- rows applies here: this one is driven by explicit native
			-- Show/Hide calls, not by the engine's highlight state.
			if highlight and button then
				pcall(highlight.SetTexture, highlight, 1, 1, 1, 0.3)
				pcall(highlight.SetAllPoints, highlight, button)
			end
		end
	end
end

function S:InstallDropDownMenuSkin()
	if dropDownMenuSkinInstalled then return end

	-- One-time pass FIRST, independent of the hook -- see point 2 above.
	local okNow = pcall(function() S:ApplyDropDownMenuChrome() end)
	if not okNow then
		S:ReportSkinProblem()
	end

	-- SECOND, INDEPENDENT TRIGGER: each list frame's own
	-- `OnShow`. The `UIDropDownMenu_Initialize` hook below is the reference
	-- implementation's trigger, but it rests on an assumption this client
	-- doesn't have to honour -- that `ToggleDropDownMenu` always calls
	-- `UIDropDownMenu_Initialize`. It does in real 1.12.1's FrameXML; UA
	-- reimplements this machinery, and if its version skips or inlines that
	-- call, the hook never fires and nothing is ever styled. `OnShow` on
	-- `DropDownList1-3` cannot be bypassed the same way: a menu that becomes
	-- visible has, by definition, been shown.
	--
	-- `S:TryHookScript`, never a bare HookScript -- AceHook's own
	-- `:HasScript` validation misfires on some frames on this client (see
	-- that function's own comment).
	local level
	for level = 1, (tonumber(_G.UIDROPDOWNMENU_MAXLEVELS) or 3) do
		local list = _G["DropDownList"..level]
		if list and not list.elvOnShowHooked then
			if S:TryHookScript(list, "OnShow", function()
				pcall(function() S:ApplyDropDownMenuChrome() end)
			end) then
				list.elvOnShowHooked = true
			end
		end
	end

	-- CONFIRMED live from REAL addon code (not just a `/run` test) that
	-- `hooksecurefunc` genuinely isn't a global function here --
	-- "hooksecurefunc is not a function", printed by this file's own
	-- diagnostic. `Modules/UnitFrames/UnitFrames.lua`'s own Castbar
	-- icon-capture code documents that bare `hooksecurefunc` was ALREADY
	-- found unreliable there too, and was replaced with AceHook-3.0's own
	-- `:SecureHook(globalName,
	-- handler)` -- the STRING-name overload (hooking a bare global
	-- function by name), not the object+method 3-arg overload (which is
	-- a SEPARATE, independently-confirmed-broken case). `S` already has
	-- AceHook-3.0 mixed in (`E:NewModule("Skins", "AceHook-3.0")`), so
	-- this reuses that same already-proven-reliable path instead of the
	-- raw global function.
	if type(_G.UIDropDownMenu_Initialize) ~= "function" then
		S:ReportSkinProblem()
		return
	end

	local ok = pcall(function()
		-- The hook body is itself `pcall`'d -- an error thrown inside a
		-- SecureHook callback is swallowed by nothing, and would take out
		-- every subsequent call with no message. That is exactly how the
		-- missing-global bug above stayed invisible.
		S:SecureHook("UIDropDownMenu_Initialize", function()
			pcall(function() S:ApplyDropDownMenuChrome() end)
		end)
	end)
	if ok then
		dropDownMenuSkinInstalled = true
	else
		S:ReportSkinProblem()
	end
end

-- Cross-cutting skin for the SHARED `StaticPopup1-4` dialog frames:
-- clicking "Add Friend" without a target selected pops one of these up
-- (`StaticPopupDialogs["ADD_FRIEND"]`, `hasEditBox = 1` -- confirmed via
-- `source/wow-ui-source/FrameXML/StaticPopup.lua:775-806`). Skinnable
-- globally, the same way the dropdown-menu skin above is, rather than
-- per-window: `StaticPopup1-4` (`STATICPOPUP_NUMDIALOGS`, 4 in real
-- vanilla) are the SAME generic, ALWAYS-EXISTING persistent frames used by
-- dozens of unrelated confirmation dialogs across the whole game (party/
-- guild invites, delete-item confirmations, ...) -- Blizzard's own
-- `StaticPopup_Show` just repopulates one of these 4 frames' CONTENT
-- (.text, which of Button1/Button2/EditBox/MoneyFrame are shown) per
-- dialog type, never creates a new frame per popup. Real recipe confirmed
-- via `source/pfUI/skins/blizzard/popup_dialogs.lua` (Shagu's pfUI, real
-- vanilla, already working) -- a ONE-TIME loop over StaticPopup1-4 at load
-- time, NO OnShow hook: `CreateBackdrop`+close/accept/cancel button skin+
-- `editbox:DisableDrawLayer("BACKGROUND")`+its own backdrop. Ported to
-- this project's own primitives (`S:StripTextures`/`S:StyleCloseButton`/
-- `S:StyleUIPanelButton`, elvBackground child frame instead of a direct
-- native SetBackdrop -- see this file's own `S:StripTextures` comment for
-- why). If a future round finds native code re-asserting chrome on repeat
-- shows (this project's own recurring pattern elsewhere), add
-- `SecureHook("StaticPopup_OnShow", ...)` then, matching
-- `InstallDropDownMenuSkin`'s own mechanism -- not preemptively here,
-- since pfUI's real-vanilla-proven version doesn't need one either.
--
-- SCOPE, first pass: outer chrome (strip, elvBackground, close button),
-- both buttons, EditBox + WideEditBox (the "Add Friend"/"Add Ignore"
-- trigger case uses the plain EditBox). Deliberately NOT touched:
-- `$parentMoneyFrame` (`SmallMoneyFrameTemplate`) -- no popup in this
-- project's current scope uses it.
-- (`S.PLAIN_BACKDROP` used to be declared here; now lives in the
-- design-token block at the top of this file.)

-- Shared with Friends.lua's
-- own Who tab, which needs the identical recipe for `WhoFrameEditBox` (the
-- search field) -- a plain native EditBox with no `<Backdrop>` tag of its
-- own, just 2 unnamed BACKGROUND-layer chrome Textures (confirmed via the
-- FrameXML, both `StaticPopup...EditBox` and `WhoFrameEditBox` use the
-- exact same shape) -- `DisableDrawLayer("BACKGROUND")` clears those
-- durably, then a fresh backdrop replaces them.
--
-- THE ONE EDIT-BOX RECIPE for this project. Two design points matter:
--
-- 1. **Color**: was `PANEL_COLOR` (.05/.95) -- byte-identical to the window
--    behind it, so a field was invisible until you clicked in it. Now
--    `WIDGET_COLOR` (.1) -- exactly one step lighter than the panel and
--    exactly the fill every skinned BUTTON already has, which is real
--    ElvUI's own split (see the design-token block at the top of this
--    file). Not a taste call: `S:HandleEditBox` in real ElvUI is literally
--    `E:CreateBackdrop(frame, "Default")`, i.e. `backdropcolor` {.1,.1,.1}.
--
-- 2. **Mechanism**: was `SetBackdrop` on the native EditBox itself. That is
--    the exact call this project has now failed with FOUR separate times
--    (ReputationDetailFrame, DropDownList1-3, MacroFrameTextBackground,
--    and the light-grey box in the screenshot that triggered this whole
--    pass) -- see `S:CreateSurface`'s own note. Now it goes through
--    `S:CreateSurface`, a real child frame that draws, one level BELOW the
--    box so the box's own text still renders on top.
--
-- Also kills the NAMED chrome pieces by hand (`$parentLeft/Middle/Right/
-- Mid`), matching real ElvUI's own `S:HandleEditBox`: `InputBoxTemplate`
-- (source/wow-ui-source/FrameXML/UIPanelTemplates.xml:226+) draws its
-- border as three named `Common-Input-Border` textures, and its `$parentLeft`
-- is anchored at x=-5, i.e. it deliberately hangs OUTSIDE the box's own
-- footprint -- `DisableDrawLayer("BACKGROUND")` already covers them (they
-- are BACKGROUND-layer regions of the box itself), the explicit `S:Kill`
-- is belt-and-braces for any client where the layer call is a no-op.
function S:StyleEditBox(box)
	if not box then return end
	-- Standing frame property, re-asserted every call -- the one mechanism
	-- confirmed to survive native redraws.
	pcall(box.DisableDrawLayer, box, "BACKGROUND")
	if box.elvEditBoxStyled then return end
	box.elvEditBoxStyled = true

	local okName, name = pcall(box.GetName, box)
	if okName and name then
		S:Kill(_G[name.."Left"])
		S:Kill(_G[name.."Middle"])
		S:Kill(_G[name.."Mid"])
		S:Kill(_G[name.."Right"])
	end

	-- Clear any native <Backdrop> the template declared, then draw our own
	-- from a child frame -- never re-SetBackdrop the box itself.
	pcall(box.SetBackdrop, box, nil)

	-- Same clamp `Util.CreateButtonBorder` uses for buttons: give the
	-- surface one guaranteed level of headroom underneath, without which
	-- it can land ON TOP of the box's own text on a frame that sits at
	-- level 0/1.
	local okLevel, level = pcall(box.GetFrameLevel, box)
	local boxLevel = (okLevel and tonumber(level)) or 1
	if boxLevel < 4 then
		pcall(box.SetFrameLevel, box, 4)
		boxLevel = 4
	end

	local bg = S:CreateSurface(box, S.WIDGET_COLOR, nil, nil, nil, nil, true)
	if bg then pcall(bg.SetFrameLevel, bg, boxLevel - 1) end

	pcall(box.SetTextInsets, box, 4, 4, 0, 0)
end

-- Generic `UIDropDownMenuTemplate` BOX chrome (the closed-state control
-- itself -- $parentLeft/Middle/Right background art + the $parentButton
-- arrow) -- NOT the popup LIST that opens from it, which is already
-- handled globally by `S:InstallDropDownMenuSkin` below (that one hooks
-- the SHARED `DropDownList1-3` frames via `UIDropDownMenu_Initialize`,
-- covering every dropdown in the game already). Extracted
-- from the pattern Character.lua's own `StylePlayerTitleDropDown` proved
-- live first, once Friends.lua's own `WhoFrameDropDown` needed the
-- identical box-chrome treatment.
--
-- Character.lua's own `StylePlayerTitleDropDown` calls this function for
-- its backdrop too, so the title dropdown shares the same `WIDGET_COLOR`
-- and child-frame mechanism as every other dropdown box in the UI,
-- instead of the near-black 0/0.4 wash a native-frame backdrop would
-- otherwise leave it with. Only the BACKDROP is shared; the
-- title-dropdown-specific width/position math and the text re-anchor stay
-- local, because those really are per-call-site.
--
-- Width and position remain deliberately the CALLER's job (they vary per
-- call site) -- this only handles the chrome + the arrow button.
function S:StyleDropDownBox(dd)
	if not dd then return end
	S:StripTextures(dd, false)

	-- Hoisted to the top of the function -- the surface
	-- anchoring below needs the `$parentLeft`/`$parentRight` art, and those
	-- are only reachable through the name.
	local okName, name = pcall(dd.GetName, dd)
	if okName and name == "" then name = nil end

	-- UNIFIED with the edit-box recipe: same `WIDGET_COLOR`
	-- fill, same child-frame mechanism. A closed dropdown box and a text
	-- field are the same KIND of control, so they can't be allowed to
	-- drift apart visually -- which they had (this used to be a
	-- near-black 0/0.4 wash applied straight onto the native frame, while
	-- edit boxes were .05/.95). Level handled exactly as in
	-- `S:StyleEditBox` -- the surface must sit under the box's own $parentText.
	local okDDLevel, ddLevel = pcall(dd.GetFrameLevel, dd)
	ddLevel = (okDDLevel and tonumber(ddLevel)) or 1
	if ddLevel < 4 then
		pcall(dd.SetFrameLevel, dd, 4)
		ddLevel = 4
	end
	local ddBg = S:CreateSurface(dd, S.WIDGET_COLOR, nil, nil, nil, nil, true)
	if ddBg then pcall(ddBg.SetFrameLevel, ddBg, ddLevel - 1) end

	-- THE SURFACE FOLLOWS THE ART HORIZONTALLY, NOT THE FRAME -- MEASURED
	-- (Video Options: a row of several horizontal dropdowns falls apart
	-- visually otherwise).
	--
	-- `S:CreateSurface` anchors `SetAllPoints(dd)`, i.e. the dropdown FRAME's
	-- footprint, and on the real 1.12.1 template that is the same rectangle
	-- as the visible box: `UIDropDownMenu_SetWidth` sets `$parentMiddle` to
	-- `width` and the frame to `width + 50`, while the art is Left(25) +
	-- Middle(width) + Right(25). Two live measurements say the WIDTHS still
	-- agree exactly on this client -- and that the art is DISPLACED:
	--
	--   OptionsFrameRefreshDropDown      f=578..718   mid=758..848
	--   OptionsFrameMultiSampleDropDown  f=728..918   mid=908..1048
	--
	-- Frame widths 140 / 190; art widths (mid + the two 25px caps) 140 / 190
	-- -- identical. But the art's left edge (mid.left - 25) sits at 733 and
	-- 883, i.e. **+155px right of the frame's own left edge in BOTH cases**.
	-- So every dropdown in that window paints one slot to the right of where
	-- its frame is, and the last one in a row falls off the window edge
	-- entirely -- exactly what the screenshot shows, and exactly why a row of
	-- them looks scattered while a lone dropdown (Sound Options, the
	-- Character title dropdown) always looked right: there the displacement
	-- is zero and frame and art coincide.
	--
	-- Anchoring to `$parentLeft`/`$parentRight` is therefore correct on BOTH
	-- shapes -- it is the same rectangle wherever the two agree, and the
	-- visible one wherever they don't. Anchors also keep following the art if
	-- the client re-runs `UIDropDownMenu_SetWidth` later, which a computed
	-- one-time offset could not (this surface is created once and reused).
	--
	-- Real ElvUI's own `S:HandleDropDownBox` was the candidate fix and is
	-- deliberately NOT what got used: it anchors the LEFT edge to the frame
	-- (`TOPLEFT, 20, -2`) and only the right edge to the arrow button, so on
	-- this client it would have left the box 155px away from its own text.
	--
	-- Only the HORIZONTAL edges come from the art. The vertical stays on the
	-- frame: the measured displacement is purely horizontal, the art strip is
	-- 64px tall (mostly transparent padding) while the frame's height is the
	-- control's real height, and the current vertical extent is already
	-- live-accepted on every other skinned dropdown.
	local ddLeftArt = name and _G[name .. "Left"]
	local ddRightArt = name and _G[name .. "Right"]
	if ddBg and ddLeftArt and ddRightArt then
		-- Hidden regions still report geometry on this client (that is how
		-- the numbers above were read AFTER the strip), so anchoring to art
		-- this module has already hidden is safe.
		local okAnchor = pcall(function()
			ddBg:ClearAllPoints()
			ddBg:SetPoint("LEFT", ddLeftArt, "LEFT", 0, 0)
			ddBg:SetPoint("RIGHT", ddRightArt, "RIGHT", 0, 0)
			ddBg:SetPoint("TOP", dd, "TOP", 0, 0)
			ddBg:SetPoint("BOTTOM", dd, "BOTTOM", 0, 0)
		end)
		-- Four single-edge anchors are a less-travelled path on this client
		-- than a TOPLEFT/BOTTOMRIGHT pair -- and this project already has one
		-- anchoring finding against it (a Texture given only two OPPOSITE
		-- edges doesn't reliably centre on UA). Four edges is the fully-constrained case rather
		-- than that under-constrained one, but a failure still falls back to
		-- exactly what every previously-accepted window already had, rather
		-- than leaving a surface with no anchors at all.
		if not okAnchor then
			pcall(ddBg.ClearAllPoints, ddBg)
			pcall(ddBg.SetAllPoints, ddBg, dd)
		end
	end

	-- OUR OWN CLICK TARGET -- the measured answer to "the
	-- microphone dropdown won't open". The `GetMouseFocus()` trail came back
	-- naming every slider it passed over (`SoundOptionsFrameSlider5/Slider`
	-- and friends) and NOTHING AT ALL over the dropdown: no focus there
	-- means nothing there receives mouse input, which is exactly why no
	-- click ever arrived and why every renderer-side theory came up empty.
	--
	-- This project's documented answer to "a native element won't do its job"
	-- is not another attempt at the native element -- it
	-- is to create our own and let that be what works. So: a real Button over the box,
	-- calling the very function the template's own OnClick calls.
	--
	-- GUARDED on `ToggleDropDownMenu` actually being a function here. If it
	-- isn't, no overlay is built at all -- an overlay that can't open
	-- anything would be strictly worse than the current state, because it
	-- would also swallow clicks on the windows where the native button DOES
	-- work today (the Character title dropdown, `WhoFrameDropDown`).
	if type(ToggleDropDownMenu) == "function" and not dd.elvClickOverlay then
		local okOverlay, overlay = pcall(CreateFrame, "Button", nil, dd)
		if okOverlay and overlay then
			-- SHRUNK to the arrow button's own footprint: covering the
			-- whole dropdown frame works for clicking, but swallows the
			-- HOVER of everything underneath, including tooltips on
			-- already-working dropdowns. Something under there does
			-- receive hover even though `GetMouseFocus()` reports nothing
			-- (which is itself worth knowing: this client has hover
			-- targets that the focus query can't see). Over the arrow
			-- alone, only the arrow's own tooltip is lost -- an accepted
			-- tradeoff -- everything else gets its hover back.
			local okOverlayName, overlayParentName = pcall(dd.GetName, dd)
			local arrowButton = okOverlayName and overlayParentName and _G[overlayParentName.."Button"]
			if arrowButton then
				pcall(overlay.SetAllPoints, overlay, arrowButton)
			else
				pcall(overlay.SetAllPoints, overlay, dd)
			end
			pcall(overlay.EnableMouse, overlay, true)
			-- Above the box and its own art, so it is what the cursor meets.
			pcall(overlay.SetFrameLevel, overlay, ddLevel + 2)
			pcall(overlay.SetScript, overlay, "OnClick", function()
				pcall(ToggleDropDownMenu, 1, nil, dd, (okOverlayName and overlayParentName) or nil, 0, 0)
			end)
			dd.elvClickOverlay = overlay
		end
	end

	-- SECOND HALF of the "the microphone dropdown won't open" measurement.
	-- `StyleDropDownList`'s own debug line says whether the
	-- menu ever INITIALISES; this one says whether it ever SHOWS. Together
	-- they split the report three ways without another guess:
	--   neither line   -> the click never gets through to the arrow button
	--                     (or this client's custom dropdown doesn't use
	--                     `UIDropDownMenu_Initialize` at all, which would
	--                     also mean none of this module's list styling has
	--                     ever applied to it);
	--   init only      -> it builds but never shows;
	--   both           -> it is shown and the problem is purely that it
	--                     renders behind this window.
	-- Deliberately polled from OUR OWN surface frame, never from an
	-- `OnUpdate`/hook on the native dropdown: replacing a script on a native
	-- widget is exactly how a working control gets broken, and this has to
	-- be a read-only probe.
	if ddBg and S.autoSkinDebug and not ddBg.elvListProbe then
		ddBg.elvListProbe = true
		pcall(ddBg.SetScript, ddBg, "OnUpdate", function()
			local now = GetTime()
			if ddBg.elvNextProbe and now < ddBg.elvNextProbe then return end
			ddBg.elvNextProbe = now + 0.2

			local list = _G.DropDownList1
			if list then
				local okShown, shown = pcall(list.IsShown, list)
				shown = okShown and shown and true or false
				if shown ~= ddBg.elvListWasShown then
					ddBg.elvListWasShown = shown
					if shown then
						local okStrata, strata = pcall(list.GetFrameStrata, list)
						local okLevel2, level2 = pcall(list.GetFrameLevel, list)
						E:Print(string.format("  DropDownList1 SHOWN: strata=%s level=%s",
							tostring(okStrata and strata or "?"), tostring(okLevel2 and level2 or "?")))
					end
				end
			end

			-- WHAT IS ACTUALLY UNDER THE CURSOR, for "the menu won't
			-- open": the two earlier probes both stayed
			-- silent no matter where the click lands, which rules out "the
			-- menu opens behind the window" and leaves "the click never
			-- reaches the arrow button". `S:DumpMouseFocus()` is the tool
			-- for that -- but it needs a typed `/run`, and this window
			-- swallows the keyboard while it is open, which is why it is not
			-- usable here. Polling `GetMouseFocus()` from our own frame is
			-- the same measurement through the one channel that does work.
			--
			-- Reports only on CHANGE and only a handful of times, so hovering
			-- around the window gives a short, readable trail instead of a
			-- flood: hover the arrow, and the last name printed is whatever
			-- would receive the click. If that is the dropdown's own
			-- `...Button`, our surfaces are innocent and the fault is in the
			-- client's own dropdown code; if it is one of ours, the culprit
			-- is named outright.
			-- DRIVE THE MENU FROM LUA, once, about two seconds after the
			-- window comes up. This is the other half of the
			-- click question and it needs no mouse at all: if the menu opens
			-- when called directly, then the machinery is fine and only the
			-- CLICK is not arriving; if it doesn't, the client's own dropdown
			-- code is what's broken and no amount of skin work will fix it.
			--
			-- `Button:Click()` would be the obvious probe and is deliberately
			-- NOT used -- it is confirmed broken on UA, so a negative
			-- result from it would prove nothing. `ToggleDropDownMenu` is what the
			-- template's own OnClick calls, so calling it with explicit
			-- arguments exercises exactly the same path.
			if not ddBg.elvToggleProbed then
				ddBg.elvProbeStart = ddBg.elvProbeStart or now
				if now - ddBg.elvProbeStart > 2 then
					ddBg.elvToggleProbed = true
					E:Print("  ToggleDropDownMenu="..type(ToggleDropDownMenu)
						.." UIDropDownMenu_Initialize="..type(UIDropDownMenu_Initialize))
					if type(ToggleDropDownMenu) == "function" then
						local okDDName, ddName = pcall(dd.GetName, dd)
						local okToggle, toggleErr = pcall(ToggleDropDownMenu, 1, nil, dd,
							(okDDName and ddName) or nil, 0, 0)
						if not okToggle then
							E:Print("  ToggleDropDownMenu error: "..tostring(toggleErr))
						end
						-- Whether anything actually appeared is reported by
						-- the IsShown watcher above, on the next tick.
					end
				end
			end

			-- THE TOOLTIP AS A SECOND INPUT CHANNEL: since the native
			-- dropdown has its own tooltip, `GameTooltip:GetOwner()` might
			-- work even where `GetMouseFocus()` doesn't. It measures
			-- something `GetMouseFocus()` cannot:
			-- if a tooltip appears over a widget that reports NO mouse focus,
			-- then something IS receiving hover events there and the focus
			-- query simply doesn't see it -- which would be a UA fact worth
			-- writing down on its own. `GetOwner` rather than `GetParent`:
			-- the owner is what `GameTooltip:SetOwner(...)` was handed, i.e.
			-- the widget the tooltip is FOR, while the parent is just
			-- whatever it is anchored under.
			--
			-- Capped and edge-triggered, so hovering around gives a few
			-- readable lines rather than a flood.
			if GameTooltip and (ddBg.elvTooltipPrints or 0) < 5 then
				local okTipShown, tipShown = pcall(GameTooltip.IsShown, GameTooltip)
				tipShown = okTipShown and tipShown and true or false
				if tipShown and not ddBg.elvTooltipWasShown then
					ddBg.elvTooltipWasShown = true
					ddBg.elvTooltipPrints = (ddBg.elvTooltipPrints or 0) + 1
					local ownerLabel = "none"
					local okOwner, owner = pcall(GameTooltip.GetOwner, GameTooltip)
					if okOwner and owner then
						local okOwnerName, ownerName = pcall(owner.GetName, owner)
						local okOwnerType, ownerType = pcall(owner.GetObjectType, owner)
						ownerLabel = tostring(okOwnerName and ownerName or "<unnamed>")
							.."/"..tostring(okOwnerType and ownerType or "?")
					end
					local tipText = "?"
					local line = _G.GameTooltipTextLeft1
					if line then
						local okText, text = pcall(line.GetText, line)
						if okText then tipText = tostring(text) end
					end
					E:Print("  tooltip owner: "..ownerLabel.." text="..tipText)
				elseif not tipShown then
					ddBg.elvTooltipWasShown = false
				end
			end

			if GetMouseFocus and (ddBg.elvFocusPrints or 0) < 12 then
				local okFocus, focus = pcall(GetMouseFocus)
				if okFocus and focus then
					local okFName, focusName = pcall(focus.GetName, focus)
					local okFType, focusType = pcall(focus.GetObjectType, focus)
					local label = tostring(okFName and focusName or "<unnamed>")
						.."/"..tostring(okFType and focusType or "?")
					if label ~= ddBg.elvLastFocus then
						ddBg.elvLastFocus = label
						ddBg.elvFocusPrints = (ddBg.elvFocusPrints or 0) + 1
						E:Print("  mouse focus: "..label)
					end
				end
			end
		end)
	end

	local text = okName and name and _G[name.."Text"]
	if text then
		pcall(text.SetTextColor, text, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	end

	local btn = okName and name and _G[name.."Button"]
	if btn then
		local okNormal, normalTexture = pcall(btn.GetNormalTexture, btn)
		if okNormal and normalTexture then
			pcall(normalTexture.SetTexture, normalTexture, nil)
			pcall(normalTexture.Hide, normalTexture)
			normalTexture.Show = E.noop
		end
		local okPushed, pushedTexture = pcall(btn.GetPushedTexture, btn)
		if okPushed and pushedTexture then
			pcall(pushedTexture.SetTexture, pushedTexture, nil)
			pcall(pushedTexture.Hide, pushedTexture)
			pushedTexture.Show = E.noop
		end
		-- DISABLED art too: switching Voice Chat
		-- off disables the microphone dropdown's arrow button, and the
		-- native disabled art (a gold bevelled square) came straight back,
		-- because only Normal and Pushed were ever cleared here. Setter
		-- only: `GetDisabledTexture` doesn't exist on this client, so the
		-- Hide()+noop treatment the other two slots get isn't available.
		pcall(btn.SetDisabledTexture, btn, "")
		pcall(btn.DisableDrawLayer, btn, "ARTWORK")

		if not btn.elvGlyph then
			local icon = btn:CreateTexture(nil, "OVERLAY")
			icon:SetWidth(10)
			icon:SetHeight(10)
			pcall(icon.SetTexture, icon, S.SQUARE_BUTTON_TEXTURE)
			local coords = S.SQUARE_BUTTON_TEXCOORDS.DOWN
			if coords then
				pcall(icon.SetTexCoord, icon, coords[1], coords[2], coords[3], coords[4])
			end
			btn.elvGlyph = icon
		end
		pcall(btn.elvGlyph.ClearAllPoints, btn.elvGlyph)
		pcall(btn.elvGlyph.SetPoint, btn.elvGlyph, "CENTER", btn, "CENTER", 0, 0)
	end
end

function S:InstallStaticPopupSkin()
	if self.staticPopupSkinInstalled then return end
	self.staticPopupSkinInstalled = true

	local numDialogs = _G.STATICPOPUP_NUMDIALOGS or 4
	local i
	for i = 1, numDialogs do
		local popup = _G["StaticPopup"..i]
		if popup then
			S:StripTextures(popup, false)

			S:CreatePanel(popup)

			S:StyleCloseButton(_G["StaticPopup"..i.."CloseButton"])
			S:StyleUIPanelButton(_G["StaticPopup"..i.."Button1"])
			S:StyleUIPanelButton(_G["StaticPopup"..i.."Button2"])
			S:StyleEditBox(_G["StaticPopup"..i.."EditBox"])
			S:StyleEditBox(_G["StaticPopup"..i.."WideEditBox"])
		end
	end
end

-- Reads E.private, NOT V: disabling the
-- module (master switch AND retested after a full client restart, not
-- just /reload) can otherwise have no effect at all. Root cause: this used to check
-- V.skins.blizzard.*, but V is the STATIC private-defaults table (merged
-- into E.private once at OnInitialize) -- the config UI's toggles write
-- to E.private.skins.blizzard.*, a SEPARATE live table that diverges from
-- V the moment either is touched at runtime. Checking V here meant this
-- always saw the frozen file-load-time default (true), never whatever
-- the user actually set. Same bug class as the earlier Mirror Timers
-- config fix (ElvUI_Config/Core.lua), mirrored in the other direction --
-- V for the default, E.private for the live, user-editable value, never
-- confuse the two.
function S:Initialize()
	if not E.private.skins.blizzard.enable then return end
	local key, list
	for key, list in pairs(self.blizzardSkins) do
		if E.private.skins.blizzard[key] then
			local i
			for i = 1, table.getn(list) do
				local ok = pcall(list[i])
				if not ok then S:ReportSkinProblem() end
			end
		end
	end

	-- Not gated by any per-window key (`self.blizzardSkins`) -- this
	-- isn't a specific window like Character/Reputation/etc., it's a
	-- cross-cutting skin for every native dropdown menu in the game,
	-- matching real ElvUI's own scope for this exact feature. Only the
	-- master `blizzard.enable` switch (already checked above) gates it.
	self:InstallDropDownMenuSkin()

	-- Same reasoning, same scope (master switch only) -- StaticPopup1-4
	-- aren't a specific window either, they're the shared confirmation-
	-- dialog frames used across the whole game.
	self:InstallStaticPopupSkin()
end

-- ---------------------------------------------------------------------
-- Diagnostics -- `/run ElvUI[1].Skins:Dump(CharacterAttributesFrame)` or
-- `/run ElvUI[1].Skins:Dump("CharacterAttributesFrame")` (either a frame
-- reference or a global name string). Exists because modifying a
-- pre-existing native element (recursive region strip, native-backdrop
-- clearing, a portrait name fix, a tab-art clear) can produce ZERO
-- visible change on it -- while everything CREATED fresh in the same
-- file (the drag handle, the inset background frame, the close button's
-- resize) works immediately. That asymmetry means guessing another
-- removal technique isn't the move -- this prints what's ACTUALLY there
-- on a stuck frame (does GetBackdrop() return non-nil, region count/
-- types/texture paths, child count/types) instead, same root-cause-first
-- approach used throughout this project. Each
-- line is its own short E:Print, since a native chat frame scrolls per
-- MESSAGE, not per wrapped visual line.
-- `childIndex` drills into `target`'s Nth child instead of dumping
-- `target` itself -- added after the first round on CharacterAttributesFrame
-- came back tex=9/fontstrings=0/paths={} (its OWN regions have no readable
-- text or texture path -- the "Strength: 28"-style text has to live on one
-- of its 12 children instead, none of which have a usable global name to
-- Dump() by string). `/run ElvUI[1].Skins:Dump("CharacterAttributesFrame", 1)`
-- dumps child #1.
function S:Dump(target, childIndex)
	local frame = target
	if type(target) == "string" then frame = _G[target] end
	if not frame then
		E:Print("Skins:Dump -- no such frame: " .. tostring(target))
		return
	end

	if childIndex then
		local okKids, kids = pcall(function() return { frame:GetChildren() } end)
		if not okKids or type(kids) ~= "table" or not kids[childIndex] then
			E:Print(string.format("Skins:Dump -- no child #%d", childIndex))
			return
		end
		frame = kids[childIndex]
	end

	local okType, objType = pcall(frame.GetObjectType, frame)
	local okName, name = pcall(frame.GetName, frame)
	E:Print(string.format("%s (%s)", tostring(okName and name or "?"), tostring(okType and objType or "?")))

	-- Geometry -- needed for the Interface Options pass. A
	-- window whose top frame is screen-sized must NOT get the panel: real
	-- vanilla's `UIOptionsFrame` is `setAllPoints` with the visible window
	-- being a child, and only a measurement can say whether that still
	-- holds on this client. Cheap enough to always print.
	local function num(method)
		local okCall, value = pcall(frame[method], frame)
		if okCall and tonumber(value) then return string.format("%d", value) end
		return "?"
	end
	-- `select` is deliberately not used anywhere in this project -- it does
	-- not exist in Lua 5.0.3.
	local okStrata, strata = pcall(frame.GetFrameStrata, frame)
	E:Print(string.format("  geom: %sx%s at %s,%s level=%s strata=%s",
		num("GetWidth"), num("GetHeight"), num("GetLeft"), num("GetBottom"),
		num("GetFrameLevel"), tostring((okStrata and strata) or "?")))

	local okBackdrop, backdrop = pcall(frame.GetBackdrop, frame)
	if okBackdrop and backdrop then
		E:Print("  backdrop: bgFile=" .. tostring(backdrop.bgFile))
		E:Print("  backdrop: edgeFile=" .. tostring(backdrop.edgeFile))
	else
		E:Print("  backdrop: none")
	end

	local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
	if okRegions and type(regions) == "table" then
		local texCount, fsCount, shownWithSize, paths, texts = 0, 0, 0, {}, {}
		local i
		for i = 1, table.getn(regions) do
			local region = regions[i]
			local okRType, rType = pcall(region.GetObjectType, region)
			if okRType and rType == "Texture" then
				texCount = texCount + 1
				local okPath, path = pcall(region.GetTexture, region)
				if okPath and type(path) == "string" and table.getn(paths) < 3 then
					table.insert(paths, string.sub(path, -28))
				end
				-- Tests whether a texture with NO path can still occupy
				-- visible space -- if this stays nonzero even after
				-- SetTexture(nil) ran, an emptied texture may still
				-- render something on this client (a real UA finding, not
				-- a strip-logic bug).
				local okShown, shown = pcall(region.IsShown, region)
				local okW, w = pcall(region.GetWidth, region)
				if okShown and shown and okW and tonumber(w) and w > 0 then
					shownWithSize = shownWithSize + 1
				end
			elseif okRType and rType == "FontString" then
				fsCount = fsCount + 1
				local okText, text = pcall(region.GetText, region)
				if okText and type(text) == "string" and text ~= "" and table.getn(texts) < 3 then
					table.insert(texts, text)
				end
			end
		end
		E:Print(string.format("  regions: tex=%d fontstrings=%d shownWithSize=%d", texCount, fsCount, shownWithSize))
		E:Print("  paths={" .. table.concat(paths, ",") .. "}")
		E:Print("  texts={" .. table.concat(texts, ",") .. "}")
	else
		E:Print("  regions: GetRegions() failed")
	end

	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	if okKids and type(kids) == "table" then
		-- NAMES, not just types. Written for the Interface
		-- Options pass, where the client's own layout is the only source of
		-- truth -- its FrameXML is customised on this server and carries
		-- options vanilla never had, so nothing may be assumed from
		-- `source/wow-ui-source`. Knowing a child is a `Frame` says nothing;
		-- knowing it is called `BasicOptions` or `UIOptionsFrameTab3` is
		-- what tells you where the real window and its tabs actually live.
		-- Resolved through `S:ResolveWidget` first for the same reason
		-- everything else here is: an enumerated native child is a crippled
		-- wrapper on this client.
		local childList = {}
		local j
		for j = 1, table.getn(kids) do
			if table.getn(childList) < 24 then
				local kid = self:ResolveWidget(kids[j])
				local okKType, kType = pcall(kid.GetObjectType, kid)
				local okKName, kName = pcall(kid.GetName, kid)
				table.insert(childList, string.format("%s(%s)",
					tostring(okKName and kName or "<unnamed>"),
					tostring(okKType and kType or "?")))
			end
		end
		E:Print(string.format("  children: %d", table.getn(kids)))
		local c
		for c = 1, table.getn(childList) do
			E:Print("    " .. childList[c])
		end
	else
		E:Print("  children: GetChildren() failed")
	end

	-- SLIDER VALUE LINE: reading the actual value out is more reliable
	-- than judging a drag by eye. Judging a drag by
	-- eye is exactly how this window burned a round already (the
	-- Microphone Gain that turned out not to save on an UNSKINNED client
	-- either), so the value gets read out instead of estimated.
	--
	-- `step=` also settles an open question outright: UA's own docs say
	-- there is no `GetValueStep` (source/UnrealAzeroth_LuaAPI/en/widgets/
	-- Slider.md), which is why `S:StyleOptionsSlider`'s drag can't snap
	-- there while the legacy client -- still on its native drag -- does
	-- step (live-confirmed). If this prints a number on UA, the
	-- doc is stale and the snap can be made to work; if it prints ERR,
	-- there is no step to read and that avenue is closed.
	if okType and objType == "Slider" then
		local function ask(method)
			local okCall, value = pcall(frame[method], frame)
			if okCall and tonumber(value) then return string.format("%.4f", value) end
			return "ERR"
		end
		local okRange, minValue, maxValue = pcall(frame.GetMinMaxValues, frame)
		E:Print(string.format("  slider: value=%s step=%s range=%s..%s",
			ask("GetValue"), ask("GetValueStep"),
			tostring(okRange and tonumber(minValue) or "ERR"),
			tostring(okRange and tonumber(maxValue) or "ERR")))
	end
end

-- Identifies whatever native frame is directly under the mouse cursor
-- RIGHT NOW, reusing the exact technique already proven for the NamePlates
-- investigation (`NamePlates.lua`'s own `DumpMouseFocus()`), generalized
-- here since "what native thing is THIS" is a recurring question for any
-- future skin work, not just one investigation. Point the mouse at the
-- mystery element in-game, then run this. Read-only.
-- Diagnostic for the global dropdown skin: confirms live whether a fix
-- actually reached the frames at all, rather than relying on a
-- screenshot that may predate it.
--
--   /run ElvUI[1].Skins:DumpDropDown()
--
-- Run it WHILE A MENU IS OPEN (right-click a unit frame, then run this
-- from a macro, or open the menu and use the chat box if it stays up).
-- What each line tells you:
--   exists=false            the frame isn't there -> UA doesn't use this
--                           machinery for that menu at all, and no amount
--                           of DropDownList skinning will ever touch it.
--   shown=true, backdrop=no our SetBackdrop didn't stick on this client.
--   shown=false on BOTH     the visible menu is drawn by something else
--                           (a UA-native widget, not these Lua frames).
function S:DumpDropDown()
	local maxLevels = tonumber(_G.UIDROPDOWNMENU_MAXLEVELS) or 3
	E:Print(string.format("DropDown: MAXLEVELS=%s MAXBUTTONS=%s Initialize=%s",
		tostring(_G.UIDROPDOWNMENU_MAXLEVELS), tostring(_G.UIDROPDOWNMENU_MAXBUTTONS),
		type(_G.UIDropDownMenu_Initialize)))

	local function describe(name)
		local frame = _G[name]
		if not frame then return name .. ": exists=false" end
		local okShown, shown = pcall(frame.IsShown, frame)
		local okBackdrop, backdrop = pcall(frame.GetBackdrop, frame)
		local okW, w = pcall(frame.GetWidth, frame)
		local okH, h = pcall(frame.GetHeight, frame)
		return string.format("%s: shown=%s backdrop=%s size=%sx%s",
			name,
			tostring(okShown and shown),
			(okBackdrop and backdrop) and "yes" or "no",
			tostring(okW and w and math.floor(w)),
			tostring(okH and h and math.floor(h)))
	end

	local i
	for i = 1, maxLevels do
		local list = _G["DropDownList"..i]
		E:Print(describe("DropDownList"..i))
		E:Print("  " .. describe("DropDownList"..i.."Backdrop"))
		E:Print("  " .. describe("DropDownList"..i.."MenuBackdrop"))

		-- Our own background frame (third attempt's mechanism). If this
		-- reports shown=true with a backdrop while the menu still renders
		-- the light grey, then the grey is drawn ABOVE a normal child frame
		-- -- which no Lua-side layering can fix, and the widget is not
		-- really this Lua frame at all.
		if list then
			local bg = list.elvBackground
			if not bg then
				E:Print("  elvBackground: not created")
			else
				local okShown, shown = pcall(bg.IsShown, bg)
				local okBD, backdrop = pcall(bg.GetBackdrop, bg)
				local okLevel, level = pcall(bg.GetFrameLevel, bg)
				local okListLevel, listLevel = pcall(list.GetFrameLevel, list)
				E:Print(string.format("  elvBackground: shown=%s backdrop=%s level=%s (list level=%s)",
					tostring(okShown and shown),
					(okBD and backdrop) and "yes" or "no",
					tostring(okLevel and level),
					tostring(okListLevel and listLevel)))
			end
		end
	end
end

function S:DumpMouseFocus()
	local ok, focus = pcall(GetMouseFocus)
	if not ok or not focus then
		E:Print("GetMouseFocus() returned nothing -- move the mouse over the target first")
		return
	end

	local okType, objType = pcall(focus.GetObjectType, focus)
	local okName, name = pcall(focus.GetName, focus)
	E:Print(string.format("focus: %s (%s)", tostring(okName and name or "?"), tostring(okType and objType or "?")))

	local okW, w = pcall(focus.GetWidth, focus)
	local okH, h = pcall(focus.GetHeight, focus)
	E:Print(string.format("  size: %s x %s", tostring(okW and w), tostring(okH and h)))

	local okP, parent = pcall(focus.GetParent, focus)
	if okP and parent then
		local okPName, parentName = pcall(parent.GetName, parent)
		E:Print("  parent: " .. tostring(okPName and parentName or "?"))
	end

	-- `elvStyled`/
	-- `elvBackground` alone can't tell "genuinely never matched" apart from
	-- "matched once, then its own native art went away as a SIDE EFFECT of
	-- our own styling" -- both end up looking identical to a later
	-- `HasNativeArt` probe (checked art field is nil either way), which is
	-- exactly the ambiguity a screenshot alone can't resolve either. This
	-- prints BOTH: the one-shot latch this project already sets everywhere
	-- (`elvStyled` on Button/CheckButton, `elvBackground` on anything ever
	-- run through `S:CreateSurface` -- panels, fields, dropdown boxes,
	-- option sliders, all of them), so a `true` here means "this project's
	-- own code ran on this widget at least once", independent of whatever
	-- the live art probe below says.
	local hasRun = (focus.elvStyled or focus.elvBackground or focus.elvThumbBG) and true or false
	E:Print("  ran before (elvStyled/elvBackground/elvThumbBG): " .. tostring(hasRun))

	if okType then
		if objType == "CheckButton" then
			E:Print("  HasNativeArt(ui-checkbox) now: " .. tostring(HasNativeArt(focus, CHECKBOX_ART)))
		elseif objType == "Button" then
			E:Print("  HasNativeArt(ui-panel-button) now: " .. tostring(HasNativeArt(focus, PANEL_BUTTON_ART)))
		elseif objType == "Frame" then
			local btn = okName and name and _G[name.."Button"]
			E:Print(string.format("  dropdown check: has $parentButton=%s, HasNativeArt(charactercreate-labelframe)=%s",
				tostring(btn and true or false), tostring(HasNativeArt(focus, DROPDOWN_ART))))
		elseif objType == "Slider" then
			local upBtn = okName and name and _G[name.."ScrollUpButton"]
			local downBtn = okName and name and _G[name.."ScrollDownButton"]
			E:Print(string.format("  slider check: ScrollUpButton=%s ScrollDownButton=%s -> treated as %s",
				tostring(upBtn and true or false), tostring(downBtn and true or false),
				tostring((upBtn or downBtn) and "scrollbar" or "options slider")))
		end
	end

	local okBackdrop, backdrop = pcall(focus.GetBackdrop, focus)
	E:Print("  GetBackdrop(): " .. tostring(okBackdrop and (backdrop and "present" or "nil") or "no-method"))
end

-- Full-UI-tree, frame-agnostic sweep for the "mystery sliver" investigation
-- -- CastingBarFrame/PetFrame/PetActionBarFrame's own named regions, and
-- separately ALL of their regions via GetRegions() regardless of name, both
-- come back negative on live testing (moved to screen-center, nothing
-- appears) -- so the element isn't a child texture of any of those three
-- frames at all. Same escalation NamePlates' own investigation used once
-- its own narrower guesses ran out (`FindByTextDeep`): stop guessing a
-- PARENT, walk the ENTIRE UI tree from UIParent down (a breadth-first
-- queue, not true Lua recursion, to keep this simple and avoid a deep call
-- stack) and report every currently-SHOWN Texture region that's thin in at
-- least one dimension (a "sliver" border) -- regardless of which frame owns
-- it. `maxVisit` bounds the walk (matches the same safety-ceiling
-- precedent as FindByTextDeep); `maxResults` caps how many hits get
-- printed (chat scrolls per MESSAGE, not per wrapped line -- keep this
-- small). Point-in-time only: run it WHILE the sliver is actually on
-- screen (i.e. mid pet-attack), not before/after.
--
-- Seeds from BOTH `UIParent` AND `WorldFrame`: `WorldFrame` is a SEPARATE
-- root, a sibling of UIParent, not a descendant of it -- a UIParent-only
-- walk exhausts the entire reachable tree from there and still misses
-- anything parented under WorldFrame instead, the same mistake the
-- NamePlates investigation already hit once (nameplates are invisible to a
-- UIParent-only walk for the identical reason). Since this element is
-- pet/combat-related (a 3D-world-adjacent concept), it could just as
-- easily live under WorldFrame.
function S:FindThinTextures(maxDim, maxVisit, maxResults)
	maxDim = maxDim or 24
	maxVisit = maxVisit or 6000
	maxResults = maxResults or 12

	local queue, qHead, qTail = {}, 1, 0
	if UIParent then qTail = qTail + 1; queue[qTail] = UIParent end
	if WorldFrame then qTail = qTail + 1; queue[qTail] = WorldFrame end
	local visited, found = 0, 0

	while qHead <= qTail and visited < maxVisit and found < maxResults do
		local f = queue[qHead]
		qHead = qHead + 1
		visited = visited + 1

		if f then
			local okType, objType = pcall(f.GetObjectType, f)
			if okType and objType == "Texture" then
				local okShown, shown = pcall(f.IsShown, f)
				if okShown and shown then
					local okW, w = pcall(f.GetWidth, f)
					local okH, h = pcall(f.GetHeight, f)
					w = (okW and tonumber(w)) or 0
					h = (okH and tonumber(h)) or 0
					if w > 0 and h > 0 and (w <= maxDim or h <= maxDim) then
						found = found + 1
						local okParent, parent = pcall(f.GetParent, f)
						local pname = "?"
						if okParent and parent then
							local okPName, n = pcall(parent.GetName, parent)
							pname = okPName and n or "(unnamed)"
						end
						E:Print(string.format("thin tex #%d: parent=%s w=%.0f h=%.0f", found, tostring(pname), w, h))
					end
				end
			else
				local okRegions, regions = pcall(function() return { f:GetRegions() } end)
				if okRegions and type(regions) == "table" then
					local i
					for i = 1, table.getn(regions) do
						qTail = qTail + 1
						queue[qTail] = regions[i]
					end
				end
				local okKids, kids = pcall(function() return { f:GetChildren() } end)
				if okKids and type(kids) == "table" then
					local j
					for j = 1, table.getn(kids) do
						qTail = qTail + 1
						queue[qTail] = kids[j]
					end
				end
			end
		end
	end

	E:Print(string.format("FindThinTextures: visited=%d found=%d (maxDim=%d)", visited, found, maxDim))
end

-- Identity-based snapshot/diff -- FindThinTextures' own "found=12 both
-- before and after" result looks like a clean negative, but that's not
-- the whole picture: `visited` itself can go 1393 -> 1394, meaning a
-- genuinely NEW object DID enter the tree when the sliver appeared, it
-- simply didn't satisfy FindThinTextures' own size filter (not thin enough
-- by that predicate, or some other reason -- unknown without seeing it
-- directly). Aggregate counts can't surface a single new object; this can.
-- A WoW frame/region is userdata, and `tostring()` on userdata yields a
-- stable, per-object identity string for as long as that object exists --
-- so two snapshots taken moments apart can be diffed by actual object
-- identity, not just totals. No size filter at all here -- every visited
-- object, of every type/size/shown-state, gets recorded.
S.snapshots = S.snapshots or {}

-- CHUNKED/BUDGETED, not a single synchronous loop: large maxVisit values
-- crash the client, repeatedly. This
-- project had previously only established that REPEATED heavy per-tick
-- work crashes/freezes UA (NamePlates' own freeze incident) -- this is a
-- NEW, more serious finding: even a single, one-shot synchronous loop
-- large enough (many thousands of pcall'd native calls + closures back to
-- back within one frame) can crash this client outright, not just stutter
-- it. Matches this project's own general `ElvUI.Util.ScheduleLimitedSweep`
-- philosophy (bounded work per tick, spread across many ticks) applied
-- here to a ONE-TIME walk instead of a recurring sweep: a small `budget`
-- of nodes is processed per timer tick, the walk's own queue/position is
-- kept in upvalues across ticks, and a repeating timer cancels itself once
-- the queue empties or `maxVisit` is reached. Call is now async --
-- `SnapshotTree` returns immediately, the actual walk finishes over the
-- next several ticks, printing when done.
function S:SnapshotTree(label, maxVisit, budget)
	maxVisit = maxVisit or 20000
	budget = budget or 250

	local queue, qHead, qTail = {}, 1, 0
	if UIParent then qTail = qTail + 1; queue[qTail] = UIParent end
	if WorldFrame then qTail = qTail + 1; queue[qTail] = WorldFrame end

	local snap = {}
	local visited = 0
	local timerHandle

	local function VisitOne(f)
		local key = tostring(f)
		local okType, objType = pcall(f.GetObjectType, f)
		local okShown, shown = pcall(f.IsShown, f)
		local okW, w = pcall(f.GetWidth, f)
		local okH, h = pcall(f.GetHeight, f)
		local okParent, parent = pcall(f.GetParent, f)
		local pname = "?"
		if okParent and parent then
			local okPName, n = pcall(parent.GetName, parent)
			pname = okPName and n or "(unnamed)"
		end
		snap[key] = string.format("type=%s shown=%s w=%s h=%s parent=%s",
			tostring(okType and objType or "?"),
			tostring(okShown and shown),
			tostring(okW and w),
			tostring(okH and h),
			tostring(pname))

		if not (okType and objType == "Texture") then
			local okRegions, regions = pcall(function() return { f:GetRegions() } end)
			if okRegions and type(regions) == "table" then
				local i
				for i = 1, table.getn(regions) do
					qTail = qTail + 1
					queue[qTail] = regions[i]
				end
			end
			local okKids, kids = pcall(function() return { f:GetChildren() } end)
			if okKids and type(kids) == "table" then
				local j
				for j = 1, table.getn(kids) do
					qTail = qTail + 1
					queue[qTail] = kids[j]
				end
			end
		end
	end

	local function Step()
		local n = 0
		while qHead <= qTail and visited < maxVisit and n < budget do
			local f = queue[qHead]
			qHead = qHead + 1
			visited = visited + 1
			n = n + 1
			if f then VisitOne(f) end
		end

		if qHead > qTail or visited >= maxVisit then
			self.snapshots[label] = snap
			E:Print(string.format("SnapshotTree(%s): visited=%d stored (done)", tostring(label), visited))
			if timerHandle then E:CancelTimer(timerHandle) end
		end
	end

	E:Print(string.format("SnapshotTree(%s): starting (budget=%d/tick)...", tostring(label), budget))
	timerHandle = E:ScheduleRepeatingTimer(Step, 0.05)
end

-- Prints every object present in snapshot `labelB` but NOT in `labelA` --
-- run SnapshotTree("before") ahead of the trigger, SnapshotTree("after")
-- while the sliver is visible, then this.
function S:DiffSnapshots(labelA, labelB)
	local a = self.snapshots[labelA]
	local b = self.snapshots[labelB]
	if not a or not b then
		E:Print("DiffSnapshots -- missing snapshot(s), run SnapshotTree first")
		return
	end
	local newCount = 0
	local key, info
	for key, info in pairs(b) do
		if not a[key] then
			newCount = newCount + 1
			E:Print("NEW: " .. info)
		end
	end
	E:Print(string.format("DiffSnapshots(%s -> %s): %d new object(s)", tostring(labelA), tostring(labelB), newCount))
end

local function InitializeCallback()
	S:Initialize()
end

E:RegisterInitialModule(S:GetName(), InitializeCallback)
