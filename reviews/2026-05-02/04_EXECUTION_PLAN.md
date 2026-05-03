# Ka0s KickCD — Review Execution Plan

Operationalises `02_PROPOSED_CHANGES.md` into milestones, tasks, agent roles, and concurrency hints for an agent-team or a single contributor.

---

## Milestones

| # | Milestone | Done when |
|---|-----------|-----------|
| M1 | Cleanup pass — locale + dead surface | `enUS.lua` has the missing key, no unused exports, no back-compat shims, no unused locale strings. The build still loads cleanly and `/kcd` smoke-tests still pass. |
| M2 | Cosmetic / doc refresh | Stale per-file version stamps gone; `OpenSettings` doc comment matches reality; Castbar header comments document `current` mutation; `_maxC` field removed. |
| M3 | Combat-state bus consolidation | `core/State.lua` is the only file calling `RegisterEvent("PLAYER_REGEN_*")`; modules subscribe to `KickCD_COMBAT_STATE`; `docs/message-bus.md` updated. Smoke test "in_combat" visibility mode passes through several enter/leave/`/reload` cycles. |
| M4 | UNIT_SPELLCAST_* unit-event filtering | New `Util.RegisterTargetEvent` helper exists; both modules adopt it; `OnDisable` cleans up the private frames. Profiling confirms reduced handler-dispatch count in a 5-man dungeon. |
| M5 | UX clarification + cross-module accessor cleanup | `/kcd reset` description disambiguated; Castbar uses `KickCD:GetModule("IconGrid", true)` instead of the `KickCD.IconGrid` direct global; `KickCD.IconGrid = IconGrid` line removed. |
| M6 | (Optional, deferred) Localise remaining slash output | Every `p(self, "...")` in `core/KickCD.lua` goes through `L[...]`; new keys added to `enUS.lua`. |

M3 and M4 are the only milestones with non-trivial behavioural risk; M1, M2, M5 are mechanical.

---

## Tasks

### M1 — Cleanup pass

| ID | Task | Role | Findings | Files touched |
|----|------|------|----------|---------------|
| T1.1 | Add `L["Cannot open settings during combat."]` to enUS.lua | locale-cleanup | F-006 | `locales/enUS.lua` |
| T1.2 | Drop the 3 unused `KickCD.Settings*` exports | lua-refactorer | F-004 | `settings/Spells.lua`, `settings/Profiles.lua`, `settings/Panel.lua` |
| T1.3 | Drop the 2 back-compat `:Register()` shims | lua-refactorer | F-005 | `settings/Spells.lua`, `settings/Profiles.lua` |
| T1.4 | Delete the 14 unused locale strings (NOT the dynamic-key category strings) | locale-cleanup | F-011 | `locales/enUS.lua` |
| T1.5 | Drop unused `_maxC` record field | lua-refactorer | F-007 | `modules/Cooldowns.lua` |

**Concurrency map.** T1.1 + T1.4 touch the same file (`enUS.lua`) → **serialise**. All other tasks have disjoint file sets → **parallelisable**.

**Checkpoint.** After M1, run smoke tests: cold install (`/reload` with deleted SavedVariables/KickCD.lua), `/kcd help`, `/kcd config`, `/kcd lock`, `/kcd unlock`, switch tabs in Settings.

### M2 — Cosmetic / doc refresh

