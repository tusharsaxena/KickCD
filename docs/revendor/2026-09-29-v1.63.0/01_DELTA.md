Delta: LibKa0s v1.62.0 -> v1.63.0

Copied from the local tag `v1.63.0` (`dd7a774`) with `git -C ../LibKa0s archive v1.63.0 LibKa0s testkit`,
never from a working tree. The tag is local only. This re-vendor is item SP-KC-02 of the 2026-09-29
smoke-rework and profile-verb run (`Ka0sAddonsCommonTasks/docs/2026-09-29-SMOKE_REWORK_AND_PROFILE_VERB/`,
spec S3).

## 3a/3b. Claimed and actual version

`grep -n '[Bb]undles' CLAUDE.md` read v1.62.0 (line 42). The last commit to touch either payload
(`git log -1 --format=%H -- libs/LibKa0s tests/_kit`, `4eb372e`) left the same line, and no
`CLAUDE.md` commit has rolled it since. The payload matched the library at v1.62.0
(`diff -rq` of both folders against `git archive v1.62.0`: no output). The vendored minors agreed
(`Slash` 16). No claim/fact disagreement. Base: v1.62.0.

Step 0 pre-flight: the newest existing bundle, `2026-09-26-v1.62.0/`, states v1.61.0 -> v1.62.0,
which the history agrees with. No base correction.

## 3c. Per-file minor delta (file list from the tag's `LibKa0s.xml`)

| File | v1.62.0 | v1.63.0 |
|---|---|---|
| `Slash.lua` (`MINOR`) | 16 | 17 |

Every other file is unchanged (`git -C ../LibKa0s diff --stat v1.62.0 v1.63.0 -- LibKa0s testkit`:
`LibKa0s/Slash.lua | 131 +++++-`, one file). No cross-major skew: every file moves with the
whole-folder copy.

## 3d. Both diffs, before the copy

`diff -rq --strip-trailing-cr <tag>/LibKa0s libs/LibKa0s`:

```
Files <tag>/LibKa0s/Slash.lua and libs/LibKa0s/Slash.lua differ
```

`diff -rq --strip-trailing-cr <tag>/testkit tests/_kit`: no output.

The byte diffs (`diff -rq`, no strip) list the same one file: no line-ending drift. No
`Only in libs/LibKa0s` or `Only in tests/_kit` line, so nothing is deleted. After the copy, all four
diffs are empty.

What moved (LibKa0s `CHANGELOG.md`, v1.63.0): Slash minor 17, the shared `profile` verb. A
descriptor field `profiles`, two instance members `CliProfile` and `ProfileSwitch`, one lib-level
function `ProfileNames`, and nine `PROFILE_*` strings. `profile` is not added to `lib.LIVE_VERBS`.

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)'` over the addon's own source finds the
Slash major looked up at `settings/Slash.lua:55`. The one major that moved is consumed.

## 3f. Kit revision

`Kit.VERSION` 31 -> 31 (`tests/_kit/framework.lua:20`). The kit did not move in this range. Both
payloads were still copied whole, which keeps the kit-revision pairing rule satisfied by
construction.

## 3g. Contract delta

No member, descriptor field or string that existed at minor 16 changed: the `Slash.lua` diff is
additive apart from the `MINOR` line. One parity gate moves (version 17 document,
`docs/api/Slash/version-17-docs.md`, *Compatibility*): the kit's by-name
`T.assertSurfaceParity(<stub>, "LibKa0s-Slash-1.0", ignore)` compares the degraded stub against
the live instance's public functions, which now include `CliProfile` and `ProfileSwitch`.

### Blockers

- **The Slash degradation stub fails surface parity on the copy alone.** `tests/test_surface_parity.lua`
  ("the Slash stub carries the whole live surface") went red after the copy with
  `CliProfile is missing (live: function); ProfileSwitch is missing (live: function)`. Fixed in the
  re-vendor commit: the stub in `settings/Slash.lua` (`SlashLib:New`) carries both on route (b)
  (the version 17 document's *The degradation stub*), each printing the library-absent line for
  `/kcd profile` and switching nothing. A new case in `tests/test_slash.lua` pins that behavior.
