-- DataTexts module -- the small text "widgets" (Gold, Time, Durability,
-- System/FPS, ...) real ElvUI shows on thin panels (2 hooked to the chat
-- frames, 1 to the Minimap). Panel creation belongs to the module that
-- owns the panel's frame: `Modules/Chat/Chat.lua` creates/registers
-- LeftChatDataPanel/RightChatDataPanel, `Layout/Layout.lua`
-- creates/registers LeftMiniPanel/RightMiniPanel. This file's own job is
-- limited to the widgets themselves and the panel REGISTRATION API
-- (RegisterPanel/RegisterDatatext), which works the same regardless of
-- which panel a widget ends up on.
--
-- Real module: ElvUI-vanilla/ElvUI/Modules/DataTexts/DataTexts.lua
-- (324 lines). Adapted for this project in a few places:
--   - Tooltip: real ElvUI builds its OWN skinned "DatatextTooltip" frame
--     via a Tooltip module (`TT:SetStyle`) this project doesn't have.
--     Uses the plain native `GameTooltip` directly instead, matching how
--     every other module here already falls back to native chrome when a
--     Skins-style helper is missing.
--   - `AssignPanelToDataText`'s `data.onUpdate` is driven by a periodic
--     `E:ScheduleRepeatingTimer` instead of real ElvUI's raw
--     `panel:SetScript("OnUpdate", ...)` -- raw OnUpdate is unreliable on
--     UA, so this project avoids it project-wide. The timer fires at a
--     FIXED 1-second interval and always passes `t = 1`, so a widget that
--     throttles its own work with an `int = int - t` countdown (System.lua)
--     still counts real elapsed seconds, just in discrete ticks instead of
--     continuous frame deltas. One second is therefore also the finest
--     refresh any widget can get here -- which is why Time.lua drops the
--     countdown entirely and repaints on CHANGE instead (see its header).
--   - The LeftChatDataPanel/RightChatDataPanel-only "battleground score"
--     special case in real `LoadDataTexts` (UPDATE_BATTLEFIELD_SCORE) is
--     dropped entirely -- chat-panel-specific, out of scope this pass.
--   - LibDataBroker-1.1 is vendored and wired up: `RegisterLDB`/
--     `SetupObjectLDB` let any addon exposing an LDB data object
--     (a "launcher" style minimap-button addon, a boss-mod status text,
--     etc.) be selected as a datatext widget, same as real ElvUI.

local E, L, V, P, G = unpack(ElvUI)
local DT = E:NewModule("DataTexts", "AceEvent-3.0")
E.DataTexts = DT

local LDB = LibStub("LibDataBroker-1.1", true)
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Settings: `P.datatexts` (Settings/Profile.lua). Its `panels` table
-- registers this project's actual panels -- LeftMiniPanel/RightMiniPanel
-- (Layout.lua) and LeftChatDataPanel/RightChatDataPanel (Chat.lua).
-- `leftChatPanel`/`rightChatPanel` (show/hide the two chat datatext panels)
-- are read by Chat.lua at runtime.

DT.RegisteredPanels = {}
DT.RegisteredDataTexts = {}

DT.PointLocation = {
	[1] = "middle",
	[2] = "left",
	[3] = "right",
}

function DT:GetDataPanelPoint(panel, i, numPoints)
	if numPoints == 1 then
		return "CENTER", panel, "CENTER"
	else
		if i == 1 then
			return "CENTER", panel, "CENTER"
		elseif i == 2 then
			return "RIGHT", panel.dataPanels.middle, "LEFT", -4, 0
		elseif i == 3 then
			return "LEFT", panel.dataPanels.middle, "RIGHT", 4, 0
		end
	end
end

-- The bars are sized by their anchors, and on the 1.12.1 client such a
-- frame's GetWidth() returns its width multiplied by the UI scale (285.6 for
-- a 386-wide bar at scale 0.74), which packed the side widgets toward the
-- middle. The edges are real on both clients; GetWidth() is only the fallback
-- for a bar not laid out yet.
local function PanelWidth(panel)
	local left, right = panel:GetLeft(), panel:GetRight()
	if left and right and right > left then
		return right - left
	end
	return panel:GetWidth()
