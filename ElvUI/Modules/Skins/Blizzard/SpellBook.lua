-- Skins > Blizzard > SpellBook -- reskins the native SpellBookFrame IN
-- PLACE. Same recipe family as Character.lua/Friends.lua: strip native
-- chrome, elvBackground child frame (never SetBackdrop the native frame
-- itself), S:StyleTab/S:StyleCloseButton/S:StyleSquareIconButton for
-- anything button-shaped. The SPELL ICONS themselves (SpellButton1-12,
-- the 12-per-page grid) use the SAME icon-crop+border recipe already
-- proven in `Modules/ActionBars/ActionBars.lua`'s own `StyleButton` --
-- rebuilt here rather than imported, since ActionBars.lua's version
-- isn't a shared/exported function, matching this project's own "each
-- skin file self-contained, built from proven primitives" convention
-- (Skins.lua's own header comment).
--
-- Real 1.12.1 structure, per `source/wow-ui-source/FrameXML/
-- SpellBookFrame.xml`/`.lua`:
-- - `SpellBookFrameTabButton1-3`: the outer book-type tabs (Spellbook /
--   Pet). ONLY 1 and 2 are ever actually used in real vanilla --
--   `SpellBookFrame_Update` (FrameXML/SpellBookFrame.lua:141-151) always
--   hides all 3 first, then assigns 1=Spell, 2=Pet via
--   `SpellBookFrame_SetTabType` ONLY IF `HasPetSpells()` is true; button 3
--   is never touched at all in this client generation. **Pet tab is
--   genuinely conditional.**
--   NOT the same 6-piece `CharacterFrameTabButtonTemplate` shape -- just
--   plain Normal/Highlight + a per-instance Disabled texture (shows
--   "currently selected", same Blizzard convention as everywhere else in
--   this project). `S:StyleTab` handles the missing pieces already (`S:Kill` is nil-safe
--   for the 6 BACKGROUND globals that don't exist here, and it blanks the
--   DisabledTexture too), it just needs SpellBook's own backdrop insets --
--   which is exactly how real ElvUI does it: its own SpellBook.lua calls
--   `S:HandleTab(tab)` on these very buttons and then overrides the
--   backdrop points.
-- - `SpellBookSkillLineTab1-8`: the PER-CLASS "spell category" side tabs
--   (the side panel that switches between spell categories) -- up to 8,
--   count and icon assigned dynamically by `SpellBookFrame_Update`
--   (`skillLineTab:SetNormalTexture(texture)`), hidden entirely for the
--   Pet book (no skill lines there). Icon is the button's own
--   NormalTexture (empty in the template, populated at runtime) -- same
--   "crop what native sets dynamically" shape as ActionBars' own action
--   icons.
-- - `SpellButton1-12`: the spell grid, ALSO shared between Spell and Pet
--   books (native code just repopulates the same 12 buttons based on
--   `SpellBookFrame.bookType`) -- no separate Pet-specific button set to
--   handle.
-- - `SpellBookPrevPageButton`/`NextPageButton`: plain Up/Down-style arrow
--   buttons (`UI-SpellbookIcon-{Prev,Next}Page-{Up,Down,Disabled}`) --
--   same shape as the scrollbar arrows `S:StyleSquareIconButton` already
--   handles, reused directly (LEFT/RIGHT crops).
--
-- Hooks needed (bare `hooksecurefunc` doesn't exist on UA -- confirmed
-- project-wide -- `S:SecureHook` throughout, matching Friends.lua's own
-- WhoList_Update/GuildStatus_Update precedent):
-- - `SpellButton_UpdateButton` -- spell name/rank TEXT genuinely changes
--   per update (new page, new spell learned), needs live recolor every
--   time, not just once. Reads the implicit global `this` (real vanilla's
--   own scripting convention for this exact function, confirmed via the
--   FrameXML -- `<OnEvent>SpellButton_UpdateButton();</OnEvent>`, no
--   explicit args) -- matches this project's own established "read
--   this/arg1 globals directly" idiom for native calls shaped this way.
-- - `SpellBookFrame_Update` -- drives outer-tab AND skill-line-tab
--   visibility/icons; a skill-line tab or the Pet tab can newly appear
--   WITHOUT `SpellBookFrame`'s own OnShow re-firing (e.g. switching book
--   types, or SPELLS_CHANGED while the window is already open) -- same
--   "subframe content changes independently of outer OnShow" pattern this
--   whole project keeps hitting (Character's subframes, Friends'
--   WhoFrame/GuildFrame). Every individual styling call inside is already
--   idempotent-guarded, so re-running this cheaply is safe.
--
-- Cooldown text on `SpellButton<i>Cooldown` needs NO spellbook-specific
-- code at all -- `Core/Cooldowns.lua` hooks `CooldownFrame_SetTimer`
-- GLOBALLY (confirmed via its own header comment and StanceBar.lua's
-- cross-reference), and native `SpellButton_UpdateButton` already calls
-- that on every button via `CooldownFrame_SetTimer(cooldown, ...)` -- free
-- countdown text, matching every other native Cooldown frame project-wide.
--
-- SCOPE, first pass: outer chrome (strip, elvBackground,
-- close button, title, draggable, mouse-wheel paging), 3 outer tabs,
-- Prev/Next page arrows, 12 spell buttons (icon crop + border, NOT the
-- native background/frame art), 8 skill-line tabs (icon crop + border).
-- UNTESTED -- first pass on a brand-new window.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

