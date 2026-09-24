# Analysis — 20260924-132214

- **Addon:** KickCD 1.3.0
- **Verdict:** green
- **Commit:** 55a1f1262cf8 (feat/2026-09-23-review-audit-remediation), clean
- **Previous run:** [`20260916-184417`](../20260916-184417/)

## Headline

Green on all four suites, zero functions above CCN 15, nothing skipped. This run measures the whole
2026-09-23 review/audit remediation on KickCD: the LibKa0s v1.56.0 re-vendor (test-kit revision 26),
items KC-01 to KC-28, and the docs sync ahead of this bundle. That is 72 commits since the previous
run. Tests rose 973 → 1141 and the `layout-§1` band grew from four files to nine. Every band file now
cites a live GitHub peel issue (#24–#32, filed by KC-28) in place of the retired trackers the old
dispositions named. Nothing is over the 1500 cap, and nothing here needs action before the owner
decides on a release.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260916-184417` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 106 files | [`lint.txt`](lint.txt) | +9 files in scope, still 0/0 |
| tests | pass | 1141 passed, 0 skipped, 0 failed, 1141 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | +168 cases |
| perf | pass | 6 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged; see below |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

**Complexity metrics** (all from [`manifest.json`](manifest.json), footer in [`complexity.txt`](complexity.txt)):

| Metric | Value |
|---|---|
| Total NLOC | 22684 |
| Functions | 2906 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.0 |
| Max CCN | 15 |
| Avg tokens / function | 51.3 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 9 |
| Files over the 1500 cap | 0 |

Every suite ran to completion. No suite was skipped and no case reported a `Kit.skip`, so passed and
total agree at 1141 and no figure here stands in for an unmeasured state. The toolchain is recorded in
[`manifest.json`](manifest.json)'s `host` block: Lua 5.1.5, `luacheck` 1.2.0, `lizard` 1.24.0. Run
duration 25878 ms. This is the first KickCD run on a kit that records the commit and tree state, so
[`../RESULTS.md`](../RESULTS.md) now carries `Commit` and `Tree` columns, with the eleven earlier
rows reading `unknown` as the runner writes them.

## What moved

The previous run measured `fac2411` on master; this one measures `55a1f12` on the remediation
branch, 72 commits later.

- **lint**: 97 → 106 files in scope, still 0 warnings / 0 errors ([`lint.txt`](lint.txt)). Ten
  authored files arrived: `core/LifecycleSetup.lua`, `core/SpellInput.lua`,
  `modules/Castbar_Handle.lua`, `settings/SchemaSetup.lua`, `settings/Spells_Rows.lua`,
  `tests/prose_waivers.lua`, `tests/test_disabled.lua`, `tests/test_events.lua`,
  `tests/test_icongrid_handle.lua` and `tests/test_schema_store.lua`. One left:
  `tests/test_spelling.lua`, replaced by the kit's `tests/_kit/test_prose.lua`, which sits under the
  `tests/_kit/` exclusion. `.luacheckrc`'s `exclude_files` is unchanged, so the scope grew because the
  tree did.
- **tests**: 973 → 1141 passed (+168), 0 skipped, 0 failed ([`tests.txt`](tests.txt)). The four new
  suites above, the kit-26 gates (`test_prose`, `test_layout_cap`) and cases added item by item across
  the remediation. The inventory is [`test-cases.md`](test-cases.md), and `docs/test-cases.md` at this
  commit is byte-identical to it.
- **perf**: 6 scenarios in both runs ([`perf.txt`](perf.txt)). Every `ms/iter` figure is lower
  (`spellPoll` 0.02096 → 0.01724, `castStart` 0.00818 → 0.00557), but the runner's caveat applies:
  timings are for orientation, not for comparing runs. `api/iter` is unchanged in all six (18.0 for
  `spellPoll`, 0.0 elsewhere). Allocation moved in the two buckets that moved last time, and in
  opposite directions again: `spellPoll` 1662.1 → 1024.8 bytes/iter and `spellState` 1440.9 → 1696.6
  ([`perf.json`](perf.json) against [`../20260916-184417/perf.json`](../20260916-184417/perf.json)).
  `iconApply`, both `probeOverhead` buckets and `castStart` are unchanged at 848.0 / 848.0 / 848.1 /
  208.0. That is the third run in a row where those two trade places, which supports the previous
  analysis's reading: harness noise, not a trend. Recorded, not actioned.
- **complexity**: NLOC 19884 → 22684 (+2800) over 2494 → 2906 functions (+412). Avg NLOC / function
  is flat at 6.7, avg CCN fell 2.1 → 2.0 and avg tokens / function 51.4 → 51.3. The totals rose
  because the addon and its suite grew, and the per-function figures held or fell, so the new code
  is no denser than the old. Max CCN is flat at 15 (at the line, not over it), and warnings are 0.
- **band**: 4 → 9 files. Five entered: `core/Database.lua` (1002), `modules/IconGrid_Render.lua`
  (1014), `tests/test_options_panel.lua` (1099), `tests/test_perfsetup.lua` (1018) and
  `tests/test_slash.lua` (1035). `settings/Spells.lua` fell 1246 → 1115 after the KC-13 row-builder
  peel. `modules/Castbar.lua` (1435), `modules/IconGrid.lua` (1368) and `tests/wow_mock.lua` (1233)
  all rose. Castbar is the closest to the cap, with 65 lines to spare.

## Complexity watch list

**Functions `lizard` warned on:**

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

**Files by `layout-§1` band.** The dispositions of record are in [`../RESULTS.md`](../RESULTS.md),
the one authored cell there. Summary:

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `core/Database.lua` | 1002 | tracked as #29; seam: profile migrations → `core/Database_Migrations.lua`; re-check at 1100 |
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1435 | tracked as #24; seam: cast-event handlers → `modules/Castbar_Events.lua`; peel before the next feature; re-check at 1450 |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1368 | tracked as #25; seam: visibility and glow gate → `modules/IconGrid_Visibility.lua`; re-check at 1450 |
| 1000–1500 (on notice) | `modules/IconGrid_Render.lua` | 1014 | first disposition; tracked as #26; seam: cooldown-text ticker → `modules/IconGrid_Text.lua`; re-check at 1100 |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1115 | tracked as #28; KC-13 peel recorded; seam: header builders → `settings/Spells_Header.lua`; re-check at 1200 |
| 1000–1500 (on notice) | `tests/test_options_panel.lua` | 1099 | tracked as #31; seam: degraded-stub and linked-Focus cases; re-check at 1200 |
| 1000–1500 (on notice) | `tests/test_perfsetup.lua` | 1018 | tracked as #32; seam: latch, suspended-flag and library-absent cases; re-check at 1100 |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1035 | tracked as #30; seam: disabled-state and degraded-stub cases; peel on next touch; re-check at 1150 |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1233 | tracked as #27; seam: frame model → `tests/wow_mock_frames.lua`; re-check at 1350 |

The earlier dispositions cited an advisory row in a frozen 2026-08-05 audit and a tracker id that
resolved to nothing. Four runs had carried "watch, no action" under those pointers, which is the
backlog anti-pattern #53 describes. Each file now points at an open issue that names its peel seam.

## Actions

1. `modules/Castbar.lua`: take the #24 peel (cast-event handlers into `modules/Castbar_Events.lua`)
   before the file takes another feature. It is 65 lines from the cap. Tracked as #24.
2. `tests/test_slash.lua`: take the #30 peel the next time the file is touched, since it grew 314
   lines this cycle. Tracked as #30.
3. The other seven band files: no action this run. Each is tracked (#25–#29, #31, #32) and carries
   its re-check line in `RESULTS.md`.
