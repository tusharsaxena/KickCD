-- tests/test_seed_clients.lua -- seeding the spell lists per client (the WoW Forever port, MKF-KC-11;
-- the synthesis 3.4 "Profiles", lead call D9).
--
-- WoW Forever seeds from defaults/Spells_Forever.lua and its racial table, Retail from
-- defaults/Spells.lua as always. On Forever the seed is by ABSENT KEY: a class + spec pair the
-- profile does not hold is added, a pair it holds (even an emptied one) is never re-seeded, and a
-- Retail pair a profile carries from an out-of-date run is left in place, never deleted. The
-- customized count, the one-list reset and resetall read the running client's pairs only. Retail's
-- seeding, resets and count are byte-identical to before the port.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

local WARRIOR, ROGUE = 1491, 1488

local function ids(list)
    local out = {}
    for i, e in ipairs(list or {}) do out[i] = e.spellID end
    return table.concat(out, ",")
end

--- A Forever instance (OnInitialize run) whose player is `classFile` of `race`. With `stored`, the
--- profile's spells are then replaced by it and BuildSpells runs again: the next login of a profile
--- that holds exactly that table.
local function forever(classFile, race, stored)
    local inst = T.load(true, false, function(m)
        m.__setForeverClass(classFile or "WARRIOR")
        if race then m.UnitRace = function() return race, race end end
    end, { world = "forever" })
    if stored then
        inst.NS.db.profile.spells = stored
        inst.NS.Database:BuildSpells()
    end
    return inst
end

local function retailClient(m)
    T.Loader.makeEnv(m)
    T.Loader.MockClient.apply(m, "retail")
end

local function pairCount(spells)
    local n = 0
    for _, specs in pairs(spells) do
        for _ in pairs(specs) do n = n + 1 end
    end
    return n
end

-- ── WoW Forever ─────────────────────────────────────────────────────────────

test("Seed (Forever): a fresh profile holds the nine Forever lists and no Retail pair", function()
    local NS = forever("WARRIOR", "Human").NS
    local spells = NS.db.profile.spells
    assertEqual(pairCount(spells), 9, "one list per Forever class")
    for classFile, specID in pairs(NS.Const.SPEC_FOREVER) do
        local want = NS.DefaultSpellsForever[classFile][specID]
        assertEqual(ids(NS.Database:GetSpellList(classFile, specID)), ids(want), classFile)
    end
    assertNil(spells.DEATHKNIGHT, "no Retail-only class")
    assertNil(spells.WARRIOR[71], "no Retail Warrior spec")
end)

test("Seed (Forever): a profile an out-of-date run left gains the absent lists and keeps its Retail pairs", function()
    local stored = { WARRIOR = { [71] = { { spellID = 6552, category = "interrupt", enabled = true } } } }
    local NS = forever("WARRIOR", "Human", stored).NS
    local spells = NS.db.profile.spells
    assertEqual(ids(spells.WARRIOR[71]), "6552", "the Retail pair is left in place")
    assertEqual(ids(spells.WARRIOR[WARRIOR]), ids(NS.DefaultSpellsForever.WARRIOR[WARRIOR]),
        "the absent Forever pair is seeded")
    assertEqual(ids(spells.ROGUE[ROGUE]), ids(NS.DefaultSpellsForever.ROGUE[ROGUE]))
end)

