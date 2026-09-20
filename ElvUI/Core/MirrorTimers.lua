-- MirrorTimers -- restyles the native breath/feign-death/exhaustion
-- ("fatigue") mirror timer bars. This is a separate feature from the
-- castbar; real ElvUI implements it as Modules/Skins/Blizzard/
-- MirrorTimers.lua, part of its Skins module.
--
-- Real ElvUI's own version is a pure RESKIN, not a rebuild -- the actual
-- breath/feign-death/exhaustion TRACKING is 100% native (Blizzard's own
-- MirrorTimerFrame_OnUpdate keeps `frame.value`/`frame.paused`/
-- `frame.label` current on its own regardless of anything an addon
-- does), matching this project's "reparent/restyle existing native
-- widgets, never reimplement the tracking" pattern (ActionBars/PetBar/
-- StanceBar). Doesn't even need reparenting here -- MirrorTimer1..N
-- already position themselves reasonably via native code, restyling in
-- place is enough.
--
-- Deliberately does NOT hook `MirrorTimerFrame_OnUpdate` the way real
-- ElvUI does (`hooksecurefunc`) -- a shared polling timer is preferred
-- over hooking native update functions when the alternative is just as
-- simple (see Cooldowns.lua's own header comment for the identical
-- tradeoff on the global cooldown-text hook) -- `frame.value`/
-- `frame.paused`/`frame.label` are just fields Blizzard's own code keeps
-- updated, freely readable without hooking anything.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()

local NUM_MIRROR_TIMERS = _G.MIRRORTIMER_NUMTIMERS or 3

-- Real ElvUI has NO per-module statusbar field for MirrorTimers -- it
-- reads the ONE shared `E.media.normTex` instead (`V.general.normTex`,
-- resolved once at OnInitialize -- see Init.lua's own comment; kept under
-- the same variable name real ElvUI vanilla uses so an imported profile
-- drives it directly). PRIVATE/reload-required by nature (matches every
-- other V.*/E.private.* setting in this project) -- no live per-tick
-- re-apply needed here, unlike UnitFrames' own `unitframe.statusbar` (a
-- genuinely different, PROFILE-level field real ElvUI also has).
local function GetBarTexture()
	return E.media and E.media.normTex or "Interface\\Buttons\\WHITE8x8"
end

local function UpdateMirrorTimerText(frame)
	local textRegion = frame.elvTimerText
	if not textRegion then return end
	if frame.paused then return end

	local value = tonumber(frame.value) or 0
	if value < 0 then value = 0 end
	local minutes = math.floor(value / 60)
	local seconds = value - minutes * 60
	local label = (frame.label and frame.label.GetText and frame.label:GetText()) or ""

	pcall(textRegion.SetText, textRegion, string.format("%s (%d:%02d)", label, minutes, seconds))
end

