# Debug Logging Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make KickCD's debug console informative and un-spammy — a secret-safe sink, key-flow traces, settings capture at the write seam, and hot-path coalescing — per the Ka0s Standard `debug-logging` §4/§8/§9/§10.

**Architecture:** Format (§3) is already compliant and untouched. Changes: (A) `NS.Debug` sanitizes `...` args (§4); (B) one `[Set]` line at `Helpers.Set` with a per-path debounce (§10); (C) one-line flow traces at lifecycle/combat/profile/visibility/cast/spells/open seams (§8); (D) delete per-spell/per-icon spam, emit one summary per pass, gated (§9).

**Tech Stack:** Lua 5.1 (WoW client), Ace3, headless Lua test harness under `tests/` (`lua tests/run.lua`, `T.mocks.__flushTimers()` drains `C_Timer.After`).

## Global Constraints

- **Target client:** WoW 12.0.7 (Midnight); English only; Ace3. (CLAUDE.md)
- **Never auto-stage / commit / push.** Leave edits in the working tree; commits happen via `/wow-addon:commit` or the user. Overrides the TDD "commit" convention in this plan. (CLAUDE.md)
- **Never bump the version.** (CLAUDE.md)
- **Secret values:** never compare/format/`tostring`/arithmetic on a value that may be secret (`C_Spell.GetSpellCooldown` timings; cast-info `name`/`texture`/`notInterruptible`/`spellID`). The sink's new stringifier gates on `issecretvalue`; flow traces must log **no** secret fields. (CLAUDE.md)
- **Closed message bus:** the five `Ka0s_KickCD_*` messages are the only inter-module channel — do not add/alter messages. (CLAUDE.md)
- **Debug is session-only:** `NS.State.debug`, default off, never in SavedVariables, resets each `/reload`. (CLAUDE.md / standard §5)
- **Line format is fixed** (standard §3): `<HH:MM:SS> | [<Tag>] <content>` via `DebugLog.FormatPlain`/`FormatColored` — do NOT change these.
- **Tag vocabulary** (standard §3, one short word): `Init`, `Migrate`, `Profile`, `Combat`, `Cooldowns`, `IconGrid`, `Cast`, `Set`, `Spells`, `Open`, `Debug`.
- **Verify before done:** `lua tests/run.lua` exits 0; `luacheck .` introduces no new warnings.

---

### Task 1: Secret-safe sink + `[Init]` snapshot on enable

**Files:**
- Modify: `modules/DebugLog.lua` (`NS.Debug` sink; `DebugLog:SetEnabled`)
- Test: `tests/test_debuglog.lua` (append cases)

**Interfaces:**
- Produces: `DebugLog.secretSafe(v)` — returns `"secret"` when `issecretvalue(v)` is true, else `v` (identity when `issecretvalue` is absent, e.g. under the harness). `NS.Debug(tag, fmt, ...)` unchanged signature; now sanitizes each `...` arg before `string.format`.
- Consumes: `NS.db.global.schemaVersion`, `NS.db:GetCurrentProfile()` (AceDB), `NS.VERSION`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_debuglog.lua`:

```lua
test("NS.Debug sanitizes secret args and never errors", function()
    -- Stub a secret sentinel: issecretvalue true only for this table.
    local SECRET = setmetatable({}, {})
    local realIsSecret = _G.issecretvalue
    _G.issecretvalue = function(v) return v == SECRET end
    NS.State.debug = true
    NS.DebugLog:Clear()
    local ok = pcall(function() NS.Debug("T", "charges=%s", SECRET) end)
    _G.issecretvalue = realIsSecret
    assertTrue(ok, "sink must not error on a secret arg")
    local line = NS.DebugLog:LastLine()
    assertTrue(line and line:find("charges=secret", 1, true) ~= nil,
        "secret arg must render as 'secret'; got: " .. tostring(line))
end)

