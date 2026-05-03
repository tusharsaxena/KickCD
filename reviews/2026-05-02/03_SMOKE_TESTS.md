# Ka0s KickCD — Review Smoke Tests (2026-05-02)

Manual in-game checks to run before pushing the M1–M5 commits. Targeted at the **behavioural deltas** introduced by this review — for the standing regression suite (cold install, profiles, schema validator, etc.) see [docs/smoke-tests.md](../../docs/smoke-tests.md).

The five commits under test, oldest-to-newest:

| Commit | Milestone |
|---|---|
| `a108787` | M1 — dead Settings exports/shims, `_maxC`, locale-key cleanup |
| `93528ab` | M2 — version-stamp drop, doc invariants, perf TODOs |
| `b6cf643` | M3 — combat-state bus consolidation (`KickCD_COMBAT_STATE`) |
| `378cd40` | M4 — `UNIT_SPELLCAST_*` filtered to "target" via dispatch frames |
| `6e490d6` | M5 — `/kcd reset` clarification + `GetModule("IconGrid")` accessor |

## Conventions

- **`/reload`** abbreviates `/console reloadui`.
- **BugSack / BugGrabber** (or the stock Lua error frame) is the primary regression signal — a clean run is "no Lua errors at any point".
- **Chat banner** — every line the addon prints starts with a cyan `[KCD]`. A double `[KCD][KCD]` banner is a regression.
- **"Hostile caster"** below means a target dummy / world mob that channels or casts an interruptible spell on demand.
- **"In combat"** smoke checks rely on `KickCD.State.inCombat`, which flips on `PLAYER_REGEN_DISABLED` / `_ENABLED`. Auto-attack on a dummy is enough.
- Each test has a **Pass** line; if the observed behaviour does not match, the test fails.

---

## Pre-flight

### P-1. Clean Lua-error baseline
- [ ] Enable BugSack (or the stock error frame).
- [ ] Log in with the new commits installed.
- [ ] Sit through 30 s of `/reload` and a Settings open.
- **Pass:** Zero Lua errors. No `[KCD]…schema error:` lines in chat.

### P-2. Banner integrity
- [ ] `/kcd help`
- **Pass:** Every chat line is prefixed with a single cyan `[KCD]` banner. The new `/kcd reset` description (M5) reads:
  > `/kcd reset` — Reset a panel to defaults. `/kcd reset spells` rebuilds EVERY spec's list — for one spec, use `/kcd spells reset`.

---

## M1 — Cleanup pass (a108787)

Mostly dead-code removal — the surface contract is unchanged. We're checking that nothing the cleanup touched broke loading.

### M1-1. Cold install
- [ ] Quit WoW. Delete `WTF/.../SavedVariables/KickCD.lua` (or rename it).
- [ ] Launch WoW; log in.
- **Pass:** Addon loads silently, no Lua errors. Default profile populates. Default spec's spell list appears on-screen.

### M1-2. Help / config / lock / unlock
- [ ] `/kcd help`
- [ ] `/kcd config` (Settings → Ka0s KickCD opens)
- [ ] `/kcd lock` then `/kcd unlock`
- **Pass:** Help prints; Settings opens to the General tab; lock toggles produce the expected `[KCD] icon grid locked` / `unlocked` chat output.

### M1-3. Settings tab swap
- [ ] In the open Settings panel, click each subcategory: General → Icons → Cast bar → Spells → Profiles.
- **Pass:** Each tab renders without Lua errors. The Spells tab shows the player's current spec on first open. Tabs swap freely; the Profiles tab renders the AceDBOptions UI.

### M1-4. In-combat config guard (locale check for F-006)
- [ ] Get into combat (auto-attack a dummy).
- [ ] `/kcd config`
- **Pass:** Chat prints `[KCD] Cannot open settings during combat.` (the locale key added by T1.1). No Lua error.

---

## M2 — Cosmetic / doc refresh (93528ab)

Pure documentation + the `PLAYER_LOGIN` unregister change in `core/State.lua` (T2.7). No behavioural regressions expected. Only one runtime check needed.

### M2-1. PLAYER_LOGIN unregister (T2.7)
- [ ] Log in.
- [ ] In a script frame or addon console, evaluate the boot frame (or just confirm by absence of regressions).
- **Pass:** Addon loads cleanly. `KickCD.State.inCombat` flips correctly through subsequent combat transitions (covered by M3-1 below). The `PLAYER_LOGIN` unregister is a no-op for behaviour — this is a "doesn't break things" check.

---

## M3 — Combat-state bus consolidation (b6cf643)

**High-risk milestone.** Per the plan, `core/State.lua` is now the *only* file in the addon that registers `PLAYER_REGEN_*`; `IconGrid` and `Castbar` subscribe to the new `KickCD_COMBAT_STATE` message. We're verifying the message wiring works end-to-end.

