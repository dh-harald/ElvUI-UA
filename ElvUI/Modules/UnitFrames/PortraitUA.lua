-- Unit frame portrait -- Unreal Azeroth implementation.
--
-- The two clients need different portrait code, so the element lives in two
-- files implementing the same three methods. Each file installs them only on
-- its own client (`ElvUI.Compat.isUA`) and returns right after loading on the
-- other one. PortraitLegacy.lua is the 1.12.1 counterpart.
--
--   UF:Construct_Portrait(frame, size)
--       Builds the widgets. Called after Construct_HealthBar.
--   UF:Update_Portrait(frame, settings, unit) -> portraitWidth
--       Layout + content refresh, every UpdateFrame. Returns the width the
--       health/power bars must leave free on the frame's left edge.
--   UF:PostUpdateHealth_Portrait(frame, bgR, bgG, bgB, a, bgTexture,
--                                r, g, b, fillTexture)
--       Called after Health's value, fill and background are applied, with
--       the background's resolved color/alpha/texture and the fill's
--       resolved color/texture (the fill's alpha is `a` as well).

local E, L, V, P, G = unpack(ElvUI)
if not ElvUI.Compat.isUA then return end

local UF = E.UnitFrames
local Util = ElvUI.Util
local INSET = UF.INSET

-- Alpha of the mirrored health fill drawn above an overlay portrait. 0.65
-- bar over the portrait gives the same mix as ElvUI-vanilla's 0.35 portrait
-- over the bar.
local OVERLAY_FILL_ALPHA = 0.65

-- frame.Portrait: a holder frame containing both a 2D Texture
-- (SetPortraitTexture) and a 3D PlayerModel (SetUnit); `db.portrait.style`
-- ("2D"/"3D") picks the visible one at update time.
--
-- frame.PortraitHealth: a second status bar mirroring frame.Health, drawn
-- above an overlay portrait. PlayerModel:SetAlpha is unreliable on UA (a
-- single call has no effect, and real ElvUI's SetAlpha(0)-then-target
-- sequence hides the model entirely), so instead of a translucent portrait
-- over the bar, the portrait is drawn opaque above Health and this mirror
-- adds the bar's color over it through a translucent fill (vertex-color
-- alpha, which does work on UA). Its background covers only the
-- missing-health part, at the bar's own alpha, hiding the portrait there.
--
-- source/UnrealUI/modules/unitframes.lua documents a crash from a 3D
-- PlayerModel portrait on UA; a standalone PlayerModel with
-- SetUnit("player") renders correctly on current UA builds, so 3D is offered.
function UF:Construct_Portrait(frame, size)
	local box = CreateFrame("Frame", nil, frame)
	box:SetWidth(size)
	box:SetHeight(size)

	local tex = box:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(box)
	box.texture = tex

	local model = CreateFrame("PlayerModel", nil, box)
	model:SetAllPoints(box)
	model:Hide()
	box.model = model

	box:Hide()
	frame.Portrait = box

	-- Health + 5: above the portrait (Health + 1, model + 2) and below
	-- Health's text layer (Health + 10), so texts and state icons stay on top.
	local mirror = Util.CreateStatusBar(frame)
	local ok, healthLevel = pcall(frame.Health.GetFrameLevel, frame.Health)
	if ok and tonumber(healthLevel) then
		pcall(mirror.SetFrameLevel, mirror, healthLevel + 5)
	end
	mirror:Hide()
	frame.PortraitHealth = mirror

	return box
end

