# KickCD — Technical Design (2026-09-07)

Remediation design for the eleven findings in `02_DEVIATIONS.md`. Keyed by deviation ID. Nothing
here touches addon behavior: **no `.lua` under `core/`, `modules/` or `settings/` changes semantics**
except the one dead-arm deletion in `KICKCD-A-08` and the hook deletion in `KICKCD-A-06`, and both
are covered by existing suites.

## Shape of the work

| Group | IDs | Files touched | Risk |
|---|---|---|---|
| Config and packaging | `KICKCD-A-01`, `KICKCD-A-04`, `KICKCD-A-11` | `.pkgmeta`, `KickCD.toc:14`, whole tree (renormalize) | none to behavior; the renormalize is a one-shot byte rewrite |
| TOC comments | `KICKCD-A-02` | `KickCD.toc` (comments only) | none — comments are not loaded |
| Prose | `KICKCD-A-03`, `KICKCD-A-07` | 12 files (spelling), `docs/ARCHITECTURE.md` (headings) | none; anchors need a sweep |
| Record | `KICKCD-A-05`, `KICKCD-A-09` | `docs/automated-tests/` (a new bundle + `RESULTS.md`) | none |
| Code, small | `KICKCD-A-06`, `KICKCD-A-08` | `core/PerfSetup.lua`, `modules/Castbar_Debug.lua` | low; both covered |
| Upstream | `KICKCD-A-10` | none in this repo | blocked |

---

## `KICKCD-A-01` — `.pkgmeta` ignore list

Three lines into the existing `ignore:` block (`.pkgmeta:5-12`), in the same style as the entries
already there and with a one-line justification comment, since the block already carries one for the
logo masks:

```yaml
  # Agent tooling and session scratch. Both are multi-file directories that
  # would otherwise land inside the packaged AddOn a player downloads.
  - .claude
  - .superpowers
  - .pkgmeta
```

`.pkgmeta` names itself because the enumerate-every-root-dot-entry sweep is the check that does not
go stale, and a packager that reads the file has no need to ship it. `.git` is the one entry that
never needs a row.

**Verification:** re-run both sweeps from `03_EVIDENCE.md` §6; the only remaining line must be
`UNACCOUNTED — .git`.

## `KICKCD-A-02` — TOC load-bearing annotations

Two comments, written in the shape `KickCD.toc:42-45` already uses. The text is a **move** of
prose that already exists at `docs/ARCHITECTURE.md:286-311` items 16 and 20, not new authorship — the
hub then summarizes and the TOC carries the constraint at the line an editor is looking at.

```
# LOAD-BEARING POSITION: modules/Castbar.lua, modules/Cooldowns.lua,
# modules/IconGrid.lua and modules/IconGrid_Render.lua each take
# `local Perf = NS.Perf` at FILE SCOPE, so this seam must be published
# before the # Modules block. Moving it below raises nothing and silently
# disables every bracket.
core\PerfSetup.lua
```

```
# LOAD-BEARING POSITION: this seam IS NS.Settings.Helpers. settings/Panel*.lua
# take it as a file-scope upvalue and settings/Icons.lua:56 calls
# H.AnchorValues() inside a schema-row literal at file load, so every
# settings/<page>.lua must load after this line.
settings\OptionsSetup.lua
```

Then the SHOULD half: one *conventional* note per group — one above the unmarked run
`core\Constants.lua` … `core\KickCD.lua`, and one under the `# Settings` header for the page files —
so no line is left ambiguous between *free to move* and *not yet understood*.

**Risk:** none. Comments do not load. **Ordering:** do this **before** `KICKCD-A-04`, so the
renormalize sweeps a TOC that is already final.

## `KICKCD-A-03` — US-English sweep

Twelve files, five substitutions, case-preserving:

| From | To |
|---|---|
| `colour` / `Colour` | `color` / `Color` |
| `colours` / `Colours` | `colors` / `Colors` |
| `coloured` | `colored` |
| `behaviour` | `behavior` |

