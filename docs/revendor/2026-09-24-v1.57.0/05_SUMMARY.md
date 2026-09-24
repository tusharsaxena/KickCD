# 05 — Summary: LibKa0s v1.56.0 -> v1.57.0

Plan item M5-KC, 2026-09-24, branch `feat/2026-09-23-review-audit-remediation`. Written by hand, the
same way RV-KC wrote the v1.56.0 bundle. Nothing pushed, and the addon version is not bumped.

## The tag, and the per-file minors

`v1.56.0` -> `v1.57.0` (tag object `d03e836`, commit `aa37bc9`). One file moves a minor:
`Launcher.lua` 2 -> 3. The kit stays at revision 26, byte for byte. Details in `01_DELTA.md`.

## Delivered on the re-vendor, with nothing asked for

- The minimap button and the broker plugin answer a hover with the library's status tooltip, enabled
  or disabled: `Ka0s KickCD`, `Enabled`, the click hints.

## Adopted

`launcher-§1` (standard v2.66.0) makes the tooltip a MUST and names what the host owes. M5-KC's
second commit supplies it in `core/LauncherSetup.lua`:

- `version`: the TOC's `## Version`, through `NS.Version()` (core/EnvSetup.lua), asked on every show.
- `isEnabled` / `disabledLine`: the Master-controls `Enable` row's reader (`NS.MasterEnabled`) and
  the Slash dispatcher's own `DisabledLine()`. The left click's disabled gate moves from the host's
  `onClick` into the library's (Launcher version 2), so the tooltip's `Enabled` line and the click
  refusal read one accessor.
- `isLocked`: `db.profile.locked`, the path the `Lock frame` row writes.
- `leftClickLabel`: rung (b), lock / unlock (`ADDONS.md`), asked on every show: `Unlock frame` while
  locked, `Lock frame` while unlocked, through the addon's locale.
- No `isTestMode`: this addon has no test mode (unlocking is the preview, options-ui-§15's
  exemption). No `onTooltipShow`: the addon has no extra lines.

## Contract blockers

None.

## Gates at the copy

| Suite | Result |
|---|---|
| `ka0s-bounded luacheck .` | 0 warnings / 0 errors in 106 files |
| `ka0s-bounded lua5.1 tests/run.lua` | 1141 passed, 0 failed, 0 skipped, 1141 total |
| `diff -r` of both payloads against the tag | empty |
