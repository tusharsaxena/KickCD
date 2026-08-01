-- tests/test_coresetup.lua
-- LibKa0s-Core-1.0 wiring: the vendored library actually loads in the harness,
-- core/CoreSetup.lua builds the prefixed printer from it, and the secret-safe
-- stringifier is published under the names the rest of the addon calls.
--
-- The first case is the one that keeps the rest honest. testing-§9: a library
-- file omitted from the runner's load list makes the dependent module refuse to
-- register, the host's setup file falls back to its stub, and the suite happily
-- measures THE STUB — green, and testing nothing. So pin the registry first.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil
local NS, mocks = T.NS, T.mocks

-- Every major LibKa0s.xml ships, in that file's own order. Kept as data so the
-- next case can compare it against the XML rather than trusting this list.
local MAJORS = {
    "LibKa0s-Core-1.0",
    "LibKa0s-DebugLog-1.0",
    "LibKa0s-Slash-1.0",
    "LibKa0s-Options-1.0",
    "LibKa0s-Perf-1.0",
}

-- ── the library is really loaded ────────────────────────────────────────────

test("the harness loads the vendored LibKa0s majors, so the suite is not measuring a stub", function()
    for _, major in ipairs(MAJORS) do
        assertTrue(mocks.LibStub(major, true) ~= nil,
            major .. " is not registered — the runner's library load list is wrong, and every "
            .. "assertion below would be measuring the degradation stub")
    end
end)

