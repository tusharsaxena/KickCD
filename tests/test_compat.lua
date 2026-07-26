-- tests/test_compat.lua — deprecated-API routing through core/Compat.lua (KCD-10)
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local Compat = NS.Compat

test("Compat exposes the spec shims", function()
    assertTrue(type(Compat.GetSpecialization) == "function")
    assertTrue(type(Compat.GetSpecializationInfo) == "function")
end)

test("GetSpecialization prefers C_SpecializationInfo", function()
    assertEqual(Compat.GetSpecialization(), 1)
end)

test("GetSpecializationInfo passes the multi-return through", function()
    local id, name = Compat.GetSpecializationInfo(1)
    assertEqual(id, 253)
    assertEqual(name, "Beast Mastery")
end)

test("GetSpecialization falls back to the deprecated global when C_ is absent", function()
    local inst = T.load(false)
    inst.mocks.C_SpecializationInfo = nil
    inst.mocks.GetSpecialization = function() return 7 end
    assertEqual(inst.NS.Compat.GetSpecialization(), 7)
end)

test("GetSpecializationInfo falls back to the deprecated global when C_ is absent", function()
    local inst = T.load(false)
    inst.mocks.C_SpecializationInfo = nil
    inst.mocks.GetSpecializationInfo = function(i) return 100 + i, "Fallback" end
    local id, name = inst.NS.Compat.GetSpecializationInfo(3)
    assertEqual(id, 103)
    assertEqual(name, "Fallback")
end)
