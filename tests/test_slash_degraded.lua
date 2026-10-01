-- tests/test_slash_degraded.lua
-- Split from tests/test_slash.lua (#30): the two halves of the CLI that answer
-- when it is NOT running normally -- the disabled state (slash-commands-§2) and
-- the library-absent degraded stub (slash-commands-§1, WS-02, LK-18). Every case
-- builds its own instance (T.load), so none depends on what test_slash.lua ran
-- before it. Case names and bodies are unchanged by the move.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil

local function joined(lines) return table.concat(lines, "\n") end

-- ── the disabled state (slash-commands-§2) ──────────────────────────────────
--
-- The rule: while `enabled` is false, a verb that DRIVES THE ADDON'S FEATURES
-- answers on ONE tagged line naming `/kcd enable` and DOES NOTHING ELSE. Every
-- case below asserts both halves, because a case that only reads the message
-- passes happily over a verb that printed the line and then acted anyway.
--
-- Each runs on its own instance: disabling is a stored write, and the shared
-- instance the rest of this suite uses would carry it into every later case.

--- A fresh instance with the addon turned OFF through its own verb, so the state
--- under test is the one a player reaches rather than a hand-written key.
local function disabled()
    local inst = T.load(true, true)
    local real = inst.NS.Util.print
    inst.NS.Util.print = function() end
    inst.NS:OnSlashCommand("disable")
    inst.NS.Util.print = real
    assertEqual(inst.NS.db.profile.enabled, false, "sanity: the addon is off")
    return inst
end

--- Everything NS.Util.print emits while `fn` runs, on `inst`.
local function say(inst, fn)
    local lines, real = {}, inst.NS.Util.print
    inst.NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    inst.NS.Util.print = real
    if not ok then error(err, 0) end
    return lines
end

-- The live set, slash-commands-§2's thirteen plus this addon's `spells` (the spell
-- lists are stored ARRAYS no schema row can address, so `/kcd spells` is their
-- only CLI route) and `profile` (a switch is a repair) — see core/KickCD.lua. Typed here rather than read off the
-- addon, so that the two lists have to be changed together: a verb added to the
-- addon's live set and not to this one goes red, while a NEW feature verb is
-- gated by default and passes without a word.
local LIVE = {
    "help", "config", "version", "enable", "disable", "debug", "diagnostics", "perf",
    "get", "set", "list", "reset", "resetall", "spells", "profile",
}

test("a disabled feature verb says so on ONE line, and does NOT act", function()
    -- The headline case, on the verb that would be loudest if it acted: `/kcd
    -- toggle` flips the lock, which is this addon's preview switch (the
    -- launcher menu's Locked entry, launcher-§2). A refusal that still flipped it would leave the player with a
    -- message saying nothing happened and a stored value saying it did.
    -- red under: the gate printing and then falling through to the handler
    local inst = disabled()
    local before = inst.NS.db.profile.locked
    local lines = say(inst, function() inst.NS:OnSlashCommand("toggle") end)
    assertEqual(#lines, 1, "one line, and one only: " .. table.concat(lines, " / "))
    assertTrue(lines[1]:find("/kcd enable", 1, true) ~= nil,
        "the line must name the verb that turns it back on: " .. lines[1])
    assertEqual(inst.NS.db.profile.locked, before, "and the lock must not have moved")
end)

test("every feature verb refuses, and NONE of them reaches the write seam", function()
    -- Driven off NS.COMMANDS rather than a typed list of feature verbs, so the
    -- next verb added to the addon is covered here the day it lands. "Did it
    -- act" is measured at the addon's single write seam and at the one act that
    -- does not go through it, rather than by re-reading each verb's own state.
    -- red under: a per-verb guard that one verb was added without
    local live = {}
    for _, v in ipairs(LIVE) do live[v] = true end
    for _, entry in ipairs(T.NS.COMMANDS) do
        local verb = entry[1]
        if not live[verb] then
            local inst = disabled()
            local H, S = inst.NS.Settings.Helpers, inst.NS.Settings.Store
            local writes, realSet = 0, S.Set
            local anchors, realAnchor = 0, H.ResetIconPosition
            S.Set = function(...) writes = writes + 1; return realSet(...) end
            H.ResetIconPosition = function(...) anchors = anchors + 1; return realAnchor(...) end
            local lines = say(inst, function() inst.NS:OnSlashCommand(verb) end)
            S.Set, H.ResetIconPosition = realSet, realAnchor
            assertEqual(#lines, 1, "`/kcd " .. verb .. "` must answer on exactly one line")
            assertTrue(lines[1]:find("/kcd enable", 1, true) ~= nil,
                "`/kcd " .. verb .. "` must name `/kcd enable`: " .. lines[1])
            assertEqual(writes, 0, "`/kcd " .. verb .. "` wrote while disabled")
            assertEqual(anchors, 0, "`/kcd " .. verb .. "` moved the grid while disabled")
        end
    end
end)

test("the live verbs still answer while disabled, and none of them refuses", function()
    -- The other half of the same rule, and the half that matters more: "refuse
    -- while disabled", read literally, takes the whole command surface down with
    -- it. A player must be able to read and repair settings, and reach the
    -- panel, while the addon is off — which is precisely when they need to.
    -- red under: gating by anything other than an explicit live set
    for _, verb in ipairs(LIVE) do
        local inst = disabled()
        local lines = say(inst, function() inst.NS:OnSlashCommand(verb) end)
        -- `help` is the one live verb that CARRIES the line, and carrying it is
        -- not refusing it: the index prints in full -- the player has to be able
        -- to SEE `enable` in the list -- with the line under the header as a
        -- statement about the rows below it, some of which are feature verbs that
        -- really are refused (LibKa0s-Slash-1.0 minor 12). So it is measured
        -- differently: the index must still be there.
        if verb == "help" then
            assertTrue(#lines > 5,
                "`/kcd help` must still print the whole index while disabled")
        else
            for _, line in ipairs(lines) do
                assertNil(line:find("is disabled", 1, true),
                    "`/kcd " .. verb .. "` must not refuse: " .. line)
            end
        end
    end
end)

test("`/kcd set` still writes while disabled — repair, not just read", function()
    -- The live set's whole reasoning. `set` is on it because a player whose
    -- settings are wrong turns the addon off first and fixes them second.
    -- red under: gating `set` as a feature verb because it changes something
    local inst = disabled()
    say(inst, function() inst.NS:OnSlashCommand("set locked true") end)
    assertEqual(inst.NS.Settings.Store.Get("locked"), true,
        "the write must have landed")
end)

test("`/kcd enable` above all — the switch is never one-way", function()
    -- red under: `enable` slipping off the live set
    local inst = disabled()
    say(inst, function() inst.NS:OnSlashCommand("enable") end)
    assertEqual(inst.NS.db.profile.enabled, true)
    -- and the feature verbs come straight back
    local before = inst.NS.db.profile.locked
    say(inst, function() inst.NS:OnSlashCommand("toggle") end)
    assertEqual(inst.NS.db.profile.locked, not before, "the lock moves again once enabled")
end)

test("nothing refuses while the addon is ENABLED", function()
    -- The gate reads the store at CALL time, so an addon that is on must behave
    -- exactly as it did before this landed.
    -- red under: a gate that latched at load, or read the wrong sense
    local inst = T.load(true, true)
    for _, entry in ipairs(T.NS.COMMANDS) do
        -- Re-armed before each verb, because `disable` is itself on the list and
        -- every verb after it would otherwise be measuring the disabled state.
        say(inst, function() inst.NS:OnSlashCommand("enable") end)
        local lines = say(inst, function() inst.NS:OnSlashCommand(entry[1]) end)
        for _, line in ipairs(lines) do
            assertNil(line:find("is disabled", 1, true),
                "`/kcd " .. entry[1] .. "` refused while enabled: " .. line)
        end
    end
end)

test("the refusal line is the LIBRARY's, and this addon does not re-spell it", function()
    -- THIS CASE REPLACES ITS OWN OPPOSITE, and the reversal is the point. It used
    -- to assert that the line came out of NS.L with a key defined in
    -- locales/enUS.lua. slash-commands-§7 settled it the other way: the wording is
    -- the COLLECTION's, one sentence, spelled once in
    -- LibKa0s-Slash-1.0's DISABLED_LINE_FORMAT, and it MUST NOT be re-spelled per
    -- addon -- a `L` override deliberately does not reach it. Eleven addons each
    -- wording it their own way is the drift the shared printer exists to end.
    -- red under: a host-side copy of the sentence, in a locale key or a literal
    assertNil(rawget(T.NS.L, "KickCD is disabled. %s turns it back on."),
        "the old host-side key must be GONE from locales/enUS.lua")

    -- And the line the addon actually emits is the one the library builds from
    -- that format, brand name and slash included -- not a lookalike.
    local inst = disabled()
    local Sl = inst.mocks.LibStub("LibKa0s-Slash-1.0", true)
    assertTrue(type(Sl.DISABLED_LINE_FORMAT) == "string",
        "the library owns the format string")
    local expected = Sl.DISABLED_LINE_FORMAT:format("Ka0s KickCD", "/kcd enable")
    local lines = say(inst, function() inst.NS:OnSlashCommand("toggle") end)
    assertEqual(lines[1], expected, "the refusal line must be the library's, byte for byte")
end)

-- ── the degraded stub's contract (slash-commands-§1, WS-02, LK-18) ──────────
--
-- A library-absent load keeps exactly one library string, the disabled line's
-- format, pinned byte for byte against the live major. The composed-row verbs
-- take route (a): `enable` / `disable` go through the stub's CliSet, which
-- writes a bool literal for a path on NS.Settings.WRITE_THROUGH and nothing
-- else, and `lock` writes through the Schema stub's own writeThrough. Every
-- other schema verb prints the collection's one library-absent line.

--- A fresh library-absent load, enabled, with its chat captured by `run`.
local function degraded()
    local inst = T.load(true, true, nil, { libFiles = {} })
    assertNil(inst.mocks.LibStub("LibKa0s-Slash-1.0", true), "sanity: no Slash major on this load")
    return inst
end

--- Run one slash line on `inst` under pcall; return ok, err and every line printed.
local function degradedRun(inst, input)
    local lines, real = {}, inst.NS.Util.print
    inst.NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(inst.NS.OnSlashCommand, inst.NS, input)
    inst.NS.Util.print = real
    return ok, err, lines
end

local ABSENT = "%s is unavailable: the LibKa0s library did not load."

test("the stub's DisabledLine format is the library constant, byte for byte", function()
    -- red under: any byte of the stub's copy drifting from lib.DISABLED_LINE_FORMAT
    local inst = degraded()
    T.assertLibraryConstant(inst.NS.Slash.cli.__disabledLineFormat,
        "LibKa0s-Slash-1.0", "DISABLED_LINE_FORMAT")
    -- ...and the line built from it is the live line, brand and verb included.
    local expected = T.NS.Slash.cli:DisabledLine()
    assertEqual(inst.NS.Slash.cli:DisabledLine(), expected,
        "the degraded DisabledLine must equal the live one")
end)

test("the stub carries no copy of the library's reserved verbs", function()
    -- slash-commands-§1 lets a stub carry ONE library string, DISABLED_LINE_FORMAT.
    -- The gate below is the host's own list of its feature verbs instead.
    -- red under: a stub that re-types lib.LIVE_VERBS (the KC-19 first cut did)
    local inst = degraded()
    assertNil(inst.NS.Slash.cli.__reservedVerbs, "no reserved-verb copy on the stub")
    local fh = assert(io.open(T.root .. "/settings/Slash.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:find('"resetall",%s*}'), "settings/Slash.lua must not spell out the reserved-verb array")
end)

test("the host's feature verbs are exactly the verbs the live gate refuses", function()
    -- NS.FEATURE_VERBS drives the degraded gate; the live gate refuses every
    -- registered verb outside lib.LIVE_VERBS + NS.EXTRA_LIVE_VERBS. The two
    -- judgments must name the same verbs, or the two loads would disagree.
    -- red under: a feature verb added to COMMANDS without joining NS.FEATURE_VERBS
    local live = {}
    for _, v in ipairs(T.mocks.LibStub("LibKa0s-Slash-1.0", true).LIVE_VERBS) do live[v] = true end
    for _, v in ipairs(T.NS.EXTRA_LIVE_VERBS) do live[v] = true end
    local refused = {}
    for _, e in ipairs(T.NS.COMMANDS) do
        if not live[e[1]] then refused[#refused + 1] = e[1] end
    end
    local feature = {}
    for _, v in ipairs(T.NS.FEATURE_VERBS) do feature[#feature + 1] = v end
    table.sort(refused)
    table.sort(feature)
    assertEqual(table.concat(feature, ","), table.concat(refused, ","))
end)

test("degraded gate while disabled refuses feature verbs and nothing else", function()
    -- red under: a degraded gate that refuses a reserved verb, or `spells`
    local inst = degraded()
    degradedRun(inst, "disable")
    assertEqual(inst.NS.db.profile.enabled, false, "sanity: disabled")
    local refusal = T.NS.Slash.cli:DisabledLine()
    local _, _, lines = degradedRun(inst, "resetposition")
    assertEqual(joined(lines), refusal, "resetposition is a feature verb")
    _, _, lines = degradedRun(inst, "list")
    assertEqual(joined(lines), ABSENT:format("/kcd list"), "list is reserved, never refused")
    _, _, lines = degradedRun(inst, "version")
    assertTrue(joined(lines) ~= refusal, "version answers: " .. joined(lines))
    _, _, lines = degradedRun(inst, "spells")
    assertTrue(not joined(lines):find(refusal, 1, true), "spells answers: " .. joined(lines))
end)

test("degraded help rows print `cmd  desc` plainly, with no em dash", function()
    -- slash-commands-§1: no FormatRow copy, so no gold command and no ` — `.
    -- red under: the stub's LandingRows joining with the library's separator
    local inst = degraded()
    local rows = inst.NS.Slash.cli.LandingRows()
    assertEqual(rows[1], "/kcd help  List available commands")
    -- Every row is exactly `/kcd <verb>  <desc>`; a description MAY carry its own
    -- em dash (the host's text), the separator may not.
    for i, e in ipairs(inst.NS.COMMANDS) do
        assertEqual(rows[i], "/kcd " .. e[1] .. "  " .. e[2])
    end
end)

test("degraded `/kcd debug` and `/kcd spells` print their sub-lists without raising", function()
    -- slash-commands-§1: a library-absent install still lists the sub-verbs.
    local inst = degraded()
    local ok, err, lines = degradedRun(inst, "debug")
    assertTrue(ok, tostring(err))
    assertTrue(joined(lines):find("/kcd debug diagnostics", 1, true) ~= nil, "got: " .. joined(lines))
    ok, err, lines = degradedRun(inst, "spells")
    assertTrue(ok, tostring(err))
    assertTrue(joined(lines):find("/kcd spells list", 1, true) ~= nil, "got: " .. joined(lines))
end)

test("degraded `/kcd list` prints the library-absent line", function()
    local inst = degraded()
    local ok, err, lines = degradedRun(inst, "list")
    assertTrue(ok, tostring(err))
    assertEqual(#lines, 1, "one line: " .. joined(lines))
    assertEqual(lines[1], ABSENT:format("/kcd list"))
end)

test("degraded CliProfile and ProfileSwitch print the library-absent line and switch nothing", function()
    -- Slash minor 17 puts both on the live instance, so the stub carries both
    -- (route (b)): with no library there is no store adapter to trust.
    -- red under: a stub missing either member, switching through NS.db, or raising
    local inst = degraded()
    local before = inst.NS.db:GetCurrentProfile()
    local stub = inst.NS.Slash.cli
    local lines, real = {}, inst.NS.Util.print
    inst.NS.Util.print = function(m) lines[#lines + 1] = tostring(m) end
    local ok1, err1 = pcall(function() return stub:CliProfile("Alt") end)
    local ok2, switched = pcall(function() return stub:ProfileSwitch("Alt") end)
    inst.NS.Util.print = real
    assertTrue(ok1, tostring(err1))
    assertTrue(ok2, tostring(switched))
    assertEqual(switched, false, "ProfileSwitch answers false: it switched nothing")
    assertEqual(joined(lines), ABSENT:format("/kcd profile") .. "\n" .. ABSENT:format("/kcd profile"))
    assertEqual(inst.NS.db:GetCurrentProfile(), before, "the profile did not move")
end)

test("degraded `/kcd set visibility always` writes nothing and prints the library-absent line", function()
    -- `visibility` is a COMPOSED row, absent on this load and not on the
    -- writeThrough list, so route (b) applies to it.
    local inst = degraded()
    local before = inst.mocks.__deepcopy(inst.NS.db.profile)
    local ok, err, lines = degradedRun(inst, "set visibility always")
    assertTrue(ok, tostring(err))
    assertEqual(#lines, 1, "one line: " .. joined(lines))
    assertEqual(lines[1], ABSENT:format("/kcd set"))
    assertEqual(inst.NS.db.profile.visibility, before.visibility, "nothing was written")
end)

test("degraded `/kcd set` refuses a non-bool value even on a writeThrough path", function()
    local inst = degraded()
    local ok, err, lines = degradedRun(inst, "set enabled maybe")
    assertTrue(ok, tostring(err))
    assertEqual(lines[1], ABSENT:format("/kcd set"))
    assertTrue(inst.NS.db.profile.enabled ~= false, "enabled was not touched")
end)

test("degraded `/kcd lock` writes locked, and confirms", function()
    local inst = degraded()
    inst.NS.db.profile.locked = false
    local ok, err, lines = degradedRun(inst, "lock")
    assertTrue(ok, tostring(err))
    assertEqual(inst.NS.db.profile.locked, true, "lock landed")
    assertTrue(joined(lines):find("icon grid locked", 1, true) ~= nil, "got: " .. joined(lines))
end)

test("degraded `/kcd lock` while disabled prints the DisabledLine and does not act", function()
    -- red under: a stub OnSlash with no gate
    local inst = degraded()
    degradedRun(inst, "disable")
    assertEqual(inst.NS.db.profile.enabled, false, "sanity: disabled")
    local before = inst.NS.db.profile.locked
    local ok, err, lines = degradedRun(inst, "lock")
    assertTrue(ok, tostring(err))
    assertEqual(#lines, 1, "one line: " .. joined(lines))
    assertEqual(lines[1], T.NS.Slash.cli:DisabledLine(), "the collection's refusal line")
    assertEqual(inst.NS.db.profile.locked, before, "the lock did not move")
end)
