# Slash dispatch

Three ordered tables in `core/KickCD.lua` drive the entire slash UX:

- `COMMANDS` — top-level subcommands.
- `DEBUG_COMMANDS` — `/kcd debug ...`.
- `SPELLS_COMMANDS` — `/kcd spells ...`.

Each row is `{ name, description, fn }`. The dispatcher:

- Bare `/kcd` → `printHelp` (iterates `COMMANDS`).
- `/kcd <known>` → executes that row's `fn`.
- `/kcd debug` → `runDebug("")` prints the help index for `DEBUG_COMMANDS`.
- `/kcd debug <known>` → executes that row's `fn`.
- `/kcd spells` → `runSpells("")` prints the help index for `SPELLS_COMMANDS` plus the player's resolved class/spec defaults.
- `/kcd spells <known>` → executes that row's `fn`.
- `/kcd <unknown>` → "unknown command" + help.
- `/kcd options` is aliased to `/kcd config` for backward compat.

`/kcd config` (and the `OpenSettings()` API behind `KickCD:OpenSettings`) opens the **General subcategory directly**, not the parent category — in WoW 12.0 a Blizzard parent category with subcategories hides its own widgets, so opening the parent would show an empty pane. The fallback target is `KickCD.SettingsCategoryID` for the rare case where the General subcategory hasn't registered yet. `InCombatLockdown()` is checked before opening so the protected category-switch doesn't fail mid-fight; the user gets a one-line "cannot open during combat" print instead.

`OnSlashCommand` lowercases only the command name and preserves case in the rest of the input, so schema paths like `icons.primarySize` survive unchanged through `/kcd set ...`. `runDebug` and `runSpells` lowercase their own subcommand for backward compat.

## Top-level commands

| Command | Purpose | Notes |
|---|---|---|
| `help` | Print the help index. | Iterates `COMMANDS`. |
| `config` | Open the settings panel. | Combat-gated; targets the General subcategory. |
| `lock` / `unlock` / `toggle` | Set / clear / flip `db.profile.locked`. | Routes through `Helpers.SetAndRefresh("locked", ...)` so the General → "Lock frame" checkbox refreshes and any future onChange wired onto the schema row fires. Falls back to a direct write if the settings layer isn't loaded yet. |
| `list` | Dump every schema-driven setting grouped by panel, with current values. | Schema-driven. |
| `get <path>` | Print one setting's current value. | Schema-driven; uses `Helpers.FindSchema(path)`. |
| `set <path> <value>` | Type-aware write to one setting. | Schema-driven; clamps numbers, validates dropdown values, parses `r g b [a]` for colors. On invalid string values, surfaces the option list — and if the schema row carries `valueGate`, also reports the gating sibling and its current value (e.g. `castbar.growDirection` reporting that the option list depends on `castbar.orientation = VERTICAL`). |
| `reset <general\|icons\|castbar\|spells>` | Reset one panel to defaults. | `general` / `icons` / `castbar` route through `Helpers.RestoreDefaults`; `spells` calls `Database:ResetAllSpells` (wipes every spec, not just the active one). |
| `resetall` | Reset every schema-driven panel **and** every spec's spell list. | Calls `Helpers.ResetAll`, the same helper behind General → "Reset all settings" popup. No CLI confirmation. |
| `resetposition` | Restore the icon grid to its default screen position. | Calls `Helpers.ResetIconPosition`. |
| `spells <subcmd>` | Per-class+spec spell-list editor (CLI parity for the Spells panel). | See subtable below. |
| `debug <subcmd>` | Diagnostic subcommands. | See subtable below. |

`list`, `get`, and `set` gain new entries automatically as schema rows are added — see [ARCHITECTURE_SETTINGS_UI.md](ARCHITECTURE_SETTINGS_UI.md). Adding a regular command is a one-row append; help text is generated from the same rows that drive dispatch.

## `/kcd spells <subcmd>`

Edits the per-class+spec spell list at `db.profile.spells[CLASS][SPEC]`. CLASS is the upper-case class file token (`WARRIOR`, `DEATHKNIGHT`, …) and SPEC is the upper-case localized spec name with whitespace stripped (`FROST`, `BEASTMASTERY`, …) — matches the keys in `defaults/Spells.lua`. Every subcommand accepts an optional trailing `[CLASS SPEC]`; when omitted, both default to the player's current class+spec.

| Subcommand | Purpose |
|---|---|
| `list [CLASS SPEC]` | Print the watched list with index, spell ID, name, category, and disabled flag. |
| `add <id\|name> [CLASS SPEC]` | Append a spell. Re-enables an existing entry rather than duplicating. Accepts spell name as well as ID. |
| `remove <id> [CLASS SPEC]` | Drop a spell from the list. |
| `enable <id> [CLASS SPEC]` / `disable <id> [CLASS SPEC]` | Flip the entry's `enabled` flag. |
| `category <id> <cat> [CLASS SPEC]` | Re-categorize an entry. Allowed: `interrupt`, `stun`, `knockback`, `incapacitate`, `silence`, `root`, `fear`, `displace`, `racial`, `other`. |
| `reset [CLASS SPEC]` | Rebuild one `(CLASS, SPEC)` list from `KickCD.DefaultSpells`. Mirrors the Spells panel's Defaults popup; intentionally narrower than `/kcd reset spells` (which wipes every spec via `Database:ResetAllSpells`). |

Every mutating subcommand fires `KickCD_CONFIG_CHANGED { section = "spells" }` and nudges the open Spells panel to redraw via `KickCD.SettingsSpells:RefreshRows` (the panel listens for `KickCD_PROFILE_CHANGED` but not for the section-keyed `_CONFIG_CHANGED`, so this direct call is what keeps the open editor in sync after a CLI write).

## `/kcd debug <subcmd>`

| Subcommand | Purpose |
|---|---|
| `spells` | Dump the watched cooldown list (`Cooldowns:DebugDump`). Prints `ready / active / cdObj / chargeCdObj / charges` per spell. Charges are `safeStr`-ed because they're secret-tainted in combat for charged spells; remaining time is deliberately not printed (`:GetRemainingDuration()` is secret in combat). |
| `castbar` | Print current target cast state plus configured/live per-state colors and `notInterruptible`'s type/secret flag (`Castbar:DebugDump`). Uses `type()` and `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error the dump. |
| `interrupt` | Dump `UnitCastingInfo` / `UnitChannelInfo` positions with their `type` and `issecretvalue()` flag, plus what `Compat.IsHostileUnitCasting` and the addon-wide visibility/glow logic decided. The reference for diagnosing 12.0 secret-value handling drift (added during the visibility-mode rework). |
| `log` | Toggle internal-message logging. Routes through `Helpers.SetAndRefresh("debugLog", ...)` so the General → Debug checkbox refreshes; section is `"debug"` (no module listens) so toggling it doesn't cascade into a wasted Cooldowns:Rebuild. |
