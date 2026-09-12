-- Skins > Blizzard > VideoOptions -- reskins the native `OptionsFrame`
-- (Escape menu -> "Video Options") in place.
--
-- NOTHING HERE IS TAKEN FROM THE FrameXML AS FACT: only traces of the
-- real 1.12.1 layout survive on this server -- the live, detected
-- structure has to be used instead (the UA version has a tab strip,
-- sliders, checkboxes and a dropdown menu). So the real 1.12.1 file
-- (source/wow-ui-source/FrameXML/OptionsFrame.xml) is used ONLY to know
-- which TEMPLATES exist in this family; every structural decision below is
-- made from what the frame reports about itself at runtime.
--
-- What the real 1.12.1 window looks like, for orientation only -- do NOT
-- rely on any of it:
--
--   OptionsFrame          450x665, strata DIALOG, its own <Backdrop>
--     regions: header texture + title FontString + the nVidia logo
--     OptionsFrameDisplay / WorldAppearance / Brightness / PixelShaders /
--       Miscellaneous      (Frame, OptionFrameBoxTemplate -> <Backdrop>)
--     OptionsFrameSlider1..9        (Slider)
--     OptionsFrameCheckButton1..18  (CheckButton)
--     OptionsFrameResolution/Refresh/MultiSampleDropDown (Frame, dropdown)
--     OptionsFrameCancel / Okay / Defaults  (Button)
--
--   ... and NO TABS AT ALL. The live window has them, so this client's
--   layout is definitely not that one -- which is exactly why nothing here
--   is written against a name or a count.
--
-- THE TWO RULES THIS FILE IS BUILT ON, both carried over from windows that
-- have already been through a live test:
--
--  1. **A native `<Backdrop>` marks a GROUP BOX.** Straight from
--     Blizzard/UIOptions.lua, where it was measured: a page/plain container
--     carries none, the boxes sitting on it do. `elvHadNativeBackdrop` is
--     set by `S:ClearNativeBackdrop` on the way past, i.e. by the strip
--     itself -- and it is the flag that works on BOTH clients (its sibling
--     `elvBackdropNeutralized` only ever gets set on UA, which is what made
--     the first UIOptions release a no-op on legacy).
--
--  2. **Stop the walk AT a box, never inside one.** This is the general
--     form of the one per-name exception Blizzard/SoundOptions.lua still
--     carries: there, five nested frames carried a backdrop and only the
--     OUTERMOST one ("Voice Chat Settings") is the box -- lightening the
--     four wells nested inside it would just stack lighter slabs on top of
--     each other, so that file had to name the box (`OptionsVoiceChat`).
--     Descending no further once a box is found gets the same result with
--     no name at all, which is the only thing that can survive a layout
--     this project cannot see.
--
-- Everything else -- tabs, sliders, checkboxes, dropdowns, the bottom
-- buttons -- is left entirely to `S:SkinChildren`. All four kinds already
-- have a live-confirmed branch in the sweep (tabs via `$parentMiddle`,
-- dropdowns via their box art plus a real `$parentButton`, sliders via the
-- absence of scroll buttons, checkboxes/buttons via template art), so this
-- window needs no per-widget code of its own for any of them.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- Is the window the whole screen, or a bounded dialog?
--
-- MEASURED AT RUNTIME rather than assumed, because the two options windows
-- this project has already skinned answer it differently and this one's
-- live layout is unknown: `SoundOptionsFrame` is a bounded dialog (panel
-- painted over the whole window), while `UIOptionsFrame` is screen-sized
-- with the visible window being a child page (panel wrapped around the
-- group boxes instead -- a window-sized panel there would be a
-- screen-covering slab). Real 1.12.1 declares this window as a 450x665
-- DIALOG, so the bounded branch is the likely one -- but "likely" is what
-- this window's whole premise says not to trust.
--
-- Defaults to false (= treat as a bounded dialog) if anything can't be
-- read: that is the branch that still produces a correct-looking window on
-- a normal-sized frame, and its failure mode on a screen-sized one is
-- loudly visible rather than silent.
local SCREEN_FRACTION = 0.9
local function IsScreenSized(frame)
	local okW, width = pcall(frame.GetWidth, frame)
	local okH, height = pcall(frame.GetHeight, frame)
	local okPW, parentWidth = pcall(UIParent.GetWidth, UIParent)
	local okPH, parentHeight = pcall(UIParent.GetHeight, UIParent)
	width, height = tonumber(width), tonumber(height)
	parentWidth, parentHeight = tonumber(parentWidth), tonumber(parentHeight)
	if not (okW and okH and okPW and okPH) then return false end
	if not (width and height and parentWidth and parentHeight) then return false end
	if parentWidth <= 0 or parentHeight <= 0 then return false end
	return width >= parentWidth * SCREEN_FRACTION and height >= parentHeight * SCREEN_FRACTION
