# KickCD — Evidence (2026-08-05)

Every claim in `01_CURRENT_STATE.md` and `02_DEVIATIONS.md` is sourced here. Mechanical checks are
recorded with the **command actually run** and its **real output**; a check that could not run is
recorded as **NOT RUN** with the reason, never inferred.

---

## 1. Mechanical checks

### 1.1 Lint — RUN, clean

```
$ luacheck .
...
Checking settings/Profiles.lua                    OK
Checking settings/Slash.lua                       OK
Checking settings/Spells.lua                      OK

Total: 0 warnings / 0 errors in 32 files
exit=0
```

Matches `docs/automated-tests/20260804-233245/manifest.json`
(`"lint": {"status":"pass","warnings":0,"errors":0,"files":32}`).

### 1.2 Headless suite — RUN, green

```
$ lua5.1 tests/run.lua
...
  PASS  libs/LibKa0s is the LibKa0s release the README says this addon bundles
  PASS  tests/_kit is the test kit that shipped with that release

-------------------
737 passed, 0 failed
exit=0
```

**Read the last two PASS lines against `KCD-43`.** They are the vendor-sync cases, and in this
environment they returned before asserting (§1.5). A `PASS` from those two lines is not evidence of
vendor sync.

### 1.3 Generated inventory in lockstep — RUN, in sync

```
$ diff <(lua5.1 tests/run.lua --list | tr -d '\r') <(tr -d '\r' < docs/test-cases.md)
test-cases.md IN SYNC        # (no diff output)
```

737 cases. `README.md:7` reads `![Tests](https://img.shields.io/badge/Tests-737%2F737_passing-green)`
— the badge, the inventory and the run agree, which is why `KCD-36` is closed.

### 1.4 Complexity — RUN with the standard's exact invocation, zero drift

```
$ lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .
...
No thresholds exceeded (cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100)
Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt
     15430       6.5     2.1       48.9     2051            0      0.00    0.00
exit=0
```

Invocation taken verbatim from `performance-§10` / `AUDIT.md`; no flag added, no path narrowed, no
threshold re-tuned.

**Drift against the latest bundle: none.**

```
$ diff <(tr -d '\r' < docs/automated-tests/20260804-233245/complexity.txt) <(tr -d '\r' < /tmp/.../cx_now.txt)
IDENTICAL                    # (no diff output)
```

- **Functions that crossed a `lizard` threshold since that run:** none. Warning count 0, unchanged.
- **Files that entered the 1000–1500 on-notice band since that run:** none. The band still holds
  `modules/Castbar.lua` 1314, `settings/Spells.lua` 1172, `modules/IconGrid.lua` 1154,
  `tests/wow_mock.lua` 1066 (`wc -l`), matching `manifest.json`'s `"bandFiles": 4` and the four rows
  at `docs/automated-tests/RESULTS.md:140-143`.
- **Staleness of the bundle's own stamp:** `"startedAt": "2026-08-04T23:32:45+05:30"` — under 24
  hours old, and the numbers still reproduce byte-for-byte, so it is current rather than merely
  recent. AP #51 is not triggered.

