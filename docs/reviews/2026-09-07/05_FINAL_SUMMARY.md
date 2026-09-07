# 05 — Final summary

**Repo:** KickCD v1.2.1 · **Review date:** 2026-09-07
**Status of this document:** written **ahead of implementation**, under the assumption that every check in
`03_SMOKE_TESTS.md` passes. Reconcile the counts and the evidence pointers against what actually shipped
before using it as a PR description or changelog entry (checkpoint CP-5 in `04_EXECUTION_PLAN.md`).

---

## Headline

KickCD came out of this review in good shape. Every out-of-game suite was re-run from scratch on 2026-09-07
and every one is green: lint clean over 36 files, **841 of 841** headless cases passing, the committed test
inventory and the README badge byte-identical to a fresh `--list`, the committed offline performance
write-up matching today's measurements exactly, and both vendored payloads content-identical to their
source repo. No Critical findings, no taint issues, no deprecated-API usage, and a secret-value discipline
that is the strongest in the collection.

The work in this cycle is one real design fix and a set of small honesty repairs. The design fix removes a
patch this addon was applying to a **process-global** AceGUI widget registry — a 42 px cosmetic
adjustment to its own settings panel that silently reached every other addon in the session, and that
existed as five hand-copied, already-divergent files across the Ka0s collection. It moves upstream into
LibKa0s, applied once and idempotently, and the five local copies are deleted. The rest brings the addon's
own evidence back into agreement with its code: a test function that had crossed the release gate's
complexity ceiling, three localisation keys that drifted away from the sentences using them (plus the
missing gate that would have caught them), three tests that leaked shared state on the failure path, and a
handful of comments and names that had stopped telling the truth.

---

## Counts

**As proposed** (fill in the "fixed" column at CP-5):

| Severity | Raised | Addressed in this cycle | Deferred |
|---|---|---|---|
| Critical | 0 | 0 | — |
| High | 1 | 1 (KICKCD-R-01) | 0 |
| Medium | 6 | 5 | 1 |
| Low | 5 | 5 | 0 |
| **Total** | **12** | **11** | **1** |

**Deliberately deferred:**

- **KICKCD-R-06** — nine tracked files whose working-tree line endings disagree with `.gitattributes`'s
  `* text=auto eol=crlf` pin, including `KickCD.toc` and three shipped `.lua` files. Deferred because
  `line-endings-§2`'s authoritative check — its commands and its rolled-up straggler count — belongs to
  `/wow-addon:standards-audit`, not to a code review. Renormalising here would pre-empt that agent's count
  and produce a large, unreviewable diff mid-cycle. Recorded, not forgotten.

**Routed elsewhere, not deferred:**

- **KICKCD-R-05** — `docs/automated-tests/RESULTS.md`'s prose contradicts its own newest table row (756
  cases in prose, 780 in the table, 841 today). The fix is in the vendored kit's generator and lands
  upstream (U-02); the file itself is regenerated in place at release and is never hand-edited.

---

## Changes by theme

### Theme A — Stop patching a process-global registry from five addons

**What changed.** `core/LSMPatch.lua` is deleted. The AceGUI `LSM30_Border` layout fixup it performed now
lives in LibKa0s, exposed as `Options.PatchLSMBorder()` and called once from `settings/OptionsSetup.lua`'s
live branch. The library version is idempotent — it stamps a sentinel on the registry entry — so several
Ka0s addons installed together apply the fix once between them instead of once each.

**Why it mattered.** `AceGUI.WidgetRegistry` is a LibStub singleton with no per-consumer scope. Wrapping
`LSM30_Border` and re-registering at `currentVer + 1` won the version race for **every** addon in the
session, so a third-party addon's border-preview tile silently vanished and its dropdown bar shifted, with
nothing pointing at KickCD as the cause. Five Ka0s addons shipped their own copy of the wrapper and a
`diff --strip-trailing-cr` showed all five already differed from one another — the drift a shared library
exists to end, with the added twist that each copy wrapped the constructor independently.

