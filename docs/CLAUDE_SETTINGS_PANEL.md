# Settings panel — schema-driven canvas layout

All five tabs (General, Icons, Cast bar, Spells, Profiles) are
registered as **canvas-layout subcategories** so they share one custom
header design:

* `GameFontNormalHuge` title on the left
* `Defaults` button on the right (AceGUI `Button`, which wraps
  `UIPanelButtonTemplate`) — present on General / Icons / Cast bar /
  Spells, omitted on Profiles. Wire its handler with
  `ctx.panel.defaultsBtn:SetCallback("OnClick", fn)` (NOT `:SetScript`,
  since the AceGUI widget object isn't a Blizzard Frame).
* `Options_HorizontalDivider` atlas underneath, full panel width

The header is built by `Helpers.CreatePanel(name, title, opts)` in
`settings/Panel.lua`. It returns a `ctx` table (`{ panel, body, scroll,
refreshers, lastGroup, panelKey }`) that the per-tab builder threads
through the rest of the layout helpers. `ctx.scroll` is the AceGUI
`ScrollFrame` (created lazily on first widget add) that hosts schema
widgets; tabs that don't use the schema renderer (Spells / Profiles)
parent their own AceGUI containers to `ctx.body` directly and never
trigger the lazy scroll.

## `KickCD.Settings.Schema` is the single source of truth

`settings/General.lua`, `settings/Icons.lua`, and `settings/Castbar.lua`
declare every option as a row in a flat array. Each row:

```lua
{
    panel    = "general",                    -- which tab renders it
    section  = "general",                    -- KickCD_CONFIG_CHANGED section
    group    = L["Master controls"],         -- sub-section header text
    path     = "scale",                      -- dotted db.profile path
    type     = "bool"|"number"|"string"|"color",
    label    = L["Master scale"],
    tooltip  = L["..."],
    default  = 1.0,
    min, max, step, fmt,                     -- numbers
    values   = { { value=, label= }, ... },  -- strings (dropdown)
    onChange = function(v) ... end,          -- optional side-effect hook
}
```

The same schema feeds:

* `Helpers.RenderSchema(ctx, panelKey)` — builds `Section` headers per
  `group` and dispatches to `RenderField` per `type` (`makeCheckbox` /
  `makeSlider` / `makeDropdown` / `makeColorPicker`).
* The `/kcd list | get <path> | set <path> <value>` slash commands in
  `core/KickCD.lua` — they look up the schema by path, parse and clamp
  the value by type, write through `Helpers.Set`, run `onChange`, and
  call `Helpers.RefreshAllPanels()` so any open panel re-syncs.
* The per-panel `Defaults` button — `Helpers.RestoreDefaults(panelKey,
  ctx)` resets every entry of that panel back to its `default`, runs
  `onChange`, fires per-section `KickCD_CONFIG_CHANGED`, and re-runs
  the panel's refreshers.

**Adding a new setting = one row in the schema.** UI widget, slash
get/set, and Defaults reset are wired automatically.

A row may declare `solo = true` to be rendered alone in the left half
of its own row (visual pivot above the controls it governs — Icons →
Border → "Show border", Cast bar → Position → "Anchor mode").

A row may declare `valueGate = "<sibling.path>"` for dropdowns whose
option list depends on another setting (the canonical case: cast bar
`growDirection`'s `RIGHT`/`LEFT` vs `UP`/`DOWN` options gated on
`orientation`). The `values` function should re-evaluate the option
list against the gate's current value, and `/kcd set` will surface
`(depends on <gate> = <current>)` on rejection so a confused user can
see why their value was refused.

The 13-option `<SIDE>_<ALIGN>` / `CENTER` anchor dropdown shared by
Icons → Layout → Anchor point and Cast bar → Position → Anchor on
primary icon / Anchor on cast bar comes from `Helpers.AnchorValues()`.
Both dropdowns must use it so the option lists stay in lockstep when
new anchors are added.

## Custom panel bodies (Spells / Profiles)

Spells and Profiles share the unified header but render custom bodies:

* **Spells** — AceGUI editor (class/spec dropdowns, Add spell button,
  scrollable row list) parented to `ctx.body`. The header `Defaults`
  button opens the existing `KICKCD_RESET_SPELLS` StaticPopup, which
  resets only the currently selected class+spec. No schema rows here.
* **Profiles** — AceDBOptions options table rendered into an AceGUI
  `SimpleGroup` parented to `ctx.body`. `AceConfigDialog:Open(
  "KickCD-Profiles", container)` is called on first show. **No
  Defaults button** — profile management has its own destructive
  controls inside the AceDBOptions UI.

## Widget primitives (canvas mode)

All widgets bind directly to `db.profile` via `Helpers.Get(path)` and
`Helpers.Set(path, section, value)`. Blizzard's `Settings.RegisterAddOnSetting`
shim was deleted in CR-8 — the canvas widgets never went through Blizzard's
Setting object lifecycle, so the shim was dead code. Don't reach for it
when adding new UI; use the schema + `Helpers.RenderField` instead.

Each widget creator pushes a refresher closure into `ctx.refreshers` so its
display can re-sync after a Defaults reset or a slash-cmd `/kcd set`.

Schema widgets are AceGUI widgets — `CheckBox`, `Slider`, `Dropdown`,
`ColorPicker`, `Heading` for sections, `Button` + `Label` inside a
`SimpleGroup` for inline action rows — paired into 50%/50% Flow rows
inside a single AceGUI `ScrollFrame` per tab (see
`Helpers.RenderSchema`). LSM-backed dropdowns (`borderTexture`,
`statusBarTexture`, font rows) carry an `lsm = "<media-type>"` field so
`makeDropdown` swaps the stock `Dropdown` widget for the matching
`LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` widget from
`libs/AceGUI-3.0-SharedMediaWidgets/widget.lua` — that gives each row
an inline preview swatch (texture / edge style / font face). The two
widget types share the `SetLabel` / `SetList(items, order)` /
`SetValue` / `OnValueChanged` interface, so the rest of `makeDropdown`
is unchanged either way.

This matches the visual style of
AceConfig-driven addons (e.g. Consumable Master) and keeps every widget
on the `Helpers.Set` / `Helpers.Get` data path. The slider's editbox is
left to AceGUI's default formatter (integer step → integer text, float
step → 2-decimal text); unit hints (`px`, `×`) belong in `def.label`,
not appended to the value. `def.fmt` is still consulted by `/kcd
get|list` slash output where text-only context benefits from a
`"48 px"` / `"1.50x"` rendering.

