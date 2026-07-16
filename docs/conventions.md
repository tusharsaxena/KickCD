# Conventions

Code style and module-level rules. The mid-level architecture (boundaries, message contract, Compat-vs-State separation) lives in [module-map.md](module-map.md), [message-bus.md](message-bus.md), and [compat-layer.md](compat-layer.md); this file collects the small-scale conventions that apply file-by-file.

## Module file structure

- Module files start with a one-paragraph header explaining the module's job and its message contract.
- Closed-set adherence: a module that names messages it emits or listens to should keep that list in sync with the actual code (and with [message-bus.md](message-bus.md)).

## Saved variables

- Saved variables live under `KickCDDB`; the active profile shape is `DEFAULT_PROFILE` in `core/Database.lua`. New persistent fields go in that table, with a comment explaining the shape and any 12.0 secret-value caveats. See [saved-variables.md](saved-variables.md).
- Modules read/write `NS.db.profile` directly but treat the schema as defined in `core/Database.lua` — the saved-variable boundary is centralised there. The exception is per-unit appearance (`icons`/`castbar`): those go through `NS.Units.Icons(unit)` / `NS.Units.Castbar(unit)` so link resolution (a linked focus reading target's tables) stays in one place — see `core/Units.lua`.
- Anchor format is fixed: `{ point, relativePoint, x, y }` relative to UIParent. No `relativeTo` frame references.

## Frame names

- Global frame names stay literally `KickCD` (see [scope.md](scope.md)): `KickCDIconGrid`, `KickCDCastbar`, `KickCDDebugWindow`, etc. — no addon-name prefixing games.
- **Deviation recorded as intentional** (per CLAUDE.md's flag-deviations rule): the target/focus dual-tracking feature extends this with a `Focus`-suffixed sibling per per-unit frame — `KickCDIconGridFocus`, `KickCDCastbarFocus` — rather than breaking the convention. Target keeps the exact legacy unsuffixed name (macros / other addons may already reference `KickCDIconGrid` / `KickCDCastbar`); focus is unambiguously suffixed rather than using a numeric or generic index, since "target" and "focus" are the addon's actual unit vocabulary. A third unit (if ever added) would follow the same `KickCD<Widget><UnitTitleCase>` pattern.
- **Deviation recorded as intentional** (per CLAUDE.md's flag-deviations rule, extending the note above): the single text-label feature's `modules/UnitLabel.lua` follows the same `KickCD<Widget><UnitTitleCase>` pattern — `KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`. Each frame is *created* on `UIParent` (so it exists before any attach frame does), but `UnitLabel:Apply` `SetParent`s it onto its resolved attach frame (the unit's cast bar or icon grid) every time it re-anchors. This is deliberate: parenting onto the attach frame means the label inherits that frame's own shown state and effective alpha for free, so the label follows the addon's General visibility exactly like the widget it's attached to — no separate visibility re-implementation or extra event wiring needed. (Earlier revision of this note said the label's visibility was independent of the attach frame's; that was the bug this convention now fixes.)

## Settings layer

- Settings reads / writes that come from outside `settings/Panel.lua` (slash commands, keybinds, …) should route through `Helpers.SetAndRefresh(path, value)` so they share the panel widgets' write-notify-refresh code path. Direct `db.profile` writes are reserved for places where no schema row exists (drag-stop anchor save, profile bootstrap).
- New schema rows automatically gain `/kcd get|set|list` coverage, the per-panel Defaults reset, and the General → "Reset all settings" reset. Don't add a parallel mutator for a field that already has a schema row.
- Slash and panel paths share a single helper (`Helpers.SetAndRefresh`) for any setting that exists as a schema row, so a future `onChange` doesn't silently diverge between the two surfaces.
- `Helpers.SetAndRefresh` is defined in `settings/Panel.lua`, which loads after `core/KickCD.lua`. Slash commands that fire before `settings/` has loaded (between `OnInitialize` and `PLAYER_LOGIN`) hit a fallback path that writes directly to `db.profile` and emits `Ka0s_KickCD_CONFIG_CHANGED`. The fallback is intentional; don't reorder the TOC to "fix" it without also revisiting that path.

## Chat output

- Chat output goes through `Util.print` (or `NS.Util.print`) — never call the global `print` directly and never write your own `|cff…KickCD|r:` prefix. `Util.print` prepends the single shared `NS.PREFIX` chat tag (a cyan `[KCD]` banner, defined once in `core/Constants.lua`); passing your own prefix produces a double banner. Any other chat site that needs the tag references `NS.PREFIX` rather than re-spelling the color code. The help printers in `core/KickCD.lua` are the only callers that color anything else (yellow `|cffffff00…|r` for the slash invocation, white `|cffffffff…|r` for the description).

## 12.0 secret-value rule of thumb

- **Secret numbers.** Operate on `isActive` / `isEnabled` (plain bools) for decisions; pass the `cdObject` from `Compat.GetSpellCooldownDuration` opaquely to C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `EvaluateRemainingDuration`); never bind `:GetRemainingDuration()` to a Lua local in combat. Visual decisions that depend on remaining time (e.g. GCD-vs-real-CD filter) live in C-side curves built by `IconGrid.BuildCurves` and applied via `SetAlphaFromBoolean` / `SetVertexColor`.
- **Secret bools and strings.** Never compare `UnitCastingInfo.notInterruptible` / `name` / `texture` / `spellID` in Lua; either pass straight to a Blizzard C method that accepts secrets (`Texture:SetTexture`, `FontString:SetText`, `Frame:SetAlphaFromBoolean`, `C_CurveUtil.EvaluateColorValueFromBoolean`) or use `NS.State.IsHostileUnitCasting` for the truthy "is something casting" check.
- **Visibility / glow / interruptibility decisions** that depend on `notInterruptible` MUST go through the two-step gate (`NS.State.IsHostileUnitCasting` for show + `NS.State.ApplyInterruptibleAlpha` for filter; both live in `core/State.lua`, not `core/Compat.lua` — these are addon visibility decisions, not API normalisation). The full pattern catalogue is in [midnight-quirks.md](midnight-quirks.md).

## Compat / State / Constants split

- `core/Compat.lua` is API normalisation only (spell-info shims, cast-info record building).
- `core/State.lua` owns shared mutable state (the event-driven combat flag) and visibility helpers (`IsHostileUnitCasting`, `ApplyInterruptibleAlpha`).
- `core/Constants.lua` owns shared magic numbers under `NS.Const` (`GCD_UPPER`, panel paddings, castbar text insets).
- New constants and shared state belong in those namespaces, not as module-local locals duplicated across files. **Don't add visibility decisions or shared state to Compat.**

## Lua / runtime

- All code is plain Lua 5.1 (WoW's runtime). No external Lua deps beyond vendored Ace3 / LSM / LibCustomGlow.

## Global lookup form

When a Blizzard / WoW global is read, the form depends on whether the symbol is GUARDED anywhere in the module:

- **Guarded somewhere → `_G.X` everywhere.** If the module ever guards the symbol (`if X then`, `X and X(...)`, `... or X`, `X = X and ... or default`), write `_G.X` for EVERY reference to that symbol in the module — including reads inside the guard's protected block. The `_G.` form makes the "this might not exist" intent obvious and matches the style in `core/Compat.lua`. Symbols that fall in this bucket today: `C_Spell`, `C_Timer`, `C_CurveUtil`, `issecretvalue`, `InCombatLockdown`, `UnitCastingInfo`, `UnitChannelInfo`, `UnitCastingDuration`, `UnitChannelDuration`, `UnitExists`, `UnitCanAttack`, `UnitName`, `GameFontNormal`, every legacy `GetSpell*` / `IsSpell*` / `IsPlayerSpell` / `IsUsableSpell`, `print` (used as a fallback), and the cast-event API surface.
- **Never guarded → bare `X`.** If the symbol is never guarded anywhere — i.e. it's a trusted baseline global the surrounding code does not short-circuit on — write bare `X`. Examples: `UnitClass`, `UnitRace`, `UnitIsDead`, `UnitIsUnit`, `CreateFrame`, `Mixin`, `Enum`, `CreateColor`.
- **Spec APIs are wrapped, not read raw.** The deprecated `GetSpecialization` / `GetSpecializationInfo` globals route through `NS.Compat.GetSpecialization()` / `NS.Compat.GetSpecializationInfo(i)` — no direct calls to the globals remain outside `core/Compat.lua`. Callers use the `NS.Compat.*` shims; the bare-vs-`_G.` rule above only governs the single guarded read inside Compat.
- **Same symbol, same form across all reads within a module.** Do not mix `_G.X` and bare `X` for the same global. If a future change adds a guard for a symbol that today is bare, sweep the module to switch every reference to `_G.X`.

## Line endings

CRLF on every tracked text file. The repo's `.gitattributes` enforces `* text=auto eol=crlf`, so git's smudge filter normalises on checkout — the working tree should never contain LF-terminated source files. The tree was normalised in commits `b6b9853` / `a74251a` / `3ba3ca3`. New files added by an agent should match the surrounding files in their directory.
