# Architecture

Orient-yourself map for **Ka0s KickCD**. Tracks the player's interrupt and CC cooldowns and surfaces them on a movable icon grid, with a sibling cast bar — for both the player's target and focus unit — driven from the same drag lock and visibility mode. Target client: WoW 12.0.7 (Midnight). 12.0-aware throughout — the cast bar was originally removed at commit `59fb5c0` and re-added with explicit secret-value gating; see [scope.md](scope.md#cast-bar-removal-history).

This file is the high-level index; topic detail lives in `docs/`.

## What it does

Two UI widgets, each tracked for **two enemy units — target and focus** — sharing one configuration model:

- **Icon grid** — pooled per-spell icon buttons with per-icon ready glow (LibCustomGlow), placed by an orthogonal anchor + grow + dimensions model (13 anchor points × 8 grow directions × free row/col dims). Visual states (ready / cooldown / GCD-suppressed) drive C-side curves so the GCD-vs-real-CD filter never compares secret-tainted remaining time in Lua.
- **Cast bar** — mirrors its unit's cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration`. Stacked dual `StatusBar`s + per-state borders are alpha-curve-switched on the cast's secret `notInterruptible` bool via `C_CurveUtil.EvaluateColorValueFromBoolean`, so per-state appearance is rendered without the addon ever inspecting the protected boolean from Lua.

Both widget types render **the same player cooldowns** (the tracked spell list is player-centric, not unit-specific) against each enabled unit's own cast state — `modules/IconGrid.lua` and `modules/Castbar.lua` are per-unit **instance managers**: `instances[unit]` holds one live frame set per enabled unit (target and focus both enabled by default). Target keeps the legacy global frame names (`KickCDIconGrid`, `KickCDCastbar`); focus gets the suffixed `KickCDIconGridFocus` / `KickCDCastbarFocus`. A focus unit can **link** to target's appearance (`units.focus.link`, default on) so it mirrors target's `icons`/`castbar` styling live; position and the optional identity label stay per-unit even while linked. See [core/Units.lua](../core/Units.lua) (`NS.Units`) for the single place link resolution happens, and [schema.md](schema.md#unitsunit-shape) for the DB shape.

Both widgets honor the master enable, **plus their own unit's per-unit `enabled` toggle**, the shared lock (`db.profile.locked`), and the addon-wide visibility mode (`db.profile.visibility`: `always` / `in_combat` / `target_casting` / `target_casting_interruptible`) — **one lock and one visibility mode still cover both units**, evaluated per-unit against that unit's own cast state. The `_interruptible` mode uses a two-step gate (Show on hostile cast, alpha-mask uninterruptible via `SetAlphaFromBoolean`) because the underlying flag can't be compared in Lua under 12.0.

Each unit can also show a single configurable identity label (`units.<unit>.label`), rendered by `modules/UnitLabel.lua` — a per-unit instance manager, mirroring `IconGrid`/`Castbar`'s pattern, that owns one `FontString` per unit in a holder frame parented to `UIParent` (`KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`) and `SetPoint`-anchors it to that unit's chosen widget (`label.style.attach`: cast bar or icon grid). Only `text` stays per-unit while linked (`NS.Units.Label`); both `show` (`NS.Units.LabelShow`) and `label.style` (position, font, justify, rotation, color — `NS.Units.LabelStyle`) follow the Focus link like `icons`/`castbar` do. See [schema.md](schema.md#unitsunitlabelstyle-shape).

An on-screen debug console (`LibKa0s-DebugLog-1.0`, wired in `core/DebugLogSetup.lua`, toggled with `/kcd debug`) surfaces internal state. Debug logging is gated on the session-only `NS.State.debug` flag — it is never persisted and resets on every `/reload`. The console and the `/kcd perf` step panel are the **library's** windows and wear the **shared Ka0s window edge** (`Core.SKIN` applied by `Core.ApplySkin`: a flat 1px black outer border, a 1px light-gray highlight synthesized inside it, a gold title, a gray divider) — this addon passes neither `applySkin` nor `makeCloseButton`, so both track the library and stay identical to their counterparts in the sibling Ka0s addons. The addon's own on-screen widgets — the icon grids, cast bars and unit labels in `modules/` — are not windows and carry no Ka0s edge; their look is entirely profile-driven (`modules/Castbar_Skin.lua`, `modules/IconGrid_Render.lua`). Don't reach for `Core.SKIN` there.

## Subsystems at a glance

```
WoW events ─▶ Cooldowns:Refresh ─▶ Ka0s_KickCD_SPELL_STATE ─▶ IconGrid instances[target]:OnSpellState
                                                           └─▶ IconGrid instances[focus]:OnSpellState (if enabled)
                                                           └─▶ alpha/tint curves (C-side)
                                                           └─▶ SetCooldownFromDurationObject

PLAYER_TARGET_CHANGED / FOCUS_CHANGED ─▶ Castbar instances[unit]:Reevaluate ─▶ Compat.GetCastingInfo(unit)
UNIT_SPELLCAST_* (unit-filtered)                                             └─▶ UnitCastingDuration/UnitChannelDuration
                                                                              └─▶ ApplyState (curve-switched on secret notInterruptible)

Settings widget / slash CLI ─▶ Helpers.Set ─▶ Ka0s_KickCD_CONFIG_CHANGED ─▶ IconGrid + Cooldowns + Castbar
                                              (section incl. "units" ─▶ ReconcileUnits on both)
AceDB profile change         ─▶                Ka0s_KickCD_PROFILE_CHANGED ─▶ same
IconGrid instances[unit]:Layout ─▶             Ka0s_KickCD_GRID_LAYOUT { unit, ... } ─▶ Castbar instances[unit] (re-anchor / auto-size)

  AceDB (all chars share the "Default" profile; user-switchable)  ──  6-tab settings panel + /kcd CLI
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
| Cast bar (stacked dual widgets, Reskin/RenderCast split, anti-patterns) | `modules/Castbar.lua`, `modules/Castbar_Skin.lua` | [castbar.md](castbar.md) |
| Schema-driven canvas-layout settings panel; widget primitives; validation | `settings/Panel.lua`, `settings/Panel_Widgets.lua`, `settings/Panel_Render.lua`, `settings/{General,Icons,Castbar,Label,Spells,Profiles}.lua` | [settings-panel.md](settings-panel.md) |
| Slash dispatch tables and command catalog | `core/KickCD.lua` | [slash-dispatch.md](slash-dispatch.md) |
| End-to-end smoke tests (cold install, visibility modes, lock/drag, cast bar, spec/talent/pet, profiles, secret values) | — | [smoke-tests.md](smoke-tests.md) |
| Slash-command + debug coverage matrices (what each command produces) | — | [testing.md](testing.md) |
| Performance instrumentation: the buckets, the offline scenarios, the in-game A/B and suspend | `core/PerfSetup.lua`, `tests/perf.lua` | [performance.md](performance.md), [perf-runs/README.md](perf-runs/README.md) |
| Code style, saved-variable boundary, `_G.X` vs bare X | every module | [common-tasks.md](common-tasks.md) |
| Scope, defaults source (Baratus sheet), cast-bar removal history | — | [scope.md](scope.md) |

## Namespace, naming, and the module publishing pattern

Every module is built on the **private addon namespace** — the vararg WoW hands each file. There is no `_G.KickCD` and no `KickCD = KickCD or {}` bootstrap:

```lua
local addonName, NS = ...
NS.Foo = NS.Foo or {}
local F = NS.Foo
```

- Every source file opens with `local addonName, NS = ...`; `NS` is the shared private table.
- Never overwrite an existing `NS.Foo` without `or {}` — another file may have reached it first, and never shadow it with a file-local of the same name.
- The public API hangs off `F` (or `NS.Foo` directly); helpers stay `local` to the file.
- `core/KickCD.lua` calls `LibStub("AceAddon-3.0"):NewAddon(NS, "KickCD", …)` and **discards the return**: `NewAddon` promotes the table it is handed, so the return is that same `NS`. There is no `_G.KickCD = addon` rebind and no `NS.addon` self-reference — later files get `NS` from their own header, not from `GetAddon`. `core/Compat.lua` simply hangs `NS.Compat` on the shared `NS` at TOC load time.

**Naming.** The display name in the addon list and Settings panel is `Ka0s KickCD` (the colored `## Title` in `KickCD.toc`). Everything machine-facing stays unprefixed `KickCD` for ergonomics: the folder, the addon id, the slash commands, the saved-variable namespace (`KickCDDB`), and the global frame names (`KickCDIconGrid`, `KickCDCastbar`, `KickCDDebugWindow`, and the `…Focus` siblings).

## Invariants worth not breaking

- **Closed message bus.** The five AceEvent messages (`Ka0s_KickCD_SPELL_STATE`, `Ka0s_KickCD_CONFIG_CHANGED`, `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_GRID_LAYOUT`, `Ka0s_KickCD_COMBAT_STATE`) are the only inter-module communication channel. Every message has exactly one **owning module**, and the two with many announcing paths reach the bus through a single named emitter in that module: `Ka0s_KickCD_CONFIG_CHANGED` only via `settings/Panel.lua`'s `Helpers.FireConfigChanged` (any schema-row write, the lock/unlock toggle, drag-stop anchor saves, the focus link/copy-styling buttons, debounced spell edits — the session-only debug toggle is off-bus), and `Ka0s_KickCD_PROFILE_CHANGED` only via `core/Database.lua`'s file-local `fireProfileChanged` (the AceDB callback, and `Database:ResetAllSpells`, which re-seeds every spec's list in place and so needs the same full-rebuild fan-out without an actual AceDB profile swap). Both therefore have a single `SendMessage` site. `Ka0s_KickCD_SPELL_STATE` (three sites) and `Ka0s_KickCD_GRID_LAYOUT` (two) still have several, but all of them sit inside the one module that owns the message, which is what `architecture-§4` requires; a cross-module `SendMessage` is the defect. Adding a message requires updating the owning emitter, every consumer, and [message-bus.md](message-bus.md).
- **`Compat` is API normalization only.** No feature decisions, no shared mutable state, no visibility helpers. Visibility decisions live in `core/State.lua`; shared mutable state lives in `core/State.lua`; shared magic numbers live in `core/Constants.lua`.
- **12.0 secret values get C-side handling, not Lua-side detox.** Pass duration-object methods, `notInterruptible`, `name`, `texture` straight into Blizzard C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`). Never bind to a Lua local for compare / format / tostring / arithmetic. `securecallfunction` / `tonumber` / `+0` "detox" were tried and don't work.
- **`NS.Settings.Schema` is the single source of truth.** UI widget, slash CLI (`get` / `set` / `list`), per-panel `Defaults` button, and the General → "Reset all settings" reset all wire from one row. Don't add parallel mutators for fields with a schema row. The `valueGate` mechanism enforces cross-row dependencies (e.g. `units.<unit>.castbar.growDirection` ↔ `units.<unit>.castbar.orientation`).
- **Colors are stored keyed, dropdowns are keyed hashes.** A color value is `{ r =, g =, b =, a = }` — the shape `LibKa0s-Slash-1.0` / `-Options-1.0` parse into and render from, so no host-side codec sits between them (the old positional `{r,g,b,a}` array migrated in `Database:MigrateColorShape`, the v3→v4 step). Dropdown `values` are keyed hashes with a sibling `sorting` array. Every color row carries `hasAlpha`; every schema row carries `desc` (not `tooltip`), `panel` and `section`.
- **One drag lock + one visibility mode shared across both UI pieces — PRESERVED across target/focus dual tracking.** The icon grid and the cast bar both read `db.profile.locked` and `db.profile.visibility`; one unlock/lock cycle moves every enabled unit's frames. Visibility is evaluated per-unit against that unit's own cast state (a focus grid hides/shows independent of whether target is casting), but the *mode* itself — and the lock — stay addon-wide, not per-unit. Don't introduce per-widget (or per-unit) lock or visibility-mode state; `scale`/`alpha` similarly stay addon-wide (per-unit scale/alpha was considered and deferred, not shipped).
- **`NS.State.inCombat` is the combat flag, not `InCombatLockdown()`.** A bootstrap CreateFrame in `core/State.lua` is the only file that registers `PLAYER_REGEN_DISABLED/_ENABLED/PLAYER_LOGIN`; it maintains the flag and fans the transition out via `Ka0s_KickCD_COMBAT_STATE` so subscribers (IconGrid, Castbar) see an explicit ordered signal. `InCombatLockdown()` lags the regen events by a frame and is unreliable.
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
- LibKa0s (the Ka0s shared library — `Core`, `DebugLog`, `Perf`, `Slash`, `Options` are adopted here, one setup file each: `core/CoreSetup.lua`, `core/DebugLogSetup.lua`, `core/PerfSetup.lua`, `settings/Slash.lua`, `settings/OptionsSetup.lua`). **Never edit `libs/LibKa0s`** — a library problem is fixed upstream in `../LibKa0s` and re-vendored. The gate is two diffs, not one: `diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s` MUST be empty (content), and the plain `diff -r` SHOULD be (bytes). A byte-only difference is a line-ending divergence, not a fork — renormalize the side that drifted, never edit `libs/`. Each setup file owns only what is genuinely this addon's — the tag, the verb table, the schema adapters — and a descriptor gap you can close *inside* the setup file is not a library change: say so in a comment there rather than forking the library. Every setup file degrades to a stub when the library is missing rather than erroring at load, and all five explain the absence through **one shared cause clause**, `NS.LIBKA0S_MISSING` (defined in `core/CoreSetup.lua`, outside its own `if not lib` branch because the seams that read it are reached on both paths). Each seam appends its own "so &lt;what&gt; is unavailable", so a degraded install says the same thing about *why* five times and a different thing about *what* each time — and says it identically to AbsorbTracker and ConsumableMaster, which is the point.
- LibSharedMedia-3.0
- AceGUI-3.0-SharedMediaWidgets (vendored upstream r65; provides the `LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` dropdowns used by the Cast bar / Icons panels). `core/LSMPatch.lua` is an in-tree fixup that hides the 42×42 Border `displayButton` preview tile and re-anchors the dropdown bar; lives in addon code so future lib refreshes don't blow it away.
- LibCustomGlow-1.0

Seven unused Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab, AceTimer) were deleted from `libs/`. AceTimer-3.0 went last (KCD-29): `library-stack-§1` lists it among the mandatory Ace3 libs, but `library-stack-§3` says vendor only what the addon actually `LibStub`s — and scheduling here is `C_Timer.After` throughout, so nothing ever loaded it. §3 won.

`KickCD.toc`'s `## Interface:` line targets the Midnight client.

## Message bus

Five `AceEvent` messages are the only inter-module communication channel — modules never call each other directly across boundaries. Full payload semantics in [message-bus.md](message-bus.md).

| Message | Sender(s) | Consumers | Payload |
|---|---|---|---|
| `Ka0s_KickCD_SPELL_STATE` | `Cooldowns:Rebuild` / `:Refresh` | `IconGrid` (every enabled unit instance) | `{ spellID, ready, isActive, cdObject, chargeCdObject, charges }` |
| `Ka0s_KickCD_CONFIG_CHANGED` | **One sender**: `settings/Panel.lua` `Helpers.FireConfigChanged`. Everything that wants to announce a config change calls it — `Helpers.Set`, `Panel_Render`'s reset/focus-link/copy helpers, `core/KickCD.lua`'s lock toggle and spells commit, the Spells editor's throttled commit, and IconGrid / Castbar `OnDragStop` | `IconGrid`, `Cooldowns`, `Castbar`, `UnitLabel`, Spells panel | `{ section }` — section ∈ `general`\|`icons`\|`castbar`\|`label`\|`spells`\|`units` |
| `Ka0s_KickCD_PROFILE_CHANGED` | **One sender**: `core/Database.lua`'s file-local `fireProfileChanged`, called by `Database:OnProfileChanged` (swap / copy / reset) and `Database:ResetAllSpells` | `IconGrid`, `Cooldowns`, `Castbar`, `UnitLabel`, Spells panel | `{ newProfileKey }` |
| `Ka0s_KickCD_GRID_LAYOUT` | `IconGrid:Layout`, once per unit instance | `Castbar` (filters on `payload.unit`), `UnitLabel` (re-applies every unit; cheap `ApplyAll`, no per-unit filter) | `{ unit, gridFrame, primaryIcon, width, height }` |
| `Ka0s_KickCD_COMBAT_STATE` | `core/State.lua` bootstrap frame | `IconGrid`, `Castbar` | `{ inCombat }` |

Receivers each register on their **own** AceEvent target: AceAddon modules use their module `self`; the Spells settings panel uses a private target from `NS.NewBusTarget()`. None register on the shared addon object.

## Slash commands

`/kcd` and `/kickcd` are aliases. The dispatch table (`NS.COMMANDS` in `core/KickCD.lua`) is sender-authoritative for the top-level verbs:

| Command | What it does |
|---|---|
| `help` | List available commands |
| `version` | Print the addon version |
| `config` | Open the settings panel |
| `lock` | Lock the icon grid in place |
| `unlock` | Unlock the icon grid for dragging |
| `toggle` | Toggle the icon grid lock state |
| `list` | List every setting and its current value |
| `get <path>` | Print a setting's current value |
| `set <path> <value>` | Set a setting (try `/kcd list`) |
| `perf` | Guided A/B performance capture (`LibKa0s-Perf-1.0`), driven from a clickable step panel |
| `reset <path>` | Reset one setting to its default. Page-scoped reset lives on each panel's **Defaults** button; the every-spec spell rebuild moved to `/kcd spells resetall` |
| `resetall` | Reset every schema-driven panel and every spec's spell list to defaults |
| `resetposition` | Restore the icon grid to its default screen position |
| `spells` | Spell-list editor (try `/kcd spells` for the list) |
| `debug` | Debug subcommands (try `/kcd debug` for the list) |

`/kcd debug` sub-verbs (`DEBUG_COMMANDS`): `window`, `on`, `off`, `toggle`, `spells`, `castbar`, `interrupt`. Bare `/kcd debug` toggles the console window.

## Settings schema

`NS.Settings.Schema` is the single source of truth for every option. Each row wires automatically into its UI widget, `/kcd get|set|list` coverage, and the per-panel `Defaults` reset (plus the General → "Reset all settings" reset) — so adding a setting is one schema row, never a parallel mutator. Detail in [settings-panel.md](settings-panel.md). `Helpers.ValidateSchema` returns the count of malformed rows (0 when healthy), runs at panel-register time, and is unit-tested.

## Event subscriptions

Game-event registration is deliberately partitioned by module (specifics in [module-map.md](module-map.md)):

- **`core/State.lua` bootstrap frame** — the only registration of `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` / `PLAYER_LOGIN`; owns the `NS.State.inCombat` flag and fans transitions out via `Ka0s_KickCD_COMBAT_STATE`.
- **`Cooldowns`** — `SPELL_UPDATE_COOLDOWN` / `_USABLE` / `_CHARGES` (coalesced through a `Util.Throttle(0)` so a same-frame burst yields one `Refresh`/frame), `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`.
- **`IconGrid`** — `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START` / `_STOP` / `_FAILED` / `_INTERRUPTED` / `_CHANNEL_START` / `_CHANNEL_STOP` / `_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE`) registered through `Util.RegisterUnitCastEvent` (dispatches only when the event's unit matches the instance's unit), plus the four inbound `Ka0s_KickCD_*` messages. Registration is enable-gated per instance: a disabled unit's instance is not built and does not register anything.
- **`Castbar`** — the `UNIT_SPELLCAST_*` family registered per instance through `Util.RegisterUnitCastEvent` (unit-filtered dispatch: a focus instance only reacts to focus casts), plus `PLAYER_TARGET_CHANGED` / `PLAYER_FOCUS_CHANGED` and its inbound messages.
- **`UnitLabel`** — `PLAYER_ENTERING_WORLD` plus its three inbound `Ka0s_KickCD_*` messages (`CONFIG_CHANGED` / `PROFILE_CHANGED` / `GRID_LAYOUT`). No cast-event or combat registration — the label has no state of its own beyond what those messages already trigger a re-`Apply` for.

## Taint notes

Under 12.0, `C_Spell.GetSpellCooldown` timing returns and `UnitCastingInfo` / `UnitChannelInfo` `notInterruptible` / `name` / `texture` come back **secret** in combat for protected interrupts. Secret values must be passed straight into Blizzard C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`) — never bound to a Lua local for compare / format / `tostring` / arithmetic, which errors in tainted scope. Visibility and interruptibility decisions that depend on `notInterruptible` go through the two-step gate `State.IsHostileUnitCasting` (show) + `State.ApplyInterruptibleAlpha` (filter). Full pattern catalog in [midnight-quirks.md](midnight-quirks.md).

## Known limitations

- English (`enUS`) only.
- Retail / Midnight only — a single `## Interface` line, no Classic support.
- No automated in-client tests — headless unit tests plus manual in-game smoke tests only (see [smoke-tests.md](smoke-tests.md)).
- Debug logging is session-only (`NS.State.debug`) and resets on every `/reload`.

## Documentation map

Every `.md` under `docs/` appears in exactly one table below (`documentation-§3`). Frozen and
generated directories are named once each and never enumerated per run: `docs/audits/`, `docs/reviews/`, `docs/automated-tests/`, `docs/superpowers/`, `docs/perf-runs/`.

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
| `slash-dispatch.md` | Present | 15 verbs in `NS.COMMANDS`, with `debug` and `spells` subcommand trees |
| `midnight-quirks.md` | Present | The 12.0 secret-value rules and the cast-info shims |
| `compat-layer.md` | Present | `core/Compat.lua` is 490 lines of addon-specific shimming beyond LibKa0s |
| `message-bus.md` | Present | The addon’s message contract, kept in sync with each module’s header |
| `profiles.md` | Present | AceDB profiles are user-visible — the Profiles settings page |
| `debug.md` | Not applicable | The console is `LibKa0s-DebugLog-1.0`’s; the `/kcd debug` subcommands dump state through it rather than adding a surface |
| `perf-runs/README.md` | Present | The performance harness is wired (`core/PerfSetup.lua`) |

### Verification and record

| Doc | Covers |
|---|---|
| `testing.md` | How to run the harness and lint; the green commit gate |
| `smoke-tests.md` | The in-game smoke-test suite |
| `test-cases.md` | The generated case inventory (authoritative pass count) |
| `performance.md` | The addon performance page |
| `automated-tests/README.md` | What the automated-test record is and how to produce it |
| `automated-tests/RESULTS.md` | One row per run; generated, never hand-edited |

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
| `savedvariables-§1` | Two profile migrators run off the **stored shape**, not off `db.global.schemaVersion`. `schemaVersion` and a migration function both exist as the rule requires; these two run beside them, ungated. | A bare `schemaVersion` bump cannot distinguish "pre-`label.style`" from "current", because AceDB's `copyDefaults` has already written the new sub-table into the stored profile before any migrator looks — the same masking trap `FoldLegacyUnits` was written around. Reasoned at [schema.md](schema.md#L212). | 2026-07-16 | An AceDB release where `copyDefaults` no longer backfills before migration runs, **or** a third shape addition under an existing profile field — either makes a version-gated migrator sufficient and retires both shape-driven ones. |
| `savedvariables-§1` | `DEFAULT_PROFILE` was **restructured** — target/focus nested under `units.<unit>` — rather than only grown, departing from the "a profile shape never changes shape, only grows" expectation the section's example implies. | Target and focus each need independently customizable `icons`/`castbar`; the flat alternative (`icons`, `focusIcons`, `castbar`, `focusCastbar`, …) does not scale to a third unit and duplicates the anchor/label bookkeeping. The shape-driven migration above is the mitigation that makes it safe for existing installs. Reasoned at [schema.md](schema.md#L222). | 2026-07-15 | A third tracked unit is added — at which point the nested shape is load-bearing rather than a departure, and this row retires. |
| `options-ui-§1` | `Helpers.LSMValues` / `Helpers.AnchorValues` / `Helpers.AnchorOrder` stay the **host's own** code in `settings/Panel.lua`, shadowing the library's published `O.LSMValues`, rather than being read off the instance like every other member. | `settings/Icons.lua` and `settings/Castbar.lua` evaluate these inside schema-row literals **at FILE LOAD**. Were they instance members, the LibKa0s-absent stub would have to publish them or the page files raise, the rows never register, and a large part of `NS.Settings.Schema` goes missing — taking `/kcd list|get|set|reset` and the profile defaults with it, silently. Keeping them host-side is what lets the degraded stub need **zero** load-time members. The library's `O.LSMValues` is also not a drop-in: it returns a deferred **closure** where the host's returns a **table**, and falls back to `STRINGS.LSM_NONE` ("None") where the host's uses `"Default"`. Measured, not assumed, and reasoned in full at [../settings/OptionsSetup.lua](../settings/OptionsSetup.lua) — the measurement is gated by `tests/test_options_panel.lua`, which loads the addon with the library absent and pins `#NS.Settings.Schema`. | 2026-08-05 | Any KickCD page file stops evaluating these inside a schema-row literal at file load — at which point the load-completing constraint is gone and all three move onto the instance. The pinning case in `tests/test_options_panel.lua` is what makes that visible. |
| `events-frames-taint-§8` | `core/Compat.lua`'s `/kcd debug interrupt` dump carries its own value renderer (`safeRender` at `:373-381`, used by `describe` at `:387-390`) beside the library's `NS.SafeToString`, which `core/CoreSetup.lua` publishes. The section's closing line makes a second stringifier the deviation, and option (a)'s scoping of the pre-formatting MUST does not touch it. | It is not the printer seam's stringifier and nothing routes through it to reach chat. It renders a diagnostic **value column** — `%q`-quoted strings, `<table>`/`<function>` for a non-scalar, printed beside that value's `type=` and `isSecret=` — which is a dump's cell, not a chat line's argument, and which `SafeToString` does not produce and should not learn to. Its detection is `issecretvalue()`, the engine's own predicate: that is what §8's `table.concat` probe exists to approximate where the predicate is unavailable, not the `..` probe §8 forbids. Every value reaching `describe`'s `string.format` has already been through `safeRender`, so the dump cannot raise on a secret. | 2026-08-05 | `LibKa0s-Core-1.0` publishes a diagnostic value renderer (a `Describe` / `RenderValue`), **or** `safeRender` gains a caller outside the `/kcd debug interrupt` dump — either makes the local copy redundant and retires this row. |
**Not in this table, and why.** The `KickCD<Widget><UnitTitleCase>` frame-naming notes at
[common-tasks.md](common-tasks.md) and the additive `GRID_LAYOUT` payload note at
[message-bus.md](message-bus.md) read as deviations but are not: they depart from *this addon's own*
conventions, not from a numbered rule in the standard, so neither has a `filename-§N` to cite and
neither belongs in a register of standards deviations. They stay where they are reasoned.

**Also not in this table:** `modules/Castbar_Debug.lua`'s pre-formatted debug lines (`:35`, `:82`,
`:85-86`, `:102`). `events-frames-taint-§8` now **scopes** its pre-formatting MUST to call sites whose
arguments can reach a value read from one of the APIs it names, and a SHOULD everywhere else. KickCD
uses none of the named APIs, and the one combat-protected value it does handle —
`current.notInterruptible` from `UnitCastingInfo`/`UnitChannelInfo` — is never formatted: those lines
build from its `type()` and from `issecretvalue()`'s boolean, and the `NINT_REPORT.boolean` arm is
reachable only when the type already *is* `boolean`. So the sites are permitted, not ratified
deviations, and there is nothing to record beyond this sentence.

One thing the scoping does **not** relax, and it is still open: `modules/Castbar_Debug.lua:125` binds
`local print = NS.Util and NS.Util.print or _G.print`. §8's prohibition on the global `print()` for
user-facing output is unqualified — it is about the missing `NS.PREFIX` tag, not about secrets. The
fallback arm is unreachable today (`core/CoreSetup.lua` defines `Util.print` on **both** the
library-present and library-absent paths, so `NS.Util.print` is never nil), which is why it grades
Info rather than a live defect — but it is dead code that reads as a sanctioned escape hatch, and it
should go the next time that file is touched.

## Load order

`KickCD.toc` is the source of truth. Order is dependency, not alphabetical:

1. `libs/` — vendored Ace3 + LibSharedMedia + LibCustomGlow
2. `locales/enUS.lua`
3. `core/Compat.lua` (hangs `NS.Compat` on the shared private `NS` table — WoW's addon vararg; `NS` is not `_G.KickCD`)
4. `core/Constants.lua` (`NS.Const`)
5. `core/State.lua` (`NS.State`; bootstrap CreateFrame for `PLAYER_REGEN_*` / `PLAYER_LOGIN`)
6. `core/Util.lua`
7. `core/CoreSetup.lua` (`LibKa0s-Core-1.0` descriptor — publishes the secret-safe, `NS.PREFIX`-tagged `NS.Util.print`, and `NS.LIBKA0S_MISSING`, the one cause clause the other four seams append their own consequence to; after `Constants` for the prefix and after `Util` so the latter's table assignment can't replace it. It is also the **first** of the five seams the TOC loads, which is why the clause lives here)
8. `core/DebugLogSetup.lua` (`LibKa0s-DebugLog-1.0` descriptor — publishes `NS.DebugLog` and binds the sink bare as `NS.Debug(tag, fmt, …)`)
9. `core/Units.lua` (`NS.Units`; unit identity + per-unit config resolution — loads after `Util`, before `Database`)
10. `core/Database.lua` (defines the Database class and the migration runner; the `units.target`/`units.focus` tree it assembles into AceDB's defaults is `defaults/Profile.lua`, read at call time because `# Defaults` loads after `# Core`; doesn't init the DB at file-load time)
11. `core/LSMPatch.lua` (one-shot `PLAYER_LOGIN` fixup wrapping the vendored `LSM30_Border` widget — hides its misaligned 42×42 `displayButton` preview tile and re-anchors the dropdown bar; kept in addon code so a lib refresh can't blow it away)
12. `core/KickCD.lua` (`AceAddon-3.0:NewAddon(NS, "KickCD", ...)` promotes the private `NS` table in place — no `_G.KickCD` rebind)
13. `core/PerfSetup.lua` (`LibKa0s-Perf-1.0` descriptor — publishes `NS.Perf`, backing `/kcd perf`. **Last** in the core block: it needs `NS.Util.print`, the debug-log sink, and `NS.VERSION`, and it must precede every module that takes `local Perf = NS.Perf` as a load-time upvalue)
14. `defaults/Profile.lua` (sets `NS.C` / `NS.DEFAULT_PROFILE` — the profile defaults tree, and the only place a profile default is hardcoded, `savedvariables-§2`)
15. `defaults/Spells.lua` (sets `NS.DefaultSpells`)
16. `modules/Cooldowns.lua` → `modules/IconGrid.lua` (per-unit instance manager) → `modules/IconGrid_Layout.lua` (peeled: anchor/grow parsing + block geometry) → `modules/IconGrid_Render.lua` (peeled: per-icon widget rendering, curves, cooldown-text ticker) → `modules/Castbar.lua` (per-unit instance manager) → `modules/Castbar_Skin.lua` (peeled: the config-driven `Castbar:Reskin` — sizing, orientation, insets, spark, fonts, text anchors, per-state textures/colors/borders) → `modules/Castbar_Debug.lua` (peeled: the `Castbar:DebugDump(unit)` diagnostic behind `/kcd debug castbar`, re-opening the already-registered module) → `modules/UnitLabel.lua` (per-unit instance manager; one identity FontString per unit, `SetPoint`-anchored to that unit's `IconGrid` or `Castbar` frame). `modules/IconGrid.lua` was split into three flat siblings (`IconGrid` / `IconGrid_Layout` / `IconGrid_Render`), and both `Reskin` and `DebugDump` peeled off `Castbar.lua`, to stay under the 1500-LOC cap.
17. `settings/Slash.lua` (`LibKa0s-Slash-1.0` descriptor — the `/kcd` dispatcher and schema CLI; loads after `core/KickCD.lua` has defined `NS.COMMANDS`, which is passed in) → `settings/OptionsSetup.lua` (`LibKa0s-Options-1.0` descriptor — **is** `NS.Settings.Helpers`, decorated in place by the three `Panel*` files; must precede every `settings/<page>.lua`, which call `Helpers.LSMValues` / `Helpers.AnchorValues` inside schema-row literals at file load) → `settings/Panel.lua` → `settings/Panel_Widgets.lua` → `settings/Panel_Render.lua` → `settings/{General, Icons, Castbar, Label, Spells, Profiles}.lua` (the two `Panel_*` siblings were peeled from `Panel.lua` to stay under the 1500-LOC cap — KCD-24; they must load before the per-tab files that call the makers / renderers)

`NS:OnInitialize` (Ace lifecycle on `ADDON_LOADED`) builds the AceDB instance, runs the three shape-driven migrators unconditionally (`Database:FoldLegacyUnits` → `Database:BackfillLabelStyle` → `Database:MigrateSpecKeys`) then the version-gated scaffold `Database:MigrateProfile` (`CURRENT_DB_VERSION = 4`; registered steps v1→v2 `FoldLegacyUnits`, v2→v3 `MigrateSpecKeys`, v3→v4 `MigrateColorShape`), and seeds spells on first profile creation. `<Module>:OnEnable` calls `ReconcileUnits()`, which registers messages and game events **per currently-enabled unit** (target by default; focus only if `units.focus.enabled`). `PLAYER_LOGIN` defers the Settings category registration so per-tab builders can run with their full schema available. Full lifecycle in [module-map.md](module-map.md#aceaddon-lifecycle).
