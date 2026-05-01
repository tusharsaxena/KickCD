# Module map

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
│   ├── Util.lua      — color, anchor, Throttle/Debounce, DeepCopy,
│                       NormalizeSpecToken/NormalizeClassToken, chat print
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
                        renderer + ValidateSchema + Helpers.Throttle wrapper
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

External dependencies (vendored under `libs/`): LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0, AceGUI-3.0, LibSharedMedia-3.0, LibCustomGlow-1.0. Several additional Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab, AceTimer) are also under `libs/` because they ship as part of the standard Ace3 distribution but are not loaded by the TOC — only the libraries listed in `KickCD.toc` are pulled in at runtime.

Display name in the addon list and the Settings panel: `Ka0s KickCD` (the `## Title` colored field in `KickCD.toc`). The folder, addon ID, saved-variable namespace (`KickCDDB`), slash commands, and global frame names all stay unprefixed `KickCD` for ergonomics.