test("NS.Debug passes plain args through unchanged", function()
    NS.State.debug = true
    NS.DebugLog:Clear()
    NS.Debug("T", "n=%d s=%s", 7, "hi")
    local line = NS.DebugLog:LastLine()
    assertTrue(line and line:find("n=7 s=hi", 1, true) ~= nil,
        "plain args must be unchanged; got: " .. tostring(line))
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: the two new `test_debuglog` cases FAIL — `secretSafe` doesn't exist yet, so `charges=%s` currently formats the raw table (no `secret` substitution). Runner exits non-zero.

- [ ] **Step 3: Add the secret-safe stringifier and rewire the sink**

In `modules/DebugLog.lua`, replace the `NS.Debug` function (currently at the bottom) with:

```lua
--- Substitute a placeholder for a combat-protected "secret" value so the sink
--- (§4) can never raise inside string.format when a call site passes one (e.g.
--- charges in combat). Identity pass-through when issecretvalue is unavailable
--- (headless harness) or the value is plain.
local function secretSafe(v)
    if _G.issecretvalue and _G.issecretvalue(v) then return "secret" end
    return v
end
DebugLog.secretSafe = secretSafe

--- NS.Debug(tag, fmt, ...) — zero-allocation when off (the gate is the first
--- line; no format/concat/table build before it). Each ... arg is routed
--- through secretSafe so a secret value renders as "secret" rather than
--- erroring the console. Routes to the console, not chat.
function NS.Debug(tag, fmt, ...)
    if not (NS.State and NS.State.debug) then return end
    local n = select("#", ...)
    local msg
    if n > 0 then
        local args = { ... }
        for i = 1, n do args[i] = secretSafe(args[i]) end
        msg = string.format(fmt, unpack(args, 1, n))
    else
        msg = fmt
    end
    if NS.DebugLog and NS.DebugLog.Add then
        NS.DebugLog:Add(tag, msg)
    end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: both new cases PASS; whole suite ends `N passed, 0 failed` (exit 0).

- [ ] **Step 5: Emit the `[Init]` snapshot when capture starts**

Debug is off at login, so an `OnEnable` boot line would always be gated off. Emit it from `SetEnabled(true)` instead, where it is visible. In `modules/DebugLog.lua`, inside `DebugLog:SetEnabled`, after the existing bracket `DebugLog:Add("Debug", …)` call, add:

```lua
    -- On enable, snapshot the session's load-time facts (standard §8 boot
    -- summary) so a log captured mid-session still records what it's running
    -- against. Emitted through the raw Add (state just flipped on; NS.Debug
    -- would also work, but Add keeps this ordered right after the bracket).
    if on and NS.db then
        local ver     = NS.VERSION or "?"
        local schema  = NS.db.global and NS.db.global.schemaVersion or "?"
        local profile = NS.db.GetCurrentProfile and NS.db:GetCurrentProfile() or "?"
        DebugLog:Add("Init", ("KickCD v%s, schema v%s, profile '%s'")
            :format(tostring(ver), tostring(schema), tostring(profile)))
    end
```

- [ ] **Step 6: Verify enable snapshot + lint**

Run: `lua tests/run.lua` (Expected: exit 0 — existing `test_debuglog` `SetEnabled` cases still green; the snapshot is additive and guarded on `NS.db`).
Run: `luacheck .` (Expected: 0 new warnings).

- [ ] **Step 7: Hand off — do NOT commit** (see Global Constraints). Report the diff + green test/lint output.

---

### Task 2: Coalesce Cooldowns + IconGrid hot-path spam (§9)

**Files:**
- Modify: `modules/Cooldowns.lua` (`Refresh`, `Rebuild`; delete per-spell dprints)
- Modify: `modules/IconGrid_Render.lua` (delete per-icon `apply` lines at ~:534/:549/:559)
- Test: `tests/test_cooldowns.lua` (append)

**Interfaces:**
- Consumes: `NS.Debug` (secret-safe, Task 1). `Cooldowns.watched` (dict spellID→state), `Cooldowns:PollSpell`, `StateChanged` (existing).
- Produces: `Cooldowns:Refresh` emits at most one `[Cooldowns]` line per pass (only when ≥1 spell changed). `Cooldowns:Rebuild` emits one `[Cooldowns] rebuild …` line.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_cooldowns.lua`:

```lua
test("Refresh logs one coalesced line only when a spell changed", function()
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    -- Two watched spells; make PollSpell report id 100 changed, id 200 same.
    Cooldowns.watched = {
        [100] = { spellID = 100, ready = false, isActive = true },
        [200] = { spellID = 200, ready = true,  isActive = false },
    }
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return { spellID = 100, ready = true, isActive = false } end
        return { spellID = 200, ready = true, isActive = false }  -- unchanged
    end

    local before = inst.NS.DebugLog:BufferSize()
    Cooldowns:Refresh()
    local after = inst.NS.DebugLog:BufferSize()
    assertEqual(after - before, 1, "exactly one coalesced line when something changed")
    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("[Cooldowns]", 1, true) and line:find("100", 1, true),
        "line names the changed id; got: " .. tostring(line))
end)

test("Refresh logs nothing when no spell changed", function()
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()
    Cooldowns.watched = { [200] = { spellID = 200, ready = true, isActive = false } }
    Cooldowns.PollSpell = function(_, id) return { spellID = 200, ready = true, isActive = false } end
    local before = inst.NS.DebugLog:BufferSize()
    Cooldowns:Refresh()
    assertEqual(inst.NS.DebugLog:BufferSize(), before, "no line on a no-change pass")
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: the two new cases FAIL — today `Refresh` logs per-spell `poll`/`emit` lines (so the counts won't be exactly 1 and 0). Exit non-zero.

- [ ] **Step 3: Rewrite `Cooldowns:Refresh` to coalesce**

In `modules/Cooldowns.lua`, remove the per-spell `dprint("poll …")` in `PollSpell` (the block at ~:173-181) and the `dprint("emit …")` / `dprint("drop …")` / `dprint("skipping …")` calls. Replace `Refresh`'s body so it accumulates changed ids (only when debug-on) and emits one line:

```lua
function Cooldowns:Refresh()
    if not isEnabled() then return end
    if not self.watched then return end

    local dbg = NS.State and NS.State.debug
    local readyIds, activeIds, dropIds  -- built only when debug-on (§9 zero-alloc)
    if dbg then readyIds, activeIds, dropIds = {}, {}, {} end
    local watched, changed = 0, 0

    for id, prev in pairs(self.watched) do
        watched = watched + 1
        local next_ = self:PollSpell(id)
        if next_ == nil then
            self.watched[id] = nil
            changed = changed + 1
            if dbg then dropIds[#dropIds + 1] = id end
            NS:SendMessage("Ka0s_KickCD_SPELL_STATE", {
                spellID = id, ready = false, isActive = false,
                cdObject = nil, chargeCdObject = nil, charges = nil,
            })
        elseif StateChanged(prev, next_) then
            self.watched[id] = next_
            changed = changed + 1
            if dbg then
                if next_.ready then readyIds[#readyIds + 1] = id
                elseif next_.isActive then activeIds[#activeIds + 1] = id end
            end
            NS:SendMessage("Ka0s_KickCD_SPELL_STATE", {
                spellID = next_.spellID, ready = next_.ready, isActive = next_.isActive,
                cdObject = next_.cdObject, chargeCdObject = next_.chargeCdObject,
                charges = next_.charges,
            })
        end
    end

    if dbg and changed > 0 then
        local parts = {}
        if #readyIds  > 0 then parts[#parts+1] = "ready=["  .. table.concat(readyIds, ",")  .. "]" end
        if #activeIds > 0 then parts[#parts+1] = "active=[" .. table.concat(activeIds, ",") .. "]" end
        if #dropIds   > 0 then parts[#parts+1] = "drop=["   .. table.concat(dropIds, ",")   .. "]" end
        NS.Debug("Cooldowns", "%d/%d changed: %s", changed, watched, table.concat(parts, " "))
    end
end
```

Note: `PollSpell` keeps its own internal `dprint` removed; it still returns the state table. Keep the `dprint` helper only if `Rebuild` still uses it (Step 4 replaces that use), otherwise delete the now-unused `dprint` local to satisfy luacheck.

- [ ] **Step 4: Rewrite `Cooldowns:Rebuild` summary**

In `modules/Cooldowns.lua` `Rebuild`, after the watched-list is built, replace the per-spell `skipping` logging with one summary. Track `watched` and `skipped` counts in the build loop and, before returning, add:

```lua
    if NS.State and NS.State.debug then
        NS.Debug("Cooldowns", "rebuild %s/%s: %d watched (%d skipped)",
            tostring(class), tostring(spec), builtCount, skippedCount)
    end
```

(where `builtCount` increments on each `self.watched[id] = state` and `skippedCount` increments on each `state == nil` branch). Remove the now-unused `dprint` local if nothing else references it.

- [ ] **Step 5: Delete per-icon apply lines**

In `modules/IconGrid_Render.lua`, delete the three `NS.Debug("IconGrid", ("apply …"))` calls at ~:534, :549, :559. Leave the surrounding render logic intact.

- [ ] **Step 6: Run tests + lint**

Run: `lua tests/run.lua` (Expected: the two new cases PASS; existing `test_cooldowns` coalescing/debounce test and all suites green; exit 0).
Run: `luacheck .` (Expected: 0 new warnings — confirm no orphaned `dprint`/locals remain).

- [ ] **Step 7: Hand off — do NOT commit.** Report diff + green output.

---

### Task 3: Settings capture at the write seam (§10)

**Files:**
- Modify: `settings/Panel.lua` (`Helpers.Set`; add `logSet` + `fmtSetValue`)
- Test: `tests/test_settings_log.lua` (new) + register in `tests/run.lua`

**Interfaces:**
- Consumes: `NS.Debug` (Task 1); `NS.State.debug`; `C_Timer.After` (harness-stubbed, drained by `__flushTimers`).
- Produces: `Helpers.Set(path, section, value)` emits one debounced `[Set] <path> = <value>` line per settled change.

- [ ] **Step 1: Write the failing test**

Create `tests/test_settings_log.lua`:

```lua
-- tests/test_settings_log.lua — settings-change capture at Helpers.Set (§10)
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("Helpers.Set logs one debounced [Set] line with the settled value", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()

    -- Two rapid writes to the same path within the debounce window.
    Helpers.Set("locked", "general", false)
    Helpers.Set("locked", "general", true)
    assertEqual(NS.DebugLog:BufferSize(), 0, "nothing logs before the debounce fires")

    inst.mocks.__flushTimers()
    assertEqual(NS.DebugLog:BufferSize(), 1, "burst collapses to one [Set] line")
    local line = NS.DebugLog:LastLine()
    assertTrue(line:find("[Set]", 1, true) and line:find("locked = true", 1, true),
        "line carries the settled value; got: " .. tostring(line))
end)

test("Helpers.Set formats an RGBA table compactly", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    Helpers.Set("castbar.color", "castbar", { 1, 0.5, 0, 1 })
    inst.mocks.__flushTimers()
    local line = NS.DebugLog:LastLine()
    assertTrue(line and line:find("{1,0.5,0,1}", 1, true) ~= nil,
        "RGBA renders as {r,g,b,a}; got: " .. tostring(line))
end)
```

Register the suite: in `tests/run.lua`, append `"test_settings_log.lua"` to the `SUITES` table.

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: new suite FAILS — `Helpers.Set` logs nothing today, so `BufferSize()` stays 0 after flush. Exit non-zero.

- [ ] **Step 3: Add `fmtSetValue` + `logSet` and call from `Helpers.Set`**

In `settings/Panel.lua`, above `Helpers.Set` (near line 70), add:

```lua
-- Settings-change logging (standard §10): one [Set] line per settled change,
-- at the single write seam. Color/slider commits call Helpers.Set on every
-- throttled drag tick (~20/sec), so a per-path trailing debounce collapses a
-- drag to one line carrying the final value. String-building stays behind the
-- debug gate (§4 zero-alloc).
local SET_LOG_DEBOUNCE = 0.3
local pendingSet, setArmed = {}, {}

local function fmtSetValue(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for i = 1, #v do parts[i] = tostring(v[i]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function logSet(path, value)
    if not (NS.State and NS.State.debug) then return end   -- gate first
    pendingSet[path] = value
    if setArmed[path] then return end
    setArmed[path] = true
    C_Timer.After(SET_LOG_DEBOUNCE, function()
        setArmed[path] = nil
        local v = pendingSet[path]
        pendingSet[path] = nil
        if NS.State and NS.State.debug then
            NS.Debug("Set", "%s = %s", tostring(path), fmtSetValue(v))
        end
    end)
end
```

Then call it inside `Helpers.Set` after the write:

```lua
function Helpers.Set(path, section, value)
    local parent, key = Resolve(path)
    if not parent then return end
    parent[key] = value
    logSet(path, value)
    Helpers.FireConfigChanged(section)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: new suite PASSES; whole run exits 0.

- [ ] **Step 5: Lint**

Run: `luacheck .`
Expected: 0 new warnings.

- [ ] **Step 6: Hand off — do NOT commit.** Report diff + green output.

---

### Task 4: Key functional-flow traces (§8)

**Files:**
- Modify: `core/Database.lua` (`OnProfileChanged`; `Migrate` seam)
- Modify: `core/State.lua` (combat transitions)
- Modify: `core/KickCD.lua` (`OpenSettings`)
- Modify: `modules/IconGrid.lua` (`RefreshVisibility` transition; `RefreshAllGlows` cast gate)
- Modify: `settings/Spells.lua` (enable/disable/remove/reset mutations)
- Test: `tests/test_flow_traces.lua` (new) + register in `tests/run.lua`

**Interfaces:**
- Consumes: `NS.Debug` (Task 1). Existing seams: `Database:OnProfileChanged` (Database.lua:505), `State` combat handler (State.lua:138-142), `IconGrid:RefreshVisibility` (IconGrid.lua:677), `IconGrid:RefreshAllGlows` (IconGrid.lua:720), `OpenSettings` (KickCD.lua:898), Spells mutations (Spells.lua:500 toggle, :604 remove, :394 reset).
- Produces: one gated line per transition at each seam; each line contains **no secret fields**.

- [ ] **Step 1: Write the failing test (the two harness-reachable traces)**

Create `tests/test_flow_traces.lua`:

```lua
-- tests/test_flow_traces.lua — §8 flow traces reachable headlessly
local T = _G.KICKCD_TEST
local test, assertTrue = T.test, T.assertTrue

test("OnProfileChanged logs a [Profile] line", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Database = NS:GetModule("Database")
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    Database:OnProfileChanged(nil, NS.db, "Raider")
    local line = NS.DebugLog:LastLine()
    assertTrue(line and line:find("[Profile]", 1, true) and line:find("Raider", 1, true),
        "profile switch logs a [Profile] line naming the key; got: " .. tostring(line))
end)
```

Register the suite: append `"test_flow_traces.lua"` to `SUITES` in `tests/run.lua`.

(Only `Profile` is asserted here — it is cleanly callable in the harness. `Combat`, `IconGrid`, `Cast`, `Open`, `Spells` are event/frame-driven; they get luacheck coverage + smoke-test entries in Step 8.)

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: new suite FAILS — no `[Profile]` line is emitted today. Exit non-zero.

- [ ] **Step 3: Add the `[Profile]` and `[Migrate]` traces**

In `core/Database.lua` `OnProfileChanged`, after `local key = …` (line 508), add:

```lua
    if NS.State and NS.State.debug then
        NS.Debug("Profile", "switched to '%s'", tostring(key))
    end
```

In `core/Database.lua`'s migration runner (`MigrateAccount`/`MigrateProfile`), inside the loop that applies a migration step, add one line **only when a step actually runs** (there are none at `CURRENT_DB_VERSION = 1`; this is the seam):

```lua
        if NS.State and NS.State.debug then
            NS.Debug("Migrate", "v%d -> v%d", from, from + 1)
        end
```

- [ ] **Step 4: Add the `[Combat]` trace**

In `core/State.lua`, in the boot frame `OnEvent` (line 138), log the two real transitions (not the PLAYER_LOGIN seed):

```lua
    if event == "PLAYER_REGEN_DISABLED" then
        State.SetInCombat(true)
        if State.debug and NS and NS.Debug then NS.Debug("Combat", "entered") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        State.SetInCombat(false)
        if State.debug and NS and NS.Debug then NS.Debug("Combat", "left") end
    elseif event == "PLAYER_LOGIN" then
        State.SetInCombat(_G.InCombatLockdown and _G.InCombatLockdown() or false)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
```

- [ ] **Step 5: Add the `[IconGrid]` visibility + `[Cast]` gate traces (transition-only)**

In `modules/IconGrid.lua` `RefreshVisibility` (line 677), track the last-shown bool on the module and log only on change:

```lua
function IconGrid:RefreshVisibility()
    if not grid then return end
    local show = shouldBeVisible()
    if NS.State and NS.State.debug and show ~= self._lastVisible then
        NS.Debug("IconGrid", "visibility %s: %s", tostring(visibilityMode()),
            show and "shown" or "hidden")
    end
    self._lastVisible = show
    if show then
        grid:Show()
    else
        grid:Hide()
    end
    -- (keep the rest of the existing body: ApplyInterruptibilityMask(), etc.)
end
```

In `modules/IconGrid.lua` `RefreshAllGlows` (line 720), which already short-circuits when the (hostile-cast, interruptible) gate hasn't moved, add — at the point where it detects the gate moved, using only the non-secret booleans it already computes — one line:

```lua
        if NS.State and NS.State.debug then
            NS.Debug("Cast", "target cast gate: interruptible %s", interruptible and "on" or "off")
        end
```

(Place it beside the existing gate-changed branch; log **no** spellID/name/notInterruptible value — only the boolean the function already derived C-side. If the current code names that boolean differently, reuse that local.)

- [ ] **Step 6: Add the `[Open]` and `[Spells]` traces**

In `core/KickCD.lua` `OpenSettings` (line 898), at the top of the successful-open path:

```lua
    if NS.State and NS.State.debug then NS.Debug("Open", "settings panel") end
```

In `settings/Spells.lua`:
- At the per-row toggle (line ~500, `entry.enabled = value and true or false`):

```lua
        if NS.State and NS.State.debug then
            NS.Debug("Spells", "%s %s", value and "enable" or "disable", tostring(entry.spellID))
        end
```

- At the remove (line ~604, before `table.remove(list, index)`), capture the id first:

```lua
        local removedId = list[index] and list[index].spellID
        table.remove(list, index)
        if NS.State and NS.State.debug then
            NS.Debug("Spells", "remove %s", tostring(removedId))
        end
```

- At the reset-to-defaults / copy path (line ~394-403), after the list is populated, one summary:

```lua
        if NS.State and NS.State.debug then
            NS.Debug("Spells", "reset %s/%s: %d spells",
                tostring(selectedClass), tostring(selectedSpec),
                #spells[selectedClass][selectedSpec])
        end
```

- [ ] **Step 7: Run tests + lint**

Run: `lua tests/run.lua` (Expected: `[Profile]` case PASSES; all suites green; exit 0).
Run: `luacheck .` (Expected: 0 new warnings — verify no undefined local like `interruptible` was assumed; reuse the real one).

- [ ] **Step 8: Add smoke-test entries for the event-driven traces**

In `docs/smoke-tests.md`, add a short "Debug traces" checklist: enable `/kcd debug on`, then verify one line each appears for — entering/leaving combat (`[Combat]`), switching profile (`[Profile]`), a target starting/stopping a cast (`[Cast]`, `[IconGrid]` when visibility mode is cast-gated), opening settings (`[Open]`), toggling/removing a spell (`[Spells]`), and changing any setting (`[Set]`), with no per-tick spam during sustained combat.

- [ ] **Step 9: Hand off — do NOT commit.** Report diff + green output + the smoke-test additions.

---

## Self-Review

**Spec coverage:**
- §4 secret-safe sink → Task 1. ✓
- §8 coverage: Init (Task 1 Step 5), Migrate/Profile (Task 4), Combat (Task 4), Cooldowns rebuild (Task 2), IconGrid visibility + Cast (Task 4), Spells (Task 4), Open (Task 4). ✓
- §9 coalescing: Cooldowns Refresh/Rebuild + IconGrid apply removal (Task 2). ✓
- §10 settings at seam, debounced, no re-echo → Task 3 (reactors already silent). ✓
- §3 format untouched; tags standardized via Global Constraints vocabulary. ✓
- Tests: sink, coalescing, settings, profile trace → Tasks 1-4. ✓

**Placeholder scan:** No TBD/TODO; all code shown. The `Migrate`/`Cast` seams note "reuse the real local" where the exact name lives in unchanged code — that is an instruction to match existing code, not a placeholder.

**Type/name consistency:** `secretSafe`, `logSet`, `fmtSetValue`, `_lastVisible`, `SET_LOG_DEBOUNCE`, `pendingSet`/`setArmed` are defined and referenced consistently within their tasks. `NS.Debug` signature unchanged across all call sites. Test helpers (`T.load`, `inst.mocks.__flushTimers`, `NS.DebugLog:BufferSize/LastLine/Clear`, `NS:GetModule`) match `tests/run.lua` and `modules/DebugLog.lua`.
