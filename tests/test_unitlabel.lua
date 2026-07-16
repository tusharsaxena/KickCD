-- tests/test_unitlabel.lua — UnitLabel module load + resolver wiring.
-- The FontString rendering itself is smoke-tested in-game (the headless
-- mock's frames are no-ops); here we assert the module loaded, registered,
-- and resolves its label data through NS.Units without error.
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("UnitLabel module is registered", function()
    assertTrue(NS:GetModule("UnitLabel", true) ~= nil, "UnitLabel module must exist")
end)

test("UnitLabel.ApplyAll runs without error for both units", function()
    local ns = T.load(true).NS
    local m = ns:GetModule("UnitLabel", true)
    ns.db.profile.units.focus.enabled = true
    local ok, err = pcall(function() m:ApplyAll() end)
    assertTrue(ok, "ApplyAll must not error: " .. tostring(err))
end)

test("Castbar:GetCastbarFrame does not create an instance for an unknown unit", function()
    local cb = NS:GetModule("Castbar", true)
    assertEqual(cb:GetCastbarFrame("nonexistent"), nil)
end)

test("UnitLabel:Apply parents the label to the icon grid, not the cast bar (General-visibility, not cast-gated)", function()
    local ns = T.load(true).NS
    local grid, castbar, label = ns:GetModule("IconGrid", true), ns:GetModule("Castbar", true), ns:GetModule("UnitLabel", true)
    local gridF, castF = {}, {}
    local origGetGridFrame, origGetCastbarFrame = grid.GetGridFrame, castbar.GetCastbarFrame
    grid.GetGridFrame = function(_, unit) return unit == "target" and gridF or nil end
    castbar.GetCastbarFrame = function(_, unit) return unit == "target" and castF or nil end

    ns.db.profile.units.target.label.style.attach = "castbar"
    ns.db.profile.units.target.label.show = true
    local inst = label:GetInstance("target")
    label:Apply(inst)

    assertEqual(inst.frame:GetParent(), gridF, "label must parent to the grid so it follows General visibility")
    assertTrue(inst.frame:GetParent() ~= castF, "label must NOT parent to the cast bar (would be cast-gated)")

    grid.GetGridFrame, castbar.GetCastbarFrame = origGetGridFrame, origGetCastbarFrame
end)
