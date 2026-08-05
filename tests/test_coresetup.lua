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

-- ── the three lists testing-§9 makes assertable ─────────────────────────────
--
-- The library load list is no longer typed in the runner and then compared
-- against libs/LibKa0s/LibKa0s.xml — it is DERIVED from that XML by
-- Loader.xmlFiles, so a file-for-file comparison against the same XML would now
-- only be asserting that the parser is deterministic. What is still worth
-- pinning is what the derivation cannot guarantee on its own: that the derived
-- list is the one the runner actually FED the loader, that every path in it
-- resolves, and that the addon's own TOC-derived list does not leak a `libs/`
-- entry back in (which would load a library file twice, and out of XML order).

test("the runner FEEDS the derived library list, and it is not empty", function()
    -- An empty list loads nothing and reads exactly like a clean run: every
    -- major would be unregistered, every setup file would fall back to its stub,
    -- and the suite would happily measure the stub. The first case above is what
    -- catches that; this is what names it.
    -- red under: handing loadInstance a hand-typed list instead of LIB_FILES
    assertTrue(#T.libFiles > 0, "the runner fed the loader an EMPTY library list")
    assertEqual(#T.libFiles, #T.Loader.xmlFiles(T.root .. "/libs/LibKa0s/LibKa0s.xml"),
        "the fed list is not the list Loader.xmlFiles derives from LibKa0s.xml")
    for i, path in ipairs(T.libFiles) do
        assertTrue(path:find("libs/LibKa0s/", 1, true) ~= nil,
            "entry " .. i .. " is not a libs/LibKa0s path: " .. tostring(path))
    end
end)

test("every file the runner loads for LibKa0s exists on disk", function()
    -- Loader.xmlFiles is line-based over the XML, so a `<Script file="...">`
    -- naming a file nobody shipped derives cleanly. The loader raises on it
    -- first, before this case is reached — so this is the belt to that braces:
    -- it is what answers WHICH path is missing when the list is consulted
    -- without being loaded (a degraded arm, or a future perf runner).
    for _, path in ipairs(T.libFiles) do
        local fh = io.open(path, "r")
        assertTrue(fh ~= nil, "missing library file: " .. path)
        if fh then fh:close() end
    end
end)

test("the TOC-derived addon list leaks no libs/ entry", function()
    -- Loader.tocFiles skips `libs\` lines on purpose: the vendored library is
    -- pulled in through an XML the TOC scan cannot see inside, and the runner
    -- loads it FIRST, from LIB_FILES. A `libs/` path surviving into this list
    -- would load a library file a second time, after the addon's own sources,
    -- in TOC order rather than XML order.
    -- red under: deleting the `libs\\...\\*.lua` lines from KickCD.toc, which
    -- is what would make this guard assert nothing at all.
    assertTrue(#T.tocFiles > 0, "the TOC-derived addon list is empty")

    -- The guard is only meaningful while the TOC actually declares a `.lua`
    -- under `libs\\` for it to skip. It declares three today (LibStub,
    -- CallbackHandler and the five Ace majors); assert at least one, so a TOC
    -- that stopped shipping them turns this case red rather than vacuous.
    local toc = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local tocSrc = toc:read("*a")
    toc:close()
    assertTrue(tocSrc:lower():match("[\r\n]%s*libs[\\/][^\r\n]*%.lua") ~= nil,
        "the TOC declares no libs/*.lua line, so the skip guard asserts nothing")
    for _, rel in ipairs(T.tocFiles) do
        assertNil(rel:lower():match("^libs/"), "libs/ path leaked into the addon list: " .. rel)
    end
end)

test("the suite list and tests/test_*.lua on disk agree in both directions", function()
    -- Kit.run asserts this before it loads a single case, so a drifting list
    -- takes the whole run down rather than quietly running fewer cases. Called
    -- again here so the gate has a NAME in docs/test-cases.md — "the runner
    -- refused to start" is a bad place for a reader to first learn it exists.
    -- red under: adding tests/test_undeclared.lua, or declaring a suite with no
    -- file on disk
    T.assertSuiteInventory(T.root .. "/tests/", T.suites)
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

-- ── the shared cause clause (adoption 2026-08-01 §8) ────────────────────────
--
-- The user's decision, taken over KickCD's own five separately-worded
-- sentences: a player with a broken install must read the SAME sentence about
-- WHY, whichever Ka0s addon they have. AbsorbTracker established the shape in
-- its PLAN-04 — one NS.LIBKA0S_MISSING in core/CoreSetup.lua, and each seam
-- appends its own "so <what> is unavailable" — and ConsumableMaster follows it.
--
-- The STUBS did not converge and must not: settings/OptionsSetup.lua's is
-- load-completing rather than member-answering for measured reasons of its own.
-- Only the cause sentence moved.
--
-- These cases pin the RENDERED BYTES rather than the presence of the word
-- "LibKa0s", because the exact wording IS the convergence — a paraphrase that
-- still names the library is precisely the failure this exists to catch. And
-- they reach the seams through a real load with the library ABSENT
-- (testing-§8), never by hand-stubbing the member under test.

local CAUSE = "The LibKa0s library is missing from this installation of KickCD "
    .. "(expected in libs/LibKa0s)"

test("the shared cause clause is published on the healthy path too", function()
    -- Set OUTSIDE core/CoreSetup.lua's `if not lib` branch on purpose. A
    -- half-vendored libs/LibKa0s can carry Core.lua and be missing DebugLog.lua,
    -- and then the seam that degrades reads a clause only the seam that LOADED
    -- was in a position to publish.
    -- red under: moving the NS.LIBKA0S_MISSING assignment inside the branch
    assertEqual(NS.LIBKA0S_MISSING, CAUSE,
        "the shared clause must be published whether or not the library loaded")
end)

test("with LibKa0s absent all five seams say the same thing about WHY", function()
    -- Loaded with the library genuinely gone, then driven through each seam's
    -- own user-facing route. Every expected string below is spelled out in
    -- full, so a wording change has to be a decision.
    -- red under: any seam re-wording its half of the sentence
    local inst = T.load(true, false, nil, { libFiles = {} })
    assertNil(inst.mocks.LibStub("LibKa0s-Core-1.0", true),
        "sanity: the degraded load must not have the majors")
    assertEqual(inst.NS.LIBKA0S_MISSING, CAUSE,
        "sanity: the degraded load must publish the same clause")

    local P = inst.NS.PREFIX
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    local function drive(fn)
        for i = #lines, 1, -1 do lines[i] = nil end
        fn()
        return lines
    end

    -- 1. Core — said ONCE, ahead of the first line the addon ever prints, so it
    --    has to be driven first or another seam's print consumes it.
    local core = drive(function() inst.NS.Util.print("ping") end)
    assertEqual(core[1], P .. " " .. CAUSE .. "; running on reduced built-in fallbacks.",
        "core/CoreSetup.lua's announce line")
    assertEqual(core[2], P .. " ping", "and the line the caller actually asked for")

    -- 2. DebugLog — `/kcd debug window`, end to end through the verb table.
    local dbg = drive(function() inst.NS:OnSlashCommand("debug window") end)
    assertEqual(dbg[1], P .. " " .. CAUSE .. ", so the debug console window is unavailable.",
        "core/DebugLogSetup.lua's stub line")

    -- 3. Perf — OnCommand returns lines for the HOST to print (slash-commands-§2:
    --    `perf` is registered by the addon, never by the library), so pin both
    --    the returned string and what `/kcd perf` renders from it.
    local perfLines = inst.NS.Perf.OnCommand("")
    assertEqual(perfLines[1], CAUSE .. ", so performance measurement is unavailable.",
        "core/PerfSetup.lua's returned line, unprefixed")
    local perf = drive(function() inst.NS:OnSlashCommand("perf") end)
    assertEqual(perf[1], P .. " " .. CAUSE .. ", so performance measurement is unavailable.",
        "and the same line once the host has tagged it")

    -- 4. Options — NOT reachable via `/kcd config`, which goes to Blizzard's
    --    Settings layer. This IS the seam's entry point.
    local opts = drive(function() inst.NS.OpenOptionsPanel() end)
    assertEqual(opts[1], P .. " " .. CAUSE .. ", so the settings panel is unavailable.",
        "settings/OptionsSetup.lua's stub line")

    -- 5. Slash — the one seam whose consequence comes FIRST, because the verb
    --    has to lead or `/kcd list` is buried mid-sentence. AbsorbTracker
    --    inverts it identically, in its own
    --    ../AbsorbTracker/settings/Slash.lua `missing` stub.
    local slash = drive(function() inst.NS:OnSlashCommand("list") end)
    assertEqual(slash[1], P .. " /kcd list is unavailable. " .. CAUSE .. ".",
        "settings/Slash.lua's stub line")
end)

test("no seam re-spells the cause in its own words", function()
    -- The clause is only shared while there is exactly ONE copy of it. A future
    -- seam that pastes the sentence rather than concatenating the constant
    -- reads identically today and drifts on the next edit — which is the whole
    -- failure mode adoption 2026-08-01 §8 was raised about.
    -- red under: pasting "The LibKa0s library is missing from ..." into any seam
    local SEAMS = {
        "core/CoreSetup.lua", "core/DebugLogSetup.lua", "core/PerfSetup.lua",
        "settings/Slash.lua", "settings/OptionsSetup.lua",
    }
    local offenders, users = {}, 0
    for _, path in ipairs(SEAMS) do
        local fh = assert(io.open(T.root .. "/" .. path, "r"))
        local src = fh:read("*a")
        fh:close()
        for line in src:gmatch("[^\r\n]+") do
            -- Comments are prose about the clause and are not what renders.
            if not line:match("^%s*%-%-") then
                if line:find("library is missing from", 1, true) and
                    not line:find("NS.LIBKA0S_MISSING = ", 1, true) then
                    offenders[#offenders + 1] = path .. ": " .. line:match("^%s*(.-)%s*$")
                end
                if line:find("NS.LIBKA0S_MISSING", 1, true) and
                    not line:find("NS.LIBKA0S_MISSING = ", 1, true) then
                    users = users + 1
                end
            end
        end
    end
    assertEqual(#offenders, 0,
        "a seam spells the cause itself instead of appending to NS.LIBKA0S_MISSING: "
        .. table.concat(offenders, " | "))
    assertEqual(users, 5, "all five seams must READ the shared clause")
end)
