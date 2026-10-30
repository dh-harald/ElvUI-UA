-- Global defaults -- `G` (Engine[5]), stored in `ElvDB.global`: one shared
-- copy per ACCOUNT, outside the profile system entirely.
--
-- THE ONE AND ONLY place a `G.*` key may be declared -- see Profile.lua's
-- header for why defaults live centrally rather than next to their
-- consumers.
--
-- This is also where anything that is NOT profile data belongs: UI state
-- and one-shot bookkeeping markers must stay out of `E.db`, which is the
-- table meant to remain format-compatible with a real ElvUI profile.

local E, L, V, P, G = unpack(ElvUI)

-- Core/ClassCache.lua: realm -> player name -> class file name.
G.classCache = {}

-- Names Modules/Chat/Chat.lua never class-colours when they are mentioned in
-- a message, keyed by the lower-cased name.
G.chat = {
	classColorMentionExcludedNames = {},
}

-- Aura lists named in a `filters.priority` string (Modules/UnitFrames/
-- AuraFilter.lua). Retail ElvUI's Classic lists (Game/Classic/Filters),
-- keyed by aura NAME instead of spell ID: neither client reports spell IDs,
-- auras are known by name only (tooltip scan, LibVanillaDurations-1.0). The
-- ranks of a spell fold into one entry, and a list entry also matches any
-- other aura of the same name. Retail's Blacklist entries are all auras of
-- later clients, so it starts empty; Classic has no PlayerBuffs list, and
-- that token matches nothing. An entry is retail's E.Filters.List.
local function List(priority)
	return { enable = true, priority = priority or 0, stackThreshold = 0 }
end

