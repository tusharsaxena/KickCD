# KickCD — Execution Plan (2026-09-23)

This is the ordered hand-off to the remediation engagement. Every step names the ids it closes and
the design section (`04_TECHNICAL_DESIGN.md` Dn) that specifies it.

**Gate after every sprint:** run `~/.claude/wow-addon/bin/ka0s-bounded lua tests/run.lua` and expect
0 failed, then run `~/.claude/wow-addon/bin/ka0s-bounded luacheck .` and expect 0/0. `docs/test-cases.md`
and the `[tests]` badge are regenerated whenever the case count changes.

**What this plan covers, and the figures it uses.** It covers the **23 roots and 4 dependents** in
`02_DEVIATIONS.md` (1 High, 1 Medium, 20 Low including dependents, 5 Info). The figures here are the
same ones `02` and `03` use:

- 25 unrecorded tags
- 36 frames leaked per cycle
- 8 bare `§N` sites
- 8 and 30 file headers
- 8 shims in a 485-line `Compat.lua`
- 7 Spells-page registrations
- a 468-line hub

---

## Sprint 0 — Upstream first (LibKa0s, WowAddonStandards)

Nothing in KickCD's `libs/` or `tests/_kit/` is edited by hand.

| Step | Ids | Work | Done when |
|---|---|---|---|
| 0.1 | B-02 (cause) | In **LibKa0s** `testkit/test_prose.lua`, narrow `SKIPPED_DIRS` from `docs/perf-analysis/` and `docs/automated-tests/` to their dated-bundle children, so that each store's `README.md` and `RESULTS.md` are scanned (D9 U1). Bump the kit revision, run LibKa0s's own suite, and release a tag. | A LibKa0s tag exists whose kit scans `docs/perf-analysis/README.md` |
| 0.2 | C-14 | **WowAddonStandards**: ask for a ruling on whether `slash-commands-§2`'s `enable`/`disable` reservation reaches sub-tree verbs (D9 U2a). | A ruling or an open-evolutions entry exists |
| 0.3 | C-01 (grade and shape) | **WowAddonStandards `AUDIT.md`**: reconcile the re-vendor check's explicit **High** with step 5, and state how a consolidated bundle names its span so the check reads it (D9 U2b). | A playbook edit or an issue exists |
| 0.4 | C-13 (optional) | If no existing catalog mark reads as "remove from list", add one in LibKa0s `tools/artwork` and release it (D9 U3). | A mark is chosen or added |

## Sprint 1 — Re-vendor LibKa0s whole

| Step | Ids | Work | Done when |
|---|---|---|---|
| 1.1 | B-02 (gate) | Run `/wow-addon:revendor-libka0s` to the tag from 0.1. Copy the **whole** `LibKa0s/` ship folder over `libs/LibKa0s/` and the whole `testkit/` over `tests/_kit/`, update `CLAUDE.md:42` in the same commit, and write the `docs/revendor/<date>-v<tag>/` bundle. | `diff -r` against the tag is empty for both folders, `test_vendor_sync` is green, and **`test_prose` is red** on `docs/perf-analysis/README.md:35-36` |
| 1.2 | B-02 | Change "analysed" to "analyzed" and "neighbours" to "neighbors" at `docs/perf-analysis/README.md:35-36`. | `test_prose` is green |

## Sprint 2 — Code (red first, then fix)

| Step | Ids | Work | Done when |
|---|---|---|---|
| 2.1 | C-03 | Add the `test_disabled` case "a disable/enable cycle creates no frames" (D1) and **see it red**, with 36 frames. | The case fails on HEAD |
| 2.2 | C-03 | Implement `Util.NewUnitFilter`, `Arm` and `Disarm`, and move `IconGrid` and `Castbar` to `inst.unitFilter`. Retire `RegisterUnitCastEvent`, or narrow it to the cast family, and update the Resume guard at `modules/Castbar.lua:1136` (D1). | 2.1 is green and the whole `test_disabled` suite is green |
| 2.3 | C-02 | Add a `__badEvents` case, **see it red**, then add `Util.SafeRegister` with the `IsEventValid` front gate, the rejected-name record, and `/kcd debug events`. Route every registration block, and D1's `Arm`, through it (D2). | Registration continues past a bad name, and the name shows in `/kcd debug events` |
| 2.4 | C-04 | Move `cacheEvents` (`settings/Spells.lua:375-381`) and `boot` (`core/State.lua:143-146`) to AceEvent targets, **or** get the owner's decision to keep `boot` and write the register row (D3). | No private frame carries non-unit events, or a row ratifies the one that does |
| 2.5 | A-08 | Add the `test_source_style` `or _G%.print` scan and see it red. Then fix the three sites (D4). | The scan is green |
| 2.6 | C-13 | Draw the Spells remove button with a catalog mark through `NS.Icon` (D7). | `settings/Spells.lua` no longer uses `transmog-icon-remove` |

