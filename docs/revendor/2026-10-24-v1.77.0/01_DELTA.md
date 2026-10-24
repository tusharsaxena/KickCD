Delta: LibKa0s v1.76.0 -> v1.77.0

Run non-interactively by item `KC-RV` of the 2026-10-24 run "keybindings (015), settings layout
(020), frame strata (030)", on branch `feat/2026-10-24-keybinds-layout-strata`, following the
installed `/dev-copilot:wow-revendor-libka0s` at 2.4.0. Both payloads are copied whole, the
provenance line rolls, the copy is pruned to the unchanged `LibKa0s icons:` line, and every adoption
candidate is recorded as decided by the run's plan (`02_CANDIDATES.md`). There is no interview and
no GitHub issue is filed.

## Source

```sh
git -C ../LibKa0s rev-parse 'v1.77.0^{commit}'   # 78240f7 (annotated, LOCAL; not pushed in this run)
git -C ../LibKa0s archive v1.77.0 LibKa0s testkit tools | tar -x -C <scratch>/new
```

The payload comes from the tag through `git archive`, never from the library's working tree.
`tools/` is extracted only for `prune-icons.lua` and is not copied into the addon.

## Pre-flight (Step 0)

KickCD's newest single-tag bundle, `../2026-10-23-v1.76.0/`, states base v1.75.2, and the provenance
line before its re-vendor commit `80babdc` named v1.75.2: ok. No base correction is owed.

## Base (3a, 3b)

```sh
grep -n 'Bundles \[LibKa0s' CLAUDE.md
# 42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.76.0 (MIT).   (before the roll)
git log -1 --format='%h %s' -- libs/LibKa0s tests/_kit
# 58f1a9e KC-RV2: Re-vendor LibKa0s from the moved local tag v1.76.0 (LK-91)
git -C ../LibKa0s archive v1.76.0 LibKa0s testkit | tar -x -C <scratch>/old
diff -rq <scratch>/old/LibKa0s libs/LibKa0s | grep -v 'Only in <scratch>/old/LibKa0s/media/icons'
#   (empty: only the undeclared icons the prune removed)
diff -rq <scratch>/old/testkit tests/_kit && echo kit-base-ok
# kit-base-ok
```

Base v1.76.0 (`e692491`, the tag as KC-RV2 of the 2026-10-23 run left it): the provenance line, the
last payload commit and the bytes agree.

## Range

```sh
git -C ../LibKa0s log --oneline v1.76.0..v1.77.0
# 78240f7 LK-90: close v1.77.0 with its release record (20261024-074358)
# 3c2bb20 LK-90: split three functions over CCN 15 that the release run found
# ea2cb09 LK-90: close v1.77.0: version block, pointers, consumers, band
# 0a5807d LK-13: Sync the Keybindings tab with Options -> Keybindings
# 9ab9d37 LK-12: Add the Keybindings tab, OptionsKeybinds minor 2
# 0b10ad3 LK-11: address review — refuse BUTTON1/BUTTON2 on the client chord route
# 88dfa8a LK-11: Add OptionsKeybinds.lua minor 1, the key binding model
# 66b7bd4 LK-20: Add O.StrataTooltip, the one shared strata-row tooltip
# 7de587b LK-04: Close the IdList suggestion list at the start of combat
# f452d69 LK-03: Clamp the dropdown menu and the autocomplete list to the screen
# dda3ff9 LK-02: Add DragHandle level offset, ApplyLevel and ignoreParentAlpha
# 665bf63 LK-01: Make the tool windows toplevel and re-raise shown StaticPopups
# 8173cdb LK-10: Kit revision 42: binding mock, layer recorder, Bindings.xml check
# 0a1683a LK-00: Open v1.77.0 with an unreleased CHANGELOG section
# 9df6df8 Merge branch 'feat/2026-10-23-sim-preview-mode-strips'
git -C ../LibKa0s diff --stat v1.76.0 v1.77.0 -- LibKa0s testkit
#  18 files changed, 1672 insertions(+), 34 deletions(-)
#  (LibKa0s/: Core, DebugLog, LibKa0s.xml, Options, OptionsCombat, OptionsCompose, OptionsIds,
#   OptionsKeybinds (new, 819 lines), PerfPanel, SimPanel, Widgets, WidgetsAutocomplete,
#   WidgetsDragHandle; testkit/: README.md, bindings_xml.lua (new), framework.lua,
#   mock_bindings.lua (new), mock_layers.lua (new))
```

## Per-file minor delta (3c)

The loop over the tag's `LibKa0s/LibKa0s.xml` (41 files) prints twelve moved files; every other file
is at its v1.76.0 minor.

| File | Major | v1.76.0 | v1.77.0 |
|---|---|---|---|
| `Core.lua` | `LibKa0s-Core-1.0` | 11 | **12** |
| `DebugLog.lua` | `LibKa0s-DebugLog-1.0` | 20 | **21** |
| `PerfPanel.lua` | `LibKa0s-Perf-1.0` | `PANEL_MINOR` 8 | **9** |
| `SimPanel.lua` | `LibKa0s-Sim-1.0` | `SIM_PANEL_MINOR` 5 | **6** |
| `Widgets.lua` | `LibKa0s-Widgets-1.0` | 14 | **15** |
| `WidgetsDragHandle.lua` | `LibKa0s-Widgets-1.0` | `DRAG_MINOR` 4 | **5** |
| `WidgetsAutocomplete.lua` | `LibKa0s-Widgets-1.0` | `AUTOCOMPLETE_MINOR` 2 | **3** |
| `Options.lua` | `LibKa0s-Options-1.0` | 29 | **30** |
| `OptionsIds.lua` | `LibKa0s-Options-1.0` | `IDS_MINOR` 2 | **3** |
| `OptionsCombat.lua` | `LibKa0s-Options-1.0` | `COMBAT_MINOR` 1 | **2** |
| `OptionsCompose.lua` | `LibKa0s-Options-1.0` | `COMPOSE_MINOR` 7 | **8** |
| `OptionsKeybinds.lua` | `LibKa0s-Options-1.0` | (new) | `KEYBINDS_MINOR` **3** |

