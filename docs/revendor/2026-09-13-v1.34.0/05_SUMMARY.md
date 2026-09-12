# 05 — Summary: LibKa0s v1.33.0 → v1.34.0

## The move

| | |
|---|---|
| From | v1.33.0 (tag `7d5e061`, commit `06ee368`) |
| To | **v1.34.0** (tag `9165044`, commit `33bae81`) |
| Files under `LibKa0s/` that moved | `Options.lua` (`MINOR` 17 → 18), `OptionsCompose.lua` (`_MINOR` 4 → 5), `Slash.lua` (`MINOR` 9 → 10) |
| Kit revision | 18 → **19** (`README.md`, `framework.lua`, `mock_base.lua`) |
| Files removed upstream | none |
| Cross-major skew found | none |

## What reached this addon for free

- **A label's text keeps every word from the slash.** `/kcd set units.target.label.text Kick Now`
  stores `"Kick Now"`.
- **The Reset-all tooltip says "current profile"** on the copy alone, because the descriptor
  supplies `resetProfile`.
- Kit 19 changes nothing observable here (see 01_DELTA).

## What was adopted, and what was declined

B1, `profilesPage = true`, is adopted in its own commit. Nothing was declined. No issue was filed.

## The re-vendor commit

The re-vendor is one commit on top of `cae55d2`. In the same commit:

- the provenance line (`CLAUDE.md:52`) and `docs/testing.md:147` move from v1.33.0 to v1.34.0;
- the geometry-flip note at `docs/smoke-tests.md:768`–`:769` moves to "kit 19 (LibKa0s v1.34.0) did
  not flip that either … kit 20 at the earliest", because kit 19 did not ship the flip.

## Gates

| When | `lua tests/run.lua` | `luacheck .` | lizard `-C 15` |
|---|---|---|---|
| Baseline, `cae55d2` | 931 passed, 0 failed, 0 skipped | 0 / 0 in 95 files | clean |
| Re-vendor (this bundle's commit) | 931 passed, 0 failed, 0 skipped | 0 / 0 in 95 files | clean |

`tests/test_vendor_sync.lua` compared both payloads against the tag and skipped none. Every changed
file is CRLF, with CR equal to LF. Nothing was pushed.
