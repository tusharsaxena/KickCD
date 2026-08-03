-- tests/test_castbar_frame.lua — the cast bar's frame behavior, end to end.
--
-- This suite is what the stateful frame mock bought. Every assertion here was
-- previously impossible: against a no-op stub, IsShown() is permanently
-- truthy, SetValue is a no-op, and SetText goes nowhere — so "the bar rendered
-- the cast" and "the bar did nothing" were the same observation.
--
-- Two contracts get pinned that only show up at frame level:
--   * casts fill 0 → total while channels drain total → 0, and
--   * the dual interruptible/uninterruptible widget stack is alpha-switched
--     off the SECRET notInterruptible flag through C_CurveUtil, never through
--     a Lua branch.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

--- A fully enabled instance per test: the cast bar keeps a lot of per-unit
--- state (current cast, cached grid layout, OnUpdate script) and sharing it
--- across cases would make them order-dependent.
local function enabled()
    local inst = T.load(true, true)
    return inst.NS, inst.mocks, inst.NS:GetModule("Castbar")
end

--- A CastingDuration stand-in. Its getters return PLAIN numbers, which is the
--- documented difference from the cooldown duration object.
local function duration(total, elapsed)
    return {
        GetTotalDuration     = function() return total end,
        GetElapsedDuration   = function() return elapsed end,
        GetRemainingDuration = function() return total - elapsed end,
    }
end

-- `field = nil` is invisible to pairs(), and "a record with NO duration
-- object" is exactly one of the cases below, so clearing needs a sentinel.
local NIL = {}

local function castRecord(over)
    local rec = {
        name = "Chaos Bolt", texture = "tex", spellID = 116858,
        notInterruptible = false, isChannel = false, duration = duration(3, 1),
    }
    for k, v in pairs(over or {}) do
        if v == NIL then rec[k] = nil else rec[k] = v end
    end
    return rec
end

--- Put the profile into a state where the bar is allowed to show.
local function makeVisible(NS)
    NS.db.profile.locked = true
    NS.db.profile.visibility = "always"
    NS.db.profile.enabled = true
end

-- ── EnsureFrame ─────────────────────────────────────────────────────────────

test("EnsureFrame builds the full widget stack once and reuses it", function()
    -- Rebuilding on every call would orphan the previous frame and leak a
    -- widget stack per config change.
    local NS, _, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local frame = Castbar:EnsureFrame(inst)
    assertTrue(frame ~= nil)
    assertTrue(rawequal(Castbar:EnsureFrame(inst), frame), "the frame must be reused")
    assertTrue(rawequal(inst.frame, frame))
    assertTrue(NS ~= nil)
end)

test("EnsureFrame creates BOTH state bars and both backgrounds", function()
    -- The dual stack is the mechanism that lets a secret flag pick a look
    -- without a Lua branch; a single bar cannot express it.
    local _, _, Castbar = enabled()
    local frame = Castbar:EnsureFrame(Castbar:GetInstance("target"))
    assertTrue(frame.bar.interruptible ~= nil)
    assertTrue(frame.bar.uninterruptible ~= nil)
    assertTrue(frame.bgInterruptible ~= nil)
    assertTrue(frame.bgUninterruptible ~= nil)
    assertFalse(rawequal(frame.bar.interruptible, frame.bar.uninterruptible),
        "the two state bars must be distinct widgets")
end)

test("EnsureFrame parents the state bars inside the bar container", function()
    local _, _, Castbar = enabled()
    local frame = Castbar:EnsureFrame(Castbar:GetInstance("target"))
    assertTrue(rawequal(frame.bar.interruptible:GetParent(), frame.bar))
    assertTrue(rawequal(frame.bar.uninterruptible:GetParent(), frame.bar))
    assertTrue(rawequal(frame.bar:GetParent(), frame))
end)

test("EnsureFrame seeds both bars to an empty 0..1 range", function()
    -- An unseeded StatusBar renders a full bar, so a freshly built cast bar
    -- would flash 100% before the first cast. Built from a NON-enabled
    -- instance on purpose: the OnEnable cascade goes on to skin the bar and
    -- (while unlocked) park a mid-bar preview on it, which would hide the
    -- state of the raw build.
    local raw = T.load(true)
    local Castbar = raw.NS:GetModule("Castbar")
    local frame = Castbar:EnsureFrame(Castbar:GetInstance("target"))
    local mn, mx = frame.bar.interruptible:GetMinMaxValues()
    assertEqual(mn, 0); assertEqual(mx, 1)
    assertEqual(frame.bar.interruptible:GetValue(), 0)
    assertEqual(frame.bar.uninterruptible:GetValue(), 0)
end)

