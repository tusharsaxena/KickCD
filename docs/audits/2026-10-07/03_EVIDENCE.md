# KickCD — Evidence (2026-10-07)

Every command below was run from the repo root (`/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD`)
at HEAD `43aa263`, with a clean tree. Every `file:line` was re-read before it was written here, and
the cited text is quoted beside it. **The default census scope is the one `layout-§1` names:**
`git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`. That is 127 files, `tests/` included and
the vendored payloads excluded. Any other scope is stated where it is used.

---

## E0 — Standard resolution

```
curl -fsSL $RAW/AUDIT.md                 -> 1156 lines
curl -fsSL $RAW/standards/STANDARDS.md   -> line 1: "# Ka0s WoW Addon Standard (v2.76.1, 2026-10-07)"
Sections list -> 27 files under standards/standards/, all fetched non-empty
curl -fsSL $RAW/standards/ADDONS.md      -> :23 "| Ka0s KickCD | [`../../KickCD/`](../../KickCD/) | https://github.com/tusharsaxena/KickCD | Enabled · Locked |"
diff -q <fetched AUDIT.md> ../WowAddonStandards/AUDIT.md   -> (no output)
dev-copilot-profile -> profile=wow kind=addon name=KickCD reason=toc:## Interface
```

## E1 — Re-vendor bundles (`KICKCD-C-01`)

The command is `AUDIT.md` step 4's, run verbatim under `bash`. Scope: every commit touching
`libs/LibKa0s` or `tests/_kit` since the store's first bundle (`2026-08-25 00:00`), and every folder
under `docs/revendor/`.

```
horizon=2026-08-25
vendored 52: v1.15.0 … v1.68.0 v1.68.1 v1.69.0 v1.70.0
recorded 50: v1.15.0 … v1.68.0 v1.68.1
UNRECORDED: v1.69.0 v1.70.0
count 2
```

- `git show --stat da8a8b8` reads "chore: re-vendor LibKa0s v1.69.0 (kit 37; adds the line chart widget)". It touches
  `CLAUDE.md`, `libs/LibKa0s/LibKa0s.xml`, `libs/LibKa0s/WidgetsLineChart.lua` and `tests/_kit/{README.md,framework.lua,mock_base.lua,mock_lines.lua}`.
- `git show --stat 9d4a10b` reads "chore: re-vendor LibKa0s v1.70.0". It touches `CLAUDE.md`,
  `libs/LibKa0s/LibKa0s.xml`, `libs/LibKa0s/WidgetsAutocomplete.lua` and `libs/LibKa0s/WidgetsLineChart.lua`.
- `ls docs/revendor` ends at `2026-10-04-v1.68.1` (`01_DELTA.md`, `02_CANDIDATES.md`, `05_SUMMARY.md`).
- The previous run's 25-tag backlog is covered by `docs/revendor/2026-09-24-v1.16.0-v1.54.2/`. The
  recorded side above includes every tag from v1.18.0 to v1.53.0.

## E2 — Vendored payload and provenance

```
git -C ../LibKa0s rev-parse v1.70.0 -> 26f441a25ad7a808ca612eecec512808b9fa4c38
git -C ../LibKa0s archive v1.70.0 LibKa0s testkit | tar -x -C <scratch>
diff -r <scratch>/LibKa0s libs/LibKa0s   -> (no output)  exit 0
diff -r <scratch>/testkit tests/_kit     -> (no output)  exit 0
grep -n 'Bundles \[LibKa0s\]' CLAUDE.md  -> 42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.70.0 (MIT).
grep -n 'Bundles \[LibKa0s\]' README.md  -> (none)
grep -nE '^## (Libraries|Bundled libraries|Libraries and credits|Credits and libraries|Credits and bundled libraries)' README.md -> (none)
grep -n 'WoW_Addon_Standard' README.md   -> 6:![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
grep -nE '!\[[^]]*\]\(media/logos|<img' README.md -> (none)
numbered-list grep outside fences (awk over README.md) -> (none)
tests/_kit/framework.lua:20  "Kit.VERSION = 37"
```

