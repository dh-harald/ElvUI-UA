-- Skins > Blizzard > InterfaceOptions -- reskins the native UIOptionsFrame
-- (Escape menu -> "Interface Options") in place.
--
-- NOTHING HERE IS TAKEN FROM THE FrameXML AS FACT. Same rule as
-- SoundOptions.lua: the FrameXML is only advisory here, not a source of
-- truth, because UA has different options than real vanilla. The real
-- 1.12.1 file is only used to recognise TEMPLATES; every structural fact
-- below came out of a live measurement instead (`S:Dump`, chat
-- screenshots).
--
-- THE MEASURED STRUCTURE:
--
--   UIOptionsFrame            1365x768 = the whole screen, FULLSCREEN strata
--     regions: tex=5 fontstrings=1   -- 4 parchment corners + a screen-wide
--                                       black backdrop + the title string
--     children: 10
--       BasicOptions            (Frame) 1024x768, backdrop: none, tex=0
--         BasicOptionsGeneral   (Frame) \
--         BasicOptionsDisplay   (Frame)  > the boxes that DO carry a <Backdrop>
--         BasicOptionsCamera    (Frame) /
--       AdvancedOptions         (Frame)
--       DiscordPrivacyOptions   (Frame)  -- this server's own page
--       UIOptionsFrameCancel/Okay/Defaults  (Button)
--       UIOptionsFrameTab1/2/3            (Button)
--
-- Two things that split cleanly out of that, and are the reason this file
-- needs no name list at all:
--
--  1. **Type separates pages from controls.** Every page container is a
--     `Frame`; everything else directly under the window is a `Button`. So
--     "for each Frame child, treat it as a page" is exact here, and stays
--     exact if the server adds a fourth page.
--  2. **A native `<Backdrop>` separates group boxes from plain containers.**
--     `BasicOptions` itself measured `backdrop: none`, while the boxes
--     inside it carry one. So `elvHadNativeBackdrop` (set by
--     `S:ClearNativeBackdrop` on the way past) marks precisely the boxes --
--     no guessing which nesting level is a "box". NOTE the flag name: the
--     first version used `elvBackdropNeutralized`, which only exists on UA
--     and made this whole file a no-op on the legacy client.
--
-- WHY THE WINDOW IS LEFT FULLSCREEN. Its top frame is screen-sized and the
-- visible 1024x768 window is a child. Shrinking the top frame (or lowering
-- its strata) was considered and rejected: the same difficulty this
-- project already hit trying to embed WorldMapFrame into a window applies
-- here too, and isn't worth chasing on UA. It also isn't needed: what makes the window
-- read as fullscreen is that it is PAINTED, not its size. Strip the five
-- textures and the top frame becomes an invisible screen-sized shell, with
-- our panel drawn on the 1024x768 page instead -- a bounded window on
-- screen, with every native behaviour (modal mouse/keyboard capture)
-- untouched.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- Frees the window from its four `setAllPoints` anchors so it can be
-- dragged, and puts it back wherever the user last left it.
--
-- ⚠ THIS HAS TO RE-RUN ON EVERY SHOW ON THE LEGACY CLIENT. That window's
-- own OnShow calls `SetupFullscreenScale(this)` -- a built-in with no Lua
-- source, used by exactly three frames in the whole UI (this one,
-- `CinematicFrame`, `WorldMapFrame`) -- and it re-asserts the fullscreen
-- placement, undoing a one-time detach. Dragging works on UA (where that
-- built-in evidently does nothing) but not on legacy. It is very likely
-- also why embedding WorldMapFrame into a window never worked -- same
-- built-in, same frame list.
--
-- `elvPlacement` is what makes the re-run harmless: without it, every open
-- would yank a moved window back to centre.
local function DetachFrame(frame)
	local okW, width = pcall(frame.GetWidth, frame)
	local okH, height = pcall(frame.GetHeight, frame)
	width, height = tonumber(width), tonumber(height)
	-- A zero/absent size would collapse the frame and take every child with
	-- it, so fall back to the screen rather than write a bad size.
	if not (okW and okH and width and height) or width <= 0 or height <= 0 then
		local okPW, parentWidth = pcall(UIParent.GetWidth, UIParent)
		local okPH, parentHeight = pcall(UIParent.GetHeight, UIParent)
		width = (okPW and tonumber(parentWidth)) or nil
		height = (okPH and tonumber(parentHeight)) or nil
		if not (width and height) then return end
	end

	local placement = frame.elvPlacement
	pcall(frame.SetWidth, frame, width)
	pcall(frame.SetHeight, frame, height)
	pcall(frame.ClearAllPoints, frame)
	if placement then
		pcall(frame.SetPoint, frame, placement.point, UIParent, placement.relPoint,
			placement.x, placement.y)
	else
		pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 0)
	end
