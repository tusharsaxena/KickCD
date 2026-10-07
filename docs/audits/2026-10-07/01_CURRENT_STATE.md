# KickCD — Current state (2026-10-07)

**Audited against:** **Ka0s WoW Addon Standard v2.76.1 (2026-10-07)**. Line 1 of the fetched
`standards/STANDARDS.md` reads `# Ka0s WoW Addon Standard (v2.76.1, 2026-10-07)`. The playbook
(`AUDIT.md`), the index and all **27** section files its Sections list links were fetched with
`curl -fsSL` from `https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master`, plus
`standards/ADDONS.md`. The fetched `AUDIT.md` is byte-identical to the sibling checkout
`../WowAddonStandards/AUDIT.md` (`diff -q` printed nothing).

**Repo kind:** **Addon**. `dev-copilot-profile` reported `profile=wow`, `kind=addon`,
`reason=toc:## Interface`, and `standards/ADDONS.md:23` lists `Ka0s KickCD` in the addon table
(`| Ka0s KickCD | ... | Enabled · Locked |`). The two agree, so the whole addon rule set and the whole
`AUDIT.md` playbook apply.

**Addon:** Ka0s KickCD **1.4.0** (`KickCD.toc:5`), `## Interface: 120100` (`KickCD.toc:1`).
**HEAD:** `43aa263` on `feat/2026-10-07-review-audit-remediation`, clean tree.
**Previous audit:** `docs/audits/2026-09-23/` (against v2.64.0). **153 commits** have landed since
2026-09-23 (`git log --oneline --since=2026-09-23 | wc -l`). They include the nav-rail Grid page, the
diagnostics dump, the launcher menu, the debug-log coverage pass, four peels below the 1000-line band,
the sighted complexity kit, and re-vendors from LibKa0s v1.57.0 to v1.70.0.

**Prefix:** `KICKCD-`. Rows carried forward keep their `A-`, `B-` and `C-` ids. New rows in this
run use the `KICKCD-D-` series.

---

## Layout (`layout`)

- Five source folders plus `libs/` and `media/`: `core/` (17 files), `defaults/` (2), `locales/` (1),
  `modules/` (16), `settings/` (14). `git ls-files '*.lua' | grep -vE '^(libs/|tests/)'` lists **50**
  shipped authored files, and every one of them appears in `KickCD.toc` (checked file by file; no
  file printed as missing).
