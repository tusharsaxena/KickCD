# KickCD — Execution Plan (2026-08-03 review)

Implements `02_PROPOSED_CHANGES.md`. Trunk-based per `versioning-git` — **do not create a branch**
unless the user explicitly asks. Commit only on green (`luacheck .` clean **and** `lua tests/run.lua`
zero failures), per anti-pattern #23.

**No milestone in this plan edits anything under `libs/` or `tests/_kit/`.** There are no upstream
findings in this pass, so there is no cross-repo handoff milestone and no re-vendor commit.

---

## Milestone M0 — Baseline and safety net

**Done when:** the pre-change gates are recorded and a test exists for every invariant M1 will move.

| Task | Owner-agent | Implements | Files touched |
|---|---|---|---|
| T-0.1 | `qa-harness` | — | (none — record only) |
| | Run `luacheck .` and `lua tests/run.lua`; record the exact counts (expected `0 warnings / 0 errors`, `648 passed, 0 failed`) into the run log. | | |
| T-0.2 | `qa-harness` | F-001 pre-work | `tests/test_options_panel.lua` |
| | Add a case asserting `NS.Settings.Helpers.EnsureScroll`, `.AddSpacer`, `.AttachTooltip` and `.LSMValues` are **the library's** — e.g. by asserting `LSMValues("font")` returns a `function`, and that `AddSpacer` returns a truthy widget. This case must go **red** before M1 and green after; a case that passes either way is not testing the invariant. | | |
| T-0.3 | `qa-harness` | F-008 pre-work | `tests/test_perfsetup.lua` |
| | Extend the existing "every PollSpell exit is measured" case to cover `Castbar`'s `onUpdate`; must go red before C-07. | | |
| T-0.4 | `qa-harness` | F-010 pre-work | `tests/test_locale.lua` |
| | Add a **bidirectional** key-set assertion: every `L[...]` reference resolves to a defined key, and every defined key has at least one reference. Must go red before C-10 (it will name the ten orphans). | | |

**Exit criterion:** T-0.2, T-0.3 and T-0.4 are each demonstrably **red**, and everything else is green.
Screenshot or paste the failing output — it is the evidence that M1–M3's tests test something.

**Checkpoint CP-0 (human):** confirm the three new cases fail for the stated reason, not for a typo.

---

## Milestone M1 — Finish the LibKa0s-Options de-duplication

The largest and riskiest milestone. Everything here touches `settings/`, so **all of M1 is serial**.

