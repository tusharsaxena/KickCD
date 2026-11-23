-- tests/test_icongrid_render.lua — the pure render helpers in
-- modules/IconGrid_Render.lua.
--
-- test_icongrid_apply.lua drives Icon:Apply end-to-end; this suite pins the
-- deciders underneath it. Two are worth isolating:
--
--   * triggerSatisfied resolves the per-slot glow trigger. The
--     "target_casting_interruptible" branch deliberately starts the glow for
--     ANY hostile cast and lets an alpha mask hide it — because
--     notInterruptible is secret in 12.0 and cannot be branched on in Lua.
--     A "fix" that filters here instead is the bug this guards.
--   * plainStateMoved is the gate that stops ~10 redundant glow/badge
--     re-renders a second for a spell parked on an unchanged cooldown. It
--     looks like Cooldowns.MaterialChange but deliberately omits charges.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

local inst     = T.load(true)
local NS       = inst.NS
local mocks    = inst.mocks
local IconGrid = NS:GetModule("IconGrid")

local TARGET = { unit = "target", isCasting = function() return false end }

test("the render helpers are published for testing", function()
    for _, name in ipairs({ "SafeUnpackColor", "UnpackGlowColor",
                            "TriggerSatisfied", "PlainStateMoved" }) do
        assertTrue(type(IconGrid[name]) == "function", name .. " must be published")
    end
end)

-- ── safeUnpackColor ─────────────────────────────────────────────────────────

test("SafeUnpackColor reads both the array and hash color shapes", function()
    local r, g, b, a = IconGrid.SafeUnpackColor({ 0.1, 0.2, 0.3, 0.4 })
    assertEqual(r, 0.1); assertEqual(g, 0.2); assertEqual(b, 0.3); assertEqual(a, 0.4)
    local r2, g2, b2, a2 = IconGrid.SafeUnpackColor({ r = 0.5, g = 0.6, b = 0.7, a = 0.8 })
    assertEqual(r2, 0.5); assertEqual(g2, 0.6); assertEqual(b2, 0.7); assertEqual(a2, 0.8)
end)

test("SafeUnpackColor honors the caller's cooldown-tint fallback", function()
    -- The whole reason it wraps Util.Unpack: a missing tint must fall back to
    -- the module's dimming color, not to white.
    local r, g, b, a = IconGrid.SafeUnpackColor(nil, 0.3, 0.3, 0.3, 0.9)
    assertEqual(r, 0.3); assertEqual(g, 0.3); assertEqual(b, 0.3); assertEqual(a, 0.9)
end)

test("SafeUnpackColor falls back to opaque white with no fallback given", function()
    local r, g, b, a = IconGrid.SafeUnpackColor(nil)
    assertEqual(r, 1); assertEqual(g, 1); assertEqual(b, 1); assertEqual(a, 1)
end)

-- ── unpackGlowColor ─────────────────────────────────────────────────────────

test("UnpackGlowColor reads a configured array color", function()
    local r, g, b, a = IconGrid.UnpackGlowColor({ 0.1, 0.2, 0.3, 0.4 })
    assertEqual(r, 0.1); assertEqual(g, 0.2); assertEqual(b, 0.3); assertEqual(a, 0.4)
end)

test("UnpackGlowColor falls back to the shipped yellow glow for a non-table", function()
    -- The glow default is deliberately NOT white: it has to read as an alert
    -- against the icon art underneath.
    for _, bad in ipairs({ "yellow", 42, true }) do
        local r, g, b, a = IconGrid.UnpackGlowColor(bad)
        assertTrue(r > 0.9 and g > 0.9 and b < 0.5, "expected the yellow default")
        assertEqual(a, 1)
    end
end)

test("UnpackGlowColor fills missing channels rather than returning nils", function()
    -- The values go into a C-side color setter; a nil channel errors.
    local r, g, b, a = IconGrid.UnpackGlowColor({})
    assertEqual(r, 1); assertEqual(g, 1); assertEqual(b, 1); assertEqual(a, 1)
end)

-- ── triggerSatisfied ────────────────────────────────────────────────────────

