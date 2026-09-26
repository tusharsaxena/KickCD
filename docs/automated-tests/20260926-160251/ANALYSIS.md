# Analysis — 20260926-160251

- **Addon:** KickCD 1.3.0
- **Verdict:** green
- **Commit:** cdff9801373302e405117502527ff84f7988b6ff (master), clean
- **Previous run:** [`20260924-132214`](../20260924-132214/)

## Headline

Green on all four suites. Nothing was skipped and no function is above CCN 15. The run measures
master at `cdff980`, 26 commits after the previous run's `55a1f12`: the remediation merge, the
diagnostics rollout (LibKa0s v1.60.0) and the NavRail adoption (LibKa0s v1.61.0, #33). Tests rose
1141 → 1201. The `layout-§1` band holds the same nine files, and four of them grew. `modules/Castbar.lua`
is now 1440 lines, 60 below the cap and 10 below its own re-check line. No entry is newly on the
watch list and no disposition is blank. The only action is the #24 peel that was already standing.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260924-132214` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 111 files | [`lint.txt`](lint.txt) | +5 files in scope, still 0/0 |
| tests | pass | 1201 passed, 0 skipped, 0 failed, 1201 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | +60 cases |
| perf | pass | 6 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged; see below |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

**Complexity metrics** (all from [`manifest.json`](manifest.json), footer in [`complexity.txt`](complexity.txt)):

| Metric | Value |
|---|---|
| Total NLOC | 24060 |
| Functions | 3089 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.0 |
| Max CCN | 15 |
| Avg tokens / function | 51.4 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 9 |
| Files over the 1500 cap | 0 |

Every suite ran to completion. No suite was skipped and no case reported a `Kit.skip`, so passed and
total agree at 1201. The toolchain in [`manifest.json`](manifest.json)'s `host` block is unchanged:
Lua 5.1.5, `luacheck` 1.2.0 and `lizard` 1.24.0. The run took 27874 ms.

Three functions sit at CCN 15 exactly. That is on the line, not over it, and `lizard` does not warn
on them ([`complexity.txt`](complexity.txt)): `State.ApplyInterruptibleAlpha` (`core/State.lua:116`),
`buildSpecNameMaps` (`core/Util.lua:260`) and `Layout.layoutBlock`
(`modules/IconGrid_Layout.lua:145`, 58 NLOC and 12 parameters). The threshold line in the same file
reads `length > 1000 … parameter_count > 100`. At those values, length and parameter count are not
effectively measured, so no threshold this run applies would flag the 12-parameter function.

Of the 13 bundles before this one, two carry no `ANALYSIS.md`: `20260807-110522` and
`20260825-103417`. `automated-tests-§5` forbids backfilling them, so this is noted once and not
actioned.

## What moved

The previous run measured `55a1f12` on the remediation branch. This one measures `cdff980` on
master, 26 commits later.

- **lint**: 106 → 111 files in scope, still 0 warnings / 0 errors ([`lint.txt`](lint.txt)). Five
  authored files arrived: `modules/Diagnostics.lua`, `settings/Grid.lua`, `tests/mock_menu.lua`,
  `tests/test_diagnostics.lua` and `tests/test_grid.lua`. None left. The five `.luacheckrc`
  exclusions named in [`../RESULTS.md`](../RESULTS.md) are unchanged.
- **tests**: 1141 → 1201 passed (+60), 0 skipped, 0 failed ([`tests.txt`](tests.txt)). The new cases
  are the diagnostics contract and the Grid page. [`test-cases.md`](test-cases.md) is byte-identical
  to `docs/test-cases.md` at this commit.
- **perf**: 6 scenarios in both runs ([`perf.txt`](perf.txt)). `api/iter` is unchanged in all six
  (18.0 for `spellPoll`, 0.0 elsewhere). `spellPoll` allocation fell 1024.8 → 921.4 bytes/iter, and
  `spellState` is flat at 1696.6. `iconApply`, both `probeOverhead` buckets and `castStart` are
  unchanged at 848.0 / 848.0 / 848.1 / 208.0 ([`perf.json`](perf.json) against
  [`../20260924-132214/perf.json`](../20260924-132214/perf.json)). `ms/iter` moved a few percent
  either way (`probeOverheadOn` 0.00270 → 0.00343, `castStart` 0.00557 → 0.00523). The runner's
  caveat applies: timings are for orientation, not for comparing runs. Recorded, not actioned.
- **complexity**: NLOC 22684 → 24060 (+1376) over 2906 → 3089 functions (+183). Avg NLOC / function
  is flat at 6.7, avg CCN is flat at 2.0 and avg tokens / function moved 51.3 → 51.4. The totals rose
  because the addon grew. The averages did not move, so the new code is no denser than the old. Max
  CCN is flat at 15 and warnings are flat at 0.
- **band**: 9 → 9 files, with no entries and no exits. Four grew: `core/Database.lua` 1002 → 1069
  (+67), `modules/Castbar.lua` 1435 → 1440 (+5), `modules/IconGrid.lua` 1368 → 1381 (+13) and
  `tests/test_options_panel.lua` 1099 → 1101 (+2). The other five did not move. No file crossed its
  re-check line: Database is 31 below 1100, Castbar 10 below 1450 and IconGrid 69 below 1450.

## Complexity watch list

**Functions `lizard` warned on:**

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

**Files by `layout-§1` band.** The dispositions of record are in [`../RESULTS.md`](../RESULTS.md),
where the runner carried them forward unchanged. None is blank. Summary:

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `core/Database.lua` | 1069 | tracked as #29; re-check at 1100 |
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1440 | tracked as #24; peel before the next feature; re-check at 1450 |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1381 | tracked as #25; re-check at 1450 |
| 1000–1500 (on notice) | `modules/IconGrid_Render.lua` | 1014 | tracked as #26; re-check at 1100 |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1115 | tracked as #28; re-check at 1200 |
| 1000–1500 (on notice) | `tests/test_options_panel.lua` | 1101 | tracked as #31; re-check at 1200 |
| 1000–1500 (on notice) | `tests/test_perfsetup.lua` | 1018 | tracked as #32; re-check at 1100 |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1035 | tracked as #30; peel on next touch; re-check at 1150 |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1233 | tracked as #27; re-check at 1350 |

Every entry points at an open tracked issue rather than a bare "Accepted", so no disposition has hit
the three-release shelf life (anti-pattern #53). The carried prose still quotes the previous run's
line counts ("1345 → 1435" and similar). Those counts describe the cycle in which each file entered
the band or grew, and the decisions recorded with them still hold.

## Actions

1. `modules/Castbar.lua`: take the #24 peel (cast-event handlers into `modules/Castbar_Events.lua`)
   before the file takes another feature. It is 60 lines from the cap and 10 from its re-check line.
   Tracked as #24, and carried from the previous run.
2. `core/Database.lua`: +67 lines this cycle, 31 below its 1100 re-check. No action yet. Tracked as
   #29.
3. The other seven band files: no action. Each is tracked and carries its re-check line in
   `RESULTS.md`.
