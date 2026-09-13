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
--
-- Keys are the English strings themselves rather than symbolic names
-- (the key is "Bottom Panel", not "BOTTOM_PANEL"), matching what real ElvUI does
-- for the bulk of its own entries: a translator sees the source text, and an
-- untranslated string still reads correctly.
--
-- Grouped by the options file each string first appears in; a string used by more
-- than one file is listed once, under the first.
--
-- WHAT IS ROUTED THROUGH HERE: every ElvUI_Config option `name`/`desc`, every
-- dropdown (`values`) label that is real prose, the static-popup bodies, and the
-- ~15 `E:Print` messages a player actually reads.
--
-- WHAT IS DELIBERATELY NOT, and should stay that way:
--   * Modules/Skins/Skins.lua's ~84 E:Print calls, and the per-window
--     "OnShow hook failed to install" warnings. These are DEVELOPER
--     DIAGNOSTICS driven by debug commands (S:DumpTabs, the sweep counters,
--     WaitForGlobal failures) -- asking a translator for
--     "checkboxes new=%d already=%d unrecog=%d seen=%d" is noise, and real
--     ElvUI does not localise its own debug output either.
--   * Modules/NamePlates/NamePlates.lua's 32 calls: that module is a
--     client-side dead end (docs/dead-ends/nameplates.md), so they are dead
--     code.
--   * All-caps token labels in `values` tables (["TOPLEFT"] = "TOPLEFT" and
--     friends) -- the label IS the key, there is nothing to translate.

local AceLocale = LibStub:GetLibrary("AceLocale-3.0")
local L = AceLocale:NewLocale("ElvUI", "enUS", true, true)
if not L then return end

--Core
L["ElvUI"] = true
L["Install"] = true
L["Run the installation process."] = true
L["Toggle Anchors"] = true
L["Unlock various elements of the UI to be repositioned."] = true
L["Reset Anchors"] = true
L["Reset all frames to their original positions."] = true
L["Profiles"] = true
L["You can change the active database profile, so you can have different settings for every character.\n\nProfiles are shared account-wide by name. Switching points this character at an existing profile, sharing it going forward -- editing it on either character then changes both. Copying takes an independent snapshot instead. Every action here requires a reload to take effect."] = true
L["\nReset the current profile back to its default values, in case your configuration is broken, or you simply want to start over."] = true
L["Reset Profile"] = true
L["Reset the current profile to the default"] = true
L["\nYou can either create a new profile by entering a name in the editbox, or choose one of the already existing profiles."] = true
L["New"] = true
L["Create a new empty profile."] = true
L["Existing Profiles"] = true
L["Select one of your currently available profiles."] = true
L["\nCopy the settings from one existing profile into the currently active profile."] = true
L["Copy From"] = true
L["Copy the settings from one existing profile into the currently active profile."] = true
L["\nDelete existing and unused profiles from the database to save space, and cleanup the SavedVariables file."] = true
L["Delete a Profile"] = true
L["Deletes a profile from the database."] = true
L["Export / Import"] = true
L["A plain Lua table -- NOT the compressed/encoded format some addons use. Click Generate, then select all (Ctrl+A) and copy from the box below to export this character's current profile as text. A profile exported from real ElvUI-vanilla's own \"Export as Lua Table\" option can be pasted into the Import box as-is."] = true
L["Generate Export"] = true
L["(Re)computes the export text below from this character's current profile."] = true
L["Export (read from here)"] = true
L["Import (paste here, press Enter)"] = true

--General
L["General"] = true
L["Core settings shared across the whole UI."] = true
L["Loot"] = true
L["Enable/disable the custom loot frame, replacing the native one. Requires /reload to take effect."] = true
L["Loot Under Mouse"] = true
L["Open the loot frame at the cursor instead of its fixed position."] = true
L["Bottom Panel"] = true
L["Display a panel across the bottom of the screen. This is for cosmetic only."] = true
L["Top Panel"] = true
L["Display a panel across the top of the screen. This is for cosmetic only."] = true
L["Cooldown Text"] = true
L["Enable"] = true
L["Display cooldown text on anything with the cooldown spiral. Turning it off clears existing text within a fraction of a second; turning it on labels cooldowns as they next start, so any spiral already running keeps no text until it is triggered again."] = true
L["Low Threshold"] = true
L["Threshold before text turns red and is in decimal form. Set to -1 for it to never turn red."] = true
L["Duration Format"] = true
L["MM:SS Threshold"] = true
L["Below this many SECONDS remaining, show the time as M:SS instead of the plain minutes form -- e.g. 30:00 rather than 30m. Set to -1 to never use this format."] = true
L["HH:MM Threshold"] = true
L["Below this many MINUTES remaining, show the time as H:MM instead of the plain hours form. Set to -1 to never use this format."] = true
L["Mirror Timers"] = true
L["Restyles the native breath/feign-death/exhaustion (fatigue) bars -- purely visual, the actual tracking is 100% Blizzard's own native code."] = true
L["Requires /reload to take effect."] = true
L["Width"] = true
L["Height"] = true
L["Media"] = true
L["Textures"] = true
L["Primary Texture"] = true
L["The texture used mainly for statusbars. Requires /reload to take effect."] = true
L["Secondary Texture"] = true
L["Used as the fill of every button-shaped backdrop -- this is where their subtle top-to-bottom falloff comes from. Requires /reload to take effect."] = true

