# Architecture

Orient-yourself map for **Ka0s KickCD**. Tracks the player's interrupt and CC cooldowns and surfaces them on a movable icon grid, with a sibling target cast bar driven from the same drag lock and visibility mode. Target client: WoW 12.0.7 (Midnight). 12.0-aware throughout — the cast bar was originally removed at commit `59fb5c0` and re-added with explicit secret-value gating; see [docs/scope.md](docs/scope.md#cast-bar-removal-history).

This file is the high-level index; topic detail lives in `docs/`.

## What it does

Two UI widgets sharing one configuration model:

- **Icon grid** — pooled per-spell icon buttons with per-icon ready glow (LibCustomGlow), placed by an orthogonal anchor + grow + dimensions model (13 anchor points × 8 grow directions × free row/col dims). Visual states (ready / cooldown / GCD-suppressed) drive C-side curves so the GCD-vs-real-CD filter never compares secret-tainted remaining time in Lua.
- **Cast bar** — mirrors the player's target's cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration`. Stacked dual `StatusBar`s + per-state borders are alpha-curve-switched on the cast's secret `notInterruptible` bool via `C_CurveUtil.EvaluateColorValueFromBoolean`, so per-state appearance is rendered without the addon ever inspecting the protected boolean from Lua.

Both widgets honor the master enable, the shared lock (`db.profile.locked`), and the addon-wide visibility mode (`db.profile.visibility`: `always` / `in_combat` / `target_casting` / `target_casting_interruptible`). The `_interruptible` mode uses a two-step gate (Show on hostile cast, alpha-mask uninterruptible via `SetAlphaFromBoolean`) because the underlying flag can't be compared in Lua under 12.0.

## Subsystems at a glance

```
WoW events ─▶ Cooldowns:Refresh ─▶ KickCD_SPELL_STATE ─▶ IconGrid:OnSpellState
                                                           └─▶ alpha/tint curves (C-side)
                                                           └─▶ SetCooldownFromDurationObject

PLAYER_TARGET_CHANGED ─▶ Castbar:Reevaluate ─▶ Compat.GetCastingInfo("target")
UNIT_SPELLCAST_*                              └─▶ UnitCastingDuration/UnitChannelDuration
                                              └─▶ ApplyState (curve-switched on secret notInterruptible)

Settings widget / slash CLI ─▶ Helpers.Set ─▶ KickCD_CONFIG_CHANGED ─▶ IconGrid + Cooldowns + Castbar
AceDB profile change         ─▶                KickCD_PROFILE_CHANGED ─▶ same
IconGrid:Layout              ─▶                KickCD_GRID_LAYOUT     ─▶ Castbar (re-anchor / auto-size)

  AceDB (per-character default; user-switchable)  ──  5-tab settings panel + /kcd CLI
