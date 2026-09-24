-- tests/test_events.lua
-- events-frames-taint-§1: one bad event name costs only itself (KICKCD-A-03).
--
-- Every AceEvent block this addon owns goes through NS.RegisterEventList
-- (core/CoreSetup.lua), which hands each row to LibKa0s-Core-1.0's
-- SafeRegisterEvent -- or to the one-rung stub bodies when the library is not
-- installed -- and records a refused name once in NS.State.rejectedEvents. The
-- player reaches that list through `/kcd debug events`, and the [Init] summary
-- counts it when it is not empty.
--
-- The retired name is modeled with the kit mock's `__badEvents`: the client
-- raises `Attempt to register unknown event "<NAME>"` on it. SPELL_UPDATE_USABLE
-- is the second row of Cooldowns' block, so a bare block would lose every row
-- after it and, because the raise escapes OnEnable, the load with it.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local BAD = "SPELL_UPDATE_USABLE"

local function markBad(m) m.__badEvents = { [BAD] = true } end

--- The AceEvent game events `target` holds, as a set.
local function eventsOf(inst, target)
    local set = {}
    for _, reg in ipairs(inst.mocks.__registrations()) do
        if reg.kind == "event" and reg.target == target then set[reg.event] = true end
    end
    return set
end

--- The block's later rows are registered and the bad name is recorded exactly once.
local function assertBlockSurvived(inst)
    local cd = inst.NS:GetModule("Cooldowns")
    local held = eventsOf(inst, cd)
    for _, ev in ipairs({ "SPELL_UPDATE_CHARGES", "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED" }) do
        assertTrue(held[ev], ev .. " must still be registered for Cooldowns after " .. BAD .. " was refused")
    end
    local rejected = inst.NS.State.rejectedEvents
    assertEqual(#rejected, 1, "exactly one rejected name")
    assertEqual(rejected[1], BAD)
end

--- Run a slash line on `inst` and return the chat lines it produced.
local function runVerb(inst, input)
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    local ok, err = pcall(inst.NS.OnSlashCommand, inst.NS, input)
    frame.AddMessage = orig
    if not ok then error(err, 0) end
    return lines
end

--- The [Init] summary line the debug console writes on enable.
local function initLine(inst)
    local NS = inst.NS
    local prev = NS.State.debug
    NS.DebugLog:Clear()
    NS.DebugLog:SetEnabled(true)
    local line = NS.DebugLog.buffer[2]
    NS.DebugLog:SetEnabled(false)
    NS.State.debug = prev
    return tostring(line)
end

test("one bad name does not stop the rest of Cooldowns' block", function()
    assertBlockSurvived(T.load(true, true, markBad))
end)

test("one bad name does not stop the block on a client without C_EventUtils (the pcall rung)", function()
    assertBlockSurvived(T.load(true, true, function(m)
        markBad(m)
        m.C_EventUtils = nil
    end))
end)

test("one bad name does not stop the block without LibKa0s (the stub bodies)", function()
    assertBlockSurvived(T.load(true, true, markBad, { libFiles = {} }))
end)

test("/kcd debug events names the rejected event", function()
    local inst = T.load(true, true, markBad)
    local out = table.concat(runVerb(inst, "debug events"), "\n")
    assertTrue(out:find(BAD, 1, true) ~= nil, "expected the rejected name, got: " .. out)
    assertTrue(out:find("no rejected events", 1, true) == nil, "must not claim an empty list: " .. out)

    local clean = table.concat(runVerb(T.load(true, true), "debug events"), "\n")
    assertTrue(clean:find("no rejected events", 1, true) ~= nil, "expected the empty answer, got: " .. clean)
end)

test("the [Init] line is unchanged when nothing was rejected", function()
    local clean = initLine(T.load(true, true))
    assertTrue(clean:find("[Init] KickCD v", 1, true) ~= nil, "expected the [Init] summary, got: " .. clean)
    assertTrue(clean:find("rejected", 1, true) == nil, "a clean session must not grow a clause: " .. clean)
    assertTrue(clean:find("profile '[^']*'$") ~= nil, "the line must still end at the profile: " .. clean)

    local dirty = initLine(T.load(true, true, markBad))
    assertTrue(dirty:find(", 1 rejected event(s)", 1, true) ~= nil,
        "a session with a refusal must count it, got: " .. dirty)
end)

test("a frame RegisterEvent honors __badEvents", function()
    local inst = T.load(false, false)
    local m = inst.mocks
    local f = m.CreateFrame("Frame")
    m.__badEvents = { [BAD] = true }
    local ok, err = pcall(f.RegisterEvent, f, BAD)
    assertTrue(not ok, "a raw frame must raise on a bad name")
    assertTrue(tostring(err):find('Attempt to register unknown event "' .. BAD .. '"', 1, true) ~= nil,
        "the client's message, got: " .. tostring(err))
    assertTrue(not f:IsEventRegistered(BAD), "nothing is recorded for a refused name")
    local okU = pcall(f.RegisterUnitEvent, f, BAD, "player")
    assertTrue(not okU, "RegisterUnitEvent must raise on a bad name too")
    -- Read at CALL time: clearing the table is heard.
    m.__badEvents = {}
    f:RegisterEvent(BAD)
    assertTrue(f:IsEventRegistered(BAD), "a name no longer marked bad registers")
end)
