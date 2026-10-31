# Analysis — 20261101-001951

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** 3a1837b3561969481534cb776b827af759f57183 (feat/2026-10-31-findings-remediation)
- **Previous run:** 20261031-212139

## Headline

All four suites pass on the LibKa0s v1.84.0 adoption tree: lint 0/0 over 154 files, 1582 of 1583 cases passed with none failed and one declared skip, 7 perf scenarios measured, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). Since the previous run the suite gained 6 cases and the tree gained one Lua file, 130 NLOC and 14 functions, with average CCN and max CCN unmoved. Nothing newly crossed a threshold and there is nothing to act on.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261031-212139 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 154 files | [`lint.txt`](lint.txt) | files 153 → 154; still 0/0 |
| tests | pass | 1582 passed, 1 skipped, 0 failed, 1583 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | total 1577 → 1583; skipped 1 → 1 |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged at 7 |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see What moved |

| Metric | Value |
|---|---|
| Total NLOC | 33161 |
| Functions | 4574 |
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

- **lint:** 0 warnings / 0 errors, unchanged. The file count rose 153 → 154.
- **tests:** 1577 → 1583 total (+6), passed 1576 → 1582, 0 failed in both runs, skipped unchanged at 1. Diffing the two `test-cases.md` files shows six added cases and one rename, *"grid: the draw order is PageHeader, NavRail, TabStrip"* to *"grid: the draw order is PageBanner, NavRail, TabStrip"*. The added cases cover the anchor rows, the Ready glow styles, a dimmed column in a shown glow group, a switched row while hidden, the band's Copy from Target click, and the band's acts. The inventory shows a new `test_switched_sections.lua` (4) and `test_options_panel_degraded.lua` 9 → 11.
- **perf:** 7 scenarios in both runs. `api/iter` is unchanged in every scenario. `bytes/iter` is unchanged in six scenarios and moved in one, `spellPoll` 517.3 → 411.3. That cause was not investigated; `perf` passes and the figure is recorded. `ms/iter` is `spellPoll` 0.02061 → 0.01953, `spellState` 0.00082 → 0.00078, `iconApply` 0.00023 → 0.00026, `probeOverheadOff` 0.00024 → 0.00025, `probeOverheadOn` 0.00048 unchanged, `castStart` 0.00560 → 0.00547, `cdText` 0.00318 → 0.00311.
- **complexity:** NLOC 33031 → 33161 and functions 4560 → 4574, so the addon grew. Avg NLOC/function rose 6.7 → 6.8 and avg tokens 54.8 → 54.9. Avg CCN 2.1, max CCN 15 and 0 warnings did not move. The growth is size rather than branching density.
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

Both rows are carried forward unchanged, so no new disposition was owed. This is not a release run, so neither has gained an Accepted reading toward the three-release limit.

## Actions

None.