### M3-1. `in_combat` visibility — basic transition
- [ ] `/kcd set visibility in_combat`
- [ ] Stand out of combat. **Pass:** icon grid + cast bar are hidden.
- [ ] Auto-attack a dummy (enter combat). **Pass:** icon grid appears within ~1 frame of `PLAYER_REGEN_DISABLED`.
- [ ] Stop attacking; wait 5 s for combat drop. **Pass:** icon grid hides on `_ENABLED`.

### M3-2. `/reload` while in combat
- [ ] In combat (still attacking the dummy), `/reload`.
- **Pass:** After the reload completes, the icon grid is **still visible** (the bootstrap `PLAYER_LOGIN` handler seeds `KickCD.State.inCombat = true` from `InCombatLockdown()`, then fires `KickCD_COMBAT_STATE`, and both modules re-evaluate visibility). No Lua errors.

### M3-3. `/reload` out of combat
- [ ] Out of combat, `/reload`.
- **Pass:** Icon grid stays hidden after reload. (Same path as M3-2 but seed is `false`.)

### M3-4. Castbar in `in_combat` mode
- [ ] Set `visibility = in_combat`. Target a hostile caster.
- [ ] Out of combat: cast bar should be **hidden** even though target is casting.
- [ ] Enter combat (start auto-attack). Cast bar should appear if the target is mid-cast.
- [ ] Drop combat. Cast bar should hide even if the cast continues.
- **Pass:** Cast bar visibility tracks combat state correctly.

### M3-5. Multiple enter/leave/`/reload` cycles
- [ ] Repeat M3-1 → M3-2 → M3-1 over 5 cycles.
- **Pass:** No drift, no stuck-visible / stuck-hidden state, no Lua errors. The `KickCD_COMBAT_STATE` message wiring is stable across reload boundaries.

### M3-6. Other visibility modes still work
- [ ] `/kcd set visibility always` — grid always visible (regardless of combat).
- [ ] `/kcd set visibility target_casting` — only when target is casting.
- [ ] `/kcd set visibility target_casting_interruptible` — only on interruptible casts.
- **Pass:** Each mode behaves as before; combat-bus changes did not regress the other modes.

---

## M4 — UNIT_SPELLCAST_* unit-event filtering (378cd40)

**Medium-risk milestone.** All `UNIT_SPELLCAST_*` registrations now go through `Util.RegisterTargetEvent` (private dispatch frames with `RegisterUnitEvent("target")`). Handlers no longer guard `unit ~= "target"` — the filter lives upstream.

### M4-1. Cast bar still shows the target's cast
- [ ] Target a hostile caster mid-cast.
- **Pass:** Cast bar appears, shows spell name + remaining time, fills correctly.

### M4-2. Cast bar hides on untarget
- [ ] With cast bar visible (M4-1), drop your target (`/cleartarget`).
- **Pass:** Cast bar hides immediately (no cast to show).

### M4-3. Cast bar transitions on retarget
- [ ] Target caster A (mid-cast) → cast bar shows A.
- [ ] Switch target to caster B (mid-cast) → cast bar shows B.
- [ ] Switch to a non-casting target → cast bar hides.
- **Pass:** Each transition is clean; no Lua errors; no stuck stale cast.

### M4-4. Interruptibility flips mid-cast
- [ ] Target a boss / mob whose cast toggles between interruptible and uninterruptible (e.g. via an aura).
- **Pass:** Cast bar's per-state visuals (color / texture / border) flip in real time as the cast toggles. (Castbar's `OnInterruptibilityChanged` handler still fires correctly.)

### M4-5. No spurious dispatches in a 5-man (or 25-player raid)
- [ ] Group with 4+ party members all casting actively (a dungeon trash pull is enough).
- [ ] `/kcd debug log on` — enables the internal-message log.
- [ ] Watch chat for several seconds.
- **Pass:** You should NOT see `KickCD_*` message dispatches firing in response to *party-member* casts. Cast bar handlers should not fire (no chat sign of `Castbar:OnCastStart` etc. for non-target casts). Without the unit filter you'd see hundreds of spurious internal-message lines per minute.
- [ ] `/kcd debug log off` to restore quiet chat.

### M4-6. IconGrid glow trigger still works
- [ ] `/kcd set icons.primaryGlowTrigger target_casting_interruptible`
- [ ] Target a hostile caster mid-interruptible-cast.
- **Pass:** Primary icon glows when target is casting an interruptible spell. Glow disappears on cast end / target swap.

### M4-7. OnDisable cleanup (optional, advanced)
- [ ] If you have an addon-disable workflow (`/kcd set enabled false`), toggle it off and on.
- **Pass:** No Lua errors. The private dispatch frames are released by `OnDisable` (`f:UnregisterAllEvents()` is called per frame).

