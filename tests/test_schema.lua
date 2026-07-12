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
    local nested = H.Get("icons.primarySize")
    assertEqual(nested, 64, "nested path must read the default value")
end)

test("Helpers.FindSchema locates a row by path", function()
    local H = NS.Settings.Helpers
    local first = NS.Settings.Schema[1]
    local found = H.FindSchema(first.path)
    assertEqual(found, first, "FindSchema must return the row with the matching path")
end)
