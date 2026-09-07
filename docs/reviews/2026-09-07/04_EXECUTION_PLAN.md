# 04 — Execution plan

**Repo:** KickCD v1.2.1 · **Date:** 2026-09-07
**Inputs:** `01_FINDINGS.md` (12 findings), `02_PROPOSED_CHANGES.md` (2 upstream + 10 local changes)

Five milestones. **M1 is cross-repo and is deliberately separate from every milestone that edits this
addon's own files** — nothing in M2–M5 may touch `libs/` or `tests/_kit/`, and nothing in M1 lands in this
repo except a re-vendor commit.

---

## Milestone map

| M | Name | Findings | Blocking? | Done when |
|---|---|---|---|---|
| **M1** | Upstream: LibKa0s owns the LSM patch + the kit's report generator | KICKCD-R-01, KICKCD-R-05 | Blocks M3 | Both fixes are tagged in `../LibKa0s`; this repo carries a **re-vendor commit** with `tests/test_vendor_sync.lua` green |
| **M2** | Test-suite truth: complexity, isolation, dead branch | KICKCD-R-02, R-04, R-09 | No | Suite green; `lizard` warning count back to 0; `docs/test-cases.md` and the README badge regenerated in the same commit |
| **M3** | Adopt the library patch; delete the local copy | KICKCD-R-01 | Needs M1 | `core/LSMPatch.lua` gone, TOC line gone, `03_SMOKE_TESTS.md` §C-01a–e all PASS |
| **M4** | Localisation seam + its gate | KICKCD-R-03 | No | Three keys reconciled; the new coverage case is green **and demonstrably red** when a key is broken |
| **M5** | Reader-facing precision | KICKCD-R-07, R-08, R-10, R-11, R-12 | No | Suite and lint green; no behaviour change beyond C-05's added line |
| — | **Not scheduled** | KICKCD-R-06 | — | Line-ending renormalisation is the audit's call (`line-endings-§2`), not this review's |

---

## M1 — Upstream (cross-repo handoff)

**This milestone edits no file in this repo except the vendored payload, and that only by whole-folder
copy.** A local patch under `libs/` would be silently reverted by the next re-vendor, and the behaviour it
fixed would come back as a regression with no cause anywhere in this addon's history.

| Task | Role | Implements | Files touched | Repo |
|---|---|---|---|---|
| **T1.1** | library-maintainer | U-01 / KICKCD-R-01 | new `LibKa0s/OptionsLSMPatch.lua`; `LibKa0s/LibKa0s.xml`; `LibKa0s/Options.lua` (export `PatchLSMBorder`) | `../LibKa0s` |
| **T1.2** | library-maintainer | U-01 | bump `LibKa0s-Options-1.0` minor; upstream unit cases for the idempotence sentinel | `../LibKa0s` |
| **T1.3** | library-maintainer | U-02 / KICKCD-R-05 | `testkit/run-automated-tests.sh` — regenerate the prose sections, not only the table row; bump the kit revision | `../LibKa0s` |
| **T1.4** | release-coordinator | U-01 + U-02 | tag `../LibKa0s`; update `CHANGELOG.md` | `../LibKa0s` |
| **T1.5** | vendor-sync | — | **whole-folder copy** `../LibKa0s/LibKa0s` → `libs/LibKa0s/`, `../LibKa0s/testkit` → `tests/_kit/`; update the provenance tag at `CLAUDE.md:52` | **KickCD** |

**T1.5 is its own commit and contains nothing else.** Its exit gate is the two-diff pair `CLAUDE.md:74`
already mandates:

```
diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s      # MUST be empty
diff -r                     ../LibKa0s/LibKa0s libs/LibKa0s      # SHOULD be empty
```

plus the same pair for `../LibKa0s/testkit` ↔ `tests/_kit`, and `lua5.1 tests/run.lua` green
(`tests/test_vendor_sync.lua` compares against the **tag**, so T1.4 must precede T1.5).

**T1.1's design constraint, carried from `02_PROPOSED_CHANGES.md` C-01:** `PatchLSMBorder` must defer
internally to `PLAYER_LOGIN` rather than patch on the caller's frame. The file being deleted waits for
login on stated grounds — *"by which point every addon's libs have run and the LSM30_Border registry slot
is stable"* (`core/LSMPatch.lua:11`–`:12`). Losing that is the one way this change can regress, and
`03_SMOKE_TESTS.md` §C-01b/§C-01c exist to catch it.

