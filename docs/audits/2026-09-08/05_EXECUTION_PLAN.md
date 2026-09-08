# KickCD — Execution Plan (2026-09-08)

Hand-off to the separate remediation engagement. **This audit changed no addon code.**

Eight rows in `02_DEVIATIONS.md`; six of them are work. Two sprints, seven steps. The whole plan is
**three Lua lines, two new test cases, one test-scope predicate, six doc edits and one decision** —
sized here so nobody mistakes it for more.

Every step names its deviation id, its checkable done-condition, and what it depends on. Verification
is the same everywhere and is stated once: `luacheck .` at 0/0 and `lua tests/run.lua` fully green
before the step is called done. Steps that move the case count also regenerate `docs/test-cases.md`
and the README `[tests]` badge **in the same change** (`testing-§5`, `documentation-§1` item 2's
keep-in-sync rule).

---

## Sprint 1 — the MUST failures

Ordered so every gate is seen **red** before it is seen green. That ordering is the only thing in
this plan that is not negotiable.

### Step 1 — `KICKCD-A-08` (a): the gate that names the class

**Do.** Add one case to `tests/test_source_style.lua` asserting that no file in `KickCD.toc`'s own
listing under `core/ modules/ settings/ defaults/ locales/` matches `_G%.print`. Read the file list
from the TOC, not from a glob (`tests/_kit/loader.lua:122` already does the `^#` skip).

**Done when.** The case is **red**, naming exactly `core/KickCD.lua:108`, `core/Compat.lua:452` and
`modules/Cooldowns.lua:538`. Do not commit on red — this step and Step 2 are one commit.

**Depends on.** Nothing.

### Step 2 — `KICKCD-A-08` (b): the three edits

**Do.** `core/KickCD.lua:108` → `local fn = self.Util.print`. `core/Compat.lua:452` → `local out =
NS.Util.print`. `modules/Cooldowns.lua:538` → `local p = NS.Util.print`.

**Done when.** Step 1's case is green; `grep -rn "_G.print" --include='*.lua' core/ modules/
settings/ defaults/ locales/` returns nothing; the LibKa0s-absent cases in
`tests/test_options_panel.lua` and `tests/test_surface_parity.lua` are still green, which is what
proves `NS.Util.print` exists on the degraded path too.

**Depends on.** Step 1 (same commit).

**Commit.** One commit with Steps 1–2. Case count +1, so `docs/test-cases.md` and the README badge
move with it.

### Step 3 — `KICKCD-B-02` (a): narrow the spelling gate's scope

**Do.** In `tests/test_spelling.lua:102-110`, replace the two store-level entries
`"docs/automated-tests/"` and `"docs/perf-analysis/"` with a stamped-directory predicate that
excludes only `<store>/<YYYYMMDD-HHMMSS>/`, leaving the stores' own `README.md` and `RESULTS.md` in
scope. Keep `libs/`, `tests/_kit/`, `docs/audits/`, `docs/reviews/`, `docs/revendor/` and the gate's
own file exactly as they are. Comment the change against `localization-§5`'s third exclusion —
*frozen dated bundles* — and against `documentation-§3`'s *"the one file in the store that is
rewritten"*.

**Done when.** `tests/test_spelling.lua` is **red**, naming `docs/perf-analysis/README.md:32` and
`:33` and nothing else. The scan-coverage guard at `:209` (`#authoredFiles() > 60`) still passes and
the must-not-reach list still holds.

**Depends on.** Nothing.

### Step 4 — `KICKCD-B-02` (b): the two words

**Do.** `docs/perf-analysis/README.md:32` `analysed` → `analyzed`; `:33` `neighbours` →
`neighbors`.

**Done when.** Step 3's case is green. No locale key moved, so nothing else changes.

**Depends on.** Step 3 (same commit).

**Commit.** One commit with Steps 3–4. Case count unchanged.

### Step 5 — `KICKCD-B-01`: move one row, and gate the two tables

**Do.** In `docs/ARCHITECTURE.md`, delete the `perf-analysis/README.md` row from `### Verification
and record` (`:224`) and add it to `### Conditional` (`:204-213`) in that table's three-column shape,
Status **Present**, Trigger *the performance harness is wired (`performance-§12`)*. Then add a case
to `tests/test_doc_structure.lua` pinning `### Verification and record` to exactly its six mandated
docs and `### Conditional` to containing `perf-analysis/README.md`. The case **MUST NOT** assert
anything about `ARCHITECTURE.md`'s own row, in either direction.

