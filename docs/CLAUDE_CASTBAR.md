# Cast bar module

`modules/Castbar.lua` shows the player's target's cast/channel on a separately-anchored bar. The lock state is shared with the icon grid (`db.profile.locked`) — one unlock/lock cycle moves both. While unlocked the bar shows a placeholder preview when no target is casting so it can be grabbed.

Two anchor modes (`db.profile.castbar.anchorMode`):
- **FREE** — drag to position, persisted to `db.profile.anchors.castbar`.
- **PRIMARY** — `SetPoint` against the icon grid's primary icon button using the configured `(anchorPoint, castbarPoint, anchorOffsetX, anchorOffsetY)` tuple, both translated from the 13-option `<SIDE>_<ALIGN>` / `CENTER` form via the `SETPOINT_MAP` table in `modules/Castbar.lua` (legacy 9-point tokens like `TOPLEFT` / `BOTTOM` from older saved profiles still pass through unchanged). Drag is forced off in this mode regardless of the global lock; the bar follows the grid for free. The Castbar listens to `KickCD_GRID_LAYOUT` so it re-anchors when the primary icon button reference changes (e.g. when the grid rebuilds against a new spec). The same listener re-runs `ApplyConfig` when `castbar.autoSize` is on so the bar's orientation-relevant dimension tracks the grid's actual visible footprint — `IconGrid:Layout` sizes the grid frame against `usedRows * usedCols` (the rectangular area occupied by the visible icons), not the configured `secondaryRows * secondaryCols` capacity, so disabling a spell shrinks the bar instead of leaving phantom width.

Orientation: `HORIZONTAL` and `VERTICAL`. The "rotate by 90°" mental model is faked C-side — `ApplyConfig` swaps which physical axis maps to width vs height, then drives `StatusBar:SetOrientation` and `SetReverseFill` so all per-frame texture-growth math stays C-side. Vertical mode also rotates the spark texture 90° so it reads as a horizontal slash across the fill edge. `growDirection`'s option list depends on `orientation` (`RIGHT`/`LEFT` for horizontal, `UP`/`DOWN` for vertical) and is enforced via the schema row's `valueGate = "castbar.orientation"`.

Visibility is gated by **all** of: the master enable, `castbar.enabled`, and the addon-wide `db.profile.visibility` mode (the same setting the icon grid honors). In `"in_combat"` mode the bar additionally requires the event-driven combat flag (`PLAYER_REGEN_*`) — `InCombatLockdown()` lags the regen events by a frame and isn't reliable. While unlocked, visibility is bypassed so the user can move the bar.

The original implementation broke in 12.0 because `UnitCastingInfo` positions 4–5 (`startTimeMS` / `endTimeMS`) come back as secret values in tainted scope for casts the player can interrupt with a protected interrupt. Arithmetic / compare / format / `tostring` on a secret raises a Lua error, so an `OnUpdate` doing `(GetTime() - startSec) / (endSec - startSec)` blows up the moment combat opens against an interruptable target.

**The key API: `UnitCastingDuration(unit)` / `UnitChannelDuration(unit)`.** These return a `CastingDuration` object whose `:GetTotalDuration()` / `:GetElapsedDuration()` / `:GetRemainingDuration()` / `:GetStartTime()` / `:GetEndTime()` methods supply the timing primitives. This is structurally similar to the `CooldownDuration` object KickCD already uses in `modules/Cooldowns.lua` — and **subject to the same secret-in-combat protection**. The methods *do* return secret-tainted numbers in combat for protected casts. The trick is identical to the cooldown pattern: never bind the return to a Lua local; pass the method call **directly as an argument** to a Blizzard C method that accepts secret args.

The Compat shim funnels both UnitCastingInfo (for `name` / `texture` / `notInterruptible` / `spellID`) and UnitCastingDuration (for the timing object) into a single record:

```
{ name, texture, spellID, notInterruptible, isChannel, duration }
```

The OnUpdate loop drives the bar by passing the duration methods *as arguments* to Blizzard C methods:

```lua
frame.bar:SetMinMaxValues(0, d:GetTotalDuration())
if current.isChannel then
    frame.bar:SetValue(d:GetRemainingDuration())   -- drains total → 0
else
    frame.bar:SetValue(d:GetElapsedDuration())     -- fills 0 → total
end
frame.timeText:SetFormattedText(
    "%.1f / %.1f", d:GetRemainingDuration(), d:GetTotalDuration())
```

`SetMinMaxValues`, `SetValue`, and `SetFormattedText` all accept secret args without erroring; the format string is interpreted C-side. **No `local total = d:GetTotalDuration()` followed by `if total > 0` anywhere** — that's the four-iteration trap.

**End-of-cast detection lives in events, not OnUpdate.** `if remaining <= 0 then Stop() end` would be a secret comparison and would error. Stop happens on `UNIT_SPELLCAST_STOP` / `_FAILED` / `_INTERRUPTED` / `_CHANNEL_STOP` (filtered to `unit == "target"`).

**The spark uses a static anchor, not per-frame arithmetic.** Computing `frame.spark:SetPoint("CENTER", frame.bar, "LEFT", barWidth * (elapsed / total), 0)` would error on the `elapsed / total` division. Instead, anchor once in `ApplyConfig` to `frame.bar:GetStatusBarTexture()`'s RIGHT edge — Blizzard reanchors the inner status texture C-side as the bar value changes, so the spark follows the fill edge automatically for both casts (texture grows left → right) and channels (texture shrinks right → left).

