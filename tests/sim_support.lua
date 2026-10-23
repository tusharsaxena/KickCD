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

-- ── a test session on the live host ──────────────────────────────────────────────────────────
--
-- modules/Sim.lua (KC-05) binds NS.SimSeam to the addon's own NS.Sim at load, and one seam binds one
-- session for good, so a suite cannot build a second instance: it injects a scenario, `test`, into
-- the live host's NS.SimHost.SCENARIOS (read at call time by the library) and starts NS.Sim on it.
-- The timeline is the steps the caller passes, copied per session (the library stamps `ranAt`,
-- `detail` and `index` onto a step that ran). Injected once per environment; a later call swaps in
-- new steps and hooks.
--
-- BARE (the default). The host's own Prepare, Refusal and Play are swapped for the fixture's for
-- the session's life, as the throwaway instance KC-03 built had them: no refusal, a prepare that
-- builds nothing (a world the caller installed stays), and play = opts.play or the host's own.
-- `opts.host = true` keeps the host's real hooks, which tests/test_sim_session.lua drives.

--- Inject the `test` scenario into env's live host once; answers the fixture state.
local function inject(env)
    local state = env.__testSim
    if state then return state end
    local Host = env.NS.SimHost
    assert(Host and Host.SCENARIOS and Host.Prepare, "the environment has no live simulator host")
    state = { steps = {} }
    local defs, names = Host.SCENARIOS.defs, Host.SCENARIOS.names
    defs.test = { label = "Test", timeline = function()
        local out = {}
        for i, step in ipairs(state.steps) do
            local copy = {}
            for k, v in pairs(step) do copy[k] = v end
            out[i] = copy
        end
        return out
    end }
    names[#names + 1] = "test"
    env.__testSim = state
    return state
end

--- Swap the host's hooks for the fixture's (bare mode); answers the function that puts them back.
local function swapHooks(Host, state)
    local saved = { Prepare = Host.Prepare, Refusal = Host.Refusal, Play = Host.Play, DelayAfter = Host.DelayAfter }
    Host.Prepare = function(session, _, startOpts, ready)
        if state.prepare then state.prepare(session, startOpts) end
        ready()
    end
    Host.Refusal = function() return nil end
    Host.Play = function(step, session)
        if state.play then return state.play(step, session) end
        return saved.Play(step, session)
    end
    if state.stepDelay ~= nil then
        Host.DelayAfter = function(step)
            local d = state.stepDelay
            if type(d) == "function" then return d(step) end
            return d
        end
    end
    return function()
        for k, v in pairs(saved) do Host[k] = v end
    end
end

--- Inject the `test` scenario over `steps` and, unless `opts.start == false`, start NS.Sim on it
--- with the member Start (nothing plays until a Step or Run). Answers the live instance and a
--- restore() that stops the session, drains its timers and puts the host's hooks back. Always call
--- restore (S.withTestSession does).
--- @param opts table|nil  { start = false } injects without starting; { host = true } keeps the
---        host's real Prepare/Refusal/Play; { play = fn(step, session) } drives each step;
---        { prepare = fn(session, opts) } runs before ready(); { stepDelay = n|fn } paces Run.
function S.testSession(env, steps, opts)
    opts = opts or {}
    local NS, mocks = env.NS, env.mocks
    local state = inject(env)
    state.steps = steps or {}
    state.play, state.prepare, state.stepDelay = opts.play, opts.prepare, opts.stepDelay

    local unswap = function() end
    if not opts.host then unswap = swapHooks(NS.SimHost, state) end
    local sim = NS.Sim
    if opts.start ~= false then
        local ok, line = sim:Start{ scenario = "test" }
        if not ok then unswap() end
        assert(ok, "the test session did not start: " .. tostring(line))
    end
    local function restore()
        if sim:IsActive() then sim:Stop("stop") end
        flush(mocks)
        unswap()
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
