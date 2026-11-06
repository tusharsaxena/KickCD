Delta: LibKa0s v1.85.0 -> v1.89.0

Part of Ka0sAddonsCommonTasks `docs/2026-11-06-REVENDOR_LIBKA0S_V1_89/` (item V89-KC). The tag is pushed, at commit `0bd4839`; the payload was taken with `git -C ../LibKa0s archive v1.89.0 LibKa0s testkit tools`, never the working tree.

## Base (3a, 3b)

- `grep -n '[Bb]undles' CLAUDE.md` -> `42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.85.0 (MIT).`
- `git log -1 --format=%H -- libs/LibKa0s tests/_kit` -> `cc61a05`, whose `CLAUDE.md` names v1.85.0. The two agree.
- The 3c loop's old column is the v1.85.0 minor set, so line and bytes agree.
- Step 0 pre-flight (the run's `inputs/step0-preflight.txt`): newest single-tag bundle `2026-11-01-v1.85.0` states base v1.84.0, and the provenance before `da85d57` was v1.84.0. `ok`, no correction owed.

`git -C ../LibKa0s log --oneline v1.85.0..v1.89.0`: 26 commits, the v1.86.0 icon browser, v1.87.0 cascading menus, v1.88.0 toast stack and v1.89.0 kit guard.

## Per-file minors (3c), moved files only

`for f in <v1.89.0 LibKa0s.xml files>: grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR ...' old against tag`

| File | old | new |
|---|---|---|
| Toast.lua | 3 | 4 |
| Widgets.lua | 22 | 23 |
| DebugLogDiagnostics.lua | 6 | 7 |
| IconBrowserSources.lua | (new) | 1 |
| IconBrowserWindow.lua | (new) | 1 |
| IconBrowser.lua | (new) | 1 |

No file is behind the old tag: no cross-major skew.

## Diffs before the copy (3d)

`diff -rq --strip-trailing-cr <extract>/LibKa0s libs/LibKa0s` (media/icons `Only in` lines aside, the undeclared icons): `DebugLogDiagnostics.lua`, `LibKa0s.xml`, `Toast.lua`, `Widgets.lua` differ; `IconBrowser.lua`, `IconBrowserSources.lua`, `IconBrowserWindow.lua` only in the tag. Kit: `README.md`, `framework.lua`, `mock_ace.lua` differ. Exactly the delta above; no `Only in libs/LibKa0s`.

## Kit (3f)

`grep -n 'Kit.VERSION'`: revision 50 -> 51. The two payloads move together.

## Consumption (3e)

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`: Bus, Charts, Compat, Core, DebugLog, Env, Glow, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Skin, Slash, Widgets. Unchanged. No `LibKa0s-Toast-1.0` and no `LibKa0s-IconBrowser-1.0` lookup.

## Contract delta (3g)

Moved and consumed: Widgets (22 -> 23) and DebugLog (Diagnostics 6 -> 7).

- Widgets 23 (`docs/api/Widgets/version-23.5.12.6.7.5-docs.md`, CHANGELOG v1.87.0): `submenu`, `radio`, `selected` and `opts.check` are new row options; "every flat menu draws what minor 22 drew". `grep -rn 'ContextMenu' --exclude-dir=libs --exclude-dir=_kit` finds no `W.ContextMenu` use site here (only `tests/mock_menu.lua`, the client `MenuUtil` mock). The library's own flat menus this addon draws (Sim picker, test strip) are unchanged per the CHANGELOG's step-5 re-look.
- DebugLogDiagnostics 7: the report's `LibKa0s running:` line names IconBrowser. No member moves.
- Toast 4's instance stub members (`SetStack`, `Visible`, `FrameFor`): not owed, no Toast lookup and no Toast stub (`grep -rn Toast --exclude-dir=libs --exclude-dir=_kit` is empty).
- `grep -rn '__Attach[A-Za-z]*'` outside the payloads: one comment, `settings/Panel.lua:181`, about `__AttachCompose`, which did not move.
- `docs/releasing.md` step 8 at the tag: v1.86.0 to v1.89.0 add no Skin facade member.

**Blockers: none.**

## Icons (3i, 3j)

- `grep -n 'LibKa0s icons:' CLAUDE.md` -> line 43, directly under the provenance line: `chevron-down, chevron-up, clear, close, confirm, copy, eye, help, info, move, reset, segment, settings, volume-high.` Kept, decided by the plan.
- The tag's *Library-drawn icons* table adds `search` and `close` for the icon browser only; this addon does not use it, so nothing new is owed. Hand lists have drifted before (`tests/test_mediasetup.lua:28`); the owner's in-client smoke is the backstop.
- 3j: `tests/test_options_panel.lua:639` opens `info.tga` (declared), `tests/test_mediasetup.lua:109` reads `Media.ICONS` names only. No whole-catalog file loop; no blocker.
- `__releaseChrome` appears only in a history comment (`settings/OptionsSetup.lua:501`); no dead mirror.

## Unrecorded tags (3h)

The 3h walk from horizon 2026-08-25: 64 vendored tags, `grep -vxF -f recorded.txt vendored.txt` printed nothing. No span bundle.
