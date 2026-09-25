-- English localization -- enUS/enGB, and the DEFAULT locale every other one
-- falls back to. Format follows real ElvUI's own Locales/English_UI.lua: a
-- `NewLocale(app, locale, isDefault, silent)` call, then one assignment per
-- string whose value is `true` -- AceLocale's shorthand for "this key IS its own
-- value". NOTE: no example of that assignment is written out in this comment on
-- purpose; a bare one would be picked up as a real declaration by anything that
-- scans this file for keys.
--
-- The FOUR-argument form matters. `silent = true` installs the metatable that
-- returns the KEY for an unknown lookup instead of raising -- so a typo at a call
-- site degrades to the English text showing through, never to a broken options
-- page. AceLocale also requires `silent` to be set on the FIRST locale registered
-- for an application, so a translation file added later cannot introduce it
-- retroactively -- which is why it is here from the start even with one language.
-- This file is that first registration: ElvUI loads before ElvUI_Config.
--
-- Keys are the English strings themselves rather than symbolic names
-- (the key is "Bottom Panel", not "BOTTOM_PANEL"), matching what real ElvUI does
-- for the bulk of its own entries: a translator sees the source text, and an
-- untranslated string still reads correctly. Where real ElvUI localises the same
-- text, reuse its key verbatim, so its translation files carry over.
--
-- WHAT IS ROUTED THROUGH HERE: strings the core addon shows -- chat output a
-- player actually reads, popups the core opens, tooltip and bag lines, the Lua
-- error window. Strings only the options window shows are declared in
-- ElvUI_Config/Locales/enUS.lua instead, under the same "ElvUI" application; a
-- key is declared in exactly one of the two files.
--
-- A problem notice the player can see without asking for it is written for a
-- player, not a developer: short, naming the visible effect rather than the
-- cause, and routed through here. Every window-skin failure goes through
-- S:ReportSkinProblem (Modules/Skins/Skins.lua), which prints once per session.
--
-- WHAT IS DELIBERATELY NOT, and should stay that way:
--   * Modules/Skins/Skins.lua's debug output: the S:Dump*/S:WhyNotSkinned/
--     S:FindThinTextures/S:SnapshotTree family, run by hand with /run, and
--     everything gated behind S.autoSkinDebug (the sweep counters, the
--     dropdown probes). Only a developer ever sees it -- asking a translator
--     for "checkboxes new=%d already=%d unrecog=%d seen=%d" is noise, and
--     real ElvUI does not localise its own debug output either.
--   * Modules/NamePlates/NamePlates.lua's 32 calls: that module is hard-disabled
--     (NP:Initialize returns immediately, native nameplates are not reachable
--     from Lua on Unreal Azeroth), so they are dead code.
--   * All-caps token labels in `values` tables (["TOPLEFT"] = "TOPLEFT" and
--     friends) -- the label IS the key, there is nothing to translate.

local AceLocale = LibStub:GetLibrary("AceLocale-3.0")
local L = AceLocale:NewLocale("ElvUI", "enUS", true, true)
if not L then return end

--Core
L["Core initialized."] = true
L["|cffff0000Error -- Addon 'ElvUI_Config' not found or is disabled.|r"] = true
L["Movers unlocked -- see the Move UI panel (drag it out of the way if it covers something). 'Lock Movers' there, or /moveui again, exits."] = true
L["Movers locked."] = true
L["Reset %d mover position(s)."] = true
L["Target"] = true

--Profiles
L["Copied profile '%s' onto this character. /reload to apply."] = true
L["Now using profile '%s'. /reload to apply."] = true
L["A profile named '%s' already exists -- pick another name, or switch to it under Existing Profiles."] = true
L["Created profile '%s' and switched to it. /reload to apply."] = true
L["Profile '%s' reset to defaults. /reload to apply."] = true
L["Refusing to delete the profile this character is using -- switch to another one first."] = true
L["Deleted profile '%s'."] = true
L["Import failed -- couldn't parse the pasted text as a Lua table."] = true
L["Profile imported. /reload to apply."] = true

--Static popups
L["One or more of the changes you have made require a ReloadUI."] = true
L["One or more of the changes you have made will effect all characters using this addon. You will have to reload the user interface to see the changes you have made."] = true
L["A setting you have changed will change an option for this character only. This setting that you have changed will be uneffected by changing user profiles. Changing this setting requires that you reload your User Interface."] = true

