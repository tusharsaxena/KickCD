# KickCD — Current State (2026-08-05)

**Addon:** Ka0s KickCD · **Version:** 1.2.1 (`KickCD.toc:5`, `core/KickCD.lua:38`)
**Standard audited against:** **v2.21.0 (2026-08-04)** — `standards/STANDARDS.md` line 1.
**Playbook:** `AUDIT.md` from the same repo, fetched at run time.
**Deviation prefix:** `KCD-` (assigned 2026-07-12; reused).

## Provenance of the rules

Fetched with `curl -fsSL` from
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master`:

- `AUDIT.md` (158 lines)
- `standards/STANDARDS.md` (142 lines) — the index; version/date read from its line 1
- **all 25 section files** discovered by following the index's Sections list under
  `standards/standards/`: `layout`, `toc-file`, `library-stack`, `architecture`, `savedvariables`,
  `options-ui`, `standalone-windows`, `preview-mode`, `slash-commands`, `localization`,
  `events-frames-taint`, `public-api`, `compat`, `debug-logging`, `packaging`, `lint`, `testing`,
  `performance`, `automated-tests`, `documentation`, `audit-review-history`, `versioning-git`,
  `naming-cheatsheet`, `anti-patterns`, `open-evolutions`
- `standards/ADDONS.md` (roster, for the prefix)

No rule below is recalled from memory. Section references use the `filename-§N` form; the retired
global `§N.M` notation is not used.

## Prior runs

`docs/audits/2026-07-12/` (`KCD-01`..`KCD-23`), `docs/audits/2026-07-18/` (`KCD-24`..`KCD-29`) and
`docs/audits/2026-08-04/` (`KCD-30`..`KCD-39`, advisory `A-1`..`A-7`). The 2026-08-04 run was
measured against **v2.17.1**; four standard versions have landed since, and two of this run's
findings exist only because of them (`automated-tests-§3`'s release gate, v2.21.0; the retirement of
`docs/complexity.md`, v2.19.0). `docs/reviews/2026-08-05/` (a code review, run today) is a separate
bundle and is not edited here.

---

## Layout (`layout`)

Modular tree as specified: `core/` (11 files), `defaults/` (1), `locales/` (1), `settings/` (11),
`modules/` (8), plus `libs/`, `media/`, `tests/`, `docs/`. No loose `.lua` at the root. Subfolders
lowercase; Lua files PascalCase. `media/` has typed subfolders only — `media/fonts/`
(`JetBrainsMono-Regular.ttf` + `JetBrainsMono-OFL.txt`), `media/logos/` (`kickcd.logo.tga` and its
`.jpg` source), `media/screenshots/` (6 PNG + 1 GIF).

`defaults/` holds **only** `defaults/Spells.lua`. The profile defaults tree is
`core/Database.lua:239-303` (`DEFAULT_PROFILE`), re-exported at `core/Database.lua:304`.

No file exceeds the 1500 LOC cap. Four sit in the 1000–1500 on-notice band:
`modules/Castbar.lua` 1314, `settings/Spells.lua` 1172, `modules/IconGrid.lua` 1154,
`tests/wow_mock.lua` 1066 — all four carry dispositions in
`docs/automated-tests/RESULTS.md:138-144`, each pointing at a tracked ID (`A-2`, `KCD-30`).

## TOC (`toc-file`)

`KickCD.toc:1-14` — field order exactly as `toc-file-§1`, no blank lines in the block, single
`## Interface: 120007`, `## SavedVariables: KickCDDB, KickCDPerfDB` (the two sanctioned globals),
`## X-License: MIT`, `## X-Standard:` the standards repo, `## X-Curse-Project-ID: 1530802`.
`X-Wago-ID` is present only as a commented placeholder (`:14`).

File listing (`:16-77`) uses `#` section headers in the order Libraries → Locales → Core → Defaults →
Modules → Settings. `libs\LibKa0s\LibKa0s.xml` is listed **once** as the single aggregate
(`:25`); no LibKa0s module file is named individually. No addon-authored `embeds.xml`.

## Library stack (`library-stack`)

`libs/` carries LibStub, CallbackHandler-1.0, AceAddon/AceEvent/AceDB/AceDBOptions/AceConsole/
AceConfig/AceGUI-3.0, AceGUI-3.0-SharedMediaWidgets, LibSharedMedia-3.0, LibCustomGlow-1.0 and
`libs/LibKa0s/`. `libs/LibKa0s/` holds all **ten** ship-folder entries — `Core.lua`, `DebugLog.lua`,
`Slash.lua`, `Options.lua`, `OptionsWidgets.lua`, `OptionsScroll.lua`, `Perf.lua`, `PerfPanel.lua`,
`LibKa0s.xml`, `LICENSE` — i.e. all five majors across all eight module files. `tests/_kit/` holds
`framework.lua`, `loader.lua`, `mock_base.lua`, `README.md`, `run-automated-tests.sh`; nothing under
`libs/`. AceTimer is deliberately not vendored (advisory `A-1`, 2026-08-04): the addon schedules
through `C_Timer.After` and never calls `LibStub("AceTimer-3.0")`.

