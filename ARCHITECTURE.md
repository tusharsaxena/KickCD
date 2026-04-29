# Architecture

Reference document for KickCD's current shape (post-cast-bar-removal, 12.0-aware). This reflects the codebase as of commit `59fb5c0` and supersedes the design discussion in `docs/TECHNICAL_DESIGN.md` where the two diverge.

## Purpose

Track the player's interrupt and CC cooldowns and surface them on a movable icon grid. The grid is always visible; an interrupt rotation helper, not a target-cast tracker.

## Module map

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
│   ├── Cooldowns.lua — polls C_Spell.GetSpellCooldown, emits KickCD_SPELL_STATE
│   └── IconGrid.lua  — owns KickCDIconGrid frame and pooled icon widgets
└── settings/
    ├── Panel.lua     — top-level category + per-tab builder mailbox + widget helpers
    ├── General.lua   — enable / lock / scale / alpha / reset position
    ├── Icons.lua     — icon grid sizing, colors, layout
    ├── Spells.lua    — per-class+spec spell editor
    └── Profiles.lua  — AceDBOptions profile UI (AceConfig)
```

External dependencies (vendored under `libs/`): LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0, AceGUI-3.0, LibSharedMedia-3.0.

## Boot sequence

1. **TOC file-load (`KickCD.toc`):** libs → locales → `core/Compat.lua` (creates `_G.KickCD` table and `KickCD.Compat`) → `core/Util.lua` → `core/Database.lua` (defines class, doesn't init) → `core/KickCD.lua` (`AceAddon-3.0:NewAddon` promotes `_G.KickCD` in place to an AceAddon object) → `defaults/Spells.lua` (sets `KickCD.DefaultSpells`) → modules (each calls `KickCD:NewModule`) → settings (each calls `KickCD.Settings.RegisterTab`).

2. **`KickCD:OnInitialize` (Ace lifecycle, fires on `ADDON_LOADED`):** `Database:Init` builds the AceDB instance, runs forward-only migrations (`global.dbVersion`), and seeds spells from `KickCD.DefaultSpells` on first profile creation. Slash commands `/kickcd` and `/kcd` are registered.

3. **`<Module>:OnEnable`:** modules subscribe to messages and game events. `Cooldowns:OnEnable` registers `SPELL_UPDATE_COOLDOWN/USABLE/CHARGES` + `PLAYER_ENTERING_WORLD` + `PLAYER_SPECIALIZATION_CHANGED`; `IconGrid:OnEnable` builds the frame, runs `BuildActiveList`, and shows the grid.

4. **`PLAYER_LOGIN` (deferred from `settings/Panel.lua`):** the Blizzard Settings category is registered and per-tab builders run. Late-loading tabs auto-register if the main category already exists.

## Data flow

```
Game event (SPELL_UPDATE_COOLDOWN, ...)
        │
        ▼
Cooldowns:Refresh ──► PollSpell(spellID) ──► Compat.GetSpellCooldown / IsSpellUsable / GetSpellCharges
        │                                          │
        │                                          ▼
        │                                  { start, duration, isActive, charges }
        │                                  (start/duration may be "secret values")
        ▼
StateChanged(prev, next) ── true ──► SendMessage("KickCD_SPELL_STATE", payload)
                                                          │
                                                          ▼
                                          IconGrid:OnSpellState ──► btn:Apply(state)
                                                                          │
                                                                          ▼
                                                         desaturate / SetCooldown (gated by issecretvalue)
```

User input (drag, settings panel, slash command) writes to `db.profile` and fires `KickCD_CONFIG_CHANGED` (or `KickCD_PROFILE_CHANGED` from AceDB callbacks). IconGrid handles each section appropriately.

## Closed message contract

Internal messages travel over AceEvent's per-addon bus (`KickCD:SendMessage` / `:RegisterMessage`). The full set:

| Message | Sender | Listeners | Payload | Notes |
|---|---|---|---|---|
| `KickCD_SPELL_STATE` | `Cooldowns:Rebuild` / `Refresh` | `IconGrid` | `{ spellID, ready, isActive, start, duration, charges }` | `start`/`duration`/`charges` may be secret |
| `KickCD_CONFIG_CHANGED` | `settings/Panel.lua Helpers.Set`, `core/KickCD.lua` (lock/unlock) | `IconGrid`, `Cooldowns` | `{ section = "general"\|"icons"\|"spells" }` | section-keyed for cheap dispatch |
| `KickCD_PROFILE_CHANGED` | `Database:OnProfileChanged` (AceDB callback) | `IconGrid`, `Cooldowns` | `{ newProfileKey }` | fires for `OnProfileChanged` / `Copied` / `Reset` |

The set is closed by convention — module headers and `CLAUDE.md` reference this list. Adding a message means updating both the source emitter, every consumer, and this table.

## Saved variables

Single saved-variable: `KickCDDB`, an AceDB-3.0 store. Default scope is per-character (the `true` arg in `AceDB:New`); the user can switch to default / per-class / per-realm via the Profiles tab.

Profile shape (see `core/Database.lua`):

```lua
{
    enabled = true,
    locked  = true,           -- icon grid drag lock
    scale   = 1.0,            -- master scale
    alpha   = 1.0,            -- master alpha

    icons = {
        primarySize, secondarySize, layout, primaryAnchor, gap,
        readyAlpha, cooldownAlpha, cooldownTint,
        showCooldownText, cooldownTextFont, cooldownTextSize,
        showCharges,
    },
    anchors = {
        icons = { point, relativePoint, x, y },   -- always relative to UIParent
    },
    spells = {
        [CLASS] = {
            [SPEC] = {
                { spellID, category, enabled }, ...
            },
        },
    },
}

