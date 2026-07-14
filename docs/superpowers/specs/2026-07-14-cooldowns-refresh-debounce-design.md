# Design — Coalesce Cooldowns `Refresh` (per-frame debounce)

**Date:** 2026-07-14
**Module touched:** `modules/Cooldowns.lua` (only)
**Status:** Approved design → implementation plan

## Problem

`modules/Cooldowns.lua` registers three Blizzard events directly to `Refresh`:

```lua
self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "Refresh")
self:RegisterEvent("SPELL_UPDATE_USABLE",   "Refresh")
self:RegisterEvent("SPELL_UPDATE_CHARGES",  "Refresh")
```

These events are **global** (they don't name the changed spell) and **chatty** — they fire many times per second while any cooldown runs or a resource/aura changes (combat-open, an active totem, etc.). Each fire calls `Refresh()`, which re-polls **every** watched spell (`Cooldowns.lua:297`). A same-frame burst of N events therefore triggers N full re-polls of the whole watched list.

This is already event-driven (there is no wall-clock timer in the module — the "poll" debug lines are just `PollSpell` reacting to events), and the `StateChanged` filter (`Cooldowns.lua:198`) already prevents redundant `SPELL_STATE` emissions downstream. The waste is confined to the redundant re-polls themselves and the proportional debug-log spam.

## Goal

Collapse a same-frame burst of `SPELL_UPDATE_*` events into a **single** `Refresh()` on the next frame, eliminating the redundant re-polls with no perceptible latency and no behavioral/contract change.

## Non-goals

- No `OnCooldownDone` hook (the separately-considered option #2). It can't replace `SPELL_UPDATE_COOLDOWN` — that event is the only reliable "a cooldown just started" signal for protected interrupts, whose `UNIT_SPELLCAST_SUCCEEDED` Blizzard suppresses. Additive complexity for marginal gain; out of scope.
- No change to the message-bus contract, `Settings.Schema`, the render layer, or `Rebuild` and its triggers.
- No change to debug logging (fewer `Refresh` calls already yields proportionally fewer `poll` lines — the spam is a symptom, not a separate concern).

## Approach (chosen: reuse `Util.Throttle`)

`core/Util.lua` already provides `Util.Throttle(ms, fn)` (`Util.lua:111`): a leading-edge coalescing throttle. The first call in a burst schedules a `C_Timer.After(ms/1000, …)`; later calls within the window only update the pending args; the wrapped `fn` runs once when the window closes. At `ms = 0` this becomes exactly "coalesce every call within the current frame into one call on the next frame."

`Refresh` ignores its arguments (it re-polls the watched table fresh each time), so `Throttle`'s "trailing args win" semantics are irrelevant here — no staleness concern.

**Rejected alternatives:**

- **Hand-rolled pending-flag** (`self._refreshPending` + inline `C_Timer.After(0)`): functionally identical to reusing `Util.Throttle`, but re-implements a tested helper. No.
- **Dedicated dispatch frame + `OnUpdate`**: extra persistent frame and machinery, no benefit over the throttle. No.

### Coalescing window

**Next frame (`Util.Throttle(0, …)`).** Zero perceptible latency — a state change lands ~1 frame (~16 ms at 60 fps) later than today. Collapses same-frame bursts; events genuinely spaced across frames still each trigger a poll, which is correct (those are real, distinct changes). Wider windows (50 ms / 100 ms) were considered and rejected in favor of zero latency, since the same-frame burst is the dominant source of waste.

## Changes to `modules/Cooldowns.lua`

1. **In `OnEnable`, before registering events**, build one coalesced dispatcher stored on the module:

   ```lua
   self._refreshCoalesced = NS.Util.Throttle(0, function() self:Refresh() end)
   ```

2. **Register the three `SPELL_UPDATE_*` events to a thin forwarder** instead of directly to `"Refresh"`. AceEvent dispatches to a named method on the module, so add a small method that forwards into the coalescer:

   ```lua
   function Cooldowns:OnCooldownEvent()
       if self._refreshCoalesced then self._refreshCoalesced() end
   end
   ```

   and register:

   ```lua
   self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownEvent")
   self:RegisterEvent("SPELL_UPDATE_USABLE",   "OnCooldownEvent")
   self:RegisterEvent("SPELL_UPDATE_CHARGES",  "OnCooldownEvent")
   ```

3. **Everything else is unchanged.** `Refresh`, `Rebuild`, `PollSpell`, `StateChanged`, and all `Rebuild`-triggering registrations (`PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`, the two message subscriptions) keep firing synchronously and immediately.

### Why this is safe

- `Refresh` already guards on `isEnabled()` and `self.watched` (`Cooldowns.lua:294–296`), so a coalesced timer that fires after the module is disabled is a harmless no-op.
- `Rebuild`'s initial per-spell `SPELL_STATE` emissions on login are **not** deferred — only the `SPELL_UPDATE_*` refresh path is.
- No secret-value handling changes: `PollSpell` and the duration-object flow are untouched.

## Behavior delta

A same-frame burst of N cooldown events produces **one** `Refresh` on the next frame instead of N synchronous ones. The only observable difference: a ready ↔ on-cooldown flip lands ~1 frame later. Imperceptible for a cooldown/interrupt tracker. Steady-state (well-spaced events) is unchanged.

## Testing

The headless harness (`tests/`) already loads and enables `Cooldowns` via `T.load(true, true)` (see `tests/test_lifecycle.lua`), exposes modules through `NS:GetModule("Cooldowns")`, stubs `C_Timer.After` into a queue, and drains it with `T.mocks.__flushTimers()` (`tests/wow_mock.lua:72`). `Util.Throttle` itself is already covered (`tests/test_util.lua:43`).

Add one focused test (new `tests/test_cooldowns.lua`, registered in `tests/run.lua`):

- Load a fresh enabled instance; get the `Cooldowns` module.
- Replace `Cooldowns.Refresh` with a counter (`local n = 0; module.Refresh = function() n = n + 1 end`).
- Invoke the coalesced path (`module:OnCooldownEvent()`) several times in a row **without** flushing.
- Assert the counter is still `0` (nothing ran synchronously).
- Call `T.mocks.__flushTimers()`.
- Assert the counter is exactly `1` (the burst collapsed to a single `Refresh`).

Run `lua tests/run.lua` (must exit 0) and `luacheck .` (0 warnings) before commit, per CLAUDE.md.

## Standard compliance

No Ka0s WoW Addon Standard deviation. This is an internal implementation detail of one module; the closed five-message bus, `Settings.Schema`, Compat/State/Constants split, and secret-value rules are all untouched.
