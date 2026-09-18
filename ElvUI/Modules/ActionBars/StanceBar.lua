-- StanceBar module -- shapeshift/stance bar (Warrior stances, Rogue
-- Stealth, Druid forms, etc. -- whichever the player's own class
-- actually has; gated on the native GetNumShapeshiftForms() count, not
-- a hardcoded class list).
--
-- Re-skins native ShapeshiftButton1..N in place, same approach as
-- Modules/ActionBars.lua/PetBar.lua (secure/protected buttons --
-- template the EXISTING globals, never create new ones; reparent onto a
-- new plain container). Deliberately does NOT copy real ElvUI's own
-- BarShapeShift.lua construction technique: real ElvUI creates BRAND NEW
-- `CheckButton` widgets via `CreateFrame(..., "ShapeshiftButtonTemplate")`,
-- a template-backed CreateFrame call that isn't guaranteed to succeed on
-- UA. This project's own ActionBars/PetBar modules never do that -- they
-- always reparent Blizzard's OWN pre-existing native buttons instead
-- (proven safe on UA via the Bagzen addon, which relies on the identical
-- technique), and ShapeshiftButton1..N already exist natively in vanilla
-- regardless of class (Blizzard's own FrameXML creates all
-- NUM_SHAPESHIFT_SLOTS of them at login), so the same recipe applies here
-- with no template risk at all.
--
-- Settings: `P.actionbar.barShapeShift` (Settings/Profile.lua).

local E, L, V, P, G = unpack(ElvUI)
local Compat = ElvUI.Compat
local M = E:NewModule("StanceBar", "AceEvent-3.0")
E.StanceBar = M

local NUM_SHAPESHIFT_SLOTS = _G.NUM_SHAPESHIFT_SLOTS or 10
local PREFIX = "ShapeshiftButton"

