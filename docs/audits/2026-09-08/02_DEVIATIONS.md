# KickCD — Deviations (2026-09-08)

**Addon:** Ka0s KickCD 1.2.1 · **HEAD:** `03f3b9a` · **Standard:** **v2.39.0 (2026-09-07)**
**Prefix:** `KICKCD-` · this run's new rows use the `KICKCD-B-` series; rows carried over from the
2026-09-07 run keep their `KICKCD-A-` ids.

## The two tallies, and their basis

| Tally | Count | Basis |
|---|---|---|
| **Headline (roots only)** | **8** | one row per independent cause; dependents excluded |
| **Total including dependents** | **8** | no row in this run is `derived from` another |
| **MUST failures (roots only)** | **4** | `KICKCD-A-08`, `KICKCD-B-01`, `KICKCD-B-02`, `KICKCD-B-03` |

**By impact grade:** High **0** · Medium **0** · Low **5** · Info **3**.

Every finding in this run is a doc, a config file, a comment or an unreachable code arm. No user, no
`KickCDDB`, no `KickCDPerfDB` and no game session can reach any of them today. The grade answers
*what can go wrong and to whom*; the MUST is named in every row so the lower grade never reads as
the rule being optional.

## Movement since 2026-09-07

The previous run filed **11** roots. Nine are **closed**; two survive in part and are re-filed below
with their original ids. Four rows are new, three of which are only visible against v2.39.0.

| Prior id | Section | Work item | Status today |
|---|---|---|---|
| `KICKCD-A-01` | `packaging` | `M2-19` | **Closed.** Both `.pkgmeta` sweeps return nothing; `.claude`, `.superpowers` and `.pkgmeta` itself are all named. |
| `KICKCD-A-02` | `toc-file-§5` | `M4-12` | **Partly closed.** The MUST is satisfied — five load-bearing positions, five annotations. The SHOULD is not; re-filed below. |
| `KICKCD-A-03` | `localization-§5` | `M4-13`, `M4c-02` | **Closed for the 12 files it named**, and a vendored gate now holds it. Two spellings survive in a doc the gate does not reach — a different cause, filed as `KICKCD-B-02`. |
| `KICKCD-A-04` | `line-endings-§1/§6` | `M4-10` (as `KICKCD-R-06`) | **Closed.** The working-tree count is **0**, and `tests/_kit/test_eol.lua` now owns the check. |
| `KICKCD-A-05` | `automated-tests-§4` | `M5-01` (as `KICKCD-R-05`) | **Closed.** Record regenerated as `20260908-181321`; all four standing sections rewritten; the CCN-18 function is gone. Residual one-commit drift filed as `KICKCD-B-04` (Info). |
| `KICKCD-A-06` | `performance-§4` | `M4-16` | **Closed.** `core/PerfSetup.lua:220` records the deliberate absence of `decorate`. |
| `KICKCD-A-07` | `documentation-§3` | `M5-03` | **Closed.** `## Overview` (`:7`) and `## Module map` (`:22`) are present; all ten mandated names, gated by `tests/test_doc_structure.lua`. |
| `KICKCD-A-08` | `events-frames-taint-§8` | `M4-20` | **NOT closed.** The one site the audit cited was fixed; **three** uncited sites of the same class survive. Re-filed below. |
| `KICKCD-A-09` | `automated-tests-§5` | `M5-01` (fix-forward) | **Closed.** `20260908-181321/ANALYSIS.md` exists; the two frozen bundles were correctly left alone. |
| `KICKCD-A-10` | `options-ui-§1` | `M1-STD-11` | **Closed at source.** `options-ui-§1` now rules that the no-copy MUST wins and that hollow composers need no register row; the PROVISIONAL row is retired at `docs/ARCHITECTURE.md:254-272`. |
| `KICKCD-A-11` | `toc-file-§1` | `M5-02` | **Closed.** The `TODO(KCD-18)` marker is gone; `KickCD.toc:14-16` is a bare, correct comment. |

## Recorded deviations — accepted, not re-filed, not counted

`docs/ARCHITECTURE.md:234-288` carries **five** ratified rows. The register was read before anything
above or below was filed. For each row this run resolved the cited rule against v2.39.0 **and**
evaluated the re-check trigger against the tree, as `audit-review-history` now MUSTs.

