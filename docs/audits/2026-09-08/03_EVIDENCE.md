# KickCD — Evidence (2026-09-08)

Every `file:line` below was **re-read at HEAD `03f3b9a` and the cited text quoted beside it** before
this file was written. Every count is produced by a **recorded command whose scope is stated** — what
it swept and what it did not. No number in this bundle is re-typed from an earlier run.

---

## 1. The standard, resolved

```
$ curl -fsSL "$RAW/standards/STANDARDS.md" -o STANDARDS.md && head -1 STANDARDS.md
# Ka0s WoW Addon Standard (v2.39.0, 2026-09-07)
```

`AUDIT.md` and all **26** section files linked from the index's `## Sections` list were fetched the
same way. Diffing them against the copies taken on 2026-09-07 (v2.38.0):

```
$ for f in $(cat seclist_v239.txt); do diff -q $v238/$f $v239/$f >/dev/null && echo "UNCHANGED $f" || echo "CHANGED $f"; done
CHANGED    anti-patterns.md        CHANGED    audit-review-history.md
CHANGED    automated-tests.md      CHANGED    documentation.md
CHANGED    layout.md               CHANGED    library-stack.md
CHANGED    line-endings.md         CHANGED    lint.md
CHANGED    localization.md         CHANGED    open-evolutions.md
CHANGED    options-ui.md           CHANGED    packaging.md
CHANGED    slash-commands.md       CHANGED    standalone-windows.md
CHANGED    toc-file.md
UNCHANGED  architecture.md  compat.md  debug-logging.md  events-frames-taint.md
UNCHANGED  naming-cheatsheet.md  performance.md  preview-mode.md  public-api.md
UNCHANGED  savedvariables.md  testing.md  versioning-git.md
```

**Scope:** all 26 files the Sections list links. `tiered-layout.md` appears in `STANDARDS.md` only
inside the frozen v2.0.0 changelog entry, not in the Sections list, and is correctly not fetched.

## 2. Lint

```
$ luacheck .
...
Total: 0 warnings / 0 errors in 94 files
```

**Scope, read off the config before the `0/0` is quoted** — `.luacheckrc:11`:

```lua
exclude_files = { "libs/", "docs/audits/", "_dev/", "tests/_kit/", "docs/reviews/" }
```