L["Decimal Length"] = true
L["How many decimals a shortened value keeps -- 0 turns 1700 into 2K, 1 into 1.7K."] = true
L["Unit Prefix Style"] = true
L["Which unit prefixes a shortened value uses. Visible on unit frame health/power text and on the XP/Reputation bars."] = true
L["Border Color"] = true
L["Main border color of the UI."] = true
L["Backdrop Color"] = true
L["Main backdrop color of the UI."] = true
L["Backdrop Faded Color"] = true
L["Backdrop color of transparent frames."] = true
L["Value Color"] = true
L["Color some texts use."] = true

--ActionBars
L["Buttons"] = true
L["The amount of buttons to display."] = true
L["Buttons Per Row"] = true
L["The amount of buttons to display per row."] = true
L["Button Size"] = true
L["The size of the action buttons."] = true
L["Button Spacing"] = true
L["The spacing between buttons."] = true
L["Backdrop"] = true
L["Toggles the display of the actionbar's backdrop."] = true
L["Show Empty Buttons"] = true
L["Alpha"] = true
L["ActionBars"] = true
L["Action bar layout, sizing and text. Each bar is configured on its own tab."] = true
L["Requires /reload to take effect -- checked once at login, no live toggle."] = true
L["General Options"] = true
L["Keybind Text"] = true
L["Display bind names on action buttons."] = true
L["Macro Text"] = true
L["Display macro names on action buttons."] = true
L["Lock Action Bars"] = true
L["Prevent dragging spells and items off the action bars."] = true
L["Fonts"] = true
L["Font"] = true
L["Font Size"] = true
L["Applies to keybind and macro text. Currently a no-op on UA (SetFont doesn't apply size there) -- kept for real 1.12.1 and in case UA fixes this."] = true
L["Font Outline"] = true
L["Pet Bar"] = true
L["Stance Bar"] = true
L["Style"] = true
L["Not yet implemented on this project -- real ElvUI's own darkenInactive behavior recolors the button's native CheckedTexture, the same kind of call already found tinting gold-wrong on UA elsewhere (see Modules/ActionBars/ActionBars.lua's own StyleButton comment). Currently only the active stance is highlighted, others are left at their native unchecked look, regardless of this setting. Schema-only for now."] = true

--Auras
L["Size"] = true
L["Set the size of the individual auras."] = true
L["Wrap After"] = true
L["Begin a new row after this many auras."] = true
L["Max Wraps"] = true
L["Limit the number of rows. Wrap After x Max Wraps is the most auras this display will ever show -- and the area the /moveui handle outlines."] = true
L["Horizontal Spacing"] = true
L["Vertical Spacing"] = true
L["Larger than you might expect by default (16) because the duration text hangs below each icon."] = true
L["Sort Method"] = true
L["Sort Direction"] = true
L["Auras"] = true
L["Player buffs and debuffs, shown next to the minimap instead of Blizzard's own BuffFrame."] = true
L["Also disables the native Blizzard buff/debuff frame -- there's no separate toggle for that, matching every other module in this addon (ActionBars, Minimap, etc.): enabling our own replacement always hides the original. Requires /reload to take effect."] = true
L["The player's own buff/debuff display, in the ORIGINAL Blizzard buff-frame location (near the minimap) -- separate from the small icon grid attached directly to the Player unit frame under UnitFrames > Player > Buffs/Debuffs. Matches real ElvUI's own separate 'Auras' module, which runs both at once."] = true
L["Fade Threshold"] = true
L["Seconds remaining before the countdown text switches to the Expiring color and decimal form, and the icon starts flashing. Set to -1 to disable both. Real ElvUI field name: auras.fadeThreshold."] = true
L["Time X Offset"] = true
L["Horizontal offset of the duration text, relative to its default spot under the icon."] = true
L["Time Y Offset"] = true
L["Count X Offset"] = true
L["Horizontal offset of the stack-count text."] = true
L["Count Y Offset"] = true
L["Buffs"] = true
L["Debuffs"] = true

