-- Static popups -- the "one or more of your changes needs a ReloadUI" dialog
-- with an Accept button that performs the reload, so a reload-bound setting
-- never needs the user to type /reload by hand.
--
-- Real ElvUI reaches this through a COMPLETE reimplementation of Blizzard's
-- static-popup system (its Core/StaticPopups.lua, 1068 lines: its own
-- ElvUI_StaticPopup1-4 frames, its own show/hide/reuse/queue logic, editbox and
-- money-input variants). That is deliberately NOT ported. This project already
-- drives the NATIVE StaticPopupDialogs registry elsewhere for exactly this kind
-- of dialog (Modules/Misc/Loot.lua overrides CONFIRM_LOOT_DISTRIBUTION in it),
-- and it already SKINS the native StaticPopup1-4 frames
-- (Modules/Skins/Skins.lua's S:InstallStaticPopupSkin) -- so registering here
-- means these dialogs come out looking like the rest of the UI for free, on
-- both clients, with no new frame code to get wrong.
--
-- The PUBLIC API is upstream's, on purpose: `E.PopupDialogs[which]` and
-- `E:StaticPopup_Show(which)`. Config setters therefore read exactly as their
-- real ElvUI counterparts do (`E:StaticPopup_Show("PRIVATE_RL")`), and if the
-- full upstream popup system is ever ported, every call site stays put.
--
-- Registry keys are prefixed `ELVUI_` inside the native table. Upstream needs no
-- prefix because it owns its own registry; here the table is shared with
-- Blizzard and every other addon, and "CONFIG_RL" is a plausible enough name
-- for someone else to claim.

local E, L, V, P, G = unpack(ElvUI)

local KEY_PREFIX = "ELVUI_"

-- `ACCEPT`/`CANCEL` are FrameXML GlobalStrings and should exist on both clients,
-- but a nil `button1` renders a dialog with NO buttons at all -- an unclosable
-- modal, which is a far worse failure than an untranslated label. Falling back to
-- literals costs nothing and removes that whole class of outcome.
-- Parked on the engine table as well: ElvUI_Config registers its own popup
-- entries (RESET_ALL_MOVERS, the profile confirmations, RESET_UF_UNIT) and
-- needs the same guarantee.
local BTN_ACCEPT = ACCEPT or L["Accept"]
local BTN_CANCEL = CANCEL or L["Cancel"]
E.PopupAccept, E.PopupCancel = BTN_ACCEPT, BTN_CANCEL

-- Texts are real ElvUI's own (its Core/StaticPopups.lua:197-226), so the wording
-- a user sees matches what they would see under real ElvUI.
E.PopupDialogs = E.PopupDialogs or {}

E.PopupDialogs["CONFIG_RL"] = {
	button1 = BTN_ACCEPT,
	button2 = BTN_CANCEL,
	OnAccept = ReloadUI,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = false,
}

E.PopupDialogs["GLOBAL_RL"] = {
	button1 = BTN_ACCEPT,
	button2 = BTN_CANCEL,
	OnAccept = ReloadUI,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = false,
}

E.PopupDialogs["PRIVATE_RL"] = {
	button1 = BTN_ACCEPT,
	button2 = BTN_CANCEL,
	OnAccept = ReloadUI,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = false,
}

-- Copied into the native registry. `StaticPopupDialogs` exists as a plain global
-- table from FrameXML on both clients, and Blizzard's own StaticPopup_Show only
-- ever looks the key up in it at call time -- so a table written here is found
-- later with no hook and no frame of our own.
--
-- Done at load AND again on every show, because entries are not all declared in
-- this file: ElvUI_Config loads much later and adds its own (RESET_ALL_MOVERS),
-- and a one-shot copy at load would silently never carry those across. Copying
-- an already-present key again is free.
--
-- The three entries above get their text here, on every registration, not in
-- their table constructors: this file loads before the "Addon Language"
-- setting is applied (Locales/Locales.lua), so a load-time read would keep the
-- client's language.
local function RegisterPopups()
	if type(StaticPopupDialogs) ~= "table" then return end

	E.PopupDialogs["CONFIG_RL"].text = L["One or more of the changes you have made require a ReloadUI."]
	E.PopupDialogs["GLOBAL_RL"].text = L["One or more of the changes you have made will effect all characters using this addon. You will have to reload the user interface to see the changes you have made."]
	E.PopupDialogs["PRIVATE_RL"].text = L["A setting you have changed will change an option for this character only. This setting that you have changed will be uneffected by changing user profiles. Changing this setting requires that you reload your User Interface."]

	local which, info
	for which, info in pairs(E.PopupDialogs) do
		StaticPopupDialogs[KEY_PREFIX..which] = info
	end
end

RegisterPopups()

-- `which` is the UNPREFIXED name, matching real ElvUI's call sites.
--
-- pcall'd, because a popup failing must never take down the config setter that
-- asked for it: a dialog that cannot be shown is a cosmetic loss, the setting
-- itself has already been written by the time this is called. (The dead-player
-- and timeout rules are Blizzard's own, driven by the `whileDead`/`timeout`
-- fields on each entry -- upstream reimplements those checks because it also
-- reimplements the frames; here the native code applies them for us.)
function E:StaticPopup_Show(which)
	if not E.PopupDialogs[which] then return end
	if type(StaticPopup_Show) ~= "function" then return end

	RegisterPopups()
	pcall(StaticPopup_Show, KEY_PREFIX..which)
end

-- Convenience for the common case, and the reason this file exists: a config
-- `set` that has just written a reload-bound field calls this and is done.
-- Picks the right upstream wording from which DB the field lives in.
--
--   "profile" (or nil) -> CONFIG_RL   E.db.*
--   "private"          -> PRIVATE_RL  E.private.*  (per character)
--   "global"           -> GLOBAL_RL   E.global.*   (all characters)
function E:RequestReload(scope)
	if scope == "private" then
		self:StaticPopup_Show("PRIVATE_RL")
	elseif scope == "global" then
		self:StaticPopup_Show("GLOBAL_RL")
	else
		self:StaticPopup_Show("CONFIG_RL")
	end
end