-- Re-skins one native stance button in place. Same trimmed recipe as
-- PetBar.lua's own StyleButton (no hotkey/macro text handling needed --
-- see that file's own comment) -- deliberately does NOT touch the
-- CheckedTexture at all (unlike NormalTexture, which this project has
-- already confirmed needs clearing): the checked state IS the entire
-- purpose of this bar (which stance is active), and nothing here
-- introduces a NEW custom checked texture the way the already-abandoned
-- SetPushedTexture/SetCheckedTexture styling attempt did (see
-- ActionBars.lua's own StyleButton comment on that gold-tint finding) --
-- this just leaves whatever checked-texture ShapeshiftButtonTemplate
-- ships with alone, toggled via plain SetChecked.
local function StyleButton(button)
	if not button then return end

	local name = button:GetName()
	local icon = _G[name.."Icon"]
	local normalTexture = _G[name.."NormalTexture"]

	if not button.elvNormalTextureCleared then
		pcall(button.SetNormalTexture, button, "")
		button.SetNormalTexture = E.noop
		button.elvNormalTextureCleared = true
	end
	if normalTexture and normalTexture.SetTexture ~= E.noop then
		pcall(normalTexture.SetTexture, normalTexture, nil)
		normalTexture.SetTexture = E.noop
	end

	if icon and not button.elvIconStyled then
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		icon.SetTexCoord = E.noop
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		button.elvIconStyled = true
	end

	ElvUI.Util.CreateButtonBorder(button)
	ElvUI.Util.RaiseCooldown(button)
end

function M:CreateBar()
	local ok, bar = pcall(CreateFrame, "Frame", "ElvUIStanceBarHolder", UIParent)
	if not ok or not bar then return nil end

	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
	E:CreateMover(bar, "ElvBar_StanceBar", L["Stance Bar"])

	pcall(bar.SetBackdrop, bar, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(bar.SetBackdropColor, bar, 0.1, 0.1, 0.1, 1)
	pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 1)

	bar.buttons = {}
	local i
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		local button = _G[PREFIX..i]
		if button then
			pcall(button.SetParent, button, bar)
			bar.buttons[i] = button
			StyleButton(button)
		end
	end

	return bar
end

function M:PositionBar()
	local bar = self.bar
	if not bar then return end
	local settings = E.db.actionbar.barShapeShift

	if not settings.enabled then
		pcall(bar.SetScale, bar, 0.000001)
		pcall(bar.SetAlpha, bar, 0)
		return
	end
	pcall(bar.SetScale, bar, 1)

	local size = settings.buttonsize
	local spacing = settings.buttonspacing
	local perRow = math.max(settings.buttonsPerRow or NUM_SHAPESHIFT_SLOTS, 1)
	local buttonCount = math.min(settings.buttons or NUM_SHAPESHIFT_SLOTS, NUM_SHAPESHIFT_SLOTS)
	local rows = math.ceil(buttonCount / perRow)
	local cols = math.min(buttonCount, perRow)
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
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		local button = bar.buttons[i]
		if button then
			local row = math.floor((i - 1) / perRow)
			local col = Compat.mod(i - 1, perRow)
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

local function UpdateVisibility()
	local bar = M.bar
	if not bar then return end
	local settings = E.db.actionbar.barShapeShift
	local okForms, numForms = pcall(GetNumShapeshiftForms)
	if settings.enabled and okForms and numForms and numForms > 0 then
		pcall(bar.Show, bar)
	else
		pcall(bar.Hide, bar)
	end
end

-- Icon texture, active stance and castability per slot -- native
-- GetShapeshiftFormInfo(i) returns (texture, name, isActive, isCastable),
-- matching real ElvUI's own BarShapeShift.lua. Unlike ActionButtons, stance
-- buttons have no per-button event handler: the native
-- ShapeshiftBar_UpdateState (driven by ShapeshiftBarFrame's OnEvent) is the
-- only thing that ever sets their icon, checked state and cooldown, and
-- ActionBars.lua's HideChrome() strips that frame's OnEvent. All three are
-- therefore this module's job. The texture matters, not just SetChecked:
-- while a form is on, GetShapeshiftFormInfo returns a different "active"
-- texture (e.g. Spell_Nature_WispSplode for Druid forms) that replaces the
-- form's own icon, which is how the native bar shows the active form.
-- SetTexture is only called when the path changed, since this also runs
-- from a 0.5s timer.
local function UpdateCheckedState()
	local bar = M.bar
	if not bar then return end

	local i
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		local button = bar.buttons[i]
		if button then
			local okInfo, texture, _, isActive, isCastable = pcall(GetShapeshiftFormInfo, i)
			pcall(button.SetChecked, button, okInfo and isActive and true or false)

			local icon = _G[button:GetName().."Icon"]
			if icon then
				if okInfo and texture and button.elvIconTexture ~= texture then
					pcall(icon.SetTexture, icon, texture)
					button.elvIconTexture = texture
				end
				if okInfo and isCastable then
					pcall(icon.SetVertexColor, icon, 1, 1, 1)
				else
					pcall(icon.SetVertexColor, icon, 0.4, 0.4, 0.4)
				end
			end
		end
	end
end

-- Same native-handler gap as UpdateCheckedState above. Event-driven only,
-- never from the timer: re-applying an unchanged cooldown every tick would
-- restart the swipe. Core/Cooldowns.lua's CooldownFrame_SetTimer hook adds
-- the countdown text.
local function UpdateCooldowns()
	local bar = M.bar
	if not bar then return end

	local i
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		local button = bar.buttons[i]
		local cooldown = button and _G[button:GetName().."Cooldown"]
		if cooldown then
			local ok, start, duration, enable = pcall(GetShapeshiftFormCooldown, i)
			if ok and start then
				pcall(CooldownFrame_SetTimer, cooldown, start, duration, enable)
			end
		end
	end
end

function M:Initialize()
	self.bar = self:CreateBar()
	if not self.bar then return end
	self:PositionBar()
	UpdateVisibility()
	UpdateCheckedState()
	UpdateCooldowns()

	local function OnStanceBarEvent()
		UpdateVisibility()
		UpdateCheckedState()
		UpdateCooldowns()
	end
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", OnStanceBarEvent)
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", OnStanceBarEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnStanceBarEvent)
	self:RegisterEvent("PLAYER_AURAS_CHANGED", OnStanceBarEvent)
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", UpdateCooldowns)

	-- Same safety-net reasoning/interval as PetBar.lua's own checked-
	-- state timer -- cheap (a handful of pcall'd reads per slot), not
	-- capped, since the active stance can change at any point in play.
	E:ScheduleRepeatingTimer(UpdateCheckedState, 0.5)

	-- Same lazily-created-region problem already found (and worked
	-- around the same way) in ActionBars.lua/PetBar.lua/Minimap.lua.
	ElvUI.Util.ScheduleLimitedSweep(function()
		if not self.bar then return end
		local i
		for i = 1, NUM_SHAPESHIFT_SLOTS do
			StyleButton(self.bar.buttons[i])
		end
	end, 3, 10)
end

-- Public so ElvUI_Config/Core.lua's `set` functions can re-apply
-- position/size/enabled live, matching E.PetBar:UpdateBar's own role.
function M:UpdateBar()
	self:PositionBar()
	UpdateVisibility()
end

E:RegisterInitialModule(M:GetName(), function() M:Initialize() end)
