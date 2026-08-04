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
| [`20260804-182144`](20260804-182144/) | 1.2.1 | 0/0 | 32 | 648/648 | skip | 14283 | 1804 | 6.8 | 2.3 | 36 | 20 | **green** |

## Test suite

648 cases. Note the harness prints `N passed, N failed` without a total; the runner parses both shapes since kit revision 2, after the first adoption sweep recorded 0/0 here and still called it green. The generated inventory `test-cases.md` in each bundle is the authority on what exists at that point; the README badge tracks the same number.

## Lint

Clean over 32 files: 0 warnings, 0 errors. `luacheck .` runs over the addon's own source and its `tests/`; the vendored `libs/` and `tests/_kit/` are out of scope by config, since neither is this repo's to fix.

## Perf

This addon ships no `tests/perf.lua`, so the `perf` column is a permanent `skip` rather than a transient tooling gap. Two things follow, and both are standing facts rather than this run's news: the record says **nothing** about the addon's runtime cost, and `performance-§9`'s zero-overhead evidence — that bracketed instrumentation is free when capture is off — does not exist for it. Adding scenarios is the only thing that changes either.

## Complexity watch list

Current state as of [`20260804-182144`](20260804-182144/) — not that run's diff.
Every function `lizard` warned on, and every file at or above `layout-§1`'s 1000-LOC
on-notice threshold, each with a one-line disposition.

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|
| `ReskinStructure` | 36 | `modules/Castbar_Skin.lua` | **Peel next.** Highest CCN and the longest non-generated body (150 lines, 5 params); it splits along the field groups it already comments. |
| `Castbar:DebugDump` | 27 | `modules/Castbar_Debug.lua` | **Accepted.** A `/kcd debug castbar` diagnostic probing every field's `type()`/`issecretvalue()`. The branch count *is* the diagnostic. |
| `IconGrid:RefreshAllGlows` | 25 | `modules/IconGrid.lua` | **Accepted for now.** Glow trigger ladder × four glow kinds — the product of two small enumerations. |
| `Icon:Apply` | 25 | `modules/IconGrid_Render.lua` | **Accepted, deliberately.** The addon's one instrumented hot path: flat and branchy on purpose, no helper calls, no allocation. |
| `OnAccept` (spell popup) | 25 | `settings/Spells.lua` | **Accepted.** Validates one text field across every input form the CLI accepts. Revisit if a third caller appears. |
| `UnitLabel:Apply` | 24 | `modules/UnitLabel.lua` | **Accepted.** Config→widget application; every branch is a distinct setting with no shared shape to factor. |
| `IconGrid:BuildActiveList` | 23 | `modules/IconGrid.lua` | **Accepted.** The pick-and-order pass; branch count tracks the visibility rules, which are the addon's product. |
| `Castbar:ApplyState` | 22 | `modules/Castbar.lua` | **Accepted.** The cast/channel/empowered/interrupted state machine, flattened so a secret `notInterruptible` never binds to a local. |
| `Spells:RefreshRows` | 22 | `settings/Spells.lua` | **Accepted for now.** Shrinks on its own once `buildRow` is peeled — the two share the row vocabulary. |
| `Database:MigrateSpecKeys` | 20 | `core/Database.lua` | **Accepted.** A one-shot SavedVariables migration over fixed historical key shapes; the honest simplification is deleting it once they are extinct. |
| `Compat.DebugInterrupt` | 19 | `core/Compat.lua` | **Already tracked as `KCD-33`** and review finding **F-002**; routing through `NS.SafeToString` removes the hand-rolled stringifier. |
| `NS:OpenSettings` | 19 | `core/KickCD.lua` | **Accepted.** Combat gate plus the Blizzard settings-category resolution ladder, which needs every fallback it has. |
| `Cooldowns:PollSpell` | 19 | `modules/Cooldowns.lua` | **Accepted, deliberately.** Per-spell poll on the coalesced pass — inline to avoid a call and an allocation per spell. |
| `buildRow` | 19 | `settings/Spells.lua` | **Peel next.** CCN is mid-pack but the body is **292 lines**, the longest in the addon; the per-widget blocks lift out without touching behaviour. |
| `Database:FoldLegacyUnits` | 16 | `core/Database.lua` | **Accepted.** Fixed-shape one-shot migration; deleted rather than refactored when it expires. |
| `Util.ResolveSpecID` | 16 | `core/Util.lua` | **Accepted.** Every branch is a supported input form the slash CLI documents. |
| `Icon:UpdateGlow` | 16 | `modules/IconGrid_Render.lua` | **Accepted.** Four glow kinds × start/stop; sits just over the line and gains nothing from a split. |
| `getCooldownManagerSpellSet` | 16 | `settings/Spells.lua` | **Accepted.** Reads Blizzard's Cooldown Manager set through several optional APIs, each guarded because any may be absent. |
| `(anonymous)` bucket guard | 18 | `tests/test_perfsetup.lua` | **Accepted.** A source-scan guard; its branches are the bracket spellings it must not miss. Simplifying it is how the guard silently narrows. |
| `New` (AceDB mock) | 16 | `tests/wow_mock.lua` | **Already tracked as `KCD-30`** — the fix rebuilds the mock as a thin extender, removing this function rather than refactoring it. |

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1296 | **Already tracked as `A-2`.** Down from 1473 after two peels — the trend is the right way. Watch, no action. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1100 | **Already tracked as `A-2`.** Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1049 | **Already tracked as `KCD-30`.** Not covered by `A-2`, which lists source files only; the whole file is the deviation. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1047 | **Already tracked as `A-2`.** Peeling `buildRow` takes this file back under the band as a side effect. |