end

-- Records where a drag left the window, so `DetachFrame` can restore it.
local function SavePlacement(frame)
	local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame)
	if ok and point then
		frame.elvPlacement = {
			point = point,
			relPoint = relPoint or point,
			x = tonumber(x) or 0,
			y = tonumber(y) or 0,
		}
	end
end

-- EVERYTHING THAT LIVES OUTSIDE THE PAGES, LINED UP WITH ONE PAGE'S PANEL:
-- the title above it, the three bottom buttons below it, and the drag handle
-- inside its top edge. None of these are children of a page, so nothing moves
-- them when the native tab logic swaps pages -- this function is what does.
--
-- ⚠ IT TAKES THE PANEL AS AN ARGUMENT ON PURPOSE, AND THAT IS THE FIX FOR
-- A REAL BUG. The first version anchored all of this to the FIRST page's
-- panel, on the assumption that "all three pages' panels land in the same
-- place". **That assumption is wrong**: switching tabs left the buttons
-- exactly where the first tab's panel put them, never tracking the new
-- tab's own panel position.
-- Each panel is anchored to its OWN page's first and last group box, so its
-- BOTTOM edge is wherever that page's content happens to end -- and the
-- pages have different amounts of content. It was nearly invisible on legacy
-- (two similarly-sized tabs) and obvious on UA.
--
-- The title's TOP anchor happened to survive that mistake, because the pages
-- do start at the same offset; it is re-anchored here anyway rather than
-- left on a separate, latched path, so one page-show call keeps every piece
-- of outside-the-page chrome consistent instead of two of the three.
--
-- Named lookups: see the note at the call site in `ApplyInterfaceOptionsChrome`
-- for why these three buttons are the file's one deliberate name list.
local function AnchorPageChrome(frame, panel)
	if not (frame and panel) then return end

	local title = _G.UIOptionsFrameTitle
	if title then
		pcall(title.ClearAllPoints, title)
		pcall(title.SetPoint, title, "BOTTOM", panel, "TOP", 0, 8)
	end

	-- Okay hangs off Cancel rather than off the panel, matching real ElvUI's
	-- own line for this exact window (source/ElvUI-vanilla/ElvUI/Modules/
	-- Skins/Blizzard/Misc.lua:232-233).
	local cancel = _G.UIOptionsFrameCancel
	if cancel then
		pcall(cancel.ClearAllPoints, cancel)
		pcall(cancel.SetPoint, cancel, "TOPRIGHT", panel, "BOTTOMRIGHT", 0, -8)
		local okay = _G.UIOptionsFrameOkay
		if okay then
			pcall(okay.ClearAllPoints, okay)
			pcall(okay.SetPoint, okay, "RIGHT", cancel, "LEFT", -4, 0)
		end
	end

	local defaults = _G.UIOptionsFrameDefaults
	if defaults then
		pcall(defaults.ClearAllPoints, defaults)
		pcall(defaults.SetPoint, defaults, "TOPLEFT", panel, "BOTTOMLEFT", 0, -8)
	end

	-- The handle is built ONCE from the load path (`S:MakeDraggable` creates a
	-- new frame per call), so it is re-anchored here rather than rebuilt. It
	-- has the same problem as the buttons if a page's panel sits differently.
	local handle = frame.elvDragHandle
	if handle then
		pcall(handle.ClearAllPoints, handle)
		pcall(handle.SetPoint, handle, "TOPLEFT", panel, "TOPLEFT", 0, 0)
		pcall(handle.SetPoint, handle, "TOPRIGHT", panel, "TOPRIGHT", 0, 0)
		pcall(handle.SetHeight, handle, 30)
	end

	frame.elvTitleAnchor = panel
end

