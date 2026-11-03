# Analysis — 20261102-023505

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** ae802c1 (feat/2026-11-01-full-skinning), run after SF-KC-1
- **Previous run:** 20261101-201900

## Headline

All four suites pass: lint 0/0 over 156 files, 1638 of 1639 cases passed with none failed and one declared skip, 7 perf scenarios, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). This run records the tree after SF-KC-1, which makes the `pull` simulator scenario cast on the target and the focus together.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261101-201900 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 156 files | [`lint.txt`](lint.txt) | unchanged |
| tests | pass | 1638 passed, 1 skipped, 0 failed, 1639 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | case count unchanged; the pull e2e case gained assertions |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | count unchanged; timings only |
| complexity | pass | max CCN 15, 0 warnings | [`complexity.txt`](complexity.txt) | NLOC and function count up by a handful |

| Metric | Value |
|---|---|
| Total NLOC | 34270 |
| Functions | 4715 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 55.3 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 2 |
| Files over the 1500 cap | 0 |
| Blind files | 0 |
| Crashed files | 0 |

Every value is from `manifest.json`. The one skip is the pre-existing diagnostics-contract case for an addon that opts out of logging.

## What moved

- **tests:** 1639 total in both runs. SF-KC-1 changed the `pull` timeline and added assertions to the existing e2e case, not new cases.
- **perf:** `bytes/iter` and `api/iter` as before for every scenario but timing noise; `spellPoll` 0.02608 → 0.01978 ms/iter, `castStart` 0.01049 → 0.00913. Timings are for orientation only.
- **complexity:** NLOC 34262 → 34270 and functions 4714 → 4715; averages did not move.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1023 | Accepted — 475 NLOC in 60 functions; one cohesive per-unit grid manager already peeled twice |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1047 | Accepted — case count, not tangle: 648 NLOC of individual schema cases |

Neither row is new; this is not a release run.

## Actions

1. Carried: `modules/IconGrid_Render.lua` is near 980 lines. The next addition there should come with a peel.
