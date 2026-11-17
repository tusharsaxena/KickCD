Delta: LibKa0s v1.93.0 -> v1.105.0

Recorded before anything was committed. Payload taken from the tag, never the sibling tree: `git -C ../LibKa0s archive v1.105.0 LibKa0s testkit tools` (tag commit 79b1d9c4, local annotated tag, not yet pushed; that is expected for this run). Run under Ka0sAddonsCommonTasks `docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS/`, item RV-KC (copy and bundle half of `/dev-copilot:wow-revendor-libka0s` 2.10.0; the adoption interview and issue filing are skipped, phase [3]).

## Step 0 pre-flight (this addon)
- Newest single-tag bundle `2026-11-07-v1.93.0` states base v1.92.0; the provenance line before its re-vendor commit `1f40c2f` named v1.92.0. ok, no correction owed.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` named v1.93.0 (CLAUDE.md:42) before the roll.
- Last payload commit, `git log -1 --format=%h -- libs/LibKa0s tests/_kit` = 70321b3; its CLAUDE.md names v1.93.0. They agree.
- Payload before the copy equalled the library at v1.93.0: `diff -rq` of `libs/LibKa0s` (outside the pruned `media/icons`) and of `tests/_kit` against a v1.93.0 extract printed nothing (payload-matches).
- Library range: `git -C ../LibKa0s log --oneline v1.93.0..v1.105.0` is 117 commits; `git diff --shortstat v1.93.0 v1.105.0 -- LibKa0s testkit` is 419 files, +10325 / -721.

## 3b/3c Per-file minors that moved (old = this addon, new = v1.105.0)
Derived from the tag's `LibKa0s.xml` with the spec's loop (`local (MAJOR, )?[A-Z_]*MINOR` grep per file).
```
Core.lua  old: 17  new: 18
Tooltip.lua  old: none  new: 1
Compat.lua  old: 3  new: 4
Role.lua  old: none  new: 1
Callout.lua  old: none  new: 4
CalloutSettings.lua  old: none  new: 5
WaypointArrow.lua  old: none  new: 2
WaypointArrowSettings.lua  old: none  new: 2
Charts.lua  old: 1  new: 2
Media.lua  old: 12  new: 13
Skin.lua  old: 17  new: 18
SkinDefs.lua  old: 27  new: 28
SkinDefsOthers.lua  old: 8  new: 10
Widgets.lua  old: 26  new: 27
WidgetsDropdown.lua  old: 1  new: 2
WidgetsReorder.lua  old: 6  new: 7
WidgetsDragHandle.lua  old: 13  new: 14
WidgetsDragHandleTip.lua  old: none  new: 1
WidgetsCopyWindow.lua  old: 5  new: 6
WidgetsHeader.lua  old: none  new: 1
WidgetsBar.lua  old: none  new: 1
DebugLog.lua  old: 22  new: 23
DebugLogDiagnostics.lua  old: 7  new: 11
DebugLogWindow.lua  old: 4  new: 5
Launcher.lua  old: 9  new: 11
OptionsWidgets.lua  old: 45  new: 46
OptionsNav.lua  old: 6  new: 7
OptionsSkinPicker.lua  old: 11  new: 12
OptionsSkinPickerQueue.lua  old: none  new: 1
IconBrowserWindow.lua  old: 1  new: 2
IconBrowser.lua  old: 1  new: 2
PerfPanel.lua  old: 13  new: 14
Sim.lua  old: 2  new: 3
SimPanel.lua  old: 10  new: 11
SimPanelRender.lua  old: 3  new: 4
```
Every file not listed matched v1.105.0 before the copy, so there is no cross-major skew. New files in the range: Role (v1.95.0), Callout and CalloutSettings (v1.96.0), WaypointArrow and WaypointArrowSettings (v1.99.0), Tooltip, WidgetsDragHandleTip, WidgetsHeader, WidgetsBar and OptionsSkinPickerQueue (v1.105.0). The harness derives its library load list from the XML (`tests/run.lua`, `Loader.xmlFiles`), so no loader line is owed.

## 3d Diffs
Before the prune, `diff -r --strip-trailing-cr` and `diff -r` of both payloads against the v1.105.0 extract were both empty (content and bytes). After the prune the only differences are `Only in <extract>/LibKa0s/media/icons` (undeclared icons) and `Only in <extract>/LibKa0s/media/sounds` (no `LibKa0s sounds:` line, so none ship). No `Only in libs/LibKa0s` line: nothing removed upstream survives here.

## 3e Consumption map (host source, `grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)'`, libs/ and tests/ excluded)
```
core/CoreSetup.lua:72:LibStub("LibKa0s-Core-1.0", true)
core/DebugLogSetup.lua:43:LibStub("LibKa0s-DebugLog-1.0", true)
core/LifecycleSetup.lua:50:LibStub("LibKa0s-Lifecycle-1.0", true)
core/LauncherSetup.lua:65:LibStub("LibKa0s-Launcher-1.0", true)
core/Constants.lua:63:LibStub("LibKa0s-Bus-1.0", true)
core/EnvSetup.lua:61:LibStub("LibKa0s-Env-1.0", true)
core/Database_Migrations.lua:395:LibStub("LibKa0s-Skin-1.0", true)
core/Database_Migrations.lua:488:LibStub("LibKa0s-Skin-1.0", true)
core/Database_Migrations.lua:569:LibStub("LibKa0s-Skin-1.0", true)
core/Compat.lua:35:LibStub("LibKa0s-Compat-1.0", true)
core/GlowSetup.lua:15:LibStub("LibKa0s-Glow-1.0", true)
core/PoolSetup.lua:38:LibStub("LibKa0s-Pool-1.0", true)
core/PerfSetup.lua:33:LibStub("LibKa0s-Perf-1.0", true)
core/SimSetup.lua:35:LibStub("LibKa0s-Sim-1.0", true)
core/SkinSetup.lua:112:LibStub("LibKa0s-Skin-1.0", true)
core/MediaSetup.lua:57:LibStub("LibKa0s-Media-1.0", true)
modules/Castbar_Handle.lua:41:LibStub("LibKa0s-Widgets-1.0", true)
modules/IconGrid_Handle.lua:42:LibStub("LibKa0s-Widgets-1.0", true)
modules/Sim.lua:431:LibStub("LibKa0s-Sim-1.0", true)
settings/SchemaSetup.lua:438:LibStub("LibKa0s-Schema-1.0", true)
settings/OptionsSetup.lua:71:LibStub("LibKa0s-Options-1.0", true)
settings/Spells.lua:614:LibStub("LibKa0s-Widgets-1.0", true)
settings/Slash.lua:55:LibStub("LibKa0s-Slash-1.0", true)
settings/Spells_Rows.lua:359:LibStub("LibKa0s-Widgets-1.0", true)
```
Majors in the payload with no host lookup: Item, Toast, Callout, WaypointArrow, Charts, IconBrowser, Role, Tooltip (whole-module candidates, class C; see 02_CANDIDATES.md).

