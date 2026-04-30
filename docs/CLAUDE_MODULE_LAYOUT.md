# Module layout and boot order

TOC load order (see `KickCD.toc`):

1. `libs/` — vendored Ace3 + LibSharedMedia. Don't edit.
2. `locales/enUS.lua` — sets up `KickCD.L` with a missing-key fallback.
3. `core/Compat.lua` — bootstraps `_G.KickCD`, hangs `Compat` shims for spell APIs and `Settings.RegisterAddOnSetting`. **Loads first** of core/ — anything later can rely on `KickCD.Compat` existing.
4. `core/Util.lua` — color helpers, anchor save/restore, debounce, chat print.
5. `core/Database.lua` — defines `DEFAULT_PROFILE` and `Database:Init` (called from `KickCD:OnInitialize`). Does not create the DB at file-load time.
6. `core/KickCD.lua` — promotes the bootstrap table to an AceAddon, registers slash commands, defines the slash dispatch tables.
7. `defaults/Spells.lua` — populates `KickCD.DefaultSpells` (per-class+spec interrupt list); merged into the profile by `Database:BuildSpells` on first profile creation.
8. `modules/Cooldowns.lua` — polls cooldown state, emits `KickCD_SPELL_STATE`.
9. `modules/IconGrid.lua` — owns the `KickCDIconGrid` frame and per-icon widgets; persistent visibility.
10. `modules/Castbar.lua` — owns the `KickCDCastbar` frame; mirrors the player's target's cast/channel via secret-value-gated `UnitCastingInfo` shims (see [CLAUDE_CASTBAR.md](CLAUDE_CASTBAR.md)).
11. `settings/Panel.lua` — registers the top-level Blizzard Settings category and the per-tab builder mailbox.
12. `settings/{General,Icons,Castbar,Spells,Profiles}.lua` — register their tabs via `KickCD.Settings.RegisterTab`.
