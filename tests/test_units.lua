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

