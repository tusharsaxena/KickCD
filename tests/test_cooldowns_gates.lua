-- tests/test_cooldowns_gates.lua — the two change-detection gates in
-- modules/Cooldowns.lua.
--
-- StateChanged decides whether a poll EMITS a Ka0s_KickCD_SPELL_STATE;
-- MaterialChange decides whether that poll gets LOGGED. They look almost
-- identical and are deliberately not: on a secret `charges` StateChanged
-- emits (a redundant render is harmless, a missed charge transition strands
-- a stale badge for a fight) while MaterialChange stays quiet (logging every
-- poll for every charged spell in combat is the exact flood the debug console
-- exists to avoid). That asymmetry is the whole point of this suite — a
-- well-meaning "make these consistent" refactor breaks one of the two.
--
-- test_cooldowns.lua drives the same rules end-to-end through Refresh; here
-- they are pinned directly, so a failure says which gate is wrong.
local T = _G.KICKCD_TEST
local test, assertTrue, assertFalse = T.test, T.assertTrue, T.assertFalse

local inst      = T.load(true)
local Cooldowns = inst.NS:GetModule("Cooldowns")
local mocks     = inst.mocks

local MaterialChange, StateChanged = Cooldowns.MaterialChange, Cooldowns.StateChanged

--- A poll result. Defaults describe a ready spell with no cooldown running.
local function st(over)
    local s = { ready = true, isActive = false, cdObject = nil,
                chargeCdObject = nil, charges = nil }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

--- Mark `values` secret for the duration of `fn`. issecretvalue is a global
--- the gates consult, so this is the only way to simulate combat taint.
local function withSecrets(values, fn)
    local prev = mocks.issecretvalue
    mocks.issecretvalue = function(v)
        for _, s in ipairs(values) do if rawequal(v, s) then return true end end
        return false
    end
    local ok, err = pcall(fn)
    mocks.issecretvalue = prev
    if not ok then error(err, 0) end
end

test("both gates are published for testing", function()
    assertTrue(type(MaterialChange) == "function")
    assertTrue(type(StateChanged) == "function")
    assertTrue(type(Cooldowns.MasterEnabled) == "function")
end)

-- ── Shared behaviour ────────────────────────────────────────────────────────

test("both gates treat a missing previous state as a change (first poll)", function()
    -- The very first poll for a spell must always emit AND log, or a spell
    -- that starts life on cooldown never renders.
    assertTrue(StateChanged(nil, st()))
    assertTrue(MaterialChange(nil, st()))
end)

test("both gates are silent when nothing at all moved", function()
    local a, b = st(), st()
    assertFalse(StateChanged(a, b))
    assertFalse(MaterialChange(a, b))
end)

test("both gates fire on a ready flip — the transition that matters most", function()
    local prev, next_ = st({ ready = true }), st({ ready = false })
    assertTrue(StateChanged(prev, next_))
    assertTrue(MaterialChange(prev, next_))
end)

test("both gates fire on an isActive flip", function()
    local prev, next_ = st({ isActive = false }), st({ isActive = true })
    assertTrue(StateChanged(prev, next_))
    assertTrue(MaterialChange(prev, next_))
end)

test("both gates fire when a cooldown handle APPEARS", function()
    local prev, next_ = st(), st({ cdObject = mocks.__makeDurationObject(30) })
    assertTrue(StateChanged(prev, next_))
    assertTrue(MaterialChange(prev, next_))
end)

test("both gates fire when a cooldown handle DISAPPEARS", function()
    local prev, next_ = st({ cdObject = mocks.__makeDurationObject(30) }), st()
    assertTrue(StateChanged(prev, next_))
    assertTrue(MaterialChange(prev, next_))
end)

test("both gates fire when a charge-recharge timer appears", function()
    -- The charge timer is a separate branch of the render path, so its
    -- presence has to be watched independently of the full cooldown.
    local prev = st()
    local next_ = st({ chargeCdObject = mocks.__makeDurationObject(10) })
    assertTrue(StateChanged(prev, next_))
    assertTrue(MaterialChange(prev, next_))
end)

-- ── Where they diverge: handle IDENTITY ─────────────────────────────────────

test("StateChanged fires on a NEW handle for the same cooldown", function()
    -- C_Spell.GetSpellCooldownDuration mints a fresh object per call, so this
    -- fires ~10x/sec. It must: the render path needs the live handle, and
    -- nothing on the object is comparable from Lua in combat.
    local prev = st({ isActive = true, cdObject = mocks.__makeDurationObject(30) })
    local next_ = st({ isActive = true, cdObject = mocks.__makeDurationObject(29) })
    assertTrue(StateChanged(prev, next_))
end)

test("MaterialChange ignores a new handle for the same cooldown", function()
    -- The mirror image: "the API minted a new wrapper" is not news, and
    -- logging it would produce ten identical console lines a second.
    local prev = st({ isActive = true, cdObject = mocks.__makeDurationObject(30) })
    local next_ = st({ isActive = true, cdObject = mocks.__makeDurationObject(29) })
    assertFalse(MaterialChange(prev, next_))
end)

