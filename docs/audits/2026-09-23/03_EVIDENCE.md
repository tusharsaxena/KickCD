# KickCD — Evidence (2026-09-23)

Every command here was run from `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD` at `dc11094`.
Each one is given with its real output and its **scope**. Before this file was written, every
`file:line` it cites was re-read, and the text found at that line is quoted beside it.

**How runs were bounded.** `ka0s-bounded` is not on `PATH` in this shell, so it was invoked by its
full path, `~/.claude/wow-addon/bin/ka0s-bounded`. No run needed a bare `timeout 900`.

---

## E0 — Standard resolution

```
curl -fsSL $RAW/AUDIT.md, $RAW/standards/STANDARDS.md, $RAW/standards/ADDONS.md,
           $RAW/standards/standards/<27 files from the Sections list>
head -1 STANDARDS.md  ->  # Ka0s WoW Addon Standard (v2.64.0, 2026-09-23)
for f in standards/standards/*.md: git -C ../WowAddonStandards show origin/master:<path> | cmp - $f
  -> no output (all 27 plus AUDIT.md, STANDARDS.md, ADDONS.md byte-identical to e68795f)
git -C ../WowAddonStandards diff --stat f37a8fa origin/master -- standards/standards/
  -> 25 files changed, 1218 insertions(+), 164 deletions(-)
```

## E1 — Vendored LibKa0s and test kit (library-stack-§7, testing-§11)

```
$ grep -n 'Bundles \[LibKa0s\]' CLAUDE.md README.md
CLAUDE.md:42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.55.0 (MIT).
$ git -C ../LibKa0s rev-parse v1.55.0 HEAD
bb161b730f2691be39a0dfbbe5c66fd7ca5e8db1
46ccaa6c5260e99cd0d1028ab0aee421329cfedf          # sibling HEAD is ahead of the tag -> diff the TAG
$ git -C ../LibKa0s archive v1.55.0 LibKa0s testkit | tar -x -C <scratch>/lk155
$ diff -r --strip-trailing-cr <scratch>/lk155/LibKa0s libs/LibKa0s ; echo rc=$?
rc=0
$ diff -r --strip-trailing-cr <scratch>/lk155/testkit tests/_kit ; echo rc=$?
rc=0
$ diff -rq <scratch>/lk155/LibKa0s libs/LibKa0s ; diff -rq <scratch>/lk155/testkit tests/_kit
(no output)
file counts: payload 146 / 146, kit 11 / 11
```

