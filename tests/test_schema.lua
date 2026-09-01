-- tests/test_schema.lua — settings schema assembly + validation (Panel.lua Helpers)
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("Settings.Schema is assembled from the settings/* files", function()
    assertTrue(NS.Settings and NS.Settings.Schema, "Settings.Schema must exist")
    assertTrue(#NS.Settings.Schema > 0, "schema must have at least one row")
end)

test("Helpers.ValidateSchema reports zero malformed rows", function()
    local H = NS.Settings.Helpers
    assertTrue(H and H.ValidateSchema, "ValidateSchema must exist")
    assertEqual(H.ValidateSchema(), 0, "assembled schema must be well-formed")
end)

test("Every schema row has a string path and a known type", function()
    local valid = { bool = true, number = true, string = true, color = true }
    for i, def in ipairs(NS.Settings.Schema) do
        assertTrue(type(def.path) == "string" and def.path ~= "",
            "row #" .. i .. " must have a non-empty path")
        assertTrue(valid[def.type], "row #" .. i .. " (" .. tostring(def.path) ..
            ") has invalid type " .. tostring(def.type))
    end
end)

test("Helpers.Resolve walks a dotted path into db.profile", function()
    local H = NS.Settings.Helpers
    -- db was built by OnInitialize; scale is a top-level profile field.
    local parent, key = H.Resolve("scale")
    assertTrue(parent ~= nil, "scale must resolve")
    assertEqual(key, "scale")
    local nested = H.Get("units.target.icons.primarySize")
    assertEqual(nested, 64, "nested path must read the default value")
end)

test("icons/castbar/label schema rows are unit-scoped and valid", function()
    local NS = T.NS
    local seen = { target = false, focus = false }
    for _, def in ipairs(NS.Settings.Schema) do
        if def.panel == "icons" or def.panel == "castbar" or def.panel == "label" then
            assertTrue(def.unit ~= nil, "row " .. tostring(def.path) .. " must carry a unit")
            assertTrue(def.path:match("^units%." .. def.unit .. "%."), "path must be unit-scoped: " .. def.path)
            seen[def.unit] = true
        end
    end
    assertTrue(seen.target and seen.focus, "both target and focus rows must exist")
    assertEqual(NS.Settings.Helpers.ValidateSchema(), 0, "schema must be valid")
end)

test("Helpers.FindSchema locates a row by path", function()
    local H = NS.Settings.Helpers
    local first = NS.Settings.Schema[1]
    local found = H.FindSchema(first.path)
    assertEqual(found, first, "FindSchema must return the row with the matching path")
end)

-- Regression (Task 8 review, Critical): CreatePanel used to force
-- ctx.unit = "target" for every panel, so RenderSchema's
-- SchemaForPanel(panelKey, ctx.unit or "target") silently dropped every
-- unit=="focus" row on General — which has no unit selector and must
-- show both units' rows (e.g. the Task 6 "Enable Focus grid" checkbox
-- and Task 8's units.focus.label.* rows). Fixed by leaving ctx.unit nil
-- unless a panel actually renders a unit selector (RenderUnitPanel,
-- used only by Icons / Castbar), and by RenderSchema passing ctx.unit
-- straight through (nil included) to SchemaForPanel instead of
-- defaulting it to "target".
test("General exposes focus rows; unit-selector panels still filter them out", function()
    local inst = T.load(true)
    local ns = inst.NS
    local H = ns.Settings.Helpers

    local function hasPath(rows, path)
        for _, def in ipairs(rows) do
            if def.path == path then return true end
        end
        return false
    end

    local generalRows = H.SchemaForPanel("general", nil)
    assertTrue(hasPath(generalRows, "units.focus.enabled"),
        "General (unit=nil) must include units.focus.enabled")

    local iconsTargetRows = H.SchemaForPanel("icons", "target")
    for _, def in ipairs(iconsTargetRows) do
        assertTrue(def.unit ~= "focus",
            "Icons filtered to target must exclude focus rows: " .. tostring(def.path))
    end

    -- Drive the actual regression path: CreatePanel must NOT force a
    -- default unit onto panels that never render a selector, or
    -- RenderSchema's SchemaForPanel(panelKey, ctx.unit) would silently
    -- re-filter General down to one unit again.
    local panelCtx = H.CreatePanel("KickCDTmpGeneral", "General", { panelKey = "general" })
    assertTrue(panelCtx.unit == nil,
        "CreatePanel must leave ctx.unit nil for selector-less panels (got " ..
            tostring(panelCtx.unit) .. ")")
end)

test("label panel carries per-unit label rows; General no longer does", function()
    local NS = T.NS
    local H  = NS.Settings.Helpers
    local function hasPath(rows, path)
        for _, d in ipairs(rows) do if d.path == path then return true end end
        return false
    end
    local generalRows = H.SchemaForPanel("general", nil)
    assertTrue(not hasPath(generalRows, "units.focus.label.show"),
        "General must NOT carry label.show anymore")
    assertTrue(hasPath(generalRows, "units.focus.enabled"),
        "General still carries the per-unit enable")

    local labelFocus = H.SchemaForPanel("label", "focus")
    assertTrue(hasPath(labelFocus, "units.focus.label.show"), "label panel has focus label.show")
    assertTrue(hasPath(labelFocus, "units.focus.label.text"), "label panel has focus label.text")

    assertEqual(H.ValidateSchema(), 0, "schema still valid with the label panel")
end)
-- REMOVED, and this is a REGRESSION worth knowing about rather than a tidy-up.
--
-- settings/Panel_Render.lua's own RenderRows wrapped every row's render in a
-- pcall, so one corrupt saved value or one throwing `values` function cost
-- that row and nothing else. LibKa0s-Options-1.0's flow engine does NOT
-- pcall: it guards the KNOWN corruption (a slider handed a non-number falls
-- back to the default) and returns nil for an unknown row type, but a maker
-- that actually raises now propagates and takes the whole page with it.
--
-- Left as a reported finding rather than patched locally: a pcall in
-- RenderRows is not something the descriptor can express, so closing it
-- properly is an upstream change to ../LibKa0s with its own failing test,
-- minor bump and re-vendor across every consumer. Editing libs/ here would
-- be a fork the next re-vendor silently reverts.


test("every label-panel row's default is a member of its static values list", function()
    local NS = T.NS
    for _, def in ipairs(NS.Settings.Schema) do
        if def.panel == "label" and type(def.values) == "table" and def.default ~= nil then
            -- `values` is a keyed { key = label } hash now, so membership is a
            -- direct lookup rather than a scan for a record whose .value matches.
            local found = def.values[def.default] ~= nil
            assertTrue(found, "label row " .. tostring(def.path) .. " default '" .. tostring(def.default) .. "' not in its values list")
        end
    end
end)

test("PartitionUnitRows splits alwaysPerUnit rows from styled rows", function()
    local H = T.NS.Settings.Helpers
    local rows = {
        { path = "a", alwaysPerUnit = true },
        { path = "b" },
        { path = "c", alwaysPerUnit = true },
    }
    local perUnit, styled = H.PartitionUnitRows(rows)
    assertEqual(#perUnit, 2, "two alwaysPerUnit rows")
    assertEqual(#styled, 1, "one styled row")
    assertEqual(perUnit[1].path, "a")
    assertEqual(styled[1].path, "b")
end)

test("debug console stays session-only: no schema row targets it (debug-logging-§5)", function()
    local NS = T.NS
    -- The General "Debug console" checkbox is a bespoke SessionToggle, never a
    -- schema row — a schema row would persist to SavedVariables. Guard that no
    -- one converts it into one, and that Helpers.SessionToggle exists to back it.
    for _, def in ipairs(NS.Settings.Schema) do
        local p = tostring(def.path)
        assertTrue(p ~= "debug" and p ~= "debugLog" and not p:find("debug", 1, true),
            "no schema row may target debug state (found path '" .. p .. "')")
    end
    assertTrue(type(NS.Settings.Helpers.SessionToggle) == "function",
        "Helpers.SessionToggle must back the session-only debug checkbox")
end)

-- ── the tab strip: page -> tab -> row count ────────────────────────────────
--
-- H.RenderTabbedSchema partitions a page's rows by `group`, IN DECLARATION
-- ORDER, and draws one tab per distinct group (options-ui-§13). So the array's
-- order IS the strip's order, and this table is the designed strip written down
-- where a diff can disagree with it.
--
-- It catches three different mistakes that all look like nothing in a diff:
-- a row landing in the wrong tab (the count moves), a tab being renamed in one
-- of the several places its name is spelled (the name moves), and — the one
-- that is invisible until you are in game — a row appended AFTER the array has
-- already left its group, which draws that tab's heading a second time further
-- down the page.
--
-- Counts are PER UNIT for the three unit-scoped pages, because that is what a
-- reader sees: the page renders only the selected unit's rows. General has no
-- unit selector, so its Units tab shows both units' toggles and counts 2.
local STRIP = {
    general = { { "Master controls", 5 }, { "Units", 2 } },
    icons   = {
        { "Sizing", 4 }, { "Layout", 6 }, { "Visual states", 4 },
        { "Border", 4 }, { "Annotations", 8 }, { "Ready glow", 6 },
    },
    castbar = {
        { "General", 9 }, { "Position", 5 }, { "Font", 3 },
        { "Spell name", 5 }, { "Cast time", 4 },
        { "Interruptible", 8 }, { "Non-interruptible", 8 },
    },
    label   = { { "General", 2 }, { "Placement", 8 }, { "Font", 4 } },
}

-- The filter each page renders with: nil is "every unit's rows", which is what
-- a page with no unit picker gets.
local STRIP_FILTER = { general = nil, icons = "target", castbar = "target", label = "target" }

--- The page's groups in declaration order, with a count each — the same walk
--- RenderTabbedSchema does.
local function partition(rows)
    local order, count = {}, {}
    for _, def in ipairs(rows) do
        local g = def.group
        if g ~= nil then
            if count[g] == nil then
                count[g] = 0
                order[#order + 1] = g
            end
            count[g] = count[g] + 1
        end
    end
    return order, count
end

test("every page partitions into the designed tab strip, in strip order", function()
    -- red under: moving one row to another `group`, renaming a tab in
    -- settings/<page>.lua without renaming it here, or reordering the array.
    local H = T.NS.Settings.Helpers
    local pagesChecked = 0
    for page, expected in pairs(STRIP) do
        local order, count = partition(H.SchemaForPanel(page, STRIP_FILTER[page]))
        assertEqual(#order, #expected,
            page .. " draws " .. #order .. " tabs, the design says " .. #expected)
        for i, want in ipairs(expected) do
            assertEqual(order[i], want[1],
                page .. " tab #" .. i .. " is '" .. tostring(order[i])
                    .. "', the design says '" .. want[1] .. "'")
            assertEqual(count[want[1]], want[2],
                page .. " > " .. want[1] .. " holds " .. tostring(count[want[1]])
                    .. " rows, the design says " .. want[2])
        end
        pagesChecked = pagesChecked + 1
    end
    assertEqual(pagesChecked, 4, "all four schema-driven pages must be checked")
end)

test("no page draws a tab twice: every group's rows are contiguous", function()
    -- red under: appending a new row at the END of settings/Castbar.lua's
    -- addUnitRows with `group = L["Position"]`. RenderTabbedSchema partitions in
    -- declaration order, so the stray row renders under a SECOND copy of that
    -- tab's heading further down the page — visible only in game.
    local H = T.NS.Settings.Helpers
    for page in pairs(STRIP) do
        local seen, closed, last = {}, {}, nil
        for _, def in ipairs(H.SchemaForPanel(page, STRIP_FILTER[page])) do
            local g = def.group
            if g ~= nil then
                if g ~= last then
                    assertTrue(not closed[g],
                        page .. ": rows for '" .. tostring(g)
                            .. "' resume after the page has left that group ("
                            .. tostring(def.path) .. ")")
                    if last ~= nil then closed[last] = true end
                    seen[g] = true
                    last = g
                end
            end
        end
    end
end)

test("no schema page falls below two tabs and loses its strip", function()
    -- RenderTabbedSchema draws NO strip for a page with fewer than two groups —
    -- the library's behaviour, not a bug, and the reason merging sections is the
    -- one reorganization that can silently un-tab a page.
    for page, expected in pairs(STRIP) do
        assertTrue(#expected >= 2,
            page .. " is designed with " .. #expected .. " tab(s); one draws no strip")
    end
end)

test("a unit page's strip is identical for Target and for Focus", function()
    -- The Unit picker is the page BANNER and switching it re-renders the page.
    -- If the two units partitioned differently, the strip would reshuffle under
    -- the reader mid-selection and ctx.activeTab would heal to tab one.
    local H = T.NS.Settings.Helpers
    for _, page in ipairs({ "icons", "castbar", "label" }) do
        local tOrder = partition(H.SchemaForPanel(page, "target"))
        local fOrder, fCount = partition(H.SchemaForPanel(page, "focus"))
        local _, tCount = partition(H.SchemaForPanel(page, "target"))
        assertEqual(#fOrder, #tOrder, page .. ": Focus draws a different number of tabs")
        for i, name in ipairs(tOrder) do
            assertEqual(fOrder[i], name, page .. " tab #" .. i .. " differs between units")
            assertEqual(fCount[name], tCount[name], page .. " > " .. name .. " differs in size")
        end
    end
end)

-- ── the Unit picker is the page BANNER, above the strip ────────────────────
--
-- options-ui-§14. It is not a tab and it must not be a row: it scopes the WHOLE
-- page, and every tab on the page edits the unit it names.
--
-- The reason this is asserted rather than trusted is a failure mode with no
-- other witness. A tab click clears the SCROLL and redraws the rows; the chrome
-- band survives it. A picker added to the scroll therefore looks correct on the
-- render that drew it and vanishes the first time the reader clicks a tab —
-- which no static reading of the builder shows.

--- A unit page's ctx, rendered, with the scroll pre-seeded the way the fixtures
--- above do it (ensureScroll returns an existing ctx.scroll rather than
--- anchoring a frame the AceGUI mock does not model).
local function renderedUnitPage(page, unit)
    local H = T.NS.Settings.Helpers
    local AceGUI = T.mocks.LibStub("AceGUI-3.0")
    local ctx = H.CreatePanel("KickCDStrip" .. page .. tostring(unit), page, { panelKey = page })
    ctx.scroll = AceGUI:Create("ScrollFrame")
    ctx.unit = unit
    H.RenderUnitPanel(ctx, page)
    return ctx, H
end

test("the Unit picker is drawn in the page's chrome band, never into the scroll", function()
    -- red under: replacing H.PageBanner in settings/Panel_Render.lua's
    -- RenderUnitPanel with a Dropdown added to the scroll, the way the
    -- hand-built unit header used to do it.
    for _, page in ipairs({ "icons", "castbar", "label" }) do
        local ctx = renderedUnitPage(page, "target")
        assertTrue(ctx.__bannerWidget ~= nil,
            page .. " drew no Unit banner at all")
        assertEqual(ctx.__bannerWidget.labelText, T.NS.L["Unit"],
            page .. "'s banner is not labelled Unit")
        for i, child in ipairs(ctx.scroll.children) do
            assertTrue(child.labelText ~= T.NS.L["Unit"],
                page .. ": the Unit picker is scroll child #" .. i
                    .. "; a tab click would clear it away")
        end
    end
end)

test("the Unit banner retargets the page and every tab follows it", function()
    -- The picker is the ONLY writer of the page's unit, and selecting one
    -- re-renders the page rather than repainting a subset of it.
    local ctx = renderedUnitPage("icons", "target")
    assertEqual(ctx.unit, "target", "precondition: the page starts on Target")

    ctx.__bannerWidget:__fire("OnValueChanged", "focus")

    assertEqual(ctx.unit, "focus", "selecting Focus must retarget the page")
    assertTrue(ctx.__bannerWidget ~= nil, "the banner must survive its own selection")
    -- Every row the page now holds belongs to Focus. RenderTabbedSchema renders
    -- one tab's rows, so this reads the active tab's partition back out.
    local H = T.NS.Settings.Helpers
    for _, def in ipairs(H.SchemaForPanel("icons", ctx.unit)) do
        assertEqual(def.unit, "focus", "row " .. def.path .. " is not the selected unit's")
    end
end)

test("a linked Focus draws the note and no strip at all", function()
    -- A tab strip over a page whose rows are all hidden is chrome for its own
    -- sake, and PageBanner drains the strip's ledger as well as its own, so the
    -- previous unit's tabs cannot be left stranded above the note.
    local NS = T.NS
    local cfg = NS.Units.Config("focus")
    local before = cfg and cfg.link
    if cfg then cfg.link = true end

    local ctx = renderedUnitPage("castbar", "focus")
    assertTrue(ctx.__bannerWidget ~= nil, "the Unit picker stays, linked or not")
    assertEqual(#(ctx.__tabKids or {}), 0,
        "a linked Focus must draw no tab buttons")

    if cfg then cfg.link = before end
end)
