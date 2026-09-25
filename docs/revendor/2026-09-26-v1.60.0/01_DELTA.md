Delta: LibKa0s v1.58.0 -> v1.60.0

# 01 — Delta

Run: 2026-09-26, plan item DR-KC-01 of the 2026-09-25 diagnostics rollout
(`Ka0sAddonsCommonTasks/docs/2026-09-25-DIAGNOSTICS_COMMAND/`, milestone M3), written by a workflow
subagent through `/wow-addon:revendor-libka0s --tag v1.60.0`. The skill's interview is answered from
that plan (`03_DECISIONS.md`), so no question was put to the owner and no decline issue is filed.
Target: this repo, branch `feat/2026-09-25-diagnostics-rollout`, cut from `master` at `1011848`. No
push.

Source: the sibling checkout `../LibKa0s`, **tag `v1.60.0` (tag object `ac59511` -> commit
`bed0eb1`)**. Extracted with `git -C ../LibKa0s archive v1.60.0 LibKa0s testkit | tar -x -C
<scratch>/`, never from the working tree. v1.59.0 was never vendored here; this re-vendor carries it
too.

```
git -C ../LibKa0s log --oneline v1.58.0..v1.60.0 | wc -l      -> 18
```

## Step 0 — Pre-flight on this addon's newest bundle

Newest bundle: `docs/revendor/2026-09-25-v1.58.0/`, base v1.57.0, which the commit that vendored
v1.58.0 (`0faae15`, M6-KC) confirms. **ok**, no base correction owed.

## 3a — Claimed version, and the delta base

`grep -n '[Bb]undles' CLAUDE.md` -> `CLAUDE.md:42`: Bundles
[LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.58.0** (MIT). `README.md` carries no
provenance line. **Base: v1.58.0.**

## 3b — Actual version, before the copy

The minors match v1.58.0's release block exactly (`DebugLog 13`, `Slash 15`, `DRAG_MINOR = 2`, and
the rest). `diff -rq --strip-trailing-cr` and `diff -rq` of both payloads against a v1.58.0 extract
both print nothing: the line agrees with the bytes, and nothing has forked.

## 3c — Per-file minor delta

File list read from the tag's `LibKa0s/LibKa0s.xml`. Minors by exact constant name:

```
grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua   (old vs tag)
```

| File | Constant | v1.58.0 | v1.60.0 |
|---|---|---|---|
| `WidgetsDragHandle.lua` | `DRAG_MINOR` | 2 | **3** (v1.59.0) |
| `DebugLog.lua` | `MINOR` | 13 | **14** |
| `DebugLogDiagnostics.lua` | `DIAG_MINOR` | (absent) | **1** (new file) |
| `Slash.lua` | `MINOR` | 15 | **16** |

Every other file is unchanged (Core 8, Env 1, Compat 1, Lifecycle 2, Bus 2, Schema 2, Pool 3, Item 2,
Media 4, Widgets 10, Launcher 4, Options key 24.31.4.7.4, Perf 13, PerfPanel 5). No file is removed,
no major is added (`DebugLogDiagnostics.lua` is a second file of `LibKa0s-DebugLog-1.0`, version key
14.1) and no `NEEDS_*` floor rises. No cross-major skew.

## 3d — Both diffs

Before the copy, against the v1.60.0 extract (`diff -rq --strip-trailing-cr`):

```
libs:  DebugLog.lua, LibKa0s.xml, Slash.lua, WidgetsDragHandle.lua differ; Only in tag: DebugLogDiagnostics.lua
kit:   README.md, framework.lua differ; Only in tag: test_diagnostics_contract.lua
```

No `Only in libs/LibKa0s` or `Only in tests/_kit` line, so nothing is deleted. The after-copy
result is in `05_SUMMARY.md`.

## 3e — Consumption map

Unchanged from the earlier bundles: thirteen majors looked up outside `libs/` and `tests/`. The
three whose minors move are all consumed:

- `LibKa0s-DebugLog-1.0` at `core/DebugLogSetup.lua:41`;
- `LibKa0s-Slash-1.0` at `settings/Slash.lua:55`;
- `LibKa0s-Widgets-1.0` (which `WidgetsDragHandle.lua` extends) at `modules/Castbar_Handle.lua:41`,
  `modules/IconGrid.lua:609`, `settings/Spells.lua:789`, `settings/Spells_Rows.lua:287`.

## 3f — Kit revision, and the pairing rule

```
grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua
  -> tag 27, vendored 26
```

The kit moves 26 -> 27 (the new `test_diagnostics_contract.lua`). Both payloads are copied whole in
one commit, so the pairing rule holds by construction.

## 3g — Contract delta

Read from the library's CHANGELOG v1.59.0 and v1.60.0 blocks and
`docs/api/DebugLog/version-14.1-docs.md` "Compatibility" (`:604-620`), `docs/api/Slash/version-16-docs.md`
and `docs/api/Widgets/version-10.3-docs.md`.

| Major | Old -> new | What moved, and what this addon hands over |
|---|---|---|
| Widgets (DragHandle) | 10.2 -> 10.3 | `spec.onClose` builds an opt-in X. A spec with no `onClose` is exactly minor 2 (same frames, reserve 29, `Measure()`). `modules/Castbar_Handle.lua` passes no `onClose`, so nothing moves on screen. |
| DebugLog | 13 -> 14.1 | `MAX_BUFFER` 1500 -> 3000, `BUFFER_SLACK` 64 -> 128 (published). No host test here writes 1500 lines or pins either constant: `grep -rn '1500\|MAX_BUFFER\|BUFFER_SLACK' --include='*.lua' .` outside `libs/` and `_kit/` finds only the comment at `core/DebugLogSetup.lua:5` (moved by DR-KC-05) and unrelated file-cap references. New instance members `RunDiagnostics`, `BuildDiagnostics`, `DebugVerb`. |
| Slash | 15 -> 16 | `lib.LIVE_VERBS` gains `diagnostics`. `settings/Slash.lua:428-433` builds its live set from `SlashLib.LIVE_VERBS` plus `NS.EXTRA_LIVE_VERBS`, so the verb is live while disabled with no host change. `/kcd diagnostics` is not yet registered (DR-KC-03), so the refused set is unchanged. |

No `__Attach*` member this addon supplies changed its call site
(`grep -rn '__Attach[A-Za-z]*' --include='*.lua' --exclude-dir=libs --exclude-dir=_kit .` finds only
the comment at `settings/Panel.lua:182`, on `OptionsCompose`, which did not move).

### Blockers

Two, both owed in the copy commit so the suite stays green, both named in the v1.60.0 block
"What a consumer owes":

1. **DebugLog stub parity.** `tests/test_surface_parity.lua:107` ("the DebugLog stub carries the
   whole live surface") goes red until `core/DebugLogSetup.lua`'s library-absent stub carries
   `RunDiagnostics`, `BuildDiagnostics` and `DebugVerb`. The stub's `RunDiagnostics` prints
   `L["%s is unavailable: the LibKa0s library did not load."]` with `/kcd diagnostics`, writes
   nothing and returns 0 (STD-14; 14.1 doc `:615-619`).
2. **The kit's new suite.** `tests/run.lua`'s suite list must declare
   `{ name = "test_diagnostics_contract", dir = "tests/_kit/" }`, or `Kit.assertSuiteInventory` fails
   the run. With `Kit.diagnostics` unset it is one declared skip until DR-KC-03 wires it.

Neither needs a decision; both are edits, so the run continues to the copy.

## 3h — Tags this addon vendored and never recorded

v1.59.0 is skipped rather than vendored; its one change (DragHandle 3) is recorded above.
