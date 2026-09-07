# KickCD — Evidence (2026-09-07)

Every citation below was **re-read at the line it names** before this file was written, and the
cited text is quoted beside it. Every count was produced by the command shown, run today from the
repo root, with its **scope** stated — what it swept and what it did not.

---

## 1. Standard resolution

```
$ RAW=https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master
$ curl -fsSL "$RAW/AUDIT.md" -o AUDIT.md && wc -l AUDIT.md
515 AUDIT.md
$ curl -fsSL "$RAW/standards/STANDARDS.md" -o STANDARDS.md && head -1 STANDARDS.md
# Ka0s WoW Addon Standard (v2.38.0, 2026-09-02)
$ grep -oE '\(standards/[a-z0-9-]+\.md\)' STANDARDS.md | tr -d '()' | sort -u | wc -l
26
```

All 26 linked section files fetched to `sec/<name>.md`, 4438 lines total, none failing. Discovered by
following the Sections list, not hard-coded.

## 2. Suites, as run today

```
$ luacheck .
Total: 0 warnings / 0 errors in 36 files
```

```
$ lua tests/run.lua | tail -1
841 passed, 0 failed, 0 skipped, 841 total
```

Scope: `luacheck .` covers the addon's own shipped source only — `.luacheckrc:4` reads
`exclude_files = { "libs/", "docs/audits/", "_dev/", "tests/", "docs/reviews/" }`, so the 52 files
under `tests/` and everything under `libs/` are **not** linted. `lua tests/run.lua` covers `tests/`
plus every addon file it loads under the mock.

## 3. Vendored Ka0s-owned library — the two diffs

Provenance line, re-read at the line:

```
$ grep -n 'Bundles \[LibKa0s\]' CLAUDE.md
52:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.25.0 (MIT). That line is the answer to
$ grep -n 'Bundles \[LibKa0s\]' README.md
(no output)
```

Sibling repo present at `../LibKa0s`. Both payloads compared **against the tag `CLAUDE.md` names**,
v1.25.0, not against `HEAD`:

```
$ git -C ../LibKa0s archive v1.25.0 | tar -x -C /tmp/lk
$ diff -r /tmp/lk/LibKa0s  ./libs/LibKa0s   ; echo "exit=$?"
exit=0
$ diff -r /tmp/lk/testkit  ./tests/_kit     ; echo "exit=$?"
exit=0
```

Both empty. No anti-pattern #45 drift and no #48 partial vendoring. `tests/_kit/` is under `tests/`,
not `libs/`, as testing requires. The TOC lists the aggregate once:

```
$ sed -n '26p' KickCD.toc
libs\LibKa0s\LibKa0s.xml
```

The repo's own gate agrees, from today's run: `PASS libs/LibKa0s is the LibKa0s release CLAUDE.md
says this addon bundles` and `PASS tests/_kit is the test kit that shipped with that release`.

## 4. `.gitattributes` — checks (a) through (d)

```
$ test -f .gitattributes && echo present
present
$ grep -n '^\* text=auto eol=\(crlf\|lf\)$' .gitattributes
26:* text=auto eol=crlf
$ grep -n '^\*\.sh text eol=lf$' .gitattributes
34:*.sh text eol=lf
$ grep -c ' binary$' .gitattributes
20
```

The repo is client-bound (it has a `.toc` and ships Lua to the client), so `eol=crlf` is the correct
pin. Body compared against `line-endings-§5`'s client-bound canonical text as a **diff**, not a
reading:

```
$ diff <(tr -d '\r' < .gitattributes) /tmp/canonical-client-bound.gitattributes ; echo "exit=$?"
exit=0
```

Byte-identical. This is not the `*.sh`-only near-miss §1 names.

## 5. `.gitattributes` — check (e), the working tree · **KICKCD-A-04**

Run verbatim as `AUDIT.md` prints it. Scope: **every tracked file in the repo**, binaries skipped by
the `text=unset` test, `docs/` and `tests/` and `libs/` all included.

