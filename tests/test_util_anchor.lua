-- tests/test_util_anchor.lua — the half of core/Util.lua that test_util.lua
-- doesn't reach: anchor persistence, the throttle's edge cases, spec display
-- and ordering, and the chat printer.
--
-- The anchor pair is the reason the frame mock now models SetPoint/GetPoint
-- as real state. Anchors are the ONE piece of frame geometry that round-trips
-- through SavedVariables, so "we saved the position" and "we saved garbage"
-- have to be distinguishable — against a no-op stub they are not.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local inst  = T.load(true)
local NS    = inst.NS
local mocks = inst.mocks
local Util  = NS.Util

local function newFrame() return mocks.CreateFrame("Frame") end

-- ── SaveAnchor ──────────────────────────────────────────────────────────────

test("SaveAnchor snapshots a frame's first anchor point", function()
    local f = newFrame()
    f:SetPoint("TOPLEFT", mocks.UIParent, "BOTTOMRIGHT", 120, -40)
    local a = Util.SaveAnchor(f)
    assertEqual(a.point, "TOPLEFT")
    assertEqual(a.relativePoint, "BOTTOMRIGHT")
    assertEqual(a.x, 120)
    assertEqual(a.y, -40)
end)

test("SaveAnchor stores no frame reference, only serializable fields", function()
    -- The saved shape goes into SavedVariables; a frame reference in there
    -- would fail to serialize and take the whole profile with it.
    local f = newFrame()
    f:SetPoint("CENTER", mocks.UIParent, "CENTER", 0, 0)
    local a = Util.SaveAnchor(f)
    for k, v in pairs(a) do
        assertTrue(type(v) == "string" or type(v) == "number",
            "anchor field " .. k .. " must be a plain scalar, got " .. type(v))
    end
    assertNil(a.relativeTo)
end)

test("SaveAnchor falls back to a centered anchor for a nil frame", function()
    -- Called from drag handlers that can fire before the frame is built.
    local a = Util.SaveAnchor(nil)
    assertEqual(a.point, "CENTER")
    assertEqual(a.relativePoint, "CENTER")
    assertEqual(a.x, 0)
    assertEqual(a.y, 0)
end)

test("SaveAnchor falls back to centered for a frame with no points set", function()
    -- A freshly created frame has never been positioned; GetPoint returns nil
    -- and every field has to default rather than propagate the nil.
    local a = Util.SaveAnchor(newFrame())
    assertEqual(a.point, "CENTER")
    assertEqual(a.x, 0)
    assertEqual(a.y, 0)
end)

test("SaveAnchor reads point ONE, ignoring later anchors", function()
    -- Only the first anchor is ever set by the addon, but a Blizzard template
    -- or another addon can add more; persisting the wrong one would move the
    -- frame on the next login.
    local f = newFrame()
    f:SetPoint("TOP", mocks.UIParent, "TOP", 1, 2)
    f:SetPoint("LEFT", mocks.UIParent, "LEFT", 9, 9)
    assertEqual(Util.SaveAnchor(f).point, "TOP")
end)

-- ── ApplyAnchor ─────────────────────────────────────────────────────────────

test("ApplyAnchor positions the frame against UIParent", function()
    -- Always UIParent: the saved shape has no relativeTo, so anchoring to
    -- anything else would make the stored offsets meaningless.
    local f = newFrame()
    Util.ApplyAnchor(f, { point = "BOTTOM", relativePoint = "BOTTOM", x = 5, y = 15 })
    local point, relativeTo, relativePoint, x, y = f:GetPoint(1)
    assertEqual(point, "BOTTOM")
    assertTrue(rawequal(relativeTo, mocks.UIParent))
    assertEqual(relativePoint, "BOTTOM")
    assertEqual(x, 5)
    assertEqual(y, 15)
end)

