# Slash dispatch

Three ordered tables in `core/KickCD.lua` drive the entire slash UX:

- `COMMANDS` — top-level subcommands.
- `DEBUG_COMMANDS` — `/kcd debug ...`.
- `SPELLS_COMMANDS` — `/kcd spells ...`.

`/kickcd` and `/kcd` are both registered via `RegisterChatCommand` and dispatch to the same `OnSlashCommand` handler — `/kickcd` is the long-form alias, all help text and docs use the short form.

Each row is `{ name, description, fn }`. The dispatcher:

- Bare `/kcd` → `printHelp` (iterates `COMMANDS`).
- `/kcd <known>` → executes that row's `fn`.
- `/kcd debug` → `runDebug("")` toggles the on-screen debug console window (`DebugLog:Toggle`) **and** prints the verb list for `DEBUG_COMMANDS`.
- `/kcd debug <known>` → executes that row's `fn`.
- `/kcd spells` → `runSpells("")` prints the help index for `SPELLS_COMMANDS` plus the player's resolved class/spec defaults.
- `/kcd spells <known>` → executes that row's `fn`.
- `/kcd <unknown>` → "unknown command" + help.
- `/kcd options` is aliased to `/kcd config` for backward compat.

`/kcd config` (and the `OpenSettings()` API behind `NS:OpenSettings`) lands the user on the **Ka0s KickCD parent page** (logo + slash-command list) with the subcategory tree expanded in the left nav so all six sibling tabs (General / Icons / Cast bar / Text Label / Spells / Profiles) are visible. Implementation: `Settings.OpenToCategory(main:GetID())` to display the parent page, then a defensive `expandMainCategory()` that reaches into `SettingsPanel:GetCategoryList():GetCategoryEntry(main):SetExpanded(true)` to force the tree open (Blizzard's CategoryList only auto-expands a parent's tree when one of its *children* is selected, never on parent self-select). The expand call is wrapped in `pcall` because `SettingsPanel.CategoryList` / `GetCategoryEntry` / `SetExpanded` are Blizzard private API that could shift between patches — if any link breaks we silently fall through to "parent opened, tree collapsed", one click away from the same end state. If the panel hasn't registered yet (a `/kcd config` immediately after login can race the `PLAYER_LOGIN`-deferred `RegisterPanel`), `OpenSettings` schedules a deferred retry via `C_Timer.After(0.5, ...)` — capped at 3 attempts. The combat-lockdown check lives inside `OpenSettings` itself (not the `/kcd config` callback) so every entry point — slash, the deferred retry, any future caller — shares the gate; it prefers `NS.State.inCombat` (the regen-event flag, which leads `InCombatLockdown()` by a frame) and falls back to `InCombatLockdown()` only when `core/State.lua` hasn't loaded yet. On a hit the user gets a one-line `L["Cannot open settings during combat."]` print and the deferred-retry counter is cleared so a queued open won't re-fire while combat is still up.

`OnSlashCommand` lowercases only the command name and preserves case in the rest of the input, so schema paths like `units.target.icons.primarySize` survive unchanged through `/kcd set ...`. `runDebug` and `runSpells` lowercase their own subcommand for backward compat.

## Chat output

Every chat line emitted by the addon flows through `Util.print` (`core/Util.lua`), which prepends a single cyan `|cff00ffff[KCD]|r` banner. Call sites pass plain text — they don't include their own prefix. The help printers (`printHelp`, `runDebug`'s no-arg branch, `runSpells`'s no-arg branch) wrap each row's invocation in `|cffffff00…|r` (yellow) and the description in `|cffffffff…|r` (white) so the slash command and its explanation are visually distinct in chat. The schema-error path in `settings/Panel.lua` also routes through `Util.print` so it shares the `[KCD]` banner; only the inner `schema error:` token is colored red.

## Top-level commands

| Command | Purpose | Notes |
|---|---|---|
| `help` | Print the help index. | Iterates `COMMANDS`. |
| `version` | Print the addon version. | `v<X.Y.Z>` from `C_AddOns.GetAddOnMetadata` with the `NS.VERSION` stamp as fallback (slash-commands-§3). |
| `config` | Open the settings panel. | Combat-gated; lands on the parent page with the subcategory tree expanded in the left nav. |
| `lock` / `unlock` / `toggle` | Set / clear / flip `db.profile.locked`. | Routes through `Helpers.SetAndRefresh("locked", ...)` so the General → "Lock frame" checkbox refreshes and any future onChange wired onto the schema row fires. Falls back to a direct write if the settings layer isn't loaded yet. |
| `list` | Dump every schema-driven setting grouped by panel, with current values. | Schema-driven. |
| `get <path>` | Print one setting's current value. | Schema-driven; uses `Helpers.FindSchema(path)`. |
| `set <path> <value>` | Type-aware write to one setting. | Schema-driven; clamps numbers, validates dropdown values, parses `r g b [a]` for colors. On invalid string values, surfaces the option list — and if the schema row carries `valueGate`, also reports the gating sibling and its current value (e.g. `units.target.castbar.growDirection` reporting that the option list depends on `units.target.castbar.orientation = VERTICAL`). |
| `reset <path>` | Reset **one setting** to its default. | `LibKa0s-Slash-1.0`'s `CliReset`, through the host's `SetAndRefresh` write seam. **Breaking change:** this used to take a page (`general`/`icons`/`castbar`/`label`/`spells`). A page is a property of a settings panel, not of the data, so page-scoped reset now lives only on each panel's **Defaults** button, and the every-spec spell rebuild moved to `/kcd spells resetall`. Each retired page name is answered with a line naming its replacement rather than a bare "Setting not found". |
| `resetall` | Reset every schema-driven panel **and** every spec's spell list. | Calls `Helpers.ResetAll`, the same helper behind General → "Reset all settings" popup. No CLI confirmation. |
| `resetposition` | Restore the icon grid to its default screen position. | Calls `Helpers.ResetIconPosition`. |
| `spells <subcmd>` | Per-class+spec spell-list editor (CLI parity for the Spells panel). | See subtable below. |
| `debug <subcmd>` | Diagnostic subcommands. | See subtable below. |

