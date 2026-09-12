# 05 — Summary: LibKa0s v1.29.0 → v1.30.0

## The move

| | |
|---|---|
| From | v1.29.0 |
| To | **v1.30.0** |
| Files under `LibKa0s/` that moved | none: every LibStub minor is the one v1.29.0 shipped |
| Kit revision | 15 → **16** (`README.md`, `framework.lua`, `mock_base.lua`, `vendor_sync.lua`) |
| Files removed upstream | none |
| Cross-major skew found | none |

## What reached this addon for free

The runner-mode case (#28), through `VendorSync.register`. The suite went from 870 to **871**. The
README `[Tests]` badge and `docs/test-cases.md` moved in the same commit.

## What was adopted

Nothing needed adopting. There was no local shim of #27, #29 or #30 to delete. There is no
`04_EXECUTION_PLAN.md` in this bundle because nothing was implemented.

## What was declined

#27, #29 and #30 are inert here: `tests/wow_mock.lua` replaces the kit's LibStub and Ace layer
wholesale. Taking them means a harness migration, declined for this run. Not filed. It went back
to the orchestrating session as a proposed issue (see `03_DECISIONS.md`).

## Other live references moved with the copy

- `CLAUDE.md` provenance line → v1.30.0.
- `docs/testing.md` → the sibling now sits on v1.30.0.
- `docs/smoke-tests.md` §28 said the mock's zero-height geometry "flips at kit 16". The v1.30.0
  changelog says it does not; the flip ships alone, at kit 17 at the earliest.
- `tests/test_vendor_sync.lua` header → names the one case the kit now adds.

## Gates

| Gate | Before | After |
|---|---|---|
| `luacheck .` | 0 warnings / 0 errors in 94 files | 0 warnings / 0 errors in 94 files |
| `lua tests/run.lua` | 870 passed, 0 failed, 0 skipped | **871 passed, 0 failed, 0 skipped** |
| `tests/test_vendor_sync.lua` | green | green, both payloads against v1.30.0 |
| eol gate (`tests/_kit/test_eol.lua`) | green | green |

`luacheck`'s figure is scoped by `.luacheckrc`'s `exclude_files`, which excludes `libs/` and
`tests/_kit/`. A clean run says the **host** is clean; the payload's own gate is upstream.

## Not pushed

Committed only. Pushing is `/wow-addon:finalize`'s.
