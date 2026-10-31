# Analysis — 20261031-212139

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** 9085fff9c78be07dc1687536321e467f2f0a3d6e (feat/2026-10-31-findings-remediation)
- **Previous run:** 20261031-202020

## Headline

All four suites pass on this post-remediation run: lint 0/0 over 153 files, 1576 of 1577 cases passed with none failed and one skip, 7 perf scenarios measured, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). The small drops since the pre-merge run (one Lua file, one case, 61 NLOC, 10 functions) are the removal of `Helpers.OpenPageTab` and with it `Panel_Widgets`. Nothing newly crossed a threshold and there is nothing to act on.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261031-202020 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 153 files | [`lint.txt`](lint.txt) | files 154 → 153; still 0/0 |
| tests | pass | 1576 passed, 1 skipped, 0 failed, 1577 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | total 1578 → 1577; skipped 1 → 1 |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged at 7 |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see What moved |

| Metric | Value |
|---|---|
| Total NLOC | 33031 |
| Functions | 4560 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 54.8 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 2 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

**tests.** The suite passed with one case reported as a skip (`tests.txt` line 1566): *"diagnostics contract: an addon that opts out lands the report and leaves logging off"*. Its reason, as the kit printed it: this addon keeps the default (`Kit.diagnostics.enablesLogging` is not false), so its report turns logging on, and the case above it holds that branch. It is a pre-existing contract branch that does not apply to this addon, carried from the previous run; it is counted in neither the passed nor the failed figure.

## What moved

- **lint:** 0 warnings / 0 errors, unchanged. The file count fell 154 → 153.
- **tests:** 1578 → 1577 total (-1), 0 failed in both runs, skipped unchanged at 1. Diffing the two `test-cases.md` files shows the one removed case: *"grid: a former page key opens Units on that entry and tab, drawn on its next show"* in `test_grid.lua`, which went with `Helpers.OpenPageTab`.
- **perf:** 7 scenarios in both runs. `api/iter` is unchanged in every scenario. `bytes/iter` is unchanged in six scenarios and moved in one, `spellPoll` 513.7 → 517.3. That cause was not investigated; `perf` passes and the figure is recorded. Timings are for orientation only and are not compared across runs.
- **complexity:** NLOC 33092 → 33031 and functions 4570 → 4560, so the addon shrank slightly. Avg NLOC/function 6.7, avg CCN 2.1 and avg tokens 54.8 did not move. Max CCN 15 and 0 warnings in both runs.
- **band files:** 2 in both runs, the same two files at the same LOC. Over-cap files 0 in both runs.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1023 | Accepted — 475 NLOC in 60 functions; the rest is comments and blanks, one cohesive per-unit grid manager already peeled twice |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1026 | Accepted — case count, not tangle: 648 NLOC of individual schema cases |

Both rows are carried forward unchanged, so no new disposition was owed. Neither has an Accepted reading on a release run yet, so neither has any history toward the three-release limit.

## Actions

None.
