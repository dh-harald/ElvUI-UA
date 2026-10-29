local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local NP = E:NewModule("NamePlates", "AceEvent-3.0")

-- NamePlates -- real ElvUI's nameplates (ElvUI-vanilla Modules/NamePlates),
-- built on top of the native plates: every native plate gets an ElvUI unit
-- frame as a child, and the native art is muted. Gated by
-- `E.private.nameplates.enable` (reload); while it runs, the NamePlates skin
-- (Modules/Skins/Blizzard/NamePlates.lua) stays off.
--
-- A native plate is an unnamed WorldFrame child with one StatusBar child
-- (health) and six regions in a fixed order: border, mouseover highlight,
-- name, level, boss skull, raid icon. It is recognised by its first region's
-- `Interface\Tooltips\Nameplate-Border` texture (true on both clients; on
-- Unreal Azeroth a Lua frame of the engine class FNamePlateFrame). Plates are
-- created on demand and reused for other units, so the WorldFrame children
-- are rescanned whenever their count changes, and every visible plate is
-- re-read each frame: on a 0.1 s timer a new plate visibly shows its native
-- look first. The per-frame work only compares values and touches widgets
-- on change.
--
-- A plate carries no unit token, so everything comes from the native plate:
-- - unit type and reaction: the native health bar's colour, which the client
--   sets by reaction (red hostile, yellow neutral, green friendly NPC, blue
--   friendly player, grey tapped);
-- - health: the native bar's value and range (a percentage for most units);
-- - target: while there is a target, the client lowers the alpha of every
--   other plate (0.498 measured on Unreal Azeroth, where that alpha is not
--   drawn); the target's plate keeps alpha 1;
-- - mouseover: the client shows the native highlight region under the mouse;
-- - name, level (with the difficulty colour), boss skull: the native regions.
--
-- Muting the native art: border and highlight are made transparent (the
-- client shows the highlight again on hover, which is what the mouseover
-- check reads); name and level are hidden, re-hidden if the client shows
-- them, and anchored below the screen; the skull is transparent but keeps
-- its shown state as data. The
-- native health bar stays shown, so the client keeps updating its value and
-- colour, but is shrunk to a point, made transparent and parked below the
-- screen. The raid icon stays native and is only re-anchored next to the
-- ElvUI health bar.
--
-- Scale: native plates are WorldFrame children and ignore the UI scale. The
-- ElvUI frame is scaled to match UIParent, as in current real ElvUI, where
-- nameplates follow the UI scale. ElvUI-vanilla leaves them at world scale.
--
-- The mouseover highlight is current real ElvUI's: a flat white layer at
-- 0.25 * 0.75 alpha over the whole health bar (ElvUI-vanilla lays the status
-- bar texture at 0.3 alpha over the filled part only). Name-only plates use
-- ElvUI-vanilla's glow behind the name.
--
-- Cast bars: the client reports no casts of other units; they are read by
-- caster name from the combat-log cast tracker the target cast bar uses
-- (UnitFrames/CastTracker.lua), which has no channels and cannot tell
-- same-named units apart.
--
-- Buffs and debuffs: read while the plate is the target or under the mouse
-- and kept on the plate until they run out (see UpdateAuras).
--
-- Threat: each hostile mob's own target, refined by LibVanillaThreat-1.0
-- when an addon loads it (see ScanThreat).
--
-- Class colours: from the class cache (Core/ClassCache.lua) by name; a
-- hostile plate whose name the cache knows is an enemy player.
--
-- Not ported yet: style filters, motion type, click-through and clickable
-- size, the elite icon, and the size animation.

local LSM = LibStub("LibSharedMedia-3.0", true)
local LVD = LibStub("LibVanillaDurations-1.0", true)
local Util = ElvUI.Util
local Compat = ElvUI.Compat
local getn = Compat.getn

local BORDER_TEXTURE = "interface\\tooltips\\nameplate-border"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA = "Interface\\AddOns\\ElvUI\\Media\\Textures\\"
local SPARK = MEDIA .. "spark"
-- Real ElvUI's pixel-mode E.Border / E.Spacing; this project has no pixel
-- perfect scaling, so both are 1.
local BORDER = 1
local TARGET_LEVEL = 20
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local ICON_COORDS = { 0.08, 0.92, 0.08, 0.92 }
local BUBBLE = MEDIA .. "bubbleTex"
local MAX_COMBO = 5
local MAX_DEBUFFS = 16
local MAX_BUFFS = 32
-- ElvUI-vanilla's FRIENDLY_PLAYER buffs have no baseHeight; its aura code
-- falls back to 18.
local AURA_HEIGHT = 18
local SCAN_TIP = "ElvUI_NamePlateScanTooltip"
-- Real ElvUI polls aura timers at this interval.
local AURA_INTERVAL = 0.1
-- Real ElvUI's spacing between aura icons (E.Border + E.Spacing * 3).
local AURA_SPACING = 4
-- Retail ElvUI's target arrows (Media/Arrows, 64x64, pointing up), drawn at
-- their own size times `units.TARGET.arrowScale` and turned by texture
-- coordinates: the top one points down, the one right of the bar left, the
-- one left of it right.
local ARROWS = "Interface\\AddOns\\ElvUI\\Media\\Arrows\\"
local ARROW_SIZE = 64
local ARROW_COORDS = {
	TopArrow = { 1, 1, 1, 0, 0, 1, 0, 0 },
	LeftArrow = { 1, 0, 0, 0, 1, 1, 0, 1 },
	RightArrow = { 1, 1, 0, 1, 1, 0, 0, 0 },
}
-- The client's dimmed non-target plate alpha is 0.498; anything this close to
-- 1 counts as undimmed.
local LIT_ALPHA = 0.99

-- The UnitFrames module, owner of the combat-log cast tracker; set at
-- Initialize.
local UF

local plates = {}
local numChildren = 0
local plateID = 0
local uiScale

local function Fetch(mediaType, name)
	return LSM and name and LSM:Fetch(mediaType, name)
end

local function SetColor(texture, color)
	texture:SetVertexColor(color.r, color.g, color.b, color.a or 1)
end

-- ---------------------------------------------------------------------
-- Native plate
-- ---------------------------------------------------------------------
local function IsNamePlate(frame)
	local ok, region = pcall(frame.GetRegions, frame)
	if not ok or not region or not region.GetTexture then return false end
	local okTex, texture = pcall(region.GetTexture, region)
	return okTex and type(texture) == "string" and string.lower(texture) == BORDER_TEXTURE
end

local function Mute(region, keepShown)
	if not region then return end
	pcall(region.SetAlpha, region, 0)
	if not keepShown then pcall(region.Hide, region) end
end

local function IsShown(region)
	if not region then return false end
	local ok, shown = pcall(region.IsShown, region)
	return ok and Compat.bool(shown)
end

-- Unreal Azeroth keeps drawing the native level text however it is hidden,
-- made transparent or narrowed, and rewrites its text every frame; it does
-- follow a new anchor, so name and level are also parked below the screen.
local function Park(region)
	if not region then return end
	pcall(region.ClearAllPoints, region)
	pcall(region.SetPoint, region, "TOP", UIParent, "BOTTOM", 0, -500)
end

