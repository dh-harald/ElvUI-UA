-- Unit frame portrait -- legacy 1.12.1 client implementation.
--
-- Ported from ElvUI-vanilla: Modules/UnitFrames/Elements/Portrait.lua
-- (construction, overlay layout, alpha) and Libraries/oUF/elements/
-- portrait.lua (when and how the content is refreshed). The method contract
-- shared with the Unreal Azeroth implementation is described at the top of
-- PortraitUA.lua.
--
-- Deviations from the source, forced by this module not being oUF-based:
-- - oUF's OnUpdate path (name/availability change detection) runs from this
--   module's 0.2s poll via Update_Portrait; oUF's event path is the event
--   frame at the bottom of this file.
-- - The non-overlay portrait keeps this module's layout (a square at the
--   frame's top-left, inside the shared panel) instead of ElvUI's separately
--   bordered portrait box.
-- - ElvUI-vanilla re-parents Health's background onto a raised frame and
--   anchors it to the fill texture's edge, so the missing-health part of the
--   bar draws above an overlay portrait. Util.CreateStatusBar hides its fill
--   texture at zero value, so nothing can be anchored to it; a separate cover
--   texture on a raised frame is sized from the bar's value instead
--   (PostUpdateHealth_Portrait).

local E, L, V, P, G = unpack(ElvUI)
if ElvUI.Compat.isUA then return end

local UF = E.UnitFrames
local INSET = UF.INSET

-- ElvUI-vanilla's overlay portrait alpha.
local OVERLAY_ALPHA = 0.35
-- oUF shows this model for a unit that is offline or out of visibility
-- range. ElvUI-vanilla keeps retail's .m2 path; the 1.12.1 client ships the
-- model as .mdx (path from pfUI).
local UNAVAILABLE_MODEL = "Interface\\Buttons\\talktomequestionmark.mdx"

-- ElvUI-vanilla's PortraitUpdate: the overlay alpha is set through 0 first,
-- and re-applied after every model load.
local function ApplyAlpha(element)
	if element.overlayMode then
		element:SetAlpha(0)
		element:SetAlpha(OVERLAY_ALPHA)
	else
		element:SetAlpha(1)
	end
end

-- Model calls are queued and run from the model's own OnUpdate, i.e. on the
-- next frame and only while the model is visible (OnUpdate does not fire for
-- a hidden frame). pfUI drives its 1.12 portraits the same way (SetUnit +
-- SetCamera(0) from OnUpdate). "unit" and "unavailable" replace each other;
-- a queued "camera" never downgrades either of them.
local function QueueModel(model, action)
	if action == "camera" and model.pendingAction then return end
	model.pendingAction = action
end

-- oUF Portrait Update, model branch.
local function Model_OnUpdate()
	local action = this.pendingAction
	if not action then return end
	this.pendingAction = nil

	if action == "unavailable" then
		pcall(this.SetModelScale, this, 4.25)
		pcall(this.SetCamera, this, 0)
		pcall(this.SetPosition, this, 0, 0, -1.5)
		pcall(this.SetModel, this, UNAVAILABLE_MODEL)
	elseif action == "unit" then
		pcall(this.ClearModel, this)
		pcall(this.SetUnit, this, this.unit)
		pcall(this.SetModelScale, this, 1)
		pcall(this.SetCamera, this, 0)
		pcall(this.SetPosition, this, 0, 0, 0)
	else
		pcall(this.SetCamera, this, 0)
	end

	ApplyAlpha(this)
end

-- oUF refreshes every element when the unit frame is shown; for a model
-- whose unit is unchanged that is a SetCamera(0). Also fires when the model
-- becomes visible through its parent unit frame being shown.
local function Model_OnShow()
	QueueModel(this, "camera")
end

-- oUF Portrait Update. `event` "OnUpdate" (the poll) refreshes only when the
-- unit's name or availability changed; any other value forces a refresh.
local function Refresh(frame, event)
	local element = frame.Portrait
	local unit = frame.unit
	if not element or not unit then return end

	local okName, name = pcall(UnitName, unit)
	name = okName and name or nil
	local okConnected, connected = pcall(UnitIsConnected, unit)
	local okVisible, visible = pcall(UnitIsVisible, unit)
	local isAvailable = (okConnected and connected and okVisible and visible) and true or false

	if event == "OnUpdate" and element.name == name and element.state == isAvailable then
		return
	end

	if element == frame.Portrait3D then
		if not isAvailable then
			QueueModel(element, "unavailable")
		elseif element.name ~= name or event == "UNIT_MODEL_CHANGED" then
			QueueModel(element, "unit")
		else
			QueueModel(element, "camera")
		end
	else
		pcall(SetPortraitTexture, element.texture, unit)
	end

	element.name = name
	element.state = isAvailable
end

