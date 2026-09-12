# 05 — Summary: LibKa0s v1.30.0 → v1.31.0

## The move

| | |
|---|---|
| From | v1.30.0 |
| To | **v1.31.0** (`30db4ed`) |
| Files under `LibKa0s/` that moved | `OptionsCompose.lua` (`COMPOSE_MINOR` 3 → 4), `OptionsWidgets.lua` (`WIDGETS_MINOR` 14 → 15) |
| Kit revision | 16 → **17** (`README.md`, `framework.lua`, `mock_base.lua`) |
| Files removed upstream | none |
| Cross-major skew found | none |

## What reached this addon for free

The Options arm and the composer arm are both path-gated, and every KickCD row carries a path, so
both reached this addon with no change to its output. Kit revision 17 changed no count on the copy:
894 before, 894 after. The harness still replaced the kit's Ace layer at that point, which is why.

## What was adopted

**Kit revision 17's Ace surfaces, by migrating the harness (KickCD#21).** Three commits:

| Commit | What |
|---|---|
| `2c83ee0` | Characterization first, on the old harness: the addon-then-modules enable order, string-method dispatch, the default method named after the message, and `UnregisterMessage` scoped to its target. 894 → 898. |
| `adbf507` | `tests/wow_mock.lua` layers over the kit. It swapped one library at a time (LibStub, AceGUI, AceConsole, AceTimer, AceAddon, AceEvent), and each run was green. The ports: `__embedAceEvent` became `LibStub("AceEvent-3.0"):Embed`, and `__busRegistry` became the kit's `__msgRegistry`. Three cases show kit revisions now reach the suite: `Printf`, the recorded and validated event half with `__fireEvent`, and `AceGUI:Release`. All three are red on the old harness. 898 → 901. |

KickCD keeps local only what the kit's version-17 document lists for it: its non-Ace library fakes
and its AceDB (registered into `mocks.__libs`), the `SetHighlight` recorder (a wrap on
`AceGUI:Create`), `__enableAll` (one line over `AceAddon:EnableAddon`), its frame model and its
`C_Timer` queue.

## What was declined

`spec.bind`, the record-backed composer arm, is not applicable: no KickCD page composes a group over
a registry record. It was not filed, because the orchestrator asked for no filing
(`03_DECISIONS.md`).

## Other live references moved with the copy

- `CLAUDE.md` provenance line → v1.31.0.
- `docs/testing.md` → the sibling now sits on v1.31.0.
- `docs/smoke-tests.md` §28: kit 17 did not flip zero-height geometry either. The flip is now "18 at
  the earliest", as the v1.31.0 changelog says.

## Gates

| Gate | Before the copy | After the copy (`ca6e0d5`) | After #21 (`adbf507`) |
|---|---|---|---|
| `luacheck .` | 0 / 0 in 95 files | 0 / 0 in 95 files | 0 / 0 in 95 files |
| `lua tests/run.lua` | 894 passed, 0 failed | 894 passed, 0 failed | **901 passed, 0 failed** |
| `tests/test_vendor_sync.lua` | green against v1.30.0 | green against v1.31.0 | green against v1.31.0 |
| eol gate (`tests/_kit/test_eol.lua`) | green | green | green |
| `lizard -C 15` on the changed test files | — | — | no function over 15 |

`luacheck`'s figure is scoped by `.luacheckrc`'s `exclude_files`, which excludes `libs/` and
`tests/_kit/`. A clean run says the **host** is clean; the payload's own gate is upstream.

## Not pushed

Committed only. Pushing is `/wow-addon:finalize`'s.
