-- tests/test_admission_clients.lua -- which spells a player may add, per client (the WoW Forever
-- port, MKF-KC-12; owner ruling R8 of 2026-11-23, clients-§4).
--
-- Retail keeps the Blizzard Cooldown Manager gate on the player's live pair: its set, its "not
-- tracked" tag, its invalidator and its `cmcache` diagnostics section. On WoW Forever the gate is
-- ABSENT by declaration, none of the four exists, and the live pair takes anything the player or
-- the pet knows (any rank of a family) plus KickCD's own Forever list for that class (R8); an
-- unlearned spell outside the list is refused. Another class's list takes any spell, on both.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local WARRIOR, ROGUE, WARLOCK = 1491, 1488, 1490

local function trapViewer(m)
    m.C_CooldownViewer = setmetatable({}, { __index = function() error("Cooldown Manager read on WoW Forever") end })
end

--- A Forever instance whose player is `classFile`, knowing `ids` (player bank) and `petIds`.
local function forever(classFile, ids, petIds, enable)
    return T.load(true, enable, function(m)
        m.__setForeverClass(classFile)
        m.__learn(ids or {})
        m.__learn(petIds or {}, 1)
        trapViewer(m)
    end, { world = "forever" })
end

local function retailClient(m)
    T.Loader.makeEnv(m)
    T.Loader.MockClient.apply(m, "retail")
end

--- A Retail instance whose Cooldown Manager tracks exactly `tracked`.
local function retail(tracked, enable)
    return T.load(true, enable, function(m)
        retailClient(m)
        m.Enum.CooldownViewerCategory = { Essential = 0 }
        m.C_CooldownViewer = {
            GetCooldownViewerCategorySet = function() return { 1 } end,
            GetCooldownViewerCooldownInfo = function() return { spellID = tracked } end,
        }
    end)
end

-- ── WoW Forever (R8) ────────────────────────────────────────────────────────

test("Admission (Forever): a spell the player knows is admitted on the live pair", function()
    local SI = forever("WARRIOR", { 100 }).NS.SpellInput
    assertTrue(SI.Admissible(100, "WARRIOR", WARRIOR), "Charge, known, on no list")
end)

test("Admission (Forever): any rank of a known family is admitted", function()
    local SI = forever("ROGUE", { 1766 }).NS.SpellInput
    assertTrue(SI.Admissible(1769, "ROGUE", ROGUE), "Kick rank 4 typed, rank 1 known")
end)

test("Admission (Forever): a spell the pet knows is admitted", function()
    local SI = forever("WARLOCK", nil, { 6358 }).NS.SpellInput
    assertTrue(SI.Admissible(6358, "WARLOCK", WARLOCK), "the Succubus's Seduction")
end)

test("Admission (Forever): an unlearned spell on the class's Forever list is admitted", function()
    local SI = forever("WARRIOR").NS.SpellInput
    assertTrue(SI.Admissible(12809, "WARRIOR", WARRIOR), "Concussion Blow, a talent not yet learned")
    assertTrue(SI.Admissible(6554, "WARRIOR", WARRIOR), "a rank of a listed family")
end)

test("Admission (Forever): an unlearned spell outside the list is refused, naming no Cooldown Manager", function()
    local SI = forever("WARRIOR").NS.SpellInput
    local ok, why = SI.Admissible(100, "WARRIOR", WARRIOR)
    assertFalse(ok)
    assertTrue(why:find("#100", 1, true) ~= nil, why)
    assertTrue(why:find("Cooldown Manager", 1, true) == nil, why)
    assertTrue(why:find("know", 1, true) ~= nil, "it says the spell is not known: " .. why)
end)

test("Admission (Forever): another class's list takes any spell", function()
    local SI = forever("WARRIOR").NS.SpellInput
    assertTrue(SI.Admissible(100, "ROGUE", ROGUE))
end)

