-- A third UI panel slot to the right, so a single window opens beside a
-- doublewide one (or beside two singles) instead of closing it.
--
-- The 1.12 panel manager (FrameXML UIParent.lua `ShowUIPanel`) knows only a
-- left and a centre slot. A doublewide frame takes both, and any "left"
-- frame opened while it is up closes it ("Close any doublewide frames"); a
-- doublewide frame in turn closes whatever is in the left and centre slots.
-- The later client (3.3.5 `FramePositionDelegate`) added a "right" slot for
-- exactly this, limited to pushable frames; here any "left" frame qualifies,
-- as long as it fits on screen. The skins resize the quest log, trade skill,
-- craft and trainer windows to doublewide, which is what makes this matter.
--
-- Wrapped and called through, never replaced: the native manager keeps
-- owning `UIParent.left` / `.center` / `.doublewide`; this file only owns the
-- one frame it parked to the right, and slides it back into a native slot
-- whenever one frees up. Both clients run this same Lua manager (on UA:
-- `UIParent.doublewide` is set, and a replaced `ShowUIPanel` sees the
-- keybinding opens).

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local M = E:GetModule("Misc")

-- Windows the player opens directly, made pushable so two of them open side
-- by side instead of replacing each other (natively both are 0). NPC
-- interaction windows (Merchant, Gossip, Quest, Taxi, Mail, ...) stay 0 and
-- keep replacing each other.
local PUSHABLE = {
	SpellBookFrame = 1,
	FriendsFrame = 1,
}

-- Native slot geometry (`SetLeftFrame` / `SetCenterFrame`).
local SLOT_WIDTH, SLOT_TOP = 384, -104

local rightFrame
local closingAll = false

local function IsShown(frame)
	if not frame then return false end
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and shown and true or false
end

local function AreaOf(frame)
	if not frame or type(_G.UIPanelWindows) ~= "table" then return nil end
	local ok, name = pcall(frame.GetName, frame)
	if not ok or not name then return nil end
	local info = _G.UIPanelWindows[name]
	return info and info.area
end

-- Native slots hold a frame until it is hidden THROUGH the manager; a frame
-- closed with a plain Hide() stays referenced. Only a shown frame counts.
local function ShownSlot(key)
	local frame = _G.UIParent[key]
	if IsShown(frame) then return frame end
	return nil
end

local function Place(frame, x, y)
	pcall(frame.ClearAllPoints, frame)
	pcall(frame.SetPoint, frame, "TOPLEFT", _G.UIParent, "TOPLEFT", x, y)
end

-- Converts a frame edge into UIParent offsets. The doublewide frames are
-- draggable, so the slot beside one follows wherever it was moved to. Its
-- visible edge is the skin panel when there is one (the frame itself runs
-- past it on the right).
local function EdgeInParent(frame)
	local box = frame.elvBackground or frame
	local okR, right = pcall(box.GetRight, box)
	local okT, top = pcall(frame.GetTop, frame)
	if not okR or not right or not okT or not top then return nil end
	local ratio = 1
	local okA, a = pcall(frame.GetEffectiveScale, frame)
	local okB, b = pcall(_G.UIParent.GetEffectiveScale, _G.UIParent)
	if okA and okB and a and b and b > 0 then ratio = a / b end
	local parentTop = _G.UIParent:GetTop() or 0
	local parentLeft = _G.UIParent:GetLeft() or 0
	return right * ratio - parentLeft, top * ratio - parentTop
end

local function Fits(frame, x)
	local okW, width = pcall(frame.GetWidth, frame)
	local okP, parentWidth = pcall(_G.UIParent.GetWidth, _G.UIParent)
	if not okW or not okP or not width or not parentWidth then return false end
	return x + width <= parentWidth
end

-- Parks `frame` in the right slot at (x, y). A frame already parked there is
-- replaced, the way a native slot replaces its occupant.
local function ParkRight(frame, x, y)
	if not Fits(frame, x) then return false end
	if rightFrame and rightFrame ~= frame then pcall(rightFrame.Hide, rightFrame) end
	rightFrame = frame
	Place(frame, x, y)
	pcall(frame.Show, frame)
	return true
end

local function ParkBeside(frame, doublewide)
	local x, y = EdgeInParent(doublewide)
	if not x then return false end
	return ParkRight(frame, x, y)
end

