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
    -- PANEL_PADDING_X is NOT here: it was a host copy of the library's
    -- published PADDING_X and is deleted (options-ui-§8). The case below
    -- pins that it stays deleted.
    for _, key in ipairs({ "PANEL_HEADER_TOP",
                           "PANEL_HEADER_HEIGHT", "PANEL_DEFAULTS_W" }) do
        assertTrue(type(Const[key]) == "number" and Const[key] > 0,
            key .. " must be a positive number")
    end
end)

-- The panel metrics that are NOT in the loop above because the host no longer
-- declares them: they come off the LibKa0s-Options instance. Deleting the host
-- copies deleted the "is a positive number" guarantee along with them, and
-- nothing replaced it — the lint below only asserts the host does not RESTATE a
-- number, which stays green when the library stops publishing one. These two
-- cases restore the guarantee, read off the instance instead of off Const.
test("Constants: the library publishes every panel layout metric as a positive number", function()
    -- NS.Settings.Helpers IS the LibKa0s-Options instance (test_options_panel.lua:70).
    -- If a future LibKa0s stops publishing one of these, settings/Panel_Render.lua:20
    -- and settings/Panel_Widgets.lua:49 bind nil at file load and forward nil.
    local H = NS.Settings.Helpers
    for _, key in ipairs({ "PADDING_X", "ROW_VSPACER",
                           "SECTION_HEADING_H", "BUTTON_PAIR_REL" }) do
        assertTrue(type(H[key]) == "number" and H[key] > 0,
            "Helpers." .. key .. " must be published as a positive number, got "
            .. tostring(H[key]))
    end
end)

test("Constants: a rendered unit panel spaces its rows by a real number of pixels", function()
    -- The user-visible end of the same guarantee, and the reason the type check
    -- above is not enough on its own: settings/Panel_Render.lua:20 binds
    -- `local ROW_VSPACER = Helpers.ROW_VSPACER` AT FILE LOAD and forwards that
    -- binding at :83 and :117. A nil arriving there is silent — AddSpacer
    -- creates a full-width SimpleGroup with no height, every options row loses
    -- its spacing in game, and nothing raises.
    --
    -- red under: `O.ROW_VSPACER = nil` at libs/LibKa0s/Options.lua:210.
    local H = NS.Settings.Helpers
    local AceGUI = T.mocks.LibStub("AceGUI-3.0")
    local ctx = H.CreatePanel("KickCDRowSpacing", "Row spacing", { pageKey = "castbar" })
    ctx.scroll = AceGUI:Create("ScrollFrame")
    ctx.unit = "target"

    H.RenderUnitPanel(ctx, "castbar")

    -- The spacers are the layout-less full-width SimpleGroups AddSpacer makes.
    local spacers = 0
    for _, child in ipairs(ctx.scroll.children) do
        if child.type == "SimpleGroup" and child.fullWidth and child.layout == nil then
            spacers = spacers + 1
            assertTrue(type(child.height) == "number" and child.height > 0,
                "row spacer " .. spacers .. " rendered with height "
                .. tostring(child.height) .. "; rows would sit flush in game")
        end
    end
    assertTrue(spacers > 0,
        "precondition: rendering a unit panel must emit at least one row spacer")
end)

