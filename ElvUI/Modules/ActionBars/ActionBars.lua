-- ActionBars module.
--
-- Re-skins native action buttons IN PLACE -- matching real ElvUI's own
-- approach (ElvUI-vanilla/ElvUI/Modules/ActionBars/ActionBars.lua):
-- these are secure/protected buttons, so we template/skin the EXISTING
-- globals, never create new button widgets. A new plain container frame
-- per bar (NOT a secure template) is created and each bar's buttons are
-- reparented onto it via SetParent -- a secure frame's own security comes
-- from ITS OWN template inheritance chain, not its current parent, so
-- reparenting a secure button onto a plain non-secure container doesn't
-- strip its security (confirmed on UA via the Bagzen addon, which relies
-- on the identical technique).
--
-- Covers all 5 native bars real ElvUI itself covers: bar1 =
-- ActionButton1..12, bars 2-5 = the four native MultiBars, matching real
-- ElvUI's own barDefaults mapping (MultiBarBottomRight/Right/Left/
-- BottomLeft). Each bar is its own independent mover (see
-- DEFAULT_Y_OFFSET/CreateBar() below and Core/Movers.lua) -- stacked
-- vertically above bar1 only as a FIRST-RUN starting arrangement, freely
-- draggable/nudgeable afterward via /moveui.
--
-- Other native actionbar-adjacent chrome (stance bar, pet bar, the
-- default bar's background art, the latency indicator) is hidden so only
-- the ElvUI-styled bars show. A bar disabled via config falls back to
-- being hidden the same way, rather than left in its native state. The
-- native XP bar and Reputation watch bar (ReputationWatchBar) are NOT
-- hidden here -- see the CHROME_TO_HIDE comment below: those are
-- Modules/DataBars/XPBar.lua's and Modules/DataBars/ReputationBar.lua's
-- job respectively, each replacing its native bar with its own styled one
-- rather than just deleting it.
--
-- Config: per-bar settings (enabled, buttons, buttonsPerRow, buttonsize,
-- buttonspacing, backdrop, alpha, showGrid) ported from real
-- ElvUI_Config/ActionBars.lua's `for i = 1, 5 do ... end` block, plus
-- module-wide hotkeytext/macrotext/lockActionBars from its "general"
-- group. Deliberately NOT ported (needs infrastructure this project
-- doesn't have, or is much lower value for a first pass): anchor
-- point/widthMult/heightMult/backdropSpacing, mouseover-fade/
-- inheritGlobalFade (no fade system), restorePosition (no mover system,
-- no E:CreateMover), pet bar, stance bar, microbar, per-state button
-- colors, the LSM font group, keyDown, useRangeColorText, the Cooldown
-- Text/Keybind Mode shortcuts.
--
-- First real touch of Blizzard's secure action button system in this
-- project. Most important UA-specific finding: Blizzard's own code
-- re-asserts several pieces of default visual state (button.
-- SetNormalTexture, icon.SetTexCoord, hotkey.SetVertexColor) whenever a
-- slot's action changes, silently undoing a one-time style pass, so those
-- methods are permanently overridden to a no-op (E.noop) after being
-- called once -- and several native frames turn out to be created LAZILY
-- well after login (ExhaustionTick, ActionButtonNNormalTexture apparently
-- among them), so both HideChrome() and StyleButton() are re-run
-- periodically, not just once at Initialize(), to catch anything that
-- didn't exist yet the first time.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local Compat = ElvUI.Compat
local M = E:NewModule("ActionBars", "AceEvent-3.0")
E.ActionBars = M

-- LibSharedMedia-3.0 -- font media registered in Media/SharedMedia.lua
-- (the client's own 4 built-in font files). ElvUI_Config/Core.lua's font
-- picker is a plain "select" reading LSM:List("font") -- NOT the
-- LSM30_Font AceGUI widget since AceGUI isn't vendored here. Neither this
-- (LSM:Fetch + SetFont) nor a SetFontObject/virtual-Font-object approach
-- actually changes the rendered font on UA -- see ApplyFont() below.
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Settings: `V.actionbar` (Settings/Private.lua), `P.actionbar` plus the
-- per-bar `P.actionbar.bar1..bar5`/`barPet`/`barShapeShift` tables
-- (Settings/Profile.lua).
--
-- The font settings are kept in the config UI even though they currently
-- have NO visible effect on UA -- neither this SetFont-based mechanism nor
-- a SetFontObject approach changes the rendered font there; see ApplyFont()
-- below. NOT ported: the text color picker and the Stack/Hotkey Text
-- Position X/Y offset group.

-- `prefix..i` must produce the ACTUAL native button name -- "ActionButton"
-- already ends in "Button" (native names are ActionButton1..12), but the
-- MultiBars' own numbered buttons are named e.g.
-- "MultiBarBottomRightButton1", not "MultiBarBottomRight1" -- so "Button"
-- has to be baked into the prefix for those, not assumed.
--
-- Bar SETTINGS (button count, row width, backdrop, enabled) are not here --
-- they live in Settings/Profile.lua as `P.actionbar.bar1..bar5`, read at
-- runtime from `E.db.actionbar["bar"..id]`. This table is only the mapping
-- from our bar number to the native button-name prefix it drives.
local BAR_DEFS = {
	{ id = 1, prefix = "ActionButton" },
	{ id = 2, prefix = "MultiBarBottomRightButton" },
	{ id = 3, prefix = "MultiBarRightButton" },
	{ id = 4, prefix = "MultiBarLeftButton" },
	{ id = 5, prefix = "MultiBarBottomLeftButton" },
}

-- FIRST-RUN-ONLY vertical gap between two stacked bars' starting
-- positions (see DEFAULT_Y_OFFSET below -- once a mover exists for a
-- bar, this is never consulted again; see ElvUI.Util.BarPadding's own
-- comment, Core/Util.lua, for the actual per-bar padding this doesn't
-- replace). At ROW_GAP=0, two vertically stacked bars' closest button
-- rows have their black button borders sit directly against each other,
-- leaving nothing to shine through from whatever's behind the
-- transparent bar container (bar1 defaults to `backdrop=false`).
-- Horizontal `buttonspacing` (2, unchanged) doesn't have the same problem
-- since it's the same value used consistently within one bar's own
-- single styling pass -- this gap specifically only affects two
-- INDEPENDENT bars' default relative starting position.
local ROW_GAP = 0

-- First-run-only starting positions. Each bar is its own independent
-- E:CreateMover (see Core/Movers.lua and CreateBar() below) -- these
-- offsets only matter the FIRST time a bar is ever created (no
-- E.db.movers["ElvAB_"..id] entry yet); after that, the mover system owns
-- each bar's position and these are never consulted again. Assumes the
-- default single-row 32px-button/8px-container-padding layout (~40px
-- tall, matching PositionOneBar's own `size*rows + spacing*(rows-1) + 8`
-- formula for a single row) stacked with ROW_GAP between -- just a
-- reasonable starting arrangement, not recalculated for other size/row
-- configs (draggable/nudgeable to fix that, same as a fresh real ElvUI
-- install's own defaults).
local DEFAULT_BAR_HEIGHT = 40
local DEFAULT_Y_OFFSET = {}
do
	local i
	for i = 1, 5 do
		DEFAULT_Y_OFFSET[i] = 4 + (i - 1) * (DEFAULT_BAR_HEIGHT + ROW_GAP)
	end
end
-- Every bar always reparents/styles all 12 possible buttons regardless of
-- the `buttons` config value -- matching real ElvUI's own
-- PositionAndSizeBar, which loops `for i = 1, NUM_ACTIONBAR_BUTTONS`
-- unconditionally and only visually hides the ones beyond the configured
-- count (SetScale(0.000001) + SetAlpha(0), ActionBars.lua:148-154) rather
-- than skipping their setup entirely. Matters for live config changes:
-- if buttons were only reparented up to the ORIGINAL `buttons` value, a
-- later increase via ElvUI_Config wouldn't be able to pull in the extra
-- ones at all (never reparented in the first place) without a /reload.
local MAX_BUTTONS = 12

-- Other native bars/chrome that would otherwise overlap or duplicate our
-- own bars. Names taken directly from real ElvUI's own
-- AB:DisableBlizzard() rather than guessed -- ShapeshiftBarLeft/Middle/
-- Right are the stance bar's own decorative texture pieces (likely
-- Texture, not Frame, objects -- real ElvUI guards this with a
-- GetObjectType() == "Frame" check before UnregisterAllEvents; here every
-- call is already pcall-wrapped, which covers the same case without
-- needing the extra type check). MainMenuBarArtFrame is the default
-- bar's background art/border texture -- hidden so our own backdrop
-- shows instead, NOT the frame the buttons themselves live under
-- (MainMenuBar stays alone, only mouse-disabled, since ActionButton1..12
-- render fine regardless of what we do to their art frame). The four
-- MultiBar containers are NOT in this list -- they're used as bars 2-5
-- instead (see HideDisabledBar for what happens if a bar is disabled).
--
-- "MainMenuExpBar"/"ExhaustionTick" (the native XP bar and its rested-XP
-- tick mark) and "ReputationWatchBar" (the native reputation watch bar,
-- shown by the Character panel's "Show as Experience Bar" checkbox) are
-- deliberately NOT in this list: real ElvUI replaces both with its own
-- styled bar rather than just deleting the native one, and hiding them
-- as generic undifferentiated chrome here (with no replacement) means
-- re-enabling the native checkbox brings Blizzard's own bar straight
-- back. Hiding them -- and, for the reputation bar, the 12 named child
-- pieces a parent Hide() doesn't reach on UA -- is Modules/DataBars/
-- XPBar.lua's and Modules/DataBars/ReputationBar.lua's own job
-- respectively, done right before each builds its own replacement bar
-- (same "hide native, build ours" pattern already used for ActionBars'
-- own buttons/PetBar). Don't re-add either name here.
local CHROME_TO_HIDE = {
	"MainMenuBarArtFrame",
	"BonusActionBarFrame",
	"PetActionBarFrame",
	"ShapeshiftBarFrame",
	"ShapeshiftBarLeft",
	"ShapeshiftBarMiddle",
	"ShapeshiftBarRight",
	-- Not in real ElvUI's own DisableBlizzard() list and not referenced
	-- anywhere in UnrealUI (which builds its own replacement XP/status
	-- bars from scratch instead of hiding these natives) -- found via
	-- direct in-game inspection instead. MainMenuBarPerformanceBar is the
	-- latency/performance indicator (rendered as a small vertical bar) --
	-- unrelated to the XP bar.
	"MainMenuBarPerformanceBar",
}

-- Blizzard's own layout manager (UIParent_ManageFramePositions, run on
-- various events) re-applies position/visibility for anything still
-- registered here -- clearing these entries stops it from undoing our
-- own positioning of bars 2-5 later. Matches real ElvUI's own
-- uiManagedFrames list exactly -- PETACTIONBAR_YPOS is a position-offset
-- key in the same table, not a frame name, but still needs clearing.
local MANAGED_FRAME_KEYS = {
	"MultiBarLeft",
	"MultiBarRight",
	"MultiBarBottomLeft",
	"MultiBarBottomRight",
	"ShapeshiftBarFrame",
	"PETACTIONBAR_YPOS",
}

-- A plain one-time Hide() isn't enough for a frame like the XP bar that
-- Blizzard's own code re-shows -- neither is clearing OnUpdate/OnEvent
-- alone: `UnregisterEvent`/`UnregisterAllEvents` do not work on UA, so
-- EVENT-driven re-shows can't be stopped by unregistering on this client.
-- Kept the UnregisterAllEvents call anyway since it still works on real
-- 1.12.1 and costs nothing there, but it can't be trusted alone on UA.
-- The robust fix: permanently overriding Show() itself to a no-op -- same
-- one-shot-then-permanently-neutered trick used for button.
-- SetNormalTexture below. Doesn't matter what mechanism (event, OnUpdate,
-- or anything else) tries to re-show the frame afterward; Show() itself
-- can't do anything anymore.
local function HideFrame(frame)
	if not frame then return end
	pcall(frame.UnregisterAllEvents, frame)
	pcall(frame.SetScript, frame, "OnEvent", nil)
	pcall(frame.SetScript, frame, "OnUpdate", nil)
	pcall(frame.Hide, frame)
	pcall(frame.SetAlpha, frame, 0)
	if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
	if frame.Show then
		frame.Show = E.noop
	end
end

-- A bar the user has disabled via config: fall back to hiding its
-- buttons directly, same technique as the old blanket MultiBar-hiding
-- this module used before bars 2-5 existed (confirmed necessary then:
-- hiding just the container frame isn't enough, its numbered buttons
-- aren't reliably hierarchy-hidden by the parent's Hide()).
local function HideDisabledBar(barDef)
	local i
	for i = 1, MAX_BUTTONS do
		HideFrame(_G[barDef.prefix..i])
	end
end

local function HideChrome()
	for _, name in ipairs(CHROME_TO_HIDE) do
		HideFrame(_G[name])
	end

	if type(_G.UIPARENT_MANAGED_FRAME_POSITIONS) == "table" then
		for _, key in ipairs(MANAGED_FRAME_KEYS) do
			_G.UIPARENT_MANAGED_FRAME_POSITIONS[key] = nil
		end
	end

	local mainBar = _G.MainMenuBar
	if mainBar and mainBar.EnableMouse then
		pcall(mainBar.EnableMouse, mainBar, false)
	end
end

-- Mapping LSM font names to XML-declared virtual Font objects +
-- SetFontObject (Media/Fonts.xml) was tried as an alternative to the
-- simpler LSM:Fetch + SetFont version below, since SetFont itself is a
-- no-op on UA -- SetFontObject had no visible effect either. Kept to the
-- simpler LSM:Fetch + SetFont version since it's no more or less
-- functional and simpler to reason about. Neither mechanism currently
-- changes the rendered font on UA.
local function ApplyFont(fontString)
	if not fontString then return end
	local desiredFamily = E.db.actionbar.font
	local desiredSize = E.db.actionbar.fontSize
	local desiredOutline = E.db.actionbar.fontOutline
	if fontString.elvFont == desiredFamily
		and fontString.elvFontSize == desiredSize
		and fontString.elvFontOutline == desiredOutline then
		return
	end
	local path = LSM and LSM:Fetch("font", desiredFamily)
	if not path then
		path = fontString:GetFont()
	end
	if path then
		-- "NONE" is real ElvUI's own stored sentinel for "no outline"
		-- (see Settings/Profile.lua) -- the native SetFont
		-- wants an empty string for that, not the literal word "NONE".
		local outlineFlag = desiredOutline
		if outlineFlag == "NONE" then outlineFlag = "" end
		pcall(fontString.SetFont, fontString, path, desiredSize, outlineFlag)
	end
	fontString.elvFont = desiredFamily
	fontString.elvFontSize = desiredSize
	fontString.elvFontOutline = desiredOutline
end

-- Per-button border construction lives in `ElvUI.Util.CreateButtonBorder`/
-- `CreateButtonHoverTextures` (Core/Util.lua) -- extracted there once
-- Modules/PetBar.lua needed the identical styling, so both modules (and
-- any future one) share a single implementation instead of drifting
-- apart. See that file's own comment for the pixel-measured backdrop
-- shape and the missing-`edgeFile` gold-tint bug it fixes.

-- The native ActionButtonTemplate's OnDragStart/OnReceiveDrag scripts
-- (real FrameXML: `PickupAction`/`PlaceAction(ActionButton_GetPagedID(this))`)
-- rely on the client's implicit `this` binding for the button that fired
-- the event. Once a button is reparented off its native bar container,
-- that binding resolves unreliably in opposite directions on the two
-- clients -- confirmed live: UA silently drops PlaceAction on a drop
-- (drag onto the bar), the real 1.12.1 client silently drops PickupAction
-- on a drag-start (drag off the bar), while the underlying `PlaceAction`/
-- `PickupAction` calls and `ActionButton_GetPagedID` slot resolution are
-- both fine in isolation. Replacing both scripts with closures that
-- reference `button` directly, never `this`, fixes both directions on
-- both clients -- the same approach UnrealUI's own actionbar module uses
-- for the identical reason (it never relies on the native
-- ActionButtonTemplate scripts at all). `LOCK_ACTIONBAR` mirrors the
-- native guard exactly (see M:Initialize, `E.db.actionbar.lockActionBars`).
local function WireButtonDrag(button)
	if button.elvDragWired then return end
	button.elvDragWired = true

	button:SetScript("OnDragStart", function()
		if LOCK_ACTIONBAR == "1" then return end
		local slot = ActionButton_GetPagedID(button)
		if slot then pcall(PickupAction, slot) end
	end)

	button:SetScript("OnReceiveDrag", function()
		if LOCK_ACTIONBAR == "1" then return end
		local slot = ActionButton_GetPagedID(button)
		if slot then pcall(PlaceAction, slot) end
	end)
end

-- Re-skins one native action button in place.
local function StyleButton(button, showGrid)
	if not button then return end

	WireButtonDrag(button)

	local name = button:GetName()
	local icon = _G[name.."Icon"]
	local border = _G[name.."Border"]
	local normalTexture = _G[name.."NormalTexture"]

	-- UNGUARDED, unlike the icon/hotkey-text guards below: this native
	-- flyout/spec border region gets re-Shows() by Blizzard's own native
	-- ActionButton_Update whenever a slot's action changes (placing or
	-- moving a spell) -- the same class of re-assertion bug found for
	-- ChatFrameMenuButton and the native buff buttons elsewhere in this
	-- project, where a one-time kill doesn't survive Blizzard's own later
	-- re-assertion. A guard here (running this only once ever) would leave
	-- the border visibly doubled/offset after any live slot change until
	-- a full /reload. Hide() on an already-hidden region is a visual
	-- no-op, so re-running this unconditionally on every StyleButton()
	-- call (including the periodic resweep AND the ACTIONBAR_SLOT_CHANGED
	-- trigger below) carries none of the flicker risk that made the
	-- icon/hotkey-text guards below necessary to keep.
	if border then
		pcall(border.Hide, border)
	end

	-- Forces the empty-slot "grid" outline to stay visible even when a
	-- slot has no action -- matches real ElvUI's own
	-- ActionButton_ShowGrid(button) call and its config's per-bar "Show
	-- Empty Buttons" toggle. Without this, empty slots render as nothing
	-- at all (no backdrop visible).
	if showGrid then
		pcall(ActionButton_ShowGrid, button)
	end

	-- The rounded-corner metal frame around the icon is NOT part of the
	-- icon texture -- it's the button's own NormalTexture region.
	-- `button:SetNormalTexture("")` (an empty string) does NOT clear it;
	-- `SetTexture(nil)` directly on the ...NormalTexture region does.
	-- Guarded (`SetTexture ~= E.noop`) so the periodic resweep doesn't
	-- keep re-clearing an already-cleared region -- re-touching this every
	-- sweep causes a visible flicker.
	--
	-- Recoloring this region dark instead of clearing it, to double as an
	-- empty-slot background on bars 2-5, does NOT work: NormalTexture
	-- draws ABOVE the icon layer, so an opaque fill hides every icon, not
	-- just empty slots. Bars 2-5 also sit inside a UA screen-space band
	-- where brand-new CreateFrame-based children never render, which is
	-- why bar1's own elvBackdrop (below) can't simply be copied onto them
	-- either. An empty-slot background on bars 2-5 is a parked, understood
	-- limitation, not a bug.
	if not button.elvNormalTextureCleared then
		pcall(button.SetNormalTexture, button, "")
		button.SetNormalTexture = E.noop
		button.elvNormalTextureCleared = true
	end
	if normalTexture and normalTexture.SetTexture ~= E.noop then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		normalTexture.SetTexture = E.noop
	end

	-- Dark backdrop square -- shared with Modules/PetBar.lua, see
	-- ElvUI.Util.CreateButtonBorder (Core/Util.lua) for the full
	-- construction and design history.
	ElvUI.Util.CreateButtonBorder(button)
	ElvUI.Util.RaiseCooldown(button)

	-- Util.CreateButtonHoverTextures (hover/pushed/checked) is deliberately
	-- NOT called here -- prime suspect for a gold/tan tint that appears
	-- across every button on UA once it's used (both ActionBars AND
	-- PetBar, which share this same call). The PUSHED texture's color is
	-- `{0.9, 0.8, 0.1, 0.3}` -- a literal gold/yellow tone, matching the
	-- symptom. Theory: on UA, the pushed (and/or hover/checked) texture
	-- may not be gated to its normal interaction state and instead
	-- renders constantly, tinting every button. Left unused entirely (not
	-- just the pushed one) to isolate the cause cleanly -- re-add only
	-- after confirming which specific texture was responsible.

	-- GUARDED: icon/hotkey/macroName repositioning must not run
	-- unconditionally on every StyleButton() call, since the periodic
	-- resweep would otherwise redo ClearAllPoints+SetPoint from scratch
	-- every pass even when nothing changed, causing a visible flicker
	-- (hotkey text flashing). Same fix pattern as the NormalTexture guard
	-- above: only redo the work when it hasn't been done yet (icon) or the
	-- desired state actually changed (hotkey/macroName, which depend on a
	-- live config toggle that CAN legitimately change between sweeps).
	if icon and not button.elvIconStyled then
		-- 0.08/0.92 matches real ElvUI's own default E.TexCoords exactly
		-- (ElvUI-vanilla/ElvUI/Core/core.lua) -- crops off the
		-- rounded-corner border baked into every stock WoW icon texture.
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		icon.SetTexCoord = E.noop
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		button.elvIconStyled = true
	end

	-- Hotkey (keybind) and macro-name text. Position/visibility/color,
	-- plus font family via ApplyFont() below -- no SHIFT-/ALT-/CTRL-
	-- abbreviation substitution (real ElvUI's FixKeybindText is skipped,
	-- low value for a first pass; native abbreviated text is left as-is).
	-- Module-wide, not per-bar -- matches real ElvUI's own config, which
	-- puts these in the "general" group, not the per-bar groups.
	local hotkey = _G[name.."HotKey"]
	-- The guard tracks the POSITION as well as the on/off mode: without the
	-- position in the signature, changing hotkeyTextPosition/XOffset/YOffset
	-- would only take effect the next time the mode itself was toggled.
	local hotkeyState = tostring(E.db.actionbar.hotkeytext)
		.."|"..tostring(E.db.actionbar.hotkeyTextPosition)
		.."|"..tostring(E.db.actionbar.hotkeyTextXOffset)
		.."|"..tostring(E.db.actionbar.hotkeyTextYOffset)
	if hotkey and button.elvHotkeyMode ~= hotkeyState then
		if E.db.actionbar.hotkeytext then
			hotkey:ClearAllPoints()
			hotkey:SetPoint(E.db.actionbar.hotkeyTextPosition or "TOPRIGHT", button,
				E.db.actionbar.hotkeyTextPosition or "TOPRIGHT",
				E.db.actionbar.hotkeyTextXOffset or 0,
				E.db.actionbar.hotkeyTextYOffset or -3)
			pcall(hotkey.SetTextColor, hotkey, 0.9, 0.9, 0.9)
			-- Same re-assertion problem as SetNormalTexture/SetTexCoord --
			-- real ElvUI overrides this exact method for this exact
			-- reason (`hotkey.SetVertexColor = E.noop`), applied here
			-- pre-emptively.
			hotkey.SetVertexColor = E.noop
			hotkey:Show()
		else
			hotkey:Hide()
			hotkey.Show = E.noop
		end
		button.elvHotkeyMode = hotkeyState
	end
	ApplyFont(hotkey)

	local macroName = _G[name.."Name"]
	if macroName and button.elvMacroMode ~= E.db.actionbar.macrotext then
		if E.db.actionbar.macrotext then
			macroName:ClearAllPoints()
			macroName:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
			pcall(macroName.SetJustifyH, macroName, "CENTER")
			macroName:Show()
		else
			macroName:Hide()
			macroName.Show = E.noop
		end
		button.elvMacroMode = E.db.actionbar.macrotext
	end
	ApplyFont(macroName)
