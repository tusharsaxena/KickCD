-- tests/test_cooldowns.lua — modules/Cooldowns.lua event coalescing
local T = _G.KICKCD_TEST
local test, assertEqual = T.test, T.assertEqual

test("SPELL_UPDATE_* burst coalesces to one Refresh per frame", function()
    -- Fresh enabled instance so Cooldowns:OnEnable has wired the coalescer.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")

    -- Drain any timers scheduled during load, then spy on Refresh.
    inst.mocks.__flushTimers()
    local refreshes = 0
    Cooldowns.Refresh = function() refreshes = refreshes + 1 end

    -- A same-frame burst of cooldown events must not re-poll synchronously.
    Cooldowns:OnCooldownEvent()
    Cooldowns:OnCooldownEvent()
    Cooldowns:OnCooldownEvent()
    assertEqual(refreshes, 0, "coalesced Refresh must not fire synchronously")

    -- Next frame: the burst collapses to exactly one Refresh.
    inst.mocks.__flushTimers()
    assertEqual(refreshes, 1, "burst must coalesce to a single Refresh")
end)