test("ApplyAnchor clears stale points instead of stacking them", function()
    -- It is called repeatedly from config-changed handlers; without the
    -- ClearAllPoints the frame accumulates conflicting anchors and drifts.
    local f = newFrame()
    f:SetPoint("TOPLEFT", mocks.UIParent, "TOPLEFT", 0, 0)
    Util.ApplyAnchor(f, { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 })
    assertEqual(f:GetNumPoints(), 1, "exactly one anchor must survive")
    assertEqual(f:GetPoint(1), "CENTER")
end)

test("ApplyAnchor fills in centered defaults for a partial saved anchor", function()
    -- Profiles written by older builds can be missing fields.
    local f = newFrame()
    Util.ApplyAnchor(f, {})
    local point, _, relativePoint, x, y = f:GetPoint(1)
    assertEqual(point, "CENTER"); assertEqual(relativePoint, "CENTER")
    assertEqual(x, 0); assertEqual(y, 0)
end)

test("ApplyAnchor is a no-op for a nil frame or nil anchor", function()
    Util.ApplyAnchor(nil, { point = "CENTER" })
    local f = newFrame()
    Util.ApplyAnchor(f, nil)
    assertEqual(f:GetNumPoints(), 0, "a nil anchor must not clear existing points")
end)

test("SaveAnchor and ApplyAnchor round-trip a dragged position exactly", function()
    -- The end-to-end contract: drag, save to the profile, reload, restore.
    local dragged = newFrame()
    dragged:SetPoint("TOPRIGHT", mocks.UIParent, "TOPRIGHT", -33, -77)
    local saved = Util.SaveAnchor(dragged)

    local restored = newFrame()
    Util.ApplyAnchor(restored, saved)
    local p, _, rp, x, y = restored:GetPoint(1)
    assertEqual(p, saved.point)
    assertEqual(rp, saved.relativePoint)
    assertEqual(x, saved.x)
    assertEqual(y, saved.y)
end)

-- ── Throttle ────────────────────────────────────────────────────────────────

test("Throttle passes the LAST call's arguments, not the first", function()
    -- Trailing-edge semantics: the point of coalescing a burst is to act on
    -- the settled value.
    local got
    local fn = Util.Throttle(50, function(...) got = { ... } end)
    fn("first", 1)
    fn("second", 2)
    fn("third", 3)
    mocks.__flushTimers()
    assertEqual(got[1], "third")
    assertEqual(got[2], 3)
end)

test("Throttle re-arms after firing, so a later burst is not swallowed", function()
    -- A one-shot latch here would silently stop refreshing after the first
    -- settings change of a session.
    local calls = 0
    local fn = Util.Throttle(50, function() calls = calls + 1 end)
    fn(); fn()
    mocks.__flushTimers()
    assertEqual(calls, 1)
    fn(); fn()
    mocks.__flushTimers()
    assertEqual(calls, 2)
end)

test("Throttle preserves embedded nils in the argument list", function()
    -- Args are captured with select('#') and replayed with unpack(…, n)
    -- precisely so a nil in the middle doesn't truncate the call.
    local n, a, b, c
    local fn = Util.Throttle(0, function(...)
        n = select("#", ...)
        a, b, c = ...
    end)
    fn("x", nil, "z")
    mocks.__flushTimers()
    assertEqual(n, 3)
    assertEqual(a, "x"); assertNil(b); assertEqual(c, "z")
end)

test("Throttle survives a nil delay by treating it as immediate", function()
    local fired = false
    local fn = Util.Throttle(nil, function() fired = true end)
    fn()
    mocks.__flushTimers()
    assertTrue(fired)
end)

-- ── Spec display / ordering ─────────────────────────────────────────────────

test("SpecDisplayName returns the client's LOCALIZED name for display", function()
    -- The inverse of the storage rule: keys are locale-free, anything the
    -- user reads is in their language.
    assertEqual(Util.SpecDisplayName(253), "Beast Mastery")
end)

test("SpecDisplayName returns the empty string for a non-number", function()
    -- It feeds straight into FontString:SetText; a nil would blank the label
    -- with no clue why.
    assertEqual(Util.SpecDisplayName(nil), "")
    assertEqual(Util.SpecDisplayName("ELEMENTAL"), "")
end)

