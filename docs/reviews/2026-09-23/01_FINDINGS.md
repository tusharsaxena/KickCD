# 01 — Findings (KickCD full-scope review, 2026-09-23)

**Verdict: minor issues. No Critical findings. Two High findings are worth fixing before the next release: per-profile color migrations silently skip every profile that wasn't active at upgrade (F-001), and the Spells page leaks tooltip hooks into AceGUI's shared widget pool, which reaches other addons (F-002).**

Reviewed at `dc11094` on branch `feat/2026-09-23-review-audit-remediation` (working tree clean). Standard resolved: **Ka0s WoW Addon Standard v2.64.0 (2026-09-23)**, fetched verbatim via `curl` from `standards/STANDARDS.md` plus all 27 linked section files. The standards cross-check was run.

## Measurement run (Step 0 — every suite re-run today, 2026-09-23)

All runs went through `~/.claude/wow-addon/bin/ka0s-bounded`. It is not on `PATH` in this shell, so it was called by absolute path and no `timeout 900` fallback was needed. Output went to a scratch directory outside the repo, and no committed artifact was touched.

| Suite | Result | Command (repo root) |
|---|---|---|
| luacheck | **pass**: 0 warnings / 0 errors in 101 files | `ka0s-bounded luacheck .` |
| Headless suite | **pass**: 1050 passed, 0 failed, 0 skipped, 1050 total | `ka0s-bounded lua5.1 tests/run.lua` |
| `--list` inventory | **pass**: generated to scratch. Identical to committed `docs/test-cases.md` (`diff` after CR-strip is empty) | `ka0s-bounded lua5.1 tests/run.lua --list > $SCRATCH/test-cases.md` |
| Offline perf | **ran**: 6 scenarios (table below) | `ka0s-bounded lua5.1 tests/perf.lua` |
| Complexity | **ran**: 20 793 NLOC, 2 640 functions, avg CCN 2.1, **max CCN 15**, 0 over threshold | `ka0s-bounded lizard -l lua -x "./libs/*" -x "./tests/_kit/*" . > $SCRATCH/complexity.txt` |
| `make test` | **skipped**: no root `Makefile` | — |
| Vendor sync | **pass**: `diff -rq libs/LibKa0s ../LibKa0s/LibKa0s` and `diff -rq tests/_kit ../LibKa0s/testkit` both empty. `CLAUDE.md` names v1.55.0 | both `diff -rq` |
| Cross-addon: slash tokens | **pass**: 20 roots across 10 addons, 0 duplicates, 0 raw `SLASH_*` in any TOC-loaded file | the two loops in the agent brief, scope = each addon's TOC-derived `.lua` load list |
| Cross-addon: LibKa0s minors | **pass**: one line for all 10. `Bus:1 Compat:1 Core:7 DebugLog:12 Env:1 Item:1 Launcher:1 Lifecycle:1 Media:3 Options:23 Perf:12 Pool:3 Schema:1 Slash:14 Widgets:9` | minors loop |
| Cross-addon: payload bytes | **pass**: `diff -rq KickCD/libs/LibKa0s <each>/libs/LibKa0s` is empty for all 10, with KickCD as the reference | payload loop |
| Cross-addon: `## Interface:` | **pass**: `120100` in all 10 | interface loop |

**Cross-addon scope.** The pass covered **ten** repos: AbsorbTracker, AuraMaster, BankLedger, ConsumableMaster, KickCD, LootHistory, MultiMeters, PanelMaster, PrettyChat and WhatGroup. The brief lists nine; AuraMaster is in the current Ka0s roster, so it was included. Three things differ from the 2026-09-07 baseline: `## Interface:` moved from 120007 to 120100, there are now 15 majors instead of 10, and minors were bumped. **Every one of those moves is uniform across all ten repos.** They are version moves, not collisions, so this is a measured non-finding.

**Today's offline perf numbers.** For orientation only; compare within this run.

| scenario | ms/iter | api/iter | bytes/iter |
|---|---|---|---|
| spellPoll | 0.02021 | 18.0 | 1196.3 |
| spellState | 0.00558 | 0.0 | 1697.3 |
| iconApply | 0.00240 | 0.0 | 848.0 |
| probeOverheadOff | 0.00261 | 0.0 | 848.0 |
| probeOverheadOn | 0.00273 | 0.0 | 848.1 |
| castStart | 0.00518 | 0.0 | 208.9 |

