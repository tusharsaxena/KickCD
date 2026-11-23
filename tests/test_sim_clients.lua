-- tests/test_sim_clients.lua -- the simulator's story per client, and the Retail-only cast routes
-- (the WoW Forever port, MKF-KC-15; Ka0sAddonsCommonTasks docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT,
-- the synthesis 3.4 "Sim" and the critic's L2; clients-§4).
--
-- Retail keeps its story byte for byte: four kickers, the two-charge boss, Retail's enemy casts and
-- every kick off the global cooldown. On WoW Forever the party is the sample characters whose class
-- has an interrupt there (Mockflame's Counterspell, Mockshield's Shield Bash), named whole; the
-- enemies cast spells Forever has; the boss has no charge steps, because no Forever kick has
-- charges; only Counterspell and the bear Feral Charge are off the global cooldown; and the
-- refusal speaks of a class. Every case loads its client explicitly, so it runs the same on both kit
-- profiles.
--
-- The cast routes: an Evoker's empowered cast (UNIT_SPELLCAST_EMPOWER_*) is Retail's alone, so its
-- three routes are registered by declaration on Retail and absent on WoW Forever, on both the icon
-- grid's and the cast bar's filters (clients-§4: a registration counts as a feature).

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local EMPOWER = { "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP" }

local function retailClient(m)
    T.Loader.makeEnv(m)
    T.Loader.MockClient.apply(m, "retail")
end

local function retail(enable)
    return T.load(true, enable, retailClient)
end

--- A Forever instance whose player is `classFile`, knowing `ids`.
local function forever(classFile, ids, enable, opts)
    local o = { world = "forever" }
    for k, v in pairs(opts or {}) do o[k] = v end
    return T.load(true, enable, function(m)
        m.__setForeverClass(classFile or "MAGE")
        m.__learn(ids or {})
    end, o)
end

local function timeline(NS, name)
    local def = NS.SimHost.SCENARIOS.defs[name]
    return def.timeline(def, { scenario = name, seed = 0 })
end

local function kinds(steps)
    local out = {}
    for i, s in ipairs(steps) do out[i] = s.kind end
    return table.concat(out, ",")
end

-- ── the party ───────────────────────────────────────────────────────────────

test("Sim (Forever): the party is the samples with a Forever kick, Counterspell and Shield Bash", function()
    -- red under: Retail's four kickers, Counter Shot and Rebuke, which WoW Forever does not have
    local P = forever().NS.SimScenario.PARTY
    local keys = {}
    for k in pairs(P) do keys[#keys + 1] = k end
    table.sort(keys)
    assertEqual(table.concat(keys, ","), "mockflame,mockshield")
    assertEqual(P.mockflame.spell, 2139, "Counterspell")
    assertEqual(P.mockshield.spell, 72, "Shield Bash: the Protection sample carries a shield")
end)

test("Sim (Forever): a party member is named whole, First Surname (forever-quirks-§4)", function()
    local P = forever().NS.SimScenario.PARTY
    assertEqual(P.mockflame.name, "Mockflame Samplewick")
    assertEqual(P.mockshield.name, "Mockshield Sampleforge")
end)

test("Sim (Forever): without LibKa0s the party is the same copy of the library's rows", function()
    local live = forever().NS.SimScenario.PARTY
    local P = forever(nil, nil, false, { libFiles = {} }).NS.SimScenario.PARTY
    for _, key in ipairs({ "mockflame", "mockshield" }) do
        for _, field in ipairs({ "name", "class", "spec", "spell" }) do
            assertEqual(P[key][field], live[key][field], key .. "." .. field)
        end
    end
    assertNil(P.samplehunter, "no Hunter kick on WoW Forever")
end)

test("Sim (Retail): the party stays the four Retail kickers, by first name", function()
    local P = retail().NS.SimScenario.PARTY
    assertEqual(P.samplehunter.spell, 147362); assertEqual(P.sampleblade.spell, 96231)
    assertEqual(P.mockflame.spell, 2139); assertEqual(P.mockshield.spell, 6552)
    assertEqual(P.mockflame.name, "Mockflame")
end)

-- ── the enemies and the story ───────────────────────────────────────────────

test("Sim (Forever): every enemy casts a spell WoW Forever has", function()
    -- red under: Chaos Bolt 116858 and Retail's Drain Life 234153, absent from Forever's data
    local E = forever().NS.SimScenario.ENEMIES
    assertEqual(E.casterA.cast, 686); assertEqual(E.casterA.channel, 15407)
    assertEqual(E.casterB.cast, 5782); assertEqual(E.casterB.channel, 689)
    assertEqual(E.boss.cast, 133); assertEqual(E.boss.channel, 689)
end)

test("Sim (Retail): the enemies keep Retail's casts", function()
    local E = retail().NS.SimScenario.ENEMIES
    assertEqual(E.boss.cast, 116858); assertEqual(E.boss.channel, 234153); assertEqual(E.casterB.channel, 234153)
end)

test("Sim (Forever): the boss story has no charge step, and its expiry is the kick's cooldown", function()
    local NS = forever().NS
    local steps = timeline(NS, "boss")
    assertTrue(not kinds(steps):find("Setup", 1, true), kinds(steps))
    for _, s in ipairs(steps) do
        if s.kind == "Expire" then assertEqual(s.label, NS.L["Your kick comes back"]) end
    end
end)

test("Sim (Retail): the boss story keeps its two charges", function()
    local NS = retail().NS
    local steps = timeline(NS, "boss")
    assertEqual(steps[1].kind, "Setup"); assertEqual(steps[1].charges, 2)
end)

test("Sim (Forever): every party step of every story names a member of the Forever party", function()
    -- red under: a timeline still naming Sampleblade or Samplehunter, whose label raises on Forever
    local NS = forever().NS
    for _, name in ipairs(NS.SimScenario.NAMES) do
        for _, s in ipairs(timeline(NS, name)) do
            if s.member ~= nil then
                assertTrue(NS.SimScenario.PARTY[s.member] ~= nil, name .. ": " .. tostring(s.member))
            end
        end
    end
end)

test("Sim (Forever): the pull is a dungeon pull; Retail keeps Mythic+", function()
    assertEqual(forever().NS.SimHost.SCENARIOS.defs.pull.label, "Dungeon pull, several kickers")
    assertEqual(retail().NS.SimHost.SCENARIOS.defs.pull.label, "Mythic+ pull, several kickers")
end)

-- ── the off-GCD rule ────────────────────────────────────────────────────────

test("Sim (Forever): only Counterspell and the bear Feral Charge are off the global cooldown", function()
    local Host = forever().NS.SimHost
    assertTrue(Host.KickOffGcd(2139), "Counterspell")
    assertTrue(Host.KickOffGcd(1238122), "Feral Charge, stored")
    assertTrue(Host.KickOffGcd(16979), "Feral Charge (Bear)")
    for _, id in ipairs({ 6552, 72, 1766, 8042, 19244, 414924 }) do
        assertFalse(Host.KickOffGcd(id), tostring(id) .. " is on the global cooldown")
    end
    assertFalse(Host.KickOffGcd(nil))
end)

test("Sim (Retail): every kick stays off the global cooldown", function()
    local Host = retail().NS.SimHost
    for _, id in ipairs({ 57994, 6552, 2139, 1766 }) do assertTrue(Host.KickOffGcd(id), tostring(id)) end
end)

test("Sim (Forever): the prepare leaves an on-GCD kick on the global cooldown", function()
    -- red under: MarkOffGcd(Host.kick) for every kick, which hid the GCD a Forever Pummel shows
    local inst = forever("WARRIOR", { 6552, 72 }, true)
    local Host = inst.NS.SimHost
    local kick = Host.ResolveSpells()
    assertEqual(kick, 6552, "Pummel leads the Warrior list")
    Host.Prepare(nil, nil, nil, function() end)
    local s = Host.world.spells[kick]
    assertTrue(s == nil or s.offGcd ~= true, "Pummel shows the GCD")
    inst.NS.Sim:OnStop(function() end)
    Host.world = nil
end)

-- ── the four stories play on WoW Forever ────────────────────────────────────

local S = dofile(T.root .. "/tests/sim_support.lua")

--- Deep equality of two plain tables (SavedVariables: no cycles).
local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

--- Play scenario `name` to its end on a Forever `class` player knowing `learn`; answers the printed
--- lines and whether KickCDDB came out as it went in.
local function playForever(class, learn, name)
    local env = S.load({ forever = { class = class, learn = learn } })
    env.advance(100)
    local NS = env.NS
    NS.db.profile.locked = true
    local lines = {}
    NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local before = env.snapshotDB()
    local ok, why = NS.Sim:Start{ scenario = name, seed = 0 }
    assertTrue(ok, name .. " did not start on WoW Forever: " .. tostring(why))
    env.advance(0)
    for i = 1, #NS.Sim:Steps() do
        local played = NS.Sim:Step()
        assertTrue(played ~= nil and played.detail ~= nil, ("%s step %d did not play"):format(name, i))
        env.advance(0)
    end
    NS.Sim:Stop()
    env.advance(0)
    return lines, deepEqual(before, env.snapshotDB()), NS
end

test("Sim (Forever): all four stories play to their end for a Mage and a Warrior", function()
    for _, who in ipairs({ { "MAGE", { 2139, 118 } }, { "WARRIOR", { 6552, 72, 12809 } } }) do
        for _, name in ipairs({ "pull", "boss", "miss", "leave" }) do
            local lines, same = playForever(who[1], who[2], name)
            assertTrue(#lines > 0, who[1] .. " " .. name .. ": nothing was said")
            assertTrue(same, who[1] .. " " .. name .. ": the session changed KickCDDB")
        end
    end
end)

test("Sim (Forever): the pull narrates the whole names and Counterspell", function()
    local lines, _, NS = playForever("MAGE", { 2139, 118 }, "pull")
    local said = table.concat(lines, "\n")
    assertTrue(said:find("Mockflame Samplewick", 1, true) ~= nil, "Mockflame named whole")
    assertTrue(said:find("Mockshield Sampleforge", 1, true) ~= nil, "Mockshield named whole")
    assertTrue(said:find((NS.Compat.GetSpellInfo(72)) or "Shield Bash", 1, true) ~= nil, "Shield Bash")
end)

-- ── the refusal ─────────────────────────────────────────────────────────────

test("Sim (Forever): with no usable spell the refusal speaks of the class", function()
    local NS = forever("MAGE", {}).NS
    NS.db.profile.locked = true
    local line = NS.SimHost.Refusal()
    assertEqual(line, "Your class tracks no spell you can use: add one with /kcd spells add, then start again.")
end)

-- ── the Retail-only cast routes (critic L2) ─────────────────────────────────

--- Every route the instance's cast filters were built with, as a set of event names per module.
local function filterRoutes(NS)
    local out = {}
    for _, r in ipairs(NS.EventRoutes.filters) do
        local name = r.module == NS:GetModule("IconGrid") and "IconGrid" or
            (r.module == NS:GetModule("Castbar") and "Castbar" or "?")
        out[name] = out[name] or {}
        for ev in pairs(r.routes) do out[name][ev] = true end
    end
    return out
end

test("Cast routes (Retail): both filters route the empowered cast", function()
    local routes = filterRoutes(retail(true).NS)
    for _, owner in ipairs({ "IconGrid", "Castbar" }) do
        assertTrue(routes[owner] ~= nil, owner .. " built a filter")
        for _, ev in ipairs(EMPOWER) do assertTrue(routes[owner][ev], owner .. " " .. ev) end
        assertTrue(routes[owner].UNIT_SPELLCAST_START, owner .. " START")
    end
end)

test("Cast routes (Forever): the empowered cast is absent by declaration, the rest kept", function()
    -- red under: EMPOWER_* registered on WoW Forever, which has no Evoker (clients-§4)
    local routes = filterRoutes(forever("MAGE", { 2139 }, true).NS)
    for _, owner in ipairs({ "IconGrid", "Castbar" }) do
        assertTrue(routes[owner] ~= nil, owner .. " built a filter")
        for _, ev in ipairs(EMPOWER) do assertNil(routes[owner][ev], owner .. " " .. ev) end
        assertTrue(routes[owner].UNIT_SPELLCAST_START and routes[owner].UNIT_SPELLCAST_CHANNEL_START,
            owner .. " keeps the cast and channel routes")
    end
end)

test("Util.AddClientRoutes: adds the routes only on a client the declaration names", function()
    local U = retail().NS.Util
    local base = { UNIT_SPELLCAST_START = "A" }
    local out = U.AddClientRoutes(base, { UNIT_SPELLCAST_EMPOWER_START = "B" }, { "retail" })
    assertTrue(out == base, "the same table, grown in place")
    assertEqual(base.UNIT_SPELLCAST_EMPOWER_START, "B")
    local f = forever().NS.Util
    local fb = { UNIT_SPELLCAST_START = "A" }
    f.AddClientRoutes(fb, { UNIT_SPELLCAST_EMPOWER_START = "B" }, { "retail" })
    assertNil(fb.UNIT_SPELLCAST_EMPOWER_START)
end)
