# KickCD — Final Summary (post-implementation)

**Date:** 2026-08-05
**Status:** written **in advance** of implementation, under the assumption that every check in
`03_SMOKE_TESTS.md` passes. Fill in the sign-off table and the commit range before using this as a
PR description.
**Derived from:** `02_PROPOSED_CHANGES.md` + `04_EXECUTION_PLAN.md`

---

## Headline

This cycle fixed a settings option that never worked, and closed the gaps in the machinery that was
supposed to have caught it. The cast bar's **spell name color** — a documented, shipped setting with
its own color picker on both the interruptible and uninterruptible rows — had no effect on any
profile: the code that painted it still read the *old* positional color layout that the v3→v4
schema migration retired, so it silently fell back to white every time. Alongside that, the review
made the addon's own evidence honest: two performance brackets that quietly under-counted their
buckets now close on every exit; the vendored-payload gate no longer reports success on machines
where it could not actually look; the "reset everything" path stopped doing half its work twice; and
the perf figures the code cites in its own design comments now have a committed record behind them.
Nothing here changes how the addon behaves in combat, and no saved data is migrated or lost.

---

## Counts

| Severity | Found | Addressed | Deferred |
|---|---|---|---|
| Critical | 0 | 0 | — |
| High | 2 | 2 | — |
| Medium | 6 | 5 | 1 |
| Low | 4 | 4 | — |

**Deferred:** **F-003** (a private options-page registration system running alongside the adopted
`LibKa0s-Options-1.0`). Deferred deliberately to milestone M7 with its own architectural checkpoint:
the fix touches the settings panel and all six page files, the private bootstrap has an
`ADDON_LOADED == "Blizzard_Settings"` arm whose library equivalent has to be confirmed rather than
assumed, and shipping it beside a user-visible bug fix would make any regression expensive to
attribute. It is a maintainability finding with no user impact, which is what makes deferring it
legitimate.

---

## Changes by theme

### Theme A — One color shape, one unpacker

**What changed.** The cast bar now reads its spell-name color through the same shape-agnostic
unpacker every other color in the addon already used. The two module-level fallback tables were
converted to the stored keyed shape so nothing in the file carries the retired positional form.

**Why it mattered.** Since the v3→v4 migration the addon stores colors as `{ r =, g =, b =, a = }`.
One four-line helper still read `c[1] … c[4]`, which a keyed table does not have — so it returned
four ones and the name text painted white regardless of what the user chose. Every other color path
went through `NS.Util.Unpack`, which handles both shapes; this was the single site that did not, and
no test covered it. Deleting the second unpacker rather than teaching it the new shape is what stops
the divergence recurring.

**Finding IDs:** F-001 · **Change IDs:** C-001, C-002
**Files touched:**
- `modules/Castbar.lua`
- `tests/test_castbar.lua` *(or `tests/test_castbar_skin.lua`)*
- `docs/test-cases.md`, `README.md`

### Theme B — Make the silent skips loud

**What changed.** The two vendored-payload cases now say in their own names when they skipped
because the sibling `LibKa0s` checkout was absent, and an opt-in environment flag makes a missing
sibling a hard failure for CI.

**Why it mattered.** Both cases returned before asserting anything when the sibling repo was not on
disk — and still printed `PASS` and still counted toward the total. On any fresh clone or CI box,
the collection's one defense against a drifted vendored library reported success without looking.
The file's own comment claimed the skip "is said in the case name"; it was not.

**Finding IDs:** F-002 · **Change IDs:** C-003
**Files touched:**
- `tests/test_vendor_sync.lua`
- `docs/test-cases.md`

### Theme C — Instrumentation that measures what it claims

**What changed.** The `cdText` and `castTick` brackets now close on their early-return paths, so
both buckets report a true call count. The test that pinned this rule for one function was
generalized to a source guard over every bracketed function. `Helpers.ResetAll` stopped re-running
the work the library's `afterRestoreAll` hook already performs. The dropdown gate-hint probe now
restores the setting it temporarily mutates even when the probe raises.

