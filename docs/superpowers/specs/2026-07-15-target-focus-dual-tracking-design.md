# Design — Target + Focus dual tracking

**Issue:** [#6 — Add ability to track Focus and Target as separate icon grids](https://github.com/tusharsaxena/kickcd/issues/6)
**Date:** 2026-07-15
**Status:** Approved design, pending implementation plan.

## 1. Summary

Give KickCD a second watched enemy unit — **focus** — with its own icon grid and cast bar,
alongside the existing **target** grid and cast bar. Both render the **same player cooldowns**;
the point of a second unit is a per-unit **visibility trigger** ("show my interrupts when my
*focus* is casting") plus a **focus cast bar**. Each unit is independently enable-able.

Target defaults **on**; Focus defaults **off** — a cold install behaves exactly as today.

### Key realization (why this is cheaper than it looks)

The cooldown pipeline is already unit-independent, so most of the addon needs no change:

- `modules/Cooldowns.lua` tracks the **player's own** cooldowns — zero unit references. Both
  grids subscribe to the same `Ka0s_KickCD_SPELL_STATE` message unchanged.
- The spell list (`db.profile.spells[CLASS][SPEC]`) is player-keyed — shared, unchanged.
- `State.IsHostileUnitCasting(unit)` and `State.ApplyInterruptibleAlpha(frame, unit, alpha)`
  are **already** unit-parameterized — the natural seam for per-unit visibility/glow gating.

The coupling to fix lives entirely in the two widget modules (frame-singletons + hardcoded
`"target"`), `Util.RegisterTargetEvent` (hardwired unit), the `GRID_LAYOUT` message (no unit
tag), and the DB/settings layer (single anchors, flat config paths).

## 2. Configuration model

Three tiers of configuration:

### 2a. Per-unit, always independent (never linked)

- `enabled` — each unit's master show/hide.
- **Position** — grid anchor + cast bar anchor. Independent *by physics*: two grids can't
  occupy the same screen point, so placement is never mirrored.
- **Label text** — defaults `"Target"` / `"Focus"`, user-editable. Independent *by semantics*:
  a focus label reading "Target" defeats its purpose. (Label *show* + *style* follow the link;
  only the text is per-unit.)

### 2b. Per-unit appearance (covered by the styling link)

Everything else visual — the entire Icons block (`icons.*`) and Cast bar block (`castbar.*`):
size, rows/cols, grow direction, glow, colors, **border color**, and label show/style.

Focus carries a **"Use same styling as Target"** link:

- **Default: ON.** While linked, Focus mirrors Target's *entire* appearance live (the link is
  total — border color included). The two grids are told apart by their **labels**, not their
  borders. (This supersedes an earlier "different borders by default" idea; distinct borders
  become something the user sets after unlinking.)
- **"Copy styling from Target"** button — one-shot snapshot of Target's current appearance into
  Focus's own config, then unlinks so the user can customize from a good starting point.
- While linked, Focus's appearance widgets are disabled in the panel (showing Target's values).

Render resolves appearance per instance: `resolveAppearance(unit)` returns
`linked and target.appearance or unit.appearance`.

### 2c. Shared / addon-wide (v1)

- **Visibility mode** (`always` / `in_combat` / `target_casting` / `target_casting_interruptible`)
  — one setting, evaluated against **each unit's own cast**. The Target grid+bar gate on the
  target's cast; the Focus grid+bar gate on the focus's cast. Preserves the documented
  "one shared visibility mode" invariant.
- **Drag lock** — one lock; one unlock shows both grids' drag handles.
- **`scale`, `alpha`** — remain addon-wide in v1 (see §9 Non-goals).

## 3. Module architecture

`IconGrid` and `Castbar` remain single AceAddon modules but stop being frame-singletons. Each
becomes a **manager over an instance table keyed by unit** — `instances.target`,
`instances.focus`.

- A `CreateInstance(unit)` factory builds each instance's frame, icon pool, and config resolver.
  Today's file-local `grid` / `frame` / `pool` / `current` / `lastGridLayout` become
  per-instance fields.
- Handler dispatch:
  - `OnSpellState` — applies to **all** instances (shared cooldown state).
  - Cast / target-changed / focus-changed events — routed to the **matching** instance only.
- **Event registration is enable-gated, per instance.** An instance registers its own
  `UNIT_SPELLCAST_*` family and its unit-change event (`PLAYER_TARGET_CHANGED` /
  `PLAYER_FOCUS_CHANGED`) only while it is being tracked — i.e. `db.profile.enabled` (master)
  **and** `db.profile.units.<unit>.enabled`. When a unit is disabled its events are
  unregistered, so a disabled unit is fully inert (no event traffic, no handler no-ops). This is
  symmetric across both units: Target defaults enabled, so it registers at login exactly as
  today; Focus registers only when turned on. The enable toggle already fires
  `Ka0s_KickCD_CONFIG_CHANGED`, which each instance hooks to (un)register. On **enable**, the
  instance immediately re-evaluates the unit's current cast (`GetCastingInfo("<unit>")` via the
  existing `Reevaluate()` path) so an already-in-progress cast is caught rather than missed.
- No file forking. Duplicating the ~2000 LOC of the two modules (and fighting the 1500-LOC
  per-file cap) is explicitly rejected in favor of the instance-manager refactor.

New global frame names: `KickCDIconGridFocus`, `KickCDCastbarFocus`. Target keeps
`KickCDIconGrid` / `KickCDCastbar` for macro / back-compat.

## 4. Database shape

**Clean restructure** (chosen over the additive alternative for symmetry and cheap future units):

