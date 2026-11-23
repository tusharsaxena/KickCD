local _, NS = ...
NS.Probe = NS.Probe or {}
local P = NS.Probe

-- modules/Probe.lua -- the WoW Forever port's probe verbs (MKF-KC-16; Ka0sAddonsCommonTasks
-- docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT, the design's "Probe verbs"; the rulings R3 and R4
-- of 2026-11-22: probe verbs, safe defaults, a contradiction becomes a follow-up). LootHistory's
-- modules/Probe.lua is the shape this follows.
--
-- `/kcd debug probe start|stop|status|clear` (core/KickCD.lua's DEBUG_COMMANDS). While started, this
-- file records the client facts the port's safe defaults rest on into ONE capped table under
-- `db.global.probe` inside KickCDDB (never a new SavedVariables global), stamped with the client
-- key, its version and build, and the addon's version. The owner plays, logs out, and the lead reads
-- `WTF/Account/<acct>/SavedVariables/KickCD.lua`. docs/forever-probes.md maps each recorded kind
-- to the unknown it answers (the research's U14-U25) and keeps the `/run` lines as the fallback.
--
-- WHAT IT RECORDS. A `start` entry: the cast-bar game rule and the game mode (U14, U23), whether
-- the global cooldown spell 61304 answers (U21), the deprecation fallbacks (U25), the class loop's
-- answers (U19), the spec reads (U18), every Forever rank family's answers and the rank the resolver
-- picks (U15), the rune spells (U24), the form and Feral Charge's override (U16), the live spell
-- list's rows, whether the Cooldown Manager exists, and the kick's cooldown secrecy (U20). Then, as
-- the client sends them: every target or focus cast with its interrupt flag as nil, plain or secret
-- (U14), each of the player's casts and, a moment later, the kick's cooldown and usability, so a GCD
-- after an instant shows (U21, the critic's C2), each form change (U16), each spellbook change whose
-- answers moved (the pet's Spell Lock, U17), each pull's cooldown secrecy (U20) and each zone-in's
-- game mode (U23).
--
-- WHAT IT IS NOT. Session-only: a reload or relog stops it (the record stays; start it again), like
-- the debug flag. It is not a capture path: it registers on a private frame, never through
-- NS.RegisterEventList, so no simulated event reaches it and it changes nothing the addon draws. It
-- records nothing while a simulation runs (the start refuses; an entry during one is dropped), so
-- every fact is the live client's. Every value passes `plain` first: a secret, a function or a table
-- never reaches the SavedVariables, and a long string is cut at TEXT_MAX. The reads below are client
-- reads no handler of the addon makes, read here and nowhere else (the LootHistory precedent).

P.CAP = 500          -- entries kept; the oldest non-start goes first, counted in `dropped`
P.TEXT_MAX = 400     -- a recorded string is cut here
P.AFTER_CAST = 0.1   -- seconds after the player's cast that the kick's cooldown is read again
P.GCD_SPELL = 61304
P.FERAL_CHARGE = 1238122
P.RUNES = { 425609, 410176 }      -- Rebuke and Skull Bash (runes, U24)
P.SPELL_LOCK = { 19244, 19647 }   -- the Felhunter's Spell Lock ranks (U17)
P.CLASS_SCAN = 13                 -- class ids the start entry asks GetClassInfo for
local BANK_PLAYER, BANK_PET = 0, 1

-- Every event the probe registers while started, in the order docs/forever-probes.md lists them.
P.EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_SUCCEEDED", "UPDATE_SHAPESHIFT_FORM",
    "SPELLS_CHANGED", "UNIT_PET", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED",
    "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
}

local CAST_UNITS = { target = true, focus = true }

local Compat = NS.Compat
local state = { running = false, frame = nil, timers = {}, rejected = {}, lastBook = nil }
P._state = state

-- ── values ────────────────────────────────────────────────────────────────────────────────

--- A value safe to keep in the SavedVariables: a boolean, a number, a string (cut at TEXT_MAX), or
--- nil. A secret of any type answers NS.SECRET (asked first, so a secret boolean is caught too); a
--- table, a function or anything else answers its type in angle brackets.
function P.plain(v)
    if v == nil then return nil end
    if Compat.IsSecret(v) then return NS.SECRET end
    local kind = type(v)
    if kind == "boolean" or kind == "number" then return v end
    if kind == "string" then return #v > P.TEXT_MAX and v:sub(1, P.TEXT_MAX) or v end
    return "<" .. kind .. ">"
end
local plain = P.plain

--- The first answer of `fn(...)` through `plain`; nil when `fn` is not a function, and
--- "<error>" when it raised, so an absent API reads as absent and a raise costs one field.
local function one(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return "<error>" end
    return plain(v)
end

local function packed(...) return { n = select("#", ...), ... } end

--- Every answer of `fn(...)` through `plain`, as an array with `n` (a nil kept as a hole); nil when
--- `fn` is no function, `{ err = ... }` when it raised.
local function all(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = packed(pcall(fn, ...))
    if not res[1] then return { err = plain(tostring(res[2])) } end
    local out = { n = res.n - 1 }
    for i = 1, out.n do out[i] = plain(res[i + 1]) end
    return out
end

local function present(v)
    if v == nil then return "absent" end
    return type(v)
end

--- A table's named fields through `plain`, or nil when `t` is no table.
local function fields(t, keys)
    if type(t) ~= "table" or Compat.IsSecret(t) then return nil end
    local out = {}
    for _, k in ipairs(keys) do out[k] = plain(t[k]) end
    return out
end

local function member(ns, name)
    local t = _G[ns]
    return type(t) == "table" and t[name] or nil
end

-- ── the store ─────────────────────────────────────────────────────────────────────────────

--- The probe table, made on first need when `create`, or nil before the database exists.
function P.Store(create)
    local g = NS.db and NS.db.global
    if not g then return nil end
    if g.probe == nil and create then g.probe = { entries = {}, dropped = 0 } end
    return g.probe
end

--- Stamp the table with the client that is answering: its key, version and build (a STAMP, never a
--- test: clients-§3 bans choosing behavior by a build), and the addon's version.
local function stamp(store)
    local build = all(_G.GetBuildInfo) or {}
    store.client, store.version, store.build = plain(Compat.ClientKey()), build[1], build[2]
    store.addonVersion = plain(NS.Version and NS.Version() or nil)
end

-- The oldest entry the cap may drop: the first that is not a `start` one, so a long session never
-- pushes the facts read once per start out; with nothing else left, the oldest entry goes.
local function oldestDroppable(list)
    for i, e in ipairs(list) do
        if e.kind ~= "start" then return i end
    end
    return 1
end

local function simActive()
    local sim = NS.Sim
    return sim ~= nil and type(sim.IsActive) == "function" and sim:IsActive() == true
end

--- Append one entry; drop the oldest non-start entry past CAP. Nothing while stopped or while a
--- simulation runs. Answers the entry, or nil.
function P.Record(kind, entry)
    if not state.running or simActive() then return nil end
    local store = P.Store(true)
    if not store then return nil end
    entry = entry or {}
    entry.kind, entry.t = kind, _G.time and _G.time() or 0
    local list = store.entries
    list[#list + 1] = entry
    while #list > P.CAP do
        table.remove(list, oldestDroppable(list))
        store.dropped = (store.dropped or 0) + 1
    end
    return entry
end

-- ── the facts ─────────────────────────────────────────────────────────────────────────────

--- "Your kick": the first usable interrupt of the live list, resolved (modules/Sim.lua's rule).
local function liveKick()
    local Host = NS.SimHost
    if not (Host and Host.ResolveSpells) then return nil end
    local ok, kick = pcall(Host.ResolveSpells)
    return ok and kick or nil
end

--- A spell's cooldown answers, field by field, or nil.
local function cooldownOf(id)
    local fn = member("C_Spell", "GetSpellCooldown")
    if type(id) ~= "number" or type(fn) ~= "function" then return nil end
    local ok, cd = pcall(fn, id)
    return ok and fields(cd, { "isActive", "isOnGCD", "isEnabled", "startTime", "duration" }) or nil
end

-- U14, U23: the cast-bar game rule, the game mode and the cast bar CVar.
local function rulesFacts()
    local rule = _G.Enum and _G.Enum.GameRule and _G.Enum.GameRule.TargetCastBarDisabled
    return {
        targetCastBarDisabled = rule ~= nil and one(member("C_GameRules", "IsGameRuleActive"), rule) or "absent",
        gameMode = one(member("C_GameRules", "GetActiveGameMode")),
        showTargetCastbar = one(_G.GetCVar, "showTargetCastbar"),
    }
end

-- U21: whether the global cooldown spell answers at all.
local function gcdFacts()
    local fn = member("C_Spell", "GetSpellCooldown")
    local ok, cd = false, nil
    if type(fn) == "function" then ok, cd = pcall(fn, P.GCD_SPELL) end
    return { answers = ok and type(cd) == "table", cooldown = ok and fields(cd, { "isActive", "duration" }) or nil }
end

-- U25: the deprecation fallbacks and the shims they carry.
local function deprecationFacts()
    return {
        loadDeprecationFallbacks = one(_G.GetCVar, "loadDeprecationFallbacks"),
        IsPlayerSpell = present(_G.IsPlayerSpell), IsSpellKnown = present(_G.IsSpellKnown),
        GetNumSpecializationsForClassID = present(_G.GetNumSpecializationsForClassID),
    }
end

-- U19: GetNumClasses, what GetClassInfo answers per id, and Forever's class id list.
local function classFacts()
    local info = {}
    for id = 1, P.CLASS_SCAN do
        local row = all(_G.GetClassInfo, id)
        if row and row[2] ~= nil then info[id] = { name = row[1], file = row[2], id = row[3] } end
    end
    local ids = {}
    local fn = member("C_SpecializationInfo", "GetAllClassIDs")
    local ok, list = false, nil
    if type(fn) == "function" then ok, list = pcall(fn) end
    if ok and type(list) == "table" then
        for i, v in ipairs(list) do ids[i] = plain(v) end
    end
    return { numClasses = one(_G.GetNumClasses), info = info, allClassIDs = ok and ids or "absent" }
end

-- U18: the spec reads, and the spec id the addon keys the player's list on.
local function specFacts()
    local index = Compat.GetSpecialization and Compat.GetSpecialization() or nil
    return {
        index = plain(index), info = index and all(Compat.GetSpecializationInfo, index) or nil,
        playerSpecID = plain(NS.Util.PlayerSpecID()), level = one(_G.UnitLevel, "player"),
        classFile = (all(_G.UnitClass, "player") or {})[2],
    }
end

local function bookAnswer(id, bank)
    return one(member("C_SpellBook", "IsSpellInSpellBook"), id, bank, false)
end

-- U15: every Forever rank family's answers, rank by rank, and the rank the resolver picks.
local function rankFacts()
    local out = {}
    for family, ids in pairs(NS.SpellRanksForever or {}) do
        local ranks = {}
        for i, id in ipairs(ids) do
            ranks[i] = { id = id, known = one(member("C_SpellBook", "IsSpellKnown"), id, BANK_PLAYER),
                inBook = bookAnswer(id, BANK_PLAYER), pet = bookAnswer(id, BANK_PET) }
        end
        out[family] = { resolved = plain(NS.SpellRanks.Resolve(family)), ranks = ranks }
    end
    return out
end

-- U24: whether the rune spells are known.
local function runeFacts()
    local out = {}
    for _, id in ipairs(P.RUNES) do out[id] = one(member("C_SpellBook", "IsSpellKnown"), id, BANK_PLAYER) end
    return out
end

-- U16: the form, Feral Charge's override, whether the slot stays in the book, and its cooldown.
local function feralFacts()
    local override = Compat.GetOverrideSpell(P.FERAL_CHARGE)
    return {
        form = one(_G.GetShapeshiftFormID), override = plain(override),
        inBook = bookAnswer(P.FERAL_CHARGE, BANK_PLAYER), cooldown = cooldownOf(override or P.FERAL_CHARGE),
    }
end

-- The live list's rows: stored id, resolved id, whether available and usable, and any charges (P8).
local function spellFacts()
    local _, classFile = (_G.UnitClass or function() end)("player")
    local class = classFile and NS.Util.NormalizeClassToken(classFile)
    local spec = NS.Util.PlayerSpecID()
    local list = class and spec and NS.Database and NS.Database:GetSpellList(class, spec) or {}
    local R, out = NS.SpellRanks, {}
    for i, entry in ipairs(list) do
        local id = entry.spellID
        local resolved = R.Resolve(id)
        out[i] = { id = id, resolved = plain(resolved), category = plain(entry.category),
            available = plain(R.IsAvailable(id)), usable = plain(R.IsUsable(id)),
            maxCharges = plain((select(2, Compat.GetSpellCharges(resolved)))) }
    end
    return { class = class, spec = plain(spec), rows = out }
end

-- U20: the kick's cooldown secrecy, out of combat here and on each pull below.
local function secretFacts()
    local kick = liveKick()
    return { kick = kick, shouldBeSecret = kick and one(member("C_Secrets", "ShouldSpellCooldownBeSecret"), kick) or nil }
end

--- The `start` entry's facts. Each part is read under its own pcall, so one raise costs one part.
local START_PARTS = {
    { "rules", rulesFacts }, { "gcd", gcdFacts }, { "deprecation", deprecationFacts },
    { "classes", classFacts }, { "spec", specFacts }, { "ranks", rankFacts }, { "runes", runeFacts },
    { "feral", feralFacts }, { "spells", spellFacts }, { "secrets", secretFacts },
    { "viewer", function() return { present = type(_G.C_CooldownViewer) == "table" } end },
}
function P.StartFacts()
    local facts = {}
    for _, part in ipairs(START_PARTS) do
        local ok, v = pcall(part[2])
        facts[part[1]] = ok and v or { err = plain(tostring(v)) }
    end
    return facts
end

-- ── the handlers ──────────────────────────────────────────────────────────────────────────

-- The interrupt flag as a fact: "nil" for a plain nil (the nil guard rests on it), else the plain
-- boolean, else NS.SECRET.
local function flagFact(v)
    if v == nil then return "nil" end
    return plain(v)
end

--- A target's or focus's cast: its spell, its name and its interrupt flag (U14). Casting info
--- carries the flag at 8 and the spell at 9; channel info at 7 and 8. An event with no cast to read
--- is recorded as `none`.
local function castEvent(event, unit)
    if not CAST_UNITS[unit] then return end
    local channel = event == "UNIT_SPELLCAST_CHANNEL_START"
    local info = not channel and all(_G.UnitCastingInfo, unit) or nil
    if not (info and info[1] ~= nil) then info, channel = all(_G.UnitChannelInfo, unit), true end
    if not (info and info[1] ~= nil) then return P.Record("cast", { event = event, unit = unit, none = true }) end
    local flagAt, spellAt = channel and 7 or 8, channel and 8 or 9
    return P.Record("cast", { event = event, unit = unit, channel = channel, name = info[1],
        spellID = info[spellAt], flag = flagFact(info[flagAt]) })
end

local function cancelTimers()
    for i = #state.timers, 1, -1 do
        local h = state.timers[i]
        if h and h.Cancel then h:Cancel() end
        state.timers[i] = nil
    end
end

--- The player's cast; a moment later the kick's cooldown and usability (U21, the critic's C2).
local function playerCast(_, unit, _, spellID)
    if unit ~= "player" then return end
    P.Record("player", { spellID = plain(spellID) })
    local timer = _G.C_Timer
    if not (timer and timer.NewTimer) then return end
    state.timers[#state.timers + 1] = timer.NewTimer(P.AFTER_CAST, function()
        if not state.running then return end
        local kick = liveKick()
        P.Record("gcd", { after = plain(spellID), kick = kick, cooldown = cooldownOf(kick),
            usable = kick and one(member("C_Spell", "IsSpellUsable"), kick) or nil })
    end)
end

--- A spellbook change, recorded only when its answers moved: the pet's Spell Lock (U17), the
--- level, and Feral Charge in the book.
local function spellbookEvent(event)
    local pet = {}
    for _, id in ipairs(P.SPELL_LOCK) do pet[id] = bookAnswer(id, BANK_PET) end
    local level, feral = one(_G.UnitLevel, "player"), bookAnswer(P.FERAL_CHARGE, BANK_PLAYER)
    local sig = table.concat({ tostring(pet[19244]), tostring(pet[19647]), tostring(level), tostring(feral) }, ",")
    if sig == state.lastBook then return end
    state.lastBook = sig
    P.Record("spellbook", { event = event, pet = pet, level = level, feralInBook = feral })
end

--- A pull: the kick's cooldown secrecy and answers in combat (U20).
local function combatStart()
    local kick = liveKick()
    P.Record("combat", { kick = kick, cooldown = cooldownOf(kick),
        shouldBeSecret = kick and one(member("C_Secrets", "ShouldSpellCooldownBeSecret"), kick) or nil })
end

local HANDLERS = {
    UNIT_SPELLCAST_START = castEvent, UNIT_SPELLCAST_CHANNEL_START = castEvent,
    UNIT_SPELLCAST_INTERRUPTIBLE = castEvent, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = castEvent,
    UNIT_SPELLCAST_SUCCEEDED = playerCast,
    UPDATE_SHAPESHIFT_FORM = function() P.Record("form", { feral = feralFacts() }) end,
    SPELLS_CHANGED = spellbookEvent, UNIT_PET = spellbookEvent,
    PLAYER_LEVEL_UP = spellbookEvent, TRAIT_CONFIG_UPDATED = spellbookEvent,
    PLAYER_REGEN_DISABLED = combatStart,
    PLAYER_ENTERING_WORLD = function()
        P.Record("world", { gameMode = one(member("C_GameRules", "GetActiveGameMode")), instance = all(_G.GetInstanceInfo) })
    end,
}
P._handlers = HANDLERS

--- A client event reaching the probe frame. A raise is recorded as an entry, never thrown.
function P.OnEvent(event, ...)
    local fn = HANDLERS[event]
    if not (fn and state.running) then return end
    local ok, err = pcall(fn, event, ...)
    if not ok then P.Record("error", { event = event, err = plain(tostring(err)) }) end
end

-- ── the verbs ─────────────────────────────────────────────────────────────────────────────

local function frame()
    if not state.frame and type(_G.CreateFrame) == "function" then
        state.frame = _G.CreateFrame("Frame")
        state.frame:SetScript("OnEvent", function(_, event, ...) P.OnEvent(event, ...) end)
    end
    return state.frame
end

function P.IsRunning() return state.running end

--- Start recording. Answers false and a reason when it cannot.
function P.Start()
    if state.running then return false, "already running" end
    if simActive() then return false, "simulation" end
    local store = P.Store(true)
    local f = frame()
    if not (store and f) then return false, "unavailable" end
    stamp(store)
    store.started, store.stopped = _G.time and _G.time() or 0, nil
    state.running, state.lastBook = true, nil
    for _, event in ipairs(P.EVENTS) do NS.SafeRegisterEvent(f, event, nil, state.rejected) end
    local rejected = {}
    for i, name in ipairs(state.rejected) do rejected[i] = plain(name) end
    store.rejected = rejected
    P.Record("start", P.StartFacts())
    return true
end

--- Stop recording: every event unregistered, every pending read canceled.
function P.Stop()
    if not state.running then return false, "not running" end
    P.Record("stop", {})
    state.running = false
    local f = state.frame
    if f and f.UnregisterAllEvents then f:UnregisterAllEvents() end
    cancelTimers()
    local store = P.Store(false)
    if store then store.stopped = _G.time and _G.time() or 0 end
    return true
end

--- Drop every entry. While running the table is made again and stamped, so recording goes on.
function P.Clear()
    local g = NS.db and NS.db.global
    if g then g.probe = nil end
    if state.running then
        local store = P.Store(true)
        if store then stamp(store); store.started = _G.time and _G.time() or 0 end
    end
    return true
end

--- The one status line.
function P.StatusLine()
    local store = P.Store(false)
    local n = store and #store.entries or 0
    local line = ("probe: %s, %d %s (cap %d)"):format(state.running and "running" or "stopped", n,
        n == 1 and "entry" or "entries", P.CAP)
    if store and store.dropped and store.dropped > 0 then line = line .. (", %d dropped"):format(store.dropped) end
    if store and store.client then
        line = line .. (", %s %s %s"):format(tostring(store.client), tostring(store.version or "?"),
            tostring(store.build or "?"))
    end
    return line
end

local function say(line) NS.Util.print(line) end

local VERBS = {
    start = function()
        local ok, why = P.Start()
        if ok then return say("probe started; /kcd debug probe stop ends it. The record is saved at logout.") end
        say(("probe not started: %s"):format(why))
    end,
    stop = function()
        local ok, why = P.Stop()
        if ok then return say(P.StatusLine()) end
        say(("probe not stopped: %s"):format(why))
    end,
    status = function() say(P.StatusLine()) end,
    clear = function() P.Clear(); say(P.StatusLine()) end,
}

--- `/kcd debug probe <word>`; a bare probe is `status`.
function P.OnVerb(word)
    word = word and tostring(word):lower():match("^%s*(%S*)") or ""
    local fn = VERBS[word ~= "" and word or "status"]
    if fn then return fn() end
    say("usage: /kcd debug probe start, stop, status or clear")
end