## 3f Kit revision
`grep -n 'Kit.VERSION'`: tests/_kit 53 -> 57 (extract 57). Both payloads copied whole in one commit, so the pairing rule holds by construction. Kit 57 holds a frame with a raw event registration until it unregisters (LK-75); no KickCD suite relied on a collection dropping one (the suite is green). `mock_screen.lua` is new and opt-in. `LIBRARY_MARKS` gains `settings`, which this addon already declares.

## 3g Contract delta
Majors that moved a minor and that this addon looks up: Core, Compat, Media, Skin, Widgets, DebugLog, Launcher, Options, Perf, Sim. Read against the tag's `CHANGELOG.md` "What a consumer owes" blocks (v1.94.0 .. v1.105.0) and the DebugLog `docs/api/DebugLog/version-23.11.1.5-docs.md` "What a host owes at its re-vendor".
- `grep -rn '__Attach[A-Za-z]*'` outside libs/ and _kit finds one comment (settings/Panel.lua:181, the `LSMValues` shadow kept as a closure for the row-declaration-time read); OptionsCompose stays at minor 19 across this range, so that contract did not move.
- `grep -rn '__releaseChrome'` finds only the history comment in settings/OptionsSetup.lua:501-502; no mirror to remove.
- **Blockers: none.** Every red at the gate was a by-name stub-parity case or a count pin (fixed in the re-vendor commit, see 05_SUMMARY.md), not a host member whose call site moved.

## 3h Span bundle
The audit's walk (payload paths plus provenance rolls since the store's horizon) against the recorded bundles printed nothing: every vendored tag has a bundle. No span bundle is owed.

## 3i Icon declaration
`grep -n 'LibKa0s icons:' CLAUDE.md`: CLAUDE.md:43, the next non-blank line under the provenance line. Kept as written: `chevron-down, chevron-up, clear, close, confirm, copy, eye, help, info, move, reset, segment, settings, volume-high.` It already carries `settings`, which kit 57's `LIBRARY_MARKS` now requires of every host. Hand lists have drifted before (KickCD `tests/test_mediasetup.lua:28`); the owner's in-client smoke is the backstop for a name the host forgot to declare.

## 3j Whole-catalog tests
`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests`: tests/test_options_panel.lua:640/647 opens `info.tga`, a declared name; tests/test_mediasetup.lua:109 builds a name set from `Media.ICONS` (catalog names, no file opened). Neither assumes the whole folder ships; no blocker.