The diff ran against the **tag** named by `CLAUDE.md:42`, not against the sibling's `HEAD`.

## E3 — Stale inventories (`KICKCD-C-08`)

Scope for (1) and (2): the 50 shipped authored files, `git ls-files '*.lua' | grep -vE '^(libs/|tests/)'`.

```
$ git ls-files '*.lua' | grep -vE '^(libs/|tests/)' | xargs grep -l '^local addonName, NS = \.\.\.'
core/Constants.lua core/CoreSetup.lua core/DebugLogSetup.lua core/EnvSetup.lua core/LauncherSetup.lua
core/LifecycleSetup.lua core/MediaSetup.lua core/PerfSetup.lua settings/OptionsSetup.lua      -> 9
$ ... | xargs grep -l '^local _, NS = \.\.\.' | wc -l                                         -> 41
$ git ls-files '*.lua' | grep -vE '^(libs/|tests/)' | wc -l                                    -> 50
```

- `docs/ARCHITECTURE.md:80` reads "it. Eight do, each handing the addon FOLDER name to a vendored LibKa0s payload that cannot work".
  `:83` reads "`core/LifecycleSetup.lua` and `core/PerfSetup.lua`. The other thirty-six write `local _, NS = ...`:".
- `settings/OptionsSetup.lua:1` reads `local addonName, NS = ...`. `:157` reads `addonName     = addonName,`.
- `.luacheckrc:25` reads "--     Eight files in this addon do read it -- Constants, CoreSetup, DebugLogSetup, EnvSetup,".
  `:29` reads "--     core/PoolSetup.lua already spelt it; thirty-three authored files open that way today."
- `docs/compat-layer.md:34` reads "| `NS.State.SetInCombat(v)` | `core/State.lua` | The single write seam for the `NS.State.inCombat` flag. Called only by that file's bootstrap `CreateFrame` on `PLAYER_REGEN_DIS…".
  Against that, `core/State.lua:161` reads `local boot = {}` and `:162` reads `LibStub("AceEvent-3.0"):Embed(boot)`. `docs/ARCHITECTURE.md:100` reads "… `core/State.lua`'s combat listener — an AceEvent target (`LibStub("AceEvent-3.0"):Embed`, …".
- `.pkgmeta:22` reads "# Tracked, and the only entries here that change a download. Seven files,". `:23` reads "# 7.5M -- the largest such payload in the collection, and most of it the".
  ```
  $ git ls-files media/screenshots            -> kickcd.image.01.addon.png, kickcd.video.01.gif   (2)
  $ git ls-files media/screenshots | xargs du -cb | tail -1   -> 4812069 total
  $ git ls-tree -r --name-only db1d396 media/screenshots      -> 7 files (when the comment was written)
  ```
- **Inventories checked and found correct** (no finding): 19 `COMMANDS` verbs (`core/KickCD.lua:231-376`)
  against `docs/ARCHITECTURE.md:291`; 8 Compat shims (`grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.' core/Compat.lua`
  → `8`) against `:293`; 5 `NS.MSG` messages against `:294`; 12 diagnostic sections
  (`modules/Diagnostics.lua:261-272`) against `:297`; 14 consumed majors (the `LibStub("LibKa0s-…")` sweep) against `:118`.

## E4 — Bare `§N` citations (`KICKCD-C-15`)

Scope: tracked `*.lua` and `*.md`, **excluding** `libs/`, `tests/_kit/` and the frozen stores
(`docs/audits/`, `docs/reviews/`, `docs/revendor/`, `docs/superpowers/`, the dated subfolders of
`docs/automated-tests/` and `docs/perf-analysis/`). That is 152 files. `tests/` and the live `docs/`
pages are **in** scope.

