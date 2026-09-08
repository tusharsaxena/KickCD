# KickCD — Technical Design (2026-09-08)

Remediation design for the six actionable rows in `02_DEVIATIONS.md` (`KICKCD-A-02`,
`KICKCD-A-08`, `KICKCD-B-01`, `KICKCD-B-02`, `KICKCD-B-03`, and the two one-line record edits in
`KICKCD-B-06`). `KICKCD-B-04` needs no design — it closes when the next release run regenerates the
record — and `KICKCD-B-05` is a single issue-title edit outside the repo.

Nothing here is large. The whole bundle is **one Lua behavior change of three identical lines**, one
test-scope narrowing, four doc edits and one register decision. The design's job is to say which of
them can move together and which must not.

---

## `KICKCD-A-08` — the three `_G.print` arms, and the gate that stops them coming back

**Files:** `core/KickCD.lua:108`, `core/Compat.lua:452`, `modules/Cooldowns.lua:538`,
`tests/test_source_style.lua`.

**Shape of the change.** Three one-line edits, each dropping the `and`/`or` guard:

```lua
-- core/KickCD.lua:108
local fn = self.Util.print
-- core/Compat.lua:452
local out = NS.Util.print
-- modules/Cooldowns.lua:538
local p = NS.Util.print
```

**Why this is safe, and how it is proved rather than asserted.** `core/CoreSetup.lua` publishes
`Util.print` on **both** arms — `:115` in the library-absent branch, `:187` in the
library-present one — and `KickCD.toc:51-58` pins `core\CoreSetup.lua` above every consumer with a
`LOAD-BEARING POSITION:` comment saying exactly why. So `NS.Util.print` is non-nil at every one of
these three call sites in both load states. `M4-20` already made this argument for
`modules/Castbar_Debug.lua` and shipped it; this is the same argument three more times.

The proof is not the reading, it is the suite: `tests/test_options_panel.lua` and the surface-parity
cases already load the addon with `LibKa0s` absent, which is the only state in which the `or` arm
could ever have been taken. If a bare table `self.Util` without `print` were reachable, dropping the
guard turns a silent no-op into a raise and one of those cases goes red. **Run them and see them
green before and after** — that is the whole verification, and it costs one command.

**The half that matters more than the three edits.** The class recurred because nothing could see
it. `tests/test_source_style.lua` already reads the addon's own sources for style facts, so the new
case belongs there and not in a new file:

```lua
test("no shipped file falls back to the global print", function()
    -- events-frames-taint-§8: the global carries no NS.PREFIX tag and secret-stringifies
    -- nothing, so a fallback arm to it is an untagged chat line waiting for a load order
    -- nobody has hit yet. KICKCD-A-08 was filed against ONE site in 2026-09-07 and fixed at
    -- that one site; three others of the same shape survived because nothing swept for them.
    for _, rel in ipairs(shippedSources()) do            -- core/ modules/ settings/ defaults/ locales/
        local n = lineMatching(rel, "_G%.print")
        assertTrue(not n, rel .. ":" .. tostring(n) .. " reaches _G.print; use NS.Util.print")
    end
end)
```

`shippedSources()` must be the **TOC's own file list**, not a glob, for the reason
`tests/_kit/loader.lua` already reads it: a glob silently stops covering a folder somebody adds.
`tests/` is deliberately out of scope — a mock may name `_G.print` legitimately.

**Ordering constraint.** Write the case first and watch it name all three files. A case that has
never been red over this tree is a case that proves nothing (`testing-§12`).

**Risk.** Effectively none, and it is bounded by the fact that all three sites are diagnostic
printers reached from `/kcd debug …` verbs. The one thing that would make this wrong is a load state
where `core/CoreSetup.lua` did not run at all, and in that state the addon has no `NS.Util` table
either and the `and` guard was already returning `_G.print` into an untagged chat line — which is the
defect, not the mitigation.

---

## `KICKCD-B-01` — moving one row between two tables

**File:** `docs/ARCHITECTURE.md` only. No code, no other document.

**Shape of the change.** Delete `:224` from `### Verification and record` and add it to
`### Conditional` (`:204-213`), re-shaped from that table's two columns to the conditional table's
three:

```markdown
| `perf-analysis/README.md` | Present | The performance harness is wired (`performance-§12`) — `core/PerfSetup.lua` publishes `NS.Perf` and `/kcd perf` takes captures |
```

Order inside `### Conditional` is not fixed by the standard; put it last, after the `debug.md`
*Not applicable* row, so the seven Tier 2 names read in the order `documentation-§3`'s own table
lists them minus the one that leads it. The `### Verification and record` table is then the mandated
six, in the mandated order.

