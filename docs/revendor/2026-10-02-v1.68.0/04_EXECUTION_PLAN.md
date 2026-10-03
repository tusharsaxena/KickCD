# Execution plan (KickCD)

Two commits, both subject `TP-KC-01: `.

1. **Re-vendor** (Step 4): both payloads whole from the tag, the `CLAUDE.md` provenance line and
   `docs/testing.md`'s version-now line to v1.68.0, and this bundle's `01`-`04`. Gate: the suite, luacheck,
   sighted complexity. No case added, so no inventory or badge change.
2. **Adopt `tooltipPlace`**, test first:
   - `tests/test_util_anchor.lua`: `PlaceTooltipBeside` places right when the tooltip fits; flips left when
     the strip's right edge plus the tooltip's width passes the screen's right edge; resolves a hovered
     `?` mark to its strip; compares in screen pixels across a scaled strip; answers non-`true` and leaves
     the tooltip unanchored for a secret read and for a nil read. Red before the function exists.
   - `tests/test_castbar_frame.lua` and `tests/test_icongrid_handle.lua`: hovering the strip (its real
     `OnEnter`) owns `GameTooltip` by `UIParent` at `ANCHOR_NONE` and leaves it anchored `TOPLEFT` to the
     strip's `TOPRIGHT`; the assertion is the anchor the tooltip ends on, which is what the player sees.
     Red before the spec field exists (the tooltip is then owned by the strip at `ANCHOR_TOP`).
   - Then `core/Util.lua` and the two spec fields; the two handle headers' tooltip paragraphs; `docs/
     castbar.md`; `docs/smoke-tests.md` (CAST-10 corrected, CAST-15 and GRID-17 added, the owed table and
     the section ranges); `docs/test-cases.md` regenerated and the README `Tests` badge; `05_SUMMARY.md`.
   - Gate: the suite through `ka0s-bounded`, luacheck 0/0, sighted complexity (no function above CCN 15),
     every file under 1500 lines.

Fences: nothing under `libs/` or `tests/_kit/` is edited after the copy. No version bump, no push.