```
$ git ls-files -z | xargs -0 -I{} sh -c '
    set -- $(git check-attr text eol -- "{}" | sed "s/.*: //")
    [ "$1" = unset ] && exit
    cr=$(tr -dc "\r" < "{}" | wc -c); lf=$(tr -dc "\n" < "{}" | wc -c)
    case "$2" in crlf) [ "$lf" -gt 0 ] && [ "$cr" -ne "$lf" ] && echo "{}";;
                 lf)   [ "$cr" -gt 0 ] && echo "{}";; esac' 2>/dev/null | wc -l
8
```

**8** tracked files disagree with the declared pin. Reported as one rolled-up finding; the files are
deliberately not listed, because the fix is a single `git add --renormalize .` plus a re-checkout and
a per-file tally would inflate the count for one action. This number is **not** comparable with the
figure in any pre-v2.28.1 bundle for this repo — the old command counted every binary and every JSON
file as a stray. Prior frozen bundles are never edited, so the two numbers stand side by side and
this sentence is the explanation.

## 6. `.pkgmeta` — the two package-ignore sweeps · **KICKCD-A-01**

Scope: the repo root only, which is what `.pkgmeta`'s ignore list addresses.

```
$ for e in .luacheckrc .gitignore .gitattributes .claude .superpowers docs tests _dev; do
    grep -q "^  - $e\b" .pkgmeta || echo "NOT IGNORED — $e"; done
NOT IGNORED — .claude
NOT IGNORED — .superpowers

$ for e in .[!.]*; do [ -e "$e" ] || continue
    grep -q "^  - $e\b" .pkgmeta || echo "UNACCOUNTED — $e"; done
UNACCOUNTED — .claude
UNACCOUNTED — .git
UNACCOUNTED — .pkgmeta
UNACCOUNTED — .superpowers
```

`.git` is the one entry the packager never sees and needs no row. The other three do.

```
$ find .superpowers -type f | wc -l
54
$ find .claude -type f | wc -l
1
$ sed -n '5,12p' .pkgmeta
ignore:
  - .luacheckrc
  - .gitignore
  - .gitattributes
  - docs
  - tests
  - _dev
  - "*.bak"
```

`.superpowers/` holds 25 `review-*.diff` files plus specs, briefs and reports — a multi-file agent
tooling directory that would land inside the packaged AddOn.

## 7. TOC position annotations · **KICKCD-A-02**

The two load-bearing positions, and the fact that makes each load-bearing:

```
$ sed -n '55p' KickCD.toc
core\PerfSetup.lua
$ grep -n '^local Perf = NS.Perf' modules/*.lua
modules/Castbar.lua:72:local Perf = NS.Perf
modules/Cooldowns.lua:66:local Perf = NS.Perf
modules/IconGrid.lua:61:local Perf = NS.Perf
modules/IconGrid_Render.lua:18:local Perf = NS.Perf
```

Four modules resolve `NS.Perf` **at file scope**, so `core\PerfSetup.lua` moving below the
`# Modules` block would leave all four holding `nil` with nothing raised. `KickCD.toc:55` carries no
comment — the line above it is `core\KickCD.lua` and the line below is blank.

```
$ sed -n '73p' KickCD.toc
settings\OptionsSetup.lua
$ grep -n '^local Helpers = NS.Settings.Helpers' settings/*.lua
settings/OptionsSetup.lua:327:local Helpers = NS.Settings.Helpers
settings/Panel.lua:47:local Helpers = NS.Settings.Helpers
settings/Panel_Render.lua:13:local Helpers = NS.Settings.Helpers
settings/Panel_Widgets.lua:30:local Helpers = NS.Settings.Helpers
$ sed -n '56p' settings/Icons.lua
local ANCHOR_VALUES = H.AnchorValues()
```

`settings/Icons.lua:56` calls a Helpers member **at file load**, which is exactly the resolution the
register's own `options-ui-§1` row is about. `KickCD.toc:73` carries no comment.

The contrast — the one position that **is** annotated, re-read at the lines:

