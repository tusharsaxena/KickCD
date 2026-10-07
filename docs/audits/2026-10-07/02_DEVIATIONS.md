# KickCD — Deviations (2026-10-07)

**Addon:** Ka0s KickCD 1.4.0 · **HEAD:** `43aa263` · **Standard:** **v2.76.1 (2026-10-07)**
**Prefix:** `KICKCD-`. Rows carried over from earlier runs keep their `A-`, `B-` and `C-` ids.
Rows new in this run use the `KICKCD-D-` series.

## The two tallies, and their basis

| Tally | Count | Basis |
|---|---|---|
| **Headline (roots only)** | **7** | One row per independent cause. No row in this run is `derived from` another. |
| **Total including dependents** | **7** | 7 roots + 0 dependents |
| **MUST failures, roots only** | **4** | `C-01`, `C-08`, `C-15`, `D-01` |
| **MUST failures including dependents** | **4** | Same four, because there are no dependents |
| **SHOULD failures** | **0** | — |

**By impact grade, roots only:** High **0** · Medium **0** · Low **4** · Info **3**.
**By impact grade, including dependents:** High **0** · Medium **0** · Low **4** · Info **3**.

**What the grades mean here.** No row can be reached by a player, by `KickCDDB` or by a game
session today. The four Lows are MUST failures, and each one is a record, a comment, a document or a
constant's name. They are graded Low under `AUDIT.md` step 5 (*"a doc-only or config-only failure is
Low or Info even when the rule it fails is a MUST"*), and each entry still names its MUST. The three
Infos are observations: a stale release record, a closed decline the tree contradicts, and a
kit-generated count.

**Verdict: minor deviations.** The heavy checks this cycle runs all pass. They are the disabled-state
registration census (`slash-commands-§7`), the diagnostics dump (`debug-logging-§14`), the library's
own debug lines (`debug-logging-§4`), the launcher menu and tooltip (`launcher-§1/§2`), the sighted
complexity gate (`automated-tests-§3`), the line-ending pin, packaging, the documentation map and the
vendored-payload `diff -r`.

## Movement since 2026-09-23 (v2.64.0)

The previous run filed **23 roots and 4 dependents**. **19 roots and all 4 dependents are closed
outright.** `C-01` closed and reopened with two newer tags. `C-08` and `C-15` recur on different
sites. `B-04` recurs as Info. **Three rows are new:** `D-01`, `D-02` and `D-03`. 4 recurring + 3 new
= 7.

