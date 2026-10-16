local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()

-- The client's shared Font objects restyled to the UI font: real ElvUI's
-- `E:UpdateBlizzardFonts` (Core/fonts.lua), same object list, sizes and
-- outlines. A FontString that inherits a Font object takes its font from it, so
-- this restyles every stock frame without touching a single FontString.
--
-- Every SetFont is pcall-wrapped so one failing object cannot stop the rest of
-- the list, and an object the running client does not define is skipped. Font
-- objects are only ever given a font, never a colour: on Unreal Azeroth a Font
-- object has no SetTextColor at all.
--
-- Real ElvUI's eyefinity branch (hiding the combat text options, Invisible.ttf
-- as combat text font) is not ported; nothing here detects eyefinity.

local LSM = LibStub("LibSharedMedia-3.0", true)

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

local function FetchFont(name)
	return (LSM and name and LSM:Fetch("font", name)) or FALLBACK_FONT
end

-- The client's Font objects that inherit one of the objects restyled below
-- (FrameXML Fonts.xml) and declare no font, height or outline of their own,
-- by parent. On the 1.12.1 client such a child follows its parent's SetFont;
-- on Unreal Azeroth it keeps the client font (measured: GameFontHighlightSmall,
-- the font of LibConfig's and most addons' edit boxes, stayed the client font
-- after GameFontNormalSmall was restyled; after a SetFont on
-- GameFontHighlightSmall itself, the edit boxes built from then on showed the
-- UI font). So on UA each child is given its parent's arguments too. TextStatusBarText (a NumberFontNormal child) is left out: it
-- is restyled explicitly, after its parent. NumberFontNormalSmallGray is left
-- out as it declares an outline of its own.
local INHERITED_FONTS = {
	GameFontNormal = { "GameFontHighlight", "GameFontDisable", "GameFontGreen", "GameFontRed", "CombatLogFont" },
	GameFontNormalSmall = { "GameFontHighlightSmall", "GameFontDisableSmall", "GameFontDarkGraySmall",
		"GameFontGreenSmall", "GameFontRedSmall", "GameFontHighlightSmallOutline" },
	GameFontNormalLarge = { "GameFontHighlightLarge", "GameFontDisableLarge", "GameFontGreenLarge",
		"GameFontRedLarge", "ErrorFont" },
	GameFontBlack = { "GameFontWhite", "QuestFontNormalSmall" },
	NumberFontNormal = { "NumberFontNormalYellow" },
	DialogButtonNormalText = { "DialogButtonHighlightText" },
}

local function SetFont(obj, font, size, style)
	if not obj or not obj.SetFont then return end
	pcall(obj.SetFont, obj, font, size, style)
	if not (ElvUI.Compat and ElvUI.Compat.isUA) then return end
	local parent, children
	for parent, children in pairs(INHERITED_FONTS) do
		if _G[parent] == obj then
			local i
			for i = 1, table.getn(children) do
				local child = _G[children[i]]
				if child and child.SetFont then
					pcall(child.SetFont, child, font, size, style)
				end
			end
			return
		end
	end
end

-- Real ElvUI's `E:FontTemplate` (Core/toolkit.lua): gives one of the addon's
-- own FontStrings the UI font and remembers the arguments, so
-- `E:UpdateFontTemplates` can re-apply them when the General -> Media font
-- settings change. A nil `font`/`fontSize` means "the Media setting" and
-- follows a later change; an explicit value stays fixed. Homespun is a pixel
-- font: an OUTLINE string at the default size is drawn MONOCHROMEOUTLINE at 10,
-- as real ElvUI does.
--
-- Outlined strings get a faint shadow, plain ones a solid one, both offset
-- 1px down-right (real ElvUI scales that offset by its pixel-perfect factor,
-- which this project does not have). The remembered arguments are stored
-- under `elv*` field names so they cannot collide with a FontString's own
-- fields.
E.texts = E.texts or {}

function E:FontTemplate(fs, font, fontSize, fontStyle)
	if not fs or not fs.SetFont then return end
	fs.elvFont, fs.elvFontSize, fs.elvFontStyle = font, fontSize, fontStyle
	self.texts[fs] = true

	local general = self.db and self.db.general
	local path = font or (self.media and self.media.normFont) or FetchFont(general and general.font)
	local size = fontSize or (general and general.fontSize) or 12

	if fontStyle == "OUTLINE" and not fontSize and general and general.font == "Homespun" and size > 10 then
		fontStyle = "MONOCHROMEOUTLINE"
		size = 10
	end

	local flags = fontStyle
	if not flags or flags == "NONE" then flags = "" end
	pcall(fs.SetFont, fs, path, size, flags)

	if flags ~= "" then
		pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.2)
	else
		pcall(fs.SetShadowColor, fs, 0, 0, 0, 1)
	end
	pcall(fs.SetShadowOffset, fs, 1, -1)
