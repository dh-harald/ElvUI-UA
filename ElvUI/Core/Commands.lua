-- Slash commands. Currently just the config toggle.

local E, L = ElvUI[1], ElvUI[2]

E:RegisterChatCommand("elvui", "ToggleConfig")
E:RegisterChatCommand("ec", "ToggleConfig")
E:RegisterChatCommand("moveui", "ToggleMoveMode") -- matches real ElvUI's own slash command name; see Core/Movers.lua
E:RegisterChatCommand("eiw", "ToggleInstallWizard") -- see Core/Install.lua

function E:ToggleConfig()
	if not IsAddOnLoaded("ElvUI_Config") then
		LoadAddOn("ElvUI_Config")
		if not IsAddOnLoaded("ElvUI_Config") then
			self:Print(L["|cffff0000Error -- Addon 'ElvUI_Config' not found or is disabled.|r"])
			return
		end
	end

	LibStub("LibConfig-1.0"):OpenToCategory("ElvUI")
end
