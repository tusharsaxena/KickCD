# Candidates

Range `v1.90.0..v1.91.0`, from the v1.91.0 CHANGELOG block and the moved majors' API documents (Core 17.1, Widgets 26.1.6.13.7.8.5, Skin 17.1.27.8.19.19.1.1.17.4.9). Decisions come from Ka0sAddonsCommonTasks `docs/2026-11-06-FOLLOWUPS_V1_91/00_PLAN.md`, not from an interview.

## Class A, delivered on the copy

- **The line chart's lines in physical pixels** (`FU-L1`, WidgetsLineChart 7, CHANGELOG v1.91.0 *The line chart's lines in physical pixels*): axis, grid, markers, crosshair and series lines are physical pixels at any UI scale. KickCD draws no line chart, so it carries the code and sees no change. No member, option or data field moves.
- **The four peels** (`FU-L2`, Core 17 / CorePixel 1, Widgets 26 / WidgetsDropdown 1, SkinPaintExtras 19 / SkinPaintHud 1 / SkinAceConfirm 1): pure moves into new payload files, "No member, option or behavior changes". They load in `LibKa0s.xml` order through the TOC and, headless, through `Loader.xmlFiles` (`tests/run.lua:53`).

## Class B, host change

None. v1.91.0 adds no surface, descriptor field or row type.

## Class C, whole-module

None. No major is new at v1.91.0. `LibKa0s-IconBrowser-1.0` and `LibKa0s-Toast-1.0` stay unadopted, as the v1.89.0 bundle settled (no icon chooser, no toast).
