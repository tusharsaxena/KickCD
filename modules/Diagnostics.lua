local _, NS = ...
NS.Diagnostics = NS.Diagnostics or {}
local X = NS.Diagnostics

-- modules/Diagnostics.lua — the sections of `/kcd diagnostics` (debug-logging-§14, DX-KC).
--
-- THE LIBRARY OWNS THE REPORT, THIS FILE OWNS ITS CONTENT. LibKa0s-DebugLog-1.0's helper
-- (DebugLogDiagnostics.lua) writes the begin marker, the identity header (the [Init] summary, the
-- client build, the locale, the debug flag, the combat reads and the running LibKa0s minors), runs
-- each section below under its own pcall, applies the cap and writes the end marker. The console
-- descriptor in core/DebugLogSetup.lua hands it `X.Sections()`, called each time a report runs.
-- Nothing here builds a line buffer, a marker or a pcall wrapper of its own (anti-pattern #90).
--
-- LIFECYCLE FIRST. The state section leads, so a reader knows whether the runtime sections under
-- it describe live machinery before reading them. While the latch is down the four runtime
-- modules (Cooldowns, IconGrid, Castbar, UnitLabel) have released what they held, and each of
-- their sections says "stood down" rather than print an empty list that reads like a bug. The
-- configuration sections (settings, units, spells) print in full either way.
--
-- READ-ONLY, AND THAT IS THE WHOLE CONTRACT. No section takes or releases a Lifecycle hold,
-- registers an event, arms a timer, writes a setting, builds an instance or a frame, or calls
-- Clear(). Instances are read through PeekInstance, never GetInstance, which would create one.
-- The spell lists are read through Database:GetSpellList, never EnsureSpellList. The Cooldown
-- Manager set is read through SpellInput.CooldownManagerCacheState, never CooldownManagerSet,
-- which would force the category walk.
--
-- SECRET-SAFE BY ROUTE. Every value reaches a line as an argument of `out:add`, which stringifies
-- it through the console's SafeToString before any format sees it. The cast record is described
-- by type only (the existing Castbar dump's rule), no remaining duration is read, and nothing
-- here compares or adds a value read from a frame or the client.
--
-- THE THREE CHAT DUMPS ARE REUSED, NOT COPIED. `/kcd debug spells`, `castbar` and `interrupt`
-- take an emit sink (DR-KC-02); the cooldowns, castbar and interrupt sections hand them one that
-- writes into the report, so the report and the chat dumps cannot drift apart.
--
-- The report body is English diagnostic text and does not go through NS.L, like every trace line.

-- The rows printed whatever their value (DX-KC's always-print set): the master switches, and per
-- unit its enable, the glow triggers and the cast bar's shape and anchor mode. `units.focus.link`
-- is focus's alone; target has no link row.
local ALWAYS = { "enabled", "locked", "visibility", "scale", "alpha", "units.focus.link" }
local PER_UNIT = {
    "enabled", "icons.primaryGlowTrigger", "icons.secondaryGlowTrigger", "castbar.enabled",
    "castbar.orientation", "castbar.growDirection", "castbar.autoSize", "castbar.anchorMode",
}

local function alwaysPaths()
    local paths = {}
    for _, p in ipairs(ALWAYS) do paths[#paths + 1] = p end
    for _, u in ipairs(NS.Units.LIST) do
        for _, rel in ipairs(PER_UNIT) do paths[#paths + 1] = "units." .. u .. "." .. rel end
    end
    return paths
end

local function isDown()
    return NS.IsDown and NS.IsDown() or false
end

local function module(name)
    return NS.GetModule and NS:GetModule(name, true)
end

--- A sink for the chat dumps that writes each line into the report under `tag`.
local function sink(out, tag)
    return function(line) out:add(tag, "%s", line) end
end

--- A saved anchor table as `point relativePoint x y`, or `default`.
local function savedAnchor(a)
    if type(a) ~= "table" then return "default" end
    return ("%s %s %s %s"):format(tostring(a.point), tostring(a.relativePoint),
        tostring(a.x), tostring(a.y))
end

--- A frame's first point as `point relativePoint x y`, read under pcall.
local function livePoint(frame)
    if not (frame and frame.GetPoint) then return "not built" end
    local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok then return "unreadable" end
    if point == nil then return "no point" end
    return ("%s %s %s %s"):format(NS.SafeToString(point), NS.SafeToString(relPoint),
        NS.SafeToString(x), NS.SafeToString(y))
end

--- A frame's IsShown, read under pcall and never compared.
local function shown(frame)
    if not (frame and frame.IsShown) then return "not built" end
    local ok, v = pcall(frame.IsShown, frame)
    if not ok then return "unreadable" end
    return v
end

-- ── state ────────────────────────────────────────────────────────────────────────────────────

function X.State(out)
    local lc = NS.Lifecycle
    local holds = lc and lc.Holds and lc:Holds() or {}
    out:add("State", "enabled stored=%s, stood down=%s, holds=%s",
        NS.MasterEnabled and NS.MasterEnabled(), isDown(),
        #holds > 0 and table.concat(holds, ",") or "-")
    local g = NS.db and NS.db.global or {}
    out:add("State", "schema stored=%s code=%s", g.schemaVersion,
        NS.Database and NS.Database.CURRENT_DB_VERSION)
    local profile = NS.db and NS.db.GetCurrentProfile and NS.db:GetCurrentProfile()
    local p = NS.db and NS.db.profile or {}
    out:add("State", "profile=%s locked=%s (unlocked is the placement preview)", profile, p.locked)
    local st = NS.State or {}
    out:add("State", "State.inCombat=%s viewedUnit=%s", st.inCombat, st.viewedUnit)
end

-- ── settings ─────────────────────────────────────────────────────────────────────────────────

function X.Settings(out)
    local S = NS.Settings
    local rows = S and S.Schema or {}
    local Store = S and S.Store
    local n = out:nonDefaults(rows, function(row) return Store.Get(row.path) end, nil, nil,
        { always = alwaysPaths(), tag = "Set" })
    out:add("Set", "%s row(s) printed: the switches, per-unit enables, glow triggers and cast bar "
        .. "shape always, the rest only when changed", n)
end

-- ── units ────────────────────────────────────────────────────────────────────────────────────

function X.Units(out)
    local U = NS.Units
    for _, u in ipairs(U.LIST) do
        local c = U.Config(u) or {}
        out:add("Units", "%s: enabled=%s linked=%s wanted=%s", u, c.enabled ~= false,
            U.IsLinked(u), U.IsEnabled(u))
    end
end

-- ── spells ───────────────────────────────────────────────────────────────────────────────────

--- One list entry: `id name` plus `off` for a disabled row and `unlearned` for a spell the
--- player does not know.
local function entryText(e)
    local Compat = NS.Compat or {}
    local id = e.spellID
    local text = tostring(id) .. " " .. NS.SafeToString(Compat.GetSpellInfo and Compat.GetSpellInfo(id) or "?")
    if e.enabled == false then text = text .. " off" end
    if Compat.IsSpellAvailable and not Compat.IsSpellAvailable(id) then text = text .. " unlearned" end
    return text
end

function X.Spells(out)
    local _, class = UnitClass("player")
    local spec = NS.Util.PlayerSpecID()
    local list = NS.Database:GetSpellList(class, spec)
    out:add("Spells", "class=%s spec=%s (%s), %s entr(ies)", class, NS.Util.SpecDisplay(spec), spec,
        list and #list or "no list")
    local items = {}
    for _, e in ipairs(list or {}) do items[#items + 1] = entryText(e) end
    out:list("Spells", "list:", items)
    local customized, stored = NS.Database:CountCustomizedSpellLists()
    out:add("Spells", "lists: %s stored, %s customized", stored, customized)
end

-- ── the runtime sections ─────────────────────────────────────────────────────────────────────

function X.Cooldowns(out)
    if isDown() then return out:add("Cooldowns", "stood down: the watched list is released") end
    local m = module("Cooldowns")
    if not (m and m.DebugDump) then return out:add("Cooldowns", "module not loaded") end
    m:DebugDump(sink(out, "Cooldowns"))
end

function X.CMCache(out)
    local SI = NS.SpellInput
    if not (SI and SI.CooldownManagerCacheState) then
        return out:add("CMCache", "cooldown manager cache: unavailable")
    end
    local state, n = SI.CooldownManagerCacheState()
    if n then return out:add("CMCache", "cooldown manager cache: %s, %s spell(s)", state, n) end
    out:add("CMCache", "cooldown manager cache: %s", state)
end

local function iconGridUnit(out, grid, u)
    local inst = grid:PeekInstance(u)
    if not inst then return out:add("IconGrid", "%s: no instance", u) end
    local free, active = NS.Pool.CountsKeyed(inst.pool)
    out:add("IconGrid", "%s: enabled=%s shown=%s icons active=%s free=%s laid out=%s handle=%s",
        u, inst.enabled, shown(inst.grid), active, free, #inst.ordered, inst.handle ~= nil)
    out:add("IconGrid", "%s: anchor saved=%s live=%s", u,
        savedAnchor(NS.Units.Anchor(u, "icons")), livePoint(inst.grid))
    out:add("IconGrid", "%s: last visible=%s gate casting=%s interruptible=%s", u,
        inst.lastVisible, inst.lastGateCasting, inst.lastGateInterruptible)
end

function X.IconGrid(out)
    if isDown() then return out:add("IconGrid", "stood down: grids hidden, cast filters disarmed") end
    local grid = module("IconGrid")
    if not grid then return out:add("IconGrid", "module not loaded") end
    for _, u in ipairs(NS.Units.LIST) do out:section("icongrid " .. u, iconGridUnit, grid, u) end
end

local function castbarUnit(out, bar, u)
    local inst = bar:PeekInstance(u)
    local cfg = NS.Units.Castbar(u)
    if not inst then return out:add("Castbar", "castbar state (%s): no instance", u) end
    out:add("Castbar", "%s: enabled=%s shown=%s casting=%s", u, inst.enabled, shown(inst.frame),
        inst.current ~= nil)
    out:add("Castbar", "%s: anchor mode=%s saved=%s live=%s", u, cfg.anchorMode or "FREE",
        savedAnchor(NS.Units.Anchor(u, "castbar")), livePoint(inst.frame))
    bar:DebugDump(u, sink(out, "Castbar"))
end

function X.Castbar(out)
    if isDown() then return out:add("Castbar", "stood down: bars hidden, cast filters disarmed") end
    local bar = module("Castbar")
    if not (bar and bar.DebugDump) then return out:add("Castbar", "module not loaded") end
    for _, u in ipairs(NS.Units.LIST) do out:section("castbar " .. u, castbarUnit, bar, u) end
end

function X.Interrupt(out)
    local Compat = NS.Compat
    if not (Compat and Compat.DebugInterrupt) then
        return out:add("Interrupt", "Compat.DebugInterrupt unavailable")
    end
    for _, u in ipairs(NS.Units.LIST) do Compat.DebugInterrupt(u, sink(out, "Interrupt")) end
end

function X.UnitLabel(out)
    if isDown() then return out:add("UnitLabel", "stood down: labels hidden") end
    local m = module("UnitLabel")
    if not (m and m.PeekInstance) then return out:add("UnitLabel", "module not loaded") end
    for _, u in ipairs(NS.Units.LIST) do
        local inst = m:PeekInstance(u)
        local label = NS.Units.Label(u)
        out:add("UnitLabel", "%s: show=%s text=%s attach=%s shown=%s", u, NS.Units.LabelShow(u),
            label.text, NS.Units.LabelStyle(u).attach, shown(inst and inst.frame))
    end
end

-- ── events, perf ─────────────────────────────────────────────────────────────────────────────

function X.Events(out)
    local st = NS.State or {}
    out:joined("Events", "rejected events:", st.rejectedEvents or {})
end

function X.Perf(out)
    local P = NS.Perf or {}
    out:add("Perf", "perf: capturing=%s suspended=%s", P.on, P.suspended)
end

--- The section list the console descriptor hands the library, in report order. Built on each
--- call so a test (or a later module) sees the live functions.
function X.Sections()
    return {
        { "state",     X.State },
        { "settings",  X.Settings },
        { "units",     X.Units },
        { "spells",    X.Spells },
        { "cooldowns", X.Cooldowns },
        { "cmcache",   X.CMCache },
        { "icongrid",  X.IconGrid },
        { "castbar",   X.Castbar },
        { "interrupt", X.Interrupt },
        { "unitlabel", X.UnitLabel },
        { "events",    X.Events },
        { "perf",      X.Perf },
    }
end
