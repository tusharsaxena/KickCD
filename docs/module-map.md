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
│                       Throttle, DeepCopy, PlayerSpecID / ResolveSpecID /
│                       NormalizeClassToken, chat print
│   ├── Units.lua     — NS.Units: single source of unit identity + per-unit
│                       config resolution for target/focus dual tracking
│                       (LIST, Config, IsEnabled, IsLinked, Icons/Castbar
│                       [link-resolved], Anchor/SetAnchor [never link-
│                       resolved], Label [text, per-unit], LabelShow +
│                       LabelStyle [both link-resolved], CopyStyling).
│                       Loads after Util, before Database
│   ├── Database.lua  — AceDB instance + DEFAULT_PROFILE (units.target /
│                       units.focus) + GetSpellList / EnsureSpellList
│                       helpers + spell-defaults merge + FoldLegacyUnits
│                       (shape-driven top-level icons/castbar/anchors ->
│                       units.target fold) + BackfillLabelStyle +
│                       MigrateSpecKeys + MigrateColorShape (positional
│                       {r,g,b,a} -> keyed { r =, g =, b =, a = }) +
│                       db.global.schemaVersion (CURRENT_DB_VERSION = 4)
│                       / MigrateProfile scaffold
│   ├── LSMPatch.lua  — PLAYER_LOGIN fixup wrapping the vendored LSM30_Border
│                       AceGUI widget to hide its 42×42 preview tile +
│                       re-anchor the dropdown bar (in-tree, survives lib refresh)
│   ├── KickCD.lua    — AceAddon bootstrap + the slash VERB TABLES (COMMANDS /
│                       DEBUG_COMMANDS / SPELLS_COMMANDS) and their handlers
│                       + OpenSettings (defers when subcategory not yet
│                       built). Dispatch itself is settings/Slash.lua's
│   ├── CoreSetup.lua — LibKa0s-Core-1.0 wiring: the secret-safe, NS.PREFIX-
│                       tagged chat printer, published as NS.Util.print
│                       (never NS.Print — AceConsole's own :Print sits there)
│   ├── DebugLogSetup.lua — LibKa0s-DebugLog-1.0 wiring: the on-screen console
│                       (KickCDDebugWindow), NS.DebugLog, and the bare
│                       NS.Debug(tag, fmt, …) sink. Session-only flag
│   └── PerfSetup.lua — LibKa0s-Perf-1.0 wiring: NS.Perf (on / Note /
│                       suspended / OnCommand) behind /kcd perf. LAST in the
│                       core block — needs NS.VERSION, the printer and the
│                       log sink, and precedes every modules/ file that takes
│                       `local Perf = NS.Perf` as a load-time upvalue
├── defaults/
│   └── Spells.lua    — per-class+spec default interrupt lists (NS.DefaultSpells)
├── modules/
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
│                       warning at layout time; stamps the per-instance
│                       inst.isCasting resolver the render sibling's glow
│                       trigger reads; emits Ka0s_KickCD_GRID_LAYOUT
│                       { unit, gridFrame, primaryIcon, width, height }
│   ├── IconGrid_Layout.lua — anchor/grow token parsing + block geometry
│                       (parseAnchor / parseGrow / placeBlock / layoutBlock),
│                       published as IconGrid.LayoutMath. Pure parsers are unit-
│                       tested headlessly; layoutBlock positions the buttons
│   ├── IconGrid_Render.lua — Icon prototype + CreateIconWidget, cooldown /
│                       glow rendering, alpha/tint/GCD-suppress curves run
│                       C-side; exposes IconGrid.CreateIconWidget /
│                       IconGrid.BuildCurves back to core, plus the pure
│                       deciders published for the headless suites
│                       (SafeUnpackColor / UnpackGlowColor /
│                       TriggerSatisfied / PlainStateMoved)
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
│   ├── Castbar_Skin.lua — the config-driven Castbar:Reskin, peeled off
│                       Castbar.lua (loads right after it, re-opening the
│                       registered module) to stay under the 1500-line cap.
│                       Split structural (guarded by a signature over the
│                       fields it reads) vs colour (always runs) so a 50 ms
│                       colour-picker drag stops re-running frame sizing,
│                       insets, spark and font loads (F-015)
│   ├── Castbar_Debug.lua — the Castbar:DebugDump(unit) diagnostic behind
│                       /kcd debug castbar, peeled off Castbar.lua (loads
│                       right after it, re-opening the registered module via
│                       NS:GetModule("Castbar")) to stay under the 1500-line cap
│   └── UnitLabel.lua — PER-UNIT INSTANCE MANAGER (instances[unit]): one
│                       identity FontString per unit, in a holder frame
│                       (KickCDUnitLabelTarget / KickCDUnitLabelFocus)
│                       created on UIParent, then SetParent'd onto the
│                       unit's ICON GRID (IconGrid:GetGridFrame(unit)) on every
│                       Apply — the grid is the frame that honors General
│                       visibility on the visibility mode alone, so the label
│                       inherits its shown state + effective alpha without
│                       being cast-gated by a cast bar that hides itself
│                       between casts. SetPoint-anchored to the unit's chosen
│                       attach frame (Castbar:GetCastbarFrame(unit) or
│                       IconGrid:GetGridFrame(unit), per label.style.attach)
│                       for POSITION only, independent of the visibility
│                       parent. Text read via NS.Units.Label (per-unit,
│                       never link-resolved); visibility via NS.Units.LabelShow
│                       and appearance (incl. label.style.color) via
│                       NS.Units.LabelStyle — both link-resolved, so a linked
│                       Focus mirrors Target's style AND its show flag.
│                       Shown iff the unit is enabled AND LabelShow AND the
│                       attach frame currently exists (further gated live by
│                       the grid's own visibility).
│                       Subscribes to the existing Ka0s_KickCD_CONFIG_CHANGED /
│                       _PROFILE_CHANGED / _GRID_LAYOUT messages — no new bus
│                       message was added. IconGrid and Castbar no longer own
│                       any label
└── settings/
    ├── Slash.lua     — LibKa0s-Slash-1.0 wiring: the /kcd dispatcher and the
                        schema CLI. Host-shaped remainder only — the `panel`
                        groupKey adapter, the valueGate hint, PAGE_ORDER, and
                        the `reset <path>` convergence with its deprecation
                        lines for the retired page names
    ├── OptionsSetup.lua — LibKa0s-Options-1.0 wiring: NS.Settings.Helpers IS
                        the library instance, decorated in place by the three
                        Panel* files. Owns skipRestoreAll (Profiles rows are
                        AceDBOptions-supplied — resetting them deletes user
                        data). Loads BEFORE Panel.lua and every page file
    ├── Panel.lua     — top-level category + canvas-panel framework
                        (CreatePanel header, lazy AceGUI scroll +
                        always-show-scrollbar patch, Section) + schema
                        query/validation (SchemaForPanel + ValidateSchema)
                        + Helpers.Set/Get + AnchorValues/LSMValues + the
                        main landing page. Peeled into two siblings that
                        load right after it (KCD-24 — all three publish onto
                        the one NS.Settings.Helpers table):
    ├── Panel_Widgets.lua — the widget-maker primitives (checkbox / slider /
                        dropdown / editbox / colorpicker) behind
                        Helpers.RenderField, plus the inline Button /
                        InlinePair / InlineButtonPair / SessionToggle
                        helpers. makeEditBox commits on Enter/focus-loss
                        (unlike the drag/click-commit widgets); the
                        ColorPicker commit runs through Util.Throttle(50, …)
                        so a color-slider drag doesn't thrash the bus/frames.
    ├── Panel_Render.lua — schema render + reset layer: Helpers.RenderRows
                        (each row's RenderField wrapped in its own pcall so
                        one bad saved value can't blank the panel),
                        Helpers.RenderSchema, Helpers.RenderUnitPanel (unit
                        selector + focus link/copy header, shared by
                        Icons/Castbar/Label), Helpers.PartitionUnitRows
                        (alwaysPerUnit split — generic infra, but no schema
                        row currently sets the flag), and the write-and-
                        refresh / reset helpers (SetAndRefresh,
                        RestoreDefaults, RestoreAllDefaults, ResetAll,
                        ResetIconPosition).
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
                        units.<unit>.label.{show,text,style.*}. Only text is
                        per-unit at READ time (NS.Units.Label); show follows
                        the link (NS.Units.LabelShow). Neither row carries
                        alwaysPerUnit any more — a linked Focus's Text Label
                        page collapses to just the "Linked to Target" note,
                        same as Icons/Cast bar (unlink to edit show/text); the
                        label still renders per-unit text, with Target's style
                        and show flag, while linked.
                        The style.* rows (attach/point/relPoint/offsets/
                        justify/rotation/font/size/flags/color) are link-resolved
                        appearance and follow the same body the Icons/Castbar
                        panels use. Rendered via the shared unit selector
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
3. `core/Compat.lua` — hangs `NS.Compat` (the shared private namespace `NS` arrives as the second file vararg, not a global), populating `Compat` shims for spell APIs (`GetSpellCooldown`, `GetSpellCooldownDuration`, `GetSpellInfo`, `GetSpellTexture`, `GetSpellCharges`, `IsSpellUsable`, `IsSpellAvailable`, `GetCastingInfo`, `GetChannelInfo`, `DebugInterrupt`) plus the `Compat._firstReturn` truthy-check helper. `GetSpellCooldownDuration`'s docstring carries the measured 12.0.7 secrecy rules — every getter on the returned object except `HasSecretValues()` is secret in combat, and it returns a ZEROED object (not nil) for an idle spell. **Loads first** of `core/` — anything later can rely on `NS.Compat` existing.
4. `core/Constants.lua` — exposes `NS.Const` with named constants used across modules (`GCD_UPPER`, `CASTBAR_INSIDE_INSET`, `CASTBAR_OUTSIDE_INSET`, `PANEL_HEADER_TOP`, `PANEL_HEADER_HEIGHT`, `PANEL_PADDING_X`, `PANEL_DEFAULTS_W`).
5. `core/State.lua` — `NS.State` namespace owning shared mutable state and visibility helpers. Owns `NS.State.inCombat` (the event-driven combat flag, mirrored across IconGrid and Castbar) and the visibility helpers `NS.State.IsHostileUnitCasting(unit)` and `NS.State.ApplyInterruptibleAlpha(frame, unit, alpha)` (hoisted out of Compat in CR-27 because they're feature decisions, not API normalisation). A bootstrap `CreateFrame` in this file is the only place in the addon that registers `PLAYER_REGEN_DISABLED/_ENABLED/PLAYER_LOGIN`; after writing the flag it fires `Ka0s_KickCD_COMBAT_STATE` so subscribers see an explicit ordered transition signal. The frame fires regardless of whether the modules have enabled yet, so an edge-case ordering bug can't desync the flag from reality.
6. `core/Util.lua` — color helper (`Unpack`), anchor save/restore (`SaveAnchor` / `ApplyAnchor`), `Throttle` (leading-edge: fires on first call then ignores until window closes — used by the Spells editor's debounced commit and the ColorPicker's drag-to-commit), `DeepCopy` (single shared deep-copy used by `Helpers.RestoreDefaults`, `Database`, `settings/Spells.lua`), the spec-identity helpers `PlayerSpecID` / `SpecTokenForID` / `SpecDisplay` / `SpecDisplayName` / `SpecOrderForClass` / `ResolveSpecID` (numeric specIDs are the locale-invariant spell-list key; localised spec names are display-only — see [saved-variables.md](saved-variables.md#migration-localised-spec-names--numeric-spec-ids)), plus `NormalizeSpecToken` / `NormalizeClassToken` (whitespace strip + uppercase, now used only to parse user input and legacy saved keys), and the chat `print` helper.
6b. `core/CoreSetup.lua` — the `LibKa0s-Core-1.0` descriptor. The secret-safe stringifier and the prefixed chat printer are the library's; this file supplies the tag the lines carry, the degradation stub, and `NS.LIBKA0S_MISSING` — the one cause clause `core/DebugLogSetup.lua`, `core/PerfSetup.lua`, `settings/OptionsSetup.lua` and `settings/Slash.lua` each append their own "so &lt;what&gt; is unavailable" to. It is set **outside** the `if not lib` branch, because the seams that read it are reached on both paths, and it lives here because this is the first of the five seams the TOC loads. AbsorbTracker and ConsumableMaster carry the identical clause; a degraded install of any Ka0s addon says the same thing about *why*. Publishes the printer as **`NS.Util.print`, never `NS.Print`** — `core/KickCD.lua` embeds AceConsole-3.0 onto `NS`, whose own `:Print` would silently swallow the key. Loads after `core/Constants.lua` (which defines `NS.PREFIX`, passed in function form so it is re-read per call) and after `core/Util.lua`, whose `NS.Util = Util` assignment would otherwise replace the table this file publishes into. Nothing downstream takes the printer as a load-time upvalue — all ~20 call sites resolve `NS.Util and NS.Util.print` at call time.

6c. `core/DebugLogSetup.lua` — the `LibKa0s-DebugLog-1.0` descriptor. The console itself — the lazily-built DIALOG-strata window "Ka0s KickCD — Debug" (global frame `KickCDDebugWindow`), the `ScrollingMessageFrame` log, the Copy/Clear pair (Copy opens `KickCDDebugCopyWindow`), the header `Debug: ON/OFF` toggle, the 500-line buffer, the scrollbar sync and the line counter — is the library's. This file supplies only what is ours: `name` (which seeds those frame globals), the title, the JetBrains Mono path shipped from `media/fonts/` and registered with LibSharedMedia at load, where the session-only `NS.State.debug` flag lives, and what the `[Init]` summary says. It publishes `NS.DebugLog` and binds the sink bare as `NS.Debug(tag, fmt, ...)`. It replaced `modules/DebugLog.lua` (518 lines), whose two formatters were already byte-identical to the library's.

7. `core/Units.lua` — `NS.Units`: single source of unit identity (`LIST = { "target", "focus" }`) and per-unit config resolution (`Config`, `IsEnabled`, `IsLinked`, `Icons`/`Castbar` [link-resolved — a linked focus reads target's appearance tables], `Anchor`/`SetAnchor` [never link-resolved — position stays per-unit], `Label` [the label table; read `.text` from it — per-unit], `LabelShow` / `LabelStyle` [both link-resolved — a linked focus mirrors target's show flag and style], `CopyStyling` [deep-copies `icons`/`castbar`/`label.style` AND snapshots `label.show`, then flips `link = false`]). `IconGrid` and `Castbar` never reach `db.profile.units.<unit>` directly for appearance; they go through here so the "link to target styling" behavior lives in exactly one place. Loads after `core/Util.lua`, before `core/Database.lua` (no dependency on Database — reads `NS.db.profile` lazily at call time, not at file load).
8. `core/Database.lua` — defines `DEFAULT_PROFILE` (`units.target` / `units.focus`, each carrying its own `icons`/`castbar`/`anchors`/`label`/`enabled`/`link`), `Database:Init` (called from `NS:OnInitialize`), `Database:GetSpellList(class, spec)` (read-only) / `Database:EnsureSpellList(class, spec)` (lazy-creating; the only mutator entry point), `Database:BuildSpells` (no-reseed-when-non-empty; see [scope.md](scope.md)), `Database:ResetAllSpells`, `Database:FoldLegacyUnits` (shape-driven fold of pre-units top-level `icons`/`castbar`/`anchors` into `units.target`, idempotent, run unconditionally ahead of the version-gated path — see [saved-variables.md](saved-variables.md#migration-folding-legacy-iconscastbaranchors-into-unitstarget)), `Database:BackfillLabelStyle` (shape-driven fill of `units.<unit>.label.style` and any key added to `LABELSTYLE_DEFAULT` since — see [saved-variables.md](saved-variables.md#unitsunitlabelstyle-shape)), `Database:MigrateSpecKeys` (shape-driven rekey of `spells[CLASS][localised name]` to `spells[CLASS][specID]`), `Database:MigrateColorShape` (version-gated v3→v4 rewrite of every stored colour from the positional `{r,g,b,a}` array to the keyed `{ r =, g =, b =, a = }` shape the LibKa0s slash / options vocabulary uses), and the `db.global.schemaVersion` migration scaffold (`CURRENT_DB_VERSION = 4`; `Database:MigrateProfile` runs at Init and on profile change). Does not create the DB at file-load time.
9. `core/LSMPatch.lua` — in-tree fixup for the vendored `AceGUI-3.0-SharedMediaWidgets`. A one-shot `PLAYER_LOGIN` frame wraps the `LSM30_Border` widget constructor to hide its misaligned 42×42 `displayButton` preview tile and re-anchor the dropdown bar. Lives in addon code (not the lib) so a future lib refresh doesn't blow it away.
10. `core/KickCD.lua` — promotes the bootstrap table to an AceAddon, registers `/kickcd` and `/kcd`, and defines the `COMMANDS` (published as `NS.COMMANDS` and passed into the Slash descriptor) / `DEBUG_COMMANDS` / `SPELLS_COMMANDS` verb tables plus their handlers. Dispatch itself — the bare-input help, the verb lowercasing that deliberately leaves `rest` alone, the `options` → `config` alias, the unknown-verb line — is `LibKa0s-Slash-1.0`'s, reached through `settings/Slash.lua` at call time; the schema CLI verbs (`list` / `get` / `set` / `reset`) are thin forwarders to it. `OpenSettings` defers (one-shot retry, capped at 3) when the General subcategory hasn't built yet so a `/kcd config` immediately after login lands on the real page rather than the empty parent.
10b. `core/PerfSetup.lua` — the `LibKa0s-Perf-1.0` descriptor, publishing `NS.Perf` (the `on` gate, the `Note` sink, the `suspended` flag the two show decisions consult, and `OnCommand`, which backs `/kcd perf`). The probe, the guided A/B run, the record schema and the clickable step panel are the library's; this file supplies which paths are worth measuring and what "inert" means here — the measurable cost is `iconApply`, whose rate is forced by `C_Spell.GetSpellCooldownDuration` minting a fresh handle per call rather than by frame rate. **Last in the core block**, after `core/KickCD.lua`: `NS.VERSION` must already exist (it didn't when this file sat higher, and every capture record stamped `v?`), as must `NS.Util.print` and the debug-log sink — and it must precede every `modules/` file that takes `local Perf = NS.Perf` as a load-time upvalue. `version` is read from the TOC manifest with `NS.VERSION` as fallback, the same pair `settings/Slash.lua` resolves, so a capture record and `/kcd version` can't disagree.
11. `defaults/Spells.lua` — populates `NS.DefaultSpells` (per-class+spec interrupt list); merged into the profile by `Database:BuildSpells` on first profile creation.
12. `modules/Cooldowns.lua` — polls cooldown state, emits `Ka0s_KickCD_SPELL_STATE`. Listens for `SPELL_UPDATE_COOLDOWN/USABLE/CHARGES` — routed through `OnCooldownEvent` into a `Util.Throttle(0)` coalescer so a same-frame burst of these chatty, global (spell-agnostic) events collapses to a single `Refresh` on the next frame instead of one full watched-list re-poll each — plus `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED` (the last two pick up talent-choice swaps and pet summon/dismiss without waiting for a spec change; these `Rebuild` triggers stay synchronous — only the `SPELL_UPDATE_*` path is coalesced). On poll-nil for a previously-watched spell (pet dismissed, talent untrained), emits a sentinel `SPELL_STATE` with `ready=false, isActive=false, cdObject=nil` and unwatches the id — without it the orphan icon would linger with stale state. Player-centric and unit-agnostic — the same `SPELL_STATE` payload feeds every enabled unit's `IconGrid` instance. `StateChanged` (which decides whether to emit) includes the cooldown-handle identity, so it re-fires on every poll for a spell on cooldown; `MaterialChange` is the narrower predicate gating the debug line so that churn doesn't flood the console.
13. `modules/IconGrid.lua` — PER-UNIT INSTANCE MANAGER: `instances[unit]` (`NS.Units.LIST`), each holding its own frame, icon pool, `Layout` state, and cooldown-text ticker. Owns the `KickCDIconGrid` (target) / `KickCDIconGridFocus` (focus) frames, the per-icon ready glow (LibCustomGlow) per instance. `EnableUnit(unit)` / `DisableUnit(unit)` / `ReconcileUnits()` build or tear down a unit's instance against `NS.Units.IsEnabled(unit)`; `UNIT_SPELLCAST_*` registration is enable-gated per instance (a disabled unit's instance doesn't listen at all) and instances re-evaluate on enable so mid-cast enabling doesn't miss the in-flight cast. `BuildActiveList` dedupes by spellID per instance; `Layout` warns once per instance when `visibleCount > rows*cols`. Stamps a per-instance `inst.isCasting` resolver that the render sibling's glow trigger reads (it replaced the old module-level `IconGrid._isTargetCasting` hook when tracking went per-unit). Also publishes the pure visibility deciders `IconGrid.VisibilityMode` / `.ShouldBeVisible` / `.InstanceCasting` / `.MasterEnabled` for the headless suites — note `MasterEnabled`, **not** `IsEnabled`, because AceAddon embeds its own `IsEnabled(self)` on every module object and publishing under that name would shadow it. Listens for the four inbound `Ka0s_KickCD_*` messages (`Ka0s_KickCD_SPELL_STATE`, `Ka0s_KickCD_CONFIG_CHANGED` — including the `"units"` section, which triggers `ReconcileUnits` **and** a `BuildCurves` rebuild, because the focus link flag lives in that section and `NS.Units.Icons` is link-aware, so flipping it changes what a unit's curves must be built from without any `icons.*` value moving — `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_COMBAT_STATE`) plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family (`UNIT_SPELLCAST_START/_STOP/_FAILED/_INTERRUPTED/_CHANNEL_START/_CHANNEL_STOP/_INTERRUPTIBLE/_NOT_INTERRUPTIBLE`). Combat transitions arrive via `Ka0s_KickCD_COMBAT_STATE` (sent by `core/State.lua`); the module no longer hooks `PLAYER_REGEN_*` directly. Each instance emits its own `Ka0s_KickCD_GRID_LAYOUT` after every layout pass with `{ unit, gridFrame, primaryIcon, width, height }`. `RefreshAllGlows` short-circuits when the (hostile-cast, interruptible) gate hasn't moved.
14. `modules/IconGrid_Layout.lua` — icon-grid geometry peeled from IconGrid (KCD-05): anchor/grow token parsing and block placement (`parseAnchor` / `parseGrow` / `placeBlock` / `layoutBlock`), published on the module as `IconGrid.LayoutMath` (a distinct key from the `IconGrid:Layout()` orchestrator method, which loads first and would otherwise be clobbered — KCD-05). The parsers are pure (numbers/strings in and out) and unit-tested headlessly; `layoutBlock` is the frame-manipulating orchestrator that positions the primary + secondary buttons against a given instance's grid frame.
15. `modules/IconGrid_Render.lua` — per-icon rendering peeled from IconGrid (KCD-05): the `Icon` prototype and its factory `CreateIconWidget`, the cooldown-swipe / countdown-text / ready-glow drawing, the step-shaped alpha/tint/GCD-suppress curves run C-side, and the shared per-instance cooldown-text ticker. `Icon:Apply` splits its work: the curve evaluations, swipe re-arm and countdown text are time-varying and run on every payload, while glow / charges badge / Show calls are gated behind `plainStateMoved` (a config-driven re-apply passes `force=true` to bypass it). The **alpha and tint curves are per unit** (`_curves[unit]`, resolved through `curvesFor(icon.unit)`): they're built from that unit's `NS.Units.Icons` table, so an unlinked focus with its own `readyAlpha` / `cooldownAlpha` / `cooldownTint` renders with those instead of silently inheriting target's. `curvesFor` deliberately does **not** fall back to target — inheriting another unit's alpha/tint is the bug the split exists to fix. The GCD-suppression curve stays module-level and is built once (its control points are the fixed flags 0 and 1, nothing config-derived). `BuildCurves` is guarded per unit by `curveSignature` over exactly those three fields, so an "icons" `CONFIG_CHANGED` that only touched border / font / layout / glow no longer recreates anything (F-016). Exposes `IconGrid.CreateIconWidget` / `IconGrid.BuildCurves` back to core plus, for the headless suites, `IconGrid.Icon` (the mixin), `IconGrid.CurvesFor` / `.CurveSignature`, and the pure deciders `IconGrid.SafeUnpackColor` / `.UnpackGlowColor` / `.TriggerSatisfied` / `.PlainStateMoved` / `.FetchBorderTexture`; the glow trigger reads the per-instance `inst.isCasting` resolver stamped on each icon via `btn.instance`.
16. `modules/Castbar.lua` — PER-UNIT INSTANCE MANAGER mirroring `IconGrid.lua`'s structure: `instances[unit]`, each owning its own frame — `KickCDCastbar` (target) / `KickCDCastbarFocus` (focus) — and mirroring the corresponding unit's target/focus cast/channel via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration` shims (see [castbar.md](castbar.md)). Stacked dual widgets (background, statusbar, border) per instance are alpha-curve-switched on the cast's secret `notInterruptible` bool. `EnableUnit` / `DisableUnit` / `ReconcileUnits` mirror `IconGrid`'s; `UNIT_SPELLCAST_*` registration is enable-gated and unit-filtered (a focus instance dispatches only on focus casts) via `Util.RegisterUnitCastEvent`. Each instance anchors free or to its own unit's icon grid primary icon button (re-anchors on `Ka0s_KickCD_GRID_LAYOUT`, filtering the payload on `payload.unit` before resolving `instances[payload.unit]`, reading the payload's `gridFrame` / `primaryIcon` directly with a fallback to `NS:GetModule("IconGrid", true):GetGridFrame` / `:GetPrimaryIcon` for the first tick). Auto-size mode tracks that unit's grid frame's actual visible footprint, not its configured rows × cols capacity. `Castbar:Reskin` / `Castbar:RenderCast` are split per instance: config-driven work (orientation, sizing, fonts, anchors) only re-runs on `OnConfigChanged` (including the `"units"` section) / `OnGridLayout` / `OnProfileChanged`, while cast-record-driven work (texture, name, seed bar values, ApplyState) runs on `Start`. The hot path doesn't re-skin per cast. Exposes `GetCastbarFrame(unit)`, one of the two attach-frame lookups `modules/UnitLabel.lua` calls.
16b. `modules/Castbar_Skin.lua` — the config-driven re-skin only. Peeled from `Castbar.lua` (loaded immediately after it in the TOC, re-opening the registered `Castbar` module via `NS:GetModule("Castbar")` to add `Castbar:Reskin`) to keep `Castbar.lua` under the §1.2 1500-line hard cap. Internally two halves: `ReskinStructure` (frame size incl. auto-size against the unit's grid, orientation + reverse fill, icon/bar inset split, spark, fonts, text anchors, per-state border **backdrops**) is guarded by a signature over exactly the config fields it reads, so it is skipped when none moved; `ReskinColors` (per-state backgrounds, status-bar textures + colours, border **tints**, the shared time-text colour) always runs. That split is F-015: a colour-picker drag commits every 50 ms and no longer pays for the ~40 structural widget calls. The signature folds in the **resolved** bar dimensions, not just raw config, because auto-size tracks the grid footprint across `Ka0s_KickCD_GRID_LAYOUT` while the config table doesn't move. `EnableUnit` passes `force = true` so a freshly built frame always gets real geometry. Shared helpers come off the module table (`Castbar.UnpackColor` / `.StateConfig` / `.FetchFont` / `.ResolveGridFrame` / …) rather than being duplicated.

16c. `modules/Castbar_Debug.lua` — the `/kcd debug castbar` diagnostic only. Peeled from `Castbar.lua` (loaded immediately after it in the TOC, re-opening the already-registered `Castbar` module via `NS:GetModule("Castbar")` to add the `Castbar:DebugDump(unit)` method) to keep `Castbar.lua` under the §1.2 1500-line hard cap. Secret-value-safe: reports `notInterruptible`/`spellID`/`name` via `type()`/`issecretvalue()`, never `tostring`/format on a secret.
17. `modules/UnitLabel.lua` — PER-UNIT INSTANCE MANAGER (`instances[unit]`): a holder frame (`KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`), created on `UIParent`, each carrying one `FontString`, `SetPoint`-anchored to `IconGrid:GetGridFrame(unit)` or `Castbar:GetCastbarFrame(unit)` per `label.style.attach` (position only). `Apply(inst)` re-reads `NS.Units.Label(unit)` (per-unit `show`/`text`) and `NS.Units.LabelStyle(unit)` (link-resolved appearance, including the text `color`) and re-applies text/font/color/justify/rotation/anchor; it also `SetParent`s the holder onto the unit's ICON GRID (`IconGrid:GetGridFrame(unit)`, falling back to the attach frame if the grid isn't up yet) — never the cast bar — so the label inherits the grid's own shown state + alpha and follows General visibility, without being cast-gated by the cast bar hiding itself between casts. Shown iff the unit is enabled AND `label.show` AND the attach frame currently resolves (and, live, whenever the grid frame itself is shown/hidden). `ApplyAll` re-runs `Apply` for every `NS.Units.LIST` entry. Subscribes to `Ka0s_KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT` plus `PLAYER_ENTERING_WORLD` — no new bus message. `IconGrid` and `Castbar` no longer own any label FontString.
18. `settings/Slash.lua` — the `LibKa0s-Slash-1.0` descriptor: the `/kcd` dispatcher, the help renderer, the row / key-value formatters, the list builder and the type-aware parser are the library's. What stays here is the host-shaped remainder — the `groupKey` adapter (KickCD rows carry `panel`, not `page`), the `parse` override carrying `NS.Slash.GateHint` (which sibling setting gated a rejected dropdown value; it probes by swapping the gate's stored value and re-asking the row's own `values` function), the `PAGE_ORDER` that `/kcd list` groups by, and the `reset` convergence: `reset` takes a schema **path**, and each retired page name (`general`/`icons`/`castbar`/`label`) plus `reset spells` answers with where its capability went. Loads after `core/KickCD.lua`, which defines the `NS.COMMANDS` verb table passed into the descriptor at load; `NS:OnSlashCommand` reaches `NS.Slash` at call time, so the registration in `OnInitialize` is unaffected by the split. Degrades to a stub — host verbs keep working, the schema CLI names the missing library — with no hand-copied formatter.
19. `settings/OptionsSetup.lua` — the `LibKa0s-Options-1.0` descriptor. The settings-canvas shell, header and breadcrumb, the lazy Defaults button, the five widget makers, the two-column flow engine and the always-shown scrollbar patch are the library's. `NS.Settings.Helpers` **is** the library instance, decorated in place by `Panel.lua` / `Panel_Widgets.lua` / `Panel_Render.lua` — never a fresh table copying members across, so a later-added host helper and a suite's spy both see the same object the library's own callers do. Supplies where a value lives, which rows belong to which page, and `descriptor.skipRestoreAll` — the Profiles rows are AceDBOptions-supplied and resetting them deletes user data, so they are vetoed from "reset everything" both by the library and by the degradation stub's own reset loop. Loads **before** `settings/Panel.lua` and therefore before every `settings/<page>.lua`, which call `Helpers.LSMValues` / `Helpers.AnchorValues` inside schema-row literals at file load.
20. `settings/Panel.lua` — the canvas-panel framework core. Registers the top-level Blizzard Settings category and the per-tab builder mailbox, builds the shared header (`Helpers.CreatePanel`), owns the lazy AceGUI scroll container + the always-visible-scrollbar patch (`Helpers.PatchAlwaysShowScrollbar`) + `Helpers.Section`, runs the schema query helpers (`Helpers.SchemaForPanel` / `Helpers.FindSchema`) and the schema-shape validator (`Helpers.ValidateSchema` runs at panel-register time and prints clear `|cffff0000KickCD schema error|r:` lines on a misshapen row), and exposes the profile-write seam (`Helpers.Set`/`Helpers.Get`), the dropdown value builders (`Helpers.AnchorValues`, `Helpers.LSMValues`), and the main landing page (`Helpers.BuildMainContent`). Peeled into two siblings (KCD-24) that load right after it; all three publish onto the one `NS.Settings.Helpers` table, so call order across the trio is irrelevant.
20b. `settings/Panel_Widgets.lua` — the widget-maker primitives, peeled from `Panel.lua`. `Helpers.RenderField` dispatches by `def.type` to a checkbox / slider / dropdown (stock or `LSM30_*` for media rows) / free-text editbox / colorpicker maker; each binds directly to `db.profile` via `Helpers.Get`/`Set` and registers a `ctx.refreshers` closure so the widget re-syncs after a Defaults reset or a `/kcd set`. `makeEditBox` commits on Enter/focus-loss (unlike the drag/click-commit widgets) and backs the per-unit label-text rows; the ColorPicker's `OnValueChanged` commit runs through `Util.Throttle(50, ...)` so dragging a color slider doesn't thrash the bus or live frames. Also the inline action helpers: `Helpers.InlinePair` (two half-width widgets on one Flow row — backs General's "Lock frame" + "Debug console" pairing) and `Helpers.InlineButtonPair` (two 50/50 action buttons — backs "Reset position" + "Reset all settings"), plus the session-only (non-schema) `Helpers.SessionToggle` (backs the debug-console checkbox).
20c. `settings/Panel_Render.lua` — the schema render + reset/orchestration layer, peeled from `Panel.lua`. The row renderer (`Helpers.RenderRows`, each row's `RenderField` wrapped in its own `pcall` so one bad saved value can't blank a panel) and its `Helpers.RenderSchema` front end; the per-unit panel header (`Helpers.RenderUnitPanel` — unit selector dropdown + focus "Use same styling as Target" link checkbox / "Copy styling from Target" button, shared by the Icons, Cast bar, and Text Label builders) plus `Helpers.ClearScroll` (which drops `ctx.refreshers` as well as releasing the widgets — a refresher outliving its widget gets replayed against whatever AceGUI's pool recycled that object into) / `Helpers.RerenderUnitPanel`; the `alwaysPerUnit` splitter (`Helpers.PartitionUnitRows` — generic infra for keeping a row editable on a linked Focus's page while the rest of that panel is link-gated; it was added for the label `show`/`text` rows, which no longer set the flag, so today no schema row does); and the write-and-refresh / reset helpers (`Helpers.SetAndRefresh`, `Helpers.RefreshAllPanels`, `Helpers.RestoreDefaults`, `Helpers.RestoreAllDefaults`, `Helpers.ResetAll`, `Helpers.ResetIconPosition`, `Helpers.ResetAllPositions`, `Helpers.RestoreUnitLinks`).
21. `settings/{General,Icons,Castbar,Label,Spells,Profiles}.lua` — register their tabs via `NS.Settings.RegisterTab`. General / Icons / Cast bar / Label are pure schema (rows in `NS.Settings.Schema`); General carries only the per-unit `enabled` rows (`section = "units"`) for both `target` and `focus` — General has no unit selector, so both units' rows render together. `label.show`/`label.text` moved off General onto the new Label tab. Icons / Cast bar / Label render through `Helpers.RenderUnitPanel` (unit selector; `SchemaForPanel` filters rows to `ctx.unit`); Label's `show`/`text` rows no longer carry `alwaysPerUnit` (removed in the defaults follow-up), so a linked Focus's Text Label page renders no body rows — just the "Linked to Target" note, matching Icons/Cast bar. Both stay per-unit *data* in the DB, but only `text` is read per-unit (`NS.Units.Label`) — `show` resolves through the link (`NS.Units.LabelShow`), so a linked, enabled Focus shows its own label text with Target's style and Target's show flag. Neither is editable on the page while linked — uncheck the link to edit them. Spells parents an AceGUI editor to `ctx.body` and listens for `Ka0s_KickCD_CONFIG_CHANGED { section = "spells" }` to rebuild rows after a slash-command write; Profiles parents an AceConfigDialog into `ctx.body` for the AceDBOptions table.

## AceAddon lifecycle

1. **TOC file-load** as listed above. After load: `core/Compat.lua` has populated `NS.Compat`; `core/Constants.lua` has populated `NS.Const`; `core/State.lua`'s bootstrap `CreateFrame` is already listening for `PLAYER_REGEN_DISABLED` / `_ENABLED` / `PLAYER_LOGIN` to maintain `NS.State.inCombat` (regardless of AceAddon module-enable order); `core/Units.lua` has populated `NS.Units`; `core/KickCD.lua` has run `AceAddon-3.0:NewAddon` to promote `NS` in place to an AceAddon object (no `_G.KickCD` rebind — the namespace stays private); `defaults/Spells.lua` has set `NS.DefaultSpells`; modules have called `NS:NewModule`; settings tabs have called `NS.Settings.RegisterTab`.
2. **`NS:OnInitialize`** (Ace lifecycle, fires on `ADDON_LOADED`): `Database:Init` builds the AceDB instance, runs `Database:FoldLegacyUnits`, `Database:BackfillLabelStyle` and `Database:MigrateSpecKeys` (all three shape-driven, always run) then `Database:MigrateProfile` (`CURRENT_DB_VERSION = 4`; the v1→v2 step also calls `FoldLegacyUnits`, the v2→v3 step `MigrateSpecKeys`, the v3→v4 step `MigrateColorShape`, each bumping `db.global.schemaVersion`), and seeds spells from `NS.DefaultSpells` on first profile creation. Slash commands `/kickcd` and `/kcd` are registered.
3. **`<Module>:OnEnable`**: modules subscribe to messages and game events. They NO LONGER seed their own `_inCombat` from `InCombatLockdown()` — `NS.State`'s file-load bootstrap owns the flag — and they NO LONGER register `PLAYER_REGEN_*` directly; combat-state transitions arrive via `Ka0s_KickCD_COMBAT_STATE` from `core/State.lua` so the dispatch order is explicit by construction.
   - `Cooldowns:OnEnable` registers `SPELL_UPDATE_COOLDOWN` / `_USABLE` / `_CHARGES`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, plus `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED` so a talent-choice swap or pet summon flips the watched-list immediately.
   - `IconGrid:OnEnable` calls `ReconcileUnits()`, which builds an instance (frame, `BuildCurves` / `BuildActiveList` / `Layout` / `RefreshVisibility`, registers the four inbound `Ka0s_KickCD_*` messages plus `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TARGET_CHANGED`, and the cast-event family) for every unit that's currently enabled (`NS.Units.IsEnabled(unit)`) — both target and focus by default, since `DEFAULT_PROFILE` seeds `units.focus.enabled = true` (a user who turns focus off leaves target as the only live instance). Message registration is shared across instances via the module's own `self` target (AceEvent's per-module registration, not per-instance) but each handler resolves `instances[unit]` from the payload/event before acting.
   - `Castbar:OnEnable` mirrors `IconGrid`'s — `ReconcileUnits()` builds an instance per currently-enabled unit (`Reskin` / `ApplyLock`, registers that unit's cast-event family via `Util.RegisterUnitCastEvent`, plus `Ka0s_KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT` / `_COMBAT_STATE`), then calls `Reevaluate` per instance so a login while staring at a casting hostile mob/focus shows the bar immediately.
   - Enabling a previously-disabled unit later (flipping `units.focus.enabled` in Settings) fires `Ka0s_KickCD_CONFIG_CHANGED{section="units"}`, which both modules' `OnConfigChanged` route to `ReconcileUnits()` — the newly-wanted instance is built and re-evaluates its current cast/cooldown state immediately, without a `/reload`.
   - `UnitLabel:OnEnable` registers `Ka0s_KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT` plus `PLAYER_ENTERING_WORLD` and calls `ApplyAll()`, which builds/updates every unit's label frame regardless of that unit's enabled state — `Apply(inst)` itself gates visibility on `NS.Units.IsEnabled(unit)`, `label.show`, and the attach frame resolving, so a disabled unit's label frame exists but stays hidden rather than never being built.
4. **`PLAYER_LOGIN`** (deferred from `settings/Panel.lua`): the Blizzard Settings category is registered, `Helpers.ValidateSchema` runs against `NS.Settings.Schema` (any malformed row prints a `|cffff0000KickCD schema error|r:` line but doesn't refuse load), and per-tab builders run. Late-loading tabs auto-register if the main category already exists. Schema-driven panels defer their AceGUI render to `OnShow` because `ctx.body` is zero-width at PLAYER_LOGIN.

## External dependencies

All vendored under `libs/` and pulled in by `KickCD.toc`: LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0 (which pulls AceConfigRegistry / AceConfigCmd / AceConfigDialog), AceGUI-3.0, LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets (vendored upstream r65 multi-file lib — `widget.xml` + `prototypes.lua` + `BorderWidget.lua` + `FontWidget.lua` + `StatusbarWidget.lua` + `BackgroundWidget.lua` + `SoundWidget.lua` — providing the `LSM30_*` dropdowns the schema renderer swaps in for LSM-backed media rows), LibCustomGlow-1.0. `core/LSMPatch.lua` is an in-tree fixup loaded after the libs that wraps the `LSM30_Border` constructor at PLAYER_LOGIN to hide the 42×42 displayButton preview tile and re-anchor the dropdown bar.

Seven unused Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab, AceTimer) were deleted from `libs/`. `AceTimer-3.0` went last (KCD-29): `library-stack-§1` lists it among the mandatory Ace3 libs, but `library-stack-§3` says vendor only what the addon actually `LibStub`s — scheduling here is `C_Timer.After` throughout and nothing ever loaded it, so §3 won. `tests/wow_mock.lua` keeps its **fake** AceTimer mixin (`embedAceTimer`) — that's the mock's own scheduling shim, unrelated to the vendored lib.

`KickCD.toc`'s `## Interface:` line targets the Midnight client.

## Standard deviations recorded (target/focus dual tracking)

Per CLAUDE.md's flag-deviations rule, these are recorded as **intentional**:

- **Suffixed global frame names** (`KickCDIconGridFocus`, `KickCDCastbarFocus`) extend, rather than break, the "frame names stay literally `KickCD`" convention documented in [scope.md](scope.md) / [conventions.md](conventions.md) — target keeps the exact legacy name so existing macros/addons referencing it are unaffected, and focus gets an unambiguous `Focus` suffix rather than a numeric or generic index.
- **`Ka0s_KickCD_GRID_LAYOUT` payload gained `unit`** — additive change within the closed five-message bus, not a new message. See [message-bus.md](message-bus.md#ka0s_kickcd_grid_layout-payload).
- **`IconGrid` / `Castbar` module singleton → per-unit instance manager** (`instances[unit]`) — necessary because the two widgets now each render N independent unit instances (currently target + focus) sharing one module's message registration; a full module-per-unit split was rejected as it would have doubled the TOC surface and the `NS:GetModule("IconGrid", true)` accessor contract other code depends on.
- **`DEFAULT_PROFILE` restructure to `units.*`** (a rename/nest, not a pure addition) — see [saved-variables.md](saved-variables.md#migration-folding-legacy-iconscastbaranchors-into-unitstarget) for the full rationale and the shape-driven migration that makes it safe for existing installs.

Per CLAUDE.md's flag-deviations rule, recorded as **intentional** for the single-text-label feature:

- **`modules/UnitLabel.lua` (a new per-unit instance-manager module) + its `KickCDUnitLabelTarget` / `KickCDUnitLabelFocus` frame names** — a label needed to live in its own module, not stay bolted onto `IconGrid` or `Castbar`, because a unit's label can attach to *either* widget (`label.style.attach`) and must be able to re-anchor if the attach target is torn down/rebuilt; see [conventions.md](conventions.md#frame-names) for the frame-name-pattern rationale (including why the holder is created on `UIParent` but reparented onto the icon grid — not the attach widget — on every `Apply`, so it follows the grid's General-visibility show/hide + alpha rather than being cast-gated when attached to the cast bar).
- **`units.<unit>.label.style` DB sub-shape + the dedicated `Database:BackfillLabelStyle` migration** — see [saved-variables.md](saved-variables.md#unitsunitlabelstyle-shape) for the full rationale.
- **The `alwaysPerUnit` schema-row flag** (`settings/Panel_Render.lua`'s `Helpers.PartitionUnitRows`) — added so a linked Focus's appearance rows could stay hidden/mirrored while its label `show`/`text` (per-unit identity data, like `label.text` always was) stayed editable. A follow-up dropped `alwaysPerUnit` from the two Label rows so a linked Focus's Text Label page collapses to just the "Linked to Target" note, matching Icons/Cast bar; `show`/`text` are still per-unit in the DB, just not editable on the page while linked. The flag/mechanism remains as generic infra in `PartitionUnitRows` for any future row that needs the exception — no schema row currently sets it.
- **The new `label` settings panel/section** (`settings/Label.lua`, `NS.Settings.order` after `castbar`) — the identity label graduated from a couple of General rows to its own full placement/orientation/font schema (`attach`, anchor points, offsets, justify, rotation, font/size/flags), which no longer fit General's "master controls" scope; a dedicated per-unit panel (mirroring Icons/Cast bar's `Helpers.RenderUnitPanel` pattern) was the natural home once the label grew a real appearance surface.
