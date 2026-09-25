-- core/Util.lua
-- Small helper surface (color, anchor, throttle, chat). See docs/module-map.md.
--
-- Small, dependency-free helpers shared across modules:
--   * Color {r,g,b,a} unpacking
--   * Frame anchor save + restore (point/relativePoint/x/y)
--   * Throttle wrapper using C_Timer.After to coalesce setting writes
--   * print() with the addon's chat prefix

local _, NS = ...
local Util = {}
NS.Util = Util

-- ---------------------------------------------------------------------------
-- Colors
-- ---------------------------------------------------------------------------

--- Unpack a color into the 4 numbers WoW APIs expect.
-- Accepts either an array-style {r,g,b,a} or a hash {r=,g=,b=,a=}.
-- @param c table
-- @return r, g, b, a
function Util.Unpack(c)
    if not c then return 1, 1, 1, 1 end
    if c.r ~= nil then
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

-- ---------------------------------------------------------------------------
-- Frame anchor save / restore
-- ---------------------------------------------------------------------------
--
-- We persist anchors as { point, relativePoint, x, y } and always anchor
-- relative to UIParent. That keeps the saved-variable shape stable and
-- avoids having to serialize a frame reference for relativeTo.

--- Snapshot a frame's primary anchor in a profile-friendly shape.
-- @param frame Frame
-- @return { point, relativePoint, x, y }
function Util.SaveAnchor(frame)
    if not frame or not frame.GetPoint then
        return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    end
    -- GetPoint(1) returns the first anchor; that's the only one we set.
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    return {
        point         = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x             = x or 0,
        y             = y or 0,
    }
end

--- Apply a saved anchor to a frame, anchored to UIParent.
-- ClearAllPoints first so we don't leak stale anchors when called
-- repeatedly from a config-changed handler.
-- @param frame Frame
-- @param anchor { point, relativePoint, x, y }
function Util.ApplyAnchor(frame, anchor)
    if not frame or not anchor then return end
    frame:ClearAllPoints()
    frame:SetPoint(
        anchor.point         or "CENTER",
        UIParent,
        anchor.relativePoint or "CENTER",
        anchor.x             or 0,
        anchor.y             or 0)
end

-- ---------------------------------------------------------------------------
-- Deep copy
-- ---------------------------------------------------------------------------

--- Recursively copy a value. Tables are cloned key-for-key (including
--- nested tables); non-table values pass through unchanged. Used by:
---   * Database:BuildSpells — clones the defaults table per profile
---     so a user-edited profile doesn't mutate KickCD.DefaultSpells.
---   * settings/Spells.lua's reset-to-defaults popup.
---   * settings/Panel.lua's RestoreDefaults — schema rows whose
---     default is a table (e.g. RGBA arrays) need a fresh copy or
---     several profiles end up sharing the same array.
---
--- Cycle detection is intentionally NOT implemented: every caller
--- works against shallow profile / defaults shapes that are guaranteed
--- acyclic. Adding cycle detection would buy nothing and slow the hot
--- path on profile load.
-- @param v any value
-- @return cloned value (same shape)
function Util.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = Util.DeepCopy(vv) end
    return out
end

-- ---------------------------------------------------------------------------
-- Throttle
-- ---------------------------------------------------------------------------

