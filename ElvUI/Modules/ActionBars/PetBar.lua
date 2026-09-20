-- PetBar module.
--
-- Re-skins native PetActionButton1..10 in place, same approach as
-- Modules/ActionBars.lua (secure/protected buttons -- template the
-- EXISTING globals, never create new ones; reparent onto a new plain
-- container). See ActionBars.lua's own header comment for the full
-- reasoning (secure reparenting confirmed safe via the Bagzen addon,
-- which relies on the identical technique) -- not repeated here.
-- `PetActionBarFrame` (the native container) is already in
-- ActionBars.lua's own `CHROME_TO_HIDE` list, so its buttons are already
-- hidden along with it UNLESS reparented out -- this module does exactly
-- that, the same way bars 2-5 escape their own native MultiBar
-- containers.
--
-- Data lives under `P.actionbar.barPet` / `E.db.actionbar.barPet`, NOT a
-- separate top-level `petbar` table: this nests Pet Bar under ActionBars
-- in the config sidebar, and matches real ElvUI's own source, which
-- nests the DATA the same way, not just the config UI (
-- ElvUI-vanilla/ElvUI_Config/ActionBars.lua reads/writes
-- `E.db.actionbar.barPet[...]` directly, and `enabled` there is a live
-- PROFILE field, not a private reload-required one -- matching this
-- module's own `barN.enabled` convention already established for bars
-- 1-5, not the module-wide `E.private.actionbar.enable` master switch).
-- This lets Pet Bar be toggled on/off live, matching real ElvUI's
-- `AB:PositionAndSizeBarPet` (scale-to-0 trick when disabled) rather than
-- only-checked-at-login.
--
-- Real ElvUI's own module (ElvUI-vanilla/ElvUI/Modules/
-- ActionBars/BarPet.lua) hooks Blizzard's pet-action state (icon
-- texture, checked/autocast state) via its own `AB:UpdatePet()`, fired on
-- UNIT_PET/UNIT_FLAGS/UNIT_AURA/PET_BAR_UPDATE(_COOLDOWN)/
-- PET_BAR_UPDATE_USABLE. This module does NOT reimplement that: pet
-- action buttons update their own icon/checked/autocast-glow state via
-- Blizzard's native PetActionButton_* script handlers regardless of what
-- addon code does, since this module never touches those handlers or
-- unregisters their events -- only cosmetic re-skinning (border/texture/
-- backdrop/position) needs our own code, matching ActionBars.lua. The
-- autocast glow renders correctly with no extra code needed.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local Compat = ElvUI.Compat
local M = E:NewModule("PetBar", "AceEvent-3.0")
E.PetBar = M

local NUM_PET_ACTION_SLOTS = _G.NUM_PET_ACTION_SLOTS or 10
local PREFIX = "PetActionButton"

-- Settings: `P.actionbar.barPet` (Settings/Profile.lua). Its default
-- `buttonsPerRow = 1` means a single VERTICAL column -- this project's
-- buttonsPerRow=1 row-inversion handling, already needed for a vertical
-- ActionBars bar, applies here unchanged.

-- Re-skins one native pet action button in place. Trimmed version of
-- ActionBars.lua's own StyleButton() -- no hotkey/macro text (pet
-- buttons don't have keybind/macro FontStrings the way regular action
-- buttons do). Empty-slot visibility is handled separately, at the BAR
-- level, by ApplyShowGrid() below -- native pet slots use their own
-- counter-based PetActionBar_ShowGrid()/PetActionBar_HideGrid() pair
-- (wow-ui-source/FrameXML/PetActionBarFrame.lua), not the
-- per-button ActionButton_ShowGrid() regular action buttons use.

-- The pet button's grey, bevelled Blizzard frame (UI-Quickslot2, larger than
-- the button, so it overlaps the neighbours) is the $parentNormalTexture2
-- region of PetActionButtonTemplate, not $parentNormalTexture. SetAlpha(0)
-- hides it on Unreal Azeroth. Also called after every PetActionBar_Update.
local function HideQuickslotFrame(button)
	local frame = button and _G[button:GetName().."NormalTexture2"]
	if frame then pcall(frame.SetAlpha, frame, 0) end
end

