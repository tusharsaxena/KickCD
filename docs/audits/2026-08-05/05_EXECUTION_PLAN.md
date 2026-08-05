# KickCD — Execution Plan (2026-08-05)

Ordered remediation for `02_DEVIATIONS.md`, designed in `04_TECHNICAL_DESIGN.md`. This is the hand-off
to a separate remediation engagement — **this audit changed no addon code.**

Every step ends green: `lua tests/run.lua` all passing and `luacheck .` at 0 errors (`testing-§4`).
Commit on green units of work only (`versioning-git`). Regenerate `docs/test-cases.md` and the
README `[tests]` badge **in the same change** as any step that moves the case count (`testing-§5`).

**Legend:** ☐ step · **ID(s)** the deviation(s) it closes · *(gate)* the check that proves it.

---

## Sprint 0 — Verify what this audit could not (half a day)

The one check that hides from both test suites. Do it first; if it fails, everything else re-plans.

- ☐ **0.1** Run `diff -r ../LibKa0s/LibKa0s ./libs/LibKa0s`. *(gate: empty)*
- ☐ **0.2** Run `diff -r ../LibKa0s/testkit ./tests/_kit`. *(gate: empty)*
- ☐ **0.3** If either is non-empty: **stop and file a new deviation** (`KCD-50`, `AP #45` for drift /
  `AP #48` for a file missing on the addon side) before any other work. Re-vendor whole-folder from
  the library repo's ship folder — never a hand-patch under `libs/` — and land it as its own commit
  so the sync is legible in history.
  *(gate: both diffs empty; `lua tests/run.lua` green)*

**Exit:** vendor sync is *verified*, not assumed. `03_EVIDENCE.md` §1.5 records it as unverified
today; nothing downstream is trustworthy until this is answered.

---

## Sprint 1 — The user-visible bug (half a day)

Smallest change, largest user impact. Ships independently of everything else.

- ☐ **1.1** Write the characterization case in `tests/test_color_shape.lua`: drive
  `applyLiveVisuals`/`applyPreviewVisuals` with a **keyed** `nameTextColor` and assert the four values
  reaching `SetTextColor`. **Run it against the current code and watch it go red** (it will report
  `1,1,1,1`). — **KCD-42** *(gate: the case is red before the fix)*
- ☐ **1.2** Add the companion case for a **positional** color table, so the fix is not a swap of one
  shape for the other. — **KCD-42**
- ☐ **1.3** Replace `modules/Castbar.lua:726-729`'s `rgba` body with `NS.Util.Unpack(c or WHITE)`.
  — **KCD-42** *(gate: both cases green; full suite green; lint clean)*
- ☐ **1.4** Regenerate `docs/test-cases.md`; update the README `[tests]` badge in the same commit.
  *(gate: `diff <(lua tests/run.lua --list) docs/test-cases.md` empty)*
- ☐ **1.5** Add a `## What's new` bullet for the next release: the cast bar's Spell name color now
  applies. *(gate: `documentation-§1` item 5)*

**Exit:** `KCD-42` closed. The Spell name color setting works.

---

## Sprint 2 — Documentation and prose (half a day)

Cheap, independent, and two of them are the surfaces that go stale silently.

- ☐ **2.1** `README.md:191` → `` `/kcd reset setting` ``. Leave the `<br>` tags at `:210-211` alone.
  — **KCD-37**
- ☐ **2.2** `docs/superpowers/plans/2026-08-04-ccn-elimination.md`: `colour(s)` → `color(s)`,
  `behaviour` → `behavior` (`:51`, `:53`, `:57`, `:121`, `:149`). **Do not touch**
  `docs/automated-tests/20260804-182144/ANALYSIS.md:72` — frozen evidence. — **KCD-47**