--- Trailing throttle: the first call arms one timer and fn fires once at
--- t=ms with the last call's args. Calls made while the timer is armed only
--- replace the pending args -- i.e. if the wrapper is called 50 times in
--- 50 ms, `fn` runs once, at t=ms, with the 50th call's args; nothing fires
--- on the leading edge. Use when you want a steady cadence during a sustained
--- burst (e.g. mirror an in-progress edit to the live module ~20 times
--- per sec while typing continues).
--- @param ms number of milliseconds per window
--- @param fn function to invoke
--- @return function wrapped
--- @return function cancel  drop the pending call, if any
---
--- THE SECOND RETURN IS THE STAND-DOWN'S (slash-commands-§7). A coalescing
--- timer that keeps its appointment after the addon has been switched off is the
--- single most expensive survivor the rule names: it wakes up, finds nothing to
--- do, and re-arms. Callers that own one through a lifecycle -- Cooldowns'
--- per-frame refresh coalescer -- keep the canceller and call it from Suspend;
--- callers whose throttle is panel-local ignore it, which is why it is a second
--- return rather than a shape change.
---
--- C_Timer.NewTimer, not C_Timer.After, for the same reason: `After` hands back
--- no handle, so a scheduled call cannot be withdrawn. The fallback to `After`
--- exists only for a client without NewTimer; there, cancel drops the ARGS and
--- the callback fires into a no-op.
function Util.Throttle(ms, fn)
    local delay = (ms or 0) / 1000
    -- Closure state: pendingArgs is a fresh table per "burst" so the
    -- captured timer callback works on the args from *that* burst,
    -- not whatever happens to be in the slot when it fires.
    local scheduled = false
    local pendingArgs
    local handle

    local function wrapped(...)
        pendingArgs = { n = select("#", ...), ... }
        if scheduled then return end
        scheduled = true
        local function fire()
            scheduled, handle = false, nil
            local args = pendingArgs
            pendingArgs = nil
            if args then
                fn(unpack(args, 1, args.n))
            end
        end
        local C = _G.C_Timer
        if C.NewTimer then
            handle = C.NewTimer(delay, fire)
        else
            C.After(delay, fire)
        end
    end

    local function cancel()
        if handle and handle.Cancel then handle:Cancel() end
        scheduled, pendingArgs, handle = false, nil, nil
    end

    return wrapped, cancel
end

-- ---------------------------------------------------------------------------
-- Spec / class token normalization
-- ---------------------------------------------------------------------------
--
-- Canonicalizes a spec NAME to a comparable token: upper-cased with every
-- run of whitespace stripped, so "Beast Mastery" and "beastmastery" meet at
-- "BEASTMASTERY".
--
-- This is NOT how spec keys are derived any more. Spell lists key on the
-- numeric specID (see "Spec identity" below); deriving a storage key from a
-- localized name is issue #8. What remains here is name MATCHING, which has
-- two legitimate callers:
--   * parsing a spec the user typed at the slash command, and
--   * matching a legacy string key during the v2 → v3 migration.
-- Both compare a name against other names, never against a stored key.

--- Normalize a spec name to a comparable token — upper-cased, whitespace
--- stripped. Returns the empty string for nil/missing input so callers can
--- pass a possibly-absent name straight through.
-- @param specName string|nil — spec display name, any locale
-- @return string  — normalized token (e.g. "BEASTMASTERY")
function Util.NormalizeSpecToken(specName)
    return (specName or ""):upper():gsub("%s+", "")
end

-- ---------------------------------------------------------------------------
-- Spec identity (locale-invariant)
-- ---------------------------------------------------------------------------
--
-- The numeric specID is the ONLY locale-invariant identity a spec has, and
-- it is what defaults/Spells.lua and db.profile.spells[CLASS][specID] key
-- on. NormalizeSpecToken above still exists, but only to parse names the
-- USER typed and to match legacy saved keys during the v2 -> v3 migration.
-- Never derive a storage key from a localized name again (issue #8).

--- The player's current specID, or nil when the API isn't available yet
--- (e.g. very early login, or a character below the spec-unlock level).
-- @return number|nil specID
function Util.PlayerSpecID()
    local Compat = NS.Compat
    if not (Compat and Compat.GetSpecialization) then return nil end
    local idx = Compat.GetSpecialization()
    if not idx then return nil end
    -- FIRST return is the numeric ID; the second is the LOCALIZED name and
    -- must never be used as a key.
    local specID = Compat.GetSpecializationInfo(idx)
    if type(specID) ~= "number" then return nil end
    return specID
end

--- English display token for a specID ("ELEMENTAL"), or nil if unknown.
--- Display / logging / slash-command output only — never a storage key.
-- @param specID number|nil
-- @return string|nil
function Util.SpecTokenForID(specID)
    if type(specID) ~= "number" then return nil end
    return NS.Const and NS.Const.SPEC_TOKEN and NS.Const.SPEC_TOKEN[specID] or nil
end

--- Human-readable spec label for log lines and chat output. Prefers the
--- English token so a bug report from a localized client quotes the same
--- string the maintainer's English client would; falls back to the raw ID
--- for a spec Const.SPEC doesn't know yet (e.g. a spec added by a patch
--- newer than this build).
-- @param specID number|nil
-- @return string
function Util.SpecDisplay(specID)
    return Util.SpecTokenForID(specID) or tostring(specID)
