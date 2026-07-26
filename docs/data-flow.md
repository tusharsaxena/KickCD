# Data flow

How a game event propagates through the addon, how user input flows back, and how lock + anchor state is owned.

## Cooldown pipeline (game event → icon grid)

```
Game event (SPELL_UPDATE_COOLDOWN / _USABLE / _CHARGES)
        │
        ▼
Cooldowns:OnCooldownEvent ──► Util.Throttle(0)   (coalesce a same-frame burst → one Refresh next frame)
        │
        ▼
Cooldowns:Refresh ──► PollSpell(spellID) ──► Compat.GetSpellCooldown          (isActive, plain bool)
        │                                    Compat.GetSpellCooldownDuration  (cdObject, secret-aware)
        │                                    Compat.IsSpellUsable / GetSpellCharges
        │                                          │
        │                                          ▼
        │                                  { ready, isActive, cdObject, chargeCdObject, charges }
        │                                  (Get…Duration on either object is secret in combat)
        ▼
StateChanged(prev, next) ── true ──► SendMessage("Ka0s_KickCD_SPELL_STATE", payload)
                                                          │
                                                          ▼
                                          IconGrid:OnSpellState ──► btn:Apply(state)
                                                                          │
                                                                          ▼
                                          alphaCurve / tintCurve evaluated C-side → SetAlphaFromBoolean / SetVertexColor
                                          cdObject → SetCooldownFromDurationObject (swipe)
                                          cdObject:GetRemainingDuration → SetFormattedText (countdown)
```

