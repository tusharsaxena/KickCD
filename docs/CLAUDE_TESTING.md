# Testing

There is no automated test harness. Verification is manual:

- `/kcd` — print the slash command help.
- `/kcd list` — dump every schema-driven setting grouped by panel,
  with current values. Useful for "did the panel/slash share state?"
  spot checks.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for
  every schema row. `path` is the dotted `db.profile` path
  (`enabled`, `icons.primarySize`, `icons.cooldownTint` …). `set`
  parses by `def.type`: bool accepts `true/false/on/off/1/0`; number
  is clamped to `[min, max]`; string must match a `values[i].value`;
  color takes 3–4 floats (`r g b [a]`). On success, any open panel
  refreshes its widgets via `Helpers.RefreshAllPanels()`.
- `/kcd debug spells` — dump the watched cooldown list with `ready / active / cdObj / charges` per spell. `cdObj=yes` means a duration object is held; `nil` means the spell is off cooldown. We deliberately do NOT print remaining time — `:GetRemainingDuration()` is secret in combat and `tostring` would error in tainted scope.
- `/kcd debug log` — toggle internal-message logging (mirrors the
  General → Debug checkbox; both write `db.profile.debugLog`).
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the icon grid lock state.
- In-game: target a hostile caster, fire your interrupt, confirm the icon desaturates without errors. The Lua error frame (or BugSack/BugGrabber) is the primary regression signal.
