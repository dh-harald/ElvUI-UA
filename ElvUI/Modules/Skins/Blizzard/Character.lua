-- Skins > Blizzard > Character -- reskins the native CharacterFrame
-- (paperdoll) IN PLACE (same frame object, same native tab-switching/
-- model/stat logic, nothing rebuilt from scratch) -- matches this
-- project's established recipe: strip native chrome, apply our own
-- SetBackdrop directly on the still-native frame (bgFile+edgeFile+
-- edgeSize=1, the already-proven-safe pairing -- edgeFile is never
-- omitted, since omitting it causes a gold/tan tint on this client), reuse
-- ElvUI.Util.CreateButtonBorder for anything button-shaped (same border
-- ActionBars/PetBar/UnitFrames already use), Chat.lua's own Kill()+
-- text-recolor recipe for the tab buttons.
--
-- IMPORTANT CAVEAT on the several fixes below that cite
-- source/wow-ui-source/FrameXML directly (region names, draw layers):
-- that tree is the OFFICIAL REAL 1.12.1 client's FrameXML, not UA's own
-- -- UA has no known extraction method or published source for its own
-- FrameXML equivalent. Region names/layer assignments confirmed there
-- are high-confidence for REAL 1.12.1 testing specifically; for UA they
-- remain a well-motivated ASSUMPTION (UA's whole design goal is 1.12.1
-- parity) pending live confirmation, not a guarantee -- treat any
-- "confirmed via FrameXML" note below as "confirmed for real 1.12.1,
-- expected but unverified for UA" unless a live UA test says otherwise.
--
-- Ported STRUCTURALLY from real ElvUI's own Modules/Skins/Blizzard/
-- Character.lua (source/ElvUI-vanilla) -- same target frames, same 20-slot
-- list, same PaperDollItemSlotButton_Update quality-color hook -- but NOT
-- its actual implementation, which depends on a full generic Skins API
-- (E:StripTextures/E:CreateBackdrop/E:StyleButton/
-- S:HandleTab/S:HandleCloseButton/...) this project doesn't have. Also
-- checked against source/UnrealUI/modules/character.lua for UA-specific
-- risk areas (pcall around every native call; that file layers a SEPARATE
-- background panel inside the native frame rather than SetBackdrop
-- directly on it -- not needed here, SetBackdrop on a container frame
-- doesn't affect its children's own rendering/interactivity, already
-- proven safe elsewhere in this project, e.g. ActionBars' own bar
-- containers).
--
-- SCOPE, first pass: outer frame chrome, movability (real Blizzard's own
-- CharacterFrame has none), close button, the 5 tab buttons' art, and the
-- 20 equipment slots (border + live quality coloring), plus
-- resistance/attribute readouts (see this file's own
-- StyleResistFrame/CharacterAttributesFrame notes further down).
-- Deliberately NOT reskinned this pass -- explicit scope cuts, not
-- oversights: the model rotate buttons. No dropdown menu was found on
-- this frame in either reference source.
--
-- SCOPE, second pass: each of the other 4 CharacterFrame subframes
-- (Reputation/Skill/Honor/PetPaperDoll) gets the same outer-chrome
-- treatment (see ApplySubFrameChrome further down) -- PLUS, for
-- PetPaperDollFrame specifically, its own close button and its
-- stat-panel/resistance-icon treatment (reusing this file's EXISTING
-- Character-tab helpers unchanged, since it uses the identical templates).
-- Deliberately NOT touched this pass: ReputationBar/Header content,
-- SkillFrame's own list/scrollframes, HonorFrame's HK/DK/rank buttons.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- CharacterResistanceFrame is deliberately NEVER stripped, not even via
-- the recursive walk from CharacterFrame: the Hide()+noop fix in
-- S:StripTextures would take the resistance icons down WITH the (now
-- finally removable) chrome, because
-- `MagicResistanceFrameTemplate` has no separate chrome texture at all
-- (confirmed via the FrameXML, PaperDollFrame.xml:106-123/654-674) -- the
-- icon IS the only Texture region there, so stripping it strips the icon.
-- Matches real ElvUI's/pfUI's own approach too, which never strips this
-- frame either, only adds a border around each icon (see StyleResistFrame
-- below). Registered once at load time, not per-OnShow.
S.stripSkipNames["CharacterResistanceFrame"] = true

