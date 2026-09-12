# 05 — Summary: LibKa0s v1.32.0 → v1.33.0

## The move

| | |
|---|---|
| From | v1.32.0 (`e18dd12`) |
| To | **v1.33.0** (tag `7d5e061`, commit `06ee368`) |
| Files under `LibKa0s/` that moved | `Options.lua` (`MINOR` 16 → 17), `Slash.lua` (`MINOR` 8 → 9) |
| Kit revision | 17 → **18** (`README.md`, `framework.lua`, `mock_base.lua`) |
| Files removed upstream | none |
| Cross-major skew found | none |

## What reached this addon for free

- **Font dropdowns draw every row on their first open.** This is the Cast bar and Text Label
  `H.FontGroup` rows. It still needs an in-game check. On a fresh session, open Settings →
  Ka0s KickCD → Cast bar → the font dropdown, and every row should draw on the first open.
- Slash 9 and kit 18 change nothing observable here (see 02_CANDIDATES).

## What was adopted, and what was declined

Nothing needed a host change. No issue was filed.

## The re-vendor commit

The re-vendor is one commit on top of the Profiles `Show()` fix (`ea50cba`). In the same commit:

- the provenance line (`CLAUDE.md:52`) and `docs/testing.md:147` move from v1.32.0 to v1.33.0;
- the geometry-flip note at `docs/smoke-tests.md:768`–`:769` moves to "kit 18 (LibKa0s v1.33.0) did
  not flip that either … kit 19 at the earliest", because kit 18 did not ship the flip.

`docs/settings-panel.md:183` and `settings/Panel.lua:264` name Options 16 / Slash 8 as the minors
that introduced the bulk bracket. Those are history and stay as written.

## Gates

| When | `lua tests/run.lua` | `luacheck .` | lizard `-C 15` |
|---|---|---|---|
| Baseline, `ea50cba` | 930 passed, 0 failed, 0 skipped | 0 / 0 in 95 files | clean |
| Re-vendor (this bundle's commit) | 930 passed, 0 failed, 0 skipped | 0 / 0 in 95 files | clean |

`tests/test_vendor_sync.lua` compared both payloads against the tag and skipped none. Every changed
file is CRLF, with CR equal to LF. Nothing was pushed.
