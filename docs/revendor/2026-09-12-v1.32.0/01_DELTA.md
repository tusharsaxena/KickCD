# 01 — Delta: LibKa0s v1.31.0 → v1.32.0

Taken **from the tag**, never from the sibling working tree:
`git -C ../LibKa0s archive v1.32.0 LibKa0s testkit | tar -x -C <scratch>`. The tag resolves to
`e18dd12` (`git -C ../LibKa0s rev-parse --short 'v1.32.0^{commit}'`), a local tag that has not
been pushed. This addon's `tests/test_vendor_sync.lua` resolves the tag its provenance line names
and compares both payloads against it file by file.

This folder is dated `2026-09-12-v1.32.0` because `docs/revendor/2026-09-12/` and
`docs/revendor/2026-09-12-v1.31.0/` already hold the same day's earlier re-vendors, and both are
frozen.

## 3a — Claimed version, before this run

> Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.31.0** (MIT).

## 3b — Actual version, before this run

```
grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua
```

Core 7, DebugLog 12, Env 1, Item 1, Media 3, Options 15, `COMPOSE_MINOR` 4, `SCROLL_MINOR` 3,
`WIDGETS_MINOR` 15, Perf 11, `PANEL_MINOR` 5, Pool 3, Slash 7, Widgets 9. That is the v1.31.0
version block exactly: the line and the bytes **agreed**.

## 3c — Per-file minor delta

| File | Constant | v1.31.0 | v1.32.0 |
|---|---|---|---|
| `Options.lua` | `MINOR` | 15 | **16** |
| `Slash.lua` | `MINOR` | 7 | **8** |
| every other shipped file | — | unchanged | unchanged |

This addon was behind on no file: **no cross-major skew**.

## 3d — Both diffs, both directions

```
diff -rq --strip-trailing-cr <tag>/LibKa0s KickCD/libs/LibKa0s   # Options.lua, Slash.lua
diff -rq                     <tag>/LibKa0s KickCD/libs/LibKa0s   # the same two
diff -rq --strip-trailing-cr <tag>/testkit KickCD/tests/_kit     # empty
diff -rq                     <tag>/testkit KickCD/tests/_kit     # empty
```

Content-dirty in exactly the two files the release moved. **No `Only in` lines.** Both payloads were
copied whole; after the copy, both byte diffs are empty. The tag's files are CRLF already, with CR
equal to LF in both moved files (1114 / 1114 and 652 / 652), so no repair was needed.
`tests/_kit/run-automated-tests.sh` stays at mode 100755.

## 3e — Consumption map

```
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/
```

Lookup sites per major: Core 16, Media 7, Options 6, Widgets 6, Slash 5, DebugLog 3, Perf 3,
Env 2, Pool 2. The same nine majors as at v1.31.0. Both moved majors, Options and Slash, are
consumed. `LibKa0s-Item-1.0` ships with no lookup.

## 3f — Kit revision, and the pairing rule

`Kit.VERSION` is **17** in both the tag and `tests/_kit/framework.lua`: the kit did not move. Both
payloads were still copied whole in the same commit as the provenance line (`2bf885c`).