--Tooltip
L["Targeted By:"] = true
L["Sell Price:"] = true
L["Count"] = true
L["Bank"] = true

--Static popup buttons (fallbacks for a missing ACCEPT/CANCEL global)
L["Accept"] = true
L["Cancel"] = true

--DataBars
L["Experience"] = true
L["XP:"] = true
L["Remaining:"] = true
L["Rested:"] = true
L["Standing:"] = true
L["Reputation:"] = true
L["Hated"] = true
L["Hostile"] = true
L["Unfriendly"] = true
L["Neutral"] = true
L["Friendly"] = true
L["Honored"] = true
L["Revered"] = true
L["Exalted"] = true
L["Unknown"] = true

--Maps
L["Cursor"] = true

--LootRoll
L["BoP"] = true
L["BoE"] = true

--Misc
L["Your items have been repaired for: "] = true
L["You don't have enough money to repair."] = true

--Tooltip (fallbacks for a missing client global)
L["Level"] = true
L["Rare"] = true
L["Dead"] = true
L["Currently Equipped"] = true
L["DPS"] = true
L["If you replace this item:"] = true

--Problem messages (shown to the player, so they name the effect, not the cause)
L["The right-click menu is not available for this frame."] = true
L["A unit frame could not be created."] = true
L["Some windows could not be restyled and keep their default look."] = true

--UnitFrames
L["Ghost"] = true
L["Offline"] = true
L["Failed"] = true
L["Interrupted"] = true
L["Castbar"] = true

--Movers
L["Move UI"] = true
L["Drag a highlighted frame to move it."] = true
L["Click one, then use the arrow keys"] = true
L["to nudge it (hold Shift for 10px)."] = true
L["Lock Movers"] = true
L["Reset All"] = true
L["Player Frame"] = true
L["Player Castbar"] = true
L["Target Castbar"] = true
L["Target Frame"] = true
L["Target of Target Frame"] = true
L["Pet Frame"] = true
L["Pet Target Frame"] = true
L["Party %d Frame"] = true
L["Bar "] = true
L["Pet Bar"] = true
L["Stance Bar"] = true
L["Experience Bar"] = true
L["Reputation Bar"] = true
L["Player Buffs"] = true
L["Player Debuffs"] = true
L["Minimap"] = true
L["Tooltip"] = true
L["Mirror Timer %d"] = true

--Bags
L["Every bank bag slot has already been purchased."] = true
L["Some bag shortcuts may still open the default bag window."] = true
L["Hold Shift + Drag:"] = true
L["Temporary Move"] = true
L["Hold Control + Right Click:"] = true
L["Reset Position"] = true
L["Toggle Keyring"] = true
L["Toggle Bags"] = true
L["Toggle Bank Bags"] = true
L["Purchase Bank Bag Slot"] = true
L["All slots purchased."] = true
L["Search"] = true
L["Bag Mover"] = true
L["Bank Mover"] = true
L["Vendoring Grays"] = true
L["Vendored gray items for: %s"] = true
L["Sort Bags"] = true
L["Already Running.. Bailing Out!"] = true
L["Confused.. Try Again!"] = true
L["Sorting the bank needs at least one bank bag."] = true

--Chat
L["Toggle Chat Frame"] = true
L["Left Chat"] = true
L["Right Chat"] = true
L["Invalid Target"] = true
L["BG"] = true
L["G"] = true
L["P"] = true
L["R"] = true
L["O"] = true
L["BGL"] = true
L["RL"] = true
L["RW"] = true
L["AFK"] = true
L["DND"] = true
L["whispers"] = true
L["says"] = true
L["yells"] = true