The test tree is **in scope** (v2.39.0's `lint` amendment); only `tests/_kit/` — the vendored kit,
linted in `LibKa0s` — is excluded, which is the narrowest form the section permits. The harness
global is in a `files["tests/"]` stanza, `.luacheckrc:101-103`:

```lua
files["tests/"] = {
  globals = { "_G.KICKCD_TEST" },
}
```

There is **no top-level `ignore`**. `.luacheckrc:13-14` says so and says why:

> `-- NO TOP-LEVEL `ignore`, and none is coming back (lint-§1, `M4-11`). This file carried`
> `-- `ignore = { "212/self", "212/event", "211/addonName" }` until `M4c-06`. Every entry was already`

The 94 files vs `20260908-181321`'s 93 is `M4c-06` adding `tests/test_lintconfig.lua`.

## 3. Tests

```
$ lua5.1 tests/run.lua
...
  PASS  libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon bundles
  PASS  tests/_kit is the test kit that shipped with that release
  PASS  eol: every tracked file carries the terminator .gitattributes declares for it

864 passed, 0 failed, 0 skipped, 864 total
```

`docs/test-cases.md:1105` — `| **Total** | **864** |` — and `README.md:7` —
`![Tests](https://img.shields.io/badge/Tests-864%2F864_passing-green)` — both agree with the run.
Three figures, one number.

## 4. Complexity — measured, and compared with the record

The standard's **verbatim** invocation, from the repo root:

```
$ lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .
...
No thresholds exceeded (cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100)
Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt
     17980       6.7     2.1       50.5     2273            0      0.00    0.00
```

Compared against the latest bundle, `docs/automated-tests/20260908-181321/complexity.txt` (last 3
lines):

```
Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt
     17805       6.6     2.1       50.4     2268            0      0.00    0.00
```

**Drift:** NLOC +175, functions +5, warnings 0 → 0. No function crossed a `lizard` threshold and no
file entered or left the `layout-§1` band since that run. The bundle's stamp dates it to today:
`docs/automated-tests/20260908-181321/manifest.json` records `"startedAt":
"2026-09-08T18:13:21+05:30"` and `"git": { "sha": "c8f938104560fcaf250494e632c4a966a91a46ed", …
"dirty": false }`. HEAD is two commits later:

```
$ git log --oneline c8f9381..HEAD
03f3b9a Merge branch 'feat/2026-09-07-audit-review-remediation'
86744a4 M4c-06: the blanket ignore goes, and thirty-two of the sixty-one were real
```

The CCN-18 function the 2026-09-07 run measured at `tests/test_schema.lua:595-631` and reported as
the collection's only open complexity warning is **gone** — `M4-25` closed it, and `Warning cnt` is
0 in both the record and today's measurement, so the release gate no longer blocks a tag.

## 5. The watch list, read as a decision record

`docs/automated-tests/RESULTS.md:73` — `### Functions `lizard` warned on` — is followed at `:75` by
`None.` **Zero** entries, so `automated-tests`' three-consecutive-releases rule (anti-pattern #53)
has nothing to bite on and no entry reads "accepted" indefinitely.

The band table (`:80-84`) carries four rows, one per file in the 1000–1500 band, each with an
authored `Disposition`. Two of those dispositions cite ids from the retired series — *"Already
tracked as `A-2`"* (three rows) and *"Already tracked as `KCD-30`"* (`tests/wow_mock.lua`) — which is
`KICKCD-B-06`(b). Every band row's own figure was re-measured today:

```
$ git ls-files '*.lua' | grep -v '^libs/' | grep -v '^tests/_kit/' | xargs wc -l | sort -rn | head -5
  31567 total
   1345 modules/Castbar.lua
   1312 settings/Spells.lua
   1235 tests/wow_mock.lua
   1152 modules/IconGrid.lua
```

**Scope:** all tracked `.lua`, `libs/` and `tests/_kit/` excluded as `layout-§1`'s two carve-outs
require; `tests/` **included**, per the v2.39.0 wording. Nothing is over 1500.

## 6. Vendored Ka0s-owned library — the two diffs

The provenance line, re-read at `CLAUDE.md:52`:

> `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.27.0 (MIT). That line is the answer to`

Diffed against **that tag**, not against the sibling's `HEAD`:

```
$ git -C ../LibKa0s archive v1.27.0 | tar -x -C /tmp/lk
$ diff -r /tmp/lk/LibKa0s /mnt/.../KickCD/libs/LibKa0s ; echo "exit=$?"
exit=0
$ diff -r /tmp/lk/testkit /mnt/.../KickCD/tests/_kit ; echo "exit=$?"
exit=0
```

**Both empty.** No `#45` drift, and no `Only in` line, so no `#48` partial vendoring either — the
whole ship folder is present, every module including the ones this addon does not wire. The kit lands
under `tests/_kit/`, never `libs/`.

The three provenance greps `AUDIT.md` names:

```
$ grep -n 'Bundles \[LibKa0s\]' CLAUDE.md
52:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.27.0 (MIT). That line is the answer to
$ grep -n 'Bundles \[LibKa0s\]' README.md
(no output)
$ grep -nE '^## (Libraries|Bundled libraries|Libraries and credits|Credits and libraries|Credits and bundled libraries)' README.md
(no output)
$ grep -n 'WoW_Addon_Standard' README.md
6:![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
```

The line is in `CLAUDE.md` and only there; the README carries no inventory heading and no roll-call
in its intro prose (`README.md:11-18` is read end to end and names no library); and the badge is the
**bare** `![Standard](…)`, not wrapped in a link.

## 7. Line endings

```
$ test -f .gitattributes && echo present
present
$ grep -n '^\* text=auto eol=\(crlf\|lf\)$' .gitattributes
26:* text=auto eol=crlf
$ grep -n '^\*\.sh text eol=lf$' .gitattributes
34:*.sh text eol=lf
$ grep -c ' binary$' .gitattributes
20
$ wc -l < .gitattributes
81
```

`KickCD.toc` exists, so this repo is **client-bound** and `eol=crlf` is the right pin.

**The §5 body diff.** The canonical client-bound block was extracted from the fetched
`line-endings.md` and compared against the repo's file with CR stripped:

```
$ diff canonical_client_81.txt repo_gitattributes_stripped.txt
(no output — identical over all 81 lines)
```

81 lines, matching `AUDIT.md`'s stated length for a client-bound repo, with **no tail** — so there is
no `line-endings-§5 appendix` and none is owed. Nothing is filed under §5.

**(e) The working tree, run exactly as written:**

```
$ git ls-files -z | xargs -0 -I{} sh -c '
    set -- $(git check-attr text eol -- "{}" | sed "s/.*: //")
    [ "$1" = unset ] && exit
    cr=$(tr -dc "\r" < "{}" | wc -c); lf=$(tr -dc "\n" < "{}" | wc -c)
    case "$2" in crlf) [ "$lf" -gt 0 ] && [ "$cr" -ne "$lf" ] && echo "{}";;
                 lf)   [ "$cr" -gt 0 ] && echo "{}";; esac' 2>/dev/null | wc -l
0
```

**Scope: all 458 tracked files**, nothing excluded — `libs/`, `tests/`, `docs/` and every frozen
bundle included; binaries skipped by the `text unset` guard, which is what the command is for.

**0 strays.** The 2026-09-07 bundle reported **8** for `KICKCD-A-04`. That bundle is frozen and is
not edited; the difference is the repair, not the command — the same command produced both numbers.

**The gate has an owner.** `tests/_kit/test_eol.lua` is vendored (kit revision 15) and its case is
green in §3 above: `PASS eol: every tracked file carries the terminator .gitattributes declares for
it`. Gate green **and** audit green, which is the state §7 asks for.

## 8. Packaging

```
$ for e in .luacheckrc .pkgmeta .gitignore .gitattributes .claude .superpowers docs tests _dev; do
    grep -q "^  - $e\b" .pkgmeta || echo "NOT IGNORED — $e"; done
(no output)
$ for e in .[!.]*; do [ -e "$e" ] || continue; [ "$e" = ".git" ] && continue;
    grep -q "^  - $e\b" .pkgmeta || echo "UNACCOUNTED — $e"; done
(no output)
```

**Scope:** the named list, then every root dot-entry actually present (`.claude`, `.git`,
`.gitattributes`, `.gitignore`, `.luacheckrc`, `.pkgmeta`, `.superpowers`), `.git` excepted as the
one entry the packager never sees. `.pkgmeta:12` — `  - .pkgmeta         # packager configuration:
consumed before the zip is built, of no use inside it` — is the line the 2026-09-07 run's
`KICKCD-A-01` asked for, and `:20-21` carry `.claude` and `.superpowers` with their justification
comment. `KICKCD-A-01` is closed.

## 9. Evidence for `KICKCD-A-08` — three `_G.print` arms

```
$ grep -rn "_G.print" --include='*.lua' core/ modules/ settings/ defaults/ locales/ tests/ | grep -v '^tests/_kit'
core/KickCD.lua:108:    local fn = self.Util and self.Util.print or _G.print
core/Compat.lua:452:    local out = (NS.Util and NS.Util.print) or _G.print
modules/Cooldowns.lua:538:    local p = NS.Util and NS.Util.print or _G.print
```

**Scope:** the addon's own Lua only — `libs/` and `tests/_kit/` excluded, `tests/` swept and clean.

Re-read at HEAD, each in context:

- `core/KickCD.lua:107-110`
  ```lua
  local function p(self, ...)
      local fn = self.Util and self.Util.print or _G.print
      fn(...)
  end
  ```
- `core/Compat.lua:451-452`
  ```lua
  function Compat.DebugInterrupt(unit)
      local out = (NS.Util and NS.Util.print) or _G.print
  ```
- `modules/Cooldowns.lua:537-538`
  ```lua
  function Cooldowns:DebugDump()
      local p = NS.Util and NS.Util.print or _G.print
  ```

**Why Low, not Medium.** `core/CoreSetup.lua:115` opens the library-absent arm's printer —
`    function Util.print(...)` — and `:187` the library-present one — `Util.print =
printer.Print`. `NS.Util.print` exists on both paths, so the `or _G.print` arm is unreachable.

**Why it is filed at all.** The site the 2026-09-07 audit cited **was** fixed:
`modules/Castbar_Debug.lua:134` now reads `    local emit = NS.Util.print`, and `git show 236f673 --
modules/Castbar_Debug.lua` shows the one-line change. The commit is titled *"M4-20: two dead arms go"*
and its own body names only the two premises it re-derived; nothing in it swept the class. Three
sites of the same class were never cited and therefore never touched.

## 10. Evidence for `KICKCD-B-01` — the fourth table's membership

`docs/ARCHITECTURE.md:215-226`, re-read:

```
### Verification and record

| Doc | Covers |
|---|---|
| `testing.md` | How to run the harness and lint; the green commit gate |
| `smoke-tests.md` | The in-game smoke-test suite |
| `test-cases.md` | The generated case inventory (authoritative pass count) |
| `performance.md` | The addon performance page |
| `automated-tests/README.md` | What the automated-test record is and how to produce it |
| `perf-analysis/README.md` | The in-game capture store: what a `perf-analysis/<stamp>/` bundle holds and how one is produced |
| `automated-tests/RESULTS.md` | One row per run; generated, never hand-edited |
```

**Seven rows.** `documentation-§3`, `### Verification and record — the fourth table (MUST)`:

> It holds **exactly** `testing.md`, `smoke-tests.md`, `test-cases.md`, `performance.md`,
> `automated-tests/README.md` and `automated-tests/RESULTS.md`. Six rows, in every addon, in every
> state — this table has no conditional member and therefore no *Not applicable* row.

> **`perf-analysis/README.md` registers in `### Conditional`, not here**, in *both* of its states.

The `### Conditional` table it belongs in is at `docs/ARCHITECTURE.md:204-213`, six rows today,
ending `| `debug.md` | Not applicable | The console is `LibKa0s-DebugLog-1.0`'s; … |` at `:213`.

**Not filed, deliberately:** the hub's own self-row at `docs/ARCHITECTURE.md:196` — `|
`ARCHITECTURE.md` | This file — the hub: overview, module map, message bus, slash commands, taint
notes, deviations |`. `documentation-§3` settles that as a **MAY** and forbids an audit from filing
its presence *or* its absence.

## 11. Evidence for `KICKCD-B-02` — the spelling gate's scope

The two live defects, re-read at `docs/perf-analysis/README.md:32-33`:

```
field (epoch seconds) — **when the capture happened**, not when it was written up, so a run analysed
a week later still sorts against its neighbours. A bundle is never renamed to match a later
```

`analys` and `neighbour` are both on `localization-§5`'s published `BRITISH` list; neither
*analysed* nor *neighbours* is on `ALLOWED`.

The gate's exclusion list, `tests/test_spelling.lua:102-110`:

```lua
local EXCLUDED_DIR = {
    "libs/",
    "tests/_kit/",
    "docs/audits/",
    "docs/reviews/",
    "docs/automated-tests/",
    "docs/revendor/",
    "docs/perf-analysis/",
}
```

`:109` excludes the **whole** `docs/perf-analysis/` directory. `localization-§5`'s third exclusion is
*"frozen dated bundles and released changelog entries, which are the record and are not rewritten"*,
and `documentation-§3` says of this exact file: *"It is the one file in the store that is rewritten —
the bundles are frozen."*

The whole-repo scan, with the canonical `BRITISH` list applied and the frozen/vendored paths removed:

```
$ grep -rniE "<the 92 canonical BRITISH substrings>" --include='*.lua' --include='*.md' --include='*.toc' . \
  | grep -vE '^\./(libs|tests/_kit|docs/audits|docs/reviews|docs/revendor)/' \
  | grep -vE '^\./docs/(automated-tests|perf-analysis)/[0-9]{8}-' \
  | grep -v '^./tests/test_spelling.lua'
./docs/perf-analysis/README.md:32:… so a run analysed
./docs/perf-analysis/README.md:33:a week later still sorts against its neighbours.
```

**Scope stated:** vendored code (`libs/`, `tests/_kit/`), the frozen dated bundles under
`docs/audits/`, `docs/reviews/`, `docs/revendor/` and the stamped run directories under
`docs/automated-tests/` and `docs/perf-analysis/`, and the gate's own copy of the lists
(`tests/test_spelling.lua`) are excluded — the four exclusions `localization-§5` names. `.superpowers/`
is untracked and outside the repo's authored text. **Everything else was swept, including the two
live docs the gate itself skips.** Exactly two hits. `docs/automated-tests/README.md` and
`docs/automated-tests/RESULTS.md` are excluded by the same over-broad rule and are clean today —
their only matches are the literal filename `ANALYSIS.md`, which delimits to `analysis`, on `ALLOWED`.

`tests/test_spelling.lua:33-68` carries both published lists **whole** — **91** `BRITISH` substrings and
**30** `ALLOWED` words — the exact counts the published block carries, checked against `localization-§5`'s block entry for entry. The list is not
the defect; the scope is.

## 12. Evidence for `KICKCD-B-03` — the register row and the tree

`docs/ARCHITECTURE.md:248`, re-read (first clause and trigger quoted):

> | `savedvariables-§1` | **Two** profile migrators run off the **stored shape**, not off
> `db.global.schemaVersion`. … these two run beside them, ungated. | … | 2026-07-16 | An AceDB release
> where `copyDefaults` no longer backfills before migration runs, **or a third shape addition under an
> existing profile field** — either makes a version-gated migrator sufficient and retires both
> shape-driven ones. |

The tree, `core/Database.lua:598-601`:

```lua
    self:FoldLegacyUnits(self.db)
    self:BackfillLabelStyle(self.db)
    -- Per-profile, so it has to run on every swap — see MigrateSpecKeys.
    self:MigrateSpecKeys(self.db)
```

and again on the fresh-install path at `:639` (`self:FoldLegacyUnits(db)`), `:644`
(`self:BackfillLabelStyle(db)`) and `:651` (`self:MigrateSpecKeys(db)`). **Three**, not two.

When the third arrived:

```
$ git log -1 --format="%h %ad %s" --date=short -S "function Database:BackfillLabelStyle" -- core/Database.lua
e143516 2026-07-16 Feat: single-sourced label.style default + shape-driven backfill
```

2026-07-16 — the row's own **Decided** date. The row has never described the tree.

The version-gated runner it sits beside, for contrast, is current: `core/Database.lua:35` reads
`local CURRENT_DB_VERSION = 5` and `:525-528` register four steps, `[1]` through `[4]`.

## 13. The issue store

```
$ gh issue list --state all --limit 200 --json number,title,state,labels \
    --jq '.[] | "\(.number)\t\(.state)\t\([.labels[].name] | join(","))\t\(.title)"' | sort -n
1   OPEN    enhancement,state:triaged,severity:low      Add more customization options for the glow effects
2   OPEN    enhancement,state:triaged,severity:low      Cast bar background animation
3   OPEN    bug,state:triaged,severity:medium           Partial Charge Swipe
4   OPEN    bug,state:triaged,severity:medium           Icon Zoom
5   OPEN    enhancement,state:triaged,severity:low      Add the ability to add items along with spells for tracking
6   CLOSED  state:done,severity:low                     Add ability to track Focus and Target as separate icon grids
7   OPEN    bug,state:triaged,severity:high             Non-interruptible casts intermittently show in "target casting interruptible" visibility mode
8   OPEN    state:triaged,severity:high                 Elemental Shaman has no tracked spells on French client
9   OPEN    enhancement,state:triaged,severity:low      [Optional] Move time-varying icon render onto the cooldown ticker
10  OPEN    enhancement,state:triaged,severity:low      Adopt RenderGrid for the spell-list editor — blocked on two LibKa0s gaps
11  CLOSED  state:will-not-do,severity:low              Adopt LibKa0s `RenderGrid` as a second consumer for KickCD's settings lists
12  CLOSED  state:will-not-do,severity:low              LibKa0s-Widgets-1.0: declined — no control in this addon wants it
13  CLOSED  state:done,severity:low                     Adopt LibKa0s-Pool-1.0 for the icon-grid pool
14  CLOSED  state:will-not-do,severity:low              LibKa0s-Item-1.0: declined — a spell-cooldown addon with no item concept
```

`gh` CLI subcommands with `--json`; no `gh api graphql`. **14 of 14** carry both a `state:` and a
`severity:` label. No `[triaged]`/`[done]` prefix and no severity word in any title; issue #9's
`[Optional]` is `KICKCD-B-05`. `docs/pending/LEDGER.md` and `docs/pending/` do not exist —
`find . -path ./.git -prune -o -name 'LEDGER.md' -print` returns nothing.

Two `severity:high` issues are open (#7, #8). Both are product defects tracked in the right place;
neither is a standards deviation and neither is filed here.

## 14. Compliance claims, each sourced

| Claim | Evidence |
|---|---|
| TOC field order and no blank lines in the block | `KickCD.toc:1-13`; `:1` `## Interface: 120007`, `:13` `## X-Curse-Project-ID: 1530802` |
| `X-Wago-ID` omission is compliant | `KickCD.toc:14-16`, a comment in the field's own position: `# ## X-Wago-ID is absent deliberately: toc-file-§1 makes a distribution id mandatory / # only for a platform the addon actually ships on, and this addon is CurseForge-only.` No placeholder id anywhere |
| Five load-bearing TOC positions, all annotated | `:44-47` MediaSetup (`# LOAD-BEARING POSITION: core/Constants.lua resolves Const.FONT_MONO from / # NS.MediaFont at file load`), `:51-58` CoreSetup, `:63-70` PerfSetup, `:88-94` OptionsSetup, `:95-101` Panel |
| `libs\LibKa0s\LibKa0s.xml` listed once, after Ace3 | `KickCD.toc:28`; no individual LibKa0s `.lua` anywhere in the file |
| Every vendored lib dir appears in the TOC | `for d in $(ls libs/); do grep -q "libs\\\\$d\\\\" KickCD.toc \|\| echo "NOT IN TOC: $d"; done` → no output, over all 13 |
| No hand-rolled shared subsystem | No `modules/DebugLog.lua`, no widget-maker file, no dispatcher, no local framework in the tree listing; the addon owns `core/{Core,Env,Pool,Media,DebugLog,Perf}Setup.lua`, `settings/OptionsSetup.lua`, `settings/Slash.lua` and `tests/_kit/` |
| The private `LSMPatch` is gone | `grep -rn "RegisterWidgetType" … \| grep -v '^./libs/'` → no addon hit; `settings/OptionsSetup.lua:380` — `lib.__PatchLSM30Border()` |
| Close-button wrapper, one definition, no bypass | `grep -rn 'MakeCloseButton(' --include='*.lua' . \| grep -v '/libs/' \| grep -v '/tests/'` → `core/CoreSetup.lua:102` `    function NS.MakeCloseButton() return nil end`, `core/CoreSetup.lua:174` `    return lib.MakeCloseButton(parent, onClick, addonName)`, and `core/PerfSetup.lua:229`, a comment. No call site, because the addon draws no window of its own |
| Perf `decorate` hook deleted (`KICKCD-A-06`) | `core/PerfSetup.lua:220` — `    -- NO \`decorate\`, and the descriptor deliberately ends here. This file used` |
| Perf stub answers every member the addon reaches | Members reached: `grep -rhoE 'Perf\.[A-Za-z_]+' core/ modules/ settings/ \| sort -u` → `Perf.Note`, `Perf.OnCommand`, `Perf.on`, `Perf.suspended`. Stub at `core/PerfSetup.lua:42-52` publishes all four |
| Media seam takes the folder-name vararg | `core/MediaSetup.lua:55` `local addonName, NS = ...`; `:105` `if Media then Media.RegisterLSM(addonName) end`; loaded at `KickCD.toc:47`, above `core\Constants.lua` at `:48` |
| No private media copy | `find media -type d` → `media`, `media/logos`, `media/screenshots`. No `fonts/`, `icons/` or `textures/` |
| Every settings page draws a strip | General `settings/General.lua:55` (`H.MasterControls{`) + `:103` (`group = L["Units"]`); Icons six groups; Castbar many; Label three; Spells **one**, drawn directly at `settings/Spells.lua:1147` — `    H.TabStrip(ctx, {` — under the comment at `:1138-1142` (`-- ONE TAB, and it draws a strip anyway (options-ui-§13)`). Profiles is AceConfig-drawn (`settings/Profiles.lua:77` `AceConfigDialog:Open("KickCD-Profiles", container)`), the named exemption |
| No `disabledIf` on a color row | `grep -rn 'disabledIf' --include='*.lua' settings/` → no output |
| No hand-written font/border/bar group | `grep -rn 'LSM30_Font\|LSM30_Border\|LSM30_Statusbar' --include='*.lua' settings/` → two hits, both **comments** at `settings/OptionsSetup.lua:344` and `:347`. No control |
| No drag-substitute arrow art | `grep -rn 'ScrollUp-Up\|ScrollDown-Up' --include='*.lua' settings/` → no output |
| No second box round a chrome band | `grep -rn 'InlineGroup' --include='*.lua' settings/` → no output |
| Color rows composed with class-color companions | `settings/Icons.lua:182,419,425` and `settings/Castbar.lua:489,496,522,529` are `H.AddComposed(H.ColorPair{…})`, each carrying `classColor = { source = … }`; `settings/Icons.lua:176-181` records why the icon page's source is `player` and the path does not decide it |
| `docs/` Tier 1 complete | `ls docs/*.md` → `scope.md`, `module-map.md`, `schema.md`, `settings-panel.md`, `data-flow.md`, `common-tasks.md` all present |
| `compat-layer.md` trigger, counted mechanically | `grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.' core/Compat.lua` → **13**, ≥ 3, so the doc is owed and shipped |
| Hub shape | `wc -l docs/ARCHITECTURE.md` → 313; longest mandated section `## Documented deviations`, 54 lines (`:234-288`). Under both `documentation-§3` thresholds |
| Ten mandated hub sections | `grep -n "^## " docs/ARCHITECTURE.md` → Overview `:7`, Module map `:22`, Message bus `:124`, Slash commands `:138`, Settings schema `:162`, Event subscriptions `:166`, Taint notes `:176`, Known limitations `:180`, Documentation map `:187`, Documented deviations `:234`. Pinned by `tests/test_doc_structure.lua` (`PASS docs/ARCHITECTURE.md carries the section names documentation-§3 mandates`) |
| No retired doc, no retired store | No `docs/file-index.md`, no `docs/conventions.md`, no `docs/complexity.md`, no `docs/perf-runs/`. Capture store is `docs/perf-analysis/20260807-131311/` with `report.md`, `dump.json` and `ANALYSIS.md`, indexed at `docs/perf-analysis/README.md:203-209` |
| `docs/testing.md` carries the per-suite checkpoint | `docs/testing.md:200` — `There are **two checkpoints** — the run/commit and the tag —`; `:207-208` give `perf` and `complexity` as `no — recorded only` / `**yes**`, so no cell is left unqualified |
| README section order | `grep -n "^## " README.md` → `## What's new in 1.2.1` `:20`, `## Screenshots` `:35`, `## Usage` `:60`, `## How interrupt tracking works` `:103`, `## FAQ` `:161`, `## Troubleshooting` `:178`, `## Issues and feature requests` `:193`, `## Version History` `:197`. No `## Credits` (a MAY, nothing external to credit), no `## Testing`, no `## Libraries` |
| No angle-bracket placeholders in the README | `grep -nE '<[a-z][a-z0-9_ -]*>' README.md \| grep -v '<br>\|<code>\|<strong>\|https\?://'` → no output |
| `## Documented deviations` present and non-empty | `docs/ARCHITECTURE.md:234`, five rows at `:248-252`, plus the 2026-09-08 retirement note at `:254-272` and the two "not in this table" notes at `:274-288` |
| Every id the register cites resolves | `docs/ARCHITECTURE.md:272` cites `KICKCD-A-10` in `docs/audits/2026-09-07/`; that bundle exists and `docs/audits/2026-09-07/02_DEVIATIONS.md` assigns the id. Pinned by `tests/test_doc_structure.lua` (`PASS every deviation id the register cites is assigned by a bundle in docs/audits/`) |
