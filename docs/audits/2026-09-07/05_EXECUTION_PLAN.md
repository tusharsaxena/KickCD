# KickCD — Execution Plan (2026-09-07)

Ordered hand-off for the separate remediation engagement. Every step names its deviation ID from
`02_DEVIATIONS.md` and carries a check that either passes or does not. The green gate —
`luacheck .` clean **and** `lua tests/run.lua` green — holds at every commit.

**Figures used below are this run's and reconcile with `02_DEVIATIONS.md`:** 11 root deviations, 11
total including dependents (none derived), 8 MUST failures, 8 line-ending stragglers, 51 British
spellings across 12 files, 2 unannotated load-bearing TOC lines, 2 bundles without `ANALYSIS.md`.

---

## Sprint 1 — Config and packaging (half a day, no code)

| # | Step | ID | Done when |
|---|---|---|---|
| 1.1 | Add `- .claude`, `- .superpowers`, `- .pkgmeta` to `.pkgmeta`'s `ignore:` block with the justification comment from `04_TECHNICAL_DESIGN.md` | `KICKCD-A-01` | The root dot-entry sweep prints only `UNACCOUNTED — .git` |
| 1.2 | Resolve the `TODO(KCD-18)` marker at `KickCD.toc:14` — open a `state:triaged` Wago issue and cite it, or drop the marker and keep the bare comment | `KICKCD-A-11` | `grep -n 'KCD-18' KickCD.toc` is empty, or the line names a live issue number |
| 1.3 | Add the two `LOAD-BEARING POSITION:` comments above `core\PerfSetup.lua` and `settings\OptionsSetup.lua` | `KICKCD-A-02` | Both lines carry a comment naming what resolves; `lua tests/run.lua` still green (the TOC is parsed by `Loader.tocFiles`) |
| 1.4 | Add one *conventional* note per unannotated group in `# Core` and `# Settings` | `KICKCD-A-02` (SHOULD half) | No line in the listing is ambiguous between "free" and "not yet understood" |

Commit 1.1 alone, 1.2 alone, and 1.3+1.4 together.

