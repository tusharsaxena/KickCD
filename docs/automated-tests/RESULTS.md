# Automated test results

<!-- Regenerated whole by tests/_kit/run-automated-tests.sh on every run. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->
<!-- Everything here is generated EXCEPT the watch list's Disposition column. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

**`lint` and `tests` gate the run and gate the commit** (`testing-§4`).
**`perf` and `complexity` never fail a run and never block a commit** — they are recorded,
read and compared, not thresholded (`performance-§9`, `performance-§10`).

**The tag is gated on all four suites at `pass`, plus zero functions above CCN 15**
(`automated-tests-§3`, *The release gate*), evaluated by `/wow-addon:bump-version` from the
`manifest.json` the release run writes — not by this script, whose exit code is unchanged.

A `skip` is a suite that did not run at all. It is never a pass, and at the release gate it is
**NOT EVALUATED** rather than passed: install the tool and re-run. A `—` is a suite that was
not selected, which is a different fact again.

The **Tests** cell reads `passed/skipped/total`.

**Commit** is the short sha the run measured and **Tree** is whether that tree was clean at the
time. Both are read from git by the runner; neither is ever typed. A **dirty** row measured bytes
that no sha can bring back, so it is kept as an experiment honestly labeled rather than dropped —
and a release record is refused outright on a dirty tree, so no release row can be one.

A row reading `unknown` in both cells was recorded before the runner emitted them. That is what
the record holds about those runs — it is not `clean`, and it is not reconstructed from git
archaeology, for the same reason a skip is never a pass (`automated-tests-§4`).

| Run | Commit | Tree | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260924-132214`](20260924-132214/) | `55a1f12` | clean | 1.3.0 | 0/0 | 106 | 1141/0/1141 | pass | 22684 | 2906 | 6.7 | 2.0 | 15 | 0 | **green** |
| [`20260916-184417`](20260916-184417/) | unknown | unknown | 1.3.0 | 0/0 | 97 | 973/0/973 | pass | 19884 | 2494 | 6.7 | 2.1 | 15 | 0 | **green** |
| [`20260916-094252`](20260916-094252/) | unknown | unknown | 1.3.0 | 0/0 | 95 | 936/0/936 | pass | 19345 | 2390 | 6.8 | 2.1 | 15 | 0 | **green** |
| [`20260910-234511`](20260910-234511/) | unknown | unknown | 1.2.1 → 1.3.0 | 0/0 | 94 | 870/0/870 | pass | 18164 | 2288 | 6.7 | 2.1 | 15 | 0 | **green** |
| [`20260908-181321`](20260908-181321/) | unknown | unknown | 1.2.1 | 0/0 | 93 | 860/0/860 | pass | 17805 | 2268 | 6.6 | 2.1 | 15 | 0 | **green** |
| [`20260825-103417`](20260825-103417/) | unknown | unknown | 1.2.1 | 0/0 | 35 | 780/780 | pass | 15802 | 2099 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-114618`](20260807-114618/) | unknown | unknown | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-110522`](20260807-110522/) | unknown | unknown | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-022824`](20260807-022824/) | unknown | unknown | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-233245`](20260804-233245/) | unknown | unknown | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-214315`](20260804-214315/) | unknown | unknown | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 0 | 0 | **green** |
| [`20260804-182144`](20260804-182144/) | unknown | unknown | 1.2.1 | 0/0 | 32 | 648/648 | skip | 14283 | 1804 | 6.8 | 2.3 | 36 | 20 | **green** |

## Test suite

**1141 cases** — 1141 passed, 0 failed, 0 skipped. The generated inventory
[`20260924-132214/test-cases.md`](20260924-132214/test-cases.md) is the authority on which cases existed at this run;
`docs/test-cases.md` is that same list at HEAD.

Moved **973 → 1141** since the previous run.

No case reported a `skip`, so passed and total agree and nothing in this row claims coverage
that was not exercised.

## Lint

**0 warnings / 0 errors over 106 files** (`luacheck .`).

Read that figure with its scope attached: `.luacheckrc` excludes 5 path(s) from it — `libs/`, `docs/audits/`, `_dev/`, `tests/_kit/`, `docs/reviews/` —
so nothing under them is in the count above. A `0/0` that never moves is partly a statement about
what was never looked at, which is why the exclusions are NAMED here on every run rather than left
to whoever thinks to open `.luacheckrc`.

## Perf

**6 scenarios** from `tests/perf.lua`; the measurements are in
[`20260924-132214/perf.json`](20260924-132214/perf.json).

| `scenario` | `iters` | `ms/iter` | `api/iter` | `bytes/iter` |
|---|---|---|---|---|
| `spellPoll` | 2000 | 0.01724 | 18.0 | 1024.8 |
| `spellState` | 2000 | 0.00599 | 0.0 | 1696.6 |
| `iconApply` | 2000 | 0.00258 | 0.0 | 848.0 |
| `probeOverheadOff` | 2000 | 0.00244 | 0.0 | 848.0 |
| `probeOverheadOn` | 2000 | 0.00270 | 0.0 | 848.1 |
| `castStart` | 2000 | 0.00557 | 0.0 | 208.0 |