**Findings covered:** KICKCD-R-01 · **Changes implemented:** U-01, C-01
**Files touched:**
- `core/LSMPatch.lua` *(deleted, 68 lines)*
- `KickCD.toc` *(one `# Core` line removed)*
- `settings/OptionsSetup.lua` *(one guarded call added in the live branch)*
- `libs/LibKa0s/` *(whole-folder re-vendor, its own commit)*

### Theme B — Bring the evidence artifacts back into agreement with the code

**What changed.** One test case that had grown to CCN 18 was split in two along the seam its own comment
already named, restoring the tree to zero functions above CCN 15. Upstream, the automated-test report
generator was fixed so it regenerates its prose sections alongside its table row rather than leaving them
describing an older run.

**Why it mattered.** `automated-tests-§3` gates the release tag on all four suites passing **plus zero
functions above CCN 15**. The newest committed bundle recorded zero warnings and a max CCN of 15; today's
fresh run recorded one warning at CCN 18, so the gate had been crossed and the next release would have
blocked with no obvious cause. Separately, `RESULTS.md` was stating 756 cases in prose while its own newest
row said 780 — a trend line that disagrees with itself is worse than no trend line, because it is read as
measured.

**Findings covered:** KICKCD-R-02, KICKCD-R-05 · **Changes implemented:** C-02, U-02
**Files touched:**
- `tests/test_schema.lua`
- `docs/test-cases.md` *(regenerated by `lua tests/run.lua --list`, never hand-edited)*
- `README.md` *(the `[Tests]` badge)*
- `tests/_kit/` *(whole-folder re-vendor; the generator fix is upstream)*

### Theme C — Close the localisation seam and give it a gate

**What changed.** Three cast-bar tooltip sentences were reconciled between `settings/Castbar.lua` and
`locales/enUS.lua`, and three superseded shorter keys were removed. A new headless case now asserts that
every `L["…"]` literal in the addon's own TOC-derived sources resolves to a key in `locales/enUS.lua`.

**Why it mattered.** The three `desc` strings had been extended at the call site without the locale file
following. English still rendered correctly — `NS.L` returns the key on a miss, the mandated fallback —
which is precisely why it survived a release unnoticed. The three rows were untranslatable and the locale
file carried three orphans. The durable fix is the gate, not the keys; the drift had no way of being caught
before.

**Findings covered:** KICKCD-R-03 · **Changes implemented:** C-04
**Files touched:** `locales/enUS.lua`, `tests/test_locale.lua`, `docs/test-cases.md`, `README.md`

### Theme D — Make the test suite honest about isolation and coverage

**What changed.** Three cases that set `focus.link = true` on the **shared** addon instance and restored it
as their last statement now take a fresh isolated instance instead, so a failing assertion cannot leak
state into every case that follows. A dead branch in the message-bus suite, guarding for an
`NS.NewBusTarget` that shipped two sprints ago, was replaced with a direct positive assertion.

**Why it mattered.** The kit pcalls each case body, so an unwinding assertion skipped the restore and left
`focus.link = true` for the rest of the run — turning one genuine failure into a cascade whose first
visible symptom was in an unrelated suite. The dead branch made a case read as covering two shapes while
covering one.

**Findings covered:** KICKCD-R-04, KICKCD-R-09 · **Changes implemented:** C-03, C-07
**Files touched:** `tests/test_schema.lua`, `tests/test_options_panel.lua`, `tests/test_bus.lua`

### Theme E — Reader-facing precision

**What changed.** `/kcd debug castbar` now prints its secret-value report unconditionally instead of
swallowing it when `C_CurveUtil` is unavailable, and an abandoned-design comment was removed. A hardcoded
anchor fallback in `settings/Panel_Render.lua` that contradicted both its own header comment and
`defaults/Profile.lua` was deleted. The remaining bare WoW globals were given the `_G.` prefix the addon's
own convention calls for, and the parameter shadowing the global `print` throughout
`modules/Castbar_Debug.lua` was renamed.