| Prior id | Status today | Evidence |
|---|---|---|
| `KICKCD-C-01` | **Reopened.** The 25-tag backlog is recorded by `docs/revendor/2026-09-24-v1.16.0-v1.54.2/`. Two newer tags, v1.69.0 and v1.70.0, have no bundle. | E1 |
| `KICKCD-C-03` | **Closed.** One cast-filter frame per (module, unit), re-armed and never rebuilt (`core/Util.lua:503-529`). `tests/test_disabled.lua` counts frames across cycles. | E12 |
| `KICKCD-A-08` | **Closed.** No `_G.print` in the shipped source. | E12 |
| `KICKCD-B-02` | **Closed.** No British spelling in `docs/perf-analysis/README.md`. | E12 |
| `KICKCD-B-03` | **Closed.** The row names five migrators and cites heading anchors that resolve. | E10 |
| `KICKCD-C-02` | **Closed.** Every registration goes through the Core `SafeRegister*` family, with a rejected list surfaced by `/kcd debug events` and diagnostics. | E12 |
| `KICKCD-C-04` | **Closed.** State is an AceEvent target. The Spells page uses `NS.NewBusTarget()`. | E12 |
| `KICKCD-C-05` | **Closed.** `README.md:100` and `:117` say to run `/kcd config` again. | E12 |
| `KICKCD-C-06` | **Closed.** `docs/debug.md` exists and is registered as Present (`docs/ARCHITECTURE.md:297`). | E9 |
| `KICKCD-C-07` | **Closed.** `docs/compat-layer.md:7` points at the library's doc instead of restating it. | E12 |
| `KICKCD-C-08` | **Recurs**, with four different stale statements (below). | E3 |
| `KICKCD-C-10` | **Closed.** Every band row names a live issue (#24 to #32), all now done. The band is empty at HEAD. | E8 |
| `KICKCD-C-11` | **Closed.** #15 is `CLOSED`, `state:done`. | E11 |
| `KICKCD-C-13` | **Closed.** The remove button draws the catalog's `close` mark. The atlas is the library-absent fallback only (`settings/Spells_Rows.lua:251-256`). | E12 |
| `KICKCD-C-15` | **Recurs.** The code-comment sites are gone. There are 17 bare `§N` sites in tests and docs. | E4 |
| `KICKCD-C-16` (+a–d) | **Closed.** Both sibling groups are annotated (`KickCD.toc:110`, `:121`). | E12 |
| `KICKCD-A-02` | **Closed.** Every group carries a conventional note (`KickCD.toc:40`, `:44`, `:100`, `:106`, `:153`). | E12 |
| `KICKCD-C-09` | **Closed.** The hub is 405 lines and every mandated section is spilled. documentation-§3: *"the failure they catch is 1071 lines, not 412"*. | E9 |
| `KICKCD-B-04` | **Recurs (Info).** The record is 81 commits stale, and no sighted bundle exists yet. | E7 |
| `KICKCD-B-05` | **Closed.** #9 is closed with a clean title. | E11 |
| `KICKCD-B-06` | **Closed.** `docs/ARCHITECTURE.md:308` carries the Disposition carve-out. | E9 |
| `KICKCD-C-12` | **Closed.** #12 carries a 2026-09-24 "Superseded" comment. | E11 |
| `KICKCD-C-14` | **Closed by the standard.** v2.65.0 lets a noun's sub-tree reuse `enable`/`disable` (`slash-commands-§2`). | — |

## Recorded deviations — accepted, not re-filed, not counted

`docs/ARCHITECTURE.md:329-338` has **eight** rows. This run read the register before it filed
anything. For every row it did three things, which are `audit-review-history`'s three MUSTs: (1) it
resolved the cited rule against v2.76.1, (2) it evaluated the re-check trigger against HEAD, and (3)
it resolved every evidence id the row cites.

| Rule | Decided | Rule changed since the row? | Trigger fired? | Evidence ids | Status |
|---|---|---|---|---|---|
| `savedvariables-§1`: five shape-driven migrators | 2026-07-16; rewritten 2026-09-24 | v2.65.0 rewrote §1 (stamp ownership, per-profile steps) on 2026-09-23. The row was rewritten the next day against it. The rule permits a per-profile stamp, not shape detection, so the behavior is not permitted outright | No. Still five steps (`core/Database.lua:662-669`), and no LibKa0s migration runner exists | `schema.md#unitsunitlabelstyle-shape` → `docs/schema.md:245` resolves. #8 resolves (closed, done) | **Accepted** |
| `savedvariables-§1`: `units.<unit>` restructure | 2026-07-15 | No change to the expectation the row cites | No. `defaults/Profile.lua:309`, `:320` still declare only target and focus | `schema.md#migration-folding-…` → `docs/schema.md:277` resolves | **Accepted** |
| `options-ui-§1`: host `LSMValues` / `AnchorValues` / `AnchorOrder` | 2026-08-05 | v2.75.0 added `addonName`. The load-completing rule the row rests on is unchanged | No. `settings/Icons.lua:58-59` and `settings/Castbar.lua:223-224` still evaluate them at file load | `tests/test_options_panel_degraded.lua` exists | **Accepted** |
| `options-ui-§15`: the visibility value list | 2026-09-02 | The value set is unchanged | No. The composer still hard-codes `values = VISIBILITY_VALUES` (`libs/LibKa0s/OptionsCompose.lua:479`) | Resolves | **Accepted** |
| `options-ui-§13`: Grid Defaults scoped to the unit in the band | 2026-09-26 | v2.69.0 (same day) bounds a railed page's Defaults by "the set the folded sub-page's own button restored". It does not address a band picking one of several instances, which is the row's trigger | No | KickCD#33 closed `state:done`. `tests/test_settings_log.lua` exists | **Accepted** |
| `events-frames-taint-§8`: `safeRender` | 2026-08-05 | §8 is unchanged in the part the row cites | No. Core publishes no `Describe`/`RenderValue`, and `safeRender` has no caller outside the interrupt dump (`core/Compat.lua:386`, `:460`) | `:370-378` and `:382-387` resolve exactly | **Accepted** |
| `options-ui-§14`: the two-row Spells band | 2026-09-22 | No | No. The vendored v1.70.0 `IdInput` has no compact form | Resolves | **Accepted** |
| `architecture-§5`: spell-entry `enabled` / `category` | 2026-09-12 | No | No | #16 and #17 are closed `state:done` | **Accepted** |

**Declines that owe no row.** #12 and #14 are module declines, which library-stack-§3/§7 count as
compliance. #23 declines optional `RenderTabbedSchema` opts. The page still draws the library's
`H.TabStrip`, so it departs from no MUST. **#11's text is contradicted by the tree (`D-02`).**

---

## Low — MUST failures

| ID | Section | Grade | Deviation | Fix direction |
|---|---|---|---|---|
| **KICKCD-C-01** | `audit-review-history` (*A re-vendor commit implies a bundle*), MUST | Low | **Two LibKa0s tags were vendored with no re-vendor bundle and no register row.** The payload-derived check (`AUDIT.md` step 4) finds 52 tags vendored since the 2026-08-25 horizon and 50 recorded. The two missing are **v1.69.0** (`da8a8b8`, "chore: re-vendor LibKa0s v1.69.0 (kit 37; adds the line chart widget)") and **v1.70.0** (`9d4a10b`, "chore: re-vendor LibKa0s v1.70.0"). The newest bundle is `docs/revendor/2026-10-04-v1.68.1/`. Both commits moved only the payload, the kit and the provenance line. No player can reach this, so it is Low under step 5. | Write **one** consolidated span bundle, `docs/revendor/<date>-v1.68.1-v1.70.0/`, with `01_DELTA.md` line 1 exactly `Delta: LibKa0s v1.68.1 -> v1.70.0 (span: v1.68.1 v1.69.0 v1.70.0)` and one `05_SUMMARY.md` line per tag (*carried by sweep, nothing adopted*, since KickCD uses neither `LineChart` nor `Autocomplete`). Route future re-vendors through `/dev-copilot:wow-revendor-libka0s`, which writes the bundle. |
| **KICKCD-C-08** | `documentation-§5` (docs kept in sync), MUST | Low | **Four stated inventories or descriptions no longer match the tree.** This is one rolled-up finding, because the fix is one sync pass. (1) `docs/ARCHITECTURE.md:79-83` says "Eight do" read `addonName` and "The other thirty-six write `local _, NS = ...`". The tree has **9 and 41** (50 shipped files). `settings/OptionsSetup.lua:1` joined the readers when v2.75.0's `addonName = addonName` landed (`:157`). (2) `.luacheckrc:25-29` repeats "Eight files in this addon do read it" and "thirty-three authored files open that way today". (3) `docs/compat-layer.md:34` says `NS.State.SetInCombat` is "Called only by that file's bootstrap `CreateFrame`". The listener is an AceEvent target (`core/State.lua:161-162`), which the hub itself says (`docs/ARCHITECTURE.md:100`). (4) `.pkgmeta:22-23` says the ignored tracked payload is "Seven files, 7.5M". `media/screenshots` now holds **2** tracked files, 4,812,069 bytes. | Correct each figure from a recorded command. Prefer wording that cannot rot, such as "every file that hands the folder name to a LibKa0s seam" instead of a count, and "an AceEvent target" in `compat-layer.md`. Re-measure `.pkgmeta`'s comment, or drop the count. |
| **KICKCD-C-15** | Index *Reading this document* (`filename-§N` is *"the **only** cross-reference form"*), `documentation-§5`, MUST | Low | **Seventeen bare `§N` citations name no file.** `tests/test_flow_traces.lua` has 12, at `:28`, `:52`, `:68`, `:83`, `:110`, `:133`, `:145`, `:216`, `:228`, `:258`, `:275` and `:318` (`§8`, `§9`, meaning `debug-logging-§8/§9`). `tests/test_library_lines.lua:97` has 1 (`§8`). `docs/settings-panel.md` has 2, at `:62` (`§7`, options-ui) and `:203` (`` `§14` ``, options-ui). `docs/slash-dispatch.md` has 2, at `:70` and `:97` (`§7`, slash-commands). Each file states the qualified form once, higher up, and then drops it. The 2026-09-23 run counted continuation shorthand as compliant only inside the same sentence, and the same scope is kept here. The 75 `§N` hits in `docs/smoke-tests.md` are that document's own retired section numbers ("the old `§36`") and are **not** standard citations. The scope and command are in E4. | Qualify each site (`debug-logging-§8`, `options-ui-§7`, `options-ui-§14`, `slash-commands-§7`). Regenerate `docs/test-cases.md` only if a case title changes; none of these sites is a title. |
| **KICKCD-D-01** | `savedvariables-§1` (*"**MUST** hold the runner's target in `NS.SCHEMA_VERSION`, equal to the highest step's `to`"*), MUST | Low | **The runner's target is a file-local `CURRENT_DB_VERSION`, republished as `Database.CURRENT_DB_VERSION`, and `NS.SCHEMA_VERSION` does not exist.** `core/Database.lua:36` reads `local CURRENT_DB_VERSION = 5` and `:39` reads `Database.CURRENT_DB_VERSION = CURRENT_DB_VERSION`. `git grep SCHEMA_VERSION` over the shipped source is empty. The value itself is correct: 5 is the highest step's `to` (`core/Database_Migrations.lua:321-329`, migrations `[1]` to `[4]`), and the runner owns the stamp. Only the name is wrong. The rule arrived in v2.65.0, after the previous audit. Nothing a player can reach differs. | Publish `NS.SCHEMA_VERSION = 5` in `core/Database.lua` and have the runner and `modules/Diagnostics.lua:103-104` read it. Keep `Database.CURRENT_DB_VERSION` as an alias only if a test needs it, or delete it. Add a case pinning `NS.SCHEMA_VERSION` to the highest step. |

## Info

| ID | Section | Grade | Note |
|---|---|---|---|
| **KICKCD-B-04** | `automated-tests-§4`, `automated-tests-§3` (*The complexity gate is sighted*), AP #51 | Info | **The record trails HEAD by 81 commits, and no sighted bundle exists yet.** The newest row, `20260927-030444`, measured `bcf9e51` (clean). `git rev-list --count bcf9e51..HEAD` = **81**. That run predates kit revision 35 (`3901b38`), so its `manifest.json` has no `suites.complexity.blindFiles`. Today's sighted `--no-bundle` run passes: 0 warnings, max CCN 15, 3,580 funcs. Since that run, tests went 1201 → 1303, files 112 → 127, funcs 3,089 → 3,580, and the 1000–1500 band went from 9 files to 0. The last release is `1.4.0-release` (`a06e2aa`). The checkpoint is **release**, so this is recorded and not filed against the addon. The next release run must write a sighted bundle with `blindFiles` 0. |
| **KICKCD-D-02** | `audit-review-history` (a closed decline is a record a re-vendor reads) | Info | **Closed decline #11 ("Adopt LibKa0s `RenderGrid` as a second consumer", `state:will-not-do`) is contradicted by the tree.** The Spells list now paints through `H.RenderGrid` (`settings/Spells.lua:615`, KickCD#10, `e0da04c`), and so does a General page row (`settings/General.lua:351`). #11 has no comment recording the reversal. It owes no register row, because adopting a library member is not a deviation. This is the same shape as `C-12` on #12, which a comment closed. | Comment on #11: superseded by #10 (`e0da04c`), which adopted `RenderGrid` once the two LibKa0s gaps it names were closed. Leave it closed. |
| **KICKCD-D-03** | `testing-§5` (*a skip "**MUST NOT** be folded into either the passed count or the total"*) | Info | **`docs/test-cases.md`'s Totals table folds the one skipped case into its total.** `docs/test-cases.md:1620` reads `**Total** | **1303**`, while the run is 1302 passed, 1 skipped. The README badge reads `1302/1302` (`README.md:7`), which follows §5. That leaves the file's own header (`:3-5`, "the README test badge ... must agree with it") contradicting itself. The skip is listed with its reason (`:1524`), as §5 asks. The table is the kit's `--list` renderer's output, regenerated byte-identical today (`diff` empty), and the skip is decided at run time. So the cause is upstream, and an edit here would be overwritten. | Upstream, in LibKa0s `testkit`: have `--list` mark a case that can only skip on this host, or have the Totals line read `1303 (1 skips here)`. Re-vendor when it lands. No local edit. |
