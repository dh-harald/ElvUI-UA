local E, L, V, P, G = unpack(ElvUI)
local getn = ElvUI.Compat.getn

-- Every LSM-registered statusbar texture, as a `values` table. A FUNCTION, not a
-- literal: LibSharedMedia is populated by Media/SharedMedia.lua at load time and
-- other addons may register more later, so the list is built per render.
-- Real ElvUI uses `AceGUIWidgetLSMlists.statusbar` here, which AceGUI owns; this
-- is the same list without depending on AceGUI.
local function STATUSBAR_VALUES()
	local LSM = LibStub("LibSharedMedia-3.0", true)
	local list = {}
	if LSM then
		local names = LSM:List("statusbar")
		local i
		for i = 1, table.getn(names) do
			list[names[i]] = names[i]
		end
	end
	return list
end

-- Top-level "General" category (real ElvUI: E.Options.args.general,
-- source/ElvUI-vanilla/ElvUI_Config/General.lua:24-29, order=1,
-- childGroups="tab" with many tabs -- general/colors/skins/chatBubbles/
-- cooldown/etc.). Only "Cooldown Text" exists here so far -- the rest of
-- that real tab set needs infrastructure (skins module, a colors system)
-- this project doesn't have yet, so they're not stubbed in. A single
-- real (non-inline) child group renders as its own indented sidebar row
-- under "General" via LibConfig-1.0's default "tree" nesting -- no
-- childGroups="tab" override needed for just one child (unlike Map/
-- ActionBars' own multi-child groups).
--
-- Cooldown Text fields/defaults matched to real ElvUI's own group
-- exactly (source/ElvUI-vanilla/ElvUI_Config/General.lua:589-659) --
-- `enable` (private, reload-required), `threshold` (range -1..20,
-- -1 = "never turn red"), and 5 `type = "color"` leaves (expiring/
-- seconds/minutes/hours/days) -- the first real exercise of
-- LibConfig-1.0's color widget (source/LibConfig-1.0/LibConfig-1.0.lua).
-- Real ElvUI wires these 5
-- colors via a GROUP-level get/set that each color leaf inherits
-- (AceConfig's handler-fallback mechanism) -- LibConfig-1.0's RenderLeaf
-- resolves get/set directly off the LEAF option table, with no such
-- fallback (nothing else in this project's config relies on it either),
-- so each color leaf gets its own explicit get/set below instead. This
-- is purely an internal options-table wiring difference -- the SAVED
-- field names/shapes (E.db.cooldown.expiringColor = {r,g,b}, etc.) are
-- identical to real ElvUI either way.
local function CooldownColorArgs(key, order, label, desc)
	return {
		type = "color",
		name = label,
		desc = desc,
		order = order,
		get = function()
			local c = E.db.cooldown[key]
			return c.r, c.g, c.b
		end,
		set = function(_, r, g, b)
			local c = E.db.cooldown[key]
			c.r, c.g, c.b = r, g, b
		end,
	}
end

E.Options.args.general = {
	type = "group",
	name = L["General"],
	order = 1,
	childGroups = "tab",
	-- Group-level get/set, as in real ElvUI: a leaf without its own pair
	-- reads and writes `E.db.general[<its own key>]`.
	get = function(info) return E.db.general[ info[getn(info)] ] end,
	set = function(info, value) E.db.general[ info[getn(info)] ] = value end,
	args = {
		intro = {
			order = 1,
			type = "description",
			name = L["Core settings shared across the whole UI."],
		},
		-- Real ElvUI keeps a `general` group INSIDE `general`, and the loot
		-- toggles live there -- ours used to have its own `loot` group, which
		-- put both controls at a tree path the original doesn't have. Orders
		-- are real ElvUI's own, so each control sits in the same place among
		-- the settings we haven't implemented yet.
		-- No manual header -- this tab's own name ("General") already
		-- duplicates the ROOT category's own name (`E.Options.args.general`
		-- above, also "General"), which LibConfig-1.0's RenderContent
		-- auto-titles at the top of this whole page regardless of which
		-- tab is selected; a matching manual header here repeated it a
		-- second time as soon as this tab was opened. See
		-- UnitFrames.lua's generalOptionsGroup for the fuller writeup.
		general = {
			order = 2,
			type = "group",
			name = L["General"],
			args = {
				autoRoll = {
					order = 7,
					type = "toggle",
					name = L["Auto Greed"],
					desc = L["Automatically select greed (when available) on green quality items. This will only work if you are the max level."],
					disabled = function() return not E.private.general.lootRoll end,
				},
				lootRoll = {
					order = 9,
					type = "toggle",
					name = L["Loot Roll"],
					desc = L["Enable/disable the loot roll frame. Requires /reload to take effect."],
					get = function() return E.private.general.lootRoll end,
					set = function(_, value)
						E.private.general.lootRoll = value
						E:RequestReload("private")
					end,
				},
				loot = {
					order = 8,
					type = "toggle",
					name = L["Loot"],
					desc = L["Enable/disable the custom loot frame, replacing the native one. Requires /reload to take effect."],
					get = function() return E.private.general.loot end,
					set = function(_, value)
						E.private.general.loot = value
						E:RequestReload("private")
					end,
				},
				lootUnderMouse = {
					order = 10,
					type = "toggle",
					name = L["Loot Under Mouse"],
					desc = L["Open the loot frame at the cursor instead of its fixed position."],
					get = function() return E.private.general.lootUnderMouse end,
					set = function(_, value) E.private.general.lootUnderMouse = value end,
					disabled = function() return not E.private.general.loot end,
				},
				-- Layout module's two cosmetic screen strips. Real ElvUI's
				-- own orders (13/14) and setter targets. `get` is inherited
				-- from the root group -- the entry name IS the DB key -- so
				-- only `set` is spelled out, to also apply it live.
				bottomPanel = {
					order = 13,
					type = "toggle",
					name = L["Bottom Panel"],
					desc = L["Display a panel across the bottom of the screen. This is for cosmetic only."],
					set = function(_, value)
						E.db.general.bottomPanel = value
						E:GetModule("Layout"):BottomPanelVisibility()
					end,
				},
				topPanel = {
					order = 14,
					type = "toggle",
					name = L["Top Panel"],
					desc = L["Display a panel across the top of the screen. This is for cosmetic only."],
					set = function(_, value)
						E.db.general.topPanel = value
						E:GetModule("Layout"):TopPanelVisibility()
					end,
				},
				-- Number abbreviation. Real ElvUI's own orders (20/21) and value
				-- set. Both are read LIVE by `E:ShortValue` (Core/Util.lua), so
				-- no reload popup here: the unit frames repaint on their own
				-- 0.2s poll and the data bars on their next event. Upstream
				-- prompts for a reload at this spot only because ITS nameplates
				-- cache the formatted string, which is not a consumer here.
				-- `get`/`set` inherited from the root group -- the entry name IS
				-- the DB key.
				decimalLength = {
					order = 20,
					type = "range",
					name = L["Decimal Length"],
					desc = L["How many decimals a shortened value keeps -- 0 turns 1700 into 2K, 1 into 1.7K."],
					min = 0, max = 4, step = 1,
				},
				numberPrefixStyle = {
					order = 21,
					type = "select",
					name = L["Unit Prefix Style"],
					desc = L["Which unit prefixes a shortened value uses. Visible on unit frame health/power text and on the XP/Reputation bars."],
					values = {
						["METRIC"] = L["Metric (k, M, G)"],
						["ENGLISH"] = L["English (K, M, B)"],
						["CHINESE"] = L["Chinese (W, Y)"],
						["KOREAN"] = L["Korean (\236\178\156, \235\167\140, \236\150\181)"],
						["GERMAN"] = L["German (Tsd, Mio, Mrd)"],
					},
				},
			},
		},
		cooldown = {
			type = "group",
			name = L["Cooldown Text"],
			-- No explicit order, matching real ElvUI: an unordered entry
			-- defaults to 100 and therefore sorts last in this group.
			args = {
				header = {
					type = "header",
					name = L["Cooldown Text"],
					order = 1,
				},
				enable = {
					type = "toggle",
					name = L["Enable"],
					desc = L["Display cooldown text on anything with the cooldown spiral. Turning it off clears existing text within a fraction of a second; turning it on labels cooldowns as they next start, so any spiral already running keeps no text until it is triggered again."],
					order = 2,
					get = function() return E.private.cooldown.enable end,
					set = function(_, value) E.private.cooldown.enable = value end,
				},
				threshold = {
					type = "range",
					name = L["Low Threshold"],
					desc = L["Threshold before text turns red and is in decimal form. Set to -1 for it to never turn red."],
					order = 3,
					min = -1,
					max = 20,
					step = 1,
					get = function() return E.db.cooldown.threshold end,
					set = function(_, value) E.db.cooldown.threshold = value end,
				},
				expiringColor = CooldownColorArgs("expiringColor", 4, "Expiring", "Color when the text is about to expire."),
				secondsColor = CooldownColorArgs("secondsColor", 5, "Seconds", "Color when the text is in the seconds format."),
				minutesColor = CooldownColorArgs("minutesColor", 6, "Minutes", "Color when the text is in the minutes format."),
				hoursColor = CooldownColorArgs("hoursColor", 7, "Hours", "Color when the text is in the hours format."),
				daysColor = CooldownColorArgs("daysColor", 8, "Days", "Color when the text is in the days format."),
				-- Duration FORMAT. Real ElvUI field names verbatim
				-- (Settings/Profile.lua:177-180) -- see
				-- Core/Cooldowns.lua's own note on why they live on
				-- the top-level cooldown table here. These govern
				-- the standalone Auras module's countdown text too,
				-- so the whole addon stays in one format regime.
				formatHeader = {
					type = "header",
					name = L["Duration Format"],
					order = 9,
				},
				mmssThreshold = {
					type = "range",
					name = L["MM:SS Threshold"],
					desc = L["Below this many SECONDS remaining, show the time as M:SS instead of the plain minutes form -- e.g. 30:00 rather than 30m. Set to -1 to never use this format."],
					order = 10,
					min = -1, max = 3600, step = 10,
					get = function() return E.db.cooldown.mmssThreshold end,
					set = function(_, value) E.db.cooldown.mmssThreshold = value end,
				},
				mmssColor = CooldownColorArgs("mmssColor", 11, "MM:SS", "Color when the text is in the M:SS format."),
				hhmmThreshold = {
					type = "range",
					name = L["HH:MM Threshold"],
					desc = L["Below this many MINUTES remaining, show the time as H:MM instead of the plain hours form. Set to -1 to never use this format."],
					order = 12,
					min = -1, max = 1440, step = 5,
					get = function() return E.db.cooldown.hhmmThreshold end,
					set = function(_, value) E.db.cooldown.hhmmThreshold = value end,
				},
				hhmmColor = CooldownColorArgs("hhmmColor", 13, "HH:MM", "Color when the text is in the H:MM format."),
			},
		},
		mirrortimers = {
			type = "group",
			name = L["Mirror Timers"],
			-- Project extension (real ElvUI has this as a SKIN -- see
			-- docs/roadmap.md). Ordered after every vanilla group so it
			-- cannot disturb their relative order.
			order = 101,
			args = {
				header = {
					type = "header",
					name = L["Mirror Timers"],
					order = 1,
				},
				intro = {
					type = "description",
					order = 2,
					name = L["Restyles the native breath/feign-death/exhaustion (fatigue) bars -- purely visual, the actual tracking is 100% Blizzard's own native code."],
				},
				enable = {
					type = "toggle",
					name = L["Enable"],
					desc = L["Requires /reload to take effect."],
					order = 3,
					get = function() return E.private.mirrortimers.enable end,
					set = function(_, value)
						E.private.mirrortimers.enable = value
						E:RequestReload("private")
					end,
				},
				-- Both live via E:ResizeMirrorTimers (Core/MirrorTimers.lua),
				-- which re-applies just the dimensions, bypassing the
				-- `elvStyled` build-once guard that used to make these two
				-- settings construction-time-only. A timer that has not been
				-- styled yet simply reads the new value when it first is.
				width = {
					type = "range",
					name = L["Width"],
					order = 4,
					min = 100, max = 400, step = 1,
					get = function() return E.db.mirrortimers.width end,
					set = function(_, value)
						E.db.mirrortimers.width = value
						if E.ResizeMirrorTimers then E:ResizeMirrorTimers() end
					end,
				},
				height = {
					type = "range",
					name = L["Height"],
					order = 5,
					min = 8, max = 40, step = 1,
					get = function() return E.db.mirrortimers.height end,
					set = function(_, value)
						E.db.mirrortimers.height = value
						if E.ResizeMirrorTimers then E:ResizeMirrorTimers() end
					end,
				},
			},
		},
		media = {
			type = "group",
			name = L["Media"],
			order = 3,
			args = {
				-- Real ElvUI's own entry names and orders. Its Media group also
				-- carries font and colour settings (orders 1-8 and 16+), which
				-- this project does not implement -- hence the jump straight to
				-- the textures block at order 10.
				texturesHeader = {
					order = 10,
					type = "header",
					name = L["Textures"],
				},
				-- The two SHARED statusbar textures, both PRIVATE and
				-- reload-required: resolved once at OnInitialize into
				-- `E.media.normTex`/`E.media.glossTex` (Init.lua). Anything
				-- without its own more specific override reads them.
				--
				-- Custom addon-shipped textures DO render on UA -- an earlier
				-- version of this section claimed they don't. The real
				-- constraint is that UA resolves media paths CASE-SENSITIVELY
				-- while the legacy client does not, so a mis-cased path works on
				-- one client and silently resolves to nothing on the other.
				-- See docs/api-diffs/media.md.
				normTex = {
					order = 11,
					type = "select",
					dialogControl = "LSM30_Statusbar",
					name = L["Primary Texture"],
					desc = L["The texture used mainly for statusbars. Requires /reload to take effect."],
					values = STATUSBAR_VALUES,
					get = function() return E.private.general.normTex end,
					set = function(_, value)
						E.private.general.normTex = value
						E:RequestReload("private")
					end,
				},
				glossTex = {
					order = 12,
					type = "select",
					dialogControl = "LSM30_Statusbar",
					name = L["Secondary Texture"],
					desc = L["Used as the fill of every button-shaped backdrop -- this is where their subtle top-to-bottom falloff comes from. Requires /reload to take effect."],
					values = STATUSBAR_VALUES,
					get = function() return E.private.general.glossTex end,
					set = function(_, value)
						E.private.general.glossTex = value
						E:RequestReload("private")
					end,
				},
				-- The three UI colours, at real ElvUI's own keys and orders
				-- (17/18/19). All three ARE read -- `E:SetTemplate` (Core/Util.lua)
				-- takes the fill from backdropcolor/backdropfadecolor and the edge
				-- from bordercolor, and UnitFrames' ApplyPanelBackdrop reads the
				-- first two as well.
				--
				-- Reload-bound, and the popup says so: upstream applies a colour
				-- change live by sweeping every registered frame
				-- (`E:UpdateMedia` + `E:UpdateBorderColors`/`UpdateBackdropColors`
				-- over its `E.frames` registry), which this project has no
				-- equivalent of -- our colours are read once, at construction.
				--
				-- `valuecolor` below is the exception to that reload-bound
				-- treatment: it is consumed through `E.valueColorUpdateFuncs`,
				-- which exists precisely so the accent can be re-applied to
				-- already-built text, so its setter takes effect live.
				bordercolor = {
					order = 17,
					type = "color",
					name = L["Border Color"],
					desc = L["Main border color of the UI."],
					get = function()
						local c = E.db.general.bordercolor
						return c.r, c.g, c.b
					end,
					set = function(_, r, g, b)
						local c = E.db.general.bordercolor
						c.r, c.g, c.b = r, g, b
						E:RequestReload()
					end,
				},
				backdropcolor = {
					order = 18,
					type = "color",
					name = L["Backdrop Color"],
					desc = L["Main backdrop color of the UI."],
					get = function()
						local c = E.db.general.backdropcolor
						return c.r, c.g, c.b
					end,
					set = function(_, r, g, b)
						local c = E.db.general.backdropcolor
						c.r, c.g, c.b = r, g, b
						E:RequestReload()
					end,
				},
				backdropfadecolor = {
					order = 19,
					type = "color",
					name = L["Backdrop Faded Color"],
					desc = L["Backdrop color of transparent frames."],
					hasAlpha = true,
					get = function()
						local c = E.db.general.backdropfadecolor
						return c.r, c.g, c.b, c.a
					end,
					set = function(_, r, g, b, a)
						local c = E.db.general.backdropfadecolor
						c.r, c.g, c.b, c.a = r, g, b, a
						E:RequestReload()
					end,
				},
				-- The UI ACCENT colour, at real ElvUI's own key and order (20).
				-- Read by every data text's value half via
				-- `E.valueColorUpdateFuncs` (Init.lua), and set by the install
				-- wizard's theme picker -- the "class" theme writes the
				-- character's class colour here.
				--
				-- `hasAlpha = false`, matching upstream: the accent only ever
				-- becomes a `|cffRRGGBB` text prefix, which has no alpha
				-- channel to carry.
				valuecolor = {
					order = 20,
					type = "color",
					name = L["Value Color"],
					desc = L["Color some texts use."],
					hasAlpha = false,
					get = function()
						local c = E.db.general.valuecolor
						return c.r, c.g, c.b
					end,
					set = function(_, r, g, b)
						local c = E.db.general.valuecolor
						c.r, c.g, c.b = r, g, b
						E:UpdateValueColor()
					end,
				},
			},
		},
	},
}
