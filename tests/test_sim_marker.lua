-- tests/test_sim_marker.lua — what marks a running simulation on screen (AD-88-KC of
-- Ka0sAddonsCommonTasks docs/2026-11-17-LIBKA0S_V1_105_ADOPTION, ruling 2; LibKa0s#88;
-- WowAddonStandards v2.110.0, preview-mode's *Where the strip sits*).
--
-- INVERTED BY AD-88-KC. Until then this suite pinned ruling D-13 (KC-02 of the 2026-10-30 skin
-- fonts run, image-46): no strip over any HUD display, the step panel the session's only sign. The
-- standard retired the HUD exemption in v2.110.0, so ruling 2 of the adoption run reverses D-13:
-- every HUD display drawing simulated data carries the library's cyan strip, DOCKED (`dock =
-- "hud"`, Widgets minor 27) on the display's top edge, outside it, and the step panel stays up as
-- well. D-13's complaint, a cyan bar over nothing while the grid hid between casts, was a strip
-- parented to UIParent; a docked strip is parented to its display and hides with it.
--
-- One strip per icon grid, and one per cast bar the player positions on its own (`anchorMode`
-- FREE). A cast bar anchored to its grid's primary icon is part of that grid's display, so the
-- grid's strip marks both, and stacks clear of the bar (the dock's `clear`) where no label sits
-- above the grid, or clear of a label above the bar when one sits there.
--
-- These cases drive the addon's own NS.Sim on the `test` scenario tests/sim_support.lua injects,
-- with the host's real Prepare (`host = true`), which opens the panel and shows the strips.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

local WIDGETS = "LibKa0s-Widgets-1.0"
local PANEL_NAME = "KickCDSimPanel"   -- the library's `<name>SimPanel` (Sim document, `name`)
local LINE = "Simulation: %s - /kcd sim stop ends it."

--- A fresh, locked environment with the `test` scenario injected (not started), the clock off zero
--- and the Widgets mode-strip constructor spied: ctx = { env, NS, W, calls }.
local function ready(mutateProfile)
    local env = S.load()
    env.advance(100)
    local NS = env.NS
    NS.db.profile.locked = true
    if mutateProfile then mutateProfile(NS.db.profile) end
    S.testSession(env, { { kind = "Noop", label = "Noop" }, { kind = "Noop", label = "Noop" } },
        { host = true, start = false })
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

local function panelFrame(ctx) return ctx.env.mocks.__frames and (function()
    for _, f in ipairs(ctx.env.mocks.__frames) do
        if f.GetName and f:GetName() == PANEL_NAME then return f end
    end
end)() end

local function special(ctx, name)
    for _, n in ipairs(ctx.env.mocks.UISpecialFrames or {}) do if n == name then return true end end
    return false
end

local function gridOf(NS, unit) return NS:GetModule("IconGrid"):GetGridFrame(unit) end
local function barOf(NS, unit) return NS:GetModule("Castbar"):GetCastbarFrame(unit) end

--- The W.TestStrip call that built the strip parented to `parent`, or nil.
local function callFor(ctx, parent)
    for _, c in ipairs(ctx.calls) do if c.parent == parent then return c end end
    return nil
end

local function configChanged(NS, section)
    NS:SendMessage(NS.MSG.CONFIG_CHANGED, { section = section })
end

-- ── the module ──────────────────────────────────────────────────────────────

test("sim marker: modules/SimStrip.lua loads straight after modules/SimScenario.lua, before Diagnostics", function()
    -- red under: D-13's removal (no module, no TOC line)
    local ctx = ready()
    assertTrue(ctx.NS.SimStrip ~= nil, "NS.SimStrip is not defined")
    local at
    for i, rel in ipairs(T.tocFiles) do if rel == "modules/SimScenario.lua" then at = i end end
    assertTrue(at ~= nil, "modules/SimScenario.lua is not in KickCD.toc")
    assertEqual(T.tocFiles[at + 1], "modules/SimStrip.lua")
    assertEqual(T.tocFiles[at + 2], "modules/Diagnostics.lua")
end)

test("sim marker: the strip's line is in the locale", function()
    local ctx = ready()
    assertEqual(rawget(ctx.NS.L, LINE), LINE)
end)

test("sim marker: idle, no strip is built and no bus target is held", function()
    local ctx = ready()
    assertEqual(#ctx.calls, 0, "a strip was built while idle")
    assertNil(next(ctx.NS.SimStrip.__strips), "an idle addon holds no strip")
    assertNil(ctx.NS.SimStrip.__bus, "an idle addon holds no strip bus target")
end)

-- ── the start: one docked strip per grid ────────────────────────────────────

test("sim marker: a start shows a cyan strip docked on each enabled grid's top edge, parented to it", function()
    -- red under: D-13 (no strip at a start), or a strip parented to UIParent and anchored by hand
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    for _, unit in ipairs({ "target", "focus" }) do
        local grid = gridOf(NS, unit)
        local c = callFor(ctx, grid)
        assertTrue(c ~= nil, unit .. ": no strip was built on the grid")
        assertEqual(c.opts.kind, "sim", unit .. ": not the sim flavor")
        assertEqual(c.opts.dock, "hud", unit .. ": the strip is not HUD-docked")
        assertEqual(c.opts.target, grid, unit .. ": the dock's target is not the grid")
        assertEqual(c.opts.owner, "KickCD", unit .. ": the strip wears no skin owner")
        assertEqual(c.opts.icon, NS.Icon("info"))
        local strip = NS.SimStrip.__strips[unit .. ":icons"]
        assertTrue(strip ~= nil and strip:IsShown(), unit .. ": the strip is not shown")
        assertEqual(strip.kind, "sim")
        assertEqual(strip.text:GetText(), NS.L[LINE]:format("Test"))
        assertEqual(strip:GetParent(), grid, unit .. ": the strip is not parented to its grid")
        local p = strip.__points and strip.__points[1]
        assertTrue(p ~= nil and p.relativeTo == grid, unit .. ": the strip is not anchored on the grid")
        assertTrue(type(strip.Place) == "function", unit .. ": the strip was never docked (no strip:Place)")
    end
    stop(ctx)
end)

test("sim marker: with the label above the grid, the grid's strip stacks clear of the label", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local above = NS:GetModule("UnitLabel"):FrameAbove("target", "icons")
    assertTrue(above ~= nil, "sanity: the default profile shows the label above the grid")
    assertEqual(NS.SimStrip.__strips["target:icons"].__dock.clear, above)
    stop(ctx)
end)

test("sim marker: with no label above the grid, an anchored cast bar is what the strip clears", function()
    local ctx = ready(function(p) p.units.target.label.show = false end)
    start(ctx)
    local NS = ctx.NS
    assertEqual(NS.Units.Castbar("target").anchorMode or "PRIMARY", "PRIMARY", "sanity: the default bar is anchored")
    assertEqual(NS.SimStrip.__strips["target:icons"].__dock.clear, barOf(NS, "target"))
    stop(ctx)
end)

-- A label attached to an anchored cast bar's TOP sits beyond the bar: clearing the bar alone would
-- lay the grid's strip over the label (preview-mode: the strip covers nothing).
test("sim marker: with the label above an anchored cast bar, the grid's strip stacks clear of that label", function()
    local ctx = ready(function(p) p.units.target.label.style.attach = "castbar" end)
    start(ctx)
    local NS = ctx.NS
    assertNil(NS:GetModule("UnitLabel"):FrameAbove("target", "icons"), "sanity: no label above the grid")
    local above = NS:GetModule("UnitLabel"):FrameAbove("target", "castbar")
    assertTrue(above ~= nil, "sanity: the label sits above the cast bar")
    assertEqual(NS.Units.Castbar("target").anchorMode or "PRIMARY", "PRIMARY", "sanity: the default bar is anchored")
    assertEqual(NS.SimStrip.__strips["target:icons"].__dock.clear, above)
    stop(ctx)
end)

test("sim marker: with the label on an anchored cast bar but not above it, the bar is what the strip clears", function()
    local ctx = ready(function(p)
        p.units.target.label.style.attach = "castbar"
        p.units.target.label.style.relPoint = "CENTER"
    end)
    start(ctx)
    local NS = ctx.NS
    assertNil(NS:GetModule("UnitLabel"):FrameAbove("target", "castbar"), "sanity: the label is not above the bar")
    assertEqual(NS.SimStrip.__strips["target:icons"].__dock.clear, barOf(NS, "target"))
    stop(ctx)
end)

-- ── the cast bar ────────────────────────────────────────────────────────────

test("sim marker: a cast bar anchored to its grid carries no strip of its own", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local strip = NS.SimStrip.__strips["target:castbar"]
    assertTrue(strip == nil or not strip:IsShown(), "an anchored cast bar shows a second strip")
    stop(ctx)
end)

test("sim marker: a free cast bar carries its own strip, docked on it and parented to it", function()
    -- red under: a strip only on the grids
    local ctx = ready(function(p) p.units.target.castbar.anchorMode = "FREE" end)
    start(ctx)
    local NS = ctx.NS
    local bar = barOf(NS, "target")
    assertTrue(bar ~= nil, "sanity: the target's cast bar frame exists")
    local c = callFor(ctx, bar)
    assertTrue(c ~= nil, "no strip was built on the free cast bar")
    assertEqual(c.opts.dock, "hud")
    assertEqual(c.opts.target, bar)
    assertEqual(c.opts.kind, "sim")
    local strip = NS.SimStrip.__strips["target:castbar"]
    assertTrue(strip:IsShown(), "the free cast bar's strip is not shown")
    assertEqual(strip:GetParent(), bar)
    assertTrue(NS.SimStrip.__strips["target:icons"].__dock.clear ~= bar,
        "a free bar is the grid strip's clear frame")
    stop(ctx)
end)

test("sim marker: a CONFIG_CHANGED mid-session re-docks: a bar set free gains its strip", function()
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    NS.db.profile.units.target.castbar.anchorMode = "FREE"
    configChanged(NS, "castbar")
    local strip = NS.SimStrip.__strips["target:castbar"]
    assertTrue(strip ~= nil and strip:IsShown(), "the bar set free mid-session carries no strip")
    NS.db.profile.units.target.castbar.anchorMode = "PRIMARY"
    configChanged(NS, "castbar")
    assertFalse(strip:IsShown(), "the bar anchored again kept its strip")
    stop(ctx)
end)

-- ── the display hides, the strip hides with it ──────────────────────────────

test("sim marker: a grid hidden between casts hides its strip with it, and the panel stays", function()
    -- D-13's cyan bar over nothing: the strip rides its display's visibility now
    local ctx = ready()
    start(ctx)
    local NS = ctx.NS
    local grid, strip = gridOf(NS, "target"), NS.SimStrip.__strips["target:icons"]
    grid:Hide()
    assertTrue(strip:IsShown(), "the strip's own shown flag is the host's, kept for the session")
    assertFalse(strip:IsVisible(), "the strip stays visible over a hidden grid")
    grid:Show()
    assertTrue(strip:IsVisible(), "the strip did not come back with its grid")
    assertTrue(NS.Sim:IsPanelShown(), "the step panel went away")
    stop(ctx)
end)

test("sim marker: a disabled unit's grid carries no shown strip", function()
    local ctx = ready(function(p)
        p.units.target.enabled = false
        p.units.target.label.show = false
    end)
    start(ctx)
    local strip = ctx.NS.SimStrip.__strips["target:icons"]
    assertTrue(strip == nil or not strip:IsShown(), "a disabled grid carries a strip")
    assertTrue(ctx.NS.SimStrip.__strips["focus:icons"]:IsShown(), "the focus grid lost its strip")
    stop(ctx)
end)

test("sim marker: the strip's level is the library's (display + 5): no HUD.MARKER slot", function()
    local ctx = ready()
    assertNil(ctx.NS.Const.LAYERS.LEVEL.HUD.MARKER, "a host-owned marker slot came back")
end)

-- ── the stop ────────────────────────────────────────────────────────────────

test("sim marker: a stop hides every strip and releases the bus", function()
    local ctx = ready(function(p) p.units.target.castbar.anchorMode = "FREE" end)
    start(ctx)
    local NS = ctx.NS
    local bus = NS.SimStrip.__bus
    local reg = ctx.env.mocks.__msgRegistry
    assertTrue(bus ~= nil, "the strips subscribed through no bus target")
    assertTrue(reg[NS.MSG.GRID_LAYOUT] and reg[NS.MSG.GRID_LAYOUT][bus] ~= nil, "sanity: subscribed while shown")
    stop(ctx)
    for key, strip in pairs(NS.SimStrip.__strips) do
        assertFalse(strip:IsShown(), key .. "'s strip outlived the session")
    end
    for _, msg in ipairs({ NS.MSG.GRID_LAYOUT, NS.MSG.CONFIG_CHANGED }) do
        assertNil(reg[msg] and reg[msg][bus], msg .. " is still registered after the stop")
    end
end)

test("sim marker: without the library's strip, no error, and the panel marks the session", function()
    local ctx = ready()
    ctx.W.TestStrip = nil
    start(ctx)
    assertTrue(ctx.NS.Sim:IsActive(), "the session did not run without the strip")
    assertNil(next(ctx.NS.SimStrip.__strips), "a strip was built with no constructor")
    assertTrue(ctx.NS.Sim:IsPanelShown(), "the panel does not mark the session")
    stop(ctx)
end)

-- ── the step panel stays (preview-mode: the strip does not replace it) ──────

test("sim marker: a start opens the step panel with no close mark", function()
    -- red under: the panel built with its close mark showing
    local ctx = ready()
    start(ctx)
    assertTrue(ctx.NS.Sim:IsPanelShown(), "the step panel stays on screen for the session")
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

-- ── after the stop, the panel is an ordinary window again ───────────────────

test("sim marker: a stop gives the idle panel its close mark back", function()
    -- red under: Host.PinPanel never reversed, so the idle picker the library leaves open after a
    -- stop has no close mark for the rest of the UI session
    local ctx = ready()
    start(ctx)
    stop(ctx)
    local f = panelFrame(ctx)
    assertTrue(f ~= nil, "the panel frame is " .. PANEL_NAME)
    assertTrue(f.closeButton ~= nil and f.closeButton:IsShown(), "the close mark is still hidden")
end)

test("sim marker: a stop puts the panel back on UISpecialFrames, once", function()
    -- red under: the name left off UISpecialFrames, so Escape no longer closes the idle panel
    local ctx = ready()
    start(ctx)
    stop(ctx)
    assertTrue(special(ctx, PANEL_NAME), "the panel is not back on UISpecialFrames")
    start(ctx)
    assertFalse(special(ctx, PANEL_NAME), "a second session did not pin the panel again")
    stop(ctx)
    local n = 0
    for _, name in ipairs(ctx.env.mocks.UISpecialFrames or {}) do
        if name == PANEL_NAME then n = n + 1 end
    end
    assertTrue(n == 1, "the panel is on UISpecialFrames " .. n .. " times")
end)
