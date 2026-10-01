-- tests/test_settings_spells_grid.lua — the Spells list draws through H.RenderGrid (KickCD#10)
--
-- The list used to be a hand loop over scroll:AddChild. It now hands one wide item per entry to
-- the library's RenderGrid with `{ gap = false }`, so the page shares the grid's per-item guard
-- and its row group instead of keeping a second loop of its own. What has to survive that move:
--
--   * the strip looks the same: one group per entry, stacked with NO spacer between them, because
--     ReorderList's drop math is arithmetic on a 28px stride (options-ui-§18) and RenderGrid's
--     default 8px gap after every row would put every drop one slot off by the fourth row;
--   * the group the reorder controller is handed is the one the scroll's List layout stacks, and
--     it is exactly Spells.ROW_HEIGHT tall;
--   * a row that cannot be built leaves no blank group behind;
--   * the empty list still says what to do.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local SHAMAN_CLASS_ID = 7

--- A fully-enabled Elemental Shaman with every Settings panel shown, so RefreshRows passes its
--- `panel:IsShown()` gate (the same fixture tests/test_settings_spells_editor.lua uses).
local function editorInstance()
    local inst = T.load(true, true, function(mocks)
        mocks.UnitClass = function() return "Shaman", "SHAMAN", SHAMAN_CLASS_ID end
        mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 1)
    end)
    for _, ctx in ipairs(inst.NS.Settings.Helpers.__panels()) do ctx.panel:Show() end
    local p = inst.NS.Settings.SpellsPanel
    p:SeedSelectionToPlayer()
    return inst, p
end

local function activeList(inst)
    local class, spec = inst.NS.Settings.SpellsPanel:GetSelection()
    return inst.NS.Database:GetSpellList(class, spec)
end

local function spellsCtx(inst)
    for _, c in ipairs(inst.NS.Settings.Helpers.__panels()) do
        if c.pageKey == "spells" then return c end
    end
end

--- Run fn with H.RenderGrid spied: every call's (ctx, items, parent, opts) is recorded and the
--- real grid still draws.
local function spyGrid(inst, fn)
    local H = inst.NS.Settings.Helpers
    local real, calls = H.RenderGrid, {}
    H.RenderGrid = function(ctx, items, parent, opts)
        calls[#calls + 1] = { ctx = ctx, items = items, parent = parent, opts = opts }
        return real(ctx, items, parent, opts)
    end
    local ok, err = pcall(fn)
    H.RenderGrid = real
    if not ok then error(err, 0) end
    return calls
end

--- Run fn with W.ReorderList wrapped, handing back the controller the render built.
local function spyReorder(inst, fn)
    local W = inst.mocks.LibStub("LibKa0s-Widgets-1.0", true)
    local real, ctl = W.ReorderList, nil
    W.ReorderList = function(opts) ctl = real(opts); return ctl end
    local ok, err = pcall(fn)
    W.ReorderList = real
    if not ok then error(err, 0) end
    return ctl
end

test("the list renders through H.RenderGrid into the page's scroll with no gap", function()
    -- red under: the hand loop over scroll:AddChild, which never reaches RenderGrid at all
    local inst, p = editorInstance()
    local calls = spyGrid(inst, function() p:RefreshRows() end)
    assertEqual(#calls, 1, "one RenderGrid call per render")
    local c, ctx = calls[1], spellsCtx(inst)
    assertTrue(c.parent ~= nil and c.parent == ctx.scroll, "the grid draws into the page's scroll")
    assertTrue(c.ctx == ctx, "with the page's ctx")
    assertEqual(c.opts and c.opts.gap, false, "and no spacer after each row")
    assertEqual(#c.items, #activeList(inst), "one item per list entry")
    for i, item in ipairs(c.items) do
        assertEqual(item.wide, true, "item " .. i .. " is a full-width row")
        assertEqual(item.path, "spells[" .. i .. "]", "item " .. i .. " is named for its entry")
    end
end)

test("the scroll holds exactly one group per entry, with no spacer between rows", function()
    -- red under: { gap = false } dropped, which stacks an 8px SimpleGroup after every row and
    -- breaks the reorder stride
    local inst, p = editorInstance()
    p:RefreshRows()
    local scroll, list = spellsCtx(inst).scroll, activeList(inst)
    assertEqual(#scroll.children, #list, "one child per entry and nothing else")
    for i, kid in ipairs(scroll.children) do
        assertEqual(kid.type, "SimpleGroup", "child " .. i .. " is a row group")
        assertTrue(#(kid.children or {}) > 0, "child " .. i .. " is a row, not an empty spacer")
    end
end)

test("the reorder controller is handed the stacked groups, in list order, each ROW_HEIGHT tall", function()
    -- red under: registering an inner group the List layout does not stack, or a wrapper whose
    -- height drifts from the stride the controller computes drops with
    local inst, p = editorInstance()
    local ctl = spyReorder(inst, function() p:RefreshRows() end)
    local scroll, list = spellsCtx(inst).scroll, activeList(inst)
    assertTrue(ctl ~= nil, "the page built a reorder controller")
    assertEqual(#ctl.rows, #list, "one reorder row per entry")
    for i, kid in ipairs(scroll.children) do
        assertTrue(ctl.rows[i].frame == kid.frame,
            "reorder row " .. i .. " is the frame the scroll stacks at position " .. i)
        assertEqual(kid.height, p.ROW_HEIGHT, "row group " .. i .. " is exactly the stride")
    end
end)

test("a row that cannot be built leaves no blank group behind", function()
    -- red under: the grid's guard bypassed, so a nil row still costs a slot in the strip
    local inst, p = editorInstance()
    local list = activeList(inst)
    assertTrue(#list >= 3, "the fixture must have at least three entries")
    local real = p.BuildRow
    p.BuildRow = function(AceGUI, l, i, into)
        if i == 2 then return nil end
        return real(AceGUI, l, i, into)
    end
    local ok, err = pcall(function() p:RefreshRows() end)
    p.BuildRow = real
    assertTrue(ok, tostring(err))
    local scroll = spellsCtx(inst).scroll
    assertEqual(#scroll.children, #list - 1, "the unbuilt row leaves no group in the scroll")
    for i, kid in ipairs(scroll.children) do
        assertTrue(#(kid.children or {}) > 0, "child " .. i .. " is not a blank group")
    end
end)

test("an empty list renders the guidance label as the grid's one item", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    for i = #list, 1, -1 do table.remove(list, i) end
    local calls = spyGrid(inst, function() p:RefreshRows() end)
    assertEqual(#calls, 1, "the empty list draws through the grid too")
    assertEqual(#calls[1].items, 1, "as one item")
    assertEqual(calls[1].items[1].path, "spells.empty")
    local scroll = spellsCtx(inst).scroll
    assertEqual(#scroll.children, 1, "one child, and no spacer under it")
    local label = scroll.children[1].children[1]
    assertEqual(label and label.type, "Label")
    assertTrue(label.text:find("No spells tracked.", 1, true) ~= nil,
        "the empty list says what to do; got: " .. tostring(label and label.text))
end)
