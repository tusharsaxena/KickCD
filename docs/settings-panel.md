# Settings panel — schema-driven canvas layout

All five tabs (General, Icons, Cast bar, Spells, Profiles) are registered as **canvas-layout subcategories** so they share one custom header design:

* `GameFontNormalHuge` title on the left
* `Defaults` button on the right (AceGUI `Button`, which wraps `UIPanelButtonTemplate`) — present on General / Icons / Cast bar / Spells, omitted on Profiles. Wire its handler with `ctx.panel.defaultsBtn:SetCallback("OnClick", fn)` (NOT `:SetScript`, since the AceGUI widget object isn't a Blizzard Frame).
* `Options_HorizontalDivider` atlas underneath, full panel width.

The header is built by `Helpers.CreatePanel(name, title, opts)` in `settings/Panel.lua`. It returns a `ctx` table (`{ panel, body, scroll, refreshers, lastGroup, panelKey }`) that the per-tab builder threads through the rest of the layout helpers. `ctx.scroll` is the AceGUI `ScrollFrame` (created lazily on first widget add) that hosts schema widgets; tabs that don't use the schema renderer (Spells / Profiles) parent their own AceGUI containers to `ctx.body` directly and never trigger the lazy scroll.

Every panel ctx is stashed in `KickCD.Settings._panels` so `Helpers.RefreshAllPanels` can re-sync widgets after a slash-cmd write.

## `KickCD.Settings.Schema` is the single source of truth

`settings/General.lua`, `settings/Icons.lua`, and `settings/Castbar.lua` declare every option as a row in a flat array. Each row:

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
    values   = { { value=, label= }, ... },  -- strings (dropdown); array or fn
    onChange = function(v) ... end,          -- optional side-effect hook
}
```

`type ∈ { bool, number, string, color }`. The same row drives:

| Surface | How |
|---|---|
| Panel widget | `Helpers.RenderField(ctx, def)` dispatches by type to `makeCheckbox` / `makeSlider` / `makeDropdown` / `makeColorPicker`; each registers a refresher closure on `ctx.refreshers` |
| `/kcd list` | Groups schema by `panel`, prints `path = formattedValue` |
| `/kcd get <path>` | `Helpers.FindSchema(path)` + `formatValue` |
| `/kcd set <path> <value>` | Type-aware parse (clamp numbers, validate dropdown values, parse `r g b [a]` for colors) → `Helpers.Set` → `onChange` → `Helpers.RefreshAllPanels` |
| `Defaults` button | `Helpers.RestoreDefaults(panelKey, ctx)` resets every panel row to `def.default`, runs `onChange`, fires per-section `KickCD_CONFIG_CHANGED`, re-runs the panel's refreshers |

**Adding an option = one schema row.** UI widget, slash CLI, and Defaults reset are wired automatically.

A row may declare `solo = true` to be rendered alone in the left half of its own row (visual pivot above the controls it governs — Icons → Border → "Show border", Cast bar → Position → "Anchor mode").

A row may declare `valueGate = "<sibling.path>"` for dropdowns whose option list depends on another setting (the canonical case: cast bar `growDirection`'s `RIGHT`/`LEFT` vs `UP`/`DOWN` options gated on `orientation`). The `values` function should re-evaluate the option list against the gate's current value, and `/kcd set` will surface `(depends on <gate> = <current>; flip <gate> to <other> for <other-options>)` on rejection so a confused user can see why their value was refused AND what to flip to enable it.

The 13-option `<SIDE>_<ALIGN>` / `CENTER` anchor dropdown shared by Icons → Layout → Anchor point and Cast bar → Position → Anchor on primary icon / Anchor on cast bar comes from `Helpers.AnchorValues()`. Both dropdowns must use it so the option lists stay in lockstep when new anchors are added.

## Custom-body tabs (Spells / Profiles)

Spells and Profiles share the unified header but render custom bodies:

* **Spells** — AceGUI editor (class/spec dropdowns, Add spell button, scrollable row list) parented to `ctx.body`. The header `Defaults` button opens the existing `KICKCD_RESET_SPELLS` StaticPopup, which resets only the currently selected class+spec. No schema rows here.
* **Profiles** — AceDBOptions options table rendered into an AceGUI `SimpleGroup` parented to `ctx.body`. `AceConfigDialog:Open("KickCD-Profiles", container)` is called on first show. **No Defaults button** — profile management has its own destructive controls inside the AceDBOptions UI.

## Widget primitives (canvas mode)

All widgets bind directly to `db.profile` via `Helpers.Get(path)` and `Helpers.Set(path, section, value)`. Blizzard's `Settings.RegisterAddOnSetting` shim was deleted in CR-8 — the canvas widgets never went through Blizzard's Setting object lifecycle, so the shim was dead code. Don't reach for it when adding new UI; use the schema + `Helpers.RenderField` instead.

Each widget creator pushes a refresher closure into `ctx.refreshers` so its display can re-sync after a Defaults reset or a slash-cmd `/kcd set`.

Schema widgets are AceGUI primitives:

- `CheckBox` for `bool`
- `Slider` for `number`
- `Dropdown` for `string` (values supplied as `{ {value=, label=}, ... }` or a function returning that shape — `Helpers.LSMValues(mediaType)` is the standard wrapper around LibSharedMedia listings, and `Helpers.AnchorValues()` returns the canonical 13-option `<SIDE>_<ALIGN>` / `CENTER` set)
- `ColorPicker` for `color`
- `Heading` (bumped to `GameFontNormalLarge`) for sections
- `Button` + `Label` inside a `SimpleGroup` for inline action rows

Paired into 50%/50% Flow rows inside a single AceGUI `ScrollFrame` per tab (see `Helpers.RenderSchema`). Spacers between rows give the airy look. Two-column rows are produced by wrapping a 50%-width pair into a Flow-laid `SimpleGroup`. A schema row tagged `solo = true` is forced onto its own row (left half, right half empty).

LSM-backed dropdowns (`borderTexture`, `statusBarTexture`, font rows) carry an `lsm = "<media-type>"` field so `makeDropdown` swaps the stock `Dropdown` widget for the matching `LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` widget from `libs/AceGUI-3.0-SharedMediaWidgets/widget.lua` — that gives each row an inline preview swatch (texture / edge style / font face). The two widget types share the `SetLabel` / `SetList(items, order)` / `SetValue` / `OnValueChanged` interface, so the rest of `makeDropdown` is unchanged either way.

This matches the visual style of AceConfig-driven addons (e.g. Consumable Master) and keeps every widget on the `Helpers.Set` / `Helpers.Get` data path. The slider's editbox is left to AceGUI's default formatter (integer step → integer text, float step → 2-decimal text); unit hints (`px`, `×`) belong in `def.label`, not appended to the value. `def.fmt` is still consulted by `/kcd get|list` slash output where text-only context benefits from a `"48 px"` / `"1.50x"` rendering.

## Deferred render

Schema rendering is **deferred to the panel's `OnShow`** because at build time (`PLAYER_LOGIN`) `ctx.body` has zero width and AceGUI's List-layout pass against the AceGUI `ScrollFrame` would size every fullwidth child to zero. See the `local rendered = false; OnShow{...}` guard in `settings/General.lua`, `settings/Icons.lua`, and `settings/Castbar.lua`.

## ColorPicker

The ColorPicker's confirmation flow is a quirk of WoW 12.0's `SetupColorPickerAndShow` — KickCD listens to **both** `OnValueChanged` (treats every drag-step as a commit, giving a live preview) and `OnValueConfirmed` (fires only on Cancel, with the original color, so the value reverts cleanly).

The `OnValueChanged` commit is wrapped in `Util.Throttle(50, ...)` so dragging a color slider fires `KickCD_CONFIG_CHANGED` at most ~20 times/sec instead of every render frame. Without it the live cast bar / icon grid would re-skin per-frame during a drag, jankily on slower systems. `OnValueConfirmed` (which only fires on Cancel under WoW 12.0's flow) stays immediate so the snap-back is instantaneous.

## Always-visible scrollbar

The schema-driven panels share a lazy AceGUI `ScrollFrame` patched to **always** display its scrollbar (`Helpers.PatchAlwaysShowScrollbar`), even when the content fits. Without the patch, short panels (General) would render edge-to-edge while long ones (Icons / Cast bar) would gain a 20 px right-side scrollbar gutter — visually asymmetric. The patch parks the thumb at the top and greys the scrollbar out when there's nothing to scroll, but leaves the gutter reserved so every panel's body content has the same right-edge x-coordinate. The original `FixScroll` / `MoveScroll` / `OnRelease` are restored when the AceGUI widget pool recycles the frame, since the pool is shared across addons.

## Schema validation

`Helpers.ValidateSchema()` runs at panel-register time and asserts every schema row has a non-empty `path`, a known `panel` (`general` / `icons` / `castbar` / `spells` / `profiles`), a known `section` (`general` / `icons` / `castbar` / `spells` / `debug`), and a known `type` (`bool` / `number` / `string` / `color`). Failures print a `|cffff0000KickCD schema error|r:` line per offending row but don't refuse to load — diagnostic guard rail for future contributors, not a hard gate. A diff that adds a typo'd row is now self-flagging during a /reload.

## Reset helpers

The General tab's "Reset all settings" button (under Master controls) funnels through `Helpers.ResetAll`, which calls `Helpers.RestoreAllDefaults` (loops over every schema-driven panel: general / icons / castbar) **and** `Database:ResetAllSpells` (rebuilds every spec's spell list from `KickCD.DefaultSpells`). The slash command `/kcd resetall` shares this same helper — the popup and the CLI cannot diverge. Profiles are intentionally skipped because the AceDBOptions UI has its own destructive controls and resetting them would delete user data.

`Helpers.ResetIconPosition` is the corresponding helper for the "Reset position" button and `/kcd resetposition` — it writes `db.profile.anchors.icons` from `KickCD.DEFAULT_PROFILE.anchors.icons` so the default coordinates live in one place. It fires `KickCD_CONFIG_CHANGED { section = "general" }` only — IconGrid's `general` branch already re-anchors, and firing `icons` would just be a wasted relayout.