**Note for the other four consumers.** AbsorbTracker, ConsumableMaster, MultiMeters and PanelMaster each
carry their own divergent `core/LSMPatch.lua` and each needs the same M3. That is **their** repos' work and
is out of scope here — record it as a cross-repo follow-up rather than letting it block KickCD.

**Done when:** T1.5's commit is in, both diff pairs are empty, and the suite is green.

### Checkpoint CP-1 (human)

Before M3 begins, confirm: the tag exists upstream, `CLAUDE.md:52`'s provenance line names it, both diffs
are empty, and the suite is green. **Do not proceed to M3 on an un-tagged library** — `test_vendor_sync`
compares against the tag and will redden or, worse, be skipped.

---

## M2 — Test-suite truth

Independent of M1; can run in parallel with it. All three tasks touch only `tests/`.

| Task | Role | Implements | Files touched | Parallel? |
|---|---|---|---|---|
| **T2.1** | test-refactorer | C-02 / KICKCD-R-02 | `tests/test_schema.lua` | **No** — same file as T2.2 |
| **T2.2** | test-refactorer | C-03 / KICKCD-R-04 | `tests/test_schema.lua`, `tests/test_options_panel.lua` | **No** — same file as T2.1 |
| **T2.3** | test-refactorer | C-07 / KICKCD-R-09 | `tests/test_bus.lua` | **Yes** |
| **T2.4** | test-refactorer | C-02 | `docs/test-cases.md`, `README.md` | **No** — runs last in M2 |

**Serialisation:** T2.1 and T2.2 both edit `tests/test_schema.lua` — and T2.2's two sites are *inside* the
case T2.1 splits. **Do them as one edit pass**, in the order T2.1 then T2.2, rather than as two tasks
racing the same file. T2.3 is disjoint and fully parallelisable.

**T2.4 is not optional and is not a follow-up.** C-02 moves the pass count 841 → 842. `testing-§7` requires
`docs/test-cases.md` and the README `[Tests]` badge to move in the **same change** as the count. Regenerate
with `lua5.1 tests/run.lua --list > docs/test-cases.md` — **never** hand-edit it. If M4 lands in the same
release, run T2.4 once after both, not twice.

**Done when:**
- `lua5.1 tests/run.lua` → `842 passed, 0 failed, 0 skipped`
- `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` → **0** warnings, max CCN 15
- `docs/test-cases.md` regenerated and the README badge matches
- `luacheck .` still 0/0

**Explicitly not done here:** regenerating `docs/automated-tests/`. That happens at release
(`/wow-addon:bump-version`); the expected movement (CCN warn 1 → 0, max 18 → 15) is a **note for that
release**, not a task now.

---

## M3 — Adopt the library patch (needs M1)

| Task | Role | Implements | Files touched | Parallel? |
|---|---|---|---|---|
| **T3.1** | wow-api-migrator | C-01 / KICKCD-R-01 | delete `core/LSMPatch.lua`; remove its line from `KickCD.toc`; add the `PatchLSMBorder` call to `settings/OptionsSetup.lua` | **No** — `settings/OptionsSetup.lua` also touched by T5.4 |

**Deletion order matters.** Remove the TOC line and the file in the **same** commit. A TOC entry for a
missing file is a load error; a file present but unlisted is dead weight that still passes lint.

**Watch the TOC's annotated positions.** `KickCD.toc` documents which lines are **load-bearing** and which
are **conventional**. `core/LSMPatch.lua` sits in the `# Core` block with no load-bearing annotation, so
removing it constrains nothing — but re-read the neighbouring comments before editing, because
`core/MediaSetup.lua`'s and `core/PerfSetup.lua`'s positions **are** load-bearing and both are in the same
block.

**Done when:** `core/LSMPatch.lua` is gone, `luacheck .` and the suite are green, and
`03_SMOKE_TESTS.md` §C-01a–e all read PASS.

### Checkpoint CP-2 (human, in-client)