-- The native health bar stays shown, so the client keeps updating its value
-- and colour. Shrunk to a point and made transparent it still draws one
-- pixel on Unreal Azeroth (a dot under a name-only plate's name), so it is
-- parked below the screen as well; value and colour still read there.
local function MuteNativeBar(frame)
	local bar = frame.oldHealthBar
	pcall(bar.SetAlpha, bar, 0)
	pcall(bar.SetWidth, bar, 1)
	pcall(bar.SetHeight, bar, 1)
	Park(bar)
end

local function MuteNative(frame)
	Mute(frame.oldBorder)
	Mute(frame.oldHighlight, true)
	Mute(frame.oldName)
	Mute(frame.oldLevel)
	Park(frame.oldName)
	Park(frame.oldLevel)
	Mute(frame.BossIcon, true)
	MuteNativeBar(frame)
end

-- The client may show the native name and level again when it refreshes a
-- plate; they hold data only.
local function KeepMuted(frame)
	if IsShown(frame.oldName) then Mute(frame.oldName) end
	if IsShown(frame.oldLevel) then Mute(frame.oldLevel) end
end

local function NativeText(region)
	if not region then return "" end
	local ok, text = pcall(region.GetText, region)
	if not ok or not text then return "" end
	local _, _, trimmed = string.find(text, "^%s*(.-)%s*$")
	return trimmed or text
end

local function NativeHealth(frame)
	local bar = frame.oldHealthBar
	local okValue, value = pcall(bar.GetValue, bar)
	local okRange, low, high = pcall(bar.GetMinMaxValues, bar)
	if not okValue or type(value) ~= "number" then value = 0 end
	if not okRange or type(high) ~= "number" or high <= 0 then high = 1 end
	return value, high
end

-- Real ElvUI's GetUnitInfo: reaction and unit type from the native bar's
-- colour. Thresholds instead of exact matches, plus the grey tapped colour
-- ElvUI-vanilla leaves out; anything else counts as hostile.
local function UnitInfo(frame)
	local bar = frame.oldHealthBar
	local ok, r, g, b = pcall(bar.GetStatusBarColor, bar)
	if not ok or type(r) ~= "number" then return 2, "ENEMY_NPC" end
	if r > 0.9 and g > 0.9 and b < 0.1 then return 4, "ENEMY_NPC" end
	if r > 0.9 and g < 0.1 and b < 0.1 then return 2, "ENEMY_NPC" end
	if g > 0.9 and r < 0.1 and b < 0.1 then return 5, "FRIENDLY_NPC" end
	if b > 0.9 and r < 0.1 then return 5, "FRIENDLY_PLAYER" end
	if math.abs(r - g) < 0.05 and math.abs(g - b) < 0.05 then return 1, "ENEMY_NPC" end
	return 2, "ENEMY_NPC"
end

-- Unreal Azeroth stops a plate whose unit leaves the screen at the screen
-- edge (its left reaches exactly 0) instead of hiding it, so a plate
-- touching an edge counts as off screen; a unit standing right at the edge
-- loses its plate a little early.
local EDGE_SLACK = 0.5

local function AtScreenEdge(plate)
	local left, bottom = plate:GetLeft(), plate:GetBottom()
	if not left or not bottom then return false end
	local screenWidth, screenHeight = WorldFrame:GetWidth(), WorldFrame:GetHeight()
	return left <= EDGE_SLACK or bottom <= EDGE_SLACK
		or plate:GetRight() >= screenWidth - EDGE_SLACK
		or plate:GetTop() >= screenHeight - EDGE_SLACK
end

local function IsLit(plate)
	local ok, alpha = pcall(plate.GetAlpha, plate)
	return not ok or type(alpha) ~= "number" or alpha >= LIT_ALPHA
end

-- The plate's own effective scale, else WorldFrame's (a plate's own scale is
-- 1), else 1.
local function ScaleFactor(plate)
	if not uiScale then return 1 end
	local ok, world = pcall(plate.GetEffectiveScale, plate)
	if not ok or type(world) ~= "number" or world <= 0 then
		ok, world = pcall(WorldFrame.GetEffectiveScale, WorldFrame)
	end
	if not ok or type(world) ~= "number" or world <= 0 then world = 1 end
	return uiScale / world
end

local function ReadUIScale()
	local ok, scale = pcall(UIParent.GetEffectiveScale, UIParent)
	if ok and type(scale) == "number" and scale > 0 then return scale end
	return nil
end

-- ---------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------
local function NewTexture(parent, layer, path)
	local tex = parent:CreateTexture(nil, layer)
	tex:SetTexture(path or WHITE)
	return tex
end

-- Unreal Azeroth does not draw the part of a texture that reaches past the
-- right or bottom edge of its parent frame: on the 1x1 plate frame only the
-- part left of and above the frame shows. A texture that overhangs its
-- parent therefore gets a frame of its own, which callers size, place, show
-- and hide; the texture (`.texture`) fills it.
local function NewFramedTexture(parent, layer, path)
	local holder = CreateFrame("Frame", nil, parent)
	local tex = NewTexture(holder, layer, path)
	tex:SetAllPoints(holder)
	holder.texture = tex
	holder:Hide()
	return holder
end

-- Real ElvUI's StyleFrame, pixel-mode branch: the bar's own background takes
-- the backdrop fade colour, and four 1-unit lines frame it from outside.
local function ConstructBorder(bar)
	local lines = {}
	local i
	for i = 1, 4 do
		lines[i] = NewTexture(bar, "BORDER")
	end
	lines[1]:SetPoint("TOPLEFT", bar, "TOPLEFT", -BORDER, BORDER)
	lines[1]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", BORDER, BORDER)
	lines[1]:SetHeight(BORDER)
	lines[2]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -BORDER, -BORDER)
	lines[2]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", BORDER, -BORDER)
	lines[2]:SetHeight(BORDER)
	lines[3]:SetPoint("TOPLEFT", bar, "TOPLEFT", -BORDER, BORDER)
	lines[3]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -BORDER, -BORDER)
	lines[3]:SetWidth(BORDER)
	lines[4]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", BORDER, BORDER)
	lines[4]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", BORDER, -BORDER)
	lines[4]:SetWidth(BORDER)
	bar.borderLines = lines
end

local function ConstructHealthBar(frame)
	local bar = Util.CreateStatusBar(frame, {})
	bar:SetFrameLevel(frame:GetFrameLevel() + 1)
	ConstructBorder(bar)

	-- The mouseover layer sits on the bar above the fill; the text gets a
	-- child frame so it always draws above that layer.
	local highlight = NewTexture(bar, "OVERLAY")
	highlight:SetAllPoints(bar)
	highlight:SetVertexColor(1, 1, 1, 0.25 * 0.75)
	highlight:Hide()
	bar.highlight = highlight

	local holder = CreateFrame("Frame", nil, bar)
	holder:SetAllPoints(bar)
	holder:SetFrameLevel(bar:GetFrameLevel() + 1)
	bar.text = holder:CreateFontString(nil, "OVERLAY")
	bar.text:SetAllPoints(bar)
	bar.textHolder = holder

	bar:Hide()
	return bar
end

-- Real ElvUI's target indicators: a border glow frame, a background glow and
-- three arrows, all hidden until UpdateGlow picks them by style.
local function ConstructGlow(frame)
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetFrameLevel(frame:GetFrameLevel())
	pcall(glow.SetBackdrop, glow, { edgeFile = Fetch("border", "ElvUI GlowBorder") or (MEDIA .. "glowTex"), edgeSize = 6 })
	glow:Hide()
	frame.Glow = glow

	frame.Glow2 = NewFramedTexture(frame, "BACKGROUND", SPARK)

	local key
	for key in pairs(ARROW_COORDS) do
		frame[key] = NewFramedTexture(frame, "BACKGROUND")
	end
end

-- Real ElvUI's cast bar: below the health bar, the spell icon to the right
-- of both, spell name and time below the bar.
local function ConstructCastBar(frame)
	local bar = Util.CreateStatusBar(frame, {})
	bar:SetFrameLevel(frame:GetFrameLevel() + 1)
	ConstructBorder(bar)

	local icon = CreateFrame("Frame", nil, bar)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints(icon)
	icon.texture:SetTexCoord(ICON_COORDS[1], ICON_COORDS[2], ICON_COORDS[3], ICON_COORDS[4])
	ConstructBorder(icon)
	bar.Icon = icon

	bar.Name = bar:CreateFontString(nil, "OVERLAY")
	bar.Time = bar:CreateFontString(nil, "OVERLAY")
	-- Twice the bar's height, so it gets a frame of its own.
	bar.Spark = NewFramedTexture(bar, "OVERLAY", SPARK_TEXTURE)
	bar.Spark.texture:SetBlendMode("ADD")

	bar:Hide()
	return bar
end

-- Real ElvUI's aura icon: bordered, no backdrop, time at the top left and
-- stacks at the bottom right.
local function ConstructAuraIcon(row)
	local aura = CreateFrame("Frame", nil, row)
	ConstructBorder(aura)
	aura.icon = aura:CreateTexture(nil, "ARTWORK")
	aura.icon:SetAllPoints(aura)
	aura.icon:SetTexCoord(ICON_COORDS[1], ICON_COORDS[2], ICON_COORDS[3], ICON_COORDS[4])
	aura.timeLeft = aura:CreateFontString(nil, "OVERLAY")
	aura.timeLeft:SetPoint("TOPLEFT", aura, "TOPLEFT", 2, 2)
	aura.count = aura:CreateFontString(nil, "OVERLAY")
	aura.count:SetPoint("BOTTOMRIGHT", aura, "BOTTOMRIGHT", 0, 0)
	aura:Hide()
	return aura
end

