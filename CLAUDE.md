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

## Settings panel registration pattern

`Settings.RegisterAddOnSetting`'s signature has churned across 10.0 → 10.2 → 11.0 → 12.0. **Always go through `KickCD.Compat.RegisterAddOnSetting`** (in `core/Compat.lua`); it tries the modern signature first and falls back through the older shapes on `pcall` failure.

Helper widgets in `settings/Panel.lua` (`Helpers.CreateCheckbox`, `CreateSlider`, `CreateDropdown`, `CreateColorPicker`) wrap this for the common cases — prefer them over calling the API directly.

## Frame mixin pattern

**Never `setmetatable(frame, t)` on a Blizzard widget** — Frame methods (`ClearAllPoints`, `Show`, `SetAlpha`, ...) live on the C-side metatable, and replacing it nils them. Use `Mixin(frame, t)` (Blizzard's global) to copy fields onto the frame without touching the metatable. See `modules/IconGrid.lua` `CreateIconWidget` → `return Mixin(btn, Icon)`.

## Existing /docs/ are partially stale

`docs/TECHNICAL_DESIGN.md`, `EXECUTION_PLAN.md`, `REQUIREMENTS.md`, `RESEARCH.md`, `UAT.md` predate the cast-bar removal and the 12.0 secret-value handling. They still describe the original three-module architecture (Tracker + Castbar + IconGrid) and the FR-1 / FR-3 cast-bar requirements that no longer apply. Use them for context on the original design intent, not as a source of truth for current behavior. `ARCHITECTURE.md` (sibling of this file) reflects current reality.

When updating module-level header comments, prefer accurate descriptions over `See docs/...` references that may now be wrong.

## Testing

There is no automated test harness. Verification is manual:

- `/kcd` — print the slash command help.
- `/kcd debug spells` — dump the watched cooldown list with `ready / active / dur / charges` per spell. `dur=secret` is expected for protected interrupts.
- `/kcd debug log` — toggle internal-message logging.
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the icon grid lock state.
- In-game: target a hostile caster, fire your interrupt, confirm the icon desaturates without errors. The Lua error frame (or BugSack/BugGrabber) is the primary regression signal.

## Conventions

- Module files start with a one-paragraph header explaining the module's job and its message contract.
- Closed-set adherence: a module that names messages it emits or listens to should keep that list in sync with the actual code.
- Saved variables live under `KickCDDB`; the active profile shape is `DEFAULT_PROFILE` in `core/Database.lua`.
- All code is plain Lua 5.1 (WoW's runtime). No external Lua deps beyond vendored Ace3 / LSM.
