-- tests/test_slash_style.lua — chat-line style rules for slash output.
--
-- slash-commands-§4: NO chat line ends in a trailing `:`. A list is introduced
-- by its header text alone, never by punctuation. The 2026-07-18 standards
-- audit caught three violations (KCD-25) — the `/kcd help` header plus the
-- `debug` and `spells` sub-headers. Those were fixed in code; this suite is the
-- regression guard that stops the next help-text edit reintroducing one
-- silently, which is the half of KCD-25 that never got written at the time.
--
-- Drives the real verbs rather than asserting against string literals, so a new
-- sub-header added anywhere under these three paths is covered automatically.
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
