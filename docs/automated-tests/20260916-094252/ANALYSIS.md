# Analysis — 20260916-094252

- **Addon:** KickCD 1.3.0
- **Verdict:** green
- **Commit:** 880c80b5d31d (master), clean
- **Previous run:** [`20260910-234511`](../20260910-234511/)

## Headline

Green on all four suites, zero functions above CCN 15. The post-release cycle — LibKa0s v1.37.0/v1.38.0 re-vendors, test mode added then removed in favour of the Lock-frame switch — added 66 test cases and 1181 NLOC while the two largest authored files in the on-notice band got *smaller*: `settings/Spells.lua` 1312 → 1246 and `tests/wow_mock.lua` 1245 → 1027. Nothing newly crossed a threshold and there is nothing to act on.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260910-234511` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 95 files | [`lint.txt`](lint.txt) | +1 file, still 0/0 |
| tests | pass | 936 passed, 0 skipped, 0 failed, 936 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | +66 cases |
| perf | pass | 6 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged; allocations moved, see below |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

**Complexity metrics** (all from [`manifest.json`](manifest.json), footer in [`complexity.txt`](complexity.txt)):

| Metric | Value |
|---|---|
| Total NLOC | 19345 |
| Functions | 2390 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 51.8 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

Every suite ran. Nothing was skipped, so no figure here stands in for an unmeasured state; `luacheck` 1.2.0, `lizard` 1.24.0 and Lua 5.1.5 are all recorded in the manifest's `host` block.

## What moved

- **lint** — 94 → 95 files in scope, still 0 warnings / 0 errors ([`lint.txt`](lint.txt)). The extra file is the growth of the tree, not a change in `.luacheckrc` scope.
- **tests** — 870 → 936 passed (+66), 0 skipped, 0 failed ([`tests.txt`](tests.txt)). Passed and total agree, so the count claims no coverage it did not exercise. The inventory is [`test-cases.md`](test-cases.md).
- **perf** — 6 scenarios in both runs ([`perf.txt`](perf.txt)). Timings are within noise of the previous run and are orientation-only by the runner's own caveat, but two allocation figures inverted: `spellPoll` 528.1 → 66.4 bytes/iter and `spellState` 209.7 → 661.5. The per-iteration API count for `spellPoll` is unchanged at 18.0, so this reads as allocation moving from the poll into the state build rather than as new work; it is recorded, not actioned.
- **complexity** — NLOC 18164 → 19345 (+1181) over 2288 → 2390 functions (+102). Avg NLOC 6.7 → 6.8 and avg tokens 50.8 → 51.8: the total rose because the addon grew, and the averages moved by one decimal, which is growth in count rather than density. Avg CCN flat at 2.1, max CCN flat at 15, warning count and both warning rates flat at zero. Four band files in both runs, none over the cap — but two of the four shrank (see below), which is the first cycle in this record where band LOC fell.

## Complexity watch list

Both tables are maintained in [`RESULTS.md`](../RESULTS.md), which the runner regenerates whole on every run; the **Disposition** column there is the authored half and is current as of this run.

### Functions `lizard` warned on

None. Max CCN measured at 15, which is at the line and not over it ([`complexity.txt`](complexity.txt) footer). That zero is measured, not assumed — `lizard` 1.24.0 ran to completion.

### Files by `layout-§1` band

4 file(s) in the 1000–1500 on-notice band, 0 over the 1500 cap. `modules/Castbar.lua` (1345) and `modules/IconGrid.lua` (1163) are unchanged from the previous run. `settings/Spells.lua` fell 1312 → 1246 and `tests/wow_mock.lua` fell 1245 → 1027 — the first reductions either has recorded, consistent with the test-mode removal in `861d5a4`. Nothing newly crossed. The band is not part of the release gate.

**Shelf life.** All four entries have now been carried as tracked-and-accepted across three consecutive runs (`20260908-181321`, `20260910-234511`, this one). Three are owned by `A-2` and `tests/wow_mock.lua` by `KCD-30`, so each has an ID and an owner rather than a bare "accepted" — the `automated-tests-§4` shelf-life rule is satisfied by the tracking, not by the repetition. `settings/Spells.lua`'s re-check point stays at 1400 and `modules/Castbar.lua`'s at 1450.

## Actions

None.
