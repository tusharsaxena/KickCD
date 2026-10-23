-- tests/test_compat_units.lua — core/Compat.lua's unit and cast readers (host contract H1).
--
-- The simulator's seam (KickCD#38) can only answer a client read that goes through NS.Compat and
-- is read off the table at CALL time. These cases pin both halves of that:
--
--   * the eight readers themselves: a passthrough with the client API present (every return,
--     nil holes included) and the documented absent value without it;
--   * every converted call site: with the NS.Compat.Unit* members swapped for fakes that report a
--     hostile caster on `target`, and the _G APIs deliberately left answering "nothing", a case
--     passes only if the call site went through Compat. A site that still reads _G sees no unit,
--     no cast and no hostility, and the case goes red.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

--- Fresh instance; the readers read _G at call time, so post-load mock edits take effect.
local function fresh(initDB, enable)
    local inst = T.load(initDB or false, enable or false)
    return inst.NS, inst.mocks
end

--- Point every raw unit API at "nothing": no unit, no cast, not attackable.
local function silenceClient(mocks)
    mocks.UnitExists          = function() return false end
    mocks.UnitCanAttack       = function() return false end
    mocks.UnitIsDead          = function() return false end
    mocks.UnitCastingInfo     = function() return nil end
    mocks.UnitChannelInfo     = function() return nil end
    mocks.UnitCastingDuration = function() return nil end
    mocks.UnitChannelDuration = function() return nil end
end

--- A duration stand-in whose methods answer plain numbers, the CastingDuration shape.
local function fakeDuration()
    return {
        GetTotalDuration     = function() return 2 end,
        GetElapsedDuration   = function() return 0.5 end,
        GetRemainingDuration = function() return 1.5 end,
        GetStartTime         = function() return 100 end,
        GetEndTime           = function() return 102 end,
    }
end

--- Swap the NS.Compat unit readers for fakes reporting a hostile caster on `target`.
--- `cast` = { notInterruptible = <flag>, channel = <bool> }.
local function swapHostileCaster(Compat, cast)
    local onTarget = function(unit) return unit == "target" end
    Compat.UnitExists    = onTarget
    Compat.UnitCanAttack = onTarget
    Compat.UnitIsDead    = function() return false end
    if cast.channel then
        Compat.UnitCastingInfo = function() return nil end
        Compat.UnitChannelInfo = function(unit)
            if unit ~= "target" then return nil end
            return "Fake Channel", "Fake", "tex", 1000, 3000, false, cast.notInterruptible, 4242
        end
    else
        Compat.UnitCastingInfo = function(unit)
            if unit ~= "target" then return nil end
            return "Fake Cast", "Fake", "tex", 1000, 3000, false, "castID", cast.notInterruptible, 4141
        end
        Compat.UnitChannelInfo = function() return nil end
    end
    Compat.UnitCastingDuration = function() return fakeDuration() end
    Compat.UnitChannelDuration = function() return fakeDuration() end
end

--- Every return of a call, with its count (table.pack is 5.2+; the client is 5.1).
local function pack(...) return { n = select("#", ...), ... } end

-- ── Passthrough with the API present ────────────────────────────────────────

local SINGLE = {
    { name = "UnitExists", value = true },
    { name = "UnitIsDead", value = true },
}

for _, case in ipairs(SINGLE) do
    test("Compat." .. case.name .. " passes the unit through and answers the API's value", function()
        local NS, mocks = fresh()
        local seen
        mocks[case.name] = function(...) seen = { n = select("#", ...), ... }; return case.value end
        assertEqual(NS.Compat[case.name]("focus"), case.value)
        assertEqual(seen.n, 1); assertEqual(seen[1], "focus")
    end)
end

test("Compat.UnitCanAttack asks the client with the player as the first argument", function()
    local NS, mocks = fresh()
    local seen
    mocks.UnitCanAttack = function(...) seen = { n = select("#", ...), ... }; return false end
    assertEqual(NS.Compat.UnitCanAttack("target"), false)
    assertEqual(seen.n, 2); assertEqual(seen[1], "player"); assertEqual(seen[2], "target")
end)

local MULTI = { "UnitCastingInfo", "UnitChannelInfo", "UnitCastingDuration", "UnitChannelDuration" }

