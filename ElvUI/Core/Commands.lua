-- Slash commands: the config toggle, the mover mode and the install wizard.
-- "/elvui errors" opens the Lua error window instead of the config, and
-- "/elvui errors on|off" switches its automatic opening (Core/DebugTools.lua).

local E, L = ElvUI[1], ElvUI[2]

E:RegisterChatCommand("elvui", "ToggleConfig")
E:RegisterChatCommand("ec", "ToggleConfig")
E:RegisterChatCommand("moveui", "ToggleMoveMode") -- matches real ElvUI's own slash command name; see Core/Movers.lua
E:RegisterChatCommand("eiw", "ToggleInstallWizard") -- see Core/Install.lua

function E:ToggleConfig(input)
	if type(input) == "string" then
		local command = string.lower(input)
		command = string.gsub(command, "^%s+", "")
		command = string.gsub(command, "%s+$", "")
		command = string.gsub(command, "%s+", " ")
		if command == "errors" or command == "errors on" or command == "errors off" then
			if self.DebugTools then
				if command == "errors on" then
					self.DebugTools:SetAutoOpen(true)
				elseif command == "errors off" then
					self.DebugTools:SetAutoOpen(false)
				else
					self.DebugTools:ShowErrors()
				end
			end
			return
		end
	end

	if not IsAddOnLoaded("ElvUI_Config") then
		LoadAddOn("ElvUI_Config")
		if not IsAddOnLoaded("ElvUI_Config") then
			self:Print(L["|cffff0000Error -- Addon 'ElvUI_Config' not found or is disabled.|r"])
			return
		end
	end

	LibStub("LibConfig-1.0"):OpenToCategory("ElvUI")
end
