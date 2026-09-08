# KickCD — Current State (2026-09-08)

**Addon:** Ka0s KickCD 1.2.1 · **Repo HEAD:** `03f3b9a` (`master`, clean tree)
**Audited against:** **Ka0s WoW Addon Standard v2.39.0 (2026-09-07)** — `standards/STANDARDS.md`
line 1 read `# Ka0s WoW Addon Standard (v2.39.0, 2026-09-07)` when fetched at the start of this run.
**Rule set:** the **addon** set. `KickCD.toc` exists, so `AUDIT.md` step 1's library-repo switch does
not apply.

**How the standard was resolved.** `curl -fsSL` against
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master` for `AUDIT.md`,
`standards/STANDARDS.md`, and **every one of the 26 section files** the index's `## Sections` list
links under `standards/standards/`. No section was read from memory or from a cached copy; the 26
fetched files were diffed against the copies taken on 2026-09-07 (v2.38.0) so this run knows exactly
which rules moved: **15 sections changed** — `anti-patterns`, `audit-review-history`,
`automated-tests`, `documentation`, `layout`, `library-stack`, `line-endings`, `lint`,
`localization`, `open-evolutions`, `options-ui`, `packaging`, `slash-commands`,
`standalone-windows`, `toc-file`.

---

## 1. Layout (`layout`)

Modular, as the standard requires: `core/ defaults/ locales/ modules/ settings/` plus `libs/`,
`tests/`, `docs/`, `media/`. Folder load order in `KickCD.toc` is
`libs/ → locales/ → core/ → defaults/ → modules/ → settings/`.

`layout-§1`'s cap binds **every authored `.lua` the repo tracks, `tests/` included** (new wording in
v2.39.0). Measured at HEAD over `git ls-files '*.lua'` minus `libs/` and `tests/_kit/`:

| File | LOC | Band |
|---|---|---|
| `modules/Castbar.lua` | 1345 | 1000–1500 (on notice) |
| `settings/Spells.lua` | 1312 | 1000–1500 (on notice) |
| `tests/wow_mock.lua` | 1235 | 1000–1500 (on notice) |
| `modules/IconGrid.lua` | 1152 | 1000–1500 (on notice) |

**Nothing is over the 1500 cap.** Four files sit in the on-notice band and all four carry a
disposition in `docs/automated-tests/RESULTS.md`'s band table. No `layout-§1` row is owed.

`media/` holds `logos/` and `screenshots/` only (`media/logos/`, `media/screenshots/`) — no private
`fonts/`, `icons/` or `textures/` duplicating `libs/LibKa0s/media/`. The monospace face and the
113-name icon catalog arrive with the vendored payload; `core/MediaSetup.lua:1-54` records the
migration.

## 2. TOC (`toc-file`)

`KickCD.toc` — 109 lines. Metadata block `:1-13` in the mandated field order, no blank lines inside
it, single `## Interface: 120007`, `## X-License: MIT`, `## X-Standard:` present,
`## SavedVariables: KickCDDB, KickCDPerfDB` (two, the harness being wired).

`## X-Curse-Project-ID: 1530802` is present (`:13`), so `toc-file-§1`'s unpublished carve-out does
not apply. `X-Wago-ID` is **absent with a three-line comment in the field's own position**
(`:14-16`) saying the addon is CurseForge-only — compliant, and the stale `TODO(KCD-18)` marker the
2026-09-07 run filed as `KICKCD-A-11` is gone.

`# Libraries → # Locales → # Core → # Defaults → # Modules → # Settings`, in that order. Every one
of the 13 directories under `libs/` is listed; `libs\LibKa0s\LibKa0s.xml` appears once, after Ace3.

