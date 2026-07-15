# Architecture

Orient-yourself map for **Ka0s KickCD**. Tracks the player's interrupt and CC cooldowns and surfaces them on a movable icon grid, with a sibling target cast bar driven from the same drag lock and visibility mode. Target client: WoW 12.0.7 (Midnight). 12.0-aware throughout — the cast bar was originally removed at commit `59fb5c0` and re-added with explicit secret-value gating; see [scope.md](scope.md#cast-bar-removal-history).

This file is the high-level index; topic detail lives in `docs/`.

## What it does

Two UI widgets sharing one configuration model:

- **Icon grid** — pooled per-spell icon buttons with per-icon ready glow (LibCustomGlow), placed by an orthogonal anchor + grow + dimensions model (13 anchor points × 8 grow directions × free row/col dims). Visual states (ready / cooldown / GCD-suppressed) drive C-side curves so the GCD-vs-real-CD filter never compares secret-tainted remaining time in Lua.
- **Cast bar** — mirrors the player's target's cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration`. Stacked dual `StatusBar`s + per-state borders are alpha-curve-switched on the cast's secret `notInterruptible` bool via `C_CurveUtil.EvaluateColorValueFromBoolean`, so per-state appearance is rendered without the addon ever inspecting the protected boolean from Lua.

Both widgets honor the master enable, the shared lock (`db.profile.locked`), and the addon-wide visibility mode (`db.profile.visibility`: `always` / `in_combat` / `target_casting` / `target_casting_interruptible`). The `_interruptible` mode uses a two-step gate (Show on hostile cast, alpha-mask uninterruptible via `SetAlphaFromBoolean`) because the underlying flag can't be compared in Lua under 12.0.

An on-screen debug console (`modules/DebugLog.lua`, toggled with `/kcd debug`) surfaces internal state. Debug logging is gated on the session-only `NS.State.debug` flag — it is never persisted and resets on every `/reload`.

## Subsystems at a glance

```
WoW events ─▶ Cooldowns:Refresh ─▶ Ka0s_KickCD_SPELL_STATE ─▶ IconGrid:OnSpellState
                                                           └─▶ alpha/tint curves (C-side)
                                                           └─▶ SetCooldownFromDurationObject

PLAYER_TARGET_CHANGED ─▶ Castbar:Reevaluate ─▶ Compat.GetCastingInfo("target")
UNIT_SPELLCAST_*                              └─▶ UnitCastingDuration/UnitChannelDuration
                                              └─▶ ApplyState (curve-switched on secret notInterruptible)

Settings widget / slash CLI ─▶ Helpers.Set ─▶ Ka0s_KickCD_CONFIG_CHANGED ─▶ IconGrid + Cooldowns + Castbar
AceDB profile change         ─▶                Ka0s_KickCD_PROFILE_CHANGED ─▶ same
IconGrid:Layout              ─▶                Ka0s_KickCD_GRID_LAYOUT     ─▶ Castbar (re-anchor / auto-size)

  AceDB (all chars share the "Default" profile; user-switchable)  ──  5-tab settings panel + /kcd CLI
