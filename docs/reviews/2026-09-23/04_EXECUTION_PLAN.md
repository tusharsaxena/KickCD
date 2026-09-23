# 04 — Execution plan

Ordering rule: **upstream first**. The LibKa0s change (U-001) lands and is tagged, and the whole folder is re-vendored, before any KickCD task that depends on the library's behavior. KickCD's own C-04 is independent and may land early.

Every commit's gate is `lua tests/run.lua` green plus `luacheck .` at 0/0, run through `ka0s-bounded`. Any commit that moves the pass count also moves `docs/test-cases.md` (via `--list`) and the README `[tests]` badge in that same commit.

## M0 — Upstream (LibKa0s repo) — cross-repo handoff

| Task | Owner role | Implements | Files (LibKa0s repo) |
|---|---|---|---|
| M0-T1 | lib-maintainer | U-001 | `LibKa0s/OptionsWidgets.lua` (library-local armed flag for the color and slider throttles), `LibKa0s/Options.lua` (descriptor doc for `scheduleTimer`), a new LibKa0s test with a nil-returning `scheduleTimer` |
| M0-T2 | lib-maintainer | U-001 | Minor bump(s), `CHANGELOG.md`, release tag |

**Done when:** LibKa0s is tagged with the fix and its own suite is green.

**Checkpoint CP0:** a human confirms the tag exists on origin.

## M1 — Re-vendor (this repo)

| Task | Owner role | Implements | Files |
|---|---|---|---|
| M1-T1 | vendor-sync | U-001 follow-up | `libs/LibKa0s/**` (whole folder), `tests/_kit/**` (whole folder), `CLAUDE.md` provenance line |

**Done when:** `tests/test_vendor_sync.lua` is green against the new tag, and `diff -rq libs/LibKa0s ../LibKa0s/LibKa0s` is empty. This is a **single commit** containing only the re-vendor. The same re-vendor goes to every other consumer as separate work in each repo; LootHistory and MultiMeters are directly affected.

## M2 — Data correctness (High)

| Task | Owner role | Implements | Files |
|---|---|---|---|
| M2-T1 | savedvars-engineer | C-01 (F-001), C-11 part | `core/Database.lua`, `tests/wow_mock.lua` (AceDB `SetProfile`), `tests/test_color_shape.lua`, `docs/ARCHITECTURE.md` (register row wording), `docs/schema.md` |
| M2-T2 | ui-engineer | C-02 (F-002), C-11 part | `settings/Spells.lua` (row builders only), `tests/test_settings_spells_editor.lua` |

M2-T1 and M2-T2 have disjoint file sets and are **parallelizable**.

**Done when:** both new cases are red on the old code and green on the new; the suite is green.

**Checkpoint CP2:** a human runs smoke tests C-01 and C-02 in client.

## M3 — Lifecycle, frames and throttles (Medium)

| Task | Owner role | Implements | Files |
|---|---|---|---|
| M3-T1 | wow-api-engineer | C-03 (F-003, F-006) | `core/Util.lua`, `modules/IconGrid.lua` (EnableUnit/DisableUnit/Suspend/Resume), `modules/Castbar.lua` (same), `tests/test_disabled.lua`, `docs/ARCHITECTURE.md`, `docs/midnight-quirks.md` (EMPOWER note) |
| M3-T2 | settings-engineer | C-04 (F-004) | `settings/OptionsSetup.lua`, `tests/test_options_panel.lua` or a new case |
| M3-T3 | lua-refactorer | C-06 (F-007) | `modules/Cooldowns.lua` (`StateFor`), `modules/IconGrid.lua` (`seedIcon`, `:340-353`), `tests/test_icongrid_buildlist.lua` |

**Concurrency:** M3-T1 and M3-T3 both touch `modules/IconGrid.lua`, so they must **serialize**, T1 then T3. M3-T2 is disjoint and **parallelizable** with either.

**Done when:** the frame count is flat across cycles in the suite, the throttle case is green and the replay case is green.

**Checkpoint CP3:** smoke tests C-03, C-04 and C-06 in client, including the EMPOWER half if an Evoker is available.

## M4 — Spells surfaces (Medium)

