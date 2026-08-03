-- tests/test_unitlabel_apply.lua — what UnitLabel:Apply actually renders.
--
-- The existing test_unitlabel.lua checks that Apply runs and picks the right
-- PARENT. This suite covers the rest, which the stateful frame mock made
-- reachable: the text, font, color and justification it writes, the anchor
-- it positions against, and the show/hide decision.
--
-- The load-bearing oddity is that position and visibility come from DIFFERENT
-- frames: the label is SetPoint'd to the user's chosen attach widget but
-- reparented onto the icon grid, so it inherits the grid's General-visibility
-- show state rather than the cast bar's cast-gated one. Parenting it to the
-- cast bar instead would make the label blink with every cast.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function enabled()
    local inst = T.load(true, true)
    return inst.NS, inst.NS:GetModule("UnitLabel")
end

--- Apply the label for `unit` after mutating its style, and hand back the
--- instance so a test can read the rendered widgets.
local function applied(NS, UnitLabel, unit, styleOver, labelOver)
    local style = NS.Units.LabelStyle(unit)
    for k, v in pairs(styleOver or {}) do style[k] = v end
    local lbl = NS.Units.Label(unit)
    for k, v in pairs(labelOver or {}) do lbl[k] = v end
    local inst = UnitLabel:GetInstance(unit)
    UnitLabel:Apply(inst)
    return inst
end

-- ── Text ────────────────────────────────────────────────────────────────────

test("Apply writes the unit's own label text", function()
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target", nil, { text = "TARGET" })
    assertEqual(inst.text:GetText(), "TARGET")
end)

test("Apply writes an empty string rather than nil for a cleared label", function()
    -- SetText(nil) leaves the previous text on screen, so a user who clears
    -- the field would see the old value until reload.
    local NS, UnitLabel = enabled()
    local inst = UnitLabel:GetInstance("target")
    NS.Units.Label("target").text = nil
    UnitLabel:Apply(inst)
    assertEqual(inst.text:GetText(), "")
end)

test("label TEXT stays per-unit even when the units are linked", function()
    -- Styling links; text deliberately does not (spec 2a/2b). A linked focus
    -- showing "Target" would be actively misleading.
    local NS, UnitLabel = enabled()
    NS.db.profile.units.focus.link = true
    local t = applied(NS, UnitLabel, "target", nil, { text = "T" })
    local f = applied(NS, UnitLabel, "focus", nil, { text = "F" })
    assertEqual(t.text:GetText(), "T")
    assertEqual(f.text:GetText(), "F")
end)

-- ── Appearance ──────────────────────────────────────────────────────────────

test("Apply pushes the configured size and color onto the FontString", function()
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target",
        { size = 22, color = { 0.1, 0.2, 0.3, 0.4 } })
    local _, size = inst.text:GetFont()
    assertEqual(size, 22)
    local r, g, b, a = inst.text:GetTextColor()
    assertEqual(r, 0.1); assertEqual(g, 0.2); assertEqual(b, 0.3); assertEqual(a, 0.4)
end)

test("Apply always resolves a non-nil font path", function()
    -- SetFont with a nil path errors and takes the label build with it.
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target", { font = "No Such Font" })
    local path = inst.text:GetFont()
    assertTrue(type(path) == "string" and #path > 0)
end)

test("Apply falls back to a 14pt outline for a style with no size or flags", function()
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target", { size = false, flags = false })
    local style = NS.Units.LabelStyle("target")
    style.size, style.flags = nil, nil
    UnitLabel:Apply(inst)
    local _, size, flags = inst.text:GetFont()
    assertEqual(size, 14)
    assertEqual(flags, "OUTLINE")
end)

test("Apply applies the configured horizontal justification", function()
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target", { justifyH = "LEFT" })
    assertEqual(inst.text:GetJustifyH(), "LEFT")
end)

test("Apply defaults justification to CENTER", function()
    local NS, UnitLabel = enabled()
    local inst = UnitLabel:GetInstance("target")
    local style = NS.Units.LabelStyle("target")
    style.justifyH = nil
    UnitLabel:Apply(inst)
    assertEqual(inst.text:GetJustifyH(), "CENTER")
end)

test("a LINKED focus renders target's styling but its own text", function()
    -- The link resolves appearance only — the exact split spec 2a/2b defines.
    local NS, UnitLabel = enabled()
    NS.db.profile.units.focus.link = true
    applied(NS, UnitLabel, "target", { size = 27 })
    local f = applied(NS, UnitLabel, "focus", nil, { text = "FOCUS" })
    local _, size = f.text:GetFont()
    assertEqual(size, 27, "a linked focus inherits target's size")
    assertEqual(f.text:GetText(), "FOCUS")
end)

-- ── Anchoring vs parenting ──────────────────────────────────────────────────

test("Apply positions the label against its chosen ATTACH frame", function()
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target",
        { attach = "icons", point = "TOP", relPoint = "BOTTOM", offsetX = 3, offsetY = -6 })
    local grid = NS:GetModule("IconGrid"):GetGridFrame("target")
    local point, relativeTo, relPoint, x, y = inst.frame:GetPoint(1)
    assertEqual(point, "TOP")
    assertTrue(rawequal(relativeTo, grid))
    assertEqual(relPoint, "BOTTOM")
    assertEqual(x, 3); assertEqual(y, -6)
end)

