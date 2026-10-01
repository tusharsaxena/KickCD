# Candidates (KickCD)

Listed, not interviewed: spec S4 of the 2026-10-01 issue pass defers adoption to the run's own items and
to GI-LK-13's consumer census.

- **`RenderGrid(ctx, items, parent, opts)` with `opts.gap = false`** (OptionsWidgets minor 34). The
  reason this release carries the change: KickCD#10, the Spells list drawn through `RenderGrid` at the
  `ReorderList` stride (`settings/Spells.lua` `fillRows`). Adopted by GI-KC-11 later in this run.
- **`RenderTabbedSchema`'s `opts.disabledReplaces` and `opts.rerender`** (OptionsTabs minor 8). The
  linked-Focus Grid page draws its strip by hand (`settings/Panel_Render.lua:163-176`) because minor 4's
  `disabledFor` drew the notice above disabled rows (KC-20, issue #23, will-not-do). `disabledReplaces`
  draws the notice instead of the rows, which removes one of the two gaps named there; the inert strip and
  the LinkRow notice are still not the library's.
- **Perf `budget = { msPerSec, maxMs }`** per bucket (Perf minor 14), report-only. KickCD has two
  committed captures (`docs/perf-analysis/`); the issue design's rule is ceil(2x) the worst observed
  figure per top-level bucket.
- **The Slash `textOf` resolver** (Slash minor 19). `settings/Slash.lua`'s `parseForHost(row, text)`
  calls `SlashLib.ParseValue(row, text)` with two arguments. Passing the third argument it now receives
  would let a KickCD `L` reach the parse refusals; the locale carries none of those keys today, so nothing
  visible changes either way.
- **Kit 35's sighted complexity suite.** Not optional: wired by this re-vendor (`01_DELTA.md` 3f).
