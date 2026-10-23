-- tests/test_sim_interference.lua — the real world interfering with a simulation (KC-06).
--
-- KickCD#38; the Sim major's host contract H5 (destructive commands refuse), H6 (the stand-down
-- stops first) and H8 (a diagnostics section); design-kc-sim D10 and §6. A session stops by itself
-- when the REAL client enters combat, shows a loading screen or puts the player in a group, when the
-- profile switches and when the grids are unlocked from the settings panel. The CLI's unlock and
-- resetall refuse while a session runs, the stand-down stops the session before any module
-- suspends, and `/kcd diagnostics` carries a `sim` section.
--
-- "Real" events here go through the kit's AceEvent (`mocks.__fireEvent`) or a cast-filter frame's
-- own OnEvent, the way the client delivers them; "simulated" ones go through NS.Sim:Fire. Every case
-- builds its own environment (tests/sim_support.lua says why).

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

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

local function has(lines, line)
    for _, l in ipairs(lines) do if l == line then return true end end
    return false
end

--- Deep equality of two plain tables (SavedVariables shapes).
local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

--- A fresh environment, locked, with the `test` scenario running on the host's real hooks.
local function running(steps)
    local env = S.load()
    env.advance(100)
    env.NS.db.profile.locked = true
    S.testSession(env, steps or { { kind = "Noop", label = "Noop" } }, { host = true, start = false })
    local ok, line = env.NS.Sim:Start{ scenario = "test" }
    assert(ok, "the session did not start: " .. tostring(line))
    return env
end

local function stopLine(env, reason)
    local L = env.NS.L
    local text = {
        combat = L["Simulation stopped: you entered combat."],
        world = L["Simulation stopped: a loading screen."],
        group = L["Simulation stopped: you joined a group."],
        profile = L["Simulation stopped: the profile changed."],
        unlocked = L["Simulation stopped: the grids were unlocked."],
        standDown = L["Simulation stopped: the addon stood down."],
    }
    return text[reason]
end

--- The watch target's registrations, by event.
local function watched(env)
    local out = {}
    for _, reg in ipairs(env.mocks.__registrationSet()) do
        if reg.target == env.NS.SimHost.watch then out[reg.event] = true end
    end
    return out
end

local REFUSE = "End the simulation first (/kcd sim stop)."

-- ── 1-3. real combat, a loading screen, a group ─────────────────────────────

test("Sim interference: a REAL PLAYER_REGEN_DISABLED stops with `combat`, and real combat stays", function()
    local env = running()
    local NS = env.NS
    local lines = said(NS, function() env.mocks.__fireEvent("PLAYER_REGEN_DISABLED") end)
    assertFalse(NS.Sim:IsActive(), "real combat did not stop the session")
    assertTrue(has(lines, stopLine(env, "combat")), table.concat(lines, " || "))
    assertTrue(NS.State.inCombat, "the stop's cleanup ended a REAL combat")
end)

test("Sim interference: a REAL PLAYER_ENTERING_WORLD stops with `world`", function()
    local env = running()
    local lines = said(env.NS, function() env.mocks.__fireEvent("PLAYER_ENTERING_WORLD", false, false) end)
    assertFalse(env.NS.Sim:IsActive())
    assertTrue(has(lines, stopLine(env, "world")), table.concat(lines, " || "))
end)

test("Sim interference: a REAL GROUP_ROSTER_UPDATE stops with `group` only when the player is in a group", function()
    local env = running()
    env.mocks.__fireEvent("GROUP_ROSTER_UPDATE")
    assertTrue(env.NS.Sim:IsActive(), "a roster update outside a group stopped the session")
    env.mocks.__context.inGroup = true
    local lines = said(env.NS, function() env.mocks.__fireEvent("GROUP_ROSTER_UPDATE") end)
    assertFalse(env.NS.Sim:IsActive())
    assertTrue(has(lines, stopLine(env, "group")), table.concat(lines, " || "))
end)

-- ── 4. a simulated event never reaches the watch ────────────────────────────

test("Sim interference: a SIMULATED GROUP_ROSTER_UPDATE never reaches the watch target", function()
    local env = running()
    local NS = env.NS
    env.mocks.__context.inGroup = true
    local reached, real = 0, NS.SimHost.OnWatchEvent
    NS.SimHost.OnWatchEvent = function(...) reached = reached + 1; return real(...) end
    NS.Sim:Fire("GROUP_ROSTER_UPDATE")
    NS.Sim:Fire("PLAYER_REGEN_DISABLED")
    NS.SimHost.OnWatchEvent = real
    assertEqual(reached, 0, "a simulated event reached the watch")
    assertTrue(NS.Sim:IsActive(), "a simulated event stopped the session")
    NS.Sim:Stop()
end)