Two things make this safe rather than a mechanical risk:

- **No locale key moves.** The single `locales/enUS.lua` hit (`:81`) is a comment. There is no
  `L["…colour…"]` key anywhere, so no `locales/*.lua` file and no call site has to move in the same
  change, and the metatable fallback cannot start rendering a raw key.
- **The heading rename has inbound links.** `docs/settings-panel.md:103` is
  `## The class-colour companion (…)`, so its anchor `#the-class-colour-companion-options-ui-17`
  changes. Sweep `docs/` and `README.md` for that anchor in the same commit.

**Do not touch** `docs/audits/`, `docs/reviews/`, `docs/automated-tests/<run>/`,
`docs/perf-analysis/<run>/`, `docs/revendor/`, `docs/superpowers/`, `.superpowers/` or `libs/`.
Frozen evidence is frozen, and a vendored library is fixed upstream.

**Verification:** the §8.1 command, re-run, must print nothing.

## `KICKCD-A-04` — renormalize the working tree

One-shot, and it is the second half of an adoption that stopped at the file:

```sh
git add .gitattributes
git add --renormalize .
git status                      # review
# then, per straggler still on disk:
rm <path> && git checkout -- <path>
```

`--renormalize` rewrites the **index**, never files already on disk, which is exactly why the count
is 8 with a canonical `.gitattributes` in place. The repo's own `.gitattributes` footer documents the
byte-count verification; use it rather than `file(1)`, which reports nothing about terminators for
JSON or for a one-line file.

**Ordering:** run this **last** among the file-editing steps, so every other change is already in
the tree and gets normalized with it.

**Verification:** the §5 command must print `0`.

## `KICKCD-A-05` / `KICKCD-A-09` — refresh the automated-test record

One command produces the bundle and appends the table row:

```sh
tests/_kit/run-automated-tests.sh
```

Then three edits **outside** the generated parts, because the standing prose sections are
hand-written and are what went stale:

1. **Test suite section** (`RESULTS.md:36-…`) — 841, and say what moved across the
   `20260825-103417` → now gap: the `feat/settings-revamp-v2` merge (`1dca167`), which is the reason
   the count jumped rather than drifted.
2. **Lint section** (`:60-…`) — the new file count, and re-derive the "what those files are"
   paragraph rather than editing its number, since `settings/` grew.
3. **Complexity watch list** (`:120-…`, `:135-141`) — re-stamp *Current state as of*, replace
   **None.** in the warned-functions table with a real row for the CCN-18 anonymous function at
   `tests/test_schema.lua:595-631`, and re-take the four band LOC figures (`modules/Castbar.lua` is
   1320 today, not the 1305 at `:165`).

**The disposition for the new warned function is the design decision here.** It is a **test** file,
and `lizard`'s 18 is dense `and`/`or` guarding rather than tangled control flow. Two honest
dispositions: *accepted, with the shelf-life clock stated* (three consecutive release runs, then it
converts to a tracked ID), or *peel next* — split the case into two, one for the disabled strip and
one for the desaturation. Prefer the peel: the release gate requires **zero** functions above CCN 15,
so as it stands **a tag cut today would be blocked**, and that fact belongs in the analysis
regardless of which disposition is chosen.

Write the run's `ANALYSIS.md` as part of producing it, per the root `AUTOMATED_TESTS.md` prompt.
Do **not** backfill `20260807-110522`'s missing analysis — a bundle is frozen evidence.

## `KICKCD-A-06` — delete the perf-panel `decorate` hook

Remove the `decorate = function(frame, api) … end,` field from the `NS.Perf` descriptor
(`core/PerfSetup.lua:217-226`) and the comment block above it that argues for it. `PerfPanel.lua`'s
`else` arm (`:190-196`) draws the same control, at the same anchor, with `d.addonName or d.name`.
The descriptor passes `name = addonName` (`core/PerfSetup.lua:69`) and **not** an `addonName` field,
so it is the library's `or d.name` fallback that resolves the folder name here — correct today, and
worth naming in the commit message so a future descriptor edit knows which arm it is standing on.