test("Admission (Forever): /kcd spells add refuses an unlearned spell off the list and adds nothing", function()
    local inst = forever("WARRIOR", nil, nil, true)
    local NS = inst.NS
    local said = {}
    NS.Util.print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
    local before = #NS.Database:GetSpellList("WARRIOR", WARRIOR)
    NS:OnSlashCommand("spells add 100")
    assertEqual(#NS.Database:GetSpellList("WARRIOR", WARRIOR), before, "nothing added")
    inst.mocks.__learn({ 100 })
    NS:OnSlashCommand("spells add 100")
    assertEqual(#NS.Database:GetSpellList("WARRIOR", WARRIOR), before + 1, "known: added")
end)

test("Admission (Forever): the Cooldown Manager gate, its tag, invalidator and section are absent", function()
    local inst = forever("WARRIOR", nil, nil, true)
    local NS = inst.NS
    assertNil(NS.SpellInput.CooldownManagerSet(), "never walked")
    assertNil(NS.Settings.SpellsPanel.SuggestTag(100), "no 'not tracked' tag")
    for _, reg in ipairs(inst.mocks.__registrationSet()) do
        assertTrue(reg.target ~= NS.SpellInput.__ev, "no invalidator registration: " .. tostring(reg.event))
    end
    for _, s in ipairs(NS.Diagnostics.Sections()) do
        assertTrue(s[1] ~= "cmcache", "no cmcache section on WoW Forever")
    end
    local built = NS.DebugLog:BuildDiagnostics()
    for _, l in ipairs(built.lines) do
        assertTrue(tostring(l[1]) ~= "CMCache", "no [CMCache] line")
    end
end)

test("Admission (Forever): the section list is Retail's in order with cmcache alone dropped (KC-REV-5)", function()
    local function names(inst)
        local out = {}
        for _, s in ipairs(inst.NS.Diagnostics.Sections()) do
            if s[1] ~= "cmcache" then out[#out + 1] = s[1] end
        end
        return table.concat(out, ",")
    end
    local fv = forever("WARRIOR", nil, nil, true)
    local rt = retail(147362, true)
    local fvAll = {}
    for _, s in ipairs(fv.NS.Diagnostics.Sections()) do fvAll[#fvAll + 1] = s[1] end
    assertEqual(table.concat(fvAll, ","), names(rt), "the Forever list is Retail's minus cmcache")
    local fh = assert(io.open(T.root .. "/modules/Diagnostics.lua", "rb"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:find("table.remove(out,", 1, true), "cmcache is never dropped by position")
end)

-- ── Retail: unchanged ───────────────────────────────────────────────────────

test("Admission (Retail): the Cooldown Manager gate still refuses an untracked spell on the live pair", function()
    local inst = retail(147362)
    local SI = inst.NS.SpellInput
    local spec = inst.NS.Util.PlayerSpecID()
    assertTrue(SI.Admissible(147362, "HUNTER", spec))
    local ok, why = SI.Admissible(100, "HUNTER", spec)
    assertFalse(ok)
    assertEqual(why, "Spell Spell100 (#100) is not tracked by the Blizzard Cooldown Manager for this specialization.")
    assertTrue(SI.Admissible(100, "ROGUE", 259), "another spec's list is lenient")
end)

test("Admission (Retail): the tag, the invalidator and the cmcache section are still there", function()
    local inst = retail(147362, true)
    local NS = inst.NS
    local found = false
    for _, s in ipairs(NS.Diagnostics.Sections()) do
        if s[1] == "cmcache" then found = true end
    end
    assertTrue(found, "cmcache section")
    local walks = 0
    NS.SpellInput.CooldownManagerSet()
    inst.mocks.C_CooldownViewer.GetCooldownViewerCategorySet = function() walks = walks + 1; return { 1 } end
    inst.mocks.__fireEvent("TRAIT_CONFIG_UPDATED")
    NS.SpellInput.CooldownManagerSet()
    assertEqual(walks, 1, "the invalidator dropped the set on a talent change")
end)
