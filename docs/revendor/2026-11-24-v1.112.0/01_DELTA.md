Delta: LibKa0s v1.111.0 -> v1.112.0

Recorded with the re-vendor commit. Payload taken from the tag, never the sibling tree: `git -C ../LibKa0s archive v1.112.0 LibKa0s testkit tools` (tag commit 1f1904ee, a local tag, not yet on origin; expected for this run). Run under Ka0sAddonsCommonTasks `docs/2026-11-24-FEEDBACK_BATCH/`, item FB-KC-01 (the copy, provenance, icon-declaration and prune mechanics of `/dev-copilot:wow-revendor-libka0s` 2.11.0; the adoption interview and issue filing are skipped by the run's instructions, and the run's decisions pre-decide adoption: `FollowColor` and the preview stand-in).

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` named v1.111.0 before the roll.
- Tags vendored since the newest bundle (`2026-11-20-v1.108.0`) without a bundle of their own: v1.109.0, v1.111.0. They were recorded in their own Ka0sAddonsCommonTasks run bundles; this bundle names them and adds no span bundle.
- Library range: `git -C ../LibKa0s diff --stat v1.111.0 v1.112.0 -- LibKa0s testkit`.

## 3b/3c Per-file minors that moved (old = this addon, new = v1.112.0)
```
Core.lua                  old: MINOR 19             new: MINOR 20
IconBrowserWindow.lua     old: WINDOW_MINOR = 2     new: WINDOW_MINOR = 3
SkinDefsOthers.lua        old: OTHERS_MINOR = 10    new: OTHERS_MINOR = 11
SkinPaintControls.lua     old: CONTROLS_MINOR = 20  new: CONTROLS_MINOR = 21
WidgetsCopyWindow.lua     old: COPY_MINOR = 6       new: COPY_MINOR = 7
WidgetsHeader.lua         old: HEADER_MINOR = 1     new: HEADER_MINOR = 2
```
Kit revision: 60 -> 60.

## Blockers (fixed in the re-vendor commit)
- SkinDefsOthers minor 11 dropped High Contrast's `hud.shadowX/Y` 2, -2: `tests/test_skin_flip.lua` (the charges badge case) re-pinned to 1, -1.

## 3i Icons
- `LibKa0s icons:` line kept as written. Prune: the undeclared icons and the 362 sound files (no `LibKa0s sounds:` line, so none).

## Title bars (standard v2.119.0, companion windows)
- This addon builds no title bar of its own (`grep -rnE "HeaderButtons|CopyWindow|settingsOptOut|hideOnSettings" --include='*.lua' . | grep -v "libs/\|tests/_kit"` prints nothing). Its windows are the library's: the debug console and the perf panel keep the gear; the copy window is now a companion (WidgetsCopyWindow minor 7) and carries the close alone. Its StaticPopups are companions. Nothing owed.
