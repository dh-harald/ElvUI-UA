-- Skins > Blizzard > Inspect -- reskins the native InspectFrame (target
-- unit's paperdoll/honor window) in place. Same recipe family as
-- Character.lua, which this file leans on heavily: `InspectFrame` and
-- `CharacterFrame` are both `UIPanelWindows`-managed, both host their real
-- content on same-size `setAllPoints="true"` sub-frames switched by the
-- native tab system independently of the outer frame's own OnShow, and
-- `InspectPaperDollFrame`/`InspectHonorFrame` are structurally the exact
-- same templates `PaperDollFrame`/`HonorFrame` already use (confirmed via
-- `AddOns/Blizzard_InspectUI/InspectPaperDollFrame.xml`/
-- `InspectHonorFrame.xml` against `FrameXML/PaperDollFrame.xml`/
-- `HonorFrame.xml`).
--
-- **`## LoadOnDemand: 1`** (`Blizzard_InspectUI.toc`) -- same family as
-- Macro/Binding/Talent/TradeSkill: `S:WaitForGlobal` owns the wait, no
-- bespoke timer.
--
-- Not yet verified against the live client.
--
-- - `InspectFrame` itself carries only one direct region of its own,
--   `InspectFramePortrait` (an ARTWORK Texture) -- no border art lives on
--   the outer frame the way it does on most other skinned windows; the
--   visible "window" chrome (4 quadrant textures per tab) lives entirely on
--   `InspectPaperDollFrame`/`InspectHonorFrame`, both `setAllPoints="true"`
--   to `InspectFrame` and therefore full-size siblings, not nested content.
--   `S:Kill`'d rather than left to the strip -- same portrait class as
--   `CharacterFramePortrait`, fed via `SetPortraitTexture` on every
--   `PLAYER_TARGET_CHANGED`/OnShow.
-- - `movable="true"` in the XML but no drag script anywhere in
--   `Blizzard_InspectUI.lua` (confirmed) -- same gap as every other window
--   in this family. `S:MakeDraggable` + `SetUserPlaced(true)` (required for
--   any `UIPanelWindows`-managed frame moved outside `/moveui`, per
--   Character.lua's own established fix).
-- - `InspectFrameTab1`/`Tab2` inherit `CharacterFrameTabButtonTemplate` --
--   `S:StyleTab`, same family as Character/Friends/Merchant/SpellBook/
--   Talent.
-- - Background inset ported directly from real ElvUI's own
--   `Modules/Skins/Blizzard/Inspect.lua` (`E:Point(backdrop, "TOPLEFT", 10,
--   -12)` / `E:Point(backdrop, "BOTTOMRIGHT", -31, 75)`) -- a real,
--   already-tuned reference for this exact frame, not a guess.
-- - 19 equipment slots (`InspectHeadSlot`..`InspectRangedSlot`, no ammo
--   slot -- confirmed via the XML, unlike Character's own 20-slot list)
--   use `Util.SkinItemButton` (`Core/Util.lua`) directly rather than a
--   private copy of Character.lua's `StyleSlot`: both target the exact
--   same `ItemButtonTemplate`-family shape (icon + native NormalTexture
--   border), and `Util.SkinItemButton` is the shared, already-proven
--   recipe Merchant.lua/Bags.lua also use.
-- - Quality-color border, same POLLING approach as Character.lua's own
--   `PollSlotQuality` and for the identical reason: hooking
--   `InspectPaperDollItemSlotButton_Update` cannot be assumed to fire on
--   this client (`PaperDollItemSlotButton_Update`, the structurally
--   identical Character-sheet hook, is confirmed NOT to exist as a
--   callable global here). Reads `InspectFrame.unit` (the currently
--   inspected unit) rather than `"player"`, and does nothing while that
--   field is nil (no active inspect target -- e.g. the window closed but
--   the timer is still ticking).
-- - Model rotate buttons (`InspectModelRotateLeftButton`/`RightButton`) use
--   the shared `S:StyleModelRotateButtons` (`Modules/Skins/Skins.lua`),
--   same native 35x35 Normal/Pushed/Highlight-only shape as Character's/
--   Stable's own.
-- - **Honor tab content deliberately left alone**, matching Character.lua's
--   own identical scope cut for `HonorFrame` (see that file's own
--   `S.stripSkipNames["HonorFrame"]` registration): the HK/DK/rank/
--   contribution buttons are read-only stat readouts with no native chrome
--   of their own to strip, and the sweep must not descend into them. Both
--   the recursive-strip skip (`stripSkipNames`) and the sweep skip
--   (`autoSkinSkipNames`) are registered for `InspectHonorFrame` for the
--   same reason. What DOES apply: `InspectFrame`'s own panel/tabs, plus a
--   dedicated non-recursive strip of `InspectHonorFrame`'s own 8 direct
--   quadrant/PvP-icon regions (its outer chrome only, matching real
--   ElvUI's own unconditional `E:StripTextures(InspectHonorFrame)`) and a
--   `S:StyleStatusBar` pass on `InspectHonorFrameProgressBar`.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- See this file's own header note on the Honor-tab scope cut.
S.stripSkipNames["InspectHonorFrame"] = true
S.autoSkinSkipNames["InspectHonorFrame"] = true

local SLOTS = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
	"ShirtSlot", "TabardSlot", "WristSlot",
	"HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
	"Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
	"MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

local TAB_COUNT = 2

-- POLLING, not hooking -- see this file's own header note.
local function PollSlotQuality()
	local unit = InspectFrame and InspectFrame.unit
	if not unit then return end

	local i
	for i = 1, table.getn(SLOTS) do
		local slot = _G["Inspect"..SLOTS[i]]
		if slot and slot.elvBackdrop then
			local okId, id = pcall(slot.GetID, slot)
			if okId and tonumber(id) then
				local r, g, b = 0, 0, 0
				local okTex, textureName = pcall(GetInventoryItemTexture, unit, id)
				if okTex and textureName then
					local okQuality, rarity = pcall(GetInventoryItemQuality, unit, id)
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

local paperDollHooked = false
local function ApplyPaperDollChrome()
	local frame = InspectPaperDollFrame
	if not frame then return end

	-- Non-recursive would already be enough (the quadrant art + level/title/
	-- guild FontStrings are all direct regions per the XML), but recursive
	-- costs nothing here -- everything one level down is either a Button
	-- (the 19 slots, the 2 rotate buttons -- both exempt from the walk) or
	-- `InspectModelFrame` (a PlayerModel with no Texture regions of its own).
	S:StripTextures(frame, true)

	S:StyleModelRotateButtons(InspectModelRotateLeftButton, InspectModelRotateRightButton)

	local i
	for i = 1, table.getn(SLOTS) do
		local slot = _G["Inspect"..SLOTS[i]]
		if slot and ElvUI.Util and ElvUI.Util.SkinItemButton then
			ElvUI.Util.SkinItemButton(slot)
		end
	end

	InstallQualityHook()

	if not paperDollHooked then
		if S:TryHookScript(frame, "OnShow", ApplyPaperDollChrome) then
			paperDollHooked = true
		end
	end
end

local honorHooked = false
local function ApplyHonorChrome()
	local frame = InspectHonorFrame
	if not frame then return end

	-- Non-recursive: strips this frame's OWN 8 quadrant/PvP-icon regions
	-- only, matching real ElvUI's own identical unconditional
	-- `E:StripTextures(InspectHonorFrame)` -- the HK/DK/rank/contribution
	-- readouts one level down are untouched, per this file's own
	-- Honor-tab scope-cut note above.
	S:StripTextures(frame, false)

	S:StyleStatusBar(InspectHonorFrameProgressBar)

	if not honorHooked then
		if S:TryHookScript(frame, "OnShow", ApplyHonorChrome) then
			honorHooked = true
		end
	end
end

local function ApplyChrome(frame)
	-- Safe to blanket-strip InspectFrame's own direct regions: its only
	-- one is the portrait, killed separately below. `stripSkipNames`
	-- above keeps this recursive walk out of `InspectHonorFrame`'s own
	-- content (it would otherwise descend into the HK/DK/contribution/
	-- rank Frames -- none of them Button-type -- and blank whatever they
	-- carry).
	S:StripTextures(frame, true)

	S:Kill(InspectFramePortrait)

	if not frame.elvBackground then
		S:CreatePanel(frame, 10, -12, -31, 75)
	end

	ApplyPaperDollChrome()
	ApplyHonorChrome()

	S:StyleCloseButton(InspectFrameCloseButton)

	local i
	for i = 1, TAB_COUNT do
		S:StyleTab(_G["InspectFrameTab"..i])
	end

	-- Catch-all -- picks up anything this server adds beyond vanilla.
	-- `autoSkinSkipNames["InspectHonorFrame"]` above keeps it out of the
	-- Honor tab's own content.
	S:SkinChildren(frame)
end

local inspectSkinApplied = false
local function ApplyInspectSkin()
	if inspectSkinApplied then return end
	local frame = InspectFrame
	if not frame then return end
	inspectSkinApplied = true

	S:MakeDraggable(frame, InspectFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	S:WaitForGlobal("InspectFrame", ApplyInspectSkin)
end

S:AddBlizzardSkin("inspect", LoadSkin)