-- An aura row; `side` is where its first icon sits (ElvUI-vanilla: buffs
-- fill from the left, debuffs from the right).
local function ConstructAuraRow(frame, side)
	local row = CreateFrame("Frame", nil, frame)
	row:SetFrameLevel(frame:GetFrameLevel() + 1)
	row:SetHeight(AURA_HEIGHT)
	row.icons = {}
	row.cache = {}
	row.names = {}
	row.side = side
	row:Hide()
	return row
end

-- Real ElvUI's combo points: five 12x12 bubbles, 2 apart, centred on the
-- bottom edge of the health bar. The holder is exactly as large as the row
-- of bubbles (see NewFramedTexture).
local function ConstructComboPoints(frame)
	local holder = CreateFrame("Frame", nil, frame.HealthBar)
	holder:SetPoint("CENTER", frame.HealthBar, "BOTTOM", 0, 0)
	holder:SetWidth(MAX_COMBO * 12 + (MAX_COMBO - 1) * 2)
	holder:SetHeight(12)
	local i
	for i = 1, MAX_COMBO do
		local point = NewTexture(holder, "OVERLAY", BUBBLE)
		point:SetWidth(12)
		point:SetHeight(12)
		if i == 1 then
			point:SetPoint("LEFT", holder, "LEFT", 0, 0)
		else
			point:SetPoint("LEFT", holder[i - 1], "RIGHT", 2, 0)
		end
		holder[i] = point
	end
	holder:Hide()
	return holder
end

-- Name and level sit on their own frame, raised above the name-only glow's
-- frame so the glow stays behind the text.
local function ConstructTexts(frame)
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	frame.TextHolder = holder
	frame.Name = holder:CreateFontString(nil, "OVERLAY")
	frame.Level = holder:CreateFontString(nil, "OVERLAY")

	-- ElvUI-vanilla anchors the glow to the name's corners, 20 out on the
	-- sides and 8 above and below. On Unreal Azeroth a frame anchored to the
	-- corners of a font string on a scaled frame gets that size times the
	-- scale once more (50 instead of 70 wide at 0.712) and the glow all but
	-- vanishes, so it is centred on the name and sized from it in UpdateName.
	local glow = NewFramedTexture(frame, "BACKGROUND", SPARK)
	glow:SetPoint("CENTER", frame.Name, "CENTER", 0, 0)
	frame.Name.NameOnlyGlow = glow
end

function NP:OnCreated(plate)
	local bar = plate:GetChildren()
	if not bar then return end
	local border, highlight, name, level, boss, raid = plate:GetRegions()

	plateID = plateID + 1
	local frame = CreateFrame("Frame", "ElvUI_NamePlate" .. plateID, plate)
	frame:SetPoint("CENTER", plate, "CENTER", 0, 0)
	frame:SetWidth(1)
	frame:SetHeight(1)
	frame.plate = plate
	frame.plateID = plateID
	frame.oldHealthBar = bar
	frame.oldBorder = border
	frame.oldHighlight = highlight
	frame.oldName = name
	frame.oldLevel = level
	frame.BossIcon = boss
	frame.RaidIcon = raid

	frame.HealthBar = ConstructHealthBar(frame)
	frame.CastBar = ConstructCastBar(frame)
	frame.Buffs = ConstructAuraRow(frame, "LEFT")
	frame.Buffs.key = "buffs"
	frame.Debuffs = ConstructAuraRow(frame, "RIGHT")
	frame.Debuffs.key = "debuffs"
	frame.CPoints = ConstructComboPoints(frame)
	ConstructGlow(frame)
	ConstructTexts(frame)

	MuteNative(frame)
	frame:Hide()
	plate.UnitFrame = frame
	table.insert(plates, frame)
end

-- ---------------------------------------------------------------------
-- Elements
-- ---------------------------------------------------------------------
local function UnitDB(frame)
	return NP.db.units[frame.UnitType]
end

local function ReactionColor(frame)
	local reactions = NP.db.reactions
	local reaction = frame.UnitReaction
	if reaction == 1 then return reactions.tapped end
	if reaction == 4 then return reactions.neutral end
	if reaction > 4 then
		if frame.UnitType == "FRIENDLY_PLAYER" then return reactions.friendlyPlayer end
		return reactions.good
	end
	return reactions.bad
end

-- Real ElvUI's E:GetFormattedText styles, on the native bar's values.
local TEXT_FORMATS = {
	CURRENT = "%s",
	CURRENT_MAX = "%s - %s",
	CURRENT_PERCENT = "%s - %.1f%%",
	CURRENT_MAX_PERCENT = "%s - %s | %.1f%%",
	PERCENT = "%.1f%%",
	DEFICIT = "-%s",
}

local function FormatHealth(style, value, high)
	local pattern = TEXT_FORMATS[style] or TEXT_FORMATS.CURRENT
	local dec = (E.db.general and E.db.general.decimalLength) or 1
	if dec ~= 1 and string.find(style, "PERCENT") then
		pattern = string.gsub(pattern, "%%%.1f%%%%", "%%." .. dec .. "f%%%%")
	end
	local percent = value / high * 100
	if style == "DEFICIT" then
		if high - value <= 0 then return "" end
		return string.format(pattern, E:ShortValue(high - value))
	elseif style == "PERCENT" then
		return string.format(pattern, percent)
	elseif style == "CURRENT" or value == high then
		return E:ShortValue(value)
	elseif style == "CURRENT_MAX" then
		return string.format(pattern, E:ShortValue(value), E:ShortValue(high))
	elseif style == "CURRENT_PERCENT" then
		return string.format(pattern, E:ShortValue(value), percent)
	end
	return string.format(pattern, E:ShortValue(value), E:ShortValue(high), percent)
end

function NP:UpdateHealth(frame)
	local value, high = NativeHealth(frame)
	frame.healthValue, frame.healthMax = value, high
	local bar = frame.HealthBar
	bar:SetMinMaxValues(0, high)
	bar:SetValue(value)
	local text = UnitDB(frame).healthbar.text
	if text.enable then
		bar.text:SetText(FormatHealth(text.format, value, high))
	else
		bar.text:SetText("")
	end
end

-- Threat. The client has no threat API (ElvUI-vanilla leaves real ElvUI's
-- threat settings unused), so the mob's own target decides who it attacks:
-- every group member's target, the pet's, the player's target and mouseover
-- are read; a hostile mob in combat whose target is the player is status 3
-- ("tanking"), one targeting anybody else is status 0, and one with no
-- target at all (fleeing, feared) has no status: its plate falls back to the
-- reaction colour and normal size. The state is kept by the mob's name for
-- THREAT_MEMORY seconds, so plates of mobs nobody targets keep it a while;
-- same-named mobs share it.
--
-- LibVanillaThreat-1.0, when an addon loads it, refines that within the
-- observed victim, never against it. It estimates only the player's and the
-- pet's threat from the combat log, so it is asked only where both sides of
-- the comparison are its own: a mob on the player with the pet above the
-- player is status 2, a mob on the pet with the player above the pet (not yet
-- past the 110% / 130% pull) is status 1. Out of a group the player and the
-- pet are a mob's whole threat list, so a mob nobody targets takes status 3 or
-- 0 from whichever of the two the library has on top. "Tanked by another
-- tank" has no source: 1.12 has no group roles.
local THREAT_MEMORY = 3
local THREAT_INTERVAL = 0.2
local threatByName = {}
local threatNext = 0
local threatSolo = true

local OWN_UNITS = { "target", "mouseover", "pettarget" }
local PARTY_UNITS, RAID_UNITS = {}, {}
local i
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i .. "target" end
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i .. "target" end

-- Looked up on use: an addon loaded after ElvUI may be the one that ships it.
local LVT
local function ThreatLib()
	if not LVT then LVT = LibStub("LibVanillaThreat-1.0", true) end
	if LVT and LVT.playerName then return LVT end
	return nil
end

local function RefineThreat(status, name, mobTarget)
	local lib = ThreatLib()
	if not lib or not lib.petName then return status end
	local mine = lib:GetThreat(lib.playerName, name)
	local pet = lib:GetThreat(lib.petName, name)
	if not mine or not pet then return status end
	if status == 3 then
		if pet > mine then return 2 end
	elseif Compat.bool(UnitIsUnit(mobTarget, "pet")) and mine > pet then
		return 1
	end
	return status
end

local function ReadThreat(unit, now)
	if not Compat.bool(UnitExists(unit)) or Compat.bool(UnitIsDeadOrGhost(unit)) then return end
	if not Compat.bool(UnitCanAttack("player", unit)) or not Compat.bool(UnitAffectingCombat(unit)) then return end
	local name = UnitName(unit)
	if not name then return end
	local mobTarget = unit .. "target"
	if not Compat.bool(UnitExists(mobTarget)) then
		threatByName[name] = { status = false, time = now }
		return
	end
	local status = Compat.bool(UnitIsUnit(mobTarget, "player")) and 3 or 0
	threatByName[name] = { status = RefineThreat(status, name, mobTarget), time = now }
