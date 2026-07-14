# Cooldowns Refresh Per-Frame Debounce — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse a same-frame burst of `SPELL_UPDATE_*` events into a single `Cooldowns:Refresh()` on the next frame, eliminating redundant full re-polls of the watched-spell list.

**Architecture:** Wrap the three cooldown events behind one `Util.Throttle(0, …)` coalescer created in `Cooldowns:OnEnable`. The events register to a thin `OnCooldownEvent` forwarder that calls the coalescer; `Refresh` itself is unchanged. `Throttle(0)` schedules a single `C_Timer.After(0, …)` per burst, so N same-frame events yield one `Refresh` next frame.

**Tech Stack:** Lua 5.1 (WoW client), Ace3 (AceEvent-3.0), headless Lua test harness under `tests/`.

## Global Constraints

- **Target client:** WoW 12.0.7 (Midnight). English only. Ace3 throughout. (verbatim from CLAUDE.md)
- **Never auto-stage / commit / push.** The user controls git; leave edits in the working tree. Commits happen only via `/wow-addon:commit` or by the user. (CLAUDE.md hard rule — overrides the TDD "commit" convention in this plan.)
- **Never bump the version.** No TOC / `KickCD.VERSION` / README edits. (CLAUDE.md)
- **Closed message bus:** the five `Ka0s_KickCD_*` messages are the only inter-module channel — do not add or alter messages. (CLAUDE.md)
- **Secret values:** do not compare/format/`tostring`/arithmetic on `C_Spell.GetSpellCooldown` timings or cast-info secrets. This change touches none of that path — keep it that way. (CLAUDE.md)
- **Local verification before done:** `lua tests/run.lua` (exit 0) and `luacheck .` (0 warnings). (CLAUDE.md §14A)
- **Scope:** change is confined to `modules/Cooldowns.lua` plus a new test file and its registration in `tests/run.lua`. No render, schema, or Compat changes.

---

### Task 1: Coalesce `SPELL_UPDATE_*` → `Refresh` with a per-frame throttle

**Files:**
- Create: `tests/test_cooldowns.lua`
- Modify: `tests/run.lua` (append `"test_cooldowns.lua"` to the `SUITES` table)
- Modify: `modules/Cooldowns.lua` (`OnEnable` event registration + new `OnCooldownEvent` method)

**Interfaces:**
- Consumes: `NS.Util.Throttle(ms, fn)` from `core/Util.lua:111` — leading-edge coalescing throttle; at `ms = 0` fires once on the next frame via `C_Timer.After(0, …)`, ignoring intermediate args.
- Consumes (test harness): `T.load(true, true)` → fresh enabled instance `{ NS, env, mocks }`; `inst.NS:GetModule("Cooldowns")`; `inst.mocks.__flushTimers()` drains the queued `C_Timer.After` callbacks (`tests/wow_mock.lua:72`).
- Produces: `Cooldowns:OnCooldownEvent()` — the new event handler that forwards to `self._refreshCoalesced()`. `self._refreshCoalesced` — the throttled dispatcher stored on the module in `OnEnable`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_cooldowns.lua`:

```lua
-- tests/test_cooldowns.lua — modules/Cooldowns.lua event coalescing
local T = _G.KICKCD_TEST
local test, assertEqual = T.test, T.assertEqual

