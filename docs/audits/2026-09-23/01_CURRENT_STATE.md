# KickCD — Current State (2026-09-23)

**Addon:** Ka0s KickCD 1.3.0 · **Repo HEAD:** `dc11094` (`feat/2026-09-23-review-audit-remediation`,
clean tree at the start of the run)
**Audited against:** **Ka0s WoW Addon Standard v2.64.0 (2026-09-23)**. Line 1 of the fetched
`standards/STANDARDS.md` reads `# Ka0s WoW Addon Standard (v2.64.0, 2026-09-23)`.
**Rule set:** the **addon** set. `KickCD.toc` exists and `standards/ADDONS.md` lists Ka0s KickCD in
its addon table. `AUDIT.md` step 1's library and documentation-repo switches do not apply.
**Previous audit:** `docs/audits/2026-09-08/`, against v2.39.0. HEAD is **116 commits** past that
run's HEAD (`git rev-list --count 03f3b9a..HEAD`).

**How the standard was resolved.** `curl -fsSL` against
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master` for `AUDIT.md`,
`standards/STANDARDS.md`, `standards/ADDONS.md`, and **all 27 section files** that the index's
`## Sections` list links under `standards/standards/`. No section was read from memory. The fetched
files were then compared byte for byte against `git show origin/master:<path>` in the local
`WowAddonStandards` checkout (`e68795f`), and every one matched. To find which rules moved since the
last audit, `git diff f37a8fa origin/master -- standards/standards/` (f37a8fa is the commit that
introduced v2.39.0) was read. **25 of the 27 sections changed.** The two new obligations that matter
most here are `events-frames-taint-§1`'s isolated-registration and unit-filter-frame rules, and
`audit-review-history`'s rule that every re-vendor commit has a bundle.

**Tooling note.** `ka0s-bounded` was not on `PATH` in this shell. It was run by its full path,
`~/.claude/wow-addon/bin/ka0s-bounded`, so every run below was bounded and `timeout 900` was never
needed. The vendored kit is at revision 25 and bounds its own Lua runs as well.

---

## 1. Layout (`layout`)

Modular: `core/ defaults/ locales/ modules/ settings/`, plus `libs/`, `tests/`, `docs/` and `media/`.
There is no `tools/` folder, and `git ls-files '*.py' '*.sh'` returns only the vendored
`tests/_kit/run-automated-tests.sh`, so there is no authored generator to place.

**The cap census (`layout-§1`)** covers `git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`:
**101 files, 37,269 lines**. Nothing is over 1500. Five files are in the 1000–1500 band:

| File | LOC now | LOC at the last recorded run (`20260916-184417`) |
|---|---|---|
| `settings/Spells.lua` | 1444 | 1246 |
| `modules/Castbar.lua` | 1423 | 1345 |
| `modules/IconGrid.lua` | 1343 | 1163 |
| `tests/wow_mock.lua` | 1129 | 1060 |
| `modules/IconGrid_Render.lua` | 1014 | *(not in the band)* |

`docs/ARCHITECTURE.md:433-440` carries `### Files over the 1500-line cap` under
`## Documented deviations` and says "Nothing is over the cap today." The kit gate
`{ name = "test_layout_cap", dir = "tests/_kit/" }` is declared in the runner (`tests/run.lua:197`)
and all 13 of its cases pass.

## 2. TOC (`toc-file`)

`KickCD.toc:1-13` follows the canonical field order: Interface `120100`, Title `Ka0s KickCD`, Notes,
Author, Version `1.3.0`, IconTexture pointing at the addon's own 128 logo, SavedVariables
`KickCDDB, KickCDPerfDB`, OptionalDeps, DefaultState, Category-enUS, X-License, X-Standard, and
X-Curse-Project-ID `1530802`. The same id is in the README's CurseForge badge. `:14-16` explains why
there is no Wago id. Section headers are in the canonical order: Libraries (`:18`), Locales (`:39`),
Core (`:42`), Defaults (`:89`), Modules (`:93`), Settings (`:104`). `libs\LibKa0s\LibKa0s.xml`
appears once, at `:28`, after Ace3.

- **Logo:** `media/logos/kickcd.logo.128.tga`. The header was read directly: image type **2**
  (uncompressed), **128×128**, **32** bpp. Compliant.
