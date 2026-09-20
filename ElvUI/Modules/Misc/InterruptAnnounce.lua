-- Interrupt announce: real ElvUI's general.interruptAnnounce. Real ElvUI
-- drives it from COMBAT_LOG_EVENT_UNFILTERED's SPELL_INTERRUPT, which does
-- not exist on this client; the 1.12 equivalent is the player's own combat
-- log line "You interrupt <unit>'s <spell>." (SPELLINTERRUPTSELFOTHER) on
-- CHAT_MSG_SPELL_SELF_DAMAGE, matched with LibDeformat-2.0. Like the
-- original it fires on true interrupts only (Kick, Pummel, Counterspell...);
-- a stun or fear that breaks a cast prints no interrupt line.
--
-- The message is real ElvUI's, minus the spell link (1.12 chat has no spell
-- hyperlinks). Channel rules are real ElvUI's too: nothing is sent while not
-- in a group, SAY/EMOTE included; inside a battleground PARTY/RAID go to
-- BATTLEGROUND.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Misc")

local Deformat = LibStub("LibDeformat-2.0", true)

local function Send(message, channel)
	pcall(SendChatMessage, message, channel)
end

local function Announce(unit, spell)
	local mode = E.db.general.interruptAnnounce
	if not mode or mode == "NONE" then return end

	local party = GetNumPartyMembers() or 0
	local raid = GetNumRaidMembers() or 0
	local message = string.format((_G.INTERRUPTED or L["Interrupted"]).." %s's %s!", unit, spell)

	if mode == "SAY" or mode == "EMOTE" then
		if party > 0 then Send(message, mode) end
		return
	end

	local _, instanceType = IsInInstance()
	local battleground = instanceType == "pvp"

	if mode == "PARTY" then
		if party > 0 then Send(message, battleground and "BATTLEGROUND" or "PARTY") end
	elseif mode == "RAID" then
		if raid > 0 then
			Send(message, battleground and "BATTLEGROUND" or "RAID")
		elseif party > 0 then
			Send(message, battleground and "BATTLEGROUND" or "PARTY")
		end
	elseif mode == "RAID_ONLY" then
		if raid > 0 then Send(message, battleground and "BATTLEGROUND" or "RAID") end
	end
end

local function OnSelfDamage()
	local mode = E.db.general.interruptAnnounce
	if not mode or mode == "NONE" then return end
	if type(arg1) ~= "string" or not SPELLINTERRUPTSELFOTHER then return end

	local unit, spell = Deformat(arg1, SPELLINTERRUPTSELFOTHER)
	if unit and spell then Announce(unit, spell) end
end

function M:LoadInterruptAnnounce()
	if not Deformat then return end

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
	frame:SetScript("OnEvent", OnSelfDamage)
end