end

local function ScanThreat(now)
	if now < threatNext then return end
	threatNext = now + THREAT_INTERVAL
	local name, entry
	for name, entry in pairs(threatByName) do
		if now - entry.time > THREAT_MEMORY then threatByName[name] = nil end
	end
	local k
	for k = 1, getn(OWN_UNITS) do ReadThreat(OWN_UNITS[k], now) end
	local raidSize = GetNumRaidMembers() or 0
	local partySize = GetNumPartyMembers() or 0
	threatSolo = raidSize == 0 and partySize == 0
	if raidSize > 0 then
		for k = 1, raidSize do ReadThreat(RAID_UNITS[k], now) end
	else
		for k = 1, partySize do ReadThreat(PARTY_UNITS[k], now) end
	end
end

-- The plate's threat status: the observed one, else (out of a group) the
-- library's top threat holder. A mob seen without a target stays without a
-- status, whatever the library holds.
local function ThreatStatus(name)
	local entry = threatByName[name]
	if entry then return entry.status or nil end
	local lib = threatSolo and ThreatLib()
	if not lib then return nil end
	local value, top = lib:GetMaxThreatOnTarget(name)
	if not top or value <= 0 then return nil end
	if top == lib.playerName then return 3 end
	return 0
end

-- Real ElvUI's E.Role (ElvUI-vanilla core.lua CheckRole): by class, or by
-- the talent tree with the most points; a feral druid with Feral Instinct
-- counts as a tank.
local CLASS_ROLE = {
	PALADIN = { "Caster", "Tank", "Melee" },
	PRIEST = "Caster", WARLOCK = "Caster", HUNTER = "Melee", ROGUE = "Melee", MAGE = "Caster",
	WARRIOR = { "Melee", "Melee", "Tank" },
	SHAMAN = { "Caster", "Melee", "Caster" },
	DRUID = { "Caster", "Melee", "Caster" },
}

function NP:CheckRole()
	local roles = CLASS_ROLE[E.myclass]
	if type(roles) == "string" then
		self.role = roles
		return
	end
	local tree, most = nil, 0
	local t
	for t = 1, 3 do
		local ok, _, _, spent = pcall(GetTalentTabInfo, t)
		if ok and type(spent) == "number" and spent > most then tree, most = t, spent end
	end
	local role = roles and tree and roles[tree] or "Melee"
	if E.myclass == "DRUID" and tree == 2 then
		local ok, _, _, _, _, rank = pcall(GetTalentInfo, 2, 22)
		if ok and type(rank) == "number" and rank > 0 then role = "Tank" end
	end
	self.role = role
end

-- Real ElvUI's GetThreatSituationColor / GetThreatSituationScale: a tank
-- wants the mob on it, anyone else wants it elsewhere. Status 3 securely
-- tanking, 2 tanking with someone above, 1 above the one tanking, 0 not
-- tanking; the transitions keep the normal scale.
function NP:ThreatColor(status)
	local db = self.db.threat
	local tank = self.role == "Tank"
	if status == 3 then
		return tank and db.goodColor or db.badColor
	elseif status == 2 then
		return tank and db.badTransition or db.goodTransition
	elseif status == 1 then
		return tank and db.goodTransition or db.badTransition
	end
	return tank and db.badColor or db.goodColor
end

local function ThreatScale(frame)
	local status = frame.threatStatus
	if not status or status == 1 or status == 2 then return 1 end
	local db = NP.db.threat
	if (status == 3) == (NP.role == "Tank") then return db.goodScale end
	return db.badScale
end

local function ClassColor(frame)
	local class = frame.UnitClass
	if not class or not E.private.general.classCache then return nil end
	return (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or RAID_CLASS_COLORS[class]
end

local function IsPlayerType(frame)
	return frame.UnitType == "FRIENDLY_PLAYER" or frame.UnitType == "ENEMY_PLAYER"
end

-- Real ElvUI's UpdateElement_HealthColor: class colour for players (when
-- the class is known), the tapped colour, then threat colours when threat
-- coloring is on and the plate has a threat state, else the reaction.
function NP:UpdateHealthColor(frame)
	local c
	if IsPlayerType(frame) and UnitDB(frame).healthbar.useClassColor then c = ClassColor(frame) end
	if not c and frame.UnitReaction ~= 1 and frame.threatStatus and self.db.threat.useThreatColor then
		c = self:ThreatColor(frame.threatStatus)
	end
	if not c then c = ReactionColor(frame) end
	Util.SetStatusBarColor(frame.HealthBar, c.r, c.g, c.b, 1)
end

-- Real ElvUI's UpdateElement_Name. A player whose class the class cache
-- does not know takes the friendly player colour, as in real ElvUI.
function NP:UpdateName(frame)
	local db = UnitDB(frame)
	local name = frame.Name
	if not db.showName then
		name:SetText("")
		return
	end
	name:SetText(frame.UnitName)
	name.NameOnlyGlow:SetWidth(name:GetWidth() + 40)
	name.NameOnlyGlow:SetHeight(name:GetHeight() + 16)

	local r, g, b = 1, 1, 1
	if IsPlayerType(frame) and db.name and db.name.useClassColor then
		local c = ClassColor(frame) or self.db.reactions.friendlyPlayer
		r, g, b = c.r, c.g, c.b
	elseif not db.healthbar.enable and not frame.isTarget then
		local c = ReactionColor(frame)
		r, g, b = c.r, c.g, c.b
	end
	name:SetTextColor(r, g, b)

	local glow = name.NameOnlyGlow.texture
	if self.db.nameColoredGlow then
		glow:SetVertexColor(r - 0.1, g - 0.1, b - 0.1, 1)
	else
		SetColor(glow, self.db.colors.glowColor)
	end
end

-- Real ElvUI's UnitLevel: "??" in red for bosses and unknown levels, else the
-- native level in its difficulty colour.
function NP:UpdateLevel(frame)
	local level = frame.Level
	local text = NativeText(frame.oldLevel)
	frame.levelText = text
	if not UnitDB(frame).showLevel then
		level:SetText("")
		return
	end
	local r, g, b = 0.9, 0, 0
	if IsShown(frame.BossIcon) or not tonumber(text) then
		text = "??"
	else
		local ok, lr, lg, lb = pcall(frame.oldLevel.GetTextColor, frame.oldLevel)
		if ok and type(lr) == "number" then r, g, b = lr, lg, lb end
	end
	if frame.healthShown then
		level:SetText(text)
	else
		level:SetText(" [" .. text .. "]")
	end
	level:SetTextColor(r, g, b)
end

-- Real ElvUI's UpdateElement_Highlight, with the current ElvUI health layer.
function NP:UpdateHighlight(frame)
	local glow, layer = frame.Name.NameOnlyGlow, frame.HealthBar.highlight
	glow:Hide()
	layer:Hide()
	if not frame.isMouseover or frame.isTarget then return end
	if frame.healthShown then
		layer:Show()
	elseif UnitDB(frame).showName then
		glow:Show()
	end
end

-- Real ElvUI's glow choice: the indicator colour on the target, otherwise
-- yellow at or below the low health threshold and red at or below half of
-- it. Low health shows the glows only, never the arrows.
local function GlowState(frame)
	local db = NP.db
	if frame.isTarget and db.units.TARGET.glowStyle ~= "none" then
		local c = db.colors.glowColor
		return 1, c.r, c.g, c.b, c.a or 1
	end
	local threshold = db.lowHealthThreshold or 0
	if threshold <= 0 or not frame.healthMax then return 0 end
	local perc = frame.healthValue / frame.healthMax
	if perc <= threshold / 2 then return 2, 1, 0, 0, 1 end
	if perc <= threshold then return 2, 1, 1, 0, 1 end
	return 0
end

local BORDER_GLOW = { style1 = true, style5 = true, style7 = true }
local BACKGROUND_GLOW = { style2 = true, style6 = true, style8 = true }
local TOP_ARROW = { style3 = true, style5 = true, style6 = true }
local SIDE_ARROWS = { style4 = true, style7 = true, style8 = true }

local function SetArrow(frame, key, path, size)
	local arrow = frame[key]
	local c = ARROW_COORDS[key]
	arrow.texture:SetTexture(path)
	arrow.texture:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
	arrow:SetWidth(size)
	arrow:SetHeight(size)
	arrow:ClearAllPoints()
	return arrow
