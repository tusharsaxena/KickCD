-- tests/test_event_routes.lua -- one dispatch table: NS.EventRoutes and NS.DeliverEvent (KickCD#38, H3).
--
-- A simulator needs ONE `deliver` that calls exactly the handlers the client's own registration
-- would call for an event. KickCD has two choke points for that registration: NS.RegisterEventList
-- (core/CoreSetup.lua) for the AceEvent targets, and Util.NewUnitCastFilter (core/Util.lua) for
-- the per-unit UNIT_SPELLCAST_* filter frames. Both record into NS.EventRoutes (core/Events.lua),
-- and NS.DeliverEvent replays from that record -- reading AceEvent's own registry for what is
-- STILL registered, and each filter's `armed` flag for what is still armed. So a stood-down addon
-- delivers nothing without DeliverEvent ever asking the latch.
--
-- Every case builds a fresh instance with the full lifecycle: the cases spy module methods and
-- toggle units, and the shared instance is not theirs to change.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local GUID = "Creature-0-0-0-0-12345-0000000000"

--- A fully enabled instance, past PLAYER_LOGIN as the client always is when a sim can run.
local function live()
    local inst = T.load(true, true)
    inst.mocks.__fireEvent("PLAYER_LOGIN")
    inst.mocks.__flushTimers()
    return inst
end

--- Replace `obj[name]` with a recorder; answers the list of calls (each the argument list after self).
local function spy(obj, name)
    local calls = {}
    obj[name] = function(_, ...) calls[#calls + 1] = { ... } end
    return calls
end

--- Run fn with chat muted (the enable switch prints a confirmation line).
local function muted(inst, fn)
    local real = inst.NS.Util.print
    inst.NS.Util.print = function() end
    local ok, err = pcall(fn)
    inst.NS.Util.print = real
    if not ok then error(err, 0) end
end

test("DeliverEvent: SPELL_UPDATE_COOLDOWN runs Cooldowns' OnCooldownEvent once and answers 1", function()
    local inst = live()
    local calls = spy(inst.NS:GetModule("Cooldowns"), "OnCooldownEvent")
    assertEqual(inst.NS.DeliverEvent("SPELL_UPDATE_COOLDOWN"), 1)
    assertEqual(#calls, 1, "OnCooldownEvent runs exactly once")
    assertEqual(calls[1][1], "SPELL_UPDATE_COOLDOWN", "called with the event name, as AceEvent calls it")
end)

test("DeliverEvent: PLAYER_TARGET_CHANGED runs every module that registered it, and counts them", function()
    local inst = live()
    local NS = inst.NS
    local grid = spy(NS:GetModule("IconGrid"), "OnTargetChanged")
    local bar = spy(NS:GetModule("Castbar"), "OnTargetChanged")
    local label = NS:GetModule("UnitLabel")
    local labelCalls = label.OnTargetChanged and spy(label, "OnTargetChanged") or {}
    local expected = 2 + (label.OnTargetChanged and 1 or 0)
    assertEqual(NS.DeliverEvent("PLAYER_TARGET_CHANGED"), expected)
    assertEqual(#grid, 1, "IconGrid:OnTargetChanged ran once")
    assertEqual(#bar, 1, "Castbar:OnTargetChanged ran once")
    assertTrue(#labelCalls <= 1)
end)

test("DeliverEvent: PLAYER_REGEN_DISABLED reaches core/State.lua's boot listener", function()
    local inst = live()
    local NS = inst.NS
    local sent = {}
    local realSend = NS.SendMessage
    NS.SendMessage = function(self, msg, ...)
        sent[#sent + 1] = msg
        return realSend(self, msg, ...)
    end
    NS.State.SetInCombat(false)
    sent = {}
    local n = NS.DeliverEvent("PLAYER_REGEN_DISABLED")
    NS.SendMessage = realSend
    assertTrue(n >= 1, "the boot listener counts")
    assertEqual(NS.State.inCombat, true, "inCombat becomes true")
    local seen = false
    for _, m in ipairs(sent) do if m == NS.MSG.COMBAT_STATE then seen = true end end
    assertTrue(seen, "COMBAT_STATE is sent")
    NS.DeliverEvent("PLAYER_REGEN_ENABLED")
end)

test("DeliverEvent: a UNIT_SPELLCAST_ event reaches only the filters for its unit", function()
    local inst = live()
    local NS = inst.NS
    local grid = spy(NS:GetModule("IconGrid"), "OnUnitCastEvent")
    local bar = spy(NS:GetModule("Castbar"), "OnCastStart")
    assertEqual(NS.DeliverEvent("UNIT_SPELLCAST_START", "target", GUID, 1), 2)
    assertEqual(#grid, 1); assertEqual(grid[1][2], "target", "IconGrid ran for the target instance")
    assertEqual(#bar, 1); assertEqual(bar[1][2], "target", "Castbar ran for the target instance")
    assertEqual(grid[1][1], "UNIT_SPELLCAST_START")
    assertEqual(grid[1][3], GUID, "the payload rides through")

    assertEqual(NS.DeliverEvent("UNIT_SPELLCAST_START", "focus", GUID, 1), 2)
    assertEqual(grid[2][2], "focus"); assertEqual(bar[2][2], "focus")

    assertEqual(NS.DeliverEvent("UNIT_SPELLCAST_START", "party1", GUID, 1), 0, "no filter for party1")
    assertEqual(#grid, 2); assertEqual(#bar, 2)
end)

test("DeliverEvent: a disarmed filter runs nothing", function()
    local inst = live()
    local NS = inst.NS
    NS.Settings.Helpers.SetAndRefresh("units.focus.enabled", false)
    inst.mocks.__flushTimers()
    local grid = spy(NS:GetModule("IconGrid"), "OnUnitCastEvent")
    local bar = spy(NS:GetModule("Castbar"), "OnCastStart")
    assertEqual(NS.DeliverEvent("UNIT_SPELLCAST_START", "focus", GUID, 1), 0)
    assertEqual(#grid + #bar, 0, "the disabled focus unit's filters are disarmed")
end)

test("DeliverEvent: a stood-down addon delivers nothing, with no latch check of its own", function()
    local inst = live()
    local NS = inst.NS
    muted(inst, function() NS.SetMasterEnabled(false) end)
    inst.mocks.__flushTimers()
    for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
                          "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED" }) do
        assertEqual(NS.DeliverEvent(ev), 0, ev .. " after the stand-down")
    end
    assertEqual(NS.DeliverEvent("UNIT_SPELLCAST_START", "target", GUID, 1), 0)
    assertEqual(NS.DeliverEvent("UNIT_SPELLCAST_START", "focus", GUID, 1), 0)
end)

test("DeliverEvent: an event nobody registered answers 0", function()
    local inst = live()
    assertEqual(inst.NS.DeliverEvent("GROUP_ROSTER_UPDATE"), 0)
end)

test("DeliverEvent: a handler that raises costs only itself and names itself on the console", function()
    local inst = live()
    local NS = inst.NS
    NS:GetModule("IconGrid").OnTargetChanged = function() error("boom") end
    local bar = spy(NS:GetModule("Castbar"), "OnTargetChanged")
    local lines = {}
    local realDebug = NS.Debug
    NS.Debug = function(cat, fmt, ...) lines[#lines + 1] = { cat = cat, text = fmt:format(...) } end
    local ok, n = pcall(NS.DeliverEvent, "PLAYER_TARGET_CHANGED")
    NS.Debug = realDebug
    assertTrue(ok, "DeliverEvent does not raise: " .. tostring(n))
    assertTrue(n >= 2, "the failing handler counts too")
    assertEqual(#bar, 1, "the rest still run")
    local named = 0
    for _, l in ipairs(lines) do
        if l.cat == "Events" and l.text:find("PLAYER_TARGET_CHANGED", 1, true)
            and l.text:find("boom", 1, true) then named = named + 1 end
    end
    assertEqual(named, 1, "one Events line names the failure")
end)

test("DeliverEvent: a raising cast handler costs only itself", function()
    local inst = live()
    local NS = inst.NS
    NS:GetModule("IconGrid").OnUnitCastEvent = function() error("cast boom") end
    local bar = spy(NS:GetModule("Castbar"), "OnCastStart")
    local realDebug = NS.Debug
    local named = 0
    NS.Debug = function(cat, fmt, ...)
        if cat == "Events" and fmt:format(...):find("cast boom", 1, true) then named = named + 1 end
    end
    local ok, n = pcall(NS.DeliverEvent, "UNIT_SPELLCAST_START", "target", GUID, 1)
    NS.Debug = realDebug
    assertTrue(ok, tostring(n))
    assertEqual(n, 2)
    assertEqual(#bar, 1)
    assertEqual(named, 1)
end)

test("EventRoutes: a registration made through NS.SafeRegisterEvent directly is not a route", function()
    local inst = live()
    local NS = inst.NS
    local t = NS.NewBusTarget()
    local ran = 0
    NS.SafeRegisterEvent(t, "GROUP_ROSTER_UPDATE", function() ran = ran + 1 end, {})
    assertEqual(NS.DeliverEvent("GROUP_ROSTER_UPDATE"), 0, "outside the list, outside deliver")
    assertEqual(ran, 0)
    for _, target in ipairs(NS.EventRoutes.targets) do
        assertTrue(target ~= t, "the direct target is not recorded")
    end
end)

test("EventRoutes: a target is recorded once, and a filter once per (module, unit)", function()
    local inst = live()
    local NS = inst.NS
    local seen = {}
    for _, target in ipairs(NS.EventRoutes.targets) do
        assertTrue(not seen[target], "a target recorded twice")
        seen[target] = true
    end
    assertTrue(seen[NS:GetModule("Cooldowns")], "Cooldowns is a route target")
    local before = #NS.EventRoutes.filters
    muted(inst, function() NS.SetMasterEnabled(false) end)
    muted(inst, function() NS.SetMasterEnabled(true) end)
    inst.mocks.__flushTimers()
    assertEqual(#NS.EventRoutes.filters, before, "a stand-down/up cycle re-arms, it does not re-record")
    assertEqual(NS.DeliverEvent("SPELL_UPDATE_COOLDOWN"), 1, "and delivery is back after the stand-up")
end)

test("DeliverEvent: an unreadable AceEvent registry answers 0 and says so once", function()
    local inst = live()
    local NS = inst.NS
    local AceEvent = inst.mocks.LibStub("AceEvent-3.0")
    local realReg = AceEvent.events
    AceEvent.events = {}
    local lines = 0
    local realDebug = NS.Debug
    NS.Debug = function(cat, fmt)
        if cat == "Events" and fmt:find("unreadable", 1, true) then lines = lines + 1 end
    end
    local a = NS.DeliverEvent("SPELL_UPDATE_COOLDOWN")
    local b = NS.DeliverEvent("SPELL_UPDATE_COOLDOWN")
    NS.Debug = realDebug
    AceEvent.events = realReg
    assertEqual(a, 0); assertEqual(b, 0)
    assertEqual(lines, 1, "the fallback line is written once")
end)
