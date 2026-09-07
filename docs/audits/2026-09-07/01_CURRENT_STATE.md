# KickCD — Current State (2026-09-07)

**Addon:** Ka0s KickCD 1.2.1 (`KickCD.toc:5`)
**Audited against:** **Ka0s WoW Addon Standard v2.38.0 (2026-09-02)** — resolved from
`standards/STANDARDS.md` plus **all 26 section files** its Sections list links, and `AUDIT.md`
(both fetched verbatim with `curl -fsSL` from
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master`).
**Rule set used:** the **addon** rule set. The repo carries a `.toc` (`KickCD.toc`), so
`AUDIT.md` step 1's library-repo switch does not apply.
**Prefix:** this run uses `KICKCD-A-NN`. Prior runs used `KCD-NN`; the mapping to prior IDs is
stated per row in `02_DEVIATIONS.md`.

---

## 1. Layout (`layout`)

Modular layout, source under `core/ defaults/ locales/ modules/ settings/`, nothing loose at the
root. Folder casing is lowercase throughout; Lua files are PascalCase.

| Folder | Files |
|---|---|
| `core/` | `Compat.lua`, `Constants.lua`, `CoreSetup.lua`, `Database.lua`, `DebugLogSetup.lua`, `EnvSetup.lua`, `KickCD.lua`, `LSMPatch.lua`, `MediaSetup.lua`, `PerfSetup.lua`, `PoolSetup.lua`, `State.lua`, `Units.lua`, `Util.lua` (14) |
| `defaults/` | `Profile.lua`, `Spells.lua` |
| `locales/` | `enUS.lua` |
| `modules/` | `Castbar.lua`, `Castbar_Debug.lua`, `Castbar_Skin.lua`, `Cooldowns.lua`, `IconGrid.lua`, `IconGrid_Layout.lua`, `IconGrid_Render.lua`, `UnitLabel.lua` (8) |
| `settings/` | `Castbar.lua`, `General.lua`, `Icons.lua`, `Label.lua`, `OptionsSetup.lua`, `Panel.lua`, `Panel_Render.lua`, `Panel_Widgets.lua`, `Profiles.lua`, `Slash.lua`, `Spells.lua` (11) |
| `media/` | typed subfolders only — `media/logos/` (3), `media/screenshots/` (7). No private copy of any `libs/LibKa0s/media/` asset. |
| `libs/` | vendored, lowercase, committed |
| `tests/` | 52 suite files + `tests/_kit/` (vendored harness, 6 files) + `perf.lua` + `run.lua` + `wow_mock.lua` |

**LOC.** No file over the 1500 cap. Four files in the 1000–1500 on-notice band, measured today:
`modules/Castbar.lua` 1320, `settings/Spells.lua` 1296, `tests/wow_mock.lua` 1232,
`modules/IconGrid.lua` 1152.

## 2. TOC (`toc-file`)

Field order is canonical (`KickCD.toc:1-13`): Interface `120007`, Title `Ka0s KickCD`, Notes,
Author, Version `1.2.1`, IconTexture, `SavedVariables: KickCDDB, KickCDPerfDB` (two, harness wired),
OptionalDeps, DefaultState, `Category-enUS: Combat`, `X-License: MIT`, `X-Standard:` pointing at the
standards repo, `X-Curse-Project-ID: 1530802`. `KickCD.toc:14` is a **commented** `X-Wago-ID`
placeholder carrying a `TODO(KCD-18)` marker.

Section headers are `# Libraries` → `# Locales` → `# Core` → `# Defaults` → `# Modules` →
`# Settings`, in the mandated order. `libs\LibKa0s\LibKa0s.xml` is listed once, after Ace3
(`KickCD.toc:26`); no module `.lua` is named individually and there is no addon-authored
`embeds.xml`.

**Position annotations.** Three `# Core` lines carry comments: `core\EnvSetup.lua` (declared
conventional, `:36-38`), `core\PoolSetup.lua` (declared conventional, `:39-41`) and
`core\MediaSetup.lua` (declared **LOAD-BEARING**, `:42-45`). Every other line in `# Core` and every
line in `# Settings` is unannotated — including two positions that are load-bearing in fact
(`KICKCD-A-02`).

## 3. Libraries (`library-stack`)

Vendored and committed under `libs/`: LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0,
AceDB-3.0, AceDBOptions-3.0, AceConsole-3.0, AceConfig-3.0, AceGUI-3.0, **LibKa0s**,
LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets, LibCustomGlow-1.0. No `externals:` in `.pkgmeta`.

**LibKa0s provenance** is in root `CLAUDE.md:52` — `Bundles [LibKa0s](…) v1.25.0 (MIT).` — and
**not** in `README.md`. Both vendored payloads diff **clean** against the sibling repo at that tag
(`03_EVIDENCE.md`).

**Modules wired**, one seam file each: `Core` (`core/CoreSetup.lua`), `Env` (`core/EnvSetup.lua`),
`Pool` (`core/PoolSetup.lua`), `Media` (`core/MediaSetup.lua`), `DebugLog`
(`core/DebugLogSetup.lua`), `Perf` (`core/PerfSetup.lua`), `Slash` (`settings/Slash.lua`),
`Options` (`settings/OptionsSetup.lua`). `Item` and `Widgets` are carried in the payload; `Widgets`
is reached for `ReorderList` (`settings/Spells.lua:1058-1059`). `Item` is unwired — a per-module
adoption decision the standard explicitly permits.

The addon owns **no** console window, widget makers, flow engine, dispatcher, parser or test
framework of its own; each is a descriptor plus a degradation stub in its setup file, and
`tests/test_surface_parity.lua` asserts the stub surfaces against the live ones on both arms.

## 4. Architecture (`architecture`)

`local addonName, NS = ...` in every file; no `_G[addonName]`. `core/KickCD.lua` promotes `NS` with
`AceAddon-3.0:NewAddon(NS, "KickCD", …)`. The chat printer is `NS.Util.print`
(`core/CoreSetup.lua`), which is the AceConsole-embed-proof form architecture-§2 names first.
Message bus: `Ka0s_KickCD_*` messages, documented in `docs/message-bus.md` and summarized in
`docs/ARCHITECTURE.md:113-126`. Schema-as-single-source: `NS.Settings.Schema`, 228 rows, validated at
panel-register time by `Helpers.ValidateSchema`.

## 5. Settings (`options-ui`)

Six pages registered through the library's registry (`NS.RegisterOptionsPage`, e.g.
`settings/General.lua:245-246`, `settings/Spells.lua:1280-1281`). Every page draws a tab strip:

| Page | Tabs, in `group` declaration order |
|---|---|
| General | `Master controls`, `Units` |
| Icons | `Sizing`, `Layout`, `Visual states`, `Border`, `Annotations`, `Ready glow` |
| Cast bar | `General`, `Size and position`, `Icon`, `Font`, `Spell name`, `Cast time`, `Interruptible`, `Non-interruptible` |
| Text Label | `General`, `Placement`, `Font` |
| Spells | one hand-drawn tab, `Spell list` (`settings/Spells.lua:1147-1152`) — the page has no schema rows |
| Profiles | exempt: AceConfigDialog draws it whole |

`docs/settings-panel.md:13-18` records exactly this table, and it is derived from the schema.

The General page's first tab is `Master controls`, emitted by `H.MasterControls`
(`settings/General.lua:55-71`), so the canonical six rows plus the closing reset pair are composed,
not typed. Font / border / bar / color-pair blocks are composed everywhere they appear
(`H.FontGroup`, `H.BorderGroup`, `H.BarGroup`, `H.ColorPair`). No `disabledIf` on any color row; no
`LSM30_*` hit outside `core/LSMPatch.lua`'s registry wrapper; no `ScrollUp-Up`/`ScrollDown-Up`
arrow pair; the spell list drags through `LibKa0s-Widgets-1.0`'s `ReorderList`. Class-color
companions carry `classColorSource` because the composer stamps it
(`libs/LibKa0s/OptionsCompose.lua:157`, `:171`).

## 6. Slash, debug, performance