end

-- `P` (Engine[4]) is only ever touched above, at file-load time, to
-- register DEFAULTS -- every runtime read below goes through
-- `E.db.actionbar`, the LIVE merged table, matching the same
-- V/P-are-defaults-only, E.private/E.db-are-live split Minimap.lua
-- already established (the same class of mistake as WorldMap.lua's
-- `G`-vs-`E.global` bug: reading the defaults table directly at runtime
-- instead of the live merged one).

function M:CreateBar(barDef)
	local barSettings = E.db.actionbar["bar"..barDef.id]

	if not barSettings.enabled then
		HideDisabledBar(barDef)
		return nil
	end

	local ok, bar = pcall(CreateFrame, "Frame", "ElvUIActionBarHolder"..barDef.id, UIParent)
	if not ok or not bar then return nil end

	pcall(bar.SetBackdrop, bar, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(bar.SetBackdropColor, bar, 0.1, 0.1, 0.1, 1)
	pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 1)

	-- First-run starting position only -- E:CreateMover below captures
	-- whatever's here as its reset default, then owns the bar's actual
	-- position from here on (drag/nudge via /moveui, persisted in
	-- E.db.movers["ElvAB_"..id], real-ElvUI-format -- see Core/Movers.lua).
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, DEFAULT_Y_OFFSET[barDef.id] or 4)
	E:CreateMover(bar, "ElvAB_"..barDef.id, L["Bar "]..barDef.id)

	bar.buttons = {}
	local i
	for i = 1, MAX_BUTTONS do
		local button = _G[barDef.prefix..i]
		if button then
			pcall(button.SetParent, button, bar)
			bar.buttons[i] = button
			StyleButton(button, barSettings.showGrid)
		end
	end

	return bar
