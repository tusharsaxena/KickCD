-- tests/test_flow_traces.lua — §8 flow traces reachable headlessly
local T = _G.KICKCD_TEST
local test, assertTrue = T.test, T.assertTrue

test("OnProfileChanged logs a [Profile] line", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Database = NS.Database
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    Database:OnProfileChanged(nil, NS.db, "Raider")
    -- FindLine (not LastLine): OnProfileChanged's own SendMessage synchronously
    -- fans out to downstream subscribers (e.g. Cooldowns:Rebuild), which may
    -- log their own line after ours. We only assert OUR trace was emitted.
    assertTrue(NS.DebugLog:FindLine("[Profile] switched to 'Raider'"),
        "profile switch logs a [Profile] line naming the key")
    NS.State.debug = false   -- leave the shared/fresh instance clean
end)
