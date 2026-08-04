-- tests/test_castbar_debug.lua — characterization of `Castbar:DebugDump`, the
-- `/kcd debug castbar` dump (modules/Castbar_Debug.lua).
--
-- The dump is pasted into bug reports, so its printed shape IS the contract.
-- Two things in particular are load-bearing and invisible to every other suite:
-- the secret-taint discipline (notInterruptible / spellID / texture / name are
-- reported through type() and a boolean branch, never through tostring or
-- format), and the fact that the configured colors render through
-- NS.Util.Unpack — a positional read of the keyed storage shape would report
-- four zeroes and send the reader chasing a bug that does not exist. Nothing
-- pinned any of it before; these cases were written to make the CCN refactor of
-- the function verifiable.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Sentinel the fake client hands back as a secret-tainted value. tostring on it
-- raises, so any line that reaches it through tostring fails loudly.
local SECRET = setmetatable({}, { __tostring = function() error("tostring on a secret") end })

--- Load an isolated instance with an existing target, let the caller stage the
--- client and the cast record, then run DebugDump and return the chat lines
--- with the [KCD] prefix stripped so the assertions read as the dump does.
--- @param stage function|nil  (mocks, inst, NS) -> () applied before the dump
--- @param enable boolean|nil  run the enable cascade (builds the frame) when true
local function dump(stage, enable, unit)
    local loaded = T.load(true, enable ~= false)
    loaded.mocks.UnitExists = function() return true end
    loaded.mocks.issecretvalue = function(v) return v == SECRET end
    local Castbar = loaded.NS:GetModule("Castbar")
    local inst = Castbar:GetInstance("target")
    if stage then stage(loaded.mocks, inst, loaded.NS) end

    local lines = {}
    loaded.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }
    Castbar:DebugDump(unit)

    for i, line in ipairs(lines) do
        lines[i] = (tostring(line):gsub("^|cff%x+%[KCD%]|r ", ""))
    end
    return lines
end

--- Index of the first line equal to `want`, or nil.
local function indexOf(lines, want)
    for i, line in ipairs(lines) do
        if line == want then return i end
    end
    return nil
end

-- ── Unit header ─────────────────────────────────────────────────────────────

