-- tests/test_debuglog.lua — pure formatters + session-only sink (§12.3/§12.4/§12.5)
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local DebugLog = NS.DebugLog

test("DebugLog module loaded with its public API", function()
    assertTrue(DebugLog ~= nil, "DebugLog must be published")
    assertTrue(type(DebugLog.FormatPlain) == "function")
    assertTrue(type(DebugLog.FormatColored) == "function")
    assertTrue(type(DebugLog.SetEnabled) == "function")
    assertTrue(type(NS.Debug) == "function", "the NS.Debug sink must exist")
end)

test("FormatPlain is clean, un-coloured, and well-shaped (§12.3)", function()
    assertEqual(DebugLog.FormatPlain("12:00:00", "Cast", "hello"), "12:00:00 | [Cast] hello")
    -- no colour escapes in the copy buffer
    assertFalse(DebugLog.FormatPlain("12:00:00", "Cast", "x"):find("|c", 1, true))
end)

test("FormatColored carries the same fields as FormatPlain (no drift)", function()
    local c = DebugLog.FormatColored("12:00:00", "Cast", "hello")
    assertTrue(c:find("12:00:00", 1, true) ~= nil, "timestamp present")
    assertTrue(c:find("[Cast]", 1, true) ~= nil, "tag present")
    assertTrue(c:find("hello", 1, true) ~= nil, "message present")
    assertTrue(c:find("|cff6f8faf", 1, true) ~= nil, "steel-blue timestamp colour")
    assertTrue(c:find("|cffc9a66b", 1, true) ~= nil, "tan tag colour")
end)

test("debug flag defaults OFF and lives in State, never in SavedVariables (§12.5)", function()
    local inst = T.load(true)
    local ns = inst.NS
    assertEqual(ns.State.debug, false, "debug must default off")
    assertEqual(ns.db.profile.debugLog, nil, "debug flag must NOT be in the profile")
    assertEqual(ns.db.global.debugLog, nil, "debug flag must NOT be in global SV either")
end)

test("SetEnabled is the single write seam and toggles State.debug", function()
    local inst = T.load(true)
    local ns = inst.NS
    ns.DebugLog:SetEnabled(true)
    assertEqual(ns.State.debug, true)
    ns.DebugLog:SetEnabled(false)
    assertEqual(ns.State.debug, false)
end)

test("SetEnabled brackets each session with a console line at both ends (§12.5)", function()
    local inst = T.load(true)
    local ns = inst.NS
    ns.DebugLog:SetEnabled(true)
    assertTrue(ns.DebugLog:LastLine():find("[Debug] logging enabled", 1, true) ~= nil,
        "enable must append a bracket console line")
    ns.DebugLog:SetEnabled(false)
    assertTrue(ns.DebugLog:LastLine():find("[Debug] logging disabled", 1, true) ~= nil,
        "disable line must land even though the flag just flipped off")
end)

test("NS.Debug is a no-op when disabled (zero capture) and appends when enabled", function()
    local inst = T.load(true)
    local ns = inst.NS
    ns.DebugLog:SetEnabled(false)
    local before = ns.DebugLog:BufferSize()
    ns.Debug("Cast", "should be dropped")
    assertEqual(ns.DebugLog:BufferSize(), before, "disabled sink must not capture")

    ns.DebugLog:SetEnabled(true)
    -- SetEnabled(true) itself logs a bracket line (above), so recapture here.
    before = ns.DebugLog:BufferSize()
    ns.Debug("Cast", "kick on %s", "target")
    assertEqual(ns.DebugLog:BufferSize(), before + 1, "enabled sink must capture one line")
    assertTrue(ns.DebugLog:LastLine():find("[Cast] kick on target", 1, true) ~= nil,
        "captured line must be format-expanded and tagged")
end)
