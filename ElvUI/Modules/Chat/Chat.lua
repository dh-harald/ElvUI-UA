-- Chat module -- ports every setting and default from real ElvUI's Chat
-- module (ElvUI-vanilla/ElvUI/Modules/Chat/Chat.lua), plus its
-- Layout.lua (panel creation) and ElvUI_Config/Chat.lua, using the same
-- field/variable names as the original so an exported real profile drives
-- this module directly. Deliberately scoped down from the full reference,
-- on purpose, not by oversight. Two big cuts, both explained here so they
-- don't get mistaken for bugs later:
--
-- 1. **No native `ChatFrame_OnEvent` replacement below this point in the
--    original design intent.** Real ElvUI's timestamp/URL-linking/
--    keyword-highlight/spam-throttle/chat-history features are NOT built
--    on any native Blizzard filter API -- the reference's own
--    `CH:ChatFrame_AddMessageEventFilter` shows ElvUI reimplements that
--    mechanism itself, and it only does anything because ElvUI ALSO fully
--    replaces every chat frame's `OnEvent` script (`CH:ChatFrame_OnEvent`)
--    with its own dispatcher that consults it. Replacing the event
--    handler that decides how every single chat message gets formatted is
--    a correctness-critical, high-blast-radius change -- a bug here could
--    break chat message display entirely, unlike every other
--    risky-but-contained thing this project ships (a broken button
--    texture, a missing datatext). It is nonetheless ported below (see
--    the "Message pipeline" section), since keeping timestamp/URL/
--    keyword/throttle features working in sync with vanilla outweighs the
--    risk here. `P.chat` declares every field real ElvUI does
--    (url/shortChannels/timeStampFormat/keywords/keywordSound/
--    whisperSound/noAlertInCombat/throttleInterval/scrollDownInterval/
--    numScrollMessages/numAllowedCombatRepeat/chatHistory/sticky/
--    useCustomTimeColor/customTimeColor/hyperlinkHover) and the config UI
--    exposes them even where a given field is currently inert. Native
--    chat message rendering itself is otherwise untouched.
-- 2. **Only `ChatFrame1` (the default/left chat window) is docked and
--    styled.** Real ElvUI's `PositionChat`/`UpdateChatTabs`/
--    `FindRightChatID` handle an arbitrary number of chat windows
--    docking/undocking between two panels, including tab-fade rules for
--    each combination -- a lot of machinery for a panel most players
--    never dock a second window into by default. Matches every other
--    module's own "first pass handles the main case" pattern (ActionBars
--    did bar1 before bar2-5, WorldMap did the coord readout before
--    Smaller World Map). RightChatPanel/RightChatTab/RightChatDataPanel/
--    RightChatToggleButton are all built and fully functional (datatexts,
--    mover, collapse icon) -- there's just no logic docking a second chat
--    WINDOW into it, matching real ElvUI's own everyday experience of
--    that panel being empty by default.
--
-- Structural reference: ElvUI-vanilla/ElvUI/Layout/Layout.lua
-- (panel/tab/toggle-button/data-panel creation, `E:CreateMover` names,
-- SPACING formula) -- that file's chat-panel job is folded directly into
-- this one, which is a DIVERGENCE from real ElvUI's file layout, not a
-- reproduction of it. A Layout module does now exist here
-- (ElvUI/Layout/Layout.lua), and it exposes upstream's chat-panel METHOD
-- NAMES (LO:ToggleChatPanels/SetChatTabStyle/ToggleChatTabPanels) as thin
-- wrappers over this file's own CH:Update* functions -- so every caller,
-- config setters included, already talks to the module upstream expects.
-- Moving the panel construction itself over there is a separate step; when
-- it happens, no caller changes.
-- Toggle-button fade: real ElvUI fades panels in/out via
-- `UIFrameFadeIn`/`UIFrameFadeOut` (Layout.lua) -- reimplemented here as
-- a plain Show()/Hide() instead, deliberately, regardless of whether the
-- animation API itself works on UA: a plain toggle is guaranteed
-- functionally correct either way. Storage convention kept identical to
-- real ElvUI though: `E.db.LeftChatPanelFaded`/
-- `RightChatPanelFaded`, undeclared/nil by default, not nested under
-- `E.db.chat`.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
-- "AceHook-3.0" mixin: AceHook-3.0's `SecureHook` on an object+method
-- routes through `hooksecurefunc(obj, method, uid)` -- a different,
-- unreliable-on-UA overload from the bare-global-name one already proven
-- working elsewhere (UnitFrames.lua's castbar icon capture, and
-- WireMessagePipeline's own `SecureHook` calls below, which use that
-- bare-name form). Kept mixed in for that bare-name usage even though
-- the ChatFrame1 reposition fix (see PositionChat) doesn't use AceHook at
-- all (raw `frame[method] = wrapper` reassignment instead).
local CH = E:NewModule("Chat", "AceEvent-3.0", "AceHook-3.0")
E.Chat = CH

local LSM = LibStub("LibSharedMedia-3.0", true)

-- Settings: `V.chat` (Settings/Private.lua), `P.chat`
-- (Settings/Profile.lua).