end

local function PlaceGlows(frame, state)
	local db = NP.db
	local target = db.units.TARGET
	local style, bar = target.glowStyle, frame.HealthBar
	if BORDER_GLOW[style] then
		-- Around the cast bar and its icon too while one is shown close below.
		local bottom = bar
		if frame.CastBar:IsShown() and UnitDB(frame).castbar.offset < 4 then
			bottom = frame.CastBar.Icon
		end
		frame.Glow:ClearAllPoints()
		frame.Glow:SetPoint("TOPLEFT", bar, "TOPLEFT", -6, 6)
		frame.Glow:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 6, -6)
		frame.Glow:Show()
	end
	if BACKGROUND_GLOW[style] then
		-- Real ElvUI reaches down over a shown cast bar and out over its icon.
		local castBar = frame.CastBar:IsShown() and frame.CastBar
		local scale = 1
		if db.useTargetScale then scale = math.max(db.targetScale, 0.75) end
		local size = (BORDER + 14 + (castBar and 3 or 0)) * scale
		frame.Glow2:ClearAllPoints()
		frame.Glow2:SetPoint("TOPLEFT", bar, "TOPLEFT", -(size * 2), size)
		frame.Glow2:SetPoint("BOTTOMRIGHT", castBar and castBar.Icon or bar, "BOTTOMRIGHT", size * 2, -size)
		frame.Glow2:Show()
	end
	if state == 2 then return end
	-- Real ElvUI: the arrows `arrowSpacing` away from the bar; the top one
	-- also clears the name, which sits above the bar here.
	local path = ARROWS .. (target.arrow or "Arrow9")
	local size = ARROW_SIZE * (target.arrowScale or 1)
	local spacing = target.arrowSpacing or 0
	if TOP_ARROW[style] then
		local space = spacing
		if UnitDB(frame).showName and frame.UnitName ~= "" then space = space + db.fontSize end
		SetArrow(frame, "TopArrow", path, size):SetPoint("BOTTOM", bar, "TOP", 0, space)
		frame.TopArrow:Show()
	end
	if SIDE_ARROWS[style] then
		SetArrow(frame, "RightArrow", path, size):SetPoint("RIGHT", bar, "LEFT", -spacing, 0)
		SetArrow(frame, "LeftArrow", path, size):SetPoint("LEFT", bar, "RIGHT", spacing, 0)
		frame.RightArrow:Show()
		frame.LeftArrow:Show()
	end
end

function NP:UpdateGlow(frame)
	local state, r, g, b, a = 0
	if frame.healthShown then state, r, g, b, a = GlowState(frame) end
	local cast = frame.CastBar:IsShown() and "cast" or ""
	local key = state ~= 0 and (state .. r .. g .. b .. a .. self.db.units.TARGET.glowStyle .. cast) or nil
	if key == frame.glowKey then return end
	frame.glowKey = key

	frame.Glow:Hide()
	frame.Glow2:Hide()
	frame.TopArrow:Hide()
	frame.LeftArrow:Hide()
	frame.RightArrow:Hide()
	if state == 0 then return end

	PlaceGlows(frame, state)
	pcall(frame.Glow.SetBackdropBorderColor, frame.Glow, r, g, b, a)
	frame.Glow2.texture:SetVertexColor(r, g, b, a)
	frame.TopArrow.texture:SetVertexColor(r, g, b, a)
	frame.LeftArrow.texture:SetVertexColor(r, g, b, a)
	frame.RightArrow.texture:SetVertexColor(r, g, b, a)
end

-- Real ElvUI's cast time formats.
local function FormatCastTime(style, value, max)
	if style == "CURRENT" then return string.format("%.1f", value) end
	if style == "CURRENT_MAX" then return string.format("%.1f / %.1f", value, max) end
	return string.format("%.1f", max - value)
end

local function HideCast(frame)
	local bar = frame.CastBar
	bar.spell, bar.startTime, bar.holdUntil = nil, nil, nil
	if bar:IsShown() then
		bar:Hide()
		NP:UpdateGlow(frame)
	end
end

local function StartCast(frame, spell, startTime, endTime, icon)
	local bar = frame.CastBar
	bar.spell, bar.startTime, bar.endTime = spell, startTime, endTime
	bar.holdUntil = nil
	bar:SetMinMaxValues(0, endTime - startTime)
	bar.Name:SetText(spell)
	bar.Icon.texture:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	bar.Spark:Show()
	if not bar:IsShown() then
		bar:Show()
		NP:UpdateGlow(frame)
	end
end

-- The cast ended without a new one: "Interrupted" for the hold time when the
-- combat log reported it broken off, otherwise the bar goes away. The client
-- reports no failed casts of other units.
local function EndCast(frame, now)
	local bar = frame.CastBar
	local hold = UnitDB(frame).castbar.timeToHold
	local brokeAt = UF and UF:GetCastBreak(frame.UnitName)
	if hold > 0 and brokeAt and bar.startTime and brokeAt >= bar.startTime then
		local _, max = bar:GetMinMaxValues()
		bar.spell, bar.startTime = nil, nil
		bar.holdUntil = now + hold
		bar:SetValue(max)
		bar.Name:SetText(INTERRUPTED or L["Interrupted"])
		bar.Time:SetText("")
		bar.Spark:Hide()
		return
	end
	HideCast(frame)
end

-- Casts of other units come from the combat log by caster name
-- (UnitFrames/CastTracker.lua), so every plate showing that name shows the
-- cast; same-named units cannot be told apart. Channels are not reported.
function NP:UpdateCast(frame)
	local bar = frame.CastBar
	if not frame.healthShown or not UnitDB(frame).castbar.enable or not UF then
		if bar:IsShown() then HideCast(frame) end
		return
	end
	local now = GetTime()
	local spell, startTime, endTime, icon = UF:GetCastByName(frame.UnitName)
	if spell then
		if spell ~= bar.spell or startTime ~= bar.startTime then
			StartCast(frame, spell, startTime, endTime, icon)
		end
		local max = endTime - startTime
		if max <= 0 then max = 0.001 end
		local value = now - startTime
		if value > max then value = max end
		bar:SetValue(value)
		bar.Time:SetText(FormatCastTime(UnitDB(frame).castbar.castTimeFormat, value, max))
		bar.Spark:SetPoint("CENTER", bar, "LEFT", value / max * bar:GetWidth(), 0)
	elseif bar.spell then
		EndCast(frame, now)
	elseif bar.holdUntil and now >= bar.holdUntil then
		HideCast(frame)
	end
end

-- Buffs and debuffs, after pfUI's nameplates: a plate carries no unit, so
-- its auras are read while it is the target or under the mouse, and kept on
-- the plate until they run out; the plate shows the kept lists the rest of
-- the time. A list is dropped when the plate shows another name. Debuff
-- names and times come from LibVanillaDurations-1.0, where "mine" is the
-- stamp of the player's own cast (UnitFrames/OwnAuras.lua). Buff names come
-- from a tooltip scan; a buff has a time only when the player cast it
-- (OwnAuras), and that also makes it "mine". Auras without a known duration
-- are kept only while the unit is read live. Filtering is real ElvUI's
-- `filters` (UnitFrames/AuraFilter.lua).
local function LiveUnit(frame)
	if frame.isTarget and UnitName("target") == frame.UnitName then return "target" end
	if frame.isMouseover and UnitName("mouseover") == frame.UnitName then return "mouseover" end
	return nil
end

local function IsFriendly(frame)
	return frame.UnitType == "FRIENDLY_PLAYER" or frame.UnitType == "FRIENDLY_NPC"
end

local scanTip

-- First line of the buff's tooltip. The owner is set on every scan: the
-- Hide at the end clears it, and on the 1.12 client an unowned tooltip is
-- not filled.
local function ScanBuffName(unit, index)
	if not scanTip then
		local ok, tip = pcall(CreateFrame, "GameTooltip", SCAN_TIP, nil, "GameTooltipTemplate")
		if not ok or not tip then return nil end
		scanTip = tip
	end
	pcall(scanTip.SetOwner, scanTip, UIParent, "ANCHOR_NONE")
	pcall(scanTip.ClearLines, scanTip)
	local name
	if pcall(scanTip.SetUnitBuff, scanTip, unit, index) then
		local line = _G[SCAN_TIP .. "TextLeft1"]
		name = line and line:GetText()
	end
	pcall(scanTip.Hide, scanTip)
	if name == "" then name = nil end
	return name
