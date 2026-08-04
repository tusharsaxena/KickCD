-- tests/test_opensettings.lua — characterization of `NS:OpenSettings`.
--
-- Nothing pinned this before; these cases were written to make the CCN
-- refactor of the function verifiable. What they guard is the `_openRetries`
-- lifecycle, which is otherwise only observable in game and fails in the worst
-- possible way — a counter that never clears leaves the addon permanently
-- refusing to open its own panel after a few racy logins.
local T = _G.KICKCD_TEST
local test, assertEqual, assertNil, assertTrue = T.test, T.assertEqual, T.assertNil, T.assertTrue

--- Fresh instance with the chat frame captured. Returns the instance, the
--- captured line list, and the list of category IDs OpenToCategory was handed.
local function harness()
    local inst = T.load(true)
    local lines, opened = {}, {}
    inst.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }
    inst.mocks.Settings.OpenToCategory = function(id) opened[#opened + 1] = id end
    inst.NS.Settings = { main = { GetID = function() return 77 end } }
    return inst, lines, opened
end

test("OpenSettings refuses in combat and clears the retry counter", function()
    local inst, lines, opened = harness()
    inst.NS._openRetries = 2
    inst.NS.State.inCombat = true
    inst.NS:OpenSettings()
    inst.NS.State.inCombat = false

    assertEqual(#opened, 0, "the protected category switch must not run in combat")
    assertNil(inst.NS._openRetries, "the combat refusal clears the counter")
    assertEqual(#lines, 1)
    assertTrue(lines[1]:find("|r", 1, true) ~= nil, "the notice body is gray-wrapped")
    assertTrue(lines[1]:lower():find("combat", 1, true) ~= nil)
end)

test("OpenSettings also reads combat off InCombatLockdown", function()
    local inst, _, opened = harness()
    inst.mocks.InCombatLockdown = function() return true end
    inst.NS:OpenSettings()
    assertEqual(#opened, 0)
end)

test("OpenSettings opens the registered category and clears the retry counter", function()
    local inst, _, opened = harness()
    inst.NS._openRetries = 2
    inst.NS:OpenSettings()
    assertEqual(#opened, 1)
    assertEqual(opened[1], 77, "the category is opened by ID, not by object")
    assertNil(inst.NS._openRetries, "a successful open resets the counter")
end)

test("OpenSettings defers with a notice when the Settings layer has not registered", function()
    local inst, lines = harness()
    inst.NS.Settings = {}
    inst.NS:OpenSettings("tail")
    assertEqual(inst.NS._openRetries, 1)
    assertEqual(#lines, 1)
    assertTrue(lines[1]:find("Settings still loading", 1, true) ~= nil)
    assertEqual(#inst.mocks.__timers, 1, "a retry must be armed")
end)

test("OpenSettings retries are bounded, then fall through to the plain notice", function()
    local inst, lines = harness()
    inst.NS.Settings = {}
    for _ = 1, 3 do inst.NS:OpenSettings() end
    assertEqual(inst.NS._openRetries, 3)
    inst.NS:OpenSettings()
    assertNil(inst.NS._openRetries, "the exhausted bound clears the counter once")
    assertTrue(lines[#lines]:find("Settings not yet registered", 1, true) ~= nil)
end)

test("OpenSettings prints the plain notice when the Settings API itself is absent", function()
    local inst, lines = harness()
    inst.mocks.Settings = false   -- masks the real global; falsy to the guard
    inst.NS:OpenSettings()
    assertEqual(#lines, 1)
    assertTrue(lines[1]:find("Settings not yet registered", 1, true) ~= nil)
    assertNil(inst.NS._openRetries, "no retry is counted when there is nothing to retry into")
end)

test("OpenSettings' deferred retry re-enters the same function", function()
    local inst, _, opened = harness()
    local main = inst.NS.Settings.main
    inst.NS.Settings = {}
    inst.NS:OpenSettings()
    inst.NS.Settings = { main = main }   -- the layer registers between attempts
    inst.mocks.__flushTimers()
    assertEqual(#opened, 1, "the armed timer must call OpenSettings again")
    assertNil(inst.NS._openRetries)
end)
