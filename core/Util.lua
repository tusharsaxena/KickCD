-- core/Util.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3 (helpers)
--
-- Small, dependency-free helpers shared across modules:
--   * Color {r,g,b,a} construction / unpacking / blending
--   * Frame anchor save + restore (point/relativePoint/x/y)
--   * Debounce wrapper using C_Timer.After to coalesce setting writes
--   * print() with the addon's chat prefix

KickCD = KickCD or {}
local Util = {}
KickCD.Util = Util

-- ---------------------------------------------------------------------------
-- Colors
-- ---------------------------------------------------------------------------

--- Construct a color table.
-- Convenience wrapper that always produces a 4-element {r,g,b,a} array
-- so module code never has to worry about a missing alpha.
-- @param r,g,b numbers in [0,1]
-- @param a optional alpha in [0,1]; defaults to 1
-- @return {r, g, b, a}
function Util.RGB(r, g, b, a)
    return { r or 0, g or 0, b or 0, a or 1 }
end

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

--- Linearly blend two colors: t=0 returns a, t=1 returns b.
-- Useful for "ready → on-cooldown" tint transitions.
-- @param a,b color tables (array or hash)
-- @param t   number in [0,1]
-- @return    {r,g,b,a}
function Util.Blend(a, b, t)
    t = math.max(0, math.min(1, t or 0))
    local ar, ag, ab, aa = Util.Unpack(a)
    local br, bg, bb, ba = Util.Unpack(b)
    return {
        ar + (br - ar) * t,
        ag + (bg - ag) * t,
        ab + (bb - ab) * t,
        aa + (ba - aa) * t,
    }
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
-- Throttle / Debounce
-- ---------------------------------------------------------------------------
--
-- Two coalescers with deliberately different semantics. The choice is:
--
--   Throttle — fires AT MOST once per `ms` window starting from the
--              FIRST call in a burst. Subsequent calls during the
--              window only update the args; the trailing call wins.
--              Use when you want a steady cadence during a sustained
--              burst (e.g. mirror an in-progress edit to the live
--              module ~20 times/sec while typing continues).
--
--   Debounce — fires `ms` after the LAST call in a burst; every new
--              call during the window resets the timer. Use when you
--              want the side effect to run only once the burst has
--              settled (e.g. commit a finished search query, persist
--              once the user has stopped dragging a slider).
--
-- Both wrappers always invoke `fn` with the args from the most recent
-- call (the trailing call wins). Args are stored in a fresh table per
-- burst so the captured C_Timer.After callback always sees the right
-- snapshot when it fires.

--- Leading-edge throttle: fires AT MOST once per `ms` window starting
--- from the first call in a burst. The trailing call's args win — i.e.
--- if the wrapper is called 50 times in 50 ms, `fn` runs once with the
--- 50th call's args at t=ms (or earlier if the burst stops within the
--- window).
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

--- Trailing-edge debounce: fires `ms` after the LAST call in a burst.
--- Every new call resets the timer, so `fn` only runs once the burst
--- has been quiet for `ms`. The trailing call's args win.
--- @param ms number of milliseconds of quiet required after the last call
--- @param fn function to invoke
--- @return wrapped function
function Util.Debounce(ms, fn)
    local delay = (ms or 0) / 1000
    -- Each call reschedules: bump the generation counter and capture
    -- it in the closure for the new C_Timer.After. When that timer
    -- fires, it only invokes `fn` if its generation still matches the
    -- current one — earlier timers from the same burst short-circuit
    -- silently. (C_Timer.After exposes no Cancel handle; the generation
    -- check is the standard workaround.)
    local generation = 0
    local pendingArgs

    return function(...)
        pendingArgs = { n = select("#", ...), ... }
        generation = generation + 1
        local thisGen = generation
        C_Timer.After(delay, function()
            if thisGen ~= generation then return end
            local args = pendingArgs
            pendingArgs = nil
            if args then
                fn(unpack(args, 1, args.n))
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------

local PREFIX = "|cff00ff00KickCD|r:"

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
