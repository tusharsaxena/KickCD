# Summary (KickCD)

LibKa0s v1.66.0 -> v1.67.0 from the local tag (`0bccf4c`): Core 9 -> 10, Options 27 -> 28, OptionsIdList
2 -> 3; every other file unchanged. `tests/_kit` stays at kit revision 35 (no change between the tags). The
base is the tag the `CLAUDE.md` provenance line named (v1.66.0). Both content diffs are empty after the
copy, and nothing was deleted.

No span bundle: no vendored tag went unrecorded. No base correction.

Blockers: none. No consumer test broke from a library change.

Host changes in the re-vendor commit: the `CLAUDE.md` provenance line and `docs/testing.md`'s version-now
line roll to v1.67.0. The TOC needs no line: it loads `LibKa0s.xml`, and no file was added. The suite total
did not move, so `docs/test-cases.md` (regenerated, identical) and the README `Tests` badge (1282) stay.

Adopted: nothing in this commit. `addonName` is CA-KC-NM's; Core minor 10's grip fields have no taker here.

Gate after the copy:

- tests: 1282 passed, 0 failed, 1 skipped, 1283 total (identical before)
- luacheck: 0 warnings / 0 errors in 127 files
- vendor parity: `diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s` empty
- complexity (`bash tests/_kit/run-automated-tests.sh --suite complexity`, sighted): `pass`, max CCN 15,
  0 warnings, blindFiles 0, 3538 functions

Smoke: the re-vendor routing in `docs/smoke-tests.md` already covers what this release moves, including
DIAG-34 – 38 (the console, copy window and perf panel grips, which `MakeResizable` minor 10 must leave
exactly as on v1.66.0). Owner-run; not marked here.
