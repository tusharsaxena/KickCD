-- tests/test_client_shape.lua — the Retail · Forever shape (clients-§2, §4, §6; toc-file-§3).
--
-- WHAT IT PROVES. KickCD ships on Retail and WoW Forever from one codebase (the WoW Forever port,
-- Ka0sAddonsCommonTasks docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT, item MKF-KC-17). Its shape
-- is spread over files nothing else ties together: the TOC's Interface line, the README's badge
-- and supported-clients sentence, the CLAUDE.md gate, DEPENDENCIES.md, docs/testing.md, the
-- per-client feature table in docs/ARCHITECTURE.md and docs/forever-quirks.md. Each case here pins
-- one of them, and the last checks, on whichever kit profile runs, that each per-client feature is
-- present where it is declared and absent where it is not (clients-§6). LootHistory's
-- tests/test_client_shape.lua is the precedent.
--
-- It reads the checkout from disk, and fails rather than passes when a file cannot be opened.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local ROOT = T.root or "."

--- A file's contents with line endings normalized, or a failure.
local function read(rel)
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    if not fh then error("client shape: " .. rel .. " could not be opened", 2) end
    local body = fh:read("*a") or ""
    fh:close()
    return (body:gsub("\r\n", "\n"))
end

--- The TOC's `## Key: value` fields, by key.
local function tocFields()
    local out = {}
    for line in (read("KickCD.toc") .. "\n"):gmatch("([^\n]*)\n") do
        local k, v = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if k then out[k] = v end
    end
    return out
end

local FOREVER = T.mocks.WOW_PROJECT_CAMELOT ~= nil and T.mocks.WOW_PROJECT_ID == T.mocks.WOW_PROJECT_CAMELOT
local CLIENT = FOREVER and "forever" or "retail"

-- ── The TOC ─────────────────────────────────────────────────────────────────

test("Client shape: the TOC carries the Retail and WoW Forever numbers and no load-gating line", function()
    -- Retail · Forever (clients-§2, toc-file-§3): one unsuffixed TOC with both numbers, no gate.
    -- red under: the Retail number alone, or an AllowLoadGameType / ExcludeLoadGameType line
    local f = tocFields()
    assertEqual(f.Interface, "120105, 16001")
    assertTrue(f.AllowLoadGameType == nil and f.ExcludeLoadGameType == nil,
        "no load-gating line on a Retail · Forever addon")
end)

test("Client shape: the Forever number arms the kit's missing-globals scan for both clients", function()
    local CG = dofile(ROOT .. "/tests/_kit/client_globals.lua")
    -- red under: `## Interface: 120105` alone (the scan then checks the live set only)
    assertEqual(table.concat(CG.clientsFromToc(read("KickCD.toc")), ","), "live,forever")
end)

-- ── The root docs ───────────────────────────────────────────────────────────

test("Client shape: the README opens on the dual-client WoW badge and the supported-clients sentence", function()
    local readme = read("README.md")
    -- documentation-§1: both clients and both numbers on the badge, then one plain sentence at the
    -- start of the description. red under: the Midnight-only badge or the port-pending sentence
    assertTrue(readme:find("![WoW](https://img.shields.io/badge/WoW-Midnight_12.1.5_and_Forever_1.60.1-purple)",
        1, true) ~= nil, "the dual-client badge")
    local body = readme:match("\n\n([^!#\n][^\n]*)")
    assertTrue(body ~= nil and body:find("^Supports Retail and WoW Forever%. ") ~= nil, tostring(body))
    assertTrue(readme:find("support is planned", 1, true) == nil, "no port-pending sentence left")
end)

test("Client shape: the CLAUDE.md gate, DEPENDENCIES.md and docs/testing.md name both suite runs", function()
    -- clients-§6: a dual-client addon's suite runs under both kit profiles, so the gate names both.
    for _, rel in ipairs({ "CLAUDE.md", "DEPENDENCIES.md", "docs/testing.md" }) do
        local body = read(rel)
        assertTrue(body:find("lua tests/run.lua", 1, true) ~= nil, rel .. " names the Retail run")
        assertTrue(body:find("KA0S_KIT_CLIENT=forever lua tests/run.lua", 1, true) ~= nil,
            rel .. " names the WoW Forever run")
    end
    local deps = read("DEPENDENCIES.md")
    assertTrue(deps:find("## Interface: 120105, 16001", 1, true) ~= nil, "DEPENDENCIES.md quotes the TOC's two numbers")
    assertTrue(deps:find("World of Warcraft (Retail). Nothing else.", 1, true) == nil, "no Retail-only runtime line")
end)

