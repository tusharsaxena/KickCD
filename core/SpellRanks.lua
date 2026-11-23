-- core/SpellRanks.lua
-- See docs/module-map.md.
--
-- THE ONE RESOLVER from a stored list row to the spell id the client is asked about (the WoW
-- Forever port, Ka0sAddonsCommonTasks docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT, MKF-KC-09;
-- clients-§10). Every consumer of a row's spell goes through it: the cooldown poll and the ready
-- flag (modules/Cooldowns.lua), the icon, the dedupe and the ticker (modules/IconGrid*.lua), the
-- tooltip, the simulator's spells (modules/Sim.lua), the Spells page's name, icon, tooltip and
-- known mark (settings/Spells_Rows.lua), the diagnostics list (modules/Diagnostics.lua), and the
-- writer, which stores any rank as its family (core/Database.lua AddSpell).
--
-- RETAIL: identity. Resolve(id) and Family(id) answer `id`, and IsUsable(id) is
-- Compat.IsSpellUsable(id)'s first value: exactly what each consumer asked before this file, so
-- Retail behaves byte for byte as it did (tests/test_spell_ranks.lua).
--
-- WOW FOREVER: every rank is its own spell id (defaults/SpellRanks_Forever.lua). A row stores the
-- family's rank-1 id; Resolve answers the HIGHEST rank the player or pet knows, which carries the
-- texture, the tooltip and the cooldown, or the stored id when no rank is known (so the row then
-- reads unavailable, as it always did). IsUsable answers whether ANY known rank is usable (critic
-- C3): a Shaman at 100 mana cannot cast Earth Shock rank 7 (450 mana) but rank 1 (30 mana) still
-- interrupts, and every rank shares the cooldown.
--
-- THE CACHE. The known set is read once per family and kept until Invalidate, because the poll and
-- the 0.1 s ticker ask on every pass. Every rebuild path invalidates first (Cooldowns:Rebuild,
-- IconGrid:BuildActiveList, the Spells page's list), and each runs on SPELLS_CHANGED,
-- TRAIT_CONFIG_UPDATED, a spec change and the login. A path that only reads (the simulator, the
-- diagnostics report) takes the cache as it stands, built on first use.
--
-- Not an NS.Compat member: the client reads it makes go through NS.Compat at call time, so the
-- simulator's seam (core/SimSetup.lua) answers them as it answers every other read.

local _, NS = ...

local Ranks = {}
NS.SpellRanks = Ranks

-- [family] = { live = id, known = { rank ids the player knows, highest first } }
local cache = {}
-- [rank id] = family; built from NS.SpellRanksForever on first use.
local byRank

local function forever()
    local Compat = NS.Compat
    return Compat ~= nil and Compat.IsForever ~= nil and Compat.IsForever() == true
end

local function rankIndex()
    if byRank then return byRank end
    local families = NS.SpellRanksForever
    local index = {}
    if type(families) ~= "table" then return index end
    for family, ranks in pairs(families) do
        for _, id in ipairs(ranks) do index[id] = family end
    end
    byRank = index
    return index
end

local function familyOf(id)
    return rankIndex()[id] or id
end

local function ranksOf(family)
    local families = NS.SpellRanksForever
    return type(families) == "table" and families[family] or nil
end

--- The ranks of `family` the player or pet knows, highest first.
local function knownRanks(family)
    local Compat = NS.Compat
    local ranks = ranksOf(family) or { family }
    local known = {}
    for i = #ranks, 1, -1 do
        if Compat.IsSpellAvailable(ranks[i]) then known[#known + 1] = ranks[i] end
    end
    return known
end

local function entryFor(family)
    local e = cache[family]
    if e then return e end
    local known = knownRanks(family)
    e = { live = known[1] or family, known = known }
    cache[family] = e
    return e
end

--- The family key a spell id is stored under: its rank-1 id on WoW Forever, the id itself on
--- Retail and for any spell that is not a ranked family.
--- @param id any
--- @return any
function Ranks.Family(id)
    if type(id) ~= "number" or not forever() then return id end
    return familyOf(id)
end

--- The spell id to ask the client about for a stored row: the highest known rank on WoW Forever
--- (the stored id when none is known), the id itself on Retail.
--- @param id any
--- @return any
function Ranks.Resolve(id)
    if type(id) ~= "number" or not forever() then return id end
    return entryFor(familyOf(id)).live
end

--- Whether the row's spell is usable: on WoW Forever, when ANY known rank is (critic C3); on
--- Retail, Compat.IsSpellUsable's first value, as before.
--- @param id any
--- @return boolean
function Ranks.IsUsable(id)
    local Compat = NS.Compat
    if type(id) ~= "number" or not forever() then return (Compat.IsSpellUsable(id)) end
    local e = entryFor(familyOf(id))
    if #e.known == 0 then return (Compat.IsSpellUsable(e.live)) end
    for _, rank in ipairs(e.known) do
        if Compat.IsSpellUsable(rank) then return true end
    end
    return false
end

--- Drop the cached known sets: the next Resolve or IsUsable reads the spellbook again.
function Ranks.Invalidate()
    for k in pairs(cache) do cache[k] = nil end
end

--- The ranks the cache holds for a stored id (highest first), for the diagnostics and the tests;
--- nil on Retail.
--- @param id number
--- @return table|nil
function Ranks.KnownRanks(id)
    if type(id) ~= "number" or not forever() then return nil end
    return entryFor(familyOf(id)).known
end
