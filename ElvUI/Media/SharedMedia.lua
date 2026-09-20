-- Registers font, statusbar, border and sound media with LibSharedMedia-3.0.
--
-- Every name below points at an asset file this addon actually ships
-- (Media/Fonts, Media/Textures, Media/Sounds) or at a NATIVE client path --
-- nothing here names a file that isn't present.
--
-- THAT INVARIANT INCLUDES EXACT CHARACTER CASE, extension included. UA resolves
-- media paths case-SENSITIVELY while the real 1.12.1 client does not, so a
-- mis-cased entry works on legacy and silently resolves to nothing on UA. That
-- asymmetry is what once got mistaken for "custom textures don't render on UA"
-- and for "LibSharedMedia doesn't work for statusbars" -- neither is true.
--
-- Because the real ElvUI font and texture files ARE vendored, real ElvUI's own
-- default media names resolve here -- "Homespun", "PT Sans Narrow",
-- "ElvUI Norm" -- so an imported real profile's font/texture choices work, and
-- our own defaults have no reason to deviate on availability grounds.
--
-- Two things are NOT settled, and neither is an availability question:
--   * `SetFont` is a no-op on UA, so a font CHANGE is
--     inert on that client regardless of what is registered here. Custom
--     TEXTURES do render.
--   * SOUND playback is unverified on this client. Sound file playback only
--     recently appeared in UA's API and nothing here has been measured against
--     it, which is why the chat sound settings default to "None" rather than to
--     real ElvUI's own "ElvUI Aska" -- the registrations below are ready for
--     when it is tested, not evidence that it works.
local LSM = LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

LSM:Register("statusbar", "ElvUI Gloss", [[Interface\AddOns\ElvUI\Media\Textures\normTex]])
LSM:Register("statusbar", "ElvUI Norm", [[Interface\AddOns\ElvUI\Media\Textures\normTex2]])
LSM:Register("statusbar", "Minimalist", [[Interface\AddOns\ElvUI\Media\Textures\Minimalist]])
LSM:Register("statusbar", "ElvUI Blank", [[Interface\BUTTONS\WHITE8X8]])
LSM:Register("statusbar", "Melli", [[Interface\AddOns\ElvUI\Media\Textures\melli]])
LSM:Register("statusbar", "BantoBar", [[Interface\AddOns\ElvUI\Media\Textures\BantoBar]])

LSM:Register("background", "ElvUI Blank", [[Interface\BUTTONS\WHITE8X8]])

LSM:Register("border", "ElvUI GlowBorder", [[Interface\AddOns\ElvUI\Media\Textures\glowTex]])

LSM:Register("font", "Continuum Medium", [[Interface\AddOns\ElvUI\Media\Fonts\Continuum_Medium.ttf]])
LSM:Register("font", "Die Die Die!", [[Interface\AddOns\ElvUI\Media\Fonts\DieDieDie.ttf]])
LSM:Register("font", "Action Man", [[Interface\AddOns\ElvUI\Media\Fonts\Action_Man.ttf]])
LSM:Register("font", "Expressway", [[Interface\AddOns\ElvUI\Media\Fonts\Expressway.ttf]], LSM.LOCALE_BIT_ruRU + LSM.LOCALE_BIT_western)
LSM:Register("font", "PT Sans Narrow", [[Interface\AddOns\ElvUI\Media\Fonts\PT_Sans_Narrow.ttf]], LSM.LOCALE_BIT_ruRU + LSM.LOCALE_BIT_western)
LSM:Register("font", "Homespun", [[Interface\AddOns\ElvUI\Media\Fonts\Homespun.ttf]], LSM.LOCALE_BIT_ruRU + LSM.LOCALE_BIT_western)

LSM:Register("sound", "ElvUI Aska", [[Interface\AddOns\ElvUI\Media\Sounds\sndIncMsg.ogg]])
LSM:Register("sound", "Awww Crap", [[Interface\AddOns\ElvUI\Media\Sounds\awwcrap.ogg]])
LSM:Register("sound", "BBQ Ass", [[Interface\AddOns\ElvUI\Media\Sounds\bbqass.ogg]])
LSM:Register("sound", "Big Yankie Devil", [[Interface\AddOns\ElvUI\Media\Sounds\yankiebangbang.ogg]])
LSM:Register("sound", "Dumb Shit", [[Interface\AddOns\ElvUI\Media\Sounds\dumbshit.ogg]])
LSM:Register("sound", "Mama Weekends", [[Interface\AddOns\ElvUI\Media\Sounds\mamaweekends.ogg]])
LSM:Register("sound", "Runaway Fast", [[Interface\AddOns\ElvUI\Media\Sounds\runfast.ogg]])
LSM:Register("sound", "Stop Running", [[Interface\AddOns\ElvUI\Media\Sounds\stoprunningslimball.ogg]])
LSM:Register("sound", "Warning", [[Interface\AddOns\ElvUI\Media\Sounds\warning.ogg]])
LSM:Register("sound", "Whisper Alert", [[Interface\AddOns\ElvUI\Media\Sounds\whisper.ogg]])
LSM:Register("sound", "ElvUI LevelUp", [[Sound\Interface\LevelUp.wav]])
