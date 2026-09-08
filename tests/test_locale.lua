-- tests/test_locale.lua — locale independence of spec resolution (issue #8)
--
-- Regression cover for the frFR bug where the addon derived its spell-list
-- key from GetSpecializationInfo's LOCALIZED second return, so a French
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
        "PlayerSpecID must read the numeric ID, never the localized name")
end)

test("frFR client resolves a localized spec name typed at the slash command", function()
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
    -- the localized lookup misses and the Const.SPEC token has to carry it.
    assertEqual(ns.Util.SpecDisplayName(250), "Blood")
end)

test("a spec-name lookup that ran before the client was ready retries later", function()
    -- Database:Init runs at ADDON_LOADED and resolves spec keys there. If the
    -- class/spec query isn't answering yet, caching that empty result would
    -- strand a localized profile permanently — the migration would silently
    -- stop recognizing localized keys for the whole session.
    -- Asserts on a LOCALIZED name throughout: the English token resolves from
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
    -- The bug was not Shaman-specific: any spec whose localized name differs
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

-- ===========================================================================
-- The routing gate — locales/enUS.lua against the TOC-derived source list
-- ===========================================================================
--
-- The half above asks whether a locale can BREAK the addon. This half asks
-- whether the addon's user-facing text ever reaches the locale seam at all,
-- which is a different question and until now nothing asked it.
--
-- THE SHAPE THIS DELIBERATELY DOES NOT HAVE. The obvious coverage case is a
-- `gmatch` for `L["…"]` over the sources, checked against the manifest. Four
-- repositories in this collection had one, and it is `testing-§12`'s failure
-- mode written out: everything such a scan can find is by construction already
-- wrapped, so the one thing it exists to catch is the one thing it cannot see.
-- KickCD never had that case either, which is how three cast-bar `desc` keys
-- could be reworded at the call site and left undefined in `locales/enUS.lua`
-- with 847 cases green (M4-21, KICKCD-R-03).
--
-- What is here instead reads the TOC-derived source list for string LITERALS
-- and asks two questions of them, in opposite directions:
--
--   * every literal that IS an `L[…]` subscript must be defined in
--     locales/enUS.lua — the direction KICKCD-R-03 is about;
--   * every literal in `settings/` that is NOT an `L[…]` subscript and reads as
--     prose must be recorded, with a class, in the residue register below — the
--     direction no scan built out of `L["…"]` can ever look in.
--
-- WHAT THE SECOND HALF COVERS, SAID PLAINLY, BECAUSE A GATE THAT OVERCLAIMS IS
-- WORSE THAN NONE. The residue scan reads `settings/` and nothing else. That is
-- the surface the M4-21 acceptance criterion names ("a bare literal added to a
-- settings file"), and it is the panel surface docs/common-tasks.md § "Add a
-- locale string" makes its rule about. It is NOT the whole addon. `/kcd`
-- command output (`core/KickCD.lua`, about a hundred prose literals) and the
-- debug-console diagnostics in `modules/Castbar_Debug.lua` and
-- `modules/Cooldowns.lua` are still bare English, are not scanned, and are a
-- known gap this gate does not close and does not pretend to: the command
-- surface is one decision about one help listing, and it is not this one.
--
-- The key-coverage half has no such fence — it reads every file the TOC loads
-- outside `libs/`, because a key used anywhere and defined nowhere is the same
-- defect wherever it sits.

local ROOT = T.root

local function readSource(rel)
    local fh = io.open(ROOT .. "/" .. rel, "r")
    assertTrue(fh ~= nil, "the TOC names a file that cannot be read: " .. rel)
    local body = fh:read("*a")
    fh:close()
    return body
end

-- The scanned surface, DERIVED from the TOC by a rule rather than typed as a
-- list. A hand-maintained list goes stale in the direction that matters: a new
-- settings file is simply never read, and the gate then reports green over a
-- surface it never looked at. Because this is a rule, a `settings/` file added
-- to the TOC tomorrow is in scope the moment it loads.
local OWN_FILES, SETTINGS_FILES = {}, {}
for _, rel in ipairs(T.tocFiles) do
    local norm = rel:gsub("\\", "/")
    if not norm:match("^libs/") then
        OWN_FILES[#OWN_FILES + 1] = norm
        if norm:match("^settings/") then SETTINGS_FILES[#SETTINGS_FILES + 1] = norm end
    end
end

-- Lua's own lexer, reduced to the two questions asked here: where does each
-- string literal start, and is it inside an `L[…]` subscript.
--
-- A `gmatch` for `"…"` cannot be used instead. This repository's comments are
-- prose and quote strings freely — `settings/Panel.lua`'s header alone quotes
-- half a dozen — so `body:gmatch('"(.-)"')` reports a paragraph ABOUT a string
-- as a string, and a gate that invents an offender is a gate people switch off.
--
-- It comes apart into three helpers and a dispatch. Two answer "where does this
-- lexeme end" — `longBracket` and `endOfQuoted` — one answers "am I inside an
-- `L[…]`" — `trackSubscript` — and `scanLiterals` asks them in the one order
-- that is correct, and records what falls out.
--
-- Long brackets are handled rather than skipped: `settings/Spells.lua:50-51`
-- holds two `[[Interface\…]]` texture paths, and a lexer that walked past `[[`
-- without knowing what it was would read the `'` in a later `spec's` as the
-- start of a string and lose the rest of the file.
local function longBracket(src, i)
    local eq = src:match("^%[(=*)%[", i)
    if not eq then return nil end
    local close = "]" .. eq .. "]"
    local from = i + #eq + 2
    local at = src:find(close, from, true)
    return from, (at or #src + 1) - 1, (at and at + #close or #src + 1)
end

-- The short-quote sibling of `longBracket`. Given the opening quote at `i`,
-- where does the literal stop? At its own closing quote, or at the newline a
-- broken literal never gets past — an unterminated `'` that ran on would eat
-- the rest of the file the same way an unread `[[` does. A backslash takes the
-- character behind it with it, so `"he said \"no\""` is one literal, not three.
local function endOfQuoted(src, i, n)
    local q, j = src:sub(i, i), i + 1
    while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == q or d == "\n" then break
        else j = j + 1 end
    end
    return j
end

-- Is the character at `i` inside an `L[…]` subscript? Answers by returning
-- where to carry on from and the depth to carry with it.
--
-- Depth is what `wrapped` is read off, rather than the characters in front of
-- the quote, because a key may be built by concatenation across lines and a
-- check on the preceding few characters calls the second fragment of such a key
-- unrouted. The `L` has to be a whole word, so `SPELL_KNOWN_LABEL[field]` is
-- not a locale lookup, and `NS.L["…"]` is (settings/Panel_Widgets.lua uses
-- exactly that spelling, with no `L` upvalue in the file).
local function trackSubscript(src, i, depth)
    local c = src:sub(i, i)
    if depth > 0 then
        if c == "[" then return i + 1, depth + 1 end
        if c == "]" then return i + 1, depth - 1 end
        return i + 1, depth
    end
    if c == "L" and src:sub(i - 1, i - 1):match("[%w_]") == nil then
        local open = src:match("^L%s*()%[", i)
        if open then return open + 1, 1 end
    end
    return i + 1, depth
end

-- The dispatch, and the order is the whole contract: a newline first so the
-- line counter is never wrong, then a comment — which may itself be a long
-- bracket — then the two literal forms, and only what none of those claimed
-- reaches the subscript tracker. That ordering is why a `"` inside an `L[…]` is
-- still recorded as a literal, carrying `wrapped`, and why a `[[…]]` inside one
-- is read as a string rather than as two more levels of depth.
local function scanLiterals(src)
    local out, i, n, line, depth = {}, 1, #src, 1, 0
    local function advance(from, to)
        for _ in src:sub(from, to):gmatch("\n") do line = line + 1 end
    end
    while i <= n do
        local c = src:sub(i, i)
        if c == "\n" then
            line, i = line + 1, i + 1
        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            local _, _, after = longBracket(src, i + 2)
            if after then
                advance(i, after - 1)
                i = after
            else
                i = src:find("\n", i, true) or (n + 1)
            end
        elseif c == "[" and longBracket(src, i) then
            local from, to, after = longBracket(src, i)
            local at = line
            advance(i, after - 1)
            out[#out + 1] = { text = src:sub(from, to), line = at, wrapped = depth > 0 }
            i = after
        elseif c == '"' or c == "'" then
            local j = endOfQuoted(src, i, n)
            out[#out + 1] = { text = src:sub(i + 1, j - 1), line = line, wrapped = depth > 0 }
            i = j + 1
        else
            i, depth = trackSubscript(src, i, depth)
        end
    end
    return out
end

-- Prose, as distinct from an identifier, a path, a pattern or an event token:
-- at least one three-letter run, and two alphabetic words with a space between
-- them. A leading `/` exempts a slash-command SYNTAX literal, which a player
-- types verbatim in every language.
--
-- The floor is honest about what it cannot see. A one-word label — "Reset",
-- "Icon", "OUTLINE" — reads exactly like a table key or a flag to any
-- mechanical test, so this gate does not claim to catch one and the register
-- does not pretend to list them. It catches the SENTENCES, which is where an
-- unrouted string actually costs a translator something.
local function isProse(s)
    if s:match("^%s*/") then return false end
    return s:find("%a%a%a") ~= nil and s:find("%a+%s+%a+") ~= nil
end

-- ---------------------------------------------------------------------------
-- The residue register
-- ---------------------------------------------------------------------------
--
-- Every prose literal in `settings/` that does NOT go through L, with the class
-- that says why. This is a register, not a mute button: the staleness case
-- below fails when an entry stops matching the tree, so a line that gets
-- wrapped, reworded or deleted takes its entry with it.
--
-- The classes, each argued once here rather than forty-one times:
--
--   DIAGNOSTIC        Reaches chat or the debug console only when the addon is
--                     already wrong — a malformed schema row, a raise out of a
--                     pcall, a rebuild the player never asked to see. The
--                     audience is whoever reads the bug report, and
--                     docs/debug.md owns the wording.
--   VALIDATOR         The `reason` half of a `nil, reason` pair that a caller
--                     pastes into a sentence assembled somewhere else. Keying
--                     the clause alone keys half a sentence and pins the English
--                     word order of the other half.
--   DEGRADED STEM     core/CoreSetup.lua builds ONE degraded-install sentence
--                     (NS.LIBKA0S_MISSING) that each seam appends its own
--                     consequence to, so a tampered install says the same thing
--                     about WHY and a different thing about WHAT. Keying a tail
--                     alone keys half a sentence; keying the stem at each site
--                     ends the sharing that is the point of it.
--   DEGRADED FALLBACK The `or` arm behind an L lookup, for the load path where
--                     locales/enUS.lua has not run. Routing it through L is
--                     circular: it exists precisely because L is not there.
--   SPLIT COLOR       The sentence's spans carry different colors mid-line
--                     because slash-dispatch.md fixes them. One key per sentence
--                     would carry `|c…|r` inside translatable text and would
--                     depend on the color stack restoring the outer span, a
--                     rendering question no headless case can settle. One key
--                     per span pins English word order and leaves a translator
--                     nothing to reorder.
--   FRAGMENT          A word or clause concatenated into a sentence built at the
--                     call site. Keying it alone keys an English word into an
--                     English sentence's grammar.
--   LIB DESCRIPTOR    A field crossing to LibKa0s. A library descriptor is never
--                     handed NS.L — the vendored majors resolve a key-returning
--                     table into itself, which is what the four "no LibKa0s
--                     descriptor is handed the key-returning locale table" cases
--                     above pin. A translator restores these by handing the
--                     descriptor a PLAIN table of just these keys.
--   MEDIA KEY         A LibSharedMedia registry key, not text. It is compared
--                     against what LSM:Fetch was registered under; translating
--                     it would fetch nothing and the row would render blank.
--                     It reaches the player only because LSM's own dropdown
--                     shows registry keys, which is LSM's decision, not ours.
--   FORMAT SUFFIX     A unit written into a `fmt` field the slider renders after
--                     the number. Its siblings — "%d px", "%d%%" — sit below the
--                     prose floor and are invisible to this scan, so routing
--                     this one alone would put one unit in a locale file and
--                     leave the rest in the source.
--   CLIENT SUPPLIED   English that exists only as a fallback for a string the
--                     CLIENT normally supplies. Routing it would move the
--                     English into a locale file without making the client's own
--                     translation reachable, which is the fix these actually
--                     want.
--   NOT YET ROUTED    A plain user-facing sentence in a settings page that would
--                     route cleanly and simply has not been. M4-21 scoped this
--                     repository's routing to KICKCD-R-03's three desc keys;
--                     these five are the rest of the settings surface's chat and
--                     label text. They are listed by name so the size of the gap
--                     is a number someone can act on rather than an impression,
--                     and so that routing one is a two-line change this file
--                     notices.
local RESIDUE = {
    -- settings/Slash.lua — the schema-gate hints and the degraded dispatcher.
    {"settings/Slash.lua", " (depends on %s = %s)", "NOT YET ROUTED"},
    {"settings/Slash.lua", "flip %s to %s for %s", "NOT YET ROUTED"},
    {"settings/Slash.lua", "`/kcd reset spells` has moved to |cFFFFFF00/kcd spells resetall|r ", "SPLIT COLOR"},
    {"settings/Slash.lua", "\\226\\128\\148 it rebuilds every spec's list.", "SPLIT COLOR"},
    {"settings/Slash.lua", "`/kcd reset %s` is gone \\226\\128\\148 `reset` now takes a setting path. ", "SPLIT COLOR"},
    {"settings/Slash.lua", "Use the ", "SPLIT COLOR"},
    {"settings/Slash.lua", " panel's |cFFFFFF00Defaults|r button to reset the ", "SPLIT COLOR"},
    {"settings/Slash.lua", "whole page, or |cFFFFFF00/kcd reset <path>|r for one setting (try /kcd list).", "SPLIT COLOR"},
    {"settings/Slash.lua", " is unavailable. ", "DEGRADED STEM"},
    {"settings/Slash.lua", "the LibKa0s library is missing", "VALIDATOR"},
    {"settings/Slash.lua", " slash commands", "FRAGMENT"},
    {"settings/Slash.lua", "unknown command '", "FRAGMENT"},

    -- settings/OptionsSetup.lua
    {"settings/OptionsSetup.lua", "Ka0s KickCD", "LIB DESCRIPTOR"},
    {"settings/OptionsSetup.lua", ", so the settings panel is unavailable.", "DEGRADED STEM"},

    -- settings/Panel.lua — ValidateSchema and the onChange guard.
    {"settings/Panel.lua", "|cffff0000schema error|r: ", "DIAGNOSTIC"},
    {"settings/Panel.lua", " |cffff0000schema error|r: ", "DIAGNOSTIC"},
    {"settings/Panel.lua", "<no path>", "DIAGNOSTIC"},
    {"settings/Panel.lua", "row is not a table", "DIAGNOSTIC"},
    {"settings/Panel.lua", "missing or empty `path`", "DIAGNOSTIC"},
    {"settings/Panel.lua", " (expected one of: general, icons, castbar, label, spells, profiles)", "DIAGNOSTIC"},
    {"settings/Panel.lua", " (expected one of: general, icons, castbar, label, spells, debug, units)", "DIAGNOSTIC"},
    {"settings/Panel.lua", " (expected one of: bool, number, string, color)", "DIAGNOSTIC"},
    {"settings/Panel.lua", "onChange for ", "DIAGNOSTIC"},

    -- settings/Panel_Widgets.lua
    {"settings/Panel_Widgets.lua", "link failed: ", "DIAGNOSTIC"},
    {"settings/Panel_Widgets.lua", "cannot open settings during combat", "DEGRADED FALLBACK"},

    -- settings/Panel_Render.lua
    {"settings/Panel_Render.lua", "onChange for ", "DIAGNOSTIC"},

    -- settings/Icons.lua, settings/Castbar.lua, settings/Label.lua — the
    -- composed blocks' LSM defaults.
    {"settings/Icons.lua", "Blizzard Tooltip", "MEDIA KEY"},
    {"settings/Icons.lua", "Friz Quadrata TT", "MEDIA KEY"},
    {"settings/Castbar.lua", "Friz Quadrata TT", "MEDIA KEY"},
    {"settings/Castbar.lua", "Blizzard Raid Bar", "MEDIA KEY"},
    {"settings/Castbar.lua", "Blizzard Tooltip", "MEDIA KEY"},
    {"settings/Label.lua", "Friz Quadrata TT", "MEDIA KEY"},
    {"settings/Label.lua", "%d deg", "FORMAT SUFFIX"},

    -- settings/Spells.lua
    {"settings/Spells.lua", "Editing %s/%s \226\137\160 player %s/%s; skipping cooldown-manager gate.", "DIAGNOSTIC"},
    {"settings/Spells.lua", "C_CooldownViewer unavailable; skipping cooldown-manager validation for spell ", "DIAGNOSTIC"},
    {"settings/Spells.lua", "reset %s/%s: %d spells", "DIAGNOSTIC"},
    {"settings/Spells.lua", "Spell %s (#%d) is not tracked by the Blizzard Cooldown Manager for this specialization.", "NOT YET ROUTED"},
    {"settings/Spells.lua", "AceGUI not loaded", "NOT YET ROUTED"},
    {"settings/Spells.lua", "No spells tracked. Click ", "NOT YET ROUTED"},
    -- classDisplayName consults these BEFORE LOCALIZED_CLASS_NAMES_MALE, so on a
    -- French client these two classes read English while the other eleven do not.
    -- Routing them would put that inconsistency in a locale file instead of
    -- ending it; the fix is to consult the client first and keep these as the
    -- no-global fallback, which is a behavior change M4-21 does not scope.
    {"settings/Spells.lua", "Death Knight", "CLIENT SUPPLIED"},
    {"settings/Spells.lua", "Demon Hunter", "CLIENT SUPPLIED"},
}

local CLASSES = {
    ["DIAGNOSTIC"]        = true, ["VALIDATOR"]      = true,
    ["DEGRADED STEM"]     = true, ["DEGRADED FALLBACK"] = true,
    ["SPLIT COLOR"]       = true, ["FRAGMENT"]       = true,
    ["LIB DESCRIPTOR"]    = true, ["MEDIA KEY"]      = true,
    ["FORMAT SUFFIX"]     = true, ["CLIENT SUPPLIED"] = true,
    ["NOT YET ROUTED"]    = true,
}

-- ---------------------------------------------------------------------------
-- The scan
-- ---------------------------------------------------------------------------

-- Every `L[…]` subscript locales/enUS.lua DEFINES. Read out of the source
-- rather than out of the loaded `NS.L`, because the loaded table answers every
-- key by construction: `locales/enUS.lua:15`'s `__index` returns the key, so
-- `NS.L[anything]` is truthy and a case built on it asserts nothing.
local DEFINED = {}
for _, lit in ipairs(scanLiterals(readSource("locales/enUS.lua"))) do
    if lit.wrapped then DEFINED[lit.text] = true end
end

-- Every `L[…]` subscript the rest of the addon USES, and every bare prose
-- literal in `settings/`.
local usedKeys, unrouted = {}, {}
local scannedLiterals, routedCount, unroutedCount = 0, 0, 0
for _, rel in ipairs(OWN_FILES) do
    local inSettings = rel:match("^settings/") ~= nil
    for _, lit in ipairs(scanLiterals(readSource(rel))) do
        scannedLiterals = scannedLiterals + 1
        if lit.wrapped then
            routedCount = routedCount + 1
            if not rel:match("^locales/") and not usedKeys[lit.text] then
                usedKeys[lit.text] = rel .. ":" .. lit.line
            end
        elseif inSettings and isProse(lit.text) then
            unrouted[rel] = unrouted[rel] or {}
            if not unrouted[rel][lit.text] then
                unrouted[rel][lit.text] = lit.line
                unroutedCount = unroutedCount + 1
            end
        end
    end
end

local recorded = {}
for _, entry in ipairs(RESIDUE) do
    recorded[entry[1]] = recorded[entry[1]] or {}
    recorded[entry[1]][entry[2]] = entry[3]
end

test("the locale scan actually reads the surface it is meant to guard", function()
    -- The guard on the guard. A lexer that silently matched nothing would make
    -- every case below pass over a tree full of bare English, which is the exact
    -- failure this half of the file was written to end.
    assertTrue(#OWN_FILES >= 30,
        "the TOC put " .. #OWN_FILES .. " of the addon's own files in scope")
    assertTrue(#SETTINGS_FILES >= 10,
        "of which " .. #SETTINGS_FILES .. " are settings pages")
    assertTrue(scannedLiterals > 2000,
        "the scan read " .. scannedLiterals .. " string literals across them")
    assertTrue(routedCount > 300,
        "and found " .. routedCount .. " of them subscripted under L")
    assertTrue(unroutedCount > 0,
        "and still reports the known residue rather than an empty set")
end)

test("every L[...] key the addon subscripts is defined in locales/enUS.lua", function()
    -- KICKCD-R-03's acceptance criterion, and the case that had to be seen red
    -- first: it named the three reworded cast-bar descs before they were added.
    local missing = {}
    for key, where in pairs(usedKeys) do
        if not DEFINED[key] then
            missing[#missing + 1] = where .. ": " .. string.format("%q", key)
        end
    end
    table.sort(missing)
    assertTrue(#missing == 0,
        "L[...] key used but never defined in locales/enUS.lua (a translator sees "
        .. "the raw key; enUS only renders because the __index returns it) at: "
        .. table.concat(missing, "; "))
end)

test("every user-facing literal in the settings surface is routed or recorded", function()
    -- THE ACCEPTANCE CASE. A bare prose literal added to a settings file is red
    -- here, named by file, line and text, until it is either wrapped in L or
    -- given a class in the register above.
    local offenders = {}
    for rel, texts in pairs(unrouted) do
        for text, line in pairs(texts) do
            if not (recorded[rel] and recorded[rel][text]) then
                offenders[#offenders + 1] =
                    rel .. ":" .. line .. ": " .. string.format("%q", text)
            end
        end
    end
    table.sort(offenders)
    assertTrue(#offenders == 0,
        "user-facing text in a settings file that neither goes through L nor is "
        .. "recorded as residue in tests/test_locale.lua: " .. table.concat(offenders, "; "))
end)

test("every recorded residue literal is still unrouted in the file that names it", function()
    -- The direction that keeps the register from decaying into a mute button: an
    -- entry whose literal was wrapped, reworded or deleted goes red here rather
    -- than living on as a license for a string that no longer exists.
    local stale = {}
    for _, entry in ipairs(RESIDUE) do
        local rel, text = entry[1], entry[2]
        if not (unrouted[rel] and unrouted[rel][text]) then
            stale[#stale + 1] = rel .. ": " .. string.format("%q", text)
        end
    end
    assertTrue(#stale == 0,
        "residue entry whose literal is no longer there to excuse — drop it: "
        .. table.concat(stale, "; "))
end)

test("every residue entry carries one of the declared classes", function()
    -- A free-text reason decays into a shrug. The class is the argument, each is
    -- written out once above, and a new entry has to pick one of them or say why
    -- a twelfth class exists.
    local bad = {}
    for _, entry in ipairs(RESIDUE) do
        if not CLASSES[entry[3]] then
            bad[#bad + 1] = entry[1] .. ": " .. string.format("%q", entry[2])
                .. " filed under " .. tostring(entry[3])
        end
    end
    assertTrue(#bad == 0, "residue entry with an undeclared class: " .. table.concat(bad, "; "))
end)

test("the three reworded cast-bar descs are keyed as the panel renders them", function()
    -- KICKCD-R-03 by name. The generic case above would go green again if the
    -- three sentences were deleted from both sides at once; these three are the
    -- ones the finding is about, so they are pinned rather than merely counted.
    local descs = {
        "Cast bar width in pixels. Overridden by Auto-size to icon grid while the bar is horizontal.",
        "Cast bar height in pixels. Overridden by Auto-size to icon grid while the bar is vertical.",
        "Spell icon size in pixels (0 hides the icon). Capped at the bar's short axis so the icon never overflows it.",
    }
    for _, sentence in ipairs(descs) do
        assertTrue(usedKeys[sentence] ~= nil,
            "settings/Castbar.lua no longer renders " .. string.format("%q", sentence))
        assertTrue(DEFINED[sentence] ~= nil,
            "locales/enUS.lua does not define " .. string.format("%q", sentence))
    end
    -- And the superseded short forms are gone, not merely joined by the long
    -- ones: a manifest that carries both leaves a translator two sentences to
    -- translate and no way to tell which one the panel shows.
    for _, gone in ipairs({
        "Cast bar width in pixels.",
        "Cast bar height in pixels.",
        "Spell icon size in pixels (0 hides the icon).",
    }) do
        assertTrue(DEFINED[gone] == nil,
            "locales/enUS.lua still defines the superseded " .. string.format("%q", gone))
    end
end)
