# Boot sequence

1. **TOC file-load (`KickCD.toc`):** libs → locales → `core/Compat.lua` (creates `_G.KickCD` table and `KickCD.Compat`) → `core/Util.lua` → `core/Database.lua` (defines class, doesn't init) → `core/KickCD.lua` (`AceAddon-3.0:NewAddon` promotes `_G.KickCD` in place to an AceAddon object) → `defaults/Spells.lua` (sets `KickCD.DefaultSpells`) → modules (each calls `KickCD:NewModule`) → settings (each calls `KickCD.Settings.RegisterTab`).

2. **`KickCD:OnInitialize` (Ace lifecycle, fires on `ADDON_LOADED`):** `Database:Init` builds the AceDB instance and seeds spells from `KickCD.DefaultSpells` on first profile creation. Slash commands `/kickcd` and `/kcd` are registered.

3. **`<Module>:OnEnable`:** modules subscribe to messages and game events.
   - `Cooldowns:OnEnable` registers `SPELL_UPDATE_COOLDOWN` / `_USABLE` / `_CHARGES`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, plus `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED` so a talent-choice swap or pet summon flips the watched-list immediately.
   - `IconGrid:OnEnable` seeds the combat flag from `InCombatLockdown()` (reliable at enable-time), builds the frame, runs `BuildCurves` / `BuildActiveList` / `Layout` / `RefreshVisibility`, then registers the four `KickCD_*` messages plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, the regen pair (`PLAYER_REGEN_DISABLED` / `_ENABLED`), `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START` / `_STOP` / `_FAILED` / `_INTERRUPTED` / `_CHANNEL_START` / `_CHANNEL_STOP` / `_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE`) so the visibility mode and per-icon glow trigger react to the addon-wide visibility / target / cast / interruptibility state.
   - `Castbar:OnEnable` seeds the combat flag, builds the frame, runs `ApplyConfig` / `ApplyLock`, registers the same regen + target + cast-event family (the bar's own copy — both modules listen independently), plus `KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT`, then calls `Reevaluate` so a login while staring at a casting hostile mob shows the bar immediately.

4. **`PLAYER_LOGIN` (deferred from `settings/Panel.lua`):** the Blizzard Settings category is registered and per-tab builders run. Late-loading tabs auto-register if the main category already exists.

