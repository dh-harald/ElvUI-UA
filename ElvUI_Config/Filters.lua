local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn

-- Editor for the aura lists named in `filters.priority` strings
-- (E.global.unitframe.aurafilters, read by ElvUI's
-- Modules/UnitFrames/AuraFilter.lua). Retail ElvUI's Filters page, keyed by
-- aura name instead of spell ID. The shipped lists and their shipped entries
-- cannot be deleted, only switched off: the saved global table is merged
-- over the defaults at every login, so a deleted default would come back.

local selectedFilter, selectedSpell

local function Lists()
	return E.global.unitframe.aurafilters
end

local function DefaultList(name)
	return G.unitframe and G.unitframe.aurafilters and G.unitframe.aurafilters[name]
end

local function SelectedList()
	return selectedFilter and Lists()[selectedFilter]
end

-- The delete buttons check these in their own func as well: a LibConfig-1.0
-- older than MINOR 9 draws a disabled `execute` as a live button.
local function RemovableFilter()
	return selectedFilter and Lists()[selectedFilter] and not DefaultList(selectedFilter)
end

local function RemovableSpell()
	local list = SelectedList()
	if not (list and selectedSpell and list.spells[selectedSpell]) then return false end
	local default = DefaultList(selectedFilter)
	return not (default and default.spells and default.spells[selectedSpell])
end

local function Trim(text)
	local _, _, inner = string.find(text or "", "^%s*(.-)%s*$")
	return inner or ""
end

local function Changed()
	local UF = E.UnitFrames
	if UF and UF.ClearAuraFilterCache then UF:ClearAuraFilterCache() end
	if E.NamePlates then E.NamePlates:ConfigureAll() end
end

local function SpellGroup()
	return {
		order = 20,
		type = "group",
		name = function() return selectedSpell or "" end,
		guiInline = true,
		hidden = function()
			local list = SelectedList()
			return not (list and selectedSpell and list.spells[selectedSpell])
		end,
		get = function(info) return SelectedList().spells[selectedSpell][ info[getn(info)] ] end,
		set = function(info, value)
			SelectedList().spells[selectedSpell][ info[getn(info)] ] = value
			Changed()
		end,
		args = {
			enable = { order = 1, type = "toggle", name = L["Enable"] },
			priority = {
				order = 2,
				type = "range",
				name = L["Priority"],
				min = 0, max = 99, step = 1,
			},
		},
	}
end

local function FilterGroup()
	return {
		order = 10,
		type = "group",
		name = function() return selectedFilter or "" end,
		guiInline = true,
		hidden = function() return not SelectedList() end,
		args = {
			filterType = {
				order = 1,
				type = "select",
				name = L["Filter Type"],
				values = { Whitelist = L["Whitelist"], Blacklist = L["Blacklist"] },
				get = function() return SelectedList().type end,
				set = function(_, value)
					SelectedList().type = value
					Changed()
				end,
			},
			addSpell = {
				order = 2,
				type = "input",
				name = L["Add Spell Name"],
				get = function() return "" end,
				set = function(_, value)
					local name = Trim(value)
					if name == "" then return end
					local spells = SelectedList().spells
					if not spells[name] then
						spells[name] = { enable = true, priority = 0, stackThreshold = 0 }
					end
					selectedSpell = name
					Changed()
				end,
			},
			selectSpell = {
				order = 3,
				type = "select",
				name = L["Select Spell"],
				values = function()
					local values = {}
					local name
					for name in pairs(SelectedList().spells) do values[name] = name end
					return values
				end,
				get = function() return selectedSpell end,
				set = function(_, value) selectedSpell = value end,
			},
			removeSpell = {
				order = 4,
				type = "execute",
				name = L["Remove Spell"],
				disabled = function() return not RemovableSpell() end,
				func = function()
					if not RemovableSpell() then return end
					SelectedList().spells[selectedSpell] = nil
					selectedSpell = nil
					Changed()
				end,
			},
			spell = SpellGroup(),
		},
	}
end

E.Options.args.filters = {
	order = 3,
	type = "group",
	name = L["Filters"],
	args = {
		createFilter = {
			order = 1,
			type = "input",
			name = L["Create Filter"],
			get = function() return "" end,
			set = function(_, value)
				local name = Trim(value)
				if name == "" then return end
				if Lists()[name] then
					E:Print(L["Filter already exists!"])
					return
				end
				Lists()[name] = { type = "Whitelist", spells = {} }
				selectedFilter, selectedSpell = name, nil
				Changed()
			end,
		},
		selectFilter = {
			order = 2,
			type = "select",
			name = L["Select Filter"],
			values = function()
				local values = {}
				local name
				for name in pairs(Lists()) do values[name] = name end
				return values
			end,
			get = function() return selectedFilter end,
			set = function(_, value) selectedFilter, selectedSpell = value, nil end,
		},
		deleteFilter = {
			order = 3,
			type = "execute",
			name = L["Delete Filter"],
			disabled = function() return not RemovableFilter() end,
			func = function()
				if not RemovableFilter() then return end
				Lists()[selectedFilter] = nil
				selectedFilter, selectedSpell = nil, nil
				Changed()
			end,
		},
		filter = FilterGroup(),
	},
}
