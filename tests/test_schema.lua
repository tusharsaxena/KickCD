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

test("icons/castbar schema rows are unit-scoped and valid", function()
    local NS = T.NS
    local seen = { target = false, focus = false }
    for _, def in ipairs(NS.Settings.Schema) do
        if def.panel == "icons" or def.panel == "castbar" then
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
    assertTrue(hasPath(generalRows, "units.focus.label.show"),
        "General (unit=nil) must include units.focus.label.show")
    assertTrue(hasPath(generalRows, "units.focus.label.text"),
        "General (unit=nil) must include units.focus.label.text")

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

test("RenderRows survives a row whose render throws (no blank panel)", function()
    local NS = T.NS
    local H  = NS.Settings.Helpers
    local AceGUI = T.mocks.LibStub("AceGUI-3.0")
    local ctx = H.CreatePanel("KickCDHardenTest", "Harden", { panelKey = "general" })
    -- Pre-seed ctx.scroll so RenderRows' internal ensureScroll(ctx) returns it
    -- immediately (settings/Panel.lua:571 `if ctx.scroll then return ctx.scroll end`)
    -- instead of anchoring scroll.frame, which the AceGUI mock doesn't model.
    ctx.scroll = AceGUI:Create("ScrollFrame")
    local good1 = { panel = "general", section = "general", path = "scale",
                    type = "number", label = "A", default = 1 }
    local boom  = { panel = "general", section = "general", path = "boom",
                    type = "string", label = "B", values = function() error("kaboom") end }
    local good2 = { panel = "general", section = "general", path = "alpha",
                    type = "number", label = "C", default = 1 }
    local ok = pcall(function() H.RenderRows(ctx, { good1, boom, good2 }, nil) end)
    assertTrue(ok, "RenderRows must not propagate a single row's render error")
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