- ☐ **2.3** `docs/testing.md`: split the suite table's `Gates?` column into `Commit?` / `Release?`,
  and add the release gate beside the commit gate — all four at `pass` plus
  `suites.complexity.warnings == 0` at the tag, evaluated by `/wow-addon:bump-version` from the
  manifest, never by the runner's exit code; a `skip` blocks as NOT EVALUATED. — **KCD-44**
- ☐ **2.4** `CLAUDE.md:75`: qualify "never a gate" as "never a **commit** gate", and name the release
  gate. — **KCD-44**
- ☐ **2.5** `docs/automated-tests/README.md`: the same two-checkpoint statement. — **KCD-44**
- ☐ **2.6** Sweep the two stale `modules/DebugLog.lua` references at `core/Constants.lua:91` and
  `core/CoreSetup.lua:20`. — **A-9**
- ☐ **2.7** Add the angle-bracket and British-spelling sweeps to the pre-release doc pass
  (`documentation-§5`), so the next straggler is caught by process.
  *(gate: lint clean; suite green; no doc-only change should move either)*

**Exit:** `KCD-37`, `KCD-47`, `KCD-44` (doc half) closed. `A-9` cleared.

---

## Sprint 3 — The output seams (1 day)

Three independent files; one review.

- ☐ **3.1** `core/Compat.lua`: delete `safeRender` (`:373-386`); route through `NS.SafeToString`;
  keep `%q` quoting by wrapping the shared result; drop the `_G.print` fallback at `:446`; keep the
  `issecretvalue` **reporting** column at `:387`. — **KCD-33**
  *(gate: `tests/test_compat.lua`, `test_compat_api.lua`, `test_compat_debug.lua` green)*
- ☐ **3.2** `core/DebugLogSetup.lua`: delete `FormatPlain` (`:94-96`) and `FormatColored` (`:114`);
  rewrite the `:58-62` comment to record what was removed and why; move any suite assertion onto the
  library path. — **KCD-45** *(gate: `tests/test_debuglogsetup.lua` green)*
- ☐ **3.3** *(defer until after Sprint 4 if the mock work has started)* `modules/Castbar_Debug.lua`:
  drop `or _G.print` at `:125`; pass varargs instead of pre-concatenated strings at all 20 call
  sites; route the dump through `NS.DebugLog:Add("Cast", …)` and reveal the console once at the top
  (`core/PerfSetup.lua:169-170`, `:182-183` are the in-repo patterns). — **KCD-46**
  *(gate: `tests/test_castbar_debug.lua` green; `/kcd debug castbar` smoke-checked in client)*

**Exit:** `KCD-33`, `KCD-45`, `KCD-46` closed. Every chat and debug line in the addon goes through
one secret-safe seam.

---

## Sprint 4 — The test harness (2–3 days)

Highest churn. Three substitutions, one commit each, full suite after each.

- ☐ **4.1** **Framework.** `dofile` the kit's `framework.lua`; `Kit.expose(_G.KICKCD_TEST)`;
  `Kit.run{ dir = "tests/", suites = {...} }`; delete `tests/run.lua:17-82`. No suite file changes.
  — **KCD-30** *(gate: 737 cases still reported, still green; `--list` output unchanged)*
- ☐ **4.2** **Loader.** Delete `tests/loader.lua`; use the kit's; derive the addon's own file list
  with `Loader.tocFiles("KickCD.toc")`; keep the explicit `LibKa0s.xml` file list in the runner and
  the `{ libFiles = {} }` degraded-path option. — **KCD-30**, **KCD-30/`testing-§9`**
- ☐ **4.3** Add the three `testing-§9` pins: the runner fed the loader exactly the TOC's files in the
  TOC's order; every derived path exists on disk; no `libs/` path leaked in. — **KCD-30**
- ☐ **4.4** **Mock.** Rebuild `tests/wow_mock.lua` as `base()` plus per-key overwrites; delete the
  verbatim-port block at `:573+`; use `M.__stubFrame()` and `M.__libs`. — **KCD-30**
  *(gate: full suite green; `wc -l tests/wow_mock.lua` out of the 1000–1500 band, clearing its
  `RESULTS.md` watch-list row)*
