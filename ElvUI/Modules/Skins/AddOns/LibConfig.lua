local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- LibConfig-1.0 (the options window of ElvUI_Config and of other addons):
-- ElvUI's colours through the library's lib:SetTheme. All addons share one
-- LibStub copy, so every LibConfig window changes together.
--
-- Theme keys, after real ElvUI's Ace3 skin (Skins/Addons/Ace3.lua):
--   backdrop          <- general.backdropcolor ("Default": window, controls)
--   backdropFade      <- general.backdropfadecolor ("Transparent": sidebar)
--   border, borderDim <- general.bordercolor; a disabled control keeps the
--                        plain border, LibConfig's lighter grey would stand
--                        out against a black one
--   hover             <- the value colour, the hover border of
--                        S:SetModifiedBackdrop, followed live through
--                        E.valueColorUpdateFuncs
-- The rule under section titles and tab strips keeps LibConfig's grey: real
-- ElvUI shows the value colour only on interaction (hover), never on a static
-- surface. The accent (checked box, selected row and tab, slider thumb) stays
-- LibConfig's gold: real ElvUI's Ace3 skin hard-codes the same 1, .82, 0.
-- The text colours are the same in both.
--
-- Border and backdrop colours are read once, at login, as on every other
-- ElvUI surface. An addon loaded on demand that brings a newer LibConfig
-- copy re-runs the library file and resets its theme.

local function DBColor(key, fallback)
	local c = E.db.general and E.db.general[key]
	if type(c) ~= "table" then return fallback end
	return { c.r, c.g, c.b, c.a or 1 }
end

local function HoverColor()
	local c = (E.media and E.media.rgbvaluecolor) or S.ACCENT_COLOR
	return { c[1], c[2], c[3], 1 }
end

-- The theme in LibConfig's THEME keys; PunyAuras.lua passes the same table
-- to PunyAuras' own options window.
function S:GetLibConfigTheme()
	local border = DBColor("bordercolor", S.BORDER_COLOR)
	return {
		backdrop = DBColor("backdropcolor", S.WIDGET_COLOR),
		backdropFade = DBColor("backdropfadecolor", { 0.06, 0.06, 0.06, 0.8 }),
		border = border,
		borderDim = border,
		hover = HoverColor(),
	}
end

local skinned

local function ValueColorUpdate(hex, r, g, b)
	if skinned then skinned:SetTheme({ hover = { r, g, b } }) end
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

-- Gated by real ElvUI's Ace3 skin switch, E.private.skins.ace3.enable.
local function LoadSkin(lib)
	local ace3 = E.private.skins and E.private.skins.ace3
	if ace3 and not ace3.enable then return end
	if type(lib.SetTheme) ~= "function" then return end
	lib:SetTheme(S:GetLibConfigTheme())
	skinned = lib
end

S:AddLibrarySkin("LibConfig-1.0", LoadSkin)
