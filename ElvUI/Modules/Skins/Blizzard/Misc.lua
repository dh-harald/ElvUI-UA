-- Skins > Blizzard > Misc -- the small stand-alone native frames real
-- ElvUI groups under its single `misc` flag (`Blizzard/Misc.lua`,
-- `ElvUI-vanilla`). Its Game Menu and the three options windows are
-- skinned by their own files here, each under its own flag; this file
-- carries the rest.
--
-- StackSplitFrame (Shift+click on a stack), per `FrameXML/StackSplitFrame.xml`:
--
-- - One direct Texture region, the unnamed `UI-MoneyFrame` box art
--   (BACKGROUND), and one BACKGROUND FontString, `StackSplitText` (the
--   split amount, rewritten by native code on every change). Plain
--   non-recursive `S:StripTextures`; the text is promoted to OVERLAY so
--   the panel (parked on the frame's own base level) does not cover it.
-- - The inner box around the amount and the arrows is drawn as 1px edges
--   only, on a holder frame. Real ElvUI fills it with the same tone as the
--   window, so a fill adds nothing, and edges never overlap the frame's own
--   text, so their draw order against it does not matter.
-- - The arrows keep their native `MoneyFrame` art (real ElvUI does not
--   restyle them either); they are re-anchored symmetrically inside the
--   box, since the native right arrow straddles its edge.
-- - Strata raised from the native HIGH to DIALOG, as in real ElvUI: the
--   bag frames sit on DIALOG, and the split frame opens anchored to a bag
--   slot.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's inner box (`StackSplitFrame.bg1`) against the 172x96 frame.
local BOX_LEFT, BOX_TOP, BOX_RIGHT, BOX_BOTTOM = 10, -15, -10, 55
local ARROW_INSET = 4

local function StyleStackSplitBox(frame)
	if frame.elvSplitBox or not frame.elvBackground then return end
	local okBox, box = pcall(CreateFrame, "Frame", nil, frame.elvBackground)
	if not okBox or not box then return end
	pcall(box.SetPoint, box, "TOPLEFT", frame, "TOPLEFT", BOX_LEFT, BOX_TOP)
	pcall(box.SetPoint, box, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", BOX_RIGHT, BOX_BOTTOM)
	pcall(box.EnableMouse, box, false)
	S:CreateIconEdges(box)
	frame.elvSplitBox = box

	local left, right = _G.StackSplitLeftButton, _G.StackSplitRightButton
	if left then
		pcall(left.ClearAllPoints, left)
		pcall(left.SetPoint, left, "LEFT", box, "LEFT", ARROW_INSET, 0)
	end
	if right then
		pcall(right.ClearAllPoints, right)
		pcall(right.SetPoint, right, "RIGHT", box, "RIGHT", -ARROW_INSET, 0)
	end
end

local function ApplyStackSplitChrome(frame)
	S:StripTextures(frame, false)
	S:CreatePanel(frame)

	local text = _G.StackSplitText
	if text then pcall(text.SetDrawLayer, text, "OVERLAY") end

	StyleStackSplitBox(frame)

	S:StyleUIPanelButton(_G.StackSplitOkayButton)
	S:StyleUIPanelButton(_G.StackSplitCancelButton)
end

local stackSplitSkinApplied = false
local function ApplyStackSplitSkin()
	if stackSplitSkinApplied then return end
	local frame = _G.StackSplitFrame
	if not frame then return end
	stackSplitSkinApplied = true

	pcall(frame.SetFrameStrata, frame, "DIALOG")
	ApplyStackSplitChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyStackSplitChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyStackSplitSkin()
end

S:AddBlizzardSkin("misc", LoadSkin)
