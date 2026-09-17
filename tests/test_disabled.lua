-- tests/test_disabled.lua — the stand-down conformance suite (slash-commands-§7).
--
-- WHAT THIS SUITE IS FOR, AND WHY IT ASSERTS WHAT IT ASSERTS.
--
-- "Disabled" used to mean a DRAW GATE in this addon, as it did in all eleven addons in the
-- collection: the grid and the bar went away, every registration stayed, and the client went on
-- walking KickCD's registration list on every SPELL_UPDATE_COOLDOWN in a twenty-five-man raid,
-- building the argument frame, entering Lua and running the comparison that decided to leave. The
-- addon had not stopped watching -- it had stopped REACTING -- and from outside the two are
-- indistinguishable, which is exactly how the draw gate survived eleven audits.
--
-- So the assertions here are about the REGISTRATION SET and nothing else. A case written as "call
-- the handler and assert it returned early" would be the draw gate passing its own test: an early
-- return is what a draw gate does. Step 3 below asks the mock's registry what this addon is still
-- registered for, by count and by name, and that is the case the whole file exists for.
--
-- The ten steps are slash-commands-§7's own, in its order.
--
-- ── TWO SURFACES, ONE QUESTION ──────────────────────────────────────────────────────────────
--
-- `mocks.__registrationSet()` (tests/wow_mock.lua) is the union of the kit's `__registrations()`
-- -- the AceEvent events, the bus messages and the buckets -- and this addon's own frame registry,
-- because KickCD's frame model is the host mock's rather than the kit's. Both halves REMOVE on
-- unregister, which is the property that makes "the set is empty" falsifiable in the useful
-- direction: a registry that only ever grew would report a perfectly torn-down addon as still
-- watching everything, and a suite written against it would be tuned until it stopped asking.
--
-- ── WHY THE SAVED-VARIABLES CHECK IS A DIFF RATHER THAN THE KIT'S ───────────────────────────
--
-- The kit's `__svWrites()` reads through the kit's own AceDB fake. This addon's mock carries its
-- own AceDB (tests/wow_mock.lua, and it predates the kit's by a long way: it stages a
-- pre-migration account out of `mocks.KickCDDB`, which several migration suites depend on), so the
-- kit's survey has no root to diff. The diff below is the same idea over the live `NS.db`: deep
-- snapshot, then compare leaf by leaf. What it cannot see is a write of the identical value over
-- itself; what it is asked to prove is that a stood-down addon wrote NOTHING, and a write that
-- changed nothing changed nothing.

local T = _G.KICKCD_TEST
local test         = T.test
local assertTrue   = T.assertTrue
local assertFalse  = T.assertFalse
local assertEqual  = T.assertEqual
local assertNil    = T.assertNil

-- ---------------------------------------------------------------------------
-- Surveys
-- ---------------------------------------------------------------------------

--- One registration as a comparable string: kind, event and unit token. Per UNIT TOKEN rather than
--- per event, because the per-unit filter is the thing a stand-down most often widens by accident --
--- an addon that re-registers UNIT_SPELLCAST_START for every unit instead of the enabled ones has
--- the same event count and a different registration set.
local function key(reg)
    return ("%s|%s|%s"):format(reg.kind, tostring(reg.event), tostring(reg.unit))
end

--- The registration set as a counted bag of those keys, plus its size.
local function registrations(inst)
    local bag, n = {}, 0
    for _, reg in ipairs(inst.mocks.__registrationSet()) do
        bag[key(reg)] = (bag[key(reg)] or 0) + 1
        n = n + 1
    end
    return bag, n
end

--- Every name still registered, sorted, for a failure message that says WHAT survived rather than
--- how many did. A count alone sends the next reader back to the mock to find out which.
local function survivors(inst)
    local names = {}
    for name in pairs((registrations(inst))) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ", ")
end

