local E, L, V, P, G = unpack(ElvUI)

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

local function SetFont(obj, font, size, style)
	if not obj or not obj.SetFont then return end
	pcall(obj.SetFont, obj, font, size, style)
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
