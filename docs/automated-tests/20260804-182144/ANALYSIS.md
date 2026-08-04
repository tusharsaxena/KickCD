# Analysis — 20260804-182144

- **Addon:** KickCD 1.2.1
- **Verdict:** green
- **Commit:** de662229e931 (master), dirty
- **Started:** 2026-08-04T18:21:44+05:30
- **Previous run:** none — this is the first recorded run

## Headline

The first automated-test record for this addon, produced while adopting `automated-tests`
(standard v2.19.0). Both gating suites are clean: `luacheck` reports 0 warnings / 0 errors across
32 files and the headless harness passes 648 of 648 cases. The offline perf runner is absent (see below). Every figure below is a **baseline** —
there is no previous run to diff against, so nothing here is a regression and nothing is an
improvement.

## Suites

| Suite | Status | Result | Artifact | Moved since previous run |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 32 files | [`lint.txt`](lint.txt) | — first run |
| tests | pass | 648 passed, 0 failed, 648 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | — first run |
| perf | skip | — | — (not run) | — first run |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | — first run |

### Complexity in full

Every field of `lizard`'s footer, plus the two derived file counts. The **averages** are what make
this run comparable to the next one across a change in size: a total that rises because the addon
grew is a different fact from an average that rises because it got denser, and only the second is a
complexity signal.

| Metric | Value |
|---|---|
| Total NLOC | 14283 |
| Functions | 1804 |
| Avg NLOC / function | 6.8 |
| Avg CCN | 2.3 |
| Max CCN | 36 |
| Avg tokens / function | 51.5 |
| Warnings (CCN > 15) | 20 |
| Warning rate — `Fun Rt` / `nloc Rt` | 0.01 / 0.07 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

`tests/perf.lua` is absent — this addon ships no offline scenarios, so nothing was measured there. That is a **skip, not a pass**: it is recorded as one in `manifest.json`, and it means this run says nothing about the addon's runtime cost.

## What moved

**First run — nothing to diff against; every figure above is a baseline reading.** The next run is
the first one that can say something moved, and this record is what it will be read against.

## Complexity watch list

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

## Actions

None arising from this run. The dispositions above are carried forward from the complexity reports
written against the same measurements earlier today; each was recorded with its evidence at the
time, and none is new here.