test("the 'always' trigger glows unconditionally", function()
    assertTrue(IconGrid.TriggerSatisfied("always", TARGET))
end)

test("the 'never' trigger and any unknown token keep the glow off", function()
    -- Unknown tokens matter: a trigger from a newer build landing in an older
    -- client must fail closed, not glow permanently.
    assertFalse(IconGrid.TriggerSatisfied("never", TARGET))
    assertFalse(IconGrid.TriggerSatisfied("some_future_trigger", TARGET))
    assertFalse(IconGrid.TriggerSatisfied(nil, TARGET))
end)

test("'target_casting' asks the INSTANCE whether its unit is casting", function()
    -- It reads the instance's own predicate rather than the unit APIs, so the
    -- focus grid can't inherit the target's cast state.
    assertTrue(IconGrid.TriggerSatisfied("target_casting",
        { unit = "target", isCasting = function() return true end }))
    assertFalse(IconGrid.TriggerSatisfied("target_casting",
        { unit = "target", isCasting = function() return false end }))
end)

test("'target_casting' is false for an instance with no predicate yet", function()
    -- Instances are built before their predicate is wired.
    assertFalse(IconGrid.TriggerSatisfied("target_casting", { unit = "target" }))
    assertFalse(IconGrid.TriggerSatisfied("target_casting", nil))
end)

test("'target_casting_interruptible' glows for ANY hostile cast", function()
    -- Coarse ON PURPOSE. The interruptibility filter is an alpha mask applied
    -- afterwards, because notInterruptible is secret and unreadable in Lua.
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return "Chaos Bolt" end
    mocks.UnitChannelInfo = function() return nil end
    assertTrue(IconGrid.TriggerSatisfied("target_casting_interruptible", TARGET))
end)

test("'target_casting_interruptible' does NOT glow for a friendly cast", function()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return false end
    mocks.UnitCastingInfo = function() return "Greater Heal" end
    assertFalse(IconGrid.TriggerSatisfied("target_casting_interruptible", TARGET))
end)

test("'target_casting_interruptible' resolves per-unit, defaulting to target", function()
    -- An instance with no unit token must not silently gate on nothing.
    mocks.UnitExists = function(u) return u == "target" end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function(u) return u == "target" and "Chaos Bolt" or nil end
    mocks.UnitChannelInfo = function() return nil end
    assertTrue(IconGrid.TriggerSatisfied("target_casting_interruptible", {}))
    assertFalse(IconGrid.TriggerSatisfied("target_casting_interruptible", { unit = "focus" }))
end)

-- ── plainStateMoved ─────────────────────────────────────────────────────────

local function st(over)
    local s = { ready = true, isActive = false, cdObject = nil, chargeCdObject = nil }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

test("PlainStateMoved treats a first render as a change", function()
    assertTrue(IconGrid.PlainStateMoved(nil, st()))
end)

test("PlainStateMoved is false when nothing plain moved", function()
    -- Before KickCD#9 this was the common case ~10x/sec through a whole
    -- cooldown (handle churn re-emitted every poll), which is why the gate
    -- was added; it still guards any emit that moves nothing plain.
    assertFalse(IconGrid.PlainStateMoved(st(), st()))
end)

test("PlainStateMoved fires on a ready or isActive flip", function()
    assertTrue(IconGrid.PlainStateMoved(st({ ready = true }), st({ ready = false })))
    assertTrue(IconGrid.PlainStateMoved(st({ isActive = false }), st({ isActive = true })))
end)

test("PlainStateMoved watches handle PRESENCE, not handle identity", function()
    -- The API mints a fresh handle per poll; treating that as a change would
    -- defeat the gate completely.
    local a = st({ cdObject = mocks.__makeDurationObject(30) })
    local b = st({ cdObject = mocks.__makeDurationObject(29) })
    assertFalse(IconGrid.PlainStateMoved(a, b), "a new handle for the same cooldown is not news")
    assertTrue(IconGrid.PlainStateMoved(a, st()), "the cooldown ENDING is")
    assertTrue(IconGrid.PlainStateMoved(st(), a), "the cooldown STARTING is")
end)

