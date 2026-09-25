# 05 — Summary: LibKa0s v1.58.0 -> v1.60.0

Plan item DR-KC-01 of the 2026-09-25 diagnostics rollout, 2026-09-26, branch
`feat/2026-09-25-diagnostics-rollout`. Nothing pushed, and the addon version is not bumped.

## The tag, and the per-file minors

`v1.58.0` -> `v1.60.0` (tag object `ac59511`, commit `bed0eb1`), carrying v1.59.0 too.

| File | v1.58.0 | v1.60.0 |
|---|---|---|
| `WidgetsDragHandle.lua` (`DRAG_MINOR`) | 2 | 3 |
| `DebugLog.lua` | 13 | 14 |
| `DebugLogDiagnostics.lua` (`DIAG_MINOR`) | (absent) | 1 |
| `Slash.lua` | 15 | 16 |
| kit `framework.lua` (`Kit.VERSION`) | 26 | 27 |

Two files arrive new, `libs/LibKa0s/DebugLogDiagnostics.lua` and `tests/_kit/test_diagnostics_contract.lua`.
None is removed. Details in `01_DELTA.md`.

## Delivered on the re-vendor, with nothing asked for

- The debug console keeps 3000 lines instead of 1500.
- `diagnostics` is a live verb while disabled, through `settings/Slash.lua`'s union over
  `SlashLib.LIVE_VERBS`. It is not registered yet, so the refused set is unchanged, and
  `tests/test_slash.lua` "the host's feature verbs are exactly the verbs the live gate refuses"
  still passes: the live union still leaves exactly `NS.FEATURE_VERBS`.
- The hand-set `TIME_COPY` switch.

## Contract blockers, resolved in the copy commit

- `core/DebugLogSetup.lua`'s library-absent stub gains `RunDiagnostics` (prints
  `/kcd diagnostics is unavailable: the LibKa0s library did not load.`, writes nothing, returns 0),
  `BuildDiagnostics` (an empty report) and `DebugVerb` (the library's routing of `diagnostics`, `on`,
  `off`). `tests/test_surface_parity.lua`'s DebugLog case is green because of them, and a new case in
  `tests/test_debuglogsetup.lua` pins the placeholder line, the zero, the empty buffer and the
  routing.
- `tests/run.lua` declares `{ name = "test_diagnostics_contract", dir = "tests/_kit/" }`. It is one
  declared skip until DR-KC-03 wires `Kit.diagnostics`.

## Adopted, declined, unreached

Nothing adopted in this item. The diagnostics helper and the `diagnostics` verb are adopted in
DR-KC-03. The DragHandle close mark is not adopted, by owner ruling (Q1, X-03). No decline issue is
filed, as the plan directs. See `02_CANDIDATES.md` and `03_DECISIONS.md`.

## Docs touched

`CLAUDE.md` (the provenance line, v1.60.0), `docs/testing.md` (the vendored-copy note names
v1.60.0), `docs/test-cases.md` (regenerated), and the README's test badge. The buffer comment at
`core/DebugLogSetup.lua:5` and the other buffer doc sites are DR-KC-05's.

## Gates after the copy

| Suite | Result |
|---|---|
| `ka0s-bounded luacheck .` | 0 warnings / 0 errors in 107 files |
| `ka0s-bounded lua tests/run.lua` | 1152 passed, 0 failed, 1 skipped, 1153 total |
| `ka0s-bounded lizard -l lua -x "./libs/*" -x "./tests/_kit/*" -C 15 -w .` | no function above CCN 15 |
| 1500-line file cap | largest authored file `modules/Castbar.lua`, 1435 lines |
| `diff -r --strip-trailing-cr` of both payloads against the tag | empty |

The one skip is the kit's diagnostics contract, declared until the report exists.
