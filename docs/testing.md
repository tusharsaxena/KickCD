# Testing

A headless Lua unit harness lives under `tests/` — run `lua tests/run.lua` from the repo root (exits non-zero on any failure); `luacheck .` must stay at 0 errors. The suites load every source under a WoW-API mock and assert pure logic, the message bus, the full `OnInitialize → OnEnable` cascade that AceAddon fires on `PLAYER_LOGIN` (via `test_lifecycle`), and the per-frame coalescing of the chatty `SPELL_UPDATE_*` events (via `test_cooldowns`). The harness cannot render frames or model taint, so it complements rather than replaces the in-game checks.

The **authoritative test count and per-suite breakdown** live in the generated inventory at [test-cases.md](test-cases.md) — never a hand-typed number here. Regenerate it (and see the current total) with `lua tests/run.lua --list > docs/test-cases.md`. `lua tests/run.lua --list` is a non-executing listing mode: it loads every suite, prints the full inventory to stdout, and exits without running a single test.

## Keeping the inventory & badge in sync

`docs/test-cases.md` and the README `Tests` badge are hand-maintained-in-lockstep coverage artifacts (Ka0s WoW Addon Standard, testing-§5). Whenever the suite changes — a case is added, removed, or renamed, or the pass count moves (i.e. whenever a failing test is resolved) — regenerate the inventory via `lua tests/run.lua --list > docs/test-cases.md` **and** update the README `Tests-X/Y_passing` badge count in the **same change**, never as a deferred follow-up. Verify the inventory is in sync with `diff <(lua tests/run.lua --list) docs/test-cases.md` (no output = clean).

For end-to-end test scenarios — fresh install, visibility modes, lock/drag, cast bar auto-size, spec/talent/pet rebuilds, profile lifecycle, secret-value safety, etc. — see [smoke-tests.md](smoke-tests.md). The matrices below catalogue what each slash and debug command produces; they're the reference the smoke tests lean on.

## Slash command coverage

- `/kcd` — print the slash command help. `/kickcd` is a long-form alias that routes to the same handler. Every printed line should carry a cyan `[KCD]` prefix (added by `Util.print`); each help row should show the slash invocation in yellow and the description in white.
- `/kcd config` — open the settings panel. Refuses during combat (the Blizzard category-switch is protected); user gets a one-line print instead. `/kcd options` is an alias.
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the shared icon grid + cast bar lock state. Routes through `Helpers.SetAndRefresh("locked", ...)` so the General → "Lock frame" checkbox refreshes.
- `/kcd list` — dump every schema-driven setting grouped by panel, with current values. Useful for "did the panel/slash share state?" spot checks.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for every schema row. `path` is the dotted `db.profile` path (`enabled`, `icons.primarySize`, `icons.cooldownTint` …). `set` parses by `def.type`: bool accepts `true/false/on/off/1/0`; number is clamped to `[min, max]`; string must match a `values[i].value` (rejection prints the option list, plus `(depends on <gate> = ...)` when the row carries a `valueGate`); color takes 3–4 floats (`r g b [a]`, each clamped to `[0, 1]`). On success, any open panel refreshes its widgets via `Helpers.RefreshAllPanels()`.
- `/kcd reset <general|icons|castbar|spells>` — reset one panel to defaults. `general` / `icons` / `castbar` route through `Helpers.RestoreDefaults`; `spells` calls `Database:ResetAllSpells` (every spec, not just the active one).
- `/kcd resetall` — reset every schema-driven panel **and** every spec's spell list to addon defaults. Mirrors the General → "Reset all settings" popup but with no CLI confirmation prompt.
- `/kcd resetposition` — restore the icon grid to its default screen position. Mirrors the General → "Reset position" button.
- `/kcd spells <subcmd>` — per-class+spec spell-list editor (CLI parity for the Spells panel). Subcommands: `list`, `add`, `remove`, `enable`, `disable`, `category`, `reset`. Every subcommand accepts an optional trailing `[CLASS SPEC]`; both default to the player's current spec when omitted. Note: `/kcd spells reset` rebuilds **one** spec's list, while `/kcd reset spells` wipes every spec.

## Debug subcommands

Continuous debug output does **not** go to the chat frame. It routes through the `NS.Debug(tag, fmt, ...)` sink (gated on the session flag `NS.State.debug`) into the on-screen debug console — the DIALOG-strata "Ka0s KickCD — Debug" window in `modules/DebugLog.lua`. The enabled flag is session-only: default off, never persisted to SavedVariables (there is no `db.profile.debugLog` field and no General → "Debug" checkbox), and it resets each `/reload`. The structured `spells|castbar|interrupt` dumps below are still printed to chat.

- `/kcd debug window` — toggle the on-screen debug console window (ScrollingMessageFrame, Copy/Clear buttons, header Debug:ON/OFF toggle, shipped JetBrains Mono font). This is where `NS.Debug` output lands.
- `/kcd debug on` / `/kcd debug off` / `/kcd debug toggle` — set / clear / flip the session-only debug flag `NS.State.debug` via the single write seam `DebugLog:SetEnabled(on)`. Off by default; not persisted; resets each `/reload`.
- `/kcd debug spells` — dump (to chat) the watched cooldown list with `ready / active / cdObj / chargeCdObj / charges` per spell. `cdObj=yes` means a full-cooldown duration object is held; `chargeCdObj=yes` means a charge-recharge timer is ticking while the spell is still castable. We deliberately do NOT print remaining time — `:GetRemainingDuration()` is secret in combat and `tostring` would error in tainted scope; charges are also secret-safed via a `safeStr` placeholder.
- `/kcd debug castbar` — print (to chat) the current target's cast state plus the configured/live per-state colors and `notInterruptible`'s type/secret-status. Uses `type()` and `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error the dump.
- `/kcd debug interrupt` — dump (to chat) every `UnitCastingInfo` / `UnitChannelInfo` position with `type()` and `issecretvalue()` flag, plus what `NS.State.IsHostileUnitCasting("target")` and the addon-wide visibility / glow-trigger logic decided. The reference for diagnosing 12.0 secret-value handling drift (especially regressions in the `target_casting_interruptible` mode where `notInterruptible` cannot be inspected from Lua). Reads safely via the `safeRender` helper that short-circuits secret values to `<secret>`.

## In-game spot checks

The end-to-end scenarios that used to live here — interrupt-on-hostile, visibility-mode matrix, drag/reload persistence, spec / talent / pet rebuilds, cast bar auto-size — are now part of the comprehensive suite in [smoke-tests.md](smoke-tests.md). Run that file before claiming a non-trivial change works.
