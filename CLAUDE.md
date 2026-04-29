# CLAUDE.md

Guidance for Claude (or any AI agent) working on this addon.

## What this is

KickCD is a WoW addon that tracks the player's interrupt and CC cooldowns and shows them on a movable, persistently-visible icon grid. Target: WoW 12.0 (Midnight). Mainline branch is `master`.

The cast bar pipeline (Castbar / Tracker / TestMode modules) was removed at commit `59fb5c0`; it will be re-added later. The icon grid is the only visible UI.

## Critical: 12.0 secret-value protection

WoW 12.0 introduced "secret values" on certain protected API returns — notably `C_Spell.GetSpellCooldown` for interrupt spells and parts of `UnitCastingInfo` / `UnitChannelInfo`. From tainted (addon) execution, **comparison and arithmetic on a secret value raise a Lua error**, and there is no addon-side strip:

| Pattern | Result |
|---|---|
| `tonumber(secret)` | Still secret. |
| `tostring(secret)` | Still secret. |
| `secret + 0` (in addon scope) | Errors — `+` is the operation that fires. |
| `securecallfunction(fn, secret)` where `fn` is addon-defined | Still tainted; arithmetic inside still errors. |
| `:format("%.1f", secret)` | Errors. |
| Blizzard C methods (`Cooldown:SetCooldown`, `Texture:SetTexture`) with secret args | **Also rejects** — the error message says "Secret values are only allowed during untainted execution for this argument." |

**The rule:** never compare, do arithmetic on, format, or pass to most Blizzard C methods a value that might be secret. Either use a sibling field that is plain (e.g. `info.isActive` and `info.isEnabled` come back plain), or gate the operation with `issecretvalue(v)` and degrade gracefully (skip the op, hide the visual, etc.).

The Cell addon's PR #457 is the canonical reference for the `issecretvalue()`-based pattern; see comments in `core/Compat.lua` and `modules/IconGrid.lua` for the rationale recorded in-tree.

Do not propose `securecallfunction` / `tonumber` / `+0` "detox" workarounds — they were tried and don't work. Comments document this so we don't re-try.

## Module layout and boot order

TOC load order (see `KickCD.toc`):

1. `libs/` — vendored Ace3 + LibSharedMedia. Don't edit.
2. `locales/enUS.lua` — sets up `KickCD.L` with a missing-key fallback.
3. `core/Compat.lua` — bootstraps `_G.KickCD`, hangs `Compat` shims for spell APIs and `Settings.RegisterAddOnSetting`. **Loads first** of core/ — anything later can rely on `KickCD.Compat` existing.
4. `core/Util.lua` — color helpers, anchor save/restore, debounce, chat print.
5. `core/Database.lua` — defines `DEFAULT_PROFILE` and `Database:Init` (called from `KickCD:OnInitialize`). Does not create the DB at file-load time.
6. `core/KickCD.lua` — promotes the bootstrap table to an AceAddon, registers slash commands, defines the slash dispatch tables.
7. `defaults/Spells.lua` — populates `KickCD.DefaultSpells` (per-class+spec interrupt list); merged into the profile by `Database:BuildSpells` on first profile creation.
8. `modules/Cooldowns.lua` — polls cooldown state, emits `KickCD_SPELL_STATE`.
9. `modules/IconGrid.lua` — owns the `KickCDIconGrid` frame and per-icon widgets; persistent visibility.
10. `settings/Panel.lua` — registers the top-level Blizzard Settings category and the per-tab builder mailbox.
11. `settings/{General,Icons,Spells,Profiles}.lua` — register their tabs via `KickCD.Settings.RegisterTab`.

## The closed message bus

All inter-module communication uses `AceEvent`-style messages with a fixed name set:

