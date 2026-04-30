# Boot sequence

1. **TOC file-load (`KickCD.toc`):** libs → locales → `core/Compat.lua` (creates `_G.KickCD` table and `KickCD.Compat`) → `core/Util.lua` → `core/Database.lua` (defines class, doesn't init) → `core/KickCD.lua` (`AceAddon-3.0:NewAddon` promotes `_G.KickCD` in place to an AceAddon object) → `defaults/Spells.lua` (sets `KickCD.DefaultSpells`) → modules (each calls `KickCD:NewModule`) → settings (each calls `KickCD.Settings.RegisterTab`).

2. **`KickCD:OnInitialize` (Ace lifecycle, fires on `ADDON_LOADED`):** `Database:Init` builds the AceDB instance and seeds spells from `KickCD.DefaultSpells` on first profile creation. Slash commands `/kickcd` and `/kcd` are registered.

3. **`<Module>:OnEnable`:** modules subscribe to messages and game events. `Cooldowns:OnEnable` registers `SPELL_UPDATE_COOLDOWN/USABLE/CHARGES` + `PLAYER_ENTERING_WORLD` + `PLAYER_SPECIALIZATION_CHANGED`; `IconGrid:OnEnable` builds the frame, runs `BuildActiveList`, and shows the grid.

4. **`PLAYER_LOGIN` (deferred from `settings/Panel.lua`):** the Blizzard Settings category is registered and per-tab builders run. Late-loading tabs auto-register if the main category already exists.