`perf` never fails a run and never blocks a commit — it is recorded, read and compared, not
thresholded (`performance-§9`). It does gate the **tag** (`automated-tests-§3`).

## Complexity watch list

Current as of [`20260924-132214`](20260924-132214/) — **this run's measurement, not its diff.** Max CCN **15** across 2906
functions, **0** of them warned on; 9 file(s) in the 1000–1500 band and 0 over the 1500 cap
(`layout-§1`).

Every row below is generated from this run's own `lizard` output. **The `Disposition` column is
the one authored cell in this file** (`automated-tests-§4`, *the one boundary*): it is carried
forward verbatim while its entry is unchanged, and left **blank** when the entry is new — a blank
cell is this file saying something crossed and nobody has ruled on it yet.

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `core/Database.lua` | 1002 | **Already tracked as #29.** New to the band this cycle, 893 → 1002 (+109), mostly the per-profile color and font-flag migration steps. Peel seam: the profile migrations (`FoldLegacyUnits` … `MigrateProfile`) into `core/Database_Migrations.lua`. Two lines over the line, so no urgency; re-check at 1100. |
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1435 | **Already tracked as #24.** Up 1345 → 1435 (+90) this cycle: the stand-down latch, the per-unit cast filter with the EMPOWER events, and the drag-strip wiring left behind when the strip itself moved to `Castbar_Handle.lua`. 65 lines below the cap, the closest file in the repo. Peel seam: the cast-event handlers into `modules/Castbar_Events.lua`. Take the #24 peel before this file takes another feature; re-check at 1450. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1368 | **Already tracked as #25.** Up 1163 → 1368 (+205) this cycle, the largest source-file climb: the icon grid's own drag strip, the stand-down latch and the per-unit cast filter. The layout pass already lives in `modules/IconGrid_Layout.lua`. Peel seam: the visibility and glow gate into `modules/IconGrid_Visibility.lua`. Re-check at 1450. |
| 1000–1500 (on notice) | `modules/IconGrid_Render.lua` | 1014 | **Already tracked as #26.** First disposition: entered the band this cycle at 998 → 1014 (+16, the stand-down latch's hooks), so it is here by drift rather than by a feature. Peel seam: the cooldown-text ticker into `modules/IconGrid_Text.lua`. Accepted until #26 lands; re-check at 1100. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1115 | **Already tracked as #28.** Down 1246 → 1115: KC-13 (`abc06cd`) peeled the row builders into `settings/Spells_Rows.lua` (302 lines), taking this file from 1363 to 1114 and back under the old 1400 re-check with room. Still in the band; the peel that takes it out is #28's seam, the class/spec header builders (`titleCaseToken` … `buildSpellsHeader`) into `settings/Spells_Header.lua`. Re-check at 1200. |
| 1000–1500 (on notice) | `tests/test_options_panel.lua` | 1099 | **Already tracked as #31.** New to the band, 963 → 1099 (+136): the options timer-handle cases, the linked-Focus decline's pinning cases and the Schema-seam migration. Case count, not tangle. Peel seam: the degraded-stub and linked-Focus cases into `tests/test_options_panel_degraded.lua`. Re-check at 1200. |
| 1000–1500 (on notice) | `tests/test_perfsetup.lua` | 1018 | **Already tracked as #32.** New to the band, 917 → 1018 (+101): the `rebuildEmit` bracket cases and the shared stand-down latch. Case count, not tangle. Peel seam: the latch, suspended-flag and library-absent cases into `tests/test_perfsetup_latch.lua`. Re-check at 1100. |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1035 | **Already tracked as #30.** New to the band, 721 → 1035 (+314), the fastest climb of the nine: the shared spell-input resolver's CLI cases and the degraded stub's WS-02 shape and write-through. Case count, not tangle, but at this rate take the #30 peel the next time the file is touched. Peel seam: the disabled-state and degraded-stub cases into `tests/test_slash_degraded.lua`. Re-check at 1150. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1233 | **Already tracked as #27.** Up 1060 → 1233 (+173) this cycle: the stand-down latch's surfaces, the per-profile migration fixtures and the recorded event registry. Peel seam: the mock's frame model into `tests/wow_mock_frames.lua`. Re-check at 1350. |

`lizard` counts every `and`/`or` short-circuit as a decision, so in Lua a run of
`t.k = rec.k or D.k` defaulting lines scores high with no visible branching at all: a large CCN
here usually means *this function defaults or guards a lot of fields* rather than *this function
is tangled*, and the two want different fixes (`performance-§10`).