**Why it mattered.** None of these changes what a player sees, but each cost a reader something. The debug
dump went quiet on exactly the branch it exists to explain. The anchor comment promised "we don't duplicate
magic numbers" and the next line duplicated them wrongly (`y = -180` against a real default of `y = +120`).
The `print` parameter made twenty correct call sites read exactly like the forbidden bare-global pattern.

**Findings covered:** KICKCD-R-07, KICKCD-R-08, KICKCD-R-10, KICKCD-R-11, KICKCD-R-12
**Changes implemented:** C-05, C-06, C-08 *(conditional)*, C-09, C-10
**Files touched:** `modules/Castbar_Debug.lua`, `settings/Panel_Render.lua`, `modules/IconGrid.lua`,
`modules/Cooldowns.lua`, `settings/Panel_Widgets.lua`, `settings/OptionsSetup.lua`,
`modules/Castbar.lua` *(C-08 only)*, `tests/perf.lua` *(C-08 only)*

---

## API / behaviour changes

Externally observable changes, in full:

| Change | Detail |
|---|---|
| **Cross-addon side effect removed** | KickCD no longer alters the `LSM30_Border` widget for other addons. A third-party Ace3 options panel with a border picker now renders exactly as it does with KickCD uninstalled. This is the one user-visible behaviour change in the set, and it is a **removal** of an unintended effect. |
| **New debug output line** | `/kcd debug castbar` gains one line on the secret-tainted branch, stating the visual state's determination route and whether `C_CurveUtil` is available. Developer-facing only. |
| **`/kcd resetposition` fallback removed** | The unreachable fallback coordinate is gone; the command now no-ops if the defaults tree is somehow absent rather than moving the grid to an invented position. No shipping configuration reaches either path. |
| **Slash commands** | **None added, renamed or removed.** `NS.COMMANDS`, `DEBUG_COMMANDS` and `SPELLS_COMMANDS` are unchanged. |
| **Locale keys** | 3 keys added to `locales/enUS.lua` (the current full sentences); 3 superseded keys removed. Rendered English is byte-identical before and after, because the metatable fallback was already producing exactly these sentences. |
| **Defaults** | None added, none removed, none changed. |

---

## Saved-variable / migration notes

**No schema change. No migration. No version bump.**

`CURRENT_DB_VERSION` stays at **5** (`core/Database.lua:35`) and the four-step migration walk at
`core/Database.lua:521`–`:528` is untouched. Nothing in this cycle alters the shape of
`DEFAULT_PROFILE`, `db.global` or `db.profile`.

Existing user profiles carry forward unchanged. **No `/kcd reset` is required** and none should be
suggested to users. The one saved-variable-adjacent change (C-06) removes an unreachable fallback branch;
it writes nothing new and reads nothing new.

---

## Deprecated-API migrations

**None. The sweep found nothing to migrate** — recorded so a future reviewer does not repeat it.

| Checked | Result |
|---|---|
| `GetSpellInfo`, `GetSpellCooldown`, `GetSpellCharges`, `GetSpellTexture` | Already routed through `core/Compat.lua`, which tries the `C_Spell.*` form first and keeps the legacy global only as an explicit fallback rung (`core/Compat.lua:162`–`:171`) |
| `IsAddOnLoaded` / `GetAddOnMetadata` | Already via `LibKa0s-Env-1.0` (`core/EnvSetup.lua:74`), replacing three previously-inline `C_AddOns` ladders |
| `UnitAura` / `UnitBuff` / `UnitDebuff` | Not used anywhere |
| `GetContainerNumSlots` / `GetContainerItemInfo` | Not used anywhere |
| `InterfaceOptions_AddCategory` | Not used; the panel uses `Settings.RegisterCanvasLayoutSubcategory` throughout (5 sites) |
| `SetBackdrop` without `BackdropTemplate` | None — every backdrop frame passes the template (`modules/Castbar.lua:531`–`:532`, `modules/IconGrid_Render.lua:224`) |
| `PLAYER_TALENT_UPDATE` and other retired events | None — the modern `TRAIT_CONFIG_UPDATED` is used (`modules/Cooldowns.lua:472`, `modules/IconGrid.lua:752`) |
| `setmetatable` on a Blizzard widget | None; `modules/IconGrid_Render.lua:194` documents why it is avoided |