```
$ sed -n '42,45p' KickCD.toc
# LOAD-BEARING POSITION: core/Constants.lua resolves Const.FONT_MONO from
# NS.MediaFont at file load, so the LibKa0s-Media-1.0 seam must already be
# published. This line moves only with that one.
core\MediaSetup.lua
$ sed -n '109p' core/Constants.lua
Const.FONT_MONO = (NS.MediaFont and NS.MediaFont(Const.FONT_MONO_NAME))
```

That is the shape §5 requires and the shape the other two lines lack. The reasoning for both missing
comments already exists in prose at `docs/ARCHITECTURE.md:286-311` — items 16 and 20 of the Load
order list — which is why the fix is a move, not new writing.

## 8. Mechanical sweeps

### 8.1 British spelling · **KICKCD-A-03**

Scope, stated: `core/ defaults/ locales/ modules/ settings/ tests/` (excluding `tests/_kit/`, which
is vendored), the **live** `.md` files directly under `docs/`, `docs/perf-analysis/README.md`,
`docs/automated-tests/README.md`, `docs/automated-tests/RESULTS.md`, and the three root docs. **Not**
swept: `libs/`, `docs/audits/`, `docs/reviews/`, `docs/automated-tests/<run>/`,
`docs/perf-analysis/<run>/`, `docs/revendor/`, `docs/superpowers/`, `.superpowers/` — all frozen or
vendored, and editing a frozen bundle is worse than the typo.

```
$ grep -rnoiE '\b(colour[a-z]*|behaviour[a-z]*|grey|centre|cancelled|minimise|maximise)\b' \
    --include='*.lua' --include='*.md' --include='*.toc' \
    core defaults locales modules settings tests docs/*.md \
    docs/perf-analysis/README.md docs/automated-tests/README.md docs/automated-tests/RESULTS.md \
    README.md CLAUDE.md DEPENDENCIES.md | grep -v '/_kit/' | awk -F: '{print $1}' \
  | sort | uniq -c | sort -rn
     20 docs/settings-panel.md
      6 docs/smoke-tests.md
      5 settings/Panel_Widgets.lua
      4 tests/test_settings_spells_editor.lua
      4 docs/module-map.md
      3 tests/test_schema.lua
      3 docs/common-tasks.md
      2 docs/ARCHITECTURE.md
      1 tests/wow_mock.lua
      1 tests/test_options_panel.lua
      1 settings/Panel_Render.lua
      1 locales/enUS.lua
$ … | wc -l
51
```

51 hits, 12 files. The locale hit is a **comment**, not a key — re-read at the line:

```
$ sed -n '81p' locales/enUS.lua
-- the second is the phrase that carries the colour and names where the click
```

so no `L[...]` key changes and no call site moves. A representative doc hit, re-read:

```
$ sed -n '103p' docs/settings-panel.md
## The class-colour companion (`options-ui-§17`)
```

### 8.2 Retired `§N.M` notation — clean

Same scope as 8.1.

```
$ grep -rnoE '§[0-9]+\.[0-9]+' --include='*.lua' --include='*.md' --include='*.toc' \
    core defaults locales modules settings tests docs/*.md \
    docs/automated-tests/README.md docs/automated-tests/RESULTS.md docs/perf-analysis/README.md \
    README.md CLAUDE.md DEPENDENCIES.md KickCD.toc | grep -v '/_kit/' | wc -l
0
```

Zero. Every cross-reference in the live tree uses `filename-§N`.

### 8.3 Close-button wrapper — clean

```
$ grep -rn 'MakeCloseButton(' --include='*.lua' . | grep -v '/libs/' | grep -v '/tests/'
core/CoreSetup.lua:99:    function NS.MakeCloseButton() return nil end
core/CoreSetup.lua:158:    return lib.MakeCloseButton(parent, onClick, addonName)
core/PerfSetup.lua:219:        local close = NS.MakeCloseButton(frame, api.Hide)
```

Three lines: the degraded twin, the **one** wrapper definition supplying `addonName`, and a single
call **to that wrapper**. No direct `lib.MakeCloseButton`, no `NS.DebugLog.MakeCloseButton`. No
anti-pattern #65.

### 8.4 Shared media — clean

