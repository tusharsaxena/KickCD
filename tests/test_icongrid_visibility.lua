-- tests/test_icongrid_visibility.lua — the icon grid's show/hide decision.
--
-- shouldBeVisible is the most branch-heavy piece of logic in the addon and
-- the one users notice first when it is wrong: every combination of master
-- enable, lock state and the four visibility modes routes through it. The
-- modes were previously only reachable in-game, so this suite walks the full
-- matrix headlessly.
--
-- Two rules here are easy to "tidy" into bugs and are pinned deliberately:
--   * unlocked ALWAYS shows, whatever the mode says — otherwise the grid
--     vanishes exactly when the user is trying to drag it;
--   * the combat mode reads NS.State.inCombat, never InCombatLockdown(),
--     because lockdown state lags the regen events by a frame.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

local inst     = T.load(true)
local NS       = inst.NS
local mocks    = inst.mocks
local IconGrid = NS:GetModule("IconGrid")

local TARGET = { unit = "target" }
local FOCUS  = { unit = "focus" }

-- `field = nil` is invisible to pairs(), so CLEARING a profile key needs an
-- explicit sentinel. The missing-key cases below are the whole point of
-- several tests (a profile migrated up from an older schema), so a silently
-- skipped override would make them assert the default instead.
local NIL = {}