test("the runner's library load list matches libs/LibKa0s/LibKa0s.xml file for file", function()
    -- A file added to the library and forgotten in the runner is exactly the
    -- silent failure testing-§9 describes, so derive the truth from the XML
    -- instead of restating it.
    local loader = dofile(T.root .. "/tests/loader.lua")
    local fromXML = {}
    local f = assert(io.open(T.root .. "/libs/LibKa0s/LibKa0s.xml", "r"))
    for line in f:lines() do
        local file = line:match('<Script%s+file="([^"]+)"')
        if file then fromXML[#fromXML + 1] = "libs/LibKa0s/" .. file end
    end
    f:close()

    assertTrue(#fromXML > 0, "parsed no <Script> entries out of LibKa0s.xml")
    assertEqual(#loader.LIB_FILES, #fromXML, "library file count")
    for i = 1, #fromXML do
        assertEqual(loader.LIB_FILES[i], fromXML[i], "library file " .. i)
    end
end)

test("every file the runner loads for LibKa0s exists on disk", function()
    local loader = dofile(T.root .. "/tests/loader.lua")
    for _, rel in ipairs(loader.LIB_FILES) do
        local fh = io.open(T.root .. "/" .. rel, "r")
        assertTrue(fh ~= nil, "missing library file: " .. rel)
        if fh then fh:close() end
    end
end)

-- ── the secret-safe seam ────────────────────────────────────────────────────

test("NS.SafeToString renders ordinary values through tostring", function()
    assertEqual(NS.SafeToString("hello"), "hello")
    assertEqual(NS.SafeToString(42), "42")
end)

test("NS.SafeToString answers nil and booleans up front, never masking them", function()
    -- table.concat rejects a boolean element too, but a boolean is never
    -- secret, so masking one would be a lie.
    assertEqual(NS.SafeToString(nil), "nil")
    assertEqual(NS.SafeToString(true), "true")
    assertEqual(NS.SafeToString(false), "false")
end)

test("NS.SafeToString renders an unconcatable value as the shared <secret> sentinel", function()
    -- The sentinel is the LIBRARY's, exported so the addon's tests, its docs and
    -- the implementation cannot drift. modules/DebugLog.lua and
    -- modules/Cooldowns.lua each emitted a bare "secret" before this landed.
    assertEqual(NS.SafeToString({}), "<secret>")
end)

test("NS.IsConcatSafe probes table.concat, not the .. operator", function()
    assertTrue(NS.IsConcatSafe("x"))
    assertTrue(NS.IsConcatSafe(1))
    -- A table survives `..`-free tostring but raises inside table.concat, which
    -- is the operation every emitted line actually ends in.
    assertEqual(NS.IsConcatSafe({}), false)
end)

-- ── the printer ─────────────────────────────────────────────────────────────

local function capture(fn)
    local lines = {}
    local prev = mocks.DEFAULT_CHAT_FRAME
    mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }
    fn()
    mocks.DEFAULT_CHAT_FRAME = prev
    return lines
end

test("NS.Util.print renders prefix, one space, then the body — byte for byte", function()
    local lines = capture(function() NS.Util.print("hello") end)
    assertEqual(#lines, 1)
    assertEqual(lines[1], NS.PREFIX .. " hello")
end)

test("NS.Util.print space-joins its arguments, mirroring print()", function()
    local lines = capture(function() NS.Util.print("a", "b", "c") end)
    assertEqual(lines[1], NS.PREFIX .. " a b c")
end)

test("NS.Util.print is secret-safe: an unconcatable argument cannot raise", function()
    -- The whole reason the printer moved. core/Util.lua's version ran tostring
    -- then table.concat with no guard at all, so a combat-protected value taken
    -- from a Unit* API raised on its way to the chat frame — and on a repeating
    -- ticker that killed the ticker until /reload.
    local lines = capture(function() NS.Util.print("charges", {}) end)
    assertEqual(lines[1], NS.PREFIX .. " charges <secret>")
end)

test("NS.Util.print resolves the prefix at call time, not at load time", function()
    -- Passed to the library as the FUNCTION form. core/Util.lua froze it into a
    -- file-scope local, so a prefix defined in a later-loading file would have
    -- been captured as nil forever.
    local prev = NS.PREFIX
    NS.PREFIX = "|cff00ffff[XX]|r"
    local lines = capture(function() NS.Util.print("body") end)
    NS.PREFIX = prev
    assertEqual(lines[1], "|cff00ffff[XX]|r body")
end)

test("NS.Util.print is the library printer, not a host reimplementation", function()
    -- Guards against the setup file quietly growing its own copy of the join.
    -- The library's Print is a plain function, never a method: call sites do a
    -- bare NS.Util.print(...) with no self.
    assertEqual(type(NS.Util.print), "function")
    local ok = pcall(NS.Util.print, "no self needed")
    assertTrue(ok, "the printer must be dot-callable")
end)

test("core/Util.lua no longer defines a printer of its own", function()
    -- red under: restoring `function Util.print` to core/Util.lua
    local f = assert(io.open(T.root .. "/core/Util.lua", "r"))
    local src = f:read("*a")
    f:close()
    assertNil(src:match("function Util%.print"),
        "core/Util.lua must not redefine the printer — CoreSetup owns that seam now")
end)

-- ── one sentinel, addon-wide ────────────────────────────────────────────────

test("no addon file emits a bare \"secret\" sentinel of its own", function()
    -- red under: restoring `return "secret"` in modules/Cooldowns.lua's safeStr
    --
    -- Three hand-written secret guards existed here before LibKa0s. They agreed
    -- on the MECHANISM (issecretvalue) and disagreed on the OUTPUT: core/Compat
    -- rendered "<secret>", while modules/DebugLog.lua and modules/Cooldowns.lua
    -- each rendered a bare "secret". A pasted log therefore spelled the same
    -- condition two ways depending on which module wrote the line. The sentinel
    -- is the library's now, exported as lib.SECRET precisely so it cannot drift.
    local dirs = { "core", "modules", "settings" }
    local offenders = {}
    for _, dir in ipairs(dirs) do
        local pipe = io.popen("ls " .. T.root .. "/" .. dir .. "/*.lua 2>/dev/null")
        for path in pipe:lines() do
            local fh = io.open(path, "r")
            local n = 0
            for line in fh:lines() do
                n = n + 1
                -- `return "secret"` — the exact shape all three guards used.
                if line:match('return%s+"secret"') then
                    offenders[#offenders + 1] = path .. ":" .. n
                end
            end
            fh:close()
        end
        pipe:close()
    end
    assertEqual(#offenders, 0,
        "bare \"secret\" sentinel at: " .. table.concat(offenders, ", ")
        .. " — use NS.SafeToString so every line spells it <secret>")
end)

-- ── the degraded path ───────────────────────────────────────────────────────

test("with LibKa0s absent the addon still loads and still prints tagged lines", function()
    -- debug-logging-§7 / testing-§8: verified by actually loading the addon
    -- without the library, not by hand-stubbing the member under test.
    local inst = T.load(true, false, nil, { libFiles = {} })
    assertNil(inst.mocks.LibStub("LibKa0s-Core-1.0", true),
        "the degraded load must not have the major registered")

    local lines = {}
    local prev = inst.mocks.DEFAULT_CHAT_FRAME
    inst.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }
    inst.NS.Util.print("still here")
    inst.mocks.DEFAULT_CHAT_FRAME = prev

    -- The honest "it is not installed" line is said ONCE, on the first line the
    -- addon prints, rather than stapled to every one of them.
    assertEqual(#lines, 2)
    assertTrue(lines[1]:find("LibKa0s", 1, true) ~= nil,
        "the first printed line must name the missing library, got: " .. tostring(lines[1]))
    assertEqual(lines[2], inst.NS.PREFIX .. " still here")
end)

test("the degraded printer is still secret-safe and still says <secret>", function()
    -- The stub MUST NOT re-implement the library's rendering, but the guard is
    -- not rendering — it is the difference between a chat line and a Lua error
    -- on a repeating ticker.
    local inst = T.load(true, false, nil, { libFiles = {} })
    assertEqual(inst.NS.SafeToString({}), "<secret>")
end)

-- ── the L trap ──────────────────────────────────────────────────────────────
--
-- Stated plainly, because the honest answer here is "there is nothing to
-- assert yet": LibKa0s-Core-1.0 declares NO lib.STRINGS table and reads NO
-- descriptor `L`. Its entire rendered output is the host's own — the prefix
-- core/CoreSetup.lua passes and whatever the caller hands Util.print. There is
-- no library string for a locale table to shadow, so a case asserting one
-- "resolves to prose" would be asserting something about KickCD's own literals
-- dressed up as an adoption guard, and it could never fail.
--
-- What CAN fail is the assumption itself. The case below is a tripwire on the
-- library, not on this addon: the day Core grows a user-visible string, it goes
-- red and whoever bumps the minor writes the fall-through assertion that
-- test_slash.lua, test_debuglogsetup.lua and test_perfsetup.lua already carry
-- for their majors.

test("LibKa0s-Core-1.0 still has no user-visible strings to trap", function()
    -- red under: adding a `lib.STRINGS = { ... }` table or a `d.L` read to
    -- libs/LibKa0s/Core.lua
    local lib = mocks.LibStub("LibKa0s-Core-1.0", true)
    assertTrue(lib ~= nil, "the vendored Core major must be registered")
    assertNil(lib.STRINGS,
        "Core now ships STRINGS — this major needs an L-trap assertion of its own")

    local fh = assert(io.open(T.root .. "/libs/LibKa0s/Core.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match("STRINGS"), "Core.lua now names STRINGS")
    assertNil(src:match("d%.L[^%w_]"), "Core.lua now reads a descriptor L")
end)

test("the Core descriptor passes no locale table, and the printer renders no key", function()
    -- The rendered half, such as it is: what actually comes out of the seam.
    -- The prefix is the ONLY library-rendered fragment in this major, and it is
    -- ours — so pin that it is prose and that nothing key-shaped leaks in.
    -- red under: `NS.PREFIX = "ADDON_PREFIX"` in core/Constants.lua
    local fh = assert(io.open(T.root .. "/core/CoreSetup.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match("\n%s*L%s*="),
        "the Core descriptor grew an L; Core has no STRINGS for it to override")

    local lines = {}
    local frame = mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    NS.Util.print("hello")
    frame.AddMessage = orig

    assertEqual(#lines, 1, "the printer must have emitted exactly one line")
    local text = lines[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for word in text:gmatch("%a[%a%d_]*") do
        assertNil(word:match("^[A-Z][A-Z0-9]*_[A-Z0-9_]*$"),
            "the printed line carries a raw key '" .. word .. "': " .. lines[1])
    end
end)
