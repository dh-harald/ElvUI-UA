-- Skins > Blizzard > GuildRegistrar -- reskins the native GuildRegistrarFrame
-- in place (the Guild Master NPC window: buy a charter, turn one in). Same
-- recipe as Gossip.lua: strip the native chrome, draw an elvBackground child
-- frame, let the automatic sweep pick up the generic controls.
--
-- Real 1.12.1 structure, per `FrameXML/GuildRegistrarFrame.xml`:
--
-- - `GuildRegistrarFrame` carries the four `UI-QuestGreeting-*` quadrants
--   (ARTWORK) as direct regions, so a non-recursive strip clears them.
-- - `GuildRegistrarFramePortrait` is the only BACKGROUND region of the frame.
--   `GuildRegistrar_OnShow` feeds it through `SetPortraitTexture` on every
--   show, so the whole layer stays disabled on top of `S:Kill`.
-- - Two child frames share the window and swap on the native side:
--   `GuildRegistrarGreetingFrame` (service list, one `UI-Quest-BotLeftPatch`
--   region) and `GuildRegistrarPurchaseFrame` (name box, cost, buy button,
--   no texture regions).
-- - `AvailableServicesText`, `GuildRegistrarPurchaseText` and the labels of
--   `GuildRegistrarButton1-2` use the Quest fonts, black by default and
--   invisible on a dark panel.
-- - `GuildRegistrarFrameEditBox` is 32 tall to fit its chat-input art. It is
--   brought down to the field height real ElvUI uses; its TOPLEFT anchor
--   stays, so the box keeps its place under the cost label.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Same 384x512 frame and same button row as GossipFrame, so the same panel
-- insets; the window lines up with the other NPC dialogues.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 15, -11, -30, 65
local EDIT_BOX_HEIGHT = 20
local NUM_SERVICE_BUTTONS = 2

local function RecolorTexts()
	local accent = S.ACCENT_COLOR
	local services = _G.AvailableServicesText
	if services then pcall(services.SetTextColor, services, accent[1], accent[2], accent[3]) end

	local purchase = _G.GuildRegistrarPurchaseText
	if purchase then pcall(purchase.SetTextColor, purchase, 1, 1, 1) end

	local i
	for i = 1, NUM_SERVICE_BUTTONS do
		local button = _G["GuildRegistrarButton"..i]
		if button then pcall(button.SetTextColor, button, accent[1], accent[2], accent[3]) end
	end
end

local function ApplyRegistrarChrome(frame)
	S:StripTextures(frame, false)
	S:StripTextures(_G.GuildRegistrarGreetingFrame, false)
	S:Kill(_G.GuildRegistrarFramePortrait)
	pcall(frame.DisableDrawLayer, frame, "BACKGROUND")

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	RecolorTexts()

	local box = _G.GuildRegistrarFrameEditBox
	if box then
		S:StyleEditBox(box)
		pcall(box.SetHeight, box, EDIT_BOX_HEIGHT)
	end

	S:StyleCloseButton(_G.GuildRegistrarFrameCloseButton)
	local close = _G.GuildRegistrarFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all pass: the Cancel and Purchase buttons of both child frames.
	S:SkinChildren(frame)
end

local registrarSkinApplied = false
local function ApplyRegistrarSkin()
	if registrarSkinApplied then return end
	local frame = _G.GuildRegistrarFrame
	if not frame then return end
	registrarSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere. The handle stops
	-- at the close button, which it would otherwise cover.
	S:MakeDraggable(frame, _G.GuildRegistrarFrameCloseButton)
	pcall(frame.SetUserPlaced, frame, true)

	ApplyRegistrarChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyRegistrarChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyRegistrarSkin()
end

S:AddBlizzardSkin("guildregistrar", LoadSkin)
