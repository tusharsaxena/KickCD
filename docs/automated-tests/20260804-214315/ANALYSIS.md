# Analysis — 20260804-214315

- **Addon:** KickCD 1.2.1
- **Verdict:** green
- **Commit:** d0b58071f3af (feat/fix-ccn), clean
- **Started:** 2026-08-04T21:43:15+05:30
- **Previous run:** [`20260804-182144`](../20260804-182144/)

## Headline

The `feat/fix-ccn` branch's record. Both gating suites are clean — `luacheck` 0 warnings / 0 errors
across 32 files, and the headless harness 737 of 737 cases — and the complexity suite reports **zero
functions above CCN 15**, down from 20 on the previous run. That is the branch's whole purpose, and
it is measured here rather than asserted. Nothing to act on; the two readings worth carrying forward
are that the addon got **bigger** while getting less complex (+1147 NLOC, +247 functions), and that
all four files in the `layout-§1` 1000–1500 band grew rather than shrank.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260804-182144` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 32 files | [`lint.txt`](lint.txt) | unmoved — 0/0 over the same 32 files |
| tests | pass | 737 passed, 0 failed, 737 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | **+89 cases** (648 → 737), 0 failures in both |
| perf | skip | — | — (not run) | unmoved — still no `tests/perf.lua` |
| complexity | pass | 0 warnings (see below) | [`complexity.txt`](complexity.txt) | **20 warnings → 0**; max CCN 36 → 15 |

### Complexity in full

Every field of `lizard`'s footer, plus the two derived file counts. The **averages** are what make
this run comparable to the previous one across a change in size: the addon grew by 1147 NLOC in the
same window, so the totals moved for reasons that have nothing to do with complexity, and only the
averages carry the signal.

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

Max CCN is read from [`complexity.txt`](complexity.txt)'s per-function table, not from
`manifest.json`: the runner derives `maxCcn` from the **warning** list, and with zero warnings that
field records `0`. Zero is not this addon's peak complexity — 15 is, and three functions sit exactly
on the line (`Layout.layoutBlock`, `buildSpecNameMaps`, `OnAccept`).

`tests/perf.lua` is absent — this addon ships no offline scenarios, so nothing was measured there.
That is a **skip, not a pass**: it is recorded as one in `manifest.json`, and it means this run says
nothing about the addon's runtime cost.

## What moved

- **lint** — unmoved. 0 warnings / 0 errors over 32 files, the same figure and the same file count as
  the previous run. Nothing the branch touched added or removed a linted file.
- **tests** — 648 → **737**, all passing. The +89 are the characterization cases the refactors were
  written against; four suites are new on this branch (`test_castbar_debug.lua`,
  `test_castbar_skin.lua`, `test_compat_debug.lua`, `test_opensettings.lua`,
  `test_icongrid_glowgate.lua`) and `test_settings_spells_editor.lua` grew substantially.
  [`test-cases.md`](test-cases.md) is the authority on what exists at this point.
- **perf** — unmoved, and permanently so until scenarios exist. Still a skip.
- **complexity** — the run's news. **Warnings 20 → 0. Max CCN 36 → 15.** Avg CCN 2.3 → 2.1 and avg
  NLOC/function 6.8 → 6.5, both consistent with 20 large functions being split into smaller named
  ones rather than deleted. Avg tokens/function 51.5 → 48.9 says the same thing from the other side.
- **size** — the cost side of the same ledger, and it is real: total NLOC 14283 → **15430** (+1147)
  and functions 1804 → **2051** (+247). Splitting a function into named helpers adds signatures,
  locals and call sites, and a large share of the +1147 is the +89 tests. The addon is bigger than it
  was this morning, and that is the price paid for the CCN column.
- **files in the band** — the count is unmoved at 4, but every one of them **grew**:
  `modules/Castbar.lua` 1296 → 1314, `settings/Spells.lua` 1047 → 1172, `modules/IconGrid.lua`
  1100 → 1154, `tests/wow_mock.lua` 1049 → 1066. No file crossed a band boundary and none approaches
  the 1500 cap, but the direction reverses the previous run's note about `Castbar.lua` trending down.

## Complexity watch list

### Functions `lizard` warned on

**None.** Every function in the addon is at or below CCN 15. The three sitting exactly on the line —
`Layout.layoutBlock` (`modules/IconGrid_Layout.lua`), `buildSpecNameMaps` (`core/Util.lua`) and
`OnAccept` (`settings/Spells.lua`) — are under the threshold, not warnings; they are named here only
so the next run's diff has a reference point.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1314 | **Already tracked as `A-2`.** Up 18 lines — the CCN work added helper signatures. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1172 | **Already tracked as `A-2`.** Up 125, the largest growth in the band: peeling `buildRow` and `RefreshRows` split the row vocabulary into named helpers in the same file. If it keeps climbing, splitting the file is the next move, not another in-file peel. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1154 | **Already tracked as `A-2`.** Up 54 from the glow-gate and active-list peels. Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1066 | **Already tracked as `KCD-30`.** Up 17. Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender. |

Nothing newly crossed a band boundary, and no file is over the 1500 cap.

## Actions

None arising from this run. The one thing to carry forward is a reading rather than a task: the band
files all grew, so `A-2`'s next look belongs on file size, not on function complexity — this branch
has taken that to zero warnings.
