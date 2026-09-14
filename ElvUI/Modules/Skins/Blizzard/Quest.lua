-- Skins > Blizzard > Quest -- reskins `QuestFrame`'s own outer chrome plus
-- its three quest-dialogue sub-panels (Detail/Progress/Reward: offering a
-- quest, turning in required items, picking a reward). Shares the `quest`
-- flag with `QuestLog.lua` (real ElvUI's own single `Blizzard/Quest.lua`
-- covers both windows under that one key; this project split them into two
-- files but keeps the shared flag so an imported profile's `quest` toggle
-- still means the same thing -- see `S:AddBlizzardSkin`'s own header for
-- why that key now holds a LIST, not a single function). The
-- `QuestFrameGreetingPanel` sub-panel is NOT here -- real ElvUI keeps it as
-- its own separate flag/file too (`greeting`, `Greeting.lua`), already
-- written; see `docs/skins/windows/gossip.md` for the full three-flag
-- breakdown this project mirrors.
--
-- Real 1.12.1 structure, per `FrameXML/QuestFrame.xml` and
-- `QuestFrameTemplates.xml`. Not yet verified against the live client.
--
-- - `QuestFrame` itself carries exactly one direct region,
--   `QuestFramePortrait` (ARTWORK) -- same portrait class as
--   `GossipFramePortrait`/`QuestFrameGreetingPanel`'s own kill target,
--   killed the same way (`S:Kill`, idempotent, harmless that `Greeting.lua`
--   also kills the same object).
-- - Each of the three sub-panels (`QuestFrameDetailPanel`/
--   `ProgressPanel`/`RewardPanel`) inherits `QuestFramePanelTemplate` --
--   BYTE IDENTICAL to `GossipFramePanelTemplate`/
--   `QuestFrameGreetingPanel`'s own template (four `UI-QuestGreeting-*`
--   quadrants, four `$parentMaterial*` pieces), so the same single
--   non-recursive strip clears each one. Like `QuestFrameGreetingPanel`,
--   `QuestFrame` itself has no background of its own besides the portrait
--   -- every visible "book" texture belongs to whichever sub-panel is
--   currently shown -- so each panel gets its OWN panel background, sized
--   to itself, not to `QuestFrame`. Same geometry as Gossip/Greeting: the
--   Accept/Decline/Complete/Cancel/Goodbye buttons across all three panels
--   anchor at the same `BOTTOMRIGHT -39,72/73` / `BOTTOMLEFT 22/23,72`
--   shape as Gossip's/Greeting's own Goodbye button, so the same measured
--   8px-below-the-button margin applies (73 - 8 = 65 -- see
--   `docs/skins/windows/gossip.md`).
-- - **Text colour is load-bearing here too, same reason as QuestLog and
--   Greeting**: every quest-dialogue FontString inherits
--   `QuestFont`/`QuestTitleFont`, black by default. UNLIKE Gossip's
--   greeting text (set once, never re-touched), the native code recolours
--   these on every panel OnShow (`QuestFrame_SetTextColor`/
--   `SetTitleTextColor`, called from `QuestFrameDetailPanel_OnShow` etc.)
--   AND independently from `QuestFrameItems_Update`/
--   `QuestFrameProgressItems_Update` on a `QUEST_ITEM_UPDATE` event with
--   the panel already open (no OnShow refires in that case) -- so both
--   paths need a re-apply: each panel's own OnShow hook (chains after the
--   native OnShow, matching `S:TryHookScript`'s "runs once the original
--   already finished" behaviour, see Greeting.lua) AND both native update
--   functions wrapped directly by reassigning the global (this project's
--   own established alternative to `hooksecurefunc`, which is confirmed
--   NOT a real global on this client -- see QuestLog.lua's
--   `WrapQuestLogUpdate` for the exact same technique already proven
--   here). One shared `ReassertQuestFrameText` covers every FontString
--   across all three panels unconditionally rather than dispatching per
--   panel/questState -- cheap (a fixed ~15-name list), and simpler than
--   tracking which call site needs which subset.
--
-- SCOPE: `QuestFrame`'s own portrait/drag/close, each sub-panel's own
-- chrome, panel background, scrollbar, and text visibility (headings,
-- body, the Progress panel's afford/can't-afford required-money colour).
--
-- Deliberately NOT done here, its own future pass: the reward/choice/
-- required item buttons (`QuestDetailItem1..10`/`QuestProgressItem1..6`/
-- `QuestRewardItem1..10`) get their decorative `$parentNameFrame` texture
-- killed (pure removal, no functional loss -- it is not the icon), but no
-- bordered-card treatment or item-quality border colour yet -- same
-- backlog item as `QuestLogFrame`'s own `QuestLogItem1..10`
-- (`QuestLog.lua`'s header), since both button families share the exact
-- same `QuestItemTemplate`/`QuestRewardItemTemplate` shape and should get
-- ONE shared recipe rather than two independently-guessed ones. The
-- native icon (`$parentIconTexture`) and its own usability vertex-colour
-- tint (`SetItemButtonTextureVertexColor`, red when unusable) are left
-- completely untouched either way -- functional, client-fed, not
-- decoration.

local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- Identical geometry to Gossip's/Greeting's own panel insets
-- (`docs/skins/windows/gossip.md`): same 384x512 size, same
-- `HitRectInsets` (right=30, bottom=70), same bottom-button placement, so
-- the same measured 8px-below-the-button margin applies: 73 - 8 = 65.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 15, -11, -30, 65

local RECOLOR_HEADINGS = {
	"QuestTitleText", "QuestDetailObjectiveTitleText", "QuestDetailRewardTitleText",
	"QuestProgressTitleText", "QuestProgressRequiredItemsText",
	"QuestRewardTitleText", "QuestRewardRewardTitleText",
}

local RECOLOR_BODY = {
	"QuestDescription", "QuestObjectiveText", "QuestDetailItemChooseText",
	"QuestDetailItemReceiveText", "QuestDetailSpellLearnText",
	"QuestProgressText",
	"QuestRewardText", "QuestRewardItemChooseText", "QuestRewardItemReceiveText",
	"QuestRewardSpellLearnText",
}

local MONEY_COLOR = {1, 0.80, 0.10}
local MONEY_SHORT_COLOR = {0.6, 0.6, 0.6}

-- The Progress panel's own required-money line: native code (`QuestFrame
-- ProgressItems_Update`) sets it to one of two near-black tones
-- (afford/can't-afford), the same "can't just recolour once" problem as
-- every other FontString here. Read the same afford check the native code
-- uses rather than trust its colour.
local function ReassertProgressMoney()
	local money = _G.QuestProgressRequiredMoneyText
	if not money then return end
	local okReq, required = pcall(GetQuestMoneyToGet)
	local okHave, have = pcall(GetMoney)
	local c = MONEY_COLOR
	if okReq and okHave and required and have and required > have then
		c = MONEY_SHORT_COLOR
	end
	pcall(money.SetTextColor, money, c[1], c[2], c[3])
end

local function ReassertQuestFrameText()
	S:RecolorNames(RECOLOR_HEADINGS, S.ACCENT_COLOR[1], S.ACCENT_COLOR[2], S.ACCENT_COLOR[3])
	S:RecolorNames(RECOLOR_BODY, 1, 1, 1)
	ReassertProgressMoney()
end

-- `$parentNameFrame` is a decorative parchment strip behind the reward
-- item's name text (`UI-QuestItemNameFrame`), a direct Texture region of
-- the item BUTTON itself -- `S:StripTextures` would take the button's own
-- `$parentIconTexture` down WITH it (same frame, same region loop, no
-- per-region exception mechanism), which is fed fresh textures by native
-- code on every update and must stay live. So this kills ONLY the named
-- decorative region, by name, leaving the icon (and the Name/Count
-- FontStrings, already light `GameFontHighlight`/`NumberFontNormal`,
-- untouched by any strip) alone.
local function KillItemNameFrames(prefix, count)
	local i
	for i = 1, count do
		S:Kill(_G[prefix..i.."NameFrame"])
	end
end

local function ApplyPanelChrome(panel, scrollbarName, itemPrefix, itemCount)
	S:StripTextures(panel, false)
	S:CreatePanel(panel, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	S:HandleScrollBar(_G[scrollbarName])
	if itemPrefix then KillItemNameFrames(itemPrefix, itemCount) end
	ReassertQuestFrameText()

	-- Catch-all -- picks up this panel's own Accept/Decline/Complete/
	-- Cancel/Goodbye button (plain UIPanelButtonTemplate). The item
	-- buttons (QuestItemTemplate) carry none of that template's
	-- Normal/Pushed/Highlight art, so the sweep's `HasNativeArt` check
	-- correctly leaves them alone -- confirmed structurally, not just
	-- assumed, from `QuestFrameTemplates.xml`.
	S:SkinChildren(panel)
end

local function ApplyDetailChrome()
	ApplyPanelChrome(_G.QuestFrameDetailPanel, "QuestDetailScrollFrameScrollBar",
		"QuestDetailItem", tonumber(_G.MAX_NUM_ITEMS) or 10)
end

local function ApplyProgressChrome()
	ApplyPanelChrome(_G.QuestFrameProgressPanel, "QuestProgressScrollFrameScrollBar",
		"QuestProgressItem", tonumber(_G.MAX_REQUIRED_ITEMS) or 6)
end

local function ApplyRewardChrome()
	ApplyPanelChrome(_G.QuestFrameRewardPanel, "QuestRewardScrollFrameScrollBar",
		"QuestRewardItem", tonumber(_G.MAX_NUM_ITEMS) or 10)
end

-- `QuestFrameItems_Update(questState)` drives BOTH the Detail and Reward
-- panels' item lists (`questState` is "QuestDetail"/"QuestReward"), and
-- fires independently of any panel OnShow on `QUEST_ITEM_UPDATE` (an item
-- entering/leaving the player's bags while the frame is already open).
-- `QuestFrameProgressItems_Update` is the Progress panel's own equivalent.
-- Wrapped by reassigning the global directly, NOT `hooksecurefunc` --
-- confirmed not a real global function on this client
-- (`docs/api-diffs/hooks-events.md`) -- same technique already proven in
-- this project by `QuestLog.lua`'s own `WrapQuestLogUpdate`.
local questFrameUpdatesWrapped = false
local function WrapQuestFrameUpdates()
	if questFrameUpdatesWrapped then return end
	questFrameUpdatesWrapped = true

	local origItems = _G.QuestFrameItems_Update
	if type(origItems) == "function" then
		_G.QuestFrameItems_Update = function(questState)
			origItems(questState)
			pcall(ReassertQuestFrameText)
		end
	end

	local origProgress = _G.QuestFrameProgressItems_Update
	if type(origProgress) == "function" then
		_G.QuestFrameProgressItems_Update = function()
			origProgress()
			pcall(ReassertQuestFrameText)
		end
	end
end

local questFrameSkinApplied = false
local function ApplyQuestFrameSkin()
	if questFrameSkinApplied then return end
	local frame = _G.QuestFrame
	if not frame then return end
	questFrameSkinApplied = true

	S:Kill(_G.QuestFramePortrait)

	-- `movable="true"` in the XML but no drag script anywhere, same gap as
	-- GossipFrame/QuestLogFrame.
	local handle = S:MakeDraggable(frame)
	if handle then
		pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT, 0)
	end
	pcall(frame.SetUserPlaced, frame, true)

	S:StyleCloseButton(_G.QuestFrameCloseButton)
	-- Re-anchored to `QuestFrame` itself using the same panel insets every
	-- sub-panel uses (no single `elvBackground` exists on `QuestFrame`
	-- itself to anchor to -- see this file's own header): the native
	-- anchor is a CENTER point 42px left / 31px up from the frame's own
	-- TOPRIGHT, which sits slightly outside where the panel corner is
	-- (PANEL_RIGHT,PANEL_TOP = -30,-11) -- same class of gap confirmed
	-- live on MerchantFrame's identically-anchored close button.
	local close = _G.QuestFrameCloseButton
	if close then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT - 4, PANEL_TOP - 4)
	end

	WrapQuestFrameUpdates()

	ApplyDetailChrome()
	ApplyProgressChrome()
	ApplyRewardChrome()

	-- Three independent OnShow hooks, not one shared `QuestFrame`-level
	-- hook: switching from one sub-panel to another while `QuestFrame`
	-- itself stays open (e.g. Detail -> Reward on accepting) shows/hides
	-- the SUB-PANELS without `QuestFrame`'s own OnShow ever refiring --
	-- same pattern as Character.lua's `SUB_FRAMES`/`ApplySubFrameChrome`.
	local subPanels = {
		{ frame = _G.QuestFrameDetailPanel, apply = ApplyDetailChrome, name = "QuestFrameDetailPanel" },
		{ frame = _G.QuestFrameProgressPanel, apply = ApplyProgressChrome, name = "QuestFrameProgressPanel" },
		{ frame = _G.QuestFrameRewardPanel, apply = ApplyRewardChrome, name = "QuestFrameRewardPanel" },
	}
	local i
	for i = 1, table.getn(subPanels) do
		local entry = subPanels[i]
		if entry.frame then
			local ok = S:TryHookScript(entry.frame, "OnShow", entry.apply)
			if not ok then S:ReportSkinProblem() end
		end
	end
end

local function LoadSkin()
	ApplyQuestFrameSkin()
end

S:AddBlizzardSkin("quest", LoadSkin)