| ID | Task | Role | Findings | Files touched |
|----|------|------|----------|---------------|
| T2.1 | Refresh per-file version stamps (option: drop them) | doc-cleanup | F-010 | `core/*.lua`, `modules/*.lua`, `defaults/Spells.lua`, `settings/*.lua` |
| T2.2 | Fix `OpenSettings` doc comment (drop `SettingsCategoryID` mention) | doc-cleanup | F-012 | `core/KickCD.lua` |
| T2.3 | Document `current` semantics in Castbar header | doc-cleanup | F-013 | `modules/Castbar.lua` |
| T2.4 | Document `state.charges` semantics in Cooldowns header | doc-cleanup | F-008 | `modules/Cooldowns.lua` |
| T2.5 | Add `TODO(perf)` notes near Reskin / BuildCurves | doc-cleanup | F-015, F-016 | `modules/Castbar.lua`, `modules/IconGrid.lua` |
| T2.6 | Document `Helpers.SetAndRefresh` load-order in conventions.md | doc-cleanup | F-017 | `docs/conventions.md` |
| T2.7 | (Optional) Unregister PLAYER_LOGIN inside `core/State.lua`'s boot frame after first fire | doc-cleanup | F-018 | `core/State.lua` |

**Concurrency map.** T2.1 touches every file in the addon — **must serialise** with everything else in M2 (do it last in M2). T2.2-T2.7 have disjoint file sets except T2.5 spans Castbar + IconGrid which T2.3 / T2.4 also touch — **serialise within each module**.

**Checkpoint.** None — pure documentation, no behavioural change.

### M3 — Combat-state bus consolidation (HIGH RISK)

| ID | Task | Role | Findings | Files touched |
|----|------|------|----------|---------------|
| T3.1 | Add `KickCD_COMBAT_STATE` emit in `core/State.lua`'s bootstrap handler | wow-event-refactorer | F-001, F-002 | `core/State.lua` |
| T3.2 | Subscribe IconGrid to `KickCD_COMBAT_STATE`; drop `PLAYER_REGEN_*` registrations | wow-event-refactorer | F-001 | `modules/IconGrid.lua` |
| T3.3 | Subscribe Castbar to `KickCD_COMBAT_STATE`; drop `PLAYER_REGEN_*` registrations | wow-event-refactorer | F-001 | `modules/Castbar.lua` |
| T3.4 | Update `docs/message-bus.md` with the fifth message's contract | doc-cleanup | F-001 | `docs/message-bus.md` |
| T3.5 | Update `CLAUDE.md`'s "closed message bus" hard-rule (4 messages → 5) | doc-cleanup | F-001 | `CLAUDE.md` |

**Concurrency map.** T3.1 must land before T3.2 / T3.3 (subscribers reference a not-yet-emitted message). T3.2 + T3.3 touch disjoint files → **parallelisable** after T3.1. T3.4 + T3.5 are pure doc, can land any time after T3.1.

**Checkpoint (manual).** Smoke test for M3:
1. Cold-login outside combat with `visibility = "in_combat"`. Grid should be hidden.
2. Engage a target dummy. Grid should appear within ~one frame.
3. `/reload` while in combat. Grid should still be visible after reload.
4. Drop combat. Grid should hide.

### M4 — UNIT_SPELLCAST_* unit-event filtering

| ID | Task | Role | Findings | Files touched |
|----|------|------|----------|---------------|
| T4.1 | Add `Util.RegisterTargetEvent(module, eventName, handlerName)` helper | lua-refactorer | F-003 | `core/Util.lua` |
| T4.2 | Replace IconGrid's UNIT_SPELLCAST_* registrations with the helper; track frames; clean up in OnDisable | wow-event-refactorer | F-003 | `modules/IconGrid.lua` |
| T4.3 | Replace Castbar's UNIT_SPELLCAST_* registrations with the helper; track frames; clean up in OnDisable | wow-event-refactorer | F-003 | `modules/Castbar.lua` |

**Concurrency map.** T4.1 must land before T4.2 / T4.3. T4.2 + T4.3 touch disjoint files → **parallelisable** after T4.1.

**Checkpoint (manual).** Smoke test for M4:
1. In a 5-man dungeon (or with 4 party members all casting), `/kcd debug log` ON.
2. Verify the IconGrid / Castbar handlers do NOT log dispatches for non-target casts.
3. Target a casting mob; verify Castbar shows the cast normally.
4. Untarget; verify Castbar hides.

### M5 — UX clarification + cross-module accessor cleanup

