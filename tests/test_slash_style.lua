-- tests/test_slash_style.lua — chat-line style rules for slash output.
--
-- slash-commands-§4: NO chat line ends in a trailing `:`. A list is introduced
-- by its header text alone, never by punctuation. The 2026-07-18 standards
-- audit caught three violations (KCD-25) — the `/kcd help` header plus the
-- `debug` and `spells` sub-headers. Those were fixed in code; this suite is the
-- regression guard that stops the next help-text edit reintroducing one
-- silently, which is the half of KCD-25 that never got written at the time.
--
-- The suite guards the rule two ways, deliberately, because each alone has a
-- hole the other covers:
--
--   1. **Behavioural** — drive the real verbs and inspect what reaches chat, so
--      a new sub-header under any covered path is caught automatically without
--      anyone remembering to add a case.
--   2. **Source scan** — grep every addon `.lua` for a string literal ending in
--      `:` that closes a call. Driving verbs can only reach code the headless
--      mock can satisfy; the diagnostic dumps in particular bail early when no
--      unit exists. Five real violations survived in exactly those unreachable
--      branches (`modules/Castbar_Debug.lua`, `core/Compat.lua`'s
--      `DebugInterrupt`) — the audit's grep missed them because it only looked
--      at the help printers, and a behaviour-only guard would have missed them
--      too.
local T = _G.KICKCD_TEST
local test, assertTrue = T.test, T.assertTrue
local NS = T.NS

--- Drive a slash verb on the shared instance and capture every chat line
--- NS.Util.print emits (it routes through DEFAULT_CHAT_FRAME:AddMessage).
local function runVerb(input)
    local lines = {}
    local frame = T.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, msg) lines[#lines + 1] = msg end
    NS:OnSlashCommand(input)
    frame.AddMessage = orig
    return lines
end

--- Strip WoW colour escapes and trailing whitespace so the assertion sees the
--- character a player actually reads last. `|cAARRGGBB` opens a colour run and
--- `|r` closes it; a line ending `…subcommands:|r` still ends in a colon.
local function visibleText(line)
    return (tostring(line)
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("%s+$", ""))
end

--- Assert no captured line ends in `:`. Names the offending line so a failure
--- points at the string to fix rather than just the verb.
local function assertNoTrailingColon(lines, what)
    assertTrue(#lines > 0, what .. " printed nothing — the capture is broken")
    for _, line in ipairs(lines) do
        local text = visibleText(line)
        assertTrue(text:sub(-1) ~= ":",
            what .. " emitted a line ending in ':' (slash-commands-§4): " .. text)
    end
end

test("/kcd help emits no line ending in ':' (slash-commands-§4)", function()
    assertNoTrailingColon(runVerb("help"), "/kcd help")
end)

test("bare /kcd emits no line ending in ':'", function()
    -- No verb falls through to the same help path; pinned separately because
    -- it is the line most players see first.
    assertNoTrailingColon(runVerb(""), "bare /kcd")
end)

test("/kcd debug sub-header emits no line ending in ':'", function()
    -- Bare `debug` also toggles the console window; harmless headlessly, and
    -- driving the real verb is what makes new sub-headers self-covering.
    assertNoTrailingColon(runVerb("debug"), "/kcd debug")
end)

test("/kcd spells sub-header emits no line ending in ':'", function()
    assertNoTrailingColon(runVerb("spells"), "/kcd spells")
end)

test("every COMMANDS verb description is free of a trailing ':'", function()
    -- The help body interpolates these, so a colon here becomes a colon on a
    -- chat line even though the header itself is clean.
    for _, entry in ipairs(NS.COMMANDS) do
        local desc = visibleText(entry[2])
        assertTrue(desc:sub(-1) ~= ":",
            "COMMANDS verb '" .. tostring(entry[1]) .. "' description ends in ':'")
    end
end)

test("an unknown verb's error line does not end in ':'", function()
    assertNoTrailingColon(runVerb("nosuchverb"), "/kcd nosuchverb")
end)

-- ── Diagnostic dumps ────────────────────────────────────────────────────────
--
-- `/kcd debug <spells|castbar|interrupt>` print to chat like everything else,
-- so the rule applies to them too. Under the mock `UnitExists` is false, so
-- these drive only the early-return branches — the deep section headers are
-- covered by the source scan below.

test("/kcd debug spells emits no line ending in ':'", function()
    assertNoTrailingColon(runVerb("debug spells"), "/kcd debug spells")
end)

test("/kcd debug castbar emits no line ending in ':'", function()
    assertNoTrailingColon(runVerb("debug castbar"), "/kcd debug castbar")
end)

test("/kcd debug interrupt emits no line ending in ':'", function()
    assertNoTrailingColon(runVerb("debug interrupt"), "/kcd debug interrupt")
end)

-- ── Source scan ─────────────────────────────────────────────────────────────

test("no addon source passes a ':'-terminated literal to a printer", function()
    -- The behavioural cases above can only reach code the mock can satisfy.
    -- This one reads the sources directly, so a violation in a branch the
    -- harness cannot enter (a dump that needs a live unit, a combat-only path)
    -- still fails the build. That is exactly how the five real violations in
    -- Castbar_Debug.lua / Compat.lua's DebugInterrupt survived the audit.
    --
    -- Matches a string literal ending in ':' immediately closing a call —
    -- `foo("header:")`. A colon MID-line (`"name: " .. value`) is fine and is
    -- not matched: the rule is about the last character a player reads.
    local DIRS = { "core", "modules", "settings", "defaults", "locales" }

    --- Every .lua under `dir`, via the TOC-independent filesystem listing so a
    --- file that exists but was never added to the TOC is still scanned.
    local function luaFiles(dir)
        local out = {}
        local pipe = io.popen('ls "' .. T.root .. "/" .. dir .. '"/*.lua 2>/dev/null')
        if not pipe then return out end
        for line in pipe:lines() do out[#out + 1] = line end
        pipe:close()
        return out
    end

    -- The one legitimate ':'-terminated literal closing a call is a SEPARATOR
    -- argument — `table.concat(parts, ":")`. It is distinguishable without
    -- guessing at the enclosing function (whose call may open several lines
    -- earlier): a separator is *exactly* ":" with nothing before the colon,
    -- whereas a chat header always carries text. So flag only a non-empty
    -- prefix, and the concat separator in IconGrid_Render's curveSignature
    -- stays legal without needing an exemption list.
    local offenders = {}
    for _, dir in ipairs(DIRS) do
        for _, path in ipairs(luaFiles(dir)) do
            local f = io.open(path, "r")
            if f then
                local n = 0
                for line in f:lines() do
                    n = n + 1
                    for prefix in line:gmatch('"([^"]*):"%s*%)') do
                        if prefix ~= "" then
                            offenders[#offenders + 1] =
                                path:gsub("^" .. T.root .. "/", "")
                                .. ":" .. n .. ' ("' .. prefix .. ':")'
                        end
                    end
                end
                f:close()
            end
        end
    end

    assertTrue(#offenders == 0,
        "string literal ending in ':' closes a call (slash-commands-§4) at: "
        .. table.concat(offenders, ", "))
end)
