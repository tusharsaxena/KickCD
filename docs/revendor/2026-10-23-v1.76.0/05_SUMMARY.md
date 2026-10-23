# Summary (KickCD)

LibKa0s v1.75.2 -> v1.76.0 from the local annotated tag (`9949368`, via `git archive`). The base
comes from the CLAUDE.md provenance line and matches the payload bytes. Payload: SimTimeline 3 and
SimPanel 5 (Sim key 2.3.5), Widgets 14 (key 14.1.4.3.2); every other file unchanged. Kit 41
unchanged.

In the same commit as both payloads:

- the CLAUDE.md provenance line rolls v1.75.2 -> v1.76.0; `LibKa0s icons: clear, close, copy,
  help, segment.` stays directly under it;
- the tag's `tools/prune-icons.lua` keeps 6 files (the five `.tga` and `LICENSE-open-iconic.txt`)
  and removes 5,834, the same set as before;
- the span bundle `../2026-10-23-v1.75.1-v1.75.2/` records the two tags carried by sweep.

- **Contract blockers:** none. KickCD consumes neither Sim nor `TestStrip` yet.
- **Delivered free (class A):** nothing visible.
- **Decided adopt (later items of this run):** `LibKa0s-Sim-1.0` 2.3.5 (KC-01 to KC-08, KC-10;
  KickCD#38) and `TestStrip`'s `kind = "sim"` (KC-09).
- **Decided not adopted:** the amber test strip (no test mode). No issue filed.
- README credits unchanged; no dead stub mirror.

Gate after the copy and prune:

- tests (`ka0s-bounded lua tests/run.lua`): 1335 passed, 0 failed, 1 skipped, 1336 total;
  `test_vendor_sync` resolves v1.76.0 from `../LibKa0s` and passes the icon gate.
- `docs/test-cases.md`: `lua tests/run.lua --list` output identical to the committed file.
- luacheck (`ka0s-bounded luacheck .`): 0 warnings / 0 errors in 129 files.
- 1500-line cap: largest authored `.lua` is `modules/IconGrid.lua` at 997 lines.

The standard reference was swept against v2.87.0 in the same item (`wow-revendor-standards`) and
needed no edit; that sweep is recorded in the commit message, not here.
