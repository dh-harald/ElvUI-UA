local E, L, V, P, G = unpack(ElvUI)
local S = E:GetModule("Skins")

-- Skins > Blizzard > NamePlates -- the native nameplates restyled in place to
-- look like real ElvUI's (ElvUI-vanilla Modules/NamePlates): a flat health bar
-- in a backdrop with a 1-unit border, the name above its left end and the
-- level above its right end, in the nameplate font; the target's plate scaled
-- up with real ElvUI's background glow, and a yellow / red glow on plates at
-- low health. Gated by `E.private.skins.blizzard.nameplates`; sizes, fonts and
-- glow settings come from real ElvUI's nameplate profile keys
-- (`E.db.nameplates`).
--
-- A plate is an unnamed WorldFrame child (on Unreal Azeroth too, a Lua frame
-- of the engine class FNamePlateFrame) with the 1.12.1 layout: one StatusBar
-- child (health) and six regions in a fixed order -- border, mouseover
-- highlight, name, level, boss skull, raid icon. It is recognised by its
-- first region's `Interface\Tooltips\Nameplate-Border` texture (real ElvUI's
-- test, true on both clients). Plates are created on demand and reused, so the
-- WorldFrame children are rescanned whenever their count changes. The scan
-- runs every frame, so a new plate shows its native look for one frame at
-- most.
--
-- The native health bar is kept and only re-textured and resized: the client
-- colours it by reaction (red / yellow / green / blue), and that colour
-- survives a texture change. On Unreal Azeroth it could not be replaced, as
-- StatusBar has no GetStatusBarColor there to read the reaction from. On
-- Unreal Azeroth the bar sits one frame level BELOW its plate, so the plate's
-- own textures would cover it; it is raised above the plate. Border and
-- highlight are hidden and made fully transparent, so a later Show() from the
-- client draws nothing.
--
-- The backdrop, border and glow are textures on the plate itself, below the
-- raised bar, without a backdrop on the native frame. The layout is re-applied
-- whenever a plate is shown again, shows another unit or gains or loses the
-- target, since a reused plate's anchors are not guaranteed.
--
-- The target: a plate carries no unit, so it is found by name, with the
-- client's dimming of non-target plates breaking ties (FindTargetPlate).
--
-- Not ported from real ElvUI: its castbar, auras, combo points, threat and
-- class colouring, own mouseover highlight and non-target transparency, which
-- need unit data a plate does not expose; of its eight target glow styles
-- only the background glow (its default, style2) is drawn, for every style
-- other than "none". The boss skull takes the level's place instead of real
-- ElvUI's red "??".

local LSM = LibStub("LibSharedMedia-3.0", true)
local getn = ElvUI.Compat.getn

local BORDER_TEXTURE = "interface\\tooltips\\nameplate-border"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local GLOW_TEXTURE = "Interface\\AddOns\\ElvUI\\Media\\Textures\\spark"
local EDGE = 1
local TEXT_GAP = 2
local RAID_ICON_GAP = 6
-- Real ElvUI's background glow reaches (border + 14) * scale above and below
-- the bar and twice that to its sides, with the scale floored at 0.75.
local GLOW_REACH = 14
local GLOW_MIN_SCALE = 0.75

local plates = {}
local numChildren = 0

local function IsNamePlate(frame)
	local ok, region = pcall(frame.GetRegions, frame)
	if not ok or not region or not region.GetTexture then return false end
	local okTex, texture = pcall(region.GetTexture, region)
	return okTex and type(texture) == "string" and string.lower(texture) == BORDER_TEXTURE
end

local function Silence(region)
	if not region then return end
	pcall(region.SetAlpha, region, 0)
	pcall(region.Hide, region)
end

local function NewTexture(plate, layer, color)
	local tex = plate:CreateTexture(nil, layer)
	tex:SetTexture(WHITE)
	tex:SetVertexColor(color.r, color.g, color.b, color.a or 1)
	return tex
end

