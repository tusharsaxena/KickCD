local _, NS = ...
-- modules/SimScenario.lua — the simulator's made-up party and KickCD#38's four scenarios (KC-08;
-- design-kc-sim §4, decision D1; OWNER_SCOPE B4).
--
-- ── THE PARTY IS NARRATIVE ───────────────────────────────────────────────────────────────────
--
-- KickCD tracks only the PLAYER's own interrupt and crowd-control cooldowns, against the target's
-- and the focus's casts. It has no party tracking, and a simulator drives the real engine, so it
-- cannot exercise a feature that does not exist. The four party members below appear only in `[sim]`
-- lines and step labels; their kicks end an enemy cast through UNIT_SPELLCAST_INTERRUPTED (the
-- PartyKick driver). Each #38 scenario maps onto the engine path it stresses:
--
--   pull   the combat gate, target and focus casting at once, a channel on the focus, your kick's
--          cooldown, the party's kicks, the CC's GCD on every other on-GCD spell, a death
--   boss   your kick's two charges: the badge counts 2 -> 1 -> 0, the recharge swipe, the expiry
--          (on WoW Forever, where no kick has charges, your kick's cooldown instead)
--   miss   an uninterruptible cast, its shield breaking, a kick refused on cooldown, a cast that
--          completes, the kick coming back
--   leave  a roster change no handler reads, then a target swap onto a cast already in progress
--          (the cast bar snaps through Castbar:Reevaluate)
--
-- ── PURE TIMELINES ───────────────────────────────────────────────────────────────────────────
--
-- Every `timeline(def, opts)` builds literal step tables and reads nothing else: the library calls
-- it while idle to preview the step list in the panel. A step names its role ("your kick", the
-- spell field "kick" / "cc") and the drivers (modules/SimDrivers.lua) resolve the real spell when
-- the step plays. Enemy names resolve here, at load, through NS.L; member names are the
-- library's sample characters and are never localized (below).
--
-- LOAD ORDER: this file FILLS NS.SimHost.SCENARIOS in place, which modules/Sim.lua creates and
-- hands to Sim:New, so it loads after modules/Sim.lua (the TOC says so under a LOAD-BEARING
-- comment). The library reads the table at call time, so a scenario filled here is one it sees.

local L = NS.L

NS.SimScenario = NS.SimScenario or {}
local SC = NS.SimScenario

-- ── THE PARTY IS THE COLLECTION'S SAMPLE CHARACTERS (AD-87-KC, LibKa0s#87) ────────────────────
--
-- preview-mode, *Sample characters* (owner ruling Q4 of 2026-11-16): a simulator's made-up people
-- are LibKa0s-Sim-1.0's sample set, read for the running client through `Sim.Sample()`, named
-- Sample/Mock and never passed through NS.L. Four of the five have a kick; the fifth, the Holy
-- priest, has none and sits the story out. `spell` is the member's kick, its name read live through
-- NS.Compat.GetSpellInfo when a line shows it. `spec` is the data's English label, for docs and
-- tests; the drivers name the spec in the client's own words from `specID`
-- (NS.Util.SpecDisplayName). Keyed by the sample's name, lowercased.
--
-- NO COPY OF OUR OWN (FB2-KC-01; LibKa0s#104, decision D1; preview-mode, standard v2.120.0): every
-- named sample person comes from the library, so this file keeps no list of names and no fallback
-- copy. Without the library the sim cannot run (core/SimSetup.lua's stub refuses it) and the party
-- is empty. The story picks its kickers by CLASS, never by a name typed here.
--
-- PER CLIENT (the WoW Forever port, MKF-KC-15; the synthesis 3.4 "Sim"). Each client's kick by
-- class: WoW Forever's Hunters and Paladins reach no interrupt (the research's FC 54), so its party
-- is the Mage and the Warrior, and the Protection sample carries a shield, so his kick is Shield
-- Bash 72 rather than Pummel, which wants Berserker Stance there. Picked once, by the client key.
local KICKS_BY_CLIENT = {
    retail = {
        HUNTER  = 147362, -- Counter Shot
        PALADIN = 96231,  -- Rebuke
        MAGE    = 2139,   -- Counterspell
        WARRIOR = 6552,   -- Pummel
    },
    forever = {
        MAGE    = 2139,   -- Counterspell
        WARRIOR = 72,     -- Shield Bash
    },
}

--- "forever" on WoW Forever, else "retail": the key every per-client table below is picked by, as
--- the library picks its sample set (Retail's on a client that is neither).
local function clientKey()
    local Compat = NS.Compat
    local key = Compat and Compat.ClientKey and Compat.ClientKey()
    return key == "forever" and "forever" or "retail"
end
SC.CLIENT = clientKey()

--- The sample rows for the running client, the library's own copy; none without the library.
local function sampleRows()
    local Sim = LibStub and LibStub("LibKa0s-Sim-1.0", true)
    if Sim and Sim.Sample then return Sim.Sample() end
    return {}
end

--- How a member is named in a `[sim]` line: the first name on Retail, the whole character name on
--- WoW Forever, "First Surname" (forever-quirks-§4). The key stays the first name, lowercased.
local function displayName(row)
    if SC.CLIENT == "forever" and type(row.surname) == "string" then return row.name .. " " .. row.surname end
    return row.name
end

--- The made-up party (narrative only, design D1): every sample character whose class has a kick on
--- the running client.
local function buildParty()
    local party = {}
    local kicks = KICKS_BY_CLIENT[SC.CLIENT]
    for _, row in ipairs(sampleRows()) do
        local kick = kicks[row.classFile]
        if kick then
            party[row.name:lower()] = { name = displayName(row), spec = row.spec, specID = row.specID,
                class = row.classFile, spell = kick }
        end
    end
    return party
end
SC.PARTY = buildParty()

-- Which member kicks at each party step of the story, per client, by the sample's class: Retail's
-- four kickers (the Paladin, the Hunter, the Mage, the Warrior tank), and on WoW Forever the two the
-- party has, the Mage and the Warrior, taking turns (every timeline names a member of SC.PARTY).
local KICKER_CLASSES = {
    retail  = { first = "PALADIN", second = "HUNTER",  third = "MAGE", tank = "WARRIOR" },
    forever = { first = "MAGE",    second = "WARRIOR", third = "MAGE", tank = "WARRIOR" },
}

--- The SC.PARTY key of the member of class `classFile`, or nil (no library, so no party).
local function memberOfClass(classFile)
    for key, row in pairs(SC.PARTY) do
        if row.class == classFile then return key end
    end
    return nil
end

local KICKER = {}
for role, classFile in pairs(KICKER_CLASSES[SC.CLIENT]) do KICKER[role] = memberOfClass(classFile) end

--- The enemies, with the spellIDs of the casts each makes (real spells, read for their names and
--- textures through NS.Compat.GetSpellInfo when the cast starts).
--- Per client: Chaos Bolt 116858 and Retail's Drain Life 234153 have no row in WoW Forever's data
--- (DB2 1.60.1.71037 SpellName), so there the boss casts Fireball 133 and Drain Life is rank 1, 689.
local ENEMIES_BY_CLIENT = {
    retail = {
        casterA = { name = L["Shadowcaster"], cast = 686, channel = 15407 },     -- Shadow Bolt, Mind Flay
        casterB = { name = L["Bonecaller"],   cast = 5782, channel = 234153 },   -- Fear, Drain Life
        boss    = { name = L["Hollow King"],  cast = 116858, channel = 234153 }, -- Chaos Bolt, Drain Life
    },
    forever = {
        casterA = { name = L["Shadowcaster"], cast = 686, channel = 15407 },     -- Shadow Bolt, Mind Flay
        casterB = { name = L["Bonecaller"],   cast = 5782, channel = 689 },      -- Fear, Drain Life
        boss    = { name = L["Hollow King"],  cast = 133, channel = 689 },       -- Fireball, Drain Life
    },
}
SC.ENEMIES = ENEMIES_BY_CLIENT[SC.CLIENT]

-- The story's timing (seconds) at one step a second: every cast, the `leave` cast, every channel.
-- The drivers scale each by the step delay when its step plays (SimDrivers D.Pace, R3-FIX), so a
-- slow pace keeps the story. The `leave` cast is 5, so the kick four steps after it meets it live,
-- and the `miss` shielded cast 5, so the kick three steps after it meets it live; each ran out with
-- the kick's own step at 4 and 3.
SC.CAST, SC.LEAVE_CAST, SC.CHANNEL, SC.SHIELD_CAST = 3, 5, 5, 5

--- One step: `kind` plus `fields` (copied, so a timeline never shares a table between calls).
local function step(kind, fields)
    local out = { kind = kind }
    for k, v in pairs(fields or {}) do out[k] = v end
    return out
end

local function enemyName(key) return SC.ENEMIES[key].name end
local function memberName(key) return SC.PARTY[key].name end

--- A cast (or, with `channel`, a channel) by enemy `key`, of `duration` seconds.
local function cast(key, label, opts)
    opts = opts or {}
    local e = SC.ENEMIES[key]
    local kind = opts.channel and "ChannelStart" or "CastStart"
    return step(kind, {
        enemy = key, spell = opts.channel and e.channel or e.cast,
        duration = opts.duration or (opts.channel and SC.CHANNEL or SC.CAST),
        uninterruptible = opts.uninterruptible, label = label,
    })
end

local function kick(key)
    return step("Kick", { enemy = key, label = L["Interrupt %s with your kick"]:format(enemyName(key)) })
end

local function partyKick(member, key)
    return step("PartyKick", { member = member, enemy = key,
        label = L["%s interrupts %s"]:format(memberName(member), enemyName(key)) })
end

local function combat(on)
    return step("Combat", { on = on, label = on and L["The pull starts"] or L["The pull ends"] })
end

local function target(key, label)
    return step("Target", { enemy = key, label = label or L["Target %s"]:format(enemyName(key)) })
end

local function focus(key, label)
    return step("Focus", { enemy = key, label = label or L["Focus %s"]:format(enemyName(key)) })
end

-- ── the four scenarios (KickCD#38) ────────────────────────────────────────────────────────────

local TIMELINES = {}

--- A Mythic+ pull (a dungeon pull on WoW Forever) with several kickers.
function TIMELINES.pull()
    local a, b = "casterA", "casterB"
    return {
        combat(true),
        target(a),
        focus(b),
        cast(a, L["%s starts a cast"]:format(enemyName(a))),
        cast(b, L["%s starts a cast beside it"]:format(enemyName(b))),
        kick(a),
        partyKick(KICKER.first, b),
        cast(b, L["%s starts a channel"]:format(enemyName(b)), { channel = true }),
        partyKick(KICKER.second, b),
        cast(a, L["%s casts again while your kick cools"]:format(enemyName(a))),
        partyKick(KICKER.third, a),
        step("Cc", { enemy = a, label = L["Stop %s with your CC"]:format(enemyName(a)) }),
        step("Die", { enemy = a, label = L["%s dies"]:format(enemyName(a)) }),
        combat(false),
    }
end

--- A boss kick rotation, with your kick on two charges. WoW Forever has no kick with charges (the
--- research's CA 2), so there the story has no Setup step: the second kick meets the first one's
--- cooldown, and the expiry is that cooldown coming back.
function TIMELINES.boss()
    local k = "boss"
    local n = enemyName(k)
    local charged = SC.CLIENT == "retail"
    local steps = {}
    if charged then steps[1] = step("Setup", { charges = 2, label = L["Your kick gets two charges"] }) end
    local story = {
        combat(true),
        target(k),
        cast(k, L["%s: cast 1"]:format(n)),
        partyKick(KICKER.first, k),
        cast(k, L["%s: cast 2"]:format(n)),
        kick(k),
        cast(k, L["%s: cast 3, a channel"]:format(n), { channel = true }),
        partyKick(KICKER.tank, k),
        cast(k, L["%s: cast 4"]:format(n)),
        kick(k),
        step("Expire", { spell = "kick",
            label = charged and L["Your kick's charges come back"] or L["Your kick comes back"] }),
        cast(k, L["%s: cast 5"]:format(n)),
        kick(k),
        combat(false),
    }
    for _, s in ipairs(story) do steps[#steps + 1] = s end
    return steps
end

--- Your kick on cooldown, and an uninterruptible cast.
function TIMELINES.miss()
    local a = "casterA"
    local n = enemyName(a)
    return {
        combat(true),
        target(a),
        cast(a, L["%s starts an uninterruptible cast"]:format(n), { uninterruptible = true, duration = SC.SHIELD_CAST }),
        kick(a),
        step("Interruptible", { enemy = a, label = L["%s's shield breaks"]:format(n) }),
        kick(a),
        cast(a, L["%s casts again"]:format(n)),
        kick(a),
        step("Complete", { enemy = a, label = L["%s's cast completes"]:format(n) }),
        step("Expire", { spell = "kick", label = L["Your kick comes back"] }),
        combat(false),
    }
end

--- A party member leaves mid-pull; you swap onto the cast they were assigned.
function TIMELINES.leave()
    local a, b = "casterA", "casterB"
    return {
        combat(true),
        target(a),
        focus(b),
        cast(b, L["%s starts a cast %s is assigned to"]:format(enemyName(b), memberName(KICKER.tank)),
            { duration = SC.LEAVE_CAST }),
        step("Leave", { member = KICKER.tank, label = L["%s leaves the party"]:format(memberName(KICKER.tank)) }),
        focus(nil, L["Clear your focus"]),
        target(b, L["Target %s mid-cast"]:format(enemyName(b))),
        kick(b),
        combat(false),
    }
end

-- ── fill the host's table in place (modules/Sim.lua created it) ──────────────────────────────

SC.NAMES = { "pull", "boss", "miss", "leave" }
-- WoW Forever has no Mythic+, so its pull is a dungeon's (the key stays `pull`).
SC.LABELS = {
    pull  = SC.CLIENT == "forever" and L["Dungeon pull, several kickers"] or L["Mythic+ pull, several kickers"],
    boss  = L["Boss kick rotation"],
    miss  = L["Kick on cooldown, uninterruptible cast"],
    leave = L["Party member leaves mid-pull"],
}

local Host = NS.SimHost
if Host and Host.SCENARIOS then
    local names, defs = Host.SCENARIOS.names, Host.SCENARIOS.defs
    for _, name in ipairs(SC.NAMES) do
        if not defs[name] then names[#names + 1] = name end
        local build = TIMELINES[name]
        defs[name] = { label = SC.LABELS[name], timeline = function() return build() end }
    end
end
