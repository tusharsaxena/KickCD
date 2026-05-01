# Testing

There is no automated test harness. Verification is manual:

## Slash command coverage

- `/kcd` — print the slash command help. `/kickcd` is a long-form alias
  that routes to the same handler. Every printed line should carry a
  cyan `[KCD]` prefix (added by `Util.print`); each help row should
  show the slash invocation in yellow and the description in white.
- `/kcd config` — open the settings panel. Refuses during combat (the
  Blizzard category-switch is protected); user gets a one-line print
  instead. `/kcd options` is an alias.
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the shared icon
  grid + cast bar lock state. Routes through
  `Helpers.SetAndRefresh("locked", ...)` so the General → "Lock frame"
  checkbox refreshes.
- `/kcd list` — dump every schema-driven setting grouped by panel,
  with current values. Useful for "did the panel/slash share state?"
  spot checks.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for
  every schema row. `path` is the dotted `db.profile` path
  (`enabled`, `icons.primarySize`, `icons.cooldownTint` …). `set`
  parses by `def.type`: bool accepts `true/false/on/off/1/0`; number
  is clamped to `[min, max]`; string must match a `values[i].value`
  (rejection prints the option list, plus `(depends on <gate> = ...)`
  when the row carries a `valueGate`); color takes 3–4 floats
  (`r g b [a]`, each clamped to `[0, 1]`). On success, any open panel
  refreshes its widgets via `Helpers.RefreshAllPanels()`.
- `/kcd reset <general|icons|castbar|spells>` — reset one panel to
  defaults. `general` / `icons` / `castbar` route through
  `Helpers.RestoreDefaults`; `spells` calls
  `Database:ResetAllSpells` (every spec, not just the active one).
- `/kcd resetall` — reset every schema-driven panel **and** every spec's
  spell list to addon defaults. Mirrors the General → "Reset all
  settings" popup but with no CLI confirmation prompt.
- `/kcd resetposition` — restore the icon grid to its default screen
  position. Mirrors the General → "Reset position" button.
- `/kcd spells <subcmd>` — per-class+spec spell-list editor (CLI parity
  for the Spells panel). Subcommands: `list`, `add`, `remove`, `enable`,
  `disable`, `category`, `reset`. Every subcommand accepts an optional
  trailing `[CLASS SPEC]`; both default to the player's current spec
  when omitted. Note: `/kcd spells reset` rebuilds **one** spec's list,
  while `/kcd reset spells` wipes every spec.

## Debug subcommands

- `/kcd debug spells` — dump the watched cooldown list with
  `ready / active / cdObj / chargeCdObj / charges` per spell.
  `cdObj=yes` means a full-cooldown duration object is held;
  `chargeCdObj=yes` means a charge-recharge timer is ticking while the
  spell is still castable. We deliberately do NOT print remaining time —
  `:GetRemainingDuration()` is secret in combat and `tostring` would
  error in tainted scope; charges are also secret-safed via a `safeStr`
  placeholder.
- `/kcd debug castbar` — print the current target's cast state plus the
  configured/live per-state colors and `notInterruptible`'s type/secret-
  status. Uses `type()` and `issecretvalue()` rather than `tostring` so
  a secret-tainted record doesn't error the dump.
- `/kcd debug interrupt` — dump every `UnitCastingInfo` /
  `UnitChannelInfo` position with `type()` and `issecretvalue()` flag,
  plus what `KickCD.State.IsHostileUnitCasting("target")` and the addon-wide
  visibility / glow-trigger logic decided. The reference for diagnosing
  12.0 secret-value handling drift (especially regressions in the
  `target_casting_interruptible` mode where `notInterruptible` cannot be
  inspected from Lua). Reads safely via the `safeRender` helper that
  short-circuits secret values to `<secret>`.
- `/kcd debug log` — toggle internal-message logging (mirrors the
  General → Debug checkbox; both write `db.profile.debugLog`). Section
  is `"debug"` (no module listens) so toggling doesn't trigger a wasted
  Cooldowns:Rebuild.

## In-game spot checks

- Target a hostile caster, fire your interrupt, confirm the icon
  desaturates without errors. The Lua error frame (or BugSack /
  BugGrabber) is the primary regression signal.
- Set General → Visibility to "When target is casting an interruptible
  spell". Targeting a friendly unit, your own self, or a hostile mob
  casting a non-interruptible spell should all leave the addon hidden.
  Targeting a hostile mob mid-interruptible cast should show it; the
  bar/icons should stay hidden during the uninterruptible phase of a
  cast that toggles via `UNIT_SPELLCAST_INTERRUPTIBLE` /
  `_NOT_INTERRUPTIBLE` events.
- Unlock with `/kcd unlock`, drag the icon grid and (in FREE anchor
  mode) the cast bar; relock with `/kcd lock`; reload UI; positions
  should persist.
- Switch spec; the Cooldowns module should rebuild the watched list and
  the IconGrid should re-acquire pooled icons against the new spec's
  default spell list.
- Talent change in the active spec (e.g. swap a choice node, summon /
  dismiss a hunter pet): the watched list and grid should rebuild
  immediately via the `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED` events
  without waiting for a spec change.
- Set Cast bar → Anchor mode = "Anchored to primary icon" with auto-size
  on, then resize the icon grid (e.g. change rows / cols, hide a spell
  via `/kcd spells disable`); the cast bar's long axis should track the
  grid's actual visible footprint, not the configured row × col
  capacity.
