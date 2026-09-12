local E, L, V, P, G = unpack(ElvUI)

--]]
E.Options.args.bags = {
	type = "group",
	name = L["Bags"],
	order = 1,
	args = {
		intro = {
			order = 1,
			type = "description",
			name = L["One merged window replacing the native bag windows. The native item and bag-slot buttons are reused rather than rebuilt, so they keep their own click, drag and tooltip behavior."],
		},
		enable = {
			order = 2,
			type = "toggle",
			name = L["Enable"],
			desc = L["Requires /reload to take effect."],
			get = function() return E.private.bags and E.private.bags.enable end,
			set = function(_, value)
				E.private.bags = E.private.bags or {}
				E.private.bags.enable = value
				E:RequestReload("private")
			end,
		},
		-- `general` and `sizeGroup`, matching real ElvUI: the money format
		-- belongs to the former and every size/width control to the latter.
		-- Ours used to have all five hanging directly off `bags`.
		general = {
			order = 3,
			type = "group",
			name = L["General"],
			args = {
				-- No manual header -- `general` has no childGroups/guiInline
				-- of its own, so LibConfig-1.0 renders it as its own sidebar
				-- TREE page (nested under "Bags") and auto-titles that page
				-- from this group's own `name`; a manual header repeating
				-- "General" here would duplicate it. See UnitFrames.lua's
				-- generalOptionsGroup for the fuller writeup of this
				-- LibConfig-1.0 rendering rule (tree/inline groups auto-
				-- title, tab children do not).
				--
				-- Order 2 is real ElvUI's `strata`, which this project doesn't
				-- expose; the number is left free.
				moneyFormat = {
					order = 3,
					type = "select",
					name = L["Money Format"],
					values = {
						SMART = "Smart",
						SHORT = "Short",
						SHORTINT = "Short (Whole Numbers)",
						CONDENSED = "Condensed",
						BLIZZARD = "Blizzard",
					},
					get = function() return E.db.bags.moneyFormat end,
					set = function(_, value)
						E.db.bags.moneyFormat = value
						if E.Bags then E.Bags:UpdateGoldText() end
					end,
				},
				-- Order 5, real ElvUI's own slot in this group (4 is its
				-- junkIcon, not implemented here, so the number stays free).
				-- Live with no extra plumbing: Modules/Bags/Bags.lua reads this
				-- inside the container's OnHide, so the next close obeys it.
				clearSearchOnClose = {
					order = 5,
					type = "toggle",
					name = L["Clear Search On Close"],
					desc = L["Reset the bag search box when the window closes, instead of keeping the filter for next time."],
					get = function() return E.db.bags.clearSearchOnClose end,
					set = function(_, value) E.db.bags.clearSearchOnClose = value end,
				},
			},
		},
		sizeGroup = {
			order = 4,
			type = "group",
			name = L["Size"],
			args = {
				header = {
					order = 0,
					type = "header",
					name = L["Size and Positions"],
				},
				bagSize = {
					order = 1,
					type = "range",
					name = L["Button Size (Bag)"],
					desc = L["The size of the individual buttons on the bag frame."],
					min = 20, max = 60, step = 1,
					get = function() return E.db.bags.bagSize end,
					set = function(_, value)
						E.db.bags.bagSize = value
						if E.Bags then E.Bags:Layout() end
					end,
				},
				bagWidth = {
					order = 2,
					type = "range",
					name = L["Panel Width (Bags)"],
					desc = L["Adjust the width of the bag frame. The number of columns follows from it and the slot size."],
					min = 150, max = 700, step = 1,
					get = function() return E.db.bags.bagWidth end,
					set = function(_, value)
						E.db.bags.bagWidth = value
						if E.Bags then E.Bags:Layout() end
					end,
				},
				-- Order 3 is real ElvUI's `split.bagSpacing`, not exposed here.
				bankSize = {
					order = 4,
					type = "range",
					name = L["Button Size (Bank)"],
					desc = L["The size of the individual buttons on the bank frame."],
					min = 20, max = 60, step = 1,
					get = function() return E.db.bags.bankSize end,
					set = function(_, value)
						E.db.bags.bankSize = value
						if E.Bags then E.Bags:Layout(true) end
					end,
				},
				bankWidth = {
					order = 5,
					type = "range",
					name = L["Panel Width (Bank)"],
					desc = L["Adjust the width of the bank frame. The number of columns follows from it and the slot size."],
					min = 150, max = 700, step = 1,
					get = function() return E.db.bags.bankWidth end,
					set = function(_, value)
						E.db.bags.bankWidth = value
						if E.Bags then E.Bags:Layout(true) end
					end,
				},
			},
		},
	},
}
