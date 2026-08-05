# KickCD — Execution Plan

**Date:** 2026-08-05
**Implements:** `02_PROPOSED_CHANGES.md` (C-001 … C-010) against `01_FINDINGS.md` (F-001 … F-012)
**Verified by:** `03_SMOKE_TESTS.md`

**Standing rule for every task below:** no task may edit a path under `libs/` or `tests/_kit/`.
Those folders are read-only copies; a local edit is reverted by the next re-vendor and returns as a
regression with no cause in this repo's history. This plan contains **no upstream milestone** —
the review found no defect in vendored code.

---

## Milestone M1 — The user-visible bug

**Done when:** a configured cast-bar spell-name color renders on the bar, on a migrated profile,
and survives `/reload`; the harness is 737+2 green; `docs/test-cases.md` and the README badge have
moved in the same commit.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| **T1.1** | lua-bugfixer | C-001 (F-001) | `modules/Castbar.lua` |
| **T1.2** | test-author | C-002 (F-001) | `tests/test_castbar.lua` *or* `tests/test_castbar_skin.lua`, `docs/test-cases.md`, `README.md` |

**Order.** T1.2 **first**, as a red test — it is the falsification, and writing it after the fix
loses the proof that it could ever go red. Then T1.1 turns it green.

**Watch item for T1.1.** Converting `INT_FALLBACK` / `UNINT_FALLBACK` to the keyed shape changes two
tables published as `Castbar.INT_FALLBACK` / `.UNINT_FALLBACK` (`modules/Castbar.lua:1304-1305`).
Grep `tests/test_castbar*.lua` for assertions on those tables before landing; any that assert
positional indices must be updated **because the shape genuinely changed**, never to make a red go
away.

---

## Milestone M2 — Instrumentation that measures what it claims

**Done when:** both early-exit brackets close, a generalized exit case is green and demonstrably
red under the mutation, and `Helpers.ResetAll` fires each section once.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| **T2.1** | lua-bugfixer | C-004 (F-005) | `modules/IconGrid_Render.lua`, `modules/Castbar.lua` |
| **T2.2** | test-author | C-005 (F-005) | `tests/test_perfsetup.lua`, `docs/test-cases.md`, `README.md` |
| **T2.3** | lua-refactorer | C-006 (F-004) | `settings/Panel_Render.lua` |
| **T2.4** | lua-bugfixer | C-007 (F-006) | `settings/Slash.lua`, `tests/test_color_shape.lua`, `docs/test-cases.md`, `README.md` |

**Order within M2.** T2.2 before T2.1 (red first, same reasoning as M1). T2.3 and T2.4 are
independent of both.

**Watch item for T2.3.** The degradation stub's own `RestoreAllDefaults`
(`settings/OptionsSetup.lua:187-196`) already calls `ResetAllPositions` + `RestoreUnitLinks`, so the
LibKa0s-absent path is unaffected. Confirm with the library-absent load
(`T.load(true, true, nil, { libFiles = {} })`) rather than by reasoning about it.

---

## Milestone M3 — Make the silent skip loud

**Done when:** a run without the sibling `LibKa0s` checkout prints a case name that says it skipped,
and a run with `KICKCD_REQUIRE_VENDOR_SYNC` set fails when the sibling is missing.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| **T3.1** | test-author | C-003 (F-002) | `tests/test_vendor_sync.lua`, `docs/test-cases.md` |

**Note.** Case *names* change, so the inventory must be regenerated even though the count does not
move. The README badge does **not** move.

---

## Milestone M4 — The perf evidence base

**Done when:** a real capture is committed under `docs/perf-runs/`, `docs/performance.md` interprets
it, `tests/perf.lua` runs offline with a zero-overhead scenario, and `core/PerfSetup.lua`'s figures
cite the record.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| **T4.1** | perf-engineer *(in-client, human)* | C-008 (F-007) | `docs/perf-runs/<date>-client-<label>.json` (new), `docs/perf-runs/README.md` |
| **T4.2** | perf-engineer | C-008 (F-007) | `tests/perf.lua` (new) |
| **T4.3** | doc-author | C-008 (F-007) | `docs/performance.md` (new), `core/PerfSetup.lua` (citation lines only) |

