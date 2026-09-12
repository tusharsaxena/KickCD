# 01 — Delta: LibKa0s v1.29.0 → v1.30.0

Taken **from the tag**, never from the sibling working tree:
`git -C ../LibKa0s archive v1.30.0 LibKa0s testkit | tar -x -C <scratch>`. This addon's
`tests/test_vendor_sync.lua` resolves the tag its provenance line names and compares
both payloads against it file by file. The sibling's HEAD was the tag itself
(`git -C ../LibKa0s describe --tags --exact-match HEAD` → `v1.30.0`), with a clean tree.

## 3a — Claimed version, before this run

```
grep -n '[Bb]undles' KickCD/CLAUDE.md
```

> Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.29.0** (MIT).

## 3b — Actual version, before this run

```
grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua
```

Core 7, DebugLog 12, Env 1, Item 1, Media 3, Options 15, `COMPOSE_MINOR` 3, `SCROLL_MINOR` 3,
`WIDGETS_MINOR` 14, Perf 10, `PANEL_MINOR` 5, Pool 3, Slash 7, Widgets 9. That is the v1.29.0
version block exactly: the line and the bytes **agreed**.

## 3c — Per-file minor delta

Read from the tag's `LibKa0s/LibKa0s.xml`. The sorted minor list hashes the same on both sides
(`md5sum` of the grep above over `libs/LibKa0s/*.lua` and over the tag's `LibKa0s/*.lua`).

| File | v1.29.0 | v1.30.0 |
|---|---|---|
| every shipped file | unchanged | unchanged |

**No file under `LibKa0s/` moved.** The release is kit revision 16 only. No cross-major skew.

## 3d — Both diffs, both directions

```
diff -rq --strip-trailing-cr <tag>/LibKa0s KickCD/libs/LibKa0s   # empty
diff -rq                     <tag>/LibKa0s KickCD/libs/LibKa0s   # empty
diff -rq --strip-trailing-cr <tag>/testkit KickCD/tests/_kit     # 4 files
diff -rq                     <tag>/testkit KickCD/tests/_kit     # the same 4 files
```

The kit is content-dirty in `README.md`, `framework.lua`, `mock_base.lua` and `vendor_sync.lua`.
That is the release. **No `Only in` lines**, so nothing was deleted inside `libs/` or `tests/_kit/`.

## 3e — Consumption map

```
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/
```

Lookup sites per major: Core 16, Media 7, Options 6, Slash 5, Widgets 5, DebugLog 3, Perf 3,
Env 2, Pool 2. Nine majors are consumed, the same nine as before. `LibKa0s-Item-1.0` ships in the
payload with no lookup, as it did at v1.29.0. It did not move in this release.

## 3f — Kit revision, and the pairing rule

```
grep -n 'Kit.VERSION' <tag>/testkit/framework.lua KickCD/tests/_kit/framework.lua
```

`Kit.VERSION` goes **15 → 16**. Both payloads are copied whole in the same commit as the
provenance line. That is the pairing rule: from revision 11 on, `vendor_sync.lua` stopped
treating `media` as a file and stopped normalizing line endings across binaries, so the two
payloads always move together.

`git ls-files -s tests/_kit/run-automated-tests.sh` → `100755`, so revision 16's new runner-mode
case passes here.