---

## Performance impact

**No measurable change is claimed**, and this section deliberately contains only measured numbers.

**Offline scenarios** (`lua5.1 tests/perf.lua`) are expected to be **unchanged** by every change in this
cycle, because none of them touches the poll or apply paths. The 2026-09-07 baseline, to be re-run and
compared after the work lands:

| scenario | ms/iter | api/iter | bytes/iter |
|---|---|---|---|
| `spellPoll` | 0.01824 | 18.0 | 545.7 |
| `spellState` | 0.00630 | 0.0 | 216.8 |
| `iconApply` | 0.00280 | 0.0 | 848.0 |
| `probeOverheadOff` | 0.00284 | 0.0 | 848.0 |
| `probeOverheadOn` | 0.00316 | 0.0 | 848.1 |

The zero-overhead property `performance-§2` requires holds and is measured, not asserted:
`probeOverheadOff` (848.0 B) is identical to the un-instrumented `iconApply` baseline (848.0 B), and arming
the probe costs 0.1 B per pass.

**C-08 (cast-bar closure caching) is conditional and, as of this review, unmeasurable.** `tests/perf.lua`
has no cast-bar scenario, and the committed in-game capture's `castTick` bucket
(`docs/perf-analysis/20260807-131311/dump.json`: `{"calls":1262,"maxMs":0.0560,"totalMs":11.6115}`)
measures the per-**frame** loop, not the per-cast setup this change touches. If C-08 ships without a
`castStart` scenario, **no performance claim may be made for it** — `performance-§8`: an interpretation
without its record is an assertion.

**Reference bucket figures** from the committed capture, for anyone comparing a future in-game run.
Nested totals are **not** disjoint and must never be summed; and the capture's own
`fps.deltaMsPerFrame` of `-0.1740` ms is below the harness's run-to-run spread and is therefore
**unresolved** — no conclusion rests on it.

```
spellPoll     399 calls  135.2610 ms  (max 1.7497)
  pollSpell  1596 calls   67.1303 ms
  spellState 1171 calls   54.3927 ms
    iconApply 2342 calls  50.0322 ms
castTick     1262 calls   11.6115 ms
cdText        225 calls   11.4686 ms
castEvent      11 calls    1.6358 ms
visibility     21 calls    1.6512 ms
```

---

## Test and complexity movement

| Metric | Before (2026-09-07, measured) | After (expected) |
|---|---|---|
| Headless cases | **841 passed, 0 failed, 0 skipped** | **843** (+1 from C-02's split, +1 from C-04's coverage case) |
| `docs/test-cases.md` | in sync with the suite | regenerated **once**, after both C-02 and C-04 |
| README `[Tests]` badge | `841/841 passing` | `843/843 passing`, moved in the same change |
| `luacheck .` | 0 warnings / 0 errors, 36 files | unchanged, minus `core/LSMPatch.lua` → 35 files |
| `lizard` warnings | **1** (CCN 18, `tests/test_schema.lua:595`) | **0** |
| Max CCN | **18** | **15** |

`docs/test-cases.md` is emitted by the runner's non-executing `--list` mode and is **never** hand-edited.
The inventory and the badge move in the **same change** as the count (`testing-§7`), not as a follow-up.

**Watch-list entries these changes are expected to move**, to be confirmed by the **next release's**
regeneration and not by regenerating `docs/automated-tests/` now:

- `(anonymous)@595-631@./tests/test_schema.lua` — CCN 18 → gone (split into two cases at ~CCN 9 each)
- `CCN warn` column: 1 → 0; `Max CCN`: 18 → 15, restoring the `automated-tests-§3` release gate
- `Files` column: 36 → 35 (`core/LSMPatch.lua` deleted)
- The `Tests` column: 780 (as last recorded) → 843

---

## Known follow-ups