| Task | Owner role | Implements | Files |
|---|---|---|---|
| M4-T1 | lua-refactorer | C-05 (F-005, F-018) | new `core/SpellInput.lua`, `KickCD.toc` (new line plus comment; read neighbors' comments, #66), `core/KickCD.lua` (`:570-639`, `:764`), `settings/Spells.lua` (`:272-485` cache and validation removed), `core/Database.lua` (`AddSpell` class check), `tests/test_slash.lua`, `tests/test_spell_registry.lua` |
| M4-T2 | ui-engineer | C-07 (F-008) | `settings/Spells.lua` (`doCommit`, `RefreshRows`) |
| M4-T3 | lua-refactorer | C-09 (F-010) | `settings/Spells.lua` → `settings/Spells_Rows.lua`, `KickCD.toc` |

**Concurrency:** every task in M4 touches `settings/Spells.lua` and must **serialize**, T1 → T2 → T3. T3 is the mechanical peel and goes last, so it moves final code. M4-T1 also touches `core/Database.lua` (as M2-T1 did), so it runs after M2.

**Done when:** the suite is green, `settings/Spells.lua` is under 1000 LOC, and the CLI and panel refusals are identical.

**Checkpoint CP4:** smoke tests C-05, C-07, C-09 and a localization pass on C-05.

## M5 — Evidence and hygiene (Medium/Low)

| Task | Owner role | Implements | Files |
|---|---|---|---|
| M5-T1 | perf-engineer | C-08 (F-009) | `modules/Cooldowns.lua` (bracket the Rebuild emit), `docs/performance.md`, `tests/test_perfsetup.lua` |
| M5-T2 | docs-cleanup | C-10: F-012, F-014 | `core/KickCD.lua` (comments), `modules/Cooldowns.lua` (comments), `core/Util.lua` (comment), `settings/Spells.lua` (comment), `settings/Panel_Render.lua` (`ResetIconPosition`), `README.md:97` |
| M5-T3 | lua-refactorer | C-10: F-013, F-015, F-017 | `modules/Cooldowns.lua`, `core/Units.lua`, `settings/Slash.lua`, `core/State.lua`, `tests/test_disabled.lua` |
| M5-T4 | lint-owner | C-10: F-016 | `.luacheckrc`, `tests/test_lintconfig.lua` |

**Concurrency:** M5-T1, M5-T2 and M5-T3 all touch `modules/Cooldowns.lua`, so they **serialize** T1 → T3 → T2. M5-T4 is disjoint and **parallelizable**.

**Done when:** the suite and lint are green, and `docs/performance.md`'s table matches `core/PerfSetup.lua` row for row.

**Checkpoint CP5:** the full regression suite in `03_SMOKE_TESTS.md`, plus the C-08 two-arm capture committed as a `docs/perf-analysis/` bundle.

## Critical path

M0 → M1 (re-vendor) → M2 → M3 (T1 then T3) → M4 (T1 → T2 → T3) → M5 → CP5.

C-04 (M3-T2) and M5-T4 can land any time after M1.

## Commit strategy (one task, one commit)

| Task | Suggested message |
|---|---|
| M1-T1 | `Re-vendor LibKa0s vX.Y.Z whole (OptionsWidgets throttle ignores host timer handle)` |
| M2-T1 | `Run the color and font-flag migrations on every profile load, not once per account` |
| M2-T2 | `Stop hooking pooled AceGUI frames on the Spells page` |
| M3-T1 | `Reuse one unit-filter frame per unit across disable/enable; track empowered casts` |
| M3-T2 | `Return a cancellable handle from scheduleTimer` |
| M3-T3 | `Seed rebuilt icons from Cooldowns' last state instead of a synthetic ready` |
| M4-T1 | `One spell-input resolver for the CLI and the Spells page` |
| M4-T2 | `Render the Spells page once per commit; never leave the render guard stuck` |
| M4-T3 | `Peel the Spells row builders into settings/Spells_Rows.lua` |
| M5-T1 | `Bracket the Rebuild emit and bring docs/performance.md in line with the descriptor` |
| M5-T2 | `Correct stale comments and the resetposition/README wording` |
| M5-T3 | `One reader of the master switch; read-only gate probe; no dead PLAYER_LOGIN` |
| M5-T4 | `Drop deprecated globals from the lint allow-list` |

Commits end with the session attribution lines. The branch is `feat/2026-09-23-review-audit-remediation`. Pushing and merging follow the workflow owner's instructions; this plan does not merge.
