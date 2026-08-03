-- tests/test_debuglogsetup.lua
-- LibKa0s-DebugLog-1.0 wiring: the descriptor is well-formed, the console the
-- library builds is the console modules/DebugLog.lua used to build, and the
-- library-absent load still answers every member the addon calls.
--
-- testing-§8: the console's own behavior is tested where it lives, in the
-- library's suite. What is pinned here is the WIRING — the descriptor fields
-- this addon passes, and the rendered bytes that changed hands.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil
local NS, mocks = T.NS, T.mocks

-- ── the old module is gone ──────────────────────────────────────────────────

test("modules/DebugLog.lua has been deleted, not left beside the library", function()
    -- red under: restoring the file. Two consoles that both work is the fork
    -- anti-patterns #47 describes: only the eighth addon's log reads differently.
    local fh = io.open(T.root .. "/modules/DebugLog.lua", "r")
    if fh then fh:close() end
    assertNil(fh, "modules/DebugLog.lua still exists")
end)

test("the TOC lists core/DebugLogSetup.lua and no longer lists modules/DebugLog.lua", function()
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local toc = fh:read("*a")
    fh:close()
    assertTrue(toc:find("core\\DebugLogSetup.lua", 1, true) ~= nil,
        "the setup file must be in the TOC")
    assertNil(toc:find("modules\\DebugLog.lua", 1, true),
        "the deleted module must not still be listed")
end)

-- ── the formatters, byte for byte ───────────────────────────────────────────
--
-- Both were already byte-identical to the library's before the swap, which is
-- exactly why they are worth pinning: a formatter that changed hands without a
-- byte-level assertion is a rendered-output regression nothing would catch.

test("FormatPlain renders <ts> | [<tag>] <msg> byte for byte", function()
    assertEqual(NS.DebugLog.FormatPlain("12:34:56", "Cast", "hello"),
        "12:34:56 | [Cast] hello")
end)

test("FormatColored keeps the steel-blue stamp, tan tag and escaped pipe", function()
    -- The `||` is ONE literal pipe inside a color-coded string. "Simplifying"
    -- it to a single pipe silently breaks the separator.
    assertEqual(NS.DebugLog.FormatColored("12:34:56", "Cast", "hello"),
        "|cff6f8faf12:34:56|r || |cffc9a66b[Cast]|r hello")
end)

test("a nil tag renders as empty brackets rather than the string 'nil'", function()
    assertEqual(NS.DebugLog.FormatPlain("00:00:00", nil, "m"), "00:00:00 | [] m")
end)

-- ── the descriptor ──────────────────────────────────────────────────────────

test("the console registers under the same frame name modules/DebugLog.lua hardcoded", function()
    -- The descriptor's `name` seeds <name>DebugWindow, <name>DebugCopyWindow and
    -- <name>DebugCopyScroll. modules/DebugLog.lua spelled all three out. Passing
    -- addonName reproduces them exactly, so ESC-to-close and a saved frame
    -- position survive the swap.
    --
    -- Asserted through UISpecialFrames rather than a global lookup because this
    -- addon's CreateFrame mock DISCARDS the name argument, so a named frame
    -- never lands in the sandbox as a global. UISpecialFrames carries the string
    -- the library actually derived, which is the thing under test anyway.
    NS.DebugLog:Show()
    NS.DebugLog:Hide()
    local seen = table.concat(mocks.UISpecialFrames or {}, ",")
    assertTrue(seen:find("KickCDDebugWindow", 1, true) ~= nil,
        "expected KickCDDebugWindow in UISpecialFrames, got: " .. seen)
end)

test("the console title is the brand plus the library's own suffix", function()
    -- _frameForTest is a FIELD on the instance, not a method: a headless mock's
    -- Show/Hide track visibility without firing OnShow, so the frame is only
    -- reachable directly.
    NS.DebugLog:Show()
    local f = NS.DebugLog._frameForTest
    NS.DebugLog:Hide()
    assertTrue(f ~= nil, "the library did not expose the console frame")
    assertEqual(f.titleText, "Ka0s KickCD \226\128\148 Debug")
end)