test("target and focus get separate frames, not one shared bar", function()
    local _, _, Castbar = enabled()
    local t = Castbar:EnsureFrame(Castbar:GetInstance("target"))
    local f = Castbar:EnsureFrame(Castbar:GetInstance("focus"))
    assertFalse(rawequal(t, f))
end)

test("GetCastbarFrame never creates an instance for an unknown unit", function()
    -- UnitLabel anchors to whatever exists; creating on read would leak an
    -- instance per query.
    local _, _, Castbar = enabled()
    assertTrue(Castbar:GetCastbarFrame("party3") == nil)
end)

-- ── Start / RenderCast ──────────────────────────────────────────────────────

test("Start renders the cast name into the bar's FontString", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    assertEqual(inst.frame.nameText:GetText(), "Chaos Bolt")
end)

test("Start applies the user's name truncation", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    NS.Units.Castbar("target").nameTruncate = 5
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    assertEqual(inst.frame.nameText:GetText(), "Chaos…")
end)

test("Start blanks the name entirely when showName is off", function()
    -- Blanking rather than leaving the previous cast's name is the point:
    -- a stale name is worse than none.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    NS.Units.Castbar("target").showName = false
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    assertEqual(inst.frame.nameText:GetText(), "")
end)

test("Start pushes the cast's icon texture onto the icon widget", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    NS.Units.Castbar("target").iconSize = 20
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ texture = "Interface\\Icons\\Chaos" }))
    assertEqual(inst.frame.icon:GetTexture(), "Interface\\Icons\\Chaos")
end)

test("a CAST fills the bar 0 -> total", function()
    -- Elapsed, not remaining: a cast bar that drains reads as a channel.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ isChannel = false, duration = duration(4, 1) }))
    local mn, mx = inst.frame.bar.interruptible:GetMinMaxValues()
    assertEqual(mn, 0); assertEqual(mx, 4)
    assertEqual(inst.frame.bar.interruptible:GetValue(), 1, "elapsed drives a cast")
end)

test("a CHANNEL drains the bar total -> 0", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ isChannel = true, duration = duration(4, 1) }))
    assertEqual(inst.frame.bar.interruptible:GetValue(), 3, "remaining drives a channel")
end)

test("both stacked bars carry identical values so the alpha switch is seamless", function()
    -- Only one is visible at a time, but the hidden one has to be in the same
    -- position or the bar jumps when interruptibility flips mid-cast.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ duration = duration(4, 2.5) }))
    assertEqual(inst.frame.bar.interruptible:GetValue(),
                inst.frame.bar.uninterruptible:GetValue())
    local imn, imx = inst.frame.bar.interruptible:GetMinMaxValues()
    local umn, umx = inst.frame.bar.uninterruptible:GetMinMaxValues()
    assertEqual(imn, umn); assertEqual(imx, umx)
end)

test("Start shows the frame and arms the per-frame OnUpdate", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    assertTrue(inst.frame:IsShown())
    assertTrue(inst.frame:GetScript("OnUpdate") ~= nil, "the animation must be running")
end)

test("Start refuses a record with no duration object rather than faking one", function()
    -- A pre-12.0 client (or a failed API call) yields no duration; inventing
    -- one would animate a bar against numbers nobody measured.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ duration = NIL }))
    assertTrue(inst.current == nil, "no cast may be tracked without a duration")
end)

test("the OnUpdate tick advances the bar as the cast progresses", function()
    -- The hot path. Driving it proves the animation reads the duration object
    -- live rather than the value seeded at cast start.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    local elapsed = 0
    local d = {
        GetTotalDuration     = function() return 4 end,
        GetElapsedDuration   = function() return elapsed end,
        GetRemainingDuration = function() return 4 - elapsed end,
    }
    Castbar:Start(inst, castRecord({ duration = d }))
    assertEqual(inst.frame.bar.interruptible:GetValue(), 0)
    elapsed = 2.5
    inst.frame:_run("OnUpdate")
    assertEqual(inst.frame.bar.interruptible:GetValue(), 2.5)
end)

