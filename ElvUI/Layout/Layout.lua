-- Layout -- real ElvUI's own screen-furniture module
-- (source/ElvUI-vanilla/ElvUI/Layout/Layout.lua, `E:NewModule("Layout")`).
-- Upstream it owns three things: the two cosmetic screen-edge strips, the two
-- chat panels (frames, tabs, datatext strips, toggle buttons, fade), and the
-- minimap-adjacent datatext panels.
--
-- HERE, TWO OF THE THREE ARE OWNED BY THIS FILE: the strips and the minimap
-- panels, plus SetDataPanelStyle. The CHAT panels are built by
-- Modules/Chat/Chat.lua, which folded upstream's CreateChatPanels into itself
-- (frame names, mover names and DataTexts:RegisterPanel arguments all match
-- upstream exactly, so nothing about that is lost -- it just lives elsewhere).
-- For that third part this module exposes upstream's Layout METHOD NAMES as a
-- thin delegating layer over Chat's own CH:Update* functions, so that every
-- caller -- config setters above all -- speaks the same API real ElvUI does.
-- Moving the panel code itself is a separate, later step; when it happens, the
-- callers do not change.
--
-- INIT TIER: registered through E:RegisterModule (the SECOND tier, see
-- Init.lua), not E:RegisterInitialModule. `Layout\Load_Layout.xml` loads
-- before `Modules\Load_Modules.xml`, so a first-tier Layout would initialize
-- before the Minimap holder, the chat panels and DataTexts exist -- all of
-- which this module touches. Upstream has the same two tiers but the opposite
-- relative order (its Layout runs at the START of tier two, because it is the
-- one building the chat panels); ours runs at the END, which is the correct
-- direction for a module that only ever references already-built frames.
--
-- No movers and no datatext registration for the two strips -- upstream gives
-- them neither; they are full screen width and purely decorative.

local E, L, V, P, G = unpack(ElvUI)

local LO = E:NewModule("Layout", "AceEvent-3.0")
E.Layout = LO

-- Matches upstream's own PANEL_HEIGHT (Layout.lua:11) -- the height of every
-- panel in this file, strips and minimap panels alike. Chat.lua carries its own
-- copy for the chat panels it still builds.
local PANEL_HEIGHT = 22

-- Pins a strip behind everything else, re-asserted on every Show rather than
-- set once: strata/level are the only thing keeping an action bar or a unit
-- frame from disappearing underneath a full-width panel, and a Show() is
-- exactly when a competing frame may have just been layered on top.
-- `this`-based wrapper form, since script handlers get no self argument here.
local function Panel_OnShow(frame)
	if not frame then return end
	pcall(frame.SetFrameLevel, frame, 0)
	pcall(frame.SetFrameStrata, frame, "BACKGROUND")
end

-- The 1px overhang on every side (-1/+1) is deliberate and comes from
-- upstream: it pushes the strip's own 1px border off-screen, so only the fill
-- is visible and the strip reads as a flat band rather than a boxed frame.
local function CreateScreenPanel(name, topAnchor)
	local panel = CreateFrame("Frame", name, UIParent)
	panel:SetHeight(PANEL_HEIGHT)

	if topAnchor then
		panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -1, 1)
		panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 1, 1)
	else
		panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -1, -1)
		panel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 1, -1)
	end

	E:SetTemplate(panel, "Transparent")
	panel:SetScript("OnShow", function() Panel_OnShow(this) end)
	Panel_OnShow(panel)

	return panel
end

function LO:BottomPanelVisibility()
	if not self.BottomPanel then return end
	if E.db.general.bottomPanel then
		self.BottomPanel:Show()
	else
		self.BottomPanel:Hide()
	end
end

-- `E.db.general.topPanel` has NO declared default, matching real ElvUI, which
-- declares `bottomPanel` and not this one -- nil is the intended "off" state.
-- Waived in scripts/config-exceptions.lua's `reads` table.
function LO:TopPanelVisibility()
	if not self.TopPanel then return end
	if E.db.general.topPanel then
		self.TopPanel:Show()
	else
		self.TopPanel:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- Chat-panel API -- upstream's names, delegating to Modules/Chat/Chat.lua
