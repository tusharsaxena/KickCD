-- defaults/SpellRanks_Forever.lua
-- WoW Forever's rank families (the Forever port, Ka0sAddonsCommonTasks
-- docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT, MKF-KC-09; clients-§10): on Forever every rank of
-- an ability is its own spell id, and a stored list row is the family's RANK-1 id. This table lists
-- each family's ranks, lowest first, so core/SpellRanks.lua can answer the highest rank the player
-- or the pet knows.
--
-- WHERE IT COMES FROM. The `ranks` of every candidate in the frozen 1.60.1.71037 seed run
-- (docs/seed-research/2026-11-23-forever/candidates.json), accepted and rejected alike, so a spell
-- a player adds by hand ranks the same way a default does. Only families with more than one rank
-- are listed: a single-rank spell is its own family. The run built the families from the class
-- skill line, the name and the rank subtext, never the name alone (same-name unreachable clones
-- exist: Kick 1775 and 3467 are not Kick ranks), and Polymorph's Turtle and Pig variants are not
-- ranks. tests/test_spell_ranks.lua holds this table to candidates.json id for id.
--
-- WHO READS THIS. core/SpellRanks.lua, and only on WoW Forever. Retail never consults it.

local _, NS = ...

NS.SpellRanksForever = {
    -- WARRIOR
    [72]    = { 72, 1671, 1672 },                                    -- Shield Bash
    [100]   = { 100, 6178, 11578 },                                  -- Charge
    [6552]  = { 6552, 6554 },                                        -- Pummel
    [20252] = { 20252, 20616, 20617 },                               -- Intercept
    -- PALADIN
    [853]   = { 853, 5588, 5589, 10308 },                            -- Hammer of Justice
    [2812]  = { 2812, 10318 },                                       -- Holy Wrath
    [2878]  = { 2878, 5627, 10326 },                                 -- Turn Undead
    -- HUNTER
    [1499]  = { 1499, 14310, 14311 },                                -- Freezing Trap
    [1513]  = { 1513, 14326, 14327 },                                -- Scare Beast
    -- ROGUE
    [408]   = { 408, 8643 },                                         -- Kidney Shot
    [1766]  = { 1766, 1767, 1768, 1769 },                            -- Kick
    [1776]  = { 1776, 1777, 8629, 11285, 11286 },                    -- Gouge
    -- PRIEST
    [605]   = { 605, 10911, 10912 },                                 -- Mind Control
    [8122]  = { 8122, 8124, 10888, 10890 },                          -- Psychic Scream
    -- SHAMAN
    [8042]  = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 },       -- Earth Shock
    -- MAGE
    [118]   = { 118, 12824, 12825, 12826 },                          -- Polymorph
    -- WARLOCK
    [5484]  = { 5484, 17928 },                                       -- Howl of Terror
    [5782]  = { 5782, 6213, 6215 },                                  -- Fear
    [6789]  = { 6789, 17925, 17926 },                                -- Death Coil
    [19244] = { 19244, 19647 },                                      -- Spell Lock (Felhunter)
    -- DRUID
    [2637]  = { 2637, 18657, 18658 },                                -- Hibernate
    [5211]  = { 5211, 6798, 8983 },                                  -- Bash
    [9005]  = { 9005, 9823, 9827 },                                  -- Pounce
}