-- ── 5-6. the profile switch and the settings checkbox ───────────────────────

test("Sim interference: a profile switch stops with `profile`", function()
    local env = running()
    local lines = said(env.NS, function() env.NS.db:SetProfile("Other") end)
    assertFalse(env.NS.Sim:IsActive(), "the profile switch did not stop the session")
    assertTrue(has(lines, stopLine(env, "profile")), table.concat(lines, " || "))
end)

test("Sim interference: unticking Lock frame (Store.Set locked false) stops with `unlocked`", function()
    local env = running()
    local NS = env.NS
    local lines = said(NS, function() NS.Settings.Store.Set("locked", false) end)
    assertFalse(NS.Sim:IsActive(), "unlocking from the settings did not stop the session")
    assertTrue(has(lines, stopLine(env, "unlocked")), table.concat(lines, " || "))
    assertEqual(NS.db.profile.locked, false, "the checkbox write itself was undone")
end)

-- ── 7-8. the CLI refuses (H5) ───────────────────────────────────────────────

test("Sim interference: /kcd unlock, /kcd toggle and NS.ToggleLock refuse while a session runs", function()
    local env = running()
    local NS = env.NS
    local line = NS.L[REFUSE]
    for _, run in ipairs({
        function() NS:OnSlashCommand("unlock") end,
        function() NS:OnSlashCommand("toggle") end,
        function() NS.ToggleLock() end,
    }) do
        local lines = said(NS, run)
        assertTrue(#lines >= 1 and lines[#lines]:find(line, 1, true) ~= nil, table.concat(lines, " || "))
        assertEqual(NS.db.profile.locked, true, "the lock moved")
        assertTrue(NS.Sim:IsActive(), "the refusal stopped the session")
    end
    -- `/kcd lock` is not destructive: it still runs.
    NS:OnSlashCommand("lock")
    assertTrue(NS.Sim:IsActive())
    NS.Sim:Stop()
    -- Idle, unlock works again.
    NS:OnSlashCommand("unlock")
    assertEqual(NS.db.profile.locked, false)
end)

test("Sim interference: /kcd resetall refuses while a session runs, and KickCDDB is unchanged", function()
    local env = running()
    local NS = env.NS
    NS.db.profile.scale = 1.5
    local before = env.snapshotDB()
    local lines = said(NS, function() NS:OnSlashCommand("resetall") end)
    assertTrue(#lines >= 1 and lines[#lines]:find(NS.L[REFUSE], 1, true) ~= nil, table.concat(lines, " || "))
    assertTrue(deepEqual(before, env.snapshotDB()), "resetall wrote KickCDDB")
    assertTrue(NS.Sim:IsActive())
    NS.Sim:Stop()
end)

-- ── 9. the stand-down stops first (H6) ──────────────────────────────────────

test("Sim interference: /kcd disable stops the session FIRST, before any module suspends", function()
    local env = running()
    local NS = env.NS
    local order = {}
    local IconGrid = NS:GetModule("IconGrid")
    local realStop, realSuspend = NS.Sim.Stop, IconGrid.Suspend
    NS.Sim.Stop = function(self, reason, ...)
        order[#order + 1] = "stop:" .. tostring(reason)
        return realStop(self, reason, ...)
    end
    IconGrid.Suspend = function(...)
        order[#order + 1] = "suspend"
        return realSuspend(...)
    end
    local lines = said(NS, function() NS:OnSlashCommand("disable") end)
    NS.Sim.Stop, IconGrid.Suspend = realStop, realSuspend
    assertFalse(NS.Sim:IsActive())
    assertEqual(order[1], "stop:standDown", table.concat(order, ", "))
    local sawSuspend = false
    for _, o in ipairs(order) do if o == "suspend" then sawSuspend = true end end
    assertTrue(sawSuspend, "IconGrid did not suspend: " .. table.concat(order, ", "))
    assertTrue(has(lines, stopLine(env, "standDown")), table.concat(lines, " || "))
end)

-- ── 10. targeting and casting are absorbed ──────────────────────────────────

--- Fire a REAL unit event at every cast-filter frame registered for it on `unit`.
local function fireUnitEvent(env, event, unit, ...)
    local n = 0
    for _, f in ipairs(env.mocks.__frames) do
        if f.__events and f.__events[event] == unit then
            local fn = f:GetScript("OnEvent")
            if fn then fn(f, event, unit, ...); n = n + 1 end
        end
    end
    return n
end

test("Sim interference: a REAL target change and a REAL cast start are absorbed", function()
    local env = running()
    local NS = env.NS
    local W = NS.SimWorld
    W.AddEnemy("casterA", { name = "Caster A", hostile = true })
    W.SetUnit("target", "casterA")
    W.StartCast("casterA", { spellID = 12345, name = "Shadow Bolt", duration = 3 })
    NS.Sim:Fire("PLAYER_TARGET_CHANGED")
    NS.Sim:Fire("UNIT_SPELLCAST_START", "target", "Cast-1", 12345)
    local bar = NS:GetModule("Castbar"):PeekInstance("target")
    assertTrue(bar and bar.current ~= nil, "sanity: the cast bar shows the simulated cast")
    assertEqual(bar.current.spellID, 12345)

    env.mocks.__fireEvent("PLAYER_TARGET_CHANGED")
    assertTrue(fireUnitEvent(env, "UNIT_SPELLCAST_START", "target", "Cast-real", 999) >= 1,
        "sanity: a cast filter is armed on target")
    assertTrue(NS.Sim:IsActive(), "a real target change or cast stopped the session")
    bar = NS:GetModule("Castbar"):PeekInstance("target")
    assertTrue(bar.current ~= nil, "the simulated cast was dropped")
    assertEqual(bar.current.spellID, 12345, "the cast bar shows the real cast")
    NS.Sim:Stop()
end)

-- ── 11. no watch while idle ─────────────────────────────────────────────────

test("Sim interference: the watch target registers only while a session runs", function()
    local env = S.load()
    env.advance(100)
    env.NS.db.profile.locked = true
    assertTrue(type(env.NS.SimHost.watch) == "table", "NS.SimHost.watch is missing")
    assertNil(next(watched(env)), "the watch is registered while idle")
    S.testSession(env, { { kind = "Noop" } }, { host = true, start = false })
    assertTrue(env.NS.Sim:Start{ scenario = "test" })
    local w = watched(env)
    assertTrue(w.PLAYER_REGEN_DISABLED and w.PLAYER_ENTERING_WORLD and w.GROUP_ROSTER_UPDATE,
        "the watch is not registered while running")
    env.NS.Sim:Stop()
    assertNil(next(watched(env)), "the watch outlived the session")
    -- The watch is never a deliver route (KC-02).
    assertEqual(env.NS.DeliverEvent("GROUP_ROSTER_UPDATE"), 0)
end)

-- ── 12. the diagnostics section (H8) ────────────────────────────────────────

local function report(NS)
    local built = NS.DebugLog:BuildDiagnostics()
    local lines = {}
    for i, l in ipairs(built.lines) do lines[i] = "[" .. tostring(l[1]) .. "] " .. tostring(l[2]) end
    return lines
end

local function hasLine(lines, needle)
    for _, l in ipairs(lines) do if l:find(needle, 1, true) then return true end end
    return false
end

test("Sim diagnostics: the sim section says idle, then names the running session", function()
    local env = S.load()
    env.advance(100)
    local NS = env.NS
    NS.db.profile.locked = true
    local lines = report(NS)
    assertTrue(hasLine(lines, "[Sim] sim: idle"), table.concat(lines, "\n"))
    S.testSession(env, { { kind = "Noop" }, { kind = "Noop" } }, { host = true, start = false })
    assertTrue(NS.Sim:Start{ scenario = "test" })
    NS.Sim:Fire("SPELL_UPDATE_COOLDOWN")
    NS.Sim:Session().simCombat = true
    lines = report(NS)
    local all = table.concat(lines, "\n")
    assertTrue(hasLine(lines, "[Sim] sim: scenario=test"), all)
    assertTrue(hasLine(lines, "[Sim] sim: step=0/2"), all)
    assertTrue(hasLine(lines, "[Sim] sim: events=1"), all)
    assertTrue(hasLine(lines, "[Sim] sim: kick=" .. S.KICK), all)
    assertTrue(hasLine(lines, "[Sim] sim: cc=" .. S.CC), all)
    assertTrue(hasLine(lines, "[Sim] sim: simulated combat=on"), all)
    NS.Sim:Session().simCombat = nil
    assertTrue(hasLine(report(NS), "[Sim] sim: simulated combat=off"))
    NS.Sim:Stop()
end)
