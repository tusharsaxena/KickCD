# Ka0s KickCD — Review Final Summary (2026-05-02)

**Verdict:** Review execution plan complete through **M5**. All 18 in-scope findings closed; **M6 (full slash localisation) deferred** per the plan, conditional on a future translation effort. Aggregate impact: **22 files changed, +246 / −177 lines** across **5 commits**, no behavioural regressions intended.

The review (verdict: "ship-ready with minor issues") catalogued **0 Critical, 0 High, 8 Medium, 11 Low** findings. This summary maps every finding to its outcome and documents the user-visible / contributor-visible deltas.

---

## Commit chain

| # | Commit | Milestone | Files | Lines |
|---|---|---|---:|---:|
| 1 | `a108787` | **M1** — drop dead Settings exports/shims, `_maxC`; tidy locale keys | 5 | +1 / −47 |
| 2 | `93528ab` | **M2** — drop version stamps, doc invariants/contracts, perf TODOs | 18 | +47 / −27 |
| 3 | `b6cf643` | **M3** — consolidate `PLAYER_REGEN_*` in State; add `KickCD_COMBAT_STATE` | 7 | +64 / −44 |
| 4 | `378cd40` | **M4** — filter `UNIT_SPELLCAST_*` to target via private dispatch frames | 3 | +116 / −39 |
| 5 | `6e490d6` | **M5** — clarify `/kcd reset`; route Castbar through `GetModule(IconGrid)` | 3 | +18 / −20 |
| | | **Total (deduped, 22 unique files)** | **22** | **+246 / −177** |

All commits sit on `master`, ahead of `origin/master`. Push when smoke tests pass.

---

## Findings status

19 findings (F-001 → F-019). Closed = behavioural change shipped, doc-only = comment / docs updated, deferred = explicitly punted per the plan.

| ID | Severity | Theme | Status | Closed by |
|---|---|---|---|---|
| F-001 | Medium | `PLAYER_REGEN_*` dispatch-order fragility | **Closed** | M3 (T3.1–T3.3) |
| F-002 | Medium | Bootstrap-frame discoverability | **Closed (doc)** | M3 (T3.4 / T3.5 + module-map.md updates) |
| F-003 | Medium | `UNIT_SPELLCAST_*` not unit-filtered | **Closed** | M4 (T4.1–T4.3) |
| F-004 | Medium | Three dead `KickCD.Settings*` exports | **Closed** | M1 (T1.2) |
| F-005 | Medium | Two dead `:Register()` shims | **Closed** | M1 (T1.3) |
| F-006 | Medium | Missing `L["Cannot open settings during combat."]` key | **Closed** | M1 (T1.1) |
| F-007 | Medium | Write-only `_maxC` field on watched record | **Closed** | M1 (T1.5) |
| F-008 | Medium | `state.charges` semantics undocumented | **Closed (doc)** | M2 (T2.4) |
| F-009 | Low | Mixed locale / bare-English slash output | **Deferred** | M6 — only if translation effort starts |
| F-010 | Low | Stale per-file `v0.1` version stamps | **Closed** | M2 (T2.1) |
| F-011 | Low | 14 unused locale keys in `enUS.lua` | **Closed** | M1 (T1.4) |
| F-012 | Low | `OpenSettings` doc comment cites dropped `SettingsCategoryID` | **Closed (doc)** | M2 (T2.2) |
| F-013 | Low | Castbar `current` mutation undocumented | **Closed (doc)** | M2 (T2.3) |
| F-014 | Low | Castbar reaches `KickCD.IconGrid` directly | **Closed** | M5 (T5.2 / T5.3) |
| F-015 | Low | `Castbar:Reskin` runs every CONFIG_CHANGED for "castbar" | **Captured (TODO)** | M2 (T2.5) — TODO(perf) note in code, defer until measured |
| F-016 | Low | `BuildCurves` rebuilds on every "icons" config change | **Captured (TODO)** | M2 (T2.5) — TODO(perf) note in code, defer until measured |
| F-017 | Low | `Helpers.SetAndRefresh` load-order subtlety undocumented | **Closed (doc)** | M2 (T2.6) — `docs/conventions.md` |
| F-018 | Low | `core/State.lua` boot doesn't unregister `PLAYER_LOGIN` | **Closed** | M2 (T2.7) |
| F-019 | Low | `/kcd reset spells` description ambiguous | **Closed** | M5 (T5.1) |

