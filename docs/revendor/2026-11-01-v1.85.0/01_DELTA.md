Delta: LibKa0s v1.84.0 -> v1.85.0

Part of Ka0sAddonsCommonTasks `docs/2026-11-01-FULL_SKINNING/` (FS-KC-RV). The tag is local, at commit `9776130`.

## Base (3a, 3b)

`grep -n '[Bb]undles' CLAUDE.md` named v1.84.0, and the last commit touching either payload left that line. The per-file minors below are the 3c loop's old column, so the bytes agree. The newest single-tag bundle `2026-11-01-v1.84.0-recut` states base v1.83.0, the addon's history. No correction owed.

## Per-file minors (3c), moved files only

`for f in LibKa0s.xml files: grep the [A-Z_]*MINOR constant, old against tag`

| File | old | new |
|---|---|---|
| Glow.lua | 1 | 2 |
| Toast.lua | 1 | 2 |
| Skin.lua | 11 | 14 |
| SkinDefs.lua | 19 | 24 |
| SkinDefsOthers.lua | 1 | 6 |
| SkinPaint.lua | 13 | 16 |
| SkinPaintExtras.lua | 7 | 15 |
| SkinPaintControls.lua | 11 | 14 |
| SkinEUI.lua | 2 | 3 |
| SkinAce.lua | 6 | 9 |
| Widgets.lua | 17 | 20 |
| WidgetsReorder.lua | 3 | 5 |
| WidgetsDragHandle.lua | 10 | 12 |
| WidgetsLineChart.lua | 5 | 6 |
| WidgetsAutocomplete.lua | 5 | 6 |
| WidgetsCopyWindow.lua | 2 | 4 |
| DebugLogWindow.lua | 2 | 3 |
| Launcher.lua | 5 | 6 |
| OptionsWidgets.lua | 41 | 44 |
| OptionsIds.lua | 6 | 7 |
| OptionsIdList.lua | 7 | 8 |
| OptionsTabs.lua | 13 | 15 |
| OptionsCompose.lua | 16 | 17 |
| OptionsScroll.lua | 10 | 13 |
| OptionsNav.lua | 4 | 5 |
| OptionsDrawer.lua | 4 | 5 |
| OptionsKeybinds.lua | 6 | 7 |
| OptionsAppearance.lua | 5 | 6 |
| OptionsSkinPicker.lua | 5 | 7 |
| OptionsMedia.lua | 3 | 4 |
| PerfPanel.lua | 11 | 12 |
| SimPanel.lua | 9 | 10 |
| SimPanelRender.lua | 1 | 2 |

No file is behind the old tag: no cross-major skew.

## Kit (3f)

`grep -n 'Kit.VERSION'`: revision 47 -> 49. The two payloads move together.

## Consumption (3e)

Lookups outside `libs/` and `tests/`: Bus, Charts, Compat, Core, DebugLog, Env, Glow, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Skin, Slash, Widgets. Unchanged.

## Blockers (3g, 3j)

- **Facades.** CHANGELOG v1.85.0, "What a consumer owes": the degraded Skin facade (`core/SkinSetup.lua`) gains `Mark`, `MarkText`, `HudTextColor`, `HudLabelColor`, `BarFillColor`, `HudShadow`, `BarGloss` and `HudFont`, the last the one that must draw; the Options stub (`settings/OptionsSetup.lua`) gains `LabelFont`.
- **Icons.** `docs/releasing.md` Step 8 for v1.85.0 owes `chevron-down, chevron-up, close, confirm, info, move, reset, volume-high`; this addon's own draws add `clear, copy, help, segment, settings`. Decided by the plan, not re-asked. Hand lists have drifted before; the owner's smoke is the backstop.
- **3j.** `tests/test_options_panel.lua` asserted `info` stays off the line while no id list is drawn; kit revision 49 now owes it. Fixed in the re-vendor commit.
- No `__Attach*` mirror, and `__releaseChrome` is only named in a comment here.

## Unrecorded tags (3h)

v1.80.0 to v1.83.0 are recorded by the span bundle `2026-10-31-v1.80.0-v1.83.0`; nothing unrecorded.