global = { dbVersion = N }    -- migration cursor, see Database.RunMigrations
```

`spells` is seeded once on first profile creation by `Database:BuildSpells`, which deep-copies `KickCD.DefaultSpells` and appends the player's racial cast-stopper. Subsequent edits are user-owned; the seeder is idempotent on populated profiles.

## Compat layer

Spell APIs and the Settings registration API have churned across recent expansions. `core/Compat.lua` provides a stable surface:

| Compat function | Wraps | 12.0 caveats |
|---|---|---|
| `Compat.GetSpellCooldown(id)` | `C_Spell.GetSpellCooldown` (table) → `_G.GetSpellCooldown` (tuple) | Returns `(start, duration, isEnabled, modRate, isActive)`; `start`/`duration`/`modRate` may be secret. Use `isActive` (plain) for "is on cooldown" decisions. |
| `Compat.GetSpellInfo(id)` | `C_Spell.GetSpellInfo` (table) → `_G.GetSpellInfo` (tuple) | — |
| `Compat.GetSpellTexture(id)` | `C_Spell.GetSpellTexture` → `_G.GetSpellTexture` | Texture may be secret on guarded spells; gate with `issecretvalue` before `SetTexture`. |
| `Compat.GetSpellCharges(id)` | `C_Spell.GetSpellCharges` (table) → `_G.GetSpellCharges` (tuple) | Charges may be secret on guarded spells. |
| `Compat.IsSpellUsable(id)` | `C_Spell.IsSpellUsable` → `_G.IsUsableSpell` | Returns `(usable, noMana)` regardless of underlying shape. |
| `Compat.RegisterAddOnSetting(...)` | `Settings.RegisterAddOnSetting` | Tries the 12.0+ `(category, variable, variableKey, variableTbl, varType, default)` shape first; falls back through 11.0 / 10.2 / 10.0 shapes via `pcall`. |

Modules call into `Compat.*` exclusively; direct calls to `C_Spell.*` or `_G.GetSpell*` outside `Compat.lua` are a smell.

## Lock and anchor

The icon grid has a single anchor (`db.profile.anchors.icons`), always relative to UIParent. `Util.SaveAnchor(frame)` snapshots `{ point, relativePoint, x, y }`; `Util.ApplyAnchor(frame, anchor)` restores it.

Lock state lives in `db.profile.locked`. `IconGrid:ApplyLock` flips `EnableMouse(true/false)` + `RegisterForDrag("LeftButton" or nothing)`. Touch points:

- Settings → General → "Lock frame" checkbox writes `db.profile.locked` and fires `KickCD_CONFIG_CHANGED { section = "general" }`.
- Slash commands `/kcd lock | unlock | toggle` do the same write + fire (see `core/KickCD.lua`).
- `IconGrid:OnConfigChanged` reacts to section `"general"` by calling `ApplyLock`.

## Slash dispatch

Two ordered tables in `core/KickCD.lua` (`COMMANDS` for top-level, `DEBUG_COMMANDS` for `/kcd debug ...`). Each row is `{name, description, fn}`. The dispatcher:

- Bare `/kcd` → `printHelp` (iterates `COMMANDS`).
- `/kcd <known>` → executes that row's `fn`.
- `/kcd debug` → `printDebugHelp` (iterates `DEBUG_COMMANDS`).
- `/kcd debug <known>` → executes that row's `fn`.
- `/kcd <unknown>` → "unknown command" + help.
- `/kcd options` is aliased to `/kcd config` for backward compat.

Adding a command is a one-row append; help text is generated from the same rows that drive dispatch.

## Conventions

- Saved-variable boundary lives in `core/Database.lua`; modules read/write `KickCD.db.profile` directly but treat the schema as defined there.
- Anchor format is fixed: `{ point, relativePoint, x, y }` relative to UIParent. No `relativeTo` frame references.
- Internal communication is via the closed message set; modules do not call each other directly across boundaries.
- Module files are header-commented with their job and message contract; keep both in sync with the code.
- 12.0 secret values: rule of thumb is "operate on `isActive` / `isEnabled` for decisions; pass `start` / `duration` opaquely or gate with `issecretvalue`." See `CLAUDE.md` for the full pattern catalogue.