test("the debug flag stays the addon's — the library never keeps a copy", function()
    local prev = NS.State.debug
    NS.DebugLog:SetEnabled(true)
    assertEqual(NS.State.debug, true, "setEnabled must write NS.State.debug")
    assertEqual(NS.DebugLog:IsEnabled(), true)
    NS.DebugLog:SetEnabled(false)
    assertEqual(NS.State.debug, false)
    NS.State.debug = prev
end)

-- ── the rendered acknowledgement ────────────────────────────────────────────

local function capture(fn)
    local lines = {}
    local prev = mocks.DEFAULT_CHAT_FRAME
    mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }
    fn()
    mocks.DEFAULT_CHAT_FRAME = prev
    return lines
end

test("the enable ack renders the state word green, through the addon's tagged printer", function()
    local prev = NS.State.debug
    local lines = capture(function() NS.DebugLog:SetEnabled(true) end)
    NS.DebugLog:SetEnabled(false)
    NS.State.debug = prev
    assertEqual(lines[1], NS.PREFIX .. " debug logging |cff40ff40ON|r")
end)

test("the disable ack renders the state word red", function()
    local prev = NS.State.debug
    NS.DebugLog:SetEnabled(true)
    local lines = capture(function() NS.DebugLog:SetEnabled(false) end)
    NS.State.debug = prev
    assertEqual(lines[1], NS.PREFIX .. " debug logging |cffff4040OFF|r")
end)

test("enabling brackets the session and follows it with the host's [Init] summary", function()
    local prev = NS.State.debug
    NS.DebugLog:Clear()
    NS.DebugLog:SetEnabled(true)
    local lines = NS.DebugLog.buffer
    NS.DebugLog:SetEnabled(false)
    NS.State.debug = prev

    assertTrue(lines[1]:find("[Debug] logging enabled", 1, true) ~= nil,
        "expected the enable bracket first, got: " .. tostring(lines[1]))
    -- The library owns WHEN it lands; only the host can know what it says.
    assertTrue(lines[2]:find("[Init] KickCD v", 1, true) ~= nil,
        "expected the [Init] summary second, got: " .. tostring(lines[2]))
    assertTrue(lines[2]:find("schema v", 1, true) ~= nil, "summary must name the schema version")
    assertTrue(lines[2]:find("profile '", 1, true) ~= nil, "summary must name the active profile")
end)

-- ── the sink ────────────────────────────────────────────────────────────────

test("NS.Debug is bound bare off the instance and takes no self", function()
    assertEqual(type(NS.Debug), "function")
    assertEqual(NS.Debug, NS.DebugLog.Debug, "must be the instance's own plain function")
end)

test("NS.Debug is zero-cost when the flag is off", function()
    local prev = NS.State.debug
    NS.State.debug = false
    NS.DebugLog:Clear()
    NS.Debug("T", "should not land %s", "x")
    assertEqual(NS.DebugLog:BufferSize(), 0)
    NS.State.debug = prev
end)

test("a numeric format slot still renders correctly now the library stringifies every arg", function()
    -- THE behavior change in this swap. modules/DebugLog.lua's guard was an
    -- IDENTITY pass-through, so `%d` received a number. The library routes every
    -- vararg through safeToString first, so `%d` now receives the STRING "3".
    -- Lua coerces, and the rendered bytes are unchanged — but this is the case
    -- that says so, because nothing else would notice until a log looked wrong.
    local prev = NS.State.debug
    NS.State.debug = true
    NS.DebugLog:Clear()
    NS.Debug("T", "dropped %d icon(s) past the %d-slot grid", 3, 12)
    NS.State.debug = prev
    local line = NS.DebugLog:LastLine()
    assertTrue(line and line:find("dropped 3 icon(s) past the 12-slot grid", 1, true) ~= nil,
        "numeric slots must still render as bare integers; got: " .. tostring(line))
end)