end

function DT:UpdateAllDimensions()
	local panelName, panel
	for panelName, panel in pairs(DT.RegisteredPanels) do
		local width = (PanelWidth(panel) / panel.numPoints) - 4
		local height = panel:GetHeight() - 4
		local i
		for i = 1, panel.numPoints do
			local pointIndex = DT.PointLocation[i]
			local dataPanel = panel.dataPanels[pointIndex]
			dataPanel:SetWidth(width)
			dataPanel:SetHeight(height)
			dataPanel:ClearAllPoints()
			dataPanel:SetPoint(DT:GetDataPanelPoint(panel, i, panel.numPoints))
			-- The label's own width tracks the panel's, because that is what
			-- `SetJustifyH("CENTER")` centres within -- see `RegisterPanel`
			-- for why the FontString is not simply pinned to all four sides.
			if dataPanel.text then
				pcall(dataPanel.text.SetWidth, dataPanel.text, width)
			end
		end
	end
end

function DT:Data_OnLeave()
	GameTooltip:Hide()
end

-- Simplified anchor (real ElvUI positions the tooltip via a per-panel
-- `anchor`/`xOff`/`yOff` set by whatever Skins-module code created that
-- specific panel type -- this project has no such system) -- a plain,
-- always-sensible ANCHOR_TOPLEFT relative to the widget itself.
function DT:SetupTooltip(panel)
	GameTooltip:SetOwner(panel, "ANCHOR_TOPLEFT")
	GameTooltip:ClearLines()
end

