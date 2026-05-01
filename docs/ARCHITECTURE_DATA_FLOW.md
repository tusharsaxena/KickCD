# Data flow

```
Game event (SPELL_UPDATE_COOLDOWN, ...)
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
StateChanged(prev, next) ── true ──► SendMessage("KickCD_SPELL_STATE", payload)
                                                          │
                                                          ▼
                                          IconGrid:OnSpellState ──► btn:Apply(state)
                                                                          │
                                                                          ▼
                                          alphaCurve / tintCurve evaluated C-side → SetAlphaFromBoolean / SetVertexColor
                                          cdObject → SetCooldownFromDurationObject (swipe)
                                          cdObject:GetRemainingDuration → SetFormattedText (countdown)
```

The GCD-vs-real-CD visual decision is made entirely C-side via `cdObject:EvaluateRemainingDuration(curve)`. The IconGrid maintains step-shaped alpha and color curves built from `cfg.readyAlpha` / `cfg.cooldownAlpha` / `cfg.cooldownTint`: remaining ≤ ~1.6s evaluates to ready visuals, anything beyond evaluates to cooldown visuals. Lua never compares the secret remaining time directly. See `modules/IconGrid.lua` `BuildCurves`.

User input (drag, settings panel widget, slash command) flows through
`Helpers.Set(path, section, value)` in `settings/Panel.lua`, which
writes `db.profile.<path>` and fires
`KickCD_CONFIG_CHANGED { section = ... }`. IconGrid and Castbar handle
each section appropriately. AceDB callbacks fire `KickCD_PROFILE_CHANGED`
on profile change/copy/reset.

Slash commands that mutate schema-backed fields (e.g. `/kcd lock`,
`/kcd debug log`) route through `Helpers.SetAndRefresh(path, value)`
so they share the panel widgets' write/notify/refresh code path
(`Helpers.Set` → schema row's `onChange` → `RefreshAllPanels`). That way
a future `onChange` added to a row doesn't silently diverge between the
two paths.

Visibility / interruptibility decisions for both the icon grid and the
cast bar use a two-step gate driven by the addon-wide
`db.profile.visibility` mode:

```
shouldBeVisible() / isVisible()
  ── always                      → true
  ── in_combat                   → _inCombat (PLAYER_REGEN_* flag, NOT
                                    InCombatLockdown — that lags by a frame)
  ── target_casting              → UnitCastingInfo / UnitChannelInfo("target") truthy
  ── target_casting_interruptible → KickCD.State.IsHostileUnitCasting("target")
        ▼
   Show / Hide
        ▼
   ApplyInterruptibilityMask / ApplyVisibilityMask
        ▼
   KickCD.State.ApplyInterruptibleAlpha(frame, "target", 1)
        ▼ (C-side, secret-safe)
   frame:SetAlphaFromBoolean(notInterruptible, 0, 1)
```

`KickCD.State.IsHostileUnitCasting` is a pure truthy check (safe even
when `name` / `texture` come back secret-tainted in combat) plus a
`UnitCanAttack` filter. `KickCD.State.ApplyInterruptibleAlpha` reads the
raw `notInterruptible` straight off `UnitCastingInfo` / `UnitChannelInfo`
and hands it to `Frame:SetAlphaFromBoolean` — the **one** C-side method
that accepts the secret-tainted bool form without erroring. Both helpers
live in `core/State.lua` (not `core/Compat.lua`) because they're feature
decisions about visibility, not API shape normalisation. So uninterruptible
casts run the full UI lifecycle (Show / glow start / cast bar drawn) but
at `alpha = 0`, with the visual filter applied entirely C-side. The
`UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE` events drive a
re-application of the alpha mask mid-cast.

Per-icon ready glow follows the same pattern: `Icon:UpdateGlow` starts the
LibCustomGlow effect for any hostile target cast under the
`target_casting_interruptible` trigger and then drives the glow frame's
alpha through `ApplyInterruptibleAlpha`. The IconGrid's `RefreshAllGlows`
re-runs the per-icon decision on `PLAYER_TARGET_CHANGED` and every cast
event so the glow gate stays in sync.

Cast bar pipeline (independent of the cooldown pipeline above):

```
PLAYER_TARGET_CHANGED / UNIT_SPELLCAST_*  (filtered to unit == "target")
        │
        ▼
Castbar:Reevaluate ──► Compat.GetCastingInfo("target")
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

The IconGrid emits `KickCD_GRID_LAYOUT { gridFrame, primaryIcon, width,
height }` after every `Layout()` pass. The Castbar listens so it can
re-anchor under the `PRIMARY` anchor mode (the primary icon button
reference may have moved — read directly from the payload's
`primaryIcon`, with a fallback to `KickCD.IconGrid:GetPrimaryIcon` for
the first tick after enable) and re-run `Reskin` when `castbar.autoSize`
is on (the grid frame's footprint may have changed — read from the
payload's `gridFrame` / `width` / `height`).

A `Cooldowns:Refresh` whose `PollSpell(id)` returns `nil` for a
previously-watched id (pet dismissed, talent untrained, encounter
mechanic suppresses the spell) emits a final sentinel
`KickCD_SPELL_STATE { spellID, ready=false, isActive=false, cdObject=nil,
chargeCdObject=nil, charges=nil }` and unwatches the id. Without it the
icon would render the last-known state until the next `Rebuild` —
which `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED` typically cover, but
not all paths fire those events.

