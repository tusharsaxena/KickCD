-- tests/test_cooldowns_refresh.lua — Cooldowns:Refresh, the per-poll pass
--
-- Characterization coverage written green against the pre-split Cooldowns:Refresh (CCN 46 under
-- the sighted complexity gate, GI-KC-12), so its split below CCN 15 is checked rather than
-- assumed. tests/test_cooldowns.lua pins the emit contract and the (gcd) marker's live traces;
-- these cases pin the rest of what the pass decides: its two guards, the vanished-spell sentinel,
-- the exact shape of the summary line, the GCD attribution it carries on the records, and the two
-- Perf brackets.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

local GCD = 61304

--- A fresh enabled addon with debug on, the console cleared, and SPELL_STATE payloads recorded.
local function harness(debug)
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = debug ~= false
    inst.NS.DebugLog:Clear()
    local spy = {}
    inst.mocks.__libs["AceEvent-3.0"]:Embed(spy)
    local emits = {}
    spy:RegisterMessage(T.NS.MSG.SPELL_STATE, function(_, p) emits[#emits + 1] = p end)
    return inst, Cooldowns, emits
end

local function gcd(inst, active)
    inst.mocks.spellCooldowns[GCD] = { isEnabled = true, isActive = active }
end

test("Refresh does nothing while the master enable is off", function()
    local inst, Cooldowns, emits = harness()
    Cooldowns.watched = { [100] = { spellID = 100, ready = true, isActive = false } }
    local polls = 0
    Cooldowns.PollSpell = function() polls = polls + 1 end
    inst.NS.MasterEnabled = function() return false end
    Cooldowns:Refresh()
    assertEqual(polls, 0); assertEqual(#emits, 0)
    assertEqual(inst.NS.DebugLog:BufferSize(), 0)
end)

test("Refresh does nothing before the first Rebuild", function()
    local _, Cooldowns, emits = harness()
    Cooldowns.watched = nil
    local polls = 0
    Cooldowns.PollSpell = function() polls = polls + 1 end
    Cooldowns:Refresh()
    assertEqual(polls, 0); assertEqual(#emits, 0)
end)

test("a vanished spell is dropped, emits the ready sentinel, and is named drop=[]", function()
    local inst, Cooldowns, emits = harness()
    gcd(inst, false)
    Cooldowns.watched = {
        [100] = { spellID = 100, ready = false, isActive = true },
        [200] = { spellID = 200, ready = true,  isActive = false },
    }
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return nil end
        return { spellID = 200, ready = true, isActive = false }
    end
    Cooldowns:Refresh()
    assertNil(Cooldowns.watched[100], "the vanished spell stops being polled")
    assertTrue(Cooldowns.watched[200] ~= nil, "the other spell stays")
    assertEqual(#emits, 1)
    local p = emits[1]
    assertEqual(p.spellID, 100); assertEqual(p.ready, false); assertEqual(p.isActive, false)
    assertNil(p.cdObject); assertNil(p.chargeCdObject); assertNil(p.charges)
    -- A drop never disqualifies the GCD marker: only a material transition can.
    assertEqual(inst.NS.DebugLog:LastLine():match("%d+/%d+ changed: .*$"), "1/2 changed: drop=[100] (gcd)")
end)

test("the summary line lists ready, then active, then drop, over the watched count", function()
    local inst, Cooldowns = harness()
    gcd(inst, false)
    Cooldowns.watched = {
        [100] = { spellID = 100, ready = false, isActive = true },
        [300] = { spellID = 300, ready = true,  isActive = false },
        [400] = { spellID = 400, ready = true,  isActive = false },
        [500] = { spellID = 500, ready = true,  isActive = false },
    }
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return { spellID = 100, ready = true,  isActive = false } end
        if id == 300 then return { spellID = 300, ready = false, isActive = true } end
        if id == 400 then return nil end
        return { spellID = 500, ready = true, isActive = false }
    end
    Cooldowns:Refresh()
    assertEqual(inst.NS.DebugLog:LastLine():match("%d+/%d+ changed: .*$"),
        "3/4 changed: ready=[100] active=[300] drop=[400]")
end)

test("a material change replaces the record and emits every field of the new state", function()
    local _, Cooldowns, emits = harness(false)
    local cd, ccd = {}, {}
    Cooldowns.watched = { [100] = { spellID = 100, ready = true, isActive = false } }
    local next_ = { spellID = 100, ready = false, isActive = true,
                    cdObject = cd, chargeCdObject = ccd, charges = 2 }
    Cooldowns.PollSpell = function() return next_ end
    Cooldowns:Refresh()
    assertTrue(Cooldowns.watched[100] == next_, "the polled state becomes the record")
    assertEqual(#emits, 1)
    local p = emits[1]
    assertEqual(p.spellID, 100); assertEqual(p.ready, false); assertEqual(p.isActive, true)
    assertTrue(p.cdObject == cd and p.chargeCdObject == ccd)
    assertEqual(p.charges, 2)
    assertTrue(p ~= next_, "the payload is a fresh table, not the record")
end)

test("a secret-charges emit is not logged, so no line is written for it", function()
    local inst, Cooldowns, emits = harness()
    local SECRET = setmetatable({}, {})
    inst.mocks.issecretvalue = function(v) return v == SECRET end
    Cooldowns.watched = { [100] = { spellID = 100, ready = true, isActive = false, charges = SECRET } }
    Cooldowns.PollSpell = function() return { spellID = 100, ready = true, isActive = false, charges = SECRET } end
    Cooldowns:Refresh()
    assertEqual(#emits, 1, "the conservative emit")
    assertEqual(inst.NS.DebugLog:BufferSize(), 0, "but no material change to log")
end)

test("with the console off no GCD attribution is written onto any record", function()
    local inst, Cooldowns = harness(false)
    gcd(inst, true)
    local held = { spellID = 200, ready = false, isActive = true, gcdOnly = true }
    Cooldowns.watched = { [100] = { spellID = 100, ready = true, isActive = false }, [200] = held }
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return { spellID = 100, ready = false, isActive = true } end
        return { spellID = 200, ready = false, isActive = true }
    end
    gcd(inst, false)
    Cooldowns:Refresh()
    assertNil(Cooldowns.watched[100].gcdOnly, "a changed record is not stamped")
    assertEqual(held.gcdOnly, true, "and an unchanged one is not withdrawn")
end)

test("an unchanged record keeps its GCD attribution only while a GCD runs", function()
    local inst, Cooldowns = harness()
    local function pass(gcdActive, prev)
        gcd(inst, gcdActive)
        Cooldowns.watched = { [100] = prev }
        Cooldowns.PollSpell = function() return { spellID = 100, ready = prev.ready, isActive = prev.isActive } end
        Cooldowns:Refresh()
        return prev.gcdOnly
    end
    assertEqual(pass(true,  { spellID = 100, ready = false, isActive = true,  gcdOnly = true }), true)
    assertEqual(pass(false, { spellID = 100, ready = false, isActive = true,  gcdOnly = true }), false)
    assertEqual(pass(false, { spellID = 100, ready = true,  isActive = false, gcdOnly = true }), true,
        "a ready record's stale flag is left alone")
end)

test("a changed record is stamped with whose doing its transition was", function()
    local inst, Cooldowns = harness()
    local function pass(gcdActive, prev, next_)
        gcd(inst, gcdActive)
        Cooldowns.watched = { [100] = prev }
        Cooldowns.PollSpell = function() return next_ end
        Cooldowns:Refresh()
        return next_.gcdOnly
    end
    -- Went down: the running GCD is the likeliest cause.
    assertEqual(pass(true,  { spellID = 100, ready = true, isActive = false },
                            { spellID = 100, ready = false, isActive = true }), true)
    assertEqual(pass(false, { spellID = 100, ready = true, isActive = false },
                            { spellID = 100, ready = false, isActive = true }), false)
    -- Still down (the emit is a charge move): kept only while it was the GCD's and a GCD runs.
    assertEqual(pass(true,  { spellID = 100, ready = false, isActive = true, gcdOnly = true, charges = 1 },
                            { spellID = 100, ready = false, isActive = true, charges = 2 }), true)
    assertEqual(pass(false, { spellID = 100, ready = false, isActive = true, gcdOnly = true, charges = 1 },
                            { spellID = 100, ready = false, isActive = true, charges = 2 }), false)
    assertEqual(pass(true,  { spellID = 100, ready = false, isActive = true, gcdOnly = false, charges = 1 },
                            { spellID = 100, ready = false, isActive = true, charges = 2 }), false)
    -- Came back: never the GCD's from here on.
    assertEqual(pass(true,  { spellID = 100, ready = false, isActive = true, gcdOnly = true },
                            { spellID = 100, ready = true, isActive = false }), false)
end)

test("Refresh closes its spellPoll bracket once and a stateEmit bracket per emit", function()
    local inst, Cooldowns = harness(false)
    local P = inst.NS.Perf
    local notes = {}
    local realNote = P.Note
    P.Note = function(key, _, parent) notes[#notes + 1] = key .. ">" .. tostring(parent) end
    P.on = true
    Cooldowns.watched = {
        [100] = { spellID = 100, ready = true, isActive = false },
        [200] = { spellID = 200, ready = true, isActive = false },
        [300] = { spellID = 300, ready = true, isActive = false },
    }
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return nil end
        if id == 200 then return { spellID = 200, ready = false, isActive = true } end
        return { spellID = 300, ready = true, isActive = false }
    end
    local ok, err = pcall(function() Cooldowns:Refresh() end)
    P.on = false
    P.Note = realNote
    assertTrue(ok, tostring(err))
    local count = {}
    for _, n in ipairs(notes) do count[n] = (count[n] or 0) + 1 end
    assertEqual(count["stateEmit>spellPoll"], 2, "the drop and the change each emit once")
    assertEqual(count["spellPoll>nil"], 1, "one pass, one closing note")
    assertEqual(notes[#notes], "spellPoll>nil", "and it closes last")
end)
