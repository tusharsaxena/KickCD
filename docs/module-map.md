# Module map

Where each responsibility lives in the source tree, plus the TOC load order and the AceAddon lifecycle hooks. The TOC at `KickCD.toc` is the source of truth for load order — match this map to it before editing.

## Directory tree

```
KickCD (AceAddon)
├── core/
│   ├── Compat.lua    — API shims for spell + cast APIs (10.0–12.0). Pure
│                       API normalisation; no feature decisions.
│   ├── Constants.lua — KickCD.Const namespace for shared magic numbers
│                       (GCD_UPPER, panel paddings, castbar text insets)
│   ├── State.lua     — KickCD.State namespace for shared mutable state +
│                       visibility helpers (inCombat flag w/ bootstrap
│                       listener; IsHostileUnitCasting; ApplyInterruptibleAlpha)
│   ├── Util.lua      — color (Unpack), anchor (SaveAnchor / ApplyAnchor),
│                       Throttle, DeepCopy, NormalizeSpecToken /
│                       NormalizeClassToken, chat print
│   ├── Database.lua  — AceDB instance + DEFAULT_PROFILE + GetSpellList /
│                       EnsureSpellList helpers + spell-defaults merge +
│                       dbVersion / MigrateProfile scaffold
│   └── KickCD.lua    — AceAddon bootstrap + slash dispatch (COMMANDS /
│                       DEBUG_COMMANDS / SPELLS_COMMANDS) + OpenSettings
│                       (defers when subcategory not yet built)
├── defaults/
│   └── Spells.lua    — per-class+spec default interrupt lists (KickCD.DefaultSpells)
├── modules/
│   ├── Cooldowns.lua — polls Compat.GetSpellCooldown + GetSpellCooldownDuration,
│                       emits KickCD_SPELL_STATE; emits a sentinel state on
│                       poll-nil so vanished spells (pet dismissed, talent
│                       untrained) don't leave a stale icon
│   ├── IconGrid.lua  — owns KickCDIconGrid frame and pooled icon widgets;
│                       runs alpha/tint/GCD-suppress curves C-side; single
│                       shared cooldown-text ticker; spellID dedupe at build
│                       time; truncation warning at layout time; emits
│                       KickCD_GRID_LAYOUT { gridFrame, primaryIcon, width, height }
│   └── Castbar.lua   — owns KickCDCastbar frame (stacked dual StatusBars +
│                       per-state borders + spark); secret-value-gated
│                       UnitCastingDuration / UnitChannelDuration consumer;
│                       Reskin / RenderCast split keeps cast start hot-path light
└── settings/
    ├── Panel.lua     — top-level category + canvas-panel framework + schema
                        renderer + ValidateSchema + Util.Throttle wrapper
                        on the ColorPicker commit + always-show-scrollbar patch
    ├── General.lua   — schema rows for enable/lock/visibility/scale/alpha/
                        debugLog + Reset position + Reset all buttons
    ├── Icons.lua     — schema rows for icon grid sizing, colors, layout, glow
    ├── Castbar.lua   — schema rows for cast bar enable/anchor/orientation/
                        sizing/text/per-state appearance. Schema rows do NOT
                        carry onChange callbacks — Helpers.Set fires the bus
                        and the Castbar module's listener handles the redraw,
                        avoiding the double-dispatch the schema previously had
    ├── Spells.lua    — unified header + AceGUI per-class+spec spell editor.
                        Listens for KickCD_CONFIG_CHANGED { section = "spells" }
                        to refresh rows after a slash-command edit, and caches
                        the Cooldown Manager spell-set (invalidated on
                        TRAIT_CONFIG_UPDATED / PLAYER_SPECIALIZATION_CHANGED).
                        The cooldown-manager validation is scoped to the
                        player's active spec — editing a different class/spec
                        falls through to the lenient validateSpellInput path.
    └── Profiles.lua  — unified header + AceDBOptions UI (AceConfig in a SimpleGroup)
```

## TOC load order

`KickCD.toc` orders files by dependency, not alphabetically:

1. `libs/` — vendored Ace3 + LibSharedMedia + LibCustomGlow. Don't edit.
2. `locales/enUS.lua` — sets up `KickCD.L` with a missing-key fallback.
3. `core/Compat.lua` — bootstraps `_G.KickCD`, hangs `Compat` shims for spell APIs (`GetSpellCooldown`, `GetSpellCooldownDuration`, `GetSpellInfo`, `GetSpellTexture`, `GetSpellCharges`, `IsSpellUsable`, `IsSpellAvailable`, `GetCastingInfo`, `GetChannelInfo`, `DebugInterrupt`) plus the `Compat._firstReturn` truthy-check helper. **Loads first** of `core/` — anything later can rely on `KickCD.Compat` existing.
4. `core/Constants.lua` — exposes `KickCD.Const` with named constants used across modules (`GCD_UPPER`, `CASTBAR_INSIDE_INSET`, `CASTBAR_OUTSIDE_INSET`, `PANEL_HEADER_TOP`, `PANEL_HEADER_HEIGHT`, `PANEL_PADDING_X`, `PANEL_DEFAULTS_W`).
5. `core/State.lua` — `KickCD.State` namespace owning shared mutable state and visibility helpers. Owns `KickCD.State.inCombat` (the event-driven combat flag, mirrored across IconGrid and Castbar) and the visibility helpers `KickCD.State.IsHostileUnitCasting(unit)` and `KickCD.State.ApplyInterruptibleAlpha(frame, unit, alpha)` (hoisted out of Compat in CR-27 because they're feature decisions, not API normalisation). A bootstrap `CreateFrame` in this file is the only place in the addon that registers `PLAYER_REGEN_DISABLED/_ENABLED/PLAYER_LOGIN`; after writing the flag it fires `KickCD_COMBAT_STATE` so subscribers see an explicit ordered transition signal. The frame fires regardless of whether the modules have enabled yet, so an edge-case ordering bug can't desync the flag from reality.
6. `core/Util.lua` — color helper (`Unpack`), anchor save/restore (`SaveAnchor` / `ApplyAnchor`), `Throttle` (leading-edge: fires on first call then ignores until window closes — used by the Spells editor's debounced commit and the ColorPicker's drag-to-commit), `DeepCopy` (single shared deep-copy used by `Helpers.RestoreDefaults`, `Database`, `settings/Spells.lua`), `NormalizeSpecToken` / `NormalizeClassToken` (strip whitespace, uppercase — fixes the Beast Mastery vs `BEASTMASTERY` lookup mismatch), and the chat `print` helper.
7. `core/Database.lua` — defines `DEFAULT_PROFILE`, `Database:Init` (called from `KickCD:OnInitialize`), `Database:GetSpellList(class, spec)` (read-only) / `Database:EnsureSpellList(class, spec)` (lazy-creating; the only mutator entry point), `Database:BuildSpells` (no-reseed-when-non-empty; see [scope.md](scope.md)), `Database:ResetAllSpells`, and the `dbVersion` migration scaffold (`Database:MigrateProfile` runs at Init and on profile change). Does not create the DB at file-load time.
8. `core/KickCD.lua` — promotes the bootstrap table to an AceAddon, registers slash commands, defines the `COMMANDS` / `DEBUG_COMMANDS` / `SPELLS_COMMANDS` dispatch tables. `OpenSettings` defers (one-shot retry, capped at 3) when the General subcategory hasn't built yet so a `/kcd config` immediately after login lands on the real page rather than the empty parent.
9. `defaults/Spells.lua` — populates `KickCD.DefaultSpells` (per-class+spec interrupt list); merged into the profile by `Database:BuildSpells` on first profile creation.
10. `modules/Cooldowns.lua` — polls cooldown state, emits `KickCD_SPELL_STATE`. Listens for `SPELL_UPDATE_COOLDOWN/USABLE/CHARGES`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED` (the last two pick up talent-choice swaps and pet summon/dismiss without waiting for a spec change). On poll-nil for a previously-watched spell (pet dismissed, talent untrained), emits a sentinel `SPELL_STATE` with `ready=false, isActive=false, cdObject=nil` and unwatches the id — without it the orphan icon would linger with stale state.
11. `modules/IconGrid.lua` — owns the `KickCDIconGrid` frame and per-icon widgets, the per-icon ready glow (LibCustomGlow), the visibility-mode gate, and a single shared cooldown-text ticker (one `OnUpdate` for every icon with countdown text, not one per icon). `BuildActiveList` dedupes by spellID; `Layout` warns once when `visibleCount > rows*cols`. Listens for the four inbound `KickCD_*` messages (`SPELL_STATE`, `CONFIG_CHANGED`, `PROFILE_CHANGED`, `COMBAT_STATE`) plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START/_STOP/_FAILED/_INTERRUPTED/_CHANNEL_START/_CHANNEL_STOP/_INTERRUPTIBLE/_NOT_INTERRUPTIBLE`). Combat transitions arrive via `KickCD_COMBAT_STATE` (sent by `core/State.lua`); the module no longer hooks `PLAYER_REGEN_*` directly. Emits `KickCD_GRID_LAYOUT` after every layout pass with `{ gridFrame, primaryIcon, width, height }`. `RefreshAllGlows` short-circuits when the (hostile-cast, interruptible) gate hasn't moved.
12. `modules/Castbar.lua` — owns the `KickCDCastbar` frame; mirrors the player's target's cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration` shims (see [castbar.md](castbar.md)). Stacked dual widgets (background, statusbar, border) are alpha-curve-switched on the cast's secret `notInterruptible` bool. Anchors free or to the icon grid's primary icon button (re-anchors on `KickCD_GRID_LAYOUT`, reading the payload's `gridFrame` / `primaryIcon` directly with a fallback to `KickCD:GetModule("IconGrid", true):GetGridFrame` / `:GetPrimaryIcon` for the first tick). UNIT_SPELLCAST_* registrations go through `Util.RegisterTargetEvent` so the dispatch frame fires only when the unit IS "target" — no per-event early-return on non-target casts. Auto-size mode tracks the grid frame's actual visible footprint, not its configured rows × cols capacity. `Castbar:Reskin` / `Castbar:RenderCast` are split: config-driven work (orientation, sizing, fonts, anchors) only re-runs on `OnConfigChanged` / `OnGridLayout` / `OnProfileChanged`, while cast-record-driven work (texture, name, seed bar values, ApplyState) runs on `Start`. The hot path doesn't re-skin per cast.
13. `settings/Panel.lua` — registers the top-level Blizzard Settings category, the per-tab builder mailbox, the schema renderer (`Helpers.RenderSchema`), the schema-shape validator (`Helpers.ValidateSchema` runs at panel-register time and prints clear `|cffff0000KickCD schema error|r:` lines on a misshapen row), the always-visible-scrollbar patch (`Helpers.PatchAlwaysShowScrollbar`), and the shared write-and-refresh helpers (`Helpers.Set`, `Helpers.SetAndRefresh`, `Helpers.RestoreDefaults`, `Helpers.RestoreAllDefaults`, `Helpers.ResetAll`, `Helpers.ResetIconPosition`, `Helpers.AnchorValues`, `Helpers.LSMValues`). The ColorPicker's `OnValueChanged` commit runs through `Util.Throttle(50, ...)` so dragging a color slider doesn't thrash the bus or live frames.
14. `settings/{General,Icons,Castbar,Spells,Profiles}.lua` — register their tabs via `KickCD.Settings.RegisterTab`. General / Icons / Cast bar are pure schema (rows in `KickCD.Settings.Schema`); Spells parents an AceGUI editor to `ctx.body` and listens for `KickCD_CONFIG_CHANGED { section = "spells" }` to rebuild rows after a slash-command write; Profiles parents an AceConfigDialog into `ctx.body` for the AceDBOptions table.

## AceAddon lifecycle

1. **TOC file-load** as listed above. After load: `core/Compat.lua` has created `_G.KickCD` and `KickCD.Compat`; `core/Constants.lua` has populated `KickCD.Const`; `core/State.lua`'s bootstrap `CreateFrame` is already listening for `PLAYER_REGEN_DISABLED` / `_ENABLED` / `PLAYER_LOGIN` to maintain `KickCD.State.inCombat` (regardless of AceAddon module-enable order); `core/KickCD.lua` has run `AceAddon-3.0:NewAddon` to promote `_G.KickCD` in place to an AceAddon object; `defaults/Spells.lua` has set `KickCD.DefaultSpells`; modules have called `KickCD:NewModule`; settings tabs have called `KickCD.Settings.RegisterTab`.
2. **`KickCD:OnInitialize`** (Ace lifecycle, fires on `ADDON_LOADED`): `Database:Init` builds the AceDB instance, runs `Database:MigrateProfile` (no-op for `dbVersion = 1`; the scaffold lets future schema changes ship a migrator next to the change), and seeds spells from `KickCD.DefaultSpells` on first profile creation. Slash commands `/kickcd` and `/kcd` are registered.
3. **`<Module>:OnEnable`**: modules subscribe to messages and game events. They NO LONGER seed their own `_inCombat` from `InCombatLockdown()` — `KickCD.State`'s file-load bootstrap owns the flag — and they NO LONGER register `PLAYER_REGEN_*` directly; combat-state transitions arrive via `KickCD_COMBAT_STATE` from `core/State.lua` so the dispatch order is explicit by construction.
   - `Cooldowns:OnEnable` registers `SPELL_UPDATE_COOLDOWN` / `_USABLE` / `_CHARGES`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, plus `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED` so a talent-choice swap or pet summon flips the watched-list immediately.
   - `IconGrid:OnEnable` builds the frame, runs `BuildCurves` / `BuildActiveList` / `Layout` / `RefreshVisibility`, then registers the four inbound `KickCD_*` messages (`SPELL_STATE`, `CONFIG_CHANGED`, `PROFILE_CHANGED`, `COMBAT_STATE`) plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START` / `_STOP` / `_FAILED` / `_INTERRUPTED` / `_CHANNEL_START` / `_CHANNEL_STOP` / `_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE`) so the visibility mode and per-icon glow trigger react to the addon-wide visibility / target / cast / interruptibility state.
   - `Castbar:OnEnable` builds the frame, runs `Reskin` / `ApplyLock`, registers the target + cast-event family, plus `KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT` / `_COMBAT_STATE`, then calls `Reevaluate` so a login while staring at a casting hostile mob shows the bar immediately.