end

function E:UpdateFontTemplates()
	for fs in pairs(self.texts) do
		self:FontTemplate(fs, fs.elvFont, fs.elvFontSize, fs.elvFontStyle)
	end
end

-- Also resolves `E.media.normFont`/`E.media.combatFont`, which real ElvUI does
-- in `E:UpdateMedia` right before calling this, so a live font change from the
-- options window keeps them current.
--
-- The four *_FONT globals are read by the client itself (names above heads,
-- nameplates, floating combat text); per real ElvUI's own option text, a
-- `dmgfont`/`namefont` change needs a game restart or relog. `replaceBlizzFonts`
-- is reload-bound: switching it off only stops this pass from running.
function E:UpdateBlizzardFonts()
	local general = self.db and self.db.general
	local private = self.private and self.private.general
	if not general or not private then return end

	local NORMAL = FetchFont(general.font)
	local COMBAT = FetchFont(private.dmgfont)
	local NUMBER = NORMAL
	local NAMEFONT = FetchFont(private.namefont)
	local size = general.fontSize
	local MONOCHROME = ""

	self.media = self.media or {}
	self.media.normFont = NORMAL
	self.media.combatFont = COMBAT
	self.nativeFontGen = (self.nativeFontGen or 0) + 1

	UIDROPDOWNMENU_DEFAULT_TEXT_HEIGHT = 12
	CHAT_FONT_HEIGHTS = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }

	UNIT_NAME_FONT = NAMEFONT
	NAMEPLATE_FONT = NAMEFONT
	DAMAGE_TEXT_FONT = COMBAT
	STANDARD_TEXT_FONT = NORMAL

	-- Homespun is a pixel font and only renders cleanly unantialiased.
	if general.font == "Homespun" then
		MONOCHROME = "MONOCHROME"
	end

	if not private.replaceBlizzFonts then return end

	SetFont(SystemFont, NORMAL, size)
	SetFont(GameFontNormal, NORMAL, size)
	SetFont(GameFontNormalSmall, NORMAL, size)
	SetFont(GameFontNormalLarge, NORMAL, size)
	SetFont(GameFontNormalHuge, NORMAL, 25, MONOCHROME .. "OUTLINE")
	SetFont(BossEmoteNormalHuge, NORMAL, 25, MONOCHROME .. "OUTLINE")
	SetFont(GameFontBlack, NORMAL, size)
	SetFont(NumberFontNormal, NUMBER, size, MONOCHROME .. "OUTLINE")
	SetFont(NumberFontNormalSmall, NUMBER, size)
	SetFont(NumberFontNormalLarge, NUMBER, size)
	SetFont(NumberFontNormalHuge, NUMBER, size)
	SetFont(ChatFontNormal, NORMAL, size)
	SetFont(ChatFontSmall, NORMAL, size)
	SetFont(QuestTitleFont, NORMAL, size + 8)
	SetFont(QuestFont, NORMAL, size)
	SetFont(QuestFontHighlight, NORMAL, size)
	SetFont(ItemTextFontNormal, NORMAL, size)
	SetFont(MailTextFontNormal, NORMAL, size)
	SetFont(SubSpellFont, NORMAL, size)
	SetFont(DialogButtonNormalText, NORMAL, size)
	SetFont(ZoneTextFont, NORMAL, 32, MONOCHROME .. "OUTLINE")
	SetFont(SubZoneTextFont, NORMAL, 24, MONOCHROME .. "OUTLINE")
	SetFont(PVPInfoTextFont, NORMAL, 22, MONOCHROME .. "OUTLINE")
	SetFont(TextStatusBarText, NORMAL, size)
	SetFont(TextStatusBarTextSmall, NORMAL, size)
	SetFont(InvoiceTextFontNormal, NORMAL, size)
	SetFont(InvoiceTextFontSmall, NORMAL, size)
	SetFont(CombatTextFont, COMBAT, 25, MONOCHROME .. "OUTLINE")
end