```

| Subsystem | Lives in | Read |
|-----------|----------|------|
| Per-module APIs + roles, TOC load order, AceAddon lifecycle | `core/`, `defaults/`, `modules/`, `settings/` | [docs/module-map.md](docs/module-map.md) |
| Game event → state → message → render pipeline; visibility gate; lock + anchor | `modules/Cooldowns.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua`, `core/State.lua`, `settings/Panel.lua` | [docs/data-flow.md](docs/data-flow.md) |
| Closed message contract (4 messages, sender/listener/payload) | every module that emits or subscribes | [docs/message-bus.md](docs/message-bus.md) |
| `KickCDDB` AceDB schema + `DEFAULT_PROFILE` shape + spell-list lifecycle | `core/Database.lua` | [docs/saved-variables.md](docs/saved-variables.md) |
| `Compat.*` spell/cast API shims + `State.*` visibility helpers (boundary) | `core/Compat.lua`, `core/State.lua` | [docs/compat-layer.md](docs/compat-layer.md) |
| 12.0 secret values + cast interruptibility two-step gate + frame mixin | `core/Compat.lua`, `core/State.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua` | [docs/midnight-quirks.md](docs/midnight-quirks.md) |
| Icon grid layout (anchor + grow + dimensions) | `modules/IconGrid.lua` | [docs/icon-grid.md](docs/icon-grid.md) |
| Cast bar (stacked dual widgets, Reskin/RenderCast split, anti-patterns) | `modules/Castbar.lua` | [docs/castbar.md](docs/castbar.md) |
| Schema-driven canvas-layout settings panel; widget primitives; validation | `settings/Panel.lua`, `settings/{General,Icons,Castbar,Spells,Profiles}.lua` | [docs/settings-panel.md](docs/settings-panel.md) |
| Slash dispatch tables and command catalogue | `core/KickCD.lua` | [docs/slash-dispatch.md](docs/slash-dispatch.md) |
| End-to-end smoke tests (cold install, visibility modes, lock/drag, cast bar, spec/talent/pet, profiles, secret values) | — | [docs/smoke-tests.md](docs/smoke-tests.md) |
| Slash-command + debug coverage matrices (what each command produces) | — | [docs/testing.md](docs/testing.md) |
| Code style, saved-variable boundary, `_G.X` vs bare X | every module | [docs/conventions.md](docs/conventions.md) |
| Scope, defaults source (Baratus sheet), cast-bar removal history | — | [docs/scope.md](docs/scope.md) |

## Invariants worth not breaking

- **Closed message bus.** The five AceEvent messages (`KickCD_SPELL_STATE`, `KickCD_CONFIG_CHANGED`, `KickCD_PROFILE_CHANGED`, `KickCD_GRID_LAYOUT`, `KickCD_COMBAT_STATE`) are the only inter-module communication channel. Each has exactly one sender. Adding a message requires updating the source emitter, every consumer, and [docs/message-bus.md](docs/message-bus.md).
- **`Compat` is API normalisation only.** No feature decisions, no shared mutable state, no visibility helpers. Visibility decisions live in `core/State.lua`; shared mutable state lives in `core/State.lua`; shared magic numbers live in `core/Constants.lua`.
- **12.0 secret values get C-side handling, not Lua-side detox.** Pass duration-object methods, `notInterruptible`, `name`, `texture` straight into Blizzard C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`). Never bind to a Lua local for compare / format / tostring / arithmetic. `securecallfunction` / `tonumber` / `+0` "detox" were tried and don't work.
- **`KickCD.Settings.Schema` is the single source of truth.** UI widget, slash CLI (`get` / `set` / `list`), per-panel `Defaults` button, and the General → "Reset all settings" reset all wire from one row. Don't add parallel mutators for fields with a schema row. The `valueGate` mechanism enforces cross-row dependencies (e.g. `castbar.growDirection` ↔ `castbar.orientation`).
- **One drag lock + one visibility mode shared across both UI pieces.** The icon grid and the cast bar both read `db.profile.locked` and `db.profile.visibility`; one unlock/lock cycle moves both. Don't introduce per-widget lock or visibility state.
- **`KickCD.State.inCombat` is the combat flag, not `InCombatLockdown()`.** A bootstrap CreateFrame in `core/State.lua` is the only file that registers `PLAYER_REGEN_DISABLED/_ENABLED/PLAYER_LOGIN`; it maintains the flag and fans the transition out via `KickCD_COMBAT_STATE` so subscribers (IconGrid, Castbar) see an explicit ordered signal. `InCombatLockdown()` lags the regen events by a frame and is unreliable.
- **Module publishing pattern:** every file does `KickCD.Foo = KickCD.Foo or {}; local F = KickCD.Foo`. Never shadow the local over the global (`local KickCD = {}` would break everything downstream).
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

Several additional Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab, AceTimer) ship as part of the standard Ace3 distribution under `libs/` but are not loaded by the TOC.

`KickCD.toc`'s `## Interface:` line targets the Midnight client.

## Load order

`KickCD.toc` is the source of truth. Order is dependency, not alphabetical:

1. `libs/` — vendored Ace3 + LibSharedMedia + LibCustomGlow
2. `locales/enUS.lua`
3. `core/Compat.lua` (creates `_G.KickCD` and `KickCD.Compat`)
4. `core/Constants.lua` (`KickCD.Const`)
5. `core/State.lua` (`KickCD.State`; bootstrap CreateFrame for `PLAYER_REGEN_*` / `PLAYER_LOGIN`)
6. `core/Util.lua`
7. `core/Database.lua` (defines class; doesn't init the DB at file-load time)
8. `core/KickCD.lua` (`AceAddon-3.0:NewAddon` promotes `_G.KickCD` in place)
9. `defaults/Spells.lua` (sets `KickCD.DefaultSpells`)
10. `modules/Cooldowns.lua` → `modules/IconGrid.lua` → `modules/Castbar.lua`
11. `settings/Panel.lua` → `settings/{General, Icons, Castbar, Spells, Profiles}.lua`

`KickCD:OnInitialize` (Ace lifecycle on `ADDON_LOADED`) builds the AceDB instance, runs the migration scaffold, and seeds spells on first profile creation. `<Module>:OnEnable` registers messages and game events. `PLAYER_LOGIN` defers the Settings category registration so per-tab builders can run with their full schema available. Full lifecycle in [docs/module-map.md](docs/module-map.md#aceaddon-lifecycle).
