# Analysis — 20260804-114812

- **Addon:** KickCD 1.2.1
- **Verdict:** green
- **Commit:** 101337d4a52a (master), dirty
- **Previous run:** none — this is the first recorded run

## Headline

The first automated-test record for this addon, produced while adopting `automated-tests`
(standard v2.19.0). Both gating suites are clean: `luacheck` reports 0 warnings / 0 errors across
32 files and the headless harness passes 648 of 648 cases. The offline perf runner is absent (see below). Every figure below is a **baseline** —
there is no previous run to diff against, so nothing here is a regression and nothing is an
improvement.

## Suites

| Suite | Status | Result | Moved since previous run |
|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 32 files (`lint.txt`) | — first run |
| tests | pass | 648 passed, 0 failed, 648 total (`tests.txt`) | — first run |
| perf | skip | skip | — first run |
| complexity | pass | 20 warnings, max CCN 36, 14283 NLOC / 1804 functions (`complexity.txt`) | — first run |

`tests/perf.lua` is absent — this addon ships no offline scenarios, so nothing was measured here. That is a **skip, not a pass**: it is recorded as one in `manifest.json`, and it means this run says nothing about the addon's runtime cost.

## What moved

**First run — nothing to diff against; every figure above is a baseline reading.** The next run is
the first one that can say something moved, and this record is what it will be read against.

## Complexity watch list

`ReskinStructure` (36) — **peel next**, the longest non-generated body in the addon. `Castbar:DebugDump` (27), `Icon:Apply` (25, the one instrumented hot path), `IconGrid:RefreshAllGlows` (25) and `buildRow` (19, but 292 lines — **peel next**) are accepted with reasons recorded at 2026-08-04, along with fifteen others.

**Files in the 1000–1500 band:** `modules/Castbar.lua` (1296), `modules/IconGrid.lua` (1100), `settings/Spells.lua` (1047) — all **already tracked as A-2**; `tests/wow_mock.lua` (1049) — **already tracked as KCD-30**.

## Actions

None arising from this run. The dispositions above are carried forward from the complexity reports
written against the same measurements earlier today; each was recorded with its evidence at the
time, and none is new here.