test("Apply parents the label to the ICON GRID even when attached to the cast bar", function()
    -- The whole point of the split: the grid honors General visibility, the
    -- cast bar additionally hides whenever nothing is being cast. Parenting to
    -- the cast bar would make the label cast-gated.
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target", { attach = "castbar" })
    local grid    = NS:GetModule("IconGrid"):GetGridFrame("target")
    local castbar = NS:GetModule("Castbar"):GetCastbarFrame("target")
    assertTrue(rawequal(inst.frame:GetParent(), grid))
    assertFalse(rawequal(inst.frame:GetParent(), castbar))
end)

test("Apply anchors POSITION to the cast bar while parenting to the grid", function()
    -- Position and visibility genuinely come from two different frames.
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target", { attach = "castbar" })
    local castbar = NS:GetModule("Castbar"):GetCastbarFrame("target")
    local _, relativeTo = inst.frame:GetPoint(1)
    assertTrue(rawequal(relativeTo, castbar))
end)

test("re-applying never stacks anchors on the holder frame", function()
    -- Apply runs on every config change, profile change and grid layout.
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target", { attach = "icons" })
    UnitLabel:Apply(inst)
    UnitLabel:Apply(inst)
    assertEqual(inst.frame:GetNumPoints(), 1)
end)

-- ── Show / hide ─────────────────────────────────────────────────────────────

test("the label shows when the unit is enabled and show is on", function()
    local NS, UnitLabel = enabled()
    NS.db.profile.enabled = true
    NS.db.profile.units.target.enabled = true
    local inst = applied(NS, UnitLabel, "target", { attach = "icons" }, { show = true })
    assertTrue(inst.frame:IsShown())
end)

test("turning the label's show off hides it", function()
    local NS, UnitLabel = enabled()
    local inst = applied(NS, UnitLabel, "target", { attach = "icons" }, { show = false })
    assertFalse(inst.frame:IsShown())
end)

test("disabling the unit hides its label regardless of the show flag", function()
    local NS, UnitLabel = enabled()
    NS.db.profile.units.target.enabled = false
    local inst = applied(NS, UnitLabel, "target", { attach = "icons" }, { show = true })
    assertFalse(inst.frame:IsShown())
    NS.db.profile.units.target.enabled = true
end)

test("the master enable gates the label too", function()
    local NS, UnitLabel = enabled()
    NS.db.profile.enabled = false
    local inst = applied(NS, UnitLabel, "target", { attach = "icons" }, { show = true })
    assertFalse(inst.frame:IsShown())
    NS.db.profile.enabled = true
end)

test("a LINKED focus mirrors target's show flag (spec 2b)", function()
    -- Hiding the target label must hide a linked focus label too, or the user
    -- has to hunt for a second checkbox that looks like it did nothing.
    local NS, UnitLabel = enabled()
    NS.db.profile.enabled = true
    NS.db.profile.units.focus.enabled = true
    NS.db.profile.units.focus.link = true
    NS.Units.Label("target").show = false
    local f = applied(NS, UnitLabel, "focus", { attach = "icons" })
    assertFalse(f.frame:IsShown())
end)

-- ── Frame construction ──────────────────────────────────────────────────────

test("EnsureFrame builds the holder once and reuses it", function()
    local _, UnitLabel = enabled()
    local inst = UnitLabel:GetInstance("target")
    UnitLabel:EnsureFrame(inst)
    local frame, text = inst.frame, inst.text
    UnitLabel:EnsureFrame(inst)
    assertTrue(rawequal(inst.frame, frame))
    assertTrue(rawequal(inst.text, text))
end)

test("target and focus each get their own label widgets", function()
    local _, UnitLabel = enabled()
    local t = UnitLabel:GetInstance("target")
    local f = UnitLabel:GetInstance("focus")
    UnitLabel:EnsureFrame(t)
    UnitLabel:EnsureFrame(f)
    assertFalse(rawequal(t.frame, f.frame))
    assertFalse(rawequal(t.text, f.text))
end)

test("ApplyAll renders every unit in one pass", function()
    local NS, UnitLabel = enabled()
    NS.Units.Label("target").text = "T"
    NS.Units.Label("focus").text = "F"
    UnitLabel:ApplyAll()
    assertEqual(UnitLabel:GetInstance("target").text:GetText(), "T")
    assertEqual(UnitLabel:GetInstance("focus").text:GetText(), "F")
end)
