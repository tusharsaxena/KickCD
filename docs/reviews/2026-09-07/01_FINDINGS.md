# 01 — Findings

**Repo:** KickCD (Ka0s KickCD v1.2.1) · **Review date:** 2026-09-07 · **Reviewer:** principal-engineer code review (full scope)
**Standard resolved:** Ka0s WoW Addon Standard **v2.38.0 (2026-09-02)**, fetched from
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master/standards/STANDARDS.md`
plus all 27 section files discovered from its Sections list. The standards cross-check was **performed**
(it constrains the remediation in `02_PROPOSED_CHANGES.md`; it is not an audit — see
`/wow-addon:standards-audit` for that).

---

## Verdict

**Ship-ready with minor issues.** No Critical findings. One High: a hand-copied AceGUI widget patch that
mutates a **process-global** registry and exists as five divergent copies across the collection. Everything
else is Medium or below. The addon's own runtime code is in unusually good shape — every out-of-game suite
is green today, the committed test inventory and README badge match the fresh run byte-for-byte, and the
committed offline perf write-up matches today's numbers.

---

## Measurement run (Step 0 — everything re-run from scratch today, 2026-09-07)

All commands run from the repo root `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD`.
Generated output was written to a scratch path outside the repo; **no committed artifact was touched.**

| Suite | Command | Result |
|---|---|---|
| **luacheck** | `luacheck .` | **pass** — `Total: 0 warnings / 0 errors in 36 files` |
| **Headless test suite** | `lua5.1 tests/run.lua` | **pass** — `841 passed, 0 failed, 0 skipped, 841 total` |
| **Test-case inventory** | `lua5.1 tests/run.lua --list` → scratch | **pass** — 1062 lines; `diff` vs. committed `docs/test-cases.md` (CR-normalised) is **empty** |
| **Offline perf runner** | `lua5.1 tests/perf.lua` | **ran** (not a gate) — 5 scenarios, figures below |
| **Complexity** | `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` → scratch | **ran** — 17109 NLOC, 2229 funcs, avg CCN 2.1, **1 warning** |
| **Makefile `test:` target** | — | **skipped (no `Makefile` in the repo root)** |
| **Vendor sync — LibKa0s** | `diff -r --strip-trailing-cr libs/LibKa0s/ ../LibKa0s/LibKa0s/` | **pass** — empty (content identical) |
| **Vendor sync — testkit** | `diff -r tests/_kit/ ../LibKa0s/testkit/` | **pass** — empty (byte identical) |

Scope of the counts above: `luacheck .` and `lizard` both cover `core/ defaults/ modules/ settings/ locales/
tests/` and **exclude** `libs/` and `tests/_kit/` (lizard by explicit `-x`, luacheck by `.luacheckrc`).
`docs/` and `media/` contain no Lua and are not counted.

### Today's offline perf numbers (`tests/perf.lua`, orientation only — compare within this run)

```
scenario                iters      ms/iter     api/iter   bytes/iter
spellPoll                2000      0.01824         18.0        545.7
spellState               2000      0.00630          0.0        216.8
iconApply                2000      0.00280          0.0        848.0
probeOverheadOff         2000      0.00284          0.0        848.0
probeOverheadOn          2000      0.00316          0.0        848.1
```

The **zero-overhead** evidence `performance-§2` requires is present and holds today:
`probeOverheadOff` allocates **848.0 B/iter**, identical to the un-instrumented `iconApply` baseline
(848.0), and `probeOverheadOn` costs **0.1 B/iter** more. A dormant bracket is free, measured rather than
asserted.

### Today's complexity: the one warning

```
NLOC  CCN  token  PARAM  length  location
  29   18    248      0      37  (anonymous)@595-631@./tests/test_schema.lua