- **Position annotations (`toc-file-§5`):**
  - `LOAD-BEARING POSITION:` notes are on `:50-53` (MediaSetup), `:57-64` (CoreSetup), `:80-87`
    (PerfSetup), `:106-112` (OptionsSetup) and `:113-119` (Panel).
  - The LifecycleSetup comment at `:74-79` names what resolves.
  - Conventional notes are on EnvSetup (`:44-46`), PoolSetup (`:47-49`) and LauncherSetup (`:69-73`).
  - **Two gaps:**
    - The `# Locales`, `# Defaults`, `# Modules` and `# Settings` groups carry no conventional note,
      and neither do the unannotated `# Core` lines (`KICKCD-A-02`).
    - Five `# Modules` positions are load-bearing and unannotated (`KICKCD-C-16`):
      `modules/IconGrid_Layout.lua:15`, `modules/IconGrid_Render.lua:19`,
      `modules/Castbar_Handle.lua:24`, `modules/Castbar_Skin.lua:53` and
      `modules/Castbar_Debug.lua:10` each call `NS:GetModule(...)` at file scope.

## 3. Libraries (`library-stack`)

Vendored: LibStub, CallbackHandler, AceAddon, AceEvent, AceDB, AceDBOptions, AceConsole, AceGUI,
AceConfig, LibKa0s, LibSharedMedia, AceGUI-3.0-SharedMediaWidgets, LibCustomGlow, LibDataBroker-1.1
and LibDBIcon-1.0 (`KickCD.toc:19-37`).

**LibKa0s provenance.** `CLAUDE.md:42` reads `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.55.0 (MIT).`
This is the only hit, and `README.md` has none.

