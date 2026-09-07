# KickCD — Deviations (2026-09-07)

**Addon:** Ka0s KickCD 1.2.1 · **Standard:** **v2.38.0 (2026-09-02)** · **Prefix (this run):**
`KICKCD-A-` · **Prior prefix:** `KCD-` (2026-07-12 … 2026-08-05 runs)

## The two tallies, and their basis

| Tally | Count | Basis |
|---|---|---|
| **Headline (roots only)** | **11** | one row per independent cause; dependents excluded |
| **Total including dependents** | **11** | no row in this run is `derived from` another |
| **MUST failures (roots only)** | **8** | `KICKCD-A-01`, `-02`, `-03`, `-04`, `-05`, `-07`, `-08`, `-10` |

**By impact grade:** High **0** · Medium **0** · Low **10** · Info **1**.

Every MUST failure in this run is **Low**. That is not a softening: each one is a config file, a
comment, a doc, a record or a dead code path, and no user, no SavedVariables and no game session can
reach any of them today. The grade answers *what can go wrong and to whom*; the MUST is named in
every row so the grade never reads as the rule being optional.

## ID continuity

The `KCD-30`..`KCD-49` set from the 2026-08-05 run is **closed** — this run re-checked each and
found none of them live (see `03_EVIDENCE.md` §9). `KCD-38` (multiple senders of
`Ka0s_KickCD_CONFIG_CHANGED`), `KCD-45` (stub re-implementing the line format) and `KCD-47` (British
spellings in a plan file) are the three worth naming, because two are gone and the third has moved:
the spelling class recurs in different files and is re-filed here as `KICKCD-A-03`. The advisory
`A-3` (`.pkgmeta` dot-entries) is **promoted to a deviation** this run, as `KICKCD-A-01`, because
v2.38.0's `packaging` check makes the root dot-entry sweep normative rather than advisory.

## Recorded deviations — accepted, not re-filed

`docs/ARCHITECTURE.md:223-284` carries six ratified rows. Five are **accepted and excluded from the
tallies above**; none cites a rule the standard has since changed, so none is a graveyard entry.

| Rule | What differs | Decided | Status this run |
|---|---|---|---|
| `savedvariables-§1` | two shape-driven migrators run beside the version-gated runner | 2026-07-16 | **Accepted.** §1's text is unchanged in v2.38.0; the trigger has not fired. |
| `savedvariables-§1` | `DEFAULT_PROFILE` restructured under `units.<unit>` | 2026-07-15 | **Accepted.** Trigger (a third tracked unit) has not fired. |
| `options-ui-§1` | `Helpers.LSMValues` / `AnchorValues` / `AnchorOrder` stay host-side | 2026-08-05 | **Accepted.** Load-time constraint still holds; `tests/test_options_panel.lua` pins it. |
| `options-ui-§15` | `General visibility`'s value list is cast-state driven | 2026-09-02 | **Accepted.** §15 still mandates the canonical four; the composer still takes no `values` override. |
| `events-frames-taint-§8` | `safeRender` in `core/Compat.lua` | 2026-08-05 | **Accepted.** §8's v2.38.0 scoping does not reach a diagnostic value column. |

The **sixth** row is marked *PROVISIONAL — not signed off*, and the register's own note says an audit
that re-files it as an open MUST failure is reading the table correctly. It is therefore **not**
accepted and is filed below as `KICKCD-A-10`.