test("Seed (Forever): a list the player emptied keeps its key and is never re-seeded", function()
    local stored = { WARRIOR = { [WARRIOR] = {} } }
    local inst = forever("WARRIOR", "Human", stored)
    local NS = inst.NS
    assertEqual(#NS.Database:GetSpellList("WARRIOR", WARRIOR), 0, "the emptied list stays empty")
    NS.Database:BuildSpells()
    assertEqual(#NS.Database:GetSpellList("WARRIOR", WARRIOR), 0, "and stays empty on the next login")
    assertTrue(#NS.Database:GetSpellList("ROGUE", ROGUE) > 0, "another class's absent list is seeded")
end)

test("Seed (Forever): a Tauren Warrior's War Stomp appears once", function()
    local NS = forever("WARRIOR", "Tauren").NS
    local n = 0
    for _, e in ipairs(NS.Database:GetSpellList("WARRIOR", WARRIOR)) do
        if e.spellID == 20549 then n = n + 1 end
    end
    assertEqual(n, 1)
end)

test("Seed (Forever): the racial comes from Forever's table", function()
    local NS = forever("WARRIOR", "Orc").NS
    for _, e in ipairs(NS.Database:GetSpellList("WARRIOR", WARRIOR)) do
        assertTrue(e.spellID ~= 33697 and e.spellID ~= 20572, "no Retail Blood Fury on Forever")
    end
end)

test("Seed (Forever): the customized count reads Forever's pairs only", function()
    local stored = { WARRIOR = { [71] = { { spellID = 1, category = "other", enabled = true } } } }
    local NS = forever("WARRIOR", "Human", stored).NS
    local customized, total = NS.Database:CountCustomizedSpellLists()
    assertEqual(customized, 0, "a stray Retail pair is not counted as customized")
    assertEqual(total, 9, "nor as stored")
    NS.Database:AddSpell("WARRIOR", WARRIOR, 100)
    customized = NS.Database:CountCustomizedSpellLists()
    assertEqual(customized, 1)
end)

test("Seed (Forever): a one-list reset restores Forever's list", function()
    local NS = forever("ROGUE", "Human").NS
    NS.Database:RemoveSpell("ROGUE", ROGUE, 1766)
    NS.Database:ResetSpellList("ROGUE", ROGUE)
    assertEqual(ids(NS.Database:GetSpellList("ROGUE", ROGUE)), ids(NS.DefaultSpellsForever.ROGUE[ROGUE]))
end)

test("Seed (Forever): resetall gives back Forever's nine lists and nothing else", function()
    -- The player asked for every list back, so a leftover Retail pair goes too (as on Retail,
    -- where resetall wipes the whole table); only the automatic load pass keeps what is stored.
    local stored = { WARRIOR = { [71] = { { spellID = 6552, category = "interrupt", enabled = true } } } }
    local NS = forever("WARRIOR", "Human", stored).NS
    NS.Database:RemoveSpell("WARRIOR", WARRIOR, 6552)
    NS.Database:ResetAllSpells()
    local spells = NS.db.profile.spells
    assertEqual(ids(spells.WARRIOR[WARRIOR]), ids(NS.DefaultSpellsForever.WARRIOR[WARRIOR]))
    assertNil(spells.WARRIOR[71], "the leftover Retail pair is gone")
    assertEqual(pairCount(spells), 9)
end)

-- ── Retail: byte for byte ───────────────────────────────────────────────────

test("Seed (Retail): the Retail lists are seeded and the Forever tables are never read", function()
    local inst = T.load(true, false, retailClient, { afterFile = { ["defaults/SpellRanks_Forever.lua"] = function(NS)
        local trap = setmetatable({}, { __index = function() error("Forever seed read on Retail") end })
        NS.DefaultSpellsForever, NS.RaceCastStoppersForever = trap, trap
    end } })
    local NS = inst.NS
    local spells = NS.db.profile.spells
    local want = 0
    for _, specs in pairs(NS.DefaultSpells) do
        for _ in pairs(specs) do want = want + 1 end
    end
    assertEqual(pairCount(spells), want, "every Retail pair")
    NS.Database:ResetAllSpells()
    NS.Database:ResetSpellList("HUNTER", 253)
    local customized = NS.Database:CountCustomizedSpellLists()
    assertEqual(customized, 0)
end)

test("Seed (Retail): a populated profile is never re-seeded, as before", function()
    local inst = T.load(true, false, retailClient)
    local NS = inst.NS
    NS.db.profile.spells = { HUNTER = { [253] = {} } }
    NS.Database:BuildSpells()
    assertEqual(pairCount(NS.db.profile.spells), 1, "the whole-table empty check still governs Retail")
end)
