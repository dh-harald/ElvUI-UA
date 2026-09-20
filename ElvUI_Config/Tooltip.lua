local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local getn = ElvUI.Compat.getn

-- Real ElvUI's `tooltip` options group (ElvUI_Config/Tooltip.lua): same keys,
-- same tree paths, same orders. Only controls whose profile field the Tooltip
-- module actually reads are exposed; real ElvUI's itemLevel and inspectInfo
-- are left out until the module reads them.

-- GlobalStrings entries, English fallback where the client lacks them.
local FALLBACK_STANDING_LABELS = {
	"Hated", "Hostile", "Unfriendly", "Neutral",
	"Friendly", "Honored", "Revered", "Exalted",
}

local OUTLINE_VALUES = {
	["NONE"] = L["None"],
	["OUTLINE"] = L["Outline"],
	["MONOCHROMEOUTLINE"] = L["Monochrome Outline"],
	["THICKOUTLINE"] = L["Thick Outline"],
}

local function FontValues()
	local LSM = LibStub("LibSharedMedia-3.0", true)
	local list = {}
	if LSM then
		local names = LSM:List("font")
		local i
		for i = 1, getn(names) do
			list[names[i]] = names[i]
		end
	end
	return list
end

local VISIBILITY_VALUES = {
	["ALL"] = L["Always Hide"],
	["NONE"] = L["Never Hide"],
	["SHIFT"] = L["Shift Key"],
	["ALT"] = L["ALT-Key"],
	["CTRL"] = L["CTRL-Key"],
}

local VISIBILITY_DESC = L["Choose when you want the tooltip to show. If a modifer is chosen, then you need to hold that down to show the tooltip."]

local function TooltipDisabled()
	return not E.Tooltip
end

local function ApplyHealthBar()
	if E.Tooltip then
		E.Tooltip:ApplyHealthBarSettings()
	end
end

local function FactionColorArgs(id)
	return {
		order = id,
		type = "color",
		name = _G["FACTION_STANDING_LABEL" .. id] or FALLBACK_STANDING_LABELS[id],
		get = function()
			local c = E.db.tooltip.factionColors[id]
			return c.r, c.g, c.b
		end,
		set = function(_, r, g, b)
			local c = E.db.tooltip.factionColors[id]
			c.r, c.g, c.b = r, g, b
		end,
		disabled = function()
			return TooltipDisabled() or not E.db.tooltip.useCustomFactionColors
		end,
	}
end

local factionColorArgs = {
	useCustomFactionColors = {
		order = 0,
		type = "toggle",
		name = L["Custom Faction Colors"],
		get = function() return E.db.tooltip.useCustomFactionColors end,
		set = function(_, value) E.db.tooltip.useCustomFactionColors = value end,
	},
}
local i
for i = 1, 8 do
	factionColorArgs["" .. i] = FactionColorArgs(i)
end

