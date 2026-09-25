# KickCD — Technical Design (2026-09-23)

This is the remediation design for the 23 roots and 4 dependents in `02_DEVIATIONS.md`. Everything
here is designed and none of it is done: this audit changes no code. The ids are the shared key with
`05_EXECUTION_PLAN.md`.

## Design principles for this pass

1. **Upstream first.** Two findings are really defects in something KickCD vendors or cites:
   - `KICKCD-B-02`: the kit's prose gate skips a whole directory.
   - `KICKCD-C-14`: the reserved-verb reach into sub-trees.

   A third, `KICKCD-C-01`, carries a grading contradiction inside the playbook. Fix these in
   `LibKa0s` or `WowAddonStandards` first, then re-vendor the **whole** LibKa0s ship folder and
   `testkit/`, and never patch `libs/` or `tests/_kit/` in place (library-stack-§5, AP #47).
2. **Code before docs**, so that every doc edit describes the final tree.
3. **Every behavior fix gets a red-first case.** The suite is 1050 green, and each new case has to
   be seen failing on HEAD before its fix lands (testing-§12, AP #52).

---

## D1 — Unit-filter frames: build once, re-register on resume (`KICKCD-C-03`, Medium)

**Files:** `core/Util.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua`, `tests/test_disabled.lua`,
and a new case in `tests/test_util.lua`.

**Shape.**

- Replace `Util.RegisterUnitCastEvent(module, unit, event, handler)`, which returns one new frame
  per event, with a per-instance filter that is built once and re-armed:

  ```lua
  -- core/Util.lua
  --- The events-frames-taint-§1 carve-out, exactly: one private frame per (module, unit) whose
  --- only job is RegisterUnitEvent + one OnEvent. Built once, held by the caller, re-armed by Arm.
  function Util.NewUnitFilter(module, unit, routes)   -- routes: { [event] = handlerName }
      local f = CreateFrame("Frame")
      f:SetScript("OnEvent", function(_, event, evUnit, ...)
          local fn = module[routes[event]]
          if fn then fn(module, event, evUnit, ...) end
      end)
      local filter = { frame = f, unit = unit, routes = routes }
      function filter.Arm()    for ev in pairs(routes) do f:RegisterUnitEvent(ev, unit) end end
      function filter.Disarm() f:UnregisterAllEvents() end
      return filter
  end
  ```

- `IconGrid` and `Castbar` hold `inst.unitFilter`, created lazily on the first `EnableUnit`.
  `EnableUnit` calls `Arm()`. `DisableUnit` and `Suspend` call `Disarm()` and **keep** the object.
  - The frame count per instance drops from 8 or 10 to **1**, so 4 frames in total instead of 36
    for each cycle.
  - The route table is a module-level constant, so no table is allocated on each enable (AP #43).
  - The `RegisterUnitEvent` calls inside `Arm` go through D2's isolated helper.
- The Resume guard `#(inst.eventFrames or {}) == 0` (`modules/Castbar.lua:1136`) becomes
  `inst.unitFilter and not inst.unitFilter.armed`. Keep an `armed` flag on the filter for this.

**Tests.**

1. In `test_disabled`, add "a disable/enable cycle creates no frames". Count `CreateFrame` calls
   through the mock across two full cycles, and require the second cycle to add 0. It must be red
   on HEAD, where it adds 36.
2. In `test_util`, check that `Arm` and `Disarm` are idempotent and that the registry row count per
   unit is unchanged.
3. `test_disabled`'s step-3 empty-registry case must stay green.

**Risk.** The dispatch closure's `module[...]` lookup is unchanged. The one behavior change is that
a frame is kept while it is disarmed, which is exactly the state slash-commands-§7 asks for.

## D2 — Isolated event registration with a visible rejected-name record (`KICKCD-C-02`)

**Files:** `core/Util.lua`, every registration block (`modules/Cooldowns.lua:544-555`,
`modules/IconGrid.lua:935-949`, `modules/Castbar.lua:1081-1087`, `modules/UnitLabel.lua:253`,
`core/State.lua:144-146`, `:205-213`, `settings/Spells.lua:380-381`, `:1358-1364`), and
`core/KickCD.lua`'s `DEBUG_COMMANDS`.

**Shape.**

- Add `Util.SafeRegister(target, event, handler)`:
  - If `C_EventUtils.IsEventValid` exists and answers false, record the name and return. This is
    the SHOULD front gate.
  - Otherwise call `pcall(target.RegisterEvent, target, event, handler)`, and record the name if it
    fails.
- Add a sibling for unit events that D1's `Arm` uses.
- Keep rejected names in `NS.State.rejectedEvents`, which is session-only. Surface them through a
  new `/kcd debug events` sub-verb, which prints the list or "none", and log one `[Events]` console
  line per rejection.
- AceEvent's `RegisterEvent` raises through the shared frame, so the `pcall` catches it.

**Tests.** Use the kit mock's `M.__badEvents`:

- Mark `SPELL_UPDATE_USABLE` as bad and assert that `SPELL_UPDATE_CHARGES` and the events after it
  still register.
- Assert that the name shows up in `/kcd debug events`.

## D3 — Move the two raw frames onto AceEvent targets, or ratify one (`KICKCD-C-04`)

- **`settings/Spells.lua` `cacheEvents`.** Move it to the page's existing `Spells.__ev` bus target,
  which is already an AceEvent target, or to a second `NS.NewBusTarget()`. `Spells.StandDown` and
  `StandUp` already release and restore that target.
- **`core/State.lua` `boot`.** The frame exists so that the combat flag is written before any
  module reacts. An AceEvent target registered at file load fires in the same dispatch pass, and the
  flag is written before `COMBAT_STATE` is sent either way, because the ordering comes from the
  handler body and not from the frame. Move it to `NS.NewBusTarget()`, which can be created at file
  load because AceEvent is loaded in `libs/`.
  - **If the owner holds that a raw frame is load-bearing**, keep it and write a
    `## Documented deviations` row for `events-frames-taint-§1`, with a re-check trigger such as
    "AceEvent dispatch order changes" or "State gains a second event".

**Tests.** `test_state` must still pass. `test_disabled` must still count 0 registrations while the
addon is disabled.

## D4 — The three `_G.print` arms, and a gate (`KICKCD-A-08`)

- Edit `core/KickCD.lua:127`, `core/Compat.lua:441` and `modules/Cooldowns.lua:661` to use
  `NS.Util.print` directly.
- Add a `test_source_style` case that scans the authored source files for `or _G%.print`, deriving
  the file list from `git ls-files` rather than typing it (testing-§1). Show it red on HEAD first.

## D5 — TOC annotations (`KICKCD-C-16`, `-C-16a` to `-C-16d`, `KICKCD-A-02`)

`KickCD.toc` only. There is no code change.

- **Two load-bearing comments.** Put one above `:96-97`: "IconGrid_Layout / IconGrid_Render call
  `NS:GetModule("IconGrid")` at file scope — below `modules\IconGrid.lua`". Put one above `:99-101`
  for the `Castbar_*` siblings.
- **One conventional note per group:**
  - `# Locales`: read through `NS.L` at call time or as a file-scope upvalue of later sections;
    free within the group.
  - `# Defaults`: read at call time by `core/Database.lua`.
  - `# Modules`: the parents are free relative to each other.
  - `# Settings`: past Panel, every page is free relative to the others.
  - The rest of `# Core`: "lines without a `LOAD-BEARING POSITION:` comment are conventional".

## D6 — Documentation corrections (`KICKCD-C-05`, `-C-06`, `-C-07`, `-C-08`, `-B-03`, `-B-06`, `-C-09`, `-C-15`)

- **C-05, the README.** Rewrite `README.md:97` and `:113`: the game blocks the panel during combat,
  and you run `/kcd config` again after it ends. Run the de-AI pass.
- **C-06, `debug.md`.** Choose one of two routes.
  - (a) Write `docs/debug.md` as a Tier 2 doc covering the three chat dumps (`spells`, `castbar`,
    `interrupt`) plus the new `events` dump from D2. Set its map row to Present, with the trigger
    "3 debug dump verbs beyond the console".
  - (b) Route the dumps into the console with `NS.Debug` and keep "Not applicable", with the reason
    corrected.
  - **Recommend (a).** Players paste these dumps into bug reports from chat (see issue #8), so chat
    output is a feature.
- **C-07, `compat-layer.md`.** Collapse the six rows for library members into one row that links
  LibKa0s `docs/api/Compat/version-1-docs.md`. Keep only KickCD-specific caveats, such as "use
  `isActive`, never compare `start`/`duration`".
- **C-08, inventories.** Re-derive each figure with a command and record the command in the commit
  message:
  - `ARCHITECTURE.md:77-81` and `.luacheckrc:24-28`: 8 files read the name, 30 do not.
  - `:352`: "8 shims by the §3 grep".
  - `:353`: state the message-bus trigger: 5 messages, trigger not fired, shipped anyway as a
    record.
  - `:281` and `core/LifecycleSetup.lua:113`: "seven registrations".
  - `.luacheckrc:89`: cite the symbol, not a line number.
  - `.pkgmeta:17`, `:20`, `:21`: cite `packaging` (the strong-form MUST), not `packaging.md:28`.
- **B-03, the first register row.** The owner decides whether `BackfillLabelStyle` is the "third
  shape addition" that the trigger names.
  - If it is, retire the row and write a one-paragraph retirement note in the register's style.
  - If it is not, rewrite **What differs** to name all three migrators and restate the trigger.
  - In both rows, replace `schema.md#L256` and `#L266` with heading anchors.
- **B-06(a).** Change `ARCHITECTURE.md:367` to the documentation-§3 template wording.
- **C-09, hub size.** Move `## The stand-down: disabled is total` (`:226-310`, 85 lines) into
  `slash-dispatch.md`'s disabled-state section, leaving a three-line summary and one link. Split the
  `:117` LibKa0s bullet into a list. The target is under 400 lines.
- **C-15, bare `§N` citations.** Qualify the eight sites: `compat`, `debug-logging-§9`,
  `debug-logging-§10`, `debug-logging-§11`. Renaming the three `test_debuglog` case titles changes
  `docs/test-cases.md`, so regenerate it with `--list` in the same commit and keep the badge count
  at 1050.

## D7 — Media mark (`KICKCD-C-13`)

- Change `settings/Spells.lua:798` so `rowRemoveButton` passes `icon = NS.Icon("clear")` instead of
  an atlas. `makeRowIconBtn` (`:590-622`) already handles `opts.atlas` and needs an `opts.icon`
  branch that calls `SetTexture`.
- The catalog art is white, so tint it to match the existing button state if needed.
- If no catalog mark reads as "remove from list", add one **upstream** in LibKa0s's generator and
  re-vendor (library-stack-§8).

## D8 — Records and the issue store (`KICKCD-C-01`, `-C-10`, `-B-04`, `-C-11`, `-C-12`, `-B-05`)

- **C-01.** Write one consolidated re-vendor bundle, `docs/revendor/2026-09-2x-v1.18.0-to-v1.53.0/`,
  containing `01_DELTA.md` and `05_SUMMARY.md`.
  - The 25 tags, each with the commit(s) that carried it (`git log --format='%h %s' -- libs/LibKa0s`).
  - A statement that those tags arrived through bulk sweeps with no per-tag deliberation.
  - `01_DELTA.md`'s first line names the span, so the playbook check reads it. The check greps one
    `vX.Y.Z` off line 1, so pick the first form below that it accepts:
    - List each tag on line 1.
    - Name the folder `…-v1.53.0` and list the rest in the body.
    - If neither passes the check, raise with WowAddonStandards how a consolidated bundle is meant
      to be read by it. That is an upstream gap, recorded in 05 Sprint 0.
- **C-10 and B-04, at the next release run.** Regenerate `RESULTS.md` with kit rev 25, which adds
  the commit and dirty cells.
  - Give each band entry a live tracker: open one issue per peel seam, starting with
    `settings/Spells.lua`, which is past its own 1400 line. Or give it a fix.
  - Write the first disposition for `modules/IconGrid_Render.lua`.
  - Drop `A-2` and `KCD-30`.
- **C-11.** Close #15 as done, or relabel it `state:triaged`.
- **C-12.** Comment on #12 that Widgets was adopted (DragHandle and ReorderList), with commits.
- **B-05.** Strip `[Optional]` from #9's title.

## D9 — Upstream items (not KickCD code)

- **U1, the LibKa0s testkit.**
  - `testkit/test_prose.lua` `SKIPPED_DIRS` lists `docs/perf-analysis/` and `docs/automated-tests/`
    whole. Narrow both to their dated-bundle children: match `^docs/perf-analysis/%d` and
    `^docs/automated-tests/%d`, or skip by glob. The live `README.md` and `RESULTS.md` would then be
    scanned, as localization-§5 intends.
  - Bump the kit revision, release, and re-vendor the **whole** ship folder and `testkit/` into
    KickCD.
  - Then fix `docs/perf-analysis/README.md:35-36` (`KICKCD-B-02`).
- **U2, WowAddonStandards.**
  - (a) `slash-commands-§2`: rule whether the `enable`/`disable` reservation reaches sub-tree verbs
    (`KICKCD-C-14`). The standard's own §3 example uses "enable/disable" as `debug` sub-arguments.
  - (b) `AUDIT.md`: reconcile the re-vendor check's explicit **High** with step 5's
    user-reachability table (`KICKCD-C-01`'s grade note). Also state how a consolidated bundle's
    first line should name a span so the check reads it.
- **U3, optional.** If the owner wants a "remove" mark in the catalog (D7), add it to LibKa0s
  `tools/artwork`.

## Ordering constraints

- D1 before D2's unit half: D2's unit-event helper is what D1's `Arm` calls.
- D1 and D2 before D6: the docs describe the final registration shape (`ARCHITECTURE.md`'s Event
  subscriptions and stand-down sections).
- U1's re-vendor before B-02's word fix, so the gate is **seen red** on the two words first.
- D6's C-15 rename and the `docs/test-cases.md` regeneration go in the same commit (the badge keep-in-sync MUST).
- D8's C-10 waits for the next release run, which is the checkpoint.
