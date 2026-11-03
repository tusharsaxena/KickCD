# Analysis — 20261103-024220

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** 691a52f (feat/2026-11-01-full-skinning), clean, run after R3-SIM-KC
- **Previous run:** 20261102-023505

## Headline

All four suites pass: lint 0/0 over 157 files, 1643 of 1644 cases passed with none failed and one declared skip, 7 perf scenarios, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). This run records the tree after R3-SIM-KC, which adds the `sim.stepDelay` slider (the General page's Simulator tab) and paces `/kcd sim` by it, plus the ten commits since the previous run (SF-FIX, SG-RV, R3-RV and R3-FRIZ). Nothing to act on beyond the carried action.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261102-023505 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 157 files | [`lint.txt`](lint.txt) | one more file in scope (156 → 157) |
| tests | pass | 1643 passed, 1 skipped, 0 failed, 1644 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 1639 → 1644 cases |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | count unchanged; timings and one allocation figure |
| complexity | pass | max CCN 15, 0 warnings | [`complexity.txt`](complexity.txt) | NLOC and function count up; averages flat |

| Metric | Value |
|---|---|
| Total NLOC | 34451 |
| Functions | 4739 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 55.4 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 2 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

Every value is from `manifest.json`. The one skip is the same pre-existing case as the previous run's; it is counted in the total and not in `passed`.

## What moved

- **lint:** 156 → 157 files, still 0/0. The new file is `tests/test_launcher_skin_entry.lua` (SF-FIX, SF-F2).
- **tests:** 1639 → 1644 cases. Three are R3-SIM-KC's in `tests/test_sim_session.lua` (the `sim.stepDelay` row and its range, `Host.DelayAfter` reading it, and a run waiting it between steps with a change landing from the next step); the rest arrived with the commits between the two runs. The schema, layout-guard, settings-log and degraded-panel pins took the new row and tab.
- **perf:** count unchanged at 7. `spellPoll` `bytes/iter` 213.0 → 200.0; every other `api/iter` and `bytes/iter` unchanged. Timings moved within noise (`spellState` 0.00141 → 0.00073 ms/iter, `castStart` 0.00913 → 0.00901); they are for orientation only.
- **complexity:** NLOC 34270 → 34451 and functions 4715 → 4739; Avg NLOC 6.8, Avg CCN 2.1 and Max CCN 15 did not move, and avg tokens 55.3 → 55.4. The addon grew, it did not get denser.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1023 | Accepted — 475 NLOC in 60 functions; one cohesive per-unit grid manager already peeled twice |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1052 | Accepted — case count, not tangle: individual schema cases |

Neither row is new (`tests/test_schema.lua` grew 1047 → 1052 with R3-SIM-KC's pins); this is not a release run.

## Actions

1. Carried: `modules/IconGrid_Render.lua` is at 980 lines. The next addition there should come with a peel.