**Order.** T4.1 must precede T4.3 — the write-up interprets a record that must exist first.
T4.2 is independent of both.

**Constraints on T4.2.** No wall-clock assertion, ever. Load list derived from the TOC via
`tests/loader.lua`'s `readTOCOrder`, never hand-maintained. Scenarios are **not** test cases: they
must not appear in `docs/test-cases.md` and must not move the README `[tests]` badge.

**Constraint on T4.1.** `docs/perf-runs/` is append-only. Never delete, rewrite or tidy a capture.

---

## Milestone M5 — Adopt the vendored test kit

**Done when:** nothing under `tests/` re-implements a kit file, `lua5.1 tests/run.lua` reports the
same pass count as before the change, and `diff <(lua5.1 tests/run.lua --list) docs/test-cases.md`
is empty.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| **T5.1** | test-infra | C-009 (F-008) | `tests/run.lua` |
| **T5.2** | test-infra | C-009 (F-008) | `tests/loader.lua` |
| **T5.3** | test-infra | C-009 (F-008) | `tests/wow_mock.lua` |

**Order.** T5.2 → T5.1 → T5.3, and **strictly serial** — all three feed the same harness and any two
in flight together make a red impossible to attribute.

**Known behavior difference to plan for (T5.2).** The kit's `makeEnv`
(`tests/_kit/loader.lua:20-23`) installs a `__newindex` that routes sandbox writes to `_G`;
`tests/loader.lua:71-77` does not. SavedVariables globals and `StaticPopupDialogs` registrations will
start landing in `_G`. Expect suite churn in the migration and popup suites. Resolve it in the
harness. **Never edit a case to change a result, and never hand-edit `docs/test-cases.md`.**

**Hard boundary.** `tests/_kit/` is not edited by any task in this milestone. If the kit is missing
something, that is an upstream additive change to LibKa0s plus a re-vendor commit — a separate piece
of work in a separate repo, not a local copy.

---

## Milestone M6 — Hygiene

**Done when:** the four cosmetic items are corrected and `luacheck .` is still 0/0 over 32 files.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| **T6.1** | doc-author | C-010 (F-009) | `core/PerfSetup.lua` |
| **T6.2** | doc-author | C-010 (F-010) | `settings/Slash.lua`, `tests/test_coresetup.lua` |
| **T6.3** | lua-refactorer | C-010 (F-011) | `modules/Castbar.lua` |
| **T6.4** | lint-owner | C-010 (F-012) | `.luacheckrc` |

---

## Milestone M7 — The options-registration fork (deferred, its own decision)

**Done when:** exactly one page-registration mechanism exists, and no `NS.*` options forwarder is
exported without a consumer.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| **T7.1** | architect *(decision, no code)* | F-003 | — |
| **T7.2a** *(if adopt)* | lua-refactorer | C-003 route 1 | `settings/Panel.lua`, `settings/OptionsSetup.lua`, all six `settings/<page>.lua` |
| **T7.2b** *(if keep)* | lua-refactorer | C-003 route 2 | `settings/OptionsSetup.lua` only — delete the four unused forwarders, document why the library's registration is deliberately unwired |

**Why last and why gated.** T7.2a touches the panel every user opens and all six page files. It must
not ride along with the bug fixes; a regression there is expensive to attribute. T7.1 is a human
decision, not an agent task — the private bootstrap has behavior the library's may not replicate
(the `ADDON_LOADED == "Blizzard_Settings"` arm at `settings/Panel.lua:612`), and that has to be
checked against the library before choosing.

---

## Critical path and concurrency map

```
M1 (T1.2 → T1.1)  ──┐
M3 (T3.1)         ──┤
M6 (T6.1/2/4)     ──┼──► CHECKPOINT 1 ──► M2 ──► CHECKPOINT 2 ──► M4 ──► M5 ──► CHECKPOINT 3 ──► M7
                    │                      │
M6 (T6.3) ──────────┘   (serialized with M1: same file)
```

