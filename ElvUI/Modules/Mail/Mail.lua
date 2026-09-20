-- Mail module -- bulk inbox handling and multi-item sending for the native
-- mailbox (MailFrame), the feature set Postal provides on this client
-- generation. Real ElvUI has no counterpart, so nothing here follows its
-- schema; the native frames stay in charge of mail data, tab switching and
-- the single-mail flow.
--
-- This file owns the module and the pieces its feature files share: the
-- sequential step runner every bulk operation needs, and the bag-space
-- count that stops an operation before the server refuses it. Feature
-- files (Inbox.lua and the ones beside it) attach with E:GetModule("Mail"), the same
-- arrangement Modules/Misc uses.
--
-- WHY A STEP RUNNER: every mail API call (TakeInboxItem, TakeInboxMoney,
-- ReturnInboxItem, SendMail) is ignored outright while a mail request is
-- already in flight, and none of them reports completion. So a bulk
-- operation cannot loop: it issues one call, then waits for the visible
-- state to change (the attachment is gone, the money is gone, the inbox
-- shrank) before issuing the next. A timeout ends the wait when the change
-- never arrives -- a unique item that cannot be taken, or a dropped
-- request -- so an operation can never hang forever.

local E, L, V, P, G = unpack(ElvUI)
local M = E:NewModule("Mail", "AceEvent-3.0", "AceHook-3.0")
E.Mail = M

-- AceTimer granularity; anything finer would only poll the same unchanged
-- state more often, since the client answers these on server round-trips.
M.POLL_INTERVAL = 0.1

-- How long one waited-for state change may take before the step is given
-- up on. Generous: this covers a server round-trip, not a local call.
M.STEP_TIMEOUT = 5

-- Arms a wait. `check` returns true once the awaited change happened;
-- `onDone` then runs. `onTimeout` runs instead if STEP_TIMEOUT passes
-- first. Only one wait exists at a time -- bulk operations are strictly
-- sequential by design.
function M:WaitFor(check, onDone, onTimeout)
	self.wait = {
		check = check,
		onDone = onDone,
		onTimeout = onTimeout,
		deadline = GetTime() + self.STEP_TIMEOUT,
	}
end

function M:ClearWait()
	self.wait = nil
end

-- The single poll every bulk operation runs on. While a wait is armed
-- nothing else advances, so an operation's own tick never has to know
-- whether a request is outstanding.
function M:Poll()
	local wait = self.wait
	if wait then
		local ok, done = pcall(wait.check)
		if ok and done then
			self.wait = nil
			if wait.onDone then wait.onDone() end
		elseif GetTime() > wait.deadline then
			self.wait = nil
			if wait.onTimeout then wait.onTimeout() end
		end
		return
	end

	if self.tick then self.tick() end
end

-- Free bag slots across the carried bags. GetContainerNumFreeSlots does not
-- exist on this client generation, so the slots are counted directly.
-- Deliberately counts every bag: a quiver or soul bag only accepts its own
-- item type, so this can overestimate by the free space in one. The number
-- is used to stop BEFORE the bags fill, and a bulk take stops on the first
-- item it cannot place anyway.
function M:FreeBagSlots()
	local free = 0
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		if slots and slots > 0 then
			for slot = 1, slots do
				local texture = GetContainerItemInfo(bag, slot)
				if not texture then free = free + 1 end
			end
		end
	end
	return free
end

-- This module's controls are drawn in this UI's style, so the window around
-- them has to be as well: with the module on, the mailbox is skinned even
-- when the per-window skin toggle is off. Done on the first MAIL_SHOW rather
-- than at init, because the Skins module initializes after this one.
function M:EnsureWindowSkin()
	if self.windowSkinned then return end
	self.windowSkinned = true

	local S = E:GetModule("Skins")
	if S and S.ApplyMailSkin then
		pcall(function() S:ApplyMailSkin() end)
	end
end

function M:Initialize()
	if not (E.global and E.global.mail and E.global.mail.enable) then return end

	self:LoadInbox()

	-- The Send tab's widgets sit on frames that exist from the start, so this
	-- needs no MAIL_SHOW: only the skin does, because the Skins module comes
	-- up after this one.
	self:LoadSend()
	self:LoadBlackBook()

	-- AceEvent passes no event arguments on this client; none are needed.
	self:RegisterEvent("MAIL_SHOW", function() M:EnsureWindowSkin() end)
	self:RegisterEvent("MAIL_CLOSED", function() M:OnMailClosed() end)

	E:ScheduleRepeatingTimer(function() M:Poll() end, M.POLL_INTERVAL)
end

E:RegisterInitialModule(M:GetName(), function() M:Initialize() end)
