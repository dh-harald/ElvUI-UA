local E, L, V, P, G = unpack(ElvUI)

-- Incompatible addon check, after real ElvUI's E:CheckIncompatible: when an
-- addon that replaces one of ElvUI's modules is loaded while that module is
-- active, a popup asks which of the two to use. Choosing the addon switches
-- the ElvUI side off; choosing ElvUI disables the addon for this character.
-- Both reload the UI.
--
-- The list is data keyed by module, in real ElvUI's shape: an `info` block
-- (`enabled`: is the ElvUI side active; `useAddOn`: switch the ElvUI side
-- off; `name`: the ElvUI button's label) followed by addon folder names.
-- `E:AddIncompatible` lets another addon add itself to a group. Only the
-- first conflict found is shown; the next one comes up after the reload.
--
-- The native 1.12 static popup has two buttons, so real ElvUI's third
-- "Disable Warning" button (`E.global.ignoreIncompatible`) is not ported.

local Compat = ElvUI.Compat

local ADDONS = {
	Bags = {
		-- The native bag skin counts as the ElvUI side too: bag addons
		-- (Bagzen) reuse the native ContainerFrame item buttons, which that
		-- skin restyles.
		info = {
			enabled = function()
				if E.private.bags.enable then return true end
				local skins = E.private.skins and E.private.skins.blizzard
				return skins and skins.enable and skins.bags
			end,
			useAddOn = function()
				E.private.bags.enable = false
				E.private.skins.blizzard.bags = false
			end,
			name = "ElvUI Bags",
		},
		"Bagzen",
		"EH_Bag",
		"AllBags",
		"Bagnon",
		"OneBag",
		"EngInventory",
		"SUCC-bag",
	},
}

E.INCOMPATIBLE_ADDONS = ADDONS

function E:AddIncompatible(module, addonName)
	local addons = ADDONS[module]
	if addons then
		table.insert(addons, addonName)
	end
end

-- Unreal Azeroth: DisableAddOn without a character name changes the setting
-- for every character, and the change is kept only after SaveAddOns. The
-- 1.12.1 client takes the addon alone and applies it to the current
-- character.
local function DisableForCharacter(addon)
	if Compat.isUA then
		pcall(DisableAddOn, UnitName("player"), addon)
	else
		pcall(DisableAddOn, addon)
	end
	if type(SaveAddOns) == "function" then
		pcall(SaveAddOns)
	end
end

-- button1 = the addon, button2 = the ElvUI module. The native popup also
-- calls OnCancel when another exclusive popup pushes this one out
-- ("override"), on timeout, and during a cinematic, so the addon is only
-- disabled for an actual click; any other dismissal asks again after the
-- next reload.
E.PopupDialogs["INCOMPATIBLE_ADDON"] = {
	OnAccept = function()
		local popup = E.PopupDialogs["INCOMPATIBLE_ADDON"]
		popup.info.useAddOn()
		ReloadUI()
	end,
	OnCancel = function(data, reason)
		if reason ~= "clicked" then return end
		local popup = E.PopupDialogs["INCOMPATIBLE_ADDON"]
		DisableForCharacter(popup.addon)
		ReloadUI()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = false,
}

function E:IncompatibleAddOn(addon, module, info)
	local popup = E.PopupDialogs["INCOMPATIBLE_ADDON"]
	popup.text = L["INCOMPATIBLE_ADDON"]
	popup.button1 = addon
	popup.button2 = info.name or module
	popup.addon = addon
	popup.module = module
	popup.info = info
	E:StaticPopup_Show("INCOMPATIBLE_ADDON", addon, popup.button2)
end

local function FindIncompatible(module, addons)
	local i
	for i = 1, Compat.getn(addons) do
		local addon = addons[i]
		if Compat.bool(IsAddOnLoaded(addon)) then
			E:IncompatibleAddOn(addon, module, addons.info)
			return true
		end
	end
end

function E:CheckIncompatible()
	local module, addons
	for module, addons in pairs(ADDONS) do
		local ok, active = pcall(addons.info.enabled)
		if ok and active and FindIncompatible(module, addons) then
			return
		end
	end
end

E:RegisterModule("Incompatible", function() E:CheckIncompatible() end)
