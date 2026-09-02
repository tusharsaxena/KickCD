# Settings panel — schema-driven canvas layout

## The tab strip

**Every page draws a strip** (`options-ui-§13`). It is not a size threshold and not a choice: a Ka0s page has a strip, so a player who has learned one page has learned all of them. For the four schema-driven pages the strip is partitioned from the rows themselves — one tab per distinct `group`, **in declaration order**, with no second list naming the tabs. So the schema array's order *is* the strip's order, and a group's rows must stay **contiguous**: a row filed under a group the array has already left prints that tab a second time further down.

A page with exactly **one** section draws a **one-tab** strip. That is the library's behaviour as of `OptionsWidgets` minor 13 — the `#groups < 2` fallback to `RenderSchema` is gone — and it is why the Spells page, which has no schema rows at all, draws its single tab by hand.

**Every row carries a `group`.** A page whose rows declare none cannot draw a strip; the library reports the page by key through the descriptor's `print` and renders it untabbed, and the missing `group` is the defect (anti-pattern #69). Pinned by a loop over `allRows()` in `tests/test_schema.lua`.

| Page | Tabs, in strip order (rows per tab) | Rows |
|---|---|---|
| **General** | Master controls (6) \| Units (2) | 8 |
| **Icons** | Sizing (4) \| Layout (6) \| Visual states (5) \| Border (5) \| Annotations (11) \| Ready glow (8) | 39 per unit |
| **Cast bar** | General (5) \| Size and position (7) \| Icon (2) \| Font (6) \| Spell name (5) \| Cast time (4) \| Interruptible (13) \| Non-interruptible (13) | 55 per unit |
| **Text Label** | General (2) \| Placement (8) \| Font (6) | 16 per unit |
| **Spells** | Spell list (1 tab, hand-drawn — the page has no schema rows) | — |
| **Profiles** | **no strip** — AceDBOptions draws the whole page, so it never reaches the flow engine | — |

Counts are **per unit** on the three unit-scoped pages, because that is what a reader sees: the page renders only the unit its banner names. General has no unit picker, so its Units tab shows both units' toggles.