-- Hides every Texture-type region directly on `obj` (not recursive --
-- children of children aren't touched). Matches real ElvUI's own
-- `E:StripTextures(frame)` helper, which this project doesn't have.
local function StripTextureRegions(obj, exclude)
	local okRegions, regions = pcall(function() return {obj:GetRegions()} end)
	if not okRegions or not regions then return end

	local r
	for r = 1, table.getn(regions) do
		local region = regions[r]
		if region and region ~= exclude and region.GetObjectType then
			local okType, objType = pcall(region.GetObjectType, region)
			if okType and objType == "Texture" then
				pcall(region.SetTexture, region, nil)
				pcall(region.Hide, region)
			end
		end
	end
end

-- Idempotent, matches ActionBars.lua's/PetBar.lua's own StyleButton
-- convention -- safe to call repeatedly on the periodic resweep below,
-- guarded so it only actually builds things once per frame.
local function StyleMirrorTimer(i)
	local frame = _G["MirrorTimer"..i]
	local statusBar = _G["MirrorTimer"..i.."StatusBar"]
	local text = _G["MirrorTimer"..i.."Text"]
	if not frame or not statusBar or frame.elvStyled then return end

	local settings = E.db.mirrortimers

	if text then
		pcall(text.Hide, text)
		text.Show = E.noop
	end

	pcall(frame.SetWidth, frame, settings.width)
	pcall(frame.SetHeight, frame, settings.height)
	pcall(statusBar.SetWidth, statusBar, settings.width)
	pcall(statusBar.SetHeight, statusBar, settings.height)

	-- Strips the OUTER frame's own native art (the metal-cap border/
	-- background regions) -- live-reported via screenshot: without
	-- this, the fully native chrome remained completely visible, our
	-- own backdrop/text only ever showing as a faint overlay behind/
	-- above it, not actually replacing anything. Deliberately does NOT
	-- run the same generic strip on `statusBar` itself -- a StatusBar's
	-- own fill texture may well be one of ITS "regions" too, and
	-- Hide()-ing it here could leave it stuck hidden even after the
	-- explicit SetStatusBarTexture override just below re-textures it.
	-- The fill is handled directly via that call instead, not generic
	-- stripping.
	StripTextureRegions(frame, text)

	-- Overrides the native StatusBar's OWN fill texture -- this is the
	-- part that actually matters (screenshot confirmed a fully native-
	-- looking blue fill/metal-cap bar underneath our text the whole
	-- time -- a backdrop drawn at BACKGROUND layer sits BEHIND a
	-- StatusBar's own fill, which draws at a higher layer by nature of
	-- being the widget's actual content, so adding a backdrop alone was
	-- never going to hide it). Real ElvUI's own equivalent:
	-- `statusBar:SetStatusBarTexture(E.media.normTex)`.
	pcall(statusBar.SetStatusBarTexture, statusBar, GetBarTexture())
	pcall(statusBar.SetStatusBarColor, statusBar, 0.6, 0.6, 0.6, 1)

	pcall(statusBar.SetBackdrop, statusBar, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(statusBar.SetBackdropColor, statusBar, 0.1, 0.1, 0.1, 1)
	pcall(statusBar.SetBackdropBorderColor, statusBar, 0, 0, 0, 1)

	local timerText = frame:CreateFontString(nil, "OVERLAY")
	-- Real ElvUI's MirrorTimers skin: the UI font at its default size.
	E:FontTemplate(timerText)
	timerText:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
	frame.elvTimerText = timerText

	-- Real ElvUI's own exact mover name (ElvUI-vanilla/ElvUI/
	-- Modules/Skins/Blizzard/MirrorTimers.lua:56) -- kept for eventual
	-- real-profile position compatibility, same convention already
	-- established for every other mover in this project.
	E:CreateMover(frame, "MirrorTimer"..i.."Mover", string.format(L["Mirror Timer %d"], i))

	frame.elvStyled = true
end

-- Live size change. StyleMirrorTimer above is guarded by `elvStyled` so it only
-- ever builds once per frame, which is correct for the one-time work (killing
-- native art, creating the backdrop and the timer text) but also meant the two
-- size settings could never be re-applied. This applies just the dimensions,
-- deliberately skipping that guard, and only to frames the styling has already
-- run on -- an unstyled frame will pick the new values up from `E.db` when it is
-- first styled anyway.
function E:ResizeMirrorTimers()
	local settings = E.db.mirrortimers
	local i
	for i = 1, NUM_MIRROR_TIMERS do
		local frame = _G["MirrorTimer"..i]
		local statusBar = _G["MirrorTimer"..i.."StatusBar"]
		if frame and statusBar and frame.elvStyled then
			pcall(frame.SetWidth, frame, settings.width)
			pcall(frame.SetHeight, frame, settings.height)
			pcall(statusBar.SetWidth, statusBar, settings.width)
			pcall(statusBar.SetHeight, statusBar, settings.height)
		end
	end
end

local function UpdateAllMirrorTimers()
	local i
	for i = 1, NUM_MIRROR_TIMERS do
		local frame = _G["MirrorTimer"..i]
		if frame and frame:IsShown() then
			UpdateMirrorTimerText(frame)
		end
	end
end

local function StyleAllMirrorTimers()
	local i
	for i = 1, NUM_MIRROR_TIMERS do
		StyleMirrorTimer(i)
	end
end

local function Initialize()
	-- `E.private`, NOT `V` -- V is the static defaults table, so reading the
	-- flag from there ignores the saved value entirely and the config
	-- checkbox does nothing.
	if not E.private.mirrortimers.enable then return end

	StyleAllMirrorTimers()
	E:ScheduleRepeatingTimer(UpdateAllMirrorTimers, 0.3)

	-- Same lazily-created-region problem already found (and worked
	-- around the same way) throughout this project -- MirrorTimer
	-- frames may not exist as usable regions yet at the exact moment
	-- Initialize() runs.
	ElvUI.Util.ScheduleLimitedSweep(StyleAllMirrorTimers, 3, 10)
end

E:RegisterInitialModule("MirrorTimers", Initialize)