E.Options.args.tooltip = {
	type = "group",
	name = L["Tooltip"],
	order = 1,
	childGroups = "tab",
	get = function(info) return E.db.tooltip[ info[getn(info)] ] end,
	set = function(info, value) E.db.tooltip[ info[getn(info)] ] = value end,
	args = {
		intro = {
			order = 1,
			type = "description",
			name = L["Setup options for the Tooltip."],
		},
		enable = {
			order = 2,
			type = "toggle",
			name = L["Enable"],
			desc = L["Requires /reload to take effect."],
			get = function() return E.private.tooltip and E.private.tooltip.enable end,
			set = function(_, value)
				E.private.tooltip = E.private.tooltip or {}
				E.private.tooltip.enable = value
				E:RequestReload("private")
			end,
		},
		general = {
			order = 3,
			type = "group",
			name = L["General"],
			disabled = TooltipDisabled,
			args = {
				header = {
					order = 1,
					type = "header",
					name = L["General"],
				},
				cursorAnchor = {
					order = 2,
					type = "toggle",
					name = L["Cursor Anchor"],
					desc = L["Should tooltip be anchored to mouse cursor"],
				},
				targetInfo = {
					order = 3,
					type = "toggle",
					name = L["Target Info"],
					desc = L["When in a raid group display if anyone in your raid is targeting the current tooltip unit."],
				},
				playerTitles = {
					order = 4,
					type = "toggle",
					name = L["Player Titles"],
					desc = L["Display player titles."],
				},
				guildRanks = {
					order = 5,
					type = "toggle",
					name = L["Guild Ranks"],
					desc = L["Display guild ranks if a unit is guilded."],
				},
				itemPrice = {
					order = 7,
					type = "toggle",
					name = L["Item Price"],
					desc = L["Display vendor sell value on item tooltips."],
				},
				spellID = {
					order = 8,
					type = "toggle",
					name = L["Spell/Item IDs"],
					desc = L["Display the spell or item ID when mousing over a spell or item tooltip."],
				},
				itemCount = {
					order = 11,
					type = "select",
					name = L["Item Count"],
					desc = L["Display how many of a certain item you have in your possession."],
					values = {
						["BAGS_ONLY"] = L["Bags Only"],
						["BANK_ONLY"] = L["Bank Only"],
						["BOTH"] = L["Both"],
						["NONE"] = L["None"],
					},
				},
				colorAlpha = {
					order = 12,
					type = "range",
					name = L["Opacity"],
					min = 0,
					max = 1,
					step = 0.01,
				},
				-- Real ElvUI's own inline group, keys and orders. Inherits the
				-- tab's `disabled` and the top-level get; its set re-applies
				-- the fonts live.
				fontGroup = {
					order = 13,
					type = "group",
					name = L["Tooltip Font Settings"],
					guiInline = true,
					set = function(info, value)
						E.db.tooltip[ info[getn(info)] ] = value
						if E.Tooltip then E.Tooltip:SetTooltipFonts() end
					end,
					args = {
						font = {
							order = 1,
							type = "select",
							dialogControl = "LSM30_Font",
							name = L["Font"],
							values = FontValues,
						},
						fontOutline = {
							order = 2,
							type = "select",
							name = L["Font Outline"],
							values = OUTLINE_VALUES,
						},
						spacer = {
							order = 3,
							type = "description",
							name = "",
						},
						headerFontSize = {
							order = 4,
							type = "range",
							name = L["Header Font Size"],
							min = 4,
							max = 33,
							step = 1,
						},
						textFontSize = {
							order = 5,
							type = "range",
							name = L["Text Font Size"],
							min = 4,
							max = 33,
							step = 1,
						},
						smallTextFontSize = {
							order = 6,
							type = "range",
							name = L["Comparison Font Size"],
							desc = L["This setting controls the size of text in item comparison tooltips."],
							min = 4,
							max = 33,
							step = 1,
						},
					},
				},
				factionColors = {
					order = 13,
					type = "group",
					name = L["Custom Faction Colors"],
					guiInline = true,
					args = factionColorArgs,
				},
			},
		},
		visibility = {
			order = 4,
			type = "group",
			name = L["Visibility"],
			get = function(info) return E.db.tooltip.visibility[ info[getn(info)] ] end,
			set = function(info, value) E.db.tooltip.visibility[ info[getn(info)] ] = value end,
			disabled = TooltipDisabled,
			args = {
				header = {
					order = 1,
					type = "header",
					name = L["Visibility"],
				},
				actionbars = {
					order = 2,
					type = "select",
					name = L["ActionBars"],
					desc = VISIBILITY_DESC,
					values = VISIBILITY_VALUES,
				},
				bags = {
					order = 3,
					type = "select",
					name = L["Bags/Bank"],
					desc = VISIBILITY_DESC,
					values = VISIBILITY_VALUES,
				},
				unitFrames = {
					order = 4,
					type = "select",
					name = L["UnitFrames"],
					desc = VISIBILITY_DESC,
					values = VISIBILITY_VALUES,
				},
				combat = {
					order = 5,
					type = "toggle",
					name = L["Combat"],
					desc = L["Hide tooltip while in combat."],
				},
			},
		},
		healthBar = {
			order = 5,
			type = "group",
			name = L["Health Bar"],
			get = function(info) return E.db.tooltip.healthBar[ info[getn(info)] ] end,
			set = function(info, value)
				E.db.tooltip.healthBar[ info[getn(info)] ] = value
				ApplyHealthBar()
			end,
			disabled = TooltipDisabled,
			args = {
				header = {
					order = 1,
					type = "header",
					name = L["Health Bar"],
				},
				height = {
					order = 2,
					type = "range",
					name = L["Height"],
					min = 1,
					max = 15,
					step = 1,
				},
				statusPosition = {
					order = 3,
					type = "select",
					name = L["Position"],
					values = {
						["BOTTOM"] = L["Bottom"],
						["TOP"] = L["Top"],
					},
				},
				text = {
					order = 4,
					type = "toggle",
					name = L["Text"],
				},
				font = {
					order = 5,
					type = "select",
					name = L["Font"],
					values = FontValues,
					disabled = function() return TooltipDisabled() or not E.db.tooltip.healthBar.text end,
				},
				fontSize = {
					order = 6,
					type = "range",
					name = L["Font Size"],
					min = 4,
					max = 33,
					step = 1,
					disabled = function() return TooltipDisabled() or not E.db.tooltip.healthBar.text end,
				},
				fontOutline = {
					order = 7,
					type = "select",
					name = L["Font Outline"],
					values = OUTLINE_VALUES,
					disabled = function() return TooltipDisabled() or not E.db.tooltip.healthBar.text end,
				},
			},
		},
	},
}
