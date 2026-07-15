-- tests/test_list_mode.lua — the runner's non-executing `--list` inventory mode
-- (testing-§5). Shells out to a child `lua tests/run.lua --list` and asserts the
-- generated Markdown contract. Safe from recursion: in --list mode `test()` only
-- records cases, so these io.popen bodies never run inside the child.
local T = _G.KICKCD_TEST
local test, assertTrue, assertEqual = T.test, T.assertTrue, T.assertEqual

--- Run the runner in --list mode and capture its stdout.
local function listOutput()
    local p = assert(io.popen("lua " .. T.root .. "/tests/run.lua --list", "r"))
    local out = p:read("*a")
    p:close()
    return out
end

test("--list emits a generated '# Test Cases' inventory header + regen note", function()
    local out = listOutput()
    assertTrue(out:match("^# Test Cases"), "must open with the '# Test Cases' header")
    assertTrue(out:find("do not hand%-edit", 1, false),
        "must carry a 'do not hand-edit' note")
    assertTrue(out:find("lua tests/run.lua --list", 1, true),
        "regen note must name the exact command")
end)

test("--list stdout is inventory-only, no run output", function()
    local out = listOutput()
    -- Key on run-only markers (the banner + the ANSI PASS glyph), not the bare
    -- word "PASS" — a case name may legitimately contain it (this one does).
    assertTrue(not out:find("KickCD test harness", 1, true),
        "list mode must not print the harness banner")
    assertTrue(not out:find("\27[32mPASS", 1, true), "list mode must not run tests")
    assertTrue(not out:find("\n-------------------\n", 1, true),
        "list mode must not print the run tail")
end)

test("--list per-suite header counts match their bullet counts", function()
    local out = listOutput()
    local seen = 0
    for suite, n in out:gmatch("### ([%w_%.]+) %((%d+)%)") do
        -- Slice this section: from its header to the next '### ' or '## Totals'.
        local hdr = "### " .. suite:gsub("%.", "%%.") .. " %(" .. n .. "%)"
        local s = out:find(hdr)
        local rest = out:sub(s)
        local nextHdr = rest:find("\n###? ", 2)
        local section = nextHdr and rest:sub(1, nextHdr) or rest
        local bullets = select(2, section:gsub("\n%- ", ""))
        assertEqual(bullets, tonumber(n),
            "suite " .. suite .. " header says " .. n .. " but has " .. bullets .. " bullets")
        seen = seen + 1
    end
    assertTrue(seen > 0, "must emit at least one '### <suite>.lua (N)' section")
end)

test("--list Totals row equals the grand total of bullets", function()
    local out = listOutput()
    local total = out:match("| %*%*Total%*%* | %*%*(%d+)%*%* |")
    assertTrue(total ~= nil, "must end with a | **Total** | **N** | row")
    local bullets = select(2, out:gsub("\n%- ", ""))
    assertEqual(tonumber(total), bullets,
        "Totals row (" .. tostring(total) .. ") must equal bullet count (" .. bullets .. ")")
end)