test("SpecDisplayName title-cases the English token for a spec the client can't name", function()
    -- Const.SPEC knows every spec; the mock client enumerates only three
    -- classes, so this is the "spec exists but the client didn't list it"
    -- path a fresh patch would hit.
    assertEqual(Util.SpecDisplayName(NS.Const.SPEC.ARCANE), "Arcane")
end)

test("SpecDisplayName falls back to the raw ID for a spec nothing knows", function()
    assertEqual(Util.SpecDisplayName(999999), "999999")
end)

test("SpecTokenForID rejects a non-number rather than indexing with it", function()
    assertNil(Util.SpecTokenForID("253"))
    assertNil(Util.SpecTokenForID(nil))
end)

test("SpecOrderForClass returns Blizzard's order, not numeric order", function()
    -- The Spells editor dropdown must match the character sheet.
    local order = Util.SpecOrderForClass("SHAMAN")
    assertTrue(order ~= nil, "the mock client enumerates SHAMAN")
    assertEqual(order[1], NS.Const.SPEC.ELEMENTAL)
    assertEqual(order[2], NS.Const.SPEC.ENHANCEMENT)
    assertEqual(order[3], NS.Const.SPEC.RESTORATION_SHAMAN)
end)

test("SpecOrderForClass normalizes a lower-case class token", function()
    assertTrue(Util.SpecOrderForClass("shaman") ~= nil)
end)

test("SpecOrderForClass is nil for a class the client can't enumerate", function()
    -- Callers fall back to their own ordering on nil, so this must not be an
    -- empty table.
    assertNil(Util.SpecOrderForClass("MAGE"))
    assertNil(Util.SpecOrderForClass(nil))
end)

-- ── Class token ─────────────────────────────────────────────────────────────

test("NormalizeClassToken upper-cases and tolerates nil", function()
    assertEqual(Util.NormalizeClassToken("Shaman"), "SHAMAN")
    assertEqual(Util.NormalizeClassToken(nil), "")
end)

-- ── print ───────────────────────────────────────────────────────────────────
--
-- The printer is no longer core/Util.lua's. It comes from LibKa0s-Core-1.0 via
-- core/CoreSetup.lua, and its cases moved wholesale to tests/test_coresetup.lua
-- — where they also cover the secret guard and the library-absent load, neither
-- of which the old implementation had. Keeping a second copy here would be the
-- duplicate testing-§8 forbids.
--
-- One case did NOT survive the move: `Util.print()` with no arguments used to
-- emit the bare tag, and now emits the tag plus the separator, because the
-- library's Print mirrors print()'s shape and joins an empty argument list to an
-- empty body. No call site in the addon prints with no arguments; the change is
-- one trailing space on a line nothing emits.

-- ── NewUnitCastFilter ───────────────────────────────────────────────────────
--
-- One filter frame per (module, unit), built once and armed/disarmed across
-- every enable cycle (events-frames-taint-§1: the unit-filter carve-out is
-- reused, never rebuilt). The route map is the frame's fixed event set.

local ONE_ROUTE = { UNIT_SPELLCAST_START = "OnCast" }

test("NewUnitCastFilter forwards the event into the routed handler", function()
    -- The filter frame exists so handlers can drop their `if unit ~= ...`
    -- guard; that only holds if the forward actually reaches the method.
    local seen = {}
    local module = {
        OnCast = function(_, event, unit, extra)
            seen = { event = event, unit = unit, extra = extra }
        end,
    }
    local filter = Util.NewUnitCastFilter(module, "focus", ONE_ROUTE)
    filter.Arm()
    filter.frame:_fire("UNIT_SPELLCAST_START", "focus", "payload")
    assertEqual(seen.event, "UNIT_SPELLCAST_START")
    assertEqual(seen.unit, "focus")
    assertEqual(seen.extra, "payload")
end)