end

-- A group box is a Frame that carried a native `<Backdrop>` -- and is not
-- one of the two other things that can look like one.
local function IsGroupBox(widget, widgetType, name)
	if widgetType ~= "Frame" then return false end
	-- Our own surfaces: `S:CreateSurface` gives them a backdrop, so without
	-- this a re-apply pass would treat the box's own lighter surface as a
	-- nested box and paint another one inside it.
	if widget.elvSurface then return false end
	-- A closed dropdown is an ordinary Frame too. It has no `<Backdrop>` in
	-- this template family, so this is belt-and-braces -- but the sweep uses
	-- exactly this fingerprint (a real `$parentButton` child) and a dropdown
	-- wearing a GROUP_COLOR slab would be a visible mess. `name ~= ""`
	-- matters as much as `name ~= nil`: an unnamed native child reports the
	-- empty string on UA, which is TRUE in Lua (Blizzard/UIOptions.lua).
	if name and name ~= "" and _G[name .. "Button"] then return false end
	return widget.elvHadNativeBackdrop and true or false
end

-- Lightens every group box under `root`, appending each to `found` in walk
-- order (which is top-to-bottom for a normal options layout, so `found`'s
-- first and last entries are usable as panel anchors).
--
-- Never descends INTO a box -- see rule 2 at the top of the file.
local function LightenBoxes(root, found, depth)
	depth = tonumber(depth) or 0
	-- Same insurance cap as `S:SkinChildren`; no options layout is anywhere
	-- near this deep.
	if depth > 6 then return end

	local okKids, kids = pcall(function() return { root:GetChildren() } end)
	if not okKids or type(kids) ~= "table" then return end

	local i
	for i = 1, table.getn(kids) do
		-- Resolved first: an enumerated native child is a crippled wrapper on
		-- this client and its type-specific methods are not even present as
		-- fields (`S:ResolveWidget`).
		local kid = S:ResolveWidget(kids[i])
		local okType, kidType = pcall(kid.GetObjectType, kid)
		local okName, kidName = pcall(kid.GetName, kid)
		if okType then
			if IsGroupBox(kid, kidType, okName and kidName or nil) then
				S:CreateSurface(kid, S.GROUP_COLOR)
				table.insert(found, kid)
			elseif kidType ~= "Button" and kidType ~= "CheckButton"
				and kidType ~= "Slider" and not kid.elvSurface then
				-- Same recursion policy as `S:StripTextures`/`S:SkinChildren`:
				-- a Button/CheckButton belongs to its own styling function,
				-- and a Slider's `<Backdrop>` is its groove, not a box.
				LightenBoxes(kid, found, depth + 1)
			end
		end
	end
end

-- Wraps a panel around a page's boxes instead of around the page itself.
-- Only used on the screen-sized branch -- see `ApplyVideoOptionsChrome`.
-- Offsets are real ElvUI's own for this window family
-- (source/ElvUI-vanilla/ElvUI/Modules/Skins/Blizzard/Misc.lua:287-290), the
-- same ones Blizzard/UIOptions.lua uses: 35px of headroom above the first
-- box, because that band is where the box's own title FontString sits.
local function PanelAroundBoxes(page, boxes)
	local panel = S:CreatePanel(page)
	local count = table.getn(boxes)
	if panel and count > 0 then
		pcall(panel.ClearAllPoints, panel)
		pcall(panel.SetPoint, panel, "TOPLEFT", boxes[1], "TOPLEFT", -20, 35)
		pcall(panel.SetPoint, panel, "BOTTOMRIGHT", boxes[count], "BOTTOMRIGHT", 20, -20)
	end
	return panel