local function StyleButton(button)
	if not button then return end

	local name = button:GetName()
	local icon = _G[name.."Icon"]
	local normalTexture = _G[name.."NormalTexture"]

	-- Same fix as ActionBars.lua's own NormalTexture handling: SetTexture
	-- with an empty string doesn't clear it on UA, SetTexture(nil) on the
	-- region directly does. Guarded so the periodic resweep below doesn't
	-- keep re-touching an already-cleared region (same flicker bug
	-- already found and fixed there).
	if not button.elvNormalTextureCleared then
		pcall(button.SetNormalTexture, button, "")
		button.SetNormalTexture = E.noop
		button.elvNormalTextureCleared = true
	end
	if normalTexture and normalTexture.SetTexture ~= E.noop then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		normalTexture.SetTexture = E.noop
	end
	HideQuickslotFrame(button)

	if icon and not button.elvIconStyled then
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		icon.SetTexCoord = E.noop
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		button.elvIconStyled = true
	end

	-- Same border as Modules/ActionBars.lua's own buttons -- shared via
	-- ElvUI.Util.CreateButtonBorder (Core/Util.lua), so pet bar buttons
	-- get the same treatment ActionBars' own go through instead of a
	-- simpler flat backdrop with no border differentiation.
	--
	-- Util.CreateButtonHoverTextures deliberately NOT called here (also
	-- unused in ActionBars.lua) -- prime suspect for a gold/tan tint that
	-- appears on EVERY button on UA, including these pet buttons, once
	-- it's used -- see ActionBars.lua's own StyleButton comment for the
	-- full reasoning (the pushed texture's color, {0.9, 0.8, 0.1, 0.3},
	-- is a literal gold/yellow tone).
	ElvUI.Util.CreateButtonBorder(button)
	ElvUI.Util.RaiseCooldown(button)
end

function M:CreateBar()
	local ok, bar = pcall(CreateFrame, "Frame", "ElvUIPetBarHolder", UIParent)
	if not ok or not bar then return nil end

	-- First-run-only starting position -- one row above bar5's own
	-- default (DEFAULT_Y_OFFSET[5] in ActionBars.lua, default bar height
	-- ~38px + ROW_GAP), stacked above bar5 the same way bar2-5 stack
	-- above bar1. E:CreateMover below captures this as its reset default,
	-- then owns the bar's actual position from here on.
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 204)
	E:CreateMover(bar, "ElvBar_Pet", L["Pet Bar"])

	pcall(bar.SetBackdrop, bar, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(bar.SetBackdropColor, bar, 0.1, 0.1, 0.1, 1)
	pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 1)

	bar.buttons = {}
	local i
	for i = 1, NUM_PET_ACTION_SLOTS do
		local button = _G[PREFIX..i]
		if button then
			pcall(button.SetParent, button, bar)
			bar.buttons[i] = button
			StyleButton(button)
		end
	end

	return bar
end

-- Sizes/lays out the bar and its buttons. Also handles live enable/
-- disable (matches real ElvUI's own AB:PositionAndSizeBarPet -- scale-
-- to-0 rather than skipping creation, since `enabled` is now a live
-- profile field, not a private reload-required one).
function M:PositionBar()
	local bar = self.bar
	if not bar then return end
	local settings = E.db.actionbar.barPet

	if not settings.enabled then
		pcall(bar.SetScale, bar, 0.000001)
		pcall(bar.SetAlpha, bar, 0)
		return
	end
	pcall(bar.SetScale, bar, 1)

	local size = settings.buttonsize
	local spacing = settings.buttonspacing
	local perRow = math.max(settings.buttonsPerRow or NUM_PET_ACTION_SLOTS, 1)
	local buttonCount = math.min(settings.buttons or NUM_PET_ACTION_SLOTS, NUM_PET_ACTION_SLOTS)
	local rows = math.ceil(buttonCount / perRow)
	local cols = math.min(buttonCount, perRow)
	-- Matches real ElvUI's own per-bar padding formula, same as
	-- Modules/ActionBars.lua's own PositionOneBar -- see
	-- ElvUI.Util.BarPadding (Core/Util.lua) for the full rationale.
	local padding = ElvUI.Util.BarPadding(settings)

	local barWidth = (size * cols) + (spacing * (cols - 1)) + (padding * 2)
	local barHeight = (size * rows) + (spacing * (rows - 1)) + (padding * 2)

	bar:SetWidth(barWidth)
	bar:SetHeight(barHeight)
	pcall(bar.SetAlpha, bar, settings.alpha or 1)
	if not settings.backdrop then
		pcall(bar.SetBackdropColor, bar, 0, 0, 0, 0)
		pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 0)
	else
		pcall(bar.SetBackdropColor, bar, 0.1, 0.1, 0.1, 1)
		pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 1)
	end

	local i
	for i = 1, NUM_PET_ACTION_SLOTS do
		local button = bar.buttons[i]
		if button then
			local row = math.floor((i - 1) / perRow)
			local col = Compat.mod(i - 1, perRow)
			-- Same top-to-bottom reading-order fix as ActionBars.lua's
			-- own PositionOneBar (row 0 = highest Y otherwise).
			local visualRow = rows - 1 - row

			pcall(button.SetWidth, button, size)
			pcall(button.SetHeight, button, size)
			button:ClearAllPoints()
			pcall(button.SetPoint, button, "BOTTOMLEFT", bar, "BOTTOMLEFT",
				padding + col * (size + spacing), padding + visualRow * (size + spacing))

			if i > buttonCount then
				pcall(button.SetScale, button, 0.000001)
				pcall(button.SetAlpha, button, 0)
			else
				pcall(button.SetScale, button, 1)
				pcall(button.SetAlpha, button, 1)
			end
		end
	end
