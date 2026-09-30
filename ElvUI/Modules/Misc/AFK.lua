-- AFK screen (general.afk), ported from ElvUI-vanilla's Modules/Misc/AFK.lua:
-- while the player is away the whole UI is hidden, the camera slowly circles
-- the character, and a bottom panel shows the character model, name, guild
-- and the time spent away; whispers and guild chat received meanwhile are
-- listed in the top left corner.
--
-- The screen opens on the "You are now AFK" system message with the
-- client's default text (MARKED_AFK_MESSAGE with DEFAULT_AFK_MESSAGE), so an
-- /afk with a custom text does not open it. It closes on the "no longer AFK"
-- message, on entering combat, on a battleground invitation, on any key
-- press or on a mouse click.
--
-- A key press or click also clears the AFK flag (Compat.ClearAFK), on both
-- clients: Unreal Azeroth never clears it by itself, and the legacy client
-- only on movement, which the keyboard-enabled frame swallows there.
--
-- Unreal Azeroth: a visible keyboard-enabled frame swallows every key, so
-- the mouse click is the guaranteed way out. The client has no
-- MoveViewLeftStart/Stop, so the camera is turned with FlipCameraYaw instead
-- (see Spin_OnUpdate). The model animation is called guarded, so a missing
-- method only loses that part of the screen.
--
-- The camera speed CVars are saved in E.global before they are changed, so a
-- client exit while the screen is up does not leave the camera turning at the
-- AFK speed: the next login restores them.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Misc")
local Compat = ElvUI.Compat

local AFK_SPEED = 7.35
local TEXTURES = "Interface\\AddOns\\ElvUI\\Media\\Textures\\"

-- Modifier keys alone never dismiss the screen; Print Screen takes a
-- screenshot instead.
local IGNORE_KEYS = { LALT = true, LSHIFT = true, RSHIFT = true }
local PRINT_KEYS = { PRINTSCREEN = true }

local CHAT_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_GUILD" }

local state = {
	shown = false,
	startTime = 0,
	timer = nil,
}

local frame -- ElvUIAFKFrame, built on first use

local function Call(fn, a, b, c)
	if type(fn) ~= "function" then return nil end
	local ok, r = pcall(fn, a, b, c)
	if ok then return r end
	return nil
end

local function InCombat()
	return Compat.bool(Call(UnitAffectingCombat, "player"))
end

local function CinematicShown()
	local cinematic = _G.CinematicFrame
	return cinematic and cinematic.IsShown and Compat.bool(cinematic:IsShown())
end

local function RestoreCamera()
	local g = E.global
	if g.afkCameraSpeedYaw then Call(SetCVar, "cameraYawMoveSpeed", g.afkCameraSpeedYaw) end
	if g.afkCameraSpeedPitch then Call(SetCVar, "cameraPitchMoveSpeed", g.afkCameraSpeedPitch) end
	g.afkEnabled, g.afkCameraSpeedYaw, g.afkCameraSpeedPitch = nil, nil, nil
end

-- Unreal Azeroth has no MoveViewLeftStart/Stop; there the AFK frame's own
-- OnUpdate turns the camera with FlipCameraYaw by AFK_SPEED degrees per
-- second (see BuildFrame), which stops by itself when the frame hides, and
-- the speed CVars are left alone.
local function Spin_OnUpdate()
	pcall(FlipCameraYaw, (arg1 or 0) * AFK_SPEED)
end

local function StartCamera()
	if type(MoveViewLeftStart) ~= "function" then return end
	local g = E.global
	g.afkEnabled = true
	g.afkCameraSpeedYaw = Call(GetCVar, "cameraYawMoveSpeed")
	g.afkCameraSpeedPitch = Call(GetCVar, "cameraPitchMoveSpeed")
	Call(SetCVar, "cameraYawMoveSpeed", AFK_SPEED)
	Call(MoveViewLeftStart)
end

local function StopCamera()
	if not E.global.afkEnabled then return end
	Call(MoveViewLeftStop)
	RestoreCamera()
end

local function UpdateTime()
	if not frame then return end
	local t = math.floor(GetTime() - state.startTime)
	frame.bottom.time:SetText(string.format("%02d:%02d", math.floor(t / 60), Compat.mod(t, 60)))
end

-- The model waves once (animation 67) over three seconds after the screen
-- opens.
local function Model_OnUpdate()
	this.animTime = (this.animTime or 0) + (arg1 or 0) * 1000
	if not pcall(this.SetSequenceTime, this, 67, this.animTime) or this.animTime >= 3000 then
		pcall(this.SetSequenceTime, this, 0, 0)
		this:SetScript("OnUpdate", nil)
	end
end

