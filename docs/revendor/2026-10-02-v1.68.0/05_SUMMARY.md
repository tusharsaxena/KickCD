# Summary (KickCD)

LibKa0s v1.67.0 -> v1.68.0 from the local tag (`cc9f5eb`): WidgetsDragHandle 3 -> 4; every other file
unchanged. `tests/_kit` stays at kit revision 35 (no change between the tags). The base is the tag the
`CLAUDE.md` provenance line named (v1.67.0). Both content diffs are empty after the copy, and nothing was
deleted.

No span bundle: no vendored tag went unrecorded. No base correction.

Blockers: none (3g: additive; without a hook a hover makes minor 3's calls).

Delivered on the copy (class A): the tooltip lines evaluated once per hover; nothing visible moves.

Re-vendor commit `18dc978`: both payloads, the `CLAUDE.md` provenance line and `docs/testing.md`'s
version-now line to v1.68.0, this bundle's `01`-`04`.

Adopted: **`tooltipPlace`**, on both strips, in the adoption commit that adds this file (`TP-KC-01: ...
beside the strip`). `NS.Util.PlaceTooltipBeside` (`core/Util.lua`) anchors the tooltip `TOPLEFT` to the
strip's `TOPRIGHT`, or `TOPRIGHT` to its `TOPLEFT` when the strip's right edge plus the tooltip's width
would pass the screen's right edge, compared in screen pixels; it resolves a hovered `?` mark to its strip
and answers nil (the widget's cursor fallback, nothing anchored) on any nil or secret read
(`NS.Compat.IsSecret`). `modules/Castbar_Handle.lua` and `modules/IconGrid_Handle.lua` pass it as
`tooltipPlace`. Before, both strips' tooltips were owned by the hovered frame at `ANCHOR_TOP`; why
beside-the-strip is the better match for the owner's request is in `03_DECISIONS.md`.

Declined: nothing. No GitHub issue filed. Unreached: nothing.

Gates:

- before the copy: 1294 passed, 0 failed, 1 skipped (1295); luacheck 0 / 0 in 127 files
- after the copy: identical; vendor sync (`libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon
  bundles`, `tests/_kit is the test kit that shipped with that release`) green; sighted complexity `pass`,
  max CCN 15, 0 warnings, 3557 functions
- after the adoption: 1302 passed, 0 failed, 1 skipped (1303), eight cases added (six in
  `test_util_anchor.lua`, one each in `test_castbar_frame.lua` and `test_icongrid_handle.lua`), all eight
  red before the code; luacheck 0 / 0 in 127 files; sighted complexity `pass`, max CCN 15, 0 warnings, 3580
  functions (`Util.PlaceTooltipBeside` CCN 10); every file under 1500 lines. `docs/test-cases.md`
  regenerated and the README `Tests` badge moved 1294 -> 1302 in the same commit.

All suites ran through `~/.claude/wow-addon/bin/ka0s-bounded`.

Smoke (owner-run, never marked here): new CAST-15 and GRID-17 (beside the strip, flipping left at the
screen's right edge; GRID-17 also at master scale 1.5), CAST-10's expectation corrected to the beside
position, both added to the re-vendor routing and the owed table.