4. **`PLAYER_LOGIN`** (deferred from `settings/Panel.lua`): the Blizzard Settings category is registered, `Helpers.ValidateSchema` runs against `KickCD.Settings.Schema` (any malformed row prints a `|cffff0000KickCD schema error|r:` line but doesn't refuse load), and per-tab builders run. Late-loading tabs auto-register if the main category already exists. Schema-driven panels defer their AceGUI render to `OnShow` because `ctx.body` is zero-width at PLAYER_LOGIN.

## External dependencies

All vendored under `libs/` and pulled in by `KickCD.toc`: LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0 (which pulls AceConfigRegistry / AceConfigCmd / AceConfigDialog), AceGUI-3.0, LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets (vendored upstream r65 multi-file lib — `widget.xml` + `prototypes.lua` + `BorderWidget.lua` + `FontWidget.lua` + `StatusbarWidget.lua` + `BackgroundWidget.lua` + `SoundWidget.lua` — providing the `LSM30_*` dropdowns the schema renderer swaps in for LSM-backed media rows), LibCustomGlow-1.0. `core/LSMPatch.lua` is an in-tree fixup loaded after the libs that wraps the `LSM30_Border` constructor at PLAYER_LOGIN to hide the 42×42 displayButton preview tile and re-anchor the dropdown bar.

Several additional Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab, AceTimer) ship as part of the standard Ace3 distribution under `libs/` but are **not** loaded by the TOC.

`KickCD.toc`'s `## Interface:` line targets the Midnight client.
