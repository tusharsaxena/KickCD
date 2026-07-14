# Module map

Where each responsibility lives in the source tree, plus the TOC load order and the AceAddon lifecycle hooks. The TOC at `KickCD.toc` is the source of truth for load order — match this map to it before editing.

## Directory tree

```
KickCD (AceAddon)
├── core/
│   ├── Compat.lua    — API shims for spell + cast APIs (10.0–12.0). Pure
│                       API normalisation; no feature decisions.
│   ├── Constants.lua — NS.Const namespace for shared magic numbers
│                       (GCD_UPPER, panel paddings, castbar text insets)
│   ├── State.lua     — NS.State namespace for shared mutable state +
│                       visibility helpers (inCombat flag w/ bootstrap
│                       listener; IsHostileUnitCasting; ApplyInterruptibleAlpha)
│   ├── Util.lua      — color (Unpack), anchor (SaveAnchor / ApplyAnchor),
│                       Throttle, DeepCopy, NormalizeSpecToken /
│                       NormalizeClassToken, chat print
│   ├── Database.lua  — AceDB instance + DEFAULT_PROFILE + GetSpellList /
│                       EnsureSpellList helpers + spell-defaults merge +
│                       db.global.schemaVersion / MigrateProfile scaffold
│   ├── LSMPatch.lua  — PLAYER_LOGIN fixup wrapping the vendored LSM30_Border
│                       AceGUI widget to hide its 42×42 preview tile +
│                       re-anchor the dropdown bar (in-tree, survives lib refresh)
│   └── KickCD.lua    — AceAddon bootstrap + slash dispatch (COMMANDS /
│                       DEBUG_COMMANDS / SPELLS_COMMANDS) + OpenSettings
│                       (defers when subcategory not yet built)
├── defaults/
│   └── Spells.lua    — per-class+spec default interrupt lists (NS.DefaultSpells)
├── modules/
│   ├── DebugLog.lua  — on-screen debug console: a DIALOG-strata window
│                       "Ka0s KickCD — Debug" (KickCDDebugWindow) built lazily,
│                       ScrollingMessageFrame log + Copy/Clear buttons +
│                       header Debug:ON/OFF toggle, JetBrains Mono font from
│                       media/fonts/. Exposes the sink NS.Debug(tag, fmt, ...)
│                       — gated on the session-only NS.State.debug, routing to
│                       the console (NOT chat) — plus the pure FormatPlain /
│                       FormatColored formatters. Inert at file load
│   ├── Cooldowns.lua — polls Compat.GetSpellCooldown + GetSpellCooldownDuration,
│                       emits Ka0s_KickCD_SPELL_STATE; emits a sentinel state on
│                       poll-nil so vanished spells (pet dismissed, talent
│                       untrained) don't leave a stale icon
│   ├── IconGrid.lua  — module + lifecycle + icon pool + Layout orchestration +
│                       visibility gate + message handlers; owns KickCDIconGrid
│                       frame; single shared cooldown-text ticker; spellID
│                       dedupe at build time; truncation warning at layout time;
│                       exposes IconGrid._isTargetCasting to the render sibling;
│                       emits Ka0s_KickCD_GRID_LAYOUT
│                       { gridFrame, primaryIcon, width, height }
│   ├── IconGrid_Layout.lua — anchor/grow token parsing + block geometry
│                       (parseAnchor / parseGrow / placeBlock / layoutBlock),
│                       published as IconGrid.LayoutMath. Pure parsers are unit-
│                       tested headlessly; layoutBlock positions the buttons
│   ├── IconGrid_Render.lua — Icon prototype + CreateIconWidget, cooldown /
│                       glow rendering, alpha/tint/GCD-suppress curves run
│                       C-side; exposes IconGrid.CreateIconWidget /
│                       IconGrid.BuildCurves back to core
│   └── Castbar.lua   — owns KickCDCastbar frame (stacked dual StatusBars +
│                       per-state borders + spark); secret-value-gated
│                       UnitCastingDuration / UnitChannelDuration consumer;
│                       Reskin / RenderCast split keeps cast start hot-path light
└── settings/
    ├── Panel.lua     — top-level category + canvas-panel framework + schema
                        renderer + ValidateSchema + Util.Throttle wrapper
                        on the ColorPicker commit + always-show-scrollbar patch
    ├── General.lua   — schema rows for enable/visibility/lock/scale/alpha
                        + Reset position + Reset all buttons (debug enable is
                        session-only NS.State.debug, not a schema row)
    ├── Icons.lua     — schema rows for icon grid sizing, colors, layout, glow
    ├── Castbar.lua   — schema rows for cast bar enable/anchor/orientation/
                        sizing/text/per-state appearance. Schema rows do NOT
                        carry onChange callbacks — Helpers.Set fires the bus
                        and the Castbar module's listener handles the redraw,
                        avoiding the double-dispatch the schema previously had
    ├── Spells.lua    — unified header + AceGUI per-class+spec spell editor.
                        Listens for Ka0s_KickCD_CONFIG_CHANGED { section = "spells" }
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
2. `locales/enUS.lua` — sets up `NS.L` with a missing-key fallback.
3. `core/Compat.lua` — hangs `NS.Compat` (the shared private namespace `NS` arrives as the second file vararg, not a global), populating `Compat` shims for spell APIs (`GetSpellCooldown`, `GetSpellCooldownDuration`, `GetSpellInfo`, `GetSpellTexture`, `GetSpellCharges`, `IsSpellUsable`, `IsSpellAvailable`, `GetCastingInfo`, `GetChannelInfo`, `DebugInterrupt`) plus the `Compat._firstReturn` truthy-check helper. **Loads first** of `core/` — anything later can rely on `NS.Compat` existing.
4. `core/Constants.lua` — exposes `NS.Const` with named constants used across modules (`GCD_UPPER`, `CASTBAR_INSIDE_INSET`, `CASTBAR_OUTSIDE_INSET`, `PANEL_HEADER_TOP`, `PANEL_HEADER_HEIGHT`, `PANEL_PADDING_X`, `PANEL_DEFAULTS_W`).
5. `core/State.lua` — `NS.State` namespace owning shared mutable state and visibility helpers. Owns `NS.State.inCombat` (the event-driven combat flag, mirrored across IconGrid and Castbar) and the visibility helpers `NS.State.IsHostileUnitCasting(unit)` and `NS.State.ApplyInterruptibleAlpha(frame, unit, alpha)` (hoisted out of Compat in CR-27 because they're feature decisions, not API normalisation). A bootstrap `CreateFrame` in this file is the only place in the addon that registers `PLAYER_REGEN_DISABLED/_ENABLED/PLAYER_LOGIN`; after writing the flag it fires `Ka0s_KickCD_COMBAT_STATE` so subscribers see an explicit ordered transition signal. The frame fires regardless of whether the modules have enabled yet, so an edge-case ordering bug can't desync the flag from reality.
6. `core/Util.lua` — color helper (`Unpack`), anchor save/restore (`SaveAnchor` / `ApplyAnchor`), `Throttle` (leading-edge: fires on first call then ignores until window closes — used by the Spells editor's debounced commit and the ColorPicker's drag-to-commit), `DeepCopy` (single shared deep-copy used by `Helpers.RestoreDefaults`, `Database`, `settings/Spells.lua`), `NormalizeSpecToken` / `NormalizeClassToken` (strip whitespace, uppercase — fixes the Beast Mastery vs `BEASTMASTERY` lookup mismatch), and the chat `print` helper.
7. `core/Database.lua` — defines `DEFAULT_PROFILE`, `Database:Init` (called from `NS:OnInitialize`), `Database:GetSpellList(class, spec)` (read-only) / `Database:EnsureSpellList(class, spec)` (lazy-creating; the only mutator entry point), `Database:BuildSpells` (no-reseed-when-non-empty; see [scope.md](scope.md)), `Database:ResetAllSpells`, and the `db.global.schemaVersion` migration scaffold (`Database:MigrateProfile` runs at Init and on profile change). Does not create the DB at file-load time.
8. `core/LSMPatch.lua` — in-tree fixup for the vendored `AceGUI-3.0-SharedMediaWidgets`. A one-shot `PLAYER_LOGIN` frame wraps the `LSM30_Border` widget constructor to hide its misaligned 42×42 `displayButton` preview tile and re-anchor the dropdown bar. Lives in addon code (not the lib) so a future lib refresh doesn't blow it away.
9. `core/KickCD.lua` — promotes the bootstrap table to an AceAddon, registers slash commands, defines the `COMMANDS` / `DEBUG_COMMANDS` / `SPELLS_COMMANDS` dispatch tables. `OpenSettings` defers (one-shot retry, capped at 3) when the General subcategory hasn't built yet so a `/kcd config` immediately after login lands on the real page rather than the empty parent.
10. `defaults/Spells.lua` — populates `NS.DefaultSpells` (per-class+spec interrupt list); merged into the profile by `Database:BuildSpells` on first profile creation.
11. `modules/DebugLog.lua` — **loads first** of `modules/`. On-screen debug console: a lazily-built DIALOG-strata window "Ka0s KickCD — Debug" (global frame `KickCDDebugWindow`) with a `ScrollingMessageFrame` log, Copy / Clear buttons (Copy opens a separate `KickCDDebugCopyWindow`), and a header `Debug:ON/OFF` toggle (`DebugLog:SetEnabled` is the single write seam — it also brackets each session with a `[Debug] logging enabled/disabled` console line at both transitions, written through the raw `Add` so the disable line lands after the flag flips off), rendered in the JetBrains Mono font shipped from `media/fonts/` and registered with LibSharedMedia at load. Exposes the sink `NS.Debug(tag, fmt, ...)` — gated on the session-only `NS.State.debug`, routing formatted lines to the console **not** chat — plus the pure `FormatPlain` / `FormatColored` formatters. Inert at file load; every frame is built in `EnsureWindow`.
12. `modules/Cooldowns.lua` — polls cooldown state, emits `Ka0s_KickCD_SPELL_STATE`. Listens for `SPELL_UPDATE_COOLDOWN/USABLE/CHARGES`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED` (the last two pick up talent-choice swaps and pet summon/dismiss without waiting for a spec change). On poll-nil for a previously-watched spell (pet dismissed, talent untrained), emits a sentinel `SPELL_STATE` with `ready=false, isActive=false, cdObject=nil` and unwatches the id — without it the orphan icon would linger with stale state.
13. `modules/IconGrid.lua` — the module core: lifecycle, the icon pool, `Layout` orchestration, the visibility-mode gate, and the message handlers. Owns the `KickCDIconGrid` frame, the per-icon ready glow (LibCustomGlow), and a single shared cooldown-text ticker (one `OnUpdate` for every icon with countdown text, not one per icon). `BuildActiveList` dedupes by spellID; `Layout` warns once when `visibleCount > rows*cols`. Publishes `IconGrid._isTargetCasting` for the render sibling's glow trigger. Listens for the four inbound `Ka0s_KickCD_*` messages (`Ka0s_KickCD_SPELL_STATE`, `Ka0s_KickCD_CONFIG_CHANGED`, `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_COMBAT_STATE`) plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START/_STOP/_FAILED/_INTERRUPTED/_CHANNEL_START/_CHANNEL_STOP/_INTERRUPTIBLE/_NOT_INTERRUPTIBLE`). Combat transitions arrive via `Ka0s_KickCD_COMBAT_STATE` (sent by `core/State.lua`); the module no longer hooks `PLAYER_REGEN_*` directly. Emits `Ka0s_KickCD_GRID_LAYOUT` after every layout pass with `{ gridFrame, primaryIcon, width, height }`. `RefreshAllGlows` short-circuits when the (hostile-cast, interruptible) gate hasn't moved.
14. `modules/IconGrid_Layout.lua` — icon-grid geometry peeled from IconGrid (KCD-05): anchor/grow token parsing and block placement (`parseAnchor` / `parseGrow` / `placeBlock` / `layoutBlock`), published on the module as `IconGrid.LayoutMath` (a distinct key from the `IconGrid:Layout()` orchestrator method, which loads first and would otherwise be clobbered — KCD-05). The parsers are pure (numbers/strings in and out) and unit-tested headlessly; `layoutBlock` is the frame-manipulating orchestrator that positions the primary + secondary buttons against the grid frame.
15. `modules/IconGrid_Render.lua` — per-icon rendering peeled from IconGrid (KCD-05): the `Icon` prototype and its factory `CreateIconWidget`, the cooldown-swipe / countdown-text / ready-glow drawing, the step-shaped alpha/tint/GCD-suppress curves run C-side, and the shared cooldown-text ticker. Exposes `IconGrid.CreateIconWidget` / `IconGrid.BuildCurves` back to core; consumes `IconGrid._isTargetCasting` for the glow trigger.
16. `modules/Castbar.lua` — owns the `KickCDCastbar` frame; mirrors the player's target's cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration` shims (see [castbar.md](castbar.md)). Stacked dual widgets (background, statusbar, border) are alpha-curve-switched on the cast's secret `notInterruptible` bool. Anchors free or to the icon grid's primary icon button (re-anchors on `Ka0s_KickCD_GRID_LAYOUT`, reading the payload's `gridFrame` / `primaryIcon` directly with a fallback to `NS:GetModule("IconGrid", true):GetGridFrame` / `:GetPrimaryIcon` for the first tick). UNIT_SPELLCAST_* registrations go through `Util.RegisterTargetEvent` so the dispatch frame fires only when the unit IS "target" — no per-event early-return on non-target casts. Auto-size mode tracks the grid frame's actual visible footprint, not its configured rows × cols capacity. `Castbar:Reskin` / `Castbar:RenderCast` are split: config-driven work (orientation, sizing, fonts, anchors) only re-runs on `OnConfigChanged` / `OnGridLayout` / `OnProfileChanged`, while cast-record-driven work (texture, name, seed bar values, ApplyState) runs on `Start`. The hot path doesn't re-skin per cast.
17. `settings/Panel.lua` — registers the top-level Blizzard Settings category, the per-tab builder mailbox, the schema renderer (`Helpers.RenderSchema`), the schema-shape validator (`Helpers.ValidateSchema` runs at panel-register time and prints clear `|cffff0000KickCD schema error|r:` lines on a misshapen row), the always-visible-scrollbar patch (`Helpers.PatchAlwaysShowScrollbar`), and the shared write-and-refresh helpers (`Helpers.Set`, `Helpers.SetAndRefresh`, `Helpers.RestoreDefaults`, `Helpers.RestoreAllDefaults`, `Helpers.ResetAll`, `Helpers.ResetIconPosition`, `Helpers.AnchorValues`, `Helpers.LSMValues`). The ColorPicker's `OnValueChanged` commit runs through `Util.Throttle(50, ...)` so dragging a color slider doesn't thrash the bus or live frames.
18. `settings/{General,Icons,Castbar,Spells,Profiles}.lua` — register their tabs via `NS.Settings.RegisterTab`. General / Icons / Cast bar are pure schema (rows in `NS.Settings.Schema`); Spells parents an AceGUI editor to `ctx.body` and listens for `Ka0s_KickCD_CONFIG_CHANGED { section = "spells" }` to rebuild rows after a slash-command write; Profiles parents an AceConfigDialog into `ctx.body` for the AceDBOptions table.

## AceAddon lifecycle

1. **TOC file-load** as listed above. After load: `core/Compat.lua` has populated `NS.Compat`; `core/Constants.lua` has populated `NS.Const`; `core/State.lua`'s bootstrap `CreateFrame` is already listening for `PLAYER_REGEN_DISABLED` / `_ENABLED` / `PLAYER_LOGIN` to maintain `NS.State.inCombat` (regardless of AceAddon module-enable order); `core/KickCD.lua` has run `AceAddon-3.0:NewAddon` to promote `NS` in place to an AceAddon object (no `_G.KickCD` rebind — the namespace stays private); `defaults/Spells.lua` has set `NS.DefaultSpells`; modules have called `NS:NewModule`; settings tabs have called `NS.Settings.RegisterTab`.
2. **`NS:OnInitialize`** (Ace lifecycle, fires on `ADDON_LOADED`): `Database:Init` builds the AceDB instance, runs `Database:MigrateProfile` (no-op at `db.global.schemaVersion = 1`; the scaffold lets future schema changes ship a migrator next to the change), and seeds spells from `NS.DefaultSpells` on first profile creation. Slash commands `/kickcd` and `/kcd` are registered.
3. **`<Module>:OnEnable`**: modules subscribe to messages and game events. They NO LONGER seed their own `_inCombat` from `InCombatLockdown()` — `NS.State`'s file-load bootstrap owns the flag — and they NO LONGER register `PLAYER_REGEN_*` directly; combat-state transitions arrive via `Ka0s_KickCD_COMBAT_STATE` from `core/State.lua` so the dispatch order is explicit by construction.
   - `Cooldowns:OnEnable` registers `SPELL_UPDATE_COOLDOWN` / `_USABLE` / `_CHARGES`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, plus `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED` so a talent-choice swap or pet summon flips the watched-list immediately.
   - `IconGrid:OnEnable` builds the frame, runs `BuildCurves` / `BuildActiveList` / `Layout` / `RefreshVisibility`, then registers the four inbound `Ka0s_KickCD_*` messages (`Ka0s_KickCD_SPELL_STATE`, `Ka0s_KickCD_CONFIG_CHANGED`, `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_COMBAT_STATE`) plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START` / `_STOP` / `_FAILED` / `_INTERRUPTED` / `_CHANNEL_START` / `_CHANNEL_STOP` / `_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE`) so the visibility mode and per-icon glow trigger react to the addon-wide visibility / target / cast / interruptibility state.
   - `Castbar:OnEnable` builds the frame, runs `Reskin` / `ApplyLock`, registers the target + cast-event family, plus `Ka0s_KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT` / `_COMBAT_STATE`, then calls `Reevaluate` so a login while staring at a casting hostile mob shows the bar immediately.
