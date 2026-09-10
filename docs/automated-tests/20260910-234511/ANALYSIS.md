# Analysis — 20260910-234511

- **Addon:** KickCD 1.2.1 → 1.3.0
- **Verdict:** green
- **Commit:** 1fee09855098 (master), clean
- **Previous run:** [`20260908-181321`](../20260908-181321/)

## Headline

The release run for **1.3.0**, green on all four suites with zero functions above CCN 15. Ten new test cases and 359 more NLOC — the largest source growth of the nine this cycle, and it is the per-spell GCD attribution work. Averages moved by one decimal place; nothing is denser in any way that matters.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260908-181321` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 94 files | [`lint.txt`](lint.txt) | see below |
| tests | pass | 870 passed, 0 skipped, 0 failed, 870 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | see below |
| perf | pass | 6 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | unchanged |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

| Metric | Value |
|---|---|
| Total NLOC | 18164 |
| Functions | 2288 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 50.8 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.0 / 0.0 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

## What moved

- **lint** — 94 files, up one from 93. Still 0 warnings / 0 errors.
- **tests** — 870 passed, up 10 from 860. No skips, no failures.
- **perf** — 6 scenarios, unchanged.
- **complexity** — NLOC 17805 → 18164 (+359) over 2268 → 2288 functions (+20). Avg NLOC 6.6 → 6.7 and avg tokens 50.4 → 50.8, both consistent with 20 new functions rather than with existing ones thickening. Avg CCN flat at 2.1, max CCN flat at 15, zero warnings. Four band files in both runs, none over the cap.

## Complexity watch list

Both tables are maintained in [`RESULTS.md`](../RESULTS.md), which the runner regenerates whole on every run; the **Disposition** column there is the authored half and is current as of this run.

### Functions `lizard` warned on

None. Zero functions above CCN 15 is what the release gate required, and it is what this run measured — max CCN 15.

### Files by `layout-§1` band

4 file(s) in the 1000–1500 on-notice band, 0 over the 1500 cap. Each carries a disposition in [`RESULTS.md`](../RESULTS.md#files-by-layout-1-band). The band is not part of the release gate.

## Actions

None. All four band entries carry current dispositions; three are owned by `A-2` and `tests/wow_mock.lua` by `KCD-30`. `settings/Spells.lua` remains the fastest-growing of them and is worth re-reading at 1400.
