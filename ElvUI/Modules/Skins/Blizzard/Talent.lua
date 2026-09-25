-- Skins > Blizzard > Talent -- reskins the native talent tree window in
-- place. Same recipe family as Merchant.lua/Stable.lua: strip the native
-- chrome, draw an elvBackground child frame (never SetBackdrop the native
-- frame itself), leave the functional tree content (branch lines, arrows,
-- talent icons) alone.
--
-- Real 1.12.1 structure, per `AddOns/Blizzard_TalentUI/
-- Blizzard_TalentUI.xml`/`.lua`/`Templates.xml`. Not yet verified against
-- the live client.
--
-- - **`## LoadOnDemand: 1`** (`Blizzard_TalentUI.toc`) -- same family as
--   Macro/Binding: `S:WaitForGlobal` owns the wait, no bespoke timer.
-- - **The window's own global name is NOT assumed to be `TalentFrame`.**
--   Real vanilla 1.12.1 names it `TalentFrame`; the later (TBC+) shape is
--   `PlayerTalentFrame`, structurally identical (same child SUFFIXES, just
--   a different prefix) -- confirmed by TWO independent, already-working
--   references handling exactly this split: pfUI's own
--   `skins/blizzard/talents.lua` (`if PlayerTalentFrame then ... else
--   ... end`, a real addon shipped for "vanilla:tbc") and `
--   UnrealUI/modules/talents.lua`'s own `ResolveFrame()` (`G("PlayerTalentFrame")
--   or G("TalentFrame")`, flagged there as unverified "WORKING_SOURCE
--   evidence, not a runtime measurement"). Since both branches are
--   structurally interchangeable via a resolved name prefix, this file
--   resolves the frame the same way instead of gambling on either name --
--   no probe needed, both cases are covered by the same code path.
--   Real ElvUI's own `Blizzard/Talent.lua` hardcodes `TalentFrame` only
--   (it captures a `PlayerTalentFrame` local but never uses it) -- a
--   vanilla-only port doesn't need the branch; this project's dual-client
--   scope does.
-- - `TalentFramePortrait` is `S:Kill`'d, not left to the strip: same
--   portrait class as every other native-NPC-ish window in this
--   project -- fed via `SetPortraitTexture` on every panel refresh.
-- - `TalentFrameBackgroundTopLeft/TopRight/BottomLeft/BottomRight` ARE
--   dynamically re-`SetTexture`'d per selected tab (`Blizzard_TalentUI.lua`
--   picks the tree-themed parchment art from `GetTalentTabInfo`'s own
--   `background` field) -- unlike `TaxiFrame`'s `TaxiMap`, this is still
--   safe to blanket-strip: it's decorative per-tree wallpaper, not
--   information, and real ElvUI's own reference strips it too (a plain
--   `E:StripTextures(TalentFrame)`, no exception carved out for these 4
--   names) -- the dark panel replaces it outright, matching the
--   established aesthetic everywhere else in this project.
-- - `TalentFrameCancelButton` ("Close" button, functionally identical to
--   the X close button) is `S:Kill`'d outright, not skinned -- matches
--   BOTH real ElvUI (`E:Kill(TalentFrameCancelButton)`) and pfUI
--   (`:Hide()`), independently agreeing it's redundant chrome.
-- - `TalentFrameTitleText`/`SpentPoints`/`TalentPointsText`/`TalentPoints`
--   are ALL already native OVERLAY-layer direct regions of `TalentFrame`
--   (confirmed via the FrameXML) -- unlike Merchant/Taxi/Stable's own
--   ARTWORK/BORDER-layer texts, these need NO `SetDrawLayer` promotion to
--   survive the panel. `SpentPoints`/`TalentPointsText` still need
--   REPOSITIONING though: their native anchors point at the
--   `TalentFramePointsLeft/Middle/Right` pill-border textures the strip
--   above removes. Ported real ElvUI's own exact repositions.
-- - `TalentFrameTab1-5` inherit `CharacterFrameTabButtonTemplate` --
--   `S:StyleTab`, same family already handling Character/Friends/
--   Merchant/SpellBook.
-- - `TalentFrameScrollFrame` (`UIPanelScrollFrameTemplate`) is SAFE for
--   `S:CreateField`: its visible content (`TalentFrameScrollChildFrame`,
--   holding the 20 talent buttons, 30 branch-line textures and the
--   30-arrow overlay frame) is a genuine `<ScrollChild>`, not an overlay
--   sibling, which is the case where wrapping a scroll frame in a field
--   is safe. Its own two direct ARTWORK textures
--   (decorative `UI-Character-ScrollBar` end-caps) get a plain
--   non-recursive strip first.
-- - `TalentFrameTalent1-20` (`TalentButtonTemplate`, inherits
--   `ItemButtonTemplate`) carry the exact same extra NAMED
--   `$parentSlot` ring (`UI-EmptySlot-White`, overhanging the button)
--   that `PetStableSlotTemplate` has -- killed by name, as in `Stable.lua`.
--   The icon crop and 1px border are built from the button's own regions
--   instead of `Util.SkinItemButton`'s backdrop frame (see
--   `StyleTalentButton`). `$parentRankBorder`/`$parentRank` (the small
--   rank-count badge in the button's own bottom-right corner) are left
--   completely native, matching real ElvUI (only re-fonts the rank text).
-- - `TalentFrameArrowFrame`/`TalentFrameBranch1-30`/`TalentFrameArrow1-30`
--   (the tree's connector lines and prerequisite arrows) are never
--   touched -- they live nested inside the ScrollChild, well below every
--   strip call in this file, matching how `TaxiRouteMap`'s own dynamic
--   content stayed untouched in `Taxi.lua`.
-- - **No drag handle added.** Unlike Merchant/Gossip/Taxi/Stable, the real
--   XML does NOT declare `movable="true"` on `TalentFrame` at all, and
--   real ElvUI's own reference doesn't add movability here either --
--   this project's own "movable=true but no drag script -> add
--   `S:MakeDraggable`" rule only fires when the native XML actually
--   claims the frame is movable in the first place.
-- - `UIPanelWindows[frameName]` gets the exact override real ElvUI's own
--   `Blizzard/Talent.lua` applies (`pushable = 0` vs vanilla's own
--   default `6`) -- keeps this panel from being shoved aside when another
--   left-docked panel opens alongside it. Keyed off the RESOLVED name,
--   not a hardcoded `"TalentFrame"` string, for the same reason as
--   everything else in this file.
--
-- SCOPE: outer chrome, panel background, close button, cancel-button
-- removal, tabs, scroll frame + scrollbar, all talent buttons.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Fixed by the XML (20 `TalentButtonTemplate` buttons declared once,
-- regardless of how many the player's class/spec actually uses this
-- session) -- matches `MAX_NUM_TALENTS` (`Blizzard_TalentUI.lua`), not
-- read from that global directly since this project has repeatedly found
-- FrameXML-defined globals missing on UA; a fixed local avoids depending
-- on it existing at all.
local TALENT_BUTTON_COUNT = 20
local TAB_COUNT = 5

-- Real ElvUI's own numbers for this window (`Blizzard/Talent.lua`,
-- `ElvUI-vanilla`) -- pure padding choices against the real 1.12.1
-- FrameXML geometry (384x512), which this window doesn't customise
-- server-side.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 13, -12, -31, 76

local frameName

local function ResolveTalentFrame()
	local frame = _G.PlayerTalentFrame or _G.TalentFrame
	if not frame then return nil end
	local ok, name = pcall(frame.GetName, frame)
	if not ok or type(name) ~= "string" or name == "" then return nil end
	frameName = name
	return frame
end

local function Named(suffix)
	if not frameName then return nil end
	return _G[frameName .. suffix]
end

-- The border is built from the button's own regions (`S:CreateIconEdges`),
-- not `Util.SkinItemButton`'s backdrop frame: the talent buttons live inside
-- the scroll child, where on the legacy client a runtime-created frame draws
-- over the button's regions whatever its frame level -- its fill hid every
-- icon and the inner half of the rank badge. The edges sit on BACKGROUND so
-- the rank badge (`$parentRankBorder`/`$parentRank`, native OVERLAY,
-- overhanging the bottom-right corner) stays on top of them, as it does over
-- real ElvUI's button backdrop.
local function StyleTalentButton(index)
	local talent = Named("Talent" .. index)
	if not talent then return end
	local okName, name = pcall(talent.GetName, talent)
	if not okName or not name then return end

	local ring = _G[name .. "Slot"]
	if ring then
		pcall(ring.SetTexture, ring, nil)
		pcall(ring.Hide, ring)
		ring.Show = E.noop
	end

	-- Same pair as `Util.SkinItemButton`: an empty SetNormalTexture alone
	-- leaves the native quickslot art drawing on UA.
	pcall(talent.SetNormalTexture, talent, "")
	local okNormal, normal = pcall(talent.GetNormalTexture, talent)
	if okNormal and normal then
		pcall(normal.SetAlpha, normal, 0)
		pcall(normal.Hide, normal)
	end

	local icon = _G[name .. "IconTexture"]
	if icon then
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", talent, "TOPLEFT", 1, -1)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", talent, "BOTTOMRIGHT", -1, 1)
	end

	S:CreateIconEdges(talent, "BACKGROUND")
end

local function ApplyTalentChrome(frame)
	S:StripTextures(frame, false)
	S:Kill(Named("Portrait"))
	S:Kill(Named("CancelButton"))

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	-- Native anchors point at the pill-border textures the strip above
	-- just removed (`$parentPointsLeft/Middle/Right`) -- real ElvUI's own
	-- exact replacement anchors, straight to the frame itself (not the
	-- panel child), since both numbers are absolute against the window's
	-- own fixed 384x512 size.
	local spent = Named("SpentPoints")
	if spent then
		pcall(spent.ClearAllPoints, spent)
		pcall(spent.SetPoint, spent, "TOP", frame, "TOP", 0, -42)
	end
	local pointsText = Named("TalentPointsText")
	if pointsText then
		pcall(pointsText.ClearAllPoints, pointsText)
		pcall(pointsText.SetPoint, pointsText, "BOTTOMRIGHT", frame, "BOTTOMLEFT", 220, 84)
	end

	S:StyleCloseButton(Named("CloseButton"))
	local close = Named("CloseButton")
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	local i
	for i = 1, TAB_COUNT do
		S:StyleTab(Named("Tab" .. i))
	end

	local scrollFrame = Named("ScrollFrame")
	if scrollFrame then
		S:StripTextures(scrollFrame, false)
		S:CreateField(scrollFrame, -1, 2, 6, -2)
	end
	local scrollBar = Named("ScrollFrameScrollBar")
	if scrollBar then
		S:HandleScrollBar(scrollBar)
		-- `UIPanelScrollBarTemplate` declares a height of 0: the slider gets
		-- its height only from the TOPLEFT/BOTTOMLEFT anchor pair, so both
		-- must be re-set after ClearAllPoints. With one anchor the legacy
		-- client collapses it to 0 -- the bar disappears, and the mouse
		-- wheel (which steps by half the bar's height) stops scrolling.
		pcall(scrollBar.ClearAllPoints, scrollBar)
		pcall(scrollBar.SetPoint, scrollBar, "TOPLEFT", scrollFrame, "TOPRIGHT", 10, -16)
		pcall(scrollBar.SetPoint, scrollBar, "BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 10, 16)
	end

	for i = 1, TALENT_BUTTON_COUNT do
		StyleTalentButton(i)
	end

	-- Catch-all -- picks up anything this server adds beyond vanilla.
	S:SkinChildren(frame)
end

local talentSkinApplied = false
local function ApplyTalentSkin()
	if talentSkinApplied then return end
	local frame = ResolveTalentFrame()
	if not frame then return end
	talentSkinApplied = true

	-- Keeps this panel from being shoved aside when another left-docked
	-- panel (Character, SpellBook, ...) opens alongside it -- matches
	-- real ElvUI's own override of vanilla's default `pushable = 6`.
	pcall(function() UIPanelWindows[frameName] = { area = "left", pushable = 0, whileDead = 1 } end)

	ApplyTalentChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyTalentChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	S:WaitForGlobal("PlayerTalentFrame", ApplyTalentSkin)
	S:WaitForGlobal("TalentFrame", ApplyTalentSkin)
end

S:AddBlizzardSkin("talent", LoadSkin)
