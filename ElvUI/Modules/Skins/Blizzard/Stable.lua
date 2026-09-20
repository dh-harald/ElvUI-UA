-- Skins > Blizzard > Stable -- reskins the native PetStableFrame (Stable
-- Master window, hunter pet swap/storage) in place. Same recipe family as
-- Merchant.lua/Gossip.lua: strip the native chrome, draw an elvBackground
-- child frame (never SetBackdrop the native frame itself).
--
-- Real 1.12.1 structure, per `FrameXML/PetStable.xml`/`.lua`. Not yet
-- verified against the live client.
--
-- - `PetStableFrame` itself carries the usual direct-region chrome:
--   `PetStableFramePortrait` (BACKGROUND), 4 corner textures (BORDER, 2
--   unnamed + 2 named -- `PetStableFrameBottomLeft`/`BottomRight`, all
--   pure decoration, none fed dynamically by native code), and 5 BORDER
--   FontStrings (`PetStableTitleLabel`/`LevelText`/`LoyaltyText`/
--   `SlotText`/`CostLabel`). Unlike `TaxiFrame`, nothing here is
--   functional content, so a plain `S:StripTextures(frame, false)` is
--   safe -- no manual exception-carrying strip needed.
-- - `PetStableFramePortrait` is `S:Kill`'d separately, not left to the
--   strip: same portrait class as `TaxiPortrait`/`GossipFramePortrait` --
--   fed via `SetPortraitTexture` on every `PetStable_Update`, which this
--   project has already found never stays cleared by a plain
--   `SetTexture(nil)`.
-- - The 5 direct FontStrings are promoted to OVERLAY (`PromotePanelText`)
--   so the panel background (parked on the frame's own base level)
--   doesn't draw over them -- same fix as Merchant.lua's own
--   `PromotePanelText`/Taxi.lua's own.
-- - `PetStableModelRotateLeftButton`/`RightButton` are the exact same
--   35x35 Normal/Pushed/Highlight-only shape as `CharacterModelFrame`'s/
--   `PetModelFrame`'s own rotate buttons -- `S:StyleModelRotateButtons`
--   (`Modules/Skins/Skins.lua`), hoisted there from Character.lua once
--   this file became a second consumer.
-- - `PetStablePetInfo` (the happiness-icon frame beside the pet model) is
--   the exact same element as `PetPaperDollPetInfo` on the Character
--   sheet's Pet tab -- `S:StylePetHappinessIcon` (`Modules/Skins/
--   Skins.lua`), hoisted there for the same reason. Passed `PetStableModel`
--   (not `PetModelFrame`, which real ElvUI's own `Blizzard/Stable.lua`
--   uses -- almost certainly a copy-paste leftover from its Character.lua
--   sibling, since `PetModelFrame` belongs to a wholly different window
--   and has no guaranteed relationship to this one's own frame levels).
-- - `PetStableCurrentPet`/`PetStableStabledPet1`/`StabledPet2`
--   (`PetStableSlotTemplate`, a `CheckButton`) are structurally different
--   from the `ItemButtonTemplate` slots `Util.SkinItemButton` was built
--   for: an extra NAMED `$parentBackground` (`UI-EmptySlot`, 64x64,
--   overhanging the 37x37 button) draws a decorative "empty slot" ring
--   that template doesn't have. Killed here explicitly (`Util.
--   SkinItemButton` itself is unaware of it), then `Util.SkinItemButton`
--   handles the icon crop/reposition and border exactly as it does for
--   Merchant/Bags slots. `S:SkinChildren`'s own `CheckButton` branch
--   fingerprints checkbox art specifically (`UICheckButtonTemplate`/
--   `OptionsCheckButtonTemplate`) and won't match this template's
--   `UI-Quickslot2` art, so the end-of-pass sweep leaves these three
--   alone rather than double-styling them as checkboxes.
-- - Native `PetStable_Update` also vertex-colors `$parentBackground`
--   red/white to signal a not-yet-purchased (locked) slot. Lost along
--   with killing that region -- accepted, since the native `:Disable()`
--   the same code calls on a locked slot still carries the signal.
-- - `PetStablePurchaseButton` is a plain `UIPanelButtonTemplate` button;
--   `PetStableFrameCloseButton` inherits `UIPanelCloseButton`, same as
--   every other window in this family.
--
-- SCOPE: outer chrome, panel background, drag handle, close button, model
-- rotate buttons, happiness icon, purchase button, all 3 pet slots.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's own numbers for this window (`Blizzard/Stable.lua`,
-- `source/ElvUI-vanilla`) -- pure padding choices against the real 1.12.1
-- FrameXML geometry (384x512), which this window doesn't customise
-- server-side. Close to the native `<HitRectInsets>` (right=34, bottom=75)
-- already declared on the frame, same "tabs/margin already drawn the
-- boundary" shape as Merchant's own panel.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -11, -32, 71

local PANEL_TEXTS = {
	"PetStableTitleLabel",
	"PetStableLevelText",
	"PetStableLoyaltyText",
	"PetStableSlotText",
	"PetStableCostLabel",
}

local function PromotePanelText()
	local i
	for i = 1, table.getn(PANEL_TEXTS) do
		local fs = _G[PANEL_TEXTS[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end
end

local SLOT_NAMES = { "PetStableCurrentPet", "PetStableStabledPet1", "PetStableStabledPet2" }

local function StyleStableSlot(name)
	local slot = _G[name]
	if not slot then return end

	local bg = _G[name.."Background"]
	if bg then
		pcall(bg.SetTexture, bg, nil)
		pcall(bg.Hide, bg)
		bg.Show = E.noop
	end

	if ElvUI.Util and ElvUI.Util.SkinItemButton then
		ElvUI.Util.SkinItemButton(slot)
	end

	-- Matches real ElvUI's own explicit promotion here; the icon sits on
	-- the BORDER layer per the XML (`$parentIconTexture`).
	local icon = _G[name.."IconTexture"]
	if icon then pcall(icon.SetDrawLayer, icon, "OVERLAY") end
end

local function ApplyStableChrome(frame)
	S:StripTextures(frame, false)
	S:Kill(_G.PetStableFramePortrait)

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	PromotePanelText()

	S:StyleModelRotateButtons(_G.PetStableModelRotateLeftButton, _G.PetStableModelRotateRightButton)
	S:StylePetHappinessIcon(_G.PetStablePetInfo, _G.PetStableModel)

	local i
	for i = 1, table.getn(SLOT_NAMES) do
		StyleStableSlot(SLOT_NAMES[i])
	end

	S:StyleUIPanelButton(_G.PetStablePurchaseButton)

	S:StyleCloseButton(_G.PetStableFrameCloseButton)
	-- Native anchor (`TOPRIGHT -29,-8`) sits slightly outside this panel's
	-- own corner (PANEL_RIGHT,PANEL_TOP = -32,-11) -- same class of gap
	-- already fixed on Merchant/Gossip/Taxi's identically-anchored close
	-- buttons.
	local close = _G.PetStableFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all -- picks up anything this server adds beyond vanilla.
	S:SkinChildren(frame)
end

local stableSkinApplied = false
local function ApplyStableSkin()
	if stableSkinApplied then return end
	local frame = _G.PetStableFrame
	if not frame then return end
	stableSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere, same gap as
	-- every other window in this family.
	local handle = S:MakeDraggable(frame)
	if handle then
		pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT, 0)
	end
	pcall(frame.SetUserPlaced, frame, true)

	ApplyStableChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyStableChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyStableSkin()
end

S:AddBlizzardSkin("stable", LoadSkin)
