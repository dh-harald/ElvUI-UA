-- ***************************************************************************
-- ** DISABLED, CONFIRMED DEAD END. Do not re-enable without a real fix for **
-- ** the root cause below.                                                 **
-- **                                                                       **
-- ** Investigation (WorldFrame scan, GetMouseFocus(), a full recursive UI- **
-- ** tree text search) conclusively found that the native nameplate on     **
-- ** this UA build is NOT a Lua/FrameXML UI Frame at all -- no GetName(),  **
-- ** no regions, not reachable from WorldFrame OR UIParent's own tree, no  **
-- ** mouse hit-testing (consistent with the separately reported bug        **
-- ** EF-225, "nameplates aren't clickable"). A follow-up check of the full **
-- ** UA API surface (functions.md, WorldFrame.md, PlayerModel.md,          **
-- ** Region.md) also found no world-space-to-screen projection API, so     **
-- ** even a target-only floating replacement (not reusing the native plate **
-- ** at all) has no primitive to anchor itself to a unit's actual 3D       **
-- ** position either. Both possible paths forward are closed, not just     **
-- ** this specific detector implementation.                                **
-- **                                                                       **
-- ** `NP:Initialize()` is hard-disabled below (unconditionally returns,    **
-- ** independent of `E.private.nameplates.enable`) and the config toggle   **
-- ** in `ElvUI_Config/Core.lua` is commented out -- this cannot be turned  **
-- ** back on by a config change or a copied-in real profile. Kept in the   **
-- ** repo rather than deleted -- equivalent unit-level info                **
-- ** (health/name/level) for the CURRENT TARGET already exists via         **
-- ** `Modules/UnitFrames/Units/Target.lua`, just not as a floating above-  **
-- ** the-head indicator.                                                   **
-- ***************************************************************************
--
-- NamePlates -- custom-built, NOT oUF-based, same reasoning as UnitFrames:
-- this module never even tried oUF.
--
-- Neither client exposes an addressable per-plate unit token on this API
-- vintage (that's a TBC+ addition) -- a plate is just an anonymous child of
-- WorldFrame. Real ElvUI-vanilla's own Modules/NamePlates/NamePlates.lua
-- (source/ElvUI-vanilla) discovers plates the same way: poll
-- WorldFrame:GetNumChildren()/GetChildren(), and recognize a genuine
-- nameplate among the new children by its native border texture
-- (`Interface\Tooltips\Nameplate-Border`). That check is ALSO how this
-- module's discovery starts (ClassifyPlate below) -- but
-- source/UnrealUI/modules/nameplates.lua found, live on UA, that the
-- border-texture check finds NOTHING there: UA's native plate doesn't carry
-- that texture at all (some don't even have a health bar). UnrealUI's fix,
-- ALSO ported here as the fallback: classify a WorldFrame child
-- structurally instead (does it have a StatusBar-shaped child plus at least
-- one FontString region, or at least two FontString regions) when the
-- border-texture check finds nothing. This dual-path detector is the single
-- most load-bearing piece of this file -- see ClassifyPlate's own comment.
--
-- Native plate art is MUTED (SetTexture(nil)/SetAlpha(0)), not Hide()d --
-- matches UnrealUI's own choice, not real ElvUI-vanilla's Hide()+shrink
-- (QueueObject). Reasoning ported directly: GetText()/GetTexture() on a
-- muted-but-not-hidden region keep working, so the native Name/Level
-- fontstrings and the elite/glow textures' own IsShown() state stay usable
-- as this module's *data source* every refresh (there is no unit token to
-- re-query instead). A real profile's motionType/threat/buffs/debuffs/
-- castbar/comboPoints/style-filter machinery (real ElvUI's own
-- P.nameplates.units[...] per-unit-type schema, source/ElvUI-vanilla's own
-- Settings/Profile.lua:202+) is DELIBERATELY NOT attempted this pass.

local E, L, V, P, G = unpack(ElvUI)
local NP = E:NewModule("NamePlates", "AceEvent-3.0")
E.NamePlates = NP

-- Settings: `V.nameplates` (Settings/Private.lua), `P.nameplates`
-- (Settings/Profile.lua). `V.nameplates.enable` is a project-only
-- convenience switch -- real ElvUI's nameplate module has no top-level
-- enable, it just always runs once loaded, since vanilla's native
-- nameplates are on via CVars regardless of any addon. It no longer gates
-- anything either way: NP:Initialize() hard-disables this module.

-- ---------------------------------------------------------------------
-- Small call helpers -- ported from UnrealUI's own defensive pattern
-- (source/UnrealUI/modules/nameplates.lua:171-199): every native plate
-- part is touched through a pcall, since a WorldFrame child that turns
-- out not to be a plate at all must never error the scan.
-- ---------------------------------------------------------------------
local function Call1(object, method, a, b)
	if not object then return nil end
	local ok, fn = pcall(function() return object[method] end)
	if not ok or type(fn) ~= "function" then return nil end
	local ok2, r1, r2, r3 = pcall(fn, object, a, b)
	if not ok2 then return nil end
	return r1, r2, r3
end

local function ObjectType(object)
	local t = Call1(object, "GetObjectType")
	if type(t) == "string" then return t end
	return nil
end

local function Clamp01(value)
	if value < 0 then return 0 end
	if value > 1 then return 1 end
	return value
end

local function MuteTexture(region)
	if not region then return end
	pcall(function() region:SetTexture(nil) end)
	pcall(function() region:SetAlpha(0) end)
end

local function MuteFontString(region)
	if not region then return end
	-- GetText()/GetTextColor() must keep working -- name, level, and the
	-- level's own difficulty color are read back off these every refresh.
	pcall(function() region:SetAlpha(0) end)
end

-- A native bar frame plus its own regions -- zeroing the frame's own alpha
-- alone doesn't stop the fill drawing (parent-alpha-not-propagated, same
-- UA quirk documented project-wide for Hide()).
local function MuteBar(bar)
	if not bar then return end
	pcall(function() bar:SetStatusBarTexture(nil) end)
	pcall(function() bar:SetAlpha(0) end)
	local ok, regions = pcall(function() return { bar:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return end
	for i = 1, table.getn(regions) do
		if ObjectType(regions[i]) == "Texture" then MuteTexture(regions[i]) end
	end
end

local function IsNumericText(text)
	if type(text) ~= "string" then return false end
	return tonumber(text) ~= nil
end

-- ---------------------------------------------------------------------
-- Plate classification -- see this file's header comment for why there
-- are two independent detectors.
-- ---------------------------------------------------------------------
local BORDER_TEXTURE = "Nameplate%-Border"

-- Known non-plate native frames the structural fallback (StatusBar-shaped
-- child + fontstring) has actually been caught matching, live: among
-- WorldFrame's adopted children, GameTooltip and GroupLootFrame1-4 both
-- matched with no real nameplate present. GameTooltip has an item-
-- quality-colored bar-shaped region plus text; GroupLootFrame1-4 (the
-- Need/Greed/Pass roll popups) have an icon border and item name/count
-- text -- both incidentally shaped enough like "healthbar+name" to slip
-- through. Real vanilla nameplates are anonymous (never `CreateFrame`'d
-- with an explicit name), so a candidate with one of these SPECIFIC,
-- deliberately-Blizzard-named identities is never a plate -- excluded by
-- name before any structural check runs. Grow this list if another named
-- frame is caught the same way; don't reject ALL named frames outright
-- (UnrealUI's own finding: this runtime auto-names even anonymous
-- CreateFrame calls as "GeneratedLuaUIObject_NNNN", so GetName() ~= nil
-- alone doesn't distinguish a real Blizzard name from an auto-generated
-- one without pattern-matching that prefix, which isn't confirmed
-- consistent enough here to rely on yet).
local KNOWN_NON_PLATE_NAMES = {
	"^GameTooltip$", "^GroupLootFrame%d+$", "^ItemRefTooltip$",
	"^ShoppingTooltip%d*$", "^AutoCompleteBox$",
}

local function IsKnownNonPlateName(name)
	if type(name) ~= "string" then return false end
	for i = 1, table.getn(KNOWN_NON_PLATE_NAMES) do
		if string.find(name, KNOWN_NON_PLATE_NAMES[i]) then return true end
	end
	return false
end

local function ClassifyPlate(frame)
	local frameName = Call1(frame, "GetName")
	if IsKnownNonPlateName(frameName) then return nil, "known-non-plate:" .. tostring(frameName) end

	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return nil, "no-getregions" end

	local parts = { textures = {}, fontstrings = {} }

	for i = 1, table.getn(regions) do
		local region = regions[i]
		local regionType = ObjectType(region)

		if regionType == "FontString" then
			table.insert(parts.fontstrings, region)
		elseif regionType == "Texture" then
			table.insert(parts.textures, region)
			local texture = Call1(region, "GetTexture")
			if type(texture) == "string" then
				if string.find(texture, BORDER_TEXTURE) then
					parts.border = region
				elseif string.find(texture, "Glow") then
					parts.glow = region
				elseif string.find(texture, "Elite") or string.find(texture, "Rare") then
					parts.levelicon = region
				end
			end
		end
	end

	local kidsOk, kids = pcall(function() return { frame:GetChildren() } end)
	if kidsOk and type(kids) == "table" then
		for i = 1, table.getn(kids) do
			local kid = kids[i]
			local kidType = ObjectType(kid)
			local hasValue = false
			pcall(function() hasValue = type(kid.GetValue) == "function" end)
			if kidType == "StatusBar" or hasValue then
				if not parts.healthbar then parts.healthbar = kid end
			end
		end
	end

	local fontCount = table.getn(parts.fontstrings)

	-- Real ElvUI's own detector (border texture present) is tried first;
	-- UnrealUI's structural fallback covers the client where that texture
	-- doesn't exist. Neither is a single generic trait -- adopting a plate
	-- mutes its native art for the rest of the session, so a false
	-- positive on some unrelated WorldFrame child would be a real, visible
	-- mistake, not a cosmetic one.
	local detector
	if parts.border then
		detector = "border-texture"
	elseif parts.healthbar and fontCount >= 1 then
		detector = "healthbar+name"
	elseif fontCount >= 2 then
		detector = "name+level-fontstrings"
	else
		-- Reason string for /run E.NamePlates:Dump() -- see that
		-- function's own comment for why this exists.
		return nil, string.format("tex=%d fs=%d bar=%s",
			table.getn(parts.textures), fontCount, parts.healthbar and "y" or "n")
	end
	parts.detector = detector

	-- The level is whichever fontstring currently reads as a number; the
	-- name is the other one. Re-checked every refresh too (RefreshPlate),
	-- since a plate is recycled onto a different unit without being
	-- rebuilt.
	local first, second = parts.fontstrings[1], parts.fontstrings[2]
	if IsNumericText(Call1(first, "GetText")) and second then
		parts.level, parts.name = first, second
	else
		parts.name, parts.level = first, second
	end

	return parts
end

-- ---------------------------------------------------------------------
-- Overlay construction -- backdrop+inset-StatusBar recipe already
-- established project-wide (DataBars/PetBar/ActionBars/UnitFrames), NOT
-- UnrealUI's own plain-texture bar (Util.CreateStatusBar exists precisely
-- so every module shares one proven-on-UA status bar implementation).
-- ---------------------------------------------------------------------
local plateCount = 0

local function ApplyFont(fontString, size)
	pcall(fontString.SetFont, fontString, "Fonts\\FRIZQT__.TTF", size or NPdb.fontSize,
		NPdb.fontOutline == "NONE" and "" or NPdb.fontOutline)
end

local function BuildOverlay(frame, parts)
	plateCount = plateCount + 1

	local overlay = CreateFrame("Frame", "ElvNamePlate" .. plateCount, frame)
	overlay.plate = frame
	overlay.parts = parts
	overlay.cache = {}
	overlay:SetWidth(NPdb.width)
	overlay:SetHeight(NPdb.healthHeight + NPdb.fontSize + 4)
	overlay:SetPoint("TOP", frame, "TOP", 0, 0)

	local health = ElvUI.Util.CreateStatusBar(overlay, {
		width = NPdb.width,
		height = NPdb.healthHeight,
		background = {0.1, 0.1, 0.1, 1},
		color = {0.31, 0.31, 0.31},
	})
	health:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 0)
	overlay.health = health

	local textLayer = CreateFrame("Frame", nil, health)
	textLayer:SetAllPoints(health)
	local ok, level = pcall(health.GetFrameLevel, health)
	if ok and tonumber(level) then pcall(textLayer.SetFrameLevel, textLayer, level + 10) end

	overlay.healthText = textLayer:CreateFontString(nil, "OVERLAY")
	ApplyFont(overlay.healthText, NPdb.healthFontSize)
	overlay.healthText:SetPoint("CENTER", health, "CENTER", 0, 0)

	overlay.name = overlay:CreateFontString(nil, "OVERLAY")
	ApplyFont(overlay.name)
	overlay.name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 2)

	overlay.level = overlay:CreateFontString(nil, "OVERLAY")
	ApplyFont(overlay.level)
	overlay.level:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 2)

	overlay:Show()
	return overlay
