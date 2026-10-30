local addonName, NS = ...
-- modules/Sim.lua — the simulator's session host, on LibKa0s-Sim-1.0 (KickCD#38, KC-05; the Sim
-- major's host contract H4, H5 and H10; design-kc-sim §6; OWNER_SCOPE B4). Binds NS.SimSeam
-- (core/SimSetup.lua) to one session with Sim:New and publishes it as NS.Sim, overwriting the stub.
-- Shaped after BankLedger's modules/Sim.lua. Everything that is KickCD's own lives on NS.SimHost,
-- never on the library's instance.
--
-- ── THE PRINCIPLE ────────────────────────────────────────────────────────────────────────────
--
-- A simulation runs the REAL cooldown and cast engine against an invented world. The seam's
-- providers (modules/SimWorld.lua) answer every client read the engine makes; the drivers
-- (modules/SimDrivers.lua, KC-07) edit that world and fire the client's events through NS.Sim:Fire,
-- which this descriptor hands to NS.DeliverEvent (core/Events.lua), the one dispatch that replays
-- exactly the handlers the client would run. The player's class, spec, spell list and spell
-- identity stay live (design D4): the grid shows their own spells, on simulated cooldowns.
--
-- ── SAVED DATA STAYS UNTOUCHED (H4) ──────────────────────────────────────────────────────────
--
-- Nothing here writes the profile: the world lives on NS.SimHost, the spell list is read and never
-- written, and the panel's position is session-only (the library holds it in memory, H10). The
-- refusals run first and the stop re-syncs the engine to the real client, so a session leaves no
-- trace. tests/test_sim_session.lua compares KickCDDB byte for byte before and after.
--
-- ── THE STOP ─────────────────────────────────────────────────────────────────────────────────
--
-- The library's two-phase stop. Nothing needs the seam while stopping (there is no settle to cancel
-- and no final pass), so there is no OnStopGuarded step. With the seam off (OnStop), each step
-- isolated by the library: the world and the spells are dropped, the strip is hidden, and the
-- engine is re-synced to the REAL client through DeliverForCleanup (the target and focus, the
-- cooldowns and charges, then a Rebuild), ending a simulated combat unless real combat ended it.

NS.SimHost = NS.SimHost or {}
local Host = NS.SimHost
local L = NS.L

--- The scenarios, filled in place at file load by modules/SimScenario.lua (KC-08); the library reads
--- them at call time: { names = { ordered }, defs = { [name] = def } }.
Host.SCENARIOS = Host.SCENARIOS or { names = {}, defs = {} }

-- ── the step delay (design D7) ───────────────────────────────────────────────────────────────
--
-- A fixed host function, with NO settings row: the scenarios tell a timed story (a 3 s cast kicked
-- 1 s in, a kick that comes back), and their cast and cooldown timing is part of that story. A
-- slider would let a run break its own story. A step's own `wait` overrides the default.
Host.STEP_DELAY = 1

--- The descriptor's stepDelay: the pause after `step` before the run plays the next one.
--- @return number
function Host.DelayAfter(step)
    return step and step.wait or Host.STEP_DELAY
end

local function debug(fmt, ...)
    if NS.State and NS.State.debug and NS.Debug then NS.Debug("Sim", fmt, ...) end
end

local function module(name)
    return NS.GetModule and NS:GetModule(name, true) or nil
end

-- ── the player's spells (design §4) ──────────────────────────────────────────────────────────

--- The class token and spec the engine keys the spell list on, read the way modules/Cooldowns.lua's
--- ResolveClassSpec does (live: design D4).
local function classSpec()
    local _, classFile = UnitClass("player")
    if not classFile then return nil, nil end
    return NS.Util.NormalizeClassToken(classFile), NS.Util.PlayerSpecID()
end

--- Whether a spell-list entry is one the simulation can use: enabled, available and known.
local function usable(entry)
    local id = type(entry) == "table" and entry.spellID
    if type(id) ~= "number" or entry.enabled == false then return false end
    return NS.Compat.IsSpellAvailable(id) and NS.Compat.GetSpellInfo(id) ~= nil