end

-- Sizes one bar and lays out its buttons in a buttonsPerRow-wrapped grid;
-- shows/hides just the bar's own BACKGROUND PANEL FILL per its
-- `backdrop`/`alpha` settings. Does NOT touch the bar's own screen
-- POSITION -- that's owned entirely by the mover system now
-- (E:CreateMover in CreateBar() above), not chained to other bars here
-- anymore.
--
-- `backdrop` toggles only an optional BACKGROUND PANEL behind the row of
-- buttons (real ElvUI: a SEPARATE `bar.backdrop` child region, shown/
-- hidden independently -- ElvUI-vanilla/ElvUI/Modules/ActionBars/
-- ActionBars.lua) -- it has nothing to do with whether the BAR ITSELF
-- (and every button parented to it) is visible. Since real ElvUI's own
-- per-bar defaults have `backdrop = false` for bar1/2/3/5 (only bar4
-- defaults to true -- see BAR_DEFS above), toggling the BAR's own
-- Show/Hide off `barSettings.backdrop` would make bar1 (the MAIN action
-- bar) start completely invisible, buttons included, on any fresh
-- install. This project's own container frame doubles as both the "bar"
-- AND its background panel (no separate `bar.backdrop` region), so
-- `backdrop` instead toggles the backdrop's fill/border ALPHA --
-- `bar:Show()` is unconditional here (enabling/disabling the BAR entirely
-- is CreateBar's job, via `barSettings.enabled` and HideDisabledBar).
-- How far the button grid sits inset from the bar container's own edge
-- on each side -- `ElvUI.Util.BarPadding` (Core/Util.lua), matching real
-- ElvUI's own `(backdrop and E.Border+backdropSpacing or E.Spacing)*2`
-- formula exactly (NOT one flat constant for every bar -- depends on the
-- bar's OWN `backdrop` setting). Extracted there once Modules/PetBar.lua
-- needed the identical calculation.

local function PositionOneBar(bar, barSettings)
	local size = barSettings.buttonsize
	local spacing = barSettings.buttonspacing
	local perRow = math.max(barSettings.buttonsPerRow or 12, 1)
	local buttonCount = barSettings.buttons
	local rows = math.ceil(buttonCount / perRow)
	local cols = math.min(buttonCount, perRow)
	local padding = ElvUI.Util.BarPadding(barSettings)

	local barWidth = (size * cols) + (spacing * (cols - 1)) + (padding * 2)
	local barHeight = (size * rows) + (spacing * (rows - 1)) + (padding * 2)

	bar:SetWidth(barWidth)
	bar:SetHeight(barHeight)
	pcall(bar.SetAlpha, bar, barSettings.alpha or 1)
	pcall(bar.Show, bar)
	local backdropAlpha = barSettings.backdrop and 1 or 0
	pcall(bar.SetBackdropColor, bar, 0.1, 0.1, 0.1, backdropAlpha)
	pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, backdropAlpha)

	local i
	for i = 1, MAX_BUTTONS do
		local button = bar.buttons[i]
		if button then
			local row = math.floor((i - 1) / perRow)
			local col = Compat.mod(i - 1, perRow)

			-- Buttons are anchored from BOTTOMLEFT (row 0 = highest Y),
			-- but button NUMBERING should always read top-to-bottom
			-- regardless of layout -- with buttonsPerRow=1 (a 1-wide
			-- vertical bar), the un-inverted `row` puts button 1 at the
			-- BOTTOM and button 12 at the TOP, backwards from how a
			-- vertical bar reads. Inverting via `rows - 1 - row` fixes
			-- that while staying a no-op for the default single-row
			-- horizontal case (rows=1 -> visualRow always equals row,
			-- since rows-1-0 = 0).
			local visualRow = rows - 1 - row

			pcall(button.SetWidth, button, size)
			pcall(button.SetHeight, button, size)
			button:ClearAllPoints()
			pcall(button.SetPoint, button, "BOTTOMLEFT", bar, "BOTTOMLEFT",
				padding + col * (size + spacing), padding + visualRow * (size + spacing))

			-- Beyond the configured `buttons` count: still positioned
			-- (harmless, invisible anyway) rather than skipped, matching
			-- real ElvUI's own SetScale(0.000001)/SetAlpha(0) trick
			-- instead of Hide() -- presumably to avoid calling Hide() on
			-- a protected button, which may be more restricted in combat
			-- than a plain visual scale/alpha change. Explicitly restored
			-- to normal for buttons WITHIN the count too, so lowering
			-- then raising `buttons` again (live, via config) correctly
			-- re-shows them.
			if i > buttonCount then
				pcall(button.SetScale, button, 0.000001)
				pcall(button.SetAlpha, button, 0)
			else
				pcall(button.SetScale, button, 1)
				pcall(button.SetAlpha, button, 1)
			end
		end
	end

	return barWidth, barHeight
end

-- Real ElvUI overrides the global ActionButton_GetPagedID exactly for
-- this reason. Without this, reparenting a MultiBar's buttons onto our
-- own container confuses Blizzard's own action-ID resolution -- keybinds
-- (resolved from a separate, static binding table) stay correct, but the
-- icon/tooltip content shown on bars 2-5 falls back to bar1's own actions
-- instead of the MultiBar's own. Blizzard's default implementation
-- resolves a
-- button's action slot via checking its PARENT frame's NAME against the
-- known native multibar containers (MultiBarBottomRight etc.); since our
-- buttons are reparented onto ElvUIActionBarHolderN instead, it no longer
-- recognizes them and falls through to the plain current-page
-- calculation bar1 itself uses.
--
-- Unlike real ElvUI (which fully REPLACES the global), this WRAPS the
-- original: our bars are special-cased directly, anything else falls
-- through to the original unchanged.
--
-- Bar1 also carries the stance/form paging. On 1.12 a form (Warrior
-- stances, Druid Cat/Bear/Prowl, Rogue Stealth, ...) never changes
-- ActionButton1-12's page: the native UI slides a SEPARATE
-- BonusActionBarFrame (BonusActionButton1-12, `isBonus`) over the main bar,
-- whose slots start at (NUM_ACTIONBAR_PAGES + GetBonusBarOffset() - 1) * 12
-- + 1. HideChrome() hides that frame, so instead bar1's own buttons resolve
-- to the bonus slots while GetBonusBarOffset() > 0 on page 1 -- the same
-- condition the native function applies to `isBonus` buttons. The offset
-- itself decides whether to page, so no class list is needed: stance-bar
-- entries without a bonus bar (e.g. Paladin auras) report 0. Keybinds
-- follow automatically: ActionButtonDown/Up only redirect to
-- BonusActionButtonN while BonusActionBarFrame:IsShown(), which never
-- happens here, so they use ActionButtonN and this wrapper.
local PAGE_CONST_FOR_BAR = {
	[2] = "BOTTOMRIGHT_ACTIONBAR_PAGE",
	[3] = "RIGHT_ACTIONBAR_PAGE",
	[4] = "LEFT_ACTIONBAR_PAGE",
	[5] = "BOTTOMLEFT_ACTIONBAR_PAGE",
}

local function InstallActionButtonGetPagedID()
	local original = _G.ActionButton_GetPagedID
	if type(original) ~= "function" then return end

	_G.ActionButton_GetPagedID = function(button)
		local okParent, parent = pcall(button.GetParent, button)
		if okParent and parent then
			local okName, name = pcall(parent.GetName, parent)
			if okName and name == "ElvUIActionBarHolder1" then
				local okOffset, offset = pcall(GetBonusBarOffset)
				if tonumber(_G.CURRENT_ACTIONBAR_PAGE) == 1 and okOffset
					and offset and offset > 0 then
					local numPages = tonumber(_G.NUM_ACTIONBAR_PAGES) or 6
					local okId, id = pcall(button.GetID, button)
					if okId and id then
						return id + ((numPages + offset - 1) * MAX_BUTTONS)
					end
				end
			elseif okName and name then
				local d
				for _, d in ipairs(BAR_DEFS) do
					local pageConst = PAGE_CONST_FOR_BAR[d.id]
					if pageConst and name == "ElvUIActionBarHolder"..d.id then
						local page = tonumber(_G[pageConst])
						local okId, id = pcall(button.GetID, button)
						if page and okId and id then
							return id + ((page - 1) * MAX_BUTTONS)
						end
					end
				end
			end
		end

		return original(button)
	end
end

-- Sizes/lays out every bar's buttons. Each bar's own screen POSITION is
-- independent now (mover-owned, see CreateBar()) -- this no longer
-- chains bar N to bar N-1, so bars can be dragged apart via /moveui
-- without one dragging the others along with it.
function M:PositionBars()
	local barDef
	for _, barDef in ipairs(BAR_DEFS) do
		local bar = self.bars[barDef.id]
		if bar then
			local barSettings = E.db.actionbar["bar"..barDef.id]
			PositionOneBar(bar, barSettings)
		end
	end
end

function M:Initialize()
	if not E.private.actionbar.enable then
		return
	end

	HideChrome()

	self.bars = {}
	for _, barDef in ipairs(BAR_DEFS) do
		self.bars[barDef.id] = self:CreateBar(barDef)
	end

	self:PositionBars()
	InstallActionButtonGetPagedID()

	-- Explicit both ways (matches real ElvUI's own
	-- `LOCK_ACTIONBAR = (self.db.lockActionBars == true and "1" or "0")`,
	-- ElvUI-vanilla/ElvUI/Modules/ActionBars/ActionBars.lua:268) --
	-- only setting the "true" branch would leave a stale "1" in place if
	-- the global ever started that way, since disabling the option would
	-- then never clear it back to "0" without a fresh client start.
	if E.db.actionbar.lockActionBars then
		LOCK_ACTIONBAR = "1"
	else
		LOCK_ACTIONBAR = "0"
	end

	-- HideChrome() alone only catches frames that already exist as
	-- globals at login. Some (e.g. ExhaustionTick) are apparently created
	-- lazily by Blizzard's own code later (only once the player actually
	-- becomes rested) -- a frame that doesn't exist yet obviously can't
	-- have its Show() overridden yet either, so the one-shot pass at
	-- Initialize() would permanently miss it. Re-running the (idempotent,
	-- cheap) sweep periodically catches anything created after login,
	-- matching UnrealUI's own "periodic sweep" strategy for the same
	-- class of problem, just without their full batching/grouping
	-- machinery -- not needed at this module's current size. Bounded at
	-- 10 runs (see ElvUI.Util.ScheduleLimitedSweep, Core/Util.lua):
	-- whatever native frame this is meant to catch shows up within a
	-- short window after login, not indefinitely.
	ElvUI.Util.ScheduleLimitedSweep(HideChrome, 3, 10)

	-- Same lazy-creation problem, for a SECOND native region:
	-- ...NormalTexture can still be nil at the exact moment Initialize()
	-- first runs, so StyleButton()'s `if normalTexture then ... end`
	-- silently skips it. StyleButton() is already idempotent (guarded
	-- backdrop creation, every override a harmless no-op on a repeat
	-- call), so re-running it on every enabled bar's buttons periodically
	-- catches anything that didn't exist yet the first time, same
	-- reasoning as HideChrome's own periodic sweep above -- also bounded
	-- at 10 runs.
	local function RestyleAllButtons()
		if not self.bars then return end
		local bd
		for _, bd in ipairs(BAR_DEFS) do
			local bar = self.bars[bd.id]
			if bar then
				local barSettings = E.db.actionbar["bar"..bd.id]
				local i
				for i = 1, MAX_BUTTONS do
					StyleButton(bar.buttons[i], barSettings.showGrid)
				end
			end
		end
	end
	ElvUI.Util.ScheduleLimitedSweep(RestyleAllButtons, 3, 10)

	-- NOT capped, unlike the sweep above -- this is the actual fix for
	-- the live-reported border bug (see StyleButton's own comment on the
	-- native Border region): re-runs for the whole session, not just the
	-- first ~30s after login, since a player can place/move a spell at
	-- any point during play. `ACTIONBAR_SLOT_CHANGED` doesn't usefully
	-- tell us WHICH bar/slot changed here (bars 2-5 remap via
	-- ActionButton_GetPagedID's own wrapper, so the raw slot id isn't
	-- directly this module's own per-bar numbering) -- restyling every
	-- button on every slot change is simple and cheap (a dozen-ish
	-- pcall'd Hide/SetTexture calls per button, ~120 buttons max) rather
	-- than chasing which specific button actually needs it.
	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", RestyleAllButtons)

	-- ActionButton_OnEvent only refreshes `isBonus` buttons on
	-- UPDATE_BONUS_ACTIONBAR, so after a form change bar1 keeps showing the
	-- previous page until something else updates it. Re-run the native
	-- ActionButton_Update per button (it reads the button from the `this`
	-- global); it resolves the slot through the ActionButton_GetPagedID
	-- wrapper above. `this` is saved and restored because UA does not
	-- restore it after a nested handler. StyleButton re-hides the native
	-- Border region that ActionButton_Update may re-show. PLAYER_ENTERING_WORLD
	-- covers logging in while already in a form.
	local function RefreshBar1Actions()
		local bar = self.bars and self.bars[1]
		if not bar or type(_G.ActionButton_Update) ~= "function" then return end
		local caller = this
		local i
		for i = 1, MAX_BUTTONS do
			local button = bar.buttons[i]
			if button then
				this = button
				pcall(ActionButton_Update)
				StyleButton(button, E.db.actionbar.bar1.showGrid)
			end
		end
		this = caller
	end
	self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", RefreshBar1Actions)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", RefreshBar1Actions)

	-- A disabled bar's buttons (HideDisabledBar above) go through the SAME
	-- Hide()+SetAlpha(0)+EnableMouse(false)+Show=noop treatment as
	-- CHROME_TO_HIDE, and that one-shot call sticks fine for chrome frames
	-- (XP bar, bonus bar, etc.). It does NOT stick here: root-caused live
	-- via a temporary print-wrapped SpellBookFrame_Update -- opening
	-- SpellBookFrame calls it 3x per open, and it re-shows a disabled
	-- multibar's buttons (same object each time, confirmed via identity
	-- check -- not a native re-create) regardless of our override. Real
	-- 1.12.1's own SpellBookFrame.lua (wow-ui-source) never touches
	-- action bars at all, so this is UA-only native behavior, not
	-- anything reachable from this project's own code. `self.bars[id]` is
	-- nil for a disabled bar, so neither PositionBars nor
	-- RestyleAllButtons ever touch it again -- this and the hook below are
	-- the only things that do.
	local function ReassertDisabledBars()
		local barDef
		for _, barDef in ipairs(BAR_DEFS) do
			if not E.db.actionbar["bar"..barDef.id].enabled then
				HideDisabledBar(barDef)
			end
		end
	end

	-- Immediate fix, now that the trigger is known: wrap the global so the
	-- re-hide happens in the SAME frame as the native re-show, instead of
	-- waiting for the polling safety net below (up to 0.5s of visible
	-- flicker). Plain global function, not a secure/protected one -- a
	-- straight reassignment is enough, no AceHook/hooksecurefunc needed
	-- (and hooksecurefunc doesn't exist on UA anyway).
	local origSpellBookFrameUpdate = _G.SpellBookFrame_Update
	if type(origSpellBookFrameUpdate) == "function" then
		_G.SpellBookFrame_Update = function(showing)
			local result = origSpellBookFrameUpdate(showing)
			ReassertDisabledBars()
			return result
		end
	end

	-- Safety net alongside the hook above -- cheap (up to 5 bars *
	-- MAX_BUTTONS pcall'd Hide calls per tick), reads `enabled` live (so
	-- re-enabling a bar through the config UI stops the re-hide without a
	-- reload), and covers any OTHER native trigger for the same symptom
	-- that hasn't surfaced yet.
	E:ScheduleRepeatingTimer(ReassertDisabledBars, 0.5)
end

-- Public so ElvUI_Config/Core.lua's per-bar `set` functions can re-apply
-- position/size/backdrop/alpha for one bar without needing a /reload --
-- enabling/disabling a bar still needs one, since that changes whether
-- its buttons are reparented onto us or left hidden (CreateBar's job, not
-- PositionBars'). Matches real ElvUI's own AB:PositionAndSizeBar(barNum)
-- being the thing every non-`enabled` per-bar config field calls.
function M:UpdateBar(id)
	local bar = self.bars and self.bars[id]
	if not bar then return end
	local barSettings = E.db.actionbar["bar"..id]
	local i
	for i = 1, MAX_BUTTONS do
		StyleButton(bar.buttons[i], barSettings.showGrid)
	end
	self:PositionBars()
end

E:RegisterInitialModule(M:GetName(), function() M:Initialize() end)
