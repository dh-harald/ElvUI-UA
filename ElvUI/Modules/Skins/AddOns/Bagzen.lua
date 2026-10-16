local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")
local Util = ElvUI.Util

-- Bagzen (one-bag addon): ElvUI's look on its bag and bank windows, their
-- bag rows and character lists, search boxes and item slots.
--
-- Bagzen's windows are XML frames that draw their own flat background as a
-- `$parentBackground` texture; it is hidden and the window gets ElvUI's panel
-- (S:CreatePanel) instead. Item slots come in three kinds: Bagzen's own
-- buttons, native ContainerFrame/BankFrame item buttons Bagzen reparents into
-- its grid, and native bag buttons in its bag row. All are ItemButton-shaped
-- and get Util.SkinItemButton.
--
-- Bagzen re-applies its own slot art (SetNormalTexture) and icon crop every
-- time it fills a borrowed button, and shows item quality by tinting that
-- NormalTexture through `Bagzen:SetSlotBorderColor`. That method is wrapped:
-- the slot is restyled and the colour goes to the ElvUI border instead.
-- `Bagzen:ContainerItemUpdate` is wrapped as well, to style slots that are
-- never coloured (empty bag-row buttons). Both are methods on Bagzen's addon
-- table, looked up at call time by every caller.

local WINDOWS = { "BagzenBagFrame", "BagzenBankFrame" }

-- White and grey are Bagzen's "no quality" colours (empty slot, common and
-- poor items); ElvUI keeps the default border for those.
local function IsPlainColor(r, g, b)
	if r == 1 and g == 1 and b == 1 then return true end
	local colors = _G.ITEM_QUALITY_COLORS
	if colors then
		local i
		for i = 0, 1 do
			local c = colors[i]
			if c and c.r == r and c.g == g and c.b == b then return true end
		end
	end
	return false
end

local function HideRegion(region)
	if not region then return end
	pcall(region.SetAlpha, region, 0)
	pcall(region.Hide, region)
end

-- Bagzen's scrap glow is a child frame of the slot (`<slot>AutoCast`, a Model;
-- `<slot>Shine` on 3.3.5) created at the slot's original level.
-- Util.SkinItemButton raises the slot, which would leave the glow under the
-- icon, so it is lifted above the slot and its cooldown (slot level + 2).
local GLOW_SUFFIXES = { "AutoCast", "Shine" }
local GLOW_LEVEL_OFFSET = 3

local function RaiseGlow(button, name)
	local okLevel, level = pcall(button.GetFrameLevel, button)
	if not okLevel or not tonumber(level) then return end
	local i
	for i = 1, table.getn(GLOW_SUFFIXES) do
		local glow = _G[name..GLOW_SUFFIXES[i]]
		if glow then
			pcall(glow.SetFrameLevel, glow, level + GLOW_LEVEL_OFFSET)
		end
	end
end

local function StyleSlot(button)
	if not button then return end
	local okName, name = pcall(button.GetName, button)
	if not okName or not name then return end
	local icon = _G[name.."IconTexture"]
	if not icon then return end

	Util.SkinItemButton(button)
	Util.RaiseCooldown(button)
	RaiseGlow(button, name)

	local okNormal, normal = pcall(button.GetNormalTexture, button)
	if okNormal then HideRegion(normal) end
	pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
end

local function ColorSlot(button, r, g, b)
	StyleSlot(button)
	if not button or not button.elvBackdrop then return end
	if IsPlainColor(r, g, b) then
		local border = Util.BORDER_COLOR
		r, g, b = border[1], border[2], border[3]
	end
	pcall(button.elvBackdrop.SetBackdropBorderColor, button.elvBackdrop, r, g, b, 1)
end

-- Every item-shaped button directly under `holder` (a bag's slot grid, the
-- bag row). Children are resolved through their global name: enumerated
-- native children are stripped-down objects on Unreal Azeroth.
local function StyleSlotsIn(holder)
	if not holder then return end
	local okKids, kids = pcall(function() return { holder:GetChildren() } end)
	if not okKids then return end
	local i
	for i = 1, table.getn(kids) do
		StyleSlot(S:ResolveWidget(kids[i]))
	end
end

-- Every slot of a window: its children are the per-bag slot grids and the bag
-- row. Bagzen fills its grids at login before this skin runs, so the slots it
-- built then are styled here rather than on their next update.
local function StyleAllSlots(frame)
	if not frame then return end
	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	if not okKids then return end
	local i
	for i = 1, table.getn(kids) do
		StyleSlotsIn(S:ResolveWidget(kids[i]))
	end
end

local function StyleWindowSlots(frame, bag)
	if not frame then return end
	local name = frame:GetName()
	if bag and Bagzen.FixBagNumber then
		local okBag, fixed = pcall(Bagzen.FixBagNumber, Bagzen, bag)
		if okBag then StyleSlotsIn(_G[name.."DummyBagSlotFrame"..fixed]) end
	end
	StyleSlotsIn(_G[name.."BagSlotsFrame"])
end

local function StylePanel(frame)
	if not frame then return end
	HideRegion(_G[frame:GetName().."Background"])
	S:CreatePanel(frame)
end

-- S:StyleEditBox sets its own symmetric text insets; the left one has to clear
-- Bagzen's magnifier icon again, as in Bagzen's template.
local function StyleSearchBox(box)
	if not box then return end
	S:StyleEditBox(box)
	pcall(box.SetTextInsets, box, 20, 4, 2, 2)
end

local function StyleWindow(frame)
	if not frame then return end
	local name = frame:GetName()
	StylePanel(frame)
	StylePanel(_G[name.."BagSlotsFrame"])
	StylePanel(_G[name.."CharactersFrame"])
	StyleSearchBox(_G[name.."SearchBox"])
	StyleSearchBox(_G[name.."CharactersFrameSearchBox"])
	StyleAllSlots(frame)
	S:TryHookScript(frame, "OnShow", function() pcall(StyleAllSlots, frame) end)
end

local function WrapMethods()
	local setColor = Bagzen.SetSlotBorderColor
	if type(setColor) == "function" then
		Bagzen.SetSlotBorderColor = function(self, button, r, g, b)
			setColor(self, button, r, g, b)
			pcall(ColorSlot, button, r, g, b)
		end
	end

	local itemUpdate = Bagzen.ContainerItemUpdate
	if type(itemUpdate) == "function" then
		Bagzen.ContainerItemUpdate = function(self, frame, bag)
			itemUpdate(self, frame, bag)
			pcall(StyleWindowSlots, frame, bag)
		end
	end
end

local function LoadSkin()
	if not Bagzen then return end
	local i
	for i = 1, table.getn(WINDOWS) do
		StyleWindow(_G[WINDOWS[i]])
	end
	WrapMethods()
end

S:AddAddOnSkin("Bagzen", LoadSkin)