end

-- Buff names per slot, scanned again only when the slot's texture or the
-- unit's name changes.
local function BuffName(row, unit, unitName, index, texture)
	local slot = row.names[index]
	if not slot or slot.texture ~= texture or slot.unitName ~= unitName then
		slot = { texture = texture, unitName = unitName, name = ScanBuffName(unit, index) }
		row.names[index] = slot
	end
	return slot.name
end

local function StartCollect(frame, row)
	local cache = Compat.wipe(row.cache)
	row.cacheName = frame.UnitName
	return cache, UnitDB(frame)[row.key].filters, IsFriendly(frame)
end

local function CollectDebuffs(frame, unit, now)
	local cache, filters, friendly = StartCollect(frame, frame.Debuffs)
	local unitName = UnitName(unit)
	local i
	for i = 1, MAX_DEBUFFS do
		local ok, texture, count, dispelType = pcall(UnitDebuff, unit, i)
		if ok and texture then
			local name, left, duration = LVD:GetDebuff(unit, i)
			local _, _, mine = LVD:GetStamp(unitName, name)
			if name and UF:AuraPasses(filters, name, mine, friendly, duration, E:IsDispellableByMe(dispelType)) then
				table.insert(cache, {
					texture = texture,
					count = tonumber(count) or 0,
					expiration = left and (now + left) or nil,
				})
			end
		end
	end
end

local function CollectBuffs(frame, unit, now)
	local row = frame.Buffs
	local cache, filters, friendly = StartCollect(frame, row)
	local unitName = UnitName(unit)
	local i
	for i = 1, MAX_BUFFS do
		local ok, texture, count = pcall(UnitBuff, unit, i)
		if not ok or not texture then break end
		local name = BuffName(row, unit, unitName, i, texture)
		local left, duration
		if name and UF.GetOwnAuraTimeLeft then left, duration = UF:GetOwnAuraTimeLeft(unitName, name) end
		if name and UF:AuraPasses(filters, name, left ~= nil, friendly, duration) then
			table.insert(cache, {
				texture = texture,
				count = tonumber(count) or 0,
				expiration = left and (now + left) or nil,
			})
		end
	end
end

-- The kept list without the auras that ran out or have no time; called
-- while the unit is not read live.
local function PruneAuras(frame, row, now)
	local cache = row.cache
	if row.cacheName ~= frame.UnitName then
		Compat.wipe(cache)
		return
	end
	local i = getn(cache)
	while i > 0 do
		local aura = cache[i]
		if not aura.expiration or aura.expiration <= now then
			table.remove(cache, i)
		end
		i = i - 1
	end
end

-- Real ElvUI's aura time text: whole units with their suffix, tenths in red
-- under 4 seconds.
local function SetAuraTime(aura, left)
	if not left then
		aura.timeLeft:SetText("")
		return
	end
	local value, id = E:GetTimeInfo(left, 4)
	local color = E.TimeColors[id] or E.TimeColors[3]
	local format = E.TimeFormats[id] and E.TimeFormats[id][2] or "%d"
	aura.timeLeft:SetText(string.format(format, value))
	aura.timeLeft:SetTextColor(color[1], color[2], color[3])
end

-- Fills the row's icons from its kept list; returns how many are shown.
local function DrawAuras(frame, row, now)
	local icons, cache = row.icons, row.cache
	local limit = UnitDB(frame)[row.key].numAuras
	local shown = 0
	local i
	for i = 1, getn(icons) do
		local aura, data = icons[i], cache[i]
		if data and i <= limit then
			aura.icon:SetTexture(data.texture)
			if data.count > 1 then aura.count:SetText(data.count) else aura.count:SetText("") end
			SetAuraTime(aura, data.expiration and (data.expiration - now))
			aura:Show()
			shown = shown + 1
		else
			aura:Hide()
		end
	end
	return shown
end

-- ElvUI-vanilla: the debuff row sits above the name and the buff row above
-- the debuffs, or in the debuffs' place while no debuff is shown.
local function AuraRowOffset(frame)
	local offset = 3
	if UnitDB(frame).showName then offset = offset + NP.db.fontSize + 5 end
	return offset
end

local function AnchorAuraRow(frame, row, above)
	row:ClearAllPoints()
	if above then
		row:SetPoint("BOTTOMLEFT", above, "TOPLEFT", 0, 3)
		row:SetPoint("BOTTOMRIGHT", above, "TOPRIGHT", 0, 3)
	else
		local offset = AuraRowOffset(frame)
		row:SetPoint("BOTTOMLEFT", frame.HealthBar, "TOPLEFT", 0, offset)
		row:SetPoint("BOTTOMRIGHT", frame.HealthBar, "TOPRIGHT", 0, offset)
	end
end

local function PlaceBuffs(frame, aboveDebuffs)
	if frame.buffsAbove == aboveDebuffs then return end
	frame.buffsAbove = aboveDebuffs
	AnchorAuraRow(frame, frame.Buffs, aboveDebuffs and frame.Debuffs or nil)
end

-- The client hands a native plate to another unit once its unit dies or
-- leaves the plate range, and hides it in between (Unreal Azeroth: a plate
-- whose unit is merely off screen stays shown). The auras the plate kept are
-- dropped then, and when its health reads 0, so a later unit of the same
-- name does not inherit them.
local function ForgetUnit(frame)
	local rows = { frame.Buffs, frame.Debuffs }
	local i
	for i = 1, 2 do
		Compat.wipe(rows[i].cache)
		rows[i].cacheName = nil
	end
	frame.auraNext = 0
end

function NP:UpdateAuras(frame, now)
	local buffs, debuffs = frame.Buffs, frame.Debuffs
	if not (buffs.enabled or debuffs.enabled) or now < (frame.auraNext or 0) then return end
	frame.auraNext = now + AURA_INTERVAL
	local unit = LiveUnit(frame)
	local numDebuffs = 0
	if debuffs.enabled then
		if unit and LVD then CollectDebuffs(frame, unit, now) else PruneAuras(frame, debuffs, now) end
		numDebuffs = DrawAuras(frame, debuffs, now)
	end
	if buffs.enabled then
		if unit then CollectBuffs(frame, unit, now) else PruneAuras(frame, buffs, now) end
		DrawAuras(frame, buffs, now)
		PlaceBuffs(frame, numDebuffs > 0)
	end
end

-- 1.12.1 and Unreal Azeroth take no arguments; the two-argument form of
-- later clients is only a fallback.
local function ReadComboPoints()
	local ok, points = pcall(GetComboPoints)
	if ok and tonumber(points) then return tonumber(points) end
	ok, points = pcall(GetComboPoints, "player", "target")
	return (ok and tonumber(points)) or 0
end

-- Real ElvUI's UpdateElement_CPoints: the player's combo points on the
-- target's plate, hostile plates only, coloured by real ElvUI's
-- comboBar.colors.
function NP:UpdateComboPoints(frame)
	local holder = frame.CPoints
	local points = 0
	if self.db.comboPoints and frame.isTarget and frame.healthShown
		and frame.UnitType ~= "FRIENDLY_PLAYER" and frame.UnitType ~= "FRIENDLY_NPC" then
		points = self.comboPoints or 0
	end
	if points == frame.comboShown then return end
	frame.comboShown = points
	if points <= 0 then
		holder:Hide()
		return
	end
	local colors = self.db.comboBar.colors
	local i
	for i = 1, MAX_COMBO do
		local c = colors[i]
		if c then holder[i]:SetVertexColor(c.r, c.g, c.b) end
		if i <= points then holder[i]:Show() else holder[i]:Hide() end
	end
	holder:Show()
end

-- Real ElvUI's non-target transparency. On the 1.12.1 client the dimmed
-- plate's own alpha multiplies with it, as in ElvUI-vanilla.
function NP:UpdateAlpha(frame)
	if self.hasTarget and not frame.isTarget then
		frame:SetAlpha(self.db.nonTargetTransparency)
	else
		frame:SetAlpha(1)
	end
end