Five LibKa0s majors are wired, one setup file each — `core/CoreSetup.lua`, `core/DebugLogSetup.lua`,
`core/PerfSetup.lua`, `settings/Slash.lua`, `settings/OptionsSetup.lua`. Each resolves its major with
`LibStub(<major>, true)` and falls back to a stub. No hand-rolled console, dispatcher, widget maker
or flow engine survives in the addon's own source; `settings/Panel_Widgets.lua` is 65 lines of
adapter (`:38` `InlinePair`, `:60` `SessionToggle` forwarding to the library's `SessionCheckbox`).

## Architecture (`architecture`)

Every file opens `local addonName, NS = ...`; there is no `_G.KickCD`. AceAddon registration at
`core/KickCD.lua` with AceEvent/AceConsole embeds; the printer is published as `NS.Util.print`
(`core/CoreSetup.lua:135`), never `NS.Print`, which is the first of `architecture-§2`'s two
sanctioned ways to survive the AceConsole `:Print` clobber — documented at `core/CoreSetup.lua:38-46`.

Closed bus with five `Ka0s_KickCD_*` messages, documented with senders/consumers/payload at
`docs/ARCHITECTURE.md:112-124` and in full at `docs/message-bus.md`. Receivers register on their own
targets: AceAddon module `self`, or `NS.NewBusTarget()` (`core/KickCD.lua:46`, used at
`settings/Spells.lua:1104`).

Schema-as-single-source: `NS.Settings.Schema`, assembled per page by the `settings/<page>.lua` files;
one write seam `Helpers.SetAndRefresh` used by both the panel and the slash CLI
(`settings/Slash.lua:302-306`); boot-time validation at `settings/Panel.lua:192` (`ValidateSchema`),
called from `RegisterPanel` at `:569`.

## SavedVariables (`savedvariables`)

`AceDB:New("KickCDDB", DEFAULTS, true)` at `core/Database.lua:820`. `schemaVersion` in the global
namespace (`:298`), with a step-table migration runner (`:711-712` and the `MIGRATIONS` fold).
`KickCDPerfDB` is the diagnostics ring, named to the Perf descriptor (`core/PerfSetup.lua:87`) and
declared in `.luacheckrc` `globals` with a comment. Colors are stored keyed `{r=,g=,b=,a=}` since the
v3→v4 migration (`core/Database.lua:203`, `:213`).

## Options UI (`options-ui`)

`settings/OptionsSetup.lua` builds the instance from a descriptor (`:224` `lib:New(descriptor)`) and
publishes `NS.RegisterOptionsPage` / `NS.CreateOptionsPanel` / `NS.OpenOptionsPanel` /
`NS.RefreshOptionsPanel` as forwarders (`:228-234`). The library-absent branch (`:169-217`) is
**load-completing, not member-answering** — the documented `options-ui-§1` exception — and its
comment (`:150-168`) records that the measured load-time member set for this addon is **zero**,
pinned by `tests/test_options_panel.lua`.

Panels are built by the library's `Helpers.CreatePanel`; the header, breadcrumb, lazy Defaults button
and the always-shown scrollbar patch are the library's. Six pages: general, icons, castbar, label,
spells, profiles.

**But the panel shell's registration is the host's, not the library's.** `settings/Panel.lua:546`
declares a private `NS.Settings.RegisterTab`, `:554` a private `RegisterPanel` that calls
`Settings.RegisterCanvasLayoutCategory` directly (`:589`) and drives the page builders itself
(`:594-603`); each page registers through `NS.Settings.RegisterTab`, not the library's
`RegisterOptionsPage`. The library's own registry and `CreateOptionsPanel` (`libs/LibKa0s/Options.lua:536`,
`:576`) are reachable but unused outside tests. Panel-open is likewise the host's
(`core/KickCD.lua:775-790`, gated on combat at `:735-739`).

Four members the library supplies are re-implemented in the host and installed onto the instance:
`Helpers.LSMValues` (`settings/Panel.lua:281`), `Helpers.AttachTooltip` (`:341`),
`Helpers.EnsureScroll` (`:394`), `Helpers.AddSpacer` (`:443`). Two layout constants are restated
host-side: `NS.Const.PANEL_PADDING_X` (read at `settings/Panel.lua:307`) and
`local ROW_VSPACER = 8` (`:426`), which then overwrites the library's published value at `:430`.

