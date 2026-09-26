-- core/SpellInput.lua
-- See docs/module-map.md.
--
-- What a player typed into "add a spell", turned into something the spell-list
-- writer (core/Database.lua) can take. ONE copy, called by both surfaces that
-- add a spell: the Spells page (settings/Spells.lua) and `/kcd spells add`
-- (core/KickCD.lua). Before this file each had its own resolver, and the command
-- line had no Cooldown Manager gate and split a multi-word name at its first
-- space (KICKCD-R-05), and took any CLASS token or spec number it was handed
-- (KICKCD-R-18).
--
--   * Resolve(input)          an id or a spell name -> spellID, name
--   * ParseTail(tokens)       `<id|name words...> [CLASS SPEC]` -> id, name, class, spec
--   * IsLivePair(class, spec) is this the logged-in player's own class + active spec
--   * Admissible(id, c, s)    the Blizzard Cooldown Manager gate, live pair only
--
-- The Cooldown Manager set is memoized here too, and so is the listener that
-- drops it on a talent or spec change. That listener is an AceEvent target made
-- at FILE LOAD, not in the page's lazy builder, so the cache is correct even when
-- the Spells page is never opened (KICKCD-A-04, events-frames-taint-§1: no
-- private frame for ordinary event traffic).

local _, NS = ...

local SpellInput = {}
NS.SpellInput = SpellInput

local function debugOn() return NS.State and NS.State.debug end

-- ---------------------------------------------------------------------------
-- Resolve
-- ---------------------------------------------------------------------------

--- An id or a spell name to (spellID, name), or nil. A name resolves only when
--- the client answers it with a NUMERIC spellID: the probe for "Wind Shear
--- SHAMAN" must miss rather than hand back something that is not an id.
-- @param input string|nil
-- @return number|nil spellID, string|nil name
function SpellInput.Resolve(input)
    if not input or input == "" then return nil end
    local Compat = NS.Compat or {}
    if not Compat.GetSpellInfo then return nil end
    local id = tonumber(input)
    if id then
        local name = Compat.GetSpellInfo(id)
        if name then return id, name end
        return nil
    end
    local name, _, _, _, _, resolvedID = Compat.GetSpellInfo(input)
    if name and type(resolvedID) == "number" then return resolvedID, name end
    return nil
end

-- ---------------------------------------------------------------------------
-- Class and spec
-- ---------------------------------------------------------------------------

local function playerPair()
    local classFile
    if _G.UnitClass then
        local _, cf = _G.UnitClass("player")
        classFile = cf
    end
    return classFile, NS.Util.PlayerSpecID()
end

--- Is (class, spec) the logged-in player's own class and active spec? The
--- Cooldown Manager answers for that pair and no other: C_CooldownViewer takes
--- no class or spec parameter.
function SpellInput.IsLivePair(class, spec)
    local pClass, pSpec = playerPair()
    return pClass ~= nil and pSpec ~= nil and class == pClass and spec == pSpec
end

-- Does `spec` belong to `class`? The client's own spec list when it can answer,
-- else the shipped defaults (defaults/Spells.lua keys every spec of every class).
local function specBelongs(class, spec)
    local order = NS.Util.SpecOrderForClass(class)
    if order then
        for _, s in ipairs(order) do
            if s == spec then return true end
        end
        return false
    end
    local byClass = NS.DefaultSpells and NS.DefaultSpells[class]
    return type(byClass) == "table" and byClass[spec] ~= nil
end