**Why it mattered.** A bracket opened above an early return under-counts `calls`, which is the
denominator of the per-call average every capture is read by — and the repo already documented that
exact rule twice while leaving two sites unfixed. The reset path fired `CONFIG_CHANGED` twice each
for `general`, `castbar` and `units`, driving a duplicate full cooldown rebuild. And the gate-hint
probe wrote directly into the live profile with no `pcall`: an error inside a row's `values()`
function would have left a user's cast-bar orientation permanently changed, persisted to
SavedVariables, with no config-changed message telling any module about it.

**Finding IDs:** F-004, F-005, F-006 · **Change IDs:** C-004, C-005, C-006, C-007
**Files touched:**
- `modules/IconGrid_Render.lua`, `modules/Castbar.lua`
- `settings/Panel_Render.lua`, `settings/Slash.lua`
- `tests/test_perfsetup.lua`, `tests/test_color_shape.lua`
- `docs/test-cases.md`, `README.md`

### Theme D — The perf evidence base

**What changed.** The addon gained an offline scenario runner and a committed in-client capture, and
the write-up that interprets it. The bucket-design comments that cite specific millisecond figures
now name the record those figures came from.

**Why it mattered.** The two most consequential instrumentation decisions in the addon — declaring
the `pollSpell` bucket, and *removing* `visibility`'s declared nesting — were argued from precise
capture numbers that existed nowhere in the repo. A maintainer could neither check the reasoning nor
notice when it stopped being true. Separately, with no offline runner, the standard's "a dormant
bracket is free" claim was unverified for this addon: the existing suite proves a dormant bracket
*records* nothing, which is weaker than *allocates* nothing.

**Finding IDs:** F-007 · **Change IDs:** C-008
**Files touched:**
- `tests/perf.lua` *(new)*
- `docs/performance.md` *(new)*, `docs/perf-runs/README.md`, `docs/perf-runs/<date>-client-<label>.json` *(new)*
- `core/PerfSetup.lua` *(citation lines only)*

### Theme E — Consume the kit that is already vendored

**What changed.** The harness now loads the vendored test kit instead of carrying three
hand-maintained copies of it.

**Why it mattered.** `tests/_kit/` was pinned byte-for-byte against its upstream tag by a gate in
this repo — and loaded by nothing. `tests/run.lua` carried its own assertion framework and `--list`
renderer, `tests/loader.lua` its own sandbox, and `tests/wow_mock.lua` described itself as a
"verbatim port" of the kit's mock builder. Beyond the duplication, the local runner executes each
case body at registration time, which is precisely the shape the kit's header names as making
`--list` a second code path that can disagree with the run.

**Finding IDs:** F-008 · **Change IDs:** C-009
**Files touched:**
- `tests/run.lua`, `tests/loader.lua`, `tests/wow_mock.lua`

*(Nothing under `tests/_kit/` was edited. It is a vendored copy; a local edit is reverted by the
next re-vendor.)*

### Theme F — Comment and surface hygiene

**What changed.** A comment claiming `PollSpell` has four exits was corrected to two; a source
citation pointing at a line that does not exist in a file it misnames was fixed; an unread
`NS.Castbar` export was removed; and a lint allowlist entry for an API removed in 10.0 that the
addon never calls was dropped.

**Why it mattered.** Each is the sentence or the allowance a future maintainer would trust. The
exit-count comment in particular is what a reader consults before deciding whether a new branch
needs its own bracket.

**Finding IDs:** F-009, F-010, F-011, F-012 · **Change IDs:** C-010
**Files touched:**
- `core/PerfSetup.lua`, `settings/Slash.lua`, `modules/Castbar.lua`, `.luacheckrc`,
  `tests/test_coresetup.lua`

---

## API / behavior changes

