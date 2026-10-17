local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- PunyAuras: its options window (PunyAurasOptions) is drawn in LibConfig-1.0's
-- look but keeps a colour table of its own, so it gets the LibConfig skin's
-- theme (S:GetLibConfigTheme, LibConfig.lua) through PA:SetOptionsTheme. The
-- aura options embedded in its right pane are LibConfig's own widgets and
-- follow that skin directly. Keys PunyAuras does not use are ignored by it.

local skinned

local function ValueColorUpdate(hex, r, g, b)
	if skinned then skinned:SetOptionsTheme({ hover = { r, g, b } }) end
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

local function LoadSkin()
	local addon = type(PunyAuras) == "table" and PunyAuras[1]
	if not (type(addon) == "table" and type(addon.SetOptionsTheme) == "function") then return end
	addon:SetOptionsTheme(S:GetLibConfigTheme())
	skinned = addon
end

S:AddAddOnSkin("PunyAuras", LoadSkin)