- ☐ **4.5** **Vendor-sync gate.** Make the not-run state visible — raise per `testing-§11`, or
  register a distinct `"vendor sync SKIPPED — ../LibKa0s not checked out"` case. Fix the `:107-109`
  comment. — **KCD-43** *(gate: with `../LibKa0s` renamed away, the run does **not** print PASS for
  those two lines)*
- ☐ **4.6** Regenerate `docs/test-cases.md` and the README badge. *(gate: diff empty)*
- ☐ **4.7** Produce a run bundle (`tests/_kit/run-automated-tests.sh`) and let `RESULTS.md` record
  the case-count and NLOC movement; update the band table's dispositions.

**Exit:** `KCD-30` and `KCD-43` closed. `tests/_kit/` is consumed rather than merely vendored, and no
test in the repo passes without looking.

---

## Sprint 5 — The Options surface (2–3 days)

One changeset in `settings/Panel.lua`, in this internal order. **Sequence after Sprint 4** — the page
registration work is easier to characterize on the kit.

- ☐ **5.1** Pin the current subcategory **order** in a case (six names, in order), run it green.
  *(gate: the pin passes before anything moves)* — protects **KCD-40**
- ☐ **5.2** Move the six page tails onto `NS.RegisterOptionsPage(key, name, Build)`
  (`settings/General.lua:183`, `Icons.lua:417`, `Castbar.lua:560`, `Label.lua:193`,
  `Spells.lua:1158`, `Profiles.lua:66`). — **KCD-40**
- ☐ **5.3** Delete `NS.Settings.RegisterTab`, `RegisterPanel`, `NS.Settings.Register` and the private
  bootstrap (`settings/Panel.lua:546-616`); call `NS.CreateOptionsPanel()` once from the surviving
  login handler, with `Helpers.ValidateSchema()` ahead of it. Repoint
  `tests/test_settings_spells_editor.lua:30`. — **KCD-40**
- ☐ **5.4** Delegate `NS:OpenSettings` (`core/KickCD.lua:775-790`) to `NS.OpenOptionsPanel()`; keep
  only `expandMainCategory` and — if it is still needed once registration is eager — the bounded
  retry. Delete the host combat gate; the library gates inside its own open. — **KCD-40**
  *(gate: 5.1's order pin green; `tests/test_options_panel.lua` and `test_coresetup.lua` green;
  in-client: the panel opens from `/kcd config`, is refused in combat with the gray notice, and the
  six tabs appear in the same order as before)*
- ☐ **5.5** Delete the four host member copies (`settings/Panel.lua:276-291`, `:315-341`, `:355-394`,
  `:435-443`); rewrite the eight `LSMValues` call sites from
  `values = function() return H.LSMValues(m) end` to `values = H.LSMValues(m)`. — **KCD-31**
- ☐ **5.6** Determine whether the `"Default"` → `LSM_NONE` fallback-key change needs a migration step
  in `core/Database.lua`; add one if a stored `"Default"` would stop resolving. Record the answer in
  the change either way. — **KCD-31**
  *(gate: in-client — every font/texture/sound dropdown still populates and the stored selection is
  preserved across a `/reload`)*
- ☐ **5.7** Delete `local ROW_VSPACER = 8` and `Helpers.ROW_VSPACER =` (`settings/Panel.lua:426`,
  `:430`); the two existing instance-readers become the only readers. — **KCD-32**
- ☐ **5.8** Comment `core/Constants.lua`'s `PANEL_PADDING_X` as a **time-boxed** deviation naming
  `KCD-32` and the upstream change it waits on. — **KCD-32** (partial)
