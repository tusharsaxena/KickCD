# 05 — Final summary (KickCD, 2026-10-07 review): to be confirmed after execution

> This is written **in advance**, assuming every check in `03_SMOKE_TESTS.md` passes and the M0
> decisions take the recommended routes (C-02 route A, C-05 option (a), C-04 and C-06 taken). Correct
> it to match what actually shipped before it is used as a PR description. In particular, the counts,
> the test movement and the dependency row depend on M0.

## Headline

This cycle fixes two real but narrow defects in KickCD. The cast bar, on its default
anchor-to-primary-icon mode, no longer loses its position when the active spec's icon grid empties.
Spell-name truncation on the cast bar now counts characters, so non-English clients get the length
they asked for and no broken glyph. Smaller fixes make a mistyped `/kcd debug` word stop toggling the
console, let the cast-bar and interrupt debug dumps target focus, make the *When target is casting*
glow follow casts by targets the player cannot attack, stop Cooldowns re-polling on cosmetic setting
changes, and tighten the lint whitelist. Lint, tests, complexity, vendor sync and the cross-addon
collision checks were all clean before the work started.

## Counts

`Critical fixed: 0, High fixed: 0, Medium fixed: 2, Low fixed: 5` (F-003, F-004, F-005, F-006, F-008).

- **Deferred:** F-007. It is latent and affects nobody today. Re-check trigger: a spec added to
  `defaults/Spells.lua` after 1.4.0.
- **Measured, not changed:** F-009. A change follows only if the new perf scenario shows a cost worth
  removing.

## Changes by theme

### T1: A cache must not outlive the thing it caches

- **What changed:** the cast bar now trusts the icon grid's announcement that there is no primary icon,
  and falls back to the grid frame.
- **Why it mattered:** it used to keep anchoring to a recycled, position-less icon button, so the bar
  could vanish until `/reload`.
- **Findings / changes:** F-001 / C-01.
- **Files:** `modules/Castbar_Events.lua`, `tests/test_castbar_frame.lua`.

### T2: Character-safe truncation

- **What changed:** *Truncate after (characters)* now counts characters.
- **Why it mattered:** it used to count bytes, which shortened accented and CJK names and could split a
  character.
- **Findings / changes:** F-002 / C-02.
- **Files:** `modules/Castbar.lua`, `tests/test_castbar_frame.lua` (or `test_castbar_helpers.lua`).
  On route A, also `libs/LibKa0s/**` through its own re-vendor commit.

### T3: A refusal must not act

- **What changed:** an unknown `/kcd debug` word prints the refusal and the sub-verb list, and no
  longer toggles the console. `/kcd debug castbar [target|focus]` and `/kcd debug interrupt
  [target|focus]` accept a unit.
- **Findings / changes:** F-003, F-004 / C-03, C-04.
- **Files:** `core/KickCD.lua`, `tests/test_slash.lua`, `docs/slash-dispatch.md`,
  `docs/ARCHITECTURE.md`.

### T4: One trigger, one meaning

- **What changed:** the glow refresh gate also tracks "any cast", so the *When target is casting*
  trigger repaints at cast start and stop for every target.
- **Findings / changes:** F-005 / C-05.
- **Files:** `modules/IconGrid_Visibility.lua`, `modules/IconGrid.lua`,
  `tests/test_icongrid_glowgate.lua`.

### T5: Announce only what a listener needs

- **What changed:** Cooldowns rebuilds on spell-list changes only. The master switch still reaches it
  through the stand-down latch.
- **Findings / changes:** F-006 / C-06.
- **Files:** `modules/Cooldowns.lua`, `tests/test_cooldowns_refresh.lua`.

### T6: Hygiene

- **What changed:** `.luacheckrc` no longer grants shipped code globals it never reads, and a case pins
  that. A perf scenario now measures the cooldown-event coalescer.
- **Findings / changes:** F-008, F-009 / C-08, C-09.
- **Files:** `.luacheckrc`, `tests/test_lintconfig.lua`, `tests/perf.lua`, `docs/performance.md`.

## API / behavior changes

- `/kcd debug castbar` and `/kcd debug interrupt` take an optional `target|focus` argument. With no
  argument they behave as before.
- An unknown `/kcd debug <word>` no longer toggles the console window.
- No new or renamed settings, no SavedVariables change, no `schemaVersion` bump, and no new locale
  keys.

## Saved-variable / migration notes

None.

## Deprecated-API migrations

None. `UIDropDownMenu_AddButton` was only ever whitelisted, never called. It is removed from the
whitelist.

## Dependency changes

| Dependency | Old | New | Why |
|---|---|---|---|
| LibKa0s (route A only) | v1.70.0 | the release carrying `LibKa0s-Core-1.0` minor 11 (`Utf8Prefix`) | a shared character-safe prefix for KickCD and MultiMeters |

## Performance impact

The only perf-tagged change that ships is C-06, and **no offline scenario covers the config path**, so
there is no before/after figure to report. C-09 adds a scenario whose first reading becomes the
baseline. `tests/perf.lua`'s existing scenarios should not move. Confirm that in the post-change run
against today's figures: `spellPoll` 581.9 B/iter, `castStart` 208.0, `cdText` 800.0.

## Test and complexity movement

- **Before:** 1302 passed, 1 skipped, 1303 total (badge `1302/1302`).
- **After (expected):** about +8 cases. C-01 adds 1, C-02 adds 1–2, C-04 adds 1, C-05 adds 1, C-06
  adds 2 and C-08 adds 1. C-03 extends an existing case.
- `docs/test-cases.md` and the README badge move in each test-adding commit.
- **Complexity:** no watch-list entry is expected to move. The next release regeneration also clears
  the 81-commit staleness in `docs/automated-tests/RESULTS.md`.

## Known follow-ups

- F-007: per-pair spell-list seeding, when a new spec ships.
- F-009: change `Util.Throttle` only if the new scenario shows real per-event garbage.
- A controlled `/kcd perf` capture on the current code. The committed captures are v1.2.1. This was
  carried over from the 2026-09-23 review.
- `localization-§3`'s terminal state (routed, or an English-only register row) is the standards
  audit's to decide, not this review's.

## Verification evidence

- `03_SMOKE_TESTS.md`, with its sign-off table filled in by the owner.
- The commit range: K-T1 … K-T7 on `feat/2026-10-07-review-audit-remediation`, plus the re-vendor commit
  on route A.

## Suggested PR description

```
KickCD: 2026-10-07 review remediation

- Cast bar no longer anchors to a recycled icon when the grid empties (F-001)
- Spell-name truncation counts characters, not bytes (F-002)
- /kcd debug: a typo refuses without toggling the console; castbar/interrupt take target|focus (F-003, F-004)
- "When target is casting" glow refreshes for any caster (F-005)
- Cooldowns no longer rebuilds on cosmetic General changes (F-006)
- .luacheckrc whitelist tightened and pinned (F-008); perf scenario for the cooldown coalescer (F-009)

Deferred: F-007 (latent; re-check on the next new spec).
Tests: 1302 -> ~1310 passing; inventory and badge moved in the same commits.
```
