# Automated test results

<!-- The newest run is prepended by tests/_kit/run-automated-tests.sh. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->

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

| Run | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260807-110522`](20260807-110522/) | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-022824`](20260807-022824/) | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-233245`](20260804-233245/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-214315`](20260804-214315/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 0 | 0 | **green** |
| [`20260804-182144`](20260804-182144/) | 1.2.1 | 0/0 | 32 | 648/648 | skip | 14283 | 1804 | 6.8 | 2.3 | 36 | 20 | **green** |

**Reading the `Max CCN` column:** the `0` on `20260804-214315` is an instrument fault, not a
measurement — see [Complexity watch list](#complexity-watch-list) below.

## Test suite

756 cases, up from 737 on [`20260804-233245`](20260804-233245/) — the count is moving again after
sitting flat across the two runs before it. The +19 is not one feature's worth of tests: it is
spread across ten existing suite files (`test_constants.lua` +3, `test_coresetup.lua` +2,
`test_castbar_helpers.lua` +2, `test_options_panel.lua` +2, `test_perfsetup.lua` +2, and single
cases in `test_color_shape.lua`, `test_debuglogsetup.lua`, `test_castbar_frame.lua`) plus **one new
suite file**, `test_surface_parity.lua` (6 cases), and one file that lost a case
(`test_opensettings.lua`, 7 -> 6). Zero failed and — stated explicitly because a trend line that
folds a skip into a pass is claiming coverage it did not exercise — **zero skipped**.

Coverage is the addon's own source and its `tests/` harness; anything that only exists in a live
client — frame skinning as WoW actually draws it, real combat-log ordering — is covered by
`docs/smoke-tests.md`, not here. Note the harness prints `N passed, N failed` without a total; the
runner parses both shapes since kit revision 2, after the first adoption sweep recorded 0/0 here and
still called it green. The generated inventory `test-cases.md` in each bundle is the authority on
what exists at that point; the README badge tracks the same number.

## Lint

Clean over **33** files on [`20260807-022824`](20260807-022824/): 0 warnings, 0 errors. The file
count rose by one from the three runs before it, which all read 32 — the new file is
`defaults/Spells.lua`.

What those 33 files are matters more than the `0/0`, because `.luacheckrc`'s `exclude_files` is not
short. It lists five entries — `libs/`, `tests/`, `_dev/`, `docs/audits/` and `docs/reviews/` — so
`luacheck .` covers the addon's own shipped source and **nothing else**. The 33 files are every
`.lua` under `core/` (11), `settings/` (11), `modules/` (8), `defaults/` (2) and `locales/` (1), and
those are exactly the `.lua` files `KickCD.toc` loads **from outside `libs/`** — not the complete set
of files the TOC loads. The TOC carries 13 further load lines, every one of them under `libs/`: seven
`.lua` files (`LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`, `AceEvent-3.0`, `AceDB-3.0`,
`AceDBOptions-3.0`, `AceConsole-3.0`) and six `.xml` files (`AceConfig-3.0`, `AceGUI-3.0`, `LibKa0s`,
`LibSharedMedia-3.0`, `AceGUI-3.0-SharedMediaWidgets`, `LibCustomGlow-1.0`) that pull in more Lua
still. `luacheck` sees none of those. Excluding `libs/` is the standard's own rule (vendored code is
not this repo's to fix), and `_dev/`, `docs/audits/` and `docs/reviews/` hold scratch and frozen
bundles. **`tests/` is the one that costs something**: the 56 `.lua` files under it — 52 in `tests/`
proper plus the 4 vendored under `tests/_kit/` — are never linted, so an unused local or a global
typo in test code is invisible to this column. The tests would have to fail for it to surface. Two
of those 56 are new since the previous run and inherit the same blind spot, and one of them is
`tests/perf.lua`, the file that flipped the Perf column below. The biggest of the 56 is
`tests/wow_mock.lua` at 1101 lines — the largest file under `tests/`, but neither the largest file
`luacheck` skips (that is the vendored `libs/AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua`,
2045 lines) nor the largest on the band list below, where it is in fact the **smallest** of the four.

## Perf

**This addon now ships `tests/perf.lua`, and as of [`20260807-022824`](20260807-022824/) the Perf
column reads `pass` rather than `skip` for the first time.** Every row above it in the table carries
the skip, and the standing sentence that used to sit here — *"this addon ships no `tests/perf.lua`,
so the record says nothing about its runtime cost"* — is no longer true and has been retired rather
than softened.

Five offline scenarios run, at 2000 iterations each, recorded in each bundle's `perf.txt` and
`perf.json`. They pin two different things:

- **Cost of the hot paths** — `spellPoll` (0.01595 ms/iter, 18.0 API calls/iter), `spellState`
  (0.00548) and `iconApply` (0.00236). `spellPoll` is the only scenario making client API calls and
  is roughly 3x the cost of the next; that is the shape to watch, not the absolute numbers.
- **`performance-§9`'s zero-overhead claim** — `probeOverheadOff` (0.00229 ms/iter) against
  `probeOverheadOn` (0.00253). This is the pair that shows bracketed instrumentation is close to
  free when capture is off, and it is evidence the record simply did not contain before this run.

Timings are for orientation only: compare scenarios **within** a run, never across machines, and
never read a single run's millisecond figure as a threshold. Perf never fails a run and never blocks
a commit; it does gate the **tag**, along with the other three suites (`automated-tests-§3`).
In-game captures are a separate store and remain in `docs/perf-runs/` — a script cannot produce
them, and the two directories are deliberately not merged.

## Complexity watch list

Current state as of [`20260807-022824`](20260807-022824/) — not that run's diff.
Every function `lizard` warned on, and every file at or above `layout-§1`'s 1000-LOC
on-notice threshold, each with a one-line disposition.

**The `Max CCN` cells on `20260804-182144` and `20260804-214315` came from a broken instrument.**
Testkit rev 5 read `CCN_MAX` out of `lizard`'s `!!!! Warnings` block, which is empty once an addon
reaches zero warnings, so it recorded `"maxCcn": 0` the moment the count hit zero — that is the `0`
in the middle of the `36 -> 0 -> 15` trend, and it is a reporting bug, not a regression and recovery.
The true ceiling was always in the same bundle's own `complexity.txt`:
[`20260804-214315/complexity.txt`](20260804-214315/complexity.txt) lists five functions at CCN 15.
Those rows stand as the runner wrote them — a bundle is frozen evidence (`automated-tests-§1`) and a
hand-corrected number is worse than a wrong one because it reads as measured (`performance-§10`).
`20260804-233245` was the first run produced by testkit rev 6, which reads the ceiling from the
per-function table, so its `15` and every figure since are real.

### Functions `lizard` warned on

**None.**

Every function in the addon is at or below CCN 15, so `lizard` warned on nothing — the footer of
[`20260807-022824/complexity.txt`](20260807-022824/complexity.txt) reads `No thresholds exceeded`.
This is now the third consecutive run at zero warnings, and it is the result of the `feat/fix-ccn`
work rather than an empty section: [`20260804-182144/complexity.txt`](20260804-182144/complexity.txt)
warned on **twenty** functions, none of which survives in a form `lizard` flags. Their dispositions
went with them; there is nothing left to carry forward.

**Five** functions sit exactly on the line at CCN 15 — the same five as on the previous run, all of
them named here rather than a sample, in
[`20260807-022824/complexity.txt`](20260807-022824/complexity.txt) order:
`State.ApplyInterruptibleAlpha` (`core/State.lua:99-118`), `buildSpecNameMaps`
(`core/Util.lua:232-269`), `StateChanged` (`modules/Cooldowns.lua:250-279`), `Layout.layoutBlock`
(`modules/IconGrid_Layout.lua:145-249`) and `OnAccept` (`settings/Spells.lua:480-503`, shifted one
line from `481-504`). They are at the threshold, not over it, so none is an entry on this list; they
are named so a future run that reports a warning has five obvious places to look first, and so that
whoever next edits one of them knows there is exactly one line of headroom. Remember that `lizard`
counts every `and`/`or` short-circuit as a decision — in Lua a run of `t.k = rec.k or D.k`
defaulting lines scores high with no visible branching, so these five are dense **defaulting and
guarding** rather than tangled control flow, and they want a different fix from one that is.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1305 | **Already tracked as `A-2`.** Down 9 since `20260804-233245`. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1171 | **Already tracked as `A-2`.** Down 1. The in-file peel is spent — the next reduction has to be a file split. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1153 | **Already tracked as `A-2`.** Down 1. Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1101 | **Already tracked as `KCD-30`.** **Up 35 — the only file in the band that grew this run**, while the three source files beside it each shrank. Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender rather than trimming it. It is the largest file under `tests/`, the smallest of the four here, and `luacheck` never sees it — see **Lint** above. |

Nothing newly crossed a band boundary and nothing is over the 1500 cap; the band has held at four
files for four runs. The group reading has changed, though, and it is worth stating: the CCN work
traded function complexity for file size, and for the first time the three **source** files in the
band are giving that back — small, but in the right direction — while the growth has moved entirely
to the harness. `tests/wow_mock.lua` is the only entry trending up.

No entry in either table is carried as a bare **Accepted**. All four band entries point at a tracked
deviation (`A-2`, `KCD-30`) and the functions table is empty, so `automated-tests-§4`'s shelf-life
rule — nothing accepted across three consecutive release runs — has nothing outstanding against this
record. Worth noting for the next reader: none of the four runs in the table is a **release** run
(`release: null` in every manifest), so the three-release clock has not started on anything here.
