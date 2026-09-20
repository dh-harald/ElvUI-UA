-- Skins > Blizzard > Binding -- reskins the native KeyBindingFrame
-- (Escape > Key Bindings) in place. Same recipe family as MainMenu.lua/
-- Macro.lua: strip native chrome, elvBackground child frame (never
-- SetBackdrop the native frame itself), automatic sweep for the generic
-- controls.
--
-- **LoadOnDemand -- the second such window in this project.**
-- `source/wow-ui-source/AddOns/Blizzard_BindingUI/Blizzard_BindingUI.toc`
-- declares `## LoadOnDemand: 1`: until the player opens Key Bindings once,
-- NOT A SINGLE `KeyBinding*` global exists, so a global search coming back
-- empty is the normal state, not a bug. `S:WaitForGlobal` owns that wait
-- (ADDON_LOADED + 0.1s poll backstop) so the unskinned native window never
-- flashes -- see Macro.lua/Skins.lua for the full reasoning.
--
-- Real 1.12.1 structure, per `Blizzard_BindingUI.xml`, and CONFIRMED
-- against the live client (`rows=17`, `KEY_BINDINGS_DISPLAYED=17`,
-- `KeyBindingFrame:GetObjectType()=="Button"`, and every name used below
-- resolving) -- unlike the Sound/Video/Interface Options windows, whose
-- FrameXML is customised on this server, here the real 1.12.1 source is
-- valid ground truth:
--
-- - **The list is NOT dynamic**, however much it looks like it. There is
--   ONE row template (`KeyBindingFrameBindingTemplate`, 17 static
--   instances `KeyBindingFrameBinding1..17`) that carries BOTH faces at
--   once: `$parentHeader` (the category caption), `$parentDescription`
--   (the action name) and `$parentKey1Button`/`$parentKey2Button`.
--   `KeyBindingFrame_Update` only Show/Hide-s between them -- it never
--   swaps templates, creates frames, or rebuilds any widget. So the 17
--   rows and 34 key buttons exist from the moment the addon loads, are
--   walked exactly once here, and need no `KeyBindingFrame_Update` hook
--   and no per-row re-apply. Both references agree (real ElvUI's own
--   `Blizzard/Binding.lua`, pfUI's `skins/blizzard/keybindings.lua`): a
--   single `1..KEY_BINDINGS_DISPLAYED` loop, no Update hook.
-- - The window's decorative art -- six `UI-KeyBindingFrame-*` BACKGROUND
--   textures plus the `UI-DialogBox-Header` ARTWORK banner -- are all
--   DIRECT Texture regions of `KeyBindingFrame` itself, so a plain
--   NON-recursive `S:StripTextures` reaches everything. Recursion would
--   add nothing: the rows carry no textures at all, and the scrollbar has
--   its own dedicated recipe.
-- - **No `DisableDrawLayer` here, deliberately**, even though that is
--   normally the reliable hammer for native art: on this frame BACKGROUND
--   also carries `KeyBindingFrameCommandLabel`/`Key1Label`/`Key2Label`/
--   `OutputText` (the binding error/prompt line), and ARTWORK carries
--   `KeyBindingFrameHeaderText` (the window title). Disabling either layer
--   would take those down with the art. `S:StripTextures` only touches
--   Texture regions, so FontStrings survive it.
-- - Every control comes from a template the sweep already recognises --
--   the key buttons and Okay/Cancel/Unbind from `UIPanelButtonTemplate(2)`,
--   `KeyBindingFrameDefaultButton` from `UIPanelButtonGrayTemplate` (whose
--   `UI-Panel-Button-Disabled` art still contains the `ui-panel-button`
--   fragment), `KeyBindingFrameCharacterButton` from `UICheckButtonTemplate`,
--   the scrollbar from `FauxScrollFrameTemplate`. Nothing needs adding to
--   `S.autoSkinSkipNames`.
--
-- SCOPE: outer chrome (strip, elvBackground, hit rect, drag handle), the
-- window's own FontStrings (see `PromotePanelText`), the 34 key buttons,
-- the scrollbar, and the repositioning the skinned (bordered) buttons
-- need. Deliberately NOT done: pfUI's optional `OnMouseDown`/`OnMouseUp`
-- no-op on the key buttons that kills the native push offset -- cosmetic
-- only, and unnecessary here since the key buttons' three background
-- regions are `S:Kill`ed (permanently noop'd `Show`), so the native
-- press-time texture reassignment cannot bring the art back.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Set by the addon itself; the literal is only a floor for the case where
-- this file somehow runs before it.
local function RowCount()
	return tonumber(_G.KEY_BINDINGS_DISPLAYED) or 17
end

-- The panel deliberately does NOT cover the frame. `KeyBindingFrame` is
-- 640x512, but its native art extends well to the right of the visible
-- content; both references inset the same way, and the -42 on the right is
-- the load-bearing number (real ElvUI: TOPLEFT 2,0 / BOTTOMRIGHT -42,12).
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 2, 0, -42, 12

-- The five FontStrings that sit DIRECTLY on `KeyBindingFrame` share their
-- draw layers with the decorative art stripped above: BACKGROUND carries
-- the COMMAND/KEY1/KEY2 column captions and `OutputText` (the binding
-- prompt/error line that appears between the list and the button row),
-- ARTWORK carries the window title. `elvBackground` is a child frame
-- pinned to the frame's OWN level, and at equal frame levels draw order
-- falls back to draw LAYER -- so the panel covers all five and the window
-- opens with no title, no column captions and no output line. Promoting
-- them to OVERLAY puts them back in front; same fix already proven for
-- PetPaperDollFrame's own header texts (Character.lua).
--
-- The per-row captions need nothing: `$parentHeader`/`$parentDescription`
-- belong to the row FRAMES, which are children of the window and so
-- already draw above the panel.
local PANEL_TEXTS = {
	"KeyBindingFrameHeaderText",
	"KeyBindingFrameCommandLabel",
	"KeyBindingFrameKey1Label",
	"KeyBindingFrameKey2Label",
	"KeyBindingFrameOutputText",
}

local function PromotePanelText(frame)
	local i
	for i = 1, table.getn(PANEL_TEXTS) do
		local fs = _G[PANEL_TEXTS[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end

	local title = _G.KeyBindingFrameHeaderText
	if not title then return end

	-- Window title in the shared accent, matching every other skinned
	-- window's title (Friends, SpellBook).
	pcall(title.SetTextColor, title, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])

	-- RE-ANCHORED, and this is the one thing that separates the title from
	-- the four captions above: it is the only FontString on this window
	-- anchored to a region the strip HID (`KeyBindingFrameHeader`, the
	-- `UI-DialogBox-Header` banner), the others hang off the frame or off
	-- each other. Anchored that way it did not render at all -- it only
	-- flashed into place while the window was being dragged, i.e. while its
	-- position was being recomputed every frame. Same class as every other
	-- "a hidden native object stops answering reliably on this client"
	-- finding in this project, so the fix is to stop depending on the dead
	-- banner: the title hangs off the PANEL instead, which also centres it
	-- on the visible window rather than on the 42px-wider frame.
	local anchor = frame and frame.elvBackground or frame
	if anchor then
		pcall(title.ClearAllPoints, title)
		pcall(title.SetPoint, title, "TOP", anchor, "TOP", 0, -6)
	end
end

-- On a key button, the highlight is FUNCTION, not decoration:
-- `KeyBindingFrame_Update` marks the button currently waiting for a key
-- with `LockHighlight()` and clears it with `UnlockHighlight()` (the
-- Unbind button's OnClick calls it too). `S:StyleUIPanelButton` blanks the
-- native HighlightTexture, so without this the player gets NO feedback
-- about which button they just pressed.
--
-- Rather than trying to keep a native texture alive, the two methods are
-- shadowed on the widget itself (a plain Lua field on the widget table,
-- the same mechanism as the `Show = E.noop` overrides used throughout this
-- module) and recolour OUR OWN border frame -- deterministic, no polling,
-- and independent of whether a locked highlight renders HIGHLIGHT-layer
-- regions on this client. The native call still runs first, so nothing
-- native changes behaviour.
local function InstallHighlightLatch(button)
	if button.elvHighlightLatch then return end
	local border = button.elvBackdrop
	if not border then return end
	button.elvHighlightLatch = true

	local nativeLock = button.LockHighlight
	local nativeUnlock = button.UnlockHighlight

	button.LockHighlight = function(self)
		if nativeLock then pcall(nativeLock, self) end
		pcall(border.SetBackdropBorderColor, border, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3], 1)
	end
	button.UnlockHighlight = function(self)
		if nativeUnlock then pcall(nativeUnlock, self) end
		pcall(border.SetBackdropBorderColor, border, S.BORDER_COLOR[1], S.BORDER_COLOR[2], S.BORDER_COLOR[3], S.BORDER_COLOR[4] or 1)
	end
end

-- The native XML butts every one of these buttons against its neighbour at
-- a 0 offset, which reads as a single merged slab once each has its own 1px
-- border. The gaps are real ElvUI's own values.
local function Reanchor(frame, point, relativeTo, relativePoint, x, y)
	if not (frame and relativeTo) then return end
	pcall(frame.ClearAllPoints, frame)
	pcall(frame.SetPoint, frame, point, relativeTo, relativePoint, x, y)
end

-- Walked once per chrome pass. Every helper called here latches its own
-- one-time work, so repeat passes are cheap; the loop is kept in the
-- re-apply path anyway rather than in one-time setup, since a row's border
-- has to survive whatever the native code re-asserts on show.
local function StyleBindingRows()
	local i
	for i = 1, RowCount() do
		local key1 = _G["KeyBindingFrameBinding"..i.."Key1Button"]
		local key2 = _G["KeyBindingFrameBinding"..i.."Key2Button"]

		-- Reached by name rather than left to the sweep: the highlight
		-- latch above needs the button's own border frame, and a `_G`
		-- lookup cannot come back truncated the way an enumerated child
		-- list can on a frame with this many children. The sweep still
		-- runs afterwards and simply skips these (`elvStyled`).
		S:StyleUIPanelButton(key1)
		S:StyleUIPanelButton(key2)
		if key1 then InstallHighlightLatch(key1) end
		if key2 then InstallHighlightLatch(key2) end

		Reanchor(key2, "LEFT", key1, "RIGHT", 1, 0)
	end
end

local function ApplyBindingChrome(frame)
	S:StripTextures(frame, false)

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	PromotePanelText(frame)

	StyleBindingRows()

	S:HandleScrollBar(_G.KeyBindingFrameScrollFrameScrollBar)

	-- Only the anchors are done by name; the buttons themselves (plus
	-- `KeyBindingFrameCharacterButton`) are left to the sweep below.
	Reanchor(_G.KeyBindingFrameOkayButton, "RIGHT", _G.KeyBindingFrameCancelButton, "LEFT", -3, 0)
	Reanchor(_G.KeyBindingFrameUnbindButton, "RIGHT", _G.KeyBindingFrameOkayButton, "LEFT", -3, 0)

	-- Catch-all pass -- see `S:SkinChildren` (Skins.lua).
	S:SkinChildren(frame)
end

local bindingSkinApplied = false
local function ApplyBindingSkin()
	if bindingSkinApplied then return end
	local frame = _G.KeyBindingFrame
	if not frame then return end
	bindingSkinApplied = true

	-- The 42px of frame to the right of the panel is now empty, but the
	-- frame is `enableMouse="true"` and toplevel, so without this it stays
	-- an invisible click-eater next to the window. Matches the visible
	-- panel exactly. (pfUI does the same on this window.)
	pcall(frame.SetHitRectInsets, frame, PANEL_LEFT, -PANEL_RIGHT, -PANEL_TOP, PANEL_BOTTOM)

	-- `movable="true"` in the XML but with no drag script anywhere, so the
	-- native window cannot actually be moved. The handle is pulled in to
	-- the panel's right edge for the same reason as the hit rect above.
	local handle = S:MakeDraggable(frame)
	if handle then
		pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT, 0)
	end
	pcall(frame.SetUserPlaced, frame, true)

	ApplyBindingChrome(frame)
	local ok = S:TryHookScript(frame, "OnShow", function() ApplyBindingChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	S:WaitForGlobal("KeyBindingFrame", ApplyBindingSkin)
end

S:AddBlizzardSkin("binding", LoadSkin)
