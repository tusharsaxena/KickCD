-- tests/wow_mock_forever.lua -- the WoW Forever world KickCD's mock does not otherwise model
-- (MKF-KC-02; the Forever port design 3.2, critic C5; Ka0sAddonsCommonTasks
-- docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT).
--
-- WHY. The kit's `forever` profile changes the project constants, the build and five globals, and
-- nothing else: under it tests/wow_mock.lua still serves a Retail Hunter at Retail spec ids, thirteen
-- classes, the deprecated spellbook shims always true, the bare spec-count global and a secret test
-- that never says yes. Every Forever defect the port research found passes in that world unnoticed.
-- This file is the world those defects fail in, so a later test fails for the right reason.
--
-- WHAT IT MODELS, each from Forever 1.60.1.71037 (DB2 and the generated API docs, the research's
-- factcheck.md):
--   * nine classes at their real ids (1-5, 7, 8, 9, 11) and ONE spec per class at its real id, named
--     for the class (ChrSpecialization: 1482 Mage ... 1491 Warrior), role DAMAGER, no icon (the
--     runtime answer measured on 70862 carries none);
--   * the spec count only as the namespaced member C_SpecializationInfo.GetNumSpecializationsForClassID,
--     the bare global absent; C_SpecializationInfo.GetAllClassIDs, which is Forever's alone;
--   * GetNumClasses answering 9 with GetClassInfo taking a class ID: how the two combine on Forever is
--     UNKNOWN (factcheck 24), so the mock takes the shape that loses Druid (11) to a 1..count loop;
--   * C_SpellBook with ranked known sets: every rank is its own spell id, and a rank is known only
--     when the case teaches it (`mocks.__learn`), on the player's bank or the pet's;
--   * the deprecation shims absent (IsPlayerSpell, IsSpellKnown, IsSpellKnownOrOverridesKnown);
--   * no global cooldown spell: 61304 has no row in Forever's data (factcheck 60);
--   * regional names: a character is "First Surname" and UnitName's second value is the surname;
--   * typed secrets (`typedSecrets` below), which the world installs and a Retail case may too.
--
-- USE. tests/run.lua's loader takes `{ world = "forever" }`, stamps the kit's forever profile on the
-- mock set whatever KA0S_KIT_CLIENT says, applies this world, then the case's own mutate hook. So a
-- case written against the world runs the same on both kit profiles. The shared instance does not
-- use the world until the addon is ready for it (the seeds, the rank resolver and the class lists
-- are later items of the port); until then the world is opt-in, case by case.
--
-- SHAPE. Returns `{ apply = function(mocks, Kit) end, typedSecrets = function(mocks, Kit) end,
-- CLASSES = ... }`. Loaded once by tests/run.lua with loadfile-and-call, never require.

local BANK_PLAYER, BANK_PET = 0, 1

-- [classID] = { classFile, name, specID } (DB2 ChrClasses and ChrSpecialization, 71037).
local CLASSES = {
    [1]  = { "WARRIOR", "Warrior", 1491 },
    [2]  = { "PALADIN", "Paladin", 1486 },
    [3]  = { "HUNTER",  "Hunter",  1485 },
    [4]  = { "ROGUE",   "Rogue",   1488 },
    [5]  = { "PRIEST",  "Priest",  1487 },
    [7]  = { "SHAMAN",  "Shaman",  1489 },
    [8]  = { "MAGE",    "Mage",    1482 },
    [9]  = { "WARLOCK", "Warlock", 1490 },
    [11] = { "DRUID",   "Druid",   1484 },
}
local CLASS_IDS = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }

local function classIDFor(classFile)
    for id, row in pairs(CLASSES) do
        if row[1] == classFile then return id end
    end
    return nil
end

--- Typed secrets: a Kit.secret wrapper whose `type()` is the underlying value's, as the client's
--- secrets are (the standard's client-quirks: a secret's type is its underlying type), and an
--- `issecretvalue` that says yes for one. The kit's wrapper alone answers "table", so code that
--- dispatches on type() before it asks IsSecret looks safe in a suite and raises in the client.
--- Installed on `mocks`, so it reaches every chunk loaded under this mock set and nothing else.
local function typedSecrets(mocks, Kit)
    local rawType = type
    mocks.type = function(v)
        if Kit.isSecret(v) then return rawType(Kit.reveal(v)) end
        return rawType(v)
    end
    mocks.issecretvalue = function(v) return Kit.isSecret(v) end
    mocks.__secret = Kit.secret