The zero-overhead pair holds: the dormant bracket costs 848.0 bytes against 848.1 armed.

**Committed artifacts that disagree with today's run:**
- `docs/automated-tests/RESULTS.md` is newest bundle `20260916-184417`, SHA `fac2411`, v1.3.0. It records **973** tests, 19 884 NLOC, 2 494 functions and **4** files in the `layout-§1` 1000–1500 band. Today's run has **1050** tests, 20 793 NLOC, 2 640 functions and **5** band files (see F-010). This is stale, not non-compliant: it regenerates at release.
- `docs/performance.md` has a stale bucket table (see F-009).
- `docs/test-cases.md` and the README `[tests]` badge (`1050/1050`) **agree** with today's run.

**Censuses in this bundle** use the default scope unless stated: `git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`, which is authored Lua with `tests/` included.

**Line endings (observation only; `line-endings-§2` belongs to the standards audit).** `.gitattributes` carries `* text=auto eol=crlf`, the `*.sh`/`*.py` LF carve-outs and the binary list. `git ls-files --eol` reports exactly one `w/lf` file, the `.sh` carve-out.

## Conventions detected (checks applied only where the convention exists)

- **Chat printer.** `NS.Util.print` is published by `core/CoreSetup.lua` from `LibKa0s-Core-1.0`. No raw `print(` sits in shipped paths outside guarded fallbacks.
- **`COMMANDS` table.** It lives in `core/KickCD.lua:194-252`, and LibKa0s-Slash dispatches it.
- **Single write seam.** `Helpers.SetAndRefresh` / `Helpers.Set` in `settings/Panel_Render.lua:273` and `settings/Panel.lua:380`. `core/Database.lua` is the only writer of the spell registry.
- **Settings schema.** Rows are composed through LibKa0s-OptionsCompose. There is no `Schema.lua`, and no secret-values document under that name; the equivalent is `docs/midnight-quirks.md`.
- **Vendored LibKa0s v1.55.0.** Wired seams: `CoreSetup`, `EnvSetup`, `PoolSetup`, `MediaSetup`, `DebugLogSetup`, `LauncherSetup`, `LifecycleSetup`, `PerfSetup`, `settings/OptionsSetup.lua`, `settings/Slash.lua`, and `core/Compat.lua` (Compat and Bus).
- **Test kit** is vendored at `tests/_kit/`.
- **Evidence the addon generates about itself:** `tests/run.lua` (1050 cases), `docs/test-cases.md`, `tests/perf.lua`, `docs/performance.md`, two `docs/perf-analysis/` bundles (`20260807-131311` and `20260909-014035`, both on v1.2.1), and `docs/automated-tests/` (RESULTS plus 11 bundles).

---

## High

### F-001 — Per-profile color and font-flag migrations run once per account, so every profile not active at upgrade keeps its pre-1.3.0 shape `[savedvariables]` `[design]`

- **Where:** `core/Database.lua:719-720`, quoted:
  ```
  [3] = function(db) NS.Database:MigrateColorShape(db); db.global.schemaVersion = 4 end,
  [4] = function(db) NS.Database:MigrateFontFlags(db); db.global.schemaVersion = 5 end,
  ```
  These are gated by `:752`, `while g.schemaVersion < CURRENT_DB_VERSION do`. `OnProfileChanged` (`:821-826`) re-runs only the shape-driven steps: `FoldLegacyUnits`, `BackfillLabelStyle`, `MigrateSpecKeys` and `BuildSpells`. It does not re-run `MigrateColorShape` or `MigrateFontFlags`.