test("MaterialChange ignores a new CHARGE handle too", function()
    local prev = st({ chargeCdObject = mocks.__makeDurationObject(10) })
    local next_ = st({ chargeCdObject = mocks.__makeDurationObject(9) })
    assertFalse(MaterialChange(prev, next_))
    assertTrue(StateChanged(prev, next_), "the render path still needs the live handle")
end)

-- ── Plain charges ───────────────────────────────────────────────────────────

test("both gates ignore charges that stayed nil", function()
    assertFalse(StateChanged(st({ charges = nil }), st({ charges = nil })))
    assertFalse(MaterialChange(st({ charges = nil }), st({ charges = nil })))
end)

test("both gates fire on a plain charge count that moved", function()
    -- Out of combat charges are plain numbers and can simply be compared.
    local prev, next_ = st({ charges = 1 }), st({ charges = 2 })
    assertTrue(StateChanged(prev, next_))
    assertTrue(MaterialChange(prev, next_))
end)

test("both gates ignore a plain charge count that held still", function()
    assertFalse(StateChanged(st({ charges = 2 }), st({ charges = 2 })))
    assertFalse(MaterialChange(st({ charges = 2 }), st({ charges = 2 })))
end)

test("both gates fire when charges appear from nothing", function()
    -- nil → 1 is a real transition (the spell gained charges via a talent
    -- swap) and one side being nil means no secret compare is needed.
    assertTrue(StateChanged(st({ charges = nil }), st({ charges = 1 })))
    assertTrue(MaterialChange(st({ charges = nil }), st({ charges = 1 })))
end)

-- ── Secret charges: the deliberate asymmetry ────────────────────────────────

test("StateChanged EMITS conservatively when either charge count is secret", function()
    -- Two secrets cannot be compared, so the gate genuinely cannot tell.
    -- Emitting is correct here: the badge renders via SetFormattedText, which
    -- accepts a secret C-side, so a redundant emit is cheap. Staying quiet
    -- was the Blood Boil 1→2 bug — a spell whose ONLY moving field is
    -- charges never re-rendered.
    local a, b = {}, {}
    withSecrets({ a, b }, function()
        assertTrue(StateChanged(st({ charges = a }), st({ charges = b })))
    end)
end)

test("MaterialChange stays QUIET when either charge count is secret", function()
    -- The opposite call, for the opposite reason: this gate only controls
    -- logging, and a charge change that matters almost always moves `ready`
    -- or `isActive` too, which is caught before charges are ever reached.
    local a, b = {}, {}
    withSecrets({ a, b }, function()
        assertFalse(MaterialChange(st({ charges = a }), st({ charges = b })))
    end)
end)

test("one secret side is enough to trigger each gate's secret rule", function()
    -- A spell can go from a plain count out of combat to a secret one the
    -- instant combat starts, so the mixed case is the common one.
    local secret = {}
    withSecrets({ secret }, function()
        assertTrue(StateChanged(st({ charges = 1 }), st({ charges = secret })))
        assertFalse(MaterialChange(st({ charges = 1 }), st({ charges = secret })))
        assertTrue(StateChanged(st({ charges = secret }), st({ charges = 1 })))
        assertFalse(MaterialChange(st({ charges = secret }), st({ charges = 1 })))
    end)
end)

test("a secret charge count never blocks a real ready/isActive transition", function()
    -- Charges are checked LAST in both gates, so the plain fields still win.
    -- If the secret branch ever moved above them, a charged interrupt coming
    -- off cooldown in combat would stop rendering entirely.
    local secret = {}
    withSecrets({ secret }, function()
        local prev = st({ ready = false, isActive = true, charges = secret })
        local next_ = st({ ready = true, isActive = false, charges = secret })
        assertTrue(StateChanged(prev, next_))
        assertTrue(MaterialChange(prev, next_))
    end)
end)

test("neither gate ever reads a secret charge value itself", function()
    -- Proof rather than inference: a value that errors on compare, tostring
    -- or arithmetic must still pass through both gates cleanly.
    local mine = setmetatable({}, {
        __eq       = function() error("compared a secret charge count", 0) end,
        __lt       = function() error("compared a secret charge count", 0) end,
        __tostring = function() error("tostring on a secret charge count", 0) end,
        __add      = function() error("arithmetic on a secret charge count", 0) end,
    })
    withSecrets({ mine }, function()
        StateChanged(st({ charges = mine }), st({ charges = mine }))
        MaterialChange(st({ charges = mine }), st({ charges = mine }))
    end)
end)

-- ── The master enable gate ──────────────────────────────────────────────────

test("Cooldowns.MasterEnabled defaults to true when the field is absent", function()
    -- A fresh profile has no `enabled` key yet; failing closed would ship an
    -- addon that tracks nothing until the user finds the checkbox.
    local profile = inst.NS.db.profile
    local prev = profile.enabled
    profile.enabled = nil
    assertTrue(Cooldowns.MasterEnabled())
    profile.enabled = prev
end)

test("Cooldowns.MasterEnabled is false only for an explicit false", function()
    local profile = inst.NS.db.profile
    local prev = profile.enabled
    profile.enabled = false
    assertFalse(Cooldowns.MasterEnabled())
    profile.enabled = true
    assertTrue(Cooldowns.MasterEnabled())
    profile.enabled = prev
end)