-- ── The Forever docs ────────────────────────────────────────────────────────

test("Client shape: docs/forever-quirks.md carries the vendored Forever catalog, then its own section", function()
    -- forever-quirks-§1: every addon whose Clients include Forever carries the file, the vendored
    -- block first and the addon's own section after it. red under: no file, or the block missing
    local body = read("docs/forever-quirks.md")
    local open = body:find("<!%-%- BEGIN VENDORED: forever quirks catalog v%d+%.%d+%.%d+ %(source: WowAddonStandards%) %-%->")
    local close = body:find("<!-- END VENDORED -->", 1, true)
    assertTrue(open ~= nil and close ~= nil and open < close, "the vendored block's two markers, in order")
    local own = body:find("\n## KickCD%-specific quirks\n")
    assertTrue(own ~= nil and own > close, "the addon's own section follows the block")
    local arch = read("docs/ARCHITECTURE.md")
    assertTrue(arch:find("| `forever-quirks.md` | Present |", 1, true) ~= nil,
        "the documentation map lists forever-quirks.md as Present")
    assertTrue(arch:find("| `midnight-quirks.md` | Present |", 1, true) ~= nil,
        "a Retail · Forever addon keeps the Retail catalog too")
end)

-- Each per-client feature the port declared, by a token its row in the table must carry.
local FEATURE_TOKENS = {
    "CooldownManagerGated", "KnownOrListed", "defaults/Spells.lua", "defaults/Spells_Forever.lua",
    "RaceCastStoppersForever", "core/SpellRanks.lua", "UPDATE_SHAPESHIFT_FORM", "OneSpecPerClass",
    "BuildSpells", "UNIT_SPELLCAST_EMPOWER_", "KickOffGcd", "modules/SimScenario.lua",
    "C_SpellBook", "GetNumSpecializationsForClassID", "InterruptFlag", "modules/Probe.lua",
}

test("Client shape: the ARCHITECTURE per-client table names every declared feature", function()
    -- clients-§4: one row per feature that serves one client or has a shape per client, its client
    -- and the file that gates it.
    local arch = read("docs/ARCHITECTURE.md")
    local section = arch:match("\n### Per%-client features %(clients%-§4%)\n(.-)\n## ")
    assertTrue(section ~= nil, "docs/ARCHITECTURE.md has a `### Per-client features (clients-§4)` section")
    for _, token in ipairs(FEATURE_TOKENS) do
        assertTrue(section:find(token, 1, true) ~= nil, "the table names " .. token)
    end
    local rows, seen = 0, {}
    for client in section:gmatch("\n| [^\n]-| `(%a+)` | [^\n]-|") do
        rows = rows + 1
        seen[client] = true
        assertTrue(client == "retail" or client == "forever" or client == "both",
            "a Client cell takes the standard's tokens alone, not " .. client)
    end
    assertTrue(rows >= 12, "the table carries its rows (" .. rows .. ")")
    assertTrue(seen.retail and seen.forever and seen.both, "rows for retail, forever and both")
end)

-- ── Present where declared, absent where not (clients-§6) ───────────────────

test("Client shape: each per-client feature's answer is the running client's", function()
    -- red under: a WoW Forever build that answers a Retail-only feature present, or the reverse
    local inst = T.load(true, true)
    local NS = inst.NS
    local retail = CLIENT == "retail"
    assertEqual(NS.SpellInput.CooldownManagerGated(), retail, "the Cooldown Manager gate on " .. CLIENT)
    assertEqual(NS.DeliverEvent("UPDATE_SHAPESHIFT_FORM"), retail and 0 or 2,
        "the form-change rebuilds (Cooldowns, IconGrid) on " .. CLIENT)
    local empower = false
    for _, r in ipairs(NS.EventRoutes.filters) do
        if r.routes.UNIT_SPELLCAST_EMPOWER_START then empower = true end
    end
    assertEqual(empower, retail, "the empowered-cast routes on " .. CLIENT)
    assertEqual(NS.SimHost.KickOffGcd(6552), retail, "a kick off the GCD in the simulator on " .. CLIENT)
    assertEqual(NS.SimScenario.CLIENT, CLIENT, "the simulator's story is the running client's")
end)
