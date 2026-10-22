Delta: LibKa0s v1.71.0 -> v1.75.0

Run non-interactively by item `KC-RV` of the 2026-10-22 run "LibKa0s issues #45-#58", on branch
`feat/2026-10-22-libka0s-issues-45-58`, following the installed `/dev-copilot:wow-revendor-libka0s`
at 2.4.0 (its icon declaration, prune and credits steps). The run's ruling makes M2 non-interactive:
both payloads are copied whole, the provenance line rolls, the `LibKa0s icons:` line is written under
it, the copy is pruned, the blockers are fixed in the same commit, and every adoption candidate is
recorded as decided here (`02_CANDIDATES.md`). There is no interview and no GitHub issue is filed.

## Source

```sh
git -C ../LibKa0s tag -l v1.75.0                        # v1.75.0 (LOCAL tag; not pushed in this run)
git -C ../LibKa0s rev-parse --short 'v1.75.0^{commit}'  # 265a89e (annotated)
git -C ../LibKa0s archive v1.75.0 LibKa0s testkit tools | tar -x -C <scratch>/v175
```

The payload comes from the tag through `git archive`, never from the library's working tree.
`tools/` is extracted only for `prune-icons.lua` and is not copied into the addon.

## Base (3a, 3b)

```sh
grep -n 'Bundles \[LibKa0s' CLAUDE.md
# 42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.71.0 (MIT).   (before the roll)
git log -1 --format='%h %s' master -- libs/LibKa0s tests/_kit
# e1dabec RV-KC: re-vendor LibKa0s v1.71.0 (kit 38) with v1.69.0-v1.70.0 span
git -C ../LibKa0s archive v1.71.0 LibKa0s testkit | tar -x -C <scratch>/v171
diff -rq <scratch>/v171/LibKa0s libs/LibKa0s && diff -rq <scratch>/v171/testkit tests/_kit && echo base-ok
# base-ok
```

Base v1.71.0: the provenance line, the last payload commit and the bytes agree, so no base
correction is owed. KickCD never vendored v1.72.0, v1.73.0 or v1.74.0, so they are in this delta's
range and not on any span line (3h).

## Range

```sh
git -C ../LibKa0s log --oneline v1.71.0..v1.75.0 | wc -l   # 56
diff -rq <scratch>/v171/LibKa0s <scratch>/v175/LibKa0s
#   differ: Core.lua, DebugLog.lua, DebugLogDiagnostics.lua, Item.lua, LibKa0s.xml, Media.lua,
#           Options.lua, OptionsIdList.lua, OptionsTabs.lua, Perf.lua, PerfPanel.lua, Widgets.lua
#   only in v1.75.0: Glow.lua, MediaIcons.lua, OptionsDrawer.lua, Sim.lua, SimTimeline.lua,
#                    SimPanel.lua; media/icons gains 111 Open Iconic marks, phosphor/ and game-icons/
diff -rq <scratch>/v171/testkit <scratch>/v175/testkit
#   differ: README.md, framework.lua, inventory.lua, mock_base.lua, mock_record.lua,
#           run-automated-tests.sh, vendor_sync.lua; only in v1.75.0: latch.lua
```

## Per-file minor delta (3c)

| File | Major | v1.71.0 | v1.75.0 | Tag that moved it |
|---|---|---|---|---|
| `Perf.lua` | `LibKa0s-Perf-1.0` | 14 | **15** | v1.72.0 |
| `Options.lua` | `LibKa0s-Options-1.0` | 28 | **29** | v1.73.0 |
| `OptionsDrawer.lua` | `LibKa0s-Options-1.0` | (new) | **1** | v1.73.0 |
| `Media.lua` | `LibKa0s-Media-1.0` | 4 | **5** | v1.74.0 |
| `MediaIcons.lua` | `LibKa0s-Media-1.0` | (new) | **1** | v1.74.0 |
| `OptionsTabs.lua` | `LibKa0s-Options-1.0` | 8 | **9** | v1.75.0 |
| `Core.lua` | `LibKa0s-Core-1.0` | 10 | **11** (comment-only) | v1.75.0 |
| `DebugLog.lua` | `LibKa0s-DebugLog-1.0` | 19 | **20** (comment-only) | v1.75.0 |
| `DebugLogDiagnostics.lua` | `LibKa0s-DebugLog-1.0` | 2 | **3** | v1.75.0 |
| `OptionsIdList.lua` | `LibKa0s-Options-1.0` | 4 | **5** (comment-only) | v1.75.0 |
| `PerfPanel.lua` | `LibKa0s-Perf-1.0` | 6 | **7** (comment-only) | v1.75.0 |
| `Widgets.lua` | `LibKa0s-Widgets-1.0` | 12 | **13** | v1.75.0 |
| `Item.lua` | `LibKa0s-Item-1.0` | 2 | **3** | v1.75.0 |
| `Glow.lua` | `LibKa0s-Glow-1.0` (new major) | - | **1** | v1.75.0 |
| `Sim.lua`, `SimTimeline.lua`, `SimPanel.lua` | `LibKa0s-Sim-1.0` (new major) | - | **1**, **1**, **1** | v1.75.0 |

