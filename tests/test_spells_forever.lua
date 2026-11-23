-- tests/test_spells_forever.lua -- WoW Forever's default lists (defaults/Spells_Forever.lua) and the
-- Retail lists they must leave alone (the Forever port, MKF-KC-08; owner rulings R6 and R7 of
-- 2026-11-23, critic L1).
--
-- The Forever lists were written by tools/seeds/seeds.py --flavor forever from the frozen
-- 1.60.1.71037 run (docs/seed-research/2026-11-23-forever/) and ordered by hand. These cases pin
-- what the owner ruled: one list per class at its Const.SPEC_FOREVER id, Pummel first for
-- Warriors, the research's core list plus Gouge and Intercept, War Stomp in the four classes a
-- Tauren plays, and every shipped entry an accepted ruling in tools/seeds/rulings_forever.json.

local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local Const = NS.Const

local CATEGORIES = { interrupt = true, stun = true, knockback = true, incapacitate = true,
    silence = true, root = true, fear = true, displace = true, racial = true, other = true }

-- The lists the owner ruled, in priority order (index 1 is the primary).
local WANT = {
    WARRIOR = { 6552, 72, 12809, 5246, 20252, 20549 },   -- Pummel first (R6); Intercept (R7)
    PALADIN = { 853, 20066 },
    HUNTER  = { 19503, 19577, 1499, 20549 },
    ROGUE   = { 1766, 408, 1833, 2094, 1776 },           -- Gouge (R7)
    PRIEST  = { 15487, 8122, 605 },
    SHAMAN  = { 8042, 20549 },
    MAGE    = { 2139, 118 },
    WARLOCK = { 19244, 6789, 5484, 5782 },
    DRUID   = { 1238122, 5211, 20549 },
}

local function readFile(rel)
    local fh = assert(io.open(T.root .. "/" .. rel, "rb"))
    local text = fh:read("*a")
    fh:close()
    return text
end