for _, name in ipairs(MULTI) do
    test("Compat." .. name .. " returns every value, nil holes included", function()
        local NS, mocks = fresh()
        local seen
        mocks[name] = function(...)
            seen = { n = select("#", ...), ... }
            return "a", nil, "c", nil, nil, 6, nil, false, 9
        end
        local r = pack(NS.Compat[name]("target"))
        assertEqual(seen.n, 1); assertEqual(seen[1], "target")
        assertEqual(r.n, 9, name .. " must keep every return, trailing values after nil holes too")
        assertEqual(r[1], "a"); assertNil(r[2]); assertEqual(r[3], "c")
        assertNil(r[4]); assertNil(r[5]); assertEqual(r[6], 6); assertNil(r[7])
        assertEqual(r[8], false); assertEqual(r[9], 9)
    end)
end

-- ── Absent values ───────────────────────────────────────────────────────────

local ABSENT = {
    { name = "UnitExists",          want = false },
    -- true preserves the old `if _G.UnitCanAttack and not ...` gate: an absent API never vetoed.
    { name = "UnitCanAttack",       want = true },
    { name = "UnitIsDead",          want = false },
    { name = "UnitCastingInfo",     want = nil },
    { name = "UnitChannelInfo",     want = nil },
    { name = "UnitCastingDuration", want = nil },
    { name = "UnitChannelDuration", want = nil },
}

for _, case in ipairs(ABSENT) do
    test("Compat." .. case.name .. " answers " .. tostring(case.want) .. " with the API absent", function()
        local NS, mocks = fresh()
        mocks[case.name] = nil
        assertEqual(NS.Compat[case.name]("target"), case.want)
    end)
end

test("Compat.NewDuration answers nil with C_DurationUtil absent", function()
    local NS, mocks = fresh()
    mocks.C_DurationUtil = nil
    assertNil(NS.Compat.NewDuration(100, 10))
    mocks.C_DurationUtil = {}
    assertNil(NS.Compat.NewDuration(100, 10), "a namespace without CreateDuration answers nil too")
end)

-- ── NewDuration ─────────────────────────────────────────────────────────────

