-- tests/test_locale.lua — locale independence of spec resolution (issue #8)
--
-- Regression cover for the frFR bug where the addon derived its spell-list
-- key from GetSpecializationInfo's LOCALISED second return, so a French
-- Elemental Shaman looked up spells[SHAMAN]["ÉLÉMENTAIRE"] against defaults
-- keyed "ELEMENTAL" and silently got an empty list.
--
-- Every case here drives the mock through loadInstance's `mutate` hook so
-- the simulated client is non-English BEFORE OnInitialize runs — the seeding
-- happens at init, so a post-load mock swap would test nothing.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local SHAMAN_CLASS_ID = 7
local ELEMENTAL = 262

-- frFR display names for the specs the mock knows about.
local FRENCH = {
    [262] = "Élémentaire",
    [263] = "Amélioration",
    [264] = "Restauration",
    [266] = "Démonologie",
}

--- Load a fresh addon instance simulating a client of the given locale.
local function loadClient(classID, specIndex, names)
    return T.load(true, false, function(mocks)
        mocks.UnitClass = function() return "Chaman", "SHAMAN", 7 end
        mocks.__setPlayerSpec(classID, specIndex, names)
        if names then mocks.GetLocale = function() return "frFR" end end
    end)
end

test("frFR Elemental Shaman seeds a non-empty default spell list (issue #8)", function()
    local ns = loadClient(SHAMAN_CLASS_ID, 1, FRENCH).NS
    local list = ns.Database:GetSpellList("SHAMAN", ELEMENTAL)
    assertTrue(type(list) == "table" and #list > 0,
        "a French Elemental Shaman must get the same defaults as an English one")
end)

test("frFR and enUS Elemental Shaman seed byte-identical spell lists", function()
    local fr = loadClient(SHAMAN_CLASS_ID, 1, FRENCH).NS
    local en = loadClient(SHAMAN_CLASS_ID, 1, nil).NS
    local frList = fr.Database:GetSpellList("SHAMAN", ELEMENTAL) or {}
    local enList = en.Database:GetSpellList("SHAMAN", ELEMENTAL) or {}
    -- Guard against the comparison passing vacuously with two empty lists.
    assertTrue(#enList > 0, "the enUS baseline must actually be seeded")
    assertEqual(#frList, #enList, "locale must not change the seeded list length")
    for i, entry in ipairs(enList) do
        assertEqual(frList[i].spellID, entry.spellID,
            "spell #" .. i .. " must match across locales")
    end
end)

test("frFR player spec resolves to the locale-invariant numeric spec ID", function()
    local ns = loadClient(SHAMAN_CLASS_ID, 1, FRENCH).NS
    assertEqual(ns.Util.PlayerSpecID(), ELEMENTAL,
        "PlayerSpecID must read the numeric ID, never the localised name")
end)

test("frFR client resolves a localised spec name typed at the slash command", function()
    local ns = loadClient(SHAMAN_CLASS_ID, 1, FRENCH).NS
    assertEqual(ns.Util.ResolveSpecID("Élémentaire", "SHAMAN"), ELEMENTAL,
        "a French user typing their own spec name must resolve")
    assertEqual(ns.Util.ResolveSpecID("elemental", "SHAMAN"), ELEMENTAL,
        "the English token must keep working on a French client")
end)

test("frFR Elemental Shaman actually watches its cooldowns end-to-end (issue #8)", function()
    -- The reporter's symptom was an empty grid, not an empty saved table:
    -- seeding and lookup are separate paths and both had to be locale-free.
    -- Drive the real Cooldowns:Rebuild and count what it ends up watching.
    local ns = loadClient(SHAMAN_CLASS_ID, 1, FRENCH).NS
    local Cooldowns = ns:GetModule("Cooldowns")
    Cooldowns:Rebuild()
    local n = 0
    for _ in pairs(Cooldowns.watched or {}) do n = n + 1 end
    assertTrue(n > 0, "a French Elemental Shaman must end up watching spells, not an empty grid")
end)

test("the Spells editor labels specs in the client's own language", function()
    -- Keys must be locale-free; the UI must NOT be. A French user should
    -- read "Élémentaire" in the dropdown even though the key is 262.
    local fr = loadClient(SHAMAN_CLASS_ID, 1, FRENCH).NS
    assertEqual(fr.Util.SpecDisplayName(ELEMENTAL), "Élémentaire")
    local en = loadClient(SHAMAN_CLASS_ID, 1, nil).NS
    assertEqual(en.Util.SpecDisplayName(ELEMENTAL), "Elemental")
end)

test("SpecDisplayName falls back to the English token for an unknown spec", function()
    local ns = loadClient(SHAMAN_CLASS_ID, 1, nil).NS
    -- 250 (Blood) is a real spec ID the mock's three classes don't cover, so
    -- the localised lookup misses and the Const.SPEC token has to carry it.
    assertEqual(ns.Util.SpecDisplayName(250), "Blood")
end)

test("a spec-name lookup that ran before the client was ready retries later", function()
    -- Database:Init runs at ADDON_LOADED and resolves spec keys there. If the
    -- class/spec query isn't answering yet, caching that empty result would
    -- strand a localised profile permanently — the migration would silently
    -- stop recognising localised keys for the whole session.
    -- Asserts on a LOCALISED name throughout: the English token resolves from
    -- the static Const.SPEC table regardless of client readiness, so it would
    -- pass either way and prove nothing.
    local inst = T.load(true, false, function(mocks)
        mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 1, FRENCH)
        mocks.GetNumClasses = function() return 0 end
    end)
    local ns = inst.NS
    assertEqual(ns.Util.ResolveSpecID("Élémentaire", "SHAMAN"), nil,
        "with no client data there is nothing to resolve against")

    -- The client comes up.
    inst.mocks.GetNumClasses = function() return 13 end
    assertEqual(ns.Util.ResolveSpecID("Élémentaire", "SHAMAN"), ELEMENTAL,
        "the map must rebuild once the client answers, not stay empty")
end)

test("every default spell list is reachable on a French client", function()
    -- The bug was not Shaman-specific: any spec whose localised name differs
    -- from the English one was unreachable. Walk the whole defaults table and
    -- assert each key is a numeric spec ID, which is locale-invariant by
    -- construction.
    local ns = loadClient(SHAMAN_CLASS_ID, 1, FRENCH).NS
    for classFile, specs in pairs(ns.DefaultSpells) do
        for specKey in pairs(specs) do
            assertEqual(type(specKey), "number",
                classFile .. " spec key must be a numeric spec ID, got " .. tostring(specKey))
        end
    end
end)
