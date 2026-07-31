local addonName, NS = ...

-- core/PerfSetup.lua — wires the addon into LibKa0s-Perf-1.0.
--
-- The probe, the guided A/B run, the record schema and the clickable step panel
-- are the library's. This file supplies the part only this addon can know: which
-- paths are worth measuring, and what "inert" means here.
--
-- TOC POSITION: after core/CoreSetup.lua (the printer) and core/State.lua, and
-- BEFORE every module that takes `local Perf = NS.Perf` as a load-time upvalue.
-- Today no module does — the brackets read NS.Perf at file scope in modules/
-- which all load later — but the constraint is real and cheap to honour.
--
-- WHY THE SIGNAL IS WHERE IT IS. This addon has almost no hot path, and saying
-- so plainly is more useful than a bucket list that reads 0.000 forever. There
-- is exactly one true 60 Hz handler (the cast bar's OnUpdate, and it only runs
-- DURING a cast), no combat-log parsing, and the per-unit dispatch frames are
-- already RegisterUnitEvent-filtered so a raid does not spray them.
--
-- The measurable cost lives in `iconApply`, and its rate is forced by an API
-- constraint rather than by frame rate: C_Spell.GetSpellCooldownDuration mints a
-- fresh handle per call, so the change-detection compares unequal on every poll
-- for any spell parked on cooldown (docs/data-flow.md). That is ~10x/sec per
-- spell on cooldown, multiplied by enabled units — roughly 100 calls/s with a
-- seven-spell list mid-fight, each doing three curve evaluations and a cooldown
-- write. If a capture shows anything, it shows there.

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)

if not lib then
    -- A missing vendored lib must degrade, not error at load. The addon's own
    -- function is unaffected by the absence of a diagnostics harness, but the
    -- stub has to cover EVERY member the addon reaches: the hot-path gate `on`
    -- and sink `Note`, the `suspended` flag the two show decisions consult, and
    -- OnCommand — because `/kcd perf` is registered unconditionally, so
    -- something has to answer it.
    NS.Perf = {
        on        = false,
        suspended = false,
        Note      = function() end,
        OnCommand = function()
            return { "Performance measurement is unavailable: the LibKa0s library is missing " ..
                "from this installation of KickCD (expected in libs/LibKa0s)." }
        end,
    }
    return
end

