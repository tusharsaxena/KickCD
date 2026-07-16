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
