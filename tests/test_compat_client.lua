-- tests/test_compat_client.lua -- the client and the whole-name reads of the compat family
-- (core/CompatClient.lua; the WoW Forever port, MKF-KC-01; clients-§3, clients-§4,
-- forever-quirks-§4): IsForever, IsRetail, ClientKey and ForClient, then RegionalNames and
-- UnitCharacterName, each routed from the vendored LibKa0s-Compat-1.0 with a library-absent stub.
--
-- Every case runs on both kit profiles (`KA0S_KIT_CLIENT=forever lua tests/run.lua`) and picks its
-- expectation by the profile (clients-§6). Each arm is a real load: the library arm with the
-- vendored payload in front of the addon, the stub arm with LibKa0s absent (T.load's
-- `{ libFiles = {} }`), so the stub is exercised by a load rather than by a hand-stub after the fact.
-- A case that needs regional names sets RegionalUniqueNamesEnabled on its own mocks.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local PROFILE = os.getenv("KA0S_KIT_CLIENT") or "retail"
local FILE = "core/CompatClient.lua"
local MEMBERS = { "IsForever", "IsRetail", "ClientKey", "ForClient", "RegionalNames", "UnitCharacterName" }

--- Both arms, library first: `{ Compat, mocks, label }` each.
local function arms()
    local live = T.load(false, false)
    local stub = T.load(false, false, nil, { libFiles = {} })
    assertNil(stub.mocks.LibStub("LibKa0s-Compat-1.0", true), "the stub arm loaded the library")
    return { { live.NS.Compat, live.mocks, "library" }, { stub.NS.Compat, stub.mocks, "stub" } }
end

-- ── the client (clients-§3, §4) ───────────────────────────────────────────────────────────────

test("compat client: the six members are functions on NS.Compat on both arms", function()
    for _, arm in ipairs(arms()) do
        for _, k in ipairs(MEMBERS) do
            assertEqual(type(arm[1][k]), "function", arm[3] .. ": " .. k)
        end
    end
end)

test("compat client: ClientKey, IsForever and IsRetail answer the kit profile on both arms", function()
    for _, arm in ipairs(arms()) do
        local Compat, label = arm[1], arm[3]
        assertEqual(Compat.ClientKey(), PROFILE, label)
        assertEqual(Compat.IsForever(), PROFILE == "forever", label)
        assertEqual(Compat.IsRetail(), PROFILE == "retail", label)
    end
end)

test("compat client: ForClient(nil) is true, a declared client only on that client, an unknown token raises", function()
    for _, arm in ipairs(arms()) do
        local Compat, label = arm[1], arm[3]
        assertTrue(Compat.ForClient(nil), label)
        assertTrue(Compat.ForClient("both"), label)
        assertTrue(Compat.ForClient({ "retail", "forever" }), label)
        assertEqual(Compat.ForClient({ "retail" }), PROFILE == "retail", label)
        assertEqual(Compat.ForClient({ "forever" }), PROFILE == "forever", label)
        assertFalse(pcall(Compat.ForClient, { "classic" }), label .. ": an unknown token raises")
        assertFalse(pcall(Compat.ForClient, "retail"), label .. ": a bare client string raises")
    end
end)

test("compat client: a client that is neither answers nil and serves undeclared features only", function()
    for _, arm in ipairs(arms()) do
        local Compat, m, label = arm[1], arm[2], arm[3]
        m.WOW_PROJECT_ID, m.WOW_PROJECT_CAMELOT = 2, nil
        assertNil(Compat.ClientKey(), label)
        assertFalse(Compat.IsForever(), label)
        assertFalse(Compat.IsRetail(), label)
        assertTrue(Compat.ForClient(nil), label)
        assertFalse(Compat.ForClient({ "retail" }), label)
        -- No constants at all must not read as Forever (nil == nil).
        m.WOW_PROJECT_ID, m.WOW_PROJECT_MAINLINE = nil, nil
        assertFalse(Compat.IsForever(), label .. ": no constants is not Forever")
        assertNil(Compat.ClientKey(), label)
    end
end)

-- ── names (forever-quirks-§4) ─────────────────────────────────────────────────────────────────