-- ===========================================================================
-- Constants / small helpers
-- ===========================================================================
local PANEL_HEIGHT = 22
local SIDE_BUTTON_WIDTH = 16
-- Approximates real ElvUI's own E.Border/E.Spacing pixel-perfect constants
-- the same way ActionBars.lua's own ELVUI_BORDER/ELVUI_SPACING already do
-- (Core/Util.lua's Util.BarPadding) -- this project has no pixel-perfect
-- scaling system, these are fixed approximations, not computed from the
-- user's actual resolution/UI scale.
local ELVUI_SPACING = 1
local ELVUI_BORDER = 2
local SPACING = ELVUI_BORDER * 3 - ELVUI_SPACING

-- The UI ACCENT colour, read LIVE from `E.media.rgbvaluecolor`/
-- `hexvaluecolor` (`E.db.general.valuecolor`, derived in Init.lua). Upstream
-- drives the chat tab text from exactly this
-- (`UpdateChatTabColor` registered into `E.valueColorUpdateFuncs`, plus
-- `E.media.hexvaluecolor` for the keyword highlight), so this file follows it.
--
-- These are FUNCTIONS, not load-time constants: `E.media.*value*color` is
-- computed in `OnInitialize`, long after this file is parsed, and it changes
-- again whenever the accent setting or the install wizard's theme changes.
-- The fallback is the old hardcoded value (LibConfig-1.0's #FFD100 yellow),
-- used only for a call that somehow lands before the derivation.
local ACCENT_FALLBACK = { 1, 0.82, 0 }

local function AccentRGB()
	local rgb = E.media and E.media.rgbvaluecolor
	if rgb and rgb[1] then return rgb[1], rgb[2], rgb[3] end
	return ACCENT_FALLBACK[1], ACCENT_FALLBACK[2], ACCENT_FALLBACK[3]
end

local function AccentHex()
	return (E.media and E.media.hexvaluecolor) or E:RGBToHex(ACCENT_FALLBACK[1], ACCENT_FALLBACK[2], ACCENT_FALLBACK[3])
end

local CHROME_SUFFIXES = {
	"Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture",
	"BottomRightTexture", "TopTexture", "BottomTexture", "LeftTexture", "RightTexture",
	"ResizeTop", "ResizeTopLeft", "ResizeTopRight", "ResizeBottom",
	"ResizeBottomLeft", "ResizeBottomRight", "ResizeLeft", "ResizeRight",
	"UpButton", "DownButton", "BottomButton", "TabDockRegion",
	"TabLeft", "TabMiddle", "TabRight",
}

-- Matches the project-wide "permanently override Show with a no-op"
-- pattern (ActionBars.lua's HideFrame/HideChrome) for native chrome we
-- never want to see again, not just hide once.
local function Kill(frame)
	if not frame then return end
	pcall(frame.Hide, frame)
	frame.Show = E.noop
end


-- ===========================================================================
-- Panel / tab / toggle-button / datatext-panel creation
-- (ElvUI-vanilla/ElvUI/Layout/Layout.lua, folded into this
-- module -- see this file's header comment for why)
-- ===========================================================================
-- Collapsing only removes the CHAT MESSAGE AREA -- the panel itself
-- (datatext bar, toggle button, tab strip) stays put so it's still
-- usable/visible. The WHOLE chat window disappears: message text, its
-- tab, AND the tab-strip backdrop (`LeftChatTab`) -- only the datatext
-- bar (`LeftChatDataPanel`) and this toggle button itself stay.
--
-- Besides hiding the content (below), two things must be handled for a clean
-- collapse:
-- 1. `LeftChatPanel` (`lchat`) has its OWN backdrop (`E:SetTemplate` in
--    CreateChatPanels), independent of `ChatFrame1`'s -- hiding
--    ChatFrame1 left that backdrop rectangle sitting there empty,
--    looking like a leftover "frame" even though nothing was
--    technically wrong. Fixed by also fading the PANEL's own backdrop
--    to alpha 0 on collapse (not hiding the frame -- `lchatdp`/`lchattb`
--    are its children and must stay visible) and restoring the real
--    `panelColor` on expand.
-- 2. Native `ChatFrameMenuButton`/scroll buttons (killed by
--    `HideNativeChatButtons`, normally via the login-time resweep) can
--    get re-shown by Blizzard's own dock-management code reacting to
--    `ChatFrame1:Hide()`/`:Show()` -- the resweep only runs for the
--    first ~30s after login, so a collapse hours into a session outran
--    it. Fixed by re-running `HideNativeChatButtons()` on every toggle,
--    not just at login.
--
-- Collapsing hides `LeftChatContent`, a plain container that parents every
-- chat window in the native dock, their tabs, the tab-strip backdrop and the
-- wheel catcher (same principle as real ElvUI, which hides the whole
-- `LeftChatPanel`; here the datatext bar and this button must stay, so the
-- container sits one level lower). Hiding the windows one by one does not
-- hold: native code re-shows them at will -- `FCF_DockUpdate` shows the
-- selected window at login, `FCF_OnUpdate` fades a hidden docked window's
-- tab back in on hover, a tab click re-selects the window -- and a hidden
-- ancestor is the only state none of that can undo.

-- The native dock stacks every docked window (Combat Log, custom windows) on
-- ChatFrame1's rectangle, so the whole dock belongs to the left panel.
local function IsLeftDockFrame(chatFrame)
	return chatFrame ~= nil and (chatFrame == ChatFrame1 or chatFrame.isDocked ~= nil)
end

-- Moves every docked window and its tab into LeftChatContent, and an undocked
-- one back to UIParent. Tabs are `frameStrata="LOW"` in the template; a new
-- parent resets that, so the original strata is re-applied. ChatFrame1Tab is
-- left to RestyleChatTab, which gives it its own strata and level.
local function AdoptLeftDock()
	local content = LeftChatContent
	if not content then return end
	local i
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local chatFrame = _G["ChatFrame"..i]
		local tab = _G["ChatFrame"..i.."Tab"]
		if chatFrame then
			local parent = IsLeftDockFrame(chatFrame) and content or UIParent
			if tab and not tab.elvOriginalStrata then
				local okStrata, strata = pcall(tab.GetFrameStrata, tab)
				tab.elvOriginalStrata = (okStrata and strata) or "LOW"
			end
			pcall(chatFrame.SetParent, chatFrame, parent)
			if tab and i ~= 1 then
				pcall(tab.SetParent, tab, parent)
				pcall(tab.SetFrameStrata, tab, tab.elvOriginalStrata)
			end
		end
	end
end
CH.AdoptLeftDock = AdoptLeftDock

local function ToggleLeftChat()
	if E.db.LeftChatPanelFaded then
		E.db.LeftChatPanelFaded = nil
		if LeftChatContent then LeftChatContent:Show() end
	else
		E.db.LeftChatPanelFaded = true
		AdoptLeftDock()
		if LeftChatContent then LeftChatContent:Hide() end
	end
	CH:UpdatePanelBackdrop()
	CH:HideNativeChatButtons()
end

-- Same shape as ToggleLeftChat -- a blanket `RightChatPanel:Show()/
-- :Hide()` would take the datatext bar and toggle button down with it,
-- since they're children. The right panel has no docked ChatFrame of its
-- own (see this file's header comment on scope), so "collapsing" it just
-- means
-- hiding its tab-strip backdrop and fading its own panel backdrop --
-- `rchatdp`/`rchattb` stay, matching the left side's semantics as
-- closely as the right panel's actual content allows.
local function ToggleRightChat()
	if E.db.RightChatPanelFaded then
		E.db.RightChatPanelFaded = nil
		if RightChatTab and E.db.chat.panelTabBackdrop then RightChatTab:Show() end
	else
		E.db.RightChatPanelFaded = true
		if RightChatTab then RightChatTab:Hide() end
	end
	CH:UpdatePanelBackdrop()
	CH:HideNativeChatButtons()
end

-- Exposed on the module as well as kept file-local: the Layout module's
-- HideLeftChat()/HideRightChat()/HideBothChat() globals (real ElvUI's own
-- public API, called from config setters and the install wizard) need a way
-- in. The local calls above/below are unchanged.
CH.ToggleLeftChat = ToggleLeftChat
CH.ToggleRightChat = ToggleRightChat

local function CreateToggleButton(name, label, onClick)
	local button = CreateFrame("Button", name, UIParent)
	button:SetWidth(SIDE_BUTTON_WIDTH)
	button:SetHeight(PANEL_HEIGHT)
	E:SetTemplate(button, "Transparent")

	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	-- Real ElvUI's chat toggle button text (Layout `lchattb.text`): the UI
	-- font at its defaults.
	E:FontTemplate(button.text)
	-- Spelled out rather than the one-argument `SetPoint("CENTER")` shorthand:
	-- the stock 1.12.1 client rejects that form with a usage error.
	button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
	-- Upstream leaves this arrow the font's own colour and never recolours
	-- the button border on hover -- both are this project's own additions.
	-- Kept, but driven from the accent rather than a hardcoded yellow, so
	-- the whole chat panel reads as one colour with the tabs beside it.
	button.elvAccentText = true
	pcall(button.text.SetTextColor, button.text, AccentRGB())
	button.text:SetText(label)

	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function()
		local ar, ag, ab = AccentRGB()
		pcall(button.SetBackdropBorderColor, button, ar, ag, ab, 1)
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(L["Toggle Chat Frame"])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 1)
		GameTooltip:Hide()
	end)

	return button
end

function CH:CreateChatPanels()
	local db = E.db.chat

	-- Left Chat Panel
	local lchat = CreateFrame("Frame", "LeftChatPanel", UIParent)
	lchat:SetFrameStrata("BACKGROUND")
	lchat:SetWidth(db.panelWidth)
	lchat:SetHeight(db.panelHeight)
	lchat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 4, 4)
	E:SetTemplate(lchat, "Transparent")
	E:CreateMover(lchat, "LeftChatMover", L["Left Chat"])

	-- Everything the collapse hides; see ToggleLeftChat.
	local lcontent = CreateFrame("Frame", "LeftChatContent", lchat)
	lcontent:SetAllPoints(lchat)

	local lchattab = CreateFrame("Frame", "LeftChatTab", lcontent)
	lchattab:SetHeight(PANEL_HEIGHT)
	lchattab:SetPoint("TOPLEFT", lchat, "TOPLEFT", SPACING, -SPACING)
	lchattab:SetPoint("TOPRIGHT", lchat, "TOPRIGHT", -SPACING, -SPACING)
	E:SetTemplate(lchattab, "Transparent")

	local lchatdp = CreateFrame("Frame", "LeftChatDataPanel", lchat)
	lchatdp:SetHeight(PANEL_HEIGHT)
	lchatdp:SetPoint("BOTTOMLEFT", lchat, "BOTTOMLEFT", SPACING + SIDE_BUTTON_WIDTH, SPACING)
	lchatdp:SetPoint("BOTTOMRIGHT", lchat, "BOTTOMRIGHT", -SPACING, SPACING)
	E:SetTemplate(lchatdp, "Transparent")
	if E.DataTexts then
		E.DataTexts:RegisterPanel(lchatdp, 3, "ANCHOR_TOPLEFT", -16, 3)
	end

	local lchattb = CreateToggleButton("LeftChatToggleButton", "<", ToggleLeftChat)
	lchattb:SetPoint("TOPRIGHT", lchatdp, "TOPLEFT", 0, 0)
	lchattb:SetPoint("BOTTOMLEFT", lchat, "BOTTOMLEFT", SPACING, SPACING)

	-- Right Chat Panel
	local rchat = CreateFrame("Frame", "RightChatPanel", UIParent)
	rchat:SetFrameStrata("BACKGROUND")
	rchat:SetWidth(db.separateSizes and db.panelWidthRight or db.panelWidth)
	rchat:SetHeight(db.separateSizes and db.panelHeightRight or db.panelHeight)
	rchat:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -4, 4)
	E:SetTemplate(rchat, "Transparent")
	E:CreateMover(rchat, "RightChatMover", L["Right Chat"])

	local rchattab = CreateFrame("Frame", "RightChatTab", rchat)
	rchattab:SetHeight(PANEL_HEIGHT)
	rchattab:SetPoint("TOPLEFT", rchat, "TOPLEFT", SPACING, -SPACING)
	rchattab:SetPoint("TOPRIGHT", rchat, "TOPRIGHT", -SPACING, -SPACING)
	E:SetTemplate(rchattab, "Transparent")

	local rchatdp = CreateFrame("Frame", "RightChatDataPanel", rchat)
	rchatdp:SetHeight(PANEL_HEIGHT)
	rchatdp:SetPoint("BOTTOMLEFT", rchat, "BOTTOMLEFT", SPACING, SPACING)
	rchatdp:SetPoint("BOTTOMRIGHT", rchat, "BOTTOMRIGHT", -SPACING - SIDE_BUTTON_WIDTH, SPACING)
	E:SetTemplate(rchatdp, "Transparent")
	if E.DataTexts then
		E.DataTexts:RegisterPanel(rchatdp, 3, "ANCHOR_TOPRIGHT", 16, 3)
	end

	local rchattb = CreateToggleButton("RightChatToggleButton", ">", ToggleRightChat)
	rchattb:SetPoint("TOPLEFT", rchatdp, "TOPRIGHT", 0, 0)
	rchattb:SetPoint("BOTTOMRIGHT", rchat, "BOTTOMRIGHT", -SPACING, SPACING)

	CH:UpdatePanelTexture("Left")
	CH:UpdatePanelTexture("Right")
	CH:UpdateDataPanelVisibility()
	CH:UpdateTabStyle()

	-- Matches ToggleLeftChat/ToggleRightChat's own scope exactly (including
	-- the panel-backdrop fade fix, via the same UpdatePanelBackdrop call)
	-- -- so a /reload while collapsed doesn't show the "empty rectangle"/
	-- "leftover border" bugs those fixed for a live toggle.
	if E.db.LeftChatPanelFaded then
		lcontent:Hide()
	end
	if E.db.RightChatPanelFaded then
		rchattab:Hide()
	end
	CH:UpdatePanelBackdrop()
end

