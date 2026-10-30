-- tests/test_sim_marker.lua — what marks a running simulation on screen (KC-02 of
-- Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, ruling D-13; image-46).
--
-- The floating simulation strip KC-09 (KickCD#38) hung over each icon grid is gone: it was the only
-- strip that floated over a HUD display, and it stayed on screen while the grid hid between casts,
-- a cyan bar over nothing. The library's step panel is the session's on-screen sign instead (the
-- preview-mode MUST, satisfied by the panel), so KickCD keeps it up for the whole session: its close
-- mark is hidden and Escape does not take it down (modules/Sim.lua's Host.PinPanel). The panel's
-- Stop row and `/kcd sim stop` end the session; `/kcd sim panel` still toggles the panel on purpose.
--
-- These cases drive the addon's own NS.Sim on the `test` scenario tests/sim_support.lua injects,
-- with the host's real Prepare (`host = true`), which opens the panel.

local T = _G.KICKCD_TEST
local test, assertTrue, assertFalse, assertNil = T.test, T.assertTrue, T.assertFalse, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

local WIDGETS = "LibKa0s-Widgets-1.0"
local PANEL_NAME = "KickCDSimPanel"   -- the library's `<name>SimPanel` (Sim document, `name`)

--- A fresh, locked environment with the `test` scenario injected (not started), the clock off zero
--- and the Widgets mode-strip constructor spied: ctx = { env, NS, calls }.
local function ready()
    local env = S.load()
    env.advance(100)
    local NS = env.NS
    NS.db.profile.locked = true
    S.testSession(env, { { kind = "Noop", label = "Noop" }, { kind = "Noop", label = "Noop" } },
        { host = true, start = false })
    NS.SimDrivers.DRIVERS.Noop = NS.SimDrivers.DRIVERS.Noop or function() return "noop" end
    local W = env.mocks.LibStub(WIDGETS, true)
    local ctx = { env = env, NS = NS, calls = {} }
    local real = W.TestStrip
    W.TestStrip = function(parent, opts)
        ctx.calls[#ctx.calls + 1] = { parent = parent, opts = opts }
        return real(parent, opts)
    end
    return ctx
end

local function start(ctx)
    local ok, line = ctx.NS.Sim:Start{ scenario = "test" }
    assertTrue(ok, "the test session did not start: " .. tostring(line))
end

local function stop(ctx)
    if ctx.NS.Sim:IsActive() then ctx.NS.Sim:Stop("stop") end
    ctx.env.flush()
end

local function panelFrame(ctx) return ctx.env.mocks.__frames and (function()
    for _, f in ipairs(ctx.env.mocks.__frames) do
        if f.GetName and f:GetName() == PANEL_NAME then return f end
    end
end)() end

local function special(ctx, name)
    for _, n in ipairs(ctx.env.mocks.UISpecialFrames or {}) do if n == name then return true end end
    return false
end

-- ── no floating strip ───────────────────────────────────────────────────────

test("sim marker: the floating strip is gone: no module, no TOC line, no strip at a start", function()
    -- red under: modules/SimStrip.lua still loaded, or a start building W.TestStrip's sim flavor
    local ctx = ready()
    assertNil(ctx.NS.SimStrip, "NS.SimStrip is still defined")
    for _, rel in ipairs(T.tocFiles) do
        assertFalse(rel == "modules/SimStrip.lua", "the TOC still loads modules/SimStrip.lua")
    end
    start(ctx)
    for _, c in ipairs(ctx.calls) do
        assertFalse(c.opts and c.opts.kind == "sim", "a sim strip was built at the start")
    end
    assertNil(ctx.NS.Const.LAYERS.LEVEL.HUD.MARKER, "the strip's HUD level slot outlived it")
    stop(ctx)
end)

test("sim marker: the scenario's strip line is out of the locale", function()
    local ctx = ready()
    assertNil(rawget(ctx.NS.L, "Simulation: %s - /kcd sim stop ends it."))
end)

-- ── the step panel is the sign ──────────────────────────────────────────────

test("sim marker: a start opens the step panel with no close mark", function()
    -- red under: the panel built with its close mark showing
    local ctx = ready()
    start(ctx)
    assertTrue(ctx.NS.Sim:IsPanelShown(), "the step panel is the session's sign")
    local f = panelFrame(ctx)
    assertTrue(f ~= nil, "the panel frame is " .. PANEL_NAME)
    assertTrue(f.closeButton == nil or not f.closeButton:IsShown(), "the close mark still shows")
    stop(ctx)
end)

test("sim marker: Escape does not take the panel down while a session runs", function()
    -- red under: the panel left on UISpecialFrames, which Escape's CloseSpecialWindows hides
    local ctx = ready()
    start(ctx)
    assertFalse(special(ctx, PANEL_NAME), "the panel is on UISpecialFrames")
    stop(ctx)
end)

test("sim marker: the panel stays up across the session's steps", function()
    local ctx = ready()
    start(ctx)
    ctx.env.flush()
    ctx.NS.Sim:Step()
    ctx.env.flush()
    assertTrue(ctx.NS.Sim:IsPanelShown(), "the panel went away mid-session")
    stop(ctx)
end)
