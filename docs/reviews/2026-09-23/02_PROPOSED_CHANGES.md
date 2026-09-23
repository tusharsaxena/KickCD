# 02 — Proposed changes (HLD + LLD)

**Standard resolved:** Ka0s WoW Addon Standard **v2.64.0 (2026-09-23)**. It was fetched verbatim, with the index and all 27 section files, so the standards conformance check below was **run**. It works as a guardrail on these changes, not as an audit.

## HLD — themes

### T1. Per-profile data migrations are shape-driven, everywhere (F-001)

**What changes.** `MigrateColorShape` and `MigrateFontFlags` join `FoldLegacyUnits`, `BackfillLabelStyle` and `MigrateSpecKeys` as steps that run on every profile load: `Init` and every `OnProfileChanged`. The version steps stay, so `schemaVersion` still advances.

**Why this and not a per-profile version stamp.** A per-profile `dbVersion` is exactly what KCD-20 removed in favor of `db.global.schemaVersion` (`savedvariables-§1`). Re-adding it would reintroduce the AceDB backfill-masking trap. Shape detection is already how this file handles the other three per-profile migrations, and both of these functions are already idempotent.

**Trade-off.** Two walks per profile swap: a bounded-depth walk over roughly 230 rows, plus nine fixed paths. The cost is negligible, and they only run on swap and init.

### T2. Nothing the Spells page builds outlives its AceGUI widget (F-002, F-008)

**What changes.**
- Tooltips move from `HookScript` on pooled frames to AceGUI callbacks, which `Release` clears. That means the `InteractiveLabel` widget for the spell name, and `H.AttachTooltip` for the dropdown.
- `doCommit` renders once per commit.
- The render guard is cleared on error too.

**Rejected.** Adding an `OnRelease` that strips the hooks. `HookScript` cannot be undone, so a strip would have to `SetScript(nil)`, and that would also delete AceGUI's own handlers on a frame the page does not own.

### T3. Unit-filter frames are created once and reused (F-003)

**What changes.** One `RegisterUnitEvent` filter frame per (module, unit), held on `inst`. It is re-registered on enable and unregistered on stand-down. `Util.RegisterUnitCastEvent` becomes `Util.UnitCastFilter(inst, module, unit, events)`, which takes the whole event list and one handler map.

**Why.** `events-frames-taint-§1`: "It **MUST** be re-used across a disable/enable cycle rather than rebuilt." The same section forbids "a general-purpose private-frame factory". The new helper builds exactly one filter frame per unit and does nothing else, so it stays inside the carve-out.

### T4. Honor the throttle contract, and harden it upstream (F-004, U-001)

**What changes.**
- **Local:** `scheduleTimer` returns a real handle via `C_Timer.NewTimer`.
- **Upstream:** LibKa0s stops trusting the return value; see the upstream change-set below.

### T5. One spell-input path for both surfaces (F-005, F-018)

**What changes.** A single `NS.SpellInput` (`Resolve`, `Admissible`, `ParseTail` — see C-05) beside the Database verbs does name/ID resolution, the multi-word name, the class/spec validation, and the Cooldown Manager gate for the player's own spec. `core/KickCD.lua` and `settings/Spells.lua` both call it.

**Rejected.** Teaching the CLI tokenizer to quote names. That is a grammar the rest of `/kcd` doesn't have (`slash-commands`), and it would still leave two resolvers.

### T6. Cast-state completeness and state replay (F-006, F-007)

**What changes.**
- Register the three EMPOWER events. They ride T3's single frame.
- After `BuildActiveList`, seed each icon from Cooldowns' published last state, instead of the synthetic "ready", when a state exists.

### T7. Evidence and hygiene (F-009 to F-017)

- Fix the perf write-up and the one missing parent key.
- Peel `settings/Spells.lua`.
- Correct the comments, collapse the master-enable readers, and trim the lint allow-list.
- Add the tests F-011 names.

## Upstream change-set (lands in the LibKa0s repo, not here)

| ID | Repo / file | Fix | Minor bump | Consumer follow-up |
|---|---|---|---|---|
| U-001 | `LibKa0s` → `LibKa0s/OptionsWidgets.lua` (color throttle `:1471-1482`, slider live commit `:1326-1337` in the vendored copy); `LibKa0s/Options.lua` descriptor doc `:537-539` | Track "armed" in a library-local boolean that is set before calling `d.scheduleTimer` and cleared in the callback. Ignore the returned handle. Document that the return value is not used. Add a LibKa0s-side case with a nil-returning `scheduleTimer` that asserts one commit per window. | `OptionsWidgets.lua` minor +1. `Options.lua` only if code changes; a doc-only comment still ships in the file, so bump it if the file changes at all. | Tag a LibKa0s release, then **re-vendor the whole `libs/LibKa0s/` and `tests/_kit/` folders** into KickCD (and every consumer: LootHistory and MultiMeters are directly affected) as its own commit. Update the provenance line in `CLAUDE.md` in that same commit. `tests/test_vendor_sync.lua` gates it. |

