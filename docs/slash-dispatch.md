# Slash dispatch

Three ordered tables in `core/KickCD.lua` drive the entire slash UX:

- `COMMANDS` — top-level subcommands.
- `DEBUG_COMMANDS` — `/kcd debug ...`.
- `SPELLS_COMMANDS` — `/kcd spells ...`.

`/kickcd` and `/kcd` are both registered via `RegisterChatCommand` and dispatch to the same `OnSlashCommand` handler — `/kickcd` is the long-form alias, all help text and docs use the short form.

Each row is `{ name, description, fn }`. The dispatcher:

- Bare `/kcd` (empty or whitespace-only) → runs the `config` row, which opens the settings panel on its landing page (slash-commands-§4). The library-absent stub in `settings/Slash.lua` does the same.
- `/kcd help` → `printHelp` (iterates `COMMANDS`).
- `/kcd <known>` → executes that row's `fn`.
- `/kcd debug` → `runDebug("")` toggles the on-screen debug console window (`DebugLog:Toggle`) **and** prints the verb list for `DEBUG_COMMANDS`.
- `/kcd debug <known>` → executes that row's `fn`.
- `/kcd spells` → `runSpells("")` prints the help index for `SPELLS_COMMANDS` plus the player's resolved class/spec defaults.
- `/kcd spells <known>` → executes that row's `fn`.
- `/kcd <unknown>` → "unknown command" + help.
- `/kcd options` is aliased to `/kcd config` for backward compat.

`/kcd config` (and the `OpenSettings()` API behind `NS:OpenSettings`) lands the user on the **Ka0s KickCD parent page** (logo + slash-command list) with the subcategory tree expanded in the left nav so all six sibling pages (General / Icons / Cast bar / Text Label / Spells / Profiles) are visible. Implementation: `NS:OpenSettings` delegates to `NS.OpenOptionsPanel`, the `settings/OptionsSetup.lua` forwarder onto LibKa0s-Options-1.0's `O.OpenOptionsPanel`. The `Settings.OpenToCategory` call, the category-ID lookup and the defensive tree expansion (`SettingsPanel:GetCategoryList():GetCategoryEntry(main):SetExpanded(true)`, wrapped in `pcall` because those are Blizzard private API) all live there. This addon used to carry a line-for-line second copy of that path against its own private page registry, plus a three-attempt, 0.5s-apart retry for the race between `/kcd config` and the `PLAYER_LOGIN`-deferred `RegisterPanel`; both went with the registry (KCD-A-09) — registration is synchronous in `OnEnable` now, so there is nothing left to race. The combat-lockdown check stays in `OpenSettings` itself (not the `/kcd config` callback) so every entry point — slash, a `/run` script, any future caller — shares the gate, and it short-circuits ahead of the library's own refusal because this one is localized; it prefers `NS.State.inCombat` (the regen-event flag, which leads `InCombatLockdown()` by a frame) and falls back to `InCombatLockdown()` only when `core/State.lua` hasn't loaded yet. On a hit the user gets a one-line `L["Cannot open settings during combat."]` print and nothing downstream runs.

`OnSlashCommand` lowercases only the command name and preserves case in the rest of the input, so schema paths like `units.target.icons.primarySize` survive unchanged through `/kcd set ...`. `runDebug` and `runSpells` lowercase their own subcommand for backward compat.

## Chat output

Every chat line emitted by the addon flows through `Util.print` — `LibKa0s-Core-1.0`'s secret-safe printer, published at `NS.Util.print` by `core/CoreSetup.lua` — which prepends a single cyan `|cff00ffff[KCD]|r` banner. Call sites pass plain text — they don't include their own prefix. The help printers (`printHelp`, `runDebug`'s no-arg branch, `runSpells`'s no-arg branch) wrap each row's invocation in `|cffffff00…|r` (yellow) and the description in `|cffffffff…|r` (white) so the slash command and its explanation are visually distinct in chat. The schema-error path in `settings/Panel.lua` also routes through `Util.print` so it shares the `[KCD]` banner; only the inner `schema error:` token is colored red.

## The disabled state: the gate is the library's, the judgment is ours