test("a secret argument renders as the shared sentinel and cannot raise", function()
    local prev = NS.State.debug
    local SECRET = setmetatable({}, {})
    local realIsSecret = mocks.issecretvalue
    mocks.issecretvalue = function(v) return v == SECRET end
    NS.State.debug = true
    NS.DebugLog:Clear()
    local ok = pcall(function() NS.Debug("T", "charges=%s", SECRET) end)
    mocks.issecretvalue = realIsSecret
    NS.State.debug = prev
    assertTrue(ok, "the sink must not raise on a secret argument")
    local line = NS.DebugLog:LastLine()
    assertTrue(line and line:find("charges=<secret>", 1, true) ~= nil,
        "got: " .. tostring(line))
end)

-- ── the degraded path ───────────────────────────────────────────────────────

test("with LibKa0s absent the stub answers every DebugLog member the addon calls", function()
    -- debug-logging-§7: "A stub that omits a member is not a fallback — it is a
    -- crash moved to a rarer code path." The list is grep-derived from the
    -- addon's own call sites, not from the library's surface.
    local inst = T.load(true, false, nil, { libFiles = {} })
    local D = inst.NS.DebugLog
    assertTrue(D ~= nil, "NS.DebugLog must exist even with no library")
    for _, member in ipairs({
        "Add", "Debug", "Clear", "Show", "Hide", "Toggle", "IsShown", "IsEnabled",
        "SetEnabled", "ShowCopy", "UpdateScrollBar", "UpdateStatus",
        "BufferSize", "LastLine", "FindLine", "FormatPlain", "FormatColored",
        "ConsoleCheckbox", "RefreshHeader",
    }) do
        assertEqual(type(D[member]), "function", "stub is missing " .. member)
    end
    assertEqual(type(D.buffer), "table", "stub must carry the raw buffer")
end)

test("the degraded stub still flips the flag and still prints the ack", function()
    -- NS.State.debug is the addon's, not the library's. A user who types
    -- `/kcd debug on` must not be told nothing happened; what is lost is the
    -- WINDOW, and the stub says so once.
    local inst = T.load(true, false, nil, { libFiles = {} })
    local lines = {}
    local prev = inst.mocks.DEFAULT_CHAT_FRAME
    inst.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }
    inst.NS.DebugLog:SetEnabled(true)
    inst.mocks.DEFAULT_CHAT_FRAME = prev

    assertEqual(inst.NS.State.debug, true, "the stub must still write the flag")
    local joined = table.concat(lines, "\n")
    assertTrue(joined:find("debug logging |cff40ff40ON|r", 1, true) ~= nil,
        "the ack must still print; got: " .. joined)
end)

