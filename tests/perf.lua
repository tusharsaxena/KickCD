-- tests/perf.lua — the offline scenario runner (performance-§9).
--
--   lua tests/perf.lua [--out <path>] [--label <text>]
--
-- DELIBERATELY OUTSIDE THE GREEN GATE. `lua tests/run.lua` does not invoke this and no commit
-- depends on it. What it asserts is the DETERMINISTIC half — WoW API calls and bytes allocated per
-- iteration — never wall-clock time, which varies with the machine and the CPU governor and would
-- turn this into a flake generator nobody reads.
--
-- Timings are printed for orientation ONLY. Read them as ratios between scenarios inside one run,
-- never as absolute numbers to compare across machines.
--
-- Why these scenarios: KickCD's cost is not driven by frame rate, it is driven by
-- C_Spell.GetSpellCooldownDuration minting a FRESH handle on every call (docs/midnight-quirks.md).
-- Cooldowns:StateChanged therefore cannot conclude "nothing moved" for a spell parked on an
-- unchanged cooldown, so the whole spellPoll -> spellState -> iconApply chain re-runs ~10x/second
-- per watched spell per enabled unit. That chain is the addon, so it is what is measured here — the
-- same four buckets core/PerfSetup.lua declares for the in-game probe.
--
-- Output is the shared record schema, encoded by the SAME NS.Perf.EncodeJSON the in-game probe
-- uses, so an offline record and an in-game record are guaranteed to be the same shape.

local root = (arg and arg[0] and arg[0]:match("^(.*)/tests/perf%.lua$")) or "."
package.path = root .. "/tests/?.lua;" .. package.path

local Loader  = dofile(root .. "/tests/_kit/loader.lua")
local mockmod = assert(loadfile(root .. "/tests/wow_mock.lua"))(root)

-- Each dofile of the kit loader returns a FRESH table, so this runner sets its own addonName
-- rather than inheriting one from tests/run.lua. Chunks are called as ("KickCD", NS) to match the
-- client's `local addonName, NS = ...` header — core/PerfSetup.lua reads that first argument.
Loader.addonName = "KickCD"

-- ── arguments ───────────────────────────────────────────────────────────────────────────────

local opts = { out = nil, label = "offline" }
do
    local i = 1
    while arg and arg[i] do
        local a = arg[i]
        if a == "--out" then opts.out = arg[i + 1]; i = i + 2
        elseif a == "--label" then opts.label = arg[i + 1] or opts.label; i = i + 2
        else
            io.stderr:write("unknown argument: " .. tostring(a) .. "\n")
            io.stderr:write("usage: lua tests/perf.lua [--out <path>] [--label <text>]\n")
            os.exit(2)
        end
    end
end

-- ── environment ─────────────────────────────────────────────────────────────────────────────
--
-- Both load lists are DERIVED, never typed here (testing-§9). This runner is not executed by
-- `lua tests/run.lua`, so a hand-maintained list would rot silently while the allocation figures
-- it produces were still being read as evidence. The library half comes from LibKa0s.xml — the
-- file the TOC actually reaches — because omitting Core.lua does not fail loudly: Perf simply
-- refuses to register, NS.Perf becomes the degradation stub, and the zero-overhead scenario
-- quietly measures a stub with no probe in it.

local mocks = mockmod.build()
mocks._G = Loader.makeEnv(mocks)

local NS = {}
Loader.loadAll(Loader.xmlFiles(root .. "/libs/LibKa0s/LibKa0s.xml"), NS, mocks)
do
    local toc = Loader.tocFiles(root .. "/KickCD.toc")
    for i, rel in ipairs(toc) do toc[i] = root .. "/" .. rel end
    Loader.loadAll(toc, NS, mocks)
end

assert(NS.Perf and NS.Perf.Note, "NS.Perf did not resolve — the library load list is wrong")
assert(NS.Perf.SCHEMA, "NS.Perf is the degradation stub, not the library instance")

pcall(NS.OnInitialize, NS)
NS:__enableAll()
if mocks.__flushTimers then mocks.__flushTimers() end

local Cooldowns = NS:GetModule("Cooldowns")
local IconGrid  = NS:GetModule("IconGrid")

-- Both units enabled is the default profile AND the worst realistic case: every SPELL_STATE fans
-- out to two grids.
local target = IconGrid:GetInstance("target")
assert(target and target.enabled, "the target grid did not come up — nothing to measure")

local SPELL_ID
for id in pairs(target.pool.active) do
    if not SPELL_ID or id < SPELL_ID then SPELL_ID = id end
