# Analysis — 20260807-022824

- **Addon:** KickCD 1.2.1
- **Verdict:** green
- **Commit:** f658a2583b7e32c0d6399ae30750188c3908639e (master), dirty
- **Previous run:** [`20260804-233245`](../20260804-233245/)

## Headline

All four suites ran and all four passed — the first run in this record with **no skipped suite at
all**. The change that makes it so is `perf`: this addon now ships `tests/perf.lua`, so the column
that read `skip` on every previous row reads `pass` over 5 scenarios, and the record stops being
silent about runtime cost. Nothing regressed; the test suite grew by 19 cases and lint gained a
33rd file, while every complexity average held exactly where it was.

## Suites

Every row links its artifact, so a reader can get from a figure to the evidence in one click.

| Suite | Status | Result | Artifact | Moved since `20260804-233245` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 33 files | [`lint.txt`](lint.txt) | +1 file checked (32 -> 33); still 0/0 |
| tests | pass | 756 passed, 0 skipped, 0 failed, 756 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | +19 cases (737 -> 756); still zero failures, zero skips |
| perf | pass | 5 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | **skip -> pass.** First run to measure this addon at all |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | 0 warnings held; +103 NLOC, +8 functions, averages flat |

**Complexity is reported in full**, because a single figure cannot be compared across a change in
size. Every value below comes from [`manifest.json`](manifest.json)'s `suites.complexity`, which
records all eight of `lizard`'s footer fields; the footer itself is at the end of
[`complexity.txt`](complexity.txt).

| Metric | Value |
|---|---|
| Total NLOC | 15533 |
| Functions | 2059 |
| Avg NLOC / function | 6.5 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 48.8 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

Every suite is a clean pass, so there is no failing-suite paragraph to write here. The one thing
worth naming is what is **not** in scope rather than what failed: `.luacheckrc` excludes `tests/`,
so the 52 `.lua` files of the harness — including the new `tests/perf.lua` — are not among the 33
files `lint` checked. See `RESULTS.md`'s **Lint** section for the full exclusion list.

## What moved

- **lint** — 32 -> **33** files checked, still 0 warnings / 0 errors
  ([`lint.txt`](lint.txt)). The extra file is `defaults/Spells.lua`; the linted scope is now
  `core/` 11, `settings/` 11, `modules/` 8, `defaults/` **2**, `locales/` 1.
- **tests** — 737 -> **756** cases (+19), still 0 failed and 0 skipped
  ([`tests.txt`](tests.txt)). The inventory that enumerates them is
  [`test-cases.md`](test-cases.md).
- **perf** — **`skip` -> `pass`**, and this is the run's real news. Every earlier row carries
  `skipReason: "no tests/perf.lua — this addon ships no offline scenarios"`; the file now exists,
  and 5 scenarios ran ([`perf.txt`](perf.txt), [`perf.json`](perf.json)). Two of the five —
  `probeOverheadOff` at 0.00229 ms/iter and `probeOverheadOn` at 0.00253 ms/iter — are the pair
  that answers `performance-§9`'s zero-overhead question, which this record could not answer at all
  before today.
- **complexity** — Total NLOC 15430 -> **15533** (+103) and functions 2051 -> **2059** (+8), so the
  addon grew. The averages did **not** move with it: avg NLOC/function held at **6.5**, avg CCN
  held at **2.1**, and avg tokens/function went 48.9 -> **48.8**. Growth without densification is
  the reading. Max CCN held at **15** and the warning count held at **0**.
- **band files** — still **4** in the 1000–1500 band and **0** over the 1500 cap. Within the band,
  three files shrank slightly and one grew: `tests/wow_mock.lua` 1066 -> **1101** (+35), against
  `modules/Castbar.lua` 1305 (-9), `settings/Spells.lua` 1171 (-1) and `modules/IconGrid.lua` 1153
  (-1). Nothing crossed a boundary.

## Complexity watch list

### Functions `lizard` warned on

**None.** No function in the addon exceeds CCN 15, so `lizard` warned on nothing — the footer of
[`complexity.txt`](complexity.txt) reads `No thresholds exceeded`.

The same **five** functions sit exactly on the line at CCN 15, unchanged in membership since
`20260804-233245`, in [`complexity.txt`](complexity.txt) order:
`State.ApplyInterruptibleAlpha` (`core/State.lua:99-118`), `buildSpecNameMaps`
(`core/Util.lua:232-269`), `StateChanged` (`modules/Cooldowns.lua:250-279`), `Layout.layoutBlock`
(`modules/IconGrid_Layout.lua:145-249`) and `OnAccept` (`settings/Spells.lua:480-503`). Only the
last has moved, and only by one line of offset. They are at the threshold, not over it, so none is
an entry on this list; they are named so that a future run reporting a warning has five obvious
places to look, and so that whoever edits one next knows there is exactly one line of headroom.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1305 | **Already tracked as `A-2`.** Down 9 since the previous run. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1171 | **Already tracked as `A-2`.** Down 1. The in-file peel is spent; the next reduction has to be a file split. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1153 | **Already tracked as `A-2`.** Down 1. Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1101 | **Already tracked as `KCD-30`.** **Up 35 — the only band file that grew.** Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender rather than trimming it. `luacheck` never sees it. |

Nothing newly crossed a band boundary and nothing is over the 1500 cap. No entry here is carried as
bare *Accepted* — all four point at a tracked deviation (`A-2`, `KCD-30`), so the
`automated-tests-§4` shelf-life rule has nothing outstanding against it.

## Actions

1. **`tests/wow_mock.lua` is the only thing in the band trending upward** (1066 -> 1101 LOC, +35)
   while the three source files beside it shrank. It is already tracked as `KCD-30`, so this is not
   a new finding — but the tracked fix (rebuild as a thin extender) has not started, and the file
   is now within 400 lines of the 1500 cap. Worth scheduling rather than carrying another run.
2. **`RESULTS.md`'s `## Perf` section needed a rewrite, not a refresh.** It asserted that the addon
   ships no `tests/perf.lua`; that is now false. Handled in this run's `RESULTS.md` update.
