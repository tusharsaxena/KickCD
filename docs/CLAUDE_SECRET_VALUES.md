# Critical: 12.0 secret-value protection

WoW 12.0 introduced "secret values" on certain protected API returns — notably `C_Spell.GetSpellCooldown` for interrupt spells and parts of `UnitCastingInfo` / `UnitChannelInfo`. From tainted (addon) execution, **comparison and arithmetic on a secret value raise a Lua error**, and there is no addon-side strip:

| Pattern | Result |
|---|---|
| `tonumber(secret)` | Still secret. |
| `tostring(secret)` | Still secret. |
| `secret + 0` (in addon scope) | Errors — `+` is the operation that fires. |
| `securecallfunction(fn, secret)` where `fn` is addon-defined | Still tainted; arithmetic inside still errors. |
| `:format("%.1f", secret)` | Errors. |
| Blizzard C methods (`Cooldown:SetCooldown`, `Texture:SetTexture`) with secret args | **Also rejects** — the error message says "Secret values are only allowed during untainted execution for this argument." |

**The rule:** never compare, do arithmetic on, format, or pass to most Blizzard C methods a value that might be secret. Either use a sibling field that is plain (e.g. `info.isActive` and `info.isEnabled` come back plain), or gate the operation with `issecretvalue(v)` and degrade gracefully (skip the op, hide the visual, etc.).

**Preferred workaround for cooldown timing:** use `C_Spell.GetSpellCooldownDuration(spellID)` (wrapped as `KickCD.Compat.GetSpellCooldownDuration`). It returns a `CooldownDuration` object that can be:

- Passed straight to `Cooldown:SetCooldownFromDurationObject(obj)` to drive the swipe.
- Passed to `FontString:SetFormattedText("%.1f", obj:GetRemainingDuration())` to render countdown text.
- Evaluated against a `C_CurveUtil.CreateCurve` / `CreateColorCurve` via `obj:EvaluateRemainingDuration(curve)` and the result passed to `Frame:SetAlphaFromBoolean(true, alpha, 0)` / `Texture:SetVertexColor(color:GetRGB())`.

**Critical caveat:** `obj:GetRemainingDuration()` returns a *secret-tainted* number in combat (plain out of combat). It is **only** safe as a direct argument to a Blizzard C method. Binding it to a Lua local for a comparison, format, tostring, or arithmetic op will error with "attempt to compare local '...' (a secret number value)" the moment combat opens. The same caveat applies to whatever `EvaluateRemainingDuration` returns — pass it through to a C method, never inspect it.

KickCD uses this API throughout: `modules/Cooldowns.lua` emits the duration object opaquely, `modules/IconGrid.lua` evaluates it against step-shaped alpha/tint curves to derive GCD-vs-real-CD visuals C-side. Reach for `C_Spell.GetSpellCooldown`'s raw `startTime`/`duration` only when you genuinely need them — and even then, gate with `issecretvalue` first because in combat *every* watched spell's timings come back secret.

Why curves instead of a `UNIT_SPELLCAST_SUCCEEDED` cast tracker for GCD filtering? Blizzard suppresses that event for protected interrupts (Mind Freeze, Pummel, Kick, Spear Hand Strike, …) — the event simply does not fire when the player casts one of those spells in tainted scope. So a cast-event tracker can never flip the primary icon's state. Curve evaluation runs entirely C-side and works for protected and unprotected spells alike.

The Cell addon's PR #457 is the canonical reference for the `issecretvalue()`-based pattern; see comments in `core/Compat.lua` and `modules/IconGrid.lua` for the rationale recorded in-tree.

Do not propose `securecallfunction` / `tonumber` / `+0` "detox" workarounds — they were tried and don't work. Comments document this so we don't re-try.

## Cast interruptibility (`UnitCastingInfo` / `UnitChannelInfo`)

`notInterruptible` (position 8 of `UnitCastingInfo`, position 7 of `UnitChannelInfo`) is **secret-tainted in 12.0** for any cast the player has a protected interrupt against. It is the same trap as cooldown timings: `not nint`, `nint == true`, `if nint then`, `tostring(nint)` all error in combat.

**Do not** try to make a Lua-side boolean decision out of it. `KickCD.Compat.IsCastingInterruptible` was the original attempt and silently broke the visibility / glow gates because the secret-taint branch had to conservatively return `true`, which meant uninterruptible casts were treated as interruptible.

**The 12.0-correct pattern**, lifted from FloatingInterruptHighlight (`FloatingInterruptHighlight.lua:123-138`): split the gate in two —

1. `Compat.IsHostileUnitCasting(unit)` — a plain truthy check on the API's `name` return (safe, even when secret) plus a `UnitCanAttack` filter. Drives `Show` / `Hide`.
2. `Compat.ApplyInterruptibleAlpha(frame, unit, alpha)` — pulls the raw `notInterruptible` and pipes it straight into `frame:SetAlphaFromBoolean(notInterruptible, 0, alpha)`. `SetAlphaFromBoolean` is the **one** C-side method that accepts the secret-tainted bool form without erroring.

So uninterruptible casts run the full UI lifecycle (Shown frame, started glow animation, drawn cast bar) but at `alpha = 0` — the visual filter is C-side and the Lua decision is never made. `UNIT_SPELLCAST_INTERRUPTIBLE` / `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` events drive a re-application of the alpha mask mid-cast. See `modules/IconGrid.lua` (`ApplyInterruptibilityMask`, `Icon:UpdateGlow`) and `modules/Castbar.lua` (`ApplyVisibilityMask`).

