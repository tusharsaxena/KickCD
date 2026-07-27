-- tests/test_state.lua — core/State.lua: the combat flag and the two
-- visibility helpers.
--
-- Everything here is load-bearing for 12.0 secret-value safety
-- (docs/midnight-quirks.md). State.IsHostileUnitCasting is the GATE both the
-- icon grid and the cast bar use for "target_casting_interruptible", and
-- State.ApplyInterruptibleAlpha is the ONLY 12.0-correct way to gate
-- visibility on `notInterruptible` — any Lua-side compare of that value
-- errors when it is secret-tainted. So these suites assert not just the
-- decisions but that the secret is handed to the C-side method VERBATIM and
-- never inspected.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

--- A fresh instance whose unit APIs the test can reshape freely. Sources are
--- already loaded by the time the mutate hook's effects matter here, because
--- State reads _G.UnitCastingInfo at CALL time, not load time.
local function freshState()
    local inst = T.load(false)
    return inst.NS.State, inst.mocks
end

--- Stand-in for a frame that only implements SetAlphaFromBoolean, recording
--- exactly what it was handed. The real method is C-side and accepts the
--- secret form; recording the raw argument is how we prove it was passed
--- through rather than coerced.
local function alphaProbe()
    local p = { calls = {} }
    function p.SetAlphaFromBoolean(_, flag, whenTrue, whenFalse)
        p.calls[#p.calls + 1] = { flag = flag, whenTrue = whenTrue, whenFalse = whenFalse }
    end
    return p
end

-- ── The combat flag ─────────────────────────────────────────────────────────

test("State: the combat flag starts false and holds `debug` session-only", function()
    local State = freshState()
    assertFalse(State.inCombat)
    assertFalse(State.debug, "debug must default off and never be persisted (§12.5)")
end)

test("State.SetInCombat coerces any truthy value to a real boolean", function()
    -- Subscribers compare this flag against `true` in places; storing a raw
    -- truthy (a table, a string) would make those comparisons fail.
    local State = freshState()
    State.SetInCombat("yes")
    assertEqual(State.inCombat, true)
    State.SetInCombat(nil)
    assertEqual(State.inCombat, false)
    State.SetInCombat(0)
    assertEqual(State.inCombat, true, "0 is truthy in Lua")
end)

test("State: the bootstrap frame owns all three combat/login events", function()
    local _, mocks = freshState()
    local boot = mocks.__findFrame("PLAYER_REGEN_DISABLED")
    assertTrue(boot ~= nil, "no frame registered PLAYER_REGEN_DISABLED")
    assertTrue(boot:IsEventRegistered("PLAYER_REGEN_ENABLED"),
        "one frame must own both regen edges")
    assertTrue(boot:IsEventRegistered("PLAYER_LOGIN"),
        "the same frame seeds the flag at login")
end)

test("State: PLAYER_REGEN_DISABLED / _ENABLED drive the flag both ways", function()
    local State, mocks = freshState()
    local boot = mocks.__findFrame("PLAYER_REGEN_DISABLED")
    boot:_fire("PLAYER_REGEN_DISABLED")
    assertEqual(State.inCombat, true)
    boot:_fire("PLAYER_REGEN_ENABLED")
    assertEqual(State.inCombat, false)
end)

test("State: PLAYER_LOGIN seeds the flag from InCombatLockdown", function()
    -- Login is the ONE moment lockdown state is trusted; after that the regen
    -- events are the source of truth because lockdown lags them by a frame.
    local State, mocks = freshState()
    mocks.InCombatLockdown = function() return true end
    local boot = mocks.__findFrame("PLAYER_LOGIN")
    boot:_fire("PLAYER_LOGIN")
    assertEqual(State.inCombat, true)
end)

test("State: PLAYER_LOGIN releases its own registration after seeding", function()
    -- It fires once per session; leaving it registered would be a dangling
    -- subscription on a frame that lives for the whole session.
    local _, mocks = freshState()
    local boot = mocks.__findFrame("PLAYER_LOGIN")
    boot:_fire("PLAYER_LOGIN")
    assertFalse(boot:IsEventRegistered("PLAYER_LOGIN"))
    assertTrue(boot:IsEventRegistered("PLAYER_REGEN_DISABLED"),
        "the regen subscriptions must survive")
end)

test("State: every combat transition fans out COMBAT_STATE with the new flag", function()
    -- Subscribers rely on the message rather than TOC load order; a
    -- transition that writes the flag but skips the fan-out would leave the
    -- grid and cast bar stale until the next unrelated refresh.
    local inst = T.load(true)
    local seen = {}
    local target = {}
    inst.mocks.__embedAceEvent(target)
    target:RegisterMessage("Ka0s_KickCD_COMBAT_STATE", function(_, payload)
        seen[#seen + 1] = payload.inCombat
    end)
    local boot = inst.mocks.__findFrame("PLAYER_REGEN_DISABLED")
    boot:_fire("PLAYER_REGEN_DISABLED")
    boot:_fire("PLAYER_REGEN_ENABLED")
    assertEqual(#seen, 2)
    assertEqual(seen[1], true)
    assertEqual(seen[2], false)
end)

-- ── IsHostileUnitCasting ────────────────────────────────────────────────────

test("IsHostileUnitCasting is false for a nil unit or one that doesn't exist", function()
    local State, mocks = freshState()
    assertFalse(State.IsHostileUnitCasting(nil))
    mocks.UnitExists = function() return false end
    assertFalse(State.IsHostileUnitCasting("target"))
end)

test("IsHostileUnitCasting is false for a friendly caster", function()
    -- You can't interrupt a friendly cast regardless of what the API's
    -- notInterruptible flag says, so the gate excludes them up front.
    local State, mocks = freshState()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return false end
    mocks.UnitCastingInfo = function() return "Greater Heal" end
    assertFalse(State.IsHostileUnitCasting("target"))
end)

test("IsHostileUnitCasting is true for a hostile CAST", function()
    local State, mocks = freshState()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return "Chaos Bolt" end
    assertTrue(State.IsHostileUnitCasting("target"))
end)

test("IsHostileUnitCasting is true for a hostile CHANNEL", function()
    -- Channels are interruptible too and come from a different API; missing
    -- them would blank the grid for the whole of e.g. a Mind Flay.
    local State, mocks = freshState()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return "Mind Flay" end
    assertTrue(State.IsHostileUnitCasting("target"))
end)

test("IsHostileUnitCasting is false for a hostile unit doing nothing", function()
    local State, mocks = freshState()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return nil end
    assertFalse(State.IsHostileUnitCasting("target"))
end)

test("IsHostileUnitCasting only truth-tests the cast name, never reads it", function()
    -- `name` is secret-tainted in combat for protected casts. `if x then` is
    -- safe on a secret; arithmetic, concatenation and tostring are not. Hand
    -- back a value that explodes on ANY of those and the gate must still work.
    local State, mocks = freshState()
    local landmine = setmetatable({}, {
        __tostring = function() error("tostring() on a secret value", 0) end,
        __concat   = function() error("concat on a secret value", 0) end,
        __len      = function() error("# on a secret value", 0) end,
        __eq       = function() error("compare on a secret value", 0) end,
    })
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return landmine end
    assertTrue(State.IsHostileUnitCasting("target"))
end)

test("IsHostileUnitCasting collapses the API multi-return to position 1", function()
    -- UnitCastingInfo returns ~10 values; a truthy check has to be on the
    -- name alone, not on "did the call return anything at all".
    local State, mocks = freshState()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    -- name is nil but later positions are populated — the "not casting, but
    -- the API still returned a tuple" shape.
    mocks.UnitCastingInfo = function() return nil, "texture", 0, 0, false, 0, 0, true end
    mocks.UnitChannelInfo = function() return nil, "texture", 0, 0, false, 0, true end
    assertFalse(State.IsHostileUnitCasting("target"))
end)

-- ── ApplyInterruptibleAlpha ─────────────────────────────────────────────────

test("ApplyInterruptibleAlpha refuses a frame that can't take the secret", function()
    -- SetAlphaFromBoolean is the only method that accepts a secret argument.
    -- Without it there is no safe path, so the helper must decline rather
    -- than fall back to a Lua-side read.
    local State = freshState()
    assertFalse(State.ApplyInterruptibleAlpha({}, "target", 1))
    assertFalse(State.ApplyInterruptibleAlpha(nil, "target", 1))
end)

test("ApplyInterruptibleAlpha declines when the unit is absent or friendly", function()
    -- Returning false WITHOUT touching the frame is the contract: the caller
    -- then applies its own alpha policy.
    local State, mocks = freshState()
    local probe = alphaProbe()
    mocks.UnitExists = function() return false end
    assertFalse(State.ApplyInterruptibleAlpha(probe, "target", 1))

    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return false end
    assertFalse(State.ApplyInterruptibleAlpha(probe, "target", 1))
    assertEqual(#probe.calls, 0, "the frame must be left untouched")
end)

test("ApplyInterruptibleAlpha declines when the unit has no cast at all", function()
    local State, mocks = freshState()
    local probe = alphaProbe()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return nil end
    assertFalse(State.ApplyInterruptibleAlpha(probe, "target", 1))
    assertEqual(#probe.calls, 0)
end)

test("ApplyInterruptibleAlpha maps interruptible -> alpha, uninterruptible -> 0", function()
    -- The argument order is (flag, whenTrue, whenFalse) and the flag is
    -- notInterruptible, so the TRUE branch must be the hidden one. Getting
    -- this inverted shows icons only for casts you cannot kick.
    local State, mocks = freshState()
    local probe = alphaProbe()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return "Chaos Bolt", nil, nil, nil, nil, nil, nil, false end
    assertTrue(State.ApplyInterruptibleAlpha(probe, "target", 0.8))
    local call = probe.calls[1]
    assertEqual(call.whenTrue, 0, "notInterruptible == true must hide the frame")
    assertEqual(call.whenFalse, 0.8, "notInterruptible == false shows it at the caller's alpha")
end)

test("ApplyInterruptibleAlpha defaults the visible alpha to 1", function()
    local State, mocks = freshState()
    local probe = alphaProbe()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return "Chaos Bolt", nil, nil, nil, nil, nil, nil, false end
    State.ApplyInterruptibleAlpha(probe, "target")
    assertEqual(probe.calls[1].whenFalse, 1)
end)

test("ApplyInterruptibleAlpha passes a SECRET notInterruptible through verbatim", function()
    -- The whole point of the helper. The flag must arrive at the C-side
    -- method as the exact value the API returned — not coerced to a boolean,
    -- not compared, not defaulted.
    local State, mocks = freshState()
    local probe = alphaProbe()
    local secret = setmetatable({}, {
        __tostring = function() error("tostring() on a secret value", 0) end,
        __eq       = function() error("compare on a secret value", 0) end,
    })
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return "Chaos Bolt", nil, nil, nil, nil, nil, nil, secret end
    assertTrue(State.ApplyInterruptibleAlpha(probe, "target", 1))
    assertTrue(rawequal(probe.calls[1].flag, secret),
        "notInterruptible must reach SetAlphaFromBoolean unmodified")
end)

test("ApplyInterruptibleAlpha reads the CHANNEL flag from position 7, not 8", function()
    -- UnitCastingInfo puts notInterruptible at position 8; UnitChannelInfo at
    -- position 7. Reusing the cast offset for a channel reads the wrong slot
    -- and silently gates on garbage.
    local State, mocks = freshState()
    local probe = alphaProbe()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function()
        return "Mind Flay", nil, nil, nil, nil, nil, "CHANNEL_FLAG", "WRONG_SLOT"
    end
    assertTrue(State.ApplyInterruptibleAlpha(probe, "target", 1))
    assertEqual(probe.calls[1].flag, "CHANNEL_FLAG")
end)

test("ApplyInterruptibleAlpha prefers the cast over a simultaneous channel", function()
    -- A unit can briefly report both; the cast is the live one.
    local State, mocks = freshState()
    local probe = alphaProbe()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return "Cast", nil, nil, nil, nil, nil, nil, "CAST_FLAG" end
    mocks.UnitChannelInfo = function() return "Chan", nil, nil, nil, nil, nil, "CHAN_FLAG" end
    State.ApplyInterruptibleAlpha(probe, "target", 1)
    assertEqual(#probe.calls, 1, "exactly one mask application per call")
    assertEqual(probe.calls[1].flag, "CAST_FLAG")
end)

test("ApplyInterruptibleAlpha never inspects the cast name it gates on", function()
    -- `name` is used only as a has-a-cast sentinel; a secret name must not
    -- break the mask.
    local State, mocks = freshState()
    local probe = alphaProbe()
    local secretName = setmetatable({}, {
        __tostring = function() error("tostring() on a secret value", 0) end,
        __len      = function() error("# on a secret value", 0) end,
    })
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return secretName, nil, nil, nil, nil, nil, nil, false
    end
    assertTrue(State.ApplyInterruptibleAlpha(probe, "target", 1))
    assertNil(probe.calls[2])
end)
