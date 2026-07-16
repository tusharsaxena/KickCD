-- tests/test_units.lua — NS.Units link/enable/config resolution (core/Units.lua)

local T = _G.KICKCD_TEST

local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue



test("Units.LIST is target then focus", function()

    local ns = T.load(true).NS

    assertEqual(ns.Units.LIST[1], "target")

    assertEqual(ns.Units.LIST[2], "focus")

end)



test("target is never linked; focus honors its link flag", function()

    local ns = T.load(true).NS

    assertEqual(ns.Units.IsLinked("target"), false)

    ns.db.profile.units.focus.link = true

    assertEqual(ns.Units.IsLinked("focus"), true)

    ns.db.profile.units.focus.link = false

    assertEqual(ns.Units.IsLinked("focus"), false)

end)



test("Icons(focus) resolves to target's icons when linked", function()

    local ns = T.load(true).NS

    ns.db.profile.units.target.icons.primarySize = 70

    ns.db.profile.units.focus.icons.primarySize  = 30

    ns.db.profile.units.focus.link = true

    assertEqual(ns.Units.Icons("focus").primarySize, 70, "linked focus reads target icons")

    ns.db.profile.units.focus.link = false

    assertEqual(ns.Units.Icons("focus").primarySize, 30, "unlinked focus reads its own icons")

end)



test("IsEnabled combines master and per-unit enable", function()

    local ns = T.load(true).NS

    ns.db.profile.enabled = true

    ns.db.profile.units.target.enabled = true

    ns.db.profile.units.focus.enabled  = false

    assertEqual(ns.Units.IsEnabled("target"), true)

    assertEqual(ns.Units.IsEnabled("focus"), false)

    ns.db.profile.enabled = false

    assertEqual(ns.Units.IsEnabled("target"), false, "master off disables all units")

    ns.db.profile.enabled = true

end)



test("CopyStyling snapshots target appearance into focus and unlinks", function()

    local ns = T.load(true).NS

    ns.db.profile.units.target.icons.primarySize = 55

    ns.db.profile.units.focus.link = true

    ns.Units.CopyStyling("target", "focus")

    assertEqual(ns.db.profile.units.focus.link, false, "copy unlinks")

    assertEqual(ns.db.profile.units.focus.icons.primarySize, 55, "focus gets a copy of target size")

    -- mutating the copy must not affect the source (deep copy, not alias)

    ns.db.profile.units.focus.icons.primarySize = 999

    assertEqual(ns.db.profile.units.target.icons.primarySize, 55, "copy is deep, not aliased")

end)



test("Label.text is per-unit and not link-resolved", function()

    local ns = T.load(true).NS

    ns.db.profile.units.focus.link = true

    assertEqual(ns.Units.Label("focus").text, "Focus")

    assertEqual(ns.Units.Label("target").text, "Target")

end)



test("IconGrid:ReconcileUnits enables focus once units.focus.enabled is true", function()

    local inst = T.load(true, true)

    local ns = inst.NS

    local ig = ns:GetModule("IconGrid")

    assertEqual(ns.Units.IsEnabled("focus"), false, "focus starts disabled by default")

    assertEqual(ig:GetInstance("focus").enabled, false, "focus instance starts not live")

    ns.db.profile.units.focus.enabled = true

    ig:ReconcileUnits()

    assertEqual(ns.Units.IsEnabled("focus"), true, "focus reports enabled once its flag flips")

    assertEqual(ig:GetInstance("focus").enabled, true, "focus instance is live after reconcile")

    assertEqual(ig:GetInstance("target").enabled, true, "target stays live and untouched")

end)



test("Castbar:ReconcileUnits mirrors IconGrid's enable/disable transitions", function()

    local inst = T.load(true, true)

    local ns = inst.NS

    local cb = ns:GetModule("Castbar")

    ns.db.profile.units.focus.enabled = true

    cb:ReconcileUnits()

    assertEqual(cb:GetInstance("focus").enabled, true, "focus bar instance goes live")

    ns.db.profile.units.focus.enabled = false

    cb:ReconcileUnits()

    assertEqual(cb:GetInstance("focus").enabled, false, "focus bar instance goes down again")

end)



test("master-enable off then on disables then revives both units without a reload", function()

    local inst = T.load(true, true)

    local ns = inst.NS

    local ig = ns:GetModule("IconGrid")

    local cb = ns:GetModule("Castbar")

    assertEqual(ig:GetInstance("target").enabled, true, "target grid starts live")

    assertEqual(cb:GetInstance("target").enabled, true, "target bar starts live")

    ns.db.profile.enabled = false

    ns:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "general" })

    assertEqual(ns.Units.IsEnabled("target"), false, "master off disables the unit")

    assertEqual(ig:GetInstance("target").enabled, false, "master off tears down the live grid instance")

    assertEqual(cb:GetInstance("target").enabled, false, "master off tears down the live bar instance")

    ns.db.profile.enabled = true

    ns:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "general" })

    assertEqual(ns.Units.IsEnabled("target"), true, "master back on re-enables the unit")

    assertEqual(ig:GetInstance("target").enabled, true, "master back on revives the grid instance without /reload")

    assertEqual(cb:GetInstance("target").enabled, true, "master back on revives the bar instance without /reload")

end)



test("LabelStyle resolves to target's style when focus is linked", function()
    local NS = T.load(true).NS
    NS.db.profile.units.target.label.style.size = 20
    NS.db.profile.units.focus.label.style.size  = 8
    NS.db.profile.units.focus.link = true
    assertEqual(NS.Units.LabelStyle("focus").size, 20, "linked focus reads target style")
    NS.db.profile.units.focus.link = false
    assertEqual(NS.Units.LabelStyle("focus").size, 8, "unlinked focus reads its own style")
end)



test("CopyStyling snapshots target label.style but keeps focus text/show", function()
    local NS = T.load(true).NS
    NS.db.profile.units.target.label.style.size = 17
    NS.db.profile.units.focus.label.show = true
    NS.db.profile.units.focus.label.text = "MINE"
    NS.db.profile.units.focus.link = true
    NS.Units.CopyStyling("target", "focus")
    assertEqual(NS.db.profile.units.focus.link, false, "copy unlinks")
    assertEqual(NS.db.profile.units.focus.label.style.size, 17, "focus got a copy of target style")
    assertEqual(NS.db.profile.units.focus.label.text, "MINE", "per-unit text preserved")
    assertEqual(NS.db.profile.units.focus.label.show, true,  "per-unit show preserved")
    NS.db.profile.units.focus.label.style.size = 99
    assertEqual(NS.db.profile.units.target.label.style.size, 17, "copy is deep, not aliased")
end)