- **The 1500-line cap.** The default census (`git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`,
  `tests/` included) covers **127 files, 45,193 lines**. The largest is `modules/IconGrid.lua` at
  **996** lines. **No file is in the 1000–1500 band and none is over the cap.** The nine files that
  were in the band at the last release run (`docs/automated-tests/RESULTS.md`, watch list) were all
  peeled below 1000 by GI-KC-01 to GI-KC-09 (issues #24 to #32, all closed `state:done`).
- **The census.** `docs/ARCHITECTURE.md:369` carries `### Files over the 1500-line cap`, and `:376`
  reads "Nothing is over the cap today." The tree agrees. The kit gate is wired by path:
  `tests/run.lua:249` `{ name = "test_layout_cap", dir = "tests/_kit/" }`.
- **Generators (`layout-§1`).** `git ls-files '*.py' '*.sh' | grep -vE '^(libs/|tests/_kit/)'` is
  empty. There is no authored generator.
- **Media (`layout-§3`, `library-stack-§8`).** `media/` holds `logos/` (four files) and
  `screenshots/` (two files) only. There is no private `fonts/`, `icons/` or `textures/` copy of the
  shared payload.

## TOC (`toc-file`)

- `## IconTexture: Interface\AddOns\KickCD\media\logos\kickcd.logo.128.tga` (`KickCD.toc:6`). The
  TGA header reads type **2** (uncompressed), **128×128**, **32** bpp. This is the right artifact.
- `## X-Standard:` is present (`:12`). `## X-Curse-Project-ID: 1530802` is present (`:13`). The absent
  `## X-Wago-ID` is explained by a comment at `:14-16` (CurseForge-only).
- `## SavedVariables: KickCDDB, KickCDPerfDB` (`:7`). `schemaVersion = 0` is declared in the AceDB
  defaults at `core/Database.lua:87` (`toc-file-§2`).
- **Position annotations (`toc-file-§5`).** Every load-bearing line carries a
  `LOAD-BEARING POSITION` comment naming what resolves: MediaSetup→Constants (`:53`), CoreSetup
  (`:60`), Database_Migrations (`:71`), SpellInput (`:75`), PerfSetup (`:89`), the five `IconGrid_*`
  siblings (`:110`), the five `Castbar_*` siblings (`:121`), SchemaSetup (`:136`), OptionsSetup
  (`:139`), Panel (`:146`), Grid (`:163`) and Spells siblings (`:168`). Every group carries a
  conventional note: Locales (`:40`), Core (`:44`), Defaults (`:100`), Modules (`:106`) and Settings
  pages (`:153`). **`KICKCD-C-16` (and `C-16a` to `C-16d`) and `KICKCD-A-02` are closed.**
- LibKa0s is loaded once as `libs\LibKa0s\LibKa0s.xml` in `# Libraries`, after Ace3.

## Libraries and the LibKa0s wiring (`library-stack`)

- **Provenance:** `CLAUDE.md:42` reads `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.70.0 (MIT).`
  `README.md` carries no provenance line and no library section.
- **Vendored payload.** `diff -r` of `../LibKa0s` at tag `v1.70.0` (`26f441a`) against
  `libs/LibKa0s` and against `tests/_kit` both printed nothing: **no drift (#45), no partial vendoring
  (#48)**. Kit revision is **37** (`tests/_kit/framework.lua:20`, `Kit.VERSION = 37`).
- **Fourteen majors consumed.** A `LibStub("LibKa0s-<Major>-1.0"` sweep over the shipped source finds
  Bus, Compat, Core, DebugLog, Env, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Slash and
  Widgets. `docs/ARCHITECTURE.md:118` says fourteen, and it is right. Item is not consumed, and the
  decline is #14.
- **Setup files (descriptor + stub).** `core/CoreSetup.lua`, `core/EnvSetup.lua`,
  `core/PoolSetup.lua`, `core/MediaSetup.lua`, `core/DebugLogSetup.lua`, `core/LauncherSetup.lua`,
  `core/LifecycleSetup.lua`, `core/PerfSetup.lua`, `settings/Slash.lua`, `settings/OptionsSetup.lua`
  and `settings/SchemaSetup.lua`. No hand-rolled console, dispatcher, widget maker or harness exists
  (#47).
- **Stub coverage.** The members reached on each seam are answered by its stub. Launcher
  (`Register`, `SetShown`): `core/LauncherSetup.lua:82`, `:92`. Lifecycle (`Hold`, `IsDown`):
  `core/LifecycleSetup.lua:186`, `:201`. Perf (`on`, `Note`, `suspended`, `OnCommand`):
  `core/PerfSetup.lua:43-50`. The DebugLog stub carries the four gate members
  (`core/DebugLogSetup.lua:90-93`). `tests/test_surface_parity.lua` pins NS, Util, DebugLog, Slash,
  Options, Schema and Compat against the live surface. The Options stub is load-completing, which is
  the documented exception.
- **Media seam.** `core/MediaSetup.lua:105` `Media.RegisterLSM(addonName)` is fed the first vararg.
  The DebugLog descriptor passes `addonName` (`core/DebugLogSetup.lua:181`) and
  `brandName = "Ka0s KickCD"` (`:188`).
- **Close buttons.** The only `MakeCloseButton(` hits are the wrapper (`core/CoreSetup.lua:245`), its
  degraded twin (`:133`) and a comment (`core/PerfSetup.lua:251`). PerfSetup has no `decorate` hook
  (`:242`).

## Architecture, bus, events (`architecture`, `events-frames-taint`)

- **Bus.** There are five messages, declared once in `NS.MSG` (`core/Constants.lua:42-50`) with
  PascalCase tails. `(Send|Register)Message("Ka0s_` has **0** call-site literals outside the tests.
  `tests/test_bus.lua` pins the catalog.
- **Event registration (`events-frames-taint-§1`).** Every game-event registration goes through
  `NS.RegisterEventList` → `NS.SafeRegisterEvent` (`core/CoreSetup.lua:85-89`, `:160`), or through
  `NS.SafeRegisterUnitEvent` (`core/Util.lua:521`). Rejected names land in
  `NS.State.rejectedEvents` and are surfaced by `/kcd debug events` (`core/KickCD.lua:428`) and the
  diagnostics `events` section (`modules/Diagnostics.lua:271`). **`KICKCD-C-02` is closed.**
- **Private frames.** The only private event frame is `Util.NewUnitCastFilter`
  (`core/Util.lua:503-529`). It is built once per (module, unit), refuses any route that is not
  `UNIT_SPELLCAST_*` (`:504-508`), and is disarmed and re-armed rather than rebuilt. That is the
  unit-filter carve-out, so it is compliant and not an entry. **`KICKCD-C-03` is closed.** The combat
  listener is an AceEvent target (`core/State.lua:161-162`, `LibStub("AceEvent-3.0"):Embed(boot)`).
  The Spells page uses `NS.NewBusTarget()`. **`KICKCD-C-04` is closed.**
- **`_G.print` fallbacks.** `git grep 'or _G\.print|_G\.print'` over the shipped source is empty.
  **`KICKCD-A-08` is closed.**

## Settings and SavedVariables (`savedvariables`, `options-ui`, `architecture-§5`)

- AceDB `KickCDDB`, `schemaVersion = 0` default, a version ladder `Database:MigrateProfile`
  (`core/Database_Migrations.lua:356-394`) whose steps write no stamp and whose runner advances the
  stamp only past a step that returned (`:385-390`). Five shape-driven migrators run on Init and on
  every `OnProfileChanged` (`core/Database.lua:662-669`, then the ladder at `:671`). The register's first row ratifies that.
  **The runner's target is `Database.CURRENT_DB_VERSION` (`core/Database.lua:36`, `:39`). No
  `NS.SCHEMA_VERSION` exists → `KICKCD-D-01`.**
- **Write paths.** The stored-tree grep classifies cleanly. The spell-list writes are the registry's
  one writer, `core/Database.lua` (`:165-167`, `:498`, `:533`). The migrations are the load pass. The
  anchor reset (`settings/Panel_Render.lua:472-477`) is a named writer of named non-setting state
  (`docs/ARCHITECTURE.md:206`).
- **Panel.** There are four pages: General, Grid (nav rail: Icons, Cast bar, Text Label), Spells and
  Profiles. Every page draws through the library's strip (`H.RenderTabbedSchema`,
  `settings/General.lua:326`, `settings/Panel_Render.lua:146`) or composes the library's `H.TabStrip`
  (`settings/Panel_Render.lua:224` for a linked Focus, `settings/Spells.lua:686`). The rail is
  `Helpers.NavRail` (`settings/Panel_Render.lua:346`). Master controls are composed by
  `H.MasterControls` (`settings/General.lua:66`). There is no Test mode, because unlocking is the
  preview (`settings/General.lua:22`). The Options descriptor passes `addonName = addonName`
  (`settings/OptionsSetup.lua:157`, v2.75.0). No `ScrollUp-Up` arrows and no `disabledIf` on a color
  row were found.
- **Combat (`options-ui-§2`).** The only `OpenToCategory` is the page jump
  `Helpers.OpenPageTab` (`settings/Panel_Widgets.lua:143-160`). It is gated by `refusedInCombat()`
  (`:144`) and uses the `:GetID()` integer (`:140`), so it is compliant. `settings/Spells.lua:776`
  reads `SettingsPanel:IsShown()` inside the page's `OnHide`. That is a C method read, with no close,
  hide, commit or field write, so it is **not** an `options-ui-§2` failure. It is recorded here so it
  is not re-derived.

## Slash, disabled state, launcher (`slash-commands`, `launcher`)

- `NS.COMMANDS` (`core/KickCD.lua:231-376`) holds **19** verbs: help, version, config, enable,
  disable, lock, unlock, toggle, list, get, set, reset, resetall, profile, resetposition, spells,
  debug, diagnostics, perf. That matches `docs/ARCHITECTURE.md:291`. `/kcd spells enable|disable`
  re-uses the pair inside a noun's sub-tree, which v2.65.0 made a MAY (`slash-commands-§2`).
  **`KICKCD-C-14` is closed.**
- **Disabled state (`slash-commands-§7`).** One `LibKa0s-Lifecycle-1.0` latch with two holds
  (`disabled`, `perf`) is in `core/LifecycleSetup.lua`. Each module's `Suspend` releases events,
  messages and timers (for example `modules/Cooldowns.lua:667-673`: `UnregisterAllEvents`,
  `UnregisterAllMessages`, the coalescer cancel). `tests/test_disabled.lua` (683 lines, in
  `tests/run.lua:229`) asserts on the mock's **registration set** (`:58-70`, `:187-196`), fires at
  the released targets to falsify the set (`:249-280`), counts filter frames across cycles (`:551`),
  and covers the perf hold and the degraded load (`:593-681`). Live verbs come from
  `SlashLib.LIVE_VERBS` plus `NS.EXTRA_LIVE_VERBS` (`settings/Slash.lua:466-470`,
  `core/KickCD.lua:366`). This is compliant, and the 11-of-11 failure the playbook expects does not
  hold here.
- **Launcher.** There is one LDB object through `LibKa0s-Launcher-1.0`
  (`core/LauncherSetup.lua:65`). The label is `"Ka0s KickCD"` (`:126`) and the icon is the 128 TGA
  (`:131`). The descriptor passes `isEnabled`/`setEnabled` and `isLocked`/`toggleLock` (`:148-153`),
  which matches ADDONS.md's `Enabled · Locked`. It also passes `debug` (`:169`) and
  `debugAtEnable` (`:174`). There is no host `OnTooltipShow`, `MenuUtil` or `NewDataObject`.
- **Library debug sinks (`debug-logging-§4`, v2.73.0).** Slash (`settings/Slash.lua:502`), Options
  (`settings/OptionsSetup.lua:160`), Launcher (`core/LauncherSetup.lua:169`) and Lifecycle
  (`core/LifecycleSetup.lua:160`) each pass `debug` as a forwarder onto `NS.Debug`. The change gates
  are the console's (`DebugChanged` at `modules/Cooldowns.lua:411`, `modules/IconGrid.lua:293`,
  `modules/IconGrid_Visibility.lua:230`, `modules/Castbar.lua:634`), and the at-enable queue is used
  (`core/DebugLogSetup.lua:260`).
- **Diagnostics (`debug-logging-§14`).** There is one `COMMANDS` row (`core/KickCD.lua:298`) and one
  `debug` word (`:382`), tested first in `runDebug` (`:454`). No alias. No host `SetEnabled` around
  `RunDiagnostics`, and no `diagnosticsEnablesLogging`, so the default enable applies. There are
  twelve sections (`modules/Diagnostics.lua:261-272`). The README carries `## Reporting a bug`
  (`README.md:122-128`) verbatim, between Troubleshooting and Issues.

## Tests, lint, complexity (`testing`, `lint`, `automated-tests`, `performance`)

- `ka0s-bounded lua tests/run.lua`: **1302 passed, 0 failed, 1 skipped, 1303 total**, exit 0. The skip
  is the kit's diagnostics opt-out case, which does not apply to an addon on the default.
- `ka0s-bounded luacheck .`: **0 warnings / 0 errors in 127 files**. `exclude_files` is `libs/`,
  `docs/audits/`, `_dev/`, `tests/_kit/`, `docs/reviews/` (`.luacheckrc:8`), so `tests/` is linted.
  The harness global is in `files["tests/"]`. There is no top-level `ignore`.
- **Complexity (sighted, kit 37).** `ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite
  complexity --no-bundle` reports `pass — 0 warnings`, **25,917 NLOC / 3,580 funcs**, max CCN **15**.
  `test_lizard_sighted` is wired (`tests/run.lua:255`). No gate line quotes raw `lizard`
  (`docs/testing.md:257`, `docs/performance.md:243`).
- **Record.** The newest row (`docs/automated-tests/RESULTS.md`, `20260927-030444`) measured
  `bcf9e51`, which is clean and **81 commits** behind HEAD. That bundle predates kit 35, so its
  manifest has no `blindFiles` (count 0 of the key). No sighted release record exists yet, and the
  next release run owes one (`KICKCD-B-04`, Info). Since then, tests went from 1201 to **1303**, files
  from 112 to **127**, and funcs from 3,089 to **3,580**. Max CCN is still 15. The band went from
  **9 files to 0**.
- **Watch list.** All nine band rows read "Already tracked as #24 to #32", and those are live issues,
  each now closed `state:done`. There are no "Accepted" dispositions. **`KICKCD-C-10` is closed.**
- **Perf.** `docs/perf-analysis/` holds `README.md` and two bundles, each with `report.md`,
  `dump.json` and `ANALYSIS.md`. There is no `docs/perf-runs/` and no `docs/complexity.md`.

## Packaging and line endings (`packaging`, `line-endings`)

- `.pkgmeta` ignores every named dev entry. The (a) check printed nothing. (b) printed only
  `UNACCOUNTED — .git`, which is the exempt entry. (c) printed nothing. Agent folders `.claude` and
  `.superpowers` are present and ignored.
- `.gitattributes` is present with `* text=auto eol=crlf` (`:26`), `*.sh text eol=lf` (`:36`) and
  `*.py text eol=lf` (`:37`), and 20 ` binary` lines. The first 84 lines diff **empty** against
  `line-endings-§5`'s client-bound body, and there is no tail. Check (e) reports **0** tracked files
  disagreeing with the pin. `test_eol` is wired (`tests/run.lua:246`).

## Root docs (`documentation-§1/§2/§7`)

- `README.md`. The H1 is `# Ka0s KickCD`. There are five badges in order. The standard badge is
  **bare** (`:6`). The Tests badge `1302/1302` (`:7`) matches passed/total with the skip excluded
  (`testing-§5`). There is no logo image, no library inventory, and no numbered list (the
  outside-fence grep is empty). The sections are in canonical order (`:13`-`:146`). The combat FAQ and
  Troubleshooting cells now say "run `/kcd config` again" (`:100`, `:117`). **`KICKCD-C-05` is
  closed.**
- `CLAUDE.md`. It is a stub, with the standards section, the docs pointers, the gate line and the
  provenance line (`:42`).
- `DEPENDENCIES.md` is present. It names the sighted runner for complexity.

## `docs/` (`documentation-§3`)

- **Tier 1:** `scope.md`, `module-map.md`, `schema.md`, `settings-panel.md`, `data-flow.md` and
  `common-tasks.md` are all present.
- **Tier 2:** all seven are present. Their triggers were measured against the code: 19 verbs, 8 shims
  (§3's grep on `core/Compat.lua`), 5 messages (under ten, so `message-bus.md` is present by choice),
  profiles user-visible, the perf harness wired, and debug surfaces beyond the console (diagnostics
  plus four chat topics). `docs/debug.md` exists. **`KICKCD-C-06` is closed.**
- **`## Documentation map`** (`docs/ARCHITECTURE.md:264`) has four tables in order. The register was
  reconciled against `git ls-files 'docs/*.md'` minus `documentation-§3`'s frozen stores. It has
  **22** files and **0** orphans, **0** dangling rows and **0** duplicates. `### Verification and
  record` holds exactly the six (`:303-308`), and `perf-analysis/README.md` sits in Conditional
  (`:296`).
- **Hub shape.** `docs/ARCHITECTURE.md` is **405** lines. The mandated sections are all under ~60
  lines (Module map 47, Settings schema 49). `documentation-§3` says the numbers are approximate on
  purpose and that "the failure they catch is 1071 lines, not 412", so this is not filed.
  **`KICKCD-C-09` is closed.**
- `docs/compat-layer.md` now collapses the six LibKa0s-Compat members to a pointer plus caveats
  (`:7-13`). **`KICKCD-C-07` is closed.** One stale description survives at `:34` (`KICKCD-C-08`).
- There are no non-canonical Tier 1/2 filenames and no retired docs (`file-index.md`,
  `conventions.md`, `complexity.md`, `docs/pending/`).

## Recorded-deviation register and issue store (`audit-review-history`)

- **Register.** `docs/ARCHITECTURE.md:329-338` has **eight** rows. Each was checked for whether its
  rule changed, whether its trigger fired, and whether its evidence ids resolve. All eight stand (see
  `02_DEVIATIONS.md`). The first row was rewritten on 2026-09-24 to name five migrators, after
  v2.65.0 rewrote `savedvariables-§1`. It cites heading anchors that resolve
  (`schema.md#unitsunitlabelstyle-shape` → `docs/schema.md:245`). **`KICKCD-B-03` is closed.**
- **Issue store** (`gh issue list --state all --limit 200 --json ...`) has **36** issues: 7 open
  (`#1`-`#5`, `#34`, `#35`, all `state:triaged`) and 29 closed. Every issue carries a `state:` label,
  there is no `[status]` title prefix and there is no `docs/pending/LEDGER.md`. #15 is closed
  `state:done` (**`KICKCD-C-11` is closed**). #9 is closed and carries no `[Optional]`
  (**`KICKCD-B-05` is closed**). #12 has a 2026-09-24 "Superseded" comment recording the Widgets
  adoption (**`KICKCD-C-12` is closed**).
- **`state:will-not-do`:** #11, #12, #14 and #23. #12 and #14 are module declines. Under
  library-stack-§3/§7 these are compliance and owe no row. #23 declines the optional
  `RenderTabbedSchema` opts for the linked-Focus page, which still draws through the library's
  `H.TabStrip` (`settings/Panel_Render.lua:224`), so it is not a departure from a MUST and owes no row.
  **#11 is now contradicted by the tree** → `KICKCD-D-02` (Info).
- **Re-vendor store.** There are 21 bundles. The payload-derived check finds **52** tags vendored
  since the 2026-08-25 horizon and **50** recorded. **v1.69.0 and v1.70.0** have no bundle →
  `KICKCD-C-01`.

## Movement since 2026-09-23

Of the 23 prior roots and 4 dependents, **19 roots and all 4 dependents are closed outright**:
A-02, A-08, B-02, B-03, B-05, B-06, C-02, C-03, C-04, C-05, C-06, C-07, C-09, C-10, C-11, C-12, C-13,
C-14 and C-16 (with C-16a to d). C-01's 25-tag backlog closed with the span bundle
`2026-09-24-v1.16.0-v1.54.2/`, and the id reopens below for two newer tags.
**Three recur in a new form:** `C-01` (two newer tags unrecorded), `C-08` (different stale
inventories) and `C-15` (the bare `§N` sites moved from code comments into tests and docs). **`B-04`
recurs** as Info. **Three are new:** `D-01`, `D-02` and `D-03`.