-- ---------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------
local function ConfigureHealthBar(frame)
	local db = NP.db
	local unitDB = UnitDB(frame).healthbar
	local bar = frame.HealthBar
	if not frame.healthShown then
		bar:Hide()
		return
	end

	-- Real ElvUI: the target scale on the target, the threat scale on the rest.
	local scale = ThreatScale(frame)
	if frame.isTarget and db.useTargetScale then scale = db.targetScale end
	bar:ClearAllPoints()
	bar:SetPoint("TOP", frame, "CENTER", 0, UnitDB(frame).castbar.height + 3)
	bar:SetWidth(unitDB.width * scale)
	bar:SetHeight(unitDB.height * scale)
	Util.SetStatusBarTexture(bar, Fetch("statusbar", db.statusbar))

	local general = E.db.general
	Util.SetStatusBarBackgroundColor(bar, general.backdropfadecolor.r, general.backdropfadecolor.g, general.backdropfadecolor.b, general.backdropfadecolor.a)
	local i
	for i = 1, 4 do
		SetColor(bar.borderLines[i], general.bordercolor)
	end

	E:FontTemplate(bar.text, Fetch("font", db.font), db.fontSize, db.fontOutline)
	bar:Show()
end

local function ConfigureTexts(frame)
	local db = NP.db
	local font = Fetch("font", db.font)
	local name, level, bar = frame.Name, frame.Level, frame.HealthBar
	E:FontTemplate(name, font, db.fontSize, db.fontOutline)
	E:FontTemplate(level, font, db.fontSize, db.fontOutline)
	name:ClearAllPoints()
	level:ClearAllPoints()
	if frame.healthShown then
		level:SetJustifyH("RIGHT")
		level:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, BORDER * 2)
		name:SetJustifyH("LEFT")
		name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, BORDER * 2)
		name:SetPoint("BOTTOMRIGHT", level, "BOTTOMLEFT", 0, 0)
	else
		name:SetJustifyH("CENTER")
		name:SetPoint("BOTTOM", frame, "CENTER", 0, 0)
		level:SetJustifyH("LEFT")
		level:SetPoint("LEFT", name, "RIGHT", 0, 0)
	end
end

-- Real ElvUI's ConfigureElement_CastBar, the icon always on the right (its
-- iconPosition setting is not read there either).
local function ConfigureCastBar(frame)
	local db = NP.db
	local unitDB = UnitDB(frame)
	local castDB = unitDB.castbar
	local bar, health = frame.CastBar, frame.HealthBar
	local font = Fetch("font", db.font)

	-- Sized explicitly rather than by a second anchor: the fill is laid out
	-- from GetWidth, which the 1.12.1 client reports scaled for frames sized
	-- by their anchors.
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -castDB.offset)
	bar:SetWidth(health:GetWidth())
	bar:SetHeight(castDB.height)
	Util.SetStatusBarTexture(bar, Fetch("statusbar", db.statusbar))
	Util.SetStatusBarColor(bar, db.castColor.r, db.castColor.g, db.castColor.b, 1)

	local general = E.db.general
	local fade = general.backdropfadecolor
	Util.SetStatusBarBackgroundColor(bar, fade.r, fade.g, fade.b, fade.a)
	local i
	for i = 1, 4 do
		SetColor(bar.borderLines[i], general.bordercolor)
		SetColor(bar.Icon.borderLines[i], general.bordercolor)
	end

	local icon = bar.Icon
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", health, "TOPRIGHT", castDB.offset, 0)
	icon:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", castDB.offset, 0)
	icon:SetWidth(castDB.height + unitDB.healthbar.height + castDB.offset)

	bar.Spark:SetWidth(15)
	bar.Spark:SetHeight(castDB.height * 2)

	E:FontTemplate(bar.Name, font, db.fontSize, db.fontOutline)
	E:FontTemplate(bar.Time, font, db.fontSize, db.fontOutline)
	bar.Time:ClearAllPoints()
	bar.Time:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -BORDER * 3)
	bar.Time:SetJustifyH("RIGHT")
	bar.Name:ClearAllPoints()
	bar.Name:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -BORDER * 3)
	bar.Name:SetPoint("TOPRIGHT", bar.Time, "TOPLEFT", 0, 0)
	bar.Name:SetJustifyH("LEFT")
	if castDB.hideSpellName then bar.Name:Hide() else bar.Name:Show() end
	if castDB.hideTime then bar.Time:Hide() else bar.Time:Show() end

	bar.spell, bar.startTime, bar.holdUntil = nil, nil, nil
	bar:Hide()
end

-- Real ElvUI's aura row: as wide as the health bar, the icons sharing that
-- width. Icons scale with the target health bar. The rows are anchored by
-- AnchorAuraRow / PlaceBuffs.
local function ConfigureAuraRow(frame, row)
	local db = NP.db
	local auraDB = UnitDB(frame)[row.key]
	local health = frame.HealthBar
	if not frame.healthShown or not auraDB or not auraDB.enable then
		row.enabled = nil
		row:Hide()
		return
	end

	local count = auraDB.numAuras
	local scale = 1
	if frame.isTarget and db.useTargetScale then scale = db.targetScale end
	local width = (health:GetWidth() - count) / count - 3
	local height = (auraDB.baseHeight or AURA_HEIGHT) * scale
	local font = Fetch("font", db.font)
	local general = E.db.general

	local icons = row.icons
	local i
	for i = 1, count do
		local aura = icons[i] or ConstructAuraIcon(row)
		icons[i] = aura
		aura:ClearAllPoints()
		if i == 1 and row.side == "LEFT" then
			aura:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
		elseif i == 1 then
			aura:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
		elseif row.side == "LEFT" then
			aura:SetPoint("LEFT", icons[i - 1], "RIGHT", AURA_SPACING, 0)
		else
			aura:SetPoint("RIGHT", icons[i - 1], "LEFT", -AURA_SPACING, 0)
		end
		aura:SetWidth(width)
		aura:SetHeight(height)
		E:FontTemplate(aura.timeLeft, font, db.fontSize, db.fontOutline)
		E:FontTemplate(aura.count, font, db.fontSize, db.fontOutline)
		local j
		for j = 1, 4 do SetColor(aura.borderLines[j], general.bordercolor) end
	end
	for i = count + 1, getn(icons) do icons[i]:Hide() end

	row:SetHeight(height)
	row.enabled = true
	row:Show()
end

local function ConfigureAuras(frame)
	ConfigureAuraRow(frame, frame.Debuffs)
	ConfigureAuraRow(frame, frame.Buffs)
	AnchorAuraRow(frame, frame.Debuffs, nil)
	frame.buffsAbove = nil
	frame.auraNext = 0
end

local function ConfigureRaidIcon(frame)
	local icon = frame.RaidIcon
	if not icon then return end
	pcall(icon.ClearAllPoints, icon)
	if frame.healthShown then
		pcall(icon.SetPoint, icon, "RIGHT", frame.HealthBar, "LEFT", -6, 0)
	else
		pcall(icon.SetPoint, icon, "BOTTOM", frame.Name, "TOP", 0, 3)
	end
end

-- Strata and level of one of the plate's frames; a nil strata keeps the
-- frame's own.
local function Place(f, strata, level)
	if strata then f:SetFrameStrata(strata) end
	f:SetFrameLevel(level)
end

-- The strata names SetFrameStrata accepts. The 1.12.1 client reports a
-- native plate's strata as "UNKNOWN", which SetFrameStrata rejects with an
-- error.
local STRATA = {
	BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true,
	DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}

-- Every frame of the plate takes the native plate's strata (BACKGROUND on
-- Unreal Azeroth; the 1.12.1 client reports none, and the frames keep
-- their own there): a frame created as its child gets MEDIUM on UA, the
-- strata of the action bars and most of the UI, and its levels would then
-- interleave with theirs. Within that strata the target is raised above
-- every other plate, as in real ElvUI. Every child frame is set again with
-- it: on Unreal Azeroth a child frame left at or below its parent's level is
-- not drawn. The target indicators and the name-only glow take the lowest
-- level, behind the bars and the text.
local function ConfigureLevels(frame)
	local plate = frame.plate
	local ok, base = pcall(plate.GetFrameLevel, plate)
	if not ok or type(base) ~= "number" then base = 0 end
	local okStrata, strata = pcall(plate.GetFrameStrata, plate)
	if not okStrata or not STRATA[strata] then strata = nil end
	local level = base + 1
	if frame.isTarget then level = level + TARGET_LEVEL end
	Place(frame, strata, level)
	Place(frame.Glow, strata, level + 1)
	Place(frame.Glow2, strata, level + 1)
	Place(frame.TopArrow, strata, level + 1)
	Place(frame.LeftArrow, strata, level + 1)
	Place(frame.RightArrow, strata, level + 1)
	Place(frame.Name.NameOnlyGlow, strata, level + 1)
	Place(frame.TextHolder, strata, level + 2)
	Place(frame.Buffs, strata, level + 2)
	Place(frame.Debuffs, strata, level + 2)
	Place(frame.CastBar, strata, level + 2)
	Place(frame.CastBar.Icon, strata, level + 3)
	Place(frame.CastBar.Spark, strata, level + 3)
	Place(frame.HealthBar, strata, level + 2)
	Place(frame.HealthBar.textHolder, strata, level + 3)
	Place(frame.CPoints, strata, level + 4)
	local i
	for i = 1, getn(frame.Buffs.icons) do
		Place(frame.Buffs.icons[i], strata, level + 3)
	end
	for i = 1, getn(frame.Debuffs.icons) do
		Place(frame.Debuffs.icons[i], strata, level + 3)
	end
