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

test("GetSpecializationInfo(nil) answers nil without calling the client", function()
    -- LibKa0s-Compat-1.0 guards the index for every consumer; core/Util.lua already refused to
    -- pass a nil, so this only moves the guard into the seam.
    -- red under: calling the client's GetSpecializationInfo with the nil index
    local inst = T.load(false)
    local called = false
    inst.mocks.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() called = true; return 250, "Called" end,
    }
    assertEqual(select("#", inst.NS.Compat.GetSpecializationInfo(nil)), 1)
    assertEqual(inst.NS.Compat.GetSpecializationInfo(nil), nil)
    assertEqual(called, false)
end)

-- ── LibKa0s-Compat-1.0 absent ───────────────────────────────────────────────
--
-- A REAL library-less load (testing-§8), with every client rung present, so a reader that still
-- called the client would answer something other than the absent value.

--- Every client rung the routed readers could reach, answering something non-absent.
local function fullClient(mocks)
    mocks.C_Spell = mocks.C_Spell or {}
    mocks.C_Spell.GetSpellInfo = function() return { name = "Kick", iconID = 7, spellID = 1766 } end
    mocks.C_Spell.GetSpellTexture = function() return 111 end
    mocks.C_Spell.GetSpellCooldown = function() return { startTime = 1, duration = 9, isActive = true } end
    mocks.C_SpecializationInfo = {
        GetSpecialization = function() return 2 end,
        GetSpecializationInfo = function() return 250, "Blood" end,
    }
end

test("with LibKa0s absent, every routed reader answers the major's absent value", function()
    -- red under: a reader stub that re-implements the top rung instead of answering absent
    local inst = T.load(false, false, nil, { libFiles = {} })
    assertTrue(inst.mocks.LibStub("LibKa0s-Compat-1.0", true) == nil,
        "the degraded load registered LibKa0s-Compat-1.0; the empty file list did not take")
    fullClient(inst.mocks)
    local C = inst.NS.Compat
    assertEqual(select("#", C.GetSpellInfo(1766)), 1); assertEqual(C.GetSpellInfo(1766), nil)
    assertEqual(select("#", C.GetSpellTexture(1766)), 1); assertEqual(C.GetSpellTexture(1766), nil)
    assertEqual(select("#", C.GetSpecialization()), 1); assertEqual(C.GetSpecialization(), nil)
    assertEqual(select("#", C.GetSpecializationInfo(1)), 1); assertEqual(C.GetSpecializationInfo(1), nil)
    local n = select("#", C.GetSpellCooldown(1766))
    local s, d, e, m, active = C.GetSpellCooldown(1766)
    assertEqual(n, 5)
    assertEqual(s, 0); assertEqual(d, 0); assertEqual(e, false); assertEqual(m, 1); assertEqual(active, false)
end)

test("with LibKa0s absent, the IsSecret guard answers what the library answers", function()
    -- The guard arm re-implements the body: "library absent" is not "no secrets on this client".
    -- red under: a guard stub of `function() return false end`
    local live = T.load(false)
    local degraded = T.load(false, false, nil, { libFiles = {} })
    local secret = {}
    local fixture = function(v) if rawequal(v, secret) then return 1 end end
    for _, inst in ipairs({ live, degraded }) do inst.mocks.issecretvalue = fixture end
    for _, v in ipairs({ secret, 42, "Kick" }) do
        assertEqual(degraded.NS.Compat.IsSecret(v), live.NS.Compat.IsSecret(v))
    end
    assertEqual(degraded.NS.Compat.IsSecret(secret), true)
    assertEqual(degraded.NS.Compat.IsSecret(nil), live.NS.Compat.IsSecret(nil))
    live.mocks.issecretvalue, degraded.mocks.issecretvalue = nil, nil
    assertEqual(degraded.NS.Compat.IsSecret(secret), false)
    assertEqual(degraded.NS.Compat.IsSecret(secret), live.NS.Compat.IsSecret(secret))
end)