Composite keys at v1.75.0 (the tag's `CHANGELOG.md` version block): Core **11**, DebugLog **20.3.1**,
Options **29.2.34.2.5.9.1.7.4.2.1**, Perf **15.1.1.7**, Widgets **13.1.4.3.2**, Media **5.1**, Item
**3**, Glow **1**, Sim **1.1.1**. Every other file is at its v1.71.0 minor. No `NEEDS_*` floor rises.
The library is seventeen majors across forty files.

`W.StepPanel` is not public (LK-11 outcome B): the step-panel renderer is a library-private section
of `SimPanel.lua` (`lib.__StepPanel` is an internal test seam), and `PerfPanel.lua` minor 7 only
gains a header comment naming the duplication.

## Both diffs (3d), summarized

**Library payload:**

- **v1.72.0, Perf 15**: `Perf.Note(key, ms, false)` means "observed at top level". KickCD calls
  `Perf.Note` in `modules/Cooldowns.lua:225,233` with a bucket key or nil, never `false`, so its
  records do not change.
- **v1.73.0, Options 29 + OptionsDrawer 1**: the new `O.Drawer(ctx, spec)` and, for every host, a
  structural refresh of a page on screen keeps its scroll offset (`RefreshAllPanels`,
  `RefreshPanel(ctx, true)`). KickCD calls both (`settings/Panel_Render.lua:128,352,397`) and never
  scrolled a page back to the top by hand, so it takes the fix with nothing to drop.
- **v1.74.0, Media 5 + MediaIcons 1**: `ICONS` grows from 113 names to 5,836 (Open Iconic, Phosphor
  `ph:`, Game-icons `gi:`), `ICON_SETS`, prefix resolution and `IconAuthor`. No member KickCD calls
  changes.
- **v1.75.0, OptionsTabs 9**: `O.__releaseChrome` is no longer exported (LibKa0s#45). KickCD's stub
  has no mirror of it (removed by M4-09).
- **v1.75.0, Core 11 / DebugLog 20 / OptionsIdList 5, comment-only** (LibKa0s#57): the comments
  that promised a text fallback for a missing icon now say a host that passes its addon name and
  does not declare the icon gets a blank control.
- **v1.75.0, DebugLogDiagnostics 3**: the report's `LibKa0s running:` line also names Glow, Sim,
  SimTimeline and SimPanel when the client runs them.
- **v1.75.0, Widgets 13**: `W.SearchBox` (#52) and `W.TestStrip` (#48).
- **v1.75.0, Item 3**: `Item.BonusIDsFromLink` (#51).
- **v1.75.0, new majors**: `LibKa0s-Glow-1.0` (#56) and `LibKa0s-Sim-1.0` (#53, #54). Both define
  only functions at load: no frame, timer or event until a host calls `Glow.Start`, `NewSeam`, `New`
  or `ShowPanel`.

**Kit payload**: revision 38 -> **41**. Revision 39 (v1.72.0): `M.__fireUnconditional` reaches
method-name and function handlers, and the new `latch.lua` (`Kit.assertLatchHoldOrder`). Revision
40/41 (v1.75.0): `vendor_sync.lua` holds `media/icons/` to the consumer's `LibKa0s icons:` line;
`Kit.__deviationRows` and `Kit.__declineFor` are no longer exported (#45); a lizard crash or bound is
a complexity fail with zeroed figures and a `crashedFiles` bucket (#46, #47).

Before the prune, `diff -r --strip-trailing-cr` and `diff -r` of both payloads against the tag were
empty in both directions, and no `Only in libs/LibKa0s` line appeared, so nothing was deleted by
hand. `tests/_kit/run-automated-tests.sh` keeps its executable mode.

## Consumption map (3e)

Fourteen majors are looked up outside `libs/` and `tests/`: Bus, Compat, Core, DebugLog, Env,
Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Slash and Widgets. Item, Glow and Sim are
not looked up. Of the moved files, KickCD reaches Core (`MakeCloseButton`, through
`core/CoreSetup.lua:244-245`), DebugLog and its diagnostics (`core/DebugLogSetup.lua`, `/kcd
diagnostics`), Options (the panel, `RefreshPanel`/`RefreshAllPanels`, the stub), Perf and PerfPanel
(`core/PerfSetup.lua`), Media (`core/MediaSetup.lua`) and Widgets (`W.ReorderList` on the Spells
page). Glow arrives here and is adopted by KC-01 in M3 (`02_CANDIDATES.md`).

## Kit revision (3f)

```sh
grep -n 'Kit.VERSION =' <scratch>/v175/testkit/framework.lua   # Kit.VERSION = 41
grep -n 'Kit.VERSION =' <scratch>/v171/testkit/framework.lua   # Kit.VERSION = 38
```

Both payloads move together in one commit (the pairing rule). `tests/test_list_mode.lua:69` names kit
38 as history and is left alone.

## Contract delta (3g)

- **Kit 39 `__fireUnconditional` reaches method-name handlers.** Checked, no change: the only use is
  `tests/test_disabled.lua:261`, through the host mock, and no stand-down case went red.
- **Options 29: structural refresh keeps the scroll offset.** Delivered free (class A).
- **Options stub surface parity: `Drawer`.** A blocker (below).
- **Core 11 / DebugLog 20 / OptionsIdList 5: an undeclared icon draws blank.** Covered by the
  declaration (3i).

### Blockers

A scratch run of the suite on the v1.75.0 payload showed exactly four reds. All are fixed in this
commit; nothing under `libs/` or `tests/_kit/` was edited and no assertion was weakened.

1. `tests/test_surface_parity.lua` "the Options stub carries every member the host calls": the live
   Options instance gained `Drawer` (v1.73.0). `settings/OptionsSetup.lua` adds `Drawer` to the
   inert no-op list, with a comment; this addon draws no drawer.
2. `tests/test_options_panel.lua` "takes no locale override": the scan derived from `LibKa0s.xml`
   found 11 Options files (`grep -c 'Options[A-Za-z]*\.lua' libs/LibKa0s/LibKa0s.xml` = 11, with
   `OptionsDrawer.lua`). The expected count moves 10 -> 11.
3. `tests/test_options_panel.lua` "the art is on disk" (3j): it opened `media/icons/info.tga`, which
   the prune removes. Rewritten to the declaration: KickCD draws no `O.IdList` (a comment-stripped
   scan of `core/`, `modules/`, `settings/` for `IdList(` finds none; `settings/Spells_Header.lua`
   uses `H.IdInput`), so `info` must be absent from both the line and the copy; if an `IdList(` call
   appears, `info` must be declared. The line is read with the kit's `VendorSync.iconDeclaration`.
4. `tests/test_mediasetup.lua` "every name the library ships has a file in the vendored copy" (3j):
   the whole-catalog loop is deleted, because the kit's vendor_sync case now gates declared ==
   shipped. The hand list `DRAWN` (with its false "never calls NS.Icon itself" comment) is replaced
   by the declaration, and two cases are added: every literal `NS.Icon("<name>")` in authored code is
   declared, and the library-drawn `close`, `copy`, `clear` are declared because the debug console
   is wired.

## Unrecorded tags (3h)

None. Every tag this addon vendored since the store's horizon has a bundle; the last is
`../2026-10-07-v1.71.0/`. v1.72.0 to v1.74.0 were never vendored here, so no span bundle is written.

## The icon declaration (3i)

Decided by the item spec (KC-RV), recorded here and not re-asked:

```
LibKa0s icons: clear, close, copy, help, segment.
```

Written as `CLAUDE.md:43`, the next non-blank line after the provenance line, with CRLF. Evidence:

| Name | Draw site |
|---|---|
| `close` | `settings/Spells_Rows.lua:252` (`NS.Icon("close")`, the row remove mark); library-drawn by `Core.MakeCloseButton` through `core/CoreSetup.lua:244-245` (the debug console, the perf panel via `core/PerfSetup.lua`, the Widgets copy window) |
| `copy`, `clear` | library-drawn: the DebugLog title bar (`libs/LibKa0s/DebugLog.lua:292-293`), wired by `core/DebugLogSetup.lua` |
| `help` | `modules/IconGrid_Handle.lua:135`, `modules/Castbar_Handle.lua:94` (`helpIcon = NS.Icon("help")`) |
| `segment` | `settings/Spells.lua:602` (`W.ReorderList` `handleIcon`) |

Not declared: `info` (no `O.IdList`, and no `W.TestStrip` host), `confirm` (no Sim session), and no
`ph:` or `gi:` name. Hand lists have drifted before: `tests/test_mediasetup.lua:28` said KickCD
"never calls NS.Icon itself" while four sites did. The owner's in-client smoke (SM-KC-1 to SM-KC-5)
is the backstop: a pruned icon still resolves to a path and draws blank.

```sh
lua <scratch>/v175/tools/prune-icons.lua <abs KickCD path>
# prune-icons: ...KickCD: 5 icon(s) declared; kept 6 file(s), removed 5834
find libs/LibKa0s/media/icons -type f | sort
# LICENSE-open-iconic.txt clear.tga close.tga copy.tga help.tga segment.tga
```

Removed by set: Open Iconic 219 marks, Phosphor (`phosphor/`, 1,434 marks and its license) and
Game-icons (`game-icons/`, 4,178 marks, its license and `AUTHORS.txt`). After the prune the only
difference from the tag is `Only in <scratch>/v175/LibKa0s/media/icons...` lines for undeclared icons,
and `tests/test_vendor_sync.lua` passes the icon gate.
