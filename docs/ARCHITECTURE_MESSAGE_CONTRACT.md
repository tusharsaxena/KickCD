# Closed message contract

Internal messages travel over AceEvent's per-addon bus (`KickCD:SendMessage` / `:RegisterMessage`). The full set:

| Message | Sender | Listeners | Payload | Notes |
|---|---|---|---|---|
| `KickCD_SPELL_STATE` | `Cooldowns:Rebuild` / `Refresh` | `IconGrid` | `{ spellID, ready, isActive, cdObject, chargeCdObject, charges }` | `cdObject` is the secret-aware `CooldownDuration` from `C_Spell.GetSpellCooldownDuration`; non-nil whenever `isActive` is true (real CD or just-GCD). `chargeCdObject` is set when the spell has charges and at least one is missing while `isActive=false` — i.e. a recharge timer is ticking but the spell is still castable; the IconGrid renders the recharge swipe + countdown text without the cooldown alpha/tint. `:GetRemainingDuration()` on either handle is secret in combat — only pass directly to C methods. `charges` may also be secret. |
| `KickCD_CONFIG_CHANGED` | `settings/Panel.lua Helpers.Set`, `core/KickCD.lua` (lock/unlock, debug log toggle), `settings/General.lua` (Reset position), `settings/Spells.lua` (debounced editor commits) | `IconGrid`, `Cooldowns`, `Castbar` | `{ section = "general"\|"icons"\|"castbar"\|"spells" }` | section-keyed for cheap dispatch. `Cooldowns` only acts on `"general"` (master enable) and `"spells"` (rebuild watched list); `IconGrid` acts on all four; `Castbar` acts on `"general"` and `"castbar"`. |
| `KickCD_PROFILE_CHANGED` | `Database:OnProfileChanged` (AceDB callback) | `IconGrid`, `Cooldowns`, `Castbar`, `settings/Spells.lua` | `{ newProfileKey }` | fires for `OnProfileChanged` / `Copied` / `Reset` |
| `KickCD_GRID_LAYOUT` | `IconGrid:Layout` (every pass, including the empty-list case) | `Castbar` | `{}` | The Castbar uses this to re-anchor under `castbar.anchorMode = "PRIMARY"` (the primary icon button reference may have moved) and to re-run `ApplyConfig` when `castbar.autoSize` is on (the grid frame's footprint may have changed). |

The set is closed by convention — module headers and `CLAUDE.md` reference this list. Adding a message means updating both the source emitter, every consumer, and this table.