4. **`PLAYER_LOGIN`** (deferred from `settings/Panel.lua`): the Blizzard Settings category is registered, `Helpers.ValidateSchema` runs against `NS.Settings.Schema` (any malformed row prints a `|cffff0000KickCD schema error|r:` line but doesn't refuse load), and per-tab builders run. Late-loading tabs auto-register if the main category already exists. Schema-driven panels defer their AceGUI render to `OnShow` because `ctx.body` is zero-width at PLAYER_LOGIN.

## External dependencies

All vendored under `libs/` and pulled in by `KickCD.toc`: LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0 (which pulls AceConfigRegistry / AceConfigCmd / AceConfigDialog), AceGUI-3.0, LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets (vendored upstream r65 multi-file lib — `widget.xml` + `prototypes.lua` + `BorderWidget.lua` + `FontWidget.lua` + `StatusbarWidget.lua` + `BackgroundWidget.lua` + `SoundWidget.lua` — providing the `LSM30_*` dropdowns the schema renderer swaps in for LSM-backed media rows), LibCustomGlow-1.0. `core/LSMPatch.lua` is an in-tree fixup loaded after the libs that wraps the `LSM30_Border` constructor at PLAYER_LOGIN to hide the 42×42 displayButton preview tile and re-anchor the dropdown bar.

`AceTimer-3.0` remains vendored under `libs/` (part of the standard Ace3 distribution) but is **not** loaded by the TOC. The six other unused Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab) were deleted from `libs/`.

`KickCD.toc`'s `## Interface:` line targets the Midnight client.
