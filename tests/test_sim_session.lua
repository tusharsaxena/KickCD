-- tests/test_sim_session.lua — the simulator's session host (modules/Sim.lua) on LibKa0s-Sim-1.0.
--
-- KC-05 (KickCD#38; the Sim major's host contract H4, H5 and H10; OWNER_SCOPE B4). modules/Sim.lua
-- binds NS.SimSeam to one session with Sim:New and owns every world rule the library leaves to its
-- host: the refusals and their order, the world it prepares, the stop that re-syncs the REAL engine
-- with the seam off, and the step panel's presentation. These cases drive the addon's own NS.Sim on
-- the `test` scenario tests/sim_support.lua injects into NS.SimHost.SCENARIOS, with the host's real
-- Prepare, Refusal and Play (`host = true`).
--
-- Every case builds its own environment: a session binds its seam for good, and a world or a
-- swapped hook left on the shared T.NS would answer for every suite after this one.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

local KICK, CC = S.KICK, S.CC

--- Every line NS.Util.print emits while `fn` runs, on `ns`.
local function said(ns, fn)
    local lines, real = {}, ns.Util.print
    ns.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    ns.Util.print = real
    if not ok then error(err, 0) end
    return lines
end

--- A fresh environment with the `test` scenario injected (not started), the grids locked and the
--- clock moved off zero. `steps` defaults to one Noop step.
local function ready(steps, opts)
    local env = S.load(opts)
    env.advance(100)
    env.NS.db.profile.locked = true
    S.testSession(env, steps or { { kind = "Noop", label = "Noop" } }, { host = true, start = false })
    return env
end

--- Start the `test` scenario; answers ok, the answered line, and the lines printed.
local function start(env)
    local ok, line
    local lines = said(env.NS, function() ok, line = env.NS.Sim:Start{ scenario = "test" } end)
    return ok, line, lines
end

--- A Noop driver for the steps these cases play (modules/SimDrivers.lua lands in KC-07).
local function withNoopDriver(NS)
    NS.SimDrivers = NS.SimDrivers or { DRIVERS = {}, EVENTS = {} }
    NS.SimDrivers.DRIVERS.Noop = function() return "noop" end
end

--- Deep equality of two plain tables (SavedVariables shapes: no functions, no cycles).
local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- ── the module ──────────────────────────────────────────────────────────────

test("TOC: modules/Sim.lua loads straight after modules/SimDrivers.lua, under a LOAD-BEARING comment", function()
    local at
    for i, rel in ipairs(T.tocFiles) do if rel == "modules/SimDrivers.lua" then at = i end end
    assertTrue(at ~= nil, "modules/SimDrivers.lua is not in KickCD.toc")
    assertEqual(T.tocFiles[at + 1], "modules/Sim.lua")
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local prev, found
    for line in fh:lines() do
        line = line:gsub("\r$", "")
        if line == "modules\\Sim.lua" then found = prev end
        if line:sub(1, 1) == "#" then prev = prev or line else prev = nil end
    end
    fh:close()
    assertTrue(found ~= nil and found:find("^# LOAD%-BEARING") ~= nil,
        "the comment block above modules\\Sim.lua must open '# LOAD-BEARING'")
end)

test("Sim session: NS.Sim is the live instance bound to NS.SimSeam, not core/SimSetup.lua's stub", function()
    local env = ready()
    local NS = env.NS
    assertEqual(NS.Sim:Status().active, false)
    local ok = start(env)
    assertTrue(ok, "the live instance did not start")
    assertTrue(NS.Sim:IsActive())
    NS.Sim:Stop()
end)

-- ── 1. the refusals, in order (H5) ──────────────────────────────────────────

-- Each condition, set on a fresh environment, and the line it must refuse with. In CHECKS order.
local function conditions(env)
    local NS, mocks, L = env.NS, env.mocks, env.NS.L
    return {
        { "stood down", function() NS.IsDown = function() return true end end,
            function() return NS.Slash.cli:DisabledLine() end },
        { "perf", function() NS.Perf.on = true end,
            function() return L["A performance capture is running: finish it first (/kcd perf finish)."] end },
        { "unlocked", function() NS.db.profile.locked = false end,
            function() return L["Lock the grids first (/kcd lock): unlocking is KickCD's preview."] end },
        { "combat", function() NS.State.inCombat = true end,
            function() return L["A simulation cannot start in combat."] end },
        { "instance", function() mocks.__context.inInstance = true end,
            function() return L["A simulation cannot start in an instance."] end },
        { "group", function() mocks.__context.inGroup = true end,
            function() return L["A simulation cannot start in a group."] end },
        { "units", function()
                NS.db.profile.units.target.enabled = false
                NS.db.profile.units.focus.enabled = false
            end,
            function() return L["Enable the Target or the Focus grid first: the simulation plays on them."] end },
        { "no spell", function() NS.db.profile.spells.SHAMAN[S.ENHANCEMENT] = {} end,
            function()
                return L["Your current spec tracks no spell you can use: add one with /kcd spells add, then start again."]
            end },
        { "no durations", function() NS.SimWorld.CanBuild = function() return false end end,
            function() return L["This client cannot build simulated cooldowns, so the simulator cannot run."] end },
    }
end

--- Assert a refused start: false, exactly `line`, printed exactly once, and nothing built.
local function assertRefused(env, line, what)
    local NS = env.NS
    local Cooldowns = NS:GetModule("Cooldowns")
    local rebuilds, real = 0, Cooldowns.Rebuild
    Cooldowns.Rebuild = function(...) rebuilds = rebuilds + 1; return real(...) end
    local ok, answered, lines = start(env)
    Cooldowns.Rebuild = real
    assertFalse(ok, what .. ": the session started")
    assertEqual(answered, line, what .. ": the answered line")
    assertEqual(table.concat(lines, "\n"), line, what .. ": the printed lines")
    assertFalse(NS.Sim:IsActive(), what .. ": the session is active")
    assertNil(NS.SimHost.world, what .. ": a world was built")
    assertNil(NS.SimHost.kick, what .. ": the spells were resolved")
    assertEqual(rebuilds, 0, what .. ": the engine was rebuilt")
end

test("Sim refusals: each condition alone refuses with exactly its line and builds nothing", function()
    for i = 1, 9 do
        local env = ready()
        local c = conditions(env)[i]
        c[2]()
        assertRefused(env, c[3](), c[1])
    end
end)

test("Sim refusals: InCombatLockdown alone refuses as combat", function()
    local env = ready()
    env.mocks.InCombatLockdown = function() return true end
    assertRefused(env, env.NS.L["A simulation cannot start in combat."], "combat lockdown")
end)

test("Sim refusals: with every condition set they refuse in CHECKS order, one by one", function()
    -- red under: two checks swapped, or a check reading the simulated world rather than Live's
    local env = ready()
    local list = conditions(env)
    local NS, mocks = env.NS, env.mocks
    local savedList = NS.db.profile.spells.SHAMAN[S.ENHANCEMENT]
    local lines = {}
    for _, c in ipairs(list) do c[2](); lines[#lines + 1] = c[3]() end
    -- Stood down WHILE a perf capture runs: the capture holds the latch, so check 1 names it.
    lines[1] = lines[2]
    local undo = {
        function() NS.IsDown = function() return false end end,
        function() NS.Perf.on = false end,
        function() NS.db.profile.locked = true end,
        function() NS.State.inCombat = false end,
        function() mocks.__context.inInstance = false end,
        function() mocks.__context.inGroup = false end,
        function() NS.db.profile.units.target.enabled = true end,
        function() NS.db.profile.spells.SHAMAN[S.ENHANCEMENT] = savedList end,
    }
    for i = 1, #list do
        assertRefused(env, lines[i], list[i][1] .. " (in order)")
        if undo[i] then undo[i]() end
    end
end)

test("Sim refusals: the library refuses an unknown scenario and a second session first", function()
    local env = ready()
    local NS = env.NS
    local lines = said(NS, function() NS.Sim:Start{ scenario = "nope" } end)
    assertTrue(#lines == 1 and lines[1]:find("nope", 1, true) ~= nil, table.concat(lines, " || "))
    assertTrue(start(env))
    NS.State.inCombat = true
    local ok, line = start(env)
    assertFalse(ok)
    assertTrue(line ~= NS.L["A simulation cannot start in combat."], "the host refusal ran before ALREADY_RUNNING")
    NS.State.inCombat = false
    NS.Sim:Stop()
end)

test("Host.ResolveSpells: the first watched interrupt is the kick, the first other kept spell the CC", function()
    local env = ready()
    local Host = env.NS.SimHost
    local kick, cc = Host.ResolveSpells()
    assertEqual(kick, KICK)
    assertEqual(cc, CC)
    -- A disabled interrupt is skipped: the kick falls back to the first kept entry.
    for _, e in ipairs(env.NS.db.profile.spells.SHAMAN[S.ENHANCEMENT]) do
        if e.spellID == KICK or e.id == KICK then e.enabled = false end
    end
    kick, cc = Host.ResolveSpells()
    assertTrue(kick ~= KICK and kick ~= nil, "a disabled kick was kept")
    assertTrue(cc ~= kick, "the CC is the kick")
end)

-- ── 2. a good start ─────────────────────────────────────────────────────────

test("Sim start: STARTED, the engine rebuilt on the world, the spells resolved, the panel asked, ready", function()
    local env = ready()
    local NS = env.NS
    local Cooldowns = NS:GetModule("Cooldowns")
    local rebuilds, realRebuild = 0, Cooldowns.Rebuild
    Cooldowns.Rebuild = function(...) rebuilds = rebuilds + 1; return realRebuild(...) end
    local shown, realShow = 0, NS.Sim.ShowPanel
    NS.Sim.ShowPanel = function(...) shown = shown + 1; return realShow(...) end
    local ok, _, lines = start(env)
    Cooldowns.Rebuild, NS.Sim.ShowPanel = realRebuild, realShow
    assertTrue(ok, "the session did not start: " .. table.concat(lines, " || "))
    assertEqual(lines[1], NS.L["Simulation started (%s): nothing is cast, nothing is saved, and your settings are not touched."]:format("Test"))
    assertTrue(rebuilds >= 1, "Cooldowns:Rebuild did not run")
    assertTrue(type(NS.SimHost.world) == "table", "no world was built")
    assertEqual(NS.SimHost.kick, KICK)
    assertEqual(NS.SimHost.cc, CC)
    assertTrue(NS.SimHost.world.spells[KICK] and NS.SimHost.world.spells[KICK].offGcd == true,
        "the kick was not marked off the GCD")
    local watched = 0
    for id, st in pairs(Cooldowns.watched or {}) do
        watched = watched + 1
        assertEqual(st.isActive, false, "spell " .. tostring(id) .. " is not ready in the world")
    end
    assertTrue(watched >= 2, "the engine watches nothing")
    assertEqual(shown, 1, "the panel was not asked to show")
    assertTrue(NS.Sim:Status().ready, "ready() was not called")
    NS.Sim:Stop()
end)

-- ── 3. deliver is NS.DeliverEvent ───────────────────────────────────────────

test("Sim deliver: NS.Sim:Fire('SPELL_UPDATE_COOLDOWN') runs Cooldowns' handler", function()
    local env = ready()
    local NS = env.NS
    assertTrue(start(env))
    local Cooldowns = NS:GetModule("Cooldowns")
    local calls, real = 0, Cooldowns.OnCooldownEvent
    Cooldowns.OnCooldownEvent = function(...) calls = calls + 1; return real(...) end
    local n = NS.Sim:Fire("SPELL_UPDATE_COOLDOWN")
    Cooldowns.OnCooldownEvent = real
    assertTrue(n >= 1, "nothing was delivered")
    assertEqual(calls, 1)
    NS.Sim:Stop()
end)

-- ── 4. the stop re-syncs the real engine ────────────────────────────────────

--- Spy NS.DeliverEvent: each event with whether the seam answered live inside it (the world has a
--- target the real client does not).
local function spyCleanup(NS)
    local seen, real = {}, NS.DeliverEvent
    NS.DeliverEvent = function(event, ...)
        seen[#seen + 1] = { event = event, live = (NS.Compat.UnitExists("target") == false) }
        return real(event, ...)
    end
    return seen, function() NS.DeliverEvent = real end
end

local function find(seen, event)
    for _, s in ipairs(seen) do if s.event == event then return s end end
end

test("Sim stop: the world dropped, combat cleared, and the engine re-synced with the seam OFF", function()
    local env = ready()
    local NS = env.NS
    env.mocks.UnitExists = function() return false end
    assertTrue(start(env))
    NS.SimWorld.SetUnit("target", "casterA")
    assertEqual(NS.Compat.UnitExists("target"), true, "sanity: the world answers the target")
    NS.Sim:Fire("PLAYER_REGEN_DISABLED")
    NS.Sim:Session().simCombat = true
    assertTrue(NS.State.inCombat, "sanity: simulated combat set the engine's flag")
    local seen, restore = spyCleanup(NS)
    NS.Sim:Stop()
    restore()
    assertNil(NS.SimHost.world)
    assertNil(NS.SimHost.kick)
    assertFalse(NS.State.inCombat, "the simulated combat outlived the session")
    for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "SPELL_UPDATE_COOLDOWN",
            "SPELL_UPDATE_CHARGES", "PLAYER_REGEN_ENABLED" }) do
        local s = find(seen, ev)
        assertTrue(s ~= nil, ev .. " was not delivered at cleanup")
        assertTrue(s.live, ev .. " was delivered while the seam still answered")
    end
end)

test("Sim stop: reason `combat` with simulated combat delivers NO PLAYER_REGEN_ENABLED", function()
    local env = ready()
    local NS = env.NS
    assertTrue(start(env))
    NS.Sim:Session().simCombat = true
    local seen, restore = spyCleanup(NS)
    NS.Sim:Stop("combat")
    restore()
    assertNil(find(seen, "PLAYER_REGEN_ENABLED"), "a real combat was ended by the cleanup")
    assertTrue(find(seen, "SPELL_UPDATE_COOLDOWN") ~= nil, "the rest of the cleanup did not run")
end)

test("Sim stop: no simulated combat, no PLAYER_REGEN_ENABLED", function()
    local env = ready()
    local NS = env.NS
    assertTrue(start(env))
    local seen, restore = spyCleanup(NS)
    NS.Sim:Stop()
    restore()
    assertNil(find(seen, "PLAYER_REGEN_ENABLED"))
end)

-- ── 5. saved data stays untouched (H4) ──────────────────────────────────────

test("Sim saved data: KickCDDB is identical before a start and after a start, a step and a stop", function()
    local env = ready()
    local NS = env.NS
    withNoopDriver(NS)
    local before = env.snapshotDB()
    assertTrue(start(env))
    local step = NS.Sim:Step()
    assertTrue(step ~= nil, "the step did not play")
    assertEqual(step.detail, "noop")
    NS.Sim:Stop()
    env.flush()
    assertTrue(deepEqual(before, env.snapshotDB()), "the session changed KickCDDB")
end)

test("Host.Play: an unknown step kind raises a clear error, and the run pauses", function()
    local env = ready({ { kind = "Nope" } })
    local NS = env.NS
    assertTrue(start(env))
    local lines = said(NS, function() NS.Sim:Step() end)
    assertTrue(#lines >= 1, "no STEP_FAILED line")
    local ok, err = pcall(NS.SimHost.Play, { kind = "Nope" })
    assertFalse(ok)
    assertTrue(tostring(err):find("Nope", 1, true) ~= nil, tostring(err))
    NS.Sim:Stop()
end)

-- ── 6. the panel's presentation ─────────────────────────────────────────────

test("Sim panel: PanelRows while idle previews the first scenario's steps", function()
    local env = ready({ { kind = "Noop", label = "One" }, { kind = "Noop", label = "Two" } })
    local NS = env.NS
    local Host = NS.SimHost
    local first = Host.SCENARIOS.names[1]
    local def = Host.SCENARIOS.defs[first]
    local preview = def.timeline(def, { scenario = first, seed = 0 })
    local rows = NS.Sim:PanelRows()
    assertEqual(#rows, #preview + 2)
    assertEqual(rows[1].key, "start")
    for i, step in ipairs(preview) do
        assertEqual(rows[i + 1].label, Host.PANEL.stepLabel(step, i, preview))
    end
    assertEqual(rows[#rows].key, "stop")
end)

test("Sim panel: stepLabel names `your kick` by the real spell while running, the role word idle", function()
    local env = ready()
    local NS = env.NS
    local L = NS.L
    local Host = NS.SimHost
    local step = { kind = "Kick", label = "Interrupt Caster A with " .. L["your kick"] }
    assertEqual(Host.PANEL.stepLabel(step, 1, { step }), "Interrupt Caster A with " .. L["your kick"])
    local cc = { kind = "Cc", label = "Stun Caster A with " .. L["your CC"] }
    assertEqual(Host.PANEL.stepLabel(cc, 1, { cc }), "Stun Caster A with " .. L["your CC"])
    assertTrue(start(env))
    local kickName = NS.Compat.GetSpellInfo(KICK)
    local ccName = NS.Compat.GetSpellInfo(CC)
    assertEqual(Host.PANEL.stepLabel(step, 1, { step }), "Interrupt Caster A with " .. kickName)
    assertEqual(Host.PANEL.stepLabel(cc, 1, { cc }), "Stun Caster A with " .. ccName)
    NS.Sim:Stop()
    assertEqual(Host.PANEL.stepLabel(step, 1, { step }), "Interrupt Caster A with " .. L["your kick"])
end)

test("Sim panel: stepTip names the events, the engine and, once played, the detail", function()
    local env = ready()
    local NS = env.NS
    local L = NS.L
    NS.SimDrivers = NS.SimDrivers or { DRIVERS = {}, EVENTS = {} }
    NS.SimDrivers.EVENTS.Probe = { "PLAYER_TARGET_CHANGED" }
    local step = { kind = "Probe" }
    local tip = NS.SimHost.PANEL.stepTip(step, 1)
    assertEqual(tip[1][1], L["Fires"]); assertEqual(tip[1][2], "PLAYER_TARGET_CHANGED")
    assertEqual(tip[2][1], L["Through"]); assertEqual(tip[2][2], L["the real cooldown and cast engine"])
    assertEqual(#tip, 2)
    step.ranAt, step.detail = 1, "did it"
    tip = NS.SimHost.PANEL.stepTip(step, 1)
    assertEqual(tip[3][1], L["Did"]); assertEqual(tip[3][2], "did it")
end)

test("Sim panel: anchorTo is the target grid while shown, else the focus grid, else nil", function()
    local env = ready()
    local NS = env.NS
    local IconGrid = NS:GetModule("IconGrid")
    local target, focus = IconGrid:GetGridFrame("target"), IconGrid:GetGridFrame("focus")
    assertTrue(target ~= nil and focus ~= nil, "sanity: both grids are built")
    local anchorTo = NS.SimHost.PANEL.anchorTo
    target:Show(); focus:Show()
    assertEqual(anchorTo(), target)
    target:Hide()
    assertEqual(anchorTo(), focus)
    focus:Hide()
    assertNil(anchorTo())
end)