**Scope:** both whole folders. **Result: compliant.** The copy has not drifted (#45), nothing is
missing (#48), and the provenance line is only in `CLAUDE.md` (#58, #59).

```
$ grep -nE '^## (Libraries|Bundled libraries|Libraries and credits|Credits and libraries|Credits and bundled libraries)' README.md
(no output)
$ grep -n 'WoW_Addon_Standard\|media/logos\|<img' README.md
6:![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)     # bare, not linked
```

## E2 — Headless suite, lint, inventory

```
$ ~/.claude/wow-addon/bin/ka0s-bounded lua tests/run.lua ; echo rc=$?
...
  PASS  layoutcap self-test: the exempt set takes folders as well as paths

1050 passed, 0 failed, 0 skipped, 1050 total
rc=0
$ ~/.claude/wow-addon/bin/ka0s-bounded luacheck . | tail -1
Total: 0 warnings / 0 errors in 101 files
$ ~/.claude/wow-addon/bin/ka0s-bounded lua tests/run.lua --list > list.md
$ diff <(tr -d '\r' < docs/test-cases.md) <(tr -d '\r' < list.md) | wc -l
0
README.md:7  ![Tests](https://img.shields.io/badge/Tests-1050%2F1050_passing-green)
```

`.luacheckrc:11` reads
`exclude_files = { "libs/", "docs/audits/", "_dev/", "tests/_kit/", "docs/reviews/" }`. `tests/` is
linted. `.luacheckrc:101-103` reads `files["tests/"] = { globals = { "_G.KICKCD_TEST" } }`, and there
is no top-level `ignore`. **Lint: compliant.**

Suite declarations: `tests/run.lua:175` reads `{ name = "test_prose", dir = "tests/_kit/" }`,
`:194` reads `{ name = "test_eol", dir = "tests/_kit/" }` and `:197` reads
`{ name = "test_layout_cap", dir = "tests/_kit/" }`. `Kit.run{ dir = root .. "/tests/", suites = SUITES }`
raises no budget. `git ls-files --others --exclude-standard` finds no untracked files. A grep for
`/mnt/`, `/home/`, `/Users/` and `:\\Users` in `tests/*.lua` finds none. **testing-§15: compliant.**

## E3 — Complexity and the record (automated-tests, AP #51, #53) → B-04, C-10

```
$ ~/.claude/wow-addon/bin/ka0s-bounded lizard -l lua -x "./libs/*" -x "./tests/_kit/*" . | tail -6
No thresholds exceeded (cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100)
Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt
     20793       6.8     2.1       51.6     2640            0      0.00    0.00
top CCN now:            15 buildSpecNameMaps (core/Util.lua:260), 15 State.ApplyInterruptibleAlpha
                        (core/State.lua:109), 15 Layout.layoutBlock (modules/IconGrid_Layout.lua:145)
top CCN at 20260916:    15 buildSpecNameMaps, 15 StateChanged (modules/Cooldowns.lua:265),
                        15 ApplyInterruptibleAlpha, 15 layoutBlock
```

The CCN-15 functions are dense guarding and defaulting. `ApplyInterruptibleAlpha` is a nil and
secret guard ladder, and `buildSpecNameMaps` is table defaulting. Nothing crossed a threshold.

```
docs/automated-tests/20260916-184417/manifest.json: "git": { "sha": "fac2411f…", "branch": "master", "dirty": false }
$ git rev-list --count fac2411..HEAD   -> 38
$ git log -1 --format='%h %ci' 1.3.0-release   -> ed88759 2026-09-10 23:54:57 +0530
RESULTS.md:26  | [`20260916-184417`] | 1.3.0 | 0/0 | 97 | 973/0/973 | pass | 19884 | 2494 | 6.7 | 2.1 | 15 | 0 | **green** |
```

Watch-list dispositions, traced through `git show <c>:docs/automated-tests/RESULTS.md` for each
commit touching the file:

```
7b1e1a1 (20260908): Castbar 1345 "Already tracked as `A-2`." | IconGrid 1152 A-2 | Spells 1312 A-2 | wow_mock 1232 KCD-30
ed88759 (20260910, Release 1.3.0): Castbar 1345 A-2 | IconGrid 1163 A-2 | Spells 1312 A-2 | wow_mock 1245 KCD-30
7d39222 (20260916): Castbar 1345 A-2 | IconGrid 1163 A-2 | Spells 1246 A-2 | wow_mock 1027 KCD-30
2b586f5 (20260916): Castbar 1345 A-2 | IconGrid 1163 A-2 | Spells 1246 A-2 | wow_mock 1060 KCD-30
```

`RESULTS.md:86` (Spells) reads "… Re-check at 1400, not at the cap." Today the file is **1444**.
`A-2` resolves only to the retired advisory row at `docs/audits/2026-08-05/02_DEVIATIONS.md:50`.

## E4 — Layout census (layout-§1)

```
$ git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | wc -l          -> 101
$ git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | xargs wc -l | sort -rn | head -6
  37269 total
   1444 settings/Spells.lua
   1423 modules/Castbar.lua
   1343 modules/IconGrid.lua
   1129 tests/wow_mock.lua
   1014 modules/IconGrid_Render.lua
```

**Scope:** every tracked, authored Lua file, including `tests/`, and excluding `libs/` and
`tests/_kit/`. No generated data is declared exempt. Nothing is over 1500.
`docs/ARCHITECTURE.md:440` reads "Nothing is over the cap today."

## E5 — Line endings (line-endings)

```
(a) test -f .gitattributes                      -> present
(b) :26  * text=auto eol=crlf
(c) :36  *.sh text eol=lf    :37  *.py text eol=lf
(d) grep -c ' binary$' .gitattributes          -> 20
(e) [the AUDIT.md one-liner, verbatim]         -> 0          (scope: git ls-files, 532 paths, no exclusions)
body: diff <(head -n 84 .gitattributes | tr -d '\r') <canonical client-bound body from line-endings-§5>  -> no output
tail -n +85 .gitattributes                      -> nothing
```

**Compliant.** The kit's `test_eol` owns (e), and it is green.

## E6 — Packaging (packaging)

```
(a) entries: .luacheckrc .pkgmeta .gitignore .gitattributes docs tests _dev .claude .superpowers -> none NOT IGNORED
(b) UNACCOUNTED — .git                          (the one exempt entry)
(c) (no output)                                 (.claude and .superpowers both exist)
```

`.pkgmeta:17` reads `# downloaded byte. They are listed because packaging.md:28 MUSTs every root`.
`:20` reads
`- .claude          # untracked; listed under packaging.md:28` and `:21` reads
`- .superpowers     # untracked; listed under packaging.md:28`. In the fetched `packaging.md`,
line 28 is `  #                    direction". The audit check gates on `[ -d tools ]` for the same reason.`,
which is a template comment. The strong-form MUST now sits on a different line → `C-08(6)`.

## E7 — The re-vendor bundle check (audit-review-history) → C-01

The `AUDIT.md` commands, run verbatim:

```
horizon=$(ls -1 docs/revendor | sort | head -1 | cut -c1-10)  -> 2026-08-25
vendored (provenance tag at each commit touching libs/LibKa0s since the horizon; 31 tags):
v1.18.0 v1.18.1 v1.19.0 v1.23.0 v1.24.0 v1.25.0 v1.26.0 v1.27.0 v1.28.0 v1.29.0 v1.31.0 v1.32.0
v1.33.0 v1.34.0 v1.35.0 v1.36.0 v1.36.1 v1.36.2 v1.37.0 v1.38.0 v1.39.0 v1.42.0 v1.44.0 v1.45.0
v1.46.1 v1.47.0 v1.50.0 v1.51.0 v1.52.0 v1.53.0 v1.55.0
recorded (folder tag, or 01_DELTA.md line 1 for the bare-dated ones; 8 tags):
v1.15.0 v1.25.0 v1.30.0 v1.31.0 v1.32.0 v1.33.0 v1.34.0 v1.55.0
grep -vxF -f recorded vendored | wc -l  -> 25
```

Bundle first lines (the bare-dated ones read correctly):

- `2026-08-25/01_DELTA.md:1` is "Delta: KickCD vs LibKa0s v1.15.0".
- `2026-09-03/01_DELTA.md:1` is "LibKa0s v1.24.0 → v1.25.0".
- `2026-09-12/01_DELTA.md:1` is "LibKa0s v1.29.0 → v1.30.0".

No row in `## Documented deviations` covers the gap.

## E8 — The disabled state (slash-commands-§7) — compliance evidence

Census commands (scope: `git ls-files '*.lua' ':!libs' ':!tests'`):

```
Register* sites:   core/State.lua:144-146, :205-206, :213 | core/Util.lua:439 (RegisterUnitEvent)
                   modules/Castbar.lua:1081,1086,1087,1126-1129 | modules/Cooldowns.lua:544-548,554,555,588,589
                   modules/IconGrid.lua:880-882,886,935,936,941,942,948,949 | modules/UnitLabel.lua:250-253
                   settings/Spells.lua:380-381, 1337, 1345, 1358, 1359, 1364
Unregister sites:  core/State.lua:162, :196 | modules/Castbar.lua:1044, 1104-1105, 1109, 1154 (+ :772, :926 OnUpdate nil)
                   modules/Cooldowns.lua:607-608 | modules/IconGrid.lua:831, 854-855, 859, 868 (_StopTextTicker)
                   modules/UnitLabel.lua:268-269 | settings/Spells.lua:1423, 1426-1427
```

- `core/LifecycleSetup.lua:109` reads `local function standDown()`. `:111` reads
  `eachModule(true, function(m) if m.Suspend then m:Suspend() end end)`. `:221` reads
  `function NS.RefreshEnabledHold()`.
- `modules/Cooldowns.lua:606-608` read `function Cooldowns:Suspend()` /
  `self:UnregisterAllEvents()` / `self:UnregisterAllMessages()`.
- `core/State.lua:195-196` read `function State.StandDown()` / `boot:UnregisterAllEvents()`.
- `core/LauncherSetup.lua:152-156` read `onClick = function()` /
  `if NS.MasterEnabled and not NS.MasterEnabled() then` /
  `if NS.Slash and NS.Slash.PrintDisabledLine then NS.Slash.PrintDisabledLine() end`.
- `tests/test_disabled.lua:180` reads
  `test("DISABLED: the registration set is EMPTY, by count and by name", function()`, and `:190` reads
  `assertEqual(n, 0, "a disabled addon must be registered for NOTHING; still live: " .. survivors(inst))`.
- `tests/test_disabled.lua:335` reads
  `test("DISABLED: every reserved verb still answers, and the bare /kcd opens the panel", function()`.

**Result: compliant**, on all five parts.

## E9 — Per-finding citations (re-read, quoted)

**KICKCD-A-08**
- `core/KickCD.lua:127` — `    local fn = self.Util and self.Util.print or _G.print`
- `core/Compat.lua:441` — `    local out = (NS.Util and NS.Util.print) or _G.print`
- `modules/Cooldowns.lua:661` — `    local p = NS.Util and NS.Util.print or _G.print`

**KICKCD-B-02**
- `docs/perf-analysis/README.md:35` — `field (epoch seconds) — **when the capture happened**, not when it was written up, so a run analysed`
- `docs/perf-analysis/README.md:36` — `a week later still sorts against its neighbours. A bundle is never renamed to match a later`
- `tests/_kit/test_prose.lua:211` — `    "docs/audits/", "docs/automated-tests/", "docs/perf-analysis/",`

**KICKCD-B-03**
- `docs/ARCHITECTURE.md:390` — `| \`savedvariables-§1\` | Two profile migrators run off the **stored shape**, …`
- `docs/ARCHITECTURE.md:468` — `… runs the three shape-driven migrators unconditionally (\`Database:FoldLegacyUnits\` → \`Database:BackfillLabelStyle\` → \`Database:MigrateSpecKeys\`) …`
- `core/Database.lua:821` — `    self:FoldLegacyUnits(self.db)`. `:822` — `    self:BackfillLabelStyle(self.db)`. `:824` — `    self:MigrateSpecKeys(self.db)`.
- `docs/schema.md:256` — `                                      --    pre-v5 token for it was "NONE"` (the row's `#L256` target). `:269` — `**Migration:** \`Database:BackfillLabelStyle(db)\` fills in …`

**KICKCD-A-02 / C-16** (the TOC)
- `KickCD.toc:39` `# Locales` · `:89` `# Defaults (the only place a profile default is hardcoded — savedvariables-§2)` · `:93` `# Modules` · `:96` `modules\IconGrid_Layout.lua` · `:97` `modules\IconGrid_Render.lua` · `:99` `modules\Castbar_Handle.lua` · `:100` `modules\Castbar_Skin.lua` · `:101` `modules\Castbar_Debug.lua`
- `modules/IconGrid_Layout.lua:15` — `local IconGrid = NS:GetModule("IconGrid")`
- `modules/IconGrid_Render.lua:19` — `local IconGrid = NS:GetModule("IconGrid")`
- `modules/Castbar_Handle.lua:24` — `local Castbar = NS:GetModule("Castbar")`
- `modules/Castbar_Skin.lua:53` — `local Castbar = NS:GetModule("Castbar")`
- `modules/Castbar_Debug.lua:10` — `local Castbar = NS:GetModule("Castbar")   -- registered by modules/Castbar.lua, which loads first`

**KICKCD-C-02** (no isolation)
- `modules/Cooldowns.lua:544` — `    self:RegisterEvent("SPELL_UPDATE_COOLDOWN",        "OnCooldownEvent")` … through `:555` — `    self:RegisterEvent("TRAIT_CONFIG_UPDATED",         "Rebuild")`
- `core/State.lua:144` — `boot:RegisterEvent("PLAYER_LOGIN")`
- `settings/Spells.lua:1358` — `        ev:RegisterEvent("SPELLS_CHANGED",       refreshIfShown)`
- Search, with scope `git ls-files '*.lua' ':!libs' ':!tests'`: `grep -n 'IsEventValid\|pcall(.*Register\|badEvents'` returns nothing.

**KICKCD-C-03** (the frames are rebuilt)
- `core/Util.lua:438` — `function Util.RegisterUnitCastEvent(module, unit, eventName, handlerName)`. `:439` — `    local f = CreateFrame("Frame")`
- `modules/IconGrid.lua:820` — `        inst.eventFrames[#inst.eventFrames + 1] =`. `:832` — `    inst.eventFrames = {}`. `:860` — `            inst.eventFrames = {}`
- `modules/Castbar.lua:1016` — `    local castEvents = {`. `:1029` — `        inst.eventFrames[#inst.eventFrames + 1] =`. `:1045` — `    inst.eventFrames = {}`. `:1110` — `            inst.eventFrames = {}`
- Count: IconGrid registers 8 events per unit (`modules/IconGrid.lua:811-818`), and Castbar registers 10 (`modules/Castbar.lua:1017-1026`). (8 + 10) × 2 units = 36 frames per cycle.

**KICKCD-C-04**
- `core/State.lua:143` — `local boot = CreateFrame("Frame")`. `:145` — `boot:RegisterEvent("PLAYER_REGEN_DISABLED")`
- `settings/Spells.lua:375` — `cacheEvents:SetScript("OnEvent", invalidateCmCache)`. `:380` — `    cacheEvents:RegisterEvent("TRAIT_CONFIG_UPDATED")`

**KICKCD-C-05**
- `README.md:97` — `| Why won't the settings panel open in combat? | The game blocks opening settings mid-fight, so \`/kcd config\` waits until combat ends. |`
- `README.md:113` — `| The settings panel won't open mid-fight. | On purpose. The game blocks it in combat, and it opens the moment combat ends. |`
- `core/KickCD.lua:815-819` — `function NS:OpenSettings()` / `    if inCombat(self) then` / `        p(self, combatNotice(self))` / `        return` / `    end`

**KICKCD-C-06**
- `docs/ARCHITECTURE.md:356` — `| \`debug.md\` | Not applicable | The console is \`LibKa0s-DebugLog-1.0\`’s; the \`/kcd debug\` subcommands dump state through it rather than adding a surface |`
- `modules/Castbar_Debug.lua:134` — `    local emit = NS.Util.print`. `core/Compat.lua:441`, quoted under A-08.

**KICKCD-C-07**
- `docs/compat-layer.md:16` — `| \`Compat.GetSpellInfo(id)\` | **\`LibKa0s-Compat-1.0\`** (\`C_Spell.GetSpellInfo\` (table) → \`GetSpellInfo\` (tuple, rank dropped)) | Returns \`name, iconID, castTime, minRange, maxRange, spellID\`, or one \`nil\`. …`

**KICKCD-C-08** (inventories)
- `docs/ARCHITECTURE.md:78` — `  it. Five do: \`core/CoreSetup.lua\`, \`core/EnvSetup.lua\`, \`core/MediaSetup.lua\`,`. `:81` — `  write \`local addonName, NS = ...\`; the other thirty write \`local _, NS = ...\`. …`
  - Census command, with scope `git ls-files 'core/*.lua' 'defaults/*.lua' 'settings/*.lua' 'modules/*.lua' 'locales/*.lua'` (38 files):
  - `grep -l '^local addonName, NS = \.\.\.'` returns **8**: core/Constants, CoreSetup, DebugLogSetup, EnvSetup, LauncherSetup, LifecycleSetup, MediaSetup, PerfSetup.
  - `grep -l '^local _, NS = \.\.\.' | wc -l` returns **30**.
- `.luacheckrc:25` — `--     Five files in this addon do read it -- CoreSetup, EnvSetup, MediaSetup, DebugLogSetup and`
- `docs/ARCHITECTURE.md:352` — `| \`compat-layer.md\` | Present | \`core/Compat.lua\` is 496 lines of addon-specific shimming beyond LibKa0s |`
  - `wc -l core/Compat.lua` returns **485**.
  - `grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.' core/Compat.lua` returns **8** (`:72, :149, :176, :208, :221, :332, :440, :473`).
- `docs/ARCHITECTURE.md:353` — `| \`message-bus.md\` | Present | The addon’s message contract, kept in sync with each module’s header |`. There are 5 messages (`core/Constants.lua:40-51`).
- `docs/ARCHITECTURE.md:281` — `- **\`settings/Spells.lua\`'s five subscriptions** — the editor's refreshers and the cooldown-manager`. The registrations are `settings/Spells.lua:380-381` (2) and `:1337, :1345, :1358, :1359, :1364` (5), which is 7.
- `.luacheckrc:89` — `-- The harness publishes its exposed table under a per-repo global, written at tests/run.lua:217`. `tests/run.lua:299` — `_G.KICKCD_TEST = Kit.expose{`

**KICKCD-C-09**
- `wc -l docs/ARCHITECTURE.md` returns **468**. `docs/ARCHITECTURE.md:226` — `## The stand-down: disabled is total`. `:312` — `## Taint notes`.

**KICKCD-C-10** — `docs/automated-tests/RESULTS.md:84` — `| 1000–1500 (on notice) | \`modules/Castbar.lua\` | 1345 | **Already tracked as \`A-2\`.** …`. The rest is in E3.

**KICKCD-C-11** — `gh issue list` returns `15	OPEN	bug,state:done,severity:low	Cooldowns: the debug log reports every global cooldown as a state change`. `README.md:125` — `| 1.3.0 | 2026-09-10 | - The global cooldown is now attributed per spell … (#15)…`

**KICKCD-C-12** — `gh issue view 12` returns `LibKa0s-Widgets-1.0: declined — no control in this addon wants it | CLOSED`. `modules/Castbar_Handle.lua:41` — `local KW = LibStub and LibStub("LibKa0s-Widgets-1.0", true)`

**KICKCD-C-13** — `settings/Spells.lua:798` — `        atlas   = "transmog-icon-remove",`. `libs/LibKa0s/Media.lua:94` — `  "close", "minimise", "expand", …`. `:97` — `  "copy", "clear", "add", "edit", "confirm", "cancel", …`

**KICKCD-C-14** — `core/KickCD.lua:733` — `    {"enable",   "Enable a spell — \`... enable <id> [CLASS SPEC]\`",`. `:735` — `    {"disable",  "Disable a spell — \`... disable <id> [CLASS SPEC]\`",`

**KICKCD-C-15** (bare `§N`)

The scope is the 128 files from
`git ls-files | grep -vE '^(libs/|tests/_kit/|docs/audits/|docs/reviews/|docs/revendor/|docs/automated-tests/2|docs/perf-analysis/2|docs/superpowers/)'`
filtered to `*.lua`, `*.md`, `*.toc`, `.luacheckrc` and `.pkgmeta`.

- `grep -nP '§ ?[0-9]+\.[0-9]'`, the dotted global form, returns **0**.
- The bare-`§N` hits were read one by one. Continuation shorthand after a qualified reference in the
  same sentence was not counted. Eight sites cite no file at all:
  - `core/Compat.lua:245` — `-- never touch the deprecated globals directly (§11). Both members are`
  - `modules/IconGrid.lua:1207` — `--- the printed label actually changes (§9). Label each state precisely`
  - `settings/Panel.lua:179` — `-- Settings-change logging (standard §10): one [Set] line per settled change,`
  - `tests/test_compat_api.lua:4` — `-- the addon's ONE seam onto the deprecated/renamed client APIs (§11), and`
  - `tests/test_debuglog.lua:108` — `test("scrollbar + line-counter sync methods exist (§11)", function()` (and `:115`, `:124`, mirrored at `docs/test-cases.md:403-405`)
  - `tests/test_settings_log.lua:1` — `-- tests/test_settings_log.lua — settings-change capture at Helpers.Set (§10)`

## E10 — Register and issues (documentation-§3, audit-review-history)

```
$ gh issue list --state all --limit 200 --json number,title,state,labels,url   (22 issues)
open:   22 (triaged/medium) 15 (state:done!) 10 9 ("[Optional] …") 8 7 5 4 3 2 1
closed: 21 20 19 18 17 16 13 6 (state:done) · 14 12 11 (state:will-not-do)
every issue carries one state: label and one severity: label
```

The register rows' trigger evidence:

- `settings/Icons.lua:56` — `local ANCHOR_VALUES = H.AnchorValues()`
- `settings/Castbar.lua:192` — `local POSITION_ANCHOR_VALUES = H.AnchorValues()`
- `libs/LibKa0s/OptionsCompose.lua:479` — `      values = VISIBILITY_VALUES, sorting = VISIBILITY_SORT, default = "always",`
- `core/Compat.lua:368` — `local function safeRender(value)`. `:452` — `        unit, safeRender(rawName), tostring(canAttack)))`, which is inside `DebugInterrupt` (`:440`).

## E11 — Options UI and launcher — compliance evidence

- The combat grep, with scope `git ls-files '*.lua' ':!libs' ':!tests/_kit'`, finds one live call:
  `settings/Panel_Widgets.lua:144` — `    Settings.OpenToCategory(id)`. It follows `:136` —
  `    if refusedInCombat() then return false end`. Its `id` comes from `category:GetID()` (`:132`).
  This is the **page-jump carve-out**, and it is compliant.
- The close grep finds `core/CoreSetup.lua:102` — `    function NS.MakeCloseButton() return nil end`,
  and `:174` — `    return lib.MakeCloseButton(parent, onClick, addonName)`. Compliant.
- `core/LauncherSetup.lua:122` — `    label = "Ka0s KickCD",`. `:127` —
  `    icon  = "Interface\\AddOns\\" .. addonName .. "\\media\\logos\\kickcd.logo.128.tga",`.
- The TGA header of `media/logos/kickcd.logo.128.tga` reads type 2, 128×128, 32 bpp.
- The bus literal grep `grep -rnE '(Send|Register)Message\("Ka0s_'` (addon files) finds one hit,
  `tests/test_bus.lua:198`, which is a comment.
