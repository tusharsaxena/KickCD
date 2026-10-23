local _, NS = ...
-- modules/SimWorld.lua — the simulated world and its seam providers (KickCD#38, KC-04; the Sim
-- major's host contract H1; design-kc-sim §5.1-5.2).
--
-- THE WORLD. One table on NS.SimHost.world (the host's own table, never the library instance),
-- built by Build() when a session prepares and dropped when it stops:
--
--   units    { target = enemyKey|nil, focus = enemyKey|nil }
--   enemies  [key] = { key, name, hostile, dead, cast = nil|{ spellID, name, texture,
--                      notInterruptible, isChannel, start, duration, castID } }
--            shared by key, so target and focus can be the same mob
--   spells   [id] = { start, duration, offGcd, maxCharges, charges, chargeStart, chargeDuration,
--                     recharge }
--   gcd      nil|{ start, duration }
--   combat   true while the simulation has put the player in combat
--   timers   [id] = the expiry handle NS.Sim:After answered ("gcd" for the GCD)
--
-- THE MUTATORS are pure world edits: they fire nothing (the drivers fire, in client order). The one
-- exception is time running out: a cooldown, a recharge or the GCD schedules its expiry with
-- NS.Sim:After, never a raw client timer, so the timers die with the session. The expiry clears the
-- state and fires what the client fires then. Every mutator is a no-op with no world installed.
--
-- THE CLOCK is GetTime(), read directly: it is not an answer the seam owns. The world reads nothing
-- else from the client.
--
-- THE PROVIDERS are registered ONCE, at file load, on NS.SimSeam (core/SimSetup.lua). The seam
-- calls one only while a session is active; each reads NS.SimHost.world at call time and answers
-- fallback(...) (the live member) when there is none. Spell identity is NOT provided:
-- GetSpellInfo, GetSpellTexture, IsSpellAvailable and GetSpecialization* answer live, the player's
-- real spells (design D4). Compat.GetCastingInfo / GetChannelInfo need no provider: they compose
-- from the wrapped raw readers below (core/Compat.lua).

NS.SimWorld = NS.SimWorld or {}
local W = NS.SimWorld

-- A cast the step gave no texture: the client's question-mark icon.
local DEFAULT_TEXTURE = 134400

local function now() return _G.GetTime() end
local function world() return NS.SimHost and NS.SimHost.world end
local function newDuration(start, dur) return NS.Compat.NewDuration(start, dur) end

--- Fire `event` through the session (NS.Sim resolved at call time: modules/Sim.lua replaces it).
local function fire(event)
    if NS.Sim and NS.Sim.Fire then NS.Sim:Fire(event) end
end

--- Schedule fn after `delay` seconds through the session; nil when there is none.
local function after(delay, fn)
    if NS.Sim and NS.Sim.After then return NS.Sim:After(delay, fn) end
    return nil
end

local function cancel(w, key)
    local h = w.timers[key]
    w.timers[key] = nil
    if h and h.Cancel then h:Cancel() end
end

--- The spell's record, created on first write.
local function spellOf(w, id)
    local s = w.spells[id]
    if not s then
        s = {}
        w.spells[id] = s
    end
    return s
end

-- ── the world ─────────────────────────────────────────────────────────────────────────────────

--- A fresh, empty world. `opts` is reserved for the session's prepare; nothing reads it yet.
function W.Build(_)
    return { units = {}, enemies = {}, spells = {}, gcd = nil, combat = false, timers = {}, castSeq = 0 }
end

--- Whether the client can build the duration objects the world answers (design D5).
function W.CanBuild()
    return newDuration(now(), 1) ~= nil
end

-- ── units and casts ───────────────────────────────────────────────────────────────────────────

--- Add (or reshape) enemy `key`. `info` = { name, hostile }; hostile defaults to true.
function W.AddEnemy(key, info)
    local w = world()
    if not (w and key ~= nil) then return end
    info = info or {}
    local e = w.enemies[key] or { key = key, dead = false }
    e.name = info.name or e.name or tostring(key)
    if info.hostile ~= nil then e.hostile = info.hostile and true or false
    elseif e.hostile == nil then e.hostile = true end
    w.enemies[key] = e
end

--- Point `unit` ("target" / "focus") at enemy `key`, adding a hostile one if it is new; nil clears.
function W.SetUnit(unit, key)
    local w = world()
    if not w then return end
    if key ~= nil and not w.enemies[key] then W.AddEnemy(key, {}) end
    w.units[unit] = key
end

--- Enemy `key` dies: its cast ends with it.
function W.Kill(key)
    local w = world()
    local e = w and w.enemies[key]
    if not e then return end
    e.dead, e.cast = true, nil
end

--- Enemy `key` starts `cast` = { spellID, name, texture, duration, notInterruptible, isChannel } now.
function W.StartCast(key, cast)
    local w = world()
    local e = w and w.enemies[key]
    if not (e and cast) then return end
    w.castSeq = (w.castSeq or 0) + 1
    e.cast = {
        spellID = cast.spellID, name = cast.name or "?", texture = cast.texture or DEFAULT_TEXTURE,
        notInterruptible = cast.notInterruptible and true or false, isChannel = cast.isChannel and true or false,
        start = now(), duration = tonumber(cast.duration) or 0, castID = w.castSeq,
    }
end

--- Enemy `key`'s cast ends (kicked, completed or stopped).
function W.EndCast(key)
    local w = world()
    local e = w and w.enemies[key]
    if e then e.cast = nil end
end

--- Enemy `key`'s cast becomes interruptible (true) or not (false).
function W.SetInterruptible(key, interruptible)
    local w = world()
    local e = w and w.enemies[key]
    if e and e.cast then e.cast.notInterruptible = not interruptible end
end

-- ── cooldowns, the GCD and charges ────────────────────────────────────────────────────────────

--- Spell `id` goes on a `dur`-second cooldown now; its expiry fires SPELL_UPDATE_COOLDOWN.
function W.StartCooldown(id, dur)
    local w = world()
    if not w then return end
    local s = spellOf(w, id)
    s.start, s.duration = now(), tonumber(dur) or 0
    cancel(w, id)
    w.timers[id] = after(s.duration, function()
        w.timers[id] = nil
        s.start, s.duration = nil, nil
        fire("SPELL_UPDATE_COOLDOWN")
    end)
end

--- Spell `id`'s cooldown (and any recharge) ends at once, its timer canceled: the drivers'
--- compressed expiry. Fires nothing; a charge spell is back to full.
function W.ClearCooldown(id)
    local w = world()
    if not w then return end
    cancel(w, id)
    local s = w.spells[id]
    if not s then return end
    s.start, s.duration = nil, nil
    if s.maxCharges then s.charges, s.chargeStart, s.chargeDuration = s.maxCharges, 0, 0 end
end

--- The global cooldown runs `dur` seconds from now; its end fires SPELL_UPDATE_COOLDOWN.
function W.StartGcd(dur)
    local w = world()
    if not w then return end
    local gcd = { start = now(), duration = tonumber(dur) or 0 }
    w.gcd = gcd
    cancel(w, "gcd")
    w.timers.gcd = after(gcd.duration, function()
        w.timers.gcd = nil
        if w.gcd == gcd then w.gcd = nil end
        fire("SPELL_UPDATE_COOLDOWN")
    end)
end

--- Spell `id` is off the GCD: a running GCD never shows on it.
function W.MarkOffGcd(id)
    local w = world()
    if w then spellOf(w, id).offGcd = true end
end

--- Spell `id` has `max` charges, all of them ready.
function W.SetCharges(id, max)
    local w = world()
    if not w then return end
    local s = spellOf(w, id)
    cancel(w, id)
    s.maxCharges, s.charges, s.chargeStart, s.chargeDuration = max, max, 0, 0
end

--- Start the next recharge of charge spell `s` (`id`) now, unless one is running or it is full.
local function startRecharge(w, id, s)
    if w.timers[id] or s.charges >= s.maxCharges then return end
    s.chargeStart, s.chargeDuration = now(), s.recharge
    w.timers[id] = after(s.recharge, function()
        w.timers[id] = nil
        s.charges = math.min(s.maxCharges, s.charges + 1)
        s.chargeStart, s.chargeDuration = 0, 0
        startRecharge(w, id, s)
        fire("SPELL_UPDATE_CHARGES")
        fire("SPELL_UPDATE_COOLDOWN")
    end)
end

--- Spend one charge of spell `id`; a charge comes back every `recharge` seconds, one at a time.
function W.UseCharge(id, recharge)
    local w = world()
    local s = w and w.spells[id]
    if not (s and s.maxCharges and s.charges > 0) then return end
    s.charges = s.charges - 1
    s.recharge = tonumber(recharge) or s.recharge or 0
    startRecharge(w, id, s)
end

-- ── the answers ───────────────────────────────────────────────────────────────────────────────

--- The cooldown spell `id` shows now: start, duration (both nil when ready). The later-ending of
--- its own cooldown (a 0-charge lockout counts) and, for an on-GCD spell, the GCD.
local function cooldownOf(w, id)
    local t, s = now(), w.spells[id]
    local start, dur
    if s and s.start and t < s.start + s.duration then
        start, dur = s.start, s.duration
    elseif s and s.maxCharges and s.charges == 0 and s.chargeStart then
        start, dur = s.chargeStart, s.chargeDuration
    end
    local g = w.gcd
    if g and not (s and s.offGcd) and t < g.start + g.duration
        and (not start or g.start + g.duration > start + dur) then
        start, dur = g.start, g.duration
    end
    return start, dur
end

--- The enemy on `unit` (target / focus), or nil.
local function enemyOn(w, unit)
    local key = w.units[unit]
    return key ~= nil and w.enemies[key] or nil
end

--- The client's positional returns for `cast`: UnitCastingInfo's nine (castID at 7,
--- notInterruptible at 8, spellID at 9), or UnitChannelInfo's eight (notInterruptible at 7,
--- spellID at 8).
local function castTuple(cast, isChannel)
    local startMS, endMS = cast.start * 1000, (cast.start + cast.duration) * 1000
    if isChannel then
        return cast.name, cast.name, cast.texture, startMS, endMS, false, cast.notInterruptible, cast.spellID
    end
    return cast.name, cast.name, cast.texture, startMS, endMS, false, cast.castID, cast.notInterruptible,
        cast.spellID
end

--- The cast of the given kind in progress on `unit`, or nil.
local function castOn(w, unit, isChannel)
    local e = enemyOn(w, unit)
    local cast = e and not e.dead and e.cast
    if cast and cast.isChannel == isChannel then return cast end
    return nil
end

local P = {}

function P.GetSpellCooldown(fallback, id, ...)
    local w = world()
    if not w then return fallback(id, ...) end
    local start, dur = cooldownOf(w, id)
    if start then return start, dur, true, 1, true end
    return 0, 0, false, 1, false
end

function P.GetSpellCooldownDuration(fallback, id, ...)
    local w = world()
    if not w then return fallback(id, ...) end
    local start, dur = cooldownOf(w, id)
    if start then return newDuration(start, dur) end
    return newDuration(0, 0)
end

function P.GetSpellCharges(fallback, id, ...)
    local w = world()
    if not w then return fallback(id, ...) end
    local s = w.spells[id]
    if not (s and s.maxCharges) then return nil end
    return s.charges, s.maxCharges, s.chargeStart or 0, s.chargeDuration or 0
end

function P.IsSpellUsable(fallback, ...)
    if not world() then return fallback(...) end
    return true, false
end

function P.UnitExists(fallback, unit, ...)
    local w = world()
    if not w then return fallback(unit, ...) end
    if unit == "player" then return true end
    return enemyOn(w, unit) ~= nil
end

function P.UnitCanAttack(fallback, unit, ...)
    local w = world()
    if not w then return fallback(unit, ...) end
    local e = enemyOn(w, unit)
    return e ~= nil and e.hostile == true
end

function P.UnitIsDead(fallback, unit, ...)
    local w = world()
    if not w then return fallback(unit, ...) end
    local e = enemyOn(w, unit)
    return e ~= nil and e.dead == true
end

function P.UnitCastingInfo(fallback, unit, ...)
    local w = world()
    if not w then return fallback(unit, ...) end
    local cast = castOn(w, unit, false)
    if cast then return castTuple(cast, false) end
    return nil
end

function P.UnitChannelInfo(fallback, unit, ...)
    local w = world()
    if not w then return fallback(unit, ...) end
    local cast = castOn(w, unit, true)
    if cast then return castTuple(cast, true) end
    return nil
end

function P.UnitCastingDuration(fallback, unit, ...)
    local w = world()
    if not w then return fallback(unit, ...) end
    local cast = castOn(w, unit, false)
    return cast and newDuration(cast.start, cast.duration) or nil
end

function P.UnitChannelDuration(fallback, unit, ...)
    local w = world()
    if not w then return fallback(unit, ...) end
    local cast = castOn(w, unit, true)
    return cast and newDuration(cast.start, cast.duration) or nil
end

-- The keys, in a fixed order (the provider table is iterated only here).
W.PROVIDED = {
    "GetSpellCooldown", "GetSpellCooldownDuration", "GetSpellCharges", "IsSpellUsable",
    "UnitExists", "UnitCanAttack", "UnitIsDead",
    "UnitCastingInfo", "UnitChannelInfo", "UnitCastingDuration", "UnitChannelDuration",
}

if NS.SimSeam and NS.SimSeam.SetProvider then
    for _, key in ipairs(W.PROVIDED) do NS.SimSeam:SetProvider(key, P[key]) end
end
