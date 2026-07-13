# CLAUDE.md — Ka0s KickCD

**Tier 2** (modular) WoW addon. Tracks the player's interrupt + CC cooldowns on a movable icon grid, with a sibling target cast bar sharing one drag-lock and visibility mode. Target client: WoW 12.0.7 (Midnight). English only. Ace3 throughout.

This addon adheres to the **Ka0s WoW Addon Standard** — <https://github.com/tusharsaxena/WowAddonStandards>. The TOC declares this via `## X-Standard:`, and the README carries the standard badge.

## The standard is the source of truth

All development in this repo is measured against the Ka0s WoW Addon Standard (URL above) — structure, naming, conventions, packaging, testing. When doing any work here:

- **Flag every deviation from the standard.** If a change you're about to make — or existing code you notice — departs from the standard, **call it out explicitly**. Do not silently conform, and do not silently diverge. Then **let the user decide** whether it should be:
  1. an **intentional deviation** (recorded with a justifying comment, per the standard's SHOULD rule), or
  2. a signal that the **standard definition itself should change** to accommodate it.
- The user owns that decision — never resolve a standard conflict unilaterally.
- The current compliance baseline is the frozen audit bundle in `audit/<date>/`. Re-run `/wow-addon:standards-audit` when in doubt; it fetches the living standard and writes a fresh dated bundle.

## Full agent context lives in `docs/`

This root file is a stub (per standard §15.2). Read these before touching code:

- **[docs/agent-context.md](docs/agent-context.md)** — the full working-notes brief: hard rules, module publishing pattern, doc index, working environment. **Start here.**
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — design overview, module map, message bus, slash commands, taint notes, invariants.
- **[docs/midnight-quirks.md](docs/midnight-quirks.md)** — required reading before touching cooldown/cast/visibility code (12.0 secret values).

## Hard rules (full text in [docs/agent-context.md](docs/agent-context.md))

- **Never auto-stage / commit / push.** The user controls `git add` / `commit` / `push`. Leave edits in the working tree; don't touch the index. (`/wow-addon:commit` is the one explicit exception.)
- **Never bump the version** (TOC `## Version`, `KickCD.VERSION`, README badge/history) without explicit instruction.
- **12.0 secret values**: never compare/format/`tostring`/do arithmetic on a value that might be secret (`C_Spell.GetSpellCooldown` timings; `UnitCastingInfo`/`UnitChannelInfo` `name`/`texture`/`notInterruptible`/`spellID`). Pass them straight into Blizzard C methods.
- **Closed message bus**: the five `Ka0s_KickCD_*` AceEvent messages are the only inter-module channel. Each receiver registers on its OWN AceEvent target (never the shared addon object).
- **Compat / State / Constants split**: `core/Compat.lua` = API normalisation only; `core/State.lua` = shared state + visibility helpers; `core/Constants.lua` = magic numbers.
- **`KickCD.Settings.Schema` is the single source of truth** for every option (one row → UI widget + `/kcd get|set|list` + Defaults reset).
- **Debug logging is session-only** (`KickCD.State.debug`, never in SavedVariables); it routes to the on-screen console (`modules/DebugLog.lua`), not chat. Toggle via the console header or `/kcd debug on|off|toggle`.

## Local verification (standard §14A)

- Unit tests: `lua tests/run.lua` (headless, exits non-zero on failure).
- Lint: `luacheck .` (0 errors).
- In-game: [docs/smoke-tests.md](docs/smoke-tests.md).

Run both before every commit.