test("the OnUpdate tick writes the remaining/total countdown when showTime is on", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    NS.Units.Castbar("target").showTime = true
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ duration = duration(4, 1) }))
    inst.frame:_run("OnUpdate")
    assertEqual(inst.frame.timeText:GetText(), "3.0 / 4.0")
end)

test("the OnUpdate tick leaves the countdown alone when showTime is off", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    NS.Units.Castbar("target").showTime = false
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    inst.frame.timeText:SetText("SENTINEL")
    inst.frame:_run("OnUpdate")
    assertEqual(inst.frame.timeText:GetText(), "SENTINEL")
end)

test("the OnUpdate script disarms itself once the cast record is gone", function()
    -- Otherwise the bar keeps ticking against a nil duration every frame for
    -- the rest of the session.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    inst.current = nil
    inst.frame:_run("OnUpdate")
    assertTrue(inst.frame:GetScript("OnUpdate") == nil)
end)

-- ── ApplyState: the secret-driven alpha switch ──────────────────────────────

test("an INTERRUPTIBLE cast shows the interruptible widgets and hides the others", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ notInterruptible = false }))
    assertEqual(inst.frame.bar.interruptible:GetAlpha(), 1)
    assertEqual(inst.frame.bar.uninterruptible:GetAlpha(), 0)
    assertEqual(inst.frame.bgInterruptible:GetAlpha(), 1)
    assertEqual(inst.frame.bgUninterruptible:GetAlpha(), 0)
end)

test("an UNINTERRUPTIBLE cast flips the whole stack the other way", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ notInterruptible = true }))
    assertEqual(inst.frame.bar.interruptible:GetAlpha(), 0)
    assertEqual(inst.frame.bar.uninterruptible:GetAlpha(), 1)
    assertEqual(inst.frame.bgInterruptible:GetAlpha(), 0)
    assertEqual(inst.frame.bgUninterruptible:GetAlpha(), 1)
end)

test("the alpha switch never branches on notInterruptible in Lua", function()
    -- The contract that keeps the cast bar working in combat. A flag that
    -- errors on every Lua operation must still drive the full render.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local secret = setmetatable({}, {
        __tostring = function() error("tostring() on a secret flag", 0) end,
        __eq       = function() error("compared a secret flag", 0) end,
        __concat   = function() error("concat on a secret flag", 0) end,
        __len      = function() error("# on a secret flag", 0) end,
    })
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ notInterruptible = secret }))
    assertTrue(inst.frame:IsShown(), "a secret flag must not break the render")
end)

test("the no-cast state falls back to interruptible visuals", function()
    -- The preview the user drags: it has no cast, so there is no flag to
    -- switch on and the friendlier of the two looks is correct.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:EnsureFrame(inst)
    inst.current = nil
    Castbar:ApplyState(inst)
    assertEqual(inst.frame.bar.interruptible:GetAlpha(), 1)
    assertEqual(inst.frame.bar.uninterruptible:GetAlpha(), 0)
    assertEqual(inst.frame.borderUninterruptible:GetAlpha(), 0)
end)

test("the uninterruptible warning border is on and the interruptible one off", function()
    -- Border show/hide is folded INTO the curve arguments rather than
    -- multiplied afterwards, because multiplying a secret result errors.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ notInterruptible = true }))
    assertEqual(inst.frame.borderUninterruptible:GetAlpha(), 1)
    assertEqual(inst.frame.borderInterruptible:GetAlpha(), 0)
end)

-- ── Stop ────────────────────────────────────────────────────────────────────

test("Stop clears the cast, empties both bars and disarms the animation", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    Castbar:Stop(inst)
    assertTrue(inst.current == nil)
    assertEqual(inst.frame.bar.interruptible:GetValue(), 0)
    assertEqual(inst.frame.bar.uninterruptible:GetValue(), 0)
    assertTrue(inst.frame:GetScript("OnUpdate") == nil)
end)

test("Stop HIDES the bar while locked", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    assertTrue(inst.frame:IsShown())
    Castbar:Stop(inst)
    assertFalse(inst.frame:IsShown())
end)

test("Stop leaves a PREVIEW on screen while unlocked, so it stays draggable", function()
    -- Hiding here would leave the user with nothing to grab the moment the
    -- target stopped casting.
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    NS.db.profile.locked = false
    Castbar:Stop(inst)
    assertTrue(inst.frame:IsShown(), "the unlocked bar must remain visible")
    assertEqual(inst.frame.bar.interruptible:GetValue(), 0.5, "the preview sits mid-bar")
end)

