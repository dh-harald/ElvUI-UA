local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn

-- DataBars (Modules/DataBars/XPBar.lua) -- mirrors real ElvUI_Config/
-- DataBars.lua's own three distinct set-function targets for this group
-- (UpdateExperienceDimensions for size/orientation/font-ish fields,
-- UpdateExperience for fields UpdateExperience itself reads directly,
-- EnableDisable_ExperienceBar for the enable toggle specifically) --
-- LibConfig-1.0 has no group-level get/set inheritance (see the Cooldown
-- Text group's own note above), so each leaf below calls the matching
-- one of these three explicitly instead of relying on a shared default.
local function UpdateExperienceDimensions()
	if E.DataBars and E.DataBars.UpdateExperienceDimensions then
		E.DataBars:UpdateExperienceDimensions()
	end
end

local function UpdateExperience()
	if E.DataBars and E.DataBars.UpdateExperience then
		E.DataBars:UpdateExperience()
	end
end

local function EnableDisableExperienceBar()
	if E.DataBars and E.DataBars.EnableDisable_ExperienceBar then
		E.DataBars:EnableDisable_ExperienceBar()
	end
end

-- Reputation Bar (Modules/DataBars/ReputationBar.lua) --
-- same three set-function targets as the XP bar above, mirroring real
-- ElvUI_Config/DataBars.lua's own "reputation" group
-- (source/ElvUI-vanilla/ElvUI_Config/DataBars.lua:143-245).
local function UpdateReputationDimensions()
	if E.DataBars and E.DataBars.UpdateReputationDimensions then
		E.DataBars:UpdateReputationDimensions()
	end
end

local function UpdateReputation()
	if E.DataBars and E.DataBars.UpdateReputation then
		E.DataBars:UpdateReputation()
	end
end

local function EnableDisableReputationBar()
	if E.DataBars and E.DataBars.EnableDisable_ReputationBar then
		E.DataBars:EnableDisable_ReputationBar()
	end
end

-- DataBars: real ElvUI's own top-level category
-- (E.Options.args.databars, source/ElvUI-vanilla/ElvUI_Config/
-- DataBars.lua:12-17, childGroups="tab" with "experience"/
-- "reputation" tabs). Both tabs exist here --
-- "reputation" was added alongside Modules/DataBars/
-- ReputationBar.lua, which is what makes the Character panel's
-- "Show as Experience Bar" checkbox actually do something.
-- Field names/order numbers matched to real ElvUI_Config/
-- DataBars.lua's own groups exactly
-- (source/ElvUI-vanilla/ElvUI_Config/DataBars.lua:29-245).
E.Options.args.databars = {
	type = "group",
	name = L["DataBars"],
	order = 4,
	childGroups = "tab",
	args = {
		intro = {
			order = 1,
			type = "description",
			name = L["Experience and reputation bars."],
		},
		spacer = {
			order = 2,
			type = "description",
			name = L["\n"],
		},
		experience = {
			type = "group",
			name = L["XP Bar"],
			order = 1,
			args = {
				header = {
					type = "header",
					name = L["XP Bar"],
					order = 1,
				},
				enable = {
					type = "toggle",
					name = L["Enable"],
					order = 2,
					get = function() return E.db.databars.experience.enable end,
					set = function(_, value)
						E.db.databars.experience.enable = value
						EnableDisableExperienceBar()
					end,
				},
				mouseover = {
					type = "toggle",
					name = L["Mouseover"],
					order = 3,
					get = function() return E.db.databars.experience.mouseover end,
					set = function(_, value)
						E.db.databars.experience.mouseover = value
						UpdateExperienceDimensions()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				hideAtMaxLevel = {
					type = "toggle",
					name = L["Hide At Max Level"],
					order = 4,
					get = function() return E.db.databars.experience.hideAtMaxLevel end,
					set = function(_, value)
						E.db.databars.experience.hideAtMaxLevel = value
						UpdateExperience()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				hideInCombat = {
					type = "toggle",
					name = L["Hide in Combat"],
					order = 5,
					get = function() return E.db.databars.experience.hideInCombat end,
					set = function(_, value)
						E.db.databars.experience.hideInCombat = value
						UpdateExperience()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				orientation = {
					type = "select",
					name = L["Statusbar Fill Orientation"],
					desc = L["Direction the bar moves on gains/losses."],
					order = 7,
					values = {
						HORIZONTAL = L["Horizontal"],
						VERTICAL = L["Vertical"],
					},
					get = function() return E.db.databars.experience.orientation end,
					set = function(_, value)
						E.db.databars.experience.orientation = value
						UpdateExperienceDimensions()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				width = {
					type = "range",
					name = L["Width"],
					order = 8,
					min = 5,
					max = 800,
					step = 1,
					get = function() return E.db.databars.experience.width end,
					set = function(_, value)
						E.db.databars.experience.width = value
						UpdateExperienceDimensions()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				height = {
					type = "range",
					name = L["Height"],
					order = 9,
					min = 5,
					max = 200,
					step = 1,
					get = function() return E.db.databars.experience.height end,
					set = function(_, value)
						E.db.databars.experience.height = value
						UpdateExperienceDimensions()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				font = {
					type = "select",
					name = L["Font"],
					dialogControl = "LSM30_Font",
					order = 10,
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
					get = function() return E.db.databars.experience.font end,
					set = function(_, value)
						E.db.databars.experience.font = value
						UpdateExperienceDimensions()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				textSize = {
					type = "range",
					name = L["Font Size"],
					desc = L["Currently a no-op on UA (SetFont doesn't apply size there) -- kept for real 1.12.1 and in case UA fixes this."],
					order = 11,
					min = 6,
					max = 22,
					step = 1,
					get = function() return E.db.databars.experience.textSize end,
					set = function(_, value)
						E.db.databars.experience.textSize = value
						UpdateExperienceDimensions()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				fontOutline = {
					type = "select",
					name = L["Font Outline"],
					order = 12,
					values = {
						["NONE"] = L["None"],
						["OUTLINE"] = L["Outline"],
						["MONOCHROMEOUTLINE"] = L["Monochrome Outline"],
						["THICKOUTLINE"] = L["Thick Outline"],
					},
					get = function() return E.db.databars.experience.fontOutline end,
					set = function(_, value)
						E.db.databars.experience.fontOutline = value
						UpdateExperienceDimensions()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
				textFormat = {
					type = "select",
					name = L["Text Format"],
					order = 13,
					values = {
						NONE = L["None"],
						PERCENT = L["Percent"],
						CUR = L["Current"],
						REM = L["Remaining"],
						CURMAX = L["Current - Max"],
						CURPERC = L["Current - Percent"],
						CURREM = L["Current - Remaining"],
						CURPERCREM = L["Current - Percent (Remaining)"],
					},
					get = function() return E.db.databars.experience.textFormat end,
					set = function(_, value)
						E.db.databars.experience.textFormat = value
						UpdateExperience()
					end,
					disabled = function() return not E.db.databars.experience.enable end,
				},
			},
		},
		-- Reputation tab -- field names/order numbers matched to
		-- real ElvUI_Config/DataBars.lua's own "reputation" group
		-- (source/ElvUI-vanilla/ElvUI_Config/DataBars.lua:143-245).
		-- Identical to the XP tab above minus "Hide At Max Level"
		-- (no such field for reputation in the reference either).
		reputation = {
			type = "group",
			name = L["Reputation Bar"],
			order = 2,
			args = {
				header = {
					type = "header",
					name = L["Reputation Bar"],
					order = 1,
				},
				enable = {
					type = "toggle",
					name = L["Enable"],
					desc = L["Shows the faction picked with the Character panel's Reputation tab > \"Show as Experience Bar\" checkbox. With no watched faction the bar stays hidden regardless."],
					order = 2,
					get = function() return E.db.databars.reputation.enable end,
					set = function(_, value)
						E.db.databars.reputation.enable = value
						EnableDisableReputationBar()
					end,
				},
				mouseover = {
					type = "toggle",
					name = L["Mouseover"],
					order = 3,
					get = function() return E.db.databars.reputation.mouseover end,
					set = function(_, value)
						E.db.databars.reputation.mouseover = value
						UpdateReputationDimensions()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
				hideInCombat = {
					type = "toggle",
					name = L["Hide in Combat"],
					order = 4,
					get = function() return E.db.databars.reputation.hideInCombat end,
					set = function(_, value)
						E.db.databars.reputation.hideInCombat = value
						UpdateReputation()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
				orientation = {
					type = "select",
					name = L["Statusbar Fill Orientation"],
					desc = L["Direction the bar moves on gains/losses."],
					order = 6,
					values = {
						HORIZONTAL = L["Horizontal"],
						VERTICAL = L["Vertical"],
					},
					get = function() return E.db.databars.reputation.orientation end,
					set = function(_, value)
						E.db.databars.reputation.orientation = value
						UpdateReputationDimensions()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
				width = {
					type = "range",
					name = L["Width"],
					order = 7,
					min = 5,
					max = 800,
					step = 1,
					get = function() return E.db.databars.reputation.width end,
					set = function(_, value)
						E.db.databars.reputation.width = value
						UpdateReputationDimensions()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
				height = {
					type = "range",
					name = L["Height"],
					order = 8,
					min = 5,
					max = 200,
					step = 1,
					get = function() return E.db.databars.reputation.height end,
					set = function(_, value)
						E.db.databars.reputation.height = value
						UpdateReputationDimensions()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
				font = {
					type = "select",
					name = L["Font"],
					dialogControl = "LSM30_Font",
					order = 9,
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
					get = function() return E.db.databars.reputation.font end,
					set = function(_, value)
						E.db.databars.reputation.font = value
						UpdateReputationDimensions()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
				textSize = {
					type = "range",
					name = L["Font Size"],
					desc = L["Currently a no-op on UA (SetFont doesn't apply size there) -- kept for real 1.12.1 and in case UA fixes this."],
					order = 10,
					min = 6,
					max = 22,
					step = 1,
					get = function() return E.db.databars.reputation.textSize end,
					set = function(_, value)
						E.db.databars.reputation.textSize = value
						UpdateReputationDimensions()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
				fontOutline = {
					type = "select",
					name = L["Font Outline"],
					order = 11,
					values = {
						["NONE"] = L["None"],
						["OUTLINE"] = L["Outline"],
						["MONOCHROMEOUTLINE"] = L["Monochrome Outline"],
						["THICKOUTLINE"] = L["Thick Outline"],
					},
					get = function() return E.db.databars.reputation.fontOutline end,
					set = function(_, value)
						E.db.databars.reputation.fontOutline = value
						UpdateReputationDimensions()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
				textFormat = {
					type = "select",
					name = L["Text Format"],
					order = 12,
					values = {
						NONE = L["None"],
						PERCENT = L["Percent"],
						CUR = L["Current"],
						REM = L["Remaining"],
						CURMAX = L["Current - Max"],
						CURPERC = L["Current - Percent"],
						CURREM = L["Current - Remaining"],
						CURPERCREM = L["Current - Percent (Remaining)"],
					},
					get = function() return E.db.databars.reputation.textFormat end,
					set = function(_, value)
						E.db.databars.reputation.textFormat = value
						UpdateReputation()
					end,
					disabled = function() return not E.db.databars.reputation.enable end,
				},
			},
		},
	},
}