--Bags
L["Bags"] = true
L["One merged window replacing the native bag windows. The native item and bag-slot buttons are reused rather than rebuilt, so they keep their own click, drag and tooltip behavior."] = true
L["Money Format"] = true
L["Clear Search On Close"] = true
L["Reset the bag search box when the window closes, instead of keeping the filter for next time."] = true
L["Size and Positions"] = true
L["Button Size (Bag)"] = true
L["The size of the individual buttons on the bag frame."] = true
L["Panel Width (Bags)"] = true
L["Adjust the width of the bag frame. The number of columns follows from it and the slot size."] = true
L["Button Size (Bank)"] = true
L["The size of the individual buttons on the bank frame."] = true
L["Panel Width (Bank)"] = true
L["Adjust the width of the bank frame. The number of columns follows from it and the slot size."] = true

--Tooltip
L["Targeted By:"] = true
L["Tooltip"] = true
L["Setup options for the Tooltip."] = true
L["Cursor Anchor"] = true
L["Should tooltip be anchored to mouse cursor"] = true
L["Target Info"] = true
L["When in a raid group display if anyone in your raid is targeting the current tooltip unit."] = true
L["Player Titles"] = true
L["Display player titles."] = true
L["Guild Ranks"] = true
L["Display guild ranks if a unit is guilded."] = true
L["Spell/Item IDs"] = true
L["Display the spell or item ID when mousing over a spell or item tooltip."] = true
L["Opacity"] = true
L["Custom Faction Colors"] = true
L["Health Bar"] = true
L["Text"] = true
L["Item Price"] = true
L["Display vendor sell value on item tooltips."] = true
L["Item Count"] = true
L["Display how many of a certain item you have in your possession."] = true
L["Bags Only"] = true
L["Bank Only"] = true
L["Both"] = true
L["Sell Price:"] = true
L["Count"] = true
L["Bank"] = true
L["Visibility"] = true
L["Bags/Bank"] = true
L["Always Hide"] = true
L["Never Hide"] = true
L["Shift Key"] = true
L["ALT-Key"] = true
L["CTRL-Key"] = true
L["Choose when you want the tooltip to show. If a modifer is chosen, then you need to hold that down to show the tooltip."] = true
L["Hide tooltip while in combat."] = true

--Chat
L["Chat"] = true
L["Only the left/default chat window is docked and skinned -- the right panel exists (datatexts, mover, collapse icon all work) but nothing docks a second chat window into it. Message formatting (timestamps, URL links, keyword highlighting, spam throttle) applies project-wide, not just the docked window. Not implemented: chat history log/replay, hyperlink hover tooltips, channel-link click-to-switch -- see CLAUDE.md."] = true
L["Requires /reload."] = true
L["Attempt to create clickable URL links inside the chat."] = true
L["Shorten the channel names in chat."] = true
L["Not yet implemented on this project (no GameTooltip hook yet)."] = true
L["Keep the last channel you spoke in selected when opening the chat editbox. Disabled means it always defaults to Say."] = true
L["Fade the chat text when there is no activity."] = true
L["Not yet implemented on this project."] = true
L["Require holding the Alt key down to move the cursor or cycle through messages in the editbox."] = true
L["Select the format of timestamps prefixed to chat messages."] = true
L["Use the custom color below for timestamps instead of plain white."] = true
L["Prevent the same channel/yell message from displaying more than once within this many seconds. 0 disables."] = true
L["Not yet implemented on this project (auto-scroll-to-bottom after being scrolled up)."] = true
L["Number of repeated characters allowed in the chat editbox while in combat before it's automatically closed."] = true
L["Number of lines to scroll per mouse wheel step."] = true
L["Alerts"] = true
L["Sound to play on an incoming whisper. Only \"None\" is selectable until custom sounds are registered with LibSharedMedia-3.0."] = true
L["Sound to play when a keyword below is spoken in chat. Only \"None\" is selectable until custom sounds are registered with LibSharedMedia-3.0."] = true
L["Don't play whisper/keyword alert sounds while in combat."] = true
L["Comma-separated list of words to highlight in chat. Use %MYNAME% for your own character name.\n\nExample:\n%MYNAME%, ElvUI"] = true
L["Panels"] = true
L["Keep the left chat frame docked inside its panel."] = true
L["Toggle the chat tab panel backdrop."] = true
L["Toggle showing of the left and right chat panel backdrops."] = true
L["Enable the use of separate size options for the right chat panel."] = true

