# 05 — Final summary (written as if every change in 02 shipped and every test in 03 passed)

## Headline

This cycle fixed two defects players could hit and tightened several smaller ones.

**Players with more than one profile now get their colors and font options migrated on every profile, not only on the profile that was active when they upgraded to 1.3.0.** The Spells settings page no longer leaves tooltip hooks on AceGUI's shared widgets, which had made tooltips and click-eating labels show up in other addons' settings pages.

The icon grid and cast bar now reuse their per-unit event frames instead of leaking 36 frames on every disable/enable. The cast bar follows empowered casts, and rebuilt icons no longer flash "ready" while on cooldown. `/kcd spells add` accepts multi-word names and applies the same rules as the settings page.

A LibKa0s fix, re-vendored whole, makes the color-picker throttle work regardless of what a host's timer returns.

## Counts

Critical fixed: 0 · High fixed: 2 (F-001, F-002) · Medium fixed: 9 (F-003 to F-011) · Low fixed: 7 (F-012 to F-018) · Upstream: 1 (U-001, fixed in LibKa0s and re-vendored).

**Deferred:** none. The F-006 EMPOWER half is marked **untested** in the sign-off if no Evoker was available. It ships behind a `pcall`ed registration.

## Changes by theme

### T1 — Shape-driven per-profile migrations

- **What changed:** color-shape and font-flag migrations run on every profile load, like the other three shape-driven steps.
- **Why it mattered:** after upgrading, non-active profiles silently showed default colors and blank outline dropdowns.
- **Findings / changes:** F-001 / C-01.
- **Files:** `core/Database.lua`, `docs/ARCHITECTURE.md`, `docs/schema.md`, `tests/wow_mock.lua`, `tests/test_color_shape.lua`.

### T2 — Nothing outlives its AceGUI widget

- **What changed:** Spells-page tooltips use AceGUI callbacks and the library's `AttachTooltip`. The page renders once per edit, and a render error can no longer freeze it.
- **Why it mattered:** hooks leaked into every AceGUI consumer in the session, and each edit rebuilt the page twice.
- **Findings / changes:** F-002, F-008 / C-02, C-07.
- **Files:** `settings/Spells.lua`, `tests/test_settings_spells_editor.lua`.

### T3 — Reusable unit-filter frames

- **What changed:** one filter frame per (module, unit), reused across every stand-down. The EMPOWER events are added.
- **Why it mattered:** 36 frames leaked per disable/enable or perf cycle, which is a MUST in `events-frames-taint-§1`. Empowered casts were invisible to the bar.
- **Findings / changes:** F-003, F-006 / C-03.
- **Files:** `core/Util.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua`, `tests/test_disabled.lua`, `docs/ARCHITECTURE.md`, `docs/midnight-quirks.md`.

### T4 — Throttle contract

- **What changed:** `scheduleTimer` returns a handle. LibKa0s no longer depends on it.
- **Why it mattered:** color drags committed on every tick.
- **Findings / changes:** F-004, U-001 / C-04, M0/M1.
- **Files:** `settings/OptionsSetup.lua`, `libs/LibKa0s/**` (whole-folder re-vendor), `tests/_kit/**`, `CLAUDE.md`.

### T5 — One spell-input path

- **What changed:** a shared resolver handles multi-word names, class/spec validation and the Cooldown Manager gate for both the CLI and the page.
- **Why it mattered:** the documented `<name>` form failed for most interrupts, and the CLI admitted spells the page refused.
- **Findings / changes:** F-005, F-018 / C-05.
- **Files:** `core/SpellInput.lua` (new), `KickCD.toc`, `core/KickCD.lua`, `core/Database.lua`, `settings/Spells.lua`, `tests/test_slash.lua`, `tests/test_spell_registry.lua`.

### T6 — State replay after rebuild

- **What changed:** rebuilt icons seed from Cooldowns' last state.
- **Why it mattered:** whether an icon showed a stale "ready" depended on unspecified event-dispatch order.
- **Findings / changes:** F-007 / C-06.
- **Files:** `modules/Cooldowns.lua`, `modules/IconGrid.lua`, `tests/test_icongrid_buildlist.lua`.

### T7 — Evidence and hygiene

- **What changed:** the perf write-up matches the descriptor and the Rebuild emit is bracketed. `settings/Spells.lua` is peeled below 1000 LOC. There is one master-switch reader, and stale comments, reset wording, the lint allow-list and the dead `PLAYER_LOGIN` registration are fixed.
- **Findings / changes:** F-009, F-010, F-012 to F-017 / C-08, C-09, C-10.
- **Files:** `docs/performance.md`, `modules/Cooldowns.lua`, `settings/Spells.lua`, `settings/Spells_Rows.lua` (new), `core/KickCD.lua`, `core/Util.lua`, `core/Units.lua`, `core/State.lua`, `settings/Slash.lua`, `settings/Panel_Render.lua`, `README.md`, `.luacheckrc`, `tests/test_lintconfig.lua`, `tests/test_perfsetup.lua`.

