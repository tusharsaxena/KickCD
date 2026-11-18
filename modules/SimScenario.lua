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
-- FALLBACK. Without the library the sim cannot run (core/SimSetup.lua's stub refuses it), but the
-- table is still built at load, so it is built from a copy of the library's rows (Sim
-- version-3.3.11.4 docs, *The data*). tests/test_sim_e2e.lua holds the copy to the library's set.
local KICKS = {
    HUNTER  = 147362, -- Counter Shot
    PALADIN = 96231,  -- Rebuke
    MAGE    = 2139,   -- Counterspell
    WARRIOR = 6552,   -- Pummel
}
local SAMPLE_COPY = {
    { name = "Samplehunter", classFile = "HUNTER",  spec = "Beast Mastery", specID = 253 },
    { name = "Sampleblade",  classFile = "PALADIN", spec = "Retribution",   specID = 70 },
    { name = "Mockflame",    classFile = "MAGE",    spec = "Fire",          specID = 63 },
    { name = "Samplemender", classFile = "PRIEST",  spec = "Holy",          specID = 257 },
    { name = "Mockshield",   classFile = "WARRIOR", spec = "Protection",    specID = 73 },
}

--- The sample rows for the running client: the library's copy, or ours without it.
local function sampleRows()
    local Sim = LibStub and LibStub("LibKa0s-Sim-1.0", true)
    if Sim and Sim.Sample then return Sim.Sample() end
    return SAMPLE_COPY
end

--- The made-up party (narrative only, design D1): every sample character whose class has a kick.
local function buildParty()
    local party = {}
    for _, row in ipairs(sampleRows()) do
        local kick = KICKS[row.classFile]
        if kick then
            party[row.name:lower()] = { name = row.name, spec = row.spec, specID = row.specID,
                class = row.classFile, spell = kick }
        end
    end
    return party
end
SC.PARTY = buildParty()

--- The enemies, with the spellIDs of the casts each makes (real spells, read for their names and
--- textures through NS.Compat.GetSpellInfo when the cast starts).
SC.ENEMIES = {
    casterA = { name = L["Shadowcaster"], cast = 686, channel = 15407 },     -- Shadow Bolt, Mind Flay
    casterB = { name = L["Bonecaller"],   cast = 5782, channel = 234153 },   -- Fear, Drain Life
    boss    = { name = L["Hollow King"],  cast = 116858, channel = 234153 }, -- Chaos Bolt, Drain Life
}

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

--- A Mythic+ pull with several kickers.
function TIMELINES.pull()
    local a, b = "casterA", "casterB"
    return {
        combat(true),
        target(a),
        focus(b),
        cast(a, L["%s starts a cast"]:format(enemyName(a))),
        cast(b, L["%s starts a cast beside it"]:format(enemyName(b))),
        kick(a),
        partyKick("sampleblade", b),
        cast(b, L["%s starts a channel"]:format(enemyName(b)), { channel = true }),
        partyKick("samplehunter", b),
        cast(a, L["%s casts again while your kick cools"]:format(enemyName(a))),
        partyKick("mockflame", a),
        step("Cc", { enemy = a, label = L["Stop %s with your CC"]:format(enemyName(a)) }),
        step("Die", { enemy = a, label = L["%s dies"]:format(enemyName(a)) }),
        combat(false),
    }
end

--- A boss kick rotation, with your kick on two charges.
function TIMELINES.boss()
    local k = "boss"
    local n = enemyName(k)
    return {
        step("Setup", { charges = 2, label = L["Your kick gets two charges"] }),
        combat(true),
        target(k),
        cast(k, L["%s: cast 1"]:format(n)),
        partyKick("sampleblade", k),
        cast(k, L["%s: cast 2"]:format(n)),
        kick(k),
        cast(k, L["%s: cast 3, a channel"]:format(n), { channel = true }),
        partyKick("mockshield", k),
        cast(k, L["%s: cast 4"]:format(n)),
        kick(k),
        step("Expire", { spell = "kick", label = L["Your kick's charges come back"] }),
        cast(k, L["%s: cast 5"]:format(n)),
        kick(k),
        combat(false),
    }
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
        cast(b, L["%s starts a cast %s is assigned to"]:format(enemyName(b), memberName("mockshield")),
            { duration = SC.LEAVE_CAST }),
        step("Leave", { member = "mockshield", label = L["%s leaves the party"]:format(memberName("mockshield")) }),
        focus(nil, L["Clear your focus"]),
        target(b, L["Target %s mid-cast"]:format(enemyName(b))),
        kick(b),
        combat(false),
    }
end

-- ── fill the host's table in place (modules/Sim.lua created it) ──────────────────────────────

SC.NAMES = { "pull", "boss", "miss", "leave" }
SC.LABELS = {
    pull  = L["Mythic+ pull, several kickers"],
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
