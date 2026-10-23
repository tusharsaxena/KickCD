Delta: LibKa0s v1.75.2 -> v1.76.0

Run non-interactively by item `KC-RV` of the 2026-10-23 run "sim auto-run, QC preview selector,
mode strips, MM/KCD simulators", on branch `feat/2026-10-23-sim-preview-mode-strips`, following the
installed `/dev-copilot:wow-revendor-libka0s` at 2.4.0. Both payloads are copied whole, the
provenance line rolls, the copy is pruned to the unchanged `LibKa0s icons:` line, and every adoption
candidate is recorded as decided by the run's plan (`02_CANDIDATES.md`). There is no interview and
no GitHub issue is filed.

## Source

```sh
git -C ../LibKa0s rev-parse 'v1.76.0^{commit}'   # 9949368 (annotated, LOCAL; not pushed in this run)
git -C ../LibKa0s archive v1.76.0 LibKa0s testkit tools | tar -x -C <scratch>/v176
```

The payload comes from the tag through `git archive`, never from the library's working tree.
`tools/` is extracted only for `prune-icons.lua` and is not copied into the addon.

## Pre-flight (Step 0)

KickCD's newest single-tag bundle, `../2026-10-22-v1.75.0/`, states base v1.71.0, and the provenance
line before its re-vendor commit `6445d94` named v1.71.0: ok. No base correction is owed.

## Base (3a, 3b)

```sh
grep -n 'Bundles \[LibKa0s' CLAUDE.md
# 42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.75.2 (MIT).   (before the roll)
git log -1 --format='%h %s' -- libs/LibKa0s tests/_kit
# 6c70977 Re-vendor LibKa0s v1.75.2 (SimPanel minor 4)
git -C ../LibKa0s archive v1.75.2 LibKa0s testkit | tar -x -C <scratch>/v1752
diff -rq <scratch>/v1752/LibKa0s libs/LibKa0s | grep -v 'Only in <scratch>/v1752/LibKa0s/media/icons'
#   (empty: only the undeclared icons the v1.75.0 prune removed)
diff -rq <scratch>/v1752/testkit tests/_kit && echo kit-base-ok
# kit-base-ok
```

Base v1.75.2: the provenance line, the last payload commit and the bytes agree.

## Range

```sh
git -C ../LibKa0s log --oneline v1.75.2..v1.76.0
# 9949368 LK-90: address review — name tests/test_sim_panel.lua in the CLAUDE.md 1000-1500 band
# 82d76f6 LK-90: close v1.76.0 with its release record (20261023-150627)
# f9ce82a LK-90 (1/2): release v1.76.0: version block, pointers, consumers
# 37e6b69 LK-25: add the preview and simulation re-look to the release checklist
# d5fa6e9 LK-10: give W.TestStrip a simulation flavor (Widgets minor 14)
# d728cc4 LK-01: play a simulation on its own and drop Run all (Sim 2.3.5)
# 05cb400 LK-00: open v1.76.0 with an unreleased CHANGELOG block
# 99fb662 Merge branch 'fix/2026-10-23-sim-picker-step-delay' (LibKa0s v1.75.2: SimPanel minor 4)
git -C ../LibKa0s diff --stat v1.75.2 v1.76.0 -- LibKa0s testkit
#  LibKa0s/SimPanel.lua    |  36 ++++++++------
#  LibKa0s/SimTimeline.lua | 122 +++++++++++++++++++++++++++++++++++++-----------
#  LibKa0s/Widgets.lua     |  43 ++++++++++++-----
```

## Per-file minor delta (3c)

The loop over the tag's `LibKa0s/LibKa0s.xml` prints three moved files; every other file is at its
v1.75.2 minor, and no file is new.

| File | Major | v1.75.2 | v1.76.0 |
|---|---|---|---|
| `SimTimeline.lua` | `LibKa0s-Sim-1.0` | `TIMELINE_MINOR` 2 | **3** |
| `SimPanel.lua` | `LibKa0s-Sim-1.0` | `SIM_PANEL_MINOR` 4 | **5** |
| `Widgets.lua` | `LibKa0s-Widgets-1.0` | 13 | **14** |

