-- tests/test_util.lua — pure helpers in core/Util.lua
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local Util = NS.Util

test("Util.Unpack array-style color", function()
    local r, g, b, a = Util.Unpack({ 0.2, 0.4, 0.6, 0.8 })
    assertEqual(r, 0.2); assertEqual(g, 0.4); assertEqual(b, 0.6); assertEqual(a, 0.8)
end)

test("Util.Unpack hash-style color", function()
    local r, g, b, a = Util.Unpack({ r = 0.1, g = 0.2, b = 0.3, a = 0.4 })
    assertEqual(r, 0.1); assertEqual(g, 0.2); assertEqual(b, 0.3); assertEqual(a, 0.4)
end)

test("Util.Unpack nil defaults to opaque white", function()
    local r, g, b, a = Util.Unpack(nil)
    assertEqual(r, 1); assertEqual(g, 1); assertEqual(b, 1); assertEqual(a, 1)
end)

test("Util.NormalizeSpecToken strips whitespace and upper-cases", function()
    assertEqual(Util.NormalizeSpecToken("Beast Mastery"), "BEASTMASTERY")
    assertEqual(Util.NormalizeSpecToken("Mistweaver"), "MISTWEAVER")
    assertEqual(Util.NormalizeSpecToken(nil), "")
end)

test("Util.PlayerSpecID returns the numeric spec ID, not the localized name", function()
    -- The shared mock is an enUS Beast Mastery Hunter (specID 253).
    assertEqual(Util.PlayerSpecID(), 253)
end)

test("Util.SpecTokenForID maps a spec ID to its English token", function()
    assertEqual(Util.SpecTokenForID(253), "BEASTMASTERY")
    assertEqual(Util.SpecTokenForID(262), "ELEMENTAL")
    assertEqual(Util.SpecTokenForID(1480), "DEVOURER")
    assertEqual(Util.SpecTokenForID(nil), nil)
    assertEqual(Util.SpecTokenForID(999999), nil, "an unknown ID must not invent a token")
end)

test("Util.SpecDisplay prefers the English token and falls back to the raw ID", function()
    -- Log lines and /kcd output are what bug reports quote, so they must stay
    -- English and human-readable even on a localized client (issue #8).
    assertEqual(Util.SpecDisplay(262), "ELEMENTAL")
    assertEqual(Util.SpecDisplay(999999), "999999", "an unknown ID must still print something")
    assertEqual(Util.SpecDisplay(nil), "nil")
end)

test("Util.ResolveSpecID accepts a number, a numeric string and an English token", function()
    assertEqual(Util.ResolveSpecID(262), 262)
    assertEqual(Util.ResolveSpecID("262"), 262)
    assertEqual(Util.ResolveSpecID("ELEMENTAL"), 262)
    assertEqual(Util.ResolveSpecID("elemental"), 262)
    assertEqual(Util.ResolveSpecID("Beast Mastery"), 253, "whitespace must still be stripped")
end)

test("Util.ResolveSpecID rejects unknown input rather than guessing", function()
    assertEqual(Util.ResolveSpecID("NOTASPEC"), nil)
    assertEqual(Util.ResolveSpecID(""), nil)
    assertEqual(Util.ResolveSpecID(nil), nil)
end)

test("Util.NormalizeClassToken upper-cases", function()
    assertEqual(Util.NormalizeClassToken("Hunter"), "HUNTER")
    assertEqual(Util.NormalizeClassToken(nil), "")
end)

test("Util.DeepCopy clones nested tables (no shared refs)", function()
    local src = { a = 1, nested = { x = { 1, 2, 3 } } }
    local dst = Util.DeepCopy(src)
    assertEqual(dst.a, 1)
    assertEqual(dst.nested.x[2], 2)
    assertTrue(dst.nested ~= src.nested, "nested table must be a fresh copy")
    dst.nested.x[2] = 99
    assertEqual(src.nested.x[2], 2, "mutating the copy must not touch the source")
end)

test("Util.Throttle coalesces a burst to one trailing-args call", function()
    T.mocks.__flushTimers()  -- drain any pending timers first
    local calls, lastArg = 0, nil
    local wrapped = Util.Throttle(50, function(v) calls = calls + 1; lastArg = v end)
    wrapped(1); wrapped(2); wrapped(3)
    assertEqual(calls, 0, "throttled fn must not fire synchronously")
    T.mocks.__flushTimers()
    assertEqual(calls, 1, "burst must coalesce to a single call")
    assertEqual(lastArg, 3, "trailing call's args win")
end)

test("RegisterUnitCastEvent registers the dispatch frame for the named unit", function()
    local calls = {}
    local module = { OnX = function(self, event, unit) calls[#calls+1] = { event, unit } end }
    local f = NS.Util.RegisterUnitCastEvent(module, "focus", "UNIT_SPELLCAST_START", "OnX")
    assertTrue(f ~= nil, "returns a frame for teardown")
    assertEqual(f._unitEvents["UNIT_SPELLCAST_START"], "focus", "registered for focus, not target")
    -- simulate the event firing for focus
    f:_fire("UNIT_SPELLCAST_START", "focus")
    assertEqual(calls[1][2], "focus", "handler receives the unit")
end)