- **Problem:** `schemaVersion` lives in `db.global`, but both steps walk only `db.profile`. They therefore rewrite only the profile that was active when the account first loaded 1.3.0. The file's own docstring for `MigrateSpecKeys` (`:586-591`) names this trap ("a version-gated step would migrate only whichever profile happened to be active at upgrade time"), and v4/v5 fall into it anyway.
- **Impact:** On every other profile, each customised color reads back as its **default**. AceDB has already merged the keyed defaults into the hybrid table, and every reader keys on `.r`. The user's values survive in the array part, where nothing reads them. Font-flag dropdowns stored as `"NONE"` open blank.
- **Measured:** a scratch repro (`$SCRATCH/repro_migrate.lua`) loaded the real TOC under the kit's mock and planted a hybrid `{0.1,0.2,0.3,1, r=1,…}` on `units.target.castbar.textColor` with `fontFlags="NONE"` at `schemaVersion=5`. It then called `Database:OnProfileChanged("OnProfileChanged", db, "Other")`. The output was `after swap: [1]=0.1 r=1 (user value 0.1; default 1)` and `fontFlags=NONE`: nothing was converted.
- **Reachability:** any player who upgraded from ≤1.2.1 (tag `1.2.1-release`, 2026-07-26) to 1.3.0 (tag `1.3.0-release`, 2026-09-10; both steps landed in that window) while holding **more than one** KickCD profile — per-character, per-class or named — and later switches to a profile other than the one active at first 1.3.0 login. Those are ordinary AceDB features reached from the Profiles page.
- **Coverage:** `tests/test_database.lua` and `tests/test_color_shape.lua` exercise each migrator directly and the version walk on the active profile. **No case covers a profile swap after the account is already at v5.** The mock AceDB has no `SetProfile`, so the path cannot currently be reached from the suite at all.
- **Fix direction:** make both steps shape-driven and run them from `OnProfileChanged` (and `Init`) beside `MigrateSpecKeys`. Both are already idempotent: `looksLikeColor` needs a numeric `[1]`, and `fix` needs the literal `"NONE"`. Keep the version steps so `schemaVersion` still advances. This extends the existing `savedvariables-§1` register row in `docs/ARCHITECTURE.md` ("two profile migrators run off the stored shape"), and that row must be updated to name four. It does not create a new deviation.

### F-002 — The Spells page `HookScript`s AceGUI's pooled Label and Dropdown frames, so its tooltips leak into every AceGUI consumer in the session `[ux]` `[frames]` `[cross-addon]`

- **Where:** `settings/Spells.lua:662-666`, quoted:
  ```
  label.frame:EnableMouse(true)
  label.frame:HookScript("OnEnter", function() showSpellTooltip(label) end)
  label.frame:HookScript("OnLeave", hideSpellTooltip)
  ```
  Also `:763-770` (`dd.frame:HookScript("OnEnter", …)` showing "Category for future filtering…").
- **Problem:** AceGUI widgets are recycled through **one process-global pool**. `releaseAceGUITree()` (`:853-865`) and panel `OnHide` (`:1295-1300`) hand these frames back. A hook cannot be removed, and neither AceGUI Label's `OnAcquire` (`libs/AceGUI-3.0/widgets/AceGUIWidget-Label.lua:72-89`) nor the Dropdown's resets `EnableMouse` or scripts. Every render adds another hook pair to each recycled frame.
- **Impact:** after the Spells page renders once, any Label that another panel acquires from the pool keeps a closure showing a **KickCD spell tooltip** on hover. It also stays mouse-enabled, so it can swallow clicks meant for whatever sits beneath it. Any recycled Dropdown shows KickCD's category tooltip. That includes KickCD's own other pages and the options pages of the other Ka0s addons that create AceGUI `Label` widgets (AbsorbTracker, AuraMaster, BankLedger, ConsumableMaster, LootHistory, PanelMaster, PrettyChat, per `grep -l 'Create("Label"' ../*/settings`). Hook count grows by one pair per row per render, and F-008 doubles the renders.
- **Reachability:** any player who opens KickCD's Settings → Spells page and then, in the same session, opens any AceGUI-based UI. Under the collection's stated deployment of all addons loaded together, that is a normal session.
- **Coverage:** none. No suite asserts on scripts left on released widgets.
- **Fix direction:** stop hooking recycled frames. Use `AceGUI:Create("InteractiveLabel")`, whose `OnEnter`/`OnLeave` callbacks are cleared on `Release`, with `SetCallback`. For the dropdown, use the library seam `H.AttachTooltip(dd, …)`, which takes AceGUI's `SetCallback` arm. This is compliant with `options-ui-§1`: it uses the library helper and hand-rolls nothing.

## Medium

### F-003 — Per-unit cast-event dispatch frames are rebuilt on every enable, adding 36 frames per disable/enable cycle `[frames]` `[perf]`

