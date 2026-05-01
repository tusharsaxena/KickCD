# Module layout and boot order

TOC load order (see `KickCD.toc`):

1. `libs/` — vendored Ace3 + LibSharedMedia. Don't edit.
2. `locales/enUS.lua` — sets up `KickCD.L` with a missing-key fallback.
3. `core/Compat.lua` — bootstraps `_G.KickCD`, hangs `Compat` shims for spell APIs and `Settings.RegisterAddOnSetting`. **Loads first** of core/ — anything later can rely on `KickCD.Compat` existing.
4. `core/Util.lua` — color helpers, anchor save/restore, debounce, chat print.
5. `core/Database.lua` — defines `DEFAULT_PROFILE` and `Database:Init` (called from `KickCD:OnInitialize`). Does not create the DB at file-load time.
6. `core/KickCD.lua` — promotes the bootstrap table to an AceAddon, registers slash commands, defines the slash dispatch tables.
7. `defaults/Spells.lua` — populates `KickCD.DefaultSpells` (per-class+spec interrupt list); merged into the profile by `Database:BuildSpells` on first profile creation.
8. `modules/Cooldowns.lua` — polls cooldown state, emits `KickCD_SPELL_STATE`. Listens for `SPELL_UPDATE_COOLDOWN/USABLE/CHARGES`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED` (the last two pick up talent-choice swaps and pet summon/dismiss without waiting for a spec change).
9. `modules/IconGrid.lua` — owns the `KickCDIconGrid` frame and per-icon widgets, the per-icon ready glow (LibCustomGlow), and the visibility-mode gate. Listens for the four `KickCD_*` messages plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_REGEN_DISABLED/_ENABLED`, `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START/_STOP/_FAILED/_INTERRUPTED/_CHANNEL_START/_CHANNEL_STOP/_INTERRUPTIBLE/_NOT_INTERRUPTIBLE`). Emits `KickCD_GRID_LAYOUT` after every layout pass.
10. `modules/Castbar.lua` — owns the `KickCDCastbar` frame; mirrors the player's target's cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration` shims (see [CLAUDE_CASTBAR.md](CLAUDE_CASTBAR.md)). Stacked dual widgets (background, statusbar, border) are alpha-curve-switched on the cast's secret `notInterruptible` bool. Anchors free or to the icon grid's primary icon button (re-anchors on `KickCD_GRID_LAYOUT`). Auto-size mode tracks the grid frame's actual visible footprint, not its configured rows × cols capacity.
11. `settings/Panel.lua` — registers the top-level Blizzard Settings category, the per-tab builder mailbox, the schema renderer (`Helpers.RenderSchema`), the always-visible-scrollbar patch (`Helpers.PatchAlwaysShowScrollbar`), and the shared write-and-refresh helpers (`Helpers.Set`, `Helpers.SetAndRefresh`, `Helpers.RestoreDefaults`, `Helpers.RestoreAllDefaults`, `Helpers.ResetAll`, `Helpers.ResetIconPosition`, `Helpers.AnchorValues`, `Helpers.LSMValues`).
12. `settings/{General,Icons,Castbar,Spells,Profiles}.lua` — register their tabs via `KickCD.Settings.RegisterTab`. General / Icons / Cast bar are pure schema (rows in `KickCD.Settings.Schema`); Spells parents an AceGUI editor to `ctx.body`; Profiles parents an AceConfigDialog into `ctx.body` for the AceDBOptions table.

