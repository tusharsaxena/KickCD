-- tests/test_slash.lua
-- LibKa0s-Slash-1.0 wiring: the dispatcher, the help renderer, the schema CLI
-- and the type-aware parser are the library's now. What is pinned here is the
-- WIRING and the rendered bytes that deliberately changed.
--
-- The two user-visible convergences this milestone ships are both asserted
-- below, so neither can be "fixed" back by accident:
--   * `/kcd reset` takes a PATH, not a page;
--   * the settings landing page renders command rows through the ONE row
--     formatter, in the help colors.

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
    -- Byte for byte, modulo the hex case the library standardized on.
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
    local before = NS.Settings.Store.Get("units.target.icons.primarySize")
    runVerb("set units.target.icons.primarySize 99999")
    local stored = NS.Settings.Store.Get("units.target.icons.primarySize")
    local row = NS.Settings.Store.FindRow("units.target.icons.primarySize")
    assertTrue(stored <= row.max, "expected a clamp to " .. tostring(row.max)
        .. ", stored " .. tostring(stored))
    NS.Settings.Helpers.SetAndRefresh("units.target.icons.primarySize", before)
end)

test("set routes through the host's single write seam", function()
    -- Not a bare table write: the panel checkbox and `/kcd set` must take the
    -- same path — the [Set] debug line, the row's onChange, the panel refresh.
    local before = NS.Settings.Store.Get("locked")
    runVerb("set locked true")
    assertEqual(NS.Settings.Store.Get("locked"), true)
    runVerb("set locked false")
    assertEqual(NS.Settings.Store.Get("locked"), false)
    NS.Settings.Helpers.SetAndRefresh("locked", before)
end)

test("a color round-trips through the library with no host translation", function()
    -- This used to need a codec: the addon stored colors positionally while the
    -- library parsed and rendered the keyed shape. The STORAGE migrated instead
    -- (core/Database.lua v3 -> v4), so the two agree and settings/Slash.lua
    -- carries no color conversion at all.
    local row
    for _, def in ipairs(NS.Settings.Schema) do
        if def.type == "color" then row = def break end
    end
    assertTrue(row ~= nil, "the schema has no color row to exercise")

    local before = NS.Settings.Store.Get(row.path)
    local lines = runVerb("set " .. row.path .. " 1 0.5 0 1")
    local stored = NS.Settings.Store.Get(row.path)

    assertEqual(type(stored), "table")
    assertEqual(stored.r, 1, "red must land in the keyed slot")
    assertEqual(stored.g, 0.5)
    assertEqual(stored.b, 0)
    assertNil(stored[1], "the stored shape must be keyed, not positional")
    -- And the echo must render the real numbers, not four zeroes.
    assertTrue(joined(lines):find("{1.00, 0.50, 0.00, 1.00}", 1, true) ~= nil,
        "color echoed wrong; got: " .. joined(lines))

    NS.Settings.Helpers.SetAndRefresh(row.path, before)
end)

