# Summary (KickCD)

LibKa0s v1.65.0 -> v1.66.0 from the local tag (`e4c5ef7`): Slash 18 -> 19 with the new SlashParse 1,
Widgets 11 -> 12 with the new WidgetsReorder 1, DebugLog 18 -> 19, OptionsWidgets 33 -> 34, OptionsTabs
7 -> 8, Perf 13 -> 14 with the new PerfSampler 1 and PerfCommands 1; every other file unchanged.
`tests/_kit` moves from kit revision 34 to 35. The base is the tag the `CLAUDE.md` provenance line named
(v1.65.0). Both content diffs are empty after the copy, and nothing was deleted.

Span bundle written: `2026-10-01-v1.64.0-v1.65.0/` (two tags, v1.64.0 and v1.65.0, vendored by the
2026-09-30 runs with no bundle). No base correction.

Blockers: none. No consumer test broke from a library change.

Host changes in the re-vendor commit: the `CLAUDE.md` provenance line and `docs/testing.md`'s version-now
line roll to v1.66.0; `tests/run.lua` declares `test_lizard_sighted`; the complexity rows in
`docs/testing.md` and `docs/performance.md` name the runner's suite rather than the raw (blind) lizard
command; `tests/test_icongrid_curves.lua` hoists three function literals out of a `for ... in` header,
the one file the sighted parity found blind. `docs/test-cases.md` and the README `Tests` badge move to
1246. The TOC needs no line: it loads `LibKa0s.xml`.

Adopted: nothing in this commit. `RenderGrid`'s `parent` / `opts.gap` is GI-KC-11's. The rest of
`02_CANDIDATES.md` is not interviewed this cycle.

Gate after the copy:

- tests: 1246 passed, 0 failed, 1 skipped, 1247 total (1238 / 0 / 1 of 1239 before; the eight new cases
  are kit 35's `test_lizard_sighted`)
- luacheck: 0 warnings / 0 errors in 114 files
- complexity (`bash tests/_kit/run-automated-tests.sh --suite complexity`, sighted): `pass`, maxCcn 46,
  3 warnings (CCN > 15: `Cooldowns.Refresh` 46, `IconGrid.Layout` 29, `tests/test_perfsetup.lua:916`
  anonymous 19; all left for GI-KC-12), blindFiles 0 (1 before the hoist)

Smoke: the re-vendor routing in `docs/smoke-tests.md` already covers what this release moves, including
SPELLS-13 (the drag reorder, `WidgetsReorder.lua`) and the DIAG perf checks (`PerfSampler.lua`,
`PerfCommands.lua`). Owner-run; not marked here.
