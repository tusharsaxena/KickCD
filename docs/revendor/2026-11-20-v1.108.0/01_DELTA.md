Delta: LibKa0s v1.107.0 -> v1.108.0

Recorded with the re-vendor commit. Payload taken from the tag, never the sibling tree: `git -C ../LibKa0s archive v1.108.0 LibKa0s testkit tools` (tag commit 56c20b76, a local tag, not yet on origin: `git -C ../LibKa0s ls-remote --tags origin v1.108.0` prints nothing; expected for this run). Run under Ka0sAddonsCommonTasks `docs/2026-11-20-LIBKA0S_94_97_99_100/`, item SD-RV-KC (the copy, provenance, icon-declaration and prune mechanics of `/dev-copilot:wow-revendor-libka0s` 2.10.1; the adoption interview and issue filing are skipped by the run's instructions).

## Step 0 pre-flight (this addon)
- Newest single-tag bundle `2026-11-19-v1.107.0` states base v1.106.0; the provenance line before its re-vendor commit (`ee02304^`) named v1.106.0. ok, no correction owed.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` named v1.107.0 before the roll.
- Last payload commit, `git log -1 --format=%h -- libs/LibKa0s tests/_kit` = 5f9d0c5 (the re-cut v1.107.0); its CLAUDE.md names v1.107.0. They agree.
- Payload before the copy equalled the library at v1.107.0: `diff -rq` of a v1.107.0 extract against `libs/LibKa0s` printed only the declaration-pruned `media/icons` and `media/sounds/callout`, and `tests/_kit` matched (payload-matches).
- Library range: `git -C ../LibKa0s log --oneline v1.107.0..v1.108.0` is 15 commits; `git -C ../LibKa0s diff --stat v1.107.0 v1.108.0 -- LibKa0s testkit` is 23 files, +1363 / -306.

## 3b/3c Per-file minors that moved (old = this addon, new = v1.108.0)
Derived from the tag's `LibKa0s.xml` with the spec's loop.
```
Core.lua                  old: MINOR 18             new: MINOR 19
Callout.lua               old: MINOR 4              new: MINOR 5
CalloutSettings.lua       old: SETTINGS_MINOR = 5   new: SETTINGS_MINOR = 6
WaypointArrow.lua         old: MINOR 2              new: MINOR 3
WaypointArrowSettings.lua old: SETTINGS_MINOR = 2   new: SETTINGS_MINOR = 3
Charts.lua                old: MINOR 2              new: MINOR 3
ChartsRender.lua          old: RENDER_MINOR = 1     new: RENDER_MINOR = 2
SkinPaint.lua             old: PAINT_MINOR = 19     new: PAINT_MINOR = 20
SkinPaintHud.lua          old: HUD_MINOR = 1        new: HUD_MINOR = 2
SkinPaintControls.lua     old: CONTROLS_MINOR = 18  new: CONTROLS_MINOR = 19
Widgets.lua               old: MINOR 29             new: MINOR 30
WidgetsDropdown.lua       old: DROPDOWN_MINOR = 2   new: DROPDOWN_MINOR = 3
WidgetsDragHandle.lua     old: DRAG_MINOR = 15      new: DRAG_MINOR = 16
WidgetsDragHandleTip.lua  old: DRAGTIP_MINOR = 2    new: DRAGTIP_MINOR = 3
WidgetsLineChart.lua      old: CHART_MINOR = 7      new: CHART_MINOR = 8
WidgetsBar.lua            old: BAR_MINOR = 1        new: BAR_MINOR = 2
OptionsCompose.lua        old: COMPOSE_MINOR = 19   new: COMPOSE_MINOR = 20
```
Every other file at its v1.107.0 minor. No cross-major skew.

## 3d Diffs
- After the copy, before the prune: `diff -r --strip-trailing-cr` and `diff -rq` of the extract against `libs/LibKa0s` both empty; `diff -rq` of the kit against `tests/_kit` empty.
- After the prune: only the undeclared icons and the 362 sound files are `Only in` the extract.

## 3e Consumption
Majors looked up outside `libs/` and `tests/`: Bus, Compat, Core, DebugLog, Env, Glow, IconBrowser, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Skin, Slash, Tooltip, Widgets. Callout, Charts and WaypointArrow are in the payload and not consumed (unchanged from v1.107.0).

## 3f Kit revision
`Kit.VERSION` 57 -> 58 (`SD-LK-GUARD`). Both payloads move in one commit, as the pairing rule requires.

## 3g Contract delta
Read: the tag's `CHANGELOG.md` v1.108.0 block in full (*What a consumer owes at its re-vendor*), the Options document `docs/api/Options/version-38.5.46.3.7.2.9.17.3.1.4.20.13.7.5.8.7.12.1.1.1.4-docs.md` (*Moving to this version: what each addon owes*, `O.ColorPair`, `O.FontGroup`, `O.BarGroup`, `O.BorderGroup`) and the testkit 58 consumer steps. Found and fixed in the re-vendor commit:
- **OptionsCompose minor 20 emits companions by default.** KickCD's composer calls already pass `fromSkin` and write every color and shadow companion in `extra`, so the composer emits none twice. The only new rows were `barColorFromSkin` on both cast-bar states and `cooldownTintFromSkin` on the icons, per unit (338 -> 344 settings, red in `test_schema`, `test_tab_partition`, `test_reset_logging`, `test_skin_flip` and the layout guard). All three are meaning colors (cast states, MC; the cooldown tint, owner D5 "leave warning tints"), so the two `H.BarGroup` calls and the cooldown tint's `H.ColorPair` pass `colorFromSkin = false`, cited beside each call. Back to 338.
- **Font shadow is disabled while its companion is on** (minor 20). `test_skin_flip`'s "every color and shadow companion" case pinned no `disabledIf` on any governed row; re-pinned so the three shadow rows carry their companion as `disabledIf` and the swatches still carry none.
- **WidgetsDragHandleTip minor 3 (LibKa0s#99).** Two `test_util_anchor` cases pinned the minor-2 fallback (a relative point on a strip whose rect reads secret or nil). Re-pinned: a secret strip places above its nearest readable ancestor by an absolute point; a strip with nothing readable up its chain hides the tooltip.
- **Test kit 58, the skin-switch spy walks `GetStatusBarTexture`.** KickCD's frame mock answered it on every object, so a Texture made a Texture without end: about 60 MB retained per declared surface, until the 1024 MB heap budget stopped the run after 18 surfaces. `tests/wow_mock_frames.lua` now answers a fill only on a StatusBar, as the client does.
- **Test kit 58, `test_skin_values` reads keyed `{ r, g, b }` tables and return triples.** 18 new hits: the composers' typed defaults in `settings/Castbar.lua`, `settings/Icons.lua` and `settings/Label.lua` (each the companion-off swatch, mirroring `defaults/Profile.lua`, which the kit's "defaults swatch" category takes; or a meaning color), `Util.Unpack`'s nil answer and the glow's non-table fallback (kit row category "unreachable default") and the Spells rows' `WHITE` (category "white base for tinting"). Each has a row in `tests/skin_facts.lua` with its why and cause or category.
- Not consumed, so nothing owed: `W.Bar`, Charts, `S.ApplyBarFill`, `W.ContextMenu`, the Callout, the waypoint arrow, `skinBands`. `S.BarGloss` is called on both cast-bar StatusBars, the shape it always took.

Blockers needing a decision: none.

## 3h Unrecorded tags
The audit's walk prints nothing new: v1.107.0 has its bundle. (The re-cut of v1.107.0 in 5f9d0c5 wrote no `06_REFRESH_1.md` into that bundle; that bundle is frozen and this run does not edit it.)

## 3i Icon declaration
`LibKa0s icons: chevron-down, chevron-up, clear, close, confirm, copy, eye, help, info, move, reset, segment, settings, volume-high.` kept as written, directly under the provenance line. No new library-drawn icon in this range. No `LibKa0s sounds:` line, so sounds are none.

## 3j Whole-folder icon tests
None in this addon.
