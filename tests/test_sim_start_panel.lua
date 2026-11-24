-- tests/test_sim_start_panel.lua — every start of KickCD's simulation shows the step panel
-- (FB2-KC-01 of Ka0sAddonsCommonTasks docs/2026-11-24-FEEDBACK_BATCH, decision D2; LibKa0s v1.113.0,
-- Sim minor 5, FB2-LK-01; standard v2.120.0).
--
-- The owner's words, 2026-11-24: "sim mode whether started from a command like /xx sim start
-- <scenario> or from just plain /xx sim should always show the sim stepper window". The library now
-- shows the panel on every successful Start; KickCD's sim runs on it and owns no start of its own
-- (Host.Prepare no longer opens the panel, which beside the library's show asked twice). These cases
-- walk each way a player starts it, on the addon's real host and the real slash dispatcher:
-- `/kcd sim start <scenario>`, the bare `/kcd sim`, the panel's Start, the Master controls Sim mode
-- box and the launcher's entry (one pair, NS.ToggleSim), a Restart, and a start after the player
-- closed the panel; and each running session's panel is pinned (no close mark, off
-- UISpecialFrames).

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local S = dofile(T.root .. "/tests/sim_support.lua")

local PANEL_NAME = "KickCDSimPanel"   -- the library's `<name>SimPanel`

--- A fresh, enabled, locked instance with chat captured; answers env, NS.
local function fresh()
    local env = S.load()
    env.advance(100)
    local NS = env.NS
    NS.db.profile.locked = true
    NS.Util.print = function() end
    return env, NS
end

--- The first scenario the host lists (`pull` on both clients).
local function firstScenario(NS) return NS.SimHost.SCENARIOS.names[1] end

local function panelFrame(env)
    for _, f in ipairs(env.mocks.__frames or {}) do
        if f.GetName and f:GetName() == PANEL_NAME then return f end
    end
end

local function onSpecial(env)
    for _, n in ipairs(env.mocks.UISpecialFrames or {}) do if n == PANEL_NAME then return true end end
    return false
end

--- The session runs, its panel is up and pinned.
local function assertShownAndPinned(env, NS, how)
    assertTrue(NS.Sim:IsActive(), how .. ": no session started")
    assertTrue(NS.Sim:IsPanelShown(), how .. ": the step panel did not open")
    local f = panelFrame(env)
    assertTrue(f ~= nil, how .. ": no " .. PANEL_NAME)
    assertTrue(f.closeButton == nil or not f.closeButton:IsShown(), how .. ": the running panel shows a close mark")
    assertFalse(onSpecial(env), how .. ": the running panel is on UISpecialFrames")
end

local function stop(env, NS)
    if NS.Sim:IsActive() then NS.Sim:Stop("stop") end
    env.flush()
end

--- Click a mock button's OnClick.
local function click(b)
    local fn = b and b.GetScript and b:GetScript("OnClick")
    assertTrue(type(fn) == "function", "the button has no OnClick")
    fn(b, "LeftButton")
end

-- ── the typed paths ─────────────────────────────────────────────────────────

test("sim start panel: `/kcd sim start <scenario>` starts and shows the pinned step panel", function()
    -- red under: Sim minor 4 (the typed start never opened the panel, the owner's /lh sim start loot)
    local env, NS = fresh()
    assertFalse(NS.Sim:IsPanelShown(), "closed before the start")
    NS:OnSlashCommand("sim start " .. firstScenario(NS))
    assertShownAndPinned(env, NS, "/kcd sim start")
    stop(env, NS)
end)

test("sim start panel: the panel is asked once per start, by the library alone", function()
    -- red under: Host.Prepare's own ShowPanel beside Sim minor 5's (two asks per start)
    local env, NS = fresh()
    local shown, real = 0, NS.Sim.ShowPanel
    NS.Sim.ShowPanel = function(...) shown = shown + 1; return real(...) end
    NS:OnSlashCommand("sim start " .. firstScenario(NS))
    NS.Sim.ShowPanel = real
    assertEqual(shown, 1)
    stop(env, NS)
end)

test("sim start panel: the bare `/kcd sim` shows the panel and starts nothing", function()
    local env, NS = fresh()
    NS:OnSlashCommand("sim")
    assertTrue(NS.Sim:IsPanelShown(), "/kcd sim did not open the step panel")
    assertFalse(NS.Sim:IsActive(), "the bare verb started a session")
    assertTrue(panelFrame(env) ~= nil)
end)

test("sim start panel: a typed start after the player closed the panel shows it again", function()
    local env, NS = fresh()
    local name = firstScenario(NS)
    NS:OnSlashCommand("sim start " .. name)
    stop(env, NS)
    NS.Sim:HidePanel()
    assertFalse(NS.Sim:IsPanelShown())
    NS:OnSlashCommand("sim start " .. name)
    assertShownAndPinned(env, NS, "the second /kcd sim start")
    stop(env, NS)
end)

test("sim start panel: a Restart after the panel was hidden mid-run shows it again", function()
    local env, NS = fresh()
    NS:OnSlashCommand("sim start " .. firstScenario(NS))
    NS:OnSlashCommand("sim panel")
    assertFalse(NS.Sim:IsPanelShown(), "`/kcd sim panel` hid the running panel")
    NS:OnSlashCommand("sim restart")
    env.flush()
    assertShownAndPinned(env, NS, "/kcd sim restart")
    stop(env, NS)
end)

-- ── the clicked paths ───────────────────────────────────────────────────────

test("sim start panel: the panel's Start starts with the panel up and pinned", function()
    local env, NS = fresh()
    NS:OnSlashCommand("sim")
    local f = panelFrame(env)
    assertTrue(f ~= nil and f.picker ~= nil and f.picker.start ~= nil, "the idle panel has no Start")
    click(f.picker.start)
    assertShownAndPinned(env, NS, "the panel's Start")
    stop(env, NS)
end)

test("sim start panel: the Master controls Sim mode box opens the panel, and its Start runs pinned", function()
    local env, NS = fresh()
    NS.Settings.Helpers.SetAndRefresh("state.sim", true)
    assertTrue(NS.Sim:IsPanelShown(), "the box did not open the step panel")
    click(panelFrame(env).picker.start)
    assertShownAndPinned(env, NS, "the box, then Start")
    stop(env, NS)
end)

test("sim start panel: the launcher's Sim mode entry (NS.ToggleSim) opens the panel", function()
    local env, NS = fresh()
    NS.ToggleSim()
    assertTrue(NS.Sim:IsPanelShown(), "the launcher entry did not open the step panel")
    click(panelFrame(env).picker.start)
    assertShownAndPinned(env, NS, "the launcher, then Start")
    stop(env, NS)
end)

-- ── a refused start ─────────────────────────────────────────────────────────

test("sim start panel: a refused start (the grids unlocked) shows no panel", function()
    local _, NS = fresh()
    NS.db.profile.locked = false
    NS:OnSlashCommand("sim start " .. firstScenario(NS))
    assertFalse(NS.Sim:IsActive(), "an unlocked addon started a sim")
    assertFalse(NS.Sim:IsPanelShown(), "a refused start opened the panel")
end)
