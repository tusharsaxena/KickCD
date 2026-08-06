-- defaults/Spells.lua
-- Seeded by Database:BuildSpells() on first profile creation;
-- see docs/schema.md for the merge semantics.
--
-- Per-class+spec default cast-stopper lists. Index 1 is the primary interrupt
-- (or, where no class-wide kick exists, the spec's best cast-stopping CC).
-- Indices 2..N are PvE-biased secondary cast-stoppers in priority order.
-- Categories are constrained to the closed set:
--   "interrupt" | "stun" | "knockback" | "incapacitate" | "silence" | "root" | "fear" | "displace" | "racial" | "other"
--
-- Class keys use the localization-independent file token from UnitClass()'s
-- second return. Spec keys are Blizzard's NUMERIC specialization IDs, written
-- through the readable Const.SPEC aliases below.
--
-- Both key kinds are locale-invariant on purpose. Spec keys were previously
-- uppercased spec NAMES, which broke every non-English client: a frFR
-- Elemental Shaman derived "ELEMENTAIRE" at runtime and missed the
-- "ELEMENTAL" key here, so the addon tracked nothing at all (issue #8).
--
-- Source: per-spec cast-stopper coverage cross-referenced against Baratus's
-- "Class Info - Wow" sheet (Midnight tab, columns Q/S/T/U/V/X — Interrupt,
-- Stuns ST/AoE, CC Hard, CC Soft AoE, CC Other; columns R Dispels and W
-- AoE Slow are intentionally excluded since neither category stops casts):
-- https://docs.google.com/spreadsheets/d/1lXIRuETd3s3wxLHE8mOwhXtz0xm71ayhrlYxwi6herU/edit?gid=2092737897

local addonName, NS = ...

-- Readable aliases for the numeric spec IDs (see core/Constants.lua). Using
-- [SPEC.ELEMENTAL] rather than a bare 262 keeps this table greppable while
-- the stored key stays locale-invariant.
local SPEC = NS.Const.SPEC

NS.DefaultSpells = {

    DEATHKNIGHT = {
        [SPEC.BLOOD] = {
            { spellID = 47528,  category = "interrupt",    enabled = true }, -- Mind Freeze
            { spellID = 49576,  category = "displace",     enabled = true }, -- Death Grip
            { spellID = 108199, category = "knockback",    enabled = true }, -- Gorefiend's Grasp
            { spellID = 221562, category = "stun",         enabled = true }, -- Asphyxiate (Blood)
            { spellID = 207167, category = "incapacitate", enabled = true }, -- Blinding Sleet
            { spellID = 1263569, category = "displace",     enabled = true }, -- Abomination Limb (Blood class talent)
        },
        [SPEC.FROST_DK] = {
            { spellID = 47528,  category = "interrupt",    enabled = true }, -- Mind Freeze
            { spellID = 49576,  category = "displace",     enabled = true }, -- Death Grip
            { spellID = 108194, category = "stun",         enabled = true }, -- Asphyxiate (Frost/Unholy)
            { spellID = 207167, category = "incapacitate", enabled = true }, -- Blinding Sleet
            { spellID = 279302, category = "stun",         enabled = true }, -- Frostwyrm's Fury (3s AoE stun w/ Absolute Zero)
        },
        [SPEC.UNHOLY] = {
            { spellID = 47528,  category = "interrupt",    enabled = true }, -- Mind Freeze
            { spellID = 49576,  category = "displace",     enabled = true }, -- Death Grip
            { spellID = 108194, category = "stun",         enabled = true }, -- Asphyxiate (Frost/Unholy)
            { spellID = 207167, category = "incapacitate", enabled = true }, -- Blinding Sleet
        },
    },

    DEMONHUNTER = {
        [SPEC.HAVOC] = {
            { spellID = 183752, category = "interrupt",    enabled = true }, -- Disrupt
            { spellID = 179057, category = "stun",         enabled = true }, -- Chaos Nova
            { spellID = 217832, category = "incapacitate", enabled = true }, -- Imprison
            { spellID = 207684, category = "fear",         enabled = true }, -- Sigil of Misery
        },
        [SPEC.VENGEANCE] = {
            { spellID = 183752, category = "interrupt",    enabled = true }, -- Disrupt
            { spellID = 179057, category = "stun",         enabled = true }, -- Chaos Nova
            { spellID = 217832, category = "incapacitate", enabled = true }, -- Imprison
            { spellID = 207684, category = "fear",         enabled = true }, -- Sigil of Misery
            { spellID = 202138, category = "displace",     enabled = true }, -- Sigil of Chains
            { spellID = 202137, category = "silence",      enabled = true }, -- Sigil of Silence (Vengeance)
        },
        [SPEC.DEVOURER] = {
            { spellID = 183752,  category = "interrupt",    enabled = true }, -- Disrupt
            { spellID = 1234195, category = "stun",         enabled = true }, -- Void Nova (replaces Chaos Nova for Devourer)
            { spellID = 217832,  category = "incapacitate", enabled = true }, -- Imprison
            { spellID = 207684,  category = "fear",         enabled = true }, -- Sigil of Misery
        },
    },

    DRUID = {
        [SPEC.BALANCE] = {
            { spellID = 78675,  category = "silence",      enabled = true }, -- Solar Beam
            { spellID = 132469, category = "knockback",    enabled = true }, -- Typhoon
            { spellID = 5211,   category = "stun",         enabled = true }, -- Mighty Bash
            { spellID = 33786,  category = "incapacitate", enabled = true }, -- Cyclone
            { spellID = 99,     category = "incapacitate", enabled = true }, -- Incapacitating Roar (class talent)
        },
        [SPEC.FERAL] = {
            { spellID = 106839, category = "interrupt",    enabled = true }, -- Skull Bash
            { spellID = 5211,   category = "stun",         enabled = true }, -- Mighty Bash
            { spellID = 22570,  category = "stun",         enabled = true }, -- Maim
            { spellID = 33786,  category = "incapacitate", enabled = true }, -- Cyclone
            { spellID = 99,     category = "incapacitate", enabled = true }, -- Incapacitating Roar (class talent)
            { spellID = 132469, category = "knockback",    enabled = true }, -- Typhoon (class talent)
        },
        [SPEC.GUARDIAN] = {
            { spellID = 106839, category = "interrupt",    enabled = true }, -- Skull Bash
            { spellID = 5211,   category = "stun",         enabled = true }, -- Mighty Bash
            { spellID = 99,     category = "incapacitate", enabled = true }, -- Incapacitating Roar
            { spellID = 33786,  category = "incapacitate", enabled = true }, -- Cyclone
            { spellID = 132469, category = "knockback",    enabled = true }, -- Typhoon (class talent)
        },
        [SPEC.RESTORATION_DRUID] = {
            { spellID = 5211,   category = "stun",         enabled = true }, -- Mighty Bash
            { spellID = 132469, category = "knockback",    enabled = true }, -- Typhoon
            { spellID = 33786,  category = "incapacitate", enabled = true }, -- Cyclone
            { spellID = 99,     category = "incapacitate", enabled = true }, -- Incapacitating Roar (class talent)
        },
    },

    EVOKER = {
        [SPEC.DEVASTATION] = {
            { spellID = 351338, category = "interrupt",    enabled = true }, -- Quell
            { spellID = 357214, category = "knockback",    enabled = true }, -- Wing Buffet
            { spellID = 368970, category = "knockback",    enabled = true }, -- Tail Swipe
            { spellID = 360806, category = "incapacitate", enabled = true }, -- Sleep Walk
        },
        [SPEC.PRESERVATION] = {
            { spellID = 351338, category = "interrupt",    enabled = true }, -- Quell
            { spellID = 357214, category = "knockback",    enabled = true }, -- Wing Buffet
            { spellID = 368970, category = "knockback",    enabled = true }, -- Tail Swipe
            { spellID = 360806, category = "incapacitate", enabled = true }, -- Sleep Walk
        },
        [SPEC.AUGMENTATION] = {
            { spellID = 351338, category = "interrupt",    enabled = true }, -- Quell
            { spellID = 357214, category = "knockback",    enabled = true }, -- Wing Buffet
            { spellID = 368970, category = "knockback",    enabled = true }, -- Tail Swipe
            { spellID = 360806, category = "incapacitate", enabled = true }, -- Sleep Walk
        },
    },

    HUNTER = {
        [SPEC.BEASTMASTERY] = {
            { spellID = 147362, category = "interrupt",    enabled = true }, -- Counter Shot
            { spellID = 19577,  category = "stun",         enabled = true }, -- Intimidation
            { spellID = 109248, category = "stun",         enabled = true }, -- Binding Shot
            { spellID = 187650, category = "incapacitate", enabled = true }, -- Freezing Trap
            { spellID = 213691, category = "incapacitate", enabled = true }, -- Scatter Shot
            { spellID = 392060, category = "silence",      enabled = true }, -- Wailing Arrow (Dark Ranger hero talent)
        },
        [SPEC.MARKSMANSHIP] = {
            { spellID = 147362, category = "interrupt",    enabled = true }, -- Counter Shot
            { spellID = 109248, category = "stun",         enabled = true }, -- Binding Shot
            { spellID = 187650, category = "incapacitate", enabled = true }, -- Freezing Trap
            { spellID = 213691, category = "incapacitate", enabled = true }, -- Scatter Shot
            { spellID = 392060, category = "silence",      enabled = true }, -- Wailing Arrow (Dark Ranger hero talent)
        },
        [SPEC.SURVIVAL] = {
            { spellID = 187707, category = "interrupt",    enabled = true }, -- Muzzle
            { spellID = 109248, category = "stun",         enabled = true }, -- Binding Shot
            { spellID = 187650, category = "incapacitate", enabled = true }, -- Freezing Trap
            { spellID = 19577,  category = "stun",         enabled = true }, -- Intimidation
        },
    },

    MAGE = {
        [SPEC.ARCANE] = {
            { spellID = 2139,   category = "interrupt",    enabled = true }, -- Counterspell
            { spellID = 31661,  category = "incapacitate", enabled = true }, -- Dragon's Breath
            { spellID = 113724, category = "incapacitate", enabled = true }, -- Ring of Frost
            { spellID = 118,    category = "incapacitate", enabled = true }, -- Polymorph
            { spellID = 157980, category = "knockback",    enabled = true }, -- Supernova (Arcane talent, knockup)
            { spellID = 383121, category = "incapacitate", enabled = true }, -- Mass Polymorph (class talent)
        },
        [SPEC.FIRE] = {
            { spellID = 2139,   category = "interrupt",    enabled = true }, -- Counterspell
            { spellID = 31661,  category = "incapacitate", enabled = true }, -- Dragon's Breath
            { spellID = 113724, category = "incapacitate", enabled = true }, -- Ring of Frost
            { spellID = 118,    category = "incapacitate", enabled = true }, -- Polymorph
            { spellID = 383121, category = "incapacitate", enabled = true }, -- Mass Polymorph (class talent)
        },
        [SPEC.FROST_MAGE] = {
            { spellID = 2139,   category = "interrupt",    enabled = true }, -- Counterspell
            { spellID = 113724, category = "incapacitate", enabled = true }, -- Ring of Frost
            { spellID = 31661,  category = "incapacitate", enabled = true }, -- Dragon's Breath
            { spellID = 118,    category = "incapacitate", enabled = true }, -- Polymorph
            { spellID = 383121, category = "incapacitate", enabled = true }, -- Mass Polymorph (class talent)
        },
    },

    MONK = {
        [SPEC.BREWMASTER] = {
            { spellID = 116705, category = "interrupt",    enabled = true }, -- Spear Hand Strike
            { spellID = 119381, category = "stun",         enabled = true }, -- Leg Sweep
            { spellID = 115078, category = "incapacitate", enabled = true }, -- Paralysis
            { spellID = 198898, category = "fear",         enabled = true }, -- Song of Chi-Ji (class talent)
            { spellID = 116844, category = "knockback",    enabled = true }, -- Ring of Peace (class talent)
        },
        [SPEC.MISTWEAVER] = {
            { spellID = 116705, category = "interrupt",    enabled = true }, -- Spear Hand Strike
            { spellID = 119381, category = "stun",         enabled = true }, -- Leg Sweep
            { spellID = 115078, category = "incapacitate", enabled = true }, -- Paralysis
            { spellID = 198898, category = "fear",         enabled = true }, -- Song of Chi-Ji (class talent)
            { spellID = 116844, category = "knockback",    enabled = true }, -- Ring of Peace (class talent)
        },
        [SPEC.WINDWALKER] = {
            { spellID = 116705, category = "interrupt",    enabled = true }, -- Spear Hand Strike
            { spellID = 119381, category = "stun",         enabled = true }, -- Leg Sweep
            { spellID = 115078, category = "incapacitate", enabled = true }, -- Paralysis
            { spellID = 198898, category = "fear",         enabled = true }, -- Song of Chi-Ji (class talent)
            { spellID = 116844, category = "knockback",    enabled = true }, -- Ring of Peace (class talent)
        },
    },

    PALADIN = {
        [SPEC.HOLY_PALADIN] = {
            { spellID = 853,    category = "stun",         enabled = true }, -- Hammer of Justice
            { spellID = 20066,  category = "incapacitate", enabled = true }, -- Repentance
            { spellID = 105421, category = "incapacitate", enabled = true }, -- Blinding Light
        },
        [SPEC.PROTECTION_PALADIN] = {
            { spellID = 96231,  category = "interrupt",    enabled = true }, -- Rebuke
            { spellID = 31935,  category = "silence",      enabled = true }, -- Avenger's Shield
            { spellID = 853,    category = "stun",         enabled = true }, -- Hammer of Justice
            { spellID = 105421, category = "incapacitate", enabled = true }, -- Blinding Light
            { spellID = 20066,  category = "incapacitate", enabled = true }, -- Repentance
        },
        [SPEC.RETRIBUTION] = {
            { spellID = 96231,  category = "interrupt",    enabled = true }, -- Rebuke
            { spellID = 853,    category = "stun",         enabled = true }, -- Hammer of Justice
            { spellID = 20066,  category = "incapacitate", enabled = true }, -- Repentance
            { spellID = 105421, category = "incapacitate", enabled = true }, -- Blinding Light
        },
    },

    PRIEST = {
        [SPEC.DISCIPLINE] = {
            { spellID = 15487,  category = "silence",      enabled = true }, -- Silence
            { spellID = 605,    category = "incapacitate", enabled = true }, -- Mind Control
            { spellID = 8122,   category = "fear",         enabled = true }, -- Psychic Scream
            { spellID = 64044,  category = "stun",         enabled = true }, -- Psychic Horror
        },
        [SPEC.HOLY_PRIEST] = {
            { spellID = 8122,   category = "fear",         enabled = true }, -- Psychic Scream
            { spellID = 605,    category = "incapacitate", enabled = true }, -- Mind Control
            { spellID = 88625,  category = "stun",         enabled = true }, -- Holy Word: Chastise
        },
        [SPEC.SHADOW] = {
            { spellID = 15487,  category = "silence",      enabled = true }, -- Silence
            { spellID = 8122,   category = "fear",         enabled = true }, -- Psychic Scream
            { spellID = 64044,  category = "stun",         enabled = true }, -- Psychic Horror
            { spellID = 605,    category = "incapacitate", enabled = true }, -- Mind Control
        },
    },

    ROGUE = {
        [SPEC.ASSASSINATION] = {
            { spellID = 1766,   category = "interrupt",    enabled = true }, -- Kick
            { spellID = 408,    category = "stun",         enabled = true }, -- Kidney Shot
            { spellID = 1833,   category = "stun",         enabled = true }, -- Cheap Shot
            { spellID = 2094,   category = "incapacitate", enabled = true }, -- Blind
        },
        [SPEC.OUTLAW] = {
            { spellID = 1766,   category = "interrupt",    enabled = true }, -- Kick
            { spellID = 408,    category = "stun",         enabled = true }, -- Kidney Shot
            { spellID = 1833,   category = "stun",         enabled = true }, -- Cheap Shot
            { spellID = 2094,   category = "incapacitate", enabled = true }, -- Blind
        },
        [SPEC.SUBTLETY] = {
            { spellID = 1766,   category = "interrupt",    enabled = true }, -- Kick
            { spellID = 408,    category = "stun",         enabled = true }, -- Kidney Shot
            { spellID = 1833,   category = "stun",         enabled = true }, -- Cheap Shot
            { spellID = 2094,   category = "incapacitate", enabled = true }, -- Blind
        },
    },

    SHAMAN = {
        [SPEC.ELEMENTAL] = {
            { spellID = 57994,  category = "interrupt",    enabled = true }, -- Wind Shear
            { spellID = 192058, category = "stun",         enabled = true }, -- Capacitor Totem
            { spellID = 51490,  category = "knockback",    enabled = true }, -- Thunderstorm
            { spellID = 51514,  category = "incapacitate", enabled = true }, -- Hex
        },
        [SPEC.ENHANCEMENT] = {
            { spellID = 57994,  category = "interrupt",    enabled = true }, -- Wind Shear
            { spellID = 192058, category = "stun",         enabled = true }, -- Capacitor Totem
            { spellID = 51514,  category = "incapacitate", enabled = true }, -- Hex
        },
        [SPEC.RESTORATION_SHAMAN] = {
            { spellID = 57994,  category = "interrupt",    enabled = true }, -- Wind Shear
            { spellID = 192058, category = "stun",         enabled = true }, -- Capacitor Totem
            { spellID = 51514,  category = "incapacitate", enabled = true }, -- Hex
            { spellID = 51490,  category = "knockback",    enabled = true }, -- Thunderstorm
        },
    },

    WARLOCK = {
        [SPEC.AFFLICTION] = {
            { spellID = 19647,  category = "interrupt",    enabled = true }, -- Spell Lock (Felhunter)
            { spellID = 30283,  category = "stun",         enabled = true }, -- Shadowfury
            { spellID = 6789,   category = "fear",         enabled = true }, -- Mortal Coil
            { spellID = 5782,   category = "fear",         enabled = true }, -- Fear
            { spellID = 5484,   category = "fear",         enabled = true }, -- Howl of Terror (class talent)
        },
        [SPEC.DEMONOLOGY] = {
            { spellID = 19647,  category = "interrupt",    enabled = true }, -- Spell Lock (Felhunter)
            { spellID = 89766,  category = "stun",         enabled = true }, -- Axe Toss (Felguard, Demo's default pet)
            { spellID = 30283,  category = "stun",         enabled = true }, -- Shadowfury
            { spellID = 6789,   category = "fear",         enabled = true }, -- Mortal Coil
            { spellID = 5782,   category = "fear",         enabled = true }, -- Fear
            { spellID = 5484,   category = "fear",         enabled = true }, -- Howl of Terror (class talent)
        },
        [SPEC.DESTRUCTION] = {
            { spellID = 19647,  category = "interrupt",    enabled = true }, -- Spell Lock (Felhunter)
            { spellID = 30283,  category = "stun",         enabled = true }, -- Shadowfury
            { spellID = 6789,   category = "fear",         enabled = true }, -- Mortal Coil
            { spellID = 5782,   category = "fear",         enabled = true }, -- Fear
            { spellID = 5484,   category = "fear",         enabled = true }, -- Howl of Terror (class talent)
        },
    },

    WARRIOR = {
        [SPEC.ARMS] = {
            { spellID = 6552,   category = "interrupt", enabled = true }, -- Pummel
            { spellID = 107570, category = "stun",      enabled = true }, -- Storm Bolt
            { spellID = 5246,   category = "fear",      enabled = true }, -- Intimidating Shout
        },
        [SPEC.FURY] = {
            { spellID = 6552,   category = "interrupt", enabled = true }, -- Pummel
            { spellID = 107570, category = "stun",      enabled = true }, -- Storm Bolt
            { spellID = 5246,   category = "fear",      enabled = true }, -- Intimidating Shout
        },
        [SPEC.PROTECTION_WARRIOR] = {
            { spellID = 6552,   category = "interrupt", enabled = true }, -- Pummel
            { spellID = 386071, category = "interrupt", enabled = true }, -- Disrupting Shout (AoE interrupt talent)
            { spellID = 46968,  category = "stun",      enabled = true }, -- Shockwave
            { spellID = 107570, category = "stun",      enabled = true }, -- Storm Bolt
            { spellID = 5246,   category = "fear",      enabled = true }, -- Intimidating Shout
            { spellID = 23920,  category = "other",     enabled = true }, -- Spell Reflection
        },
    },
}

-- Race-specific cast-stoppers, appended to the per-spec list at first profile
-- creation by Database:BuildSpells() (see docs/schema.md).
NS.RaceCastStoppers = {
    Tauren             = 20549,  -- War Stomp
    HighmountainTauren = 255654, -- Bull Rush
    Pandaren           = 107079, -- Quaking Palm
    KulTiran           = 287712, -- Haymaker
    Nightborne         = 260364, -- Arcane Pulse
}

