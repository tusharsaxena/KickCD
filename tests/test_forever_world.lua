-- tests/test_forever_world.lua -- the WoW Forever mock world itself (tests/wow_mock_forever.lua;
-- MKF-KC-02, the Forever port design 3.2, critic C5).
--
-- These cases pin the world's shape, not the addon's behavior in it: the later port items test
-- KickCD against this world, and each of them is only as good as the world is faithful. Every case
-- loads with `{ world = "forever" }`, so each runs the same on both kit profiles.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local W = T.foreverWorld

local function forever(mutate)
    return T.load(false, false, mutate, { world = "forever" })
end

test("Forever world: the instance is a WoW Forever client on both kit profiles", function()
    local inst = forever()
    assertEqual(inst.NS.Compat.ClientKey(), "forever")
    assertTrue(inst.NS.Compat.IsForever())
    assertFalse(inst.NS.Compat.IsRetail())
end)

test("Forever world: nine classes at their real ids, and a 1..GetNumClasses loop loses Druid", function()
    local m = forever().mocks
    local ids = m.C_SpecializationInfo.GetAllClassIDs()
    assertEqual(table.concat(ids, ","), "1,2,3,4,5,7,8,9,11")
    for _, id in ipairs(ids) do
        local name, file, back = m.GetClassInfo(id)
        assertEqual(file, W.CLASSES[id][1], "class " .. id)
        assertEqual(name, W.CLASSES[id][2], "class " .. id)
        assertEqual(back, id)
    end
    assertNil(m.GetClassInfo(6), "no Death Knight")
    assertNil(m.GetClassInfo(10), "no Monk")
    -- The count is UNKNOWN on Forever (factcheck 24); the world takes the shape that drops a class.
    local seen = {}
    for id = 1, m.GetNumClasses() do
        local _, file = m.GetClassInfo(id)
        if file then seen[file] = true end
    end
    assertNil(seen.DRUID, "the trap a class loop falls into")
end)

test("Forever world: one spec per class at its real id, named for the class", function()
    local m = forever().mocks
    local want = { [1] = 1491, [2] = 1486, [3] = 1485, [4] = 1488, [5] = 1487, [7] = 1489,
                   [8] = 1482, [9] = 1490, [11] = 1484 }
    for classID, specID in pairs(want) do
        assertEqual(m.C_SpecializationInfo.GetNumSpecializationsForClassID(classID), 1, "class " .. classID)
        local id, name, _, icon, role = m.GetSpecializationInfoForClassID(classID, 1)
        assertEqual(id, specID, "class " .. classID)
        assertEqual(name, W.CLASSES[classID][2], "the spec is named for the class")
        assertNil(icon, "the runtime answer carries no icon")
        assertEqual(role, "DAMAGER")
        assertNil((m.GetSpecializationInfoForClassID(classID, 2)), "no second spec")
    end
end)

test("Forever world: the player is a Hunter at 1485 until a case makes it another class", function()
    local inst = forever()
    assertEqual(inst.NS.Util.PlayerSpecID(), 1485)
    assertEqual(select(2, inst.mocks.UnitClass("player")), "HUNTER")
    local warrior = forever(function(m) m.__setForeverClass("WARRIOR") end)
    assertEqual(warrior.NS.Util.PlayerSpecID(), 1491)
    assertEqual(select(3, warrior.mocks.UnitClass("player")), 1)
end)

test("Forever world: the spec count is the namespaced member only; the bare spec globals are absent", function()
    local m = forever().mocks
    assertNil(m.GetNumSpecializationsForClassID, "the bare global")
    assertNil(m.GetSpecialization, "the bare global")
    assertNil(m.GetSpecializationInfo, "the bare global")
    assertEqual(type(m.C_SpecializationInfo.GetNumSpecializationsForClassID), "function")
    assertEqual(type(m.GetSpecializationInfoForClassID), "function", "this one stays global on Forever")
end)

test("Forever world: C_SpellBook knows each rank only once it is taught, per bank", function()
    local m = forever().mocks
    local SB = m.C_SpellBook
    assertFalse(SB.IsSpellKnown(6552, 0), "nothing is known until a case teaches it")
    m.__learn({ 6554 })
    assertTrue(SB.IsSpellKnown(6554, 0), "Pummel rank 2")
    assertFalse(SB.IsSpellKnown(6552, 0), "rank 1 is its own id")
    assertTrue(SB.IsSpellInSpellBook(6554, 0, false))
    m.__learn({ 19244 }, 1)
    assertTrue(SB.IsSpellInSpellBook(19244, m.Enum.SpellBookSpellBank.Pet, false), "the Felhunter's Spell Lock")
    assertFalse(SB.IsSpellKnown(19244, m.Enum.SpellBookSpellBank.Player), "a pet spell is not the player's")
    m.__unlearn({ 19244 }, 1)
    assertFalse(SB.IsSpellInSpellBook(19244, 1, false), "the pet is dismissed")
end)

test("Forever world: the deprecated spellbook shims are absent", function()
    local m = forever().mocks
    assertNil(m.IsPlayerSpell)
    assertNil(m.IsSpellKnown)
    assertNil(m.IsSpellKnownOrOverridesKnown)
end)

test("Forever world: there is no global cooldown spell 61304", function()
    local m = forever().mocks
    assertNil(m.C_Spell.GetSpellCooldown(61304))
    assertNil(m.C_Spell.GetSpellInfo(61304))
    assertTrue(m.C_Spell.GetSpellCooldown(6552) ~= nil, "a real spell still answers")
end)

test("Forever world: a character is First Surname", function()
    local inst = forever()
    assertTrue(inst.NS.Compat.RegionalNames())
    assertEqual((inst.NS.Compat.UnitCharacterName("player")), "Mock Mockwood")
end)

test("Forever world: a typed secret answers its underlying type and reads secret", function()
    local inst = forever()
    local s = T.secret(true)
    assertEqual(inst.mocks.type(s), "boolean", "a secret's type is its underlying type")
    assertEqual(inst.mocks.type(T.secret("Kick")), "string")
    assertEqual(inst.mocks.type(7), "number", "a plain value is untouched")
    assertTrue(inst.NS.Compat.IsSecret(s))
    assertFalse(inst.NS.Compat.IsSecret(true))
end)

test("typed secrets install alone on a mock set of either client", function()
    local inst = T.load(false, false, T.typedSecrets)
    assertEqual(inst.mocks.type(T.secret(false)), "boolean")
    assertTrue(inst.NS.Compat.IsSecret(T.secret(false)))
    assertEqual(type(inst.mocks.C_SpellBook), "table", "both clients carry C_SpellBook")
    assertEqual(inst.mocks.Enum.SpellBookSpellBank.Pet, 1)
end)
