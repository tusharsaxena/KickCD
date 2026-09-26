-- tests/test_diagnostics.lua — the diagnostics report's KickCD half (debug-logging-§14, DX-KC).
--
-- The dispatcher contract -- both forms, while disabled, append, ungated, the markers, and `diag`
-- not running the report -- is the kit's shared case, tests/_kit/test_diagnostics_contract.lua,
-- wired in tests/run.lua through Kit.diagnostics. What the library writes around the sections
-- (the markers, the identity header, the per-section pcall, the cap) is the library's own suite.
-- What is pinned HERE is what only this addon knows: which sections it hands the library, in
-- which order, what each says, and that none of them stands anything up or forces anything the
-- player did not ask for.
--
-- Every case reads the report as DATA, through BuildDiagnostics, unless it is about what the
-- report writes into the console or chat.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertNil, T.assertFalse

-- Sentinel a fake client hands back as a secret value: tostring on it raises, so any report line
-- that reaches it through tostring fails the section, and the section-failed line shows it.
local SECRET = setmetatable({}, { __tostring = function() error("tostring on a secret") end })

--- A fresh, enabled instance with chat captured rather than printed.
local function fresh()
    local inst = T.load(true, true)
    inst.chat = {}
    inst.NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        inst.chat[#inst.chat + 1] = table.concat(parts, " ")
    end
    return inst
end

--- The report's lines as `[Tag] msg` strings, built and never written.
local function report(inst, spec)
    local built = inst.NS.DebugLog:BuildDiagnostics(spec)
    local lines = {}
    for i, l in ipairs(built.lines) do lines[i] = "[" .. tostring(l[1]) .. "] " .. tostring(l[2]) end
    return lines, built
end

local function joined(lines) return table.concat(lines, "\n") end

--- Structural equality over plain data (the profile tree).
local function same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

--- Index of the first line containing `needle` (plain), or nil.
local function find(lines, needle)
    for i, line in ipairs(lines) do
        if line:find(needle, 1, true) then return i end
    end
    return nil
end

--- Every line containing `needle` (plain).
local function all(lines, needle)
    local hits = {}
    for _, line in ipairs(lines) do
        if line:find(needle, 1, true) then hits[#hits + 1] = line end
    end
    return hits
end

-- ── the two forms are registered ────────────────────────────────────────────

test("`diagnostics` is a COMMANDS row and a `debug` word, and nothing else runs it", function()
    local verbs = {}
    for _, e in ipairs(T.NS.COMMANDS) do verbs[e[1]] = true end
    assertTrue(verbs.diagnostics, "NS.COMMANDS must carry the `diagnostics` row")
    -- red under: an alias row, which debug-logging-§14 forbids
    for _, word in ipairs({ "diag", "dump", "dx" }) do
        assertNil(verbs[word], "no `" .. word .. "` row may run the report")
    end
    -- The bare `/kcd debug` list is the discoverable form of the second spelling.
    local inst = fresh()
    inst.NS:OnSlashCommand("debug")
    assertTrue(find(inst.chat, "/kcd debug diagnostics") ~= nil,
        "the `debug` word list names diagnostics: " .. joined(inst.chat))
end)

test("no source file under core, modules or settings spells a report alias", function()
    -- The plan's grep (03_EXECUTION_PLAN.md section 4) as a case, so it stays true after this item.
    -- red under: a `{"diag", ...}` row, a `diag = "diagnostics"` alias, or a `dump` debug word
    local files = {}
    for _, rel in ipairs(T.tocFiles) do
        if rel:match("^core/") or rel:match("^modules/") or rel:match("^settings/") then
            files[#files + 1] = rel
        end
    end
    assertTrue(#files > 20, "sanity: the TOC lists the addon's own files")
    for _, rel in ipairs(files) do
        local fh = assert(io.open(T.root .. "/" .. rel, "r"))
        local src = fh:read("*a"):lower()
        fh:close()
        for _, word in ipairs({ '"diag"', '"dump"', '"dx"' }) do
            assertNil(src:find(word, 1, true), rel .. " spells " .. word)
        end
    end
end)

-- ── the sections, in order ──────────────────────────────────────────────────

test("the addon hands the library its sections with the lifecycle first", function()
    -- DX-KC: lifecycle FIRST, so a reader knows whether the runtime sections below it are live
    -- before reading them.
    -- red under: the state section moved below a runtime section, or dropped
    local names = {}
    for i, s in ipairs(T.NS.Diagnostics.Sections()) do
        assertEqual(type(s[2]), "function", "section " .. tostring(s[1]) .. " has a body")
        names[i] = s[1]
    end
    assertEqual(table.concat(names, ","),
        "state,settings,units,spells,cooldowns,cmcache,icongrid,castbar,interrupt,unitlabel,events,perf")
end)

test("the report runs every section and none of them fails on a live load", function()
    local lines, built = report(fresh())
    assertFalse(built.capped, "a default report fits the cap: " .. #lines .. " lines")
    assertNil(find(lines, "failed:"), "no section may fail:\n" .. joined(lines))
    -- Budget from 02_SPEC.md (DX-KC): 100 to 200 lines. Well under the cap either way, but a report
    -- that grew past it has started dumping something it should summarize.
    assertTrue(#lines <= 200, "the report stays inside its budget: " .. #lines .. " lines")
    local state = find(lines, "[State] ")
    local runtime = find(lines, "[Cooldowns] ")
    assertTrue(state ~= nil and runtime ~= nil and state < runtime,
        "the state lines come before the runtime sections")
end)

test("the state section says stored enabled, stood down, holds and both schema versions", function()
    local inst = fresh()
    local lines = report(inst)
    assertTrue(find(lines, "[State] enabled stored=true, stood down=false, holds=-") ~= nil,
        joined(lines))
    local want = ("[State] schema stored=%s code=%s"):format(
        tostring(inst.NS.db.global.schemaVersion), tostring(inst.NS.Database.CURRENT_DB_VERSION))
    assertTrue(find(lines, want) ~= nil, "want `" .. want .. "`:\n" .. joined(lines))
    assertEqual(type(inst.NS.Database.CURRENT_DB_VERSION), "number",
        "the code's schema version is published for the report")
end)

-- ── while disabled ──────────────────────────────────────────────────────────

test("while disabled every section still runs and the runtime ones say they are stood down", function()
    -- STD-05: the report runs every section while stood down; a section whose runtime state is
    -- released says so rather than printing an empty list that reads like a bug.
    -- red under: a runtime section that reads its released tables and prints nothing, or a report
    -- that skips sections while disabled
    local inst = fresh()
    inst.NS:OnSlashCommand("disable")
    assertEqual(inst.NS.db.profile.enabled, false, "sanity: disabled")
    local lines = report(inst)
    assertNil(find(lines, "failed:"), joined(lines))
    assertTrue(find(lines, "[State] enabled stored=false, stood down=true, holds=disabled") ~= nil,
        joined(lines))
    for _, tag in ipairs({ "Cooldowns", "IconGrid", "Castbar", "UnitLabel" }) do
        assertTrue(find(lines, "[" .. tag .. "] stood down") ~= nil,
            tag .. " says it is stood down:\n" .. joined(lines))
    end
    -- The configuration sections are not runtime state and still print in full.
    assertTrue(find(lines, "[Set] enabled = false (true)") ~= nil, joined(lines))
    assertTrue(find(lines, "[Spells] class=") ~= nil, joined(lines))
end)

test("the report stands nothing up: no hold, no registration, no stored write", function()
    -- STD-05: read-only. It must not take or release a Lifecycle hold, register an event or write
    -- a setting, disabled or not.
    -- red under: a section that calls Resume/EnableUnit/Rebuild, or reads through EnsureSpellList
    for _, off in ipairs({ false, true }) do
        local inst = fresh()
        if off then inst.NS:OnSlashCommand("disable") end
        local holds = table.concat(inst.NS.Lifecycle:Holds(), ",")
        local regs = #inst.mocks.__registrationSet()
        local before = inst.mocks.__deepcopy(inst.NS.db.profile)
        inst.NS:OnSlashCommand("diagnostics")
        assertEqual(table.concat(inst.NS.Lifecycle:Holds(), ","), holds, "the holds did not move")
        assertEqual(#inst.mocks.__registrationSet(), regs, "nothing registered or unregistered")
        assertTrue(same(inst.NS.db.profile, before), "the profile was not written")
    end
end)

-- ── settings ────────────────────────────────────────────────────────────────

test("the settings section prints the always rows and only the rows that differ", function()
    local inst = fresh()
    inst.NS.Settings.Store.Set("scale", 1.5)
    local lines = report(inst)
    -- Always rows print at their defaults.
    for _, want in ipairs({
        "[Set] enabled = true (true)",
        "[Set] locked = ",
        "[Set] visibility = ",
        "[Set] units.target.enabled = true (true)",
        "[Set] units.focus.link = true (true)",
        "[Set] units.focus.castbar.enabled = ",
        "[Set] units.target.icons.primaryGlowTrigger = ",
        "[Set] units.target.castbar.orientation = ",
        "[Set] units.target.castbar.anchorMode = ",
    }) do
        assertTrue(find(lines, want) ~= nil, "want `" .. want .. "`:\n" .. joined(lines))
    end
    -- The changed row, with its default.
    assertTrue(find(lines, "[Set] scale = 1.5 (") ~= nil, joined(lines))
    -- An unchanged row that is not on the always list stays out.
    assertNil(find(lines, "[Set] units.target.icons.gap = "), joined(lines))
end)

-- ── spells ──────────────────────────────────────────────────────────────────

test("the spells section lists the live class and spec with unlearned and disabled flags", function()
    local inst = fresh()
    local NS = inst.NS
    local class, spec = "HUNTER", NS.Util.PlayerSpecID()
    local list = NS.Database:GetSpellList(class, spec)
    assertTrue(list and #list >= 2, "sanity: the mock's Hunter spec has a seeded list")
    local unlearned, off = list[1].spellID, list[2].spellID
    list[2].enabled = false
    local realAvail = NS.Compat.IsSpellAvailable
    NS.Compat.IsSpellAvailable = function(id) return id ~= unlearned end
    local lines = report(inst)
    NS.Compat.IsSpellAvailable = realAvail
    local head = lines[find(lines, "[Spells] class=") or 0] or ""
    assertTrue(head:find("class=HUNTER", 1, true) ~= nil, head)
    assertTrue(head:find("(" .. tostring(spec) .. ")", 1, true) ~= nil, head)
    local body = joined(all(lines, "[Spells] "))
    assertTrue(body:find(tostring(unlearned) .. " [^,]*unlearned") ~= nil,
        "the unlearned spell is flagged:\n" .. body)
    assertTrue(body:find(tostring(off) .. " [^,]*off") ~= nil,
        "the disabled row is flagged:\n" .. body)
end)

test("the spells section counts the lists that differ from their defaults", function()
    local inst = fresh()
    local lines = report(inst)
    assertTrue(find(lines, "0 customized") ~= nil, "a fresh profile has none:\n" .. joined(lines))
    local list = inst.NS.Database:GetSpellList("HUNTER", inst.NS.Util.PlayerSpecID())
    list[1].enabled = false
    lines = report(inst)
    assertTrue(find(lines, "1 customized") ~= nil, "one edited list counts:\n" .. joined(lines))
end)

-- ── the Cooldown Manager cache: read, never walked ──────────────────────────

test("the CM cache line reads the memo and never forces the walk", function()
    -- DX-KC's Never column: forcing the CM recompute. The report says whether the set is built,
    -- and a report run before the Spells editor ever asked must leave it unbuilt.
    -- red under: a section that calls SpellInput.CooldownManagerSet()
    local inst = fresh()
    local walks = 0
    inst.mocks.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function() walks = walks + 1; return {} end,
        GetCooldownViewerCooldownInfo = function() return nil end,
    }
    local lines = report(inst)
    assertEqual(walks, 0, "the report walked C_CooldownViewer")
    assertTrue(find(lines, "[CMCache] cooldown manager cache: unbuilt") ~= nil, joined(lines))
    assertEqual(inst.NS.SpellInput.CooldownManagerCacheState(), "unbuilt", "and left it unbuilt")
end)

test("the CM cache accessor names the three states without walking", function()
    local inst = fresh()
    local SI = inst.NS.SpellInput
    assertEqual(SI.CooldownManagerCacheState(), "unbuilt")
    inst.mocks.C_CooldownViewer = nil
    SI.CooldownManagerSet()
    assertEqual(SI.CooldownManagerCacheState(), "empty")
    SI.StandUp()
    inst.mocks.Enum = inst.mocks.Enum or {}
    inst.mocks.Enum.CooldownViewerCategory = { Essential = 0 }
    inst.mocks.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function() return { 1, 2 } end,
        GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end,
    }
    SI.CooldownManagerSet()
    local state, n = SI.CooldownManagerCacheState()
    assertEqual(state, "built")
    assertEqual(n, 2)
end)

-- ── units, events, perf ─────────────────────────────────────────────────────

test("the units section reports each unit's enabled and link state", function()
    local lines = report(fresh())
    assertTrue(find(lines, "[Units] target: enabled=true linked=false") ~= nil, joined(lines))
    assertTrue(find(lines, "[Units] focus: enabled=true linked=true") ~= nil, joined(lines))
end)

test("the events section names every event this client refused", function()
    local inst = fresh()
    inst.NS.State.rejectedEvents = { "NOT_A_REAL_EVENT", "ANOTHER_ONE" }
    local lines = report(inst)
    assertTrue(find(lines, "[Events] rejected events: NOT_A_REAL_EVENT, ANOTHER_ONE") ~= nil,
        joined(lines))
    inst.NS.State.rejectedEvents = {}
    lines = report(inst)
    assertTrue(find(lines, "[Events] rejected events: -") ~= nil, joined(lines))
end)

-- ── the runtime sections route the existing dumps ───────────────────────────

test("the runtime sections carry the three chat dumps, and chat receives none of them", function()
    -- DR-KC-02 gave the dumps an emit sink so the report could take their lines. A section that
    -- called them without one would print them to chat as well.
    local inst = fresh()
    inst.NS:OnSlashCommand("diagnostics")
    for _, line in ipairs(inst.chat) do
        assertNil(line:find("Cooldowns: class=", 1, true), "the spells dump went to chat")
        assertNil(line:find("castbar state (", 1, true), "the castbar dump went to chat")
    end
    local lines = report(inst)
    assertTrue(find(lines, "[Cooldowns] Cooldowns: class=HUNTER") ~= nil, joined(lines))
    assertTrue(find(lines, "[Castbar] castbar state (target)") ~= nil, joined(lines))
    assertTrue(find(lines, "[Castbar] castbar state (focus)") ~= nil, joined(lines))
    assertTrue(#all(lines, "[Interrupt] ") >= 2, "the interrupt dump runs for both units")
end)

test("the IconGrid and Castbar sections give saved and live anchors per unit", function()
    local lines = report(fresh())
    assertTrue(find(lines, "[IconGrid] target: enabled=true") ~= nil, joined(lines))
    assertTrue(find(lines, "[IconGrid] target: anchor saved=CENTER CENTER 0 120 live=") ~= nil,
        joined(lines))
    assertTrue(find(lines, "[Castbar] target: anchor mode=") ~= nil, joined(lines))
end)

-- ── STD-19's failure cases ──────────────────────────────────────────────────

test("a raising section costs exactly one line and the next section still runs", function()
    -- red under: the sections run outside the library's per-section pcall
    local inst = fresh()
    local cd = inst.NS:GetModule("Cooldowns")
    cd.DebugDump = function() error("boom") end
    local lines = report(inst)
    local failed = all(lines, "failed:")
    assertEqual(#failed, 1, joined(failed))
    assertTrue(failed[1]:find("section cooldowns failed:", 1, true) ~= nil, failed[1])
    assertTrue(find(lines, "[CMCache] ") ~= nil, "the section after it ran")
end)

test("an over-cap report ends in the truncated line and then the end marker", function()
    local lines = report(fresh(), { maxLines = 20 })
    assertEqual(#lines, 20)
    assertTrue(lines[19]:find("truncated: ", 1, true) ~= nil, lines[19])
    assertTrue(lines[20]:find("Ka0s KickCD diagnostics end: 20 line(s)", 1, true) ~= nil, lines[20])
end)

test("secret values in the cast record and the charges do not raise", function()
    -- Midnight 12.x: the cast record's name, texture, spellID and notInterruptible, and a charged
    -- spell's charges, may all be secret. The report prints types and the sentinel, never values.
    -- red under: a section that tostring()s a cast record field or a charges count
    local inst = fresh()
    inst.mocks.issecretvalue = function(v) return v == SECRET end
    inst.mocks.UnitExists = function() return true end
    local cb = inst.NS:GetModule("Castbar"):GetInstance("target")
    cb.current = { isChannel = false, notInterruptible = SECRET, texture = SECRET,
                   spellID = SECRET, name = SECRET }
    local cd = inst.NS:GetModule("Cooldowns")
    for _, s in pairs(cd.watched or {}) do s.charges = SECRET end
    local lines = report(inst)
    assertNil(find(lines, "failed:"), joined(lines))
    assertTrue(find(lines, "[Castbar]   current.notInterruptible: type=table, isSecret=true") ~= nil,
        joined(lines))
end)

-- ── the chat line and the library-absent load ───────────────────────────────

test("`/kcd diagnostics` writes one chat line naming the count and Copy", function()
    local inst = fresh()
    inst.NS:OnSlashCommand("diagnostics")
    assertEqual(#inst.chat, 1, joined(inst.chat))
    local n = tonumber(inst.chat[1]:match("console: (%d+) lines"))
    assertTrue(n ~= nil and n > 20, inst.chat[1])
    assertTrue(inst.chat[1]:find("Copy", 1, true) ~= nil, inst.chat[1])
end)

test("with LibKa0s absent both forms print the library-absent line and raise nothing", function()
    -- STD-14. Enabled and disabled: the degraded dispatcher's gate refuses only FEATURE_VERBS.
    for _, off in ipairs({ false, true }) do
        local inst = T.load(true, true, nil, { libFiles = {} })
        local lines = {}
        inst.NS.Util.print = function(line) lines[#lines + 1] = tostring(line) end
        if off then inst.NS:OnSlashCommand("disable") end
        for _, form in ipairs({ "diagnostics", "debug diagnostics" }) do
            lines = {}
            local ok, err = pcall(inst.NS.OnSlashCommand, inst.NS, form)
            assertTrue(ok, tostring(err))
            assertEqual(joined(lines),
                "/kcd diagnostics is unavailable: the LibKa0s library did not load.",
                "/kcd " .. form .. (off and " (disabled)" or ""))
        end
    end
end)
