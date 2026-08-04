# Automated test results

<!-- The newest run is prepended by tests/_kit/run-automated-tests.sh. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

**`lint` and `tests` gate. `perf` and `complexity` are recorded and never fail a run** —
they are read and compared, not thresholded. A `skip` is a suite that did not run at all,
which is never the same as a pass.

| Run | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260804-214315`](20260804-214315/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 0 | 0 | **green** |
| [`20260804-182144`](20260804-182144/) | 1.2.1 | 0/0 | 32 | 648/648 | skip | 14283 | 1804 | 6.8 | 2.3 | 36 | 20 | **green** |

## Test suite

737 cases, up from 648 on the previous run — the +89 are characterization cases written against the CCN refactors before those refactors moved a line, which is why the two runs agree on behavior while the code underneath changed shape. Note the harness prints `N passed, N failed` without a total; the runner parses both shapes since kit revision 2, after the first adoption sweep recorded 0/0 here and still called it green. The generated inventory `test-cases.md` in each bundle is the authority on what exists at that point; the README badge tracks the same number.

## Lint

Clean over 32 files: 0 warnings, 0 errors. `luacheck .` runs over the addon's own source and its `tests/`; the vendored `libs/` and `tests/_kit/` are out of scope by config, since neither is this repo's to fix.

## Perf

This addon ships no `tests/perf.lua`, so the `perf` column is a permanent `skip` rather than a transient tooling gap. Two things follow, and both are standing facts rather than this run's news: the record says **nothing** about the addon's runtime cost, and `performance-§9`'s zero-overhead evidence — that bracketed instrumentation is free when capture is off — does not exist for it. Adding scenarios is the only thing that changes either.

## Complexity watch list

Current state as of [`20260804-214315`](20260804-214315/) — not that run's diff.
Every function `lizard` warned on, and every file at or above `layout-§1`'s 1000-LOC
on-notice threshold, each with a one-line disposition.

### Functions `lizard` warned on

**None.**

Every function in the addon is at or below CCN 15, so `lizard` warned on nothing. This is the result
of the `feat/fix-ccn` work, not an empty section: the twenty functions this table carried on
`20260804-182144` — `ReskinStructure` at 36 down through the four at 16 — were each split or
flattened behind characterization tests, and none of them survives in a form `lizard` flags. Their
old dispositions went with them; there is nothing left to carry forward.

Three functions now sit exactly on the line at CCN 15 — `Layout.layoutBlock`
(`modules/IconGrid_Layout.lua`), `buildSpecNameMaps` (`core/Util.lua`) and `OnAccept`
(`settings/Spells.lua`). They are under the threshold and are not entries on this list; they are
noted so a future run that reports a warning has somewhere obvious to look first.

What this table costs to keep at "None." is visible in the other one: the same refactors added 1147
NLOC and 247 functions, and every file in the band below grew. Zero warnings is not free, and the
place the bill lands is file size.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1314 | **Already tracked as `A-2`.** Up 18 on this run. The earlier downward trend (1473 → 1296 across two peels) has stopped: the CCN work put helper signatures back. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1172 | **Already tracked as `A-2`.** Up 125, the band's largest move, from peeling `buildRow` and `RefreshRows` into named helpers that stayed in this file. The next reduction has to be a file split — the in-file peel is spent. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1154 | **Already tracked as `A-2`.** Up 54 from the glow-gate and active-list peels. Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1066 | **Already tracked as `KCD-30`.** Up 17. Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender rather than trimming it. |

No file crossed a band boundary on this run and none is over the 1500 cap, but all four grew — the
band is worth reading as a group now rather than file by file.