M3 is the only change in this set that is **invisible to every headless suite**. Do not sign it off from a
green run. §C-01d in particular — the other addon's picker being identical with and without KickCD
installed — is the entire point of the change; if it fails, M3 has not achieved its purpose and should be
reported back to M1 rather than merged.

---

## M4 — Localisation seam

Fully parallel with M1, M2 and M5 — it touches `locales/enUS.lua` and `tests/test_locale.lua`, which no
other task edits.

| Task | Role | Implements | Files touched | Parallel? |
|---|---|---|---|---|
| **T4.1** | localization | C-04 / KICKCD-R-03 | `locales/enUS.lua` | **Yes** |
| **T4.2** | test-author | C-04 | `tests/test_locale.lua` | **Yes** |
| **T4.3** | test-refactorer | C-04 | `docs/test-cases.md`, `README.md` | **No** — coordinate with T2.4 |

**Order T4.2 before T4.1 and watch it go red.** The new coverage case must be demonstrably falsifiable —
write it first, confirm it fails on the three current keys, then fix `locales/enUS.lua` and watch it go
green. A case written after the fix is a case nobody has ever seen fail, which is the unfalsifiable-test
failure mode `testing-§12` names.

**T4.2's construction constraints** (from `02_PROPOSED_CHANGES.md` C-04): derive the file list from the TOC
via `T.tocFiles` — never hand-maintain it (`testing-§9`); never glob `tests/_kit/` or `libs/`; and skip
`core/PerfSetup.lua:197`'s comment-only `NS.L["STEP_START"]` by matching code rather than comment text.

**Done when:** the case is green, was seen red first, and `docs/test-cases.md` + the badge reflect the new
count.

---

## M5 — Reader-facing precision

No behaviour change beyond C-05's one added output line. Lowest risk in the set.

| Task | Role | Implements | Files touched | Parallel? |
|---|---|---|---|---|
| **T5.1** | lua-refactorer | C-05 / KICKCD-R-07 | `modules/Castbar_Debug.lua` | **No** — same file as T5.2, T5.5 |
| **T5.2** | lua-refactorer | C-10 / KICKCD-R-12 | `modules/Castbar_Debug.lua` | **No** — same file as T5.1, T5.5 |
| **T5.3** | lua-refactorer | C-06 / KICKCD-R-08 | `settings/Panel_Render.lua` | **Yes** |
| **T5.4** | lua-refactorer | C-09 / KICKCD-R-11 | `modules/IconGrid.lua`, `modules/Cooldowns.lua`, `settings/Panel_Widgets.lua`, `settings/OptionsSetup.lua` | **No** — `settings/OptionsSetup.lua` also T3.1 |
| **T5.5** | lua-refactorer | C-09 | `modules/Castbar_Debug.lua` (the three bare-global sites) | **No** — same file as T5.1, T5.2 |
| **T5.6** | perf-engineer | C-08 / KICKCD-R-10 | `modules/Castbar.lua`, `tests/perf.lua` | **Yes** |

**T5.6 is conditional.** Take it only together with its `castStart` scenario in `tests/perf.lua`. Without a
scenario the change has no record, and `performance-§8` is explicit that an interpretation without its
record is an assertion. If the scenario is skipped, **skip C-08 entirely** rather than shipping an
unmeasurable perf claim. Note that a perf scenario is **not** a test case and must not be counted in
`docs/test-cases.md` or the README badge (`testing-§7`).

**T5.3 needs one check first:** grep the suite for `-180` before deleting the fallback, to confirm no case
asserts on it.

**Done when:** `luacheck .` 0/0, suite green at the M2/M4 count, `03_SMOKE_TESTS.md` §C-05, §C-06,
§C-09/§C-10 PASS.

---

## Critical path and concurrency

```
M1 (upstream) ───────────────────────────► CP-1 ──► M3 ──► CP-2 ──┐
                                                                   ├──► release readiness
M2 (tests) ──┐                                                     │
M4 (locale) ─┼── converge on docs/test-cases.md + README badge ────┤
M5 (polish) ─┘                                                     │
```

**M1 is the critical path.** It is cross-repo, needs a tag, and gates M3. Start it first and run M2, M4 and
M5 alongside it — none of the three depends on it.

### File-collision map (must serialise)