test("the degraded stub carries no copy of the line formatters", function()
    -- debug-logging-§3: the stub MUST NOT reproduce the format or its color
    -- codes. Copying the exact strings whose seven-way drift this extraction
    -- exists to end is the one duplicate testing-§8 most specifically forbids.
    -- red under: pasting the real format string into the stub's FormatColored
    local fh = assert(io.open(T.root .. "/core/DebugLogSetup.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match("6f8faf"), "the stub must not carry the timestamp color")
    assertNil(src:match("c9a66b"), "the stub must not carry the tag color")
end)

-- ── the L trap ──────────────────────────────────────────────────────────────
--
-- core/DebugLogSetup.lua's descriptor omits `L` entirely, which is the correct
-- shape for an addon that translates nothing. The guard below is what stops
-- someone adding one — this addon SHIPPED the trap once, in its perf panel, and
-- the console has thirteen more strings that would go the same way at once.
--
-- Honest about falsifiability, same split as the Slash and Perf pairs:
--   * the first case pins the rendered result — red when a raw key reaches the
--     override table;
--   * the second case is the LIBRARY-regression detector — red the moment
--     DebugLog.lua resolves an override with a plain index instead of rawget.
-- Adding `L = NS.L` to the descriptor reddens NEITHER, because DebugLog 3 uses
-- rawget and this addon's NS.L is keyed by English phrases, so every rawget
-- misses and lib.STRINGS wins. That descriptor mistake is caught by the source
-- check in test_perfsetup.lua, which sweeps all five setup files.

test("every string the debug console renders resolves to prose, not to its own key", function()
    -- red under: `L = { CLEAR = "CLEAR" }` on the descriptor in
    -- core/DebugLogSetup.lua
    local lib = mocks.LibStub("LibKa0s-DebugLog-1.0", true)
    assertTrue(lib ~= nil, "the vendored DebugLog major must be registered")
    local D = NS.DebugLog
    assertEqual(type(D.Text), "function",
        "Text is THE resolver; without it on the live instance this case proves nothing")

    for key in pairs(lib.STRINGS) do
        local rendered = D:Text(key)
        assertEqual(type(rendered), "string", "Text('" .. key .. "') returned no string")
        -- The exact shape of the trap: the rendered string IS the key. Stated
        -- this way rather than as the bare `^[A-Z][A-Z0-9_]+$` sweep because
        -- two of this module's strings are legitimately all-caps prose —
        -- STATE_ON renders "ON" and STATE_OFF renders "OFF" — and a pattern
        -- that reddens on those is a case that fails for the wrong reason.
        assertTrue(rendered ~= key, "'" .. key .. "' rendered its own key verbatim")
        -- The SCREAMING_SNAKE sweep still applies to everything with an
        -- underscore in it, which is every remaining key in the table.
        assertNil(rendered:match("^[A-Z][A-Z0-9]*_[A-Z0-9_]*$"),
            "'" .. key .. "' rendered a raw key: " .. rendered)
        -- The descriptor declares no override, so EVERY key must be the
        -- library's own. That is the half a bare `NS.L` would take away.
        assertEqual(rendered, lib.STRINGS[key],
            "'" .. key .. "' must come from the library's own STRINGS")
    end
end)

test("the console title and checkbox carry prose, reached the way the UI reaches them", function()
    -- Not the resolver this time: the two composed strings a user actually
    -- reads. ConsoleCheckbox() is what settings/General.lua renders.
    -- red under: `L = { TITLE_SUFFIX = "TITLE_SUFFIX" }` on the descriptor
    local D = NS.DebugLog
    local title = "Ka0s KickCD" .. D:Text("TITLE_SUFFIX")
    assertEqual(title, "Ka0s KickCD \226\128\148 Debug",
        "the composed title bar changed: " .. title)

    local cb = D:ConsoleCheckbox()
    assertEqual(type(cb), "table", "ConsoleCheckbox must answer")
    for _, field in ipairs({ "label", "tooltip" }) do
        local v = cb[field]
        assertEqual(type(v), "string", "the checkbox " .. field .. " must be a string")
        assertNil(v:match("^[A-Z][A-Z0-9_]+$"),
            "the checkbox " .. field .. " rendered its raw key: " .. v)
    end
    -- The slash-carrying variant, so a regression to the no-slash string shows.
    assertTrue(cb.tooltip:find("/kcd", 1, true) ~= nil,
        "the descriptor passes slash = \"/kcd\", so the substituted tooltip is the one to render")
end)

test("the vendored DebugLog major falls THROUGH a key-returning locale table", function()
    -- The library-regression half. Every Ka0s host's locale table answers an
    -- unknown key WITH THE KEY (locales/enUS.lua:15, mandated by the standard),
    -- so a synthesized value IS a string and a plain index accepts all of them.
    --
    -- red under: `local v = strings and rawget(strings, key)` ->
    -- `local v = strings and strings[key]` in libs/LibKa0s/DebugLog.lua
    local lib = mocks.LibStub("LibKa0s-DebugLog-1.0", true)
    local D = lib:New({
        name       = "TrapProbe",
        title      = "TrapProbe",
        font       = "Interface\\AddOns\\KickCD\\media\\fonts\\probe.ttf",
        isEnabled  = function() return false end,
        setEnabled = function() end,
        print      = function() end,
        L          = setmetatable({}, { __index = function(_, k) return k end }),
    })
    for key in pairs(lib.STRINGS) do
        local rendered = D:Text(key)
        assertTrue(rendered ~= key,
            "the vendored library let the synthesized key '" .. key .. "' through verbatim")
        assertEqual(rendered, lib.STRINGS[key],
            "'" .. key .. "' must fall through to the library's own string")
    end
end)