## Standalone windows / preview mode

No data-browser main window — the addon's surfaces are the icon grid, the cast bar and the unit
label, plus the library's debug console and perf panel. `standalone-windows` is therefore mostly N/A;
the console and perf panel are skinned by `LibKa0s-Core-1.0` and the perf panel's close button comes
from `NS.DebugLog.MakeCloseButton` (`core/PerfSetup.lua:209-210`).

Preview mode is present and unlock-driven: `modules/Castbar.lua:426-431` shows the placeholder while
unlocked, `:733` `applyPreviewVisuals` feeds the same render path, `:835-839` keeps it while
unlocked, and it clears on re-lock.

## Slash (`slash-commands`)

`settings/Slash.lua:286` builds one dispatcher from `LibKa0s-Slash-1.0` with a descriptor whose
`commands` is the host's ordered `NS.COMMANDS` (`core/KickCD.lua:148-195`, positional triples).
`set`/`applyDefault` route through `Helpers.SetAndRefresh`, the same seam the panel uses. Registration
is through AceConsole (`/kcd`, `/kickcd`). Reserved verbs are present: `help`, `config`, `list`,
`get`, `set`, `reset`, `resetall`, `debug`, `perf` (`:183`), `version` (`:151`). Two host adapters are
documented at `:18-30` (`groupKey`, because rows carry `panel` not `page`; and a `parse` override
carrying the `valueGate` hint). A full stub covers `OnSlash`/`PrintHelp`/`LandingRows`/`ParseValue`
and each `Cli*` verb when the library is absent (`:206-266`).

`NS.PREFIX` is `|cff00ffff[KCD]|r` and every chat line goes through `NS.Util.print`.

## Localization (`localization`)

`locales/enUS.lua` only, metatable-fallback `NS.L`. Game data is matched on IDs and tokens — spec IDs
rather than translated spec names since the 1.2.1 migration (`README.md:210`).

## Events / frames / taint (`events-frames-taint`)

AceEvent throughout; per-unit dispatch frames are `RegisterUnitEvent`-filtered
(`core/PerfSetup.lua:22-23`). Combat gate on panel open uses `InCombatLockdown()` plus the addon's
own `State.inCombat` (`core/KickCD.lua:735-739`). The secret-safe seam is the library's, published at
`core/CoreSetup.lua:130-131`, with the library-absent fallback at `:76-98` — the one sanctioned second
copy.

Two files still reach past the seam: `core/Compat.lua:373` defines a private `safeRender` keyed on
`_G.issecretvalue` and `:446` falls back to `_G.print`; `modules/Castbar_Debug.lua:125` takes
`NS.Util.print or _G.print` and its 20 dump lines pre-concatenate with `..` before the printer.

## Debug logging (`debug-logging`)

`core/DebugLogSetup.lua:45` resolves `LibKa0s-DebugLog-1.0` silently, `:120-164` builds the instance
from a descriptor with all five required fields plus `slash`, `initSummary` (`:149`),
`onVisibilityChanged` (`:160`), and call-time forwarders for `print`/`safeToString` (`:142-143`).
`NS.Debug` is bound bare at `:170`. The monospace font is registered with LSM at `:37-43` from
`NS.Const.FONT_MONO`. The library-absent stub (`:73-115`) answers every member the addon reaches —
`Toggle`, `SetEnabled`, `Add`, `Show`, `Hide`, `IsShown`, `MakeCloseButton`, plus the buffer
introspection the suites drive — and still flips `NS.State.debug` and prints the ack. It also defines
`FormatPlain`/`FormatColored` (`:94-96`, `:114`).

The `/kcd debug castbar` structured dump prints to **chat**, not the console
(`modules/Castbar_Debug.lua:123-135`).

## Performance (`performance`)

`core/PerfSetup.lua:70` creates the instance from a descriptor with `sv = "KickCDPerfDB"` (`:87`),
`version` read from the TOC manifest with `NS.VERSION` as fallback (`:84-85`), and eight declared
buckets with `within` nesting (`:96-105`). Brackets use the mandated
`local __t0 = Perf.on and debugprofilestop()` … `if __t0 then Perf.Note(...) end` shape;
`debugprofilestop` is in `.luacheckrc` `read_globals` with the rule cited. The library-absent stub
(`:43-55`) carries `on`, `suspended`, `Note` and `OnCommand`. `suspend`/`resume` are implemented at
`:130+`.