test("PlainStateMoved watches the charge timer's presence independently", function()
    local withCharge = st({ chargeCdObject = mocks.__makeDurationObject(10) })
    assertTrue(IconGrid.PlainStateMoved(st(), withCharge))
    assertFalse(IconGrid.PlainStateMoved(withCharge,
        st({ chargeCdObject = mocks.__makeDurationObject(9) })))
end)

test("PlainStateMoved deliberately IGNORES charges, unlike the cooldown gates", function()
    -- Charges can be secret and a secret cannot be compared. Gating the badge
    -- on an uncomparable value would strand a stale count on screen for a
    -- whole fight, so the badge is simply always refreshed instead.
    local secret = {}
    local prev = mocks.issecretvalue
    mocks.issecretvalue = function(v) return rawequal(v, secret) end
    assertFalse(IconGrid.PlainStateMoved(st({ charges = 1 }), st({ charges = 2 })),
        "a plain charge move must not re-trigger the glow half of Apply")
    assertFalse(IconGrid.PlainStateMoved(st({ charges = secret }), st({ charges = secret })))
    mocks.issecretvalue = prev
end)

test("PlainStateMoved never compares a secret charge value", function()
    -- Proof, not inference: a landmine charge value must pass straight through.
    local mine = setmetatable({}, {
        __eq       = function() error("compared a secret charge count", 0) end,
        __tostring = function() error("tostring on a secret charge count", 0) end,
    })
    IconGrid.PlainStateMoved(st({ charges = mine }), st({ charges = mine }))
end)