-- The pages are shown one at a time by the native tab logic, so giving each
-- one its own panel can never produce overlapping slabs.
local function StylePage(frame, page)
	if not page then return end

	-- Recursive: the group boxes' own native backdrops live one level down,
	-- and their controls' art another level below that. On UA the recursion
	-- is also what marks the boxes for us -- see `S:ClearNativeBackdrop`.
	S:StripTextures(page, true)

	-- Group boxes: a lighter surface, same treatment (and same token) as
	-- Sound Options' "Voice Chat Settings" box. There it had to be named
	-- because four nested wells carried a backdrop too and would all have
	-- matched; here the measurement says the page itself has none and only
	-- the boxes do, so the generic rule is safe -- and it is the only rule
	-- that survives options this client has and vanilla doesn't.
	local firstBox, lastBox
	local okKids, kids = pcall(function() return { page:GetChildren() } end)
	if okKids and type(kids) == "table" then
		local i
		for i = 1, table.getn(kids) do
			-- Resolved first: an enumerated native child is a crippled
			-- wrapper on this client (`S:ResolveWidget`).
			local box = S:ResolveWidget(kids[i])
			local okType, boxType = pcall(box.GetObjectType, box)
			-- `elvHadNativeBackdrop`, NOT `elvBackdropNeutralized`: the
			-- latter only gets set when `SetBackdrop(nil)` FAILED, which is
			-- a UA-only condition -- on the legacy client the removal works,
			-- the flag never appears, and this whole branch silently did
			-- nothing there (no lighter boxes, and the panel below fell back
			-- to covering the entire page). See `S:ClearNativeBackdrop`.
			if okType and boxType == "Frame" and box.elvHadNativeBackdrop then
				S:CreateSurface(box, S.GROUP_COLOR)
				if not firstBox then firstBox = box end
				lastBox = box
			end
		end
	end

	-- THE PANEL WRAPS THE BOXES, NOT THE PAGE. Straight from real ElvUI's
	-- own recipe for this exact window (source/ElvUI-vanilla/ElvUI/Modules/
	-- Skins/Blizzard/Misc.lua:287-290): it parents a backdrop frame to
	-- `BasicOptions` but anchors it from the FIRST group box to the LAST,
	-- not to the page. The reason is visible in any screenshot of this
	-- window: the page is 1024x768 while the content stops well above its
	-- bottom edge, so a page-sized panel would hang a large empty slab
	-- under the last box.
	--
	-- Where this deliberately DIVERGES from that reference: real ElvUI
	-- names its endpoints (`BasicOptionsGeneral` .. `BasicOptionsHelp`), and
	-- **`BasicOptionsHelp` does not exist on this client** -- the live
	-- measurement found three boxes, not four. So the endpoints come from
	-- the walk above: first and last box in child order, which is also
	-- top-to-bottom order for this layout. If a page has no boxes at all,
	-- the panel falls back to covering the page, which is wrong-looking but
	-- never invisible -- the failure stays obvious rather than silent.
	local panel = S:CreatePanel(page)
	if panel and firstBox and lastBox then
		pcall(panel.ClearAllPoints, panel)
		pcall(panel.SetPoint, panel, "TOPLEFT", firstBox, "TOPLEFT", -20, 35)
		pcall(panel.SetPoint, panel, "BOTTOMRIGHT", lastBox, "BOTTOMRIGHT", 20, -20)
	end

	-- RE-ANCHOR THE OUTSIDE CHROME WHENEVER THIS PAGE COMES UP. The native tab
	-- logic just shows/hides these pages, and the title/buttons/handle are not
	-- children of any of them, so nothing else would ever move them when
	-- switching tabs. Same shape as `Blizzard/Character.lua`'s per-subframe OnShow
	-- hooks, and for the same reason: switching tabs does not fire the outer
	-- window's own OnShow.
	--
	-- Hooked once per page, and the latch only sets on SUCCESS so a failed
	-- attempt retries on the next re-apply.
	if panel and not page.elvChromeHooked then
		local ok = S:TryHookScript(page, "OnShow", function()
			AnchorPageChrome(frame, page.elvBackground)
		end)
		if ok then page.elvChromeHooked = true end
	end

	return panel
end