end
assert(SPELL_ID, "the target grid has no active icons — the default spell list did not seed")

local icon = target.pool.active[SPELL_ID]

-- ── the API counting layer ──────────────────────────────────────────────────────────────────
--
-- Wrapped HERE rather than inside tests/wow_mock.lua on purpose: the gated suite must keep
-- measuring the addon, not a counting shim, and a mock that counted for everyone would be one more
-- thing every future case has to reason about. `_G.C_Spell` resolves through the mock table on
-- every read (the loader's env has no local capture), so replacing the functions after load is
-- enough — core/Compat.lua's every spell read lands on one of these.

local apiCalls = 0
for name, fn in pairs(mocks.C_Spell) do
    if type(fn) == "function" then
        mocks.C_Spell[name] = function(...) apiCalls = apiCalls + 1; return fn(...) end
    end
end

-- ── measurement helpers ─────────────────────────────────────────────────────────────────────

local results  = {}
local failures = {}

local function assert_(cond, msg)
    if not cond then failures[#failures + 1] = msg end
    return cond
end

--- Run `fn` `iterations` times, reporting wall time, API calls and bytes allocated PER ITERATION.
---
--- The allocation figure is the load-bearing one. A full collect either side isolates the garbage
--- this path actually produces, and garbage per poll is what turns a cheap-looking function into a
--- frame-rate problem once it runs at 10 Hz per spell per unit in combat.
local function measure(name, iterations, fn)
    collectgarbage("collect")
    collectgarbage("collect")
    apiCalls = 0
    local kbBefore = collectgarbage("count")
    local t0 = os.clock()
    for i = 1, iterations do fn(i) end
    local elapsed = os.clock() - t0
    local kbAfter = collectgarbage("count")

    local r = {
        name         = name,
        iterations   = iterations,
        totalMs      = elapsed * 1000,
        msPerIter    = (elapsed * 1000) / iterations,
        apiCalls     = apiCalls,
        apiPerIter   = apiCalls / iterations,
        bytesPerIter = ((kbAfter - kbBefore) * 1024) / iterations,
    }
    results[#results + 1] = r
    return r
end

--- A fresh SPELL_STATE payload for a spell parked on an unchanged cooldown — a brand-new
--- cdObject handle carrying the same plain fields, which is exactly what the live API hands back.
local function onCooldownState()
    return {
        spellID = SPELL_ID, ready = false, isActive = true,
        cdObject = mocks.__makeDurationObject(12), chargeCdObject = nil, charges = nil,
    }
end

-- ── scenarios ───────────────────────────────────────────────────────────────────────────────

local ITERS = 2000

-- 1. spellPoll — Cooldowns:Refresh over the whole watched set. The coalescer collapses a burst of
--    SPELL_UPDATE_* into one of these, so this is the per-frame ceiling of the polling half.
local watchedCount = 0
for _ in pairs(Cooldowns.watched) do watchedCount = watchedCount + 1 end
assert_(watchedCount > 0, "nothing is being watched — spellPoll would measure an empty loop")

local spellPoll = measure("spellPoll", ITERS, function()
    Cooldowns:Refresh()
end)
assert_(spellPoll.apiPerIter > 0, "spellPoll made no API calls — the counting layer is not attached")
assert_(spellPoll.apiPerIter == watchedCount * 3,
    ("spellPoll makes %.1f API calls/pass over %d watched spells, expected %d (3 per spell)")
        :format(spellPoll.apiPerIter, watchedCount, watchedCount * 3))

-- 2. spellState — the fan-out. One cooldown-state change reaches every enabled unit's active pool.
local statePayload = onCooldownState()
measure("spellState", ITERS, function()
    IconGrid:OnSpellState(nil, statePayload)
end)

-- 3. iconApply — the innermost bucket, run once per icon per unit per poll. This is the steady
--    state: the same logical state re-applied, so the plain-state gate holds and only the
--    time-varying half (curves, swipe handle, countdown text) runs.
local iconApply = measure("iconApply", ITERS, function()
    icon:Apply(statePayload)
end)

-- 4. THE ZERO-OVERHEAD SCENARIO (performance-§9 MUST). The instrumentation must be free when
--    capture is off, or the measurement tool is itself the regression. Same path, brackets dormant
--    versus armed.
local probeOff = measure("probeOverheadOff", ITERS, function()
    icon:Apply(statePayload)
end)
NS.Perf.on = true
local probeOn = measure("probeOverheadOn", ITERS, function()
    icon:Apply(statePayload)
end)
NS.Perf.on = false

-- The relation alone cannot go red the way it matters: if a regression adds allocation to
-- Icon:Apply itself, BOTH arms rise together and `off <= on + 1` still holds. The dormant arm
-- therefore also carries an ABSOLUTE ceiling, set just above the measured figure. Raise it only
-- with a recorded reason — a rise IS the finding.
local PROBE_OFF_BYTES_CEILING = 900   -- measured 848.0 with the brackets dormant

assert_(probeOff.bytesPerIter <= PROBE_OFF_BYTES_CEILING,
    ("a dormant pass allocated %.1f bytes/iter, over the %d-byte ceiling — Icon:Apply grew")
        :format(probeOff.bytesPerIter, PROBE_OFF_BYTES_CEILING))
assert_(probeOff.bytesPerIter <= probeOn.bytesPerIter + 1,
    ("a dormant bracket allocated %.1f bytes/iter against the armed arm's %.1f — the gating idiom "
     .. "is wrong (performance-§2 wants one upvalue read, one field read, one boolean test)")
        :format(probeOff.bytesPerIter, probeOn.bytesPerIter))
assert_(probeOff.apiPerIter == probeOn.apiPerIter,
    ("the probe changed how many API calls a pass makes: %.1f dormant against %.1f armed")
        :format(probeOff.apiPerIter, probeOn.apiPerIter))
assert_(math.abs(iconApply.bytesPerIter - probeOff.bytesPerIter) < 1,
    "the dormant arm did not reproduce the plain iconApply figure — the two are the same path")

-- ── report ──────────────────────────────────────────────────────────────────────────────────

print(("Ka0s KickCD \226\128\148 offline perf  (v%s, label '%s')"):format(NS.VERSION, opts.label))
print(("%d spells watched, %d units enabled, spell %d measured")
    :format(watchedCount, #NS.Units.LIST, SPELL_ID))
print()
print(("%-18s %10s %12s %12s %12s"):format("scenario", "iters", "ms/iter", "api/iter", "bytes/iter"))
for _, r in ipairs(results) do
    print(("%-18s %10d %12.5f %12.1f %12.1f")
        :format(r.name, r.iterations, r.msPerIter, r.apiPerIter, r.bytesPerIter))
end
print()
print("timings are for orientation only \226\128\148 compare scenarios within a run, never across machines")

if #failures > 0 then
    print()
    print(("%d assertion%s FAILED:"):format(#failures, #failures == 1 and "" or "s"))
    for _, f in ipairs(failures) do print("  - " .. f) end
end

-- ── record ──────────────────────────────────────────────────────────────────────────────────

if opts.out then
    local buckets = {}
    for _, r in ipairs(results) do
        -- Map the scenario onto the shared bucket shape: `calls` is the iteration count and
        -- `totalMs` / `maxMs` carry the same meaning as in-game, so one reader handles both
        -- sources. No `within`, deliberately: each scenario is driven directly and times only its
        -- own loop, so no scenario's total is contained in another's — which is precisely what a
        -- missing `within` means in the record schema. The in-game buckets DO nest; these do not,
        -- and claiming otherwise would be the exact false containment performance-§3 forbids.
        buckets[r.name] = {
            calls        = r.iterations,
            totalMs      = r.totalMs,
            maxMs        = r.msPerIter,
            apiPerIter   = r.apiPerIter,
            bytesPerIter = r.bytesPerIter,
        }
    end

    local record = {
        schema    = NS.Perf.SCHEMA,
        addon     = "KickCD",
        source    = "offline",
        version   = NS.VERSION,
        interface = 0,          -- no client involved
        timestamp = os.time(),
        label     = opts.label,
        buckets   = buckets,
        fps       = {           -- fixed shape; an offline run has no frames to sample
            active    = { seconds = 0, frames = 0, avgFps = 0, msPerFrame = 0 },
            suspended = { seconds = 0, frames = 0, avgFps = 0, msPerFrame = 0 },
            deltaMsPerFrame = 0,
        },
        watched   = watchedCount,
        failures  = failures,
    }

    local fh, err = io.open(opts.out, "w")
    if not fh then
        io.stderr:write("cannot write " .. opts.out .. ": " .. tostring(err) .. "\n")
        os.exit(2)
    end
    fh:write(NS.Perf.EncodeJSON(record), "\n")
    fh:close()
    print("wrote " .. opts.out)
end

os.exit(#failures == 0 and 0 or 1)
