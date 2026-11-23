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
-- 2026-11-23.

local _, NS = ...

local SPEC = NS.Const.SPEC_FOREVER

NS.DefaultSpellsForever = {

    WARRIOR = {
        [SPEC.WARRIOR] = {
        },
    },

    PALADIN = {
        [SPEC.PALADIN] = {
        },
    },

    HUNTER = {
        [SPEC.HUNTER] = {
        },
    },

    ROGUE = {
        [SPEC.ROGUE] = {
        },
    },

    PRIEST = {
        [SPEC.PRIEST] = {
        },
    },

    SHAMAN = {
        [SPEC.SHAMAN] = {
        },
    },

    MAGE = {
        [SPEC.MAGE] = {
        },
    },

    WARLOCK = {
        [SPEC.WARLOCK] = {
        },
    },

    DRUID = {
        [SPEC.DRUID] = {
        },
    },
}

NS.RaceCastStoppersForever = {
    Tauren = 20549, -- War Stomp
}