## API / behavior changes

- `/kcd spells add <name>` accepts multi-word names. It refuses an unknown CLASS token and, for the player's own spec, a spell the Cooldown Manager does not track.
- `/kcd resetposition` covers every unit's icon grid (or its help text says "target" explicitly, whichever C-10 chose).
- The cast bar and grid react to `UNIT_SPELLCAST_EMPOWER_*`.
- New files: `core/SpellInput.lua` and `settings/Spells_Rows.lua`, both with commented TOC lines.
- No slash verbs were added or removed. No locale keys were renamed. Refusal strings added for C-05 go through `NS.L`.

## Saved-variable / migration notes

- **No `schemaVersion` bump.** The account stays at v5.
- The v3→v4 color reshape and the v4→v5 font-flag rewrite now also run, idempotently, on every profile load. Every existing profile auto-migrates the first time it is activated. No `/kcd reset` is needed.
- **Old → new shape** is unchanged from 1.3.0's intent: positional `{r,g,b,a}` becomes keyed `{r=,g=,b=,a=}`, and `"NONE"` becomes `""`.

## Deprecated-API migrations

None in shipped code; the review found no deprecated call. The lint allow-list stopped admitting `GetSpellInfo`, `GetSpecialization`, `GetSpecializationInfo`, `IsSpellKnown`, `IsPlayerSpell` and `IsSpellKnownOrOverridesKnown`, so a regression would now lint dirty.

## Performance impact

Only measured numbers are listed here, and the after-numbers come from records produced when the work lands.

- **Frames per disable/enable cycle.** The scratch harness measured +36 before (142 → 178 → 214 → 250 over three cycles). The expected result is +0 after, pinned by the new `tests/test_disabled.lua` case.
- **Offline scenarios, before (2026-09-23):**

  | scenario | bytes/iter |
  |---|---|
  | spellPoll | 1196.3 |
  | spellState | 1697.3 |
  | iconApply | 848.0 |
  | probeOverhead off | 848.0 |
  | probeOverhead on | 848.1 |
  | castStart | 208.9 |

  After: re-run `lua tests/perf.lua`. C-08 must leave the dormant arm at or below its 900-byte ceiling.
- **In-game:** the C-08 capture bundle under `docs/perf-analysis/<stamp>/` is the first on the 1.3.x bucket set. Cite its bucket figures, not the frame-time delta.

## Test and complexity movement

- **Pass count:** 1050 before; after is 1050 plus the new cases (roughly +10–12). `docs/test-cases.md` and the README `[tests]` badge moved **in each commit that added a case**.
- **Watch list:** `docs/automated-tests/RESULTS.md` is expected to show `settings/Spells.lua` leaving the 1000–1500 band after C-09. `modules/IconGrid.lua` and `modules/Castbar.lua` should be roughly flat, since C-03 is net neutral in LOC. The next release's regeneration confirms this; it was not regenerated here.

## Known follow-ups

- **`modules/Castbar.lua` (1423) and `modules/IconGrid.lua` (1343)** remain in the band. Peel them along their Skin/Handle and Layout/Render seams in a later cycle; this one kept to defects.
- **LootHistory and MultiMeters** must take the M1 re-vendor in their own repos. Until then they keep the throttle defect.
- **A controlled perf capture** (training dummy, fixed rotation, console off) is still wanted, per `docs/perf-analysis/README.md`.

## Verification evidence

- `03_SMOKE_TESTS.md` with its sign-off table filled in.
- Commit range: M1-T1 … M5-T4 on `feat/2026-09-23-review-audit-remediation`.
- LibKa0s tag: see the M0 checkpoint.

## Suggested PR description

```
KickCD: review 2026-09-23 remediation

High
- F-001 Color/font-flag migrations now run on every profile load (non-active profiles
  kept defaults after the 1.3.0 upgrade).
- F-002 Spells page no longer HookScripts pooled AceGUI frames (tooltips/mouse capture
  leaked into every AceGUI consumer).

Medium
- F-003/F-006 One reusable unit-filter frame per unit (+36 frames/cycle leak gone);
  UNIT_SPELLCAST_EMPOWER_* tracked.
- F-004 + U-001 scheduleTimer returns a handle; LibKa0s throttle no longer trusts it
  (LibKa0s vX.Y.Z re-vendored whole).
- F-005/F-018 One spell-input resolver for /kcd spells and the Spells page.
- F-007 Rebuilt icons seed from Cooldowns' last state.
- F-008 One render per Spells-page commit; render guard cannot stick.
- F-009 performance.md matches the Perf descriptor; Rebuild emit bracketed.
- F-010 settings/Spells.lua peeled below 1000 LOC.
- F-011 Tests for all of the above (each with a `red under:` line).

Low
- F-012..F-017 comments, master-switch reader, gate probe, lint allow-list,
  dead PLAYER_LOGIN, reset/README wording.

Tests: 1050 -> <new>/<new>; docs/test-cases.md and badge updated per commit.
```