`SPELL_UPDATE_COOLDOWN` / `_USABLE` are **global and chatty** — they don't name the changed spell and fire many times per frame in combat, and each fire would otherwise re-poll every watched spell. The three events register to `Cooldowns:OnCooldownEvent`, which forwards into a `Util.Throttle(0)` coalescer built in `OnEnable`: a same-frame burst schedules a single `C_Timer.After(0, …)` that runs one `Refresh` on the next frame. `Refresh` re-polls the whole watched table fresh, so the throttle's trailing-args behaviour is irrelevant. `Rebuild` and its triggers (`PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, …) stay synchronous — only the `SPELL_UPDATE_*` path is coalesced.

The GCD-vs-real-CD visual decision is made entirely C-side via `cdObject:EvaluateRemainingDuration(curve)`. The IconGrid maintains step-shaped alpha and color curves built from `cfg.readyAlpha` / `cfg.cooldownAlpha` / `cfg.cooldownTint`: remaining ≤ ~1.6s evaluates to ready visuals, anything beyond evaluates to cooldown visuals. Lua never compares the secret remaining time directly. See `modules/IconGrid_Render.lua` `BuildCurves`.

A `Cooldowns:Refresh` whose `PollSpell(id)` returns `nil` for a previously-watched id (pet dismissed, talent untrained, encounter mechanic suppresses the spell) emits a final sentinel `Ka0s_KickCD_SPELL_STATE { spellID, ready=false, isActive=false, cdObject=nil, chargeCdObject=nil, charges=nil }` and unwatches the id. Without it the icon would render the last-known state until the next `Rebuild` — which `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED` typically cover, but not all paths fire those events.

`Cooldowns` is unit-agnostic — it polls the player's OWN spellbook, not a per-unit state — so a single `Ka0s_KickCD_SPELL_STATE` broadcast feeds every enabled unit's `IconGrid` instance identically (`instances[unit]:OnSpellState`, unit by unit).

### Emit rate: why SPELL_STATE fires ~10x/sec per spell on cooldown

`StateChanged` compares the cooldown handle, and `C_Spell.GetSpellCooldownDuration` mints a **fresh object on every call** — so any spell sitting on an unchanged cooldown compares unequal on every poll. This is not a defect to tidy up: in combat every getter on the duration object is secret-tainted (including the booleans, which therefore cannot be branched on), so the identity compare is the *only* change signal an addon has. It over-fires but never under-fires. See [midnight-quirks.md](midnight-quirks.md).

Two consequences shaped the downstream code:

- **Logging** is gated on `MaterialChange` (plain fields + handle presence, ignoring identity), so the debug console shows one line per real transition rather than ten per second.
- **Rendering** is split in `Icon:Apply`: the alpha/tint/GCD curve evaluations, the swipe re-arm and the countdown text are time-varying and must run on every payload; glow, the charges badge and the Show/Hide calls are gated behind `plainStateMoved`. Anything added to `Icon:Apply` has to land on the correct side of that split — the time-varying half runs at ~10 Hz.

## Settings input → bus

Most user input (settings panel widget, slash `/kcd set`, slash `/kcd lock|unlock|toggle`) flows through `Helpers.Set(path, section, value)` in `settings/Panel.lua`, which writes `db.profile.<path>` and fires `Ka0s_KickCD_CONFIG_CHANGED { section = ... }`. IconGrid and Castbar handle each section appropriately. AceDB callbacks fire `Ka0s_KickCD_PROFILE_CHANGED` on profile change / copy / reset.

The debug enabled-flag is outside this path: `/kcd debug on|off|toggle` sets the session-only `NS.State.debug` through `DebugLog:SetEnabled(on)` (default off, never in SavedVariables, resets each `/reload`). Continuous `NS.Debug(tag, fmt, ...)` output routes to the on-screen debug console (`modules/DebugLog.lua`), not the chat frame.

Slash commands that mutate schema-backed fields (e.g. `/kcd lock`) route through `Helpers.SetAndRefresh(path, value)` so they share the panel widgets' write/notify/refresh code path (`Helpers.Set` → schema row's `onChange` → `RefreshAllPanels`). That way a future `onChange` added to a row doesn't silently diverge between the two paths.

Drag is the one exception: each instance's `IconGrid:onDragStop` and `Castbar:onDragStop` write `db.profile.units.<unit>.anchors.icons` / `.castbar` directly via `Util.SaveAnchor(frame)` (the schema doesn't cover anchor tables — they aren't simple key-value rows; position is also never link-resolved, so the write always targets the dragged instance's own unit), then fire `Ka0s_KickCD_CONFIG_CHANGED { section = "general" }` and `{ section = "castbar" }` respectively so any future anchor-aware subscriber gets notified. The IconGrid / Castbar own re-anchor handlers are idempotent on the just-saved value, so the re-entrant dispatch is safe. The Reset position button + `/kcd resetposition` go through `Helpers.ResetIconPosition`, which writes `units.target.anchors.icons` directly from `NS.DEFAULT_PROFILE` and fires the same `general`-section message — TARGET only (a legacy affordance that predates focus tracking; see [settings-panel.md](settings-panel.md#reset-helpers)).

## Visibility two-step gate

Visibility / interruptibility decisions for every enabled unit's icon grid and cast bar instance use a two-step gate driven by the addon-wide `db.profile.visibility` mode, evaluated per-instance against that instance's own unit:

```
shouldBeVisible(unit) / isVisible(unit)
  ── always                       → true
  ── in_combat                    → NS.State.inCombat (PLAYER_REGEN_* flag
                                     owned by core/State.lua's bootstrap and
                                     fanned out via Ka0s_KickCD_COMBAT_STATE; NOT
                                     InCombatLockdown — that lags by a frame)
  ── target_casting               → UnitCastingInfo / UnitChannelInfo(unit) truthy
  ── target_casting_interruptible → NS.State.IsHostileUnitCasting(unit)
        ▼
   Show / Hide
        ▼
   ApplyInterruptibilityMask / ApplyVisibilityMask
        ▼
   NS.State.ApplyInterruptibleAlpha(frame, unit, 1)
        ▼ (C-side, secret-safe)
   frame:SetAlphaFromBoolean(notInterruptible, 0, 1)
```

`unit` is `"target"` or `"focus"` — each unit instance's gate reads that unit's OWN cast state (`UnitCastingInfo(unit)` etc.) and is otherwise identical logic; a focus instance's visibility never depends on target's cast state or vice versa. Only the *mode itself* (`db.profile.visibility`) is shared.

`NS.State.IsHostileUnitCasting` is a pure truthy check (safe even when `name` / `texture` come back secret-tainted in combat) plus a `UnitCanAttack` filter. `NS.State.ApplyInterruptibleAlpha` reads the raw `notInterruptible` straight off `UnitCastingInfo` / `UnitChannelInfo` and hands it to `Frame:SetAlphaFromBoolean` — the **one** C-side method that accepts the secret-tainted bool form without erroring. Both helpers live in `core/State.lua` (not `core/Compat.lua`) because they're feature decisions about visibility, not API shape normalisation.

So uninterruptible casts run the full UI lifecycle (Show / glow start / cast bar drawn) but at `alpha = 0`, with the visual filter applied entirely C-side. The `UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE` events (unit-filtered per instance via `Util.RegisterUnitCastEvent`) drive a re-application of the alpha mask mid-cast.

Per-icon ready glow follows the same pattern per instance: `Icon:UpdateGlow` starts the LibCustomGlow effect for any hostile cast on that instance's unit under the `target_casting_interruptible` trigger and then drives the glow frame's alpha through `ApplyInterruptibleAlpha`. Each `IconGrid` instance's `RefreshAllGlows` re-runs the per-icon decision on `PLAYER_TARGET_CHANGED` / `PLAYER_FOCUS_CHANGED` and every cast event so the glow gate stays in sync.

The full secret-value rationale lives in [midnight-quirks.md](midnight-quirks.md).

## Cast bar pipeline

Independent of the cooldown pipeline above. Each `Castbar` instance runs this per its own unit:

```
PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED / UNIT_SPELLCAST_*  (filtered to this instance's unit)
        │
        ▼
Castbar instances[unit]:Reevaluate ──► Compat.GetCastingInfo(unit)
                             │  (UnitCastingInfo for name/texture/notInterruptible/spellID
                             │   + UnitCastingDuration for the timing object)
                             ▼
                       Castbar:Start(rec) ──► OnUpdate
                                                 │
                                                 ▼
                       d:GetTotalDuration / GetElapsedDuration / GetRemainingDuration
                       passed DIRECTLY (never via a Lua local) to
                       StatusBar:SetMinMaxValues / SetValue and
                       FontString:SetFormattedText. Both stacked StatusBars
                       (interruptible / uninterruptible) receive identical
                       calls; ApplyState alpha-curves whichever is visible
                       via C_CurveUtil.EvaluateColorValueFromBoolean on
                       the secret notInterruptible bool.
```

Each `IconGrid` instance emits its own `Ka0s_KickCD_GRID_LAYOUT { unit, gridFrame, primaryIcon, width, height }` after every `Layout()` pass. Each `Castbar` instance listens, filters on `payload.unit`, and — only for its own unit's payload — re-anchors under the `PRIMARY` anchor mode (the primary icon button reference may have moved — read directly from the payload's `primaryIcon`, with a fallback to `NS:GetModule("IconGrid", true):GetPrimaryIcon` for the first tick after enable) and re-runs `Reskin` when `castbar.autoSize` is on (the grid frame's footprint may have changed — read from the payload's `gridFrame` / `width` / `height`). A focus instance ignores a target `GRID_LAYOUT` payload and vice versa.

## Lock and anchor

Each enabled unit's icon grid and cast bar instance has its own single anchor in `db.profile.units.<unit>.anchors`, always relative to UIParent — anchors are never link-resolved, so a linked focus still tracks its own independent position. `Util.SaveAnchor(frame)` snapshots `{ point, relativePoint, x, y }`; `Util.ApplyAnchor(frame, anchor)` restores it. `NS.Units.Anchor(unit, which)` / `.SetAnchor(unit, which, a)` are the read/write helpers (`core/Units.lua`).

* `units.<unit>.anchors.icons` — that unit's icon grid saved position. Persisted by that instance's `IconGrid` `OnDragStop` and re-applied by `IconGrid:OnProfileChanged` / (target only) the General → "Reset position" button. `OnDragStop` also fires `Ka0s_KickCD_CONFIG_CHANGED { section = "general" }` so any future anchor-aware subscriber gets notified — today each IconGrid instance is the only consumer of its own anchor, but the message closes the contract.
* `units.<unit>.anchors.castbar` — that unit's cast bar saved position. Only consulted when `units.<unit>.castbar.anchorMode == "FREE"`. Under `"PRIMARY"` the bar is `SetPoint`'d to its OWN unit's icon grid primary icon button via the configured `(anchorPoint, castbarPoint, anchorOffsetX, anchorOffsetY)` tuple, the bar is locked from dragging regardless of `db.profile.locked`, and `Ka0s_KickCD_GRID_LAYOUT` triggers re-anchoring whenever that unit's primary icon button reference changes (the listener filters on `payload.unit` before reading the payload's `gridFrame` / `primaryIcon` directly). The Castbar instance's `OnDragStop` symmetrically fires `Ka0s_KickCD_CONFIG_CHANGED { section = "castbar" }`.

Lock state lives in `db.profile.locked` and is shared addon-wide — one unlock/lock cycle moves every enabled unit's frames (see [ARCHITECTURE.md](ARCHITECTURE.md#invariants-worth-not-breaking)). `IconGrid:ApplyLock` and `Castbar:ApplyLock` flip `EnableMouse(true/false)` + `RegisterForDrag("LeftButton" or nothing)` per instance accordingly. The icon grid also flips per-icon `EnableMouse` based on `(locked AND icons.showTooltip)` so the hover-tooltip path lights up only while the grid frame isn't claiming the mouse for drag. Touch points:

- Settings → General → "Lock frame" checkbox writes `db.profile.locked` through `Helpers.Set` and fires `Ka0s_KickCD_CONFIG_CHANGED { section = "general" }`.
- Slash commands `/kcd lock | unlock | toggle` route through `Helpers.SetAndRefresh("locked", ...)` so they share the same write/notify/refresh path as the checkbox (and so an open General panel reflects the lock state immediately). They fall back to a direct write only when the settings layer hasn't loaded yet.
- `IconGrid:OnConfigChanged` and `Castbar:OnConfigChanged` react to section `"general"` by calling `ApplyLock`.
- `IconGrid:ApplyLock` additionally toggles per-icon `EnableMouse` based on `(locked AND icons.showTooltip)` so the hover-tooltip path lights up only while the grid frame isn't claiming the mouse for drag.
- `Castbar:ApplyLock` additionally forces drag off whenever `castbar.anchorMode == "PRIMARY"`, regardless of the global lock — under that mode the bar's position is determined by the icon-grid anchor + offsets, not by dragging.