---

## M5 — UX clarification + accessor cleanup (6e490d6)

### M5-1. `/kcd reset` help text
- [ ] `/kcd help`
- **Pass:** The `/kcd reset` line now reads "Reset a panel to defaults. `/kcd reset spells` rebuilds EVERY spec's list — for one spec, use `/kcd spells reset`." (P-2 above.)

### M5-2. `/kcd reset spells` still wipes every spec
- [ ] Customise the spell list on two different specs (add a spell, change a category).
- [ ] `/kcd reset spells`
- **Pass:** Both specs' lists revert to defaults. Chat prints `[KCD] spells reset to defaults`.

### M5-3. `/kcd spells reset` only wipes the active spec
- [ ] Customise the spell list on two different specs.
- [ ] `/kcd spells reset` (with no args — defaults to the active spec).
- **Pass:** Only the active spec's list reverts; the other spec's customisations remain.

### M5-4. Castbar PRIMARY anchor mode (the plan's M5 checkpoint)
- [ ] `/kcd set castbar.anchorMode PRIMARY`
- **Pass:** Cast bar attaches to the icon grid's primary icon button at the configured anchor points / offsets.
- [ ] Drag the icon grid (`/kcd unlock` → drag → `/kcd lock`).
- **Pass:** Cast bar follows the grid (re-anchors on `KickCD_GRID_LAYOUT` / drag stop).

### M5-5. Cast bar accessor fallback (FIRST tick after enable)
- [ ] `/reload` while `castbar.anchorMode = PRIMARY` and `visibility = always`.
- **Pass:** Cast bar appears anchored correctly on the first tick after reload. Tests the `KickCD:GetModule("IconGrid", true)` fallback path (no `KickCD_GRID_LAYOUT` payload yet at first tick).

### M5-6. Spec change + PRIMARY anchor
- [ ] In `castbar.anchorMode = PRIMARY`, swap specialisation in-game.
- **Pass:** After `BuildActiveList` rebuilds for the new spec, the cast bar re-anchors to the new primary icon. No Lua errors.

---

## Cross-cutting regression sweep

These are quick existing-feature checks that touch the surfaces this review modified. Run them last; they should be no-ops with respect to the changes, but a regression here = the review broke something.

### R-1. Profiles still work
- [ ] Settings → Profiles → create a new profile, switch to it, copy from the previous one, reset, delete.
- **Pass:** Each operation works without Lua errors. Switching profile rebuilds the icon grid and re-applies the cast bar to the new profile's settings.

### R-2. Schema validator boot output
- [ ] `/reload`
- **Pass:** No `[KCD]|cffff0000schema error|r:` lines on PLAYER_LOGIN.

### R-3. Slash ↔ panel parity
- [ ] Pick any setting, e.g. `castbar.width`. Change via panel.
- [ ] `/kcd get castbar.width` reflects the new value.
- [ ] `/kcd set castbar.width 240` — panel widget updates live.
- **Pass:** Bidirectional sync is intact.

### R-4. Cooldown observation + glow
- [ ] Cast an interrupt (e.g. Mind Freeze, Pummel, Kick) on a hostile caster.
- **Pass:** Primary icon dims (cooldown alpha/tint) for the CD duration; reads "ready" again at the end. If `primaryGlowTrigger != Never`, the glow re-appears when the spell is castable.

### R-5. `/kcd debug` subcommands
- [ ] `/kcd debug` (lists subcommands)
- [ ] `/kcd debug log on/off` (already tested in M4-5)
- [ ] `/kcd debug spells` / `/kcd debug grid` / `/kcd debug castbar` (whichever your build exposes — see [docs/testing.md](../../docs/testing.md))
- **Pass:** Each subcommand prints its diagnostic without Lua errors.

### R-6. Spec / talent / pet rebuild
- [ ] Swap to a different specialisation.
- **Pass:** Icon grid rebuilds against the new spec's spell list within ~1 frame; cast bar re-anchors if `anchorMode = PRIMARY`.

---

## Sign-off

| Section | Status |
|---|---|
| Pre-flight (P-1, P-2) | ☐ pass / ☐ fail |
| M1 cleanup (M1-1 → M1-4) | ☐ pass / ☐ fail |
| M2 doc refresh (M2-1) | ☐ pass / ☐ fail |
| M3 combat-state bus (M3-1 → M3-6) | ☐ pass / ☐ fail |
| M4 unit-event filter (M4-1 → M4-7) | ☐ pass / ☐ fail |
| M5 UX + accessor (M5-1 → M5-6) | ☐ pass / ☐ fail |
| Regression sweep (R-1 → R-6) | ☐ pass / ☐ fail |

If anything fails: capture the error, the failing step number, and the chat output; revert the commit chain or land a follow-up fix before pushing to remote.