end

function NP:ConfigurePlate(frame)
	local unitDB = UnitDB(frame)
	frame.healthShown = unitDB.healthbar.enable or (frame.isTarget and self.db.alwaysShowTargetHealth)
	frame.uiScale = uiScale
	frame:SetScale(ScaleFactor(frame.plate))
	-- `false`, not nil: UpdateGlow's key for "no glow" is nil, and the
	-- indicators shown before the re-layout must still be hidden.
	frame.glowKey = false
	frame.dirty = nil

	MuteNative(frame)
	ConfigureHealthBar(frame)
	ConfigureCastBar(frame)
	ConfigureAuras(frame)
	ConfigureTexts(frame)
	ConfigureRaidIcon(frame)
	ConfigureLevels(frame)

	if frame.healthShown then
		self:UpdateHealth(frame)
		Util.RefreshStatusBar(frame.HealthBar)
		self:UpdateHealthColor(frame)
	end
	self:UpdateName(frame)
	self:UpdateLevel(frame)
	self:UpdateHighlight(frame)
	self:UpdateCast(frame)
	self:UpdateAuras(frame, GetTime())
	frame.comboShown = nil
	self:UpdateComboPoints(frame)
	self:UpdateGlow(frame)
	self:UpdateAlpha(frame)
end

-- ---------------------------------------------------------------------
-- Update loop
-- ---------------------------------------------------------------------
function NP:ScanPlates()
	local count = WorldFrame:GetNumChildren()
	if count == numChildren then return end
	numChildren = count
	local kids = { WorldFrame:GetChildren() }
	local i
	for i = 1, getn(kids) do
		local frame = kids[i]
		if not frame.UnitFrame and IsNamePlate(frame) then
			self:OnCreated(frame)
		end
	end
end

-- Per-frame values that do not need a new layout.
function NP:RefreshPlate(frame)
	if frame.healthShown then
		local value, high = NativeHealth(frame)
		if value ~= frame.healthValue or high ~= frame.healthMax then
			if value <= 0 then ForgetUnit(frame) end
			self:UpdateHealth(frame)
			self:UpdateGlow(frame)
		end
	end
	if NativeText(frame.oldLevel) ~= frame.levelText then
		self:UpdateLevel(frame)
	end
	local mouseover = IsShown(frame.oldHighlight)
	if mouseover ~= frame.isMouseover then
		frame.isMouseover = mouseover
		self:UpdateHighlight(frame)
	end
	if frame.hasTarget ~= self.hasTarget then
		frame.hasTarget = self.hasTarget
		self:UpdateAlpha(frame)
	end
	self:UpdateCast(frame)
	self:UpdateAuras(frame, GetTime())
	self:UpdateComboPoints(frame)
	KeepMuted(frame)
end

-- Unreal Azeroth does not hide an addon frame with its hidden native plate:
-- the frame stays drawn where the client parks the plate (the left screen
-- edge), so it is hidden and shown here along with the plate, and also while
-- the plate is held at a screen edge.
function NP:UpdatePlate(frame)
	local shown = IsShown(frame.plate)
	if not shown and frame.plateShown then ForgetUnit(frame) end
	frame.plateShown = shown
	if not shown or AtScreenEdge(frame.plate) then
		if frame.active then
			frame.active = nil
			frame:Hide()
		end
		return
	end
	local name = NativeText(frame.oldName)
	local reaction, unitType = UnitInfo(frame)
	local isTarget = self.hasTarget and IsLit(frame.plate)
	-- Real ElvUI: a hostile "NPC" the class cache knows is an enemy player.
	local class
	if unitType ~= "FRIENDLY_NPC" and E.ClassCache then class = E.ClassCache:GetClassByName(name) end
	if unitType == "ENEMY_NPC" and class then unitType = "ENEMY_PLAYER" end
	local threat
	if unitType == "ENEMY_NPC" or unitType == "ENEMY_PLAYER" then
		threat = ThreatStatus(name)
	end
	if frame.dirty or not frame.active or name ~= frame.UnitName or unitType ~= frame.UnitType
		or reaction ~= frame.UnitReaction or isTarget ~= frame.isTarget or frame.uiScale ~= uiScale
		or class ~= frame.UnitClass or threat ~= frame.threatStatus then
		frame.active = true
		frame.UnitName = name
		frame.UnitType = unitType
		frame.UnitReaction = reaction
		frame.UnitClass = class
		frame.threatStatus = threat
		frame.isTarget = isTarget
		frame.isMouseover = IsShown(frame.oldHighlight)
		frame.hasTarget = self.hasTarget
		frame:Show()
		self:ConfigurePlate(frame)
		return
	end
	self:RefreshPlate(frame)
end

-- A failing plate update is reported once, not on every frame.
local reported

local function OnUpdate()
	NP:ScanPlates()
	NP.hasTarget = Compat.bool(UnitExists("target"))
	NP.comboPoints = NP.hasTarget and ReadComboPoints() or 0
	uiScale = ReadUIScale()
	ScanThreat(GetTime())
	local i
	for i = 1, getn(plates) do
		local ok, err = pcall(NP.UpdatePlate, NP, plates[i])
		if not ok and not reported then
			reported = true
			local handler = geterrorhandler and geterrorhandler() or _ERRORMESSAGE
			if handler then handler(err) end
		end
	end
end

-- Re-applies the layout of every plate on its next update; the config calls
-- this after a change.
function NP:ConfigureAll()
	self.db = E.db.nameplates
	if not self.Frame then return end
	local i
	for i = 1, getn(plates) do
		plates[i].dirty = true
	end
end

-- Real ElvUI's combat toggles: TOGGLE_ON shows the plates in combat and hides
-- them out of it, TOGGLE_OFF the other way round, DISABLED leaves them.
local function ApplyCombatToggle(setting, inCombat, show, hide)
	if setting == "TOGGLE_ON" then
		if inCombat then show() else hide() end
	elseif setting == "TOGGLE_OFF" then
		if inCombat then hide() else show() end
	end
end

local function ApplyCombatToggles(inCombat)
	local db = NP.db
	if ShowFriendNameplates and HideFriendNameplates then
		ApplyCombatToggle(db.showFriendlyCombat, inCombat, ShowFriendNameplates, HideFriendNameplates)
	end
	if ShowNameplates and HideNameplates then
		ApplyCombatToggle(db.showEnemyCombat, inCombat, ShowNameplates, HideNameplates)
	end
end

function NP:PLAYER_REGEN_DISABLED()
	ApplyCombatToggles(true)
end

function NP:PLAYER_REGEN_ENABLED()
	ApplyCombatToggles(false)
end

function NP:CHARACTER_POINTS_CHANGED()
	self:CheckRole()
	self:ConfigureAll()
end

-- The client does not remember whether enemy nameplates were shown (the V
-- key), so they start hidden every session; the module turns them on after
-- each loading screen unless the enemy combat toggle decides. Friendly
-- plates (Shift-V) are left to the player and the friendly combat toggle.
function NP:PLAYER_ENTERING_WORLD()
	if self.db.showEnemyCombat == "DISABLED" and ShowNameplates then ShowNameplates() end
	ApplyCombatToggles(Compat.bool(UnitAffectingCombat("player")))
	self:CheckRole()
end

function NP:Initialize()
	self.db = E.db.nameplates
	if not E.private.nameplates.enable then return end

	self.hasTarget = false
	-- The cast tracker is shared with the target cast bar and starts once,
	-- whichever of the two asks first.
	UF = E.UnitFrames
	if UF and UF.InitializeCastTracker then UF:InitializeCastTracker() end
	self.Frame = CreateFrame("Frame")
	self.Frame:SetScript("OnUpdate", OnUpdate)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("CHARACTER_POINTS_CHANGED")
	self:PLAYER_ENTERING_WORLD()
	E.NamePlates = self
end

local function InitializeCallback()
	NP:Initialize()
end

E:RegisterInitialModule(NP:GetName(), InitializeCallback)
