-- tests/test_settings_widgets.lua — the pure logic behind the settings UI.
--
-- settings/ is the largest area of the addon by line count and was almost
-- entirely untested, because everything lived behind an AceGUI tree. The
-- pieces pinned here are the ones where a bug reaches the SavedVariables file
-- rather than just the screen:
--
--   * snapToStep decides what value a slider drag actually writes;
--   * validateSpellInput decides whether a spell the user typed is accepted
--     into their list at all, and is the one place a raw ID and a spell name
--     converge;
--   * specOrder decides which specs the editor is willing to render.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil

local inst    = T.load(true)
local NS      = inst.NS
local mocks   = inst.mocks
local Helpers = NS.Settings.Helpers
local Spells  = NS.Settings.SpellsPanel

test("the settings helpers are published for testing", function()
    assertTrue(type(Helpers.SnapToStep) == "function")
    assertTrue(type(Spells.ValidateSpellInput) == "function")
    assertTrue(type(Spells.SpecOrder) == "function")
    assertTrue(type(Spells.SortedKeys) == "function")
end)

-- ── snapToStep ──────────────────────────────────────────────────────────────

test("SnapToStep lands a drag on the nearest step", function()
    -- Without snapping, a size slider writes 17.3194 into SavedVariables and
    -- the panel then displays that back to the user.
    assertEqual(Helpers.SnapToStep(17, 0, 5), 15)
    assertEqual(Helpers.SnapToStep(18, 0, 5), 20)
end)

test("SnapToStep rounds a value exactly halfway UP", function()
    -- Deterministic tie-breaking; otherwise the same drag can land either way
    -- depending on float noise.
    assertEqual(Helpers.SnapToStep(12.5, 0, 5), 15)
end)

test("SnapToStep measures steps from the slider's MINIMUM, not from zero", function()
    -- A range starting at 8 with step 5 must offer 8/13/18, not 10/15/20 —
    -- otherwise the minimum itself isn't reachable.
    assertEqual(Helpers.SnapToStep(8, 8, 5), 8)
    assertEqual(Helpers.SnapToStep(10, 8, 5), 8)
    assertEqual(Helpers.SnapToStep(11, 8, 5), 13)
end)

test("SnapToStep handles a negative minimum (offset sliders)", function()
    assertEqual(Helpers.SnapToStep(-7, -20, 5), -5)
    assertEqual(Helpers.SnapToStep(-20, -20, 5), -20)
end)

test("SnapToStep leaves the value alone when there is no step", function()
    -- A continuous slider must not be quantised to whatever step happened to
    -- be nil-defaulted.
    assertEqual(Helpers.SnapToStep(17.3, 0, nil), 17.3)
    assertEqual(Helpers.SnapToStep(17.3, 0, 0), 17.3)
end)

test("SnapToStep supports a fractional step", function()
    -- Alpha and scale rows step by 0.05 / 0.1.
    assertEqual(Helpers.SnapToStep(0.72, 0, 0.1), 0.7000000000000001)
    assertEqual(Helpers.SnapToStep(1, 0, 0.25), 1)
end)

-- ── sortedKeys ──────────────────────────────────────────────────────────────

test("SortedKeys returns a deterministic ordering", function()
    -- pairs() order is undefined, so a UI built straight off it reshuffles
    -- between sessions.
    local keys = Spells.SortedKeys({ [264] = 1, [262] = 1, [263] = 1 })
    assertEqual(keys[1], 262); assertEqual(keys[2], 263); assertEqual(keys[3], 264)
end)

