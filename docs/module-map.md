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
│   ├── Units.lua     — NS.Units: single source of unit identity + per-unit
│                       config resolution for target/focus dual tracking
│                       (LIST, Config, IsEnabled, IsLinked, Icons/Castbar
│                       [link-resolved], Anchor/SetAnchor [never link-
│                       resolved], Label, CopyStyling). Loads after Util,
│                       before Database
│   ├── Database.lua  — AceDB instance + DEFAULT_PROFILE (units.target /
│                       units.focus) + GetSpellList / EnsureSpellList
│                       helpers + spell-defaults merge + FoldLegacyUnits
│                       (shape-driven top-level icons/castbar/anchors ->
│                       units.target fold) + db.global.schemaVersion
│                       (CURRENT_DB_VERSION = 2) / MigrateProfile scaffold
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
│   ├── IconGrid.lua  — PER-UNIT INSTANCE MANAGER (instances[unit], keyed by
│                       NS.Units.LIST): lifecycle + icon pool + Layout
│                       orchestration + visibility gate + message handlers,
│                       one live instance per enabled unit. Target's frame
│                       keeps the legacy global name KickCDIconGrid; Focus is
│                       KickCDIconGridFocus. EnableUnit/DisableUnit/
│                       ReconcileUnits build/tear down a unit's instance;
│                       UNIT_SPELLCAST_* registration is enable-gated per
│                       instance. Single shared cooldown-text ticker per
│                       instance; spellID dedupe at build time; truncation
│                       warning at layout time; exposes
│                       IconGrid._isTargetCasting to the render sibling;
│                       emits Ka0s_KickCD_GRID_LAYOUT
│                       { unit, gridFrame, primaryIcon, width, height }
│   ├── IconGrid_Layout.lua — anchor/grow token parsing + block geometry
│                       (parseAnchor / parseGrow / placeBlock / layoutBlock),
│                       published as IconGrid.LayoutMath. Pure parsers are unit-
│                       tested headlessly; layoutBlock positions the buttons
│   ├── IconGrid_Render.lua — Icon prototype + CreateIconWidget, cooldown /
│                       glow rendering, alpha/tint/GCD-suppress curves run
│                       C-side; exposes IconGrid.CreateIconWidget /
│                       IconGrid.BuildCurves back to core
│   ├── Castbar.lua   — PER-UNIT INSTANCE MANAGER (instances[unit]), mirroring
│                       IconGrid's structure: owns KickCDCastbar (target) /
│                       KickCDCastbarFocus (focus) — stacked dual StatusBars +
│                       per-state borders + spark per instance; secret-value-
│                       gated UnitCastingDuration / UnitChannelDuration
│                       consumer; EnableUnit/DisableUnit/ReconcileUnits mirror
│                       IconGrid's; Reskin / RenderCast split keeps cast start
│                       hot-path light; OnGridLayout filters the inbound
│                       Ka0s_KickCD_GRID_LAYOUT payload on payload.unit before
│                       resolving instances[payload.unit]. Owns no label —
│                       identity text moved to modules/UnitLabel.lua
│   └── UnitLabel.lua — PER-UNIT INSTANCE MANAGER (instances[unit]): one
│                       identity FontString per unit, in a holder frame
│                       (KickCDUnitLabelTarget / KickCDUnitLabelFocus)
│                       parented to UIParent — NOT to the attach widget — so
│                       the label's own show/alpha stay independent of its
│                       attach target's visibility. SetPoint-anchored to the
│                       unit's chosen attach frame (Castbar:GetCastbarFrame
│                       (unit) or IconGrid:GetGridFrame(unit), per
│                       label.style.attach). Text/show read via NS.Units.Label
│                       (per-unit, never link-resolved); appearance read via
│                       NS.Units.LabelStyle (link-resolved — a linked Focus
│                       reads Target's style). Shown iff the unit is enabled
│                       AND label.show AND the attach frame currently exists.
│                       Subscribes to the existing Ka0s_KickCD_CONFIG_CHANGED /
│                       _PROFILE_CHANGED / _GRID_LAYOUT messages — no new bus
│                       message was added. IconGrid and Castbar no longer own
│                       any label
└── settings/
    ├── Panel.lua     — top-level category + canvas-panel framework + schema
                        renderer + ValidateSchema + Util.Throttle wrapper
                        on the ColorPicker commit + always-show-scrollbar patch
                        + Helpers.RenderUnitPanel (unit selector + focus
                        link/copy header, shared by Icons/Castbar/Label)
                        + makeEditBox + Helpers.RenderRows (row renderer,
                        extracted so RenderUnitPanel and PartitionUnitRows'
                        alwaysPerUnit split share one code path; each row's
                        RenderField call is wrapped in its own pcall so one
                        bad saved value can't blank the whole panel)
                        + Helpers.PartitionUnitRows (splits a panel's schema
                        rows into "always render per-unit, even while linked"
                        vs. link-gated appearance rows, keyed on the row's
                        alwaysPerUnit flag)
    ├── General.lua   — schema rows for enable/visibility/lock/scale/alpha
                        + per-unit enabled (both target and focus,
                        section="units"; no unit selector — General renders
                        both units' rows together). label.show/label.text
                        moved OFF General onto the Text Label panel; General
                        keeps only the per-unit enable toggles
                        + Reset position + Reset all buttons (debug enable is
                        session-only NS.State.debug, not a schema row)
    ├── Icons.lua     — schema rows for icon grid sizing, colors, layout, glow,
                        rendered per-unit via Helpers.RenderUnitPanel (unit
                        selector; a linked focus hides the appearance body)
    ├── Castbar.lua   — schema rows for cast bar enable/anchor/orientation/
                        sizing/text/per-state appearance, rendered per-unit
                        via Helpers.RenderUnitPanel (unit selector; a linked
                        focus hides the appearance body). Schema rows do NOT
                        carry onChange callbacks — Helpers.Set fires the bus
                        and the Castbar module's listener handles the redraw,
                        avoiding the double-dispatch the schema previously had
    ├── Label.lua     — "Text Label" canvas panel (panel/section "label"),
                        rendered by modules/UnitLabel.lua. Schema rows are
                        generated once per NS.Units.LIST entry at
                        units.<unit>.label.{show,text,style.*}. show/text
                        carry alwaysPerUnit = true so they stay editable even
                        while the unit is linked to Target (Helpers.
                        PartitionUnitRows + Helpers.RenderUnitPanel render
                        them outside the link-gated appearance body); the
                        style.* rows (attach/point/relPoint/offsets/justify/
                        rotation/font/size/flags) are link-resolved appearance
                        and follow the same body the Icons/Castbar panels use.
                        Rendered via the shared unit selector
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
7. `core/Units.lua` — `NS.Units`: single source of unit identity (`LIST = { "target", "focus" }`) and per-unit config resolution (`Config`, `IsEnabled`, `IsLinked`, `Icons`/`Castbar` [link-resolved — a linked focus reads target's appearance tables], `Anchor`/`SetAnchor` [never link-resolved — position stays per-unit], `Label`, `CopyStyling`). `IconGrid` and `Castbar` never reach `db.profile.units.<unit>` directly for appearance; they go through here so the "link to target styling" behavior lives in exactly one place. Loads after `core/Util.lua`, before `core/Database.lua` (no dependency on Database — reads `NS.db.profile` lazily at call time, not at file load).
8. `core/Database.lua` — defines `DEFAULT_PROFILE` (`units.target` / `units.focus`, each carrying its own `icons`/`castbar`/`anchors`/`label`/`enabled`/`link`), `Database:Init` (called from `NS:OnInitialize`), `Database:GetSpellList(class, spec)` (read-only) / `Database:EnsureSpellList(class, spec)` (lazy-creating; the only mutator entry point), `Database:BuildSpells` (no-reseed-when-non-empty; see [scope.md](scope.md)), `Database:ResetAllSpells`, `Database:FoldLegacyUnits` (shape-driven fold of pre-units top-level `icons`/`castbar`/`anchors` into `units.target`, idempotent, run unconditionally ahead of the version-gated path — see [saved-variables.md](saved-variables.md#migration-folding-legacy-iconscastbaranchors-into-unitstarget)), and the `db.global.schemaVersion` migration scaffold (`CURRENT_DB_VERSION = 2`; `Database:MigrateProfile` runs at Init and on profile change). Does not create the DB at file-load time.
10. `core/LSMPatch.lua` — in-tree fixup for the vendored `AceGUI-3.0-SharedMediaWidgets`. A one-shot `PLAYER_LOGIN` frame wraps the `LSM30_Border` widget constructor to hide its misaligned 42×42 `displayButton` preview tile and re-anchor the dropdown bar. Lives in addon code (not the lib) so a future lib refresh doesn't blow it away.
11. `core/KickCD.lua` — promotes the bootstrap table to an AceAddon, registers slash commands, defines the `COMMANDS` / `DEBUG_COMMANDS` / `SPELLS_COMMANDS` dispatch tables. `OpenSettings` defers (one-shot retry, capped at 3) when the General subcategory hasn't built yet so a `/kcd config` immediately after login lands on the real page rather than the empty parent.
12. `defaults/Spells.lua` — populates `NS.DefaultSpells` (per-class+spec interrupt list); merged into the profile by `Database:BuildSpells` on first profile creation.
13. `modules/DebugLog.lua` — **loads first** of `modules/`. On-screen debug console: a lazily-built DIALOG-strata window "Ka0s KickCD — Debug" (global frame `KickCDDebugWindow`) with a `ScrollingMessageFrame` log, Copy / Clear buttons (Copy opens a separate `KickCDDebugCopyWindow`), and a header `Debug:ON/OFF` toggle (`DebugLog:SetEnabled` is the single write seam — it also brackets each session with a `[Debug] logging enabled/disabled` console line at both transitions, written through the raw `Add` so the disable line lands after the flag flips off), rendered in the JetBrains Mono font shipped from `media/fonts/` and registered with LibSharedMedia at load. Exposes the sink `NS.Debug(tag, fmt, ...)` — gated on the session-only `NS.State.debug`, routing formatted lines to the console **not** chat — plus the pure `FormatPlain` / `FormatColored` formatters. Inert at file load; every frame is built in `EnsureWindow`.
14. `modules/Cooldowns.lua` — polls cooldown state, emits `Ka0s_KickCD_SPELL_STATE`. Listens for `SPELL_UPDATE_COOLDOWN/USABLE/CHARGES` — routed through `OnCooldownEvent` into a `Util.Throttle(0)` coalescer so a same-frame burst of these chatty, global (spell-agnostic) events collapses to a single `Refresh` on the next frame instead of one full watched-list re-poll each — plus `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED` (the last two pick up talent-choice swaps and pet summon/dismiss without waiting for a spec change; these `Rebuild` triggers stay synchronous — only the `SPELL_UPDATE_*` path is coalesced). On poll-nil for a previously-watched spell (pet dismissed, talent untrained), emits a sentinel `SPELL_STATE` with `ready=false, isActive=false, cdObject=nil` and unwatches the id — without it the orphan icon would linger with stale state. Player-centric and unit-agnostic — the same `SPELL_STATE` payload feeds every enabled unit's `IconGrid` instance.
15. `modules/IconGrid.lua` — PER-UNIT INSTANCE MANAGER: `instances[unit]` (`NS.Units.LIST`), each holding its own frame, icon pool, `Layout` state, and cooldown-text ticker. Owns the `KickCDIconGrid` (target) / `KickCDIconGridFocus` (focus) frames, the per-icon ready glow (LibCustomGlow) per instance. `EnableUnit(unit)` / `DisableUnit(unit)` / `ReconcileUnits()` build or tear down a unit's instance against `NS.Units.IsEnabled(unit)`; `UNIT_SPELLCAST_*` registration is enable-gated per instance (a disabled unit's instance doesn't listen at all) and instances re-evaluate on enable so mid-cast enabling doesn't miss the in-flight cast. `BuildActiveList` dedupes by spellID per instance; `Layout` warns once per instance when `visibleCount > rows*cols`. Publishes `IconGrid._isTargetCasting` for the render sibling's glow trigger. Listens for the four inbound `Ka0s_KickCD_*` messages (`Ka0s_KickCD_SPELL_STATE`, `Ka0s_KickCD_CONFIG_CHANGED` — including the `"units"` section, which triggers `ReconcileUnits` — `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_COMBAT_STATE`) plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START/_STOP/_FAILED/_INTERRUPTED/_CHANNEL_START/_CHANNEL_STOP/_INTERRUPTIBLE/_NOT_INTERRUPTIBLE`). Combat transitions arrive via `Ka0s_KickCD_COMBAT_STATE` (sent by `core/State.lua`); the module no longer hooks `PLAYER_REGEN_*` directly. Each instance emits its own `Ka0s_KickCD_GRID_LAYOUT` after every layout pass with `{ unit, gridFrame, primaryIcon, width, height }`. `RefreshAllGlows` short-circuits when the (hostile-cast, interruptible) gate hasn't moved.
16. `modules/IconGrid_Layout.lua` — icon-grid geometry peeled from IconGrid (KCD-05): anchor/grow token parsing and block placement (`parseAnchor` / `parseGrow` / `placeBlock` / `layoutBlock`), published on the module as `IconGrid.LayoutMath` (a distinct key from the `IconGrid:Layout()` orchestrator method, which loads first and would otherwise be clobbered — KCD-05). The parsers are pure (numbers/strings in and out) and unit-tested headlessly; `layoutBlock` is the frame-manipulating orchestrator that positions the primary + secondary buttons against a given instance's grid frame.
17. `modules/IconGrid_Render.lua` — per-icon rendering peeled from IconGrid (KCD-05): the `Icon` prototype and its factory `CreateIconWidget`, the cooldown-swipe / countdown-text / ready-glow drawing, the step-shaped alpha/tint/GCD-suppress curves run C-side, and the shared per-instance cooldown-text ticker. Exposes `IconGrid.CreateIconWidget` / `IconGrid.BuildCurves` back to core; consumes `IconGrid._isTargetCasting` for the glow trigger.
18. `modules/Castbar.lua` — PER-UNIT INSTANCE MANAGER mirroring `IconGrid.lua`'s structure: `instances[unit]`, each owning its own frame — `KickCDCastbar` (target) / `KickCDCastbarFocus` (focus) — and mirroring the corresponding unit's target/focus cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration` shims (see [castbar.md](castbar.md)). Stacked dual widgets (background, statusbar, border) per instance are alpha-curve-switched on the cast's secret `notInterruptible` bool. `EnableUnit` / `DisableUnit` / `ReconcileUnits` mirror `IconGrid`'s; `UNIT_SPELLCAST_*` registration is enable-gated and unit-filtered (a focus instance dispatches only on focus casts) via `Util.RegisterUnitCastEvent`. Each instance anchors free or to its own unit's icon grid primary icon button (re-anchors on `Ka0s_KickCD_GRID_LAYOUT`, filtering the payload on `payload.unit` before resolving `instances[payload.unit]`, reading the payload's `gridFrame` / `primaryIcon` directly with a fallback to `NS:GetModule("IconGrid", true):GetGridFrame` / `:GetPrimaryIcon` for the first tick). Auto-size mode tracks that unit's grid frame's actual visible footprint, not its configured rows × cols capacity. `Castbar:Reskin` / `Castbar:RenderCast` are split per instance: config-driven work (orientation, sizing, fonts, anchors) only re-runs on `OnConfigChanged` (including the `"units"` section) / `OnGridLayout` / `OnProfileChanged`, while cast-record-driven work (texture, name, seed bar values, ApplyState) runs on `Start`. The hot path doesn't re-skin per cast. Exposes `GetCastbarFrame(unit)`, one of the two attach-frame lookups `modules/UnitLabel.lua` calls.
19. `modules/UnitLabel.lua` — PER-UNIT INSTANCE MANAGER (`instances[unit]`): a holder frame (`KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`) parented to `UIParent`, each carrying one `FontString`, `SetPoint`-anchored to `IconGrid:GetGridFrame(unit)` or `Castbar:GetCastbarFrame(unit)` per `label.style.attach`. `Apply(inst)` re-reads `NS.Units.Label(unit)` (per-unit `show`/`text`) and `NS.Units.LabelStyle(unit)` (link-resolved appearance) and re-applies text/font/justify/rotation/anchor/visibility; shown iff the unit is enabled AND `label.show` AND the attach frame currently resolves. `ApplyAll` re-runs `Apply` for every `NS.Units.LIST` entry. Subscribes to `Ka0s_KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT` plus `PLAYER_ENTERING_WORLD` — no new bus message. `IconGrid` and `Castbar` no longer own any label FontString.
20. `settings/Panel.lua` — registers the top-level Blizzard Settings category, the per-tab builder mailbox, the schema renderer (`Helpers.RenderSchema`), the schema-shape validator (`Helpers.ValidateSchema` runs at panel-register time and prints clear `|cffff0000KickCD schema error|r:` lines on a misshapen row), the always-visible-scrollbar patch (`Helpers.PatchAlwaysShowScrollbar`), the per-unit panel header (`Helpers.RenderUnitPanel` — unit selector dropdown + focus "Use same styling as Target" link checkbox / "Copy styling from Target" button, shared by the Icons, Cast bar, and Text Label builders), the row renderer (`Helpers.RenderRows`, each row wrapped in its own `pcall` so one bad saved value can't blank a panel) and the `alwaysPerUnit` splitter (`Helpers.PartitionUnitRows`, keeps a linked Focus's label `show`/`text` rows editable even though the rest of that panel's rows are link-gated), and the shared write-and-refresh helpers (`Helpers.Set`, `Helpers.SetAndRefresh`, `Helpers.RestoreDefaults`, `Helpers.RestoreAllDefaults`, `Helpers.ResetAll`, `Helpers.ResetIconPosition`, `Helpers.AnchorValues`, `Helpers.LSMValues`). `makeEditBox` is a free-text schema widget (commits on Enter/focus-loss, unlike the drag/click-commit widgets) backing the per-unit label-text rows. The ColorPicker's `OnValueChanged` commit runs through `Util.Throttle(50, ...)` so dragging a color slider doesn't thrash the bus or live frames.
21. `settings/{General,Icons,Castbar,Label,Spells,Profiles}.lua` — register their tabs via `NS.Settings.RegisterTab`. General / Icons / Cast bar / Label are pure schema (rows in `NS.Settings.Schema`); General carries only the per-unit `enabled` rows (`section = "units"`) for both `target` and `focus` — General has no unit selector, so both units' rows render together. `label.show`/`label.text` moved off General onto the new Label tab. Icons / Cast bar / Label render through `Helpers.RenderUnitPanel` (unit selector; `SchemaForPanel` filters rows to `ctx.unit`); Label's `show`/`text` rows carry `alwaysPerUnit = true` so `Helpers.PartitionUnitRows` renders them outside the link-gated appearance body — a linked Focus can still customize its own identity text even though its style rows mirror Target. Spells parents an AceGUI editor to `ctx.body` and listens for `Ka0s_KickCD_CONFIG_CHANGED { section = "spells" }` to rebuild rows after a slash-command write; Profiles parents an AceConfigDialog into `ctx.body` for the AceDBOptions table.

## AceAddon lifecycle

1. **TOC file-load** as listed above. After load: `core/Compat.lua` has populated `NS.Compat`; `core/Constants.lua` has populated `NS.Const`; `core/State.lua`'s bootstrap `CreateFrame` is already listening for `PLAYER_REGEN_DISABLED` / `_ENABLED` / `PLAYER_LOGIN` to maintain `NS.State.inCombat` (regardless of AceAddon module-enable order); `core/Units.lua` has populated `NS.Units`; `core/KickCD.lua` has run `AceAddon-3.0:NewAddon` to promote `NS` in place to an AceAddon object (no `_G.KickCD` rebind — the namespace stays private); `defaults/Spells.lua` has set `NS.DefaultSpells`; modules have called `NS:NewModule`; settings tabs have called `NS.Settings.RegisterTab`.
2. **`NS:OnInitialize`** (Ace lifecycle, fires on `ADDON_LOADED`): `Database:Init` builds the AceDB instance, runs `Database:FoldLegacyUnits` (shape-driven, always runs) then `Database:MigrateProfile` (`CURRENT_DB_VERSION = 2`; the v1→v2 step also calls `FoldLegacyUnits` and bumps `db.global.schemaVersion`), and seeds spells from `NS.DefaultSpells` on first profile creation. Slash commands `/kickcd` and `/kcd` are registered.
3. **`<Module>:OnEnable`**: modules subscribe to messages and game events. They NO LONGER seed their own `_inCombat` from `InCombatLockdown()` — `NS.State`'s file-load bootstrap owns the flag — and they NO LONGER register `PLAYER_REGEN_*` directly; combat-state transitions arrive via `Ka0s_KickCD_COMBAT_STATE` from `core/State.lua` so the dispatch order is explicit by construction.
   - `Cooldowns:OnEnable` registers `SPELL_UPDATE_COOLDOWN` / `_USABLE` / `_CHARGES`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, plus `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED` so a talent-choice swap or pet summon flips the watched-list immediately.
   - `IconGrid:OnEnable` calls `ReconcileUnits()`, which builds an instance (frame, `BuildCurves` / `BuildActiveList` / `Layout` / `RefreshVisibility`, registers the four inbound `Ka0s_KickCD_*` messages plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family) for every unit that's currently enabled (`NS.Units.IsEnabled(unit)`) — target only by default, since focus defaults `enabled = false`. Message registration is shared across instances via the module's own `self` target (AceEvent's per-module registration, not per-instance) but each handler resolves `instances[unit]` from the payload/event before acting.
   - `Castbar:OnEnable` mirrors `IconGrid`'s — `ReconcileUnits()` builds an instance per currently-enabled unit (`Reskin` / `ApplyLock`, registers that unit's cast-event family via `Util.RegisterUnitCastEvent`, plus `Ka0s_KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT` / `_COMBAT_STATE`), then calls `Reevaluate` per instance so a login while staring at a casting hostile mob/focus shows the bar immediately.
   - Enabling a previously-disabled unit later (flipping `units.focus.enabled` in Settings) fires `Ka0s_KickCD_CONFIG_CHANGED{section="units"}`, which both modules' `OnConfigChanged` route to `ReconcileUnits()` — the newly-wanted instance is built and re-evaluates its current cast/cooldown state immediately, without a `/reload`.
   - `UnitLabel:OnEnable` registers `Ka0s_KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT` plus `PLAYER_ENTERING_WORLD` and calls `ApplyAll()`, which builds/updates every unit's label frame regardless of that unit's enabled state — `Apply(inst)` itself gates visibility on `NS.Units.IsEnabled(unit)`, `label.show`, and the attach frame resolving, so a disabled unit's label frame exists but stays hidden rather than never being built.
4. **`PLAYER_LOGIN`** (deferred from `settings/Panel.lua`): the Blizzard Settings category is registered, `Helpers.ValidateSchema` runs against `NS.Settings.Schema` (any malformed row prints a `|cffff0000KickCD schema error|r:` line but doesn't refuse load), and per-tab builders run. Late-loading tabs auto-register if the main category already exists. Schema-driven panels defer their AceGUI render to `OnShow` because `ctx.body` is zero-width at PLAYER_LOGIN.

## External dependencies

All vendored under `libs/` and pulled in by `KickCD.toc`: LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0 (which pulls AceConfigRegistry / AceConfigCmd / AceConfigDialog), AceGUI-3.0, LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets (vendored upstream r65 multi-file lib — `widget.xml` + `prototypes.lua` + `BorderWidget.lua` + `FontWidget.lua` + `StatusbarWidget.lua` + `BackgroundWidget.lua` + `SoundWidget.lua` — providing the `LSM30_*` dropdowns the schema renderer swaps in for LSM-backed media rows), LibCustomGlow-1.0. `core/LSMPatch.lua` is an in-tree fixup loaded after the libs that wraps the `LSM30_Border` constructor at PLAYER_LOGIN to hide the 42×42 displayButton preview tile and re-anchor the dropdown bar.

`AceTimer-3.0` remains vendored under `libs/` (part of the standard Ace3 distribution) but is **not** loaded by the TOC. The six other unused Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab) were deleted from `libs/`.

`KickCD.toc`'s `## Interface:` line targets the Midnight client.

## Standard deviations recorded (target/focus dual tracking)

Per CLAUDE.md's flag-deviations rule, these are recorded as **intentional**:

- **Suffixed global frame names** (`KickCDIconGridFocus`, `KickCDCastbarFocus`) extend, rather than break, the "frame names stay literally `KickCD`" convention documented in [scope.md](scope.md) / [conventions.md](conventions.md) — target keeps the exact legacy name so existing macros/addons referencing it are unaffected, and focus gets an unambiguous `Focus` suffix rather than a numeric or generic index.
- **`Ka0s_KickCD_GRID_LAYOUT` payload gained `unit`** — additive change within the closed five-message bus, not a new message. See [message-bus.md](message-bus.md#ka0s_kickcd_grid_layout-payload).
- **`IconGrid` / `Castbar` module singleton → per-unit instance manager** (`instances[unit]`) — necessary because the two widgets now each render N independent unit instances (currently target + focus) sharing one module's message registration; a full module-per-unit split was rejected as it would have doubled the TOC surface and the `NS:GetModule("IconGrid", true)` accessor contract other code depends on.
- **`DEFAULT_PROFILE` restructure to `units.*`** (a rename/nest, not a pure addition) — see [saved-variables.md](saved-variables.md#migration-folding-legacy-iconscastbaranchors-into-unitstarget) for the full rationale and the shape-driven migration that makes it safe for existing installs.

Per CLAUDE.md's flag-deviations rule, recorded as **intentional** for the single-text-label feature:

- **`modules/UnitLabel.lua` (a new per-unit instance-manager module) + its `KickCDUnitLabelTarget` / `KickCDUnitLabelFocus` frame names** — a label needed to live in its own module, not stay bolted onto `IconGrid` or `Castbar`, because a unit's label can attach to *either* widget (`label.style.attach`) and must keep rendering even if the attach target is momentarily torn down/rebuilt; see [conventions.md](conventions.md#frame-names) for the frame-name-pattern rationale (including why the holder parents to `UIParent`, not the attach widget).
- **`units.<unit>.label.style` DB sub-shape + the dedicated `Database:BackfillLabelStyle` migration** — see [saved-variables.md](saved-variables.md#unitsunitlabelstyle-shape) for the full rationale.
- **The `alwaysPerUnit` schema-row flag** (`settings/Panel.lua`'s `Helpers.PartitionUnitRows`) — needed because a linked Focus's appearance rows are correctly hidden/mirrored, but its label `show`/`text` are per-unit identity data (like `label.text` always was) that must stay editable even while linked; a link-gate flag scoped to the row (rather than a parallel "always-shown panel section" concept) keeps the exception local to the two rows that need it.
- **The new `label` settings panel/section** (`settings/Label.lua`, `NS.Settings.order` after `castbar`) — the identity label graduated from a couple of General rows to its own full placement/orientation/font schema (`attach`, anchor points, offsets, justify, rotation, font/size/flags), which no longer fit General's "master controls" scope; a dedicated per-unit panel (mirroring Icons/Cast bar's `Helpers.RenderUnitPanel` pattern) was the natural home once the label grew a real appearance surface.
