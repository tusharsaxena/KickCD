# Conventions

- Saved-variable boundary lives in `core/Database.lua`; modules read/write `KickCD.db.profile` directly but treat the schema as defined there.
- Anchor format is fixed: `{ point, relativePoint, x, y }` relative to UIParent. No `relativeTo` frame references.
- Internal communication is via the closed message set; modules do not call each other directly across boundaries.
- Module files are header-commented with their job and message contract; keep both in sync with the code.
- 12.0 secret values: rule of thumb is "operate on `isActive` / `isEnabled` (plain bools) for decisions; pass the `cdObject` from `Compat.GetSpellCooldownDuration` opaquely to C methods (`SetCooldownFromDurationObject`, `SetFormattedText`, `EvaluateRemainingDuration`); never bind `:GetRemainingDuration()` to a Lua local in combat." Visual decisions that depend on remaining time (e.g. GCD-vs-real-CD filter) live in C-side curves built by `IconGrid.BuildCurves` and applied via `SetAlphaFromBoolean` / `SetVertexColor`. See [`CLAUDE.md`](../CLAUDE.md) for the full pattern catalogue.

