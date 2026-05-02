# CLAUDE.md

Guidance for Claude (or any AI agent) working on this addon. This file is an index — each section lives in its own file. Read the relevant section(s) for the task at hand; read all of them before any non-trivial change.

## Workflow rules

- **Never auto-stage, auto-commit, or auto-push.** The user controls when changes get staged, committed, and pushed. After editing files, leave the changes in the working tree — don't run `git add` / `git stage` / `git restore --staged` / `git checkout -- <file>` to manipulate the index or discard working-tree edits. Only run `git add` / `git commit` / `git push` when the user explicitly asks ("stage this", "commit this", "commit all changes", "push", etc.). This holds even when working in auto mode. If you need to inspect what would change, use read-only commands (`git status`, `git diff`, `git diff --stat`) instead of staging as a probe.
- **Never bump the version without explicit instruction.** Don't edit `KickCD.toc`'s `## Version`, `KickCD.VERSION` in `core/KickCD.lua`, the README badge, or the README "Version History" section as part of any other task. Version bumps are a release-time decision the user makes deliberately. If a task seems to imply a bump (new feature, breaking change), call it out in the reply and let the user decide. Synchronising version strings *to a value the user already chose* (e.g. "make all the version strings say 1.0.1") is fine — that's not a bump.

The addon ships two pieces of UI (icon grid + target cast bar) sharing one drag lock and one visibility mode, plus a settings panel with full slash-command parity (`/kcd list|get|set|reset|resetall|resetposition|spells|debug`). Every section below points at where the rules / models for one of those pieces live.

- [Overview](docs/CLAUDE_OVERVIEW.md) — what KickCD is, target version, and the cast-bar removal history.
- [12.0 secret-value protection](docs/CLAUDE_SECRET_VALUES.md) — **read first.** The rule for working with WoW 12.0 protected APIs (`C_Spell.GetSpellCooldown`, `UnitCastingInfo`, …); patterns that error and the preferred `CooldownDuration` workaround.
- [Module layout and boot order](docs/CLAUDE_MODULE_LAYOUT.md) — TOC load order; what each `core/` / `modules/` / `settings/` file is responsible for.
- [The closed message bus](docs/CLAUDE_MESSAGE_BUS.md) — the four AceEvent messages (`KickCD_SPELL_STATE`, `KickCD_CONFIG_CHANGED`, `KickCD_PROFILE_CHANGED`, `KickCD_GRID_LAYOUT`) and their payloads.
- [Icon grid layout model](docs/CLAUDE_ICON_GRID_LAYOUT.md) — anchor + grow + dimensions: how `modules/IconGrid.lua` places primary and secondary icons.
- [Settings panel](docs/CLAUDE_SETTINGS_PANEL.md) — schema-driven canvas layout; `KickCD.Settings.Schema` as single source of truth; widget primitives; custom-body tabs.
- [Cast bar module](docs/CLAUDE_CASTBAR.md) — secret-value-gated `UnitCastingInfo` / `UnitCastingDuration` handling; stacked dual widgets; per-state appearance via `C_CurveUtil.EvaluateColorValueFromBoolean`; anti-patterns to avoid.
- [Visibility + glow gating](docs/CLAUDE_SECRET_VALUES.md#cast-interruptibility-unitcastinginfo--unitchannelinfo) — the two-step gate behind `target_casting_interruptible` (Show on hostile cast, alpha-mask uninterruptible via `SetAlphaFromBoolean`). Same pattern in `IconGrid:ApplyInterruptibilityMask`, `Icon:UpdateGlow`, `Castbar:ApplyVisibilityMask`.
- [Frame mixin pattern](docs/CLAUDE_FRAME_MIXIN.md) — never `setmetatable` on a Blizzard widget; use `Mixin`.
- [Stale /docs/](docs/CLAUDE_DOCS_STALE.md) — caveats on `docs/*.md` predating cast-bar removal and 12.0 secret-value handling.
- [Testing](docs/CLAUDE_TESTING.md) — manual verification steps and slash-command coverage.
- [Conventions](docs/CLAUDE_CONVENTIONS.md) — code style and module-level rules.

For the current architecture (module map, data flow, saved-variable shape, Compat surface), see [ARCHITECTURE.md](ARCHITECTURE.md) and the `ARCHITECTURE_*.md` files it indexes.

