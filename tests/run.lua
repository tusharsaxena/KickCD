-- tests/run.lua
-- Headless test runner + micro-framework (§14A.1).
--
--   lua tests/run.lua            -- from the repo root; exits non-zero on any failure
--
-- Loads every addon source once in TOC order under the WoW mock, builds the
-- DB, then dofiles each test_*.lua suite. Suites pull the shared framework
-- and namespace off the single global table _G.KICKCD_TEST.

-- Resolve the repo root from this script's path so it runs from anywhere.
local root = (arg and arg[0] and arg[0]:match("^(.*)/tests/run%.lua$")) or "."
package.path = root .. "/tests/?.lua;" .. package.path

local mockmod = dofile(root .. "/tests/wow_mock.lua")
local loader  = dofile(root .. "/tests/loader.lua")

-- ---------------------------------------------------------------------------
-- Micro-framework
-- ---------------------------------------------------------------------------
local passed, failed = 0, 0
local failures = {}

-- --list mode (§5): enumerate every registered case grouped by suite without
-- running it. Set once from argv; `currentSuite` is stamped around each dofile
-- below so test() can attribute each case to its originating file.
local listMode = false
if arg then
    for _, a in ipairs(arg) do
        if a == "--list" then listMode = true end
    end
end
local registry = {}       -- ordered { name = ..., suite = ... } records
local currentSuite = nil  -- base filename (no .lua) of the suite being loaded

local function fmt(v)
    if type(v) == "table" then return "<table>" end
    return tostring(v)
end