-- On Unreal Azeroth the Font object pass above does not reach any FontString
-- (a Font object's SetFont is not inherited, and SetFontObject does not
-- re-bind a string to the changed object), while a FontString's own SetFont
-- works, native strings included, and lasts. So on UA a window's text is set
-- string by string: `E:ApplyNativeFonts(frame)` walks the frame's regions and
-- child frames and gives every FontString the UI font at its current size and
-- flags. Sizes therefore stay the client's own; the per-object sizes of the
-- pass above are not reproduced.
--
-- Enumerated regions and children are stripped-down objects on UA (a
-- FontString from GetRegions has no SetFont), so each is resolved through its
-- global name; unnamed region strings are skipped. The addon's own E:FontTemplate
-- strings (`E.texts`) keep their font. `elvFontGen` marks the
-- E:UpdateBlizzardFonts generation a string was given, so repeated calls on
-- every show only touch new strings or a changed setting.
local NATIVE_FONT_MAX_DEPTH = 8

local function ResolveByName(object)
	local okName, name = pcall(object.GetName, object)
	if okName and type(name) == "string" and name ~= "" then
		return _G[name]
	end
end

local function ApplyNativeFontToString(fs, path, gen, texts)
	if fs and fs.elvFontGen ~= gen and not texts[fs] and fs.SetFont and fs.GetFont then
		local okFont, _, size, flags = pcall(fs.GetFont, fs)
		if okFont and type(size) == "number" and size > 0 then
			pcall(fs.SetFont, fs, path, size, flags or "")
		end
		fs.elvFontGen = gen
	end
end

local function ApplyNativeFontToRegions(frame, path, gen, texts)
	local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
	if not okRegions or type(regions) ~= "table" then return end
	local i
	for i = 1, table.getn(regions) do
		ApplyNativeFontToString(ResolveByName(regions[i]), path, gen, texts)
	end
end

-- A button's label on UA takes its font from the button's current state:
-- normal, highlight (hovered) and disabled (a selected tab included,
-- PanelTemplates_SelectTab disables it) each keep a font of their own. A
-- FontString SetFont changes only the state shown at that moment, and that
-- state keeps it (measured: a font set once while hovered came back on every
-- later hover). UA has no SetHighlightFontObject / SetDisabledFontObject, a
-- native button's XML OnEnter cannot be read back to chain onto, and the
-- state switch from LockHighlight / Disable lands a frame later (a SetFont in
-- the same call still writes the normal state), so the states cannot be set
-- in advance without flipping native state that native code also uses. They
-- are covered by a per-frame poll instead, grouped by the window the walk
-- started from, so a hidden window costs one IsVisible. The client switches a
-- state's font some frames after the state begins (after OnEnter for a
-- hover), with a varying delay, and GetFont does not tell which state's font
-- is shown, so while a button stays in one state its label is given the UI
-- font on each of that state's first 16 frames (the frame the switch lands on
-- gets it at once), and the state counts as set only after frame 16; a state
-- left earlier is tried again next time. A SetFont that lands on an already
-- converted state is harmless. A button leaves the watch once its normal and
-- highlight states are set and its disabled state is set or left to the
-- Disable wrapper below (until the font setting changes), and the poll hides
-- itself once no shown window has a button left to watch; every walk of a
-- window that still has one shows it again.
local STATE_DONE_FRAMES = 16
local stateGroups = {}
local statePoller

local function CursorOverButton(button)
	local x, y = GetCursorPosition()
	local scale = button:GetEffectiveScale()
	if not x or not y or not scale or scale == 0 then return false end
	x = x / scale
	y = y / scale
	local left, right = button:GetLeft(), button:GetRight()
	local top, bottom = button:GetTop(), button:GetBottom()
	if not left or not right or not top or not bottom then return false end
	return x >= left and x <= right and y >= bottom and y <= top
end

local function ButtonFontState(button)
	local okEnabled, enabled = pcall(button.IsEnabled, button)
	if okEnabled and not ElvUI.Compat.bool(enabled) then return "disabled" end
	local okOver, over = pcall(CursorOverButton, button)
	if okOver and over then return "highlight" end
	return "normal"
end

-- The disabled state is not waited for when the button's Disable is wrapped
-- (HookButtonDisable): the wrapper puts the button back on the watch when it
-- is disabled. Without the wrapper all three states have to be seen.
local function ButtonFontStatesDone(entry, state, gen)
	if entry.normal ~= gen or entry.highlight ~= gen then return false end
	if entry.disabled == gen then return true end
	return entry.disableHooked and state ~= "disabled"
end

