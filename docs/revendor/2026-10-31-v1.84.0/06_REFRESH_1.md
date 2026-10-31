# Refresh 1 of v1.84.0 (KickCD)

The local-only tag v1.84.0 moved again before its release was pushed, so this is a refresh and not a
new re-vendor. `git -C ../LibKa0s ls-remote --tags origin v1.84.0` prints nothing. The move before
this one (`e917ccd` -> `7a8bc0f`) is recorded in `docs/revendor/2026-11-01-v1.84.0-recut/`.

- Old: `7a8bc0f`
- New: `b5229b876e803768322fb4d8c66be69f01c8e4a1`, from `git -C ../LibKa0s rev-parse 'v1.84.0^{commit}'`

The library deletes `lib.__PatchLSM30Border` with no stub, by the owner's ruling of 2026-11-01.

| File | Old | New |
|---|---|---|
| `Options.lua` | `MINOR` 36 | `MINOR` 37 |
| `OptionsDrawer.lua` | `DRAWER_MINOR` 3 | `DRAWER_MINOR` 4 |
| `OptionsMedia.lua` | `MEDIA_MINOR` 2 | `MEDIA_MINOR` 3 |

Every other file's minor is unchanged, and the kit stays at revision 47.

## Authored code

Nothing changed. `grep -rn PatchLSM30Border . --exclude-dir=.git --exclude-dir=libs --exclude-dir=_kit`
finds only frozen records under `docs/`. KickCD's call and its test went in `1a8b0f2`. No stub, guard
or pinned minor needed moving, and no new one was added.

## Gate

- Copy: both content diffs were empty against the whole copy, before the prune.
- Prune: `LibKa0s icons:` line kept, 7 declared, kept 8 files, removed 5,832.
- `ka0s-bounded luacheck .`: 0 warnings / 0 errors in 154 files.
- `ka0s-bounded lua tests/run.lua`: 1582 passed, 0 failed, 1 skipped, 1583 total.
