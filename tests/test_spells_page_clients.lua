-- tests/test_spells_page_clients.lua -- the Spells page, the `/kcd spells` wording and the class and
-- spec checks per client (the WoW Forever port, MKF-KC-13; critic C6, factcheck E).
--
-- WoW Forever has one spec per class, named for the class, and nine classes at ids 1-5, 7, 8, 9, 11,
-- so a 1..GetNumClasses loop loses Druid. There the class list is C_SpecializationInfo.GetAllClassIDs,
-- a spec's token is its class's, a Retail spec token (ARMS) is refused, a class the Forever lists do
-- not carry is unknown, `reset`, `list` and `remove` validate what they are given, the picker reads
-- "Class" with one name per row, and the command words say [CLASS]. On Retail all of it is as before.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local WARRIOR, ROGUE, DRUID = 1491, 1488, 1484

local function forever(classFile, enable, mutate)
    return T.load(true, enable, function(m)
        m.__setForeverClass(classFile or "WARRIOR")
        if mutate then mutate(m) end
    end, { world = "forever" })
end

local function retailClient(m)
    T.Loader.makeEnv(m)
    T.Loader.MockClient.apply(m, "retail")
end

--- Run `/kcd <line>` and return what it printed, one string per line.
local function said(inst, line)
    local out = {}
    local NS = inst.NS
    local real = NS.Util.print
    NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        out[#out + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(NS.OnSlashCommand, NS, line)
    NS.Util.print = real
    if not ok then error(err, 0) end
    return table.concat(out, "\n")
end

-- ── the spec maps (Forever) ─────────────────────────────────────────────────

test("Spells page (Forever): the spec maps reach Druid, the class a 1..GetNumClasses loop loses", function()
    local U = forever().NS.Util
    local order = U.SpecOrderForClass("DRUID")
    assertTrue(order ~= nil, "Druid is enumerated")
    assertEqual(table.concat(order, ","), tostring(DRUID))
    assertEqual(U.SpecDisplayName(DRUID), "Druid")
end)

test("Spells page (Forever): a spec's token is its class's, and a Retail token is refused", function()
    local U = forever().NS.Util
    assertEqual(U.SpecTokenForID(WARRIOR), "WARRIOR")
    assertEqual(U.SpecDisplay(ROGUE), "ROGUE")
    assertEqual(U.ResolveSpecID("WARRIOR", "WARRIOR"), WARRIOR)
    assertNil(U.ResolveSpecID("ARMS", "WARRIOR"), "Arms is a Retail spec")
    assertNil(U.ResolveSpecID("ELEMENTAL"), "so is Elemental")
end)

test("Spells page (Forever): an early nil spec answer falls back to the class's one spec", function()
    local inst = forever("ROGUE", false, function(m)
        m.C_SpecializationInfo.GetSpecialization = function() return nil end
    end)
    assertEqual(inst.NS.Util.PlayerSpecID(), ROGUE)
end)

test("Spells page (Forever): a class the Forever lists do not carry is unknown", function()
    local DB = forever().NS.Database
    assertTrue(DB.IsKnownClass("DRUID"))
    assertFalse(DB.IsKnownClass("DEATHKNIGHT"), "no Death Knight on WoW Forever")
    assertFalse(DB.IsKnownClass("MONK"))
end)

-- ── `/kcd spells` (Forever) ─────────────────────────────────────────────────

test("Spells page (Forever): reset refuses a Retail spec token and writes no orphan list", function()
    local inst = forever("WARRIOR", true)
    local out = said(inst, "spells reset WARRIOR ARMS")
    assertNil(inst.NS.db.profile.spells.WARRIOR[71], "no Arms list")
    assertTrue(out:find("ARMS", 1, true) ~= nil, out)
end)

test("Spells page (Forever): reset refuses a Retail-only class", function()
    local inst = forever("WARRIOR", true)
    local out = said(inst, "spells reset DEATHKNIGHT")
    assertNil(inst.NS.db.profile.spells.DEATHKNIGHT, "no Death Knight list")
    assertTrue(out:find("DEATHKNIGHT", 1, true) ~= nil, out)
end)

test("Spells page (Forever): a CLASS alone names that class's one list, for every verb", function()
    local inst = forever("WARRIOR", true)
    local NS = inst.NS
    said(inst, "spells remove 1766 ROGUE")
    for _, e in ipairs(NS.Database:GetSpellList("ROGUE", ROGUE)) do
        assertTrue(e.spellID ~= 1766, "Kick removed from the Rogue's list")
    end
    said(inst, "spells add 1766 ROGUE")
    local last = NS.Database:GetSpellList("ROGUE", ROGUE)
    assertEqual(last[#last].spellID, 1766, "added back through a CLASS alone")
    said(inst, "spells reset ROGUE")
    assertEqual(NS.Database:GetSpellList("ROGUE", ROGUE)[1].spellID, 1766)
    local out = said(inst, "spells list ROGUE")
    assertTrue(out:find("Unknown", 1, true) == nil and out:find("written to the debug console", 1, true) ~= nil, out)
end)

test("Spells page (Forever): the command words say [CLASS], never [CLASS SPEC]", function()
    local inst = forever("WARRIOR", true)
    local out = said(inst, "spells")
    assertTrue(out:find("[CLASS]", 1, true) ~= nil, out)
    assertTrue(out:find("SPEC", 1, true) == nil, "no spec on WoW Forever:\n" .. out)
    out = said(inst, "spells remove")
    assertEqual(out:find("[CLASS SPEC]", 1, true), nil, out)
    assertTrue(out:find("[CLASS]", 1, true) ~= nil, out)
    local _, why = inst.NS.SpellInput.ParseTail({})
    assertEqual(why, "Usage: /kcd spells add <id|name> [CLASS]")
end)

-- ── the Spells page (Forever) ───────────────────────────────────────────────

test("Spells page (Forever): the picker reads Class, one row per Forever class with one name", function()
    local NS = forever("WARRIOR", true).NS
    local P = NS.Settings.SpellsPanel
    local entries = P.SpecEntries()
    assertEqual(#entries, 9)
    for _, e in ipairs(entries) do
        assertEqual(e.specID, NS.Const.SPEC_FOREVER[e.classFile], e.value)
        local name = P.ClassDisplayName(e.classFile)
        local _, n = e.label:gsub(name, name)
        assertEqual(n, 1, "the class's name once: " .. e.label)
    end
    assertEqual(P.PickerLabel(), NS.L["Class"])
end)

test("Spells page (Forever): the page opens on the player's own class list", function()
    local inst = forever("ROGUE", true)
    for _, ctx in ipairs(inst.NS.Settings.Helpers.__panels()) do ctx.panel:Show() end
    local P = inst.NS.Settings.SpellsPanel
    P:SeedSelectionToPlayer()
    local class, spec = P:GetSelection()
    assertEqual(class, "ROGUE")
    assertEqual(spec, ROGUE)
end)

-- ── Retail: unchanged ───────────────────────────────────────────────────────

test("Spells page (Retail): the picker, the tokens, the classes and the words are as before", function()
    local inst = T.load(true, true, retailClient)
    local NS = inst.NS
    local P = NS.Settings.SpellsPanel
    local want = 0
    for _, specs in pairs(NS.DefaultSpells) do
        for _ in pairs(specs) do want = want + 1 end
    end
    assertEqual(#P.SpecEntries(), want, "every Retail spec")
    assertEqual(P.PickerLabel(), NS.L["Class and specialization"])
    assertEqual(NS.Util.ResolveSpecID("ARMS", "WARRIOR"), 71)
    assertEqual(NS.Util.SpecDisplay(1491), "1491", "a Forever id means nothing on Retail")
    assertTrue(NS.Database.IsKnownClass("DEATHKNIGHT"))
    local out = said(inst, "spells")
    assertTrue(out:find("[CLASS SPEC]", 1, true) ~= nil, out)
    local _, why = NS.SpellInput.ParseTail({})
    assertEqual(why, "Usage: /kcd spells add <id|name> [CLASS SPEC]")
end)

test("Spells page (Retail): reset still takes what it is given, as before", function()
    local inst = T.load(true, true, retailClient)
    said(inst, "spells reset WARRIOR ARMS")
    assertTrue(inst.NS.db.profile.spells.WARRIOR[71] ~= nil, "Retail's reset is unchanged")
end)

test("Spells page (Forever): the Defaults popup and the list tab speak of a class", function()
    local inst = forever("WARRIOR", true)
    local NS = inst.NS
    assertEqual(inst.mocks.StaticPopupDialogs.KICKCD_RESET_SPELLS.text,
        NS.L["Reset all spells for this class to addon defaults?"])
    local retail = T.load(true, true, retailClient)
    assertEqual(retail.mocks.StaticPopupDialogs.KICKCD_RESET_SPELLS.text,
        retail.NS.L["Reset all spells for this spec to addon defaults?"])
end)
