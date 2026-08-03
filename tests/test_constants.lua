-- tests/test_constants.lua — integrity of core/Constants.lua.
--
-- Constants.lua carries no logic, so nothing here asserts behavior: it
-- asserts that the tables are INTERNALLY CONSISTENT and that the rest of the
-- addon can't have drifted away from them. That matters more than it sounds.
-- Const.SPEC is the locale-invariant identity every spell list, every
-- SavedVariables key and the v2→v3 migration are keyed by (issue #8), and
-- Const.SPEC_TOKEN is derived from it by a `gsub` that silently drops an
-- entry if two tokens ever collide on one specID.
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local Const = NS.Const

-- The four spec names Blizzard reuses across classes. Const.SPEC has to
-- disambiguate these with a _CLASS suffix; every other token stands alone.
local SHARED_NAMES = { FROST = true, HOLY = true, PROTECTION = true, RESTORATION = true }

-- ── Chat styling ────────────────────────────────────────────────────────────

test("Constants: the chat prefix is the cyan [KCD] tag and closes its color code", function()
    assertEqual(NS.PREFIX, "|cff00ffff[KCD]|r")
end)

test("Constants: the notice gray is an opener with no closer (callers add |r)", function()
    assertTrue(NS.GRAY:match("^|cff%x%x%x%x%x%x$") ~= nil,
        "GRAY must be a bare color opener, got " .. tostring(NS.GRAY))
end)

-- ── Numeric constants ───────────────────────────────────────────────────────

test("Constants: the GCD upper bound covers an unhasted 1.5s global", function()
    -- Below 1.5 and an unhasted GCD would be classified as a real cooldown,
    -- dimming and tinting every icon for the whole global.
    assertTrue(Const.GCD_UPPER >= 1.5, "GCD_UPPER must cover the unhasted 1.5s global")
    assertTrue(Const.GCD_UPPER < 2, "GCD_UPPER must stay below any real cooldown")
end)

test("Constants: the cast bar's inside and outside insets are symmetric", function()
    -- The two exist so the visual gap is identical whichever side the spell
    -- name sits on; if they drift apart the text jumps when the user flips
    -- the name position.
    assertEqual(Const.CASTBAR_INSIDE_INSET, Const.CASTBAR_OUTSIDE_INSET)
end)

test("Constants: the panel header reserves more height than its top inset", function()
    -- HEADER_HEIGHT positions the divider BELOW the title that HEADER_TOP
    -- positions; inverting them would draw the divider through the title.
    assertTrue(Const.PANEL_HEADER_HEIGHT > Const.PANEL_HEADER_TOP,
        "the divider must sit below the title")
end)

test("Constants: every panel metric is a positive number", function()
    for _, key in ipairs({ "PANEL_PADDING_X", "PANEL_HEADER_TOP",
                           "PANEL_HEADER_HEIGHT", "PANEL_DEFAULTS_W" }) do
        assertTrue(type(Const[key]) == "number" and Const[key] > 0,
            key .. " must be a positive number")
    end
end)

-- ── Shipped media ───────────────────────────────────────────────────────────

test("Constants: FONT_MONO points at a font that is actually shipped", function()
    -- A path typo here is invisible until a user opens the debug console and
    -- gets Blizzard's fallback font, so check the file exists on disk.
    -- The constant is a WoW-style path; map it back to a repo-relative one.
    local rel = Const.FONT_MONO:gsub("\\", "/"):gsub("^Interface/AddOns/KickCD/", "")
    local fh = io.open(T.root .. "/" .. rel, "r")
    assertTrue(fh ~= nil, "missing shipped font: " .. rel)
    if fh then fh:close() end
end)

test("Constants: the shipped mono font ships its OFL license alongside it", function()
    -- §12.2 requires the license to travel with the font.
    local fh = io.open(T.root .. "/media/fonts/JetBrainsMono-OFL.txt", "r")
    assertTrue(fh ~= nil, "the shipped font's OFL license is missing")
    if fh then fh:close() end
end)

-- ── Const.SPEC ──────────────────────────────────────────────────────────────

test("Constants: every spec ID is a positive integer", function()
    for token, id in pairs(Const.SPEC) do
        assertTrue(type(id) == "number" and id > 0 and id % 1 == 0,
            token .. " must map to a positive integer spec ID, got " .. tostring(id))
    end
end)

test("Constants: every spec token is UPPER_SNAKE_CASE", function()
    for token in pairs(Const.SPEC) do
        assertTrue(token:match("^[A-Z][A-Z_]*$") ~= nil,
            "spec token " .. token .. " is not UPPER_SNAKE_CASE")
    end
end)

test("Constants: no two spec tokens share a spec ID", function()
    -- A duplicate would be invisible in SPEC but destructive in SPEC_TOKEN:
    -- the reverse map is built by assignment, so the second token silently
    -- overwrites the first and one spec starts displaying another's name.
    local owner = {}
    for token, id in pairs(Const.SPEC) do
        assertTrue(owner[id] == nil,
            ("spec ID %d is claimed by both %s and %s"):format(id, tostring(owner[id]), token))
        owner[id] = token
    end
end)

test("Constants: the three Midnight-era spec IDs are present and correct", function()
    -- Devourer is new in 12.0 and the Evoker specs post-date several guides,
    -- so pin them against the ChrSpecialization DB2 values the file cites.
    assertEqual(Const.SPEC.DEVOURER, 1480)
    assertEqual(Const.SPEC.DEVASTATION, 1467)
    assertEqual(Const.SPEC.AUGMENTATION, 1473)
end)

test("Constants: SPEC covers all thirteen player classes at three specs each", function()
    -- Druid is the only four-spec class; every other class ships three.
    -- 12 * 3 + 4 = 40. A miscount means a whole spec can never be tracked.
    local n = 0
    for _ in pairs(Const.SPEC) do n = n + 1 end
    assertEqual(n, 40, "expected 40 player specs across the 13 classes")
end)

-- ── Const.SPEC_TOKEN (the derived reverse map) ──────────────────────────────

test("Constants: every spec ID has a reverse token", function()
    for token, id in pairs(Const.SPEC) do
        assertTrue(Const.SPEC_TOKEN[id] ~= nil,
            token .. " (" .. id .. ") has no SPEC_TOKEN entry")
    end
end)

test("Constants: the reverse map is exactly as large as the forward map", function()
    -- Equal sizes is the structural proof that no entry was lost to a
    -- collision — the failure mode the duplicate-ID test guards from the
    -- other side.
    local fwd, rev = 0, 0
    for _ in pairs(Const.SPEC) do fwd = fwd + 1 end
    for _ in pairs(Const.SPEC_TOKEN) do rev = rev + 1 end
    assertEqual(rev, fwd)
end)

test("Constants: the reverse map strips the disambiguating class suffix", function()
    -- The specID already carries the class, so the display token shouldn't
    -- repeat it: 251 is "FROST", not "FROST_DK".
    assertEqual(Const.SPEC_TOKEN[Const.SPEC.FROST_DK], "FROST")
    assertEqual(Const.SPEC_TOKEN[Const.SPEC.FROST_MAGE], "FROST")
    assertEqual(Const.SPEC_TOKEN[Const.SPEC.RESTORATION_DRUID], "RESTORATION")
    assertEqual(Const.SPEC_TOKEN[Const.SPEC.HOLY_PALADIN], "HOLY")
    assertEqual(Const.SPEC_TOKEN[Const.SPEC.PROTECTION_WARRIOR], "PROTECTION")
end)

test("Constants: a non-shared token survives the suffix strip unchanged", function()
    -- The gsub is anchored to a trailing _WORD, so a single-word token must
    -- pass through untouched.
    assertEqual(Const.SPEC_TOKEN[Const.SPEC.ELEMENTAL], "ELEMENTAL")
    assertEqual(Const.SPEC_TOKEN[Const.SPEC.BEASTMASTERY], "BEASTMASTERY")
end)

test("Constants: exactly the four reused spec names carry a class suffix", function()
    -- Suffixing a token whose name isn't actually shared would make
    -- `/kcd spells ... <SPEC>` reject the name a user reads on their
    -- character sheet.
    for token in pairs(Const.SPEC) do
        local base, suffix = token:match("^([A-Z]+)_([A-Z]+)$")
        if suffix then
            assertTrue(SHARED_NAMES[base] ~= nil,
                token .. " carries a class suffix but " .. base .. " is not a shared spec name")
        end
    end
end)

test("Constants: every shared spec name is suffixed on every class that has it", function()
    -- The inverse direction: an unsuffixed FROST/HOLY/PROTECTION/RESTORATION
    -- would collide with its sibling and lose an entry from SPEC_TOKEN.
    for token in pairs(Const.SPEC) do
        assertTrue(SHARED_NAMES[token] == nil,
            token .. " is a shared spec name and must carry a class suffix")
    end
end)

-- ── Cross-file: defaults/Spells.lua is keyed by these IDs ───────────────────

test("Constants: every spec key in defaults/Spells.lua is a known spec ID", function()
    -- The shipped defaults are written as [SPEC.X], so a key that isn't in
    -- SPEC means a nil index leaked in and that spec seeds nothing.
    for classFile, specs in pairs(NS.DefaultSpells) do
        for specID in pairs(specs) do
            assertTrue(Const.SPEC_TOKEN[specID] ~= nil,
                ("%s ships a default list under unknown spec ID %s"):format(
                    classFile, tostring(specID)))
        end
    end
end)

test("Constants: every spec ID in Const.SPEC has a shipped default list", function()
    -- The other direction: a spec the addon knows about but ships no
    -- cooldowns for tracks nothing at all on a fresh install.
    local seeded = {}
    for _, specs in pairs(NS.DefaultSpells) do
        for specID in pairs(specs) do seeded[specID] = true end
    end
    for token, id in pairs(Const.SPEC) do
        assertTrue(seeded[id], token .. " (" .. id .. ") has no default spell list")
    end
end)

test("Constants: defaults ship one class table per class, all UPPER-case tokens", function()
    local n = 0
    for classFile in pairs(NS.DefaultSpells) do
        n = n + 1
        assertTrue(classFile:match("^[A-Z]+$") ~= nil,
            "class key " .. classFile .. " must be the UnitClass file token")
    end
    assertEqual(n, 13, "expected a default spell table for each of the 13 classes")
end)
