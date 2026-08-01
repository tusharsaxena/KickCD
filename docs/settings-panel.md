# Settings panel — schema-driven canvas layout

All six tabs (General, Icons, Cast bar, Text Label, Spells, Profiles) are registered as **canvas-layout subcategories** so they share one custom header design:

* `GameFontNormalHuge` title on the left
* `Defaults` button on the right (AceGUI `Button`, which wraps `UIPanelButtonTemplate`) — present on General / Icons / Cast bar / Text Label / Spells, omitted on Profiles. It is **created lazily**, on the panel's first `OnShow`, by `Helpers.EnsureDefaultsButton(panel)`: AceGUI is a shared library and UI skins restyle its widgets by hooking `RegisterAsWidget`, so a widget built during load (when the category is registered) keeps Blizzard's stock red `UI-Panel-Button-Up` art whenever this addon happens to load before the skinner. Builders therefore park the handler as `ctx.panel.defaultsOnClick = fn` (a plain function — `EnsureDefaultsButton` wires it with `:SetCallback("OnClick", …)`, NOT `:SetScript`, since the AceGUI widget object isn't a Blizzard Frame) and call `H.EnsureDefaultsButton(ctx.panel)` as the first statement of the panel's `OnShow`.
* `Options_HorizontalDivider` atlas underneath, full panel width.

The header is built by `Helpers.CreatePanel(name, title, opts)` in `settings/Panel.lua`. It returns a `ctx` table (`{ panel, body, scroll, refreshers, lastGroup, panelKey }`) that the per-tab builder threads through the rest of the layout helpers. `ctx.scroll` is the AceGUI `ScrollFrame` (created lazily on first widget add) that hosts schema widgets; tabs that don't use the schema renderer (Spells / Profiles) parent their own AceGUI containers to `ctx.body` directly and never trigger the lazy scroll.

Every panel ctx is stashed in `NS.Settings._panels` so `Helpers.RefreshAllPanels` can re-sync widgets after a slash-cmd write.

## Per-unit panels (Icons / Cast bar)

Icons and Cast bar render their schema per-unit via `Helpers.RenderUnitPanel(ctx, panelKey, afterGroup)` (`settings/Panel_Render.lua`): a full-width `Unit` dropdown (Target / Focus, from `NS.Units.LIST`) sits above the schema body and re-renders the whole panel (`Helpers.ClearScroll` + re-run) on selection — `ctx.unit` is stashed on the panel ctx so `Helpers.SchemaForPanel(panelKey, ctx.unit)` can filter rows to the selected unit's `units.<unit>.icons.*` / `units.<unit>.castbar.*` paths.

When `ctx.unit == "focus"`, a header row adds a **"Use same styling as Target"** checkbox (`units.focus.link`) and a **"Copy styling from Target"** button (`NS.Units.CopyStyling("target", "focus")`, a one-time deep-copy that also flips `link = false`) — both fire `Ka0s_KickCD_CONFIG_CHANGED{section="units"}` and re-render the panel. While linked, the appearance schema body is hidden entirely (replaced with a "Linked to Target — uncheck to customize." label) rather than shown-but-inert, since any edit there would silently write to a table nothing reads (`NS.Units.Icons("focus")` / `.Castbar("focus")` resolve to `units.target.*` while linked).

General has no unit selector — its only per-unit rows are the two `units.<unit>.enabled` toggles, which render together, tagged with `unit = "target"|"focus"` purely so `RestoreDefaults`/`RestoreAllDefaults` reset both units together. (`label.show` / `label.text` used to live here; they moved to the Text Label panel, which does use the unit selector.)

## `NS.Settings.Schema` is the single source of truth

`settings/General.lua`, `settings/Icons.lua`, and `settings/Castbar.lua` declare every option as a row in a flat array. Each row:

```lua
{
    panel    = "general",                    -- which tab renders it
    section  = "general",                    -- Ka0s_KickCD_CONFIG_CHANGED section
    group    = L["Master controls"],         -- sub-section header text
    path     = "scale",                      -- dotted db.profile path (per-unit rows use
                                             --   "units.<unit>.icons.<field>" etc.)
    unit     = "target"|"focus",             -- optional; tags a row as belonging to one
                                             --   unit for RestoreDefaults grouping.
                                             --   SchemaForPanel(panelKey, ctx.unit) filters
                                             --   Icons/Castbar rows on this
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
| `Defaults` button | `Helpers.RestoreDefaults(panelKey, ctx)` resets every panel row to `def.default`, runs `onChange`, fires per-section `Ka0s_KickCD_CONFIG_CHANGED`, re-runs the panel's refreshers |

**Adding an option = one schema row.** UI widget, slash CLI, and Defaults reset are wired automatically.

A row may declare `solo = true` to be rendered alone in the left half of its own row (visual pivot above the controls it governs — Icons → Border → "Show border", Cast bar → Position → "Anchor mode").

A row may declare `skipRender = true` to stay a full schema row — `/kcd get|set|list`, Defaults reset, validation — while being left out of the automatic `RenderSchema` pass, because the panel builder renders it by hand somewhere specific. The one user today is General's `locked`, which an `afterGroup` callback renders via `Helpers.RenderField(c, H.FindSchema("locked"), row, 0.5)` so it can share a row with the bespoke session-only "Debug console" toggle.

A row may declare `valueGate = "<sibling.path>"` for dropdowns whose option list depends on another setting (the canonical case: cast bar `growDirection`'s `RIGHT`/`LEFT` vs `UP`/`DOWN` options gated on `orientation`). The `values` function should re-evaluate the option list against the gate's current value, and `/kcd set` will surface `(depends on <gate> = <current>; flip <gate> to <other> for <other-options>)` on rejection so a confused user can see why their value was refused AND what to flip to enable it.

The 13-option `<SIDE>_<ALIGN>` / `CENTER` anchor dropdown shared by Icons → Layout → Anchor point and Cast bar → Position → Anchor on primary icon / Anchor on cast bar comes from `Helpers.AnchorValues()`. Both dropdowns must use it so the option lists stay in lockstep when new anchors are added.

## Custom-body tabs (Spells / Profiles)

Spells and Profiles share the unified header but render custom bodies:

* **Spells** — AceGUI editor (class/spec dropdowns, Add spell button, scrollable row list) parented to `ctx.body`. The header `Defaults` button opens the existing `KICKCD_RESET_SPELLS` StaticPopup, which resets only the currently selected class+spec. No schema rows here.
* **Profiles** — AceDBOptions options table rendered into an AceGUI `SimpleGroup` parented to `ctx.body`. `AceConfigDialog:Open("KickCD-Profiles", container)` is called on first show. **No Defaults button** — profile management has its own destructive controls inside the AceDBOptions UI.

## Widget primitives (canvas mode)

All widgets bind directly to `db.profile` via `Helpers.Get(path)` and `Helpers.Set(path, section, value)`. Blizzard's `Settings.RegisterAddOnSetting` shim was deleted in CR-8 — the canvas widgets never went through Blizzard's Setting object lifecycle, so the shim was dead code. Don't reach for it when adding new UI; use the schema + `Helpers.RenderField` instead.

Each widget creator pushes a refresher closure into `ctx.refreshers` so its display can re-sync after a Defaults reset or a slash-cmd `/kcd set`.

### The refresher lifetime rule

**A refresher is valid only while the widget it captures is live, so `Helpers.ClearScroll` wipes `ctx.refreshers` at the same time it calls `ReleaseChildren`.** Every maker registers immediately after `parent:AddChild(...)`, which is what makes the wholesale wipe safe — no entry in the registry belongs to a widget outside the scroll. If you ever add a refresher for a persistent widget, it must **not** live in `ctx.refreshers`.

Getting this wrong is not a leak, it is corruption. AceGUI's pool recycles the *same widget objects* into whatever the next render creates, so a closure that outlives its widget doesn't quietly no-op — it writes its old row's value and dropdown list onto an unrelated widget. That shipped once: the **Unit** dropdown rendered anchor-point values on Icons and text-position values on Cast bar, because a stale anchor/position refresher fired against the recycled object now serving as the unit selector.

It reproduces through ordinary use, since `Helpers.RenderUnitPanel` clears and rebuilds on every unit switch, "Use same styling as Target" tick, and "Copy styling from Target" press — then any `/kcd set` runs `RefreshAllPanels` and fires the whole registry. Guarded by `tests/test_settings_refreshers.lua`.

Schema widgets are AceGUI primitives:

- `CheckBox` for `bool`
- `Slider` for `number` — **unless** the row also declares a `values` list. As of OptionsWidgets minor 5 the library reads that shape as a constrained enum, not a range, and renders it as a `Dropdown` (matching what `LibKa0s-Slash-1.0` has always parsed it as). No row in this addon is a `number` carrying `values` today, so no widget here changed; a new one would draw as a dropdown, not a 0-to-1 slider.
- `Dropdown` for `string` rows that declare a `values` list (fixed-choice), or a function returning one. This addon supplies the **key-map** shape — `{ TOP_LEFT = "Top left", ... }` — paired with an explicit `sorting` array where the order matters, because alphabetising an anchor list scrambles it. `Helpers.LSMValues(mediaType)` is the standard wrapper around LibSharedMedia listings, and `Helpers.AnchorValues()` returns the canonical 13-option `<SIDE>_<ALIGN>` / `CENTER` set. As of OptionsWidgets minor 4 the library also reads an **ordered array** of `{ value =, text = }`; either shape works, and note the key is `text` — never `label`.
- `EditBox` (`makeEditBox`) for `string` rows with NO `values` list — free text, e.g. the per-unit `label.text` caption rows. Commits on `OnEnterPressed` (Enter / focus-loss), unlike the drag/click-commit widgets above, so a half-typed label never writes a partial string to `db.profile`. `Helpers.RenderField` dispatches `type == "string"` to `makeDropdown` when `def.values` is set, `makeEditBox` otherwise.
- `ColorPicker` for `color`
- `Heading` (bumped to `GameFontNormalLarge`) for sections

Non-schema action rows are built by `Helpers.InlinePair` (two half-width widgets sharing one Flow row — General's "Lock frame" checkbox beside the session-only "Debug console" toggle) and `Helpers.InlineButtonPair` (two 50/50 `Button`s — "Reset position" beside "Reset all settings").

Paired into 50%/50% Flow rows inside a single AceGUI `ScrollFrame` per tab (see `Helpers.RenderSchema`). Spacers between rows give the airy look. Two-column rows are produced by wrapping a 50%-width pair into a Flow-laid `SimpleGroup`. A schema row tagged `solo = true` is forced onto its own row (left half, right half empty).

LSM-backed dropdowns (`borderTexture`, `statusBarTexture`, font rows) carry an `lsm = "<media-type>"` field so `makeDropdown` swaps the stock `Dropdown` widget for the matching `LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` widget from the vendored upstream `libs/AceGUI-3.0-SharedMediaWidgets/` (r65, multi-file under `widget.xml`). Statusbar and Font show an inline closed-state preview (the bar texture / the font's `Aa` glyphs); Border's 42×42 `displayButton` preview tile is suppressed by `core/LSMPatch.lua` (a PLAYER_LOGIN constructor wrapper) so the closed Border row is text-only and aligned with neighbouring sliders. The popup hover-preview pane (upstream's `ContentOnEnter` swaps the popup backdrop's `edgeFile` to the hovered border) is unaffected. The widget types share the `SetLabel` / `SetList(items, order)` / `SetValue` / `OnValueChanged` interface with the stock `Dropdown`, so the rest of `makeDropdown` is unchanged either way.

This matches the visual style of AceConfig-driven addons (e.g. Consumable Master) and keeps every widget on the `Helpers.Set` / `Helpers.Get` data path. The slider's editbox is left to AceGUI's default formatter (integer step → integer text, float step → 2-decimal text); unit hints (`px`, `×`) belong in `def.label`, not appended to the value. `def.fmt` is still consulted by `/kcd get|list` slash output where text-only context benefits from a `"48 px"` / `"1.50x"` rendering.

## Deferred render

Schema rendering is **deferred to the panel's `OnShow`** because at build time (`PLAYER_LOGIN`) `ctx.body` has zero width and AceGUI's List-layout pass against the AceGUI `ScrollFrame` would size every fullwidth child to zero. See the `local rendered = false; OnShow{...}` guard in `settings/General.lua`, `settings/Icons.lua`, and `settings/Castbar.lua`.

## ColorPicker

The ColorPicker's confirmation flow is a quirk of WoW 12.0's `SetupColorPickerAndShow` — KickCD listens to **both** `OnValueChanged` (treats every drag-step as a commit, giving a live preview) and `OnValueConfirmed` (fires only on Cancel, with the original color, so the value reverts cleanly).

The `OnValueChanged` commit is wrapped in `Util.Throttle(50, ...)` so dragging a color slider fires `Ka0s_KickCD_CONFIG_CHANGED` at most ~20 times/sec instead of every render frame. Without it the live cast bar / icon grid would re-skin per-frame during a drag, jankily on slower systems. `OnValueConfirmed` (which only fires on Cancel under WoW 12.0's flow) stays immediate so the snap-back is instantaneous.

## Always-visible scrollbar

The schema-driven panels share a lazy AceGUI `ScrollFrame` patched to **always** display its scrollbar (`Helpers.PatchAlwaysShowScrollbar`), even when the content fits. Without the patch, short panels (General) would render edge-to-edge while long ones (Icons / Cast bar) would gain a 20 px right-side scrollbar gutter — visually asymmetric. The patch parks the thumb at the top and greys the scrollbar out when there's nothing to scroll, but leaves the gutter reserved so every panel's body content has the same right-edge x-coordinate. The original `FixScroll` / `MoveScroll` / `OnRelease` are restored when the AceGUI widget pool recycles the frame, since the pool is shared across addons.

## Schema validation

`Helpers.ValidateSchema()` runs at panel-register time and asserts every schema row has a non-empty `path`, a known `panel` (`general` / `icons` / `castbar` / `label` / `spells` / `profiles`), a known `section` (`general` / `icons` / `castbar` / `label` / `spells` / `units` / `debug`), and a known `type` (`bool` / `number` / `string` / `color`). `debug` remains a valid `section` enum, but no shipped row uses it — debug is session-only (`NS.State.debug`, toggled via the console header button or `/kcd debug on|off|toggle`), never persisted and never a schema row. Failures print a schema-error line (the printer prefixes with the shared `NS.PREFIX`) per offending row but don't refuse to load — diagnostic guard rail for future contributors, not a hard gate. A diff that adds a typo'd row is now self-flagging during a /reload.

## Reset helpers

The General tab's "Reset all settings" button (under Master controls) funnels through `Helpers.ResetAll`, which calls, in order: `Helpers.RestoreAllDefaults` (loops over every schema-driven panel: general / icons / castbar / label), `Helpers.ResetAllPositions` (restores every unit's icon-grid and cast-bar anchor, since positions aren't schema rows), `Helpers.RestoreUnitLinks` (restores each unit's `link` flag — target=false, focus=true — which is also not a schema row, so `RestoreAllDefaults` can't reach it), **and** `Database:ResetAllSpells` (rebuilds every spec's spell list from `NS.DefaultSpells`). The slash command `/kcd resetall` shares this same helper — the popup and the CLI cannot diverge. Profiles are intentionally skipped because the AceDBOptions UI has its own destructive controls and resetting them would delete user data.

`Helpers.ResetIconPosition` is the corresponding helper for the "Reset position" button and `/kcd resetposition` — it writes `db.profile.units.target.anchors.icons` from `NS.DEFAULT_PROFILE.units.target.anchors.icons` so the default coordinates live in one place. It is TARGET-only by design — both are legacy "reset the grid" affordances that predate focus tracking, so a focus position reset is intentionally out of scope for them (focus already gets its own distinct default screen offset, and unlike target it can also be re-derived via "Copy styling from Target"). It fires `Ka0s_KickCD_CONFIG_CHANGED { section = "general" }` only — IconGrid's `general` branch already re-anchors every enabled unit's grid from its own anchor, and firing `icons` would just be a wasted relayout.
