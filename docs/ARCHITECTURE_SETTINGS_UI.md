# Settings UI framework

The settings tabs are not native vertical-layout subcategories; they are
**canvas-layout** panels that share one custom header and a schema-driven
widget renderer.

## Panel chrome

`Helpers.CreatePanel(name, title, opts)` builds a Frame compatible with
`Settings.RegisterCanvasLayoutSubcategory` and stamps a unified header on
top:

* Title FontString (`GameFontNormalHuge`) at top-left
* `Defaults` button (AceGUI `Button`) at top-right when
  `opts.defaultsButton` is true (General / Icons / Cast bar / Spells);
  omitted on Profiles
* `Options_HorizontalDivider` atlas underneath, full panel width
* A `body` Frame anchored beneath the header that hosts the panel's
  content

The function returns a `ctx` table — `{ panel, body, scroll,
refreshers, lastGroup, panelKey }` — that the caller threads through
the section/widget helpers. `scroll` is a lazily-created AceGUI
`ScrollFrame` (built on first widget add via `ensureScroll`); tabs that
don't use the schema renderer (Spells / Profiles) parent their own
AceGUI containers to `ctx.body` directly and never trigger the lazy
scroll. Every panel ctx is stashed in `KickCD.Settings._panels` so
`Helpers.RefreshAllPanels` can re-sync widgets after a slash-cmd write.

## Schema (`KickCD.Settings.Schema`)

A flat array; each row declares one option:

```lua
{ panel, section, group, path, type, label, tooltip, default,
  min, max, step, fmt,            -- numbers
  values,                          -- strings (dropdown); array or fn
  onChange = function(v) ... end } -- optional
```

`type ∈ { bool, number, string, color }`. The same row drives:

| Surface | How |
|---|---|
| Panel widget | `Helpers.RenderField(ctx, def)` dispatches by type to `makeCheckbox` / `makeSlider` / `makeDropdown` / `makeColorPicker`; each registers a refresher closure on `ctx.refreshers` |
| `/kcd list` | groups schema by `panel`, prints `path = formattedValue` |
| `/kcd get <path>` | `Helpers.FindSchema(path)` + `formatValue` |
| `/kcd set <path> <value>` | type-aware parse (clamp numbers, validate dropdown values, parse `r g b [a]` for colors) → `Helpers.Set` → `onChange` → `Helpers.RefreshAllPanels` |
| `Defaults` button | `Helpers.RestoreDefaults(panelKey, ctx)` resets every panel row to `def.default`, runs `onChange`, fires per-section `KickCD_CONFIG_CHANGED`, re-runs the panel's refreshers |

**Adding an option = one schema row.** UI, slash CLI, and Defaults reset
are wired automatically.

## Custom-body tabs

* **Spells** — AceGUI editor (class/spec dropdowns, Add spell button,
  scrollable row list) parented to `ctx.body`. Header `Defaults` button
  opens the existing `KICKCD_RESET_SPELLS` StaticPopup (resets the
  current class+spec only).
* **Profiles** — `AceConfigDialog:Open("KickCD-Profiles", container)`
  renders the AceDBOptions options table into an AceGUI `SimpleGroup`
  parented to `ctx.body`. No `Defaults` button — AceDBOptions has its
  own destructive controls.

## Widget binding

Canvas widgets bind directly to `db.profile` via `Helpers.Get(path)` /
`Helpers.Set(path, section, value)`. They do **not** go through
`Settings.RegisterAddOnSetting` — the Compat shim for that API exists
but has no live callers. Schema rows are rendered by AceGUI primitives:
`CheckBox` for `bool`, `Slider` for `number`, `Dropdown` for `string`
(values supplied as `{ {value=, label=}, ... }` or a function returning
that shape — `Helpers.LSMValues(mediaType)` is the standard wrapper
around LibSharedMedia listings), and `ColorPicker` for `color`. The
ColorPicker's confirmation flow is a quirk of WoW 12.0's
`SetupColorPickerAndShow` — KickCD listens to **both** `OnValueChanged`
(treats every drag-step as a commit, giving a live preview) and
`OnValueConfirmed` (fires only on Cancel, with the original color, so
the value reverts cleanly). Section headings are AceGUI `Heading`
widgets bumped to `GameFontNormalLarge`. Two-column rows are produced
by wrapping a 50%-width pair into a Flow-laid `SimpleGroup`; spacers
between rows give the airy look. See `Helpers.RenderSchema` and the
`makeCheckbox` / `makeSlider` / `makeDropdown` / `makeColorPicker`
factories in `settings/Panel.lua`.

