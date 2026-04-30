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
Cooldowns:Refresh ──► PollSpell(spellID) ──► Compat.GetSpellCooldown          (isActive, plain bool)
        │                                    Compat.GetSpellCooldownDuration  (cdObject, secret-aware)
        │                                    Compat.IsSpellUsable / GetSpellCharges
        │                                          │
        │                                          ▼
        │                                  { ready, isActive, cdObject, charges }
        │                                  (cdObject:GetRemainingDuration is secret in combat)
        ▼
StateChanged(prev, next) ── true ──► SendMessage("KickCD_SPELL_STATE", payload)
                                                          │
                                                          ▼
                                          IconGrid:OnSpellState ──► btn:Apply(state)
                                                                          │
                                                                          ▼
                                          alphaCurve / tintCurve evaluated C-side → SetAlphaFromBoolean / SetVertexColor
                                          cdObject → SetCooldownFromDurationObject (swipe)
                                          cdObject:GetRemainingDuration → SetFormattedText (countdown)
```

The GCD-vs-real-CD visual decision is made entirely C-side via `cdObject:EvaluateRemainingDuration(curve)`. The IconGrid maintains step-shaped alpha and color curves built from `cfg.readyAlpha` / `cfg.cooldownAlpha` / `cfg.cooldownTint`: remaining ≤ ~1.6s evaluates to ready visuals, anything beyond evaluates to cooldown visuals. Lua never compares the secret remaining time directly. See `modules/IconGrid.lua` `BuildCurves`.

User input (drag, settings panel widget, slash command) flows through
`Helpers.Set(path, section, value)` in `settings/Panel.lua`, which
writes `db.profile.<path>` and fires
`KickCD_CONFIG_CHANGED { section = ... }`. IconGrid handles each section
appropriately. AceDB callbacks fire `KickCD_PROFILE_CHANGED` on
profile change/copy/reset.

## Settings UI framework

The settings tabs are not native vertical-layout subcategories; they are
**canvas-layout** panels that share one custom header and a schema-driven
widget renderer.

### Panel chrome

`Helpers.CreatePanel(name, title, opts)` builds a Frame compatible with
`Settings.RegisterCanvasLayoutSubcategory` and stamps a unified header on
top:

* Title FontString (`GameFontNormalHuge`) at top-left
* `Defaults` button (`UIPanelButtonTemplate`) at top-right when
  `opts.defaultsButton` is true (General/Icons/Spells); omitted on
  Profiles
* `Options_HorizontalDivider` atlas underneath, full panel width
* A `body` Frame anchored beneath the header that hosts the panel's
  content

The function returns a `ctx` table with `panel`, `body`, a layout
`cursor`, and a `refreshers` array; the caller threads this through the
section/widget helpers.

### Schema (`KickCD.Settings.Schema`)

A flat array; each row declares one option:

```lua
{ panel, section, group, path, type, label, tooltip, default,
  min, max, step, fmt,            -- numbers
  values,                          -- strings (dropdown); array or fn
  onChange = function(v) ... end } -- optional
