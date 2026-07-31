-- tests/test_icongrid_curve_link.lua — curves must follow the focus LINK flag.
--
-- Regression suite for a defect that shipped green and was caught in-game.
--
-- The focus link flag (`units.focus.link`) lives in the `"units"` config
-- section, not `"icons"`. `IconGrid:OnConfigChanged` rebuilt the curves only
-- for `"icons"`, so unchecking "Use same styling as Target" re-resolved
-- `inst.cfg` and re-laid-out the grid while leaving the CURVES built from
-- whatever the link resolved to a moment earlier — i.e. target's appearance.
-- An unlinked focus therefore kept rendering with target's readyAlpha /
-- cooldownAlpha / cooldownTint, which is precisely the bug the per-unit curve
-- split existed to fix.
--
-- Why the original suite missed it: it asserted the curves were CONSTRUCTED
-- per unit (reading control points straight off the objects) and never that an
-- icon RENDERED with its own unit's curve. The mock compounded that — its
-- EvaluateRemainingDuration ignored the curve entirely and returned a
-- constant, so "used its own curve" and "used target's curve" were literally
-- the same observation. The mock now reads control points; these cases assert
-- on the rendered alpha, end to end.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Comfortably past Const.GCD_UPPER (1.6), so the step curves evaluate to their
-- cooldown end rather than their ready end.
local ON_COOLDOWN = 30

--- A fresh enabled instance with focus live. Per-test, because curves cache
--- per unit and a shared instance would leak that cache between cases.
local function enabledWithFocus()
    local inst = T.load(true, true)
    local NS = inst.NS
    NS.db.profile.units.focus.enabled = true
    return inst, NS, NS:GetModule("IconGrid")
end

local function icons(NS, unit) return NS.db.profile.units[unit].icons end

--- Build a standalone icon carrying the real Icon mixin, stamped for `unit`.
--- Mirrors tests/test_icongrid_apply.lua's helper; kept local so a change to
--- that suite's fixture can't silently alter this regression's meaning.
local function makeIcon(inst, unit)
    local IconGrid = inst.NS:GetModule("IconGrid")
    local mk = inst.mocks.CreateFrame
    local icon = mk("Button")
    icon.icon         = mk("Frame")
    icon.cooldown     = mk("Frame")
    icon.cooldownText = mk("Frame")
    icon.chargesText  = mk("Frame")
    icon.glow         = mk("Frame")
    icon.unit         = unit
    icon.spellID      = 192058
    icon._isPrimary   = true
    inst.mocks.Mixin(icon, IconGrid.Icon)
    icon.UpdateGlow = function() end
    return icon
end

--- Render an on-cooldown state onto a fresh icon for `unit` and report the
--- alpha the icon ended up at — the number the player actually sees.
local function renderedAlpha(inst, unit)
    local icon = makeIcon(inst, unit)
    icon:Apply({
        spellID = 192058, ready = false, isActive = true,
        cdObject = inst.mocks.__makeDurationObject(ON_COOLDOWN),
    })
    return icon:GetAlpha()
end

--- Fire the real bus message a settings write produces, so these cases go
--- through IconGrid:OnConfigChanged rather than poking BuildCurves directly.
--- Driving the handler is the whole point: the bug was a missing call inside
--- it, which a direct BuildCurves() invocation would have hidden.
local function fireConfigChanged(NS, section)
    NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = section })
end

test("the mock's curve evaluation actually reads control points", function()
    -- Guards the guard. If this regresses to a constant, every assertion below
    -- silently stops discriminating and this whole suite goes vacuously green.
    local inst, NS, IconGrid = enabledWithFocus()
    icons(NS, "target").cooldownAlpha = 0.20
    fireConfigChanged(NS, "icons")
    local curve = IconGrid.CurvesFor("target").alpha
    assertTrue(curve ~= nil, "target must have an alpha curve")
    local d = inst.mocks.__makeDurationObject(ON_COOLDOWN)
    assertEqual(d:EvaluateRemainingDuration(curve), 0.20,
        "past GCD_UPPER the curve must evaluate to cooldownAlpha, not a constant")
end)

