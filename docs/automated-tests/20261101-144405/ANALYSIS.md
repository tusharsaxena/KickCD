# Analysis — 20261101-144405

- **Addon:** KickCD 1.5.0
- **Verdict:** green
- **Commit:** 90bebccbcfde00809c131dfe0a558897e855a596 (feat/2026-11-01-full-skinning)
- **Previous run:** 20261101-025914

## Headline

All four suites pass with LibKa0s v1.85.0 and the HUD's colors and shadows on the skin: lint 0/0 over 155 files, 1609 of 1610 cases passed with none failed and one declared skip, 7 perf scenarios measured, and no function above CCN 15 on a sighted run (`blindFiles` 0, `crashedFiles` 0). The case total rose by 27, all in the new `tests/test_skin_flip.lua`, and the tree gained 797 NLOC and 91 functions. No threshold was crossed.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261101-025914 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 155 files | [`lint.txt`](lint.txt) | one more file |
| tests | pass | 1609 passed, 1 skipped, 0 failed, 1610 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 27 cases added |
| perf | pass | 7 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged at 7; see What moved |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see What moved |

| Metric | Value |
|---|---|
| Total NLOC | 33956 |
| Functions | 4663 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 55.5 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 2 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

Every value above is from `manifest.json`. The complexity run is sighted: `blindFiles` and `crashedFiles` are both present and 0.

The one skip is pre-existing and does not count toward `passed`. It is the diagnostics contract case for an addon that opts out of logging (`tests.txt`): KickCD keeps the default, so its report turns logging on and the case above it holds that behavior.

## What moved

- **lint:** 0 warnings / 0 errors, 154 → 155 files. The new file is `tests/test_skin_flip.lua`; `libs/` and `tests/_kit/` stay excluded, so the re-vendored payload is not in that count.
- **tests:** 1583 → 1610 total, 1582 → 1609 passed, 0 failed, 1 skipped. The 27 added cases are the flip's: companions and defaults, Ka0s Default's pixels, a skin switch through spies on the drawing setters, the shadow's font object and cache, gloss on the kit's paint recorder, the Spells rows' mark and the v8 → v9 step on stored partial profiles. Earlier ladder cases seed `skin.fullSkinReset` true, because the new step writes the same keys.
- **perf:** 7 scenarios in both runs. `api/iter` is unchanged in every scenario, so no scenario makes a new client call. `bytes/iter` is unchanged in six scenarios and fell in one, `spellPoll` 412.0 → 306.9. `ms/iter`: `spellPoll` 0.02520 → 0.03028, `spellState` 0.00081 → 0.00132, `iconApply` 0.00026 → 0.00033, `probeOverheadOff` 0.00024 → 0.00043, `probeOverheadOn` 0.00039 → 0.00089, `castStart` 0.00596 → 0.01770, `cdText` 0.00361 → 0.00562. Every scenario slowed, including the two probe scenarios that no change here touches, and this run took place with other addons' batteries running on the same machine, which the runner's timing note warns about. `castStart` moved most and is also where this change adds work: each state now asks the skin for the spell name's color. Its share of the move was not measured.
- **complexity:** NLOC 33159 → 33956 and functions 4572 → 4663. Avg NLOC/function 6.8, avg CCN 2.1 and max CCN 15 did not move, avg tokens 54.9 → 55.5, 0 warnings. The total rose because the tree grew; the averages say it did not get denser.
- **band files:** 2 in both runs, over-cap files 0 in both runs. `core/Database_Migrations.lua` rose to 660 lines and `modules/IconGrid_Render.lua` to 980, the second close to the 1000 line of the band.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1023 | Accepted — 475 NLOC in 60 functions; the rest is comments and blanks, one cohesive per-unit grid manager already peeled twice |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1047 | Accepted — case count, not tangle: 648 NLOC of individual schema cases |

Neither row is new. This is not a release run, so neither has gained an Accepted reading toward the three-release limit.

## Actions

1. `modules/IconGrid_Render.lua` is at 980 lines. The next addition there should come with a peel, before it enters the band.
2. Carried from 20261101-025914: the 648 NLOC in the `tests/test_schema.lua` disposition predates that run's growth.
