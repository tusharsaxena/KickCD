-- defaults/Spells_Forever.lua
-- WoW Forever's default cast-stopper lists (the Forever port, Ka0sAddonsCommonTasks
-- docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT; clients-§5): Forever's own lists, derived from
-- Forever's own DB2 tables, never by filtering defaults/Spells.lua (id 99 is Demoralizing Roar on
-- Forever, 23920 is unlearnable, 19647 is only rank 2 of Spell Lock).
--
-- Same shape and rules as defaults/Spells.lua: per class and spec, index 1 is the primary interrupt
-- (or, where the class has no kick, its best cast-stopping CC), indices 2..N are PvE-biased secondary
-- cast-stoppers in priority order, and the categories are the same closed set. Forever has ONE spec
-- per class, so there is one list per class (owner ruling R6), keyed through Const.SPEC_FOREVER.
-- One entry per ability, at its rank-1 id: every rank is its own spell id on Forever.
--
-- Written by tools/seeds/seeds.py --flavor forever (docs/validate-seeds.md, `## Flavor: forever`),
-- which writes its ruled changes here; the rulings are tools/seeds/rulings_forever.json, the
-- evidence docs/seed-research/. Seeded against wago.tools WoW Forever build 1.60.1.71037 on
-- 2026-11-23 (docs/seed-research/2026-11-23-forever/), then ordered by hand: the tool puts
-- interrupts first and each group in id order, and the priority order is curation. Membership is
-- the owner's rulings R6 and R7 of 2026-11-23: the research's core list per class plus Rogue
-- Gouge and Warrior Intercept, with War Stomp in each class a Tauren plays (a shared profile
-- appends the racial to its creator's class only). The rank lists in the comments are the
-- families the run found; the run-time rank resolver owns them (the port's MKF-KC-09).
--
-- WHO READS THIS. This file publishes NS.DefaultSpellsForever and NS.RaceCastStoppersForever and
-- never touches defaults/Spells.lua's NS.DefaultSpells or NS.RaceCastStoppers, so it changes
-- nothing on Retail. The per-client seeding that reads it on WoW Forever is the port's MKF-KC-11.

local _, NS = ...

local SPEC = NS.Const.SPEC_FOREVER

NS.DefaultSpellsForever = {

    WARRIOR = {
        [SPEC.WARRIOR] = {
            { spellID = 6552,   category = "interrupt",    enabled = true }, -- Pummel (Berserker Stance; ranks 6552, 6554; index 1 by R6)
            { spellID = 72,     category = "interrupt",    enabled = true }, -- Shield Bash (a shield; ranks 72, 1671, 1672; shares Pummel's cooldown category)
            { spellID = 12809,  category = "stun",         enabled = true }, -- Concussion Blow (Protection talent)
            { spellID = 5246,   category = "fear",         enabled = true }, -- Intimidating Shout
            { spellID = 20252,  category = "stun",         enabled = true }, -- Intercept (Berserker Stance; ranks 20252, 20616, 20617; R7)
            { spellID = 20549,  category = "racial",       enabled = true }, -- War Stomp (Tauren; hidden when not known)
        },
    },

    PALADIN = {
        [SPEC.PALADIN] = {
            { spellID = 853,    category = "stun",         enabled = true }, -- Hammer of Justice (ranks 853, 5588, 5589, 10308; no paladin interrupt)
            { spellID = 20066,  category = "incapacitate", enabled = true }, -- Repentance (Retribution talent)
        },
    },

    HUNTER = {
        [SPEC.HUNTER] = {
            { spellID = 19503,  category = "incapacitate", enabled = true }, -- Scatter Shot (Marksmanship talent; no hunter interrupt, pets included)
            { spellID = 19577,  category = "stun",         enabled = true }, -- Intimidation (Beast Mastery talent; the pet stuns on its next hit)
            { spellID = 1499,   category = "incapacitate", enabled = true }, -- Freezing Trap (ranks 1499, 14310, 14311)
            { spellID = 20549,  category = "racial",       enabled = true }, -- War Stomp (Tauren; hidden when not known)
        },
    },

    ROGUE = {
        [SPEC.ROGUE] = {
            { spellID = 1766,   category = "interrupt",    enabled = true }, -- Kick (ranks 1766, 1767, 1768, 1769)
            { spellID = 408,    category = "stun",         enabled = true }, -- Kidney Shot (ranks 408, 8643)
            { spellID = 1833,   category = "stun",         enabled = true }, -- Cheap Shot (Stealth; no cooldown)
            { spellID = 2094,   category = "incapacitate", enabled = true }, -- Blind
            { spellID = 1776,   category = "incapacitate", enabled = true }, -- Gouge (ranks 1776, 1777, 8629, 11285, 11286; R7)
        },
    },

    PRIEST = {
        [SPEC.PRIEST] = {
            { spellID = 15487,  category = "silence",      enabled = true }, -- Silence (Shadow talent; a 3 s lockout besides the silence)
            { spellID = 8122,   category = "fear",         enabled = true }, -- Psychic Scream (ranks 8122, 8124, 10888, 10890)
            { spellID = 605,    category = "incapacitate", enabled = true }, -- Mind Control (ranks 605, 10911, 10912; no cooldown)
        },
    },

    SHAMAN = {
        [SPEC.SHAMAN] = {
            { spellID = 8042,   category = "interrupt",    enabled = true }, -- Earth Shock (ranks 8042-8046, 10412-10414; shares the shocks' cooldown)
            { spellID = 20549,  category = "racial",       enabled = true }, -- War Stomp (Tauren; hidden when not known)
        },
    },

    MAGE = {
        [SPEC.MAGE] = {
            { spellID = 2139,   category = "interrupt",    enabled = true }, -- Counterspell (off the GCD)
            { spellID = 118,    category = "incapacitate", enabled = true }, -- Polymorph (ranks 118, 12824, 12825, 12826; no cooldown)
        },
    },

    WARLOCK = {
        [SPEC.WARLOCK] = {
            { spellID = 19244,  category = "interrupt",    enabled = true }, -- Spell Lock (Felhunter; ranks 19244, 19647)
            { spellID = 6789,   category = "fear",         enabled = true }, -- Death Coil (ranks 6789, 17925, 17926)
            { spellID = 5484,   category = "fear",         enabled = true }, -- Howl of Terror (ranks 5484, 17928)
            { spellID = 5782,   category = "fear",         enabled = true }, -- Fear (ranks 5782, 6213, 6215; no cooldown)
        },
    },

    DRUID = {
        [SPEC.DRUID] = {
            { spellID = 1238122, category = "interrupt",   enabled = true }, -- Feral Charge (Feral talent; interrupts in bear forms only)
            { spellID = 5211,   category = "stun",         enabled = true }, -- Bash (bear forms; ranks 5211, 6798, 8983)
            { spellID = 20549,  category = "racial",       enabled = true }, -- War Stomp (Tauren; hidden when not known)
        },
    },
}

NS.RaceCastStoppersForever = {
    Tauren = 20549, -- War Stomp
}
