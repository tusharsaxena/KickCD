-- tests/test_units.lua — NS.Units link/enable/config resolution (core/Units.lua)

local T = _G.KICKCD_TEST

local test, assertEqual = T.test, T.assertEqual



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

    -- Focus defaults to enabled now; explicitly start it disabled so the
    -- disabled->enabled transition below is still exercised.
    ns.db.profile.units.focus.enabled = false

    ig:ReconcileUnits()

    assertEqual(ns.Units.IsEnabled("focus"), false, "focus starts disabled (test setup)")

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



test("LabelShow follows the link: a linked focus mirrors target's show (spec 2b)", function()
    local NS = T.load(true).NS
    NS.db.profile.units.target.label.show = false
    NS.db.profile.units.focus.label.show  = true
    NS.db.profile.units.focus.link = true
    assertEqual(NS.Units.LabelShow("focus"), false, "linked focus reads target's show (off)")
    assertEqual(NS.Units.LabelShow("target"), false, "target reads its own show")
    NS.db.profile.units.focus.link = false
    assertEqual(NS.Units.LabelShow("focus"), true, "unlinked focus reads its own show")
end)

test("CopyStyling snapshots target label.style + show, keeps focus text (spec 2a/2b)", function()
    local NS = T.load(true).NS
    NS.db.profile.units.target.label.style.size = 17
    NS.db.profile.units.target.label.show = false  -- target's show is what a snapshot must capture
    NS.db.profile.units.focus.label.show = true
    NS.db.profile.units.focus.label.text = "MINE"
    NS.db.profile.units.focus.link = true
    NS.Units.CopyStyling("target", "focus")
    assertEqual(NS.db.profile.units.focus.link, false, "copy unlinks")
    assertEqual(NS.db.profile.units.focus.label.style.size, 17, "focus got a copy of target style")
    assertEqual(NS.db.profile.units.focus.label.text, "MINE", "per-unit text preserved")
    assertEqual(NS.db.profile.units.focus.label.show, false, "show snapshotted from target (follows link)")
    NS.db.profile.units.focus.label.style.size = 99
    assertEqual(NS.db.profile.units.target.label.style.size, 17, "copy is deep, not aliased")
end)


-- ── #19: the Focus styling link and Copy styling, through the helper ────────
--
-- architecture-§5: a setting the player sets needs a row, and a copy-from that
-- touches rows is a write through the helper. The characterization cases were
-- written and run green against the old whole-table copy first, so the
-- row-by-row copy is provably the same copy.

local COPIED = { "icons.", "castbar.", "label.style.", "label.show" }

local function isCopied(rel)
    for _, prefix in ipairs(COPIED) do
        if rel:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function deepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

