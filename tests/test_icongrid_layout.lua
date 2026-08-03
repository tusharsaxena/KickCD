-- tests/test_icongrid_layout.lua — pure geometry peeled into IconGrid_Layout.lua (KCD-05)
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local IconGrid = NS:GetModule("IconGrid")
local Layout = IconGrid.LayoutMath

test("Layout math is published on the IconGrid module", function()
    assertTrue(Layout ~= nil, "IconGrid.LayoutMath must exist")
    assertTrue(type(Layout.parseAnchor) == "function")
    assertTrue(type(Layout.parseGrow) == "function")
    assertTrue(type(Layout.placeBlock) == "function")
    assertTrue(type(Layout.layoutBlock) == "function")
end)

-- Regression (KCD-05 peel): the geometry table must NOT be published under the
-- same key as the IconGrid:Layout() method, or the sibling file clobbers the
-- method and every self:Layout() call (OnEnable, config/profile handlers) dies
-- with "attempt to call a nil value". Keep the method callable AND the math
-- reachable — they live on distinct keys.
test("IconGrid:Layout method survives alongside the geometry table", function()
    assertTrue(type(IconGrid.Layout) == "function", "IconGrid:Layout must stay a callable method")
    assertTrue(IconGrid.LayoutMath ~= IconGrid.Layout, "method and geometry table must be distinct keys")
end)

test("parseAnchor normalizes modern, legacy, and CENTER tokens", function()
    local s, a = Layout.parseAnchor("CENTER");        assertEqual(s, "CENTER"); assertEqual(a, "CENTER")
    s, a = Layout.parseAnchor("RIGHT_MIDDLE");        assertEqual(s, "RIGHT");  assertEqual(a, "CENTER")
    s, a = Layout.parseAnchor("RIGHT_CENTER");        assertEqual(s, "RIGHT");  assertEqual(a, "CENTER")
    s, a = Layout.parseAnchor("TOP_LEFT");            assertEqual(s, "TOP");    assertEqual(a, "LEFT")
    s, a = Layout.parseAnchor("LEFT_TOP");            assertEqual(s, "LEFT");   assertEqual(a, "TOP")
end)

test("parseAnchor rejects invalid combos with the RIGHT/CENTER default", function()
    -- LEFT side can't take a LEFT align (that's a same-axis nonsense combo)
    local s, a = Layout.parseAnchor("LEFT_LEFT");     assertEqual(s, "RIGHT"); assertEqual(a, "CENTER")
    s, a = Layout.parseAnchor("garbage");             assertEqual(s, "RIGHT"); assertEqual(a, "CENTER")
    s, a = Layout.parseAnchor(nil);                   assertEqual(s, "RIGHT"); assertEqual(a, "CENTER")
end)

test("parseGrow accepts perpendicular axes and defaults otherwise", function()
    local p, sec = Layout.parseGrow("right_down");    assertEqual(p, "right"); assertEqual(sec, "down")
    p, sec = Layout.parseGrow("up_left");             assertEqual(p, "up");    assertEqual(sec, "left")
    -- both-horizontal is invalid → default
    p, sec = Layout.parseGrow("right_left");          assertEqual(p, "right"); assertEqual(sec, "down")
    p, sec = Layout.parseGrow("nonsense");            assertEqual(p, "right"); assertEqual(sec, "down")
end)

test("placeBlock RIGHT/CENTER geometry (primary left, block right, centered)", function()
    local gW, gH, pX, pY, bX, bY = Layout.placeBlock("RIGHT", "CENTER", 64, 20, 20, 4)
    assertEqual(gW, 88, "grid width = primary + gap + block")   -- 64+4+20
    assertEqual(gH, 64, "grid height = max(primary, block)")
    assertEqual(pX, 0);  assertEqual(pY, 0)
    assertEqual(bX, 68, "block sits right of primary+gap")       -- 64+4
    assertEqual(bY, 22, "block vertically centered")              -- floor((64-20)/2)
end)

test("placeBlock TOP/CENTER geometry (block above primary)", function()
    local gW, gH, pX, pY, bX, bY = Layout.placeBlock("TOP", "CENTER", 64, 40, 20, 4)
    assertEqual(gW, 64); assertEqual(gH, 88)  -- 20+4+64
    assertEqual(bY, 0);  assertEqual(pY, 24)  -- primary below block+gap
    assertEqual(pX, 0);  assertEqual(bX, 12)  -- floor((64-40)/2)
end)

test("placeBlock CENTER stacks both on the grid center", function()
    local gW, gH, pX, pY, bX, bY = Layout.placeBlock("CENTER", "CENTER", 64, 20, 20, 4)
    assertEqual(gW, 64); assertEqual(gH, 64)
    assertEqual(pX, 0);  assertEqual(pY, 0)
    assertEqual(bX, 22); assertEqual(bY, 22)  -- floor((64-20)/2)
end)
