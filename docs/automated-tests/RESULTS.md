# Automated test results

<!-- The newest run is prepended by tests/_kit/run-automated-tests.sh. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

**`lint` and `tests` gate. `perf` and `complexity` are recorded and never fail a run** —
they are read and compared, not thresholded. A `skip` is a suite that did not run at all,
which is never the same as a pass.

| Run | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260804-233245`](20260804-233245/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 15 | 0 | **green** |
| [`20260804-214315`](20260804-214315/) | 1.2.1 | 0/0 | 32 | 737/737 | skip | 15430 | 2051 | 6.5 | 2.1 | 0 | 0 | **green** |
| [`20260804-182144`](20260804-182144/) | 1.2.1 | 0/0 | 32 | 648/648 | skip | 14283 | 1804 | 6.8 | 2.3 | 36 | 20 | **green** |

**Reading the `Max CCN` column:** the `0` on `20260804-214315` is an instrument fault, not a
measurement — see [Complexity watch list](#complexity-watch-list) below.

## Test suite

737 cases, unmoved since [`20260804-214315`](20260804-214315/) — that run's `tests.txt` and
`test-cases.md` are byte-identical to the newest run's, so not one case was added or renamed between
the two. The count itself is recent: it rose from 648 on `20260804-182144`, and the +89 are the
characterization cases written against the CCN refactors before those refactors moved a line, which
is why runs on either side of the refactor agree on behavior while the code underneath changed shape.
Coverage is the addon's own source and its `tests/` harness; anything that only exists in a live
client — frame skinning as WoW actually draws it, real combat-log ordering — is covered by
`docs/smoke-tests.md`, not here. Note the harness prints `N passed, N failed` without a total; the
runner parses both shapes since kit revision 2, after the first adoption sweep recorded 0/0 here and
still called it green. The generated inventory `test-cases.md` in each bundle is the authority on
what exists at that point; the README badge tracks the same number.

## Lint

Clean over 32 files on [`20260804-233245`](20260804-233245/): 0 warnings, 0 errors, and the same
figure over the same file count on the two runs before it.

What those 32 files are matters more than the `0/0`, because `.luacheckrc`'s `exclude_files` is not
short. It lists five entries — `libs/`, `tests/`, `_dev/`, `docs/audits/` and `docs/reviews/` — so
`luacheck .` covers the addon's own shipped source and **nothing else**. The 32 files are every
`.lua` under `core/` (11), `settings/` (11), `modules/` (8), `defaults/` (1) and `locales/` (1), and
those are exactly the `.lua` files `KickCD.toc` loads **from outside `libs/`** — not the complete set
of files the TOC loads. The TOC carries 13 further load lines, every one of them under `libs/`: seven
`.lua` files (`LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`, `AceEvent-3.0`, `AceDB-3.0`,
`AceDBOptions-3.0`, `AceConsole-3.0`) and six `.xml` files (`AceConfig-3.0`, `AceGUI-3.0`, `LibKa0s`,
`LibSharedMedia-3.0`, `AceGUI-3.0-SharedMediaWidgets`, `LibCustomGlow-1.0`) that pull in more Lua
still. `luacheck` sees none of those. Excluding `libs/` is the standard's own rule (vendored code is
not this repo's to fix), and `_dev/`, `docs/audits/` and `docs/reviews/` hold scratch and frozen
bundles. **`tests/` is the one that costs something**: the 54 `.lua` files of the harness and its
mock are never linted, so an unused local or a global typo in test code is invisible to this column.
The tests would have to fail for it to surface. The biggest of those 54 is `tests/wow_mock.lua` at
1066 lines — the largest file under `tests/`, but neither the largest file `luacheck` skips (that is
the vendored `libs/AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua`, 2045 lines) nor the
largest on the band list below, where it is in fact the **smallest** of the four.

## Perf

This addon ships no `tests/perf.lua`, so the `perf` column is a permanent `skip` rather than a
transient tooling gap, and it has been a skip on every run in the table above. Two things follow, and
both are standing facts rather than any run's news: the record says **nothing** about the addon's
runtime cost, and `performance-§9`'s zero-overhead evidence — that bracketed instrumentation is free
when capture is off — does not exist for it. Adding scenarios is the only thing that changes either.

## Complexity watch list

Current state as of [`20260804-233245`](20260804-233245/) — not that run's diff.
Every function `lizard` warned on, and every file at or above `layout-§1`'s 1000-LOC
on-notice threshold, each with a one-line disposition.

**The `Max CCN` cells on `20260804-182144` and `20260804-214315` came from a broken instrument.**
Testkit rev 5 read `CCN_MAX` out of `lizard`'s `!!!! Warnings` block, which is empty once an addon
reaches zero warnings, so it recorded `"maxCcn": 0` the moment the count hit zero — that is the `0`
in the middle of the `36 → 0 → 15` trend, and it is a reporting bug, not a regression and recovery.
The true ceiling was always in the same bundle's own `complexity.txt`:
[`20260804-214315/complexity.txt`](20260804-214315/complexity.txt) lists five functions at CCN 15.
Those rows stand as the runner wrote them — a bundle is frozen evidence (`automated-tests-§1`) and a
hand-corrected number is worse than a wrong one because it reads as measured (`performance-§10`).
`20260804-233245` is the first run produced by testkit rev 6, which reads the ceiling from the
per-function table, so its `15` is the real figure.

### Functions `lizard` warned on

**None.**

Every function in the addon is at or below CCN 15, so `lizard` warned on nothing. This is the result
of the `feat/fix-ccn` work, not an empty section. [`20260804-182144/complexity.txt`](20260804-182144/complexity.txt)
warned on **twenty** functions, and because a count is worth nothing without its members, here are
all twenty in descending CCN, as that file lists them:

| CCN | Function | File |
|---|---|---|
| 36 | `ReskinStructure@176-325` | `modules/Castbar_Skin.lua` |
| 27 | `Castbar@17-95` | `modules/Castbar_Debug.lua` |
| 25 | `OnAccept@360-423` | `settings/Spells.lua` |
| 25 | `IconGrid@957-1024` | `modules/IconGrid.lua` |
| 25 | `Icon@633-721` | `modules/IconGrid_Render.lua` |
| 24 | `UnitLabel@70-123` | `modules/UnitLabel.lua` |
| 23 | `IconGrid@294-358` | `modules/IconGrid.lua` |
| 22 | `Spells@854-920` | `settings/Spells.lua` |
| 22 | `Castbar@726-780` | `modules/Castbar.lua` |
| 20 | `Database@583-625` | `core/Database.lua` |
| 19 | `Compat.DebugInterrupt@371-455` | `core/Compat.lua` |
| 19 | `NS@733-771` | `core/KickCD.lua` |
| 19 | `Cooldowns@93-199` | `modules/Cooldowns.lua` |
| 19 | `buildRow@506-797` | `settings/Spells.lua` |
| 18 | `(anonymous)@65-111` | `tests/test_perfsetup.lua` |
| 16 | `Database@516-533` | `core/Database.lua` |
| 16 | `Util.ResolveSpecID@290-322` | `core/Util.lua` |
| 16 | `Icon@532-560` | `modules/IconGrid_Render.lua` |
| 16 | `getCooldownManagerSpellSet@254-290` | `settings/Spells.lua` |
| 16 | `New@510-530` | `tests/wow_mock.lua` |

Five sat at 16, not four: `Database@516-533`, `Util.ResolveSpecID`, `Icon@532-560`,
`getCooldownManagerSpellSet` and `New@510-530`. Eighteen of the twenty are addon source and were
split or flattened behind characterization tests; the remaining two — `(anonymous)@65-111` in
`tests/test_perfsetup.lua` and `New@510-530` in `tests/wow_mock.lua` — are harness code, which
`lizard` measures (only `tests/_kit/` is excluded) but no characterization test guards. None of the
twenty survives in a form `lizard` flags. Their old dispositions went with them; there is nothing
left to carry forward.

**Five** functions now sit exactly on the line at CCN 15, all of them named here rather than a sample
of them, in [`20260804-233245/complexity.txt`](20260804-233245/complexity.txt) order:
`State.ApplyInterruptibleAlpha` (`core/State.lua:99-118`), `buildSpecNameMaps`
(`core/Util.lua:232-269`), `StateChanged` (`modules/Cooldowns.lua:250-279`), `Layout.layoutBlock`
(`modules/IconGrid_Layout.lua:145-249`) and `OnAccept` (`settings/Spells.lua:481-504`). They are at
the threshold, not over it, so none is an entry on this list; they are named so a future run that
reports a warning has five obvious places to look first, and so that whoever next edits one of them
knows there is exactly one line of headroom.

What this table costs to keep at "None." is visible in the other one: the same refactors added 1147
NLOC and 247 functions, and every file in the band below grew. Zero warnings is not free, and the
place the bill lands is file size.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1314 | **Already tracked as `A-2`.** Unmoved since `20260804-214315`, where it rose 18. The earlier downward trend (1473 → 1296 across two peels) has stopped: the CCN work put helper signatures back. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1172 | **Already tracked as `A-2`.** Unmoved since `20260804-214315`, where it rose 125 — the band's largest move — from peeling `buildRow` and `RefreshRows` into named helpers that stayed in this file. The next reduction has to be a file split; the in-file peel is spent. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1154 | **Already tracked as `A-2`.** Unmoved since `20260804-214315`, where it rose 54 from the glow-gate and active-list peels. Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1066 | **Already tracked as `KCD-30`.** Unmoved since `20260804-214315`, where it rose 17. Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender rather than trimming it. It is the largest file under `tests/`, the smallest of the four in this band, and `luacheck` never sees it — see **Lint** above. |

No file crossed a band boundary and none is over the 1500 cap. All four grew on `20260804-214315`
and none has moved since, so the band is still worth reading as a group rather than file by file:
the CCN work traded function complexity for file size, and this is where the bill landed.