Watch list read as a decision record (`AUDIT.md` step 6, AP #53): the functions table reads
**"None."** with the twenty former entries named in full for comparison
(`docs/automated-tests/RESULTS.md:113-134`); the files table carries four rows, and **not one is
dispositioned "accepted"** — three read "Already tracked as `A-2`" and one "Already tracked as
`KCD-30`" (`:140-143`). No entry is at risk of the three-consecutive-release shelf life.

Artifact audit against `automated-tests`:

- `tests/_kit/run-automated-tests.sh` present, vendored, `-rwxrwxrwx`,
  `file` → `Bourne-Again shell script, … executable`.
- `.gitattributes:19` → `*.sh   text eol=lf`, with the CRLF rationale at `:17-21`. Present.
- `docs/automated-tests/README.md` and `docs/automated-tests/RESULTS.md` both present.
- `docs/complexity.md` — **absent**, which is the compliant post-v2.19.0 state (the v2.19.0 finding
  is an addon that still *carries* one).

### 1.5 Vendored Ka0s-owned library drift — **NOT RUN**

Both diffs `library-stack-§7` requires were **not run**, because this audit is constrained to the
single repository `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD` and reading the sibling
`../LibKa0s` checkout was out of scope for the run. The commands not executed were:

```
$ diff -r ../LibKa0s/LibKa0s  ./libs/LibKa0s      # NOT RUN
$ diff -r ../LibKa0s/testkit  ./tests/_kit        # NOT RUN
```

**This check is therefore unverified, not passing.** What *can* be said from inside the repo:

- `ls libs/LibKa0s/` → `Core.lua  DebugLog.lua  LICENSE  LibKa0s.xml  Options.lua  OptionsScroll.lua
  OptionsWidgets.lua  Perf.lua  PerfPanel.lua  Slash.lua` — all **eight** module files
  `library-stack-§7` names across the five majors, plus the aggregate XML and the license. No file
  the ship folder is documented to carry is missing, so **AP #48 is not indicated** on the evidence
  available; a byte-level difference would still only show in the diff.
- The harness sits at `tests/_kit/`, not under `libs/` — `library-stack-§7` and `testing-§1` both
  require exactly that. `ls tests/_kit/` → `README.md  framework.lua  loader.lua  mock_base.lua
  run-automated-tests.sh`.
- The addon's own gate for this (`tests/test_vendor_sync.lua`) **printed PASS without looking** in
  this environment — see `KCD-43` and §1.2 — so its green is not a substitute.

---

## 2. Evidence per deviation

### KCD-30 — the kit is vendored but not consumed (`testing-§1`, `testing-§9`, AP #47)

- `tests/run.lua:14-15` — `dofile(root .. "/tests/wow_mock.lua")`, `dofile(root .. "/tests/loader.lua")`.
  Nothing under `tests/_kit/` is loaded by any file in `tests/`.
- `tests/run.lua:17-32` — `-- Micro-framework`, `local passed, failed = 0, 0`, the private
  `registry`/`currentSuite` pair and the `--list` flag parse.
- `tests/run.lua:39-55` — `local function test(name, fn)`: in list mode it records and returns; in
  run mode it calls `pcall(fn)` **at registration time**. `testing-§1`: "A runner that executes a
  case body at registration time and short-circuits it in list mode makes `--list` a second code
  path through the same file… An addon **MUST NOT** reintroduce that shape."
- `tests/run.lua:57-82` — the private `assertTrue`/`assertFalse`/`assertNil`/`assertEqual`/
  `assertError`/`assertNear` set. `:73-75` concedes the point: "Same name, signature and semantics as
  `tests/_kit/framework.lua`'s, so adopting the kit replaces this with an identical function".
- `tests/loader.lua:42` — `local toc = assert(io.open(root .. "/KickCD.toc", "r"))`, a private TOC
  reader where `testing-§9` requires `Loader.tocFiles`.
- `tests/loader.lua:93-94` — `local libFiles = (opts and opts.libFiles) or LIB_FILES`, a
  hand-maintained vendored-library list.
- `tests/wow_mock.lua` — 1066 lines (`wc -l`); `:573` — "Deliberately a VERBATIM port of
  `tests/_kit/mock_base.lua`'s builder".
- `tests/wow_mock.lua:789` — `local fh = io.open("KickCD.toc", "r")`, a second private TOC read.

### KCD-31 — host copies of library Options members (`options-ui-§1`, AP #47)

Host implementations, each assigned onto the instance:

- `settings/Panel.lua:281` — `function Helpers.LSMValues(mediaType)`; `:284-286` builds and returns a
  **table**; `:288-289` falls back to `out["Default"] = "Default"`.
- `settings/Panel.lua:341` — `Helpers.AttachTooltip = attachTooltip` (body `:315-340`).
- `settings/Panel.lua:394` — `Helpers.EnsureScroll = ensureScroll` (body from `:360`).
- `settings/Panel.lua:443` — `Helpers.AddSpacer = addSpacer` (body `:435-441`).

Library implementations of the same four:

- `libs/LibKa0s/Options.lua:502` — `function O.LSMValues(mediaType)` (returns the deferred closure
  `options-ui-§6` requires).
- `libs/LibKa0s/Options.lua:322` — `function O.EnsureScroll(ctx)`.
- `libs/LibKa0s/OptionsWidgets.lua:333` — `function O.AttachTooltip(widget, label, tooltip)`.
- `libs/LibKa0s/OptionsWidgets.lua:362` — `function O.AddSpacer(scroll, height)`.

The library's own makers reach them through the instance, so the host copies are what actually run:
`libs/LibKa0s/OptionsWidgets.lua:374`, `:379`, `:391`, `:405`, `:437`, `:450`, `:473`, `:480`,
`:487`, `:501`, `:508`, `:557`, `:565`, `:596`, `:607`, `:620`; `libs/LibKa0s/Options.lua:308-309`,
`:333-334`.

Call sites that change with the closure/table contract: `settings/Icons.lua:196`, `:220`;
`settings/Label.lua:147`; `settings/Castbar.lua:280`, `:401`, `:438`, `:463`, `:500`.

### KCD-32 — host copies of layout constants (`options-ui-§8`, AP #47)

- `settings/Panel.lua:300-306` — the comment quoting the rule: "options-ui-§8 is explicit that a host
  **MUST NOT** keep its own copies… it reads it off the instance (`Helpers.ROW_VSPACER`, …) rather
  than restating the number."
- `settings/Panel.lua:307` — `local PADDING_X = NS.Const.PANEL_PADDING_X` (declared in
  `core/Constants.lua`), restating `libs/LibKa0s/Options.lua:46` `PADDING_X = 16`.
- `settings/Panel.lua:426` — `local ROW_VSPACER = 8`, restating `libs/LibKa0s/Options.lua:56`
  `ROW_VSPACER = 8`.
- `settings/Panel.lua:430` — `Helpers.ROW_VSPACER = ROW_VSPACER`, overwriting the library's published
  value at `libs/LibKa0s/Options.lua:176` (`O.ROW_VSPACER = L.ROW_VSPACER`).
- Compliant counter-example in the same repo: `settings/Panel_Render.lua:20` —
  `local ROW_VSPACER = Helpers.ROW_VSPACER`, and `settings/Panel_Widgets.lua:48-50`, which reads it
  off the instance and cites the rule.

### KCD-33 — a second secret-safe stringifier (`events-frames-taint-§8`, AP #35, AP #47)

- `core/Compat.lua:361` — "Renderers by Lua type, so `safeRender` below is one lookup instead of a…"
- `core/Compat.lua:373-375` — `local function safeRender(value)` / `if _G.issecretvalue and
  _G.issecretvalue(value) then` — detection by `issecretvalue`, not the mandated `table.concat`
  probe.
- `core/Compat.lua:387-389` — `local secret = _G.issecretvalue and _G.issecretvalue(value) or false`
  … `safeRender(value)`.
- `core/Compat.lua:446` — `local out = (NS.Util and NS.Util.print) or _G.print`.
- The sanctioned copies, for contrast: `core/CoreSetup.lua:76` (`local function probeConcat(v) return
  table.concat({ v }) end`), `:78-80` `NS.IsConcatSafe`, `:82-87` `NS.SafeToString` — inside the
  `if not lib then` branch at `:69`, which `events-frames-taint-§8` names as "the **only** sanctioned
  place a second copy may exist". The library path is `core/CoreSetup.lua:130-131`
  (`NS.IsConcatSafe = lib.IsConcatSafe`, `NS.SafeToString = lib.SafeToString`).

### KCD-34 — no offline scenario runner (`performance-§9`, `-§2`, `testing-§7`)

- `ls tests/perf.lua` → no such file. The suite listing in §1.2 contains no `perf` scenarios.
- `docs/automated-tests/20260804-233245/manifest.json` —
  `"perf": {"status":"skip","skipReason":"no tests/perf.lua — this addon ships no offline scenarios","scenarios":0}`.
  Same on both earlier bundles.
- `docs/automated-tests/RESULTS.md:61-66` — "This addon ships no `tests/perf.lua`… the record says
  **nothing** about the addon's runtime cost, and `performance-§9`'s zero-overhead evidence… does not
  exist for it."
- The bracket the scenario would cover is named in-repo: `core/PerfSetup.lua:26-31` — "The measurable
  cost lives in `iconApply`… roughly 100 calls/s with a seven-spell list mid-fight".

### KCD-35 — two required topic-detail docs absent (`documentation-§3`, `performance-§8`)

- `ls docs/performance.md` → no such file. `ls docs/perf-runs/` → no such directory.
- Present, for contrast: `docs/test-cases.md`, `docs/automated-tests/README.md`,
  `docs/automated-tests/RESULTS.md` — three of the five required.

### KCD-37 — angle-bracket placeholder in the README (`documentation-§1`)

- `README.md:191` — "One setting: `` `/kcd reset <setting>` ``."
- Compliant siblings in the same document: `README.md:73-75` use the bare form.
- Protected HTML that must not be swept: `README.md:210`, `:211` (`<br>` inside Version History
  cells).

### KCD-38 — six sends of one bus message (`architecture-§4`, AP #17)

```
$ grep -rn 'SendMessage("Ka0s_KickCD_CONFIG_CHANGED"' core modules settings
core/KickCD.lua      -> { section = "general" }
core/KickCD.lua      -> { section = "spells" }
modules/Castbar.lua  -> { section = "castbar" }
modules/IconGrid.lua -> { section = "general" }
settings/Spells.lua  -> { section = "spells" }
settings/Panel.lua   -> { section = section }
```

- `docs/ARCHITECTURE.md:118` documents the five senders honestly: "Panel `Helpers.Set`,
  `core/KickCD.lua`, Spells editor, IconGrid / Castbar `OnDragStop`, `Helpers.RenderUnitPanel`".
- The natural single owner already exists: `settings/Panel.lua:75`
  `function Helpers.FireConfigChanged(section)`, called at `:121`.
- Every other message has a single owning file: `Ka0s_KickCD_SPELL_STATE` ×3 in
  `modules/Cooldowns.lua`, `Ka0s_KickCD_PROFILE_CHANGED` ×2 in `core/Database.lua`,
  `Ka0s_KickCD_GRID_LAYOUT` ×2 in `modules/IconGrid.lua`, `Ka0s_KickCD_COMBAT_STATE` ×1 in
  `core/State.lua`.

### KCD-40 — private page registry and category bootstrap (`options-ui-§5`, `-§1`, AP #47)

Host-side:

- `settings/Panel.lua:546` — `function NS.Settings.RegisterTab(key, builder)`; `:548` stores into
  `NS.Settings.builders[key]`; `:550-553` eagerly builds if the main category already exists.
- `settings/Panel.lua:554` — `local function RegisterPanel()`; `:559-563` guards on
  `Settings.RegisterCanvasLayoutCategory`; `:576` builds the main panel through the library's
  `Helpers.CreatePanel`; `:589` — `local main = Settings.RegisterCanvasLayoutCategory(mainCtx.panel,
  L["Ka0s KickCD"])`; `:590` `Settings.RegisterAddOnCategory(main)`; `:594-603` iterates
  `NS.Settings.order` and calls each builder.
- `settings/Panel.lua:605-616` — `NS.Settings.Register = RegisterPanel` and the private
  `PLAYER_LOGIN`/`ADDON_LOADED` bootstrap frame.
- Page tails, all six on the private registry: `settings/General.lua:182-183`,
  `settings/Icons.lua:416-417`, `settings/Castbar.lua:559-560`, `settings/Label.lua:192-193`,
  `settings/Spells.lua:1157-1158`, `settings/Profiles.lua:65-66`.
- Each page then calls `Settings.RegisterCanvasLayoutSubcategory` itself:
  `settings/General.lua:178`, `settings/Icons.lua:412`, `settings/Castbar.lua:555`,
  `settings/Label.lua:188`, `settings/Spells.lua:1154`, `settings/Profiles.lua:61`.

Library-side, wired and unused:

- `settings/OptionsSetup.lua:228` — `NS.RegisterOptionsPage = function(key, name, builder)
  Helpers.RegisterOptionsPage(key, name, builder) end`; `:229` `NS.CreateOptionsPanel`;
  `:230` `NS.OpenOptionsPanel`; `:234` `NS.RefreshOptionsPanel`.
- `libs/LibKa0s/Options.lua:536` `function O.RegisterOptionsPage(key, name, builder)`;
  `:569` `mainCategory = Settings.RegisterCanvasLayoutCategory(mainCtx.panel, d.parentTitle)`;
  `:576` `function O.CreateOptionsPanel()`; `:636` `function O.OpenOptionsPanel()`.
- Callers of the forwarders, repo-wide:
  `grep -rn "OpenOptionsPanel\|CreateOptionsPanel\|RegisterOptionsPage" core settings modules tests`
  → `tests/test_coresetup.lua:354`, `tests/test_options_panel.lua:342` only. Production callers:
  **none**.

Second open path:

- `core/KickCD.lua:154` — the `config` verb calls `NS:OpenSettings()`.
- `core/KickCD.lua:775-790` — `function NS:OpenSettings(input)`; `:776-780` the combat gate through
  `inCombat` (`:735-739`, `InCombatLockdown()` plus `State.inCombat`); `:757`
  `Settings.OpenToCategory(main:GetID())` inside `openRegisteredPanel`. The gate is present, so
  `options-ui-§2` holds; the duplication is the finding.

### KCD-41 — profile defaults outside `defaults/Profile.lua` (`savedvariables-§2`)

- `ls defaults/` → `Spells.lua` only.
- `core/Database.lua:239` — `local DEFAULT_PROFILE = {` … through `:303`; `:292`
  `profile = DEFAULT_PROFILE` inside `local DEFAULTS = {` (`:291`); `:304`
  `NS.DEFAULT_PROFILE = DEFAULT_PROFILE`; `:820` `local db = AceDB:New("KickCDDB", DEFAULTS, true)`.
- The second hardcoded copy: `modules/Castbar.lua:566-590`, including `:573` and `:583`
  `nameTextColor = { 1, 1, 1, 1 }` — positional, where `core/Database.lua:203` and `:213` store
  `nameTextColor = { r = 1, g = 1, b = 1, a = 1 }`.

### KCD-42 — keyed colors read positionally (`options-ui-§1`, `testing-§4`)

- Stored shape (keyed): `core/Database.lua:203`, `:213` — `nameTextColor = { r = 1, g = 1, b = 1, a = 1 }`.
- Schema rows: `settings/Castbar.lua:419` and `:481` — `type = "color", hasAlpha = true` on
  `units.<unit>.castbar.{interruptible,uninterruptible}.nameTextColor`.
- The defect: `modules/Castbar.lua:726-729` —
  ```lua
  local function rgba(c)
      c = c or WHITE
      return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
  end
  ```
  With a keyed table, `c[1]`..`c[4]` are all nil, so every channel falls to `1` — white.
- Consumers: `modules/Castbar.lua:740` `frame.nameText:SetTextColor(rgba(intCfg.nameTextColor))`;
  `:747-748` `local ur, ug, ub, ua = rgba(unintCfg.nameTextColor)` /
  `local ir, ig, ib, ia = rgba(intCfg.nameTextColor)`.
- The correct decoder, used by every other color read in the addon:
  `core/Util.lua:22-28` `function Util.Unpack(c)` — `if c.r ~= nil then return c.r or 1, …` with the
  positional arm as the fallback. Referenced at `modules/Castbar.lua:228-231` and
  `modules/Castbar_Debug.lua:19`.
- Coverage: `grep -rn "nameTextColor\|rgba" tests/` → no match. `testing-§4` requires a covering test
  for the behavior; there is none.

### KCD-43 — two tests that cannot fail (`testing-§12`, `testing-§11`)

- `tests/test_vendor_sync.lua:110-116` —
  ```lua
  local function siblingTag()
      if not gitShow("HEAD:LibKa0s/Core.lua") then return nil end
  ```
  and `:52-59`'s `gitOut`, which returns `nil` when the `git -C "../LibKa0s"` pipe yields nothing.
- `tests/test_vendor_sync.lua:138-142` —
  ```lua
  test("libs/LibKa0s is the LibKa0s release the README says this addon bundles", function()
      local tag = siblingTag()
      if not tag then return end
  ```
- `tests/test_vendor_sync.lua:144-149` — the same shape for `tests/_kit`.
- `:107-109` claims the skip "is said in the case name rather than hidden" — the two case names
  (`:138`, `:144`) are unconditional positive assertions and say nothing about a skip.
- Observed today: §1.2's run printed `PASS` for both, and §1.5 records that the sibling repo was
  never read by this audit. The two states are indistinguishable from the output.

### KCD-44 — the release gate is unstated (`automated-tests-§3`, `documentation-§5`)

- `docs/testing.md:84-89` — the suite/gates table: `perf` → "no — recorded only", `complexity` →
  "no — recorded only", with no release column.
- `docs/testing.md:91-94` — "**`perf` and `complexity` never fail a run.**… They contribute `amber`".
- `docs/testing.md:99-100` — "**At release, not at commit.** A full bundle is produced as part of
  every version bump, before the tag… Commits are gated on lint + tests only." The bundle is
  described; the **gate on it** is not.
- `CLAUDE.md:75` — "**Complexity — recorded, never a gate.**" No checkpoint named.
- What the standard now says (`automated-tests-§3`, *The release gate*): "**MUST NOT** cut a release…
  unless the release run's `manifest.json` shows **all four** suites at `pass`, and
  `suites.complexity.warnings` at **0**" and "**MUST** treat a **skip** as a gate that did **not**
  pass", with the narrow no-`tests/perf.lua` exception that "**MUST** be stated as such in the release
  notes".
- Current manifest state: `docs/automated-tests/20260804-233245/manifest.json` —
  `"perf": {"status": "skip", …}`, `"complexity": {"status":"pass","warnings":0,"maxCcn":15}`,
  `"verdict": "green"`. Green as a *run*; not a passing *release gate*.
- `README.md:206-211` (Version History) carries no statement of the perf exception for 1.2.1.

### KCD-45 — the DebugLog stub re-implements the line format (`debug-logging-§7`, `-§3`)

- `core/DebugLogSetup.lua:92-96` —
  ```lua
  -- Plain text, deliberately: the shape is recognizable, the colors are
  -- not reproduced, and nothing downstream parses these.
  FormatPlain     = function(ts, tag, msg)
      return tostring(ts) .. " | [" .. tostring(tag or "") .. "] " .. tostring(msg)
  end,
  ```
- `core/DebugLogSetup.lua:114` — `D.FormatColored = D.FormatPlain`.
- `debug-logging-§3` specifies the very shape being reproduced: "Every line the library renders
  follows `<HH:MM:SS> | [<Tag>] <content>`", and the addon "**MUST NOT** redefine, wrap, or hand-copy
  those formatters".
- `debug-logging-§7`: "The stub **MUST NOT** re-implement the formatters or the line format (§3)."
- The file's comment at `:58-62` argues the point and gets the color half right; the line-format half
  is the finding.

### KCD-46 — the castbar dump bypasses the shared seam (`events-frames-taint-§8`, `debug-logging-§4`/`-§12`)

- `modules/Castbar_Debug.lua:125` — `local print = NS.Util and NS.Util.print or _G.print`.
- Pre-concatenated call sites (all 20 lines in the file build with `..` before the printer), e.g.
  `:35` `print("    plain value = " .. tostring(v))`; `:56` `print("  no " .. inst.unit)`;
  `:60`; `:82` `print("  current.isChannel = " .. tostring(current.isChannel))`; `:85`;
  `:90-93`; `:102`; `:105`; `:114-115`; `:126`.
- `events-frames-taint-§8` on call sites: they "**MUST NOT**: call the global `print()` directly…
  [or] feed chat/debug args through `..` / `tostring` / `table.concat` before the shared printer".
- The dump is chat-bound: `modules/Castbar_Debug.lua:123-135` `function Castbar:DebugDump(unit)`,
  reached from `/kcd debug castbar` (`:6`, `core/KickCD.lua:178`).
- The compliant pattern already exists in the repo for exactly this shape:
  `core/PerfSetup.lua:169-170` — `if NS.DebugLog and NS.DebugLog.Add then NS.DebugLog:Add("Perf",
  line)`, and `:182-183` reveals the console once, per `debug-logging-§12`.
- Second `_G.print` fallback (covered by `KCD-33`): `core/Compat.lua:446`.

### KCD-47 — British spelling in authored docs prose (`localization-§5`, AP #46)

```
$ grep -rniE "colour|behaviour|grey|centre|cancelled|-ise" docs README.md CLAUDE.md DEPENDENCIES.md
docs/superpowers/plans/2026-08-04-ccn-elimination.md:51  colours … behaviour
docs/superpowers/plans/2026-08-04-ccn-elimination.md:53  colour (x2)
docs/superpowers/plans/2026-08-04-ccn-elimination.md:57  Colours
docs/superpowers/plans/2026-08-04-ccn-elimination.md:121 Colour
docs/superpowers/plans/2026-08-04-ccn-elimination.md:149 colour
docs/automated-tests/20260804-182144/ANALYSIS.md:72      behaviour        [FROZEN — do not edit]
```

`README.md`, `CLAUDE.md`, `DEPENDENCIES.md`, the `docs/` trio and every source file are clean.
`localization-§5` scopes the MUST to "prose in `README.md` and every file under `docs/`".

### KCD-48 — an unguarded direct SavedVariables write (`options-ui-§1`, `slash-commands-§3`)

- `settings/Slash.lua:103` — `function NS.Slash.GateHint(row)`.
- `:114` — `local parent, key = H.Resolve(row.valueGate)`.
- `:118-122` —
  ```lua
      if candidate ~= gateVal then
          parent[key] = candidate
          local alt = allowedKeys(row)
          parent[key] = gateVal
  ```
  `allowedKeys(row)` calls the row's `values()`; a raise between the two assignments leaves
  `parent[key]` at `candidate` permanently, with no `onChange` and no panel refresh.
- The seam it bypasses: `settings/Slash.lua:302-306` — `set = function(path, v) … H.SetAndRefresh(path, v)`,
  described at `:298-301` as "The single write seam… the one path that fires CONFIG_CHANGED with the
  row's section, runs the row's `onChange` and refreshes any open panel."
- The documented intent: `settings/Slash.lua:98-102` — "the swap is transient — one call between
  mutate and restore, with no message-bus dispatch in between." The transience is the design; the
  missing `pcall` is the gap.

### KCD-49 — brackets not closed on early returns (`performance-§3`, `testing-§8`)

- `modules/IconGrid_Render.lua:825-836` —
  ```lua
  local function _tickAllTextIcons()
      local __t0 = Perf.on and debugprofilestop()
      …
      if next(_textIcons) == nil then
          …
          return                       -- cdText bracket never closed
      end
  ```
- `modules/Castbar.lua:689-697` —
  ```lua
  local function onUpdate(inst)
      local __t0 = Perf.on and debugprofilestop()
      …
      if not d then
          frame:SetScript("OnUpdate", nil)
          return                       -- castTick bracket never closed
      end
  ```
- The correct shape, in this repo: `modules/Cooldowns.lua:190-202` — the bracket opens at `:190` and
  **both** exits close it (`:194`, `:201`).
- The cost of getting it wrong, recorded in this repo: `core/PerfSetup.lua:107-113` — "spellPoll
  totaled 125.02 ms of which its only declared child accounted for 51.14, leaving 73.9 ms — the
  largest single cost in the addon — attributed to nothing at all."
- The pin that covers only one function: `tests/test_perfsetup.lua:551-589`.
- The comment inaccuracy: `core/PerfSetup.lua:108` "All four of PollSpell's exits are instrumented
  now" vs `modules/Cooldowns.lua:179` "TWO exits, and both are instrumented on purpose", with the two
  at `:194` and `:201`.

---

## 3. Compliance evidence (claims made in `01_CURRENT_STATE.md`)

| Claim | Evidence |
|---|---|
| TOC field order and required fields | `KickCD.toc:1-13` in the exact `toc-file-§1` order; `:12` `X-Standard`; `:13` `X-Curse-Project-ID: 1530802` |
| Single Retail Interface, badge in lockstep | `KickCD.toc:1` `## Interface: 120007`; `README.md:3` `WoW-Midnight_12.0.7-purple` |
| Two SavedVariables globals, no third | `KickCD.toc:7`; `.luacheckrc` `globals` = `KickCDDB`, `StaticPopupDialogs`, `KickCDPerfDB`, each commented |
| `LibKa0s.xml` listed once, after Ace3 | `KickCD.toc:25`, inside `# Libraries` (`:16`), after the AceGUI/AceConfig XML lines |
| No addon-authored `embeds.xml` | `KickCD.toc:17-28` lists each library directly; no aggregate beyond each library's own `.xml` |
| TOC section headers in load order | `KickCD.toc:16` Libraries, `:30` Locales, `:33` Core, `:45` Defaults, `:48` Modules, `:57` Settings |
| Namespace bootstrap, no `_G` table | `local addonName, NS = ...` heads every file; `CLAUDE.md:56` "there is no `_G.KickCD`" |
| AceConsole `:Print` clobber avoided | `core/CoreSetup.lua:38-46` (the rationale), `:135` `Util.print = printer.Print` |
| Bus receivers on their own targets | `core/KickCD.lua:46` `function NS.NewBusTarget()`; `settings/Spells.lua:1104-1105`; `docs/ARCHITECTURE.md:124` |
| Single write seam shared by panel and CLI | `settings/Panel.lua:116` `Helpers.Set`; `settings/Slash.lua:302-306`, `:311-320` both on `SetAndRefresh` |
| Boot-time schema validation | `settings/Panel.lua:192` `Helpers.ValidateSchema`, called at `:569` |
| Core seam publishes the library's functions | `core/CoreSetup.lua:130-131`; the sanctioned fallback at `:69-98` |
| DebugLog descriptor complete + bare sink | `core/DebugLogSetup.lua:120-164`; `:170` `NS.Debug = NS.DebugLog.Debug` |
| DebugLog stub answers every member reached | Call sites: `core/KickCD.lua:213`, `:218`, `:223`, `:229`, `:258` (`Toggle`, `SetEnabled`); `core/PerfSetup.lua:169-170` (`Add`), `:182-183` (`Show`, `IsShown`), `:209-210` (`MakeCloseButton`); `settings/General.lua:156-159` (`IsShown`, `Show`, `Hide`). Stub: `core/DebugLogSetup.lua:74-113` covers all of them plus the buffer introspection the suites drive |
| Monospace font shipped + registered | `media/fonts/JetBrainsMono-Regular.ttf` with `JetBrainsMono-OFL.txt`; `core/DebugLogSetup.lua:37-43` |
| Perf descriptor: buckets, nesting, SV, version | `core/PerfSetup.lua:70`, `:84-87`, `:96-105` (eight buckets, three `within` declarations) |
| Perf stub covers every member reached | `core/PerfSetup.lua:43-55` (`on`, `suspended`, `Note`, `OnCommand`) against the `Perf.on`/`Perf.Note` bracket sites and `core/KickCD.lua:183` |
| Options stub is load-completing by measurement | `settings/OptionsSetup.lua:150-168` (the measured zero-member finding), `:169-217` (the stub), pinned by `tests/test_options_panel.lua` |
| Slash: one dispatcher, host `COMMANDS`, reserved verbs | `settings/Slash.lua:286-345`; `core/KickCD.lua:148-195`, incl. `version` `:151`, `config` `:154`, `debug` `:178`, `perf` `:183` |
| Slash stub carries every member | `settings/Slash.lua:206-266` |
| Cyan prefix, single printer | `NS.PREFIX` = `\|cff00ffff[KCD]\|r`; 16 `NS.Util.print(` call sites across `core/`, `modules/`, `settings/` |
| Preview mode present and unlock-driven | `modules/Castbar.lua:426-431`, `:733` `applyPreviewVisuals`, `:793`, `:835-839` |
| `.pkgmeta` correct | `package-as: KickCD`, no `externals:`, ignores `docs`, `tests`, `_dev`, `.luacheckrc`, `.gitignore`, `.gitattributes`, `*.bak` |
| `.luacheckrc` has `debugprofilestop` with the cited reason | `.luacheckrc` `read_globals`, comment naming `performance-§2` |
| Root doc set is exactly three plus LICENSE | `ls` root → `CLAUDE.md`, `DEPENDENCIES.md`, `README.md`, `LICENSE`, `KickCD.toc`, dotfiles, folders |
| `docs/` trio present | `docs/ARCHITECTURE.md`, `docs/testing.md`, `docs/smoke-tests.md` |
| Three-place standards reference complete | `KickCD.toc:12`; `README.md:6`; `CLAUDE.md:7` `## Standards compliance (read first)` |
| README canonical order | `README.md` headings at `:1`, `:20`, `:35`, `:60`, `:62`, `:86`, `:103`, `:161`, `:178`, `:202`, `:206` |
| `## What's new` rolled forward | `README.md:20` `## What's new in 1.2.1`; top Version History row `:210` is 1.2.1 |
| No retired/forbidden docs | no `docs/complexity.md`, no `docs/agent-context.md`, no `TODO.md` |
| `DEPENDENCIES.md` splits the three groups, with pipx | `DEPENDENCIES.md:14` Runtime, `:32` Development, `:97` Release/assets; `:56` "lizard — via pipx, NOT pip"; `:79` Verification |
| Bundles frozen, cumulative, correctly named | `docs/automated-tests/{20260804-182144,20260804-214315,20260804-233245}/`, each with `manifest.json`, `ANALYSIS.md`, `lint.txt`, `tests.txt`, `test-cases.md`, `complexity.txt` |
| `RESULTS.md` single path, two watch tables, four standing sections | `docs/automated-tests/RESULTS.md:3-4` (the overwrite note), `:16-19` (the trend rows), `:26`/`:45`/`:59`/`:68` (per-suite prose), `:111` and `:137` (the two tables with header rows) |
| Degraded path exercised by a real load | `tests/run.lua:97-99` documents `{ libFiles = {} }`, used by the stub suites |

## 4. Not verified

- **`diff -r ../LibKa0s/LibKa0s ./libs/LibKa0s`** — NOT RUN (single-repo scope). Unverified.
- **`diff -r ../LibKa0s/testkit ./tests/_kit`** — NOT RUN (single-repo scope). Unverified.
- **`make test`** — no `Makefile` in the repo; not applicable.
- **Falsifiability of individual cases** (`testing-§12`) — mutation testing leaves no artifact and is
  not mechanically auditable, so it is recorded as **unverified**, not as a deviation, per the
  section's own instruction. The two cases in `KCD-43` are the exception: their unfalsifiability is
  visible in the source, so they are recorded as a deviation.