test("SPELL_UPDATE_* burst coalesces to one Refresh per frame", function()
    -- Fresh enabled instance so Cooldowns:OnEnable has wired the coalescer.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")

    -- Drain any timers scheduled during load, then spy on Refresh.
    inst.mocks.__flushTimers()
    local refreshes = 0
    Cooldowns.Refresh = function() refreshes = refreshes + 1 end

    -- A same-frame burst of cooldown events must not re-poll synchronously.
    Cooldowns:OnCooldownEvent()
    Cooldowns:OnCooldownEvent()
    Cooldowns:OnCooldownEvent()
    assertEqual(refreshes, 0, "coalesced Refresh must not fire synchronously")

    -- Next frame: the burst collapses to exactly one Refresh.
    inst.mocks.__flushTimers()
    assertEqual(refreshes, 1, "burst must coalesce to a single Refresh")
end)
```

- [ ] **Step 2: Register the new suite**

In `tests/run.lua`, add `"test_cooldowns.lua"` to the `SUITES` table (after `"test_lifecycle.lua"`):

```lua
local SUITES = {
    "test_util.lua",
    "test_schema.lua",
    "test_database.lua",
    "test_bus.lua",
    "test_compat.lua",
    "test_debuglog.lua",
    "test_icongrid_layout.lua",
    "test_lifecycle.lua",
    "test_cooldowns.lua",
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `lua tests/run.lua`
Expected: the new suite reports `FAIL  SPELL_UPDATE_* burst coalesces to one Refresh per frame` with an error like `attempt to call ... 'OnCooldownEvent' (a nil value)` — the method does not exist yet. The runner exits non-zero.

- [ ] **Step 4: Add the coalescer and forwarder in `Cooldowns:OnEnable`**

In `modules/Cooldowns.lua`, inside `Cooldowns:OnEnable` (currently around lines 340–356), replace the cooldown-event registration block. Before:

```lua
    -- Game events that signal cooldown / usability / charge changes.
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN",        "Refresh")
    self:RegisterEvent("SPELL_UPDATE_USABLE",          "Refresh")
    self:RegisterEvent("SPELL_UPDATE_CHARGES",         "Refresh")
```

After:

```lua
    -- Game events that signal cooldown / usability / charge changes.
    -- SPELL_UPDATE_COOLDOWN / _USABLE are global (they don't name the changed
    -- spell) and chatty — they fire many times per frame in combat, and each
    -- fire would re-poll EVERY watched spell. Coalesce a same-frame burst into
    -- one Refresh on the next frame via a zero-delay throttle. Refresh ignores
    -- its args (it re-polls the watched table fresh), so the throttle's
    -- trailing-args semantics are irrelevant here.
    self._refreshCoalesced = NS.Util.Throttle(0, function() self:Refresh() end)
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN",        "OnCooldownEvent")
    self:RegisterEvent("SPELL_UPDATE_USABLE",          "OnCooldownEvent")
    self:RegisterEvent("SPELL_UPDATE_CHARGES",         "OnCooldownEvent")
```

- [ ] **Step 5: Add the `OnCooldownEvent` method**

In `modules/Cooldowns.lua`, immediately after the `Cooldowns:OnEnable` function (before `Cooldowns:OnPlayerEnteringWorld`), add:

```lua
--- AceEvent handler for the chatty SPELL_UPDATE_* family. Forwards into the
--- per-frame coalescer built in OnEnable so a burst of these events triggers
--- a single Refresh() on the next frame rather than one full re-poll each.
function Cooldowns:OnCooldownEvent()
    if self._refreshCoalesced then self._refreshCoalesced() end
end
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `lua tests/run.lua`
Expected: `PASS  SPELL_UPDATE_* burst coalesces to one Refresh per frame`, and the whole suite still ends with `N passed, 0 failed` (exit 0). The pre-existing `test_lifecycle.lua` cases that enable `Cooldowns` must remain green — the coalescer is created before the events register, so `OnEnable` still completes cleanly.

- [ ] **Step 7: Lint**

Run: `luacheck .`
Expected: `0 warnings / 0 errors`. (`self._refreshCoalesced` is a plain field assignment; no new globals or unused locals are introduced.)

- [ ] **Step 8: Hand off for commit — do NOT auto-commit**

Per the Global Constraints (CLAUDE.md hard rule), do not stage or commit. Show the working-tree diff and the green test + lint output, and tell the user the change is ready to commit via `/wow-addon:commit` (or their own `git`). The files in the change are: `modules/Cooldowns.lua`, `tests/test_cooldowns.lua`, `tests/run.lua`.

---

## Self-Review

**Spec coverage:**
- Debounce via `Util.Throttle(0)` → Task 1, Steps 4–5. ✓
- Confined to `modules/Cooldowns.lua` → Steps 4–5; test file + registration are the only additions. ✓
- `Rebuild` and its triggers stay synchronous → untouched (only the three `SPELL_UPDATE_*` registrations change). ✓
- Test: N `OnCooldownEvent` calls collapse to one `Refresh` after `__flushTimers()` → Step 1. ✓
- Verification (`lua tests/run.lua` exit 0, `luacheck .` 0 warnings) → Steps 6–7. ✓
- No message-bus / schema / secret-value change → nothing in the plan touches those paths. ✓
- No auto-commit → Step 8 + Global Constraints. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; all code shown in full. ✓

**Type consistency:** `_refreshCoalesced` (field) and `OnCooldownEvent` (method) are named identically in the implementation (Steps 4–5) and the test (Step 1). `Util.Throttle` signature matches `core/Util.lua:111`. `T.load` / `inst.mocks.__flushTimers` / `NS:GetModule` match `tests/run.lua` and `tests/wow_mock.lua`. ✓
