local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- PunyAuras: its options window (PunyAurasOptions) is drawn in LibConfig-1.0's
-- look but keeps a colour table of its own, so it gets the LibConfig skin's
-- theme (S:GetLibConfigTheme, LibConfig.lua) through PA:SetOptionsTheme. The
-- aura options embedded in its right pane are LibConfig's own widgets and
-- follow that skin directly. Keys PunyAuras does not use are ignored by it.
--
-- Fonts: on Unreal Azeroth the window's XML strings (title, toolbar, filter,
-- list headers, the aura rows built from PunyAurasDisplayButtonTemplate) keep
-- the client font, as a Font object change does not reach them there, while
-- the LibConfig widgets in the right pane already show the UI font. The window
-- is walked with E:ApplyNativeFonts while it is shown: once, again for every
-- new aura row (PunyAuras names them PunyAurasOptionsDisplay1, 2, ... and
-- builds them as the list grows), and after a font setting change. Each check
-- is a visibility test and one global lookup.

local OPTIONS = "PunyAurasOptions"
local DISPLAY_ROW = OPTIONS .. "Display"

local skinned

local function ValueColorUpdate(hex, r, g, b)
	if skinned then skinned:SetOptionsTheme({ hover = { r, g, b } }) end
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

local fontRows, fontGen = 0, nil

local function UpdateFonts()
	local window = _G[OPTIONS]
	if not (window and window:IsVisible()) then return end
	local changed = fontGen ~= E.nativeFontGen
	while _G[DISPLAY_ROW .. (fontRows + 1)] do
		fontRows = fontRows + 1
		changed = true
	end
	if changed then
		fontGen = E.nativeFontGen
		E:ApplyNativeFonts(window)
	end
end

local function WatchFonts()
	if not (ElvUI.Compat and ElvUI.Compat.isUA) then return end
	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnUpdate", function() pcall(UpdateFonts) end)
end

local function LoadSkin()
	local addon = type(PunyAuras) == "table" and PunyAuras[1]
	if not (type(addon) == "table" and type(addon.SetOptionsTheme) == "function") then return end
	addon:SetOptionsTheme(S:GetLibConfigTheme())
	skinned = addon
	WatchFonts()
end

S:AddAddOnSkin("PunyAuras", LoadSkin)