```

| Subsystem | Lives in | Read |
|-----------|----------|------|
| Per-module APIs + roles, TOC load order, AceAddon lifecycle | `core/`, `defaults/`, `modules/`, `settings/` | [module-map.md](module-map.md) |
| Game event → state → message → render pipeline; visibility gate; lock + anchor | `modules/Cooldowns.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua`, `core/State.lua`, `settings/Panel.lua` | [data-flow.md](data-flow.md) |
| Closed message contract (5 messages, sender/listener/payload) | every module that emits or subscribes | [message-bus.md](message-bus.md) |
| `KickCDDB` AceDB schema + `DEFAULT_PROFILE` shape + spell-list lifecycle | `core/Database.lua` | [saved-variables.md](saved-variables.md) |
| `Compat.*` spell/cast API shims + `State.*` visibility helpers (boundary) | `core/Compat.lua`, `core/State.lua` | [compat-layer.md](compat-layer.md) |
| 12.0 secret values + cast interruptibility two-step gate + frame mixin | `core/Compat.lua`, `core/State.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua` | [midnight-quirks.md](midnight-quirks.md) |
| Icon grid layout (anchor + grow + dimensions) | `modules/IconGrid.lua` | [icon-grid.md](icon-grid.md) |
| Cast bar (stacked dual widgets, Reskin/RenderCast split, anti-patterns) | `modules/Castbar.lua` | [castbar.md](castbar.md) |
| Schema-driven canvas-layout settings panel; widget primitives; validation | `settings/Panel.lua`, `settings/{General,Icons,Castbar,Spells,Profiles}.lua` | [settings-panel.md](settings-panel.md) |
| Slash dispatch tables and command catalogue | `core/KickCD.lua` | [slash-dispatch.md](slash-dispatch.md) |
| End-to-end smoke tests (cold install, visibility modes, lock/drag, cast bar, spec/talent/pet, profiles, secret values) | — | [smoke-tests.md](smoke-tests.md) |
| Slash-command + debug coverage matrices (what each command produces) | — | [testing.md](testing.md) |
| Code style, saved-variable boundary, `_G.X` vs bare X | every module | [conventions.md](conventions.md) |
| Scope, defaults source (Baratus sheet), cast-bar removal history | — | [scope.md](scope.md) |

## Invariants worth not breaking

- **Closed message bus.** The five AceEvent messages (`Ka0s_KickCD_SPELL_STATE`, `Ka0s_KickCD_CONFIG_CHANGED`, `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_GRID_LAYOUT`, `Ka0s_KickCD_COMBAT_STATE`) are the only inter-module communication channel. `Ka0s_KickCD_CONFIG_CHANGED` is emitted from several modules (any schema-row write, the lock/unlock toggle, drag-stop anchor saves, debounced spell edits — the session-only debug toggle is off-bus); the other four each have a single owning emitter. Adding a message requires updating the source emitter(s), every consumer, and [message-bus.md](message-bus.md).
- **`Compat` is API normalisation only.** No feature decisions, no shared mutable state, no visibility helpers. Visibility decisions live in `core/State.lua`; shared mutable state lives in `core/State.lua`; shared magic numbers live in `core/Constants.lua`.
- **12.0 secret values get C-side handling, not Lua-side detox.** Pass duration-object methods, `notInterruptible`, `name`, `texture` straight into Blizzard C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`). Never bind to a Lua local for compare / format / tostring / arithmetic. `securecallfunction` / `tonumber` / `+0` "detox" were tried and don't work.
- **`NS.Settings.Schema` is the single source of truth.** UI widget, slash CLI (`get` / `set` / `list`), per-panel `Defaults` button, and the General → "Reset all settings" reset all wire from one row. Don't add parallel mutators for fields with a schema row. The `valueGate` mechanism enforces cross-row dependencies (e.g. `castbar.growDirection` ↔ `castbar.orientation`).
- **One drag lock + one visibility mode shared across both UI pieces.** The icon grid and the cast bar both read `db.profile.locked` and `db.profile.visibility`; one unlock/lock cycle moves both. Don't introduce per-widget lock or visibility state.
- **`NS.State.inCombat` is the combat flag, not `InCombatLockdown()`.** A bootstrap CreateFrame in `core/State.lua` is the only file that registers `PLAYER_REGEN_DISABLED/_ENABLED/PLAYER_LOGIN`; it maintains the flag and fans the transition out via `Ka0s_KickCD_COMBAT_STATE` so subscribers (IconGrid, Castbar) see an explicit ordered signal. `InCombatLockdown()` lags the regen events by a frame and is unreliable.
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
- LibSharedMedia-3.0
- AceGUI-3.0-SharedMediaWidgets (vendored upstream r65; provides the `LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` dropdowns used by the Cast bar / Icons panels). `core/LSMPatch.lua` is an in-tree fixup that hides the 42×42 Border `displayButton` preview tile and re-anchors the dropdown bar; lives in addon code so future lib refreshes don't blow it away.
- LibCustomGlow-1.0

