# 01 — Delta: LibKa0s v1.30.0 → v1.31.0

Taken **from the tag**, never from the sibling working tree:
`git -C ../LibKa0s archive v1.31.0 LibKa0s testkit | tar -x -C <scratch>`. This addon's
`tests/test_vendor_sync.lua` resolves the tag its provenance line names and compares both payloads
against it file by file. The sibling's HEAD was the tag itself
(`git -C ../LibKa0s describe --tags --exact-match HEAD` → `v1.31.0`, commit `30db4ed`), with a
clean tree.

This folder is dated `2026-09-12-v1.31.0` because `docs/revendor/2026-09-12/` already holds the
v1.30.0 re-vendor from the same day, and that bundle is frozen.

## 3a — Claimed version, before this run

```
grep -n '[Bb]undles' KickCD/CLAUDE.md
```

> Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.30.0** (MIT).

## 3b — Actual version, before this run

```
grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua
```

Core 7, DebugLog 12, Env 1, Item 1, Media 3, Options 15, `COMPOSE_MINOR` 3, `SCROLL_MINOR` 3,
`WIDGETS_MINOR` 14, Perf 10, `PANEL_MINOR` 5, Pool 3, Slash 7, Widgets 9. That is the v1.30.0
version block exactly: the line and the bytes **agreed**.

## 3c — Per-file minor delta

The same grep over the tag's `LibKa0s/*.lua`. The file list is the tag's `LibKa0s/LibKa0s.xml`.

| File | Constant | v1.30.0 | v1.31.0 |
|---|---|---|---|
| `OptionsCompose.lua` | `COMPOSE_MINOR` | 3 | **4** |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 14 | **15** |
| every other shipped file | — | unchanged | unchanged |

This addon was behind on no file: **no cross-major skew**.

## 3d — Both diffs, both directions

```
diff -rq --strip-trailing-cr <tag>/LibKa0s KickCD/libs/LibKa0s   # OptionsCompose.lua, OptionsWidgets.lua
diff -rq                     <tag>/LibKa0s KickCD/libs/LibKa0s   # the same two
diff -rq --strip-trailing-cr <tag>/testkit KickCD/tests/_kit     # README.md, framework.lua, mock_base.lua
diff -rq                     <tag>/testkit KickCD/tests/_kit     # the same three
```

Content-dirty in exactly the files the release moved. That is the release, not a fork. **No
`Only in` lines**, so nothing was deleted inside `libs/` or `tests/_kit/`.

After the copy and the CRLF repair (`git add <p> && rm <p> && git checkout -- <p>`, CR count equal
to LF count in all five files), both content diffs are **empty**.

## 3e — Consumption map

```
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/
```

Lookup sites per major: Core 16, Media 7, Options 6, Widgets 6, Slash 5, DebugLog 3, Perf 3,
Env 2, Pool 2. Nine majors are consumed, the same nine as before. `LibKa0s-Item-1.0` ships in the
payload with no lookup, as it did at v1.30.0, and it did not move in this release.

## 3f — Kit revision, and the pairing rule

```
grep -n 'Kit.VERSION' <tag>/testkit/framework.lua KickCD/tests/_kit/framework.lua
```

`Kit.VERSION` goes **16 → 17**. Both payloads were copied whole in the same commit as the
provenance line (`ca6e0d5`). That is the pairing rule: from revision 11 on, `vendor_sync.lua`
stopped treating `media` as a file and stopped normalizing line endings across binaries, so the
two payloads always move together.

## Addendum, 2026-09-12: the v1.31.0 tag was re-cut before release

This bundle was written against the first cut of the `v1.31.0` tag (commit `30db4ed`). Before
anything was pushed, a review of that release found defects in the kit-17 fakes, and LibKa0s re-cut
the tag on the fixed tree: **`v1.31.0` now points at `e7e1962`**
(`git -C ../LibKa0s rev-parse --short 'v1.31.0^{commit}'` → `e7e1962`). The re-vendor commit that
follows this bundle, **`4a27fdb`** ("Re-vendor the reviewed LibKa0s v1.31.0 (tag moved to
e7e1962)"), copied both payloads whole from the re-cut tag, and the vendor-sync cases pass against
it.

What the re-cut changed, relative to the tables above:

| File | First cut | Re-cut |
|---|---|---|
| `Perf.lua` | minor 10 (unchanged) | **minor 11**: `P.Save` traces the ring trim once past its cap (debug-logging-§8) |
| `OptionsWidgets.lua` | minor 15 | minor 15 (review fixes land inside the unreleased minor: `pairWith` keyed by `row.path or row.field`; a bound row's `disabledIf` reads through `row.get`) |
| `OptionsCompose.lua` | minor 4 | minor 4 (unchanged surface) |
| kit (`tests/_kit/`) | revision 17 | revision 17 (review fixes: repeating-timer delay no longer drifts; the nameless `NewAddon` path is exactly one table argument; the timer handle field is AceTimer's own `cancelled`, and `NewTimer` handles answer `IsCancelled()`; dispatch survives a handler error; `ADDON_LOADED` after login enables a load-on-demand addon; the AceEvent library object carries the message API) |

`4a27fdb` touched exactly those files: `libs/LibKa0s/OptionsCompose.lua`,
`libs/LibKa0s/OptionsWidgets.lua`, `libs/LibKa0s/Perf.lua`, `tests/_kit/README.md` and
`tests/_kit/mock_base.lua`.

So three files in `LibKa0s/` move in this release, not two. 3c's "every other shipped file —
unchanged" no longer holds for `Perf.lua`, which is now at minor 11 in `libs/LibKa0s/Perf.lua`.
**The Perf ring trim is now traced upstream**: Perf minor 11's `P.Save` logs the trim once when the
ring passes its cap (debug-logging-§8), so any "the ring trim is not traced" finding against this
release is resolved in the library. This addon consumes `LibKa0s-Perf-1.0` (three lookup sites, 3e)
and needed no change of its own to pick the trace up.

**Gate on the re-cut payload, at `4a27fdb`:** `lua tests/run.lua` 901 passed, 0 failed, the
vendor-sync cases green against `e7e1962`; `luacheck .` 0 / 0 in 95 files; `lizard -C 15` no
function over 15.