```
$ git ls-files '*.lua' '*.md' | grep -vE '^(libs/|tests/_kit/|docs/audits/|docs/reviews/|docs/revendor/|docs/superpowers/|docs/automated-tests/[0-9]|docs/perf-analysis/[0-9])' \
    | xargs grep -nP '(?<![A-Za-z0-9_-])§[0-9]+' | grep -vP '[a-z]-§[0-9]+' | cut -d: -f1 | sort | uniq -c
      2 docs/settings-panel.md
      2 docs/slash-dispatch.md
     75 docs/smoke-tests.md
     12 tests/test_flow_traces.lua
      1 tests/test_library_lines.lua
```

**Excluded with reason:** the 75 hits in `docs/smoke-tests.md` are that document's own retired section
numbers, not standard citations. For example, `:988` reads "to KC-S11, the old `§36`, …" and `:1001`
reads "| INSTALL-1 – 4 | §1 L65 – 66, L70 – 71 | No result recorded |". **Counted: 17.**

- `tests/test_flow_traces.lua:28` reads "-- folding does not satisfy §9, so a folded repeat still has to fail them."
  `:52` reads "-- §9 quiet steady state: SPELLS_CHANGED fires several times at login and every".
  `:68` reads "-- §8: the missing-icon answer. …". The same `§8`/`§9` shorthand appears at `:83`, `:110`, `:133`,
  `:145`, `:216`, `:228`, `:258`, `:275` and `:318`. The file qualifies it once, at `:1` ("debug-logging-§8 flow traces …")
  and `:22`.
- `tests/test_library_lines.lua:97` reads "-- §8 diagnosis: a player who says "it stopped working" with the addon".
- `docs/settings-panel.md:62` reads "Both would be legitimate `subgroup` candidates on a reading of §7 that counts widget types …". The qualified form is at `:47` (`options-ui-§7`).
- `docs/settings-panel.md:203` reads "It is also the page's **only** picker, which is the other half of `§14`: …".
- `docs/slash-dispatch.md:70` reads "§7 keeps AceDB's callbacks alive), and the end of **`NS:OnEnable`**, …".
- `docs/slash-dispatch.md:97` reads "**Nothing is held pending for `PLAYER_REGEN_ENABLED`.** §7 permits a disabled addon to keep exactly".
- `standards/STANDARDS.md` (*Reading this document*) reads "This is the **only** cross-reference form".
- No `.lua` file outside `tests/` matches. The previous run's code-comment sites are gone.

## E5 — Schema-version constant (`KICKCD-D-01`)

```
$ git grep -n 'SCHEMA_VERSION' -- core defaults settings modules     -> (no output)
```

- `core/Database.lua:36` reads `local CURRENT_DB_VERSION = 5`. `:39` reads `Database.CURRENT_DB_VERSION = CURRENT_DB_VERSION`.
- `core/Database.lua:87` reads `schemaVersion = 0,`, which is compliant.
- `core/Database_Migrations.lua:321-329` is `local migrations = { … [1] … [4] = function(db) NS.Database:MigrateFontFlags(db) end, }`. The highest `to` is 5.
- `core/Database_Migrations.lua:385` reads `local ok, err = pcall(step, self.db)`. `:390` reads `g.schemaVersion = v + 1`. The runner owns the stamp, which is compliant.
- The rule, fetched `savedvariables.md:57-59`, reads "**MUST** hold the runner's target in `NS.SCHEMA_VERSION`, equal to the highest step's `to`. The defaults value **MUST** stay `0` …".

## E6 — Decline contradicted, kit-folded total (`KICKCD-D-02`, `KICKCD-D-03`)

- `gh issue list` shows #11 `CLOSED ['state:will-not-do','severity:low']` "Adopt LibKa0s `RenderGrid` as a second consumer for KickCD's settings lists".
  `gh issue view 11 --json comments` returns no comments.
