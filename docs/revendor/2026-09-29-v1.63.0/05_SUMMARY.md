# Summary (KickCD)

LibKa0s v1.62.0 -> v1.63.0 from the local tag (`dd7a774`): Slash 16 -> 17, every other file
unchanged. `tests/_kit` stays at kit revision 31. The base is the tag the `CLAUDE.md` provenance line
named (v1.62.0), and no tag the addon vendored is unrecorded, so no span bundle is written. Both
content diffs are empty after the copy, and nothing was deleted.

Blocker: the Slash degradation stub failed the kit's by-name surface parity on the copy alone
(`CliProfile` and `ProfileSwitch` missing). Resolved in the re-vendor commit: the stub carries both
on route (b), each printing the library-absent line for `/kcd profile`.

Adopted: only the Slash minor 17 profile surface, by item SP-KC-02 (`/kcd profile` via
`CliProfile`), in its own commit after the re-vendor. No interview was run and no issue was filed:
the adoption was decided by the run's owner decisions D1-D3.

Host changes in the re-vendor commit: the `CLAUDE.md` provenance line and `docs/testing.md`'s
version-now line roll to v1.63.0, the stub gains its two members, `docs/slash-dispatch.md`'s
degraded-verbs list names them, and one case is added to `tests/test_slash.lua`.
`docs/test-cases.md` and the README `Tests` badge move to 1202.

Gate after the copy and the stub fix:

- tests: 1202 passed, 0 failed, 0 skipped, 1202 total (1201 before the copy; the copy alone left
  1200 passed and 1 failed, the parity case)
- luacheck: 0 warnings / 0 errors in 112 files
- lizard (`-x ./libs/* -x ./tests/_kit/*`, CCN 15): 0 warnings
