# Analysis — 20261104-042110

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** d88fbe5 (feat/2026-11-01-full-skinning), clean, run as R6-AT (label `R6 finish`)
- **Previous run:** 20261103-024220

## Headline

All four suites pass: lint 0/0 over 158 files, 1669 of 1670 cases passed with none failed and one declared skip, 7 perf scenarios, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). This run records the tree after rounds 4 to 6 of the full skinning run (the R4/R5/R6 re-vendors of LibKa0s v1.85.0, R5-ICON, R6-PV, R6-SIM and R6-NAME), 20 commits after the previous run. The one figure that moved sharply, `spellPoll` `bytes/iter` 200.0 → 1576.4, is a measurement artifact rather than new garbage; see *What moved*.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261103-024220 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 158 files | [`lint.txt`](lint.txt) | one more file in scope (157 → 158) |
| tests | pass | 1669 passed, 1 skipped, 0 failed, 1670 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 1644 → 1670 cases |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | count unchanged; `spellPoll` `bytes/iter` up (artifact), timings |
| complexity | pass | max CCN 15, 0 warnings | [`complexity.txt`](complexity.txt) | NLOC and function count up; averages flat |

| Metric | Value |
|---|---|
| Total NLOC | 34997 |
| Functions | 4821 |
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

Every value is from `manifest.json`. The one skip is the same pre-existing diagnostics-contract case as the previous run's (this addon keeps `Kit.diagnostics.enablesLogging` at its default, so the opt-out case does not apply; see `tests.txt`). It is counted in the total and not in `passed`.

## What moved

- **lint:** 157 → 158 files, still 0/0. The new file is `tests/test_sim_checkbox.lua` (R6-SIM).
- **tests:** 1644 → 1670 cases. They arrive from `tests/test_sim_checkbox.lua` (new, R6-SIM's Sim mode box), `tests/test_skin_picker.lua` and `tests/test_skin_settings.lua` (R6-PV's unlock-mode eye and the profile copy/reset restore), `tests/test_sim_e2e.lua` and `tests/test_mediasetup.lua`; the schema, layout-guard, settings-log and skin-HUD pins took the new row.
- **perf:** count unchanged at 7. `api/iter` is unchanged in every scenario, and `bytes/iter` in all but one. `spellPoll` `bytes/iter` went 200.0 → 1576.4. This is **not** a regression in `Cooldowns:Refresh`. `tests/perf.lua`'s `measure` records the net heap delta across the loop with the collector running, so the figure is the garbage the incremental collector had not yet reclaimed when the loop ended, and it moves with the size of the loaded heap. The rise was gradual across the re-vendor commits (198 at 691a52f, 579 at fa24785, 1105 at 7546ad3, 1466 at b6f713c, 1577 at cc61a05, 1605 at d88fbe5, each one `tests/perf.lua` run in a throwaway worktree), with no single step. With the collector stopped around the loop, also in a throwaway worktree that was then removed, 691a52f and d88fbe5 both measured an identical 4992.2 bytes/iter for `spellPoll`, and identical `spellState`, `castStart` and `cdText` figures too. The true allocation per poll did not change; the recorded figure under-reports it, which is Action 2. Timings moved within noise (`castStart` 0.00901 → 0.01311 ms/iter, `iconApply` 0.00024 → 0.00045) and are for orientation only.
- **complexity:** NLOC 34451 → 34997 and functions 4739 → 4821. Avg NLOC 6.8, Avg CCN 2.1 and Max CCN 15 did not move, and avg tokens went 55.4 → 55.3. The addon grew without getting denser.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1023 | Accepted — 475 NLOC in 60 functions; one cohesive per-unit grid manager already peeled twice |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1057 | Accepted — case count, not tangle: individual schema cases |

Neither row is new. `tests/test_schema.lua` grew 1052 → 1057 with the Sim mode row's pins. This is not a release run.

## Actions

1. Carried: `modules/IconGrid_Render.lua` is at 980 lines. The next addition there should come with a peel.
2. New here: `tests/perf.lua`'s `measure` reports net heap growth with the collector running, so `spellPoll` `bytes/iter` reads anywhere from 200 to 1600 where the real figure is about 4992, and it drifts with every re-vendor. Stopping the collector between the two `collectgarbage("count")` reads, or summing per-iteration deltas, would turn the figure into a measurement. That is a change to the addon's own `tests/perf.lua`, and this run does not make it.
