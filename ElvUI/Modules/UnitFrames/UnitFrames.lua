-- UnitFrames -- core module. Custom-built, NOT oUF-based: oUF was tried
-- and abandoned -- its own frame-metatable-swap mechanism, core to how it
-- attaches methods to a spawned frame, is broken on UA.
--
-- This mirrors real ElvUI's own
-- ARCHITECTURE (a shared core module with Construct_HealthBar/
-- Construct_PowerBar/Construct_NameText helpers, reused by a per-unit
-- Construct_XFrame in Units/<Name>.lua, dispatched by unit id) and its
-- CONFIG SCHEMA (P.unitframe.* field names matched to real ElvUI's own,
-- for eventual real-profile compatibility) -- but the actual RENDERING
-- primitives are custom, built from pieces already proven working on UA
-- elsewhere in this project, plus one new one (Util.CreateStatusBar,
-- Core/Util.lua) stolen from source/UnrealUI/modules/unitframes.lua's own
-- proven-on-UA hand-rolled status bar technique.
--
-- SECOND PASS: port over every setting related to the character frame and
-- try to implement it, ahead of copying a real profile onto this
-- character. Real ElvUI's actual Player unit frame
-- (source/ElvUI-vanilla/ElvUI/Modules/UnitFrames/{UnitFrames,Units/
-- Player,Elements/{Health,Power,Name,Portrait,RestingIndicator,
-- CombatIndicator}}.lua) is genuinely enormous -- pixel-perfect
-- BORDER/SPACING/portrait/classbar-offset layout math, detached/inset/
-- spaced power-bar modes, castbar, buffs/debuffs, class resource bars,
-- raid icons/roles, an info panel, a whole Skins-module dependency this
-- project doesn't have. Full fidelity is not attempted. What IS ported,
-- field-name-and-behavior-matched to the real thing: health/power
-- color options (colorOverride, healthclass, colorhealthbyvalue,
-- customhealthbackdrop, useDeadBackdrop, powerclass), health/power/name
-- TEXT via a small tag substitution engine (a handful of the most common
-- real ElvUI tags -- NOT the full tag DSL), text position/offset,
-- portrait (both 2D and 3D -- see the "THIRD PASS" note below, this line
-- was written before 3D was re-tested and confirmed working), and the
-- resting/combat state icons. Explicitly NOT implemented: castbar,
-- buffs/debuffs (blocked on the aura duration-tracking system), class resource bars, raid target
-- icon/role icons, threat glow, heal prediction, info panel, custom
-- texts, detached/inset/spaced power-bar layouts, the PvP text/icon
-- elements. Still schema-inert if a real profile carries fields for any
-- of these -- Util.MergeTable passes unknown keys through untouched, see
-- Core/Profiles.lua's own comment on this.
--
-- THIRD PASS: portrait simplified to ONLY real
-- ElvUI's own fields (enable/width/style/overlay; the element itself is
-- implemented per client in PortraitUA.lua / PortraitLegacy.lua), the shared
-- color/update logic generalized to any unit (not hardcoded `.player`),
-- and a second unit (Target) added.