local function ids(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.spellID end
    return table.concat(out, ",")
end

test("Forever lists: one list per Forever class, at its SPEC_FOREVER id and nowhere else", function()
    local n = 0
    for classFile, specs in pairs(NS.DefaultSpellsForever) do
        n = n + 1
        local want = Const.SPEC_FOREVER[classFile]
        assertTrue(want ~= nil, classFile .. " is not a Forever class")
        local keys = 0
        for specID in pairs(specs) do
            keys = keys + 1
            assertEqual(specID, want, classFile .. "'s list key")
        end
        assertEqual(keys, 1, classFile .. " ships exactly one list")
    end
    assertEqual(n, 9, "nine Forever classes")
end)

test("Forever lists: each list is the ruled membership in the ruled order", function()
    for classFile, want in pairs(WANT) do
        local list = NS.DefaultSpellsForever[classFile][Const.SPEC_FOREVER[classFile]]
        assertEqual(ids(list), table.concat(want, ","), classFile)
    end
end)

test("Forever lists: Pummel leads the Warrior list, and every list leads with an interrupt where its class has one", function()
    local warrior = NS.DefaultSpellsForever.WARRIOR[Const.SPEC_FOREVER.WARRIOR]
    assertEqual(warrior[1].spellID, 6552, "Pummel first (R6)")
    -- Paladin, Hunter and Priest reach no interrupt with a cooldown on 71037 (Silence's lockout is
    -- server-linked), so their index 1 is the best stop, as defaults/Spells.lua's header allows.
    for _, classFile in ipairs({ "WARRIOR", "ROGUE", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        local list = NS.DefaultSpellsForever[classFile][Const.SPEC_FOREVER[classFile]]
        assertEqual(list[1].category, "interrupt", classFile .. " index 1")
    end
end)

test("Forever lists: every entry is the stored shape, in the closed category set, enabled", function()
    for classFile, specs in pairs(NS.DefaultSpellsForever) do
        for _, list in pairs(specs) do
            local seen = {}
            for i, e in ipairs(list) do
                local where = classFile .. "[" .. i .. "]"
                assertTrue(type(e.spellID) == "number" and e.spellID > 0, where .. " spellID")
                assertTrue(CATEGORIES[e.category] ~= nil, where .. " category " .. tostring(e.category))
                assertEqual(e.enabled, true, where .. " enabled")
                assertTrue(not seen[e.spellID], where .. " duplicates " .. e.spellID)
                seen[e.spellID] = true
            end
        end
    end
end)

test("Forever lists: War Stomp is in the four classes a Tauren plays, as a racial, and the racial table names it", function()
    local tauren = { WARRIOR = true, HUNTER = true, SHAMAN = true, DRUID = true }
    for classFile, specs in pairs(NS.DefaultSpellsForever) do
        local found
        for _, e in ipairs(specs[Const.SPEC_FOREVER[classFile]]) do
            if e.spellID == 20549 then found = e end
        end
        assertEqual(found ~= nil, tauren[classFile] == true, classFile .. " and War Stomp")
        if found then assertEqual(found.category, "racial", classFile .. " War Stomp's category") end
    end
    local n = 0
    for race, id in pairs(NS.RaceCastStoppersForever) do
        n = n + 1
        assertEqual(race, "Tauren")
        assertEqual(id, 20549)
    end
    assertEqual(n, 1, "Forever's one cast-stopping racial")
end)

test("Forever lists: every shipped entry is an accepted ruling, and every accepted ruling is shipped", function()
    -- Rulings are data (docs/validate-seeds.md): the membership calls live in the rulings file,
    -- keyed <CLASS>:<specID>:<id>, so the shipped lists and the file can never drift apart.
    local json = readFile("tools/seeds/rulings_forever.json")
    local accepted = {}
    for key, body in json:gmatch('"([A-Z]+:%d+:%d+)": (%b{})') do
        if body:match('"ruling": "accept"') then accepted[key] = true end
    end
    local shipped = {}
    for classFile, specs in pairs(NS.DefaultSpellsForever) do
        for specID, list in pairs(specs) do
            for _, e in ipairs(list) do
                local key = classFile .. ":" .. specID .. ":" .. e.spellID
                shipped[key] = true
                assertTrue(accepted[key], key .. " ships without an accepted ruling")
            end
        end
    end
    for key in pairs(accepted) do
        assertTrue(shipped[key], key .. " is accepted but not shipped")
    end
end)

test("Retail lists: defaults/Spells.lua is byte-identical to the port's base (333cd49)", function()
    -- The Forever port adds a second file and never edits the Retail one (clients-§5). The digest
    -- is over the file's text with CRLF read as LF, the bytes git stores. A Retail seed run that
    -- changes the file re-pins it here, in its own commit.
    local text = readFile("defaults/Spells.lua"):gsub("\r\n", "\n")
    local h = 0
    for i = 1, #text do h = (h * 31 + text:byte(i)) % 4294967296 end
    assertEqual(#text, 21699, "length")
    assertEqual(h, 2616645865, "digest")
end)

test("Retail lists: the Forever file touches neither Retail table, and every Forever list is a SPEC_FOREVER key", function()
    -- Spells_Forever.lua loads after Spells.lua and publishes its own two tables.
    local n = 0
    for _ in pairs(NS.DefaultSpells) do n = n + 1 end
    assertEqual(n, 13, "the Retail lists are all thirteen classes'")
    assertTrue(NS.DefaultSpells ~= NS.DefaultSpellsForever)
    assertTrue(NS.RaceCastStoppers ~= NS.RaceCastStoppersForever)
    assertEqual(NS.RaceCastStoppers.Tauren, 20549)
    assertTrue(NS.RaceCastStoppers.HighmountainTauren ~= nil, "the Retail racials stay Retail's")
    for classFile, id in pairs(Const.SPEC_FOREVER) do
        assertTrue(NS.DefaultSpellsForever[classFile] and NS.DefaultSpellsForever[classFile][id] ~= nil,
            classFile .. " (" .. id .. ") has no Forever list")
    end
end)

test("Forever lists: the TOC loads defaults/Spells_Forever.lua straight after defaults/Spells.lua", function()
    local toc = readFile("KickCD.toc")
    assertTrue(toc:find("defaults\\Spells.lua\r?\ndefaults\\Spells_Forever.lua\r?\n") ~= nil,
        "defaults\\Spells_Forever.lua must follow defaults\\Spells.lua")
end)
