# Closed message contract

Internal messages travel over AceEvent's per-addon bus (`KickCD:SendMessage` / `:RegisterMessage`). The full set:

| Message | Sender | Listeners | Payload | Notes |
|---|---|---|---|---|
| `KickCD_SPELL_STATE` | `Cooldowns:Rebuild` / `Refresh` | `IconGrid` | `{ spellID, ready, isActive, cdObject, chargeCdObject, charges }` | `cdObject` is the secret-aware `CooldownDuration` from `C_Spell.GetSpellCooldownDuration`; non-nil whenever `isActive` is true (real CD or just-GCD). `chargeCdObject` is set when the spell has charges and at least one is missing while `isActive=false` — i.e. a recharge timer is ticking but the spell is still castable; the IconGrid renders the recharge swipe + countdown text without the cooldown alpha/tint. `:GetRemainingDuration()` on either handle is secret in combat — only pass directly to C methods. `charges` may also be secret. |
| `KickCD_CONFIG_CHANGED` | `settings/Panel.lua Helpers.Set`, `core/KickCD.lua` (lock/unlock) | `IconGrid`, `Cooldowns` | `{ section = "general"\|"icons"\|"spells" }` | section-keyed for cheap dispatch |
| `KickCD_PROFILE_CHANGED` | `Database:OnProfileChanged` (AceDB callback) | `IconGrid`, `Cooldowns` | `{ newProfileKey }` | fires for `OnProfileChanged` / `Copied` / `Reset` |

The set is closed by convention — module headers and `CLAUDE.md` reference this list. Adding a message means updating both the source emitter, every consumer, and this table.
