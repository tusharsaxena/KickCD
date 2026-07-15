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
-- Spec / class token normalisation
-- ---------------------------------------------------------------------------
--
-- defaults/Spells.lua keys specs with a no-whitespace upper-case token
-- ("BEASTMASTERY", "MARKSMANSHIP", "MISTWEAVER", ...). The runtime side
-- has to derive the same token from GetSpecializationInfo's second
-- return — which is the LOCALISED display name. In English that
-- includes "Beast Mastery" (with whitespace); in non-English locales
-- additional spec names span multiple words. Uppercasing alone is not
-- enough — the whitespace has to be stripped too, or the runtime
-- lookup tries `profile.spells.HUNTER["BEAST MASTERY"]` and silently
-- gets nil.
--
-- These two helpers are the single source of truth for the conversion
-- so a future locale quirk only needs fixing in one place.

--- Normalise a localised spec name to the key used in defaults/Spells.lua
--- and db.profile.spells[CLASS][SPEC]: upper-cased and with every run of
--- whitespace stripped. Returns the empty string for nil/missing input
--- so callers can pass GetSpecializationInfo's second return verbatim.
-- @param specName string|nil — localised spec display name
-- @return string  — normalised spec token (e.g. "BEASTMASTERY")
function Util.NormalizeSpecToken(specName)
    return (specName or ""):upper():gsub("%s+", "")
end

--- Normalise a class file token. Today UnitClass() already returns the
--- locale-independent file token in upper-case ("HUNTER", "DEATHKNIGHT",
--- ...) so the helper is effectively a no-op — but routing every
--- class-key build through it gives one place to fix any future locale
--- quirk and keeps the symmetry with NormalizeSpecToken obvious at the
--- call site.
-- @param classFile string|nil — UnitClass() second return
-- @return string  — normalised class token (e.g. "HUNTER")
function Util.NormalizeClassToken(classFile)
    return (classFile or ""):upper()
end

-- ---------------------------------------------------------------------------
-- Unit-event filtering
-- ---------------------------------------------------------------------------
--
-- AceEvent's RegisterEvent fans out to every UnitEvent for every unit; in
-- a 25-player raid the UNIT_SPELLCAST_* family fires thousands of times
-- per minute and a handler that only cares about "target" pays for every
-- one before its early-return. Frame:RegisterUnitEvent restricts dispatch
-- to the unit(s) we name, but AceEvent doesn't expose it.
-- RegisterTargetEvent wraps a private CreateFrame, registers it for unit
-- "target" only, and forwards into module:handler so the call site reads
-- like an Ace registration. Handlers can drop their `if unit ~= "target"`
-- guard since the dispatch frame already filtered upstream.
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

--- Back-compat: target-only registration (unchanged call sites).
--- @param module table     — AceEvent module (handler methods live on it)
--- @param eventName string — UNIT_SPELLCAST_START / _STOP / etc.
--- @param handlerName string — method on `module` to call on dispatch
--- @return Frame — caller stashes this and runs UnregisterAllEvents in OnDisable
function Util.RegisterTargetEvent(module, eventName, handlerName)
    return Util.RegisterUnitCastEvent(module, "target", eventName, handlerName)
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------

-- Single source of truth for the chat tag lives on the namespace
-- (KickCD.PREFIX, set in core/Constants.lua which loads before this file).
-- The local fallback covers the theoretical case of Util loading first.
local PREFIX = NS.PREFIX or "|cff00ffff[KCD]|r"

--- Print to the default chat frame with the KickCD prefix.
-- Multiple args are space-separated, mirroring print().
function Util.print(...)
    local n = select("#", ...)
    if n == 0 then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX) end
        return
    end
    local parts = { PREFIX }
    for i = 1, n do
        parts[i + 1] = tostring((select(i, ...)))
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " "))
    end
end