-- One trailing token: a CLASS (taking the player's spec, but only when that spec
-- is one of the class's), or else a SPEC of the player's own class, so
-- `/kcd spells add 51490 ELEMENTAL` edits the player's Elemental list.
local function parseOneToken(token, pClass, pSpec)
    local class = NS.Util.NormalizeClassToken(token)
    if NS.Database.IsKnownClass(class) then
        if pSpec and specBelongs(class, pSpec) then return class, pSpec end
        return nil, "Specify a spec for " .. class
    end
    local spec = pClass and NS.Util.ResolveSpecID(token, pClass)
    if spec and specBelongs(pClass, spec) then return pClass, spec end
    return nil, "Unknown class " .. class
end

-- A trailing `[CLASS [SPEC]]` to (class, spec), or nil plus the line to print.
-- An empty tail is the player's own pair.
local function parseClassSpec(tail)
    local pClass, pSpec = playerPair()
    if #tail == 0 then
        if not (pClass and pSpec) then return nil, "Could not determine class+spec" end
        return pClass, pSpec
    end
    if #tail == 1 then return parseOneToken(tail[1], pClass, pSpec) end
    if #tail > 2 then
        return nil, "Usage: /kcd spells add <id|name> [CLASS SPEC]"
    end
    local class = NS.Util.NormalizeClassToken(tail[1])
    if not NS.Database.IsKnownClass(class) then
        return nil, "Unknown class " .. class
    end
    local spec = NS.Util.ResolveSpecID(tail[2], class)
    if not (spec and specBelongs(class, spec)) then
        return nil, ("Unknown spec %s for %s"):format(tail[2], class)
    end
    return class, spec
end

--- `<id|name words...> [CLASS SPEC]`, already split on whitespace, to
--- (spellID, name, class, spec) -- or nil plus the line to print.
---
--- The name is the LONGEST prefix of `tokens` that resolves, so "Wind Shear"
--- resolves before "Wind" is tried; whatever follows it is the CLASS and SPEC,
--- validated rather than trusted (KICKCD-R-18): an unknown class or a spec that
--- is not one of that class's answers nil, and nothing reaches the writer.
-- @param tokens string[]
-- @return number|nil spellID (or nil), string name (or the error line), class, spec
function SpellInput.ParseTail(tokens)
    if not tokens[1] then return nil, "Usage: /kcd spells add <id|name> [CLASS SPEC]" end
    for n = #tokens, 1, -1 do
        local id, name = SpellInput.Resolve(table.concat(tokens, " ", 1, n))
        if id then
            local class, spec = parseClassSpec({ unpack(tokens, n + 1) })
            if not class then return nil, spec end
            return id, name, class, spec
        end
    end
    return nil, "Unknown spell: " .. table.concat(tokens, " ")
end

-- ---------------------------------------------------------------------------
-- The Cooldown Manager set
-- ---------------------------------------------------------------------------
--
-- The spellIDs the Blizzard Cooldown Manager would surface for the player's
-- active spec: every CooldownViewerCategory enum value, unioned. Memoized in
-- `_cmCache` because the walk is every category x every cdID and the answer is
-- stable for a (login x spec x talent build). A marker table stands in for "the
-- API answered nothing", so an empty answer is not re-walked on every call.

local _cmCache         -- the set, or _CM_EMPTY, once computed; nil otherwise
local _CM_EMPTY = {}   -- sentinel: the API returned no data; don't recompute

-- The two C_CooldownViewer entry points the walk needs, or nil when this client
-- can't answer. Older clients have no C_CooldownViewer at all, and the Enum the
-- category walk iterates arrived with it.
local function cooldownViewerApi()
    if not C_CooldownViewer then return nil end
    local getCategorySet = C_CooldownViewer.GetCooldownViewerCategorySet
    local getInfo        = C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not (getCategorySet and getInfo and Enum and Enum.CooldownViewerCategory) then
        return nil
    end
    return getCategorySet, getInfo
end

-- Union one category's spellIDs into `set`; returns whether it contributed any.
-- Both pcalls are load-bearing: C_CooldownViewer throws on some category values
-- in some client builds, and one bad category must not abort the whole walk.
local function collectCategorySpells(getCategorySet, getInfo, category, set)
    local ok, ids = pcall(getCategorySet, category)
    if not (ok and type(ids) == "table") then return false end
    local added = false
    for _, cdID in ipairs(ids) do
        local ok2, info = pcall(getInfo, cdID)
        if ok2 and type(info) == "table" and info.spellID then
            set[info.spellID] = true
            added = true
        end
    end
    return added
end

--- The Cooldown Manager's spell set for the active spec, or nil when the client
--- cannot answer (no opinion, never a rejection).
function SpellInput.CooldownManagerSet()
    if _cmCache == _CM_EMPTY then return nil end
    if _cmCache then return _cmCache end

    local getCategorySet, getInfo = cooldownViewerApi()
    if not getCategorySet then
        _cmCache = _CM_EMPTY
        return nil
    end

    local set = {}
    local seenAny = false
    for _, category in pairs(Enum.CooldownViewerCategory) do
        -- Deliberately NOT `seenAny = seenAny or collect(...)`: that
        -- short-circuits and stops walking once anything has been found.
        if collectCategorySpells(getCategorySet, getInfo, category, set) then
            seenAny = true
        end
    end

    if not seenAny then
        _cmCache = _CM_EMPTY
        return nil
    end
    _cmCache = set
    return set
end

--- What the memo holds, WITHOUT computing it: "unbuilt" (nothing has asked
--- since login or the last invalidation), "empty" (the client answered
--- nothing), or "built" plus the number of spells in the set. `/kcd
--- diagnostics` reads this; calling CooldownManagerSet instead would force the
--- walk the report must never force (DX-KC).
-- @return string state, number|nil count
function SpellInput.CooldownManagerCacheState()
    if _cmCache == nil then return "unbuilt" end
    if _cmCache == _CM_EMPTY then return "empty" end
    local n = 0
    for _ in pairs(_cmCache) do n = n + 1 end
    return "built", n
end

--- May `id` be added to (class, spec)? True, or false plus the line to print.
---
--- The gate applies only on the player's LIVE pair, because that is the only
--- pair C_CooldownViewer answers for: a Mage editing a Hunter list would
--- otherwise be refused every Hunter spell. Off the live pair, and on a client
--- with no viewer API, the answer is lenient -- the resolver has already
--- confirmed the spell exists.
-- @return boolean, string|nil reason
function SpellInput.Admissible(id, class, spec)
    if not SpellInput.IsLivePair(class, spec) then return true end
    local cmSet = SpellInput.CooldownManagerSet()
    if not cmSet then
        if debugOn() then
            NS.Debug("Spells", "C_CooldownViewer unavailable; skipping cooldown-manager validation for spell " .. tostring(id))
        end
        return true
    end
    if cmSet[id] then return true end
    local Compat = NS.Compat or {}
    local name = (Compat.GetSpellInfo and Compat.GetSpellInfo(id)) or tostring(id)
    return false, ("Spell %s (#%d) is not tracked by the Blizzard Cooldown Manager for this specialization."):format(name, id)
end

-- ---------------------------------------------------------------------------
-- The invalidator
-- ---------------------------------------------------------------------------
--
-- A talent swap or a spec change flips what C_CooldownViewer returns, so a set
-- cached before either is stale. The listener is an AceEvent target made at
-- FILE LOAD -- NS.NewBusTarget is core/KickCD.lua's, one TOC line up -- so it is
-- armed whether or not the Spells page is ever built.

local function invalidate()
    _cmCache = nil
end

local ev = NS.NewBusTarget()

-- File-scope rows, so a stand-up allocates nothing (anti-patterns #43).
local INVALIDATE_EVENTS = {
    { "TRAIT_CONFIG_UPDATED",          invalidate },
    { "PLAYER_SPECIALIZATION_CHANGED", invalidate },
}

--- Arm the cache invalidator. Idempotent: AceEvent keys on (event, target).
function SpellInput.Arm()
    if ev then NS.RegisterEventList(ev, INVALIDATE_EVENTS) end
end

--- Release it. Called by core/LifecycleSetup.lua's standDown (slash-commands-§7).
function SpellInput.StandDown()
    if ev then ev:UnregisterAllEvents() end
end

--- Put it back, dropping the cached set on the way: the spec or the talent build
--- can have changed while nothing was listening.
function SpellInput.StandUp()
    _cmCache = nil
    SpellInput.Arm()
end

--- The private target, for the harness's registration survey.
SpellInput.__ev = ev

SpellInput.Arm()
