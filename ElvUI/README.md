# ElvUI

ElvUI rewrite for World of Warcraft — built from scratch to run on **both**
vanilla 1.12.1 and **Unreal Azeroth** (a from-scratch UE5 reimplementation
of the 1.12.1 client). ElvUI is a full UI replacement: it replaces the
default Blizzard UI at every level — unit frames, action bars, chat,
data panels, and every native Blizzard window it reskins in place — with
one coherent, configurable interface instead of a pile of separate addons.

The goal is to stay as visually and API-close to the real ElvUI as this
engine allows, so that an existing "real" ElvUI profile (the plain Lua
table `SavedVariables` format, not the modern compressed one) can
eventually be loaded as-is.

Two addons ship together:
- **ElvUI** — the main addon (unit frames, action bars, chat, data texts,
  movers, aura tracking, Blizzard-window skinning, and more).
- **ElvUI_Config** — the options window, since the stock
  `AceConfigDialog-3.0`/`InterfaceOptionsFrame_OpenToCategory` path is
  broken on Unreal Azeroth. Built on `LibConfig-1.0` instead.

## Status

**Done:**
- Core engine (profiles, defaults, SavedVariables layout matching real
  ElvUI where practical)
- Layout (screen panels, minimap panels, mover system)
- ActionBars, PetBar/StanceBar, Cooldown text
- UnitFrames (player/target/pet/party/etc.), Auras
- DataBars (XP/Reputation), DataTexts
- Chat
- Bags/Bank
- Solo loot
- Install Wizard
- Skinning of a large and growing set of native Blizzard windows in
  place (Character, Friends, SpellBook, Macro, Key Bindings, Main Menu,
  Interface/Video/Sound Options, Gossip/Greeting/Quest/QuestLog,
  Merchant, Taxi, Pet Stable, Talents, Trade Skills, and more)

**Missing / not yet started:**
- Group loot (Need/Greed/Pass roll UI) — solo loot only for now
- Tooltip module
- A handful of native windows not yet reskinned (Auction House, Mail,
  Trade, Trainer, Tabard, World Map polish, and a few more niche ones)
- Nameplate customization — blocked by a client-side limitation on
  Unreal Azeroth, parked until that changes
- A few smaller ElvUI features (auto-track reputation, chat-anchored
  data panels) are researched but not built yet

## Known issues

- A number of settings still require a full UI reload to take effect; the
  options window tells you when that's the case, and a confirmation
  popup offers to reload for you.

## Sources

Re-used ideas/recipes from the following projects:
- [ElvUI](https://www.tukui.org/elvui.php) — the addon this project
  rewrites from scratch; the closest match to it, plus the
  [ElvUI-Vanilla](https://github.com/ElvUI-Vanilla/ElvUI) backport, is
  the primary structural/API reference throughout.
- [pfUI](https://github.com/shagu/pfUI) — proven vanilla-compatible skin
  recipes for native Blizzard windows.
- [Bagzen](https://github.com/dh-harald/Bagzen) — bag/bank item-slot
  skinning recipe.
- [LibConfig-1.0](https://git.sagittarius.guru/misi/LibConfig-1.0) — the
  options-window library, since AceConfigDialog-3.0 doesn't work on
  Unreal Azeroth.

## Development

Built with heavy use of [Claude Code](https://claude.com/claude-code)
(Anthropic) — architecture, modules, Blizzard-window skinning, dual-client
compatibility work, and documentation.

## Screenshots

<img src="media/screenshot-1.png" width="48.5%">
<img src="media/screenshot-2.png" width="48.5%">
<img src="media/screenshot-3.png" width="48.5%">
<img src="media/screenshot-4.png" width="48.5%">

## Tested on

- WoW 1.12.1 (Legacy client)
- WoW 1.12.1 (Unreal Azeroth)
