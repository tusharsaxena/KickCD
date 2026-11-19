Delta: LibKa0s v1.106.0 -> v1.107.0

Recorded with the re-vendor commit. Payload taken from the tag, never the sibling tree: `git -C ../LibKa0s archive v1.107.0 LibKa0s testkit tools` (tag commit 5e963659, a local tag, not yet on origin; expected for this run). Run under Ka0sAddonsCommonTasks `docs/2026-11-19-ADOPTION_FEEDBACK/`, item AF-RV-KC (the copy, provenance, icon-declaration and prune mechanics of `/dev-copilot:wow-revendor-libka0s` 2.9.0; the adoption interview is skipped, the run's bundle pre-decides the one adoption, AF-STRIP-KC).

## Step 0 pre-flight (this addon)
- Newest single-tag bundle `2026-11-16-v1.105.0` states base v1.93.0; the provenance line before its re-vendor commit named v1.93.0. ok, no correction owed.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` named v1.106.0 (CLAUDE.md:42) before the roll.
- Last payload commit, `git log -1 --format=%h -- libs/LibKa0s tests/_kit` = bb5a668; its CLAUDE.md names v1.106.0. They agree.
- Payload before the copy equalled the library at v1.106.0: `diff -rq` of a v1.106.0 extract against `libs/LibKa0s` printed only the pruned `media/icons` and `media/sounds/callout` (both declaration-driven), and `tests/_kit` matched (payload-matches).
- Library range: `git -C ../LibKa0s log --oneline v1.106.0..v1.107.0` is 6 commits; `git -C ../LibKa0s diff --stat v1.106.0 v1.107.0 -- LibKa0s testkit` is 2 files, +195 / -197.

## 3b/3c Per-file minors that moved (old = this addon, new = v1.107.0)
Derived from the tag's `LibKa0s.xml` with the spec's loop.
```
WidgetsDragHandle.lua     old: DRAG_MINOR = 14     new: DRAG_MINOR = 15
WidgetsDragHandleTip.lua  old: DRAGTIP_MINOR = 1   new: DRAGTIP_MINOR = 2
```
Every other file at its v1.106.0 minor. No cross-major skew.

## 3d Diffs
- After the copy, before the prune: `diff -r --strip-trailing-cr` and `diff -r` of the extract against `libs/LibKa0s` both empty; `diff -r` of the kit against `tests/_kit` empty.
- After the prune: only the undeclared icons and the sound packs are `Only in` the extract.

## 3e Consumption
`LibKa0s-Widgets-1.0` is looked up at 32 sites outside `libs/` and `tests/`; the two DragHandle builds are `modules/Castbar_Handle.lua` and `modules/IconGrid_Handle.lua`.

## 3f Kit revision
`Kit.VERSION = 57` on both sides; the kit did not move.

## 3g Contract delta
The two moved files are under a consumed major (Widgets). Read: the tag's `CHANGELOG.md` v1.107.0 block, *What a consumer owes at its re-vendor*, and the `spec` block of `libs/LibKa0s/WidgetsDragHandle.lua` (the `@param spec` table above `lib.DragHandle`).
- The settings mark is standard (built unless `settings = false`). Both KickCD strips already pass `settings`, so no width moves for that.
- The marks read [?][settings][close]: the "?" now anchors to the gear's LEFT, where through minor 14 the gear anchored to the "?". Two KickCD cases pinned the old order (`tests/test_icongrid_handle.lua`, `tests/test_castbar_frame.lua`, "carries the settings mark beside its help mark") and went red after the copy; re-pinned in this commit. Not a blocker that needs a decision, only a pin.
- `tooltipPlace` is retired (accepted, never called). KickCD passes none since AD-92-KC, so nothing to delete.
- The X needs `onClose`, which every host MUST pass (standard v2.115.0's HUD header rule). Neither strip passes one today: that is AF-STRIP-KC, the run's own item, not part of this commit.

Blockers: none.

## 3h Unrecorded tags
The audit's walk printed `v1.106.0`, vendored by the v1.106.0 sweep (`bb5a668`) with no bundle. Recorded in the span bundle `docs/revendor/2026-11-19-v1.106.0-v1.106.0/`.

## 3i Icon declaration
`LibKa0s icons: chevron-down, chevron-up, clear, close, confirm, copy, eye, help, info, move, reset, segment, settings, volume-high.` kept as written, directly under the provenance line. `settings` (owed by every strip consumer at v1.107.0) and `close` (the X, from AF-STRIP-KC) are already declared. No `LibKa0s sounds:` line, so sounds are none.

## 3j Whole-folder icon tests
None in this addon; the gate stayed green on the icon side.
