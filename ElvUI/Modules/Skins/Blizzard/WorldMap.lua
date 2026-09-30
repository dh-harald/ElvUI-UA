-- Skins > Blizzard > WorldMap -- reskins the native WorldMapFrame chrome in
-- place. Same scope as real ElvUI's own `Skins/Blizzard/WorldMap.lua`
-- (ElvUI-vanilla): strip the frame's art, a panel over
-- `WorldMapPositioningGuide` (here a ring around the map, never under it),
-- a 1px border around the map canvas, the two dropdowns, the Zoom Out
-- button and the close button. The map canvas itself keeps its native look.
--
-- Real 1.12.1 structure, per `FrameXML/WorldMapFrame.xml`:
--
-- - `WorldMapFrame` (fullscreen, `setAllPoints`, no parent) carries the art
--   as DIRECT regions: `BlackoutWorld` (BACKGROUND, the black sheet hiding
--   the game world), twelve unnamed 256x256 `UI-WorldMap-*` pieces
--   (ARTWORK) laid out around the frame's centre, and one unnamed ARTWORK
--   FontString (the "World Map" title). A non-recursive `S:StripTextures`
--   takes every Texture region -- `BlackoutWorld` included, like real
--   ElvUI's `E:StripTextures`, so the world stays visible around the map.
-- - `WorldMapPositioningGuide` is an empty 1024x768 frame centred on
--   `WorldMapFrame`; the twelve art pieces cover exactly its footprint, and
--   every control is anchored to it. The panel strips are children of
--   `WorldMapFrame` itself (not of the guide), anchored on the guide: as
--   guide children they would sit ABOVE the title FontString, which is a
--   region of `WorldMapFrame`; at `WorldMapFrame`'s own level the title
--   only needs promoting to OVERLAY.
-- - `WorldMapDetailFrame` holds the map tiles as its own BACKGROUND
--   regions, and `WorldMapButton` (its sibling, anchored on it) holds the
--   player/party/raid/POI/flag frames. Neither is chrome: both are kept out
--   of the end-of-pass sweep (dropdowns other addons put on the canvas are
--   styled by name instead). The border around the canvas is an edge-only
--   surface (fill alpha 0), so it can sit above the tiles without covering
--   them.
-- - `WorldMapContinentDropDown`/`WorldMapZoneDropDown` re-run
--   `UIDropDownMenu_SetWidth(130)` from their own OnShow; the box, text and
--   button are anchored frame-relative, so that needs no re-apply.
--
-- The art is static (nothing native re-textures it on show), so the skin is
-- applied once, with no OnShow hook.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Functional map content, not chrome -- see file header.
S.autoSkinSkipNames["WorldMapDetailFrame"] = true
S.autoSkinSkipNames["WorldMapButton"] = true

-- Fill alpha 0: the border is drawn, the map tiles under it are not covered.
local CANVAS_EDGE_COLOR = { 0, 0, 0, 0 }

local function PromoteTitle(frame)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "FontString" then
			pcall(region.SetDrawLayer, region, "OVERLAY")
		end
	end
end