local E, L, V, P, G = unpack(ElvUI)
-- "AceHook-3.0" is needed for the Castbar's own icon-capture
-- hooks (see that section's own comment) -- bare `hooksecurefunc` alone
-- was silently not firing for the icon capture, matching this project's
-- own already-established finding for HookScript ("no reliably-present
-- bare global HookScript... route through AceHook-3.0's :HookScript
-- instead") -- the same class of gap, apparently not unique to
-- HookScript specifically.
local UF = E:NewModule("UnitFrames", "AceEvent-3.0", "AceHook-3.0")
E.UnitFrames = UF

-- LSM statusbar-texture selector, mirroring how font selection
-- is already wired in throughout this project even though custom fonts
-- don't render on UA either: LSM/SetTexture themselves work fine, only
-- EXTERNAL addon-shipped asset FILES fail to load -- a native
-- `Interface\...` path always works, which is exactly what "ElvUI Blank"
-- -- this setting's own default -- resolves to). Same
-- `LibStub("LibSharedMedia-3.0", true)` pattern already used for fonts
-- elsewhere in this project (ActionBars.lua/Chat.lua's own file-level
-- upvalue), no shared helper exists project-wide so this is its own
-- local copy, matching the established per-module convention.
local LSM = LibStub("LibSharedMedia-3.0", true)
local function GetBarTexture()
	local path = LSM and LSM:Fetch("statusbar", E.db.unitframe.statusbar)
	return path or "Interface\\Buttons\\WHITE8x8"
end

-- ---------------------------------------------------------------------
-- Settings: `P.unitframe` -- fonts, `colors`, and the per-unit
-- `units.<unit>` tables (Settings/Profile.lua).
--
-- There is NO private master enable switch for this module, unlike
-- Minimap/ActionBars/PetBar/Cooldowns. Real ElvUI's
-- `P.unitframe.units[id].enable` is already a real, per-unit,
-- reload-required field; a single global private switch on top of it would
-- be redundant with, and could confusingly override, that granularity.
-- ---------------------------------------------------------------------
-- Tag substitution -- a small subset of real ElvUI's own tag DSL
-- (source/ElvUI-vanilla/ElvUI/Modules/UnitFrames/Tags.lua), not the
-- whole thing. `[tagname]` inside a text_format string is replaced by
-- its resolved value; unknown tags resolve to "". Pattern-based, not a
-- live `%` arithmetic operator, so this is Lua-5.0-parse-safe (see
-- Core/Compat.lua's own header note on that distinction).
-- ---------------------------------------------------------------------
local function ApplyTags(formatStr, tags)
	if not formatStr or formatStr == "" then return "" end
	return (string.gsub(formatStr, "%[([^%]]+)%]", function(tag)
		return tags[tag] or ""
	end))
end

-- ---------------------------------------------------------------------
-- Shared visual construction -- the pieces every per-unit Construct_*
-- function (Units/Player.lua, and any future unit) calls into.
-- ---------------------------------------------------------------------

local BACKDROP_COLOR = {0.05, 0.05, 0.05, 1}
local BORDER_COLOR = {0, 0, 0, 1}
local HEALTH_BG_COLOR = {0.1, 0.1, 0.1, 1}
local POWER_BG_COLOR = {0.1, 0.1, 0.1, 1}
local DEAD_COLOR = {0.5, 0.5, 0.5}
local INSET = 2
-- Shared with the per-client portrait files (PortraitUA.lua/PortraitLegacy.lua).
UF.INSET = INSET
-- Fixed alpha for colors.transparentHealth/transparentPower -- see the
-- defaults block above for why this is a simplified uniform-alpha
-- stand-in for real ElvUI's own inverted-fill masking technique.
local TRANSPARENT_ALPHA = 0.35

-- Builds the frame's own outer panel -- same plain SetBackdrop pattern
-- established throughout this project (Minimap/Movers/DataBars/PetBar/
-- ActionBars), NOT UnrealUI's 4-plain-texture border technique. This
-- project's own version of this exact call (bgFile PAIRED with edgeFile+
-- edgeSize) is already proven working on UA across several modules --
-- the part actually borrowed from UnrealUI here is the STATUS BAR fill
-- underneath (Util.CreateStatusBar), a genuinely different widget type,
-- not this backdrop.
-- `E.db.general.backdropcolor`/`bordercolor` (named-key, Settings/
-- Profile.lua) take over once `E:SetupTheme` (Core/Install.lua) has run
-- -- these two locals stay as the fallback for a call that lands before
-- `E.db` is built. Read at construction time only, like every other
-- backdrop in this project -- a theme switch after a frame already
-- exists needs a `/reload` to reach it, same as everywhere else.
local function ApplyPanelBackdrop(frame)
	local bc = (E.db and E.db.general and E.db.general.backdropcolor) or BACKDROP_COLOR
	local brc = (E.db and E.db.general and E.db.general.bordercolor) or BORDER_COLOR
	pcall(frame.SetBackdrop, frame, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(frame.SetBackdropColor, frame, bc.r or bc[1], bc.g or bc[2], bc.b or bc[3], bc.a or bc[4])
	pcall(frame.SetBackdropBorderColor, frame, brc.r or brc[1], brc.g or brc[2], brc.b or brc[3], brc.a or brc[4])
end

-- outline == "NONE" -> "" translation, matching the ActionBars/DataBars/
-- DataTexts established convention (this project's own stored sentinel
-- for "no outline" is the literal string "NONE", not "", which is what
-- SetFont itself expects).
local function ResolveOutline(outline)
	if outline == "NONE" then return "" end
	return outline
end

-- Real ElvUI's `UF:Update_FontString`: `unitframe.font` through LSM.
local function UnitFrameFont(name)
	return (LSM and LSM:Fetch("font", name or E.db.unitframe.font)) or "Fonts\\FRIZQT__.TTF"
end

local function ApplyFont(fontString)
	local db = E.db.unitframe
	pcall(fontString.SetFont, fontString, UnitFrameFont(), db.fontSize, ResolveOutline(db.fontOutline))
end

-- frame.Health -- a Util.CreateStatusBar bar, inset from the panel's own
-- edge. Width/position are (re)applied every UpdateFrame call (cheap,
-- and picks up a portrait being toggled on/off without a separate
-- reflow path) rather than fixed at construction.
function UF:Construct_HealthBar(frame, height)
	local bar = ElvUI.Util.CreateStatusBar(frame, {
		background = HEALTH_BG_COLOR,
		color = DEAD_COLOR,
		texture = GetBarTexture(),
	})
	bar:SetHeight(height)

	-- Explicit level, not left to auto-assignment -- an overlay portrait
	-- needs a GUARANTEED-below level relative to `frame`'s own base
	-- (where its opaque panel backdrop draws), and computing that
	-- relative to Health's level only works if Health's own level is
	-- itself reliably ABOVE frame's base, which auto-assignment doesn't
	-- guarantee for certain (siblings can land on the same level).
	-- Symptom this fixes: a transparent health bar can show
	-- the PANEL's own dark backdrop instead of the portrait behind it.
	local ok, frameLevel = pcall(frame.GetFrameLevel, frame)
	if ok and tonumber(frameLevel) then
		pcall(bar.SetFrameLevel, bar, frameLevel + 2)
	end

	-- Text sits on a raised child layer above the bar -- the fill is a
	-- sibling texture whose width changes every refresh, and text on the
	-- SAME layer can end up drawn behind it (UnrealUI's own documented
	-- reason for this same construction, source/UnrealUI/modules/
	-- unitframes.lua:926-940).
	local textLayer = CreateFrame("Frame", nil, bar)
	textLayer:SetAllPoints(bar)
	local ok, level = pcall(bar.GetFrameLevel, bar)
	if ok and tonumber(level) then
		pcall(textLayer.SetFrameLevel, textLayer, level + 10)
	end
	bar.textLayer = textLayer

	local text = textLayer:CreateFontString(nil, "OVERLAY")
	ApplyFont(text)
	bar.text = text

	frame.Health = bar
	return bar
end

-- frame.Power -- same construction, anchored directly below Health.
function UF:Construct_PowerBar(frame, height)
	local bar = ElvUI.Util.CreateStatusBar(frame, {
		background = POWER_BG_COLOR,
		color = E.db.unitframe.colors.power.MANA,
		texture = GetBarTexture(),
	})
	bar:SetHeight(height)

	-- Explicit level -- see Construct_HealthBar's own comment on why.
	local ok, frameLevel = pcall(frame.GetFrameLevel, frame)
	if ok and tonumber(frameLevel) then
		pcall(bar.SetFrameLevel, bar, frameLevel + 2)
	end

	local textLayer = CreateFrame("Frame", nil, bar)
	textLayer:SetAllPoints(bar)
	local ok, level = pcall(bar.GetFrameLevel, bar)
	if ok and tonumber(level) then
		pcall(textLayer.SetFrameLevel, textLayer, level + 10)
	end
	bar.textLayer = textLayer

	local text = textLayer:CreateFontString(nil, "OVERLAY")
	ApplyFont(text)
	bar.text = text

	frame.Power = bar
	return bar
end

-- frame.Name -- position re-applied every UpdateFrame from
-- db.name.position/xOffset/yOffset, anchored to the health bar (real
-- ElvUI's own default `attachTextTo` for player is "Health" too, so this
-- isn't a simplification for the DEFAULT case, only for a profile that
-- explicitly attaches it elsewhere -- not supported here).
function UF:Construct_NameText(frame)
	local text = frame.Health.textLayer:CreateFontString(nil, "OVERLAY")
	ApplyFont(text)
	frame.Name = text
	return text
end

-- UF:Construct_Portrait / Update_Portrait / PostUpdateHealth_Portrait are
-- defined per client: PortraitUA.lua (Unreal Azeroth) and PortraitLegacy.lua
-- (1.12.1). The method contract is at the top of PortraitUA.lua.

-- A small square icon texture (RestIcon/CombatIcon share this shape).
-- Parented to `parent` (a raised child layer, NOT `frame` directly) so it
-- draws ABOVE the health/power bars -- a texture created straight on
-- `frame` sits at `frame`'s own frame level, and `frame.Health`/`.Power`
-- are CHILD FRAMES one (or more) levels above it, so anything parented
-- to `frame` itself renders BEHIND them regardless of draw layer. Bug
-- found from a live report: the combat indicator icon was invisible
-- (hidden under the health bar) for exactly this reason.
function UF:Construct_StateIcon(parent)
	local icon = parent:CreateTexture(nil, "OVERLAY")
	icon:Hide()
	return icon
end

-- Click-to-target: the player/pet/pettarget unit frames aren't
-- clickable, and clicking one should target it. Every
-- Construct_XFrame already creates its frame as a `Button` widget, but
-- none of them ever registered for clicks or wired an OnClick -- a real
-- gap, not scope-limited to just the 3 units reported (Target/
-- TargetTarget/Party had the exact same gap, just less noticed). Plain
-- `TargetUnit(unit)` -- confirmed NOT protected on UA
-- (source/UnrealAzeroth_LuaAPI/en/globals/Targetting.md has no
-- "Protected: yes" marker, unlike e.g. CastSpell/CastShapeshiftForm,
-- which do) -- so no SecureUnitButtonTemplate/secure-attribute
-- machinery is needed at all, avoiding the template-backed-CreateFrame
-- UA risk entirely. `frame` is captured directly by the closure, not
-- read via an implicit self/this argument, so this doesn't need the
-- usual `this`-wrapping vanilla script-handler workaround -- there's
-- nothing to wrap.
-- ---------------------------------------------------------------------
-- Tooltip + right-click unit menu: player, target, target of target, pet
-- and pettarget all need a tooltip, and at least player/target need
-- their own right-click menu. Both were genuine gaps: `EnableUnitClick` only ever
-- registered LeftButtonUp and wired an OnClick, nothing else -- no
-- OnEnter/OnLeave at all, and no right-button handling.
--
-- NATIVE UNIT DROPDOWNS. Real vanilla builds one dropdown frame per unit
-- frame, and every native right-click handler just calls
-- `ToggleDropDownMenu(1, nil, <that dropdown>, ...)` -- confirmed in the
-- FrameXML: `PlayerFrame.lua:170`, `TargetFrame.lua:253`,
-- `PetFrame.lua:128`, `PartyMemberFrame.lua:236`. Reusing those frames is
-- what real ElvUI/oUF and `source/UnrealUI` both do, so the menu contents
-- (Set Focus / Trade / Invite / Raid Target / Leave Party / ...) stay
-- native and correct with no menu-building code here at all.
--
-- CONFIRMED WORKING ON UA, live: the pet frame's menu opens
-- and Dismiss works from it. That single data point clears the whole
-- chain this file was flagged as unverified on -- `ToggleDropDownMenu`,
-- the native `*DropDown` globals, `UnitPopup_ShowMenu` and the dropdown
-- frames surviving their hidden parents ALL exist and work on this
-- client. `source/UnrealUI`'s "no compact-DB record for any of these"
-- warning is superseded by evidence.
--
-- NO MENU APPEARING ON THE PLAYER FRAME IS NOT A BUG -- it is vanilla's
-- own rule, and it is worth knowing before anyone debugs it again.
-- `UnitPopup_ShowMenu`
-- (FrameXML/UnitPopup.lua:115-123) ends with:
--     -- If only one menu item (the cancel button) then don't show the menu
--     if ( count < 1 ) then return; end
-- ...where `count` skips CANCEL. The SELF menu is
-- `{LOOT_METHOD, LOOT_THRESHOLD, LOOT_PROMOTE, LEAVE, RESET_INSTANCES,
-- RAID_TARGET_ICON, CANCEL}` and `UnitPopup_HideButtons` hides EVERY one
-- of those when `inParty == 0` (LEAVE at line 339, LOOT_METHOD at 374,
-- and so on). So a SOLO player right-clicking their own frame gets
-- nothing at all, in real vanilla too -- Leave Party is exactly one of
-- the entries that only exists while grouped. Testable only in a party.
--
-- UNIT TYPE, NOT FRAME IDENTITY, PICKS THE MENU: what matters is which
-- kind of unit is targeted, not which frame was clicked. Vanilla already
-- agrees: its own
-- most general handler, `TargetFrameDropDown_Initialize`
-- (FrameXML/TargetFrame.lua:435-455), dispatches on what the unit IS
-- (SELF / PET / PARTY / PLAYER / RAID_TARGET_ICON), not on which frame
-- was clicked. The four native initializers already do the right thing
-- for the units they cover, so they're kept; what was missing is
-- everything they DON'T cover.
--
-- TARGETTARGET AND PETTARGET now get a menu too (they didn't in the first
-- pass). Real 1.12.1 has no `TargetofTargetFrameDropDown`/
-- `PetTargetFrameDropDown` to borrow -- vanilla's ToT frame has no menu
-- at all and there is no pet target frame -- so `ShowGenericUnitMenu`
-- below runs vanilla's own dispatch itself and drives `UnitPopup_ShowMenu`
-- through a spare dropdown frame. Same architecture oUF uses for the
-- units it can't map to a native dropdown.
--
-- The dropdown frames are CHILDREN of the native unit frames, which this
-- module hides (`HideNativePlayerFrame` & co: Hide + SetAlpha(0) +
-- noop'd Show). Proven not to matter by the working pet menu --
-- `ToggleDropDownMenu` shows the separate top-level `DropDownList1`,
-- never the dropdown frame itself.
local UNIT_DROPDOWNS = {
	player = "PlayerFrameDropDown",
	target = "TargetFrameDropDown",
	pet = "PetFrameDropDown",
	party1 = "PartyMemberFrame1DropDown",
	party2 = "PartyMemberFrame2DropDown",
	party3 = "PartyMemberFrame3DropDown",
	party4 = "PartyMemberFrame4DropDown",
}

local unitMenuErrorPrinted = false

-- Vanilla's own dispatch, ported verbatim from
-- `TargetFrameDropDown_Initialize` (FrameXML/TargetFrame.lua:435-455) --
-- including its final `else` branch, where a non-player unit (an NPC, a
-- mob, someone else's pet) gets the RAID_TARGET_ICON marker submenu
-- rather than no menu at all. Every call `pcall`'d: `UnitInParty` in
-- particular has no UA-doc entry, and falling back to the plain PLAYER
-- menu is the right answer if it's missing.
local function GetUnitMenuType(unit)
	local function check(fn, a, b)
		if type(fn) ~= "function" then return false end
		local ok, result = pcall(fn, a, b)
		return ok and result and true or false
	end

	if not check(UnitExists, unit) then return nil end
	if check(UnitIsUnit, unit, "player") then return "SELF" end
	if check(UnitIsUnit, unit, "pet") then return "PET" end
	if check(UnitIsPlayer, unit) then
		if check(UnitInParty, unit) then return "PARTY" end
		return "PLAYER"
	end
	return "RAID_TARGET_ICON"
end

-- For units with no native dropdown frame of their own (targettarget,
-- pettarget). Borrows `FriendsDropDown` as the container the way oUF
-- does: it's a real `UIDropDownMenuTemplate` frame listed in vanilla's
-- own `UnitPopupFrames`, and `FriendsFrame_ShowDropdown`
-- (FrameXML/FriendsFrame.lua:35-42) re-assigns `.initialize` and
-- `.displayMode` every single time before it opens it -- so hijacking it
-- is safe in BOTH directions as long as we do the same, which is what
-- the three assignments below are for. `HideDropDownMenu(1)` first,
-- also copied from that function: without it, re-opening while another
-- unit's menu is already up would toggle the list CLOSED instead
-- (`ToggleDropDownMenu` treats a second call on the same frame as a
-- toggle), which is exactly the trap a single shared container invites.
local function ShowGenericUnitMenu(unit)
	-- No unit there (empty ToT/pettarget slot) is "handled", not "failed" --
	-- returning false here would fire the diagnostic print below for a
	-- perfectly normal right-click on an empty frame.
	local which = GetUnitMenuType(unit)
	if not which then return true end

	local dropdown = _G.FriendsDropDown
	if not dropdown or type(_G.UnitPopup_ShowMenu) ~= "function"
		or type(_G.ToggleDropDownMenu) ~= "function" then
		return false
	end

	dropdown.initialize = function()
		pcall(_G.UnitPopup_ShowMenu, dropdown, which, unit)
	end
	dropdown.displayMode = "MENU"
	dropdown.unit = unit

	if type(_G.HideDropDownMenu) == "function" then
		pcall(_G.HideDropDownMenu, 1)
	end
	return pcall(_G.ToggleDropDownMenu, 1, nil, dropdown, "cursor")
end

function UF:ShowUnitMenu(frame)
	local unit = frame and frame.unit
	if not unit then return end

	local dropdownName = UNIT_DROPDOWNS[unit]
	if not dropdownName then
		if not ShowGenericUnitMenu(unit) and not unitMenuErrorPrinted then
			unitMenuErrorPrinted = true
			E:Print(L["The right-click menu is not available for this frame."])
		end
		return
	end

	local dropdown = _G[dropdownName]
	if not dropdown or type(_G.ToggleDropDownMenu) ~= "function" then
		if not unitMenuErrorPrinted then
			unitMenuErrorPrinted = true
			E:Print(L["The right-click menu is not available for this frame."])
		end
		return
	end

	local ok = pcall(_G.ToggleDropDownMenu, 1, nil, dropdown, "cursor")
	if not ok and not unitMenuErrorPrinted then
		unitMenuErrorPrinted = true
		E:Print(L["The right-click menu is not available for this frame."])
	end
end

-- `GameTooltip:SetUnit(unit)` is documented on UA
-- (source/UnrealAzeroth_LuaAPI/en/widgets/GameTooltip.md), as are
-- `SetOwner` and `FadeOut` -- so unlike the menu above, this half rests on
-- the client's own docs, not on borrowed source. `GameTooltip_SetDefaultAnchor`
-- is a FrameXML global (not a widget method) and therefore NOT covered by
-- those docs: tried first so the user's own interface tooltip-anchor
-- setting is honored, with a plain `SetOwner(..., "ANCHOR_RIGHT")`
-- fallback when it isn't there.
--
-- The `UnitExists` gate matters: without it, hovering a frame whose unit
-- is gone (dead pet, no target) pops an empty tooltip box.
function UF:ShowUnitTooltip(frame)
	local unit = frame and frame.unit
	if not unit or not GameTooltip then return end

	local okExists, exists = pcall(UnitExists, unit)
	if okExists and not exists then
		-- No frame argument on purpose: this hides the tooltip WITHOUT
		-- clearing `elvTooltipActive`, so the refresh loop keeps running
		-- and the tooltip comes back on its own if the unit reappears
		-- while the cursor is still on the frame (a pet being resummoned,
		-- a new target while hovering the ToT frame). Latched, because the
		-- refresh loop would otherwise re-trigger `FadeOut` every 0.25s and
		-- restart the fade forever, leaving the tooltip permanently
		-- half-visible instead of gone.
		if not frame.elvTooltipHidden then
			frame.elvTooltipHidden = true
			UF:HideUnitTooltip()
		end
		return
	end
	frame.elvTooltipHidden = nil

	-- Tooltip visibility (unitFrames modifier, combat). The 0.25s refresh
	-- runs this again, so pressing or releasing the modifier while hovering
	-- shows or hides the tooltip without leaving the frame.
	if E.Tooltip and E.Tooltip:IsSuppressed("unitFrames") then
		if GameTooltip:IsShown() then
			pcall(GameTooltip.Hide, GameTooltip)
		end
		return
	end

	local anchored = false
	if type(_G.GameTooltip_SetDefaultAnchor) == "function" then
		anchored = pcall(_G.GameTooltip_SetDefaultAnchor, GameTooltip, frame)
	end
	if not anchored then
		pcall(GameTooltip.SetOwner, GameTooltip, frame, "ANCHOR_RIGHT")
	end

	if pcall(GameTooltip.SetUnit, GameTooltip, unit) then
		-- An offline party member fills no line (the native frame shows no
		-- tooltip for it either); showing anyway would draw an empty box.
		local okLines, lines = pcall(GameTooltip.NumLines, GameTooltip)
		if okLines and (tonumber(lines) or 0) == 0 then
			pcall(GameTooltip.Hide, GameTooltip)
			return
		end
		pcall(GameTooltip.Show, GameTooltip)
		-- The Tooltip module restyles world units from UPDATE_MOUSEOVER_UNIT,
		-- which does not cover a SetUnit on a frame's own unit token, and the
		-- GameTooltip setters cannot be hooked on UA -- so the rewrite is
		-- called directly after the fill.
		if E.Tooltip then
			pcall(E.Tooltip.UpdateUnitTooltip, E.Tooltip, unit)
		end
	end
end

-- FadeOut first, Hide as the fallback -- matches native `UnitFrame_OnLeave`
-- (FrameXML/UnitFrame.lua) and `source/UnrealUI`'s own note that a bare
-- Hide() makes the tooltip vanish the instant the cursor crosses the edge
-- instead of easing out the way the rest of the UI does.
function UF:HideUnitTooltip(frame)
	if not GameTooltip then return end
	if frame then frame.elvTooltipActive = nil end
	if not pcall(GameTooltip.FadeOut, GameTooltip) then
		pcall(GameTooltip.Hide, GameTooltip)
	end
end

-- Live refresh while the cursor stays on the frame. Native
-- `UnitFrame_OnUpdate` does the same via its own `updateTooltip` counter,
-- and it genuinely matters here: `targettarget`/`pettarget` can change
-- unit WHILE hovered, and any unit can die or go out of range, which
-- would otherwise leave a stale tooltip up. Gated on
-- `frame.elvTooltipActive`, so this costs one float compare per frame per
-- frame-tick when nothing is hovered. Reads `arg1` (the elapsed time)
-- from the global, matching this file's own existing OnUpdate convention
-- (see the castbar tick) rather than a direct handler argument.
local TOOLTIP_UPDATE_INTERVAL = 0.25

-- RENAMED from `EnableUnitClick` -- it now wires the whole
-- mouse surface (target, menu, tooltip), not just the click. Every
-- Construct_*Frame call site updated in the same pass.
function UF:EnableUnitMouse(frame)
	pcall(frame.EnableMouse, frame, true)
	pcall(frame.RegisterForClicks, frame, "LeftButtonUp", "RightButtonUp")

	frame:SetScript("OnClick", function(a, b)
		-- Vanilla script handlers receive the clicked button in the `arg1`
		-- GLOBAL; `source/UnrealUI` reports UA may instead pass it as a
		-- direct argument (their own `ResolveClickButton` accepts either),
		-- so both shapes are read here. `frame` itself is captured by the
		-- closure, so no `this`-wrapping is needed (same reasoning as the
		-- original click-to-target handler).
		local button
		if type(a) == "string" then button = a
		elseif type(b) == "string" then button = b
		elseif type(arg1) == "string" then button = arg1 end

		-- Same order as the native unit frames (PlayerFrame_OnClick,
		-- TargetFrame_OnClick, PetFrame_OnClick, PartyMemberFrame_OnClick):
		-- with a pending spell cursor the right button cancels it and the
		-- left button casts on the unit; an item on the cursor is equipped
		-- (player frame) or dropped on the unit; otherwise left targets and
		-- right opens the menu.
		local targeting = SpellIsTargeting and ElvUI.Compat.bool(SpellIsTargeting())
		if button == "RightButton" then
			if targeting then
				pcall(SpellStopTargeting)
			else
				UF:ShowUnitMenu(frame)
			end
		elseif targeting then
			pcall(SpellTargetUnit, frame.unit)
		elseif CursorHasItem and ElvUI.Compat.bool(CursorHasItem()) then
			if frame.unit == "player" then
				pcall(AutoEquipCursorItem)
			else
				pcall(DropItemOnUnit, frame.unit)
			end
		else
			pcall(TargetUnit, frame.unit)
		end
	end)

	frame:SetScript("OnEnter", function()
		frame.elvTooltipActive = true
		frame.elvTooltipElapsed = 0
		frame.elvTooltipHidden = nil
		UF:ShowUnitTooltip(frame)
	end)

	frame:SetScript("OnLeave", function()
		UF:HideUnitTooltip(frame)
	end)

	frame:SetScript("OnUpdate", function()
		if not frame.elvTooltipActive then return end
		local elapsed = tonumber(arg1) or 0
		frame.elvTooltipElapsed = (frame.elvTooltipElapsed or 0) + elapsed
		if frame.elvTooltipElapsed < TOOLTIP_UPDATE_INTERVAL then return end
		frame.elvTooltipElapsed = 0
		UF:ShowUnitTooltip(frame)
	end)
end

-- Back-compat alias -- kept so nothing outside this module breaks on the
-- rename; new code should call `UF:EnableUnitMouse`.
function UF:EnableUnitClick(frame)
	UF:EnableUnitMouse(frame)
end

-- ---------------------------------------------------------------------
-- Pet Happiness -- HUNTER-pet-only loyalty indicator: only Hunter pets
-- have it, e.g. a Warlock pet doesn't. Checked real ElvUI's own Elements/Happiness.lua first:
-- it uses `HasPetUI()`'s SECOND return value (`isHunterPet`) to gate
-- this exactly -- confirmed on UA too (source/UnrealAzeroth_LuaAPI/en/
-- globals/Pet.md: "The default stable UI treats the second return as
-- isHunterPet", real booleans on this client, not 1/nil). A narrow
-- VERTICAL bar, real ElvUI field names verbatim (`happiness = {enable,
-- autoHide, width}`, default width 10, Settings/Profile.lua:1593) --
-- real ElvUI reflows Health/Power's own width to make room for it
-- (`frame.HAPPINESS_WIDTH`); this project skips that pixel-perfect
-- layout math (matches this project's own established simplification
-- pattern elsewhere, e.g. `orientation` stored-but-not-read) and instead
-- just sticks it out past Health's own left edge.
function UF:Construct_Happiness(frame)
	local bar = ElvUI.Util.CreateStatusBar(frame, {
		orientation = "VERTICAL",
		background = {0.1, 0.1, 0.1, 1},
		texture = GetBarTexture(),
	})
	bar:SetWidth(10)
	local ok, frameLevel = pcall(frame.GetFrameLevel, frame)
	if ok and tonumber(frameLevel) then
		pcall(bar.SetFrameLevel, bar, frameLevel + 2)
	end
	bar:Hide()
	frame.HappinessIndicator = bar
	return bar
end

-- 33/66/100 + red/yellow/green, matching real ElvUI's own
-- HappinessOverride exactly (damagePercentage 75/100/125 ->
-- Unhappy/Content/Happy, the actual vanilla 3-tier system --
-- GetPetHappiness's own docs confirm this shape on UA too). Sized/
-- positioned to Health's own height, stuck out past its left edge (see
-- this section's own header comment for why, vs. real ElvUI's width-
-- reflow).
function UF:UpdateHappiness(frame)
	local bar = frame.HappinessIndicator
	if not bar then return end
	ElvUI.Util.SetStatusBarTexture(bar, GetBarTexture())

	local settings = E.db.unitframe.units[frame.unitDBKey or frame.unit]
	local happinessDB = settings and settings.happiness
	if not happinessDB or not happinessDB.enable then
		bar:Hide()
		return
	end

	local okUI, hasPetUI, isHunterPet = pcall(HasPetUI)
	if not okUI or not hasPetUI or not isHunterPet then
		bar:Hide()
		return
	end

	local okHappy, happinessIndex = pcall(GetPetHappiness)
	if not okHappy or not happinessIndex then
		bar:Hide()
		return
	end

	-- Branches on `happinessIndex` (the FIRST return, 1/2/3 =
	-- unhappy/content/happy), NOT `damagePercentage` (the second):
	-- GetPetHappiness can report 3 (happy) while the bar shows yellow
	-- (content color) if branching on `damagePercentage == 75/125` (real
	-- vanilla's own documented value shape for Unhappy/Happy) -- that
	-- doesn't hold exactly on UA, so if damagePercentage never actually
	-- equals 75 or 125 there, EVERY happiness state silently falls into
	-- the `else` (content/yellow) branch regardless of the pet's real
	-- state. `happinessIndex` itself
	-- is the one value UA's own docs explicitly confirm as 1/2/3
	-- (source/UnrealAzeroth_LuaAPI/en/globals/Pet.md), confirmed directly
	-- by live testing -- branching on that instead is strictly safer, not
	-- a guess.
	local value, r, g, b
	if happinessIndex == 1 then
		value, r, g, b = 33, 0.8, 0.2, 0.1
	elseif happinessIndex == 3 then
		value, r, g, b = 100, 0, 0.8, 0
	else
		value, r, g, b = 66, 1, 1, 0
	end

	bar:SetWidth(happinessDB.width or 10)
	bar:ClearAllPoints()
	bar:SetPoint("TOPRIGHT", frame.Health, "TOPLEFT", -2, 0)
	bar:SetPoint("BOTTOMRIGHT", frame.Health, "BOTTOMLEFT", -2, 0)
	bar:SetMinMaxValues(0, 100)
	bar:SetValue(value)
	ElvUI.Util.SetStatusBarColor(bar, r, g, b)

	if happinessIndex == 3 and happinessDB.autoHide then
		bar:Hide()
	else
		bar:Show()
	end
end

-- ---------------------------------------------------------------------
-- Castbar -- player and target. Real ElvUI's own
-- Elements/Castbar.lua is just the STYLING layer on top of oUF's own
-- `elements/castbar.lua`, which does the actual event-driven tracking --
-- this project has no oUF (see this file's own header comment on why),
-- so the tracking logic below is ported directly from oUF's element
-- instead, as plain functions, the same "keep the proven LOGIC, drop
-- oUF's own metatable/element machinery" approach already used
-- throughout this project.
--
-- The player bar runs on the classic vanilla 1.12.1 SPELLCAST_* events,
-- which only ever describe the PLAYER's own cast (oUF's element registers
-- them for `unit == "player"` only). The target bar has no such event: it
-- polls UF:GetUnitCast (CastTracker.lua), which rebuilds other units' casts
-- from the combat log. Both bars share the styling and time-text helpers
-- below; `bar.unit` selects the settings table.
--
-- IMPORTANT: this project's own AceEvent-3.0 copy does NOT forward
-- event payloads as function arguments (confirmed by reading
-- Libraries/AceEvent-3.0/AceEvent-3.0.lua:119 -- its frame's own OnEvent
-- script calls `events:Fire(event)`, the event NAME only) -- every
-- handler below reads the vanilla `arg1`/`arg2` GLOBALS directly instead
-- (the same convention already established project-wide for raw script
-- handlers, e.g. Chat.lua's wheel-scroll handler) -- these globals are
-- still correctly populated by the client itself before any OnEvent
-- code runs, AceEvent's own indirection doesn't clear them.
--
-- Icon capture: real oUF hooks `UseAction`/`CastSpell`/
-- `UseContainerItem` via `hooksecurefunc` to know which icon to show
-- (SPELLCAST_START itself doesn't say) -- ported verbatim, pcall-wrapped
-- (matches this project's own accepted, if cautious, use of
-- hooksecurefunc elsewhere, e.g. Chat.lua's ChatEdit_* hooks) -- falls
-- back to a generic icon if the hook never fired or isn't available.
--
-- Driven by a shared E:ScheduleRepeatingTimer, NOT castbar:SetScript
-- ("OnUpdate", ...) the way real oUF drives it -- matches this
-- project's own established preference (Cooldowns.lua's own header
-- comment has the full reasoning) for a shared timer over relying on
-- per-frame OnUpdate, which this project has found unreliable on UA
-- elsewhere.
local castbarIconTexture

-- Take the hooked function's REAL arguments as plain Lua parameters:
-- neither a keybind nor a mouse click shows an icon, pointing at both
-- hooks failing uniformly. Re-reading this found TWO separate bugs, not one:
--   1. These functions were reading the vanilla `arg1`/`arg2` GLOBALS
--      (this project's own established `this`/`arg1` convention) --
--      but that convention only applies to SCRIPT HANDLERS
--      (SetScript("OnEvent"/"OnClick"/...)), which real vanilla Lua 5.0
--      doesn't pass real arguments to. `hooksecurefunc`'s own callback
--      is NOT a script handler -- it's a plain Lua function hook, and
--      the ORIGINAL function's arguments ARE passed through as real Lua
--      parameters, same as any normal function call, on both clients.
--      Misapplied that convention somewhere it doesn't belong -- these
--      globals were never populated by a CastSpell/UseAction call at
--      all, so the capture was reading stale/irrelevant leftover data.
--   2. Bare `hooksecurefunc` itself also wasn't firing reliably --
--      matches this project's own already-established finding for
--      HookScript ("no reliably-present bare global HookScript...
--      route through AceHook-3.0's :HookScript instead"), apparently
--      not unique to that one function. Routed through AceHook-3.0's
--      `:SecureHook` instead (UF now mixes in "AceHook-3.0").
local function CaptureCastIcon(id, bookType)
	local ok, texture = pcall(GetSpellTexture, id, bookType)
	if ok and texture then castbarIconTexture = texture end
end

local function CaptureActionIcon(id)
	local ok, texture = pcall(GetActionTexture, id)
	if ok and texture then castbarIconTexture = texture end
end

local function CaptureContainerIcon(id, index)
	local ok, texture = pcall(GetContainerItemInfo, id, index)
	if ok and texture then castbarIconTexture = texture end
end

pcall(function() UF:SecureHook("CastSpell", CaptureCastIcon) end)
pcall(function() UF:SecureHook("UseAction", CaptureActionIcon) end)
pcall(function() UF:SecureHook("UseContainerItem", CaptureContainerIcon) end)

-- Same technique as Units/Player.lua's own HideNativePlayerFrame --
-- real oUF just does `CastingBarFrame.Show = CastingBarFrame.Hide;
-- CastingBarFrame:Hide()`, which this project's own established
-- HideNative*-style pattern already covers more thoroughly (UA's
-- confirmed UnregisterEvent no-op, so nil the OnEvent handler too).
local function HideNativeCastingBarFrame()
	local frame = CastingBarFrame
	if not frame then return end
	pcall(frame.UnregisterAllEvents, frame)
	pcall(frame.SetScript, frame, "OnEvent", nil)
	pcall(frame.Hide, frame)
	frame.Show = E.noop
end

function UF:Construct_Castbar(frame)
	local bar = ElvUI.Util.CreateStatusBar(frame, {
		color = {1, 0.7, 0, 1},
		background = {0.1, 0.1, 0.1, 1},
		texture = GetBarTexture(),
	})
	bar:SetFrameLevel(frame:GetFrameLevel() + 40)
	bar:Hide()

	local icon = bar:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	bar.Icon = icon

	local spark = bar:CreateTexture(nil, "OVERLAY")
	spark:SetBlendMode("ADD")
	spark:SetVertexColor(1, 1, 1)
	bar.Spark = spark

	local text = bar:CreateFontString(nil, "OVERLAY")
	ApplyFont(text)
	text:SetPoint("LEFT", bar, "LEFT", 4, 0)
	text:SetJustifyH("LEFT")
	bar.Text = text

	local time = bar:CreateFontString(nil, "OVERLAY")
	ApplyFont(time)
	time:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	time:SetJustifyH("RIGHT")
	bar.Time = time

	bar.unit = frame.unit
	if frame.unit == "target" then
		self.TargetCastbar = bar
	else
		self.PlayerCastbar = bar
	end
	return bar
end

local function FormatCastbarTime(bar, duration)
	local settings = E.db.unitframe.units[bar.unit].castbar
	local format = settings and settings.format or "REMAINING"

	local text
	if bar.channeling then
		if format == "CURRENT" then
			text = string.format("%.1f", math.abs(duration - bar.max))
		elseif format == "CURRENTMAX" then
			text = string.format("%.1f / %.1f", duration, bar.max)
		else
			text = string.format("%.1f", duration)
		end
	else
		if format == "CURRENT" then
			text = string.format("%.1f", duration)
		elseif format == "CURRENTMAX" then
			text = string.format("%.1f / %.1f", duration, bar.max)
		else
			text = string.format("%.1f", math.abs(duration - bar.max))
		end
	end

	if bar.delay and bar.delay ~= 0 then
		text = text.."|cffff0000 +"..string.format("%.1f", bar.delay).."|r"
	end

	pcall(bar.Time.SetText, bar.Time, text)
end

-- `icon`: the spell's texture when the caller knows it (target casts);
-- the player bar passes nil and uses the texture captured by the hooks.
function UF:ApplyCastbarStyle(bar, name, icon)
	local settings = E.db.unitframe.units[bar.unit].castbar
	pcall(bar.Text.SetText, bar.Text, name)

	if settings.icon then
		pcall(bar.Icon.SetTexture, bar.Icon, icon or castbarIconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
		bar.Icon:Show()
		bar.Icon:ClearAllPoints()
		bar.Icon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
		bar.Icon:SetWidth(bar:GetHeight())
		bar.Icon:SetHeight(bar:GetHeight())
	else
		bar.Icon:Hide()
	end
	if bar.unit == "player" then castbarIconTexture = nil end

	local r, g, b = 1, 0.7, 0
	if E.db.unitframe.colors.castClassColor and UnitIsPlayer(bar.unit) then
		local _, class = UnitClass(bar.unit)
		local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if classColor then r, g, b = classColor.r, classColor.g, classColor.b end
	end
	ElvUI.Util.SetStatusBarColor(bar, r, g, b)
	ElvUI.Util.SetStatusBarTexture(bar, GetBarTexture())

	if settings.spark then
		bar.Spark:Show()
		bar.Spark:SetWidth(20)
		bar.Spark:SetHeight(bar:GetHeight() * 2)
	else
		bar.Spark:Hide()
	end
end

local function CASTBAR_SPELLCAST_START()
	local bar = UF.PlayerCastbar
	if not bar then return end
	local name, endTime = arg1, arg2
	if not name then bar:Hide() return end

	endTime = endTime / 1000
	bar.startTime = GetTime()
	bar.max = endTime
	bar.delay = 0
	bar.casting = true
	bar.channeling = nil
	bar.holdTime = 0

	bar:SetMinMaxValues(0, bar.max)
	bar:SetValue(0)
	UF:ApplyCastbarStyle(bar, name)
	pcall(bar.Time.SetText, bar.Time, "")
	bar:Show()
end

local function CASTBAR_SPELLCAST_CHANNEL_START()
	local bar = UF.PlayerCastbar
	if not bar then return end
	local endTime, name = arg1, arg2
	if not name then return end

	endTime = endTime / 1000
	bar.startTime = GetTime()
	bar.duration = bar.startTime + endTime
	bar.max = endTime
	bar.delay = 0
	bar.channeling = true
	bar.casting = nil
	bar.holdTime = 0

	bar:SetMinMaxValues(0, endTime)
	bar:SetValue(endTime)
	UF:ApplyCastbarStyle(bar, name)
	pcall(bar.Time.SetText, bar.Time, "")
	bar:Show()
end

local function CASTBAR_SPELLCAST_DELAYED()
	local bar = UF.PlayerCastbar
	if not bar or not arg1 or not bar:IsShown() then return end

	local delay = arg1 / 1000
	local duration = GetTime() - bar.startTime
	if duration < 0 then duration = 0 end

	bar.startTime = bar.startTime + delay
	bar.delay = delay
	bar:SetValue(duration)
end

local function CASTBAR_SPELLCAST_CHANNEL_UPDATE()
	local bar = UF.PlayerCastbar
	if not bar or not bar:IsShown() then return end

	local delay = (arg1 or 0) / 1000
	local duration = bar.startTime + (bar.max - GetTime()) - delay
	bar.delay = (bar.delay or 0) - duration
	bar.startTime = bar.startTime - duration
	bar:SetValue(duration)
end

local function CASTBAR_SPELLCAST_STOP()
	local bar = UF.PlayerCastbar
	if not bar then return end
	if bar:IsShown() then bar.casting = nil end
end

local function CASTBAR_SPELLCAST_FAILED()
	local bar = UF.PlayerCastbar
	if not bar or not bar.casting then return end
	pcall(bar.Text.SetText, bar.Text, _G.FAILED or L["Failed"])
	bar.casting = nil
	bar.holdTime = 1
end

local function CASTBAR_SPELLCAST_INTERRUPTED()
	local bar = UF.PlayerCastbar
	if not bar then return end
	pcall(bar.Text.SetText, bar.Text, _G.INTERRUPTED or L["Interrupted"])
	bar.casting = nil
	bar.channeling = nil
	bar.holdTime = 1
end

-- Driven by a REAL `OnUpdate` script, not a shared timer: the NATIVE
-- CastingBarFrame (which real vanilla drives via a true per-frame
-- OnUpdate, `CastingBarFrame_OnUpdate`) animates perfectly smoothly on
-- this client, concrete evidence that OnUpdate itself isn't the
-- unreliable part on UA; a fixed 0.1s timer tick simply can't look as
-- smooth as a true per-frame update REGARDLESS of client, by definition
-- (10 updates/sec vs. every rendered frame). This project's general
-- "prefer a shared timer over OnUpdate" caution (Cooldowns.lua's own
-- header comment) is based on a DIFFERENT finding, about OnUpdate
-- reliability on some other frame shape -- not a blanket rule, and this
-- evidence overrides it specifically here. Matches oUF's OWN original
-- mechanism (Libraries/oUF/elements/castbar.lua's own `onUpdate`,
-- `element:SetScript("OnUpdate", ...)`) -- `elapsed` read from the
-- vanilla `arg1` global (this project's established script-handler
-- convention), not a function parameter.
-- Keeps the castbar on screen while /moveui is unlocked, showing a static
-- full-length preview. WHY THIS EXISTS: the mover drag handle is created
-- as a CHILD of the frame it moves, so a frame that hides itself takes
-- its own handle down with it and becomes unreachable in move mode. The
-- castbar hides itself on EVERY tick while idle (the `else` branches
-- below), so outside of an actual cast it was never visible in /moveui
-- at all -- the same bug class already root-caused and fixed twice in
-- this project (Reputation bar, PetTarget frame; see Core/Movers.lua's
-- own `RegisterMoverStateCallback` comment).
local function PreviewCastbar(bar)
	if not bar then return end

	if E.moversUnlocked then
		if bar.casting or bar.channeling then return end
		pcall(bar.SetMinMaxValues, bar, 0, 1)
		pcall(bar.SetValue, bar, 1)
		if bar.Text then pcall(bar.Text.SetText, bar.Text, _G.SPELLS or L["Castbar"]) end
		if bar.Time then pcall(bar.Time.SetText, bar.Time, "") end
		if bar.Spark then pcall(bar.Spark.Hide, bar.Spark) end
		pcall(bar.SetAlpha, bar, 1)
		pcall(bar.Show, bar)
	elseif not bar.casting and not bar.channeling then
		pcall(bar.Hide, bar)
	end
end

local function ApplyCastbarMoverPreview()
	PreviewCastbar(UF.PlayerCastbar)
	PreviewCastbar(UF.TargetCastbar)
end

local function UpdateCastbarTick(elapsed)
	local bar = UF.PlayerCastbar
	if not bar then return end

	-- While movers are unlocked and nothing is actually being cast, leave
	-- the preview alone -- every branch below ends in `bar:Hide()`, which
	-- is exactly what used to remove the drag handle.
	if E.moversUnlocked and not bar.casting and not bar.channeling then return end

	if bar.casting then
		local duration = GetTime() - bar.startTime
		if duration >= bar.max then
			bar.casting = nil
			bar:Hide()
			return
		end
		bar:SetValue(duration)
		FormatCastbarTime(bar, duration)
		if bar.Spark:IsShown() then
			local pct = duration / bar.max
			if pct > 1 then pct = 1 end
			pcall(bar.Spark.SetPoint, bar.Spark, "CENTER", bar, "LEFT", pct * bar:GetWidth(), 0)
		end
	elseif bar.channeling then
		local duration = bar.startTime + (bar.max - GetTime())
		if duration <= 0 then
			bar.channeling = nil
			bar:Hide()
			return
		end
		bar:SetValue(duration)
		FormatCastbarTime(bar, duration)
		if bar.Spark:IsShown() then
			local pct = duration / bar.max
			if pct > 1 then pct = 1 end
			pcall(bar.Spark.SetPoint, bar.Spark, "CENTER", bar, "LEFT", pct * bar:GetWidth(), 0)
		end
	elseif bar.holdTime and bar.holdTime > 0 then
		bar.holdTime = bar.holdTime - (tonumber(elapsed) or 0.1)
		if bar.holdTime <= 0 then bar:Hide() end
	else
		-- Catch-all: nothing active, nothing holding -- hide. Matches
		-- real oUF's own identical final `else` branch (previously
		-- missing here, live-reported as a stuck-bar bug and already
		-- fixed once this session -- kept intact through this OnUpdate
		-- conversion).
		bar.casting = nil
		bar.channeling = nil
		bar:Hide()
	end
end

-- Called once from Units/Player.lua's own Construct_PlayerFrame, same
-- pattern as every other "one-time setup" call there.
function UF:InitializeCastbar()
	if not E.db.unitframe.units.player.castbar.enable then return end

	HideNativeCastingBarFrame()

	self:RegisterEvent("SPELLCAST_START", CASTBAR_SPELLCAST_START)
	self:RegisterEvent("SPELLCAST_STOP", CASTBAR_SPELLCAST_STOP)
	self:RegisterEvent("SPELLCAST_FAILED", CASTBAR_SPELLCAST_FAILED)
	self:RegisterEvent("SPELLCAST_INTERRUPTED", CASTBAR_SPELLCAST_INTERRUPTED)
	self:RegisterEvent("SPELLCAST_DELAYED", CASTBAR_SPELLCAST_DELAYED)
	self:RegisterEvent("SPELLCAST_CHANNEL_START", CASTBAR_SPELLCAST_CHANNEL_START)
	self:RegisterEvent("SPELLCAST_CHANNEL_UPDATE", CASTBAR_SPELLCAST_CHANNEL_UPDATE)
	self:RegisterEvent("SPELLCAST_CHANNEL_STOP", CASTBAR_SPELLCAST_STOP)

	if self.PlayerCastbar then
		self.PlayerCastbar:SetScript("OnUpdate", function() UpdateCastbarTick(arg1) end)
	end

	-- Fires the instant /moveui toggles, so the bar appears/disappears
	-- immediately rather than on some later tick. Registered here (not in
	-- Construct_Castbar) because the whole castbar is optional -- when
	-- `castbar.enable` is false there is no bar and nothing to preview.
	if E.RegisterMoverStateCallback and not UF.castbarPreviewRegistered then
		UF.castbarPreviewRegistered = true
		E:RegisterMoverStateCallback(ApplyCastbarMoverPreview)
	end
end

-- Target bar. It has no start/stop events of its own: every state change
-- (new cast, cast over, target switched or dead) is read back from
-- UF:GetUnitCast -- on PLAYER_TARGET_CHANGED, on a new combat-log cast under
-- the target's name, and on every frame while the bar is shown.
function UF:UpdateTargetCastbar()
	local bar = self.TargetCastbar
	if not bar then return end

	local spell, startTime, endTime, icon = self:GetUnitCast("target")
	if not spell then
		if bar.casting then
			bar.casting = nil
			bar.spell = nil
			-- Hides the bar, or puts the /moveui preview back.
			PreviewCastbar(bar)
		elseif bar.holdTime and bar.holdTime > 0 and UnitName("target") ~= bar.caster then
			-- The "Interrupted" hold belongs to the previous target.
			bar.holdTime = 0
			PreviewCastbar(bar)
		end
		return
	end

	if bar.spell ~= spell or bar.startTime ~= startTime then
		bar.caster = UnitName("target")
		bar.holdTime = 0
		bar.spell = spell
		bar.startTime = startTime
		bar.max = endTime - startTime
		bar.delay = 0
		bar.casting = true
		bar.channeling = nil
		bar:SetMinMaxValues(0, bar.max)
		bar:SetValue(0)
		self:ApplyCastbarStyle(bar, spell, icon)
		pcall(bar.Time.SetText, bar.Time, "")
		bar:Show()
	end
end

-- Called by CastTracker.lua when the target's cast is broken off. Keeps the
-- bar up with "Interrupted" for the same 1 s hold as the player bar.
function UF:InterruptTargetCastbar()
	local bar = self.TargetCastbar
	if not bar or not bar.casting then return end

	pcall(bar.Text.SetText, bar.Text, _G.INTERRUPTED or L["Interrupted"])
	pcall(bar.Time.SetText, bar.Time, "")
	bar.Spark:Hide()
	bar.casting = nil
	bar.spell = nil
	bar.holdTime = 1
end

local function UpdateTargetCastbarTick()
	local bar = UF.TargetCastbar
	local elapsed = tonumber(arg1) or 0
	UF:UpdateTargetCastbar()

	if bar.holdTime and bar.holdTime > 0 then
		bar.holdTime = bar.holdTime - elapsed
		if bar.holdTime <= 0 then PreviewCastbar(bar) end
		return
	end
	if not bar.casting then return end

	local duration = GetTime() - bar.startTime
	if duration > bar.max then duration = bar.max end
	bar:SetValue(duration)
	FormatCastbarTime(bar, duration)
	if bar.Spark:IsShown() then
		pcall(bar.Spark.SetPoint, bar.Spark, "CENTER", bar, "LEFT", duration / bar.max * bar:GetWidth(), 0)
	end
end

-- Called once from Units/Target.lua's Construct_TargetFrame.
function UF:InitializeTargetCastbar()
	local bar = self.TargetCastbar
	if not bar then return end

	self:InitializeCastTracker()
	bar:SetScript("OnUpdate", UpdateTargetCastbarTick)

	if E.RegisterMoverStateCallback and not UF.castbarPreviewRegistered then
		UF.castbarPreviewRegistered = true
		E:RegisterMoverStateCallback(ApplyCastbarMoverPreview)
	end
end

-- ---------------------------------------------------------------------
-- Information Panel -- a third bar below Health/Power, matching real
-- ElvUI's own field exactly (P.unitframe.units.<unit>.infoPanel =
-- {enable, height, transparent}, source/ElvUI-vanilla/ElvUI/Settings/
-- Profile.lua's own per-unit block). Carries no text of its own in real
-- ElvUI either -- it's a bare colored strip, purely a mounting surface
-- for Custom Text entries (attachTextTo = "InfoPanel"): a strip below the
-- power/mana bar, called the Information Panel.
-- Position is fixed below Health/Power in UpdateFrame's own layout step
-- (not here) -- construction just builds the plain backdrop, matching
-- this project's own ApplyPanelBackdrop-style plain SetBackdrop
-- convention (NOT real ElvUI's E:CreateBackdrop, which this project
-- doesn't have; E:SetTemplate does exist but reads the general backdrop
-- colors, which is what the explicit values below already resolve to).
function UF:Construct_InfoPanel(frame)
	local panel = CreateFrame("Frame", nil, frame)
	local bc = (E.db and E.db.general and E.db.general.backdropcolor) or BACKDROP_COLOR
	local brc = (E.db and E.db.general and E.db.general.bordercolor) or BORDER_COLOR
	pcall(panel.SetBackdrop, panel, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(panel.SetBackdropColor, panel, bc.r or bc[1], bc.g or bc[2], bc.b or bc[3], bc.a or bc[4])
	pcall(panel.SetBackdropBorderColor, panel, brc.r or brc[1], brc.g or brc[2], brc.b or brc[3], brc.a or brc[4])
	panel:Hide()
	return panel
end

-- ---------------------------------------------------------------------
-- Custom Texts -- real ElvUI's own user-extensible text system
-- (Modules/UnitFrames/Elements/CustomText.lua): an arbitrary, user-named
-- LIST of extra FontStrings, each independently positioned/formatted,
-- attachable to Health/Power/InfoPanel/Frame. This is how a real profile
-- puts BOTH a current AND a max value on the same bar (two separate
-- Custom Text entries, e.g. one tagged `[power:current]` anchored LEFT,
-- one tagged `[power:max]` anchored RIGHT) -- the single built-in
-- health/power `text_format` field can only ever show ONE string.
-- `E.db.unitframe.units[dbKey].customTexts` is a plain table KEYED BY
-- NAME (not an array), matching real ElvUI's own schema exactly, each
-- entry: {enable, text_format, font, size, fontOutline, justifyH,
-- xOffset, yOffset, attachTextTo}. Real ElvUI renders through oUF's
-- `frame:Tag()` (the full tag DSL) -- this project has no oUF, so this reuses UnitFrames.lua's own
-- already-built `ApplyTags`/tags-table substitution instead (the SAME
-- `tags` table UpdateFrame already builds for Health/Power/Name text
-- each tick) -- a real but smaller tag vocabulary, documented in the
-- config's own field `desc`, not silently different.
function UF:Construct_CustomTexts(frame)
	frame.customTexts = {}
end

-- `point` -- "Health"/"Power"/"InfoPanel"/"Frame" (real ElvUI's own
-- exact 4 values, `attachToValues` in ElvUI_Config/UnitFrames.lua).
-- Mirrors real ElvUI's own `UF:GetObjectAnchorPoint` exactly: falls back
-- to the frame itself for an unknown/"Frame" point, and to Health if the
-- requested element exists but isn't currently shown (e.g. Power
-- disabled, or InfoPanel disabled) -- avoids anchoring to an invisible
-- element.
local function GetCustomTextAnchor(frame, point)
	local target = frame[point]
	if not target or point == "Frame" then
		return frame
	elseif not target:IsShown() then
		return frame.Health
	end
	return target
end

-- `tags` is the SAME table UpdateFrame already built for Health/Power/
-- Name this tick -- passed in rather than recomputed, so a Custom Text's
-- `[power:current]` etc. always matches what the built-in bars just
-- showed.
function UF:UpdateCustomTexts(frame, tags)
	local dbKey = frame.unitDBKey or frame.unit
	local settings = E.db.unitframe.units[dbKey]
	local customTexts = settings and settings.customTexts
	if not frame.customTexts then return end

	-- Hide/drop any FontString whose entry no longer exists in the
	-- current profile (deleted via config, or a profile switch) -- same
	-- cleanup real ElvUI's own Configure_CustomTexts does first.
	local objectName, object
	for objectName, object in pairs(frame.customTexts) do
		if not customTexts or not customTexts[objectName] then
			object:Hide()
			frame.customTexts[objectName] = nil
		end
	end

	if not customTexts then return end

	for objectName, objectDB in pairs(customTexts) do
		local fontString = frame.customTexts[objectName]
		if not fontString then
			-- Parented to Health's own raised text layer regardless of
			-- WHICH element this text is anchored/positioned to
			-- (Health/Power/InfoPanel/Frame) -- the PARENT only decides
			-- frame-level (z-order), the SetPoint call below decides
			-- POSITION, and those are independent. Same fix as
			-- Construct_StateIcon's own icons: a FontString parented
			-- directly to `frame` renders BEHIND Health/Power (both
			-- explicitly raised to frame's base level + 2), regardless
			-- of draw layer.
			fontString = frame.Health.textLayer:CreateFontString(nil, "OVERLAY")
			frame.customTexts[objectName] = fontString
		end

		if objectDB.enable ~= false then
			pcall(fontString.SetFont, fontString, UnitFrameFont(objectDB.font), objectDB.size or E.db.unitframe.fontSize, ResolveOutline(objectDB.fontOutline or E.db.unitframe.fontOutline))
			pcall(fontString.SetJustifyH, fontString, objectDB.justifyH or "CENTER")

			local anchor = GetCustomTextAnchor(frame, objectDB.attachTextTo or "Health")
			local justify = objectDB.justifyH or "CENTER"
			fontString:ClearAllPoints()
			fontString:SetPoint(justify, anchor, justify, objectDB.xOffset or 0, objectDB.yOffset or 0)

			fontString:SetText(ApplyTags(objectDB.text_format, tags))
			fontString:Show()
		else
			fontString:Hide()
		end
	end
end

-- ---------------------------------------------------------------------
-- Buffs/Debuffs -- shared icon-grid system for both aura types,
-- including buffs on the player's own frame and a proper buff/debuff
-- config section.
--
-- DURATION SOURCES, three tiers, picked automatically per unit/type:
--   1. Player's own buffs AND debuffs: the native `GetPlayerBuff*`
--      family (`GetPlayerBuff(index, "HELPFUL"/"HARMFUL")` ->
--      `GetPlayerBuffTexture`/`Applications`/`TimeLeft`), confirmed via
--      UA's own docs (source/UnrealAzeroth_LuaAPI/en/globals/Buff.md).
--      REAL, exact, second-accurate duration -- no approximation at
--      all. This turns out to cover debuffs too (same function
--      family, `"HARMFUL"` filter), so Player needs neither the pfUI
--      approximation NOR to go without a debuff timer.
--   2. Any OTHER unit's debuffs (Target/TargetTarget/Pet so far): the
--      pfUI/libdebuff-ported approximation (DebuffDurations.lua) --
--      real duration DATA, but an approximated START time (stamped on
--      first observation, not the true application moment). See that
--      file's own header comment for the full reasoning.
--   3. Any OTHER unit's buffs: no duration source exists at all (no
--      per-unit equivalent of GetPlayerBuff, and libdebuff's own table
--      is debuffs-only) -- icon + stack count only, same as the
--      original first-pass Debuffs scope.
-- ---------------------------------------------------------------------
local MAX_AURAS = 32
local AURA_SPACING = 2

-- Appropriate position: buffs sit ABOVE the frame growing up, debuffs BELOW growing
-- down -- the conventional placement for a compact unit frame's aura
-- rows, matching how virtually every unit-frame addon separates the two
-- types, and keeping them from ever overlapping each other.
function UF:Construct_Auras(frame, auraType)
	local container = CreateFrame("Frame", nil, frame)
	container.icons = {}
	container:Hide()
	if auraType == "buff" then
		frame.Buffs = container
	else
		frame.Debuffs = container
	end
	return container
end

-- Tooltip-on-hover -- ported from real oUF's own aura element
-- (Libraries/oUF/elements/auras.lua:80-100), the exact same technique:
-- `GameTooltip:SetPlayerBuff(index)` for the player's own auras (must
-- be this call specifically, not SetUnitBuff/SetUnitDebuff -- confirmed
-- from the reference, not guessed), `SetUnitBuff`/`SetUnitDebuff`
-- otherwise. NOT the "can't hook GameTooltip yet" limitation elsewhere
-- in this project -- that's about intercepting tooltips OTHER code
-- shows; this is our own icon showing its OWN tooltip via the standard
-- OnEnter/OnLeave + GameTooltip:SetOwner pattern, same as everywhere
-- else in WoW's UI. `self.tooltipUnit`/`Index`/`Filter` are set fresh
-- each UpdateAuras call, matching real oUF's own approach of
-- recomputing the tooltip data on demand rather than caching it.
local function AuraIcon_OnEnter(self)
	if not self:IsVisible() or not self.tooltipUnit then return end

	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	if self.tooltipUnit == "player" then
		local ok, buffIndex = pcall(GetPlayerBuff, self.tooltipIndex - 1, self.tooltipFilter)
		if ok and buffIndex and buffIndex >= 0 then
			pcall(GameTooltip.SetPlayerBuff, GameTooltip, buffIndex)
		end
	elseif self.tooltipFilter == "HELPFUL" then
		pcall(GameTooltip.SetUnitBuff, GameTooltip, self.tooltipUnit, self.tooltipIndex)
	else
		pcall(GameTooltip.SetUnitDebuff, GameTooltip, self.tooltipUnit, self.tooltipIndex)
	end
	GameTooltip:Show()
end

local function AuraIcon_OnLeave()
	GameTooltip:Hide()
end

-- Exposed as a UF: method (not local) -- the standalone Modules/Auras/
-- Auras.lua module (real ElvUI's OWN separate player-buff/
-- debuff display, see that file's own header comment) reuses this same
-- pooling/tooltip-wiring code for its own icons rather than duplicating
-- it, instead of building two independent icon systems.
--
-- `cooldownStyle` ("below"/"inside", default "below") -- ONLY matters on
-- first construction (a pooled icon's position is set once and reused).
-- Two different real conventions for two different displays: the
-- standalone Auras.lua module's icons
-- put the countdown BELOW the icon (matches real ElvUI's own
-- Modules/Auras/Auras.lua placement exactly). The per-unit debuff grid (Target/TargetTarget/Pet, THIS
-- module's own UpdateAuras) instead wants it CENTERED INSIDE the icon,
-- like a normal OmniCC-style cooldown swipe overlay -- "mint rendes
-- cd-nel" (like a proper cooldown), matching Cooldowns.lua's own
-- GetOrCreateText/`text:SetPoint("CENTER", cd, "CENTER", 0, 1)`.
function UF:GetOrCreateAuraIcon(container, index, cooldownStyle)
	local icon = container.icons[index]
	if icon then return icon end

	-- A Button, not a plain Frame -- needed for OnEnter/OnLeave to
	-- receive mouse input reliably (matches this project's own
	-- established "frames.movable_drag_requires_button"-style finding
	-- elsewhere, and matches real oUF's own aura buttons too).
	icon = CreateFrame("Button", nil, container)
	pcall(icon.SetBackdrop, icon, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(icon.SetBackdropColor, icon, 0, 0, 0, 1)
	pcall(icon.SetBackdropBorderColor, icon, 0, 0, 0, 1)

	local tex = icon:CreateTexture(nil, "ARTWORK")
	-- Insets past the icon's own border, and crops the native
	-- "spell-book page corner" margin baked into most icon textures --
	-- same 0.08 crop convention used throughout Blizzard's own UI.
	tex:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.texture = tex

	local count = icon:CreateFontString(nil, "OVERLAY")
	count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)
	ApplyFont(count)
	icon.count = count

	-- Duration countdown -- see this function's own header comment for
	-- which style each caller wants and why. "below" callers (Auras.lua)
	-- reserve extra vertical row spacing to leave room for this; "inside"
	-- callers (this module's own UpdateAuras) don't need to, since the
	-- text stays within the icon's own bounds.
	local cooldown = icon:CreateFontString(nil, "OVERLAY")
	if cooldownStyle == "inside" then
		cooldown:SetPoint("CENTER", icon, "CENTER", 0, 1)
	else
		cooldown:SetPoint("TOP", icon, "BOTTOM", 0, -2)
	end
	ApplyFont(cooldown)
	icon.cooldown = cooldown

	pcall(icon.EnableMouse, icon, true)
	-- `this`, not `self` -- vanilla script handlers don't auto-pass the
	-- frame as an argument (see Chat.lua's own wheel-scroll handler and
	-- real ElvUI's Modules/Auras/Auras.lua for the identical pattern).
	icon:SetScript("OnEnter", function() AuraIcon_OnEnter(this) end)
	icon:SetScript("OnLeave", function() AuraIcon_OnLeave(this) end)

	icon:Hide()
	container.icons[index] = icon
	return icon
end

-- Returns texture, count, timeLeft (or nil), hasRealDuration (boolean).
-- `index` is 1-based throughout this module (matches UnitBuff/UnitDebuff's
-- own convention) -- converted to GetPlayerBuff's 0-based index here.
-- Exposed as a UF: method for the same reason as GetOrCreateAuraIcon above.
function UF:GetAuraInfo(unit, auraType, index)
	if unit == "player" then
		local filter = (auraType == "buff") and "HELPFUL" or "HARMFUL"
		local okIdx, buffIndex = pcall(GetPlayerBuff, index - 1, filter)
		if not okIdx or not buffIndex or buffIndex < 0 then return nil end

		local okTex, texture = pcall(GetPlayerBuffTexture, buffIndex)
		if not okTex or not texture then return nil end

		local okApp, count = pcall(GetPlayerBuffApplications, buffIndex)
		local okTime, timeLeft = pcall(GetPlayerBuffTimeLeft, buffIndex)
		timeLeft = (okTime and timeLeft and timeLeft > 0) and timeLeft or nil

		return texture, (okApp and count) or 1, timeLeft, true
	end

	local nativeFn = (auraType == "buff") and UnitBuff or UnitDebuff
	local okTex, texture, count = pcall(nativeFn, unit, index)
	if not okTex or not texture then return nil end
	return texture, count, nil, false
end

-- `dbKey`/`unit` split matches UpdateFrame's own (Party's 4 frames
-- share one settings table but each has its own unit token).
function UF:UpdateAuras(frame, auraType)
	local container = (auraType == "buff") and frame.Buffs or frame.Debuffs
	if not container then return end

	local unit = frame.unit
	local dbKey = frame.unitDBKey or unit
	local settings = E.db.unitframe.units[dbKey]
	local auraSettings = settings and settings[(auraType == "buff") and "buffs" or "debuffs"]

	if not auraSettings or not auraSettings.enable then
		container:Hide()
		return
	end

	-- `sizeOverride`, real ElvUI's own field name. Upstream treats 0 as
	-- "derive from the font size"; there is no such formula here, so 0 falls
	-- back to a fixed 20 -- which is also what the declared default is.
	local size = auraSettings.sizeOverride
	if not size or size <= 0 then size = 20 end
	local perRow = auraSettings.perrow or 8
	if perRow < 1 then perRow = 1 end
	-- `numrows` caps the grid, real ElvUI's own field: with perrow 8 and
	-- numrows 1 at most 8 icons are ever shown, however many the unit has.
	-- 0/nil means "no cap", so an old profile without the field behaves as
	-- before this existed.
	local numRows = auraSettings.numrows or 0
	local maxIcons = (numRows > 0) and (perRow * numRows) or MAX_AURAS
	local minDuration = auraSettings.minDuration or 0
	local maxDuration = auraSettings.maxDuration or 0

	-- TWO PASSES, because sorting needs the whole set before anything is placed:
	-- collect first, then order, then lay out. A single pass could only ever
	-- render in client order.
	local collected = {}
	local i
	for i = 1, MAX_AURAS do
		local texture, count, timeLeft, hasRealDuration = self:GetAuraInfo(unit, auraType, i)
		if not texture then break end

		-- Debuff-only approximated duration (tier 2 above) -- only when
		-- the real API (tier 1, player-only) didn't already answer.
		if not hasRealDuration and auraType == "debuff" then
			local name = self:GetDebuffName(unit, i)
			timeLeft = self:GetDebuffTimeLeft(unit, name)
		end

		-- minDuration/maxDuration (real ElvUI fields, `0` = no filter on
		-- that side) -- only meaningful once there's a timeLeft to
		-- compare; an aura with no known duration always passes
		-- through, matching real ElvUI's own "can't filter what you
		-- can't measure" behavior.
		local passesFilter = true
		if timeLeft then
			if minDuration > 0 and timeLeft < minDuration then passesFilter = false end
			if maxDuration > 0 and timeLeft > maxDuration then passesFilter = false end
		end

		if passesFilter then
			table.insert(collected, {
				index = i, texture = texture, count = count, timeLeft = timeLeft,
			})
		end
	end

	-- `sortMethod`/`sortDirection`, real ElvUI's own fields. Only TIME_REMAINING
	-- is an actual sort here; INDEX means "leave the client's own order alone",
	-- which for DESCENDING is that order reversed. An aura with no measurable
	-- timeLeft always sinks to the end regardless of direction -- the same
	-- "can't sort what you can't measure" rule the duration FILTER above follows,
	-- and the same convention the standalone Auras module uses.
	local ascending = (auraSettings.sortDirection == "ASCENDING")
	if auraSettings.sortMethod == "TIME_REMAINING" then
		table.sort(collected, function(a, b)
			if not a.timeLeft then return false end
			if not b.timeLeft then return true end
			if a.timeLeft == b.timeLeft then return a.index < b.index end
			if ascending then return a.timeLeft < b.timeLeft end
			return a.timeLeft > b.timeLeft
		end)
	elseif not ascending then
		table.sort(collected, function(a, b) return a.index > b.index end)
	end

	local shown = 0
	local total = table.getn(collected)
	for i = 1, total do
		local aura = collected[i]
		local texture, count, timeLeft = aura.texture, aura.count, aura.timeLeft

		if shown < maxIcons then
			shown = shown + 1
			local icon = self:GetOrCreateAuraIcon(container, shown, "inside")
			icon:SetWidth(size)
			icon:SetHeight(size)
			pcall(icon.texture.SetTexture, icon.texture, texture)
			icon.count:SetText((count and count > 1) and tostring(count) or "")

			-- Player's own icons skip the visible countdown text
			-- entirely (user's explicit request: "playerframe-en nem
			-- kell duration, de jo lenne, ha fole menve latnam a
			-- tooltipet is" -- on the player frame duration text isn't
			-- needed, but it'd be good to see it via tooltip on hover)
			-- -- `timeLeft` is still computed/used for min/max duration
			-- filtering above regardless, only the TEXT is suppressed
			-- here. Every other unit keeps the visible text.
			icon.cooldown:SetText((timeLeft and unit ~= "player") and self:FormatDebuffTimeLeft(timeLeft) or "")

			-- `clickThrough`: an icon that ignores the mouse entirely, so a
			-- dense aura grid over a unit frame does not swallow clicks meant
			-- for the frame. Re-applied every pass because icons are pooled
			-- and reused across units with different settings.
			pcall(icon.EnableMouse, icon, not auraSettings.clickThrough)

			icon.tooltipUnit = unit
			icon.tooltipIndex = aura.index
			icon.tooltipFilter = (auraType == "buff") and "HELPFUL" or "HARMFUL"

			local row = math.floor((shown - 1) / perRow)
			local col = (shown - 1) - row * perRow
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", container, "TOPLEFT", col * (size + AURA_SPACING), -row * (size + AURA_SPACING))
			icon:Show()
		end
	end

	local j
	for j = shown + 1, table.getn(container.icons) do
		container.icons[j]:Hide()
	end

	if shown > 0 then
		local rows = math.floor((shown - 1) / perRow) + 1
		local cols = (shown < perRow) and shown or perRow
		container:SetWidth(cols * size + (cols - 1) * AURA_SPACING)
		container:SetHeight(rows * size + (rows - 1) * AURA_SPACING)

		container:ClearAllPoints()
		local xOffset = auraSettings.xOffset or 0
		local yOffset = auraSettings.yOffset or 0

		-- `attachTo` + `anchorPoint`, real ElvUI's own two aura-position fields,
		-- replacing what used to be a hardcoded pair (buffs above the frame,
		-- debuffs below it).
		--
		-- `anchorPoint` names the point on the ATTACH-TO frame; the container
		-- attaches by the INVERSE point (E.InversePoints, Core/Util.lua), which
		-- is what makes the grid grow AWAY from what it hangs off. So
		-- anchorPoint = "TOPLEFT" reproduces the old buff behaviour exactly
		-- (container BOTTOMLEFT -> frame TOPLEFT) and "BOTTOMLEFT" the old
		-- debuff one.
		--
		-- BUFFS/DEBUFFS mean "attach to the OTHER aura container" (upstream's
		-- default for the player's buffs, so they stack on top of the debuffs).
		-- That target is only usable while it is actually shown and sized: an
		-- empty container is hidden and zero-height, and anchoring to it would
		-- park the grid on top of the frame. Falls back to the frame in that
		-- case -- upstream has the same problem and solves it with a permanently
		-- sized anchor frame, which is more machinery than this needs.
		--
		-- Consequence worth knowing: the two containers can depend on each other
		-- in EITHER direction (upstream's own defaults have player buffs on
		-- DEBUFFS and target debuffs on BUFFS), so no single update order
		-- satisfies both. The dependent side therefore lands on the frame for one
		-- 0.2s poll after it first appears, then settles onto the other container
		-- and stays there.
		local anchorPoint = auraSettings.anchorPoint or ((auraType == "buff") and "TOPLEFT" or "BOTTOMLEFT")
		local containerPoint = E.InversePoints[anchorPoint] or "BOTTOMLEFT"

		local parent = frame
		local attachTo = auraSettings.attachTo
		if attachTo == "HEALTH" and frame.Health then
			parent = frame.Health
		elseif attachTo == "POWER" and frame.Power then
			parent = frame.Power
		elseif attachTo == "BUFFS" and frame.Buffs and frame.Buffs:IsShown() then
			parent = frame.Buffs
		elseif attachTo == "DEBUFFS" and frame.Debuffs and frame.Debuffs:IsShown() then
			parent = frame.Debuffs
		end

		-- The 4px gap is kept, and now follows the anchor: it pushes the grid
		-- away from the parent's edge whichever side that edge is on.
		local gap = 4
		local gapX, gapY = 0, 0
		if string.find(anchorPoint, "TOP") then
			gapY = gap
		elseif string.find(anchorPoint, "BOTTOM") then
			gapY = -gap
		end
		if anchorPoint == "LEFT" then
			gapX = -gap
		elseif anchorPoint == "RIGHT" then
			gapX = gap
		end

		container:SetPoint(containerPoint, parent, anchorPoint, xOffset + gapX, yOffset + gapY)
		container:Show()
	else
		container:Hide()
	end
end

-- ---------------------------------------------------------------------
-- Per-unit dispatch -- mirrors oUF's own RegisterStyle/SetActiveStyle/
-- Spawn shape in spirit, matching real ElvUI's own approach, just
-- without oUF underneath: a unit
-- file calls UF:RegisterUnit(id, constructFunc), and UF:SpawnUnit(id)
-- calls it once and registers the periodic update.
-- ---------------------------------------------------------------------
UF.UnitConstructors = UF.UnitConstructors or {}
UF.Frames = UF.Frames or {}

function UF:RegisterUnit(id, constructFunc)
	self.UnitConstructors[id] = constructFunc
end

function UF:SpawnUnit(id)
	local constructFunc = self.UnitConstructors[id]
	if not constructFunc then return nil end

	local frame = constructFunc(self)
	if not frame then return nil end

	ApplyPanelBackdrop(frame)
	self.Frames[id] = frame
	return frame
end

-- ---------------------------------------------------------------------
-- Update -- reads live unit data, resolves colors/text/layout from
-- E.db.unitframe.*, and pushes it all onto a frame's bars/text/icons.
-- Driven by a shared periodic poll (matches this project's established
-- preference for E:ScheduleRepeatingTimer over relying solely on events).
-- Events are registered ONCE and never unregistered (UnregisterEvent/
-- UnregisterAllEvents don't work on UA) -- no separate enable check needed in UpdateFrame itself:
-- only a unit whose own `enable` was true at Initialize time ever gets
-- spawned into `self.Frames` to begin with, so UpdateAll never iterates
-- a disabled unit's frame in the first place.
-- ---------------------------------------------------------------------
local NUMERIC_POWER_TOKENS = {[0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY"}
local RESTING_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
local COMBAT_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"

local function ClassColor(unit)
	local ok, _, class = pcall(UnitClass, unit)
	if ok and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local c = RAID_CLASS_COLORS[class]
		return c.r, c.g, c.b
	end
	return 0.6, 0.6, 0.6
end

-- UnitReaction's 1-8 scale collapsed to real ElvUI's own 3-bucket
-- {BAD,NEUTRAL,GOOD} reaction color table.
local REACTION_KEYS = {[1] = "BAD", [2] = "BAD", [3] = "BAD", [4] = "NEUTRAL", [5] = "GOOD", [6] = "GOOD", [7] = "GOOD", [8] = "GOOD"}

local function ReactionColor(unit)
	local ok, reaction = pcall(UnitReaction, unit, "player")
	local key = (ok and reaction and REACTION_KEYS[reaction]) or "NEUTRAL"
	local c = E.db.unitframe.colors.reaction[key]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

-- Added for Target: the Player-only version of this
-- function just called ClassColor unconditionally, correct only because
-- UnitIsPlayer("player") is always true. Generalized now that a second
-- unit exists -- matches real oUF's own colorClass+colorReaction combo
-- (Elements/Health.lua's Configure_HealthBar): a player unit is class-
-- colored, anything else (an NPC target) is reaction-colored.
-- `forceReaction` mirrors real ElvUI's `colors.forcehealthreaction` --
-- when true, even a player unit gets reaction-colored instead.
local function UnitColor(unit, forceReaction)
	local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
	if not forceReaction and okPlayer and isPlayer then
		return ClassColor(unit)
	end
	return ReactionColor(unit)
end

local function PowerToken(unit)
	local ok, token = pcall(UnitPowerType, unit)
	if ok and type(token) == "number" then
		return NUMERIC_POWER_TOKENS[token] or "MANA"
	end
	ok, token = pcall(UnitManaType, unit)
	if ok and type(token) == "string" then
		return string.upper(token)
	end
	return "MANA"
end

-- Real ElvUI's own health/power bar colors (Configure_HealthBar/
-- PostUpdateHealth, Elements/Health.lua) minus the `isForced` test-mode
-- branch (a debug feature, not needed here). Generalized for
-- Target (reads `E.db.unitframe.units[unit]`, not a hardcoded
-- `.player`, and colors non-player units by reaction via `UnitColor`
-- instead of always assuming class color applies).
--
-- BUG FIXED -- symptom: grey at full health, yellow otherwise. In the
-- (default!) case of
-- `healthclass=false, colorhealthbyvalue=true`, this used to gradient red -> yellow
-- -> `colors.health` (the FLAT gray fallback color) -- conflating two
-- separate real-ElvUI branches (oUF's own standalone "smooth" percent
-- gradient, which ends in GREEN and has nothing to do with
-- `colors.health`, vs. the flat `colorHealth` single-color case, which
-- uses `colors.health` but has NO gradient at all). Fixed by keeping
-- those two cases genuinely separate below.
-- `dbKey` defaults to `unit` (correct for every unit so far: Player,
-- Target, Pet, ...) but Party is the first case where they genuinely
-- differ -- four frames (`party1`..`party4`, distinct unit tokens, so
-- each reads its own live unit data) all sharing ONE settings table
-- (`E.db.unitframe.units.party`, matching real ElvUI's own schema:
-- party members are configured uniformly, not per-slot).
--
-- BUG FIXED: class color used to also dim toward red as
-- health dropped whenever `colorhealthbyvalue` was ALSO on (true by
-- default) -- a literal reading of Elements/Health.lua's own
-- `PostUpdateHealth` combo condition. On an actual real ElvUI
-- client, with matching settings, class color stays FLAT regardless of
-- health -- direct observation of a live client outweighs one static
-- source snapshot (possibly a different version, or a subtlety missed
-- reading it). Simplified: class/reaction color is now ALWAYS flat,
-- never gradient-dimmed -- `colorhealthbyvalue`'s gradient only applies
-- in the non-class branch now.
local function ResolveHealthColor(unit, percent, isDead, dbKey, isOffline)
	local colors = E.db.unitframe.colors
	local settings = E.db.unitframe.units[dbKey or unit]
	local override = settings.colorOverride

	local useClass, useGradient
	if override == "FORCE_ON" then
		useClass = true
	elseif override == "FORCE_OFF" then
		useGradient = colors.colorhealthbyvalue
	elseif colors.healthclass then
		useClass = true
	else
		useGradient = colors.colorhealthbyvalue
	end

	local r, g, b
	if useClass then
		r, g, b = UnitColor(unit, colors.forcehealthreaction)
	elseif useGradient then
		-- oUF's own standard percent-based "smooth" gradient (red ->
		-- yellow-brown -> green) -- same 3 stops as the `healthcolor`
		-- text tag below, deliberately NOT involving `colors.health`.
		r, g, b = E:ColorGradient(percent, 0.69, 0.31, 0.31, 0.65, 0.63, 0.35, 0.33, 0.59, 0.33)
	else
		local c = colors.health
		r, g, b = c.r, c.g, c.b
	end

	if isOffline then
		local c = colors.disconnected
		r, g, b = c.r, c.g, c.b
	elseif isDead then
		r, g, b = DEAD_COLOR[1], DEAD_COLOR[2], DEAD_COLOR[3]
	end

	local bgR, bgG, bgB
	if colors.useDeadBackdrop and isDead then
		local c = colors.health_backdrop_dead
		bgR, bgG, bgB = c.r, c.g, c.b
	elseif colors.customhealthbackdrop then
		local c = colors.health_backdrop
		bgR, bgG, bgB = c.r, c.g, c.b
	end

	return r, g, b, bgR, bgG, bgB
end

-- Anchors `element` to its own reference frame from a position/xOffset/
-- yOffset triplet -- shared by health/power/name text.
local function ApplyTextPosition(element, reference, position, xOffset, yOffset)
	element:ClearAllPoints()
	element:SetPoint(position or "CENTER", reference, position or "CENTER", xOffset or 0, yOffset or 0)
end

-- `attachTextTo`, real ElvUI's own field: which element a text sits on, rather
-- than always its own bar. Upstream's value set and its default -- "Health" for
-- every text, including the POWER one, because a thin power bar rarely has room
-- for a number.
--
-- nil means Health too: upstream declares the field on some units and not
-- others (player/target/party and targettarget's name have it; pet, pettarget
-- and the rest do not), so nil has to mean the same thing as the declared
-- default, not "no attachment".
--
-- A requested target that does not exist on this frame falls back to the frame
-- itself -- InfoPanel in particular is optional per unit.
local function ResolveTextAnchor(frame, attachTextTo)
	if attachTextTo == "Power" then
		return frame.Power or frame
	elseif attachTextTo == "InfoPanel" then
		return frame.InfoPanel or frame
	elseif attachTextTo == "Frame" then
		return frame
	end
	return frame.Health or frame
end

-- `texture` / `customTexture`, real ElvUI's own pair for the state icons. Only
-- DEFAULT and CUSTOM are offered: upstream's other two values (RESTING,
-- RESTING1) name ITS OWN bundled artwork, which this project does not ship, and
-- a value that silently resolves to nothing is worse than an absent one.
--
-- CUSTOM with an empty path falls back to DEFAULT rather than blanking the icon.
-- Returns the path plus whether the DEFAULT sprite-sheet TexCoord still applies
-- -- a custom file is a whole image, not a corner of the native sheet.
local function ResolveStateIconTexture(settings, defaultTexture)
	if settings.texture == "CUSTOM" then
		local path = settings.customTexture
		if path and path ~= "" then
			return path, false
		end
	end
	return defaultTexture, true
end

local function UpdateStateIcon(icon, shown, settings, anchor)
	if not shown or not settings.enable then
		icon:Hide()
		return
	end

	if settings.defaultColor then
		icon:SetVertexColor(1, 1, 1, 1)
		pcall(icon.SetDesaturated, icon, false)
	else
		local c = settings.color
		icon:SetVertexColor(c.r, c.g, c.b, c.a or 1)
		pcall(icon.SetDesaturated, icon, true)
	end

	icon:SetWidth(settings.size)
	icon:SetHeight(settings.size)
	icon:ClearAllPoints()
	icon:SetPoint("CENTER", anchor, settings.anchorPoint, settings.xOffset, settings.yOffset)
	icon:Show()
end

-- Raid target mark: real ElvUI's RaidTargetIndicator element, `raidicon`
-- settings, on ElvUI's own raidicons texture cropped with the shared icon-sheet
-- grid (Util.RAID_TARGET_COORDS). Refreshed by the unit frame poll rather than
-- RAID_TARGET_UPDATE: UA's API documentation lists no events. Placement is
-- real ElvUI's Configure_RaidIcon: `attachTo` is both the icon's own point and
-- the point on the element `attachToObject` names.
local RAID_ICON_TEXTURE = "Interface\\AddOns\\ElvUI\\Media\\Textures\\raidicons"

local function UpdateRaidIcon(frame, unit, settings)
	local icon = frame.RaidTargetIndicator
	local okIndex, index = pcall(GetRaidTargetIndex, unit)
	local coords = okIndex and index and ElvUI.Util.RAID_TARGET_COORDS[index]
	if not settings.enable or not coords then
		icon:Hide()
		return
	end

	icon:SetTexture(RAID_ICON_TEXTURE)
	icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	icon:SetWidth(settings.size)
	icon:SetHeight(settings.size)
	icon:ClearAllPoints()
	icon:SetPoint(settings.attachTo, GetCustomTextAnchor(frame, settings.attachToObject), settings.attachTo, settings.xOffset, settings.yOffset)
	icon:Show()
end

-- Incoming resurrection: real ElvUI's ResurrectIndicator element,
-- `resurrectIcon` settings, placed like the raid icon. The client has no
-- UnitHasIncomingResurrection, so the source is LibHealComm-1.0: a resurrection
-- cast by anyone running HealComm (the player's own included) is recorded by
-- target name until it is cancelled, the target's health changes, or 70 s pass.
-- A method rather than a file local, so UF:UpdateFrame gains no upvalue.
local HealComm = LibStub("LibHealComm-1.0", true)
local RESURRECT_TEXTURE = "Interface\\AddOns\\ElvUI\\Media\\Textures\\Raid-Icon-Rez"

function UF:UpdateResurrectIcon(frame, unit, settings)
	local icon = frame.ResurrectIndicator
	local name = UnitName(unit)
	if not settings.enable or not HealComm or not name or not HealComm:UnitisResurrecting(name) then
		icon:Hide()
		return
	end

	icon:SetTexture(RESURRECT_TEXTURE)
	icon:SetWidth(settings.size)
	icon:SetHeight(settings.size)
	icon:ClearAllPoints()
	icon:SetPoint(settings.attachTo, GetCustomTextAnchor(frame, settings.attachToObject), settings.attachTo, settings.xOffset, settings.yOffset)
	icon:Show()
end

function UF:UpdateFrame(frame)
	local unit = frame.unit
	if not unit then return end

	-- `frame.unitDBKey` lets several frames share one settings table
	-- (Party's own 4 member frames) -- see ResolveHealthColor's own
	-- comment. Defaults to `unit` for every other frame, unchanged.
	local dbKey = frame.unitDBKey or unit
	local settings = E.db.unitframe.units[dbKey]

	-- Stays shown while movers are unlocked EVEN IF the unit doesn't
	-- exist right now: without this, a frame like PetTarget can't be
	-- found or positioned in moveui at all, since it almost never has a
	-- live unit to show. Root cause: the mover handle (Core/Movers.lua's own
	-- CreateHandle) is parented AS A CHILD of this very frame -- when
	-- `frame:Hide()` ran here (unconditionally, whenever UnitExists was
	-- false -- true for PetTarget almost all the time, since it needs an
	-- active pet WITH a target, the rarest of every unit this project
	-- builds), the handle had no chance to render regardless of its own
	-- `:Show()` call. Every unit-existence-gated frame (Target/
	-- TargetTarget/Pet/PetTarget/Party) had this same latent bug -- most
	-- just aren't AS hard to get a live unit for, so it went unnoticed
	-- until PetTarget's specifically-rare precondition surfaced it.
	-- Matches real ElvUI's own "stay visible for positioning while
	-- unlocked" behavior in its own mover/test mode.
	local okExists, exists = pcall(UnitExists, unit)
	if (not okExists or not exists) and not E.moversUnlocked then
		frame:Hide()
		return
	end
	frame:Show()

	-- Portrait layout and content, per client (PortraitUA.lua /
	-- PortraitLegacy.lua). Returns the width the bars leave free on the
	-- left. Guarded so a portrait file that failed to load costs only the
	-- portrait, not the whole frame update.
	local portraitWidth = 0
	if self.Update_Portrait then
		portraitWidth = self:Update_Portrait(frame, settings, unit) or 0
	end

	local barLeft = INSET + (portraitWidth > 0 and (portraitWidth + INSET) or 0)
	local barWidth = frame:GetWidth() - barLeft - INSET

	-- Bar HEIGHTS are re-derived here, with the same formula the unit's own
	-- Construct_* function uses (Units/Player.lua and friends: health takes the
	-- whole frame height, minus the power bar and the 1px gap when power is on).
	-- Recomputing it on every pass -- exactly as the widths above already were
	-- -- is what makes `height` and `power.height` live settings instead of
	-- construction-time-only ones; before this they were set once by
	-- Construct_HealthBar/Construct_PowerBar and never touched again.
	local healthHeight = settings.height
	if settings.power and settings.power.enable then
		healthHeight = settings.height - settings.power.height - 1
	end

	frame.Health:ClearAllPoints()
	frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", barLeft, -INSET)
	frame.Health:SetWidth(barWidth)
	frame.Health:SetHeight(healthHeight)

	-- `bgUseBarTexture`, real ElvUI's own field: the bar's BACKGROUND uses the
	-- statusbar texture instead of the flat WHITE8x8 it is built with
	-- (Util.CreateStatusBar). Upstream declares no default for it per unit, so
	-- nil/false means "flat", which is what this project has always drawn.
	-- Waived in scripts/config-exceptions.lua's `reads` table.
	local bgTex = settings.health and settings.health.bgUseBarTexture
	local bgTexturePath = bgTex and GetBarTexture() or "Interface\\Buttons\\WHITE8x8"
	if frame.Health.barBgTexture then
		pcall(frame.Health.barBgTexture.SetTexture, frame.Health.barBgTexture, bgTexturePath)
	end

	if frame.Power then
		frame.Power:ClearAllPoints()
		frame.Power:SetPoint("TOPLEFT", frame.Health, "BOTTOMLEFT", 0, -1)
		frame.Power:SetWidth(barWidth)
		frame.Power:SetHeight(settings.power.height)
	end

	-- Estimated absolute values for hostile units (LibMobHealth-4.0).
	local okHealth, health, healthMax = pcall(ElvUI.Util.UnitHealth, unit)
	health = (okHealth and tonumber(health)) or 0
	healthMax = (okHealth and tonumber(healthMax)) or 0
	-- A player who logged off: real ElvUI (oUF's colorDisconnected) draws a
	-- full bar in colors.disconnected and "Offline" as the health text. Asked
	-- for players only, so an NPC can never read as offline.
	local offline = false
	if UnitIsConnected and ElvUI.Compat.bool(UnitIsPlayer(unit)) then
		local okConnected, connected = pcall(UnitIsConnected, unit)
		offline = okConnected and not ElvUI.Compat.bool(connected)
	end
	if offline then health = healthMax end

	local healthPercent = (healthMax > 0) and (health / healthMax) or 0

	frame.Health:SetMinMaxValues(0, healthMax > 0 and healthMax or 1)
	frame.Health:SetValue(health)

	local okDead, isDead = pcall(UnitIsDead, unit)
	local okGhost, isGhost = pcall(UnitIsGhost, unit)
	local dead = (okDead and isDead) or (okGhost and isGhost)

	local healthAlpha = E.db.unitframe.colors.transparentHealth and TRANSPARENT_ALPHA or 1
	local r, g, b, bgR, bgG, bgB = ResolveHealthColor(unit, healthPercent, dead, dbKey, offline)
	ElvUI.Util.SetStatusBarColor(frame.Health, r, g, b, healthAlpha)
	-- Live-reapplied every tick, same as color above -- cheap (one
	-- SetTexture call) and lets the config dropdown take effect
	-- immediately without a /reload, matching this project's established
	-- "just re-apply every poll" preference over precise change-detection.
	ElvUI.Util.SetStatusBarTexture(frame.Health, GetBarTexture())
	if bgR then
		ElvUI.Util.SetStatusBarBackgroundColor(frame.Health, bgR, bgG, bgB, healthAlpha)
	else
		ElvUI.Util.SetStatusBarBackgroundColor(frame.Health, HEALTH_BG_COLOR[1], HEALTH_BG_COLOR[2], HEALTH_BG_COLOR[3], healthAlpha)
	end
	-- Incoming-heal segment ahead of the health fill (HealPrediction.lua).
	if self.UpdateHealPrediction then
		pcall(self.UpdateHealPrediction, self, frame, unit, dbKey, health, healthMax, dead or offline, GetBarTexture())
	end
	-- The overlay portrait mirrors this bar's state above the portrait
	-- (PortraitUA.lua / PortraitLegacy.lua).
	if self.PostUpdateHealth_Portrait then
		self:PostUpdateHealth_Portrait(frame, bgR or HEALTH_BG_COLOR[1], bgG or HEALTH_BG_COLOR[2],
			bgB or HEALTH_BG_COLOR[3], healthAlpha, bgTexturePath, r, g, b, GetBarTexture())
	end

	local power, powerMax, powerToken = 0, 0, "MANA"
	if frame.Power then
		local okPower, powerVal = pcall(UnitMana, unit)
		local okPowerMax, powerMaxVal = pcall(UnitManaMax, unit)
		power = (okPower and tonumber(powerVal)) or 0
		powerMax = (okPowerMax and tonumber(powerMaxVal)) or 0
		powerToken = PowerToken(unit)

		frame.Power:SetMinMaxValues(0, powerMax > 0 and powerMax or 1)
		frame.Power:SetValue(power)

		local powerAlpha = E.db.unitframe.colors.transparentPower and TRANSPARENT_ALPHA or 1
		local powerColors = E.db.unitframe.colors.power
		local pc = powerColors[powerToken] or powerColors.MANA
		if E.db.unitframe.colors.powerclass then
			local cr, cg, cb = UnitColor(unit)
			ElvUI.Util.SetStatusBarColor(frame.Power, cr, cg, cb, powerAlpha)
		else
			ElvUI.Util.SetStatusBarColor(frame.Power, pc.r, pc.g, pc.b, powerAlpha)
		end
		ElvUI.Util.SetStatusBarBackgroundColor(frame.Power, POWER_BG_COLOR[1], POWER_BG_COLOR[2], POWER_BG_COLOR[3], powerAlpha)
		ElvUI.Util.SetStatusBarTexture(frame.Power, GetBarTexture())
	end

	-- Text -- tag substitution (ApplyTags above), a small subset of real
	-- ElvUI's own tag DSL. See this file's header comment for the exact
	-- list.
	local tags = {}
	if offline then
		tags["health:current"] = L["Offline"]
		tags["health:current-percent"] = L["Offline"]
		tags["health:percent"] = L["Offline"]
	elseif dead then
		local statusText = (okGhost and isGhost) and L["Ghost"] or L["Dead"]
		tags["health:current"] = statusText
		tags["health:current-percent"] = statusText
		tags["health:percent"] = statusText
	else
		-- `E:ShortValue` (Core/Util.lua), not a bare "%d": the profile decides
		-- whether 1700 reads as "1700" or "1.7K", via
		-- E.db.general.numberPrefixStyle / decimalLength.
		tags["health:current"] = E:ShortValue(health)
		tags["health:current-percent"] = string.format("%s - %.1f%%", E:ShortValue(health), healthPercent * 100)
		tags["health:percent"] = string.format("%.1f%%", healthPercent * 100)
	end
	local hr, hg, hb = E:ColorGradient(healthPercent, 0.69, 0.31, 0.31, 0.65, 0.63, 0.35, 0.33, 0.59, 0.33)
	tags["healthcolor"] = E:RGBToHex(hr, hg, hb)
	-- `health:max`/`power:max`: needed for Custom Text, since a real
	-- profile can put CURRENT and MAX as two SEPARATE text elements on
	-- the same bar (e.g. power showing "183" left/max right) -- the
	-- single built-in health/power `text_format` can't do that alone,
	-- but two Custom Text entries each using one of these tags can.
	tags["health:max"] = E:ShortValue(healthMax)
	tags["power:current"] = E:ShortValue(power)
	tags["power:max"] = E:ShortValue(powerMax)
	tags["power:percent"] = string.format("%.1f%%", (powerMax > 0) and (power / powerMax * 100) or 0)
	local powerColors = E.db.unitframe.colors.power
	local pcTag = powerColors[powerToken] or powerColors.MANA
	tags["powercolor"] = E:RGBToHex(pcTag.r, pcTag.g, pcTag.b)
	local okName, name = pcall(UnitName, unit)
	tags["name"] = (okName and name) or unit
	local okLevel, level = pcall(UnitLevel, unit)
	tags["level"] = (okLevel and level and level > 0) and tostring(level) or "??"

	if settings.health then
		frame.Health.text:SetText(ApplyTags(settings.health.text_format, tags))
		ApplyTextPosition(frame.Health.text, ResolveTextAnchor(frame, settings.health.attachTextTo), settings.health.position, settings.health.xOffset, settings.health.yOffset)
	end
	if frame.Power and settings.power then
		frame.Power.text:SetText(ApplyTags(settings.power.text_format, tags))
		ApplyTextPosition(frame.Power.text, ResolveTextAnchor(frame, settings.power.attachTextTo), settings.power.position, settings.power.xOffset, settings.power.yOffset)
	end
	if frame.Name and settings.name then
		frame.Name:SetText(ApplyTags(settings.name.text_format, tags))
		ApplyTextPosition(frame.Name, ResolveTextAnchor(frame, settings.name.attachTextTo), settings.name.position, settings.name.xOffset, settings.name.yOffset)
	end

	-- Information Panel -- a bare colored strip below Health/Power (see
	-- Construct_InfoPanel's own comment). Anchored below Power's bottom
	-- edge when Power is enabled, otherwise below Health's -- matches
	-- real ElvUI's own equivalent fallback (its Configure_InfoPanel
	-- anchors to Power's backdrop only when a non-detached/non-inset
	-- power bar is actually in use, Health's otherwise). Extends BELOW
	-- the frame's own configured height rather than being counted
	-- within it, same as real ElvUI.
	if frame.InfoPanel then
		local infoDB = settings.infoPanel
		if infoDB and infoDB.enable then
			local aboveElement = (frame.Power and settings.power and settings.power.enable) and frame.Power or frame.Health
			frame.InfoPanel:ClearAllPoints()
			frame.InfoPanel:SetPoint("TOPLEFT", aboveElement, "BOTTOMLEFT", 0, -1)
			frame.InfoPanel:SetPoint("TOPRIGHT", aboveElement, "BOTTOMRIGHT", 0, -1)
			frame.InfoPanel:SetHeight(infoDB.height or 20)
			pcall(frame.InfoPanel.SetBackdropColor, frame.InfoPanel,
				BACKDROP_COLOR[1], BACKDROP_COLOR[2], BACKDROP_COLOR[3], infoDB.transparent and 0 or BACKDROP_COLOR[4])
			frame.InfoPanel:Show()
		else
			frame.InfoPanel:Hide()
		end
	end

	-- Custom Texts -- see Construct_CustomTexts' own comment. Reuses the
	-- SAME `tags` table just built above for Health/Power/Name, so a
	-- Custom Text's own tags always match this tick's values.
	self:UpdateCustomTexts(frame, tags)

	-- Pet Happiness -- see Construct_Happiness's own comment. Only Pet
	-- ever builds frame.HappinessIndicator, so this is naturally a no-op
	-- for every other unit, same gating pattern as RestingIndicator below.
	self:UpdateHappiness(frame)

	-- Resting/combat state icons. RestIcon is PLAYER-ONLY -- `IsResting()`
	-- takes no unit argument, it's inherently about the player character
	-- specifically (an inn/city rest state), there's no equivalent
	-- concept for an arbitrary unit like Target: a rest icon on a target
	-- frame would be nonsensical. CombatIcon, unlike RestIcon, generalizes for
	-- real (`UnitAffectingCombat` takes any unit token, so it can
	-- meaningfully answer "is THIS unit in combat" instead of always
	-- being about the player) -- fixed to read `frame.unit` instead of
	-- a hardcoded "player" (a no-op change for Player itself, a real
	-- fix for Target). `frame.RestingIndicator` is simply never built
	-- for Target now (see Units/Target.lua), so this block naturally
	-- skips it there via the existing nil guard.
	if frame.RestingIndicator and settings.RestIcon then
		local okResting, resting = pcall(IsResting)
		UpdateStateIcon(frame.RestingIndicator, okResting and resting, settings.RestIcon, frame.Health)
		if okResting and resting and settings.RestIcon.enable then
			local path, useCoords = ResolveStateIconTexture(settings.RestIcon, RESTING_TEXTURE)
			frame.RestingIndicator:SetTexture(path)
			if useCoords then
				frame.RestingIndicator:SetTexCoord(0, 0.5, 0, 0.421875)
			else
				frame.RestingIndicator:SetTexCoord(0, 1, 0, 1)
			end
		end
	end
	if frame.CombatIndicator and settings.CombatIcon then
		local okCombat, inCombat = pcall(UnitAffectingCombat, unit)
		UpdateStateIcon(frame.CombatIndicator, okCombat and inCombat, settings.CombatIcon, frame.Health)
		if okCombat and inCombat and settings.CombatIcon.enable then
			local path, useCoords = ResolveStateIconTexture(settings.CombatIcon, COMBAT_TEXTURE)
			frame.CombatIndicator:SetTexture(path)
			if useCoords then
				frame.CombatIndicator:SetTexCoord(0.5, 1, 0, 0.49)
			else
				frame.CombatIndicator:SetTexCoord(0, 1, 0, 1)
			end
		end
	end
	if frame.RaidTargetIndicator and settings.raidicon then
		UpdateRaidIcon(frame, unit, settings.raidicon)
	end
	if frame.ResurrectIndicator and settings.resurrectIcon then
		pcall(self.UpdateResurrectIcon, self, frame, unit, settings.resurrectIcon)
	end

	self:UpdateAuras(frame, "buff")
	self:UpdateAuras(frame, "debuff")
end

function UF:UpdateAll()
	local id, frame
	for id, frame in pairs(self.Frames) do
		self:UpdateFrame(frame)
	end
end

-- Live size change -- NOT blocked by anything technical, just never wired up
-- before: `UpdateFrame` recomputes Health/Power's own width AND (since the bar
-- heights were folded into it, see its own comment) their height on every poll
-- tick, so the outer frame's `SetWidth`/`SetHeight` is the only piece that was
-- ever missing. `UpdateFrame` is called once here instead of waiting up to 0.2s
-- for the next poll, so the change reads as instant.
--
-- `id` is a settings key, not necessarily one frame: Party's four member frames
-- all share the `party` table via `frame.unitDBKey`, so the fast path (a frame
-- registered under exactly this id) falls back to a sweep over every frame
-- pointing at the same settings.
--
-- Either dimension may be nil, meaning "leave it alone".
-- Copies one unit's whole settings table onto another, and resets a unit back to
-- its declared defaults. Real ElvUI's own two entry points for the per-unit
-- "Copy From" / "Restore Defaults" controls (its UF:MergeUnitSettings /
-- UF:ResetUnitSettings).
--
-- Both are RELOAD-BOUND on purpose, and the config setters say so: a unit's
-- settings table includes fields that are only read while the frame is being
-- BUILT (`enable`, `power.enable`, the portrait style), so overwriting the table
-- wholesale cannot be made live without a teardown/rebuild path this module does
-- not have. The pieces that ARE live (sizes, text, auras) simply come along.
--
-- `Util.MergeTable` overlays rather than replaces, and deep-copies any table it
-- takes from the source -- so the two units never end up sharing a nested table
-- by reference, which would make editing one silently edit the other.
function UF:MergeUnitSettings(fromId, toId)
	if not fromId or not toId or fromId == toId then return false end
	local from = E.db.unitframe.units[fromId]
	local to = E.db.unitframe.units[toId]
	if not from or not to then return false end

	ElvUI.Util.MergeTable(to, from)
	return true
end

function UF:ResetUnitSettings(id)
	local defaults = P.unitframe.units[id]
	if not defaults then return false end

	-- Emptied first, then re-merged: a plain merge would LEAVE any key the user
	-- added that the defaults do not mention, which is not a reset.
	local live = E.db.unitframe.units[id]
	local k
	for k in pairs(live) do
		live[k] = nil
	end
	ElvUI.Util.MergeTable(live, defaults)
	return true
end

function UF:ResizeUnit(id, width, height)
	local function apply(frame)
		if width then pcall(frame.SetWidth, frame, width) end
		if height then pcall(frame.SetHeight, frame, height) end
		self:UpdateFrame(frame)
	end

	local frame = self.Frames[id]
	if frame then
		apply(frame)
		return
	end

	local frameId, other
	for frameId, other in pairs(self.Frames) do
		if (other.unitDBKey or other.unit) == id then
			apply(other)
		end
	end
end

-- Live castbar size change -- like ResizeUnit's width fix, not blocked by
-- anything technical: Construct_Castbar (above) anchors Icon/Spark/Text/
-- Time via SetPoint LEFT/RIGHT relative to the bar itself, not fixed
-- widths, so they already follow a resize with no extra work. Only the
-- bar's own SetWidth/SetHeight (set once in Units/Player.lua at
-- construction) was ever missing a live call.
-- `unit`: "target" for the target bar, anything else the player bar.
function UF:ResizeCastbar(width, height, unit)
	local bar = self.PlayerCastbar
	if unit == "target" then bar = self.TargetCastbar end
	if not bar then return end
	pcall(bar.SetWidth, bar, width)
	pcall(bar.SetHeight, bar, height)
end

-- Build guard shared by every unit's spawn: one unit that fails to build must
-- not stop the others. A failure can stay silent on the real 1.12.1 client
-- even with scriptErrors on, so a short chat notice is printed instead of
-- relying on the client's error display. The notice is written for players
-- and names the effect only.
local function SpawnUnitSafely(id)
	local ok = pcall(function() UF:SpawnUnit(id) end)
	if not ok then
		E:Print(L["A unit frame could not be created."])
	end
end

function UF:Initialize()
	-- Each unit gated by its OWN `enable` (real ElvUI field, per unit) --
	-- reload-required, same as width/height, since frame construction
	-- itself is one-shot. No separate private master switch (see the
	-- defaults block's own comment on why that was dropped). Looped over
	-- an explicit list now that there are 4 units, not 2 -- add a new
	-- unit id here (plus its own Units/<Name>.lua registering it) rather
	-- than another copy-pasted if-block.
	local units = E.db.unitframe.units
	local unitIds = {"player", "target", "pet", "targettarget", "pettarget"}
	local i
	for i = 1, table.getn(unitIds) do
		local id = unitIds[i]
		if units[id] and units[id].enable then
			SpawnUnitSafely(id)
		end
	end

	-- Party is special -- 4 frames, but ONE shared `enable` (and every
	-- other setting) at `units.party`, not `units.party1`.."party4"
	-- separately (see Groups/Party.lua's own comment on why).
	if units.party and units.party.enable then
		local partyIndex
		for partyIndex = 1, 4 do
			SpawnUnitSafely("party"..partyIndex)
		end
	end

	self:UpdateAll()
	E:ScheduleRepeatingTimer(function() UF:UpdateAll() end, 0.2)

	local function OnUnitEvent() UF:UpdateAll() end
	self:RegisterEvent("UNIT_HEALTH", OnUnitEvent)
	self:RegisterEvent("UNIT_MAXHEALTH", OnUnitEvent)
	self:RegisterEvent("UNIT_MANA", OnUnitEvent)
	self:RegisterEvent("UNIT_RAGE", OnUnitEvent)
	self:RegisterEvent("UNIT_ENERGY", OnUnitEvent)
	self:RegisterEvent("UNIT_FOCUS", OnUnitEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnUnitEvent)
	self:RegisterEvent("PLAYER_UPDATE_RESTING", OnUnitEvent)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", OnUnitEvent)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", OnUnitEvent)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", OnUnitEvent)
	self:RegisterEvent("UNIT_PET", OnUnitEvent)
	self:RegisterEvent("PARTY_MEMBERS_CHANGED", OnUnitEvent)
	self:RegisterEvent("UNIT_AURA", OnUnitEvent)
end

E:RegisterInitialModule(UF:GetName(), function() UF:Initialize() end)
