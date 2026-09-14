-- Registration of the core addon's translations.
--
-- AceLocale-3.0 decides on every NewLocale call whether a translation is
-- needed, comparing against `GAME_LOCALE or GetLocale()`. GAME_LOCALE is the
-- "Addon Language" setting (ElvUI_Config/General.lua), stored as one of
-- ElvUI's own SavedVariables -- and a client assigns an addon's
-- SavedVariables only after every file of that addon has run. A translation
-- file in this directory calling NewLocale directly therefore always sees
-- GAME_LOCALE as nil and registers for the game client's language only, while
-- ElvUI_Config, loading after ElvUI's SavedVariables, follows the setting.
--
-- So the translation files here only fill a plain table per locale
-- (ElvUI.NewLocaleTable), and ElvUI.ApplyLocale writes the chosen one into the
-- AceLocale application. It is called from three places, and only the first
-- call that sees a different language does any work:
--   * Init.lua at file load, with the client language, so strings read while
--     the remaining core files load are translated on a non-English client;
--   * ElvUI_Config/Locales/enUS.lua, the first ElvUI_Config file: GAME_LOCALE
--     is loaded by then, and the options files store L[] strings in their
--     tables at file load, which can happen before ElvUI's OnInitialize;
--   * the start of ElvUI's OnInitialize, for when ElvUI_Config is disabled.
-- A string read at file load keeps the client language under an override, so
-- core code reads L[] where the string is used, not into a file-level local.
--
-- enUS.lua still registers the default locale itself: it is the application's
-- first registration and sets `silent`. ElvUI_Config/Locales keeps calling
-- NewLocale directly.

ElvUI = ElvUI or {}

local translations = {}
local applied = "enUS"

-- Returns the table a translation file assigns its strings into.
function ElvUI.NewLocaleTable(locale)
	local strings = translations[locale]
	if not strings then
		strings = {}
		translations[locale] = strings
	end
	return strings
end

-- Switching away from an already applied translation first writes `true` back
-- for its keys: every enUS.lua value is `true` (the key is the English text),
-- and a non-default write replaces an existing value, unlike the default
-- locale's write.
function ElvUI.ApplyLocale()
	local locale = GAME_LOCALE or GetLocale()
	if locale == "enGB" then locale = "enUS" end
	if locale == applied then return end

	local L = LibStub("AceLocale-3.0"):NewLocale("ElvUI", locale)
	if not L then return end

	local key, value
	local previous = translations[applied]
	if previous then
		for key in pairs(previous) do
			L[key] = true
		end
	end

	local strings = translations[locale]
	if strings then
		for key, value in pairs(strings) do
			L[key] = value
		end
	end

	applied = locale
end
