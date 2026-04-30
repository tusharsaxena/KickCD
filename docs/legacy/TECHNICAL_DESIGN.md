# Ka0s KickCD — Technical Design

**Version:** 0.1 (draft, awaiting sign-off)
**Companion docs:** [REQUIREMENTS.md](REQUIREMENTS.md), [RESEARCH.md](RESEARCH.md)
**Target:** WoW Midnight 12.0.5 (Interface 120005)

---

## 1. Architecture overview

KickCD is an Ace3-based addon split into **three layers**:

```
              ┌─────────────────────────────────────────────┐
              │                Settings Layer                │
              │   (Blizzard Settings panel + AceDBOptions)   │
              └──────────────────────┬──────────────────────┘
                                     │ writes/reads profile
                                     ▼
              ┌─────────────────────────────────────────────┐
              │                  Data Layer                  │
              │     AceDB profile · defaults · migrations    │
              └──────────────────────┬──────────────────────┘
                                     │ reads on init/profile-change
                                     ▼
              ┌─────────────────────────────────────────────┐
              │               Runtime / UI Layer             │
              │  Tracker · Cooldowns · IconGrid · Castbar    │
              └─────────────────────────────────────────────┘
```

**Communication:** loose, message-based. Modules talk via Ace3 `AceEvent-3.0`
internal messages (`SendMessage` / `RegisterMessage`), never via direct cross-
module function calls. This keeps modules independently testable and lets the
settings UI swap configs live without poking module internals.

### Internal messages

| Message | Sender | Payload | Subscribers |
| --- | --- | --- | --- |
| `KickCD_TARGET_CAST_START`    | Tracker   | `{ spellID, name, texture, startMS, endMS, isChannel, notInterruptible }` | IconGrid, Castbar |
| `KickCD_TARGET_CAST_UPDATE`   | Tracker   | `{ startMS, endMS, notInterruptible }` (delays, channel ticks, shield changes) | Castbar |
| `KickCD_TARGET_CAST_END`      | Tracker   | `{ reason: "completed" \| "stopped" \| "interrupted" \| "no-target" \| "not-hostile" }` | IconGrid, Castbar |
| `KickCD_SPELL_STATE`          | Cooldowns | `{ spellID, ready, start, duration, charges }` | IconGrid |
| `KickCD_PROFILE_CHANGED`      | Database  | `{ newProfileKey }` | Tracker, IconGrid, Castbar, Settings |
| `KickCD_CONFIG_CHANGED`       | Settings  | `{ section: "icons" \| "castbar" \| "general" \| "spells" }` | IconGrid, Castbar, Tracker |
| `KickCD_TEST_MODE`            | TestMode  | `{ enabled: bool }` | IconGrid, Castbar |

This list is **closed** for v0.1 — new messages require a design update.

---

## 2. File layout

