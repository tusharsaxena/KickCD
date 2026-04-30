# CLAUDE.md

Guidance for Claude (or any AI agent) working on this addon.

## What this is

KickCD is a WoW addon that tracks the player's interrupt and CC cooldowns and shows them on a movable, persistently-visible icon grid. Target: WoW 12.0 (Midnight). Mainline branch is `master`.

The original cast-bar pipeline (Castbar / Tracker / TestMode modules) was removed at commit `59fb5c0` because its `OnUpdate` did arithmetic on `startTimeMS` / `endTimeMS` from `UnitCastingInfo`, which 12.0 returns as secret values. A fresh `modules/Castbar.lua` was re-added later with explicit secret-value gating (see "Cast bar module" below). The TestMode preview was not re-added.

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

**Preferred workaround for cooldown timing:** use `C_Spell.GetSpellCooldownDuration(spellID)` (wrapped as `KickCD.Compat.GetSpellCooldownDuration`). It returns a `CooldownDuration` object that can be:

- Passed straight to `Cooldown:SetCooldownFromDurationObject(obj)` to drive the swipe.
- Passed to `FontString:SetFormattedText("%.1f", obj:GetRemainingDuration())` to render countdown text.
- Evaluated against a `C_CurveUtil.CreateCurve` / `CreateColorCurve` via `obj:EvaluateRemainingDuration(curve)` and the result passed to `Frame:SetAlphaFromBoolean(true, alpha, 0)` / `Texture:SetVertexColor(color:GetRGB())`.

**Critical caveat:** `obj:GetRemainingDuration()` returns a *secret-tainted* number in combat (plain out of combat). It is **only** safe as a direct argument to a Blizzard C method. Binding it to a Lua local for a comparison, format, tostring, or arithmetic op will error with "attempt to compare local '...' (a secret number value)" the moment combat opens. The same caveat applies to whatever `EvaluateRemainingDuration` returns — pass it through to a C method, never inspect it.

This is the API `FloatingInterruptHighlight` uses, and we've adopted the same pattern: `modules/Cooldowns.lua` emits the duration object opaquely, `modules/IconGrid.lua` evaluates it against step-shaped alpha/tint curves to derive GCD-vs-real-CD visuals C-side. Reach for `C_Spell.GetSpellCooldown`'s raw `startTime`/`duration` only when you genuinely need them — and even then, gate with `issecretvalue` first because in combat *every* watched spell's timings come back secret.

Why curves instead of a `UNIT_SPELLCAST_SUCCEEDED` cast tracker for GCD filtering? Blizzard suppresses that event for protected interrupts (Mind Freeze, Pummel, Kick, Spear Hand Strike, …) — the event simply does not fire when the player casts one of those spells in tainted scope. So a cast-event tracker can never flip the primary icon's state. Curve evaluation runs entirely C-side and works for protected and unprotected spells alike.

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
10. `modules/Castbar.lua` — owns the `KickCDCastbar` frame; mirrors the player's target's cast/channel via secret-value-gated `UnitCastingInfo` shims (see "Cast bar module" below).
11. `settings/Panel.lua` — registers the top-level Blizzard Settings category and the per-tab builder mailbox.
12. `settings/{General,Icons,Castbar,Spells,Profiles}.lua` — register their tabs via `KickCD.Settings.RegisterTab`.

## The closed message bus

All inter-module communication uses `AceEvent`-style messages with a fixed name set:

| Message | Sender | Payload |
|---|---|---|
| `KickCD_SPELL_STATE` | Cooldowns | `{ spellID, ready, isActive, cdObject, charges }` |
| `KickCD_CONFIG_CHANGED` | settings/* + slash | `{ section = "general"\|"icons"\|"spells"\|"castbar" }` |
| `KickCD_PROFILE_CHANGED` | Database (AceDB callback) | `{ newProfileKey }` |

**Don't invent new messages without a reason.** The closed list is documented in this file and in module headers; new entries should appear here too. `cdObject` is the secret-aware `CooldownDuration` handle from `C_Spell.GetSpellCooldownDuration`, non-nil whenever the legacy `isActive` flag is true (real CD or just-GCD; the IconGrid disambiguates downstream). It can be:
- Passed to `Cooldown:SetCooldownFromDurationObject` for the swipe.
- Passed to `FontString:SetFormattedText("%.1f", cdObj:GetRemainingDuration())` for countdown text.
- Evaluated against a `C_CurveUtil.CreateCurve` / `CreateColorCurve` via `cdObj:EvaluateRemainingDuration(curve)` to produce alpha / color values that ride through `Frame:SetAlphaFromBoolean(true, alpha, 0)` and `Texture:SetVertexColor(color:GetRGB())`.

The legacy `start` / `duration` raw timings are NOT in the payload precisely because they go secret in combat for every watched spell and break arithmetic in tainted scope. **`cdObject:GetRemainingDuration()` is also secret in combat** — only ever pass it directly to a C method as an argument; never hold it in a Lua local for compare / format / tostring. The GCD-vs-real-CD visual filter lives entirely in `modules/IconGrid.lua` as a step-shaped alpha/tint curve evaluated C-side: `UNIT_SPELLCAST_SUCCEEDED` is suppressed for protected interrupts (Mind Freeze, Pummel, Kick, …) so a cast-event tracker would never flip the primary icon's state — the curve sidesteps that by reading remaining only inside Blizzard's curve evaluator.

## Icon grid layout model

`modules/IconGrid.lua` builds the visible grid from three orthogonal pieces, picked in this order:

1. **`icons.anchor`** — one of 12 anchor points naming where the secondary block attaches to the primary. The first word (`TOP` / `BOTTOM` / `LEFT` / `RIGHT`) is the side; the second word is the alignment along the perpendicular axis (`CENTER` always works; `LEFT` / `RIGHT` for `TOP`/`BOTTOM` sides; `TOP` / `BOTTOM` for `LEFT`/`RIGHT` sides). Examples: `RIGHT_CENTER`, `TOP_LEFT`, `BOTTOM_RIGHT`. There is no longer a separate `layout` (horizontal/vertical) field — the anchor's side is the primary axis.
2. **`icons.secondaryGrow`** — fill order inside the block as a compound `<primary>_<secondary>` direction. 8 valid values: `right_down`, `right_up`, `left_down`, `left_up`, `down_right`, `down_left`, `up_right`, `up_left`. Primary axis decides row-major (`right`/`left`) vs column-major (`down`/`up`) fill; secondary axis decides which way the next row/column wraps. Anchor and grow are independent — any of the 96 combinations renders sensibly.
3. **`icons.secondaryRows` × `icons.secondaryCols`** — block dimensions. Always geometric: `rows` is the vertical extent (icons stacked up/down), `cols` is the horizontal extent. Same values produce the same shape regardless of anchor.

The whole layout is in three small functions: `parseAnchor`, `parseGrow`, `placeBlock` (computes grid bounding box and the primary/block TOPLEFT corners), and the single `layoutBlock` that anchors every widget to the grid frame's TOPLEFT in pixel-floored screen coordinates.

`secondaryOffsetX` / `secondaryOffsetY` shift the block (not the primary) in screen-pixel space (positive X = right, positive Y = down). Saved-vars from older builds are forward-migrated by `Migrations[4]` in `core/Database.lua`.

## Settings panel — schema-driven canvas layout

All four tabs (General, Icons, Spells, Profiles) are registered as
**canvas-layout subcategories** so they share one custom header design:

* `GameFontNormalHuge` title on the left
* `Defaults` button on the right (AceGUI `Button`, which wraps
  `UIPanelButtonTemplate`) — present on General/Icons/Spells, omitted on
  Profiles. Wire its handler with
  `ctx.panel.defaultsBtn:SetCallback("OnClick", fn)` (NOT `:SetScript`,
  since the AceGUI widget object isn't a Blizzard Frame).
* `Options_HorizontalDivider` atlas underneath, full panel width

The header is built by `Helpers.CreatePanel(name, title, opts)` in
`settings/Panel.lua`. It returns a `ctx` table (`{ panel, body, scroll,
refreshers, lastGroup, panelKey }`) that the per-tab builder threads
through the rest of the layout helpers. `ctx.scroll` is the AceGUI
`ScrollFrame` (created lazily on first widget add) that hosts schema
widgets; tabs that don't use the schema renderer (Spells / Profiles)
parent their own AceGUI containers to `ctx.body` directly and never
trigger the lazy scroll.

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

Schema widgets are AceGUI widgets — `CheckBox`, `Slider`, `Dropdown`,
`ColorPicker`, `Heading` for sections, `Button` + `Label` inside a
`SimpleGroup` for inline action rows — added to a single AceGUI
`ScrollFrame` per tab. This matches the visual style of AceConfig-driven
addons (e.g. Consumable Master) and keeps every widget on the
`Helpers.Set` / `Helpers.Get` data path. The slider's value editbox is
post-formatted via a `HookScript` on the inner Blizzard Slider so
`def.fmt` (`"%.2fx"`, `"%d px"`) wins over AceGUI's raw-numeric
`UpdateText`.

Schema rendering is **deferred to the panel's `OnShow`** because at
build time (PLAYER_LOGIN) `ctx.body` has zero width and AceGUI's
List-layout pass against the AceGUI `ScrollFrame` would size every
fullwidth child to zero. See the `local rendered = false; OnShow{...}`
guard in `settings/General.lua` and `settings/Icons.lua`.

### `Compat.RegisterAddOnSetting` is vestigial

The shim still exists in `core/Compat.lua` and is documented for
historical context, but **no live code calls it**. The canvas widgets
bind directly to `db.profile` and don't go through Blizzard's Setting
object lifecycle at all. Don't reach for the shim when adding new UI;
use the schema + `Helpers.RenderField` instead.

## Cast bar module

`modules/Castbar.lua` shows the player's target's cast/channel on a separately-anchored bar (`db.profile.anchors.castbar`). The lock state is shared with the icon grid (`db.profile.locked`) — one unlock/lock cycle moves both. While unlocked, the bar shows a placeholder preview when no target is casting so it can be grabbed.

The original implementation broke in 12.0 because `UnitCastingInfo` positions 4–5 (`startTimeMS` / `endTimeMS`) come back as secret values in tainted scope for casts the player can interrupt with a protected interrupt. Arithmetic / compare / format / `tostring` on a secret raises a Lua error, so an `OnUpdate` doing `(GetTime() - startSec) / (endSec - startSec)` blows up the moment combat opens against an interruptable target.

**The key API: `UnitCastingDuration(unit)` / `UnitChannelDuration(unit)`.** These return a `CastingDuration` object whose `:GetTotalDuration()` / `:GetElapsedDuration()` / `:GetRemainingDuration()` / `:GetStartTime()` / `:GetEndTime()` methods supply the timing primitives. This is structurally similar to the `CooldownDuration` object KickCD already uses in `modules/Cooldowns.lua` — and **subject to the same secret-in-combat protection**. The methods *do* return secret-tainted numbers in combat for protected casts. The trick is identical to the cooldown pattern: never bind the return to a Lua local; pass the method call **directly as an argument** to a Blizzard C method that accepts secret args. The technique is the same UltimateCastbars uses for its target/focus bar.

The Compat shim funnels both UnitCastingInfo (for `name` / `texture` / `notInterruptible` / `spellID`) and UnitCastingDuration (for the timing object) into a single record:

```
{ name, texture, spellID, notInterruptible, isChannel, duration }
```

The OnUpdate loop drives the bar by passing the duration methods *as arguments* to Blizzard C methods:

```lua
frame.bar:SetMinMaxValues(0, d:GetTotalDuration())
if current.isChannel then
    frame.bar:SetValue(d:GetRemainingDuration())   -- drains total → 0
else
    frame.bar:SetValue(d:GetElapsedDuration())     -- fills 0 → total
end
frame.timeText:SetFormattedText(
    "%.1f / %.1f", d:GetRemainingDuration(), d:GetTotalDuration())
```

`SetMinMaxValues`, `SetValue`, and `SetFormattedText` all accept secret args without erroring; the format string is interpreted C-side. **No `local total = d:GetTotalDuration()` followed by `if total > 0` anywhere** — that's the four-iteration trap.

**End-of-cast detection lives in events, not OnUpdate.** `if remaining <= 0 then Stop() end` would be a secret comparison and would error. Stop happens on `UNIT_SPELLCAST_STOP` / `_FAILED` / `_INTERRUPTED` / `_CHANNEL_STOP` (filtered to `unit == "target"`).

**The spark uses a static anchor, not per-frame arithmetic.** Computing `frame.spark:SetPoint("CENTER", frame.bar, "LEFT", barWidth * (elapsed / total), 0)` would error on the `elapsed / total` division. Instead, anchor once in `ApplyConfig` to `frame.bar:GetStatusBarTexture()`'s RIGHT edge — Blizzard reanchors the inner status texture C-side as the bar value changes, so the spark follows the fill edge automatically for both casts (texture grows left → right) and channels (texture shrinks right → left).

**`name` and `texture` may themselves be secret in combat for protected casts.** Pass them through to `FontString:SetText` and `Texture:SetTexture` anyway — those C methods accept secret args without erroring (Blizzard's protection is on arithmetic, not on UI render calls). Do **not** call `tostring(name)`, `:format("...", name)`, `if name == "..." then`, or any operation that'd treat the value as data — same secret-value guard the original Castbar tripped on `endTimeMS`.

**`notInterruptible` is a secret boolean.** It stays plain on non-protected casts but is secret in the same scenario `name` / `texture` are. Don't compare or `not` it — only feed it to `C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, valueIfTrue, valueIfFalse)`, which is a Blizzard secure function that accepts a (possibly secret) boolean and a pair of plain values, returning whichever matches.

KickCD uses this to render distinct visuals for interruptible vs uninterruptible casts. The cast bar carries **stacked dual widgets** for everything that can't be expressed as a scalar curve evaluation:

- `frame.bgInterruptible` / `frame.bgUninterruptible` — two BACKGROUND textures, alpha-switched.
- `frame.bar.interruptible` / `frame.bar.uninterruptible` — two `StatusBar`s at identical anchors. OnUpdate calls `SetMinMaxValues` / `SetValue` on **both**, so their inner status textures track together; only one is alpha-visible at a time.
- `frame.borderInterruptible` / `frame.borderUninterruptible` — two `BackdropTemplate` frames with their own LSM border textures, edge sizes, and colors. Border show toggles fold *into* the curve params (passing `0` for the off side) rather than as a multiplier afterwards — multiplying a secret curve result would error.
- `frame.nameText` (single `FontString`) — color is per-state but a single FontString suffices because we curve-evaluate each RGBA channel separately and pass all four results directly to `SetTextColor(r, g, b, a)`.

Each curve evaluation looks like:

```lua
frame.barInterruptible:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(
    current.notInterruptible, 0, 1))   -- visible when interruptible
frame.barUninterruptible:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(
    current.notInterruptible, 1, 0))   -- visible when uninterruptible
```

The result of `EvaluateColorValueFromBoolean` may itself be secret-tainted; pass it directly to `SetAlpha` / `SetTextColor` and never bind to a Lua local. Same rule as the duration object's methods — Blizzard C methods accept secret args; Lua arithmetic does not.

UCB's `Backend/Core/GeneralCore_Helpers.lua` lines 9–23 (`KickAlpha`) and 61–71 (`SecretTo0_1` / `NotSecretTo0_1` / `SecretToA_B`) are the canonical reference for this idiom; we use the same pattern.

Texture differentiation between states (different statusbar textures, different LSM border edge files) genuinely requires two stacked widgets — the texture *path* is a string, not a number, and there's no way to curve-switch a string. Color / alpha / thickness / show-toggle differentiation only needs the curve evaluator and folds into the same widget.

**Anti-pattern that I tried and burned my hands on:** sourcing `castTime` from `C_Spell.GetSpellInfo(spellID)` to size a fallback timeline. The whole returned table is tainted in combat against an interruptable target — *every* field comes back secret (`name`, `castTime`, `iconID`, `minRange`, `maxRange`, `originalIconID`). Reading `info.castTime` into a Lua local and comparing it to `0` errors the same way `endTimeMS` does. UnitCastingDuration sidesteps the whole problem — there's no reason to fall back when the duration object is available.

**Anti-patterns explicitly avoided** (each one was tried and broke; don't repeat):
- Reading `startTimeMS` / `endTimeMS` from `UnitCastingInfo` and doing `(now - start) / (end - start)` arithmetic. (The original v0.1 Castbar bug.)
- Sourcing `castTime` from `C_Spell.GetSpellInfo(spellID)` for a fallback timeline. The whole returned table is tainted.
- Binding `CastingDuration:Get…Duration()` returns to a Lua local for `if x > 0` / `x / y` / `x <= 0`. Pass the method calls as arguments only.
- Computing the spark position from `barWidth * (elapsed / total)`. Anchor to `bar:GetStatusBarTexture():RIGHT` and let Blizzard reposition C-side.
- Detecting end-of-cast in OnUpdate via `if remaining <= 0`. Use `UNIT_SPELLCAST_STOP` and friends.
- `tonumber` / `tostring` / `+0` / `securecallfunction` "detox" of secret values — see `core/Compat.lua` line 28.
- Using `CastingBarFrameTemplate` and pointing it at `"target"`. Its built-in `OnUpdate` does `GetTime() < self.maxValue`, which becomes `GetTime() < <secret>` and errors once the addon sets `maxValue` from a secret `endTime`.
- Restyling `TargetFrameSpellBar` (the default UI cast bar) instead of building a fresh frame.
- Gating `name` / `texture` / `notInterruptible` with `issecretvalue` and replacing with placeholders. They may be secret, but `Texture:SetTexture` / `FontString:SetText` / `C_CurveUtil.EvaluateColorValueFromBoolean` accept secret args without erroring — gating just makes the bar look worse for no benefit.

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
- `/kcd debug spells` — dump the watched cooldown list with `ready / active / cdObj / charges` per spell. `cdObj=yes` means a duration object is held; `nil` means the spell is off cooldown. We deliberately do NOT print remaining time — `:GetRemainingDuration()` is secret in combat and `tostring` would error in tainted scope.
- `/kcd debug log` — toggle internal-message logging (mirrors the
  General → Debug checkbox; both write `db.profile.debugLog`).
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the icon grid lock state.
- In-game: target a hostile caster, fire your interrupt, confirm the icon desaturates without errors. The Lua error frame (or BugSack/BugGrabber) is the primary regression signal.

## Conventions

- Module files start with a one-paragraph header explaining the module's job and its message contract.
- Closed-set adherence: a module that names messages it emits or listens to should keep that list in sync with the actual code.
- Saved variables live under `KickCDDB`; the active profile shape is `DEFAULT_PROFILE` in `core/Database.lua`.
- All code is plain Lua 5.1 (WoW's runtime). No external Lua deps beyond vendored Ace3 / LSM.
