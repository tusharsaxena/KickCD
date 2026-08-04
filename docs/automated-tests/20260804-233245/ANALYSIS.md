# Analysis — 20260804-233245

- **Addon:** KickCD 1.2.1
- **Verdict:** green
- **Commit:** 5eca94079020 (feat/fix-ccn), **dirty**
- **Started:** 2026-08-04T23:32:45+05:30
- **Previous run:** [`20260804-214315`](../20260804-214315/)

## Headline

This is the run that closes the CCN work, and it closes it by finally being able to *say* so. Both
gating suites are clean — `luacheck` 0 warnings / 0 errors over 32 files, and the headless harness
737 of 737 cases — and the complexity suite reports **zero functions above CCN 15 with a measured
ceiling of 15**. The previous run had the same code and the same zero warnings, but the instrument
could not report the peak: testkit rev 5 derived `maxCcn` from `lizard`'s "!!!! Warnings" block, so
an addon that reached zero warnings recorded `"maxCcn": 0`. Rev 6, vendored into the working tree
that produced this bundle, reads the ceiling from the per-function table instead. Nothing about the
addon moved between the two runs; the measurement did. Nothing to act on.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260804-214315` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 32 files | [`lint.txt`](lint.txt) | unmoved — byte-identical to the previous run's `lint.txt` |
| tests | pass | 737 passed, 0 failed, 737 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | unmoved — 737/737 in both, and both inventories are byte-identical |
| perf | skip | — (not run) | — no artifact | unmoved — still no `tests/perf.lua`, so still nothing measured |
| complexity | pass | 0 warnings, max CCN 15 (see below) | [`complexity.txt`](complexity.txt) | **Max CCN 0 → 15 — the instrument, not the code** |

### Complexity in full

Every field of `lizard`'s footer as [`manifest.json`](manifest.json) records it under
`suites.complexity`, plus the two derived file counts. The **averages** are the comparable figures:
totals move whenever the addon changes size, and only an average that moves is a complexity signal.

| Metric | Value |
|---|---|
| Total NLOC | 15430 |
| Functions | 2051 |
| Avg NLOC / function | 6.5 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 48.9 |
| Warnings (CCN > 15) | 0 |
| Warning rate — `Fun Rt` / `nloc Rt` | 0.00 / 0.00 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

[`complexity.txt`](complexity.txt)'s footer agrees line for line — `Total nloc 15430`, `Avg.NLOC 6.5`,
`AvgCCN 2.1`, `Avg.token 48.9`, `Fun Cnt 2051`, `Warning cnt 0`, `Fun Rt 0.00`, `nloc Rt 0.00` — and
its threshold line reads `No thresholds exceeded (cyclomatic_complexity > 15 …)`.

`tests/perf.lua` is absent, so the `perf` suite ran nothing at all. That is a **skip, not a pass**:
`manifest.json` records `"status": "skip"` with the reason `no tests/perf.lua — this addon ships no
offline scenarios`, and this run therefore says nothing whatsoever about the addon's runtime cost.

This bundle was captured from a **dirty** working tree (`git.dirty: true` in
[`manifest.json`](manifest.json)). It is not a clean snapshot of commit `5eca940`: the tree also held
the uncommitted LibKa0s v1.7.0 / testkit rev 6 re-vendor, which is exactly why this run could report
a ceiling the previous one could not. The re-vendor landed immediately afterwards as `a6d807e`.

## What moved

- **lint** — unmoved. 0 warnings / 0 errors over 32 files. [`lint.txt`](lint.txt) is byte-identical
  to the previous run's.
- **tests** — unmoved. 737 passed, 0 failed. [`tests.txt`](tests.txt) and
  [`test-cases.md`](test-cases.md) are both byte-identical to the previous run's, so not one case was
  added, removed or renamed between the two.
- **perf** — unmoved, and unmovable until scenarios exist. Still a skip.
- **complexity** — every figure unmoved except one. Total NLOC 15430, functions 2051, avg NLOC 6.5,
  avg CCN 2.1, avg tokens 48.9, warnings 0, both warning rates 0.00, band files 4, over-cap files 0 —
  all identical to `20260804-214315`. The single change is **Max CCN 0 → 15**, and it is not a
  regression: the previous bundle's own [`complexity.txt`](../20260804-214315/complexity.txt) already
  listed five functions at CCN 15, so 15 was the true ceiling then too. Rev 5 of the kit read
  `CCN_MAX` out of the warnings block, which is empty at zero warnings, and printed the `0`. Anyone
  reading the trend column as `36 → 0 → 15` is reading an instrument fault in the middle position.
- **the code itself** — the two bundles' `complexity.txt` differ on exactly nine lines, all in
  `modules/Castbar_Skin.lua` and all a one-line offset (`structureSignature@154-167` →
  `@155-168`, and the eight functions below it). That is the Reskin pointer comment added in
  `5eca940`; no function changed shape.
- **size** — unmoved. The +1147 NLOC and +247 functions that the CCN refactors cost were paid on the
  previous run and are already in the baseline.

## Complexity watch list

### Functions `lizard` warned on

**None.** [`complexity.txt`](complexity.txt) ends with `No thresholds exceeded` and `Warning cnt 0`.

Five functions sit exactly on the line at CCN 15, and this run is the first that can name that
ceiling from `manifest.json` rather than by reading the table by hand. In
[`complexity.txt`](complexity.txt) order:

| Function | CCN | Location |
|---|---|---|
| `State.ApplyInterruptibleAlpha` | 15 | `core/State.lua:99-118` |
| `buildSpecNameMaps` | 15 | `core/Util.lua:232-269` |
| `StateChanged` | 15 | `modules/Cooldowns.lua:250-279` |
| `Layout.layoutBlock` | 15 | `modules/IconGrid_Layout.lua:145-249` |
| `OnAccept` | 15 | `settings/Spells.lua:481-504` |

They are **at** the threshold, not over it, so none of them is an entry on this list. They are named
in full because a partial list is the thing that goes stale silently: a future run that reports a
warning has five specific places to look first, and the next person to touch any of them has one
line of headroom.

### Files by `layout-§1` band

The count is [`manifest.json`](manifest.json)'s `bandFiles: 4` and `overCapFiles: 0`; the per-file
LOC are `wc -l` at the recorded commit, since `lizard` reports NLOC rather than raw lines.

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1314 | **Already tracked as `A-2`.** Unmoved on this run. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1172 | **Already tracked as `A-2`.** Unmoved. The previous run's reading still stands: the in-file peel is spent, and the next reduction has to be a file split. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1154 | **Already tracked as `A-2`.** Unmoved. Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1066 | **Already tracked as `KCD-30`.** Unmoved. Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender. |

Nothing newly crossed a band boundary and no file is over the 1500 cap.

## Actions

None arising from this run. Two readings to carry forward:

1. `20260804-182144` and `20260804-214315` were produced by testkit rev 5 and their `Max CCN` cells
   are not trustworthy at zero warnings — `20260804-214315` records `0` where its own
   [`complexity.txt`](../20260804-214315/complexity.txt) says 15. Those bundles stand as written
   (`automated-tests-§1`); `RESULTS.md`'s standing prose carries the annotation so the trend column
   is readable.
2. `perf` remains a permanent skip. Nothing in this record, or in the two before it, is evidence
   about runtime cost, and `performance-§9`'s zero-overhead evidence does not exist for this addon.