| Change | Detail |
|---|---|
| **Cast bar spell-name color now applies** | Users who previously set this option and saw no effect will see their color take effect on first login after the update. This is a **visible change in appearance** for anyone whose stored value is not white. Worth a changelog line so it does not read as a new bug |
| Slash subcommands | **None added, renamed or removed** |
| Saved-variable schema | **No change.** `CURRENT_DB_VERSION` is unmoved; no migration step was added |
| Defaults | **None added or removed.** The two cast-bar fallback tables changed *in-memory shape only* (positional → keyed); they are code constants, never persisted |
| Locale keys | **None added, renamed or removed** |
| Deprecated APIs | **None replaced** — see below |
| Lint config | `InterfaceOptionsFrame_OpenToCategory` removed from `read_globals`; no call site existed |
| New SavedVariables | **None.** `KickCDPerfDB` already existed (`KickCD.toc:7`) |

---

## Saved-variable / migration notes

**No schema bump and no migration.** Existing profiles are read and written exactly as before.

One clarification worth recording, because it is easy to misread as a migration: the v3→v4 color
migration (`core/Database.lua:677-704`) was **already correct** and had already converted every
stored color to the keyed shape. The bug was entirely on the read side — one helper that had not
been updated to match. Nothing in a user's saved data was wrong, and nothing needed to be repaired.
No user needs to run `/kcd resetall`, and no profile requires manual intervention.

---

## Deprecated-API migrations

**None.** The review found no deprecated or removed API in live use. The bare globals that appear in
`core/Compat.lua` (`GetSpellInfo` at `:164`, `GetSpecialization` at `:253`,
`GetSpecializationInfo` at `:263`) are all guarded fallbacks sitting behind a modern-first branch
(`C_Spell.*`, `C_SpecializationInfo.*`) inside the compat layer, which is the intended pattern.
Panel registration already uses `Settings.RegisterCanvasLayoutCategory` +
`Settings.RegisterAddOnCategory`, and `NS:OpenSettings` already passes a category ID to
`Settings.OpenToCategory` (`core/KickCD.lua:757`).

---

## Performance impact

*Fill in from the committed record produced by T4.1 and the offline run from T4.2. Do not write an
estimate here — an interpretation without its record is an assertion, and this section is omitted
rather than guessed at if the numbers are not available.*

| Metric | Before | After | Source |
|---|---|---|---|
| `cdText` bucket — call count | under-counted (early exit unbracketed) | true count | `docs/perf-runs/<date>-client-<label>.json` |
| `castTick` bucket — call count | under-counted (early exit unbracketed) | true count | same record |
| `iconApply` — allocations per iteration, capture **off** | not measured (no runner) | | `tests/perf.lua` zero-overhead scenario |
| `/kcd resetall` — `CONFIG_CHANGED` dispatches | 2× general, 2× castbar, 2× units | 1× each | counted in the harness |

