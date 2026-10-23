local _, NS = ...

-- core/Events.lua -- the one dispatch table (KickCD#38; Sim-1.0 H3).
--
-- A simulator needs ONE `deliver` that calls exactly the handlers the client's own registration
-- would call for an event, and no more. KickCD registers through two choke points, and both
-- record here at runtime:
--
--   * NS.RegisterEventList (core/CoreSetup.lua) -- every AceEvent block this addon owns. Its
--     first line hands the target to RecordList.
--   * Util.NewUnitCastFilter (core/Util.lua) -- the private per-(module, unit) frame the
--     UNIT_SPELLCAST_* family rides. It hands the filter to RecordFilter once, when it is built;
--     the frame is re-armed rather than rebuilt, so the record never duplicates.
--
-- What is recorded is WHO registered, never WHAT is registered now. NS.DeliverEvent asks AceEvent's
-- own CallbackHandler registry which of the recorded targets still hold the event, and each
-- filter's `armed` flag whether it is still listening. So a stood-down addon delivers nothing --
-- every target unregistered and every filter disarmed -- without DeliverEvent reading the latch.
--
-- A registration made through NS.SafeRegisterEvent DIRECTLY is not a route: it is not in the list,
-- so it is not replayed. That is deliberate and tests/test_event_routes.lua pins it.
--
-- No behavior change while no simulation runs: nothing calls DeliverEvent outside a simulation.

local Routes = { targets = {}, byTarget = {}, filters = {} }
NS.EventRoutes = Routes

--- Record an AceEvent target the first time NS.RegisterEventList sees it, in registration order.
--- @param target table  the AceEvent target the list was registered on
--- @param list table    its `{ event, handler }` rows (unused today; the registry is the truth)
function Routes.RecordList(target, list) -- luacheck: no unused args
    if Routes.byTarget[target] then return end
    Routes.byTarget[target] = true
    Routes.targets[#Routes.targets + 1] = target
end

--- Record one cast filter, once, when Util.NewUnitCastFilter builds it.
--- @param module table  the module whose methods the routes name
--- @param unit string   the filter's unit token
--- @param routes table  { [UNIT_SPELLCAST_* event] = method name }
--- @param filter table  the filter; `filter.armed` says whether it is listening now
function Routes.RecordFilter(module, unit, routes, filter)
    Routes.filters[#Routes.filters + 1] = { module = module, unit = unit, routes = routes, filter = filter }
end

local CAST_FAMILY = "UNIT_SPELLCAST_"

local function failed(event, err)
    NS.Debug("Events", "handler for %s failed: %s", event, NS.SafeToString(err))
end

--- Replay a UNIT_SPELLCAST_* event into every ARMED filter for its unit, as the filter frame's
--- OnEvent would. Answers how many handlers ran.
local function deliverCast(event, unit, ...)
    local n = 0
    for i = 1, #Routes.filters do
        local r = Routes.filters[i]
        local name = r.filter.armed and r.unit == unit and r.routes[event]
        local fn = name and r.module[name]
        if fn then
            n = n + 1
            local ok, err = pcall(fn, r.module, event, unit, ...)
            if not ok then failed(event, err) end
        end
    end
    return n
end

local warnedUnreadable = false

--- Replay `event` into every recorded target that AceEvent still holds it for, in registration
--- order, calling CallbackHandler's stored callable the way its Fire does. Answers how many ran.
local function deliverAce(event, ...)
    local ace = LibStub and LibStub("AceEvent-3.0", true)
    local reg = ace and ace.events
    if not (reg and type(reg.events) == "table") then
        if not warnedUnreadable then
            warnedUnreadable = true
            NS.Debug("Events", "deliver: AceEvent registry unreadable")
        end
        return 0
    end
    local list = reg.events[event]
    if not list then return 0 end
    local n = 0
    for i = 1, #Routes.targets do
        local fn = list[Routes.targets[i]]
        if type(fn) == "function" then
            n = n + 1
            local ok, err = pcall(fn, event, ...)
            if not ok then failed(event, err) end
        end
    end
    return n
end

--- Deliver `event` to exactly the handlers the client's registration would call, each isolated so
--- one that raises costs only itself (and writes one `Events` debug line). Answers the count.
--- @param event string
--- @return number
function NS.DeliverEvent(event, ...)
    local n = 0
    if event:sub(1, #CAST_FAMILY) == CAST_FAMILY then n = deliverCast(event, ...) end
    return n + deliverAce(event, ...)
end