`slash-commands-§7` makes *disabled* **total** — every registration actually unregistered, every
timer canceled, every frame hidden at the source, nothing written from a game event. That half is
[ARCHITECTURE.md → The stand-down](ARCHITECTURE.md#the-stand-down-disabled-is-total). This section is
the other half: what the **command surface** does while the addon is off.

**It does not narrow.** Every reserved verb answers normally — `help`, `config`, `version`,
`enable`, `disable`, `debug`, `perf` and the whole schema CLI `get` / `set` / `list` / `reset` /
`resetall` — and the bare `/kcd` opens the settings panel exactly as it does when the addon is
running. A player must be able to read and repair settings, and reach the panel, while the addon is
off, which is precisely when they are most likely to need to; and `enable` above all, or the switch
only goes one way. The dispatcher and the settings registration are **setup, not features**: they
come up on load in either state.

> The standard narrowed this surface to `enable` and `help` at v2.56.0 and **reversed it at
> v2.57.0**, the same day. It failed on the first thing anyone tried: `/kcd` on a disabled addon
> answered with a refusal instead of opening the panel — the one surface a player uses to switch it
> back on by hand. The round trip is recorded rather than erased, upstream and here.

**The one refusal is `slash-commands-§2`'s SHOULD**, and this addon takes it: a verb that *drives
the addon's features* answers on **one** tagged line naming `/kcd enable` and does nothing else.

**The gate is no longer this addon's code.** `LibKa0s-Slash-1.0` carries it (minor 14, vendored at v1.42.0):
`settings/Slash.lua` passes `isEnabled` (asked at dispatch time, never cached, so the command after
an `enable` works) and `brandName`, and the dispatcher refuses the host's own feature verbs *after*
the `COMMANDS` lookup. That ordering is a behavior the host-side wrapper this replaced never got
right: a **typo** is not a refusal — nothing was refused, the addon genuinely did not understand —
so a misspelling still gets `unknown command '<verb>'` and the index.

The **refusal line is the collection's, not this addon's**: one sentence, built by the library from
`lib.DISABLED_LINE_FORMAT`, the brand name and the slash. There is no locale key for it here and a
descriptor `L` override deliberately does not reach it. The launcher's refused left click prints
**that same line**, through `NS.Slash.PrintDisabledLine`, rather than a second copy of it.

The **live set** is a union, built in `settings/Slash.lua` and never a typed copy:

* the library's twelve, which are the standard's reserved verbs. A host MUST NOT refuse any of them,
  and building from `lib.LIVE_VERBS` means a thirteenth arriving in a future LibKa0s tag is live the
  day it is vendored rather than silently refused;
* **plus `spells`, which is this addon's own call** (`NS.EXTRA_LIVE_VERBS`, `core/KickCD.lua`). The
  per-spec spell lists are stored **arrays**: an array is addressable as a whole while its members
  deliberately are not, so no schema row covers them and `get` / `set` / `list` / `reset` cannot
  reach them at all. `/kcd spells` is their only CLI route, which makes it the schema CLI for that
  data rather than a feature verb. It configures; it does not drive.

What is left refuses: **`lock`, `unlock`, `toggle`** — the preview switch, since `launcher-§2` puts
KickCD on rung (b) because unlocking *is* this addon's preview, and with the addon off there is no
grid to unlock — and **`resetposition`**, which re-anchors the grids, fires `CONFIG_CHANGED` so the
live grids move, and then echoes *icon grid positions reset* at a player who can see no grid.

`isEnabled` reads `NS.MasterEnabled()` (`core/LifecycleSetup.lua`), which is the addon's **one**
reader of `db.profile.enabled` — the same function the stand-down latch takes its hold from, so the
gate and the teardown can never disagree about whether the addon is on. It defaults to true on a
missing profile, because the `enabled` row is **composed** and a load without LibKa0s has no row to
resolve; a gate that silently refused every feature verb on that load would be worse than the
failure it guards against.

Pinned by `tests/test_slash.lua` and, end to end with the stand-down, by `tests/test_disabled.lua`.

## Degraded verbs: a load without LibKa0s

`/kcd` is registered unconditionally, so a load whose `libs/LibKa0s/` is missing still answers it,
through the degradation stub at the top of `settings/Slash.lua`. Its shape is the one
`slash-commands-§1` (standard v2.65.0, WS-02) and `LibKa0s-Slash-1.0`'s version-15 document ("The
degradation stub") prescribe:

* **Minimal dispatch, with the same gate.** Bare `/kcd` runs `config`; a known verb runs its row; an
  unknown one gets `unknown command '<verb>'` and a plain help list. While the addon is disabled, a
  verb outside the descriptor's `liveVerbs` is refused with `DisabledLine`, exactly as on the live
  load.
* **One library string, verbatim and pinned.** The stub carries `DISABLED_LINE_FORMAT`'s bytes as a
  local, exposed as `NS.Slash.cli.__disabledLineFormat` (the `__` prefix keeps it outside the
  surface-parity gate), and `tests/test_slash.lua` pins it with `Kit.assertLibraryConstant`. The
  degraded `DisabledLine` is therefore the live line, brand and `/kcd enable` included, and
  `NS.Slash.PrintDisabledLine` prints it on this load too. The gate also needs the standard's
  reserved verbs, which the library publishes as `lib.LIVE_VERBS` and this load cannot read, so the
  stub carries that array too, exposed as `__reservedVerbs` and pinned element for element against
  the live array. Without it `/kcd enable` would be refused while disabled.
* **No formatter, parser or key/value copy.** Help rows render plainly (`/kcd <verb> — <desc>`).
* **Composed-row verbs take route (a).** `enable` / `disable` still dispatch into `/kcd set
  enabled <bool>`. The stub's `CliSet` accepts a path on `NS.Settings.WRITE_THROUGH` (`enabled`,
  `locked`) with a bool literal (`true` / `false` / `on` / `off`), writes it through the Schema stub's
  `Store.Set`, and echoes `<path> = <bool>`. The Schema announce takes the disabled hold on an
  `enabled` write, so `disable` stands the addon down and `enable` brings it back. `lock` / `unlock`
  / `toggle` write `locked` through `Store.Set` in `setLocked` and confirm as usual.