`/kcd` through `LibKa0s-Slash-1.0` (`settings/Slash.lua`), 15 verbs with `debug` and `spells`
subcommand trees — `docs/slash-dispatch.md` is present as Tier 2 requires. Debug console is
`LibKa0s-DebugLog-1.0`'s. Performance harness is wired (`core/PerfSetup.lua`), `KickCDPerfDB` is
declared, `tests/perf.lua` ships five scenarios including the zero-overhead pair, and
`docs/perf-analysis/` holds one frozen in-game bundle (`20260807-131311/`) with `report.md`,
`dump.json` **and** `ANALYSIS.md`.

## 7. `.gitattributes` (`line-endings`)

Present at the root and **byte-identical to line-endings-§5's client-bound canonical body** (diff
recorded in `03_EVIDENCE.md`). Pin recorded verbatim: `* text=auto eol=crlf`; carve-out
`*.sh text eol=lf`; 20 `binary` markings. The working tree does **not** fully agree with the pin —
see `KICKCD-A-04`.

## 8. Root doc set

`README.md` (player-facing, canonical section order, bare `![Standard](…)` badge at `:6`, no
bundled-library inventory, no `## Credits`), the `CLAUDE.md` **stub** (adherence line,
`## Standards compliance (read first)`, pointer list, green-gate line, provenance line at `:52`),
`DEPENDENCIES.md`, and `LICENSE`. No `CHANGELOG.md`, no `TODO.md`, no `docs/agent-context.md`.
`[tests]` badge reads `841%2F841`, matching `docs/test-cases.md`'s Totals row and today's run.

## 9. `docs/`

Trio present (`ARCHITECTURE.md`, `testing.md`, `smoke-tests.md`). **Tier 1 complete** under the exact
canonical names: `scope.md`, `module-map.md`, `schema.md`, `settings-panel.md`, `data-flow.md`,
`common-tasks.md`. **Tier 2**: `slash-dispatch.md`, `midnight-quirks.md`, `compat-layer.md`,
`message-bus.md`, `profiles.md`, `perf-analysis/README.md` all present with their triggers fired;
`debug.md` carries a *Not applicable* row with its trigger. **Tier 3**: `castbar.md`, `icon-grid.md`.
Verification set: `test-cases.md`, `performance.md`, `automated-tests/README.md`,
`automated-tests/RESULTS.md`. No `file-index.md`, no `conventions.md`, no `complexity.md`, no
`docs/perf-runs/`, no `docs/pending/`, no non-canonical Tier 1/2 filename.

`## Documentation map` is present (`docs/ARCHITECTURE.md:176-221`) and accounts for all 21 live
`.md` files under `docs/` with no dangling row; frozen directories (`audits/`, `reviews/`,
`automated-tests/`, `superpowers/`, `perf-analysis/`, `revendor/`) are named once each. The hub is
**311 lines**, under the ~400 guidance, and no mandated section runs past ~60 lines.

`## Documented deviations` is present (`docs/ARCHITECTURE.md:223-284`) with **six** rows, one of
them explicitly marked **PROVISIONAL — not signed off**.

## 10. Decision register (issue store)

`gh issue list` returns 14 issues, all carrying a `state:` label and a `severity:` label, none with
a `[status]` title prefix. Three `state:will-not-do` closures (#11, #12, #14) decline **library
module adoptions**, which library-stack-§7 makes a per-addon schedule decision rather than a
deviation — no register row is owed for them. `docs/pending/LEDGER.md` does not exist.

## 11. Suites, as run today

- `luacheck .` — **0 warnings / 0 errors in 36 files**.
- `lua tests/run.lua` — **841 passed, 0 failed, 0 skipped, 841 total**.
- `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` — **1 warning**: an anonymous function at
  `tests/test_schema.lua:595-631`, CCN 18. Total 17109 NLOC across 2229 functions, avg CCN 2.1.
- `diff -r` against `LibKa0s` v1.25.0 — both payloads **empty**.

The newest committed run bundle is `docs/automated-tests/20260825-103417/`, which predates the
`feat/settings-revamp-v2` merge and reports 780 tests, 35 lint files and **zero** CCN warnings.
