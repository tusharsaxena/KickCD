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
│   └── IconGrid.lua  — owns KickCDIconGrid frame and pooled icon widgets; runs alpha/tint curves C-side
└── settings/
    ├── Panel.lua     — top-level category + canvas-panel framework + schema renderer
    ├── General.lua   — schema rows for enable/lock/scale/alpha/debugLog + Reset position button
    ├── Icons.lua     — schema rows for icon grid sizing, colors, layout
    ├── Spells.lua    — unified header + AceGUI per-class+spec spell editor
    └── Profiles.lua  — unified header + AceDBOptions UI (AceConfig in a SimpleGroup)
```

External dependencies (vendored under `libs/`): LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0, AceGUI-3.0, LibSharedMedia-3.0.
