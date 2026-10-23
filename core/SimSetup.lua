local addonName, NS = ...
-- core/SimSetup.lua — the simulator's answer seam, on LibKa0s-Sim-1.0 (library-stack-§7; KickCD#38,
-- LibKa0s#54; the host contract H1-H10 is in the vendored LibKa0s's docs/api/Sim/, version 2.3.5).
-- Modeled line for line on BankLedger's core/SimSetup.lua.
--
-- THE SEAM. At load, straight after core/Compat.lua and before any other file can read a member
-- (the LOAD-BEARING TOC slot, host contract H2), Sim:NewSeam wraps every NS.Compat function member
-- in place, once, except the four PURE ones below. While a simulation session runs, a wrapped member
-- asks the simulator's provider first; idle, it calls straight through to the live member, so the
-- whole cost of the seam is one field test per call. This file names no client API: core/Compat.lua
-- stays the only caller (compat). A member added to NS.Compat after this file loads, or one
-- replaced by assignment, escapes the wrap; the seam's Unwrapped() lists it, and
-- tests/test_sim_seam.lua asserts that list is empty after the whole addon loads.
--
-- PURE. IsSecret is the secret-value guard and _firstReturn a multi-return helper: both answer for
-- nobody. NewDuration is a constructor over C_DurationUtil, and the simulator builds its own
-- durations through it. DebugInterrupt dumps the REAL client for `/kcd debug interrupt` on purpose
-- (core/Compat.lua says why). None of the four is ever wrapped.
--
-- GUARDED: none. KickCD sends nothing, casts nothing and acts on nothing in the world (design D6):
-- every Compat member is a read, so there is no outward action for a session to intercept.
--
-- HOST TABLES (OWNER_SCOPE C.4). NS.SimHost is the host's own table for host fields (its world, its
-- counters); NS.SimSeam is the seam, held for SetProvider and Live. Nothing host-side is ever
-- written onto the library instance or the seam.
--
-- LIBRARY ABSENT. Nothing is wrapped. NS.SimSeam is the inert seam stub and NS.Sim the inert
-- session stub, both the library's reference copies (LibKa0s tests/test_sim_stub.lua): every
-- member answers, nothing simulates, and `/kcd sim` says the simulator needs the library.
--
-- LIBRARY PRESENT. NS.Sim is the live instance modules/Sim.lua builds with Sim:New (KC-05). Until
-- that file lands the stub stands in, so `/kcd sim` answers rather than raising; modules/Sim.lua
-- overwrites it.

local Sim = LibStub and LibStub("LibKa0s-Sim-1.0", true)

NS.SimHost = NS.SimHost or {}

-- The members that answer for nobody. Never wrapped.
local PURE = { IsSecret = true, _firstReturn = true, NewDuration = true, DebugInterrupt = true }

-- The seam's debug sink until a session binds: the `Sim` tag, only while the console is on.
local function debug(_, fmt, ...)
    if NS.State and NS.State.debug and NS.Debug then NS.Debug("Sim", fmt, ...) end
end

-- ── the degradation stubs (host contract H9) ──────────────────────────────────────────────────

local function newSeamStub()
    local seam = {}
    function seam.SetProvider() end
    function seam.Live(_, fn, ...) return fn(...) end
    function seam.Keys() return {} end
    function seam.Unwrapped() return {} end
    return seam
end

local function newSimStub(say)
    local line = NS.L["The simulator needs LibKa0s-Sim-1.0."]
    local sim = {}
    local function no() return false end
    local function noop() end
    local function absent() return false, "absent" end
    sim.IsActive, sim.IsDelivering, sim.IsPanelShown = no, no, no
    function sim.Fire() return 0 end
    function sim.DeliverForCleanup() return 0 end
    function sim.After() return nil end
    function sim.Start() say(line); return false, line end
    sim.Stop = no
    sim.OnStop, sim.OnStopGuarded, sim.AddListener = noop, noop, noop
    function sim.Status() return { active = false } end
    function sim.Session() return nil end
    function sim.Steps() return {} end
    function sim.Step() return nil, "absent" end
    sim.Run, sim.Pause, sim.Resume, sim.Restart = absent, absent, absent, absent
    function sim.RunVerb() say(line); return false, "absent" end
    sim.ShowPanel, sim.TogglePanel = no, no
    sim.HidePanel, sim.RefreshPanel, sim.ResetPanelPosition = noop, noop, noop
    function sim.PanelRows() return {} end
    return sim
end

-- The two stubs, exported for tests/test_sim_seam.lua's surface-parity cases (Sim document,
-- *Adopting it* step 4). The `__` prefix keeps them off any public surface.
NS.SimHost.__newSeamStub = newSeamStub
NS.SimHost.__newSimStub = newSimStub

-- NS.Util.print is resolved at call time: core/CoreSetup.lua, which publishes it, loads later.
local function say(line)
    if NS.Util and NS.Util.print then NS.Util.print(line) end
end

-- ── the seam ──────────────────────────────────────────────────────────────────────────────────

if Sim then
    NS.SimSeam = Sim:NewSeam(NS.Compat, {
        name = addonName,
        pure = PURE,
        guarded = {},
        debug = debug,
    })
    -- Until modules/Sim.lua (KC-05) builds the live instance, which overwrites this.
    NS.Sim = NS.Sim or newSimStub(say)
else
    NS.SimSeam = newSeamStub()
    NS.Sim = newSimStub(say)
end