-- HONOR TAB -- CONTENTS DELIBERATELY LEFT ALONE: our own outer chrome and
-- tabs apply, but the sweep must not touch the tab's own content. The
-- Honor tab's own content has no skin pass of its own to begin with, and
-- would visibly break if the sweep ran over it. The page currently shows
-- nothing but zeroes on this server, so there is
-- no value to protect there and no way to judge a fix; touching it blind
-- can only produce damage nobody can evaluate. Revisit when the page has
-- real data on it.
--
-- Both lists, because they gate two different walks and only together do
-- they leave the CONTENTS untouched:
--   * `stripSkipNames` stops `ApplyChrome`'s `S:StripTextures(CharacterFrame,
--     true)` from recursing in;
--   * `autoSkinSkipNames` stops `S:SkinChildren(CharacterFrame)` from both
--     styling it and descending into it.
-- What deliberately still runs: the CharacterFrame panel itself and
-- `CharacterFrameTab1-5` (both live on CharacterFrame, not inside
-- HonorFrame), plus `StyleSubFrameChrome`'s own NON-recursive
-- `S:StripTextures(HonorFrame, false)` -- that only clears HonorFrame's
-- own direct regions, i.e. the native page background that would
-- otherwise sit on top of our panel. Exactly the "frame yes, contents no"
-- split that was asked for.
S.stripSkipNames["HonorFrame"] = true
S.autoSkinSkipNames["HonorFrame"] = true

-- ROOT CAUSE of "Pet tab resistance icons/border never render, only the
-- number and the tooltip do" -- and it was never a strata/frame-level
-- problem at all. `PetResistanceFrame` is
-- the EXACT structural twin of `CharacterResistanceFrame` (confirmed via
-- the FrameXML: PetPaperDollFrame.xml:517-634 vs.
-- PaperDollFrame.xml:641-758 -- same `MagicResistanceFrameTemplate`, same
-- per-icon BACKGROUND Texture + FontString layout, same ids, same sizes)
-- -- the ONLY difference was that Character's own container was
-- registered here as strip-exempt and Pet's never was.
--
-- Why that alone killed it: `ApplyChrome`'s very first line is
-- `S:StripTextures(CharacterFrame, true)` -- a RECURSIVE walk, and
-- `PetPaperDollFrame` is a direct child of `CharacterFrame`
-- (PetPaperDollFrame.xml:4, `parent="CharacterFrame"`), so the walk
-- descends CharacterFrame -> PetPaperDollFrame -> PetResistanceFrame ->
-- PetMagicResFrame1-5 and, on each of those, (a) Hide()+permanently
-- noop's EVERY Texture region -- including the fresh ARTWORK icon
-- `StyleResistFrame` had created -- and (b) `SetBackdrop(nil)`s their
-- child frames, which is exactly what `ElvUI.Util.CreateButtonBorder`'s
-- 3 border layers are. FontStrings are never touched by the strip, and
-- the tooltip lives on the template's own OnEnter script, so BOTH
-- survived -- precisely the reported symptom ("csak az ertek es a
-- tooltip"). And because both `StyleResistFrame` (frame.elvIconCropped)
-- and `CreateButtonBorder` (button.elvBackdrop) guard their one-time
-- work, nothing was ever rebuilt afterwards: ApplyChrome re-runs on
-- every CharacterFrame OnShow, so the very first panel-open after login
-- wiped the icons and borders permanently for the session.
S.stripSkipNames["PetResistanceFrame"] = true

-- `PetPaperDollPetInfo` (the pet diet / happiness icon) -- SAME root
-- cause as `PetResistanceFrame` right above, found the same way: it's a
-- child Frame of `PetPaperDollFrame` whose ONLY content is a single
-- BACKGROUND Texture (FrameXML: PetPaperDollFrame.xml:245-274,
-- `UI-PetHappiness`), so `ApplyChrome`'s recursive
-- `S:StripTextures(CharacterFrame, true)` walk reached it and
-- Hide()+noop'd the icon outright -- while its tooltip, living on the
-- frame's own OnEnter script, kept working. Registered strip-exempt so
-- both the native region AND the replacement icon `StylePetDietIcon`
-- draws survive; the native one is still hidden deliberately there.
S.stripSkipNames["PetPaperDollPetInfo"] = true

local ACCENT_COLOR = S.ACCENT_COLOR

local SLOTS = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
	"ShirtSlot", "TabardSlot", "WristSlot",
	"HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
	"Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
	"MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot",
}

-- CharacterFrameTab1-5: Character, Reputation, Pet (conditional on
-- HasPetUI(), stays a valid frame either way, just hidden), Skills,
-- Honor -- per source/UnrealUI/modules/character.lua's own comment on
-- this exact frame set. Only cosmetic styling is applied here (corner
-- art, text color) -- native anchoring/show-hide logic is untouched, so
-- unlike UnrealUI's own tab handling there's no "don't chain into a
-- hidden tab" concern to replicate.
local TAB_COUNT = 5

-- StyleTab/StyleCloseButton live in Skins.lua as `S:StyleTab`/
-- `S:StyleCloseButton`, shared with Friends.lua (FriendsFrameTab1-4 share
-- CharacterFrameTabButtonTemplate; FriendsFrameCloseButton is the same
-- UIPanelCloseButton shape). Full recipe details (6-piece not 3-piece tab
-- art, the DisableDrawLayer fix, the close button's 20x20/X-glyph recipe)
-- live in Skins.lua's own comments, not re-derived here.

-- Native NormalTexture (the slot's own frame/border art) is cleared the
-- same precise way ActionBars.lua's own StyleButton does it -- NOT a
-- blanket S:StripTextures(slot), which would also blank the icon (the
-- icon is one of the slot button's own regions too). The icon itself is
-- kept, just cropped/repositioned to sit inside our new border, matching
-- ActionBars' identical recipe exactly.
local function StyleSlot(slotName)
	local slot = _G["Character"..slotName]
	local icon = _G["Character"..slotName.."IconTexture"]
	if not slot then return end

	if not slot.elvNormalTextureCleared then
		local okNormal, normalTexture = pcall(slot.GetNormalTexture, slot)
		pcall(slot.SetNormalTexture, slot, "")
		slot.SetNormalTexture = E.noop
		if okNormal and normalTexture then
			pcall(normalTexture.SetTexture, normalTexture, nil)
		end
		slot.elvNormalTextureCleared = true
	end

	ElvUI.Util.CreateButtonBorder(slot)

	if icon and not slot.elvIconStyled then
		-- 0.08/0.92 matches real ElvUI's own default E.TexCoords, same
		-- crop ActionBars.lua's own icons use to remove the baked-in
		-- rounded-corner border every stock WoW icon texture has.
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", slot, "TOPLEFT", 1, -1)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
		slot.elvIconStyled = true
	end
end

-- Resistance icons (MagicResFrame1-5) -- confirmed via the FrameXML
-- (PaperDollFrame.xml:106-123, MagicResistanceFrameTemplate) that this
-- one has NO texture layers of its own at all -- the icon is added
-- dynamically by PaperDollFrame.lua, not defined in XML -- so there is no
-- native border art here to strip in the first place. Real ElvUI's and
-- pfUI's own Character skins both handle this the same way: ADD a fresh
-- border around each icon rather than trying to remove anything. Same
-- recipe as StyleSlot above (this project's own ActionBar-matching
-- border), just without the NormalTexture-clearing step this template
-- doesn't have.
local RESIST_FRAMES = { "MagicResFrame1", "MagicResFrame2", "MagicResFrame3", "MagicResFrame4", "MagicResFrame5" }

-- Even with our own border added, the icon itself still shows its
-- baked-in ornate frame unless explicitly cropped tighter. A generic
-- proportional inward crop from the native TexCoord is not enough --
-- both real ElvUI's own Character.lua AND pfUI's own
-- character.lua (two INDEPENDENTLY-written, real-vanilla-proven addons)
-- hardcode a SPECIFIC, hand-tuned TexCoord rectangle PER resistance icon
-- -- not a generic percentage crop -- and land on nearly IDENTICAL
-- numbers despite being unrelated codebases, strong evidence these are
-- the genuinely correct values, not a guess. Neither one computes them
-- from the native XML's own per-icon TexCoords (which select a much
-- larger region, ~0-1 horizontally, ~0.11 tall vertically per icon,
-- including the baked-in border) -- both replace them outright with
-- these tighter, independently-converged-on numbers. Ported from real
-- ElvUI's own Modules/Skins/Blizzard/Character.lua:65-69 (pfUI's own
-- version, source/pfUI/skins/blizzard/character.lua:25-31, differs only
-- in the last decimal place or two -- used ElvUI's exact numbers here).
-- Order is Arcane/Fire/Nature/Frost/Shadow for MagicResFrame1-5, matching
-- both reference sources' own comments.
local RESIST_TEXCOORDS = {
	{ 0.21875, 0.8125, 0.25, 0.32421875 },        -- MagicResFrame1, Arcane
	{ 0.21875, 0.8125, 0.0234375, 0.09765625 },   -- MagicResFrame2, Fire
	{ 0.21875, 0.8125, 0.13671875, 0.2109375 },   -- MagicResFrame3, Nature
	{ 0.21875, 0.8125, 0.36328125, 0.4375 },      -- MagicResFrame4, Frost
	{ 0.21875, 0.8125, 0.4765625, 0.55078125 },   -- MagicResFrame5, Shadow
}

-- `SetTexCoord` on an EXISTING native region evidently doesn't visually
-- apply on this client at all, matching this whole investigation's
-- broader pattern: MODIFYING a pre-existing native object often silently
-- fails here, while CREATING something new and HIDING the native
-- original (both independently proven throughout this file already --
-- the border frames, the background panel, the chrome Hide()+noop fix)
-- reliably works. So the native icon region is Hide()+noop'd (not
-- touched otherwise), and a brand new Texture is created and drawn
-- ourselves, using the same real-vanilla asset path
-- (`Interface\PaperDollInfoFrame\UI-Character-ResistanceIcons` -- can't
-- confirm this from a live GetTexture() call, that returns nothing
-- usable on this client same as everywhere else in this file, but it's
-- the actual path per the real 1.12.1 FrameXML) and the proven
-- TexCoords above.
--
-- `PetMagicResFrame1-5`: a frame STRATA + FRAME LEVEL fix (on
-- `PetMagicResFrame1`'s own ancestor chain, which sits above our created
-- border layers' default strata) got the "0" text number showing again,
-- but the ICON itself still never rendered, and a separate
-- tooltip-content oddity (only the resistance NAME shows, no
-- value/subtext) remained unexplained. That fix is NOT applied here --
-- `StyleResistFrame` stays in the exact form Character's own
-- already-confirmed-working `MagicResFrame1-5` call sites use, no
-- strata/level branch, since it only partially worked. Don't re-attempt
-- the same strata+level combination without solving the icon and
-- tooltip gaps too.
local function StyleResistFrame(name, index)
	local frame = _G[name]
	if not frame then return end
	ElvUI.Util.CreateButtonBorder(frame)

	if frame.elvIconCropped then return end
	frame.elvIconCropped = true

	-- The native "0" FontString (MagicResText1-5) sits on the SAME
	-- "BACKGROUND" layer the native icon used to
	-- (confirmed via the FrameXML, PaperDollFrame.xml:663-671, both in one
	-- <Layer level="BACKGROUND"> block) -- our new icon draws on
	-- "ARTWORK" (a higher layer), so it now covers the text instead of
	-- sitting behind it. Real ElvUI's own HandleResistanceFrame hits this
	-- identical problem and fixes it the identical way: icon on ARTWORK,
	-- text explicitly promoted to OVERLAY (Modules/Skins/Blizzard/
	-- Character.lua:52-53) -- ported directly rather than guessed at.
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if ok and type(regions) == "table" then
		local i
		for i = 1, table.getn(regions) do
			local region = regions[i]
			local okType, rType = pcall(region.GetObjectType, region)
			if okType and rType == "Texture" then
				pcall(region.Hide, region)
				region.Show = E.noop
			elseif okType and rType == "FontString" then
				pcall(region.SetDrawLayer, region, "OVERLAY")
			end
		end
	end

	-- Icon inset widened 2->5px: otherwise confirmed working (the
	-- border-baked-in-art problem is genuinely solved).
	local coords = RESIST_TEXCOORDS[index]
	if coords then
		local icon = frame:CreateTexture(nil, "ARTWORK")
		pcall(icon.SetTexture, icon, "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons")
		pcall(icon.SetTexCoord, icon, coords[1], coords[2], coords[3], coords[4])
		pcall(icon.SetPoint, icon, "TOPLEFT", frame, "TOPLEFT", 5, -5)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
	end
end

-- Reputation/Skill "+/-" expand-collapse buttons -- Blizzard-themed
-- native buttons on both tabs. Checked real ElvUI's own Character.lua
-- instead of guessing: it reskins
-- `ReputationHeader1-NUM_FACTIONS_DISPLAYED`/
-- `SkillFrameCollapseAllButton`/`SkillTypeLabel1-SKILLS_TO_DISPLAY` with a
-- custom PlusMinusButton sprite sheet, kept in sync with Blizzard's own
-- expanded/collapsed state via `hooksecurefunc(button, "SetNormalTexture",
-- ...)` (reading whether the PATH Blizzard just set contains "Minus" or
-- "Plus"). **Deliberately NOT ported that exact mechanism** -- that's the
-- 3-arg OBJECT-METHOD `hooksecurefunc` overload, which this project has
-- ALREADY independently confirmed unreliable on this client (never fired
-- during the oUF Castbar icon-capture investigation -- see this file's own
-- InstallQualityHook comment). Used the CONFIRMED-WORKING 2-arg
-- BARE-GLOBAL-NAME form instead, hooking the native UPDATE
-- functions (`ReputationFrame_Update`/`SkillFrame_UpdateSkills`) rather
-- than the per-button texture setter, then reading the plain state fields
-- Blizzard's own code already sets on each button afterward
-- (`factionHeader.isCollapsed` -- confirmed via real ElvUI's own read of
-- the same field; `skillTypeLabel.isExpanded`/`SkillFrameCollapseAllButton
-- .isExpanded` -- confirmed via source/wow-ui-source/FrameXML/
-- SkillFrame.lua:63-68/417-425, opposite polarity from Reputation's own
-- field, both read as-is rather than normalized).
--
-- REAL SPRITE, not an ASCII glyph: custom addon-shipped texture files do
-- render fine on UA (`source/Bagzen` successfully renders custom shipped
-- icon/button textures via this exact mechanism) -- a missing file at
-- the referenced path, not a client limitation, is what breaks this if
-- it ever appears to fail. Real ElvUI's own actual asset,
-- `Interface\AddOns\ElvUI\Media\Textures\PlusMinusButton` (now vendored
-- into `target/ElvUI/media/textures/PlusMinusButton.blp`), is used here,
-- matching real ElvUI's own visual result exactly.
local NUM_FACTIONS_DISPLAYED = _G.NUM_FACTIONS_DISPLAYED or 15
local SKILLS_TO_DISPLAY = _G.SKILLS_TO_DISPLAY or 12
-- Collapse-glyph recipe (native icon killed, own bordered 16x16 glyph in
-- its place) lives in Skins.lua: the Quest Log's header rows and its "All"
-- button need the identical treatment, down to the same 16x16-at-LEFT+3
-- geometry, so it is shared rather than copied. These two wrappers exist
-- only so the call sites below read unchanged.
local function StylePlusMinusButton(button, refresh)
	S:StylePlusMinusButton(button, nil, refresh)
end

local function SetGlyphExpanded(button, expanded)
	S:SetGlyphExpanded(button, expanded)
end

-- `SkillFrameCollapseAllButton` is the one widget on this window anchored
-- to a TEXTURE the strip hides: `<Anchor point="LEFT"
-- relativeTo="SkillFrameExpandTabLeft" relativePoint="RIGHT" x="-3" y="-3">`
-- (SkillFrame.xml). Once that texture is Hide()+noop'd, the anchor stops
-- resolving on this client and the button renders at a stale position --
-- live symptom: it appeared on top of the Quest Log window, doubling its
-- "All", and snapped back only when something forced a re-layout. Same
-- class as KeyBindingFrame's own title, which hung off the hidden
-- `UI-DialogBox-Header` banner and only flashed into place while the window
-- was being dragged.
--
-- The fix is to stop depending on the dead region, not to keep it alive.
-- The offsets reproduce where the native anchor chain put it: the texture
-- sits at its parent's TOPLEFT +0,+6 and is 8x32, so its RIGHT edge is at
-- x+8 and its vertical centre at y-10; the button's own -3,-3 lands it at
-- the parent's TOPLEFT +5,-13. `GetParent()` is used rather than the
-- containing frame's name, which nothing else in this file needs.
local function ReanchorSkillCollapseAll()
	local button = _G.SkillFrameCollapseAllButton
	if not button or button.elvReanchored then return end

	local okParent, parent = pcall(button.GetParent, button)
	if not okParent or not parent then return end
	button.elvReanchored = true

	pcall(button.ClearAllPoints, button)
	pcall(button.SetPoint, button, "LEFT", parent, "TOPLEFT", 5, -13)
end


-- POLLING, not hooking: hooking `ReputationFrame_Update`/
-- `SkillFrame_UpdateSkills` fails with "attempt to call a nil value" on
-- every single panel-open, not just intermittently. Not a lazy-load
-- TIMING issue (these FrameXML functions maybe not defined yet at
-- PLAYER_LOGIN): the SAME pattern also hits
-- `PaperDollItemSlotButton_Update` (see `InstallQualityHook` below),
-- which belongs to the Character/PaperDoll tab -- the ALWAYS-visible
-- default tab, open the instant the panel shows, no lazy-load excuse
-- possible there -- and it still fails on every open. Conclusion: these
-- global functions most likely don't exist on this client AT ALL, not
-- just "not yet," so retrying forever would just repeat the same
-- failure message on every open, forever. Uses this project's own
-- well-established alternative for exactly this situation
-- (Cooldowns.lua/UnitFrames.lua/PetBar.lua's own `UpdateCheckedState`,
-- etc. -- not relying solely on event delivery, periodic re-check
-- instead): a shared `E:ScheduleRepeatingTimer` reads the plain
-- `.isCollapsed`/`.isExpanded` state fields Blizzard's own code already
-- sets on each button directly, no hook of any kind needed.
-- Row -> list index, the same mapping the client's own code uses
-- (`ReputationFrame.lua`/`SkillFrame.lua`).
local function RowIndex(scrollFrameName, row)
	local ok, offset = pcall(FauxScrollFrame_GetOffset, _G[scrollFrameName])
	if not ok or not offset then offset = 0 end
	return row + offset
end

-- State comes from the QUEST/SKILL/FACTION APIs, not from the
-- `.isExpanded`/`.isCollapsed` fields on the buttons.
--
-- Those fields are maintained by `SkillFrame_UpdateSkills` and
-- `ReputationFrame_Update` -- and neither of those functions exists on this
-- client (the finding that made this a poll rather than a hook in the first
-- place). So the fields are only as fresh as whatever else happens to write
-- them, which is why SOME categories tracked the click correctly and others
-- stayed a step behind: the ones that worked were the ones something else
-- kept up to date. `GetSkillLineInfo`/`GetFactionInfo` are correct the
-- moment the click toggles the state, for every row, and cannot go stale.
--
-- Same rule as the Quest Log's own collapse glyphs: on this client, ask the
-- API for state, never a native field or the rendering.
local plusMinusPollStarted = false
local function PollPlusMinusGlyphs()
	local j
	for j = 1, NUM_FACTIONS_DISPLAYED do
		local header = _G["ReputationHeader"..j]
		if header then
			-- Eight discards, not seven: GetFactionInfo returns name,
			-- description, standingID, barMin, barMax, barValue, atWarWith,
			-- canToggleAtWar, isHeader, isCollapsed, isWatched -- so
			-- isHeader is the NINTH value. Reading it one slot early lands
			-- on canToggleAtWar, which is nil on a header, and the glyph
			-- gets hidden on exactly the rows that should carry one.
			local ok, _, _, _, _, _, _, _, _, isHeader, isCollapsed =
				pcall(GetFactionInfo, RowIndex("ReputationListScrollFrame", j))
			if ok and isHeader then
				S:SetGlyphShown(header, true)
				SetGlyphExpanded(header, not isCollapsed)
			else
				S:SetGlyphShown(header, false)
			end
		end
	end

	-- The "All" button is not a list row and has no index; it carries its
	-- own state, like the Quest Log's equivalent.
	SetGlyphExpanded(SkillFrameCollapseAllButton, SkillFrameCollapseAllButton and SkillFrameCollapseAllButton.isExpanded)

	for j = 1, SKILLS_TO_DISPLAY do
		local label = _G["SkillTypeLabel"..j]
		if label then
			local ok, _, isHeader, isExpanded = pcall(GetSkillLineInfo, RowIndex("SkillListScrollFrame", j))
			if ok and isHeader then
				S:SetGlyphShown(label, true)
				SetGlyphExpanded(label, isExpanded)
			else
				S:SetGlyphShown(label, false)
			end
		end
	end
end

-- The poll is the only thing that can DISCOVER a state change here
-- (`ReputationFrame_Update`/`SkillFrame_UpdateSkills` do not exist on this
-- client, so there is nothing to wrap), but it is not what DRIVES the
-- glyph: `S:StylePlusMinusButton` installs it as an OnClick post-hook too,
-- so the icon changes in the click instead of on the next tick. The poll
-- stays as the backstop for changes no click causes.
local function StylePlusMinusButtons()
	local i
	for i = 1, NUM_FACTIONS_DISPLAYED do
		StylePlusMinusButton(_G["ReputationHeader"..i], PollPlusMinusGlyphs)
	end
	StylePlusMinusButton(SkillFrameCollapseAllButton, PollPlusMinusGlyphs)
	ReanchorSkillCollapseAll()
	for i = 1, SKILLS_TO_DISPLAY do
		StylePlusMinusButton(_G["SkillTypeLabel"..i], PollPlusMinusGlyphs)
	end

	if not plusMinusPollStarted then
		plusMinusPollStarted = true

		-- EVENTS, not the click, are what these two lists actually change
		-- on. A click here only REQUESTS the collapse/expand; the list's
		-- own state does not flip until the client answers, so an OnClick
		-- post-hook still reads the previous state and the glyph appears to
		-- lag exactly as if nothing had been hooked at all. (The Quest Log
		-- is the opposite case -- there the state flips inside the click,
		-- which is why the same hook works fine on it.)
		--
		-- `UPDATE_FACTION` is the event `QuestLogFrame` itself listens to
		-- for the same reason. Nothing is ever unregistered: the handler is
		-- idempotent, and `UnregisterEvent` is unreliable on this client
		-- anyway.
		pcall(S.RegisterEvent, S, "UPDATE_FACTION", function() PollPlusMinusGlyphs() end)
		pcall(S.RegisterEvent, S, "SKILL_LINES_CHANGED", function() PollPlusMinusGlyphs() end)

		E:ScheduleRepeatingTimer(PollPlusMinusGlyphs, 0.3)
	end
end

-- PaperDollFrame's own chrome (the "Character" tab's content frame) --
-- pulled into its OWN function and given its OWN OnShow hook, matching the
-- SUB_FRAMES treatment further down, not left as a CharacterFrame-OnShow-only
-- thing. Root cause: `CharacterFrame_ShowSubFrame` (native tab-switch) hides/shows
-- `PaperDollFrame` independently of `CharacterFrame`'s own OnShow (which
-- only fires once, when the whole panel first opens) -- the SAME "native
-- re-asserts state on show" gap already fixed for the other 4 subframes
-- (`ApplySubFrameChrome`'s own per-subframe OnShow hooks) but never
-- extended to PaperDollFrame itself, since its chrome application used to
-- live directly inline in `ApplyChrome` instead. Switching away to another
-- tab and back to Character could let native code re-show PaperDollFrame's
-- own chrome (the `UI-Character-CharacterTab-L1/R1`+BottomLeft/BottomRight
-- quadrant textures, PaperDollFrame.xml:130-173) with nothing left to
-- re-strip it at that specific moment. The other 4 subframes' own hooks
-- (already in place) should already cover them -- this was the one actual
-- gap, not a project-wide pattern that needs re-auditing everywhere.
-- 3D model rotate buttons (`CharacterModelFrameRotateLeftButton`/
-- `RightButton`, `PaperDollFrame.xml:234-253`; `PetModelFrameRotateLeftButton`/
-- `RightButton`, `PetPaperDollFrame.xml:201-224`). Recipe HOISTED to
-- `S:StyleModelRotateButton(s)` (`Modules/Skins/Skins.lua`) once
-- `PetStableModelRotateLeftButton`/`RightButton` (`Stable.lua`) became a
-- second FILE needing the identical native shape -- see that function's
-- own header for the full recipe and why (re-crops the EXISTING native
-- icon in place via a 4-value `SetTexCoord`, matching real ElvUI's own
-- `S:HandleRotateButton`).

-- Title dropdown -- NOT part of real 1.12.1's own PaperDollFrame.xml --
-- a UA/Emberveil-specific addition, so the usual "check the real
-- FrameXML" research path didn't apply here directly. Real global name
-- confirmed live via `S:DumpMouseFocus()`: `PlayerTitleDropDown`/
-- `PlayerTitleDropDownButton` -- this naming EXACTLY matches real
-- vanilla's own actual, real `UIDropDownMenuTemplate`
-- (`source/wow-ui-source/FrameXML/UIDropDownMenuTemplates.xml:253-361`,
-- a genuine 1.12.1-era shared template, just never used by
-- PaperDollFrame.xml itself in the unmodified client) -- so a real
-- reference DOES exist after all, once the right file was found:
-- `$parentLeft`/`$parentMiddle`/`$parentRight` (3 chrome Texture regions,
-- `CharacterCreate-LabelFrame` asset), `$parentText` (the "None"
-- FontString), `$parentButton` (a 24x24 Button with the classic
-- Normal/Pushed/Disabled/Highlight 4-slot set, a `UI-ChatIcon-ScrollDown-*`
-- down-chevron icon).
local function StylePlayerTitleDropDown()
	local dd = PlayerTitleDropDown
	if not dd or dd.elvStyled then return end
	dd.elvStyled = true

	-- WOTLK-era real ElvUI's version is ONE unified wide box (left-aligned
	-- text + a plain arrow at the box's own right edge, no separate
	-- bordered control) rather than plain text sitting next to a small,
	-- individually-bordered button -- matched to that combined look here.

	-- Non-recursive -- the 3 chrome pieces are direct Texture regions of
	-- `dd` itself per the template's own `<Layers>` block, same shape
	-- already handled for SkillDetailStatusBar's own chrome earlier in
	-- this file. Leaves `$parentText` (a FontString) and `$parentButton`
	-- (a Button) untouched.
	S:StripTextures(dd, false)

	-- Widen into a single unified box -- real vanilla's own template
	-- sizes this tightly around "None"; the WOTLK reference is a much
	-- wider bar so the title text has room and the arrow sits flush at
	-- its own right edge, not immediately after the text.
	pcall(dd.SetWidth, dd, 240)

	-- Live-tested: widening pushed it further RIGHT, not left -- meaning
	-- the native anchor is LEFT-based, not right-based as first guessed.
	-- Re-anchored to center on the whole CharacterFrame horizontally.
	--
	-- Preserving the CURRENT vertical position via `GetTop()` before
	-- re-anchoring does NOT work here: the widget's native Y position
	-- isn't in a simple, directly-comparable coordinate relationship with
	-- CharacterFrame's own `GetTop()` at all (plausibly parented to
	-- UIParent or something else UA-internal, with its own unrelated Y),
	-- so that produces a real but MEANINGLESS offset -- the box ends up
	-- floating well ABOVE CharacterFrame entirely. Uses a fixed,
	-- hand-picked offset instead -- a reasonable guess (matching roughly
	-- where the WOTLK reference shows it, just below the name/level
	-- text), not a computed "preserve the original" value. Adjust this
	-- one number based on the next live screenshot rather than
	-- reintroducing dynamic GetTop() math.
	pcall(dd.ClearAllPoints, dd)
	-- -45 (rather than the tighter -60) gives clearance from the rotate
	-- buttons directly below it (Y decreases going DOWN from a "TOP"
	-- anchor).
	pcall(dd.SetPoint, dd, "TOP", CharacterFrame, "TOP", 0, -45)

	-- Both the color AND the mechanism come from the one shared dropdown-box
	-- recipe (`S:StyleDropDownBox`, Skins.lua), rather than a bespoke
	-- inline backdrop table applied straight onto the native frame, so this
	-- box matches the Who-frame dropdown and every edit box. The width/
	-- position math above and the text re-anchor below stay local, because
	-- those genuinely ARE title-dropdown-specific.
	S:StyleDropDownBox(dd)

	local text = _G["PlayerTitleDropDownText"]
	if text then
		pcall(text.SetTextColor, text, ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3])
		-- Native default is RIGHT-justified, anchored off the (now
		-- stripped-but-still-geometrically-present) `$parentRight` chrome
		-- piece near the ORIGINAL narrow width -- re-anchored to the
		-- new wider box's own LEFT edge instead, matching the reference.
		pcall(text.SetJustifyH, text, "LEFT")
		pcall(text.ClearAllPoints, text)
		pcall(text.SetPoint, text, "LEFT", dd, "LEFT", 8, 0)
	end

	-- Deliberately NOT `S:StyleSquareIconButton` (no `CreateButtonBorder`)
	-- this round -- a separate bordered control would duplicate the
	-- OUTER box's own border, contradicting the "one seamless box"
	-- reference. Just the native texture clear + a small fresh icon,
	-- matching this file's own established idiom for the clear step,
	-- re-anchored to the new wide box's own right edge (native anchor
	-- was relative to `$parentRight`, which stayed at its old, narrow
	-- position after `dd` itself was widened).
	local btn = _G["PlayerTitleDropDownButton"]
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
		local okHighlight, highlightTexture = pcall(btn.GetHighlightTexture, btn)
		if okHighlight and highlightTexture then
			pcall(highlightTexture.SetTexture, highlightTexture, nil)
			pcall(highlightTexture.Hide, highlightTexture)
			highlightTexture.Show = E.noop
		end

		-- Confirmed via `S:Dump("PlayerTitleDropDownButton")`: our own
		-- icon is there (tex=1, shownWithSize=1) but the native chrome
		-- still renders underneath it if left alone. Same
		-- already-established pattern as CharacterAttributesFrame's own
		-- chrome: `SetTexture(nil)` on a pre-existing native slot doesn't
		-- reliably stop it from rendering -- `DisableDrawLayer` as a
		-- standing property is the actually-reliable fix. Our own icon is
		-- on "OVERLAY" (above ARTWORK), so disabling ARTWORK here only
		-- suppresses the native chrome, not our own icon.
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

		pcall(btn.ClearAllPoints, btn)
		pcall(btn.SetPoint, btn, "RIGHT", dd, "RIGHT", -8, 0)
	end
end

local paperDollHooked = false
local function ApplyPaperDollChrome()
	if PaperDollFrame then S:StripTextures(PaperDollFrame, true) end

	-- Stat panel -- explicit dedicated call, matching real ElvUI's own
	-- separate `E:StripTextures(CharacterAttributesFrame)`, even though
	-- the recursive strip on PaperDollFrame above should already reach it
	-- as a descendant -- belt and suspenders, costs nothing (idempotent).
	if CharacterAttributesFrame then S:StripTextures(CharacterAttributesFrame, true) end

	-- CharacterResistanceFrame is deliberately NEVER stripped -- see this
	-- file's own top-level S.stripSkipNames registration for why.

	-- CONFIRMED via the actual vanilla FrameXML (source/wow-ui-source/
	-- FrameXML/PaperDollFrame.xml:274-404): CharacterAttributesFrame owns
	-- exactly 9 Texture regions, all on the BACKGROUND layer, forming the
	-- three separate boxed panels (Strength-through-Armor, Melee Attack,
	-- Ranged Attack) -- same DisableDrawLayer fix as CharacterFrame's own
	-- chrome, targeted at "BACKGROUND" specifically (confirmed via XML to
	-- be the ONLY layer used for this frame's border art -- no FontString
	-- or icon of any kind lives on CharacterAttributesFrame's own direct
	-- regions, those are all on its CharacterStatFrame1-5 children, so
	-- disabling this whole layer here is safe).
	if CharacterAttributesFrame then
		pcall(CharacterAttributesFrame.DisableDrawLayer, CharacterAttributesFrame, "BACKGROUND")
	end

	-- Portrait -- real ElvUI's own Character skin doesn't show one.
	-- Standard vanilla convention for a dialog's own PortraitFrameTemplate
	-- region is `<FrameName>Portrait`, i.e. `CharacterFramePortrait`.
	S:Kill(CharacterFramePortrait)

	S:StyleModelRotateButtons(CharacterModelFrameRotateLeftButton, CharacterModelFrameRotateRightButton)
	StylePlayerTitleDropDown()

	if not paperDollHooked and PaperDollFrame then
		if S:TryHookScript(PaperDollFrame, "OnShow", ApplyPaperDollChrome) then
			paperDollHooked = true
		end
	end
end

-- Checked the real 1.12.1 FrameXML for each subframe
-- (source/wow-ui-source/FrameXML/
-- {ReputationFrame,SkillFrame,HonorFrame,PetPaperDollFrame}.xml) instead of
-- guessing -- all 4 use the EXACT SAME chrome convention already solved for
-- PaperDollFrame: a handful of UNNAMED corner Texture regions, direct
-- children of the subframe itself (confirmed via the raw XML -- unlike
-- CharacterFrame's own chrome, which lives on NESTED children and needed
-- recursion, these are direct `<Layer>` entries right under
-- `<Frame name="ReputationFrame">` etc.). So a plain NON-recursive
-- `S:StripTextures(frame, false)` is enough and, critically, SAFE: none of
-- these subframes' own functional content (ReputationBar/Header,
-- SkillFrame's list/scrollframes, HonorFrame's HK/DK/rank buttons,
-- PetPaperDollFrame's stat/resist frames) is a DIRECT region of the
-- subframe itself -- they're all nested child Frames/StatusBars/Buttons one
-- level down, untouched by a non-recursive strip. Recursing (the way
-- PaperDollFrame needed) would risk stripping ReputationBar's own fill
-- texture, etc. -- deliberately NOT done here.
--
-- Explicit scope cut: ReputationBar/Header, SkillFrame's list content,
-- HonorFrame's HK/DK/rank buttons are NOT touched this pass -- only each subframe's own outer
-- chrome, plus PetPaperDollFrame's close button/stat-panel/resist icons,
-- which reuse this file's EXISTING Character-tab helpers UNCHANGED, since
-- PetAttributesFrame/PetMagicResFrame1-5 use the identical templates
-- already solved above for CharacterAttributesFrame/MagicResFrame1-5.
--
-- ROOT CAUSE for the `HonorFrame` OnShow hook failure: NOT a
-- lazy-load/missing-frame issue at all -- the identical bug is already
-- documented and fixed in a completely different vendored library,
-- `Libraries/LibDBIcon-1.0/LibDBIcon-1.0.lua:441-447`, which hits it on
-- `Minimap`. AceHook-3.0's own `:HookScript` validation calls
-- `frame:HasScript(method)` before allowing the hook, and on THIS client
-- `:HasScript()` incorrectly returns `false` for some frames even though
-- `:GetScript()`/`:SetScript()` both work completely normally on the
-- exact same frame+script -- a genuine client-level binding bug,
-- confirmed by two independent real libraries hitting it on two
-- unrelated frames, not a HonorFrame-specific or lazy-load issue at
-- all. `S:TryHookScript` (added to `Skins.lua`, see its own comment for
-- the full mechanism) tries the normal AceHook path first and falls
-- back to LibDBIcon-1.0's own proven manual `:SetScript`-chain technique
-- only where that fails -- used everywhere in this file that hooks a
-- script from here on, not just for `HonorFrame`.

local SUB_FRAMES = { "ReputationFrame", "SkillFrame", "HonorFrame", "PetPaperDollFrame" }

local function StyleSubFrameChrome(frame)
	if not frame then return end
	S:StripTextures(frame, false)
end

-- PetAttributesFrame -- same "SetTexture(nil) clears the path but the box
-- still renders" finding already confirmed for CharacterAttributesFrame
-- (this file's own comment further up) -- same fix, same reasoning: only 2
-- Texture regions here (vs. CharacterAttributesFrame's 9), confirmed via
-- the FrameXML to be its ONLY layer (no FontString/icon of any kind lives
-- on PetAttributesFrame's own direct regions -- those are all on its
-- PetStatFrame1-5/PetAttackFrame/etc children), so disabling the whole
-- BACKGROUND layer here is safe the same way.
local function StylePetAttributesFrame()
	if not PetAttributesFrame then return end
	pcall(PetAttributesFrame.DisableDrawLayer, PetAttributesFrame, "BACKGROUND")
end

-- Pet diet / happiness icon (`PetPaperDollPetInfo`). Recipe HOISTED to
-- `S:StylePetHappinessIcon(frame, levelRefFrame)` (`Modules/Skins/Skins.lua`)
-- once `PetStablePetInfo` (`Stable.lua`) became a second consumer of the
-- identical native element (same asset, same per-happiness crop table) --
-- see that function's own header for the full recipe and why.
local function StylePetDietIcon()
	S:StylePetHappinessIcon(PetPaperDollPetInfo, PetModelFrame)
end

-- Pet header/footer texts -- `PetNameText`/`PetLevelText`/
-- `PetLoyaltyText`/`PetTrainingPointText`/`PetTrainingPointLabel` are the
-- 5 FontStrings sitting directly on `PetPaperDollFrame`'s own BACKGROUND
-- layer (FrameXML: PetPaperDollFrame.xml:58-105), sharing that layer with
-- the native chrome textures this file strips. The real fix for them
-- going missing is the explicit `elvBackground` frame level in
-- `ApplyChrome` (see its own comment there) -- this promotion to OVERLAY
-- is the cheap belt-and-suspenders half of the same fix: at equal frame
-- levels draw order still falls back to draw LAYER, so putting the text
-- on the topmost layer keeps it in front of any BACKGROUND-layer backdrop
-- regardless. Exactly the recipe already proven for `MagicResText1-5`
-- (see StyleResistFrame). Text and colors otherwise untouched -- real
-- ElvUI doesn't restyle these either.
local PET_INFO_TEXTS = {
	"PetNameText", "PetLevelText", "PetLoyaltyText",
	"PetTrainingPointText", "PetTrainingPointLabel",
}

local function StylePetInfoText()
	local i
	for i = 1, table.getn(PET_INFO_TEXTS) do
		local fs = _G[PET_INFO_TEXTS[i]]
		if fs then
			pcall(fs.SetDrawLayer, fs, "OVERLAY")
		end
	end
end

-- Pet XP bar (PetPaperDollFrameExpBar) -- real ElvUI's own call site is
-- three lines (Blizzard/Character.lua:135-138):
-- `E:StripTextures(PetPaperDollFrameExpBar)` +
-- `SetStatusBarTexture(E.media.normTex)` + `E:CreateBackdrop(..., "Default")`
-- -- ported via this project's own equivalents, same recipe already
-- proven for the Reputation/Skill rank/Skill detail bars.
--
-- The native chrome here is 2 OVERLAY Texture regions carved out of
-- `UI-MainMenuBar-Dwarf` (only the first is even named,
-- `PetPaperDollXPBar1`, the second is anonymous -- confirmed via the
-- FrameXML, PetPaperDollFrame.xml:109-176), so a targeted S:Kill by name
-- can't reach both; a non-recursive `S:StripTextures` gets them both and
-- leaves `PetPaperDollFrameExpBarText` (a FontString, never touched by
-- the strip) alone -- it's the hover-only XP readout and must survive.
--
-- Deliberately NOT guarded on the SetStatusBarTexture line: this bar IS
-- reached by `ApplyChrome`'s own recursive CharacterFrame strip (it's a
-- StatusBar child of PetPaperDollFrame, and the strip only skips
-- Button-type children), so if that walk ever Hide()+noop's the widget's
-- own fill texture on a later panel-open, re-applying the texture every
-- pass repairs it -- unlike the resistance icons, which needed the
-- strip-exemption above because their icon is a region we CREATE.
local function StylePetExpBar()
	local bar = PetPaperDollFrameExpBar
	if not bar then return end

	if not bar.elvStyled then
		bar.elvStyled = true
		S:StripTextures(bar, false)
		pcall(bar.SetBackdrop, bar, {
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		pcall(bar.SetBackdropColor, bar, 0, 0, 0, 0)
		pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 1)
	end

	pcall(bar.SetStatusBarTexture, bar, E.media and E.media.normTex or "Interface\\Buttons\\WHITE8x8")
end

-- Pet's own 5 resistance icons (PetMagicResFrame1-5) use the IDENTICAL
-- MagicResistanceFrameTemplate already solved above for Character's own
-- MagicResFrame1-5 -- StyleResistFrame already takes an explicit name/index
-- pair, so this reuses it unchanged rather than duplicating the function.
-- Icon still doesn't render here (border/number do) -- paused for now.
local function StylePetResistFrames()
	local i
	for i = 1, 5 do
		StyleResistFrame("PetMagicResFrame"..i, i)
	end
end

-- Reputation bars (ReputationBar1-NUM_FACTIONS_DISPLAYED). Checked the
-- real FrameXML (ReputationFrame.xml:57-210, `ReputationBarTemplate`) for
-- exactly what to target, matched against a real-ElvUI-vanilla reference
-- screenshot (same native background, bar texture replaced, no hover/
-- selected highlight, a plain square-ish border):
--   * `$parentReputationBarLeft`/`$parentReputationBarRight` -- the native
--     background chrome (ARTWORK layer, direct regions) -- stripped, not
--     recolored, matching real ElvUI's own treatment.
--   * `$parentHighlight1`/`$parentHighlight2` -- the gold/glow highlight
--     (OVERLAY layer, `hidden="true"` by default) -- the template's own
--     `<Scripts><OnEnter>` calls `Highlight1:Show()`/`Highlight2:Show()`
--     directly (and `OnLeave` only re-hides them if this faction ISN'T
--     currently selected) -- this is the thick rounded gold glow around a
--     hovered/selected faction row, absent in the real-ElvUI reference.
--     Hide()+noop, not just Hide() alone -- these get re-Shown directly by
--     the template's own native OnEnter/OnLeave scripts on every hover,
--     the exact same "native re-asserts via a direct :Show() call"
--     pattern this file has hit and fixed everywhere else via a permanent
--     Show=noop override.
--   * `BarTexture file="...UI-Character-Skills-Bar"` -- the StatusBar's
--     own native fill texture -- replaced via `SetStatusBarTexture` with
--     a flat white texture (`Interface\Buttons\WHITE8x8`, this project's
--     own established flat-fill convention throughout), matching real
--     ElvUI's own bar-texture swap.
--   * Border: a THIN square edge (`SetBackdrop` with a transparent fill,
--     `edgeFile`+`edgeSize=1` only) rather than this file's usual thicker
--     3-layer `CreateButtonBorder` -- matches the reference screenshot's
--     own thin, plain rectangular look, deliberately NOT the same border
--     style used for slots/tabs/close buttons elsewhere in this file.
--   * `$parentFactionName`/`$parentFactionStanding` (FontStrings) and the
--     `$parentCheck`/`$parentAtWarCheck` (native at-war indicators,
--     hidden by default, only shown when actually relevant) are left
--     completely untouched -- meaningful content/state, not decorative
--     chrome.
local function StyleReputationBar(index)
	local name = "ReputationBar"..index
	local bar = _G[name]
	if not bar or bar.elvStyled then return end
	bar.elvStyled = true

	S:Kill(_G[name.."ReputationBarLeft"])
	S:Kill(_G[name.."ReputationBarRight"])
	S:Kill(_G[name.."Highlight1"])
	S:Kill(_G[name.."Highlight2"])

	-- A hover/select indicator can still show even after the Hide()+noop
	-- kill above -- the template's own OnEnter/OnLeave scripts call
	-- `getglobal(name.."Highlight1"):Show()` DIRECTLY (ReputationFrame.xml:
	-- 190-203), and apparently that survives the per-region Show=noop
	-- override here, matching the SAME class of "a native call bypasses a
	-- per-region override" finding already hit for the tab buttons
	-- (Enable/Disable state) -- same fix: `DisableDrawLayer("OVERLAY")`,
	-- a standing frame property immune to any number of :Show() calls.
	-- Confirmed via the FrameXML that Highlight1/Highlight2 share this
	-- layer with only one other region, the at-war "Check" icon
	-- (`$parentCheck`, hidden by default, only shown when a faction is
	-- actually at war) -- accepted tradeoff: that small in-row icon goes
	-- with it, redundant anyway with the "At War" checkbox already in the
	-- detail popup.
	pcall(bar.DisableDrawLayer, bar, "OVERLAY")

	-- E.media.normTex -- matches real ElvUI's own EXACT call here
	-- (`factionBar:SetStatusBarTexture(E.media.normTex)`, source/
	-- ElvUI-vanilla's own Character.lua) rather than a hardcoded literal.
	-- See Init.lua's own comment for the full `E.media.normTex` explanation.
	pcall(bar.SetStatusBarTexture, bar, E.media and E.media.normTex or "Interface\\Buttons\\WHITE8x8")

	pcall(bar.SetBackdrop, bar, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(bar.SetBackdropColor, bar, 0, 0, 0, 0)
	pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 1)
end

-- Skill rank bars (SkillRankFrame1-SKILLS_TO_DISPLAY) -- same treatment
-- as Reputation's own bars: replace the bar texture, strip the border.
-- Real ElvUI's own actual code for this (source/ElvUI-vanilla's
-- Character.lua) confirms the exact structure: `SkillRankFrame%d` (the bar itself),
-- `SkillRankFrame%dBorder` (chrome to strip), `SkillRankFrame%dBackground`
-- (a background texture to clear) -- `E:StripTextures(border)` +
-- `background:SetTexture(nil)` there map onto this file's own established
-- `S:Kill()` (Hide+noop, more reliable than SetTexture(nil) alone on this
-- client, per this file's own repeated finding) for both.
local function StyleSkillRankBar(index)
	local name = "SkillRankFrame"..index
	local bar = _G[name]
	if not bar or bar.elvStyled then return end
	bar.elvStyled = true

	-- `$parentBorder` (real FrameXML: SkillFrame.xml's own
	-- SkillStatusBarTemplate) is NOT a plain Texture region like
	-- Reputation's own equivalent -- it's a whole separate 281x32 BUTTON
	-- with its own explicitly-named NormalTexture ($parentNormal, the
	-- persistent border art) and HighlightTexture ($parentHighlight, the
	-- hover glow) children. `S:Kill()` on the button itself (Hide+noop)
	-- doesn't reliably suppress those two CHILD regions on this client --
	-- same "hiding a parent doesn't hide its children" UA quirk already
	-- documented project-wide -- so both are reached and cleared directly,
	-- matching this file's own established StylePlusMinusButton idiom.
	local border = _G[name.."Border"]
	if border then
		local okNormal, normalTexture = pcall(border.GetNormalTexture, border)
		if okNormal and normalTexture then
			pcall(normalTexture.SetTexture, normalTexture, nil)
			pcall(normalTexture.Hide, normalTexture)
			normalTexture.Show = E.noop
		end
		local okHighlight, highlight = pcall(border.GetHighlightTexture, border)
		if okHighlight and highlight then
			pcall(highlight.SetTexture, highlight, nil)
			pcall(highlight.Hide, highlight)
			highlight.Show = E.noop
		end
		S:Kill(border)
	end
	S:Kill(_G[name.."Background"])

	pcall(bar.SetStatusBarTexture, bar, E.media and E.media.normTex or "Interface\\Buttons\\WHITE8x8")

	pcall(bar.SetBackdrop, bar, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(bar.SetBackdropColor, bar, 0, 0, 0, 0)
	pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 1)
end

local function StyleSkillRankBars()
	local i
	for i = 1, SKILLS_TO_DISPLAY do
		StyleSkillRankBar(i)
	end
end

-- Skill Detail panel: the "unlearn a primary profession" popup is also
-- Blizzard-styled, including its close button -- confirmed via the real
-- FrameXML (SkillFrame.xml) to be `SkillFrameCancelButton`
-- (`SkillFrameAcceptButton` is XML-commented-out, doesn't actually exist
-- on this client at all, ruled out as a candidate) and the 3 buttons on
-- `SkillDetailStatusBar` (LeftArrow/RightArrow rank navigation,
-- UnlearnButton). Deliberately NOT touching `SkillDetailStatusBar`'s own
-- border/fill/background here -- that's still part of the "bars need
-- reskinning later" scope deferred elsewhere; only the 3 BUTTONS on it
-- are in scope here.

-- `SkillFrameCancelButton` uses `UIPanelButtonTemplate` -- confirmed via
-- the real FrameXML (UIPanelTemplates.xml:18-27) to be a PLAIN Normal/
-- Pushed/Disabled/Highlight texture set via the standard Button API (no
-- separate named Left/Middle/Right pieces the way the CharacterFrame tabs
-- needed) -- same recipe as this file's own StyleCloseButton, just
-- keeping the native "CLOSE" label (recolored) instead of replacing it
-- with a glyph, since the text itself is the whole point here.
--
-- `S:StyleUIPanelButton` lives in Skins.lua, shared with Friends.lua's own
-- UIPanelButtonTemplate action buttons (Add Friend, Remove Friend, ...).

-- PetPaperDollCloseButton, plus a one-time repair of what the WRONG
-- helper did to it before. This button was mistakenly run
-- through StyleCloseButton -- the X-style handler meant for
-- CharacterFrameCloseButton -- which squashed it to 20x20 and stamped an
-- "X" FontString over its own "Close" label. Since a native Blizzard
-- frame's already-applied mutations are NOT undone by /reload on this
-- client (established elsewhere in this file: testing a Skins change
-- really off needs a full client restart), the leftover 20x20 size and
-- leftover X would otherwise survive into any session that only
-- /reload'ed -- so both are explicitly undone here rather than relying on
-- a restart. Size restored to the FrameXML's own 80x22
-- (PetPaperDollFrame.xml:277-279).
local function StylePetCloseButton()
	local button = PetPaperDollCloseButton
	if not button then return end

	if button.elvCloseText then
		pcall(button.elvCloseText.SetText, button.elvCloseText, "")
		pcall(button.elvCloseText.Hide, button.elvCloseText)
	end
	pcall(button.SetWidth, button, 80)
	pcall(button.SetHeight, button, 22)

	S:StyleUIPanelButton(button)
end

-- `SkillDetailStatusBarUnlearnButton` -- REAL sprite icon, not an ASCII
-- glyph. `S:HandleCloseButton` was separately checked (Skins.lua:388+)
-- for the actual Character-frame close button convention -- real ElvUI
-- uses a plain "x" FontString there, NOT a sprite, so `StyleCloseButton`'s
-- own existing ASCII "X" already matches real ElvUI's own real convention
-- and needed no change.
-- Matches real ElvUI's OWN actual recipe exactly
-- (`source/ElvUI-vanilla/ElvUI/Modules/Skins/Skins.lua`'s own
-- `S:HandleNextPrevButton`/`S:SquareButton_SetIcon`, and
-- `Blizzard/Character.lua`'s own `SkillDetailStatusBarUnlearnButton`
-- call site). An inset-crop approach on the native-sized button alone is
-- NOT enough to make it read smaller. Two things the reference does
-- differently, confirmed by reading it directly instead of guessing at
-- inset values:
-- (1) real ElvUI's icon is a FIXED 13x13 texture, always CENTERED in the
--     button, independent of the button's own outer size -- not an
--     inset that shrinks/grows proportionally with the button.
-- (2) real ElvUI explicitly RESIZES THE BUTTON ITSELF
--     (`E:Size(SkillDetailStatusBarUnlearnButton, 24)`, native default is
--     32x32 per the FrameXML) -- shrinking only the icon's inset inside
--     an unchanged, still-native-sized button never visibly shrinks
--     anything.
-- Also confirmed via the same reference: real ElvUI does NOT skin
-- `SkillDetailStatusBarLeftArrow`/`RightArrow` AT ALL (grepped for
-- "Arrow" in its own Character.lua -- zero matches) -- only
-- `UnlearnButton` gets this treatment here too, matching upstream
-- exactly.
-- The actual icon-button recipe now lives in `S:StyleSquareIconButton`
-- (`Modules/Skins/Skins.lua`), hoisted there once the scrollbar up/down
-- arrows (see `S:HandleScrollBar`, wired in below) needed the identical
-- thing -- this file no longer keeps its own local copy.

-- Unlearn button only -- resized to 16x16 (24x24 still reads too big;
-- ~70-75% of that lands on the next multiple of 8) and re-anchored off
-- `SkillDetailStatusBarBorder`'s own right edge
-- (real ElvUI's own exact offset) since the native anchor point assumes
-- the button's old 32x32 footprint.
local function StyleUnlearnButton(button)
	if not button then return end
	S:StyleSquareIconButton(button, "DELETE")
	pcall(button.SetWidth, button, 16)
	pcall(button.SetHeight, button, 16)
	local border = _G["SkillDetailStatusBarBorder"]
	if border then
		pcall(button.ClearAllPoints, button)
		pcall(button.SetPoint, button, "LEFT", border, "RIGHT", 5, 0)
	end
	pcall(button.SetHitRectInsets, button, 0, 0, 0, 0)
end

-- `SkillDetailStatusBar`'s own chrome. Real ElvUI's own call site
-- (`E:StripTextures(SkillDetailStatusBar)` +
-- `SkillDetailStatusBar:SetStatusBarTexture(E.media.normTex)`,
-- Blizzard/Character.lua:290-293) strips its 3 direct-child Texture
-- regions ($parentBorder/$parentFillBar/$parentBackground, confirmed via
-- the real FrameXML -- none of them are the actual progress fill, that's
-- the StatusBar widget's own separate built-in texture slot set via
-- SetStatusBarTexture) and gives it the shared ElvUI Blank/normTex fill
-- -- ported directly via this project's own `S:StripTextures` (non-
-- recursive, matching real ElvUI's own non-recursive call) plus the
-- established thin backdrop recipe already used for the Skill rank/
-- Reputation bars.
local function StyleSkillDetailBar()
	local bar = SkillDetailStatusBar
	if not bar or bar.elvStyled then return end
	bar.elvStyled = true

	S:StripTextures(bar, false)

	pcall(bar.SetStatusBarTexture, bar, E.media and E.media.normTex or "Interface\\Buttons\\WHITE8x8")

	pcall(bar.SetBackdrop, bar, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(bar.SetBackdropColor, bar, 0, 0, 0, 0)
	pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 1)
end

local skillDetailHooked = false
local function ApplySkillDetailChrome()
	-- `SkillFrameCancelButton` is not styled by name:
	-- it is a plain `UIPanelButtonTemplate` descendant of CharacterFrame,
	-- so `ApplyChrome`'s own sweep recognises it from the template's art.
	-- `StyleUnlearnButton` below stays -- that button is RESIZED and has
	-- its native label suppressed, which is more than styling.
	StyleSkillDetailBar()
	StyleUnlearnButton(SkillDetailStatusBarUnlearnButton)
	-- Real ElvUI's own call site: `S:HandleScrollBar
	-- (SkillDetailScrollFrameScrollBar)` (Blizzard/Character.lua:288).
	S:HandleScrollBar(_G["SkillDetailScrollFrameScrollBar"])

	-- SkillDetailStatusBar (and therefore its 3 buttons) only actually
	-- exists/populates once a skill row has been clicked -- matches this
	-- file's now-standard "native re-asserts/lazily-shown" pattern, same
	-- reasoning as every other per-subframe OnShow hook in this file.
	-- `S:TryHookScript` (AceHook first, native :SetScript fallback if
	-- AceHook's own :HasScript misfires -- see Skins.lua) rather than a
	-- bare hook call.
	if not skillDetailHooked and SkillDetailStatusBar then
		if S:TryHookScript(SkillDetailStatusBar, "OnShow", ApplySkillDetailChrome) then
			skillDetailHooked = true
		end
	end
end

local function StyleReputationBars()
	local i
	for i = 1, NUM_FACTIONS_DISPLAYED do
		StyleReputationBar(i)
	end
end

-- Reputation detail popup (ReputationDetailFrame): a modal with a text
-- label and 3 checkbox options (At War, Move to Inactive, Show as
-- Experience Bar) plus a close button. Checked real ElvUI's own
-- Character.lua first: it strips this frame, applies its own
-- "Transparent" template, and skins the close button + all 3 checkboxes
-- (`E:StripTextures` + `E:SetTemplate` + `S:HandleCloseButton` +
-- `S:HandleCheckBox` x3) -- rebuilt here from this project's own
-- primitives, same recipe as everywhere else in this file. Checked the
-- real FrameXML (source/wow-ui-source/FrameXML/ReputationFrame.xml:
-- 631-834): `ReputationDetailFrame` has its own native `<Backdrop>`
-- (cleared by `S:StripTextures`'s own first line) plus 3 direct regions
-- -- an unnamed `UI-Character-Reputation-DetailBackground` texture and 2
-- named ones (`ReputationDetailCorner`/`Divider`, dialog-box corner/divider
-- chrome) -- all direct children of the frame itself (not nested), so a
-- plain NON-recursive strip already reaches and Hide()+noop's all 3,
-- without needing to touch the close button or checkboxes (child FRAMES,
-- untouched by a non-recursive strip). The 2 FontStrings
-- (`ReputationDetailFactionName`/`Description`) are left alone as always.
-- Native checkbox chrome: a 26x26 button carrying UI-CheckBox-Up/Down/
-- Highlight art plus a CheckedTexture (the sword/checkmark that conveys
-- the actual state). Real ElvUI's own S:HandleCheckBox
-- (source/ElvUI-vanilla/ElvUI/Modules/Skins/Skins.lua:309-326) does
-- exactly four things: nil the Normal/Pushed/Highlight/Disabled texture
-- slots, add its own backdrop, INSET that backdrop 4px on every side
-- (E:SetInside(frame.backdrop, nil, 4, 4)), and leave the CheckedTexture
-- completely alone so the check still reads on top. Rebuilt here from
-- this project's own primitives.
--
-- The 4px INSET matters: a border applied straight to the checkbox draws
-- at the full 26x26 native hit-area size instead of the ~18x18 box real
-- ElvUI shows. Native checkboxes deliberately carry several px of empty
-- padding inside their clickable footprint; a border drawn at that full
-- size reads as an oversized slab, not a checkbox.
-- Lives as `S:StyleCheckBox` (Skins.lua) so the generic auto-skin sweep
-- (`S:SkinChildren`) can reach checkboxes in windows this file knows
-- nothing about. Kept as a named local alias rather than replacing the 3
-- call sites below, so this file's own reading order stays intact.
local function StyleReputationCheckbox(checkbox)
	S:StyleCheckBox(checkbox)
end

local reputationDetailHooked = false
local function ApplyReputationDetailChrome()
	local frame = ReputationDetailFrame
	if not frame then return end

	-- Non-recursive -- reaches the frame's own native Backdrop + its 3
	-- direct Texture regions, leaves the close button/checkboxes (child
	-- Frames) and the 2 FontStrings untouched.
	S:StripTextures(frame, false)

	-- SEPARATE, INSET-FREE child background frame instead of SetBackdrop
	-- directly on ReputationDetailFrame: the modal can still show as light
	-- grey even after `S:StripTextures` clears the native `<Backdrop>`
	-- (`Interface\DialogFrame\UI-DialogBox-Background`, a light tan/grey
	-- parchment texture) and our own dark backdrop is applied right
	-- after. Matches the exact same class of issue already solved for
	-- CharacterFrame itself (see this file's own `ApplyChrome` comment):
	-- calling `SetBackdrop(frame, nil)` then immediately `SetBackdrop
	-- (frame, {...})` on the SAME frame in one call apparently doesn't
	-- reliably replace a native backdrop on this client -- a genuinely
	-- separate child frame with its OWN backdrop sidesteps whatever native
	-- backdrop state this leaves behind, instead of fighting it directly.
	-- `SetAllPoints` (not an inset) -- unlike CharacterFrame's own
	-- background, this popup has no tab-strip/footer area to leave
	-- uncovered, so no inset math is needed. EnableMouse(false) so it
	-- never intercepts clicks meant for the close button/checkboxes above
	-- it; left at the plain default auto-assigned frame level (no
	-- explicit SetFrameLevel) -- matches CharacterFrame's own background,
	-- which needed no level override once its own chrome was genuinely
	-- removed rather than merely covered.
	-- Explicit frame level (S:CreatePanel's default), matching `frame`'s own
	-- base level: without it, the checkboxes can render invisible even
	-- though checking one blind still registers the click (so the
	-- checkbox itself works, it's just not visible). Root cause: `bg`
	-- left at its DEFAULT auto-assigned frame level,
	-- which on THIS frame apparently lands above the pre-existing
	-- checkboxes/close button (unlike CharacterFrame's own background,
	-- where the default level happened to already sit below its siblings --
	-- not a universal rule, frame-specific). Forcing `bg` down to `frame`'s
	-- own base level guarantees it's the backmost layer regardless of how
	-- the checkboxes/close button/text happened to be auto-leveled.
	S:CreatePanel(frame)

	S:StyleCloseButton(ReputationDetailCloseButton)
	StyleReputationCheckbox(ReputationDetailAtWarCheckBox)
	StyleReputationCheckbox(ReputationDetailInactiveCheckBox)
	StyleReputationCheckbox(ReputationDetailMainScreenCheckBox)

	-- Own OnShow hook -- this popup shows on demand (clicking to expand a
	-- faction), independently of ReputationFrame's own OnShow -- matches
	-- this file's now-standard "native re-asserts/lazily-shown" pattern.
	-- pcall-wrapped: an unguarded HookScript failure here must never be
	-- able to take down anything else in the same call chain.
	if not reputationDetailHooked then
		if S:TryHookScript(frame, "OnShow", ApplyReputationDetailChrome) then
			reputationDetailHooked = true
		end
	end

	-- Own sweep: this popup is a SEPARATE toplevel frame, not a descendant
	-- of CharacterFrame, so ApplyChrome's own catch-all never reaches it.
	S:SkinChildren(frame)
end

-- Hooks each subframe's own OnShow, not just applying once here --
-- CharacterFrame_ShowSubFrame (native tab-switch) shows/hides these
-- INDEPENDENTLY of CharacterFrame's own OnShow (which only fires once, when
-- the whole panel first opens) -- matches this file's own established
-- "native re-asserts state on show" finding for CharacterFrame itself.
-- Guarded so hooks only ever register once, not on every ApplyChrome call
-- (ApplyChrome itself already re-runs on every CharacterFrame OnShow).
local subFramesHooked = false
local function ApplySubFrameChrome()
	local i
	for i = 1, table.getn(SUB_FRAMES) do
		StyleSubFrameChrome(_G[SUB_FRAMES[i]])
	end

	-- PetPaperDollCloseButton is a UIPanelButtonTemplate with the text
	-- "CLOSE" (FrameXML: PetPaperDollFrame.xml:276), NOT an X-style
	-- CloseButton like CharacterFrameCloseButton -- StyleCloseButton was
	-- squashing it to 20x20 and stamping an "X" FontString on top of its
	-- own "Close" label. Real ElvUI uses its plain button handler here
	-- too (`S:HandleButton(PetPaperDollCloseButton)`,
	-- Blizzard/Character.lua:110) -- StyleUIPanelButton is this file's
	-- equivalent, already used for SkillFrameCancelButton.
	StylePetCloseButton()
	StylePetAttributesFrame()
	StylePetResistFrames()
	StylePetInfoText()
	StylePetDietIcon()
	StylePetExpBar()
	S:StyleModelRotateButtons(PetModelFrameRotateLeftButton, PetModelFrameRotateRightButton)
	StylePlusMinusButtons()
	StyleReputationBars()
	StyleSkillRankBars()
	-- Native list scrollbars. Real ElvUI's own call sites are
	-- `S:HandleScrollBar(ReputationListScrollFrameScrollBar)`/
	-- `(SkillListScrollFrameScrollBar)` (`Blizzard/Character.lua:
	-- 221-222,284-285`) -- ported directly via the shared
	-- `S:HandleScrollBar` (Modules/Skins/Skins.lua).
	S:HandleScrollBar(_G["ReputationListScrollFrameScrollBar"])
	S:HandleScrollBar(_G["SkillListScrollFrameScrollBar"])
	ApplyReputationDetailChrome()
	-- `ApplySkillDetailChrome` used to define and self-register its OWN
	-- re-apply-on-show hook INSIDE its own body, but nothing ever called
	-- it the FIRST time -- a chicken-and-egg gap: the hook that would
	-- keep re-styling it never got a chance to register either, so this
	-- whole panel stayed 100% native. A purely visual comparison against
	-- real ElvUI's own reference can mask this: real ElvUI's own DELETE
	-- icon and Blizzard's native CancelButton-Up happen to look similarly
	-- like a red prohibition circle, so an untouched panel and a styled
	-- one can look deceptively alike. Called explicitly here now.
	ApplySkillDetailChrome()

	-- ROOT CAUSE for CharacterFrame's own chrome-strip appearing to
	-- regress after previously working: one of these 4 `S:HookScript`
	-- calls can throw "Usage: HookScript(object, method, [handler]): You
	-- can only hook a script on a frame object" at PLAYER_LOGIN, UNWRAPPED
	-- in pcall unlike every other native call in this file. Since this
	-- runs from inside `LoadSkin()` (via `ApplyChrome` ->
	-- `ApplySubFrameChrome`), an uncaught error here aborts the REST of
	-- `LoadSkin()` too -- INCLUDING its own final line,
	-- `S:HookScript(frame, "OnShow", ...)`, which registers CharacterFrame's
	-- own re-apply-on-show hook. That hook then silently never gets
	-- installed: nothing re-runs the strip after the panel is actually
	-- opened, on ANY tab, since the one hook that mattered most never got
	-- registered. Fixed by pcall-wrapping every `S:HookScript` call added
	-- in this pass, matching this file's own established defensive
	-- convention everywhere else -- one subframe failing to hook must
	-- never be able to take down anything downstream of it again.
	-- Per-frame retry, not one shared guard: `HonorFrame` can fail to hook
	-- with "Usage: HookScript(object, method, [handler]): You can only
	-- hook a script on a frame object" even though it is non-nil (passed
	-- the `if sub then` check) -- AceHook-3.0 doesn't recognize it as a
	-- valid frame object at this point, same likely "not
	-- created/lazily-loaded yet at PLAYER_LOGIN" timing issue as
	-- `ReputationFrame_Update`/`SkillFrame_UpdateSkills` above. A shared
	-- `subFramesHooked` guard flipped to `true` regardless of any
	-- individual failure would permanently block retries for ALL 4
	-- subframes the moment even ONE of them failed -- fixed with a
	-- per-frame table instead, so `ReputationFrame`/`SkillFrame`/
	-- `PetPaperDollFrame` (already hooked successfully) are never
	-- re-hooked, while `HonorFrame` keeps retrying on every subsequent
	-- panel-open until it succeeds.
	--
	-- ONE hook per frame, not two: `PetPaperDollFrame` can fail to hook
	-- with "Attempting to rehook already active hook OnShow." A real bug
	-- in THIS project's own code, unrelated to whose AceHook-3.0 copy
	-- actually runs (LibStub shares ONE global instance per library
	-- name+version across every addon in the session, so a different
	-- addon's vendored copy can end up winning the version race -- a
	-- real, worth-remembering fact about this client's addon ecosystem,
	-- but NOT the cause of this bug) -- AceHook-3.0 refuses a second
	-- `:HookScript`
	-- on the SAME (self, target, script) triple no matter whose copy
	-- handles it, and this file was doing exactly that: the generic loop
	-- below hooked `PetPaperDollFrame`'s OnShow once for
	-- `StyleSubFrameChrome`, then a SEPARATE block hooked the SAME
	-- frame's SAME OnShow a second time for the close/stat/resist extras.
	-- Fixed by merging into a single per-subframe handler that does
	-- everything needed for that frame -- `PetPaperDollFrame` gets its
	-- extras appended right after the shared strip, every other subframe
	-- unchanged.
	subFramesHooked = subFramesHooked or {}
	local j
	for j = 1, table.getn(SUB_FRAMES) do
		local subName = SUB_FRAMES[j]
		if not subFramesHooked[subName] then
			local sub = _G[subName]
			if sub then
				local handler
				if subName == "PetPaperDollFrame" then
					handler = function()
						StyleSubFrameChrome(sub)
						StylePetCloseButton()
						StylePetAttributesFrame()
						StylePetResistFrames()
						StylePetInfoText()
						StylePetDietIcon()
						StylePetExpBar()
						S:StyleModelRotateButtons(PetModelFrameRotateLeftButton, PetModelFrameRotateRightButton)
					end
				else
					handler = function() StyleSubFrameChrome(sub) end
				end
				if S:TryHookScript(sub, "OnShow", handler) then
					subFramesHooked[subName] = true
				else
					E:Print("Skins (character): OnShow hook failed for " .. tostring(subName) .. " (both AceHook and native SetScript fallback)")
				end
			end
		end
	end
end

-- Live quality-colored border -- ported from real ElvUI's own identical
-- hook (Modules/Skins/Blizzard/Character.lua:95-105), adapted to recolor
-- `slot.elvBackdrop` (the backdrop frame `ElvUI.Util.CreateButtonBorder`
-- puts on the slot) rather than the slot itself -- that IS a single
-- backdrop with a single 1px border, exactly what real ElvUI recolors
-- here. 2-arg bare-global-name hooksecurefunc -- the CONFIRMED WORKING
-- variant on this client (the 3-arg object-method overload is the one
-- that never fired during the oUF Castbar icon-capture investigation).
-- `this` here is a real vanilla global, not a declared parameter --
-- matches real ElvUI's own identical reliance on it;
-- PaperDollItemSlotButton_Update is always invoked from a script-handler
-- context that sets it.
-- POLLING, not hooking: hooking `PaperDollItemSlotButton_Update` fails to
-- install, repeating on EVERY panel open, even for the Character/PaperDoll
-- tab specifically -- the ALWAYS-visible default tab, no lazy-load timing
-- excuse available. Confirms the same conclusion as `PollPlusMinusGlyphs`
-- above: `PaperDollItemSlotButton_Update` most likely doesn't exist as a
-- global on this client at all. Uses the same periodic-poll pattern --
-- reads each slot's OWN `:GetID()`
-- (matches the native button's own ID, same value the removed hook read
-- via `this:GetID()`) and looks up its current item quality directly,
-- no hook of any kind needed.
local function PollSlotQuality()
	local i
	for i = 1, table.getn(SLOTS) do
		local slot = _G["Character"..SLOTS[i]]
		if slot and slot.elvBackdrop then
			local okId, id = pcall(slot.GetID, slot)
			if okId and tonumber(id) then
				local r, g, b = 0, 0, 0
				local okTex, textureName = pcall(GetInventoryItemTexture, "player", id)
				if okTex and textureName then
					local okQuality, rarity = pcall(GetInventoryItemQuality, "player", id)
					if okQuality and rarity then
						local okColor, cr, cg, cb = pcall(GetItemQualityColor, rarity)
						if okColor then r, g, b = cr, cg, cb end
					end
				end
				pcall(slot.elvBackdrop.SetBackdropBorderColor, slot.elvBackdrop, r, g, b, 1)
			end
		end
	end
end

local qualityPollStarted = false
local function InstallQualityHook()
	if qualityPollStarted then return end
	qualityPollStarted = true
	E:ScheduleRepeatingTimer(PollSlotQuality, 0.3)
end

-- `S:MakeDraggable` lives in Skins.lua, shared with Friends.lua's own
-- always-draggable header handle for FriendsFrame. Full backstory (why
-- E:CreateMover alone is wrong here, the 60px->24px shrink after a live
-- click-swallowing bug) preserved in Skins.lua's own comment on the
-- hoisted function.

-- Chrome application -- pulled out into its own function and RE-APPLIED
-- on every OnShow, not just once at login: a one-time application at
-- login has zero visible effect once the panel is actually opened --
-- matches this project's own repeated finding elsewhere (ActionBars' native
-- lazily-created frames, Chat's native dock-management resetting tab
-- style) that native code re-asserts certain visual state on
-- show/update, silently undoing a one-time Lua styling pass. Every call
-- here is already idempotent/cheap on repeat (StyleSlot/StyleTab/
-- StyleCloseButton all guard their own one-time work with elv* flags,
-- ElvUI.Util.CreateButtonBorder checks button.elvBackdrop) except
-- S:StripTextures itself, which is naturally idempotent by nature
-- (clearing an already-nil texture is a no-op) -- safe to run on every
-- show without accumulating state or duplicating work.
local function ApplyChrome(frame)
	-- Safe to blanket-strip CharacterFrame's OWN direct regions (unlike a
	-- slot button, nothing on the frame itself is a functional icon --
	-- the character MODEL renders via the separate CharacterModelFrame,
	-- untouched by this).
	S:StripTextures(frame, true)

	-- DisableDrawLayer("ARTWORK") -- ported directly from source/pfUI's
	-- own Character skin (`CharacterFrame:DisableDrawLayer("ARTWORK")`,
	-- skins/blizzard/character.lua:43), a REAL, working-on-vanilla addon:
	-- region-nil'ing alone produces zero visible change here. Fundamentally different
	-- mechanism from SetTexture(nil): this suppresses an entire DRAW
	-- LAYER for the frame as a standing property, not a one-time
	-- per-object mutation -- any texture drawn to that layer, including
	-- ones a native update redraws LATER, stays hidden automatically,
	-- which also sidesteps the "native re-asserts state" problem this
	-- file's own OnShow re-apply was built to work around. Scoped to
	-- CharacterFrame only (matching pfUI's own exact usage) -- NOT
	-- applied blanket to every recursively-stripped sub-frame, since
	-- ARTWORK is also the conventional layer for item-slot icons, and
	-- disabling it there would hide those too.
	pcall(frame.DisableDrawLayer, frame, "ARTWORK")

	-- Background -- a SEPARATE, INSET child frame, not SetBackdrop
	-- directly on CharacterFrame itself: CharacterFrame's own FULL bounds
	-- extend noticeably below the visible dialog art (to cover the tab
	-- row), so a backdrop on the frame itself would overspill past where
	-- the actual "window" reads as ending. Real ElvUI's own Character.lua
	-- never backdrops CharacterFrame directly either -- it creates its
	-- own backdrop child, INSET from the frame's true edges (11px left,
	-- 12px top, 32px right, and specifically 76px up from the BOTTOM --
	-- source/ElvUI-vanilla/ElvUI/Modules/Skins/Blizzard/Character.lua:
	-- 24-26) so the background stops short of the tab strip instead of
	-- covering it. Same insets reused here. EnableMouse(false) so it
	-- never intercepts clicks meant for the slots/tabs/model above it.
	-- Guarded by frame.elvBackground so the repeat-on-OnShow re-apply
	-- doesn't create a new one every time the panel opens.
	if not frame.elvBackground then
		-- Alpha is slightly translucent (matches `S.PANEL_COLOR`,
		-- Skins.lua, shared with every other window), not fully opaque.
		--
		-- Pinned to `CharacterFrame`'s OWN BASE level (S:CreatePanel's
		-- default), i.e. BELOW every child frame in the window, not an
		-- explicit "+N" level: `PetPaperDollFrame`'s own header/footer
		-- FontStrings (PetNameText, PetLevelText, PetLoyaltyText,
		-- PetTrainingPointText/Label) are DIRECT regions of
		-- `PetPaperDollFrame` itself (confirmed via the FrameXML,
		-- PetPaperDollFrame.xml:58-105 -- all on its own BACKGROUND
		-- layer), while `bg` is a sibling of `PetPaperDollFrame` under
		-- `CharacterFrame`. Both would auto-assign the same level
		-- (parent+1), and at equal levels the LATER-created frame draws
		-- on top -- `bg` is created here at runtime, long after the
		-- XML-defined panel, so an uncontrolled level would cover
		-- `PetPaperDollFrame`'s own direct regions while everything one
		-- level deeper (stat numbers, resist numbers, XP bar text, model)
		-- stayed visible. Same class of bug already fixed once in this
		-- file for `ReputationDetailFrame`'s own background (its
		-- checkboxes went invisible for the identical reason). Pinning to
		-- the BASE level -- what a backmost background should always
		-- have been -- avoids it regardless of creation order. Safe now
		-- that CharacterFrame's own regions (chrome + portrait) are
		-- genuinely removed rather than merely covered. (`S:CreatePanel`'s
		-- default behaviour is exactly this: the surface is pinned to its
		-- own parent's base level.)
		S:CreatePanel(frame, 11, -12, -32, 76)
	end

	ApplyPaperDollChrome()

	S:StyleCloseButton(CharacterFrameCloseButton)

	local i
	for i = 1, TAB_COUNT do
		S:StyleTab(_G["CharacterFrameTab"..i])
	end

	for i = 1, table.getn(SLOTS) do
		StyleSlot(SLOTS[i])
	end

	for i = 1, table.getn(RESIST_FRAMES) do
		StyleResistFrame(RESIST_FRAMES[i], i)
	end

	ApplySubFrameChrome()
	InstallQualityHook()

	-- Catch-all pass -- picks up every remaining generic
	-- native widget in this window (UIPanelButtonTemplate buttons, edit
	-- boxes, OptionsCheckButtonTemplate checkboxes, `*ScrollBar` sliders)
	-- WITHOUT anyone having to enumerate it by name. Runs LAST, after
	-- every dedicated styling function above, so anything with a bespoke
	-- recipe is already `elvStyled` and gets skipped here. See
	-- `S:SkinChildren` for why it only touches positively-identified
	-- native templates and never a bare Button.
	S:SkinChildren(frame)
end

local function LoadSkin()
	local frame = CharacterFrame
	if not frame then return end

	-- Movability -- real Blizzard's own CharacterFrame has none. Runs
	-- once, not on every OnShow -- MakeDraggable CreateFrame()s a new
	-- handle each call, so repeating it on every show would leak a new
	-- overlay handle every time the panel opens. SetUserPlaced IS safe to
	-- leave here too (idempotent) -- REQUIRED, not optional --
	-- CharacterFrame is a UIPanelWindows-managed frame, and native
	-- panel-position management silently adds a SECOND conflicting anchor
	-- point on any managed frame that isn't marked user-placed (see the
	-- Chat module's own frame-shrink fix for the same mechanism).
	S:MakeDraggable(frame, CharacterFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyChrome(frame)

	-- S:TryHookScript (AceHook-3.0 first, native :SetScript-chain fallback
	-- if AceHook's own :HasScript validation misfires -- see Skins.lua's
	-- own comment) instead of a bare S:HookScript call -- this is the
	-- single most load-bearing line in the whole file (see the root-cause
	-- note in ApplySubFrameChrome above: an unwrapped HookScript failure
	-- elsewhere in this same call chain once silently prevented this
	-- exact line from ever running at all) -- never let it be the one
	-- unguarded/unfallback-protected call again.
	local ok = S:TryHookScript(frame, "OnShow", function() ApplyChrome(frame) end)
	if not ok then E:Print("Skins (character): CharacterFrame OnShow hook failed to install") end
end

S:AddBlizzardSkin("character", LoadSkin)