| Item | Rationale for deferring |
|---|---|
| **KICKCD-R-06** — nine line-ending stragglers against `.gitattributes` | `line-endings-§2`'s authoritative check and rolled-up count belong to `/wow-addon:standards-audit`. Renormalising mid-cycle would pre-empt that count and bury the real changes in a large mechanical diff. |
| **The other four `core/LSMPatch.lua` copies** — AbsorbTracker, ConsumableMaster, MultiMeters, PanelMaster | Same defect, four other repos. Each needs its own adoption milestone once LibKa0s ships `PatchLSMBorder`. Tracked as cross-repo work so it is not lost when this bundle closes. |
| **A `castStart` perf scenario** | Only worth adding if C-08 is taken. Without it, C-08 is skipped rather than shipped unmeasured. |
| **`RESULTS.md` prose regeneration** | The generator fix is upstream (U-02); the file itself is rewritten in place at the next release run. Never hand-edited. |
| **`docs/automated-tests/` regeneration** | Release work (`/wow-addon:bump-version`), not review work. The expected movements are recorded above for that run to confirm. |

---

## Verification evidence

- **Headless measurement:** `01_FINDINGS.md` § *Measurement run*, all suites re-run 2026-09-07 with the
  exact commands and their real output.
- **In-client verification:** `03_SMOKE_TESTS.md`, sign-off table completed — **required** before this
  summary is used as a PR description. Checkpoint **CP-2** (§C-01a–e) is the one that cannot be substituted
  by any headless run.
- **Execution record:** `04_EXECUTION_PLAN.md`, checkpoints CP-1 … CP-5.
- **Commit range / PR:** `________________` *(fill in at CP-5)*
- **Vendored payload provenance:** `CLAUDE.md:52`, updated to the LibKa0s tag that carries
  `Options.PatchLSMBorder` and the testkit generator fix; gated by `tests/test_vendor_sync.lua`.

---

## Suggested commit message / PR description

```
Move the LSM border fixup upstream; restore the release gate and the locale seam

Removes a process-global side effect, restores the complexity gate, and closes a
localisation drift that had no way of being caught.

core/LSMPatch.lua wrapped AceGUI's LSM30_Border constructor and re-registered it at
currentVer + 1 to close a 42px cosmetic gap in KickCD's own settings panel. AceGUI's
WidgetRegistry is a LibStub singleton, so that wrapper applied to every addon in the
session -- a third-party border picker lost its preview tile with nothing pointing at
KickCD. Five Ka0s addons shipped their own copy of the wrapper and all five had already
drifted apart. The fixup now lives in LibKa0s as an idempotent, once-per-session
Options.PatchLSMBorder(), called from settings/OptionsSetup.lua; the local copy is gone.

A test case had grown to CCN 18, crossing automated-tests-3's "zero functions above 15"
release gate, which the newest committed bundle still recorded as clean. It is split in
two along the seam its own comment named. Three tests that mutated the shared instance
and restored only on the success path now take isolated instances, so one genuine
failure no longer cascades into unrelated suites.

Three cast-bar tooltip sentences had been extended at the call site without
locales/enUS.lua following. English rendered correctly via the mandated key-returning
fallback, which is exactly why it survived a release -- the three rows were simply
untranslatable. Keys reconciled, and a new headless case now asserts every L[...]
literal in the TOC-derived sources resolves.

Plus: /kcd debug castbar now reports its secret-tainted branch unconditionally instead
of swallowing it when C_CurveUtil is absent; an unreachable anchor fallback that
contradicted DEFAULT_PROFILE by 300px is removed; the remaining bare WoW globals take
the _G. prefix the addon's own convention calls for.

No saved-variable schema change, no migration, no deprecated-API migration -- the sweep
found nothing to migrate. No slash command added, renamed or removed.

Findings: KICKCD-R-01 (High), R-02, R-03, R-04, R-05, R-07 (Medium),
          R-08, R-09, R-10, R-11, R-12 (Low)
Deferred: KICKCD-R-06 (line endings -- belongs to the standards audit)

Tests: 841 -> 843 passing, 0 failed, 0 skipped
Lint:  0 warnings / 0 errors
Lizard: 1 warning (CCN 18) -> 0; max CCN 18 -> 15
Review bundle: docs/reviews/2026-09-07/
```