--- Every schema row the copy carries, as target-relative paths.
local function copiedRows(NS)
    local out = {}
    for _, def in ipairs(NS.Settings.Schema) do
        local rel = type(def.path) == "string" and def.path:match("^units%.target%.(.+)$")
        if rel and isCopied(rel) then out[#out + 1] = rel end
    end
    return out
end

local function firstColorRow(NS, prefix)
    for _, def in ipairs(NS.Settings.Schema) do
        if def.type == "color" and def.path:sub(1, #prefix) == prefix then return def.path end
    end
end

--- Give Target an appearance that differs from the defaults in every way the
--- copy has to carry: a size, a color, a VERTICAL bar whose growDirection is not
--- that axis's default, a label style and a label show.
local function seedTarget(NS)
    local t = NS.db.profile.units.target
    t.icons.primarySize = 55
    t.castbar.orientation = "VERTICAL"
    t.castbar.growDirection = "DOWN"
    t.label.style.size = 17
    t.label.show = false
    local H = NS.Settings.Helpers
    H.Set(firstColorRow(NS, "units.target.icons."), "icons", { r = 0.1, g = 0.2, b = 0.3, a = 0.4 })
end

test("CopyStyling carries every icons, castbar, label.style and label.show row onto focus", function()
    local NS = T.load(true).NS
    local H = NS.Settings.Helpers
    seedTarget(NS)
    local f = NS.db.profile.units.focus
    f.link, f.enabled, f.label.text, f.label.show = true, false, "MINE", true
    local anchorsBefore = NS.Util.DeepCopy(f.anchors)

    NS.Units.CopyStyling("target", "focus")

    local rows = copiedRows(NS)
    T.assertTrue(#rows > 100, "sanity: the copy carries every per-unit appearance row")
    for _, rel in ipairs(rows) do
        T.assertTrue(deepEqual(H.Get("units.focus." .. rel), H.Get("units.target." .. rel)),
            "focus." .. rel .. " was not copied from target")
    end
    assertEqual(f.label.show, false, "label.show is snapshotted: it follows the link")
    assertEqual(f.label.text, "MINE", "label.text is per-unit and deliberately not copied")
    assertEqual(f.enabled, false, "the unit's enable is not appearance")
    T.assertTrue(deepEqual(f.anchors, anchorsBefore), "position is not appearance")
    assertEqual(f.link, false, "the copy unlinks")
end)

test("CopyStyling's copy is deep: focus gets its own color tables", function()
    local NS = T.load(true).NS
    seedTarget(NS)
    NS.Units.CopyStyling("target", "focus")
    local H = NS.Settings.Helpers
    local rel = firstColorRow(NS, "units.target.icons."):match("^units%.target%.(.+)$")
    local src, dst = H.Get("units.target." .. rel), H.Get("units.focus." .. rel)
    T.assertTrue(src ~= dst, "a copied color must not alias target's table")
    dst.r = 0.9
    assertEqual(src.r, 0.1, "editing focus's copy must not reach target")
end)

test("CopyStyling writes every copied row, and the link, through Helpers.Set", function()
    -- red under: the old whole-table copy (`dst.icons = DeepCopy(src.icons)`),
    -- which wrote around the helper and ran no row's onChange.
    local NS = T.load(true).NS
    local H = NS.Settings.Helpers
    local seen = {}
    local real = H.Set
    H.Set = function(path, ...) seen[#seen + 1] = path; return real(path, ...) end
    local ok, err = pcall(NS.Units.CopyStyling, "target", "focus")
    H.Set = real
    if not ok then error(err, 0) end
    local written = {}
    for _, p in ipairs(seen) do written[p] = true end
    for _, rel in ipairs(copiedRows(NS)) do
        T.assertTrue(written["units.focus." .. rel], "units.focus." .. rel .. " bypassed Helpers.Set")
    end
    T.assertTrue(written["units.focus.link"], "the link must be written through its row")
    T.assertNil(written["units.focus.label.text"], "label.text must not be written at all")
end)

test("CopyStyling runs each row's onChange, and orientation's cannot undo the copied growDirection", function()
    -- orientation's onChange resets growDirection to that axis's default. The
    -- copy walks rows in declaration order, orientation first, so the copied
    -- growDirection lands after it and wins.
    local NS = T.load(true).NS
    local H = NS.Settings.Helpers
    seedTarget(NS)
    local def = H.FindSchema("units.focus.castbar.orientation")
    local real, ran = def.onChange, false
    def.onChange = function(...) ran = true; return real(...) end
    local ok, err = pcall(NS.Units.CopyStyling, "target", "focus")
    def.onChange = real
    if not ok then error(err, 0) end
    T.assertTrue(ran, "the orientation row's onChange must run")
    assertEqual(NS.db.profile.units.focus.castbar.orientation, "VERTICAL")
    assertEqual(NS.db.profile.units.focus.castbar.growDirection, "DOWN",
        "the copied growDirection must survive orientation's reset")
end)

test("CopyStyling announces each section once and refreshes the panels structurally once", function()
    -- A hundred-odd row writes must not be a hundred-odd CONFIG_CHANGED fan-outs.
    local NS = T.load(true).NS
    local H = NS.Settings.Helpers
    local sent, refreshes = {}, 0
    local realSend, realRefresh = NS.SendMessage, H.RefreshAllPanels
    NS.SendMessage = function(self, msg, payload)
        if msg == "Ka0s_KickCD_CONFIG_CHANGED" then
            sent[payload.section] = (sent[payload.section] or 0) + 1
        end
        return realSend(self, msg, payload)
    end
    H.RefreshAllPanels = function(...) refreshes = refreshes + 1; return realRefresh(...) end
    local ok, err = pcall(NS.Units.CopyStyling, "target", "focus")
    NS.SendMessage, H.RefreshAllPanels = realSend, realRefresh
    if not ok then error(err, 0) end
    for _, section in ipairs({ "icons", "castbar", "label", "units" }) do
        assertEqual(sent[section], 1, section .. " must be announced exactly once")
    end
    assertEqual(refreshes, 1, "one structural refresh, after the copy")
end)

test("CopyStyling logs ONE [Set] summary line, not one per copied row", function()
    -- The owner's call: a copy is one act of ~111 rows, and ~111 [Set] lines
    -- bury the log and evict older lines from the 500-line buffer
    -- (debug-logging-§9). red under: SetRows letting each row's Helpers.Set log.
    local inst = T.load(true, true)
    local NS = inst.NS
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    local ok, err = pcall(NS.Units.CopyStyling, "target", "focus")
    inst.mocks.__flushTimers()   -- a per-row line would be a debounced one
    local lines = {}
    for line in (NS.DebugLog:CopyText() .. "\n"):gmatch("([^\n]*)\n") do
        if line:find("[Set]", 1, true) then lines[#lines + 1] = line end
    end
    NS.State.debug = false
    if not ok then error(err, 0) end
    assertEqual(#lines, 1, "one summary line: " .. table.concat(lines, " | "))
    local rows = #copiedRows(NS) + 1   -- every copied row, and the link
    T.assertTrue(lines[1]:find("copy target", 1, true) ~= nil, "it names the copy: " .. lines[1])
    T.assertTrue(lines[1]:find(": " .. rows .. " rows", 1, true) ~= nil,
        "it carries the row count (" .. rows .. "): " .. lines[1])
    T.assertNil(lines[1]:find("units.focus.", 1, true), "and no per-row path")
end)

test("CopyStyling still validates and runs onChange per row with the log muted", function()
    -- The mute is the log's alone: a row's write, its onChange and the helper's
    -- schema lookup all still happen per row.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    NS.State.debug = true
    local def = H.FindSchema("units.focus.castbar.orientation")
    local realChange, ran = def.onChange, 0
    def.onChange = function(...) ran = ran + 1; return realChange(...) end
    local sets, realSet = 0, H.Set
    H.Set = function(...) sets = sets + 1; return realSet(...) end
    local ok, err = pcall(NS.Units.CopyStyling, "target", "focus")
    def.onChange, H.Set = realChange, realSet
    NS.State.debug = false
    if not ok then error(err, 0) end
    assertEqual(ran, 1, "orientation's onChange ran once")
    T.assertTrue(sets >= #copiedRows(NS) + 1, "every row still went through Helpers.Set")
    -- And a later single write logs its own [Set] line again: the mute is over.
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    H.Set("locked", "general", true)
    inst.mocks.__flushTimers()
    NS.State.debug = false
    T.assertTrue(NS.DebugLog:FindLine("[Set] locked = true"), "the per-row log is back after the copy")
end)

test("units.focus.link is a General > Units row, drawn by the tab's own tick", function()
    -- red under: `link` going back to a plain profile field with no row, which
    -- leaves it outside /kcd get|set|list|reset and the page's Defaults.
    local NS = T.load(true).NS
    local H = NS.Settings.Helpers
    local def = H.FindSchema("units.focus.link")
    T.assertTrue(def ~= nil, "units.focus.link must be a schema row")
    assertEqual(def.type, "bool")
    assertEqual(def.panel, "general")
    assertEqual(def.section, "units")
    assertEqual(def.group, NS.L["Units"])
    assertEqual(def.default, NS.DEFAULT_PROFILE.units.focus.link)
    assertEqual(def.skipRender, true, "the tab draws the tick itself, paired with Copy styling")
    assertEqual(type(def.onChange), "function", "the structural refresh is the row's")
    T.assertNil(H.FindSchema("units.target.link"), "target is never linked, so it has no row")
    T.assertNil(H.RestoreUnitLinks, "the profile reset and the row's own reset replace RestoreUnitLinks")
end)

test("`/kcd set units.focus.link` writes it, announces units and repaints structurally", function()
    local NS = T.load(true).NS
    local H = NS.Settings.Helpers
    local sent, refreshes = {}, 0
    local realSend, realRefresh = NS.SendMessage, H.RefreshAllPanels
    NS.SendMessage = function(self, msg, payload)
        if msg == "Ka0s_KickCD_CONFIG_CHANGED" then sent[#sent + 1] = payload.section end
        return realSend(self, msg, payload)
    end
    H.RefreshAllPanels = function(...) refreshes = refreshes + 1; return realRefresh(...) end
    local ok, err = pcall(function()
        NS:OnSlashCommand("set units.focus.link false")
        assertEqual(NS.db.profile.units.focus.link, false)
        assertEqual(sent[1], "units")
        T.assertTrue(refreshes >= 1, "flipping the link must re-render the unit pages")
        NS:OnSlashCommand("reset units.focus.link")
        assertEqual(NS.db.profile.units.focus.link, true, "reset restores the shipped link")
    end)
    NS.SendMessage, H.RefreshAllPanels = realSend, realRefresh
    if not ok then error(err, 0) end
end)

test("the Units tab's tick writes the link through Helpers.SetAndRefresh", function()
    -- red under: the tick writing `cfg.link` itself and firing `units` by hand.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local ctx = H.__panelFor("general")
    ctx.activeTab = NS.L["Units"]
    ctx.panel:Show()
    H.RefreshPanel(ctx, true)
    local tick
    for _, child in ipairs((ctx.scroll and ctx.scroll.children) or {}) do
        for _, w in ipairs(child.children or {}) do
            if w.labelText == NS.L["Use same styling as Target"] then tick = w end
        end
    end
    T.assertTrue(tick ~= nil, "the Units tab must draw the tick")
    local paths = {}
    local real = H.SetAndRefresh
    H.SetAndRefresh = function(path, ...) paths[#paths + 1] = path; return real(path, ...) end
    local ok, err = pcall(tick.__fire, tick, "OnValueChanged", false)
    H.SetAndRefresh = real
    if not ok then error(err, 0) end
    assertEqual(paths[1], "units.focus.link", "the tick must write through the helper")
    assertEqual(NS.db.profile.units.focus.link, false)
end)

--- The General page, shown on its Units tab, and the tick it draws there.
local function generalUnitsTab(inst)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local ctx = H.__panelFor("general")
    ctx.activeTab = NS.L["Units"]
    ctx.panel:Show()
    H.RefreshPanel(ctx, true)
    local function tick()
        for _, child in ipairs((ctx.scroll and ctx.scroll.children) or {}) do
            for _, w in ipairs(child.children or {}) do
                if w.labelText == NS.L["Use same styling as Target"] then return w end
            end
        end
    end
    return ctx, tick
end

--- Count H.RefreshAllPanels calls made while `fn` runs.
local function countRefreshes(H, fn)
    local n, real = 0, H.RefreshAllPanels
    H.RefreshAllPanels = function(...) n = n + 1; return real(...) end
    local ok, err = pcall(fn)
    H.RefreshAllPanels = real
    if not ok then error(err, 0) end
    return n
end

test("General's Defaults re-links Focus and survives the refresh raised inside the library's loop", function()
    -- RestoreDefaults walks the page's rows and resets each through
    -- SetAndRefresh. The link row's onChange is a STRUCTURAL refresh, so it
    -- clears and re-renders this very page -- replacing ctx.refreshers -- while
    -- the library is still in its row loop, and the loop then runs the page's
    -- refreshers. Neither half may raise, and the page must come back whole.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local ctx, tick = generalUnitsTab(inst)
    H.SetAndRefresh("units.focus.link", false)
    assertEqual(NS.db.profile.units.focus.link, false, "setup: Focus unlinked")
    T.assertTrue(type(ctx.panel.defaultsOnClick) == "function", "General parks a Defaults handler")

    local refreshes = countRefreshes(H, function() ctx.panel.defaultsOnClick() end)

    assertEqual(NS.db.profile.units.focus.link, true, "Defaults must re-link Focus")
    T.assertTrue(refreshes >= 1, "flipping the link back repaints structurally")
    T.assertTrue(tick() ~= nil, "the Units tab is drawn again after the refresh")
    for i, fn in ipairs(ctx.refreshers or {}) do
        local ok, err = pcall(fn)
        T.assertTrue(ok, "refresher #" .. i .. " raised after the reset: " .. tostring(err))
    end
end)

test("the link row repaints structurally only when the link actually changes", function()
    -- red under: an onChange that rebuilds every page on every write, including
    -- a Defaults or a `/kcd set` that leaves the link where it already was.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    generalUnitsTab(inst)
    assertEqual(NS.db.profile.units.focus.link, true, "setup: Focus linked by default")
    assertEqual(countRefreshes(H, function() H.SetAndRefresh("units.focus.link", true) end), 0,
        "writing the value it already has repaints nothing")
    assertEqual(countRefreshes(H, function() H.SetAndRefresh("units.focus.link", false) end), 1,
        "unlinking repaints once")
    assertEqual(countRefreshes(H, function() H.SetAndRefresh("units.focus.link", false) end), 0,
        "and unlinking again repaints nothing")
end)

test("CopyStyling onto an already-unlinked Focus still refreshes the panels once", function()
    -- The copy's structural refresh is the link row's onChange when the copy
    -- flips the link. When Focus is unlinked already the link does not move, so
    -- the copy must repaint by itself -- once, not zero times and not twice.
    local NS = T.load(true).NS
    local H = NS.Settings.Helpers
    H.SetAndRefresh("units.focus.link", false)
    assertEqual(countRefreshes(H, function() NS.Units.CopyStyling("target", "focus") end), 1,
        "one structural refresh after a copy onto an unlinked Focus")
end)
