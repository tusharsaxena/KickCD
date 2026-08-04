# Analysis — 20260804-182144

- **Addon:** KickCD 1.2.1
- **Verdict:** green
- **Commit:** de662229e931 (master), dirty
- **Started:** 2026-08-04T18:21:44+05:30
- **Previous run:** none — this is the first recorded run

## Headline

The first automated-test record for this addon, produced while adopting `automated-tests`
(standard v2.19.0). Both gating suites are clean: `luacheck` reports 0 warnings / 0 errors across
32 files and the headless harness passes 648 of 648 cases. The offline perf runner is absent (see below). Every figure below is a **baseline** —
there is no previous run to diff against, so nothing here is a regression and nothing is an
improvement.

## Suites

| Suite | Status | Result | Artifact | Moved since previous run |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 32 files | [`lint.txt`](lint.txt) | — first run |
| tests | pass | 648 passed, 0 failed, 648 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | — first run |
| perf | skip | — | — (not run) | — first run |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | — first run |

### Complexity in full

Every field of `lizard`'s footer, plus the two derived file counts. The **averages** are what make
this run comparable to the next one across a change in size: a total that rises because the addon
grew is a different fact from an average that rises because it got denser, and only the second is a
complexity signal.

| Metric | Value |
|---|---|
| Total NLOC | 14283 |
| Functions | 1804 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.3 |
| Max CCN | 36 |
| Avg tokens / function | 51.5 |
| Warnings (CCN > 15) | 20 |
| Warning rate — `Fun Rt` / `nloc Rt` | 0.01 / 0.07 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

`tests/perf.lua` is absent — this addon ships no offline scenarios, so nothing was measured there. That is a **skip, not a pass**: it is recorded as one in `manifest.json`, and it means this run says nothing about the addon's runtime cost.

## What moved

**First run — nothing to diff against; every figure above is a baseline reading.** The next run is
the first one that can say something moved, and this record is what it will be read against.

## Complexity watch list

`ReskinStructure` (36) — **peel next**, the longest non-generated body in the addon. `Castbar:DebugDump` (27), `Icon:Apply` (25, the one instrumented hot path), `IconGrid:RefreshAllGlows` (25) and `buildRow` (19, but 292 lines — **peel next**) are accepted with reasons recorded 2026-08-04, along with fifteen others.

**Files in the 1000–1500 band:** `modules/Castbar.lua` (1296), `modules/IconGrid.lua` (1100), `settings/Spells.lua` (1047) — all **already tracked as A-2**; `tests/wow_mock.lua` (1049) — **already tracked as KCD-30**.

## Actions

None arising from this run. The dispositions above are carried forward from the complexity reports
written against the same measurements earlier today; each was recorded with its evidence at the
time, and none is new here.