- **Where:** `core/Util.lua:437-445` (`local f = CreateFrame("Frame")` per call), `modules/IconGrid.lua:810-822` (8 events per unit), `modules/Castbar.lua:1016-1031` (10 events per unit). Teardown drops them in `IconGrid.lua:831-832` and `Castbar.lua:1044-1045` (`inst.eventFrames = {}`), and WoW frames are never garbage-collected.
- **Problem:** `events-frames-taint-§1` carves this frame out and adds: "It **MUST** be re-used across a disable/enable cycle rather than rebuilt, so flicking the switch does not leak one frame per turn." Here each `EnableUnit` mints fresh frames. There are also 18 single-event frames per unit where one frame per (module, unit) can carry every `RegisterUnitEvent`.
- **Measured:** a scratch run (`$SCRATCH/repro_frames.lua`, real TOC under the kit mock) toggled `SetAndRefresh("enabled", false/true)` three times. Frame counts: `142 → 178 → 214 → 250`, **+36 per cycle**.
- **Reachability:** any player who uses `/kcd disable` + `/kcd enable`, the *Enable KickCD* checkbox, a per-unit *Enable* toggle, a profile switch that flips `enabled`, or runs `/kcd perf` (the suspended arm stands down and back up).
- **Coverage:** `tests/test_disabled.lua` "RE-ENABLED: the registration set comes back, exactly" (`:436`) counts registrations by name, so it cannot see orphaned frames.
- **Fix direction:** hold one filter frame per (module, unit) on `inst`, created once. Re-register its events in `EnableUnit`/`Resume` and `UnregisterAllEvents()` it in teardown. Keep the frame on the instance, as the carve-out requires.

### F-004 — `scheduleTimer` returns nil, so LibKa0s' color-picker throttle never engages `[perf]`

- **Where:** `settings/OptionsSetup.lua:243`, quoted: `scheduleTimer = function(fn, delay) return _G.C_Timer.After(delay, fn) end,`
- **Problem:** `C_Timer.After` returns nothing. The library uses the **return value** as its "armed" flag: `timer = d.scheduleTimer(function() … end, COLOR_THROTTLE)` / `if timer then return end` (`libs/LibKa0s/OptionsWidgets.lua:1471-1482`). With nil it re-arms on every `OnValueChanged`.
- **Impact:** each color-drag tick (~60 Hz) schedules its own delayed commit. Each commit is a `SetAndRefresh`, which means a `CONFIG_CHANGED` fan-out to IconGrid/Castbar/UnitLabel plus a `RefreshScalars` sweep. The library's stated "O(1) garbage" design is defeated.
- **Reachability:** any player dragging a color swatch on any KickCD settings page.
- **Coverage:** none. No case pins the throttle's call count.
- **Fix direction:** return a handle: `return _G.C_Timer.NewTimer(delay, fn)`, matching the siblings that return `NS.addon:ScheduleTimer(...)`. The library-side root cause is U-001.

### F-005 — `/kcd spells add` disagrees with the Spells page on what it accepts `[ux]` `[design]`

- **Where:** `core/KickCD.lua:501-505` (`tokenize` on `%S+`), `:617-624` (`resolveSpellInput(args[1])`), `:570-584` (`resolveSpellInput`), against `settings/Spells.lua:272-285` (`validateSpellInput`, a line-for-line copy) and `:461-473` (`cooldownManagerRejects`, applied only on the page).
- **Problem:** there are three divergences on one verb.
  1. A multi-word spell name is split, and only its first word is resolved. `/kcd spells add Wind Shear` tries "Wind" and treats "Shear" as the class token.
  2. The Blizzard Cooldown Manager gate the page enforces for the player's own spec is skipped. The README (`README.md:95`) says "only spells the game already tracks as cooldowns can be added".
  3. The ID/name resolver exists twice.
- **Impact:** the documented `<id|name>` form fails for most interrupts (Wind Shear, Mind Freeze, Spell Lock, Skull Bash, Counter Shot…). The CLI also admits spells the panel would refuse.
- **Reachability:** any player using the documented `/kcd spells add <name>` command.
- **Fix direction:** move the resolver and the Cooldown Manager check into one shared helper beside `Database`'s verbs (single-writer rule, `architecture-§5`), and call it from both surfaces. Take `[CLASS SPEC]` as the trailing tokens only if they resolve, and treat the rest as the name.

### F-006 — Empowered casts are not tracked by the cast bar or the icon grid's cast-state logic `[logic]` — **unverified in client**

