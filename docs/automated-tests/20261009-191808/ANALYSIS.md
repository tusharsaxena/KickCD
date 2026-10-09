# Analysis — 20261009-191808

- **Addon:** KickCD 1.4.0 (release run for 1.5.0, `--release 1.5.0`)
- **Verdict:** green
- **Commit:** c6470e76397c3265d94622d7027217c19143b042 (master)
- **Previous run:** 20260927-030444 (the 1.4.0 release run)

## Headline

All four suites pass and the release gate holds: lint 0/0, 1319 of 1320 cases passed with none failed, 7 perf scenarios measured, and no function above CCN 15 on a sighted run (`blindFiles` 0). Since the 1.4.0 release run the suite grew by 119 cases, and all nine files that sat in the 1000–1500 band have been peeled out of it. The one skipped case is a kit contract branch this addon does not take; nothing else needs action.

## Suites

| Suite | Status | Result | Artifact | Moved since 20260927-030444 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 127 files | [`lint.txt`](lint.txt) | files 112 → 127; still 0/0 |
| tests | pass | 1319 passed, 1 skipped, 0 failed, 1320 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | total 1201 → 1320; skipped 0 → 1 |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | 6 → 7 scenarios (`cdText` added) |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see What moved |

| Metric | Value |
|---|---|
| Total NLOC | 26160 |
| Functions | 3616 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 54.6 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 0 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |

**tests.** The suite passed with one case reported as a skip (`tests.txt` line 1309): *"diagnostics contract: an addon that opts out lands the report and leaves logging off"*. Its reason, as the kit printed it: this addon keeps the default (`Kit.diagnostics.enablesLogging` is not false), so its report turns logging on, and the case above it holds that branch. It is a contract branch that does not apply to KickCD, not a case that failed to run for want of a tool or checkout. It is counted in the total and not in `passed`. It is new since the previous run because the kit's diagnostics contract arrived with the LibKa0s re-vendors in between.

**complexity.** This is the first sighted run in this record: the previous manifest carries no `blindFiles` field, so its figures came from a kit older than revision 35. This run's `blindFiles` is 0 and the functions table is still empty, so the sighted measurement found no function above CCN 15 that the unsighted runs had missed. Nothing is newly measured.

## What moved

- **lint:** 0 warnings / 0 errors, unchanged. The file count rose 112 → 127, from the peeled modules and split test files (`IconGrid_Visibility.lua`, `IconGrid_Ticker.lua`, `Castbar_Frame.lua`, `Database_Migrations.lua`, `Spells_Header.lua`, `wow_mock_frames.lua` and the `*_degraded.lua` / `*_latch.lua` test splits).
- **tests:** 1201 → 1320 total (+119), 0 failed both runs, skipped 0 → 1 (above).
- **perf:** 6 → 7 scenarios; `cdText` is new. Within this run, `spellState` allocates 1.5 bytes/iter (1696.6 before), `iconApply` and `probeOverheadOff` 0.0 (848.0 before) and `probeOverheadOn` 0.1 (848.1 before), which matches the ticker taking over time-varying icon render (KickCD#9). `spellPoll` allocates 572.2 bytes/iter (906.3 before) with api/iter unchanged at 18.0. `castStart` is unchanged at 208.0 bytes/iter and 0.0 api/iter. Timings are for orientation only and are not compared across runs.
- **complexity:** NLOC 24073 → 26160 and functions 3089 → 3616, so the addon grew. Avg NLOC/function 6.7 → 6.8, avg CCN 2.0 → 2.1, avg tokens 51.4 → 54.6: a small rise in density. Max CCN 15 and 0 warnings in both runs.
- **band files:** 9 → 0. Every file the previous watch list tracked (#24–#32) left the 1000–1500 band through the GI-KC-01 … GI-KC-09 peels and splits. Over-cap files 0 in both runs.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|

None.

## Actions

None. The nine band-file issues (#24–#32) can be checked for closure now that none of their files is in the band; this run is the evidence.
