# Architecture

Reference document for KickCD's current shape (post-cast-bar-removal, 12.0-aware). This reflects the codebase as of commit `59fb5c0` and supersedes the design discussion in `docs/TECHNICAL_DESIGN.md` where the two diverge.

This file is an index — each section lives in its own file.

- [Purpose](docs/ARCHITECTURE_PURPOSE.md) — what KickCD does at a glance.
- [Module map](docs/ARCHITECTURE_MODULE_MAP.md) — directory tree (`core/` / `defaults/` / `modules/` / `settings/`) and external dependencies.
- [Boot sequence](docs/ARCHITECTURE_BOOT_SEQUENCE.md) — TOC file-load → `OnInitialize` → `OnEnable` → `PLAYER_LOGIN`.
- [Data flow](docs/ARCHITECTURE_DATA_FLOW.md) — game event → `Cooldowns:Refresh` → `KickCD_SPELL_STATE` → `IconGrid:Apply`; user-input flow through `Helpers.Set`.
- [Settings UI framework](docs/ARCHITECTURE_SETTINGS_UI.md) — canvas-layout panel chrome, the `Schema` table, custom-body tabs, widget binding.
- [Closed message contract](docs/ARCHITECTURE_MESSAGE_CONTRACT.md) — full sender/listener/payload table for the AceEvent messages.
- [Saved variables](docs/ARCHITECTURE_SAVED_VARIABLES.md) — `KickCDDB` AceDB store and `DEFAULT_PROFILE` shape.
- [Compat layer](docs/ARCHITECTURE_COMPAT_LAYER.md) — wrapped spell + settings APIs and their 12.0 caveats.
- [Lock and anchor](docs/ARCHITECTURE_LOCK_ANCHOR.md) — drag lock, anchor save/restore, lock touch points.
- [Slash dispatch](docs/ARCHITECTURE_SLASH_DISPATCH.md) — `COMMANDS` / `DEBUG_COMMANDS` tables and the schema-driven `list` / `get` / `set` commands.
- [Conventions](docs/ARCHITECTURE_CONVENTIONS.md) — saved-variable boundary, anchor format, secret-value rule of thumb.

For the agent-oriented guide (rules, anti-patterns, testing), see [CLAUDE.md](CLAUDE.md) and the `CLAUDE_*.md` files it indexes.
