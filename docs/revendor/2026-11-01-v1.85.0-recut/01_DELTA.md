Delta: LibKa0s v1.84.0 -> v1.85.0

This is a re-cut, not a new release. The local tag v1.85.0 moved from `9776130` to `2ad1a50` before it was pushed, for the owner's rulings of 2026-11-01 and the review of them. Line 1 keeps the tag-level delta, so the pre-flight base check reads the v1.85.0 re-vendor correctly. The real delta of this folder is commit to commit, `9776130..2ad1a50`.

Run by item `FS-KC-GATE` of Ka0sAddonsCommonTasks `docs/2026-11-01-FULL_SKINNING/`. `2026-11-01-v1.85.0/` is frozen, so this record sits in its own suffixed folder.

## What moved

Ten library files and three kit files changed, and the kit gained four: `Media.lua`, `OptionsCompose.lua`, `Skin.lua`, `SkinDefs.lua`, `SkinDefsOthers.lua`, `SkinEUI.lua`, `SkinPaint.lua`, `SkinPaintControls.lua`, `SkinPaintExtras.lua`, `Widgets.lua`; kit revision 49 -> 50, adding `skin_values.lua`, `skin_switch.lua`, `test_skin_values.lua` and `test_skin_switch.lua`. Keys at the tag are `docs/releasing.md`'s and the CHANGELOG's.

## Blockers

- **Facade.** `BarBorder` answers its stored three and `HoverArt` is a no-op, both in `core/SkinSetup.lua`.
- **Inventory.** Both kit suites are declared in `tests/run.lua` by the pair.
- **Pin.** `tests/test_skin_flip.lua` pinned one font object per string. It now pins one object per look, shared.
