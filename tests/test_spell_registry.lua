-- tests/test_spell_registry.lua — the spell-list registry and its one writer
--
-- architecture-§5: every membership change of a structural registry goes through
-- ONE registry writer, and panel code and slash handlers call it rather than
-- appending to, splicing or removing from the stored collection themselves. For
-- the spell lists (`db.profile.spells[CLASS][specID]`) that writer is
-- core/Database.lua (#16).
--
-- The first block is CHARACTERIZATION, written and run green against the code
-- as it stood before the writes moved: each panel and slash path, pinned by
-- what it leaves in the list, so the move is provably behavior-preserving.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil

local SHAMAN_CLASS_ID = 7
local ELEMENTAL, ENHANCEMENT = 262, 263
local BLOOD = 250

--- A fully-enabled instance playing an Elemental Shaman, every settings panel
--- shown (RefreshRows is gated on the Spells panel being shown), the editor
--- seeded to the player's own spec. `race` overrides the mock's Orc, which has
--- no racial cast-stopper.
local function instance(race)
    local inst = T.load(true, true, function(mocks)
        mocks.UnitClass = function() return "Shaman", "SHAMAN", SHAMAN_CLASS_ID end
        mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 1)
        if race then mocks.UnitRace = function() return race, race end end
    end)
    for _, ctx in ipairs(inst.NS.Settings.Helpers.__panels()) do ctx.panel:Show() end
    local p = inst.NS.Settings.SpellsPanel
    p:SeedSelectionToPlayer()
    return inst, p
end

--- Run a `/kcd` line and hand back the chat lines it printed.
local function slash(inst, line)
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    local ok, err = pcall(inst.NS.OnSlashCommand, inst.NS, line)
    frame.AddMessage = orig
    if not ok then error(err, 0) end
    return table.concat(lines, "\n")
end

local function list(inst, class, spec)
    return inst.NS.Database:GetSpellList(class, spec)
end

local function indexOf(l, id)
    for i, e in ipairs(l or {}) do if e.spellID == id then return i end end
end

--- The defaults for one spec, in the profile's record shape.
local function defaultsFor(NS, class, spec)
    local out = {}
    for _, e in ipairs(NS.DefaultSpells[class][spec]) do
        out[#out + 1] = {
            spellID  = e.spellID or e[1],
            category = e.category or e[2] or "other",
            enabled  = e.enabled ~= false,
        }
    end
    return out
end

