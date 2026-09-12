# 01 — Delta: LibKa0s v1.33.0 → v1.34.0

Recorded before anything was copied. The payload was extracted from the tag, not from the
sibling's working tree:

```sh
git -C ../LibKa0s rev-parse v1.34.0 'v1.34.0^{commit}'
# 916504409cb3508bd71af77c1b1a70a00bcd249c   (tag object)
# 33bae81ecf6de8e8d196ea87663882aceb140945   (commit)
git -C ../LibKa0s archive v1.34.0 LibKa0s testkit | tar -x -C <scratch>/
```

The tag is local to `../LibKa0s` (branch `feat/2026-09-13-v1.34.0`). `tests/test_vendor_sync.lua`
compares against the sibling at the tag `CLAUDE.md` names, so a local tag is enough.

## Claimed and actual version

```sh
grep -n '[Bb]undles' CLAUDE.md
# 52:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.33.0 (MIT). …
```

Options 17, OptionsCompose 4 and Slash 9 in `libs/LibKa0s/`. The claim and the bytes agree.

## Per-file minor delta

| File | Constant | Old | Tag |
|---|---|---|---|
| `Options.lua` | `MINOR` | 17 | **18** |
| `OptionsCompose.lua` | `_MINOR` | 4 | **5** |
| `Slash.lua` | `MINOR` | 9 | **10** |
| every other shipped file | its `MINOR` / `*_MINOR` | unchanged | unchanged |
| `testkit/framework.lua` | `Kit.VERSION` | 18 | **19** |

This matches the v1.34.0 block of `CHANGELOG.md` at the tag. There is no cross-major skew.

## What moved, and both diffs

```sh
git -C ../LibKa0s diff --name-status v1.33.0 v1.34.0 -- LibKa0s testkit
# M LibKa0s/Options.lua   M LibKa0s/OptionsCompose.lua   M LibKa0s/Slash.lua
# M testkit/README.md     M testkit/framework.lua        M testkit/mock_base.lua
```

No additions or deletions. After the whole-folder `rsync -rt --delete` from the extracted archive,
both `diff -r` forms, with and without `--strip-trailing-cr`, are empty for both payloads.
`tests/_kit/run-automated-tests.sh` is still recorded `100755`.

## Consumption map

`Options` is looked up at `settings/OptionsSetup.lua:44`; its descriptor supplies `resetProfile`
at `:129`, and `settings/General.lua:55` draws the Master controls through `H.MasterControls`, the
composer whose Reset-all tooltip moved. `Slash` is looked up at `settings/Slash.lua:55`. All three files
that moved are consumed.

### `parseForHost` is unaffected

`settings/Slash.lua:147`–`:154` wraps `SlashLib.ParseValue`: it returns the library's value when
there is one, and on a refusal appends `NS.Slash.GateHint(row)` for a `string` row that declares a
`valueGate`. It never splits or rewrites the text, so it hands minor 10 exactly what the CLI gave
it, and the only thing that changes is what `ParseValue` itself returns. Measured: the slash suites
pass unchanged.

## Kit revision 19 and this harness

Unreachable here, as kit 18 was. `tests/wow_mock.lua:545`–`:566` replaces the kit's AceDB, and its
`fire` still hands `OnProfileReset` the active key as a third argument, which AceDB-3.0 does not
(the comment at `:562`–`:564` says so). The production handler (`core/Database.lua:786`) reads that
argument only for an event that is neither a copy nor a reset, so nothing depends on it. Aligning
the fake is left for its own change: the brief for this run asks only that a moved total be fixed,
and none moved.

## Baseline (before the copy, at `cae55d2`)

```sh
lua tests/run.lua   # 931 passed, 0 failed, 0 skipped, 931 total
luacheck .          # 0 warnings / 0 errors in 95 files
lizard -l lua -x "./libs/*" -x "./tests/_kit/*" -C 15 -w .   # no warnings
```