**Load-bearing positions, established by reading the seam files rather than by counting lines**
(`toc-file-§5`'s denominator rule, new in v2.39.0). Five, and **all five are annotated at the line,
naming what resolves**: `:47` `core\MediaSetup.lua` (`Const.FONT_MONO` from `NS.MediaFont`), `:58`
`core\CoreSetup.lua` (`NS.Util.print` vs `core/Util.lua`'s fresh table), `:70` `core\PerfSetup.lua`
(`local Perf = NS.Perf` in four modules), `:94` `settings\OptionsSetup.lua` (`NS.Settings.Helpers`),
`:101` `settings\Panel.lua` (`AddComposed` / `AnchorValues` / `LSMValues`). Two conventional
positions carry their own notes (`:38-40` `EnvSetup`, `:41-43` `PoolSetup`).

What is **not** marked is the rest: `# Locales` (`:33`), `# Defaults` (`:72`), `# Modules` (`:76`,
eight files) and the eight unannotated `# Core` lines carry no per-group *conventional* note. That is
the `toc-file-§5` SHOULD, and it is `KICKCD-A-02`'s surviving half.

## 3. Libraries (`library-stack`)

Vendored and committed under `libs/`: `LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`,
`AceEvent-3.0`, `AceDB-3.0`, `AceDBOptions-3.0`, `AceConsole-3.0`, `AceConfig-3.0`, `AceGUI-3.0`,
`AceGUI-3.0-SharedMediaWidgets`, `LibSharedMedia-3.0`, `LibCustomGlow-1.0`, `LibKa0s`. No
`externals:` in `.pkgmeta`. `AceTimer-3.0` is **not** vendored and is not reached by shipped source
(only mocked, `tests/wow_mock.lua:811`) — compliant under v2.39.0's "mandatory *when used*" wording
for `library-stack-§1`.

`LibKa0s` is vendored **whole**: 14 payload files plus `media/`, matching the ship folder. Root
`CLAUDE.md:52` carries the provenance line — `Bundles [LibKa0s](…) v1.27.0 (MIT).` — and it is in
`CLAUDE.md`, **not** `README.md`. Both `diff -r` gates against tag `v1.27.0` are **empty** (see
`03_EVIDENCE.md` §6).

**The shared subsystems are consumed, not hand-rolled.** The addon owns a descriptor plus a
degradation stub per module and nothing else: `core/CoreSetup.lua`, `core/EnvSetup.lua`,
`core/PoolSetup.lua`, `core/MediaSetup.lua`, `core/DebugLogSetup.lua`, `core/PerfSetup.lua`,
`settings/OptionsSetup.lua`, the slash descriptor in `settings/Slash.lua`, and `tests/_kit/`. There
is no `modules/DebugLog.lua`, no widget-maker file, no dispatcher and no local test framework.

The private `core/LSMPatch.lua` that `KICKCD-R-01` filed is **gone**; `settings/OptionsSetup.lua:380`
calls the library-owned `__PatchLSM30Border` instead (`library-stack-§9`, anti-pattern #76).

**Close-button wrapper.** One wrapper (`core/CoreSetup.lua:174`) and its degraded twin (`:102`). The
grep `grep -rn 'MakeCloseButton(' --include='*.lua' . | grep -v '/libs/' | grep -v '/tests/'` returns
those two plus one comment at `core/PerfSetup.lua:229`. **No call sites** — the addon draws no
standalone window of its own; the console and the perf panel are the library's. No decline is
recorded and none is needed.

## 4. Architecture, SavedVariables, options, slash, debug, compat

- **Architecture.** `AceAddon-3.0:NewAddon(NS, "KickCD", …)` at `core/KickCD.lua`; modules via
  `NewModule`; closed message bus with `NS.NewBusTarget` (`core/KickCD.lua:46`). Five feature
  modules, so `architecture-§4`'s bus condition is met.
- **SavedVariables.** AceDB, `defaults/Profile.lua` the only place a profile default is hardcoded,
  `db.global.schemaVersion` with `CURRENT_DB_VERSION = 5` (`core/Database.lua:35`) and a four-step
  version-gated runner (`:525-528`). **Three** shape-driven migrators also run ungated
  (`core/Database.lua:598-601`) — the register records this at `docs/ARCHITECTURE.md:248` but says
  *two*; see `KICKCD-B-03`.
- **Options.** Built by `LibKa0s-Options-1.0` from a descriptor. Six pages. Every non-exempt page
  draws a tab strip: General (`Master controls` composed by `H.MasterControls`, then `Units`), Icons
  (six groups), Castbar (many), Label (three), Spells (**one** tab, drawn directly at
  `settings/Spells.lua:1147` rather than skipped). Profiles is the AceConfig exemption; the landing
  page is the host's `buildMain`. Colors are composed via `H.ColorPair` with `classColor` on every
  one. No `disabledIf` on any row, no `LSM30_*` control outside a composer, no `ScrollUp-Up` /
  `ScrollDown-Up` reorder art, no `InlineGroup` boxing a chrome band.
- **Slash.** `LibKa0s-Slash-1.0` over `NS.COMMANDS`; 15 verbs with `debug` and `spells` subcommand
  trees; cyan `[KCD]` tag.
- **Debug.** `LibKa0s-DebugLog-1.0` console; descriptor carries `addonName`.
- **Compat.** `core/Compat.lua`, 496 lines, **13** shims by `documentation-§3`'s own grep.

## 5. `.gitattributes` (`line-endings`)

Present at the repo root. 81 lines, and **byte-identical to `line-endings-§5`'s client-bound
canonical body** — `diff` against the extracted canonical file is empty over all 81 lines, with no
tail and therefore no `§5` appendix. Pin recorded verbatim: `* text=auto eol=crlf` (`:26`).
`*.sh text eol=lf` at `:34`. 20 `binary` marks. The working-tree check returns **0**.
`tests/_kit/test_eol.lua` (kit revision 15) is vendored and green.

## 6. Lint, tests, perf, complexity

- `luacheck .` — **0 warnings / 0 errors in 94 files**. `.luacheckrc:11` excludes exactly
  `libs/`, `docs/audits/`, `_dev/`, `tests/_kit/`, `docs/reviews/` — the test tree is **in scope**
  (v2.39.0's `lint` amendment) and the harness global sits in a `files["tests/"]` stanza
  (`.luacheckrc:101-103`), not in top-level `read_globals`. There is **no** top-level `ignore`.
- `lua5.1 tests/run.lua` — **864 passed, 0 failed, 0 skipped, 864 total**.
- `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` — **0 warnings**, NLOC 17980, 2273 functions,
  avg CCN 2.1. The CCN-18 function the 2026-09-07 run measured at `tests/test_schema.lua:595-631` is
  gone.
- Perf harness wired: brackets in `modules/IconGrid.lua`, `modules/IconGrid_Render.lua`,
  `modules/Cooldowns.lua`, `modules/Castbar.lua`; `KickCDPerfDB`; `/kcd perf`; one frozen capture
  bundle at `docs/perf-analysis/20260807-131311/` with all three artifacts, indexed at
  `docs/perf-analysis/README.md:203-209`.

## 7. Packaging (`packaging`)

`.pkgmeta` — `package-as: KickCD`, no `externals:`. Both of `AUDIT.md`'s sweeps return **nothing**:
the named dev-only entries are all ignored, and every root dot-entry present in the repo is
accounted for, `.pkgmeta` itself included. `media/screenshots`, `CLAUDE.md`, `DEPENDENCIES.md` and
the non-`.tga` logos are ignored too, each with its justification comment.

## 8. Root doc set (`documentation-§1/§2/§7`)

- `README.md` — player-facing, sections in the canonical order: H1, badge row, logo, description,
  `## What's new in 1.2.1`, `## Screenshots`, `## Usage` (`### Slash commands`, `### Settings
  panel`), `## How interrupt tracking works`, `## FAQ`, `## Troubleshooting`, `## Issues and feature
  requests`, `## Version History`. No `## Credits` (nothing external to credit — a **MAY**).
  - Standard badge is the **bare** `![Standard](…)` at `:6`, not wrapped in a link.
  - **No bundled-library inventory** — no `## Libraries` / `## Bundled libraries` /
    `## Libraries and credits` heading, and no roll-call in the intro prose.
  - `![Tests](…864%2F864…)` at `:7` agrees with `docs/test-cases.md:1105` (**864**) and with today's
    run.
  - No angle-bracket placeholders anywhere in the file.
- `CLAUDE.md` — stub with `## Standards compliance (read first)`, `## Vendored library provenance`
  (the LibKa0s line at `:52`), `## Hard rules`, `## Local verification (standard testing)`.
- `DEPENDENCIES.md` — present, the WSL2/Ubuntu toolchain contract.
- No `CHANGELOG.md` and no `TODO.md` at the root, and none under `docs/`.

## 9. `docs/` against `documentation-§3`'s tier model

Measured as a directory listing, not read as prose.

- **Tier 1 — all six present**, under exactly the canonical names: `scope.md`, `module-map.md`,
  `schema.md`, `settings-panel.md`, `data-flow.md`, `common-tasks.md`.
- **Tier 2 — all seven accounted for.** `slash-dispatch.md`, `midnight-quirks.md`,
  `compat-layer.md` (trigger measured: 13 shims ≥ 3), `message-bus.md`, `profiles.md`,
  `perf-analysis/README.md` present; `debug.md` absent with a *Not applicable* row at
  `docs/ARCHITECTURE.md:213` whose trigger reads correctly against the code — every `/kcd debug`
  subcommand dumps **through** the `LibKa0s-DebugLog-1.0` console and the addon draws no debug
  surface of its own.
- **`## Documentation map`** present (`docs/ARCHITECTURE.md:187`) with **four** tables in the
  mandated order — `### Required` `:192`, `### Conditional` `:204`, `### Verification and record`
  `:215`, `### Addon-specific` `:227`. Every one of the 18 live `.md` files under `docs/` appears in
  exactly one table; no dangling row; frozen and generated directories named once each. The hub
  registers itself at `:196`, which `documentation-§3` settles as a **MAY** and an audit **MUST NOT**
  file either way — so it is recorded here and filed nowhere.
  - The one placement defect: `perf-analysis/README.md` sits at `:224` in `### Verification and
    record`, where v2.39.0 MUSTs it in `### Conditional`. Filed as `KICKCD-B-01`.
- **Non-canonical filenames** — none. `castbar.md` and `icon-grid.md` are Tier 3 and registered as
  such. No `data-model.md`, `saved-variables.md`, `pipeline.md`, `settings-system.md`,
  `wow-quirks.md`, `slash-commands.md`, `debug-console.md`.
- **Retired docs** — none. No `file-index.md`, no `conventions.md`, no `complexity.md`, no
  `docs/perf-runs/`. The capture store is `docs/perf-analysis/<YYYYMMDD-HHMMSS>/`.
- **Hub shape** — `docs/ARCHITECTURE.md` is **313 lines**, all ten mandated sections present, longest
  mandated section 54 lines (`## Documented deviations`). Under both thresholds; nothing to spill.
  `## Overview` and `## Module map` — the two names the 2026-09-07 run filed as `KICKCD-A-07` — are
  now there.

## 10. The recorded-deviation register and the issue store

`docs/ARCHITECTURE.md:234-288` carries **five** ratified rows, read before anything below was filed.
The PROVISIONAL sixth row is **gone**, retired on 2026-09-08 with the ruling `options-ui-§1` now
carries — `KICKCD-A-10` is closed at source.

Every row's cited rule was resolved against v2.39.0 and every re-check trigger evaluated against the
tree; the results are in `02_DEVIATIONS.md`.

**Issue store** (`gh issue list --state all --limit 200`): 14 issues, **all 14** carrying both a
`state:` and a `severity:` label, none carrying a status or severity word in the title. Three closed
`state:will-not-do` issues (#11, #12, #14) decline LibKa0s module adoptions — `library-stack-§3`'s
prune rule and `§7`'s "wires only the modules it actually uses" make those **compliance**, not
deviations, so they owe no register row and the inverse rule files nothing. No `state:will-not-do`
issue in this store declines a rule without a row. `docs/pending/LEDGER.md` does not exist.
