# Analysis — 20260926-193108

- **Addon:** KickCD 1.3.0
- **Verdict:** green
- **Commit:** 99211f0f1155c51855b4cbf00f5564570e356b41 (feat/2026-09-26-automated-tests-sweep), clean
- **Previous run:** [`20260926-160251`](../20260926-160251/)

## Headline

Green on all four suites, nothing skipped, and no function above CCN 15 ([`manifest.json`](manifest.json)).
This is the automated-tests sweep's closing run, three commits after the sweep run's `cdff980`: the
sweep's own record (KC-ATS-00), the LibKa0s v1.62.0 re-vendor (KC-ATS-RV) and the Castbar peel
(KC-ATS-01). The one movement that matters is `modules/Castbar.lua`, 1440 → 1217, which takes what was
the repo's closest-to-cap file 223 lines further from the cap. Tests held at 1201. The band still holds
the same nine files and no entry is new, so there is nothing to act on beyond the peels already tracked.

## Suites

Every row links its artifact, so a reader can get from a figure to the evidence in one click. A
skipped suite links nothing — there is no artifact — and says what was not measured.

| Suite | Status | Result | Artifact | Moved since `20260926-160251` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 112 files | [`lint.txt`](lint.txt) | +1 file in scope (`modules/Castbar_Events.lua`), still 0/0 |
| tests | pass | 1201 passed, 0 skipped, 0 failed, 1201 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | unchanged |
| perf | pass | 6 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged; see below |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

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

Every suite is a clean pass, so there is no failure paragraph to write. Perf and complexity are
recorded and gate neither the run nor the commit; as measured here both would satisfy the tag gate
(four suites at pass, zero functions above CCN 15).

## What moved

- **lint:** 111 → 112 files in scope, the new `modules/Castbar_Events.lua`; still 0 warnings / 0 errors ([`lint.txt`](lint.txt)).
- **tests:** 1201 → 1201. The Castbar peel was a move and added no case; the existing 1500-LOC cap
  case now reaches the new file ([`tests.txt`](tests.txt)).
- **perf:** same six scenarios, same `api/iter` in every row. `spellPoll` read 0.01623 ms/iter and
  905.0 bytes/iter against 0.01774 and 921.4; the other five moved by a few thousandths of a
  millisecond either way ([`perf.txt`](perf.txt)). Timings are for orientation within a run, not a
  cross-run signal, and nothing here reads as a change in behavior.
- **complexity:** NLOC 24060 → 24073 (+13, the module-table exports and upvalue bindings the peel
  needed), functions 3089 → 3089, and every average unchanged (6.7 NLOC, 2.0 CCN, 51.4 tokens). Max
  CCN held at 15 and warnings at 0 ([`complexity.txt`](complexity.txt)).
- **band:** the same nine files. `modules/Castbar.lua` 1440 → 1217; the other eight are at the same
  LOC as the previous run. `modules/IconGrid.lua` (1381) is now the file closest to the cap.

## Complexity watch list

**Functions warned on (CCN > 15):**

| Function | CCN | Location | Disposition |
|---|---|---|---|
| None. | | | |

**Files by `layout-§1` band:**

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `core/Database.lua` | 1069 | Already tracked as #29 |
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1217 | Already tracked as #24 (peeled 1440 → 1217 by KC-ATS-01) |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1381 | Already tracked as #25 (now closest to the cap) |
| 1000–1500 (on notice) | `modules/IconGrid_Render.lua` | 1014 | Already tracked as #26 |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1115 | Already tracked as #28 |
| 1000–1500 (on notice) | `tests/test_options_panel.lua` | 1101 | Already tracked as #31 |
| 1000–1500 (on notice) | `tests/test_perfsetup.lua` | 1018 | Already tracked as #32 |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1035 | Already tracked as #30 |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1233 | Already tracked as #27 |

Nothing newly crossed. The full dispositions, refreshed to this run's figures, are in
[`../RESULTS.md`](../RESULTS.md).

## Actions

None new. The standing peels are #24–#32, one per band file. The one to take first is #25
(`modules/IconGrid.lua`, the visibility and glow gate into `modules/IconGrid_Visibility.lua`), because
that file is now the closest to the cap.
