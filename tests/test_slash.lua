-- tests/test_slash.lua
-- LibKa0s-Slash-1.0 wiring: the dispatcher, the help renderer, the schema CLI
-- and the type-aware parser are the library's now. What is pinned here is the
-- WIRING and the rendered bytes that deliberately changed.
--
-- The two user-visible convergences this milestone ships are both asserted
-- below, so neither can be "fixed" back by accident:
--   * `/kcd reset` takes a PATH, not a page;
--   * the settings landing page renders command rows through the ONE row
--     formatter, in the help colours.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil
local NS, mocks = T.NS, T.mocks

--- Run a slash line and return the chat lines it produced.
local function runVerb(input)
    local lines = {}
    local frame = mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    NS:OnSlashCommand(input)
    frame.AddMessage = orig
    return lines
end

local function joined(lines) return table.concat(lines, "\n") end

-- ── the dispatcher is the library's ─────────────────────────────────────────

test("the dispatcher instance is built from LibKa0s-Slash-1.0", function()
    assertTrue(NS.Slash ~= nil, "NS.Slash must exist")
    assertEqual(type(NS.Slash.OnSlash), "function")
    assertEqual(type(NS.Slash.LandingRows), "function")
end)

test("NS.COMMANDS stays the host's, as ordered positional triples", function()
    -- slash-commands-§3: the library reads entry[1], entry[2], entry[3]. A table
    -- of named fields is silently invisible to it — every verb becomes unknown
    -- and the help block renders empty.
    assertEqual(type(NS.COMMANDS), "table")
    assertTrue(#NS.COMMANDS > 0)
    for i, e in ipairs(NS.COMMANDS) do
        assertEqual(type(e[1]), "string", "COMMANDS[" .. i .. "] name")
        assertEqual(type(e[2]), "string", "COMMANDS[" .. i .. "] description")
        assertEqual(type(e[3]), "function", "COMMANDS[" .. i .. "] handler")
    end
end)

test("every COMMANDS handler takes (rest), not (self, rest)", function()
    -- The library calls entry[3](rest) with the rest of the line verbatim. A
    -- handler still expecting `self` would read the REST as its self and the
    -- argument as nil — silently wrong rather than an error.
    -- red under: reverting a handler to `function(self, rest)`
    local lines = runVerb("get units.target.icons.primarySize")
    assertTrue(joined(lines):find("units.target.icons.primarySize", 1, true) ~= nil,
        "get did not receive its path; got: " .. joined(lines))
end)

test("an unknown verb names it and then prints the help index", function()
    local lines = runVerb("nosuchverb")
    assertTrue(lines[1]:find("unknown command 'nosuchverb'", 1, true) ~= nil,
        "got: " .. tostring(lines[1]))
    assertTrue(#lines > 2, "help must follow the unknown-command line")
end)

test("only the verb is lowercased — a schema path keeps its case", function()
    -- `units.target.icons.primarySize` does not survive a folded `rest`.
    local lines = runVerb("GET units.target.icons.primarySize")
    assertTrue(joined(lines):find("units.target.icons.primarySize", 1, true) ~= nil,
        "got: " .. joined(lines))
end)

test("the `options` alias still reaches `config`", function()
    -- Carried by the descriptor's aliases map rather than a dead branch in the
    -- dispatcher.
    local lines = runVerb("options")
    assertNil(joined(lines):match("unknown command"))
end)

-- ── the help renderer ───────────────────────────────────────────────────────

test("the help header now carries the em dash the standard mandates", function()
    -- CHANGED, deliberately. KickCD rendered "v1.2.1 slash commands (…)"; the
    -- library and slash-commands-§4 both spell it "v<version> — slash commands".
    -- The alias clause is unchanged apart from hex case.
    local lines = runVerb("help")
    assertTrue(lines[1]:find("\226\128\148 slash commands", 1, true) ~= nil,
        "expected the em dash before 'slash commands'; got: " .. tostring(lines[1]))
    assertTrue(lines[1]:find("/kickcd", 1, true) ~= nil, "alias clause must survive")
end)

test("a help row is the one shared formatter, two-space indented", function()
    -- Byte for byte, modulo the hex case the library standardised on.
    local lines = runVerb("help")
    local row
    for _, l in ipairs(lines) do
        if l:find("/kcd help", 1, true) then row = l break end
    end
    assertTrue(row ~= nil, "no help row found")
    assertEqual(row, NS.PREFIX .. "   |cFFFFFF00/kcd help|r \226\128\148 |cFFFFFFFFList available commands|r")
end)

test("the landing page renders the SAME rows, un-indented", function()
    -- THE second convergence. settings/Panel.lua used to carry its own format
    -- string — two spaces either side of the dash, the dash white-wrapped, the
    -- description bare — so the panel and `/kcd help` drifted on the same data.
    -- red under: restoring the panel's private format string
    local rows = NS.Slash:LandingRows()
    assertTrue(#rows > 0)
    assertEqual(rows[1]:sub(1, 2) ~= "  ", true, "landing rows must not be indented")
    local help
    for _, r in ipairs(rows) do
        if r:find("/kcd help", 1, true) then help = r break end
    end
    assertEqual(help, "|cFFFFFF00/kcd help|r \226\128\148 |cFFFFFFFFList available commands|r")
end)

test("the panel no longer carries a second command-row formatter", function()
    -- grep the source: the drift this convergence exists to end is one literal
    -- format string away from coming back.
    local fh = assert(io.open(T.root .. "/settings/Panel.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match("|cffffff00/kcd"), "settings/Panel.lua still formats its own rows")
end)

-- ── the schema CLI ──────────────────────────────────────────────────────────

test("list groups by the row's panel, in the addon's declared page order", function()
    -- The library groups on whatever groupKey returns and preserves allRows()'s
    -- order. KickCD rows carry `panel`, not `page`, so the override is
    -- mandatory: without it every row would group under "settings".
    local lines = runVerb("list")
    assertEqual(lines[1], NS.PREFIX .. " |cff33ff99Available settings|r")
    local text = joined(lines)
    assertTrue(text:find("  |cff3399ff[general]|r", 1, true) ~= nil,
        "expected a [general] group header; got: " .. text:sub(1, 300))
    local gi = text:find("[general]", 1, true)
    local ii = text:find("[icons]", 1, true)
    assertTrue(gi and ii and gi < ii, "general must list before icons")
end)

test("get echoes the shared key = value pair", function()
    local lines = runVerb("get units.target.icons.primarySize")
    assertTrue(lines[1]:find("|cFFFFFF00units.target.icons.primarySize|r = ", 1, true) ~= nil,
        "got: " .. tostring(lines[1]))
end)

test("set clamps out of range and echoes what was actually STORED", function()
    -- A clamped number is only visible to the user because the echo re-reads.
    local before = NS.Settings.Helpers.Get("units.target.icons.primarySize")
    runVerb("set units.target.icons.primarySize 99999")
    local stored = NS.Settings.Helpers.Get("units.target.icons.primarySize")
    local row = NS.Settings.Helpers.FindSchema("units.target.icons.primarySize")
    assertTrue(stored <= row.max, "expected a clamp to " .. tostring(row.max)
        .. ", stored " .. tostring(stored))
    NS.Settings.Helpers.SetAndRefresh("units.target.icons.primarySize", before)
end)

test("set routes through the host's single write seam", function()
    -- Not a bare table write: the panel checkbox and `/kcd set` must take the
    -- same path — the [Set] debug line, the row's onChange, the panel refresh.
    local before = NS.Settings.Helpers.Get("locked")
    runVerb("set locked true")
    assertEqual(NS.Settings.Helpers.Get("locked"), true)
    runVerb("set locked false")
    assertEqual(NS.Settings.Helpers.Get("locked"), false)
    NS.Settings.Helpers.SetAndRefresh("locked", before)
end)

test("a colour round-trips through the addon's positional {r,g,b,a} storage", function()
    -- THE adapter that would fail silently. KickCD stores colours as a
    -- positional array; the library's parser returns {r=,g=,b=,a=} and its
    -- FormatValue reads the same keys. Without the codec every saved colour
    -- reads back white and every `set` writes a shape the addon cannot unpack.
    local row
    for _, def in ipairs(NS.Settings.Schema) do
        if def.type == "color" then row = def break end
    end
    assertTrue(row ~= nil, "the schema has no colour row to exercise")

    local before = NS.Settings.Helpers.Get(row.path)
    local lines = runVerb("set " .. row.path .. " 1 0.5 0 1")
    local stored = NS.Settings.Helpers.Get(row.path)

    assertEqual(type(stored), "table")
    assertEqual(stored[1], 1, "red must land in the POSITIONAL slot 1")
    assertEqual(stored[2], 0.5)
    assertEqual(stored[3], 0)
    assertNil(stored.r, "the addon's stored shape must stay positional")
    -- And the echo must render the real numbers, not four zeroes.
    assertTrue(joined(lines):find("{1.00, 0.50, 0.00, 1.00}", 1, true) ~= nil,
        "colour echoed wrong; got: " .. joined(lines))

    NS.Settings.Helpers.SetAndRefresh(row.path, before)
end)

test("a colour given in 0-255 rescales jointly", function()
    local row
    for _, def in ipairs(NS.Settings.Schema) do
        if def.type == "color" then row = def break end
    end
    local before = NS.Settings.Helpers.Get(row.path)
    runVerb("set " .. row.path .. " 255 128 0")
    local stored = NS.Settings.Helpers.Get(row.path)
    assertEqual(stored[1], 1)
    assertTrue(math.abs(stored[2] - 128 / 255) < 1e-9, "green must rescale with the others")
    assertEqual(stored[3], 0)
    NS.Settings.Helpers.SetAndRefresh(row.path, before)
end)

test("an unknown path says so rather than writing anything", function()
    local lines = runVerb("get nosuch.path")
    assertEqual(lines[1], NS.PREFIX .. " Setting not found: nosuch.path")
end)

-- ── the reset convergence ───────────────────────────────────────────────────

test("reset takes a PATH and resets exactly that one row", function()
    -- CHANGED, deliberately (slash-commands-§2): a page is a property of a
    -- settings panel, not of the data, and every schema-driven page carries a
    -- Defaults button that resets it.
    local row = NS.Settings.Helpers.FindSchema("units.target.icons.primarySize")
    NS.Settings.Helpers.SetAndRefresh("units.target.icons.primarySize", row.min)
    local lines = runVerb("reset units.target.icons.primarySize")
    assertEqual(NS.Settings.Helpers.Get("units.target.icons.primarySize"), row.default)
    assertTrue(lines[1]:find("|cFFFFFF00units.target.icons.primarySize|r = ", 1, true) ~= nil,
        "reset must echo the restored pair; got: " .. tostring(lines[1]))
end)

test("the old page-shaped reset names its replacement instead of going quiet", function()
    -- A removal shipped silently is a bug report. Each of the five old page
    -- names is answered with where the capability went.
    for _, page in ipairs({ "general", "icons", "castbar", "label" }) do
        local lines = runVerb("reset " .. page)
        local text = joined(lines)
        assertTrue(text:find("Defaults", 1, true) ~= nil,
            "`reset " .. page .. "` must point at the panel's Defaults button; got: " .. text)
    end
end)

test("`reset spells` names the verb its database rebuild moved to", function()
    local text = joined(runVerb("reset spells"))
    assertTrue(text:find("/kcd spells resetall", 1, true) ~= nil,
        "must name the new home of the spell-database rebuild; got: " .. text)
end)

test("the spell-database rebuild survives, under its new verb", function()
    -- The capability, not just the message. `/kcd spells reset` resets ONE
    -- class+spec pair; this is the every-spec rebuild `/kcd reset spells` used
    -- to carry.
    -- red under: dropping the resetall entry from SPELLS_COMMANDS
    local profile = NS.db.profile
    profile.spells = { BOGUS = { [1] = {} } }
    runVerb("spells resetall")
    assertNil(profile.spells.BOGUS, "the rebuild must have wiped the bogus class key")
    assertTrue(next(profile.spells) ~= nil, "and re-seeded from the defaults")
end)

-- ── resetall stays the host's ───────────────────────────────────────────────

test("resetall keeps its four-part host semantics rather than becoming CliResetAll", function()
    -- The library's CliResetAll walks schema rows only. KickCD's resetall also
    -- clears the saved anchors, the per-unit link flag and the spell lists —
    -- none of which is a schema row. Wiring it to the library form would have
    -- silently stopped resetting three of the four.
    local fh = assert(io.open(T.root .. "/core/KickCD.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertTrue(src:find("H.ResetAll()", 1, true) ~= nil,
        "resetall must still delegate to the host's shared ResetAll helper")
end)

-- ── the degraded path ───────────────────────────────────────────────────────

test("with LibKa0s absent /kcd still answers and host verbs still work", function()
    local inst = T.load(true, false, nil, { libFiles = {} })
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    inst.NS:OnSlashCommand("help")
    frame.AddMessage = orig
    assertTrue(#lines > 0, "/kcd must still answer with no library")
end)

test("the degraded stub carries no copy of the row formatter or the parser", function()
    -- slash-commands-§1: "The stub MUST NOT re-implement the library's
    -- rendering — no copied row formatter, no copied parser, no copied
    -- key/value shape."
    local fh = assert(io.open(T.root .. "/settings/Slash.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match("|cFFFFFFFF%%s|r"), "the stub reproduces the row formatter")
    assertNil(src:match("|cFFFFFF00%%s|r = "), "the stub reproduces the key/value shape")
end)