end

-- A thin white/gold border appears on `PetActionBarFrame` specifically
-- during combat, pet-attack-related. The culprit: `SlidingActionBarTexture0`/
-- `1`, two native Texture regions directly on `PetActionBarFrame`
-- (identified via UnrealUI/modules/petbar.lua, which solves the
-- identical client element). Critically, the hide must be re-applied on
-- EVERY UNIT_PET/PET_BAR_UPDATE/PLAYER_ENTERING_WORLD event, not just
-- once at login: PET_BAR_UPDATE fires when the pet attacks, and native
-- code re-asserts these textures' visible state at that exact moment, so
-- a one-time Hide() from login has no chance against it. Deliberately
-- NOT overriding Show permanently (unlike this project's usual S:Kill/
-- E.noop recipe) -- matches UnrealUI's own proven `U.HideRegion` exactly
-- (SetTexture(nil) + SetAlpha(0) + Hide(), re-invoked, no override).
local function HideSlidingBorder()
	local i
	for i = 0, 1 do
		local region = _G["SlidingActionBarTexture"..i]
		if region then
			local okType, objType = pcall(region.GetObjectType, region)
			if okType and objType == "Texture" then
				pcall(region.SetTexture, region, nil)
				pcall(region.SetAlpha, region, 0)
				pcall(region.Hide, region)
			end
		end
	end
end

-- `PetActionBar_ShowGrid`/`PetActionBar_HideGrid` are COUNTER-based on the
-- real client (PetActionBarFrame.showgrid increments/decrements, only
-- actually hides empty slots once it reaches 0) -- calling ShowGrid
-- repeatedly without a matching HideGrid would leave the counter
-- climbing forever, and toggling the config off would then need that
-- many HideGrid calls to ever take effect. `gridApplied` tracks OUR last
-- vote so a call only fires on an actual state change (config toggle,
-- or first run), never redundantly from a periodic resweep.
local gridApplied = nil

local function ApplyShowGrid()
	local want = E.db.actionbar.barPet.showGrid
	if want == gridApplied then return end
	if want then
		pcall(_G.PetActionBar_ShowGrid)
	else
		pcall(_G.PetActionBar_HideGrid)
	end
	gridApplied = want
end

local function UpdateVisibility()
	local bar = M.bar
	if not bar then return end
	local settings = E.db.actionbar.barPet
	if settings.enabled and _G.PetHasActionBar and _G.PetHasActionBar() then
		pcall(bar.Show, bar)
	else
		pcall(bar.Hide, bar)
	end
end

-- Checked-state refresh (Aggressive/Defensive/Passive stance,
-- Follow/Stay behavior -- slots 2/3/8/9/10, "isActive" per
-- UnrealAzeroth_LuaAPI/en/globals/Pet.md's own documented
-- GetPetActionInfo return shape: `name, subtext, texture, isToken,
-- isActive, autoCastAllowed, autoCastEnabled`).
--
-- This module's header comment above claims icon/checked/autocast state
-- all update via Blizzard's native PetActionButton_* handlers with zero
-- extra code needed -- true, but only for AUTOCAST GLOW specifically (a
-- continuously-redrawn animation, driven every frame regardless of
-- events, same as the cooldown swipe: Blizzard's own cooldown-swipe
-- logic keeps running regardless of reparenting). Checked state is
-- different -- a discrete, EVENT-triggered change (only updates when you
-- click), and event-driven refreshes are unreliable on UA after
-- reparenting (UnregisterEvent, native OnEvent handlers not always firing
-- where expected). Rather than chase whether the native handler itself is
-- firing, this explicitly re-asserts the checked state ourselves --
-- matches this project's own established preference (Cooldowns.lua,
-- UnitFrames.lua) for a periodic re-check over trusting event delivery
-- alone for state that must stay live and correct.
local function UpdateCheckedState()
	local bar = M.bar
	if not bar then return end

	local i
	for i = 1, NUM_PET_ACTION_SLOTS do
		local button = bar.buttons[i]
		if button then
			local ok, _, _, _, _, isActive = pcall(GetPetActionInfo, i)
			pcall(button.SetChecked, button, ok and Compat.bool(isActive))
		end
	end
