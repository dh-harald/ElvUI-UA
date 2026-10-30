local E, L, V, P, G = unpack(ElvUI)

-- Silent /who lookups of single player names, for Core/ClassCache.lua.
-- Real ElvUI uses LibWho-2.0 for this, which replaces the native SendWho,
-- SetWhoToUI and FriendsFrame_OnEvent globals and relies on
-- hooksecurefunc (absent on Unreal Azeroth). None of that is needed: with
-- the Social frame's WHO_LIST_UPDATE unregistered and SetWhoToUI(1), a
-- SendWho answers with WHO_LIST_UPDATE alone -- no window opens and nothing
-- is printed -- on both clients, also for a name with no match (0 results).
-- With SetWhoToUI(0) a reply of fewer than 4 names is printed to chat and
-- fires no event, so the state is set for every query and restored right
-- after its answer.
--
-- One query at a time, at least MIN_INTERVAL seconds apart (the server
-- answers a quicker one late). A query unanswered after TIMEOUT seconds is
-- reported as no match and stretches the interval, up to MAX_INTERVAL, as
-- LibWho does. Nothing is sent while the Social frame is open, so the
-- player's own /who browsing is never disturbed.
--
-- "n-Name" matches any name containing the text, so the answer is searched
-- for the exact name.

local Compat = ElvUI.Compat

local Who = {}
E.Who = Who

local MIN_INTERVAL, MAX_INTERVAL, TIMEOUT = 5, 10, 10

local interval = MIN_INTERVAL
local order = {}      -- names waiting, oldest first
local callbacks = {}  -- name -> list of callbacks
local pending         -- the name of the query in flight
local reply, replied  -- its answer, read in the event, handled on the next frame
local sentAt = 0
local lastSent = -MAX_INTERVAL

local driver = CreateFrame("Frame")
driver:Hide()

local function RestoreNative()
	pcall(FriendsFrame.RegisterEvent, FriendsFrame, "WHO_LIST_UPDATE")
	SetWhoToUI(0)
end

-- result: { name, level, class (localized), race, guild, zone } or nil.
local function Finish(result)
	local name = pending
	pending = nil
	RestoreNative()
	local list = callbacks[name]
	callbacks[name] = nil
	if not list then return end
	local i
	for i = 1, Compat.getn(list) do
		list[i](result)
	end
end

local function ReadResult(name)
	local count = GetNumWhoResults() or 0
	local i
	for i = 1, count do
		local whoName, guild, level, race, class, zone = GetWhoInfo(i)
		if whoName == name then
			return { name = whoName, level = level, class = class, race = race, guild = guild, zone = zone }
		end
	end
	return nil
end

local function SendNext()
	local name = table.remove(order, 1)
	if not name then return end
	pending = name
	sentAt = GetTime()
	lastSent = sentAt
	pcall(FriendsFrame.UnregisterEvent, FriendsFrame, "WHO_LIST_UPDATE")
	SetWhoToUI(1)
	SendWho("n-"..name)
end

driver:SetScript("OnUpdate", function()
	if replied then
		replied = false
		Finish(reply)
		return
	end
	local now = GetTime()
	if pending then
		if now - sentAt >= TIMEOUT then
			interval = math.min(interval + 0.5, MAX_INTERVAL)
			Finish(nil)
		end
		return
	end
	if not order[1] then
		driver:Hide()
		return
	end
	if now - lastSent >= interval and not FriendsFrame:IsShown() then
		SendNext()
	end
end)

-- The answer is read here, while GetWhoInfo holds it, but the native state
-- is restored on the next frame: on the 1.12.1 client a frame that
-- registers for an event while it is being dispatched can still receive
-- that same event (when frames registered after this one are yet to get
-- it), so re-registering the Social frame here opened its Who list.
driver:RegisterEvent("WHO_LIST_UPDATE")
driver:SetScript("OnEvent", function()
	if not pending or replied then return end
	reply = ReadResult(pending)
	replied = true
end)

-- Queues a lookup of `name`; `callback(result)` runs once with the
-- player's row, or nil when the player is not online or the query timed
-- out. A name already waiting gets the extra callback, not a second query.
function Who:Query(name, callback)
	if not name or name == "" then return end
	local list = callbacks[name]
	if list then
		table.insert(list, callback)
		return
	end
	callbacks[name] = { callback }
	table.insert(order, name)
	driver:Show()
end