-- ===========================================================================
-- Chat frame chrome stripping + font (ChatFrame1 only, see header comment)
-- ===========================================================================
-- Reparenting doesn't change a frame's own strata/level (same established
-- lesson as the GameTimeFrame minimap fix) -- the tab could still be
-- carrying whatever level it had under its ORIGINAL native parent, which
-- may not be high enough to render above LeftChatTab's own backdrop once
-- it's a child of a brand new frame, leaving the General tab effectively
-- invisible/unclickable after reparenting. Explicit strata+level copy,
-- same fix shape as GameTimeFrame's -- pulled into its own
-- always-re-runnable function (not
-- guarded by `elvStyled`) since Blizzard's own dock-management code
-- (FCFDock_UpdateTabs) may re-run and reset level/position whenever tabs
-- are shown/hidden/docked, the same class of "something else keeps
-- re-asserting a default" problem already seen with ActionBars'
-- SetNormalTexture -- also called from the periodic resweep below.
function CH:RestyleChatTab()
	local tab = ChatFrame1Tab
	if not tab or not LeftChatTab or not LeftChatPanel then return end

	-- ROOT CAUSE: parenting `tab` onto `LeftChatTab` is wrong -- a tab
	-- correctly reading `IsShown()`/`GetAlpha()` as true/1 can still be
	-- invisible on screen if an ancestor is hidden, since effective
	-- visibility is the AND of the whole ancestor chain (`IsVisible()`
	-- would reveal this, `IsShown()` alone would not). `LeftChatTab` is only
	-- ever a purely DECORATIVE backdrop strip in real ElvUI too (see
	-- Layout.lua's own `CreateChatPanels`: `LeftChatTab` is created as a
	-- sibling under `LeftChatPanel`, and the actual tabs get parented onto
	-- `LeftChatPanel` directly in `PositionChat`, never onto `LeftChatTab`).
	-- `E.db.chat.panelTabBackdrop` defaults to `false` (matches real
	-- ElvUI's own default) -- `CH:UpdateTabStyle()` correctly `Hide()`s
	-- `LeftChatTab` for that default, exactly like real ElvUI's own
	-- `ToggleChatTabPanels` does. Parenting the tab onto `LeftChatPanel`
	-- instead of `LeftChatTab`, matching the reference, keeps
	-- `LeftChatTab` purely a backdrop sibling behind it, so its own
	-- visibility no longer affects the tab at all. The parent is
	-- `LeftChatContent`, the panel-sized container the collapse hides.
	pcall(tab.SetParent, tab, LeftChatContent or LeftChatPanel)
	pcall(tab.ClearAllPoints, tab)
	pcall(tab.SetPoint, tab, "BOTTOMLEFT", LeftChatTab, "BOTTOMLEFT", 4, 0)
	pcall(tab.SetFrameStrata, tab, LeftChatPanel:GetFrameStrata())
	pcall(tab.SetFrameLevel, tab, LeftChatPanel:GetFrameLevel() + 5)
	pcall(tab.Show, tab)
	pcall(tab.SetAlpha, tab, 1)
	local okHighlight, highlight = pcall(tab.GetHighlightTexture, tab)
	if okHighlight and highlight then
		pcall(highlight.SetTexture, highlight, nil)
	end
	local tabText = ChatFrame1TabText
	if tabText then
		pcall(tabText.SetTextColor, tabText, AccentRGB())
	end
end

function CH:StyleChatFrame(frame)
	if frame.elvStyled then return end
	local name = frame:GetName()

	local i
	for i = 1, table.getn(CHROME_SUFFIXES) do
		Kill(_G[name..CHROME_SUFFIXES[i]])
	end

	CH:RestyleChatTab()

	pcall(frame.SetClampedToScreen, frame, false)
	frame.elvStyled = true
end

-- The small chat-menu icon button (channel/chat-type dropdown) and the
-- native Up/Down/ToBottom scroll buttons all sit at their own native
-- position, independent of ChatFrame1Tab -- reparenting/repositioning the
-- tab alone leaves them behind. Matches real ElvUI's own
-- `E:Kill(ChatFrameMenuButton)` plus the Up/Down/BottomButton kills
-- already in CHROME_SUFFIXES. These buttons can reappear after a
-- /reload, since Blizzard's own dock-management code re-creates/re-shows
-- them lazily. Pulled out of the one-time `StyleChatFrame` (guarded by
-- `frame.elvStyled`, so it only ever runs once per frame) into its own
-- unconditionally-re-runnable function so a periodic resweep can catch
-- these if Blizzard's own code re-creates/re-shows them lazily after
-- login -- same established pattern as ActionBars' HideChrome/
-- ExhaustionTick and Minimap's GameTimeFrame fixes.
function CH:HideNativeChatButtons()
	Kill(ChatFrameMenuButton)
	Kill(ChatFrame1UpButton)
	Kill(ChatFrame1DownButton)
	Kill(ChatFrame1BottomButton)
end

-- By default Combat Log (ChatFrame2) is DOCKED together with ChatFrame1,
-- and Blizzard's own native tab layout anchors a docked window's tab
-- RELATIVE TO the previous one in the row (not to any fixed screen
-- position) -- so ChatFrame2Tab follows ChatFrame1Tab into LeftChatTab's
-- area automatically, without this project ever explicitly reparenting
-- it (`RestyleChatTab` only reparents/positions ChatFrame1's OWN tab; see
-- this module's "ChatFrame1 only" scope decision at the top of the file).
-- Real ElvUI's own answer to "should every docked tab look the same": yes
-- -- `UpdateChatTabColor` recolors EVERY chat window's tab text uniformly
-- via `E.valueColorUpdateFuncs`, not just the main one, and `StyleChat`
-- strips each window's OWN corner/highlight textures the same way.
-- Extending that here to every window (kill corner art + accent-color the
-- text, NOT reparenting/positioning, which stays ChatFrame1-only per this
-- module's scope) gives any window that ends up riding along via the
-- native anchor chain the same clean look, and covers any further chat
-- windows created later too.
function CH:StyleAllChatTabs()
	local i
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local suffix
		for suffix = 1, table.getn(CHROME_SUFFIXES) do
			local key = CHROME_SUFFIXES[suffix]
			if key == "TabLeft" or key == "TabMiddle" or key == "TabRight" or key == "TabDockRegion" then
				Kill(_G["ChatFrame"..i..key])
			end
		end

		local tab = _G["ChatFrame"..i.."Tab"]
		if tab then
			local okHighlight, highlight = pcall(tab.GetHighlightTexture, tab)
			if okHighlight and highlight then
				pcall(highlight.SetTexture, highlight, nil)
			end
		end

		local tabText = _G["ChatFrame"..i.."TabText"]
		if tabText then
			pcall(tabText.SetTextColor, tabText, AccentRGB())
		end
	end
end

-- Re-applies the accent to everything this file colours, on init and on every
-- later change. Same job as upstream's own `UpdateChatTabColor`, extended to
-- the two toggle buttons this project adds. Named frames only -- no registry
-- to keep, and a button that was never built simply isn't found.
local function ValueColorUpdate(_, r, g, b)
	local i
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local tabText = _G["ChatFrame"..i.."TabText"]
		if tabText then pcall(tabText.SetTextColor, tabText, r, g, b) end
	end

	local names = { "LeftChatToggleButton", "RightChatToggleButton" }
	local n
	for n = 1, table.getn(names) do
		local button = _G[names[n]]
		if button and button.elvAccentText and button.text then
			pcall(button.text.SetTextColor, button.text, r, g, b)
		end
	end
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

-- Matches ActionBars.lua's own ApplyFont exactly (Modules/ActionBars/
-- ActionBars.lua) -- same guard-then-SetFont shape, same "NONE"
-- stored-sentinel -> "" translation.
function CH:ApplyFont(frame)
	local db = E.db.chat
	local id = frame.GetID and frame:GetID()
	local okInfo, _, size = pcall(GetChatWindowInfo, id)
	local fontSize = (okInfo and size and size > 0) and size or 14

	local path = LSM and LSM:Fetch("font", db.font)
	local outline = db.fontOutline
	if outline == "NONE" then outline = "" end
	if path then
		pcall(frame.SetFont, frame, path, fontSize, outline)
	end

	local tabText = _G[frame:GetName().."TabText"]
	if tabText then
		local tabPath = LSM and LSM:Fetch("font", db.tabFont)
		local tabOutline = db.tabFontOutline
		if tabOutline == "NONE" then tabOutline = "" end
		if tabPath then
			pcall(tabText.SetFont, tabText, tabPath, db.tabFontSize, tabOutline)
		end
	end
end

-- Mouse wheel scroll. Two things combined here: (1) real ElvUI's own
-- Chat.lua explicitly wires this itself (`ChatFrame_OnMouseScroll`,
-- SetScript("OnMouseWheel",...) + EnableMouseWheel(true)) rather than
-- relying on any default-UI wheel support existing on its own; (2)
-- `OnMouseWheel` only reliably fires on a **ScrollFrame** widget on UA --
-- a plain Frame/Button (and a ScrollingMessageFrame like ChatFrame1 too)
-- does not reliably receive it. Same fix already proven
-- for Minimap zoom (`ElvUIMinimapWheelCatcher`): an invisible ScrollFrame
-- OVERLAY, not a handler on the real target frame directly. Uses
-- `EnableMouseWheel` only (not `EnableMouse`), matching the Minimap
-- catcher's own confirmed-safe recipe -- normal clicking/hovering chat
-- (links, etc.) passes through underneath, same as Minimap's own clicks
-- were confirmed unaffected by its wheelCatcher.
local function ChatWheelCatcher_OnMouseScroll()
	local n = E.db.chat.numScrollMessages or 3
	if arg1 and arg1 > 0 then
		if IsShiftKeyDown() then
			pcall(ChatFrame1.ScrollToTop, ChatFrame1)
		else
			local i
			for i = 1, n do
				pcall(ChatFrame1.ScrollUp, ChatFrame1)
			end
		end
	elseif arg1 and arg1 < 0 then
		if IsShiftKeyDown() then
			pcall(ChatFrame1.ScrollToBottom, ChatFrame1)
		else
			local i
			for i = 1, n do
				pcall(ChatFrame1.ScrollDown, ChatFrame1)
			end
		end
	end
end

function CH:EnableWheelScroll(frame)
	if self.wheelCatcher then return end
	-- Parented to LeftChatContent directly (not `frame:GetParent()`) --
	-- this runs BEFORE ChatFrame1 itself actually gets reparented onto
	-- it later in Initialize, so `frame:GetParent()` would still be
	-- ChatFrame1's original native parent at this point.
	-- `SetAllPoints(frame)` tracks ChatFrame1's on-screen rectangle
	-- correctly regardless of the catcher's own parent either way.
	local okCatcher, catcher = pcall(CreateFrame, "ScrollFrame", "LeftChatWheelCatcher", LeftChatContent or LeftChatPanel)
	if not okCatcher or not catcher then return end
	catcher:SetAllPoints(frame)
	pcall(catcher.SetFrameLevel, catcher, (frame:GetFrameLevel() or 0) + 5)
	pcall(catcher.EnableMouseWheel, catcher, true)
	catcher:SetScript("OnMouseWheel", ChatWheelCatcher_OnMouseScroll)
	self.wheelCatcher = catcher
end

-- ===========================================================================
-- Editbox skin + positioning
-- ===========================================================================
function CH:SkinEditBox()
	local editbox = ChatFrameEditBox
	if not editbox or editbox.elvSkinned then return end

	-- Best-effort region kill -- vanilla's classic edit box template names
	-- its 3 border textures Left/Mid/Right; harmless no-op via pcall if
	-- this guess is wrong on either client.
	Kill(_G["ChatFrameEditBoxLeft"])
	Kill(_G["ChatFrameEditBoxMid"])
	Kill(_G["ChatFrameEditBoxRight"])

	-- NOT E:SetTemplate: this is a NATIVE frame, and that helper's contract is
	-- our own CreateFrame'd frames only (on UA a native frame's <Backdrop> is a
	-- template-level shared resource, so one SetBackdrop can alter an unrelated
	-- window). The explicit call below is
	-- the ONE audited exception in this project: it predates the rule, it is
	-- what real ElvUI does to the same frame, and no collateral damage has ever
	-- shown up from it -- the edit box's own chrome is texture-based
	-- (ChatFrameEditBoxLeft/Mid/Right, killed just above), not a <Backdrop>.
	-- Do not generalize from it; a NEW surface gets a child frame instead.
	pcall(editbox.SetBackdrop, editbox, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(editbox.SetBackdropColor, editbox, 0.06, 0.06, 0.06, 0.9)
	pcall(editbox.SetBackdropBorderColor, editbox, 0, 0, 0, 1)

	pcall(editbox.SetAltArrowKeyMode, editbox, E.db.chat.useAltKey)

	ElvCharacterDB.ChatEditHistory = ElvCharacterDB.ChatEditHistory or {}
	editbox.historyLines = ElvCharacterDB.ChatEditHistory
	editbox.historyIndex = 0

	-- Combat-repeat-spam block + /tt and /gr shortcuts (CH.OnTextChanged,
	-- defined in the "Message pipeline" section below) -- `E:HookScript`
	-- (not a bare `HookScript` global, established project convention)
	-- so this CHAINS with whatever native OnTextChanged behavior already
	-- exists rather than replacing it.
	E:HookScript(editbox, "OnTextChanged", function() CH.OnTextChanged() end)

	editbox:Hide()
	editbox.elvSkinned = true
end

function CH:UpdateAnchors()
	local editbox = ChatFrameEditBox
	if not editbox or not LeftChatDataPanel then return end

	editbox:ClearAllPoints()
	if E.db.chat.editBoxPosition == "BELOW_CHAT" then
		if E.db.datatexts.leftChatPanel then
			editbox:SetAllPoints(LeftChatDataPanel)
		else
			editbox:SetPoint("TOPLEFT", ChatFrame1, "BOTTOMLEFT", 0, -2)
			editbox:SetPoint("TOPRIGHT", ChatFrame1, "BOTTOMRIGHT", 0, -2)
			editbox:SetHeight(PANEL_HEIGHT)
		end
	else
		editbox:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 2)
		editbox:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 2)
		editbox:SetHeight(PANEL_HEIGHT)
	end
