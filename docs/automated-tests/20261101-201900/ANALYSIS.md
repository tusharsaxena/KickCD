# Analysis — 20261101-201900

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** b65518eca75710b02b536152c0a363d15d872ec3 (feat/2026-11-01-full-skinning)
- **Previous run:** 20261101-144405

## Headline

All four suites pass on the re-cut LibKa0s v1.85.0 and kit revision 50: lint 0/0 over 156 files, 1638 of 1639 cases passed with none failed and one declared skip, 7 perf scenarios measured, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). The case total rose by 29, most of it the kit's two skin gates. Nothing here needs acting on beyond the carried notes under Actions.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261101-144405 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 156 files | [`lint.txt`](lint.txt) | one more file |
| tests | pass | 1638 passed, 1 skipped, 0 failed, 1639 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 29 cases added |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged at 7; see What moved |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see What moved |

| Metric | Value |
|---|---|
| Total NLOC | 34262 |
| Functions | 4714 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 55.3 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 2 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

Every value above is from `manifest.json`. The complexity run is sighted: `blindFiles` and `crashedFiles` are both present and 0.

The one skip is pre-existing and does not count toward `passed`. It is the diagnostics contract case for an addon that opts out of logging (`tests.txt`): KickCD keeps the default.

## What moved

- **lint:** 0 warnings / 0 errors, 155 → 156 files. The new file is `tests/skin_facts.lua`. `libs/` and `tests/_kit/` stay excluded, so the re-vendored payload and the kit's new suites are not in that count.
- **tests:** 1610 → 1639 total, 1609 → 1638 passed, 0 failed, 1 skipped. The kit's `test_skin_values` and `test_skin_switch` are the new suites. Those run in this bundle against 19 declared surfaces. The rest of the rise came in on the commits between the two runs.
- **perf:** 7 scenarios in both runs. `api/iter` is unchanged in every scenario. `bytes/iter` moved in one, `spellPoll` 306.9 → 284.0. `ms/iter`: `spellPoll` 0.03028 → 0.02608, `spellState` 0.00132 → 0.00088, `iconApply` 0.00033 → 0.00037, `probeOverheadOff` 0.00043 → 0.00033, `probeOverheadOn` 0.00089 → 0.00048, `castStart` 0.01770 → 0.01049, `cdText` 0.00562 → 0.00404. Timings are for orientation only.
- **complexity:** NLOC 33956 → 34262 and functions 4663 → 4714. Avg NLOC/function 6.8, avg CCN 2.1 and max CCN 15 did not move, avg tokens 55.5 → 55.3, 0 warnings. The total rose because the tree grew; the averages say it did not get denser.
- **band files:** 2 in both runs, over-cap files 0 in both runs.

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

Neither row is new. This is not a release run, so neither has gained an Accepted reading toward the three-release limit.

## Actions

1. Carried from 20261101-144405: `modules/IconGrid_Render.lua` is at 980 lines. The next addition there should come with a peel, before it enters the band.
2. Carried from 20261101-025914: the 648 NLOC in the `tests/test_schema.lua` disposition predates that run's growth.
