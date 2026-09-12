-- World Map module.
--
-- Real ElvUI's own WorldMap.lua (source/ElvUI-vanilla/ElvUI/Modules/Maps/
-- WorldMap.lua) does two things: a player/cursor coordinate readout
-- (CONFIRMED WORKING in-game -- see CreateCoordsHolder/Refresh below) and
-- "Smaller World Map" (ApplySmallerWorldMap below -- untested). Its own
-- separate Skins/Blizzard/WorldMap.lua (dropdown/button/backdrop
-- reskinning) needs core Skins-module helpers (E:StripTextures/
-- E:CreateBackdrop/E:Point/S:HandleDropDownBox/S:HandleButton) that don't
-- exist anywhere in this project yet -- still deferred, not attempted
-- here.
--
-- UA construction pattern for the coordinate readout deliberately copied
-- from UnrealUI's OWN worldmap.lua (source/UnrealUI/modules/worldmap.lua),
-- not real ElvUI's -- UnrealUI documents a client-specific rendering bug:
-- "a bare addon FontString child can report shown,
-- positioned and opaque throughout the first fullscreen-map presentation
-- yet remain visually absent until the map is opened again." Their
-- proven-working construction instead: a Button frame with one
-- file-backed BACKGROUND texture, with any label FontString attached to
-- THAT already-rendering surface -- not a bare FontString parented
-- straight to the map. Copied here for the same reason, and it worked --
-- confirmed rendering correctly on first map open. Also per their
-- documented findings: child-frame OnUpdate scripts are unreliable on UA
-- (drives the readout off an AceTimer repeating timer instead), and
-- WorldMapFrame:IsShown() doesn't reliably track the fullscreen
-- presentation either (so this doesn't try to gate the timer on map
-- visibility -- runs unconditionally, matching their own accepted
-- tradeoff). Parented to WorldMapButton, not WorldMapDetailFrame like real
-- ElvUI -- WorldMapButton is UnrealUI's own UA-verified geometry anchor
-- for this exact kind of overlay.
--
-- ApplySmallerWorldMap has NOT been tested in-game yet.

local E, L, V, P, G = unpack(ElvUI)
local M = E:NewModule("WorldMap")
E.WorldMap = M

-- Settings: `G.general.WorldMapCoordinates` and `G.general.smallerWorldMap`
-- (Settings/Global.lua) -- GLOBAL, not per-profile, matching real ElvUI:
-- both are per-account preferences. Everything below reads the LIVE merged
-- table (`E.global`), never `G` directly.

local function CreateCoordsHolder()
	local canvas = _G.WorldMapButton or _G.WorldMapFrame
	if not canvas then return nil end

	local ok, holder = pcall(CreateFrame, "Button", "ElvUIWorldMapCoords", canvas)
	if not ok or not holder then return nil end

	holder:SetWidth(150)
	holder:SetHeight(34)
	local okLevel, canvasLevel = pcall(canvas.GetFrameLevel, canvas)
	pcall(holder.SetFrameLevel, holder, math.max((okLevel and canvasLevel or 0) + 20, 120))
	if holder.EnableMouse then pcall(holder.EnableMouse, holder, false) end

	local ok2, bg = pcall(holder.CreateTexture, holder, nil, "BACKGROUND")
	if ok2 and bg then
		pcall(bg.SetTexture, bg, "Interface\\Buttons\\WHITE8x8")
		pcall(bg.SetAllPoints, bg, holder)
		pcall(bg.SetVertexColor, bg, 0.05, 0.05, 0.05, 0.7)
	end

	local playerText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	playerText:SetPoint("TOPLEFT", holder, "TOPLEFT", 5, -5)
	playerText:SetJustifyH("LEFT")

	local mouseText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mouseText:SetPoint("TOPLEFT", playerText, "BOTTOMLEFT", 0, -3)
	mouseText:SetJustifyH("LEFT")

	return holder, playerText, mouseText
end

