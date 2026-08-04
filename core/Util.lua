-- core/Util.lua
-- Small helper surface (color, anchor, throttle, chat). See docs/module-map.md.
--
-- Small, dependency-free helpers shared across modules:
--   * Color {r,g,b,a} unpacking
--   * Frame anchor save + restore (point/relativePoint/x/y)
--   * Throttle wrapper using C_Timer.After to coalesce setting writes
--   * print() with the addon's chat prefix

local addonName, NS = ...
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

--- Leading-edge throttle: fires AT MOST once per `ms` window starting
--- from the first call in a burst. The trailing call's args win — i.e.
--- if the wrapper is called 50 times in 50 ms, `fn` runs once with the
--- 50th call's args at t=ms (or earlier if the burst stops within the
--- window). Use when you want a steady cadence during a sustained
--- burst (e.g. mirror an in-progress edit to the live module ~20 times
--- per sec while typing continues).
--- @param ms number of milliseconds per window
--- @param fn function to invoke
--- @return wrapped function
function Util.Throttle(ms, fn)
    local delay = (ms or 0) / 1000
    -- Closure state: pendingArgs is a fresh table per "burst" so the
    -- captured C_Timer.After callback works on the args from *that* burst,
    -- not whatever happens to be in the slot when it fires.
    local scheduled = false
    local pendingArgs

    return function(...)
        pendingArgs = { n = select("#", ...), ... }
        if scheduled then return end
        scheduled = true
        C_Timer.After(delay, function()
            scheduled = false
            local args = pendingArgs
            pendingArgs = nil
            if args then
                fn(unpack(args, 1, args.n))
            end
        end)
    end
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
-- RegisterUnitCastEvent wraps a private CreateFrame, registers it for the
-- named unit ("target" / "focus" / ...) only, and forwards into
-- module:handler so the call site reads like an Ace registration.
-- Handlers can drop their `if unit ~= <expected unit>` guard since the
-- dispatch frame already filtered upstream.
--
-- The frame is RETURNED, not tracked here. AceAddon's UnregisterAllEvents
-- on the module will not release these private frames; OnDisable must
-- iterate the caller-owned table and run f:UnregisterAllEvents() on each.

--- Create a private dispatch frame that fires `module[handlerName](module, ...)`
--- only when `eventName` fires for `unit`. Caller stashes the returned frame and
--- runs UnregisterAllEvents in OnDisable (or on per-unit enable-toggle teardown).
--- @param module table     — AceEvent module (handler methods live on it)
--- @param unit string      — "target" / "focus"
--- @param eventName string — UNIT_SPELLCAST_START / _STOP / etc.
--- @param handlerName string — method on `module` to call on dispatch
--- @return Frame
function Util.RegisterUnitCastEvent(module, unit, eventName, handlerName)
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent(eventName, unit)
    f:SetScript("OnEvent", function(_, event, evUnit, ...)
        local fn = module[handlerName]
        if fn then fn(module, event, evUnit, ...) end
    end)
    return f
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
