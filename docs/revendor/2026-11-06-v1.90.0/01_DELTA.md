Delta: LibKa0s v1.89.0 -> v1.90.0

Part of Ka0sAddonsCommonTasks `docs/2026-11-06-REVENDOR_LIBKA0S_V1_89/` (item SF1-RV-KC, from `SF1_SMOKE_FEEDBACK.md`). The tag is local and not pushed, at commit `4485b8f`, so `git ls-remote --tags origin v1.90.0` prints nothing. This is a new tag, not a refresh. The payload was taken with `git -C ../LibKa0s archive v1.90.0 LibKa0s testkit tools`, never the working tree.

## Base (3a, 3b)

- `grep -n '[Bb]undles' CLAUDE.md` -> `42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.89.0 (MIT).`
- `git log -1 --format=%H -- libs/LibKa0s tests/_kit` -> `4bd1834`, whose `CLAUDE.md` names v1.89.0. The two agree. `git log "4bd1834..HEAD" -- CLAUDE.md` is empty.
- `diff -rq <v1.89.0 extract>/LibKa0s libs/LibKa0s` prints only the undeclared icons' `Only in` lines, and the kit matches: the payload is v1.89.0's.
- The 3b minors (`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR ...' libs/LibKa0s/*.lua`) are the v1.89.0 set, so line and bytes agree.
- Step 0 for this addon: newest single-tag bundle `2026-11-06-v1.89.0` states base v1.85.0, and the provenance before `4bd1834` was v1.85.0. `ok`, no correction owed.

`git -C ../LibKa0s log --oneline v1.89.0..v1.90.0`: 7 commits, the `SF1-L1` pixel edges, the `SF1-L2` `keepScope` opt-out and the `SF1-L3` release (with the v2.102.2 harvest merge `e809ca3` before them).

## Per-file minors (3c), moved files only

`for f in <v1.90.0 LibKa0s.xml files>: grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR ...' old against tag`

| File | old | new |
|---|---|---|
| Core.lua | 15 | 16 |
| Skin.lua | 16 | 17 |
| SkinPaint.lua | 18 | 19 |
| SkinPaintExtras.lua | 17 | 18 |
| Widgets.lua | 23 | 24 |
| WidgetsAutocomplete.lua | 7 | 8 |
| OptionsAppearance.lua | 6 | 7 |

Every other file is at its v1.89.0 minor. No file is behind the old tag, so there is no cross-major skew. No file is new.

## Diffs before the copy (3d)

`diff -r [--strip-trailing-cr] <extract>/LibKa0s libs/LibKa0s` (media/icons `Only in` lines aside, the undeclared icons): exactly the seven files above differ, in content and bytes alike. No `Only in libs/LibKa0s`. Kit: both diffs are empty (revision 51 on both sides).

## Kit (3f)

`grep -n 'Kit.VERSION'`: revision 51 -> 51. The two payloads still move together.

## Consumption (3e)

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`: Bus, Compat, Core, DebugLog, Env, Glow, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Sim, Skin, Slash, Widgets. Unchanged from v1.89.0.

## Contract delta (3g)

Moved and consumed: Core (15 -> 16), Skin (Skin 17, SkinPaint 19, SkinPaintExtras 18), Widgets (Widgets 24, WidgetsAutocomplete 8) and Options (OptionsAppearance 7).

- Core 16 (`docs/api/Core/version-16-docs.md`, CHANGELOG v1.90.0 *One physical pixel*): `__PixelSize`, `__WatchPixels`, `__OnPixelScale` and `__PixelBackdrop` are internal (`__`) and no member manifest moves. They degrade to the old size where the client has no `PixelUtil` or `hooksecurefunc`.
- Widgets 24 / WidgetsAutocomplete 8: `W.Dropdown`'s box, `W.SearchBox`, the shared menu and the autocomplete list take the pixel backdrop. "No member or option moves." `grep -rn 'W\.Dropdown\|W\.SearchBox\|Autocomplete' --include='*.lua' --exclude-dir=libs --exclude-dir=_kit` finds no use site in this addon's own code.
- Skin 17: `RegisterOwner(owner, { keepScope = true })` is opt-in. KickCD's `core/SkinSetup.lua:641` registration passes no `keepScope`, so it behaves as before. OptionsAppearance 7: `lib.__copySkinTo` treats only a `keepScope` target differently.
- `grep -rn '__Attach[A-Za-z]*'` outside the payloads: one comment, `settings/Panel.lua:181`, about `__AttachCompose`, which did not move.
- `docs/releasing.md` step 8 at the tag: "v1.90.0 adds no Skin facade, major or instance member", so no stub owes a new member.

**Blockers: none.**

## Icons (3i, 3j)

- `grep -n 'LibKa0s icons:' CLAUDE.md` -> line 43, directly under the provenance line: `chevron-down, chevron-up, clear, close, confirm, copy, eye, help, info, move, reset, segment, settings, volume-high.` Kept, decided by the plan. v1.90.0 adds no library-drawn icon. Hand lists have drifted before (`tests/test_mediasetup.lua:28`); the owner's in-client smoke is the backstop.
- 3j: `tests/test_options_panel.lua:639` opens `info.tga` (declared), and `tests/test_mediasetup.lua:109` reads `Media.ICONS` names only. No whole-catalog file loop, so no blocker.
- `__releaseChrome` appears only in a history comment (`settings/OptionsSetup.lua:501`), so there is no dead mirror.

## Unrecorded tags (3h)

The 3h walk from horizon 2026-08-25: `grep -vxF -f recorded.txt vendored.txt` printed nothing. No span bundle.