- `settings/Spells.lua:615` reads "--- Paint the rows through H.RenderGrid, and hand each one to the reorder controller."
- `settings/General.lua:351` reads "H.RenderGrid(ctxRef, {".
- #10 reads `CLOSED ['enhancement','state:done']` "Adopt RenderGrid for the spell-list editor — blocked on two LibKa0s gaps". Commit `e0da04c` is "GI-KC-11: the Spells list renders through H.RenderGrid with no gap (KickCD#10)".
- `docs/test-cases.md:1620` reads `| **Total** | **1303** |`. `:1524` reads "- diagnostics contract: an addon that opts out lands the report and leaves logging off (skipped: this addon keeps the default …)".
  `:3-5` reads "The `## Totals` table below is the **authoritative pass count** — the README test badge and any count quoted in the docs must agree with it."
- `README.md:7` reads `![Tests](https://img.shields.io/badge/Tests-1302%2F1302_passing-green)`.
- `ka0s-bounded lua tests/run.lua --list > <scratch>; diff docs/test-cases.md <scratch>` prints nothing, exit 0. The file is current kit output.

## E7 — Complexity and the record (`KICKCD-B-04`)

```
$ which lizard -> /home/tushar/.local/bin/lizard
$ ~/.claude/dev-copilot/bin/ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle
KickCD 1.4.0 — automated tests — 20261007-154928
  complexity  pass  — 0 warnings (fun rate 0.00), 25917 NLOC / 3580 funcs, avg NLOC 6.8, avg CCN 2.1 (max 15), avg tokens 54.6 (recorded, non-gating)
  verdict: green
  record:  newest bundle 20260927-030444 measured bcf9e51, 81 commit(s) behind HEAD — its figures describe a tree this one is no longer
EXIT 0
$ git rev-list --count bcf9e51..HEAD -> 81
$ grep -c blindFiles docs/automated-tests/20260927-030444/manifest.json -> 0
$ git status --short -> (clean after the run; --no-bundle wrote nothing)
```

- `docs/automated-tests/RESULTS.md` newest row reads "| [`20260927-030444`](20260927-030444/) | `bcf9e51` | clean | 1.3.0 → 1.4.0 | 0/0 | 112 | 1201/0/1201 | pass | 24073 | 3089 | 6.7 | 2.0 | 15 | 0 | **green** |".
- `3901b38` "GI-KC-RV: re-vendor LibKa0s v1.66.0 (kit 35), wire test_lizard_sighted, record sighted complexity". Its message records "maxCcn 46, warnings 3 … left for GI-KC-12". `1589fb8` "GI-KC-12: split the three sighted CCN>15 functions below 15". Today's run confirms max 15.
- `tests/run.lua:255` reads `{ name = "test_lizard_sighted", dir = "tests/_kit/" },`.
- `docs/testing.md:257` reads "| `complexity` | `bash tests/_kit/run-automated-tests.sh --suite complexity` (lizard over the kit's sighted shadow, …". No gate line quotes raw `lizard`. `docs/performance.md:243` reads "Never the raw `lizard -l lua -x ...` command".
- `git tag --sort=-creatordate | head -1` gives `1.4.0-release`, at `a06e2aa` (2026-09-27).

## E8 — LOC census and the watch list (closes `C-10`)

```
$ git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | wc -l                 -> 127
$ git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | xargs wc -l | sort -rn | head -3
  45193 total
    996 modules/IconGrid.lua
    976 tests/test_schema.lua
```

No file is at or above 1000. There are no declared generated-data exemptions to subtract.
`docs/ARCHITECTURE.md:369` reads `### Files over the 1500-line cap` and `:376` reads "Nothing is over
the cap today.". `tests/run.lua:249` reads `{ name = "test_layout_cap", dir = "tests/_kit/" },`.
The watch list in `RESULTS.md` has 9 band rows, each "**Already tracked as #24**" … "#32".
`gh issue list` shows #24 to #32 all `CLOSED ['enhancement','state:done','severity:low']`. No
disposition reads "Accepted".

## E9 — `docs/` shape (`documentation-§3`)

