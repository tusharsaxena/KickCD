-- tests/test_icongrid_layout_pass.lua — IconGrid:Layout, the pass that binds and places the icons
--
-- Characterization coverage written green against the pre-split IconGrid:Layout (CCN 29 under the
-- sighted complexity gate, GI-KC-12), so its split below CCN 15 is checked rather than assumed.
-- The geometry itself is IconGrid.LayoutMath's and is pinned in tests/test_icongrid_layout.lua;
-- these cases drive the method with a fake grid, fake buttons and a spied layoutBlock, and pin
-- what the method decides: the config defaults, the per-button binding, the empty-list size, the
-- truncation warning's dedup and re-arm, and the GRID_LAYOUT payload.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

local function fakeButton()
    local b = { calls = {} }
    function b:Show() self.calls[#self.calls + 1] = "Show" end
    function b:ApplyAppearance(cfg) self.calls[#self.calls + 1] = "ApplyAppearance"; self.appearanceCfg = cfg end
    function b:ApplyTextConfig(cfg)
        -- _isPrimary is stamped BEFORE ApplyTextConfig, because Apply reads it through the glow.
        self.calls[#self.calls + 1] = "ApplyTextConfig"; self.textCfg = cfg; self.primaryAtText = self._isPrimary
    end
    return b
end

--- A fresh addon, the IconGrid module and a synthetic instance over `n` fake buttons. `cfg` is
--- what NS.Units.Icons answers; `layout` is what the spied layoutBlock returns (w, h, truncated).
--- Every print, GRID_LAYOUT send and layoutBlock call is recorded on the returned spy.
local function harness(n, cfg, layout)
    local inst = T.load(true, true)
    local NS = inst.NS
    local IconGrid = NS:GetModule("IconGrid")
    local spy = { sizes = {}, prints = {}, sends = {}, blocks = {} }
    local grid = { SetSize = function(_, w, h) spy.sizes[#spy.sizes + 1] = { w, h } end }
    local ordered = {}
    for i = 1, n do ordered[i] = fakeButton() end
    local gi = { grid = grid, unit = "target", ordered = ordered }

    NS.Units.Icons = function(unit) spy.iconsUnit = unit; return cfg end
    NS.Util.print = function(msg) spy.prints[#spy.prints + 1] = msg end
    NS.SendMessage = function(_, msg, payload)
        if msg == NS.MSG.GRID_LAYOUT then spy.sends[#spy.sends + 1] = payload end
    end
    local LM = IconGrid.LayoutMath
    local realBlock = LM.layoutBlock
    LM.layoutBlock = function(...)
        spy.blocks[#spy.blocks + 1] = { ... }
        return layout[1], layout[2], layout[3]
    end
    spy.restore = function() LM.layoutBlock = realBlock end
    return IconGrid, gi, spy, NS, inst.mocks
end

--- Run fn and restore layoutBlock whatever happens.
local function run(spy, fn)
    local ok, err = pcall(fn)
    spy.restore()
    if not ok then error(err, 0) end
end

test("Layout returns at once when the instance has no grid frame", function()
    local IconGrid, gi, spy = harness(2, {}, { 1, 1, 0 })
    gi.grid = nil
    run(spy, function() IconGrid:Layout(gi) end)
    assertNil(spy.iconsUnit, "no config read without a grid")
    assertEqual(#spy.blocks, 0)
    assertEqual(#spy.sends, 0)
end)

test("Layout re-reads the unit's config and binds every button, primary first", function()
    local cfg = { primarySize = 40 }
    local IconGrid, gi, spy = harness(3, cfg, { 100, 50, 0 })
    run(spy, function() IconGrid:Layout(gi) end)
    assertEqual(spy.iconsUnit, "target")
    assertTrue(gi.cfg == cfg, "inst.cfg is the fresh read")
    for i, b in ipairs(gi.ordered) do
        assertTrue(b.cfg == cfg, "button " .. i .. " carries the cfg")
        assertEqual(b.unit, "target")
        assertTrue(b.instance == gi)
        assertEqual(b._isPrimary, i == 1, "only slot 1 is primary")
        assertEqual(b.primaryAtText, i == 1, "the slot flag is stamped before ApplyTextConfig")
        assertEqual(table.concat(b.calls, ","), "Show,ApplyAppearance,ApplyTextConfig")
        assertTrue(b.appearanceCfg == cfg and b.textCfg == cfg)
    end
end)

test("Layout resolves every unset config field to its default", function()
    local IconGrid, gi, spy = harness(2, nil, { 10, 20, 0 })
    run(spy, function() IconGrid:Layout(gi) end)
    local a = spy.blocks[1]
    assertTrue(a ~= nil, "layoutBlock was called")
    assertTrue(a[1] == gi.grid and a[2] == gi.ordered[1], "grid, then the primary")
    assertEqual(#a[3], 1, "the secondaries are every icon after the first")
    assertTrue(a[3][1] == gi.ordered[2])
    assertEqual(a[4], 48, "primarySize")
    assertEqual(a[5], math.floor(48 * 0.7), "secondarySize")
    assertEqual(a[6], 4, "gap")
    assertEqual(a[7], "RIGHT_MIDDLE", "anchor")
    assertEqual(a[8], "right_down", "grow")
    assertEqual(a[9], 1, "rows")
    assertEqual(a[10], 6, "cols")
    assertEqual(a[11], 0, "offX")
    assertEqual(a[12], 0, "offY")
end)

test("Layout passes every configured field through", function()
    local cfg = { primarySize = 50, secondarySize = 0.5, gap = 2, anchor = "TOP_LEFT",
                  secondaryGrow = "down_right", secondaryRows = 3, secondaryCols = 2,
                  secondaryOffsetX = 7, secondaryOffsetY = -3 }
    local IconGrid, gi, spy = harness(1, cfg, { 10, 20, 0 })
    run(spy, function() IconGrid:Layout(gi) end)
    local a = spy.blocks[1]
    assertEqual(#a[3], 0, "a single icon has no secondaries")
    assertEqual(a[4], 50); assertEqual(a[5], 25); assertEqual(a[6], 2)
    assertEqual(a[7], "TOP_LEFT"); assertEqual(a[8], "down_right")
    assertEqual(a[9], 3); assertEqual(a[10], 2); assertEqual(a[11], 7); assertEqual(a[12], -3)
end)

test("an empty list keeps the frame at primary size and announces no primary", function()
    local IconGrid, gi, spy = harness(0, { primarySize = 36 }, { 1, 1, 0 })
    run(spy, function() IconGrid:Layout(gi) end)
    assertEqual(#spy.blocks, 0, "no block layout for an empty list")
    assertEqual(#spy.sizes, 1)
    assertEqual(spy.sizes[1][1], 36); assertEqual(spy.sizes[1][2], 36)
    assertEqual(#spy.sends, 1)
    local p = spy.sends[1]
    assertEqual(p.unit, "target"); assertTrue(p.gridFrame == gi.grid)
    assertNil(p.primaryIcon); assertEqual(p.width, 36); assertEqual(p.height, 36)
end)

test("a laid-out grid takes the block's size and announces the primary with it", function()
    local IconGrid, gi, spy = harness(2, {}, { 120, 60, 0 })
    run(spy, function() IconGrid:Layout(gi) end)
    assertEqual(spy.sizes[1][1], 120); assertEqual(spy.sizes[1][2], 60)
    assertEqual(#spy.sends, 1)
    local p = spy.sends[1]
    assertTrue(p.primaryIcon == gi.ordered[1] and p.gridFrame == gi.grid)
    assertEqual(p.unit, "target"); assertEqual(p.width, 120); assertEqual(p.height, 60)
    assertEqual(#spy.prints, 0, "no truncation, no warning")
end)

test("a truncated grid warns once per class/spec/cap, and re-arms when the cap changes", function()
    local cfg = { secondaryRows = 2, secondaryCols = 3 }
    local IconGrid, gi, spy, NS, mocks = harness(2, cfg, { 10, 10, 4 })
    run(spy, function()
        IconGrid:Layout(gi)
        IconGrid:Layout(gi)
        assertEqual(#spy.prints, 1, "the same overflow warns once")
        local cls = NS.Util.NormalizeClassToken(select(2, mocks.UnitClass("player")))
        local key = cls .. "/" .. tostring(NS.Util.PlayerSpecID())
        assertEqual(spy.prints[1], ("dropped 4 icon(s) past the 6-slot grid for %s — bump rows*cols or remove spells")
            :format(key))
        assertEqual(gi.truncationWarnedFor, key .. "/6")
        cfg.secondaryCols = 4
        IconGrid:Layout(gi)
        assertEqual(#spy.prints, 2, "a new cap re-arms the warning")
        assertEqual(gi.truncationWarnedFor, key .. "/8")
    end)
end)

test("a pass with no truncation clears the dedup key so a later overflow warns again", function()
    local IconGrid, gi, spy = harness(2, { secondaryRows = 1, secondaryCols = 1 }, { 10, 10, 2 })
    run(spy, function()
        IconGrid:Layout(gi)
        assertEqual(#spy.prints, 1)
        spy.restore()
        local LM = IconGrid.LayoutMath
        local real = LM.layoutBlock
        LM.layoutBlock = function() return 10, 10, 0 end
        IconGrid:Layout(gi)
        assertNil(gi.truncationWarnedFor, "a clean pass clears the key")
        LM.layoutBlock = function() return 10, 10, nil end
        gi.truncationWarnedFor = "stale"
        IconGrid:Layout(gi)
        assertNil(gi.truncationWarnedFor, "a nil truncation count clears it too")
        LM.layoutBlock = function() return 10, 10, 2 end
        IconGrid:Layout(gi)
        assertEqual(#spy.prints, 2, "the overflow warns again")
        LM.layoutBlock = real
    end)
end)

test("the warning names ?/? when the player's class cannot be read", function()
    local IconGrid, gi, spy, _, mocks = harness(2, { secondaryRows = 1, secondaryCols = 2 }, { 10, 10, 1 })
    local realClass = mocks.UnitClass
    mocks.UnitClass = function() return nil, nil end
    local ok, err = pcall(function()
        run(spy, function() IconGrid:Layout(gi) end)
    end)
    mocks.UnitClass = realClass
    assertTrue(ok, tostring(err))
    assertTrue(spy.prints[1] and spy.prints[1]:find("2-slot grid for ?/?", 1, true) ~= nil,
        "got: " .. tostring(spy.prints[1]))
    assertEqual(gi.truncationWarnedFor, "?/?/2")
end)