-- The map canvas inside the 1024x768 guide (`WorldMapDetailFrame`, 1002x668
-- at the guide's `TOP -502,-69`): 10 in from the left, 12 from the right,
-- 69 from the top, 31 from the bottom.
local CANVAS_LEFT, CANVAS_RIGHT, CANVAS_TOP, CANVAS_BOTTOM = 10, 12, 69, 31

-- One borderless panel-coloured strip between two guide-relative points.
local function CreateStrip(frame, guide, p1, x1, y1, p2, x2, y2)
	local okStrip, strip = pcall(CreateFrame, "Frame", nil, frame)
	if not okStrip or not strip then return end
	pcall(strip.SetPoint, strip, "TOPLEFT", guide, p1, x1, y1)
	pcall(strip.SetPoint, strip, "BOTTOMRIGHT", guide, p2, x2, y2)
	pcall(strip.SetBackdrop, strip, S.PLAIN_BACKDROP)
	local c = S.PANEL_COLOR
	pcall(strip.SetBackdropColor, strip, c[1], c[2], c[3], c[4] or 1)
	pcall(strip.SetBackdropBorderColor, strip, 0, 0, 0, 0)
	pcall(strip.EnableMouse, strip, false)
	local okLevel, level = pcall(frame.GetFrameLevel, frame)
	pcall(strip.SetFrameLevel, strip, (okLevel and tonumber(level)) or 1)
	strip.elvSurface = true
end

-- The window surface is a ring around the map canvas, never a sheet under
-- it: four fill strips plus one edge-only outline over the whole guide. The
-- map stays uncovered whatever frame levels the canvas and this surface end
-- up with (a reparent of `WorldMapFrame`, e.g. "Smaller World Map", moves
-- the frame's own level but not necessarily its children's).
local function CreateWindowFrame(frame, guide)
	CreateStrip(frame, guide, "TOPLEFT", 0, 0, "TOPRIGHT", 0, -CANVAS_TOP)
	CreateStrip(frame, guide, "BOTTOMLEFT", 0, CANVAS_BOTTOM, "BOTTOMRIGHT", 0, 0)
	CreateStrip(frame, guide, "TOPLEFT", 0, -CANVAS_TOP, "BOTTOMLEFT", CANVAS_LEFT, CANVAS_BOTTOM)
	CreateStrip(frame, guide, "TOPRIGHT", -CANVAS_RIGHT, -CANVAS_TOP, "BOTTOMRIGHT", 0, CANVAS_BOTTOM)

	local outline = S:CreateSurface(frame, CANVAS_EDGE_COLOR)
	if not outline then return nil end
	pcall(outline.ClearAllPoints, outline)
	pcall(outline.SetAllPoints, outline, guide)
	return outline
end

-- Real ElvUI's `S:HandleDropDownBox` geometry: the box starts 20 in from the
-- frame's left edge and ends 2 past the arrow button, which sits 10 in from
-- the frame's right edge. The native template instead draws its box inside
-- 25px transparent caps and lets neighbouring dropdowns overlap by 33, so a
-- box covering the whole frame runs into its neighbour. The text and button
-- anchors are frame-relative, so they follow the native
-- `UIDropDownMenu_SetWidth(130)` each dropdown re-runs on show.
local function LayoutDropDown(dd)
	if not dd then return end
	local okName, name = pcall(dd.GetName, dd)
	if not okName or not name then return end
	local button, text, box = _G[name .. "Button"], _G[name .. "Text"], dd.elvBackground
	if not button then return end

	-- Text offsets are taken from the button's RIGHT edge (-26 = 2px left of
	-- the native 24px button): `UIDropDownMenu_SetButtonWidth` can widen the
	-- button over the whole box (pfQuest's map dropdown, on every show), and
	-- its LEFT edge then no longer marks where the arrow is.
	pcall(button.ClearAllPoints, button)
	pcall(button.SetPoint, button, "RIGHT", dd, "RIGHT", -10, 3)
	if text then
		pcall(text.ClearAllPoints, text)
		pcall(text.SetPoint, text, "RIGHT", button, "RIGHT", -26, 0)
	end
	-- `UIDropDownMenu_JustifyText("RIGHT")` re-anchors the text to the
	-- (stripped) `$parentRight` art at `RIGHT -43,+2`; pfQuest calls it on
	-- every show of its map dropdown. Pinning that art to the button makes
	-- the native re-anchor land the text at the same spot as above.
	local rightArt = _G[name .. "Right"]
	if rightArt then
		pcall(rightArt.ClearAllPoints, rightArt)
		pcall(rightArt.SetPoint, rightArt, "RIGHT", button, "RIGHT", 17, -2)
	end
	if box then
		pcall(box.ClearAllPoints, box)
		pcall(box.SetPoint, box, "TOPLEFT", dd, "TOPLEFT", 20, -2)
		pcall(box.SetPoint, box, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
	end
end

-- Real ElvUI's offsets for the row: 4px gaps between the two boxes and the
-- Zoom Out button, given the box geometry above.
local function LayoutControlRow()
	local continent, zone, zoomOut = _G.WorldMapContinentDropDown, _G.WorldMapZoneDropDown, _G.WorldMapZoomOutButton
	if continent and zone then
		pcall(zone.ClearAllPoints, zone)
		pcall(zone.SetPoint, zone, "LEFT", continent, "RIGHT", -24, 0)
	end
	if zone and zoomOut then
		pcall(zoomOut.ClearAllPoints, zoomOut)
		pcall(zoomOut.SetPoint, zoomOut, "LEFT", zone, "RIGHT", -4, 3)
	end
end

-- Dropdowns other addons attach to the map canvas (e.g. pfQuest's
-- `pfQuestMapDropdown`, a child of `WorldMapButton`). The canvas itself is
-- kept out of the generic sweep, so its direct children are checked here for
-- the dropdown template's named parts and nothing else is touched. Already
-- styled ones are skipped, so this can re-run on every ADDON_LOADED.
local function StyleCanvasDropDowns()
	local canvas = _G.WorldMapButton
	if not canvas then return end
	local ok, kids = pcall(function() return { canvas:GetChildren() } end)
	if not ok or type(kids) ~= "table" then return end
	local i
	for i = 1, table.getn(kids) do
		local kid = S:ResolveWidget(kids[i])
		local okName, name = pcall(kid.GetName, kid)
		if okName and name and name ~= "" and not kid.elvBackground
			and _G[name .. "Middle"] and _G[name .. "Button"] and _G[name .. "Text"] then
			S:StyleDropDownBox(kid)
			LayoutDropDown(kid)
		end
	end
end

-- On Unreal Azeroth an addon's ADDON_LOADED can arrive after this skin has
-- run at login, so a dropdown that addon creates from its ADDON_LOADED
-- handler (pfQuest does) does not exist yet on the first pass. A plain
-- event frame, not the Skins module's AceEvent registration, which
-- `S:WaitForGlobal` owns.
local function WatchCanvasDropDowns()
	local ok, watcher = pcall(CreateFrame, "Frame")
	if not ok or not watcher then return end
	pcall(watcher.RegisterEvent, watcher, "ADDON_LOADED")
	pcall(watcher.SetScript, watcher, "OnEvent", function() pcall(StyleCanvasDropDowns) end)
end

local function CreateCanvasBorder(detail)
	local edge = S:CreateSurface(detail, CANVAS_EDGE_COLOR, -1, 1, 1, -1, true)
	if not edge then return end
	-- Above the tiles, and above `WorldMapButton`'s own level, so no map
	-- overlay can paint over the edge. The surface never takes the mouse.
	local okLevel, level = pcall(detail.GetFrameLevel, detail)
	pcall(edge.SetFrameLevel, edge, ((okLevel and tonumber(level)) or 1) + 10)
end

local function StyleCloseButton(panel)
	local close = _G.WorldMapFrameCloseButton
	if not close then return end
	S:StyleCloseButton(close)
	-- Native anchor (`TOP` of the guide `+516,+4`) puts the button outside
	-- the guide's top-right corner, i.e. outside the panel.
	pcall(close.ClearAllPoints, close)
	pcall(close.SetPoint, close, "TOPRIGHT", panel, "TOPRIGHT", -4, -4)
end

local worldMapSkinApplied = false
local function ApplyWorldMapSkin()
	if worldMapSkinApplied then return end
	local frame = _G.WorldMapFrame
	local guide = _G.WorldMapPositioningGuide
	if not frame or not guide then return end

	S:StripTextures(frame)
	local outline = CreateWindowFrame(frame, guide)
	if not outline then return end
	worldMapSkinApplied = true
	PromoteTitle(frame)

	if _G.WorldMapDetailFrame then CreateCanvasBorder(_G.WorldMapDetailFrame) end

	S:StyleDropDownBox(_G.WorldMapContinentDropDown)
	S:StyleDropDownBox(_G.WorldMapZoneDropDown)
	S:StyleUIPanelButton(_G.WorldMapZoomOutButton)
	StyleCloseButton(outline)
	StyleCanvasDropDowns()
	WatchCanvasDropDowns()

	-- Catch-all for anything this server adds to the map window.
	S:SkinChildren(frame)

	-- After the sweep: it re-runs `S:StyleDropDownBox` on the dropdowns it
	-- recognises, which re-anchors the box to the native art.
	LayoutDropDown(_G.WorldMapContinentDropDown)
	LayoutDropDown(_G.WorldMapZoneDropDown)
	LayoutControlRow()
end

S:AddBlizzardSkin("worldmap", ApplyWorldMapSkin)
