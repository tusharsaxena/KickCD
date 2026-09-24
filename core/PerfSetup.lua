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
-- DURING a cast), no combat-log parsing, and the per-unit cast-filter frames are
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

-- There is no `runtimeModules()` helper here any more, and its absence is the
-- point: which modules go inert, and in which order, is core/LifecycleSetup.lua's
-- answer now, given once for both reasons to be inert rather than once here and
-- again wherever `disable` was implemented.

NS.Perf = lib:New({
    name    = addonName,
    -- THE FOLDER NAME, and a different question from the one above even though
    -- this addon answers both with the same string. `name` is what the panel's
    -- frame globals are seeded from; `addonName` is what
    -- libs/LibKa0s/PerfPanel.lua builds the close control's texture path from,
    -- and it reads `d.addonName or d.name` -- so leaving this out would still be
    -- right, by luck, until the day the two strings diverge. `title` below is
    -- already a THIRD string, which is what a rename reaches for first. Passed
    -- explicitly for the same reason core/DebugLogSetup.lua passes it, and the
    -- two descriptors are deliberately the same shape.
    addonName = addonName,
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
    --
    -- spellState declares stateEmit, the steady-state path. Cooldowns:Rebuild
    -- publishes too, from outside any poll, so its emit is the ROOT bucket
    -- rebuildEmit and IconGrid:OnSpellState passes whichever parent it ran
    -- under: a capture that saw a Rebuild reports spellState as observedMixed
    -- instead of silently claiming stateEmit for every call.
    buckets = {
        { key = "spellPoll" },                          -- Cooldowns:Refresh, the coalesced pass
        { key = "pollSpell",  within = "spellPoll"  },  -- Cooldowns:PollSpell, per watched spell
        { key = "stateEmit",  within = "spellPoll"  },  -- the SPELL_STATE publish, per emitting spell
        { key = "spellState", within = "stateEmit"  },  -- IconGrid:OnSpellState, synchronous
        { key = "iconApply",  within = "spellState" },  -- Icon:Apply, per icon per unit
        { key = "cdText" },                             -- the 0.1s cooldown-text ticker pass
        { key = "castEvent" },                          -- IconGrid:OnUnitCastEvent
        { key = "glowGate" },                           -- IconGrid:RefreshAllGlows
        { key = "visibility" },                         -- IconGrid:RefreshVisibility
        { key = "castTick" },                           -- Castbar OnUpdate, per frame while casting
        { key = "rebuildEmit" },                        -- Cooldowns:Rebuild's publish, outside any poll
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
    -- `stateEmit` EXISTS BECAUSE A CAPTURE ASKED A QUESTION THE BUCKETS COULD
    -- NOT ANSWER. docs/perf-analysis/20260909-014035 recorded one `spellPoll`
    -- pass at 9.6400 ms — 37x its own mean and 69.7% of that capture's 13.83 ms
    -- frame — with NO child anywhere near it (`pollSpell` max 0.2961,
    -- `spellState` 0.2135, `iconApply` 0.1948). The cost was inside
    -- Cooldowns:Refresh and outside every bracket it contained, so the record
    -- could locate the hitch to a function and no further.
    --
    -- What sat in that gap was the publish. `spellState` brackets the SUBSCRIBER
    -- (IconGrid:OnSpellState); nothing bracketed the `NS:SendMessage` around it,
    -- which is CallbackHandler's dispatch plus the six-field payload table this
    -- loop allocates per emitting spell — ~2 emits per pass, so ~1590 tables
    -- across that capture's 810 passes. A collection landing inside the bracket
    -- is charged to whatever pass was unlucky, which is the shape a lone 9.64 ms
    -- outlier with no child spike actually has. `stateEmit` measures the publish
    -- so the next capture can separate dispatch from handler, and
    -- `spellPoll - pollSpell - stateEmit` is then the bare loop.
    --
    -- NOT `glowGate`, which the 20260909 write-up first proposed and which
    -- would have measured the wrong function: RefreshAllGlows is NOT reachable
    -- from Cooldowns:Refresh. The only glow work on the poll path is
    -- Icon:UpdateGlow, called from Icon:Apply (modules/IconGrid_Render.lua:787)
    -- and therefore already inside `iconApply`.
    --
    -- `glowGate` IS declared now, on its own merits rather than that one's:
    -- RefreshAllGlows walks every active icon into UpdateGlow, and four of its
    -- five call sites (EnableUnit, a config change, a target swap, a focus swap)
    -- sit inside no bracket at all, so LibCustomGlow's cost has been invisible
    -- in every capture taken so far.
    --
    -- It declares NO `within`, for the reason the paragraph above gives for
    -- `visibility`: only OnUnitCastEvent's call site runs inside `castEvent`,
    -- and out of combat that parent may not run at all. Both buckets therefore
    -- overlap `castEvent` on one path and stand alone on the others — which is
    -- why the report's roots must not be summed, and why neither claims a
    -- parent it cannot keep.

    -- THE LATCH, NOT A PAIR OF CALLBACKS (LibKa0s-Perf-1.0 minor 12,
    -- slash-commands-§7). This descriptor used to carry `suspend` and `resume`,
    -- and the library called them directly. It no longer does: the suspended arm
    -- takes the `perf` HOLD on the latch below, and the host's own standDown /
    -- standUp -- core/LifecycleSetup.lua's, the same two functions `disable`
    -- reaches -- are what run on the edge.
    --
    -- That is the whole of the anti-pattern this closes (#85). A second teardown
    -- written beside this one for `disable` would be two mechanisms that both
    -- mean "be inert", and they drift on the first module added after the second
    -- was written. There is now ONE, and this file no longer owns it.
    --
    -- The other half is the four-state problem a boolean cannot hold: a player
    -- can `/kcd disable` DURING a suspended arm, and `/kcd enable` there too.
    -- With a boolean, the run's resume brings the addon back under a player who
    -- switched it off. With two holds, releasing `perf` leaves `disabled` taken
    -- and nothing is rebuilt.
    --
    -- `NS.Perf.suspended` still answers, and still means exactly what it meant --
    -- it is a VIEW of the latch's `perf` hold now rather than a boolean beside
    -- it. Visibility is still enforced at the SOURCE: the show ladders ask
    -- NS.IsDown(), which is the latch, so nothing -- a combat transition, a
    -- target swap, a settings change -- can re-show a grid behind it.
    lifecycle = NS.Lifecycle,

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

    -- NO `decorate`, and the descriptor deliberately ends here. This file used
    -- to supply that hook, and by the end its whole body was a close button:
    -- LibKa0s-Perf's own panel draws the identical control in its else arm
    -- (libs/LibKa0s/PerfPanel.lua:185-196) out of the same LibKa0s-Core factory,
    -- at the same TOPRIGHT anchor and the same -(TITLE_H - 18) / 2 offset,
    -- resolving the folder through `d.addonName or d.name` -- which the
    -- `addonName` field above answers explicitly rather than by luck.
    --
    -- THE HOOK EARNED ITS PLACE ONCE. It began as
    -- `NS.DebugLog.MakeCloseButton(frame, api.Hide)`, two arguments onto a
    -- three-argument function, so this panel drew a multiplication sign while
    -- the console beside it wore the collection's mark -- a texture path that is
    -- never built draws nothing and raises nothing, so luacheck was clean and
    -- every suite was green. Routing it through NS.MakeCloseButton fixed the
    -- drawing and made the hook IDENTICAL to the arm it was shadowing, which is
    -- the point at which a private copy stops being a fix and becomes a
    -- liability: the two arms are EXCLUSIVE, so for as long as `decorate` sat
    -- here the library's own control never ran once, in any client, and nothing
    -- would have said so the day the two drifted (performance-§4,
    -- anti-pattern #64). tests/test_perfsetup.lua pins BOTH directions -- the
    -- folder name present, the hook absent -- and then shows the real panel
    -- against a spy on the library's factory, because a descriptor's shape says
    -- nothing about what reaches the screen.
    --
    -- Add one back only for chrome the library does not draw, and build its
    -- close control through `NS.MakeCloseButton` (core/CoreSetup.lua) -- the one
    -- wrapper that carries the folder name -- never through the library seam
    -- directly.
})
