-- tests/test_reports.lua — the report verbs on the console's report seam (AD-79-KC, LibKa0s#79).
--
-- debug-logging-§15 and slash-commands-§4's "Chat or the console" (owner ruling of 2026-11-08): a
-- REPORT, a multi-line read-out the player asks for by name, is written to the debug console through
-- `D:Report` whatever the logging flag reads, the console is revealed, and chat gets exactly ONE
-- pointer line. A usage or refusal line inside a report verb stays in chat and writes nothing to the
-- console. Without LibKa0s the stub streams the report to chat with no pointer.
--
-- KickCD's report verbs: `/kcd spells list`, and the `/kcd debug spells|castbar|interrupt|events`
-- dumps. `/kcd debug window`, `on`, `off` and `toggle` are acknowledgments, not reports; `/kcd list`
-- is the reserved schema list, which the ruling keeps in chat; `/kcd diagnostics` and `/kcd perf`
-- write their reports through their own library helpers. A one-line answer (`no rejected events`,
-- `no spells tracked for ...`, `no target` from a unit dump) is a short answer and stays in chat.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local POINTER = "lines written to the debug console. Use Copy to share it."

--- A fresh enabled instance with the console hidden and logging off.
local function fresh(mutate, opts)
    local inst = T.load(true, true, mutate, opts)
    inst.mocks.__flushTimers()
    local D = inst.NS.DebugLog
    if D:IsShown() then D:Hide() end
    D:SetEnabled(false)
    return inst
end

