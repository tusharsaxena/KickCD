-- tests/test_icongrid_curves.lua — the per-unit alpha/tint curves in
-- modules/IconGrid_Render.lua.
--
-- Two changes land here and they pull in opposite directions, which is why they
-- are pinned together:
--
--   * F-016 — BuildCurves is now guarded by a signature, so an "icons" config
--     change that only touched a border / font / layout / glow field no longer
--     recreates three curves. A guard that skips too eagerly stops honoring
--     alpha edits.
--   * The per-unit split — the curves used to be module-level and read TARGET's
--     resolved appearance for every unit, so an UNLINKED focus silently
--     rendered with target's readyAlpha / cooldownAlpha / cooldownTint despite
--     having a full independent appearance config. Each unit now owns its pair.
--
-- The mock curve records its control points, so "which values did this unit's
-- curve actually get built from" is directly observable.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

--- A fresh enabled instance per test — curves are cached per unit and keyed on
--- a config signature, so a shared instance would leak cache state between
--- cases and hide exactly the bugs this suite exists to catch.
local function enabled()
    local inst = T.load(true, true)
    return inst.NS, inst.NS:GetModule("IconGrid")
end

local function iconsCfg(NS, unit)
    return NS.db.profile.units[unit or "target"].icons
end

--- The value a curve's FIRST control point was built with. Point 1 is the
--- "ready" end of the step for the alpha curve.
local function firstPointValue(curve)
    assertTrue(curve ~= nil, "expected a curve, got nil")
    assertTrue(curve.points and curve.points[1] ~= nil, "curve has no control points")
    return curve.points[1].value
end

--- Split a focus off target so the two resolve to genuinely different
--- appearance tables. Link defaults ON, which would make them the same table.
local function unlinkFocus(NS, IconGrid)
    NS.db.profile.units.focus.enabled = true
    NS.db.profile.units.focus.link    = false
    IconGrid:ReconcileUnits()
end

-- ── Per-unit independence ───────────────────────────────────────────────────

test("each unit gets its own curve pair", function()
    local NS, IconGrid = enabled()
    unlinkFocus(NS, IconGrid)
    IconGrid.BuildCurves()

    local t = IconGrid.CurvesFor("target")
    local f = IconGrid.CurvesFor("focus")
    assertTrue(t.alpha ~= nil, "target must have an alpha curve")
    assertTrue(f.alpha ~= nil, "focus must have an alpha curve")
    assertTrue(t.alpha ~= f.alpha, "target and focus must not share one curve object")
end)

test("an unlinked focus builds its curve from ITS OWN readyAlpha", function()
    -- The bug this split fixes: focus used to render with target's alpha.
    local NS, IconGrid = enabled()
    unlinkFocus(NS, IconGrid)
    iconsCfg(NS, "target").readyAlpha = 1.0
    iconsCfg(NS, "focus").readyAlpha  = 0.3
    IconGrid.BuildCurves()

    assertEqual(firstPointValue(IconGrid.CurvesFor("target").alpha), 1.0,
        "target's curve must use target's readyAlpha")
    assertEqual(firstPointValue(IconGrid.CurvesFor("focus").alpha), 0.3,
        "focus's curve must use focus's readyAlpha, not target's")
end)

test("an unlinked focus builds its tint curve from ITS OWN cooldownTint", function()
    local NS, IconGrid = enabled()
    unlinkFocus(NS, IconGrid)
    iconsCfg(NS, "target").cooldownTint = { 1, 0, 0, 1 }
    iconsCfg(NS, "focus").cooldownTint  = { 0, 0, 1, 1 }
    IconGrid.BuildCurves()

    local fTint = IconGrid.CurvesFor("focus").tint
    assertTrue(fTint ~= nil, "focus must have a tint curve")
    -- Point 3 is the post-GCD_UPPER end of the step, where the tint applies.
    local c = fTint.points[3].value
    assertEqual(c.b, 1, "focus's tint must be focus's blue, not target's red")
    assertEqual(c.r, 0, "focus's tint must not carry target's red channel")
end)

test("a LINKED focus resolves to target's values", function()
    -- Link is the default and must keep behaving as before the split: the
    -- link-awareness lives in NS.Units, so both units resolve the same table.
    local NS, IconGrid = enabled()
    NS.db.profile.units.focus.enabled = true
    NS.db.profile.units.focus.link    = true
    IconGrid:ReconcileUnits()
    iconsCfg(NS, "target").readyAlpha = 0.65
    IconGrid.BuildCurves()

    assertEqual(firstPointValue(IconGrid.CurvesFor("focus").alpha), 0.65,
        "a linked focus must build from target's readyAlpha")
end)

