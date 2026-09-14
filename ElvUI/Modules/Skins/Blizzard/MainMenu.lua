-- Skins > Blizzard > MainMenu -- reskins the native GameMenuFrame (the
-- Escape-key menu) in place. Same recipe family as Character/Friends/
-- SpellBook/Macro.lua: strip native chrome, elvBackground child frame
-- (never SetBackdrop the native frame itself), automatic sweep for the
-- generic buttons.
--
-- Real 1.12.1 structure, per `source/wow-ui-source/FrameXML/
-- GameMenuFrame.xml`:
-- - `GameMenuFrame` is core FrameXML, NOT a `## LoadOnDemand` AddOn like
--   MacroFrame -- it exists from PLAYER_LOGIN, so this file needs no
--   `S:WaitForGlobal` wait, matching Character/Friends/SpellBook rather
--   than Macro.
-- - The frame declares its OWN native `<Backdrop>` directly (DialogBox
--   background+border), NOT built from separate Texture layers like
--   Character/Macro's own chrome. `S:StripTextures` already clears a
--   frame's own `<Backdrop>` unconditionally (`SetBackdrop(frame, nil)`,
--   Skins.lua) before ever touching `recurse` -- a plain non-recursive
--   call is enough here, no need to reach for `S:CreatePanel`'s
--   `keepDefaultLevel` dance used elsewhere.
-- - `GameMenuFrameHeader` (the "MAIN_MENU" banner art) is a DIRECT
--   ARTWORK-layer Texture region of `GameMenuFrame` itself -- confirmed
--   non-nested, so `S:StripTextures(frame, false)` reaches it with no
--   recursion needed at all. The 8 menu buttons are the frame's only
--   children and are all Button-type, which a recursive strip would skip
--   over anyway -- recursion would add nothing here.
-- - The "MAIN_MENU" FontString is anchored TOP relativeTo=
--   `GameMenuFrameHeader` -- deliberately NOT repositioned once the header
--   texture is hidden (matches Macro.lua's own restraint: `Hide()`
--   preserves a region's anchor geometry on this client, only rendering
--   stops, so the FontString's relative anchor keeps resolving fine).
-- - The 8 vanilla rows (`GameMenuButtonOptions/SoundOptions/UIOptions/
--   Keybindings/Macros/Logout/Quit/Continue`) inherit
--   `GameMenuButtonTemplate` -> `UIPanelButtonTemplate`. In the REAL
--   FrameXML that template's slots are `<NormalTexture inherits=
--   "UIPanelButtonUpTexture"/>` -- i.e. the asset path comes from a
--   virtual `<Texture>`, never spelled out on the button itself.
--   Live on UA this menu ALSO carries at least two rows the FrameXML
--   knows nothing about: one Emberveil (the client) injects, and our own
--   "ElvUI" row from `Core/GameMenu.lua`.
--
-- This file was the project's first to rely on `S:SkinChildren` ALONE
-- for its buttons -- everywhere else the same buttons are ALSO styled by
-- name. `GameMenuFrame:GetChildren()` returns all 11 children with
-- correct names and types, but each native child comes back as a
-- CRIPPLED object that has no `GetNormalTexture` field at all and is not
-- the same object as `_G[name]` -- so the sweep was interrogating a
-- widget that had nothing to answer with, which is also why styling a
-- button by hand (through the global) always worked. Fixed in the sweep
-- by `S:ResolveWidget` (Skins.lua): every enumerated child is resolved
-- through its global name before anything is asked of it.
--
-- A hardcoded list of this window's buttons was considered and rejected:
-- the whole point of the sweep is that rows nobody enumerated --
-- Emberveil's own `GameMenuButtonShop`, our "ElvUI" row, an addon's extra
-- QuestLog buttons -- inherit the design too.
--
-- SCOPE: outer chrome (native-backdrop clear, header strip,
-- elvBackground) plus the buttons. Deliberately NOT done:
-- dragging (real vanilla doesn't make this frame draggable, no drag script
-- in the FrameXML, and it's a toggle-open modal-ish menu, not a HUD
-- element worth `S:MakeDraggable`), repositioning the title text (see
-- above), a close button (native GameMenuFrame has none -- "Continue"/
-- Escape is the only way to close it, matches real ElvUI leaving it
-- alone too).

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

local function ApplyGameMenuChrome(frame)
	S:StripTextures(frame, false)

	S:CreatePanel(frame)

	-- Deliberately still the sweep ALONE, with no per-button name list: the
	-- point of `S:SkinChildren` is that a row this file never heard of --
	-- our own "ElvUI" row, or one another addon injects -- inherits the
	-- design too. A crippled-object identification bug in the sweep itself
	-- (fixed via `S:ResolveWidget`, Skins.lua) was the actual cause of the
	-- first failure, not a reason to enumerate this window's buttons by
	-- hand.
	S:SkinChildren(frame)
end

local gameMenuSkinApplied = false
local function ApplyGameMenuSkin()
	if gameMenuSkinApplied then return end
	local frame = _G.GameMenuFrame
	if not frame then return end
	gameMenuSkinApplied = true

	ApplyGameMenuChrome(frame)
	local ok = S:TryHookScript(frame, "OnShow", function() ApplyGameMenuChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyGameMenuSkin()
end

S:AddBlizzardSkin("mainmenu", LoadSkin)