| Message | Sender | Payload |
|---|---|---|
| `KickCD_SPELL_STATE` | Cooldowns | `{ spellID, ready, isActive, start, duration, charges }` |
| `KickCD_CONFIG_CHANGED` | settings/* + slash | `{ section = "general"\|"icons"\|"spells" }` |
| `KickCD_PROFILE_CHANGED` | Database (AceDB callback) | `{ newProfileKey }` |

**Don't invent new messages without a reason.** The closed list is documented in this file and in module headers; new entries should appear here too. `start` and `duration` in the spell-state payload may be secret values — never compare or do arithmetic on them downstream; gate with `issecretvalue` or use `isActive` (always plain).

## Settings panel — schema-driven canvas layout

All four tabs (General, Icons, Spells, Profiles) are registered as
**canvas-layout subcategories** so they share one custom header design:

* `GameFontNormalHuge` title on the left
* `Defaults` button on the right (`UIPanelButtonTemplate`) — present on
  General/Icons/Spells, omitted on Profiles
* `Options_HorizontalDivider` atlas underneath, full panel width

The header is built by `Helpers.CreatePanel(name, title, opts)` in
`settings/Panel.lua`. It returns a `ctx` table (`{ panel, body, cursor,
refreshers, lastGroup }`) that the per-tab builder threads through the
rest of the layout helpers.

### `KickCD.Settings.Schema` is the single source of truth

`settings/General.lua` and `settings/Icons.lua` declare every option as a
row in a flat array. Each row:

```lua
{
    panel    = "general",                    -- which tab renders it
    section  = "general",                    -- KickCD_CONFIG_CHANGED section
    group    = L["Master controls"],         -- sub-section header text
    path     = "scale",                      -- dotted db.profile path
    type     = "bool"|"number"|"string"|"color",
    label    = L["Master scale"],
    tooltip  = L["..."],
    default  = 1.0,
    min, max, step, fmt,                     -- numbers
    values   = { { value=, label= }, ... },  -- strings (dropdown)
    onChange = function(v) ... end,          -- optional side-effect hook
}
```

The same schema feeds:

* `Helpers.RenderSchema(ctx, panelKey)` — builds `Section` headers per
  `group` and dispatches to `RenderField` per `type` (`makeCheckbox` /
  `makeSlider` / `makeDropdown` / `makeColorPicker`).
* The `/kcd list | get <path> | set <path> <value>` slash commands in
  `core/KickCD.lua` — they look up the schema by path, parse and clamp
  the value by type, write through `Helpers.Set`, run `onChange`, and
  call `Helpers.RefreshAllPanels()` so any open panel re-syncs.
* The per-panel `Defaults` button — `Helpers.RestoreDefaults(panelKey,
  ctx)` resets every entry of that panel back to its `default`, runs
  `onChange`, fires per-section `KickCD_CONFIG_CHANGED`, and re-runs
  the panel's refreshers.

**Adding a new setting = one row in the schema.** UI widget, slash
get/set, and Defaults reset are wired automatically.

### Custom panel bodies (Spells / Profiles)

Spells and Profiles share the unified header but render custom bodies:

* **Spells** — AceGUI editor (class/spec dropdowns, Add spell button,
  scrollable row list) parented to `ctx.body`. The header `Defaults`
  button opens the existing `KICKCD_RESET_SPELLS` StaticPopup, which
  resets only the currently selected class+spec. No schema rows here.
* **Profiles** — AceDBOptions options table rendered into an AceGUI
  `SimpleGroup` parented to `ctx.body`. `AceConfigDialog:Open(
  "KickCD-Profiles", container)` is called on first show. **No
  Defaults button** — profile management has its own destructive
  controls inside the AceDBOptions UI.

### Widget primitives (canvas mode)

All widgets bind directly to `db.profile` via `Helpers.Get(path)` and
`Helpers.Set(path, section, value)` — no `Settings.RegisterAddOnSetting`
involvement. Each widget creator pushes a refresher closure into
`ctx.refreshers` so its display can re-sync after a Defaults reset or
a slash-cmd `/kcd set`.

Modern dropdowns use `MenuUtil.CreateContextMenu` (12.0+). Sliders use
`OptionsSliderTemplate` with hand-laid label/value FontStrings. Color
swatches use `ColorPickerFrame` via `OpenColorPicker`.

### `Compat.RegisterAddOnSetting` is vestigial

The shim still exists in `core/Compat.lua` and is documented for
historical context, but **no live code calls it**. The canvas widgets
bind directly to `db.profile` and don't go through Blizzard's Setting
object lifecycle at all. Don't reach for the shim when adding new UI;
use the schema + `Helpers.RenderField` instead.

## Frame mixin pattern

**Never `setmetatable(frame, t)` on a Blizzard widget** — Frame methods (`ClearAllPoints`, `Show`, `SetAlpha`, ...) live on the C-side metatable, and replacing it nils them. Use `Mixin(frame, t)` (Blizzard's global) to copy fields onto the frame without touching the metatable. See `modules/IconGrid.lua` `CreateIconWidget` → `return Mixin(btn, Icon)`.

## Existing /docs/ are partially stale

`docs/TECHNICAL_DESIGN.md`, `EXECUTION_PLAN.md`, `REQUIREMENTS.md`, `RESEARCH.md`, `UAT.md` predate the cast-bar removal and the 12.0 secret-value handling. They still describe the original three-module architecture (Tracker + Castbar + IconGrid) and the FR-1 / FR-3 cast-bar requirements that no longer apply. Use them for context on the original design intent, not as a source of truth for current behavior. `ARCHITECTURE.md` (sibling of this file) reflects current reality.

When updating module-level header comments, prefer accurate descriptions over `See docs/...` references that may now be wrong.

## Testing

There is no automated test harness. Verification is manual:

- `/kcd` — print the slash command help.
- `/kcd list` — dump every schema-driven setting grouped by panel,
  with current values. Useful for "did the panel/slash share state?"
  spot checks.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for
  every schema row. `path` is the dotted `db.profile` path
  (`enabled`, `icons.primarySize`, `icons.cooldownTint` …). `set`
  parses by `def.type`: bool accepts `true/false/on/off/1/0`; number
  is clamped to `[min, max]`; string must match a `values[i].value`;
  color takes 3–4 floats (`r g b [a]`). On success, any open panel
  refreshes its widgets via `Helpers.RefreshAllPanels()`.
- `/kcd debug spells` — dump the watched cooldown list with `ready / active / dur / charges` per spell. `dur=secret` is expected for protected interrupts.
- `/kcd debug log` — toggle internal-message logging (mirrors the
  General → Debug checkbox; both write `db.profile.debugLog`).
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the icon grid lock state.
- In-game: target a hostile caster, fire your interrupt, confirm the icon desaturates without errors. The Lua error frame (or BugSack/BugGrabber) is the primary regression signal.

## Conventions

- Module files start with a one-paragraph header explaining the module's job and its message contract.
- Closed-set adherence: a module that names messages it emits or listens to should keep that list in sync with the actual code.
- Saved variables live under `KickCDDB`; the active profile shape is `DEFAULT_PROFILE` in `core/Database.lua`.
- All code is plain Lua 5.1 (WoW's runtime). No external Lua deps beyond vendored Ace3 / LSM.
