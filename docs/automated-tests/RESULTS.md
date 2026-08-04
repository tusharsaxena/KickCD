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
| [`20260804-182144`](20260804-182144/) | 1.2.1 | 0/0 | 32 | 648/648 | skip | 14283 | 1804 | 6.8 | 2.3 | 36 | 20 | **green** |

## Test suite

648 cases. Note the harness prints `N passed, N failed` without a total; the runner parses both shapes since kit revision 2, after the first adoption sweep recorded 0/0 here and still called it green. The generated inventory `test-cases.md` in each bundle is the authority on what exists at that point; the README badge tracks the same number.

## Lint

Clean over 32 files: 0 warnings, 0 errors. `luacheck .` runs over the addon's own source and its `tests/`; the vendored `libs/` and `tests/_kit/` are out of scope by config, since neither is this repo's to fix.

## Perf

This addon ships no `tests/perf.lua`, so the `perf` column is a permanent `skip` rather than a transient tooling gap. Two things follow, and both are standing facts rather than this run's news: the record says **nothing** about the addon's runtime cost, and `performance-§9`'s zero-overhead evidence — that bracketed instrumentation is free when capture is off — does not exist for it. Adding scenarios is the only thing that changes either.

## Complexity watch list

Current state as of [`20260804-182144`](20260804-182144/) — not that run's diff. Every function `lizard` warned on and every file in `layout-§1`'s 1000–1500 on-notice band, each with a one-line disposition.

`ReskinStructure` (36) — **peel next**, the longest non-generated body in the addon. `Castbar:DebugDump` (27), `Icon:Apply` (25, the one instrumented hot path), `IconGrid:RefreshAllGlows` (25) and `buildRow` (19, but 292 lines — **peel next**) are accepted with reasons recorded 2026-08-04, along with fifteen others.

**Files in the 1000–1500 band:** `modules/Castbar.lua` (1296), `modules/IconGrid.lua` (1100), `settings/Spells.lua` (1047) — all **already tracked as A-2**; `tests/wow_mock.lua` (1049) — **already tracked as KCD-30**.
