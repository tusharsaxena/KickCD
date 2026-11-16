# 02 Candidates

Sources: the tag's `CHANGELOG.md` blocks v1.94.0 .. v1.105.0, its "What a consumer owes" lists, and Ka0sAddonsCommonTasks `docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS/03_ADOPTION_PLAN.md` with research note R7 (KickCD row). Under the owner's ruling Q6 of 2026-11-16, the rules for the new surfaces bind a host when it adopts the feature, not at this re-vendor.

## Class A: delivered by the re-vendor alone
- Skin colors (#82, #84): Ka0s Default's row stripe/hover/selection values, seven skins' `icon.hot`, Glass and High Contrast `icon.tint`. The host copy `NS.SKIN_FALLBACK` still equals the live Ka0s Default values (`tests/test_surface_parity.lua`, "each host-copy skin token is the live library's Ka0s Default value", green).
- Header marks (#86) on the library windows this addon opens (the debug console, the copy window, the perf panel, the sim panel, the skin picker): extras, settings, close.
- The debug console's 24 px Widgets footer (#90) and plain-text Copy (#79 part).
- The library's own tooltips through the placers (#92 part B): dropdowns, reorder handles, drag strips with no `tooltipPlace` hook, the sim panel, the minimap button.
- The sim panel's default title (#78); KickCD sets its own title, so no player sees it.
- OptionsWidgets 46: a slider box takes no junk text.

## Class B: host change required (owed in phase [3], not offered in this run)
| Issue | Surface | KickCD sites | Note |
|---|---|---|---|
| LibKa0s#79 | `D:Report` / `D:Serialize` | `/kcd spells list` (core/KickCD.lua:890) and the `/kcd debug spells|castbar|interrupt|window|events` dumps (DEBUG_COMMANDS, core/KickCD.lua:444) | Report verbs move onto the seam; the stub members already landed in this commit. |
| LibKa0s#88 | Docked HUD test/sim strip (`dock="hud"`) | icon grids and cast bar under `/kcd sim` | Reverses ruling D-13 (step panel only, no strip); `tests/test_sim_marker.lua` is inverted at adoption, never before. |
| LibKa0s#92 | `LibKa0s-Tooltip-1.0` placers | modules/IconGrid_Render.lua:319 (HUD, `ANCHOR_RIGHT`); settings/Spells_Rows.lua:85 and :174 (Settings canvas, likely out of scope; confirm per site) | |
| LibKa0s#87 | `Sim.SAMPLE` / `Sim.Sample(client)` | none found by grep for sample character names in modules/ and core/ | Re-check at adoption; likely N/A. |
| LibKa0s#86 | `W.HeaderButtons` on the host's own windows | 0 addon-owned windows (R7) | N/A unless a window is added; library windows already delivered (class A). |
| LibKa0s#89 | `W.Footer` | 0 hand-built footers (R7) | N/A. |
| LibKa0s#85 | Callout consumers | not a candidate addon in 03_ADOPTION_PLAN.md | N/A. |

## Class C: whole-module candidates
Majors with no host lookup: Item, Toast, Callout, WaypointArrow, Charts, IconBrowser, Role, Tooltip. Tooltip is the #92 row above; the rest have no recorded need in this addon and none is planned in phase [3].
