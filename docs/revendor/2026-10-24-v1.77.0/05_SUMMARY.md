# Summary (KickCD)

LibKa0s v1.76.0 -> v1.77.0 from the local annotated tag (`78240f7`, via `git archive`). The base
comes from the CLAUDE.md provenance line and matches the payload bytes. Payload: Core 12,
DebugLog 21, PerfPanel 9, SimPanel 6, Widgets 15, WidgetsDragHandle 5, WidgetsAutocomplete 3,
Options 30, OptionsIds 3, OptionsCombat 2, OptionsCompose 8 and the new OptionsKeybinds 3; every
other file unchanged. Kit 41 -> 42.

In the same commit as both payloads:

- the CLAUDE.md provenance line rolls v1.76.0 -> v1.77.0; `LibKa0s icons: clear, close, confirm,
  copy, help, info, segment.` stays directly under it;
- the tag's `tools/prune-icons.lua` keeps 8 files (the seven `.tga` and `LICENSE-open-iconic.txt`)
  and removes 5,832, the same set as before;
- the 3g blocker fix: `settings/OptionsSetup.lua`'s Options stub gains `KeybindingsTab`,
  `KeybindRows` (no-ops), `StrataTooltip` (answers `""`) and `KEYBINDS_UNCHANGED` (`""`), and
  `tests/test_options_panel.lua` counts twelve Options files.

- **Contract blockers:** the four stub members and the file count, both fixed here.
- **Delivered free (class A):** toplevel console / perf / sim panels that re-raise a shown
  StaticPopup, clamped dropdown and autocomplete popups, and the id suggestion list closed at combat
  start.
- **Decided adopt (later item of this run):** DragHandle `level` / `ApplyLevel` /
  `ignoreParentAlpha` (KC-ZS, held for the owner).
- **Deferred (run 2026-10-24):** the Keybindings tab, `O.StrataTooltip`, the kit's binding mock
  and Bindings.xml check, and `mock_layers.lua` (to KC-ZS). No issue filed.
- No span bundle (nothing unrecorded); no base correction; README credits unchanged; no dead stub
  mirror; no refresh file.

Gate after the copy, prune and blocker fix:

- tests (`ka0s-bounded lua tests/run.lua`): 1480 passed, 0 failed, 1 skipped, 1481 total;
  `test_vendor_sync` resolves v1.77.0 from `../LibKa0s` and passes the icon gate. Before the fix:
  1478 passed, 2 failed (the two blockers above).
- `docs/test-cases.md`: `lua tests/run.lua --list` output identical to the committed file.
- luacheck (`ka0s-bounded luacheck .`): 0 warnings / 0 errors in 146 files.
- 1500-line cap: largest authored `.lua` is `modules/IconGrid.lua` at 1010 lines.

The standard reference was swept against v2.88.0 in the same item (`wow-revendor-standards`) and
needed no edit; that sweep is recorded in the commit message, not here.

## Re-vendor after the tag moved (M3)

LK-95 moved the local annotated tag v1.77.0 to carry the settings-layout surfaces. Old target:
commit `78240f7` (LK-90). New target: tag object `b2b8ee2`, commit
`afae2f75cb7ff61c57156d9a3d8a6b2b9f4c5e10` (`afae2f7`, LK-95). Both payloads were copied whole again
from `git -C ../LibKa0s archive v1.77.0 LibKa0s testkit`.

- **Per-file minors that moved:** OptionsCompose 8 -> 11 (minor 9: MasterControls `notes`,
  `resetPositionTooltip`, `lockIsPreview`, the Master opacity label and the packed Minimap button;
  minor 10: the group composers' `tooltips`; minor 11: `O.ResetAllTooltip`). Every other payload file
  is byte-identical; the kit is unchanged (revision 42).
- The CLAUDE.md provenance line stays v1.77.0 (it records no sha or kit revision); the
  `LibKa0s icons:` declaration is unchanged, and the tag's `tools/prune-icons.lua` again keeps 8 files
  and removes 5,832.
- **Contract blocker:** kit surface parity failed on `ResetAllTooltip` (live: function). Fixed in
  `settings/OptionsSetup.lua`: the Options stub answers `""`, inert, like `StrataTooltip`.
- No adoption here (KC-LY adopts). The standard reference is unversioned and needed no edit.

Gate: tests 1495 passed, 0 failed, 1 skipped, 1496 total (1494 / 1 failed before the stub fix);
`docs/test-cases.md` matches `--list`; luacheck 0 warnings / 0 errors in 147 files; largest authored
`.lua` is `modules/IconGrid.lua` at 1013 lines.

## Re-vendor after the tag moved again (one key button)

LK-96 moved the local annotated tag v1.77.0 again, for the owner's one-key-button follow-up to 015.
Old target: tag object `b2b8ee2`, commit `afae2f7` (LK-95). New target: tag object `e9b126d`, commit
`2f2b2e22b4c9219cd8a4101d7e894681c7aea16e` (`2f2b2e2`, LK-96). Both payloads were copied whole again
from `git -C ../LibKa0s archive v1.77.0 LibKa0s testkit`.

- **Per-file minors that moved:** OptionsKeybinds 3 -> 4 (one key button and Clear per row: the
  button binds and right-click clears slot 1, reads "<first key> +N" when the action holds more, and
  its tooltip names every key; `KEY1` / `KEY2` gone, `KEY`, `KEY_MORE`, `KEYS_ALL`, `KEYS_OTHER` new).
  Every other library file is byte-identical. The kit stays revision 42; `bindings_xml.lua` and its
  README row changed (`Kit.keybindThroughTab` slot 2 on a one-button row writes through
  `lib.__keybindSet`).
- No new public `O.*` member, so kit surface parity passes and the Options degradation stub in
  `settings/OptionsSetup.lua` is unchanged. KickCD does not draw a Keybindings tab, so nothing to adopt.
- The CLAUDE.md provenance line stays v1.77.0; the `LibKa0s icons:` declaration is unchanged, and the
  tag's `tools/prune-icons.lua` again keeps 8 files and removes 5,832.

Gate: tests 1497 passed, 0 failed, 1 skipped, 1498 total; the README badge (1497/1497) and
`docs/test-cases.md` match `--list`; luacheck 0 warnings / 0 errors in 148 files; largest authored
`.lua` is `tests/test_schema.lua` at 1016 lines; `diff -r --strip-trailing-cr ../LibKa0s/LibKa0s
libs/LibKa0s` (icons excluded) is empty.
