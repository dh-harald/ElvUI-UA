# LibConfig-1.0

A vanilla (WoW 1.12.1 / Lua 5.0) options-window library. It takes an
AceConfig-format options table (the same shape `AceConfigDialog-3.0` consumes)
and renders it into its own window: a list of registered addons/categories on
the left, the selected category's options on the right.

It exists to replace `InterfaceOptionsFrame_OpenToCategory`, whose Blizzard
Interface Options frame is broken on the Unreal Azeroth 1.12.1 private server
(and needlessly heavyweight on a plain 1.12.1 client). The window is the same on
both clients.

## Usage

```lua
local LC = LibStub("LibConfig-1.0")

-- Register an options table. The table is AceConfig format:
-- { name = "...", type = "group", args = { ... } }
LC:RegisterOptionsTable("MyAddon", "MyAddon", ConfigTable)

-- Build the panel (returns the panel frame). Optional.
local panel = LC:AddToBlizOptions("MyAddon", "MyAddon")

-- Open the window to a registered category. This is the call that replaces
-- InterfaceOptionsFrame_OpenToCategory("MyAddon").
LC:OpenToCategory("MyAddon")

-- Also available:
-- LC:Open(appName, name)
-- LC:Close()
```

A category registered with `RegisterOptionsTable` shows up in the left sidebar
under its `name`; clicking it renders that category's options on the right.

## Supported options

Widgets (`type`):

- `group` — nested groups render as inline section headers.
- `toggle` — checkbox.
- `select` — dropdown; `values` may be a table or a zero-arg function, and
  `width = "full"` makes it span the content width.
- `range` — drag-thumb slider (`min`/`max`/`step`).
- `execute` — button (`func`, or `set` if `func` is absent).
- `header` / `description` — display-only rows.

Option members (resolved the same way AceConfigDialog resolves them):

- `name`, `desc` — string literals or functions.
- `order` — number or function.
- `hidden`, `disabled` — booleans or functions.
- `get`, `set`, `values` — function refs or method-name strings resolved on the
  nearest `handler`. `set`/`get` receive an `info` table (`info[1..n]` path,
  `info.arg`, `info.type`, `info.option`, `info.handler`, `info.options`,
  `info.appName`).

Long lists scroll. Both the content area and the category sidebar get a proper
vertical scrollbar — a dark track between two arrow buttons, with a draggable
thumb sized to how much of the list is visible — shown only when that list
overflows. Dropdown menus use `^` / `v` navigation buttons instead. The mouse
wheel works too where the client allows it, but is unreliable on Unreal Azeroth,
so the buttons and thumb are the dependable path on both clients.

The scrollbar thumb is driven from `GetCursorPosition` rather than
`StartMoving`, which is what keeps it locked to its own axis and inside its
track (`StartMoving` is a free 2D move, so a thumb dragged that way drifts
sideways and can leave the track).

A `childGroups = "tab"` group draws its children as a tab strip. Tabs are
measured at their full label width and wrap onto as many rows as they need, so a
label is never truncated no matter how many tabs a group has; each row is then
justified to the content width.

## Theme

The look borrows **ElvUI's color palette** (dark panel fill, thin 1 px borders,
a yellow `#FFD100` accent); the widget/frame mechanics follow **UnrealUI's**
proven-on-this-client patterns — flat fill backdrops, explicit borders drawn as
textures, a drag-thumb Button for `range` instead of the broken native Slider,
and no EditBox.

### Artwork

The library ships its own sprite sheets in `Media/` (`PlusMinusButton.blp` for
the sidebar's expand/collapse markers, `SquareButtonTextures.blp` for the
navigation arrows), so it needs no media from the host addon. Because the
library is *embedded*, its absolute `Interface\AddOns\…` path differs per host;
it recovers its own folder from `debugstack()` at load. If that ever fails, the
glyphs degrade to plain `+` / `-` / `^` / `v` characters — never an error.

To supply different artwork, register it before opening the window:

```lua
LC:SetMedia({
    plusMinus = "Interface\\AddOns\\MyAddon\\Media\\MyPlusMinus",
    arrows    = "Interface\\AddOns\\MyAddon\\Media\\MyArrows",
})
```

Both keys are optional and expect ElvUI's sheet layout (the `PLUS`/`MINUS`
halves, and `UP`/`DOWN`/`LEFT`/`RIGHT` cells respectively).

## Requirements

- **Lua 5.0** (WoW 1.12.1). A `Compat/Lua50.lua` shim file is included and is a
  no-op on a Lua 5.1+ client (a future 3.3.5a build).
- **LibStub** (embedded by the host addon).

## Distribution

A LibStub embedded minor. Embed it via your packager's `externals` and load
`LibConfig-1.0.xml` from the host addon's `.toc`. Because it is an embedded
minor, only one copy loads (whichever addon loads first) — keep every embedded
copy in sync.

## Credits

- Library design and implementation: **DeepSeek**, **Claude**.
- Widget/frame mechanics adapted from [UnrealUI](https://github.com/Tom75VN/UnrealUI) (MIT).
- Color palette inspired by [ElvUI](https://github.com/tukui-org/ElvUI).
- `Media/PlusMinusButton.blp` and `Media/SquareButtonTextures.blp` are
  [ElvUI](https://github.com/tukui-org/ElvUI) artwork.

## License

MIT — see [LICENSE](LICENSE) for the full text and the third-party reference
notes (UnrealUI mechanics, ElvUI palette).