test("NewUnitCastFilter tolerates a handler that isn't defined yet", function()
    -- A typo'd or not-yet-defined handler must not error inside the dispatch.
    local filter = Util.NewUnitCastFilter({}, "target",
        { UNIT_SPELLCAST_STOP = "NoSuchHandler" })
    filter.Arm()
    filter.frame:_fire("UNIT_SPELLCAST_STOP", "target")
end)

test("NewUnitCastFilter Disarm empties the frame's registrations", function()
    -- AceAddon's UnregisterAllEvents won't reach this private frame, so the
    -- module's teardown has to — and the frame itself is kept for the next Arm.
    local filter = Util.NewUnitCastFilter({}, "target", ONE_ROUTE)
    assertFalse(filter.armed, "a new filter starts disarmed")
    assertNil(next(filter.frame.__events), "and registers nothing until armed")
    filter.Arm()
    assertTrue(filter.armed)
    assertEqual(filter.frame.__events.UNIT_SPELLCAST_START, "target",
        "registered for the named unit only")
    local frame = filter.frame
    filter.Disarm()
    assertFalse(filter.armed)
    assertNil(next(filter.frame.__events), "Disarm must leave nothing registered")
    assertTrue(rawequal(filter.frame, frame), "the frame survives a Disarm")
end)

test("Arm twice registers each event once", function()
    -- Arm is idempotent: a second Arm on an armed filter registers nothing.
    local filter = Util.NewUnitCastFilter({}, "target", {
        UNIT_SPELLCAST_START = "A", UNIT_SPELLCAST_STOP = "B",
    })
    local calls = {}
    local real = filter.frame.RegisterUnitEvent
    filter.frame.RegisterUnitEvent = function(f, ev, ...)
        calls[ev] = (calls[ev] or 0) + 1
        return real(f, ev, ...)
    end
    filter.Arm()
    filter.Arm()
    assertEqual(calls.UNIT_SPELLCAST_START, 1)
    assertEqual(calls.UNIT_SPELLCAST_STOP, 1)
    -- A Disarm/Arm cycle re-arms the SAME fixed set on the SAME frame.
    filter.Disarm()
    filter.Arm()
    assertEqual(calls.UNIT_SPELLCAST_START, 2)
    assertEqual(calls.UNIT_SPELLCAST_STOP, 2)
end)

test("a non-UNIT_SPELLCAST route is refused", function()
    -- The helper's one job is the cast family; a general private-frame
    -- factory is what events-frames-taint-§1 forbids.
    local before = #mocks.__frames
    T.assertErrorMatches(function()
        Util.NewUnitCastFilter({}, "target", {
            UNIT_SPELLCAST_START = "A", UNIT_AURA = "B",
        })
    end, "UNIT_SPELLCAST_")
    assertEqual(#mocks.__frames, before, "a refused route map must not build a frame")
end)

test("a bad EMPOWER name is rejected and the other routes still arm", function()
    -- One name the client refuses costs only its own row, and lands once in
    -- NS.State.rejectedEvents.
    local BAD = "UNIT_SPELLCAST_EMPOWER_START"
    local savedBad = mocks.__badEvents
    local savedRejected = NS.State.rejectedEvents
    mocks.__badEvents = { [BAD] = true }
    NS.State.rejectedEvents = {}
    local ok, err = pcall(function()
        local filter = Util.NewUnitCastFilter({}, "target", {
            [BAD] = "A", UNIT_SPELLCAST_STOP = "B",
        })
        filter.Arm()
        assertTrue(filter.armed)
        assertNil(filter.frame.__events[BAD], "the refused name is not registered")
        assertEqual(filter.frame.__events.UNIT_SPELLCAST_STOP, "target",
            "the other route still armed")
        assertEqual(#NS.State.rejectedEvents, 1)
        assertEqual(NS.State.rejectedEvents[1], BAD)
    end)
    mocks.__badEvents = savedBad
    NS.State.rejectedEvents = savedRejected
    if not ok then error(err, 0) end
end)