| File | Tasks | Resolution |
|---|---|---|
| `tests/test_schema.lua` | T2.1, T2.2 | One edit pass, T2.1 then T2.2 |
| `settings/OptionsSetup.lua` | T3.1, T5.4 | T3.1 first (structural), then T5.4's `C_Timer` prefix |
| `modules/Castbar_Debug.lua` | T5.1, T5.2, T5.5 | One edit pass, T5.1 → T5.2 → T5.5 |
| `docs/test-cases.md`, `README.md` | T2.4, T4.3 | **Single regeneration** after both M2 and M4 land — never two |

### Genuinely parallelisable (disjoint file sets)

`T2.3` · `T4.1` + `T4.2` · `T5.3` · `T5.6` · and all of M1's upstream tasks against all of M2/M4/M5.

---

## Checkpoints

| ID | After | Verifier | What must be true |
|---|---|---|---|
| **CP-1** | M1 | human | Library tagged; `CLAUDE.md:52` provenance updated; **both** vendor diff pairs empty; suite green |
| **CP-2** | M3 | human, **in-client** | `03_SMOKE_TESTS.md` §C-01a–e all PASS, especially §C-01d. No headless suite covers this |
| **CP-3** | M2 + M4 | agent | Suite green at the new count; `lizard` 0 warnings; `docs/test-cases.md` and the badge regenerated **once**, matching |
| **CP-4** | M5 | human, in-client | §C-05, §C-06, §C-09/§C-10 PASS; the full Regression suite R-01…R-18 and Taint T-01…T-06 pass |
| **CP-5** | all | human | Sign-off table in `03_SMOKE_TESTS.md` complete; `05_FINAL_SUMMARY.md` counts reconciled against what actually shipped |

---

## Incremental commit strategy

One commit per task group, atomic and revertible. Suggested boundaries and messages:

| # | Scope | Message |
|---|---|---|
| 1 | T1.5 **only** | `chore(vendor): re-vendor LibKa0s <tag> — Options gains PatchLSMBorder, testkit rev N` |
| 2 | T2.1 + T2.2 | `test(schema): split the CCN-18 tab-strip case and isolate its shared-state writes (KICKCD-R-02, R-04)` |
| 3 | T2.3 | `test(bus): drop the dead pre-KCD-09 NewBusTarget fallback (KICKCD-R-09)` |
| 4 | T4.2 then T4.1 | `fix(locale): reconcile three cast-bar desc keys and gate L[...] coverage (KICKCD-R-03)` |
| 5 | T2.4 + T4.3 | `docs(tests): regenerate the case inventory and badge for the new count` |
| 6 | T3.1 | `refactor(options): adopt LibKa0s PatchLSMBorder; delete the local LSM30_Border patch (KICKCD-R-01)` |
| 7 | T5.1 + T5.2 + T5.5 | `fix(castbar-debug): report the secret branch unconditionally; rename the shadowing print param (KICKCD-R-07, R-12, R-11)` |
| 8 | T5.3 | `fix(settings): drop the anchor fallback that contradicted DEFAULT_PROFILE (KICKCD-R-08)` |
| 9 | T5.4 | `style: prefix the remaining bare WoW globals with _G. (KICKCD-R-11)` |
| 10 | T5.6 *(conditional)* | `perf(castbar): cache the per-cast OnUpdate closure, with its scenario (KICKCD-R-10)` |

**Commit 1 stands alone** and contains nothing but the vendored payload copy and the provenance line —
that is what makes a future `git log` able to explain a behaviour change that arrived by file copy.
**Commit 6 must come after commit 1**, never merged into it.

Each commit message ends with the collection's standard trailer.

---

## Deliberately out of scope

- **KICKCD-R-06** (line-ending stragglers) — `line-endings-§2`'s authoritative check, with its commands and
  rolled-up count, belongs to `/wow-addon:standards-audit`. Recorded here as an observation only.
- **Regenerating `docs/automated-tests/`** — that is release work (`/wow-addon:bump-version`), and a
  hand-edited report reads as measured when it is not (`performance-§10`).
- **The other four consumers' `core/LSMPatch.lua`** — same defect, their repos, their milestones.
- **Anything under `libs/` or `tests/_kit/`** — read-only in this repo, in every milestone, without
  exception.