**Done when.** The fourth table holds six rows; the conditional table holds seven; the new case is
green and was seen red against the pre-move file.

**Depends on.** Nothing.

**Commit.** Its own commit. Case count +1 → `docs/test-cases.md` and the badge move with it.

---

## Sprint 2 — the record, the register and the convention gap

Nothing here blocks anything in Sprint 1 and Sprint 1 blocks nothing here; the split is by kind, not
by dependency.

### Step 6 — `KICKCD-B-03`: rule the register row

**Do.** This is a **decision**, not an edit, and it is the one item in the plan that needs the
owner rather than a diff. Read `docs/ARCHITECTURE.md:248`'s trigger — *"a third shape addition under
an existing profile field"* — against `Database:BackfillLabelStyle` (`core/Database.lua:325`, called
at `:599` and `:644`), which backfills `units.<unit>.label.style` and landed in `e143516` on
2026-07-16, the row's own Decided date. Then take one of exactly two outcomes:

- **Fired** → retire the row. The three migrators stay; the record stops calling them a departure.
- **Not fired** → rewrite **What differs** to name all three by function with their call sites, and
  restate the trigger with a number in it (*"a fourth ungated shape-driven migrator"*).

**Not permitted:** changing *Two* to *Three* and leaving the trigger untouched. That is the state
this finding is about.

**Done when.** The row either is gone or describes `core/Database.lua:598-601` accurately, and its
trigger is one a reader can evaluate without opening `Database.lua`.

**Depends on.** Nothing. Raise it first, close it last.

### Step 7 — `KICKCD-A-02` and `KICKCD-B-06`: four TOC comments and two record lines

**Do.** Three edits, one commit:

1. `KickCD.toc` — four one-line conventional notes, above `# Core` (`:36`), `# Locales` (`:33`),
   `# Defaults` (`:72`) and `# Modules` (`:76`). The `# Core` note says the block's conventional
   lines are every line **without** a `LOAD-BEARING POSITION:` comment. **Comment-only: no file entry
   moves and no order changes.**
2. `docs/ARCHITECTURE.md:225` — restate the `RESULTS.md` map description to name the one authored
   cell, matching what `docs/automated-tests/RESULTS.md:68-71` already says.
3. `docs/automated-tests/RESULTS.md:81-84` — replace the `A-2` / `KCD-30` citations in the four
   `Disposition` cells with something that resolves: a live issue number, or a plain statement with
   no id in it. **Before the next release run**, because the runner carries an unchanged entry's
   disposition forward verbatim.

**Done when.** `KickCD.toc` still parses (the suite is the proof — all cases load the addon through
`tests/_kit/loader.lua`); no `Disposition` cell names a retired id; `docs/ARCHITECTURE.md:225` and
`RESULTS.md:68-71` agree.

**Depends on.** Nothing. Step 7's third edit is the only thing in this plan with a **deadline** —
the next release run.

---

## Not in this plan

| Row | Why |
|---|---|
| `KICKCD-B-04` | The record trails HEAD by one commit. It closes when the release run regenerates `docs/automated-tests/RESULTS.md` and the bundle; there is nothing to hand-edit and hand-editing it would be the worse defect. |
| `KICKCD-B-05` | One issue-title edit on GitHub (`gh issue edit 9`), outside the repo. Strip `[Optional]` on the next edit that touches #9 for another reason; not worth an edit of its own. |
| The five ratified register rows | Accepted, cited in `02_DEVIATIONS.md` with each row's rule re-resolved against v2.39.0 and each trigger evaluated against the tree. `audit-review-history` forbids re-filing them, and nothing here asks for a change to any of them except `KICKCD-B-03`'s. |

## What the whole plan costs

| Sprint | Steps | Files touched | Lua behavior change |
|---|---|---|---|
| 1 | 1–5 | `core/KickCD.lua`, `core/Compat.lua`, `modules/Cooldowns.lua`, `tests/test_source_style.lua`, `tests/test_spelling.lua`, `tests/test_doc_structure.lua`, `docs/perf-analysis/README.md`, `docs/ARCHITECTURE.md`, `docs/test-cases.md`, `README.md` | three lines, all on unreachable fallback arms |
| 2 | 6–7 | `KickCD.toc`, `docs/ARCHITECTURE.md`, `docs/automated-tests/RESULTS.md` | none |

Three commits in Sprint 1, two in Sprint 2. No version bump: nothing a player can see changes, so
`versioning-git`'s release path is not entered by any step here.