--- Run `fn` with the profile keys overridden, then restore them. Restoring
--- matters because this module shares one instance with the rest of the suite.
local function withProfile(over, fn)
    local p = NS.db.profile
    local saved, keys = {}, {}
    for k, v in pairs(over) do
        keys[#keys + 1] = k
        saved[k] = p[k]
        -- Written out rather than `(v ~= NIL) and v or nil`: that idiom
        -- collapses a legitimate `false` to nil, and `enabled = false` /
        -- `locked = false` are exactly the overrides this suite needs.
        if v == NIL then p[k] = nil else p[k] = v end
    end
    local ok, err = pcall(fn)
    for _, k in ipairs(keys) do p[k] = saved[k] end
    if not ok then error(err, 0) end
end

--- Simulate a unit that exists, is attackable, and is/isn't casting.
local function setCasting(casting, channeling)
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return casting and "Chaos Bolt" or nil end
    mocks.UnitChannelInfo = function() return channeling and "Mind Flay" or nil end
end

local function clearCasting()
    mocks.UnitExists = function() return false end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return nil end
end

test("the visibility deciders are published for testing", function()
    assertTrue(type(IconGrid.ShouldBeVisible) == "function")
    assertTrue(type(IconGrid.VisibilityMode) == "function")
    assertTrue(type(IconGrid.InstanceCasting) == "function")
    assertTrue(type(IconGrid.MasterEnabled) == "function")
end)

-- ── visibilityMode ──────────────────────────────────────────────────────────

test("visibilityMode reads the addon-wide setting", function()
    withProfile({ visibility = "in_combat" }, function()
        assertEqual(IconGrid.VisibilityMode(), "in_combat")
    end)
end)

test("visibilityMode defaults to 'always' when the field is missing", function()
    -- A profile migrated up from an older schema can be missing the key; the
    -- safe default is the one that shows the addon rather than hiding it.
    withProfile({ visibility = NIL }, function()
        assertEqual(IconGrid.VisibilityMode(), "always")
    end)
end)

test("the cast bar reads the SAME visibility setting as the grid", function()
    -- The two are documented to show and hide together; a second copy of the
    -- key would let them drift apart.
    withProfile({ visibility = "target_casting" }, function()
        assertEqual(IconGrid.VisibilityMode(), NS.db.profile.visibility)
    end)
end)

-- ── The master enable gate ──────────────────────────────────────────────────

test("master enable off hides the grid in every mode", function()
    -- Enable is checked FIRST, ahead of even the unlocked override, so
    -- turning the addon off can't be defeated by any other setting.
    for _, mode in ipairs({ "always", "in_combat", "target_casting",
                            "target_casting_interruptible" }) do
        withProfile({ enabled = false, visibility = mode, locked = false }, function()
            assertFalse(IconGrid.ShouldBeVisible(TARGET), "mode " .. mode)
        end)
    end
end)

test("a fresh profile with no enable field reads as enabled", function()
    withProfile({ enabled = NIL, visibility = "always", locked = true }, function()
        assertTrue(IconGrid.MasterEnabled())
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

-- ── The unlocked override ───────────────────────────────────────────────────

test("unlocked shows the grid even in a mode that would hide it", function()
    -- Without this the user drags an invisible frame.
    clearCasting()
    NS.State.SetInCombat(false)
    for _, mode in ipairs({ "in_combat", "target_casting",
                            "target_casting_interruptible" }) do
        withProfile({ enabled = true, visibility = mode, locked = false }, function()
            assertTrue(IconGrid.ShouldBeVisible(TARGET), "mode " .. mode)
        end)
    end
end)

test("locked restores the mode's own decision", function()
    clearCasting()
    NS.State.SetInCombat(false)
    withProfile({ enabled = true, visibility = "in_combat", locked = true }, function()
        assertFalse(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

-- ── Mode: always ────────────────────────────────────────────────────────────

test("'always' shows regardless of combat or casting", function()
    clearCasting()
    NS.State.SetInCombat(false)
    withProfile({ enabled = true, visibility = "always", locked = true }, function()
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

test("an unrecognised mode falls back to always-visible", function()
    -- A future mode arriving in a SavedVariables file from a newer build must
    -- not blank the addon on an older client.
    withProfile({ enabled = true, visibility = "no_such_mode", locked = true }, function()
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

-- ── Mode: in_combat ─────────────────────────────────────────────────────────

test("'in_combat' follows State.inCombat in both directions", function()
    withProfile({ enabled = true, visibility = "in_combat", locked = true }, function()
        NS.State.SetInCombat(true)
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
        NS.State.SetInCombat(false)
        assertFalse(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

test("'in_combat' ignores InCombatLockdown, which lags the regen events", function()
    -- Reading lockdown state inside the decision would make the grid flicker
    -- on the first frame of every pull.
    withProfile({ enabled = true, visibility = "in_combat", locked = true }, function()
        local prev = mocks.InCombatLockdown
        mocks.InCombatLockdown = function() return true end
        NS.State.SetInCombat(false)
        assertFalse(IconGrid.ShouldBeVisible(TARGET),
            "the event-driven flag is the source of truth, not lockdown")
        mocks.InCombatLockdown = prev
    end)
end)

-- ── Mode: target_casting ────────────────────────────────────────────────────

test("'target_casting' shows while the unit casts and hides when it stops", function()
    withProfile({ enabled = true, visibility = "target_casting", locked = true }, function()
        setCasting(true, false)
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
        setCasting(false, false)
        assertFalse(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

test("'target_casting' counts a CHANNEL as casting", function()
    withProfile({ enabled = true, visibility = "target_casting", locked = true }, function()
        setCasting(false, true)
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

test("'target_casting' hides when the unit doesn't exist", function()
    withProfile({ enabled = true, visibility = "target_casting", locked = true }, function()
        clearCasting()
        assertFalse(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

test("'target_casting' does NOT filter on hostility, unlike the interruptible mode", function()
    -- instanceCasting deliberately omits the UnitCanAttack check that
    -- State.IsHostileUnitCasting applies: this mode means "my target is
    -- casting", not "my target is casting something I can kick".
    withProfile({ enabled = true, visibility = "target_casting", locked = true }, function()
        setCasting(true, false)
        mocks.UnitCanAttack = function() return false end
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

-- ── Mode: target_casting_interruptible ──────────────────────────────────────

test("'target_casting_interruptible' shows for any HOSTILE cast", function()
    -- The gate is deliberately coarse — the actual interruptibility filter is
    -- an alpha mask applied later, because notInterruptible is secret and
    -- cannot be branched on in Lua.
    withProfile({ enabled = true, visibility = "target_casting_interruptible",
                  locked = true }, function()
        setCasting(true, false)
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

test("'target_casting_interruptible' hides for a FRIENDLY cast", function()
    -- This is where the mode differs from plain target_casting: you can never
    -- interrupt a friendly cast, so it shouldn't show at all.
    withProfile({ enabled = true, visibility = "target_casting_interruptible",
                  locked = true }, function()
        setCasting(true, false)
        mocks.UnitCanAttack = function() return false end
        assertFalse(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

test("'target_casting_interruptible' hides when nothing is being cast", function()
    withProfile({ enabled = true, visibility = "target_casting_interruptible",
                  locked = true }, function()
        clearCasting()
        assertFalse(IconGrid.ShouldBeVisible(TARGET))
    end)
end)

-- ── Per-unit independence ───────────────────────────────────────────────────

test("each unit's decision is made against its OWN unit token", function()
    -- Target and focus share one visibility MODE but must evaluate it
    -- separately; a hard-coded "target" would make the focus grid mirror the
    -- target's cast state.
    withProfile({ enabled = true, visibility = "target_casting", locked = true }, function()
        mocks.UnitExists = function(u) return u == "target" end
        mocks.UnitCanAttack = function() return true end
        mocks.UnitCastingInfo = function(u) return u == "target" and "Chaos Bolt" or nil end
        mocks.UnitChannelInfo = function() return nil end
        assertTrue(IconGrid.ShouldBeVisible(TARGET))
        assertFalse(IconGrid.ShouldBeVisible(FOCUS))
    end)
end)

test("instanceCasting truth-tests the cast name without ever reading it", function()
    -- The name is secret-tainted in combat for protected casts.
    local landmine = setmetatable({}, {
        __tostring = function() error("tostring() on a secret cast name", 0) end,
        __len      = function() error("# on a secret cast name", 0) end,
        __concat   = function() error("concat on a secret cast name", 0) end,
    })
    mocks.UnitExists = function() return true end
    mocks.UnitCastingInfo = function() return landmine end
    assertTrue(IconGrid.InstanceCasting(TARGET))
end)

test("instanceCasting is false for a unit that doesn't exist", function()
    clearCasting()
    assertFalse(IconGrid.InstanceCasting(TARGET))
end)