**No entry below targets a path under `libs/` or `tests/_kit/`.**

## LLD — change-set per finding

### C-01 (F-001) — shape-driven color and font-flag migration on every profile

- **Files:** `core/Database.lua`, `docs/ARCHITECTURE.md` (register row), `docs/schema.md`, `tests/wow_mock.lua` (AceDB `SetProfile`), `tests/test_database.lua` or `tests/test_color_shape.lua`.
- **Sketch:**
  ```lua
  -- Database:OnProfileChanged, and Database:Init, after MigrateSpecKeys:
  self:MigrateColorShape(self.db)   -- idempotent: needs a numeric [1]
  self:MigrateFontFlags(self.db)    -- idempotent: needs the literal "NONE"
  ```
  `migrations[3]`/`[4]` still call them, which is harmless and keeps the walk for v1–v3 accounts intact. `MigrateColorShape` currently dereferences `db.profile` unguarded (`:666`), so add `if not (db and db.profile) then return end`.
- **Test:** stage two profiles in the mock, one positional and one hybrid, with `schemaVersion = 5`, then `SetProfile("Other")`. Assert `.r == 0.1` and `[1] == nil`. Add a `-- red under: removing the MigrateColorShape call from OnProfileChanged` line.
- **Risk:**
  - `looksLikeColor` must not match a non-color three- or four-number array. The existing narrow shape test is the guard, and today's schema has no such row.
  - A user who **already** edited a color on an unmigrated profile after 1.3.0 has a keyed value plus a stale array part. The array part is the "user's real color" by this migration's own rule, so it would win.

  **Mitigation:** convert only when the keyed part equals the declared default; otherwise drop the array part. State this in `docs/schema.md`.
- **Standards:** `savedvariables-§1`. It extends the existing ratified register row ("two profile migrators run off the stored shape") and does not add a deviation. Update that row's text to name all five shape-driven steps.

### C-02 (F-002) — callbacks, not hooks, on pooled widgets

- **File:** `settings/Spells.lua` `rowNameLabel` (`:653-668`) and `rowCategoryDropdown` (`:755-772`).
- **Sketch:**
  ```lua
  local label = AceGUI:Create("InteractiveLabel")   -- callbacks cleared on Release
  label:SetText(name); label:SetWidth(238)
  label:SetCallback("OnEnter", showSpellTooltip)
  label:SetCallback("OnLeave", hideSpellTooltip)
  -- dropdown:
  H.AttachTooltip(dd, L["Category"], L["Category for future filtering. Currently informational only."])
  ```
- **Risk:** `InteractiveLabel` has a highlight texture. Pass `label:SetHighlight(nil)` if the visual change is unwanted.
- **Test:** render the page twice, release, then acquire a `Label`. Assert its frame has no `OnEnter` script from KickCD and `IsMouseEnabled()` is false (the kit mock records scripts as lists).
- **Standards:** `options-ui-§1` (use the library's `AttachTooltip`, don't hand-roll). No new deviation.

### C-03 (F-003, F-006) — one reusable filter frame per (module, unit)

- **Files:** `core/Util.lua:410-445`, `modules/IconGrid.lua:787-835` and `:853-898`, `modules/Castbar.lua:997-1049` and `:1103-1141`, `docs/ARCHITECTURE.md` (per-unit frames paragraph).
- **Sketch:**
  ```lua
  -- Util
  function Util.UnitCastFilter(holder, module, unit, map)   -- map: { [event] = "Handler" }
      local f = holder.castFilter
      if not f then
          f = CreateFrame("Frame"); holder.castFilter = f
          f:SetScript("OnEvent", function(_, ev, evUnit, ...)
              local fn = module[holder.castMap[ev]]
              if fn then fn(module, ev, evUnit, ...) end
          end)
      end
      holder.castMap = map
      for ev in pairs(map) do f:RegisterUnitEvent(ev, unit) end
      return f
  end
  ```
  Teardown becomes `if inst.castFilter then inst.castFilter:UnregisterAllEvents() end`. The `#(inst.eventFrames or {}) == 0` checks in both `Resume`s become `not inst.castFilter:IsEventRegistered(...)`, or an `inst.castArmed` boolean. Add `UNIT_SPELLCAST_EMPOWER_START/STOP/UPDATE` to both maps. Castbar maps them to `OnChannelStart`/`OnCastStop`/`OnCastDelayed`.
