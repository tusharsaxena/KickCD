Delta: LibKa0s v1.83.0 -> v1.84.0

This is a re-cut, not a new release. The local tag v1.84.0 moved from `e917ccd` to `7a8bc0f` before it
was pushed (`git ls-remote --tags origin v1.84.0` prints nothing), for the owner's ruling of 2026-11-01
that `Ka0sMedia_*` is the only media picker. Line 1 keeps the tag-level delta, so the pre-flight base
check and the audit's re-vendor check still read the v1.84.0 re-vendor correctly. The real delta of this
folder is commit to commit, `e917ccd..7a8bc0f`.

Run by item `M3-RV` of the 2026-10-31 findings remediation. `2026-10-31-v1.84.0/` is frozen, so this
record sits in its own suffixed folder rather than in a `06_REFRESH_1.md` inside that bundle.

Base: `grep -n '[Bb]undles' CLAUDE.md` gives v1.84.0, and the payload matched the tag's first cut.

## Per-file minors

Command: the skill's 3c loop over `LibKa0s/LibKa0s.xml`. Only these moved:

| File | Old | New |
|---|---|---|
| `Options.lua` | 35 | 36 |
| `OptionsWidgets.lua` | 40 | 41 |
| `OptionsCompose.lua` | 15 | 16 |
| `OptionsScroll.lua` | 9 | 10 (comments only) |
| `OptionsMedia.lua` | 1 | 2 |
| `SkinAce.lua` | 5 | 6 (comments only) |

`git -C ../LibKa0s diff --stat e917ccd v1.84.0 -- LibKa0s testkit tools`: those six files, 67 insertions
and 109 deletions. No kit file moved: `Kit.VERSION` stays 47.

## Blockers

`CHANGELOG.md`, v1.84.0, "One media picker": a test expecting `__PatchLSM30Border` to wrap moves.

- `tests/test_options_panel.lua`'s "the live wiring patches LSM30_Border through the library" went red
  (1581 passed, 1 failed). The member is a no-op that answers false at Options minor 36. The test is
  retired in the re-vendor commit.
- `settings/OptionsSetup.lua`'s call is deleted with it. The no-op would be safe to keep, but its comment
  described a wrapper that no longer exists.

No host-supplied member's contract moved. `Helpers.LSMValues` stays the deferred reader, and the host's
`__Attach*` sites are unchanged.
