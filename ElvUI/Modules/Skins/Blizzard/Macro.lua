-- Skins > Blizzard > Macro -- reskins the native MacroFrame AND its own
-- popup modal (MacroPopupFrame, the "name + choose an icon" dialog opened
-- by MacroNewButton/MacroEditButton) IN PLACE. Same recipe family as
-- Character.lua/Friends.lua/SpellBook.lua: strip native chrome,
-- elvBackground child frame (never SetBackdrop the native frame itself),
-- S:StyleTab/S:StyleCloseButton/S:StyleUIPanelButton/S:StyleEditBox/
-- S:HandleScrollBar for anything already covered by a shared helper.
--
-- **LoadOnDemand, unlike every other window skinned so far.**
-- `source/wow-ui-source/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.toc`
-- declares `## LoadOnDemand: 1` -- `MacroFrame`/`MacroPopupFrame` do NOT
-- exist at PLAYER_LOGIN, only once the player actually opens Macros for
-- the first time in the session (micro-button click or `/macro`, which
-- triggers Blizzard's own on-demand addon load before showing the frame).
-- `LoadSkin` below hands that wait to `S:WaitForGlobal("MacroFrame", ...)`
-- (Skins.lua), which drives it from BOTH `ADDON_LOADED` and a 0.1s poll
-- backstop -- a hand-rolled 1s `E:ScheduleRepeatingTimer` poll alone is
-- NOT enough here: the native code shows the frame in the same call that
-- loads the addon, so a 1s poll interval is exactly how long the player
-- would see the unskinned native window flash before the design applies.
-- See `S:WaitForGlobal` for why it is event + poll rather than either
-- alone.
--
-- Real 1.12.1 structure, per `source/wow-ui-source/AddOns/
-- Blizzard_MacroUI/Blizzard_MacroUI.xml`:
-- - `MacroFrameSelectedMacroButton` (id 0), `MacroButton1-18` (`MAX_MACROS`),
--   and `MacroPopupButton1-20` (`NUM_MACRO_ICONS_SHOWN`) ALL inherit the
--   SAME `MacroFrameButtonTemplate`: a 36x36 CheckButton with an UNNAMED
--   BACKGROUND-layer `UI-EmptySlot(-Disabled)` decorative slot texture (64x64,
--   centered, overhangs the button's own footprint) and the real icon on
--   the widget's own `NormalTexture` slot (`$parentIcon`). One shared local
--   styling function (`StyleMacroIconButton`) handles all three families --
--   same "walk GetRegions(), spare only GetNormalTexture()" recipe already
--   proven in SpellBook.lua's own `StyleSkillLineTab` for an identical
--   unnamed-decorative-region shape.
-- - `MacroFrameTab1-2`: plain `TabButtonTemplate`, NOT
--   `CharacterFrameTabButtonTemplate` -- confirmed structurally identical
--   (6-piece BACKGROUND layout) to the Friends/Ignore internal toggle
--   tabs, which use the same plain template. `S:StyleTab` already handles
--   both shapes uniformly. UNLIKE
--   Character/Friends/SpellBook, these two tabs are anchored with a PLAIN
--   0-offset `LEFT`/`RIGHT` join (no native overlap to counteract via the
--   inset backdrop) -- left on `S:StyleTab`'s own default 10/1/3 inset for
--   a first pass rather than inventing a bespoke override; if the resulting
--   gap reads as too wide live, that's a cheap follow-up tweak, not a new
--   investigation.
-- - `MacroFrame`'s own decorative art (portrait, corner pieces, the
--   "Create Macros" title, `MacroFrameSelectedMacroBackground`'s empty-slot
--   art) are all DIRECT Texture regions of `MacroFrame` itself -- confirmed
--   non-nested, matching Character's own established "always read the real
--   FrameXML before deciding recurse vs non-recursive" rule. Recursion is
--   still used (`S:StripTextures(frame, true)`) to reach
--   `MacroFrameTextBackground`'s own native `<Backdrop>` (a plain child
--   Frame, not a Button/CheckButton, so not auto-skipped) -- harmless
--   elsewhere since every other native descendant is either a Button/
--   CheckButton (auto-skipped) or has no Texture regions of its own
--   (`MacroFrameText` the EditBox, `MacroFrameScrollFrame`).
-- - `MacroPopupFrame` is a SEPARATE toplevel frame declared in the SAME
--   XML file as `MacroFrame` -- both come into existence together the
--   moment `Blizzard_MacroUI` loads, so one `LoadSkin` covers both under
--   the single "macro" toggle.
--
-- SCOPE, first pass: outer chrome (strip, elvBackground, close button,
-- draggable), 2 outer tabs, 18 macro-icon slots + the "currently selected"
-- slot, macro-body edit box background, scrollbar; popup chrome (strip,
-- elvBackground, name edit box, 20 icon-picker slots, scrollbar, Okay/
-- Cancel buttons). Deliberately NOT done: repositioning any native element
-- (matches SpellBook.lua's own restraint -- native anchors keep working
-- fine once the underlying decorative art is just invisible), recoloring
-- the unnamed "Create Macros"/popup label FontStrings (no global to grab
-- them by without a bespoke region walk, low value for a first pass).
-- UNTESTED -- first pass on a brand-new, and first LoadOnDemand, window.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

