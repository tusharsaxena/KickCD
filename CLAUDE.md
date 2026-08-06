# CLAUDE.md — Ka0s KickCD

**Ka0s WoW addon.** Tracks the player's interrupt + CC cooldowns on a movable icon grid, with a sibling cast bar — for both the player's target and focus — sharing one drag-lock and visibility mode. Focus is on by default and links to target's appearance. Target client: WoW 12.0.7 (Midnight). English only. Ace3 throughout.

This addon adheres to the **Ka0s WoW Addon Standard** — <https://github.com/tusharsaxena/WowAddonStandards>. The TOC declares this via `## X-Standard:`, and the README carries the standard badge.

## Standards compliance (read first)

All development in this repo is measured against the Ka0s WoW Addon Standard (URL above) — structure, naming, conventions, packaging, testing. When doing any work here:

- **Flag every deviation from the standard.** If a change you're about to make — or existing code you notice — departs from the standard, **call it out explicitly**. Do not silently conform, and do not silently diverge. Then **let the user decide** whether it should be:
  1. an **intentional deviation** (recorded with a justifying comment, per the standard's SHOULD rule), or
  2. a signal that the **standard definition itself should change** to accommodate it.
- The user owns that decision — never resolve a standard conflict unilaterally.
- The current compliance baseline is the frozen audit bundle in `docs/audits/<date>/`. Re-run `/wow-addon:standards-audit` when in doubt; it fetches the living standard and writes a fresh dated bundle.

When in doubt, treat conformance as a hard requirement and ask.

## The `docs/` set — there is no `agent-context.md`

The canonical `docs/` set is exactly three files: **`ARCHITECTURE.md`** (what this addon is),
**`testing.md`** (how to verify) and **`smoke-tests.md`** (in-game checks) — plus the generated
`test-cases.md`, and the topic-detail docs — Tier 1 (`scope.md`, `module-map.md`, `schema.md`, `settings-panel.md`, `data-flow.md`, `common-tasks.md`) is always present, and `ARCHITECTURE.md` → `## Documentation map` lists the rest.

**`docs/agent-context.md` does not exist in this repo and MUST NOT be created.** The standard
deleted it in **v2.17.0**; shipping it is **anti-pattern #49**. It held `NEW_ADDON_CONTEXT.md` —
the scaffolding pack — which is fetched at runtime and never stored: a copy in the repo describes
the addon on the day it was born, forever, and because it loads as *working context* a stale copy
does not go quiet, it gets **followed** (documentation-§3). This root `CLAUDE.md` is the repo's
only agent brief.

Older audit bundles, review bundles, ledgers and plans under `docs/` predate v2.17.0 and still
name the file, and some describe a four-file or a pre-v2.3.0 `agent-context.md`-based set. Those
are **frozen history** — never treat them as a live requirement, and never "restore" the file.

## Full context lives in `docs/`

This root file is a stub (per standard documentation-§2). Read these before touching code:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — what this addon is: design overview, module map, namespace + module publishing pattern, message bus, slash commands, taint notes, invariants, and the `## Documentation map` listing every page under `docs/` (`documentation-§3`). **Start here.**
- **[docs/testing.md](docs/testing.md)** — how to verify: the headless harness, lint, the local toolchain, the vendored-copy diffs, and the slash/debug coverage matrices.
- **[docs/midnight-quirks.md](docs/midnight-quirks.md)** — required reading before touching cooldown/cast/visibility code (12.0 secret values).
- **[docs/common-tasks.md](docs/common-tasks.md)** — code style, chat-output rule, saved-variable boundary, line endings.

## Hard rules

- **Never auto-stage / commit / push.** The user controls `git add` / `commit` / `push`. Leave edits in the working tree; don't touch the index. (`/wow-addon:commit` is the one explicit exception.)
- **Never bump the version** (TOC `## Version`, `NS.VERSION` in `core/KickCD.lua`, README badge/history) without explicit instruction.
- **12.0 secret values**: never compare/format/`tostring`/do arithmetic on a value that might be secret (`C_Spell.GetSpellCooldown` timings; `UnitCastingInfo`/`UnitChannelInfo` `name`/`texture`/`notInterruptible`/`spellID`). Pass them straight into Blizzard C methods.
- **Closed message bus**: the five `Ka0s_KickCD_*` AceEvent messages are the only inter-module channel. Each receiver registers on its OWN AceEvent target (never the shared addon object).
- **Compat / State / Constants split**: `core/Compat.lua` = API normalization only; `core/State.lua` = shared state + visibility helpers; `core/Constants.lua` = magic numbers.
- **Five LibKa0s modules are adopted**, one setup file each: `core/CoreSetup.lua` (printer + secret seam), `core/DebugLogSetup.lua` (console), `core/PerfSetup.lua` (A/B capture), `settings/Slash.lua` (dispatcher + schema CLI), `settings/OptionsSetup.lua` (settings panel). **Never edit `libs/`** — a library problem is fixed upstream in `../LibKa0s` and re-vendored. The vendor gate is **two** diffs, run before every commit: `diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s` (content — MUST be empty; anything here is a fork) and `diff -r ../LibKa0s/LibKa0s libs/LibKa0s` (bytes — SHOULD be empty; a difference here alone is line-ending drift, renormalized, never fixed by editing `libs/`). Same pair for `../LibKa0s/testkit` ↔ `tests/_kit`. See [docs/testing.md](docs/testing.md).
- **Colors are stored keyed** (`{ r =, g =, b =, a = }`) and dropdown `values` are keyed hashes with a sibling `sorting` array — both are the library's vocabulary. Schema rows carry `desc` (not `tooltip`), `panel`, `section`, and `hasAlpha` on every color row.
- **`NS.Settings.Schema` is the single source of truth** for every option (one row → UI widget + `/kcd get|set|list` + Defaults reset). `NS` is the private addon namespace (`local addonName, NS = ...`) — there is no `_G.KickCD`.
- **Debug logging is session-only** (`NS.State.debug`, never in SavedVariables); it routes to the on-screen console (`LibKa0s-DebugLog-1.0`, wired in `core/DebugLogSetup.lua`), not chat. Toggle via the console header or `/kcd debug on|off|toggle`.
- **Keep the static README badges in lockstep with their sources** (standard documentation-§1 / testing-§5): the `[WoW]` and `[Tests]` badges are static and go stale silently, so each moves in the *same change* as its source of truth. `[WoW]` ↔ TOC `## Interface:` on every patch bump (both MUST show the same number). `[Tests]` ↔ the regenerated `docs/test-cases.md`: whenever the suite changes (a case added/removed/renamed or the pass count moves), regenerate via `lua tests/run.lua --list` **and** update the README `[Tests]` X/Y count together — never as a follow-up.

## Working style in this repo

- Terse: state the change, not the deliberation, and don't summarize what the diff already says. Point at code with `file_path:line_number`.
- Ship functional, defer polish — when core functionality lands, move on; polish is a later dedicated pass.
- Comment only the non-obvious *why* (subtle invariant, Blizzard quirk, hidden constraint), never what well-named code already says.
- Don't create docs or planning files unless asked.

## Local verification (standard testing)

- Unit tests: `lua tests/run.lua` (headless, exits non-zero on failure).
- Lint: `luacheck .` (0 warnings, 0 errors — the tree is clean on both).
- In-game: [docs/smoke-tests.md](docs/smoke-tests.md).

Run both before every commit.

- Toolchain install (WSL2/Ubuntu commands that work, with evidence per entry): [DEPENDENCIES.md](DEPENDENCIES.md). Keep it current in the same change that adds a script, an import or a tool.
- **Complexity — recorded at the commit, gating at the tag.** It is the `complexity` suite of the automated-test runner, which uses exactly `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .`. It never fails a run and never blocks a commit; it *does* gate the tag, which requires all four suites at `pass` plus zero functions above CCN 15. Read its diff in the same change that bumps the version, before the tag, and record anything newly over a threshold in the `## Complexity watch list` of [docs/automated-tests/RESULTS.md](docs/automated-tests/RESULTS.md). Standard performance-§10; the how and why are in [docs/testing.md](docs/testing.md#automated-test-records--the-consolidated-run).
