Delta: LibKa0s v1.90.0 -> v1.91.0

Part of Ka0sAddonsCommonTasks `docs/2026-11-06-FOLLOWUPS_V1_91/` (item FU-RV-KC, from `00_PLAN.md`). The tag is local and not pushed, at commit `55bfbb4`, so `git ls-remote --tags origin v1.91.0` prints nothing. This is a new tag, not a refresh. The payload was taken with `git -C ../LibKa0s archive v1.91.0 LibKa0s testkit tools`, never the working tree.

## Base (3a, 3b)

- `grep -n '[Bb]undles' CLAUDE.md` -> `42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.90.0 (MIT).`
- `git log -1 --format=%H -- libs/LibKa0s tests/_kit` -> `e4a6713` (the SF2 refresh), whose `CLAUDE.md` names v1.90.0. The two agree.
- `diff -rq <v1.90.0 extract>/LibKa0s libs/LibKa0s | grep -v media/icons` prints nothing, and `diff -rq <v1.90.0 extract>/testkit tests/_kit` is empty: the payload is v1.90.0's.
- The 3b minors (`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR ...' libs/LibKa0s/*.lua`) are the v1.90.0 set, so line and bytes agree.
- Step 0, the installed skill's version, was skipped: its roster regex matches nothing in the current `ADDONS.md`, a defect this run fixes in dev-copilot (`FU-DC1`). Run by hand for this addon: the newest single-tag bundle `2026-11-06-v1.90.0` states base v1.89.0, and `git show b6687f0^:CLAUDE.md` names v1.89.0. `ok`, no correction owed.

`git -C ../LibKa0s log --oneline v1.90.0..v1.91.0`: 7 commits, the `FU-L1` line-chart pixels, the four `FU-L2` peels and the two `FU-L3` release commits. `git -C ../LibKa0s diff --stat v1.90.0 v1.91.0 -- LibKa0s testkit`: 9 payload files, 4 of them new, nothing in `testkit`.

## Per-file minors (3c), moved files only

`for f in <v1.91.0 LibKa0s.xml files>: grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR ...' old against tag`

| File | old | new |
|---|---|---|
| Core.lua | 16 | 17 |
| CorePixel.lua | (new) | 1 |
| SkinPaintExtras.lua | 18 | 19 |
| SkinPaintHud.lua | (new) | 1 |
| SkinAceConfirm.lua | (new) | 1 |
| Widgets.lua | 25 | 26 |
| WidgetsDropdown.lua | (new) | 1 |
| WidgetsLineChart.lua | 6 | 7 |

The other 63 files of the 71 the XML lists are at their v1.90.0 minors. No file is behind the old tag, so there is no cross-major skew. Four files are new: `CorePixel.lua`, `SkinPaintHud.lua`, `SkinAceConfirm.lua` and `WidgetsDropdown.lua`.

## Diffs before the copy (3d)

`diff -rq [--strip-trailing-cr] <extract>/LibKa0s libs/LibKa0s` (media/icons `Only in` lines aside, the undeclared icons): `Core.lua`, `LibKa0s.xml`, `SkinPaintExtras.lua`, `Widgets.lua` and `WidgetsLineChart.lua` differ, and the four new files are `Only in` the extract. No `Only in libs/LibKa0s`. Kit: both diffs are empty (revision 51 on both sides).

## Kit (3f)

`grep -n 'Kit.VERSION'`: revision 51 -> 51. The two payloads still move together.

## Consumption (3e)

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`: Bus, Compat, Core, DebugLog, Env, Glow, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Skin, Slash, Widgets. Unchanged from v1.90.0.

## Contract delta (3g)

Moved and consumed: Core (17.1), Widgets (26.1.6.13.7.8.5) and Skin (SkinPaintExtras 19, SkinPaintHud 1, SkinAceConfirm 1). The v1.91.0 CHANGELOG block says of every peel "No member, option or behavior changes", and of `FU-L1` "No member, option or data field moves".

- Core 17 / CorePixel 1: the `__Pixel*` members moved file, not shape. `grep -rnE '__PixelSize|__WatchPixels|__OnPixelScale|__PixelBackdrop'` outside the payloads finds nothing.
- Widgets 26 / WidgetsDropdown 1: `lib.Dropdown`, `lib.ContextMenu` and `lib.CloseMenu` moved file. No use site in this addon's own code. WidgetsLineChart 7: KickCD draws no line chart.
- SkinPaintExtras 19 / SkinPaintHud 1 / SkinAceConfirm 1: `S.BarGloss` and `S.HudFont` moved file. KickCD's degradation stub (`core/SkinSetup.lua:561`, `:613`) mirrors them by name, not by file, and their shape did not move, so the stub is unchanged; `tests/test_surface_parity.lua` holds it to the live facade.
- `grep -rn '__Attach[A-Za-z]*'` outside the payloads: one comment, `settings/Panel.lua:181`, about `__AttachCompose`, which did not move.
- `docs/releasing.md` step 8 at the tag: v1.91.0 adds no Skin facade, major or instance member, and a consumer whose tests load library files by name adds the four new files.

**Blockers: none.** The library load list is derived, not typed: `tests/run.lua:53` and `tests/perf.lua:65` call `Loader.xmlFiles(root .. "/libs/LibKa0s/LibKa0s.xml")`, so the four new files load in the XML's order on the copy. `grep -rnE 'libs/LibKa0s/[A-Za-z]+\.lua' tests` finds only comments and `tests/test_coresetup.lua:357`, which reads `Core.lua` for `STRINGS`, which the peel did not add. `tests/test_coresetup.lua`'s `MAJORS` list names majors, and no major is new. No test pins a minor that moved.

## Icons (3i, 3j)

- `grep -n 'LibKa0s icons:' CLAUDE.md` -> line 43, directly under the provenance line: `chevron-down, chevron-up, clear, close, confirm, copy, eye, help, info, move, reset, segment, settings, volume-high.` Kept, decided by the plan. v1.91.0 adds no library-drawn icon. Hand lists have drifted before (`tests/test_mediasetup.lua:28`); the owner's in-client smoke is the backstop.
- 3j: `tests/test_options_panel.lua:639` opens `info.tga` (declared), and `tests/test_mediasetup.lua:109` reads `Media.ICONS` names only. No whole-catalog file loop, so no blocker.
- `__releaseChrome`: no mirror outside the payloads.

## Unrecorded tags (3h)

The 3h walk from horizon 2026-08-25, with `tag_at` written over a named variable (`rev="$1"`): 66 tags vendored, 66 recorded, and `grep -vxF -f recorded.txt vendored.txt` printed nothing. No span bundle.