end

-- Fold a spec name to an accent-insensitive ASCII key. WoW's strupper is
-- locale-aware and upper-cases accented letters ("Élémentaire" ->
-- "ÉLÉMENTAIRE"); stock Lua's string.upper (and therefore the headless test
-- harness) leaves the multi-byte sequences alone. Dropping every non-ASCII
-- byte makes the two agree, so a saved key written by any client build still
-- matches the name the running client reports. Used only as a last-resort
-- alias after the exact matches below have missed.
local function asciiFold(name)
    return (tostring(name or ""):upper():gsub("[^A-Z0-9]", ""))
end

-- Lazily-built { [normalizedName] = specID } map for the CURRENT client
-- locale, plus a per-class variant so shared names (Frost, Holy,
-- Protection, Restoration) can be disambiguated. Rebuilt on demand; the
-- data is static for a session, so one build is enough.
local specNameMap, specNameMapByClass
-- { [specID] = localizedName } and { [classFile] = { specID, ... } } in
-- Blizzard's own spec order — both DISPLAY concerns (the Spells editor's
-- dropdown), never keys.
local specDisplayName, specOrderByClass
-- True only once a build actually saw spec data — see ensureSpecNameMaps.
local specMapsReady

-- Returns true once the client actually answered with at least one spec.
-- A build that came up empty is NOT cached: Database:Init resolves spec keys
-- at ADDON_LOADED, and caching an empty map there would strand a localized
-- profile for the whole session — the migration would quietly stop
-- recognizing localized keys with no way to recover short of a /reload.
local function buildSpecNameMaps()
    specNameMap, specNameMapByClass = {}, {}
    specDisplayName, specOrderByClass = {}, {}
    if not (GetNumClasses and GetClassInfo and GetNumSpecializationsForClassID
            and GetSpecializationInfoForClassID) then
        return false
    end
    for classID = 1, GetNumClasses() do
        local _, classFile = GetClassInfo(classID)
        if classFile then
            local byClass, order = {}, {}
            specNameMapByClass[classFile] = byClass
            specOrderByClass[classFile] = order
            for i = 1, (GetNumSpecializationsForClassID(classID) or 0) do
                local specID, specName = GetSpecializationInfoForClassID(classID, i)
                if specID and specName then
                    specDisplayName[specID] = specName
                    order[#order + 1] = specID
                    for _, alias in ipairs({ Util.NormalizeSpecToken(specName),
                                             specName, asciiFold(specName) }) do
                        if alias ~= "" then
                            byClass[alias] = specID
                            -- Ambiguous names stay out of the global map so a
                            -- bare "FROST" never silently resolves to whichever
                            -- class happened to be enumerated last.
                            if specNameMap[alias] == nil then
                                specNameMap[alias] = specID
                            elseif specNameMap[alias] ~= specID then
                                specNameMap[alias] = false
                            end
                        end
                    end
                end
            end
        end
    end
    return next(specDisplayName) ~= nil
end

-- Populate the maps, caching them only once the client has actually answered.
-- The tables are always left non-nil so callers can index them without a
-- guard; `specMapsReady` is what decides whether the next call rebuilds.
local function ensureSpecNameMaps()
    if specMapsReady then return end
    specMapsReady = buildSpecNameMaps()
end

-- ── ResolveSpecID's three lookup tiers ──────────────────────────────────────
-- One file-local per tier so each alias chain stands alone. The ORDER they are
-- called in is the behavior (see ResolveSpecID's own comment); each returns nil
-- to mean "not my answer, keep looking".

-- Class-scoped tier: the only one that can resolve a name shared across
-- classes (Frost, Holy, Protection, Restoration).
local function resolveByClass(classFile, token, input, folded)
    local byClass = classFile and specNameMapByClass[NS.Util.NormalizeClassToken(classFile)]
    if not byClass then return nil end
    return byClass[token] or byClass[input] or byClass[folded]
end

-- The English token from Const.SPEC.
local function resolveByConstToken(token)
    local Const = NS.Const
    if not (Const and Const.SPEC) then return nil end
    return Const.SPEC[token]
end

-- The global localized map, built for the client's own language.
local function resolveByLocalizedName(token, input, folded)
    local hit = specNameMap[token] or specNameMap[input] or specNameMap[folded]
    -- `false` marks an ambiguous name with no class hint — refuse it.
    if hit then return hit end
    return nil
end

--- Resolve user- or profile-supplied spec input to a numeric specID.
--- Accepts, in order of preference: a number, a numeric string, a localized
--- spec name in the client's own language, and the English token used by
--- Const.SPEC. Returns nil rather than guessing when nothing matches.
---
--- `classFile` is optional but disambiguates the four names shared across
--- classes (Frost, Holy, Protection, Restoration); without it those resolve
--- only via the English token.
-- @param input string|number|nil
-- @param classFile string|nil  e.g. "SHAMAN"
-- @return number|nil specID
function Util.ResolveSpecID(input, classFile)
    if type(input) == "number" then return input end
    if type(input) ~= "string" or input == "" then return nil end

    local asNumber = tonumber(input)
    if asNumber then return asNumber end

    ensureSpecNameMaps()

    local token = Util.NormalizeSpecToken(input)
    local folded = asciiFold(input)

    -- Class-scoped first: it is the only tier that can resolve a shared name.
    -- Then the English token from Const.SPEC, ahead of the global localized
    -- map so an English-speaking user's input keeps resolving identically no
    -- matter what locale the client is running.
    return resolveByClass(classFile, token, input, folded)
        or resolveByConstToken(token)
        or resolveByLocalizedName(token, input, folded)
end

--- Localized spec name for UI display ("Élémentaire" on a frFR client).
--- The inverse of the storage rule: keys must be locale-free, but anything
--- the user READS should be in their own language. Falls back to a
--- title-cased English token when the client can't be queried (or for a
--- spec Const.SPEC knows but the client doesn't enumerate).
-- @param specID number|nil
-- @return string
function Util.SpecDisplayName(specID)
    if type(specID) ~= "number" then return "" end
    ensureSpecNameMaps()
    local name = specDisplayName and specDisplayName[specID]
    if name then return name end
    local token = Util.SpecTokenForID(specID)
    if not token then return tostring(specID) end
    return (token:lower():gsub("^%l", string.upper))
end

--- Spec IDs for a class in Blizzard's own spec order (the order the
--- character sheet shows them), for building the Spells editor's dropdown.
--- Returns nil when the client can't be queried, so callers fall back to
--- their own ordering.
-- @param classFile string
-- @return table|nil  array of specIDs
function Util.SpecOrderForClass(classFile)
    if not classFile then return nil end
    ensureSpecNameMaps()
    local order = specOrderByClass and specOrderByClass[Util.NormalizeClassToken(classFile)]
    if order and #order > 0 then return order end
    return nil
end

--- Normalize a class file token. Today UnitClass() already returns the
--- locale-independent file token in upper-case ("HUNTER", "DEATHKNIGHT",
--- ...) so the helper is effectively a no-op — but routing every
--- class-key build through it gives one place to fix any future locale
--- quirk and keeps the symmetry with NormalizeSpecToken obvious at the
--- call site.
-- @param classFile string|nil — UnitClass() second return
-- @return string  — normalized class token (e.g. "HUNTER")
function Util.NormalizeClassToken(classFile)
    return (classFile or ""):upper()
end

-- ---------------------------------------------------------------------------
-- Unit-event filtering
-- ---------------------------------------------------------------------------
--
-- AceEvent's RegisterEvent fans out to every UnitEvent for every unit; in
-- a 25-player raid the UNIT_SPELLCAST_* family fires thousands of times
-- per minute and a handler that only cares about one unit pays for every
-- one before its early-return. Frame:RegisterUnitEvent restricts dispatch
-- to the unit(s) we name, but AceEvent doesn't expose it.
-- NewUnitCastFilter builds ONE private frame per (module, unit), registered
-- for that unit only ("target" / "focus" / ...) through RegisterUnitEvent, and
-- forwards each event into the module method its route names, so handlers can
-- drop their `if unit ~= <expected unit>` guard.
--
-- ITS ONE JOB IS THE UNIT_SPELLCAST_* FAMILY. events-frames-taint-§1 allows a
-- private frame for unit filtering and forbids a general-purpose frame factory,
-- so a route that is not UNIT_SPELLCAST_* is refused at construction. The route
-- map is the frame's FIXED event set: Arm registers exactly those names and
-- nothing is ever added later.
--
-- The frame is BUILT ONCE AND RE-ARMED. A disable/enable cycle, a per-unit
-- toggle or a perf suspend/resume calls Disarm (UnregisterAllEvents) and later
-- Arm again on the same frame; rebuilding it instead orphaned one frame per
-- event per cycle (events-frames-taint-§1: the filter frame MUST be reused, not rebuilt). AceAddon's
-- UnregisterAllEvents does not reach this frame, so the owner Disarms it on
-- teardown. Arm and Disarm are built once per filter, so arming allocates
-- nothing. Each name goes through NS.SafeRegisterUnitEvent, so one the client
-- refuses (a future retirement, say) costs only its own route and lands once in
-- NS.State.rejectedEvents.

local CAST_FAMILY = "UNIT_SPELLCAST_"

--- Build the one cast-filter frame for (module, unit).
--- @param module table  — AceEvent module (handler methods live on it)
--- @param unit string   — "target" / "focus"
--- @param routes table  — { [UNIT_SPELLCAST_* event] = handler method name };
---                        file-scope in the caller, so it is the fixed set
--- @return table { frame, armed, Arm(), Disarm() }
function Util.NewUnitCastFilter(module, unit, routes)
    for ev in pairs(routes) do
        if type(ev) ~= "string" or ev:sub(1, #CAST_FAMILY) ~= CAST_FAMILY then
            error("Util.NewUnitCastFilter: route " .. tostring(ev)
                .. " is not a UNIT_SPELLCAST_* event", 2)
        end
    end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, evUnit, ...)
        local name = routes[event]
        local fn = name and module[name]
        if fn then fn(module, event, evUnit, ...) end
    end)
    local filter = { frame = f, armed = false }
    function filter.Arm()
        if filter.armed then return end
        local rejected = NS.State and NS.State.rejectedEvents
        for ev in pairs(routes) do
            NS.SafeRegisterUnitEvent(f, ev, rejected, unit)
        end
        filter.armed = true
    end
    function filter.Disarm()
        f:UnregisterAllEvents()
        filter.armed = false
    end
    return filter
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------
--
-- NS.Util.print now comes from LibKa0s-Core-1.0 and is published by
-- core/CoreSetup.lua, which loads immediately after this file. The version that
-- lived here had no secret guard, so a combat-protected value raised inside the
-- table.concat every line ends in. Call sites are unchanged: it is still a plain
-- dot-callable NS.Util.print(...).