--DataTexts
L["DataTexts"] = true
L["Small information panels; each slot can show a different datatext."] = true
L["\n"] = true
L["Panel Transparency"] = true
L["Use the transparent backdrop for the datatext panels instead of the solid one."] = true
L["Draw a backdrop behind the chat datatext panels. Turning this off leaves them functional but invisible."] = true
L["Gold Format"] = true
L["The display format of the money text shown in the gold datatext and its tooltip."] = true
L["Currently a no-op on UA (SetFont doesn't apply size there) -- kept for real 1.12.1 and in case UA fixes this."] = true
L["Datatext Panel (Left)"] = true
L["Display a data panel below the left chat frame, used for datatexts."] = true
L["Datatext Panel (Right)"] = true
L["Display a data panel below the right chat frame, used for datatexts."] = true
L["Minimap Panels"] = true
L["Display minimap panels below the minimap, used for datatexts."] = true
L["Small Panels"] = true
L["Time"] = true
L["Time Format"] = true
L["Date Format"] = true
L["Friends"] = true
L["Hide"] = true
L["Away"] = true
L["Busy"] = true

--Nameplates
L["NamePlates"] = true
L["First pass -- name/level/health only, colored by unit reaction. Discovers native plates by scanning WorldFrame's children (no per-plate unit token exists on this API vintage) and mutes their native art. Real ElvUI's own per-unit-type (Friendly Player/Enemy Player/NPC/...) health bar sizing, castbar, buffs/debuffs, combo points, and threat coloring are NOT implemented."] = true
L["Replaces the native nameplate name/level/health display. Requires /reload to take effect."] = true
L["Show Level"] = true
L["Show Health Percentage"] = true
L["Scale Target Plate"] = true
L["Target Scale"] = true
L["Non-Target Transparency"] = true

--Skins
L["Skins"] = true
L["Reskins native Blizzard windows in place -- same frame, same functionality, just restyled to match this UI. Individually toggleable per window."] = true
L["Blizzard"] = true
L["Master switch for every Blizzard window skin below. Requires /reload to take effect."] = true

