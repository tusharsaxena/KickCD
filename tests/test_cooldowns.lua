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

test("Refresh marks a line the global cooldown explains (#15)", function()
    -- From a live 45-second fight: seventeen [Cooldowns] lines, and only two were cooldowns.
    -- Every global cooldown flips `ready` and `isActive` for every watched spell, because
    -- buildSpellState derives both from the legacy active flag and that flag covers "real CD or
    -- just GCD" (modules/Cooldowns.lua:50). MaterialChange keys on exactly those two fields, so
    -- the churn is material by its own test and gets a line.
    --
    -- Suppression is not available: the C-side curve evaluation that separates a GCD from a real
    -- cooldown cannot return its answer into a Lua `if`, and every duration involved is secret in
    -- combat. Spell 61304 is the GCD, and its plain-bool active flag is the one thing that CAN be
    -- branched on -- so the line says which it was and lets the reader judge.
    -- red under: a log line that reports a GCD flip identically to a real cooldown.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = true, startTime = 0, duration = 0 }
    Cooldowns.watched = { [100] = { spellID = 100, ready = true, isActive = false } }
    Cooldowns.PollSpell = function() return { spellID = 100, ready = false, isActive = true } end

    Cooldowns:Refresh()
    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("gcd", 1, true) ~= nil,
        "a flip the GCD explains must say so; got: " .. tostring(line))
end)

test("Refresh marks the ready half of a GCD too (#15)", function()
    -- The first attempt marked "was a GCD running?" when the question is "is this line explained
    -- by the GCD?", and the live trace showed the difference immediately. A GCD flips a spell
    -- active, and ~1.5s LATER flips it back to ready -- by which time the GCD has ended, so the
    -- closing half of the same churn came out unmarked. Half the noise stayed unlabeled.
    -- red under: a marker read from the live GCD flag at emit time.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true

    -- The GCD starts: the spell goes active while it runs.
    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = true }
    Cooldowns.watched = { [100] = { spellID = 100, ready = true, isActive = false } }
    Cooldowns.PollSpell = function() return { spellID = 100, ready = false, isActive = true } end
    Cooldowns:Refresh()

    -- The GCD ends: the same spell comes back ready, and no GCD is running now.
    inst.NS.DebugLog:Clear()
    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = false }
    Cooldowns.PollSpell = function() return { spellID = 100, ready = true, isActive = false } end
    Cooldowns:Refresh()

    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("gcd", 1, true) ~= nil,
        "the closing half of a GCD is the same churn; got: " .. tostring(line))
end)

test("Refresh does not mark a real cooldown that merely coincides with a GCD (#15)", function()
    -- From the live trace, and the sharper half of the same mistake:
    --
    --   00:30:35 | 1/5 changed: ready=[47528] (gcd)
    --
    -- Mind Freeze coming off its own 15s cooldown -- the single most interesting line in the log --
    -- flagged as noise because an unrelated GCD happened to be running. Mind Freeze is OFF the
    -- global cooldown, so nothing about its transition is the GCD's doing.
    -- red under: a marker read from the live GCD flag at emit time.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true

    -- It went on its own cooldown with no GCD running (an off-GCD interrupt).
    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = false }
    Cooldowns.watched = { [47528] = { spellID = 47528, ready = true, isActive = false } }
    Cooldowns.PollSpell = function() return { spellID = 47528, ready = false, isActive = true } end
    Cooldowns:Refresh()

    -- Fifteen seconds later it comes back, and someone's GCD is running at that moment.
    inst.NS.DebugLog:Clear()
    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = true }
    Cooldowns.PollSpell = function() return { spellID = 47528, ready = true, isActive = false } end
    Cooldowns:Refresh()

    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("47528", 1, true) ~= nil, "the real transition still logs")
    assertTrue(line:find("gcd", 1, true) == nil,
        "a coincident GCD does not make this the GCD's doing; got: " .. tostring(line))
end)

test("Refresh leaves a line MIXED with a real transition unmarked (#15)", function()
    -- The live trace's `5/5 changed: ready=[4 spells] active=[47528]`: four spells closing a GCD
    -- alongside Mind Freeze starting a real cooldown. Marking that line would bury the real half
    -- under a label that says "skip me".
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true

    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = true }
    Cooldowns.watched = {
        [100]   = { spellID = 100,   ready = true, isActive = false },
        [47528] = { spellID = 47528, ready = true, isActive = false },
    }
    Cooldowns.PollSpell = function(_, id) return { spellID = id, ready = false, isActive = true } end
    Cooldowns:Refresh()   -- both go active under a GCD

    inst.NS.DebugLog:Clear()
    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = false }
    -- The GCD ends. 100 comes back ready; 47528 stays down on a real cooldown.
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return { spellID = 100, ready = true, isActive = false } end
        return { spellID = 47528, ready = false, isActive = true }
    end
    Cooldowns:Refresh()

    -- 47528 did not change this pass, so only 100 is logged and the line is pure churn.
    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("gcd", 1, true) ~= nil, "got: " .. tostring(line))

    -- Now 47528 comes off its real cooldown, with a fresh GCD running.
    inst.NS.DebugLog:Clear()
    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = true }
    Cooldowns.PollSpell = function(_, id)
        if id == 100 then return { spellID = 100, ready = false, isActive = true } end
        return { spellID = 47528, ready = true, isActive = false }
    end
    Cooldowns:Refresh()

    line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("47528", 1, true) ~= nil, "the real transition is on this line")
    assertTrue(line:find("gcd", 1, true) == nil,
        "one real transition disqualifies the whole line; got: " .. tostring(line))
end)

test("Refresh does not cry GCD when the global cooldown is not running (#15)", function()
    -- The half that keeps the marker worth reading. Mind Freeze coming off its own 15s cooldown
    -- arrives with no GCD running, and marking that line too would make the annotation noise
    -- itself -- an marker on every line carries exactly as much information as none.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    inst.mocks.spellCooldowns[61304] = { isEnabled = true, isActive = false, startTime = 0, duration = 0 }
    Cooldowns.watched = { [47528] = { spellID = 47528, ready = false, isActive = true } }
    Cooldowns.PollSpell = function() return { spellID = 47528, ready = true, isActive = false } end

    Cooldowns:Refresh()
    local line = inst.NS.DebugLog:LastLine()
    assertTrue(line:find("47528", 1, true) ~= nil, "the real transition still logs")
    assertTrue(line:find("gcd", 1, true) == nil,
        "an unmarked line is the signal; got: " .. tostring(line))
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
    Cooldowns.PollSpell = function() return { spellID = 200, ready = true, isActive = false } end
    local before = inst.NS.DebugLog:BufferSize()
    Cooldowns:Refresh()
    assertEqual(inst.NS.DebugLog:BufferSize(), before, "no line on a no-change pass")
end)
