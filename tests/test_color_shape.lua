-- tests/test_color_shape.lua
-- Colors are stored as the KEYED { r =, g =, b =, a = } table, not as a
-- positional { r, g, b, a } array.
--
-- WHY THE SHAPE MOVED. LibKa0s-Slash-1.0 parses a typed color into the keyed
-- form and lib.FormatValue renders the keyed form; LibKa0s-Options-1.0's color
-- picker decodes and encodes it. The keyed shape is the collection's, and it is
-- what lets both libraries read this addon's colors with no translation layer.
-- The alternative — keeping arrays and supplying a codec at every seam — was a
-- get/parse adapter pair in settings/Slash.lua plus colorDecode/colorEncode in
-- the options descriptor, i.e. the same translation written twice.
--
-- The migration is real user data: a profile written before this ran holds
-- arrays, so core/Database.lua's ladder converts them on load. That step is what
-- most of this suite is about — the defaults are easy, the saved profiles are
-- the part that can silently render every color white.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil, assertNear =
    T.test, T.assertEqual, T.assertTrue, T.assertNil, T.assertNear
local NS = T.NS

--- Every color path in the schema, so no case has to hardcode a list that
--- drifts as rows are added.
local function colorRows()
    local out = {}
    for _, def in ipairs(NS.Settings.Schema) do
        if def.type == "color" then out[#out + 1] = def end
    end
    return out
end

-- ── the declared defaults ───────────────────────────────────────────────────

test("the schema declares at least one color row per color-bearing panel", function()
    -- A guard on the guard: if colorRows() ever returned empty, every assertion
    -- below would pass vacuously.
    assertTrue(#colorRows() >= 13,
        "expected 13+ color rows, found " .. #colorRows())
end)

test("every schema color default is keyed, never positional", function()
    -- red under: reverting one `default = { r = .., g = .., b = .., a = .. }`
    -- back to `{ 1, 0.4, 0.4, 1 }`
    for _, def in ipairs(colorRows()) do
        assertEqual(type(def.default), "table", def.path .. " default")
        assertTrue(def.default.r ~= nil, def.path .. " default has no .r — still positional?")
        assertNil(def.default[1], def.path .. " default still carries index [1]")
    end
end)

test("every schema color default carries all four channels", function()
    -- An omitted alpha reads as nil and the picker then renders fully
    -- transparent rather than falling back, so the shape has to be complete.
    for _, def in ipairs(colorRows()) do
        local d = def.default
        for _, k in ipairs({ "r", "g", "b", "a" }) do
            assertEqual(type(d[k]), "number", def.path .. " default." .. k)
        end
    end
end)

test("every color row declares hasAlpha, so the picker keeps its alpha channel", function()
    -- The old panel passed hasAlpha unconditionally; the library reads it off
    -- the row. Left undeclared, every swatch silently loses its alpha slider —
    -- which for bgColor (default a = 0.5) would be a visible regression.
    for _, def in ipairs(colorRows()) do
        assertEqual(def.hasAlpha, true, def.path .. " must declare hasAlpha")
    end
end)

-- ── the live profile ────────────────────────────────────────────────────────

test("the built profile stores colors keyed", function()
    local H = NS.Settings.Helpers
    for _, def in ipairs(colorRows()) do
        local v = H.Get(def.path)
        assertEqual(type(v), "table", def.path)
        assertTrue(v.r ~= nil, def.path .. " stored positionally in the live profile")
        assertNil(v[1], def.path .. " stored value still carries index [1]")
    end
end)

test("DEFAULT_PROFILE and the schema agree on every color", function()
    -- Two literals for one value is how they drift. They are declared in both
    -- core/Database.lua and settings/*.lua, so pin that they match.
    local H = NS.Settings.Helpers
    for _, def in ipairs(colorRows()) do
        local live = H.Get(def.path)
        local d = def.default
        assertNear(live.r, d.r, 1e-9, def.path .. ".r")
        assertNear(live.g, d.g, 1e-9, def.path .. ".g")
        assertNear(live.b, d.b, 1e-9, def.path .. ".b")
        assertNear(live.a, d.a, 1e-9, def.path .. ".a")
    end
end)

-- ── the unpack seam ─────────────────────────────────────────────────────────

test("Util.Unpack reads the keyed shape", function()
    local r, g, b, a = NS.Util.Unpack({ r = 1, g = 0.5, b = 0.25, a = 0.75 })
    assertEqual(r, 1); assertEqual(g, 0.5); assertEqual(b, 0.25); assertEqual(a, 0.75)
end)

test("Util.Unpack still reads a positional array, so a stray one renders rather than blanks", function()
    -- Deliberately kept. The migration converts saved profiles, but an array
    -- reaching a color setter from anywhere the ladder did not touch should
    -- render the color it names, not white.
    local r, g, b, a = NS.Util.Unpack({ 1, 0.5, 0.25, 0.75 })
    assertEqual(r, 1); assertEqual(g, 0.5); assertEqual(b, 0.25); assertEqual(a, 0.75)
end)

test("no module reads a color by positional index any more", function()
    -- red under: restoring `c[1] or 1, c[2] or 1, ...` in UnitLabel/IconGrid_Render
    --
    -- Three readers bypassed Util.Unpack and indexed [1]..[4] directly. Under
    -- keyed storage each would have read nil and fallen back to its default, so
    -- the label would have rendered gold and the glow yellow no matter what the
    -- user picked — silently, and only in game.
    local offenders = {}
    for _, rel in ipairs({
        "modules/UnitLabel.lua", "modules/IconGrid_Render.lua", "modules/Castbar_Debug.lua",
    }) do
        local fh = assert(io.open(T.root .. "/" .. rel, "r"))
        local n = 0
        for line in fh:lines() do
            n = n + 1
            if line:match("c%[1%]") or line:match("color%[1%]") then
                offenders[#offenders + 1] = rel .. ":" .. n
            end
        end
        fh:close()
    end
    assertEqual(#offenders, 0, "positional color read at: " .. table.concat(offenders, ", "))
end)

-- ── the migration ───────────────────────────────────────────────────────────

test("a pre-migration profile's array colors convert to the keyed shape", function()
    -- THE case that protects real user data. A profile saved before this change
    -- holds arrays; without the ladder step every color would read nil on every
    -- channel and render as the fallback.
    -- red under: removing the [3] entry from the MIGRATIONS table
    local inst = T.load(false)
    local NS2 = inst.NS

    -- A v3 account with one array-shaped color saved, exactly as it was written.
    local saved = {
        global  = { schemaVersion = 3 },
        profile = {
            units = { target = { icons = { cooldownTint = { 0.25, 0.5, 0.75, 0.5 } } } },
        },
    }
    inst.mocks.KickCDDB = saved
    pcall(NS2.OnInitialize, NS2)

    local v = NS2.db and NS2.db.profile
        and NS2.db.profile.units.target.icons.cooldownTint
    assertEqual(type(v), "table")
    assertNear(v.r, 0.25, 1e-9, "red must survive the conversion")
    assertNear(v.g, 0.5, 1e-9)
    assertNear(v.b, 0.75, 1e-9)
    assertNear(v.a, 0.5, 1e-9, "alpha must survive — bgColor defaults to 0.5")
    assertNil(v[1], "the array indices must be gone, not merely shadowed")
end)

test("the migration bumps the stored schema version so it runs once", function()
    local inst = T.load(false)
    local NS2 = inst.NS
    inst.mocks.KickCDDB = { global = { schemaVersion = 3 }, profile = {} }
    pcall(NS2.OnInitialize, NS2)
    assertTrue(NS2.db.global.schemaVersion >= 4,
        "expected schemaVersion >= 4, got " .. tostring(NS2.db.global.schemaVersion))
end)

test("an already-keyed color passes through the migration untouched", function()
    -- Idempotence. The ladder is keyed on schemaVersion so it should not re-run,
    -- but a converter that mangled an already-converted value would be a
    -- one-reload data loss the version guard could not undo.
    local inst = T.load(false)
    local NS2 = inst.NS
    inst.mocks.KickCDDB = {
        global  = { schemaVersion = 3 },
        profile = {
            units = { target = { icons = {
                cooldownTint = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 },
            } } },
        },
    }
    pcall(NS2.OnInitialize, NS2)
    local v = NS2.db.profile.units.target.icons.cooldownTint
    assertNear(v.r, 0.1, 1e-9)
    assertNear(v.g, 0.2, 1e-9)
    assertNear(v.b, 0.3, 1e-9)
    assertNear(v.a, 0.4, 1e-9)
end)

-- ── the CLI, end to end ─────────────────────────────────────────────────────

test("the slash layer needs no color codec now the shapes agree", function()
    -- The adapter this decision deleted. settings/Slash.lua carried a get-side
    -- array->keyed conversion and a parse-side keyed->array conversion purely
    -- because the two shapes disagreed.
    -- red under: reinstating either conversion
    local fh = assert(io.open(T.root .. "/settings/Slash.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match("{ v%.r, v%.g, v%.b, v%.a }"),
        "settings/Slash.lua still folds a parsed color back into an array")
    assertNil(src:match("r = v%[1%]"),
        "settings/Slash.lua still converts a stored color on read")
end)

test("set and get round-trip a color through the library with no translation", function()
    local H = NS.Settings.Helpers
    local row = colorRows()[1]
    local before = H.Get(row.path)

    NS:OnSlashCommand("set " .. row.path .. " 0.25 0.5 0.75 0.5")
    local stored = H.Get(row.path)
    assertNear(stored.r, 0.25, 1e-9)
    assertNear(stored.g, 0.5, 1e-9)
    assertNear(stored.b, 0.75, 1e-9)
    assertNear(stored.a, 0.5, 1e-9)
    assertNil(stored[1], "the library must write the keyed shape directly")

    H.SetAndRefresh(row.path, before)
end)

-- ── the dropdown vocabulary ─────────────────────────────────────────────────

test("every dropdown row's values is a keyed hash, never an array of records", function()
    -- red under: reverting one row to `values = { { value = .., label = .. } }`
    --
    -- The library reads `values` as { key = label } and `sorting` as the order.
    -- An array of records is silently invisible to both halves: the parser would
    -- offer "1, 2, 3 ..." as the allowed values and the dropdown would list the
    -- indices instead of the options.
    for _, def in ipairs(NS.Settings.Schema) do
        if def.type == "string" and type(def.values) == "table" then
            for k, v in pairs(def.values) do
                assertEqual(type(k), "string",
                    def.path .. " has a non-string values key — still an array?")
                assertEqual(type(v), "string", def.path .. " values[" .. tostring(k) .. "]")
            end
        end
    end
end)

test("every static dropdown declares its order, so nothing silently alphabetizes", function()
    -- A hash has no order, and the widget makers fall back to table.sort when a
    -- row gives none. That scrambles lists whose reading order is the point —
    -- the 13 anchors, and grow directions like "First right then down".
    local missing = {}
    for _, def in ipairs(NS.Settings.Schema) do
        if def.type == "string" and type(def.values) == "table" then
            if type(def.sorting) ~= "table" then
                missing[#missing + 1] = def.path
            else
                for _, key in ipairs(def.sorting) do
                    assertTrue(def.values[key] ~= nil,
                        def.path .. " sorting names '" .. tostring(key) .. "', absent from values")
                end
                local n = 0
                for _ in pairs(def.values) do n = n + 1 end
                assertEqual(#def.sorting, n, def.path .. " sorting must cover every option")
            end
        end
    end
    assertEqual(#missing, 0, "static dropdown with no sorting: " .. table.concat(missing, ", "))
end)

test("the anchor dropdown still reads top row, bottom row, sides, center", function()
    -- The one list where alphabetizing is obviously wrong to a user: it would
    -- put BOTTOM_LEFT first and CENTER fourth.
    local H = NS.Settings.Helpers
    local order = H.AnchorOrder()
    assertEqual(order[1], "TOP_LEFT")
    assertEqual(order[4], "BOTTOM_LEFT")
    assertEqual(order[13], "CENTER")
    local values = H.AnchorValues()
    for _, k in ipairs(order) do
        assertTrue(values[k] ~= nil, "AnchorOrder names " .. k .. ", absent from AnchorValues")
    end
end)

test("an LSM-backed row resolves its values at call time, never at declaration", function()
    -- Every media row evaluates inside a schema-row literal at FILE LOAD, long
    -- before the addons that register media have run. A snapshot table there
    -- freezes the list at whatever happened to be registered first.
    local row
    for _, def in ipairs(NS.Settings.Schema) do
        if def.path:find("Texture", 1, true) or def.path:find("font", 1, true) then
            if type(def.values) == "function" then row = def break end
        end
    end
    assertTrue(row ~= nil, "expected at least one deferred media row")
    local resolved = row.values()
    assertEqual(type(resolved), "table")
    for k, v in pairs(resolved) do
        assertEqual(type(k), "string", "media values must be keyed")
        assertEqual(type(v), "string")
    end
end)

test("the valueGate hint explains WHY a gated dropdown value was rejected", function()
    -- This capability was lost when the schema CLI moved to the library and had
    -- to be rebuilt: the comment moved but the code did not. Without it a user
    -- who types a sensible growDirection gets "Allowed values: ..." and no clue
    -- why the option they wanted is missing.
    -- red under: returning "" from NS.Slash.GateHint
    local row
    for _, def in ipairs(NS.Settings.Schema) do
        if def.valueGate then row = def break end
    end
    assertTrue(row ~= nil, "the schema declares no valueGate row to exercise")

    local hint = NS.Slash.GateHint(row)
    assertTrue(hint:find("depends on", 1, true) ~= nil,
        "the hint must name the gating setting; got: " .. hint)
    assertTrue(hint:find(row.valueGate, 1, true) ~= nil, "and name it by path; got: " .. hint)
    assertTrue(hint:find("flip", 1, true) ~= nil,
        "and say what flipping the gate would offer; got: " .. hint)
end)

test("a rejected gated value carries the hint through the slash layer", function()
    local row
    for _, def in ipairs(NS.Settings.Schema) do
        if def.valueGate then row = def break end
    end
    local lines = {}
    local frame = T.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    NS:OnSlashCommand("set " .. row.path .. " DEFINITELY_NOT_A_VALUE")
    frame.AddMessage = orig
    local text = table.concat(lines, "\n")
    assertTrue(text:find("Invalid value for", 1, true) ~= nil, "got: " .. text)
    assertTrue(text:find("depends on", 1, true) ~= nil,
        "the gate hint must reach the user; got: " .. text)
end)
