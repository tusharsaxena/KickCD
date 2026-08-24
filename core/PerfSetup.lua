local addonName, NS = ...

-- core/PerfSetup.lua — wires the addon into LibKa0s-Perf-1.0.
--
-- The probe, the guided A/B run, the record schema and the clickable step panel
-- are the library's. This file supplies the part only this addon can know: which
-- paths are worth measuring, and what "inert" means here.
--
-- TOC POSITION: LAST in the core block, immediately after core/KickCD.lua, and
-- before every module that takes `local Perf = NS.Perf` as a load-time upvalue
-- (all of modules/, which loads after core/). Three things pin it there:
--   * core/CoreSetup.lua has run, so NS.Util.print exists;
--   * core/DebugLogSetup.lua has run, so the log sink and MakeCloseButton exist;
--   * core/KickCD.lua has run, so NS.VERSION exists — it did NOT when this file
--     sat higher in the block, so the descriptor's `version` captured nil and
--     every capture record stamped "v?".
-- The move is the belt; the TOC-manifest read below is the braces.
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
        -- The cause half is core/CoreSetup.lua's shared clause
        -- (NS.LIBKA0S_MISSING); only the consequence is this seam's. Read at
        -- CALL time rather than captured into a load-time local, so the TOC
        -- order of the two setup files can never freeze a nil in.
        OnCommand = function()
            return { NS.LIBKA0S_MISSING .. ", so performance measurement is unavailable." }
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
    -- Not `NS.VERSION` alone. While this file sat ABOVE core/KickCD.lua — which
    -- is where that constant is set — the descriptor captured nil and every
    -- record stamped "v?", unattributable the moment it leaves the session
    -- (performance-§8). The library takes `version` as a plain STRING resolved
    -- once at :New, so unlike Slash's function form it cannot be deferred; the
    -- value has to be resolvable HERE. The TOC move (see TOC POSITION above) is
    -- the belt; reading the manifest first is the braces.
    --
    -- The TOC manifest is the better source anyway: it cannot drift from
    -- the packaged build (slash-commands-§3). NS.VERSION remains the fallback for
    -- a client without the metadata API — both live in core/EnvSetup.lua now, so
    -- `/kcd version` and a capture record resolve the SAME function rather than
    -- two copies of one ladder that were free to drift apart.
    version = NS.Version(),
    sv      = "KickCDPerfDB",

    -- Ordered for the report, with nesting DECLARED rather than left as prose:
    -- SendMessage dispatches inline through CallbackHandler, so IconGrid's
    -- spell-state handler really does execute inside Cooldowns:Refresh's frame.
    -- A reader comparing two captures months apart cannot be expected to know
    -- which totals overlap, and a parent must never be summed with its children.
    buckets = {
        { key = "spellPoll" },                          -- Cooldowns:Refresh, the coalesced pass
        { key = "pollSpell",  within = "spellPoll"  },  -- Cooldowns:PollSpell, per watched spell
        { key = "spellState", within = "spellPoll"  },  -- IconGrid:OnSpellState, synchronous
        { key = "iconApply",  within = "spellState" },  -- Icon:Apply, per icon per unit
        { key = "cdText" },                             -- the 0.1s cooldown-text ticker pass
        { key = "castEvent" },                          -- IconGrid:OnUnitCastEvent
        { key = "visibility" },                         -- IconGrid:RefreshVisibility
        { key = "castTick" },                           -- Castbar OnUpdate, per frame while casting
    },

    -- NOTE ON EVIDENCE. Both decisions below were taken off an early live
    -- capture that predates docs/perf-analysis/ and was never committed. Under
    -- performance-§8 an interpretation without its record is an assertion, not
    -- evidence, so the figures that used to be quoted here have been removed
    -- rather than left reading as fact. What survives is the reasoning, which
    -- stands on its own; the next in-game capture lands in a frozen bundle at
    -- docs/perf-analysis/<YYYYMMDD-HHMMSS>/ and can be cited from then on.
    --
    -- `pollSpell` WAS left out at first, on the grounds that its inline
    -- early-return guards would make a single fall-through bracket under-count.
    -- Leaving it out was worse: `spellPoll` is the parent and PollSpell is where
    -- it spends most of its time, so the addon's largest single cost was
    -- attributed to nothing at all. Both of PollSpell's exits are instrumented
    -- now, so the objection is answered rather than avoided.
    --
    -- `visibility` no longer declares `within = "castEvent"`. That reading came
    -- from the dominant IN-COMBAT caller, but RefreshVisibility has seven call
    -- sites and six of them are not cast events (a config change, a target swap,
    -- a layout, ...) — out of combat the parent may not run at all. The report
    -- was indenting a bucket under a parent that had not run, which is worse
    -- than not declaring the relationship: nesting exists to tell a reader which
    -- totals overlap, and that one did not.
    --
    -- STILL NOT DECLARED: `glowGate` (IconGrid:RefreshAllGlows), same
    -- multi-exit shape and no capture has yet pointed at it. `Note()` records an
    -- undeclared key anyway, so it can be added ad hoc the moment one does.

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

    -- NO `L`, deliberately, and this is a trap rather than an omission.
    --
    -- NS.L carries the metatable fallback the standard mandates (anti-patterns
    -- #2): a miss returns the KEY rather than nil, so `NS.L["STEP_START"]` is
    -- the string "STEP_START". The library resolves a descriptor's `L` first and
    -- only falls through to its own STRINGS when the override is not a string —
    -- so handing it NS.L satisfies that check for EVERY key, its own strings
    -- become unreachable, and the panel renders STEP_START / STEP_MEASURE_A /
    -- PANEL_TITLE_SUFFIX verbatim. Which is exactly what shipped, and it was
    -- visible only in game.
    --
    -- KickCD has no perf translations, so the right answer is to pass nothing
    -- and let the library's English through. A host that DOES want to override
    -- must pass a PLAIN table holding only the keys it actually translates —
    -- never the addon-wide locale table. settings/Slash.lua does exactly that.

    -- Built by the addon's ONE close-button wrapper (core/CoreSetup.lua) rather
    -- than a lookalike or a second route to the same library function, so this
    -- panel and the debug console beside it cannot drift apart. The wrapper is
    -- what supplies the addon FOLDER name the library needs to build a texture
    -- path from; calling the library seam directly from here would compile, run,
    -- pass every suite, and quietly draw a multiplication sign on the one window
    -- in this addon whose close button the host builds (anti-patterns-§64).
    decorate = function(frame, api)
        if not NS.MakeCloseButton then return end
        local close = NS.MakeCloseButton(frame, api.Hide)
        -- The factory answers nil where CreateFrame is unavailable — a close
        -- button is worth degrading over, not erroring over.
        if close then
            close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(api.TITLE_H - 18) / 2)
            frame.closeButton = close
        end
    end,
})
