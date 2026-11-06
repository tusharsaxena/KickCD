# Candidates

Range `v1.85.0..v1.89.0`, from the four CHANGELOG blocks (v1.86.0 to v1.89.0) and the moved majors' API documents. Adoption is decided by Ka0sAddonsCommonTasks `docs/2026-11-06-REVENDOR_LIBKA0S_V1_89/00_PLAN.md` (*Decisions*), not by an interview.

## Class A, delivered on the copy

- **Kit revision 51** (CHANGELOG v1.89.0, `docs/api/testkit/version-51-docs.md`): `mock_ace.lua`'s CallbackHandler unregister clears an entry only where one exists, so an `Unregister*` during a dispatch no longer risks `invalid key to 'next'`. No member moves.
- **DebugLogDiagnostics 7** (CHANGELOG v1.86.0): the `/kcd diagnostics` report's `LibKa0s running:` line names IconBrowser. No member moves.
- **Widgets 23, flat menus** (CHANGELOG v1.87.0): "every flat menu draws what minor 22 drew"; the library-drawn flat menus this addon shows (the Sim scenario picker, the test strip's right-click menu) are unchanged per that block's step-5 re-look.

## Class B, host change

- **Widgets 23 `submenu` / `radio` / `selected` / `opts.check`** (`docs/api/Widgets/version-23.5.12.6.7.5-docs.md`): not applicable. `grep -rn 'ContextMenu' --include='*.lua' --exclude-dir=libs --exclude-dir=_kit` finds no `W.ContextMenu` use site (only the client `MenuUtil` mock, `tests/mock_menu.lua`). Additive if a menu were ever added.
- **Toast 4 stack, `SetStack` / `Visible` / `FrameFor`** (`docs/api/Toast/version-4-docs.md`): not applicable. KickCD does not look up `LibKa0s-Toast-1.0` and carries no Toast stub.

## Class C, whole-module

- **`LibKa0s-IconBrowser-1.0`** (new at v1.86.0, `docs/api/IconBrowser/version-1.1.1-docs.md`): KickCD has no icon chooser; its icons are the tracked spells' own textures, and no setting lets the player pick from the catalog (`grep -rni 'chooser\|IconBrowser\|icon picker'` outside the payloads finds nothing). Settled by the plan: no chooser, no adoption, no issue. Blast radius if ever adopted: additive.
