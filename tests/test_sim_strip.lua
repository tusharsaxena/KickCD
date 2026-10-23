-- tests/test_sim_strip.lua — the simulation strip over the icon grids (modules/SimStrip.lua).
--
-- KC-09 (KickCD#38; OWNER_SCOPE B2; the Sim major's preview-mode marker rule, H8). While a
-- simulation runs, each enabled icon grid carries LibKa0s-Widgets-1.0's mode strip in its sim
-- flavor, BOTTOM to the grid's TOP (above the unit's label when the label sits there). These cases
-- drive the addon's own NS.Sim on the `test` scenario tests/sim_support.lua injects, with the host's
-- real Prepare (`host = true`), which calls NS.SimStrip:Refresh.
--
-- The strip's own fill, icon and text anchors are the library's and are covered by its suite; what
-- is KickCD's, and pinned here, is the wiring: when it exists, what it says, where it sits, and that
-- it lets go of the bus when the session ends.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

local WIDGETS = "LibKa0s-Widgets-1.0"

--- A fresh, locked environment with the `test` scenario injected (not started), the clock off zero
--- and the Widgets constructor spied: ctx = { env, NS, W, calls }.
local function ready(mutateProfile)
    local env = S.load()
    env.advance(100)
    local NS = env.NS
    NS.db.profile.locked = true
    if mutateProfile then mutateProfile(NS.db.profile) end
    S.testSession(env, { { kind = "Noop", label = "Noop" } }, { host = true, start = false })
    NS.SimDrivers.DRIVERS.Noop = NS.SimDrivers.DRIVERS.Noop or function() return "noop" end
    local W = env.mocks.LibStub(WIDGETS, true)
    local ctx = { env = env, NS = NS, W = W, calls = {} }
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

