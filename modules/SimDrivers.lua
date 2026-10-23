local _, NS = ...
-- modules/SimDrivers.lua — the simulator's step drivers (KickCD#38, KC-07; design-kc-sim §5.3).
--
-- One driver per step kind. modules/Sim.lua's play hands a step to DRIVERS[step.kind]; the driver
-- edits the world through the NS.SimWorld mutators, then fires the client's events IN CLIENT ORDER
-- through NS.Sim:Fire (which hands them to NS.DeliverEvent), and answers the step's one-line detail
-- (the step panel's "Did" line). A driver never fires any other way and never writes the world
-- table directly; it READS the world to decide.
--
-- STATE-DRIVEN. A step names what the story intends ("you kick A"); the driver checks what the
-- world says now. No cast, an uninterruptible cast, a kick on cooldown and no charge left each take
-- their own truthful branch with their own `[sim]` line and fire nothing. So a paused run, a
-- click-ahead or a slow pace never prints a false line: only a different outcome, narrated truly.
--
-- NAMES. Spell names come from NS.Compat.GetSpellInfo (live: the player's real spells, design D4).
-- An enemy is named from NS.SimHost.world.enemies (first seen: NS.SimScenario.ENEMIES[key].name,
-- else the key); a party member from NS.SimScenario.PARTY[key] (modules/SimScenario.lua, KC-08),
-- read at call time. The role words "kick" and "cc" resolve to NS.SimHost.kick / NS.SimHost.cc when
-- the step plays, so a timeline stays pure.
--
-- EVENTS[kind] lists every event a kind can fire: modules/Sim.lua's StepTip reads it for the
-- tooltip's Fires line.

NS.SimDrivers = NS.SimDrivers or {}
local D = NS.SimDrivers
D.DRIVERS = D.DRIVERS or {}
D.EVENTS = D.EVENTS or {}
local DRIVERS, EVENTS = D.DRIVERS, D.EVENTS

-- The timing the scenarios' story is told in (seconds).
D.KICK_CD = 15     -- your kick's cooldown
D.CC_CD = 30       -- your CC's cooldown
D.GCD = 1.5        -- the global cooldown a CC triggers
D.RECHARGE = 15    -- one charge's recharge

local W = NS.SimWorld
local L = NS.L
local UNITS = { "target", "focus" }
local UNIT_EVENT = { target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED" }
-- Each unit's detail lines: set to an enemy, and cleared.
local UNIT_TEXT = {
    target = { set = L["target: %s"], clear = L["target cleared"] },
    focus  = { set = L["focus: %s"], clear = L["focus cleared"] },
}

-- ── helpers ───────────────────────────────────────────────────────────────────────────────────

local function world() return NS.SimHost and NS.SimHost.world end
local function now() return _G.GetTime() end
local function fire(event, ...) return NS.Sim:Fire(event, ...) end

--- One `[sim]` narration line through the addon's printer (NS.SimHost: core/SimSetup.lua made it).
NS.SimHost = NS.SimHost or {}
function NS.SimHost.Say(line)
    NS.Util.print(L["[sim] %s"]:format(line))
end
local function say(line) return NS.SimHost.Say(line) end

local guidSeq = 0
--- A fresh cast GUID, "Cast-sim-<n>".
local function newGuid()
    guidSeq = guidSeq + 1
    return "Cast-sim-" .. guidSeq
end

--- A spell's live name, or its id as text.
local function spellName(id)
    local name = id and NS.Compat.GetSpellInfo(id)
    if type(name) == "string" and name ~= "" then return name end
    return tostring(id)
end

--- The scenario's data for `key` in table `field` (PARTY / ENEMIES), read at call time.
local function scenarioRow(field, key)
    local sc = NS.SimScenario
    local t = sc and sc[field]
    return type(t) == "table" and t[key] or nil
end

--- Enemy `key`, added (named from the scenario) on first sight.
local function enemy(key)
    local w = world()
    if not (w and key ~= nil) then return nil end
    if not w.enemies[key] then
        local row = scenarioRow("ENEMIES", key)
        W.AddEnemy(key, { name = row and row.name or tostring(key) })
    end
    return w.enemies[key]
end

local function enemyName(key)
    local e = enemy(key)
    return e and e.name or tostring(key)
end

--- The units ("target", "focus") showing enemy `key` now, in that order.
local function unitsShowing(key)
    local w, out = world(), {}
    if not w then return out end
    for _, unit in ipairs(UNITS) do
        if w.units[unit] == key then out[#out + 1] = unit end
    end
    return out
end

--- The live cast of enemy `key`, or nil.
local function castOf(key)
    local e = enemy(key)
    return e and not e.dead and e.cast or nil
end

--- Fire `event` (unit, castGUID, spellID) for every unit showing enemy `key`.
local function fireCast(event, key, cast)
    for _, unit in ipairs(unitsShowing(key)) do fire(event, unit, cast.castGUID, cast.spellID) end
end

local function stopEvent(cast)
    return cast.isChannel and "UNIT_SPELLCAST_CHANNEL_STOP" or "UNIT_SPELLCAST_STOP"
end

--- A role word ("kick" / "cc") resolved to the host's spell; a number passes through.
local function resolveSpell(role)
    if type(role) == "number" then return role end
    local host = NS.SimHost
    if role == "kick" then return host and host.kick end
    if role == "cc" then return host and host.cc end
    return nil
end

--- The seconds spell `id` stays unusable, or nil when it can be cast now (a charge left counts).
local function lockedFor(id)
    local w = world()
    local s = w and w.spells[id]
    if not s then return nil end
    local t, ends = now(), nil
    if s.maxCharges then
        if s.charges > 0 then return nil end
        ends = (s.chargeStart or 0) + (s.chargeDuration or 0)
    elseif s.start then
        ends = s.start + s.duration
    end
    if ends and ends > t then return ends - t end
    return nil
end

--- Spend spell `id`: a charge for a charge spell (then CHARGES fires too), else a `cd` cooldown.
--- Answers whether it was a charge spell.
local function spend(id, cd)
    local w = world()
    local s = w and w.spells[id]
    if s and s.maxCharges then
        W.UseCharge(id, D.RECHARGE)
        return true
    end
    W.StartCooldown(id, cd)
    return false
end

-- ── combat and unit changes ───────────────────────────────────────────────────────────────────

EVENTS.Combat = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
function DRIVERS.Combat(step)
    local on = step.on ~= false
    W.SetCombat(on)
    local session = NS.Sim:Session()
    if session then session.simCombat = on end
    fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    return on and L["in combat"] or L["out of combat"]
end

--- Point `unit` at step.enemy (nil clears) and fire its change event.
local function setUnit(unit, key)
    if key ~= nil then enemy(key) end
    W.SetUnit(unit, key)
    fire(UNIT_EVENT[unit])
    if key == nil then return UNIT_TEXT[unit].clear end
    return UNIT_TEXT[unit].set:format(enemyName(key))
end

EVENTS.Setup = { "SPELL_UPDATE_CHARGES" }
--- The scenario's opening state: your kick gets step.charges charges (the `boss` scenario's two),
--- all ready, then SPELL_UPDATE_CHARGES so the badge shows them.
function DRIVERS.Setup(step)
    local id = resolveSpell("kick")
    if not id then return L["no kick tracked"] end
    W.SetCharges(id, tonumber(step.charges) or 2)
    fire("SPELL_UPDATE_CHARGES")
    return L["%s: %d charges"]:format(spellName(id), tonumber(step.charges) or 2)
end

EVENTS.Target = { "PLAYER_TARGET_CHANGED" }
function DRIVERS.Target(step) return setUnit("target", step.enemy) end

EVENTS.Focus = { "PLAYER_FOCUS_CHANGED" }
function DRIVERS.Focus(step) return setUnit("focus", step.enemy) end

-- ── an enemy cast begins or changes ───────────────────────────────────────────────────────────

--- Start step's cast (a channel when `isChannel`) on step.enemy and fire `event` per unit.
local function startCast(step, isChannel, event, detailFmt)
    local key = step.enemy
    if not enemy(key) then return L["no enemy"] end
    local name, texture = NS.Compat.GetSpellInfo(step.spell)
    W.StartCast(key, {
        spellID = step.spell, name = name, texture = texture, duration = step.duration,
        notInterruptible = step.uninterruptible, isChannel = isChannel, castGUID = newGuid(),
    })
    fireCast(event, key, castOf(key))
    return detailFmt:format(enemyName(key), spellName(step.spell))
end

EVENTS.CastStart = { "UNIT_SPELLCAST_START" }
function DRIVERS.CastStart(step) return startCast(step, false, "UNIT_SPELLCAST_START", L["%s casts %s"]) end

EVENTS.ChannelStart = { "UNIT_SPELLCAST_CHANNEL_START" }
function DRIVERS.ChannelStart(step)
    return startCast(step, true, "UNIT_SPELLCAST_CHANNEL_START", L["%s channels %s"])
end

EVENTS.Interruptible = { "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }
--- The shield breaks (default) or, with `interruptible = false`, comes up.
function DRIVERS.Interruptible(step)
    local key = step.enemy
    if not castOf(key) then return L["no cast"] end
    local on = step.interruptible ~= false
    W.SetInterruptible(key, on)
    local event = on and "UNIT_SPELLCAST_INTERRUPTIBLE" or "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
    for _, unit in ipairs(unitsShowing(key)) do fire(event, unit) end
    return on and L["interruptible"] or L["not interruptible"]
end

-- ── the player's kick ─────────────────────────────────────────────────────────────────────────

--- Which branch a kick at enemy `key` takes now: "nokick", "nocast", "immune", "cooldown" (with the
--- seconds left) or "land".
function D.KickBranch(key, kickID)
    if not kickID then return "nokick" end
    local cast = castOf(key)
    if not cast then return "nocast" end
    if cast.notInterruptible then return "immune" end
    local left = lockedFor(kickID)
    if left then return "cooldown", left end
    return "land"
end

--- The kick lands: spend it, fire the player's cast and the cooldown update(s), then end the
--- enemy's cast with INTERRUPTED (or CHANNEL_STOP) on every unit showing it.
local function kickLands(key, kickID)
    local cast = castOf(key)
    local charged = spend(kickID, D.KICK_CD)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", newGuid(), kickID)
    fire("SPELL_UPDATE_COOLDOWN")
    if charged then fire("SPELL_UPDATE_CHARGES") end
    W.EndCast(key)
    fireCast(cast.isChannel and "UNIT_SPELLCAST_CHANNEL_STOP" or "UNIT_SPELLCAST_INTERRUPTED", key, cast)
    return L["kicked %s"]:format(enemyName(key))
end

local KICK_REFUSED = {
    nokick = function()
        say(L["No kick is tracked, so nothing is kicked."])
        return L["no kick tracked"]
    end,
    nocast = function(key, kickID)
        say(L["%s: %s is not casting, so there is nothing to kick."]:format(spellName(kickID), enemyName(key)))
        return L["no cast"]
    end,
    immune = function(key, kickID)
        say(L["%s: %s's cast is uninterruptible."]:format(spellName(kickID), enemyName(key)))
        return L["uninterruptible"]
    end,
    cooldown = function(_, kickID, left)
        say(L["%s: your kick is on cooldown (%ds)."]:format(spellName(kickID), math.ceil(left)))
        return L["on cooldown"]
    end,
}

EVENTS.Kick = { "UNIT_SPELLCAST_SUCCEEDED", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }
function DRIVERS.Kick(step)
    local key, kickID = step.enemy, resolveSpell("kick")
    local branch, left = D.KickBranch(key, kickID)
    if branch == "land" then return kickLands(key, kickID) end
    return KICK_REFUSED[branch](key, kickID, left)
end

-- ── a party member's kick, a completed cast, crowd control ────────────────────────────────────

--- Party member `key`'s name, spec word and kick spell (scenario data; the key when absent).
local function member(key)
    local row = scenarioRow("PARTY", key) or {}
    return row.name or tostring(key), row.spec or "?", row.spell or row.kick
end

EVENTS.PartyKick = { "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }
function DRIVERS.PartyKick(step)
    local name, spec, spell = member(step.member)
    local key = step.enemy
    local cast = castOf(key)
    if not cast then
        say(L["%s (%s) has nothing to interrupt on %s."]:format(name, spec, enemyName(key)))
        return L["no cast"]
    end
    say(L["%s (%s) interrupts %s with %s."]:format(name, spec, enemyName(key), spellName(spell)))
    W.EndCast(key)
    fireCast(cast.isChannel and "UNIT_SPELLCAST_CHANNEL_STOP" or "UNIT_SPELLCAST_INTERRUPTED", key, cast)
    return L["%s interrupts"]:format(name)
end

EVENTS.Complete = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP" }
function DRIVERS.Complete(step)
    local key = step.enemy
    local cast = castOf(key)
    if not cast then return L["no cast"] end
    W.EndCast(key)
    fireCast("UNIT_SPELLCAST_SUCCEEDED", key, cast)
    fireCast(stopEvent(cast), key, cast)
    return L["%s completes %s"]:format(enemyName(key), cast.name)
end

EVENTS.Cc = { "UNIT_SPELLCAST_SUCCEEDED", "SPELL_UPDATE_COOLDOWN" }
function DRIVERS.Cc(step)
    local key, ccID = step.enemy, resolveSpell("cc")
    if not ccID then
        say(L["No crowd control is tracked, so nothing is cast on %s."]:format(enemyName(key)))
        return L["no crowd control tracked"]
    end
    local left = lockedFor(ccID)
    if left then
        say(L["%s is on cooldown (%ds)."]:format(spellName(ccID), math.ceil(left)))
        return L["on cooldown"]
    end
    W.StartCooldown(ccID, D.CC_CD)
    W.StartGcd(D.GCD)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", newGuid(), ccID)
    fire("SPELL_UPDATE_COOLDOWN")
    say(L["You use %s on %s."]:format(spellName(ccID), enemyName(key)))
    return L["%s used"]:format(spellName(ccID))
end

-- ── other world changes ───────────────────────────────────────────────────────────────────────

EVENTS.Die = { "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED" }
--- Enemy dies: its cast ends (STOP while the units still show it), then every unit showing it
--- clears, each with its change event.
function DRIVERS.Die(step)
    local key = step.enemy
    local cast = castOf(key)
    W.Kill(key)
    if cast then fireCast(stopEvent(cast), key, cast) end
    for _, unit in ipairs(unitsShowing(key)) do
        W.SetUnit(unit, nil)
        fire(UNIT_EVENT[unit])
    end
    return L["%s dies"]:format(enemyName(key))
end

EVENTS.Leave = { "GROUP_ROSTER_UPDATE" }
--- A party member leaves: narration, then the roster update (KickCD has no handler: delivered for
--- fidelity, it reaches none and the interference watch never sees it).
function DRIVERS.Leave(step)
    local name, spec = member(step.member)
    say(L["%s (%s) leaves the party."]:format(name, spec))
    fire("GROUP_ROSTER_UPDATE")
    return L["%s left"]:format(name)
end

EVENTS.Expire = { "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_COOLDOWN" }
--- Compressed time: spell step.spell ("kick" / "cc" / an id) comes back now, its timer canceled.
function DRIVERS.Expire(step)
    local id = resolveSpell(step.spell)
    if not id then return L["no spell"] end
    local w = world()
    local s = w and w.spells[id]
    W.ClearCooldown(id)
    if s and s.maxCharges then fire("SPELL_UPDATE_CHARGES") end
    fire("SPELL_UPDATE_COOLDOWN")
    return L["%s ready"]:format(spellName(id))
end
