# CLAUDE.md — Ka0s KickCD

**Ka0s WoW addon.** Adheres to the **Ka0s WoW Addon Standard** —
https://github.com/tusharsaxena/WowAddonStandards

## Standards compliance (read first)

This repo is built to the **Ka0s WoW Addon Standard** (URL above). All development here — features,
refactors, doc changes — MUST conform to it. The standard is the source of truth for layout, TOC
shape, the Ace substrate, schema-driven settings, slash/prefix conventions, locales, Compat,
tests/lint, and doc structure.

**If a change would deviate from the standard, STOP and flag the deviation explicitly.** Do not
silently deviate and do not silently "fix" to match. Surface it and let the user decide which of
two things it is:

1. **An accepted deviation** — this addon intentionally differs; record it as a row in
   `docs/ARCHITECTURE.md` → `## Documented deviations`, shaped
   `| Rule | What differs | Why | Decided | Re-check trigger |`, where Rule is the `filename-§N`
   reference. That register is the single home: the reasoning may live in the issue-audit GitHub
   issue or an audit bundle and the row cites it, but a deviation not in the register is not ratified.
2. **A change to the standard itself** — the standard's definition should evolve; the update
   belongs upstream in the WowAddonStandards repo, after which this addon conforms to the new rule.

When in doubt, treat standard conformance as a hard requirement and ask.

Start here, then read the docs:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — what this addon is: overview, module map,
  namespace pattern, invariants, dependencies, message bus, slash commands, taint notes, the
  `## Documentation map` and the documented deviations.
- **[docs/testing.md](docs/testing.md)** — how to verify: the headless harness, lint, the
  vendored-copy diffs, the automated-test records and the coverage matrices.
- **[docs/midnight-quirks.md](docs/midnight-quirks.md)** — required reading before touching
  cooldown, cast or visibility code (12.0 secret values).
- **[docs/common-tasks.md](docs/common-tasks.md)** — recipes and house rules (working style, code
  style, chat output, saved variables, line endings).
- Topic detail in `docs/` as needed (`schema.md`, `settings-panel.md`, `smoke-tests.md`, …).

Green gate before every commit: `lua tests/run.lua` and `luacheck .` (0/0). Never auto-stage/commit/push and never bump the version without an explicit instruction.

Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.57.0 (MIT).
