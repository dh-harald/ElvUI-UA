-- First-run setup wizard, matching real ElvUI's own Install screen in
-- spirit (a multi-page popup with Next/Previous/Skip and a page counter)
-- but rebuilt for what this project actually has: real ElvUI's install.lua
-- leans on E:UpdateAll/E:ResetMovers/E:CopyTable/E.PixelMode and
-- raid/raid40/focus unitframes, none of which exist here.
--
-- Content pages are added incrementally; this file currently has Welcome,
-- CVars, Chat, Theme, Resolution, Layout, Auras, and Complete -- same 8
-- pages and order as real ElvUI's own install.lua. Page branches in
-- SetPage below must stay a contiguous 1..MAX_PAGE range -- bump
-- MAX_PAGE when inserting a page.

local E, L, V, P, G = unpack(ElvUI)

local MAX_PAGE = 8

local installStepComplete

-- Small confirmation toast shown after a content page's action button
-- runs (e.g. "CVars Set") -- ported from real ElvUI's own
-- InstallStepComplete (source/ElvUI-vanilla/.../install.lua:853-899),
-- reusing the LevelUpTex asset already vendored in this project
-- (Media/Textures/LevelUpTex.blp). Plain Show()-then-delayed-Hide()
-- instead of real ElvUI's UIFrameFadeOut -- matches this project's own
-- established choice elsewhere (Modules/Chat/Chat.lua's toggle-button
-- fade) of a plain toggle over a native fade animation whose reliability
-- on UA is unverified.
local function ShowStepComplete(message)
	if not installStepComplete then
		local ok, imsg = pcall(CreateFrame, "Frame", "ElvUIInstallStepComplete", UIParent)
		if not ok or not imsg then return end
		installStepComplete = imsg

		pcall(imsg.SetWidth, imsg, 418)
		pcall(imsg.SetHeight, imsg, 72)
		pcall(imsg.SetPoint, imsg, "TOP", UIParent, "TOP", 0, -190)
		pcall(imsg.SetFrameStrata, imsg, "FULLSCREEN_DIALOG")
		pcall(imsg.Hide, imsg)

		local okBg, bg = pcall(imsg.CreateTexture, imsg, nil, "BACKGROUND")
		if okBg and bg then
			pcall(bg.SetTexture, bg, "Interface\\AddOns\\ElvUI\\Media\\Textures\\LevelUpTex")
			pcall(bg.SetPoint, bg, "BOTTOM", imsg, "BOTTOM", 0, 0)
			pcall(bg.SetWidth, bg, 326)
			pcall(bg.SetHeight, bg, 103)
			pcall(bg.SetTexCoord, bg, 0.00195313, 0.63867188, 0.03710938, 0.23828125)
			pcall(bg.SetVertexColor, bg, 1, 1, 1, 0.6)
		end

		local i
		for i = 1, 2 do
			local point = (i == 1) and "TOP" or "BOTTOM"
			local okLine, line = pcall(imsg.CreateTexture, imsg, nil, "BACKGROUND")
			if okLine and line then
				pcall(line.SetDrawLayer, line, "BACKGROUND", 2)
				pcall(line.SetTexture, line, "Interface\\AddOns\\ElvUI\\Media\\Textures\\LevelUpTex")
				pcall(line.SetPoint, line, point, imsg, point, 0, 0)
				pcall(line.SetWidth, line, 418)
				pcall(line.SetHeight, line, 7)
				pcall(line.SetTexCoord, line, 0.00195313, 0.81835938, 0.01953125, 0.03320313)
			end
		end

		local okText, text = pcall(imsg.CreateFontString, imsg, nil, "OVERLAY")
		if okText and text then
			E:FontTemplate(text, E.media and E.media.normFont, 32, "OUTLINE")
			pcall(text.SetPoint, text, "BOTTOM", imsg, "BOTTOM", 0, 16)
			pcall(text.SetTextColor, text, 1, 0.82, 0)
			pcall(text.SetJustifyH, text, "CENTER")
		end
		imsg.text = text
	end

	if installStepComplete.text then
		pcall(installStepComplete.text.SetText, installStepComplete.text, message)
	end
	-- "Master" channel argument matches this project's own established
	-- PlaySoundFile usage (Modules/Chat/Chat.lua) -- omitting it is a
	-- likely silent-no-sound cause on this client. Fetched through LSM
	-- (Media/SharedMedia.lua's "ElvUI LevelUp" entry) with the same
	-- literal as a fallback for a call that lands before LSM is ready.
	local LSM = LibStub("LibSharedMedia-3.0", true)
	local soundPath = (LSM and LSM:Fetch("sound", "ElvUI LevelUp")) or "Sound\\Interface\\LevelUp.wav"
	pcall(PlaySoundFile, soundPath, "Master")
	pcall(installStepComplete.Show, installStepComplete)
	E:ScheduleTimer(function() pcall(installStepComplete.Hide, installStepComplete) end, 4)
end

-- Builds one backdrop button with a gold-border hover highlight and a
-- centered label -- same recipe as Core/Movers.lua's own CreatePanelButton
-- (the only other standalone-panel button in this codebase), kept as a
-- separate local copy since that one isn't exported.
local function CreateWizardButton(parent, name, label, width, onClick)
	local ok, button = pcall(CreateFrame, "Button", name, parent)
	if not ok or not button then return nil end

	pcall(button.SetWidth, button, width)
	pcall(button.SetHeight, button, 24)
	pcall(button.EnableMouse, button, true)

	-- Above the panel background surface S:CreatePanel pins to the
	-- parent's OWN frame level -- without this, a new child frame's
	-- default level ties with that background instead of sitting above it.
	local okLevel, level = pcall(parent.GetFrameLevel, parent)
	pcall(button.SetFrameLevel, button, (okLevel and tonumber(level) or 1) + 10)

	pcall(button.SetBackdrop, button, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(button.SetBackdropColor, button, 0.15, 0.15, 0.15, 1)
	pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 1)

	local okLabel, text = pcall(button.CreateFontString, button, nil, "OVERLAY", "GameFontNormal")
	if okLabel and text then
		pcall(text.SetPoint, text, "CENTER", button, "CENTER", 0, 0)
		pcall(text.SetText, text, label or "")
		pcall(text.SetTextColor, text, 1, 0.82, 0)
		button.label = text
	end

	button:SetScript("OnEnter", function()
		pcall(button.SetBackdropBorderColor, button, 1, 0.82, 0, 1)
	end)
	button:SetScript("OnLeave", function()
		pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 1)
	end)
	if onClick then
		button:SetScript("OnClick", onClick)
	end

	return button