```
$ git ls-files 'docs/*.md' | grep -vE '^docs/(audits|reviews|revendor|superpowers|investigations)/|^docs/automated-tests/[0-9]|^docs/perf-analysis/[0-9]' \
    | sed 's#^docs/##' | sort > files ; <rows of docs/ARCHITECTURE.md:264-316> | sort > reg
files (22): ARCHITECTURE.md automated-tests/README.md automated-tests/RESULTS.md castbar.md common-tasks.md compat-layer.md
            data-flow.md debug.md icon-grid.md message-bus.md midnight-quirks.md module-map.md perf-analysis/README.md
            performance.md profiles.md schema.md scope.md settings-panel.md slash-dispatch.md smoke-tests.md test-cases.md testing.md
orphans: (none)   dangling: (none)   duplicates: (none)
$ wc -l docs/ARCHITECTURE.md -> 405
```

- The four tables appear in order: `:275` `### Required`, `:287` `### Conditional`, `:299` `### Verification and record`, `:310` `### Addon-specific`.
- `:296` reads "| `perf-analysis/README.md` | Present | `/kcd perf` exists …", so it sits in Conditional.
- `:297` reads "| `debug.md` | Present | … the `/kcd diagnostics` report and its twelve sections …".
- `:308` reads "| `automated-tests/RESULTS.md` | One row per run; generated by the runner, never hand-edited apart from the watch list's `Disposition` column …". This closes `B-06`.
- Mandated-section lengths: `## Module map` runs `:22-68` (47 lines) and `## Settings schema` runs `:182-230` (49 lines). Fetched `documentation.md` reads "the failure they catch is 1071 lines, not 412 — and an audit reports the shape, not the arithmetic."
- `ls docs/pending docs/perf-runs docs/complexity.md docs/file-index.md docs/conventions.md` finds none of them.

## E10 — The register

Rows are `docs/ARCHITECTURE.md:331-338` (header `:329`). The trigger and evidence reads:

- Row 1. `core/Database.lua:662` reads `self:FoldLegacyUnits(self.db)` through `:669` `self:MigrateFontFlags(self.db)`, which is five calls. `docs/schema.md:245` reads `` ### `units.<unit>.label.style` shape ``.
- Row 2. `defaults/Profile.lua:309` reads `target = {` and `:320` reads `focus = {`. There is no third unit. `docs/schema.md:277` reads `` ## Migration: folding legacy `icons`/`castbar`/`anchors` into `units.target` ``.
- Row 3. `settings/Icons.lua:58` reads `local ANCHOR_VALUES = H.AnchorValues()`. `settings/Castbar.lua:223` reads `local POSITION_ANCHOR_VALUES = H.AnchorValues()`.
- Row 4. `libs/LibKa0s/OptionsCompose.lua:479` reads `values = VISIBILITY_VALUES, sorting = VISIBILITY_SORT, default = "always",`.
- Row 5. `tests/test_settings_log.lua` exists. KickCD#33 is closed `state:done`.
- Row 6. `core/Compat.lua:370` reads `local function safeRender(value)`, ending at `:378`. `:382` reads `local function describe(out, label, value)`, ending at `:387`. Callers are `:386` and `:460`. `grep 'lib.Describe\|RenderValue' libs/LibKa0s/Core*.lua` finds nothing.
- Row 7. A grep of the vendored payload for an `IdInput` compact or caption-less form finds nothing.
- Row 8. #16 and #17 are `CLOSED … state:done`.

## E11 — Issue store

`gh issue list --state all --limit 200 --json number,title,state,body,labels,url`. The `gh` CLI was
used, never GraphQL. There are 36 issues.

```
OPEN   #1 #2 #5 (enhancement, state:triaged, severity:low)   #3 #4 (bug, state:triaged, severity:medium)
       #34 #35 (bug, state:triaged, severity:low)
CLOSED state:done       #6-#10 #13 #15-#22 #24-#33 #36
CLOSED state:will-not-do #11 #12 #14 #23
```

