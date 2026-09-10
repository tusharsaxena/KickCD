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

| Run | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260910-234511`](20260910-234511/) | 1.2.1 → 1.3.0 | 0/0 | 94 | 870/0/870 | pass | 18164 | 2288 | 6.7 | 2.1 | 15 | 0 | **green** |
| [`20260908-181321`](20260908-181321/) | 1.2.1 | 0/0 | 93 | 860/0/860 | pass | 17805 | 2268 | 6.6 | 2.1 | 15 | 0 | **green** |
| [`20260825-103417`](20260825-103417/) | 1.2.1 | 0/0 | 35 | 780/780 | pass | 15802 | 2099 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-114618`](20260807-114618/) | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-110522`](20260807-110522/) | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-022824`](20260807-022824/) | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-233245`](20260804-233245/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-214315`](20260804-214315/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 0 | 0 | **green** |
| [`20260804-182144`](20260804-182144/) | 1.2.1 | 0/0 | 32 | 648/648 | skip | 14283 | 1804 | 6.8 | 2.3 | 36 | 20 | **green** |

## Test suite

**870 cases** — 870 passed, 0 failed, 0 skipped. The generated inventory
[`20260910-234511/test-cases.md`](20260910-234511/test-cases.md) is the authority on which cases existed at this run;
`docs/test-cases.md` is that same list at HEAD.

Moved **860 → 870** since the previous run.

No case reported a `skip`, so passed and total agree and nothing in this row claims coverage
that was not exercised.

## Lint

**0 warnings / 0 errors over 94 files** (`luacheck .`).

Read that figure with its scope attached: `.luacheckrc` sets `exclude_files = { "libs/", "docs/audits/", "_dev/", "tests/_kit/", "docs/reviews/" }`, so those paths
are not in it. A `0/0` that never moves is partly a statement about what was never looked at, which
is why the exclusion is restated on every run.

## Perf

**6 scenarios** from `tests/perf.lua`; the measurements are in
[`20260910-234511/perf.json`](20260910-234511/perf.json).

`perf` never fails a run and never blocks a commit — it is recorded, read and compared, not
thresholded (`performance-§9`). It does gate the **tag** (`automated-tests-§3`).

## Complexity watch list

Current as of [`20260910-234511`](20260910-234511/) — **this run's measurement, not its diff.** Max CCN **15** across 2288
functions, **0** of them warned on; 4 file(s) in the 1000–1500 band and 0 over the 1500 cap
(`layout-§1`).

Every row below is generated from this run's own `lizard` output. **The `Disposition` column is
the one authored cell in this file** (`automated-tests-§4`, *the one boundary*): it is carried
forward verbatim while its entry is unchanged, and left **blank** when the entry is new — a blank
cell is this file saying something crossed and nobody has ruled on it yet.

### Functions `lizard` warned on

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1345 | **Already tracked as `A-2`.** Not unchanged any more: 1305 at the previous run's commit, +40 this cycle. 155 lines of headroom before `layout-§1`'s cap. Watch, no action, and re-check at 1450 rather than at the cap. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1163 | **Already tracked as `A-2`.** Effectively flat — 1153 at the previous run's commit, one line down. The layout pass already lives in a sibling file, `modules/IconGrid_Layout.lua`, so the peel this file would take has been taken. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1312 | **Already tracked as `A-2`, and the fastest-growing file in the band.** 1171 at the previous run's commit, +141 this cycle — more than the other three moved together. The in-file peel is spent, so the next reduction has to be a file split. Re-check at 1400, not at the cap. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1245 | **Already tracked as `KCD-30`.** 1128 at the previous run's commit, +104 this cycle as the mock grew to cover what the new cases exercise. Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender rather than trimming it. It is the largest file under `tests/` and, since `M4-11`, `luacheck` does see it — the lint scope went 35 files to 93. |

`lizard` counts every `and`/`or` short-circuit as a decision, so in Lua a run of
`t.k = rec.k or D.k` defaulting lines scores high with no visible branching at all: a large CCN
here usually means *this function defaults or guards a lot of fields* rather than *this function
is tangled*, and the two want different fixes (`performance-§10`).

