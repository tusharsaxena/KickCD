-- tests/test_spec_reads.lua -- the spec reads both clients share (MKF-KC-04, the WoW Forever port).
--
-- Two Retail-invisible fixes, each red before its change:
--   * the spec count comes from the namespaced C_SpecializationInfo.GetNumSpecializationsForClassID.
--     The bare global is Blizzard_DeprecatedSpecialization's alias of that member, loaded on Retail
--     only while the CVar loadDeprecationFallbacks is on and not at all on WoW Forever (its TOC
--     allows `classic, standard`), so the spec names, the editor's spec order and the spec icons came
--     up empty there;
--   * a spec id of 0 or less is no spec. GetSpecializationInfo's documented default is 0, which a
--     `type == "number"` test let through as a storage key.
-- GetSpecializationInfoForClassID stays the client global it is on both clients, read through
-- NS.Compat like every other client read.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

-- ── the spec id ─────────────────────────────────────────────────────────────────────────────────

-- The Retail client whatever KA0S_KIT_CLIENT says (the stamp the loader would make, then Retail's).
local function retailClient(m)
    T.Loader.makeEnv(m)
    T.Loader.MockClient.apply(m, "retail")
end

test("PlayerSpecID: a spec id of 0 is no spec; on WoW Forever the class's one spec stands in", function()
    -- MKF-KC-13 (the synthesis 3.4 "Spec"): a Forever class has exactly one spec, so an early or
    -- default answer falls back to it rather than emptying the grid; Retail has no such fallback.
    local function zero(m) m.C_SpecializationInfo.GetSpecializationInfo = function() return 0, "", "", nil, "NONE" end end
    local retail = T.load(false, false, function(m) retailClient(m); zero(m) end)
    assertNil(retail.NS.Util.PlayerSpecID(), "retail: the documented default 0")
    local forever = T.load(false, false, zero, { world = "forever" })
    assertEqual(forever.NS.Util.PlayerSpecID(), 1485, "forever: the Hunter's one spec")
end)

test("PlayerSpecID: a negative spec id is no spec either", function()
    local inst = T.load(false, false, function(m)
        retailClient(m)
        m.C_SpecializationInfo.GetSpecializationInfo = function() return -1 end
    end)
    assertNil(inst.NS.Util.PlayerSpecID())
end)

test("PlayerSpecID: a real spec id still answers, on both clients", function()
    assertEqual(T.load(false, false).NS.Util.PlayerSpecID(), 253)
    assertEqual(T.load(false, false, nil, { world = "forever" }).NS.Util.PlayerSpecID(), 1485)
end)

-- ── the spec count ──────────────────────────────────────────────────────────────────────────────

test("spec count: NS.Compat reads the namespaced member, never the deprecated global", function()
    -- red under: a read of the bare GetNumSpecializationsForClassID
    local inst = T.load(false, false, function(m)
        m.C_SpecializationInfo.GetNumSpecializationsForClassID = function(classID) return classID == 3 and 3 or 0 end
        m.GetNumSpecializationsForClassID = function() error("the deprecated alias was read") end
    end)
    assertEqual(inst.NS.Compat.GetNumSpecializationsForClassID(3), 3)
    assertEqual(inst.NS.Compat.GetNumSpecializationsForClassID(6), 0)
end)

test("spec count: absent member answers 0, never raising", function()
    local inst = T.load(false, false, function(m)
        m.C_SpecializationInfo.GetNumSpecializationsForClassID = nil
    end)
    assertEqual(inst.NS.Compat.GetNumSpecializationsForClassID(3), 0)
end)

test("spec info by class: NS.Compat passes the client global's returns through", function()
    local inst = T.load(false, false)
    local id, name = inst.NS.Compat.GetSpecializationInfoForClassID(7, 2)
    assertEqual(id, 263)
    assertEqual(name, "Enhancement")
    inst.mocks.GetSpecializationInfoForClassID = nil
    assertNil((inst.NS.Compat.GetSpecializationInfoForClassID(7, 2)), "absent global: nil")
end)

test("spec names on WoW Forever come from the namespaced count: Warrior is 1491", function()
    -- red under: the bare-global gate, which answers no names at all on Forever
    local NS = T.load(false, false, nil, { world = "forever" }).NS
    assertEqual(NS.Util.SpecDisplayName(1491), "Warrior")
    assertEqual(NS.Util.SpecDisplayName(1485), "Hunter")
    local order = NS.Util.SpecOrderForClass("WARRIOR")
    assertTrue(order ~= nil, "the editor's spec order for Warrior")
    assertEqual(table.concat(order, ","), "1491")
end)

test("spec names on Retail keep Blizzard's order and localized names", function()
    local NS = T.load(false, false).NS
    assertEqual(NS.Util.SpecDisplayName(262), "Elemental")
    assertEqual(table.concat(NS.Util.SpecOrderForClass("SHAMAN"), ","), "262,263,264")
end)