end

-- Sized so 4 buttons (the Layout page's Tank/Healer/Phys DPS/Caster DPS)
-- fit inside the 500px-wide frame with margin -- 4*110 + 3*10 = 470.
local OPTION_BUTTON_WIDTH = 110
local OPTION_BUTTON_GAP = 10

-- Centers however many option buttons a page actually uses as one group,
-- instead of a fixed 4-slot row -- a page with 1 button (Welcome/Complete)
-- must land in the middle, not in the leftmost slot of a row sized for 4.
local function PositionOptionButtons(frame, count)
	local spacing = OPTION_BUTTON_WIDTH + OPTION_BUTTON_GAP
	local i
	for i = 1, count do
		local button = frame["OptionButton"..i]
		if button then
			local offset = (i - (count + 1) / 2) * spacing
			pcall(button.ClearAllPoints, button)
			pcall(button.SetPoint, button, "BOTTOM", frame, "BOTTOM", offset, 96)
		end
	end
end

-- Ported from real ElvUI's own SetupCVars
-- (source/ElvUI-vanilla/.../install.lua:209-223), minus two items
-- deliberately dropped: `SetActionBarToggles(1, 0, 1, 1)` and
-- `ALWAYS_SHOW_MULTIBARS = 1` both drive the exact native
-- SHOW_MULTI_ACTIONBAR_* / MultiActionBar_Update machinery that was the
-- root cause of a already-fixed bug in this project (a disabled
-- ActionBars bar's buttons re-appearing on SpellBookFrame_Update,
-- Modules/ActionBars/ActionBars.lua) -- forcing those toggles here risks
-- re-triggering the same class of native reassertion against a bar this
-- project's own config has deliberately disabled, so they're left alone
-- until that interaction has actually been tested live.
local function SetupCVars()
	SHOW_NEWBIE_TIPS = 0
	LOCK_ACTIONBAR = "1"
	SIMPLE_CHAT = 0
	pcall(SetCVar, "showLootSpam", 1)
	pcall(SetCVar, "UberTooltips", 1)
	pcall(TutorialFrame_HideAllAlerts)
	pcall(ClearTutorials)

	ShowStepComplete(L["CVars Set"])
end

-- Values ported from real ElvUI's own SetupTheme
-- (source/ElvUI-vanilla/.../install.lua:229-266) -- `border`/`backdrop`
-- happen to share the SAME backdropcolor across all three real presets,
-- so `dark` here intentionally does NOT match this project's own
-- current shipped border tone ({0,0,0,1} -- see Settings/Profile.lua);
-- clicking "Dark" is a real, visible change, not a no-op re-confirming
-- today's look.
local THEME_PRESETS = {
	classic = {
		bordercolor = { r = 0.31, g = 0.31, b = 0.31 },
		backdropcolor = { r = 0.1, g = 0.1, b = 0.1 },
		backdropfadecolor = { r = 0.06, g = 0.06, b = 0.06, a = 0.8 },
		healthclass = false,
		castClassColor = false,
	},
	dark = {
		bordercolor = { r = 0.1, g = 0.1, b = 0.1 },
		backdropcolor = { r = 0.1, g = 0.1, b = 0.1 },
		backdropfadecolor = { r = 0.054, g = 0.054, b = 0.054, a = 0.8 },
		healthclass = false,
		castClassColor = false,
	},
	class = {
		bordercolor = { r = 0.31, g = 0.31, b = 0.31 },
		backdropcolor = { r = 0.1, g = 0.1, b = 0.1 },
		backdropfadecolor = { r = 0.06, g = 0.06, b = 0.06, a = 0.8 },
		healthclass = true,
		castClassColor = true,
	},
}

local function GetClassColor()
	local classColor = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[E.myclass]
	if classColor then
		return { r = classColor.r, g = classColor.g, b = classColor.b }
	end
	return { r = 1, g = 1, b = 1 }
end

-- Only `Util.BORDER_COLOR`/`BACKDROP_COLOR` (Core/Util.lua) get mutated
-- here -- deliberately NOT `Modules/Skins/Skins.lua`'s own
-- `S.PANEL_COLOR`. All three presets above share one `backdropcolor`
-- (matching real ElvUI, which has no separate window-vs-widget shade at
-- all), but this project's `S.PANEL_COLOR` (.05) is kept a step DARKER
-- than `S.WIDGET_COLOR`/`Util.BACKDROP_COLOR` (.1) on purpose (Skins.lua's
-- own comment: a button/edit-box sitting ON a same-toned panel would
-- visually dissolve into it) -- writing the theme's backdropcolor into
-- PANEL_COLOR too would collapse that distinction on every theme click,
-- including "Dark". Window/config-panel backgrounds are left alone.
function E:SetupTheme(theme)
	local preset = THEME_PRESETS[theme]
	if not preset then return end

	E.private.theme = theme

	local general = E.db.general
	general.bordercolor = preset.bordercolor
	general.backdropcolor = preset.backdropcolor
	general.backdropfadecolor = preset.backdropfadecolor
	-- The UI ACCENT colour. Read live by every data text's value half
	-- (`E.valueColorUpdateFuncs`, Init.lua), so this is a visible change,
	-- not bookkeeping.
	--
	-- MEASURED, and the reason it looks transposed. Upstream writes
	-- `E:GetColor(.09, .819, .513)` for the non-class themes, which reads
	-- like {r=.09, g=.819, b=.513} -- but its own helper is declared
	-- `function E:GetColor(r, b, g, a) return {r = r, b = b, g = g, a = a}`
	-- (install.lua:225), i.e. the SECOND parameter is BLUE, not green. The
	-- stored value is therefore {r=.09, g=.513, b=.819} -- a blue. Same
	-- helper is why upstream's class branch reads
	-- `E:GetColor(classColor.r, classColor.b, classColor.g)`: that call
	-- site is compensating for the parameter order, and the result is the
	-- plain, untransposed class colour.
	--
	-- An earlier version here "fixed" this to {r=.09, g=.819, b=.513} on
	-- the assumption that upstream's argument order was literal and that
	-- the blue was our own transposition bug. It was the other way round.
	general.valuecolor = (theme == "class") and GetClassColor() or { r = 0.09, g = 0.513, b = 0.819 }

	-- Live -- read every health/cast update
	-- (Modules/UnitFrames/UnitFrames.lua's ResolveHealthColor/castbar
	-- code), takes effect immediately, no reload needed.
	E.db.unitframe.colors.healthclass = preset.healthclass
	E.db.unitframe.colors.castClassColor = preset.castClassColor

	-- In-place index assignment, never `Util.BORDER_COLOR = {...}` --
	-- Modules/Skins/Skins.lua:208-209 aliases these exact table OBJECTS
	-- at load time (`S.WIDGET_COLOR`/`S.BORDER_COLOR`); a reassignment
	-- here would silently break that alias. Only reaches frames built
	-- AFTER this runs -- Util.CreateButtonBorder/S:CreateSurface read
	-- color once, at construction, so already-built frames need a
	-- `/reload` to pick up the change, same as everywhere else in this
	-- project that mutates `E.db` live.
	local bc, brc = general.backdropcolor, general.bordercolor
	ElvUI.Util.BACKDROP_COLOR[1] = bc.r
	ElvUI.Util.BACKDROP_COLOR[2] = bc.g
	ElvUI.Util.BACKDROP_COLOR[3] = bc.b
	ElvUI.Util.BORDER_COLOR[1] = brc.r
	ElvUI.Util.BORDER_COLOR[2] = brc.g
	ElvUI.Util.BORDER_COLOR[3] = brc.b

	ShowStepComplete(L["Theme Set"])
end

-- Toggles an option button between usable and disabled-with-explanation,
-- for a page (Resolution) where the action genuinely doesn't apply on
-- one client -- a plain :Disable() alone leaves the label gold, which
-- reads as clickable, so the label is dimmed too.
local function SetButtonUsable(button, usable)
	if not button then return end
	if usable then
		pcall(button.Enable, button)
		if button.label then pcall(button.label.SetTextColor, button.label, 1, 0.82, 0) end
	else
		pcall(button.Disable, button)
		if button.label then pcall(button.label.SetTextColor, button.label, 0.5, 0.5, 0.5) end
	end
end

-- Real ElvUI's own SetupResolution (source/ElvUI-vanilla/.../
-- install.lua:280-370) is a GetScreenWidth()-driven rescale touching
-- E.PixelMode/E:ResetMovers/E:CopyTable and raid/raid40/focus fields,
-- none of which exist in this project. Rewritten small, touching only
-- fields that exist here: chat panel size, bag width, bar1 button size,
-- player/target/pet/targettarget position (player/target ALSO resize --
-- pet/targettarget default to a already-compact 130 width in this
-- project, real ElvUI's own low-res number (200) would make them BIGGER
-- here, so only their position changes, not their size) -- reverted to
-- this project's own P defaults by "High Resolution", not recomputed from
-- E.PixelMode (which doesn't exist). Mover names have NO "Mover" suffix
-- in this project (`ElvUF_Player`, not real ElvUI's `ElvUF_PlayerMover`)
-- and are relative to `UIParent` (this project has no `ElvUIParent`) --
-- see Core/Movers.lua's own ApplyPositionString comment.
--
-- Live-refresh calls below are the SAME ones ElvUI_Config's own sliders
-- for these exact fields already use (Bags.lua/ActionBars.lua/Chat.lua),
-- plus two additions made FOR this feature (`UF:ResizeUnit`,
-- Modules/UnitFrames/UnitFrames.lua; `E:ApplyMoverPosition`,
-- Core/Movers.lua) once checking found no actual blocker for either --
-- UpdateFrame already recomputes Health/Power width from
-- `frame:GetWidth()` on every poll tick, the outer SetWidth call was
-- just never wired up anywhere. Both new functions are general-purpose
-- (not wizard-only) and ElvUI_Config's own unit frame width slider was
-- updated to use the same one, so this field now behaves identically no
-- matter where it's changed from.
local function ApplyResolutionLiveRefresh()
	if E.Chat and E.Chat.UpdatePanelSizes then E.Chat:UpdatePanelSizes() end
	if E.Bags and E.Bags.Layout then
		E.Bags:Layout()
		E.Bags:Layout(true)
	end
	if E.ActionBars and E.ActionBars.UpdateBar then E.ActionBars:UpdateBar(1) end
	if E.UnitFrames and E.UnitFrames.ResizeUnit then
		E.UnitFrames:ResizeUnit("player", E.db.unitframe.units.player.width)
		E.UnitFrames:ResizeUnit("target", E.db.unitframe.units.target.width)
	end
	E:ApplyMoverPosition("ElvUF_Player")
	E:ApplyMoverPosition("ElvUF_Target")
	E:ApplyMoverPosition("ElvUF_Pet")
	E:ApplyMoverPosition("ElvUF_TargetTarget")
end

local function SetupResolutionLow()
	E.db.chat.panelWidth = 340
	E.db.chat.panelHeight = 140
	E.db.chat.panelWidthRight = 340
	E.db.chat.panelHeightRight = 140

	E.db.bags.bagWidth = 340
	E.db.bags.bankWidth = 340

	E.db.actionbar.bar1.buttonsize = 24

	E.db.unitframe.units.player.width = 200
	E.db.unitframe.units.target.width = 200

	-- Pet/TargetTarget tucked in just below Player/Target, mirroring real
	-- ElvUI's own low-res relative layout (its Pet/TargetTarget movers sit
	-- 62px below its Player/Target movers) scaled to this project's own
	-- chosen offsets above -- a first-pass position, adjust live if it
	-- doesn't look right.
	E.db.movers.ElvUF_Player = "BOTTOM,UIParent,BOTTOM,-102,142"
	E.db.movers.ElvUF_Target = "BOTTOM,UIParent,BOTTOM,102,142"
	E.db.movers.ElvUF_Pet = "BOTTOM,UIParent,BOTTOM,-102,100"
	E.db.movers.ElvUF_TargetTarget = "BOTTOM,UIParent,BOTTOM,102,100"

	E.db.lowresolutionset = true
	ApplyResolutionLiveRefresh()
	ShowStepComplete(L["Resolution Style Set"])
end

local function SetupResolutionHigh()
	E.db.chat.panelWidth = 412
	E.db.chat.panelHeight = 180
	E.db.chat.panelWidthRight = 412
	E.db.chat.panelHeightRight = 180

	E.db.bags.bagWidth = 406
	E.db.bags.bankWidth = 406

	E.db.actionbar.bar1.buttonsize = 32

	E.db.unitframe.units.player.width = 270
	E.db.unitframe.units.target.width = 270

	E.db.movers.ElvUF_Player = nil
	E.db.movers.ElvUF_Target = nil
	E.db.movers.ElvUF_Pet = nil
	E.db.movers.ElvUF_TargetTarget = nil

	E.db.lowresolutionset = false
	ApplyResolutionLiveRefresh()
	ShowStepComplete(L["Resolution Style Set"])
end

-- Real ElvUI's own SetupLayout (source/ElvUI-vanilla/.../
-- install.lua:372-630) is ~260 lines of per-resolution/per-pixel-mode
-- mover strings plus raid/raid40/party/focus/GPSArrow/healPrediction/
-- Clique references, none of which exist in this project (this
-- project's own party frames are per-index-numbered, `ElvUF_Party1..N`,
-- and are NOT repositioned by this feature -- no single group anchor to
-- move). Rewritten small: only the 4 single-instance unitframe movers
-- that exist here (player/target/pet/targettarget), the player castbar
-- for healer/caster (real ElvUI widens and moves it for exactly those
-- two roles), one `E.db.actionbar.bar2.enabled` flip for healer (real
-- ElvUI's own click-heal extra bar), and a datatext-panel swap limited
-- to what this project actually has (`Attack Power`/`Armor`/
-- `Avoidance` exist; `Haste`/`Spell/Heal Power` do not, so healer/
-- caster don't get one). Numbers below are real ElvUI's own non-pixel-
-- mode, non-low-res values (`E.PixelMode` doesn't exist here, so
-- there's only one branch to port, not four).
--
-- `bar2.enabled` and the castbar's own width/height stay reload-bound
-- (matches `ElvUI_Config`'s own current state for both fields -- see
-- the "Requires /reload" backlog, docs/roadmap.md) -- only the mover
-- repositions below are live via `E:ApplyMoverPosition`.
local LAYOUT_PRESETS = {
	tank = {
		player = "BOTTOM,UIParent,BOTTOM,-307,76",
		target = "BOTTOM,UIParent,BOTTOM,307,76",
		targettarget = "BOTTOM,UIParent,BOTTOM,0,76",
		pet = "BOTTOM,UIParent,BOTTOM,0,115",
		datatextRight = "Avoidance",
	},
	healer = {
		player = "BOTTOM,UIParent,BOTTOM,-307,145",
		target = "BOTTOM,UIParent,BOTTOM,307,145",
		targettarget = "BOTTOM,UIParent,BOTTOM,0,145",
		pet = "BOTTOM,UIParent,BOTTOM,0,186",
		castbar = { width = 436, height = 28, mover = "BOTTOM,UIParent,BOTTOM,-2,81" },
		datatextRight = "Avoidance",
	},
	dpsMelee = {
		player = "BOTTOM,UIParent,BOTTOM,-307,76",
		target = "BOTTOM,UIParent,BOTTOM,307,76",
		targettarget = "BOTTOM,UIParent,BOTTOM,0,76",
		pet = "BOTTOM,UIParent,BOTTOM,0,115",
		datatextRight = "Attack Power",
	},
	dpsCaster = {
		player = "BOTTOM,UIParent,BOTTOM,-307,110",
		target = "BOTTOM,UIParent,BOTTOM,307,110",
		targettarget = "BOTTOM,UIParent,BOTTOM,0,110",
		pet = "BOTTOM,UIParent,BOTTOM,0,150",
		castbar = { width = 436, height = 28, mover = "BOTTOM,UIParent,BOTTOM,-2,47" },
		datatextRight = "Avoidance",
	},
}

function E:SetupLayout(role)
	local preset = LAYOUT_PRESETS[role]
	if not preset then return end

	E.db.layoutSet = role

	-- Reset first, then override for healer -- matches real ElvUI's own
	-- SetupLayout exactly (install.lua:378-393/453-462): a healer gets a
	-- 4th extra bar's worth of click-heal room by growing bar3/bar5 to 12
	-- buttons each and turning bar4 off entirely; every other role resets
	-- back to this project's own defaults (6/6/enabled), so switching
	-- roles never leaves a previous healer pick behind. `bar1.heightMult`
	-- (real ElvUI's own healer tweak) doesn't exist in this project --
	-- dropped. `bar2`/`bar4` `enabled` flips need `/reload` (matches
	-- `ElvUI_Config`'s own current state for per-bar `enabled`); the
	-- bar3/bar5 BUTTON COUNT change is live via `UpdateBar`.
	E.db.actionbar.bar2.enabled = false
	E.db.actionbar.bar3.buttons = P.actionbar.bar3.buttons
	E.db.actionbar.bar5.buttons = P.actionbar.bar5.buttons
	E.db.actionbar.bar4.enabled = true

	if role == "healer" then
		E.db.actionbar.bar2.enabled = true
		E.db.actionbar.bar3.buttons = 12
		E.db.actionbar.bar5.buttons = 12
		E.db.actionbar.bar4.enabled = false
	end

	if E.ActionBars and E.ActionBars.UpdateBar then
		E.ActionBars:UpdateBar(3)
		E.ActionBars:UpdateBar(5)
	end

	E.db.movers.ElvUF_Player = preset.player
	E.db.movers.ElvUF_Target = preset.target
	E.db.movers.ElvUF_TargetTarget = preset.targettarget
	E.db.movers.ElvUF_Pet = preset.pet
	E:ApplyMoverPosition("ElvUF_Player")
	E:ApplyMoverPosition("ElvUF_Target")
	E:ApplyMoverPosition("ElvUF_TargetTarget")
	E:ApplyMoverPosition("ElvUF_Pet")

	local castbarSettings = E.db.unitframe.units.player.castbar
	if preset.castbar then
		castbarSettings.width = preset.castbar.width
		castbarSettings.height = preset.castbar.height
		E.db.movers.ElvUF_PlayerCastbar = preset.castbar.mover
	else
		-- Reset to this project's own default -- otherwise switching
		-- FROM healer/caster TO tank/phys-dps would leave the widened
		-- castbar behind.
		castbarSettings.width = P.unitframe.units.player.castbar.width
		castbarSettings.height = P.unitframe.units.player.castbar.height
		E.db.movers.ElvUF_PlayerCastbar = nil
	end
	E:ApplyMoverPosition("ElvUF_PlayerCastbar")
	if E.UnitFrames and E.UnitFrames.ResizeCastbar then
		E.UnitFrames:ResizeCastbar(castbarSettings.width, castbarSettings.height)
	end

	-- Reset first, then override -- every role writes both fields
	-- (even when the result matches the default), so switching roles
	-- never leaves a stale value from a PREVIOUS role's pick.
	local panel = E.db.datatexts.panels.LeftChatDataPanel
	panel.left = "Armor"
	panel.middle = "Durability"
	panel.right = preset.datatextRight

	ShowStepComplete(L["Layout Set"])
end

-- Ported from real ElvUI's own SetupChat
-- (source/ElvUI-vanilla/.../install.lua:104-207) -- the message-group/
-- channel setup on `ChatFrame1`/`ChatFrame2` only, native calls that
-- don't depend on anything about how THIS project's own Chat module
-- docks/positions windows. Deliberately dropped: opening a THIRD chat
-- window (real ElvUI's own Loot/Trade window) and renaming/reparenting
-- ChatFrame1-3 onto `LeftChatToggleButton`/`RightChatDataPanel` --
-- `Modules/Chat/Chat.lua` already docks `ChatFrame1` into `LeftChatPanel`
-- unconditionally at its own Initialize (not gated behind this wizard
-- step at all), and has no logic to dock a SECOND window the way real
-- ElvUI's version assumes (see that file's own header comment). Also
-- dropped: `ChangeChatColor("CHANNEL2"/"CHANNEL3", ...)` (Trade/Local
-- Defense) -- channel INDEX depends on the player's actual joined-
-- channel order, not a fixed slot, so only `CHANNEL1` (General, reliably
-- index 1) is safe to recolor blind.
--
-- Nothing here is a one-way lock: every message group/channel choice is
-- the same thing a player can always change by right-clicking a chat
-- tab -- no special "revert" trick exists or is needed, same native menu
-- undoes it.
-- Individually pcall'd (not one shared pcall around the whole batch) --
-- one missing/renamed group constant on either client must not abort
-- every call after it.
local function SetupChat()
	pcall(ChatFrame_RemoveAllMessageGroups, ChatFrame1)

	local groups = {
		"SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "WHISPER",
		"MONSTER_SAY", "MONSTER_EMOTE", "MONSTER_YELL", "MONSTER_BOSS_EMOTE",
		"PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
		"BATTLEGROUND", "BATTLEGROUND_LEADER", "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL",
		"SYSTEM", "ERRORS", "AFK", "DND", "IGNORED", "CHANNEL",
	}
	local i
	for i = 1, table.getn(groups) do
		pcall(ChatFrame_AddMessageGroup, ChatFrame1, groups[i])
	end

	pcall(ChatFrame_AddChannel, ChatFrame1, GENERAL)
	pcall(ChatFrame_RemoveMessageGroup, ChatFrame1, "SKILL")
	pcall(ChatFrame_RemoveMessageGroup, ChatFrame1, "LOOT")
	pcall(ChatFrame_RemoveMessageGroup, ChatFrame1, "MONEY")
	pcall(ChatFrame_RemoveMessageGroup, ChatFrame1, "COMBAT_FACTION_CHANGE")
	pcall(ChatFrame_RemoveChannel, ChatFrame1, TRADE)

	pcall(ChatFrame_ActivateCombatMessages, ChatFrame2)

	pcall(ChangeChatColor, "CHANNEL1", 195 / 255, 230 / 255, 232 / 255)

	ShowStepComplete(L["Chat Set"])
end

-- Ported from real ElvUI's own SetupAuras
-- (source/ElvUI-vanilla/.../install.lua:632-682) -- unit-frame-attached
-- buff/debuff ICONS only (`Modules/UnitFrames/UnitFrames.lua`'s own
-- `Construct_Auras`/`UpdateAuras`), NOT the separate standalone Auras
-- module (a native BuffFrame replacement near the minimap,
-- `docs/modules/auras.md`) -- real ElvUI's own page offers "Icons Only"
-- vs "Aura Bar & Icons"; this project has no aura-BAR style at all, so
-- only the icons choice exists, matching a single-button page like
-- Welcome/Complete/CVars. Real ElvUI also sets `buffs.attachTo`/
-- `debuffs.attachTo` -- this project's own schema has no `attachTo`
-- field (fixed attachment, not configurable), so those two lines are
-- dropped, not silently kept as dead writes.
--
-- Already fully live with no extra call needed: `Construct_Auras`
-- (UnitFrames.lua) builds `frame.Buffs`/`Debuffs` UNCONDITIONALLY at
-- construction regardless of `enable`, and `UF:UpdateAuras` reads
-- `auraSettings.enable` fresh on every periodic poll tick -- flipping
-- the DB field alone is enough.
local function SetupAuras()
	E.db.unitframe.units.player.buffs.enable = true
	E.db.unitframe.units.target.debuffs.enable = true
	ShowStepComplete(L["Auras Set"])
end

-- Forward-declared so CreateInstallFrame's button closures (built before
-- these bodies are assigned) can still capture them as upvalues.
local SetPage, NextPage, PrevPage

local function ResetPage(frame)
	local i
	for i = 1, 4 do
		local button = frame["OptionButton"..i]
		if button then
			pcall(button.Hide, button)
			-- Re-enabled unconditionally on every page switch -- Resolution
			-- is the only page that disables an option button (UA has no
			-- use for it), and reused buttons must not carry that disabled
			-- state onto whatever OTHER page shows them next.
			SetButtonUsable(button, true)
			button:SetScript("OnClick", nil)
			if button.label then pcall(button.label.SetText, button.label, "") end
		end
	end

	pcall(frame.SubTitle.SetText, frame.SubTitle, "")
	pcall(frame.Desc1.SetText, frame.Desc1, "")
	pcall(frame.Desc2.SetText, frame.Desc2, "")
	pcall(frame.Desc3.SetText, frame.Desc3, "")
end

SetPage = function(frame, pageNum)
	frame.currentPage = pageNum
	ResetPage(frame)

	pcall(frame.ProgressBar.SetMinMaxValues, frame.ProgressBar, 1, MAX_PAGE)
	pcall(frame.ProgressBar.SetValue, frame.ProgressBar, pageNum)
	pcall(frame.ProgressText.SetText, frame.ProgressText, string.format("%d / %d", pageNum, MAX_PAGE))

	-- SetButtonUsable also dims the label -- a plain :Disable() alone
	-- blocks the click but leaves the gold text looking just as
	-- clickable as always (this is what read as "there's still a Next
	-- button" on the last page -- it WAS inert, just not visibly so).
	SetButtonUsable(frame.PrevButton, pageNum > 1)
	SetButtonUsable(frame.NextButton, pageNum < MAX_PAGE)

	if pageNum == 1 then
		pcall(frame.SubTitle.SetText, frame.SubTitle, L["Welcome to ElvUI"])
		pcall(frame.Desc1.SetText, frame.Desc1,
			L["This wizard will help you set up your interface."])
		pcall(frame.Desc2.SetText, frame.Desc2,
			L["The configuration menu is always available via /elvui or /ec. This wizard can be reopened later with /eiw."])
		pcall(frame.Desc3.SetText, frame.Desc3,
			L["Press Next to continue, or Skip to close without changing anything."])

		PositionOptionButtons(frame, 1)
		pcall(frame.OptionButton1.label.SetText, frame.OptionButton1.label, L["Skip"])
		frame.OptionButton1:SetScript("OnClick", function() pcall(frame.Hide, frame) end)
		pcall(frame.OptionButton1.Show, frame.OptionButton1)
	elseif pageNum == 2 then
		pcall(frame.SubTitle.SetText, frame.SubTitle, L["CVars"])
		pcall(frame.Desc1.SetText, frame.Desc1,
			L["This step sets up a few of your World of Warcraft options so the interface behaves as expected."])
		pcall(frame.Desc2.SetText, frame.Desc2,
			L["Click the button below to apply them."])
		pcall(frame.Desc3.SetText, frame.Desc3, L["Importance: High"])

		PositionOptionButtons(frame, 1)
		pcall(frame.OptionButton1.label.SetText, frame.OptionButton1.label, L["Setup CVars"])
		frame.OptionButton1:SetScript("OnClick", SetupCVars)
		pcall(frame.OptionButton1.Show, frame.OptionButton1)
	elseif pageNum == 3 then
		pcall(frame.SubTitle.SetText, frame.SubTitle, L["Chat"])
		pcall(frame.Desc1.SetText, frame.Desc1,
			L["This step sets up which message types show in your main chat window (say/yell/emotes/whispers/etc.) and your combat log window."])
		pcall(frame.Desc2.SetText, frame.Desc2,
			L["You can always change this later by right-clicking a chat tab -- nothing here is one-way."])
		pcall(frame.Desc3.SetText, frame.Desc3, L["Importance: Medium"])

		PositionOptionButtons(frame, 1)
		pcall(frame.OptionButton1.label.SetText, frame.OptionButton1.label, L["Setup Chat"])
		frame.OptionButton1:SetScript("OnClick", SetupChat)
		pcall(frame.OptionButton1.Show, frame.OptionButton1)
	elseif pageNum == 4 then
		pcall(frame.SubTitle.SetText, frame.SubTitle, L["Theme Setup"])
		pcall(frame.Desc1.SetText, frame.Desc1,
			L["Choose a color theme for your interface."])
		pcall(frame.Desc2.SetText, frame.Desc2,
			L["Border/backdrop colors apply to newly built frames immediately; a /reload shows the full effect everywhere else. Class also colors health/cast bars by class."])
		pcall(frame.Desc3.SetText, frame.Desc3, L["Importance: Low"])

		PositionOptionButtons(frame, 3)
		pcall(frame.OptionButton1.label.SetText, frame.OptionButton1.label, L["Classic"])
		frame.OptionButton1:SetScript("OnClick", function() E:SetupTheme("classic") end)
		pcall(frame.OptionButton1.Show, frame.OptionButton1)
		pcall(frame.OptionButton2.label.SetText, frame.OptionButton2.label, L["Dark"])
		frame.OptionButton2:SetScript("OnClick", function() E:SetupTheme("dark") end)
		pcall(frame.OptionButton2.Show, frame.OptionButton2)
		pcall(frame.OptionButton3.label.SetText, frame.OptionButton3.label, L["Class"])
		frame.OptionButton3:SetScript("OnClick", function() E:SetupTheme("class") end)
		pcall(frame.OptionButton3.Show, frame.OptionButton3)
	elseif pageNum == 5 then
		pcall(frame.SubTitle.SetText, frame.SubTitle, L["Resolution"])
		PositionOptionButtons(frame, 2)
		pcall(frame.OptionButton1.label.SetText, frame.OptionButton1.label, L["High Resolution"])
		pcall(frame.OptionButton1.Show, frame.OptionButton1)
		pcall(frame.OptionButton2.label.SetText, frame.OptionButton2.label, L["Low Resolution"])
		pcall(frame.OptionButton2.Show, frame.OptionButton2)

		-- Runs on BOTH clients -- unlike real ElvUI's own
		-- GetScreenWidth()-driven version, SetupResolutionLow/High only
		-- write this project's own E.db fields (chat panel size, bag
		-- width, bar1 button size, player/target width, their movers),
		-- never a native UI-scale/resolution API. Nothing about THAT
		-- specific mechanism is UA-broken -- native UI Scale itself is a
		-- separate thing this step never touched even on the legacy
		-- client, and isn't implemented here either.
		pcall(frame.Desc1.SetText, frame.Desc1,
			L["This step resizes chat windows, unit frames, and action bar buttons for your resolution."])
		pcall(frame.Desc2.SetText, frame.Desc2,
			L["Choose High Resolution if your screen is wide enough, or Low Resolution if things feel cramped."])
		pcall(frame.Desc3.SetText, frame.Desc3,
			L["All changes apply immediately -- no /reload needed."])
		SetButtonUsable(frame.OptionButton1, true)
		SetButtonUsable(frame.OptionButton2, true)
		frame.OptionButton1:SetScript("OnClick", SetupResolutionHigh)
		frame.OptionButton2:SetScript("OnClick", SetupResolutionLow)
	elseif pageNum == 6 then
		pcall(frame.SubTitle.SetText, frame.SubTitle, L["Layout"])
		pcall(frame.Desc1.SetText, frame.Desc1,
			L["Choose a layout based on your combat role."])
		pcall(frame.Desc2.SetText, frame.Desc2,
			L["This repositions your unit frames and (Healer only) reshapes your action bars for more click-heal room. Unit frames, bar button counts, and castbar size apply immediately; enabling/disabling a bar needs /reload."])
		pcall(frame.Desc3.SetText, frame.Desc3, L["Importance: Medium"])

		PositionOptionButtons(frame, 4)
		pcall(frame.OptionButton1.label.SetText, frame.OptionButton1.label, L["Tank"])
		frame.OptionButton1:SetScript("OnClick", function() E:SetupLayout("tank") end)
		pcall(frame.OptionButton1.Show, frame.OptionButton1)
		pcall(frame.OptionButton2.label.SetText, frame.OptionButton2.label, L["Healer"])
		frame.OptionButton2:SetScript("OnClick", function() E:SetupLayout("healer") end)
		pcall(frame.OptionButton2.Show, frame.OptionButton2)
		pcall(frame.OptionButton3.label.SetText, frame.OptionButton3.label, L["Physical DPS"])
		frame.OptionButton3:SetScript("OnClick", function() E:SetupLayout("dpsMelee") end)
		pcall(frame.OptionButton3.Show, frame.OptionButton3)
		pcall(frame.OptionButton4.label.SetText, frame.OptionButton4.label, L["Caster DPS"])
		frame.OptionButton4:SetScript("OnClick", function() E:SetupLayout("dpsCaster") end)
		pcall(frame.OptionButton4.Show, frame.OptionButton4)
	elseif pageNum == 7 then
		pcall(frame.SubTitle.SetText, frame.SubTitle, L["Auras"])
		pcall(frame.Desc1.SetText, frame.Desc1,
			L["Select the aura style for your unit frames."])
		pcall(frame.Desc2.SetText, frame.Desc2,
			L["This project only has icon-style auras -- there is no aura bar style to choose between."])
		pcall(frame.Desc3.SetText, frame.Desc3, L["Importance: Medium"])

		PositionOptionButtons(frame, 1)
		pcall(frame.OptionButton1.label.SetText, frame.OptionButton1.label, L["Icons Only"])
		frame.OptionButton1:SetScript("OnClick", SetupAuras)
		pcall(frame.OptionButton1.Show, frame.OptionButton1)
	elseif pageNum == MAX_PAGE then
		pcall(frame.SubTitle.SetText, frame.SubTitle, L["Setup Complete"])
		pcall(frame.Desc1.SetText, frame.Desc1,
			L["You are finished with the setup wizard."])
		pcall(frame.Desc2.SetText, frame.Desc2,
			L["Click Finished to save and reload your interface."])

		PositionOptionButtons(frame, 1)
		pcall(frame.OptionButton1.label.SetText, frame.OptionButton1.label, L["Finished"])
		frame.OptionButton1:SetScript("OnClick", function()
			E.private.installComplete = true
			ReloadUI()
		end)
		pcall(frame.OptionButton1.Show, frame.OptionButton1)
	end
end

NextPage = function(frame)
	if frame.currentPage < MAX_PAGE then
		SetPage(frame, frame.currentPage + 1)
	end
end

PrevPage = function(frame)
	if frame.currentPage > 1 then
		SetPage(frame, frame.currentPage - 1)
	end
end

local function CreateInstallFrame()
	local ok, frame = pcall(CreateFrame, "Frame", "ElvUIInstallFrame", UIParent)
	if not ok or not frame then return nil end

	pcall(frame.SetWidth, frame, 500)
	pcall(frame.SetHeight, frame, 350)
	pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 0)
	pcall(frame.SetFrameStrata, frame, "FULLSCREEN_DIALOG")
	pcall(frame.SetFrameLevel, frame, 200)
	pcall(frame.EnableMouse, frame, true)
	pcall(frame.SetClampedToScreen, frame, true)

	-- Resolved at build time (first E:Install() call, well after login),
	-- not at file-load time, so load order against Modules/Skins/Skins.lua
	-- doesn't matter.
	local S = E.Skins
	if S and S.CreatePanel then
		pcall(S.CreatePanel, S, frame)
	end

	local okClose, closeButton = pcall(CreateFrame, "Button", nil, frame)
	if okClose and closeButton then
		pcall(closeButton.SetWidth, closeButton, 20)
		pcall(closeButton.SetHeight, closeButton, 20)
		pcall(closeButton.SetFrameLevel, closeButton, 210)
		pcall(closeButton.SetPoint, closeButton, "TOPRIGHT", frame, "TOPRIGHT", -6, -6)
		-- Hide only -- never writes installComplete, so closing early
		-- keeps the auto-open-on-next-login behavior intact.
		closeButton:SetScript("OnClick", function() pcall(frame.Hide, frame) end)
		if S and S.StyleCloseButton then
			pcall(S.StyleCloseButton, S, closeButton)
		end
	end

	local okTitle, title = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontNormalLarge")
	if okTitle and title then
		-- Font arguments of real ElvUI's install frame: SubTitle 15, the
		-- descriptions and the status text at the defaults.
		E:FontTemplate(title, nil, 15)
		pcall(title.SetPoint, title, "TOP", frame, "TOP", 0, -16)
		pcall(title.SetTextColor, title, 1, 0.82, 0)
	end
	frame.SubTitle = title

	local i
	for i = 1, 3 do
		local okDesc, desc = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontHighlightSmall")
		if okDesc and desc then
			E:FontTemplate(desc)
			pcall(desc.SetPoint, desc, "TOP", frame, "TOP", 0, -50 - (i - 1) * 34)
			pcall(desc.SetWidth, desc, 440)
			pcall(desc.SetJustifyH, desc, "CENTER")
		end
		frame["Desc"..i] = desc
	end

	-- Up to 4 option buttons, reused across pages (SetPage shows/hides +
	-- relabels them, PositionOptionButtons re-centers however many a page
	-- actually uses) rather than rebuilt per page. No initial SetPoint --
	-- PositionOptionButtons always runs before the frame is ever shown.
	for i = 1, 4 do
		local button = CreateWizardButton(frame, nil, "", OPTION_BUTTON_WIDTH, nil)
		if button then
			pcall(button.Hide, button)
		end
		frame["OptionButton"..i] = button
	end

	local progressBar = ElvUI.Util.CreateStatusBar(frame, {
		width = 460, height = 12, color = { 1, 0.82, 0, 1 },
	})
	if progressBar then
		pcall(progressBar.SetFrameLevel, progressBar, 210)
		pcall(progressBar.SetPoint, progressBar, "BOTTOM", frame, "BOTTOM", 0, 64)
	end
	frame.ProgressBar = progressBar

	local okProgressText, progressText = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontNormalSmall")
	if okProgressText and progressText then
		E:FontTemplate(progressText)
		pcall(progressText.SetPoint, progressText, "BOTTOM", frame, "BOTTOM", 0, 80)
	end
	frame.ProgressText = progressText

	frame.PrevButton = CreateWizardButton(frame, nil, L["Previous"], 100, function() PrevPage(frame) end)
	if frame.PrevButton then
		pcall(frame.PrevButton.SetPoint, frame.PrevButton, "BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
	end

	frame.NextButton = CreateWizardButton(frame, nil, L["Next"], 100, function() NextPage(frame) end)
	if frame.NextButton then
		pcall(frame.NextButton.SetPoint, frame.NextButton, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
	end

	pcall(frame.Hide, frame)
	return frame
end

function E:Install()
	if not self.installFrame then
		self.installFrame = CreateInstallFrame()
	end
	if not self.installFrame then return end

	SetPage(self.installFrame, 1)
	pcall(self.installFrame.Show, self.installFrame)
end

function E:ToggleInstallWizard()
	if self.installFrame then
		local okShown, shown = pcall(self.installFrame.IsShown, self.installFrame)
		if okShown and shown then
			pcall(self.installFrame.Hide, self.installFrame)
			return
		end
	end
	self:Install()
end

E:RegisterInitialModule("InstallWizard", function()
	if not E.private.installComplete then
		E:Install()
	end
end)