Composite keys (the tag's `CHANGELOG.md` v1.76.0 block): Sim **2.3.5** (`Sim` 2 unchanged), Widgets
**14.1.4.3.2**. No `NEEDS_*` floor rises. Still seventeen majors across forty files.

## Both diffs (3d)

Before the prune, `diff -r --strip-trailing-cr` and `diff -r` of both payloads against the tag were
empty. No `Only in libs/LibKa0s` line appeared, so nothing was deleted by hand. After the prune the
only difference is `Only in <scratch>/v176/LibKa0s/media/icons…` lines for the undeclared icons.

- **SimTimeline 3 / SimPanel 5**: a verb start or restart plays the run on its own; a manual step or
  click holds it; the controls are Pause/Resume, Restart and Stop (Run all and `RUN_ALL` are gone).
- **Widgets 14**: `W.TestStrip(parent, { kind = "sim" })` draws the simulation cyan, and
  `strip.kind` is readable. No member is added.

**Kit**: revision 41 at both tags, byte-identical (`diff -rq <scratch>/v176/testkit tests/_kit`
empty before the copy).

## Consumption map (3e)

Fifteen majors are looked up outside `libs/` and `tests/`: Bus, Compat, Core, DebugLog, Env, Glow,
Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Slash and Widgets. `LibKa0s-Sim-1.0` and
`LibKa0s-Item-1.0` are not looked up (the two `Item` hits are library-internal, in
`OptionsIds.lua` and `OptionsIdList.lua`). Of the moved files KickCD reaches only Widgets
(`W.ReorderList` on the Spells page), which this release does not touch.

## Kit revision (3f)

```sh
grep -n 'Kit.VERSION =' <scratch>/v176/testkit/framework.lua tests/_kit/framework.lua
# both: Kit.VERSION = 41
```

Both payloads still move together in one commit (the pairing rule), though the kit is unchanged.

## Contract delta (3g)

- **Sim 2.3.5: a start plays at once.** KickCD hosts no Sim session yet, so nothing it ships is
  affected. The run's KC-03 to KC-10 build `/kcd sim` against 2.3.5 from the start.
- **Widgets 14: `TestStrip` gains `kind`.** Additive; KickCD draws no strip yet (KC-09 adopts the sim
  flavor).

No `__Attach*` member KickCD supplies moved (`settings/Panel.lua:181` is a comment about
`__AttachCompose`, whose file did not move). **No blockers.**

## Unrecorded tags (3h)

v1.75.1 and v1.75.2 were vendored and never recorded, so the span bundle
`../2026-10-23-v1.75.1-v1.75.2/` is written in this run. Re-run after writing it, the listing is
empty.

## The icon declaration (3i), and tests that assume the whole folder (3j)

Kept unchanged, directly under the provenance line (`CLAUDE.md:43`):

```
LibKa0s icons: clear, close, copy, help, segment.
```

The evidence is in `../2026-10-22-v1.75.0/01_DELTA.md`; no draw site changed since. The `confirm`
and `info` names the simulator owes are declared by KC-03, in the commit that first draws them.

```sh
lua <scratch>/v176/tools/prune-icons.lua <abs KickCD path>
# prune-icons: ...KickCD: 5 icon(s) declared; kept 6 file(s), removed 5834
```

3j: the whole-catalog test loops were removed in the v1.75.0 re-vendor; nothing in `tests/`
outside `_kit/` opens an undeclared icon. No README credit changes (the same Open Iconic set ships),
and no `__releaseChrome` mirror exists.

## Addendum: the tag moved (KC-RV2)

The local tag `v1.76.0` was moved after `KC-RV` copied it: `9949368` -> `e692491` (LK-91, then
LK-92, README only). `KC-RV2` re-vendored both payloads whole from the moved tag, with no new
bundle:

```sh
git -C ../LibKa0s rev-parse 'v1.76.0^{commit}'   # e692491 (annotated, LOCAL)
git -C ../LibKa0s diff --stat 9949368 e692491 -- LibKa0s testkit
#  LibKa0s/PerfPanel.lua | 19 +++++++++++++------
#  LibKa0s/SimPanel.lua  | 26 +++++++++++++++++++++++---
```

- `SimPanel.lua` stays at `SIM_PANEL_MINOR` 5 (Sim key 2.3.5): a step-panel label is anchored
  LEFT and RIGHT short of the command column, so a long label truncates with an ellipsis instead
  of running under the command (LK-91).
- `PerfPanel.lua` moves `PANEL_MINOR` 7 -> **8** (Perf key 15.1.1.8), the same label fix.
- The kit is unchanged (41). No other file moved.

```sh
lua <scratch>/tools/prune-icons.lua <abs KickCD path>
# prune-icons: ...KickCD: 7 icon(s) declared; kept 8 file(s), removed 5832
```

After the prune, `diff -r` against the tag shows only `Only in <scratch>/LibKa0s/media/icons`
lines, and `diff -r` of `tests/_kit` is empty. KickCD draws neither panel's labels itself, so
nothing needs adoption or a test change.
