-- tests/test_sample_names.lua — one source of sample names (FB2-KC-01 of Ka0sAddonsCommonTasks
-- docs/2026-11-24-FEEDBACK_BATCH, decision D1; LibKa0s#104; preview-mode, standard v2.120.0).
--
-- The owner, 2026-11-24: "adopt the predefined test mode names consistently across all addon's
-- test/sim modes". Every named sample person KickCD draws (today the simulator's party) is read from
-- LibKa0s-Sim-1.0, Sim.Sample() for the five protagonists and Sim.SampleCrowd() for anyone beyond
-- them, never a list or a literal of the addon's own. modules/SimScenario.lua kept a fallback copy
-- of the library's rows and picked its kickers by typed name keys until this item.
--
-- A SOURCE SCAN over the addon's own shipped files (the TOC's, libs/ dropped; tests/ is not shipped
-- and may name the people it asserts on). It reads string literals only: a comment may name a
-- sample person in prose, but a name inside quotes is one the code would draw. A name is a word
-- starting Sample or Mock (any case) followed by at least two letters, so "Sample" and "Mock" as
-- plain words stay legal.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

--- The string literals on `line` after its comment is cut: an array of their contents.
local function literals(line)
    local out = {}
    local code = line:gsub("%[=*%[.-%]=*%]", function(s) out[#out + 1] = s; return '""' end)
    code = code:gsub('\\"', "")
    -- Cut the comment only outside a string: strip the strings first, then find `--`.
    local masked = code:gsub('"[^"]*"', function(s) return ("\0"):rep(#s) end)
        :gsub("'[^']*'", function(s) return ("\0"):rep(#s) end)
    local cut = masked:find("--", 1, true)
    if cut then code = code:sub(1, cut - 1) end
    for s in code:gmatch('"([^"]*)"') do out[#out + 1] = s end
    for s in code:gmatch("'([^']*)'") do out[#out + 1] = s end
    return out
end

--- The sample-shaped names inside the literals of `line`.
local function namesOn(line)
    local found = {}
    for _, s in ipairs(literals(line)) do
        for word in s:gmatch("%a+") do
            local low = word:lower()
            if low:match("^sample%a%a") or low:match("^mock%a%a") then found[#found + 1] = word end
        end
    end
    return found
end

--- Every offender in the addon's own TOC files, as "path:line: word".
local function offenders()
    local out = {}
    for _, rel in ipairs(T.tocFiles) do
        if rel:sub(-4) == ".lua" and rel:sub(1, 5) ~= "libs/" then
            local fh = io.open(T.root .. "/" .. rel, "r")
            if fh then
                local n = 0
                for line in fh:lines() do
                    n = n + 1
                    for _, word in ipairs(namesOn(line)) do out[#out + 1] = rel .. ":" .. n .. ": " .. word end
                end
                fh:close()
            end
        end
    end
    return out
end

test("sample names: no Sample/Mock name literal in the addon's own shipped code", function()
    -- red under: modules/SimScenario.lua's SAMPLE_COPY and its typed kicker keys ("sampleblade", ...)
    local bad = offenders()
    assertEqual(#bad, 0, "sample names typed outside the library:\n  " .. table.concat(bad, "\n  "))
end)

test("sample names: the scan is falsifiable (a planted literal is found, prose and plain words are not)", function()
    assertEqual(table.concat(namesOn('local x = { name = "Mockflame" }'), ","), "Mockflame")
    assertEqual(table.concat(namesOn("first = 'sampleblade', -- x"), ","), "sampleblade")
    assertEqual(#namesOn("-- Mockflame and Mockshield kick"), 0, "a comment is prose")
    assertEqual(#namesOn('L["Sample"] = "Mock"'), 0, "the bare words Sample and Mock are legal")
    assertEqual(#namesOn('local s = "a" -- "Samplehunter"'), 0, "a quoted name inside a comment is prose")
end)

test("sample names: the scan reads the addon's own files, the simulator's party among them", function()
    local own, party = 0, false
    for _, rel in ipairs(T.tocFiles) do
        if rel:sub(-4) == ".lua" and rel:sub(1, 5) ~= "libs/" then
            own = own + 1
            if rel == "modules/SimScenario.lua" then party = true end
        end
    end
    assertTrue(own > 10, "the TOC lists too few of the addon's own files: " .. own)
    assertTrue(party, "modules/SimScenario.lua is not among the scanned files")
end)