```

`type ∈ { bool, number, string, color }`. The same row drives:

| Surface | How |
|---|---|
| Panel widget | `Helpers.RenderField(ctx, def)` dispatches by type to `makeCheckbox` / `makeSlider` / `makeDropdown` / `makeColorPicker`; each registers a refresher closure on `ctx.refreshers` |
| `/kcd list` | groups schema by `panel`, prints `path = formattedValue` |
| `/kcd get <path>` | `Helpers.FindSchema(path)` + `formatValue` |
| `/kcd set <path> <value>` | type-aware parse (clamp numbers, validate dropdown values, parse `r g b [a]` for colors) → `Helpers.Set` → `onChange` → `Helpers.RefreshAllPanels` |
| `Defaults` button | `Helpers.RestoreDefaults(panelKey, ctx)` resets every panel row to `def.default`, runs `onChange`, fires per-section `KickCD_CONFIG_CHANGED`, re-runs the panel's refreshers |

**Adding an option = one schema row.** UI, slash CLI, and Defaults reset
are wired automatically.

### Custom-body tabs

* **Spells** — AceGUI editor (class/spec dropdowns, Add spell button,
  scrollable row list) parented to `ctx.body`. Header `Defaults` button
  opens the existing `KICKCD_RESET_SPELLS` StaticPopup (resets the
  current class+spec only).
* **Profiles** — `AceConfigDialog:Open("KickCD-Profiles", container)`
  renders the AceDBOptions options table into an AceGUI `SimpleGroup`
  parented to `ctx.body`. No `Defaults` button — AceDBOptions has its
  own destructive controls.

### Widget binding

Canvas widgets bind directly to `db.profile` via `Helpers.Get(path)` /
`Helpers.Set(path, section, value)`. They do **not** go through
`Settings.RegisterAddOnSetting` — the Compat shim for that API exists
but has no live callers. Modern dropdowns use
`MenuUtil.CreateContextMenu` (12.0+); sliders use `OptionsSliderTemplate`
with hand-laid label/value FontStrings; color swatches drive
`ColorPickerFrame` via `OpenColorPicker`.

## Closed message contract

Internal messages travel over AceEvent's per-addon bus (`KickCD:SendMessage` / `:RegisterMessage`). The full set:

| Message | Sender | Listeners | Payload | Notes |
|---|---|---|---|---|
| `KickCD_SPELL_STATE` | `Cooldowns:Rebuild` / `Refresh` | `IconGrid` | `{ spellID, ready, isActive, cdObject, charges }` | `cdObject` is the secret-aware `CooldownDuration` from `C_Spell.GetSpellCooldownDuration`; non-nil whenever `isActive` is true. `:GetRemainingDuration()` on it is secret in combat — only pass directly to C methods. `charges` may also be secret. |
| `KickCD_CONFIG_CHANGED` | `settings/Panel.lua Helpers.Set`, `core/KickCD.lua` (lock/unlock) | `IconGrid`, `Cooldowns` | `{ section = "general"\|"icons"\|"spells" }` | section-keyed for cheap dispatch |
| `KickCD_PROFILE_CHANGED` | `Database:OnProfileChanged` (AceDB callback) | `IconGrid`, `Cooldowns` | `{ newProfileKey }` | fires for `OnProfileChanged` / `Copied` / `Reset` |

The set is closed by convention — module headers and `CLAUDE.md` reference this list. Adding a message means updating both the source emitter, every consumer, and this table.

## Saved variables

Single saved-variable: `KickCDDB`, an AceDB-3.0 store. Default scope is per-character (the `true` arg in `AceDB:New`); the user can switch to default / per-class / per-realm via the Profiles tab.

Profile shape (see `core/Database.lua` `DEFAULT_PROFILE`):

```lua
{
    enabled  = true,
    locked   = true,           -- icon grid drag lock
    scale    = 1.0,            -- master scale
    alpha    = 1.0,            -- master alpha
    debugLog = false,          -- mirrors /kcd debug log; toggles internal-message logging

    icons = {
        -- Sizing
        primarySize, secondarySize, gap, zoom,
        -- Layout (12 anchor points + 8 grow directions; orthogonal)
        anchor,                                -- "TOP_LEFT" | "RIGHT_CENTER" | ...
        secondaryGrow,                         -- "right_down" | "up_left" | ...
        secondaryRows, secondaryCols,
        secondaryOffsetX, secondaryOffsetY,
        -- Visual states (drives the alpha/tint curves in IconGrid)
        readyAlpha, cooldownAlpha, cooldownTint,
        -- Border
        borderShow, borderColor, borderSize,
        -- Annotations
        showCooldownText, cooldownTextFont, cooldownTextSize, cooldownTextFlags,
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

Forward-only migrations bring older saved-vars up to the current schema (`Database.Migrations[1..4]` in `core/Database.lua`). Notably `v4` translated the old `layout` (horizontal/vertical) + `primaryAnchor` pair into the unified 12-option `anchor` enum.

`spells` is seeded once on first profile creation by `Database:BuildSpells`, which deep-copies `KickCD.DefaultSpells` and appends the player's racial cast-stopper. Subsequent edits are user-owned; the seeder is idempotent on populated profiles.

## Compat layer

Spell APIs and the Settings registration API have churned across recent expansions. `core/Compat.lua` provides a stable surface:

| Compat function | Wraps | 12.0 caveats |
|---|---|---|
| `Compat.GetSpellCooldown(id)` | `C_Spell.GetSpellCooldown` (table) → `_G.GetSpellCooldown` (tuple) | Returns `(start, duration, isEnabled, modRate, isActive)`; `start`/`duration`/`modRate` may be secret. Use `isActive` (plain) for "is on cooldown" decisions. |
| `Compat.GetSpellCooldownDuration(id)` | `C_Spell.GetSpellCooldownDuration` | Returns a secret-aware `CooldownDuration` object (or nil). Pass to `Cooldown:SetCooldownFromDurationObject`, `FontString:SetFormattedText("%.1f", obj:GetRemainingDuration())`, or `obj:EvaluateRemainingDuration(curve)`. **`:GetRemainingDuration()` is secret in combat** — only pass directly to a C method; never bind to a Lua local for compare / format / tostring. |
| `Compat.GetSpellInfo(id)` | `C_Spell.GetSpellInfo` (table) → `_G.GetSpellInfo` (tuple) | — |
| `Compat.GetSpellTexture(id)` | `C_Spell.GetSpellTexture` → `_G.GetSpellTexture` | Texture may be secret on guarded spells; gate with `issecretvalue` before `SetTexture`. |
| `Compat.GetSpellCharges(id)` | `C_Spell.GetSpellCharges` (table) → `_G.GetSpellCharges` (tuple) | Charges may be secret on guarded spells. |
| `Compat.IsSpellUsable(id)` | `C_Spell.IsSpellUsable` → `_G.IsUsableSpell` | Returns `(usable, noMana)` regardless of underlying shape. |
| `Compat.RegisterAddOnSetting(...)` | `Settings.RegisterAddOnSetting` | Tries the 12.0+ `(category, variable, variableKey, variableTbl, varType, name, default)` shape first; falls back through 11.0 / 10.0 shapes via `pcall`. **Vestigial** — no live caller; canvas-layout panels bind directly to `db.profile`. |

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

`OnSlashCommand` lowercases only the command name and preserves case in
the rest of the input, so schema paths like `icons.primarySize` survive
unchanged through `/kcd set ...`. `runDebug` lowercases its own
subcommand for backward compat.

Three of the top-level commands (`list`, `get`, `set`) are
schema-driven and gain new entries automatically as schema rows are
added — see the **Settings UI framework** section above.

Adding a regular command is a one-row append; help text is generated from the same rows that drive dispatch.

## Conventions

- Saved-variable boundary lives in `core/Database.lua`; modules read/write `KickCD.db.profile` directly but treat the schema as defined there.
- Anchor format is fixed: `{ point, relativePoint, x, y }` relative to UIParent. No `relativeTo` frame references.
- Internal communication is via the closed message set; modules do not call each other directly across boundaries.
- Module files are header-commented with their job and message contract; keep both in sync with the code.
- 12.0 secret values: rule of thumb is "operate on `isActive` / `isEnabled` (plain bools) for decisions; pass the `cdObject` from `Compat.GetSpellCooldownDuration` opaquely to C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `EvaluateRemainingDuration`); never bind `:GetRemainingDuration()` to a Lua local in combat." Visual decisions that depend on remaining time (e.g. GCD-vs-real-CD filter) live in C-side curves built by `IconGrid.BuildCurves` and applied via `SetAlphaFromBoolean` / `SetVertexColor`. See `CLAUDE.md` for the full pattern catalogue.