| Rule | What differs | Decided | Rule changed in v2.39.0? | Trigger fired? | Status |
|---|---|---|---|---|---|
| `savedvariables-§1` | shape-driven migrators run beside the version-gated runner | 2026-07-16 | No — `savedvariables.md` is byte-identical to v2.38.0 | **See `KICKCD-B-03`** — the row says *two*, the tree runs *three* | **Accepted**, but the row's own text is now wrong |
| `savedvariables-§1` | `DEFAULT_PROFILE` restructured under `units.<unit>` | 2026-07-15 | No | No — `defaults/Profile.lua` still declares `target` and `focus` only | **Accepted** |
| `options-ui-§1` | `Helpers.LSMValues` / `AnchorValues` / `AnchorOrder` stay host-side | 2026-08-05 | **Yes** — §1 gained the hollow-composer ruling. Re-read: the ruling governs a stub's **composer** members, not a host shadow of a value provider, so the behavior this row records is **not** now mandated or permitted, and no retirement is owed | No — `settings/Icons.lua` and `settings/Castbar.lua` still evaluate `H.AnchorValues()` in schema-row literals at file load | **Accepted** |
| `options-ui-§15` | `General visibility`'s value list is cast-state driven | 2026-09-02 | No — the v2.39.0 `options-ui` diff touches §1 and §16 only | No — the composer still takes no `values` override | **Accepted** |
| `events-frames-taint-§8` | `safeRender` in `core/Compat.lua` | 2026-08-05 | No — `events-frames-taint.md` is byte-identical to v2.38.0 | No — `safeRender` still has no caller outside the `/kcd debug interrupt` dump | **Accepted** |