-- Real ElvUI's StyleFrame (pixel-perfect branch): a backdrop filling the bar
-- and four border lines EDGE outside it.
local function BuildBackdrop(plate, bar)
	local general = E.db.general
	local fill = NewTexture(plate, "BORDER", general.backdropfadecolor)
	fill:SetAllPoints(bar)

	local border = general.bordercolor
	local top = NewTexture(plate, "BORDER", border)
	top:SetPoint("TOPLEFT", bar, "TOPLEFT", -EDGE, EDGE)
	top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", EDGE, EDGE)
	top:SetHeight(EDGE)
	local bottom = NewTexture(plate, "BORDER", border)
	bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -EDGE, -EDGE)
	bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", EDGE, -EDGE)
	bottom:SetHeight(EDGE)
	local left = NewTexture(plate, "BORDER", border)
	left:SetPoint("TOPLEFT", bar, "TOPLEFT", -EDGE, EDGE)
	left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -EDGE, -EDGE)
	left:SetWidth(EDGE)
	local right = NewTexture(plate, "BORDER", border)
	right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", EDGE, EDGE)
	right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", EDGE, -EDGE)
	right:SetWidth(EDGE)
end

local function PlaceGlow(p)
	local db = E.db.nameplates
	local scale = 1
	if db.useTargetScale then
		scale = math.max(db.targetScale, GLOW_MIN_SCALE)
	end
	local size = (EDGE + GLOW_REACH) * scale
	p.glow:ClearAllPoints()
	p.glow:SetPoint("TOPLEFT", p.bar, "TOPLEFT", -size * 2, size)
	p.glow:SetPoint("BOTTOMRIGHT", p.bar, "BOTTOMRIGHT", size * 2, -size)
end

local function Layout(p)
	local db = E.db.nameplates
	local bar, name, level = p.bar, p.name, p.level

	Silence(p.border)
	Silence(p.highlight)

	local scale = 1
	if p.isTarget and db.useTargetScale then scale = db.targetScale end
	bar:SetFrameLevel(p.plate:GetFrameLevel() + 1)
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", p.plate, "CENTER", 0, 0)
	bar:SetWidth(db.width * scale)
	bar:SetHeight(db.healthHeight * scale)
	local texture = LSM and LSM:Fetch("statusbar", db.statusbar)
	if texture then pcall(bar.SetStatusBarTexture, bar, texture) end
	PlaceGlow(p)

	local font = LSM and LSM:Fetch("font", db.font)
	if level then
		E:FontTemplate(level, font, db.fontSize, db.fontOutline)
		level:ClearAllPoints()
		level:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, TEXT_GAP)
		level:SetJustifyH("RIGHT")
	end
	if name then
		E:FontTemplate(name, font, db.fontSize, db.fontOutline)
		name:ClearAllPoints()
		name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, TEXT_GAP)
		if level then
			name:SetPoint("BOTTOMRIGHT", level, "BOTTOMLEFT", 0, 0)
		else
			name:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, TEXT_GAP)
		end
		name:SetJustifyH("LEFT")
	end
	if p.boss then
		p.boss:ClearAllPoints()
		p.boss:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, TEXT_GAP)
	end
	if p.raid then
		p.raid:ClearAllPoints()
		p.raid:SetPoint("RIGHT", bar, "LEFT", -RAID_ICON_GAP, 0)
	end
end

local function SkinPlate(plate)
	local bar = plate:GetChildren()
	if not bar then return end
	local regions = { plate:GetRegions() }
	local p = {
		plate = plate,
		bar = bar,
		border = regions[1],
		highlight = regions[2],
		name = regions[3],
		level = regions[4],
		boss = regions[5],
		raid = regions[6],
	}
	plate.elvPlate = p
	BuildBackdrop(plate, bar)
	p.glow = plate:CreateTexture(nil, "BACKGROUND")
	p.glow:SetTexture(GLOW_TEXTURE)
	p.glow:Hide()
	table.insert(plates, p)
end

local function IsShown(p)
	local ok, shown = pcall(p.plate.IsShown, p.plate)
	return ok and ElvUI.Compat.bool(shown)
end

local function NameOf(p)
	if not p.name then return nil end
	local ok, text = pcall(p.name.GetText, p.name)
	if ok then return text end
