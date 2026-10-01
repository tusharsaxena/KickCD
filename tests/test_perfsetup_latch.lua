-- tests/test_perfsetup_latch.lua
-- Split from tests/test_perfsetup.lua (#32): testing-§8's last two pins for the
-- LibKa0s-Perf-1.0 adoption -- suspend genuinely makes THIS addon inert (the
-- latch as step 0, the per-unit cast filters, the session-only suspended flag),
-- and the degraded path answers rather than erroring. Case names and bodies are
-- unchanged by the move; every case builds its own instance with T.load.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

-- ── suspend / resume ────────────────────────────────────────────────────────

test("the show decisions consult the LATCH as step 0, at the source", function()
    -- performance-§6: visibility MUST be enforced by the addon's own
    -- show-decision, never by suspend reaching in and hiding frames. A hidden
    -- frame comes back on the next combat transition or target swap, and the
    -- suspended arm then measures the addon still working.
    -- red under: deleting either guard
    local inst = T.load(true, true)
    local NS2 = inst.NS
    local IconGrid = NS2:GetModule("IconGrid", true)
    assertTrue(IconGrid ~= nil)
    assertTrue(IconGrid.ShouldBeVisible ~= nil, "IconGrid.ShouldBeVisible must be published")

    -- DRIVEN THROUGH THE LATCH, not by assigning `Perf.suspended`. That field is
    -- a VIEW of the latch's `perf` hold since LibKa0s-Perf-1.0 minor 12 -- a
    -- write to it raises, deliberately, because a boolean beside the latch is
    -- exactly the second copy that let a resume resurrect an addon the player had
    -- disabled mid-capture (slash-commands-§7).
    local fakeInst = { unit = "target" }
    local beforeCall = IconGrid.ShouldBeVisible(fakeInst)
    NS2.Perf.Suspend()
    local whileSuspended = IconGrid.ShouldBeVisible(fakeInst)
    NS2.Perf.Resume()

    assertEqual(whileSuspended, false, "the grid must refuse to show while suspended")
    assertTrue(beforeCall ~= nil, "sanity: the ladder answered before suspending")
end)

test("suspend disarms the per-unit cast filters AceEvent cannot reach", function()
    -- Each module holds ONE UNIT_SPELLCAST_* filter frame per unit, built by
    -- Util.NewUnitCastFilter and kept on the instance as inst.castFilter;
    -- AceEvent's UnregisterAllEvents only knows its own table.
    local inst = T.load(true, true)
    local NS2 = inst.NS
    local IconGrid = NS2:GetModule("IconGrid", true)
    local Castbar = NS2:GetModule("Castbar", true)
    local gridFilter = IconGrid:GetInstance("target").castFilter
    local barFilter = Castbar:GetInstance("target").castFilter
    assertTrue(gridFilter.armed and barFilter.armed, "sanity: both filters armed before Suspend")

    NS2.Perf.Suspend()
    assertEqual(NS2.Perf.suspended, true, "Suspend must set the flag the ladders read")

    -- Counted, not inferred from visibility: asserting ShouldBeVisible here
    -- would pass on the show-decision guard alone and stay green with the
    -- ReconcileUnits guard deleted — an unfalsifiable assertion, caught by
    -- mutating exactly that.
    assertEqual(inst.mocks.__countFramesFor("UNIT_SPELLCAST_START"), 0,
        "suspend must release every UNIT_SPELLCAST_START registration")
    assertFalse(gridFilter.armed or barFilter.armed, "suspend must disarm both filters")

    assertEqual(IconGrid.ShouldBeVisible({ unit = "target" }), false,
        "and the grid must refuse to show")
    NS2.Perf.Resume()
    assertTrue(gridFilter.armed and barFilter.armed, "Resume must re-arm both filters")
    assertTrue(rawequal(IconGrid:GetInstance("target").castFilter, gridFilter)
        and rawequal(Castbar:GetInstance("target").castFilter, barFilter),
        "Resume must re-arm the SAME filters, not build new ones")
end)

test("enabling a unit while suspended does not re-register its frames mid-capture", function()
    -- THE scenario the ReconcileUnits guard exists for, and the one a naive test
    -- misses: Suspend leaves `inst.enabled` alone, so a plain CONFIG_CHANGED
    -- finds every instance already reconciled and does nothing either way. The
    -- guard only earns its keep when the DESIRED state changes while suspended —
    -- a unit toggled ON — because ReconcileUnits would then call EnableUnit and
    -- re-arm the unit's cast filter in the middle of a capture.
    --
    -- red under: deleting `if NS.IsDown and NS.IsDown() then return end`
    -- from IconGrid:ReconcileUnits
    local inst = T.load(true, true)
    local NS2 = inst.NS
    local H = NS2.Settings.Helpers

    -- Start from focus OFF so enabling it is a real state change.
    H.SetAndRefresh("units.focus.enabled", false)
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end

    NS2.Perf.Suspend()
    assertEqual(inst.mocks.__countFramesFor("UNIT_SPELLCAST_START"), 0,
        "suspend must leave no cast filter registered")

    -- Toggle focus ON while suspended. Without the guard this reaches EnableUnit.
    H.SetAndRefresh("units.focus.enabled", true)
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end
    assertEqual(inst.mocks.__countFramesFor("UNIT_SPELLCAST_START"), 0,
        "a unit enabled while suspended must not arm its filter until Resume")

    -- Resume then honors the CURRENT desired state, focus included.
    NS2.Perf.Resume()
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end
    assertTrue(inst.mocks.__countFramesFor("UNIT_SPELLCAST_START") > 0,
        "Resume must re-arm the cast filters from current state")

    NS2.Perf.Resume()
    assertEqual(NS2.Perf.suspended, false, "Resume must clear the flag")
end)

test("resume restores from CURRENT state, not from a snapshot", function()
    -- performance-§6: a unit toggled while suspended must come back correctly,
    -- which is why Resume rebuilds through ReconcileUnits rather than replaying
    -- what was live at suspend time.
    local inst = T.load(true, true)
    local NS2 = inst.NS
    local H = NS2.Settings.Helpers
    local S = NS2.Settings.Store

    NS2.Perf.Suspend()
    -- Toggle focus off WHILE suspended.
    local before = S.Get("units.focus.enabled")
    H.SetAndRefresh("units.focus.enabled", not before)
    NS2.Perf.Resume()
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end

    -- The addon must reflect the value as it is NOW, not as it was at suspend.
    assertEqual(S.Get("units.focus.enabled"), not before)
    H.SetAndRefresh("units.focus.enabled", before)
end)

test("the suspended flag is session-only and never persisted", function()
    -- performance-§6: a suspended addon that stayed suspended across a /reload
    -- is indistinguishable from a broken one.
    local inst = T.load(true, true)
    inst.NS.Perf.Suspend()
    local db = inst.NS.db
    assertNil(db.profile.perfSuspended, "suspend state must not reach the profile")
    assertNil(db.global and db.global.perfSuspended, "nor the global table")
    inst.NS.Perf.Resume()
end)

-- ── the degraded path ───────────────────────────────────────────────────────

test("with LibKa0s absent the probe stub answers every member the addon calls", function()
    local inst = T.load(true, false, nil, { libFiles = {} })
    local P = inst.NS.Perf
    assertTrue(P ~= nil, "NS.Perf must exist even with no library")
    assertEqual(P.on, false, "the gate must be a real false, so brackets stay inert")
    assertEqual(P.suspended, false, "the show ladders read this unconditionally")
    assertEqual(type(P.Note), "function")
    local lines = P.OnCommand("")
    assertEqual(type(lines), "table", "OnCommand must return printable lines")
    assertTrue(#lines > 0 and lines[1]:find("LibKa0s", 1, true) ~= nil,
        "the stub must name the missing library")
end)

test("with LibKa0s absent the bracketed paths still run", function()
    -- A missing diagnostics harness must not break the addon's own function.
    local inst = T.load(true, true, nil, { libFiles = {} })
    local Cooldowns = inst.NS:GetModule("Cooldowns", true)
    local ok = pcall(function()
        if Cooldowns and Cooldowns.Refresh then Cooldowns:Refresh() end
    end)
    assertTrue(ok, "a bracketed path must not raise when the probe is a stub")
end)
