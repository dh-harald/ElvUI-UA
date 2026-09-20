-- Misc > RaidMarker -- a ring of the eight raid target icons that opens at the
-- cursor on the "Raid Marker" key binding (Bindings.xml) and puts the clicked
-- icon on the current target; right-click clears the target's mark. Port of
-- real ElvUI's Modules/Misc/RaidMarker.lua (ElvUI-vanilla).
--
-- Where it differs from real ElvUI:
--   * No permission check. The 1.12 FrameXML unit menu offers the same marks
--     to every player, grouped or not, with no hide rule, and leaves the
--     decision to the server (UnitPopup.lua). Real ElvUI-vanilla's own check
--     lets any raid member through but stops a party member who is not the
--     leader, which matches no client's rule.
--   * Icons are cropped from a constant table, Util.RAID_TARGET_COORDS, instead
--     of SetRaidTargetIconTexture, which is not in UA's API documentation.
--   * The ring positions are real ElvUI's (angle pi / 0.7 * i, radius 60)
--     precomputed, so the angle unit of the client's math.sin/cos never
--     matters.
--   * Real ElvUI opens the ring on key press and closes it on release through
--     the binding's `keystate`. A client that runs the binding body without a
--     keystate toggles the ring on each run instead.
--   * Plain SetPoint/SetWidth on UIParent: E:Point/E:Size/E.UIParent do not
--     exist in this project.

local E, L, V, P, G = unpack(ElvUI)
local M = E:GetModule("Misc")

local ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local RING_SIZE = 100
local BUTTON_SIZE = 40
local HOVER_GROW = 10
local MARK_COUNT = 8

-- Offsets from the ring's centre for marks 1-7; mark 8 (skull) sits in the
-- middle.
local RING_OFFSETS = {
	{ -58.5, -13.35 },
	{ 26.03, -54.06 },
	{ 46.91, 37.41 },
	{ -46.91, 37.41 },
	{ -26.03, -54.06 },
	{ 58.5, -13.35 },
	{ 0, 60 },
}

local keyDown = false

function M:RaidMarkShowIcons()
	local ring = self.RaidMarkFrame
	if not ring or not UnitExists("target") or UnitIsDead("target") then return end
	local x, y = GetCursorPosition()
	local scale = ring:GetEffectiveScale()
	if not x or not y or not scale or scale == 0 then return end
	ring:ClearAllPoints()
	ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	ring:Show()
end

-- Called from the Bindings.xml body.
function RaidMark_HotkeyPressed(keystate)
	local ring = M.RaidMarkFrame
	if not ring then return end
	if keystate == "down" then
		keyDown = true
		M:RaidMarkShowIcons()
	elseif keystate == "up" then
		keyDown = false
		ring:Hide()
	elseif ring:IsShown() then
		ring:Hide()
	else
		M:RaidMarkShowIcons()
	end
end

function M:RaidMark_OnEvent()
	if keyDown then self:RaidMarkShowIcons() end
end

-- The clicked mouse button arrives as a direct argument on UA and in the
-- `arg1` global on the legacy client; both are read (as in UnitFrames.lua).
local function CreateMarkButton(ring, index)
	local button = CreateFrame("Button", "RaidMarkIconButton" .. index, ring)
	button:SetWidth(BUTTON_SIZE)
	button:SetHeight(BUTTON_SIZE)
	button:SetID(index)

	local texture = button:CreateTexture(nil, "ARTWORK")
	texture:SetTexture(ICON_TEXTURE)
	local coords = ElvUI.Util.RAID_TARGET_COORDS[index]
	texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	texture:SetAllPoints(button)
	button.Texture = texture

	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(a, b)
		local mouseButton
		if type(a) == "string" then mouseButton = a
		elseif type(b) == "string" then mouseButton = b
		elseif type(arg1) == "string" then mouseButton = arg1 end

		PlaySound("UChatScrollButton")
		if mouseButton == "RightButton" then
			SetRaidTarget("target", 0)
		else
			SetRaidTarget("target", index)
		end
		ring:Hide()
	end)
	button:SetScript("OnEnter", function()
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", button, "TOPLEFT", -HOVER_GROW, HOVER_GROW)
		texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", HOVER_GROW, -HOVER_GROW)
	end)
	button:SetScript("OnLeave", function()
		texture:ClearAllPoints()
		texture:SetAllPoints(button)
	end)

	if index == MARK_COUNT then
		button:SetPoint("CENTER", ring, "CENTER", 0, 0)
	else
		local offset = RING_OFFSETS[index]
		button:SetPoint("CENTER", ring, "CENTER", offset[1], offset[2])
	end
	return button
end

function M:LoadRaidMarker()
	if self.RaidMarkFrame then return end

	local ring = CreateFrame("Frame", nil, UIParent)
	ring:EnableMouse(true)
	ring:SetWidth(RING_SIZE)
	ring:SetHeight(RING_SIZE)
	ring:SetFrameStrata("DIALOG")
	ring:Hide()

	local i
	for i = 1, MARK_COUNT do
		CreateMarkButton(ring, i)
	end

	self.RaidMarkFrame = ring
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "RaidMark_OnEvent")
end