end

-- ===========================================================================
-- Positioning (ChatFrame1 only -- see header comment)
-- ===========================================================================
function CH:PositionChat()
	if not LeftChatPanel or not ChatFrame1 then return end
	if not E.db.chat.lockPositions or E.private.chat.enable ~= true then return end

	local chat = ChatFrame1
	-- Guards the diagnostic SecureHook's in Initialize (see that
	-- comment) so our OWN calls here don't get reported as an
	-- "external" reposition -- set for the whole duration of this
	-- function's own SetParent/ClearAllPoints/SetPoint calls.
	CH.repositioning = true
	chat:SetParent(LeftChatContent or LeftChatPanel)
	AdoptLeftDock()
	CH:RestyleChatTab()

	chat:ClearAllPoints()
	local topOffset = SPACING + PANEL_HEIGHT
	local bottomOffset = E.db.datatexts.leftChatPanel and (SPACING + PANEL_HEIGHT) or SPACING
	chat:SetPoint("TOPLEFT", LeftChatPanel, "TOPLEFT", SPACING, -topOffset)
	chat:SetPoint("BOTTOMRIGHT", LeftChatPanel, "BOTTOMRIGHT", -SPACING, bottomOffset)

	-- ROOT CAUSE of a "chat frame randomly shrinks" bug: `ChatFrame1` is a
	-- native Blizzard "managed frame"
	-- (`UIPARENT_MANAGED_FRAME_POSITIONS["ChatFrame1"] = {baseY=85,
	-- xOffset=32, anchorTo="UIParent", point="BOTTOMLEFT",
	-- rpoint="BOTTOMLEFT", ...}`). `UIParent_ManageFramePositions`
	-- (UIParent.lua) runs periodically (durability/reputation-bar/pet-bar
	-- changes, among others) and for any managed frame that ISN'T
	-- `IsUserPlaced()`, it calls `frame:SetPoint(...)` WITHOUT a preceding
	-- `ClearAllPoints()` -- adding a 3rd, conflicting anchor point on top
	-- of our own 2, corrupting ChatFrame1's computed size. Real ElvUI's
	-- own reference code guards this with `if chat:IsMovable() then chat:
	-- SetUserPlaced(true) end`, which marks the frame as user-placed so
	-- `UIParent_ManageFramePositions` skips it entirely -- but
	-- `ChatFrame1:IsMovable()` returns false on UA (unlike real 1.12.1,
	-- where it presumably returns true), so that guarded call never
	-- fires here. Fixed by calling `SetUserPlaced(true)` UNCONDITIONALLY
	-- (still pcall-wrapped for safety) instead of gating it behind
	-- `IsMovable()`. See Initialize's own commented-out safety net for a
	-- reactive fallback kept in reserve in case this alone doesn't fully
	-- suppress the bug.
	pcall(chat.SetUserPlaced, chat, true)
	CH.repositioning = false
end

-- ===========================================================================
-- Live-apply helpers, wired from ElvUI_Config/Core.lua's "Chat" category
-- ===========================================================================
-- The collapse fade in ToggleLeftChat/ToggleRightChat must fade BOTH
-- SetBackdropColor (the fill) AND SetBackdropBorderColor (the edge) --
-- `E:SetTemplate` sets those as two SEPARATE calls, so fading only the
-- fill leaves the border opaque black. This function already pairs both
-- correctly for a different setting (panelBackdrop mode), so
-- ToggleLeftChat/ToggleRightChat/the login-restore block call this
-- instead of setting colors directly, and it ANDs the mode-based
-- visibility with the collapsed state too.
function CH:UpdatePanelBackdrop()
	local mode = E.db.chat.panelBackdrop
	local showLeft = (mode == "SHOWBOTH" or mode == "LEFT") and not E.db.LeftChatPanelFaded
	local showRight = (mode == "SHOWBOTH" or mode == "RIGHT") and not E.db.RightChatPanelFaded
	local c = E.db.chat.panelColor
	if LeftChatPanel then
		pcall(LeftChatPanel.SetBackdropColor, LeftChatPanel, c.r, c.g, c.b, showLeft and c.a or 0)
		pcall(LeftChatPanel.SetBackdropBorderColor, LeftChatPanel, 0, 0, 0, showLeft and 1 or 0)
	end
	if RightChatPanel then
		pcall(RightChatPanel.SetBackdropColor, RightChatPanel, c.r, c.g, c.b, showRight and c.a or 0)
		pcall(RightChatPanel.SetBackdropBorderColor, RightChatPanel, 0, 0, 0, showRight and 1 or 0)
	end
end

function CH:UpdatePanelSizes()
	-- Guards the diagnostic hooks in Initialize (see that comment) --
	-- this legitimately resizes LeftChatPanel/RightChatPanel itself
	-- (e.g. from a config change), which would otherwise falsely report
	-- as an "external" reposition.
	CH.repositioning = true
	local db = E.db.chat
	if LeftChatPanel then
		LeftChatPanel:SetWidth(db.panelWidth)
		LeftChatPanel:SetHeight(db.panelHeight)
	end
	if RightChatPanel then
		RightChatPanel:SetWidth(db.separateSizes and db.panelWidthRight or db.panelWidth)
		RightChatPanel:SetHeight(db.separateSizes and db.panelHeightRight or db.panelHeight)
	end
	CH:PositionChat()
	CH.repositioning = false
end

function CH:UpdatePanelTexture(side)
	local frame = (side == "Right") and RightChatPanel or LeftChatPanel
	if not frame then return end
	local path = (side == "Right") and E.db.chat.panelBackdropNameRight or E.db.chat.panelBackdropNameLeft

	if not frame.tex then
		local okTex, tex = pcall(frame.CreateTexture, frame, nil, "OVERLAY")
		if not okTex then return end
		frame.tex = tex
		pcall(tex.SetAllPoints, tex, frame)
	end

	if path and path ~= "" then
		pcall(frame.tex.SetTexture, frame.tex, path)
	else
		pcall(frame.tex.SetTexture, frame.tex, nil)
	end
end