Schema rendering is **deferred to the panel's `OnShow`** because at
build time (PLAYER_LOGIN) `ctx.body` has zero width and AceGUI's
List-layout pass against the AceGUI `ScrollFrame` would size every
fullwidth child to zero. See the `local rendered = false; OnShow{...}`
guard in `settings/General.lua`, `settings/Icons.lua`, and
`settings/Castbar.lua`.

The General tab's "Reset all settings" button (under Master controls)
funnels through `Helpers.ResetAll`, which calls
`Helpers.RestoreAllDefaults` (loops over every schema-driven panel:
general / icons / castbar) **and** `Database:ResetAllSpells` (rebuilds
every spec's spell list from `KickCD.DefaultSpells`). The slash command
`/kcd resetall` shares this same helper — the popup and the CLI cannot
diverge. Profiles are intentionally skipped because the AceDBOptions UI
has its own destructive controls and resetting them would delete user
data.

`Helpers.ResetIconPosition` is the corresponding helper for the
"Reset position" button and `/kcd resetposition` — it writes
`db.profile.anchors.icons` from `KickCD.DEFAULT_PROFILE.anchors.icons`
so the default coordinates live in one place. It fires
`KickCD_CONFIG_CHANGED { section = "general" }` only — IconGrid's
`general` branch already re-anchors, and firing `icons` would just be
a wasted relayout.

## Schema validation

`Helpers.ValidateSchema()` runs at panel-register time and asserts every
schema row has a non-empty `path`, a known `panel` (`general` / `icons` /
`castbar` / `spells` / `profiles`), a known `section` (`general` / `icons`
/ `castbar` / `spells` / `debug`), and a known `type` (`bool` / `number`
/ `string` / `color`). Failures print a `|cffff0000KickCD schema error|r:`
line per offending row but don't refuse to load — diagnostic guard rail
for future contributors, not a hard gate.

## ColorPicker writes are throttled

`makeColorPicker`'s `OnValueChanged` commit goes through `Util.Throttle(50,
...)` so dragging a color slider fires `KickCD_CONFIG_CHANGED` at most ~20
times/sec instead of every render frame. Without it the live cast bar /
icon grid would re-skin per-frame during a drag, jankily on slower
systems. `OnValueConfirmed` (which fires only on Cancel — a 12.0 quirk of
`SetupColorPickerAndShow`) is left immediate so the snap-back is
instantaneous.

