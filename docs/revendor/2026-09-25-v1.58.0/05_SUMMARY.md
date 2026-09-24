# 05 — Summary: LibKa0s v1.57.0 -> v1.58.0

Plan item M6-KC, 2026-09-25, branch `feat/2026-09-23-review-audit-remediation`. Written by hand, the
same way M5-KC wrote the v1.57.0 bundle. Nothing pushed, and the addon version is not bumped.

## The tag, and the per-file minors

`v1.57.0` -> `v1.58.0` (tag object `93cf3ad`, commit `34931c9`). One file moves a minor:
`Launcher.lua` 3 -> 4. The kit stays at revision 26, byte for byte. Details in `01_DELTA.md`.

## Delivered on the re-vendor, with nothing asked for

- Left-click opens the settings panel, enabled or disabled.
- The tooltip's hints read `Left-click: Open settings` and `Right-click: Options menu`.
- The disabled left-click refusal is gone.

## Adopted

`launcher-§2` (standard v2.67.0) makes the options menu a MUST and names what the host owes. The same
M6-KC commit supplies it in `core/LauncherSetup.lua`, matching WowAddonStandards `ADDONS.md`'s row for
KickCD, `Enabled · Locked`:

- `setEnabled` beside `isEnabled`: `NS.SetMasterEnabled(on)`, newly published in `core/KickCD.lua`
  as THE handler `/kcd enable` and `/kcd disable` run (it is `/kcd set enabled <bool>`), so the verbs
  and the menu entry are two callers of one function.
- `toggleLock` beside `isLocked`: `NS.ToggleLock`, the handler `/kcd toggle` already ran.
- No test-mode pair (no test mode: unlocking is the preview, options-ui-§15's exemption) and no
  window pair (no primary window).
- `onClick`, `leftClickLabel` and `disabledLine` deleted from the descriptor. With them go
  `NS.Slash.DisabledLine` (its only caller was `disabledLine`) and the `Unlock frame` locale key (its
  only reader was `leftClickLabel`).
- `version`, `isEnabled` and `isLocked` stay as M5 wired them.

Tests drive the menu through `tests/mock_menu.lua`, the library's own `MenuUtil` stand-in copied
whole (the library keeps it repo-local, not in the kit).

## Contract blockers

The seven red cases at the copy (`01_DELTA.md`, 3g) pinned the retired rung, its refusal and its
hints; each is replaced by a case on the version 4 contract.

## Gates after the adoption

| Suite | Result |
|---|---|
| `ka0s-bounded luacheck .` | 0 warnings / 0 errors in 107 files |
| `ka0s-bounded lua5.1 tests/run.lua` | 1151 passed, 0 failed, 0 skipped, 1151 total |
| `ka0s-bounded lizard ... -C 15 -w .` | no function above CCN 15 |
| `diff -r --strip-trailing-cr` of both payloads against the tag | empty |
