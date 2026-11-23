-- tests/test_spell_ranks.lua -- the one rank resolver (core/SpellRanks.lua) and every consumer of a
-- stored row's spell (the WoW Forever port, MKF-KC-09; clients-§10, critic C3).
--
-- On WoW Forever every rank is its own spell id and a stored row is the family's rank-1 id. The
-- resolver answers the highest rank the player knows for the texture, the tooltip and the cooldown,
-- and "usable" when ANY known rank is (a downranking Shaman's rank 1 still interrupts). On Retail it
-- is identity, and the Retail cases below pin that each consumer asks the client exactly what it
-- asked before the resolver existed.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local WARRIOR, SHAMAN = 1491, 1489

--- A Forever instance whose player is `classFile`, knowing `ids` on the player's bank, with its
--- class list replaced by `entries` (spell ids). Enabled when `enable`.
local function forever(classFile, ids, entries, enable)
    local inst = T.load(true, enable, function(m)
        m.__setForeverClass(classFile)
        m.__learn(ids or {})
    end, { world = "forever" })
    local NS = inst.NS
    if entries then
        local spec = NS.Const.SPEC_FOREVER[classFile]
        NS.db.profile.spells[classFile] = NS.db.profile.spells[classFile] or {}
        local list = {}
        for i, id in ipairs(entries) do list[i] = { spellID = id, category = "interrupt", enabled = true } end
        NS.db.profile.spells[classFile][spec] = list
    end
    return inst
end

--- A mutate hook that makes the instance a Retail client whatever KA0S_KIT_CLIENT says, so the
--- Retail cases run the same on both kit profiles (the stamp the loader would make, then Retail's).
local function retailClient(m)
    T.Loader.makeEnv(m)
    T.Loader.MockClient.apply(m, "retail")
end

local function retail(entries)
    local inst = T.load(true, true, retailClient)
    local NS = inst.NS
    local list = {}
    for i, id in ipairs(entries) do list[i] = { spellID = id, category = "interrupt", enabled = true } end
    NS.db.profile.spells.HUNTER[NS.Util.PlayerSpecID()] = list
    return inst
end

local function idsOf(gi)
    local out = {}
    for _, btn in ipairs(gi.ordered) do out[#out + 1] = btn.spellID end
    return table.concat(out, ",")
end

-- ── the data ────────────────────────────────────────────────────────────────

test("Ranks: the Forever rank table is the frozen seed run's rank families, id for id", function()
    local NS = T.NS
    local fh = assert(io.open(T.root .. "/docs/seed-research/2026-11-23-forever/candidates.json", "rb"))
    local text = fh:read("*a")
    fh:close()
    local want, n = {}, 0
    local candidates = assert(text:match('"candidates":%s*(%b[])'), "candidates.json has a candidates array")
    for block in candidates:gmatch("%b{}") do
        local id = tonumber(block:match('"id":%s*(%d+)'))
        local ranks = block:match('"ranks":%s*(%b[])')
        if id and ranks then
            local list = {}
            for r in ranks:gmatch("%d+") do list[#list + 1] = tonumber(r) end
            if #list > 1 then want[id] = table.concat(list, ",") end
        end
    end
    for id, ranks in pairs(want) do
        n = n + 1
        local have = NS.SpellRanksForever[id]
        assertTrue(have ~= nil, "family " .. id .. " is missing")
        assertEqual(table.concat(have, ","), ranks, "family " .. id)
    end
    local shipped = 0
    for id in pairs(NS.SpellRanksForever) do
        shipped = shipped + 1
        assertTrue(want[id] ~= nil, "family " .. id .. " is not in the seed run")
    end
    assertEqual(shipped, n, "the table holds the run's multi-rank families and no others")
    assertEqual(n, 23)
end)

test("Ranks: every family's first rank is its key, and no rank sits in two families", function()
    local seen = {}
    for family, ranks in pairs(T.NS.SpellRanksForever) do
        assertEqual(ranks[1], family, "family " .. family .. " is keyed by its rank 1")
        for _, id in ipairs(ranks) do
            assertNil(seen[id], "rank " .. id .. " is in two families")
            seen[id] = family
        end
    end
end)

-- ── the resolver on WoW Forever ─────────────────────────────────────────────

test("Ranks (Forever): a row resolves to the highest rank the player knows", function()
    local NS = forever("WARRIOR", { 6552, 6554, 72 }).NS
    local R = NS.SpellRanks
    assertEqual(R.Resolve(6552), 6554, "Pummel rank 2")
    assertEqual(R.Resolve(6554), 6554, "a stored rank 2 resolves the same")
    assertEqual(R.Resolve(72), 72, "Shield Bash rank 1 only")
    assertEqual(R.Resolve(1671), 72, "a stored higher rank falls to the rank the player knows")
    assertEqual(R.Resolve(20252), 20252, "nothing known: the stored id, so the row reads unavailable")
    assertEqual(R.Resolve(12809), 12809, "a single-rank spell is its own family")
    assertEqual(R.Family(6554), 6552)
    assertEqual(R.Family(10414), 8042)
    assertEqual(R.Family(12809), 12809)
end)

test("Ranks (Forever): a pet's ranks resolve on the pet's bank", function()
    local inst = forever("WARLOCK")
    inst.mocks.__learn({ 19244, 19647 }, 1)
    assertEqual(inst.NS.SpellRanks.Resolve(19244), 19647, "Spell Lock rank 2, the Felhunter's")
end)

test("Ranks (Forever): usable when ANY known rank is (critic C3)", function()
    local inst = forever("SHAMAN", { 8042, 8044, 8045, 8046, 10412, 10413, 10414 })
    local NS, m = inst.NS, inst.mocks
    -- 100 mana: rank 7 costs 450, rank 1 costs 30.
    m.C_Spell.IsSpellUsable = function(id) return id == 8042 end
    assertEqual(NS.SpellRanks.Resolve(8042), 10414, "the texture and cooldown follow rank 7")
    assertTrue(NS.SpellRanks.IsUsable(8042), "rank 1 still interrupts")
    m.C_Spell.IsSpellUsable = function() return false end
    assertFalse(NS.SpellRanks.IsUsable(8042), "no rank usable")
end)

test("Ranks (Forever): the known set is cached until Invalidate", function()
    local inst = forever("WARRIOR", { 6552 })
    local R = inst.NS.SpellRanks
    assertEqual(R.Resolve(6552), 6552)
    inst.mocks.__learn({ 6554 })
    assertEqual(R.Resolve(6552), 6552, "cached")
    R.Invalidate()
    assertEqual(R.Resolve(6552), 6554, "read again after Invalidate")
end)

-- ── the consumers on WoW Forever ────────────────────────────────────────────

test("Ranks (Forever): Cooldowns polls the live rank under the stored row's id", function()
    local inst = forever("WARRIOR", { 6552, 6554 }, { 6552 }, true)
    local NS, m = inst.NS, inst.mocks
    m.spellCooldowns[6554] = { isEnabled = true, startTime = 1, duration = 10, isActive = true }
    local Cooldowns = NS:GetModule("Cooldowns")
    Cooldowns:Rebuild()
    local s = Cooldowns:StateFor(6552)
    assertTrue(s ~= nil, "the row is watched under its stored id")
    assertTrue(s.isActive, "rank 2's cooldown, not rank 1's")
end)

test("Ranks (Forever): the ready flag uses any known rank's usability", function()
    local inst = forever("SHAMAN", { 8042, 10414 }, { 8042 }, true)
    local NS, m = inst.NS, inst.mocks
    m.C_Spell.IsSpellUsable = function(id) return id == 8042 end
    local Cooldowns = NS:GetModule("Cooldowns")
    Cooldowns:Rebuild()
    assertTrue(Cooldowns:StateFor(8042).ready, "rank 1 is usable, so the row is ready")
end)

test("Ranks (Forever): a poll reads the cache, never the spellbook's rank walk", function()
    local inst = forever("SHAMAN", { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, { 8042 }, true)
    local NS, m = inst.NS, inst.mocks
    local Cooldowns = NS:GetModule("Cooldowns")
    Cooldowns:Rebuild()
    local asked = {}
    local known = m.C_SpellBook.IsSpellKnown
    m.C_SpellBook.IsSpellKnown = function(id, bank)
        asked[id] = true
        return known(id, bank)
    end
    Cooldowns:Refresh()
    for id in pairs(asked) do
        assertEqual(id, 10414, "a poll asks about the live rank alone, got " .. id)
    end
end)

test("Ranks (Forever): the grid draws the live rank's icon, deduped on the live id", function()
    local inst = forever("WARRIOR", { 6552, 6554 }, { 6552, 6554, 72 }, true)
    local NS, m = inst.NS, inst.mocks
    m.__learn({ 72 })
    local painted = {}
    m.C_Spell.GetSpellTexture = function(id) painted[#painted + 1] = id; return 1000 + id end
    local IconGrid = NS:GetModule("IconGrid")
    local gi = IconGrid:GetInstance("target")
    IconGrid:BuildActiveList(gi)
    assertEqual(idsOf(gi), "6552,72", "6552 and 6554 are one family: one icon")
    assertEqual(painted[1], 6554, "the icon is rank 2's")
end)

test("Ranks (Forever): the ticker reads the live rank's cooldown", function()
    local inst = forever("WARRIOR", { 6552, 6554 }, { 6552 }, true)
    local NS, m = inst.NS, inst.mocks
    local asked = {}
    local cd = m.C_Spell.GetSpellCooldown
    m.C_Spell.GetSpellCooldown = function(id) asked[#asked + 1] = id; return cd(id) end
    local IconGrid = NS:GetModule("IconGrid")
    local gi = IconGrid:GetInstance("target")
    IconGrid:BuildActiveList(gi)
    local btn = gi.ordered[1]
    asked = {}
    btn:_TickCooldown(1)
    assertEqual(asked[1], 6554, "branch 1 asks rank 2")
end)

test("Ranks (Forever): the icon tooltip shows the live rank", function()
    local inst = forever("WARRIOR", { 6552, 6554 }, { 6552 }, true)
    local NS, m = inst.NS, inst.mocks
    NS.Units.Icons("target").showTooltip = true
    local shown
    m.GameTooltip.SetSpellByID = function(_, id) shown = id end
    local IconGrid = NS:GetModule("IconGrid")
    local gi = IconGrid:GetInstance("target")
    IconGrid:BuildActiveList(gi)
    gi.ordered[1]:GetScript("OnEnter")(gi.ordered[1])
    assertEqual(shown, 6554)
end)

test("Ranks (Forever): the simulator's kick is the live rank", function()
    local inst = forever("WARRIOR", { 6552, 6554 }, { 6552 }, true)
    local kick = inst.NS.SimHost.ResolveSpells()
    assertEqual(kick, 6554)
end)

test("Ranks (Forever): the diagnostics list calls a known higher rank learned, and names it", function()
    local inst = forever("WARRIOR", { 6554 }, { 6552 }, true)
    local built = inst.NS.DebugLog:BuildDiagnostics()
    local body = {}
    for _, l in ipairs(built.lines) do body[#body + 1] = tostring(l[2]) end
    body = table.concat(body, "\n")
    assertTrue(body:find("6552 [^\n,]*rank 6554") ~= nil, "the live rank is named:\n" .. body)
    assertTrue(body:find("6552 [^\n,]*unlearned") == nil, "rank 2 known is learned:\n" .. body)
end)

test("Ranks (Forever): the Spells page's name, icon and known mark follow the live rank", function()
    local inst = forever("WARRIOR", { 6554 }, { 6552 }, true)
    local NS, m = inst.NS, inst.mocks
    local deps = NS.Settings.SpellsPanel.__rowDeps
    local asked = {}
    m.C_Spell.GetSpellTexture = function(id) asked[#asked + 1] = id; return 1 end
    deps.getSpellIcon(6552)
    assertEqual(asked[1], 6554, "the icon is the live rank's")
    assertEqual(NS.Settings.SpellsPanel.RowKnown({ spellID = 6552 }), true, "rank 2 known: the mark is green")
end)

test("Ranks (Forever): adding any rank stores the family's rank-1 id", function()
    local inst = forever("WARRIOR", { 6552, 6554 }, {})
    local NS = inst.NS
    assertEqual(NS.Database:AddSpell("WARRIOR", WARRIOR, 6554), "added")
    local list = NS.Database:GetSpellList("WARRIOR", WARRIOR)
    assertEqual(list[1].spellID, 6552)
    assertEqual(NS.Database:AddSpell("WARRIOR", WARRIOR, 6552), "enabled", "the family is already there")
    assertEqual(#list, 1)
    assertEqual(NS.Database:AddSpell("SHAMAN", SHAMAN, 10414), "added", "another class's list too")
    assertEqual(NS.Database:GetSpellList("SHAMAN", SHAMAN)[1].spellID, 8042)
end)

-- ── Retail: identity, byte for byte ─────────────────────────────────────────

test("Ranks (Retail): every answer is the id itself and the Forever table is never read", function()
    local NS = T.load(true, false, retailClient).NS
    local R = NS.SpellRanks
    local real = NS.SpellRanksForever
    NS.SpellRanksForever = setmetatable({}, { __index = function() error("read on Retail") end,
        __pairs = function() error("walked on Retail") end })
    assertEqual(R.Resolve(6554), 6554)
    assertEqual(R.Resolve(6552), 6552)
    assertEqual(R.Family(6554), 6554)
    assertNil(R.KnownRanks(6552))
    NS.SpellRanksForever = real
end)

test("Ranks (Retail): IsUsable is Compat.IsSpellUsable's first value", function()
    local inst = T.load(true, false, retailClient)
    local NS, m = inst.NS, inst.mocks
    m.C_Spell.IsSpellUsable = function(id) return id == 1, true end
    assertTrue(NS.SpellRanks.IsUsable(1))
    assertFalse(NS.SpellRanks.IsUsable(2))
    assertEqual(select("#", NS.SpellRanks.IsUsable(1)), 1, "one value, as the poll read it")
end)

test("Ranks (Retail): two rank ids stay two rows, two icons and two stored entries", function()
    local inst = retail({ 6552, 6554 })
    local NS = inst.NS
    local IconGrid = NS:GetModule("IconGrid")
    local gi = IconGrid:GetInstance("target")
    IconGrid:BuildActiveList(gi)
    assertEqual(idsOf(gi), "6552,6554", "Retail does not fold ranks")
    local Cooldowns = NS:GetModule("Cooldowns")
    Cooldowns:Rebuild()
    assertTrue(Cooldowns:StateFor(6552) ~= nil and Cooldowns:StateFor(6554) ~= nil)
    assertEqual(NS.Database:AddSpell("HUNTER", NS.Util.PlayerSpecID(), 1671), "added")
    local list = NS.Database:GetSpellList("HUNTER", NS.Util.PlayerSpecID())
    assertEqual(list[#list].spellID, 1671, "stored as typed")
end)

test("Ranks (Retail): every consumer asks the client the stored id", function()
    local inst = retail({ 147362 })
    local NS, m = inst.NS, inst.mocks
    local asked = {}
    local function spy(tbl, key)
        local real = tbl[key]
        tbl[key] = function(id, ...) asked[key .. ":" .. tostring(id)] = true; return real(id, ...) end
    end
    spy(m.C_Spell, "GetSpellCooldown")
    spy(m.C_Spell, "GetSpellTexture")
    spy(m.C_Spell, "IsSpellUsable")
    spy(m.C_SpellBook, "IsSpellKnown")
    NS:GetModule("Cooldowns"):Rebuild()
    local IconGrid = NS:GetModule("IconGrid")
    IconGrid:BuildActiveList(IconGrid:GetInstance("target"))
    for _, key in ipairs({ "GetSpellCooldown", "GetSpellTexture", "IsSpellUsable", "IsSpellKnown" }) do
        assertTrue(asked[key .. ":147362"], key .. " is asked the stored id")
    end
    for k in pairs(asked) do
        assertTrue(k:find(":147362", 1, true) ~= nil or k:find(":61304", 1, true) ~= nil,
            "nothing but the stored id (and the GCD spell) is asked: " .. k)
    end
end)