-- THIS WINDOW HAS NO PARENT, WHICH IS WHY IT RENDERS OVERSIZED ON LEGACY.
--
-- On legacy the window renders noticeably larger than every other options
-- window, as if UI Scale doesn't affect it -- and the FrameXML says why in
-- one line: this frame is declared with NO `parent` attribute:
--
--   <Frame name="UIOptionsFrame"    setAllPoints="true" frameStrata="FULLSCREEN" ...>
--   <Frame name="WorldMapFrame"     setAllPoints="true" frameStrata="FULLSCREEN" ...>
--   <Frame name="CinematicFrame"    setAllPoints="true" ...>
--   <Frame name="OptionsFrame"      ... parent="UIParent">
--   <Frame name="SoundOptionsFrame" ... parent="UIParent">
--
-- The UI Scale setting IS `UIParent`'s scale, so a frame that is not its
-- child never inherits it. Measured on legacy at 3840x2160 with UI Scale
-- 0.64, using the one widget both windows build from the same template (the
-- 8-unit slider handle): 14px wide in Video Options, 23px here -- a ratio of
-- 1.5625, which is 1/0.64 exactly. Two independent cross-checks (the accent
-- checkbox squares, and px/unit = 2160/768 * effectiveScale) agree.
--
-- ⚠ `SetupFullscreenScale` is NOT the cause: `UIOptionsFrame:GetScale()`
-- reads 1 on legacy, so nothing is calling `SetScale` on it. The three
-- parentless frames above are exactly the three that call that built-in,
-- which makes the two easy to confuse -- they are both consequences of
-- the same "this frame is not part of the scaled UI" design, not cause and
-- effect.
--
-- `SetParent(UIParent)` is also what real ElvUI does, as the very first line
-- of its own Interface Options block (source/ElvUI-vanilla/ElvUI/Modules/
-- Skins/Blizzard/Misc.lua:261). Confirmed live before being written:
-- the window closed on the call, and reopened at normal size and STAYED
-- there -- the client does not put the parent back -- so the guard below is
-- only for the login path, not a fight with native code.
--
-- No visible change on UA: with no UI Scale there, `UIParent`'s effective
-- scale is already 1, so both branches render identically. It matters the
-- day UA gains a UI Scale setting.
local function ReparentToUIParent(frame)
	if not UIParent then return end
	local okParent, currentParent = pcall(frame.GetParent, frame)
	-- Redundant on a client where the reference compare misfires -- and that
	-- is harmless, `SetParent` to the parent it already has is a no-op.
	if okParent and currentParent == UIParent then return end
	pcall(frame.SetParent, frame, UIParent)
end

