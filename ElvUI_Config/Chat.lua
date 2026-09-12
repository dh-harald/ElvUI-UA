local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn

E.Options.args.chat = {
	type = "group",
	name = L["Chat"],
	order = 6,
	childGroups = "tab",
	args = {
		intro = {
			type = "description",
			order = 1,
			name = L["Only the left/default chat window is docked and skinned -- the right panel exists (datatexts, mover, collapse icon all work) but nothing docks a second chat window into it. Message formatting (timestamps, URL links, keyword highlighting, spam throttle) applies project-wide, not just the docked window. Not implemented: chat history log/replay, hyperlink hover tooltips, channel-link click-to-switch -- see CLAUDE.md."],
		},
		enable = {
			type = "toggle",
			name = L["Enable"],
			desc = L["Requires /reload."],
			order = 2,
			get = function() return E.private.chat.enable end,
			set = function(_, value)
				E.private.chat.enable = value
				E:RequestReload("private")
			end,
		},
		general = {
			type = "group",
			name = L["General"],
			order = 3,
			args = {
				header = { type = "header", name = "General", order = 1 },
				url = {
					type = "toggle", name = "URL Links", order = 2,
					desc = L["Attempt to create clickable URL links inside the chat."],
					get = function() return E.db.chat.url end,
					set = function(_, value) E.db.chat.url = value end,
				},
				shortChannels = {
					type = "toggle", name = "Short Channels", order = 3,
					desc = L["Shorten the channel names in chat."],
					get = function() return E.db.chat.shortChannels end,
					set = function(_, value) E.db.chat.shortChannels = value end,
				},
				hyperlinkHover = {
					type = "toggle", name = "Hyperlink Hover", order = 4,
					desc = L["Not yet implemented on this project (no GameTooltip hook yet)."],
					get = function() return E.db.chat.hyperlinkHover end,
					set = function(_, value) E.db.chat.hyperlinkHover = value end,
				},
				sticky = {
					type = "toggle", name = "Sticky Chat", order = 5,
					desc = L["Keep the last channel you spoke in selected when opening the chat editbox. Disabled means it always defaults to Say."],
					get = function() return E.db.chat.sticky end,
					set = function(_, value) E.db.chat.sticky = value end,
				},
				fade = {
					type = "toggle", name = "Fade Chat", order = 6,
					desc = L["Fade the chat text when there is no activity."],
					get = function() return E.db.chat.fade end,
					set = function(_, value)
						E.db.chat.fade = value
						if E.Chat then E.Chat:UpdateFading() end
					end,
				},
				chatHistory = {
					type = "toggle", name = "Chat History", order = 7,
					desc = L["Not yet implemented on this project."],
					get = function() return E.db.chat.chatHistory end,
					set = function(_, value) E.db.chat.chatHistory = value end,
				},
				useAltKey = {
					type = "toggle", name = "Use Alt Key", order = 8,
					desc = L["Require holding the Alt key down to move the cursor or cycle through messages in the editbox."],
					get = function() return E.db.chat.useAltKey end,
					set = function(_, value)
						E.db.chat.useAltKey = value
						if E.Chat then E.Chat:UpdateSettings() end
					end,
				},
				spacer = { type = "description", name = " ", order = 9 },
				-- Moved up from the bottom of this list: a dropdown
				-- sitting at the bottom of a scrolled tab can show a
				-- tooltip on hover (so the button itself IS live)
				-- but never opened on click when it sat at the very
				-- end of a 15-item tab -- consistent with something
				-- about its position near the scrolled content's
				-- lower edge, not the field's own definition (every
				-- other select in this project uses the identical
				-- CreateDropdown call). If it works here but the
				-- range sliders below develop the same "can't
				-- interact" symptom now that THEY'RE at the bottom
				-- instead, that confirms a genuine LibConfig-1.0
				-- scroll-edge bug worth reporting/fixing upstream,
				-- not a fluke of this one field.
				timeStampFormat = {
					type = "select", name = "Chat Timestamps", order = 10,
					desc = L["Select the format of timestamps prefixed to chat messages."],
					values = {
						["NONE"] = L["None"],
						["%I:%M "] = "03:27",
						["%I:%M:%S "] = "03:27:32",
						["%I:%M %p "] = "03:27 PM",
						["%I:%M:%S %p "] = "03:27:32 PM",
						["%H:%M "] = "15:27",
						["%H:%M:%S "] = "15:27:32",
					},
					get = function() return E.db.chat.timeStampFormat end,
					set = function(_, value) E.db.chat.timeStampFormat = value end,
				},
				useCustomTimeColor = {
					type = "toggle", name = "Custom Timestamp Color", order = 11,
					desc = L["Use the custom color below for timestamps instead of plain white."],
					get = function() return E.db.chat.useCustomTimeColor end,
					set = function(_, value) E.db.chat.useCustomTimeColor = value end,
				},
				customTimeColor = {
					type = "color", name = "Timestamp Color", order = 12,
					hasAlpha = false,
					get = function()
						local c = E.db.chat.customTimeColor
						return c.r, c.g, c.b
					end,
					set = function(_, r, g, b)
						local c = E.db.chat.customTimeColor
						c.r, c.g, c.b = r, g, b
					end,
				},
				spacer2 = { type = "description", name = " ", order = 13 },
				throttleInterval = {
					type = "range", name = "Spam Interval", order = 14,
					desc = L["Prevent the same channel/yell message from displaying more than once within this many seconds. 0 disables."],
					min = 0, max = 120, step = 1,
					get = function() return E.db.chat.throttleInterval end,
					set = function(_, value)
						E.db.chat.throttleInterval = value
						if value == 0 and E.Chat then E.Chat:DisableChatThrottle() end
					end,
				},
				scrollDownInterval = {
					type = "range", name = "Scroll Interval", order = 15,
					desc = L["Not yet implemented on this project (auto-scroll-to-bottom after being scrolled up)."],
					min = 0, max = 120, step = 5,
					get = function() return E.db.chat.scrollDownInterval end,
					set = function(_, value) E.db.chat.scrollDownInterval = value end,
				},
				numAllowedCombatRepeat = {
					type = "range", name = "Allowed Combat Repeat", order = 16,
					desc = L["Number of repeated characters allowed in the chat editbox while in combat before it's automatically closed."],
					min = 2, max = 10, step = 1,
					get = function() return E.db.chat.numAllowedCombatRepeat end,
					set = function(_, value) E.db.chat.numAllowedCombatRepeat = value end,
				},
				numScrollMessages = {
					type = "range", name = "Scroll Messages", order = 17,
					desc = L["Number of lines to scroll per mouse wheel step."],
					min = 1, max = 10, step = 1,
					get = function() return E.db.chat.numScrollMessages end,
					set = function(_, value) E.db.chat.numScrollMessages = value end,
				},
			},
		},
		alerts = {
			type = "group",
			name = L["Alerts"],
			order = 4,
			args = {
				header = { type = "header", name = "Alerts", order = 1 },
				whisperSound = {
					type = "select", name = "Whisper Alert", order = 2,
					desc = L["Sound to play on an incoming whisper. Only \"None\" is selectable until custom sounds are registered with LibSharedMedia-3.0."],
					values = function()
						local LSM = LibStub("LibSharedMedia-3.0", true)
						local list = { ["None"] = "None" }
						if LSM then
							local names = LSM:List("sound")
							if names then
								local i
								for i = 1, table.getn(names) do
									list[names[i]] = names[i]
								end
							end
						end
						return list
					end,
					get = function() return E.db.chat.whisperSound end,
					set = function(_, value) E.db.chat.whisperSound = value end,
				},
				keywordSound = {
					type = "select", name = "Keyword Alert", order = 3,
					desc = L["Sound to play when a keyword below is spoken in chat. Only \"None\" is selectable until custom sounds are registered with LibSharedMedia-3.0."],
					values = function()
						local LSM = LibStub("LibSharedMedia-3.0", true)
						local list = { ["None"] = "None" }
						if LSM then
							local names = LSM:List("sound")
							if names then
								local i
								for i = 1, table.getn(names) do
									list[names[i]] = names[i]
								end
							end
						end
						return list
					end,
					get = function() return E.db.chat.keywordSound end,
					set = function(_, value) E.db.chat.keywordSound = value end,
				},
				noAlertInCombat = {
					type = "toggle", name = "No Alert In Combat", order = 4,
					desc = L["Don't play whisper/keyword alert sounds while in combat."],
					get = function() return E.db.chat.noAlertInCombat end,
					set = function(_, value) E.db.chat.noAlertInCombat = value end,
				},
				keywords = {
					type = "input", name = "Keywords", order = 5,
					desc = L["Comma-separated list of words to highlight in chat. Use %MYNAME% for your own character name.\n\nExample:\n%MYNAME%, ElvUI"],
					width = "full",
					get = function() return E.db.chat.keywords end,
					set = function(_, value)
						E.db.chat.keywords = value
						if E.Chat then E.Chat:UpdateChatKeywords() end
					end,
				},
			},
		},
		panels = {
			type = "group",
			name = L["Panels"],
			order = 5,
			args = {
				header = { type = "header", name = "Panels", order = 1 },
				lockPositions = {
					type = "toggle", name = "Lock Positions", order = 2,
					desc = L["Keep the left chat frame docked inside its panel."],
					get = function() return E.db.chat.lockPositions end,
					set = function(_, value)
						E.db.chat.lockPositions = value
						if value and E.Chat then E.Chat:PositionChat() end
					end,
				},
				-- The chat PANEL controls drive the Layout module, not Chat
				-- directly -- real ElvUI's own setter targets for these three
				-- (its ElvUI_Config/Chat.lua:270-306). Layout currently
				-- delegates straight back to Chat's CH:Update* functions,
				-- but the call site is the one upstream has, so it survives
				-- the panel code eventually moving into Layout.
				panelTabTransparency = {
					type = "toggle", name = "Tab Panel Transparency", order = 3,
					get = function() return E.db.chat.panelTabTransparency end,
					set = function(_, value)
						E.db.chat.panelTabTransparency = value
						E:GetModule("Layout"):SetChatTabStyle()
					end,
				},
				panelTabBackdrop = {
					type = "toggle", name = "Tab Panel", order = 4,
					desc = L["Toggle the chat tab panel backdrop."],
					get = function() return E.db.chat.panelTabBackdrop end,
					set = function(_, value)
						E.db.chat.panelTabBackdrop = value
						E:GetModule("Layout"):ToggleChatPanels()
					end,
				},
				editBoxPosition = {
					type = "select", name = "Chat EditBox Position", order = 5,
					values = {
						["BELOW_CHAT"] = L["Below Chat"],
						["ABOVE_CHAT"] = L["Above Chat"],
					},
					get = function() return E.db.chat.editBoxPosition end,
					set = function(_, value)
						E.db.chat.editBoxPosition = value
						if E.Chat then E.Chat:UpdateAnchors() end
					end,
				},
				panelBackdrop = {
					type = "select", name = "Panel Backdrop", order = 6,
					desc = L["Toggle showing of the left and right chat panel backdrops."],
					values = {
						["HIDEBOTH"] = L["Hide Both"],
						["SHOWBOTH"] = L["Show Both"],
						["LEFT"] = L["Left Only"],
						["RIGHT"] = L["Right Only"],
					},
					get = function() return E.db.chat.panelBackdrop end,
					set = function(_, value)
						E.db.chat.panelBackdrop = value
						E:GetModule("Layout"):ToggleChatPanels()
						if E.Chat then
							E.Chat:PositionChat()
							E.Chat:UpdateAnchors()
						end
					end,
				},
				separateSizes = {
					type = "toggle", name = "Separate Panel Sizes", order = 7,
					desc = L["Enable the use of separate size options for the right chat panel."],
					get = function() return E.db.chat.separateSizes end,
					set = function(_, value)
						E.db.chat.separateSizes = value
						if E.Chat then E.Chat:UpdatePanelSizes() end
					end,
				},
				spacer1 = { type = "description", name = " ", order = 8 },
				panelHeight = {
					type = "range", name = "Panel Height", order = 9,
					min = 50, max = 600, step = 1,
					get = function() return E.db.chat.panelHeight end,
					set = function(_, value)
						E.db.chat.panelHeight = value
						if E.Chat then E.Chat:UpdatePanelSizes() end
					end,
				},
				panelWidth = {
					type = "range", name = "Panel Width", order = 10,
					min = 50, max = 1000, step = 1,
					get = function() return E.db.chat.panelWidth end,
					set = function(_, value)
						E.db.chat.panelWidth = value
						if E.Chat then E.Chat:UpdatePanelSizes() end
					end,
				},
				panelColor = {
					type = "color", name = "Backdrop Color", order = 11,
					hasAlpha = true,
					get = function()
						local c = E.db.chat.panelColor
						return c.r, c.g, c.b, c.a
					end,
					set = function(_, r, g, b, a)
						local c = E.db.chat.panelColor
						c.r, c.g, c.b, c.a = r, g, b, a
						if E.Chat then E.Chat:UpdatePanelBackdrop() end
					end,
				},
				spacer2 = { type = "description", name = " ", order = 12 },
				panelHeightRight = {
					type = "range", name = "Right Panel Height", order = 13,
					min = 50, max = 600, step = 1,
					disabled = function() return not E.db.chat.separateSizes end,
					get = function() return E.db.chat.panelHeightRight end,
					set = function(_, value)
						E.db.chat.panelHeightRight = value
						if E.Chat then E.Chat:UpdatePanelSizes() end
					end,
				},
				panelWidthRight = {
					type = "range", name = "Right Panel Width", order = 14,
					min = 50, max = 1000, step = 1,
					disabled = function() return not E.db.chat.separateSizes end,
					get = function() return E.db.chat.panelWidthRight end,
					set = function(_, value)
						E.db.chat.panelWidthRight = value
						if E.Chat then E.Chat:UpdatePanelSizes() end
					end,
				},
				panelBackdropNameLeft = {
					type = "input", name = "Panel Texture (Left)", order = 15,
					width = "full",
					get = function() return E.db.chat.panelBackdropNameLeft end,
					set = function(_, value)
						E.db.chat.panelBackdropNameLeft = value
						if E.Chat then E.Chat:UpdatePanelTexture("Left") end
					end,
				},
				panelBackdropNameRight = {
					type = "input", name = "Panel Texture (Right)", order = 16,
					width = "full",
					get = function() return E.db.chat.panelBackdropNameRight end,
					set = function(_, value)
						E.db.chat.panelBackdropNameRight = value
						if E.Chat then E.Chat:UpdatePanelTexture("Right") end
					end,
				},
			},
		},
		fontGroup = {
			type = "group",
			name = L["Fonts"],
			order = 6,
			args = {
				header = { type = "header", name = "Fonts", order = 1 },
				font = {
					type = "select", name = "Font", dialogControl = "LSM30_Font", order = 2,
					values = function()
						local LSM = LibStub("LibSharedMedia-3.0", true)
						local list = {}
						if LSM then
							local names = LSM:List("font")
							local i
							for i = 1, table.getn(names) do
								list[names[i]] = names[i]
							end
						end
						return list
					end,
					get = function() return E.db.chat.font end,
					set = function(_, value)
						E.db.chat.font = value
						if E.Chat then E.Chat:ApplyFont(ChatFrame1) end
					end,
				},
				fontOutline = {
					type = "select", name = "Font Outline", order = 3,
					values = {
						["NONE"] = L["None"],
						["OUTLINE"] = L["Outline"],
						["MONOCHROMEOUTLINE"] = L["Monochrome Outline"],
						["THICKOUTLINE"] = L["Thick Outline"],
					},
					get = function() return E.db.chat.fontOutline end,
					set = function(_, value)
						E.db.chat.fontOutline = value
						if E.Chat then E.Chat:ApplyFont(ChatFrame1) end
					end,
				},
				spacer = { type = "description", name = " ", order = 4 },
				tabFont = {
					type = "select", name = "Tab Font", dialogControl = "LSM30_Font", order = 5,
					values = function()
						local LSM = LibStub("LibSharedMedia-3.0", true)
						local list = {}
						if LSM then
							local names = LSM:List("font")
							local i
							for i = 1, table.getn(names) do
								list[names[i]] = names[i]
							end
						end
						return list
					end,
					get = function() return E.db.chat.tabFont end,
					set = function(_, value)
						E.db.chat.tabFont = value
						if E.Chat then E.Chat:ApplyFont(ChatFrame1) end
					end,
				},
				tabFontSize = {
					type = "range", name = "Tab Font Size", order = 6,
					min = 6, max = 22, step = 1,
					get = function() return E.db.chat.tabFontSize end,
					set = function(_, value)
						E.db.chat.tabFontSize = value
						if E.Chat then E.Chat:ApplyFont(ChatFrame1) end
					end,
				},
				tabFontOutline = {
					type = "select", name = "Tab Font Outline", order = 7,
					values = {
						["NONE"] = L["None"],
						["OUTLINE"] = L["Outline"],
						["MONOCHROMEOUTLINE"] = L["Monochrome Outline"],
						["THICKOUTLINE"] = L["Thick Outline"],
					},
					get = function() return E.db.chat.tabFontOutline end,
					set = function(_, value)
						E.db.chat.tabFontOutline = value
						if E.Chat then E.Chat:ApplyFont(ChatFrame1) end
					end,
				},
			},
		},
	},
}
