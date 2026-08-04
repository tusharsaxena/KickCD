-- tests/test_icongrid_glowgate.lua — IconGrid:RefreshAllGlows' gate cache.
--
-- RefreshAllGlows fires on every UNIT_SPELLCAST_* transition, and a boss
-- chaining short casts used to re-push the glow decision through every icon
-- on each one. The per-instance cache of the two booleans the trigger
-- predicates branch on is what stops that, and three of its rules are easy
-- to lose in a tidy-up:
--
--   * an UNMOVED gate must skip the per-icon loop entirely;
--   * a SECRET interruptibility reading must DEFEAT the cache — the flip
--     cannot be compared from Lua, so iteration re-runs every time
--     (correctness over efficiency for a rare transition);
--   * the debug line is deduped on the printed LABEL, which is the only
--     thing keeping that deliberate bypass from logging once per cast.
--
-- The tri-state labels are deliberately distinct: false (hostile cast, not
-- interruptible) is not nil (no hostile cast at all).
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

--- A grid instance carrying `n` fake icons that only count their UpdateGlow
--- calls — the loop's observable effect.
local function makeInstance(n)
    local counts = { glow = 0 }
    local ordered = {}
    for i = 1, n do
        ordered[i] = { _lastState = nil,
                       UpdateGlow = function() counts.glow = counts.glow + 1 end }
    end
    return { unit = "target", ordered = ordered }, counts
end

--- Point the cast APIs at a hostile unit whose cast reports `nint` in the
--- notInterruptible position. `nint = nil` with casting = false means no cast.
local function setCast(mocks, casting, nint)
    mocks.UnitExists    = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        if not casting then return nil end
        return "Chaos Bolt", nil, nil, nil, nil, nil, nil, nint
    end
    mocks.UnitChannelInfo = function() return nil end
end

test("RefreshAllGlows pushes the glow decision through every icon", function()
    local loaded = T.load(true, true)
    local IconGrid = loaded.NS:GetModule("IconGrid")
    local inst, counts = makeInstance(3)
    setCast(loaded.mocks, true, false)
    IconGrid:RefreshAllGlows(inst)
    assertEqual(counts.glow, 3, "one UpdateGlow per active icon")
end)

test("an unmoved gate short-circuits the per-icon loop", function()
    local loaded = T.load(true, true)
    local IconGrid = loaded.NS:GetModule("IconGrid")
    local inst, counts = makeInstance(3)
    setCast(loaded.mocks, true, false)
    IconGrid:RefreshAllGlows(inst)
    IconGrid:RefreshAllGlows(inst)
    IconGrid:RefreshAllGlows(inst)
    assertEqual(counts.glow, 3, "repeat events on an identical gate must not re-iterate")
end)

test("an interruptibility flip moves the gate and re-iterates", function()
    local loaded = T.load(true, true)
    local IconGrid = loaded.NS:GetModule("IconGrid")
    local inst, counts = makeInstance(2)
    setCast(loaded.mocks, true, false)
    IconGrid:RefreshAllGlows(inst)
    setCast(loaded.mocks, true, true)   -- now uninterruptible
    IconGrid:RefreshAllGlows(inst)
    assertEqual(counts.glow, 4, "a flip must push the new decision through")
end)

test("cast start and cast stop each move the gate", function()
    local loaded = T.load(true, true)
    local IconGrid = loaded.NS:GetModule("IconGrid")
    local inst, counts = makeInstance(1)
    setCast(loaded.mocks, false, nil)
    IconGrid:RefreshAllGlows(inst)      -- no cast
    setCast(loaded.mocks, true, false)
    IconGrid:RefreshAllGlows(inst)      -- cast start
    setCast(loaded.mocks, false, nil)
    IconGrid:RefreshAllGlows(inst)      -- cast stop
    assertEqual(counts.glow, 3, "each transition re-pushes")
end)

test("the gate cache is per-instance, so target and focus don't clobber", function()
    local loaded = T.load(true, true)
    local IconGrid = loaded.NS:GetModule("IconGrid")
    local a, ca = makeInstance(1)
    local b, cb = makeInstance(1)
    b.unit = "focus"
    setCast(loaded.mocks, true, false)
    IconGrid:RefreshAllGlows(a)
    IconGrid:RefreshAllGlows(b)
    assertEqual(ca.glow, 1)
    assertEqual(cb.glow, 1, "the second instance must not read the first's cache")
end)

test("a SECRET interruptibility reading defeats the short-circuit", function()
    -- While the flag is secret-tainted the equality compare is impossible, so
    -- the cache is deliberately bypassed and every event re-iterates.
    local loaded = T.load(true, true)
    local IconGrid = loaded.NS:GetModule("IconGrid")
    local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
    local prev = loaded.mocks.issecretvalue
    loaded.mocks.issecretvalue = function(v) return rawequal(v, SECRET) end
    local inst, counts = makeInstance(2)
    setCast(loaded.mocks, true, SECRET)
    IconGrid:RefreshAllGlows(inst)
    IconGrid:RefreshAllGlows(inst)
    IconGrid:RefreshAllGlows(inst)
    loaded.mocks.issecretvalue = prev
    assertEqual(counts.glow, 6, "a secret gate must re-run iteration every call")
end)

test("the debug line dedups on the printed label", function()
    -- The secret bypass reaches the debug block on every cast event; without
    -- the dedup a boss would log an identical line per cast.
    local loaded = T.load(true, true)
    local IconGrid = loaded.NS:GetModule("IconGrid")
    local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
    local prev = loaded.mocks.issecretvalue
    loaded.mocks.issecretvalue = function(v) return rawequal(v, SECRET) end
    local inst = makeInstance(1)
    setCast(loaded.mocks, true, SECRET)
    loaded.NS.State.debug = true
    loaded.NS.DebugLog:Clear()
    local before = loaded.NS.DebugLog:BufferSize()
    IconGrid:RefreshAllGlows(inst)
    IconGrid:RefreshAllGlows(inst)
    IconGrid:RefreshAllGlows(inst)
    local logged = loaded.NS.DebugLog:BufferSize() - before
    local line = loaded.NS.DebugLog:LastLine()
    loaded.NS.State.debug = false
    loaded.mocks.issecretvalue = prev
    assertEqual(logged, 1, "three identical gates must log once")
    assertTrue(line:find("secret (combat-tainted)", 1, true) ~= nil,
        "the secret state gets its own label; got: " .. tostring(line))
end)

test("each gate state gets its own debug label", function()
    -- The four labels are the diagnostic; collapsing "secret"/nil into "on"
    -- would send a reader chasing the wrong thing.
    local loaded = T.load(true, true)
    local IconGrid = loaded.NS:GetModule("IconGrid")
    local inst = makeInstance(1)
    loaded.NS.State.debug = true

    local function labelFor(casting, nint)
        setCast(loaded.mocks, casting, nint)
        loaded.NS.DebugLog:Clear()
        IconGrid:RefreshAllGlows(inst)
        return loaded.NS.DebugLog:LastLine()
    end

    assertTrue(labelFor(true, false):find("interruptible on", 1, true) ~= nil,
        "an interruptible cast reads 'on'")
    assertTrue(labelFor(true, true):find("interruptible off", 1, true) ~= nil,
        "an uninterruptible cast reads 'off'")
    assertTrue(labelFor(false, nil):find("none (no hostile cast)", 1, true) ~= nil,
        "no cast is not the same as 'off'")
    loaded.NS.State.debug = false
end)
