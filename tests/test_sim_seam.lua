-- tests/test_sim_seam.lua — the simulator's answer seam (core/SimSetup.lua) on LibKa0s-Sim-1.0.
--
-- KC-03 (KickCD#38; the Sim major's host contract H2, H7 and H9). core/SimSetup.lua wraps NS.Compat
-- with Sim:NewSeam straight after core/Compat.lua: the four PURE members are left alone, nothing is
-- guarded (KickCD sends and casts nothing), and every other function member is wrapped. These cases
-- pin what the library cannot enforce for us: nothing escapes the wrap (H2), the TOC slot, the two
-- degradation stubs against the live surfaces (H9), and the one `sim` slash row (H7) on a load
-- without the major and on a disabled addon.
--
-- Every case builds its own environment (tests/sim_support.lua's S.load, or T.load), never the
-- shared T.NS: an earlier suite may have swapped a Compat member by assignment, which is exactly
-- what Unwrapped() reports, and a session binds its seam for good.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

-- KC-01's unit and cast readers, and the four spell reads the grid's cooldowns run on.
local MUST_WRAP = {
    "UnitExists", "UnitCanAttack", "UnitIsDead", "UnitCastingInfo", "UnitChannelInfo",
    "UnitCastingDuration", "UnitChannelDuration",
    "GetSpellCooldown", "GetSpellCooldownDuration", "GetSpellCharges", "IsSpellUsable",
}
local PURE = { "IsSecret", "_firstReturn", "NewDuration", "DebugInterrupt" }

local NEEDS = "The simulator needs LibKa0s-Sim-1.0."

--- Every line NS.Util.print emits while `fn` runs, on `ns`.
local function said(ns, fn)
    local lines, real = {}, ns.Util.print
    ns.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    ns.Util.print = real
    if not ok then error(err, 0) end
    return lines
end

--- T.libFiles with the three Sim files left out: the payload loads, LibKa0s-Sim-1.0 does not.
local function libFilesWithoutSim()
    local out = {}
    for _, path in ipairs(T.libFiles) do
        if not path:match("/Sim[%a]*%.lua$") then out[#out + 1] = path end
    end
    assertTrue(#out == #T.libFiles - 3, "expected to drop Sim.lua, SimTimeline.lua and SimPanel.lua")
    return out
end

-- ── the seam ────────────────────────────────────────────────────────────────

test("Sim seam: NS.SimSeam is the library's seam and NS.SimHost the host's own table", function()
    local env = S.load()
    assertTrue(env.mocks.LibStub("LibKa0s-Sim-1.0", true) ~= nil, "LibKa0s-Sim-1.0 did not register")
    assertTrue(type(env.NS.SimHost) == "table", "NS.SimHost, the host's own table, is missing")
    assertTrue(#env.NS.SimSeam:Keys() > 0, "NS.SimSeam is the inert stub, not the library's seam")
end)

test("Sim seam: Unwrapped() is EMPTY after the whole addon loads (host contract H2)", function()
    -- red under: a Compat member defined after core/SimSetup.lua, or one replaced by assignment
    local escaped = S.load().NS.SimSeam:Unwrapped()
    assertEqual(#escaped, 0, "Compat members escaped the wrap: " .. table.concat(escaped, ", "))
end)

test("Sim seam: Keys() carries every read the simulator answers, and no PURE member", function()
    -- red under: a reader dropped into PURE, or a pure member left off it
    local NS = S.load().NS
    local keys = {}
    for _, k in ipairs(NS.SimSeam:Keys()) do keys[k] = true end
    for _, k in ipairs(MUST_WRAP) do
        assertTrue(type(NS.Compat[k]) == "function", k .. " is not a Compat function")
        assertTrue(keys[k] == true, k .. " is not wrapped by the seam")
    end
    for _, k in ipairs(PURE) do
        assertTrue(type(NS.Compat[k]) == "function", k .. " is not a Compat function")
        assertNil(keys[k], k .. " is pure and must not be wrapped")
    end
end)

test("Sim seam: idle, a wrapped member answers exactly what the client answers", function()
    -- No session: the wrap is one field test and a straight call through.
    local env = S.load()
    env.mocks.UnitExists = function(unit) return unit == "target" end
    assertEqual(env.NS.Compat.UnitExists("target"), true)
    assertEqual(env.NS.Compat.UnitExists("focus"), false)
end)

test("TOC: core/SimSetup.lua loads straight after core/Compat.lua, under a LOAD-BEARING comment", function()
    -- red under: moving the line, or dropping the comment that keeps it there
    local at
    for i, rel in ipairs(T.tocFiles) do if rel == "core/Compat.lua" then at = i end end
    assertTrue(at ~= nil, "core/Compat.lua is not in KickCD.toc")
    assertEqual(T.tocFiles[at + 1], "core/SimSetup.lua")
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local lines = {}
    for line in fh:lines() do lines[#lines + 1] = (line:gsub("\r$", "")) end
    fh:close()
    for i, line in ipairs(lines) do
        if line == "core\\SimSetup.lua" then
            assertTrue(lines[i - 2]:find("^# LOAD%-BEARING:") ~= nil,
                "the comment above core\\SimSetup.lua must open '# LOAD-BEARING:'")
        end
    end
end)

-- ── the degradation stubs against the live surfaces (H9; the Sim document's step 4) ──────────

test("Sim stubs: surface parity with a live instance and the live seam, both ways", function()
    -- red under: a stub missing a member the live surface has, or carrying one it does not
    local env = S.load()
    local host = env.NS.SimHost
    assertTrue(type(host.__newSimStub) == "function" and type(host.__newSeamStub) == "function",
        "core/SimSetup.lua does not export its two stubs on NS.SimHost")
    local liveSim, restore = S.testSession(env, {}, { start = false })
    local liveSeam = env.NS.SimSeam
    local stub, seamStub = host.__newSimStub(function() end), host.__newSeamStub()
    local previous = T.setSurfaceSource({ ["LibKa0s-Sim-1.0"] = liveSim })
    local ok, err = pcall(T.assertSurfaceParity, stub, "LibKa0s-Sim-1.0", {})
    T.setSurfaceSource(previous)
    restore()
    if not ok then error(err, 0) end
    T.assertSurfaceParity(stub, liveSim, "stub over the live instance", {})
    T.assertSurfaceParity(liveSim, stub, "live instance over the stub", {})
    T.assertSurfaceParity(seamStub, liveSeam, "seam stub over the live seam", {})
    T.assertSurfaceParity(liveSeam, seamStub, "live seam over the seam stub", {})
end)

-- ── the `sim` row (H7) ──────────────────────────────────────────────────────

test("Sim absent: NS.Sim:RunVerb prints the needs-library line once and answers absent", function()
    -- The payload loads; LibKa0s-Sim-1.0 does not. Nothing is wrapped and both stubs stand in.
    -- red under: a stub RunVerb that raises, prints twice, or reads NS.Util.print at load
    local inst = T.load(true, true, nil, { libFiles = libFilesWithoutSim() })
    local NS = inst.NS
    assertNil(inst.mocks.LibStub("LibKa0s-Sim-1.0", true), "sanity: no Sim major on this load")
    assertEqual(#NS.SimSeam:Keys(), 0, "the seam stub wraps nothing")
    local ok, code
    local lines = said(NS, function() ok, code = NS.Sim:RunVerb("") end)
    assertEqual(ok, false)
    assertEqual(code, "absent")
    assertEqual(table.concat(lines, "\n"), NEEDS)
    -- ...and `/kcd sim` dispatches to it.
    lines = said(NS, function() NS:OnSlashCommand("sim start") end)
    assertEqual(table.concat(lines, "\n"), NEEDS)
end)

test("LibKa0s absent: `/kcd sim` reaches the stub through the degraded dispatcher", function()
    -- The whole payload missing (tests/test_slash_degraded.lua's loader idiom).
    local inst = T.load(true, true, nil, { libFiles = {} })
    local NS = inst.NS
    assertNil(inst.mocks.LibStub("LibKa0s-Slash-1.0", true), "sanity: no library on this load")
    local lines = said(NS, function() NS:OnSlashCommand("sim") end)
    assertEqual(table.concat(lines, "\n"), NEEDS)
end)

test("`/kcd sim` while disabled is refused with the library's line and does not reach NS.Sim", function()
    -- red under: `sim` missing from the refused set (NS.FEATURE_VERBS, the live gate's complement)
    local inst = T.load(true, true)
    local NS = inst.NS
    said(NS, function() NS:OnSlashCommand("disable") end)
    assertEqual(NS.db.profile.enabled, false, "sanity: the addon is off")
    local calls, real = 0, NS.Sim.RunVerb
    NS.Sim.RunVerb = function(...) calls = calls + 1; return real(...) end
    local lines = said(NS, function() NS:OnSlashCommand("sim") end)
    NS.Sim.RunVerb = real
    assertEqual(table.concat(lines, "\n"), NS.Slash.cli:DisabledLine())
    assertEqual(calls, 0, "the refused verb still reached NS.Sim:RunVerb")
end)
