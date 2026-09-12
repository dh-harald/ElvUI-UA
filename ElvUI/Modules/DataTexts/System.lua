-- System DataText (FPS/latency) -- faithful port of real ElvUI's own
-- System.lua (source/ElvUI-vanilla/ElvUI/Modules/DataTexts/System.lua).
-- `onUpdate` driven by DataTexts.lua's periodic 1s timer, `t` always `1`
-- -- see DataTexts.lua's header comment for why.

local E, L, V, P, G = unpack(ElvUI)
local DT = E.DataTexts

local statusColors = {
	"|cff0CD809",
	"|cffE8DA0F",
	"|cffFF9000",
	"|cffD80909",
}

local enteredFrame = false
local totalMemory = 0

local function formatMem(memory)
	if memory > 999 then
		return string.format("%.2f mb", memory / 1024)
	else
		return string.format("%d kb", memory)
	end
end

local memoryTable = {}
local function RebuildAddonList()
	local addOnCount = GetNumAddOns()
	if addOnCount == table.getn(memoryTable) then return end

	memoryTable = {}
	local i
	for i = 1, addOnCount do
		local ok, name, title = pcall(GetAddOnInfo, i)
		memoryTable[i] = { i, (ok and title) or (ok and name) or "?" }
	end
end

local function OnClick()
	if arg1 == "RightButton" then
		collectgarbage()
	elseif arg1 == "LeftButton" then
		if GameMenuFrame:IsShown() then
			pcall(HideUIPanel, GameMenuFrame)
		else
			pcall(ShowUIPanel, GameMenuFrame)
		end
	end
end

local function OnEnter(self)
	enteredFrame = true
	DT:SetupTooltip(self)

	totalMemory = gcinfo()
	-- Positional capture, not `select(3, ...)`: `select` does not exist on
	-- the legacy client's Lua 5.0 at all.
	local _, _, homeLatency = GetNetStats()
	GameTooltip:AddDoubleLine("Home Latency:", string.format("%d ms", homeLatency), 0.69, 0.31, 0.31, 0.84, 0.75, 0.65)
	GameTooltip:AddDoubleLine("Total Memory:", formatMem(totalMemory), 0.69, 0.31, 0.31, 0.84, 0.75, 0.65)

	GameTooltip:AddLine(" ")
	local i
	for i = 1, table.getn(memoryTable) do
		local entry = memoryTable[i]
		if entry and IsAddOnLoaded(entry[1]) then
			GameTooltip:AddLine(entry[2])
		end
	end

	GameTooltip:Show()
end

local function OnLeave()
	enteredFrame = false
	GameTooltip:Hide()
end

local intAddon, intFps = 6, 5
local function OnUpdate(self, t)
	intAddon = intAddon - t
	intFps = intFps - t

	if intAddon < 0 then
		RebuildAddonList()
		intAddon = 10
	end

	if intFps < 0 then
		local framerate = math.floor(GetFramerate())
		local _, _, latency = GetNetStats()

		self.text:SetText(string.format("FPS: %s%d|r MS: %s%d|r",
			statusColors[framerate >= 30 and 1 or (framerate >= 20 and 2) or (framerate >= 10 and 3) or 4],
			framerate,
			statusColors[latency < 150 and 1 or (latency < 300 and 2) or (latency < 500 and 3) or 4],
			latency))
		intFps = 5
		if enteredFrame then
			OnEnter(self)
		end
	end
end

DT:RegisterDatatext("System", nil, nil, OnUpdate, OnClick, OnEnter, OnLeave, "System")