test("a LINKED focus renders with target's cooldown alpha", function()
    local inst, NS = enabledWithFocus()
    NS.db.profile.units.focus.link = true
    icons(NS, "target").cooldownAlpha = 0.20
    icons(NS, "focus").cooldownAlpha  = 0.90   -- present but must be ignored
    fireConfigChanged(NS, "icons")

    assertEqual(renderedAlpha(inst, "focus"), 0.20,
        "while linked, focus must mirror target's cooldownAlpha")
end)

test("unlinking focus via the `units` section re-renders with ITS OWN alpha", function()
    -- THE REGRESSION. Reproduces the in-game sequence exactly: values set while
    -- linked, then the link unchecked — which fires section "units", not
    -- "icons". Before the fix, focus kept target's 0.20 and the two grids were
    -- visually identical.
    local inst, NS = enabledWithFocus()
    NS.db.profile.units.focus.link = true
    icons(NS, "target").cooldownAlpha = 0.20
    icons(NS, "focus").cooldownAlpha  = 0.90
    fireConfigChanged(NS, "icons")
    assertEqual(renderedAlpha(inst, "focus"), 0.20, "precondition: linked")

    NS.db.profile.units.focus.link = false
    fireConfigChanged(NS, "units")

    assertEqual(renderedAlpha(inst, "focus"), 0.90,
        "after unlinking, focus must render with its own cooldownAlpha")
    assertEqual(renderedAlpha(inst, "target"), 0.20,
        "target must be untouched by the focus unlink")
end)

test("re-linking focus via the `units` section restores target's alpha", function()
    -- The same missing rebuild in the other direction.
    local inst, NS = enabledWithFocus()
    NS.db.profile.units.focus.link = false
    icons(NS, "target").cooldownAlpha = 0.20
    icons(NS, "focus").cooldownAlpha  = 0.90
    fireConfigChanged(NS, "icons")
    assertEqual(renderedAlpha(inst, "focus"), 0.90, "precondition: unlinked")

    NS.db.profile.units.focus.link = true
    fireConfigChanged(NS, "units")

    assertEqual(renderedAlpha(inst, "focus"), 0.20,
        "after re-linking, focus must render with target's cooldownAlpha")
end)

test("unlinking picks up focus's own cooldown TINT, not target's", function()
    local inst, NS = enabledWithFocus()
    NS.db.profile.units.focus.link = true
    icons(NS, "target").cooldownTint = { 1, 0, 0, 1 }   -- red
    icons(NS, "focus").cooldownTint  = { 0, 0, 1, 1 }   -- blue
    fireConfigChanged(NS, "icons")

    NS.db.profile.units.focus.link = false
    fireConfigChanged(NS, "units")

    local icon = makeIcon(inst, "focus")
    icon:Apply({
        spellID = 192058, ready = false, isActive = true,
        cdObject = inst.mocks.__makeDurationObject(ON_COOLDOWN),
    })
    local r, g, b = icon.icon:GetVertexColor()
    assertEqual(b, 1, "focus must tint with its own blue")
    assertEqual(r, 0, "focus must not carry target's red")
    assertTrue(g == 0, "focus green channel must be its own")
end)

test("a per-unit enable toggle also refreshes curves", function()
    -- `units` covers the per-unit enable flags too, not just `link`. A focus
    -- enabled after its appearance was edited must not come up with a curve
    -- built from a stale resolution.
    local inst, NS, IconGrid = enabledWithFocus()
    NS.db.profile.units.focus.link = false
    NS.db.profile.units.focus.enabled = false
    IconGrid:ReconcileUnits()

    icons(NS, "focus").cooldownAlpha = 0.75
    NS.db.profile.units.focus.enabled = true
    fireConfigChanged(NS, "units")

    assertEqual(renderedAlpha(inst, "focus"), 0.75,
        "a newly-enabled focus must render with its own configured alpha")
end)
