local E, L, V, P, G = unpack(ElvUI)
local M = E:GetModule("Misc")

-- Chat bubbles, ported from real ElvUI's Modules/Misc/ChatBubbles.lua
-- (ElvUI-vanilla). Settings: `E.private.general.chatBubbles` (backdrop /
-- backdrop_noborder / nobackdrop / disabled), `chatBubbleFont`,
-- `chatBubbleFontSize`, `chatBubbleFontOutline`, `chatBubbleName`; all read
-- once at login.
--
-- A bubble is an unnamed WorldFrame child the client creates on first use and
-- reuses afterwards (hidden in between), so the WorldFrame children are
-- rescanned whenever their count changes. Recognition differs per client:
--   1.12.1: a region textured `Interface\Tooltips\ChatBubble-Background`
--           (real ElvUI's test).
--   Unreal Azeroth: the widget's metatable `__name` names its engine class,
--           `FChatBubbleFrame`. Its only regions are the tail texture and the
--           text; the background and rounded border are the frame's own
--           backdrop and are muted with a fully transparent backdrop colour
--           (they ignore DisableDrawLayer). The tail is hidden rather than
--           cleared, as SetTexture(nil) is unreliable there. Both settings
--           survive the frame's reuse.
--
-- The ElvUI look is drawn with textures created on the bubble itself (real
-- ElvUI's non-pixel-perfect branch) instead of a backdrop on the native frame:
-- the fill on BACKGROUND, so the bubble's own text stays above it, and a
-- 1-unit border in the text colour (white for /say, red for /yell, ...) with
-- a black outline. Real ElvUI's pixel-perfect branch is not ported; this
-- project has no pixel-perfect scale.
--
-- Each shown bubble is checked on every scan for a new message: the border
-- takes the new text colour, the font is set again (the client may restore its
-- own when it reuses the frame) and, with `chatBubbleName`, the speaker's name
-- is written above it. The speaker comes from the matching chat event, keyed
-- by message text, as in real ElvUI; it is shown uncoloured, as this project
-- has no class cache. Real ElvUI's class-coloured name mentions inside the
-- bubble text (`classColorMentionsSpeech`) are not ported for the same reason.

local LSM = LibStub("LibSharedMedia-3.0", true)
local getn = ElvUI.Compat.getn

local SCAN_INTERVAL = 0.1
local UA_BUBBLE_CLASS = "FChatBubbleFrame"
local LEGACY_BUBBLE_TEXTURE = "interface\\tooltips\\chatbubble-background"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local EDGE = 1
-- The message -> speaker cache is dropped once it holds this many entries.
local SENDER_CACHE_LIMIT = 200

local SENDER_EVENTS = {
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_MONSTER_SAY",
	"CHAT_MSG_MONSTER_YELL",
}

local messageToSender = {}
local senderCount = 0
local bubbles = {}
local numChildren = 0

local function IsUABubble(frame)
	local ok, mt = pcall(getmetatable, frame)
	if not ok or type(mt) ~= "table" then return false end
	local class = rawget(mt, "__name")
	return type(class) == "string" and string.find(class, UA_BUBBLE_CLASS, 1, true) ~= nil
end

local function HasBubbleTexture(frame)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok or type(regions) ~= "table" then return false end
	local i
	for i = 1, getn(regions) do
		local region = regions[i]
		local okTex, texture = pcall(function() return region.GetTexture and region:GetTexture() end)
		if okTex and type(texture) == "string" and string.lower(texture) == LEGACY_BUBBLE_TEXTURE then
			return true
		end
	end
	return false
end

local function IsChatBubble(frame)
	if ElvUI.Compat.isUA then return IsUABubble(frame) end
	return HasBubbleTexture(frame)
end

-- Hides the client's own bubble art and returns the bubble's text.
local function MuteNative(frame)
	local text
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if ok and type(regions) == "table" then
		local i
		for i = 1, getn(regions) do
			local region = regions[i]
			local okType, kind = pcall(region.GetObjectType, region)
			if okType and kind == "Texture" then
				if ElvUI.Compat.isUA then
					pcall(region.Hide, region)
				else
					pcall(region.SetTexture, region, nil)
				end
			elseif okType and kind == "FontString" then
				text = region
			end
		end
	end
	pcall(frame.SetBackdropColor, frame, 0, 0, 0, 0)
	pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
	return text
end

local function NewTexture(frame, layer, r, g, b, a)
	local tex = frame:CreateTexture(nil, layer)
	tex:SetTexture(WHITE)
	tex:SetVertexColor(r, g, b, a or 1)
	return tex
end

local function FillColor()
	local c = E.db.general and E.db.general.backdropfadecolor
	if type(c) ~= "table" then return 0.06, 0.06, 0.06, 0.8 end
	return c.r, c.g, c.b, c.a or 0.8
end

-- The border, real ElvUI's geometry: on each side a line in the text colour,
-- 2*EDGE outside the bubble, centred on a black line three times as thick.
-- Each entry: the two anchor points shared by the line and the bubble, the
-- line's offsets from them, the outline's offsets from the line, and whether
-- the side runs horizontally.
local BORDER_SIDES = {
	{ "TOPLEFT", "TOPRIGHT", -2, 2, 2, 2, -1, 1, 1, 1, true },
	{ "BOTTOMLEFT", "BOTTOMRIGHT", -2, -2, 2, -2, -1, -1, 1, -1, true },
	{ "TOPLEFT", "BOTTOMLEFT", -2, 2, -2, -2, -1, 1, -1, -1, false },
	{ "TOPRIGHT", "BOTTOMRIGHT", 2, 2, 2, -2, 1, 1, 1, -1, false },
}

local function BuildBorder(frame)
	local lines = {}
	local i
	for i = 1, getn(BORDER_SIDES) do
		local s = BORDER_SIDES[i]
		local line = NewTexture(frame, "ARTWORK", 1, 1, 1)
		line:SetPoint(s[1], frame, s[1], s[3] * EDGE, s[4] * EDGE)
		line:SetPoint(s[2], frame, s[2], s[5] * EDGE, s[6] * EDGE)
		local outline = NewTexture(frame, "BORDER", 0, 0, 0)
		outline:SetPoint(s[1], line, s[1], s[7] * EDGE, s[8] * EDGE)
		outline:SetPoint(s[2], line, s[2], s[9] * EDGE, s[10] * EDGE)
		if s[11] then
			line:SetHeight(EDGE)
			outline:SetHeight(EDGE * 3)
		else
			line:SetWidth(EDGE)
			outline:SetWidth(EDGE * 3)
		end
		lines[i] = line
	end
	return lines
end

local function ApplyFont(frame)
	local general = E.private.general
	local path = LSM and LSM:Fetch("font", general.chatBubbleFont)
	if frame.elvBubbleText then
		E:FontTemplate(frame.elvBubbleText, path, general.chatBubbleFontSize, general.chatBubbleFontOutline)
	end
	if frame.elvBubbleName then
		E:FontTemplate(frame.elvBubbleName, path, general.chatBubbleFontSize * 0.85, general.chatBubbleFontOutline)
	end
end

local function SkinBubble(frame)
	local style = E.private.general.chatBubbles
	frame.elvBubble = true
	frame.elvBubbleText = MuteNative(frame)

	local name = frame:CreateFontString(nil, "OVERLAY")
	if style == "backdrop" then
		name:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, 19)
	else
		name:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, 6)
	end
	name:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -5, -5)
	name:SetJustifyH("LEFT")
	name:SetTextColor(1, 1, 1)
	frame.elvBubbleName = name

	if style == "backdrop" then
		local fill = NewTexture(frame, "BACKGROUND", FillColor())
		fill:SetAllPoints(frame)
		frame.elvBubbleBorder = BuildBorder(frame)
	elseif style == "backdrop_noborder" then
		local fill = NewTexture(frame, "BACKGROUND", FillColor())
		fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
		fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
		pcall(frame.SetClampedToScreen, frame, false)
	elseif style == "nobackdrop" then
		pcall(frame.SetClampedToScreen, frame, false)
		name:Hide()
	end

	pcall(frame.SetFrameStrata, frame, "DIALOG")
	ApplyFont(frame)
	table.insert(bubbles, frame)