**`name` and `texture` may themselves be secret in combat for protected casts.** Pass them through to `FontString:SetText` and `Texture:SetTexture` anyway — those C methods accept secret args without erroring (Blizzard's protection is on arithmetic, not on UI render calls). Do **not** call `tostring(name)`, `:format("...", name)`, `if name == "..." then`, or any operation that'd treat the value as data — same secret-value guard the original Castbar tripped on `endTimeMS`.

**`notInterruptible` is a secret boolean.** It stays plain on non-protected casts but is secret in the same scenario `name` / `texture` are. Don't compare or `not` it — only feed it to `C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, valueIfTrue, valueIfFalse)`, which is a Blizzard secure function that accepts a (possibly secret) boolean and a pair of plain values, returning whichever matches.

**Friendly-target override.** The raw `notInterruptible` from `UnitCastingInfo` reports whether the spell is *flagged* uninterruptible (whether spell-interrupt mechanics work on it at all). It does **not** consider whether *you* can practically interrupt the cast — you can't interrupt yourself, you can't interrupt friendlies, regardless of the flag. `Compat.effectiveNotInterruptible(unit, raw)` overrides the value to `true` (force "uninterruptible" visuals) when `UnitCanAttack("player", unit)` is false. This is why a mount cast on yourself colors red even though `UnitCastingInfo.notInterruptible` is `false` — the mount's API flag says "interruptible" (because Counterspell would work on you in PvP), but from the user's perspective the cast is non-interruptable.

KickCD uses this to render distinct visuals for interruptible vs uninterruptible casts. The cast bar carries **stacked dual widgets** for everything that can't be expressed as a scalar curve evaluation:

- `frame.bgInterruptible` / `frame.bgUninterruptible` — two BACKGROUND textures, alpha-switched.
- `frame.bar.interruptible` / `frame.bar.uninterruptible` — two `StatusBar`s at identical anchors. OnUpdate calls `SetMinMaxValues` / `SetValue` on **both**, so their inner status textures track together; only one is alpha-visible at a time.
- `frame.borderInterruptible` / `frame.borderUninterruptible` — two `BackdropTemplate` frames with their own LSM border textures, edge sizes, and colors. Border show toggles fold *into* the curve params (passing `0` for the off side) rather than as a multiplier afterwards — multiplying a secret curve result would error.
- `frame.nameText` (single `FontString`) — color is per-state but a single FontString suffices because we curve-evaluate each RGBA channel separately and pass all four results directly to `SetTextColor(r, g, b, a)`.

Each curve evaluation looks like:

```lua
frame.barInterruptible:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(
    current.notInterruptible, 0, 1))   -- visible when interruptible
frame.barUninterruptible:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(
    current.notInterruptible, 1, 0))   -- visible when uninterruptible
```

The result of `EvaluateColorValueFromBoolean` may itself be secret-tainted; pass it directly to `SetAlpha` / `SetTextColor` and never bind to a Lua local. Same rule as the duration object's methods — Blizzard C methods accept secret args; Lua arithmetic does not.

Texture differentiation between states (different statusbar textures, different LSM border edge files) genuinely requires two stacked widgets — the texture *path* is a string, not a number, and there's no way to curve-switch a string. Color / alpha / thickness / show-toggle differentiation only needs the curve evaluator and folds into the same widget.

**Spell-name truncate cap.** `castbar.nameTruncate` (0 = unlimited) trims the spell-name string in `truncateName` before handing it to `FontString:SetText`. The helper is byte-counted via `#` (so multi-byte UTF-8 names may truncate mid-character at the edge but won't error) and short-circuits via `issecretvalue` — secret-tainted names pass through verbatim to `SetText` (which is C-side safe), losing the truncation for that frame rather than throwing. `ApplyConfig` re-paints the name when called mid-cast so a config change (truncate cap, `showName`) takes effect immediately.

**Anti-pattern that I tried and burned my hands on:** sourcing `castTime` from `C_Spell.GetSpellInfo(spellID)` to size a fallback timeline. The whole returned table is tainted in combat against an interruptable target — *every* field comes back secret (`name`, `castTime`, `iconID`, `minRange`, `maxRange`, `originalIconID`). Reading `info.castTime` into a Lua local and comparing it to `0` errors the same way `endTimeMS` does. UnitCastingDuration sidesteps the whole problem — there's no reason to fall back when the duration object is available.

**Anti-patterns explicitly avoided** (each one was tried and broke; don't repeat):
- Reading `startTimeMS` / `endTimeMS` from `UnitCastingInfo` and doing `(now - start) / (end - start)` arithmetic. (The original v0.1 Castbar bug.)
- Sourcing `castTime` from `C_Spell.GetSpellInfo(spellID)` for a fallback timeline. The whole returned table is tainted.
- Binding `CastingDuration:Get…Duration()` returns to a Lua local for `if x > 0` / `x / y` / `x <= 0`. Pass the method calls as arguments only.
- Computing the spark position from `barWidth * (elapsed / total)`. Anchor to `bar:GetStatusBarTexture():RIGHT` and let Blizzard reposition C-side.
- Detecting end-of-cast in OnUpdate via `if remaining <= 0`. Use `UNIT_SPELLCAST_STOP` and friends.
- `tonumber` / `tostring` / `+0` / `securecallfunction` "detox" of secret values — see `core/Compat.lua` line 28.
- Using `CastingBarFrameTemplate` and pointing it at `"target"`. Its built-in `OnUpdate` does `GetTime() < self.maxValue`, which becomes `GetTime() < <secret>` and errors once the addon sets `maxValue` from a secret `endTime`.
- Restyling `TargetFrameSpellBar` (the default UI cast bar) instead of building a fresh frame.
- Gating `name` / `texture` / `notInterruptible` with `issecretvalue` and replacing with placeholders. They may be secret, but `Texture:SetTexture` / `FontString:SetText` / `C_CurveUtil.EvaluateColorValueFromBoolean` accept secret args without erroring — gating just makes the bar look worse for no benefit.

