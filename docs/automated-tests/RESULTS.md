# Automated test results

<!-- The newest run is prepended by tests/_kit/run-automated-tests.sh. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

| Run | Version | Lint w/e | Tests | Perf | CCN warn | Max CCN | Verdict |
|---|---|---|---|---|---|---|---|
| [`20260804-122616`](20260804-122616/) | 1.2.1 | 0/0 | 648/648 | skip | 20 | 36 | **green** |

## Complexity watch list

Current state as of [`20260804-122616`](20260804-122616/) — not that run's diff.
Every function `lizard` warned on and every file in `layout-§1`'s 1000–1500 on-notice band,
each with a one-line disposition.

`ReskinStructure` (36) — **peel next**, the longest non-generated body in the addon. `Castbar:DebugDump` (27), `Icon:Apply` (25, the one instrumented hot path), `IconGrid:RefreshAllGlows` (25) and `buildRow` (19, but 292 lines — **peel next**) are accepted with reasons recorded at 2026-08-04, along with fifteen others.

**Files in the 1000–1500 band:** `modules/Castbar.lua` (1296), `modules/IconGrid.lua` (1100), `settings/Spells.lua` (1047) — all **already tracked as A-2**; `tests/wow_mock.lua` (1049) — **already tracked as KCD-30**.