AceTimer-3.0 remains vendored under `libs/` (part of the standard Ace3 distribution) but is not loaded by the TOC. The six other unused Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab) were deleted from `libs/`.

`KickCD.toc`'s `## Interface:` line targets the Midnight client.

## Message bus

Five `AceEvent` messages are the only inter-module communication channel — modules never call each other directly across boundaries. Full payload semantics in [message-bus.md](message-bus.md).

| Message | Sender(s) | Consumers | Payload |
|---|---|---|---|
| `Ka0s_KickCD_SPELL_STATE` | `Cooldowns:Rebuild` / `:Refresh` | `IconGrid` | `{ spellID, ready, isActive, cdObject, chargeCdObject, charges }` |
| `Ka0s_KickCD_CONFIG_CHANGED` | Panel `Helpers.Set`, `core/KickCD.lua`, Spells editor, IconGrid / Castbar `OnDragStop` | `IconGrid`, `Cooldowns`, `Castbar`, Spells panel | `{ section }` |
| `Ka0s_KickCD_PROFILE_CHANGED` | `Database:OnProfileChanged` | `IconGrid`, `Cooldowns`, `Castbar`, Spells panel | `{ newProfileKey }` |
| `Ka0s_KickCD_GRID_LAYOUT` | `IconGrid:Layout` | `Castbar` | `{ gridFrame, primaryIcon, width, height }` |
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
| `reset <panel>` | Reset a panel to defaults (`/kcd reset spells` rebuilds every spec's list) |
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
- **`IconGrid`** — `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START` / `_STOP` / `_FAILED` / `_INTERRUPTED` / `_CHANNEL_START` / `_CHANNEL_STOP` / `_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE`), plus the four inbound `Ka0s_KickCD_*` messages.
- **`Castbar`** — the `UNIT_SPELLCAST_*` family registered through `Util.RegisterTargetEvent` (target-only dispatch), plus its inbound messages.

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
7. `core/Database.lua` (defines class; doesn't init the DB at file-load time)
8. `core/LSMPatch.lua` (one-shot `PLAYER_LOGIN` fixup wrapping the vendored `LSM30_Border` widget — hides its misaligned 42×42 `displayButton` preview tile and re-anchors the dropdown bar; kept in addon code so a lib refresh can't blow it away)
9. `core/KickCD.lua` (`AceAddon-3.0:NewAddon(NS, "KickCD", ...)` promotes the private `NS` table in place — no `_G.KickCD` rebind)
10. `defaults/Spells.lua` (sets `NS.DefaultSpells`)
11. `modules/DebugLog.lua` (on-screen debug console) → `modules/Cooldowns.lua` → `modules/IconGrid.lua` → `modules/IconGrid_Layout.lua` (peeled: anchor/grow parsing + block geometry) → `modules/IconGrid_Render.lua` (peeled: per-icon widget rendering, curves, cooldown-text ticker) → `modules/Castbar.lua`. `modules/IconGrid.lua` was split into three flat siblings (`IconGrid` / `IconGrid_Layout` / `IconGrid_Render`) to stay under the 1500-LOC cap.
12. `settings/Panel.lua` → `settings/{General, Icons, Castbar, Spells, Profiles}.lua`

`NS:OnInitialize` (Ace lifecycle on `ADDON_LOADED`) builds the AceDB instance, runs the migration scaffold, and seeds spells on first profile creation. `<Module>:OnEnable` registers messages and game events. `PLAYER_LOGIN` defers the Settings category registration so per-tab builders can run with their full schema available. Full lifecycle in [module-map.md](module-map.md#aceaddon-lifecycle).