test("Constants: no host copy of a LibKa0s-Options layout constant", function()
    -- options-ui-§8: a host MUST NOT restate a value the options library
    -- publishes on the instance. A host copy is the one that goes stale, and
    -- because both copies start out equal nothing observes the divergence
    -- until the library retunes its value and only some panels move.
    --
    -- This addon shipped two: `Const.PANEL_PADDING_X = 16` restating
    -- `lib.LAYOUT.PADDING_X`, and `settings/Panel.lua`'s `local ROW_VSPACER = 8`
    -- which then ASSIGNED ITSELF OVER the published `O.ROW_VSPACER`, so the
    -- library's value could not have won even where a caller read the instance.
    -- Both are gone; this is what keeps them gone.
    --
    -- Source-scanned rather than driven, per testing-§11: a reintroduced copy
    -- is a declaration, and no runtime observation distinguishes "read the
    -- library's 8" from "read a host 8" while the two agree — which is the
    -- entire failure mode.
    --
    -- red under: restoring `Const.PANEL_PADDING_X = 16` in core/Constants.lua,
    -- or `local ROW_VSPACER = 8` in settings/Panel.lua.
    local published = { "PADDING_X", "ROW_VSPACER", "SECTION_HEADING_H", "BUTTON_PAIR_REL" }
    local offenders = {}
    for _, rel in ipairs({ "core/Constants.lua", "settings/Panel.lua",
                           "settings/Panel_Render.lua", "settings/Panel_Widgets.lua" }) do
        local fh = assert(io.open(T.root .. "/" .. rel, "r"))
        local ln = 0
        for line in fh:lines() do
            ln = ln + 1
            local code = line:gsub("%-%-.*$", "")
            for _, key in ipairs(published) do
                -- A declaration assigning a NUMERIC LITERAL to the published
                -- name (with or without a PANEL_ prefix). Reading the value off
                -- the instance -- `= Helpers.ROW_VSPACER` -- is the compliant
                -- shape and must not trip this.
                if code:match("[%w_.]*" .. key .. "%s*=%s*[%d.]+%s*$") then
                    offenders[#offenders + 1] = rel .. ":" .. ln .. " " .. line:gsub("^%s+", "")
                end
            end
        end
        fh:close()
    end
    assertEqual(#offenders, 0,
        "host copies of a published LibKa0s-Options layout constant:\n  "
        .. table.concat(offenders, "\n  "))
end)

-- ── Shipped media ───────────────────────────────────────────────────────────

test("Constants: FONT_MONO points at a font that is actually shipped", function()
    -- A path typo here is invisible until a user opens the debug console and gets
    -- Blizzard's fallback font, so check the file exists on disk. The bytes moved
    -- OUT of this addon and into the vendored LibKa0s payload, so what is checked
    -- now is the copy under libs/ — a re-vendor that dropped media/fonts/, or a
    -- packaging step that filtered it out, is exactly this test's job.
    -- The constant is a WoW-style path; map it back to a repo-relative one.
    local rel = Const.FONT_MONO:gsub("\\", "/"):gsub("^Interface/AddOns/KickCD/", "")
    assertTrue(rel:find("libs/LibKa0s/media/fonts/", 1, true) ~= nil,
        "FONT_MONO must resolve into the vendored payload, got " .. rel)
    local fh = io.open(T.root .. "/" .. rel, "r")
    assertTrue(fh ~= nil, "missing shipped font: " .. rel)
    if fh then fh:close() end
end)

test("Constants: the shipped mono font ships its OFL license alongside it", function()
    -- debug-logging-§2 requires the license to travel with the font. It travels with
    -- the LIBRARY now: one copy of the face for the whole collection means one copy
    -- of the license, and it has to arrive in the vendored payload or this build
    -- ships a font it has no license for.
    local fh = io.open(T.root .. "/libs/LibKa0s/media/fonts/JetBrainsMono-OFL.txt", "r")
    assertTrue(fh ~= nil, "the shipped font's OFL license is missing")
    if fh then fh:close() end
end)

test("Constants: this addon no longer ships its own copy of the mono font", function()
    -- red under: media/fonts/ coming back. Two copies of one face is two licenses to
    -- track and two provenance stories, and the second copy is the one that silently
    -- stops matching after the first is regenerated (library-stack-§8).
    local fh = io.open(T.root .. "/media/fonts/JetBrainsMono-Regular.ttf", "rb")
    if fh then fh:close() end
    assertTrue(fh == nil,
        "media/fonts/ is back — the face ships in libs/LibKa0s/media/fonts/ now")
end)

test("Constants: FONT_MONO is the face FONT_MONO_NAME names, not a hand-typed path", function()
    -- The two constants answer different questions -- a name for LibSharedMedia and
    -- for anything a profile stores, a path for SetFont -- and they must be two
    -- spellings of ONE face. A profile naming a key nobody registered renders in
    -- Blizzard's fallback, which is the exact outcome shipping a monospace font was
    -- meant to prevent.
    assertEqual(Const.FONT_MONO, NS.MediaFont(Const.FONT_MONO_NAME))
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