--- Run a slash line on `inst`: the chat lines it printed and the console lines it added.
local function run(inst, input)
    local NS, chat = inst.NS, {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end
    local before = NS.DebugLog.buffer and #NS.DebugLog.buffer or 0
    local ok, err = pcall(NS.OnSlashCommand, NS, input)
    frame.AddMessage = orig
    if not ok then error(err, 0) end
    local added = {}
    for i = before + 1, NS.DebugLog.buffer and #NS.DebugLog.buffer or 0 do
        added[#added + 1] = NS.DebugLog.buffer[i]
    end
    return chat, added
end

local function joined(lines) return table.concat(lines, "\n") end

--- The shared shape of one report: the header and body are in the console, the flag is still
--- off, the console is shown, and chat holds exactly the pointer line naming `title`.
local function assertReport(inst, input, title, bodyText)
    local NS = inst.NS
    local chat, added = run(inst, input)
    -- red under: printing the report line by line through p(self, ...) (the pre-adoption form)
    assertEqual(#chat, 1, input .. ": exactly one chat line, got: " .. joined(chat))
    assertTrue(chat[1]:find(title .. ": " .. #added .. " " .. POINTER, 1, true) ~= nil,
        input .. ": the pointer names the report and its line count, got: " .. chat[1])
    -- red under: writing the body through NS.Debug (gated), which lands nothing with logging off
    assertTrue(#added >= 2, input .. ": header and body must land with logging off, got: " .. joined(added))
    assertTrue(added[1]:find("/kcd " .. title, 1, true) ~= nil, input .. ": header, got: " .. tostring(added[1]))
    assertTrue(joined(added):find(bodyText, 1, true) ~= nil,
        input .. ": body must carry '" .. bodyText .. "', got: " .. joined(added))
    assertEqual(NS.DebugLog:IsEnabled(), false, input .. ": a report must leave logging off")
    assertEqual(NS.DebugLog:IsShown(), true, input .. ": a report reveals a hidden console")
end

--- A refusal: its line in chat, nothing in the console, the console left hidden.
local function assertRefusal(inst, input, refusalText)
    local chat, added = run(inst, input)
    assertEqual(#added, 0, input .. ": a refusal writes no report, got: " .. joined(added))
    assertTrue(joined(chat):find(refusalText, 1, true) ~= nil, input .. ": refusal in chat, got: " .. joined(chat))
    assertTrue(joined(chat):find(POINTER, 1, true) == nil, input .. ": a refusal prints no pointer")
    assertEqual(inst.NS.DebugLog:IsShown(), false, input .. ": a refusal does not reveal the console")
end

local function markBad(m) m.__badEvents = { SPELL_UPDATE_USABLE = true } end

-- ── each report verb ─────────────────────────────────────────────────────────────────────────

test("/kcd spells list is a report: console, ungated, one chat pointer", function()
    assertReport(fresh(), "spells list", "spells list", "spells for ")
end)

test("/kcd debug spells is a report: console, ungated, one chat pointer", function()
    assertReport(fresh(), "debug spells", "debug spells", "Cooldowns: class=")
end)

--- A fresh instance whose tracked units exist, so the unit dumps run their real body, not the bail.
local function withUnits()
    local inst = fresh()
    inst.mocks.UnitExists = function() return true end
    inst.mocks.UnitName = function() return "Boss" end
    inst.mocks.UnitCanAttack = function() return true end
    return inst
end

test("/kcd debug castbar is a report, on target or the named unit", function()
    -- re-pinned (AD-79-KC review): the body is the real dump of an existing unit, not the no-unit bail
    assertReport(withUnits(), "debug castbar", "debug castbar", "  target = Boss")
    assertReport(withUnits(), "debug castbar focus", "debug castbar", "  focus = Boss")
end)

test("/kcd debug interrupt is a report, on target or the named unit", function()
    -- re-pinned (AD-79-KC review): the body is the real dump of an existing unit, not the no-unit bail
    assertReport(withUnits(), "debug interrupt", "debug interrupt", 'unit=target name="Boss"')
    assertReport(withUnits(), "debug interrupt FOCUS", "debug interrupt", 'unit=focus name="Boss"')
end)

test("/kcd debug events is a report when the client refused a name", function()
    assertReport(fresh(markBad), "debug events", "debug events", "rejected event: SPELL_UPDATE_USABLE")
end)

-- ── short answers and refusals stay in chat ──────────────────────────────────────────────────

test("/kcd debug events answers an empty list in one chat line and writes nothing", function()
    -- red under: wrapping the empty answer in the report too (one line is a short answer)
    local inst = fresh()
    local chat, added = run(inst, "debug events")
    assertEqual(#added, 0, "got: " .. joined(added))
    assertEqual(#chat, 1)
    assertTrue(chat[1]:find("no rejected events", 1, true) ~= nil, chat[1])
    assertEqual(inst.NS.DebugLog:IsShown(), false)
end)

test("/kcd debug castbar|interrupt with no such unit answer in one chat line and write nothing", function()
    -- red under: running the dump's one-line bail through the report (header, pointer, console shown)
    for _, case in ipairs({
        { "debug castbar", "no target" }, { "debug castbar focus", "no focus" },
        { "debug interrupt", "no target" }, { "debug interrupt focus", "no focus" },
    }) do
        local inst = fresh()
        inst.mocks.UnitExists = function() return false end
        local chat, added = run(inst, case[1])
        assertEqual(#added, 0, case[1] .. ": nothing in the console, got: " .. joined(added))
        assertEqual(#chat, 1, case[1] .. ": one chat line, got: " .. joined(chat))
        assertTrue(chat[1]:find(case[2], 1, true) ~= nil, case[1] .. ": got: " .. chat[1])
        assertTrue(chat[1]:find(POINTER, 1, true) == nil, case[1] .. ": no pointer")
        assertEqual(inst.NS.DebugLog:IsShown(), false, case[1] .. ": the console stays hidden")
    end
end)

test("a refused report verb writes nothing to the console and stays in chat", function()
    assertRefusal(fresh(), "debug castbar bogus", "unknown unit 'bogus', expected target or focus")
    assertRefusal(fresh(), "debug interrupt bogus", "unknown unit 'bogus', expected target or focus")
    assertRefusal(fresh(), "spells list WARRIOR nosuchspec", "Could not determine class+spec")
end)

-- ── without LibKa0s ──────────────────────────────────────────────────────────────────────────

test("without LibKa0s a report streams to chat with no pointer", function()
    local inst = T.load(true, true, markBad, { libFiles = {} })
    local chat = run(inst, "debug events")
    local text = joined(chat)
    assertTrue(text:find("rejected event: SPELL_UPDATE_USABLE", 1, true) ~= nil, "got: " .. text)
    assertTrue(text:find(POINTER, 1, true) == nil, "the stub prints no pointer: " .. text)
end)