end

local function UpdateBorderColor(frame, r, g, b)
	local border = frame.elvBubbleBorder
	if not border or type(r) ~= "number" then return end
	local i
	for i = 1, getn(border) do
		border[i]:SetVertexColor(r, g, b, 1)
	end
end

local function UpdateName(frame, message)
	local name = frame.elvBubbleName
	if not name then return end
	local sender = E.private.general.chatBubbleName and message and messageToSender[message]
	name:SetText(sender or "")
end

-- Restyles a shown bubble once per new message. A message counts as new when
-- its text or its colour changes: the client can reuse a shown bubble for the
-- same line on another channel (/say, then /yell), changing only the colour.
-- A hidden bubble forgets its last message, so the same line said again later
-- is restyled too.
local function UpdateBubble(frame)
	local okShown, shown = pcall(frame.IsShown, frame)
	if not okShown or not ElvUI.Compat.bool(shown) then
		frame.elvBubbleLast = nil
		return
	end
	local text = frame.elvBubbleText
	if not text then return end
	local okText, message = pcall(text.GetText, text)
	if not okText then return end
	local okColor, r, g, b = pcall(text.GetTextColor, text)
	if not okColor then r, g, b = nil, nil, nil end
	local key = tostring(message) .. ":" .. tostring(r) .. ":" .. tostring(g) .. ":" .. tostring(b)
	if key == frame.elvBubbleLast then return end
	frame.elvBubbleLast = key
	ApplyFont(frame)
	UpdateBorderColor(frame, r, g, b)
	UpdateName(frame, message)
end

local function Scan()
	local count = WorldFrame:GetNumChildren()
	if count ~= numChildren then
		numChildren = count
		local kids = { WorldFrame:GetChildren() }
		local i
		for i = 1, getn(kids) do
			local frame = kids[i]
			if not frame.elvBubble and IsChatBubble(frame) then
				SkinBubble(frame)
			end
		end
	end
	local i
	for i = 1, getn(bubbles) do
		UpdateBubble(bubbles[i])
	end
end

local function OnSenderEvent()
	if not E.private.general.chatBubbleName then return end
	if type(arg1) ~= "string" then return end
	if senderCount >= SENDER_CACHE_LIMIT then
		messageToSender = {}
		senderCount = 0
	end
	if not messageToSender[arg1] then senderCount = senderCount + 1 end
	messageToSender[arg1] = arg2
end

function M:LoadChatBubbles()
	if E.private.general.chatBubbles == "disabled" then return end

	local events = CreateFrame("Frame")
	local i
	for i = 1, getn(SENDER_EVENTS) do
		events:RegisterEvent(SENDER_EVENTS[i])
	end
	events:SetScript("OnEvent", OnSenderEvent)

	E:ScheduleRepeatingTimer(function() pcall(Scan) end, SCAN_INTERVAL)
end
