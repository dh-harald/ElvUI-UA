-- Leave Druid form when an action fails because of it (general.cancelForm:
-- "NONE" / "MANUAL" / "AUTO"). Not a real ElvUI feature; the error list and
-- the in-combat NPC rule follow pfUI's autoshift module.
--
-- Trigger: UI_ERROR_MESSAGE, whose text arrives in `arg1` on both clients.
-- It is compared against the client's own global strings, so every locale
-- matches without a translated pattern list.
--
-- Leaving the form: CastShapeshiftForm on the ACTIVE form's stance slot
-- toggles it off (not protected on either client). Any other slot switches
-- to that form instead, so the active slot is looked up every time. Druid
-- only: a rogue's Stealth is also a stance slot, and none of these errors
-- should ever unstealth.
--
-- ERR_CANT_INTERACT_SHAPESHIFTED ("Can't speak while shapeshifted.") is not
-- specific to NPC dialogue: right-clicking a neutral (yellow) mob in form
-- raises it too, where leaving the form is exactly wrong. It is therefore
-- only acted on when the clicked unit is an NPC the player cannot attack.
-- The clicked unit is read from "target": the right-click has already
-- targeted it when the error arrives, while "mouseover" is empty by then
-- on UA. In combat, or with no target, it falls back to the button even in
-- AUTO mode.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Misc")
local Compat = ElvUI.Compat

-- Errors raised by casting, using an item, mounting or taking a taxi while
-- shapeshifted. Global names, resolved at load; a name the client lacks is
-- skipped.
local FORM_ERRORS = {
	"SPELL_FAILED_NOT_SHAPESHIFT",
	"SPELL_FAILED_NO_ITEMS_WHILE_SHAPESHIFTED",
	"SPELL_NOT_SHAPESHIFTED",
	"SPELL_NOT_SHAPESHIFTED_NOSPACE",
	"ERR_NOT_WHILE_SHAPESHIFTED",
	"ERR_NO_ITEMS_WHILE_SHAPESHIFTED",
	"ERR_MOUNT_SHAPESHIFTED",
	"ERR_TAXIPLAYERSHAPESHIFTED",
	"ERR_EMBLEMERROR_NOTABARDGEOSET",
}

-- The button hides itself after this many seconds if not clicked.
local BUTTON_TIMEOUT = 8

local formErrors = {}
local interactError

-- Stance slot of the active form, and its name; nil when in caster form.
local function GetActiveForm()
	local num = tonumber(GetNumShapeshiftForms and GetNumShapeshiftForms()) or 0
	local i
	for i = 1, num do
		local ok, _, name, isActive = pcall(GetShapeshiftFormInfo, i)
		if ok and Compat.bool(isActive) then return i, name end
	end
	return nil
end

local function LeaveForm()
	local slot = GetActiveForm()
	if slot then pcall(CastShapeshiftForm, slot) end
end

local button

local function HideButton()
	if button then button:Hide() end
end

local function CreateButton()
	button = CreateFrame("Button", "ElvUICancelFormButton", UIParent)
	button:SetWidth(240)
	button:SetHeight(44)
	button:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
	pcall(button.SetFrameStrata, button, "HIGH")
	E:SetTemplate(button, "Default")

	-- A font template is required: SetFont is a no-op on UA, so a
	-- FontString without one has no font and draws nothing.
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	text:SetPoint("CENTER", button, "CENTER", 0, 0)
	E:FontTemplate(text, nil, 16, "OUTLINE")
	button.text = text

	button:SetScript("OnClick", function()
		LeaveForm()
		HideButton()
	end)
	button:SetScript("OnUpdate", function()
		if GetTime() >= (button.hideAt or 0) or not GetActiveForm() then
			HideButton()
		end
	end)
	button:Hide()
end

local function ShowButton(name)
	if not button then CreateButton() end
	button.text:SetText(string.format(L["Leave %s"], name or ""))
	button.hideAt = GetTime() + BUTTON_TIMEOUT
	button:Show()
end

-- For ERR_CANT_INTERACT_SHAPESHIFTED: "ignore", "button" or "mode".
local function InteractVerdict()
	local unit = "target"
	if not UnitExists(unit) then return "button" end
	if Compat.bool(UnitIsPlayer(unit)) or Compat.bool(UnitCanAttack("player", unit)) then
		return "ignore"
	end
	if Compat.bool(UnitAffectingCombat("player")) then return "button" end
	return "mode"
end

local function OnError()
	local mode = E.db.general.cancelForm
	if not mode or mode == "NONE" then return end
	if type(arg1) ~= "string" then return end

	local verdict
	if formErrors[arg1] then
		verdict = "mode"
	elseif interactError and arg1 == interactError then
		verdict = InteractVerdict()
	end
	if not verdict or verdict == "ignore" then return end

	local slot, name = GetActiveForm()
	if not slot then return end

	if mode == "AUTO" and verdict == "mode" then
		pcall(CastShapeshiftForm, slot)
	else
		ShowButton(name)
	end
end

function M:LoadCancelForm()
	local _, class = UnitClass("player")
	if class ~= "DRUID" then return end

	local i
	for i = 1, table.getn(FORM_ERRORS) do
		local text = _G[FORM_ERRORS[i]]
		if type(text) == "string" then formErrors[text] = true end
	end
	if type(_G.ERR_CANT_INTERACT_SHAPESHIFTED) == "string" then
		interactError = _G.ERR_CANT_INTERACT_SHAPESHIFTED
	end

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("UI_ERROR_MESSAGE")
	frame:SetScript("OnEvent", OnError)
end