end

--- The spec rows: one per class, at its real id.
local function specInfo(classID, index)
    local row = CLASSES[classID]
    if not row or index ~= 1 then return nil end
    return row[3], row[2], "", nil, "DAMAGER"
end

local function installClasses(mocks, world)
    mocks.GetNumClasses = function() return #CLASS_IDS end
    mocks.GetClassInfo = function(classID)
        local row = CLASSES[classID]
        if not row then return nil end
        return row[2], row[1], classID
    end
    mocks.UnitClass = function()
        local row = CLASSES[world.classID]
        return row[2], row[1], world.classID
    end
    mocks.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function(index) return specInfo(world.classID, index or 1) end,
        GetNumSpecializationsForClassID = function(classID) return CLASSES[classID] and 1 or 0 end,
        GetAllClassIDs = function()
            local out = {}
            for i, id in ipairs(CLASS_IDS) do out[i] = id end
            return out
        end,
    }
    mocks.GetSpecializationInfoForClassID = function(classID, index) return specInfo(classID, index) end
    mocks.GetNumSpecializationsForClassID = nil
    --- Make the simulated player a `classFile` character (its one spec follows).
    mocks.__setForeverClass = function(classFile)
        local id = classIDFor(classFile)
        if not id then error("wow_mock_forever: no Forever class " .. tostring(classFile), 2) end
        world.classID = id
    end
end

local function installSpellBook(mocks, world)
    world.known = { [BANK_PLAYER] = {}, [BANK_PET] = {} }
    local function bankOf(bank) return bank == nil and BANK_PLAYER or bank end
    local function knows(id, bank)
        local set = world.known[bankOf(bank)]
        return set ~= nil and set[id] == true
    end
    mocks.C_SpellBook = {
        IsSpellKnown = function(id, bank) return knows(id, bank) end,
        IsSpellInSpellBook = function(id, bank) return knows(id, bank) end,
    }
    --- Teach the listed spell ids (each rank its own id) on `bank` (0 the player's, 1 the pet's).
    mocks.__learn = function(ids, bank)
        for _, id in ipairs(ids) do world.known[bankOf(bank)][id] = true end
    end
    --- Forget the listed ids on `bank`, as a dismissed pet or a respec would.
    mocks.__unlearn = function(ids, bank)
        for _, id in ipairs(ids) do world.known[bankOf(bank)][id] = nil end
    end
    mocks.IsPlayerSpell = nil
    mocks.IsSpellKnown = nil
    mocks.IsSpellKnownOrOverridesKnown = nil
end

local function installNoGcdSpell(mocks)
    local spell = mocks.C_Spell
    local cooldown, info = spell.GetSpellCooldown, spell.GetSpellInfo
    spell.GetSpellCooldown = function(id)
        if id == 61304 then return nil end
        return cooldown(id)
    end
    spell.GetSpellInfo = function(id)
        if id == 61304 then return nil end
        return info(id)
    end
end

local function installNames(mocks)
    mocks.RegionalUniqueNamesEnabled = function() return true end
    mocks.UnitName = function() return "Mock", "Mockwood" end
    mocks.UnitNameUnmodified = mocks.UnitName
end

--- Apply the WoW Forever world to a freshly built mock set. `Kit` is the test kit (its secrets).
local function apply(mocks, Kit)
    local world = { classID = 3 }
    mocks.__foreverWorld = world
    installClasses(mocks, world)
    installSpellBook(mocks, world)
    installNoGcdSpell(mocks)
    installNames(mocks)
    typedSecrets(mocks, Kit)
    return world
end

return {
    apply = apply,
    typedSecrets = typedSecrets,
    CLASSES = CLASSES,
    CLASS_IDS = CLASS_IDS,
    BANK_PLAYER = BANK_PLAYER,
    BANK_PET = BANK_PET,
}