```

Highest CCN in the addon's **own runtime source** today is **15**, at five sites:
`Layout.layoutBlock@modules/IconGrid_Layout.lua:145`, `buildSpecNameMaps@core/Util.lua:232`,
`OnAccept@settings/Spells.lua:503`, `State.ApplyInterruptibleAlpha@core/State.lua:109`,
`StateChanged@modules/Cooldowns.lua:252`. No runtime file is in `layout-§1`'s 1000–1500 LOC on-notice
band except `modules/IconGrid.lua` (1152), `settings/Spells.lua` (1296) and `modules/Castbar.lua` (1320);
all three are under the 1500 hard cap and all three carry a recorded intentional-split note.

### Committed artifacts that disagree with today's run

| Artifact | Committed says | Today says | Reading |
|---|---|---|---|
| `docs/test-cases.md` | 841 cases | 841 cases | **agrees** (byte-identical after CR normalisation) |
| `README.md` `[Tests]` badge | `841/841 passing` | 841/841 | **agrees** |
| `docs/performance.md` | dormant arm "measured 848.0", ceiling 900 B | 848.0 | **agrees** |
| `docs/perf-analysis/20260807-131311/` | `spellPoll` 135.26 ms / 399 calls | (in-client; not re-run here) | frozen evidence, cited below |
| `docs/automated-tests/RESULTS.md` | newest row `20260825-103417`: 780/780, 35 files, CCN warn **0**, max CCN 15 | 841/841, 36 files, CCN warn **1**, max CCN 18 | **stale** → see KICKCD-R-02 and KICKCD-R-05 |

`docs/automated-tests/RESULTS.md` is regenerated at **release** (`/wow-addon:bump-version`), so being
behind the working tree is expected and is *stale, not non-compliant*. What is **not** expected is that its
own prose contradicts its own newest table row — that is KICKCD-R-05.

In-client checks (taint under real combat, locale rendering, the `/kcd perf` two-arm capture protocol,
saved-variable migration across a real `/reload`) are deliberately **absent** from this block. They are in
`03_SMOKE_TESTS.md`.

---

## Conventions detected in this addon (checks applied only where the convention exists)

- `NS.PREFIX` chat prefix + a single printer at **`NS.Util.print`** (never `NS.Print` — the AceConsole
  embed collision, `architecture-§2`). ✔ applied.
- `NS.COMMANDS` / `DEBUG_COMMANDS` / `SPELLS_COMMANDS` ordered dispatch tables in `core/KickCD.lua`,
  passed **into** `LibKa0s-Slash-1.0` rather than owned by it. ✔ applied.
- Single write path: `Helpers.SetAndRefresh` (schema rows) with a documented carve-out for anchors,
  `link` and spell lists, which are not schema rows. ✔ applied.
- Flat-row settings schema, composed across `settings/*.lua` into `NS.Settings.Schema`. ✔ applied.
- `.gitattributes` carries `* text=auto eol=crlf`, the `*.sh text eol=lf` carve-out and the full binary
  list. ✔ checked (KICKCD-R-06).
- Nine adopted `LibKa0s` majors, eight with a setup file (`core/CoreSetup.lua`, `core/EnvSetup.lua`,
  `core/PoolSetup.lua`, `core/MediaSetup.lua`, `core/DebugLogSetup.lua`, `core/PerfSetup.lua`,
  `settings/Slash.lua`, `settings/OptionsSetup.lua`) plus `LibKa0s-Widgets-1.0` resolved inline in
  `settings/Spells.lua`. Each carries a descriptor **and** a degradation stub; `tests/test_surface_parity.lua`
  diffs live surface against stub. ✔ reviewed as the addon's half of the contract.
- Vendored test kit at `tests/_kit/`. ✔ never globbed, never edited.
- Evidence the addon generates about itself: `tests/run.lua` + 52 suites, `docs/test-cases.md`,
  `tests/perf.lua` + `docs/performance.md`, one frozen in-game capture at
  `docs/perf-analysis/20260807-131311/`, and seven automated-test bundles under `docs/automated-tests/`.
  ✔ all re-measured or cited.
- No `docs/CLAUDE_SECRET_VALUES.md`; the secret-value rules live in `CLAUDE.md` and in the module headers.
  The secret discipline in the code is **excellent** — see the note at the end of this file.

---

## High

### KICKCD-R-01 — `core/LSMPatch.lua` rewrites AceGUI's process-global widget registry, in five divergent copies

- **Locus:** `core/LSMPatch.lua:46` (`AceGUI:RegisterWidgetType("LSM30_Border", …, currentVer + 1)`)
- **Category:** `[design]` `[cross-cutting]`
- **Problem:** to close a 42 px cosmetic gap in *this addon's* settings panel, the file wraps whatever
  `LSM30_Border` constructor AceGUI currently holds and re-registers the wrapper at `currentVer + 1` —
  winning the version race for **every addon in the session**, not just KickCD. `AceGUI.WidgetRegistry`
  is a LibStub singleton; there is no per-consumer scope. Any other addon that creates an `LSM30_Border`
  widget (Ace3 config panels with a LibSharedMedia border picker) gets KickCD's `displayButton:Hide()`
  and KickCD's `DLeft` re-anchor applied to its widget too.
- **Impact:** a third-party addon's border-preview tile silently disappears and its dropdown bar shifts,
  with no error and nothing pointing at KickCD. Compounding it, the file has **no idempotence marker**, so
  with several Ka0s addons installed the constructor is wrapped once per addon — five nested closures for
  one fix.
- **Reachability:** `Any player running KickCD alongside any other addon that builds an AceGUI
  LSM30_Border widget — every session, from PLAYER_LOGIN, on a default profile.`
- **Evidence (measured, not asserted):** five sibling repos ship their own `core/LSMPatch.lua` —
  `AbsorbTracker` (50 lines), `ConsumableMaster` (65), `KickCD` (68), `PanelMaster` (66),
  `MultiMeters` (101) — and `diff --strip-trailing-cr` shows **all four siblings differ from KickCD's copy**.
  Five hand-copies of one fix, already drifted. Command:
  `for a in AbsorbTracker ConsumableMaster MultiMeters PanelMaster; do diff -q --strip-trailing-cr KickCD/core/LSMPatch.lua $a/core/LSMPatch.lua; done`
  → four `differ` results.
- **Fix direction:** this clears all three of `library-stack`'s promotion bars — 2+ consumers, identical
  semantics, no per-consumer flags, a stable shape — so the compliant direction is **upstream into
  LibKa0s** as an additive, once-only, marker-guarded patch that every consumer calls from its setup file,
  and delete the five local copies. Do **not** patch `libs/AceGUI-3.0-SharedMediaWidgets/` (third-party
  vendored, `anti-patterns` #48) and do not paper over it with a sixth local variant.
- **Scope:** `libka0s-upstream` (and cross-cutting: four sibling addons carry the same defect).

---

## Medium

### KICKCD-R-02 — today's tree has a CCN-18 function; the documented release gate is "zero above 15"

- **Locus:** `tests/test_schema.lua:595` — the case `"a linked Focus's tab strip is disabled and desaturated"`,
  measured by lizard as `(anonymous)@595-631`, **CCN 18**, 29 NLOC, 37 lines.
- **Category:** `[complexity]` `[tests]`
- **Problem:** `automated-tests-§3` gates the release tag on "all four suites at `pass`, **plus zero
  functions above CCN 15**", evaluated by `/wow-addon:bump-version` from the release run's
  `manifest.json`. The newest committed bundle (`20260825-103417`) records `CCN warn 0`, `Max CCN 15`.
  Today's fresh run records **1 warning at CCN 18**, so the gate has been crossed since that bundle.
- **Impact:** the next release run blocks. The cause is a single test case doing **two** independent
  scenarios — the linked-Focus strip and then the unlinked-Focus strip — in one body, with two nested
  loops each.
- **Reachability:** `Only a maintainer running the release gate; no shipped code path and no player is
  affected — the CCN sits in a test file.` (Reachability caps this below High.)
- **Evidence:** fresh `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .`, warnings block:
  `29 18 248 0 37 (anonymous)@595-631@./tests/test_schema.lua`. Committed comparison:
  `docs/automated-tests/RESULTS.md:23` — newest row `Max CCN 15 | CCN warn 0`.
- **Fix direction:** split the case in two along the seam its own comment already names ("And an UNLINKED
  page's strip is untouched"), which removes decisions rather than relocating them. Do **not** raise the
  lizard threshold and do **not** gate commits on complexity — `performance-§10` names a per-commit
  complexity gate as an anti-pattern. Splitting one case into two moves the count 841 → 842, so
  `docs/test-cases.md` and the README `[Tests]` badge must move **in the same change** (`testing-§7`).
- **Scope:** `addon-local`

### KICKCD-R-03 — three cast-bar tooltip keys are used but absent from `locales/enUS.lua`

- **Locus:** `settings/Castbar.lua:219`, `:227`, `:302` vs. `locales/enUS.lua:340`, `:342`, `:347`
- **Category:** `[locale]`
- **Problem:** three schema `desc` strings were extended with a second sentence at the call site, but the
  locale file still carries only the older, shorter keys. Cited verbatim:
  - used — `settings/Castbar.lua:219`:
    `desc = L["Cast bar width in pixels. Overridden by Auto-size to icon grid while the bar is horizontal."],`
  - defined — `locales/enUS.lua:340`:
    `L["Cast bar width in pixels."]   = "Cast bar width in pixels."`

  Same pattern for the height row (`:227` vs. `:342`) and the icon-size row (`:302` vs. `:347`).
- **Impact:** English still renders correctly, because `NS.L` carries the mandated key-returning metatable
  fallback (`anti-patterns` #2) and the keys *are* English sentences. But the three rows are **not
  translatable** — a `locales/deDE.lua` added tomorrow has no key to translate — and `enUS.lua` now
  carries three orphaned entries no code reads, which is drift in both directions at once.
- **Reachability:** `Every player who hovers those three cast-bar rows sees correct English today; a
  non-enUS locale could never translate them, and the addon ships only enUS.`
- **Evidence:** full key sweep — 222 distinct `L["…"]` keys referenced across `core/ modules/ settings/
  defaults/`, 304 defined in `locales/enUS.lua`; `comm -23` of the two sorted sets yields exactly four
  unmatched keys: the three above plus `"STEP_START"`, which is a false positive (it appears only inside a
  comment in `core/PerfSetup.lua:197` explaining why the addon deliberately does **not** hand `NS.L` to the
  library — correct behaviour, and pinned by `tests/test_perfsetup.lua:372`).
- **Fix direction:** add the three current sentences to `locales/enUS.lua` and remove the three superseded
  keys. Then add a headless case asserting every `L["…"]` literal in the addon's own sources resolves to an
  entry in `locales/enUS.lua` — there is no such case today (`tests/test_locale.lua` covers spec/locale
  independence only), which is why the drift went unnoticed.
- **Scope:** `likely-cross-cutting` (the missing key-coverage test is a collection-wide gap; the drift
  itself is local)

### KICKCD-R-04 — three tests mutate the shared instance and restore only on the success path

- **Locus:** `tests/test_schema.lua:581`, `tests/test_schema.lua:630`, `tests/test_options_panel.lua:552`
  — each the line `if cfg then cfg.link = before end`, the **last statement** of its case body
- **Category:** `[tests]`
- **Problem:** all three cases take `local cfg = NS.Units.Config("focus")` off `T.NS` — the **shared,
  DB-built instance** every non-degradation suite uses — set `cfg.link = true`, run assertions, then
  restore at the bottom. The kit's `test()` pcalls the body, so a failing assertion unwinds past the
  restore and leaves `focus.link = true` for every case that runs afterwards.
- **Impact:** one genuine failure in any of these three produces a cascade of unrelated red in later
  suites, and the real cause is 40 lines above the first visible symptom. It also makes the suite
  order-dependent in a way nothing declares.
- **Reachability:** `Only a developer debugging a red suite — but precisely then, when the diagnostic
  cost is highest. No shipped code path.`
- **Evidence:** `grep -rn --include='test_*.lua' '= before$' tests` → 3 sites; all three are the final
  statement of the case body, none is inside a `pcall`/finally shape.
- **Fix direction:** restore in a guaranteed-run wrapper, or take a fresh isolated instance via
  `T.load(true)` for these three cases so nothing needs restoring. Do not delete or weaken the assertions.
- **Scope:** `likely-cross-cutting`

### KICKCD-R-05 — `RESULTS.md` prose contradicts its own newest table row

- **Locus:** `docs/automated-tests/RESULTS.md:23` (newest row) vs. `:36`, `:56`, `:120` (prose)
- **Category:** `[docs]`
- **Problem:** the table's newest row is `20260825-103417 | 1.2.1 | 0/0 | 35 | 780/780 | … | 15 | 0 | green`.
  The prose beneath it still describes the run *before* that one:
  - `:36` — `**756 cases**, zero failed … The count has now held at 756 across three consecutive runs`
  - `:120` — `Current state as of [20260807-114618] — not that run's diff.` (the complexity watch list)
  - the Lint section — `Clean over **33** files as of [20260807-114618]`
- **Impact:** the file's job is to be the trend line a reader consults instead of re-deriving. A reader who
  takes the prose at face value is three runs and 85 test cases behind, and the watch list they are told is
  "current" predates the newest bundle. The gap against **today** is wider still: 841 cases, 36 files.
- **Reachability:** `Any maintainer or reviewer who reads RESULTS.md's prose rather than its table — the
  numbers disagree by 24 cases within the file itself, before today's run is considered.`
- **Evidence:** the three line citations above, quoted verbatim, against `:23`; and today's
  `lua5.1 tests/run.lua` → `841 passed`, `luacheck .` → `36 files`.
- **Fix direction:** this file is regenerated **in place** by `tests/_kit/run-automated-tests.sh` at
  release. Do not hand-edit it and do not regenerate it as part of a fix — a hand-edited report is worse
  than an absent one because it reads as measured (`performance-§10`). The next release run rewrites the
  prose sections; the finding is that the prose sections are **not** being regenerated alongside the table,
  which is a defect in the kit's generator, not in this repo's data.
- **Scope:** `libka0s-upstream` (the generator lives in `tests/_kit/run-automated-tests.sh`, vendored;
  fix upstream in `../LibKa0s/testkit/`, bump the kit revision, re-vendor the whole folder — **never** an
  edit under `tests/_kit/` here)

### KICKCD-R-06 — nine tracked files' working-tree line endings disagree with `.gitattributes`

- **Locus:** `.gitattributes:26` (`* text=auto eol=crlf`); stragglers include `KickCD.toc`,
  `core/PoolSetup.lua`, `modules/IconGrid.lua`, `tests/test_icongrid_buildlist.lua`, `.pkgmeta`,
  `docs/slash-dispatch.md`, `docs/revendor/2026-08-25/01_DELTA.md` (**mixed**), `docs/revendor/2026-08-25/05_SUMMARY.md`
- **Category:** `[line-endings]`
- **Problem:** `.gitattributes` is correct and complete — `* text=auto eol=crlf` at `:26`, the
  `*.sh text eol=lf` carve-out at `:34`, and the full binary list at `:43`–`:59`. The **working tree** does
  not agree with it: eight files check out LF and one checks out mixed, against a `crlf` pin.
- **Impact:** cosmetic for Lua the client loads either way, but it produces spurious whole-file diffs on the
  next touch (exactly the `1,793c1,793` shape seen in the vendor byte-diff), and `01_DELTA.md`'s **mixed**
  endings are the state that makes a future normalisation look like a content change.
- **Reachability:** `No player; any contributor whose next edit to one of these nine files produces a
  whole-file diff, and any reviewer reading that diff.`
- **Evidence:** `git ls-files --eol | grep -v 'w/crlf' | grep -v 'w/-text'` → 9 rows, each showing
  `w/lf` or `w/mixed` against `attr/text=auto eol=crlf`. The one `attr/text eol=lf` row
  (`tests/_kit/run-automated-tests.sh`) is the intended carve-out and is **not** a straggler.
- **Fix direction:** renormalise the working tree (`git add --renormalize .` as its own commit). This is a
  review **observation**; the authoritative rolled-up count belongs to `/wow-addon:standards-audit`
  (`line-endings-§2`), which owns the check.
- **Scope:** `likely-cross-cutting`

### KICKCD-R-07 — `/kcd debug castbar` silently prints nothing on the secret branch when `C_CurveUtil` is absent

- **Locus:** `modules/Castbar_Debug.lua:42`–`:50` (`reportSecretNint`)
- **Category:** `[design]` `[observability]`
- **Problem:** `NINT_REPORT` handles `boolean` and `nil`; **every other type falls through to
  `reportSecretNint`**, which is the one branch that matters (a secret-tainted `notInterruptible` in
  combat). That function's entire body sits inside
  `if _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean then … end` — with no `else`. On a
  client where the curve API is unavailable, the dump emits its `type=…, isSecret=…` line
  (`:85`) and then **nothing at all** where the value report should be.
- **Impact:** the diagnostic goes quiet exactly on the path it exists to explain, and a reader cannot tell
  a missing report from "there was nothing to say". The guard also tests for a capability
  (`C_CurveUtil` exists) that has no bearing on whether the *sentence* can be printed — the branch prints
  only prose.
- **Reachability:** `Only a developer who types /kcd debug castbar — an undocumented diagnostic verb,
  unreachable from the settings UI — and only on a client lacking C_CurveUtil.` (Capped below High.)
- **Evidence:** `modules/Castbar_Debug.lua:44` is the sole statement guard; `:87` routes every non-boolean,
  non-nil type here. The stale scaffolding comment at `:45`–`:46` ("Pass to FontString:SetText via a hidden
  frame to render and read back. Cleanest: just say 'secret' and trust the curve.") describes a design that
  was abandoned and now only confuses.
- **Fix direction:** print the "secret-tainted" line unconditionally, and mention `C_CurveUtil`'s
  availability as a separate clause. Delete the abandoned-design comment. Keep every existing
  secret-handling rule — do not `tostring` the value.
- **Scope:** `addon-local`

---

## Low

### KICKCD-R-08 — a fallback anchor contradicts both its own comment and the real default

- **Locus:** `settings/Panel_Render.lua:304`
- **Category:** `[naming]` `[dead-code]`
- **Problem:** `Helpers.ResetIconPosition`'s header states the default coords come from
  `DEFAULT_PROFILE.units.target.anchors.icons` "so we don't duplicate magic numbers across UI / CLI /
  Database layers" — and then line 304 duplicates them anyway, **wrongly**:
  - `settings/Panel_Render.lua:304` — `or  { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }`
  - `defaults/Profile.lua:314` — `icons   = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 },`

  300 px apart and opposite in sign.
- **Impact:** none at runtime — the branch is reached only when `NS.DEFAULT_PROFILE` is nil, which cannot
  happen in a shipping install (`defaults/Profile.lua` is a TOC-loaded file). The harm is that the comment
  asserts an invariant the next line breaks, which is the kind of thing a future reader trusts.
- **Reachability:** `Nobody: the fallback needs defaults/Profile.lua to have failed to load, which no
  shipping configuration produces. A reader-facing defect only.`
- **Fix direction:** drop the fallback and early-return when `d` is nil, or make the fallback a reference
  to the same constant. Either way, one source for the number.
- **Scope:** `addon-local`

### KICKCD-R-09 — a test carries a dead "lands in Sprint 3" fallback for a shipped function

- **Locus:** `tests/test_bus.lua:48` vs. `core/KickCD.lua:46`
- **Category:** `[tests]` `[dead-code]`
- **Problem:** `tests/test_bus.lua:48` reads
  `-- NewBusTarget lands in Sprint 3 (KCD-09); until then, exercise the` and guards an alternate code path
  behind `if not target then`. `NS.NewBusTarget` has shipped: `core/KickCD.lua:46` declares
  `function NS.NewBusTarget()`, it is used in production at `settings/Spells.lua:1227`, and the very next
  case (`tests/test_bus.lua:59`) asserts on it by name.
- **Impact:** the branch can never be taken, so the case reads as covering two shapes while covering one.
  The comment misdates the codebase for anyone reading the suite as documentation.
- **Reachability:** `Only the test inventory — the shipped code is correct and the branch is unreachable.`
- **Fix direction:** delete the fallback branch and the comment; assert `NS.NewBusTarget` exists instead.
  Case count is unchanged, so no inventory movement.
- **Scope:** `addon-local`

### KICKCD-R-10 — a fresh closure is allocated at every cast start

- **Locus:** `modules/Castbar.lua:833` — `inst.frame:SetScript("OnUpdate", function() onUpdate(inst) end)`
- **Category:** `[perf]`
- **Problem:** `Castbar:Start` builds a new closure over `inst` on every cast. `inst` never changes for a
  given cast bar, so the closure could be built once in `EnsureFrame` and cached on the instance.
- **Impact:** small and bounded — one closure per cast per tracked unit, not per frame. Worth noting only
  because this is the module that documents per-frame allocation avoidance in detail
  (`modules/Castbar.lua:668`–`:680`), so the one allocation left on the path stands out.
- **Reachability:** `Any player with the cast bar enabled, once per observed cast — a few dozen
  allocations per minute in heavy content, GC-visible only in aggregate.`
- **Evidence, and its limit:** today's `tests/perf.lua` has **no cast-bar scenario**
  (`spellPoll`/`spellState`/`iconApply`/`probeOverhead*` only), and the committed capture
  `docs/perf-analysis/20260807-131311/dump.json` measures `castTick` at
  `{"calls":1262,"maxMs":0.0560,"totalMs":11.6115}` — the per-**frame** loop, not the per-cast setup. So
  the cost of this specific allocation is **unverified**; there is no scenario or bucket that isolates it.
- **Fix direction:** cache `inst.__onUpdate = function() onUpdate(inst) end` in `EnsureFrame` and reuse it.
  If it is taken, add a cast-start scenario to `tests/perf.lua` so the claim has a record.
- **Scope:** `addon-local`

### KICKCD-R-11 — bare WoW globals sit beside `_G.`-prefixed reads in the same functions

- **Locus:** `modules/IconGrid.lua:232` (`local _, classFile = UnitClass("player")`) against
  `modules/IconGrid.lua:148` (`if not (_G.UnitExists and _G.UnitExists(unit))`); also
  `modules/Cooldowns.lua:80`, `modules/Castbar_Debug.lua:55`/`:60`/`:61` against `:59`,
  `settings/Panel_Widgets.lua:121` (`InCombatLockdown`), `settings/OptionsSetup.lua:126` (`C_Timer`)
- **Category:** `[naming]`
- **Problem:** `tests/run.lua` states the addon's own convention plainly — *"Nearly every WoW-API read in
  this addon is written `_G.C_SpecializationInfo`, `_G.InCombatLockdown`, `_G.UnitGUID` — explicit …
  the `_G.` prefix is what makes a Compat-bypassing read visible in review."* A handful of sites do not
  follow it, sometimes two lines from one that does.
- **Impact:** none functionally — the kit's `makeEnv` resolves both spellings through the same mock table,
  and `.luacheckrc` declares both, so lint is clean either way. The cost is the review signal the
  convention exists to give.
- **Reachability:** `No runtime effect; a reviewer-facing inconsistency only.`
- **Fix direction:** prefix the stragglers. Mechanical, low risk, no behaviour change.
- **Scope:** `likely-cross-cutting`

### KICKCD-R-12 — the global `print` is shadowed as a parameter name across a whole file

- **Locus:** `modules/Castbar_Debug.lua:33`, `:37`, `:42`, `:54`, `:69`, `:80`, `:97`, `:111` — each
  function takes a parameter literally named `print`; `:125` resolves it
  (`local print = NS.Util and NS.Util.print or _G.print`)
- **Category:** `[naming]`
- **Problem:** the routing is correct — every line goes through `NS.Util.print`, so this is **not** a raw
  `print(` bypass of the prefix helper. But naming the parameter `print` makes 20-odd call sites in the
  file read exactly like the forbidden bare-global pattern, and a reviewer (or a future grep-based lint
  rule) has to read the whole file to establish that they are not.
- **Impact:** review cost and false-positive risk, no runtime effect.
- **Reachability:** `No runtime effect; costs every future reviewer one file read to clear.`
- **Fix direction:** rename the parameter to `emit` (or `out`, matching `settings/Slash.lua:61`).
  Purely mechanical.
- **Scope:** `addon-local`

---

## What the review checked and found clean

Recorded because a review that only lists defects overstates the risk, and because several of these are
the exact places this collection has been bitten before.

- **Taint / protected APIs.** No protected call on a non-secure path; no `SetAttribute` under lockdown; no
  `SecureActionButtonTemplate` (deliberately avoided, with the reason stated at
  `modules/IconGrid_Render.lua:206`); no `:Hook` where `:SecureHook` is required.
  `Settings.RegisterCanvasLayoutSubcategory` is called from builders, never from `OnInitialize`, and both
  panel-open doors refuse under combat rather than deferring
  (`settings/Panel_Widgets.lua:121`, and `/kcd config` at `core/KickCD.lua:712`).
- **Secret values (12.0).** This is the strongest part of the codebase. Cooldown and cast-duration handles
  are never bound-then-read: they are passed straight into `SetCooldownFromDurationObject`,
  `SetFormattedText`, `SetValue`, `SetAlphaFromBoolean` and
  `C_CurveUtil.EvaluateColorValueFromBoolean`. Alpha and border toggles are folded **into** the curve's
  parameters rather than multiplied afterwards (`modules/Castbar.lua:756`–`:775`) precisely because
  multiplying a secret result would raise. Charge counts are probed with `_G.issecretvalue` before any
  comparison (`modules/Cooldowns.lua:115`, `:243`). `core/CoreSetup.lua`'s printer routes every argument
  through `NS.SafeToString`, whose concat probe is the one thing the degradation stub is allowed to
  reproduce.
- **Deprecated APIs.** No bare `GetSpellInfo`, `IsAddOnLoaded`, `UnitAura`, `GetContainerItemInfo` or
  `InterfaceOptions_AddCategory` on any live path. Every such read goes through `core/Compat.lua`, which
  tries the `C_*` form first and keeps the legacy global only as an explicit fallback rung
  (`core/Compat.lua:162`–`:171`). `BackdropTemplate` is passed wherever `SetBackdrop` is used
  (`modules/Castbar.lua:531`–`:532`, `modules/IconGrid_Render.lua:224`).
- **Frames.** `setmetatable` is never applied to a widget — `modules/IconGrid_Render.lua:194` documents
  why. `ClearAllPoints` precedes every re-anchor (`modules/IconGrid.lua:257`, `core/LSMPatch.lua:52`,
  `:62`). Icons come from `LibKa0s-Pool-1.0` keyed by spellID rather than per-event `CreateFrame`. The
  three named frames (`KickCDCastbar`, `KickCDCastbarFocus`, `KickCDUnitLabel*`) are named **on purpose**,
  with the reason stated at `modules/Castbar.lua:443` (macros and other addons reference them).
- **Events.** Registration is in the module `OnEnable` cascade, never `OnInitialize`. Per-unit cast events
  use `RegisterUnitEvent` through `core/Util.lua:410` rather than AceEvent's fan-out, with the reason at
  `:386`–`:389`. `TRAIT_CONFIG_UPDATED` is used for the modern talent system, not `PLAYER_TALENT_UPDATE`.
- **Saved variables.** `schemaVersion` is account-scoped in `db.global` with a four-step forward migration
  walk (`core/Database.lua:521`–`:528`) and a documented one-shot adoption of the legacy per-profile
  `dbVersion`. Defaults are deep-copied on every read (`copy` at `core/Database.lua:51`), so the shared
  defaults table is never mutated. No `x or true`/`x or false` defaulting anywhere — the codebase uses
  `~= false` and `== nil` throughout (17 sites), which is what `savedvariables` asks for.
- **Perf brackets.** Declared buckets and real brackets agree exactly, `within` nesting is declared,
  every bracketed function closes on **every** exit including the rejection and teardown paths, and the
  gate is read through a load-time upvalue. All four are pinned by `tests/test_perfsetup.lua`, and today's
  `probeOverheadOff` measurement (848.0 B, identical to baseline) confirms a dormant bracket is free.
- **Format-string arity.** A mechanical scan of every `:format(` / `format(` call across
  `core/ modules/ settings/ defaults/ locales/` found **zero** specifier/argument mismatches.
- **`COMMANDS` dispatcher.** Every documented verb resolves through `NS.COMMANDS` / `DEBUG_COMMANDS` /
  `SPELLS_COMMANDS`; `perf` is a **host** verb in `NS.COMMANDS` rather than one the library registers, and
  `tests/test_perfsetup.lua` pins that.
- **The library seam.** All eight setup files pass descriptors, never implementations. `core/PerfSetup.lua`
  passes **no** `L` at all, with a long comment explaining that handing it `NS.L` would satisfy the
  library's string check for every key and render `STEP_START` verbatim — a trap this addon already hit
  once and now guards with two separate cases. No stub re-implements a library formatter, line format or
  layout constant; `settings/OptionsSetup.lua:296` even records that the three layout constants are
  deliberately absent, and `tests/test_options_panel.lua` scans the file to keep them absent.

---

## Standards cross-check

Performed against **v2.38.0 (2026-09-02)**, all 27 sections fetched verbatim via `curl` to a scratch path.
No finding's fix direction in this document, and no entry in `02_PROPOSED_CHANGES.md`, recommends anything
the standard forbids or introduces a new deviation. Rules that shaped a remediation are cited inline
(`automated-tests-§3`, `testing-§7`, `performance-§10`, `library-stack`, `line-endings-§2`,
`anti-patterns` #2 / #48).
