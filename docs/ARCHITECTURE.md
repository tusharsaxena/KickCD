# Architecture

Orient-yourself map for **Ka0s KickCD**. Tracks the player's interrupt and CC cooldowns and surfaces them on a movable icon grid, with a sibling cast bar — for both the player's target and focus unit — driven from the same drag lock and visibility mode. Target client: WoW 12.0.7 (Midnight). 12.0-aware throughout — the cast bar was originally removed at commit `59fb5c0` and re-added with explicit secret-value gating; see [scope.md](scope.md#cast-bar-removal-history).

This file is the high-level index; topic detail lives in `docs/`.

## What it does

Two UI widgets, each tracked for **two enemy units — target and focus** — sharing one configuration model:

- **Icon grid** — pooled per-spell icon buttons with per-icon ready glow (LibCustomGlow), placed by an orthogonal anchor + grow + dimensions model (13 anchor points × 8 grow directions × free row/col dims). Visual states (ready / cooldown / GCD-suppressed) drive C-side curves so the GCD-vs-real-CD filter never compares secret-tainted remaining time in Lua.
- **Cast bar** — mirrors its unit's cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration`. Stacked dual `StatusBar`s + per-state borders are alpha-curve-switched on the cast's secret `notInterruptible` bool via `C_CurveUtil.EvaluateColorValueFromBoolean`, so per-state appearance is rendered without the addon ever inspecting the protected boolean from Lua.

Both widget types render **the same player cooldowns** (the tracked spell list is player-centric, not unit-specific) against each enabled unit's own cast state — `modules/IconGrid.lua` and `modules/Castbar.lua` are per-unit **instance managers**: `instances[unit]` holds one live frame set per enabled unit (target and focus both enabled by default). Target keeps the legacy global frame names (`KickCDIconGrid`, `KickCDCastbar`); focus gets the suffixed `KickCDIconGridFocus` / `KickCDCastbarFocus`. A focus unit can **link** to target's appearance (`units.focus.link`, default on) so it mirrors target's `icons`/`castbar` styling live; position and the optional identity label stay per-unit even while linked. See [core/Units.lua](../core/Units.lua) (`NS.Units`) for the single place link resolution happens, and [saved-variables.md](saved-variables.md#unitsunit-shape) for the DB shape.

Both widgets honor the master enable, **plus their own unit's per-unit `enabled` toggle**, the shared lock (`db.profile.locked`), and the addon-wide visibility mode (`db.profile.visibility`: `always` / `in_combat` / `target_casting` / `target_casting_interruptible`) — **one lock and one visibility mode still cover both units**, evaluated per-unit against that unit's own cast state. The `_interruptible` mode uses a two-step gate (Show on hostile cast, alpha-mask uninterruptible via `SetAlphaFromBoolean`) because the underlying flag can't be compared in Lua under 12.0.

Each unit can also show a single configurable identity label (`units.<unit>.label`), rendered by `modules/UnitLabel.lua` — a per-unit instance manager, mirroring `IconGrid`/`Castbar`'s pattern, that owns one `FontString` per unit in a holder frame parented to `UIParent` (`KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`) and `SetPoint`-anchors it to that unit's chosen widget (`label.style.attach`: cast bar or icon grid). Only `text` stays per-unit while linked (`NS.Units.Label`); both `show` (`NS.Units.LabelShow`) and `label.style` (position, font, justify, rotation, color — `NS.Units.LabelStyle`) follow the Focus link like `icons`/`castbar` do. See [saved-variables.md](saved-variables.md#unitsunitlabelstyle-shape).

An on-screen debug console (`LibKa0s-DebugLog-1.0`, wired in `core/DebugLogSetup.lua`, toggled with `/kcd debug`) surfaces internal state. Debug logging is gated on the session-only `NS.State.debug` flag — it is never persisted and resets on every `/reload`.

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
| Unit identity + per-unit (target/focus) config resolution, link semantics | `core/Units.lua` | [module-map.md](module-map.md), [saved-variables.md](saved-variables.md#unitsunit-shape) |
| Game event → state → message → render pipeline; visibility gate; lock + anchor | `modules/Cooldowns.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua`, `core/State.lua`, `settings/Panel.lua` | [data-flow.md](data-flow.md) |
| Closed message contract (5 messages, sender/listener/payload) | every module that emits or subscribes | [message-bus.md](message-bus.md) |
| `KickCDDB` AceDB schema + `DEFAULT_PROFILE` shape + spell-list lifecycle | `core/Database.lua` | [saved-variables.md](saved-variables.md) |
| `Compat.*` spell/cast API shims + `State.*` visibility helpers (boundary) | `core/Compat.lua`, `core/State.lua` | [compat-layer.md](compat-layer.md) |
| 12.0 secret values + cast interruptibility two-step gate + frame mixin | `core/Compat.lua`, `core/State.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua` | [midnight-quirks.md](midnight-quirks.md) |
| Icon grid layout (anchor + grow + dimensions) | `modules/IconGrid.lua` | [icon-grid.md](icon-grid.md) |
| Cast bar (stacked dual widgets, Reskin/RenderCast split, anti-patterns) | `modules/Castbar.lua`, `modules/Castbar_Skin.lua` | [castbar.md](castbar.md) |
| Schema-driven canvas-layout settings panel; widget primitives; validation | `settings/Panel.lua`, `settings/Panel_Widgets.lua`, `settings/Panel_Render.lua`, `settings/{General,Icons,Castbar,Label,Spells,Profiles}.lua` | [settings-panel.md](settings-panel.md) |
| Slash dispatch tables and command catalogue | `core/KickCD.lua` | [slash-dispatch.md](slash-dispatch.md) |
| End-to-end smoke tests (cold install, visibility modes, lock/drag, cast bar, spec/talent/pet, profiles, secret values) | — | [smoke-tests.md](smoke-tests.md) |
| Slash-command + debug coverage matrices (what each command produces) | — | [testing.md](testing.md) |
| Code style, saved-variable boundary, `_G.X` vs bare X | every module | [conventions.md](conventions.md) |
| Scope, defaults source (Baratus sheet), cast-bar removal history | — | [scope.md](scope.md) |

## Invariants worth not breaking

- **Closed message bus.** The five AceEvent messages (`Ka0s_KickCD_SPELL_STATE`, `Ka0s_KickCD_CONFIG_CHANGED`, `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_GRID_LAYOUT`, `Ka0s_KickCD_COMBAT_STATE`) are the only inter-module communication channel. `Ka0s_KickCD_CONFIG_CHANGED` is emitted from several modules (any schema-row write, the lock/unlock toggle, drag-stop anchor saves, debounced spell edits — the session-only debug toggle is off-bus). **Deviation recorded as intentional:** `Ka0s_KickCD_PROFILE_CHANGED` has two emitters, both inside `core/Database.lua` — `Database:OnProfileChanged` (the AceDB callback) and `Database:ResetAllSpells`, which re-seeds every spec's list in place and so needs the same full-rebuild fan-out without an actual AceDB profile swap. The emitter set stays confined to the one file that owns the profile, so the message is still single-*owner* even though it is not single-*call-site*. The remaining three messages each have exactly one emitter. Adding a message requires updating the source emitter(s), every consumer, and [message-bus.md](message-bus.md).
- **`Compat` is API normalisation only.** No feature decisions, no shared mutable state, no visibility helpers. Visibility decisions live in `core/State.lua`; shared mutable state lives in `core/State.lua`; shared magic numbers live in `core/Constants.lua`.
- **12.0 secret values get C-side handling, not Lua-side detox.** Pass duration-object methods, `notInterruptible`, `name`, `texture` straight into Blizzard C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`). Never bind to a Lua local for compare / format / tostring / arithmetic. `securecallfunction` / `tonumber` / `+0` "detox" were tried and don't work.
- **`NS.Settings.Schema` is the single source of truth.** UI widget, slash CLI (`get` / `set` / `list`), per-panel `Defaults` button, and the General → "Reset all settings" reset all wire from one row. Don't add parallel mutators for fields with a schema row. The `valueGate` mechanism enforces cross-row dependencies (e.g. `units.<unit>.castbar.growDirection` ↔ `units.<unit>.castbar.orientation`).
- **Colours are stored keyed, dropdowns are keyed hashes.** A colour value is `{ r =, g =, b =, a = }` — the shape `LibKa0s-Slash-1.0` / `-Options-1.0` parse into and render from, so no host-side codec sits between them (the old positional `{r,g,b,a}` array migrated in `Database:MigrateColorShape`, the v3→v4 step). Dropdown `values` are keyed hashes with a sibling `sorting` array. Every colour row carries `hasAlpha`; every schema row carries `desc` (not `tooltip`), `panel` and `section`.
- **One drag lock + one visibility mode shared across both UI pieces — PRESERVED across target/focus dual tracking.** The icon grid and the cast bar both read `db.profile.locked` and `db.profile.visibility`; one unlock/lock cycle moves every enabled unit's frames. Visibility is evaluated per-unit against that unit's own cast state (a focus grid hides/shows independent of whether target is casting), but the *mode* itself — and the lock — stay addon-wide, not per-unit. Don't introduce per-widget (or per-unit) lock or visibility-mode state; `scale`/`alpha` similarly stay addon-wide (per-unit scale/alpha was considered and deferred, not shipped).
- **`NS.State.inCombat` is the combat flag, not `InCombatLockdown()`.** A bootstrap CreateFrame in `core/State.lua` is the only file that registers `PLAYER_REGEN_DISABLED/_ENABLED/PLAYER_LOGIN`; it maintains the flag and fans the transition out via `Ka0s_KickCD_COMBAT_STATE` so subscribers (IconGrid, Castbar) see an explicit ordered signal. `InCombatLockdown()` lags the regen events by a frame and is unreliable.
- **Persisted keys are never derived from a localized string.** The spell-list key is the numeric specID (`Const.SPEC`); the class key is `UnitClass()`'s file token. `GetSpecializationInfo`'s second return is the *localized display name* and is display-only — routing it into a lookup key is what broke every non-English client in issue #8, silently and with no error, because a missing spec list is indistinguishable from a deliberately emptied one. Localized names may be accepted as slash-command input (`Util.ResolveSpecID`) and shown as UI labels (`Util.SpecDisplayName`); they may not be stored, compared, or used as identity. The same rule applies to any future per-something table.
- **Module publishing pattern:** every file does `NS.Foo = NS.Foo or {}; local F = NS.Foo`. Never shadow the local over the global (`local KickCD = {}` would break everything downstream).
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
- LibKa0s (the Ka0s shared library — `Core`, `DebugLog`, `Perf`, `Slash`, `Options` are adopted here, one setup file each: `core/CoreSetup.lua`, `core/DebugLogSetup.lua`, `core/PerfSetup.lua`, `settings/Slash.lua`, `settings/OptionsSetup.lua`). **Never edit `libs/LibKa0s`** — a library problem is fixed upstream in `../LibKa0s` and re-vendored. The gate is two diffs, not one: `diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s` MUST be empty (content), and the plain `diff -r` SHOULD be (bytes). A byte-only difference is a line-ending divergence, not a fork — renormalise the side that drifted, never edit `libs/`. Every setup file degrades to a stub when the library is missing rather than erroring at load, and all five explain the absence through **one shared cause clause**, `NS.LIBKA0S_MISSING` (defined in `core/CoreSetup.lua`, outside its own `if not lib` branch because the seams that read it are reached on both paths). Each seam appends its own "so &lt;what&gt; is unavailable", so a degraded install says the same thing about *why* five times and a different thing about *what* each time — and says it identically to AbsorbTracker and ConsumableMaster, which is the point.
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
| `Ka0s_KickCD_CONFIG_CHANGED` | Panel `Helpers.Set`, `core/KickCD.lua`, Spells editor, IconGrid / Castbar `OnDragStop`, `Helpers.RenderUnitPanel` (focus link/copy) | `IconGrid`, `Cooldowns`, `Castbar`, `UnitLabel`, Spells panel | `{ section }` — section ∈ `general`\|`icons`\|`castbar`\|`label`\|`spells`\|`units` |
| `Ka0s_KickCD_PROFILE_CHANGED` | `Database:OnProfileChanged`, `Database:ResetAllSpells` | `IconGrid`, `Cooldowns`, `Castbar`, `UnitLabel`, Spells panel | `{ newProfileKey }` |
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

Under 12.0, `C_Spell.GetSpellCooldown` timing returns and `UnitCastingInfo` / `UnitChannelInfo` `notInterruptible` / `name` / `texture` come back **secret** in combat for protected interrupts. Secret values must be passed straight into Blizzard C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`) — never bound to a Lua local for compare / format / `tostring` / arithmetic, which errors in tainted scope. Visibility and interruptibility decisions that depend on `notInterruptible` go through the two-step gate `State.IsHostileUnitCasting` (show) + `State.ApplyInterruptibleAlpha` (filter). Full pattern catalogue in [midnight-quirks.md](midnight-quirks.md).

## Known limitations

- English (`enUS`) only.
- Retail / Midnight only — a single `## Interface` line, no Classic support.
- No automated in-client tests — headless unit tests plus manual in-game smoke tests only (see [smoke-tests.md](smoke-tests.md)).
- Debug logging is session-only (`NS.State.debug`) and resets on every `/reload`.

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
10. `core/Database.lua` (defines class + `units.target`/`units.focus` in `DEFAULT_PROFILE`; doesn't init the DB at file-load time)
11. `core/LSMPatch.lua` (one-shot `PLAYER_LOGIN` fixup wrapping the vendored `LSM30_Border` widget — hides its misaligned 42×42 `displayButton` preview tile and re-anchors the dropdown bar; kept in addon code so a lib refresh can't blow it away)
12. `core/KickCD.lua` (`AceAddon-3.0:NewAddon(NS, "KickCD", ...)` promotes the private `NS` table in place — no `_G.KickCD` rebind)
13. `core/PerfSetup.lua` (`LibKa0s-Perf-1.0` descriptor — publishes `NS.Perf`, backing `/kcd perf`. **Last** in the core block: it needs `NS.Util.print`, the debug-log sink, and `NS.VERSION`, and it must precede every module that takes `local Perf = NS.Perf` as a load-time upvalue)
14. `defaults/Spells.lua` (sets `NS.DefaultSpells`)
15. `modules/Cooldowns.lua` → `modules/IconGrid.lua` (per-unit instance manager) → `modules/IconGrid_Layout.lua` (peeled: anchor/grow parsing + block geometry) → `modules/IconGrid_Render.lua` (peeled: per-icon widget rendering, curves, cooldown-text ticker) → `modules/Castbar.lua` (per-unit instance manager) → `modules/Castbar_Skin.lua` (peeled: the config-driven `Castbar:Reskin` — sizing, orientation, insets, spark, fonts, text anchors, per-state textures/colours/borders) → `modules/Castbar_Debug.lua` (peeled: the `Castbar:DebugDump(unit)` diagnostic behind `/kcd debug castbar`, re-opening the already-registered module) → `modules/UnitLabel.lua` (per-unit instance manager; one identity FontString per unit, `SetPoint`-anchored to that unit's `IconGrid` or `Castbar` frame). `modules/IconGrid.lua` was split into three flat siblings (`IconGrid` / `IconGrid_Layout` / `IconGrid_Render`), and both `Reskin` and `DebugDump` peeled off `Castbar.lua`, to stay under the 1500-LOC cap.
16. `settings/Slash.lua` (`LibKa0s-Slash-1.0` descriptor — the `/kcd` dispatcher and schema CLI; loads after `core/KickCD.lua` has defined `NS.COMMANDS`, which is passed in) → `settings/OptionsSetup.lua` (`LibKa0s-Options-1.0` descriptor — **is** `NS.Settings.Helpers`, decorated in place by the three `Panel*` files; must precede every `settings/<page>.lua`, which call `Helpers.LSMValues` / `Helpers.AnchorValues` inside schema-row literals at file load) → `settings/Panel.lua` → `settings/Panel_Widgets.lua` → `settings/Panel_Render.lua` → `settings/{General, Icons, Castbar, Label, Spells, Profiles}.lua` (the two `Panel_*` siblings were peeled from `Panel.lua` to stay under the 1500-LOC cap — KCD-24; they must load before the per-tab files that call the makers / renderers)

`NS:OnInitialize` (Ace lifecycle on `ADDON_LOADED`) builds the AceDB instance, runs the three shape-driven migrators unconditionally (`Database:FoldLegacyUnits` → `Database:BackfillLabelStyle` → `Database:MigrateSpecKeys`) then the version-gated scaffold `Database:MigrateProfile` (`CURRENT_DB_VERSION = 4`; registered steps v1→v2 `FoldLegacyUnits`, v2→v3 `MigrateSpecKeys`, v3→v4 `MigrateColorShape`), and seeds spells on first profile creation. `<Module>:OnEnable` calls `ReconcileUnits()`, which registers messages and game events **per currently-enabled unit** (target by default; focus only if `units.focus.enabled`). `PLAYER_LOGIN` defers the Settings category registration so per-tab builders can run with their full schema available. Full lifecycle in [module-map.md](module-map.md#aceaddon-lifecycle).