```
db.profile
  units
    target
      enabled = true
      label   = { show, text = "Target", ... }
      anchors = { icons, castbar }
      icons   = { ... }   -- was db.profile.icons
      castbar = { ... }   -- was db.profile.castbar
    focus
      enabled     = false
      link        = true          -- "Use same styling as Target"
      label       = { show, text = "Focus", ... }
      anchors     = { icons, castbar }   -- default offset from target so they don't overlap
      icons       = { ... }       -- used only when link = false
      castbar     = { ... }       -- used only when link = false
  -- shared / addon-wide (unchanged locations):
  visibility, locked, scale, alpha, enabled, spells
```

- **Migration:** move existing `db.profile.icons` / `castbar` / `anchors.icons` /
  `anchors.castbar` into `db.profile.units.target.*` via the existing `OnInitialize` migration
  scaffold. Must be idempotent and covered by a unit test (see §8).
- All ~72 schema `path` strings gain a `units.<unit>.` prefix; `Helpers.Resolve` is generalized
  to walk from a unit-scoped root instead of the fixed `db.profile` root.

## 5. Settings panel

- **Icons** and **Cast bar** panels gain a **unit selector** (`[ Target ▾ ]`) at the top that
  repoints every widget to that unit's subtree.
- When **Focus** is selected: a **"Use same styling as Target"** checkbox and a
  **"Copy styling from Target"** button sit above the appearance widgets. While linked, those
  widgets are disabled and reflect Target's values.
- **General** panel gains per-unit **enable** toggles and the **label** controls (show + text)
  for each unit.
- `_validSections` and `Helpers.ValidateSchema` extend to cover the new rows. The schema stays
  the single source of truth — no parallel mutators.
- `/kcd get|set|list` parity follows automatically from the schema rows (paths now include the
  unit dimension, e.g. `units.focus.icons.size`).

## 6. Message bus & shared plumbing

- `Ka0s_KickCD_GRID_LAYOUT` payload gains a **`unit`** field so each cast bar instance anchors
  to *its* grid. This is a payload change within the closed bus, **not** a new message — update
  emitter(s), consumer(s), and `docs/message-bus.md`.
- `Util.RegisterTargetEvent` gains a `unit` parameter (currently hardwired to
  `RegisterUnitEvent(..., "target")`); handlers dispatch on the forwarded `unit`. Registration
  is driven by the per-instance enable gate (§3), not statically at `OnEnable` — the helper must
  therefore support **unregistering** a unit's events too (add a matching teardown, or return a
  handle the instance can release).
- `Castbar`'s grid resolver (`resolveGridFrame` / `resolvePrimaryIcon`) becomes unit-aware so a
  focus cast bar anchors to the focus grid, not the target grid.
- Focus tracking registers the focus-change event (`PLAYER_FOCUS_CHANGED`) mirroring the
  existing `PLAYER_TARGET_CHANGED` handling.

## 7. Visibility & lock

- `shouldBeVisible(unit)` per instance, built on the already-parameterized
  `State.IsHostileUnitCasting(unit)` (show) + `State.ApplyInterruptibleAlpha(frame, unit, 1)`
  (interruptibility mask). One visibility mode, evaluated per unit.
- One drag lock (`db.profile.locked`) shared across both units' grids and cast bars.

## 8. Testing

- **Migration test** — legacy profile (`db.profile.icons/castbar/anchors`) migrates to
  `units.target.*` idempotently; a v2 profile is left untouched.
- **Schema validation** — `Helpers.ValidateSchema` returns 0 malformed rows with the expanded,
  unit-scoped schema.
- **Config resolution** — `resolveAppearance(unit)` returns Target's block when Focus is linked
  and Focus's own block when unlinked; "Copy from Target" seeds + unlinks.
- Regenerate `docs/test-cases.md` and bump the README `[Tests]` badge in the same change
  (standard testing-§5).
- **Smoke tests** (new scenarios in `docs/smoke-tests.md`): enable Focus; focus a caster and
  confirm the focus grid/bar gate on the focus's cast independently of the target; unlink Focus
  and confirm independent styling; "Copy from Target"; drag both under one unlock; migration
  from a pre-feature profile.
- **Enable-gated registration** (smoke): enabling Focus **while the focus is mid-cast** shows the
  in-progress cast immediately (reevaluate-on-enable, §3); disabling Focus leaves the target
  grid/bar unaffected and stops all focus event handling.

## 9. Non-goals (v1)

Deferred, cheaply addable later on the unit-keyed instance model:

- Per-unit `scale` / `alpha` (stay addon-wide).
- Additional units (arena1 / boss1 / party) — the instance model generalizes, but v1 ships
  target + focus only.
- Per-unit spell lists (cooldowns are player-centric; shared list is correct).
- Per-unit visibility mode (shared mode preserved; per-unit mode was considered and declined for
  v1 as it breaks the "one shared visibility mode" invariant).

## 10. Standard / invariant impact (per CLAUDE.md — flag & record)

| Item | Nature | Disposition |
|---|---|---|
| Suffixed global frame names (`KickCDIconGridFocus`, `KickCDCastbarFocus`) | Extends "frame names stay literally `KickCD`" | Intentional; document in conventions/module-map |
| `Ka0s_KickCD_GRID_LAYOUT` gains `unit` field | Payload change within closed bus | Update `docs/message-bus.md` |
| Module singleton → per-unit instance manager | Internal structure change | Update `docs/module-map.md` / `ARCHITECTURE.md` |
| DB restructure to `units.*` + migration | Saved-variables shape change | Update `docs/schema.md`; migration test |
| One lock + one visibility mode | **Preserved** — no deviation | — |

The user owns any decision to record these as intentional deviations vs. amend the standard.