--UnitFrames
L["Text Format"] = true
L["Tag substitution (not the full real-ElvUI tag DSL): [healthcolor] [powercolor] [health:current] [health:max] [health:current-percent] [health:percent] [power:current] [power:max] [power:percent] [name] [level], plus any plain text. Empty = no text."] = true
L["Position"] = true
L["X Offset"] = true
L["Y Offset"] = true
L["Default (White) Color"] = true
L["Color"] = true
L["Used when Default Color is off."] = true
L["Anchor Point"] = true
L["Corner of the health bar this icon is centered on."] = true
L["Per Row"] = true
L["Icon Size"] = true
L["NOT a real ElvUI field -- a project addition."] = true
L["Min Duration"] = true
L["Only show an aura if its remaining duration is at least this many seconds. 0 = no minimum. Has no effect on an aura with no known duration."] = true
L["Max Duration"] = true
L["Only show an aura if its remaining duration is at most this many seconds. 0 = no maximum. Has no effect on an aura with no known duration."] = true
L["Transparent"] = true
L["Extra text elements, each independently positioned/attached. Uses this addon's own tag list (same as Health/Power/Name's own Text Format field: [healthcolor] [powercolor] [health:current] [health:max] [health:current-percent] [health:percent] [power:current] [power:max] [power:percent] [name] [level]) -- NOT real ElvUI's full tag DSL."] = true
L["Delete"] = true
L["Attach To"] = true
L["Justify"] = true
L["Create Custom Text"] = true
L["Type a unique name and press Enter to add a new custom text below."] = true
L["Color Override"] = true
L["Force On always uses class/reaction color; Force Off never does, regardless of the Colors tab toggles (that tab is shared by every unit)."] = true
L["Health"] = true
L["Power"] = true
L["Name"] = true
L["Portrait"] = true
L["Only real ElvUI's own fields (Enable/Style/Size/Overlay) -- see CLAUDE.md's \"UnitFrames\" section for the UA-specific research (SetCamera, etc.) behind why 3D looks right without any extra project-only knobs."] = true
L["Only used when Overlay is off."] = true
L["Overlay"] = true
L["The portrait overlays the Health bar instead of sitting beside it."] = true
L["Combat Icon"] = true
L["Information Panel"] = true
L["Custom Texts"] = true
L["Resting Icon"] = true
L["Happiness"] = true
L["Hunter-pet-only loyalty indicator (HasPetUI()'s own isHunterPet flag) -- stays hidden for any other pet, e.g. a Warlock's. A narrow bar stuck out past Health's own left edge -- see UnitFrames.lua's own Construct_Happiness comment for why this doesn't reflow Health/Power's width the way real ElvUI does."] = true
L["Auto Hide When Happy"] = true
L["Castbar"] = true
L["Requires /reload to take effect (enable only). Player-only -- the classic vanilla cast events only ever describe your own cast."] = true
L["Show Icon"] = true
L["Show Spark"] = true
L["UnitFrames"] = true
L["Custom-built unit frames (Player, Target, Pet, Target of Target, Pet Target, Party). Per-unit settings live in their own sidebar sections; the shared colours and the statusbar texture are under General."] = true
L["Bars"] = true
L["Statusbar Texture"] = true
L["Applies live, no /reload needed. Custom addon-shipped textures don't render on UA -- only native paths (like the default) actually show anything."] = true
L["Colors"] = true
L["Color Health By Class"] = true
L["Color Health By Value"] = true
L["Gradient from red to green (or, combined with Color Health By Class, red to the class/reaction color) as health drops, instead of a flat color."] = true
L["Custom Health Backdrop Color"] = true
L["Transparent Health"] = true
L["Dims the health bar (fill and background) so something behind it -- e.g. an overlay portrait -- shows through. Simplified from real ElvUI's own texture-masking technique to a uniform alpha reduction, see UnitFrames.lua's own comment."] = true
L["Use Dead Backdrop Color"] = true
L["Base Health Color"] = true
L["Used when Color Health By Class and Color Health By Value are both off."] = true
L["Health Backdrop Color"] = true
L["Dead Backdrop Color"] = true
L["Color Power By Class"] = true
L["Transparent Power"] = true
L["Same as Transparent Health, for the power bar."] = true
L["Reaction"] = true
L["Reaction: Hostile"] = true
L["Used for a non-player unit's class/reaction color (e.g. Target) when it's hostile."] = true
L["Reaction: Neutral"] = true
L["Reaction: Friendly"] = true
L["Player"] = true
L["Target"] = true
L["Pet"] = true
L["Target of Target"] = true
L["Pet Target"] = true
L["Party"] = true

L["What the aura grid hangs off. Buffs/Debuffs stacks it on the other aura grid instead of on the frame."] = true
L["Frame"] = true
L["Which point of the attach-to frame the grid sits on, and therefore which way it grows."] = true
L["Num Rows"] = true
L["Maximum rows of icons. Together with Per Row this caps how many auras can ever show; 0 means no cap."] = true
L["Click Through"] = true
L["Ignore mouse events, so clicks land on the unit frame underneath instead of on the icon. Also disables the icon's own tooltip."] = true
L["Size Override"] = true
L["Icon edge length. 0 falls back to the built-in default size."] = true
L["Sort By"] = true
L["Method to sort by. Auras with no measurable duration always sort last."] = true
L["Time Remaining"] = true
L["Index"] = true
L["Ascending"] = true
L["Descending"] = true

--DataBars
L["DataBars"] = true
L["Experience and reputation bars."] = true
L["XP Bar"] = true
L["Mouseover"] = true
L["Hide At Max Level"] = true
L["Hide in Combat"] = true
L["Statusbar Fill Orientation"] = true
L["Direction the bar moves on gains/losses."] = true
L["Reputation Bar"] = true
L["Shows the faction picked with the Character panel's Reputation tab > \"Show as Experience Bar\" checkbox. With no watched faction the bar stays hidden regardless."] = true

