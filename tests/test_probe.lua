-- tests/test_probe.lua -- `/kcd debug probe start|stop|status|clear` (the WoW Forever port, MKF-KC-16;
-- Ka0sAddonsCommonTasks docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT, the design's "Probe verbs";
-- LootHistory's modules/Probe.lua is the precedent, 2026-11-22 rulings R3 and R4).
--
-- While started, modules/Probe.lua records the client facts the port's safe defaults rest on into
-- ONE capped table, db.global.probe, stamped with the client and its build: a `start` entry of
-- facts read once, then an entry per watched event. docs/forever-probes.md maps each kind to the
-- probe it answers. Every case builds its own instance: the probe's state is per load.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

--- A Forever instance whose player is `classFile`, knowing `ids`; chat captured on `inst.lines`.
local function forever(classFile, ids, mutate)
    local inst = T.load(true, true, function(m)
        m.__setForeverClass(classFile or "ROGUE")
        m.__learn(ids or {})
        if mutate then mutate(m) end
    end, { world = "forever" })
    inst.lines = {}
    inst.NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        inst.lines[#inst.lines + 1] = table.concat(parts, " ")
    end
    return inst
end

local function slash(inst, line) inst.NS:OnSlashCommand(line) end
local function store(inst) return inst.NS.db.global.probe end
local function last(inst) local s = store(inst); return s.entries[#s.entries] end

local function frame(inst) return inst.NS.Probe._state.frame end

--- Fire `event` on the probe's private frame, as the client would.
local function fire(inst, event, ...)
    local f = frame(inst)
    assertTrue(f ~= nil and f.__events[event] ~= nil, event .. " is not registered on the probe frame")
    f:_fire(event, ...)
end

-- ── the verbs ───────────────────────────────────────────────────────────────

test("Probe: a bare probe and `status` answer one line, stopped and empty before a start", function()
    local inst = forever()
    slash(inst, "debug probe")
    slash(inst, "debug probe status")
    assertEqual(inst.lines[1], "probe: stopped, 0 entries (cap 500)")
    assertEqual(inst.lines[2], inst.lines[1])
    assertNil(store(inst), "a status makes no record")
end)

test("Probe: start stamps the client, its build and the addon, and writes a start entry", function()
    local inst = forever()
    slash(inst, "debug probe start")
    local s = store(inst)
    assertTrue(s ~= nil, "the record is db.global.probe")
    assertEqual(s.client, "forever")
    assertTrue(s.version ~= nil and s.build ~= nil, "the client's version and build")
    assertTrue(s.addonVersion ~= nil, "the addon's version")
    assertEqual(#s.entries, 1)
    assertEqual(s.entries[1].kind, "start")
    for _, part in ipairs({ "rules", "gcd", "deprecation", "classes", "spec", "ranks", "runes", "feral",
        "spells", "secrets", "viewer" }) do
        assertTrue(s.entries[1][part] ~= nil, "the start entry records " .. part)
    end
    assertTrue(inst.NS.Probe.IsRunning())
    assertTrue(inst.lines[1]:find("probe started", 1, true) ~= nil, tostring(inst.lines[1]))
end)

test("Probe: the start entry records each rank's answers and the rank the resolver picks", function()
    -- U15: whether a superseded rank stays known. Kick ranks 1 and 2 learned.
    local inst = forever("ROGUE", { 1766, 1767 })
    slash(inst, "debug probe start")
    local kick = store(inst).entries[1].ranks[1766]
    assertTrue(kick ~= nil, "the Kick family is recorded")
    assertEqual(kick.resolved, 1767, "the highest known rank")
    assertEqual(kick.ranks[1].id, 1766); assertEqual(kick.ranks[1].known, true)
    assertEqual(kick.ranks[3].id, 1768); assertEqual(kick.ranks[3].known, false)
end)

test("Probe: the start entry says whether the global cooldown spell answers", function()
    local inst = forever()
    slash(inst, "debug probe start")
    assertEqual(store(inst).entries[1].gcd.answers, false, "61304 has no row on WoW Forever")
end)

test("Probe: stop unregisters every event and stamps the record; start again resumes it", function()
    local inst = forever()
    slash(inst, "debug probe start")
    local f = frame(inst)
    assertTrue(next(f.__events) ~= nil, "the probe registers while running")
    slash(inst, "debug probe stop")
    assertNil(next(f.__events), "nothing stays registered")
    assertFalse(inst.NS.Probe.IsRunning())
    assertTrue(store(inst).stopped ~= nil)
    assertEqual(last(inst).kind, "stop")
    slash(inst, "debug probe start")
    assertEqual(last(inst).kind, "start", "a second start appends to the same record")
end)

test("Probe: clear drops the record; while running a fresh, stamped one goes on", function()
    local inst = forever()
    slash(inst, "debug probe start")
    slash(inst, "debug probe clear")
    local s = store(inst)
    assertTrue(s ~= nil and #s.entries == 0, "a fresh record while running")
    assertEqual(s.client, "forever")
    slash(inst, "debug probe stop")
    slash(inst, "debug probe clear")
    assertNil(store(inst), "stopped, the record is gone")
end)

test("Probe: an unknown word prints the usage line", function()
    local inst = forever()
    slash(inst, "debug probe nope")
    assertEqual(inst.lines[1], "usage: /kcd debug probe start, stop, status or clear")
end)

test("Probe: the `/kcd debug` list names the probe", function()
    local inst = forever()
    slash(inst, "debug nope")
    assertTrue(table.concat(inst.lines, "\n"):find("probe", 1, true) ~= nil)
end)

-- ── the casts (U14: the flag a target's cast carries) ───────────────────────

local function casting(flag)
    return function(m)
        m.UnitExists = function() return true end
        m.UnitCastingInfo = function(unit)
            if unit ~= "target" then return nil end
            return "Shadow Bolt", "", 136197, 1000, 3000, false, 7, m.__flag, 686
        end
        m.__flag = flag
    end
end

test("Probe: a target's cast records whether its flag is nil, plain or secret", function()
    local inst = forever("ROGUE", {}, casting(nil))
    slash(inst, "debug probe start")
    fire(inst, "UNIT_SPELLCAST_START", "target", "Cast-1", 686)
    local e = last(inst)
    assertEqual(e.kind, "cast"); assertEqual(e.unit, "target"); assertEqual(e.spellID, 686)
    assertEqual(e.flag, "nil", "a plain nil is the fact the nil guard rests on")
    inst.mocks.__flag = false
    fire(inst, "UNIT_SPELLCAST_START", "target", "Cast-2", 686)
    assertEqual(last(inst).flag, false)
    inst.mocks.__flag = T.secret(true)
    fire(inst, "UNIT_SPELLCAST_START", "target", "Cast-3", 686)
    assertEqual(last(inst).flag, inst.NS.SECRET, "a secret is never stored")
end)

test("Probe: a cast on a unit the addon does not track is not recorded", function()
    local inst = forever("ROGUE", {}, casting(nil))
    slash(inst, "debug probe start")
    local n = #store(inst).entries
    fire(inst, "UNIT_SPELLCAST_START", "party1", "Cast-1", 686)
    assertEqual(#store(inst).entries, n)
end)

-- ── the form, the spellbook, combat ─────────────────────────────────────────

test("Probe: a form change records the form and Feral Charge's override (U16)", function()
    local inst = forever("DRUID", { 1238122 }, function(m)
        m.GetShapeshiftFormID = function() return 5 end
        m.C_Spell.GetOverrideSpell = function(id) return id == 1238122 and 16979 or id end
    end)
    slash(inst, "debug probe start")
    fire(inst, "UPDATE_SHAPESHIFT_FORM")
    local e = last(inst)
    assertEqual(e.kind, "form")
    assertEqual(e.feral.form, 5)
    assertEqual(e.feral.override, 16979)
    assertEqual(e.feral.inBook, true)
end)

test("Probe: a spellbook change is recorded only when its answers changed (U17)", function()
    local inst = forever("WARLOCK", {})
    slash(inst, "debug probe start")
    fire(inst, "SPELLS_CHANGED")
    local n = #store(inst).entries
    assertEqual(last(inst).kind, "spellbook")
    fire(inst, "SPELLS_CHANGED")
    assertEqual(#store(inst).entries, n, "the same answers twice are one entry")
    inst.mocks.__learn({ 19244 }, 1)
    fire(inst, "SPELLS_CHANGED")
    assertEqual(#store(inst).entries, n + 1)
    assertEqual(last(inst).pet[19244], true, "Spell Lock on the pet's bank")
end)

test("Probe: combat start records the tracked kick's cooldown secrecy (U20)", function()
    local inst = forever("ROGUE", { 1766 })
    slash(inst, "debug probe start")
    fire(inst, "PLAYER_REGEN_DISABLED")
    local e = last(inst)
    assertEqual(e.kind, "combat")
    assertEqual(e.kick, 1766)
    assertTrue(e.cooldown ~= nil, "the cooldown's answers")
end)

-- ── the record's guards ─────────────────────────────────────────────────────

test("Probe: past the cap the oldest entry that is not a start goes, and is counted", function()
    local inst = forever()
    local P = inst.NS.Probe
    slash(inst, "debug probe start")
    for i = 1, P.CAP + 5 do P.Record("note", { i = i }) end
    local s = store(inst)
    assertEqual(#s.entries, P.CAP)
    assertEqual(s.entries[1].kind, "start", "the start entry survives")
    assertEqual(s.dropped, 6)
    slash(inst, "debug probe status")
    assertTrue(inst.lines[#inst.lines]:find("6 dropped", 1, true) ~= nil, inst.lines[#inst.lines])
end)

test("Probe: a long string is cut, and a table or function is stored as its type", function()
    local P = forever().NS.Probe
    assertEqual(#P.plain(string.rep("x", P.TEXT_MAX + 50)), P.TEXT_MAX)
    assertEqual(P.plain({}), "<table>")
    assertEqual(P.plain(print), "<function>")
    assertEqual(P.plain(T.secret("Shadow Bolt")), forever().NS.SECRET)
end)

test("Probe: a handler that raises is recorded as an error entry, never thrown", function()
    local inst = forever()
    slash(inst, "debug probe start")
    inst.NS.Probe._handlers.UPDATE_SHAPESHIFT_FORM = function() error("boom") end
    fire(inst, "UPDATE_SHAPESHIFT_FORM")
    local e = last(inst)
    assertEqual(e.kind, "error"); assertEqual(e.event, "UPDATE_SHAPESHIFT_FORM")
    assertTrue(tostring(e.err):find("boom", 1, true) ~= nil)
end)

test("Probe: nothing is recorded while a simulation runs, and the start refuses during one", function()
    local inst = forever()
    local P = inst.NS.Probe
    local active = true
    inst.NS.Sim.IsActive = function() return active end
    local ok, why = P.Start()
    assertFalse(ok); assertEqual(why, "simulation")
    active = false
    assertTrue(P.Start())
    local n = #store(inst).entries
    active = true
    assertNil(P.Record("note", {}))
    assertEqual(#store(inst).entries, n)
end)

test("Probe: Retail records the same start entry, stamped retail", function()
    local inst = T.load(true, true, T.retailClient)
    inst.NS.Util.print = function() end
    inst.NS:OnSlashCommand("debug probe start")
    local s = inst.NS.db.global.probe
    assertEqual(s.client, "retail")
    assertEqual(s.entries[1].kind, "start")
    assertEqual(s.entries[1].gcd.answers, true, "61304 answers on Retail")
end)
