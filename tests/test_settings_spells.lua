-- tests/test_settings_spells.lua — Spells editor selection state
--
-- The editor keeps its own (class, spec) selection, seeded from the player
-- and steered by the dropdown. These cases cover the seeding rules and the
-- spec-change tracking that the dropdown depends on.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local HUNTER_CLASS_ID, SHAMAN_CLASS_ID = 3, 7
local BEASTMASTERY, MARKSMANSHIP = 253, 254
local ELEMENTAL, ENHANCEMENT = 262, 263

local function panelFor(inst)
    return inst.NS.Settings and inst.NS.Settings.SpellsPanel
end

test("Spells editor seeds its selection to the player's own class and spec", function()
    local inst = T.load(true, false, function(mocks)
        mocks.UnitClass = function() return "Shaman", "SHAMAN", 7 end
        mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 1)
    end)
    local p = panelFor(inst)
    p:SeedSelectionToPlayer()
    local class, spec = p:GetSelection()
    assertEqual(class, "SHAMAN")
    assertEqual(spec, ELEMENTAL, "the seeded spec must be the numeric specID")
end)

test("Spells editor selection follows an in-game spec change (dropdown regression)", function()
    -- Regression: swapping spec with Settings > Spells already OPEN left the
    -- dropdown on the old spec. freshOpen was only re-armed on a full
    -- Settings close, and the panel's SPELLS_CHANGED / TRAIT_CONFIG_UPDATED
    -- handlers only re-rendered rows — nothing re-read the player's spec.
    local inst = T.load(true, false, function(mocks)
        mocks.UnitClass = function() return "Shaman", "SHAMAN", 7 end
        mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 1)
    end)
    local p = panelFor(inst)
    p:SeedSelectionToPlayer()
    assertEqual(select(2, p:GetSelection()), ELEMENTAL)

    -- The player respecs to Enhancement.
    inst.mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 2)
    p:OnPlayerSpecChanged()

    assertEqual(select(2, p:GetSelection()), ENHANCEMENT,
        "the editor must follow the player's new spec, not stay on the old one")
end)

test("Spells editor spec change also tracks a class it can render", function()
    local inst = T.load(true, false, function(mocks)
        mocks.UnitClass = function() return "Hunter", "HUNTER", 3 end
        mocks.__setPlayerSpec(HUNTER_CLASS_ID, 1)
    end)
    local p = panelFor(inst)
    p:SeedSelectionToPlayer()
    assertEqual(select(2, p:GetSelection()), BEASTMASTERY)
    inst.mocks.__setPlayerSpec(HUNTER_CLASS_ID, 2)
    p:OnPlayerSpecChanged()
    local class, spec = p:GetSelection()
    assertEqual(class, "HUNTER")
    assertEqual(spec, MARKSMANSHIP)
end)

test("Spells editor exposes specs in Blizzard's order, not numeric order", function()
    -- Shaman IDs happen to ascend with spec order; Monk's do not
    -- (Brewmaster 268, Windwalker 269, Mistweaver 270 vs. the character
    -- sheet's Brewmaster / Mistweaver / Windwalker). Assert against a class
    -- the mock enumerates so the ordering source is unambiguous.
    local inst = T.load(true, false, function(mocks)
        mocks.UnitClass = function() return "Shaman", "SHAMAN", 7 end
        mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 1)
    end)
    local order = inst.NS.Util.SpecOrderForClass("SHAMAN")
    assertTrue(order ~= nil, "the client's spec order must be available")
    assertEqual(order[1], ELEMENTAL)
    assertEqual(order[2], ENHANCEMENT)
end)