The repo root is the addon folder (per user's instruction "build the addon
inside this folder itself as root folder"). The TOC sits at the root.

```
KickCD/                                    ← repo root = AddOn folder
├── KickCD.toc                             ← single TOC for Midnight 12.0.5
├── LICENSE                                ← MIT
├── docs/
│   ├── RESEARCH.md
│   ├── REQUIREMENTS.md
│   ├── TECHNICAL_DESIGN.md                ← this file
│   ├── EXECUTION_PLAN.md
│   └── UAT.md
├── libs/                                  ← embedded Ace3 + LibSharedMedia
│   ├── LibStub/LibStub.lua
│   ├── CallbackHandler-1.0/CallbackHandler-1.0.lua
│   ├── AceAddon-3.0/AceAddon-3.0.lua
│   ├── AceEvent-3.0/AceEvent-3.0.lua
│   ├── AceDB-3.0/AceDB-3.0.lua
│   ├── AceDBOptions-3.0/AceDBOptions-3.0.lua
│   ├── AceConsole-3.0/AceConsole-3.0.lua
│   ├── AceGUI-3.0/                         ← used only for Spells editor rows
│   └── LibSharedMedia-3.0/LibSharedMedia-3.0.lua
├── locales/
│   └── enUS.lua                            ← L["..."] = "..." table
├── core/
│   ├── KickCD.lua                          ← AceAddon bootstrap, slash commands
│   ├── Database.lua                        ← AceDB defaults, migrations
│   ├── Compat.lua                          ← API shims (C_Spell, Settings)
│   └── Util.lua                            ← color/format/anchor helpers
├── modules/
│   ├── Tracker.lua                         ← target+cast state machine
│   ├── Cooldowns.lua                       ← per-spell cooldown observer
│   ├── IconGrid.lua                        ← icon container + per-icon widget
│   ├── Castbar.lua                         ← target castbar
│   └── TestMode.lua                        ← fake cast loop
├── settings/
│   ├── Panel.lua                           ← Settings.RegisterAddOnCategory entry
│   ├── General.lua
│   ├── Icons.lua
│   ├── Castbar.lua
│   ├── Spells.lua                          ← spell-list editor (AceGUI rows)
│   └── Profiles.lua                        ← AceDBOptions wrapper
├── defaults/
│   └── Spells.lua                          ← per-class+spec spellID lists
└── media/
    ├── icon.tga                            ← addon icon (64x64)
    ├── statusbar-flat.tga                  ← default castbar texture
    └── README.txt                          ← media licensing notes
```

### Load order (`KickCD.toc`)

```toc
## Interface: 120005
## Title: Ka0s |cff00ff00KickCD|r
## Notes: Tracks interrupt + CC cooldowns and shows a target castbar.
## Author: Ka0s
## Version: 0.1.0
## IconTexture: Interface\AddOns\KickCD\media\icon
## SavedVariables: KickCDDB
## DefaultState: enabled
## Category-enUS: Combat
## X-License: MIT

# Libraries (must load first)
libs\LibStub\LibStub.lua
libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
libs\AceAddon-3.0\AceAddon-3.0.lua
libs\AceEvent-3.0\AceEvent-3.0.lua
libs\AceDB-3.0\AceDB-3.0.lua
libs\AceDBOptions-3.0\AceDBOptions-3.0.lua
libs\AceConsole-3.0\AceConsole-3.0.lua
libs\AceGUI-3.0\AceGUI-3.0.xml
libs\LibSharedMedia-3.0\lib.xml

# Locales
locales\enUS.lua

# Core
core\Compat.lua
core\Util.lua
core\Database.lua
core\KickCD.lua

# Defaults
defaults\Spells.lua

# Modules
modules\Tracker.lua
modules\Cooldowns.lua
modules\IconGrid.lua
modules\Castbar.lua
modules\TestMode.lua

# Settings (last — depend on everything else being initialized)
settings\Panel.lua
settings\General.lua
settings\Icons.lua
settings\Castbar.lua
settings\Spells.lua
settings\Profiles.lua
```

Note `KickCDDB` is the only SavedVariable — Ace3 AceDB handles per-character /
per-class scoping inside it via profile keys.

---

## 3. Module specs

Each `module` is a regular Lua file that registers a sub-module on the main
AceAddon object:

```lua
-- modules/Tracker.lua
local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local Tracker = KickCD:NewModule("Tracker", "AceEvent-3.0")
```

This gives every module `RegisterEvent`, `RegisterMessage`, `SendMessage`,
`UnregisterEvent` for free.

### 3.1 `core/KickCD.lua` — bootstrap

Responsibilities:
- Create the AceAddon (`LibStub("AceAddon-3.0"):NewAddon("KickCD", "AceConsole-3.0", "AceEvent-3.0")`).
- `OnInitialize()` — call `Database:Init()`, register `/kickcd`, `/kcd` slash commands.
- `OnEnable()` — start all modules. Modules are auto-enabled by Ace3 unless they opt out.
- Provide `KickCD:OpenSettings()` — opens the Blizzard Settings panel to the KickCD category.

### 3.2 `core/Database.lua` — AceDB + migrations

Responsibilities:
- Build the `defaults` table for AceDB (see §4 schema).
- Initialize `KickCD.db = LibStub("AceDB-3.0"):New("KickCDDB", defaults, true)`.
  The `true` makes per-character the default scope on first login (FR-10.2).
- Wire profile callbacks:
  ```lua
  self.db.RegisterCallback(self, "OnProfileChanged",  "OnProfileChanged")
  self.db.RegisterCallback(self, "OnProfileCopied",   "OnProfileChanged")
  self.db.RegisterCallback(self, "OnProfileReset",    "OnProfileChanged")
  ```
  `OnProfileChanged` fires `KickCD_PROFILE_CHANGED`.
- Run migrations against `db.global.dbVersion`. Migration table:
  ```lua
  local Migrations = {
      [1] = function(db) end,   -- initial — no-op
      -- [2] = function(db) ... end, -- future
  }
  ```

### 3.3 `core/Compat.lua` — API shims

Wraps APIs whose signatures may shift between Midnight minor patches:

```lua
KickCD.Compat = {
    GetSpellCooldown = function(spellID)
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            return info.startTime, info.duration, info.isEnabled, info.modRate
        end
        return 0, 0, false, 1
    end,
    GetSpellTexture = function(spellID)
        return C_Spell.GetSpellTexture(spellID)
    end,
    GetSpellInfo = function(spellID)
        local i = C_Spell.GetSpellInfo(spellID)
        if i then return i.name, i.iconID, i.castTime, i.minRange, i.maxRange, i.spellID end
    end,
    GetSpellCharges = function(spellID)
        local c = C_Spell.GetSpellCharges(spellID)
        if c then return c.currentCharges, c.maxCharges, c.cooldownStartTime, c.cooldownDuration end
    end,
    IsSpellUsable = function(spellID)
        if C_Spell.IsSpellUsable then
            return C_Spell.IsSpellUsable(spellID)
        end
        return IsUsableSpell(spellID)
    end,
}
```

### 3.4 `modules/Tracker.lua` — target/cast state machine

The single source of truth for "should the UI be visible right now?". States:

```
        ┌──────────┐  PLAYER_TARGET_CHANGED            ┌─────────────┐
        │  Hidden  │ ──────────────────────────────▶  │ Evaluating  │
        └──────────┘                                   └──────┬──────┘
              ▲                                               │
              │ no-target                                     │ valid hostile + interruptible cast
              │ not-hostile                                   ▼
              │ cast-stopped                            ┌──────────┐
              └──────────────────────────────────────── │  Showing │
                          target/cast events            └──────────┘
```

Events listened to (all via `RegisterUnitEvent("...","target")` where possible):
- `PLAYER_TARGET_CHANGED` (frame event, no unit filter)
- `UNIT_SPELLCAST_START`, `_STOP`, `_SUCCEEDED`, `_INTERRUPTED`, `_FAILED`
- `UNIT_SPELLCAST_CHANNEL_START`, `_STOP`, `_UPDATE`
- `UNIT_SPELLCAST_DELAYED`
- `UNIT_SPELLCAST_INTERRUPTIBLE`, `_NOT_INTERRUPTIBLE`
- `UNIT_SPELLCAST_EMPOWER_START`, `_STOP` (we treat empowered as a cast for v0.1)
- `UNIT_FACTION` (target reaction may flip — re-evaluate)

Re-evaluation function:
```lua
function Tracker:Evaluate()
    if not (UnitExists("target")
            and not UnitIsDead("target")
            and UnitCanAttack("player","target")) then
        return self:Hide("not-hostile")
    end
    local cast = self:GetCast("target")
    if not cast or cast.notInterruptible then
        return self:Hide(cast and "shielded" or "no-cast")
    end
    self:Show(cast)
end
```

Throttling: `_DELAYED` events fire often; they only trigger `KickCD_TARGET_CAST_UPDATE`,
not a full re-evaluate. The castbar interpolates progress via OnUpdate; pushback
just rewrites endMS.

### 3.5 `modules/Cooldowns.lua` — per-spell observer

Owns a table of "watched" spellIDs, derived from the active spec's spell list.

```lua
Cooldowns.watched = {
    [183752] = { ready = true, start = 0, duration = 0, charges = nil },
    [217832] = { ... },
}
```

Events:
- `SPELL_UPDATE_COOLDOWN`
- `SPELL_UPDATE_USABLE`
- `SPELL_UPDATE_CHARGES`
- `PLAYER_ENTERING_WORLD`
- `PLAYER_SPECIALIZATION_CHANGED`
- `KickCD_PROFILE_CHANGED` (rebuild watched list)
- `KickCD_CONFIG_CHANGED` if section == "spells" (rebuild watched list)

On any of these, refresh state for all watched spells and `SendMessage("KickCD_SPELL_STATE", ...)` for each one whose state changed (compare against the cached previous state to avoid spamming).

`SPELL_UPDATE_COOLDOWN` fires globally with no payload — we have to re-poll
each watched spell. With ~6 spells per spec, this is trivial (~6 Lua function
calls per event).

### 3.6 `modules/IconGrid.lua` — UI

Owns one parent frame (`KickCDIconGrid`) and N child icon widgets. Each icon is
created once and pooled — reused when the spell list changes.

Per-icon widget structure:
```
Icon (Button, parent)
├── icon texture           (SetTexture from C_Spell.GetSpellTexture)
├── cooldown swipe         (CooldownFrameTemplate, SetCooldown(start, duration))
├── cooldown text          (FontString — optional, FR-2.6)
├── charges badge          (FontString — corner)
└── highlight overlay      (texture, hidden by default — for "ready" pulse animation, stretch goal)
```

State application:
```lua
function Icon:Apply(state)   -- state from KickCD_SPELL_STATE
    if state.ready then
        self.icon:SetVertexColor(1, 1, 1)
        self:SetAlpha(self.cfg.readyAlpha or 1.0)
        self.cooldown:Hide()
    else
        self.icon:SetVertexColor(unpack(self.cfg.cooldownTint or {1, 0.4, 0.4}))
        self:SetAlpha(self.cfg.cooldownAlpha or 0.4)
        self.cooldown:SetCooldown(state.start, state.duration)
        self.cooldown:Show()
    end
    if state.charges and state.charges > 0 then
        self.chargesText:SetText(state.charges); self.chargesText:Show()
    else
        self.chargesText:Hide()
    end
end
```

Show/hide/relayout triggered by:
- `KickCD_TARGET_CAST_START` → show grid, build icons from active spec list, attach Cooldowns state
- `KickCD_TARGET_CAST_END` → hide grid
- `KickCD_SPELL_STATE` → update one icon
- `KickCD_CONFIG_CHANGED` (section == "icons" or "spells") → re-layout

Layout algorithm: primary icon at anchor; secondary icons spread out in
configured direction (default: right, horizontal) with configured gap.

### 3.7 `modules/Castbar.lua` — UI

Single `StatusBar` with:
- spell-icon texture on left
- spell-name FontString centered
- time-remaining FontString right
- spark texture indicating fill position
- border + background

OnUpdate handler runs only while shown. Computes:
```lua
local now = GetTime()
local elapsed = now - self.startMS
local pct = elapsed / (self.endMS - self.startMS)
if self.isChannel then pct = 1 - pct end
self.bar:SetValue(pct)
```

Subscribes to:
- `KickCD_TARGET_CAST_START` → show, set name/icon/duration, start OnUpdate
- `KickCD_TARGET_CAST_UPDATE` → adjust endMS (handles _DELAYED + channel haste)
- `KickCD_TARGET_CAST_END` → hide, stop OnUpdate
- `KickCD_CONFIG_CHANGED` (section == "castbar") → restyle without recreate

### 3.8 `modules/TestMode.lua`

Synthesizes `KickCD_TARGET_CAST_START` / `_END` on a 5-second loop with a fake
spellID. Listens for `PLAYER_REGEN_DISABLED` (combat start) to auto-disable.
Drives the same code paths as a real cast — enables WYSIWYG editing.

---

## 4. SavedVariables schema

Single SavedVariable: `KickCDDB`. AceDB wraps the structure:

```lua
KickCDDB = {
    -- AceDB scaffolding (managed by AceDB-3.0)
    profileKeys     = { ["Player-Realm"] = "Default" },
    profiles        = { ["Default"] = { ...see below... } },
    char            = { ["Player-Realm"] = {} },   -- not used in v0.1
    global          = { dbVersion = 1 },
}
```

### Profile shape (the only thing user-customizable):

```lua
local DEFAULT_PROFILE = {
    enabled  = true,
    locked   = true,
    testMode = false,
    scale    = 1.0,
    alpha    = 1.0,

    icons = {
        primarySize    = 48,
        secondarySize  = 0.7,         -- multiplier of primary
        layout         = "horizontal", -- or "vertical"
        primaryAnchor  = "left",       -- left|right|top|bottom — relative to secondaries
        gap            = 4,
        readyAlpha     = 1.0,
        cooldownAlpha  = 0.4,
        cooldownTint   = { 1, 0.4, 0.4, 1 },
        showCooldownText = false,
        cooldownTextFont = "Friz Quadrata TT",
        cooldownTextSize = 14,
        showCharges    = true,
    },

    castbar = {
        width   = 240,
        height  = 22,
        font    = "Friz Quadrata TT",
        fontSize = 12,
        texture = "Blizzard",          -- LibSharedMedia key
        border  = "None",
        interruptibleColor    = { 1.0, 0.82, 0, 1 },
        notInterruptibleColor = { 0.5, 0.5, 0.5, 1 },
        showSpark = true,
        showIcon  = true,
    },

    anchors = {
        icons   = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 },
        castbar = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 },
    },

    -- spells[CLASS][SPEC] = { { spellID, category, enabled }, ... } in priority order
    spells = {
        DEMONHUNTER = {
            HAVOC = {
                { spellID = 183752, category = "interrupt",     enabled = true },  -- Disrupt
                { spellID = 217832, category = "incapacitate",  enabled = true },  -- Imprison
                { spellID = 207684, category = "fear",          enabled = true },  -- Sigil of Misery
                { spellID = 179057, category = "stun",          enabled = true },  -- Chaos Nova
                { spellID = 198793, category = "movement",      enabled = true },  -- Vengeful Retreat (knockback w/ talent)
            },
            VENGEANCE = { ... },
        },
        MAGE = {
            ARCANE = {
                { spellID = 2139,   category = "interrupt",     enabled = true },  -- Counterspell
                { spellID = 122,    category = "root",          enabled = true },  -- Frost Nova
                { spellID = 31661,  category = "incapacitate",  enabled = true },  -- Dragon's Breath
                { spellID = 113724, category = "root",          enabled = true },  -- Ring of Frost
            },
            FIRE = { ... }, FROST = { ... },
        },
        -- ... full list per RESEARCH.md §6, populated in defaults/Spells.lua
    },
}
```

`spells` defaults are loaded from `defaults/Spells.lua` at file-load time and
merged into the AceDB defaults table — AceDB handles "user customized →
preserve, untouched → upgrade" automatically when defaults change between
addon versions.

### Migrations

`KickCDDB.global.dbVersion` tracks schema version. Migrations run inside
`Database:Init()` after AceDB is created:

```lua
function Database:RunMigrations()
    local current = self.db.global.dbVersion or 0
    for v = current + 1, LATEST_VERSION do
        if Migrations[v] then Migrations[v](self.db) end
        self.db.global.dbVersion = v
    end
end
```

For v0.1, `LATEST_VERSION = 1` and `Migrations[1]` is a no-op (initial state).
The structure is in place for future migrations.

---

## 5. Settings panel design

Implemented in `settings/Panel.lua` using the post-10.0 `Settings` API. Each
subcategory is its own file that builds and registers a `VerticalLayoutSubcategory`.

### 5.1 Category registration

```lua
-- settings/Panel.lua
local mainCategory = Settings.RegisterVerticalLayoutCategory("Ka0s KickCD")
Settings.RegisterAddOnCategory(mainCategory)
KickCD.SettingsCategoryID = mainCategory:GetID()

KickCD.Settings = {
    main = mainCategory,
    sub  = {
        general  = General:Build(mainCategory),
        icons    = Icons:Build(mainCategory),
        castbar  = Castbar:Build(mainCategory),
        spells   = Spells:Build(mainCategory),
        profiles = Profiles:Build(mainCategory),
    },
}
```

### 5.2 Native widget pattern

```lua
local function CreateCheckBox(category, key, label, tooltip, getter, setter)
    local setting = Settings.RegisterAddOnSetting(
        category, "KickCD_" .. key, key, db.profile, "boolean", label, getter())
    Settings.SetOnValueChangedCallback("KickCD_" .. key, function(_, _, value)
        setter(value)
        KickCD:SendMessage("KickCD_CONFIG_CHANGED", { section = sectionFor(key) })
    end)
    Settings.CreateCheckbox(category, setting, tooltip)
    return setting
end
```

The `Compat.lua` shim wraps `Settings.RegisterAddOnSetting` because the
signature has churned (10.0 → 10.2 → 11.0). The shim picks the right form at
runtime.

### 5.3 Spell-list editor (Spells subcategory)

Native `Settings` widgets don't include row editors. We use a hybrid: register
the subcategory as a custom panel via `Settings.RegisterCanvasLayoutSubcategory`
and embed an `AceGUI` container that renders our row UI inside it.

```lua
local sub = Settings.RegisterCanvasLayoutSubcategory(mainCategory, panelFrame, "Spells")
```

Where `panelFrame` is a `Frame` that hosts an AceGUI `ScrollFrame` populated
with one row per tracked spell:

```
[icon] [name + ID] [enabled toggle] [category dropdown] [▲] [▼] [✕]
```

Top of panel:
- Class/spec selector (defaults to active class+spec)
- "Add spell..." button → modal with EditBox for name or ID
- "Reset to defaults" button (with `StaticPopupDialogs` confirmation)

State writes go through a debounced setter (50 ms) that updates
`db.profile.spells[CLASS][SPEC]` and fires `KickCD_CONFIG_CHANGED`.

### 5.4 Profiles subcategory

Pure AceDBOptions:

```lua
-- settings/Profiles.lua
local options = LibStub("AceDBOptions-3.0"):GetOptionsTable(KickCD.db)
-- AceDBOptions returns an AceConfig-style table; we render it via AceConfigDialog
LibStub("AceConfig-3.0"):RegisterOptionsTable("KickCD-Profiles", options)
local panel = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("KickCD-Profiles", "Profiles", "Ka0s KickCD")
```

This adds a `AceConfig`-3.0 / `AceConfigDialog`-3.0 dependency to libs/. Worth
it for the full profile UX (create/copy/switch/reset/delete + scope dropdowns)
that AceDBOptions delivers for free.

### 5.5 Slash commands

```lua
-- core/KickCD.lua
KickCD:RegisterChatCommand("kickcd", "OpenSettings")
KickCD:RegisterChatCommand("kcd",    "OpenSettings")

function KickCD:OpenSettings()
    Settings.OpenToCategory(self.SettingsCategoryID)
end
```

---

## 6. Default spell sets — strategy

`defaults/Spells.lua` exports a single table covering every class+spec.
Sourced from RESEARCH.md §6.1–6.3, biased toward PvE per FR-5.1.

For each class+spec, the list is **ordered by priority**:
1. Primary interrupt (always index 1)
2. Hard CCs that reliably stop a cast (stuns)
3. Knockbacks (can stop a cast via positional displacement)
4. Incapacitates / silences
5. Race-specific cast-stoppers (appended at runtime if the player's race matches)

Race-specific append logic (in `Database:BuildSpells()`):

```lua
local racialCastStoppers = {
    Tauren           = 20549,   -- War Stomp (stun)
    HighmountainTauren = 255654,-- Bull Rush
    Pandaren         = 107079,  -- Quaking Palm
    KulTiran         = 287712,  -- Haymaker
    Nightborne       = 260364,  -- Arcane Pulse
}
local _, race = UnitRace("player")
local id = racialCastStoppers[race]
if id then
    table.insert(profileSpells[class][spec], { spellID = id, category = "racial", enabled = true })
end
```

This append happens **only on first profile creation** — subsequent edits are
preserved.

The final defaults file is large (~13 classes × 3 specs × 4–6 spells). Layout:

```lua
-- defaults/Spells.lua
KickCD.DefaultSpells = {
    DEMONHUNTER = {
        HAVOC     = { {183752,"interrupt"}, {217832,"incapacitate"}, {179057,"stun"}, {207684,"fear"} },
        VENGEANCE = { {183752,"interrupt"}, {217832,"incapacitate"}, {179057,"stun"} },
    },
    DEATHKNIGHT = {
        BLOOD = { {47528,"interrupt"}, {221562,"stun"}, {108199,"grip"} },  -- Asphyxiate (Blood)
        FROST = { {47528,"interrupt"}, {108194,"stun"}, {207167,"incapacitate"} }, -- Asphyxiate (Frost)
        UNHOLY= { {47528,"interrupt"}, {108194,"stun"}, {207167,"incapacitate"} },
    },
    -- ... etc. spec-level entries are short tables of {id, category} pairs
}
```

The DK Asphyxiate spec-split (R-5 in REQUIREMENTS) is handled here: each spec
lists the spec-correct spellID.

---

## 7. Performance + correctness

### 7.1 Event filtering

All `UNIT_SPELLCAST_*` events use `RegisterUnitEvent("...","target")` so the
client only delivers events for the player's current target. Ace3
`AceEvent-3.0` only supports broadcast `RegisterEvent`, so Tracker creates a
**dedicated raw frame** for unit-filtered events:

```lua
function Tracker:OnEnable()
    self.castFrame = CreateFrame("Frame")
    for _, ev in ipairs(UNIT_CAST_EVENTS) do
        self.castFrame:RegisterUnitEvent(ev, "target")
    end
    self.castFrame:SetScript("OnEvent", function(_, event, ...) self:OnCastEvent(event, ...) end)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "Evaluate")
    self:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
end
```

### 7.2 OnUpdate scoping

Castbar's OnUpdate is `:SetScript("OnUpdate", ...)` only when shown, and
`:SetScript("OnUpdate", nil)` on hide. No idle work.

### 7.3 Cooldown polling cost

`SPELL_UPDATE_COOLDOWN` fires multiple times per second under heavy combat. We
re-poll all watched spells (typically 4–6) on each — that's ~30 function calls/s
worst case, well under any concern threshold.

### 7.4 Taint avoidance

No secure templates, no `SecureActionButton`, no manipulating action bars or
unit frames. `UIParent` is the only secure parent we touch (as a positioning
anchor).

### 7.5 Memory

- Icon widgets pooled (created once, reused).
- Castbar is a single instance.
- No anonymous closures inside hot paths (OnUpdate, OnEvent) — bind methods up-front.

---

## 8. Testing strategy

Manual UAT lives in `UAT.md`. Automated testing in WoW addons is impractical
(no headless client). Pre-release sanity: load the addon in the live client
and run through:

1. **/run** debug helpers shipped under `/kickcd debug` slash subcommand:
   - `/kickcd debug spells` — prints active spell list and current cooldown state
   - `/kickcd debug target` — prints what Tracker sees for the current target
   - `/kickcd debug fire <event>` — synthesizes an internal message
2. Event log toggle: `/kickcd debug log` prints every internal message to chat.
3. Test mode (FR-9) for visual layout work without a target.

These are dev-only; they don't appear in the Settings panel.

---

## 9. Open technical questions

| ID | Question | Default position | Decide by |
| --- | --- | --- | --- |
| Q-1 | Use `AceConfig`+`AceConfigDialog` for the Profiles tab, or hand-roll? | Use AceConfig (1 small dep, full UX) | Before code starts |
| Q-2 | Spells editor: AceGUI rows or pure native frames? | AceGUI rows (faster to build) | Before code starts |
| Q-3 | Should `KickCD_TARGET_CAST_END` distinguish "interrupted by player" specifically? | No — user can read combat log; v0.1 doesn't need this | Before code starts |
| Q-4 | If spec-locked spells are present in another spec's default list, hide or gray out? | Hide (FR-2.8) | Decided |
| Q-5 | Do we ship a tiny built-in icon, or rely on default Blizzard icon? | Ship `media/icon.tga` (placeholder OK) | Decided |

---

## 10. Sign-off

**Status:** ⏳ Awaiting user sign-off

Reply with:
- ✅ "Approved — proceed to EXECUTION_PLAN"
- 🔧 "Changes needed: ..." (with specifics)