test("the preview resets the bar range so it doesn't inherit the last cast's total", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ duration = duration(30, 1) }))
    NS.db.profile.locked = false
    Castbar:Stop(inst)
    local mn, mx = inst.frame.bar.interruptible:GetMinMaxValues()
    assertEqual(mn, 0); assertEqual(mx, 1)
end)

test("Stop is safe before the frame has ever been built", function()
    local _, _, Castbar = enabled()
    Castbar:Stop(Castbar:GetInstance("focus"))
end)

-- ── Visibility gating ───────────────────────────────────────────────────────

test("a cast starting out of combat is suppressed in the in_combat mode", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    NS.db.profile.visibility = "in_combat"
    NS.State.SetInCombat(false)
    local inst = Castbar:GetInstance("target")
    Castbar:EnsureFrame(inst)
    inst.frame:Hide()
    Castbar:Start(inst, castRecord())
    assertFalse(inst.frame:IsShown())
end)

test("the same cast shows once combat is flagged", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    NS.db.profile.visibility = "in_combat"
    NS.State.SetInCombat(true)
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord())
    assertTrue(inst.frame:IsShown())
    NS.State.SetInCombat(false)
end)

test("disabling the cast bar for a unit keeps its frame hidden through a cast", function()
    local NS, _, Castbar = enabled()
    makeVisible(NS)
    NS.Units.Castbar("target").enabled = false
    local inst = Castbar:GetInstance("target")
    Castbar:EnsureFrame(inst)
    inst.frame:Hide()
    Castbar:Start(inst, castRecord())
    assertFalse(inst.frame:IsShown())
end)

test("the interruptible mode masks the bar's alpha from the SECRET flag", function()
    -- The two-step gate: shouldBeVisible lets any hostile cast through, then
    -- the mask hides the uninterruptible ones C-side.
    local NS, mocks, Castbar = enabled()
    makeVisible(NS)
    NS.db.profile.visibility = "target_casting_interruptible"
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return "Chaos Bolt", nil, nil, nil, nil, nil, nil, true
    end
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ notInterruptible = true }))
    assertEqual(inst.frame:GetAlpha(), 0,
        "an uninterruptible cast must be masked out")
    assertTrue(inst.frame.__alphaFromBoolean ~= nil,
        "the mask must go through SetAlphaFromBoolean, not a Lua branch")
end)

test("an interruptible cast in that mode stays fully visible", function()
    local NS, mocks, Castbar = enabled()
    makeVisible(NS)
    NS.db.profile.visibility = "target_casting_interruptible"
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return "Chaos Bolt", nil, nil, nil, nil, nil, nil, false
    end
    local inst = Castbar:GetInstance("target")
    Castbar:Start(inst, castRecord({ notInterruptible = false }))
    assertEqual(inst.frame:GetAlpha(), 1)
end)

-- ── Anchoring ───────────────────────────────────────────────────────────────

test("ApplyAnchor in FREE mode restores the saved anchor against UIParent", function()
    local NS, mocks, Castbar = enabled()
    local c = NS.Units.Castbar("target")
    c.anchorMode = "FREE"
    NS.Units.SetAnchor("target", "castbar",
        { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 42, y = -17 })
    local inst = Castbar:GetInstance("target")
    Castbar:EnsureFrame(inst)
    Castbar:ApplyAnchor(inst)
    local point, relativeTo, relativePoint, x, y = inst.frame:GetPoint(1)
    assertEqual(point, "TOPLEFT")
    assertTrue(rawequal(relativeTo, mocks.UIParent))
    assertEqual(relativePoint, "TOPLEFT")
    assertEqual(x, 42); assertEqual(y, -17)
end)

test("re-anchoring never stacks a second point on the frame", function()
    -- ApplyAnchor runs on every config change and grid layout; leaking points
    -- would slowly drag the bar off position.
    local NS, _, Castbar = enabled()
    NS.Units.Castbar("target").anchorMode = "FREE"
    local inst = Castbar:GetInstance("target")
    Castbar:EnsureFrame(inst)
    Castbar:ApplyAnchor(inst)
    Castbar:ApplyAnchor(inst)
    Castbar:ApplyAnchor(inst)
    assertEqual(inst.frame:GetNumPoints(), 1)
end)