test("CurvesFor never falls back to another unit's curves", function()
    -- Returning target's pair for an unbuilt unit would silently reintroduce
    -- the exact inheritance bug, so an unknown unit gets an empty table.
    local _NS, IconGrid = enabled()
    IconGrid.BuildCurves()
    local unknown = IconGrid.CurvesFor("nosuchunit")
    assertTrue(unknown ~= nil, "must return a table, not nil, so callers need no guard")
    assertTrue(unknown.alpha == nil, "an unbuilt unit must NOT inherit target's curve")
end)

-- ── The rebuild guard (F-016) ───────────────────────────────────────────────

test("rebuilding with an unchanged config reuses the same curve objects", function()
    local _NS, IconGrid = enabled()
    IconGrid.BuildCurves()
    local before = IconGrid.CurvesFor("target").alpha
    IconGrid.BuildCurves()
    assertTrue(IconGrid.CurvesFor("target").alpha == before,
        "an unchanged config must not recreate the curve")
end)

test("an unrelated icons edit does NOT recreate the curves", function()
    -- The point of F-016: every "icons" CONFIG_CHANGED used to land in
    -- BuildCurves, including border / font / layout / glow edits.
    local NS, IconGrid = enabled()
    IconGrid.BuildCurves()
    local before = IconGrid.CurvesFor("target").alpha

    local c = iconsCfg(NS)
    c.borderSize = (c.borderSize or 1) + 3
    c.zoom       = 0.2
    IconGrid.BuildCurves()

    assertTrue(IconGrid.CurvesFor("target").alpha == before,
        "a border/zoom edit must not rebuild the alpha curve")
end)

test("a readyAlpha edit DOES recreate the curve", function()
    local NS, IconGrid = enabled()
    IconGrid.BuildCurves()
    local before = IconGrid.CurvesFor("target").alpha

    iconsCfg(NS).readyAlpha = 0.42
    IconGrid.BuildCurves()

    local after = IconGrid.CurvesFor("target").alpha
    assertTrue(after ~= before, "the guard must re-open when readyAlpha moves")
    assertEqual(firstPointValue(after), 0.42, "the new curve must carry the new alpha")
end)

test("a cooldownAlpha edit DOES recreate the curve", function()
    local NS, IconGrid = enabled()
    IconGrid.BuildCurves()
    local before = IconGrid.CurvesFor("target").alpha
    iconsCfg(NS).cooldownAlpha = 0.11
    IconGrid.BuildCurves()
    assertTrue(IconGrid.CurvesFor("target").alpha ~= before,
        "the guard must re-open when cooldownAlpha moves")
end)

test("a cooldownTint edit DOES recreate the curve", function()
    local NS, IconGrid = enabled()
    IconGrid.BuildCurves()
    local before = IconGrid.CurvesFor("target").tint
    iconsCfg(NS).cooldownTint = { 0.2, 0.9, 0.1, 1 }
    IconGrid.BuildCurves()
    assertTrue(IconGrid.CurvesFor("target").tint ~= before,
        "the guard must re-open when cooldownTint moves")
end)

test("one unit's rebuild does not disturb the other's cached curves", function()
    local NS, IconGrid = enabled()
    unlinkFocus(NS, IconGrid)
    IconGrid.BuildCurves()
    local focusBefore = IconGrid.CurvesFor("focus").alpha

    iconsCfg(NS, "target").readyAlpha = 0.77
    IconGrid.BuildCurves()

    assertTrue(IconGrid.CurvesFor("focus").alpha == focusBefore,
        "a target-only edit must leave an unlinked focus's curve alone")
end)

-- ── Signature ───────────────────────────────────────────────────────────────

test("CurveSignature covers exactly the three curve-shaping fields", function()
    local _NS, IconGrid = enabled()
    local base = { readyAlpha = 1, cooldownAlpha = 0.4, cooldownTint = { 1, 0.4, 0.4, 1 } }
    local sig  = IconGrid.CurveSignature(base)

    -- Unrelated fields must not move it.
    base.borderSize, base.zoom, base.glowType = 5, 0.2, "Pixel"
    assertEqual(IconGrid.CurveSignature(base), sig,
        "non-curve fields must be absent from the signature")

    -- Each of the three must.
    for _, mutate in ipairs({
        function(t) t.readyAlpha = 0.5 end,
        function(t) t.cooldownAlpha = 0.9 end,
        function(t) t.cooldownTint = { 0, 1, 0, 1 } end,
    }) do
        local t = { readyAlpha = 1, cooldownAlpha = 0.4, cooldownTint = { 1, 0.4, 0.4, 1 } }
        mutate(t)
        assertTrue(IconGrid.CurveSignature(t) ~= sig,
            "a curve-shaping field must change the signature")
    end
end)
