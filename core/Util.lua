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
-- Debounce
-- ---------------------------------------------------------------------------

--- Wrap a function so rapid successive calls collapse into a single
--- delayed execution. The trailing call wins (latest args used).
--- Used by the spells editor to avoid firing KickCD_CONFIG_CHANGED on
--- every keystroke.
-- @param ms number of milliseconds to wait after the last call
-- @param fn function to invoke
-- @return wrapped function
function Util.Debounce(ms, fn)
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
