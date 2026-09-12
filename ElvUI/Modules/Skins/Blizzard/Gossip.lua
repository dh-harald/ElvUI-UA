-- Skins > Blizzard > Gossip -- reskins the native GossipFrame in place (the
-- NPC dialogue window opened by talking to a gossip-enabled NPC). Same
-- recipe family as QuestLog.lua/Binding.lua: strip the native chrome, draw
-- an elvBackground child frame (never SetBackdrop the native frame
-- itself), let the automatic sweep pick up the generic controls.
--
-- Real 1.12.1 structure, per `FrameXML/GossipFrame.xml` and
-- `GossipFrame.lua`. Not yet verified against the live client -- if a name
-- below never resolves, that is the first thing to check, not a mechanism
-- failure.
--
-- - `GossipFrame`'s only own direct region is `GossipFramePortrait`
--   (ARTWORK layer) -- killed with `S:Kill`, not `S:StripTextures`: a
--   portrait fed by `SetPortraitTexture` is the one texture class in this
--   project that never responded to a plain strip (`CharacterFramePortrait`,
--   same fix).
-- - All the parchment/corner art (four `UI-QuestGreeting-*` quadrants, four
--   `$parentMaterial*` pieces, one `UI-Quest-BotLeftPatch`) lives on
--   `GossipFrameGreetingPanel`, a nested child frame -- a single
--   NON-recursive strip of that one frame clears all nine regions, since
--   every piece is a direct region of it, none nested further.
-- - Text colour is load-bearing here, same reason as QuestLog: both
--   `GossipGreetingText` and every `GossipTitleButton<n>` label inherit
--   `QuestFont`, pure black by default (`FrameXML/Fonts.xml`) -- invisible
--   on a dark panel. `GossipFrameNpcNameText` inherits `GameFontHighlight`,
--   already light, left alone.
-- - The title button list (`GossipTitleButton1..NUMGOSSIPBUTTONS`) is
--   fully native-driven: `GossipFrameUpdate` (FrameXML) rewrites text, icon
--   and Show/Hide on every GOSSIP_SHOW and on every option pick, but never
--   touches an already-set `SetTextColor` on these persistent,
--   never-destroyed FontStrings -- so colouring all of them once, up
--   front, is enough (matches real ElvUI's own Gossip.lua, which does the
--   same). If a future report shows a button reverting to black after a
--   chained gossip option, that call needs to move into the update path
--   instead -- not yet observed, no code written for it speculatively.
-- - Each title button's own `$parentGossipIcon` (Available/Active/plain
--   option indicator) is left untouched -- it is functional, not
--   decorative, and the client keeps writing a fresh texture path to it on
--   every update.
--
-- SCOPE: outer chrome, the panel and drag handle, the close button, the
-- greeting scroll frame's scrollbar, text visibility.
--
-- Deliberately NOT done here, each its own window: `ItemTextFrame` (the
-- "read this" book/letter popup -- real ElvUI bundles it into the same
-- file/flag, structurally near-identical to this one, the next candidate
-- for this flag) and the `QuestFrame` dialogue side (Detail/Progress/Reward
-- -- shares this project's existing `quest` flag with QuestLog.lua, see
-- that file's own header; tied to the same font-object recolouring work,
-- a separate pass).

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- Left/top/right measured off the native, unmodified 384x512 frame -- real
-- ElvUI's own numbers for those three (`Blizzard/Gossip.lua`,
-- `source/ElvUI-vanilla`) apply directly since this window is never
-- resized, unlike QuestLogFrame. The native `HitRectInsets` (right=30,
-- bottom=70) already exclude the dead area on the right edge and are left
-- untouched there.
--
-- Bottom is NOT real ElvUI's own number (0, flush to the true frame
-- bottom): live on UA that left a bare dark slab hanging well below
-- `GossipFrameGreetingGoodbyeButton` with nothing on it. Confirmed live
-- (`GossipFrame:GetBottom()` 152, `GossipFrameGreetingGoodbyeButton
-- :GetBottom()` 225) that the button's bottom edge sits 73px above the
-- true frame bottom, matching the XML anchor (`BOTTOMRIGHT -39,73`)
-- exactly -- the rendering itself was never in question, only where to
-- crop below the button. `65` applies this project's own standing margin
-- below the lowest button (QuestLogFrame's panel: button bottom edge at
-- 54, panel stops at 46 -- an 8px gap), so this window's crop lands on
-- the same convention: 73 - 8 = 65.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 15, -11, -30, 65

local function RecolorTitleButtons()
	local count = tonumber(_G.NUMGOSSIPBUTTONS) or 32
	local i
	for i = 1, count do
		local button = _G["GossipTitleButton"..i]
		if button then
			pcall(button.SetTextColor, button, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
		end
	end
end

local function ApplyGossipChrome(frame)
	S:StripTextures(_G.GossipFrameGreetingPanel, false)
	S:Kill(_G.GossipFramePortrait)

	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	S:HandleScrollBar(_G.GossipGreetingScrollFrameScrollBar)

	local greeting = _G.GossipGreetingText
	if greeting then pcall(greeting.SetTextColor, greeting, 1, 1, 1) end
	RecolorTitleButtons()

	S:StyleCloseButton(_G.GossipFrameCloseButton)
	-- Re-anchored to the PANEL, not left on the frame: the native anchor
	-- is a CENTER point 42px left / 31px up from GossipFrame's own
	-- TOPRIGHT, which sits slightly outside this panel's own corner
	-- (PANEL_RIGHT,PANEL_TOP = -30,-11) -- same class of gap confirmed
	-- live on MerchantFrame's identically-anchored close button. Real
	-- ElvUI's own Gossip.lua repositions this exact button too, for the
	-- same reason.
	local close = _G.GossipFrameCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	-- Catch-all pass -- picks up GossipFrameGreetingGoodbyeButton (plain
	-- UIPanelButtonTemplate).
	S:SkinChildren(frame)
end

local gossipSkinApplied = false
local function ApplyGossipSkin()
	if gossipSkinApplied then return end
	local frame = _G.GossipFrame
	if not frame then return end
	gossipSkinApplied = true

	-- `movable="true"` in the XML but no drag script anywhere, same gap as
	-- QuestLogFrame.
	local handle = S:MakeDraggable(frame)
	if handle then
		pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT, 0)
	end
	pcall(frame.SetUserPlaced, frame, true)

	ApplyGossipChrome(frame)

	local ok = S:TryHookScript(frame, "OnShow", function() ApplyGossipChrome(frame) end)
	if not ok then E:Print("Skins (gossip): GossipFrame OnShow hook failed to install") end
end

local function LoadSkin()
	ApplyGossipSkin()
end

-- `gossip`, real ElvUI's own flag name (`Blizzard/Gossip.lua`) -- kept
-- separate from `quest` (QuestLog.lua's flag, shared with the eventual
-- QuestFrame dialogue skin) so an imported profile's per-window toggles
-- keep meaning the same thing they do in real ElvUI.
S:AddBlizzardSkin("gossip", LoadSkin)