Two reading rules carried forward from `03_SMOKE_TESTS.md`: cite **bucket figures**, never the
frame-time delta between capture arms (it is unresolved below the harness's own run-to-run spread);
and never sum a parent bucket with its declared children.

---

## Test and complexity movement

| | Before | After |
|---|---|---|
| Harness pass count | **737 / 737** (measured 2026-08-05) | 737 + 4 expected (C-002 ×2, C-005 ×1, C-007 ×1, less any case C-005 subsumes) |
| `docs/test-cases.md` | in sync with the fresh `--list` | regenerated in the same commit as each count change |
| README `[Tests]` badge | `737/737 passing` | moved in the same commit, never deferred |
| `luacheck` | 0 warnings / 0 errors over 32 files | unchanged |
| `lizard` — functions over CCN 15 | **0** | **0** expected |
| `suites.perf` in the next run's `manifest.json` | `skip` — *"no tests/perf.lua"* | a real status, once C-008 lands |

**Complexity watch list:** nothing here is expected to move it. The fresh `lizard` run
(`lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .`) reported 15430 NLOC across 2051 functions,
average CCN 2.1, **zero** threshold warnings. C-001 removes a four-line function and C-006 removes
two statements; neither adds a branch. To be confirmed by the next release's regeneration under
`/wow-addon:bump-version` — **not** regenerated as part of this work, and never gated on per commit.

---

## Known follow-ups

| Item | Rationale for deferring |
|---|---|
| **F-003** — collapse the private options-page registration into `LibKa0s-Options-1.0`'s, or delete the four unused `NS.*` forwarders | Touches the settings panel and all six page files. The private bootstrap has an `ADDON_LOADED == "Blizzard_Settings"` arm whose library equivalent must be confirmed, not assumed. Scheduled as M7 behind its own architectural checkpoint |
| `NS.CreateOptionsPanel` / `NS.OpenOptionsPanel` are exercised **only** by tests | Symptom of F-003; resolving F-003 resolves it. Kept visible so the two suites that drive a production-unused path are not mistaken for coverage |
| `tests/run.lua`'s hand-maintained 48-entry `SUITES` list | Not currently a hazard — all 48 files on disk are listed, and `dofile` raises on a missing one, so neither silent-skip mode is live. The natural time to derive it is during the kit adoption (M5) |
| `tests/` excluded from `luacheck` (`.luacheckrc:4`) | A deliberate, documented choice; `docs/automated-tests/RESULTS.md` already names its cost (54 unlinted files). Left as-is rather than changed mid-review |
| `docs/performance.md` / `docs/perf-runs/` did not exist before this cycle | Their absence is a compliance matter owned by `wow-addon:standards-audit`. C-008 creates them because F-007 needs the evidence, not because the review is auditing structure |

---

## Verification evidence

- **In-client sign-off:** `docs/reviews/2026-08-05/03_SMOKE_TESTS.md`, sign-off table completed.
- **Headless evidence, re-measured at review time (2026-08-05):** `luacheck .` → 0/0 over 32 files;
  `lua5.1 tests/run.lua` → 737 passed, 0 failed; `lua5.1 tests/run.lua --list` diffs clean against
  `docs/test-cases.md`; `lizard` → 0 functions over CCN 15. All four reproduce the newest committed
  bundle `docs/automated-tests/20260804-233245/`.
- **Commit range / PR:** _fill in_.

---

## Suggested commit message / PR description

```
Fix the cast bar's spell-name color, and make the evidence around it honest

The cast bar's "Spell name color" setting never worked. Since the v3->v4 schema
migration every stored color is the keyed { r, g, b, a } table, but one helper in
modules/Castbar.lua still read the retired positional layout and so returned four
ones on every call — the name text painted white regardless of what the user had
chosen, in both the interruptible and uninterruptible states, on fresh and
migrated profiles alike. Every other color in the addon already went through the
shape-agnostic NS.Util.Unpack; this was the one site that did not, and nothing in
the 737-case suite covered it. The second unpacker is deleted rather than taught
the new shape, so the divergence cannot recur.

Four defects in the machinery that should have caught it are fixed alongside:

  * Two perf brackets (cdText, castTick) opened above an early return and never
    closed on it, under-counting the call count every capture's per-call average
    divides by. The rule was documented twice in this repo and pinned for exactly
    one function; the case is now a source guard over every bracketed function.
  * tests/test_vendor_sync.lua returned before asserting anything when the sibling
    LibKa0s checkout was absent — and still printed PASS. On any fresh clone the
    collection's defense against a drifted vendored payload reported success
    without looking. The skip is now named in the case, with an opt-in strict mode
    for CI.
  * Helpers.ResetAll re-ran the work LibKa0s-Options-1.0's afterRestoreAll hook had
    already done, firing CONFIG_CHANGED twice each for general/castbar/units and
    driving a duplicate full cooldown rebuild on every reset.
  * The dropdown gate-hint probe mutated the live profile and restored it without a
    pcall, so an error inside a row's values() function would have left a user's
    cast-bar orientation permanently changed and persisted.

The bucket design's cited capture figures now have a committed record under
docs/perf-runs/ behind them, and tests/perf.lua adds the zero-overhead scenario
that makes "a dormant bracket is free" a measured claim rather than an asserted
one. The harness now loads the vendored test kit instead of carrying three
hand-maintained copies of it.

No schema bump, no migration, no saved data touched. The one visible change is
that a spell-name color a user set some time ago will now actually appear.

Findings: F-001, F-002, F-004, F-005, F-006, F-007, F-008, F-009, F-010, F-011, F-012
Deferred: F-003 (private options-page registration alongside the library's) — M7
Review:   docs/reviews/2026-08-05/
```