-- After any close: the parked frame moves into the first free native slot,
-- so no gap opens on the left. Beside a shown doublewide frame it stays.
local function Compact()
	if rightFrame and not IsShown(rightFrame) then rightFrame = nil end
	if not rightFrame or closingAll then return end
	if IsShown(_G.UIParent.doublewide) then return end

	local frame = rightFrame
	if not ShownSlot("left") then
		rightFrame = nil
		_G.UIParent.left = frame
		Place(frame, 0, SLOT_TOP)
	elseif not ShownSlot("center") then
		rightFrame = nil
		_G.UIParent.center = frame
		Place(frame, SLOT_WIDTH, SLOT_TOP)
	else
		Place(frame, SLOT_WIDTH * 2, SLOT_TOP)
	end
end

-- The native early-outs (dead player, a full-screen or a native "center"
-- frame up) are left to the original, which then does what it always did.
local function NativeOnly(frame, info)
	if not info then return true end
	if type(_G.GetFullScreenFrame) == "function" and _G.GetFullScreenFrame() then return true end
	if type(_G.CanOpenPanels) == "function" and not _G.CanOpenPanels() then return true end
	if not info.whileDead and _G.UnitIsDead("player") then return true end
	return false
end

-- A doublewide frame clears both native slots. One frame survives beside it:
-- the parked one if any, else the centre one, else the left one -- the most
-- recently placed. It is detached from its native slot first so the
-- manager does not hide it.
local function ShowDoublewide(origShow, frame, force)
	local keep = rightFrame
	if not keep then
		local center = ShownSlot("center")
		if center and AreaOf(center) == "left" then keep = center end
	end
	if not keep then keep = ShownSlot("left") end

	if keep then
		if _G.UIParent.left == keep then _G.UIParent.left = nil end
		if _G.UIParent.center == keep then _G.UIParent.center = nil end
		rightFrame = nil
	end

	origShow(frame, force)

	if keep and IsShown(frame) then
		if not ParkBeside(keep, frame) then pcall(keep.Hide, keep) end
	elseif keep then
		pcall(keep.Hide, keep)
	end
end

local function WrapShow()
	local origShow = _G.ShowUIPanel
	if type(origShow) ~= "function" then return end
	_G.ShowUIPanel = function(frame, force)
		if not frame or frame:IsVisible() then return origShow(frame, force) end
		local info = type(_G.UIPanelWindows) == "table" and _G.UIPanelWindows[frame:GetName() or ""]
		if NativeOnly(frame, info) then return origShow(frame, force) end
		if rightFrame and not IsShown(rightFrame) then rightFrame = nil end

		if info.area == "doublewide" then
			ShowDoublewide(origShow, frame, force)
			return
		end

		if info.area == "left" then
			local doublewide = _G.UIParent.doublewide
			if IsShown(doublewide) then
				if ParkBeside(frame, doublewide) then return end
			else
				local center = ShownSlot("center")
				if ShownSlot("left") and center and AreaOf(center) ~= "center" then
					if ParkRight(frame, SLOT_WIDTH * 2, SLOT_TOP) then return end
				end
			end
		end

		return origShow(frame, force)
	end
end

local function WrapHide()
	local origHide = _G.HideUIPanel
	if type(origHide) ~= "function" then return end
	_G.HideUIPanel = function(frame)
		if frame and frame == rightFrame then
			rightFrame = nil
			pcall(frame.Hide, frame)
			return
		end
		origHide(frame)
		Compact()
	end
end

-- Escape (and every other "close all" path) goes through CloseWindows, which
-- only knows the native slots. Its own HideUIPanel calls must not slide the
-- parked frame into a slot it is about to empty, hence `closingAll`.
local function WrapCloseWindows()
	local origClose = _G.CloseWindows
	if type(origClose) ~= "function" then return end
	_G.CloseWindows = function(ignoreCenter)
		closingAll = true
		local ok, found = pcall(origClose, ignoreCenter)
		closingAll = false
		-- An error inside the original surfaces exactly as without this
		-- wrapper; the pcall only guarantees the flag is cleared.
		if not ok then error(found, 0) end
		if IsShown(rightFrame) then
			pcall(rightFrame.Hide, rightFrame)
			found = 1
		end
		rightFrame = nil
		return found
	end
end

function M:LoadPanelSlots()
	if not _G.UIParent then return end
	if type(_G.UIPanelWindows) == "table" then
		local name, value
		for name, value in pairs(PUSHABLE) do
			local info = _G.UIPanelWindows[name]
			if type(info) == "table" then info.pushable = value end
		end
	end
	WrapShow()
	WrapHide()
	WrapCloseWindows()
end