G.unitframe = {
	aurafilters = {
		Blacklist = {
			type = "Blacklist",
			spells = {},
		},
		-- Auras which should always be displayed. Retail's Classic list
		-- without the Chronoboon Displacer (a later Classic item) and its
		-- later-client Blood Fury variants; potions by the aura they apply.
		Whitelist = {
			type = "Whitelist",
			spells = {
			-- Consumables
			["Invulnerability"] = List(), -- Limited Invulnerability Potion
			["Free Action"] = List(), -- Free Action Potion
			-- Racial
			["Berserking"] = List(),
			["Will of the Forsaken"] = List(),
			["Blood Fury"] = List(),
			["Fear Ward"] = List(),
			["Stoneform"] = List(),
			-- All Classes
			["Divine Intervention"] = List(),
			-- Druid
			["Innervate"] = List(),
			["Barkskin"] = List(),
			["Nature's Swiftness"] = List(),
			["Nature's Grasp"] = List(),
			["Omen of Clarity"] = List(),
			["Tiger's Fury"] = List(),
			["Enrage"] = List(),
			},
		},
		-- Stuns, roots, slows, silences and other crowd control.
		CCDebuffs = {
			type = "Whitelist",
			spells = {
			-- Druid
			["Entangling Roots"] = List(1),
			["Hibernate"] = List(1),
			["Feral Charge Effect"] = List(2),
			["Bash"] = List(4),
			["Starfire Stun"] = List(2),
			["Pounce"] = List(2),
			-- Hunter
			["Freezing Trap Effect"] = List(3),
			["Frost Trap Aura"] = List(1),
			["Scatter Shot"] = List(4),
			["Concussive Shot"] = List(2),
			["Wing Clip"] = List(2),
			["Scare Beast"] = List(2),
			["Intimidation"] = List(6),
			["Wyvern Sting"] = List(2),
			["Improved Wing Clip"] = List(2),
			["Counterattack"] = List(2),
			["Improved Concussive Shot"] = List(2),
			["Charge"] = List(2),
			["Entrapment"] = List(1),
			-- Mage
			["Polymorph"] = List(3),
			["Polymorph: Turtle"] = List(3),
			["Polymorph: Pig"] = List(3),
			["Frost Nova"] = List(1),
			["Frostbite"] = List(2),
			["Frostbolt"] = List(2),
			["Impact"] = List(2),
			["Counterspell - Silenced"] = List(2),
			["Blast Wave"] = List(2),
			["Chilled"] = List(2),
			["Cone of Cold"] = List(2),
			-- Paladin
			["Hammer of Justice"] = List(3),
			["Repentance"] = List(3),
			["Stun"] = List(2),
			["Turn Undead"] = List(3),
			-- Priest
			["Psychic Scream"] = List(3),
			["Mind Control"] = List(5),
			["Blackout"] = List(2),
			["Mind Flay"] = List(2),
			["Silence"] = List(2),
			-- Rogue
			["Sap"] = List(4),
			["Blind"] = List(5),
			["Kidney Shot"] = List(4),
			["Cheap Shot"] = List(2),
			["Gouge"] = List(2),
			["Kick - Silenced"] = List(2),
			["Riposte"] = List(2),
			-- Shaman
			["Earthbind"] = List(1),
			["Frost Shock"] = List(2),
			["Frostbrand Attack"] = List(2),
			-- Warlock
			["Fear"] = List(3),
			["Seduction"] = List(3),
			["Curse of Exhaustion"] = List(2),
			["Pyroclasm"] = List(2),
			["Banish"] = List(2),
			["Death Coil"] = List(3),
			["Howl of Terror"] = List(3),
			["Spell Lock"] = List(2),
			["Aftermath"] = List(2),
			["Cripple"] = List(2),
			["Enslave Demon"] = List(5),
			-- Warrior
			["Intimidating Shout"] = List(4),
			["Hamstring"] = List(2),
			["Concussion Blow"] = List(2),
			["Intercept Stun"] = List(2),
			["Charge Stun"] = List(2),
			["Revenge Stun"] = List(2),
			["Shield Bash - Silenced"] = List(2),
			["Improved Hamstring"] = List(2),
			["Disarm"] = List(2),
			["Piercing Howl"] = List(2),
			-- Mace Specialization
			["Mace Stun Effect"] = List(2),
			-- Racial
			["War Stomp"] = List(2),
			-- Armor and spell debuffs
			["Sunder Armor"] = List(6),
			["Faerie Fire"] = List(5),
			["Faerie Fire (Feral)"] = List(5),
			["Winter's Chill"] = List(5),
			},
		},
		-- Immunities and major defensive cooldowns.
		TurtleBuffs = {
			type = "Whitelist",
			spells = {
			-- Druid
			["Barkskin"] = List(2),
			-- Hunter
			["Deterrence"] = List(2),
			-- Mage
			["Ice Block"] = List(2),
			-- Paladin
			["Divine Protection"] = List(2),
			["Divine Shield"] = List(2),
			["Blessing of Protection"] = List(2),
			-- Rogue
			["Evasion"] = List(2),
			["Vanish"] = List(2),
			-- Warrior
			["Last Stand"] = List(2),
			["Shield Wall"] = List(2),
			["Retaliation"] = List(2),
			-- Consumables
			["Limited Invulnerability Potion"] = List(2),
			["Free Action Potion"] = List(2),
			-- Racial
			["Will of the Forsaken"] = List(2),
			["Fear Ward"] = List(2),
			["Stoneform"] = List(2),
			-- All Classes
			["Divine Intervention"] = List(2),
			},
		},
		-- Important dungeon and raid debuffs.
		RaidDebuffs = {
			type = "Whitelist",
			spells = {
			-- Misc
			["Resurrection Sickness"] = List(6),
			-- Multiple Dungeons
			["Poison"] = List(2),
			["Curse of Weakness"] = List(2),
			["Immolate"] = List(2),
			["Slow"] = List(2),
			["Net"] = List(2),
			["Sleep"] = List(2),
			-- Blackrock Depths
			["Psychic Scream"] = List(2),
			-- Deadmines
			["Rhahk'Zor Slam"] = List(2),
			["Pierce Armor"] = List(2),
			["Terrify"] = List(2),
			["Disarm"] = List(2),
			["Molten Metal"] = List(2),
			["Poisoned Harpoon"] = List(2),
			-- Maraudon
			["Smoke Bomb"] = List(2),
			["Repulsive Gaze"] = List(2),
			-- Razorfen Downs, Razorfen Kraul
			["Curse of Tuten'kash"] = List(2),
			["Web Spray"] = List(2),
			["Dominate Mind"] = List(2),
			["Putrid Stench"] = List(2),
			-- Scarlet Monastery
			["Flame Spike"] = List(2),
			["Silence"] = List(2),
			["Deep Sleep"] = List(2),
			["Curse of Blood"] = List(2),
			-- Shadowfang Keep
			["Veil of Shadow"] = List(2),
			["Toxic Saliva"] = List(2),
			["Arugal's Curse"] = List(2),
			-- Stratholme
			["Enchanting Lullaby"] = List(2),
			["Ground Smash"] = List(2),
			["Burning Winds"] = List(2),
			["Domination"] = List(2),
			["Banshee Curse"] = List(2),
			["Ice Tomb"] = List(2),
			["Knockout"] = List(2),
			-- Sunken Temple
			["Curse of Tongues"] = List(2),
			["Cause Insanity"] = List(2),
			["Hex of Jammal'an"] = List(2),
			["Deep Slumber"] = List(2),
			["War Stomp"] = List(2),
			-- Uldaman
			["Flame Lash"] = List(2),
			["Ground Tremor"] = List(2),
			-- Wailing Caverns
			["Druid's Slumber"] = List(2),
			["Grasping Vines"] = List(2),
			["Naralex's Nightmare"] = List(2),
			["Thundercrack"] = List(2),
			-- Zul'Farrak
			["Freeze Solid"] = List(2),
			-- World Bosses
			["Mark of Kazzak"] = List(2),
			["Seeping Fog"] = List(2),
			-- Onyxia's Lair
			["Bellowing Roar"] = List(2),
			-- Molten Core
			["Lucifron's Curse"] = List(5),
			["Panic"] = List(2),
			["Gehennas' Curse"] = List(3),
			["Living Bomb"] = List(6),
			["Inferno"] = List(3),
			["Shazzrah's Curse"] = List(5),
			["Fist of Ragnaros"] = List(2),
			["Ignite Mana"] = List(2),
			["Deaden Magic"] = List(2),
			-- Blackwing Lair
			["Conflagration"] = List(2),
			["Burning Adrenaline"] = List(2),
			["Mortal Strike"] = List(2),
			["Shadow of Ebonroc"] = List(2),
			["Brood Affliction: Bronze"] = List(2),
			-- Zul'Gurub
			["Holy Fire"] = List(2),
			["Sonic Burst"] = List(2),
			["Corrosive Poison"] = List(2),
			["Blind"] = List(2),
			["Corrupted Blood"] = List(2),
			["Hex"] = List(2),
			["Delusions of Jin'do"] = List(2),
			["Poison Bolt Volley"] = List(2),
			-- Ruins of Ahn'Qiraj
			["Mortal Wound"] = List(2),
			["Attack Order"] = List(2),
			["Dismember"] = List(2),
			["Paralyze"] = List(2),
			["Enveloping Winds"] = List(2),
			-- Temple of Ahn'Qiraj
			["True Fulfillment"] = List(2),
			["Fear"] = List(2),
			["Acid Spit"] = List(2),
			["Wyvern Sting"] = List(2),
			["Noxious Poison"] = List(2),
			["Unbalancing Strike"] = List(2),
			["Dark Glare"] = List(2),
			-- Naxxramas
			["Widow's Embrace"] = List(2),
			["Web Wrap"] = List(2),
			["Mutating Injection"] = List(2),
			["Curse of the Plaguebringer"] = List(2),
			["Mark of Zeliek"] = List(2),
			["Frost Blast"] = List(2),
			["Chains of Kel'Thuzad"] = List(2),
			["Detonate Mana"] = List(2),
			},
		},
	},
}