**`tests/perf.lua` does not exist**, so `performance-§9`'s offline scenario runner and its
zero-overhead evidence are absent — as `docs/automated-tests/RESULTS.md:61-66` states plainly.
`docs/performance.md` and `docs/perf-runs/` do not exist.

Complexity: `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` run today reports **15430 NLOC, 2051
functions, avg CCN 2.1, max CCN 15, 0 warnings** — **byte-identical** to
`docs/automated-tests/20260804-233245/complexity.txt`. No drift. `docs/complexity.md` (retired in
v2.19.0) is **absent**, which is the compliant state.

## Automated tests record (`automated-tests`)

Three frozen bundles: `20260804-182144`, `20260804-214315`, `20260804-233245`, each with
`manifest.json`, `ANALYSIS.md`, `lint.txt`, `tests.txt`, `test-cases.md`, `complexity.txt`. No
`perf.txt`/`perf.json` — the addon ships no scenarios. `docs/automated-tests/README.md` and
`RESULTS.md` both exist; `RESULTS.md` carries the trend table, standing sections for all four suites,
and the watch list as **two tables with header rows** (functions: "None."; files by band: four rows
with dispositions). The runner is the vendored `tests/_kit/run-automated-tests.sh`, executable
(`-rwxrwxrwx`, Bourne-Again shell script), and `.gitattributes:19` carries `*.sh   text eol=lf`.

## Documentation (`documentation`)

Root ships exactly three docs plus `LICENSE`: `README.md`, `CLAUDE.md`, `DEPENDENCIES.md`. The
README follows the canonical order (H1 → 5 badges → logo → description → `## What's new in 1.2.1` →
`## Screenshots` → `## Usage` with both subsections → `## How interrupt tracking works` → `## FAQ` →
`## Troubleshooting` → `## Libraries and credits` → `## Issues and feature requests` →
`## Version History`). The `[wow]` badge reads `Midnight_12.0.7`, matching `## Interface: 120007`; the
`[tests]` badge reads `737%2F737`, matching today's run and `docs/test-cases.md`.

`CLAUDE.md` is a stub with `## Standards compliance (read first)` at `:7`. The three-place standards
reference is complete: `KickCD.toc:12`, `README.md:6`, `CLAUDE.md:7`.

`docs/` trio present: `ARCHITECTURE.md`, `testing.md`, `smoke-tests.md`. Of the five **required**
topic-detail docs, three exist — `test-cases.md`, `automated-tests/README.md`,
`automated-tests/RESULTS.md` — and two do not: **`performance.md`** and **`perf-runs/README.md`**.
No `docs/agent-context.md`, no `TODO.md`, no retired `docs/complexity.md`.

`docs/testing.md:99-100` and `CLAUDE.md:75` both state that perf and complexity never gate and that
the bundle is produced at release rather than at commit. Neither states the **release gate** that
v2.21.0 added.

## Tests (`testing`)

737 cases across 48 suites, green. `docs/test-cases.md` is generated and in sync with
`lua tests/run.lua --list` today.

`tests/_kit/` is vendored and byte-pinned by `tests/test_vendor_sync.lua`, **and is loaded by
nothing**. `tests/run.lua:19-83` carries a private registry, the assertion set and the `--list`
renderer; `tests/loader.lua` is a private sandboxed source loader reading `KickCD.toc` at `:42`;
`tests/wow_mock.lua` is 1066 lines of full replacement whose own comment at `:573` calls its widget
builder "a VERBATIM port of `tests/_kit/mock_base.lua`'s builder". `tests/run.lua:39-55` executes
each case body **at registration time** and short-circuits in list mode.

The degraded-path discipline is real: `tests/run.lua:97-99` documents `{ libFiles = {} }`, which
loads the addon with LibKa0s genuinely absent so the stubs are exercised by a real load.

## Lint (`lint`) and packaging (`packaging`)

`.luacheckrc` at root; `luacheck .` → 0 warnings / 0 errors over 32 files. `exclude_files` lists
`libs/`, `docs/audits/`, `_dev/`, `tests/`, `docs/reviews/`. Both `globals` entries carry comments.
`.pkgmeta` has `package-as: KickCD`, no `externals:`, and ignores `.luacheckrc`, `.gitignore`,
`.gitattributes`, `docs`, `tests`, `_dev`, `*.bak`. `.superpowers/` (54 files) and
`.claude/settings.local.json` are not ignored.

## Versioning / git (`versioning-git`)

Semver `1.2.1` in the TOC and `core/KickCD.lua:38`; README Version History top row is 1.2.1 and
`## What's new in 1.2.1` agrees with it. Working tree is on `master`, clean except the untracked
`docs/reviews/2026-08-05/` produced by today's review and this bundle.