**Score:** 18 / 19 closed; 1 deferred (F-009, by design).

---

## Behavioural changes — what users / contributors see

### User-visible

- **`/kcd config` in combat now prints the localised key** instead of leaking the bare English fallback when a translator adds a non-English locale. (F-006)
- **`/kcd help` clarifies the spells-reset semantics**:
  > `/kcd reset spells` rebuilds EVERY spec's list — for one spec, use `/kcd spells reset`. (F-019)
- **No other surface changes.** All visibility modes, settings-panel rows, profiles, anchors, drag-lock behaviour, and slash subcommands work as before.

### Performance

- **`UNIT_SPELLCAST_*` events filtered to target.** In a 25-player raid the cast-event family fired thousands of times per minute and was discarded inside the handler with `if unit ~= "target"`. The new private dispatch frames use `Frame:RegisterUnitEvent("target")`, so the unit filter happens C-side before the handler is even invoked. **Expected impact:** measurable reduction in handler-dispatch count in dense combat; not user-perceptible at the frame-time level but verifiable via `/kcd debug log on`. (F-003)

### Architecture

- **The closed message bus grew from 4 → 5 messages.** The new `KickCD_COMBAT_STATE` message is the canonical signal for combat transitions. `core/State.lua` is now the **only** file in the addon that registers `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED`. Modules subscribe to the message and never hook the raw events; the dispatch order is explicit by construction (the message fires from inside State's handler, after the flag write). (F-001, F-002)
- **The Castbar→IconGrid coupling now uses the AceAddon idiom.** `KickCD:GetModule("IconGrid", true)` replaces the global `KickCD.IconGrid` reach. `KickCD.IconGrid = IconGrid` self-export at the bottom of `modules/IconGrid.lua` is gone; no in-tree consumers remain. (F-014)
- **`Util.RegisterTargetEvent(module, eventName, handlerName)`** is a new utility for registering target-only unit events that AceEvent doesn't natively support. Returns the dispatch frame so the caller can release it in `OnDisable`. (F-003)

### Cleanup / hygiene (no behavioural delta)

- **Three dead `KickCD.Settings*` exports** dropped (`SettingsSpells`, `SettingsProfiles`, `SettingsCategoryID`). (F-004)
- **Two `:Register()` back-compat shims** with no callers dropped (`Spells:Register`, `Profiles:Register`). (F-005)
- **14 unused locale keys** pruned from `enUS.lua`. (F-011)
- **Write-only `_maxC` field** dropped from the `KickCD_SPELL_STATE` record. (F-007)
- **Per-file `KickCD vX.Y` version stamps** dropped from 17 file headers + 3 inline references. The canonical version remains in `KickCD.toc` / `KickCD.VERSION`. (F-010)
- **`PLAYER_LOGIN` listener** in `core/State.lua` now unregisters after first fire (mirrors `core/LSMPatch.lua` pattern). (F-018)

---

## Documentation updates

### Hard-rule docs (the canonical contracts)

- **`CLAUDE.md`** — closed message bus updated from "four AceEvent messages" to "five", with `KickCD_COMBAT_STATE` added to the enumerated list.
- **`ARCHITECTURE.md`** — same hard-rule restatement updated to "five"; the `KickCD.State.inCombat` invariant note now documents the `KickCD_COMBAT_STATE` fan-out.

### Topic docs

- **`docs/message-bus.md`** — table extended to 5 messages; new payload section for `KickCD_COMBAT_STATE` (sender, listeners, payload-shape, ordered-transition rationale).
- **`docs/module-map.md`** — IconGrid / Castbar listens-to inventories updated; `OnEnable` event-list summaries now reflect the four inbound `KickCD_*` messages and absence of `PLAYER_REGEN_*` direct hooks; the `core/State.lua` description gains the `KickCD_COMBAT_STATE` emit.
- **`docs/conventions.md`** — new bullet under "Settings layer" documenting the `Helpers.SetAndRefresh` load-order subtlety (F-017).

### In-code documentation

- **`modules/Castbar.lua` header** — `current` is now documented as a `Compat.GetCastingInfo` record that `OnInterruptibilityChanged` mutates in place (the "plain-after-flip invariant"). (F-013)
- **`modules/Cooldowns.lua` message contract** — `state.charges` semantics clarified: raw `currentCharges` from `C_Spell.GetSpellCharges`, with explicit note about the `0`-charges case. (F-008)
- **`core/KickCD.lua`** — `OpenSettings` doc comment no longer cites the dropped `KickCD.SettingsCategoryID`; the `OnEnable` `for v0.1` aside removed. (F-012, T2.1)
- **`modules/Castbar.lua:Reskin`** — TODO(perf) note above the function pointing at the color-only-vs-structural split opportunity (F-015), not yet acted on; defer until profiling confirms the cost.
- **`modules/IconGrid.lua:BuildCurves`** — TODO(perf) note above the function pointing at the cache-and-skip opportunity (F-016); same defer-until-measured posture.

---

## Files touched (aggregate, deduped)

22 unique files across the 5 commits:

```
ARCHITECTURE.md          |   4 +-
CLAUDE.md                |   2 +-
core/Compat.lua          |   2 +-
core/Constants.lua       |   2 +-
core/Database.lua        |   2 +-
core/KickCD.lua          |  15 +++--
core/State.lua           |  24 ++++++--
core/Util.lua            |  36 +++++++++++-
defaults/Spells.lua      |   2 +-
docs/conventions.md      |   1 +
docs/message-bus.md      |   9 ++-
docs/module-map.md       |  10 ++--
locales/enUS.lua         |  19 +------
modules/Castbar.lua      | 149 ++++++++++++++++++++++++++++++--------------------
modules/Cooldowns.lua    |   8 ++-
modules/IconGrid.lua     |  96 ++++++++++++++++++++------------
settings/Castbar.lua     |   2 +-
settings/General.lua     |   2 +-
settings/Icons.lua       |   2 +-
settings/Panel.lua       |   3 +-
settings/Profiles.lua    |  23 +-------
settings/Spells.lua      |  10 +---
                          22 files changed, 246 insertions(+), 177 deletions(-)
```

**Hot files:** `modules/Castbar.lua` (M2 + M3 + M4 + M5), `modules/IconGrid.lua` (M2 + M3 + M4 + M5), `core/State.lua` (M2 + M3), `core/Util.lua` (M2 + M4).

---

## Outstanding items

### Smoke tests — pending in-game verification

The plan calls out manual smoke tests for M1, M3, M4, M5. The full review-specific checklist lives in [REVIEW_SMOKE_TESTS.md](REVIEW_SMOKE_TESTS.md). Headlines:

- **M1**: cold install + `/kcd help|config|lock|unlock` + tab swap.
- **M3**: `visibility=in_combat` enter/leave/`/reload` cycles (the high-risk milestone — verify `KickCD_COMBAT_STATE` wiring across reload boundaries).
- **M4**: 5-man dungeon + `/kcd debug log on` — verify no spurious dispatches for non-target casts; target/untarget casting mob.
- **M5**: `/kcd set castbar.anchorMode PRIMARY` — bar anchors to the icon grid's primary icon.

### Deferred work

- **M6 (T6.1)** — full localisation of `core/KickCD.lua`'s slash output (~20 keys). Status: deferred per the plan, only worth doing if a non-English locale file is being added. Captured as F-009.
- **TODO(perf) F-015** — `Castbar:Reskin` color-only vs structural split. Acted on as an in-code note; revisit if a frame-rate report comes in for sustained color-picker drags.
- **TODO(perf) F-016** — `BuildCurves` cache-and-compare. Acted on as an in-code note; revisit if the per-config-change rebuild ever shows up in a profile.

### Push readiness

- 5 commits ahead of `origin/master`.
- No version bump (per the hard rule, version bumps are an explicit user decision; this review is purely cleanup + refactoring).
- Tree clean.
- Recommend running [REVIEW_SMOKE_TESTS.md](REVIEW_SMOKE_TESTS.md) in-game before `git push`.

---

## Companion artifacts

- [REVIEW_FINDINGS.md](REVIEW_FINDINGS.md) — original 19-finding catalogue.
- [REVIEW_PROPOSED_CHANGES.md](REVIEW_PROPOSED_CHANGES.md) — HLD + LLD per finding.
- [REVIEW_EXECUTION_PLAN.md](REVIEW_EXECUTION_PLAN.md) — milestone / task breakdown that drove this work.
- [REVIEW_SMOKE_TESTS.md](REVIEW_SMOKE_TESTS.md) — review-specific in-game test checklist.
