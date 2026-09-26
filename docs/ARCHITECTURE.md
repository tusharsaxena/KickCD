# Architecture

Orient-yourself map for **Ka0s KickCD**. Tracks the player's interrupt and CC cooldowns and surfaces them on a movable icon grid, with a sibling cast bar — for both the player's target and focus unit — driven from the same drag lock and visibility mode. Target client: WoW 12.1.0 (Midnight). 12.0-aware throughout — the cast bar was originally removed at commit `59fb5c0` and re-added with explicit secret-value gating; see [scope.md](scope.md#cast-bar-removal-history).

This file is the high-level index; topic detail lives in `docs/`.

## Overview

Two UI widgets, each tracked for **two enemy units — target and focus** — sharing one configuration model:

- **Icon grid** — pooled per-spell icon buttons with per-icon ready glow (LibCustomGlow), placed by an orthogonal anchor + grow + dimensions model (13 anchor points × 8 grow directions × free row/col dims). Visual states (ready / cooldown / GCD-suppressed) drive C-side curves so the GCD-vs-real-CD filter never compares secret-tainted remaining time in Lua.
- **Cast bar** — mirrors its unit's cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration`. Stacked dual `StatusBar`s + per-state borders are alpha-curve-switched on the cast's secret `notInterruptible` bool via `C_CurveUtil.EvaluateColorValueFromBoolean`, so per-state appearance is rendered without the addon ever inspecting the protected boolean from Lua.

Both widget types render **the same player cooldowns** (the tracked spell list is player-centric, not unit-specific) against each enabled unit's own cast state — `modules/IconGrid.lua` and `modules/Castbar.lua` are per-unit **instance managers**: `instances[unit]` holds one live frame set per enabled unit (target and focus both enabled by default). Target keeps the legacy global frame names (`KickCDIconGrid`, `KickCDCastbar`); focus gets the suffixed `KickCDIconGridFocus` / `KickCDCastbarFocus`. A focus unit can **link** to target's appearance (`units.focus.link`, default on) so it mirrors target's `icons`/`castbar` styling live; position and the optional identity label stay per-unit even while linked. See [core/Units.lua](../core/Units.lua) (`NS.Units`) for the single place link resolution happens, and [schema.md](schema.md#unitsunit-shape) for the DB shape.

Both widgets honor the master enable, **plus their own unit's per-unit `enabled` toggle**, the shared lock (`db.profile.locked`), and the addon-wide visibility mode (`db.profile.visibility`: `always` / `in_combat` / `target_casting` / `target_casting_interruptible`) — **one lock and one visibility mode still cover both units**, evaluated per-unit against that unit's own cast state. The `_interruptible` mode uses a two-step gate (Show on hostile cast, alpha-mask uninterruptible via `SetAlphaFromBoolean`) because the underlying flag can't be compared in Lua under 12.0.

Each unit can also show a single configurable identity label (`units.<unit>.label`), rendered by `modules/UnitLabel.lua` — a per-unit instance manager, mirroring `IconGrid`/`Castbar`'s pattern, that owns one `FontString` per unit in a holder frame parented to `UIParent` (`KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`) and `SetPoint`-anchors it to that unit's chosen widget (`label.style.attach`: cast bar or icon grid). Only `text` stays per-unit while linked (`NS.Units.Label`); both `show` (`NS.Units.LabelShow`) and `label.style` (position, font, justify, rotation, color — `NS.Units.LabelStyle`) follow the Focus link like `icons`/`castbar` do. See [schema.md](schema.md#unitsunitlabelstyle-shape).

An on-screen debug console (`LibKa0s-DebugLog-1.0`, wired in `core/DebugLogSetup.lua`, toggled with `/kcd debug`) surfaces internal state. Debug logging is gated on the session-only `NS.State.debug` flag — it is never persisted and resets on every `/reload`. The console and the `/kcd perf` step panel are the **library's** windows and wear the **shared Ka0s window edge** (`Core.SKIN` applied by `Core.ApplySkin`: a flat 1px black outer border, a 1px light-gray highlight synthesized inside it, a gold title, a gray divider) — this addon passes neither `applySkin` nor `makeCloseButton`, so both track the library and stay identical to their counterparts in the sibling Ka0s addons. The addon's own on-screen widgets — the icon grids, cast bars and unit labels in `modules/` — are not windows and carry no Ka0s edge; their look is entirely profile-driven (`modules/Castbar_Skin.lua`, `modules/IconGrid_Render.lua`). Don't reach for `Core.SKIN` there.

## Module map

The pipeline first, then one row per subsystem naming the files it lives in and the page that
covers it. Per-file responsibilities and the AceAddon lifecycle are [module-map.md](module-map.md)'s;
the TOC order those files actually load in is [Load order](#load-order), at the foot of this page.

```
WoW events ─▶ Cooldowns:Refresh ─▶ Ka0s_KickCD_SpellState ─▶ IconGrid instances[target]:OnSpellState
                                                           └─▶ IconGrid instances[focus]:OnSpellState (if enabled)
                                                           └─▶ alpha/tint curves (C-side)
                                                           └─▶ SetCooldownFromDurationObject

PLAYER_TARGET_CHANGED / FOCUS_CHANGED ─▶ Castbar instances[unit]:Reevaluate ─▶ Compat.GetCastingInfo(unit)
UNIT_SPELLCAST_* (unit-filtered)                                             └─▶ UnitCastingDuration/UnitChannelDuration
                                                                              └─▶ ApplyState (curve-switched on secret notInterruptible)

Settings widget / slash CLI ─▶ Store.Set  ─▶ Ka0s_KickCD_ConfigChanged ─▶ IconGrid + Cooldowns + Castbar
                                              (section incl. "units" ─▶ ReconcileUnits on both)
AceDB profile change         ─▶                Ka0s_KickCD_ProfileChanged ─▶ same
IconGrid instances[unit]:Layout ─▶             Ka0s_KickCD_GridLayout { unit, ... } ─▶ Castbar instances[unit] (re-anchor / auto-size)

  AceDB (all chars share the "Default" profile; user-switchable)  ──  6-page settings panel (each schema page tab-stripped) + /kcd CLI
```

| Subsystem | Lives in | Read |
|-----------|----------|------|
| Per-module APIs + roles, TOC load order, AceAddon lifecycle | `core/`, `defaults/`, `modules/`, `settings/` | [module-map.md](module-map.md) |
| Unit identity + per-unit (target/focus) config resolution, link semantics | `core/Units.lua` | [module-map.md](module-map.md), [schema.md](schema.md#unitsunit-shape) |
| Game event → state → message → render pipeline; visibility gate; lock + anchor | `modules/Cooldowns.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua`, `core/State.lua`, `settings/Panel.lua` | [data-flow.md](data-flow.md) |
| Closed message contract (5 messages, sender/listener/payload) | every module that emits or subscribes | [message-bus.md](message-bus.md) |
| `KickCDDB` AceDB schema + `DEFAULT_PROFILE` shape + spell-list lifecycle | `defaults/Profile.lua` (the shape), `core/Database.lua` (the AceDB instance + migrations) | [schema.md](schema.md) |
| `Compat.*` spell/cast API shims + `State.*` visibility helpers (boundary) | `core/Compat.lua`, `core/State.lua` | [compat-layer.md](compat-layer.md) |
| 12.0 secret values + cast interruptibility two-step gate + frame mixin | `core/Compat.lua`, `core/State.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua` | [midnight-quirks.md](midnight-quirks.md) |
| Icon grid layout (anchor + grow + dimensions) | `modules/IconGrid.lua` | [icon-grid.md](icon-grid.md) |
| Cast bar (stacked dual widgets, Reskin/RenderCast split, anti-patterns) | `modules/Castbar.lua`, `modules/Castbar_Handle.lua`, `modules/Castbar_Skin.lua` | [castbar.md](castbar.md) |
| The settings write seam (`LibKa0s-Schema-1.0`): the row index, `Store.Set` / `SetMany`, the bulk bracket, validation, and its degradation stub | `settings/SchemaSetup.lua` | [settings-panel.md](settings-panel.md#the-write-seam-libka0s-schema-10) |
| Schema-driven canvas-layout settings panel; widget primitives | `settings/Panel.lua`, `settings/Panel_Widgets.lua`, `settings/Panel_Render.lua`, `settings/{General,Icons,Castbar,Label,Spells,Profiles}.lua` | [settings-panel.md](settings-panel.md) |
| Slash dispatch tables and command catalog | `core/KickCD.lua` | [slash-dispatch.md](slash-dispatch.md) |
| Adding a spell: the one resolver (id or name, multi-word names, validated `[CLASS SPEC]`), the Cooldown Manager gate and its cached set, shared by the Spells page and `/kcd spells add` | `core/SpellInput.lua` | [module-map.md](module-map.md) |
| The launcher: one LibDataBroker object, the minimap button, the `Minimap button` row | `core/LauncherSetup.lua`, `settings/General.lua` (`minimapPath`, and the row's own get/set) | [settings-panel.md](settings-panel.md) |
| End-to-end smoke tests (cold install, visibility modes, lock/drag, cast bar, spec/talent/pet, profiles, secret values) | — | [smoke-tests.md](smoke-tests.md) |
| Slash-command + debug coverage matrices (what each command produces) | — | [testing.md](testing.md) |
| Performance instrumentation: the buckets, the offline scenarios, the in-game A/B and suspend | `core/PerfSetup.lua`, `tests/perf.lua` | [performance.md](performance.md), [perf-analysis/README.md](perf-analysis/README.md) |
| The stand-down latch: one teardown, two named holds (`disabled`, `perf`) | `core/LifecycleSetup.lua`, each module's `Suspend` / `Resume` | [slash-dispatch.md → The disabled state](slash-dispatch.md#the-disabled-state) |
| Code style, saved-variable boundary, `_G.X` vs bare X | every module | [common-tasks.md](common-tasks.md) |
| Scope, defaults source (Baratus sheet), cast-bar removal history | — | [scope.md](scope.md) |

## Namespace, naming, and the module publishing pattern

Every module is built on the **private addon namespace** — the vararg WoW hands each file. There is no `_G.KickCD` and no `KickCD = KickCD or {}` bootstrap:

```lua
local _, NS = ...
NS.Foo = NS.Foo or {}
local F = NS.Foo
```

- Every source file opens on that vararg, and the FIRST half is spelt `_` unless the file reads
  it. Eight do, each handing the addon FOLDER name to a vendored LibKa0s payload that cannot work
  out which folder it was copied into: `core/Constants.lua` (`Bus.Catalog`), `core/CoreSetup.lua`,
  `core/EnvSetup.lua`, `core/MediaSetup.lua`, `core/DebugLogSetup.lua`, `core/LauncherSetup.lua`,
  `core/LifecycleSetup.lua` and `core/PerfSetup.lua`. The other thirty-three write `local _, NS = ...`:
  a name nothing reads is a dead local, and `M4c-06` removed twenty-nine of them.
- `NS` is the shared private table.
- Never overwrite an existing `NS.Foo` without `or {}` — another file may have reached it first, and never shadow it with a file-local of the same name.
- The public API hangs off `F` (or `NS.Foo` directly); helpers stay `local` to the file.
- `core/KickCD.lua` calls `LibStub("AceAddon-3.0"):NewAddon(NS, "KickCD", …)` and **discards the return**: `NewAddon` promotes the table it is handed, so the return is that same `NS`. There is no `_G.KickCD = addon` rebind and no `NS.addon` self-reference — later files get `NS` from their own header, not from `GetAddon`. `core/Compat.lua` simply hangs `NS.Compat` on the shared `NS` at TOC load time.

**Naming.** The display name in the addon list and Settings panel is `Ka0s KickCD` (the colored `## Title` in `KickCD.toc`). Everything machine-facing stays unprefixed `KickCD` for ergonomics: the folder, the addon id, the slash commands, the saved-variable namespace (`KickCDDB`), and the global frame names (`KickCDIconGrid`, `KickCDCastbar`, `KickCDDebugWindow`, and the `…Focus` siblings).

## Invariants worth not breaking

- **Closed message bus.** The five AceEvent messages (`Ka0s_KickCD_SpellState`, `Ka0s_KickCD_ConfigChanged`, `Ka0s_KickCD_ProfileChanged`, `Ka0s_KickCD_GridLayout`, `Ka0s_KickCD_CombatState`) are the only inter-module communication channel. Every message has exactly one **owning module**, and the two with many announcing paths reach the bus through a single named emitter in that module: `Ka0s_KickCD_ConfigChanged` only via `settings/Panel.lua`'s `Helpers.FireConfigChanged` (any schema-row write, through the schema seam's `announce` in `settings/SchemaSetup.lua` — the lock/unlock toggle and the Focus link row among them — a batched row write such as Copy styling, which the seam's `announceBatch` announces once per section, drag-stop anchor saves, throttled spell edits — the session-only debug toggle is off-bus), and `Ka0s_KickCD_ProfileChanged` only via `core/Database.lua`'s file-local `fireProfileChanged` (the AceDB callback, and `Database:ResetAllSpells`, which re-seeds every spec's list in place and so needs the same full-rebuild fan-out without an actual AceDB profile swap). Both therefore have a single `SendMessage` site. `Ka0s_KickCD_SpellState` (three sites) and `Ka0s_KickCD_GridLayout` (two) still have several, but all of them sit inside the one module that owns the message, which is what `architecture-§4` requires; a cross-module `SendMessage` is the defect. Adding a message requires updating the owning emitter, every consumer, and [message-bus.md](message-bus.md).
- **`Compat` is API normalization only.** No feature decisions, no shared mutable state, no visibility helpers. Visibility decisions live in `core/State.lua`; shared mutable state lives in `core/State.lua`; shared magic numbers live in `core/Constants.lua`.
- **12.0 secret values get C-side handling, not Lua-side detox.** Pass duration-object methods, `notInterruptible`, `name`, `texture` straight into Blizzard C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`). Never bind to a Lua local for compare / format / tostring / arithmetic. `securecallfunction` / `tonumber` / `+0` "detox" were tried and don't work.
- **`NS.Settings.Schema` is the single source of truth.** UI widget, slash CLI (`get` / `set` / `list`), per-panel `Defaults` button, and the General → "Reset all settings" reset all wire from one row. Don't add parallel mutators for fields with a schema row. The `valueGate` mechanism enforces cross-row dependencies (e.g. `units.<unit>.castbar.growDirection` ↔ `units.<unit>.castbar.orientation`).
- **Colors are stored keyed, dropdowns are keyed hashes.** A color value is `{ r =, g =, b =, a = }` — the shape `LibKa0s-Slash-1.0` / `-Options-1.0` parse into and render from, so no host-side codec sits between them (the old positional `{r,g,b,a}` array migrated in `Database:MigrateColorShape`, the v3→v4 step, which also runs for every profile on Init and each profile swap). Dropdown `values` are keyed hashes with a sibling `sorting` array. Every color row carries `hasAlpha`; every schema row carries `desc` (not `tooltip`), `panel` and `section`.
- **One drag lock + one visibility mode shared across both UI pieces — PRESERVED across target/focus dual tracking.** The icon grid and the cast bar both read `db.profile.locked` and `db.profile.visibility`; one unlock/lock cycle moves every enabled unit's frames. Visibility is evaluated per-unit against that unit's own cast state (a focus grid hides/shows independent of whether target is casting), but the *mode* itself — and the lock — stay addon-wide, not per-unit. Don't introduce per-widget (or per-unit) lock or visibility-mode state; `scale`/`alpha` similarly stay addon-wide (per-unit scale/alpha was considered and deferred, not shipped).
- **`NS.State.inCombat` is the combat flag, not `InCombatLockdown()`.** `core/State.lua`'s combat listener — an AceEvent target (`LibStub("AceEvent-3.0"):Embed`, since `NS.NewBusTarget` loads later), armed from `NS:OnInitialize` by `State.Arm` — is the only registration of `PLAYER_REGEN_DISABLED/_ENABLED/PLAYER_LOGIN`; it maintains the flag and fans the transition out via `Ka0s_KickCD_CombatState` so subscribers (IconGrid, Castbar) see an explicit ordered signal. `InCombatLockdown()` lags the regen events by a frame and is unreliable.
- **Persisted keys are never derived from a localized string.** The spell-list key is the numeric specID (`Const.SPEC`); the class key is `UnitClass()`'s file token. `GetSpecializationInfo`'s second return is the *localized display name* and is display-only — routing it into a lookup key is what broke every non-English client in issue #8, silently and with no error, because a missing spec list is indistinguishable from a deliberately emptied one. Localized names may be accepted as slash-command input (`Util.ResolveSpecID`) and shown as UI labels (`Util.SpecDisplayName`); they may not be stored, compared, or used as identity. The same rule applies to any future per-something table.
- **Module publishing pattern:** every file does `NS.Foo = NS.Foo or {}; local F = NS.Foo`. Never shadow the local over the global (`local KickCD = {}` would break everything downstream). Full idiom above.
- **Frame mixin, not setmetatable.** Use `Mixin(frame, t)` to copy fields onto a Blizzard widget. `setmetatable` nils the C-side frame methods.

## External dependencies

All vendored under `libs/` and pulled in by `KickCD.toc`:

- LibStub
- CallbackHandler-1.0
- AceAddon-3.0
- AceEvent-3.0
- AceDB-3.0
- AceDBOptions-3.0
- AceConsole-3.0
- AceConfig-3.0 (pulls in AceConfigRegistry / AceConfigCmd / AceConfigDialog)
- AceGUI-3.0
- LibKa0s, the Ka0s shared library. **Fourteen majors are adopted**; what each one supplies, how
  each seam degrades and the one shared cause clause are
  [module-map.md → The LibKa0s majors](module-map.md#the-libka0s-majors).
  - Eleven have a setup file: `Core`, `Env`, `Pool`, `Media`, `DebugLog`, `Launcher`, `Lifecycle`
    and `Perf` in `core/<Major>Setup.lua`; `Slash`, `Options` and `Schema` in `settings/Slash.lua`,
    `settings/OptionsSetup.lua` and `settings/SchemaSetup.lua`.
  - `Widgets` is resolved inline by its two callers; `Compat` is wired onto `NS.Compat` by
    `core/Compat.lua` ([compat-layer.md](compat-layer.md)); `Bus` is taken for its `Catalog` alone.
  - **Never edit `libs/LibKa0s`**: fix it upstream and re-vendor. The vendoring gate is [testing.md](testing.md).
- LibSharedMedia-3.0
- AceGUI-3.0-SharedMediaWidgets (vendored upstream r65; provides the `LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` dropdowns used by the Cast bar / Icons panels). The fixup that hides the 42×42 Border `displayButton` preview tile and re-anchors the dropdown bar is **`lib.__PatchLSM30Border()`, a LibKa0s-Options-1.0 member** (minor 15), called from `settings/OptionsSetup.lua`'s live wiring. It used to be `core/LSMPatch.lua` here and in four sibling addons; AceGUI's widget registry is process-global, so five private registrations in one client meant the last addon loaded owned everyone's Border dropdown. One idempotent library member behind `lib.__lsmBorderPatched` is one registration however many copies of the library are vendored.
- LibCustomGlow-1.0
- LibDataBroker-1.1 and LibDBIcon-1.0 — the launcher's two libraries (`launcher-§1`), vendored here rather than arriving inside the LibKa0s payload. `LibKa0s-Launcher-1.0` resolves both with `LibStub(..., true)` at **Register** time, not at load, and degrades by name: a host with neither gets a launcher that reports itself absent, and one with the broker but no LibDBIcon still gets the plugin row in a broker display. Call time rather than load time is deliberate — nothing fixes the relative order of `LibKa0s.xml` and these two inside the TOC's `# Libraries` block.

Seven unused Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab, AceTimer) were deleted from `libs/`. AceTimer-3.0 went last (KCD-29): `library-stack-§1` lists it among the mandatory Ace3 libs, but `library-stack-§3` says vendor only what the addon actually `LibStub`s — and scheduling here is `C_Timer` throughout (`After`, plus one `NewTimer` behind the options drag throttle), so nothing ever loaded it. §3 won.

`KickCD.toc`'s `## Interface:` line targets the Midnight client.

## Message bus

Five `AceEvent` messages are the only inter-module communication channel — modules never call each other directly across boundaries. Full payload semantics in [message-bus.md](message-bus.md).

Each name is declared **once**, in `NS.MSG` (`core/Constants.lua`, keyed by the SCREAMING_SNAKE constant with its one sender named beside it), and every `SendMessage` / `RegisterMessage` call site reads `NS.MSG.<KEY>` — no call site types the literal (`architecture-§4`). The wire name's `<Event>` is PascalCase (naming-cheatsheet). The table is wrapped in **`LibKa0s-Bus-1.0`**'s `Catalog` (the only member of that major this addon takes): it validates the prefix and the casing at load and answers a strict copy, so reading an undeclared key raises at the call site for a sender as well as a receiver. Library absent, `NS.MSG` is the plain table with the same keys and wire names. The bus itself stays AceEvent, and receivers stay untracked (below). `tests/test_bus.lua` scans the authored files for a stray literal, pins each key to its wire name, and pins both arms.

| Message | Sender(s) | Consumers | Payload |
|---|---|---|---|
| `Ka0s_KickCD_SpellState` | `Cooldowns:Rebuild` / `:Refresh` | `IconGrid` (every enabled unit instance) | `{ spellID, ready, isActive, cdObject, chargeCdObject, charges, rebuild }` |
| `Ka0s_KickCD_ConfigChanged` | **One sender**: `settings/Panel.lua` `Helpers.FireConfigChanged`. Everything that wants to announce a config change calls it — the schema seam's `announce` (every row write, the Focus link included) and `announceBatch` (a `Store.SetMany` such as Copy styling, each section once), `Panel_Render`'s reset helpers, `core/KickCD.lua`'s spells commit, the Spells editor's throttled commit, and IconGrid / Castbar `OnDragStop` | `IconGrid`, `Cooldowns`, `Castbar`, `UnitLabel`, Spells panel | `{ section }` — section ∈ `general`\|`icons`\|`castbar`\|`label`\|`spells`\|`units` |
| `Ka0s_KickCD_ProfileChanged` | **One sender**: `core/Database.lua`'s file-local `fireProfileChanged`, called by `Database:OnProfileChanged` (swap / copy / reset; `newProfileKey` is the active profile afterwards) and `Database:ResetAllSpells` | `IconGrid`, `Cooldowns`, `Castbar`, `UnitLabel`, Spells panel | `{ newProfileKey }` |
| `Ka0s_KickCD_GridLayout` | `IconGrid:Layout`, once per unit instance | `Castbar` (filters on `payload.unit`), `UnitLabel` (re-applies every unit; cheap `ApplyAll`, no per-unit filter) | `{ unit, gridFrame, primaryIcon, width, height }` |
| `Ka0s_KickCD_CombatState` | `core/State.lua` combat listener | `IconGrid`, `Castbar` | `{ inCombat }` |

Receivers each register on their **own** AceEvent target: AceAddon modules use their module `self`; the Spells settings panel uses a private target from `NS.NewBusTarget()`. None register on the shared addon object.

## Slash commands

`/kcd` and `/kickcd` are aliases. Bare `/kcd` runs `config` and opens the settings panel on its landing page; `/kcd help` prints the command list (slash-commands-§4). The dispatch table (`NS.COMMANDS` in `core/KickCD.lua`) is sender-authoritative for the top-level verbs:

| Command | What it does |
|---|---|
| `help` | List available commands |
| `version` | Print the addon version |
| `config` | Open the settings panel |
| `enable` | Turn the addon on. A **reserved alias** (`slash-commands-§2`): it writes the Master-controls `enabled` row's own stored path through the same single write seam the checkbox writes through, and holds no state of its own |
| `disable` | Turn the addon off — **totally**: every registration released, every timer canceled, nothing drawn and nothing written from a game event ([The disabled state](slash-dispatch.md#the-disabled-state)). The same alias in reverse. Every reserved verb keeps answering while it is off, and the bare `/kcd` still opens the panel — the dispatcher and the settings registration are **setup, not features** — so the pair is never one-way |
| `lock` | Lock the icon grid in place |
| `unlock` | Unlock the icon grid for dragging |
| `toggle` | Toggle the icon grid lock state |
| `list` | List every setting and its current value |
| `get <path>` | Print a setting's current value |
| `set <path> <value>` | Set a setting (try `/kcd list`) |
| `perf` | Guided A/B performance capture (`LibKa0s-Perf-1.0`), driven from a clickable step panel |
| `reset <path>` | Reset one setting to its default. Page-scoped reset lives on each panel's **Defaults** button; the every-spec spell rebuild moved to `/kcd spells resetall` |
| `resetall` | Reset the **active profile** to the shipped defaults — a profile reset, and the same act as Profiles → Reset Profile (`options-ui-§12`). Every panel, every anchor, every unit's `link` flag and every spec's spell list come back with it, because all of them live in the profile; `Database:OnProfileChanged` re-seeds and refreshes on the way back, exactly as it does for a profile switch. Other profiles are never touched |
| `resetposition` | Restore the icon grids to their default screen positions |
| `spells` | Spell-list editor (try `/kcd spells` for the list) |
| `debug` | Debug subcommands (try `/kcd debug` for the list) |

With LibKa0s absent, `/kcd` still answers through the degradation stub in `settings/Slash.lua` (`slash-commands-§1`, WS-02): minimal dispatch with the same disabled gate, the library's `DISABLED_LINE_FORMAT` carried verbatim and pinned by `Kit.assertLibraryConstant`, and no formatter or parser copy. `enable`, `disable`, `lock`, `unlock` and `toggle` keep working because `enabled` and `locked` are on `NS.Settings.WRITE_THROUGH` (route (a)); every other schema verb prints `/kcd <verb> is unavailable: the LibKa0s library did not load.` Detail in [slash-dispatch.md](slash-dispatch.md#degraded-verbs-a-load-without-libka0s).

`/kcd debug` sub-verbs (`DEBUG_COMMANDS`): `window`, `on`, `off`, `toggle`, `spells`, `castbar`, `interrupt`, `events`. Bare `/kcd debug` toggles the console window.

## Settings schema

`NS.Settings.Schema` is the single source of truth for every option. Each row wires automatically into its UI widget, `/kcd get|set|list` coverage, and the per-panel `Defaults` reset (plus the General → "Reset all settings" reset) — so adding a setting is one schema row, never a parallel mutator. Every row also carries a `group`, which **is the tab**: each schema page partitions its rows by `group` in declaration order and draws a strip from them (`options-ui-§13`), so a group's rows must stay contiguous. The font, border, bar and color blocks are **composed** by `LibKa0s-Options-1.0` rather than written out (`options-ui-§16`), and every color swatch carries a `Use class color` companion immediately to its right (`options-ui-§17`). Detail in [settings-panel.md](settings-panel.md).

**The runtime over the rows is `LibKa0s-Schema-1.0`'s.** `settings/SchemaSetup.lua` builds `NS.Settings.Store` over the live `NS.Settings.Schema` array: the path index (`Store.FindRow`), the single write seam (`Store.Set`, and `Store.SetMany` for an all-or-nothing batch), the bulk bracket both descriptors take, the profile reset's count (`Store.ResetCounted` / `ConsumeResetCount`) and the shape check (`Store.Validate`, run at panel-register time and unit-tested at 0 errors, with every stored path resolving against `NS.DEFAULT_PROFILE`). An **unknown path is refused, never stored**; a table value is **copied** in; a row's `onChange` runs after the store and before the announce, and **its errors propagate**. The two rows stored outside the profile (`state.debugConsole`, `global.minimap.shown`) carry their own `get`/`set`, wired in `settings/General.lua`. `enabled` and `locked` are on the seam's `writeThrough` list, so the host verbs that write them still land on a load where the composer that declares them is absent. With LibKa0s absent the seam is the host's own write-completing, log-silent degradation stub in the same file ([settings-panel.md](settings-panel.md#the-write-seam-libka0s-schema-10)).

**Reading a schema path.** The schema seam's `Store.Get` is the reader, and both descriptors take it by value. `settings/OptionsSetup.lua` publishes it as **`NS.Settings.ReadForPanel`** too, so the panel's reader has a name a case can call. That is there for one reason: the reader's only historical defect — `H and H.Get and H.Get(path) or nil`, whose trailing `or nil` folds a stored `false` to `nil` — is **invisible** through the options surface, because every consumer of `d.get` in `OptionsWidgets.lua` folds the answer to a boolean first. The identical spelling in `settings/Slash.lua` was loud (`/kcd get` printed the literal `nil`). Both files are pinned, one case each, in `tests/test_options_panel.lua` and `tests/test_slash.lua`.

**The drag throttle's timer.** The descriptor's `scheduleTimer` is published the same way, as **`NS.Settings.ScheduleTimer`**, and returns `C_Timer.NewTimer`'s cancelable handle rather than `C_Timer.After`'s nil. Since LibKa0s v1.56.0 (OptionsWidgets minor 31) the library keeps its own armed flag and ignores the return value, so the handle is belt and braces: an older payload used it as the armed flag, and nil meant every ~60 Hz color or slider drag tick committed and fanned out `CONFIG_CHANGED` (KICKCD-R-04). `tests/test_options_panel.lua` pins both the handle and one commit per throttle window.

**The one structural registry: the spell lists (`architecture-§5`).** The per-class, per-spec tracked-spell lists are a collection the player adds to and removes from, and no schema row addresses a member, so they are a registry rather than a setting.

- **Storage keys.** `db.profile.spells[CLASS][specID]` is an ordered array of `{ spellID, category, enabled }` entries, keyed by `UnitClass()`'s file token and the numeric spec ID, whose array order is the icon grid's render priority (declared as `spells = {}` in `defaults/Profile.lua`).
- **Writer.** `core/Database.lua` (`NS.Database`) is the one writer, and compliant. It owns every runtime write: add-or-enable (`AddSpell`), remove (`RemoveSpell`), reorder (`MoveSpell`, one splice per drag), the per-spec reset (`ResetSpellList`), the every-list reset (`ResetAllSpells`, behind `/kcd spells resetall`) and the lazy create (`EnsureSpellList`, called only from this file). Both resets share the load pass's seed routine, so both re-append the player's racial on their own class. The Spells page (`settings/Spells.lua`, with its row builders in `settings/Spells_Rows.lua`) and the `/kcd spells` handlers (`core/KickCD.lua`) call these verbs and keep their own notify paths (the page's throttled `commitSoon`, the slash layer's `commitSpellsChange`). Neither touches a stored list, and `tests/test_spell_registry.lua` scans all three files to keep it that way.
- **Load pass.** `Database:MigrateSpecKeys` (re-keys legacy spec names to spec IDs) then `Database:BuildSpells` (seeds a never-populated profile and appends the player's racial), run from `Database:Init` and again from `Database:OnProfileChanged` on every profile switch, copy and reset.

Each entry's `enabled` and `category` fields are player preferences, not membership, so the writer's closed list does not cover them. They stay bespoke controls with no schema row: the Spells page's row checkbox and category dropdown, `/kcd spells enable|disable|category`, and the re-enable when a spell already listed is added again. Every one of those writes goes through `Database` (`SetSpellEnabled`, `SetSpellCategory`, `AddSpell`). That is a ratified `architecture-§5` deviation, recorded with its re-check trigger in [Documented deviations](#documented-deviations).

**Named non-setting state: the frame anchors (`architecture-§5`).** Each unit's icon-grid and cast-bar screen position is geometry that only a drag determines. No control sets it and no row addresses it, so it is named state rather than a setting. Naming it here is the compliance, and it carries no register row.

- **Storage key.** `db.profile.units.<unit>.anchors.icons` and `.anchors.castbar`, each a `{ point, relativePoint, x, y }` snapshot relative to `UIParent` (`Util.SaveAnchor`). It is kept per unit and never link-resolved.
- **Owner.** `core/Units.lua` (`NS.Units`). `Units.SetAnchor(unit, which, a)` writes it and `Units.Anchor(unit, which)` reads it.
- **Writers, with the act that reaches each.**
  - `Units.SetAnchor`, from the icon grid's drag-stop (`modules/IconGrid.lua` `onDragStop`, `"icons"`) and the cast bar's drag-stop (`modules/Castbar.lua` `onDragStop`, `"castbar"`; the bar only drags in `FREE` anchor mode).
  - `Helpers.ResetIconPosition` (`settings/Panel_Render.lua`), from Master controls → *Reset position* (`settings/General.lua`) and `/kcd resetposition` (`core/KickCD.lua`). It writes every unit's `anchors.icons` (`NS.Units.LIST`) directly rather than through `Units`, putting back each unit's `DEFAULT_PROFILE` coordinate; cast-bar anchors are left alone. A reset to the shipped default chooses nothing, so this is a listed writer and not a finding.

  No other runtime code writes an anchor. Two paths also touch the anchors and are not writers the naming has to list. The load pass, `Database:FoldLegacyUnits`, merges a legacy top-level `anchors` table into `units.target.anchors`. The profile reset behind `/kcd resetall` and Profiles → Reset Profile replaces the profile wholesale.

**Named non-setting state: the perf capture ring (`architecture-§5`).** Recorded data, written by a vendored library into the SavedVariables global the addon hands it. No control sets it and no row addresses it.

- **Storage key.** `KickCDPerfDB`, the TOC's second SavedVariables: its `schema` stamp and the `runs` ring of capture records. It sits outside the AceDB tree on purpose, so a profile copy, reset or switch never touches it.
- **Owner.** `core/PerfSetup.lua` (`NS.Perf`), which hands the library the key as the descriptor's `sv`.
- **Writer, with the act that reaches it.** `LibKa0s-Perf-1.0`'s `P.Save` (`libs/LibKa0s/Perf.lua`), from `/kcd perf finish` and from the step panel's Finish step, which runs the same command. It appends the finished record, drops the oldest past the library's ring size, and discards a ring stored under an older record schema, logging that discard itself.

  No addon code writes it, and there is no forget, purge or delete verb over it. `/kcd perf cancel` saves nothing.

**The launcher, and the one table it shares with a library (`launcher-§1`/`§3`).** The minimap button and the broker plugin are **one** LibDataBroker-1.1 object registered twice — once with LibDataBroker, once with LibDBIcon-1.0 — so there is one `OnClick`, one icon and one name. Written as two features it would be two click implementations that drift on the first behavior change (anti-pattern #81).

- **Owner.** `core/LauncherSetup.lua` (`NS.Launcher`), the `LibKa0s-Launcher-1.0` descriptor. It supplies the four answers that are genuinely this addon's: the **folder name** (`addonName`, which LibDBIcon keys the button's saved position by, so it is not cosmetic), the icon (`media/logos/kickcd.logo.128.tga`, the same file the TOC's `## IconTexture` names), `openSettings`, and the options menu's pairs. The **`label`** is `Ka0s KickCD` — the brand name in **plain text**, which `launcher-§1` fixes because a broker display prints it beside the other ten Ka0s addons. It is deliberately not the TOC's `## Title` (a Title may carry color escapes, and one in the collection does) and not the folder name, which is `name`.
- **Both buttons are the library's (`launcher-§2`, standard v2.67.0; Launcher version 4).** Left-click opens the settings panel, in either state. Right-click opens the client's context menu (`MenuUtil.CreateContextMenu`), titled `Ka0s KickCD`, with the entries this addon's pairs supply — **Enabled** (`isEnabled = NS.MasterEnabled`, `setEnabled = NS.SetMasterEnabled`, the handler `/kcd enable` / `disable` run) and **Locked** (`isLocked = db.profile.locked`, `toggleLock = NS.ToggleLock`, the handler `/kcd toggle` runs, landing on `Store.Set("locked", v)`). Both handlers live in `core/KickCD.lua`; the launcher holds no copy of either state and builds no menu or click route of its own (anti-pattern #81). No Test mode entry (unlocking *is* the preview) and no Show window entry (no primary window). While the addon is disabled the library grays *Locked* (`Locked (enable the addon first)`) and calls nothing for it; *Enabled* stays live. Without `MenuUtil` the right click opens the panel.
- **The status tooltip is the library's (`launcher-§1`; Launcher version 3, hints fixed at version 4).** It draws the title and version, `Enabled`, `Locked`, then `Left-click: Open settings` and `Right-click: Options menu`, enabled or disabled. The descriptor only answers it: `version` (the TOC's `## Version`, through `NS.Version()`), `isEnabled` and `isLocked`, each asked on every show. No `isTestMode` (there is no test mode) and no `onTooltipShow` (no lines of the addon's own; a host title or hint beside the library's is anti-pattern #89).
- **Registration.** `NS:OnEnable` calls `NS.Launcher:Register()`, after `OnInitialize` has built the db — `Register` resolves `db.global.minimap` through the descriptor's `minimap` **function**, because a table captured at file load is one AceDB later replaces. It is idempotent.
- **Storage key.** `db.global.minimap` — LibDBIcon's **own** table, declared as `minimap = { hide = false }` in `core/Database.lua`'s `aceDBDefaults`. The declared default is what materializes it; nothing seeds or backfills it by hand (`architecture-§5`).
- **Writers.** The `global.minimap.shown` row's own `set` (wired in `settings/General.lua`), reached from the *Minimap button* row, `/kcd set` and `/kcd reset` through the addon's single write seam (`Store.Set`) — and **LibDBIcon itself**, which writes `hide` from its own `Hide` / `Show` and `minimapPos` when the player drags it. Both write the same table on purpose: a second key beside `hide` would be a copy free to disagree. The row's **path** reads in the row's own sense (`launcher-§3`, standard v2.65.0), so `/kcd get global.minimap.shown` answers true while the button shows; the path names no stored key, and its get/set invert onto `hide`. The rename moved only the CLI name — no SavedVariables migration and no `schemaVersion` bump — and the old `global.minimap.hide` path answers *Setting not found*. The library's writes need no register row (`architecture-§5`).
- **Scope.** GLOBAL, so a profile switch does not move a player's buttons. This addon has never stored a minimap table under `profile`, so adoption moved no stored path and `schemaVersion` did not bump.
- **It survives every reset, and that is a property rather than a consequence of the scope (`launcher-§3`, standard v2.54.0).** A player's minimap-button choice is a per-installation display preference, in the same class as the button's position, which LibDBIcon keeps in the very same table and which no reset touches. Both resets are held off, by different means, and only one of them ever was:
  - ***Reset all settings*** never reached it. `LibKa0s-Options-1.0`'s `RestoreAllDefaults` narrows its row walk to the `sessionOnly` rows once `resetProfile` is supplied and this row is deliberately **stored**; `settings/OptionsSetup.lua`'s `vetoedFromResetAll` answers true for it regardless; and the reset itself is `db:ResetProfile()`, which empties `db.profile` while the table is `db.global`.
  - **The General page's *Defaults* button DID reach it**, and putting it back on the ring at LibDBIcon's default angle was a real bug. `RestoreDefaults` walks `rowsForPage("general")` — where the composed *Minimap button* row lives — and consults no veto at all, because `skipRestoreAll` is read by `RestoreAllDefaults` and by nothing else. The schema seam's **`resetExempt`** (`settings/SchemaSetup.lua`) now refuses the row inside `Store.ApplyDefault` while a bulk bracket is open, and both walks write through the descriptor's `applyDefault` inside the bracket, so the one row is exempt from both from one place. `/kcd reset global.minimap.shown` is untouched: a row the player named out loud is neither of the two resets the rule is about.

## Event subscriptions

Game-event registration is deliberately partitioned by module (specifics in [module-map.md](module-map.md)).
Every registration below is released on the stand-down and rebuilt on the stand-up ([The disabled
state](slash-dispatch.md#the-disabled-state)), so a disabled KickCD is registered for **nothing**:

- **`core/State.lua` combat listener** (an AceEvent target, not a frame) — the only registration of `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` / `PLAYER_LOGIN`; owns the `NS.State.inCombat` flag and fans transitions out via `Ka0s_KickCD_CombatState`.
- **`Cooldowns`** — `SPELL_UPDATE_COOLDOWN` / `_USABLE` / `_CHARGES` (coalesced through a `Util.Throttle(0)` so a same-frame burst yields one `Refresh`/frame), `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`.
- **`IconGrid`** — `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START` / `_STOP` / `_FAILED` / `_INTERRUPTED` / `_CHANNEL_START` / `_CHANNEL_STOP` / `_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE` / `_EMPOWER_START` / `_EMPOWER_UPDATE` / `_EMPOWER_STOP`) on the instance's cast filter (`Util.NewUnitCastFilter`; dispatches only when the event's unit matches the instance's unit), plus the four inbound `Ka0s_KickCD_*` messages. Registration is enable-gated per instance: a disabled unit's instance is not built and does not register anything.
- **`Castbar`** — the `UNIT_SPELLCAST_*` family, `EMPOWER_START` / `_UPDATE` / `_STOP` included, on the instance's cast filter (unit-filtered dispatch: a focus instance only reacts to focus casts), plus `PLAYER_TARGET_CHANGED` / `PLAYER_FOCUS_CHANGED` and its inbound messages.

**One cast-filter frame per module per unit, re-armed and never rebuilt.** `Util.NewUnitCastFilter(module, unit, routes)` builds a single private frame per (module, unit) the first time that unit enables, from a file-scope route map (`ICON_CAST_ROUTES` / `CASTBAR_CAST_ROUTES`) that is the frame's fixed event set; it refuses any route that is not `UNIT_SPELLCAST_*`, so it is not a general frame factory (events-frames-taint-§1). `Arm()` registers exactly that set through `NS.SafeRegisterUnitEvent` (one name the client refuses costs only its own route and lands once in `NS.State.rejectedEvents`) and is idempotent; `Disarm()` is `UnregisterAllEvents()`. `DisableUnit`, `Suspend` and every disable/enable, per-unit toggle, profile switch or perf suspend/resume disarm and re-arm the same frame, so a cycle creates no frames (`tests/test_disabled.lua` counts them).
- **`UnitLabel`** — `PLAYER_ENTERING_WORLD` plus its three inbound `Ka0s_KickCD_*` messages (`CONFIG_CHANGED` / `PROFILE_CHANGED` / `GRID_LAYOUT`). No cast-event or combat registration — the label has no state of its own beyond what those messages already trigger a re-`Apply` for.

## The stand-down: disabled is total

`slash-commands-§7`: *disabled* means NOT RUNNING, not hidden. The stored `enabled = false` and a perf
capture's suspended arm are two named holds (`disabled`, `perf`) on one `LibKa0s-Lifecycle-1.0` latch in
`core/LifecycleSetup.lua`; while either is taken every registration, bus subscription and timer is released
and nothing is drawn, and the dispatcher, the settings panel and the launcher stay up because they are
setup. The full account is [slash-dispatch.md → The disabled state](slash-dispatch.md#the-disabled-state).

## Taint notes

Under 12.0, `C_Spell.GetSpellCooldown` timing returns and `UnitCastingInfo` / `UnitChannelInfo` `notInterruptible` / `name` / `texture` come back **secret** in combat for protected interrupts. Secret values must be passed straight into Blizzard C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`) — never bound to a Lua local for compare / format / `tostring` / arithmetic, which errors in tainted scope. Visibility and interruptibility decisions that depend on `notInterruptible` go through the two-step gate `State.IsHostileUnitCasting` (show) + `State.ApplyInterruptibleAlpha` (filter). Full pattern catalog in [midnight-quirks.md](midnight-quirks.md).

## Known limitations

- English (`enUS`) only.
- Retail / Midnight only — a single `## Interface` line, no Classic support.
- No automated in-client tests — headless unit tests plus manual in-game smoke tests only (see [smoke-tests.md](smoke-tests.md)).
- Debug logging is session-only (`NS.State.debug`) and resets on every `/reload`.

## Documentation map

Every `.md` under `docs/` appears in exactly one table below (`documentation-§3`). Frozen and
generated directories are named once each and never enumerated per run: `docs/audits/`, `docs/reviews/`, `docs/automated-tests/`, `docs/superpowers/`, `docs/perf-analysis/`, `docs/revendor/`.

Those frozen bundles are history, not requirements. The older ones predate standard v2.17.0 and
still name `docs/agent-context.md` or describe an earlier doc set; that file does not exist here and
MUST NOT be restored (documentation-§3) — root `CLAUDE.md` is the only agent brief. The current
compliance baseline is the newest `docs/audits/<date>/` bundle; re-run `/wow-addon:standards-audit`
when in doubt, which fetches the living standard and writes a fresh one.

### Required (documentation-§3, Tier 1)

| Doc | Covers |
|---|---|
| `ARCHITECTURE.md` | This file — the hub: overview, module map, message bus, slash commands, taint notes, deviations |
| `scope.md` | What the tracker watches, and the cooldowns it deliberately ignores |
| `module-map.md` | Every non-vendored file, its responsibility, and load order |
| `schema.md` | The persisted shape, every default, and the migration seam |
| `settings-panel.md` | The panel tree, per-option behavior, and the write seam |
| `data-flow.md` | Cast/cooldown events in → state → icon grid and cast bar out |
| `common-tasks.md` | Recipes for the changes made most often here |

### Conditional (documentation-§3, Tier 2)

| Doc | Status | Trigger |
|---|---|---|
| `slash-dispatch.md` | Present | 18 verbs in `NS.COMMANDS`, with `debug` and `spells` subcommand trees |
| `midnight-quirks.md` | Present | The 12.0 secret-value rules and the cast-info shims |
| `compat-layer.md` | Present | `core/Compat.lua` publishes 8 shims beyond LibKa0s by the `documentation-§3` count (`grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.' core/Compat.lua`), over the trigger of three |
| `message-bus.md` | Present by choice | 5 messages in `NS.MSG`, under the more-than-ten trigger, which has not fired; kept because the closed contract is cited from each module’s header |
| `profiles.md` | Present | AceDB profiles are user-visible — the Profiles settings page |
| `perf-analysis/README.md` | Present | `/kcd perf` exists (`LibKa0s-Perf-1.0`, `core/PerfSetup.lua`), so in-game captures have a store to describe |
| `debug.md` | Present | Debug surfaces beyond the LibKa0s console: the `/kcd diagnostics` report and its twelve sections (`debug-logging-§14`), and four chat topics (`/kcd debug spells`, `castbar`, `interrupt`, `events`) |

### Verification and record

| Doc | Covers |
|---|---|
| `testing.md` | How to run the harness and lint; the green commit gate |
| `smoke-tests.md` | The in-game smoke-test suite |
| `test-cases.md` | The generated case inventory (authoritative pass count) |
| `performance.md` | The addon performance page |
| `automated-tests/README.md` | What the automated-test record is and how to produce it |
| `automated-tests/RESULTS.md` | One row per run; generated by the runner, never hand-edited apart from the watch list's `Disposition` column (automated-tests-§4) |

### Addon-specific (documentation-§3, Tier 3)

| Doc | Covers |
|---|---|
| `castbar.md` | The cast bar: skin, layout, and its debug dump |
| `icon-grid.md` | The icon grid: layout, render, and the C-side alpha curves |

## Documented deviations

The **single home** for a ratified deviation from the Ka0s WoW Addon Standard (`documentation-§3`).
A deviation not in this table is not ratified: an audit that cannot find the decision here re-files it
as an open MUST failure, and the same argument gets had every cycle. The reasoning may live at length
in the topic doc named in **Why**; the row is what makes it a decision rather than a note.

**Re-check trigger** is the condition that *ends* the deviation, written so a reader can tell whether
it has already fired. A row without one is a permanent opt-out wearing a table's clothes. When a cited
rule changes so that the behavior is now mandated or permitted outright, the row is **retired** — this
table must not become a graveyard.

| Rule | What differs | Why | Decided | Re-check trigger |
|---|---|---|---|---|
| `savedvariables-§1` | Five profile migrators run off the **stored shape**, not off `db.global.schemaVersion` alone: `FoldLegacyUnits`, `BackfillLabelStyle`, `MigrateSpecKeys`, `MigrateColorShape` and `MigrateFontFlags` run on `Database:Init` and on every `OnProfileChanged`, beside the version ladder. `schemaVersion` (declared default 0) and the ladder both exist as the rule requires, and the ladder still runs four of them once per account to advance the stamp. | A bare `schemaVersion` bump cannot distinguish "pre-`label.style`" from "current", because AceDB's `copyDefaults` has already written the new sub-table into the stored profile before any migrator looks — the same masking trap `FoldLegacyUnits` was written around. And the stamp is per-account while the data is per-profile, so a stamp-gated step converts only the profile active at the upgrade (issue #8, KICKCD-R-01). Reasoned at [schema.md](schema.md#unitsunitlabelstyle-shape). | 2026-07-16; rewritten 2026-09-24 | An AceDB release where `copyDefaults` no longer backfills before migration runs, **or** a sixth shape-driven step, **or** a LibKa0s per-profile migration runner — any of these makes the hand-rolled set the wrong tool and reopens this row. |
| `savedvariables-§1` | `DEFAULT_PROFILE` was **restructured** — target/focus nested under `units.<unit>` — rather than only grown, departing from the "a profile shape never changes shape, only grows" expectation the section's example implies. | Target and focus each need independently customizable `icons`/`castbar`; the flat alternative (`icons`, `focusIcons`, `castbar`, `focusCastbar`, …) does not scale to a third unit and duplicates the anchor/label bookkeeping. The shape-driven migration above is the mitigation that makes it safe for existing installs. Reasoned at [schema.md](schema.md#migration-folding-legacy-iconscastbaranchors-into-unitstarget). | 2026-07-15 | A third tracked unit is added — at which point the nested shape is load-bearing rather than a departure, and this row retires. |
| `options-ui-§1` | `Helpers.LSMValues` / `Helpers.AnchorValues` / `Helpers.AnchorOrder` stay the **host's own** code in `settings/Panel.lua`, shadowing the library's published `O.LSMValues`, rather than being read off the instance like every other member. | `settings/Icons.lua` and `settings/Castbar.lua` evaluate these inside schema-row literals **at FILE LOAD**. Were they instance members, the LibKa0s-absent stub would have to publish them or the page files raise, the rows never register, and a large part of `NS.Settings.Schema` goes missing — taking `/kcd list|get|set|reset` and the profile defaults with it, silently. Keeping them host-side is what lets the degraded stub need **zero** load-time members. The library's `O.LSMValues` is still not a drop-in — it falls back to `STRINGS.LSM_NONE` ("None") where the host's uses `"Default"` — but the **shape** difference is gone: from LibKa0s-OptionsCompose minor 3 (vendored at v1.26.0) `lib.__AttachCompose` reads this member once, at row-declaration time, so a host shadow handing back a **table** freezes every composed media row at file load, silently. The shadow returns the deferred **closure** the library's does, and `tests/test_color_shape.lua`'s "an LSM-backed row resolves its values at call time" is what holds it there. Measured, not assumed, and reasoned in full at [../settings/OptionsSetup.lua](../settings/OptionsSetup.lua) — the measurement is gated by `tests/test_options_panel.lua`, which loads the addon with the library absent and pins `#NS.Settings.Schema`. | 2026-08-05 | Any KickCD page file stops evaluating these inside a schema-row literal at file load — at which point the load-completing constraint is gone and all three move onto the instance. The pinning case in `tests/test_options_panel.lua` is what makes that visible. |
| `options-ui-§15` | **`General visibility`'s VALUE LIST** is this addon's own — `Always` / `In combat` / `When target is casting` / `When target is casting an interruptible spell` — where §15 mandates `Always` / `Only in combat` / `Only out of combat` / `Never`. Everything else about the row is the composer's: its position, its label, its pairing, its stored path. | KickCD's visibility is **cast-state driven**, and *"when the target is casting an interruptible spell"* is the mode the entire addon exists for — it is what makes an interrupt tracker different from a cooldown bar. The canonical four cannot express it, so adopting them verbatim would delete the feature rather than standardize it. The two canonical modes this addon lacks are covered or meaningless here: `Never` is what the tab's own `Enable KickCD` does, and `Only out of combat` names a state in which nothing this addon draws has anything to show. The stored KEYS are untouched (`in_combat`, not `inCombat`), so this is a declaration difference and not a migration — see [settings-panel.md](settings-panel.md#master-controls--the-canonical-tab-options-ui-15). | 2026-09-02 | `LibKa0s-Options-1.0`'s `MasterControls` composer accepts a `values` override for the visibility row, **or** options-ui-§15 admits an addon-specific visibility set — either makes this a supported shape rather than a departure and retires the row. |
| `options-ui-§13` | The Grid page's **Defaults** restores the active rail entry's rows **for the unit in the band only** (`Helpers.RestoreGridSection`, `settings/Panel_Render.lua`). §13 bounds a railed page's Defaults by "the set the folded sub-page's own button restored", and the Icons, Cast bar and Text Label pages' own buttons reset **both** units: the library's `O.RestoreDefaults` omits the unit filter on purpose. | The owner's ruling for KickCD#33 (2026-09-26). The band names the unit the page is editing, and a Defaults that reached the unit off screen would change settings the player cannot see. MultiMeters' Windows page behaves the same way with no deviation, because its rows are window-relative. The library's page walk is unchanged, so `H.RestoreDefaults(page)` still resets every unit (`tests/test_settings_log.lua`). | 2026-09-26 | options-ui-§13 states the Defaults scope for a railed page whose band picks one of several instances (either way), **or** the owner reverts the Grid page to both units. |
| `events-frames-taint-§8` | `core/Compat.lua`'s `/kcd debug interrupt` dump carries its own value renderer (`safeRender` at `:368-376`, used by `describe` at `:380-385`) beside the library's `NS.SafeToString`, which `core/CoreSetup.lua` publishes. The section's closing line makes a second stringifier the deviation, and option (a)'s scoping of the pre-formatting MUST does not touch it. | It is not the printer seam's stringifier and nothing routes through it to reach chat. It renders a diagnostic **value column** — `%q`-quoted strings, `<table>`/`<function>` for a non-scalar, printed beside that value's `type=` and `isSecret=` — which is a dump's cell, not a chat line's argument, and which `SafeToString` does not produce and should not learn to. Its detection is `issecretvalue()`, the engine's own predicate: that is what §8's `table.concat` probe exists to approximate where the predicate is unavailable, not the `..` probe §8 forbids. Every value reaching `describe`'s `string.format` has already been through `safeRender`, so the dump cannot raise on a secret. | 2026-08-05 | `LibKa0s-Core-1.0` publishes a diagnostic value renderer (a `Describe` / `RenderValue`), **or** `safeRender` gains a caller outside the `/kcd debug interrupt` dump — either makes the local copy redundant and retires this row. |
| `options-ui-§14` | **The Spells page's chrome band is TWO ROWS** — the Specialization picker on the first, `Add a spell` (the library's `IdInput`) on the second — where §14 says *"The band is ONE ROW, and where the acts do not fit in it they move to a `General` first tab."* The band's height is 105 rather than the library's one-row `BANNER_H` of 44, so every row below the strip sits permanently lower. | §14's own escape does not reach this page. It moves the **acts** (rename, copy-from, enable, unlock, reset, delete) to a `General` tab and is explicit that it is *"an escape for the acts, never for the picker"*; the same sentence names *"the picker, and the create control where the page has one"* as the identity controls the band **MUST** carry. Adding a spell is this page's create control, so both of the two things §14 refuses to let leave the band are on it, and they do not fit side by side: each is a caption over a control, the two controls are different heights, and aligning the captions left the controls crooked while aligning the controls left the captions crooked — the owner saw both shapes in the live panel and chose the stack. A one-row band here would mean deleting the create control or putting it in the scroll, which is the first thing §14 forbids. | 2026-09-22 | `LibKa0s-Options-1.0`'s `IdInput` gains a compact form — no caption, or a status line that does not need a row of its own — so the picker and the add box fit on one row; **or** §14 admits a second band row for a picker paired with a create control, at which point this is a supported shape and the row retires. |
| `architecture-§5` | Each spell-list entry's `enabled` and `category` fields (`db.profile.spells[CLASS][specID][i]`) are player preferences with **no schema row**, so they have no `/kcd get\|set\|list\|reset` reach and never pass through the schema-row helper. They stay bespoke controls: the Spells page's row checkbox and category dropdown, `/kcd spells enable\|disable\|category`, and the re-enable when a spell already in the list is added again. Since [#16](https://github.com/tusharsaxena/KickCD/issues/16) every one of those writes goes through `core/Database.lua`, the spell lists' one writer (`SetSpellEnabled`, `SetSpellCategory`, `AddSpell`), so they have a single writer, just not the helper. | `category` is informational only. It drives no rendering, filtering or ordering, and the dropdown's own tooltip says so. `enabled` does have runtime behavior, since a disabled entry is not tracked, and it was decided with that in view: it is one boolean on one entry, set by the same per-entry controls, and it hits the same addressing wall, so the runtime effect does not earn it a row. Rows per entry would multiply the schema by every tracked spell in every class and spec, and the helper addresses fixed paths only, with no instance argument that could name one entry of one list. Decided by the owner on [#17](https://github.com/tusharsaxena/KickCD/issues/17). | 2026-09-12 | Any one of: `category` starts driving filtering or ordering; a new per-entry field is added to the spell-list entry shape; **or** the helper gains instance addressing, so a row can name one entry of one list. |

**Retired on 2026-09-08: the hollow composers, and the ruling this addon asked for.** The register
carried an `options-ui-§1` row marked PROVISIONAL (`KICKCD-A-10` in `docs/audits/2026-09-07/`): a
library-less load registered **112 of 228** schema rows, and once `LibKa0s-OptionsCompose` moved schema
**content** behind a library call no stub could be both load-completing and free of a host copy of
library content. `options-ui-§1` now answers it: the **no-copy MUST wins**, a stub's composer members
answer an empty row list, and *"this shape needs no register row, and the rows already written for it
retire"*. Its bounds are the ones this row measured: `LibKa0s` is vendored whole, profile defaults come
from `defaults/Profile.lua` rather than off the schema, and `tests/test_options_panel.lua` fingerprints
composed rows by their `order` field and pins the gap. Standard v2.65.0 (WS-02) has since replaced the
fall-together bound: on a library-absent load a host verb that writes a composed row writes through the
schema seam's `writeThrough` list or prints the library-absent line. KickCD takes route (a) for
`enabled` and `locked` (see [Slash commands](#slash-commands)), so those two composed paths are
addressable, and stored, there.

**Not in this table, and why.** The `KickCD<Widget><UnitTitleCase>` frame-naming notes at
[common-tasks.md](common-tasks.md) and the additive `GRID_LAYOUT` payload note at
[message-bus.md](message-bus.md) read as deviations but are not: they depart from *this addon's own*
conventions, not from a numbered rule in the standard, so neither has a `filename-§N` to cite and
neither belongs in a register of standards deviations. They stay where they are reasoned.

**Also not in this table:** `modules/Castbar_Debug.lua`'s pre-formatted debug lines (`:35`, `:91`,
`:94-95`, `:111`). `events-frames-taint-§8` now **scopes** its pre-formatting MUST to call sites whose
arguments can reach a value read from one of the APIs it names, and a SHOULD everywhere else. KickCD
uses none of the named APIs, and the one combat-protected value it does handle —
`current.notInterruptible` from `UnitCastingInfo`/`UnitChannelInfo` — is never formatted: those lines
build from its `type()` and from `issecretvalue()`'s boolean, and the `NINT_REPORT.boolean` arm is
reachable only when the type already *is* `boolean`. So the sites are permitted, not ratified
deviations, and there is nothing to record beyond this sentence.

### Files over the 1500-line cap

The `layout-§1` census: one row per authored `.lua` file the repo tracks that is over 1500 lines,
naming its terminal state (the issue that names the seam, the deviation row above that ratified it,
or the scheduled peel). `libs/` and `tests/_kit/` are vendored and not counted.
`tests/_kit/test_layout_cap.lua` holds this census against the tree in both directions.

Nothing is over the cap today.

## Load order

`KickCD.toc` is the source of truth. Order is dependency, not alphabetical:

1. `libs/` — vendored Ace3 + LibSharedMedia + LibCustomGlow + LibDataBroker-1.1 + LibDBIcon-1.0 (the last two after `CallbackHandler-1.0`, which both need; nothing fixes their order relative to `LibKa0s.xml`, which is why `LibKa0s-Launcher-1.0` resolves them at Register time rather than at load)
2. `locales/enUS.lua`
3. `core/Compat.lua` (hangs `NS.Compat` on the shared private `NS` table — WoW's addon vararg; `NS` is not `_G.KickCD`)
4. `core/EnvSetup.lua` (`LibKa0s-Env-1.0` seam — publishes `NS.Meta(field)` and `NS.Version()`: this addon's own TOC manifest, read in one place instead of three. Position is conventional rather than load-bearing — nothing here resolves at load, and both callers that resolve a version AT load sit far below it)
5. `core/PoolSetup.lua` (`LibKa0s-Pool-1.0` seam — publishes `NS.Pool`: `NewKeyed` / `AcquireKeyed` / `ReleaseAllKeyed` / `CountsKeyed`, the spellID-keyed widget pool `modules/IconGrid.lua` builds every instance's icon pool from. Adopted at the library's minor 2, which added the keyed members — minor 1's array-shaped `active` would have iterated nothing on release and leaked a widget per rebuild. Position is conventional: anywhere after the libs block and before `modules/IconGrid.lua`, its only caller. With the library absent it falls back to the same four members locally, keyed, rather than making the grid leak only on a broken install)
6. `core/MediaSetup.lua` (`LibKa0s-Media-1.0` seam — publishes `NS.Icon` and `NS.MediaFont` and registers the shipped faces with LibSharedMedia at load. **Load-bearing position**: it is ahead of `Constants` because `Const.FONT_MONO` is resolved from `NS.MediaFont` at file load)
7. `core/Constants.lua` (`NS.Const`)
8. `core/State.lua` (`NS.State`; the combat listener, an AceEvent target for `PLAYER_REGEN_*` / `PLAYER_LOGIN`, registered by `State.Arm` from `NS:OnInitialize`)
9. `core/Util.lua`
10. `core/CoreSetup.lua` (`LibKa0s-Core-1.0` descriptor — publishes the secret-safe, `NS.PREFIX`-tagged `NS.Util.print`, and `NS.LIBKA0S_MISSING`, the one cause clause the other five reading seams (`DebugLogSetup`, `PerfSetup`, `LauncherSetup`, `SchemaSetup`, `OptionsSetup`) append their own consequence to; after `Constants` for the prefix and after `Util` so the latter's table assignment can't replace it. It also loads ahead of every seam that reads the clause, which is why the clause lives here)
11. `core/DebugLogSetup.lua` (`LibKa0s-DebugLog-1.0` descriptor — publishes `NS.DebugLog` and binds the sink bare as `NS.Debug(tag, fmt, …)`)
12. `core/Units.lua` (`NS.Units`; unit identity + per-unit config resolution — loads after `Util`, before `Database`)
13. `core/Database.lua` (defines the Database class and the migration runner; the `units.target`/`units.focus` tree it assembles into AceDB's defaults is `defaults/Profile.lua`, read at call time because `# Defaults` loads after `# Core`; doesn't init the DB at file-load time)
14. `core/KickCD.lua` (`AceAddon-3.0:NewAddon(NS, "KickCD", ...)` promotes the private `NS` table in place — no `_G.KickCD` rebind)
15. `core/SpellInput.lua` (`NS.SpellInput` — the one add-a-spell resolver and the Cooldown Manager gate the Spells page and `/kcd spells add` share; calls `NS.NewBusTarget` at file load for its cache invalidator, so it sits directly below `core/KickCD.lua`)
16. `core/LauncherSetup.lua` (`LibKa0s-Launcher-1.0` descriptor — publishes `NS.Launcher`, the one LibDataBroker object behind the minimap button and the broker plugin. Position is conventional: nothing here resolves at load beyond `LibStub`, and its handlers reach `NS:OpenSettings`, `NS.SetMasterEnabled` and `NS.ToggleLock` at call time. It sits below `core/KickCD.lua` only so a reader meets the lock switch before the button that drives it; `NS:OnEnable` is what calls `Register()`)
17. `core/LifecycleSetup.lua` (`LibKa0s-Lifecycle-1.0` descriptor — publishes `NS.Lifecycle`, `NS.IsDown`, `NS.MasterEnabled` and `NS.RefreshEnabledHold`, the stand-down latch both `disable` and the perf harness take a hold on. **Above `core/PerfSetup.lua`**, which passes the latch into its descriptor at load and raises at `:New` without it, and below `core/CoreSetup.lua` for the printer. Everything else it touches — the modules it stands down — it resolves at call time)
18. `core/PerfSetup.lua` (`LibKa0s-Perf-1.0` descriptor — publishes `NS.Perf`, backing `/kcd perf`. **Last** in the core block: it needs `NS.Util.print`, the debug-log sink, and `NS.VERSION`, and it must precede every module that takes `local Perf = NS.Perf` as a load-time upvalue)
19. `defaults/Profile.lua` (sets `NS.C` / `NS.DEFAULT_PROFILE` — the profile defaults tree, and the only place a profile default is hardcoded, `savedvariables-§2`)
20. `defaults/Spells.lua` (sets `NS.DefaultSpells`)
21. `modules/Cooldowns.lua` → `modules/IconGrid.lua` (per-unit instance manager) → `modules/IconGrid_Layout.lua` (peeled: anchor/grow parsing + block geometry) → `modules/IconGrid_Render.lua` (peeled: per-icon widget rendering, curves, cooldown-text ticker) → `modules/Castbar.lua` (per-unit instance manager) → `modules/Castbar_Handle.lua` (peeled: the cast bar's drag strip, `LibKa0s-Widgets-1.0`'s `DragHandle` published back as `Castbar.BuildHandle`) → `modules/Castbar_Skin.lua` (peeled: the config-driven `Castbar:Reskin` — sizing, orientation, insets, spark, fonts, text anchors, per-state textures/colors/borders) → `modules/Castbar_Debug.lua` (peeled: the `Castbar:DebugDump(unit)` diagnostic behind `/kcd debug castbar`, re-opening the already-registered module) → `modules/UnitLabel.lua` (per-unit instance manager; one identity FontString per unit, `SetPoint`-anchored to that unit's `IconGrid` or `Castbar` frame) → `modules/Diagnostics.lua` (the sections of `/kcd diagnostics`, read by the library's report helper at run time). `modules/IconGrid.lua` was split into three flat siblings (`IconGrid` / `IconGrid_Layout` / `IconGrid_Render`), and `Reskin`, `DebugDump` and the drag strip peeled off `Castbar.lua`, to stay under the 1500-LOC cap.
22. `settings/Slash.lua` (`LibKa0s-Slash-1.0` descriptor — the `/kcd` dispatcher and schema CLI; loads after `core/KickCD.lua` has defined `NS.COMMANDS`, which is passed in) → `settings/OptionsSetup.lua` (`LibKa0s-Options-1.0` descriptor — **is** `NS.Settings.Helpers`, decorated in place by the three `Panel*` files; must precede every `settings/<page>.lua`, which call `Helpers.LSMValues` / `Helpers.AnchorValues` inside schema-row literals at file load) → `settings/Panel.lua` → `settings/Panel_Widgets.lua` → `settings/Panel_Render.lua` → `settings/{General, Icons, Castbar, Label, Spells, Profiles}.lua` (the two `Panel_*` siblings were peeled from `Panel.lua` to stay under the 1500-LOC cap — KCD-24; they must load before the per-tab files that call the makers / renderers)

`NS:OnInitialize` (Ace lifecycle on `ADDON_LOADED`) builds the AceDB instance, runs the five shape-driven migrators unconditionally (`Database:FoldLegacyUnits` → `Database:BackfillLabelStyle` → `Database:MigrateSpecKeys` → `Database:MigrateColorShape` → `Database:MigrateFontFlags`, again on every `OnProfileChanged`) then the version ladder `Database:MigrateProfile` (`CURRENT_DB_VERSION = 5`, declared default 0; registered pure steps v1→v2 `FoldLegacyUnits`, v2→v3 `MigrateSpecKeys`, v3→v4 `MigrateColorShape`, v4→v5 `MigrateFontFlags`, the stamp advancing only past a step that returned without raising), and seeds spells on first profile creation. `<Module>:OnEnable` calls `ReconcileUnits()`, which registers messages and game events **per currently-enabled unit** (target by default; focus only if `units.focus.enabled`). `NS:OnEnable` — which AceAddon fires at `PLAYER_LOGIN` — calls `NS.CreateOptionsPanel()` once, which is where the library registers the Blizzard category and drains its page-builder queue, so per-tab builders run with their full schema available. Full lifecycle in [module-map.md](module-map.md#aceaddon-lifecycle).
