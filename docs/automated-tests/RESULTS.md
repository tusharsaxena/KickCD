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
| [`20260825-103417`](20260825-103417/) | 1.2.1 | 0/0 | 35 | 780/780 | pass | 15802 | 2099 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-114618`](20260807-114618/) | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-110522`](20260807-110522/) | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260807-022824`](20260807-022824/) | 1.2.1 | 0/0 | 33 | 756/756 | pass | 15533 | 2059 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-233245`](20260804-233245/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-214315`](20260804-214315/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 0 | 0 | **green** |
| [`20260804-182144`](20260804-182144/) | 1.2.1 | 0/0 | 32 | 648/648 | skip | 14283 | 1804 | 6.8 | 2.3 | 36 | 20 | **green** |

**Reading the `Max CCN` column:** the `0` on `20260804-214315` is an instrument fault, not a
measurement — see [Complexity watch list](#complexity-watch-list) below.

## Test suite

**756 cases**, zero failed, and — stated explicitly, because a trend line that folds a skip into a
pass is claiming coverage it did not exercise — **zero skipped**. The count has now held at 756
across three consecutive runs ([`20260807-022824`](20260807-022824/),
[`20260807-110522`](20260807-110522/), [`20260807-114618`](20260807-114618/)), which is not yet a
coverage gap: no addon source changed across those three either, so a flat suite against a flat
addon is the expected reading. It becomes worth a sentence the moment source moves and this number
does not.

The count last moved on [`20260807-022824`](20260807-022824/), 737 to 756. That +19 was not one
feature's worth of tests: it was spread across ten existing suite files (`test_constants.lua` +3,
`test_coresetup.lua` +2, `test_castbar_helpers.lua` +2, `test_options_panel.lua` +2,
`test_perfsetup.lua` +2, and single cases in `test_color_shape.lua`, `test_debuglogsetup.lua`,
`test_castbar_frame.lua`) plus **one new suite file**, `test_surface_parity.lua` (6 cases), and one
file that lost a case (`test_opensettings.lua`, 7 -> 6).

Coverage is the addon's own source and its `tests/` harness; anything that only exists in a live
client — frame skinning as WoW actually draws it, real combat-log ordering — is covered by
`docs/smoke-tests.md`, not here. Note the harness prints `N passed, N failed` without a total; the
runner parses both shapes since kit revision 2, after the first adoption sweep recorded 0/0 here and
still called it green. The generated inventory `test-cases.md` in each bundle is the authority on
what exists at that point; the README badge tracks the same number.

## Lint

Clean over **33** files as of [`20260807-114618`](20260807-114618/): 0 warnings, 0 errors. The file
count has held at 33 for three runs; it rose by one on [`20260807-022824`](20260807-022824/) from
the 32 the three runs before it read, and the file that made the difference is `defaults/Spells.lua`.

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
typo in test code is invisible to this column. The tests would have to fail for it to surface. That
56 is unchanged this run, and it includes `tests/perf.lua` — the file that flipped the Perf column
below, and one that shares the same blind spot. The biggest of the 56 is
`tests/wow_mock.lua` at 1101 lines — the largest file under `tests/`, but neither the largest file
`luacheck` skips (that is the vendored `libs/AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua`,
2045 lines) nor the largest on the band list below, where it is in fact the **smallest** of the four.

## Perf

**This addon ships `tests/perf.lua`, and the Perf column has read `pass` since
[`20260807-022824`](20260807-022824/)** — three consecutive runs now. Every row above that one in
the table carries a `skip`, and the standing sentence that used to sit here — *"this addon ships no
`tests/perf.lua`, so the record says nothing about its runtime cost"* — is no longer true and has
been retired rather than softened.

Five offline scenarios run, at 2000 iterations each, recorded in each bundle's `perf.txt` and
`perf.json`. Figures below are [`20260807-114618`](20260807-114618/)'s. They pin two different
things:

- **Cost of the hot paths** — `spellPoll` (0.01920 ms/iter, 18.0 API calls/iter, 226.4 bytes/iter),
  `spellState` (0.00767) and `iconApply` (0.00333). `spellPoll` is the only scenario making client
  API calls and is roughly 2.5x the cost of the next; that shape, and the API-call and byte counts
  beside it, are what to watch — not the millisecond figures.
- **`performance-§9`'s zero-overhead claim** — `probeOverheadOff` (0.00299 ms/iter) against
  `probeOverheadOn` (0.00445). This is the pair showing bracketed instrumentation is close to free
  when capture is off.

**The millisecond figures move run to run on an unchanged addon, and that is the single most
important thing to know about this section.** Across `20260807-022824`, `20260807-110522` and
`20260807-114618` no line of addon source changed, yet `spellPoll` read 0.01595, 0.01678 and 0.01920
ms/iter and `probeOverheadOn` read 0.00253, 0.00262 and 0.00445. What did **not** move across those
three is the deterministic part: 18.0 API calls per iteration for `spellPoll` and identical
per-iteration byte figures for all five scenarios. Read the API-call and allocation columns as the
signal and the timings as host noise. Timings are for orientation only: compare scenarios **within**
a run, never across runs or machines, and never read a millisecond figure as a threshold. Perf never
fails a run and never blocks a commit; it does gate the **tag**, along with the other three suites
(`automated-tests-§3`).
In-game captures are a separate store and live in `docs/perf-analysis/`, one frozen
`<YYYYMMDD-HHMMSS>/` bundle per capture — a script cannot produce them, and the two directories are
deliberately not merged.

## Complexity watch list

Current state as of [`20260807-114618`](20260807-114618/) — not that run's diff.
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
[`20260807-114618/complexity.txt`](20260807-114618/complexity.txt) reads `No thresholds exceeded`.
This is now the **fourth** consecutive run at zero warnings, and it is the result of the
`feat/fix-ccn` work rather than an empty section:
[`20260804-182144/complexity.txt`](20260804-182144/complexity.txt) warned on **twenty** functions,
none of which survives in a form `lizard` flags. Their dispositions went with them; there is nothing
left to carry forward.

**Five** functions sit exactly on the line at CCN 15 — the same five on each of the last four runs,
all of them named here rather than a sample, in
[`20260807-114618/complexity.txt`](20260807-114618/complexity.txt) order:
`State.ApplyInterruptibleAlpha` (`core/State.lua:99-118`), `buildSpecNameMaps`
(`core/Util.lua:232-269`), `StateChanged` (`modules/Cooldowns.lua:250-279`), `Layout.layoutBlock`
(`modules/IconGrid_Layout.lua:145-249`) and `OnAccept` (`settings/Spells.lua:480-503`). Every one of
those line ranges is unchanged from the previous run. They are at the threshold, not over it, so
none is an entry on this list; they
are named so a future run that reports a warning has five obvious places to look first, and so that
whoever next edits one of them knows there is exactly one line of headroom. Remember that `lizard`
counts every `and`/`or` short-circuit as a decision — in Lua a run of `t.k = rec.k or D.k`
defaulting lines scores high with no visible branching, so these five are dense **defaulting and
guarding** rather than tangled control flow, and they want a different fix from one that is.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1305 | **Already tracked as `A-2`.** Unchanged since `20260807-022824`. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1171 | **Already tracked as `A-2`.** Unchanged. The in-file peel is spent — the next reduction has to be a file split. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1153 | **Already tracked as `A-2`.** Unchanged. Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1101 | **Already tracked as `KCD-30`.** Unchanged, after the +35 recorded on `20260807-022824`. Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender rather than trimming it. It is the largest file under `tests/`, the smallest of the four here, and `luacheck` never sees it — see **Lint** above. |

Nothing newly crossed a band boundary and nothing is over the 1500 cap; the band has held at four
files, with all four at the same LOC, for six runs. The group reading from the previous entry still
stands: the CCN work traded function complexity for file size, the three **source** files gave a
little of that back on `20260804-233245` and have been flat since, and the growth has moved to the
harness — `tests/wow_mock.lua` is the only entry that has trended up at all.

No entry in either table is carried as a bare **Accepted**. All four band entries point at a tracked
deviation (`A-2`, `KCD-30`) and the functions table is empty, so `automated-tests-§4`'s shelf-life
rule — nothing accepted across three consecutive release runs — has nothing outstanding against this
record. Worth noting for the next reader: none of the six runs in the table is a **release** run
(`release: null` in every manifest), so the three-release clock has not started on anything here.

## A note on this record's own line endings

[`20260807-114618`](20260807-114618/) is the **first bundle written by test-kit revision 10**, which
added a `normalize_eol` pass so the runner writes the line ending `.gitattributes` declares instead
of LF unconditionally. This repo is CRLF-pinned (`* text=auto eol=crlf`), and every artifact in that
bundle carries equal `\r` and `\n` counts, as does this file. Earlier bundles were written LF on
disk and left to git's filters on staging; they are frozen and stay as they are
(`automated-tests-§1`). Counting the bytes is the only way to check this — `file(1)` reports nothing
about line terminators for JSON or for a one-line file, so it passes files it never examined
(`line-endings-§7`).