test("SortedKeys returns an empty list for a nil or non-table input", function()
    assertEqual(#Spells.SortedKeys(nil), 0)
    assertEqual(#Spells.SortedKeys("not a table"), 0)
end)

-- ── specOrder ───────────────────────────────────────────────────────────────

test("SpecOrder lists specs in Blizzard's order, not numeric order", function()
    -- The editor dropdown has to match the character sheet. For SHAMAN the
    -- two orders coincide numerically, so assert against the client's list.
    local order = Spells.SpecOrder("SHAMAN")
    assertEqual(order[1], NS.Const.SPEC.ELEMENTAL)
    assertEqual(order[2], NS.Const.SPEC.ENHANCEMENT)
    assertEqual(order[3], NS.Const.SPEC.RESTORATION_SHAMAN)
end)

test("SpecOrder falls back to sorted numeric keys when the client can't be queried", function()
    -- The mock client enumerates only three classes; MAGE is one it can't,
    -- which is the same shape as an early-login query.
    local order = Spells.SpecOrder("MAGE")
    assertEqual(#order, 3)
    assertEqual(order[1], NS.Const.SPEC.ARCANE)   -- 62
    assertEqual(order[2], NS.Const.SPEC.FIRE)     -- 63
    assertEqual(order[3], NS.Const.SPEC.FROST_MAGE) -- 64
end)

test("SpecOrder only offers specs the addon ships defaults for", function()
    -- Listing a spec with no default list would open an editor that renders
    -- nothing, with no explanation.
    for _, classFile in ipairs({ "SHAMAN", "HUNTER", "WARLOCK", "DRUID" }) do
        for _, specID in ipairs(Spells.SpecOrder(classFile)) do
            assertTrue(NS.DefaultSpells[classFile][specID] ~= nil,
                classFile .. " offers spec " .. specID .. " with no default list")
        end
    end
end)

test("SpecOrder lists EVERY spec the defaults ship for that class", function()
    -- The other direction: a spec added to defaults ahead of a client patch
    -- still has to appear, which is what the reconciliation pass is for.
    for _, classFile in ipairs({ "SHAMAN", "DRUID", "DEMONHUNTER" }) do
        local listed = {}
        for _, id in ipairs(Spells.SpecOrder(classFile)) do listed[id] = true end
        for specID in pairs(NS.DefaultSpells[classFile]) do
            assertTrue(listed[specID],
                classFile .. " spec " .. specID .. " ships defaults but isn't offered")
        end
    end
end)

test("SpecOrder is empty for a class with no shipped defaults", function()
    assertEqual(#Spells.SpecOrder("NOSUCHCLASS"), 0)
    assertEqual(#Spells.SpecOrder(nil), 0)
end)

test("Druid's four specs all survive the ordering", function()
    -- The only four-spec class, and the one most likely to be truncated by an
    -- off-by-one in the reconciliation.
    assertEqual(#Spells.SpecOrder("DRUID"), 4)
end)

-- ── validateSpellInput ──────────────────────────────────────────────────────

test("ValidateSpellInput accepts a numeric spell ID and resolves its name", function()
    local id, name = Spells.ValidateSpellInput(1766)
    assertEqual(id, 1766)
    assertEqual(name, "Spell1766")
end)

test("ValidateSpellInput accepts an ID typed as a string", function()
    -- The edit box always hands back a string.
    local id = Spells.ValidateSpellInput("1766")
    assertEqual(id, 1766)
end)

test("ValidateSpellInput rejects empty and nil input", function()
    assertNil(Spells.ValidateSpellInput(""))
    assertNil(Spells.ValidateSpellInput(nil))
end)

test("ValidateSpellInput rejects an ID the client doesn't know", function()
    -- Accepting it would add a row that can never render an icon or a name.
    local prev = mocks.C_Spell.GetSpellInfo
    mocks.C_Spell.GetSpellInfo = function() return nil end
    assertNil(Spells.ValidateSpellInput(999999))
    mocks.C_Spell.GetSpellInfo = prev
end)

test("ValidateSpellInput resolves a spell NAME to its numeric ID", function()
    -- Names are accepted for convenience but must never be STORED — the list
    -- keys on the ID, which is locale-invariant.
    local prev = mocks.C_Spell.GetSpellInfo
    mocks.C_Spell.GetSpellInfo = function(input)
        if input == "Kick" then
            return { name = "Kick", iconID = 1, spellID = 1766 }
        end
        return nil
    end
    local id, name = Spells.ValidateSpellInput("Kick")
    assertEqual(id, 1766)
    assertEqual(name, "Kick")
    mocks.C_Spell.GetSpellInfo = prev
end)

test("ValidateSpellInput rejects a name that resolves to no spell", function()
    local prev = mocks.C_Spell.GetSpellInfo
    mocks.C_Spell.GetSpellInfo = function() return nil end
    assertNil(Spells.ValidateSpellInput("Not A Spell"))
    mocks.C_Spell.GetSpellInfo = prev
end)

test("ValidateSpellInput refuses a name whose lookup yields no ID", function()
    -- A name without a resolved ID cannot be keyed on, so a partial hit has
    -- to be rejected rather than stored under a nil key.
    local prev = mocks.C_Spell.GetSpellInfo
    mocks.C_Spell.GetSpellInfo = function() return { name = "Kick" } end
    assertNil(Spells.ValidateSpellInput("Kick"))
    mocks.C_Spell.GetSpellInfo = prev
end)

-- ── Class display names ─────────────────────────────────────────────────────

test("ClassDisplayName spaces the two-word class tokens", function()
    -- "Deathknight" is wrong in a UI the user reads.
    assertEqual(Spells.ClassDisplayName("DEATHKNIGHT"), "Death Knight")
    assertEqual(Spells.ClassDisplayName("DEMONHUNTER"), "Demon Hunter")
end)

test("TitleCaseToken lower-cases everything after the first letter", function()
    assertEqual(Spells.TitleCaseToken("HUNTER"), "Hunter")
    assertEqual(Spells.TitleCaseToken("ELEMENTAL"), "Elemental")
end)

test("TitleCaseToken returns an empty string for nil rather than erroring", function()
    -- It feeds a SetText call on a path that can run before the class is known.
    assertEqual(Spells.TitleCaseToken(nil), "")
end)

test("every shipped class token produces a non-empty display name", function()
    -- A blank entry in the class dropdown is unselectable.
    for classFile in pairs(NS.DefaultSpells) do
        local name = Spells.ClassDisplayName(classFile)
        assertTrue(type(name) == "string" and #name > 0,
            classFile .. " has no display name")
    end
end)