```
$ find media -type f
media/logos/kickcd.logo.jpg
media/logos/kickcd.logo.png
media/logos/kickcd.logo.tga
media/screenshots/kickcd.image.01.addon.png   (… 7 screenshots total)
```

Typed subfolders only, and nothing that also exists under `libs/LibKa0s/media/` — no second
JetBrains Mono, no icon copies. The seam is fed the addon's own vararg in `core/MediaSetup.lua` and
loads at `KickCD.toc:45`, before `core\Constants.lua` at `:46`. `SetAtlas` appears twice in
`settings/Spells.lua` (`:764` `atlas = "transmog-icon-remove"`, `:869` `"classicon-"..classFile`) —
both are Blizzard atlases the catalog has no equivalent for, and the file's comment at `:536-538`
says so.

### 8.5 Anti-pattern spot sweeps — all clean

```
$ grep -rn '_G\[addonName\]' --include='*.lua' core modules settings defaults locales   → 0
$ grep -rn 'SLASH_'          --include='*.lua' core modules settings                    → 0
$ grep -rn 'WOW_PROJECT_ID'  --include='*.lua' core modules settings                    → 0
$ grep -n  'externals'       .pkgmeta   → only the comment "NOT fetched as externals."
$ ls libs/embeds.xml TODO.md CHANGELOG.md docs/CHANGELOG.md docs/agent-context.md \
     docs/complexity.md docs/file-index.md docs/conventions.md docs/pending docs/perf-runs
  → all absent
$ grep -rn 'ScrollUp-Up\|ScrollDown-Up' --include='*.lua' settings/                     → 0
$ grep -rn 'disabledIf' --include='*.lua' settings/                                     → 0
$ grep -rn 'LSM30_' --include='*.lua' settings/                                         → 0
```

`LSM30_*` appears only in `core/LSMPatch.lua`, which wraps the vendored widget's registry slot rather
than hand-writing a media control.

## 9. Complexity — measured, and the drift

Run **verbatim**, from the repo root, exactly as `performance-§10` and `CLAUDE.md:96` state it:

```
$ lizard -l lua -x "./libs/*" -x "./tests/_kit/*" . | tail -8
!!!! Warnings (cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100)
  NLOC    CCN   token  PARAM  length  location
      29     18    248      0      37 (anonymous)@595-631@./tests/test_schema.lua
Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt
     17109       6.6     2.1       50.1     2229            1      0.00    0.00
```

The warned function, re-read at the line it starts:

```
$ sed -n '595p' tests/test_schema.lua
test("a linked Focus's tab strip is disabled and desaturated", function()
```

**It is dense guarding, not tangled control flow** — a case walking a schema partition with a run of
`and`/`or` short-circuits, each of which `lizard` counts as a decision. It is also **test** code, not
shipped code.

Compared against the latest committed bundle:

```
$ tail -4 docs/automated-tests/20260825-103417/complexity.txt
No thresholds exceeded (cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 …)
Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt
     15802       6.5     2.1       48.7     2099            0      0.00    0.00
```

**Drift:** +1307 NLOC, +130 functions, and **one function crossed CCN 15** since that run. Staleness
of the run's own stamp: `20260825-103417` is 13 days old and predates the merge that produced the
change —

```
$ git log --oneline -1 --merges
1dca167 Merge branch 'feat/settings-revamp-v2'
```

File LOC bands today, against `layout-§1`:

```
$ find core defaults locales modules settings tests -name '*.lua' -not -path 'tests/_kit/*' \
    | xargs wc -l | sort -rn | head -5
   1320 modules/Castbar.lua
   1296 settings/Spells.lua
   1232 tests/wow_mock.lua
   1152 modules/IconGrid.lua
```

Four files on notice, none over the 1500 cap. The band membership is unchanged from the record; the
LOC figures are not (`RESULTS.md:165` still reads `1305` for `modules/Castbar.lua`).

## 10. The automated-test record · **KICKCD-A-05**, **KICKCD-A-09**

Every line below re-read at the number given.