local function ApplyInterfaceOptionsChrome(frame)
	-- BEFORE `DetachFrame`, because it changes what a screen-sized frame
	-- measures: see this function's own note.
	ReparentToUIParent(frame)

	-- FIRST, before any styling: re-detach. On legacy this runs after the
	-- native OnShow has already called `SetupFullscreenScale`, so it undoes
	-- that re-anchoring and restores the user's own position. Idempotent and
	-- harmless on UA, where nothing had re-anchored it in the first place.
	DetachFrame(frame)

	-- NON-recursive on the top frame: its own five regions are the whole of
	-- its art, and the pages are handled individually below (each needs a
	-- panel of its own, which a blanket walk can't place).
	S:StripTextures(frame, false)

	-- Tab spacing for the sweep -- see `S:SkinChildren`'s tab branch. The
	-- project default (10) is tuned for CharacterFrame, whose tabs OVERLAP
	-- each other by ~14px, so a wide inset is what stops their border boxes
	-- from colliding. These tabs don't overlap at all -- they sit 3px apart
	-- -- so the same inset just adds 10px of gap on each side, i.e. a ~25px
	-- gulf that reads as too wide. 2 leaves 3+2+2 = 7px between boxes.
	frame.elvTabInsetX = 2

	local firstPanel, shownPanel
	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	if okKids and type(kids) == "table" then
		local i
		for i = 1, table.getn(kids) do
			local kid = S:ResolveWidget(kids[i])
			local okType, kidType = pcall(kid.GetObjectType, kid)
			local okName, kidName = pcall(kid.GetName, kid)
			if okType and kidType == "Frame" then
				local panel = StylePage(frame, kid)
				if panel and not firstPanel then firstPanel = panel end
				-- WHICH page is on screen right now -- the tab logic shows
				-- exactly one. Its panel is what the title, the buttons and
				-- the drag handle must line up with.
				if panel and not shownPanel then
					local okShown, shown = pcall(kid.IsShown, kid)
					if okShown and shown then shownPanel = panel end
				end
			-- `kidName == ""` matters as much as nil: an EMPTY STRING is
			-- TRUE in Lua, so a naive `not (okName and kidName)` test never
			-- fires on UA, where an unnamed native child reports "" rather
			-- than nil. `S:ResolveWidget` guards the same way.
			elseif okType and kidType == "Button" and (not okName or kidName == nil or kidName == "") then
				-- THE CLOSE BUTTON, identified by having NO NAME, and
				-- removed for this window only: it doesn't work here on
				-- either client.
				--
				-- Namelessness is the reliable marker, not a guess: the
				-- measured child list had 9 named children (3 pages, 3 tabs,
				-- Cancel/Okay/Defaults) and exactly one unnamed, and the
				-- FrameXML confirms why -- this window declares its close
				-- button as a bare `<Button inherits="UIPanelCloseButton">`
				-- with no `name` attribute at all
				-- (source/wow-ui-source/FrameXML/UIOptionsFrame.xml:1477),
				-- unlike every other window this project has skinned, where
				-- the close button is named and styled by name.
				--
				-- The window still closes with Escape and with its own
				-- Okay/Cancel buttons, so nothing is lost.
				S:Kill(kid)
			end
		end
	end

	-- THE CHROME OUTSIDE THE PAGES FOLLOWS THE **VISIBLE** PAGE'S PANEL.
	-- `AnchorPageChrome` does the actual anchoring; see its own note for why
	-- `firstPanel` is only a fallback and no longer the anchor itself.
	local anchorPanel = shownPanel or firstPanel
	if anchorPanel then
		frame.elvTitleAnchor = anchorPanel
		AnchorPageChrome(frame, anchorPanel)
	end

	-- Everything else -- the three bottom buttons, the tabs, and every
	-- control inside the pages -- comes from the sweep. The tabs are new
	-- capability added alongside this file (`S:SkinChildren`'s own tab
	-- branch, Skins.lua): recognised by their `$parentMiddle` region rather
	-- than by name, so this server's third tab is styled without anyone
	-- enumerating it, and a fourth would be too.
	S:SkinChildren(frame)
end

local interfaceOptionsSkinApplied = false
local function ApplyInterfaceOptionsSkin()
	if interfaceOptionsSkinApplied then return end
	local frame = _G.UIOptionsFrame
	if not frame then return end
	interfaceOptionsSkinApplied = true

	ApplyInterfaceOptionsChrome(frame)

	-- MOVABLE, and it takes one step the other windows don't
	-- need. `UIOptionsFrame` is declared `setAllPoints`, i.e. it has NO size
	-- of its own -- it borrows the screen's. Clearing its anchors to move it
	-- would therefore collapse it to nothing, so its current size is pinned
	-- first and only then is it re-anchored to a single CENTER point. The
	-- centre is where it already sat, so nothing moves on screen; the frame
	-- just stops being welded to UIParent's four corners.
	--
	-- Moving the TOP frame (rather than the visible page) is deliberate:
	-- the pages, the tabs and the three buttons are all children of it, so
	-- they travel together. The invisible screen-sized shell going off-screen
	-- with the drag costs nothing -- it has no art left after the strip.
	--
	-- Runs once, never from the OnShow path: `S:MakeDraggable` creates a new
	-- handle frame per call and would leak one on every open.
	DetachFrame(frame)

	-- The handle goes INSIDE the panel's own top edge, not on the frame's
	-- top edge (that is the top of the SCREEN here) and not above the panel
	-- either -- the tab strip lives there, and `S:MakeDraggable` lifts its
	-- handle 50 frame levels, so an overlapping handle would swallow every
	-- tab click. The panel's first 35px are empty by construction (its
	-- TOPLEFT is anchored 35 above the first group box), so a 30px handle
	-- fits in that band without covering either the tabs or the boxes.
	--
	-- Remembered on the frame so `AnchorPageChrome` can move it with the rest
	-- of the outside-the-page chrome on every tab switch -- it has exactly the
	-- same problem the bottom buttons had if one page's panel sits differently
	-- from another's. The placement itself is done there, in one place, rather
	-- than duplicated here.
	local handle = S:MakeDraggable(frame, nil, function() SavePlacement(frame) end)
	if handle then
		frame.elvDragHandle = handle
		AnchorPageChrome(frame, frame.elvTitleAnchor)
	end

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyInterfaceOptionsChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyInterfaceOptionsSkin()
end

S:AddBlizzardSkin("uioptions", LoadSkin)
