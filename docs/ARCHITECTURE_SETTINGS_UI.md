# Settings UI framework

The settings tabs are not native vertical-layout subcategories; they are
**canvas-layout** panels that share one custom header and a schema-driven
widget renderer.

## Panel chrome

`Helpers.CreatePanel(name, title, opts)` builds a Frame compatible with
`Settings.RegisterCanvasLayoutSubcategory` and stamps a unified header on
top:

* Title FontString (`GameFontNormalHuge`) at top-left
* `Defaults` button (`UIPanelButtonTemplate`) at top-right when
  `opts.defaultsButton` is true (General/Icons/Spells); omitted on
  Profiles
* `Options_HorizontalDivider` atlas underneath, full panel width
* A `body` Frame anchored beneath the header that hosts the panel's
  content

The function returns a `ctx` table with `panel`, `body`, a layout
`cursor`, and a `refreshers` array; the caller threads this through the
section/widget helpers.

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
but has no live callers. Modern dropdowns use
`MenuUtil.CreateContextMenu` (12.0+); sliders use `OptionsSliderTemplate`
with hand-laid label/value FontStrings; color swatches drive
`ColorPickerFrame` via `OpenColorPicker`.
