# Debug surfaces

KickCD has three kinds of debug output:

- **The debug console** is `LibKa0s-DebugLog-1.0`'s window. Continuous, tagged `NS.Debug` lines land
  there while the session flag is on.
- **The diagnostics report**, `/kcd diagnostics`, is one structured snapshot of the addon's state,
  appended to the same console after whatever trace is already there. It is what a bug report
  carries (`debug-logging-§14`).
- **The four debug topics** (`/kcd debug spells`, `castbar`, `interrupt`, `events`) are narrower
  one-shot snapshots printed to the chat frame through `NS.Util.print`, each on the cyan `[KCD]`
  banner. They run whether the debug flag is on or off. The first three are also sections of the
  report.

The report and the topics are why this page exists (`documentation-§3`, Tier 2: debug surfaces
beyond the LibKa0s default console). The console and the report's frame are the library's, and
their contract lives in LibKa0s's
[`docs/api/DebugLog/version-14.1-docs.md`](https://github.com/tusharsaxena/LibKa0s/blob/master/docs/api/DebugLog/version-14.1-docs.md)
(DebugLog minor 14 with its diagnostics file at minor 1, as vendored at LibKa0s v1.60.0). This page
covers only what KickCD adds on top.

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
- **The buffer is the library's** (`lib.MAX_BUFFER`, 3000 lines at LibKa0s v1.60.0). The copy
  window pastes out of it, so a long capture keeps only its newest lines. Nothing in this addon sets
  or repeats the number.
- **The `[Init]` line** opens a session when the flag goes on:
  `KickCD v<version>, schema v<n>, profile '<name>'`. When this client refused an event name it adds
  `, N rejected event(s)`; `/kcd debug events` lists them, and so does the report's `events` section.
- **The sink is `NS.Debug(tag, fmt, ...)`**, bound bare to the library's gated `Debug`. A call with
  the flag off does nothing and allocates nothing.
- **The report's brand and sections.** The descriptor's `brandName` is `Ka0s KickCD`, which both
  report markers carry, and its `diagnostics` field hands the library `NS.Diagnostics.Sections()`
  (`modules/Diagnostics.lua`), resolved each time a report runs rather than at load.

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

A new tag is a one-word string at the call site. Add its row here in the same change. The report's
own tags are listed with its sections below; the report writes them through the ungated append, not
through `NS.Debug`.

## `/kcd diagnostics`: the report (`debug-logging-§14`)

Run it **after** reproducing the problem, not before. It is appended below whatever the console
already holds, so the trace you just produced and the state it left behind travel in one **Copy**.
That is what the README's *Reporting a bug* steps do.

**Two forms, no third.** `/kcd diagnostics` and `/kcd debug diagnostics` (either case, and through
`/kickcd` as well as `/kcd`) are the same call. The first is its own `diagnostics` row in
`NS.COMMANDS` (`core/KickCD.lua`); the second is tested in `runDebug` before every other `debug`
word and before the bare toggle. Both end in `NS.DebugLog:RunDiagnostics()`. There is no `diag`,
`dump` or `dx` alias: `/kcd diag` gets the library's `unknown command 'diag'` line and the help
index, and `/kcd debug diag` is an ordinary unknown `debug` word, answered like any other (the
unknown-word line, then the bare `/kcd debug` toggle and verb list).

**What it does to the console.** It writes through the library's raw append, not the gated sink
`NS.Debug`, so it lands in full with logging **off**, and it never changes the logging flag beyond
printing it. It never clears the console, and it shows the console if it was hidden. Then it prints
one chat line: *Diagnostic report written to the debug console: N lines. Use Copy to share it.*
`debug` and `diagnostics` are both reserved verbs (`slash-commands-§2`) on the library's live set,
so both forms answer while the addon is **disabled**.

**The shape.** The library writes the frame; `modules/Diagnostics.lua` writes the sections, in this
order. The markers and the identity header carry the `[Diag]` tag; each section's lines carry the
tag shown.

| Part | Tag | Written by | What it holds |
|---|---|---|---|
| Begin marker | `Diag` | the library | `==== Ka0s KickCD diagnostics begin ====` |
| Identity header | `Diag` | the library | The `[Init]` summary line, the client version, build, date and interface, the locale, the debug flag, the two combat reads, and every LibKa0s file **running** in the client with its minor (running, because under LibStub another addon's newer copy may be the one loaded) |
| `state` | `State` | this addon | **Lifecycle first**: the stored `enabled`, whether the latch has stood the addon down, the Lifecycle holds; the schema version stored and in code; the profile and `locked` (unlocked is the placement preview); `State.inCombat` and the viewed unit |
| `settings` | `Set` | this addon | Every schema row that differs from its default as `path = value (default)`, plus the always-print rows whatever their value: `enabled`, `locked`, `visibility`, `scale`, `alpha`, `units.focus.link`, and per unit its `enabled`, both glow triggers and the cast bar's `enabled`, orientation, grow direction, auto-size and anchor mode. Then how many rows printed |
| `units` | `Units` | this addon | Per unit: stored enable, linked, and whether it is wanted now |
| `spells` | `Spells` | this addon | The class and spec, the current spec's list with `off` on a disabled row and `unlearned` on a spell the player does not know, and how many stored lists exist and how many differ from their defaults |
| `cooldowns` | `Cooldowns` | this addon | The `/kcd debug spells` dump, routed into the report |
| `cmcache` | `CMCache` | this addon | The Cooldown Manager cache's state and its spell count, read from the memo |
| `icongrid` | `IconGrid` | this addon | Per unit: enabled, shown, active and free icons, laid-out count, handle; the saved anchor against the live one; the last visibility decision and the cast gate |
| `castbar` | `Castbar` | this addon | Per unit: enabled, shown, casting; the anchor mode and the saved anchor against the live one; then the `/kcd debug castbar` dump for that unit |
| `interrupt` | `Interrupt` | this addon | The `/kcd debug interrupt` dump, once for `target` and once for `focus` |
| `unitlabel` | `UnitLabel` | this addon | Per unit: show, text, attach point, shown |
| `events` | `Events` | this addon | `rejected events: <names>`, or `rejected events: -` when there are none |
| `perf` | `Perf` | this addon | Whether a perf capture is running and whether it is suspended |
| `truncated` line | `Diag` | the library | Only when a cap bit: `truncated: N line(s) omitted, per-list caps hit=yes/no` |
| End marker | `Diag` | the library | `==== Ka0s KickCD diagnostics end: N line(s) ====`, counting both markers |

**The topics are reused, not copied.** `Cooldowns:DebugDump(emit)`, `Castbar:DebugDump(unit, emit)`
and `Compat.DebugInterrupt(unit, emit)` take an optional line sink. The slash topics pass none, so
their lines go to chat; the report passes one that writes into the report under the section's tag.
One dump backs both surfaces, so they cannot drift apart.

**Reading it.** Start with `state`. `stood down=true` means the addon is off, and the runtime
sections below it say so rather than describe released machinery. Then:

- An icon missing, stuck ready or stuck on cooldown: compare `spells` (what the list holds, and
  whether the spell is `off` or `unlearned`) with `cooldowns` (what the tracker actually watches).
  A spell in the first and not the second was filtered at rebuild.
- A grid or cast bar in the wrong place: the `anchor saved=… live=…` lines. `live=not built` means
  no frame exists for that unit.
- A grid or bar that never shows: `units` (`wanted=false`), then the `icongrid` last-visibility and
  cast-gate line, then `interrupt` for what the client returned.
- A wrong cast bar color: the configured and live colors at the end of that unit's `castbar` lines.

**Stood down.** While the addon is disabled every section still runs. `cooldowns`, `icongrid`,
`castbar` and `unitlabel` each print one `stood down: …` line rather than an empty list that reads
like a bug. `state`, `settings`, `units`, `spells`, `cmcache`, `interrupt`, `events` and `perf`
print in full.

**Caps.**

- The whole report: at most `min(lib.DIAG_MAX_LINES, lib.MAX_BUFFER - 100)` lines, markers
  included. That is **1200** at LibKa0s v1.60.0 (`min(1200, 3000 - 100)`), so a full report leaves at
  least 1800 lines of trace above it in a full console. Two lines stay reserved for the `truncated`
  line and the end marker, so a capped report still ends properly. KickCD's report is far smaller:
  its suite holds it to 200 lines on a default profile.
- The spell list: 40 entries, the library's default, then `(+N more)`.
- A list line (the spell list, the rejected events, the running minors) wraps onto indented
  continuation lines at 200 characters rather than being cut.

**What it deliberately never does.** It takes or releases no Lifecycle hold, registers no event,
arms no timer, writes no setting and builds no instance or frame. Instances are read through
`PeekInstance`, never `GetInstance`; spell lists through `Database:GetSpellList`, never
`EnsureSpellList`; the Cooldown Manager set through `SpellInput.CooldownManagerCacheState`, never
`CooldownManagerSet`, which would force the category walk. The cast record is described by type
only: no cast name, texture, spell ID or `notInterruptible` value is printed, and no remaining
duration is read. Nothing compares or adds a value read from a frame or the client; frame points
and `IsShown` are read under `pcall` and printed, never compared. It calls no protected API, so it
is safe in combat. Every value reaches a line through the library's `out:add`, which stringifies it
through `SafeToString` before any format sees it, so a secret value prints as `<secret>` instead of
raising. The library runs each section under its own `pcall`, and `icongrid`, `castbar` and
`interrupt` run each unit under another, so one that raises costs exactly one line
(`section <name> failed: <err>`) and the next one still prints.

**Without LibKa0s** there is no console to write into: both forms print
`/kcd diagnostics is unavailable: the LibKa0s library did not load.` and write nothing
(`core/DebugLogSetup.lua`'s degraded arm).

Nothing is redacted: the report goes to the maintainer privately with a bug report, so it prints
what reproducing a bug needs. Report lines are English diagnostic text and do not go through `NS.L`;
the one chat line is the library's.

**Adding a section.** Write a read-only function `X.<Name>(out)` in `modules/Diagnostics.lua`, add
it to `X.Sections()` in report order, add its row to the table above, and cover it in
`tests/test_diagnostics.lua` (the section-order case names every section).

## The debug topics

Each topic prints to chat whether or not the console is on, and none of them writes to the console.
None of them `tostring`s or formats a value that may be secret in combat: they print a value's
`type()`, its secret flag, or the shared `<secret>` placeholder (`NS.SafeToString`) instead. See
[midnight-quirks.md](midnight-quirks.md) for why that matters. For a bug report, run the report
instead: it carries the first three topics for both units, and everything around them.

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

`Castbar:DebugDump` (`modules/Castbar_Debug.lua`), always on `target` from the slash command (the
report runs it for both units). It prints the unit's name, whether it is the player, and whether it
can be attacked. If no cast is tracked, it says so, and flags a record that `Compat.GetCastingInfo`
still returns, since that points to a missed event. With a cast tracked it prints `isChannel`,
`notInterruptible`'s type and secret flag (and how the bar resolved it), the types of `duration`,
`texture`, `spellID` and `name`, the per-state colors the profile holds, and the colors actually
live on the two status bars.

**Use it when** the cast bar shows the wrong color or border, or stays hidden while the target is
visibly casting. Configured and live colors disagreeing means a write did not reach the reskin.

### `/kcd debug interrupt`

`Compat.DebugInterrupt` (`core/Compat.lua`), on `target` (the report runs it for both units). It
prints every positional return of `UnitCastingInfo` and `UnitChannelInfo` with its `type()` and
secret flag, rendered through `safeRender`. Then it prints what `NS.State.IsHostileUnitCasting`
decided, the addon-wide visibility mode, and the primary and secondary glow triggers.

**Use it when** the `target_casting_interruptible` visibility mode or an interrupt glow misbehaves,
or when a client patch may have moved or newly secreted a cast-info position. It is the reference
dump for 12.0 secret-value drift.

### `/kcd debug events`

The `events` row in `core/KickCD.lua`. It prints one `rejected event: <NAME>` line per event name
this client refused to register this session, or `no rejected events`. The list is
`NS.State.rejectedEvents`, filled by `NS.RegisterEventList` (`core/CoreSetup.lua`) through
LibKa0s-Core's `SafeRegisterEvent`. A refused name costs only its own row of a registration block
(`events-frames-taint-§1`). The report's `events` section prints the same list.

**Use it when** the `[Init]` line reports rejected events, or when a feature goes quiet after a
client patch that may have retired an event it listens to.

## Where else this is pinned

The command rows are in [slash-dispatch.md](slash-dispatch.md#kcd-debug-subcmd), and the
`diagnostics` row is in its [top-level commands](slash-dispatch.md#top-level-commands). The
chat-output checks for all four topics (sub-header color, the `[KCD]` banner) are described in
[testing.md](testing.md). The suites are `tests/test_diagnostics.lua` (the report's sections,
order, budget, read-only and stood-down behavior), the kit's shared `test_diagnostics_contract.lua`
run against `/kcd`'s own dispatcher, `tests/test_disabled.lua` (both forms while disabled),
`tests/test_debuglog.lua`, `tests/test_debuglogsetup.lua`, `tests/test_castbar_debug.lua`,
`tests/test_compat_debug.lua` and `tests/test_events.lua`. The in-game checks are section 35 of
[smoke-tests.md](smoke-tests.md).
