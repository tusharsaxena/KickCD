# Compat layer

Spell APIs have churned across recent expansions. `core/Compat.lua` provides a stable surface for those — and **only** those: it does API-shape normalization, not feature decisions.

The visibility helpers `IsHostileUnitCasting` / `ApplyInterruptibleAlpha` (the two-step gate behind `target_casting_interruptible` mode) live in `core/State.lua` instead, since they're addon-policy decisions rather than API shims. The Settings registration shim (`Settings.RegisterAddOnSetting`) was removed entirely — the canvas widgets bind directly to `db.profile` via `Helpers.Get` / `Helpers.Set` and never went through Blizzard's Setting object lifecycle.

## `Compat.*` surface

| Compat function | Wraps | 12.0 caveats |
|---|---|---|
| `Compat.GetSpellCooldown(id)` | `C_Spell.GetSpellCooldown` (table) → `_G.GetSpellCooldown` (tuple) | Returns `(start, duration, isEnabled, modRate, isActive)`; `start`/`duration`/`modRate` may be secret. Use `isActive` (plain) for "is on cooldown" decisions. |
| `Compat.GetSpellCooldownDuration(id)` | `C_Spell.GetSpellCooldownDuration` | Returns a secret-aware `CooldownDuration` object (or nil). Pass to `Cooldown:SetCooldownFromDurationObject`, `FontString:SetFormattedText("%.1f", obj:GetRemainingDuration())`, or `obj:EvaluateRemainingDuration(curve)`. **`:GetRemainingDuration()` is secret in combat** — only pass directly to a C method; never bind to a Lua local for compare / format / tostring. |
| `Compat.GetSpellInfo(id)` | `C_Spell.GetSpellInfo` (table) → `_G.GetSpellInfo` (tuple) | — |
| `Compat.GetSpellTexture(id)` | `C_Spell.GetSpellTexture` → `_G.GetSpellTexture` | Texture may be secret on guarded spells; gate with `issecretvalue` before `SetTexture`. |
| `Compat.GetSpellCharges(id)` | `C_Spell.GetSpellCharges` (table) → `_G.GetSpellCharges` (tuple) | Charges may be secret on guarded spells. |
| `Compat.IsSpellUsable(id)` | `C_Spell.IsSpellUsable` → `_G.IsUsableSpell` | Returns `(usable, noMana)` regardless of underlying shape. Some 12.0 builds return a `SpellUsabilityInfo` table; the shim covers both paths. |
| `Compat.IsSpellAvailable(id)` | `_G.IsPlayerSpell` + `_G.IsSpellKnown(id)` + `_G.IsSpellKnown(id, true)` | "Can the player actually cast this *right now*" — distinct from `GetSpellInfo` (which only proves the ID exists in the spell DB). `IsPlayerSpell` covers talent choice nodes (only the chosen branch returns true); `IsSpellKnown(id)` catches racials / profession spells; `IsSpellKnown(id, true)` catches pet spells like Counter Shot / Spell Lock / Optical Blast (only true while the matching pet is summoned). Used by `Cooldowns:PollSpell` and `IconGrid:BuildActiveList` to hide unavailable entries from default lists (e.g. Blood DK's Gorefiend's Grasp ↔ Abomination Limb choice node only renders the picked branch). |
| `Compat.GetCastingInfo(unit)` | `_G.UnitCastingInfo` + `_G.UnitCastingDuration` (falls through to `Compat.GetChannelInfo` when not casting) | Returns a record `{ name, texture, spellID, notInterruptible, isChannel, duration }`. `name` / `texture` / `notInterruptible` / `spellID` may be secret-tainted in combat — pass through to `Texture:SetTexture` / `FontString:SetText` / `C_CurveUtil.EvaluateColorValueFromBoolean` only; never compare or format. `notInterruptible` is post-processed by `effectiveNotInterruptible` so friendly / self casts always force "uninterruptible" visuals regardless of the API flag. |
| `Compat.GetChannelInfo(unit)` | `_G.UnitChannelInfo` + `_G.UnitChannelDuration` | Same record shape as the cast variant with `isChannel = true`. The signature is one position shorter than `UnitCastingInfo` (no `isTradeSkill` slot) — the shim hides that. |
| `Compat.GetSpecialization()` | `C_SpecializationInfo.GetSpecialization` → `_G.GetSpecialization` | Returns the active spec index. Prefers the post-11.x `C_SpecializationInfo` namespace and falls back to the deprecated global `GetSpecialization()`. All spec-API call sites in the feature modules route through this — no direct `GetSpecialization` remains outside Compat. |
| `Compat.GetSpecializationInfo(index)` | `C_SpecializationInfo.GetSpecializationInfo` → `_G.GetSpecializationInfo` | Multi-return passthrough for a spec index (id, name, description, icon, …). Prefers the `C_SpecializationInfo` namespace and falls back to the deprecated global. No direct `GetSpecializationInfo` remains outside Compat. |
| `Compat.DebugInterrupt(unit)` | n/a — diagnostic over `_G.UnitCastingInfo` / `_G.UnitChannelInfo` | Backs `/kcd debug interrupt`. Prints every positional return with its `type()` and `issecretvalue()` flag, plus what `NS.State.IsHostileUnitCasting` and the visibility/glow logic decided. Renders through a `safeRender` helper that short-circuits secret values to `<secret>`, so the dump never `tostring`s a secret. |
| `Compat._firstReturn(fn, ...)` | n/a — internal helper | Returns the first return of `fn(...)` or `nil` if `fn` is missing. Used to taint-safely truthy-check `_G.UnitCastingInfo(unit)` and `_G.UnitChannelInfo(unit)` (whose first return is `name`, the only position that's reliably truthy) without binding the multi-return to a Lua local that might capture a secret-tainted positional return. |

## State helpers (visibility / policy)

The visibility helpers were formerly in this layer; they were relocated to `core/State.lua` in CR-27 because they're addon-policy decisions, not API normalization:

| Visibility helper | Lives in | Purpose |
|---|---|---|
| `NS.State.SetInCombat(v)` | `core/State.lua` | The single write seam for the `NS.State.inCombat` flag. Called only by that file's bootstrap `CreateFrame` on `PLAYER_REGEN_DISABLED` / `_ENABLED` / `PLAYER_LOGIN`; it writes the flag and then fires `Ka0s_KickCD_COMBAT_STATE` so subscribers see the write land before their handler runs. |
| `NS.State.IsHostileUnitCasting(unit)` | `core/State.lua` | Visibility GATE for `target_casting_interruptible` mode. Returns whether `unit` exists, is hostile (`UnitCanAttack`), and has an active cast/channel. Pure truthy-check — safe even when the API's positional returns are secret-tainted. |
| `NS.State.ApplyInterruptibleAlpha(frame, unit, alpha)` | `core/State.lua` | The 12.0-correct interruptibility filter. Reads `notInterruptible` from `UnitCastingInfo` / `UnitChannelInfo` and passes the (possibly secret) flag straight to `Frame:SetAlphaFromBoolean(notInterruptible, 0, alpha)` — the **one** C-side method that accepts the secret bool form without erroring. Returns `true` if the mask was applied, `false` if the unit isn't hostile-casting (caller falls back to its own alpha policy). |

## Boundary rule

Modules call into `Compat.*` for spell-API normalization and `NS.State.*` for visibility decisions. **Direct calls to `C_Spell.*` or `_G.GetSpell*` outside `Compat.lua` are a smell.**

The IconGrid and Castbar modules read `_G.UnitCastingInfo` / `_G.UnitChannelInfo` directly for the addon-wide visibility gate — they only check whether the first return is non-nil through `Compat._firstReturn`, which is a taint-safe truthy check, and never inspect the secret positions themselves. The full secret-value rules live in [midnight-quirks.md](midnight-quirks.md).