- **Test:** extend `tests/test_disabled.lua` so `#mocks.__frames` is unchanged across three disable/enable cycles (measured today: +36 per cycle). Keep the registration-set assertions, which must still come back exactly.
- **Risk:**
  - The map table must be a file-scope constant so no per-enable allocation creeps in (#43).
  - `RegisterUnitEvent` of an event this client lacks raises (`events-frames-taint-§1`), so the EMPOWER names go through `pcall` or `C_EventUtils.IsEventValid`.
- **Standards:** `events-frames-taint-§1` (the carve-out's reuse MUST, and a single job). The helper serves one filter frame per unit and adds no second job, so it is not the forbidden generic factory.

### C-04 (F-004) — return a timer handle

- **File:** `settings/OptionsSetup.lua:243`.
- **Change:** `scheduleTimer = function(fn, delay) return _G.C_Timer.NewTimer(delay, fn) end,`
- **Test:** drive the color widget's `OnValueChanged` 10 times inside one mock window and assert one `SetAndRefresh`. It goes red with the current line.
- **Standards:** no rule touched. U-001 makes this belt-and-braces.

### C-05 (F-005, F-018) — one resolver for spell input

- **Files:** new `core/SpellInput.lua` (TOC after `core/Database.lua`), `core/KickCD.lua:570-639`, `settings/Spells.lua:272-285` and `:461-485`, `KickCD.toc`.
- **Shape:**
  - `NS.SpellInput.Resolve(text) -> id, name | nil, reason`.
  - `NS.SpellInput.Admissible(id, class, spec) -> ok, reason` does the Cooldown Manager gate, only when (class, spec) is the player's own.
  - `NS.SpellInput.ParseTail(tokens) -> text, class, spec`: trailing tokens become `[CLASS SPEC]` only when the class is a real `GetClassInfo` file token and the spec resolves for it. Otherwise they are part of the name.
  - `Database:AddSpell` rejects an unknown class token.
- **Moves:** the `_cmCache` builder moves from `settings/Spells.lua:287-384` into this file, along with its invalidation frame. This also helps F-010.
- **Test:** `/kcd spells add Wind Shear` adds 57994 in a mocked Shaman. `/kcd spells add 1766 WARLORD` refuses. The CLI refuses a spell the Cooldown Manager set lacks for the player's own spec.
- **Standards:** `architecture-§5` (the spell registry keeps one writer, and validation sits beside it), `layout-§1` (a new file rather than growth). `docs/ARCHITECTURE.md`'s module map gains the file. **Moving a TOC line: read its comment first (#66).** The new line goes into the `# Core` block with a comment naming its load-time needs (none).

### C-06 (F-007) — replay real state after a grid rebuild

- **Files:** `modules/Cooldowns.lua` (publish `Cooldowns:StateFor(spellID)`, a read-only return of `self.watched[id]`), `modules/IconGrid.lua:340-353`.
- **Sketch:**
  ```lua
  local cd = NS:GetModule("Cooldowns", true)
  local st = cd and cd.StateFor and cd:StateFor(spellID)
  btn:Apply(st or READY_SEED, true)          -- READY_SEED: file-scope constant, no per-call table
  ```
- **Risk:** a `watched` entry's `cdObject` from before the rebuild is still a live duration object. That is fine for C-side rendering.
- **Test:** register Cooldowns before IconGrid in the mock dispatch, fire PEW, and assert an on-cooldown spell's icon is not "ready". It goes red today under that order.
- **Standards:** `architecture-§4` / anti-pattern #19. This is a published accessor, not reaching into another module's table.

### C-07 (F-008) — one render per commit, and an unstickable guard

- **File:** `settings/Spells.lua:404-407` and `:1179-1244`.
- **Change:**
  - `doCommit` only calls `FireConfigChanged()`; the subscriber at `:1345` renders. The subscriber is not registered while the addon is disabled, and the page must still refresh its own edits then, so `doCommit` keeps the direct render **only** when `NS.IsDown()`.
  - Wrap the body of `RefreshRows` so `rebuildScheduled = false` runs on raise, then re-raise.
- **Test:** count `RefreshRows` per `commitSoon` flush (expect 1). Force `fillRows` to raise once, then assert a later refresh renders.

### C-08 (F-009) — perf evidence matches the descriptor

- **Files:** `docs/performance.md:36-55`, `modules/IconGrid.lua:994`, and `modules/IconGrid.lua:976-995` (`OnSpellState(_evt, payload)`; add the parent as `payload.__perfParent` or, preferably, a module-local `emitParent` set by Cooldowns' bracket).
- **Simplest compliant form:** Cooldowns brackets the Rebuild emit as `stateEmit` too, with its parent nil. `spellState` then always sits inside a `stateEmit`, and the declaration `within = "stateEmit"` becomes true on both paths.
- **Test:** `tests/test_perfsetup.lua` already pins exits. Add "every `spellState` note has an open `stateEmit`" under `Perf.on`.
- **Expected movement:** the offline `spellState`/`spellPoll` bytes/iter should be unchanged, since the bracket allocates nothing while capture is off. Re-check with `lua tests/perf.lua` after the change. The next **in-game** capture (`/kcd perf`, recorded via `/wow-addon:perf-analysis`) is the evidence the nesting reads correctly.

### C-09 (F-010) — peel `settings/Spells.lua`

- **Files:** `settings/Spells.lua` → `settings/Spells_Rows.lua` (the row builders `:590-835`) plus C-05's move of the Cooldown Manager cache.
- **Target:** under 1000 LOC.
- **Rule:** a mechanical move. No behavior change in the same commit, comments move with the code (#52), and the characterization cases in `tests/test_settings_spells_editor.lua` must stay green unchanged.
- **Expected movement:** the next release's regeneration should show `settings/Spells.lua` leaving the band. That is for the release to confirm, not a task now.

### C-10 (F-012, F-013, F-014, F-015, F-016, F-017) — hygiene batch

- **Comments:** rewrite the four stale blocks named in F-012.
- **F-013:** `Cooldowns`' `isEnabled` → `NS.MasterEnabled`. Drop the dead early returns, or keep them with a comment that the latch is primary. `Units.IsEnabled` calls `NS.MasterEnabled()` for its first rung.
- **F-014:** extend `Helpers.ResetIconPosition` to every unit's icon grid, and rename the help text to "Restore the icon grids to their default positions". Alternatively, keep target-only and say so in the verb text. Fix `README.md:97` to "refuses during combat; open it once combat ends". The README change moves no badge.
- **F-015:** compute hints by calling a `row.valuesFor(gateValue)` if present. Otherwise keep the probe, but go through `Helpers.Resolve` and restore in a `pcall`/finally shape, and document it as a read-only probe.
- **F-016:** remove `GetSpellInfo`, `GetSpecialization`, `GetSpecializationInfo`, `IsSpellKnown`, `IsPlayerSpell` and `IsSpellKnownOrOverridesKnown` from `read_globals`. Move any that `tests/` needs into `files["tests/"]`. `tests/test_lintconfig.lua` may pin the list, so update it in the same change.
- **F-017:** drop the `PLAYER_LOGIN` re-registration in `State.StandUp`. The `InCombatLockdown()` seed on the next line already covers it.
- **F-018:** the raw spec ID becomes `sd(spc)` (`core/KickCD.lua:764`).

### C-11 (F-011) — the tests

These are listed with each change above. Every new case carries `-- red under:` (`testing-§12`).

**Inventory impact.** This change set adds roughly 10–12 cases, so the pass count moves from 1050. **`docs/test-cases.md` (regenerated by `lua tests/run.lua --list`) and the README `[tests]` badge must move in the same commit as each case**, never as a follow-up.

## Standards conformance (per change)

| Change | Governing rule(s) | New deviation? | Notes |
|---|---|---|---|
| C-01 | `savedvariables-§1` | No | Extends the ratified register row. Update its wording. |
| C-02 | `options-ui-§1` | No | Uses `H.AttachTooltip`. |
| C-03 | `events-frames-taint-§1` carve-out | No (removes one) | Satisfies the reuse MUST. One frame, one job. EMPOWER names are `pcall`-registered. |
| C-04 | none | No | |
| C-05 | `architecture-§5`, `layout-§1`, `toc-file`, #66 | No | New TOC line with its comment. |
| C-06 | `architecture-§4`, #19 | No | Published accessor. |
| C-07 | `slash-commands-§7` | No | Keeps the disabled-page refresh. |
| C-08 | `performance-§3`, `-§8` | No | |
| C-09 | `layout-§1`, #52 | No | Mechanical move. |
| C-10 | `lint`, `documentation-§1` | No | |
| U-001 | `library-stack-§7` (minor bump, whole-folder re-vendor, #48) | No | Upstream only. |

**Rejected option (standard-driven).** The tempting F-004 fix is to vendor-patch `OptionsWidgets.lua` locally. That is forbidden (`library-stack-§7`, #45/#48): the next re-vendor silently reverts it. It is routed as U-001 instead.
