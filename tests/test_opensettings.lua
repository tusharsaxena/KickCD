-- tests/test_opensettings.lua — characterization of `NS:OpenSettings`.
--
-- What this file guards changed with M4-01. It used to pin the `_openRetries`
-- lifecycle of a private open path: core/KickCD.lua read KickCD.Settings.main
-- off settings/Panel.lua's private registry, called Settings.OpenToCategory
-- itself, force-expanded the Blizzard category tree through SettingsPanel's
-- private API, and retried three times against the PLAYER_LOGIN race — every
-- line of it a second copy of LibKa0s-Options-1.0's O.OpenOptionsPanel, which
-- this addon also shipped and never called (KCD-A-09).
--
-- The registry and the retry are gone (registration is synchronous in OnEnable,
-- so there is nothing left to race), and what is left to pin is narrower and
-- more useful: the combat refusal is KickCD's because its notice is localized,
-- and EVERYTHING past the refusal is the library's.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

--- A fully-enabled instance with the chat frame captured. Enabled, because
--- OnEnable is where NS.CreateOptionsPanel() runs — an un-enabled instance has
--- no registered category and would pass the "it opened" case for the wrong
--- reason. Returns the instance, the captured chat lines, and the list of
--- category handles Settings.OpenToCategory was handed.
local function harness(mutate)
    local opened = {}
    local inst = T.load(true, true, function(mocks)
        mocks.Settings.OpenToCategory = function(id) opened[#opened + 1] = id end
        if mutate then mutate(mocks) end
    end)
    local lines = {}
    inst.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }
    return inst, lines, opened
end

test("OpenSettings refuses in combat", function()
    local inst, lines, opened = harness()
    inst.NS.State.inCombat = true
    inst.NS:OpenSettings()
    inst.NS.State.inCombat = false

    assertEqual(#opened, 0, "the protected category switch must not run in combat")
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

test("the combat refusal is KickCD's and never reaches the library", function()
    -- The gate lives here rather than being left to O.OpenOptionsPanel's own
    -- refusal for one reason: the library prints its shared English string and
    -- this addon's refusal is localized. So the host gate MUST short-circuit —
    -- reaching the library too would print the refusal twice, in two languages.
    local inst, lines = harness()
    local reached = 0
    local real = inst.NS.OpenOptionsPanel
    inst.NS.OpenOptionsPanel = function() reached = reached + 1; return real() end
    inst.NS.State.inCombat = true
    inst.NS:OpenSettings()
    inst.NS.State.inCombat = false
    assertEqual(reached, 0, "the library forwarder must not be reached under lockdown")
    assertEqual(#lines, 1, "exactly one refusal line")
end)

test("OpenSettings opens through the library forwarder, not a private copy", function()
    -- The whole of KCD-R-03/KCD-A-09 in one assertion: the forwarder at
    -- settings/OptionsSetup.lua has a caller, and the category handle the open
    -- receives is the one the LIBRARY registered — not one this addon parked on
    -- NS.Settings.main for itself.
    local inst, _, opened = harness()
    local reached = 0
    local real = inst.NS.OpenOptionsPanel
    inst.NS.OpenOptionsPanel = function() reached = reached + 1; return real() end
    inst.NS:OpenSettings()
    assertEqual(reached, 1, "OpenSettings must delegate to NS.OpenOptionsPanel")
    assertEqual(#opened, 1, "the library must have opened exactly one category")
    assertNil(inst.NS.Settings.main, "the private registry's `main` must be gone")
end)

test("OpenSettings prints the plain notice when the settings layer never loaded", function()
    local inst, lines, opened = harness()
    inst.NS.OpenOptionsPanel = nil
    inst.NS:OpenSettings()
    assertEqual(#opened, 0)
    assertEqual(#lines, 1)
    assertTrue(lines[1]:find("Settings not yet registered", 1, true) ~= nil)
end)

test("with LibKa0s absent the open says so instead of touching the category API", function()
    -- The degraded arm produced by a real load with an empty library file list,
    -- not by hand-stubbing the member under test (testing-§8): OptionsSetup's
    -- stub points NS.OpenOptionsPanel at the "settings panel is unavailable"
    -- printer, and OpenSettings reaches it like any other caller.
    local opened = {}
    local inst = T.load(true, true, function(mocks)
        mocks.Settings.OpenToCategory = function(id) opened[#opened + 1] = id end
    end, { libFiles = {} })
    local lines = {}
    inst.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }

    inst.NS:OpenSettings()
    assertEqual(#opened, 0, "there is no category to open")
    assertEqual(#lines, 1)
    assertTrue(lines[1]:lower():find("unavailable", 1, true) ~= nil,
        "the degraded stub must say the panel is unavailable; got: " .. tostring(lines[1]))
end)
