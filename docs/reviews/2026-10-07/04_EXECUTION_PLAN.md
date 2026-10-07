# 04 — Execution plan (KickCD, 2026-10-07 review)

This review feeds a cross-repo consolidation (`../Ka0sAddonsCommonTasks/docs/2026-10-07-…/`). The
task IDs below are local placeholders. The consolidated plan assigns the final `<ID>: ` commit
prefixes. All work happens on `feat/2026-10-07-review-audit-remediation`. Nothing merges, tags or
bumps a version without the owner's go-ahead.

## Milestones

### M0: decisions (owner or consolidator)

- Pick C-02's route: **A**, an upstream `LibKa0s-Core-1.0` member, or **B**, a local helper.
- Pick C-05's meaning: **(a)** any cast refreshes the gate, or **(b)** `target_casting` is hostile-only.
- Decide whether to take or decline C-04 and C-06. Both are optional (see `01_FINDINGS.md`).
- **Done when:** each decision is recorded in the consolidated plan.

### M1: correctness fixes (KickCD only)

| Task | Role | Implements | Files |
|---|---|---|---|
| K-T1 | lua-fixer + test-author | C-01 / F-001 | `modules/Castbar_Events.lua`, `tests/test_castbar_frame.lua`, `docs/test-cases.md`, `README.md` (badge) |
| K-T2 | lua-fixer + test-author | C-03, C-04 / F-003, F-004 | `core/KickCD.lua`, `tests/test_slash.lua`, `docs/slash-dispatch.md`, `docs/ARCHITECTURE.md`, `docs/test-cases.md`, `README.md` |
| K-T3 | lua-fixer + test-author | C-05 / F-005 | `modules/IconGrid_Visibility.lua`, `modules/IconGrid.lua` (`newInstance`), `tests/test_icongrid_glowgate.lua`, `docs/test-cases.md`, `README.md` |
| K-T4 | lua-fixer + test-author | C-06 / F-006 (if taken) | `modules/Cooldowns.lua`, `tests/test_cooldowns_refresh.lua`, `docs/test-cases.md`, `README.md` |

**Done when:** `ka0s-bounded lua5.1 tests/run.lua` is green, `luacheck .` is 0/0, the sighted
complexity run shows 0 warnings, and `docs/test-cases.md` and the badge match the new `--list` output.

### M2: locale-safe truncation (C-02)

- **Route A:**
  - **U-T1 (LibKa0s, cross-repo handoff):** add `lib.Utf8Prefix`, bump Core 10 → 11, add the library
    case, and release. This lands in `../LibKa0s`, not here.
  - **K-T5a:** `chore: re-vendor LibKa0s vX.Y.Z`, the whole folder, as its own commit
    (`/dev-copilot:wow-revendor-libka0s`).
  - **K-T5b:** adopt it in `modules/Castbar.lua`, with the degraded arm and tests.
- **Route B:** **K-T5:** a local helper in `modules/Castbar.lua` plus tests.
- **Done when:** the truncation tests are green, and on route A the re-vendor commit exists and
  `diff -rq libs/LibKa0s ../LibKa0s/LibKa0s` is empty.

### M3: hygiene and measurement

| Task | Role | Implements | Files |
|---|---|---|---|
| K-T6 | lint-cleanup | C-08 / F-008 | `.luacheckrc`, `tests/test_lintconfig.lua`, `docs/test-cases.md`, `README.md` |
| K-T7 | perf-author | C-09 / F-009 (measurement only) | `tests/perf.lua`, `docs/performance.md` (scenario row) |

**Done when:** lint is 0/0, the new perf scenario prints, and any `Util.Throttle` change is gated on
its figure (a separate follow-up task, if warranted).

### Deferred

C-07 / F-007. Re-check trigger: the first spec added to `defaults/Spells.lua` after 1.4.0.

## Critical path and concurrency

- **Every test-adding task touches `docs/test-cases.md` and `README.md`** (K-T1 through K-T6).
  **Serialize the regeneration.** Either run the tasks one after another, or let them run in parallel
  and have one final commit per milestone regenerate the inventory and badge. The first option is
  simpler and matches "same change" (`testing-§5`) literally, so it is the recommendation.
- `modules/IconGrid.lua` is touched by K-T3 only. `modules/Cooldowns.lua` by K-T4 only.
  `core/KickCD.lua` by K-T2 only. `modules/Castbar.lua` by K-T5 only. `modules/Castbar_Events.lua` by
  K-T1 only.
- Ignoring the shared docs, the code changes in K-T1, K-T2, K-T3, K-T4, K-T5 and K-T6 have **disjoint
  file sets**, so they could be written in parallel and committed serially.
- K-T5 (route A) depends on U-T1's release. Everything else is independent of upstream.

## Checkpoints

1. **After M0:** the decisions are recorded.
2. **After M1:** the green gate passes, then the owner runs smoke C-01, C-03/C-04, C-05 and C-06 in the
   client. Push the feature branch only if the owner has authorized it for this run.
3. **After M2:** on route A, confirm the re-vendor diff is clean and the cross-addon class 2 and class 3
   loops are still one line and empty across all 11 addons. Then the owner runs smoke C-02.
4. **After M3:** the green gate passes and the perf scenario output is recorded in the consolidated
   execution record.

## Incremental commits (one per task)

- `K-T1: cast bar drops a stale primary-icon anchor when the grid empties (F-001)`
- `K-T2: /kcd debug refuses without toggling; castbar/interrupt take a unit (F-003, F-004)`
- `K-T3: glow gate keys on any cast for the target_casting trigger (F-005)`
- `K-T4: Cooldowns ignores CONFIG_CHANGED{general} (F-006)`
- `K-T5: cast-bar name truncation counts characters (F-002)`, preceded on route A by
  `chore: re-vendor LibKa0s vX.Y.Z`
- `K-T6: .luacheckrc grants no read-global that shipped code never reads (F-008)`
- `K-T7: perf scenario for the cooldown-event coalescer (F-009)`

Each commit message ends with the session's attribution trailers.