end

-- FORCE A RE-LAYOUT, the way a drag does.
--
-- Symptom this fixes: every time the window opens, dropdown menus render
-- in the wrong position, with their own background correctly underneath
-- them wherever they land, and stay that way until the window is dragged
-- -- a drag snaps everything into its correct place from then on.
--
-- Two things follow from it, and neither is a guess:
--
--  1. The surface anchoring is RIGHT -- the box is under the dropdown
--     wherever the dropdown happens to be, which is exactly what
--     anchoring it to `$parentLeft`/`$parentRight` buys. So the measured
--     +155px displacement is not a fixed template offset at all: it is a
--     STALE LAYOUT that has not been recomputed yet when the window comes
--     up.
--  2. A drag fixes it permanently. `S:MakeDraggable`'s handler does exactly
--     `SetMovable(true)` + `StartMoving` + `StopMovingOrSizing`, so that pair
--     is the operation that makes this client re-resolve the anchors -- no
--     theory needed about WHY the client leaves them stale.
--
-- So: do the same thing, with no mouse involved. `StartMoving` attaches the
-- frame to the cursor and `StopMovingOrSizing` in the same call detaches it
-- before a single frame is drawn, so nothing moves on screen -- the window
-- stays exactly where the user put it (`SetUserPlaced` keeps it there), and
-- the children get re-anchored as if it had been dragged. The same
-- start/stop warm-up pair already lives in `S:MakeDraggable`'s own
-- `StartDrag`, so it is a proven-harmless call on this client.
--
-- DEFERRED, not called inline: this window's native OnShow runs
-- `OptionsFrame_Load()`, which rebuilds every control from the current cvars,
-- and the stale positions are that pass's output. Nudging before it has
-- finished would just re-settle the OLD layout. One 0.05s one-shot per open
-- is enough to land after it, and is not a standing cost.
--
-- Scheduled TWICE, at 0.05 and 0.3. Nobody has measured when this client
-- finishes its own layout pass, and a nudge that lands too early simply
-- re-settles the stale positions; a second one costs one no-op re-anchor in
-- the common case and saves a whole test round in the other. Both are
-- one-shots -- nothing keeps running once the window is up.
local function Nudge(frame)
	local okShown, shown = pcall(frame.IsShown, frame)
	if not (okShown and shown) then return end
	pcall(frame.SetMovable, frame, true)
	if pcall(frame.StartMoving, frame) then
		pcall(frame.StopMovingOrSizing, frame)
	end
end

-- THE GROUP BOX IS WIDER THAN ITS OWN WINDOW -- MEASURED.
--
-- Confirmed as a separate issue from the stale dropdown layout above: it
-- survives the settle, so it is the client's own geometry, not a
-- layout-timing artifact.
--
-- Column-brightness profile of a live 2560x1440 screenshot, right edge,
-- four horizontal bands:
--
--   title band      (y  80..140)   flat UI ends at x=1766  <- PANEL_COLOR
--   tab strip       (y 180..220)   flat UI ends at x=1798  <- GROUP_COLOR
--   content         (y 600..900)   flat UI ends at x=1798  <- GROUP_COLOR
--   bottom buttons  (y1290..1340)  flat UI ends at x=1766  <- PANEL_COLOR
--
-- So the window's own right edge is 1766 and the group box runs to 1798 --
-- the box overhangs its own window by ~32 screen px (~17 UI px). The two
-- tones confirm which is which: the bands that stop at 1766 measure ~12/255
-- (`PANEL_COLOR` .05) and the ones that reach 1798 measure ~18/255
-- (`GROUP_COLOR` .075).
--
-- Nothing in this file positions either one: the panel is the frame's own
-- footprint and the box surface is the box's. The box is simply built wider
-- than the window it sits in, and skinning it is what made that visible --
-- natively the same overhang was drawn as the box's own tooltip-border
-- backdrop over the window's ornate art, where it read as decoration.
--
-- CLAMPED, and only our OWN surface is touched -- the native box keeps its
-- size and position, so no control moves or gets clipped (the rightmost
-- control, the multisample dropdown, ends ~45px inside the window edge
-- anyway). The right edge is pulled in to MIRROR the box's own left margin,
-- rather than to the window's exact edge: the box sits ~24 UI px in from the
-- left, so a flush right edge would read as lopsided.
local function ClampBoxes(frame)
	local boxes = frame.elvBoxes
	if type(boxes) ~= "table" then return end

	local okFL, frameLeft = pcall(frame.GetLeft, frame)
	local okFR, frameRight = pcall(frame.GetRight, frame)
	frameLeft, frameRight = tonumber(frameLeft), tonumber(frameRight)
	if not (okFL and okFR and frameLeft and frameRight) then return end

	local i
	for i = 1, table.getn(boxes) do
		local box = boxes[i]
		local bg = box and box.elvBackground
		if bg and not bg.elvClamped then
			local okBL, boxLeft = pcall(box.GetLeft, box)
			local okBR, boxRight = pcall(box.GetRight, box)
			boxLeft, boxRight = tonumber(boxLeft), tonumber(boxRight)
			if okBL and okBR and boxLeft and boxRight and boxRight > frameRight then
				local margin = boxLeft - frameLeft
				if margin < 0 then margin = 0 end
				-- Three points, fully constraining: TOPLEFT gives top and left,
				-- BOTTOM gives bottom, RIGHT overrides only the right edge.
				local okClamp = pcall(function()
					bg:ClearAllPoints()
					bg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
					bg:SetPoint("BOTTOM", box, "BOTTOM", 0, 0)
					bg:SetPoint("RIGHT", frame, "RIGHT", -margin, 0)
				end)
				if okClamp then
					bg.elvClamped = true
				else
					pcall(bg.ClearAllPoints, bg)
					pcall(bg.SetAllPoints, bg, box)
				end
			end
		end
	end