function DT:RegisterPanel(panel, numPoints, anchor, xOff, yOff)
	DT.RegisteredPanels[panel:GetName()] = panel
	panel.dataPanels = {}
	panel.numPoints = numPoints

	panel.xOff = xOff
	panel.yOff = yOff
	panel.anchor = anchor

	local i
	for i = 1, numPoints do
		local pointIndex = DT.PointLocation[i]
		if not panel.dataPanels[pointIndex] then
			local dataPanel = CreateFrame("Button", panel:GetName().."DataText"..i, panel)
			pcall(dataPanel.RegisterForClicks, dataPanel, "LeftButtonUp", "RightButtonUp")
			local text = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			-- A SINGLE `CENTER` point plus an EXPLICIT WIDTH (set alongside
			-- the panel's own in `UpdateAllDimensions`). Both halves matter,
			-- and each of the other two shapes gets exactly one of them
			-- right:
			--   * `SetAllPoints()` gives the width (so `SetJustifyH`
			--     centres horizontally) but also the full panel HEIGHT, and
			--     where the glyphs sit inside that taller box is left to
			--     `SetJustifyV` -- which is how the text ended up riding
			--     visibly high in the bar.
			--   * `LEFT`+`RIGHT` anchors with no width fixes the height, but
			--     the FontString then auto-sizes to its own text and
			--     `SetJustifyH` has no spare room to centre in, so every
			--     label sat flush against its left edge.
			-- One CENTER point makes the vertical centre exact without
			-- `SetJustifyV` (the box is only as tall as the text), and the
			-- explicit width gives `SetJustifyH("CENTER")` the panel-third
			-- to centre within.
			text:SetPoint("CENTER", dataPanel, "CENTER")
			text:SetJustifyH("CENTER")
			-- The label half of every widget is uncoloured text, so it takes
			-- the FontString's own colour; real ElvUI's is white. The
			-- `GameFontNormal` template, which only supplies a font until
			-- `LoadDataTexts` applies the configured one, is gold on the legacy
			-- client and white on UA, so the colour is set here.
			text:SetTextColor(1, 1, 1)
			dataPanel.text = text
			panel.dataPanels[pointIndex] = dataPanel
		end

		panel.dataPanels[pointIndex]:ClearAllPoints()
		panel.dataPanels[pointIndex]:SetPoint(DT:GetDataPanelPoint(panel, i, numPoints))
	end

	panel:SetScript("OnSizeChanged", function() DT:UpdateAllDimensions() end)
	DT:UpdateAllDimensions()
end

function DT:AssignPanelToDataText(panel, data)
	panel.name = data.name or ""

	if data.events then
		local i
		for i = 1, table.getn(data.events) do
			local eventName = data.events[i]
			-- Matches real ElvUI's own substitution exactly
			-- (DataTexts.lua:192-194, "random error 132") -- registering
			-- PLAYER_ENTERING_WORLD directly on a plain Button in vanilla
			-- errors; PLAYER_LOGIN fires at the same point for this
			-- purpose (data-text widgets only ever want "the game has
			-- loaded", not the exact semantic difference between the two).
			if eventName == "PLAYER_ENTERING_WORLD" then
				eventName = "PLAYER_LOGIN"
			end
			pcall(panel.RegisterEvent, panel, eventName)
		end
	end

	if data.eventFunc then
		panel:SetScript("OnEvent", function()
			data.eventFunc(this, event)
		end)
		pcall(data.eventFunc, panel, "ELVUI_FORCE_RUN")
	end

	-- Periodic timer instead of real ElvUI's raw OnUpdate -- see this
	-- file's own header comment for why. `data.onUpdate` itself is
	-- untouched (still receives `(self, t)` the same shape it always
	-- did) -- only the DRIVER changed.
	if data.onUpdate then
		local handle = E:ScheduleRepeatingTimer(function()
			data.onUpdate(panel, 1)
		end, 1)
		panel.elvUpdateTimer = handle
		pcall(data.onUpdate, panel, 20)
	end

	if data.onClick then
		panel:SetScript("OnClick", function()
			data.onClick(this)
		end)
	end

	if data.onEnter then
		panel:SetScript("OnEnter", function()
			data.onEnter(this)
		end)
	end

	if data.onLeave then
		panel:SetScript("OnLeave", function()
			data.onLeave(this)
		end)
	else
		panel:SetScript("OnLeave", function() DT:Data_OnLeave() end)
	end
end

function DT:LoadDataTexts()
	self.db = E.db.datatexts

	local panelName, panel
	for panelName, panel in pairs(DT.RegisteredPanels) do
		local i
		for i = 1, panel.numPoints do
			local pointIndex = DT.PointLocation[i]
			local dataPanel = panel.dataPanels[pointIndex]

			pcall(dataPanel.UnregisterAllEvents, dataPanel)
			if dataPanel.elvUpdateTimer then
				E:CancelTimer(dataPanel.elvUpdateTimer)
				dataPanel.elvUpdateTimer = nil
			end
			dataPanel:SetScript("OnUpdate", nil)
			dataPanel:SetScript("OnEnter", nil)
			dataPanel:SetScript("OnLeave", nil)
			dataPanel:SetScript("OnClick", nil)
			dataPanel:SetScript("OnEvent", nil)
			E:FontTemplate(dataPanel.text, LSM and LSM:Fetch("font", self.db.font), self.db.fontSize, self.db.fontOutline)
			dataPanel.text:SetText(nil)
			dataPanel.pointIndex = pointIndex

			local panelValue = self.db.panels[panelName]
			local widgetName
			if type(panelValue) == "table" then
				widgetName = panelValue[pointIndex]
			elseif type(panelValue) == "string" and pointIndex == "middle" then
				-- A numPoints=1 panel's assignment is a bare string
				-- (matches real ElvUI's own P["datatexts"]["panels"]
				-- ["LeftMiniPanel"]/["RightMiniPanel"] shape exactly --
				-- Settings/Profile.lua:598-599 -- NOT a
				-- {middle=...}-wrapped table) -- required for a real
				-- saved profile's value to actually be read correctly.
				widgetName = panelValue
			end

			local data = widgetName and widgetName ~= "" and DT.RegisteredDataTexts[widgetName]
			if data then
				DT:AssignPanelToDataText(dataPanel, data)
			end
		end
	end
end

function DT:RegisterDatatext(name, events, eventFunc, updateFunc, clickFunc, onEnterFunc, onLeaveFunc, localizedName)
	if not name then
		error("Cannot register datatext, no name was provided.")
	end

	DT.RegisteredDataTexts[name] = {
		name = name,
		events = events,
		eventFunc = eventFunc,
		onUpdate = type(updateFunc) == "function" and updateFunc or nil,
		onClick = type(clickFunc) == "function" and clickFunc or nil,
		onEnter = type(onEnterFunc) == "function" and onEnterFunc or nil,
		onLeave = type(onLeaveFunc) == "function" and onLeaveFunc or nil,
		localizedName = type(localizedName) == "string" and localizedName or nil,
	}
end

-- ===========================================================================
-- LibDataBroker-1.1 integration -- lets any addon exposing an LDB data
-- object be picked as a datatext widget, same as real ElvUI
-- (DataTexts.lua:53-110).
-- ===========================================================================
local hex = "|cffFFFFFF"

function DT:SetupObjectLDB(name, obj)
	local curFrame

	local function OnEnter()
		DT:SetupTooltip(this)
		if obj.OnTooltipShow then
			obj.OnTooltipShow(GameTooltip)
		end
		if obj.OnEnter then
			obj.OnEnter(this)
		end
		GameTooltip:Show()
	end

	local function OnLeave()
		if obj.OnLeave then
			obj.OnLeave(this)
		end
		GameTooltip:Hide()
	end

	local function OnClick(self, button)
		if obj.OnClick then
			obj.OnClick(self, button)
		end
	end

	local function textUpdate(_, updateName, _, value)
		if not curFrame then return end
		if value == nil or (string.len(tostring(value)) >= 3) or value == "n/a" or updateName == value then
			curFrame.text:SetText(value ~= "n/a" and value or updateName)
		else
			curFrame.text:SetText(string.format("%s: %s%s|r", updateName, hex, tostring(value)))
		end
	end

	local function OnEvent(self)
		curFrame = self
		LDB.RegisterCallback(DT, "LibDataBroker_AttributeChanged_"..name.."_text", textUpdate)
		LDB.RegisterCallback(DT, "LibDataBroker_AttributeChanged_"..name.."_value", textUpdate)
		-- LibDataBroker-1.1 (MINOR 5) and CallbackHandler-1.0 (MINOR 7) from
		-- dh-harald/Ace3v fire upstream-style, `Fire(eventname, ...)` with no
		-- argument count, so this is real ElvUI's call as it is. (The earlier
		-- vanilla CallbackHandler, MINOR 6, took an explicit count here.)
		LDB.callbacks:Fire("LibDataBroker_AttributeChanged_"..name.."_text", name, nil, obj.text, obj)
	end

	DT:RegisterDatatext(name, {"PLAYER_ENTERING_WORLD"}, OnEvent, nil, OnClick, OnEnter, OnLeave)

	if DT.hasEnteredWorld then
		E:Delay(0.5, function() DT:LoadDataTexts() end)
	end
end

function DT:RegisterLDB()
	if not LDB then return end
	local name, obj
	for name, obj in LDB:DataObjectIterator() do
		self:SetupObjectLDB(name, obj)
	end
end

function DT:PLAYER_ENTERING_WORLD()
	DT.hasEnteredWorld = true
	-- Panels registered at load may not be laid out yet (no edges, so
	-- PanelWidth falls back to GetWidth); by now they are.
	DT:UpdateAllDimensions()
	DT:LoadDataTexts()
end

function DT:Initialize()
	self.db = E.db.datatexts

	self:RegisterLDB()
	if LDB then
		LDB.RegisterCallback(DT, "LibDataBroker_DataObjectCreated", function(_, name, obj) DT:SetupObjectLDB(name, obj) end)
	end

	self:LoadDataTexts()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

E:RegisterInitialModule(DT:GetName(), function() DT:Initialize() end)
