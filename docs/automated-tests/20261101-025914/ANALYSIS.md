# Analysis — 20261101-025914

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** e15d81b8829650df257ff256794d7d697b7609f9 (feat/2026-10-31-findings-remediation)
- **Previous run:** 20261101-001951

## Headline

All four suites pass on the final pre-merge tree: lint 0/0 over 154 files, 1582 of 1583 cases passed with none failed and one declared skip, 7 perf scenarios measured, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). Since the previous run the case total is unchanged at 1583 because one case was retired and one added, the tree lost 2 NLOC and 2 functions, and no threshold was crossed. `tests/test_schema.lua` grew inside its existing band, which leaves one small note under Actions and nothing that blocks a merge.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261101-001951 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 154 files | [`lint.txt`](lint.txt) | nothing moved |
| tests | pass | 1582 passed, 1 skipped, 0 failed, 1583 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | figures unchanged; one case swapped for another |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged at 7; see What moved |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see What moved |

| Metric | Value |
|---|---|
| Total NLOC | 33159 |
| Functions | 4572 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 54.9 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 2 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

Every value above is from `manifest.json`. The complexity run is sighted: `blindFiles` and `crashedFiles` are both present and 0.

The one skip is pre-existing and does not count toward `passed`. It is the diagnostics contract case for an addon that opts out of logging (`tests.txt`): KickCD keeps the default, so its report turns logging on and the case above it holds that behavior.

## What moved

- **lint:** 0 warnings / 0 errors over 154 files, unchanged.
- **tests:** 1583 total, 1582 passed, 0 failed and 1 skipped, all unchanged. Diffing the two `test-cases.md` files shows the composition moved: *"the live wiring patches LSM30_Border through the library, not a private copy"* left `test_options_panel.lua` (33 → 32), and *"every media row draws Ka0sMedia_*, and the TOC loads no second picker"* joined `test_schema.lua` (41 → 42). The swap follows the move to one media picker.
- **perf:** 7 scenarios in both runs. `api/iter` is unchanged in every scenario. `bytes/iter` is unchanged in six scenarios and moved in one, `spellPoll` 411.3 → 412.0. `ms/iter` is `spellPoll` 0.01953 → 0.02520, `spellState` 0.00078 → 0.00081, `iconApply` 0.00026 unchanged, `probeOverheadOff` 0.00025 → 0.00024, `probeOverheadOn` 0.00048 → 0.00039, `castStart` 0.00547 → 0.00596, `cdText` 0.00311 → 0.00361. The largest move is `spellPoll`. Its cause was not investigated; the same run's `tests` suite also took longer (`durationMs` 32552 → 54167), and `api/iter` did not move. `perf` passes and the figures are recorded.
- **complexity:** NLOC 33161 → 33159 and functions 4574 → 4572. Avg NLOC/function 6.8, avg CCN 2.1, max CCN 15, avg tokens 54.9 and 0 warnings did not move.
- **band files:** 2 in both runs and over-cap files 0 in both runs. `modules/IconGrid.lua` stayed at 1023 LOC. `tests/test_schema.lua` rose 1026 → 1047 LOC inside the 1000–1500 band, which is the added case above.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1023 | Accepted — 475 NLOC in 60 functions; the rest is comments and blanks, one cohesive per-unit grid manager already peeled twice |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1047 | Accepted — case count, not tangle: 648 NLOC of individual schema cases |

Neither row is new, so no disposition was owed and both were carried forward. The reason for `tests/test_schema.lua` still holds, since its growth is one more schema case, but its 648 NLOC figure was written before this growth and this bundle holds no per-file NLOC to replace it, so it is left as carried. This is not a release run, so neither row has gained an Accepted reading toward the three-release limit.

## Actions

1. `docs/automated-tests/RESULTS.md`: the 648 NLOC in the `tests/test_schema.lua` disposition predates the 21 lines added in this run's tree. Refresh it from a per-file reading at the next edit of that row. New here, with no tracked ID.