end

local function SettleLayout(frame)
	E:ScheduleTimer(function() Nudge(frame) end, 0.05)
	-- The clamp rides on the LATE nudge only, never the early one. It is a
	-- decision made from measured geometry, and the whole reason this settle
	-- exists is that geometry is not trustworthy right after the window
	-- opens. Reading it too early could only produce a WRONG clamp (a latched
	-- one, at that); reading it late can at worst produce none, and the "not
	-- overhanging" answer is the safe default.
	E:ScheduleTimer(function()
		Nudge(frame)
		ClampBoxes(frame)
	end, 0.3)
end

local function ApplyVideoOptionsChrome(frame)
	-- RECURSIVE, like SoundOptions.lua and unlike MainMenu.lua: this window's
	-- art is not all direct regions of the top frame. The group boxes' own
	-- `<Backdrop>`s live a level down, the sliders' grooves another level
	-- below that, and -- the point that matters most here -- this same walk
	-- is what SETS `elvHadNativeBackdrop`, so the box detection below has
	-- nothing to work with until it has run.
	--
	-- It also takes care of the two decorative regions the reference skins
	-- both remove by name (the dialog header art and the nVidia logo): they
	-- are direct Texture regions of the frame, so nothing needs to know they
	-- exist.
	S:StripTextures(frame, true)

	if IsScreenSized(frame) then
		-- Screen-sized: the visible window is a child page, so the panel goes
		-- on the page and wraps its boxes. Identical situation to
		-- `UIOptionsFrame`; see that file for the full reasoning.
		local okKids, kids = pcall(function() return { frame:GetChildren() } end)
		if okKids and type(kids) == "table" then
			local i
			for i = 1, table.getn(kids) do
				local kid = S:ResolveWidget(kids[i])
				local okType, kidType = pcall(kid.GetObjectType, kid)
				local okName, kidName = pcall(kid.GetName, kid)
				if okType and kidType == "Frame" and not kid.elvSurface then
					if IsGroupBox(kid, kidType, okName and kidName or nil) then
						-- A box sitting directly on a screen-sized window: there
						-- is no page to wrap, so it just gets its own surface.
						S:CreateSurface(kid, S.GROUP_COLOR)
					else
						local boxes = {}
						LightenBoxes(kid, boxes)
						if table.getn(boxes) > 0 then PanelAroundBoxes(kid, boxes) end
					end
				end
			end
		end
	else
		-- Bounded dialog: the window IS the page, so it gets the panel over
		-- its whole footprint and the boxes are lightened wherever they sit.
		-- This is also what both reference skins do for this window
		-- (pfUI: `CreateBackdrop(OptionsFrame)` plus one per box).
		S:CreatePanel(frame)
		-- Kept, not discarded: `ClampBoxes` needs the list once the layout has
		-- settled. Only this branch records it -- on the screen-sized branch a
		-- box would have to be clamped against its own PAGE rather than the
		-- window, and that branch has never fired on either client.
		local boxes = {}
		LightenBoxes(frame, boxes)
		frame.elvBoxes = boxes
	end

	-- Tabs, sliders, checkboxes, dropdowns and the bottom buttons, all of
	-- them without naming a single one. Tab spacing is deliberately left at
	-- the project default (`S.TAB_INSET_X = 10`) rather than the 2 that
	-- `UIOptionsFrame` needs: that value depends on whether this window's
	-- tabs OVERLAP (CharacterFrame-style, where the wide inset is what stops
	-- neighbouring border boxes from colliding) or sit apart (UIOptions
	-- style, where it just adds a gap), and nobody has seen these tabs yet.
	-- The default's failure mode is a gap that is too wide -- cosmetic, and a
	-- one-line fix (`frame.elvTabInsetX = 2`) once the screenshot exists.
	S:SkinChildren(frame)

	SettleLayout(frame)
