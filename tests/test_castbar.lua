-- tests/test_castbar.lua — Castbar pure helpers. Frame geometry itself is
-- smoke-tested in-game (the headless mock's frames are no-ops); here we
-- assert the scale-aware auto-size math so a master scale != 1 can't
-- regress the "Auto-size to icon grid" bar width again.
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local Castbar = NS:GetModule("Castbar", true)

test("Castbar exposes the pure AutoSizeLong helper", function()
    assertTrue(type(Castbar.AutoSizeLong) == "function",
        "AutoSizeLong must be published for unit testing")
end)

test("AutoSizeLong copies the grid extent verbatim when scales match", function()
    -- grid and bar both at effective scale 1 -> on-screen extents already agree
    assertEqual(Castbar.AutoSizeLong(250, 1, 1, 99), 250)
end)

test("AutoSizeLong shrinks the bar when the grid is scaled down (master scale < 1)", function()
    -- grid rendered at 250 * 0.6 = 150 px on screen; the bar (scale 1) must be
    -- set to 150 in its own coords to match, not the raw 250.
    assertEqual(Castbar.AutoSizeLong(250, 0.6, 1, 99), 150)
end)

test("AutoSizeLong grows the bar when the grid is scaled up (master scale > 1)", function()
    assertEqual(Castbar.AutoSizeLong(250, 1.5, 1, 99), 375)
end)

test("AutoSizeLong honors the bar's own effective scale", function()
    -- grid on-screen = 200 * 1.0; bar at scale 2 needs only 100 of its own coords.
    assertEqual(Castbar.AutoSizeLong(200, 1.0, 2.0, 99), 100)
end)

test("AutoSizeLong returns the fallback for a zero/nil grid extent", function()
    assertEqual(Castbar.AutoSizeLong(0, 1, 1, 42), 42)
    assertEqual(Castbar.AutoSizeLong(nil, 1, 1, 42), 42)
end)

test("AutoSizeLong treats a zero/nil scale as 1 (never divides by zero)", function()
    assertEqual(Castbar.AutoSizeLong(250, nil, nil, 99), 250)
    assertEqual(Castbar.AutoSizeLong(250, 1, 0, 99), 250)
end)

-- ── Empowered casts (UNIT_SPELLCAST_EMPOWER_*) ──────────────────────────────

--- Fire `event` at every created frame registered for it on `unit`, the way the
--- client dispatches a RegisterUnitEvent registration.
local function fireUnitEvent(mocks, event, unit)
    for _, f in ipairs(mocks.__frames) do
        if f.__events[event] == unit then f:_fire(event, unit) end
    end
end

test("UNIT_SPELLCAST_EMPOWER_START on target starts the bar and EMPOWER_STOP stops it", function()
    -- An Evoker's empowered cast reports through UnitChannelInfo and fires the
    -- EMPOWER family, not CHANNEL_START; an unregistered EMPOWER_START leaves
    -- the bar blank for a cast begun after targeting.
    local inst = T.load(true, true)
    local mocks, CB = inst.mocks, inst.NS:GetModule("Castbar")
    local p = inst.NS.db.profile
    p.locked, p.visibility, p.enabled = true, "always", true
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function()
        return "Fire Breath", "d", "tex", 1, 2, false, false, 357208
    end
    mocks.UnitChannelDuration = function()
        return {
            GetTotalDuration     = function() return 2 end,
            GetElapsedDuration   = function() return 0 end,
            GetRemainingDuration = function() return 2 end,
        }
    end
    local bar = CB:GetInstance("target")
    fireUnitEvent(mocks, "UNIT_SPELLCAST_EMPOWER_START", "target")
    assertTrue(bar.current ~= nil, "EMPOWER_START must start the target bar")
    assertTrue(bar.current.isChannel, "an empower reads through the channel shim")
    fireUnitEvent(mocks, "UNIT_SPELLCAST_EMPOWER_STOP", "target")
    assertTrue(bar.current == nil, "EMPOWER_STOP must stop the bar")
end)