local MAX_MACROS_COUNT = tonumber(_G.MAX_MACROS) or 18
local NUM_MACRO_ICONS = tonumber(_G.NUM_MACRO_ICONS_SHOWN) or 20

-- Everything the native XML anchors to `MacroFrameSelectedMacroBackground`,
-- as TOPLEFT offsets from MacroFrame's own TOPLEFT. Each value is the native
-- offset plus the texture's own position (TOPLEFT 16,-228, 64x64), so the
-- result is pixel-identical to the native layout.
local SLOT_ART_DEPENDENTS = {
	{ "MacroFrameSelectedMacroButton", 30, -242 },
	{ "MacroFrameSelectedMacroName", 76, -243 },
	{ "MacroEditButton", 67, -258 },
	{ "MacroFrameEnterMacroText", 24, -292 },
	{ "MacroFrameScrollFrame", 27, -310 },
}

local function Reanchor(region, point, relativeTo, relativePoint, x, y)
	if not (region and relativeTo) then return end
	pcall(region.ClearAllPoints, region)
	pcall(region.SetPoint, region, point, relativeTo, relativePoint, x, y)
end

-- Shared by MacroFrameSelectedMacroButton, MacroButton1-18 and
-- MacroPopupButton1-20 -- all three families inherit MacroFrameButtonTemplate
-- (see header). Strip pattern ported from SpellBook.lua's own
-- `StyleSkillLineTab` (unnamed decorative region, spared by comparing
-- against GetNormalTexture() rather than by name); icon crop/inset ported
-- from ActionBars.lua's own `StyleButton` (0.08/0.92 crop, 1px inset
-- TOPLEFT/BOTTOMRIGHT) -- this project's one standing icon convention.
local function StyleMacroIconButton(button, clearChecked)
	if not button then return end

	-- CheckedTexture -- a leftover gold ring on
	-- `MacroFrameSelectedMacroButton`. Two UA facts explain it together:
	--
	--  1. `MacroFrameButtonTemplate` declares `<CheckedTexture
	--     alphaMode="ADD" file="Interface\Buttons\CheckButtonHilight"/>`,
	--     and on UA a checked texture renders as a gold/tan tint and is
	--     not reliably gated to the checked STATE (this is why this
	--     project's own `Util.StyleButton` stopped setting one at all).
	--  2. It cannot be reached by the region walk above: a CheckedTexture
	--     does NOT appear in `GetRegions()` on this client (measured via
	--     `S:DumpSpellButton`). So the strip could never have caught it,
	--     on any button, however many times it ran.
	--
	-- The SETTER works though (same shape as `SetDisabledTexture`, whose
	-- getter is likewise missing), so blanking it is a one-liner.
	--
	-- **Opt-in, and deliberately NOT applied to the macro LIST buttons.**
	-- On `MacroButton1-18`/`MacroPopupButton1-20` the checked state is the
	-- native "this is the selected macro" cue (`MacroFrame_Update` calls
	-- `SetChecked(1)` on exactly one of them, Blizzard_MacroUI.lua:76), so
	-- blanking it there would trade a cosmetic bug for a functional one --
	-- this project has made that exact mistake before with the Friends
	-- rows. `MacroFrameSelectedMacroButton` has no such meaning: native
	-- code never `SetChecked(1)`s it (its own OnClick even does
	-- `SetChecked(nil)`), so on that one button the ring is pure noise.
	-- If the list buttons turn out to show the same permanent ring, the fix
	-- there is NOT to blank it too but to mirror `IsChecked()` onto our own
	-- border -- the `StyleDropDownCheck` recipe.
	if clearChecked and not button.elvCheckedCleared then
		button.elvCheckedCleared = true
		pcall(button.SetCheckedTexture, button, "")
	end

	if not button.elvStripped then
		button.elvStripped = true
		local okNormal, normalTexture = pcall(button.GetNormalTexture, button)
		normalTexture = okNormal and normalTexture or nil

		local ok, regions = pcall(function() return { button:GetRegions() } end)
		if ok and type(regions) == "table" then
			local j
			for j = 1, table.getn(regions) do
				local region = regions[j]
				local okType, regionType = pcall(region.GetObjectType, region)
				if okType and regionType == "Texture" and region ~= normalTexture then
					pcall(region.SetTexture, region, nil)
					pcall(region.Hide, region)
					region.Show = E.noop
				end
			end
		end
	end

	ElvUI.Util.CreateButtonBorder(button)

	-- Crop stays at the project-wide 0.08/0.92: the leftover gold frame
	-- was the CheckedTexture cleared above, not the icon art, so no crop
	-- change is needed here.
	local okIcon, icon = pcall(button.GetNormalTexture, button)
	if okIcon and icon and not button.elvIconStyled then
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		icon.SetTexCoord = E.noop
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		button.elvIconStyled = true
	end
end

-- `MacroFrameSelectedMacroButton` is left at its native 36x36 size and
-- anchor -- nothing in this file resizes it. Worth remembering before
-- resizing any native Button in this project: **`SetWidth`/`SetHeight` on
-- a Button does NOT carry its Highlight/Checked/Pushed textures with it
-- on this client** -- those keep their old footprint and have to be
-- re-anchored to the button by hand.

local function ApplyMacroFrameChrome(frame)
	S:StripTextures(frame, true)

	-- `MacroFrameSelectedMacroBackground` -- killed BY NAME, not left to the
	-- recursive strip above.
	--
	-- This is the gold ring around the selected-macro preview icon: it's
	-- not drawn ON the button at all, but is `UI-EmptySlot`, a 64x64 direct
	-- ARTWORK region of `MacroFrame` centred on that slot
	-- (Blizzard_MacroUI.xml:172), whose visible ring sits at roughly
	-- 44-48px -- bigger than the button's own native 36x36 footprint, so it
	-- shows around the button rather than under it.
	--
	-- Why by name: `S:StripTextures(frame, true)` should already have
	-- caught it as a direct region, and does not. The likeliest reason is
	-- enumeration, not the removal recipe -- this client is already known
	-- to return short/empty multi-return lists on frames with many
	-- children, and `MacroFrame` carries a lot of regions. A `_G` lookup
	-- cannot be truncated, so it sidesteps the question entirely.
	-- `SetAlpha(0)` is added as a third, independent mechanism alongside
	-- `S:Kill`'s Hide()+noop and the texture clear.
	--
	-- NOT `DisableDrawLayer("ARTWORK")`, the usual heavy hammer for a native
	-- region that won't die: on THIS frame that layer also carries
	-- `MacroFrameSelectedMacroName`, `MacroFrameEnterMacroText` and
	-- `MacroFrameCharLimitText` (checked in the XML, all three in the same
	-- `<Layer>` block) -- it would take the macro's name, the "Enter Macro
	-- Commands:" label and the character counter down with it.
	local slotArt = _G.MacroFrameSelectedMacroBackground
	if slotArt then
		pcall(slotArt.SetTexture, slotArt, nil)
		pcall(slotArt.SetAlpha, slotArt, 0)
		S:Kill(slotArt)
	end

	-- A hidden Texture does not resolve as an anchor on the legacy 1.12.1
	-- client: its GetTop() returns a stale off-screen value, SetPoint() on it
	-- has no effect while it stays hidden, and everything anchored to it (the
	-- preview icon, its name, Change Name/Icon, the "Enter Macro Commands:"
	-- label and the whole macro-body scroll frame) renders 130-160px too
	-- low. So the dependents are anchored to MacroFrame instead. Keeping the
	-- texture shown and merely blank is not an alternative: on UA
	-- SetTexture(nil) does not reliably stop a native texture from
	-- rendering, and the gold slot ring would come back.
	local j
	for j = 1, table.getn(SLOT_ART_DEPENDENTS) do
		local entry = SLOT_ART_DEPENDENTS[j]
		Reanchor(_G[entry[1]], "TOPLEFT", frame, "TOPLEFT", entry[2], entry[3])
	end

	-- The character counter natively overlaps the text field's bottom edge
	-- by a few pixels, hidden by the native backdrop's 5px inset. The field
	-- surface below is a child frame drawn above MacroFrame's own regions,
	-- so the counter would be half covered; it goes directly under the field
	-- instead (real ElvUI moves it below the field as well).
	Reanchor(_G.MacroFrameCharLimitText, "TOP", _G.MacroFrameTextBackground, "BOTTOM", 0, -1)

	S:CreatePanel(frame, 10, -11, -32, 71)

	S:StyleCloseButton(_G.MacroFrameCloseButton)

	StyleMacroIconButton(_G.MacroFrameSelectedMacroButton, true)
	local i
	for i = 1, MAX_MACROS_COUNT do
		StyleMacroIconButton(_G["MacroButton"..i])
	end

	for i = 1, 2 do
		S:StyleTab(_G["MacroFrameTab"..i])
	end

	-- Edit/Delete/New/Exit are NOT listed here: they are plain
	-- `UIPanelButtonTemplate` children of MacroFrame, so the sweep at the
	-- end of this function recognises them from the template's own art.
	-- The icon buttons above keep their dedicated call -- their
	-- NormalTexture IS the icon, which the sweep deliberately never
	-- touches.

	-- Macro-body text area: `MacroFrameTextBackground`
	-- (Blizzard_MacroUI.xml:449-477) is a plain Frame whose entire purpose
	-- is its own `<Backdrop>` -- `UI-Tooltip-Background` + a 16px tiled
	-- `UI-Tooltip-Border`, with an `<OnLoad>` that re-asserts both colors
	-- on itself. `SetBackdrop` on a native frame like this is confirmed
	-- unreliable on this client (ReputationDetailFrame, DropDownList1-3),
	-- so it goes through `S:CreateSurface` (via `S:CreateField` below), a
	-- real child frame that draws, with `WIDGET_COLOR` rather than
	-- `PANEL_COLOR` -- the same tone as the window behind it would make
	-- the field invisible.
	--
	-- Deliberately `S:CreateField` rather than `S:StyleEditBox`: the widget
	-- the user types into is `MacroFrameText`, which lives inside
	-- `MacroFrameScrollFrame` and scrolls -- it has no fixed footprint to
	-- border. This holder frame is the thing with the field's actual
	-- geometry, exactly as Blizzard intended it.
	S:CreateField(_G.MacroFrameTextBackground)

	S:HandleScrollBar(_G.MacroFrameScrollFrameScrollBar)

	-- Catch-all pass -- see `S:SkinChildren` (Skins.lua).
	S:SkinChildren(frame)
end

local function ApplyMacroPopupChrome()
	local frame = _G.MacroPopupFrame
	if not frame then return end

	S:StripTextures(frame, true)

	S:CreatePanel(frame)

	S:StyleEditBox(_G.MacroPopupEditBox)

	local i
	for i = 1, NUM_MACRO_ICONS do
		StyleMacroIconButton(_G["MacroPopupButton"..i])
	end

	S:HandleScrollBar(_G.MacroPopupScrollFrameScrollBar)

	-- Catch-all pass -- see `S:SkinChildren` (Skins.lua).
	-- `MacroPopupFrame` is a separate toplevel frame, not a descendant of
	-- MacroFrame, so it needs its own sweep.
	S:SkinChildren(frame)
end

-- Runs the one-time-per-frame setup (drag handle, OnShow hooks) plus the
-- first chrome pass. Only ever called once `MacroFrame` exists --
-- `S:WaitForGlobal` owns that wait now (see `LoadSkin` below).
local macroSkinApplied = false
local function ApplyMacroSkin()
	if macroSkinApplied then return end
	local frame = _G.MacroFrame
	if not frame then return end
	macroSkinApplied = true

	S:MakeDraggable(frame, _G.MacroFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyMacroFrameChrome(frame)
	local ok = S:TryHookScript(frame, "OnShow", function() ApplyMacroFrameChrome(frame) end)
	if not ok then S:ReportSkinProblem() end

	ApplyMacroPopupChrome()
	local okPopup = S:TryHookScript(_G.MacroPopupFrame, "OnShow", ApplyMacroPopupChrome)
	if not okPopup then S:ReportSkinProblem() end
end

-- A hand-rolled `E:ScheduleRepeatingTimer(..., 1)` poll would flash the
-- unskinned native window: `MacroFrame_LoadUI` loads this addon and
-- `ShowUIPanel()`s the frame in the same breath, so a 1s poll interval
-- leaves the unskinned window on screen for up to a full tick before the
-- poll next looks.
--
-- `S:WaitForGlobal` (Skins.lua) uses ADDON_LOADED instead (fires DURING
-- `LoadAddOn`, i.e. before the native Show -- so there is no unskinned
-- frame to see at all) plus a 0.1s poll as the backstop in case UA
-- doesn't fire that event for on-demand addons. Full reasoning at the
-- function itself. **Any future LoadOnDemand window (Trade Skill, Auction
-- House) should use it too rather than growing its own timer.**
local function LoadSkin()
	S:WaitForGlobal("MacroFrame", ApplyMacroSkin)
end

S:AddBlizzardSkin("macro", LoadSkin)
