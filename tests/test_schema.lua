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