* **Everything else prints the library-absent line.** `list`, `get`, `reset`, `resetall`, and `set`
  for any other path or value, print the one sentence `slash-commands-§1` fixes, through the locale:
  `/kcd list is unavailable: the LibKa0s library did not load.` Nothing is written and nothing
  raises.

Pinned on a real library-less load (`T.load(..., { libFiles = {} })`) by `tests/test_slash.lua`,
`tests/test_disabled.lua` and `tests/test_options_panel.lua`.

## Top-level commands

| Command | Purpose | Notes |
|---|---|---|
| `help` | Print the help index. | Iterates `COMMANDS`. |
| `version` | Print the addon version. | `v<X.Y.Z>` from `C_AddOns.GetAddOnMetadata` with the `NS.VERSION` stamp as fallback (slash-commands-§3). |
| `config` | Open the settings panel. | Combat-gated; lands on the parent page with the subcategory tree expanded in the left nav. |
| `enable` / `disable` | Turn the addon on / off. | **Reserved aliases** (`slash-commands-§2`), never a second switch. Both dispatch into `setSetting(NS, "enabled <bool>")` — which IS `/kcd set` — so they write the Master-controls `Enable KickCD` row's own stored path through the same single write seam the checkbox writes through (`options-ui-§1`), run the same `onChange`, and get §5's `set` confirmation line for free. They hold **no state of their own**: no second key, no session flag, no `NS.enabled`. `/kcd` and every verb on the live set keep working while the addon is **disabled** — `RegisterChatCommand` is unconditional in `OnInitialize` and nothing tears down `COMMANDS` or the dispatcher, so the pair is never one-way. Pinned by `tests/test_launcher.lua` and `tests/test_slash.lua`. |
| `lock` / `unlock` / `toggle` | Set / clear / flip `db.profile.locked`. | **Refuses while the addon is disabled** (see above). Writes through the schema seam, `NS.Settings.Store.Set("locked", ...)`, then `Helpers.RefreshScalars` when a panel exists — the same two steps `Helpers.SetAndRefresh` takes for the General → "Lock frame" checkbox — so the checkbox repaints and any onChange wired onto the schema row fires. A LibKa0s-less load composes no `locked` row, and `locked` is on the seam's `writeThrough` list (`settings/SchemaSetup.lua`, `options-ui-§1` route (a)), so the degraded stub still stores it ([Degraded verbs](#degraded-verbs-a-load-without-libka0s)). Only when there is no `Store` at all does it print "Settings layer not ready yet" and write nothing; there is no direct-write fallback. `toggle` is published as **`NS.ToggleLock`**, because the minimap button's left click is its second caller — `launcher-§2` rung (b) drives the addon's EXISTING preview switch through the same seam rather than holding a copy of it. |
| `list` | Dump every schema-driven setting grouped by panel, with current values. | Schema-driven. |
| `get <path>` | Print one setting's current value. | Schema-driven; the descriptor's `findRow` and `get` are the schema seam's `Store.FindRow` and `Store.Get`. |
| `set <path> <value>` | Type-aware write to one setting. | Schema-driven; clamps numbers, validates dropdown values, parses `r g b [a]` for colors, then writes through `Helpers.SetAndRefresh` (`Store.Set`). A path no schema row declares is refused and never stored (`Setting not found: <path>`), and a refusal the seam answers with `false, err, why` is printed instead of an echo (LibKa0s-Slash-1.0 minor 15). On invalid string values, surfaces the option list — and if the schema row carries `valueGate`, also reports the gating sibling and its current value (e.g. `units.target.castbar.growDirection` reporting that the option list depends on `units.target.castbar.orientation = VERTICAL`). |
| `reset <path>` | Reset **one setting** to its default. | `LibKa0s-Slash-1.0`'s `CliReset`, through the schema seam's `Store.ApplyDefault` (outside any bulk bracket, so `/kcd reset global.minimap.shown` still resets the one row every sweep leaves alone). **Breaking change:** this used to take a page (`general`/`icons`/`castbar`/`label`/`spells`). A page is a property of a settings panel, not of the data, so page-scoped reset now lives only on each panel's **Defaults** button, and the every-spec spell rebuild moved to `/kcd spells resetall`. Each retired page name is answered with a line naming its replacement rather than a bare "Setting not found". |
| `resetall` | Reset the **active profile** to the shipped defaults — panels, anchors, `link` flags and every spec's spell list, all of which live in the profile (`options-ui-§12`). | Calls `Helpers.ResetAll`, the same helper behind the General → "Reset all settings" popup, which is now one `db:ResetProfile()`. No CLI confirmation. |
| `resetposition` | Restore the icon grids to their default screen positions. | **Refuses while the addon is disabled** (see above). Calls `Helpers.ResetIconPosition`. |
| `spells <subcmd>` | Per-class+spec spell-list editor (CLI parity for the Spells panel). | See subtable below. |
| `debug <subcmd>` | Diagnostic subcommands. | See subtable below. |
| `perf [args]` | Guided A/B performance capture. | `LibKa0s-Perf-1.0`'s (`core/PerfSetup.lua`), driven from a clickable step panel; records persist in the `KickCDPerfDB` saved variable. `perf` is a **reserved verb across the collection** (slash-commands-§2) and must be registered by the addon, never the library: `NS.Perf.OnCommand(rest)` returns lines and `core/KickCD.lua` prints them through the tagged printer. |

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
| `reset [CLASS SPEC]` | Rebuild one `(CLASS, SPEC)` list from `NS.DefaultSpells`, plus the player's racial cast-stopper when it is their own class, through `Database:ResetSpellList`, the same verb the Spells panel's Defaults popup calls. Intentionally narrower than `/kcd spells resetall` (which wipes every spec via `Database:ResetAllSpells`). |