-- ---------------------------------------------------------------------------
-- Every caller (config setters above all) talks to the Layout module, exactly
-- as it does in real ElvUI. What sits behind the name is currently Chat's own
-- CH:Update* pair, which is the confirmed-working code; when the panel code
-- itself moves here, no caller changes.
--
-- The existence checks are not defensive padding: the Chat module can be
-- switched off entirely (E.private.chat.enable), in which case none of these
-- frames or functions exist at all.
--
-- One upstream method is deliberately absent: RepositionChatDataPanels. It
-- exists there because upstream's ToggleChatPanels gives each datatext strip
-- a SINGLE anchor point, so the strip has to be re-stretched afterwards with
-- four. Chat.lua anchors both strips with two points plus an explicit height,
-- so there is nothing to re-anchor -- and an empty stub would be worse than
-- an absent name.

function LO:SetChatTabStyle()
	local CH = E:GetModule("Chat")
	if CH and CH.UpdateTabStyle then CH:UpdateTabStyle() end
end

-- The two override arguments are upstream's signature (each says "force this
-- side's tab strip hidden regardless of the setting, because that side's panel
-- backdrop is off"). Ours does not need them: CH:UpdateTabStyle derives both
-- the show/hide and the transparency from the settings in one pass. Kept in
-- the signature so a future caller ported from upstream needs no edit.
function LO:ToggleChatTabPanels(rightOverride, leftOverride)
	self:SetChatTabStyle()
end

-- Upstream ToggleChatPanels does THREE things in one function: shows/hides the
-- datatext strips and toggle buttons per E.db.datatexts.leftChatPanel /
-- rightChatPanel, applies the 4-way E.db.chat.panelBackdrop mode, and ends
-- every branch with a ToggleChatTabPanels call. Here those are three separate
-- Chat-side functions, so all three are driven -- dropping the tab one makes
-- the "Tab Panel" setting silently inert, since that is its only applier.
function LO:ToggleChatPanels()
	local CH = E:GetModule("Chat")
	if not CH then return end
	if CH.UpdateDataPanelVisibility then CH:UpdateDataPanelVisibility() end
	if CH.UpdatePanelBackdrop then CH:UpdatePanelBackdrop() end
	self:ToggleChatTabPanels()
end

-- Upstream exposes these three as plain globals (its Layout.lua:113-124) and
-- both its config and its install wizard call them by that name. Dot-called,
-- because Chat's own toggles are argument-less file-locals.
function HideLeftChat()
	local CH = E:GetModule("Chat")
	if CH and CH.ToggleLeftChat then CH.ToggleLeftChat() end
end

function HideRightChat()
	local CH = E:GetModule("Chat")
	if CH and CH.ToggleRightChat then CH.ToggleRightChat() end
end

function HideBothChat()
	HideLeftChat()
	HideRightChat()
end

-- ---------------------------------------------------------------------------
-- Minimap datatext panels
-- ---------------------------------------------------------------------------
-- Real ElvUI creates these here too, not in its Minimap module -- the Minimap
-- module only owns their show/hide (M:UpdateSettings) and the `size` they are
-- derived from. Ours runs in the second init tier precisely so that
-- `E.Minimap.holder` already exists by the time this is called.
--
-- Deliberately parented to the HOLDER, not to Minimap itself, and anchored
-- OUTSIDE the holder's bounds (below its BOTTOM edge) rather than growing the
-- holder's height: the holder IS the mover's drag hit area, and it should
-- match just the map+header visual, not this extra strip. Upstream instead
-- parents to `Minimap.backdrop` and folds the panel height into MMHolder.
--
-- Default widget assignment (Guild left / Friends right) comes from
-- P.datatexts.panels, not hardcoded here.
--
-- Only the two side panels are built. Upstream additionally creates six
-- minimap CORNER panels (TopMiniPanel, BottomLeftMiniPanel, ...) that it
-- neither styles nor shows by default; nothing here consumes them, so they
-- have no config controls either.
local MINI_PANEL_GAP = 2