-- Overlay (real ElvUI's `portrait.overlay`): the portrait spans the Health
-- bar's rect ABOVE the bar, with frame.PortraitHealth above it; Power is
-- never covered, as in real ElvUI. The bars keep their full width.
-- The model gets an explicit level too, rather than relying on it following
-- its parent's level.
--
-- Content refresh is edge-triggered. SetPortraitTexture on every poll tick
-- makes the 2D portrait flicker, so SetUnit/SetPortraitTexture only run when
-- the portrait becomes shown, the style switches, or UnitName(unit) changes.
-- The name stands in for UnitGUID, which this client generation lacks; two
-- same-named units therefore share one refresh. A portrait change on an
-- unchanged unit (e.g. a druid shapeshift) is not picked up.
function UF:Update_Portrait(frame, settings, unit)
	local portrait = frame.Portrait
	if not portrait then return 0 end

	local pdb = settings.portrait
	if not (pdb and pdb.enable) then
		-- A parent's Hide() does not hide its children on UA, so the model and
		-- the texture are hidden individually.
		portrait.model:Hide()
		portrait.texture:Hide()
		portrait:Hide()
		portrait.shown2D = false
		portrait.shown3D = false
		portrait.overlayMode = false
		return 0
	end

	local portraitWidth = 0
	portrait:ClearAllPoints()
	portrait.overlayMode = pdb.overlay and true or false

	if pdb.overlay then
		portrait:SetPoint("TOPLEFT", frame.Health, "TOPLEFT", 0, 0)
		portrait:SetWidth(frame.Health:GetWidth())
		portrait:SetHeight(frame.Health:GetHeight())

		local ok, healthLevel = pcall(frame.Health.GetFrameLevel, frame.Health)
		if ok and tonumber(healthLevel) then
			pcall(portrait.SetFrameLevel, portrait, healthLevel + 1)
			pcall(portrait.model.SetFrameLevel, portrait.model, healthLevel + 2)
		end
	else
		portraitWidth = pdb.width
		portrait:SetWidth(portraitWidth)
		portrait:SetHeight(portraitWidth)
		portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -INSET)
	end

	local okName, unitName = pcall(UnitName, unit)
	unitName = okName and unitName or nil
	if portrait.lastName ~= unitName then
		portrait.shown2D = false
		portrait.shown3D = false
		portrait.lastName = unitName
	end

	if pdb.style == "3D" then
		portrait.texture:Hide()
		if not portrait.shown3D then
			local model = portrait.model
			pcall(model.SetUnit, model, unit)
			-- oUF's stock scale/position. SetCamera(0) selects the model's
			-- built-in portrait camera; without it the model is turned away
			-- from the viewer on UA. SetPortraitZoom and SetCamDistanceScale
			-- do not exist on UA's PlayerModel.
			pcall(model.SetModelScale, model, 1)
			pcall(model.SetPosition, model, 0, 0, 0)
			pcall(model.SetCamera, model, 0)
			portrait.shown3D = true
		end
		portrait.shown2D = false
		portrait.model:Show()
	else
		portrait.model:Hide()
		if not portrait.shown2D then
			pcall(SetPortraitTexture, portrait.texture, unit)
			portrait.shown2D = true
		end
		portrait.shown3D = false
		portrait.texture:Show()
	end

	portrait:Show()
	return portraitWidth
end

-- Keeps frame.PortraitHealth in sync with frame.Health: geometry, range,
-- value, textures and colors. Explicit size rather than SetAllPoints:
-- Util.CreateStatusBar sizes its fill from GetWidth/GetHeight, which is only
-- guaranteed for an explicitly sized frame. Size is applied before the value,
-- so a value change recomputes the fill at the current size.
function UF:PostUpdateHealth_Portrait(frame, bgR, bgG, bgB, a, bgTexture, r, g, b, fillTexture)
	local mirror = frame.PortraitHealth
	if not mirror then return end

	local portrait = frame.Portrait
	if not (portrait and portrait:IsShown() and portrait.overlayMode) then
		mirror:Hide()
		return
	end

	local health = frame.Health
	mirror:ClearAllPoints()
	mirror:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
	mirror:SetWidth(health:GetWidth())
	mirror:SetHeight(health:GetHeight())

	local minValue, maxValue = health:GetMinMaxValues()
	local value = health:GetValue()
	mirror:SetMinMaxValues(minValue, maxValue)
	mirror:SetValue(value)

	Util.SetStatusBarTexture(mirror, fillTexture)
	Util.SetStatusBarColor(mirror, r, g, b, OVERLAY_FILL_ALPHA)

	-- Util.CreateStatusBar's background spans the whole bar, under the fill
	-- too. Opaque, it would hide the portrait behind the filled part as well,
	-- so on the mirror it is re-anchored to the missing-health part only.
	local bg = mirror.barBgTexture
	minValue = minValue or 0
	local range = (maxValue or 0) - minValue
	local fraction = 0
	if range > 0 then
		fraction = ((value or 0) - minValue) / range
	end
	if fraction < 0 then fraction = 0 end

	if fraction >= 1 then
		bg:Hide()
	else
		bg:ClearAllPoints()
		if health.barVertical then
			local height = tonumber(health:GetHeight()) or 0
			bg:SetPoint("TOPLEFT", mirror, "TOPLEFT", 0, 0)
			bg:SetPoint("BOTTOMRIGHT", mirror, "BOTTOMRIGHT", 0, height * fraction)
		else
			local width = tonumber(health:GetWidth()) or 0
			bg:SetPoint("TOPLEFT", mirror, "TOPLEFT", width * fraction, 0)
			bg:SetPoint("BOTTOMRIGHT", mirror, "BOTTOMRIGHT", 0, 0)
		end
		if bgTexture then
			pcall(bg.SetTexture, bg, bgTexture)
		end
		Util.SetStatusBarBackgroundColor(mirror, bgR, bgG, bgB, a)
		bg:Show()
	end

	mirror:Show()
end