G.general = {
	smallerWorldMap = true,
	smallerWorldMapScale = 0.9,
	WorldMapCoordinates = {
		enable = true,
		position = "BOTTOMLEFT",
		xOffset = 0,
		yOffset = 0,
	},
}

-- One-shot migration markers for the standalone Auras module -- see
-- `A:MigrateAuraFields`. Global rather than per-profile because a marker key
-- in `E.db` would be exactly the kind of invented field that breaks real
-- profile compatibility.
G.auras = {
	gridDefaultsCorrected = false,
}

-- Mail module (`Modules/Mail/`): bulk inbox handling and multi-item sending
-- on the native mailbox. Global rather than profile because real ElvUI has
-- no such module and `E.db` has to stay real-profile compatible.
--
-- `enable` also decides which look the mailbox gets, in the direction that
-- is easy to get backwards: with the module ON the window is ALWAYS skinned,
-- because the module draws its own controls in this UI's style and pulls the
-- skin in itself (`Modules/Skins/Blizzard/Mail.lua`, `S:ApplyMailSkin`).
-- The per-window skin toggle therefore only decides anything while the
-- module is off, and the options tree disables it accordingly.
--
-- `expiryWarning`, `moneySummary` and `express` are read fresh on the next
-- inbox refresh, bulk run and row click, so none of them needs a reload.
-- `express` is a toggle rather than always-on because Ctrl-clicking a row
-- sends that mail away with no confirmation and no undo.
G.mail = {
	enable = true,
	expiryWarning = true,
	moneySummary = true,
	express = true,
	cleanEmptied = true,
	autoComplete = true,
}