```
$ sed -n '23p' docs/automated-tests/RESULTS.md
| [`20260825-103417`](20260825-103417/) | 1.2.1 | 0/0 | 35 | 780/780 | pass | 15802 | 2099 | 6.5 | 2.1 | 15 | 0 | **green** |
$ sed -n '36p' docs/automated-tests/RESULTS.md
**756 cases**, zero failed, and — stated explicitly, because a trend line that folds a skip into a
$ sed -n '60p' docs/automated-tests/RESULTS.md
Clean over **33** files as of [`20260807-114618`](20260807-114618/): 0 warnings, 0 errors. The file
$ sed -n '120p' docs/automated-tests/RESULTS.md
Current state as of [`20260807-114618`](20260807-114618/) — not that run's diff.
$ sed -n '135,139p' docs/automated-tests/RESULTS.md
### Functions `lizard` warned on

**None.**

Every function in the addon is at or below CCN 15, so `lizard` warned on nothing — the footer of
```

So three figures in the standing prose (756 cases, 33 lint files, "warned on nothing") are each
contradicted — the first two by the table's own newest row on `:23`, and the third by today's
verbatim `lizard` run. Today's suite is 841, not 756 and not 780.

Bundle inventory and `release` status, read from each manifest:

```
$ for d in docs/automated-tests/2026*/; do python3 -c "…json.load(open('$d/manifest.json'))…"; done
20260804-182144  release=None  ANALYSIS.md=yes
20260804-214315  release=None  ANALYSIS.md=yes
20260804-233245  release=None  ANALYSIS.md=yes
20260807-022824  release=None  ANALYSIS.md=yes
20260807-110522  release=None  ANALYSIS.md=NO
20260807-114618  release=None  ANALYSIS.md=yes
20260825-103417  release=None  ANALYSIS.md=NO
```

No run in the store is a release run, so `automated-tests-§5`'s **MUST** arm has not been triggered
and the two gaps fail its **SHOULD** arm — `20260825-103417`'s numbers moved on every column.

