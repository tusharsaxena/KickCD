-- tests/test_icongrid_glow_knobs.lua — the ready glow's per-style knobs.
--
-- Each glow slot (primary, secondary) carries its own copy of every style's
-- knobs: core/Constants.lua's Const.GLOW_KNOBS is the set, its ranges and its
-- defaults (shared with Ka0s Drop Watcher's upgrade glow), settings/Icons.lua
-- draws one row per knob per slot on Grid -> Icons -> Ready glow, and
-- modules/IconGrid_Render.lua's StartGlow hands the chosen style's knobs to
-- LibCustomGlow-1.0. Three things are pinned here:
--
--   * the three restatements agree: the constant, defaults/Profile.lua and the
--     schema rows (default, range, interleaved primary | secondary order);
--   * a knob row is dimmed under any other style and under trigger Never, and
--     enabled for its own style;
--   * the render passes each knob to the right argument, clamps a bad stored
--     value, and restarts a running glow when a knob moves (but not otherwise).
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local SLOTS = { "primary", "secondary" }

--- A LibCustomGlow stand-in that records every _Start call's arguments.
local function recordingLCG()
    local lcg = { calls = {} }
    for _, name in ipairs({ "ButtonGlow_Start", "ProcGlow_Start",
                            "PixelGlow_Start", "AutoCastGlow_Start" }) do
        lcg[name] = function(...)
            lcg.calls[#lcg.calls + 1] = { name = name, n = select("#", ...), ... }
        end
    end
    for _, name in ipairs({ "ButtonGlow_Stop", "ProcGlow_Stop",
                            "PixelGlow_Stop", "AutoCastGlow_Stop" }) do
        lcg[name] = function() end
    end
    return lcg
end

--- A fresh instance over the recording library, and one icon carrying the real
--- Icon mixin with a glow frame. Returns (icon, lcg, inst).
local function glowIcon()
    local lcg = recordingLCG()
    local inst = T.load(true, true, function(mocks)
        mocks.__libs["LibCustomGlow-1.0"] = lcg
    end)
    local IconGrid = inst.NS:GetModule("IconGrid")
    local mk = inst.mocks.CreateFrame
    local icon = mk("Button")
    icon.glow = mk("Frame")
    icon.unit = "target"
    inst.mocks.Mixin(icon, IconGrid.Icon)
    return icon, lcg, inst
end

local RED = { r = 1, g = 0, b = 0, a = 1 }

-- ── the three restatements agree ────────────────────────────────────────────

test("every glow knob's default is defaults/Profile.lua's, for both slots", function()
    -- red under: changing a default in Const.GLOW_KNOBS and not in the profile
    local NS = T.NS
    local icons = NS.DEFAULT_PROFILE.units.target.icons
    assertTrue(#NS.Const.GLOW_KNOBS == 13, "the shared knob set is thirteen knobs")
    for _, knob in ipairs(NS.Const.GLOW_KNOBS) do
        for _, slot in ipairs(SLOTS) do
            local key = slot .. "Glow" .. knob.leaf
            assertEqual(icons[key], knob.default, key .. " defaults as the knob table says")
        end
    end
end)

test("the Ready glow tab draws each knob as a primary | secondary pair with the knob's range", function()
    -- red under: emitting every primary knob before the secondaries, which
    -- breaks the two-column mirror the rest of the tab keeps
    local NS = T.NS
    local rows = {}
    for _, def in ipairs(NS.Settings.Helpers.SchemaForPanel("icons", "target")) do
        if def.group == "Ready glow" and def.path:match("Glow[A-Z]%a*$")
           and not def.path:match("Glow[TC]%a+$") then
            rows[#rows + 1] = def
        end
    end
    assertEqual(#rows, 2 * #NS.Const.GLOW_KNOBS, "one row per knob per slot")
    for i, knob in ipairs(NS.Const.GLOW_KNOBS) do
        local p, s = rows[2 * i - 1], rows[2 * i]
        assertEqual(p.path, "units.target.icons.primaryGlow" .. knob.leaf)
        assertEqual(s.path, "units.target.icons.secondaryGlow" .. knob.leaf)
        for _, def in ipairs({ p, s }) do
            assertEqual(def.type, knob.kind, def.path .. "'s type")
            assertEqual(def.default, knob.default, def.path .. "'s default")
            assertEqual(def.min, knob.min, def.path .. "'s min")
            assertEqual(def.max, knob.max, def.path .. "'s max")
            assertEqual(def.step, knob.step, def.path .. "'s step")
            assertTrue(type(def.disabledIf) == "function", def.path .. " dims itself")
        end
        assertEqual(p.subgroup, s.subgroup, knob.leaf .. "'s pair sits under one heading")
    end
end)

-- ── dimming ─────────────────────────────────────────────────────────────────

--- The Ready glow rows of the target page, by path.
local function readyGlowRows(inst)
    local byPath = {}
    for _, def in ipairs(inst.NS.Settings.Helpers.SchemaForPanel("icons", "target")) do
        if def.group == "Ready glow" then byPath[def.path] = def end
    end
    return byPath
end

local function dimmed(def) return def.disabledIf(def) and true or false end

test("a knob row is dimmed under another style and under Never, and live under its own", function()
    -- red under: a disabledIf that tests only the style, so a Never slot's
    -- knobs stay live; or one that reads the OTHER slot's trigger
    local inst = T.load(true, true)
    local Store = inst.NS.Settings.Store
    local rows = readyGlowRows(inst)
    local P = "units.target.icons."
    Store.Set(P .. "primaryGlowTrigger", "always")
    Store.Set(P .. "primaryGlowType", "pixel")
    Store.Set(P .. "secondaryGlowTrigger", "never")

    assertFalse(dimmed(rows[P .. "primaryGlowPixelLines"]), "pixel's own knob is live")
    assertFalse(dimmed(rows[P .. "primaryGlowXOffset"]), "the shared offset is live under pixel")
    assertTrue(dimmed(rows[P .. "primaryGlowAutocastScale"]), "auto cast's knob is dimmed under pixel")
    assertTrue(dimmed(rows[P .. "primaryGlowButtonFrequency"]), "button's knob is dimmed under pixel")
    assertTrue(dimmed(rows[P .. "secondaryGlowPixelLines"]), "a Never slot's knobs are all dimmed")

    Store.Set(P .. "primaryGlowType", "button")
    assertFalse(dimmed(rows[P .. "primaryGlowButtonFrequency"]), "re-read live: button's knob wakes")
    assertTrue(dimmed(rows[P .. "primaryGlowXOffset"]), "the offsets do not apply to button")
    assertTrue(dimmed(rows[P .. "primaryGlowPixelLines"]), "pixel's knob sleeps")
end)

test("the style dropdown is dimmed while its slot's trigger is Never; the swatch never is", function()
    -- red under: dropping styleOff from the style row, or keying it on the
    -- other slot's trigger
    local inst = T.load(true, true)
    local Store = inst.NS.Settings.Store
    local rows = readyGlowRows(inst)
    local P = "units.target.icons."
    Store.Set(P .. "primaryGlowTrigger", "never")
    Store.Set(P .. "secondaryGlowTrigger", "always")
    assertTrue(dimmed(rows[P .. "primaryGlowType"]), "Never dims the style")
    assertFalse(dimmed(rows[P .. "secondaryGlowType"]), "the other slot's trigger is its own")
    assertNil(rows[P .. "primaryGlowColor"].disabledIf, "a swatch carries no disabledIf")
end)

-- ── the render ──────────────────────────────────────────────────────────────

test("each style's _Start receives its own knobs, the slot's and not the other's", function()
    -- red under: reading the primary keys for a secondary icon, or passing
    -- PixelLength 0 through instead of nil (a zero-length line)
    local icon, lcg = glowIcon()
    local cfg = {
        primaryGlowPixelLines = 3, primaryGlowPixelFrequency = 0.5, primaryGlowPixelLength = 0,
        primaryGlowPixelThickness = 4, primaryGlowPixelBorder = true,
        primaryGlowXOffset = 2, primaryGlowYOffset = -3,
        secondaryGlowPixelLines = 11,
    }
    icon:StartGlow("pixel", RED, false, cfg, true)
    local c = lcg.calls[#lcg.calls]
    assertEqual(c.name, "PixelGlow_Start")
    assertEqual(c[3], 3);    assertEqual(c[4], 0.5); assertNil(c[5], "length 0 is automatic: nil")
    assertEqual(c[6], 4);    assertEqual(c[7], 2);   assertEqual(c[8], -3)
    assertEqual(c[9], true); assertEqual(c[10], "KickCD")

    icon:StopGlow()
    icon:StartGlow("pixel", RED, false, cfg, false)
    c = lcg.calls[#lcg.calls]
    assertEqual(c[3], 11, "the secondary icon reads the secondary knobs")
    assertEqual(c[6], 1, "and a knob it does not set reads the default")

    icon:StartGlow("autocast", RED, false, { primaryGlowAutocastParticles = 6,
        primaryGlowAutocastFrequency = 0.3, primaryGlowAutocastScale = 1.5,
        primaryGlowXOffset = 1, primaryGlowYOffset = 2 }, true)
    c = lcg.calls[#lcg.calls]
    assertEqual(c.name, "AutoCastGlow_Start")
    assertEqual(c[3], 6); assertEqual(c[4], 0.3); assertEqual(c[5], 1.5)
    assertEqual(c[6], 1); assertEqual(c[7], 2);   assertEqual(c[8], "KickCD")

    icon:StartGlow("button", RED, false, { primaryGlowButtonFrequency = 0.5 }, true)
    c = lcg.calls[#lcg.calls]
    assertEqual(c.name, "ButtonGlow_Start"); assertEqual(c[3], 0.5)

    icon:StartGlow("proc", RED, false, { primaryGlowProcDuration = 2,
        primaryGlowProcStartAnim = false, primaryGlowXOffset = -1, primaryGlowYOffset = 4 }, true)
    c = lcg.calls[#lcg.calls]
    assertEqual(c.name, "ProcGlow_Start")
    local o = c[2]
    assertEqual(o.duration, 2); assertEqual(o.startAnim, false)
    assertEqual(o.xOffset, -1); assertEqual(o.yOffset, 4); assertEqual(o.key, "KickCD")
end)

test("the knob defaults draw the glow the library drew before the knobs existed", function()
    -- Before the knobs, StartGlow passed nil for every one of them and the
    -- library filled its own: 8 lines, frequency 0.25 (period 4), th 1 and the
    -- dark inner border for pixel; 4 particles, frequency 0.125 (period 8),
    -- scale 1 for auto cast; throttle 0.01 for button, which its frequency
    -- spells 0.25 (throttle = 0.25 / frequency * 0.01). The defaults must keep
    -- that look for a profile that never touched a knob.
    -- red under: PixelThickness 2, PixelBorder false or ButtonFrequency 0.125
    local icon, lcg = glowIcon()
    icon:StartGlow("pixel", RED, false, {}, true)
    local c = lcg.calls[#lcg.calls]
    assertEqual(c[3], 8);  assertEqual(c[4], 0.25); assertNil(c[5])
    assertEqual(c[6], 1, "the library's nil thickness is 1")
    assertTrue(c[9] ~= false, "the library draws the dark border unless told false")
    assertEqual(c[7], 0); assertEqual(c[8], 0)

    icon:StartGlow("autocast", RED, false, {}, true)
    c = lcg.calls[#lcg.calls]
    assertEqual(c[3], 4); assertEqual(c[4], 0.125); assertEqual(c[5], 1)

    icon:StartGlow("button", RED, false, {}, true)
    c = lcg.calls[#lcg.calls]
    assertEqual(0.25 / c[3] * 0.01, 0.01, "the button ants step every 0.01 s, as with nil")

    icon:StartGlow("proc", RED, false, {}, true)
    local o = lcg.calls[#lcg.calls][2]
    assertEqual(o.duration, 1); assertEqual(o.startAnim, true)
    assertEqual(o.xOffset, 0);  assertEqual(o.yOffset, 0)
end)

test("a stored knob out of range is clamped, and a wrong type reads the default", function()
    -- red under: handing a hand-edited SavedVariable straight to the library
    local icon, lcg = glowIcon()
    icon:StartGlow("pixel", RED, false, { primaryGlowPixelLines = 900,
        primaryGlowPixelThickness = -5, primaryGlowPixelFrequency = "fast",
        primaryGlowPixelBorder = "yes" }, true)
    local c = lcg.calls[#lcg.calls]
    assertEqual(c[3], 20, "lines clamp to the slider's max")
    assertEqual(c[6], 1, "thickness clamps to the slider's min")
    assertEqual(c[4], 0.25, "a string frequency reads the default")
    assertEqual(c[9], true, "a non-boolean border reads the default")
end)

test("a moved knob restarts a running glow; an unchanged re-apply does not", function()
    -- The idempotency gate stops SPELL_STATE re-emits replaying the glow's
    -- intro; a knob must ride it like the color does, or a slider edit would
    -- not show until something else moved.
    -- red under: leaving the knobs out of StartGlow's gate
    local icon, lcg = glowIcon()
    local cfg = { primaryGlowPixelLines = 5 }
    icon:StartGlow("pixel", RED, false, cfg, true)
    icon:StartGlow("pixel", RED, false, cfg, true)
    assertEqual(#lcg.calls, 1, "the same knobs do not restart the glow")
    cfg.primaryGlowPixelLines = 6
    icon:StartGlow("pixel", RED, false, cfg, true)
    assertEqual(#lcg.calls, 2, "a moved knob restarts it")
    assertEqual(lcg.calls[2][3], 6)
end)

test("UpdateGlow hands the icon's slot config to StartGlow", function()
    -- red under: UpdateGlow calling StartGlow without cfg, so every knob
    -- silently reads its default
    local icon, lcg, inst = glowIcon()
    local cfg = inst.NS.db.profile.units.target.icons
    cfg.primaryGlowTrigger, cfg.primaryGlowType = "always", "autocast"
    cfg.primaryGlowAutocastParticles = 9
    icon.cfg, icon._isPrimary = cfg, true
    icon:UpdateGlow({ ready = true })
    local c = lcg.calls[#lcg.calls]
    assertEqual(c.name, "AutoCastGlow_Start")
    assertEqual(c[3], 9)
end)
