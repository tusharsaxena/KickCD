# Debug surfaces

KickCD has two kinds of debug output, and they go to two different places:

- **The debug console** is `LibKa0s-DebugLog-1.0`'s window. Continuous, tagged `NS.Debug` lines land
  there while the session flag is on.
- **The four chat dumps** are one-shot snapshots printed to the chat frame through `NS.Util.print`,
  each on the cyan `[KCD]` banner. They run whether the debug flag is on or off.

The dumps are the reason this page exists (`documentation-§3`, Tier 2: debug surfaces beyond the
LibKa0s default console). The console itself is the library's, and its contract lives in LibKa0s's
[`docs/api/DebugLog/version-13-docs.md`](https://github.com/tusharsaxena/LibKa0s/blob/master/docs/api/DebugLog/version-13-docs.md)
(minor 13 is the vendored one). This page covers only what KickCD adds on top.

## The console

| Command | Effect |
|---|---|
| `/kcd debug` | Toggles the console window and prints the `/kcd debug` verb list. |
| `/kcd debug window` | Toggles the console window: "Ka0s KickCD — Debug", `KickCDDebugWindow`. |
| `/kcd debug on` / `off` / `toggle` | Sets, clears or flips the debug flag through `DebugLog:SetEnabled`, and confirms on one chat line. |

What KickCD supplies, all in `core/DebugLogSetup.lua`:

- **The flag is ours, and session-only.** It is `NS.State.debug`: off at login, never written to
  SavedVariables, and reset by every `/reload`. There is no schema row for it. The General page's
  "Debug console" checkbox shows and hides the window; it does not set the flag.
- **The buffer is the library's 1500 lines** (`lib.MAX_BUFFER`). The copy window pastes out of it,
  so a long capture keeps only its newest 1500 lines.
- **The `[Init]` line** opens a session when the flag goes on:
  `KickCD v<version>, schema v<n>, profile '<name>'`. When this client refused an event name it adds
  `, N rejected event(s)`; `/kcd debug events` lists them.
- **The sink is `NS.Debug(tag, fmt, ...)`**, bound bare to the library's gated `Debug`. A call with
  the flag off does nothing and allocates nothing.

On a load without LibKa0s the flag still works and `on` / `off` still confirm. The window is gone,
and the stub says so once. It renders no line of its own (`debug-logging-§3`).

### Tags in use

| Tag | Emitted by | What it logs |
|---|---|---|
| `Init` | `core/DebugLogSetup.lua`, `core/Database.lua` | The session summary; the color and font-flag migrations |
| `Migrate` | `core/Database.lua` | The spell-list spec-key migration (each resolved, unresolved or colliding entry), and a migration step that raised |
| `Set` | `settings/SchemaSetup.lua`, `core/Database.lua` | Every schema write (`<path> = <value>`, debounced), bulk-reset brackets, profile reset and copy |
| `Profile` | `core/Database.lua` | Profile switches |
| `Spells` | `core/Database.lua`, `core/SpellInput.lua`, `settings/Spells.lua` | Spell-list edits and resets, and a skipped cooldown-manager check |
| `Cooldowns` | `modules/Cooldowns.lua` | Each watched-list rebuild (watched and skipped counts) and material state changes |
| `IconGrid` | `modules/IconGrid.lua` | Visibility decisions per unit; duplicate spell IDs skipped |
| `Cast` | `modules/IconGrid.lua` | The interruptible cast gate per unit |
| `Combat` | `core/State.lua` | Entering and leaving combat |
| `Open` | `core/KickCD.lua` | The settings panel opening |
| `Events` | `core/CoreSetup.lua` | Each event name the client refused to register |
| `Launcher` | `core/LauncherSetup.lua` (forwarded from the library's launcher) | Launcher registration (or the missing library that skipped it) and the minimap button shown or hidden |
| `Cfg` | `settings/OptionsSetup.lua` (forwarded from the library's options panel) | The settings panel opening and registering, including an open refused or a register parked in combat |

A new tag is a one-word string at the call site. Add its row here in the same change.

## The four chat dumps

Each dump prints to chat whether or not the console is on. None of them `tostring`s or formats a
value that may be secret in combat: they print a value's `type()`, its secret flag, or the shared
`<secret>` placeholder (`NS.SafeToString`) instead. See [midnight-quirks.md](midnight-quirks.md) for
why that matters.

### `/kcd debug spells`

`Cooldowns:DebugDump` (`modules/Cooldowns.lua`). It prints a header,
`Cooldowns: class=<TOKEN> spec=<SPEC> (<specID>)`, then one line per watched spell, sorted by ID:
`[id] name ready= active= cdObj= chargeCdObj= charges=`. `cdObj=yes` means a full-cooldown duration
object is held. `chargeCdObj=yes` means a charge is recharging while the spell is still castable.
Remaining time is deliberately left out, because `:GetRemainingDuration()` is secret in combat.

**Use it when** an icon is missing, stuck ready or stuck on cooldown. It shows what the tracker
actually watches for the player's class and spec, as against what the Spells page lists. A spell the
page lists but the dump lacks was filtered at rebuild; the `Cooldowns` rebuild line in the console
says why.

### `/kcd debug castbar`

`Castbar:DebugDump` (`modules/Castbar_Debug.lua`), always on `target` from the slash command. It
prints the unit's name, whether it is the player, and whether it can be attacked. If no cast is
tracked, it says so, and flags a record that `Compat.GetCastingInfo` still returns, since that
points to a missed event. With a cast tracked it prints `isChannel`, `notInterruptible`'s type and
secret flag (and how the bar resolved it), the types of `duration`, `texture`, `spellID` and `name`,
the per-state colors the profile holds, and the colors actually live on the two status bars.

**Use it when** the cast bar shows the wrong color or border, or stays hidden while the target is
visibly casting. Configured and live colors disagreeing means a write did not reach the reskin.

### `/kcd debug interrupt`

`Compat.DebugInterrupt` (`core/Compat.lua`), on `target`. It prints every positional return of
`UnitCastingInfo` and `UnitChannelInfo` with its `type()` and secret flag, rendered through
`safeRender`. Then it prints what `NS.State.IsHostileUnitCasting` decided, the addon-wide
visibility mode, and the primary and secondary glow triggers.

**Use it when** the `target_casting_interruptible` visibility mode or an interrupt glow misbehaves,
or when a client patch may have moved or newly secreted a cast-info position. It is the reference
dump for 12.0 secret-value drift.

### `/kcd debug events`

The `events` row in `core/KickCD.lua`. It prints one `rejected event: <NAME>` line per event name
this client refused to register this session, or `no rejected events`. The list is
`NS.State.rejectedEvents`, filled by `NS.RegisterEventList` (`core/CoreSetup.lua`) through
LibKa0s-Core's `SafeRegisterEvent`. A refused name costs only its own row of a registration block
(`events-frames-taint-§1`).

**Use it when** the `[Init]` line reports rejected events, or when a feature goes quiet after a
client patch that may have retired an event it listens to.

## Where else this is pinned

The command rows are in [slash-dispatch.md](slash-dispatch.md#kcd-debug-subcmd). The chat-output
checks for all four dumps (sub-header color, the `[KCD]` banner) are described in
[testing.md](testing.md). The suites are `tests/test_debuglog.lua`, `tests/test_debuglogsetup.lua`,
`tests/test_castbar_debug.lua`, `tests/test_compat_debug.lua` and `tests/test_events.lua`.