- ☐ **5.9** *(upstream, blocks the rest of `KCD-32`)* In the `LibKa0s` repo: publish
  `O.PADDING_X = L.PADDING_X`, bump `Options.lua`'s LibStub minor, add the changelog entry, tag,
  then **re-vendor whole-folder into every consumer** as its own commit. Return here and read
  `Helpers.PADDING_X`. — **KCD-32**

**Exit:** `KCD-40`, `KCD-31` closed; `KCD-32` closed except the upstream half, which is tracked in
the `LibKa0s` repo.

---

## Sprint 6 — The performance surface (2 days)

- ☐ **6.1** Close the two brackets: `modules/IconGrid_Render.lua:831-837` and
  `modules/Castbar.lua:694-697` gain the `Perf.Note` on the early-return arm. Correct
  `core/PerfSetup.lua:108` from "four" to "both". — **KCD-49** *(source half)*
- ☐ **6.2** Generalize `tests/test_perfsetup.lua:551-589` from `PollSpell` to every bracketed
  function, as a source-scan guard in the shape of `tests/test_slash_style.lua`. — **KCD-49**
  *(gate: the generalized case is red against the pre-6.1 source)*
- ☐ **6.3** Write `tests/perf.lua`: `Loader.tocFiles`-derived load list; the **zero-overhead
  scenario** over `iconApply` (capture off vs. `NS.Perf` absent, `collectgarbage("count")` deltas
  with a full collect either side); a bucket-reach scenario over
  `spellPoll → pollSpell → spellState → iconApply`. Deterministic assertions only — **never**
  wall-clock. Not referenced by `tests/run.lua`. — **KCD-34**
- ☐ **6.4** Pin `tests/perf.lua`'s derivation call by reading its source from a gated suite
  (`testing-§9`, ungated load lists). — **KCD-34**
  *(gate: `lua tests/perf.lua` runs and passes; `tests/_kit/run-automated-tests.sh` records
  `"perf": {"status":"pass"}` in the manifest)*
- ☐ **6.5** Write `docs/performance.md`, **moving** the rationale from `core/PerfSetup.lua:19-31` and
  `:96-122` rather than duplicating it, plus how to run `/kcd perf`, how to read the report, and what
  the harness cannot resolve. Resolve the unsourced 125.02/51.14/73.9 ms figures: either commit the
  capture (6.6) or mark them as an uncommitted historical reading. — **KCD-35**
- ☐ **6.6** Create `docs/perf-runs/README.md` (naming convention, schema summary, upstream pointer,
  the `automated-tests-§7` in-game/offline split) and commit the first in-game capture worth keeping.
  — **KCD-35**
- ☐ **6.7** Produce a run bundle and confirm the manifest now shows all four suites at `pass` with
  `complexity.warnings == 0` — i.e. the release gate would pass. — **KCD-44** (the dependency half)

**Exit:** `KCD-34`, `KCD-35`, `KCD-49` closed; `KCD-44` fully closed. The addon can be released
without invoking `automated-tests-§3`'s narrow perf exception.

---

## Sprint 7 — The defaults tree (1 day)

- ☐ **7.1** Create `defaults/Profile.lua` holding `DEFAULT_PROFILE` verbatim, published as `NS.C` /
  `NS.DEFAULT_PROFILE`. Cut-and-paste only; **no content edits** in this commit. — **KCD-41**
- ☐ **7.2** `core/Database.lua`: read `NS.DEFAULT_PROFILE` at `:291-292`; delete the `:304`
  re-export. Confirm no file-scope statement indexes the tree at load. — **KCD-41**
- ☐ **7.3** `KickCD.toc`: add `defaults\Profile.lua` before `defaults\Spells.lua`. — **KCD-41**
- ☐ **7.4** Delete the second copy at `modules/Castbar.lua:566-590` and read the shared tree; the
  positional `nameTextColor` at `:573`/`:583` goes with it. — **KCD-41**
  *(gate: `tests/test_database.lua` green unchanged; the Sprint-1 color cases still green; in-client:
  a fresh profile gets the shipped defaults and an existing one is untouched)*