**Why it is worth a gate.** `tests/test_doc_structure.lua` already parses `docs/ARCHITECTURE.md` for
its mandated section names and for register-id resolution, so it has the parser. What it does not do
is read the map's **table boundaries**, which is exactly why a row sat in the wrong table through
three audits. The case to add:

```lua
test("## Documentation map's fourth table holds exactly the six verification-and-record docs", function()
    local rows = mapTableRows("### Verification and record")
    assertSame({ "testing.md", "smoke-tests.md", "test-cases.md", "performance.md",
                 "automated-tests/README.md", "automated-tests/RESULTS.md" }, rows)
    assertTrue(mapTableHas("### Conditional", "perf-analysis/README.md"),
        "perf-analysis/README.md registers with its trigger, in ### Conditional (documentation-§3)")
end)
```

Note what the case must **not** assert: anything about `ARCHITECTURE.md`'s own row. That is a
**MAY**, and `documentation-§3` forbids an audit — and by extension a gate — from having an opinion
either way.

**Risk.** None. The two tables are adjacent, no anchor in the repo points at either heading (checked:
`tests/test_doc_structure.lua`'s anchor case is green over the whole file today), and no other
document links a `#verification-and-record` fragment.

---

## `KICKCD-B-02` — narrowing the spelling gate, then fixing what it finds

**Files:** `tests/test_spelling.lua:102-110`, then `docs/perf-analysis/README.md:32-33`.

**The design decision is what to replace the two directory exclusions with**, and there are two
candidates. Take the first.

1. **Exclude the dated bundles, not the store.** Keep `docs/audits/`, `docs/reviews/` and
   `docs/revendor/` as they are — every `.md` under those is inside a dated bundle — and replace the
   two store-level entries with a **stamped-directory predicate**:

   ```lua
   -- localization-§5's third exclusion is FROZEN DATED BUNDLES, not the stores that hold them.
   -- docs/automated-tests/README.md, docs/automated-tests/RESULTS.md and
   -- docs/perf-analysis/README.md are live, rewritten documents and are IN scope; only the
   -- stamped run directories beside them are frozen. Named as a shape rather than one entry per
   -- run, because a per-run list is a list the next run falls out of.
   local EXCLUDED_STAMPED = { "docs/automated-tests/", "docs/perf-analysis/" }
   -- a path is excluded when it sits under one of the above AND its next segment is a stamp
   ```

   The stamp shape is `%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d` for `docs/perf-analysis/` and the same for
   `docs/automated-tests/`, both of which the runner already writes. The predicate is four lines and
   it cannot go stale.

2. **Reject:** listing the six current run directories explicitly. It satisfies
   `localization-§5`'s *"named directory by directory rather than inferred from a pattern"* most
   literally, and it is wrong here — the next release run adds a seventh and the list silently stops
   describing the tree. The section's intent is that the **exclusion list cannot quietly grow**, and
   a shape that admits exactly one machine-written directory name is narrower than a store-wide
   exclusion, not wider.

**What comes into scope, and what it costs.** Three files: `docs/automated-tests/README.md`,
`docs/automated-tests/RESULTS.md`, `docs/perf-analysis/README.md`. Measured today with the canonical
lists, their only matches are the literal string `ANALYSIS.md`, which the gate's own
delimit-on-non-letters step reduces to `analysis` — on `ALLOWED`, so it does not redden. The two real
hits are the ones this deviation names.

**Then the prose.** `docs/perf-analysis/README.md:32` `analysed` → `analyzed`; `:33` `neighbours` →
`neighbors`. Both are prose, neither is a locale key, no call site moves.

**Ordering constraint, and it is the point of the item.** Land the scope change **first**, on its
own, and watch `tests/test_spelling.lua` go red naming both lines. A gate that is green the first
time it runs over a newly-widened scope has told you nothing about whether the widening worked.

**Risk.** One: `assertTrue(#authoredFiles() > 60, …)` at `tests/test_spelling.lua` guards against a
scan that reaches nothing. Widening can only increase that count, so the guard is unaffected. The
mirror guard — the list of files the scan **must not** reach — must gain nothing, because
`libs/`, `tests/_kit/` and the gate's own file are untouched by this change.

---

## `KICKCD-B-03` — the register row, which is a decision and not an edit

**File:** `docs/ARCHITECTURE.md:248`.

This is the only item in the bundle that cannot be executed mechanically, and the design is to say
so rather than to pick for the owner.

**The question.** The row's trigger reads *"…**or** a third shape addition under an existing profile
field — either makes a version-gated migrator sufficient and retires **both** shape-driven ones."*
Since `e143516` (2026-07-16) the tree has run **three** ungated shape-driven migrators
(`core/Database.lua:598-601`), and `Database:BackfillLabelStyle` backfills `units.<unit>.label.style`
— a field added under an existing profile field. Read literally, the trigger fired on the day the
row was written.

**Two outcomes, and each has a different fix.**

- **The trigger fired.** Then the deviation ended on 2026-07-16, the row is asserting a live
  deviation that is not one, and it **retires** — `audit-review-history`'s third MUST is explicit that
  this is the failure the rule exists to catch. Retirement is a doc change and not a re-decision: the
  three migrators stay exactly where they are, and the record simply stops calling them a departure.
  It also means the version-gated runner at `core/Database.lua:525-528` — four steps to
  `CURRENT_DB_VERSION = 5` — is what the record points at going forward.
- **The trigger did not fire**, because the author meant *a third addition after the two the row was
  written about*. Then the row stays, but **What differs** is rewritten to name all three by function
  — `FoldLegacyUnits`, `BackfillLabelStyle`, `MigrateSpecKeys` — with their call sites
  (`core/Database.lua:598-601` and `:639,:644,:651`), and the trigger is restated in a form a reader
  can evaluate without opening `Database.lua`: *"a fourth ungated shape-driven migrator"*, with a
  number in it.

**What must not happen** is the third outcome: quietly changing *Two* to *Three* and leaving the
trigger as it stands. That is the shape that produced this finding — a row that reads as maintained,
whose trigger nobody has evaluated since it was typed.

**Risk.** Zero to the code, whichever way it goes. `core/Database.lua` is not touched by this item at
all, and `tests/test_database.lua` pins the migrators' behavior independently of what the register
says about them.

---

## `KICKCD-A-02` — four conventional-group comments

**File:** `KickCD.toc` only. Comment-only; **no file entry moves and no order changes.**

Four one-line `#` comments, one above each group header that has none:

| Line | Group | The note |
|---|---|---|
| `:33` | `# Locales` | one file, reached at call time through `NS.L`; conventional |
| `:72` | `# Defaults` | read at call time by `core/Database.lua`, not at load; conventional |
| `:76` | `# Modules` | every module reaches its dependencies through closures; conventional, and pinned only by the `# Settings` header below |
| `:36` | `# Core` | the block's conventional lines are every line **not** carrying a `LOAD-BEARING POSITION:` comment |

The `# Core` note is the one that carries weight, because it is what tells a reader that `:37`,
`:49`, `:50`, `:59`, `:60`, `:61` and `:62` are free while `:47`, `:58` and `:70` are not — and it
does it without making seven lines restate their neighbor's comment, which `toc-file-§5`'s worked
example explicitly calls noise.

**Do not annotate line by line.** §5's grading table takes one SHOULD row per **file**; four group
notes close it and forty line notes close it worse.

**Risk.** None mechanical: `#` lines are skipped by every TOC parser in the repo, including
`tests/_kit/loader.lua:122` (`not entry:match("^#")`), which is how all 864 cases load the addon. The
three cases that read the raw TOC anchor their patterns at column one (`^##`, `^core\`). `M4-12` made
exactly this argument for its own comment block and it held.

---

## `KICKCD-B-06` — two record edits

**(a)** `docs/ARCHITECTURE.md:225` — change the `RESULTS.md` map description from *"generated, never
hand-edited"* to name the one exception, e.g. *"One row per run; generated by the runner, with the
watch list's `Disposition` the one authored cell."* The file itself already says this correctly at
`docs/automated-tests/RESULTS.md:68-71`, so this is bringing a one-line summary into line with the
thing it summarizes.

**(b)** `docs/automated-tests/RESULTS.md`'s band-table dispositions (`:81-84`) cite `A-2` and
`KCD-30`. Both belong to a retired id series and `docs/audits/2026-09-07/02_DEVIATIONS.md` recorded
the `KCD-30..49` set as closed. The `Disposition` column is the **one authored cell**
(`automated-tests-§4`), so it is legitimate to edit — but the edit must be made **before** the next
release run, because the runner carries the cell forward verbatim while the entry is unchanged, and
an entry whose file is still in the band is unchanged. Replace each with either a live issue number
or a plain statement (*"Watch, no action; 155 lines of headroom"*), and say nothing that points at an
id no longer assigned.

---

## Ordering constraints across the whole bundle

Only three, and everything else is independent:

1. **`KICKCD-B-02`'s gate change lands before its prose fix**, so the gate is seen red.
2. **`KICKCD-A-08`'s test case lands before the three edits**, for the same reason.
3. **`KICKCD-B-06`(b) lands before the next release run**, or the runner carries the stale
   disposition forward and the edit is owed again.

`KICKCD-B-03` blocks nothing and is blocked by nothing, but it is the only item that needs a person
rather than a diff, so it should be raised first and closed last.