--Maps
L["Scale"] = true
L["Note: the calendar icon was invisible near the minimap on UA (a frame-stacking issue, see CLAUDE.md) -- a fix was applied 2026-08-31 but isn't yet confirmed in-game."] = true
L["Map"] = true
L["World Map"] = true
L["Smaller World Map"] = true
L["Opens the World Map as a normal panel instead of a fullscreen, input-blocking window. Requires /reload -- untested."] = true
L["World Map Coordinates"] = true
L["Puts coordinates on the world map. Requires /reload to take effect -- checked once at login, no live toggle."] = true
L["X-Offset"] = true
L["Y-Offset"] = true
L["Minimap"] = true
L["Adjust the size of the minimap. Takes effect immediately."] = true
L["Location Text"] = true
L["Change when the zone name above the minimap is shown."] = true
L["Reset Zoom"] = true
L["Automatically zoom back out after a period of no zoom activity."] = true
L["Seconds"] = true
L["Minimap Buttons"] = true
L["Time Info"] = true
L["Mail"] = true
L["PvP Queue"] = true

--ActionBars (text position)
L["Text Position"] = true
L["Hotkey Text Position"] = true
L["Hotkey Text X-Offset"] = true
L["Hotkey Text Y-Offset"] = true
L["Backdrop Spacing"] = true
L["The spacing between the backdrop and the buttons."] = true
L["Attach Text To"] = true
L["Texture"] = true
L["Default"] = true
L["Custom"] = true
L["Custom Texture"] = true
L["A texture path, e.g. Interface\\Icons\\Spell_Nature_Sleep. Empty falls back to the default icon."] = true
L["Select a unit to copy settings from."] = true
L["Restore Defaults"] = true
L["Reset every setting for this unit back to its default."] = true
L["Use Health Texture Backdrop"] = true
L["Draw the bar background with the statusbar texture instead of a flat fill."] = true

--Core / modules (chat output, popup bodies)
L["Core initialized."] = true
L["|cffff0000Error -- Addon 'ElvUI_Config' not found or is disabled.|r"] = true
L["Movers unlocked -- see the Move UI panel (drag it out of the way if it covers something). 'Lock Movers' there, or /moveui again, exits."] = true
L["Movers locked."] = true
L["Reset %d mover position(s)."] = true
L["Copied profile '%s' onto this character. /reload to apply."] = true
L["Now using profile '%s'. /reload to apply."] = true
L["A profile named '%s' already exists -- pick another name, or switch to it under Existing Profiles."] = true
L["Created profile '%s' and switched to it. /reload to apply."] = true
L["Profile '%s' reset to defaults. /reload to apply."] = true
L["Refusing to delete the profile this character is using -- switch to another one first."] = true
L["Deleted profile '%s'."] = true
L["Import failed -- couldn't parse the pasted text as a Lua table."] = true
L["Profile imported. /reload to apply."] = true
L["One or more of the changes you have made require a ReloadUI."] = true
L["One or more of the changes you have made will effect all characters using this addon. You will have to reload the user interface to see the changes you have made."] = true
L["A setting you have changed will change an option for this character only. This setting that you have changed will be uneffected by changing user profiles. Changing this setting requires that you reload your User Interface."] = true
L["Every bank bag slot has already been purchased."] = true
L["None"] = true
L["Outline"] = true
L["Monochrome Outline"] = true
L["Thick Outline"] = true
L["Darken Inactive"] = true
L["Normal"] = true
L["Below Chat"] = true
L["Above Chat"] = true
L["Hide Both"] = true
L["Show Both"] = true
L["Left Only"] = true
L["Right Only"] = true
L["Left"] = true
L["Right"] = true
L["Top"] = true
L["Bottom"] = true
L["Center"] = true
L["Top Left"] = true
L["Top Right"] = true
L["Bottom Left"] = true
L["Bottom Right"] = true
L["Reset every frame to its original position? All saved mover positions will be lost."] = true
L["Replace this character's entire profile with an independent copy of the selected one?"] = true
L["Reset this character's profile back to its default values? Every setting you have changed on this profile will be lost."] = true
L["Are you sure you want to delete the selected profile?"] = true
L["Smart"] = true
L["Full"] = true
L["Short"] = true
L["Short (Whole Numbers)"] = true
L["Condensed"] = true
L["Blizzard Style"] = true
L["Metric (k, M, G)"] = true
L["English (K, M, B)"] = true
L["Chinese (W, Y)"] = true
L["Korean (\236\178\156, \235\167\140, \236\150\181)"] = true
L["German (Tsd, Mio, Mrd)"] = true
L["Reset this unit frame's settings to their defaults? Everything you have changed for this unit will be lost."] = true
L["Use Default"] = true
L["Force Class Color On"] = true
L["Force Class Color Off"] = true
L["Current"] = true
L["Current / Max"] = true
L["Remaining"] = true
