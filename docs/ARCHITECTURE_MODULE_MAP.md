# Module map

```
KickCD (AceAddon)
├── core/
│   ├── Compat.lua    — API shims for spell + settings APIs across 10.0–12.0
│   ├── Util.lua      — color, anchor, debounce, chat helpers
│   ├── Database.lua  — AceDB instance + DEFAULT_PROFILE + spell-defaults merge
│   └── KickCD.lua    — AceAddon bootstrap + slash dispatch
├── defaults/
│   └── Spells.lua    — per-class+spec default interrupt lists (KickCD.DefaultSpells)
├── modules/
│   ├── Cooldowns.lua — polls Compat.GetSpellCooldown + GetSpellCooldownDuration, emits KickCD_SPELL_STATE
│   ├── IconGrid.lua  — owns KickCDIconGrid frame and pooled icon widgets; runs alpha/tint/GCD-suppress curves C-side; emits KickCD_GRID_LAYOUT
│   └── Castbar.lua   — owns KickCDCastbar frame (stacked dual StatusBars + per-state borders + spark); secret-value-gated UnitCastingDuration / UnitChannelDuration consumer
└── settings/
    ├── Panel.lua     — top-level category + canvas-panel framework + schema renderer
    ├── General.lua   — schema rows for enable/lock/visibility/scale/alpha/debugLog + Reset position + Reset all buttons
    ├── Icons.lua     — schema rows for icon grid sizing, colors, layout, glow
    ├── Castbar.lua   — schema rows for cast bar enable/anchor/orientation/sizing/text/per-state appearance
    ├── Spells.lua    — unified header + AceGUI per-class+spec spell editor (with Cooldown Manager validation)
    └── Profiles.lua  — unified header + AceDBOptions UI (AceConfig in a SimpleGroup)
```

External dependencies (vendored under `libs/`): LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0, AceGUI-3.0, LibSharedMedia-3.0, LibCustomGlow-1.0. Several additional Ace modules (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab, AceTimer) are also under `libs/` because they ship as part of the standard Ace3 distribution but are not loaded by the TOC — only the libraries listed in `KickCD.toc` are pulled in at runtime.

Display name in the addon list and the Settings panel: `Ka0s KickCD` (the `## Title` colored field in `KickCD.toc`). The folder, addon ID, saved-variable namespace (`KickCDDB`), slash commands, and global frame names all stay unprefixed `KickCD` for ergonomics.