--Install
L["CVars Set"] = true
L["Theme Set"] = true
L["Resolution Style Set"] = true
L["Layout Set"] = true
L["Chat Set"] = true
L["Auras Set"] = true
L["Welcome to ElvUI"] = true
L["This wizard will help you set up your interface."] = true
L["The configuration menu is always available via /elvui or /ec. This wizard can be reopened later with /eiw."] = true
L["Press Next to continue, or Skip to close without changing anything."] = true
L["Skip"] = true
L["CVars"] = true
L["This step sets up a few of your World of Warcraft options so the interface behaves as expected."] = true
L["Click the button below to apply them."] = true
L["Importance: High"] = true
L["Importance: Medium"] = true
L["Importance: Low"] = true
L["Setup CVars"] = true
L["Chat"] = true
L["This step sets up which message types show in your main chat window (say/yell/emotes/whispers/etc.) and your combat log window."] = true
L["You can always change this later by right-clicking a chat tab -- nothing here is one-way."] = true
L["Setup Chat"] = true
L["Theme Setup"] = true
L["Choose a color theme for your interface."] = true
L["Border/backdrop colors apply to newly built frames immediately; a /reload shows the full effect everywhere else. Class also colors health/cast bars by class."] = true
L["Classic"] = true
L["Dark"] = true
L["Class"] = true
L["Resolution"] = true
L["High Resolution"] = true
L["Low Resolution"] = true
L["This step resizes chat windows, unit frames, and action bar buttons for your resolution."] = true
L["Choose High Resolution if your screen is wide enough, or Low Resolution if things feel cramped."] = true
L["All changes apply immediately -- no /reload needed."] = true
L["Layout"] = true
L["Choose a layout based on your combat role."] = true
L["This repositions your unit frames and (Healer only) reshapes your action bars for more click-heal room. Unit frames, bar button counts, and castbar size apply immediately; enabling/disabling a bar needs /reload."] = true
L["Tank"] = true
L["Healer"] = true
L["Physical DPS"] = true
L["Caster DPS"] = true
L["Auras"] = true
L["Select the aura style for your unit frames."] = true
L["This project only has icon-style auras -- there is no aura bar style to choose between."] = true
L["Icons Only"] = true
L["Setup Complete"] = true
L["You are finished with the setup wizard."] = true
L["Click Finished to save and reload your interface."] = true
L["Finished"] = true

--Loot
L["Fishy Loot"] = true
L["Empty Slot"] = true
L["Loot Frame"] = true

--DataTexts
L["Armor"] = true
L["Mitigation By Level: "] = true
L["AP"] = true
L["Attack Power"] = true
L["Melee Attack Power"] = true
L["Ranged Attack Power"] = true
L["Avoidance"] = true
L["Defense"] = true
L["Avoidance Breakdown"] = true
L["lvl"] = true
L["Boss"] = true
L["Dodge Chance"] = true
L["Parry Chance"] = true
L["Block Chance"] = true
L["Miss Chance"] = true
L["Unhittable:"] = true
L["Durability"] = true
L["Friends"] = true
L["Friends List"] = true
L["Online"] = true
L["Gold"] = true
L["Session:"] = true
L["Earned:"] = true
L["Spent:"] = true
L["Deficit:"] = true
L["Profit:"] = true
L["Character: "] = true
L["Server: "] = true
L["Total: "] = true
L["Reset Data: Hold Shift + Right Click"] = true
L["Guild"] = true
L["No Guild"] = true
L["MOTD"] = true
L["System"] = true
L["Home Latency:"] = true
L["Total Memory:"] = true
L["Time"] = true
L["Realm Time:"] = true

--Misc
L["Loot / Alert Frames"] = true
L["Totem Tracker"] = true

--Mail
L["Open All"] = true
L["Open Selected"] = true
L["Stop"] = true
L["No mail selected."] = true
L["The mailbox is empty."] = true
L["Received %s (x%d)."] = true
L["Received %s."] = true
L["Your bags are full -- stopped opening mail."] = true
L["Stopped opening mail."] = true
L["Could not take everything from one mail -- skipped it."] = true
L["Skipped %d C.O.D. mail(s)."] = true
L["Collected %s."] = true
L["Return Selected"] = true
L["Returned mail to %s."] = true
L["Could not return one mail -- skipped it."] = true
L["Skipped %d mail(s) that cannot be returned."] = true
L["Stopped returning mail."] = true
L["The attachment list is full."] = true
L["No recipient."] = true
L["Could not attach one item -- skipped it."] = true
L["%s (%d of %d)"] = true
L["Sent %s."] = true
L["One mail was not accepted -- stopped sending."] = true
L["Sent %d mails."] = true
L["Removed %d emptied mail(s)."] = true

--Lua error window
L["|cFFE30000Lua error recieved. You can view the error message when you exit combat."] = true
L["Lua Error"] = true
L["Reload UI"] = true
L["First"] = true
L["Previous"] = true
L["Next"] = true
L["Last"] = true
L["Clear"] = true
L["No Lua errors recorded."] = true
L["To copy: click the text, then Ctrl+A and Ctrl+C."] = true
L["Lua error recorded. Type /elvui errors to view it."] = true
L["Lua error window: opens automatically."] = true
L["Lua error window: does not open automatically. /elvui errors shows recorded errors."] = true