function LO:CreateMinimapPanels()
	local M = E.Minimap
	local holder = M and M.holder
	if not holder then return end

	local size = E.db.general.minimap.size or 176
	local panelWidth = (size - MINI_PANEL_GAP) / 2

	local lminipanel = CreateFrame("Frame", "LeftMiniPanel", holder)
	lminipanel:SetWidth(panelWidth)
	lminipanel:SetHeight(PANEL_HEIGHT)
	lminipanel:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -2)

	local rminipanel = CreateFrame("Frame", "RightMiniPanel", holder)
	rminipanel:SetWidth(panelWidth)
	rminipanel:SetHeight(PANEL_HEIGHT)
	rminipanel:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -2)

	local DT = E.DataTexts
	if DT then
		DT:RegisterPanel(lminipanel, 1, "ANCHOR_TOPLEFT", 0, 0)
		DT:RegisterPanel(rminipanel, 1, "ANCHOR_TOPRIGHT", 0, 0)
	end

	if E.db.datatexts.minimapPanels then
		lminipanel:Show()
		rminipanel:Show()
	else
		lminipanel:Hide()
		rminipanel:Hide()
	end

	-- DT:LoadDataTexts() already ran at the end of the DataTexts module's own
	-- Initialize, which is in the FIRST init tier -- so these two panels
	-- registered too late to be handed a widget. Re-running it is what fills
	-- them. (DT also re-runs it on PLAYER_ENTERING_WORLD, but relying on that
	-- would leave the panels blank for the first part of the login.)
	if DT and DT.LoadDataTexts then
		DT:LoadDataTexts()
	end
end

-- ---------------------------------------------------------------------------
-- Datatext panel styling
-- ---------------------------------------------------------------------------
-- The consumer for E.db.datatexts.panelTransparency and .panelBackdrop, which
-- until this module existed were declared-but-unread (their config controls
-- were therefore deliberately left out; they are wired now).
--
-- Two different rules, both upstream's (Layout.lua:150-182):
--   * the four chat-side frames honor panelBackdrop -- turning it off means
--     "NoBackdrop", i.e. the strips stay functional and clickable but draw
--     nothing at all.
--   * the two minimap panels ignore panelBackdrop entirely and only follow
--     panelTransparency.
-- `glossTex` is passed for the "Default" template only, again as upstream.
local CHAT_STYLE_FRAMES = {
	"LeftChatDataPanel", "RightChatDataPanel",
	"LeftChatToggleButton", "RightChatToggleButton",
}

local MINIMAP_STYLE_FRAMES = { "LeftMiniPanel", "RightMiniPanel" }

function LO:SetDataPanelStyle()
	local db = E.db.datatexts
	local transparent = db.panelTransparency
	local template = transparent and "Transparent" or "Default"
	local gloss = not transparent

	for _, name in ipairs(CHAT_STYLE_FRAMES) do
		local frame = _G[name]
		if frame then
			if db.panelBackdrop then
				E:SetTemplate(frame, template, gloss)
			else
				E:SetTemplate(frame, "NoBackdrop")
			end
		end
	end

	for _, name in ipairs(MINIMAP_STYLE_FRAMES) do
		local frame = _G[name]
		if frame then
			E:SetTemplate(frame, template, gloss)
		end
	end
end

function LO:Initialize()
	self:CreateMinimapPanels()
	self:SetDataPanelStyle()

	self.BottomPanel = CreateScreenPanel("ElvUI_BottomPanel")
	self:BottomPanelVisibility()

	self.TopPanel = CreateScreenPanel("ElvUI_TopPanel", true)
	self:TopPanelVisibility()
end

E:RegisterModule(LO:GetName(), function() LO:Initialize() end)
