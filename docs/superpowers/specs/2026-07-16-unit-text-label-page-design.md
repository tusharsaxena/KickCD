# Unit Text Label + "Text Label" settings page — Design

**Status:** approved 2026-07-16 (design). Follow-up to the target/focus dual-tracking feature (issue #6). Branch: `feat/target-focus-dual`.

## Problem

The dual-tracking work (Task 9) shipped **two** on-widget identity labels per unit — one anchored to the icon grid, one to the cast bar — with only a `show`/`text` pair to configure them, and those controls live under **Settings → General → Units**. The user wants instead:

1. **One** label per unit (not two), attachable to *either* the cast bar or the icon grid.
2. Full control over that label: attach target, anchor point + attach point, X/Y offset, text justification, rotation, and font / size / flags.
3. Those controls moved out of General into their own **"Text Label"** sub-page that uses the same unit dropdown as the Icons and Cast bar pages.

Two adjacent items surfaced while scoping and are folded in:

- **Icons panel render robustness.** A pre-migration profile carried a stale/invalid saved value that made the whole Icons panel body fail to render (only the Unit selector survived). A settings reset cleared it. The code path is otherwise correct, so this is not a bug hunt — it is a **hardening** item: one bad saved value must not blank an entire panel.
- **Focus ships identical to Target.** Focus's `icons`, `castbar`, and (new) `label.style` default tables must be byte-identical to Target's, so unlinking Focus yields exactly Target's look. (Already true for `icons`/`castbar` via single-sourced `copy(ICONS_DEFAULT)` / `copy(CASTBAR_DEFAULT)`; the new `label.style` gets the same single-source treatment.)

## Decisions (locked)

From the brainstorming Q&A:

- **Orientation = both.** The label exposes text justification (`justifyH` ∈ LEFT/CENTER/RIGHT, `justifyV` ∈ TOP/MIDDLE/BOTTOM) **and** a rotation angle (degrees, via `FontString:SetRotation`).
- **Visibility = independent show toggle.** The label is visible whenever its unit is enabled and `label.show == true`, independent of whether the attach target (cast bar / grid) is currently drawn. Consequence: a label attached to the cast bar floats in place while the target is *not* casting (cast bar hidden, label stays). This is intended.
- **Focus link = follow the link.** When `units.focus.link == true`, the label's **appearance** (`label.style`) resolves to Target's, exactly like `icons`/`castbar`. `label.show` and `label.text` stay per-unit even while linked (matching today's `label.text` behavior).

## Data model

Replace `units.<unit>.label = { show, text }` with:

```lua
label = {
    show,  text,                 -- ALWAYS per-unit (never link-resolved)
    style = {                    -- link-resolved for Focus (follows units.focus.link)
        attach   = "castbar",    -- "castbar" | "icons"   (which frame the label anchors to)
        point    = "BOTTOM",     -- the label's own anchor point
        relPoint = "TOP",        -- point on the attach frame  (default: label BOTTOM -> frame TOP)
        offsetX  = 0,
        offsetY  = 0,
        justifyH = "CENTER",     -- LEFT | CENTER | RIGHT
        justifyV = "MIDDLE",     -- TOP  | MIDDLE | BOTTOM
        rotation = 0,            -- degrees; FontString:SetRotation(rad = deg * pi/180)
        font     = "Friz Quadrata TT",   -- LSM "font" key
        size     = 14,
        flags    = "OUTLINE",    -- NONE | OUTLINE | THICKOUTLINE | MONOCHROME
    },
}
```

**Single-sourced default.** Define `LABELSTYLE_DEFAULT` once in `core/Database.lua` (next to `ICONS_DEFAULT` / `CASTBAR_DEFAULT`) and build each unit's `label` as `{ show = false, text = <Title>, style = copy(LABELSTYLE_DEFAULT) }`. Target and Focus therefore ship with an **identical** `label.style`; only `text` differs ("Target" / "Focus").

**Migration.** A shape-driven, idempotent `Database:BackfillLabelStyle(db)` (same pattern and rationale as `FoldLegacyUnits`): for each unit, if `label.style == nil`, set `label.style = copy(LABELSTYLE_DEFAULT)`; preserve any existing `label.show` / `label.text`. Called **unconditionally** from `Database:Init` and `Database:OnProfileChanged`, after `FoldLegacyUnits` — that unconditional, shape-driven call (keyed on `style == nil`) is the guarantee that covers every account, so no `CURRENT_DB_VERSION` bump is strictly required. Whether to also bump the version and register a formal migrator entry (belt-and-suspenders, matching `FoldLegacyUnits`) is an implementation detail for the plan; the unconditional call is what the correctness rests on.

**`NS.Units` resolvers.**
- `NS.Units.Label(unit)` → own `{ show, text }` (unchanged; never link-resolved).
- `NS.Units.LabelStyle(unit)` → **link-resolved** `label.style` (Target's table when `unit` is a linked Focus, else own), mirroring `NS.Units.Icons` / `.Castbar`.

## Rendering — new `modules/UnitLabel.lua`

A dedicated per-unit label module, following the IconGrid / Castbar instance-manager pattern (`instances[unit]`, `GetInstance`, `EnableUnit` / `DisableUnit`, enable-gated reconcile). It replaces both Task-9 labels.

- **One `FontString` per unit**, parented to **`UIParent`** (so its show state and alpha are independent of the attach frame — required by the "independent show toggle" decision) but **`SetPoint`-anchored to the chosen attach frame** returned by the existing accessors: `IconGrid:GetGridFrame(unit)` for `attach == "icons"`, the Castbar instance frame for `attach == "castbar"`. Because `SetPoint` tracks its anchor frame live, the label follows the grid / cast bar as those move with **no** extra bookkeeping — it re-anchors only when `attach`, the points, or the offsets change, or when the attach frame is (re)created.
- **Apply** on `ApplyLabel(inst)`: read `NS.Units.Label(unit)` (show/text) and `NS.Units.LabelStyle(unit)` (appearance); set text, font (LSM fetch), size, flags, `SetJustifyH/V`, `SetRotation(rad)`, and re-`SetPoint` to the resolved attach frame with the configured points + offsets; `SetShown(enabled and show)`.
- **Fallback:** if the chosen attach frame does not exist for that unit (e.g. its cast bar is off), the label hides. Documented, not silent.
- **Events (module-level, once):** `Ka0s_KickCD_CONFIG_CHANGED` (react to `label`, `units`, and — for linked Focus — `icons`/`castbar` sections), `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_GRID_LAYOUT` (re-anchor when a grid is (re)created so the `SetPoint` target is fresh), and the master enable reconcile. No new message is added.

**IconGrid / Castbar shed their label code.** The Task-9 grid label (`IconGrid:ApplyLabel`, the per-instance label FontString) and cast bar label are removed; those modules no longer touch labels.

## Settings — new "Text Label" sub-page

A new canvas sub-page **"Text Label"**, registered **after Cast bar** (before Spells), built by a new `settings/Label.lua` that mirrors the Icons / Castbar builders: it calls `H.RenderUnitPanel(ctx, "label")`, reusing the shared Unit dropdown + Focus link/copy header. Every control is a **schema row** (so `/kcd set units.<unit>.label.*` and Defaults-reset keep working), `panel = "label"`, tagged `unit`, generated once per `NS.Units.LIST` entry with a single-sourced default.

Row sections:
- `show` (bool) and `text` (string) — tagged **`alwaysPerUnit = true`** (see below).
- `style.attach` (dropdown: Cast bar / Icon grid), `style.point` + `style.relPoint` (the shared 13-option `H.AnchorValues()` dropdowns, like the old Icons anchor UI), `style.offsetX` / `style.offsetY` (sliders), `style.justifyH` / `style.justifyV` (dropdowns), `style.rotation` (slider, degrees), `style.font` (LSM font dropdown), `style.size` (slider), `style.flags` (dropdown). `section = "label"` on all appearance rows.

**`alwaysPerUnit` render flag (small `RenderUnitPanel` enhancement).** Today, when Focus is linked, `RenderUnitPanel` skips the *entire* schema body and shows "Linked to Target — uncheck to customize." Because `show`/`text` are per-unit even when linked, `RenderUnitPanel` gains a split: rows flagged `alwaysPerUnit` render **regardless** of link state; the remaining (appearance) rows render only when not linked, else the existing note. Icons and Cast bar have no `alwaysPerUnit` rows, so their behavior is unchanged.

**General panel:** the per-unit **enable** rows stay in General; the label **show / text** rows are **removed** from General (moved to the Text Label page).

**`_validPanels`** in `settings/Panel.lua` gains `label = true`; the settings tab order registers `label` after `castbar`.

## Robustness hardening (Icons regression class)

In `Helpers.RenderSchema` (and thus every unit panel), wrap each row's `Helpers.RenderField` call in `pcall`. On failure, log a schema/render error via the existing `_printSchemaError` path and continue to the next row, so **one** bad saved value (bad enum, wrong-typed value) degrades to a single missing widget plus a logged reason — never a blank panel. This is defensive coverage for legacy/hand-edited SavedVariables; it does not change the happy path.

## Standard deviations to record (flag-deviations rule)

- New module `modules/UnitLabel.lua` and its frame/FontString names (`KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`).
- `label.style` DB sub-shape + `BackfillLabelStyle` migration.
- `alwaysPerUnit` schema/render flag.
- New settings panel key `label` ("Text Label").

Each recorded as an intentional deviation with a one-line justification in the relevant doc, per the existing pattern in `docs/conventions.md` / `docs/schema.md` / `docs/module-map.md`.

## Testing

Headless (`lua tests/run.lua`):
- `BackfillLabelStyle` idempotency + preservation of existing show/text; fresh v-current profile untouched.
- `NS.Units.LabelStyle` link resolution (linked Focus reads Target's style; unlinked reads own; deep-copy not alias after `CopyStyling`).
- Schema validity + unit-scoping of the new `label` panel rows; `alwaysPerUnit` rows present on `show`/`text` only.
- Defaults parity: `units.focus.label.style` deep-equals `units.target.label.style`.

In-game smoke (required, `docs/smoke-tests.md` additions):
- Text Label page: unit switch, attach target Cast bar ↔ Icon grid, anchor/attach point + offset, justification, rotation, font/size/flags — all live.
- Independent visibility: label stays while the cast-bar attach target is hidden (target not casting).
- Focus link: linked Focus label mirrors Target's style but keeps its own text; unlink → independent.
- Migration smoke: load a pre-`label.style` profile; confirm it backfills with no visual change.

Regenerate `docs/test-cases.md` and update the README `[Tests]` badge in the **same** change.

## Open item for spec review

**Focus anchor offset.** Focus's screen-*position* anchors (`units.focus.anchors.icons/castbar`) currently carry a small default offset from Target's so the two grids don't stack exactly on first enable. This is the **sole** default that is not identical between Target and Focus. The "ship identical" instruction was phrased about label / icon / cast bar *settings* (appearance); I have kept the position offset. **Confirm** during review whether you want the position anchors identical too (perfect overlap on first enable) or the offset retained.

## Out of scope

- Per-icon or per-spell labels (this is one identity label per unit).
- A third unit; the `NS.Units.LIST` pattern already generalizes to one if ever added.
- Version bump (per hard rules — not touched without explicit instruction).
