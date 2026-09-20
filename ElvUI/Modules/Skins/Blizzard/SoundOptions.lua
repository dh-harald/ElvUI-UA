-- Skins > Blizzard > SoundOptions -- reskins the native SoundOptionsFrame
-- (opened from the Escape menu's "Sound Options" row) in place. Same
-- recipe family as MainMenu.lua: strip native chrome, elvBackground child
-- frame (never SetBackdrop the native frame itself), automatic sweep for
-- the generic controls.
--
-- SPECIAL CASE for this window: this project can normally read the real
-- 1.12.1 FrameXML (`source/wow-ui-source/FrameXML/SoundOptionsFrame.xml`)
-- as ground truth for a window's exact child names/nesting before writing
-- a skin file. Here that doesn't apply -- this window's FrameXML has been
-- customised on this server, so real vanilla's own
-- 8-checkbox/4-slider/3-button, all-direct-children layout is only a
-- rough guide, NOT the actual live structure: at minimum there's also a
-- dropdown (real vanilla has none; only pfUI's TBC branch does, alongside
-- grouped sub-panels -- source/pfUI/skins/blizzard/options-sound.lua), and
-- a distinct graphical box element not seen in any window skinned so far.
--
-- Consequences of not knowing the real structure up front:
-- - `S:StripTextures(frame, true)` (RECURSIVE, unlike MainMenu's
--   non-recursive call) -- if this window nests controls inside grouping
--   sub-frames the way pfUI's TBC branch does, only a recursive strip
--   reaches their own native backdrops/art too. If it turns out
--   everything really is a direct child (matching plain vanilla), the
--   recursive call still does the right thing -- it only ever walks past
--   Button/CheckButton and dropdown-recognised Frames (Skins.lua).
-- - Every control (checkboxes, sliders, the Defaults/Cancel/Okay buttons,
--   the dropdown, the microphone level bar) is left to `S:SkinChildren`
--   alone. ONE per-name exception exists and it is not a control:
--   `OptionsVoiceChat`, the grouping box, needs a lighter surface that no
--   generic rule can place correctly -- see its own note at the constant
--   below for why the name is trustworthy here (it came from a live
--   measurement, not from the FrameXML) and why the generic version of
--   that rule would be wrong. Otherwise still no per-name calls,
--   deliberately: a hardcoded name list is exactly the thing that can't
--   survive a customised layout, which is the whole reason the sweep
--   exists. `S:SkinChildren` recurses through ordinary
--   (non-Button/CheckButton/dropdown) Frames up to 8 levels deep, so
--   nested grouping sub-panels are still reached even without knowing
--   their names.
-- - The Defaults/Cancel/Okay buttons inherit `GameMenuButtonTemplate` in
--   real vanilla -- the exact same template as `GameMenuFrame`'s own 8
--   rows, which the sweep is CONFIRMED WORKING on live. High confidence
--   these pick up the same way with zero per-button code.
-- - The dropdown is new sweep capability added alongside this file
--   (`S:SkinChildren`'s Frame branch, Skins.lua): a `UIDropDownMenuTemplate`
--   box is recognised by its own template-fixed Left/Middle/Right art
--   PLUS a `$parentButton` child actually existing, so it doesn't depend
--   on knowing the dropdown's name in advance, and doesn't mis-fire on an
--   unrelated decorative box using the same label-frame asset.
--
-- The "distinct box" element is the "Voice Chat Settings" grouping box:
-- its real global name (`OptionsVoiceChat`) came from a live measurement
-- with `S.autoSkinDebug` on, not from the FrameXML, since this window's
-- layout is customised on this server.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- The "Voice Chat Settings" grouping box. Its name is NOT from any
-- FrameXML -- this window's is customised on the server and has no such box
-- in it at all; the name came out of a LIVE measurement: with
-- `S.autoSkinDebug` on, the sweep reported five frames whose native
-- `<Backdrop>` had to be neutralised, and this was the only one of the five
-- with a real name rather than a `GeneratedLuaUIObject_NNNN` (the client
-- builds this box from its own Lua, not from XML).
--
-- Used by NAME here anyway, and only here, because the alternative is worse:
-- the generic "any frame that carried a native backdrop is a group box" rule
-- would have hit all five, and the other four are nested rows/wells inside
-- this one -- lightening those too would just produce a stack of overlapping
-- lighter slabs. Degrades to nothing if the name ever goes away.
local VOICE_CHAT_BOX = "OptionsVoiceChat"

local function ApplySoundOptionsChrome(frame)
	S:StripTextures(frame, true)

	S:CreatePanel(frame)

	-- Stripping the native chrome also removes the native light-grey
	-- background this box used to have; `GROUP_COLOR` gives it a slightly
	-- lighter background than the panel again, sitting between the panel
	-- and the widget tone precisely so the "Test Microphone" button and
	-- the microphone dropdown INSIDE this box stay readable against it --
	-- see that token's own note in Skins.lua.
	local voiceBox = _G[VOICE_CHAT_BOX]
	if voiceBox then S:CreateSurface(voiceBox, S.GROUP_COLOR) end

	S:SkinChildren(frame)
end

local soundOptionsSkinApplied = false
local function ApplySoundOptionsSkin()
	if soundOptionsSkinApplied then return end
	local frame = _G.SoundOptionsFrame
	if not frame then return end
	soundOptionsSkinApplied = true

	ApplySoundOptionsChrome(frame)
	local ok = S:TryHookScript(frame, "OnShow", function() ApplySoundOptionsChrome(frame) end)
	if not ok then S:ReportSkinProblem() end
end

local function LoadSkin()
	ApplySoundOptionsSkin()
end

S:AddBlizzardSkin("sound", LoadSkin)