**Two pages are exempt, and both are exempt for the same reason** — the host does not render them through the flow engine. They are the **Profiles** sub-page (`options-ui-§3`, AceConfigDialog draws it whole) and the **landing page** (`options-ui-§5`, whose body is this addon's own `buildMain`: the logo, the tagline, a *Slash Commands* heading and one Label per `COMMANDS` row). The landing page declares no `group` and names no sections, so there is nothing for a strip to be a strip of; its untabbed `Heading` form is its mandated rendering, not a deviation.

The table is pinned by `tests/test_schema.lua`, which asserts the strip order, the per-tab counts, that no group's rows resume after the page has left it, that every row anywhere carries a `group`, and that Target and Focus partition identically.

### Cast bar: what moved, and why

The **General** tab held nine rows and four of them were two other subjects wearing its name. The two size sliders (`width`, `height`) moved onto the tab that already held the bar's placement — renamed **Size and position**, because that is what it now answers — and the two icon rows (`iconPosition`, `iconSize`) became a tab of their own, **Icon**: the spell icon is a piece of the bar you can switch off entirely, not a property of the bar's geometry.

Renaming a group **detaches any `afterGroup` hook on it**, because the group name *is* the hook key and nothing errors when it stops matching. This page renders through `Helpers.RenderUnitPanel` with no `afterGroup` at all, so there was nothing to re-key — but the rule is why the rename is called out here rather than left to the diff.

### Subsection headings

**A tab that mixes kinds of control breaks them up with subsection headings** (`options-ui-§7`), declared by the row's `subgroup` field and drawn through `H.Section` whenever it changes within a group. Unlike the section heading — which the tab label already carries and which is therefore suppressed — a subsection heading is **not** suppressed. A `subgroup` names the KIND of control and never repeats its tab's own name.

| Tab | Subsections |
|---|---|
| Icons → Annotations | Icon · Font · Charges |
| Cast bar → Size and position | Size · Position |
| Cast bar → Interruptible / Non-interruptible | Bar · Background · Text · Border |

There are no hand-rolled headings anywhere — a coloured full-width `Label` standing in for a `Heading` is anti-pattern #71, and `tests/test_schema.lua` scans `settings/` for the gold it would be written in.

**Every other tab is one subject, and that is a recorded decision rather than an omission.** `tests/test_schema.lua` classifies **every** tab on every page into one of two tables — `TAB_MIXED`, whose rows must *all* carry a `subgroup`, and `TAB_SINGLE_SUBJECT`, whose rows must carry *none* — reading the tab list off the live schema, so a tab added later belongs to neither and fails until somebody decides which it is. The earlier gate was a literal list of the four mixed tabs, which asserted nothing about a tab not on it; a new bare mixed tab passed in silence. Each single-subject entry carries its reason, and the two closest calls are worth naming here:

* **Icons → Visual states** — ready alpha, cooldown alpha, the cooldown tint and the GCD sub-state's swipe toggle. The sliders and the swatch are not two *kinds* of control on this tab; they are two channels of one answer to *what does this icon look like right now*, which is the tab's entire question. Headings would read *Opacity* / *Tint* over two rows each and name properties of one subject rather than subjects beside it.
* **Icons → Ready glow** — one effect declared twice because there are two icon slots: trigger, style and colour for the primary icon and for the secondary. Every row's label already says *glow*, and *Trigger* / *Style* / *Colour* headings would name the glow's properties, not a second subject.

Both would be legitimate `subgroup` candidates on a reading of §7 that counts widget types rather than subjects. They are bare on purpose, and the purpose is written down where the gate can be read beside it.

## Master controls — the canonical tab (`options-ui-§15`)

The **General** page's first tab is named exactly `Master controls`, and **KickCD is the collection's reference implementation of it**: eight sibling addons copy the shape below, so changing it here changes it everywhere.

It is **composed, not written out**. `H.MasterControls` (`libs/LibKa0s/OptionsCompose.lua`) emits the canonical set from one declaration and returns **two** values — the rows, and the `afterGroup` that draws the tab's closing button pair:

| | |
|---|---|
| Enable KickCD | General visibility |
| Master scale | Master alpha |
| Lock frame | Debug console |
| Reset position | Reset all settings |

The two resets are a **button pair**, not rows: they are acts rather than settings, so they belong in neither the CLI nor the reset sweep. The pair is wired as `H.RenderTabbedSchema(ctx, "general", { [H.MASTER_GROUP] = masterTail }, …)` — and because **the group name is the hook key**, renaming the group detaches the hook and nothing says so.

Two things about this tab are this addon's rather than the composer's:

* **`visibility` keeps its own four values.** KickCD's visibility is cast-state driven — *when target is casting an interruptible spell* is the mode the whole addon exists for — and the canonical `Always / Only in combat / Only out of combat / Never` cannot express it. Only the option list and its prose differ; the stored keys are untouched, so nothing migrates. Recorded as a ratified deviation in [ARCHITECTURE.md](ARCHITECTURE.md#documented-deviations).
* **`state.debugConsole` resolves outside the profile.** It is the composer's session-only row, and its path names a live object rather than a saved key, so `settings/Panel.lua`'s `SESSION_PATHS` table answers it off `NS.DebugLog` inside `Helpers.Get`/`Set`. `debug-logging-§5` still holds — nothing about the console ever reaches SavedVariables — and `/kcd get|set|list state.debugConsole` now works, which the bespoke `SessionToggle` it replaced never allowed.

## The composed control groups (`options-ui-§16`)

Font, border and bar blocks are **emitted by the library**, never typed out — a hand-written copy is anti-pattern #73. Each composer returns an array of ordinary schema rows, so `rowsForPage`, `applyDefault`, `RestoreDefaults`, the CLI and the reset sweep all keep working with nothing added to them. `Helpers.AddComposed(rows, stamp)` (`settings/Panel.lua`) stamps this addon's own `panel` / `section` / `unit` onto what comes back and appends it in declaration order.

| Composer | Emits | Used by |
|---|---|---|
| `H.FontGroup` | Font · Font size · Font color · Use class color · Font flags · Font shadow | Icons → Annotations, Cast bar → Font, Text Label → Font |
| `H.BorderGroup` | *(Show border)* · Border style · Border thickness (px) · Border color · Use class color | Icons → Border, Cast bar → Interruptible / Non-interruptible |
| `H.BarGroup` | Bar texture · Bar opacity · Bar color · Use class color | Cast bar → Interruptible / Non-interruptible |
| `H.ColorPair` | a swatch and its companion, and nothing else | the cooldown tint, the two glow colors, both background swatches, both spell-name swatches |
| `H.MasterControls` | the **six** canonical rows above, plus the button-pair hook that draws the other two | General → Master controls |

**`keys` and `defaults` are what keep the stored shape this addon's.** Every composer call passes the leaf names this addon already shipped — `borderStyle` → `borderTexture`, `fontSize` → `size` on the label, `fontColor` → `textColor` on the cast bar — so the composer changes what is *declared* and how it is *laid out*, never what is *stored*.

Rows a composer does not emit but this addon legitimately has go in `spec.extra` and are appended **after** the mandated block, never interleaved.

**A group over a background is not a bar group.** The cast bar's `bgColor` is a `SetColorTexture` with no fill, so it takes the swatch and its companion and nothing else — inventing a texture picker for a surface with no texture is a control wired to nothing.

### What the composers added that this addon did not have

| Setting | Honored at |
|---|---|
| `units.<unit>.icons.cooldownTextColor` + companion | `modules/IconGrid_Render.lua` → `Icon:ApplyTextConfig` |
| `units.<unit>.icons.cooldownTextShadow` | same |
| `units.<unit>.castbar.textColor` + companion (the **cast time** text) | `modules/Castbar_Skin.lua` → `ReskinColors` |
| `units.<unit>.castbar.fontShadow` | `modules/Castbar_Skin.lua` → `applyLabelFonts` (and in the structure signature, or a toggle would never take effect) |
| `units.<unit>.castbar.<state>.barAlpha` | `modules/Castbar.lua` → `ApplyState`, folded into the per-state alpha curve |
| `units.<unit>.label.style.shadow` | `modules/UnitLabel.lua` → `applyLabelFont` |
| **fifteen** `useClassColor*` companions per unit | see below |

The cast bar's new colour governs the **cast time** text, and is labelled *Cast time color* for that reason. The spell name keeps its two per-state `nameTextColor` swatches: the choice between them is a curve evaluation on a possibly-secret flag, so a third writer over the same `FontString` would simply lose to them.

## The class-colour companion (`options-ui-§17`)

**Every colour picker carries a `Use class color` checkbox immediately to its right**, and the composers set `startsLine` on the swatch so an odd number of widgets above the pair can never split it across two lines. Thirty swatches, fifteen per unit, every one of them paired.

Resolution goes through **one** resolver — `NS.ResolveColor` (`core/CoreSetup.lua`, handed over from `LibKa0s-Core-1.0`) — which owns the three rules a host would otherwise re-decide per surface: the stored **alpha** always applies, an **unresolvable class falls through to the stored swatch** (never to white, never to a substitute hue), and the swatch is therefore **never disabled**. `disabledIf` on a colour row is forbidden (anti-pattern #74) and the rule is said in the swatch's tooltip instead.

**Which class — and the path does not decide it:**

| Surface | Source | Why |
|---|---|---|
| Icons: cooldown tint, icon border, cooldown-text colour, both glow colours | **player** | the grid counts down the PLAYER'S OWN interrupts — `modules/Cooldowns.lua`'s `ResolveClassSpec` and `modules/IconGrid.lua`'s `getActiveSpecKey` both key the watched list on `UnitClass("player")`. That these settings live under `units.<unit>.` says nothing about whose class they mean. |
| Cast bar: both bar colours, both backgrounds, both spell names, both borders, the cast-time colour | **unit** | the bar describes the tracked unit |
| Text Label: the label colour | **unit** | the label names the unit it is drawn beside |

The intent is **declared on the row** (`classColorSource`, plus `classColorUnit` for the unit-scoped half), because the path cannot be trusted — and that declaration is what an audit reads. Pinned by `tests/test_schema.lua`.

**A linked Focus resolves on the RENDERING unit.** `units.focus.link` makes Focus draw with *Target's* appearance tables, but the bar and label on screen are the focus's, so every drawing site passes its own `inst.unit` and never the unit whose table the value came out of. Pinned in `tests/test_castbar_skin.lua` and `tests/test_unitlabel_apply.lua`.

Against an NPC boss — which is most of what this addon watches — the class is unresolvable and the stored swatch renders. That is intended, and the tooltip says so.


All six pages (General, Icons, Cast bar, Text Label, Spells, Profiles) are registered as **canvas-layout subcategories** so they share one custom header design:

* `GameFontNormalHuge` title on the left
* `Defaults` button on the right (AceGUI `Button`, which wraps `UIPanelButtonTemplate`) — present on General / Icons / Cast bar / Text Label / Spells, omitted on Profiles. It is **created lazily**, on the panel's first `OnShow`, by `Helpers.EnsureDefaultsButton(panel)`: AceGUI is a shared library and UI skins restyle its widgets by hooking `RegisterAsWidget`, so a widget built during load (when the category is registered) keeps Blizzard's stock red `UI-Panel-Button-Up` art whenever this addon happens to load before the skinner. Builders therefore park the handler as `ctx.panel.defaultsOnClick = fn` (a plain function — `EnsureDefaultsButton` wires it with `:SetCallback("OnClick", …)`, NOT `:SetScript`, since the AceGUI widget object isn't a Blizzard Frame) and call `H.EnsureDefaultsButton(ctx.panel)` as the first statement of the panel's `OnShow`. As of Options minor 5 that parked handler feeds a **second** control as well: `CreatePanel` stamps `OnCommit` / `OnRefresh` / `OnDefault` on the canvas frame, which is what the Settings window's own **footer** Defaults control calls. `OnDefault` is a *forwarder* — it reads `panel.defaultsOnClick` at click time, not at `CreatePanel` time, which is the only ordering that works when every builder parks its handler after `CreatePanel` has returned — so all five pages gained a working footer control with no host edit, and Profiles (which parks nothing) gets a callable, inert one. Pinned by three cases in `tests/test_options_panel.lua`; nothing else here would notice losing it, since the header button keeps working and looks equivalent to the user.
* `Options_HorizontalDivider` atlas underneath, full panel width.

The header is built by `Helpers.CreatePanel(name, title, opts)` in `settings/Panel.lua`. It returns a `ctx` table (`{ panel, body, chrome, chromeHeight, scroll, refreshers, lastGroup, lastSubgroup, pageKey }`) that the per-tab builder threads through the rest of the layout helpers. `ctx.scroll` is the AceGUI `ScrollFrame` (created lazily on first widget add) that hosts schema widgets; Profiles parents its own AceGUI container to `ctx.body` directly and never triggers the lazy scroll; **Spells no longer does** — it renders into `ctx.scroll` like every other page, because its own hand-anchored ScrollFrame hardcoded a top inset that cannot be right both with and without a chrome band.

The opts key is **`pageKey`**, not `panelKey`. Every page here handed `CreatePanel` a `panelKey` it silently dropped — the library reads `opts.pageKey` — which left `ctx.pageKey` nil, `O.__panelFor` unable to find any page, and the library's render-failure line naming `"?"` instead of the page that raised. Inert until something asked, which is why it survived; corrected in the settings-revamp-v2 pass.

Every panel ctx is stashed in `NS.Settings._panels` so `Helpers.RefreshAllPanels` can re-sync widgets after a slash-cmd write.

## Per-unit pages (Icons / Cast bar / Text Label)

These three render through `Helpers.RenderUnitPanel(ctx, panelKey, afterGroup)` (`settings/Panel_Render.lua`), which does three things in this order and the order matters:

1. **The Unit picker, as the page banner** (`Helpers.PageBanner`, `options-ui-§14`). It is pinned in the page's **chrome band, above the tab strip** — not added to the scroll, and not a tab. It scopes the whole page: `ctx.unit` is stashed on the panel ctx so `Helpers.SchemaForPanel(panelKey, ctx.unit)` filters rows to the selected unit's `units.<unit>.icons.*` / `.castbar.*` / `.label.*` paths, and every tab on the page edits that unit.

   Putting it in the chrome band is load-bearing rather than cosmetic. A tab click clears the **scroll** and redraws the rows; the chrome band survives it. A picker added to the scroll therefore looks right on the render that drew it and vanishes the first time the reader clicks a tab — which no static reading of the builder shows. Pinned by `tests/test_schema.lua`.

   It is also the page's **only** picker, which is the other half of `§14`: two controls over one piece of state is a synchronisation problem the design invents and then owns forever. Selecting a unit re-enters `RenderUnitPanel`, and `PageBanner` drains **both** chrome ledgers (its own and the strip's) before it draws, so a switch onto a linked Focus — which draws no strip — cannot leave the previous unit's tabs stranded above the note.

2. **The linked-Focus branch** (`Helpers.RenderLinkedUnit`). When `ctx.unit` is a linked Focus, the page draws **the strip first, always**, then the `alwaysPerUnit` rows (there are none today) and a note reading *"Linked to Target. Untick 'Use same styling as Target' on the General page's Units tab to give Focus its own."*

   It used to return **before** the strip, on the argument that a strip over a note is chrome for its own sake. That is a true sentence about one page and the wrong rule for a panel (`options-ui-§13`): flipping the Unit picker to a linked Focus made the whole page change shape under the reader, and the page with no strip is the one that reads as broken. The link is a **state of the page**, so it is content inside it.

   Editable-but-inert appearance widgets are still worse than none — a linked Focus renders with Target's tables, so any styled row here would write to a table nothing reads (`NS.Units.Icons("focus")` / `.Castbar("focus")` resolve to `units.target.*` while linked) — so the tab's CONTENT is still only its `alwaysPerUnit` rows plus the note. What changed is that the strip is above them. `RenderLinkedUnit` draws it by hand rather than through `RenderTabbedSchema`, which would render the very rows that must not be shown; the tab selection, the stale-pointer heal and the re-render on click are the same three things it does.

3. **The strip and the rows**, via `Helpers.RenderTabbedSchema`.

The **"Use same styling as Target"** checkbox (`units.focus.link`) and the **"Copy styling from Target"** button (`NS.Units.CopyStyling("target", "focus")`, a one-time deep-copy that also flips `link = false`) live on **General → Units** now (`settings/General.lua`, the group's `afterGroup`). They used to be drawn three times over, once in each unit page's hand-built header; there is exactly one of them — whether Focus keeps its own appearance or mirrors Target's — and the scroll, the only place left to draw them on a tabbed page, is cleared out from under them by every tab click. Both fire `Ka0s_KickCD_CONFIG_CHANGED{section="units"}` and then `Helpers.RefreshAllPanels`, which is a **structural** refresh: it re-renders every page that declared a renderer and marks the hidden ones dirty so they repaint on their next `OnShow`. That is what lets the control reach the three unit pages from another page at all.

General has no unit picker — its only per-unit rows are the two `units.<unit>.enabled` toggles on its Units tab, which render together, tagged with `unit = "target"|"focus"` purely so `RestoreDefaults`/`RestoreAllDefaults` reset both units together. (`label.show` / `label.text` used to live here; they moved to the Text Label page, which does use the picker.)

## `NS.Settings.Schema` is the single source of truth

`settings/General.lua`, `settings/Icons.lua`, and `settings/Castbar.lua` declare every option as a row in a flat array. Each row:

```lua
{
    panel    = "general",                    -- which tab renders it
    section  = "general",                    -- Ka0s_KickCD_CONFIG_CHANGED section
    group    = L["Master controls"],         -- THE TAB. One tab per distinct
                                             --   group, in declaration order
    path     = "scale",                      -- dotted db.profile path (per-unit rows use
                                             --   "units.<unit>.icons.<field>" etc.)
    unit     = "target"|"focus",             -- optional; tags a row as belonging to one
                                             --   unit for RestoreDefaults grouping.
                                             --   SchemaForPanel(panelKey, ctx.unit) filters
                                             --   Icons/Castbar rows on this
    type     = "bool"|"number"|"string"|"color",
    label    = L["Master scale"],
    desc     = L["..."],                     -- the tooltip BODY. A schema row may key it
                                             --   `desc` OR `tooltip`; the library reads either.
                                             --   A BESPOKE spec (SessionToggle, InlineButtonPair,
                                             --   PageBanner) must key it `tooltip` -- those makers
                                             --   read spec.tooltip and nothing else, so `desc`
                                             --   there draws the label with an empty body,
                                             --   silently and only in game.
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

A row may declare `solo = true` to be rendered alone in the left half of its own line — a genuine pivot above the controls it governs, never spacing. Four rows use it: Cast bar → General → "Enable cast bar" (everything under it is inert without it), Cast bar → Size and position → "Anchor mode" (it decides whether the two attach-point dropdowns below it are read at all), Text Label → Placement → "Attach to" (it decides what the two anchor points beneath it even refer to), and Icons → Annotations → "Show charges" (so the badge's two offsets read across one line rather than the first of them pairing with the toggle that governs whether the badge exists).

Two further row fields arrived with `OptionsWidgets` 13 and are worth distinguishing from `solo`: `wide = true` renders a row alone at FULL width (`solo` is alone in the LEFT HALF), and `startsLine = true` flushes the pending line *before* the row, which is what makes a declared pair unsplittable. No row here declares `wide`; every composed colour swatch declares `startsLine`.

A row may declare `skipRender = true` to stay a full schema row — `/kcd get|set|list`, Defaults reset, validation — while being left out of the automatic render pass, because the panel builder draws it by hand somewhere specific. **No row uses it today.** Its one user was General's `locked`, drawn by an `afterGroup` so it could share a line with the bespoke session-only "Debug console" toggle; both are ordinary composed rows on the Master controls tab now and the flow engine pairs them by itself.

A row may declare `valueGate = "<sibling.path>"` for dropdowns whose option list depends on another setting (the canonical case: cast bar `growDirection`'s `RIGHT`/`LEFT` vs `UP`/`DOWN` options gated on `orientation`). The `values` function should re-evaluate the option list against the gate's current value, and `/kcd set` will surface `(depends on <gate> = <current>; flip <gate> to <other> for <other-options>)` on rejection so a confused user can see why their value was refused AND what to flip to enable it.

The 13-option `<SIDE>_<ALIGN>` / `CENTER` anchor dropdown shared by Icons → Layout → Anchor point and Cast bar → Size and position → Anchor on primary icon / Anchor on cast bar comes from `Helpers.AnchorValues()`. Both dropdowns must use it so the option lists stay in lockstep when new anchors are added.

## Custom-body tabs (Spells / Profiles)

Spells and Profiles share the unified header but render custom bodies:

* **Spells** — no schema rows, but it is drawn the way every other page is drawn now:

  1. the spec picker and the **Add spell** button in a page-wide **chrome block** (`H.PageHeader`, `options-ui-§14`). Both apply to every tab — choosing what the page edits, and creating a new one — so neither may sit in the scroll, where a tab click would clear it away;
  2. a **one-tab strip** under it (`H.TabStrip`, `options-ui-§13`), labelled *Spell list*. Drawn directly rather than through `RenderTabbedSchema`, because there are no rows to partition;
  3. the rows in the library's own scroll (`H.EnsureScroll`), which anchors itself under whatever band the two above reserved.

  The chrome block is drawn **before** the strip: the strip's own band reservation reads `ctx.__bannerHeight`, and the other way round it would not know about it. The header `Defaults` button opens the existing `KICKCD_RESET_SPELLS` StaticPopup, which resets only the currently selected class+spec.

  **The rows drag** (`LibKa0s-Widgets-1.0`'s `ReorderList`, `options-ui-§18`) — see below.
* **Profiles** — AceDBOptions options table rendered into an AceGUI `SimpleGroup` parented to `ctx.body`. `AceConfigDialog:Open("KickCD-Profiles", container)` is called on first show. **No Defaults button** — profile management has its own destructive controls inside the AceDBOptions UI.

## The Spells reorder list (`options-ui-§18`)

The order of a spell list *is* the setting — it is the priority order the icon grid renders in — so the player drags it.

The paired up/down **arrow buttons are gone** (anti-pattern #75): two clicks per position, no feedback about where an item is going, and a different set of arrows drawn in every addon that had them. So is this page's row background: **the library owns the chrome** — the hamburger handle in a fixed 30px gutter at the row's far left, the row's bounded box (fill `1,1,1,0.06`, 1px edge `1,1,1,0.12`), the ghost that follows the cursor, the gold insertion line and the index arithmetic. Drawing our own box under the library's would stack two fills.

The row's **contents** are still entirely ours, and the only change to `buildRow` is a leading spacer sized from `W.ROW_BOX.HANDLE_W` — read off the library, never restated — so nothing sits under the handle.

Three things about the adoption are load-bearing:

* **Rows are a uniform height** (`ROW_HEIGHT = 28`, and the list's `stride` is the same number). The drop position is arithmetic on the stride, not a hit test, so a list of unequal rows drops in the wrong place.
* **`onMove(from, to)` is a splice to an index, one write.** `Spells.MoveTo` does `table.insert(list, to, table.remove(list, from))` and calls `commitSoon` once. Expressed as a run of adjacent swaps — which is what the arrows did, correctly, for one step — a four-position move would be four mutations and four re-renders, each pulling the page out from under a gesture that is still finishing.
* **The controller is cancelled at the TOP of the render**, before the first widget is created — not merely before the list is rebuilt. Handles and boxes are pooled and parented to the row frames, and `releaseAceGUITree` hands those frames straight back to AceGUI; a `Cancel` after that point reclaims a handle from whatever widget took the frame next. This is a shipped-bug lesson, it is the most common way an adoption of this widget goes wrong, and `tests/test_settings_spells_editor.lua` asserts the cancel/clear ORDER rather than the fact of the cancel.

There is **one** controller here — one flat list with no section a drag must not cross — so no `boundary` is passed. Without `LibKa0s-Widgets` there is no handle and no box and the list is not reorderable; that is an accepted cosmetic degradation and the arrows are deliberately not re-added as a fallback.

## Widget primitives (canvas mode)

All widgets bind directly to `db.profile` via `Helpers.Get(path)` and `Helpers.Set(path, section, value)`. Blizzard's `Settings.RegisterAddOnSetting` shim was deleted in CR-8 — the canvas widgets never went through Blizzard's Setting object lifecycle, so the shim was dead code. Don't reach for it when adding new UI; use the schema + `Helpers.RenderField` instead.

Each widget creator pushes a refresher closure into `ctx.refreshers` so its display can re-sync after a Defaults reset or a slash-cmd `/kcd set`.

### The refresher lifetime rule

**A refresher is valid only while the widget it captures is live, so `Helpers.ClearScroll` wipes `ctx.refreshers` at the same time it calls `ReleaseChildren`.** Every maker registers immediately after `parent:AddChild(...)`, which is what makes the wholesale wipe safe — no entry in the registry belongs to a widget outside the scroll. If you ever add a refresher for a persistent widget, it must **not** live in `ctx.refreshers`.

Getting this wrong is not a leak, it is corruption. AceGUI's pool recycles the *same widget objects* into whatever the next render creates, so a closure that outlives its widget doesn't quietly no-op — it writes its old row's value and dropdown list onto an unrelated widget. That shipped once: the **Unit** dropdown rendered anchor-point values on Icons and text-position values on Cast bar, because a stale anchor/position refresher fired against the recycled object now serving as the unit selector.

It reproduces through ordinary use, since the page clears and rebuilds on every unit switch, every **tab click**, and every structural refresh (the General → Units link tick, "Copy styling from Target", a profile switch) — then any `/kcd set` fires the whole registry. Guarded by `tests/test_settings_refreshers.lua`.

`Helpers.SetAndRefresh` — the addon's single write seam — ends in `Helpers.RefreshScalars`, **never** `RefreshAllPanels`. A value write changes what a widget *shows*; it does not make a row appear or vanish. A structural sweep there would clear and rebuild every rendered page on each committed change, including the page holding the slider or the colour swatch the user is still dragging, which AceGUI would take back into its pool mid-gesture. Structural refreshes have their own callers: `NS.RefreshOptionsPanel` on a profile switch, and the Units tab's link toggle, which really does change what the unit pages draw.

Schema widgets are AceGUI primitives:

- `CheckBox` for `bool`
- `Slider` for `number` — **unless** the row also declares a `values` list. As of OptionsWidgets minor 5 the library reads that shape as a constrained enum, not a range, and renders it as a `Dropdown` (matching what `LibKa0s-Slash-1.0` has always parsed it as). No row in this addon is a `number` carrying `values` today, so no widget here changed; a new one would draw as a dropdown, not a 0-to-1 slider.
- `Dropdown` for `string` rows that declare a `values` list (fixed-choice), or a function returning one. This addon supplies the **key-map** shape — `{ TOP_LEFT = "Top left", ... }` — paired with an explicit `sorting` array where the order matters, because alphabetizing an anchor list scrambles it. `Helpers.LSMValues(mediaType)` is the standard wrapper around LibSharedMedia listings, and `Helpers.AnchorValues()` returns the canonical 13-option `<SIDE>_<ALIGN>` / `CENTER` set. As of OptionsWidgets minor 4 the library also reads an **ordered array** of `{ value =, text = }`; either shape works, and note the key is `text` — never `label`.
- `EditBox` (`makeEditBox`) for `string` rows that **declare `dialogControl = "EditBox"`** — free text, which today is the two per-unit `label.text` caption rows (`maxLetters = 32`). It commits on `OnEnterPressed` (Enter / focus-loss), unlike the drag/click-commit widgets above, so a half-typed label never writes a partial string to `db.profile`.

  **The opt-in is explicit, and that is a fixed bug rather than a quirk.** `Helpers.RenderField` sends every `string` row that is not `dialogControl == "EditBox"` to `makeDropdown`, and `makeDropdown` calls `SetList({}, {})` when `values` is nil — so `label.text`, which shipped with neither key, rendered as a dropdown that opened on nothing, in game only. The library does **not** infer free text from a missing `values`: inference would silently turn a row whose `values` FUNCTION returned empty (an LSM list queried before registration) into a text box. As of the re-vendor it prints a warning for exactly that shape the first time such a page is opened, and `tests/test_schema.lua` asserts no row in this addon has it.
- `ColorPicker` for `color`
- `Heading` (bumped to `GameFontNormalLarge`) for sections

Non-schema action rows are built by `Helpers.InlineButtonPair` (two 50/50 `Button`s — the Master controls tab's "Reset position" beside "Reset all settings", drawn by the composer's own `afterGroup`, and General → Units' "Copy styling from Target"). `Helpers.InlinePair` is **gone**: it existed for exactly one line, the Lock-frame / Debug-console pairing, and that line is two ordinary schema rows now.

Paired into 50%/50% Flow rows inside a single AceGUI `ScrollFrame` per tab (see `Helpers.RenderSchema`). Spacers between rows give the airy look. Two-column rows are produced by wrapping a 50%-width pair into a Flow-laid `SimpleGroup`. A schema row tagged `solo = true` is forced onto its own row (left half, right half empty).

LSM-backed dropdowns (`borderTexture`, `statusBarTexture`, font rows) carry an `lsm = "<media-type>"` field so `makeDropdown` swaps the stock `Dropdown` widget for the matching `LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` widget from the vendored upstream `libs/AceGUI-3.0-SharedMediaWidgets/` (r65, multi-file under `widget.xml`). Statusbar and Font show an inline closed-state preview (the bar texture / the font's `Aa` glyphs); Border's 42×42 `displayButton` preview tile is suppressed by `core/LSMPatch.lua` (a PLAYER_LOGIN constructor wrapper) so the closed Border row is text-only and aligned with neighboring sliders. The popup hover-preview pane (upstream's `ContentOnEnter` swaps the popup backdrop's `edgeFile` to the hovered border) is unaffected. The widget types share the `SetLabel` / `SetList(items, order)` / `SetValue` / `OnValueChanged` interface with the stock `Dropdown`, so the rest of `makeDropdown` is unchanged either way.

This matches the visual style of AceConfig-driven addons (e.g. Consumable Master) and keeps every widget on the `Helpers.Set` / `Helpers.Get` data path. The slider's editbox is left to AceGUI's default formatter (integer step → integer text, float step → 2-decimal text); unit hints (`px`, `×`) belong in `def.label`, not appended to the value. `def.fmt` is still consulted by `/kcd get|list` slash output where text-only context benefits from a `"48 px"` / `"1.50x"` rendering.

## Deferred render

Rendering is **deferred**, because at build time (`PLAYER_LOGIN`) `ctx.body` has zero width and AceGUI's List-layout pass would size every fullwidth child to zero.

The four schema-driven pages declare *how* they draw with `Helpers.SetRenderer(ctx, fn)` and let the **library** own *when*: first show, and again when a refresh marked the page dirty while it was hidden. That second half is what makes a structural refresh from another page work — see the General → Units link toggle above — and it is why these pages no longer carry the hand-rolled `local rendered = false; OnShow{...}` guard. `SetRenderer` also installs the combat refusal (`options-ui-§2`): the Blizzard AddOns sidebar reaches a panel without going through `OpenOptionsPanel`, so its combat guard was bypassed on exactly the path a user is most likely to take mid-fight.

Spells and Profiles still park their own `OnShow` — they render bespoke bodies with their own lifecycles, not schema rows.

## ColorPicker

The ColorPicker's confirmation flow is a quirk of WoW 12.0's `SetupColorPickerAndShow` — KickCD listens to **both** `OnValueChanged` (treats every drag-step as a commit, giving a live preview) and `OnValueConfirmed` (fires only on Cancel, with the original color, so the value reverts cleanly).

The `OnValueChanged` commit is wrapped in `Util.Throttle(50, ...)` so dragging a color slider fires `Ka0s_KickCD_CONFIG_CHANGED` at most ~20 times/sec instead of every render frame. Without it the live cast bar / icon grid would re-skin per-frame during a drag, jankily on slower systems. `OnValueConfirmed` (which only fires on Cancel under WoW 12.0's flow) stays immediate so the snap-back is instantaneous.

## Always-visible scrollbar

The schema-driven panels share a lazy AceGUI `ScrollFrame` patched to **always** display its scrollbar (`Helpers.PatchAlwaysShowScrollbar`), even when the content fits. Without the patch, short panels (General) would render edge-to-edge while long ones (Icons / Cast bar) would gain a 20 px right-side scrollbar gutter — visually asymmetric. The patch parks the thumb at the top and grays the scrollbar out when there's nothing to scroll, but leaves the gutter reserved so every panel's body content has the same right-edge x-coordinate. The original `FixScroll` / `MoveScroll` / `OnRelease` are restored when the AceGUI widget pool recycles the frame, since the pool is shared across addons.

## Schema validation

`Helpers.ValidateSchema()` runs at panel-register time and asserts every schema row has a non-empty `path`, a known `panel` (`general` / `icons` / `castbar` / `label` / `spells` / `profiles`), a known `section` (`general` / `icons` / `castbar` / `label` / `spells` / `units` / `debug`), and a known `type` (`bool` / `number` / `string` / `color`). `debug` remains a valid `section` enum and no shipped row uses it. The debug **capture** flag is still session-only and still not a schema row (`NS.State.debug`, toggled via the console header button or `/kcd debug on|off|toggle`). The console **window** is a schema row now — `state.debugConsole`, `sessionOnly`, filed under section `general` — but it never reaches SavedVariables either: `settings/Panel.lua`'s `SESSION_PATHS` answers its path off `NS.DebugLog` inside `Helpers.Get`/`Set`, so the write never touches `db.profile`. Failures print a schema-error line (the printer prefixes with the shared `NS.PREFIX`) per offending row but don't refuse to load — diagnostic guard rail for future contributors, not a hard gate. A diff that adds a typo'd row is now self-flagging during a /reload.

## Reset helpers

The Master controls tab's "Reset all settings" button — drawn by `H.MasterControls`' returned `afterGroup`, not by this page — funnels through `Helpers.ResetAll`, which calls, in order: `Helpers.RestoreAllDefaults` (the library's — it loops over every schema-driven panel, then fires the descriptor's `afterRestoreAll` hook, which is `Helpers.ResetAllPositions` + `Helpers.RestoreUnitLinks`: anchors and the per-unit `link` flag are not schema rows, so `applyDefault` cannot reach them, and the hook runs **before** the refresh so the panel paints post-hook values) **and** `Database:ResetAllSpells` (rebuilds every spec's spell list from `NS.DefaultSpells`, the one piece nothing upstream can reach). `ResetAll` used to re-call `ResetAllPositions` and `RestoreUnitLinks` itself, duplicating the hook (KCD-R-04); that made the hook look optional, while the library's own footer Defaults control — which only ever goes through `RestoreAllDefaults` — depended on it. The slash command `/kcd resetall` shares this same helper — the popup and the CLI cannot diverge. Profiles are intentionally skipped because the AceDBOptions UI has its own destructive controls and resetting them would delete user data.

`Helpers.ResetIconPosition` is the corresponding helper for the "Reset position" button and `/kcd resetposition` — it writes `db.profile.units.target.anchors.icons` from `NS.DEFAULT_PROFILE.units.target.anchors.icons` so the default coordinates live in one place. It is TARGET-only by design — both are legacy "reset the grid" affordances that predate focus tracking, so a focus position reset is intentionally out of scope for them (focus already gets its own distinct default screen offset, and unlike target it can also be re-derived via "Copy styling from Target"). It fires `Ka0s_KickCD_CONFIG_CHANGED { section = "general" }` only — IconGrid's `general` branch already re-anchors every enabled unit's grid from its own anchor, and firing `icons` would just be a wasted relayout.
