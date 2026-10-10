-- Skins > Blizzard > Quest Timers -- QuestTimerFrame, the small box listing
-- the time left on timed quests (`questtimer` flag, real ElvUI-vanilla's
-- key; its `Blizzard/QuestTimers.lua` is the reference).
--
-- Per `FrameXML/QuestTimerFrame.xml`:
--
-- - The frame's chrome is a native `<Backdrop>` (dialog box art) plus one
--   ARTWORK Texture, `QuestTimerHeader` (the dialog banner). A plain
--   non-recursive `S:StripTextures` takes both; the panel is our own surface.
-- - The title is an unnamed ARTWORK FontString anchored to
--   `QuestTimerHeader`. A FontString anchored to a hidden texture keeps a
--   stale position on this client, so it is re-anchored to the frame itself
--   (real ElvUI's header offset: TOP +1,+8 with the native -13 below it) and
--   promoted to OVERLAY, above the panel parked on the frame's base level.
-- - The timer lines are QuestTimer1..N child buttons (one BACKGROUND
--   FontString each, white small font); they sit above the panel by frame
--   level and need nothing.
--
-- Position: native UIParent_ManageFramePositions anchors the frame under
-- MinimapCluster, which is not where this addon's minimap is. The frame is
-- pinned to a holder with a mover (real ElvUI's "QuestTimerFrameMover",
-- labelled with the client's QUEST_TIMERS), placed by default under the
-- minimap's data panels. Its SetPoint is replaced so a Lua repositioning
-- lands on the holder instead (same idea as real ElvUI's SetPoint hook and
-- pfUI's SetPoint override), and a watcher undoes any anchor that bypasses
-- the replaced method (see IsPinned).

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")
local Compat = ElvUI.Compat

-- Native frame size (QuestTimerFrame.xml); the height grows by 16 per timer.
local FRAME_WIDTH, FRAME_HEIGHT = 160, 72
local TITLE_X, TITLE_Y = 1, -5
local HOLDER_GAP = 4
local HOLDER_NAME = "ElvUIQuestTimerHolder"
local HOLDER_WAIT = 5

local function FindTitle(frame)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return nil end
	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "FontString" then return region end
	end
	return nil
end

local function StyleTitle(frame)
	local title = FindTitle(frame)
	if not title then return end
	pcall(title.ClearAllPoints, title)
	pcall(title.SetPoint, title, "TOP", frame, "TOP", TITLE_X, TITLE_Y)
	pcall(title.SetDrawLayer, title, "OVERLAY")
end

-- Default spot: under the minimap's data panels, else under the minimap,
-- else the top right corner.
local function PlaceHolder(holder)
	local below = _G.RightMiniPanel or _G.ElvUIMinimapHolder
	if below then
		holder:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -HOLDER_GAP)
	else
		holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -HOLDER_GAP, -260)
	end
end

-- Returns the function that re-anchors the frame onto the holder.
local function PinToHolder(frame)
	local okHolder, holder = pcall(CreateFrame, "Frame", HOLDER_NAME, UIParent)
	if not okHolder or not holder then return nil end
	holder:SetWidth(FRAME_WIDTH)
	holder:SetHeight(FRAME_HEIGHT)
	PlaceHolder(holder)
	E:CreateMover(holder, "QuestTimerFrameMover", _G.QUEST_TIMERS or "Quest Timers")

	local nativeClear, nativeSetPoint = frame.ClearAllPoints, frame.SetPoint
	local function Pin()
		pcall(nativeClear, frame)
		pcall(nativeSetPoint, frame, "TOP", holder, "TOP", 0, 0)
	end
	frame.SetPoint = Pin
	Pin()
	return Pin
end

-- True while the frame hangs on the holder alone. On Unreal Azeroth the
-- native MinimapCluster anchor is added past the replaced SetPoint method
-- (the frame ends up with two points and is drawn at the native spot), so
-- the anchor itself is checked. Compared by name: an anchor frame handed
-- back by GetPoint is not guaranteed to be the same Lua object.
local function IsPinned(frame)
	local okNum, num = pcall(frame.GetNumPoints, frame)
	if not okNum or num ~= 1 then return false end
	local okPoint, _, relative = pcall(frame.GetPoint, frame, 1)
	if not okPoint or not relative then return false end
	local okName, name = pcall(relative.GetName, relative)
	return okName and name == HOLDER_NAME
end

-- The holder waits for the minimap's data panels (created by the Layout
-- module, possibly after the skins run), so the mover's default spot is
-- under them; after HOLDER_WAIT seconds it settles for what exists. From
-- then on, every frame the timer box is shown, a foreign anchor is undone.
local function StartWatch(frame)
	local okWatch, watch = pcall(CreateFrame, "Frame", nil, UIParent)
	if not okWatch or not watch then return end
	local deadline = GetTime() + HOLDER_WAIT
	local pin
	watch:SetScript("OnUpdate", function()
		if not pin then
			if _G.RightMiniPanel or GetTime() > deadline then
				pin = PinToHolder(frame)
				if not pin then watch:SetScript("OnUpdate", nil) end
			end
			return
		end
		if Compat.bool(frame:IsShown()) and not IsPinned(frame) then pin() end
	end)
end

local applied = false
local function LoadSkin()
	if applied then return end
	local frame = _G.QuestTimerFrame
	if not frame then return end
	applied = true

	S:StripTextures(frame, false)
	S:CreatePanel(frame)
	StyleTitle(frame)
	StartWatch(frame)
end

S:AddBlizzardSkin("questtimer", LoadSkin)
