# Conventions

- Saved-variable boundary lives in `core/Database.lua`; modules read/write `KickCD.db.profile` directly but treat the schema as defined there.
- Anchor format is fixed: `{ point, relativePoint, x, y }` relative to UIParent. No `relativeTo` frame references.
- Internal communication is via the closed message set; modules do not call each other directly across boundaries.
- Module files are header-commented with their job and message contract; keep both in sync with the code.
- 12.0 secret values: rule of thumb is "operate on `isActive` / `isEnabled` (plain bools) for decisions; pass the `cdObject` from `Compat.GetSpellCooldownDuration` opaquely to C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `EvaluateRemainingDuration`); never bind `:GetRemainingDuration()` to a Lua local in combat." Visual decisions that depend on remaining time (e.g. GCD-vs-real-CD filter) live in C-side curves built by `IconGrid.BuildCurves` and applied via `SetAlphaFromBoolean` / `SetVertexColor`. See [`CLAUDE.md`](../CLAUDE.md) for the full pattern catalogue.
- 12.0 secret bools (`UnitCastingInfo.notInterruptible`, `name`, `texture`, `spellID`): never compare in Lua; either pass straight to a Blizzard C method that accepts secrets (`Texture:SetTexture`, `FontString:SetText`, `Frame:SetAlphaFromBoolean`, `C_CurveUtil.EvaluateColorValueFromBoolean`) or use `Compat.IsHostileUnitCasting` for the truthy "is something casting" check. The visibility / glow `target_casting_interruptible` filter is implemented as a two-step gate (Show on hostile cast, then alpha-mask uninterruptible) precisely because of this rule. See [`CLAUDE_SECRET_VALUES.md`](CLAUDE_SECRET_VALUES.md).
- Slash and panel paths share a single helper (`Helpers.SetAndRefresh`) for any setting that exists as a schema row, so a future `onChange` doesn't silently diverge between the two surfaces.
- Line endings: CRLF on tracked source / docs (the WoW client and the Windows toolchain prefer it; commits `b6b9853` / `a74251a` / `3ba3ca3` normalized the tree). New files added by an agent should match the surrounding files in their directory.

