-- GENERATED from the default tables of the source ElvUI versions; do not
-- edit by hand.
--
-- The defaults of other ElvUI versions wherever they differ from this
-- addon's, by source ("retail": current ElvUI for Classic, "vanilla":
-- ElvUI-vanilla) and export type. An export carries only the values that
-- differ from its own ElvUI's defaults; E:ImportProfile fills every key a
-- foreign string leaves out from here, so the import looks as it did at the
-- source. Values are already in this addon's value space. Font faces are
-- left out (what the string sets stays, the rest is ours), and so are a few
-- keys this addon cannot follow (data bar orientation, ElvUI-vanilla's
-- vertical data bar size, nameplates, sounds).

local E = unpack(ElvUI)

E.ImportDefaults = {
	retail = {
		profile = {
			auras = {
				buffs = {
					maxWraps = 3,
					wrapAfter = 12,
				},
				debuffs = {
					maxWraps = 1,
					wrapAfter = 12,
				},
			},
			bags = {
				bagBar = {
					visibility = "show",
				},
				bagWidth = 600,
				bankWidth = 800,
				colors = {
					items = {
						questItem = {
							r = 0.9,
						},
						questStarter = {
							b = 0.41,
							g = 0.96,
						},
					},
					profession = {
						ammoPouch = {
							b = 0.41,
							g = 0.69,
						},
						enchanting = {
							b = 0.74,
							g = 0.22,
							r = 0.72,
						},
						gems = {
							b = 0.75,
							g = 0.65,
						},
						herbs = {
							b = 0.07,
							g = 0.74,
							r = 0.28,
						},
						leatherworking = {
							b = 0.2,
							g = 0.55,
							r = 0.74,
						},
						quiver = {
							b = 0.41,
							g = 0.69,
						},
						soulBag = {
							b = 0.41,
							g = 0.69,
							r = 1,
						},
					},
				},
				strata = "HIGH",
			},
			chat = {
				fadeUndockedTabs = false,
				keywords = "ElvUI",
				numAllowedCombatRepeat = 5,
			},
			databars = {
				experience = {
					height = 10,
					width = 348,
				},
				reputation = {
					enable = false,
					width = 222,
				},
			},
			datatexts = {
				fontOutline = "NONE",
			},
			general = {
				fontStyle = "OUTLINE",
				minimap = {
					icons = {
						battlefield = {
							scale = 1.1,
							xOffset = 4,
							yOffset = -4,
						},
					},
					size = 175,
				},
				valuecolor = {
					b = 0.82,
					g = 0.52,
					r = 0.09,
				},
			},
			tooltip = {
				headerFontSize = 13,
				healthBar = {
					fontOutline = "NONE",
					fontSize = 12,
					height = 12,
				},
			},
			unitframe = {
				colors = {
					classResources = {
						comboPoints = {
							[1] = {
								r = 0.75,
							},
							[2] = {
								g = 0.56,
								r = 0.78,
							},
							[3] = {
								b = 0.31,
								g = 0.81,
								r = 0.81,
							},
							[4] = {
								b = 0.31,
								g = 0.78,
								r = 0.56,
							},
							[5] = {
								b = 0.31,
								g = 0.76,
								r = 0.43,
							},
						},
					},
					healPrediction = {
						others = {
							a = 0.5,
						},
						personal = {
							a = 0.5,
						},
					},
					power = {
						ENERGY = {
							b = 0.41,
							g = 0.96,
							r = 1,
						},
						FOCUS = {
							b = 0.25,
							g = 0.5,
							r = 1,
						},
					},
				},
				units = {
					party = {
						CombatIcon = {
							enable = false,
							size = 20,
						},
						buffs = {
							enable = true,
							maxDuration = 300,
							perrow = 8,
							sizeOverride = 0,
						},
						debuffs = {
							perrow = 5,
						},
						health = {
							text_format = "[healthcolor][health:current-percent:shortvalue]",
						},
						name = {
							text_format = "[classcolor][name:medium] [difficultycolor][smartlevel]",
						},
						power = {
							text_format = "[powercolor][power:current:shortvalue]",
						},
					},
					pet = {
						buffs = {
							maxDuration = 300,
							sizeOverride = 0,
						},
						debuffs = {
							maxDuration = 300,
							sizeOverride = 0,
						},
						name = {
							text_format = "[classcolor][name:medium]",
						},
						power = {
							height = 10,
						},
					},
					pettarget = {
						buffs = {
							maxDuration = 300,
							sizeOverride = 0,
						},
						debuffs = {
							maxDuration = 300,
							sizeOverride = 0,
						},
						enable = false,
						name = {
							text_format = "[classcolor][name:medium]",
						},
						power = {
							enable = true,
							height = 10,
						},
					},
					player = {
						buffs = {
							sizeOverride = 0,
						},
						debuffs = {
							sizeOverride = 0,
						},
						health = {
							text_format = "[healthcolor][health:current-percent:shortvalue]",
						},
						power = {
							text_format = "[cpoints][powercolor][  >power:current:shortvalue]",
						},
					},
					target = {
						buffs = {
							sizeOverride = 0,
						},
						debuffs = {
							maxDuration = 300,
							sizeOverride = 0,
						},
						health = {
							text_format = "[healthcolor][health:current-percent:shortvalue]",
						},
						name = {
							text_format = "[classcolor][name:medium] [difficultycolor][smartlevel] [shortclassification]",
						},
						power = {
							text_format = "[powercolor][power:current:shortvalue]",
						},
					},
					targettarget = {
						buffs = {
							maxDuration = 300,
							sizeOverride = 0,
						},
						debuffs = {
							attachTo = "BUFFS",
							maxDuration = 300,
							sizeOverride = 0,
						},
						name = {
							text_format = "[classcolor][name:medium]",
						},
						power = {
							height = 10,
						},
					},
				},
			},
		},
		private = {
		},
	},
	vanilla = {
		profile = {
			auras = {
				buffs = {
					maxWraps = 3,
					wrapAfter = 12,
				},
				debuffs = {
					maxWraps = 1,
					wrapAfter = 12,
				},
			},
			databars = {
				reputation = {
					enable = false,
				},
			},
			unitframe = {
				units = {
					party = {
						name = {
							text_format = "[namecolor][name:medium] [difficultycolor][smartlevel]",
						},
					},
					pet = {
						name = {
							text_format = "[namecolor][name:medium]",
						},
					},
					pettarget = {
						enable = false,
						name = {
							text_format = "[namecolor][name:medium]",
						},
					},
					target = {
						name = {
							text_format = "[namecolor][name:medium] [difficultycolor][smartlevel] [shortclassification]",
						},
					},
					targettarget = {
						name = {
							text_format = "[namecolor][name:medium]",
						},
					},
				},
			},
		},
		private = {
		},
	},
}
