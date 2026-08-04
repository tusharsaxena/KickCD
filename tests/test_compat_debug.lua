-- tests/test_compat_debug.lua — characterization of `Compat.DebugInterrupt`,
-- the `/kcd debug interrupt` dump.
--
-- The dump exists to be pasted into a bug report, so its exact shape IS the
-- contract: the position numbering (1..9 for casting, 1..8 for channel — the
-- channel signature is one position shorter), the column widths in the
-- describe line, and above all the secret-taint discipline, where every value
-- pulled from a Unit* API is rendered as "<secret>" rather than reaching
-- tostring/format. Nothing pinned this before; these cases were written to
-- make the CCN refactor of the function verifiable.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Sentinel the fake client hands back as a secret-tainted value.
local SECRET = setmetatable({}, { __tostring = function() error("tostring on a secret") end })

--- Load an isolated instance, let the caller stage the client on it, then run
--- DebugInterrupt and return the chat lines with the [KCD] prefix stripped so
--- the assertions read exactly as the dump does.
local function dump(stage, unit)
    local inst = T.load(true)
    inst.mocks.UnitExists = function() return true end
    inst.mocks.UnitName = function() return "Boss" end
    inst.mocks.UnitCanAttack = function() return true end
    inst.mocks.issecretvalue = function(v) return v == SECRET end
    if stage then stage(inst.mocks) end

    local lines = {}
    inst.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }
    inst.NS.Compat.DebugInterrupt(unit)

    local prefix = inst.NS.PREFIX .. " "
    for i, line in ipairs(lines) do
        lines[i] = (tostring(line):gsub("^" .. prefix:gsub("[%%%|%[%]%(%)%.%+%-%*%?%^%$]", "%%%0"), ""))
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

test("DebugInterrupt bails with the unit name when the unit does not exist", function()
    local lines = dump(function(mocks) mocks.UnitExists = function() return false end end, "focus")
    assertEqual(#lines, 1)
    assertEqual(lines[1], "DebugInterrupt: unit 'focus' does not exist")
end)

test("DebugInterrupt defaults the unit to target", function()
    local lines = dump(function(mocks) mocks.UnitExists = function() return false end end, nil)
    assertEqual(lines[1], "DebugInterrupt: unit 'target' does not exist")
end)

test("DebugInterrupt's header quotes the unit name and reports canAttack", function()
    local lines = dump()
    assertEqual(lines[1], 'DebugInterrupt: unit=target name="Boss" canAttack=true')
end)

test("DebugInterrupt renders a secret-tainted unit name as <secret>", function()
    local lines = dump(function(mocks) mocks.UnitName = function() return SECRET end end)
    assertEqual(lines[1], "DebugInterrupt: unit=target name=<secret> canAttack=true")
end)

test("DebugInterrupt reports 'not casting' / 'not channeling' when nothing is cast", function()
    local lines = dump()
    assertTrue(indexOf(lines, "UnitCastingInfo: not casting") ~= nil)
    assertTrue(indexOf(lines, "UnitChannelInfo: not channeling") ~= nil)
end)

test("DebugInterrupt dumps all nine UnitCastingInfo positions, in order", function()
    local lines = dump(function(mocks)
        mocks.UnitCastingInfo = function()
            return "Fireball", "Fireball", 12345, 1000, 3000, false, "cast-1", true, 133
        end
    end)
    local at = indexOf(lines, "UnitCastingInfo positions")
    assertTrue(at ~= nil, "the positions header must be printed")
    assertEqual(lines[at + 1], '  1 name               type=string   isSecret=false value="Fireball"')
    assertEqual(lines[at + 2], '  2 displayName        type=string   isSecret=false value="Fireball"')
    assertEqual(lines[at + 3], "  3 texture            type=number   isSecret=false value=12345")
    assertEqual(lines[at + 4], "  4 startTimeMS        type=number   isSecret=false value=1000")
    assertEqual(lines[at + 5], "  5 endTimeMS          type=number   isSecret=false value=3000")
    assertEqual(lines[at + 6], "  6 isTradeSkill       type=boolean  isSecret=false value=false")
    assertEqual(lines[at + 7], '  7 castID             type=string   isSecret=false value="cast-1"')
    assertEqual(lines[at + 8], "  8 notInterruptible   type=boolean  isSecret=false value=true")
    assertEqual(lines[at + 9], "  9 spellID            type=number   isSecret=false value=133")
end)

test("DebugInterrupt dumps eight UnitChannelInfo positions — notInterruptible at 7", function()
    local lines = dump(function(mocks)
        mocks.UnitChannelInfo = function()
            return "Drain", "Drain", 4242, 1000, 3000, false, false, 689
        end
    end)
    local at = indexOf(lines, "UnitChannelInfo positions")
    assertTrue(at ~= nil, "the positions header must be printed")
    assertEqual(lines[at + 1], '  1 name               type=string   isSecret=false value="Drain"')
    assertEqual(lines[at + 6], "  6 isTradeSkill       type=boolean  isSecret=false value=false")
    assertEqual(lines[at + 7], "  7 notInterruptible   type=boolean  isSecret=false value=false")
    assertEqual(lines[at + 8], "  8 spellID            type=number   isSecret=false value=689")
    assertTrue(lines[at + 9]:match("^  9 ") == nil, "the channel dump stops at position 8")
end)

test("DebugInterrupt renders a secret notInterruptible without touching tostring", function()
    local lines = dump(function(mocks)
        mocks.UnitCastingInfo = function()
            return "Fireball", "Fireball", 12345, 1000, 3000, false, "cast-1", SECRET, 133
        end
    end)
    local at = indexOf(lines, "UnitCastingInfo positions")
    assertEqual(lines[at + 8], "  8 notInterruptible   type=table    isSecret=true  value=<secret>")
end)

test("DebugInterrupt renders a nil position as the literal nil", function()
    local lines = dump(function(mocks)
        mocks.UnitCastingInfo = function()
            return "Fireball", nil, nil, 1000, 3000, nil, nil, nil, nil
        end
    end)
    local at = indexOf(lines, "UnitCastingInfo positions")
    assertEqual(lines[at + 2], "  2 displayName        type=nil      isSecret=false value=nil")
    assertEqual(lines[at + 9], "  9 spellID            type=nil      isSecret=false value=nil")
end)

test("DebugInterrupt skips the casting block entirely when the API is absent", function()
    local lines = dump(function(mocks)
        mocks.UnitCastingInfo = false   -- masks the real global; `false` is falsy to the guard
    end)
    assertTrue(indexOf(lines, "UnitCastingInfo: not casting") == nil)
    assertTrue(indexOf(lines, "UnitCastingInfo positions") == nil)
    assertTrue(indexOf(lines, "UnitChannelInfo: not channeling") ~= nil)
end)

test("DebugInterrupt closes with the addon's own visibility and glow decisions", function()
    local lines = dump()
    assertEqual(lines[#lines - 3], "State.IsHostileUnitCasting(target) = false")
    assertEqual(lines[#lines - 2], "addon visibility mode = target_casting_interruptible")
    assertTrue(lines[#lines - 1]:match("^primary glow trigger   = ") ~= nil)
    assertTrue(lines[#lines]:match("^secondary glow trigger = ") ~= nil)
end)
