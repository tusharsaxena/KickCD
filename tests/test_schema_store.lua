-- tests/test_schema_store.lua — the settings seam is a LibKa0s-Schema-1.0 instance
--
-- settings/SchemaSetup.lua builds NS.Settings.Store from the library (or, with the library
-- absent, from its own degradation stub), and every settings write in the addon lands on it:
-- the panel's widgets, `/kcd set`, both resets, Copy styling and the host verbs. These cases pin
-- what the seam does for THIS addon -- the section it announces, the master switch in the same
-- turn, the batch -- and the behavior the library's adoption notes say a host crossing them must
-- pin in its own suite: an unknown path is refused, a table value is copied in, a raising
-- onChange propagates, and `group` is required (tests/test_schema.lua's Validate case).
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertNil, T.assertFalse

--- Every CONFIG_CHANGED section `fn` sends, in order ("<nil>" for a nil section).
local function sections(NS, fn)
    local sent = {}
    local realSend = NS.SendMessage
    NS.SendMessage = function(self, msg, payload)
        if msg == T.NS.MSG.CONFIG_CHANGED then
            local s = payload and payload.section
            sent[#sent + 1] = s == nil and "<nil>" or s
        end
        return realSend(self, msg, payload)
    end
    local ok, err = pcall(fn)
    NS.SendMessage = realSend
    if not ok then error(err, 0) end
    return sent
end

--- Every [Set]-tagged console line, read after the debounce has fired.
local function setLines(inst)
    inst.mocks.__flushTimers()
    local out = {}
    for line in (inst.NS.DebugLog:CopyText() .. "\n"):gmatch("([^\n]*)\n") do
        if line:find("[Set]", 1, true) then out[#out + 1] = line end
    end
    return out
end

-- ── the instance ────────────────────────────────────────────────────────────

test("the settings seam is a LibKa0s-Schema-1.0 instance", function()
    -- red under: the host's own Helpers.Get / Helpers.Set seam in settings/Panel.lua
    local NS = T.NS
    local Store = NS.Settings.Store
    assertTrue(type(Store) == "table", "NS.Settings.Store must exist")
    for _, m in ipairs({ "Get", "Set", "SetMany", "FindRow", "AddRows", "ApplyDefault",
                         "BulkBegin", "BulkEnd", "ResetCounted", "ConsumeResetCount", "Validate" }) do
        assertEqual(type(Store[m]), "function", "Store." .. m .. " must be a function")
    end
    assertTrue(NS.Settings.SchemaLib == T.mocks.LibStub("LibKa0s-Schema-1.0", true),
        "the live load builds the seam from the library, not from the host's stub")
    assertTrue(Store.AllRows() == NS.Settings.Schema, "the instance holds the schema array itself")
    local H = NS.Settings.Helpers
    assertNil(H.Set, "the host's own write seam is gone")
    assertNil(H.Get, "and its reader with it")
end)

test("a write announces CONFIG_CHANGED once with the row's section", function()
    -- red under: an announce that ignores `row.section`, or one that also fires
    -- for the write's own onChange.
    local NS = T.load(true).NS
    local S = NS.Settings.Store
    local path = "units.target.icons.primarySize"
    local sent = sections(NS, function() assertTrue(S.Set(path, 50), "the write lands") end)
    assertEqual(#sent, 1, "one announcement: " .. table.concat(sent, ", "))
    assertEqual(sent[1], S.FindRow(path).section, "with the row's own section")
    assertEqual(S.Get(path), 50)

    -- A row stored somewhere else announces nothing: nothing on the bus renders
    -- the console window or the minimap button.
    sent = sections(NS, function() S.Set("global.minimap.shown", false) end)
    assertEqual(#sent, 0, "a row with its own storage is silent: " .. table.concat(sent, ", "))
end)

test("`/kcd set enabled false` stands the addon down in the same turn", function()
    -- The `enabled` row's onChange takes the hold, and the seam runs it BEFORE
    -- it announces: a module that re-rendered first and stood down second would
    -- draw one frame of an addon that is already off. red under: an `enabled`
    -- row with no onChange, or a hold taken after the announcement.
    local inst = T.load(true, true)
    local NS = inst.NS
    inst.mocks.__fireEvent("PLAYER_LOGIN")
    inst.mocks.__flushTimers()
    assertFalse(NS.IsDown(), "sanity: the addon starts up")
    local downWhenAnnounced
    local bus = NS.NewBusTarget()
    bus:RegisterMessage(T.NS.MSG.CONFIG_CHANGED, function() downWhenAnnounced = NS.IsDown() end)
    NS:OnSlashCommand("set enabled false")
    bus:UnregisterMessage(T.NS.MSG.CONFIG_CHANGED)
    assertTrue(NS.IsDown(), "stood down with no timer flushed")
    assertEqual(downWhenAnnounced, true, "and already down when CONFIG_CHANGED went out")
    NS:OnSlashCommand("set enabled true")
    assertFalse(NS.IsDown(), "and back up the same way")
end)

-- ── the batch ───────────────────────────────────────────────────────────────

test("Copy styling is one SetMany: one [Set] copy target→focus: N rows line, each section announced once",
function()
    -- red under: a copy written row by row, which logs a line and announces a
    -- section per row.
    local inst = T.load(true, true)
    local NS = inst.NS
    NS.db.profile.units.target.icons.primarySize = 55
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    local sent = sections(NS, function() assertTrue(NS.Units.CopyStyling("target", "focus")) end)
    local lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 1, "one line for the copy: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] copy target\226\134\146focus: ", 1, true) ~= nil
        and lines[1]:find(" rows", 1, true) ~= nil, "the act's one line: " .. lines[1])
    local count = {}
    for _, s in ipairs(sent) do count[s] = (count[s] or 0) + 1 end
    for _, s in ipairs({ "icons", "castbar", "label", "units" }) do
        assertEqual(count[s], 1, s .. " announced once: " .. table.concat(sent, ", "))
    end
end)

test("a bad value in a batch writes nothing", function()
    -- All or nothing: every entry is checked before any is stored. red under: a
    -- batch that stores as it goes, leaving the entries ahead of the refusal.
    local NS = T.load(true).NS
    local S = NS.Settings.Store
    local sizePath, scalePath = "units.target.icons.primarySize", "scale"
    local sizeBefore, scaleBefore = S.Get(sizePath), S.Get(scalePath)
    local row = S.FindRow(scalePath)
    row.validate = function(v) return type(v) == "number" and v > 0, "must be positive" end
    local called = false
    local realChange = S.FindRow(sizePath).onChange
    S.FindRow(sizePath).onChange = function() called = true end
    local ok, err, why, at
    local sent = sections(NS, function()
        ok, err, why, at = S.SetMany({
            { path = sizePath,  value = sizeBefore + 1 },
            { path = scalePath, value = -1 },
        })
    end)
    row.validate = nil
    S.FindRow(sizePath).onChange = realChange
    assertEqual(ok, false, "the batch is refused")
    assertTrue(type(err) == "string" and err:find(scalePath, 1, true) ~= nil, "naming the path: " .. tostring(err))
    assertEqual(why, "must be positive", "with the row's own reason")
    assertEqual(at, 2, "and the entry that refused")
    assertEqual(S.Get(sizePath), sizeBefore, "the entry ahead of the refusal was not stored")
    assertEqual(S.Get(scalePath), scaleBefore, "nor the refused one")
    assertFalse(called, "no onChange ran")
    assertEqual(#sent, 0, "and nothing was announced")
end)

-- ── the behavior the adoption notes pin ─────────────────────────────────────

test("an unknown path is refused, never stored", function()
    -- architecture-§5 scopes the seam to schema-row paths. red under: a seam that
    -- resolves any dotted path and stores into it, which is how a typo becomes a
    -- setting nothing reads and nothing resets.
    local NS = T.load(true).NS
    local S = NS.Settings.Store
    local ok, err = S.Set("icons.nope", 1)
    assertEqual(ok, false)
    assertEqual(err, "Setting not found: icons.nope")
    assertNil(NS.db.profile.icons, "nothing was created in the profile")

    local lines = {}
    local realPrint = NS.Util.print
    NS.Util.print = function(line) lines[#lines + 1] = tostring(line) end
    NS:OnSlashCommand("set icons.nope 1")
    NS.Util.print = realPrint
    local text = table.concat(lines, "\n")
    assertTrue(text:find("Setting not found", 1, true) ~= nil, "the CLI says so: " .. text)
end)

test("a stored table is a copy", function()
    -- red under: storing the caller's table itself, so a later edit of the
    -- argument reaches into the profile, and two profiles can share one table.
    local NS = T.load(true).NS
    local S = NS.Settings.Store
    local path = "units.target.icons.borderColor"
    local given = { r = 0.1, g = 0.2, b = 0.3, a = 1 }
    assertTrue(S.Set(path, given))
    local stored = S.Get(path)
    assertTrue(stored ~= given, "the store holds its own table")
    given.r = 0.9
    assertEqual(S.Get(path).r, 0.1, "editing the argument afterwards does not reach the profile")
end)

test("a raising onChange propagates after the store", function()
    -- It used to be pcall'd and printed. red under: a seam that swallows the
    -- reaction's error, or one that raises before the value is stored.
    local NS = T.load(true).NS
    local S = NS.Settings.Store
    local row = S.FindRow("scale")
    local real = row.onChange
    row.onChange = function() error("reaction failed", 0) end
    local ok, err
    local sent = sections(NS, function() ok, err = pcall(S.Set, "scale", 1.25) end)
    row.onChange = real
    assertEqual(ok, false, "the error reaches the caller")
    assertEqual(err, "reaction failed", "unchanged")
    assertEqual(S.Get("scale"), 1.25, "the value was stored before the reaction ran")
    assertEqual(#sent, 0, "and a failed reaction announces nothing")
end)

-- ── the degraded load ───────────────────────────────────────────────────────

test("degraded: Store.Set(\"enabled\", false) writes through and takes the disabled hold, with no Lua error",
function()
    -- With LibKa0s absent the composer that declares `enabled` is hollow, so
    -- there is no row. The host's stub takes the same writeThrough list the live
    -- instance takes, stores the value raw and announces it, and the announce
    -- dispatches the master switch itself. red under: an empty writeThrough list
    -- (the seam refuses), or an announce that does not take the hold.
    local inst = T.load(true, true, nil, { libFiles = {} })
    local NS = inst.NS
    local S = NS.Settings.Store
    assertTrue(NS.Settings.SchemaLib == NS.Settings.HostSchemaStub, "sanity: the stub is the seam")
    assertNil(S.FindRow("enabled"), "sanity: no composed row on this load")
    assertFalse(NS.IsDown(), "sanity: the addon starts up")
    local ok, err = pcall(S.Set, "enabled", false)
    assertTrue(ok, "no Lua error: " .. tostring(err))
    assertEqual(err, true, "the write is accepted")
    assertEqual(NS.db.profile.enabled, false, "and stored")
    assertTrue(NS.IsDown(), "and the disabled hold is taken")
    assertTrue(S.Set("locked", true), "the other listed path writes through too")
    assertEqual(NS.db.profile.locked, true)
end)

test("degraded: Store.Set on any other composed path is refused", function()
    -- red under: a stub that stores every row-less path, which is the unknown-path
    -- store the seam exists to refuse.
    local inst = T.load(true, false, nil, { libFiles = {} })
    local NS = inst.NS
    local S = NS.Settings.Store
    local before = NS.db.profile.visibility
    local ok, err = S.Set("visibility", "always")
    assertEqual(ok, false)
    assertEqual(err, "Setting not found: visibility", "in the host's own words")
    assertEqual(NS.db.profile.visibility, before, "and nothing was stored")
    assertEqual(S.Set("scale", 1.5), false, "the same for every composed row")
end)
