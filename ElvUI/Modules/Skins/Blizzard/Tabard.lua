-- Skins > Blizzard > Tabard -- reskins the native TabardFrame in place (the
-- guild tabard designer). Strips the native chrome, draws an elvBackground
-- child frame and lets the automatic sweep pick up the two panel buttons.
--
-- Real 1.12.1 structure, per `FrameXML/TabardFrame.xml`:
--
-- - `TabardFrame` holds its art as direct regions on four layers: the portrait
--   (BACKGROUND), the four paperdoll quadrants (BORDER), `TabardFrameBackground`
--   (ARTWORK) and the `TabardFrameOuterFrame*` pieces (OVERLAY). The strip is
--   local, because the same OVERLAY layer holds the four `TabardFrameEmblem*`
--   regions: the live preview of the design, rewritten by
--   `TabardFrame_UpdateTextures` on every change, which has to stay.
-- - Three things are anchored to the stripped art, and a widget anchored to a
--   hidden texture does not reliably keep its place on Unreal Azeroth: the
--   emblems and `TabardFrameCostFrame` (to `TabardFrameOuterFrameTopRight`),
--   the first customization row (to `TabardFrameCustomizationBorder`), and each
--   row's text and arrows (to the row's own `$parentMiddle/Left/Right`). All are
--   moved to the frame or the row, at the positions the native chain resolves
--   to where the look does not change.
-- - `TabardFrameCostFrame` carries a native `<Backdrop>`, removed by the strip
--   and replaced with a field.
-- - The rotate buttons sit in the model's BOTTOMLEFT corner, real ElvUI's spot.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's numbers for this frame.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -12, -32, 74
local NUM_CUSTOMIZATION_ROWS = 5
local ROW_ARROW_SIZE = 20
local ROW_ARROW_GAP = 2

-- TOPLEFT-relative positions the native anchor chains resolve to.
local EMBLEM_RIGHT, EMBLEM_TOP = 374, -53
local COST_RIGHT, COST_TOP = 332, -78
local FIRST_ROW_LEFT, FIRST_ROW_TOP = 167, -271

local EMBLEM_NAMES = {
	TabardFrameEmblemTopLeft = true,
	TabardFrameEmblemTopRight = true,
	TabardFrameEmblemBottomLeft = true,
	TabardFrameEmblemBottomRight = true,
}

-- Manual strip, not `S:StripTextures`: that helper blanks every direct Texture
-- region, and the emblem preview must survive.
local function StripChrome(frame)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "Texture" then
			local okName, name = pcall(region.GetName, region)
			if not (okName and name and EMBLEM_NAMES[name]) then
				pcall(region.SetTexture, region, nil)
				pcall(region.Hide, region)
				region.Show = E.noop
			end
		end
	end
end

local function Reanchor(widget, point, relative, relativePoint, x, y)
	if not widget then return end
	pcall(widget.ClearAllPoints, widget)
	pcall(widget.SetPoint, widget, point, relative, relativePoint, x, y)
end

local function StyleArrow(button, iconName, point, row)
	if not button then return end
	S:StyleNextPrevButton(button, iconName)
	pcall(button.SetWidth, button, ROW_ARROW_SIZE)
	pcall(button.SetHeight, button, ROW_ARROW_SIZE)
	Reanchor(button, point, row, point, 0, 0)
end

local function StyleCustomizationRow(index)
	local name = "TabardFrameCustomization"..index
	local row = _G[name]
	if not row then return end

	S:StripTextures(row, false)
	local inset = ROW_ARROW_SIZE + ROW_ARROW_GAP
	S:CreateField(row, inset, 0, -inset, 0)

	StyleArrow(_G[name.."LeftButton"], "LEFT", "LEFT", row)
	StyleArrow(_G[name.."RightButton"], "RIGHT", "RIGHT", row)

	-- BACKGROUND natively, which puts it under the row's own field.
	local text = _G[name.."Text"]
	if text then
		pcall(text.SetDrawLayer, text, "OVERLAY")
		Reanchor(text, "CENTER", row, "CENTER", 0, 0)
	end
end

local function StyleCostFrame(frame)
	local cost = _G.TabardFrameCostFrame
	if not cost then return end
	S:StripTextures(cost, false)
	S:CreateField(cost)
	Reanchor(cost, "TOPRIGHT", frame, "TOPLEFT", COST_RIGHT, COST_TOP)
end

-- Natively centred on the full 384px frame with an offset for the portrait,
-- which sits right of the panel's own centre once the portrait is gone.
local function CentreHeaderTexts(frame)
	local panel = frame.elvBackground
	if not panel then return end
	Reanchor(_G.TabardFrameNameText, "TOP", panel, "TOP", 0, -4)
	Reanchor(_G.TabardFrameGreetingText, "TOP", panel, "TOP", 0, -27)
end

local function StyleRotateButtons()
	local model = _G.TabardModel
	local left = _G.TabardCharacterModelRotateLeftButton
	local right = _G.TabardCharacterModelRotateRightButton
	S:StyleModelRotateButtons(left, right)
	Reanchor(left, "BOTTOMLEFT", model, "BOTTOMLEFT", 4, 4)
	Reanchor(right, "TOPLEFT", left, "TOPRIGHT", 4, 0)
end

local function ApplyTabardChrome(frame)
	StripChrome(frame)
	S:Kill(_G.TabardFramePortrait)
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
	S:StripTextures(_G.TabardFrameCustomizationFrame, false)

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	Reanchor(_G.TabardFrameEmblemTopRight, "TOPRIGHT", frame, "TOPLEFT", EMBLEM_RIGHT, EMBLEM_TOP)
	StyleCostFrame(frame)
	CentreHeaderTexts(frame)

	Reanchor(_G.TabardFrameCustomization1, "TOPLEFT", frame, "TOPLEFT", FIRST_ROW_LEFT, FIRST_ROW_TOP)
	local i
	for i = 1, NUM_CUSTOMIZATION_ROWS do
		StyleCustomizationRow(i)
	end

	StyleRotateButtons()

	S:StyleCloseButton(_G.TabardFrameCloseButton)
	local close = _G.TabardFrameCloseButton
	if close and frame.elvBackground then
		Reanchor(close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all pass: the Accept and Cancel buttons.
	S:SkinChildren(frame)
end

local tabardSkinApplied = false
local function ApplyTabardSkin()
	if tabardSkinApplied then return end
	local frame = _G.TabardFrame
	if not frame then return end
	tabardSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere. The handle stops
	-- at the close button, which it would otherwise cover.
	S:MakeDraggable(frame, _G.TabardFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyTabardChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyTabardChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyTabardSkin()
end

S:AddBlizzardSkin("tabard", LoadSkin)