local ACCENT_COLOR = S.ACCENT_COLOR

-- Mirrors ActionBars.lua's own `StyleButton` (icon crop 0.08/0.92,
-- SetTexCoord=noop'd so a later native SetTexture doesn't need re-cropping
-- -- TexCoord is independent of which file is loaded, so this only ever
-- needs to run once per button) -- rebuilt here since that function isn't
-- exported/shared, matching this project's "each skin file self-contained"
-- convention. `$parentBackground` (the decorative frame sprite) and
-- `$parentNormalTexture` (the metal quickslot ring) are cleared the same
-- way ActionBars clears its own NormalTexture -- `$parentIconTexture` (the
-- actual spell icon) is the one region kept and cropped.

-- Auto-cast marker geometry. BOTH values live on the module (not as file
-- locals) so `S:TuneAutoCast` below can change them live in-game -- see
-- that function for why this one number is calibrated rather than derived.
--
-- `SPELLBOOK_AUTOCASTABLE_OUTSET` -- how far outside the button the gold
-- corner flares sit, on every side. Real ElvUI uses 16
-- (`E:SetOutside(..., button, 16, 16)`); Blizzard's own fixed 60x60 on a
-- 37x37 button works out to 11.5. Measured live: 16 renders as a 69x69
-- box, slightly too big.
--
-- `SPELLBOOK_AUTOCAST_OUTSET` -- how far outside the button the shine Model
-- sits, in px. **Not a scale**: `SetScale` on this Model is confirmed
-- INERT on UA -- its scale argument has no visible effect, while a px
-- outset on anchors works. `Bagzen`'s own `scale="1.5"` for the same
-- model is not evidence to the contrary: `Bagzen` is not a UA-native
-- addon (it's a port), and this same feature renders too small there
-- too. Scaling being broken/unreliable on UA is a general pattern, not a
-- Model-only quirk -- `SetScale` is a LAST RESORT here, only when no
-- other sizing method exists, and only once proven live.
-- `SetPoint`/`SetAllPoints` on the same Model IS measured to work (the dump
-- showed the native fixed 36x36 become 37x37), so size is set by anchors.
--
-- The working reference is this project's own **PetBar**, live-confirmed
-- ("the autocast glow correctly highlighted with no extra code needed",
-- Modules/ActionBars/PetBar.lua's own header). It does NOTHING to the model
-- -- because `PetActionBarFrame.xml:25` already declares it
-- `setAllPoints="true"` with NO fixed `<Size>`, so it tracks the button for
-- free, even when PetBar resizes that button. SpellBook's declaration is
-- the odd one out (fixed 36x36, no setAllPoints), so it needs in Lua what
-- the pet bar gets from XML.
--
-- **CONFIRMED LIVE, final values: model 6, flares 20** -- these are the
-- current defaults after tuning in-game.
--
-- At flares=13 the enlarged shine would largely COVER the gold corner
-- flares underneath; flares=20 works because it moves the flares out
-- from under the shine, so both markers read at once. General lesson:
-- when two stacked markers collide, push the OUTER one further out --
-- don't accept the occlusion, and don't conclude a covered element's
-- parameter is inert just because it is currently hidden.
S.SPELLBOOK_AUTOCASTABLE_OUTSET = S.SPELLBOOK_AUTOCASTABLE_OUTSET or 20
S.SPELLBOOK_AUTOCAST_OUTSET = S.SPELLBOOK_AUTOCAST_OUTSET or 6

-- Both geometry applications in one place so the one-time styling pass and
-- the live tuner below can't drift apart.
local function ApplyAutoCastGeometry(button, autoCast)
	if not (button and autoCast) then return end
	local outset = S.SPELLBOOK_AUTOCAST_OUTSET
	pcall(autoCast.ClearAllPoints, autoCast)
	pcall(autoCast.SetPoint, autoCast, "TOPLEFT", button, "TOPLEFT", -outset, outset)
	pcall(autoCast.SetPoint, autoCast, "BOTTOMRIGHT", button, "BOTTOMRIGHT", outset, -outset)
end

local function ApplyAutoCastableGeometry(button, autoCastable)
	if not (button and autoCastable) then return end
	local outset = S.SPELLBOOK_AUTOCASTABLE_OUTSET
	pcall(autoCastable.ClearAllPoints, autoCastable)
	pcall(autoCastable.SetPoint, autoCastable, "TOPLEFT", button, "TOPLEFT", -outset, outset)
	pcall(autoCastable.SetPoint, autoCastable, "BOTTOMRIGHT", button, "BOTTOMRIGHT", outset, -outset)
end

-- LIVE TUNER. BOTH arguments are px outsets from the button's own edge --
-- `modelOutset` for the shine Model, `flareOutset` for the gold corner
-- texture:
--
--   /run ElvUI[1]:GetModule("Skins"):TuneAutoCast(6, 20)
--
-- Both go through anchor-based sizing, the one mechanism measured to
-- work on this Model (see the constants above -- `SetScale` is inert
-- here).
--
-- Not a debug leftover to delete: a marker whose correct size is a
-- judgement call needs a way to make that judgement without a
-- build+deploy+relog cycle per guess, and the same will be true the next
-- time one of these appears.
function S:TuneAutoCast(modelOutset, flareOutset)
	if tonumber(modelOutset) then S.SPELLBOOK_AUTOCAST_OUTSET = tonumber(modelOutset) end
	if tonumber(flareOutset) then S.SPELLBOOK_AUTOCASTABLE_OUTSET = tonumber(flareOutset) end

	local i
	for i = 1, 12 do
		local button = _G["SpellButton"..i]
		if button then
			local okName, name = pcall(button.GetName, button)
			if okName and name then
				ApplyAutoCastGeometry(button, _G[name.."AutoCast"])
				ApplyAutoCastableGeometry(button, _G[name.."AutoCastable"])
			end
		end
	end

	E:Print(string.format("Skins: autocast model outset=%d, flare outset=%d",
		S.SPELLBOOK_AUTOCAST_OUTSET, S.SPELLBOOK_AUTOCASTABLE_OUTSET))
end

local function StyleSpellButton(button)
	if not button then return end
	local okName, name = pcall(button.GetName, button)
	if not (okName and name) then return end

	local normalTexture = _G[name.."NormalTexture"]
	local background = _G[name.."Background"]
	local icon = _G[name.."IconTexture"]

	if not button.elvNormalTextureCleared then
		pcall(button.SetNormalTexture, button, "")
		button.SetNormalTexture = E.noop
		button.elvNormalTextureCleared = true
	end
	if normalTexture and normalTexture.SetTexture ~= E.noop then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		normalTexture.SetTexture = E.noop
	end

	if background and not button.elvBackgroundHidden then
		pcall(background.Hide, background)
		background.Show = E.noop
		button.elvBackgroundHidden = true
	end

	ElvUI.Util.CreateButtonBorder(button)

	if icon and not button.elvIconStyled then
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		icon.SetTexCoord = E.noop
		button.elvIconStyled = true
	end

	-- AutoCast model (`$parentAutoCast`, the animated glow indicating a
	-- PET ability's auto-cast is currently ON): the animation can stop
	-- showing after this skin runs.
	-- Suspected cause (untested, but matches this project's own repeated
	-- pattern elsewhere -- the PetPaperDollFrame background z-order fix):
	-- `CreateButtonBorder` forces `button`'s own frame level up to at
	-- least 4 if it was lower; `$parentAutoCast` is a CHILD FRAME (a
	-- Model, not a texture region governed by draw layer), and if its own
	-- level was fixed at native XML-load time rather than live-bound to
	-- the button's, it could now sit BELOW the button/border and render
	-- hidden behind them. Explicitly lifted above the button's own
	-- (possibly just-changed) level, matching the same fix shape already
	-- proven for the dropdown-menu highlight (Skins.lua's own
	-- `S:InstallDropDownMenuSkin`, `backdropLevel + 1`).
	local autoCast = _G[name.."AutoCast"]
	if autoCast and not button.elvAutoCastLevelFixed then
		local okLevel, level = pcall(button.GetFrameLevel, button)
		if okLevel and tonumber(level) then
			pcall(autoCast.SetFrameLevel, autoCast, level + 1)
		end
		button.elvAutoCastLevelFixed = true
	end

	-- ...and its SIZE: the glow model itself needs to scale with the
	-- button, distinct from the static `$parentAutoCastable` flares below.
	--
	-- Evidence, not theory -- the SAME model file is declared in two places
	-- in the real FrameXML, and SpellBook's is the odd one out:
	--   PetActionBarFrame.xml:25  setAllPoints="true", no Size   scale="1.2"
	--   SpellBookFrame.xml:137    NO setAllPoints, FIXED 36x36   scale="1.22"
	-- A hardcoded 36x36 that tracks nothing is exactly the "forgot to scale
	-- it with the button" the report describes -- and the pet bar version is
	-- the one this project already renders CORRECTLY (see
	-- `S.SPELLBOOK_AUTOCAST_OUTSET` above: PetBar does nothing to the model
	-- at all, it just inherits `setAllPoints` from XML). So this gives the
	-- SpellBook model in Lua what the pet bar gets for free.
	--
	-- A third declaration in `Bagzen` (`scale="1.5"`) is NOT UA-specific
	-- evidence -- see the constants above. Ignore it.
	--
	-- Size comes from ANCHORS, never `SetScale`, which is measured inert
	-- on this Model.
	if autoCast and not button.elvAutoCastSized then
		button.elvAutoCastSized = true
		ApplyAutoCastGeometry(button, autoCast)
	end

	-- AutoCastable overlay (`$parentAutoCastable`, the gold corner flares
	-- marking a PET ability that can be / is set to auto-cast): left
	-- untouched, it sits tight against the icon art instead of framing
	-- the button, since it never gets resized along with everything else
	-- this skin changes. The native template gives it a FIXED
	-- `<Size> 60x60` anchored `CENTER`
	-- (source/wow-ui-source/FrameXML/SpellBookFrame.xml:121-133), a number
	-- picked to sit on top of the native 64x64 `$parentBackground` slot art
	-- -- which this skin HIDES. With that art gone the button reads as its
	-- true 37x37 footprint plus our 1px border, and a fixed 60x60 centered
	-- overlay no longer relates to anything on screen.
	--
	-- Real ElvUI's own SpellBook skin does exactly one thing about this and
	-- it is the fix: stop letting the overlay have its own size, anchor it
	-- OUTSIDE the button on all four sides --
	-- `E:SetOutside(_G["SpellButton"..i.."AutoCastable"], button, 16, 16)`
	-- (source/ElvUI-vanilla/ElvUI/Modules/Skins/Blizzard/SpellBook.lua:63).
	-- `E:SetOutside` is just the two-corner anchor pair
	-- (`TOPLEFT -x,+y` / `BOTTOMRIGHT +x,-y`, Core/toolkit.lua:74-86), which
	-- this project already uses everywhere, so it ports 1:1 with no helper
	-- needed. Two anchor points also OVERRIDE the template's `<Size>`, so
	-- the overlay now tracks the button's real footprint whatever it is,
	-- scaling with the button rather than drifting again the next time
	-- the button geometry changes.
	--
	-- One-time: native `SpellButton_UpdateButton` only ever `Show()`s and
	-- `Hide()`s this texture, never re-anchors or resizes it (confirmed,
	-- SpellBookFrame.lua:326-371) -- so unlike the text colors, this does
	-- not need to be re-asserted from that hook.
	local autoCastable = _G[name.."AutoCastable"]
	if autoCastable and not button.elvAutoCastableSized then
		button.elvAutoCastableSized = true
		ApplyAutoCastableGeometry(button, autoCastable)
	end
end

-- Skill-line ("spell category") side tabs -- the decorative BACKGROUND
-- sprite (`SpellBook-SkillLineTab`) is an UNNAMED direct Texture region,
-- with no separate global to grab it by -- and the icon (this button's
-- own NormalTexture, set dynamically by `SpellBookFrame_Update`) is ALSO
-- just a direct Texture region, so a blanket `S:StripTextures(tab, false)`
-- call here would strip BOTH indiscriminately (its first, non-recursive
-- pass clears every direct Texture region of whatever frame it's given,
-- regardless of that frame's own object type -- the Button/CheckButton
-- skip only governs recursion into CHILDREN, not the passed-in frame
-- itself). Caught by code review before any live test: manually walks
-- `tab:GetRegions()` instead, explicitly comparing each Texture region's
-- identity against `tab:GetNormalTexture()` so the icon is the one region
-- spared.
local function StyleSkillLineTab(tab)
	if not tab then return end

	if not tab.elvStripped then
		tab.elvStripped = true
		local okNormal, normalTexture = pcall(tab.GetNormalTexture, tab)
		normalTexture = okNormal and normalTexture or nil

		local ok, regions = pcall(function() return { tab:GetRegions() } end)
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

	ElvUI.Util.CreateButtonBorder(tab)

	if not tab.elvIconStyled then
		local okNormal, normalTexture = pcall(tab.GetNormalTexture, tab)
		if okNormal and normalTexture then
			pcall(normalTexture.SetTexCoord, normalTexture, 0.07, 0.93, 0.07, 0.93)
		end
		tab.elvIconStyled = true
	end
end

-- "Prev"/"Next" labels next to the page arrows -- removed since the
-- arrows are self-explanatory. UNNAMED BACKGROUND-layer FontStrings
-- declared directly on each page button (confirmed in
-- `source/wow-ui-source/FrameXML/SpellBookFrame.xml`), killed by
-- `S:KillButtonLabel` (`Skins.lua` -- hoisted there once Merchant.lua
-- needed the identical recipe for its own page-nav buttons).

local spellButtonUpdateHooked = false
local spellBookUpdateHooked = false

-- Outer book-type tabs ("Spellbook" / "<pet type>"). NOT resized: the
-- native 128x64 button keeps its native geometry, and the shared tab
-- recipe (`S:StyleTab`) draws a smaller visible box via backdrop insets
-- instead -- resizing the BUTTON itself is the wrong tool here:
--
-- 1. **RESIZING THE BUTTON BREAKS CLICKS.**
--    `SpellBookFrameTabButtonTemplate` declares `<HitRectInsets left="15"
--    right="14" top="13" bottom="15"/>` -- absolute pixel insets sized
--    for a 64px-tall button. Shrinking the button to 28px high leaves a
--    clickable rect of 28 - 13 - 15 = **ZERO** height, so neither tab
--    could ever receive a click, even though nothing is wrong with the
--    tabs' own OnClick (`ToggleSpellBook(this.bookType)`) or with
--    `SpellBookFrame_SetTabType`'s Enable/Disable dance.
-- 2. **RESIZING THE BUTTON ALSO LOOKS WRONG.** These tabs need to go
--    through the same `S:StyleTab` recipe as every other window's tabs,
--    not a bespoke one-off, or they read as generic buttons rather than
--    as tabs.
--
-- The fix: keep the BUTTON at its native geometry (so the native hit
-- rect stays valid) and use `S:StyleTab` with real ElvUI's own
-- SpellBook-specific insets -- its `Blizzard/SpellBook.lua` overrides
-- `S:HandleTab`'s default 10/1/3 with `E:Point(tab.backdrop, "TOPLEFT",
-- 14, -17)` / `"BOTTOMRIGHT", -14, 19)` for exactly these tabs. On the
-- native 128x64 footprint that yields a 100x28 visible box, while the
-- native -20 overlap between tab1 and tab2 turns into a clean ~8px gap
-- between the two boxes.
local TAB_INSET_X = 14
local TAB_INSET_TOP = 17
local TAB_INSET_BOTTOM = 19

local function ApplySpellBookUpdate()
	local i
	for i = 1, 3 do
		S:StyleTab(_G["SpellBookFrameTabButton"..i], TAB_INSET_X, TAB_INSET_TOP, TAB_INSET_BOTTOM)
	end
	for i = 1, MAX_SKILLLINE_TABS or 8 do
		StyleSkillLineTab(_G["SpellBookSkillLineTab"..i])
	end
end

local function InstallSpellBookHooks()
	if not spellButtonUpdateHooked then
		local ok, err = pcall(function()
			S:SecureHook("SpellButton_UpdateButton", function()
				local button = _G.this
				if not button then return end
				local okName, name = pcall(button.GetName, button)
				if not (okName and name) then return end

				local spellName = _G[name.."SpellName"]
				local subSpellName = _G[name.."SubSpellName"]
				local highlight = _G[name.."Highlight"]

				if spellName then
					pcall(spellName.SetTextColor, spellName, ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3])
				end
				if subSpellName then
					pcall(subSpellName.SetTextColor, subSpellName, 1, 1, 1)
				end
				if highlight then
					pcall(highlight.SetTexture, highlight, 1, 1, 1, 0.3)
				end
			end)
		end)
		if ok then
			spellButtonUpdateHooked = true
		else
			E:Print("Skins (spellbook): SecureHook(SpellButton_UpdateButton) failed: " .. tostring(err))
		end
	end

	if not spellBookUpdateHooked then
		local ok, err = pcall(function()
			S:SecureHook("SpellBookFrame_Update", ApplySpellBookUpdate)
		end)
		if ok then
			spellBookUpdateHooked = true
		else
			E:Print("Skins (spellbook): SecureHook(SpellBookFrame_Update) failed: " .. tostring(err))
		end
	end
end

local function ApplyChrome(frame)
	S:StripTextures(frame, true)

	S:CreatePanel(frame, 10, -12, -31, 75)

	local title = _G["SpellBookTitleText"]
	if title then
		pcall(title.SetTextColor, title, ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3])
	end
	local pageText = _G["SpellBookPageText"]
	if pageText then
		pcall(pageText.SetTextColor, pageText, 1, 1, 1)
	end

	S:StyleCloseButton(SpellBookCloseButton)

	-- 0.5 icon scale -- these page buttons are a native 32x32, twice the
	-- size of the other `S:StyleSquareIconButton` consumers, so a
	-- full-footprint arrow reads as oversized. Scoped to this call
	-- site rather than changed in the shared helper, so the already-accepted
	-- scrollbar-arrow and Unlearn-button sizes don't move.
	S:StyleSquareIconButton(SpellBookPrevPageButton, "LEFT", 0.5)
	S:StyleSquareIconButton(SpellBookNextPageButton, "RIGHT", 0.5)
	S:KillButtonLabel(SpellBookPrevPageButton)
	S:KillButtonLabel(SpellBookNextPageButton)

	local i
	for i = 1, 12 do
		StyleSpellButton(_G["SpellButton"..i])
	end

	ApplySpellBookUpdate()
	InstallSpellBookHooks()

	-- Mouse-wheel paging -- matches real ElvUI's own reference exactly
	-- (source/ElvUI-vanilla/ElvUI/Modules/Skins/Blizzard/SpellBook.lua) --
	-- a pure behavior addition (not chrome), low risk, only pages the
	-- SPELL book (native `SpellBookFrame.bookType` check), never touches
	-- the Pet book's own paging.
	if not frame.elvMouseWheel then
		pcall(frame.EnableMouseWheel, frame, true)
		pcall(frame.SetScript, frame, "OnMouseWheel", function()
			if SpellBookFrame.bookType ~= BOOKTYPE_SPELL then return end
			local okPage, currentPage, maxPages = pcall(SpellBook_GetCurrentPage)
			if not okPage then return end
			if arg1 > 0 then
				if currentPage > 1 then pcall(PrevPageButton_OnClick) end
			else
				if currentPage < maxPages then pcall(NextPageButton_OnClick) end
			end
		end)
		frame.elvMouseWheel = true
	end

	-- Catch-all pass -- see `S:SkinChildren` (Skins.lua).
	-- Runs LAST, after every dedicated function above, so the spell
	-- buttons/skill-line tabs/page arrows keep their own recipes and only
	-- the generic leftovers are picked up here.
	S:SkinChildren(frame)
end

local function LoadSkin()
	local frame = SpellBookFrame
	if not frame then return end

	-- Movability -- real Blizzard's own SpellBookFrame has none, same gap
	-- Character.lua/Friends.lua already found and fixed for their own
	-- windows. SetUserPlaced applied proactively for the same
	-- UIPanelWindows-managed-frame reason established there.
	S:MakeDraggable(frame, SpellBookCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyChrome(frame) end)
	if not ok then E:Print("Skins (spellbook): SpellBookFrame OnShow hook failed to install") end
end

S:AddBlizzardSkin("spellbook", LoadSkin)
