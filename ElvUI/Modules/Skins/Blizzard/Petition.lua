-- Skins > Blizzard > Petition -- reskins the native PetitionFrame in place (a
-- guild charter: opened from the charter item or from another player's offer).
-- Same recipe as Gossip.lua and GuildRegistrar.lua.
--
-- Real 1.12.1 structure, per `FrameXML/PetitionFrame.xml`:
--
-- - `PetitionFrame` carries the four `UI-QuestGreeting-*` quadrants (ARTWORK)
--   as direct regions, so a non-recursive strip clears them. The texts sit in
--   the same layer as FontStrings, so the layer itself has to stay on.
-- - `PetitionFramePortrait` is the only BACKGROUND region of the frame.
-- - Every text uses the Quest fonts, black by default and invisible on a dark
--   panel. `PetitionFrame_Update` only ever calls SetText on them, so the
--   colours stay.
-- - `PetitionFrameRenameButton` is stretched between the Request and Cancel
--   buttons with a -3 overlap meant for the native button art. Flat buttons
--   need a gap there instead (real ElvUI's own numbers).

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Same 384x512 frame and same button row as GossipFrame, so the same panel
-- insets; the window lines up with the other NPC dialogues.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 15, -11, -30, 65
local BUTTON_GAP = 3

local TITLE_TEXTS = {
	"PetitionFrameCharterTitle",
	"PetitionFrameMasterTitle",
	"PetitionFrameMemberTitle",
}
local BODY_TEXTS = {
	"PetitionFrameCharterName",
	"PetitionFrameMasterName",
	"PetitionFrameInstructions",
}

local function Recolor(name, r, g, b)
	local text = _G[name]
	if text then pcall(text.SetTextColor, text, r, g, b) end
end

local function RecolorTexts()
	local accent = S.ACCENT_COLOR
	local i
	for i = 1, table.getn(TITLE_TEXTS) do
		Recolor(TITLE_TEXTS[i], accent[1], accent[2], accent[3])
	end
	for i = 1, table.getn(BODY_TEXTS) do
		Recolor(BODY_TEXTS[i], 1, 1, 1)
	end
	local count = tonumber(_G.MAX_PETITION_SIGNATURES) or 9
	for i = 1, count do
		Recolor("PetitionFrameMemberName"..i, 1, 1, 1)
	end
end

local function ApplyPetitionChrome(frame)
	S:StripTextures(frame, false)
	S:Kill(_G.PetitionFramePortrait)
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	RecolorTexts()

	local rename = _G.PetitionFrameRenameButton
	local request = _G.PetitionFrameRequestButton
	local cancel = _G.PetitionFrameCancelButton
	if rename and request and cancel then
		pcall(rename.ClearAllPoints, rename)
		pcall(rename.SetPoint, rename, "LEFT", request, "RIGHT", BUTTON_GAP, 0)
		pcall(rename.SetPoint, rename, "RIGHT", cancel, "LEFT", -BUTTON_GAP, 0)
	end

	S:StyleCloseButton(_G.PetitionFrameCloseButton)
	local close = _G.PetitionFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all pass: the four UIPanelButtonTemplate buttons.
	S:SkinChildren(frame)
end

local petitionSkinApplied = false
local function ApplyPetitionSkin()
	if petitionSkinApplied then return end
	local frame = _G.PetitionFrame
	if not frame then return end
	petitionSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere. The handle stops
	-- at the close button, which it would otherwise cover.
	S:MakeDraggable(frame, _G.PetitionFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyPetitionChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyPetitionChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyPetitionSkin()
end

S:AddBlizzardSkin("petition", LoadSkin)
