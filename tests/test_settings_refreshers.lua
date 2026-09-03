-- tests/test_settings_refreshers.lua — the panel refresher registry's lifetime.
--
-- Regression suite for a settings-panel corruption caught in-game: the Unit
-- dropdown on Icons rendered ANCHOR-POINT values, and on Cast bar rendered
-- text-POSITION values.
--
-- Cause: `Helpers.ClearScroll` released the scroll's widgets back to AceGUI's
-- pool but never truncated `ctx.refreshers`. Every widget maker appends a
-- closure capturing its own widget, so after a rebuild the registry held
-- closures pointing at widgets AceGUI had already recycled into different
-- roles. The next `/kcd set` ran `RefreshAllPanels`, every stale closure fired,
-- and an old dropdown's refresher wrote its list and value onto whatever
-- widget object now occupied that slot.
--
-- The rebuild path is reached by ordinary use: switching the Unit dropdown,
-- ticking "Use same styling as Target", or pressing "Copy styling from
-- Target" all call `Helpers.RenderUnitPanel`, which clears and rebuilds.
--
-- These cases assert the registry's INVARIANT rather than the symptom: a
-- refresher may only exist while the widget it closes over is live. Every
-- registration site sits immediately after a `parent:AddChild(...)` inside the
-- scroll, so "the scroll was cleared" implies "no refresher is still valid".
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

--- A panel ctx with its scroll pre-seeded, matching the fixture in
--- tests/test_schema.lua: ensureScroll returns an existing ctx.scroll
--- immediately instead of anchoring a frame the AceGUI mock doesn't model.
local function panelCtx(name)
    local NS = T.NS
    local H = NS.Settings.Helpers
    local AceGUI = T.mocks.LibStub("AceGUI-3.0")
    local ctx = H.CreatePanel(name, name, { pageKey = "icons" })
    ctx.scroll = AceGUI:Create("ScrollFrame")
    return ctx, H
end

--- A couple of schema-shaped rows that exercise different widget makers, so
--- the registry actually gains entries.
local function rows()
    return {
        { panel = "icons", section = "icons", path = "scale",
          type = "number", label = "Scale", default = 1, min = 0, max = 2, step = 0.1 },
        { panel = "icons", section = "icons", path = "locked",
          type = "bool", label = "Locked", default = true },
    }
end

test("rendering rows registers refreshers", function()
    -- Precondition for everything below: if rendering stopped registering,
    -- the emptiness assertions would pass vacuously.
    local ctx, H = panelCtx("KickCDRefreshRegister")
    H.RenderRows(ctx, rows())
    assertTrue(#ctx.refreshers > 0,
        "rendering schema rows must register refreshers")
end)

test("ClearScroll empties the refresher registry", function()
    -- THE FIX. ReleaseChildren hands every widget back to AceGUI's pool, so
    -- every closure capturing one is dead the moment this returns.
    local ctx, H = panelCtx("KickCDRefreshClear")
    H.RenderRows(ctx, rows())
    assertTrue(#ctx.refreshers > 0, "precondition: refreshers registered")

    H.ClearScroll(ctx)

    assertEqual(#ctx.refreshers, 0,
        "ClearScroll must drop refreshers along with the widgets they capture")
end)

test("a clear-and-rebuild cycle does not grow the registry", function()
    -- The leak's observable signature: each rebuild appended a fresh set while
    -- keeping the dead ones, so the registry grew without bound and the
    -- proportion of stale entries climbed with every unit-dropdown switch.
    local ctx, H = panelCtx("KickCDRefreshGrowth")
    H.RenderRows(ctx, rows())
    local afterFirst = #ctx.refreshers

    for _ = 1, 3 do
        H.ClearScroll(ctx)
        H.RenderRows(ctx, rows())
    end

    assertEqual(#ctx.refreshers, afterFirst,
        "three rebuilds must leave the same number of refreshers, not 4x")
end)

test("RefreshAllPanels never runs a refresher from a cleared render", function()
    -- The corruption itself. A stale closure surviving into RefreshAllPanels is
    -- what wrote an anchor dropdown's list onto the recycled Unit dropdown.
    local NS = T.NS
    local ctx, H = panelCtx("KickCDRefreshStale")

    local staleRan = false
    H.RenderRows(ctx, rows())
    -- Stand in for a widget-capturing closure from this render pass.
    ctx.refreshers[#ctx.refreshers + 1] = function() staleRan = true end

    H.ClearScroll(ctx)
    H.RenderRows(ctx, rows())   -- rebuild: fresh widgets, fresh refreshers

    H.RefreshAllPanels()

    assertTrue(not staleRan,
        "a refresher registered before ClearScroll must not run afterwards")
    -- Guard against the lazy fix of never running any refresher at all.
    assertTrue(#ctx.refreshers > 0,
        "the rebuilt panel must still have live refreshers to run")
    assertTrue(NS.Settings._panels ~= nil, "panels registry must exist")
end)

test("ClearScroll is safe on a ctx that never rendered", function()
    local ctx, H = panelCtx("KickCDRefreshEmpty")
    H.ClearScroll(ctx)
    assertEqual(#ctx.refreshers, 0)
end)
