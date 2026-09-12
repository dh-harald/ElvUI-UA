-- Adds an "ElvUI" row to the native Escape/System menu (GameMenuFrame) that
-- opens our config window, mirroring real ElvUI's Init.lua behavior.
--
-- The CreateFrame(template) call and the frame-height arithmetic are
-- pcall-wrapped: on UA, GetChildren() can come back empty, Button:Click()
-- is broken, and template-backed CreateFrame calls aren't guaranteed to
-- succeed (UnrealUI's own gamemenu.lua documents the same quirks around
-- this frame) -- so frame construction here is treated as something that
-- might fail rather than something that definitely won't. Uses
-- AceHook-3.0's :HookScript (already vendored) instead of a bare global
-- HookScript, which isn't reliably present/working on UA.
--
-- IMPORTANT: never derive the anchor from a *live* GetPoint() query on
-- repeat OnShow calls. On this client a stored frame reference and a
-- freshly-queried reference to "the same" frame can compare unequal
-- (UnrealUI's gamemenu.lua hits the identical issue with GetChildren()
-- returning rows that don't `==` the stored ones), so a check like
-- `relTo ~= button` against a fresh GetPoint() can keep re-triggering even
-- once Logout is already anchored to our button, re-anchoring it relative
-- to what has effectively become itself and compounding a few pixels
-- further down on every menu toggle. Fix: capture the ORIGINAL anchor
-- exactly once into a local upvalue (never touched again), and always
-- reposition from that fixed, captured value -- never from a fresh query.

local E = ElvUI[1]

local button
local originalRelTo
local heightGrown = false

local function CreateGameMenuButton(frame, logout)
	-- Named rather than anonymous. Not required for skinning -- the Skins
	-- sweep recognises this row by its template's art and colours its
	-- label through `Button:GetFontString()` either way -- but a name is
	-- what makes the row measurable when something goes wrong
	-- (`S:DumpButton("ElvUIGameMenuButton")`), matching how UnrealUI keeps
	-- its own menu rows identifiable.
	local ok, created = pcall(CreateFrame, "Button", "ElvUIGameMenuButton", frame, "GameMenuButtonTemplate")
	if not ok or not created then
		return nil
	end

	pcall(created.SetWidth, created, logout:GetWidth())
	pcall(created.SetHeight, created, logout:GetHeight())
	pcall(created.SetText, created, "ElvUI")

	created:SetScript("OnClick", function()
		E:ToggleConfig()
		pcall(HideUIPanel, frame)
	end)

	return created
end

-- Created ONCE at file-load time, deliberately not lazily inside the
-- OnShow handler: the Skins module's own first pass over `GameMenuFrame`
-- (`Modules/Skins/Blizzard/MainMenu.lua`, at PLAYER_LOGIN and again from
-- its OnShow hook) can already have run by the first Escape press, so a
-- button built inside OnShow would be the one row the auto-skin sweep
-- can't see. Nothing about hook ORDER is worth relying on here: creating
-- the button at file-load time means it simply exists before any skin
-- pass, in every ordering.
local function EnsureGameMenuButton(frame, logout)
	if button then return button end
	button = CreateGameMenuButton(frame, logout)
	return button
end

local function LayoutGameMenu()
	local frame = _G.GameMenuFrame
	local logout = _G.GameMenuButtonLogout
	if not frame or not logout then
		return
	end

	if not EnsureGameMenuButton(frame, logout) then
		return
	end

	if not originalRelTo then
		local okPoint, _, relTo = pcall(logout.GetPoint, logout)
		if okPoint then
			originalRelTo = relTo
		end
	end

	if not heightGrown then
		local okHeight, height = pcall(frame.GetHeight, frame)
		local okLogoutHeight, logoutHeight = pcall(logout.GetHeight, logout)
		if okHeight and okLogoutHeight then
			pcall(frame.SetHeight, frame, height + logoutHeight + 17)
		end
		heightGrown = true
	end

	if not originalRelTo then
		return
	end

	-- Re-applied every OnShow (not just once, in case native menu code
	-- resets anchors on its own), but always from the fixed captured
	-- anchor and fixed literal offsets -- see the note at the top of this
	-- file for why a fresh GetPoint() query here caused a drift bug.
	button:ClearAllPoints()
	pcall(button.SetPoint, button, "TOPLEFT", originalRelTo, "BOTTOMLEFT", 0, -1)

	logout:ClearAllPoints()
	pcall(logout.SetPoint, logout, "TOPLEFT", button, "BOTTOMLEFT", 0, -16)
end

if _G.GameMenuFrame then
	-- Build the row now (see EnsureGameMenuButton) -- positioning still
	-- happens in the OnShow handler, which is where the native menu's own
	-- anchors are known to be settled. GameMenuFrame is core FrameXML, so
	-- both it and `GameMenuButtonLogout` exist by the time any addon file
	-- runs; the nil-guard is only there as defense against a missing
	-- FrameXML global.
	if _G.GameMenuButtonLogout then
		EnsureGameMenuButton(_G.GameMenuFrame, _G.GameMenuButtonLogout)
	end
	E:HookScript(_G.GameMenuFrame, "OnShow", LayoutGameMenu)
end