local function RefreshGuild()
	local ok, guild, rank = false, nil, nil
	if type(GetGuildInfo) == "function" then ok, guild, rank = pcall(GetGuildInfo, "player") end
	if ok and guild and Compat.bool(Call(IsInGuild)) then
		frame.bottom.guild:SetText(string.format("%s - %s", guild, rank or ""))
	else
		frame.bottom.guild:SetText(L["No Guild"])
	end
end

local function RefreshModel()
	local model = frame.bottom.model
	pcall(model.SetUnit, model, "player")
	pcall(model.SetModelScale, model, 0.8)
	pcall(model.SetFacing, model, 6)
	model.animTime = 0
	model:SetScript("OnUpdate", Model_OnUpdate)
end

local function Chat_OnEvent()
	local chatType = string.sub(event, 10)
	local fmt = _G["CHAT_"..chatType.."_GET"] or "%s: "
	local sender = arg2 or ""
	local link = "|Hplayer:"..sender.."|h["..sender.."]|h"
	local ok, prefix = pcall(string.format, fmt, link)
	if not ok then prefix = "["..sender.."]: " end

	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
	local r, g, b = 1, 1, 1
	if info then r, g, b = info.r or 1, info.g or 1, info.b or 1 end
	this:AddMessage(prefix..(arg1 or ""), r, g, b)
end

local function Chat_OnMouseWheel()
	if arg1 and arg1 > 0 then
		if IsShiftKeyDown() then this:ScrollToTop() else this:ScrollUp() end
	else
		if IsShiftKeyDown() then this:ScrollToBottom() else this:ScrollDown() end
	end
end

local function SetChatEvents(on)
	local chat = frame.chat
	local i
	for i = 1, Compat.getn(CHAT_EVENTS) do
		if on then
			chat:RegisterEvent(CHAT_EVENTS[i])
		else
			pcall(chat.UnregisterEvent, chat, CHAT_EVENTS[i])
		end
	end
end

local function Dismiss()
	M:SetAFK(false)
	Compat.ClearAFK()
end

local function Frame_OnKeyDown()
	if IGNORE_KEYS[arg1] then return end
	if PRINT_KEYS[arg1] then
		Call(Screenshot)
		return
	end
	Dismiss()
end

local function Frame_OnMouseDown()
	Dismiss()
end

local function BuildChat(parent)
	local chat = CreateFrame("ScrollingMessageFrame", "ElvUIAFKChat", parent)
	chat:SetWidth(500)
	chat:SetHeight(200)
	chat:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -3)
	E:FontTemplate(chat)
	chat:SetJustifyH("LEFT")
	chat:SetMaxLines(500)
	chat:SetFading(false)
	chat:EnableMouse(true)
	chat:EnableMouseWheel(true)
	chat:SetScript("OnMouseWheel", Chat_OnMouseWheel)
	chat:SetScript("OnEvent", Chat_OnEvent)
	return chat
end

local function NewText(parent, anchor, relPoint, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	E:FontTemplate(fs, nil, 20)
	fs:SetPoint("TOPLEFT", anchor, relPoint, x, y)
	fs:SetTextColor(0.7, 0.7, 0.7)
	return fs
end

local function BuildBottom(parent)
	local bottom = CreateFrame("Frame", nil, parent)
	bottom:SetFrameLevel(parent:GetFrameLevel())
	E:SetTemplate(bottom, "Transparent")
	bottom:SetPoint("BOTTOM", parent, "BOTTOM", 0, -1)
	-- UIParent's size, not GetScreenWidth(): on Unreal Azeroth the two are in
	-- different units.
	bottom:SetWidth(UIParent:GetWidth() + 2)
	bottom:SetHeight(UIParent:GetHeight() * 0.1)

	local logo = parent:CreateTexture(nil, "OVERLAY")
	logo:SetWidth(320)
	logo:SetHeight(150)
	logo:SetPoint("CENTER", bottom, "CENTER", 0, 50)
	logo:SetTexture(TEXTURES.."logo")
	bottom.logo = logo

	local faction = bottom:CreateTexture(nil, "OVERLAY")
	faction:SetWidth(140)
	faction:SetHeight(140)
	faction:SetPoint("BOTTOMLEFT", bottom, "BOTTOMLEFT", -20, -16)
	local group = Call(UnitFactionGroup, "player")
	if group == "Alliance" or group == "Horde" then
		faction:SetTexture(TEXTURES..group.."-Logo")
	end
	bottom.faction = faction

	local name = NewText(bottom, faction, "TOPRIGHT", -10, -28)
	name:SetText(string.format("%s - %s", E.myname or "", E.myrealm or ""))
	local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[E.myclass]
	if color then name:SetTextColor(color.r, color.g, color.b) end
	bottom.name = name

	bottom.guild = NewText(bottom, name, "BOTTOMLEFT", 0, -6)
	bottom.guild:SetText(L["No Guild"])
	bottom.time = NewText(bottom, bottom.guild, "BOTTOMLEFT", 0, -6)
	bottom.time:SetText("00:00")

	local model = CreateFrame("PlayerModel", "ElvUIAFKPlayerModel", bottom)
	model:SetWidth(800)
	model:SetHeight(800)
	model:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 120, -100)
	bottom.model = model

	return bottom