end

local videoOptionsSkinApplied = false
local function ApplyVideoOptionsSkin()
	if videoOptionsSkinApplied then return end
	local frame = _G.OptionsFrame
	if not frame then
		-- LOUD, unlike the silent `return` the other skin files use. Every
		-- window skinned so far had its global name confirmed by a live
		-- measurement first; this one hasn't, so "the skin did nothing" and
		-- "this client calls the window something else" have to be
		-- distinguishable from the very first test.
		E:Print("Skins (video): OptionsFrame does not exist -- Video Options skin skipped")
		return
	end
	videoOptionsSkinApplied = true

	ApplyVideoOptionsChrome(frame)

	-- MOVABLE, added after the handle position concern (top of the window,
	-- where a tab strip could be) turned out not to matter in practice.
	-- Nothing was broken before this -- dragging was simply never built.
	--
	-- `SetUserPlaced(true)` is REQUIRED here, not decorative: real 1.12.1
	-- registers this window in `UIPanelWindows` (`UIParent.lua:16`,
	-- `area = "center"`), and the native panel-position manager silently
	-- adds a SECOND, conflicting anchor to any managed frame that isn't
	-- marked user-placed (see the Chat module's own frame-shrink fix for
	-- the same mechanism). `CharacterFrame` (also `UIPanelWindows`-managed)
	-- carries the same call for the same reason.
	--
	-- Unlike `UIOptionsFrame`, no `DetachFrame`/placement-saving is needed:
	-- that window is declared `setAllPoints` (no size of its own) and its own
	-- OnShow calls `SetupFullscreenScale`, which re-asserts the fullscreen
	-- placement on every open. This one is an ordinary sized dialog anchored
	-- at a single CENTER point, so `StartMoving` has something to move.
	--
	-- Runs once, from the load path only -- `S:MakeDraggable` builds a fresh
	-- handle frame per call and would leak one on every open if it were in
	-- `ApplyVideoOptionsChrome`.
	--
	-- The handle's own default height (24) is what keeps it off the tab
	-- strip: it is raised 50 frame levels, so anything it overlaps stops
	-- receiving clicks, and in the live screenshot the tabs start ~46px below
	-- the window's top edge, with only the title in the band above them.
	S:MakeDraggable(frame, nil)
	pcall(frame.SetUserPlaced, frame, true)

	-- Re-apply on every open: native code re-asserts visual state on show,
	-- silently undoing a one-time pass (established project-wide). This
	-- window's own native OnShow runs `OptionsFrame_Load()`, which rebuilds
	-- the controls from the current cvars, so it is a particularly likely
	-- one to need it.
	local ok = S:TryHookScript(frame, "OnShow", function() ApplyVideoOptionsChrome(frame) end)
	if not ok then E:Print("Skins (video): OptionsFrame OnShow hook failed to install") end
end

local function LoadSkin()
	ApplyVideoOptionsSkin()
end

S:AddBlizzardSkin("video", LoadSkin)
