-- Skins > Blizzard > Greeting -- reskins `QuestFrameGreetingPanel`, the
-- multi-quest "here is everything I have for you" list shown via
-- `QuestFrame` (an NPC with several available/active quests but no gossip
-- dialogue). Distinct from `GossipFrame`'s own greeting panel
-- (`Gossip.lua`) -- same visual shape, different native frame, and real
-- ElvUI keeps them as two entirely separate files/flags (`Blizzard/
-- Gossip.lua` vs `Blizzard/Greeting.lua`), which this project mirrors so
-- an imported profile's per-window toggles keep their real meaning. See
-- `docs/skins/windows/gossip.md` for the full three-flag breakdown
-- (`gossip`/`quest`/`greeting`).
--
-- Real 1.12.1 structure, per `FrameXML/QuestFrame.xml` and
-- `QuestFrameTemplates.xml`. Not yet verified against the live client.
--
-- - `QuestFrameGreetingPanel` inherits `QuestFramePanelTemplate` -- BYTE
--   IDENTICAL to `GossipFramePanelTemplate` (same four `UI-QuestGreeting-*`
--   quadrants, four `$parentMaterial*` pieces, one
--   `UI-Quest-BotLeftPatch`), so the same single non-recursive strip
--   clears all nine regions.
-- - Unlike `GossipFrame`, `QuestFrame` (the panel's own parent) has NO
--   background of its own besides its portrait -- every visible "book"
--   texture belongs to whichever sub-panel (Detail/Progress/Reward/
--   Greeting) is currently shown. Stripping this panel's art without
--   drawing a replacement leaves a fully transparent window. So this file
--   DOES draw its own panel background, sized to `QuestFrameGreetingPanel`
--   itself (not to `QuestFrame`) -- it shows and hides in lockstep with
--   the panel, and needs nothing from the (not yet written) `quest` flag
--   to look complete on its own.
-- - `QuestFramePortrait` lives on `QuestFrame` itself, not on this panel,
--   and is shared with the Detail/Progress/Reward panels too -- but
--   nothing else currently owns it, so it is killed defensively here
--   (`S:Kill` is idempotent; whichever flag runs first wins, harmless if
--   the `quest` flag also kills it later).
-- - `GreetingText`/`CurrentQuestsText`/`AvailableQuestsText` inherit
--   `QuestFont`/`QuestTitleFont`, black/near-black by default -- but
--   UNLIKE Gossip's greeting text, the native
--   `QuestFrameGreetingPanel_OnShow` (this panel's own `<OnShow>` script)
--   recolours all three itself on EVERY show
--   (`QuestFrame_SetTextColor`/`QuestFrame_SetTitleTextColor`,
--   `QuestFrame.lua`), so a one-time colour would be undone the next time
--   the panel is shown. Reasserted from our own `OnShow` hook instead,
--   same fix real ElvUI's own `Greeting.lua` uses.
-- - `QuestTitleButton1..MAX_NUM_QUESTS` behave like Gossip's title
--   buttons: fully native-driven Show/Hide/SetText, but the client never
--   re-touches an already-set `SetTextColor` on them, so colouring once is
--   enough (matches real ElvUI's own `Greeting.lua`).
-- - The per-button bullet icon (`UI-Quest-BulletPoint`, unnamed BACKGROUND
--   region) is a plain static marker here, unlike Gossip's per-type icon
--   swap -- left untouched either way, it is not decorative clutter.
--
-- SCOPE: this ONE sub-panel's own chrome and text visibility. Deliberately
-- NOT done here: `QuestFrame`'s own drag handle, hit rect, close button
-- and NPC-name text -- those belong to the outer `quest` flag
-- (`QuestLog.lua`'s own header explains why that flag is still pending).
-- Enabling `greeting` alone therefore looks complete for this panel's own
-- content, but the surrounding `QuestFrame` window stays undraggable and
-- its close button unstyled until `quest` is written -- expected, matches
-- what real ElvUI itself would show in the same partial-flag state.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- Identical geometry to `GossipFrame`'s own panel insets
-- (`docs/skins/windows/gossip.md`): same 384x512 size, same
-- `HitRectInsets` (right=30, bottom=70), and
-- `QuestFrameGreetingGoodbyeButton` anchored at the exact same
-- `BOTTOMRIGHT -39,73` as `GossipFrameGreetingGoodbyeButton` -- so the
-- same measured 8px-below-the-button margin applies: 73 - 8 = 65.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 15, -11, -30, 65

local function RecolorGreetingHeaders()
	local greeting = _G.GreetingText
	local current = _G.CurrentQuestsText
	local available = _G.AvailableQuestsText
	if greeting then pcall(greeting.SetTextColor, greeting, 1, 1, 1) end
	if current then
		pcall(current.SetTextColor, current, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	end
	if available then
		pcall(available.SetTextColor, available, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	end
end

local function RecolorTitleButtons()
	local count = tonumber(_G.MAX_NUM_QUESTS) or 32
	local i
	for i = 1, count do
		local button = _G["QuestTitleButton"..i]
		if button then
			pcall(button.SetTextColor, button, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
		end
	end
end

local function ApplyGreetingChrome(panel)
	S:StripTextures(panel, false)
	S:Kill(_G.QuestFramePortrait)
	S:Kill(_G.QuestGreetingFrameHorizontalBreak)

	S:CreatePanel(panel, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)

	S:HandleScrollBar(_G.QuestGreetingScrollFrameScrollBar)

	RecolorGreetingHeaders()
	RecolorTitleButtons()

	-- Catch-all -- picks up QuestFrameGreetingGoodbyeButton (plain
	-- UIPanelButtonTemplate).
	S:SkinChildren(panel)
end

local greetingSkinApplied = false
local function ApplyGreetingSkin()
	if greetingSkinApplied then return end
	local panel = _G.QuestFrameGreetingPanel
	if not panel then return end
	greetingSkinApplied = true

	ApplyGreetingChrome(panel)

	-- `S:TryHookScript` chains AFTER whatever script the frame already had
	-- (AceHook's own `:HookScript`, or the manual `:SetScript` fallback,
	-- both preserve-and-call-through) -- so this always runs once the
	-- native `QuestFrameGreetingPanel_OnShow` has already finished,
	-- including its own header colouring. One re-apply call covers both
	-- the defensive chrome re-strip every window in this project does AND
	-- overwriting that native colouring back to ours.
	local ok = S:TryHookScript(panel, "OnShow", function() ApplyGreetingChrome(panel) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplyGreetingSkin()
end

-- `greeting`, real ElvUI's own flag name (`Blizzard/Greeting.lua`) --
-- separate from `gossip` and `quest`, see this file's own header.
S:AddBlizzardSkin("greeting", LoadSkin)