| ID | Task | Role | Findings | Files touched |
|----|------|------|----------|---------------|
| T5.1 | Update `/kcd reset` description to disambiguate `spells` semantics | ux-cleanup | F-019 | `core/KickCD.lua` |
| T5.2 | Replace `KickCD.IconGrid` direct reaches in Castbar with `GetModule("IconGrid", true)` | lua-refactorer | F-014 | `modules/Castbar.lua` |
| T5.3 | (Conditional on T5.2 landing cleanly) Drop `KickCD.IconGrid = IconGrid` export | lua-refactorer | F-014 | `modules/IconGrid.lua` |

**Concurrency map.** T5.1 disjoint from T5.2 / T5.3 → **parallelisable**. T5.3 follows T5.2.

**Checkpoint.** Smoke-test cast bar in PRIMARY anchor mode (`/kcd set castbar.anchorMode PRIMARY`) — bar should still anchor to the icon grid's primary icon.

### M6 — Localise remaining slash output (DEFERRED — only if a translation effort starts)

| ID | Task | Role | Findings | Files touched |
|----|------|------|----------|---------------|
| T6.1 | Wrap every bare-English slash output in `L[...]` | locale-cleanup | F-009 | `core/KickCD.lua`, `locales/enUS.lua` |

---

## Critical path / concurrency map (compact view)

```
M1 (cleanup) ─┐
              ├─→ M3 (combat bus) ─┐
M2 (docs) ────┘                    ├─→ M5 (ux + accessor)
              ┌─→ M4 (unit-events) ┘
M1 ───────────┘
```

- M1, M2 can run in parallel (files mostly disjoint, but T2.1 must serialise).
- M3 should land before M5 because the cleanup of `KickCD.IconGrid = IconGrid` in M5 is easier when there are no in-flight refactors competing for IconGrid.lua.
- M4 can run in parallel with M3, since UNIT_SPELLCAST_* and PLAYER_REGEN_* are independent event domains.
- M5 follows both M3 and M4.
- M6 is fully optional and disjoint from everything else.

---

## Incremental commit strategy

Suggested one-commit-per-milestone-task split, with HEREDOC-style messages following the recent commit style ("Component: short description"):

```
T1.1: Locales: add "Cannot open settings during combat" key
T1.2: Settings: drop dead KickCD.Settings* exports
T1.3: Settings: drop back-compat :Register() shims
T1.4: Locales: prune 14 unused strings
T1.5: Cooldowns: drop write-only _maxC field on watched record

T2.1: Drop per-file v0.1 version stamps
T2.2: Core: fix OpenSettings doc comment to match reality
T2.3: Castbar: document `current` mutation invariant in header
T2.4: Cooldowns: document state.charges semantics in header
T2.5: TODO(perf) notes for Reskin / BuildCurves
T2.6: Docs: note Helpers.SetAndRefresh load-order subtlety

T3.1: State: emit KickCD_COMBAT_STATE on regen transitions
T3.2: IconGrid: subscribe to KickCD_COMBAT_STATE
T3.3: Castbar: subscribe to KickCD_COMBAT_STATE
T3.4: Docs: extend message-bus.md with KickCD_COMBAT_STATE
T3.5: CLAUDE.md: bump bus from 4 messages to 5

T4.1: Util: add RegisterTargetEvent helper
T4.2: IconGrid: filter UNIT_SPELLCAST_* via RegisterTargetEvent
T4.3: Castbar: filter UNIT_SPELLCAST_* via RegisterTargetEvent

T5.1: Slash: clarify /kcd reset spells semantics
T5.2: Castbar: replace KickCD.IconGrid with GetModule lookup
T5.3: IconGrid: drop self-export (no in-tree consumers)

T6.1: Localise core/KickCD.lua slash output (DEFERRED)
```

User runs the actual `git add` / `git commit`; per CLAUDE.md hard rule, the agent never auto-commits.
