-- tests/test_cooldowns.lua — modules/Cooldowns.lua event coalescing
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("SPELL_UPDATE_* burst coalesces to one Refresh per frame", function()
    -- Fresh enabled instance so Cooldowns:OnEnable has wired the coalescer.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")

    -- Drain any timers scheduled during load, then spy on Refresh.
    inst.mocks.__flushTimers()
    local refreshes = 0
    Cooldowns.Refresh = function() refreshes = refreshes + 1 end

    -- A same-frame burst of cooldown events must not re-poll synchronously.
    Cooldowns:OnCooldownEvent()
    Cooldowns:OnCooldownEvent()
    Cooldowns:OnCooldownEvent()
    assertEqual(refreshes, 0, "coalesced Refresh must not fire synchronously")

    -- Next frame: the burst collapses to exactly one Refresh.
    inst.mocks.__flushTimers()
    assertEqual(refreshes, 1, "burst must coalesce to a single Refresh")
end)

test("Refresh logs one coalesced line only when a spell changed", function()
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    -- Two watched spells; make PollSpell report id 100 changed, id 200 same.
    Cooldowns.watched = {
        [100] = { spellID = 100, ready = false, isActive = true },
        [200] = { spellID = 200, ready = true,  isActive = false },
    }
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return { spellID = 100, ready = true, isActive = false } end
        return { spellID = 200, ready = true, isActive = false }  -- unchanged
    end

    local before = inst.NS.DebugLog:BufferSize()
    Cooldowns:Refresh()
    local after = inst.NS.DebugLog:BufferSize()
    assertEqual(after - before, 1, "exactly one coalesced line when something changed")
    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("[Cooldowns]", 1, true) and line:find("100", 1, true),
        "line names the changed id; got: " .. tostring(line))
end)

test("Refresh coalesces multiple simultaneous changes into ONE line", function()
    -- The discriminating case: two spells change in the same pass. Coalesced
    -- logging emits exactly one summary line naming both ids; the old per-spell
    -- logging would have emitted two lines (BufferSize +2), so this fails
    -- against the pre-refactor behavior.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    Cooldowns.watched = {
        [100] = { spellID = 100, ready = false, isActive = true },   -- -> becomes ready
        [300] = { spellID = 300, ready = true,  isActive = false },  -- -> becomes active
    }
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return { spellID = 100, ready = true,  isActive = false } end
        return { spellID = 300, ready = false, isActive = true }
    end

    local before = inst.NS.DebugLog:BufferSize()
    Cooldowns:Refresh()
    assertEqual(inst.NS.DebugLog:BufferSize() - before, 1,
        "two simultaneous changes must collapse to exactly one line")
    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("100", 1, true) and line:find("300", 1, true),
        "the single line must name both changed ids; got: " .. tostring(line))
end)

-- ---------------------------------------------------------------------------
-- Refresh: cooldown-handle churn must not reach the debug log
-- ---------------------------------------------------------------------------
--
-- C_Spell.GetSpellCooldownDuration returns a FRESH object every call, so a
-- spell sitting on an unchanged cooldown compares unequal on every poll.
-- The re-emit is load-bearing (Icon:Apply re-evaluates the alpha/tint/GCD
-- curves from it), but logging it floods the console ~10x/sec per spell.

--- Drive one Refresh where every poll returns the same logical state but a
--- brand-new cdObject, mimicking the live API. Returns (linesLogged, emits).
local function refreshWithChurnedHandle(inst, prevReady, prevActive)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    Cooldowns.watched = {
        [192058] = { spellID = 192058, ready = prevReady, isActive = prevActive,
                     cdObject = {}, chargeCdObject = nil, charges = nil },
    }
    -- Same booleans every poll; a NEW table for cdObject each time.
    Cooldowns.PollSpell = function(_, id)
        return { spellID = id, ready = false, isActive = true,
                 cdObject = {}, chargeCdObject = nil, charges = nil }
    end

    local spy = {}
    inst.mocks.__libs["AceEvent-3.0"]:Embed(spy)
    local emits = 0
    spy:RegisterMessage("Ka0s_KickCD_SPELL_STATE", function() emits = emits + 1 end)

    local before = inst.NS.DebugLog:BufferSize()
    Cooldowns:Refresh()
    local logged = inst.NS.DebugLog:BufferSize() - before
    inst.NS.State.debug = false
    return logged, emits
end

test("Refresh does not log when only the cooldown handle identity changed", function()
    -- prev already on cooldown; poll returns the same state with a new handle.
    local inst = T.load(true, true)
    local logged = refreshWithChurnedHandle(inst, false, true)
    assertEqual(logged, 0,
        "an unchanged cooldown must not produce a debug line just because the handle is new")
end)