function CH:UpdateTabStyle()
	local shown = E.db.chat.panelTabBackdrop
	if LeftChatTab then
		if shown then LeftChatTab:Show() else LeftChatTab:Hide() end
	end
	if RightChatTab then
		if shown then RightChatTab:Show() else RightChatTab:Hide() end
	end

	local a = E.db.chat.panelTabTransparency and 0 or 0.8
	if LeftChatTab then pcall(LeftChatTab.SetBackdropColor, LeftChatTab, 0.06, 0.06, 0.06, a) end
	if RightChatTab then pcall(RightChatTab.SetBackdropColor, RightChatTab, 0.06, 0.06, 0.06, a) end
end

function CH:UpdateDataPanelVisibility()
	if not LeftChatDataPanel then return end

	if E.db.datatexts.leftChatPanel then
		LeftChatDataPanel:Show()
		LeftChatToggleButton:Show()
	else
		LeftChatDataPanel:Hide()
		LeftChatToggleButton:Hide()
	end

	if E.db.datatexts.rightChatPanel then
		RightChatDataPanel:Show()
		RightChatToggleButton:Show()
	else
		RightChatDataPanel:Hide()
		RightChatToggleButton:Hide()
	end

	CH:PositionChat()
	CH:UpdateAnchors()
end

function CH:UpdateSettings()
	pcall(ChatFrameEditBox.SetAltArrowKeyMode, ChatFrameEditBox, E.db.chat.useAltKey)
end

function CH:UpdateFading()
	local i
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame"..i]
		if frame then
			pcall(frame.SetFading, frame, E.db.chat.fade)
		end
	end
end

