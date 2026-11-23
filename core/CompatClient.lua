-- core/CompatClient.lua -- which client this is, and a unit's whole character name (the WoW
-- Forever port, Ka0sAddonsCommonTasks docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT; clients-§3,
-- clients-§4, forever-quirks-§4).
--
-- WHY HERE. The client questions (IsForever, IsRetail, ClientKey, ForClient) and the name readers
-- (RegionalNames, UnitCharacterName) are LibKa0s-Compat-1.0 members, vendored in
-- libs/LibKa0s/Compat.lua, so this file routes them, each with its library-absent stub, rather than
-- writing them again. It is a sibling of core/Compat.lua so the spell, cast and spec shims stay one
-- topic there. BankLedger's and LootHistory's core/CompatClient.lua have the same shape.
--
-- THE RULE (clients-§3). This is the ONE file in the addon that reads a WOW_PROJECT_* constant or
-- RegionalUniqueNamesEnabled; every other file asks NS.Compat. A feature's presence on a client is a
-- declaration through ForClient (clients-§4), never feature detection. tests/test_compat_client.lua
-- holds every other shipped file to it.
--
-- THE STUBS are the library's bodies, globals read at call time, so an install missing LibKa0s
-- answers the client questions exactly as one with it. A secret name part is never joined.
--
-- PURE to the simulator's seam (core/SimSetup.lua): which client this is and how it spells a name
-- are facts of the install, not of a simulated world.
--
-- LOAD-BEARING POSITION: straight after core/Compat.lua, which creates NS.Compat, and before
-- core/SimSetup.lua, which wraps every NS.Compat member at load (Sim-1.0 host contract H2).

local _, NS = ...

local Compat = NS.Compat
local CompatLib = LibStub and LibStub("LibKa0s-Compat-1.0", true)

-- ── the client (clients-§3) ───────────────────────────────────────────────────────────────────
-- The nil guard keeps a client with neither constant from reading as Forever (nil == nil).

local function isForeverStub()
    local camelot = _G.WOW_PROJECT_CAMELOT
    return camelot ~= nil and _G.WOW_PROJECT_ID == camelot
end

local function isRetailStub()
    local mainline = _G.WOW_PROJECT_MAINLINE
    return mainline ~= nil and _G.WOW_PROJECT_ID == mainline and not isForeverStub()
end

local function clientKeyStub()
    if isForeverStub() then return "forever" end
    if isRetailStub() then return "retail" end
    return nil
end

local CLIENT_TOKENS = { retail = true, forever = true, both = true }

local function forClientStub(clients)
    if clients == nil or clients == "both" then return true end
    if type(clients) ~= "table" then error('ForClient: unknown client "' .. tostring(clients) .. '"', 2) end
    for _, token in ipairs(clients) do
        if not CLIENT_TOKENS[token] then error('ForClient: unknown client "' .. tostring(token) .. '"', 2) end
    end
    local key = clientKeyStub()
    for _, token in ipairs(clients) do
        if token == "both" or token == key then return true end
    end
    return false
end

--- Whether this is a WoW Forever client. Exactly one boolean.
Compat.IsForever = CompatLib and CompatLib.IsForever or isForeverStub

--- Whether this is a Retail client (the mainline project id and NOT Forever). Exactly one boolean.
Compat.IsRetail = CompatLib and CompatLib.IsRetail or isRetailStub

--- "retail", "forever", or nil when the project constants say neither: the key a per-client table
--- is picked by, once (clients-§5).
Compat.ClientKey = CompatLib and CompatLib.ClientKey or clientKeyStub

--- Whether a `clients` declaration (nil, "both", or an array of "retail" / "forever" / "both")
--- includes this client; nil means both (clients-§4). An unknown token raises on any client.
Compat.ForClient = CompatLib and CompatLib.ForClient or forClientStub

-- ── the character's name (forever-quirks-§4) ──────────────────────────────────────────────────

--- Whether character names are unique per region: true on WoW Forever, where a character is its
--- first name and surname together and carries no realm. False where the switch is absent.
--- @return boolean
Compat.RegionalNames = CompatLib and CompatLib.RegionalNames or function()
    local fn = _G.RegionalUniqueNamesEnabled
    return fn ~= nil and fn() == true
end

local function unitCharacterNameStub(unit)
    local read = _G.UnitName
    if not (unit and read) then return nil, nil end
    local name, second = read(unit)
    if name == nil then return nil, nil end
    if not Compat.RegionalNames() then return name, second end
    if Compat.IsSecret(name) or Compat.IsSecret(second) or type(second) ~= "string" or second == "" then
        return name, nil
    end
    return name .. " " .. second, nil
end

--- A unit's whole character name and its realm: "Traxex Silentshot" and a nil realm with regional
--- names (WoW Forever, where UnitName's second value is the SURNAME); UnitName's own name and realm
--- otherwise. Nil, nil for no unit or no answer. A secret part is never joined: the name comes back
--- untouched with a nil realm, so a caller still tests it with Compat.IsSecret before any compare.
--- @param unit string
--- @return any name, string|nil realm
Compat.UnitCharacterName = CompatLib and CompatLib.UnitCharacterName or unitCharacterNameStub