- `gh issue view 15 --json state,labels` gives `CLOSED bug,state:done,severity:low`. This closes `C-11`.
- `gh issue view 12 --json comments` gives `2026-09-24T07:41:07Z Superseded: KickCD now consumes LibKa0s-Widgets-1.0 twice. …`. This closes `C-12`.
- No title carries a `[status]` or `[Optional]` prefix (`B-05`). There is no `docs/pending/LEDGER.md`.

## E12 — Mechanical checks and compliance claims

**Tests.** `~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua` gives
`1302 passed, 0 failed, 1 skipped, 1303 total`, exit 0. The skip line reads
`SKIP  diagnostics contract: an addon that opts out lands the report and leaves logging off — this addon keeps the default …`.

**Lint.** `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` gives `Total: 0 warnings / 0 errors in 127 files`, exit 0.
`.luacheckrc:8` reads `exclude_files = { "libs/", "docs/audits/", "_dev/", "tests/_kit/", "docs/reviews/" }`,
so `tests/` is linted. The harness global is in a `files["tests/"]` stanza, and there is no top-level `ignore`.

**Line endings.**
```
test -f .gitattributes                                  -> present
grep -n '^\* text=auto eol=\(crlf\|lf\)$' .gitattributes -> 26:* text=auto eol=crlf
grep -nE '^\*\.(sh|py) text eol=lf$' .gitattributes      -> 36:*.sh text eol=lf / 37:*.py text eol=lf
grep -c ' binary$' .gitattributes                        -> 20
tr -d '\r' < .gitattributes | head -84 | diff - <line-endings-§5 client-bound body> -> (no output); tail after 84: empty
(e) the AUDIT.md one-liner over `git ls-files -z` (whole tracked set, no exclusions) -> 0
```

**Packaging** (run under `bash`). (a) prints nothing. (b) prints `UNACCOUNTED — .git` only, which is
the exempt entry. (c) prints nothing.

**Disabled state (`slash-commands-§7`).** Scope: shipped source (`':!libs' ':!tests'`).
- Registration sites all route through `NS.RegisterEventList` or `NS.SafeRegisterUnitEvent`, plus
  `RegisterMessage` on module targets. Examples: `modules/Cooldowns.lua:616` reads `NS.RegisterEventList(self, LIFECYCLE_EVENTS)`
  and `:649` reads `self:RegisterMessage(NS.MSG.PROFILE_CHANGED, "OnProfileChanged")`.
- Teardown: `modules/Cooldowns.lua:667-673` (`self:UnregisterAllEvents()`, `self:UnregisterAllMessages()`, the canceller),
  `core/State.lua:225` (`boot:UnregisterAllEvents()`), `core/Util.lua:526` (`f:UnregisterAllEvents()` in `Disarm`),
  `settings/Spells.lua:907`, `core/SpellInput.lua:334`, and the ticker cancel `modules/IconGrid_Ticker.lua:230`.
- `tests/run.lua:229` lists `"test_disabled"`. `tests/test_disabled.lua:187` reads `test("DISABLED: the registration set is EMPTY, by count and by name", function()`,
  `:58` reads `local function registrations(inst)`, and `:491` reads `test("RE-ENABLED: the registration set comes back, exactly", function()`.
- `settings/Slash.lua:466-470` builds `liveVerbs()` from `SlashLib.LIVE_VERBS` plus `NS.EXTRA_LIVE_VERBS` (`core/KickCD.lua:366` reads `NS.EXTRA_LIVE_VERBS = { "spells", "profile" }`).

**Events (`events-frames-taint-§1`).** `core/CoreSetup.lua:89` reads `NS.SafeRegisterEvent(target, event, list[i][2], rejected)`.
`:160` reads `function NS.SafeRegisterEvent(target, event, handler, rejected)`. `core/Util.lua:503` reads
`function Util.NewUnitCastFilter(module, unit, routes)`, and `:506` reads
`error("Util.NewUnitCastFilter: route " .. tostring(ev)`. `core/KickCD.lua:428` reads
`{"events", "List event names this client refused to register",`.

