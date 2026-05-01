# Conventions

- Module files start with a one-paragraph header explaining the module's job and its message contract.
- Closed-set adherence: a module that names messages it emits or listens to should keep that list in sync with the actual code.
- Saved variables live under `KickCDDB`; the active profile shape is `DEFAULT_PROFILE` in `core/Database.lua`. New persistent fields go in that table, with a comment explaining the shape and any 12.0 secret-value caveats.
- Settings reads / writes that come from outside `settings/Panel.lua` (slash commands, keybinds, …) should route through `Helpers.SetAndRefresh(path, value)` so they share the panel widgets' write-notify-refresh code path. Direct `db.profile` writes are reserved for places where no schema row exists (drag-stop anchor save, profile bootstrap).
- New schema rows automatically gain `/kcd get|set|list` coverage, the per-panel Defaults reset, and the General → "Reset all settings" reset. Don't add a parallel mutator for a field that already has a schema row.
- Visibility / glow / interruptibility decisions that depend on `notInterruptible` MUST go through the two-step gate (`Compat.IsHostileUnitCasting` for show + `Compat.ApplyInterruptibleAlpha` for filter). Lua-side comparison of the secret bool errors in combat — see [CLAUDE_SECRET_VALUES.md](CLAUDE_SECRET_VALUES.md).
- All code is plain Lua 5.1 (WoW's runtime). No external Lua deps beyond vendored Ace3 / LSM / LibCustomGlow.
- Line endings on tracked files are CRLF (the tree was normalized in commits `b6b9853` / `a74251a` / `3ba3ca3`). New files added by an agent should match the surrounding files in their directory.

