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
    Helpers.Set("castbar.interruptible.barColor", "castbar", { 1, 0.5, 0, 1 })
    inst.mocks.__flushTimers()
    assertTrue(NS.DebugLog:FindLine("{1,0.5,0,1}"), "RGBA renders as {r,g,b,a}")
end)
