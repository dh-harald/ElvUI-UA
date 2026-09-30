-- World Map module.
--
-- Real ElvUI's own WorldMap.lua (ElvUI-vanilla/ElvUI/Modules/Maps/
-- WorldMap.lua) does two things: a player/cursor coordinate readout
-- (CONFIRMED WORKING in-game -- see CreateCoordsHolder/Refresh below) and
-- "Smaller World Map" (ApplySmallerWorldMap below: the map in a draggable
-- window). The map
-- window's chrome is styled separately, by Skins/Blizzard/WorldMap.lua
-- (`E.private.skins.blizzard.worldmap`).
--
-- UA construction pattern for the coordinate readout deliberately copied
-- from UnrealUI's OWN worldmap.lua (UnrealUI/modules/worldmap.lua),
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

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
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
		self.mouseText:SetText(string.format(L["Cursor"]..": %.1f, %.1f", u * 100, v * 100))
	else
		self.mouseText:SetText("")
	end
end

-- "Smaller World Map": the map in a draggable window of its content's size
-- (the 1024x768 `WorldMapPositioningGuide` holding the 1002x668 map) instead
-- of a fullscreen overlay. `WorldMapFrame` is reparented into a holder and
-- stays wherever the holder is: neither client moves it back on open.
--
-- Legacy client: real ElvUI's route (`UIPanelWindows` area "center") cannot
-- be used, because `SetCenterFrame` re-anchors the frame to
-- `TOPLEFT 384,-104` on every open. The frame is taken out of
-- `UIPanelWindows` altogether instead -- `ShowUIPanel`/`HideUIPanel` then
-- just Show()/Hide() it, and `UIParent` is no longer hidden -- and Escape
-- closes it through `UISpecialFrames`. The holder sits under `UIParent`, so
-- the map follows the UI scale; keyboard and mouse on the map frame are off,
-- as in real ElvUI, so the game keeps its input around the window.
--
-- Unreal Azeroth: the client's panel handling does not consult
-- `UIPanelWindows`, and opening the map hides `UIParent` regardless, so the
-- holder has no parent (like the native `WorldMapFrame`). `SetScale` has no
-- effect there (effective scale stays 1), so the window is always full size.
-- The character keeps moving under the open map, so input is left as is.
--
-- One-shot, like real ElvUI's own `smallerWorldMap` check (the config marks
-- it reload-required).
local MAP_WIDTH, MAP_HEIGHT = 1024, 768

local function CreateWindowHolder(isUA)
	local parent = (not isUA) and UIParent or nil
	local ok, holder = pcall(CreateFrame, "Frame", "ElvUIWorldMapHolder", parent)
	if not ok or not holder then return nil end
	holder:SetWidth(MAP_WIDTH)
	holder:SetHeight(MAP_HEIGHT)
	holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	-- The map's own strata; the drag handle inherits it from the holder.
	pcall(holder.SetFrameStrata, holder, "FULLSCREEN")
	pcall(holder.SetClampedToScreen, holder, true)
	return holder
end

-- Legacy-only half: out of the panel manager, Escape via UISpecialFrames,
-- plus real ElvUI's dropdown-scale and tooltip-level fixes.
local function DetachFromPanelManager(frame)
	pcall(frame.SetScale, frame, 1)
	if frame.EnableKeyboard then pcall(frame.EnableKeyboard, frame, false) end
	if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
	if frame.SetToplevel then pcall(frame.SetToplevel, frame) end

	if type(_G.UIPanelWindows) == "table" then
		_G.UIPanelWindows["WorldMapFrame"] = nil
	end
	if type(_G.UISpecialFrames) == "table" then
		table.insert(_G.UISpecialFrames, "WorldMapFrame")
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

