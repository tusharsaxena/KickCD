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
-- RETAIL: identity. Resolve(id) and Family(id) answer `id`, IsAvailable(id) is
-- Compat.IsSpellAvailable(id) and IsUsable(id) is Compat.IsSpellUsable(id)'s first value: exactly
-- what each consumer asked before this file, so Retail behaves byte for byte as it did
-- (tests/test_spell_ranks.lua).
--
-- WOW FOREVER: every rank is its own spell id (defaults/SpellRanks_Forever.lua). A row stores the
-- family's rank-1 id; Resolve answers the HIGHEST rank the player or pet knows, which carries the
-- texture, the tooltip and the cooldown, or the stored id when no rank is known (so the row then
-- reads unavailable, as it always did). IsUsable answers whether ANY known rank is usable (critic
-- C3): a Shaman at 100 mana cannot cast Earth Shock rank 7 (450 mana) but rank 1 (30 mana) still
-- interrupts, and every rank shares the cooldown.
--
-- FORMS (MKF-KC-10, critic C4). For a family defaults/SpellRanks_Forever.lua declares in
-- NS.SpellOverridesForever (Feral Charge), Resolve answers the spell the player's form puts in the
-- base rank's place (C_Spell.GetOverrideSpell): the bear charge 16979 or the cat leap 414924. The
-- slot's availability stays the base rank's (IsAvailable), which the spellbook holds in every form,
-- and a replacement that never interrupts is never usable. The cache is re-read on
-- UPDATE_SHAPESHIFT_FORM, which Cooldowns and IconGrid register on WoW Forever only.
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

-- [family] = { base = the highest known rank (or the family), live = base or its form's override,
--              inert = the override never interrupts, known = { known rank ids, highest first } }
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

--- The spell a form puts in `base`'s place, for a family NS.SpellOverridesForever declares (Feral
--- Charge, MKF-KC-10), else `base`; and whether that replacement never interrupts.
local function overrideOf(family, base)
    local decl = type(NS.SpellOverridesForever) == "table" and NS.SpellOverridesForever[family]
    if not decl then return base, false end
    local id = NS.Compat.GetOverrideSpell and NS.Compat.GetOverrideSpell(base) or nil
    if not id then return base, false end
    return id, decl.notInterrupt ~= nil and decl.notInterrupt[id] == true
end

local function entryFor(family)
    local e = cache[family]
    if e then return e end
    local known = knownRanks(family)
    local base = known[1] or family
    local live, inert = overrideOf(family, base)
    e = { base = base, live = live, inert = inert, known = known }
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

--- The spell id to ask the client about for a stored row's cooldown, icon and tooltip: on WoW Forever
--- the highest known rank (the stored id when none is known), or the spell a form puts in its place
--- (Feral Charge); the id itself on Retail.
--- @param id any
--- @return any
function Ranks.Resolve(id)
    if type(id) ~= "number" or not forever() then return id end
    return entryFor(familyOf(id)).live
end

--- Whether the row's spell is available to the player right now: Compat.IsSpellAvailable of the
--- highest known rank on WoW Forever, asked live (a dismissed pet drops its spell mid-fight), and
--- of the BASE rank, never a form's override, which the spellbook does not hold (critic C4: the
--- slot stays in cat form); Compat.IsSpellAvailable(id) on Retail.
--- @param id any
--- @return boolean
function Ranks.IsAvailable(id)
    local Compat = NS.Compat
    if type(id) ~= "number" or not forever() then return Compat.IsSpellAvailable(id) end
    return Compat.IsSpellAvailable(entryFor(familyOf(id)).base)
end

--- Whether the row's spell is usable: on WoW Forever, when ANY known rank is (critic C3), and never
--- while a form puts a spell that does not interrupt in its place (cat Feral Charge); on Retail,
--- Compat.IsSpellUsable's first value, as before.
--- @param id any
--- @return boolean
function Ranks.IsUsable(id)
    local Compat = NS.Compat
    if type(id) ~= "number" or not forever() then return (Compat.IsSpellUsable(id)) end
    local e = entryFor(familyOf(id))
    if e.inert then return false end
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