--- The two modules that own runtime work. Resolved at CALL time, never hoisted:
--- this file loads before modules/, so a load-time GetModule would answer nil.
local function runtimeModules()
    local out = {}
    for _, name in ipairs({ "IconGrid", "Castbar" }) do
        local m = NS.GetModule and NS:GetModule(name, true)
        if m then out[#out + 1] = m end
    end
    return out
end

NS.Perf = lib:New({
    name    = addonName,
    title   = "Ka0s KickCD",
    slash   = "/kcd",
    version = NS.VERSION,
    sv      = "KickCDPerfDB",

    -- Ordered for the report, with nesting DECLARED rather than left as prose:
    -- SendMessage dispatches inline through CallbackHandler, so IconGrid's
    -- spell-state handler really does execute inside Cooldowns:Refresh's frame.
    -- A reader comparing two captures months apart cannot be expected to know
    -- which totals overlap, and a parent must never be summed with its children.
    buckets = {
        { key = "spellPoll" },                          -- Cooldowns:Refresh, the coalesced pass
        { key = "spellState", within = "spellPoll"  },  -- IconGrid:OnSpellState, synchronous
        { key = "iconApply",  within = "spellState" },  -- Icon:Apply, per icon per unit
        { key = "cdText" },                             -- the 0.1s cooldown-text ticker pass
        { key = "castEvent" },                          -- IconGrid:OnUnitCastEvent
        { key = "visibility", within = "castEvent"  },  -- IconGrid:RefreshVisibility
        { key = "castTick" },                           -- Castbar OnUpdate, per frame while casting
    },

    -- DELIBERATELY NOT DECLARED: `pollSpell` (Cooldowns:PollSpell) and
    -- `glowGate` (IconGrid:RefreshAllGlows). Both have inline early-return
    -- guards, so a single fall-through bracket would under-count their calls and
    -- report a total that quietly excluded the rejected paths. A bucket that no
    -- bracket fully reaches is a lie in every report (performance-§3), so they
    -- are left out rather than declared and half-measured. `Note()` still records
    -- an undeclared key, so either can be added ad hoc if a capture points there.

    --- Make the addon inert without a /reload.
    ---
    --- Reloading, or disabling the addon through the AddOns list, shifts
    --- shared-frame ownership — the exact confound that makes the built-in
    --- profiler untrustworthy for this question. So the flip has to happen in
    --- place, live, mid-session.
    ---
    --- Visibility is NOT enforced by hiding frames from here. IconGrid's
    --- shouldBeVisible and Castbar's isVisible each check NS.Perf.suspended as
    --- step 0 of their ladder, so nothing — a combat transition, a target swap,
    --- a settings change — can re-show a grid behind suspend's back. The
    --- per-module Suspend() then releases the work: the module's game events and
    --- its private per-unit dispatch frames, which AceEvent's
    --- UnregisterAllEvents cannot reach.
    suspend = function()
        for _, m in ipairs(runtimeModules()) do
            if m.Suspend then m:Suspend() end
        end
        -- Cooldowns has no per-unit frames, but its throttle may have a poll
        -- already queued; the gate below makes the callback a no-op.
        local cd = NS.GetModule and NS:GetModule("Cooldowns", true)
        if cd and cd.UnregisterAllEvents then cd:UnregisterAllEvents() end
    end,

    --- Restore everything suspend took away, from CURRENT state: each module's
    --- Resume rebuilds its registrations from the units enabled NOW, so a unit
    --- toggled while suspended comes back correctly (performance-§6).
    ---
    --- No CONFIG_CHANGED is published from here. The modules' own Resume paths
    --- re-anchor and re-render, so this file does not become a sixth sender of a
    --- message docs/message-bus.md governs.
    resume = function()
        local cd = NS.GetModule and NS:GetModule("Cooldowns", true)
        if cd and cd.RegisterLifecycleEvents then cd:RegisterLifecycleEvents() end
        for _, m in ipairs(runtimeModules()) do
            if m.Resume then m:Resume() end
        end
    end,

    -- Perf output is deliberately NOT gated on NS.State.debug, unlike NS.Debug.
    -- That gate keeps the addon free when idle; a perf run is explicit user
    -- action and none of it executes unless someone typed `/kcd perf start`.
    -- Gating it meant a user who started a run without first enabling debug
    -- logging watched a console that stayed empty while a capture plainly ran.
    log = function(line)
        if NS.DebugLog and NS.DebugLog.Add then
            NS.DebugLog:Add("Perf", line)
        elseif NS.Util and NS.Util.print then
            NS.Util.print(line)
        end
    end,

    print = function(line) if NS.Util and NS.Util.print then NS.Util.print(line) end end,

    -- `start`, `report` and `dump` want the console in front of the user.
    -- Everything else must not pop it open: a lifecycle line mid-combat is the
    -- last moment to throw a window on screen.
    showLog = function()
        if NS.DebugLog and NS.DebugLog.Show and not NS.DebugLog:IsShown() then
            NS.DebugLog:Show()
        end
    end,

    L = NS.L,

    -- Built by the console's own close-button factory rather than a lookalike,
    -- so the two windows cannot drift apart. Resolved HERE and not into a
    -- load-time local: decorate fires at frame-build time, long after every file
    -- has loaded, which is the only reason this file may reach for a member of a
    -- module that loads after it.
    decorate = function(frame, api)
        if not (NS.DebugLog and NS.DebugLog.MakeCloseButton) then return end
        local close = NS.DebugLog.MakeCloseButton(frame, api.Hide)
        -- The factory answers nil where CreateFrame is unavailable — a close
        -- button is worth degrading over, not erroring over.
        if close then
            close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(api.TITLE_H - 18) / 2)
            frame.closeButton = close
        end
    end,
})
