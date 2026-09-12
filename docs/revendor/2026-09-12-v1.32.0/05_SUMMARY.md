# 05 — Summary: LibKa0s v1.31.0 → v1.32.0

## The move

| | |
|---|---|
| From | v1.31.0 (`e7e1962`) |
| To | **v1.32.0** (`e18dd12`) |
| Files under `LibKa0s/` that moved | `Options.lua` (`MINOR` 15 → 16), `Slash.lua` (`MINOR` 7 → 8) |
| Kit revision | 17, unchanged (`tests/_kit/` byte-identical to the tag) |
| Files removed upstream | none |
| Cross-major skew found | none |

## What reached this addon for free

Nothing observable. With no bracket supplied, both walks run the previous minors' calls in the same
order: 913 passed before the copy and after it (`2bf885c`).

## What was adopted

**The bulk bracket (`debug-logging-§10`), in `7ef08c9`.** Tests first: eleven new cases, all red on
the pre-adoption code, plus the Copy styling summary test moved to the changed-row count.

| Act | Lines logged now |
|---|---|
| A page's **Defaults** (castbar, icons, label, general: 110, 78, 32 and 9 rows walked) | `[Set] reset <page>: N rows`, N = rows whose value changed; `0 rows` at defaults |
| **Reset all settings** / `/kcd resetall`, live and with LibKa0s absent | `[Set] reset profile '<name>' to defaults (N rows)` alone, from the profile handler |
| AceDB profile copy | `[Set] copied profile '<source>' → '<active>'` |
| Profile switch | `[Profile] switched to '<name>'`, unchanged |
| Copy styling from Target | `[Set] copy target→focus: N rows`, N = rows changed |
| Nested acts | one line, the outermost act's, with every level's rows; none if a level reset the profile |
| `Sl:CliResetAll` (no KickCD route reaches it) | `[Set] reset all: N rows` |

`/kcd reset <path>` (one row) and the Spells registry resets are unchanged.

## What was declined

Nothing. `LibKa0s-Item-1.0` remains unconsumed and was not re-offered.

## Other live references moved with the copy

- `CLAUDE.md` provenance line → v1.32.0.
- `docs/testing.md` → the sibling sits on v1.32.0.
- `docs/smoke-tests.md` §28: kit 17 is unchanged at v1.32.0.

## Gates

| Gate | Before the copy | After the copy (`2bf885c`) | After adoption (`7ef08c9`) |
|---|---|---|---|
| `luacheck .` | 0 / 0 in 95 files | 0 / 0 in 95 files | 0 / 0 in 95 files |
| `lua tests/run.lua` | 913 passed, 0 failed | 913 passed, 0 failed | **924 passed, 0 failed** |
| `tests/test_vendor_sync.lua` | green against v1.31.0 | green against v1.32.0 | green against v1.32.0 |
| eol gate (`tests/_kit/test_eol.lua`) | green | green | green |
| `lizard -C 15` | — | — | no function over 15 |

## Not pushed

Committed only. Pushing is `/wow-addon:finalize`'s.