**Parallelizable (disjoint file sets):**
- T1.2, T3.1, T2.2 — three different `tests/test_*.lua` files. **But** all three touch
  `docs/test-cases.md` and two touch `README.md`, so regenerate the inventory **once**, after the
  last of them lands, in that same commit.
- T2.3 (`settings/Panel_Render.lua`) ∥ T2.4 (`settings/Slash.lua`) ∥ T2.1 (`modules/*`).
- T6.1 (`core/PerfSetup.lua`) ∥ T6.2 (`settings/Slash.lua` + a test) ∥ T6.4 (`.luacheckrc`).

**Must serialize:**
- **T1.1 and T6.3** both touch `modules/Castbar.lua` → T1.1 first, T6.3 after.
- **T2.1 and T1.1** both touch `modules/Castbar.lua` → M1 fully before M2's T2.1.
- **T2.4 and T6.2** both touch `settings/Slash.lua` → T2.4 first.
- **T5.1, T5.2, T5.3** — strictly serial among themselves, and **after** every test-authoring task
  in M1/M2/M3, so new cases are written against the framework they will finally run under.
- **T4.3 after T4.1** — the write-up needs the record.

---

## Checkpoints

**Checkpoint 1 — after M1, M3 and M6 (except T6.3).**
Human verifies: `luacheck .` is 0/0 over 32 files; the harness is green at the new count;
`diff <(lua5.1 tests/run.lua --list) docs/test-cases.md` is empty; the README badge matches.
Then run **C-001's in-client section of `03_SMOKE_TESTS.md`** — this is the one finding a user would
notice, and it should be confirmed before anything else moves.

**Checkpoint 2 — after M2.**
Human verifies the harness and then runs `03_SMOKE_TESTS.md` sections C-004, C-006 and C-007 plus
regression rows R-1, R-4, R-5, R-9. The reset path (C-006) is the highest-risk change in this plan;
do not proceed to M4 without it green.

**Checkpoint 3 — after M5.**
Human verifies the harness reports the **same** pass count as at Checkpoint 2 and the inventory diff
is empty. A kit adoption that moves the pass count has changed behavior, and that has to be explained
before it lands.

**Checkpoint 4 — before M7.**
Architectural decision (T7.1) is written down — with its reason — before any code moves.

---

## Incremental commit strategy

One commit per task, except where a shared generated artifact forces a merge.

| Commit | Contents | Suggested message |
|---|---|---|
| 1 | T1.2 (red) + T1.1 (green) + inventory + badge | `castbar: honor the configured spell-name color (F-001)` |
| 2 | T3.1 + inventory | `tests: name the vendor-sync skip instead of passing silently (F-002)` |
| 3 | T6.1, T6.2, T6.4 | `docs/lint: correct a stale exit count, a dangling citation and a removed-API allowance (F-009, F-010, F-012)` |
| 4 | T6.3 | `castbar: drop the unread NS.Castbar export (F-011)` |
| 5 | T2.2 (red) + T2.1 (green) + inventory + badge | `perf: close the cdText and castTick brackets on their early exits (F-005)` |
| 6 | T2.3 | `settings: let afterRestoreAll own the non-schema reset (F-004)` |
| 7 | T2.4 + inventory + badge | `slash: restore the gate-hint probe even when values() raises (F-006)` |
| 8 | T4.1 | `perf-runs: commit the capture the bucket design cites (F-007)` |
| 9 | T4.2 | `tests: add the offline perf scenarios, incl. the zero-overhead case (F-007)` |
| 10 | T4.3 | `docs: performance write-up, and cite the record from PerfSetup (F-007)` |
| 11 | T5.2 | `tests: load through the vendored kit loader (F-008)` |
| 12 | T5.1 | `tests: run on the vendored kit framework (F-008)` |
| 13 | T5.3 | `tests: build the mock on the vendored mock_base (F-008)` |
| 14 | T7.2a or T7.2b | `settings: one options-registration path (F-003)` |

Commits 1–7 and 14 change behavior or coverage and therefore move `docs/test-cases.md` and/or the
README badge **in the same commit** — never as a follow-up. Commits 8–10 touch no test case and must
not move either.