local function lastPoint(frame)
    local pts = frame.__points
    return pts and pts[#pts]
end

local function gridOf(NS, unit) return NS:GetModule("IconGrid"):GetGridFrame(unit) end

local function configChanged(NS, section)
    NS:SendMessage(NS.MSG.CONFIG_CHANGED, { section = section })
end

-- ── the module ──────────────────────────────────────────────────────────────

test("TOC: modules/SimStrip.lua loads straight after modules/SimScenario.lua, before Diagnostics", function()
    local at
    for i, rel in ipairs(T.tocFiles) do if rel == "modules/SimScenario.lua" then at = i end end
    assertTrue(at ~= nil, "modules/SimScenario.lua is not in KickCD.toc")
    assertEqual(T.tocFiles[at + 1], "modules/SimStrip.lua")
    assertEqual(T.tocFiles[at + 2], "modules/Diagnostics.lua")
end)

test("SimStrip: idle, no strip frame exists (it is built lazily on the first start)", function()
    local ctx = ready()
    assertTrue(ctx.NS.SimStrip ~= nil, "NS.SimStrip is not defined")
    assertNil(ctx.NS.SimStrip.__frame, "an idle addon holds no strip")
    assertNil(next(ctx.NS.SimStrip.__frames), "an idle addon holds no strip")
    assertEqual(#ctx.calls, 0, "nothing built a strip while idle")
    assertNil(ctx.NS.SimStrip.__bus, "an idle addon holds no strip bus target")
end)

-- ── the start ───────────────────────────────────────────────────────────────

test("SimStrip: on start the strip is shown, built with the sim flavor, and names the scenario", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local strip = NS.SimStrip.__frame
    assertTrue(strip ~= nil, "no strip after the start")
    assertTrue(strip:IsShown(), "the strip is not shown during a simulation")
    assertEqual(strip.kind, "sim")
    assertTrue(#ctx.calls >= 1, "the strip was not built through W.TestStrip")
    assertEqual(ctx.calls[1].opts.kind, "sim", "W.TestStrip was not asked for the sim flavor")
    assertEqual(ctx.calls[1].parent, ctx.env.mocks.UIParent, "the strip is parented to UIParent")
    assertEqual(ctx.calls[1].opts.icon, NS.Icon("info"))
    assertEqual(strip.text:GetText(), NS.L["Simulation: %s - /kcd sim stop ends it."]:format("Test"))
    assertEqual(strip:GetFrameStrata(), "MEDIUM")
    stop(ctx)
end)

test("SimStrip: with the default label above the grid, the strip sits BOTTOM to the label's TOP, 2 up", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local strip = NS.SimStrip.__frames.target
    local above = NS:GetModule("UnitLabel"):FrameAbove("target", "icons")
    assertTrue(above ~= nil, "sanity: the default profile shows the label above the grid")
    assertEqual(strip.__anchorTo, above)
    local p = lastPoint(strip)
    assertEqual(p.point, "BOTTOM")
    assertEqual(p.relativeTo, above)
    assertEqual(p.relativePoint, "TOP")
    assertEqual(p.x, 0)
    assertEqual(p.y, 2)
    stop(ctx)
end)

test("SimStrip: one strip per enabled grid: the focus grid carries its own", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local focus = NS.SimStrip.__frames.focus
    assertTrue(focus ~= nil and focus:IsShown(), "the focus grid carries no strip")
    assertTrue(focus ~= NS.SimStrip.__frames.target, "the two grids share one strip")
    assertEqual(focus.__anchorTo, NS:GetModule("UnitLabel"):FrameAbove("focus", "icons"))
    assertEqual(NS.SimStrip.__frame, NS.SimStrip.__frames.target, "the primary strip is the target's")
    stop(ctx)
end)

test("SimStrip: with the target label off, the strip anchors to the target grid frame", function()
    local ctx = ready(function(p) p.units.target.label.show = false end)
    start(ctx)
    local NS = ctx.NS
    local strip = NS.SimStrip.__frames.target
    assertEqual(strip.__anchorTo, gridOf(NS, "target"))
    local p = lastPoint(strip)
    assertEqual(p.point, "BOTTOM")
    assertEqual(p.relativePoint, "TOP")
    assertEqual(p.y, 2)
    stop(ctx)
end)

test("SimStrip: with the target disabled, the strip marks the focus grid", function()
    local ctx = ready(function(p)
        p.units.target.enabled = false
        -- A linked Focus reads Target's label.show (NS.Units.LabelShow), so the label goes off there.
        p.units.target.label.show = false
    end)
    start(ctx)
    local NS = ctx.NS
    assertEqual(NS.SimStrip.__frame, NS.SimStrip.__frames.focus)
    assertEqual(NS.SimStrip.__frame.__anchorTo, gridOf(NS, "focus"))
    assertTrue(NS.SimStrip.__frame:IsShown())
    local target = NS.SimStrip.__frames.target
    assertTrue(target == nil or not target:IsShown(), "a disabled target grid carries no strip")
    stop(ctx)
end)

test("SimStrip: with both units disabled mid-session, the strip floats at UIParent CENTER 0, 180", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    NS.db.profile.units.target.enabled = false
    NS.db.profile.units.focus.enabled = false
    configChanged(NS, "units")
    assertTrue(NS.Sim:IsActive(), "sanity: the session still runs")
    local strip = NS.SimStrip.__frame
    assertTrue(strip:IsShown(), "the floating strip is not shown")
    local p = lastPoint(strip)
    assertEqual(p.point, "CENTER")
    assertEqual(p.relativeTo, ctx.env.mocks.UIParent)
    assertEqual(p.relativePoint, "CENTER")
    assertEqual(p.x, 0)
    assertEqual(p.y, 180)
    assertFalse(NS.SimStrip.__frames.focus:IsShown(), "the focus strip hides with its grid")
    stop(ctx)
end)

test("SimStrip: visibility target_casting with no cast hides the grid, not the strip", function()
    local ctx = ready(function(p) p.visibility = "target_casting" end)
    start(ctx)
    local NS = ctx.NS
    configChanged(NS, "general")
    assertTrue(NS.SimStrip.__frames.target:IsShown(), "the strip went away with the grid")
    stop(ctx)
end)

test("SimStrip: a GRID_LAYOUT or a CONFIG_CHANGED (units) re-places it", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local strip = NS.SimStrip.__frames.target
    strip:ClearAllPoints()
    NS:SendMessage(NS.MSG.GRID_LAYOUT, { unit = "target", gridFrame = gridOf(NS, "target") })
    assertTrue(lastPoint(strip) ~= nil, "GRID_LAYOUT did not re-place the strip")
    strip:ClearAllPoints()
    NS.db.profile.units.target.label.show = false
    configChanged(NS, "units")
    assertEqual(strip.__anchorTo, gridOf(NS, "target"), "CONFIG_CHANGED did not re-place the strip")
    stop(ctx)
end)

test("SimStrip: the width is max(220, the grid's width)", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local grid, strip = gridOf(NS, "target"), NS.SimStrip.__frames.target
    assertEqual(strip:GetWidth(), math.max(220, grid:GetWidth() or 0))
    grid:SetWidth(400)
    NS.SimStrip:Place()
    assertEqual(strip:GetWidth(), 400)
    grid:SetWidth(50)
    NS.SimStrip:Place()
    assertEqual(strip:GetWidth(), 220)
    stop(ctx)
end)

-- ── the stop ────────────────────────────────────────────────────────────────

test("SimStrip: on stop it hides and releases its bus subscriptions", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local bus = NS.SimStrip.__bus
    local reg = ctx.env.mocks.__msgRegistry
    assertTrue(bus ~= nil, "the strip subscribed through no bus target")
    assertTrue(reg[NS.MSG.GRID_LAYOUT] and reg[NS.MSG.GRID_LAYOUT][bus] ~= nil, "sanity: subscribed while shown")
    stop(ctx)
    for unit, frame in pairs(NS.SimStrip.__frames) do
        assertFalse(frame:IsShown(), unit .. "'s strip outlived the session")
    end
    for _, msg in ipairs({ NS.MSG.GRID_LAYOUT, NS.MSG.CONFIG_CHANGED }) do
        assertNil(reg[msg] and reg[msg][bus], msg .. " is still registered after the stop")
    end
end)

-- ── degraded ────────────────────────────────────────────────────────────────

test("SimStrip: without the library's sim flavor, no strip, no error, and the session runs", function()
    local ctx = ready()
    ctx.W.TestStrip = nil
    start(ctx)
    local NS = ctx.NS
    assertTrue(NS.Sim:IsActive(), "the session did not run without the strip")
    assertNil(NS.SimStrip.__frame, "a strip was built with no constructor")
    assertNil(next(NS.SimStrip.__frames))
    stop(ctx)
    assertFalse(NS.Sim:IsActive())
end)
