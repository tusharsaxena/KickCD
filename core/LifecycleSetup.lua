local addonName, NS = ...

-- core/LifecycleSetup.lua — wires the addon into LibKa0s-Lifecycle-1.0: the
-- stand-down latch (slash-commands-§7).
--
-- ── WHAT THIS FILE IS FOR ────────────────────────────────────────────────────
--
-- "Disabled" used to mean a DRAW GATE here, as it did in all eleven addons in
-- the collection: `enabled = false` hid the grid and the bar, every module kept
-- every registration it owned, and the client went on walking this addon's
-- registration list on every SPELL_UPDATE_COOLDOWN in a twenty-five-man raid,
-- building the argument frame, entering Lua and running the comparison that
-- decided to leave. That is the cost a player switching the addon off is trying
-- to stop paying, and it is invisible from every surface they can see.
--
-- slash-commands-§7 makes the disabled state TOTAL: every registration actually
-- unregistered, every timer cancelled, every frame hidden at the source, and no
-- SavedVariables write from any game event. What SURVIVES is setup rather than
-- feature — the chat command and its dispatcher, the settings registration and
-- the panel, the AceDB handle and its profile callbacks, and the launcher's
-- registration.
--
-- ── ONE LATCH, TWO HOLDS, AND NO SECOND TEARDOWN PATH ────────────────────────
--
-- The machinery to make this addon inert already existed: core/PerfSetup.lua's
-- suspend/resume arm, built for the capture's Experiment B. Writing a second
-- teardown beside it for `disable` would be the anti-pattern (#85) rather than
-- an implementation detail — two mechanisms that both mean "be inert" drift, and
-- the day they disagree the addon is half down, which is a state nobody designed
-- and no test covers. So both reasons are NAMED HOLDS on the one latch below:
--
--   * `disabled`  taken from the stored `enabled` path. PERSISTED, by being
--                 re-taken at load from the store.
--   * `perf`      taken by LibKa0s-Perf-1.0 for the suspended arm. SESSION-ONLY,
--                 and this file never spells it — the library owns it.
--
-- The addon is down whenever at least one hold is taken and stands up only when
-- the LAST one is released, so a perf run that finishes while the player has the
-- addon switched off does not resurrect it, and a `/kcd enable` typed mid-capture
-- does not un-suspend the run.
--
-- ── TOC POSITION ─────────────────────────────────────────────────────────────
--
-- ABOVE core/PerfSetup.lua, which passes NS.Lifecycle into its descriptor at
-- load — LibKa0s-Perf-1.0 minor 12 requires it and raises at :New without it.
-- Below core/CoreSetup.lua, so NS.Util.print exists for the latch's `print`.
-- Everything else here resolves at CALL time: the modules are looked up through
-- NS:GetModule when an edge fires, long after modules/ has loaded.

local Lifecycle = LibStub and LibStub("LibKa0s-Lifecycle-1.0", true)

-- The hold key, read off the library rather than typed at the call site: two
-- majors and every host in the collection have to spell it the same way, and the
-- day one of them reads "Disabled" the addon takes a hold nothing releases. The
-- literal is the degraded install's only spelling of it, and it is here — once —
-- rather than at the two call sites below.
local HOLD_DISABLED = (Lifecycle and Lifecycle.HOLD_DISABLED) or "disabled"

--- True when the master enable flag is set — THE one reader of the stored path.
---
--- Defaults to true on a fresh or missing profile, exactly as the modules' own
--- ladders read it, so a load that has not reached OnInitialize stands nothing
--- down. Read straight off the profile rather than through Helpers.Get: the
--- `enabled` row is COMPOSED by LibKa0s-Options-1.0's Master controls block, so
--- a load without the library has no row to resolve, and a latch that stood the
--- addon down on that load would be a far worse failure than the one it guards.
function NS.MasterEnabled()
    local profile = NS.db and NS.db.profile
    if not profile then return true end
    return profile.enabled ~= false
end

-- ---------------------------------------------------------------------------
-- The teardown and the rebuild
-- ---------------------------------------------------------------------------
--
-- The modules own what "inert" means for their own registrations; this file
-- owns the ORDER, and the order is not cosmetic. Cooldowns is the publisher on
-- the message bus (Ka0s_KickCD_SPELL_STATE) and IconGrid is its subscriber, so
-- the rebuild brings the subscribers up FIRST and the publisher last —
-- otherwise Cooldowns:Rebuild's initial fan-out lands on a bus nobody has
-- re-subscribed to yet and the grid comes back empty until the next poll. The
-- teardown runs the same list in reverse, so the publisher stops first.
local UP_ORDER = { "IconGrid", "Castbar", "UnitLabel", "Cooldowns" }

--- Call `fn(module)` for each runtime module that exists, in `UP_ORDER` or its
--- reverse. Resolved at CALL time, never hoisted: this file loads before
--- modules/, so a load-time GetModule would answer nil for every one of them.
local function eachModule(reverse, fn)
    for i = 1, #UP_ORDER do
        local name = UP_ORDER[reverse and (#UP_ORDER - i + 1) or i]
        local m = NS.GetModule and NS:GetModule(name, true)
        if m then fn(m) end
    end
end

--- Stand the addon down: every event, message and per-unit dispatch frame it
--- owns actually UNREGISTERED, every timer and ticker cancelled, every frame
--- hidden through the show ladder rather than imperatively.
---
--- NOTHING HERE IS COMBAT-UNSAFE, and that is a property of this addon rather
--- than a lucky accident: KickCD owns no secure frame, no attribute driver and
--- no state driver (the icon grid is a plain frame — see the note in
--- modules/IconGrid_Render.lua about SecureActionButton being deliberately
--- avoided), so there is nothing to hold pending for PLAYER_REGEN_ENABLED.
--- slash-commands-§7's pending-completion carve-out is therefore unused here. An
--- addon that GROWS a secure frame must hold its teardown pending instead of
--- extending this function.
local function standDown()
    if NS.State and NS.State.StandDown then NS.State.StandDown() end
    eachModule(true, function(m) if m.Suspend then m:Suspend() end end)
    -- The Spells editor is a settings page rather than an AceAddon module, so it
    -- is not in the loop above -- but its five subscriptions are registrations
    -- like any other and §7 does not carve the settings layer out of "actually
    -- UNREGISTERED". The PAGE survives (it still opens, still draws, still
    -- writes); what goes is its reaction to game events. settings/Spells.lua
    -- argues the line in full.
    local sp = NS.Settings and NS.Settings.SpellsPanel
    if sp and sp.StandDown then sp.StandDown() end
end

--- Stand the addon back up, FROM CURRENT STATE rather than from a snapshot
--- taken on the way down: a unit toggled, a spell enabled or a bar re-anchored
--- while the addon was off has to come back the way it is NOW (performance-§6).
--- Each module's Resume is the same path its OnEnable runs, so there is exactly
--- one way up.
local function standUp()
    if NS.State and NS.State.StandUp then NS.State.StandUp() end
    local sp = NS.Settings and NS.Settings.SpellsPanel
    if sp and sp.StandUp then sp.StandUp() end
    eachModule(false, function(m) if m.Resume then m:Resume() end end)
end

-- ---------------------------------------------------------------------------
-- The latch
-- ---------------------------------------------------------------------------

if Lifecycle then
    NS.Lifecycle = Lifecycle:New({
        name      = addonName,
        standDown = standDown,
        standUp   = standUp,
        print     = function(line) if NS.Util and NS.Util.print then NS.Util.print(line) end end,
    })
else
    -- The degradation stub, and it is deliberately the SMALLEST thing that can
    -- answer: the hold set and the edge, and not one line of teardown of its own.
    -- standDown/standUp above stay the single mechanism in either install, which
    -- is the half that anti-pattern #85 is actually about — what is stubbed here
    -- is bookkeeping, not lifecycle.
    --
    -- Without LibKa0s there is no LibKa0s-Perf-1.0 either (core/PerfSetup.lua
    -- returns its own stub above), so `disabled` is the only hold that can ever
    -- be taken here.
    local holds, taken, down = {}, 0, false
    local stub = { name = addonName }
    local function edge()
        local wanted = taken > 0
        if wanted == down then return false end
        down = wanted
        if wanted then standDown() else standUp() end
        return true
    end
    -- Dot-declared with a discarded first parameter rather than colon-declared,
    -- because every member here ignores the receiver and an unused `self` is a
    -- lint warning the gate treats as a failure. The CALL shape is unchanged:
    -- callers write `NS.Lifecycle:Hold(...)` against the library and the stub
    -- alike, which is the whole point of a parity stub.
    function stub.Hold(_, key)
        if holds[key] then return false end
        holds[key], taken = true, taken + 1
        return edge()
    end
    function stub.Release(_, key)
        if not holds[key] then return false end
        holds[key], taken = nil, taken - 1
        return edge()
    end
    function stub.Set(_, key, held)
        if held then return stub.Hold(nil, key) end
        return stub.Release(nil, key)
    end
    function stub.IsHeld(_, key) return holds[key] == true end
    function stub.IsDown() return taken > 0 end
    function stub.Holds()
        local out = {}
        for key in pairs(holds) do out[#out + 1] = key end
        table.sort(out)
        return out
    end
    function stub.Reevaluate() return edge() end
    function stub.PrintHolds() return false end
    NS.Lifecycle = stub
end

--- Is the addon stood down — for ANY reason? The first rung of every show
--- decision in the addon (modules/IconGrid.lua's shouldBeVisible,
--- modules/Castbar.lua's isVisible) and the guard on both ReconcileUnits.
---
--- Asked of the LATCH rather than of the stored setting, so the one question
--- covers both holds: a disabled addon and a perf-suspended one draw exactly the
--- same nothing, and neither can be re-shown behind the latch's back by a combat
--- transition, a target swap or a settings change (slash-commands-§7's
--- "enforced at the source").
function NS.IsDown()
    return NS.Lifecycle and NS.Lifecycle:IsDown() or false
end

--- Re-take or release the `disabled` hold from the stored path, then settle.
---
--- The ONE place the stored `enabled` value becomes a hold, called from all
--- three routes that can change it: the single write seam (settings/Panel.lua's
--- Helpers.Set, which is what the checkbox, `/kcd set enabled` and the
--- `enable` / `disable` verbs all land on), AceDB's profile callbacks
--- (core/Database.lua — a profile switch can flip the path with nothing else
--- being touched), and the end of NS:OnEnable, where the stored value is taken
--- for the first time in the session.
---
--- `:Reevaluate()` after `:Set` is for the profile case and is idempotent
--- everywhere else: it fires a callback only on an ACTUAL edge.
function NS.RefreshEnabledHold()
    local lc = NS.Lifecycle
    if not lc then return end
    lc:Set(HOLD_DISABLED, not NS.MasterEnabled())
    lc:Reevaluate()
end