test("a color given in 0-255 rescales jointly", function()
    local row
    for _, def in ipairs(NS.Settings.Schema) do
        if def.type == "color" then row = def break end
    end
    local before = NS.Settings.Store.Get(row.path)
    runVerb("set " .. row.path .. " 255 128 0")
    local stored = NS.Settings.Store.Get(row.path)
    assertEqual(stored.r, 1)
    assertTrue(math.abs(stored.g - 128 / 255) < 1e-9, "green must rescale with the others")
    assertEqual(stored.b, 0)
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
    local row = NS.Settings.Store.FindRow("units.target.icons.primarySize")
    NS.Settings.Helpers.SetAndRefresh("units.target.icons.primarySize", row.min)
    local lines = runVerb("reset units.target.icons.primarySize")
    assertEqual(NS.Settings.Store.Get("units.target.icons.primarySize"), row.default)
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

-- ── bare /kcd is `config` (slash-commands-§4) ───────────────────────────────
--
-- LibKa0s-Slash-1.0 minor 11: empty or whitespace-only input runs the host's
-- `config` handler with "", and `/kcd help` is the only route to the list.
-- The stub in settings/Slash.lua mirrors it, so both halves are pinned.

--- True when any captured line is the help header ("v<x> — slash commands").
local function printedHelp(lines)
    for _, l in ipairs(lines) do
        if l:find("slash commands", 1, true) then return true end
    end
    return false
end

test("bare /kcd opens the settings landing page through `config`", function()
    -- Enabled, so OnEnable has registered the category the open is handed.
    -- red under: `if raw == "" then return self:PrintHelp() end` in the library
    local opened = {}
    local inst = T.load(true, true, function(m)
        m.Settings.OpenToCategory = function(id) opened[#opened + 1] = id end
    end)
    local lines = {}
    inst.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }

    inst.NS:OnSlashCommand("")
    assertEqual(#opened, 1, "bare /kcd must open the settings panel")
    assertTrue(opened[1] ~= nil, "the open must be handed a registered category")
    assertTrue(not printedHelp(lines), "bare /kcd must not print the help list")

    -- The same page `/kcd config` lands on, which is the parent category.
    inst.NS:OnSlashCommand("config")
    assertEqual(opened[2], opened[1], "bare /kcd and /kcd config must open the same page")

    -- ...and `help` still prints the list without opening anything.
    inst.NS:OnSlashCommand("help")
    assertEqual(#opened, 2, "/kcd help must not open the settings panel")
    assertTrue(printedHelp(lines), "/kcd help must print the list")
end)

test("whitespace-only /kcd is bare and reaches `config` too", function()
    local calls = 0
    local real = NS.OpenSettings
    NS.OpenSettings = function() calls = calls + 1 end
    local out1 = runVerb("   ")
    local out2 = runVerb("\t ")
    NS.OpenSettings = real
    assertEqual(calls, 2, "whitespace-only input must run `config`")
    assertTrue(not printedHelp(out1) and not printedHelp(out2),
        "whitespace-only input must not print the help list")
end)

test("with LibKa0s absent bare /kcd still reaches `config`", function()
    -- red under: `if raw == "" then return stub.PrintHelp() end` in the stub
    local inst = T.load(true, false, nil, { libFiles = {} })
    local calls = 0
    inst.NS.OpenSettings = function() calls = calls + 1 end
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    inst.NS:OnSlashCommand("")
    inst.NS:OnSlashCommand("  ")
    frame.AddMessage = orig
    assertEqual(calls, 2, "the stub must run `config` on bare and whitespace-only input")
    assertTrue(not printedHelp(lines), "the stub must not print the help list on bare input")
end)

-- `/kcd lock` writes `locked` through the helper or not at all (#20). It used to
-- fall back to `db.profile.locked = v` whenever SetAndRefresh could not take the
-- write, which put a schema-row path around the helper. The helper is the schema
-- seam now (LibKa0s-Schema-1.0), and `locked` is on its writeThrough list
-- (settings/SchemaSetup.lua, options-ui-§1 route (a)): on a load where the
-- composer that declares the row is absent, the seam still stores it -- raw, and
-- announced -- so the verb keeps working on the load it most needs to survive.
-- The refusal stays for a load where the settings layer never came up at all.

--- Run one COMMANDS verb's handler directly and return what it printed. Direct,
--- because a LibKa0s-absent load has no dispatcher to route `/kcd lock` through.
local function runHandler(inst, verb)
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    local ok, err
    for _, e in ipairs(inst.NS.COMMANDS) do
        if e[1] == verb then ok, err = pcall(e[3], "") end
    end
    frame.AddMessage = orig
    if ok == false then error(err, 0) end
    return joined(lines)
end

test("/kcd lock with no `locked` row still writes it, through the seam's writeThrough", function()
    -- red under: an empty writeThrough list, where the seam refuses a row-less
    -- `locked` and the verb says the settings layer is not ready.
    local inst = T.load(true)
    local ns = inst.NS
    local schema = ns.Settings.Schema
    for i = #schema, 1, -1 do
        if schema[i].path == "locked" then table.remove(schema, i) end
    end
    ns.Settings.Store.Reindex()
    assertNil(ns.Settings.Store.FindRow("locked"), "sanity: the row is gone")
    ns.db.profile.locked = false
    local fired = {}
    local H = ns.Settings.Helpers
    local realFire = H.FireConfigChanged
    H.FireConfigChanged = function(section, ...) fired[#fired + 1] = section; return realFire(section, ...) end
    local ok, out = pcall(runHandler, inst, "lock")
    H.FireConfigChanged = realFire
    if not ok then error(out, 0) end

    assertEqual(ns.db.profile.locked, true, "the seam stored the row-less path")
    assertEqual(#fired, 1, "and announced it once")
    assertEqual(fired[1], "general", "under the General page's section")
    assertTrue(out:find("icon grid locked", 1, true) ~= nil, "the verb confirms; got: " .. out)
end)

test("/kcd lock before the settings layer is up writes nothing and says why", function()
    -- red under: restoring the `self.db.profile.locked = v` fallback in setLocked
    local inst = T.load(true)
    local ns = inst.NS
    ns.db.profile.locked = false
    local realSet = ns.Settings.Helpers.SetAndRefresh
    ns.Settings.Helpers.SetAndRefresh = nil
    local ok, out = pcall(runHandler, inst, "lock")
    ns.Settings.Helpers.SetAndRefresh = realSet
    if not ok then error(out, 0) end
    assertEqual(ns.db.profile.locked, false, "no helper, no write")
    assertTrue(out:find("Settings layer not ready yet", 1, true) ~= nil,
        "the refusal must say why; got: " .. out)
    assertNil(out:find("icon grid locked", 1, true), "it must not claim the grid locked")
end)

test("with LibKa0s absent /kcd lock and /kcd toggle still write, through the stub's writeThrough", function()
    -- The real no-row case: `locked` is composed by LibKa0s-Options-1.0's Master
    -- controls block, so a library-less load has no such row. The Schema
    -- degradation stub takes the same writeThrough list the live instance does.
    -- red under: a stub that refuses every row-less path.
    local inst = T.load(true, false, nil, { libFiles = {} })
    inst.NS.db.profile.locked = false
    runHandler(inst, "lock")
    assertEqual(inst.NS.db.profile.locked, true, "lock landed in the store")
    runHandler(inst, "toggle")
    assertEqual(inst.NS.db.profile.locked, false, "toggle landed in the store")
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

-- ── the L trap ──────────────────────────────────────────────────────────────
--
-- KickCD SHIPPED this bug once (a perf panel rendering PANEL_TITLE_SUFFIX,
-- STEP_START, STEP_MEASURE_A verbatim), so the guard is extended here to the
-- Slash major rather than left to Perf alone.
--
-- The failure: a module that takes an `L` override resolves the descriptor's
-- table first and falls through to lib.STRINGS only when the override is NOT a
-- string. This addon's NS.L carries the metatable fallback the standard MANDATES
-- (locales/enUS.lua:15 — a miss returns the KEY), so handing a descriptor NS.L
-- makes lib.STRINGS unreachable for EVERY key at once, in-game only.
--
-- Which half of the pair below is falsifiable, stated honestly:
--   * the FIRST case pins the rendered result. It reddens when a host puts a
--     raw key into the override table.
--   * the SECOND case is the one that reddens on a LIBRARY regression — swap
--     Slash.lua's `rawget(strings, key)` for a plain index and it fires. That is
--     the drift a re-vendor introduces with both repos green.
-- Note for whoever mutates this file: `L = NS.L` on the descriptor no longer
-- reddens EITHER case, because Slash 4 resolves the override with rawget and
-- NS.L is keyed by English phrases, so rawget misses and lib.STRINGS wins. The
-- descriptor mistake is caught by the source check in test_perfsetup.lua.

test("every string the Slash CLI renders resolves to prose, not to its own key", function()
    -- red under: `L = NS.L and { LIST_HEADER = "LIST_HEADER" } or nil`
    -- in settings/Slash.lua
    local lib = mocks.LibStub("LibKa0s-Slash-1.0", true)
    assertTrue(lib ~= nil, "the vendored Slash major must be registered")
    local cli = NS.Slash.cli
    assertTrue(cli ~= nil, "the library instance must be reachable for this to mean anything")
    assertEqual(type(cli.Text), "function", "Text is THE resolver; without it this case proves nothing")

    -- Every key the library declares, through the live instance's own resolver.
    for key in pairs(lib.STRINGS) do
        local rendered = cli:Text(key)
        assertEqual(type(rendered), "string", "Text('" .. key .. "') returned no string")
        -- The exact shape of the trap: the rendered string IS the key.
        assertTrue(rendered ~= key, "'" .. key .. "' rendered its own key verbatim")
        assertNil(rendered:match("^[A-Z][A-Z0-9_]+$"),
            "'" .. key .. "' rendered its raw key: " .. rendered)
    end

    -- ...and the strings the addon does NOT override still come from the
    -- library, which is the half a bare `NS.L` would take away.
    for _, key in ipairs({ "LIST_GROUP", "LIST_EMPTY", "NOT_FOUND", "USAGE_GET",
                           "USAGE_SET", "USAGE_RESET", "RESET_ALL", "HELP_HEADER" }) do
        assertEqual(cli:Text(key), lib.STRINGS[key],
            "'" .. key .. "' must fall through to the library's own string")
    end

    -- The one override this addon declares is byte-identical to the library's
    -- default (settings/Slash.lua:331 says so). Pinned so a future divergence in
    -- either direction is a decision rather than a surprise.
    assertEqual(cli:Text("LIST_HEADER"), lib.STRINGS.LIST_HEADER)
end)

test("no chrome line /kcd prints is a raw SCREAMING_SNAKE key", function()
    -- The end-to-end form: the actual chat output, not the resolver.
    --
    -- Scoped to the library's CHROME — headers, usage lines, errors — and
    -- deliberately not to `path = value` rows: a stored enum token legitimately
    -- IS SCREAMING_SNAKE ("RIGHT_MIDDLE" is the value, not an unresolved key),
    -- so a blanket sweep cannot tell the two apart and would be a case that
    -- fails for the wrong reason. Same reason ERR_ALLOWED is not driven here:
    -- "allowed values: TOP_LEFT, ..." is a list of stored tokens by design.
    -- red under: `L = NS.L and { LIST_HEADER = "LIST_HEADER" } or nil`
    local KV = " = "   -- lib.FormatKV's separator; the rows that carry values
    local checked = 0
    for _, input in ipairs({ "help", "list", "get nosuchpath", "set enabled" }) do
        for _, line in ipairs(runVerb(input)) do
            if not line:find(KV, 1, true) then
                checked = checked + 1
                -- Strip color escapes first: |cFFFFFF00 is not a rendered word.
                local text = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                for word in text:gmatch("%a[%a%d_]*") do
                    assertNil(word:match("^[A-Z][A-Z0-9]*_[A-Z0-9_]*$"),
                        "'" .. input .. "' printed a raw key '" .. word .. "' in: " .. line)
                end
            end
        end
    end
    assertTrue(checked > 0, "no chrome lines were produced; the sweep proved nothing")
end)

test("the vendored Slash major falls THROUGH a key-returning locale table", function()
    -- The library-regression half. A locale table whose __index answers every
    -- key with the key is what every Ka0s host hands around; the library must
    -- treat it as EMPTY, because a synthesized value is still a string.
    --
    -- red under: `local v = strings and rawget(strings, key)` ->
    -- `local v = strings and strings[key]` in libs/LibKa0s/Slash.lua
    local lib = mocks.LibStub("LibKa0s-Slash-1.0", true)
    local cli = lib:New({
        slash    = "/trapprobe",
        commands = { { "help", "show help" } },
        version  = function() return "1.0.0" end,
        allRows  = function() return {} end,
        L        = setmetatable({}, { __index = function(_, k) return k end }),
    })
    for key in pairs(lib.STRINGS) do
        local rendered = cli:Text(key)
        assertNil(rendered:match("^[A-Z][A-Z0-9_]+$"),
            "the vendored library let the synthesized key '" .. key .. "' through as '"
            .. tostring(rendered) .. "'")
        assertEqual(rendered, lib.STRINGS[key],
            "'" .. key .. "' must fall through to the library's own string")
    end
end)

-- ── a free-text value keeps every word ──────────────────────────────────────

test("set stores a multi-word label text whole", function()
    -- LibKa0s-Slash-1.0 minor 10 hands a string row the whole remainder,
    -- trimmed. Through minor 9 it took the first word, so `/kcd set
    -- units.target.label.text Kick Them Now` stored "Kick". parseForHost
    -- (settings/Slash.lua) only adds a hint to a refusal, so it passes the
    -- library's value through untouched.
    -- red under: Slash.lua minor 9 (the parse splitting a string row's value).
    local path = "units.target.label.text"
    local before = NS.Settings.Store.Get(path)
    local out = runVerb("set " .. path .. "  Kick Them Now ")
    assertEqual(NS.Settings.Store.Get(path), "Kick Them Now", joined(out))
    NS.Settings.Helpers.SetAndRefresh(path, before)
end)

-- ── the disabled state (slash-commands-§2) ──────────────────────────────────
--
-- The rule: while `enabled` is false, a verb that DRIVES THE ADDON'S FEATURES
-- answers on ONE tagged line naming `/kcd enable` and DOES NOTHING ELSE. Every
-- case below asserts both halves, because a case that only reads the message
-- passes happily over a verb that printed the line and then acted anyway.
--
-- Each runs on its own instance: disabling is a stored write, and the shared
-- instance the rest of this suite uses would carry it into every later case.

--- A fresh instance with the addon turned OFF through its own verb, so the state
--- under test is the one a player reaches rather than a hand-written key.
local function disabled()
    local inst = T.load(true, true)
    local real = inst.NS.Util.print
    inst.NS.Util.print = function() end
    inst.NS:OnSlashCommand("disable")
    inst.NS.Util.print = real
    assertEqual(inst.NS.db.profile.enabled, false, "sanity: the addon is off")
    return inst
end

--- Everything NS.Util.print emits while `fn` runs, on `inst`.
local function say(inst, fn)
    local lines, real = {}, inst.NS.Util.print
    inst.NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    inst.NS.Util.print = real
    if not ok then error(err, 0) end
    return lines
end

-- The live set, slash-commands-§2's twelve plus this addon's `spells` (the spell
-- lists are stored ARRAYS no schema row can address, so `/kcd spells` is their
-- only CLI route — see core/KickCD.lua). Typed here rather than read off the
-- addon, so that the two lists have to be changed together: a verb added to the
-- addon's live set and not to this one goes red, while a NEW feature verb is
-- gated by default and passes without a word.
local LIVE = {
    "help", "config", "version", "enable", "disable", "debug", "perf",
    "get", "set", "list", "reset", "resetall", "spells",
}

test("a disabled feature verb says so on ONE line, and does NOT act", function()
    -- The headline case, on the verb that would be loudest if it acted: `/kcd
    -- toggle` flips the lock, which is this addon's preview switch (launcher-§2
    -- rung (b)). A refusal that still flipped it would leave the player with a
    -- message saying nothing happened and a stored value saying it did.
    -- red under: the gate printing and then falling through to the handler
    local inst = disabled()
    local before = inst.NS.db.profile.locked
    local lines = say(inst, function() inst.NS:OnSlashCommand("toggle") end)
    assertEqual(#lines, 1, "one line, and one only: " .. table.concat(lines, " / "))
    assertTrue(lines[1]:find("/kcd enable", 1, true) ~= nil,
        "the line must name the verb that turns it back on: " .. lines[1])
    assertEqual(inst.NS.db.profile.locked, before, "and the lock must not have moved")
end)

test("every feature verb refuses, and NONE of them reaches the write seam", function()
    -- Driven off NS.COMMANDS rather than a typed list of feature verbs, so the
    -- next verb added to the addon is covered here the day it lands. "Did it
    -- act" is measured at the addon's single write seam and at the one act that
    -- does not go through it, rather than by re-reading each verb's own state.
    -- red under: a per-verb guard that one verb was added without
    local live = {}
    for _, v in ipairs(LIVE) do live[v] = true end
    for _, entry in ipairs(T.NS.COMMANDS) do
        local verb = entry[1]
        if not live[verb] then
            local inst = disabled()
            local H = inst.NS.Settings.Helpers
            local writes, realSet = 0, H.SetAndRefresh
            local anchors, realAnchor = 0, H.ResetIconPosition
            H.SetAndRefresh = function(...) writes = writes + 1; return realSet(...) end
            H.ResetIconPosition = function(...) anchors = anchors + 1; return realAnchor(...) end
            local lines = say(inst, function() inst.NS:OnSlashCommand(verb) end)
            H.SetAndRefresh, H.ResetIconPosition = realSet, realAnchor
            assertEqual(#lines, 1, "`/kcd " .. verb .. "` must answer on exactly one line")
            assertTrue(lines[1]:find("/kcd enable", 1, true) ~= nil,
                "`/kcd " .. verb .. "` must name `/kcd enable`: " .. lines[1])
            assertEqual(writes, 0, "`/kcd " .. verb .. "` wrote while disabled")
            assertEqual(anchors, 0, "`/kcd " .. verb .. "` moved the grid while disabled")
        end
    end
end)

test("the live verbs still answer while disabled, and none of them refuses", function()
    -- The other half of the same rule, and the half that matters more: "refuse
    -- while disabled", read literally, takes the whole command surface down with
    -- it. A player must be able to read and repair settings, and reach the
    -- panel, while the addon is off — which is precisely when they need to.
    -- red under: gating by anything other than an explicit live set
    for _, verb in ipairs(LIVE) do
        local inst = disabled()
        local lines = say(inst, function() inst.NS:OnSlashCommand(verb) end)
        -- `help` is the one live verb that CARRIES the line, and carrying it is
        -- not refusing it: the index prints in full -- the player has to be able
        -- to SEE `enable` in the list -- with the line under the header as a
        -- statement about the rows below it, some of which are feature verbs that
        -- really are refused (LibKa0s-Slash-1.0 minor 12). So it is measured
        -- differently: the index must still be there.
        if verb == "help" then
            assertTrue(#lines > 5,
                "`/kcd help` must still print the whole index while disabled")
        else
            for _, line in ipairs(lines) do
                assertNil(line:find("is disabled", 1, true),
                    "`/kcd " .. verb .. "` must not refuse: " .. line)
            end
        end
    end
end)

test("`/kcd set` still writes while disabled — repair, not just read", function()
    -- The live set's whole reasoning. `set` is on it because a player whose
    -- settings are wrong turns the addon off first and fixes them second.
    -- red under: gating `set` as a feature verb because it changes something
    local inst = disabled()
    say(inst, function() inst.NS:OnSlashCommand("set locked true") end)
    assertEqual(inst.NS.Settings.Store.Get("locked"), true,
        "the write must have landed")
end)

test("`/kcd enable` above all — the switch is never one-way", function()
    -- red under: `enable` slipping off the live set
    local inst = disabled()
    say(inst, function() inst.NS:OnSlashCommand("enable") end)
    assertEqual(inst.NS.db.profile.enabled, true)
    -- and the feature verbs come straight back
    local before = inst.NS.db.profile.locked
    say(inst, function() inst.NS:OnSlashCommand("toggle") end)
    assertEqual(inst.NS.db.profile.locked, not before, "the lock moves again once enabled")
end)

test("nothing refuses while the addon is ENABLED", function()
    -- The gate reads the store at CALL time, so an addon that is on must behave
    -- exactly as it did before this landed.
    -- red under: a gate that latched at load, or read the wrong sense
    local inst = T.load(true, true)
    for _, entry in ipairs(T.NS.COMMANDS) do
        -- Re-armed before each verb, because `disable` is itself on the list and
        -- every verb after it would otherwise be measuring the disabled state.
        say(inst, function() inst.NS:OnSlashCommand("enable") end)
        local lines = say(inst, function() inst.NS:OnSlashCommand(entry[1]) end)
        for _, line in ipairs(lines) do
            assertNil(line:find("is disabled", 1, true),
                "`/kcd " .. entry[1] .. "` refused while enabled: " .. line)
        end
    end
end)

test("the refusal line is the LIBRARY's, and this addon does not re-spell it", function()
    -- THIS CASE REPLACES ITS OWN OPPOSITE, and the reversal is the point. It used
    -- to assert that the line came out of NS.L with a key defined in
    -- locales/enUS.lua. slash-commands-§7 settled it the other way: the wording is
    -- the COLLECTION's, one sentence, spelled once in
    -- LibKa0s-Slash-1.0's DISABLED_LINE_FORMAT, and it MUST NOT be re-spelled per
    -- addon -- a `L` override deliberately does not reach it. Eleven addons each
    -- wording it their own way is the drift the shared printer exists to end.
    -- red under: a host-side copy of the sentence, in a locale key or a literal
    assertNil(rawget(T.NS.L, "KickCD is disabled. %s turns it back on."),
        "the old host-side key must be GONE from locales/enUS.lua")

    -- And the line the addon actually emits is the one the library builds from
    -- that format, brand name and slash included -- not a lookalike.
    local inst = disabled()
    local Sl = inst.mocks.LibStub("LibKa0s-Slash-1.0", true)
    assertTrue(type(Sl.DISABLED_LINE_FORMAT) == "string",
        "the library owns the format string")
    local expected = Sl.DISABLED_LINE_FORMAT:format("Ka0s KickCD", "/kcd enable")
    local lines = say(inst, function() inst.NS:OnSlashCommand("toggle") end)
    assertEqual(lines[1], expected, "the refusal line must be the library's, byte for byte")
end)

test("`/kcd get` on a bool stored FALSE prints false, not the literal `nil`", function()
    -- THE PIN FOR settings/Slash.lua's HALF of the same fix. The host reader read
    -- `H and H.Get and H.Get(path) or nil`, whose trailing `or nil` folds a stored
    -- false to nil, and the library formats nil as the literal string "nil" — so
    -- every unticked bool in `/kcd get` and `/kcd list` reported a value the addon
    -- does not hold. The identical spelling lived in settings/OptionsSetup.lua,
    -- where it is invisible (a checkbox draws the same either way), which is why
    -- tests/test_options_panel.lua carries the other half of this pair: a fix in
    -- one file with a case in only one file is a fix half-guarded.
    -- red under: restoring `H and H.Get and H.Get(path) or nil` in Slash.lua
    local inst = T.load(true, true)
    inst.NS.Settings.Helpers.SetAndRefresh("locked", false)
    local lines = say(inst, function() inst.NS:OnSlashCommand("get locked") end)
    assertEqual(#lines, 1, "one line: " .. table.concat(lines, " / "))
    assertTrue(lines[1]:find("false", 1, true) ~= nil,
        "`/kcd get locked` must report false: " .. lines[1])
    assertNil(lines[1]:find("nil", 1, true),
        "and must never report the literal nil: " .. lines[1])
end)

-- ── `/kcd spells add` agrees with the Spells page (KICKCD-R-05, KICKCD-R-18) ──
--
-- core/SpellInput.lua is the one resolver both surfaces call. These pin the
-- three ways the command line used to disagree with the page: a multi-word name
-- split at its first space, the Cooldown Manager gate skipped, and an unchecked
-- CLASS / SPEC that lazily wrote an orphan list into SavedVariables.

local WIND_SHEAR, HEX = 57994, 51514
local KNOWN_SPELLS = { [WIND_SHEAR] = "Wind Shear", [HEX] = "Hex" }

--- An enabled Elemental Shaman whose spell DB knows exactly KNOWN_SPELLS, by id
--- and by name. `cmIds`, when given, is the set the Cooldown Manager tracks.
local function shaman(cmIds)
    return T.load(true, true, function(m)
        m.UnitClass = function() return "Shaman", "SHAMAN", 7 end
        m.__setPlayerSpec(7, 1)
        m.C_Spell.GetSpellInfo = function(q)
            for id, name in pairs(KNOWN_SPELLS) do
                if q == id or q == name then
                    return { name = name, iconID = 1, spellID = id }
                end
            end
            return nil
        end
        if cmIds then
            m.Enum = { CooldownViewerCategory = { ESSENTIAL = 1 } }
            m.C_CooldownViewer = {
                GetCooldownViewerCategorySet = function()
                    local out = {}
                    for i in ipairs(cmIds) do out[i] = i end
                    return out
                end,
                GetCooldownViewerCooldownInfo = function(cdID)
                    return { spellID = cmIds[cdID] }
                end,
            }
        end
    end)
end

local function hasSpell(inst, class, spec, id)
    for _, e in ipairs(inst.NS.Database:GetSpellList(class, spec) or {}) do
        if e.spellID == id then return true end
    end
    return false
end

test("`/kcd spells add Wind Shear` adds 57994 for a Shaman", function()
    -- red under: tokenizing on %S+ and resolving args[1] alone, which answers
    -- "Unknown spell: Wind" and reads "Shear" as a CLASS.
    local inst = shaman()
    inst.NS.db.profile.spells.SHAMAN[262] = {}
    local lines = say(inst, function() inst.NS:OnSlashCommand("spells add Wind Shear") end)
    assertTrue(hasSpell(inst, "SHAMAN", 262, WIND_SHEAR),
        "Wind Shear must land on SHAMAN/ELEMENTAL: " .. joined(lines))
    assertTrue(joined(lines):find("added Wind Shear (#57994) to SHAMAN/ELEMENTAL", 1, true) ~= nil,
        "got: " .. joined(lines))
end)

test("`/kcd spells add Wind Shear SHAMAN ENHANCEMENT` takes the trailing pair", function()
    local inst = shaman()
    inst.NS.db.profile.spells.SHAMAN[263] = {}
    say(inst, function() inst.NS:OnSlashCommand("spells add Wind Shear SHAMAN ENHANCEMENT") end)
    assertTrue(hasSpell(inst, "SHAMAN", 263, WIND_SHEAR), "the explicit pair is the target")
end)

test("the CLI refuses a spell the Cooldown Manager does not track for the live spec", function()
    -- red under: spellsAdd skipping the gate the page's add box applies.
    local inst = shaman({ WIND_SHEAR })
    inst.NS.db.profile.spells.SHAMAN[262] = {}
    local lines = say(inst, function() inst.NS:OnSlashCommand("spells add 51514") end)
    assertTrue(not hasSpell(inst, "SHAMAN", 262, HEX), "a spell the CM lacks must not be written")
    assertTrue(joined(lines):find("is not tracked by the Blizzard Cooldown Manager", 1, true) ~= nil,
        "the refusal must say why: " .. joined(lines))
    -- The gate admits what the Cooldown Manager does track.
    say(inst, function() inst.NS:OnSlashCommand("spells add Wind Shear") end)
    assertTrue(hasSpell(inst, "SHAMAN", 262, WIND_SHEAR), "a tracked spell is admitted")
end)

test("the CLI gate is dropped for a pair other than the player's live one, as on the page", function()
    -- C_CooldownViewer answers only for the logged-in spec, so another spec's
    -- list gets no opinion from it.
    local inst = shaman({ WIND_SHEAR })
    inst.NS.db.profile.spells.SHAMAN[263] = {}
    say(inst, function() inst.NS:OnSlashCommand("spells add 51514 SHAMAN ENHANCEMENT") end)
    assertTrue(hasSpell(inst, "SHAMAN", 263, HEX), "another spec's list is not CM-gated")
end)

test("`spells add <id> WARLORD 99999` writes nothing", function()
    -- red under: an unchecked class token reaching Database:AddSpell, whose
    -- EnsureSpellList creates profile.spells.WARLORD[99999].
    local inst = shaman()
    local lines = say(inst, function() inst.NS:OnSlashCommand("spells add 57994 WARLORD 99999") end)
    assertNil(inst.NS.db.profile.spells.WARLORD, "no orphan class list")
    assertTrue(joined(lines):find("Unknown class WARLORD", 1, true) ~= nil, "got: " .. joined(lines))
end)

test("`spells add <id> SHAMAN 99999` names the spec it could not resolve", function()
    local inst = shaman()
    local lines = say(inst, function() inst.NS:OnSlashCommand("spells add 57994 SHAMAN 99999") end)
    assertNil(inst.NS.db.profile.spells.SHAMAN[99999], "no orphan spec list")
    assertTrue(joined(lines):find("Unknown spec 99999 for SHAMAN", 1, true) ~= nil, "got: " .. joined(lines))
    -- A real spec of ANOTHER class is not a spec of this one.
    say(inst, function() inst.NS:OnSlashCommand("spells add 57994 SHAMAN 253") end)
    assertNil(inst.NS.db.profile.spells.SHAMAN[253], "a Hunter spec is not a Shaman spec")
end)

test("bare `/kcd spells` names the default spec by SpecDisplay", function()
    -- red under: formatting the raw spec ID, which printed SHAMAN/262.
    local inst = shaman()
    local lines = say(inst, function() inst.NS:OnSlashCommand("spells") end)
    assertTrue(joined(lines):find("SHAMAN/ELEMENTAL", 1, true) ~= nil, "got: " .. joined(lines))
    assertNil(joined(lines):find("SHAMAN/262", 1, true), "never the raw ID")
end)