-- frame.Portrait3D (PlayerModel) and frame.Portrait2D (a frame holding the
-- texture) are both built, as in ElvUI-vanilla; frame.Portrait points at the
-- one `db.portrait.style` selects.
function UF:Construct_Portrait(frame, size)
	local model = CreateFrame("PlayerModel", nil, frame)
	model:SetWidth(size)
	model:SetHeight(size)
	model:Hide()
	model:SetScript("OnShow", Model_OnShow)
	model:SetScript("OnUpdate", Model_OnUpdate)
	frame.Portrait3D = model

	-- The 2D texture sits in its own frame so its level can be raised above
	-- Health for the overlay (ElvUI-vanilla re-parents the texture onto the
	-- Health bar instead). The TexCoord crop is ElvUI-vanilla's.
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetWidth(size)
	holder:SetHeight(size)
	holder:Hide()
	local texture = holder:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints(holder)
	texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
	holder.texture = texture
	frame.Portrait2D = holder

	-- Covers the missing-health part of the bar above an overlay portrait,
	-- so the portrait only shows across the filled part. Health + 5 is
	-- ElvUI-vanilla's `portrait.overlay` level; Health's text layer sits at
	-- Health + 10 and stays on top.
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints(frame.Health)
	overlay:SetFrameLevel(frame.Health:GetFrameLevel() + 5)
	local cover = overlay:CreateTexture(nil, "BACKGROUND")
	cover:SetTexture("Interface\\Buttons\\WHITE8x8")
	cover:Hide()
	overlay.cover = cover
	frame.PortraitOverlay = overlay

	frame.Portrait = model
	return model
end

-- ElvUI-vanilla Configure_Portrait, on this module's layout.
--
-- Overlay: the selected portrait spans the Health bar one level above it at
-- OVERLAY_ALPHA, and the cover hides it over the missing-health part. The
-- bars keep their full width, and colors.transparentHealth is not needed for
-- the portrait to show. ElvUI-vanilla puts a 3D overlay at Health's own
-- level; + 1 makes "portrait above the fill" explicit instead of relying on
-- same-level draw order between sibling frames.
function UF:Update_Portrait(frame, settings, unit)
	local model, holder = frame.Portrait3D, frame.Portrait2D
	if not model then return 0 end

	local pdb = settings.portrait
	if not (pdb and pdb.enable) then
		model:Hide()
		holder:Hide()
		return 0
	end

	local element, other = model, holder
	if pdb.style == "2D" then
		element, other = holder, model
	end
	other:Hide()
	frame.Portrait = element
	model.unit = unit

	local portraitWidth = 0
	local overlay = pdb.overlay and true or false
	element:ClearAllPoints()
	if overlay then
		element:SetAllPoints(frame.Health)
		element:SetFrameLevel(frame.Health:GetFrameLevel() + 1)
	else
		portraitWidth = pdb.width
		element:SetWidth(portraitWidth)
		element:SetHeight(portraitWidth)
		element:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -INSET)
		element:SetFrameLevel(frame:GetFrameLevel() + 1)
	end

	if element.overlayMode ~= overlay then
		element.overlayMode = overlay
		ApplyAlpha(element)
	end

	if element:IsShown() then
		Refresh(frame, "OnUpdate")
	else
		element:Show()
		Refresh(frame, "ForceUpdate")
	end

	return portraitWidth
end

function UF:PostUpdateHealth_Portrait(frame, r, g, b, a, texture)
	local overlay = frame.PortraitOverlay
	if not overlay then return end
	local cover = overlay.cover

	local element = frame.Portrait
	if not (element and element:IsShown() and element.overlayMode) then
		cover:Hide()
		return
	end

	local health = frame.Health
	local minValue, maxValue = health:GetMinMaxValues()
	minValue = minValue or 0
	local range = (maxValue or 0) - minValue
	local fraction = 0
	if range > 0 then
		fraction = ((health:GetValue() or 0) - minValue) / range
	end
	if fraction >= 1 then
		cover:Hide()
		return
	end
	if fraction < 0 then fraction = 0 end

	cover:ClearAllPoints()
	if health.barVertical then
		local height = tonumber(health:GetHeight()) or 0
		cover:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
		cover:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, height * fraction)
	else
		local width = tonumber(health:GetWidth()) or 0
		cover:SetPoint("TOPLEFT", overlay, "TOPLEFT", width * fraction, 0)
		cover:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
	end
	if texture then
		cover:SetTexture(texture)
	end
	cover:SetVertexColor(r, g, b, a)
	cover:Show()
end

-- oUF's event path: UNIT_PORTRAIT_UPDATE / UNIT_MODEL_CHANGED for the unit
-- in arg1, PLAYER_TARGET_CHANGED for the target frame, PARTY_MEMBER_ENABLE
-- for party frames, PLAYER_ENTERING_WORLD for every frame. A frame that is
-- not visible is skipped; the poll refreshes it once it is shown.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
eventFrame:RegisterEvent("UNIT_MODEL_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
	if not UF.Frames then return end
	local id, frame
	for id, frame in pairs(UF.Frames) do
		local unit = frame.unit
		local element = frame.Portrait
		if unit and element and element:IsVisible() then
			local match
			if event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
				local ok, same = pcall(UnitIsUnit, unit, arg1)
				match = ok and same
			elseif event == "PLAYER_TARGET_CHANGED" then
				match = (unit == "target")
			elseif event == "PARTY_MEMBER_ENABLE" then
				match = (string.find(unit, "^party") ~= nil)
			else
				match = true
			end
			if match then
				Refresh(frame, event)
			end
		end
	end
end)