| Task | Owner-agent | Implements | Files touched |
|---|---|---|---|
| T-1.1 | `lua-refactorer` | C-01 (member deletion) | `settings/Panel.lua` |
| | Delete `attachTooltip`+publication, `ensureScroll`+publication, `addSpacer`+publication, `Helpers.LSMValues`. Repoint the file's own internal callers (`BuildMainContent`, the `addBlock` neighbours) to `Helpers.EnsureScroll` / `Helpers.AddSpacer`. | | |
| T-1.2 | `lua-refactorer` | C-01 (call-site sweep) | `settings/Icons.lua`, `settings/Castbar.lua`, `settings/Label.lua` |
| | Rewrite the eight `values = function() return H.LSMValues(m) end` sites to `values = H.LSMValues(m)` — the library returns the closure the row wants. Grep for `LSMValues` afterwards; zero wrapping closures must remain. | | |
| T-1.3 | `lua-refactorer` | C-01 (sibling callers) | `settings/Panel_Render.lua`, `settings/Panel_Widgets.lua` |
| | Confirm `addSpacer` / `attachTooltip` locals in these two files resolve to the library's members (they read off `Helpers`, so this is a verification task plus any upvalue fix). | | |
| T-1.4 | `lua-refactorer` | C-02 | `core/Constants.lua`, `settings/Panel.lua` |
| | Delete `Const.PANEL_PADDING_X` and `local ROW_VSPACER = 8` / `Helpers.ROW_VSPACER = …`. Introduce `MAIN_PADDING_X` beside the other `MAIN_*` landing-page constants (`options-ui-§8`'s landing-page carve-out). Rewrite the stale comment at `Panel.lua:300-306`. | | |
| T-1.5 | `wow-api-migrator` | C-05 | `settings/Panel.lua`, `settings/Panel_Widgets.lua`, `settings/Panel_Render.lua` |
| | Make the three AceGUI resolutions silent + instance-sourced, and add `if not AceGUI then return end` to **every** widget-creating function in the three files. Enumerate them with `grep -n "AceGUI:Create"` and tick each off. | | |
| T-1.6 | `lua-refactorer` | C-03 | `settings/OptionsSetup.lua` |
| | **Re-measure first**, then write. Run the library-absent load (T-0.2's harness path) and compare `#NS.Settings.Schema` against the loaded environment. If C-01 opened a load-time hole, grow the stub back by exactly the member the measurement names (`LSMValues`, returning a closure yielding an empty table). Only then correct the two comment blocks to describe the measured reality. | | |

**Concurrency:** T-1.1 → T-1.2 → T-1.3 → T-1.4 → T-1.5 → T-1.6, strictly serial. T-1.1/T-1.4/T-1.5 all
touch `settings/Panel.lua`; T-1.5 also touches the two files T-1.3 verifies; T-1.6 depends on the
outcome of every prior task. **Nothing in M1 is parallelizable.**

**Exit criterion:** `luacheck .` clean; `lua tests/run.lua` green **including T-0.2's case now passing**;
`grep -rn "ensureScroll\|addSpacer\|attachTooltip\|Helpers.LSMValues *=" settings/` returns nothing.

**Checkpoint CP-1 (human, in-client):** run smoke tests **C-01, C-02, C-03, C-05** plus regression
**R-1, R-6, R-7** before proceeding. M1 is the change most likely to need a visual judgement call
(dropdown fallback label, row spacing), and no later milestone should stack on top of an unverified
panel.

---

## Milestone M2 — Secret-value and correctness fixes

| Task | Owner-agent | Implements | Files touched |
|---|---|---|---|
| T-2.1 | `wow-api-migrator` | C-04 | `core/Compat.lua` |
| | Replace `safeRender`'s body with a delegation to `NS.SafeToString`. Leave `describe()`'s `isSecret=` column on `issecretvalue` — that is reporting, not stringification. | | |
| T-2.2 | `wow-api-migrator` | C-04 | `modules/Castbar_Debug.lua` |
| | Apply the same substitution at `:45`'s stringification. | | |
| T-2.3 | `lua-refactorer` | C-06 | `settings/Slash.lua` |
| | `pcall` the `allowedKeys(row)` probe so the restore always runs. | | |
| T-2.4 | `lua-refactorer` | C-07 | `modules/Castbar.lua` |
| | Close the `castTick` bracket on the `not d` early return. | | |
| T-2.5 | `ux-cleanup` | C-08 | `modules/Castbar_Debug.lua` |
| | Give the secret-`notInterruptible` branch an unconditional line. | | |

**Concurrency map:**
- T-2.2 and T-2.5 both touch `modules/Castbar_Debug.lua` → **must serialize** (T-2.2 then T-2.5).
- T-2.1, T-2.3, T-2.4 touch disjoint files (`core/Compat.lua`, `settings/Slash.lua`,
  `modules/Castbar.lua`) → **parallelizable** with each other and with the Castbar_Debug chain.
- No file in M2 overlaps any file in M1, so M2 could in principle start before CP-1 — **do not**.
  T-2.3 touches `settings/`, and keeping the settings folder single-owner through CP-1 is what makes
  a CP-1 failure attributable.

**Exit criterion:** `luacheck .` clean; `lua tests/run.lua` green **including T-0.3's case now passing**.

**Checkpoint CP-2 (human, in-client):** run smoke tests **C-04, C-06, C-07, C-08** and taint tests
**T-1…T-4**. C-04 must be exercised **in combat** — out of combat it proves nothing, because nothing is
secret.

---

## Milestone M3 — Hygiene

| Task | Owner-agent | Implements | Files touched |
|---|---|---|---|
| T-3.1 | `ux-cleanup` | C-09 | `.pkgmeta` |
| T-3.2 | `ux-cleanup` | C-10 | `locales/enUS.lua` |
| T-3.3 | `docs-editor` | C-11 | `docs/message-bus.md` |
| T-3.4 | `docs-editor` | roll-up | `README.md`, `KickCD.toc`, `docs/pending/LEDGER.md` |
| | If the work ships as a release: bump `## Version:` and `NS.VERSION` together, add the Version History row, and roll `## What's new in <X.Y.Z>` forward **in the same change** (anti-pattern #40, `versioning-git`). If it ships as an unreleased maintenance commit, do none of this. | | |

**Concurrency:** T-3.1, T-3.2, T-3.3 touch three disjoint files → **fully parallelizable**. T-3.4 must
run **last** (it summarizes the others).

**Exit criterion:** `luacheck .` clean; `lua tests/run.lua` green **including T-0.4's case now passing**;
`grep -n "superpowers" .pkgmeta` non-empty.

**Checkpoint CP-3 (human):** run smoke tests **C-09, C-10, C-11**, the full regression table
**R-1…R-13**, the localization pass, and the perf spot-checks. Fill in the sign-off table in
`03_SMOKE_TESTS.md`.

---

## Critical path

```
M0 (serial, gate)
  └─> M1 (fully serial — all of settings/) ──> CP-1 ─┐
                                                     ├─> M3 (parallel) ─> CP-3
      M2 (mostly parallel) ──────────> CP-2 ─────────┘
```

M2 may run concurrently with M1 **only after CP-1**. M3 requires both CP-1 and CP-2 because T-3.4's
release note enumerates the whole change-set.

**File-collision summary — tasks that must serialize:**

| File | Tasks |
|---|---|
| `settings/Panel.lua` | T-1.1, T-1.4, T-1.5 |
| `settings/Panel_Widgets.lua` | T-1.3, T-1.5 |
| `settings/Panel_Render.lua` | T-1.3, T-1.5 |
| `modules/Castbar_Debug.lua` | T-2.2, T-2.5 |

**Disjoint, safely parallel:** `core/Compat.lua` (T-2.1) · `settings/Slash.lua` (T-2.3) ·
`modules/Castbar.lua` (T-2.4) · `.pkgmeta` (T-3.1) · `locales/enUS.lua` (T-3.2) ·
`docs/message-bus.md` (T-3.3).

---

## Incremental commit strategy

One commit per task where the task is self-contained; one per milestone where the tasks are a single
logical move. Commit **only on green**.

| Commit | Contents | Suggested message |
|---|---|---|
| 1 | T-0.2…T-0.4 | `test: pin the invariants this review's fixes move (F-001, F-008, F-010)` |
| 2 | T-1.1…T-1.3 | `refactor(settings): stop shadowing LibKa0s-Options members on its own instance (F-001)` |
| 3 | T-1.4 | `refactor(settings): drop the host copies of the library's layout constants (F-004)` |
| 4 | T-1.5 | `fix(settings): AceGUI is survivable, not a load-time dependency (F-003)` |
| 5 | T-1.6 | `docs(settings): re-measure the Options stub's member set and say what is true (F-007)` |
| 6 | T-2.1, T-2.2 | `fix(compat): one secret-safe stringifier, and it is the library's (F-002)` |
| 7 | T-2.3 | `fix(slash): GateHint's probe must restore even when a values() raises (F-005)` |
| 8 | T-2.4 | `fix(castbar): close the castTick bracket on its early exit (F-008)` |
| 9 | T-2.5 | `fix(castbar): always print the interruptibility line in the debug dump (F-009)` |
| 10 | T-3.1 | `chore(packaging): keep .superpowers and .claude out of the shipped zip (F-006)` |
| 11 | T-3.2 | `chore(locale): remove ten orphaned enUS keys (F-010)` |
| 12 | T-3.3 | `docs(message-bus): the emitter rule now matches the emitter table (F-011)` |
| 13 | T-3.4 | `release: v<X.Y.Z> — <headline>` (only if releasing) |