**Bus.** `git grep -nE '(Send|Register)Message\("Ka0s_' -- '*.lua' ':!libs' ':!tests/_kit'` matches only
a comment in `tests/test_bus.lua:202`. The wire names are at `core/Constants.lua:42-50`.

**Diagnostics.** `core/KickCD.lua:298` reads `{"diagnostics",   NS.L["Write a diagnostic report to the debug console, for a bug report"],`.
`:382` is the `debug` word row, and `:454` reads `if sub == "diagnostics" then return self.DebugLog:RunDiagnostics() end`.
`grep -rniE '"(diag|dump|dx)"' settings core modules` finds nothing. `grep -n 'diagnosticsEnablesLogging' core/*.lua` finds nothing.
`README.md:122` reads `## Reporting a bug`, `:124-126` are the three bullets, and `:128` reads
"The report is added after the debug trace in the same window, so one copy carries both."

**Library sinks.** `settings/Slash.lua:502` reads `debug   = function(tag, message) if NS.Debug then NS.Debug(tag, "%s", message) end end,`.
`settings/OptionsSetup.lua:160` reads `debug = function(tag, fmt, ...) if NS.Debug then NS.Debug(tag, fmt, ...) end end,`.
`core/LauncherSetup.lua:169` is `debug = …` and `:174` is `debugAtEnable = function(tag, message)`.
`core/LifecycleSetup.lua:160` is `debug     = function(tag, message) …`.

**Launcher.** `core/LauncherSetup.lua:126` reads `label = "Ka0s KickCD",`. `:131` reads `icon  = "Interface\\AddOns\\" .. addonName .. "\\media\\logos\\kickcd.logo.128.tga",`.
`:148` is `isEnabled  = …` and `:153` is `toggleLock = …`. `git grep -nE 'OnTooltipShow|MenuUtil|EasyMenu|NewDataObject'` over the shipped source finds nothing.

**Close buttons.** `git grep -n 'MakeCloseButton(' -- '*.lua' ':!libs' ':!tests'` gives `core/CoreSetup.lua:133`
`function NS.MakeCloseButton() return nil end`, `:245` `return lib.MakeCloseButton(parent, onClick, addonName)`, and a comment at `core/PerfSetup.lua:251`.

**Settings window in combat.** `settings/Panel_Widgets.lua:144` reads `if refusedInCombat() then return false end`, and `:160` reads
`Settings.OpenToCategory(id)` (the page jump). `settings/Spells.lua:776` reads `if not (SettingsPanel and SettingsPanel:IsShown()) then`,
inside `OnHide`. That is a read, with no close or commit.

**IconTexture.** `python3 -I` header read of `media/logos/kickcd.logo.128.tga` gives `type 2 w 128 h 128 bpp 32`.

**TOC annotations.** `KickCD.toc:110` reads "# LOAD-BEARING POSITION: modules/IconGrid_Layout.lua, modules/IconGrid_Render.lua,".
`:121` reads "# LOAD-BEARING POSITION: modules/Castbar_Frame.lua, modules/Castbar_Handle.lua,". `:44` reads
"# A line in this block without a LOAD-BEARING POSITION comment is conventional:".

**Closures.** `README.md:100` reads "| Why won't the settings panel open in combat? | The game blocks it mid-fight. Run `/kcd config` again once combat e…" (C-05).
`docs/compat-layer.md:7` reads "**Six members are `LibKa0s-Compat-1.0`'s, not KickCD's.** … documented once, in LibKa0s's …" (C-07).
`settings/Spells_Rows.lua:252` reads `local mark = NS.Icon and NS.Icon("close")` and `:255` reads `atlas   = not mark and "transmog-icon-remove" or nil,` (C-13, library-absent fallback only).
`git grep -nE 'or _G\.print|_G\.print' -- core modules settings defaults locales` finds nothing (A-08).
The British-spelling grep over `docs/perf-analysis/README.md` and the root docs finds nothing (B-02).