**Watch-list shelf life (anti-pattern #53), checked rather than assumed.** `RESULTS.md:135-137` has
an empty warned-functions table, and all four band rows point at a tracked deviation
(`A-2`, `KCD-30`) rather than reading "accepted":

```
$ sed -n '165p' docs/automated-tests/RESULTS.md
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1305 | **Already tracked as `A-2`.** Unchanged since `20260807-022824`. Watch, no action. |
```

No entry reads a bare *Accepted*, and no run in `git log` on this path is a release run, so the
three-release clock has not started on anything. **Not a #53 finding.**

## 11. Documentation shape (`documentation-§3`) — measured as a directory listing

```
$ ls docs/*.md docs/automated-tests/README.md docs/automated-tests/RESULTS.md docs/perf-analysis/README.md
```

| Tier | Required | On disk |
|---|---|---|
| 1 | `scope.md` `module-map.md` `schema.md` `settings-panel.md` `data-flow.md` `common-tasks.md` | **all six present, exact names** |
| 2 | trigger-gated | `slash-dispatch.md` (15 verbs + 2 subcommand trees — `core/KickCD.lua:156-196`, 15 rows), `midnight-quirks.md`, `compat-layer.md` (`core/Compat.lua` is 496 lines of addon shims), `message-bus.md`, `profiles.md`, `perf-analysis/README.md` (harness wired) — **all present**; `debug.md` **absent with a *Not applicable* row** carrying its trigger at `docs/ARCHITECTURE.md:202` |
| verification | `test-cases.md` `performance.md` `perf-analysis/README.md` `automated-tests/README.md` `automated-tests/RESULTS.md` | **all five present** |
| 3 | free-form | `castbar.md`, `icon-grid.md` — both in the map |

**Non-canonical Tier 1/2 filenames:** none. `data-model.md`, `saved-variables.md`, `pipeline.md`,
`settings-system.md`, `wow-quirks.md`, `slash-commands.md`, `debug-console.md` — all absent.
**Retired docs:** `file-index.md`, `conventions.md`, `complexity.md`, `docs/perf-runs/`,
`docs/pending/` — all absent.

**`## Documentation map`** present at `docs/ARCHITECTURE.md:176`, and its coverage is exact: 21 live
`.md` files under `docs/`, 21 rows, no dangling row. Frozen directories named once each at `:178-179`
rather than enumerated per run.

```
$ find docs -name '*.md' | grep -v 'docs/audits/\|docs/reviews/\|docs/automated-tests/2026\|docs/perf-analysis/2026\|docs/superpowers/\|docs/revendor/' | wc -l
21
```

**Hub shape:** `wc -l docs/ARCHITECTURE.md` → **311**, under the ~400 guidance; no mandated section
exceeds ~60 lines (the longest, `## Documented deviations`, is 62 lines and is a register rather than
spillable prose).

**The two missing section names · KICKCD-A-07**, re-read:

```
$ grep -n '^## ' docs/ARCHITECTURE.md
7:## What it does
22:## Subsystems at a glance
61:## Namespace, naming, and the module publishing pattern
78:## Invariants worth not breaking
91:## External dependencies
113:## Message bus
127:## Slash commands
151:## Settings schema
155:## Event subscriptions
165:## Taint notes
169:## Known limitations
176:## Documentation map
223:## Documented deviations
286:## Load order
```

Eight of the ten mandated names are present verbatim. `## Overview` and `## Module map` are not; the
material is under `## What it does`, `## Subsystems at a glance` and `## Load order`.

## 12. The deviation register and the issue store

```
$ gh issue list --state all --limit 200 --json number,title,state,labels \
    --jq '.[] | "\(.number)\t\(.state)\t\((.labels|map(.name)|join(",")))\t\(.title)"'
14  CLOSED  state:will-not-do,severity:low   LibKa0s-Item-1.0: declined — a spell-cooldown addon with no item concept
13  CLOSED  state:done,severity:low          Adopt LibKa0s-Pool-1.0 for the icon-grid pool
12  CLOSED  state:will-not-do,severity:low   LibKa0s-Widgets-1.0: declined — no control in this addon wants it
11  CLOSED  state:will-not-do,severity:low   Adopt LibKa0s `RenderGrid` as a second consumer for KickCD's settings lists
10  OPEN    enhancement,state:triaged,severity:low
 9  OPEN    enhancement,state:triaged,severity:low
 8  OPEN    state:triaged,severity:high      Elemental Shaman has no tracked spells on French client
 7  OPEN    bug,state:triaged,severity:high
 6  CLOSED  state:done,severity:low
 5  OPEN    enhancement,state:triaged,severity:low
 4  OPEN    bug,state:triaged,severity:medium
 3  OPEN    bug,state:triaged,severity:medium
 2  OPEN    enhancement,state:triaged,severity:low
 1  OPEN    enhancement,state:triaged,severity:low
```

Fourteen issues, **every one** carrying a `state:` label and a `severity:` label, **none** carrying a
`[status]` title prefix (anti-pattern #62 clean). `docs/pending/LEDGER.md` does not exist
(anti-pattern #60 clean).

**The inverse rule — a decline with no register row.** The three `state:will-not-do` closures (#11,
#12, #14) decline **library module adoptions**. `library-stack-§7` states *"Adoption is per module,
on the addon's own schedule. An addon wires only the modules it actually uses"* — so declining `Item`
or `Widgets`-`RenderGrid` is the compliant state, not a departure from a numbered rule, and no
register row is owed. Filing one would be filing compliance in the deviation register, which §3
forbids by name. **No unratified decline found.**

**Register rows against the current standard.** Each of the six rows' cited rules was re-read in the
v2.38.0 section files fetched today: `savedvariables-§1` (unchanged in substance),
`options-ui-§1` (both MUSTs still stand, and still conflict — see `KICKCD-A-10`), `options-ui-§15`
(still mandates the canonical four values, and the composer still takes no `values` override),
`events-frames-taint-§8` (v2.38.0's scoping narrows the **pre-formatting** MUST and does not reach a
diagnostic value column, exactly as the row argues). **No row is a graveyard entry.**

## 13. The provisional row · **KICKCD-A-10**

```
$ sed -n '241p' docs/ARCHITECTURE.md | cut -c1-140
| `options-ui-§1` **(PROVISIONAL — not signed off; see the note below the table)** | The **degraded stub's five schema composers are HOLLOW** …
$ sed -n '260,261p' docs/ARCHITECTURE.md
review, not a ratified deviation, and an audit that re-files it as an open MUST failure is reading
the table correctly.
```

The register instructs this filing in its own words. The measured blast radius is recorded in the
row itself and is confirmed by today's green `PASS the Options stub carries every member the host
calls` in `tests/test_surface_parity.lua`.

## 14. The perf panel decorate hook · **KICKCD-A-06**

```
$ sed -n '217,226p' core/PerfSetup.lua
    decorate = function(frame, api)
        if not NS.MakeCloseButton then return end
        local close = NS.MakeCloseButton(frame, api.Hide)
        -- The factory answers nil where CreateFrame is unavailable — a close
        -- button is worth degrading over, not erroring over.
        if close then
            close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(api.TITLE_H - 18) / 2)
            frame.closeButton = close
        end
    end,
```

The whole body is a close button. The vendored library already does it, at the same anchor:

```
$ sed -n '13p' libs/LibKa0s/PerfPanel.lua
local PANEL_MINOR = 4
$ sed -n '190,196p' libs/LibKa0s/PerfPanel.lua
    else
      local close = core.MakeCloseButton(frame, P.HidePanel, d.addonName or d.name)
      if close then
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(TITLE_H - 18) / 2)
        frame.closeButton = close
      end
    end
```

Panel minor **4** is the revision `AUDIT.md` names as the point the hook stops earning its place. The
hook is a second copy of library behavior that can fall behind it — not a defect today, which is why
it is graded Low.

## 15. The `_G.print` fallback · **KICKCD-A-08**

```
$ sed -n '125p' modules/Castbar_Debug.lua
    local print = NS.Util and NS.Util.print or _G.print
```

Unreachable arm, proved by the definition on both paths:

```
$ grep -n 'function Util.print\|^Util.print' core/CoreSetup.lua
112:    function Util.print(...)          -- the LibKa0s-absent branch
171:Util.print = printer.Print            -- the library-present branch
```

and stated in the repo's own register prose:

```
$ sed -n '281,282p' docs/ARCHITECTURE.md
fallback arm is unreachable today (`core/CoreSetup.lua` defines `Util.print` on **both** the
library-present and library-absent paths, so `NS.Util.print` is never nil), which is why it grades
```

## 16. Options-UI content checks (a)–(i)

- **(a) Every page draws a strip.** Groups per page, in declaration order, from the schema:
  General `Master controls` (composer default, `libs/LibKa0s/OptionsCompose.lua:357`) + `Units`
  (`settings/General.lua:103`); Icons six; Cast bar eight; Text Label three. Spells draws a
  **one-tab strip by hand** at `settings/Spells.lua:1147-1152` because it declares no schema rows.
  Profiles is the AceConfig-drawn exemption; there is no landing-page finding to make, since
  `buildMain` is the library's. **No page fails.** The renderer has no untabbed fallback below a tab
  count — `settings/General.lua:191` calls `H.RenderTabbedSchema` unconditionally.
- **(b) `Master controls` first, canonical rows.** `settings/General.lua:55-71` calls
  `H.MasterControls`, which emits `enabled`, `visibility`, `scale`, `alpha`, `locked`,
  `debugConsole` (`OptionsCompose.lua:360-381`) plus the closing reset pair via `masterTail`. The
  addon **does** draw movable frames (`modules/IconGrid.lua:594` and `modules/Castbar.lua:450` both
  `SetMovable(true)`), so no row may be omitted, and none is. The **value-list** departure is the
  ratified `options-ui-§15` register row; the stored **keys** are untouched
  (`settings/General.lua:63-66` passes `visibility = "target_casting_interruptible"` as a
  `defaults` field, never editing the composer), so there is no stored-type change and no migration
  is owed.
- **(c) Class-color companions.** Every swatch comes from `H.ColorPair` / `H.FontGroup` /
  `H.BorderGroup` / `H.BarGroup`, which emit the companion as the **next** row and stamp
  `classColorSource` on both (`OptionsCompose.lua:157`, `:171`). The intent is declared, not
  inferred from the path — `settings/Icons.lua:175-181` states why the per-unit icon tint is
  `source = "player"`. One resolver, `NS.ResolveColor`, and the unresolvable-class fallback is the
  stored swatch (`docs/settings-panel.md:107`).
- **(d) `disabledIf` on a color row:** zero hits (§8.5).
- **(e) Ordering is a drag:** zero `ScrollUp-Up`/`ScrollDown-Up` hits; `settings/Spells.lua:1058-1059`
  uses `W.ReorderList`, and `:778` records the row-stride arithmetic the widget owns.
- **(f) No hand-written font/border/bar group:** zero `LSM30_*` hits under `settings/`; every group
  is an `H.*Group` call. No hand-rolled colored `Label` heading — `docs/settings-panel.md:42` records
  the test in `tests/test_schema.lua` that scans `settings/` for the gold it would be written in.
- **(g) One chrome block, unboxed:** `settings/Spells.lua:1133-1136`'s `H.PageHeader` is the single
  chrome block, holding the page-wide spec picker and *Add spell*, drawn **above** the strip and not
  wrapped in an `InlineGroup`.
- **(h) Wrapped-strip geometry:** the pitch is measured once from the **inactive** cap atlas on a
  throwaway texture (`libs/LibKa0s/OptionsWidgets.lua:398-401`, `:423-442`), which is the compliant
  form. This is library code; it is audited in the library's own repo, so no finding is filed here.
- **(i) Secondary strip / third level:** no page draws one. Not applicable.

## 17. Prior-run IDs — verified closed, not assumed

| Prior ID | Check run today | Result |
|---|---|---|
| `KCD-30` | `grep -n '_kit/framework' tests/run.lua` → `22:local Kit = dofile(root .. "/tests/_kit/framework.lua")` | closed |
| `KCD-31`/`KCD-32` | `settings/Panel.lua:354` *"`NS.Const.PANEL_PADDING_X` is deleted outright"*, `:394` *"This file used to declare `local ROW_VSPACER = 8`"*; `core/Constants.lua:65` *"PANEL_PADDING_X is deliberately absent"* | closed |
| `KCD-33` | now the ratified `events-frames-taint-§8` register row | accepted |
| `KCD-34` | `tests/perf.lua` exists; five scenarios incl. `probeOverheadOff`/`On` | closed |
| `KCD-35` | `docs/performance.md` and `docs/perf-analysis/README.md` both present | closed |
| `KCD-37` | `grep -n '<setting>\|<value>' README.md` → 0 | closed |
| `KCD-38` | `grep -rn 'SendMessage("Ka0s_KickCD_CONFIG_CHANGED'` → **one** site, `settings/Panel.lua:98` | closed |
| `KCD-40` | pages register via `NS.RegisterOptionsPage` (`settings/General.lua:245-246`) | closed |
| `KCD-41` | `defaults/Profile.lua` exists and is TOC-listed at `KickCD.toc:58` | closed |
| `KCD-42` | `rgba` gone from `modules/Castbar.lua` | closed |
| `KCD-43` | `tests/test_vendor_sync.lua` both cases **PASS against a real sibling read** today | closed |
| `KCD-44` | `docs/testing.md:125-149` states both checkpoints; `CLAUDE.md:96` reads *"recorded at the commit, gating at the tag"* | closed |
| `KCD-45` | `core/DebugLogSetup.lua:102` now `FormatPlain = function(_ts, _tag, msg) return tostring(msg) end` — the line format is gone | closed |
| `KCD-46` | routing fixed; the surviving `_G.print` fallback arm is re-filed as `KICKCD-A-08` | partly open |
| `KCD-47` | the plan file is fixed; the class recurs elsewhere and is re-filed as `KICKCD-A-03` | re-filed |
| `KCD-49` | `modules/IconGrid_Render.lua:938` closes the `cdText` bracket on the early-return arm | closed |
