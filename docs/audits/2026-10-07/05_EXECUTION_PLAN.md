# KickCD — Execution plan (2026-10-07)

This is the hand-off to the remediation engagement. Every step names the deviation id it closes and
how to check it is done. The gate after any Lua edit is: `~/.claude/dev-copilot/bin/ka0s-bounded lua
tests/run.lua` (0 failed), `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` (0/0), and
`~/.claude/dev-copilot/bin/ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity
--no-bundle` (0 warnings).

**Totals being closed:** 7 roots (4 Low MUST, 3 Info), 0 dependents.

## Sprint 1 — records (no code)

| # | Step | Closes | Done when |
|---|---|---|---|
| 1.1 | Write `docs/revendor/<date>-v1.68.1-v1.70.0/01_DELTA.md`. Line 1 is exactly `Delta: LibKa0s v1.68.1 -> v1.70.0 (span: v1.68.1 v1.69.0 v1.70.0)`, with the payload diff between `7b29045` and `9d4a10b` summarized beneath it. | `KICKCD-C-01` | `AUDIT.md`'s step-4 re-vendor loop prints `count 0` |
| 1.2 | Write `05_SUMMARY.md` for the same bundle, one line per tag. v1.69.0: carried by sweep, nothing adopted. v1.70.0: carried, nothing adopted, `Autocomplete` noted as a Spells add-box candidate. | `KICKCD-C-01` | Both files exist, and no other file is in the folder |
| 1.3 | Comment on GitHub #11, recording that `RenderGrid` was adopted (`e0da04c`, KickCD#10). It stays closed. | `KICKCD-D-02` | `gh issue view 11 --json comments` shows the comment |

## Sprint 2 — docs and comments

| # | Step | Closes | Done when |
|---|---|---|---|
| 2.1 | `docs/ARCHITECTURE.md:79-83`: add `settings/OptionsSetup.lua` to the `addonName` readers and correct or drop the counts (9 / 41). | `KICKCD-C-08` (1) | The list matches `git ls-files '*.lua' \| grep -vE '^(libs/\|tests/)' \| xargs grep -l '^local addonName, NS = \.\.\.'` |
| 2.2 | `.luacheckrc:25-29`: re-word the `M4c-06` history so it stops asserting a current count, or correct it. | `KICKCD-C-08` (2) | `luacheck .` still 0/0, and the comment holds no count the tree contradicts |
| 2.3 | `docs/compat-layer.md:34`: "bootstrap `CreateFrame`" → "combat listener, an AceEvent target". | `KICKCD-C-08` (3) | `git grep -n 'bootstrap .CreateFrame' -- docs` is empty |
| 2.4 | `.pkgmeta:22-23`: re-measure the tracked ignored payload, or drop the figure. | `KICKCD-C-08` (4) | The comment matches `git ls-files media/screenshots CLAUDE.md DEPENDENCIES.md \| xargs du -cb` |
| 2.5 | Qualify the four doc sites: `docs/settings-panel.md:62` (`options-ui-§7`), `:203` (`options-ui-§14`), `docs/slash-dispatch.md:70` and `:97` (`slash-commands-§7`). | `KICKCD-C-15` (docs half) | E4's command prints no `docs/settings-panel.md` or `docs/slash-dispatch.md` line |

## Sprint 3 — Lua (green gate after each step)

| # | Step | Closes | Done when |
|---|---|---|---|
| 3.1 | Qualify the 13 test-comment sites: `tests/test_flow_traces.lua` (12) and `tests/test_library_lines.lua:97`. | `KICKCD-C-15` (tests half) | E4's command prints only `docs/smoke-tests.md`. `lua tests/run.lua --list` diff against `docs/test-cases.md` is empty |
| 3.2 | (Optional) Add a `tests/test_source_style.lua` case enforcing qualified `§N` over authored Lua and live docs, with `docs/smoke-tests.md`'s legacy table excluded by name. | `KICKCD-C-15` (guard) | The case is red when one bare `§9` is re-inserted, and green after. Regenerate `docs/test-cases.md` and the README Tests badge in the same commit (`testing-§5`) |
| 3.3 | Publish `NS.SCHEMA_VERSION = 5` in `core/Database.lua`. Repoint `core/Database_Migrations.lua:18`, `modules/Diagnostics.lua:103-104` and any test reading `CURRENT_DB_VERSION`. Drop the `Database.CURRENT_DB_VERSION` alias if nothing still needs it. | `KICKCD-D-01` | `git grep -n 'SCHEMA_VERSION' -- core` finds the definition. The gate is green |
| 3.4 | Add a `tests/test_database.lua` case pinning `NS.SCHEMA_VERSION` to the highest migration step's `to`. Regenerate `docs/test-cases.md` and the Tests badge. | `KICKCD-D-01` | The case goes red if `NS.SCHEMA_VERSION` is set to 4 or 6. The badge and inventory agree with the run |

## Sprint 4 — upstream and release (not this repo's commits)

| # | Step | Closes | Done when |
|---|---|---|---|
| 4.1 | File a LibKa0s `testkit` issue. The diagnostics contract's opt-out case registers only for an opted-out host, or `--list` reports skips separately, so the inventory total stops folding the always-skipped case (`testing-§5`). | `KICKCD-D-03` | LibKa0s ships the fix. After the re-vendor, `docs/test-cases.md`'s Total equals the badge's `<Y>` |
| 4.2 | At the next release, run `/dev-copilot:wow-automated-tests` for a sighted bundle on kit 37 or later, with `suites.complexity.blindFiles` equal to `0`. | `KICKCD-B-04` | `RESULTS.md`'s newest row is within a few commits of the release tag, and its manifest carries `blindFiles: 0` |

## Out of scope for this plan

- The eight register rows are all accepted. None is retired or rewritten by this plan.
- Open feature and bug issues (#1 to #5, #34, #35) are product backlog, not standard deviations.
- No version bump, tag or release. Those are the owner's call.