test("Refresh STILL emits SPELL_STATE when the cooldown handle changed", function()
    -- Guard on the fix not going too far: Icon:Apply re-evaluates the
    -- alpha/tint/GCD-suppression curves from the emitted object, so
    -- suppressing the emit (rather than just the log) would freeze those
    -- visuals mid-cooldown.
    local inst = T.load(true, true)
    local _, emits = refreshWithChurnedHandle(inst, false, true)
    assertEqual(emits, 1, "the renderer must still receive the fresh handle")
end)

test("Refresh logs a genuine on-cooldown -> ready transition", function()
    -- The complement: real transitions must still be visible in the log.
    local inst = T.load(true, true)
    local logged = refreshWithChurnedHandle(inst, true, false)
    assertEqual(logged, 1, "a real isActive/ready transition must still log")
end)

test("Rebuild summary names the class/spec IDs and every watched + skipped spell", function()
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    Cooldowns:_logRebuild("SHAMAN", 7, 262, { 57994, 192058 }, { 51490 })
    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line ~= nil and line:find("rebuild", 1, true) ~= nil,
        "a rebuild line must be logged, got: " .. tostring(line))
    assertTrue(line:find("SHAMAN(7)", 1, true) ~= nil,
        "class must carry its numeric ID, got: " .. tostring(line))
    assertTrue(line:find("ELEMENTAL(262)", 1, true) ~= nil,
        "spec must carry its numeric ID, got: " .. tostring(line))
    assertTrue(line:find("2 watched (57994,192058)", 1, true) ~= nil,
        "watched spell IDs must be listed, got: " .. tostring(line))
    assertTrue(line:find("1 skipped (51490)", 1, true) ~= nil,
        "skipped spell IDs must be listed, got: " .. tostring(line))
    inst.NS.State.debug = false
end)

test("Rebuild summary distinguishes an empty watched set from an empty skipped set", function()
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    Cooldowns:_logRebuild("SHAMAN", 7, 262, {}, {})
    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("0 watched ()", 1, true) ~= nil,
        "an empty list must still render its parens, got: " .. tostring(line))
    assertTrue(line:find("0 skipped ()", 1, true) ~= nil,
        "an empty skipped list must still render its parens, got: " .. tostring(line))
    inst.NS.State.debug = false
end)

test("Rebuild summary re-logs when only the SKIPPED set changes", function()
    -- The skipped list is now user-visible data, so a change to it is a
    -- material change even when the watched set is identical.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    local base = inst.NS.DebugLog:BufferSize()
    Cooldowns:_logRebuild("SHAMAN", 7, 262, { 57994 }, { 51490 })
    assertEqual(inst.NS.DebugLog:BufferSize() - base, 1, "first rebuild logs")
    Cooldowns:_logRebuild("SHAMAN", 7, 262, { 57994 }, { 51490 })
    assertEqual(inst.NS.DebugLog:BufferSize() - base, 1, "an identical rebuild stays silent")
    Cooldowns:_logRebuild("SHAMAN", 7, 262, { 57994 }, { 51514 })
    assertEqual(inst.NS.DebugLog:BufferSize() - base, 2,
        "a different skipped spell must log even though the watched set is unchanged")
    inst.NS.State.debug = false
end)

test("Rebuild summary logs on a material change and is silent on a repeat", function()
    -- Guards against the Set->reactor spam regression: a general-section slider
    -- drag fires Rebuild ~20/sec with an unchanged watched set; only a genuine
    -- change to the watched set may log a [Cooldowns] rebuild line.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    local base = inst.NS.DebugLog:BufferSize()
    Cooldowns:_logRebuild("MAGE", 8, 63, { 100, 200 }, {})
    assertEqual(inst.NS.DebugLog:BufferSize() - base, 1, "first rebuild logs")

    Cooldowns:_logRebuild("MAGE", 8, 63, { 100, 200 }, {})
    assertEqual(inst.NS.DebugLog:BufferSize() - base, 1,
        "an identical rebuild (cosmetic reactor pass) must be silent")

    Cooldowns:_logRebuild("MAGE", 8, 63, { 100 }, {})
    assertEqual(inst.NS.DebugLog:BufferSize() - base, 2,
        "a material change to the watched set logs again")
    inst.NS.State.debug = false
end)

test("Refresh logs nothing when no spell changed", function()
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()
    Cooldowns.watched = { [200] = { spellID = 200, ready = true, isActive = false } }
    Cooldowns.PollSpell = function(_, id) return { spellID = 200, ready = true, isActive = false } end
    local before = inst.NS.DebugLog:BufferSize()
    Cooldowns:Refresh()
    assertEqual(inst.NS.DebugLog:BufferSize(), before, "no line on a no-change pass")
end)