end

local registry = {}
local plateOrder = {}

-- Diagnostics -- see NP:Report()/NP:Dump()/NP:DumpAdopted() at the bottom
-- of this file: with no other symptom to go on when the scan adopts zero
-- plates, this exists so a report can say WHY instead of guessing at a
-- second detector blind. `rejected`/`rejectReasons` reflect only the MOST
-- RECENT scan pass (reset every tick, see ScanWorldFrame) -- `adopted` is
-- cumulative (a frame, once adopted, is never reclassified).
local stats = { worldChildren = 0, adopted = 0, rejected = 0 }
local rejectReasons = {}

local function AdoptPlate(frame)
	local parts, reason = ClassifyPlate(frame)
	if not parts then
		stats.rejected = stats.rejected + 1
		reason = reason or "unknown"
		rejectReasons[reason] = (rejectReasons[reason] or 0) + 1
		return nil
	end
	stats.adopted = stats.adopted + 1

	MuteTexture(parts.border)
	MuteTexture(parts.glow)
	MuteFontString(parts.name)
	MuteFontString(parts.level)
	MuteBar(parts.healthbar)

	-- Everything not explicitly excepted above gets muted too, INCLUDING
	-- the elite/rare icon (parts.levelicon) -- it stays invisible but its
	-- own IsShown() keeps working (MuteTexture is alpha, not Hide()), which
	-- is exactly what RefreshPlate reads to append the "+" suffix.
	for i = 1, table.getn(parts.textures) do
		local region = parts.textures[i]
		if region ~= parts.border and region ~= parts.glow then
			MuteTexture(region)
		end
	end
	for i = 1, table.getn(parts.fontstrings) do
		MuteFontString(parts.fontstrings[i])
	end

	local overlay = BuildOverlay(frame, parts)
	registry[frame] = overlay
	table.insert(plateOrder, overlay)
	return overlay