end

local function Dimmed(alpha)
	return type(alpha) == "number" and alpha < 0.99
end

-- False when the client has dimmed the plate as a non-target.
local function IsLit(p)
	local okPlate, alpha = pcall(p.plate.GetAlpha, p.plate)
	if okPlate and Dimmed(alpha) then return false end
	if p.name then
		local okName, r, g, b, nameAlpha = pcall(p.name.GetTextColor, p.name)
		if okName and Dimmed(nameAlpha) then return false end
	end
	return true
end

-- The target's plate, or nil: the one visible plate showing the target's
-- name. Among several of that name, the one the client left undimmed. While
-- there is a target, the client dims non-target plates: Unreal Azeroth draws
-- their names at half alpha, the 1.12.1 client lowers the plates' own alpha
-- (pfUI reads it the same way). On Unreal Azeroth some non-target plates keep
-- full alpha too (measured, cause unknown), so the dimming only breaks a tie
-- between plates of the target's name and is never trusted on its own; with
-- no single undimmed plate among them none is marked.
local function FindTargetPlate()
	if not ElvUI.Compat.bool(UnitExists("target")) then return nil end
	local targetName = UnitName("target")
	if not targetName then return nil end
	local named, lit
	local namedCount, litCount = 0, 0
	local i
	for i = 1, getn(plates) do
		local p = plates[i]
		if IsShown(p) and NameOf(p) == targetName then
			namedCount = namedCount + 1
			named = p
			if IsLit(p) then
				litCount = litCount + 1
				lit = p
			end
		end
	end
	if namedCount == 1 then return named end
	if litCount == 1 then return lit end
	return nil
end

-- Real ElvUI's glow choice: the target glow colour on the target, otherwise
-- yellow at or below the low health threshold and red at or below half of it.
local function GlowColor(p)
	local db = E.db.nameplates
	if p.isTarget and db.targetGlow ~= "none" then
		local c = db.glowColor
		return c.r, c.g, c.b, c.a or 1
	end
	local threshold = db.lowHealthThreshold or 0
	if threshold <= 0 then return nil end
	local okValue, value = pcall(p.bar.GetValue, p.bar)
	local okRange, low, high = pcall(p.bar.GetMinMaxValues, p.bar)
	if not okValue or not okRange or type(value) ~= "number" or type(high) ~= "number" or high <= 0 then
		return nil
	end
	local perc = value / high
	if perc <= threshold / 2 then return 1, 0, 0, 1 end
	if perc <= threshold then return 1, 1, 0, 1 end
	return nil
end

local function UpdateGlow(p)
	local r, g, b, a = GlowColor(p)
	local key = r and (r .. ":" .. g .. ":" .. b .. ":" .. a) or nil
	if key == p.glowKey then return end
	p.glowKey = key
	if r then
		p.glow:SetVertexColor(r, g, b, a)
		p.glow:Show()
	else
		p.glow:Hide()
	end
end

local function UpdatePlate(p, targetPlate)
	if not IsShown(p) then
		p.shown = nil
		return
	end
	local unitName = NameOf(p)
	local isTarget = (p == targetPlate)
	if not p.shown or unitName ~= p.unitName or isTarget ~= p.isTarget then
		p.shown = true
		p.unitName = unitName
		p.isTarget = isTarget
		Layout(p)
	end
	UpdateGlow(p)
end

local function Scan()
	local count = WorldFrame:GetNumChildren()
	if count ~= numChildren then
		numChildren = count
		local kids = { WorldFrame:GetChildren() }
		local i
		for i = 1, getn(kids) do
			local frame = kids[i]
			if not frame.elvPlate and IsNamePlate(frame) then
				SkinPlate(frame)
			end
		end
	end
	local targetPlate = FindTargetPlate()
	local i
	for i = 1, getn(plates) do
		UpdatePlate(plates[i], targetPlate)
	end
end

local function LoadSkin()
	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function() pcall(Scan) end)
end

S:AddBlizzardSkin("nameplates", LoadSkin)
