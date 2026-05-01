# CLAUDE.md

Guidance for Claude (or any AI agent) working on this addon. This file is an index — each section lives in its own file. Read the relevant section(s) for the task at hand; read all of them before any non-trivial change.

- [Overview](docs/CLAUDE_OVERVIEW.md) — what KickCD is, target version, and the cast-bar removal history.
- [12.0 secret-value protection](docs/CLAUDE_SECRET_VALUES.md) — **read first.** The rule for working with WoW 12.0 protected APIs (`C_Spell.GetSpellCooldown`, `UnitCastingInfo`, …); patterns that error and the preferred `CooldownDuration` workaround.
- [Module layout and boot order](docs/CLAUDE_MODULE_LAYOUT.md) — TOC load order; what each `core/` / `modules/` / `settings/` file is responsible for.
- [The closed message bus](docs/CLAUDE_MESSAGE_BUS.md) — the four AceEvent messages (`KickCD_SPELL_STATE`, `KickCD_CONFIG_CHANGED`, `KickCD_PROFILE_CHANGED`, `KickCD_GRID_LAYOUT`) and their payloads.
- [Icon grid layout model](docs/CLAUDE_ICON_GRID_LAYOUT.md) — anchor + grow + dimensions: how `modules/IconGrid.lua` places primary and secondary icons.
- [Settings panel](docs/CLAUDE_SETTINGS_PANEL.md) — schema-driven canvas layout; `KickCD.Settings.Schema` as single source of truth; widget primitives; custom-body tabs.
- [Cast bar module](docs/CLAUDE_CASTBAR.md) — secret-value-gated `UnitCastingInfo` / `UnitCastingDuration` handling; stacked dual widgets; anti-patterns to avoid.
- [Frame mixin pattern](docs/CLAUDE_FRAME_MIXIN.md) — never `setmetatable` on a Blizzard widget; use `Mixin`.
- [Stale /docs/](docs/CLAUDE_DOCS_STALE.md) — caveats on `docs/*.md` predating cast-bar removal and 12.0 secret-value handling.
- [Testing](docs/CLAUDE_TESTING.md) — manual verification steps and slash-command coverage.
- [Conventions](docs/CLAUDE_CONVENTIONS.md) — code style and module-level rules.

For the current architecture (module map, data flow, saved-variable shape, Compat surface), see [ARCHITECTURE.md](ARCHITECTURE.md) and the `ARCHITECTURE_*.md` files it indexes.