-- Cursor as a 0..1 fraction of the map canvas -- UnrealUI's own verified
-- normalization (worldmap.lua's CursorMapPosition), using WorldMapButton's
-- geometry rather than real ElvUI's WorldMapDetailFrame:GetCenter()-based
-- approach.
local function GetCursorMapPercent()
	local canvas = _G.WorldMapButton
	if not canvas then return nil, nil end

	local okPos, x, y = pcall(GetCursorPosition)
	if not okPos or not x or not y then return nil, nil end

	local okScale, scale = pcall(canvas.GetEffectiveScale, canvas)
	scale = (okScale and scale and scale ~= 0) and scale or 1

	local okLeft, left = pcall(canvas.GetLeft, canvas)
	local okTop, top = pcall(canvas.GetTop, canvas)
	local okW, width = pcall(canvas.GetWidth, canvas)
	local okH, height = pcall(canvas.GetHeight, canvas)
	if not (okLeft and okTop and okW and okH) or not (left and top and width and height) then
		return nil, nil
	end
	if width == 0 or height == 0 then return nil, nil end

	local u = (x / scale - left) / width
	local v = (top - y / scale) / height
	return u, v
end

function M:PositionCoords()
	if not self.holder then return end

	local canvas = _G.WorldMapButton or _G.WorldMapFrame
	if not canvas then return end

	local cfg = E.global.general.WorldMapCoordinates
	local pos = cfg.position or "BOTTOMLEFT"
	self.holder:ClearAllPoints()
	pcall(self.holder.SetPoint, self.holder, pos, canvas, pos, cfg.xOffset or 0, cfg.yOffset or 0)
end

function M:Refresh()
	if not self.holder then return end

	local okP, mx, my = pcall(GetPlayerMapPosition, "player")
	if okP and mx and my and (mx ~= 0 or my ~= 0) then
		local name = UnitName and UnitName("player") or "Player"
		self.playerText:SetText(string.format("%s: %.1f, %.1f", name, mx * 100, my * 100))
	else
		self.playerText:SetText("")
	end

	local u, v = GetCursorMapPercent()
	if u and v and u >= 0 and u <= 1 and v >= 0 and v <= 1 then
		self.mouseText:SetText(string.format("Cursor: %.1f, %.1f", u * 100, v * 100))
	else
		self.mouseText:SetText("")
	end
end

-- "Smaller World Map": pulls WorldMapFrame out of Blizzard's fullscreen-
-- modal window system so it behaves like a normal, non-blocking panel
-- (game world stays visible/interactive behind it) instead of a
-- screen-darkening exclusive overlay. Ported from real ElvUI's
-- WorldMap.lua, adapted for this project: real ElvUI reparents onto
-- `E.UIParent`, a custom top-level frame it creates for its own scaling
-- purposes -- this from-scratch project has no such thing, so plain
-- `UIParent` is used instead. Also swapped the bare `HookScript(...)`
-- global call for `E:HookScript(...)` (AceHook-3.0) -- no bare HookScript
-- global is reliably present on UA (see Core/GameMenu.lua). One-shot,
-- like real ElvUI's own `E.global.general.
-- smallerWorldMap` check (not a live-toggle -- config marks it
-- reload-required). Entirely untested -- a bigger, riskier change than
-- the coordinate readout: reparents the map frame, disables its own
-- input-blocking, and rewrites its entry in Blizzard's UIPanelWindows
-- table.
function M:ApplySmallerWorldMap()
	if not E.global.general.smallerWorldMap then return end

	local frame = _G.WorldMapFrame
	if not frame then return end

	local blackout = _G.BlackoutWorld
	if blackout then pcall(blackout.SetTexture, blackout, nil) end

	pcall(frame.SetParent, frame, UIParent)
	pcall(frame.SetScale, frame, 1)
	if frame.EnableKeyboard then pcall(frame.EnableKeyboard, frame, false) end
	if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
	if frame.SetToplevel then pcall(frame.SetToplevel, frame) end

	if type(_G.UIPanelWindows) == "table" then
		_G.UIPanelWindows["WorldMapFrame"] = { area = "center", pushable = 0, whileDead = 1 }
	end

	local dropdown = _G.DropDownList1
	if dropdown then
		E:HookScript(dropdown, "OnShow", function()
			local okDD, ddScale = pcall(dropdown.GetScale, dropdown)
			local okUI, uiScale = pcall(UIParent.GetScale, UIParent)
			if okDD and okUI and ddScale ~= uiScale then
				pcall(dropdown.SetScale, dropdown, uiScale)
			end
		end)
	end

	local tooltip, guide = _G.WorldMapTooltip, _G.WorldMapPositioningGuide
	if tooltip and guide then
		local okLevel, guideLevel = pcall(guide.GetFrameLevel, guide)
		pcall(tooltip.SetFrameLevel, tooltip, (okLevel and guideLevel or 0) + 110)
	end
end

function M:Initialize()
	self:ApplySmallerWorldMap()

	if not E.global.general.WorldMapCoordinates.enable then
		return
	end

	local holder, playerText, mouseText = CreateCoordsHolder()
	if not holder then return end

	self.holder = holder
	self.playerText = playerText
	self.mouseText = mouseText

	self:PositionCoords()

	-- Fixed-interval AceTimer, not a per-frame OnUpdate script and not
	-- gated on WorldMapFrame:IsShown() -- see the file header for why
	-- (both are UnrealUI-documented-unreliable on UA). E (not M) is used
	-- since only the main AddOn object has AceTimer-3.0 mixed in.
	E:ScheduleRepeatingTimer(function() M:Refresh() end, 0.1)
end

E:RegisterInitialModule(M:GetName(), function() M:Initialize() end)
