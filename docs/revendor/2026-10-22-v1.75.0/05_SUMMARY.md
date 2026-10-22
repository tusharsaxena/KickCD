# Summary (KickCD)

LibKa0s v1.71.0 -> v1.75.0 from the local annotated tag (`265a89e`, via `git archive`). The base
comes from the CLAUDE.md provenance line and matches the payload bytes. v1.72.0 to v1.74.0 were
never vendored here, so this one bundle covers the range and no span bundle is written. Payload:
Perf 15, Options 29 with the new OptionsDrawer 1, Media 5 with the new MediaIcons 1, OptionsTabs 9,
Core 11, DebugLog 20 and DebugLogDiagnostics 3, OptionsIdList 5, PerfPanel 7, Widgets 13, Item 3,
and the new majors Glow 1 and Sim 1.1.1. Kit 38 -> 41.

In the same commit as both payloads:

- the CLAUDE.md provenance line rolls v1.71.0 -> v1.75.0, and `LibKa0s icons: clear, close, copy,
  help, segment.` is written directly under it (line 43, CRLF);
- the tag's `tools/prune-icons.lua` keeps 6 files (the five `.tga` and `LICENSE-open-iconic.txt`) and
  removes 5,834 (219 Open Iconic marks, `phosphor/`, `game-icons/`);
- `settings/OptionsSetup.lua`'s Options stub gains `Drawer` as an inert no-op (blocker 1); no
  `__releaseChrome` mirror existed to remove;
- `tests/test_options_panel.lua` counts eleven Options files and checks `info` against the
  declaration instead of the disk; `tests/test_mediasetup.lua` drops the whole-catalog loop and the
  drifted hand list for the declaration plus two new cases (blockers 2 to 4);
- stale mentions corrected: `core/MediaSetup.lua`, `docs/module-map.md` (the 113-name set),
  `docs/testing.md` (the expected `Only in ... media/icons` lines, the prune, kit 41's crashed
  lizard), `DEPENDENCIES.md` (kit 41's crashed lizard), `docs/debug.md` (DebugLog 20.3.1),
  `docs/smoke-tests.md` PANEL-30 (no `info` art ships);
- README `## Credits` names Open Iconic by Waybury, MIT, with what KickCD draws from it; JetBrains
  Mono kept; no Phosphor or Game-icons line;
- `docs/test-cases.md` regenerated and the README badge moved to the new total.

- **Delivered free (class A):** the scroll-keeping structural refresh, the fuller diagnostics
  header, kit 41's crashed-lizard rule and icon gate.
- **Decided adopt:** `LibKa0s-Glow-1.0`, by KC-01 in M3 (not in this commit).
- **Decided not adopted in this run:** `W.SearchBox`, `W.TestStrip`, `LibKa0s-Sim-1.0` (KickCD#38
  stays open), `Item.BonusIDsFromLink`, `O.Drawer`, `Perf.Note(..., false)`. The step panel is
  Sim-private (LK-11 outcome B). No issue filed.

Gate after the copy and prune:

- tests (`ka0s-bounded lua tests/run.lua`): 1330 passed, 0 failed, 1 skipped, 1331 total;
  `test_vendor_sync` resolves v1.75.0 from `../LibKa0s` and passes the icon gate.
- `docs/test-cases.md`: `| Skipped | 1 |`, `| **Total** | **1330** |`, equal to the README badge
  (1330/1330, was 1329/1329).
- luacheck (`ka0s-bounded luacheck .`): 0 warnings / 0 errors in 128 files.
- 1500-line cap: largest authored `.lua` is `modules/IconGrid.lua` at 997 lines.
- `diff -r --strip-trailing-cr` and `diff -r` of both payloads against the tag empty before the
  prune; `tests/_kit/run-automated-tests.sh` stays executable.

In-client smoke (owner's): SM-KC-1 to SM-KC-5 in the run bundle's `06_SMOKE_TESTS.md`.