-- Returns true once the button needs no more watching; it is then marked
-- (`elvStateFontGen`) so a later walk does not watch it again.
local function ScanButtonFontState(button, entry, path, gen)
	local state
	local okVisible, visible = pcall(button.IsVisible, button)
	if okVisible and visible then state = ButtonFontState(button) end
	if ButtonFontStatesDone(entry, state, gen) then
		button.elvStateFontGen = gen
		entry.pending = nil
		return true
	end
	if not state then
		entry.pending = nil
		return false
	end
	if entry[state] == gen then
		entry.pending = nil
		return false
	end
	if entry.pending ~= state then
		entry.pending = state
		entry.frames = 0
	end
	entry.frames = entry.frames + 1
	do
		local text = entry.text
		local okFont, _, size, flags = pcall(text.GetFont, text)
		if okFont and type(size) == "number" and size > 0 then
			pcall(text.SetFont, text, path, size, flags or "")
		end
	end
	if entry.frames >= STATE_DONE_FRAMES then
		entry[state] = gen
		entry.pending = nil
	end
	return false
end

local function ScanButtonFontStates(path, gen)
	local complete = true
	local window, group, button, entry
	for window, group in pairs(stateGroups) do
		local okShown, shown = pcall(window.IsVisible, window)
		if okShown and shown then
			for button, entry in pairs(group) do
				if ScanButtonFontState(button, entry, path, gen) then
					group[button] = nil
				else
					complete = false
				end
			end
			if not next(group) then stateGroups[window] = nil end
		end
	end
	return complete
end

local function ShowStatePoller()
	if not statePoller then
		statePoller = CreateFrame("Frame")
		statePoller:SetScript("OnUpdate", function()
			local path = E.media and E.media.normFont
			if not path then return end
			if ScanButtonFontStates(path, E.nativeFontGen or 1) then
				statePoller:Hide()
			end
		end)
	end
	statePoller:Show()
end

local function WatchButton(window, button, entry)
	local group = stateGroups[window]
	if not group then
		group = {}
		stateGroups[window] = group
	end
	group[button] = entry
	ShowStatePoller()
end

-- Native code disables a button from Lua (`PanelTemplates_SelectTab` on the
-- selected tab, the quest log on its Share button), so an instance-level
-- Disable wrapper sees every switch to the disabled state and the poll does
-- not have to wait for it. On UA an instance field shadows the widget method
-- for Lua callers (pfQuest replaces ChatFrame AddMessage the same way). If
-- the field cannot be set, the poll keeps waiting for the state instead.
local function HookButtonDisable(button, entry)
	if entry.disableHooked ~= nil then return end
	entry.disableHooked = false
	local original = button.Disable
	if type(original) ~= "function" then return end
	local wrapper = function(self)
		original(self)
		if entry.disabled ~= (E.nativeFontGen or 1) and entry.window then
			pcall(WatchButton, entry.window, button, entry)
		end
	end
	if pcall(function() button.Disable = wrapper end) and button.Disable == wrapper then
		entry.disableHooked = true
	end
end

local walkWindow

local function WatchButtonFontStates(button, text)
	if button.elvStateFontGen == (E.nativeFontGen or 1) then return end
	local entry = button.elvFontEntry
	if not entry then
		entry = {}
		button.elvFontEntry = entry
	end
	entry.text = text
	entry.window = walkWindow
	HookButtonDisable(button, entry)
	WatchButton(walkWindow, button, entry)
end

-- A button's own label is not among its regions on UA (GetRegions returns
-- only its textures), so it is fetched with GetFontString.
local function ApplyNativeFontToButtonText(frame, path, gen, texts)
	if not frame.GetFontString then return end
	local okText, text = pcall(frame.GetFontString, frame)
	if not okText or not text then return end
	text = ResolveByName(text) or text
	if texts[text] or not text.SetFont then return end
	ApplyNativeFontToString(text, path, gen, texts)
	WatchButtonFontStates(frame, text)
end

local function ApplyNativeFontTree(frame, path, gen, texts, depth)
	ApplyNativeFontToRegions(frame, path, gen, texts)
	ApplyNativeFontToButtonText(frame, path, gen, texts)
	if depth >= NATIVE_FONT_MAX_DEPTH then return end

	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	if not okKids or type(kids) ~= "table" then return end
	local i
	for i = 1, table.getn(kids) do
		local kid = ResolveByName(kids[i]) or kids[i]
		ApplyNativeFontTree(kid, path, gen, texts, depth + 1)
	end
end

function E:ApplyNativeFonts(frame)
	if not frame or not (ElvUI.Compat and ElvUI.Compat.isUA) then return end
	local private = self.private and self.private.general
	if not private or not private.replaceBlizzFonts then return end
	local path = self.media and self.media.normFont
	if not path then return end
	walkWindow = frame
	pcall(ApplyNativeFontTree, frame, path, self.nativeFontGen or 1, self.texts, 0)
	walkWindow = nil
	-- The poll hid itself when this window last closed; buttons still waiting
	-- from then are already listed, so no new registration would show it.
	if stateGroups[frame] then ShowStatePoller() end
end