- **Where:** `modules/Castbar.lua:1016-1027` and `modules/IconGrid.lua:810-819`. Neither registers `UNIT_SPELLCAST_EMPOWER_START` / `_STOP` / `_UPDATE`, and `grep -rni empower core modules settings` returns nothing. Sibling PartyFrameEnhanced does register them (`../PartyFrameEnhanced/modules/CastBars.lua:34`).
- **Problem:** empower casts report through `UnitChannelInfo` but announce and end on the EMPOWER events. KickCD therefore only notices one on an unrelated re-evaluation (target change), and does not see it end.
- **Impact:** the bar does not appear for an empower started after targeting. A bar started by `Reevaluate` mid-empower may persist until the next target or cast event. In the `target_casting*` modes, visibility and glow lag the same way.
- **Reachability:** players targeting an enemy Evoker using empowered spells, mainly in PvP. Whether any NPC uses empower is unknown, and that is the reason this is marked unverified.
- **Fix direction:** add the three events to both modules' lists, mapped to `OnChannelStart` / `OnCastStop` / `OnCastDelayed` and `OnUnitCastEvent`. Verify in client before shipping (see `03_SMOKE_TESTS.md`).

### F-007 — IconGrid's rebuild repaints every icon "ready" and relies on unordered event dispatch to be corrected `[design]` — **unverified in client**

