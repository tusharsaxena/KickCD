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

local function fmt(v)
    if type(v) == "table" then return "<table>" end
    return tostring(v)
end

local function test(name, fn)
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

-- ---------------------------------------------------------------------------
-- Instance factory: a fully-loaded, isolated addon environment
-- ---------------------------------------------------------------------------
--- Load a fresh isolated addon instance under its own mock.
--- @param initDB boolean  call the AceAddon OnInitialize (builds db) when true
--- @param enable boolean  run the OnEnable lifecycle cascade (needs initDB) when true
--- @return table inst  { NS, env, mocks }
local function loadInstance(initDB, enable)
    local mocks = mockmod.build()
    local env, ns = loader.loadAll(root, mocks)
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
    "test_schema.lua",
    "test_database.lua",
    "test_bus.lua",
    "test_compat.lua",
    "test_debuglog.lua",
    "test_icongrid_layout.lua",
    "test_lifecycle.lua",
    "test_cooldowns.lua",
}

io.write("\nKickCD test harness\n===================\n")
for _, suite in ipairs(SUITES) do
    io.write("\n" .. suite .. "\n")
    dofile(root .. "/tests/" .. suite)
end

io.write(("\n-------------------\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
    io.write("\nFailures:\n")
    for _, f in ipairs(failures) do io.write("  - " .. f .. "\n") end
end
os.exit(failed == 0 and 0 or 1)