end

--- "Your kick" and "your CC": the first kept entry of category `interrupt` (else the first kept
--- entry), and the first other kept entry that is not the kick. Read-only on the spell list.
--- @return number|nil kick, number|nil cc
function Host.ResolveSpells()
    local class, spec = classSpec()
    local list = class and spec and NS.Database and NS.Database:GetSpellList(class, spec)
    local kept = {}
    for _, entry in ipairs(list or {}) do
        if usable(entry) then kept[#kept + 1] = entry end
    end
    local kick
    for _, entry in ipairs(kept) do
        if entry.category == "interrupt" then kick = entry.spellID break end
    end
    kick = kick or (kept[1] and kept[1].spellID)
    for _, entry in ipairs(kept) do
        if entry.category ~= "interrupt" and entry.spellID ~= kick then return kick, entry.spellID end
    end
    return kick, nil
end

-- ── refusals (design D9; the preview-mode simulator MUSTs, H5) ───────────────────────────────

-- Each answers its line and the guard word the debug line names, or nil, checked in this order.
-- The library runs the refusal inside NS.SimSeam:Live, so every read below answers the real client,
-- and it has already refused an unknown scenario and a second session.
local PERF_LINE = L["A performance capture is running: finish it first (/kcd perf finish)."]
local CHECKS = {
    function()
        -- The perf harness holds the same stand-down latch as `disable`, so a capture reads as
        -- stood down; it answers its own line rather than the disabled one, which would be false.
        if not (NS.IsDown and NS.IsDown()) then return nil end
        if NS.Perf and NS.Perf.on then return PERF_LINE, "perf capture" end
        return NS.Slash.cli:DisabledLine(), "stood down"
    end,
    function()
        if NS.Perf and NS.Perf.on then return PERF_LINE, "perf capture" end
    end,
    function()
        -- Unlocking IS KickCD's preview (ARCHITECTURE.md *launcher*): the two never run together.
        if NS.db and NS.db.profile and NS.db.profile.locked == false then
            return L["Lock the grids first (/kcd lock): unlocking is KickCD's preview."], "unlocked"
        end
    end,
    function()
        if NS.State.inCombat or (_G.InCombatLockdown and _G.InCombatLockdown()) then
            return L["A simulation cannot start in combat."], "combat"
        end
    end,
    function()
        if _G.IsInInstance and _G.IsInInstance() then
            return L["A simulation cannot start in an instance."], "instance"
        end
    end,
    function()
        if _G.IsInGroup and _G.IsInGroup() then
            return L["A simulation cannot start in a group."], "group"
        end
    end,
    function()
        if not (NS.Units.IsEnabled("target") or NS.Units.IsEnabled("focus")) then
            return L["Enable the Target or the Focus grid first: the simulation plays on them."], "no unit"
        end
    end,
    function()
        if not Host.ResolveSpells() then
            return L["Your current spec tracks no spell you can use: add one with /kcd spells add, then start again."],
                "no spell"
        end
    end,
    function()
        if not NS.SimWorld.CanBuild() then
            return L["This client cannot build simulated cooldowns, so the simulator cannot run."], "no durations"
        end
    end,
}
Host.CHECKS = CHECKS

--- Why a simulation may not start now, as the one line to print, or nil when it may.
function Host.Refusal(opts)
    for i = 1, #CHECKS do
        local line, guard = CHECKS[i](opts or {})
        if line then
            debug("start refused: %s", tostring(guard))
            return line
        end
    end
    return nil
end

-- ── the real world's interference (design D10; KC-06) ────────────────────────────────────────
--
-- While a session runs, three REAL client events end it: combat, a loading screen and joining a
-- group. The watch is its own AceEvent target, registered in Prepare and released in the stop, so
-- it holds nothing while idle (tests/test_disabled.lua's empty registration set). It registers
-- through NS.SafeRegisterEvent DIRECTLY, never NS.RegisterEventList, so it is never a deliver route
-- (core/Events.lua; KC-02): a simulated event, fired through NS.Sim:Fire, cannot reach it, and the
-- handler's IsDelivering test is the belt to that pair of braces. A target change or a cast start
-- is not watched: the seam answers every read it makes from the world, so it is absorbed.
Host.watch = Host.watch or {}
local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
if AceEvent and not Host.watch.RegisterEvent then AceEvent:Embed(Host.watch) end

-- The watched events and the stop reason each raises (STOP_TEXT below).
Host.WATCH = {
    PLAYER_REGEN_DISABLED = "combat",
    PLAYER_ENTERING_WORLD = "world",
    GROUP_ROSTER_UPDATE   = "group",
}

local function inRealGroup()
    return NS.SimSeam:Live(function() return _G.IsInGroup ~= nil and _G.IsInGroup() == true end)
end

--- The watch's handler: a real event that ends the session stops it with its reason. A roster
--- update stops it only when the REAL client says the player is in a group.
function Host.OnWatchEvent(event)
    if NS.Sim:IsDelivering() then return end
    local reason = Host.WATCH[event]
    if not reason or not NS.Sim:IsActive() then return end
    if reason == "group" and not inRealGroup() then return end
    debug("real %s: stopping (%s)", tostring(event), reason)
    NS.Sim:Stop(reason)
end

local function onWatch(event, ...) return Host.OnWatchEvent(event, ...) end

--- Register the watch (Prepare). Rejected names land in NS.State.rejectedEvents like any other.
function Host.ArmWatch()
    if not Host.watch.RegisterEvent then return end
    local rejected = NS.State and NS.State.rejectedEvents
    for event in pairs(Host.WATCH) do NS.SafeRegisterEvent(Host.watch, event, onWatch, rejected) end
end

-- ── the start and the steps ──────────────────────────────────────────────────────────────────

--- The descriptor's prepare: the world, the two spells, the engine re-polled through the seam, the
--- panel (pinned up), then ready() once. The seam is already on.
function Host.Prepare(_, _, _, ready)
    Host.world = NS.SimWorld.Build()
    Host.kick, Host.cc = Host.ResolveSpells()
    NS.SimWorld.MarkOffGcd(Host.kick)
    -- The watched set re-polls through the seam, so every icon answers from the world: ready.
    local Cooldowns = module("Cooldowns")
    if Cooldowns then Cooldowns:Rebuild() end
    -- The step panel opens beside the grid (Sim-1.0 docks it to the panel's anchorTo), and it is
    -- the session's on-screen sign (ruling D-13): pinned up for the whole session.
    if NS.Sim and NS.Sim.ShowPanel and NS.Sim:ShowPanel() then Host.PinPanel() end
    -- The real world's interference: combat, a loading screen and a group now stop the session.
    Host.ArmWatch()
    debug("world built: kick %s, cc %s", tostring(Host.kick), tostring(Host.cc))
    ready()
end

--- The descriptor's play: one step is one driver call, and the driver's answer is the step's detail.
--- An unknown kind raises (the library counts the step failed and pauses the run).
function Host.Play(step)
    local D = NS.SimDrivers
    local driver = D and D.DRIVERS and D.DRIVERS[step.kind]
    if not driver then error(("no simulator driver for step kind %s"):format(tostring(step.kind)), 0) end
    return driver(step)
end

-- ── the panel's presentation (Sim-1.0's `d.panel`; H7, H10) ──────────────────────────────────
--
-- The panel itself (its rows, states, controls, picker, click-ahead and placement) is the
-- library's. These fields say only what KickCD's steps are called and what their tooltips say. No
-- `title` (the library default, `KickCD - Simulation`: the panel's name, not a mode word on a host
-- window) and no `store`: the position is session-only, so nothing reaches SavedVariables.

-- The role words a scenario's step labels carry, and the host field each resolves to.
local ROLES = { { word = L["your kick"], field = "kick" }, { word = L["your CC"], field = "cc" } }

--- `text` with every plain occurrence of `word` replaced by `with`.
local function replacePlain(text, word, with)
    local out, from = {}, 1
    while true do
        local a, b = text:find(word, from, true)
        if not a then break end
        out[#out + 1] = text:sub(from, a - 1)
        out[#out + 1] = with
        from = b + 1
    end
    out[#out + 1] = text:sub(from)
    return table.concat(out)
end

--- A timeline step's name (`d.panel.stepLabel`): its label, with "your kick" and "your CC" named by
--- the real spell while a session has resolved them (live, Compat.GetSpellInfo), else the role word,
--- so an idle preview still reads.
function Host.StepLabel(step)
    local label = step.label or step.kind or "?"
    for _, role in ipairs(ROLES) do
        local id = Host[role.field]
        local name = id and NS.Compat.GetSpellInfo(id)
        if type(name) == "string" and name ~= "" then label = replacePlain(label, role.word, name) end
    end
    return label
end

--- A timeline step's tooltip (`d.panel.stepTip`), { left, right } lines: the events its driver fires
--- (modules/SimDrivers.lua's EVENTS, KC-07), the engine it runs through, and once it played what the
--- driver did.
function Host.StepTip(step)
    local lines = {}
    local D = NS.SimDrivers
    local events = D and D.EVENTS and D.EVENTS[step.kind]
    if type(events) == "table" and #events > 0 then
        lines[#lines + 1] = { L["Fires"], table.concat(events, ", ") }
    end
    lines[#lines + 1] = { L["Through"], L["the real cooldown and cast engine"] }
    if step.ranAt and step.detail ~= nil then lines[#lines + 1] = { L["Did"], tostring(step.detail) } end
    return lines
end

--- The window the panel docks beside: the target grid while it is shown, else the focus grid, else
--- nil (the panel floats).
function Host.PanelAnchor()
    local IconGrid = module("IconGrid")
    if not IconGrid then return nil end
    for _, unit in ipairs({ "target", "focus" }) do
        local f = IconGrid:GetGridFrame(unit)
        if f and f:IsShown() then return f end
    end
    return nil
end

--- Keep the step panel up while a session runs (ruling D-13 of Ka0sAddonsCommonTasks
--- docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, image-46). The floating sim strip KC-09 hung over each
--- grid is gone, so the panel is the session's on-screen sign (the preview-mode MUST) and must not
--- be closed by accident: its close mark is hidden, and its frame comes off UISpecialFrames, so
--- Escape leaves it. Its Stop row and `/kcd sim stop` end the session; `/kcd sim panel` still
--- toggles it on purpose.
---
--- COMPOSED, NOT A DESCRIPTOR FIELD. The step panel's renderer takes `close = false`, but
--- LibKa0s-Sim-1.0 (SimPanel.lua at v1.82.0) does not forward a host's `panel.close` to it and
--- puts the frame on UISpecialFrames whatever; so this reaches the frame by its documented name,
--- `<name>SimPanel`, after the first ShowPanel built it. Idempotent; a frame or close mark that is
--- not there is left alone.
function Host.PinPanel()
    local name = addonName .. "SimPanel"
    local frame = _G[name]
    if type(frame) ~= "table" then return false end
    local close = frame.closeButton
    if type(close) == "table" and close.Hide then close:Hide() end
    local special = _G.UISpecialFrames
    if type(special) == "table" then
        for i = #special, 1, -1 do
            if special[i] == name then table.remove(special, i) end
        end
    end
    return true
end

local PANEL = {
    stepLabel = function(step, i, steps) return Host.StepLabel(step, i, steps) end,
    stepTip = function(step, i) return Host.StepTip(step, i) end,
    startTip = {
        { L["Builds"], L["a simulated world: enemy casts and your cooldowns"] },
        { L["Uses"], L["your real grids, cast bars and spell list"] },
        { L["Saves"], L["nothing: your settings are not touched"] },
    },
    stopTip = {
        { L["Ends"], L["the simulation"] },
        { L["Restores"], L["your real target, focus and cooldowns"] },
    },
    anchorTo = function() return Host.PanelAnchor() end,
    check = NS.Icon and NS.Icon("confirm") or nil,
}
Host.PANEL = PANEL

-- ── the session (LibKa0s-Sim-1.0) ────────────────────────────────────────────────────────────

-- The stop lines for the host's own reasons (the watch, core/Database.lua's profile switch,
-- modules/IconGrid.lua's unlock; KC-06) and the stand-down (core/LifecycleSetup.lua).
local STOP_TEXT = {
    combat    = L["Simulation stopped: you entered combat."],
    world     = L["Simulation stopped: a loading screen."],
    group     = L["Simulation stopped: you joined a group."],
    profile   = L["Simulation stopped: the profile changed."],
    unlocked  = L["Simulation stopped: the grids were unlocked."],
    standDown = L["Simulation stopped: the addon stood down."],
}

-- The library's lines in this addon's words, by its STRINGS keys. STARTED makes the saved-data
-- claim the library leaves to its host (H4); tests/test_sim_session.lua's before/after check backs it.
local LINES = {
    STARTED = L["Simulation started (%s): nothing is cast, nothing is saved, and your settings are not touched."],
}

local Lib = LibStub and LibStub("LibKa0s-Sim-1.0", true)
if Lib then
    NS.Sim = Lib:New({
        -- The folder name, which is also the skin owner the sim panel wears (skinning-§1).
        name = addonName,
        seam = NS.SimSeam,
        slash = "/kcd sim",
        -- KC-02's one dispatch: the AceEvent routes and the armed cast filters, in client order.
        deliver = function(event, ...) return NS.DeliverEvent(event, ...) end,
        isStoodDown = function() return NS.IsDown ~= nil and NS.IsDown() end,
        scenarios = Host.SCENARIOS,
        prepare = function(...) return Host.Prepare(...) end,
        play = function(step, session) return Host.Play(step, session) end,
        refusal = function(opts) return Host.Refusal(opts) end,
        stepDelay = function(step) return Host.DelayAfter(step) end,
        stopText = STOP_TEXT,
        L = LINES,
        print = function(line) NS.Util.print(line) end,
        debug = function(_, fmt, ...) debug(fmt, ...) end,
        panel = PANEL,
    })
end
-- Library absent: NS.Sim stays core/SimSetup.lua's inert stub, whose OnStop and AddListener do
-- nothing, so the registrations below are harmless.

-- ── the stop: with the seam off, each step isolated by the library ───────────────────────────

-- (a) The world and the spells.
NS.Sim:OnStop(function()
    Host.world, Host.kick, Host.cc = nil, nil, nil
end)

-- (a2) The watch: nothing stays registered once the session ends.
NS.Sim:OnStop(function()
    if Host.watch.UnregisterAllEvents then Host.watch:UnregisterAllEvents() end
end)

-- (b) Re-sync the engine to the real client: the cast bars and grids re-read the real target and
-- focus, the cooldowns re-poll, and the watched set is rebuilt from the real reads.
local CLEANUP_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES" }
NS.Sim:OnStop(function()
    for _, event in ipairs(CLEANUP_EVENTS) do NS.Sim:DeliverForCleanup(event) end
    local Cooldowns = module("Cooldowns")
    if Cooldowns then Cooldowns:Rebuild() end
end)

-- (c) End a simulated combat. Not on a `combat` stop: real combat set the flag, and it stays set.
-- The drivers set `simCombat` on the session when they fire PLAYER_REGEN_DISABLED (KC-07).
NS.Sim:OnStop(function(session, reason)
    if session and session.simCombat and reason ~= "combat" then
        NS.Sim:DeliverForCleanup("PLAYER_REGEN_ENABLED")
    end
end)