**Exit:** `KCD-41` closed. Exactly one place hardcodes a default.

---

## Sprint 8 — The two decisions (scheduling, not coding)

These need a call from the user before code moves.

- ☐ **8.1** `KCD-48` — decide between removing the write (pass the candidate into `allowedKeys`) and
  containing it (`pcall` around mutate/probe/restore). Implement, and add a case that makes
  `values()` raise and asserts the stored value is unchanged — proven falsifiable by removing the
  guard and watching it redden (`testing-§12`). — **KCD-48**
- ☐ **8.2** `KCD-38` — decide between (a) narrowing `Ka0s_KickCD_CONFIG_CHANGED` to one owning seam
  (probably relocated from `settings/Panel.lua:75` into `core/`) and (b) taking a fan-in carve-out
  upstream to `architecture-§4`. Record the decision in `docs/message-bus.md` and
  `docs/ARCHITECTURE.md:118` either way. Route (a) also removes `A-8` for free. — **KCD-38**, **A-8**
- ☐ **8.3** *(optional, `A-3`)* Add `.superpowers` and `.claude` to `.pkgmeta`'s ignore list.
- ☐ **8.4** *(optional, `A-7`)* Delete or fill `KickCD.toc:14`'s commented `X-Wago-ID` placeholder.

**Exit:** `KCD-38` and `KCD-48` either closed or converted into recorded accepted deviations with the
user's reason attached — which is the standard's own escalation path and what stops `KCD-38` from
being carried into a fourth audit unchanged.

---

## Release checkpoint

Before the next tag (`automated-tests-§6`, `documentation-§1`, `performance-§10`):

- ☐ Produce a full four-suite bundle with `tests/_kit/run-automated-tests.sh`.
- ☐ Confirm the manifest shows **all four** at `pass` and `suites.complexity.warnings == 0`
  (`automated-tests-§3`, *The release gate*). A `skip` is **not** a pass; if `perf` is still a skip
  because Sprint 6 has not landed, state the narrow no-`tests/perf.lua` exception in the release
  notes explicitly.
- ☐ Write that run's `ANALYSIS.md` (`automated-tests-§5`), evidence-backed against its own bundle,
  reporting complexity with **totals and averages both**.
- ☐ Update `RESULTS.md`'s watch list with dispositions for anything that newly crossed, and note the
  band movement the Sprint-4 mock rebuild produces.
- ☐ Roll `## What's new` and the top `## Version History` row forward together; keep the `[wow]` and
  `[tests]` badges in lockstep with the TOC and the regenerated inventory.
- ☐ Re-run both `diff -r` vendor checks (Sprint 0).

---

## Rough sizing

| Sprint | Deviations | Size | Blocked by |
|---|---|---|---|
| 0 — verify vendor sync | (would open `KCD-50`) | 0.5 d | — |
| 1 — the color bug | `KCD-42` | 0.5 d | — |
| 2 — docs and prose | `KCD-37`, `KCD-47`, `KCD-44` (doc half), `A-9` | 0.5 d | — |
| 3 — output seams | `KCD-33`, `KCD-45`, `KCD-46` | 1 d | 3.3 after Sprint 4 |
| 4 — test harness | `KCD-30`, `KCD-43` | 2–3 d | Sprint 0 |
| 5 — Options surface | `KCD-40`, `KCD-31`, `KCD-32` | 2–3 d | Sprint 4; 5.9 upstream |
| 6 — performance | `KCD-34`, `KCD-35`, `KCD-49`, `KCD-44` (dep half) | 2 d | Sprint 4 (loader) |
| 7 — defaults tree | `KCD-41` | 1 d | Sprint 1 |
| 8 — the two decisions | `KCD-38`, `KCD-48`, `A-3`, `A-7`, `A-8` | user call | — |

Total ≈ **10–12 working days** plus one upstream `LibKa0s` minor (5.9) and two user decisions
(Sprint 8).
