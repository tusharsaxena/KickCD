# Analysis — 20260927-030444

- **Addon:** KickCD 1.3.0 → 1.4.0 (release run)
- **Verdict:** green
- **Commit:** bcf9e51eb413c3d4c86f6e504f950f07845219da (master), clean
- **Previous run:** [`20260926-193108`](../20260926-193108/)

## Headline

The release run for **1.4.0**. It is green on all four suites with nothing skipped and zero functions
above CCN 15 ([`manifest.json`](manifest.json)), so all five release-gate conditions hold. Since the
previous run the tree changed only in documentation and comments (the README passes, the sync-docs
record and two comment-citation fixes), and every figure is the same as it was apart from perf
timings, which moved by thousandths of a millisecond. Nothing new to act on: the nine band files are
unchanged and each is already tracked.

## Suites

Every row links its artifact, so a reader can get from a figure to the evidence in one click. A
skipped suite links nothing — there is no artifact — and says what was not measured.

| Suite | Status | Result | Artifact | Moved since `20260926-193108` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 112 files | [`lint.txt`](lint.txt) | unchanged |
| tests | pass | 1201 passed, 0 skipped, 0 failed, 1201 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | unchanged |
| perf | pass | 6 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged; see below |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | unchanged |

**Complexity is reported in full**, because a single figure cannot be compared across a change in
size. All values from [`manifest.json`](manifest.json)'s `suites.complexity`, footer in
[`complexity.txt`](complexity.txt):

| Metric | Value |
|---|---|
| Total NLOC | 24073 |
| Functions | 3089 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.0 |
| Max CCN | 15 |
| Avg tokens / function | 51.4 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 9 |
| Files over the 1500 cap | 0 |

Every suite is a clean pass, so there is no failure paragraph to write. The release gate, read from
this manifest: lint pass (0/0), tests pass with 0 failed, perf pass (6 scenarios, measured rather
than skipped), complexity pass, and 0 functions above CCN 15.

## What moved

- **lint:** 112 files, 0 warnings / 0 errors, the same as the previous run ([`lint.txt`](lint.txt)).
- **tests:** 1201 → 1201 ([`tests.txt`](tests.txt)). Nothing changed that a case could observe:
  the commits since the previous run touched `README.md`, the sweep's docs and two comments
  (`.luacheckrc`, `tests/test_lifecycle.lua`). The count has been flat across three runs because
  those runs measured documentation and move-only commits, not an addon that grew without tests.
- **perf:** the same six scenarios and the same `api/iter` in every row. `spellPoll` read
  0.01928 ms/iter and 906.3 bytes/iter against 0.01623 and 905.0; `spellState` 0.00679 against
  0.00551; `castStart` 0.00590 against 0.00531; `iconApply`, `probeOverheadOff` and
  `probeOverheadOn` moved by under 0.0004 ms either way ([`perf.txt`](perf.txt)). No executable line
  changed between the two runs, so this is run-to-run timing noise, not a behavior change.
- **complexity:** NLOC 24073, functions 3089, averages 6.7 NLOC / 2.0 CCN / 51.4 tokens, max CCN 15,
  0 warnings, all identical to the previous run ([`complexity.txt`](complexity.txt)).
- **band:** the same nine files at the same LOC.

Against the previous **release** run (`20260910-234511`, 1.2.1 → 1.3.0), the 1.4.0 cycle took the
suite from 870 to 1201 cases, lint scope from 94 to 112 files and NLOC from 18164 to 24073 over
2288 → 3089 functions, while avg CCN went from 2.1 to 2.0 and max CCN stayed at 15. The addon grew
by about a third and got no denser.

## Complexity watch list

**Functions warned on (CCN > 15):**

| Function | CCN | Location | Disposition |
|---|---|---|---|
| None. | | | |

None, by construction: this is a release run that passed the zero-CCN>15 gate.

**Files by `layout-§1` band:**

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `core/Database.lua` | 1069 | Already tracked as #29 |
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1217 | Already tracked as #24 |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1381 | Already tracked as #25 (closest to the cap) |
| 1000–1500 (on notice) | `modules/IconGrid_Render.lua` | 1014 | Already tracked as #26 |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1115 | Already tracked as #28 |
| 1000–1500 (on notice) | `tests/test_options_panel.lua` | 1101 | Already tracked as #31 |
| 1000–1500 (on notice) | `tests/test_perfsetup.lua` | 1018 | Already tracked as #32 |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1035 | Already tracked as #30 |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1233 | Already tracked as #27 |

Nothing newly crossed. Every entry carries a tracked issue rather than an *Accepted* disposition, so
none is owed a fix under anti-pattern #53's three-release rule. The full dispositions, refreshed to
this run, are in [`../RESULTS.md`](../RESULTS.md).

## Actions

None new. The standing peels are #24–#32, one per band file. Take #25 first
(`modules/IconGrid.lua`, the visibility and glow gate into `modules/IconGrid_Visibility.lua`),
because that file is the closest to the cap, 119 lines below it.