function M:ApplySmallerWorldMap()
	if not E.global.general.smallerWorldMap then return end

	local frame = _G.WorldMapFrame
	if not frame then return end

	local isUA = ElvUI.Compat.isUA
	local holder = CreateWindowHolder(isUA)
	if not holder then return end

	pcall(frame.SetParent, frame, holder)
	pcall(frame.ClearAllPoints, frame)
	pcall(frame.SetAllPoints, frame, holder)

	-- `WorldMapFrame_OnLoad` sizes this black sheet to the whole screen from
	-- the frame's BOTTOMLEFT; inside the holder it would spill over the game
	-- world on the right and above.
	local blackout = _G.BlackoutWorld
	if blackout then
		pcall(blackout.SetTexture, blackout, nil)
		pcall(blackout.Hide, blackout)
	end

	if not isUA then DetachFromPanelManager(frame) end

	-- Ends at the close button, so the handle never covers it.
	local S = E:GetModule("Skins", true)
	if S and S.MakeDraggable then
		S:MakeDraggable(holder, _G.WorldMapFrameCloseButton)
	end

	self.windowHolder = holder
end

-- Zone dropdown in alphabetical order. Unreal Azeroth's `GetMapZones`
-- returns a continent's zones unsorted (the legacy client returns them
-- sorted), and the native dropdown lists them in that order, using the
-- list POSITION both as the `SetMapZoom` zone index and as the selected
-- entry (`UIDropDownMenu_SetSelectedID(..., GetCurrentMapZone())`). Only the
-- two map-dropdown globals are replaced, each keeping a position -> zone
-- index table so clicks and the check mark still resolve to the real
-- index. `GetMapZones` itself is left alone: other addons address zones by
-- that index. An already sorted list maps to itself, so where the client
-- sorts, nothing changes.
local zoneOrder = {}

local function ZoneEntryLess(a, b)
	local la, lb = string.lower(a.name), string.lower(b.name)
	if la ~= lb then return la < lb end
	return a.index < b.index
end

-- Rebuilds `zoneOrder` for the current continent and returns the sorted
-- entries ({ name, index }).
local function BuildZoneOrder()
	local ok, zones = pcall(function() return { GetMapZones(GetCurrentMapContinent()) } end)
	local entries = {}
	for k in pairs(zoneOrder) do zoneOrder[k] = nil end
	if not ok or type(zones) ~= "table" then return entries end

	local n = table.getn(zones)
	local i
	for i = 1, n do
		entries[i] = { name = tostring(zones[i]), index = i }
	end
	table.sort(entries, ZoneEntryLess)
	for i = 1, n do
		zoneOrder[i] = entries[i].index
	end
	return entries
end

local function ZoneButton_OnClick()
	local pos = this:GetID()
	UIDropDownMenu_SetSelectedID(_G.WorldMapZoneDropDown, pos)
	SetMapZoom(GetCurrentMapContinent(), zoneOrder[pos] or pos)
end

local function ZoneDropDown_Initialize()
	local entries = BuildZoneOrder()
	local i
	for i = 1, table.getn(entries) do
		UIDropDownMenu_AddButton({ text = entries[i].name, func = ZoneButton_OnClick })
	end
end

local function UpdateZoneDropDownText()
	local dropdown = _G.WorldMapZoneDropDown
	local zone = GetCurrentMapZone()
	if zone == 0 then
		UIDropDownMenu_ClearAll(dropdown)
		return
	end
	BuildZoneOrder()
	for pos, index in pairs(zoneOrder) do
		if index == zone then
			UIDropDownMenu_SetSelectedID(dropdown, pos)
			return
		end
	end
	UIDropDownMenu_SetSelectedID(dropdown, zone)
end

-- The native dropdown's OnShow/OnEvent look both globals up by name on
-- every call, so replacing them takes effect from the next map open.
function M:SortZoneDropDown()
	if type(_G.WorldMapZoneDropDown_Initialize) ~= "function"
		or type(_G.WorldMap_UpdateZoneDropDownText) ~= "function"
		or type(GetMapZones) ~= "function" or type(SetMapZoom) ~= "function" then
		return
	end
	_G.WorldMapZoneDropDown_Initialize = ZoneDropDown_Initialize
	_G.WorldMap_UpdateZoneDropDownText = UpdateZoneDropDownText
end

function M:Initialize()
	self:ApplySmallerWorldMap()
	self:SortZoneDropDown()

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