test("Compat.NewDuration builds a duration and sets it from start and length", function()
    local NS, mocks = fresh()
    local obj = { calls = {} }
    function obj:SetTimeFromStart(start, dur) self.calls[#self.calls + 1] = { start, dur } end
    mocks.C_DurationUtil = { CreateDuration = function() return obj end }
    assertTrue(NS.Compat.NewDuration(100, 10) == obj)
    assertEqual(#obj.calls, 1)
    assertEqual(obj.calls[1][1], 100); assertEqual(obj.calls[1][2], 10)
end)

test("Compat.NewDuration answers nil, without raising, when the constructor raises", function()
    local NS, mocks = fresh()
    mocks.C_DurationUtil = { CreateDuration = function() error("boom") end }
    local ok, d = pcall(NS.Compat.NewDuration, 100, 10)
    assertTrue(ok, "NewDuration must not raise"); assertNil(d)
end)

test("Compat.NewDuration answers nil, without raising, when the setter raises", function()
    local NS, mocks = fresh()
    local obj = { SetTimeFromStart = function() error("boom") end }
    mocks.C_DurationUtil = { CreateDuration = function() return obj end }
    local ok, d = pcall(NS.Compat.NewDuration, 100, 10)
    assertTrue(ok, "NewDuration must not raise"); assertNil(d)
end)

test("Compat.NewDuration answers nil when the constructor yields nothing", function()
    local NS, mocks = fresh()
    mocks.C_DurationUtil = { CreateDuration = function() return nil end }
    assertNil(NS.Compat.NewDuration(100, 10))
end)

-- ── GetCastingInfo / GetChannelInfo read the members at call time ───────────

test("GetCastingInfo builds its record from the swapped NS.Compat members", function()
    local NS, mocks = fresh()
    silenceClient(mocks)
    swapHostileCaster(NS.Compat, { notInterruptible = false })
    local rec = NS.Compat.GetCastingInfo("target")
    assertTrue(rec ~= nil, "a swapped UnitCastingInfo must reach GetCastingInfo")
    assertEqual(rec.name, "Fake Cast"); assertEqual(rec.spellID, 4141)
    assertEqual(rec.notInterruptible, false, "a hostile (swapped UnitCanAttack) keeps the raw flag")
    assertFalse(rec.isChannel)
    assertEqual(rec.duration:GetTotalDuration(), 2, "the duration comes from the swapped member")
end)

test("GetCastingInfo falls through to the swapped channel members", function()
    local NS, mocks = fresh()
    silenceClient(mocks)
    swapHostileCaster(NS.Compat, { notInterruptible = true, channel = true })
    local rec = NS.Compat.GetCastingInfo("target")
    assertTrue(rec ~= nil, "a swapped UnitChannelInfo must reach GetChannelInfo")
    assertEqual(rec.name, "Fake Channel"); assertEqual(rec.spellID, 4242)
    assertEqual(rec.notInterruptible, true); assertTrue(rec.isChannel)
    assertEqual(rec.duration:GetRemainingDuration(), 1.5)
end)

test("GetCastingInfo forces uninterruptible through the swapped UnitCanAttack", function()
    local NS, mocks = fresh()
    mocks.UnitCanAttack = function() return true end
    swapHostileCaster(NS.Compat, { notInterruptible = false })
    NS.Compat.UnitCanAttack = function() return false end
    local rec = NS.Compat.GetCastingInfo("target")
    assertEqual(rec.notInterruptible, true, "a non-attackable unit (per the member) forces true")
end)

-- ── Converted call sites ────────────────────────────────────────────────────

test("State.IsHostileUnitCasting reads the unit through NS.Compat", function()
    local NS, mocks = fresh()
    silenceClient(mocks)
    swapHostileCaster(NS.Compat, { notInterruptible = false })
    assertTrue(NS.State.IsHostileUnitCasting("target"))
    swapHostileCaster(NS.Compat, { notInterruptible = false, channel = true })
    assertTrue(NS.State.IsHostileUnitCasting("target"), "the channel twin goes through Compat too")
    assertFalse(NS.State.IsHostileUnitCasting("focus"))
end)

test("State.ApplyInterruptibleAlpha feeds the swapped member's flag to SetAlphaFromBoolean", function()
    local NS, mocks = fresh()
    silenceClient(mocks)
    local calls = {}
    local frame = { SetAlphaFromBoolean = function(_, flag, a, b) calls[#calls + 1] = { flag, a, b } end }
    swapHostileCaster(NS.Compat, { notInterruptible = "castFlag" })
    assertTrue(NS.State.ApplyInterruptibleAlpha(frame, "target", 0.8))
    assertEqual(calls[1][1], "castFlag", "position 8 of the swapped UnitCastingInfo")
    assertEqual(calls[1][2], 0); assertEqual(calls[1][3], 0.8)
    swapHostileCaster(NS.Compat, { notInterruptible = "chanFlag", channel = true })
    assertTrue(NS.State.ApplyInterruptibleAlpha(frame, "target"))
    assertEqual(calls[2][1], "chanFlag", "position 7 of the swapped UnitChannelInfo")
end)

test("IconGrid.InstanceCasting reads the unit through NS.Compat", function()
    local NS, mocks = fresh(true)
    silenceClient(mocks)
    local IconGrid = NS:GetModule("IconGrid")
    swapHostileCaster(NS.Compat, { notInterruptible = false })
    assertTrue(IconGrid.InstanceCasting({ unit = "target" }))
    swapHostileCaster(NS.Compat, { notInterruptible = false, channel = true })
    assertTrue(IconGrid.InstanceCasting({ unit = "target" }), "the channel twin too")
end)

test("IconGrid's interruptible resolve reads positions 8 and 7 through NS.Compat", function()
    local NS, mocks = fresh(true, true)
    silenceClient(mocks)
    local IconGrid = NS:GetModule("IconGrid")
    local inst = { unit = "target", ordered = {} }
    swapHostileCaster(NS.Compat, { notInterruptible = false })
    IconGrid:RefreshAllGlows(inst)
    assertEqual(inst.lastGateCasting, true)
    assertEqual(inst.lastGateInterruptible, true, "cast position 8 = false reads as interruptible")
    swapHostileCaster(NS.Compat, { notInterruptible = true, channel = true })
    IconGrid:RefreshAllGlows(inst)
    assertEqual(inst.lastGateInterruptible, false, "channel position 7 = true reads as not interruptible")
end)

test("Castbar:Reevaluate starts the bar from the swapped NS.Compat members", function()
    local NS, mocks = fresh(true, true)
    silenceClient(mocks)
    local CB = NS:GetModule("Castbar")
    local p = NS.db.profile
    p.locked, p.visibility, p.enabled = true, "always", true
    local bar = CB:GetInstance("target")
    swapHostileCaster(NS.Compat, { notInterruptible = false })
    CB:Reevaluate(bar)
    assertTrue(bar.current ~= nil, "Reevaluate must see the unit and the cast through Compat")
    NS.Compat.UnitIsDead = function() return true end
    CB:Reevaluate(bar)
    assertTrue(bar.current == nil, "a dead unit (per the member) stops the bar")
end)
