# 01 — Delta: LibKa0s v1.32.0 → v1.33.0

Recorded before anything was copied. The payload was extracted from the tag, not from the
sibling's working tree:

```sh
git -C ../LibKa0s rev-parse v1.33.0 'v1.33.0^{commit}'
# 7d5e0615e69a426ffcd8903dd3289068f691daab   (tag object)
# 06ee3680a16b3bcac8e17a5313a3243fae1a5508   (commit)
git -C ../LibKa0s archive v1.33.0 LibKa0s testkit | tar -x -C <scratch>/
```

The tag is local to `../LibKa0s` (branch `feat/2026-09-12-v1.33.0`). `tests/test_vendor_sync.lua`
compares against the sibling at the tag `CLAUDE.md` names, so a local tag is enough.

## Claimed and actual version

```sh
grep -n '[Bb]undles' CLAUDE.md
# 52:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.32.0 (MIT). …
grep -hoE 'local MAJOR, MINOR *= *"[^"]+", *[0-9]+' libs/LibKa0s/Options.lua libs/LibKa0s/Slash.lua
# Options 16, Slash 8
```

The claim and the bytes agree.

## Per-file minor delta

| File | Constant | Old | Tag |
|---|---|---|---|
| `Options.lua` | `MINOR` | 16 | **17** |
| `Slash.lua` | `MINOR` | 8 | **9** |
| every other shipped file | its `MINOR` / `*_MINOR` | unchanged | unchanged |
| `testkit/framework.lua` | `Kit.VERSION` | 17 | **18** |

This matches the v1.33.0 block of `CHANGELOG.md` at the tag. There is no cross-major skew.

## What moved, and both diffs

```sh
git -C ../LibKa0s diff --name-status v1.32.0 v1.33.0 -- LibKa0s testkit
# M LibKa0s/Options.lua   M LibKa0s/Slash.lua
# M testkit/README.md     M testkit/framework.lua   M testkit/mock_base.lua
```

No additions or deletions. After the whole-folder `rsync -a --delete` and a re-checkout through the
CRLF filter, both `diff -r` forms, with and without `--strip-trailing-cr`, are empty for both
payloads. `tests/_kit/run-automated-tests.sh` is still recorded `100755`.

## Consumption map

`Options` is looked up at `settings/OptionsSetup.lua:44` and `Slash` at `settings/Slash.lua:55`.
Both majors that moved are consumed.

## Baseline (before the copy, at `ea50cba`)

```sh
lua tests/run.lua   # 930 passed, 0 failed, 0 skipped, 930 total
luacheck .          # 0 warnings / 0 errors in 95 files
lizard -l lua -x "./libs/*" -x "./tests/_kit/*" -C 15 -w .   # no warnings
```