-- ===========================================================================
-- Message pipeline. This REPLACES this module's own `OnEvent` script on
-- every chat window with `id ~= 2` (Combat Log) -- genuinely the highest
-- blast-radius change in this whole module; see this file's own header
-- comment (section 1, above) for the risk tradeoff that this ports
-- anyway, to keep chat text parsing in sync with vanilla and drive the
-- stored settings that would otherwise be inert.
-- Ported closely from ElvUI-vanilla/ElvUI/Modules/Chat/Chat.lua
-- (matching structure, not simplifying, since the goal is vanilla-parity)
-- with these deviations:
--   - `CH:GetColoredName` (class-colors a linked player name) depended on
--     a `ClassCache` module (`CC:GetClassByName`) this project has never
--     built -- `E.private.general` doesn't even exist as a table here.
--     Not ported; `coloredName` is just `arg2` unchanged. Same reasoning
--     drops `CheckKeyword`'s own classColorMentionsChat word-by-word
--     coloring step -- only the KEYWORD-highlight half is ported.
--   - `E.media.hexvaluecolor` is read through this file's own `AccentHex()`
--     accessor (it only exists from `OnInitialize` onwards, so it cannot be
--     captured in a load-time local).
--   - `ConcatenateTimeStamp` uses `Compat.BetterDate` (Core/Compat.lua),
--     same as Time.lua's own datatext.
--   - `UpdateChatKeywords`'s comma-splitting reimplemented with
--     `Compat.gmatch` instead of the reference's bare `split`/`select`
--     combo -- functionally equivalent, avoids depending on an unclear
--     global.
--   - Explicitly NOT ported this round (separate, smaller pieces, not
--     "core parsing" -- pick up later if wanted): `SaveChatHistory`/
--     `DisplayChatHistory` (persists+replays chat across relogs, itself
--     calls back into ChatFrame_OnEvent -- another layer of risk stacked
--     on an already-large change), `DelayGuildMOTD`, `CopyChatFrame`
--     (clipboard-copy window), WIM integration, `SetItemRef`'s
--     channel-link-click-to-switch override (global override of a
--     function every hyperlink click routes through -- higher risk for
--     a peripheral interaction, not parsing), and the hyperlink-hover
--     TOOLTIP specifically (still blocked on "can't hook GameTooltip
--     yet", standing project-wide limitation -- `ItemRefTooltip:
--     SetHyperlink`'s URL click-to-INSERT below is unrelated to tooltips
--     and IS ported, since it's what makes the `url` setting's linkified
--     text actually usable).
--   - CHAT_MSG_SYSTEM is first checked against the client's global
--     `ChatFrame_OnEvent` (`SuppressedByClientHandler`), so messages a
--     wrapped global hides stay hidden. The reference does not do this.
--   - The `id ~= 2` gate (which chat windows get the custom OnEvent at
--     all) is ported unchanged/unquestioned -- the reference doesn't
--     state why Combat Log is excluded, and guessing at "fixing" that
--     risks diverging from "sync with vanilla" for no confirmed reason.
-- Every native global referenced below (ChatTypeInfo, `_G["CHAT_"..type
-- .."_GET"]` format strings, self.channelList/self.zoneChannelList,
-- TEXT()/GetText() macros, LEVEL_UP_* globals, etc.) is UNVERIFIED on UA
-- specifically -- this is the single largest surface of "assumed
-- vanilla-identical behavior" in the whole project. If chat messages
-- render wrong/missing/error after this, look here first.
-- ===========================================================================

local Compat = ElvUI.Compat

local GlobalStrings = {
	AFK = CHAT_MSG_AFK,
	CHAT_FILTERED = CHAT_FILTERED,
	CHAT_IGNORED = CHAT_IGNORED,
	CHAT_RESTRICTED = CHAT_RESTRICTED,
	CHAT_TELL_ALERT_TIME = CHAT_TELL_ALERT_TIME,
	DND = CHAT_MSG_DND,
	CHAT_MSG_RAID_WARNING = CHAT_MSG_RAID_WARNING,
}

-- Built on first use, not at file load: this file loads before the "Addon
-- Language" setting is applied (Locales/Locales.lua).
local DEFAULT_STRINGS

local function DefaultStrings()
	if not DEFAULT_STRINGS then
		DEFAULT_STRINGS = {
			BATTLEGROUND = L["BG"],
			GUILD = L["G"],
			PARTY = L["P"],
			RAID = L["R"],
			OFFICER = L["O"],
			BATTLEGROUND_LEADER = L["BGL"],
			RAID_LEADER = L["RL"],
		}
	end
	return DEFAULT_STRINGS
end

local FindURL_Events = {
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_BATTLEGROUND_LEADER", "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY",
	"CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_AFK", "CHAT_MSG_DND",
}

local chatFilters = {}
local msgList, msgCount, msgTime = {}, {}, {}
local protectLinks = {}
CH.Keywords = {}

local function PrepareMessage(author, message)
	if not author then return message end
	return string.upper(author)..message
end

function CH:ChatFrame_AddMessageEventFilter(event, filter)
	if not chatFilters[event] then chatFilters[event] = {} end
	local i
	for i = 1, table.getn(chatFilters[event]) do
		if chatFilters[event][i] == filter then return end
	end
	table.insert(chatFilters[event], filter)
end

function CH:ChatFrame_RemoveMessageEventFilter(event, filter)
	if not chatFilters[event] then return end
	local i
	for i = 1, table.getn(chatFilters[event]) do
		if chatFilters[event][i] == filter then
			table.remove(chatFilters[event], i)
			return
		end
	end
end

function CH:PrintURL(url)
	return "|cFFFFFFFF[|Hurl:"..url.."|h"..url.."|h]|r "
end

function CH:ThrottleSound()
	self.SoundPlayed = nil
end

-- `noAlertInCombat` -- real ElvUI's own FindURL/CheckKeyword don't
-- actually gate these sounds on combat state despite having the setting
-- (same class of "setting exists, nothing reads it" gap as DataBars/
-- XPBar's own hideInCombat). Wired up here rather than left inert.
local function AlertsAllowed()
	if E.db.chat.noAlertInCombat and UnitAffectingCombat("player") then
		return false
	end
	return true
end

function CH:FindURL(event, msg, ...)
	if event and event == "CHAT_MSG_WHISPER" and E.db.chat.whisperSound ~= "None" and not CH.SoundPlayed and AlertsAllowed() then
		local sound = LSM and LSM:Fetch("sound", E.db.chat.whisperSound)
		if sound then pcall(PlaySoundFile, sound, "Master") end
		CH.SoundPlayed = true
		CH.SoundTimer = E:ScheduleTimer(function() CH:ThrottleSound() end, 1)
	end

	if not E.db.chat.url then
		msg = CH:CheckKeyword(msg)
		return false, msg, unpack(arg)
	end

	msg = string.gsub(string.gsub(msg, "(%S)(|c.-|H.-|h.-|h|r)", '%1 %2'), "(|c.-|H.-|h.-|h|r)(%S)", "%1 %2")
	-- http://example.com
	local newMsg, found = string.gsub(msg, "(%a+)://(%S+)%s?", CH:PrintURL("%1://%2"))
	if found > 0 then return false, CH:CheckKeyword(newMsg), unpack(arg) end
	-- www.example.com
	newMsg, found = string.gsub(msg, "www%.([_A-Za-z0-9-]+)%.(%S+)%s?", CH:PrintURL("www.%1.%2"))
	if found > 0 then return false, CH:CheckKeyword(newMsg), unpack(arg) end
	-- example@example.com
	newMsg, found = string.gsub(msg, "([_A-Za-z0-9-%.]+)@([_A-Za-z0-9-]+)(%.+)([_A-Za-z0-9-%.]+)%s?", CH:PrintURL("%1@%2%3%4"))
	if found > 0 then return false, CH:CheckKeyword(newMsg), unpack(arg) end
	-- IP address with port 1.1.1.1:1
	newMsg, found = string.gsub(msg, "(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)(:%d+)%s?", CH:PrintURL("%1.%2.%3.%4%5"))
	if found > 0 then return false, CH:CheckKeyword(newMsg), unpack(arg) end
	-- IP address 1.1.1.1
	newMsg, found = string.gsub(msg, "(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%s?", CH:PrintURL("%1.%2.%3.%4"))
	if found > 0 then return false, CH:CheckKeyword(newMsg), unpack(arg) end

	msg = CH:CheckKeyword(msg)
	return false, msg, unpack(arg)
end

function CH:ShortChannel()
	return string.format("|Hchannel:%s|h[%s]|h", self, DefaultStrings()[string.upper(self)] or string.gsub(self, "channel:", ""))
end

function CH:ConcatenateTimeStamp(msg)
	local db = E.db.chat
	if db.timeStampFormat and db.timeStampFormat ~= "NONE" then
		local timeStamp = Compat.BetterDate(db.timeStampFormat, time())
		timeStamp = string.gsub(timeStamp, " ", "")
		timeStamp = string.gsub(timeStamp, "AM", " AM")
		timeStamp = string.gsub(timeStamp, "PM", " PM")
		if db.useCustomTimeColor then
			local c = db.customTimeColor
			local hexColor = E:RGBToHex(c.r, c.g, c.b)
			msg = string.format("%s[%s]|r %s", hexColor, timeStamp, msg)
		else
			msg = string.format("[%s] %s", timeStamp, msg)
		end
	end
	return msg
end

function CH:UpdateChatKeywords()
	local k
	for k in pairs(CH.Keywords) do
		CH.Keywords[k] = nil
	end

	local keywords = E.db.chat.keywords or ""
	keywords = string.gsub(keywords, "%%MYNAME%%", E.myname or "")
	keywords = string.gsub(keywords, ",%s+", ",")

	local part
	for part in Compat.gmatch(keywords..",", "([^,]*),") do
		if part ~= "" then
			CH.Keywords[part] = true
		end
	end
end

-- Keyword-highlight half only, see this section's header comment for why
-- the class-color-mentions half isn't ported.
function CH:CheckKeyword(message)
	local itemLink
	for itemLink in Compat.gmatch(message, "|%x+|Hitem:.-|h.-|h|r") do
		protectLinks[itemLink] = string.gsub(itemLink, "%s", "|s")
		local keyword
		for keyword in pairs(CH.Keywords) do
			if itemLink == keyword then
				if E.db.chat.keywordSound ~= "None" and not CH.SoundPlayed and AlertsAllowed() then
					local sound = LSM and LSM:Fetch("sound", E.db.chat.keywordSound)
					if sound then pcall(PlaySoundFile, sound, "Master") end
					CH.SoundPlayed = true
					CH.SoundTimer = E:ScheduleTimer(function() CH:ThrottleSound() end, 1)
				end
			end
		end
	end

	local link, tempLink
	for link, tempLink in pairs(protectLinks) do
		message = string.gsub(message, string.gsub(link, "([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"), tempLink)
	end

	local tempWord, lowerCaseWord, rebuiltString
	local isFirstWord = true
	local word
	for word in Compat.gmatch(message, "%s-[^%s]+%s*") do
		tempWord = string.gsub(word, "[%s%p]", "")
		lowerCaseWord = string.lower(tempWord)

		local keyword
		for keyword in pairs(CH.Keywords) do
			if lowerCaseWord == string.lower(keyword) then
				word = string.gsub(word, tempWord, AccentHex()..tempWord.."|r")
				if E.db.chat.keywordSound ~= "None" and not CH.SoundPlayed and AlertsAllowed() then
					local sound = LSM and LSM:Fetch("sound", E.db.chat.keywordSound)
					if sound then pcall(PlaySoundFile, sound, "Master") end
					CH.SoundPlayed = true
					CH.SoundTimer = E:ScheduleTimer(function() CH:ThrottleSound() end, 1)
				end
			end
		end

		if isFirstWord then
			rebuiltString = word
			isFirstWord = false
		else
			rebuiltString = rebuiltString..word
		end
	end
	rebuiltString = rebuiltString or message

	for link, tempLink in pairs(protectLinks) do
		rebuiltString = string.gsub(rebuiltString, string.gsub(tempLink, "([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"), link)
		protectLinks[link] = nil
	end

	return rebuiltString
end

function CH:DisableChatThrottle()
	local k
	for k in pairs(msgList) do msgList[k] = nil end
	for k in pairs(msgCount) do msgCount[k] = nil end
	for k in pairs(msgTime) do msgTime[k] = nil end
end

function CH:ChatThrottleHandler(author, message)
	if author and author ~= "" then
		local msg = PrepareMessage(author, message)
		if msgList[msg] == nil then
			msgList[msg] = true
			msgCount[msg] = 1
			msgTime[msg] = time()
		else
			msgCount[msg] = msgCount[msg] + 1
		end
	end
end

-- These 3 are picked up automatically by `WireMessagePipeline`'s
-- `CH[event] or CH.FindURL` lookup (their method names are literally the
-- event names) -- called as plain filter functions, `self` below is the
-- CHAT FRAME, not the CH module, matching FindURL's own calling
-- convention exactly.
function CH:CHAT_MSG_CHANNEL(event, message, author, ...)
	local blockFlag = false
	local msg = PrepareMessage(author, message)

	if author == E.myname then return CH.FindURL(self, event, message, author, unpack(arg)) end
	if msgList[msg] and E.db.chat.throttleInterval ~= 0 then
		if (time() - msgTime[msg]) <= E.db.chat.throttleInterval then
			blockFlag = true
		end
	end

	if blockFlag then
		return true
	else
		if E.db.chat.throttleInterval ~= 0 then
			msgTime[msg] = time()
		end
		return CH.FindURL(self, event, message, author, unpack(arg))
	end
end

function CH:CHAT_MSG_YELL(event, message, author, ...)
	local blockFlag = false
	local msg = PrepareMessage(author, message)

	if msg == nil then return CH.FindURL(self, event, message, author, unpack(arg)) end
	if author == E.myname then return CH.FindURL(self, event, message, author, unpack(arg)) end
	if msgList[msg] and msgCount[msg] and msgCount[msg] > 1 and E.db.chat.throttleInterval ~= 0 then
		if (time() - msgTime[msg]) <= E.db.chat.throttleInterval then
			blockFlag = true
		end
	end

	if blockFlag then
		return true
	else
		if E.db.chat.throttleInterval ~= 0 then
			msgTime[msg] = time()
		end
		return CH.FindURL(self, event, message, author, unpack(arg))
	end
end

function CH:CHAT_MSG_SAY(event, message, author, ...)
	return CH.FindURL(self, event, message, author, unpack(arg))
end

function CH:GetGroupDistribution()
	local okInstance, inInstance, kind = pcall(IsInInstance)
	if okInstance and inInstance and kind == "pvp" then
		return "/bg "
	end
	if GetNumRaidMembers() > 0 then
		return "/ra "
	end
	if GetNumPartyMembers() > 0 then
		return "/p "
	end
	return "/s "
end

local function OnTextChanged()
	local self = this
	local text = self:GetText()

	if UnitAffectingCombat("player") then
		local minRepeat = E.db.chat.numAllowedCombatRepeat
		if string.len(text) > minRepeat then
			local repeatChar = true
			local i
			for i = 1, minRepeat do
				if string.sub(text, (0 - i), (0 - i)) ~= string.sub(text, (-1 - i), (-1 - i)) then
					repeatChar = false
					break
				end
			end
			if repeatChar then
				self:Hide()
				return
			end
		end
	end

	if string.len(text) < 5 then
		if string.sub(text, 1, 4) == "/tt " then
			local unitname, realm = UnitName("target")
			if unitname and realm then
				unitname = unitname.."-"..string.gsub(realm, " ", "")
			end
			pcall(ChatFrame_SendTell, unitname or L["Invalid Target"], ChatFrame1)
		end

		if string.sub(text, 1, 4) == "/gr " then
			self:SetText(CH:GetGroupDistribution()..string.sub(text, 5))
			pcall(ChatEdit_ParseText, self, 0)
		end
	end

	local new, found = string.gsub(text, "|Kf(%S+)|k(%S+)%s(%S+)|k", "%2 %3")
	if found > 0 then
		new = string.gsub(new, "|", "")
		self:SetText(new)
	end
end
CH.OnTextChanged = OnTextChanged

function CH:ChatEdit_UpdateHeader(editbox)
	local ctype = editbox.chatType
	if ctype == "CHANNEL" then
		local id = GetChannelName(editbox.channelTarget)
		if id == 0 then
			pcall(editbox.SetBackdropBorderColor, editbox, 0, 0, 0, 1)
		else
			local info = ChatTypeInfo[ctype..id]
			if info then
				pcall(editbox.SetBackdropBorderColor, editbox, info.r, info.g, info.b)
			end
		end
	elseif ctype then
		local info = ChatTypeInfo[ctype]
		if info then
			pcall(editbox.SetBackdropBorderColor, editbox, info.r, info.g, info.b)
		end
	end
end

function CH:ChatEdit_OnEnterPressed()
	local ctype = this.chatType
	local info = ChatTypeInfo[ctype]
	if info and info.sticky == 1 then
		if not E.db.chat.sticky then ctype = "SAY" end
		this.chatType = ctype
	end
end

-- The client's global `ChatFrame_OnEvent` can be wrapped to hide messages
-- that are really data, e.g. a server's own UI addon talking to itself over
-- CHAT_MSG_SYSTEM ("PRESTIGEUI <name> <value>" on Project Legacy). The OnEvent
-- replacement below never calls that global, so it would print those lines.
-- This dry-runs the global handler with the frame's AddMessage stubbed out:
-- if it prints nothing, the client suppressed the message.
-- Limited to CHAT_MSG_SYSTEM: the stock SYSTEM branch does nothing besides
-- AddMessage, while other branches play sounds, flash tabs or edit
-- `channelList`, which a dry run would duplicate. Every failure path (a
-- different handler signature, an instance field that does not shadow the
-- method) answers "not suppressed", so a message is never lost by accident.
local function SuppressedByClientHandler(frame, event)
	local handler = ChatFrame_OnEvent
	if type(handler) ~= "function" then return false end

	local printed = false
	local stub = function() printed = true end
	local okRaw, prior = pcall(rawget, frame, "AddMessage")
	if not okRaw then prior = nil end
	if not pcall(function() frame.AddMessage = stub end) then return false end
	if frame.AddMessage ~= stub then
		pcall(function() frame.AddMessage = prior end)
		return false
	end

	local savedThis = this
	this = frame
	local ok = pcall(handler, event)
	this = savedThis
	frame.AddMessage = prior

	return ok and not printed
end

function CH:ChatFrame_OnEvent(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
	if event == "UPDATE_CHAT_WINDOWS" then
		local _, fontSize, _, _, _, _, shown = GetChatWindowInfo(self:GetID())
		if fontSize and fontSize > 0 then
			local fontFile, _, fontFlags = self:GetFont()
			pcall(self.SetFont, self, fontFile, fontSize, fontFlags)
		end
		if shown then
			self:Show()
		end
		pcall(ChatFrame_RegisterForMessages, GetChatWindowMessages(self:GetID()))
		pcall(ChatFrame_RegisterForChannels, GetChatWindowChannels(self:GetID()))
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		self.defaultLanguage = GetDefaultLanguage()
		return
	end
	if event == "TIME_PLAYED_MSG" then
		pcall(ChatFrame_DisplayTimePlayed, arg1, arg2)
		return
	end
	if event == "PLAYER_LEVEL_UP" then
		local info = ChatTypeInfo["SYSTEM"]
		local msg = string.format(TEXT(LEVEL_UP), arg1)
		self:AddMessage(msg, info.r, info.g, info.b, info.id)

		if arg3 and arg3 > 0 then
			msg = string.format(TEXT(LEVEL_UP_HEALTH_MANA), arg2, arg3)
		else
			msg = string.format(TEXT(LEVEL_UP_HEALTH), arg2)
		end
		self:AddMessage(msg, info.r, info.g, info.b, info.id)

		if arg4 and arg4 > 0 then
			msg = string.format(GetText("LEVEL_UP_CHAR_POINTS", nil, arg4), arg4)
			self:AddMessage(msg, info.r, info.g, info.b, info.id)
		end
		if arg5 and arg5 > 0 then
			msg = string.format(TEXT(LEVEL_UP_STAT), TEXT(SPELL_STAT0_NAME), arg5)
			self:AddMessage(msg, info.r, info.g, info.b, info.id)
		end
		if arg6 and arg6 > 0 then
			msg = string.format(TEXT(LEVEL_UP_STAT), TEXT(SPELL_STAT1_NAME), arg6)
			self:AddMessage(msg, info.r, info.g, info.b, info.id)
		end
		if arg7 and arg7 > 0 then
			msg = string.format(TEXT(LEVEL_UP_STAT), TEXT(SPELL_STAT2_NAME), arg7)
			self:AddMessage(msg, info.r, info.g, info.b, info.id)
		end
		if arg8 and arg8 > 0 then
			msg = string.format(TEXT(LEVEL_UP_STAT), TEXT(SPELL_STAT3_NAME), arg8)
			self:AddMessage(msg, info.r, info.g, info.b, info.id)
		end
		if arg9 and arg9 > 0 then
			msg = string.format(TEXT(LEVEL_UP_STAT), TEXT(SPELL_STAT4_NAME), arg9)
			self:AddMessage(msg, info.r, info.g, info.b, info.id)
		end
		return
	end
	if event == "CHARACTER_POINTS_CHANGED" then
		local info = ChatTypeInfo["SYSTEM"]
		if arg2 and arg2 > 0 then
			local _, cp2 = UnitCharacterPoints("player")
			if cp2 then
				local msg = string.format(GetText("LEVEL_UP_SKILL_POINTS", nil, cp2), cp2)
				self:AddMessage(msg, info.r, info.g, info.b, info.id)
			end
		end
		return
	end
	if event == "GUILD_MOTD" then
		if arg1 and string.len(arg1) > 0 then
			local info = ChatTypeInfo["GUILD"]
			local msg = string.format(TEXT(GUILD_MOTD_TEMPLATE), arg1)
			self:AddMessage(msg, info.r, info.g, info.b, info.id)
		end
		return
	end
	if event == "EXECUTE_CHAT_LINE" then
		self.editBox:SetText(arg1)
		pcall(ChatEdit_SendText, self.editBox)
		pcall(ChatEdit_OnEscapePressed, self.editBox)
		return
	end
	if event == "UPDATE_CHAT_COLOR" then
		local info = ChatTypeInfo[string.upper(arg1)]
		if info then
			info.r, info.g, info.b = arg2, arg3, arg4
			pcall(self.UpdateColorByID, self, info.id, info.r, info.g, info.b)
			if string.upper(arg1) == "WHISPER" then
				info = ChatTypeInfo["REPLY"]
				if info then
					info.r, info.g, info.b = arg2, arg3, arg4
					pcall(self.UpdateColorByID, self, info.id, info.r, info.g, info.b)
				end
			end
		end
		return
	end
	if string.sub(event, 1, 8) == "CHAT_MSG" then
		local msgType = string.sub(event, 10)
		local info = ChatTypeInfo[msgType]
		if not info then return end
		if msgType == "SYSTEM" and SuppressedByClientHandler(self, event) then
			return true
		end

		local filter, newarg1, newarg2, newarg3, newarg4, newarg5, newarg6, newarg7, newarg8, newarg9, newarg10 = false
		if chatFilters[event] then
			local _, filterFunc
			for _, filterFunc in pairs(chatFilters[event]) do
				filter, newarg1, newarg2, newarg3, newarg4, newarg5, newarg6, newarg7, newarg8, newarg9, newarg10 = filterFunc(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
				arg1 = newarg1 or arg1
				if filter then
					return true
				elseif newarg1 and newarg2 then
					arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10 = newarg1, newarg2, newarg3, newarg4, newarg5, newarg6, newarg7, newarg8, newarg9, newarg10
				end
			end
		end

		local coloredName = arg2

		local channelLength = arg4 and string.len(arg4)
		if (string.sub(msgType, 1, 7) == "CHANNEL") and (msgType ~= "CHANNEL_LIST") and ((arg1 ~= "INVITE") or (msgType ~= "CHANNEL_NOTICE_USER")) then
			if arg1 == "WRONG_PASSWORD" then
				local okPopup, popupName = pcall(StaticPopup_Visible, "CHAT_CHANNEL_PASSWORD")
				local staticPopup = okPopup and popupName and _G[popupName]
				if staticPopup and staticPopup.data == arg9 then
					-- Don't display invalid password messages if we're going to prompt for a password
					return
				end
			end

			local found = 0
			if self.channelList then
				local index, value
				for index, value in pairs(self.channelList) do
					if channelLength and channelLength > string.len(value) then
						if (arg7 and arg7 > 0 and self.zoneChannelList and self.zoneChannelList[index] == arg7) or (string.upper(value) == string.upper(arg9 or "")) then
							found = 1
							info = ChatTypeInfo["CHANNEL"..arg8]
							if (msgType == "CHANNEL_NOTICE") and (arg1 == "YOU_LEFT") then
								self.channelList[index] = nil
								self.zoneChannelList[index] = nil
							end
							break
						end
					end
				end
			end
			if found == 0 or not info then
				return true
			end
		end

		if msgType == "SYSTEM" or msgType == "TEXT_EMOTE" or msgType == "SKILL" or msgType == "LOOT" or msgType == "MONEY"
			or msgType == "OPENING" or msgType == "TRADESKILLS" or msgType == "PET_INFO" then
			self:AddMessage(CH:ConcatenateTimeStamp(arg1), info.r, info.g, info.b, info.id)
		elseif string.sub(msgType, 1, 7) == "COMBAT_" then
			self:AddMessage(CH:ConcatenateTimeStamp(arg1), info.r, info.g, info.b, info.id)
		elseif string.sub(msgType, 1, 6) == "SPELL_" then
			self:AddMessage(CH:ConcatenateTimeStamp(arg1), info.r, info.g, info.b, info.id)
		elseif string.sub(msgType, 1, 10) == "BG_SYSTEM_" then
			self:AddMessage(CH:ConcatenateTimeStamp(arg1), info.r, info.g, info.b, info.id)
		elseif msgType == "IGNORED" then
			self:AddMessage(string.format(CH:ConcatenateTimeStamp(GlobalStrings.CHAT_IGNORED), arg2), info.r, info.g, info.b, info.id)
		elseif msgType == "FILTERED" then
			self:AddMessage(string.format(CH:ConcatenateTimeStamp(GlobalStrings.CHAT_FILTERED), arg2), info.r, info.g, info.b, info.id)
		elseif msgType == "RESTRICTED" then
			self:AddMessage(CH:ConcatenateTimeStamp(GlobalStrings.CHAT_RESTRICTED), info.r, info.g, info.b, info.id)
		elseif msgType == "CHANNEL_LIST" then
			if channelLength and channelLength > 0 then
				self:AddMessage(string.format(CH:ConcatenateTimeStamp(_G["CHAT_"..msgType.."_GET"]..arg1), arg4), info.r, info.g, info.b, info.id)
			else
				self:AddMessage(CH:ConcatenateTimeStamp(arg1), info.r, info.g, info.b, info.id)
			end
		elseif msgType == "CHANNEL_NOTICE_USER" then
			local globalstring = CH:ConcatenateTimeStamp(_G["CHAT_"..arg1.."_NOTICE"])
			if arg5 and string.len(arg5) > 0 then
				self:AddMessage(string.format(globalstring, arg4, arg2, arg5), info.r, info.g, info.b, info.id)
			else
				self:AddMessage(string.format(globalstring, arg4, arg2), info.r, info.g, info.b, info.id)
			end
		elseif msgType == "CHANNEL_NOTICE" then
			local globalstring = _G["CHAT_"..arg1.."_NOTICE"]
			if arg10 and arg10 > 0 then
				arg4 = arg4.." "..arg10
			end
			self:AddMessage(string.format(CH:ConcatenateTimeStamp(globalstring), arg4), info.r, info.g, info.b, info.id)
		else
			local body

			local pflag
			if arg6 and arg6 ~= "" then
				if arg6 == "DND" or arg6 == "AFK" then
					pflag = (pflag or "").._G["CHAT_FLAG_"..arg6]
				else
					pflag = _G["CHAT_FLAG_"..arg6]
				end
			end
			pflag = pflag or ""

			local showLink = 1
			if string.sub(msgType, 1, 7) == "MONSTER" or msgType == "RAID_BOSS_EMOTE" then
				showLink = nil
			else
				arg1 = string.gsub(arg1, "%%", "%%%%")
			end

			if arg3 and string.len(arg3) > 0 and arg3 ~= "Universal" and arg3 ~= GetDefaultLanguage() then
				local languageHeader = "["..arg3.."] "
				if showLink and arg2 and string.len(arg2) > 0 then
					body = string.format(_G["CHAT_"..msgType.."_GET"]..languageHeader..arg1, pflag.."|Hplayer:"..arg2.."|h".."["..coloredName.."]".."|h")
				else
					body = string.format(_G["CHAT_"..msgType.."_GET"]..languageHeader..arg1, pflag..(arg2 or ""))
				end
			else
				if showLink and arg2 and string.len(arg2) > 0 then
					body = string.format(_G["CHAT_"..msgType.."_GET"]..arg1, pflag.."|Hplayer:"..arg2.."|h".."["..coloredName.."]".."|h")
				else
					arg1 = string.gsub(arg1, "%%s %%s", "%%s")
					body = string.format(_G["CHAT_"..msgType.."_GET"]..arg1, pflag..(arg2 or ""))

					if msgType == "RAID_BOSS_EMOTE" then
						pcall(RaidBossEmoteFrame.AddMessage, RaidBossEmoteFrame, body, info.r, info.g, info.b, 1.0)
						pcall(PlaySound, "RaidBossEmoteWarning")
					end
				end
			end

			arg4 = arg4 and string.gsub(arg4, "%s%-%s.*", "") or arg4
			if channelLength and channelLength > 0 then
				body = "|Hchannel:channel:"..arg8.."|h["..arg4.."]|h "..body
			end

			if E.db.chat.shortChannels then
				body = string.gsub(body, "|Hchannel:(.-)|h%[(.-)%]|h", CH.ShortChannel)
				body = string.gsub(body, "CHANNEL:", "")
				-- The three verbs are matched against the client's own chat
				-- line (built from its CHAT_*_GET globals), so their
				-- translations must use that locale's client wording, and
				-- must not contain Lua pattern magic characters.
				body = string.gsub(body, "^(.-|h) "..L["whispers"], "%1")
				body = string.gsub(body, "^(.-|h) "..L["says"], "%1")
				body = string.gsub(body, "^(.-|h) "..L["yells"], "%1")
				body = string.gsub(body, "<"..GlobalStrings.AFK..">", "[|cffFF0000"..L["AFK"].."|r] ")
				body = string.gsub(body, "<"..GlobalStrings.DND..">", "[|cffE7E716"..L["DND"].."|r] ")
				body = string.gsub(body, "^%["..GlobalStrings.CHAT_MSG_RAID_WARNING.."%]", "["..L["RW"].."]")
			end
			self:AddMessage(CH:ConcatenateTimeStamp(body), info.r, info.g, info.b, info.id)
		end

		if msgType == "WHISPER" then
			pcall(ChatEdit_SetLastTellTarget, self.editBox, arg2)
			if self.tellTimer and GetTime() > self.tellTimer then
				pcall(PlaySound, "TellMessage")
			end
			self.tellTimer = GetTime() + (GlobalStrings.CHAT_TELL_ALERT_TIME or 10)
			pcall(FCF_FlashTab)
		end

		return true
	end
end

function CH:FloatingChatFrame_OnEvent()
	if CH:ChatFrame_OnEvent(this, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10) then return end
	FloatingChatFrame_OnEvent(event)
end

-- Installs the OnEvent replacement (id ~= 2 only, matching the reference's
-- own gate), registers the URL/throttle filters, hooks the editbox header/
-- sticky-channel behavior, installs the URL click-to-insert override on
-- ItemRefTooltip, marks the sticky chat types, and builds the keyword
-- list. Idempotent -- safe to call more than once.
function CH:WireMessagePipeline()
	if self.messagePipelineWired then return end

	local i
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame"..i]
		if frame then
			local okId, id = pcall(frame.GetID, frame)
			if okId and id ~= 2 then
				frame:SetScript("OnEvent", CH.FloatingChatFrame_OnEvent)
			end
		end
	end

	for i = 1, table.getn(FindURL_Events) do
		local event = FindURL_Events[i]
		CH:ChatFrame_AddMessageEventFilter(event, CH[event] or CH.FindURL)
	end

	-- Bare `hooksecurefunc` isn't a global function on this client at
	-- all, so these hooks use AceHook-3.0's own `:SecureHook(globalName,
	-- handler)` instead (the bare global-function-name string overload --
	-- CH already mixes in "AceHook-3.0") -- the same fix proven working
	-- for this exact failure mode elsewhere in this project (UnitFrames.
	-- lua's own Castbar icon-capture hooks).
	pcall(function() CH:SecureHook("ChatEdit_UpdateHeader", function(editbox) CH:ChatEdit_UpdateHeader(editbox) end) end)
	pcall(function() CH:SecureHook("ChatEdit_OnEnterPressed", function() CH:ChatEdit_OnEnterPressed() end) end)

	local okNative, nativeSetHyperlink = pcall(function() return ItemRefTooltip.SetHyperlink end)
	if okNative and nativeSetHyperlink then
		ItemRefTooltip.SetHyperlink = function(tooltip, data, ...)
			if string.sub(data, 1, 3) == "url" then
				local currentLink = string.sub(data, 5)
				if not ChatFrameEditBox:IsShown() then
					ChatFrameEditBox:Show()
					pcall(ChatEdit_UpdateHeader, ChatFrameEditBox)
				end
				ChatFrameEditBox:Insert(currentLink)
				ChatFrameEditBox:HighlightText()
			else
				nativeSetHyperlink(tooltip, data, unpack(arg))
			end
		end
	end

	local _, stickyType
	for _, stickyType in pairs({ "SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "RAID", "RAID_WARNING", "BATTLEGROUND", "GUILD", "OFFICER", "CHANNEL" }) do
		if ChatTypeInfo[stickyType] then
			ChatTypeInfo[stickyType].sticky = 1
		end
	end

	self:UpdateChatKeywords()

	self.messagePipelineWired = true
end

-- ===========================================================================
-- Initialize
-- ===========================================================================
function CH:Initialize()
	self.db = E.db.chat

	if E.private.chat.enable ~= true then return end

	ElvCharacterDB = ElvCharacterDB or {}
	ElvCharacterDB.ChatEditHistory = ElvCharacterDB.ChatEditHistory or {}

	self:CreateChatPanels()
	self:StyleChatFrame(ChatFrame1)
	self:ApplyFont(ChatFrame1)
	self:SkinEditBox()
	self:UpdateFading()
	self:EnableWheelScroll(ChatFrame1)
	self:HideNativeChatButtons()
	self:StyleAllChatTabs()
	self:WireMessagePipeline()

	pcall(ChatFrame1.SetTimeVisible, ChatFrame1, 100)

	pcall(DEFAULT_CHAT_FRAME.SetParent, DEFAULT_CHAT_FRAME, LeftChatContent or LeftChatPanel)

	-- The native dock is filled after this point at login, and windows can be
	-- docked/undocked at any time; both paths end in FCF_DockUpdate or
	-- FCF_UnDockFrame, so the container's membership follows them.
	pcall(function() CH:SecureHook("FCF_DockUpdate", AdoptLeftDock) end)
	pcall(function() CH:SecureHook("FCF_UnDockFrame", AdoptLeftDock) end)

	-- Matches real ElvUI's own one-shot delayed PositionChat -- the
	-- native chat frame's own layout isn't necessarily settled yet at
	-- this exact point in the login sequence.
	E:Delay(0.05, function()
		CH:PositionChat()
		CH:UpdateAnchors()
	end)

	-- ChatFrameMenuButton/Up/Down/BottomButton can reappear after a plain
	-- /reload -- consistent with Blizzard re-creating/re-showing them
	-- lazily sometime after login, same class of problem as
	-- ExhaustionTick/GameTimeFrame elsewhere in this project. Resweep,
	-- not just a one-time kill.
	ElvUI.Util.ScheduleLimitedSweep(function()
		CH:HideNativeChatButtons()
		CH:RestyleChatTab()
		CH:StyleAllChatTabs()
	end, 3, 10)

	-- See PositionChat's own ROOT CAUSE comment for the "chat frame
	-- randomly shrinks" bug and its primary fix (`SetUserPlaced(true)`
	-- called unconditionally). Diagnosing it required read-only anchor
	-- introspection (`GetNumPoints`/`GetPoint`) rather than intercepting
	-- the call: hooking a native frame method here is a dead end on UA
	-- either via AceHook-3.0's `SecureHook(obj, method, handler)` object-
	-- method overload or via raw `frame[method] = wrapper` reassignment,
	-- most likely because `UIParent_ManageFramePositions` runs as
	-- protected/secure FrameXML code that bypasses addon-installed method
	-- overrides entirely.
	--
	-- SAFETY NET, kept disabled below: in case `SetUserPlaced` alone
	-- doesn't fully suppress this on UA, this lightweight read-only poll
	-- detects extra anchor points (>2, the known-good count) and restores
	-- the clean anchor via PositionChat() when found. Re-enable (delete
	-- the `--[[`/`--]]` pair below) if the shrink still happens without
	-- it.
	--[[
	local function CheckChatFrameAnchor()
		if not ChatFrame1 then return end
		local okN, n = pcall(ChatFrame1.GetNumPoints, ChatFrame1)
		if okN and n and n > 2 then
			print("ChatFrame1 had "..tostring(n).." anchor points (expected 2) -- restoring PositionChat()'s own anchor.")
			CH:PositionChat()
		end
	end
	E:ScheduleRepeatingTimer(CheckChatFrameAnchor, 1)
	--]]
end

E:RegisterInitialModule(CH:GetName(), function() CH:Initialize() end)
