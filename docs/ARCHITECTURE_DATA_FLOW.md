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
`KickCD_CONFIG_CHANGED { section = ... }`. IconGrid handles each section
appropriately. AceDB callbacks fire `KickCD_PROFILE_CHANGED` on
profile change/copy/reset.