-- ── The cooldown ticker owns time (KickCD#9) ────────────────────────────────
--
-- Emit = state changed, ticker = time passed. Cooldowns no longer re-emits for
-- a fresh handle, so every time-varying visual must be reachable by ticks
-- alone: the body alpha/tint curves, the GCD-suppression alpha and the text.
-- `mocks.__flushTimers()` fires exactly one tick (the ticker re-queues itself
-- onto the NEXT queue), which is what lets these cases step time.

--- A real icon widget on a fresh enabled instance, with Compat's cooldown
--- readers answering from `world`, which a case edits between ticks.
local function tickWorld()
    local ti = T.load(true, true)
    local TNS = ti.NS
    local IG = TNS:GetModule("IconGrid")
    ti.mocks.__flushTimers()
    local cfg = TNS.db.profile.units.target.icons
    cfg.readyAlpha, cfg.cooldownAlpha = 1.0, 0.4
    IG.BuildCurves("target")
    local icon = IG.CreateIconWidget(ti.mocks.CreateFrame("Frame"))
    icon.unit, icon.spellID, icon._isPrimary, icon.cfg = "target", 192058, true, cfg
    icon.UpdateGlow = function() end
    local world = { active = true, charges = nil, swipes = 0,
                    handle = ti.mocks.__makeDurationObject(29, 30) }
    TNS.Compat.GetSpellCooldown = function() return 0, 0, true, 1, world.active end
    TNS.Compat.GetSpellCooldownDuration = function() return world.handle end
    TNS.Compat.GetSpellCharges = function() return world.charges end
    icon.cooldown.SetCooldownFromDurationObject = function() world.swipes = world.swipes + 1 end
    return ti, icon, cfg, world
end

local function fullCd(ti, remaining, total)
    return { spellID = 192058, ready = false, isActive = true,
             cdObject = ti.mocks.__makeDurationObject(remaining, total) }
end

test("an icon on a full cooldown is ticked even with the countdown text OFF", function()
    -- The text toggle used to gate the ticker registration, so with it off the
    -- curves ran only when an emit arrived — and emits no longer arrive for time.
    -- red under: registering on the ticker only when cfg.showCooldownText is set
    local ti, icon, cfg, world = tickWorld()
    cfg.showCooldownText = false
    icon:Apply(fullCd(ti, 1.0, 1.0))           -- a GCD-length total: ready alpha
    assertEqual(icon:GetAlpha(), 1.0, "sanity: a GCD reads as ready")
    world.handle = ti.mocks.__makeDurationObject(14, 15)
    ti.mocks.__flushTimers()
    assertEqual(icon:GetAlpha(), 0.4, "one tick must re-evaluate the alpha curve from a fresh handle")
    assertFalse(icon.cooldownText:IsShown(), "the countdown stays hidden while its toggle is off")
end)

test("a tick never re-arms a running swipe", function()
    -- SWIPE STUTTER: a fresh handle every 0.1s could restart the animation.
    -- red under: calling SetCooldownFromDurationObject on every tick
    local ti, icon, _, world = tickWorld()
    icon:Apply(fullCd(ti, 29, 30))
    assertEqual(world.swipes, 1, "sanity: the state work armed it once")
    for _ = 1, 3 do ti.mocks.__flushTimers() end
    assertEqual(world.swipes, 1, "ticks must leave a running swipe alone")
end)

test("a tick after the cooldown ends hides the swipe and the text", function()
    local ti, icon, _, world = tickWorld()
    icon:Apply(fullCd(ti, 29, 30))
    assertTrue(icon.cooldown:IsShown(), "sanity: the swipe is up")
    world.active = false
    ti.mocks.__flushTimers()
    assertFalse(icon.cooldown:IsShown(), "the plain isActive flip must hide the swipe")
    assertFalse(icon.cooldownText:IsShown(), "and the countdown with it")
end)

test("a recast inside the event lag is re-armed by the ticker, not lost", function()
    -- The ticker reads the plain isActive before SPELL_UPDATE_COOLDOWN lands.
    -- If the spell goes straight back on cooldown, Cooldowns sees active ->
    -- active and emits nothing, so the ticker must bring the swipe back itself.
    -- red under: unregistering the icon on the isActive=false tick
    local ti, icon, _, world = tickWorld()
    icon:Apply(fullCd(ti, 29, 30))
    world.active = false
    ti.mocks.__flushTimers()
    world.active = true
    world.handle = ti.mocks.__makeDurationObject(15, 15)
    ti.mocks.__flushTimers()
    assertTrue(icon.cooldown:IsShown(), "the swipe must come back")
    assertEqual(world.swipes, 2, "re-armed once, from the fresh handle")
end)

test("a finished swipe on a still-active spell is re-armed on the next tick", function()
    -- The GCD -> real-cooldown handoff: an off-GCD interrupt pressed under a
    -- GCD keeps isActive true and the handle present, so no emit. The swipe
    -- was armed from the GCD handle and finishes first; the C side says so
    -- through OnCooldownDone, and the next tick re-arms from a fresh handle.
    -- red under: not re-arming after OnCooldownDone
    local ti, icon, _, world = tickWorld()
    icon:Apply(fullCd(ti, 1.0, 1.2))
    world.handle = ti.mocks.__makeDurationObject(14, 15)
    ti.mocks.__flushTimers()
    assertEqual(world.swipes, 1, "sanity: no re-arm while the GCD swipe still runs")
    icon.cooldown:_run("OnCooldownDone")
    ti.mocks.__flushTimers()
    assertEqual(world.swipes, 2, "the finished swipe must be re-armed from the real cooldown")
    ti.mocks.__flushTimers()
    assertEqual(world.swipes, 2, "once, not on every tick after")
end)

test("a charge-recharge tick never touches the icon body", function()
    -- Branch 2: the spell IS castable, so the body keeps its ready visuals and
    -- only the swipe overlay, its suppression alpha and the text are time's.
    -- red under: painting the body alpha curve on a branch-2 tick
    local ti, icon, cfg, world = tickWorld()
    cfg.showCooldownText = true
    world.active, world.charges = false, 1
    icon:Apply({ spellID = 192058, ready = true, isActive = false, charges = 1,
                 chargeCdObject = ti.mocks.__makeDurationObject(9, 10) })
    icon:SetAlpha(0.123)                       -- a sentinel no tick may overwrite
    world.handle = ti.mocks.__makeDurationObject(7, 10)
    ti.mocks.__flushTimers()
    assertEqual(icon:GetAlpha(), 0.123, "a recharge tick must leave the body alpha alone")
    assertEqual(icon.cooldownText:GetText(), "7.0", "but must repaint the text from a fresh handle")
end)

test("the ticker never compares a duration getter in Lua", function()
    -- Every getter on a DurationObject is secret in combat. A landmine handle
    -- whose getters return values that error on compare, arithmetic or
    -- tostring must still pass through a whole tick cleanly.
    local ti, icon, _, world = tickWorld()
    local mine = setmetatable({}, {
        __eq  = function() error("compared a secret duration", 0) end,
        __lt  = function() error("compared a secret duration", 0) end,
        __le  = function() error("compared a secret duration", 0) end,
        __add = function() error("arithmetic on a secret duration", 0) end,
        __tostring = function() error("tostring on a secret duration", 0) end,
    })
    icon:Apply(fullCd(ti, 29, 30))
    local h = ti.mocks.__makeDurationObject(29, 30)
    h.GetRemainingDuration = function() return mine end
    world.handle = h
    icon.cooldownText.SetFormattedText = function() end   -- the C side accepts a secret
    ti.mocks.__flushTimers()
end)

-- ── The icon tooltip: the body rule (AD-92-KC, LibKa0s#92) ──────────────────
--
-- An icon is a body element of its unit's HUD display (WowAddonStandards standalone-windows,
-- *Tooltip placement*): its spell tooltip opens BESIDE THE WHOLE DISPLAY (grid, drag strip, sim
-- strip, an anchored cast bar, the unit label), right when it fits, else left, its top level with
-- the icon's, 2 px off the display's outer edge, through LibKa0s-Tooltip-1.0's PlaceBeside. It was
-- `SetOwner(self, "ANCHOR_RIGHT")`, a corner offset off the icon, which every case here is red under.

local SCREEN_KIT = "/tests/_kit/mock_screen.lua"

--- Rawset a frame's geometry in its own units, as mock_screen's frames answer it.
local function geom(f, l, b, w, h, s)
    rawset(f, "GetLeft",   function() return l end)
    rawset(f, "GetBottom", function() return b end)
    rawset(f, "GetRight",  function() return l and l + w end)
    rawset(f, "GetTop",    function() return b and b + h end)
    rawset(f, "GetWidth",  function() return w end)
    rawset(f, "GetHeight", function() return h end)
    rawset(f, "GetEffectiveScale", function() return s or 1 end)
end

--- A fresh enabled addon on a `sw` x `sh` screen, its target grid at (gl, 400) `gw` x 40 and
--- locked, one icon at (640, 400) 40 x 40 with tooltips on, and a 250 x 100 GameTooltip that
--- records its owner.
local function tipWorld(sw, gl, gw)
    local ti       = T.load(true, true)
    local tNS, m    = ti.NS, ti.mocks
    local IG       = tNS:GetModule("IconGrid")
    local scr      = dofile(T.root .. SCREEN_KIT)(m, { width = sw, height = 800 })
    tNS.db.profile.locked = true
    local tInst     = IG:GetInstance("target")
    IG:ApplyLock(tInst)
    geom(tInst.grid, gl, 400, gw, 40)
    tNS.Units.Icons("target").showTooltip = true
    local btn = IG.CreateIconWidget(tInst.grid)
    btn.unit, btn.spellID = "target", 1766
    geom(btn, 640, 400, 40, 40)
    -- The rest of the display, laid out where the client puts it: the unit label's text on the
    -- grid's top edge, inside the grid's span, and the cast bar hidden (it shows only while a cast
    -- plays; the cast-bar case below shows and places it). Left at the mock's 0,0 they would
    -- stretch the display to the screen's left edge.
    local lbl = tNS:GetModule("UnitLabel"):PeekInstance("target")
    if lbl and lbl.text then geom(lbl.text, gl, 442, 60, 12) end
    local bar = tNS:GetModule("Castbar"):GetCastbarFrame("target")
    if bar then bar:Hide() end
    local tip, owners = m.GameTooltip, {}
    geom(tip, nil, nil, 250, 100)
    tip.SetOwner = function(self, owner, anchor)
        owners[#owners + 1] = { owner, anchor }
        rawset(self, "__owner", owner)
    end
    tip.GetOwner = function(self) return rawget(self, "__owner") end
    return { NS = tNS, m = m, IG = IG, scr = scr, inst = tInst, btn = btn, tip = tip, owners = owners }
end

--- The tooltip's one point as (point, relativeTo, relativePoint, x, y).
local function pointOf(tip)
    assertEqual(tip:GetNumPoints(), 1, "the tooltip is placed by one point")
    return tip:GetPoint(1)
end

test("an icon's tooltip is owned at ANCHOR_NONE, never at a corner or the cursor", function()
    local w = tipWorld(1920, 600, 200)
    w.btn:_run("OnEnter")
    assertEqual(#w.owners, 1)
    assertTrue(rawequal(w.owners[1][1], w.btn), "owned by the icon hovered")
    assertEqual(w.owners[1][2], "ANCHOR_NONE", "red under the old ANCHOR_RIGHT corner offset")
    w.scr.restore()
end)

test("an icon's tooltip opens right of the display, top level with the icon, when it fits", function()
    local w = tipWorld(1920, 600, 200)
    w.btn:_run("OnEnter")
    local point, rel, relPoint, x, y = pointOf(w.tip)
    assertEqual(point, "TOPLEFT")
    assertTrue(rawequal(rel, w.m.UIParent), "an absolute point on UIParent")
    assertEqual(relPoint, "BOTTOMLEFT")
    assertEqual(x, 802, "the grid's right edge (800) plus the 2 px gap")
    assertEqual(y, 440, "level with the icon's top")
    w.scr.restore()
end)

test("an icon's tooltip opens left of the display when the right side would leave the screen", function()
    -- 800 + 2 + 250 runs past a 1000 px screen, so the left: TOPRIGHT at 600 - 2.
    local w = tipWorld(1000, 600, 200)
    w.btn:_run("OnEnter")
    local point, _, _, x, y = pointOf(w.tip)
    assertEqual(point, "TOPRIGHT")
    assertEqual(x, 598)
    assertEqual(y, 440)
    w.scr.restore()
end)

test("an anchored cast bar is part of the display: the tooltip clears the bar, not just the grid", function()
    -- red under: a group of the icon alone (or the grid alone), which would open at 682 or 802.
    local w = tipWorld(1920, 600, 200)
    local Castbar = w.NS:GetModule("Castbar")
    local bar = Castbar:EnsureFrame(Castbar:GetInstance("target"))
    bar:Show()
    geom(bar, 550, 445, 400, 20)
    w.btn:_run("OnEnter")
    local point, _, _, x = pointOf(w.tip)
    assertEqual(point, "TOPLEFT")
    assertEqual(x, 952, "the anchored bar's right edge (950) plus the gap")
    -- A FREE bar is a display of its own: it drops out of the icon's group.
    w.NS.Units.Castbar("target").anchorMode = "FREE"
    w.tip:ClearAllPoints()
    w.btn:_run("OnEnter")
    local _, _, _, xFree = pointOf(w.tip)
    assertEqual(xFree, 802, "a free bar does not widen the grid's display")
    -- A hidden bar drops out too.
    w.NS.Units.Castbar("target").anchorMode = "PRIMARY"
    bar:Hide()
    w.tip:ClearAllPoints()
    w.btn:_run("OnEnter")
    local _, _, _, xHidden = pointOf(w.tip)
    assertEqual(xHidden, 802, "a hidden bar is no part of what the player sees")
    w.scr.restore()
end)

test("the display group lists the grid first and only the members that show", function()
    local w = tipWorld(1920, 600, 200)
    local frames = w.IG.TipGroup("target")
    assertTrue(rawequal(frames[1], w.inst.grid), "the grid is the group's main frame")
    for i = 2, #frames do
        assertTrue(frames[i]:IsShown(), "member " .. i .. " is shown")
    end
    assertFalse(w.inst.handle and w.inst.handle:IsShown(), "a locked grid's strip is hidden")
    for _, f in ipairs(frames) do
        assertFalse(rawequal(f, w.inst.handle), "so the hidden drag strip is not a member")
    end
    w.scr.restore()
end)

test("the drag strip is never a member: it shows only unlocked, when no icon takes the mouse", function()
    -- The review of AD-92-KC: an icon takes the mouse only while locked and the strip shows only
    -- while unlocked, so a strip member was dead logic. Pinned so it does not come back; red under
    -- a tipGroup that adds inst.handle when shown.
    local w = tipWorld(1920, 600, 200)
    assertTrue(w.inst.handle ~= nil, "the grid has a drag strip")
    local mouse
    rawset(w.btn, "EnableMouse", function(_, on) mouse = on end)
    w.inst.ordered[#w.inst.ordered + 1] = w.btn
    w.NS.db.profile.locked = false
    w.IG:ApplyLock(w.inst)
    w.inst.ordered[#w.inst.ordered] = nil
    assertTrue(w.inst.handle:IsShown(), "unlocked, the strip shows")
    assertEqual(mouse, false, "and no icon takes the mouse, so no icon tooltip fires")
    for _, f in ipairs(w.IG.TipGroup("target")) do
        assertFalse(rawequal(f, w.inst.handle), "the strip is not a member even while shown")
    end
    w.scr.restore()
end)

test("a shown sim strip is part of the display: the tooltip clears the strip", function()
    -- red under: a group without the docked sim strip, which would open at 802.
    local w = tipWorld(1920, 600, 200)
    local strip = w.m.CreateFrame("Frame", nil, w.inst.grid)
    geom(strip, 600, 444, 420, 16)
    strip:Show()
    w.NS.SimStrip.__strips["target:icons"] = strip
    w.btn:_run("OnEnter")
    local point, _, _, x = pointOf(w.tip)
    assertEqual(point, "TOPLEFT")
    assertEqual(x, 1022, "the sim strip's right edge (1020) plus the gap")
    strip:Hide()
    w.tip:ClearAllPoints()
    w.btn:_run("OnEnter")
    local _, _, _, xHidden = pointOf(w.tip)
    assertEqual(xHidden, 802, "a hidden sim strip drops out")
    w.NS.SimStrip.__strips["target:icons"] = nil
    w.scr.restore()
end)

test("the unit label's text is part of the display while shown on the grid", function()
    -- red under: a group without the label, which would open at 802.
    local w = tipWorld(1920, 600, 200)
    local lbl = w.NS:GetModule("UnitLabel"):PeekInstance("target")
    assertTrue(lbl and lbl.frame and lbl.text, "the target label exists")
    w.NS.Units.LabelStyle("target").attach = "icons"
    lbl.frame:Show()
    geom(lbl.text, 600, 442, 350, 12)
    w.btn:_run("OnEnter")
    local point, _, _, x = pointOf(w.tip)
    assertEqual(point, "TOPLEFT")
    assertEqual(x, 952, "the label text's right edge (950) plus the gap")
    lbl.frame:Hide()
    w.tip:ClearAllPoints()
    w.btn:_run("OnEnter")
    local _, _, _, xHidden = pointOf(w.tip)
    assertEqual(xHidden, 802, "a hidden label drops out")
    w.scr.restore()
end)

test("a label attached to the cast bar is a member only while the bar is anchored (KC-REV-1)", function()
    -- Pins tipGroup's label rule across its split into helpers (CCN 18 -> under 15).
    local w = tipWorld(1920, 600, 200)
    local lbl = w.NS:GetModule("UnitLabel"):PeekInstance("target")
    local style = w.NS.Units.LabelStyle("target")
    lbl.frame:Show()
    local function hasLabel()
        for _, f in ipairs(w.IG.TipGroup("target")) do
            if rawequal(f, lbl.text) then return true end
        end
        return false
    end
    style.attach = "castbar"
    w.NS.Units.Castbar("target").anchorMode = "PRIMARY"
    assertTrue(hasLabel(), "on an anchored bar the label is part of the display")
    w.NS.Units.Castbar("target").anchorMode = "FREE"
    assertFalse(hasLabel(), "on a free bar it belongs to the bar's own display")
    style.attach = "icons"
    assertTrue(hasLabel(), "attached to the icons it is a member whatever the bar does")
    style.attach = "screen"
    assertFalse(hasLabel(), "any other attachment is not")
    style.attach = "icons"
    lbl.frame:Hide()
    assertFalse(hasLabel(), "a hidden label never is")
    w.NS.Units.Castbar("target").anchorMode = "PRIMARY"
    w.scr.restore()
end)

test("a tooltip that grows after it is placed is placed again, re-clamped to the screen", function()
    -- SetSpellByID on uncached data: the client fills the tooltip later and it grows. Placed for
    -- 100 px tall, its top sits level with the icon's (440); grown to 500 px it would run 60 px off
    -- the screen's bottom, so the size hook re-runs the placement (Tooltip.Replace) and the top
    -- clamps to 500. Red under a placement made once, right after Show.
    local w = tipWorld(1920, 600, 200)
    w.btn:_run("OnEnter")
    local _, _, _, _, y = pointOf(w.tip)
    assertEqual(y, 440)
    geom(w.tip, nil, nil, 250, 500)
    w.tip:_run("OnSizeChanged", 250, 500)
    local point, _, _, x, yGrown = pointOf(w.tip)
    assertEqual(point, "TOPLEFT")
    assertEqual(x, 802, "still beside the display")
    assertEqual(yGrown, 500, "re-clamped so the grown tooltip stays on screen")
    -- Once the pointer leaves, or another frame owns the tooltip, a resize moves nothing.
    w.btn:_run("OnLeave")
    w.tip:SetOwner(w.m.UIParent, "ANCHOR_NONE")
    w.tip:Show()
    geom(w.tip, nil, nil, 250, 600)
    w.tip:_run("OnSizeChanged", 250, 600)
    local _, _, _, _, yAfter = pointOf(w.tip)
    assertEqual(yAfter, 500, "a tooltip no icon of ours owns is left where it is")
    w.scr.restore()
end)

test("with no room on either side the icon's tooltip is attached above the icon", function()
    -- The display spans 50..950 of a 1000 px screen: neither side holds 250 px (body rule 4).
    local w = tipWorld(1000, 50, 900)
    w.btn:_run("OnEnter")
    local point, rel, _, x, y = pointOf(w.tip)
    assertEqual(point, "BOTTOM")
    assertTrue(rawequal(rel, w.m.UIParent))
    assertEqual(x, 660, "centered on the icon")
    assertEqual(y, 442, "2 px above the icon's top")
    w.scr.restore()
end)

test("an icon whose geometry cannot be read gets its tooltip above the icon, never at the cursor", function()
    local w = tipWorld(1920, 600, 200)
    geom(w.btn, nil, nil, nil, nil)
    w.btn:_run("OnEnter")
    local point, rel, relPoint, x, y = pointOf(w.tip)
    assertEqual(point, "BOTTOM")
    assertTrue(rawequal(rel, w.btn), "a relative point on the icon")
    assertEqual(relPoint, "TOP")
    assertEqual(x, 0); assertEqual(y, 2)
    w.scr.restore()
end)

test("an icon shows no tooltip while the tooltip option is off", function()
    local w = tipWorld(1920, 600, 200)
    w.NS.Units.Icons("target").showTooltip = false
    w.btn:_run("OnEnter")
    assertEqual(#w.owners, 0)
    w.scr.restore()
end)

test("no HUD file anchors a tooltip at the cursor or a corner, nor hooks the strips' placement", function()
    -- The HUD's own tooltips go through LibKa0s-Tooltip-1.0 (AD-92-KC). settings/ is left out: the
    -- Settings canvas is out of the rule's scope (standalone-windows, *What it does not bind*).
    local bad = {}
    for _, rel in ipairs(T.tocFiles) do
        if rel:match("^core/") or rel:match("^modules/") then
            local fh = assert(io.open(T.root .. "/" .. rel, "r"))
            local n = 0
            for line in fh:lines() do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                local anchor = code:match('SetOwner%s*%b()') and code:match('"(ANCHOR_[%u_]+)"')
                if (anchor and anchor ~= "ANCHOR_NONE") or code:find("GetCursorPosition", 1, true)
                    or code:find("tooltipPlace", 1, true) then
                    bad[#bad + 1] = rel .. ":" .. n
                end
            end
            fh:close()
        end
    end
    assertEqual(#bad, 0, "cursor or corner tooltip anchors: " .. table.concat(bad, ", "))
end)