-- Nameplate style filters (Modules/NamePlates/StyleFilter.lua), real ElvUI's
-- values (ElvUI-vanilla Settings/Filters/NamePlate.lua). The switch of a
-- filter is per profile, in `P.nameplates.filters`.
G.nameplates = {
	filters = {
		Boss = {
			triggers = {
				level = true,
				curlevel = -1,
				nameplateType = {
					enable = true,
					enemyNPC = true,
				},
			},
			actions = {
				scale = 1.15,
			},
		},
	},
}

-- What a filter leaves out takes these values. Real ElvUI's keys;
-- `instanceDifficulty` and `casting.interruptible` are not read, neither
-- exists on these clients.
E.StyleFilterDefaults = {
	triggers = {
		priority = 1,
		isTarget = false,
		notTarget = false,
		level = false,
		casting = {
			interruptible = false,
			spells = {},
		},
		role = {
			tank = false,
			healer = false,
			damager = false,
		},
		curlevel = 0,
		maxlevel = 0,
		minlevel = 0,
		healthThreshold = false,
		healthUsePlayer = false,
		underHealthThreshold = 0,
		overHealthThreshold = 0,
		powerThreshold = false,
		underPowerThreshold = 0,
		overPowerThreshold = 0,
		names = {},
		nameplateType = {
			enable = false,
			friendlyPlayer = false,
			friendlyNPC = false,
			enemyPlayer = false,
			enemyNPC = false,
		},
		reactionType = {
			enable = false,
			hostile = false,
			neutral = false,
			friendly = false,
		},
		instanceType = {
			none = false,
			party = false,
			raid = false,
			arena = false,
			pvp = false,
		},
		instanceDifficulty = {
			dungeon = { normal = false, heroic = false },
			raid = { normal = false, heroic = false },
		},
		cooldowns = {
			names = {},
			mustHaveAll = false,
		},
		buffs = {
			mustHaveAll = false,
			missing = false,
			names = {},
			minTimeLeft = 0,
			maxTimeLeft = 0,
		},
		debuffs = {
			mustHaveAll = false,
			missing = false,
			names = {},
			minTimeLeft = 0,
			maxTimeLeft = 0,
		},
		inCombat = false,
		outOfCombat = false,
	},
	actions = {
		color = {
			health = false,
			border = false,
			name = false,
			healthColor = {r = 1, g = 1, b = 1, a = 1},
			borderColor = {r = 1, g = 1, b = 1, a = 1},
			nameColor = {r = 1, g = 1, b = 1, a = 1},
		},
		texture = {
			enable = false,
			texture = "ElvUI Norm",
		},
		flash = {
			enable = false,
			color = {r = 1, g = 1, b = 1, a = 1},
			speed = 4,
		},
		hide = false,
		nameOnly = false,
		scale = 1.0,
		alpha = -1,
	},
}

-- Saved position of the `/moveui` control panel. Project-only UI state,
-- filled at runtime by Core/Movers.lua.
G.moverPanel = {}

-- Arrow-key bindings removed while `/moveui` is open on Unreal Azeroth, keyed
-- by chord, so they are rebound even after a /reload inside move mode.
-- Project-only UI state, filled and emptied at runtime by Core/Movers.lua.
G.moverBindings = {}

-- Whether the Lua error window (Core/DebugTools.lua) opens by itself on a new
-- error; errors are recorded either way. Toggled with "/elvui errors on|off".
-- Project-only UI state, so global rather than profile.
G.debugTools = {
	autoOpen = true,
}
