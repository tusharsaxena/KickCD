-- defaults/Spells.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §6 and docs/RESEARCH.md §6
--
-- Per-class+spec default cast-stopper lists. Index 1 is the primary interrupt
-- (or, where no class-wide kick exists, the spec's best cast-stopping CC).
-- Indices 2..N are PvE-biased secondary cast-stoppers in priority order.
-- Categories are constrained to the closed set:
--   "interrupt" | "stun" | "knockback" | "incapacitate" | "silence" | "root" | "fear" | "displace" | "racial"
--
-- Class keys use the localization-independent file token from UnitClass()'s
-- second return. Spec keys use uppercase tokens of the spec name.

KickCD = KickCD or {}

KickCD.DefaultSpells = {

    DEATHKNIGHT = {
        BLOOD = {
            { spellID = 47528,  category = "interrupt",    enabled = true }, -- Mind Freeze
            { spellID = 49576,  category = "displace",     enabled = true }, -- Death Grip
            { spellID = 108199, category = "knockback",    enabled = true }, -- Gorefiend's Grasp
            { spellID = 221562, category = "stun",         enabled = true }, -- Asphyxiate (Blood)
            { spellID = 207167, category = "incapacitate", enabled = true }, -- Blinding Sleet
        },
        FROST = {
            { spellID = 47528,  category = "interrupt",    enabled = true }, -- Mind Freeze
            { spellID = 49576,  category = "displace",     enabled = true }, -- Death Grip
            { spellID = 108194, category = "stun",         enabled = true }, -- Asphyxiate (Frost/Unholy)
            { spellID = 207167, category = "incapacitate", enabled = true }, -- Blinding Sleet
        },
        UNHOLY = {
            { spellID = 47528,  category = "interrupt",    enabled = true }, -- Mind Freeze
            { spellID = 49576,  category = "displace",     enabled = true }, -- Death Grip
            { spellID = 108194, category = "stun",         enabled = true }, -- Asphyxiate (Frost/Unholy)
            { spellID = 207167, category = "incapacitate", enabled = true }, -- Blinding Sleet
        },
    },

    DEMONHUNTER = {
        HAVOC = {
            { spellID = 183752, category = "interrupt",    enabled = true }, -- Disrupt
            { spellID = 179057, category = "stun",         enabled = true }, -- Chaos Nova
            { spellID = 217832, category = "incapacitate", enabled = true }, -- Imprison
            { spellID = 207684, category = "fear",         enabled = true }, -- Sigil of Misery
            { spellID = 370965, category = "root",         enabled = true }, -- The Hunt
        },
        VENGEANCE = {
            { spellID = 183752, category = "interrupt",    enabled = true }, -- Disrupt
            { spellID = 179057, category = "stun",         enabled = true }, -- Chaos Nova
            { spellID = 217832, category = "incapacitate", enabled = true }, -- Imprison
            { spellID = 207684, category = "fear",         enabled = true }, -- Sigil of Misery
            { spellID = 202138, category = "displace",     enabled = true }, -- Sigil of Chains
        },
        DEVOURER = {
            { spellID = 183752,  category = "interrupt",    enabled = true }, -- Disrupt
            { spellID = 1234195, category = "stun",         enabled = true }, -- Void Nova (replaces Chaos Nova for Devourer)
            { spellID = 217832,  category = "incapacitate", enabled = true }, -- Imprison
            { spellID = 207684,  category = "fear",         enabled = true }, -- Sigil of Misery
            { spellID = 370965,  category = "root",         enabled = true }, -- The Hunt
        },
    },

    DRUID = {
        BALANCE = {
            { spellID = 78675,  category = "silence",   enabled = true }, -- Solar Beam
            { spellID = 132469, category = "knockback", enabled = true }, -- Typhoon
            { spellID = 5211,   category = "stun",      enabled = true }, -- Mighty Bash
            { spellID = 33786,  category = "incapacitate", enabled = true }, -- Cyclone
            { spellID = 339,    category = "root",      enabled = true }, -- Entangling Roots
        },
        FERAL = {
            { spellID = 106839, category = "interrupt", enabled = true }, -- Skull Bash
            { spellID = 5211,   category = "stun",      enabled = true }, -- Mighty Bash
            { spellID = 22570,  category = "stun",      enabled = true }, -- Maim
            { spellID = 33786,  category = "incapacitate", enabled = true }, -- Cyclone
        },
        GUARDIAN = {
            { spellID = 106839, category = "interrupt", enabled = true }, -- Skull Bash
            { spellID = 5211,   category = "stun",      enabled = true }, -- Mighty Bash
            { spellID = 99,     category = "incapacitate", enabled = true }, -- Incapacitating Roar
            { spellID = 33786,  category = "incapacitate", enabled = true }, -- Cyclone
        },
        RESTORATION = {
            { spellID = 5211,   category = "stun",         enabled = true }, -- Mighty Bash
            { spellID = 132469, category = "knockback",    enabled = true }, -- Typhoon
            { spellID = 33786,  category = "incapacitate", enabled = true }, -- Cyclone
            { spellID = 339,    category = "root",         enabled = true }, -- Entangling Roots
        },
    },

    EVOKER = {
        DEVASTATION = {
            { spellID = 351338, category = "interrupt", enabled = true }, -- Quell
            { spellID = 357214, category = "knockback", enabled = true }, -- Wing Buffet
            { spellID = 360806, category = "incapacitate", enabled = true }, -- Sleep Walk
        },
        PRESERVATION = {
            { spellID = 351338, category = "interrupt", enabled = true }, -- Quell
            { spellID = 357214, category = "knockback", enabled = true }, -- Wing Buffet
            { spellID = 360806, category = "incapacitate", enabled = true }, -- Sleep Walk
        },
        AUGMENTATION = {
            { spellID = 351338, category = "interrupt", enabled = true }, -- Quell
            { spellID = 357214, category = "knockback", enabled = true }, -- Wing Buffet
            { spellID = 360806, category = "incapacitate", enabled = true }, -- Sleep Walk
        },
    },

    HUNTER = {
        BEASTMASTERY = {
            { spellID = 147362, category = "interrupt", enabled = true }, -- Counter Shot
            { spellID = 19577,  category = "stun",      enabled = true }, -- Intimidation
            { spellID = 109248, category = "stun",      enabled = true }, -- Binding Shot
            { spellID = 187650, category = "incapacitate", enabled = true }, -- Freezing Trap
            { spellID = 213691, category = "incapacitate", enabled = true }, -- Scatter Shot
        },
        MARKSMANSHIP = {
            { spellID = 147362, category = "interrupt", enabled = true }, -- Counter Shot
            { spellID = 109248, category = "stun",      enabled = true }, -- Binding Shot
            { spellID = 187650, category = "incapacitate", enabled = true }, -- Freezing Trap
            { spellID = 213691, category = "incapacitate", enabled = true }, -- Scatter Shot
        },
        SURVIVAL = {
            { spellID = 187707, category = "interrupt",    enabled = true }, -- Muzzle
            { spellID = 109248, category = "stun",         enabled = true }, -- Binding Shot
            { spellID = 187650, category = "incapacitate", enabled = true }, -- Freezing Trap
            { spellID = 19577,  category = "stun",         enabled = true }, -- Intimidation
        },
    },

    MAGE = {
        ARCANE = {
            { spellID = 2139,   category = "interrupt",    enabled = true }, -- Counterspell
            { spellID = 122,    category = "root",         enabled = true }, -- Frost Nova
            { spellID = 31661,  category = "incapacitate", enabled = true }, -- Dragon's Breath
            { spellID = 113724, category = "incapacitate", enabled = true }, -- Ring of Frost
            { spellID = 118,    category = "incapacitate", enabled = true }, -- Polymorph
        },
        FIRE = {
            { spellID = 2139,   category = "interrupt",    enabled = true }, -- Counterspell
            { spellID = 31661,  category = "incapacitate", enabled = true }, -- Dragon's Breath
            { spellID = 122,    category = "root",         enabled = true }, -- Frost Nova
            { spellID = 113724, category = "incapacitate", enabled = true }, -- Ring of Frost
            { spellID = 118,    category = "incapacitate", enabled = true }, -- Polymorph
        },
        FROST = {
            { spellID = 2139,   category = "interrupt",    enabled = true }, -- Counterspell
            { spellID = 122,    category = "root",         enabled = true }, -- Frost Nova
            { spellID = 113724, category = "incapacitate", enabled = true }, -- Ring of Frost
            { spellID = 31661,  category = "incapacitate", enabled = true }, -- Dragon's Breath
            { spellID = 118,    category = "incapacitate", enabled = true }, -- Polymorph
        },
    },

    MONK = {
        BREWMASTER = {
            { spellID = 116705, category = "interrupt",    enabled = true }, -- Spear Hand Strike
            { spellID = 119381, category = "stun",         enabled = true }, -- Leg Sweep
            { spellID = 115078, category = "incapacitate", enabled = true }, -- Paralysis
        },
        MISTWEAVER = {
            { spellID = 116705, category = "interrupt",    enabled = true }, -- Spear Hand Strike
            { spellID = 119381, category = "stun",         enabled = true }, -- Leg Sweep
            { spellID = 115078, category = "incapacitate", enabled = true }, -- Paralysis
        },
        WINDWALKER = {
            { spellID = 116705, category = "interrupt",    enabled = true }, -- Spear Hand Strike
            { spellID = 119381, category = "stun",         enabled = true }, -- Leg Sweep
            { spellID = 115078, category = "incapacitate", enabled = true }, -- Paralysis
        },
    },

    PALADIN = {
        HOLY = {
            { spellID = 853,    category = "stun",    enabled = true }, -- Hammer of Justice
            { spellID = 20066,  category = "incapacitate", enabled = true }, -- Repentance
            { spellID = 105421, category = "incapacitate", enabled = true }, -- Blinding Light
        },
        PROTECTION = {
            { spellID = 96231,  category = "interrupt", enabled = true }, -- Rebuke
            { spellID = 31935,  category = "silence",   enabled = true }, -- Avenger's Shield
            { spellID = 853,    category = "stun",      enabled = true }, -- Hammer of Justice
            { spellID = 105421, category = "incapacitate", enabled = true }, -- Blinding Light
            { spellID = 20066,  category = "incapacitate", enabled = true }, -- Repentance
        },
        RETRIBUTION = {
            { spellID = 96231,  category = "interrupt",    enabled = true }, -- Rebuke
            { spellID = 853,    category = "stun",         enabled = true }, -- Hammer of Justice
            { spellID = 20066,  category = "incapacitate", enabled = true }, -- Repentance
            { spellID = 105421, category = "incapacitate", enabled = true }, -- Blinding Light
        },
    },

    PRIEST = {
        DISCIPLINE = {
            { spellID = 15487,  category = "silence",      enabled = true }, -- Silence
            { spellID = 605,    category = "incapacitate", enabled = true }, -- Mind Control
            { spellID = 8122,   category = "fear",         enabled = true }, -- Psychic Scream
            { spellID = 64044,  category = "stun",         enabled = true }, -- Psychic Horror
        },
        HOLY = {
            { spellID = 8122,   category = "fear",         enabled = true }, -- Psychic Scream
            { spellID = 605,    category = "incapacitate", enabled = true }, -- Mind Control
            { spellID = 88625,  category = "stun",         enabled = true }, -- Holy Word: Chastise
        },
        SHADOW = {
            { spellID = 15487,  category = "silence",      enabled = true }, -- Silence
            { spellID = 8122,   category = "fear",         enabled = true }, -- Psychic Scream
            { spellID = 64044,  category = "stun",         enabled = true }, -- Psychic Horror
            { spellID = 605,    category = "incapacitate", enabled = true }, -- Mind Control
        },
    },

    ROGUE = {
        ASSASSINATION = {
            { spellID = 1766,   category = "interrupt",    enabled = true }, -- Kick
            { spellID = 408,    category = "stun",         enabled = true }, -- Kidney Shot
            { spellID = 1833,   category = "stun",         enabled = true }, -- Cheap Shot
            { spellID = 2094,   category = "incapacitate", enabled = true }, -- Blind
        },
        OUTLAW = {
            { spellID = 1766,   category = "interrupt",    enabled = true }, -- Kick
            { spellID = 408,    category = "stun",         enabled = true }, -- Kidney Shot
            { spellID = 1833,   category = "stun",         enabled = true }, -- Cheap Shot
            { spellID = 2094,   category = "incapacitate", enabled = true }, -- Blind
        },
        SUBTLETY = {
            { spellID = 1766,   category = "interrupt",    enabled = true }, -- Kick
            { spellID = 408,    category = "stun",         enabled = true }, -- Kidney Shot
            { spellID = 1833,   category = "stun",         enabled = true }, -- Cheap Shot
            { spellID = 2094,   category = "incapacitate", enabled = true }, -- Blind
        },
    },

    SHAMAN = {
        ELEMENTAL = {
            { spellID = 57994,  category = "interrupt",    enabled = true }, -- Wind Shear
            { spellID = 192058, category = "stun",         enabled = true }, -- Capacitor Totem
            { spellID = 51490,  category = "knockback",    enabled = true }, -- Thunderstorm
            { spellID = 51514,  category = "incapacitate", enabled = true }, -- Hex
        },
        ENHANCEMENT = {
            { spellID = 57994,  category = "interrupt",    enabled = true }, -- Wind Shear
            { spellID = 192058, category = "stun",         enabled = true }, -- Capacitor Totem
            { spellID = 51514,  category = "incapacitate", enabled = true }, -- Hex
        },
        RESTORATION = {
            { spellID = 57994,  category = "interrupt",    enabled = true }, -- Wind Shear
            { spellID = 192058, category = "stun",         enabled = true }, -- Capacitor Totem
            { spellID = 51514,  category = "incapacitate", enabled = true }, -- Hex
            { spellID = 51490,  category = "knockback",    enabled = true }, -- Thunderstorm
        },
    },

    WARLOCK = {
        AFFLICTION = {
            { spellID = 19647,  category = "interrupt",    enabled = true }, -- Spell Lock (Felhunter)
            { spellID = 30283,  category = "stun",         enabled = true }, -- Shadowfury
            { spellID = 6789,   category = "fear",         enabled = true }, -- Mortal Coil
            { spellID = 5782,   category = "fear",         enabled = true }, -- Fear
        },
        DEMONOLOGY = {
            { spellID = 19647,  category = "interrupt",    enabled = true }, -- Spell Lock (Felhunter)
            { spellID = 30283,  category = "stun",         enabled = true }, -- Shadowfury
            { spellID = 6789,   category = "fear",         enabled = true }, -- Mortal Coil
            { spellID = 5782,   category = "fear",         enabled = true }, -- Fear
        },
        DESTRUCTION = {
            { spellID = 19647,  category = "interrupt", enabled = true }, -- Spell Lock (Felhunter)
            { spellID = 30283,  category = "stun",      enabled = true }, -- Shadowfury
            { spellID = 6789,   category = "fear",      enabled = true }, -- Mortal Coil
            { spellID = 5782,   category = "fear",      enabled = true }, -- Fear
        },
    },

    WARRIOR = {
        ARMS = {
            { spellID = 6552,   category = "interrupt", enabled = true }, -- Pummel
            { spellID = 107570, category = "stun",      enabled = true }, -- Storm Bolt
            { spellID = 5246,   category = "fear",      enabled = true }, -- Intimidating Shout
        },
        FURY = {
            { spellID = 6552,   category = "interrupt", enabled = true }, -- Pummel
            { spellID = 107570, category = "stun",      enabled = true }, -- Storm Bolt
            { spellID = 5246,   category = "fear",      enabled = true }, -- Intimidating Shout
        },
        PROTECTION = {
            { spellID = 6552,   category = "interrupt", enabled = true }, -- Pummel
            { spellID = 46968,  category = "stun",      enabled = true }, -- Shockwave
            { spellID = 107570, category = "stun",      enabled = true }, -- Storm Bolt
            { spellID = 5246,   category = "fear",      enabled = true }, -- Intimidating Shout
        },
    },
}

-- Race-specific cast-stoppers, appended to the per-spec list at first profile
-- creation by Database:BuildSpells() (see TECHNICAL_DESIGN §6).
KickCD.RaceCastStoppers = {
    Tauren             = 20549,  -- War Stomp
    HighmountainTauren = 255654, -- Bull Rush
    Pandaren           = 107079, -- Quaking Palm
    KulTiran           = 287712, -- Haymaker
    Nightborne         = 260364, -- Arcane Pulse
}
