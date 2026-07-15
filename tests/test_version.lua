-- tests/test_version.lua — the `/kcd version` verb (slash-commands-§3).
--
-- Every Ka0s addon MUST answer "what version am I running?" identically: a
-- standalone `version` verb that prints `<tag> v<version>` on its OWN line, so
-- the answer stays greppable without parsing the /kcd help header. The version
-- is read from the TOC manifest (C_AddOns.GetAddOnMetadata) with the in-code
-- NS.VERSION stamp as fallback, so it can't drift from the packaged build.
-- Under the headless mock the metadata API is absent, so these cases also
-- pin the fallback path.
local T = _G.KICKCD_TEST
local test, assertTrue, assertEqual = T.test, T.assertTrue, T.assertEqual
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

test("`version` is a registered COMMANDS verb (slash-commands-§3)", function()
    local found
    for _, entry in ipairs(NS.COMMANDS) do
        if entry[1] == "version" then found = entry end
    end
    assertTrue(found ~= nil, "COMMANDS must carry a standalone `version` verb")
    assertTrue(type(found[2]) == "string" and found[2] ~= "", "verb needs a description")
    assertTrue(type(found[3]) == "function", "verb needs a handler")
end)

test("`/kcd version` prints v<version> on exactly one line", function()
    local lines = runVerb("version")
    assertEqual(#lines, 1, "version must answer on a single line")
    assertTrue(lines[1]:find("v" .. NS.VERSION, 1, true) ~= nil,
        "line must contain v" .. NS.VERSION .. ", got: " .. tostring(lines[1]))
end)

test("`version` falls back to the NS.VERSION stamp when TOC metadata is absent", function()
    -- The mock exposes no C_AddOns.GetAddOnMetadata, so the verb must fall back
    -- to the in-code stamp and still emit a semver-shaped line.
    local lines = runVerb("version")
    assertTrue(lines[1]:match("v%d+%.%d+%.%d+") ~= nil,
        "must print a semver-shaped version, got: " .. tostring(lines[1]))
end)