**The inverse rule.** Three closed `state:will-not-do` issues (#11 `RenderGrid`, #12
`LibKa0s-Widgets-1.0`, #14 `LibKa0s-Item-1.0`) decline LibKa0s module adoptions.
`library-stack-§3`'s prune rule and `§7`'s *"an addon wires only the modules it actually uses"* make
those **compliance**, not deviations from a rule, so they owe no register row and nothing is filed.
No other decline exists anywhere in this repo without a row.

---

## MUST failures

| ID | Section(s) | Grade | Deviation | Fix direction |
|---|---|---|---|---|
| **KICKCD-A-08** | `events-frames-taint-§8` | Low | **Three `_G.print` fallback arms survive at call sites.** `core/KickCD.lua:108` (`local fn = self.Util and self.Util.print or _G.print`), `core/Compat.lua:452` (`local out = (NS.Util and NS.Util.print) or _G.print`) and `modules/Cooldowns.lua:538` (`local p = NS.Util and NS.Util.print or _G.print`). §8's first unrelaxed rule is unqualified — *"No addon calls the global `print()` for user-facing output — at any site, in scope or out"* — and it is about the missing `NS.PREFIX` tag, not about secrets. **This is a MUST failure.** It is **Low** because every arm is unreachable: `core/CoreSetup.lua` defines `Util.print` on both the library-present path (`:187`) and the library-absent path (`:115`). `M4-20` closed the one site the 2026-09-07 audit cited (`modules/Castbar_Debug.lua`, now `local emit = NS.Util.print`) and did not sweep for the class — the audit under-scoped, and the fix followed the audit. | Same edit, three times: `local fn = self.Util.print`, `local out = NS.Util.print`, `local p = NS.Util.print`. Then add a source-style case to `tests/test_source_style.lua` asserting `grep -rn 'or _G%.print'` over `core/ modules/ settings/ defaults/ locales/` returns nothing, so the class cannot come back one site at a time. |
| **KICKCD-B-01** | `documentation-§3` | Low | **`perf-analysis/README.md` is registered in the wrong table of `## Documentation map`.** It sits at `docs/ARCHITECTURE.md:224` under `### Verification and record`. v2.39.0 ratifies that fourth table and states its membership exactly: *"It holds **exactly** `testing.md`, `smoke-tests.md`, `test-cases.md`, `performance.md`, `automated-tests/README.md` and `automated-tests/RESULTS.md`. Six rows, in every addon, in every state"* — and then, in its own bullet, *"`perf-analysis/README.md` registers in `### Conditional`, not here, in both of its states … the trigger decides the table."* KickCD's table carries **seven** rows. **A MUST failure**, and Low: a reader is misdirected by one row and nothing else happens. Invisible before this cycle, because the fourth table had no specification at all until v2.39.0. | Move the `perf-analysis/README.md` row out of `### Verification and record` (`docs/ARCHITECTURE.md:224`) and into `### Conditional` (`:204-213`), re-shaped to that table's `\| Doc \| Status \| Trigger \|` columns — Status **Present**, Trigger *the performance harness is wired (`performance-§12`)*. The Verification table then holds its mandated six. While in the file, `tests/test_doc_structure.lua` should gain a case pinning both memberships, since nothing in the suite reads the map's table boundaries today. |
| **KICKCD-B-02** | `localization-§5`, AP #46 | Low | **Two British spellings live in a doc the spelling gate cannot see.** `docs/perf-analysis/README.md:32` — *"so a run **analysed**"* — and `:33` — *"still sorts against its **neighbours**"*. Both are on v2.39.0's canonical `BRITISH` list (`analys`, `neighbour`) and neither is covered by `ALLOWED`. The cause is not the list: `tests/test_spelling.lua:33-68` carries both published lists **whole**. The cause is the scope. `tests/test_spelling.lua:102-110` excludes the directory `docs/perf-analysis/` outright, alongside `docs/audits/`, `docs/reviews/`, `docs/automated-tests/` and `docs/revendor/` — but `localization-§5`'s third exclusion is *"frozen dated bundles"*, and `docs/perf-analysis/README.md` is not one. `documentation-§3` says so in as many words: *"It is the one file in the store that is rewritten — the bundles are frozen."* `docs/automated-tests/README.md` and `RESULTS.md` are excluded on the same over-broad rule and happen to be clean today. **A MUST failure** against US English as the source dialect, and Low: doc prose. | Two edits, in this order. (1) Narrow the two directory exclusions in `tests/test_spelling.lua:107` and `:109` from `docs/automated-tests/` and `docs/perf-analysis/` to their **dated bundles only**, so the two live `README.md` files and `RESULTS.md` come into scope — the gate already delimits on non-letters, so `ANALYSIS.md` as a filename resolves to `analysis`, which is on `ALLOWED`, and does not redden. (2) Fix the two words. Land the gate change first and watch it go red, so the case is seen failing before it is seen passing. |
| **KICKCD-B-03** | `documentation-§3`, `audit-review-history` | Low | **A register row asserts a state the tree left behind.** `docs/ARCHITECTURE.md:248` opens *"**Two** profile migrators run off the **stored shape**… these two run beside them, ungated"* and closes with a re-check trigger naming *"a third shape addition under an existing profile field"*. The tree runs **three** ungated shape-driven migrators — `core/Database.lua:598-601`: `self:FoldLegacyUnits(self.db)`, `self:BackfillLabelStyle(self.db)`, `self:MigrateSpecKeys(self.db)` — and the same three again on the fresh-install path at `:639`, `:644`, `:651`. `BackfillLabelStyle` was added in `e143516` on **2026-07-16**, the row's own Decided date, so the row has been one migrator behind since the day it was written and three consecutive audits have accepted it without re-reading the count. Whether the trigger's second arm has *fired* is a judgment the row's author owes; what is not a judgment is that the row's **What differs** column is factually wrong, and `documentation-§3` makes the register the single home of a ratified decision precisely so a reader can trust it. **A MUST failure** against the register's accuracy; **Low** because it misleads a reader and reaches nothing else. Only visible this cycle because `audit-review-history`'s third MUST — *evaluate every row's re-check trigger against the tree* — is a v2.39.0 amendment. | Do not silently change *two* to *three*. Re-read the trigger against `BackfillLabelStyle` and decide it: if backfilling `units.<unit>.label.style` **is** the "third shape addition under an existing profile field" the trigger names, the deviation ended on 2026-07-16 and the row **retires**, with the version-gated runner (`core/Database.lua:525-528`, now four steps to `CURRENT_DB_VERSION = 5`) taking over in the record. If it is not, rewrite **What differs** to name all three by function and re-state the trigger so a reader can evaluate it without opening `Database.lua`. Either way the row moves; leaving it is what this finding is about. |

## SHOULD failures

| ID | Section(s) | Grade | Deviation | Fix direction |
|---|---|---|---|---|
| **KICKCD-A-02** | `toc-file-§5` | Low | **`KickCD.toc` annotates every load-bearing position and marks no conventional group.** The MUST half is closed — `:47`, `:58`, `:70`, `:94`, `:101` all carry a `LOAD-BEARING POSITION:` comment naming what resolves, which is the whole denominator. What is missing is §5's companion SHOULD: *"A position that is merely conventional SHOULD say that too, once per group … A TOC that annotates only its load-bearing lines leaves every other line ambiguous between 'free' and 'not yet understood'."* Four groups carry no such note — `# Locales` (`:33`), `# Defaults` (`:72`), `# Modules` (`:76`, eight files) and the eight unannotated `# Core` lines (`:37`, `:49`, `:50`, `:59`, `:60`, `:61`, `:62`; `:48` `core\Constants.lua` is already pinned by the annotated line above it and is compliant). `M4-12`'s own commit message shows this was a deliberate omission, so it is open rather than overlooked. Per §5's grading table this is **one SHOULD row for the file**, never one per line. | Four one-line comments, one above each `#` header: `# Locales` and `# Modules` reach everything through closures at call time; `# Defaults` is read at call time by `core/Database.lua`, not at load; and the `# Core` note says the block's conventional lines are everything not carrying a `LOAD-BEARING POSITION:` comment. Do **not** annotate line by line — §5's worked example is explicit that a rule making every line restate its neighbor's comment is noise a reader learns to skip. |

## Info

| ID | Section(s) | Grade | Note |
|---|---|---|---|
| **KICKCD-B-04** | `automated-tests-§4`, AP #51 | Info | **The newest run bundle trails HEAD by one commit.** `docs/automated-tests/20260908-181321/manifest.json` stamps sha `c8f9381` on `feat/2026-09-07-audit-review-remediation`; HEAD is `03f3b9a`, two commits later (`86744a4` `M4c-06` and the merge). `docs/automated-tests/RESULTS.md:26` therefore reads 860 tests over 93 lint files and NLOC 17805, where HEAD measures **864 / 94 / 17980**. The record is not stale in the sense `KICKCD-A-05` was — every standing section was regenerated, the watch list is this run's own measurement, and the four figures moved by 4, 1, 175 and 5 respectively because `M4c-06` added `tests/test_lintconfig.lua`. `automated-tests-§3` puts the checkpoint at **release**, HEAD carries no tag, and the release run regenerates all of it. Recorded so the two numbers do not sit side by side unexplained; **not** a reason to flag the addon for failing to gate commits on the record. The same one-commit gap shows in the band table: `docs/automated-tests/RESULTS.md:84` records `tests/wow_mock.lua` at **1232** where `wc -l` reads **1235** today. |
| **KICKCD-B-05** | `audit-review-history`, AP #62 | Info | **Issue #9's title carries a bracket prefix.** *"[Optional] Move time-varying icon render onto the cooldown ticker"*. `[Optional]` is neither a `state:` value nor a `severity:` word, so this is **not** anti-pattern #62 and is deliberately not filed as one — but it is a disposition living in a title, in a store where *"the level lives in the label and nowhere else"*. All 14 issues carry both labels correctly and no other title carries a prefix. Recorded, not filed: strip it on the next edit that touches the issue for another reason. |
| **KICKCD-B-06** | `documentation-§3`, `audit-review-history` | Info | **Two descriptions quote wording their sources have moved past.** (a) `docs/ARCHITECTURE.md:225` describes `RESULTS.md` as *"generated, never hand-edited"* — the flat formulation v2.39.0 retired in favor of the one-authored-cell boundary (*"Through v2.38.0 this line read 'generated, never hand-edited' flat"*), and the file itself already states the exception correctly at `docs/automated-tests/RESULTS.md:68-71`. (b) `RESULTS.md`'s band-table dispositions cite `A-2` and `KCD-30` as trackers; both belong to the retired `KCD-`/advisory series, and `docs/audits/2026-09-07/02_DEVIATIONS.md` recorded the whole `KCD-30`..`KCD-49` set as closed. Neither reaches anything, and the `Disposition` cell is authored rather than generated, so both are one-line edits at the next release run. |
