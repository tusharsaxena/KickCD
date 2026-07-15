-- tests/test_units.lua — NS.Units link/enable/config resolution (core/Units.lua)

local T = _G.KICKCD_TEST

local NS = T.NS

local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue



test("Units.LIST is target then focus", function()

    assertEqual(NS.Units.LIST[1], "target")

    assertEqual(NS.Units.LIST[2], "focus")

end)



test("target is never linked; focus honors its link flag", function()

    assertEqual(NS.Units.IsLinked("target"), false)

    NS.db.profile.units.focus.link = true

    assertEqual(NS.Units.IsLinked("focus"), true)

    NS.db.profile.units.focus.link = false

    assertEqual(NS.Units.IsLinked("focus"), false)

end)



test("Icons(focus) resolves to target's icons when linked", function()

    NS.db.profile.units.target.icons.primarySize = 70

    NS.db.profile.units.focus.icons.primarySize  = 30

    NS.db.profile.units.focus.link = true

    assertEqual(NS.Units.Icons("focus").primarySize, 70, "linked focus reads target icons")

    NS.db.profile.units.focus.link = false

    assertEqual(NS.Units.Icons("focus").primarySize, 30, "unlinked focus reads its own icons")

end)



test("IsEnabled combines master and per-unit enable", function()

    NS.db.profile.enabled = true

    NS.db.profile.units.target.enabled = true

    NS.db.profile.units.focus.enabled  = false

    assertEqual(NS.Units.IsEnabled("target"), true)

    assertEqual(NS.Units.IsEnabled("focus"), false)

    NS.db.profile.enabled = false

    assertEqual(NS.Units.IsEnabled("target"), false, "master off disables all units")

    NS.db.profile.enabled = true

end)



test("CopyStyling snapshots target appearance into focus and unlinks", function()

    NS.db.profile.units.target.icons.primarySize = 55

    NS.db.profile.units.focus.link = true

    NS.Units.CopyStyling("target", "focus")

    assertEqual(NS.db.profile.units.focus.link, false, "copy unlinks")

    assertEqual(NS.db.profile.units.focus.icons.primarySize, 55, "focus gets a copy of target size")

    -- mutating the copy must not affect the source (deep copy, not alias)

    NS.db.profile.units.focus.icons.primarySize = 999

    assertEqual(NS.db.profile.units.target.icons.primarySize, 55, "copy is deep, not aliased")

end)



test("Label.text is per-unit and not link-resolved", function()

    NS.db.profile.units.focus.link = true

    assertEqual(NS.Units.Label("focus").text, "Focus")

    assertEqual(NS.Units.Label("target").text, "Target")

end)