Every mutating subcommand fires `Ka0s_KickCD_ConfigChanged { section = "spells" }`. The Spells panel subscribes to that message in `ensurePanel` and re-renders rows when it arrives, so the open editor stays in sync after a CLI write — no direct cross-module call from the slash dispatch into the panel module.

## `/kcd debug <subcmd>`

| Subcommand | Purpose |
|---|---|
| `window` | Toggle the on-screen debug console window — the DIALOG-strata "Ka0s KickCD — Debug" panel (`LibKa0s-DebugLog-1.0`, wired in `core/DebugLogSetup.lua`) with a ScrollingMessageFrame, a title-bar trio of `copy` / `clear` / `close` marks from the shared LibKa0s icon set, a header Debug:ON/OFF toggle, and the JetBrains Mono face that ships in the vendored LibKa0s payload. This is where continuous `NS.Debug(tag, fmt, ...)` output lands (gated on `NS.State.debug`), not the chat frame. |
| `on` / `off` / `toggle` | Set / clear / flip the session-only debug flag `NS.State.debug` via the single write seam `DebugLog:SetEnabled(on)`. Default off; never persisted to SavedVariables; resets each `/reload`. |
| `spells` | Dump the watched cooldown list (`Cooldowns:DebugDump`), printed to chat. Prints `ready / active / cdObj / chargeCdObj / charges` per spell. Charges are `safeStr`-ed because they're secret-tainted in combat for charged spells; remaining time is deliberately not printed (`:GetRemainingDuration()` is secret in combat). |
| `castbar` | Print (to chat) one unit's current cast state plus configured/live per-state colors and `notInterruptible`'s type/secret flag (`Castbar:DebugDump(unit)`, defaulting to `target`). Uses `type()` and `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error the dump. |
| `interrupt` | Dump (to chat) `UnitCastingInfo` / `UnitChannelInfo` positions with their `type` and `issecretvalue()` flag, plus what `NS.State.IsHostileUnitCasting` and the addon-wide visibility/glow logic decided. The reference for diagnosing 12.0 secret-value handling drift (added during the visibility-mode rework). |
| `events` | List (to chat) every event name this client refused to register this session, one `rejected event: <NAME>` line each, or `no rejected events`. The list is `NS.State.rejectedEvents` (session-only), filled by `NS.RegisterEventList` (`core/CoreSetup.lua`) through LibKa0s-Core's `SafeRegisterEvent`, so one retired name costs only its own row of a registration block (events-frames-taint-§1). A non-empty list also adds `, N rejected event(s)` to the debug console's `[Init]` line. |