local function test(name, fn)
    if listMode then
        -- List mode: record attribution only, never execute the body.
        registry[#registry + 1] = { name = name, suite = currentSuite }
        return
    end
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write("  \27[32mPASS\27[0m  " .. name .. "\n")
    else
        failed = failed + 1
        failures[#failures + 1] = name .. " -> " .. tostring(err)
        io.write("  \27[31mFAIL\27[0m  " .. name .. "\n         " .. tostring(err) .. "\n")
    end
end

local function assertTrue(cond, msg)
    if not cond then error(msg or "expected truthy, got " .. fmt(cond), 2) end
end
local function assertFalse(cond, msg)
    if cond then error(msg or "expected falsy, got " .. fmt(cond), 2) end
end
local function assertNil(v, msg)
    if v ~= nil then error(msg or "expected nil, got " .. fmt(v), 2) end
end
local function assertEqual(a, b, msg)
    if a ~= b then error((msg or "not equal") .. ": expected " .. fmt(b) .. ", got " .. fmt(a), 2) end
end
local function assertError(fn, msg)
    local ok = pcall(fn)
    if ok then error(msg or "expected function to error, but it returned", 2) end
end
--- Float comparison with an explicit tolerance — never compare computed
--- geometry or a rescaled color channel with `==`. Same name, signature and
--- semantics as tests/_kit/framework.lua's, so adopting the kit replaces this
--- with an identical function rather than changing any call site.
local function assertNear(got, want, tolerance, msg)
    tolerance = tolerance or 1e-6
    if type(got) ~= "number" or math.abs(got - want) > tolerance then
        error((msg or "assertNear") ..
            (" (expected %s +/- %s, got %s)"):format(fmt(want), fmt(tolerance), fmt(got)), 2)
    end
end

-- ---------------------------------------------------------------------------
-- Instance factory: a fully-loaded, isolated addon environment
-- ---------------------------------------------------------------------------
--- Load a fresh isolated addon instance under its own mock.
--- @param initDB boolean  call the AceAddon OnInitialize (builds db) when true
--- @param enable boolean  run the OnEnable lifecycle cascade (needs initDB) when true
--- @param mutate function|nil  optional (mocks) -> () hook applied to the freshly
---        built mock table BEFORE any source loads. Needed by suites that have to
---        change the simulated client *before* init-time reads happen — e.g. the
---        frFR locale suite, where BuildSpells() resolves the player's spec during
---        OnInitialize and a post-load mock swap would be too late.
--- @param opts function|nil  optional loader options, forwarded verbatim. The
---        one that matters is `{ libFiles = {} }`, which loads the addon with
---        LibKa0s absent so the degradation stubs are exercised by a real load
---        rather than by hand-stubbing the member under test (testing-§8).
--- @return table inst  { NS, env, mocks }
local function loadInstance(initDB, enable, mutate, opts)
    local mocks = mockmod.build()
    if mutate then mutate(mocks) end
    local env, ns = loader.loadAll(root, mocks, opts)
    -- Pre-migration sources publish onto the global namespace (env.KickCD);
    -- post-KCD-01 sources populate the private `ns`. Prefer whichever exists.
    local NS = env.KickCD or ns
    if initDB and NS and NS.OnInitialize then pcall(NS.OnInitialize, NS) end
    -- Enable is NOT pcall-wrapped on purpose: a lifecycle throw (e.g. the
    -- IconGrid.Layout clobber) must surface to the calling test() so it's
    -- reported as a failure, not silently swallowed like OnInitialize.
    if enable and NS and NS.__enableAll then
        NS:__enableAll()
        if mocks.__flushTimers then mocks.__flushTimers() end
    end
    return { NS = NS, env = env, mocks = mocks }
end

-- Shared instance most suites use (DB built once).
local shared = loadInstance(true)

local T = {
    root = root,
    test = test,
    assertTrue = assertTrue,
    assertFalse = assertFalse,
    assertNil = assertNil,
    assertEqual = assertEqual,
    assertError = assertError,
    assertNear = assertNear,
    -- shared instance
    NS = shared.NS,
    env = shared.env,
    mocks = shared.mocks,
    -- fresh isolated instance for migration / bus tests
    load = loadInstance,
}
_G.KICKCD_TEST = T

-- ---------------------------------------------------------------------------
-- Suites (append new suites here as sprints add coverage)
-- ---------------------------------------------------------------------------
local SUITES = {
    "test_util.lua",
    "test_coresetup.lua",
    "test_util_anchor.lua",
    "test_constants.lua",
    "test_state.lua",
    "test_locale.lua",
    "test_units.lua",
    "test_schema.lua",
    "test_database.lua",
    "test_color_shape.lua",
    "test_bus.lua",
    "test_compat.lua",
    "test_compat_api.lua",
    "test_compat_debug.lua",
    "test_debuglog.lua",
    "test_debuglogsetup.lua",
    "test_icongrid_layout.lua",
    "test_icongrid_apply.lua",
    "test_icongrid_visibility.lua",
    "test_icongrid_render.lua",
    "test_icongrid_curves.lua",
    "test_icongrid_curve_link.lua",
    "test_icongrid_buildlist.lua",
    "test_lifecycle.lua",
    "test_unitlabel.lua",
    "test_unitlabel_apply.lua",
    "test_castbar.lua",
    "test_castbar_helpers.lua",
    "test_castbar_frame.lua",
    "test_castbar_skin.lua",
    "test_castbar_debug.lua",
    "test_cooldowns.lua",
    "test_cooldowns_gates.lua",
    "test_settings_log.lua",
    "test_settings_spells.lua",
    "test_settings_widgets.lua",
    "test_options_panel.lua",
    "test_settings_refreshers.lua",
    "test_flow_traces.lua",
    "test_version.lua",
    "test_slash_style.lua",
    "test_slash.lua",
    "test_opensettings.lua",
    "test_perfsetup.lua",
    "test_list_mode.lua",
    "test_vendor_sync.lua",
}

--- Render docs/test-cases.md's body from the recorded registry (§5).
-- Suites keep their load order (first-seen); cases keep registration order.
local function renderInventory()
    local order, bySuite = {}, {}
    for _, rec in ipairs(registry) do
        local g = bySuite[rec.suite]
        if not g then
            g = {}
            bySuite[rec.suite] = g
            order[#order + 1] = rec.suite
        end
        g[#g + 1] = rec.name
    end

    local out, total = {}, 0
    out[#out + 1] = "# Test Cases"
    out[#out + 1] = ""
    out[#out + 1] = "_Generated — do not hand-edit. Regenerate with "
        .. "`lua tests/run.lua --list > docs/test-cases.md`._"
    out[#out + 1] = ""
    for _, suite in ipairs(order) do
        local g = bySuite[suite]
        out[#out + 1] = ("### %s.lua (%d)"):format(suite, #g)
        out[#out + 1] = ""
        for _, name in ipairs(g) do
            out[#out + 1] = "- " .. name
        end
        out[#out + 1] = ""
        total = total + #g
    end
    out[#out + 1] = "## Totals"
    out[#out + 1] = ""
    out[#out + 1] = "| Suite | Cases |"
    out[#out + 1] = "| --- | --- |"
    for _, suite in ipairs(order) do
        out[#out + 1] = ("| %s.lua | %d |"):format(suite, #bySuite[suite])
    end
    out[#out + 1] = ("| **Total** | **%d** |"):format(total)
    out[#out + 1] = ""
    -- CRLF to match the repo-wide `eol=crlf` policy (.gitattributes): the body
    -- is redirected straight into docs/test-cases.md, which is stored/checked
    -- out as CRLF, so `diff <(--list) docs/test-cases.md` stays clean.
    return table.concat(out, "\r\n")
end

if not listMode then
    io.write("\nKickCD test harness\n===================\n")
end
for _, suite in ipairs(SUITES) do
    currentSuite = suite:gsub("%.lua$", "")
    if not listMode then io.write("\n" .. suite .. "\n") end
    dofile(root .. "/tests/" .. suite)
end

if listMode then
    io.write(renderInventory())
    os.exit(0)
end

io.write(("\n-------------------\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
    io.write("\nFailures:\n")
    for _, f in ipairs(failures) do io.write("  - " .. f .. "\n") end
end
os.exit(failed == 0 and 0 or 1)
