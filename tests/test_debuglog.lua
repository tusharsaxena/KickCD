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
    -- The [Init] snapshot now lands after the bracket line on enable, so the
    -- bracket is no longer LastLine — assert its presence in the buffer.
    assertTrue(ns.DebugLog:FindLine("[Debug] logging enabled"),
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

test("NS.Debug sanitizes secret args and never errors", function()
    -- Stub a secret sentinel on the MOCK the addon actually reads: the sandbox
    -- env resolves _G.issecretvalue through T.mocks (wow_mock defines it), which
    -- shadows any stub on the real _G.
    local SECRET = setmetatable({}, {})
    local realIsSecret = T.mocks.issecretvalue
    T.mocks.issecretvalue = function(v) return v == SECRET end
    NS.State.debug = true
    NS.DebugLog:Clear()
    local ok = pcall(function() NS.Debug("T", "charges=%s", SECRET) end)
    T.mocks.issecretvalue = realIsSecret
    assertTrue(ok, "sink must not error on a secret arg")
    local line = NS.DebugLog:LastLine()
    assertTrue(line and line:find("charges=secret", 1, true) ~= nil,
        "secret arg must render as 'secret'; got: " .. tostring(line))
    NS.State.debug = false   -- leave the shared instance clean for later suites
end)

test("NS.Debug passes plain args through unchanged", function()
    NS.State.debug = true
    NS.DebugLog:Clear()
    NS.Debug("T", "n=%d s=%s", 7, "hi")
    local line = NS.DebugLog:LastLine()
    assertTrue(line and line:find("n=7 s=hi", 1, true) ~= nil,
        "plain args must be unchanged; got: " .. tostring(line))
    NS.State.debug = false   -- leave the shared instance clean for later suites
end)

test("scrollbar + line-counter sync methods exist (§11)", function()
    assertTrue(type(DebugLog.UpdateScrollBar) == "function",
        "DebugLog:UpdateScrollBar must exist")
    assertTrue(type(DebugLog.UpdateStatus) == "function",
        "DebugLog:UpdateStatus must exist")
end)

test("sync methods are a clean no-op before the window is built (§11)", function()
    -- Fresh instance whose console window has never been shown: both syncs must
    -- return without error (window == nil) rather than touching a nil frame.
    local dl = T.load(true).NS.DebugLog
    assertEqual(dl:IsShown(), false, "window must start unbuilt")
    local ok = pcall(function() dl:UpdateScrollBar(); dl:UpdateStatus() end)
    assertTrue(ok, "syncs must be safe with no window built")
end)

test("building the console + Add/Clear run the guarded sync headlessly (§11)", function()
    -- Show() builds the window (scrollbar Slider + counter) and runs the initial
    -- sync. Under the headless mock the frame's GetMaxScrollRange returns a
    -- non-number, so the type guard makes UpdateScrollBar a clean no-op — this
    -- is exactly the "MUST stay a no-op under the test mock" rule of §11. The
    -- whole flow must complete without raising (and never call the nil C getters
    -- GetNumLinesDisplayed / GetCurrentScroll).
    local dl = T.load(true).NS.DebugLog
    local ok, err = pcall(function()
        dl:Show()
        dl:Add("Test", "line one")
        dl:Add("Test", "line two")
        dl:Clear()
        dl:Hide()
    end)
    assertTrue(ok, "console build + Add/Clear must not error: " .. tostring(err))
end)

test("console WINDOW visibility is decoupled from the capture flag (§12.5)", function()
    -- The General "Debug console" checkbox drives IsShown/Show/Hide (window),
    -- NOT SetEnabled (capture). Enabling capture must not open the window.
    local ns = T.load(true).NS
    local dl = ns.DebugLog
    assertTrue(type(dl.IsShown) == "function", "DebugLog:IsShown must exist")
    assertEqual(dl:IsShown(), false, "window starts hidden")
    dl:SetEnabled(true)
    assertEqual(dl:IsShown(), false, "enabling capture must not show the window")
    assertEqual(ns.State.debug, true, "capture flag is independently on")
    dl:SetEnabled(false)
end)
