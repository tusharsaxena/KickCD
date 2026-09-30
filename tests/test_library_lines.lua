-- tests/test_library_lines.lua — the debug lines LibKa0s writes itself, through
-- the sinks this addon passes its descriptors (LibKa0s v1.65.0, debug-logging-§4)
--
-- The library decides these refusals and edges, so only it can log them; what
-- the host owes is the sink. Each case pins that the library's line lands in
-- THIS addon's console, and that nothing writes it a second time: the host's own
-- `[State]` stand-down lines were deleted when the library took them over, and a
-- Slash refusal has no host line at all.
local T = _G.KICKCD_TEST
local test, assertTrue, assertEqual = T.test, T.assertTrue, T.assertEqual

--- A fresh instance whose account holds two stored profiles, logging on and
--- the console empty.
local function listening()
    local inst = T.load(true, true, function(m)
        m.KickCDDB = { global = { schemaVersion = 5 }, profiles = { Default = {}, Alt = {} } }
    end)
    inst.mocks.__flushTimers()
    inst.NS.DebugLog:SetEnabled(true)
    inst.NS.DebugLog:Clear()
    return inst, inst.NS
end

--- How many buffered lines contain `needle`, repeats included.
local function count(NS, needle)
    local n = 0
    for _, line in ipairs(NS.DebugLog.buffer) do
        if tostring(line):find(needle, 1, true) then n = n + 1 end
    end
    return n
end

--- Run `/kcd <input>` with chat swallowed.
local function slash(NS, input)
    local real = NS.Util.print
    NS.Util.print = function() end
    local ok, err = pcall(NS.OnSlashCommand, NS, input)
    NS.Util.print = real
    if not ok then error(err, 0) end
end

-- ── LibKa0s-Slash-1.0 (minor 18): the dispatcher's own refusals ───────────────

test("an unknown /kcd verb is one [Cmd] line from the library", function()
    -- red under: the `debug` field dropped from settings/Slash.lua's descriptor
    local _, NS = listening()
    slash(NS, "frobnicate")
    assertEqual(count(NS, "[Cmd] refused frobnicate: unknown verb"), 1)
    assertEqual(count(NS, "frobnicate"), 1, "no second line names the verb")
    NS.DebugLog:SetEnabled(false)
end)

test("a feature verb while disabled is the library's disabled-gate line, once", function()
    -- The refusal AbsorbTracker used to match out of the chat; here it is the
    -- library's line and the host writes none.
    -- red under: the `debug` field dropped from settings/Slash.lua's descriptor
    local _, NS = listening()
    NS.SetMasterEnabled(false)
    NS.DebugLog:Clear()
    slash(NS, "lock")
    assertEqual(count(NS, "[Cmd] refused lock: disabled"), 1)
    assertEqual(count(NS, "refused"), 1, "no host refusal line beside it")
    NS.SetMasterEnabled(true)
    NS.DebugLog:SetEnabled(false)
end)

test("a /kcd set the library cannot parse names the path and the guard", function()
    local _, NS = listening()
    slash(NS, "set locked banana")
    assertTrue(NS.DebugLog:FindLine("[Cmd] refused set locked: parse"), "the parse refusal is logged")
    assertEqual(count(NS, "refused"), 1, "one refusal line, not two")
    NS.DebugLog:SetEnabled(false)
end)

test("a profile switch in combat is the library's in-combat line", function()
    local inst, NS = listening()
    inst.mocks.InCombatLockdown = function() return true end
    slash(NS, "profile Alt")
    inst.mocks.InCombatLockdown = function() return false end
    assertEqual(count(NS, "[Cmd] refused profile Alt: in combat"), 1)
    assertEqual(NS.db:GetCurrentProfile(), "Default", "the switch did not happen")
    NS.DebugLog:SetEnabled(false)
end)

test("with logging off a Slash refusal writes nothing", function()
    -- The sink is the gated NS.Debug, so the library's line costs nothing off.
    local _, NS = listening()
    NS.DebugLog:SetEnabled(false)
    NS.DebugLog:Clear()
    slash(NS, "frobnicate")
    assertEqual(count(NS, "[Cmd]"), 0)
end)

-- ── LibKa0s-Lifecycle-1.0 (minor 3): the stand-down and stand-up edges ────────

test("the stand-down and stand-up edges are one [Lifecycle] line each, naming the hold", function()
    -- §8 diagnosis: a player who says "it stopped working" with the addon
    -- disabled is answered by this line and nothing else.
    -- red under: the `debug` field dropped from core/LifecycleSetup.lua's descriptor
    local _, NS = listening()
    NS.SetMasterEnabled(false)
    assertEqual(count(NS, "[Lifecycle] stood down: added disabled (holds: disabled)"), 1)
    NS.SetMasterEnabled(true)
    assertEqual(count(NS, "[Lifecycle] stood up: released disabled (holds: none)"), 1)
    assertEqual(count(NS, "stood down"), 1, "no host line repeats the stand-down edge")
    assertEqual(count(NS, "stood up"), 1, "no host line repeats the stand-up edge")
    assertEqual(count(NS, "[State]"), 0, "the host's retired [State] edge lines stay retired")
    NS.DebugLog:SetEnabled(false)
end)

test("a hold call that fires no edge writes no Lifecycle line", function()
    local _, NS = listening()
    NS.RefreshEnabledHold()
    NS.RefreshEnabledHold()
    assertEqual(count(NS, "[Lifecycle]"), 0, "an enabled addon re-reading its switch is no edge")
    NS.DebugLog:SetEnabled(false)
end)

-- ── LibKa0s-Launcher-1.0 (minor 5): state lines held for the first enable ─────

test("the launcher's registration lands the first time logging is turned on", function()
    -- Register runs at OnEnable with the session-only flag off, so through
    -- `debug` this line never rendered; the console's at-enable queue holds it.
    -- red under: the `debugAtEnable` field dropped from core/LauncherSetup.lua's descriptor
    local inst = T.load(true, true)
    local NS = inst.NS
    NS.DebugLog:Clear()
    NS.DebugLog:SetEnabled(true)
    assertEqual(count(NS, "[Launcher] registered"), 1)
    NS.DebugLog:SetEnabled(false)
    NS.DebugLog:SetEnabled(true)
    assertEqual(count(NS, "[Launcher] registered"), 1, "held once, not on every enable edge")
    NS.DebugLog:SetEnabled(false)
end)

test("a missing LibDBIcon is the launcher's own line at enable, and nothing else names it", function()
    -- The [Init] summary used to carry a `, missing <names>` clause for the
    -- broker libraries; the launcher's state line replaced it, so the fact is
    -- written once.
    local inst = T.load(true, true, function(m) m.__libs["LibDBIcon-1.0"] = nil end)
    local NS = inst.NS
    NS.DebugLog:Clear()
    NS.DebugLog:SetEnabled(true)
    assertEqual(count(NS, "[Launcher] LibDBIcon-1.0 absent; broker plugin only"), 1)
    assertEqual(count(NS, "LibDBIcon-1.0"), 1, "one line names the missing library")
    NS.DebugLog:SetEnabled(false)
end)