end

function M:Initialize()
	-- Always created regardless of `barPet.enabled` -- that's now a live
	-- profile toggle (PositionBar/UpdateVisibility above handle it),
	-- not a private one only checked once at login.
	self.bar = self:CreateBar()
	if not self.bar then return end
	self:PositionBar()
	UpdateVisibility()
	ApplyShowGrid()
	UpdateCheckedState()
	HideSlidingBorder()

	-- The pet buttons' content (icon, shown/hidden, autocast, cooldown) is
	-- driven by PetActionBarFrame's OnEvent (PET_BAR_UPDATE/UNIT_PET ->
	-- PetActionBar_Update, PET_BAR_UPDATE_COOLDOWN ->
	-- PetActionBar_UpdateCooldowns), not by the buttons themselves, and
	-- ActionBars.lua's HideChrome clears that frame's OnEvent. Without these
	-- calls a pet summoned or revived after login gets no buttons. Both
	-- native functions address the buttons by global name, so they work on
	-- the reparented buttons unchanged. PetActionBar_UpdateCooldowns is
	-- called explicitly as well, so the cooldowns do not depend on the
	-- client's PetActionBar_Update including that call.
	local function UpdateButtons()
		if type(_G.PetActionBar_Update) == "function" then
			pcall(PetActionBar_Update)
		end
		local i
		for i = 1, NUM_PET_ACTION_SLOTS do
			HideQuickslotFrame(_G["PetActionButton"..i])
		end
	end

	local function UpdateCooldowns()
		if type(_G.PetActionBar_UpdateCooldowns) == "function" then
			pcall(PetActionBar_UpdateCooldowns)
		end
	end

	local function OnPetBarEvent()
		UpdateButtons()
		UpdateVisibility()
		UpdateCheckedState()
		HideSlidingBorder()
		UpdateCooldowns()
	end
	self:RegisterEvent("UNIT_PET", OnPetBarEvent)
	self:RegisterEvent("PET_BAR_UPDATE", OnPetBarEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnPetBarEvent)
	self:RegisterEvent("PLAYER_CONTROL_LOST", OnPetBarEvent)
	self:RegisterEvent("PLAYER_CONTROL_GAINED", OnPetBarEvent)
	self:RegisterEvent("PLAYER_FARSIGHT_FOCUS_CHANGED", OnPetBarEvent)
	self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN", UpdateCooldowns)

	-- Safety net alongside the event triggers above -- matches this
	-- project's established preference (Cooldowns.lua, UnitFrames.lua)
	-- for not relying solely on event delivery for state that must stay
	-- live; cheap (10 pcall'd reads), so an unbounded repeating timer
	-- (not ScheduleLimitedSweep's capped-runs style) is fine for the
	-- whole session.
	E:ScheduleRepeatingTimer(function()
		UpdateCheckedState()
		HideSlidingBorder()
	end, 0.5)

	-- Same lazily-created-region problem already found (and worked
	-- around the same way) in ActionBars.lua/Minimap.lua -- re-run the
	-- idempotent style pass periodically to catch anything that didn't
	-- exist yet at login. Bounded at 10 runs -- see
	-- ElvUI.Util.ScheduleLimitedSweep (Core/Util.lua).
	ElvUI.Util.ScheduleLimitedSweep(function()
		if not self.bar then return end
		local i
		for i = 1, NUM_PET_ACTION_SLOTS do
			StyleButton(self.bar.buttons[i])
		end
	end, 3, 10)
end

-- Public so ElvUI_Config/Core.lua's `set` functions can re-apply
-- position/size/enabled live, matching E.ActionBars:UpdateBar's own role.
function M:UpdateBar()
	self:PositionBar()
	UpdateVisibility()
	ApplyShowGrid()
end

E:RegisterInitialModule(M:GetName(), function() M:Initialize() end)