- **Where:** `modules/IconGrid.lua:351` (`btn:Apply({ ready = true, start = 0, duration = 0 }, true)` in every `BuildActiveList`), with `:1290-1306` (PEW / SPELLS_CHANGED / TRAIT_CONFIG_UPDATED rebuilds) against `modules/Cooldowns.lua:547-555`, which handles the same events with its own `Rebuild` emit.
- **Problem:** both modules subscribe to the same game events and to `PROFILE_CHANGED` / `CONFIG_CHANGED{spells}` through AceEvent. CallbackHandler fires registrants in `pairs` order, which is unspecified. If Cooldowns runs first, its `SPELL_STATE` lands on the old pool, and IconGrid then releases it and seeds a synthetic "ready". Nothing replays the real state until the next `SPELL_UPDATE_*`.
- **Impact:** an interrupt that is on cooldown can read as ready after a talent swap, pet summon, spec change, profile switch or `/reload`. It stays wrong until the next cooldown event, which in combat is usually one GCD.
- **Reachability:** any player on those paths, on roughly half of dispatch orderings.
- **Fix direction:** after `BuildActiveList`, seed each icon from `Cooldowns.watched[spellID]` when present rather than from the synthetic ready frame. That is a pull over a published read-only accessor, so it avoids cross-module table access (`architecture-§4`, anti-pattern #19). Alternatively, have Cooldowns re-emit on `GRID_LAYOUT`. Either removes the order dependence.

### F-008 — Every Spells-page edit renders the whole page twice, and an error mid-render freezes the page for the session `[perf]` `[logic]`

- **Where:** `settings/Spells.lua:404-407`, quoted:
  ```
  local function doCommit()
      if panel and panel:IsShown() then Spells:RefreshRows() end
      FireConfigChanged()
  ```
  `FireConfigChanged` dispatches synchronously to this page's own subscriber at `:1345-1350`, which calls `Spells:RefreshRows()` again. The `rebuildScheduled` guard (`:1181-1182`) has already been cleared at `:1243`.
- **Impact:**
  1. Two full AceGUI tree teardowns and rebuilds per enable/category/remove/add/drag, which also doubles F-002's hook growth.
  2. If `fillRows` raises, `rebuildScheduled` stays `true`, and every later `RefreshRows` returns at `:1181` for the rest of the session. The comment at `:1186-1188` says the flag "is cleared on EVERY exit", which is true of the explicit returns only.
- **Reachability:** any player editing a spell on the Spells page. The stuck flag needs an error during render.
- **Fix direction:** have `doCommit` only announce and let the subscriber render, or keep the direct render and skip the subscriber when the page itself is the source. Clear the flag in a `pcall`/finally shape.

### F-009 — `docs/performance.md`'s bucket table no longer matches the descriptor, and one declared nesting is wrong on the Rebuild path `[perf]` `[docs]`

- **Where:**
  - `docs/performance.md:40` says `spellState` sits inside `spellPoll` and omits `stateEmit`. `:52` says "`glowGate` … is deliberately **not declared**".
  - `core/PerfSetup.lua:100-101,105` declare `stateEmit` within `spellPoll`, `spellState` within `stateEmit`, and `glowGate`.
  - `modules/IconGrid.lua:994` (`Perf.Note("spellState", …)`) passes no observed parent, and `modules/Cooldowns.lua:339` (the Rebuild emit) is not bracketed as `stateEmit`. So `spellState` from a Rebuild runs outside its declared parent.
- **Impact:** a reader of the write-up reads captures against the wrong tree. Both committed captures (`docs/perf-analysis/20260909-014035/dump.json`: `"spellState":{…,"within":"spellPoll"}`) predate the current nesting. No capture yet exists for the 1.3.0 bucket set.
- **Reachability:** a maintainer reading perf evidence (documentation and evidence only).
- **Fix direction:** regenerate the table from the descriptor, pass the parent key at `IconGrid.lua:994` as `iconApply` already does, and take the next in-game capture on 1.3.x.

### F-010 — `layout-§1` band drift since the last recorded run: Spells.lua has passed its own re-check trigger `[complexity]`

- **Census:**
  ```
  git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | tr '\n' '\0' | xargs -0 wc -l | awk '$2!="total" && $1>=1000'
  ```
  Default scope: tracked authored Lua, `tests/` in, `libs/` and `tests/_kit/` out. Output: `settings/Spells.lua` **1444**, `modules/Castbar.lua` **1423**, `modules/IconGrid.lua` **1343**, `tests/wow_mock.lua` 1129, `modules/IconGrid_Render.lua` **1014**. Zero files are over 1500.
- **Against `RESULTS.md` (20260916):** Spells 1246 → 1444 (+198, **past its own "Re-check at 1400" disposition**), IconGrid 1163 → 1343 (+180), Castbar 1345 → 1423 (+78), wow_mock 1060 → 1129. `IconGrid_Render.lua` is new to the band, and its row has a blank Disposition.
- **Fresh lizard:** max CCN 15 (`buildSpecNameMaps@260-297@core/Util.lua`, `State.ApplyInterruptibleAlpha@109-128@core/State.lua`, `Layout.layoutBlock@145-249@modules/IconGrid_Layout.lua`). Zero functions over threshold. The CCN is mostly `and`/`or` guard density, not tangled control flow.
- **Reachability:** maintainability only.
- **Fix direction:** peel `settings/Spells.lua` along its existing seams (row builders `:590-835`, cooldown-manager cache `:287-384`). This is not a complexity gate on commits (#51/#52). The watch list regenerates at release.

### F-011 — The High and Medium findings above sit on paths no case covers `[tests]`

- **Gaps:**
  - F-001: no profile swap at the current version; the mock AceDB has no `SetProfile` (`tests/wow_mock.lua:573-640`).
  - F-002: no assertion on scripts or mouse state left on released AceGUI widgets.
  - F-003: no frame count across a disable/enable cycle. `mocks.__frames` exists (`tests/wow_mock.lua:769`) and is not asserted on.
  - F-004: no throttle call count.
  - F-008: no render count per commit.
- **Also:** the shared instance swallows an `OnInitialize` raise, `tests/run.lua:105` (`if initDB and NS.OnInitialize then pcall(NS.OnInitialize, NS) end`). Only `test_database`'s "OnInitialize built a live db" would notice it, indirectly.
- **Reachability:** test inventory only; the shipped defects are covered by F-001 through F-008.
- **Fix direction:** add a case per fix, each with a `-- red under:` line (`testing-§12`). Grow the mock's AceDB a real `SetProfile` in `tests/wow_mock.lua` (the addon's own mock, not the kit).

## Low

### F-012 — Stale or wrong comments `[naming]`

- `core/KickCD.lua:13-19` describes an `_G.KickCD` rebind; `:23-27` of the same file says "there is NO _G.KickCD rebind".
- `modules/Cooldowns.lua:35-38` and `:648-650` describe master-enable recovery through a `general` rebuild. That was superseded by the Lifecycle latch.
- `core/Util.lua:101` calls `Util.Throttle` "Leading-edge"; it fires trailing, with the last args.
- `settings/Spells.lua:1411` ("The cost is precisely one thing") understates it: slash-driven spell edits and profile switches also stop refreshing an open page while disabled.
- **Reachability:** comments; no runtime effect.

### F-013 — Three readers of the master `enabled` path, one of which claims to be the only one `[design]`

- `core/LifecycleSetup.lua:59` ("THE one reader of the stored path"), `modules/Cooldowns.lua:298-302` (`isEnabled`, a copy), and `core/Units.lua:33-37` (`Units.IsEnabled` reads `p.enabled`).
- Cooldowns' `Rebuild`/`Refresh` early returns (`:311`, `:408`) are dead under the latch, which already unregisters the module.
- **Reachability:** none at runtime; a drift hazard.

### F-014 — Reset-position and combat-open wording promise more than the code does `[ux]`

- `/kcd resetposition` (`settings/Panel_Render.lua:358-377`) resets only the **target** icon grid; the focus grid and both cast bars are untouched. Its help text says "the icon grid".
- `README.md:97` says "`/kcd config` waits until combat ends". `NS:OpenSettings` (`core/KickCD.lua:815-819`) refuses and does not defer.
- **Reachability:** any player reading the README or help; the behavior itself is safe.

### F-015 — `GateHint` probes by writing candidate values into the live profile `[design]`

- `settings/Slash.lua:127` `parent[key] = candidate` … `:129` `parent[key] = gateVal`. This is a temporary write around the single write seam.
- It is safe only while every `row.values()` is pure and nothing else runs in between.
- **Reachability:** a player whose `/kcd set` value is rejected on a `valueGate` row.

### F-016 — `.luacheckrc` whitelists deprecated globals nothing in shipped code reads `[lint]`

- `.luacheckrc:57` (`"GetSpellInfo", "GetSpecialization", "GetSpecializationInfo"`) and `:63` (`"IsPlayerSpell", "IsSpellKnown", …`). A bare-name count over the default scope, excluding `tests/`, is 0 for each.
- A regression to a bare deprecated call would lint clean.
- **Reachability:** development only.

### F-017 — A disabled-at-login addon re-registers a `PLAYER_LOGIN` that will never fire `[lifecycle]`

- `core/State.lua:213` `if not State.__seeded then boot:RegisterEvent("PLAYER_LOGIN") end`.
- The first hold is taken inside `PLAYER_LOGIN` itself (`core/KickCD.lua:109`), so the "enabled again before login" case in the comment cannot occur. After the first `/kcd enable`, a dead registration remains.
- **Reachability:** a player who logs in with KickCD disabled and then enables it; harmless beyond one entry.

### F-018 — `/kcd spells` accepts any CLASS token or numeric spec and lazily creates lists for them `[ux]` `[savedvariables]`

- `core/KickCD.lua:532-547` passes `NormalizeClassToken` output unvalidated (`core/Util.lua:406-408`), and `ResolveSpecID` returns any number (`:347-351`). `Database:AddSpell` → `EnsureSpellList` (`core/Database.lua:147-154`) then writes `spells.WARLORD[99999]`.
- The bare `/kcd spells` prints the default spec as a raw ID (`core/KickCD.lua:764`), where every other line uses `SpecDisplay`.
- **Reachability:** a player who mistypes a class or spec on a documented command; the orphan lists are inert.

---

## Upstream findings (do not land in this repo)

### U-001 `[upstream]` LibKa0s — `OptionsWidgets.lua` uses the host's `scheduleTimer` return value as its "armed" flag

- **Owning library / file:** `LibKa0s` → `LibKa0s/OptionsWidgets.lua` (vendored here as `libs/LibKa0s/OptionsWidgets.lua:1326-1337` slider live-commit and `:1471-1482` color throttle). The contract is at `libs/LibKa0s/Options.lua:537-539`, which does not say a truthy handle is required.
- **Problem:** a host returning nil, which is `C_Timer.After`'s documented return, silently turns the throttle into a per-event re-arm.
- **Reachability:** KickCD today (F-004). LootHistory and MultiMeters also pass `C_Timer.After` wrappers that return nil (`LootHistory/settings/OptionsSetup.lua:205-207`, `MultiMeters/settings/OptionsSetup.lua:270-272`), so every consumer with a color row or a live slider is affected.
- **Fix direction:** fix in the LibKa0s repo by tracking "armed" in a library-local boolean, independent of the returned handle, and document the field. Bump `OptionsWidgets.lua`'s LibStub minor, then **re-vendor the whole `LibKa0s/` folder** into KickCD and every consumer as its own commit. This is **not** a local edit under `libs/`.