**Both vendored diffs are EMPTY against the `v1.55.0` tag.** The tag was extracted with
`git -C ../LibKa0s archive v1.55.0 LibKa0s testkit` because the sibling's `HEAD` (`46ccaa6`) is ahead
of the tag. Both `diff -r --strip-trailing-cr` (content) and `diff -rq` (bytes) came back empty:
146/146 files in the payload and 11/11 in the kit (`03_EVIDENCE.md` §E1). That means no drift
(anti-pattern #45) and no partial vendoring (#48).

**Wiring: 13 of the 15 majors are adopted, and all of them are consumed rather than hand-rolled.**

| Major | Seam | Library-absent branch |
|---|---|---|
| Core | `core/CoreSetup.lua:67` | member-answering stub, including `NS.MakeCloseButton` (`:102`) |
| Env | `core/EnvSetup.lua:61` | reads the TOC directly |
| Pool | `core/PoolSetup.lua:38` | a local keyed pool |
| Media | `core/MediaSetup.lua:57`, which passes the `addonName` vararg (`:55`, `:74`, `:83`) and makes one `RegisterLSM(addonName)` call (`:105`) | answers nil |
| DebugLog | `core/DebugLogSetup.lua:41`, whose descriptor carries `addonName` (`:142`) | stub |
| Launcher | `core/LauncherSetup.lua:61` | stub `:66-93` covering Register, IsRegistered, Object, IsShown and SetShown |
| Lifecycle | `core/LifecycleSetup.lua:50` | stub `:145-194` covering Hold, Release, Set, IsHeld, IsDown, Holds, Reevaluate and PrintHolds |
| Perf | `core/PerfSetup.lua:33` | stub |
| Slash | `settings/Slash.lua:55` | stub |
| Options | `settings/OptionsSetup.lua:90` | **load-completing** stub, the documented exception |
| Widgets | inline at `modules/IconGrid.lua:581` and `modules/Castbar_Handle.lua:41` | degrades to less UI |
| Compat | `core/Compat.lua:35`, with reader arms and the `IsSecret` guard arm at `:46` | as options-ui-§1 names |
| Bus | `core/Constants.lua:63-64`, `Catalog` only | falls back to the plain table |

Schema and Item are not adopted. Item was declined in #14, and Schema is on hold as open triaged
#22. v2.64.0 requires neither. `tests/test_surface_parity.lua` holds the DebugLog, Slash, Options
and Compat stubs to the live surfaces, and it is green. The addon calls four Lifecycle members
(`:Set`, `:Reevaluate`, `:IsDown`, and `:Hold` from inside the stub's own `Set`), and the stub
answers all of them.

**Shared media.** There is no private `media/fonts|icons|textures`, and `media/` holds only `logos/`
and `screenshots/`. There is one one-off mark: the Spells remove button draws the Blizzard atlas
`transmog-icon-remove` (`settings/Spells.lua:798`), although the catalog carries `close`, `clear`
and `cancel` (`KICKCD-C-13`). The close-button grep hits only the wrapper and its degraded twin
(`core/CoreSetup.lua:102`, `:174`) and a comment (`core/PerfSetup.lua:244`), so it is compliant.

## 4. Architecture and events (`architecture`, `events-frames-taint`)

- **Namespace.** The private vararg is used and there is no `_G.KickCD`. Eight files read `addonName`:
  Constants, CoreSetup, DebugLogSetup, EnvSetup, LauncherSetup, LifecycleSetup, MediaSetup and
  PerfSetup. The other 30 authored source files write `local _, NS = ...` (38 in total).
  `docs/ARCHITECTURE.md:77-81` says five and thirty (`KICKCD-C-08`).
- **Bus (`architecture-§4`).** `NS.MSG` is declared once, at `core/Constants.lua:40-51`, wrapped in
  `LibKa0s-Bus-1.0`'s `Catalog` (`:63-64`), and names each sender. All five wire names are
  PascalCase. The literal grep finds no call-site literals, only a comment in `tests/test_bus.lua`.
  Receivers are module targets or `NS.NewBusTarget`. Compliant.
- **Write paths (`architecture-§5`).** Every stored write outside the helper was classified:
  - **Registry writer and load pass** (`core/Database.lua`): named at `docs/ARCHITECTURE.md:175-181`.
  - **Anchors:** named state, `:183-191`.
  - **`KickCDPerfDB`:** named state, `:193-199`.
  - **`db.global.minimap`:** `:201-211`.
  - **Spell-entry `enabled` / `category`:** a ratified register row (`:396`).
  - Nothing is unclassified.
- **Event registration (`events-frames-taint-§1`).**
  - AceEvent is used in the modules.
  - **No registration block is isolated with `pcall`.** `C_EventUtils.IsEventValid` is not used and
    rejected names are not recorded (`KICKCD-C-02`).
  - **Two private frames carry ordinary, non-unit event traffic** (`KICKCD-C-04`):
    - `core/State.lua:143-146`: `PLAYER_LOGIN` and `PLAYER_REGEN_*`.
    - `settings/Spells.lua:375-381`: `TRAIT_CONFIG_UPDATED` and `PLAYER_SPECIALIZATION_CHANGED`.
  - **The unit-filter frames are rebuilt on every enable** (`KICKCD-C-03`).
    `Util.RegisterUnitCastEvent` (`core/Util.lua:438-445`) creates a new frame on each call:
    - `modules/IconGrid.lua` creates 8 per unit.
    - `modules/Castbar.lua` creates 10 per unit.
    - `DisableUnit` and `Suspend` then discard them with `inst.eventFrames = {}`.

    The carve-out requires those frames to be re-used across a disable/enable cycle.
- **Secret values and printing (`events-frames-taint-§8`).** `NS.Util.print` comes from Core. Three
  unreachable `or _G.print` fallbacks remain (`KICKCD-A-08`). The `safeRender` register row still
  holds, because its only callers are inside the `/kcd debug interrupt` dump.

## 5. The disabled state (`slash-commands-§7`)

**Compliant. This is the check the whole collection failed at v2.56.0, and KickCD now passes it.**

- **Teardown.** There is one latch with two named holds, in `core/LifecycleSetup.lua:109-132`
  (`standDown` / `standUp`):
  - The `disabled` hold is taken through `NS.RefreshEnabledHold` (`:221-226`).
  - The `perf` hold is the library's.
  - There is no second teardown path.
- **Registration set.** Every registration is undone:
  - `State.StandDown` → `boot:UnregisterAllEvents()` (`core/State.lua:195-197`).
  - Each module's `Suspend` releases its events, its messages and its per-unit frames:
    `modules/Cooldowns.lua:606-612`, `modules/IconGrid.lua:853-869`, `modules/Castbar.lua:1103-1115`,
    `modules/UnitLabel.lua:267-272`.
  - `Spells.StandDown` releases the settings page's subscriptions (`settings/Spells.lua:1422-1429`).
  - The icon ticker is stopped (`modules/IconGrid.lua:868`) and the cast bar's `OnUpdate` is cleared
    (`modules/Castbar.lua:926`).
- **Writes.** No SavedVariables write comes from a game event. The combat handler writes only
  `NS.State.inCombat`, which is session state (`core/State.lua:147-155`).
- **Surfaces.**
  - Every reserved verb, `config`, the bare `/kcd` and the schema CLI keep answering.
  - Feature verbs refuse on one line.
  - A left launcher click while disabled prints the refusal line and writes nothing
    (`core/LauncherSetup.lua:152-158`).
  - Right-click opens the panel.
- **Suite.** `tests/test_disabled.lua` is declared in `tests/run.lua` and asserts on the mock's
  **registry** by count and by name (`:180-191`). It asserts the v2.57.0 live list (`:335-361`) and
  pins the feature-verb refusal (`:363-392`). The kit's `mock_record.lua` records `RegisterUnitEvent`.
- **Adoption floor.** The vendored tag is v1.55.0, which is at or above v1.42.0.

## 6. Settings (`options-ui`, `savedvariables`, `preview-mode`, `launcher`)

- **Pages and tabs:**

  | Page | Tabs (from the schema's `group` values, in declaration order) |
  |---|---|
  | General | **Master controls** (composed by `H.MasterControls`, `settings/General.lua:64`), then Units (`:120`) |
  | Icons | Sizing, Layout, Visual states, Border, Annotations, Ready glow |
  | Cast bar | General, Size and position, Icon, Font, Spell name, Cast time, Interruptible, Non-interruptible |
  | Text Label | General, Placement, Font |
  | Spells | a hand-drawn single tab |
  | Profiles | exempt |

  Every page draws a strip. There is no Test mode row: KickCD falls under the §15 exemption, where
  unlocking is the preview (`settings/General.lua:19-25`).
- **Colors.** All color rows are composed with `H.ColorPair`, `FontGroup` or `BorderGroup`. There is
  no `disabledIf` on a color row.
- **Controls.** There are no reorder arrows and no hand-written `LSM30_*` groups.
- **Combat.** The only `OpenToCategory` call is the page jump at `settings/Panel_Widgets.lua:135-150`.
  It is combat-gated and uses the integer `:GetID()`, so it is compliant. No settings close in combat
  was found.
- **Launcher.**
  - One LDB object, labeled `Ka0s KickCD` (`core/LauncherSetup.lua:122`), with the icon at `:127`.
  - Rung (b): left-click is `NS.ToggleLock`.
  - `minimap.hide` is written through `GLOBAL_PATHS`, and both resets are held off
    (`docs/ARCHITECTURE.md:209-211`).
- **SavedVariables.** `CURRENT_DB_VERSION = 5` (`core/Database.lua:35`), with the runner steps at
  `:717-720`. Three shape-driven migrators run first (`:821-824`). The register row covering them
  still says "Two" (`KICKCD-B-03`).

## 7. Slash (`slash-commands`)

`NS.COMMANDS` (`core/KickCD.lua:194-304`) holds **17** verbs: help, version, config, enable, disable,
lock, unlock, toggle, list, get, set, reset, resetall, resetposition, spells, debug and perf.
`enable` and `disable` are aliases onto the `enabled` row through `/kcd set`. `lock`, `unlock` and
`toggle` write `locked` through `Helpers.SetAndRefresh` (`:157`).

The `spells` sub-tree reuses `enable` and `disable` for single spell entries (`:733-736`). The
standard is unclear about whether that reuse is allowed inside a sub-tree, so it is filed as Info
(`KICKCD-C-14`).

## 8. Debug and performance (`debug-logging`, `performance`)

- The console is `LibKa0s-DebugLog-1.0`'s. `[Set]` logging follows the bulk-act rule
  (`settings/Panel.lua:220-284`, `core/Units.lua:129-131`, `core/Database.lua:785-797`).
- The perf harness is wired, and `docs/perf-analysis/` holds two frozen bundles, both indexed in its
  README (`:215-216`).
- The three `/kcd debug` state dumps print to **chat** through `NS.Util.print`
  (`core/Compat.lua:441`, `modules/Castbar_Debug.lua:134`, `modules/Cooldowns.lua:661`). The
  `debug.md` "Not applicable" row says they go "through" the console (`KICKCD-C-06`).

## 9. Tests, lint and complexity (`testing`, `lint`, `automated-tests`)

| Check | Result |
|---|---|
| `ka0s-bounded lua tests/run.lua` | **1050 passed, 0 failed, 0 skipped, 1050 total** (exit 0) |
| `ka0s-bounded luacheck .` | **0 warnings / 0 errors in 101 files** (exit 0) |
| `.luacheckrc` | `exclude_files` is libs/, docs/audits/, _dev/, tests/_kit/, docs/reviews/. `tests/` is linted, the harness global sits in `files["tests/"]`, and there is no top-level `ignore` |
| `docs/test-cases.md` against `--list` | identical (0 diff lines) |
| README badge | `1050/1050` |
| `ka0s-bounded lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` | NLOC 20793 over 2640 functions, **0 warnings**, max CCN 15 |
| Kit | revision 25. `test_eol`, `test_prose` and `test_layout_cap` are each declared with `dir = "tests/_kit/"`. `run-automated-tests.sh` is mode 100755 |

**The automated-test record.** The newest bundle is `20260916-184417` at `fac2411`, which is
**38 commits behind HEAD**. The latest release tag, `1.3.0-release`, is `ed88759` from 2026-09-10,
and there has been no release since, so the checkpoint has not come due (`KICKCD-B-04`). The watch
list's four entries have read "watch, no action" for four consecutive runs, and the trackers they
cite are from a retired series (`KICKCD-C-10`).

## 10. Packaging (`packaging`)

The three mechanical checks pass. Check (a) is clean. Check (b) prints only `.git`. Check (c) prints
nothing: `.claude` and `.superpowers` are present and are ignored at `.pkgmeta:20-21`. The comments
at `.pkgmeta:17`, `:20` and `:21` cite `packaging.md:28`, which has since become a line inside the
template (`KICKCD-C-08`).

## 11. `.gitattributes` (`line-endings`)

The body diffs clean against the canonical 84-line client-bound file, with no appendix.

- (a) The file is present.
- (b) `:26` pins `* text=auto eol=crlf`.
- (c) The shebang carve-outs are at `:36-37`.
- (d) There are 20 `binary` lines.
- (e) **0** tracked files disagree with the pin, out of 532.
- The owner of (e) is the kit's `test_eol`, which is green.

## 12. Root docs (`documentation-§1/§2/§7`)

- **README.** The five canonical badges are present, and the standard badge is **bare** (`:6`). There
  is no logo, no library inventory, no command or settings-page table, and every Version History cell
  is bulleted.
  - **Two FAQ and Troubleshooting lines are wrong.** `:97` and `:113` say the panel "waits until
    combat ends" or "opens the moment combat ends". The code refuses and does not defer
    (`core/KickCD.lua:815-819`), and `options-ui-§2` forbids deferring (`KICKCD-C-05`).
- **CLAUDE.md.** A stub with the compliance section, the pointer list, the gate line and the
  provenance line at `:42`.
- **DEPENDENCIES.md.** Present.

## 13. `docs/` (`documentation-§3`)

- **(a) Tier 1.** All six are present.
- **(b) Tier 2.**
  - `slash-dispatch.md`: present, and 17 verbs is at or above 8.
  - `midnight-quirks.md`: present.
  - `compat-layer.md`: present. 8 shims by the §3 grep, which is at or above 3.
    - The Trigger cell says "496 lines", but the file is 485 lines and the rule counts shims.
    - The doc restates the contracts of LibKa0s-Compat's six members (`KICKCD-C-07`).
  - `message-bus.md`: present, although 5 messages does not reach "more than ten". Its Trigger cell
    states no trigger.
  - `profiles.md`: present.
  - `perf-analysis/README.md`: present, and it sits in **Conditional** (so `KICKCD-B-01` is closed).
  - `debug.md`: "Not applicable", but the reason the row gives is untrue (`KICKCD-C-06`).
- **(c) The map.** It has four tables, in order. Every one of the 21 in-scope `docs/*.md` files is
  registered, `debug.md` is the one Not-applicable row, there are no orphans and no dangling rows, and
  the hub registers itself (a MAY, not filed).
- **(d) and (e).** No non-canonical or retired filenames, and no `docs/perf-runs/` or
  `docs/pending/`.
- **(f) Hub shape.** `docs/ARCHITECTURE.md` is **468 lines**, over the roughly 400-line SHOULD
  (`KICKCD-C-09`). No mandated section is over roughly 60 lines.

## 14. The register and the issue store (`documentation-§3`, `audit-review-history`)

**`## Documented deviations` holds seven rows (`docs/ARCHITECTURE.md:388-396`).** For each one, this
run read whether the cited rule had changed, evaluated its trigger, and resolved its evidence ids. The
full table is in `02_DEVIATIONS.md`. Six rows are accepted. The first `savedvariables-§1` row states
something the tree has moved past (`KICKCD-B-03`).

**Issues** were read with
`gh issue list --state all --limit 200 --json number,title,state,labels,url`. There are 22 issues,
and every one carries both a `state:` label and a `severity:` label. Three anomalies:

- **#15** is OPEN but labeled `state:done` (`KICKCD-C-11`).
- **#12**'s decline says "no control in this addon wants" Widgets, but the addon has since adopted
  it (`KICKCD-C-12`).
- **#9** still has an `[Optional]` title prefix (`KICKCD-B-05`).

There is no `docs/pending/LEDGER.md`. The declines in #11, #12 and #14 are compliance under the
library-stack-§3/§7 prune rule and owe no register row.

**Re-vendor bundles.** Eight bundles are in `docs/revendor/`. The payload-derived check finds **25**
tags vendored since the store's horizon (2026-08-25) that no bundle names and no register row
explains (`KICKCD-C-01`).
