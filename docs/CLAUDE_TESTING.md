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
- `/kcd debug spells` — dump the watched cooldown list with `ready / active / cdObj / chargeCdObj / charges` per spell. `cdObj=yes` means a full-cooldown duration object is held; `chargeCdObj=yes` means a charge-recharge timer is ticking while the spell is still castable. We deliberately do NOT print remaining time — `:GetRemainingDuration()` is secret in combat and `tostring` would error in tainted scope; charges are also secret-safed via a `safeStr` placeholder.
- `/kcd debug castbar` — print the current target's cast state plus the configured/live per-state colors and `notInterruptible`'s type/secret-status. Uses `type()` and `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error the dump.
- `/kcd debug log` — toggle internal-message logging (mirrors the
  General → Debug checkbox; both write `db.profile.debugLog`).
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the icon grid lock state.
- In-game: target a hostile caster, fire your interrupt, confirm the icon desaturates without errors. The Lua error frame (or BugSack/BugGrabber) is the primary regression signal.
