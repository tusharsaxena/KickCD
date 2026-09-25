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
    assertFalse(State.debug, "debug must default off and never be persisted (debug-logging-§5)")
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

-- The combat listener is an AceEvent target armed from NS:OnInitialize
-- (State.Arm), so a load that never ran OnInitialize has registered nothing.
-- These cases load WITH init and fire through the kit's AceEvent seam,
-- mocks.__fireEvent, the way AceEvent's own frame delivers an event.

--- The registration rows for `event`, from the whole live set (AceEvent
--- targets and this mock's own frames alike).
local function rowsFor(mocks, event)
    local out = {}
    for _, reg in ipairs(mocks.__registrationSet()) do
        if reg.event == event then out[#out + 1] = reg end
    end
    return out
end

test("State: the combat listener owns all three combat/login events", function()
    local inst = T.load(true)
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN" }) do
        assertEqual(#rowsFor(inst.mocks, event), 1, event .. " must have exactly one registration")
    end
    assertTrue(rowsFor(inst.mocks, "PLAYER_REGEN_DISABLED")[1].target
        == rowsFor(inst.mocks, "PLAYER_REGEN_ENABLED")[1].target,
        "one target must own both regen edges")
end)

test("State: the combat listener is an AceEvent registration, not a frame", function()
    -- events-frames-taint-§1: no private frame for ordinary event traffic. The
    -- listener used to be a CreateFrame'd bootstrap frame; it is an AceEvent
    -- target now, so the kit's AceEvent survey sees it and no created frame does.
    local inst = T.load(true, true)
    local found = false
    for _, reg in ipairs(inst.mocks.__registrations()) do
        if reg.event == "PLAYER_REGEN_DISABLED" and reg.kind == "event" then found = true end
    end
    assertTrue(found, "PLAYER_REGEN_DISABLED must be an AceEvent ('event') registration")
    assertEqual(inst.mocks.__countFramesFor("PLAYER_REGEN_DISABLED"), 0,
        "no created frame may carry PLAYER_REGEN_DISABLED")
end)

test("State: PLAYER_REGEN_DISABLED / _ENABLED drive the flag both ways", function()
    local inst = T.load(true)
    local State = inst.NS.State
    inst.mocks.__fireEvent("PLAYER_REGEN_DISABLED")
    assertEqual(State.inCombat, true)
    inst.mocks.__fireEvent("PLAYER_REGEN_ENABLED")
    assertEqual(State.inCombat, false)
end)

test("State: PLAYER_LOGIN seeds the flag from InCombatLockdown", function()
    -- Login is the ONE moment lockdown state is trusted; after that the regen
    -- events are the source of truth because lockdown lags them by a frame.
    local inst = T.load(true)
    inst.mocks.InCombatLockdown = function() return true end
    inst.mocks.__fireEvent("PLAYER_LOGIN")
    assertEqual(inst.NS.State.inCombat, true)
end)

test("State: PLAYER_LOGIN releases its own registration after seeding", function()
    -- It fires once per session; leaving it registered would be a dangling
    -- subscription for the whole session.
    local inst = T.load(true)
    inst.mocks.__fireEvent("PLAYER_LOGIN")
    assertEqual(#rowsFor(inst.mocks, "PLAYER_LOGIN"), 0)
    assertEqual(#rowsFor(inst.mocks, "PLAYER_REGEN_DISABLED"), 1,
        "the regen subscriptions must survive")
end)

test("State: a stand-up never re-registers PLAYER_LOGIN", function()
    -- KICKCD-R-17. A disabled-at-login addon is stood down inside OnEnable,
    -- which AceAddon runs from its own PLAYER_LOGIN handler -- so there is no
    -- "enabled again before login" case, and a stand-up that restored
    -- PLAYER_LOGIN left a registration for an event that never fires again.
    -- The stand-up's InCombatLockdown() seed is what the login seed was for.
    local inst = T.load(true, true, function(m)
        m.KickCDDB = { global = { schemaVersion = 5 },
            profiles = { Default = { enabled = false } } }
    end)
    assertTrue(inst.NS.IsDown(), "sanity: the stored switch stood the addon down at load")
    local real = inst.NS.Util.print
    inst.NS.Util.print = function() end
    local ok, err = pcall(inst.NS.OnSlashCommand, inst.NS, "enable")
    inst.NS.Util.print = real
    if not ok then error(err, 0) end
    inst.mocks.__flushTimers()
    assertFalse(inst.NS.IsDown(), "sanity: /kcd enable stood the addon back up")
    assertEqual(#rowsFor(inst.mocks, "PLAYER_LOGIN"), 0,
        "a stand-up must not restore the one-shot PLAYER_LOGIN")
    assertEqual(#rowsFor(inst.mocks, "PLAYER_REGEN_DISABLED"), 1,
        "but it must restore the regen pair")
end)

test("State: every combat transition fans out COMBAT_STATE with the new flag", function()
    -- Subscribers rely on the message rather than TOC load order; a
    -- transition that writes the flag but skips the fan-out would leave the
    -- grid and cast bar stale until the next unrelated refresh.
    local inst = T.load(true)
    local seen = {}
    local target = {}
    inst.mocks.LibStub("AceEvent-3.0"):Embed(target)
    target:RegisterMessage(T.NS.MSG.COMBAT_STATE, function(_, payload)
        seen[#seen + 1] = payload.inCombat
    end)
    inst.mocks.__fireEvent("PLAYER_REGEN_DISABLED")
    inst.mocks.__fireEvent("PLAYER_REGEN_ENABLED")
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