--- Frames that are actually ON SCREEN: shown, with every ancestor shown, and POSITIONED.
---
--- The position is what separates a display frame from an event-dispatch frame. CreateFrame'd
--- frames start shown in the client and in this mock, and the addon never hides the private frames
--- it uses purely to receive events -- there is nothing to hide, they draw nothing and they carry no
--- anchor. Asking for a SetPoint is how this suite says "the things the player can see" without
--- reaching into the modules for their instance tables.
local function shownFrames(inst)
    local out = {}
    for _, f in ipairs(inst.mocks.__frames or {}) do
        if f.__points and #f.__points > 0 and f.IsVisible and f:IsVisible() then
            out[#out + 1] = f
        end
    end
    return out
end

--- A deep snapshot of the addon's whole stored tree, for the write diff described in the header.
local function svSnapshot(inst)
    local copy = inst.mocks.__deepcopy
    local db = inst.NS.db
    return { profile = copy(db.profile), global = copy(db.global) }
end

--- Every leaf that differs between two snapshots, as dotted paths.
local function svDiff(before, after)
    local out = {}
    local function walk(prefix, now, was)
        if type(now) ~= "table" then return end
        for k, v in pairs(now) do
            local path = prefix .. "." .. tostring(k)
            local old
            if type(was) == "table" then old = was[k] end
            if type(v) == "table" then
                walk(path, v, old)
            elseif v ~= old then
                out[#out + 1] = path
            end
        end
        if type(was) == "table" then
            for k, v in pairs(was) do
                if now[k] == nil and type(v) ~= "table" then out[#out + 1] = prefix .. "." .. tostring(k) end
            end
        end
    end
    walk("profile", after.profile, before.profile)
    walk("global",  after.global,  before.global)
    table.sort(out)
    return out
end

--- Everything NS.Util.print emits while `fn` runs.
local function say(inst, fn)
    local lines, real = {}, inst.NS.Util.print
    inst.NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    inst.NS.Util.print = real
    if not ok then error(err, 0) end
    return lines
end

-- ---------------------------------------------------------------------------
-- Driving the switch
-- ---------------------------------------------------------------------------

--- Write the enable path THROUGH THE SINGLE WRITE SEAM -- never by calling a teardown function
--- directly. §7 step 2 is explicit about this: the test has to exercise the route the checkbox and
--- the `/kcd disable` verb take, or it proves the teardown works and says nothing about whether
--- anything reaches it.
local function setEnabled(inst, on, keepTimers)
    inst.NS.Settings.Helpers.SetAndRefresh("enabled", on)
    -- The flush settles whatever the write itself coalesced, so the assertions after it are about
    -- the addon rather than about a queue that happened to be mid-window. `keepTimers` is for the
    -- one case that is ABOUT the queue: flushing there would fire the pending timer and empty the
    -- queue whether or not the stand-down canceled anything, which is an assertion that cannot
    -- fail.
    if not keepTimers then inst.mocks.__flushTimers() end
end

--- A fresh, fully enabled instance with its baseline surveys taken.
local function baseline()
    local inst = T.load(true, true)
    inst.mocks.__flushTimers()
    local bag, n = registrations(inst)
    return inst, bag, n
end

-- ---------------------------------------------------------------------------
-- Steps 1-3: the registration set
-- ---------------------------------------------------------------------------

test("baseline: an ENABLED addon registers something worth standing down", function()
    -- Step 1. Without this every later assertion is trivially true: an addon that registers nothing
    -- when it is on passes "registers nothing when it is off" without being tested at all.
    local inst, _, n = baseline()
    assertTrue(n > 20,
        "an enabled KickCD must hold a real registration set; got " .. n)
    assertTrue(#shownFrames(inst) > 0, "and must be drawing something")
end)

test("DISABLED: the registration set is EMPTY, by count and by name", function()
    -- Step 3, and the case this whole file exists for. It is written against the mock's REGISTRY,
    -- never against a handler's return value -- a handler that early-returns is precisely the draw
    -- gate this is here to catch, and it would pass a return-value assertion happily.
    --
    -- red under: drop the `Suspend` call out of core/LifecycleSetup.lua's standDown, or make
    -- NS.RefreshEnabledHold a no-op, and this reddens with the whole 76-row set named
    local inst = baseline()
    setEnabled(inst, false)
    local _, n = registrations(inst)
    assertEqual(n, 0, "a disabled addon must be registered for NOTHING; still live: " .. survivors(inst))
end)

test("DISABLED: nothing is left armed to wake up", function()
    -- Step 4. `mocks.__timers()` CALLED is the live set -- every un-cancelled timer and ticker and
    -- every frame still carrying an OnUpdate -- rather than the pending queue, because a repeating
    -- ticker that has just fired is absent from the queue for a moment and is still very much alive.
    --
    -- The cast bar's OnUpdate and the 0.1s cooldown-text ticker are the two this addon has, and the
    -- ticker is the shape §7 calls the most expensive survivor of the lot: it wakes ten times a
    -- second to find nothing to paint.
    --
    -- ONE IS ARMED FIRST, deliberately. An addon idling in a headless harness has nothing
    -- scheduled, so "no timer is armed after disabling" would be true of a stand-down that cancels
    -- nothing at all -- an assertion that cannot fail is the draw gate wearing a different hat. A
    -- SPELL_UPDATE_COOLDOWN arms Cooldowns' coalescing throttle, which is this addon's own example
    -- of the shape the rule names: it wakes on the next frame to re-poll a spell list that is no
    -- longer being drawn.
    --
    -- red under: drop `self._cancelRefresh()` from Cooldowns:Suspend, or hand Util.Throttle back to
    -- C_Timer.After, which returns no handle and therefore cannot be canceled at all
    local inst = baseline()
    inst.mocks.__fire("SPELL_UPDATE_COOLDOWN")     -- armed, and deliberately NOT flushed
    assertTrue(#inst.mocks.__timers() > 0, "sanity: the coalescer really did arm a timer")

    setEnabled(inst, false, true)
    assertEqual(#inst.mocks.__timers(), 0, "a disabled addon must have no timer, ticker or OnUpdate armed")

    -- And nothing re-arms for the rest of the run: the events that would have are gone.
    inst.mocks.__fire("SPELL_UPDATE_COOLDOWN")
    assertEqual(#inst.mocks.__timers(), 0, "a disabled addon armed a timer after the fact")
end)

test("DISABLED: every frame that was on screen is off it", function()
    -- Step 5, and it is enforced at the SOURCE rather than by hiding: the show ladders' first rung
    -- asks the latch (NS.IsDown), so a combat transition, a target swap or a settings change cannot
    -- re-show a grid behind the switch's back. This case measures the OUTCOME; the "settings change
    -- while disabled" case further down measures that it holds afterwards.
    local inst = baseline()
    local before = shownFrames(inst)
    setEnabled(inst, false)
    for _, f in ipairs(before) do
        assertFalse(f:IsVisible(), "a frame the addon was drawing is still on screen")
    end
end)

-- ---------------------------------------------------------------------------
-- Step 6: fire everything at it anyway
-- ---------------------------------------------------------------------------

--- Fire `event` AT `target` whether or not it is still registered.
---
--- THE FALSIFICATION HALF, and it is not a convenience. `mocks.__fire` over an empty registry runs
--- nothing, so "no write, no line, no frame shown" is true of a correctly stood-down addon AND of a
--- harness that has lost the ability to dispatch at all. Firing at a target whose registration has
--- been REMOVED is what proves a survivor would have been caught: the handler is still there, it is
--- simply no longer reachable from the client, and this reaches it anyway.
---
--- Frames go through the host mock's own `_fire` rather than the kit's `__fireUnconditional`,
--- because this addon's frames keep their scripts as a LIST (HookScript stacks them) and the kit's
--- helper expects the single-function shape.
local function fireAt(inst, target, event, ...)
    if type(target) ~= "table" then return end
    if target._fire then return target:_fire(event, ...) end
    return inst.mocks.__fireUnconditional(target, event, ...)
end

test("DISABLED: firing every event it USED to watch changes nothing", function()
    -- Step 6. The client will not fire these -- nothing is registered -- but a survivor would still
    -- be reached, so they are fired at the recorded targets directly. Three things must not happen:
    -- a SavedVariables write, a line to the player, or a frame coming back on screen.
    --
    -- PLAYER_REGEN_DISABLED is in the list BY NAME, and it is the one the rule was written for: the
    -- collection's live example is an addon that writes `locked = true` and prints to chat on
    -- entering combat while it is disabled, and the player's evidence that the addon is off is the
    -- absence of exactly that line.
    --
    -- red under: leave core/State.lua's boot frame registered in standDown -- the COMBAT_STATE
    -- publish then reaches the modules and the debug line reaches chat
    local inst = baseline()
    local recorded = {}
    for _, reg in ipairs(inst.mocks.__registrationSet()) do
        recorded[#recorded + 1] = { target = reg.target, event = reg.event, unit = reg.unit }
    end
    setEnabled(inst, false)

    local before = svSnapshot(inst)
    local shownBefore = #shownFrames(inst)
    local lines = say(inst, function()
        for _, reg in ipairs(recorded) do
            fireAt(inst, reg.target, reg.event, reg.unit or "target")
        end
        -- Named explicitly, in both directions, whether or not the survey happened to carry them.
        for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
            inst.mocks.__fire(ev)
            for _, reg in ipairs(recorded) do fireAt(inst, reg.target, ev) end
        end
        inst.mocks.__flushTimers()
    end)

    local writes = svDiff(before, svSnapshot(inst))
    assertEqual(#writes, 0, "a disabled addon wrote to SavedVariables: " .. table.concat(writes, ", "))
    assertEqual(#lines, 0, "a disabled addon spoke to the player: " .. table.concat(lines, " / "))
    assertEqual(#shownFrames(inst), shownBefore, "a disabled addon put a frame back on screen")
    assertEqual(#inst.mocks.__timers(), 0, "a disabled addon armed a timer in response to an event")
    assertEqual((select(2, registrations(inst))), 0, "and it re-registered nothing")
end)

test("DISABLED: a settings change does not bring it back", function()
    -- The other half of "enforced at the source". A player who turns the addon off then goes and
    -- changes something is the ordinary case, and a CONFIG_CHANGED that reached EnableUnit would
    -- rebuild every per-unit dispatch frame on an addon that is supposed to be inert.
    --
    -- red under: restore `if NS.Perf and NS.Perf.suspended then return end` to ReconcileUnits --
    -- the perf hold is not taken here, so that guard reads false and the frames come back
    local inst = baseline()
    setEnabled(inst, false)
    local H = inst.NS.Settings.Helpers
    H.SetAndRefresh("units.focus.enabled", true)
    H.SetAndRefresh("icons.size", 40)
    inst.mocks.__flushTimers()
    assertEqual((select(2, registrations(inst))), 0,
        "a settings change re-registered a disabled addon: " .. survivors(inst))
    assertEqual(#shownFrames(inst), 0, "and it put the grid back on screen")
end)

-- ---------------------------------------------------------------------------
-- Step 7: the slash surface -- UNCHANGED, and that is the ruling
-- ---------------------------------------------------------------------------
--
-- This step is NOT the stand-down: steps 1-6 are, and a green step 7 says nothing about whether the
-- addon is inert. What it pins is the surface the standard reversed at v2.57.0 after narrowing it at
-- v2.56.0: every reserved verb answers normally while disabled and the bare `/kcd` opens the panel,
-- because a player must be able to read and repair settings, and reach the panel, while the addon is
-- off -- which is precisely when they are most likely to need to.

--- The live set: the library's twelve reserved verbs plus this addon's `spells`, TYPED here rather
--- than read off the addon, so that the two lists have to be changed together. A verb added to the
--- addon's live set and not to this one goes red; a new FEATURE verb is refused by default and
--- passes without a word.
local LIVE = {
    "help", "config", "version", "enable", "disable", "debug", "perf",
    "get", "set", "list", "reset", "resetall", "spells",
}

test("DISABLED: every reserved verb still answers, and the bare /kcd opens the panel", function()
    -- red under: passing a NARROWED `liveVerbs` in settings/Slash.lua, which is what v2.56.0 asked
    -- for and v2.57.0 reversed
    local inst = baseline()
    setEnabled(inst, false)

    for _, verb in ipairs(LIVE) do
        local lines = say(inst, function() inst.NS:OnSlashCommand(verb) end)
        if verb == "help" then
            -- `help` CARRIES the refusal line, under its header, and that is not a refusal OF help:
            -- the index prints in full, because the player has to be able to SEE `enable` in it.
            assertTrue(#lines > 5, "`/kcd help` must still print the whole index")
        else
            for _, line in ipairs(lines) do
                assertNil(line:find("is disabled", 1, true), "`/kcd " .. verb .. "` refused: " .. line)
            end
        end
    end

    -- The bare command, which is the case that settled the reversal: it opens the settings panel,
    -- the one surface a player uses to switch a disabled addon back on by hand.
    local opened, realOpen = 0, inst.NS.OpenSettings
    inst.NS.OpenSettings = function(self) opened = opened + 1; return realOpen(self) end
    say(inst, function() inst.NS:OnSlashCommand("") end)
    inst.NS.OpenSettings = realOpen
    assertEqual(opened, 1, "the bare `/kcd` must open the panel while disabled")
end)

test("DISABLED: a feature verb refuses on ONE line and reaches no write seam", function()
    -- §2's SHOULD, which this addon adopts: `lock`, `unlock`, `toggle` and `resetposition` drive the
    -- display -- unlocking IS this addon's preview (launcher-§2 rung (b)) -- and with the addon off
    -- there is no grid to unlock. Driven off NS.COMMANDS rather than a typed list, so the next verb
    -- added to the addon is covered here the day it lands.
    local inst = baseline()
    setEnabled(inst, false)
    local live = {}
    for _, verb in ipairs(LIVE) do live[verb] = true end

    local Sl = inst.mocks.LibStub("LibKa0s-Slash-1.0", true)
    local expected = Sl.DISABLED_LINE_FORMAT:format("Ka0s KickCD", "/kcd enable")

    local refused = 0
    for _, entry in ipairs(inst.NS.COMMANDS) do
        local verb = entry[1]
        if not live[verb] then
            refused = refused + 1
            local before = svSnapshot(inst)
            local lines = say(inst, function() inst.NS:OnSlashCommand(verb) end)
            assertEqual(#lines, 1, "`/kcd " .. verb .. "` must answer on exactly one line")
            assertEqual(lines[1], expected, "and it must be the collection's line, byte for byte")
            local writes = svDiff(before, svSnapshot(inst))
            assertEqual(#writes, 0, "`/kcd " .. verb .. "` wrote: " .. table.concat(writes, ", "))
        end
    end
    assertTrue(refused > 0, "sanity: this addon HAS feature verbs, so the SHOULD is testable here")
end)

-- ---------------------------------------------------------------------------
-- Step 8: the launcher
-- ---------------------------------------------------------------------------

test("DISABLED: the launcher's LEFT click is refused and writes nothing", function()
    -- launcher-§2: rung (a) and rung (b) are refused while disabled because both drive features, and
    -- KickCD is rung (b) -- the left button toggles the lock, which IS its preview switch. The
    -- rung-(c) carve-out does not reach this addon: that one opens the settings panel, which §7 keeps
    -- standing, and refusing it would decline one button for doing what the button beside it must
    -- keep doing.
    --
    -- red under: dropping the gate from core/LauncherSetup.lua's onClick -- the audit found an addon
    -- whose minimap button writes the stored tree of an addon the player switched off
    local inst = baseline()
    setEnabled(inst, false)
    local click = inst.NS.Launcher:Object().OnClick
    local before = svSnapshot(inst)
    local shownBefore = #shownFrames(inst)
    local lines = say(inst, function() click(nil, "LeftButton") end)
    local writes = svDiff(before, svSnapshot(inst))

    assertEqual(#writes, 0, "the click wrote SavedVariables: " .. table.concat(writes, ", "))
    assertEqual(#lines, 1, "the click must answer on exactly one line")
    assertTrue(lines[1]:find("/kcd enable", 1, true) ~= nil, "naming the verb that turns it back on")
    assertEqual(#shownFrames(inst), shownBefore, "and it must not have shown anything")
end)

test("DISABLED: the launcher's RIGHT click still opens the panel", function()
    -- Unchanged in either state, and deliberately not inconsistent with anything: the owner's ruling
    -- is about the slash surface, and a mouse click is not a slash command. It is also one of the two
    -- routes §7 nominates for reaching the panel of an addon that is off.
    local inst = baseline()
    setEnabled(inst, false)
    local opened, realOpen = 0, inst.NS.OpenSettings
    inst.NS.OpenSettings = function(self) opened = opened + 1; return realOpen(self) end
    say(inst, function() inst.NS.Launcher:Object().OnClick(nil, "RightButton") end)
    inst.NS.OpenSettings = realOpen
    assertEqual(opened, 1, "right-click must open the settings panel while disabled")
end)

-- ---------------------------------------------------------------------------
-- Step 9: back up, from CURRENT state
-- ---------------------------------------------------------------------------

test("RE-ENABLED: the registration set comes back, exactly", function()
    local inst, before = baseline()
    setEnabled(inst, false)
    setEnabled(inst, true)
    local after = registrations(inst)
    for name, n in pairs(before) do
        assertEqual(after[name], n, "a registration did not come back: " .. name)
    end
    for name, n in pairs(after) do
        assertEqual(before[name] or 0, n, "a registration came back that was not there: " .. name)
    end
end)

test("RE-ENABLED: it rebuilds from CURRENT state, not from a snapshot", function()
    -- performance-§6, applied to the latch in full. A setting changed while the addon was down has to
    -- be reflected when it comes back, which is why standUp rebuilds rather than replaying what was
    -- live on the way down.
    --
    -- red under: an IconGrid:Resume that restores `inst.enabled` from a snapshot instead of asking
    -- NS.Units.IsEnabled now
    local inst = baseline()
    local H = inst.NS.Settings.Helpers
    H.SetAndRefresh("units.focus.enabled", false)
    inst.mocks.__flushTimers()
    local withoutFocus = select(2, registrations(inst))

    setEnabled(inst, false)
    H.SetAndRefresh("units.focus.enabled", true)   -- changed WHILE it is off
    setEnabled(inst, true)

    local withFocus = select(2, registrations(inst))
    assertTrue(withFocus > withoutFocus,
        "the rebuilt set must reflect the setting as it is NOW: " .. withoutFocus .. " -> " .. withFocus)
end)

-- ---------------------------------------------------------------------------
-- Step 10: the latch -- two holds, and neither releases the other
-- ---------------------------------------------------------------------------

test("LATCH: releasing the perf hold does NOT resurrect a disabled addon", function()
    -- The trap §7 names, and it is reachable by a player rather than only in theory: `/kcd disable`
    -- is a LIVE verb, so it can be typed during a suspended arm, and a resume that called a bare
    -- stand-up would bring the addon back under a player who had just switched it off.
    --
    -- red under: a `StandUp()` called directly from either arm instead of release-and-re-evaluate
    local inst = baseline()
    inst.NS.Perf.Suspend()
    assertEqual((select(2, registrations(inst))), 0, "sanity: the perf hold stands it down")

    setEnabled(inst, false)                        -- now BOTH holds are taken
    inst.NS.Perf.Resume()                          -- release one
    assertEqual((select(2, registrations(inst))), 0,
        "releasing the perf hold resurrected an addon the player disabled: " .. survivors(inst))
    assertFalse(inst.NS.Perf.suspended, "and the perf hold really is released")

    setEnabled(inst, true)                         -- release the last one
    assertTrue((select(2, registrations(inst))) > 20, "and it stands up when the LAST hold goes")
end)

test("LATCH: the holds are order-independent", function()
    -- The same trap approached from the other side: disable first, suspend second, release the
    -- DISABLED hold, and the addon must stay down because the perf arm still holds it.
    --
    -- red under: a disable path that stands the addon up directly on its way out
    local inst = baseline()
    setEnabled(inst, false)
    inst.NS.Perf.Suspend()
    setEnabled(inst, true)
    assertEqual((select(2, registrations(inst))), 0,
        "enabling mid-capture resurrected a suspended addon: " .. survivors(inst))
    assertTrue(inst.NS.Perf.suspended, "sanity: the perf hold is still taken")

    inst.NS.Perf.Resume()
    assertTrue((select(2, registrations(inst))) > 20, "and it comes back when the capture ends")
end)

test("LATCH: a profile switch that flips `enabled` is honored", function()
    -- §7 keeps AceDB's profile callbacks alive for exactly this: `enabled` is a stored setting like
    -- any other, and a profile switch can flip it with no checkbox ticked and no verb typed.
    --
    -- Driven through the db's own reset, which is the one profile event this addon's mock models
    -- end to end: with `enabled` stored false, a reset restores the default (true) and the addon
    -- must stand back up off the callback alone.
    local inst = baseline()
    setEnabled(inst, false)
    assertEqual((select(2, registrations(inst))), 0, "sanity: it is down")

    inst.NS.db.ResetProfile()
    inst.mocks.__flushTimers()
    assertTrue(inst.NS.db.profile.enabled ~= false, "sanity: the reset restored the default")
    assertTrue((select(2, registrations(inst))) > 20,
        "a profile event that re-enabled the addon left it stood down")
end)