`list`, `get`, and `set` gain new entries automatically as schema rows are added — see [settings-panel.md](settings-panel.md). Adding a regular command is a one-row append; help text is generated from the same rows that drive dispatch.

## `/kcd spells <subcmd>`

Edits the per-class+spec spell list at `db.profile.spells[CLASS][specID]`. CLASS is the upper-case class file token (`WARRIOR`, `DEATHKNIGHT`, …); the stored spec key is Blizzard's **numeric** specialization ID (see `Const.SPEC` in `core/Constants.lua`), matching the keys in `defaults/Spells.lua`.

At the command line SPEC is still typed as a name: `Util.ResolveSpecID` accepts the English token (`ELEMENTAL`), the spec name in the client's own language (`Élémentaire`), or the raw ID, resolving against the given class so names shared by several classes (`FROST`, `HOLY`, `PROTECTION`, `RESTORATION`) are unambiguous. Output always echoes the English token so a pasted bug report reads identically in every locale. Every subcommand accepts an optional trailing `[CLASS SPEC]`; when omitted, both default to the player's current class+spec.

| Subcommand | Purpose |
|---|---|
| `list [CLASS SPEC]` | Print the watched list with index, spell ID, name, category, and disabled flag. |
| `add <id\|name> [CLASS SPEC]` | Append a spell. Re-enables an existing entry rather than duplicating. Accepts spell name as well as ID. |
| `remove <id> [CLASS SPEC]` | Drop a spell from the list. |
| `enable <id> [CLASS SPEC]` / `disable <id> [CLASS SPEC]` | Flip the entry's `enabled` flag. |
| `category <id> <cat> [CLASS SPEC]` | Re-categorize an entry. Allowed: `interrupt`, `stun`, `knockback`, `incapacitate`, `silence`, `root`, `fear`, `displace`, `racial`, `other`. |
| `reset [CLASS SPEC]` | Rebuild one `(CLASS, SPEC)` list from `NS.DefaultSpells`. Mirrors the Spells panel's Defaults popup; intentionally narrower than `/kcd spells resetall` (which wipes every spec via `Database:ResetAllSpells`). |

Every mutating subcommand fires `Ka0s_KickCD_CONFIG_CHANGED { section = "spells" }`. The Spells panel subscribes to that message in `ensurePanel` and re-renders rows when it arrives, so the open editor stays in sync after a CLI write — no direct cross-module call from the slash dispatch into the panel module.

## `/kcd debug <subcmd>`

| Subcommand | Purpose |
|---|---|
| `window` | Toggle the on-screen debug console window — the DIALOG-strata "Ka0s KickCD — Debug" panel (`modules/DebugLog.lua`) with a ScrollingMessageFrame, Copy/Clear buttons, a header Debug:ON/OFF toggle, and the shipped JetBrains Mono font. This is where continuous `NS.Debug(tag, fmt, ...)` output lands (gated on `NS.State.debug`), not the chat frame. |
| `on` / `off` / `toggle` | Set / clear / flip the session-only debug flag `NS.State.debug` via the single write seam `DebugLog:SetEnabled(on)`. Default off; never persisted to SavedVariables; resets each `/reload`. |
| `spells` | Dump the watched cooldown list (`Cooldowns:DebugDump`), printed to chat. Prints `ready / active / cdObj / chargeCdObj / charges` per spell. Charges are `safeStr`-ed because they're secret-tainted in combat for charged spells; remaining time is deliberately not printed (`:GetRemainingDuration()` is secret in combat). |
| `castbar` | Print (to chat) one unit's current cast state plus configured/live per-state colors and `notInterruptible`'s type/secret flag (`Castbar:DebugDump(unit)`, defaulting to `target`). Uses `type()` and `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error the dump. |
| `interrupt` | Dump (to chat) `UnitCastingInfo` / `UnitChannelInfo` positions with their `type` and `issecretvalue()` flag, plus what `NS.State.IsHostileUnitCasting` and the addon-wide visibility/glow logic decided. The reference for diagnosing 12.0 secret-value handling drift (added during the visibility-mode rework). |