end

-- WARNING: never re-walk EVERY not-yet-adopted WorldFrame child's full
-- region/child tree, through pcall-wrapped closures, on EVERY 0.1s tick --
-- this freezes the client. Repeated pcall+closure allocation across many
-- objects, many times a second, is a known stutter/freeze risk on this
-- engine (also documented in source/UnrealUI's own comments) -- exactly
-- what an unthrottled full re-walk does once WorldFrame's child count is
-- more than trivial.
--
-- Why a retry is needed at all: real ElvUI-vanilla's own code notes
-- "Vanilla never destroys a plate" -- a native plate frame is CREATED
-- ONCE and reused/repopulated for different mobs over the whole session.
-- A frame that was empty (no health bar/fontstring yet) at scan time and
-- got rejected must eventually be retried, or a plate that later becomes
-- a real, visible, populated mob nameplate never gets adopted (live-
-- confirmed: a fully native "Elder Mottled Boar" plate stayed unreplaced
-- because its frame had already been scanned-and-rejected earlier in the
-- session).
--
-- This version keeps BOTH constraints: cheap per-tick cost (only
-- genuinely NEW WorldFrame children are classified every 0.1s, via the
-- scannedChildren cursor), plus eventual retry for rejected candidates,
-- but THROTTLED (one retry pass every RETRY_EVERY_TICKS ticks, ~2s) AND
-- BUDGETED (at most RETRY_BUDGET candidates reclassified per retry pass,
-- regardless of how large the rejected/pending set has grown) -- a hard
-- ceiling on worst-case per-tick cost no matter how many stray WorldFrame
-- children accumulate over a long session.
local pending = {}
local scannedChildren = 0
local tickCount = 0
local RETRY_EVERY_TICKS = 20
local RETRY_BUDGET = 25

local function TryAdopt(frame)
	local overlay = AdoptPlate(frame)
	if overlay then
		pending[frame] = nil
	else
		pending[frame] = true
	end
end

local function ScanWorldFrame()
	local count = tonumber(Call1(WorldFrame, "GetNumChildren"))
	if not count then return end
	stats.worldChildren = count
	stats.rejected = 0
	rejectReasons = {}
	tickCount = tickCount + 1

	if count < scannedChildren then scannedChildren = 0 end
	if count > scannedChildren then
		local ok, kids = pcall(function() return { WorldFrame:GetChildren() } end)
		if ok and type(kids) == "table" then
			for i = scannedChildren + 1, count do
				local child = kids[i]
				if child and not registry[child] then TryAdopt(child) end
			end
		end
		scannedChildren = count
	end

	if tickCount >= RETRY_EVERY_TICKS then
		tickCount = 0
		local n = 0
		for frame in pairs(pending) do
			if n >= RETRY_BUDGET then break end
			n = n + 1
			if not registry[frame] then TryAdopt(frame) end
		end
	end
end

-- ---------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------

-- Unit-type color, read from the native health bar's own tint -- the only
-- unit-type signal available for a plate that isn't the current target
-- (ported from UnrealUI's own UnitTypeFromBarColor, thresholds unchanged,
-- remapped onto real ElvUI's own P.nameplates.reactions palette instead of
-- UnrealUI's own).
local function ReactionColorFromBarTint(r, g, b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
	if r > 0.8 and g < 0.3 and b < 0.3 then return NPdb.reactions.bad end
	if r > 0.8 and g > 0.8 and b < 0.3 then return NPdb.reactions.neutral end
	if r < 0.3 and g > 0.8 and b < 0.3 then return NPdb.reactions.good end
	if r < 0.3 and g < 0.3 and b > 0.8 then return NPdb.reactions.friendlyPlayer end
	return nil
end

local function IsFriendlyPlayerTarget()
	local ok, isPlayer = pcall(UnitIsPlayer, "target")
	if not ok or not isPlayer then return false end
	local ok2, canAttack = pcall(UnitCanAttack, "player", "target")
	return ok2 and not canAttack
end

-- Fallback reaction lookup for the CURRENT TARGET's own plate, where a
-- real unit token ("target") actually exists to query -- ported from
-- UnrealUI's identical fallback branch.
local function ReactionColorFromTarget()
	if IsFriendlyPlayerTarget() then return NPdb.reactions.friendlyPlayer end
	local ok, reaction = pcall(UnitReaction, "target", "player")
	if not ok or not reaction then return nil end
	if reaction <= 3 then return NPdb.reactions.bad end
	if reaction == 4 then return NPdb.reactions.neutral end
	return NPdb.reactions.good
end

local function RefreshPlate(overlay)
	local parts = overlay.parts
	local plate = overlay.plate

	local visible = Call1(plate, "IsVisible")
	if not visible then return end

	-- Re-resolve which fontstring is the level -- a plate is recycled
	-- onto a new unit without being rebuilt.
	local a, b = parts.fontstrings[1], parts.fontstrings[2]
	if b then
		if IsNumericText(Call1(a, "GetText")) then
			parts.level, parts.name = a, b
		else
			parts.name, parts.level = a, b
		end
	end

	local hasTarget = false
	pcall(function() hasTarget = UnitExists("target") and true or false end)
	local plateAlpha = tonumber(Call1(plate, "GetAlpha")) or 1
	overlay.isTarget = hasTarget and plateAlpha >= 1

	-- Name
	local name = Call1(parts.name, "GetText")
	if name ~= overlay.cache.name then
		overlay.cache.name = name
		overlay.name:SetText(name or "")
	end

	-- Level (native elite/rare marker kept as a "+" suffix)
	if NPdb.showLevel then
		local levelText = Call1(parts.level, "GetText")
		local suffix = ""
		if parts.levelicon and Call1(parts.levelicon, "IsShown") then suffix = "+" end
		local text = parts.level and ((levelText or "??") .. suffix) or ""
		if text ~= overlay.cache.level then
			overlay.cache.level = text
			overlay.level:SetText(text)
			local r, g, bb = Call1(parts.level, "GetTextColor")
			if type(r) ~= "number" then r, g, bb = 1, 1, 1 end
			pcall(overlay.level.SetTextColor, overlay.level, r, g, bb, 1)
		end
	elseif overlay.cache.level ~= "" then
		overlay.cache.level = ""
		overlay.level:SetText("")
	end

	-- Health -- native bar first (works for any plate); UnitHealth("target")
	-- fallback only for the plate that IS the current target.
	local value, minimum, maximum
	if parts.healthbar then
		value = tonumber(Call1(parts.healthbar, "GetValue"))
		minimum, maximum = Call1(parts.healthbar, "GetMinMaxValues")
		minimum, maximum = tonumber(minimum), tonumber(maximum)
	end
	if not (value and maximum and maximum > 0) and overlay.isTarget then
		local ok, hp = pcall(UnitHealth, "target")
		local ok2, hpMax = pcall(UnitHealthMax, "target")
		if ok and ok2 and hpMax and hpMax > 0 then
			value, minimum, maximum = hp, 0, hpMax
		end
	end

	if value and maximum and maximum > 0 then
		overlay.health:Show()
		overlay.health:SetMinMaxValues(minimum or 0, maximum)
		overlay.health:SetValue(value)
		if NPdb.showHealthText then
			local perc = (value - (minimum or 0)) / (maximum - (minimum or 0)) * 100
			overlay.healthText:SetText(string.format("%.0f%%", perc))
		else
			overlay.healthText:SetText("")
		end
	else
		overlay.health:Hide()
		overlay.healthText:SetText("")
	end

	-- Unit-type / reaction color
	local r, g, bb = Call1(parts.healthbar, "GetStatusBarColor")
	local color = ReactionColorFromBarTint(r, g, bb)
	if not color and overlay.isTarget then color = ReactionColorFromTarget() end
	color = color or NPdb.reactions.bad
	if color ~= overlay.cache.color then
		overlay.cache.color = color
		ElvUI.Util.SetStatusBarColor(overlay.health, color.r, color.g, color.b, 1)
	end

	-- Target emphasis: scale + fade non-target plates, matching real
	-- ElvUI's own useTargetScale/targetScale/nonTargetTransparency fields.
	local wantScale = 1
	if NPdb.useTargetScale and overlay.isTarget then wantScale = NPdb.targetScale end
	if wantScale ~= overlay.cache.scale then
		overlay.cache.scale = wantScale
		pcall(overlay.SetScale, overlay, wantScale)
	end

	local wantAlpha = 1
	if hasTarget and not overlay.isTarget then wantAlpha = Clamp01(NPdb.nonTargetTransparency) end
	if wantAlpha ~= overlay.cache.alpha then
		overlay.cache.alpha = wantAlpha
		pcall(overlay.SetAlpha, overlay, wantAlpha)
	end
end

local function RefreshAll()
	for i = 1, table.getn(plateOrder) do
		local overlay = plateOrder[i]
		if overlay then
			local ok, err = pcall(RefreshPlate, overlay)
			if not ok then E:Print("NamePlates refresh error: " .. tostring(err)) end
		end
	end
end

-- ---------------------------------------------------------------------
-- Diagnostics -- `E` is a local upvalue in every module file, not reachable
-- from the console; call these instead as:
--   /run ElvUI[1].NamePlates:Report()
--   /run ElvUI[1].NamePlates:Dump()              -- first 10 WorldFrame children
--   /run ElvUI[1].NamePlates:Dump(nil, 3)        -- just WorldFrame child [3]
--   /run ElvUI[1].NamePlates:DumpAdopted()       -- all adopted plates
--   /run ElvUI[1].NamePlates:DumpAdopted(1)      -- just entry [1]
--   /run ElvUI[1].NamePlates:DumpMouseFocus()    -- whatever is under the mouse RIGHT NOW
--   /run ElvUI[1].NamePlates:FindByText("Elder Mottled Boar")  -- find by name, WorldFrame's
--                                                                  DIRECT children only
--   /run ElvUI[1].NamePlates:FindByTextDeep("Elder Mottled Boar")  -- same, but the WHOLE UI
--                                                                      tree (slower, one-shot,
--                                                                      use if FindByText finds
--                                                                      nothing)
-- Every entry prints as SEVERAL short chat messages, not one long line --
-- see Dump()'s own comment for why (a native chat frame scrolls per
-- MESSAGE, not per wrapped visual line).
-- Root-causing "nothing got replaced" needs to know WHICH of the two
-- detectors (or neither) matched WorldFrame's children, not another
-- blind theory.
-- ---------------------------------------------------------------------
function NP:Report()
	E:Print(string.format(
		"worldChildren=%d adopted=%d rejected(this pass)=%d",
		stats.worldChildren, stats.adopted, stats.rejected))
	for reason, n in pairs(rejectReasons) do
		E:Print("  rejected (" .. tostring(n) .. "x): " .. tostring(reason))
	end
end

-- Prints ONLY the plates actually adopted (never the whole WorldFrame
-- child list) -- short enough to fit on screen unlike Dump(). Pass an
-- index (`/run ElvUI[1].NamePlates:DumpAdopted(1)`) to print just ONE
-- entry -- the chat frame's own scrollback may not reach an earlier
-- entry, and one line never needs scrolling.
-- Also prints the native plate's own name/type and the health bar's
-- min/max (not just its current value): a "plate" with name="Item Name"
-- and plateVisible=false is a completely unrelated native frame, not a
-- nameplate at all (see ScanWorldFrame's own comment for the actual bug
-- this traces back to).
function NP:DumpAdopted(onlyIndex)
	local total = table.getn(plateOrder)
	local first, last = 1, total
	if onlyIndex then first, last = onlyIndex, onlyIndex end
	if not onlyIndex then E:Print(string.format("%d plate(s) adopted:", total)) end

	for i = first, last do
		local overlay = plateOrder[i]
		if overlay then
			local parts = overlay.parts
			local visible = Call1(overlay.plate, "IsVisible")
			local shown = Call1(overlay, "IsShown")
			local alpha = tonumber(Call1(overlay, "GetAlpha")) or -1
			local plateName = Call1(overlay.plate, "GetName")
			local plateType = ObjectType(overlay.plate)
			local minV, maxV = Call1(overlay.health, "GetMinMaxValues")
			-- Split into several SHORT messages, not one long line -- a
			-- native chat frame scrolls per MESSAGE, not per wrapped
			-- visual line, so one message that wraps taller than the
			-- visible chat panel can never be fully seen no matter how
			-- you scroll. Several short messages are each individually
			-- scrollable instead.
			E:Print(string.format("[%d] plate=%s(%s) detector=%s",
				i, tostring(plateType), tostring(plateName), tostring(parts.detector)))
			E:Print(string.format("  visible=%s shown=%s alpha=%.2f",
				tostring(visible), tostring(shown), alpha))
			E:Print(string.format("  name=%s level=%s",
				tostring(Call1(parts.name, "GetText")), tostring(Call1(parts.level, "GetText"))))
			E:Print(string.format("  health=%s (%s-%s)",
				tostring(Call1(overlay.health, "GetValue")), tostring(minV), tostring(maxV)))
		else
			E:Print(string.format("[%d] no such adopted plate (only %d adopted)", i, total))
		end
	end
end

-- Dumps whatever frame is directly under the mouse cursor right now --
-- point the mouse at the REAL native nameplate (health bar or name text)
-- in-game, then run this, instead of guessing which of the WorldFrame
-- scan's many children is the actual plate: Dump()/DumpAdopted() only
-- find unrelated native frames (GameTooltip, GroupLootFrame1-4), never
-- the plate itself, since blind scanning doesn't converge on it -- this
-- identifies the real target directly instead. Read-only.
function NP:DumpMouseFocus()
	local ok, focus = pcall(GetMouseFocus)
	if not ok or not focus then
		E:Print("GetMouseFocus() returned nothing -- move the mouse over the plate first")
		return
	end

	E:Print(string.format("focus: %s(%s)", tostring(ObjectType(focus)), tostring(Call1(focus, "GetName"))))

	local ok2, regions = pcall(function() return { focus:GetRegions() } end)
	local textures, fontstrings, texts, paths = 0, 0, {}, {}
	if ok2 and type(regions) == "table" then
		for j = 1, table.getn(regions) do
			local rtype = ObjectType(regions[j])
			if rtype == "Texture" then
				textures = textures + 1
				local path = Call1(regions[j], "GetTexture")
				if type(path) == "string" and table.getn(paths) < 3 then
					table.insert(paths, string.sub(path, -28))
				end
			elseif rtype == "FontString" then
				fontstrings = fontstrings + 1
				local text = Call1(regions[j], "GetText")
				if type(text) == "string" and table.getn(texts) < 3 then
					table.insert(texts, text)
				end
			end
		end
	end
	local ok3, subs = pcall(function() return { focus:GetChildren() } end)
	local childTypes, childCount = {}, 0
	if ok3 and type(subs) == "table" then
		childCount = table.getn(subs)
		for j = 1, childCount do
			if table.getn(childTypes) < 4 then
				local hasValue = false
				pcall(function() hasValue = type(subs[j].GetValue) == "function" end)
				table.insert(childTypes, (ObjectType(subs[j]) or "?") .. (hasValue and "*" or ""))
			end
		end
	end

	E:Print(string.format("  tex=%d fs=%d children=%d", textures, fontstrings, childCount))
	E:Print("  texts={" .. table.concat(texts, ",") .. "}")
	E:Print("  paths={" .. table.concat(paths, ",") .. "}")
	E:Print("  childTypes={" .. table.concat(childTypes, ",") .. "}")

	-- Also walk up one parent level -- the plate's actual health-bar-
	-- shaped part might be a CHILD of what's directly under the cursor
	-- (e.g. hovering the health bar itself lands on the bar, not its
	-- WorldFrame-level container), so the container's own identity matters
	-- too for matching it back to a Dump()/Report() entry.
	local ok4, parent = pcall(focus.GetParent, focus)
	if ok4 and parent then
		E:Print(string.format("  parent: %s(%s)", tostring(ObjectType(parent)), tostring(Call1(parent, "GetName"))))
	end
end

-- Recursive, whole-UI-tree version of FindByText() -- walks EVERY frame
-- reachable from `root` (default UIParent, covers WorldFrame too since
-- it's normally a descendant), not just WorldFrame's direct children.
-- Exists to test the theory that the nameplate isn't nested under
-- WorldFrame's direct children at all: FindByText() (direct children
-- only) can find nothing for a real mob's exact name even though the
-- plate is visibly on screen, so this rules out the narrower possibility
-- that it's just nested somewhere else in the tree before concluding the
-- bigger finding (that the native plate isn't a Lua/FrameXML frame at
-- all -- see this file's own top-of-file banner). One-shot diagnostic
-- call, not a repeating poll -- a slower full-tree walk is acceptable
-- here (unlike ScanWorldFrame's own per-tick budget concern, see its own
-- comment on the freeze this avoids), but still capped by maxVisit as a
-- safety ceiling regardless of how large the live UI tree turns out to
-- be.
function NP:FindByTextDeep(needle, root, maxVisit)
	if type(needle) ~= "string" or needle == "" then
		E:Print("usage: /run ElvUI[1].NamePlates:FindByTextDeep(\"Mob Name\")")
		return
	end
	root = root or UIParent
	maxVisit = maxVisit or 5000
	local visited, found = 0, 0

	local function Walk(frame, depth)
		if visited >= maxVisit then return end
		visited = visited + 1

		local ok, regions = pcall(function() return { frame:GetRegions() } end)
		if ok and type(regions) == "table" then
			for j = 1, table.getn(regions) do
				if ObjectType(regions[j]) == "FontString" then
					local text = Call1(regions[j], "GetText")
					if type(text) == "string" and string.find(text, needle, 1, true) then
						found = found + 1
						E:Print(string.format("depth=%d %s(%s)", depth,
							tostring(ObjectType(frame)), tostring(Call1(frame, "GetName"))))
						E:Print("  matched text: " .. text)
					end
				end
			end
		end

		local ok2, kids = pcall(function() return { frame:GetChildren() } end)
		if ok2 and type(kids) == "table" then
			for i = 1, table.getn(kids) do
				if kids[i] and visited < maxVisit then Walk(kids[i], depth + 1) end
			end
		end
	end

	Walk(root, 0)
	E:Print(string.format("visited=%d found=%d (maxVisit=%d, root=%s)",
		visited, found, maxVisit, tostring(Call1(root, "GetName"))))
end

-- Searches every WorldFrame child's fontstring text for `needle` (plain
-- substring, no pattern magic) and prints only the matches -- the
-- targeted alternative to DumpMouseFocus(), needed because
-- DumpMouseFocus() returns nothing even with the mouse directly over a
-- real, visible native nameplate. Shares a plausible root cause with bug
-- report EF-225 ("Nameplates are not clickable to target the mobs"): if
-- the native plate frame isn't mouse-enabled at all, neither
-- click-to-target nor GetMouseFocus() would ever see it, which is
-- exactly what both symptoms describe. Since hovering can't identify the
-- frame, this identifies it by CONTENT instead: Tab-target (not click --
-- per EF-225, click doesn't work) a real mob, note its exact name, then
-- run `/run ElvUI[1].NamePlates:FindByText("Elder Mottled Boar")` --
-- prints just the WorldFrame child(ren) whose own fontstring text
-- contains that name, instead of dumping dozens of irrelevant entries.
function NP:FindByText(needle)
	if type(needle) ~= "string" or needle == "" then
		E:Print("usage: /run ElvUI[1].NamePlates:FindByText(\"Mob Name\")")
		return
	end
	local count = tonumber(Call1(WorldFrame, "GetNumChildren")) or 0
	local ok, kids = pcall(function() return { WorldFrame:GetChildren() } end)
	if not ok or type(kids) ~= "table" then
		E:Print("GetChildren() failed")
		return
	end

	local found = 0
	for i = 1, count do
		local child = kids[i]
		if child then
			local ok2, regions = pcall(function() return { child:GetRegions() } end)
			if ok2 and type(regions) == "table" then
				for j = 1, table.getn(regions) do
					if ObjectType(regions[j]) == "FontString" then
						local text = Call1(regions[j], "GetText")
						if type(text) == "string" and string.find(text, needle, 1, true) then
							found = found + 1
							E:Print(string.format("[%d] %s(%s)",
								i, tostring(ObjectType(child)), tostring(Call1(child, "GetName"))))
							E:Print("  matched text: " .. text)
							break
						end
					end
				end
			end
		end
	end
	if found == 0 then
		E:Print("no WorldFrame child's fontstring text contains \"" .. needle .. "\"")
	end
end

-- Prints the first `max` (default 10) WorldFrame children's own shape --
-- object type, region/child counts, and the actual texture paths/
-- fontstring text found -- whether or not they were adopted. Read-only,
-- mutates nothing. Use this when Report() shows 0 adopted and the reject
-- reasons alone aren't enough to tell what's actually there.
--
-- Pass an index (`/run ElvUI[1].NamePlates:Dump(nil, 3)` dumps only
-- WorldFrame child [3]) to inspect just one -- and every entry is now
-- SEVERAL short messages, not one long line, for the same reason
-- DumpAdopted() was split: a native chat frame scrolls per MESSAGE, not
-- per wrapped visual line, so one long message that wraps taller than
-- the visible chat panel can never be fully seen no matter how you
-- scroll.
function NP:Dump(max, onlyIndex)
	max = max or 10
	local count = tonumber(Call1(WorldFrame, "GetNumChildren")) or 0
	local ok, kids = pcall(function() return { WorldFrame:GetChildren() } end)
	if not ok or type(kids) ~= "table" then
		E:Print("GetChildren() failed")
		return
	end

	local first, last = 1, count
	if onlyIndex then
		first, last = onlyIndex, onlyIndex
	else
		E:Print(string.format("WorldFrame has %d children, showing up to %d:", count, max))
	end

	local shown = 0
	for i = first, last do
		if not onlyIndex and shown >= max then break end
		local child = kids[i]
		if child then
			shown = shown + 1
			local ok2, regions = pcall(function() return { child:GetRegions() } end)
			local textures, fontstrings, texts, paths = 0, 0, {}, {}
			if ok2 and type(regions) == "table" then
				for j = 1, table.getn(regions) do
					local rtype = ObjectType(regions[j])
					if rtype == "Texture" then
						textures = textures + 1
						local path = Call1(regions[j], "GetTexture")
						if type(path) == "string" and table.getn(paths) < 3 then
							table.insert(paths, string.sub(path, -28))
						end
					elseif rtype == "FontString" then
						fontstrings = fontstrings + 1
						local text = Call1(regions[j], "GetText")
						if type(text) == "string" and table.getn(texts) < 3 then
							table.insert(texts, text)
						end
					end
				end
			end
			local ok3, subs = pcall(function() return { child:GetChildren() } end)
			local children = (ok3 and type(subs) == "table") and table.getn(subs) or 0

			E:Print(string.format("[%d] %s adopted=%s",
				i, tostring(ObjectType(child)), tostring(registry[child] ~= nil)))
			E:Print(string.format("  tex=%d fs=%d children=%d", textures, fontstrings, children))
			E:Print("  texts={" .. table.concat(texts, ",") .. "}")
			E:Print("  paths={" .. table.concat(paths, ",") .. "}")
		elseif onlyIndex then
			E:Print(string.format("[%d] no such WorldFrame child (has %d)", i, count))
		end
	end
end

-- ---------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------
function NP:Initialize()
	-- Hard-disabled, confirmed dead end -- see this file's own top-of-file
	-- banner comment. Unconditional return, independent of
	-- E.private.nameplates.enable, so this can't be turned back on by a
	-- config change or a copied-in real profile.
	return
end

local function InitializeCallback()
	NP:Initialize()
end

E:RegisterInitialModule(NP:GetName(), InitializeCallback)
