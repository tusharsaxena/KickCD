# Analysis — 20261031-202020

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** f97114c1cdc423b585a9ed2d96c8c84adff540e9 (feat/2026-10-31-font-pickers-skin-faces)
- **Previous run:** 20261009-191808 (the 1.5.0 release run)

## Headline

All four suites pass on this pre-merge run: lint 0/0 over 154 files, 1577 of 1578 cases passed with none failed, 7 perf scenarios measured, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). The addon grew by 6932 NLOC and 954 functions since the release run while the averages held. Two files newly crossed into the 1000–1500 band; neither needs a split now, and no code changed for this run.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261009-191808 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 154 files | [`lint.txt`](lint.txt) | files 127 → 154; still 0/0 |
| tests | pass | 1577 passed, 1 skipped, 0 failed, 1578 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | total 1320 → 1578; skipped 1 → 1 |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged at 7 |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see What moved |

| Metric | Value |
|---|---|
| Total NLOC | 33092 |
| Functions | 4570 |
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

**tests.** The suite passed with one case reported as a skip (`tests.txt` line 1567): *"diagnostics contract: an addon that opts out lands the report and leaves logging off"*. Its reason, as the kit printed it: this addon keeps the default (`Kit.diagnostics.enablesLogging` is not false), so its report turns logging on, and the case above it holds that branch. It is a pre-existing contract branch that does not apply to KickCD, the same skip the previous run carried. It is counted in the total and not in `passed`.

## What moved

- **lint:** 0 warnings / 0 errors, unchanged. The file count rose 127 → 154, a net 27 from the files added since `c6470e7`: the simulation (`modules/Sim*.lua`), `core/Events.lua`, `core/GlowSetup.lua`, `core/SimSetup.lua`, `core/SkinSetup.lua`, and their suites.
- **tests:** 1320 → 1578 total (+258), 0 failed in both runs, skipped unchanged at 1.
- **perf:** 7 scenarios in both runs. Allocation and API counts are the comparable figures: `spellPoll` 572.2 → 513.7 bytes/iter with api/iter unchanged at 18.0; `spellState`, `iconApply`, `probeOverheadOff`, `probeOverheadOn`, `castStart` and `cdText` unchanged in bytes/iter and api/iter. Timings are for orientation only and are not compared across runs.
- **complexity:** NLOC 26160 → 33092 and functions 3616 → 4570, so the addon grew. Avg NLOC/function 6.8 → 6.7, avg CCN 2.1 → 2.1, avg tokens 54.6 → 54.8: size rose, density did not. Max CCN 15 and 0 warnings in both runs. `crashedFiles` is new to the manifest and reads 0; the previous manifest has no such field.
- **band files:** 0 → 2, both newly crossed (below). Over-cap files 0 in both runs.

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

Both rows are new at this run, so neither has any Accepted history toward the three-release limit.

## Actions

None.