local function assertListIs(l, want, label)
    assertTrue(l ~= nil, label .. ": no list")
    assertEqual(#l, #want, label .. ": length")
    for i, w in ipairs(want) do
        assertEqual(l[i].spellID, w.spellID, label .. ": #" .. i .. " spellID")
        assertEqual(l[i].category, w.category, label .. ": #" .. i .. " category")
        assertEqual(l[i].enabled, w.enabled, label .. ": #" .. i .. " enabled")
    end
end

--- Fire the Spells page's Defaults popup exactly as its Yes button does.
local function panelReset(inst)
    inst.mocks.StaticPopupDialogs["KICKCD_RESET_SPELLS"].OnAccept()
end

--- Rebuild the Spells page and hand back the `onMove` it gave the reorder
--- controller -- the callback a finished drag calls.
local function panelOnMove(inst, p)
    local W = inst.mocks.LibStub("LibKa0s-Widgets-1.0", true)
    local real = W.ReorderList
    local onMove
    W.ReorderList = function(opts) onMove = opts.onMove; return real(opts) end
    local ok, err = pcall(p.RefreshRows, p)
    W.ReorderList = real
    if not ok then error(err, 0) end
    return onMove
end

local function mangle(l)
    for i = #l, 2, -1 do table.remove(l, i) end
    l[1].enabled = false
    l[#l + 1] = { spellID = 12345, category = "other", enabled = true }
end

-- ── characterization: the slash surface ─────────────────────────────────────

test("`/kcd spells add` appends { id, other, enabled } and re-adding re-enables in place", function()
    local inst = instance()
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local before = #l
    local out = slash(inst, "spells add 12345 SHAMAN ELEMENTAL")
    assertEqual(#l, before + 1, "the spell must be appended")
    assertEqual(l[#l].spellID, 12345)
    assertEqual(l[#l].category, "other")
    assertEqual(l[#l].enabled, true)
    assertTrue(out:find("added", 1, true) ~= nil, "the add must say so: " .. out)

    l[#l].enabled = false
    out = slash(inst, "spells add 12345 SHAMAN ELEMENTAL")
    assertEqual(#l, before + 1, "an existing spell is never appended twice")
    assertEqual(l[#l].enabled, true, "it must be re-enabled in place")
    assertTrue(out:find("re-enabled", 1, true) ~= nil, "the re-enable must say so: " .. out)
end)

test("`/kcd spells add` lazy-creates the list of a spec that has none", function()
    local inst = instance()
    inst.NS.db.profile.spells.SHAMAN[ENHANCEMENT] = nil
    slash(inst, "spells add 12345 SHAMAN ENHANCEMENT")
    local l = list(inst, "SHAMAN", ENHANCEMENT)
    assertTrue(l ~= nil, "the list must have been created")
    assertEqual(#l, 1)
    assertEqual(l[1].spellID, 12345)
end)

test("`/kcd spells remove` deletes exactly that spell, and a missing one writes nothing", function()
    local inst = instance()
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local before, victim, keep = #l, l[2].spellID, l[1].spellID
    slash(inst, "spells remove " .. victim .. " SHAMAN ELEMENTAL")
    assertEqual(#l, before - 1)
    assertNil(indexOf(l, victim), "the removed spell must be gone")
    assertEqual(l[1].spellID, keep, "nothing else moves")

    local out = slash(inst, "spells remove 999999 SHAMAN ELEMENTAL")
    assertEqual(#l, before - 1, "a spell not in the list removes nothing")
    assertTrue(out:find("not in", 1, true) ~= nil, "and says so: " .. out)
end)

test("`/kcd spells enable|disable` stores a real boolean on the entry", function()
    local inst = instance()
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local id = l[1].spellID
    slash(inst, "spells disable " .. id .. " SHAMAN ELEMENTAL")
    assertEqual(l[1].enabled, false)
    slash(inst, "spells enable " .. id .. " SHAMAN ELEMENTAL")
    assertEqual(l[1].enabled, true)
end)

test("`/kcd spells category` writes the entry's category, and refuses an unknown one", function()
    local inst = instance()
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local id = l[1].spellID
    slash(inst, "spells category " .. id .. " silence SHAMAN ELEMENTAL")
    assertEqual(l[1].category, "silence")
    slash(inst, "spells category " .. id .. " nosuch SHAMAN ELEMENTAL")
    assertEqual(l[1].category, "silence", "an unknown category writes nothing")
end)

test("`/kcd spells reset` rebuilds ONE spec from the defaults and leaves the others alone", function()
    local inst = instance()
    local NS = inst.NS
    mangle(list(inst, "DEATHKNIGHT", BLOOD))
    local other = list(inst, "SHAMAN", ELEMENTAL)
    local otherLen = #other
    other[#other + 1] = { spellID = 12345, category = "other", enabled = true }

    slash(inst, "spells reset DEATHKNIGHT BLOOD")
    assertListIs(list(inst, "DEATHKNIGHT", BLOOD), defaultsFor(NS, "DEATHKNIGHT", BLOOD), "reset spec")
    assertEqual(#list(inst, "SHAMAN", ELEMENTAL), otherLen + 1, "another spec is untouched")
end)

-- ── characterization: the Spells page ───────────────────────────────────────

test("the Spells page's Defaults popup rebuilds the selected spec from the defaults", function()
    local inst = instance()
    mangle(list(inst, "SHAMAN", ELEMENTAL))
    panelReset(inst)
    assertListIs(list(inst, "SHAMAN", ELEMENTAL), defaultsFor(inst.NS, "SHAMAN", ELEMENTAL), "popup reset")
end)

test("the Defaults popup rebuilds a class the profile holds no table for", function()
    -- The popup used to reach the list through its own profile accessor rather
    -- than Database:EnsureSpellList; either way a class with no table at all
    -- must come back with the defaults.
    local inst = instance()
    inst.NS.db.profile.spells.SHAMAN = nil
    panelReset(inst)
    assertListIs(list(inst, "SHAMAN", ELEMENTAL), defaultsFor(inst.NS, "SHAMAN", ELEMENTAL), "popup reset")
end)

test("the page's Defaults popup and `/kcd spells reset` leave the same list", function()
    local a = instance()
    mangle(list(a, "SHAMAN", ELEMENTAL))
    panelReset(a)
    local b = instance()
    mangle(list(b, "SHAMAN", ELEMENTAL))
    slash(b, "spells reset SHAMAN ELEMENTAL")
    local la, lb = list(a, "SHAMAN", ELEMENTAL), list(b, "SHAMAN", ELEMENTAL)
    assertListIs(la, lb, "panel vs slash")
end)

test("a finished drag on the Spells page splices the dragged row to its drop index", function()
    local inst, p = instance()
    local l = list(inst, "SHAMAN", ELEMENTAL)
    assertTrue(#l >= 4, "the fixture needs at least four rows")
    local a, b, c, d = l[1].spellID, l[2].spellID, l[3].spellID, l[4].spellID
    local onMove = panelOnMove(inst, p)
    assertTrue(onMove ~= nil, "the page must hand the reorder controller an onMove")
    onMove(1, 4)
    assertEqual(l[1].spellID, b)
    assertEqual(l[2].spellID, c)
    assertEqual(l[3].spellID, d)
    assertEqual(l[4].spellID, a, "the dragged row landed at 4")
end)

-- ── the per-spec reset keeps the racial (#16) ───────────────────────────────
--
-- Both per-spec resets used to rebuild from NS.DefaultSpells alone, so a player
-- who reset their OWN class's spec lost the racial cast-stopper the load pass
-- and `/kcd spells resetall` both append. They share the seed routine now.

test("a per-spec reset of the player's own class keeps the racial, on both surfaces", function()
    local WAR_STOMP = 20549
    local inst = instance("Tauren")
    local l = list(inst, "SHAMAN", ELEMENTAL)
    assertTrue(indexOf(l, WAR_STOMP) ~= nil, "sanity: the load pass appended the racial")

    mangle(l)
    panelReset(inst)
    l = list(inst, "SHAMAN", ELEMENTAL)
    assertEqual(indexOf(l, WAR_STOMP), #l, "the popup reset must re-append the racial, last")
    assertEqual(l[#l].category, "racial")

    mangle(l)
    slash(inst, "spells reset SHAMAN ELEMENTAL")
    l = list(inst, "SHAMAN", ELEMENTAL)
    assertEqual(indexOf(l, WAR_STOMP), #l, "`/kcd spells reset` must re-append the racial, last")

    slash(inst, "spells reset DEATHKNIGHT BLOOD")
    assertNil(indexOf(list(inst, "DEATHKNIGHT", BLOOD), WAR_STOMP),
        "another class's reset never gains the player's racial")
end)

-- ── one writer ──────────────────────────────────────────────────────────────

--- The file's code with every `--` comment stripped, so prose naming a write
--- cannot trip the scan.
local function code(rel)
    local fh = assert(io.open(T.root .. "/" .. rel, "r"))
    local out = {}
    for line in fh:lines() do out[#out + 1] = (line:gsub("%-%-.*$", "")) end
    fh:close()
    return table.concat(out, "\n")
end

test("neither the Spells page nor `/kcd spells` writes a stored spell list itself", function()
    -- red under: any append, splice, removal, entry-field write or lazy create
    -- in either caller -- architecture-§5's "they never append to, splice or
    -- table.remove the stored collection themselves".
    local forbidden = {
        { "table%.insert%s*%(",     "table.insert" },
        { "table%.remove%s*%(",     "table.remove" },
        -- `list` is what both callers named a stored list; a local array of
        -- another name (sortedKeys' `keys`) is not the registry.
        { "list%[#list%s*%+%s*1%]%s*=", "an append" },
        -- Any indexed write into a fetched list, which is the old per-spec
        -- slash reset's shape (`list[i] = nil` to wipe, then `list[i] = { … }`
        -- to refill); the append above is one case of it.
        { "list%[[^%]]+%]%s*=[^=]", "an indexed write into a list" },
        -- Replacing a whole list outright, which is the old Defaults popup's
        -- shape (`spells[selectedClass][selectedSpec] = Util.DeepCopy(source)`).
        { "spells%s*%[[^%]]*%]%s*%[[^%]]*%]%s*=[^=]", "a list replaced outright" },
        -- Rewriting an entry's identity, as that popup's normalizing loop did
        -- (`e.spellID = e.spellID or e[1]`).
        { "%.spellID%s*=[^=]",      "an entry's spellID" },
        { "%.enabled%s*=[^=]",      "an entry's enabled" },
        { "%.category%s*=[^=]",     "an entry's category" },
        { "EnsureSpellList",        "the lazy create" },
        { "profile%.spells%s*=",    "the store itself" },
    }
    for _, rel in ipairs({ "settings/Spells.lua", "core/KickCD.lua" }) do
        local src = code(rel)
        for _, f in ipairs(forbidden) do
            assertNil(src:match(f[1]), rel .. " writes " .. f[2] .. " itself; call NS.Database")
        end
    end
end)

-- ── the writer's verbs ──────────────────────────────────────────────────────

test("Database:AddSpell appends, re-enables in place, and lazy-creates", function()
    local inst = instance()
    local D = inst.NS.Database
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local n = #l
    assertEqual(D:AddSpell("SHAMAN", ELEMENTAL, 12345), "added")
    assertEqual(#l, n + 1)
    l[#l].enabled = false
    assertEqual(D:AddSpell("SHAMAN", ELEMENTAL, 12345), "enabled")
    assertEqual(#l, n + 1, "never a duplicate")
    assertEqual(l[#l].enabled, true)

    inst.NS.db.profile.spells.SHAMAN[ENHANCEMENT] = nil
    assertEqual(D:AddSpell("SHAMAN", ENHANCEMENT, 12345), "added")
    assertEqual(#list(inst, "SHAMAN", ENHANCEMENT), 1)
    assertNil(D:AddSpell(nil, ENHANCEMENT, 12345), "no class, no write")
end)

test("Database:RemoveSpell removes by spellID and reports whether it did", function()
    local inst = instance()
    local D = inst.NS.Database
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local n, victim = #l, l[2].spellID
    assertEqual(D:RemoveSpell("SHAMAN", ELEMENTAL, victim), true)
    assertEqual(#l, n - 1)
    assertNil(indexOf(l, victim))
    assertEqual(D:RemoveSpell("SHAMAN", ELEMENTAL, victim), false, "a second remove finds nothing")
    assertEqual(D:RemoveSpell("SHAMAN", ELEMENTAL, nil), false, "no id is not a crash")
    assertEqual(D:RemoveSpell("SHAMAN", 999, victim), false, "no list creates none")
    assertNil(list(inst, "SHAMAN", 999))
end)

test("Database:MoveSpell is a SPLICE to the index, not a swap", function()
    -- red under: `l[from], l[to] = l[to], l[from]`, which leaves the rows
    -- between the ends in the wrong order.
    local inst = instance()
    local D = inst.NS.Database
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local a, b, c, d = l[1].spellID, l[2].spellID, l[3].spellID, l[4].spellID
    assertEqual(D:MoveSpell("SHAMAN", ELEMENTAL, 1, 4), true)
    assertEqual(l[1].spellID, b)
    assertEqual(l[2].spellID, c)
    assertEqual(l[3].spellID, d)
    assertEqual(l[4].spellID, a)
    assertEqual(D:MoveSpell("SHAMAN", ELEMENTAL, 4, 1), true, "and backwards")
    assertEqual(l[1].spellID, a)
    assertEqual(l[2].spellID, b)
end)

test("Database:MoveSpell writes nothing for a move that goes nowhere or off the ends", function()
    -- A stale drop after a rebuild can name an index the list no longer has.
    local inst = instance()
    local D = inst.NS.Database
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local n, first = #l, l[1].spellID
    assertEqual(D:MoveSpell("SHAMAN", ELEMENTAL, 2, 2), false, "a move to its own index")
    assertEqual(D:MoveSpell("SHAMAN", ELEMENTAL, 0, 1), false, "below the list")
    assertEqual(D:MoveSpell("SHAMAN", ELEMENTAL, 1, n + 1), false, "past the list")
    assertEqual(D:MoveSpell("SHAMAN", 999, 1, 2), false, "no list")
    assertEqual(#l, n)
    assertEqual(l[1].spellID, first)
end)

test("Database:SetSpellEnabled and :SetSpellCategory write one entry's field", function()
    local inst = instance()
    local D = inst.NS.Database
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local id = l[1].spellID
    assertEqual(D:SetSpellEnabled("SHAMAN", ELEMENTAL, id, nil), true)
    assertEqual(l[1].enabled, false, "a nil stores a real false")
    assertEqual(D:SetSpellEnabled("SHAMAN", ELEMENTAL, id, true), true)
    assertEqual(l[1].enabled, true)
    assertEqual(D:SetSpellCategory("SHAMAN", ELEMENTAL, id, "root"), true)
    assertEqual(l[1].category, "root")
    assertEqual(D:SetSpellEnabled("SHAMAN", ELEMENTAL, 999999, false), false, "a missing spell")
    assertEqual(D:SetSpellCategory("SHAMAN", 999, id, "root"), false, "a missing list")
end)

-- ── the writer traces its own writes (debug-logging-§8, §10) ───────────────
--
-- A registry's create or delete is a functional flow, traced once by the
-- registry writer. The trace lives in Database, so the Spells page and
-- `/kcd spells` log the same line, and neither logs it a second time.

-- The writer's verbs, as the first word after the tag. The Spells page's
-- reorder controller logs under the same tag (`released …`, `painted …` on each
-- rebuild), and those are the library's lines about its own widgets, not writes.
local WRITE_VERBS = {
    add = true, remove = true, move = true, enable = true, disable = true,
    category = true, reset = true, ["resetall:"] = true,
}

--- Every [Spells] WRITE line in the console buffer.
local function spellsLines(NS)
    local out = {}
    for line in (NS.DebugLog:CopyText() .. "\n"):gmatch("([^\n]*)\n") do
        local verb = line:match("%[Spells%]%s+(%S+)")
        if verb and WRITE_VERBS[verb] then out[#out + 1] = line end
    end
    return out
end

--- Run `fn` with the debug flag set to `on` and a cleared console; hand back
--- the [Spells] lines it logged.
local function traced(inst, on, fn)
    local NS = inst.NS
    inst.mocks.__flushTimers()
    NS.State.debug = on
    NS.DebugLog:Clear()
    local ok, err = pcall(fn)
    local lines = spellsLines(NS)
    NS.State.debug = false
    if not ok then error(err, 0) end
    return lines
end

test("`/kcd spells remove` traces one [Spells] line with debug on, none with it off", function()
    local inst = instance()
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local a, b = l[1].spellID, l[2].spellID
    local on = traced(inst, true, function() slash(inst, "spells remove " .. a .. " SHAMAN ELEMENTAL") end)
    assertEqual(#on, 1, "one line: " .. table.concat(on, " | "))
    assertTrue(on[1]:find("remove " .. a, 1, true) ~= nil, "it names the spell: " .. on[1])
    local off = traced(inst, false, function() slash(inst, "spells remove " .. b .. " SHAMAN ELEMENTAL") end)
    assertEqual(#off, 0, "debug off logs nothing")
    assertNil(indexOf(l, b), "and the remove still happened")
end)

test("`/kcd spells reset` traces one [Spells] line with debug on, none with it off", function()
    local inst = instance()
    local on = traced(inst, true, function() slash(inst, "spells reset SHAMAN ELEMENTAL") end)
    assertEqual(#on, 1, "one line: " .. table.concat(on, " | "))
    assertTrue(on[1]:find("reset SHAMAN/", 1, true) ~= nil, "it names the list: " .. on[1])
    local off = traced(inst, false, function() slash(inst, "spells reset SHAMAN ELEMENTAL") end)
    assertEqual(#off, 0, "debug off logs nothing")
end)

test("`/kcd spells resetall` traces one [Spells] line for the bulk rewrite", function()
    local inst = instance()
    local on = traced(inst, true, function() slash(inst, "spells resetall") end)
    assertEqual(#on, 1, "one line: " .. table.concat(on, " | "))
    assertTrue(on[1]:find("resetall", 1, true) ~= nil, on[1])
end)

test("each Database spell-list verb traces one [Spells] line", function()
    local inst = instance()
    local D = inst.NS.Database
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local id = l[1].spellID
    for _, case in ipairs({
        { "add",      function() D:AddSpell("SHAMAN", ELEMENTAL, 12345) end },
        { "enable",   function() D:AddSpell("SHAMAN", ELEMENTAL, 12345) end },
        { "move",     function() D:MoveSpell("SHAMAN", ELEMENTAL, 1, 2) end },
        { "disable",  function() D:SetSpellEnabled("SHAMAN", ELEMENTAL, id, false) end },
        { "category", function() D:SetSpellCategory("SHAMAN", ELEMENTAL, id, "root") end },
        { "remove",   function() D:RemoveSpell("SHAMAN", ELEMENTAL, 12345) end },
        { "reset",    function() D:ResetSpellList("SHAMAN", ELEMENTAL) end },
    }) do
        local lines = traced(inst, true, case[2])
        assertEqual(#lines, 1, case[1] .. ": one line: " .. table.concat(lines, " | "))
        assertTrue(lines[1]:find(case[1], 1, true) ~= nil, case[1] .. ": " .. lines[1])
    end
end)

test("a verb that writes nothing traces nothing", function()
    local inst = instance()
    local D = inst.NS.Database
    local lines = traced(inst, true, function()
        D:RemoveSpell("SHAMAN", ELEMENTAL, 999999)
        D:MoveSpell("SHAMAN", ELEMENTAL, 2, 2)
        D:SetSpellEnabled("SHAMAN", ELEMENTAL, 999999, false)
    end)
    assertEqual(#lines, 0, "no write, no line: " .. table.concat(lines, " | "))
end)

test("the Spells page's actions trace once, from the writer, not again at the call site", function()
    -- red under: the page's own NS.Debug beside the writer's, which logs the
    -- remove, the toggle, the drag and the Defaults popup twice each.
    local inst, p = instance()
    local l = list(inst, "SHAMAN", ELEMENTAL)
    local popup = traced(inst, true, function() panelReset(inst) end)
    assertEqual(#popup, 1, "Defaults popup: " .. table.concat(popup, " | "))
    local onMove = panelOnMove(inst, p)
    local drag = traced(inst, true, function() onMove(1, 3) end)
    assertEqual(#drag, 1, "drag: " .. table.concat(drag, " | "))
    assertTrue(#l >= 3, "the fixture needs at least three rows")
end)

test("Database:ResetSpellList rebuilds IN PLACE, so a held reference stays valid", function()
    local inst = instance()
    local held = list(inst, "SHAMAN", ELEMENTAL)
    mangle(held)
    local back = inst.NS.Database:ResetSpellList("SHAMAN", ELEMENTAL)
    assertTrue(back == held, "the list table must be the same one")
    assertListIs(held, defaultsFor(inst.NS, "SHAMAN", ELEMENTAL), "in-place reset")
end)