end

-- Parentless, so hiding UIParent leaves it on screen; it copies UIParent's
-- scale because a parentless frame does not inherit it.
local function BuildFrame()
	local f = CreateFrame("Frame", "ElvUIAFKFrame")
	f:SetFrameStrata("FULLSCREEN")
	f:SetScale(UIParent:GetScale())
	f:SetAllPoints(UIParent)
	f:Hide()
	f:EnableKeyboard(true)
	f:EnableMouse(true)
	f:SetScript("OnKeyDown", Frame_OnKeyDown)
	f:SetScript("OnMouseDown", Frame_OnMouseDown)
	if type(MoveViewLeftStart) ~= "function" and type(FlipCameraYaw) == "function" then
		f:SetScript("OnUpdate", Spin_OnUpdate)
	end

	f.chat = BuildChat(f)
	f.bottom = BuildBottom(f)
	return f
end

function M:SetAFK(status)
	if status and not state.shown then
		if not frame then frame = BuildFrame() end
		state.shown = true

		local inspect = _G.InspectPaperDollFrame
		if inspect and inspect.Hide then pcall(inspect.Hide, inspect) end

		UIParent:Hide()
		frame:Show()
		StartCamera()

		RefreshGuild()
		RefreshModel()
		state.startTime = GetTime()
		frame.bottom.time:SetText("00:00")
		state.timer = E:ScheduleRepeatingTimer(UpdateTime, 1)
		SetChatEvents(true)
	elseif not status and state.shown then
		state.shown = false
		frame:Hide()
		UIParent:Show()
		StopCamera()

		if state.timer then E:CancelTimer(state.timer) end
		state.timer = nil
		SetChatEvents(false)
		-- Unreal Azeroth's ScrollingMessageFrame has no Clear: there the
		-- lines of earlier AFK sessions stay, up to SetMaxLines.
		if frame.chat.Clear then pcall(frame.chat.Clear, frame.chat) end
	end
end

local function BattlefieldConfirm()
	local i
	for i = 1, (_G.MAX_BATTLEFIELD_QUEUES or 3) do
		if Call(GetBattlefieldStatus, i) == "confirm" then return true end
	end
	return false
end

local function TryEnter()
	if not E.db.general.afk then return end
	if InCombat() or CinematicShown() then return end
	M:SetAFK(true)
end

-- A "now AFK" reply to Compat.ClearAFK's own command is not the player going
-- away, so it does not open the screen.
local function OnSystemMessage(msg)
	local kind = Compat.AFKMessage(msg)
	if kind == "CLEARED" then
		M:SetAFK(false)
	elseif kind == "AFK" and not Compat.IsClearingAFK() then
		local default = _G.DEFAULT_AFK_MESSAGE and string.format(_G.MARKED_AFK_MESSAGE, _G.DEFAULT_AFK_MESSAGE)
		if msg == default then TryEnter() end
	end
end

local function OnEvent()
	if event == "PLAYER_REGEN_DISABLED" then
		M:SetAFK(false)
	elseif event == "UPDATE_BATTLEFIELD_STATUS" then
		if BattlefieldConfirm() then M:SetAFK(false) end
	elseif event == "CHAT_MSG_SYSTEM" and type(arg1) == "string" then
		OnSystemMessage(arg1)
	end
end

local EVENTS = { "CHAT_MSG_SYSTEM", "PLAYER_REGEN_DISABLED", "UPDATE_BATTLEFIELD_STATUS" }
local listener

-- Applies general.afk; the options toggle calls this.
function M:ToggleAFK()
	if not listener then
		listener = CreateFrame("Frame")
		listener:SetScript("OnEvent", OnEvent)
	end
	local i
	for i = 1, Compat.getn(EVENTS) do
		if E.db.general.afk then
			listener:RegisterEvent(EVENTS[i])
		else
			pcall(listener.UnregisterEvent, listener, EVENTS[i])
		end
	end
	if E.db.general.afk then
		Call(SetCVar, "autoClearAFK", "1")
	else
		M:SetAFK(false)
	end
end

function M:LoadAFK()
	if E.global.afkEnabled then RestoreCamera() end
	self:ToggleAFK()
end
