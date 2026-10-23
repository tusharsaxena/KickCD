-- tests/test_sim_e2e.lua — KickCD#38's four scenarios, end to end on the REAL engine (KC-08).
--
-- OWNER_SCOPE B4 takes #38's scenario list as scope, each with a headless end-to-end suite. Each
-- case starts a scenario of modules/SimScenario.lua with the member NS.Sim:Start{scenario, seed}
-- (nothing plays: Sim-1.0's members arm no run), plays every step with NS.Sim:Step(), draining
-- the zero-delay ticks after each one (the Cooldowns refresh coalesces to the next frame), and
-- asserts after the named steps what the real engine produced: NS.State, Cooldowns:StateFor, the
-- cast bars' instances, the icon grids, and the handlers the deliveries reached. The clock never
-- moves past a step, so the story's cooldowns hold for the whole run. One more case plays a
-- scenario on the auto-run a typed `/kcd sim start` arms.
--
-- Every case also asserts the session's end: FINISHED printed on the last step, KickCDDB byte for
-- byte as it was before the start (H4), and no live timer once the session stops. And every
-- scenario's timeline is pure: two calls answer equal step lists and fire nothing.
--
-- The client is tests/sim_support.lua's Enhancement Shaman: Wind Shear (57994) is "your kick",
-- Capacitor Totem (192058) "your CC", and Hex (51514) is a further on-GCD spell. Every case builds
-- its own environment (tests/sim_support.lua says why).

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

local KICK, CC = S.KICK, S.CC

--- Deep equality of two plain tables (SavedVariables and step shapes: no cycles).
local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function canceled(t) return t.cancelled or (t.timer and t.timer.cancelled) end

--- The timers still live on the kit's queue, after the stop's zero-delay re-sync has drained and one
--- tick of the grid's shared 0.1 s cooldown ticker has passed: that ticker is the engine's own and
--- cancels itself lazily on the first fire that finds no icon cooling (modules/IconGrid_Ticker.lua),
--- so a live timer after it is one the session left behind, or an icon still cooling on real data.
local function liveTimers(env)
    env.advance(0)
    env.advance(0.2)
    local mocks = env.mocks
    local n = 0
    for _, t in ipairs(mocks.__timers) do if not canceled(t) then n = n + 1 end end
    return n
end

--- A fresh, locked environment with the clock off zero, NS.DeliverEvent spied (the real dispatch
--- still runs) and NS.Util.print captured. ctx = { env, NS, L, events, lines, delivered(event[, unit]),
--- said(line), bar(unit), grid(unit), state(id), spy(target, method) -> calls }.
local function fresh(profile)
    local env = S.load()
    env.advance(100)
    local NS = env.NS
    NS.db.profile.locked = true
    for k, v in pairs(profile or {}) do NS.db.profile[k] = v end
    local ctx = { env = env, NS = NS, L = NS.L, events = {}, lines = {} }
    local realDeliver = NS.DeliverEvent
    NS.DeliverEvent = function(event, ...)
        local rec = { event = event, unit = (...) }
        ctx.events[#ctx.events + 1] = rec
        rec.handlers = realDeliver(event, ...)
        return rec.handlers
    end
    NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        ctx.lines[#ctx.lines + 1] = table.concat(parts, " ")
    end
    function ctx.delivered(event, unit, from)
        for i = from or 1, #ctx.events do
            local e = ctx.events[i]
            if e.event == event and (unit == nil or e.unit == unit) then return e end
        end
        return nil
    end
    function ctx.said(line)
        for _, l in ipairs(ctx.lines) do if l == line then return true end end
        return false
    end
    function ctx.simLine(fmt, ...) return NS.L["[sim] %s"]:format(NS.L[fmt]:format(...)) end
    function ctx.bar(unit) return NS:GetModule("Castbar"):GetInstance(unit) end
    function ctx.grid(unit) return NS:GetModule("IconGrid"):GetGridFrame(unit) end
    function ctx.state(id) return NS:GetModule("Cooldowns"):StateFor(id) end
    function ctx.spy(target, method)
        local calls, real = {}, target[method]
        target[method] = function(...)
            calls[#calls + 1] = { select(2, ...) }
            return real(...)
        end
        return calls
    end
    return ctx
end

--- The library's FINISHED line, as the host prints it.
local function finishedLine(ctx)
    local lib = ctx.env.mocks.LibStub("LibKa0s-Sim-1.0")
    return lib.STRINGS.FINISHED:format("/kcd sim")
end

--- The scenario's step list, from its own timeline (what the panel previews while idle).
local function timelineOf(ctx, name)
    local def = ctx.NS.SimHost.SCENARIOS.defs[name]
    return def.timeline(def, { scenario = name, seed = 0 })
end

--- Index of the first step of `kind` (the `nth` one) in `steps`, so a check names its step.
local function nth(steps, kind, n)
    local seen = 0
    for i, s in ipairs(steps) do
        if s.kind == kind then
            seen = seen + 1
            if seen == (n or 1) then return i end
        end
    end
    error("no step " .. kind .. " #" .. tostring(n or 1))
end

--- Play scenario `name` step by step. `checks(steps)` answers { [index] = fn(ctx, step, from) },
--- where `from` is the first event index the step delivered. Then the session's end: FINISHED,
--- the stop, KickCDDB unchanged, no live timer.
local function play(ctx, name, checks)
    local NS, env = ctx.NS, ctx.env
    local before = env.snapshotDB()
    local ok, line = NS.Sim:Start{ scenario = name, seed = 0 }
    assertTrue(ok, name .. " did not start: " .. tostring(line))
    env.advance(0)
    local steps = NS.Sim:Steps()
    assertTrue(#steps > 0, name .. " has no steps")
    local byIndex = checks(steps)
    for i = 1, #steps do
        local from = #ctx.events + 1
        local played = NS.Sim:Step()
        assertTrue(played ~= nil, ("%s step %d did not play"):format(name, i))
        env.advance(0)
        assertTrue(played.detail ~= nil, ("%s step %d has no detail"):format(name, i))
        if byIndex[i] then byIndex[i](ctx, played, from) end
    end
    assertEqual(ctx.lines[#ctx.lines], finishedLine(ctx), name .. ": FINISHED is the last line")
    NS.Sim:Stop()
    env.advance(0)
    assertFalse(NS.Sim:IsActive())
    assertTrue(deepEqual(before, env.snapshotDB()), name .. ": the session changed KickCDDB")
    assertEqual(liveTimers(env), 0, name .. ": a timer outlived the session")
end

-- ── the module ──────────────────────────────────────────────────────────────

test("SimScenario: the four #38 scenarios fill NS.SimHost.SCENARIOS in order, each labeled", function()
    local ctx = fresh()
    local NS = ctx.NS
    local sc = NS.SimHost.SCENARIOS
    assertEqual(table.concat(sc.names, ","), "pull,boss,miss,leave")
    assertEqual(sc.defs.pull.label, NS.L["Mythic+ pull, several kickers"])
    assertEqual(sc.defs.boss.label, NS.L["Boss kick rotation"])
    assertEqual(sc.defs.miss.label, NS.L["Kick on cooldown, uninterruptible cast"])
    assertEqual(sc.defs.leave.label, NS.L["Party member leaves mid-pull"])
    local P = NS.SimScenario.PARTY
    assertEqual(P.thrall.spell, 57994); assertEqual(P.jaina.spell, 2139)
    assertEqual(P.uther.spell, 96231); assertEqual(P.valeera.spell, 1766)
    assertEqual(P.jaina.name, NS.L["Jaina"]); assertEqual(P.jaina.spec, NS.L["Frost"])
    for _, key in ipairs({ "casterA", "casterB", "boss" }) do
        local e = NS.SimScenario.ENEMIES[key]
        assertTrue(type(e.name) == "string" and type(e.cast) == "number" and type(e.channel) == "number", key)
    end
end)

test("TOC: modules/SimScenario.lua loads straight after modules/Sim.lua, under a LOAD-BEARING comment", function()
    local at
    for i, rel in ipairs(T.tocFiles) do if rel == "modules/SimScenario.lua" then at = i end end
    assertTrue(at ~= nil, "modules/SimScenario.lua is not in KickCD.toc")
    assertEqual(T.tocFiles[at - 1], "modules/Sim.lua")
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local prev, found
    for line in fh:lines() do
        line = line:gsub("\r$", "")
        if line == "modules\\SimScenario.lua" then found = prev end
        if line:sub(1, 1) == "#" then prev = prev or line else prev = nil end
    end
    fh:close()
    assertTrue(found ~= nil and found:find("^# LOAD%-BEARING") ~= nil,
        "the comment block above modules\\SimScenario.lua must open '# LOAD-BEARING'")
end)

test("SimScenario: every timeline is pure: two calls answer equal steps and fire nothing", function()
    local ctx = fresh()
    local NS = ctx.NS
    for _, name in ipairs({ "pull", "boss", "miss", "leave" }) do
        local a, b = timelineOf(ctx, name), timelineOf(ctx, name)
        assertTrue(#a > 0, name .. " is empty")
        assertTrue(a ~= b and a[1] ~= b[1], name .. " shares its tables between calls")
        assertTrue(deepEqual(a, b), name .. ": two calls differ")
        for i, step in ipairs(a) do
            assertTrue(type(NS.SimDrivers.DRIVERS[step.kind]) == "function",
                ("%s step %d: no driver for %s"):format(name, i, tostring(step.kind)))
            assertTrue(type(step.label) == "string" and step.label ~= "", ("%s step %d has no label"):format(name, i))
        end
    end
    assertEqual(#ctx.events, 0, "a timeline fired an event")
    assertEqual(#ctx.lines, 0, "a timeline printed")
    assertNil(NS.SimHost.world, "a timeline built a world")
end)

test("SimScenario: the panel's idle preview lists exactly the first scenario's step labels", function()
    local ctx = fresh()
    local NS = ctx.NS
    local steps = timelineOf(ctx, "pull")
    local rows = NS.Sim:PanelRows()
    assertEqual(#rows, #steps + 2)
    for i, step in ipairs(steps) do assertEqual(rows[i + 1].label, step.label, "row " .. i) end
end)

-- ── pull: Mythic+ pull, several kickers ─────────────────────────────────────

test("Sim e2e pull: combat, both bars, your kick, the party's kicks, the CC's GCD, a death", function()
    local ctx = fresh({ visibility = "target_casting" })
    local NS = ctx.NS
    local IconGrid = NS:GetModule("IconGrid")
    local spellStates = ctx.spy(IconGrid, "OnSpellState")
    play(ctx, "pull", function(steps)
        local c = {}
        c[1] = function() assertTrue(NS.State.inCombat, "the pull did not enter combat") end
        c[nth(steps, "CastStart", 1)] = function()
            assertTrue(ctx.bar("target").current ~= nil, "the target bar shows no cast")
            assertTrue(ctx.grid("target"):IsShown(), "target_casting did not show the target grid")
        end
        c[nth(steps, "Kick", 1)] = function()
            assertTrue(ctx.state(KICK).isActive, "your kick is not cooling")
            assertNil(ctx.bar("target").current, "the kicked cast is still on the bar")
            assertTrue(#spellStates > 0, "no SPELL_STATE reached IconGrid:OnSpellState")
        end
        c[nth(steps, "ChannelStart", 1)] = function()
            local cur = ctx.bar("focus").current
            assertTrue(cur ~= nil and cur.isChannel == true, "the focus bar shows no channel")
        end
        c[nth(steps, "PartyKick", 1)] = function()
            assertNil(ctx.bar("focus").current, "Thrall's kick left the focus bar running")
        end
        c[nth(steps, "PartyKick", 2)] = function()
            assertTrue(ctx.state(KICK).isActive, "your kick came back too soon")
            assertTrue(ctx.said(ctx.simLine("%s (%s) interrupts %s with %s.", NS.L["Jaina"], NS.L["Frost"],
                NS.L["Shadowcaster"], (NS.Compat.GetSpellInfo(2139)))), "Jaina's line was not printed")
        end
        c[nth(steps, "Cc")] = function()
            assertTrue(ctx.state(CC).isActive, "the CC is not cooling")
            local others = 0
            for id, st in pairs(NS:GetModule("Cooldowns").watched) do
                if id ~= KICK and id ~= CC then
                    others = others + 1
                    assertTrue(st.isActive, "spell " .. id .. " shows no GCD")
                    assertEqual(st.cdObject:GetTotalDuration(), 1.5, "spell " .. id .. "'s GCD")
                end
            end
            assertTrue(others >= 1, "no other on-GCD spell is watched")
        end
        c[nth(steps, "Die")] = function()
            assertFalse(NS.Compat.UnitExists("target"), "the dead target is still targeted")
            assertNil(ctx.bar("target").current, "the target bar still runs")
        end
        c[#steps] = function() assertFalse(NS.State.inCombat, "the pull did not end combat") end
        return c
    end)
end)

-- ── boss: boss kick rotation, two charges ───────────────────────────────────

test("Sim e2e boss: your kick's charges go 2 -> 1 -> 0, and the expire step brings both back", function()
    local ctx = fresh()
    play(ctx, "boss", function(steps)
        local c = {}
        c[nth(steps, "Setup")] = function(_, _, from)
            assertTrue(ctx.delivered("SPELL_UPDATE_CHARGES", nil, from) ~= nil, "Setup fired no charges update")
            assertEqual(ctx.state(KICK).charges, 2)
        end
        c[nth(steps, "Kick", 1)] = function()
            assertEqual(ctx.state(KICK).charges, 1)
            assertFalse(ctx.state(KICK).isActive, "a charge is left, so the kick is not locked")
        end
        c[nth(steps, "Kick", 2)] = function()
            assertEqual(ctx.state(KICK).charges, 0)
            assertTrue(ctx.state(KICK).isActive, "no charge left, yet the kick is not locked")
        end
        c[nth(steps, "Expire")] = function()
            assertEqual(ctx.state(KICK).charges, 2)
            assertFalse(ctx.state(KICK).isActive)
        end
        c[nth(steps, "Kick", 3)] = function()
            assertEqual(ctx.state(KICK).charges, 1)
            assertNil(ctx.bar("target").current, "the fifth cast was not kicked")
        end
        return c
    end)
end)

-- ── miss: kick on cooldown, uninterruptible cast ────────────────────────────

test("Sim e2e miss: the shield refuses a kick, breaks, the kick lands, the next cast completes", function()
    local ctx = fresh()
    local NS = ctx.NS
    local Castbar = NS:GetModule("Castbar")
    local flips = ctx.spy(Castbar, "OnInterruptibilityChanged")
    play(ctx, "miss", function(steps)
        local c = {}
        c[nth(steps, "CastStart", 1)] = function()
            local cur = ctx.bar("target").current
            assertTrue(cur ~= nil and cur.notInterruptible == true, "the cast is not uninterruptible")
        end
        c[nth(steps, "Kick", 1)] = function(_, _, from)
            assertEqual(#ctx.events, from - 1, "a refused kick fired an event")
            assertTrue(ctx.bar("target").current ~= nil, "the shielded cast ended")
        end
        c[nth(steps, "Interruptible")] = function()
            assertEqual(#flips, 1, "Castbar:OnInterruptibilityChanged did not run")
            assertEqual(flips[1][1], "UNIT_SPELLCAST_INTERRUPTIBLE")
            assertEqual(flips[1][2], "target")
        end
        c[nth(steps, "Kick", 2)] = function()
            assertTrue(ctx.state(KICK).isActive, "the kick did not land")
            assertNil(ctx.bar("target").current, "the kicked cast is still on the bar")
        end
        c[nth(steps, "Kick", 3)] = function(_, played, from)
            assertEqual(#ctx.events, from - 1, "a kick on cooldown fired an event")
            assertEqual(played.detail, NS.L["on cooldown"])
        end
        c[nth(steps, "Complete")] = function(_, _, from)
            assertTrue(ctx.delivered("UNIT_SPELLCAST_SUCCEEDED", "target", from) ~= nil, "the cast did not complete")
            assertNil(ctx.bar("target").current)
        end
        c[nth(steps, "Expire")] = function()
            assertFalse(ctx.state(KICK).isActive, "the kick did not come back")
        end
        return c
    end)
end)

-- ── leave: party member leaves mid-pull ─────────────────────────────────────

test("Sim e2e leave: the roster update reaches no handler; the target swap snaps onto the cast", function()
    local ctx = fresh()
    local NS = ctx.NS
    local Castbar = NS:GetModule("Castbar")
    local reevaluated = ctx.spy(Castbar, "Reevaluate")
    play(ctx, "leave", function(steps)
        local c = {}
        c[nth(steps, "Leave")] = function(_, played, from)
            local e = ctx.delivered("GROUP_ROSTER_UPDATE", nil, from)
            assertTrue(e ~= nil, "GROUP_ROSTER_UPDATE was not delivered")
            assertEqual(e.handlers, 0)
            assertEqual(played.detail, NS.L["%s left"]:format(NS.L["Valeera"]))
            assertTrue(NS.Sim:IsActive(), "the simulated roster update stopped the session")
        end
        c[nth(steps, "Focus", 2)] = function()
            assertFalse(NS.Compat.UnitExists("focus"), "the focus was not cleared")
            assertNil(ctx.bar("focus").current)
        end
        c[nth(steps, "Target", 2)] = function()
            assertTrue(#reevaluated > 0, "the target swap did not reach Castbar:Reevaluate")
            local cur = ctx.bar("target").current
            assertTrue(cur ~= nil, "the target bar did not snap onto the cast in progress")
            assertEqual(cur.spellID, NS.SimScenario.ENEMIES.casterB.cast)
        end
        c[nth(steps, "Kick")] = function()
            assertTrue(ctx.state(KICK).isActive, "your kick did not land")
            assertNil(ctx.bar("target").current, "the kicked cast is still on the bar")
        end
        return c
    end)
end)

-- ── the auto-run a typed start arms (LibKa0s v1.76.0, LK-01) ────────────────

test("Sim e2e auto-run: `start pull` plays every step at the step delay, then FINISHED", function()
    local ctx = fresh()
    local NS, env = ctx.NS, ctx.env
    local before = env.snapshotDB()
    local ok = NS.Sim:RunVerb("start pull")
    assertTrue(ok, "the typed start was refused: " .. table.concat(ctx.lines, " || "))
    local finished = finishedLine(ctx)
    for _ = 1, 40 do
        if ctx.said(finished) then break end
        env.advance(NS.SimHost.STEP_DELAY)
    end
    assertTrue(ctx.said(finished), "the auto-run never finished")
    for i, step in ipairs(NS.Sim:Steps()) do assertTrue(step.ranAt ~= nil, "step " .. i .. " never played") end
    assertFalse(NS.State.inCombat, "the pull did not end combat")
    NS.Sim:Stop()
    env.advance(0)
    assertTrue(deepEqual(before, env.snapshotDB()), "the session changed KickCDDB")
    assertEqual(liveTimers(env), 0, "a timer outlived the session")
end)