test("compat client: RegionalNames follows RegionalUniqueNamesEnabled, false where it is absent", function()
    for _, arm in ipairs(arms()) do
        local Compat, m, label = arm[1], arm[2], arm[3]
        m.RegionalUniqueNamesEnabled = nil
        assertFalse(Compat.RegionalNames(), label .. ": absent")
        m.RegionalUniqueNamesEnabled = function() return false end
        assertFalse(Compat.RegionalNames(), label .. ": off")
        m.RegionalUniqueNamesEnabled = function() return true end
        assertTrue(Compat.RegionalNames(), label .. ": on")
    end
end)

test("compat client: UnitCharacterName is the whole name with regional names, name and realm without", function()
    for _, arm in ipairs(arms()) do
        local Compat, m, label = arm[1], arm[2], arm[3]
        m.UnitName = function(unit) if unit == "target" then return "Traxex", "Silentshot" end end
        m.RegionalUniqueNamesEnabled = function() return false end
        local name, realm = Compat.UnitCharacterName("target")
        assertEqual(name, "Traxex", label)
        assertEqual(realm, "Silentshot", label .. ": the second value is a realm without regional names")
        m.RegionalUniqueNamesEnabled = function() return true end
        name, realm = Compat.UnitCharacterName("target")
        assertEqual(name, "Traxex Silentshot", label .. ": the whole name, never the first word")
        assertNil(realm, label .. ": no realm with regional names")
        m.UnitName = function() return "Traxex", "" end
        name, realm = Compat.UnitCharacterName("target")
        assertEqual(name, "Traxex", label .. ": a name with no surname is the name alone")
        assertNil(realm, label)
        assertNil((Compat.UnitCharacterName(nil)), label .. ": no unit")
        m.UnitName = function() return nil end
        assertNil((Compat.UnitCharacterName("focus")), label .. ": no answer")
    end
end)

test("compat client: UnitCharacterName never joins a secret part", function()
    for _, arm in ipairs(arms()) do
        local Compat, m, label = arm[1], arm[2], arm[3]
        -- Two opaque stand-ins the mock's issecretvalue names as secrets; a join would raise on them.
        local trap = { __concat = function() error("secret value: joined") end }
        local secretName, secretSurname = setmetatable({}, trap), setmetatable({}, trap)
        m.issecretvalue = function(v) return v == secretName or v == secretSurname end
        m.RegionalUniqueNamesEnabled = function() return true end
        m.UnitName = function() return secretName, "Silentshot" end
        local name, realm = Compat.UnitCharacterName("target")
        assertTrue(name == secretName, label .. ": the secret name comes back untouched")
        assertNil(realm, label)
        m.UnitName = function() return "Traxex", secretSurname end
        name = Compat.UnitCharacterName("target")
        assertEqual(name, "Traxex", label .. ": a secret surname is dropped, never joined")
    end
end)

-- ── the boundary (clients-§3) ─────────────────────────────────────────────────────────────────

test("compat client: no shipped file but core/CompatClient.lua reads a project id or the regional-names switch", function()
    -- red under: a WOW_PROJECT_ read, or a RegionalUniqueNamesEnabled read, anywhere else in the TOC
    local offenders = {}
    for _, path in ipairs(T.tocFiles) do
        if path ~= FILE and path:find("%.lua$") and not path:find("^libs/") then
            local fh = assert(io.open(T.root .. "/" .. path, "r"))
            local src = fh:read("*a")
            fh:close()
            for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                local code = line:gsub("%-%-.*$", "")
                if code:find("WOW_PROJECT_", 1, true) or code:find("RegionalUniqueNamesEnabled", 1, true) then
                    offenders[#offenders + 1] = path .. ": " .. line
                end
            end
        end
    end
    assertEqual(table.concat(offenders, " | "), "")
end)

test("compat client: the boundary check is falsifiable, a planted read is found", function()
    local code = ("local x = _G.WOW_PROJECT_ID -- planted"):gsub("%-%-.*$", "")
    assertTrue(code:find("WOW_PROJECT_", 1, true) ~= nil)
    local comment = ("-- WOW_PROJECT_ID in prose"):gsub("%-%-.*$", "")
    assertNil(comment:find("WOW_PROJECT_", 1, true), "a comment is not a read")
end)

test("compat client: core/CompatClient.lua loads straight after core/Compat.lua and before core/SimSetup.lua", function()
    local at
    for i, p in ipairs(T.tocFiles) do if p == "core/Compat.lua" then at = i end end
    assertTrue(at ~= nil, "core/Compat.lua is not in KickCD.toc")
    assertEqual(T.tocFiles[at + 1], FILE)
    assertEqual(T.tocFiles[at + 2], "core/SimSetup.lua")
end)
