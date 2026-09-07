# 02 — Proposed Changes (HLD + LLD)

**Repo:** KickCD v1.2.1 · **Date:** 2026-09-07
**Standard resolved:** Ka0s WoW Addon Standard **v2.38.0 (2026-09-02)** — index plus all 27 section files
fetched verbatim with `curl` from
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master/standards/`.
The standards cross-check **was performed**; every change below is annotated with its conformance note.

Derived from `01_FINDINGS.md`. Change IDs are `C-nn` and map back to finding IDs.

---

## HLD — themes

### Theme A — Stop patching a process-global registry from five addons; promote the fixup into LibKa0s

**Covers:** KICKCD-R-01

**Rationale.** `core/LSMPatch.lua` exists to close a 42 px cosmetic gap in *this addon's* settings panel,
but the mechanism it uses — `AceGUI:RegisterWidgetType("LSM30_Border", wrapper, currentVer + 1)` — has no
per-consumer scope. `AceGUI.WidgetRegistry` is a LibStub singleton, so the wrapper applies to every
`LSM30_Border` any addon creates for the rest of the session. Five Ka0s addons each ship their own copy and
**all five differ**, which is both the blast radius and the maintenance story in one sentence.

This clears all three of `library-stack`'s promotion bars, and it is worth stating each one explicitly
because the standard is equally clear that raw frequency alone is *not* a reason to share
(`anti-patterns` #55):

1. **2+ consumers with the same semantics** — five, and the semantics are identical: hide `displayButton`,
   re-anchor `label` and `DLeft`. The divergence between the copies is comment prose and load timing, not
   behaviour.
2. **No per-consumer escape hatches** — none of the five copies takes a parameter or branches on the host.
3. **A stable abstraction** — the shape has been "wrap the constructor, hide one child, re-anchor two"
   since it was written; it is pinned by a third-party library's layout, not by any Ka0s design that is
   still moving.

**Alternatives considered and rejected.**

- *Patch `libs/AceGUI-3.0-SharedMediaWidgets/prototypes.lua` directly.* **Rejected.** Third-party vendored
  code is read-only (`anti-patterns` #48); the next re-vendor silently reverts it and the regression has no
  cause anywhere in this addon's history. The compliant shape for a third-party defect is a
  presence-guarded workaround in the addon's own code — which is what `core/LSMPatch.lua` already is. The
  problem is not *that* it is a workaround, it is *where* the workaround lives and how wide it reaches.
- *Leave the five copies and just add an idempotence marker to each.* **Rejected.** It fixes the nesting
  but not the drift (they already differ) and not the cross-addon reach. It also entrenches exactly the
  duplication the extraction exists to end.
- *Scope the patch to KickCD's own widgets only.* **Rejected as impossible.** AceGUI's registry is the only
  hook; there is no per-consumer widget namespace. The honest mitigation is to make the patch **once,
  correctly, idempotently, and in one place** — which is the upstream change.

### Theme B — Bring the evidence artifacts back into agreement with the code

**Covers:** KICKCD-R-02, KICKCD-R-05

**Rationale.** The addon's out-of-game evidence is unusually good — `docs/test-cases.md` and the README
badge are byte-current, and `docs/performance.md` matches today's run. Two things have slipped: a test
function has crossed the release gate's CCN ceiling, and `RESULTS.md`'s prose has fallen three runs behind
its own table. Neither affects a player; both affect whether the next release can be cut and whether a
reader can trust the trend line.

**Trade-off accepted.** `RESULTS.md` is regenerated **in place at release** by the vendored kit script. The
right fix is upstream in the generator, not a hand-edit here — `performance-§10` is explicit that a
hand-corrected report is worse than a wrong one because it reads as measured.

### Theme C — Close the localisation seam and give it a gate

**Covers:** KICKCD-R-03

**Rationale.** Three `desc` sentences were extended at the call site without the locale file following.
English is unaffected because `NS.L` returns the key on a miss (the mandated fallback,
`anti-patterns` #2) — which is exactly *why* it went unnoticed for a release. The durable fix is not the
three keys; it is the missing headless case that would have caught them.

**Alternative rejected.** *Shorten the `desc` strings back to the existing keys.* Rejected — the longer
sentences carry real information (which sizing row the auto-size toggle overrides), and shortening user
text to match a stale locale file is the tail wagging the dog.

### Theme D — Make the test suite honest about isolation and about what it covers

**Covers:** KICKCD-R-04, KICKCD-R-09

**Rationale.** Two independent small defects with the same root: a test that is a little less true than it
reads. One leaks shared state on the failure path, so a real red turns into a cascade whose first symptom
is 40 lines from its cause. The other guards a branch for a function that shipped two sprints ago, so the
case reads as covering two shapes while covering one.

### Theme E — Reader-facing precision (no behaviour change)

**Covers:** KICKCD-R-07, KICKCD-R-08, KICKCD-R-10, KICKCD-R-11, KICKCD-R-12

**Rationale.** A cluster of small, low-risk items: a diagnostic that goes quiet on the branch it exists to
explain, a comment contradicted by the line beneath it, one avoidable allocation, and two naming
inconsistencies that cost a reviewer a file read each. Grouped because they share a risk profile
(near-zero) and none needs its own checkpoint.

---

## Upstream change-set (does NOT land in this repo)

**No entry anywhere in this document targets a path under `libs/` or `tests/_kit/` in KickCD.**
Both entries below are changes in the LibKa0s repo, followed by a re-vendor commit here.

### U-01 — LibKa0s: own the `LSM30_Border` fixup, once, idempotently

- **Finding:** KICKCD-R-01
- **Owning repo:** `../LibKa0s`
- **File within the library:** a new file in the `LibKa0s-Options-1.0` family (the major that already owns
  the settings-panel shell and its widget makers) — e.g. `LibKa0s/OptionsLSMPatch.lua`, added to
  `LibKa0s/LibKa0s.xml` **after** `Options.lua`.
- **The fix:**
  - Expose one additive member, `Options.PatchLSMBorder()`, which:
    - returns immediately if a module-level `applied` flag is already set (idempotence across consumers —
      today's five copies each wrap independently because nothing marks the registry);
    - resolves `AceGUI-3.0` via `LibStub(..., true)` and returns silently when absent;
    - wraps the current `LSM30_Border` constructor and re-registers at `currentVer + 1`, with the same
      `displayButton:Hide()` + `label` / `DLeft` re-anchor body the five copies share;
    - sets `applied = true`.
  - Because the library is **vendored**, the `applied` flag is per-copy, so five installed Ka0s addons
    still produce up to five wraps. Close that too, with a registry sentinel the wrapper stamps onto the
    constructor it returns (e.g. a `__ka0sLSMBorderPatched` field on the registry entry) and checks before
    wrapping. This is the part none of the five current copies has and the part that makes the fix correct
    rather than merely shared.
- **Minor bump:** `LibKa0s-Options-1.0` minor +1 (additive member; no existing behaviour changes).
- **Consumer work, per consumer:** delete `core/LSMPatch.lua`, remove its TOC line, and call
  `Options.PatchLSMBorder()` from the existing `settings/OptionsSetup.lua` live branch — where the library
  instance already exists and where the degradation stub already returns early, so a missing library means
  no patch, which is the correct degraded answer. The five consumers are **KickCD, AbsorbTracker,
  ConsumableMaster, MultiMeters, PanelMaster**.
- **Exit criterion in this repo:** a standalone **re-vendor commit** copying the whole `../LibKa0s/LibKa0s`
  folder into `libs/LibKa0s/`, with `tests/test_vendor_sync.lua` green and the `CLAUDE.md:52` provenance
  line updated to the new tag. The `core/LSMPatch.lua` deletion is a **separate** commit, after it.

### U-02 — LibKa0s testkit: regenerate `RESULTS.md`'s prose sections, not only its table

- **Finding:** KICKCD-R-05
- **Owning repo:** `../LibKa0s`
- **File within the kit:** `testkit/run-automated-tests.sh` (vendored here as
  `tests/_kit/run-automated-tests.sh` — **read-only in this repo**)
- **The fix:** the script prepends a row to the run table but leaves the "Test suite", "Lint" and
  "Complexity watch list" prose describing whichever run last had them rewritten by hand. Either regenerate
  those sections from the newest `manifest.json` alongside the row, or emit them into a clearly-marked
  generated block so a stale hand-written section is visible as such. As shipped, one file states 756 cases
  in prose and 780 in its own table.
- **Minor bump:** kit revision +1, recorded in `tests/_kit/README.md` upstream.
- **Exit criterion in this repo:** the same re-vendor commit as U-01 (both payloads are gated against one
  tag — `CLAUDE.md:58`), then the **next release run** regenerates `RESULTS.md` correctly. Nothing about
  `docs/automated-tests/` is edited by hand at any point.

---

## LLD — change-set

### C-01 — Adopt the library's LSM border patch; delete the local copy

- **Findings:** KICKCD-R-01
- **Depends on:** U-01 landing upstream and being re-vendored here
- **Files touched:** `core/LSMPatch.lua` (deleted), `KickCD.toc` (one line removed),
  `settings/OptionsSetup.lua` (one line added)
- **Before → after:**

  ```lua
  -- core/LSMPatch.lua  (68 lines, deleted in full)
  local hookFrame = CreateFrame("Frame")
  hookFrame:RegisterEvent("PLAYER_LOGIN")
  hookFrame:SetScript("OnEvent", function(self)
      ...
      AceGUI:RegisterWidgetType("LSM30_Border", function() ... end, currentVer + 1)
  end)
  ```

  ```lua
  -- settings/OptionsSetup.lua, in the live branch after NS.Settings.Helpers = lib:New(descriptor)

  -- The AceGUI-3.0-SharedMediaWidgets LSM30_Border fixup. Guarded and applied at most
  -- once per session across every Ka0s addon (LibKa0s-Options-1.0 minor N); it used to be
  -- five hand-copies of one wrapper, each re-registering the widget for the whole client.
  if Helpers.PatchLSMBorder then Helpers.PatchLSMBorder() end
  ```

- **Risk notes.** The call site moves from `PLAYER_LOGIN` to **file load**. The current file waits for
  login on the stated grounds that "every addon's libs have run and the LSM30_Border registry slot is
  stable" — that reasoning must be carried upstream and honoured there, so `PatchLSMBorder` should itself
  defer to `PLAYER_LOGIN` internally rather than patch on the caller's frame. If it does not, the fix
  regresses the ordering the current file was careful about. **This is the single riskiest line in the
  whole change-set** and it is why C-01 has its own checkpoint in `04_EXECUTION_PLAN.md`.
  The other risk is cosmetic-only and in-client-visible only: `03_SMOKE_TESTS.md` §C-01 covers it.
- **Standards conformance.** `library-stack` — all three promotion bars met and stated. `anti-patterns` #48
  — the third-party vendored widget library is **not** edited; the workaround stays in first-party code.
  `anti-patterns` #55 — the extraction is justified by shared semantics across five consumers, not by
  frequency. **Rejected option and the rule it broke:** editing
  `libs/AceGUI-3.0-SharedMediaWidgets/prototypes.lua`, which `anti-patterns` #48 forbids outright.

### C-02 — Split the CCN-18 test case along the seam its own comment names

- **Findings:** KICKCD-R-02
- **Files touched:** `tests/test_schema.lua`, `docs/test-cases.md`, `README.md`
- **Before → after:** the case at `tests/test_schema.lua:595` runs two scenarios. Its own comment at
  `:616`–`:620` already names the seam: *"And an UNLINKED page's strip is untouched…"*. Split there:

  ```lua
  -- red under: dropping the disable pass, or applying it to an unlinked page.
  test("a linked Focus's tab strip is disabled and desaturated", function()
      ... assertions on the linked strip only ...
  end)

  -- red under: extending the disable pass to unlinked pages -- there the tabs are the
  -- only way to reach most of the page's rows, so a disabled strip is an unusable page.
  test("an unlinked Focus's tab strip stays operable and undimmed", function()
      ... the operable/dimmed count assertions ...
  end)
  ```

- **Risk notes.** No production code changes. Both halves keep their `-- red under:` falsification note, so
  neither becomes an unfalsifiable negative (`testing-§12`). Fold C-03's isolation fix in at the same time,
  since it touches the same two case bodies.
- **Regression pressure on the inventory.** This moves the pass count **841 → 842**.
  `docs/test-cases.md` (regenerated by `lua tests/run.lua --list`, never hand-edited) and the README
  `[Tests]` badge **must move in this same change** — `testing-§7` is explicit that the inventory travels
  with the change that moves the count, not as a follow-up.
- **Expected complexity movement (a note for the next release, not a task now):** this should take the
  lizard warning count from 1 back to 0 and the max CCN from 18 back to 15, restoring the
  `automated-tests-§3` release gate. To be **confirmed by the next release's regeneration**, not by
  regenerating `docs/automated-tests/` here.
- **Standards conformance.** `automated-tests-§3` (the release gate is what motivates the split);
  `testing-§7` (inventory and badge move together); `testing-§12` (both halves keep a falsification note).
  **Rejected options:** raising the lizard threshold, and adding a pre-commit complexity gate —
  `performance-§10` names the latter as a documented anti-pattern that teaches a collection to reach for
  `--no-verify`.

### C-03 — Make the three shared-instance tests restore unconditionally

- **Findings:** KICKCD-R-04
- **Files touched:** `tests/test_schema.lua` (2 sites), `tests/test_options_panel.lua` (1 site)
- **Before → after:**

  ```lua
  -- before: restore is the last statement, skipped when an assertion unwinds
  local cfg = NS.Units.Config("focus")
  local before = cfg and cfg.link
  if cfg then cfg.link = true end
  ...assertions...
  if cfg then cfg.link = before end
  ```

  ```lua
  -- after: a fresh isolated instance -- nothing shared, nothing to restore
  local inst = T.load(true)
  local NS   = inst.NS
  local cfg  = NS.Units.Config("focus")
  if cfg then cfg.link = true end
  ...assertions...
  ```

  Where a fresh instance is too slow for the case, the alternative is
  `local ok, err = pcall(body); if cfg then cfg.link = before end; if not ok then error(err, 0) end` —
  correct, but noisier; prefer the fresh instance.
- **Risk notes.** `T.load(true)` is measurably slower than the shared instance (a full source load per
  call). Three extra loads is acceptable; if the suite's wall time moves noticeably, use the pcall shape
  instead. Pass count is **unchanged**, so no inventory movement from this change alone.
- **Standards conformance.** `testing` — no assertion is weakened, deleted or made unfalsifiable; the
  change only guarantees teardown. No test is edited to change a result.

### C-04 — Reconcile the three cast-bar `desc` keys and add a locale-coverage gate

- **Findings:** KICKCD-R-03
- **Files touched:** `locales/enUS.lua`, `tests/test_locale.lua`, `docs/test-cases.md`, `README.md`
- **Before → after (`locales/enUS.lua`):**

  ```lua
  -- before (:340, :342, :347) -- keys no code references any more
  L["Cast bar width in pixels."]   = "Cast bar width in pixels."
  L["Cast bar height in pixels."]  = "Cast bar height in pixels."
  L["Spell icon size in pixels (0 hides the icon)."] = "..."
  ```

  ```lua
  -- after -- the keys settings/Castbar.lua:219/:227/:302 actually use
  L["Cast bar width in pixels. Overridden by Auto-size to icon grid while the bar is horizontal."] =
      "Cast bar width in pixels. Overridden by Auto-size to icon grid while the bar is horizontal."
  L["Cast bar height in pixels. Overridden by Auto-size to icon grid while the bar is vertical."] =
      "Cast bar height in pixels. Overridden by Auto-size to icon grid while the bar is vertical."
  L["Spell icon size in pixels (0 hides the icon). Capped at the bar's short axis so the icon never overflows it."] =
      "Spell icon size in pixels (0 hides the icon). Capped at the bar's short axis so the icon never overflows it."
  ```

- **The gate (the part that matters).** One new case in `tests/test_locale.lua`:

  ```lua
  -- red under: extending any L["..."] sentence at a call site without updating locales/enUS.lua
  -- -- which is exactly the drift this case was added for (three cast-bar desc rows, 2026-09).
  test("every L[...] key the addon references exists in locales/enUS.lua", function()
      -- Scan the addon's OWN sources, derived from the TOC via T.tocFiles -- never a
      -- hand-maintained file list (testing-§9), and never libs/ or tests/_kit/.
      ... collect L["..."] literals, assert each is a key of the loaded locale table ...
  end)
  ```

  It must scan a **TOC-derived** file list (`T.tocFiles` is already exposed by `tests/run.lua`), skip
  `core/PerfSetup.lua`'s comment-only `NS.L["STEP_START"]` reference by matching code rather than comments,
  and assert positively (key present) so it is falsifiable by construction.
- **Risk notes.** Low. The user-visible English is byte-identical before and after, because the metatable
  fallback was already producing exactly these sentences.
- **Regression pressure:** +1 case, **841 → 842** (or 843 with C-02). `docs/test-cases.md` and the README
  badge move in the same change.
- **Standards conformance.** `localization` — user-facing strings go through `L[…]` with a complete
  `locales/enUS.lua`; `anti-patterns` #2 — the key-returning metatable fallback stays, it is what keeps a
  future miss non-fatal. `testing-§9` — the new case derives its file list from the TOC.
  **Rejected option:** shortening the `desc` strings to match the stale keys, which would trade correct
  user documentation for a smaller diff.

### C-05 — Make the cast-bar debug dump speak on its secret branch

- **Findings:** KICKCD-R-07
- **Files touched:** `modules/Castbar_Debug.lua`
- **Before → after:**

  ```lua
  -- before (:42-:50) -- the whole body is inside the capability guard, no else
  local function reportSecretNint(print)
      if _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean then
          -- Pass to FontString:SetText via a hidden frame to render and
          -- read back. Cleanest: just say "secret" and trust the curve.
          print("    secret-tainted; visual state determined via "
              .. "C_CurveUtil.EvaluateColorValueFromBoolean")
      end
  end
  ```

  ```lua
  -- after -- the report is unconditional; the capability is a separate clause.
  -- The value is described, never tostring'd: this is the default arm of NINT_REPORT
  -- precisely because anything reaching it is presumed secret.
  local function reportSecretNint(print)
      local haveCurve = _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean
      print("    secret-tainted; not rendered in Lua. Visual state is "
          .. (haveCurve
              and "determined via C_CurveUtil.EvaluateColorValueFromBoolean"
              or  "UNAVAILABLE -- C_CurveUtil is missing on this client"))
  end
  ```

  The abandoned-design comment ("Pass to FontString:SetText via a hidden frame…") is deleted, not moved:
  it describes a route that was considered and rejected, and it now reads as a TODO.
- **Risk notes.** Diagnostic output only, behind an undocumented developer verb. No secret value is
  stringified, compared or arithmetic'd — the change adds no new read of `notInterruptible`.
- **Standards conformance.** `debug-logging` — diagnostics route through the addon's printer seam
  (unchanged here: `print` is the resolved `NS.Util.print`). The secret-value discipline is preserved
  exactly.

### C-06 — Remove the contradicted anchor fallback

- **Findings:** KICKCD-R-08
- **Files touched:** `settings/Panel_Render.lua`
- **Before → after:**

  ```lua
  -- before (:301-:304)
  NS.db.profile.units.target.anchors.icons = d
      and { point = d.point, relativePoint = d.relativePoint, x = d.x, y = d.y }
      or  { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }
  ```

  ```lua
  -- after -- one source for the number, which is what the header already promises.
  -- Nothing to reset to if the defaults tree failed to load; the caller's grid keeps
  -- its current position rather than jumping to a coordinate invented here.
  if not d then return end
  NS.db.profile.units.target.anchors.icons =
      { point = d.point, relativePoint = d.relativePoint, x = d.x, y = d.y }
  ```

- **Risk notes.** The removed branch is unreachable in any shipping configuration
  (`NS.DEFAULT_PROFILE` is set by a TOC-loaded file). Confirm no test asserts on `y = -180`
  before deleting.
- **Standards conformance.** `savedvariables` — `defaults/Profile.lua` stays the single place a profile
  default is hardcoded, which the current fallback quietly violated.

### C-07 — Delete the dead `NewBusTarget` fallback in the bus suite

- **Findings:** KICKCD-R-09
- **Files touched:** `tests/test_bus.lua`
- **Before → after:** replace the `if not target then … end` block at `:47`–`:53` and its
  "lands in Sprint 3 (KCD-09)" comment with a direct positive assertion:

  ```lua
  local target = assert(NS.NewBusTarget, "NS.NewBusTarget must exist (core/KickCD.lua)")()
  ```

- **Risk notes.** None. Pass count unchanged.
- **Standards conformance.** `testing` — removes a branch that reads as coverage and provides none; no
  assertion is weakened.

### C-08 — Cache the cast-bar `OnUpdate` closure

- **Findings:** KICKCD-R-10
- **Files touched:** `modules/Castbar.lua`
- **Before → after:**

  ```lua
  -- before (:833), rebuilt at every cast start
  inst.frame:SetScript("OnUpdate", function() onUpdate(inst) end)
  ```

  ```lua
  -- in EnsureFrame, once per instance:
  inst.__onUpdate = inst.__onUpdate or function() onUpdate(inst) end
  -- at :833:
  inst.frame:SetScript("OnUpdate", inst.__onUpdate)
  ```

- **Risk notes.** `inst` is stable for a frame's lifetime, so the closure is safe to reuse. `Castbar:Stop`
  still nils the script, so the teardown path is unchanged.
- **The number behind the claim, and its absence.** `tests/perf.lua` has **no cast-bar scenario** today,
  and the committed capture's `castTick` bucket measures the per-frame loop
  (`docs/perf-analysis/20260807-131311/dump.json`: `"castTick":{"calls":1262,…,"totalMs":11.6115}`),
  not the per-cast setup. So this change's benefit is currently **unmeasurable**. If C-08 is taken, add a
  `castStart` scenario to `tests/perf.lua` asserting bytes/iter, so the claim has a record —
  `performance-§8`: an interpretation without its record is an assertion. If the scenario is not added,
  do not claim a perf improvement in the changelog.
- **Standards conformance.** `performance` — a perf claim must name the scenario that demonstrates it;
  this change is therefore paired with the scenario or not made at all. Scenarios are **not** counted in
  `docs/test-cases.md` or the README badge (`testing-§7`).

### C-09 — Prefix the bare WoW globals

- **Findings:** KICKCD-R-11
- **Files touched:** `modules/IconGrid.lua:232`, `modules/Cooldowns.lua:80`,
  `modules/Castbar_Debug.lua:55`/`:60`/`:61`, `settings/Panel_Widgets.lua:121`,
  `settings/OptionsSetup.lua:126`
- **Before → after:** `UnitClass("player")` → `_G.UnitClass("player")`, and so on for `UnitExists`,
  `UnitName`, `UnitIsUnit`, `InCombatLockdown`, `C_Timer`.
- **Risk notes.** None functionally — the kit's `makeEnv` resolves both spellings through the same mock
  table and `.luacheckrc` declares both, so the suite and lint are unaffected either way. Purely
  mechanical; run `luacheck .` and the suite after.
- **Standards conformance.** `architecture-§1` — the explicit `_G.` prefix is what makes a
  Compat-bypassing read visible in review, which is the addon's own stated rationale in `tests/run.lua`.

### C-10 — Rename the shadowing `print` parameter

- **Findings:** KICKCD-R-12
- **Files touched:** `modules/Castbar_Debug.lua` (8 function signatures + their call sites)
- **Before → after:** the parameter `print` becomes `emit`, matching `settings/Slash.lua:61`'s `out(line)`
  convention. The resolution at `:125` stays exactly as it is:
  `local emit = NS.Util and NS.Util.print or _G.print`.
- **Risk notes.** Rename only; no control flow changes. `tests/test_castbar_debug.lua` asserts on the
  emitted lines, not on the parameter name, so it should stay green untouched — verify.
- **Standards conformance.** `slash-commands-§4` / `naming-cheatsheet` — every user-facing line still goes
  through the prefixed printer; the rename makes that visible at a glance instead of requiring a file read.

---

## Change → finding map

| Change | Findings | Files | Parallelisable with |
|---|---|---|---|
| U-01 | KICKCD-R-01 | `../LibKa0s` (upstream) | U-02 |
| U-02 | KICKCD-R-05 | `../LibKa0s/testkit` (upstream) | U-01 |
| C-01 | KICKCD-R-01 | `core/LSMPatch.lua`, `KickCD.toc`, `settings/OptionsSetup.lua` | C-04…C-10 (after U-01) |
| C-02 | KICKCD-R-02 | `tests/test_schema.lua`, `docs/test-cases.md`, `README.md` | — (serialise with C-03, C-04) |
| C-03 | KICKCD-R-04 | `tests/test_schema.lua`, `tests/test_options_panel.lua` | — (serialise with C-02) |
| C-04 | KICKCD-R-03 | `locales/enUS.lua`, `tests/test_locale.lua`, `docs/test-cases.md`, `README.md` | — (serialise with C-02) |
| C-05 | KICKCD-R-07 | `modules/Castbar_Debug.lua` | C-06, C-08, C-09 |
| C-06 | KICKCD-R-08 | `settings/Panel_Render.lua` | C-05, C-08, C-09, C-10 |
| C-07 | KICKCD-R-09 | `tests/test_bus.lua` | everything |
| C-08 | KICKCD-R-10 | `modules/Castbar.lua`, `tests/perf.lua` | C-05, C-06, C-09, C-10 |
| C-09 | KICKCD-R-11 | 5 files across `modules/`, `settings/` | — (touches C-05's and C-01's files) |
| C-10 | KICKCD-R-12 | `modules/Castbar_Debug.lua` | — (touches C-05's file) |

**Serialisation callouts.** `tests/test_schema.lua` is touched by **C-02 and C-03** → serialise.
`docs/test-cases.md` and `README.md` are touched by **C-02 and C-04** → serialise, and regenerate the
inventory once at the end of both rather than twice. `modules/Castbar_Debug.lua` is touched by
**C-05, C-09 and C-10** → serialise. `settings/OptionsSetup.lua` is touched by **C-01 and C-09** →
serialise.

---

## Standards conformance summary

Every change above was checked against **v2.38.0**. None introduces a new deviation. Rules that shaped or
constrained a change: `library-stack` (promotion bars, C-01), `anti-patterns` #48 (no edit to vendored
third-party code, C-01), `anti-patterns` #55 (extraction justified by semantics not frequency, C-01),
`anti-patterns` #2 (the locale metatable fallback stays, C-04), `automated-tests-§3` (the release gate,
C-02), `testing-§7` (inventory and badge move with the count, C-02/C-04), `testing-§9` (TOC-derived file
lists, C-04), `testing-§12` (falsification notes on both halves of a split case, C-02), `performance-§8`
(a perf claim names its record, C-08), `performance-§10` (no per-commit complexity gate; no hand-edited
report, C-02/U-02), `savedvariables` (one place for a default, C-06), `architecture-§1` (`_G.` prefix,
C-09), `localization` (C-04), `line-endings-§2` (KICKCD-R-06, deliberately left as an observation for the
audit rather than a change here).

**Options rejected for violating a rule**, recorded so the reasoning is not re-litigated:
editing `libs/AceGUI-3.0-SharedMediaWidgets/prototypes.lua` (#48); editing `tests/_kit/run-automated-tests.sh`
in place (#48, same rule, vendored kit); hand-editing `docs/automated-tests/RESULTS.md`
(`performance-§10`); raising the lizard threshold or adding a pre-commit complexity gate
(`performance-§10`); and hand-editing `docs/test-cases.md` rather than regenerating it from
`tests/run.lua --list`.
