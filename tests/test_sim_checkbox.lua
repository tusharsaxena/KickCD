-- tests/test_sim_checkbox.lua
-- The Master controls tab's Sim mode checkbox (R6-SIM of Ka0sAddonsCommonTasks
-- docs/2026-11-03-SMOKE_ROUND6; LibKa0s OptionsCompose minor 19, options-ui-§15).
--
-- The owner's rule: an addon with a simulation shows a Sim checkbox in its settings, next to Test.
-- KickCD has no Test mode row (unlocking IS its preview, settings/General.lua's header), so the
-- composer puts Sim mode beside Lock frame. The row's get / set are the host's isSimMode /
-- toggleSim, the SAME pair its launcher carries (core/LauncherSetup.lua), hoisted to NS.IsSimMode /
-- NS.ToggleSim in core/SimSetup.lua so the box, the launcher's Sim mode entry and `/kcd sim` are one
-- act. The cases below pin the row, that pair, the live refresh from the sim's listener and the
-- reset walk stopping a running sim.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

local S = dofile(T.root .. "/tests/sim_support.lua")

--- A fresh, enabled, locked instance with the simulator live and chat captured.
local function fresh()
    local env = S.load()
    env.advance(100)
    local NS = env.NS
    NS.db.profile.locked = true
    local lines = {}
    NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    return env, NS, lines
end

--- The Master controls rows of `NS`'s General page, in declaration order.
local function masterRows(NS)
    local H, got = NS.Settings.Helpers, {}
    for _, def in ipairs(H.SchemaForPanel("general", nil)) do
        if def.group == H.MASTER_GROUP then got[#got + 1] = def end
    end
    return got
end

--- Swap NS.Sim for a recorder answering `active`; answers the calls list and the restore.
local function fakeSim(NS, active)
    local real, calls = NS.Sim, {}
    NS.Sim = {
        IsActive = function() return active end,
        RunVerb = function(_, line) calls[#calls + 1] = line; return true end,
    }
    return calls, function() NS.Sim = real end
end

-- ── the row ─────────────────────────────────────────────────────────────────

test("Sim mode is a session-only Master controls row at state.sim, beside Lock frame", function()
    -- red under: settings/General.lua's MasterControls spec without isSimMode / toggleSim
    local _, NS = fresh()
    local row = NS.Settings.Store.FindRow("state.sim")
    assertTrue(row ~= nil, "the Master controls tab must declare the Sim mode row")
    assertEqual(row.type, "bool")
    assertEqual(row.label, "Sim mode", "the library's own label")
    assertEqual(row.sessionOnly, true, "nothing is stored: a reload ends the sim")
    assertEqual(row.default, false)
    assertEqual(type(row.get), "function", "the row reads the sim")
    assertEqual(type(row.set), "function", "and drives it")
    local rows = masterRows(NS)
    local at
    for i, def in ipairs(rows) do if def.path == "state.sim" then at = i end end
    assertTrue(at ~= nil, "the row is on the Master controls tab")
    assertEqual(rows[at - 1].path, "locked", "Sim mode sits straight after Lock frame")
    assertTrue(not rows[at].startsLine, "in Lock frame's second column")
    assertEqual(rows[at + 1].path, "state.debugConsole", "Debug console opens the next line")
    assertEqual(rows[at + 1].startsLine, true)
end)

-- ── one pair behind the box, the launcher and the slash verb ────────────────

test("the launcher and the box share NS.IsSimMode / NS.ToggleSim, the acts of `/kcd sim`", function()
    -- red under: the launcher's inline pair left in core/LauncherSetup.lua, or no NS pair
    local _, NS = fresh()
    assertEqual(type(NS.IsSimMode), "function", "NS.IsSimMode is the one reader")
    assertEqual(type(NS.ToggleSim), "function", "NS.ToggleSim is the one act")
    local f = assert(io.open(T.root .. "/core/LauncherSetup.lua", "rb"))
    local body = f:read("*a"); f:close()
    assertTrue(body:find("isSimMode = NS.IsSimMode", 1, true) ~= nil, "the launcher reads NS.IsSimMode")
    assertTrue(body:find("toggleSim = NS.ToggleSim", 1, true) ~= nil, "the launcher acts through NS.ToggleSim")
    f = assert(io.open(T.root .. "/settings/General.lua", "rb"))
    body = f:read("*a"); f:close()
    assertTrue(body:find("isSimMode        = NS.IsSimMode", 1, true) ~= nil, "the box reads NS.IsSimMode")
    assertTrue(body:find("toggleSim        = NS.ToggleSim", 1, true) ~= nil, "the box acts through NS.ToggleSim")
end)

test("ticking runs the bare `/kcd sim` verb, unticking runs `/kcd sim stop`", function()
    -- red under: a set that toggles without comparing, or a set that picks a scenario itself
    local _, NS = fresh()
    local H = NS.Settings.Helpers
    local calls, restore = fakeSim(NS, false)
    H.SetAndRefresh("state.sim", true)
    assertEqual(#calls, 1, "one act per tick")
    assertEqual(calls[1], "", "the bare verb, the same as typing /kcd sim")
    H.SetAndRefresh("state.sim", false)
    assertEqual(#calls, 1, "unticking an idle sim does nothing")
    restore()
    calls, restore = fakeSim(NS, true)
    H.SetAndRefresh("state.sim", false)
    assertEqual(calls[1], "stop", "unticking a running sim stops it")
    H.SetAndRefresh("state.sim", true)
    assertEqual(#calls, 1, "ticking a running sim does nothing")
    restore()
end)

test("the box reads the live sim: unticked idle, ticked while a scenario plays, unticked after", function()
    local _, NS = fresh()
    local S2 = NS.Settings.Store
    assertFalse(S2.Get("state.sim"), "idle reads unticked")
    assertTrue(NS.Sim:RunVerb("start pull"), "the typed start was refused")
    assertTrue(S2.Get("state.sim"), "a sim started from the slash verb reads ticked")
    NS.Settings.Helpers.SetAndRefresh("state.sim", false)
    assertFalse(NS.Sim:IsActive(), "unticking stopped the sim")
    assertFalse(S2.Get("state.sim"))
end)

-- ── the live refresh ────────────────────────────────────────────────────────

test("a sim that starts or stops elsewhere repaints the open panel (RefreshScalars)", function()
    -- red under: no Sim:AddListener in modules/Sim.lua calling Helpers.RefreshScalars
    local env, NS = fresh()
    local H = NS.Settings.Helpers
    local n, real = 0, H.RefreshScalars
    H.RefreshScalars = function(...) n = n + 1; return real(...) end
    assertTrue(NS.Sim:RunVerb("start pull"), "the typed start was refused")
    assertTrue(n >= 1, "the start did not refresh the panel")
    local mark = n
    NS.Sim:Stop()
    env.advance(0)
    assertTrue(n > mark, "the stop did not refresh the panel")
    H.RefreshScalars = real
end)

-- ── the reset walk ──────────────────────────────────────────────────────────

test("Reset all settings stops a running sim and never starts an idle one", function()
    -- red under: no Sim mode row (the session walk has nothing to stop the sim with)
    local _, NS = fresh()
    local H = NS.Settings.Helpers
    local calls, restore = fakeSim(NS, false)
    H.ResetAll()
    assertEqual(#calls, 0, "a reset with the sim idle must not start it")
    restore()
    -- The walk itself stops a running sim: the profile reset's own stop (core/Database.lua's
    -- OnProfileChanged) would end a real sim with no Sim mode row at all, so the recorder answers
    -- "running" to every ask and the row's `/kcd sim stop` is the only RunVerb it can hear.
    calls, restore = fakeSim(NS, true)
    NS.Sim.Stop = function() end
    H.ResetAll()
    assertEqual(calls[1], "stop", "the reset walk's Sim mode row must stop a running sim")
    assertEqual(#calls, 1, "one stop, never a start")
    restore()
    NS.db.profile.locked = true   -- the reset unlocked the frames, and an unlocked addon refuses a start
    assertTrue(NS.Sim:RunVerb("start pull"), "the typed start was refused")
    H.ResetAll()
    assertFalse(NS.Sim:IsActive(), "Reset all settings left the sim running")
end)