test("DebugDump opens with the resolved unit and bails when it does not exist", function()
    local lines = dump(function(mocks) mocks.UnitExists = function() return false end end)
    assertEqual(#lines, 2)
    assertEqual(lines[1], "castbar state (target)")
    assertEqual(lines[2], "  no target")
end)

test("DebugDump defaults the unit to target", function()
    local lines = dump(function(mocks) mocks.UnitExists = function() return false end end, true, nil)
    assertEqual(lines[1], "castbar state (target)")
end)

test("DebugDump's unit line reports name, isUnit and canAttack", function()
    local lines = dump()
    assertEqual(lines[2], "  target = Tester, isUnit=other, canAttack=true")
end)

test("DebugDump reports isUnit=self for the player's own unit", function()
    local lines = dump(function(mocks)
        mocks.UnitIsUnit = function() return true end
        mocks.UnitCanAttack = function() return false end
    end)
    assertEqual(lines[2], "  target = Tester, isUnit=self, canAttack=false")
end)

test("DebugDump falls back to '?' when the unit has no name", function()
    local lines = dump(function(mocks) mocks.UnitName = function() return nil end end)
    assertEqual(lines[2], "  target = ?, isUnit=other, canAttack=true")
end)

-- ── The no-cast branch ──────────────────────────────────────────────────────

test("DebugDump stops after the no-cast line when nothing is tracked", function()
    local lines = dump(function(mocks)
        mocks.UnitCastingInfo = false
        mocks.UnitChannelInfo = false
    end)
    assertEqual(#lines, 3)
    assertEqual(lines[3], "  no active cast tracked (current = nil)")
end)

test("DebugDump flags a missed event when Compat still sees a cast", function()
    -- The whole diagnostic value of that branch: `current` is nil but the API
    -- says a cast is in progress, so an event was dropped somewhere.
    local lines = dump(function(mocks)
        mocks.UnitCastingInfo = function()
            return "Fireball", "Fireball", 12345, 1000, 3000, false, "cast-1", false, 133
        end
    end)
    assertEqual(lines[3], "  no active cast tracked (current = nil)")
    assertEqual(lines[4], "  but Compat.GetCastingInfo returned a record — debug a missed event?")
    assertEqual(#lines, 4)
end)

-- ── The tracked cast record ─────────────────────────────────────────────────

--- Stage a tracked cast record with the given notInterruptible value.
local function withCast(nint, extra)
    return function(_mocks, inst)
        local rec = { isChannel = false, notInterruptible = nint,
                      duration = nil, texture = 12345, spellID = 133, name = "Fireball" }
        for k, v in pairs(extra or {}) do rec[k] = v end
        inst.current = rec
    end
end

test("DebugDump reports a plain boolean notInterruptible by value", function()
    local lines = dump(withCast(true))
    assertEqual(lines[3], "  current.isChannel = false")
    assertEqual(lines[4], "  current.notInterruptible: type=boolean, isSecret=false")
    assertEqual(lines[5], "    plain value = true")
end)

test("DebugDump reports a nil notInterruptible as interruptible", function()
    local lines = dump(withCast(nil))
    assertEqual(lines[4], "  current.notInterruptible: type=nil, isSecret=false")
    assertEqual(lines[5], "    plain nil (treated as interruptible)")
end)

test("DebugDump reports a secret notInterruptible without touching tostring", function()
    local lines = dump(withCast(SECRET))
    assertEqual(lines[4], "  current.notInterruptible: type=table, isSecret=true")
    assertEqual(lines[5], "    secret-tainted; visual state determined via "
        .. "C_CurveUtil.EvaluateColorValueFromBoolean")
end)

test("DebugDump prints no state line for a secret value with no curve evaluator", function()
    local lines = dump(function(mocks, inst)
        mocks.C_CurveUtil = false
        withCast(SECRET)(mocks, inst)
    end)
    assertEqual(lines[4], "  current.notInterruptible: type=table, isSecret=true")
    assertEqual(lines[5], "  duration: nil")
end)

test("DebugDump reports the channel flag and the record's field TYPES only", function()
    local lines = dump(withCast(false, { isChannel = true, duration = { } }))
    assertEqual(lines[3], "  current.isChannel = true")
    assertEqual(lines[6], "  duration: present")
    assertEqual(lines[7], "  texture:  type=number")
    assertEqual(lines[8], "  spellID:  type=number")
    assertEqual(lines[9], "  name:     type=string")
end)

test("DebugDump reports secret record fields by type, never by value", function()
    local lines = dump(withCast(false, { texture = SECRET, spellID = SECRET, name = SECRET }))
    assertEqual(lines[7], "  texture:  type=table")
    assertEqual(lines[8], "  spellID:  type=table")
    assertEqual(lines[9], "  name:     type=table")
end)

-- ── Configured colors ───────────────────────────────────────────────────────

test("DebugDump renders the configured per-state colors from the live profile", function()
    local lines = dump(withCast(true))
    local at = indexOf(lines, "  configured colors")
    assertTrue(at ~= nil, "the configured-colors header must be printed")
    assertEqual(lines[at + 1], "    interruptible   bar={1.00, 0.85, 0.05, 1.00}"
        .. " border={0.00, 0.00, 0.00, 1.00} bg={0.00, 0.00, 0.00, 0.50}")
    assertEqual(lines[at + 2], "    uninterruptible bar={0.85, 0.10, 0.10, 1.00}"
        .. " border={0.00, 0.00, 0.00, 1.00} bg={0.00, 0.00, 0.00, 0.50}")
end)

test("DebugDump reads colors through Util.Unpack, in the keyed storage shape", function()
    -- The keyed shape is what the color picker writes. A positional read finds
    -- nil on every channel here and reports the fallback, silently and only in
    -- game — so the dump would say the write did not land when it did.
    local lines = dump(function(mocks, inst, NS)
        NS.db.profile.units.target.castbar.interruptible.barColor =
            { r = 0.25, g = 0.5, b = 0.75, a = 0.5 }
        withCast(true)(mocks, inst)
    end)
    local at = indexOf(lines, "  configured colors")
    assertTrue(lines[at + 1]:find("bar={0.25, 0.50, 0.75, 0.50}", 1, true) ~= nil,
        "a keyed color must render its real channels: " .. lines[at + 1])
end)

test("DebugDump reports a missing color table as (missing)", function()
    local lines = dump(function(mocks, inst, NS)
        NS.db.profile.units.target.castbar.interruptible.barColor = nil
        withCast(true)(mocks, inst)
    end)
    local at = indexOf(lines, "  configured colors")
    assertTrue(lines[at + 1]:find("bar=(missing)", 1, true) ~= nil,
        "an absent color table must render as (missing): " .. lines[at + 1])
end)

-- ── Live widget colors ──────────────────────────────────────────────────────

test("DebugDump reports the colors live on the StatusBar widgets", function()
    local lines = dump(withCast(true))
    local at = indexOf(lines, "  live SetStatusBarColor values")
    assertTrue(at ~= nil, "the live-colors header must be printed")
    assertEqual(lines[at + 1], "    interruptible   = {1.00, 0.85, 0.05, 1.00}")
    assertEqual(lines[at + 2], "    uninterruptible = {0.85, 0.10, 0.10, 1.00}")
    assertEqual(#lines, at + 2, "the live colors are the last thing the dump prints")
end)

test("DebugDump says (no widget) before the frame has ever been built", function()
    local lines = dump(withCast(true), false)
    local at = indexOf(lines, "  live SetStatusBarColor values")
    assertEqual(lines[at + 1], "    interruptible   = (no widget)")
    assertEqual(lines[at + 2], "    uninterruptible = (no widget)")
end)
