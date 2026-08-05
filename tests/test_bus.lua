-- tests/test_bus.lua — message bus keyed by (message, target) (architecture-§4 / AP-33)
--
-- The whole point: two receivers of ONE message, each on its OWN target,
-- must BOTH fire. A no-op or single-slot mock would hide the last-registrant-
-- wins clobber this addon's Spells panel was vulnerable to (KCD-09).
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("AceEvent mock fans one message out to two distinct targets", function()
    local inst = T.load(false)
    local AceEvent = inst.mocks.__libs["AceEvent-3.0"]

    local a, b = {}, {}
    AceEvent:Embed(a)
    AceEvent:Embed(b)

    local gotA, gotB = nil, nil
    a:RegisterMessage("Test_Msg", function(_, payload) gotA = payload end)
    b:RegisterMessage("Test_Msg", function(_, payload) gotB = payload end)

    a:SendMessage("Test_Msg", 42)
    assertEqual(gotA, 42, "receiver A must fire")
    assertEqual(gotB, 42, "receiver B (separate target) must ALSO fire")
end)

test("Two receivers on the SAME target clobber (proves keying is by target)", function()
    local inst = T.load(false)
    local AceEvent = inst.mocks.__libs["AceEvent-3.0"]
    local shared = {}
    AceEvent:Embed(shared)

    local firstFired, secondFired = false, false
    shared:RegisterMessage("Dup_Msg", function() firstFired = true end)
    shared:RegisterMessage("Dup_Msg", function() secondFired = true end)  -- overwrites
    shared:SendMessage("Dup_Msg")
    -- Only the last registrant on a single target survives — this is exactly
    -- the clobber the receiver rule forbids; asserting it locks in the mock's
    -- (message, target) semantics.
    assertFalse(firstFired, "first registrant on a shared target is clobbered")
    assertTrue(secondFired, "last registrant on a shared target must be the survivor")
end)

test("Addon SendMessage reaches a registered module target", function()
    local inst = T.load(true)
    local NS = inst.NS
    local target = NS.NewBusTarget and NS.NewBusTarget()
    if not target then
        -- NewBusTarget lands in Sprint 3 (KCD-09); until then, exercise the
        -- addon object's own embed so the bus path is still covered.
        target = {}
        inst.mocks.__libs["AceEvent-3.0"]:Embed(target)
    end
    local got = false
    target:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED", function() got = true end)
    NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "test" })
    assertTrue(got, "a private target must receive the addon's broadcast")
end)

test("NewBusTarget gives each receiver its own target — both fire (KCD-09)", function()
    local inst = T.load(true)
    local NS = inst.NS
    assertTrue(type(NS.NewBusTarget) == "function", "NewBusTarget factory must exist")

    -- Two independent consumers (e.g. the Spells panel + a module) each own a
    -- private target; a single broadcast must reach BOTH.
    local a = NS.NewBusTarget()
    local b = NS.NewBusTarget()
    assertTrue(a ~= b, "each NewBusTarget must be a distinct table")
    local gotA, gotB = false, false
    a:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", function() gotA = true end)
    b:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", function() gotB = true end)
    NS:SendMessage("Ka0s_KickCD_PROFILE_CHANGED", { newProfileKey = "Default" })
    assertTrue(gotA, "receiver A (private target) must fire")
    assertTrue(gotB, "receiver B (private target) must ALSO fire")
end)
