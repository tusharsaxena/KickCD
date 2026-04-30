# Compat layer

Spell APIs and the Settings registration API have churned across recent expansions. `core/Compat.lua` provides a stable surface:

| Compat function | Wraps | 12.0 caveats |
|---|---|---|
| `Compat.GetSpellCooldown(id)` | `C_Spell.GetSpellCooldown` (table) → `_G.GetSpellCooldown` (tuple) | Returns `(start, duration, isEnabled, modRate, isActive)`; `start`/`duration`/`modRate` may be secret. Use `isActive` (plain) for "is on cooldown" decisions. |
| `Compat.GetSpellCooldownDuration(id)` | `C_Spell.GetSpellCooldownDuration` | Returns a secret-aware `CooldownDuration` object (or nil). Pass to `Cooldown:SetCooldownFromDurationObject`, `FontString:SetFormattedText("%.1f", obj:GetRemainingDuration())`, or `obj:EvaluateRemainingDuration(curve)`. **`:GetRemainingDuration()` is secret in combat** — only pass directly to a C method; never bind to a Lua local for compare / format / tostring. |
| `Compat.GetSpellInfo(id)` | `C_Spell.GetSpellInfo` (table) → `_G.GetSpellInfo` (tuple) | — |
| `Compat.GetSpellTexture(id)` | `C_Spell.GetSpellTexture` → `_G.GetSpellTexture` | Texture may be secret on guarded spells; gate with `issecretvalue` before `SetTexture`. |
| `Compat.GetSpellCharges(id)` | `C_Spell.GetSpellCharges` (table) → `_G.GetSpellCharges` (tuple) | Charges may be secret on guarded spells. |
| `Compat.IsSpellUsable(id)` | `C_Spell.IsSpellUsable` → `_G.IsUsableSpell` | Returns `(usable, noMana)` regardless of underlying shape. |
| `Compat.RegisterAddOnSetting(...)` | `Settings.RegisterAddOnSetting` | Tries the 12.0+ `(category, variable, variableKey, variableTbl, varType, name, default)` shape first; falls back through 11.0 / 10.0 shapes via `pcall`. **Vestigial** — no live caller; canvas-layout panels bind directly to `db.profile`. |

Modules call into `Compat.*` exclusively; direct calls to `C_Spell.*` or `_G.GetSpell*` outside `Compat.lua` are a smell.
