-- tests/sim_support.lua — the simulator suites' shared fixture (not a suite: tests/run.lua does
-- not declare it, and the kit's suite inventory reads only `test_*.lua`).
--
-- KC-03 (KickCD#38). tests/test_sim_seam.lua and the KC-04..KC-09 suites build on it:
--
--   local S = dofile(T.root .. "/tests/sim_support.lua")
--   local env = S.load()            -- a fresh, enabled instance: env.NS, env.mocks, helpers
--   env.advance(12)                 -- the clock moves 12 s; every timer due by then fires, in order
--   local sim, restore = S.testSession(env, { { kind = "Noop" } })
--
-- ISOLATION. Every environment is its own T.load, never the shared T.NS: a simulator session binds
-- its seam for good (one seam binds one session), and a provider or a world left on the shared
-- instance would answer for every suite after this one.
--
-- THE CLIENT IT MODELS. An enUS Enhancement Shaman whose default spell list (defaults/Spells.lua)
-- carries Wind Shear (57994, `interrupt`) and Capacitor Totem (192058, `stun`) — and Hex (51514),
-- which the default list carries too — every one known (`IsPlayerSpell` true). The kit's clock
-- (`mocks.__now`) drives `GetTime`, which this addon's mock otherwise pins at 0, and
-- `C_DurationUtil.CreateDuration` answers a Lua duration fake read off that same clock, so
-- core/Compat.lua's NewDuration builds a duration whose remaining time really runs down.

local T = _G.KICKCD_TEST

local S = {}

S.KICK, S.CC, S.HEX = 57994, 192058, 51514
S.SHAMAN_CLASS_ID, S.ENHANCEMENT_INDEX, S.ENHANCEMENT = 7, 2, 263

-- ── the duration fake ─────────────────────────────────────────────────────────────────────────

--- Evaluate a mock curve (tests/wow_mock.lua's C_CurveUtil shape: `points = { {at, value}, ... }`)
--- the way the client does: the last control point at or below `at`, else the first one. Nil for a
--- curve with no points.
local function evaluateCurve(curve, at)
    local pts = type(curve) == "table" and curve.points
    if not (pts and pts[1]) then return nil end
    local chosen = pts[1]
    for _, p in ipairs(pts) do
        if p.at <= at then chosen = p else break end
    end
    return chosen.value
end

--- A fresh duration object on `mocks`' clock. Every getter reads `mocks.GetTime()` at call time, so
--- a test that advances the clock sees the remaining time fall. Never secret.
local function newDuration(mocks)
    local d = { start = 0, total = 0 }
    function d.SetTimeFromStart(self, startTime, duration)
        self.start, self.total = tonumber(startTime) or 0, tonumber(duration) or 0
    end
    function d.GetStartTime(self) return self.start end
    function d.GetTotalDuration(self) return self.total end
    function d.GetElapsedDuration(self)
        local e = mocks.GetTime() - self.start
        if e < 0 then return 0 end
        if e > self.total then return self.total end
        return e
    end
    function d.GetRemainingDuration(self) return self.total - self:GetElapsedDuration() end
    function d.EvaluateRemainingDuration(self, curve)
        local at = self:GetRemainingDuration()
        local v = evaluateCurve(curve, at)
        if v == nil then return at end
        return v
    end
    function d.EvaluateTotalDuration(self, curve)
        local v = evaluateCurve(curve, self.total)
        if v == nil then return self.total end
        return v
    end
    function d.HasSecretValues() return false end
    return d
end
S.newDuration = newDuration

-- ── the clock ─────────────────────────────────────────────────────────────────────────────────

local function canceled(t) return t.cancelled or (t.timer and t.timer.cancelled) end

--- Move `mocks`' clock forward `seconds`, firing every timer that falls due on the way, earliest
--- first and in queue order on a tie (BankLedger's tests/sim_support.lua clock). A timer queued
--- before this call is taken to have been queued now: the kit's queue records a delay, not a due
--- time. A timer a fired one arms joins the run when it falls inside the window (the cooldown
--- ticker re-arms itself this way). Entries left over go back on the queue with the rest of their
--- delay. Bounded, so a runaway chain fails the case instead of hanging the run.
local function advance(mocks, seconds)
    local stop = mocks.__now + (seconds or 0)
    local pending, seq = {}, 0
    local function collect()
        local q = mocks.__timers
        if #q == 0 then return end
        mocks.__timers = setmetatable({}, getmetatable(q))
        for _, t in ipairs(q) do
            seq = seq + 1
            pending[#pending + 1] = { t = t, due = mocks.__now + (tonumber(t.delay) or 0), seq = seq }
        end
    end
    for _ = 1, 10000 do
        collect()
        local best
        for i, p in ipairs(pending) do
            if not canceled(p.t) and (not best or p.due < pending[best].due
                or (p.due == pending[best].due and p.seq < pending[best].seq)) then
                best = i
            end
        end
        if not best or pending[best].due > stop then break end
        local p = table.remove(pending, best)
        if p.due > mocks.__now then mocks.__now = p.due end
        p.t.fn()
    end
    mocks.__now = math.max(mocks.__now, stop)
    collect()
    for _, p in ipairs(pending) do
        if not canceled(p.t) then
            p.t.delay = math.max(0, p.due - mocks.__now)
            mocks.__timers[#mocks.__timers + 1] = p.t
        end
    end
end

--- Fire every timer due NOW (delay 0 after an advance, or anything queued), repeatedly, since a
--- timer may arm the next one. Stops at the first round that runs nothing. Bounded: a ticker that
--- re-arms forever ends the drain after twenty rounds rather than hanging it.
local function flush(mocks)
    for _ = 1, 20 do
        if mocks.__fireTimers() == 0 then return end
    end
end

-- ── the environment ───────────────────────────────────────────────────────────────────────────

--- A fresh instance of the whole addon on the Shaman client above.
--- @param opts table|nil  { enable = false } skips the enable cascade (default: enabled);
---        { mutate = fn(mocks) } reshapes the mock further before any source loads;
---        { loadOpts = { ... } } is handed to T.load as its fourth argument (libFiles, afterFile).
--- @return table env  { NS, mocks, inst, advance(sec), flush(), snapshotDB() }
function S.load(opts)
    opts = opts or {}
    local inst = T.load(true, opts.enable ~= false, function(mocks)
        mocks.GetTime = function() return mocks.__now end
        mocks.C_DurationUtil = { CreateDuration = function() return newDuration(mocks) end }
        mocks.UnitClass = function() return "Shaman", "SHAMAN", S.SHAMAN_CLASS_ID end
        mocks.__setPlayerSpec(S.SHAMAN_CLASS_ID, S.ENHANCEMENT_INDEX)
        mocks.IsPlayerSpell = function() return true end
        if opts.mutate then opts.mutate(mocks) end
    end, opts.loadOpts)
    local env = { NS = inst.NS, mocks = inst.mocks, inst = inst }
    function env.advance(seconds) advance(env.mocks, seconds) end
    function env.flush() flush(env.mocks) end
    --- A deep copy of the KickCDDB SavedVariables root, for a byte-for-byte before/after (H4).
    --- AceDB's db.sv IS that root; the global is read first, the db's view second.
    function env.snapshotDB()
        local root = env.mocks.KickCDDB or (env.NS.db and env.NS.db.sv)
        return env.mocks.__deepcopy(root)
    end
    return env
end

-- ── a throwaway session (PLAN-REVIEW RESOLUTION) ──────────────────────────────────────────────
--
-- Until modules/Sim.lua (KC-05) builds the live host, NS.Sim is core/SimSetup.lua's stub, so a suite
-- that needs a RUNNING session builds its own here: a real LibStub("LibKa0s-Sim-1.0"):New bound to
-- the environment's own NS.SimSeam and delivering through NS.DeliverEvent, the LibKa0s
-- tests/test_sim_host.lua shape. One scenario, `test`, whose timeline is the steps the caller passes
-- (copied per session: the library stamps `ranAt`, `detail` and `index` onto a step that ran).
--
-- One seam binds one session for good, so the instance is built once per environment and kept on
-- it; a later call swaps in new steps and hooks. Once KC-05 binds the seam at load, a second New on
-- it raises, and this fixture must move to injecting its scenario into the live host instead.

--- Build (once per env) and, unless `opts.start == false`, start a throwaway session over `steps`,
--- pointing env.NS.Sim at it. Answers the instance and a restore() that stops the session, drains
--- its timers and puts the previous NS.Sim back. Always call restore (S.withTestSession does).
--- @param opts table|nil  { start = false } builds without starting; { play = fn(step, session) }
---        drives each step (default: NS.SimHost.Play when a host publishes one, else nothing);
---        { prepare = fn(session, opts) } runs before ready(); { stepDelay = n|fn } paces Run.
function S.testSession(env, steps, opts)
    opts = opts or {}
    local NS, mocks = env.NS, env.mocks
    local state = env.__testSim
    if not state then
        local Sim = mocks.LibStub("LibKa0s-Sim-1.0", true)
        assert(Sim, "the environment has no LibKa0s-Sim-1.0")
        state = { steps = {} }
        state.sim = Sim:New{
            name = "KickCD",
            seam = NS.SimSeam,
            slash = "/kcd sim",
            deliver = function(event, ...) return NS.DeliverEvent(event, ...) end,
            isStoodDown = function() return NS.IsDown and NS.IsDown() or false end,
            scenarios = {
                names = { "test" },
                defs = { test = { label = "Test", timeline = function()
                    local out = {}
                    for i, step in ipairs(state.steps) do
                        local copy = {}
                        for k, v in pairs(step) do copy[k] = v end
                        out[i] = copy
                    end
                    return out
                end } },
            },
            prepare = function(session, _, startOpts, ready)
                if state.prepare then state.prepare(session, startOpts) end
                ready()
            end,
            play = function(step, session)
                local fn = state.play or (NS.SimHost and NS.SimHost.Play)
                if fn then return fn(step, session) end
            end,
            stepDelay = function(step)
                local d = state.stepDelay
                if type(d) == "function" then return d(step) end
                return d or (step and step.wait) or 1
            end,
            print = function(line) if NS.Util and NS.Util.print then NS.Util.print(line) end end,
        }
        env.__testSim = state
    end
    state.steps = steps or {}
    state.play, state.prepare, state.stepDelay = opts.play, opts.prepare, opts.stepDelay

    local sim = state.sim
    local previous = NS.Sim
    NS.Sim = sim
    if opts.start ~= false then
        local ok, line = sim:Start{ scenario = "test" }
        assert(ok, "the test session did not start: " .. tostring(line))
    end
    local function restore()
        if sim:IsActive() then sim:Stop("stop") end
        flush(mocks)
        NS.Sim = previous
    end
    return sim, restore
end

--- Run `fn(sim)` inside a test session over `steps`, restoring whatever happens.
function S.withTestSession(env, steps, fn, opts)
    local sim, restore = S.testSession(env, steps, opts)
    local ok, err = pcall(fn, sim)
    restore()
    if not ok then error(err, 0) end
end

return S