**Risk:** low and visual only. No case in `tests/test_perfsetup.lua` asserts the hook exists, so the
suite will not catch a mistake here — add the panel's close control to the next smoke pass
(`docs/smoke-tests.md`) rather than relying on green.

## `KICKCD-A-08` — drop the dead `_G.print` arm

`modules/Castbar_Debug.lua:125` becomes:

```lua
local print = NS.Util.print
```

`core/CoreSetup.lua` defines `Util.print` on both arms — `:112` (library absent) and `:171` (library
present) — so the fallback can never be taken and the bare form is safe. In the same change, delete
the paragraph at `docs/ARCHITECTURE.md:278-284` that records it as open, since the register is not a
graveyard and the sentence has done its job.

**Characterization:** `tests/test_castbar_debug.lua` already drives this file. Run it before and
after; the output must be byte-identical.

## `KICKCD-A-07` — `ARCHITECTURE.md` mandated section names

Two renames and one decision:

- `## What it does` → `## Overview`.
- `## Subsystems at a glance` → `## Module map`. Its body already summarizes and links to
  `module-map.md`, so it satisfies the spill rule as written.
- `## Load order` — keep it, as a Tier-3-style extra section beneath the mandated ten. It is 26
  lines of genuinely per-addon detail and folding it into `## Module map` would push that section
  past the ~60-line spill threshold, trading one finding for another. State in the new
  `## Module map` that the load order lives below it.

Then sweep `docs/` and `README.md` for anchors into the two renamed headings, and update the
`ARCHITECTURE.md` row in `## Documentation map` if its description names the old sections.

**Not filed, and deliberately not changed:** the map's fourth table (*Verification and record*). The
template shows three, but §3 separately names those five docs as a distinct class, and a fourth table
groups them more honestly than scattering them through the other three. Leave it.

## `KICKCD-A-10` — the provisional register row

**No change lands in this repo.** The conflict is inside `options-ui-§1`: the degradation stub MUST be
load-completing, and it MUST NOT carry a host copy of composed row sets. Both are the standard's, and
the addon cannot satisfy both while the composers live only in `libs/LibKa0s/OptionsCompose.lua`.

Two upstream shapes end it, and the row already names both:

1. **`LibKa0s`** ships the composers in a file that loads and answers **without** the Options major,
   the way `LibStub` itself does. Then the stub inherits real composers and the row retires.
2. **`options-ui-§1`** states which of its two MUSTs wins when a composer moves schema *content*
   behind a library call.

Until one lands, the addon's job is to keep the row honest: `tests/test_options_panel.lua` pins the
exact 112-of-228 delta by fingerprint, so the day the number changes the case says so. Do not
"resolve" this locally by hollowing the composers into the host — that is anti-pattern #73 and the
row exists because someone already reasoned that through.

## `KICKCD-A-11` — the stale TODO marker

Either open a `state:triaged` issue for Wago publication and rewrite `KickCD.toc:14` to cite its
number, or drop the marker and leave the bare comment:

```
# ## X-Wago-ID: <id>   -- add once published on Wago
```

The commented field itself stays; `X-Wago-ID` is a MAY, and the comment is what keeps the omission
reading as a decision rather than an oversight.

---

## Cross-cutting notes

- **Nothing here needs a `## Documented deviations` row.** Every finding is closable by an act of
  this addon except `KICKCD-A-10`, which is already recorded (provisionally) and whose resolution is
  a ruling, not a decision this repo gets to ratify.
- **The green gate holds throughout.** `luacheck .` and `lua tests/run.lua` must be clean at every
  commit; only `KICKCD-A-06` and `KICKCD-A-08` touch executable code, and both are covered.
- **One commit per finding**, except `KICKCD-A-04`, which is deliberately last and alone so the
  renormalize diff is legible in history rather than mixed into a content change.