**Ratification check (the inverse rule).** Three closed `state:will-not-do` issues (#11, #12, #14)
decline **LibKa0s module adoptions**. `library-stack-§7` makes adoption a per-addon schedule
decision — *"an addon wires only the modules it actually uses"* — so those are compliance, not
deviations, and owe no register row. No decline in the issue store lacks a row it needs.

---

## MUST failures (all Low)

| ID | Section(s) | Grade | Deviation | Fix direction |
|---|---|---|---|---|
| **KICKCD-A-01** | `packaging` | Low | **Two root dot-directories are unaccounted for in `.pkgmeta`'s ignore list**, so the packager ships them: `.claude/` (1 file) and `.superpowers/` (54 files of agent scratch — specs, reports and 25 review diffs). The named-entry sweep and the enumerate-every-dot-entry sweep both flag them; `.pkgmeta` also does not name itself. Was advisory `A-3` on 2026-08-05; the sweep is normative in v2.38.0. | Add `- .claude`, `- .superpowers` and `- .pkgmeta` to the `ignore:` block in `.pkgmeta`, keeping the existing justification-comment style. One file, three lines. |
| **KICKCD-A-02** | `toc-file-§5` | Low | **Two load-bearing TOC positions carry no annotation.** `core\PerfSetup.lua` (`KickCD.toc:55`) must precede the four modules that take `local Perf = NS.Perf` **at file scope**; `settings\OptionsSetup.lua` (`KickCD.toc:73`) must precede the four `settings/` files that take `local Helpers = NS.Settings.Helpers` at file scope and evaluate `H.AnchorValues()` inside schema-row literals at load. §5 makes a comment **at the line, naming what resolves**, a MUST — it is the only guard against anti-pattern #66. Separately the SHOULD is unmet: the remaining nine `# Core` lines and the whole `# Settings` block are unannotated, so no reader can tell "free to move" from "not yet understood". | Add a `LOAD-BEARING:` comment above each of the two lines, in the shape `core\MediaSetup.lua` already uses at `:42-45` — naming `NS.Perf` and `NS.Settings.Helpers` respectively. Then add one "conventional" note per group for the unmarked remainder. `docs/ARCHITECTURE.md:286-311` already carries the reasoning; move it, do not duplicate it. |
| **KICKCD-A-03** | `localization-§5`, AP #46 | Low | **51 British spellings in authored English**, across 12 live files: `colour`/`colours`/`Colour`/`coloured` and `behaviour`. Worst concentration is `docs/settings-panel.md` (20 hits, including the heading `## The class-colour companion`); also `docs/smoke-tests.md` (6), `settings/Panel_Widgets.lua` (5, code comments), `docs/module-map.md` (4), `tests/test_settings_spells_editor.lua` (4), `tests/test_schema.lua` (3), `docs/common-tasks.md` (3), `docs/ARCHITECTURE.md` (2), and one each in `settings/Panel_Render.lua`, `locales/enUS.lua` (a comment, **not** a key), `tests/wow_mock.lua`, `tests/test_options_panel.lua`. US English is the collection's source dialect. Recurs from `KCD-47`, which fixed one plan file and left this set. | Sweep the twelve files: `colour`→`color`, `colours`→`colors`, `coloured`→`colored`, `Colour`→`Color`, `behaviour`→`behavior`. **No locale key changes** — the one `locales/enUS.lua` hit is a comment, so no call site moves. Do **not** touch frozen bundles under `docs/audits/`, `docs/reviews/`, `docs/automated-tests/<run>/` or `docs/perf-analysis/<run>/`. |
| **KICKCD-A-04** | `line-endings-§1`, `line-endings-§6` | Low | **8 tracked files disagree with the declared `eol=crlf` pin.** `.gitattributes` itself is byte-identical to line-endings-§5's client-bound canonical body, so this is the adopt-and-stop-there failure §1 names: `git add --renormalize` fixes the index and never the working tree. Reported as **one** rolled-up finding with the command in `03_EVIDENCE.md` §5 so the number reproduces; the files are deliberately not enumerated, because the fix is one action. Note the number is not comparable with any pre-v2.28.1 bundle's, whose command counted binaries and JSON as strays. | `git add --renormalize .`, then re-checkout the stragglers (`rm <path> && git checkout -- <path>`) and verify with the byte counts the repo's own `.gitattributes` footer documents. Commit as its own change. |
| **KICKCD-A-05** | `automated-tests-§4`, AP #51 | Low | **The automated-test record no longer matches the code, in three ways.** (a) The newest bundle is `20260825-103417`, which predates the `feat/settings-revamp-v2` merge (`1dca167`) and six commits under it. (b) `RESULTS.md`'s standing prose is anchored two runs further back still — `:36` says *"756 cases"*, `:60` says *"Clean over 33 files as of 20260807-114618"*, `:120` says *"Current state as of 20260807-114618"* — while the table's own newest row (`:23`) reads 780 tests over 35 lint files and today's suite is **841**. (c) `:135-141`'s watch list asserts *"Functions `lizard` warned on: **None.**"*, but the standard's verbatim invocation run today warns on **one** function, CCN **18**, at `tests/test_schema.lua:595-631`. The checkpoint is **release**, so this is a finding about the release process, not about gating commits. | Run `tests/_kit/run-automated-tests.sh` to produce a current bundle, which regenerates the table row. Then rewrite the four standing prose sections against the new numbers and give the CCN-18 function a disposition in the warned-functions table. Note in the same pass that the release gate ("zero functions above CCN 15") would **block a tag today**. |
| **KICKCD-A-07** | `documentation-§3` | Low | **`docs/ARCHITECTURE.md` does not carry two of the ten mandated section names.** There is no `## Overview` (the opener is `## What it does`, `:7`) and no `## Module map` — that material is split across `## Subsystems at a glance` (`:22`) and `## Load order` (`:286`). §3 names all ten *"because a bare count goes stale silently"*, and the spill rule addresses *Module Map* by name, which a reader cannot apply to a section that is not there. The other eight are present and correct. Adjacent, and reported not filed: `## Documentation map` uses **four** tables where the template has three, the fourth being a sensible *Verification and record* grouping for the five docs §3 names. | Rename `## What it does` → `## Overview` and `## Subsystems at a glance` → `## Module map` (its body already summarizes and links to `module-map.md`); either fold `## Load order` into it as a summary plus the existing link, or leave it as an extra section beneath. Update `docs/ARCHITECTURE.md`'s own map row and any inbound anchors. |
| **KICKCD-A-08** | `events-frames-taint-§8` | Low | **A `_G.print` fallback arm at a call site.** `modules/Castbar_Debug.lua:125` binds `local print = NS.Util and NS.Util.print or _G.print`. §8's second unrelaxed rule is unqualified — *"No addon calls the global `print()` for user-facing output — at any site"* — and it is about the missing `NS.PREFIX` tag, not about secrets. The arm is **unreachable today**: `core/CoreSetup.lua` defines `Util.print` on both the library-present and library-absent paths, which is why this is Low rather than a live defect. `docs/ARCHITECTURE.md:278-284` records it as open and says it should go; it is not a register row and is not ratified. | `local print = NS.Util.print`. `tests/test_castbar_debug.lua` already drives the file and characterizes the change. |
| **KICKCD-A-10** | `options-ui-§1`, `documentation-§3` | Low | **The register's sixth row is PROVISIONAL and unratified** (`docs/ARCHITECTURE.md:241`, note at `:244-261`): the degraded Options stub's five schema composers answer an empty table, so a LibKa0s-less load registers 112 of 228 schema rows. The row is filed here because the register itself instructs it — the entry is *"a recorded decision under review, not a ratified deviation"*. The cause is a genuine conflict **inside** options-ui-§1: the stub MUST be load-completing, and the stub MUST NOT hold a host copy of composed row sets. No per-addon change resolves it, and the same row will be inherited by the other eight addons. Blast radius is measured and empty — on that load the schema CLI and the panel are both absent too. | **Not an addon fix.** Take the ruling upstream: either `LibKa0s-Options-1.0` ships the composers in a file that loads and answers without the Options major, or `options-ui-§1` states which of its two MUSTs wins. When the ruling lands, either close the row or restate it as ratified with a Decided date. |

## SHOULD failures (Low)

| ID | Section(s) | Grade | Deviation | Fix direction |
|---|---|---|---|---|
| **KICKCD-A-06** | `performance-§4`, `standalone-windows` | Low | **The perf panel's `decorate` hook is a second copy of library behavior.** `core/PerfSetup.lua:217-226`'s hook body is nothing but a close button built through `NS.MakeCloseButton` and anchored. Since `PerfPanel.lua` minor 4 — and the vendored copy **is** minor 4 (`libs/LibKa0s/PerfPanel.lua:13`) — the library's own `else` arm at `:190-196` draws the identical control with the host's own name and the identical anchor. The hook is correct today and is a place the two can fall out of step; the comment above it argues for a wrapper the library now uses itself. | Delete the `decorate` field from the descriptor and the hook body with it, and let `PerfPanel`'s `else` arm draw the control. `d.addonName` is already supplied. Re-check the panel in a smoke pass; nothing in `tests/test_perfsetup.lua` asserts the hook exists. |
| **KICKCD-A-09** | `automated-tests-§5` | Low | **Two run bundles carry no `ANALYSIS.md`.** `docs/automated-tests/20260825-103417/` and `docs/automated-tests/20260807-110522/` have none, while the other five do. §5 makes it a MUST at release and a **SHOULD** for any run whose numbers moved — and `20260825-103417`'s did move on every column (tests 756→780, lint files 33→35, NLOC 15533→15802). No manifest in the store records `release`, so the MUST arm has not been triggered. | Bundles are frozen evidence, so do not backfill `20260807-110522`. For the run this audit's `KICKCD-A-05` calls for, write its `ANALYSIS.md` from the root `AUTOMATED_TESTS.md` prompt as part of producing it, and say in it what moved across the `20260825`→now gap. |

## Info

| ID | Section(s) | Grade | Note |
|---|---|---|---|
| **KICKCD-A-11** | `toc-file-§1`, `audit-review-history` | Info | `KickCD.toc:14` carries a commented `# ## X-Wago-ID: <id>   -- TODO(KCD-18): add once published on Wago`. The commented field is **compliant** — `X-Wago-ID` is a MAY and a comment is an omission, so field order and the no-blank-lines rule both hold. What is stale is the marker: `KCD-18` was a ledger ID, the ledger is retired collection-wide, and no GitHub issue on this repo tracks Wago publication. Either open a `state:triaged` issue and cite its number, or drop the marker and keep the bare comment. |