Composite keys (the tag's `CHANGELOG.md` v1.77.0 block, `CHANGELOG.md:21-31`): Core **12**, DebugLog
**21.3.1**, Perf **15.1.1.9**, Sim **2.3.6**, Widgets **15.1.5.3.3**, Options
**30.2.34.3.5.9.2.8.4.2.1.3**. Seventeen majors across forty-one files. No consumer file is behind
the tag after the copy, so there is no cross-major skew.

## Both diffs (3d)

Before the prune, `diff -r --strip-trailing-cr` and `diff -r` of both payloads against the tag were
empty. No `Only in libs/LibKa0s` line appeared, so nothing was deleted by hand. After the prune the
only difference is `Only in <scratch>/new/LibKa0s/media/icons…` lines for the undeclared icons.

## Consumption map (3e)

Seventeen majors are looked up outside `libs/` and `tests/`: Bus, Compat, Core, DebugLog, Env, Glow,
Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Slash and Widgets (the two `Item`
hits are the vendored `OptionsIds.lua` / `OptionsIdList.lua` reached through Options). Of the moved
majors KickCD reaches all six: Core, DebugLog (the console), Perf (the panel), Sim (`/kcd sim`),
Widgets (`W.ReorderList`, the DragHandle, `W.TestStrip`) and Options (the settings panel).

## Kit revision (3f)

```sh
grep -n 'Kit.VERSION =' <scratch>/new/testkit/framework.lua tests/_kit/framework.lua
# <scratch>/new/testkit/framework.lua:20:Kit.VERSION = 42
# tests/_kit/framework.lua:20:Kit.VERSION = 41    (before the copy)
```

Kit revision 41 -> **42** (`mock_bindings.lua`, `mock_layers.lua`, `bindings_xml.lua` with
`Kit.assertBindingsXml` and `Kit.keybindThroughTab`). Both payloads move together in one commit (the
pairing rule).

## Contract delta (3g)

### Blockers

- **The Options degradation stub owes four new instance members.** The tag's `CHANGELOG.md`
  *What a consumer owes* (v1.77.0 block): "Every Options degradation stub gains four instance
  members: `KeybindingsTab`, `KeybindRows`, `KEYBINDS_UNCHANGED` and `StrataTooltip`.
  `Kit.assertSurfaceParity` is red at the re-vendor until the stub answers them." Measured: after
  the copy, `tests/test_surface_parity.lua`'s "the Options stub carries every member the host calls"
  failed with exactly those four missing (`docs/api/Options/version-30.2.34.3.5.9.2.8.4.2.1.3-docs.md:61-63`
  and `:86`). Fixed in this commit in `settings/OptionsSetup.lua`'s stub: `KeybindingsTab` and
  `KeybindRows` join the inert no-op list (render-time only), `StrataTooltip` answers `""` and
  `KEYBINDS_UNCHANGED` is `""`, so the stub carries no copy of the library's words
  (`options-ui-§1`). This is MultiMeters' shape for the same members in this run.
- **The Options major is twelve files.** `tests/test_options_panel.lua`'s "libs/LibKa0s/Options.lua
  takes no locale override" pins the file count derived from the vendored XML at eleven;
  `OptionsKeybinds.lua` makes it twelve. The derived scan already covered the new file (it reads no
  `d.L`); only the count and its message move.

No `__Attach*` member KickCD supplies moved (`settings/Panel.lua:181` is a comment about
`__AttachCompose`, whose LSMValues contract did not change at Compose 8). The toplevel tool windows,
the clamped popups and the suggestion list's combat close take effect on the copy (class A).

### Bindings.xml

KickCD ships no `Bindings.xml`, so the kit's `Kit.assertBindingsXml` has nothing to check and no
test is marked pending.

## Unrecorded tags (3h)

The listing (vendored since the store's horizon minus recorded) is empty: every tag KickCD vendored
has a bundle. No span bundle is written.

## The icon declaration (3i), and tests that assume the whole folder (3j)

Kept unchanged, directly under the provenance line (`CLAUDE.md:43`):

```
LibKa0s icons: clear, close, confirm, copy, help, info, segment.
```

No candidate adopted in this commit draws a new catalog name.

```sh
lua <scratch>/new/tools/prune-icons.lua <abs KickCD path>
# prune-icons: ...KickCD: 7 icon(s) declared; kept 8 file(s), removed 5832
```

The same eight files ship as before (seven `.tga` and `LICENSE-open-iconic.txt`); `git status` shows
no change under `media/icons`. 3j: `tests/test_mediasetup.lua:109` reads `Media.ICONS` as a name
list and `tests/test_options_panel.lua:675` opens `info.tga`, which is declared; neither assumes the
whole folder. No README credit changes (the same Open Iconic set ships), and no `__releaseChrome`
mirror exists (`settings/OptionsSetup.lua:469` names it only as history).
