# KickCD — Code Review Findings

**Date:** 2026-08-05
**Reviewer:** principal-engineer review (`/wow-addon:review`)
**Addon version:** 1.2.1 (`KickCD.toc:5`)
**Standard resolved:** Ka0s WoW Addon Standard **v2.21.0, 2026-08-04**
(`standards/STANDARDS.md:1`). The index and its Sections list were fetched from
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master`; the section files were
read from the local read-only checkout of that same repo after two section fetches completed and
the rest timed out. The local copy was verified byte-identical to the remote for the one section
fetched both ways (`architecture.md`), and the local repo is at a clean `master`. The standards
cross-check below is therefore **not** skipped.

---

## Verdict

**Minor issues — not ship-blocking, but one user-visible functional bug and one asleep test.**
The addon is in unusually good shape: lint is clean, 737/737 cases pass, zero functions exceed
CCN 15, and every committed artifact agrees with a fresh run. The findings below are real defects,
not compliance gaps.

---

## Measurement run (Step 0 — all re-run from scratch today)

| Suite | Command (from repo root) | Result |
|---|---|---|
| **luacheck** | `luacheck .` | **PASS** — 0 warnings / 0 errors in 32 files, exit 0 |
| **Headless tests** | `lua5.1 tests/run.lua` | **PASS** — **737 passed, 0 failed**, exit 0 |
| **Test-case inventory** | `lua5.1 tests/run.lua --list` → scratch | **PASS** — 938 lines, 737 cases |
| **Offline perf runner** | `lua5.1 tests/perf.lua` | **SKIPPED** — `tests/perf.lua` does not exist in this repo |
| **Complexity** | `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` | **PASS** — 15430 NLOC, 2051 functions, avg CCN 2.1, **0 warnings; no function with CCN > 15** |
| **Makefile target** | `make test` | **SKIPPED** — no root `Makefile` |
| **Vendor sync** | `diff -r libs/LibKa0s/ ../LibKa0s/LibKa0s/` | **SKIPPED** — this review is constrained to the KickCD repo; the sibling `LibKa0s` checkout was not read. See F-002: the in-repo gate that *would* answer this passes vacuously under the same condition |

Tool versions observed: `lua5.1` 5.1.5, `luacheck` 1.2.0, `lizard` 1.23.0.

**Functions with CCN > 15:** none. The four files lizard lists under its per-file band summary are
`modules/IconGrid_Layout.lua` (avg CCN 12.0 over 4 functions), `settings/Castbar.lua`,
`settings/Icons.lua` and `settings/Label.lua` — all reported by average, none by threshold.

### Committed artifacts vs. today's run

| Artifact | Agreement |
|---|---|
| `docs/test-cases.md` | **In sync.** `diff` of the fresh `--list` against the committed file (CR-normalized) is empty |
| README `[Tests]` badge (`README.md:7`) | **In sync** — `737/737 passing` |
| `docs/automated-tests/RESULTS.md` newest row (`20260804-233245`) | **In sync** — lint 0/0 over 32 files, tests 737/737, NLOC 15430, funcs 2051, avg CCN 2.1, CCN warn 0. Its `perf: skip` with reason *"no tests/perf.lua — this addon ships no offline scenarios"* matches what I observed |
| `docs/automated-tests/20260804-233245/manifest.json` | Run stamp `2026-08-04T23:32:45+05:30`, git `5eca940…`, `dirty: true`. Dated but **not stale**: every number it carries reproduces today |
| `docs/performance.md`, `docs/perf-runs/` | **Do not exist.** Their absence is a compliance matter for `wow-addon:standards-audit`, not a review finding — but it is *load-bearing evidence* for F-007 |

**Nothing in this review's perf reasoning is backed by a measured number**, because there is no
offline runner and no committed capture in this repo. Every perf claim below is marked
**unverified** where it could have been measured and was not.

---

## Upstream findings

**None.** No defect was found in `libs/` or `tests/_kit/`. F-003 and F-009 touch code that *consumes*
`libs/LibKa0s/`, and both fixes land in this repo's own files.

---

## High

### F-001 — Cast-bar spell-name color is silently ignored; the bar always paints it white `[bug]`

- **Where:** `modules/Castbar.lua:726-729` (`rgba`), read at `modules/Castbar.lua:740`,
  `modules/Castbar.lua:747-748`.
- **Problem:** `rgba(c)` returns `c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1` — the **positional**
  color shape only. Since the v3→v4 migration (`core/Database.lua:677-704`) every stored color is the
  **keyed** `{ r =, g =, b =, a = }` table, which is also the schema default for both rows
  (`settings/Castbar.lua:419-423` and `:481`) and the DB default (`core/Database.lua:203`, `:213`).
  A keyed table has no `[1]`, so `rgba` returns `1, 1, 1, 1` on every call.
- **Impact:** the Castbar → Interruptible/Uninterruptible → **"Spell name color"** setting has no
  effect on any profile, fresh or migrated. The spell name renders white always, in both preview
  (`applyPreviewVisuals`, `modules/Castbar.lua:733-741`) and live
  (`applyLiveVisuals`, `:746-773`) paths.
- **Why it survived:** every *other* color in the same file goes through
  `unpackColor` (`modules/Castbar.lua:228-231`), which delegates to `NS.Util.Unpack`
  (`core/Util.lua:22-28`) — and that one is shape-agnostic. `rgba` is the single site in the addon
  that reads a profile color positionally (verified by grep across `core/`, `modules/`, `settings/`;
  the only other `[1] or`-shaped reads are the spell-list category tuple at `core/KickCD.lua:639`
  and `settings/Spells.lua:492`, and the migration itself).
- **Coverage:** **the suite claims no case over this path.** `nameTextColor` and `rgba` appear in
  **zero** files under `tests/`. This is a coverage gap, not an asleep test.
- **Measurement:** not applicable — proven by reading, confirmed against the stored shape.
- **Fix direction:** delete `rgba` and route both call sites through the existing
  `Castbar.UnpackColor` / `NS.Util.Unpack`, and move `INT_FALLBACK` / `UNINT_FALLBACK`'s color
  literals (`modules/Castbar.lua:571-576`, `:581-586`) to the keyed shape so the fallback and the
  stored shape stop disagreeing. Do **not** add a second positional↔keyed translation layer —
  `settings/Slash.lua:35-39` records that the migration was deliberately chosen over one, and
  re-introducing it would re-open the drift `savedvariables`/`options-ui-§1` closed.

### F-002 — The vendored-payload gate passes vacuously, and its own comment says otherwise `[tests]`

- **Where:** `tests/test_vendor_sync.lua:110-116` (`siblingTag`), consumed at `:138-142` and
  `:144-149`.
- **Problem:** `siblingTag()` returns `nil` when the sibling `../LibKa0s` checkout is absent, and
  both cases then `return` **before asserting anything** — while still printing `PASS` and still
  counting toward 737. The case names are unconditional positive claims:
  *"libs/LibKa0s **is** the LibKa0s release the README says this addon bundles"*.
- **Impact:** on any machine without the sibling repo — CI, a fresh clone, a contributor's box —
  the collection's one defense against a drifted vendored payload reports success without looking.
  This is exactly the `testing-§12` shape: green that reads as coverage and provides none.
- **The comment is wrong about itself.** `tests/test_vendor_sync.lua:107-109` states *"A missing
  sibling is the ONE case where this pair may go quiet, and it is said in the case name rather than
  hidden."* It is not said in either case name.
- **Measurement:** these two cases were among the 737 that passed today. I could not determine
  whether they ran non-vacuously, because this review is scoped to the KickCD repo and may not read
  the sibling checkout — **which is precisely the reader's problem too**, and is why the skip has to
  be visible in the output.
- **Fix direction:** make the skip legible — either name the condition in the case name
  (`"… (skipped: no sibling LibKa0s checkout)"`) or fail closed when an environment marker says the
  sibling is expected. Do **not** delete the cases and do **not** relax the byte-identity assertions;
  `testing-§8` and the vendor rule both depend on them.

---

## Medium

### F-003 — A private options-page registration system runs alongside the adopted library's `[design]`

- **Where:** `settings/Panel.lua:35-36`, `:546-555` (`NS.Settings.RegisterTab`), `:557-604`
  (`RegisterPanel`), `:607-617` (its own `PLAYER_LOGIN`/`ADDON_LOADED` bootstrap) — against
  `settings/OptionsSetup.lua:228-234` and `libs/LibKa0s/Options.lua:536`, `:576`, `:636`.
- **Problem:** the addon adopts `LibKa0s-Options-1.0` for the canvas shell, widget makers, flow
  engine and refresh fan-out (correctly), but keeps its **own** page-registration table
  (`NS.Settings.builders` / `.order` / `.sub`), its **own** `Settings.RegisterCanvasLayoutCategory`
  + `RegisterAddOnCategory` call (`settings/Panel.lua:589-590`) and its **own** deferral frame —
  duplicating `O.RegisterOptionsPage` / `O.CreateOptionsPanel` / `O.OpenOptionsPanel`. All six page
  files register through the private path (`settings/{General,Icons,Castbar,Label,Spells,Profiles}.lua`,
  each at its file tail).
- **Consequence, and this is the measurable half:** `NS.RegisterOptionsPage`
  (`settings/OptionsSetup.lua:228`) and `NS.RefreshOptionsPanel` (`:234`) have **zero callers
  anywhere** in `core/`, `modules/`, `settings/` **or** `tests/` — verified by grep.
  `NS.CreateOptionsPanel` (`:229`) and `NS.OpenOptionsPanel` (`:230`) have **test-only** callers
  (`tests/test_coresetup.lua:354`, `tests/test_options_panel.lua:342`), so two suites exercise a
  path production never takes.
- **Impact:** two registration mechanisms to keep correct, a dead public surface on the namespace,
  and two suites whose green says nothing about the code users run.
- **Fix direction:** pick one. The compliant direction is to adopt the library's page registration
  (`options-ui-§1`: the instance is decorated in place, not shadowed) and delete the private
  `RegisterTab`/`RegisterPanel`/bootstrap; if the private path must stay for a reason worth writing
  down, then delete the four unused `NS.*` forwarders and say in `settings/OptionsSetup.lua` why the
  library's registration is deliberately not wired. Do **not** re-implement anything the library
  already provides in order to close this.

### F-004 — `Helpers.ResetAll` re-runs work the library's `afterRestoreAll` hook already did `[design]`

- **Where:** `settings/Panel_Render.lua:259-266` against `settings/OptionsSetup.lua:93-97`, driven by
  `libs/LibKa0s/Options.lua:394-407`.
- **Problem:** `Helpers.ResetAll()` calls `RestoreAllDefaults()`, then calls `ResetAllPositions()`
  and `RestoreUnitLinks()` explicitly. But the library's `RestoreAllDefaults` already invokes
  `d.afterRestoreAll()` (`libs/LibKa0s/Options.lua:403`), and this addon's `afterRestoreAll`
  descriptor field *is* `ResetAllPositions` + `RestoreUnitLinks`
  (`settings/OptionsSetup.lua:93-97`). Both run twice per reset.
- **Impact:** `/kcd resetall` and the General page's "Reset all settings" popup fire
  `Ka0s_KickCD_CONFIG_CHANGED` **twice** for `general` (`settings/Panel_Render.lua:199`, `:226`),
  twice for `castbar` (`:227`) and twice for `units` (`:251`). Each `general` fire drives a full
  `Cooldowns:Rebuild` (`modules/Cooldowns.lua:520-528`) and a re-anchor pass across every enabled
  unit. Not a correctness bug — the second pass is idempotent — but it is duplicated work on a path
  the user watches, and it means the hook and the caller each believe they own the same step.
- **Measurement:** cost **unverified** — there is no offline scenario for the reset path and no
  committed capture (see F-007).
- **Fix direction:** let the hook own it. Drop the two explicit calls from `Helpers.ResetAll` and
  leave `ResetAllSpells` (which no schema row and no hook covers) as the only thing it adds beyond
  `RestoreAllDefaults`.

### F-005 — Two perf brackets are not closed on their early-return exit `[perf]`

- **Where:** `modules/IconGrid_Render.lua:827` opens the `cdText` bracket; the early return at
  `:831-837` leaves without a `Perf.Note`, which only happens at `:843`.
  Same shape in `modules/Castbar.lua:690` (`castTick` opened) with the early return at `:694-697`,
  closed only at `:716`.
- **Problem:** an exit that skips the bracket under-counts that bucket's `calls`, which is the
  denominator of the per-call average every report is read by.
- **Why this one matters more than it looks:** the repo already knows the rule and states it twice —
  `core/PerfSetup.lua:105-113` and `modules/Cooldowns.lua:179-189` both explain that a single
  fall-through bracket under-counts, and `tests/test_perfsetup.lua:551-589` pins it. But that case
  is written **against `PollSpell` specifically** ("every PollSpell exit is measured"); there is no
  generic every-exit case, so the two sites above are uncovered. The paired case at
  `tests/test_perfsetup.lua:126-155` cross-checks *which keys* are declared vs. bracketed, not
  whether every exit closes.
- **Impact:** `cdText` and `castTick` report an inflated mean and an undercounted call count in every
  capture. Both missed exits are the cheap ones, so the *total* is roughly right and the *average* is
  biased high.
- **Measurement:** magnitude **unverified** — no runner, no capture.
- **Fix direction:** close both brackets on the early-return path (the `Cooldowns:PollSpell` shape at
  `modules/Cooldowns.lua:190-202` is the in-repo pattern to copy), and widen
  `tests/test_perfsetup.lua`'s exit case from PollSpell-specific to every bracketed function.

### F-006 — `GateHint` writes the live profile directly and restores without a `pcall` `[design]`

- **Where:** `settings/Slash.lua:118-129`, reached from `parseForHost` at `:141-148`.
- **Problem:** the hint probe does `parent[key] = candidate`, calls `allowedKeys(row)` — which
  invokes the row's own `values()` function (`:83-89`) — and only then restores
  `parent[key] = gateVal`. Two things: (a) the write bypasses `Helpers.SetAndRefresh`, the addon's
  documented single write seam (`settings/Slash.lua:302-309`, `settings/Panel_Render.lua:152-165`);
  (b) there is no `pcall` around the probe, so **an error thrown inside `values()` leaves the gating
  setting permanently changed** in the live profile and therefore in SavedVariables.
- **Impact:** a user who typos a cast-bar `growDirection` value could silently have their
  `castbar.orientation` flipped and persisted, with no CONFIG_CHANGED fired to tell any module about
  it. `values()` for media-backed rows reaches LibSharedMedia through another addon's data
  (`settings/Slash.lua:81-82` says so explicitly), which is exactly the kind of call that can raise.
- **Coverage:** `tests/test_color_shape.lua:311-318` exercises `GateHint`'s happy path with a
  `-- red under:` note; nothing exercises a raising `values()`.
- **Fix direction:** wrap the mutate/probe in `pcall` and restore in all paths (a `finally`-shaped
  local), keeping the raw write — a transient probe genuinely should not fire the notify path — and
  document *that* as the reason the write seam is bypassed here.

### F-007 — The bucket design is justified by capture figures that exist nowhere in the repo `[perf]`

- **Where:** `core/PerfSetup.lua:105-113` and `:114-120`; echoed verbatim at
  `modules/Cooldowns.lua:180-189`.
- **Problem:** the decision to declare `pollSpell` and to *undeclare* `visibility`'s nesting is
  argued from specific numbers — *"spellPoll totaled 125.02 ms of which its only declared child
  accounted for 51.14, leaving 73.9 ms"* and *"the same capture recorded six `visibility` calls
  against ZERO for `castEvent`"*. There is no `docs/perf-runs/`, no `docs/performance.md` and no
  `tests/perf.lua` in this repo, so **the record behind those figures cannot be opened**. A future
  maintainer cannot check the reasoning, re-derive it, or notice when it stops being true.
- **Second half:** with no offline runner, `performance-§2`'s *"a dormant bracket is free"* claim is
  **unverified for this addon**. `tests/test_perfsetup.lua:182-194` proves a dormant bracket records
  nothing, which is a different and weaker statement than *allocates nothing* — it counts `calls`,
  not allocations.
- **Impact:** the addon's most consequential perf decisions rest on assertions rather than records.
- **Measurement:** this finding *is* the measurement result — the runner is absent, so the claim is
  unverified rather than false.
- **Fix direction:** commit the capture the comments already describe under `docs/perf-runs/` as
  append-only evidence and cite the filename from `core/PerfSetup.lua`, and add the zero-overhead
  scenario `performance-§9` describes. Do **not** delete the numbers from the comments — an
  unsourced number is still a lead; make it sourceable.

### F-008 — The vendored test kit is pinned byte-for-byte and loaded by nothing `[tests]`

- **Where:** `tests/_kit/framework.lua`, `tests/_kit/loader.lua`, `tests/_kit/mock_base.lua` against
  `tests/run.lua:19-90` (a private micro-framework), `tests/loader.lua:1-108` (a private loader) and
  `tests/wow_mock.lua:573`.
- **Problem:** `tests/run.lua` defines its own `test`, `assertTrue`, `assertFalse`, `assertNil`,
  `assertEqual`, `assertError`, `assertNear` and its own `--list` renderer; `tests/loader.lua`
  defines its own sandbox + TOC reader; `tests/wow_mock.lua:573` describes itself as *"a VERBATIM
  port of `tests/_kit/mock_base.lua`'s builder"*. Nothing in `tests/` ever loads a file from
  `tests/_kit/` — verified by grep: the only references are comments and the sync gate itself.
  Meanwhile `tests/test_vendor_sync.lua:144-149` gates the unused folder for byte-identity against
  the upstream tag.
- **Impact:** three hand-maintained copies of code the collection extracted precisely to stop
  copying, kept green by a gate on a payload nothing consumes. `tests/run.lua:75-77` is candid about
  it — *"so adopting the kit replaces this with an identical function"* — which makes this a stated
  intention that has not landed, not an oversight.
- **A concrete behavioral difference, not just duplication:** the kit is **collect-then-run** by
  design and says why (`tests/_kit/framework.lua:2-7`: a runner that executes at registration makes
  `--list` a second code path that can disagree with the run). `tests/run.lua:41-58` executes each
  case body inside `test()` at registration and early-returns in list mode — the exact shape the kit
  header names. It happens not to bite today (`docs/test-cases.md` diffs clean), but the guarantee
  the kit buys is not in force here.
- **Secondary note (same file):** `tests/run.lua:139-187` hand-maintains the 48-entry `SUITES` list.
  All 48 `tests/test_*.lua` on disk are present and `dofile` raises on a missing one, so neither
  silent-skip failure mode of `testing-§9` is live — but the list is still hand-maintained, and the
  *addon* file list beside it is correctly TOC-derived (`tests/loader.lua:41-55`), so the asymmetry
  is worth closing when the kit is adopted.
- **Fix direction:** adopt the kit — `tests/run.lua` and `tests/loader.lua` become thin consumers of
  `tests/_kit/framework.lua` and `tests/_kit/loader.lua`, and `tests/wow_mock.lua` builds on
  `mock_base.lua` instead of porting it. Do **not** edit anything under `tests/_kit/`, and do not
  delete the sync gate.

---

## Low

### F-009 — `core/PerfSetup.lua` claims `PollSpell` has four exits; it has two `[naming]`

`core/PerfSetup.lua:108` reads *"All four of PollSpell's exits are instrumented now"*, while
`modules/Cooldowns.lua:179` opens with *"TWO exits, and both are instrumented on purpose"* over a
function with exactly two `return`s (`:194`, `:202`). The count was correct before a refactor and was
not carried. Cosmetic, but it is the sentence a future reader uses to decide whether a third exit
needs a bracket.

### F-010 — A source citation that cannot resolve, repeated in a test `[naming]`

`settings/Slash.lua:211` cites *"AbsorbTracker inverts it the same way for the same reason
(settings/Slash.lua:383)"* — but this file is 348 lines, and the path names *this* repo's file
rather than AbsorbTracker's. `tests/test_coresetup.lua:360` repeats the same dangling reference.
Cross-repo citations should name the repo, or carry no line number at all.

### F-011 — `NS.Castbar` is published with no readers `[dead-code]`

`modules/Castbar.lua:1312` sets `NS.Castbar = Castbar`. Grep across `core/`, `modules/`, `settings/`
and `tests/` finds no other reference. Every consumer reaches the module through
`NS:GetModule("Castbar")` (e.g. `core/KickCD.lua:199`, `modules/Castbar_Debug.lua:10`). The
test-hook block immediately above it (`:1296-1305`) is *not* dead — those fields have suite callers —
but this line is.

### F-012 — `.luacheckrc` allowlists an API removed in 10.0 that the addon never calls `[lint]`

`.luacheckrc:29` lists `InterfaceOptionsFrame_OpenToCategory` in `read_globals`. Grep finds no call
site in `core/`, `modules/` or `settings/`. The addon correctly uses `Settings.OpenToCategory`
(`core/KickCD.lua:757`). A stale allowance for a removed global is a small trap: it would wave the
removed call through if anyone reached for it. The rest of the allowlist is accurate —
`debugprofilestop` (`:18`) and `KickCDPerfDB` (`:47`) are both declared, so the bracket call sites
and the second SavedVariables global lint clean, which is the case the standard cares about.

---

## Notes on things checked and found clean

Recorded so a later reader does not re-derive them: no raw `print(` bypasses `NS.Util.print` (the
~30 `print(...)` calls in `modules/Castbar_Debug.lua` are a **parameter** bound from
`NS.Util.print` at `:125`); every declared perf bucket is reached by a real bracket and every bracket
records into a declared bucket; `Perf.on` is read through a load-time upvalue in all four modules
(`modules/{Cooldowns:64,IconGrid:61,IconGrid_Render:18,Castbar:72}.lua`); all 263 distinct `L[...]`
keys resolve in `locales/enUS.lua`; every `/kcd` verb documented in `README.md` is in `COMMANDS` or
the `options → config` alias (`settings/Slash.lua:290`); events are registered in `OnEnable`, not
`OnInitialize`; per-unit cast events use `RegisterUnitEvent` (`core/Util.lua:410-411`) and are torn
down explicitly (`modules/IconGrid.lua:667`, `:690`); icons are pooled
(`modules/IconGrid.lua:243-283`) with `ClearAllPoints` before re-anchor; the deprecated bare globals
in `core/Compat.lua` (`:164`, `:253`, `:263`) are all guarded fallbacks behind a modern-first branch,
which is the `compat` section's own pattern; secret values are never bound to locals on the cast-bar
hot path (`modules/Castbar.lua:702-713`).
