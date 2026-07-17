-- tests/test_settings_log.lua — settings-change capture at Helpers.Set (§10)
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("Helpers.Set logs one debounced [Set] line with the settled value", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()

    -- Two rapid writes to the same path within the debounce window. NOTE:
    -- with the full lifecycle enabled (T.load(true, true)), a "general"
    -- CONFIG_CHANGED also triggers Cooldowns:Rebuild(), which logs its own
    -- synchronous "[Cooldowns] rebuild ..." line on every Set call — that's
    -- pre-existing, unrelated module behavior, not the debounced [Set] line
    -- under test here. Assertions below key off the "[Set]"-tagged line
    -- specifically (via FindLine) rather than raw BufferSize()/LastLine(),
    -- so this suite stays robust to that orthogonal noise.
    Helpers.Set("locked", "general", false)
    Helpers.Set("locked", "general", true)
    assertTrue(not NS.DebugLog:FindLine("[Set]"), "nothing [Set]-tagged logs before the debounce fires")

    inst.mocks.__flushTimers()
    assertTrue(NS.DebugLog:FindLine("[Set] locked = true"), "settled value is logged after the debounce fires")
    assertTrue(not NS.DebugLog:FindLine("[Set] locked = false"),
        "burst collapses to one [Set] line; the earlier value must not appear")
end)

test("Helpers.Set formats an RGBA table compactly", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    Helpers.Set("units.target.castbar.interruptible.barColor", "castbar", { 1, 0.5, 0, 1 })
    inst.mocks.__flushTimers()
    assertTrue(NS.DebugLog:FindLine("{1,0.5,0,1}"), "RGBA renders as {r,g,b,a}")
end)

test("ResetIconPosition restores units.target.anchors.icons to the default (Task 8 fix)", function()
    local inst = T.load(true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers

    -- Simulate the user having dragged the target grid away from default.
    NS.db.profile.units.target.anchors.icons = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 400, y = -300 }

    Helpers.ResetIconPosition()

    local d = NS.DEFAULT_PROFILE.units.target.anchors.icons
    local a = NS.db.profile.units.target.anchors.icons
    assertEqual(a.point, d.point, "point restored to default")
    assertEqual(a.relativePoint, d.relativePoint, "relativePoint restored to default")
    assertEqual(a.x, d.x, "x restored to default")
    assertEqual(a.y, d.y, "y restored to default")
end)

test("ResetAll (via ResetAllPositions) restores both units' icons+castbar anchors to default (resetall bug fix)", function()
    local inst = T.load(true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers

    -- Simulate the user having dragged every grid away from default, for
    -- both units and both anchor kinds.
    local garbage = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 999, y = -999 }
    NS.db.profile.units.target.anchors.icons   = { point = garbage.point, relativePoint = garbage.relativePoint, x = garbage.x, y = garbage.y }
    NS.db.profile.units.target.anchors.castbar = { point = garbage.point, relativePoint = garbage.relativePoint, x = garbage.x, y = garbage.y }
    NS.db.profile.units.focus.anchors.icons    = { point = garbage.point, relativePoint = garbage.relativePoint, x = garbage.x, y = garbage.y }
    NS.db.profile.units.focus.anchors.castbar  = { point = garbage.point, relativePoint = garbage.relativePoint, x = garbage.x, y = garbage.y }

    -- Unit under test: ResetAllPositions directly (ResetAll also resets
    -- spells, which is heavier than this test needs).
    Helpers.ResetAllPositions()

    for _, unit in ipairs({ "target", "focus" }) do
        for _, which in ipairs({ "icons", "castbar" }) do
            local d = NS.DEFAULT_PROFILE.units[unit].anchors[which]
            local a = NS.db.profile.units[unit].anchors[which]
            assertEqual(a.point, d.point, unit .. "." .. which .. " point restored to default")
            assertEqual(a.relativePoint, d.relativePoint, unit .. "." .. which .. " relativePoint restored to default")
            assertEqual(a.x, d.x, unit .. "." .. which .. " x restored to default")
            assertEqual(a.y, d.y, unit .. "." .. which .. " y restored to default")
        end
    end
end)

test("ResetAll (via RestoreUnitLinks) restores each unit's link flag to default (link reset bug fix)", function()
    local inst = T.load(true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers

    -- `link` is not a schema row, so RestoreAllDefaults can't reach it: an
    -- unlinked Focus would otherwise survive a full reset and silently lose
    -- the mirror-Target relationship. Simulate the user having unlinked Focus.
    NS.db.profile.units.focus.link  = false
    NS.db.profile.units.target.link = true   -- garbage: target is never linked

    Helpers.RestoreUnitLinks()

    assertEqual(NS.db.profile.units.focus.link,
        NS.DEFAULT_PROFILE.units.focus.link, "focus link restored to default (true)")
    assertEqual(NS.db.profile.units.target.link,
        NS.DEFAULT_PROFILE.units.target.link, "target link restored to default (false)")
end)