## Sprint 3 — TOC

| Step | Ids | Work | Done when |
|---|---|---|---|
| 3.1 | C-16, C-16a to C-16d | Add two `LOAD-BEARING POSITION:` comments above `KickCD.toc:96-97` and `:99-101` (D5). | All five positions are annotated |
| 3.2 | A-02 | Add one conventional note per group: Locales, the rest of Core, Defaults, Modules, and Settings past Panel (D5). | Every group states whether its positions are free |

## Sprint 4 — Docs (after the code, so the docs describe the final tree)

| Step | Ids | Work | Done when |
|---|---|---|---|
| 4.1 | C-05 | Rewrite the combat cells at `README.md:97` and `:113` to describe the refusal, then run the de-AI pass. | The README matches `NS:OpenSettings` |
| 4.2 | C-06 | Write `docs/debug.md`, covering the `spells`, `castbar`, `interrupt` and `events` dumps. Flip the map row at `ARCHITECTURE.md:356` to Present, with the trigger stated (D6). | The row and the doc agree with the tree |
| 4.3 | C-07 | Collapse the six LibKa0s-Compat rows in `docs/compat-layer.md` into one link (D6). | No library contract is restated |
| 4.4 | C-08 | Re-derive every inventory with a recorded command, and replace line citations into other files with symbols or section ids (D6). Covers `ARCHITECTURE.md:77-81`, `:281`, `:352`, `:353`; `core/LifecycleSetup.lua:113`; `.luacheckrc:24-28`, `:89`; `.pkgmeta:17`, `:20`, `:21`. | Every figure matches its command |
| 4.5 | B-03 | The owner rules on the first `savedvariables-§1` row: retire it, or rewrite it to name the three migrators and restate the trigger. Replace the `#L256` and `#L266` anchors with heading anchors (D6). | The row is true of the tree, or has been retired |
| 4.6 | B-06 | Change `ARCHITECTURE.md:367` to the documentation-§3 template wording. | Done |
| 4.7 | C-15 | Qualify the 8 bare `§N` sites. Rename the three `test_debuglog` titles, then regenerate `docs/test-cases.md` and check the badge in the same commit (D6). | A re-run of the E9 bare-`§N` sweep finds none |
| 4.8 | C-09 | Spill the stand-down section and split the `:117` bullet, so `ARCHITECTURE.md` is under about 400 lines (D6). Do this **last** in the sprint, after every other hub edit. | `wc -l` is under about 400, and every map row still resolves |

## Sprint 5 — Records and the issue store

| Step | Ids | Work | Done when |
|---|---|---|---|
| 5.1 | C-01 | Write one consolidated bundle, `docs/revendor/<date>-v1.18.0-to-v1.53.0/` with `01_DELTA.md` and `05_SUMMARY.md`, listing all 25 tags and their commits, in the shape 0.3 settles (D8). | The `AUDIT.md` payload-derived check prints **0** unrecorded tags |
| 5.2 | C-11 | Close #15 with `state:done`, or relabel it `state:triaged`. | The label and the state agree |
| 5.3 | C-12 | Comment on #12 recording the Widgets adoption. | Done |
| 5.4 | B-05 | Strip `[Optional]` from #9's title. | Done |
| 5.5 | C-14 | Apply the ruling from 0.2. If the reservation reaches sub-trees, rename `/kcd spells enable\|disable` to `track` / `untrack`, updating the docs, the tests and the help text. | Resolved as the ruling says |

## Sprint 6 — At the next release (the checkpoint)

| Step | Ids | Work | Done when |
|---|---|---|---|
| 6.1 | B-04, C-10 | Run `tests/_kit/run-automated-tests.sh` for the release (kit rev 25 or later adds the commit and dirty cells). Rewrite the watch-list dispositions: give each band entry a live issue or a fix, starting with `settings/Spells.lua` (1444, past its own 1400 line). Write the first disposition for `modules/IconGrid_Render.lua`, and retire `A-2` and `KCD-30`. | `RESULTS.md`'s newest row names HEAD, and no disposition cites a retired id |

## Checkpoints

After each sprint, commit incrementally on the remediation branch. Then re-run the three mechanical
checks this audit relied on, because they are the regression net for the records:

- the `AUDIT.md` re-vendor check
- the bare-`§N` sweep from E9
- the `.gitattributes` check (e)
