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
`Settings.RegisterAddOnSetting` — that shim was removed in CR-8 (it had
no live callers; the canvas widgets always wrote `db.profile` directly).
Schema rows are rendered by AceGUI primitives:
`CheckBox` for `bool`, `Slider` for `number`, `Dropdown` for `string`
(values supplied as `{ {value=, label=}, ... }` or a function returning
that shape — `Helpers.LSMValues(mediaType)` is the standard wrapper
around LibSharedMedia listings, and `Helpers.AnchorValues()` returns the
canonical 13-option `<SIDE>_<ALIGN>` / `CENTER` set used by both Icons →
Layout → Anchor point and Cast bar → Position → Anchor on primary icon /
Anchor on cast bar), and `ColorPicker` for `color`. The ColorPicker's
confirmation flow is a quirk of WoW 12.0's `SetupColorPickerAndShow` —
KickCD listens to **both** `OnValueChanged` (treats every drag-step as a
commit, giving a live preview) and `OnValueConfirmed` (fires only on
Cancel, with the original color, so the value reverts cleanly). Section
headings are AceGUI `Heading` widgets bumped to `GameFontNormalLarge`.
Two-column rows are produced by wrapping a 50%-width pair into a
Flow-laid `SimpleGroup`; spacers between rows give the airy look. A
schema row tagged `solo = true` is forced onto its own row (left half,
right half empty) so visual pivots like Icons → Border → "Show border"
or Cast bar → Position → "Anchor mode" stand apart from the controls
they govern. See `Helpers.RenderSchema` and the `makeCheckbox` /
`makeSlider` / `makeDropdown` / `makeColorPicker` factories in
`settings/Panel.lua`.

A schema row may declare `valueGate = "<sibling.path>"`. The slash
command's invalid-value error appends `(depends on <gate> = <current>;
flip <gate> to <other> for <other-options>)` so a user typing `/kcd set
castbar.growDirection LEFT` while `castbar.orientation` is `VERTICAL`
learns *why* their value is rejected AND what to flip to enable it. The
dropdown's `values` function should also re-evaluate the option list
against the gate so the panel and CLI stay in lockstep — see
`castbar.growDirection` in `settings/Castbar.lua`.

`Helpers.ValidateSchema()` runs at the top-level category register
(after every settings/* file has loaded its rows) and prints
`|cffff0000KickCD schema error|r:` lines for any row missing a
`path` / unknown `panel` / unknown `section` / unknown `type`. It
doesn't refuse to load on a misshapen row — the panel just won't show
that row — but a diff that adds a typo'd row is now self-flagging
during a /reload.

The ColorPicker's `OnValueChanged` commit is wrapped in
`Util.Throttle(50, ...)` so dragging a color slider doesn't thrash the
bus or the live frames. `OnValueConfirmed` (which only fires on Cancel
under WoW 12.0's `SetupColorPickerAndShow` flow) stays immediate.

The schema-driven panels share a lazy AceGUI `ScrollFrame` patched to
**always** display its scrollbar (`Helpers.PatchAlwaysShowScrollbar`),
even when the content fits. Without the patch, short panels (General)
would render edge-to-edge while long ones (Icons / Cast bar) would gain
a 20 px right-side scrollbar gutter — visually asymmetric. The patch
parks the thumb at the top and greys the scrollbar out when there's
nothing to scroll, but leaves the gutter reserved so every panel's body
content has the same right-edge x-coordinate. The original `FixScroll` /
`MoveScroll` / `OnRelease` are restored when the AceGUI widget pool
recycles the frame, since the pool is shared across addons.