**Gate:** `luacheck .` → 0/0. `lua tests/run.lua` → green. `tests/test_vendor_sync.lua` still passes
(it reads the TOC's `libs\LibKa0s\LibKa0s.xml` list, which step 1.3 does not touch).

## Sprint 2 — Small code (half a day)

| # | Step | ID | Done when |
|---|---|---|---|
| 2.1 | `modules/Castbar_Debug.lua:125` → `local print = NS.Util.print`; delete the now-spent paragraph at `docs/ARCHITECTURE.md:278-284` | `KICKCD-A-08` | `grep -rn '_G.print' modules/ settings/ core/` is empty; `tests/test_castbar_debug.lua` output byte-identical before and after |
| 2.2 | Delete the `decorate` field and its comment block from the `NS.Perf` descriptor (`core/PerfSetup.lua:217-226`) | `KICKCD-A-06` | `grep -n 'decorate' core/PerfSetup.lua` is empty; `grep -rn 'MakeCloseButton(' --include='*.lua' . \| grep -v '/libs/\|/tests/'` returns **two** lines (the wrapper and its degraded twin), not three |
| 2.3 | Add the perf panel's close control to `docs/smoke-tests.md` — the suite cannot see it | `KICKCD-A-06` | A smoke row exists naming the mark the button must draw |

**Gate:** as Sprint 1, plus a live-client smoke pass on `/kcd perf`. Step 2.2's only witness is a
person with the panel open; nothing goes red if it is wrong.

## Sprint 3 — Prose (one day)

| # | Step | ID | Done when |
|---|---|---|---|
| 3.1 | US-English sweep over the 12 files, five substitutions, case-preserving | `KICKCD-A-03` | The `03_EVIDENCE.md` §8.1 command prints nothing |
| 3.2 | Sweep `docs/` and `README.md` for the `#the-class-colour-companion-…` anchor and any other inbound link into a renamed heading | `KICKCD-A-03` | No dead in-repo anchor |
| 3.3 | Rename `## What it does` → `## Overview` and `## Subsystems at a glance` → `## Module map` in `docs/ARCHITECTURE.md`; keep `## Load order` as an extra section and say so under the new `## Module map` | `KICKCD-A-07` | `grep -n '^## ' docs/ARCHITECTURE.md` shows all ten mandated names |
| 3.4 | Update the `ARCHITECTURE.md` row in `## Documentation map` if its description names an old section, and re-sweep for anchors into the two renamed headings | `KICKCD-A-07` | Map row reads true; no dead anchor |

**Gate:** `luacheck .` (it lints none of these, so this is a formality), plus a manual read of the
two renamed sections. Do not touch anything under `docs/audits/`, `docs/reviews/`,
`docs/automated-tests/<run>/`, `docs/perf-analysis/<run>/`, `docs/revendor/`, `docs/superpowers/`,
`.superpowers/` or `libs/`.

## Sprint 4 — The record (half a day, run it last of the content work)

| # | Step | ID | Done when |
|---|---|---|---|
| 4.1 | Decide the CCN-18 disposition — peel `tests/test_schema.lua:595-631` into two cases, or accept it with the shelf-life clock stated | `KICKCD-A-05` | Either `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` warns on nothing, or the watch list carries a dated disposition |
| 4.2 | Run `tests/_kit/run-automated-tests.sh` to produce a current bundle and append its `RESULTS.md` row | `KICKCD-A-05` | A new `docs/automated-tests/<stamp>/` exists with all four suite artifacts and a `manifest.json` |
| 4.3 | Write that bundle's `ANALYSIS.md` from the root `AUTOMATED_TESTS.md` prompt, saying what moved across the `20260825-103417` → now gap | `KICKCD-A-09` | `ANALYSIS.md` present, evidence-backed against files in its own directory |
| 4.4 | Rewrite `RESULTS.md`'s four standing prose sections against the new numbers — test suite, lint, perf, complexity watch list — including the four band LOC figures | `KICKCD-A-05` | No figure in the prose contradicts the table's newest row or the bundle's own artifacts |

**Do not** backfill `20260807-110522`'s missing `ANALYSIS.md`. A bundle is frozen evidence.

**Note for whoever cuts the next tag:** run 4.1 **before** the release, not during it. The release
gate requires zero functions above CCN 15, and today's measurement has one.

## Sprint 5 — Renormalize (30 minutes, alone, last)

| # | Step | ID | Done when |
|---|---|---|---|
| 5.1 | `git add .gitattributes && git add --renormalize .`, review, commit | `KICKCD-A-04` | Commit contains only line-ending changes |
| 5.2 | Re-checkout each straggler still on disk (`rm <path> && git checkout -- <path>`) and verify by byte count, not `file(1)` | `KICKCD-A-04` | The `03_EVIDENCE.md` §5 command prints `0` |

This sprint is **last and alone** so the renormalize diff is legible in history rather than mixed
into a content change, and so every earlier edit is normalized with it.

## Not scheduled — blocked upstream

| # | Item | ID | Blocked on |
|---|---|---|---|
| — | The provisional `options-ui-§1` hollow-composer register row | `KICKCD-A-10` | A ruling: either `LibKa0s-Options-1.0` ships the composers in a file that answers without the Options major, or `options-ui-§1` states which of its two MUSTs wins. **Nothing lands in this repo until then**, and the local "fix" — copying the composed row sets into the host stub — is anti-pattern #73 and must not be taken. |

Keep `tests/test_options_panel.lua`'s fingerprint case green in the meantime; it is what makes the
112-of-228 delta a measured fact rather than a claim, and it is what will say so the day the number
moves.

---

## Sequencing constraints, stated once

1. **Sprint 5 is last.** Renormalizing before the content edits means doing it twice.
2. **Sprint 4 is after Sprints 1–3.** The record should measure the fixed tree, not the tree that
   produced this audit.
3. **Step 1.3 before Sprint 5** — the TOC must be final before its bytes are normalized.
4. Sprints 1, 2 and 3 are otherwise independent and may run in any order or in parallel.

## Definition of done

- All eight MUST failures closed or, for `KICKCD-A-10`, resolved upstream.
- `luacheck .` → 0 warnings / 0 errors; `lua tests/run.lua` → green.
- The three sweeps in `03_EVIDENCE.md` §5, §6 and §8.1 each print their clean answer.
- `docs/automated-tests/RESULTS.md`'s prose and table agree with each other and with a bundle
  produced after the last content commit.
- No file under `docs/audits/`, `docs/reviews/` or any frozen run directory has been edited.
