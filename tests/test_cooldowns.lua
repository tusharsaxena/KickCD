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

test("Rebuild summary logs on a material change and is silent on a repeat", function()
    -- Guards against the Set->reactor spam regression: a general-section slider
    -- drag fires Rebuild ~20/sec with an unchanged watched set; only a genuine
    -- change to the watched set may log a [Cooldowns] rebuild line.
    local inst = T.load(true, true)
    local Cooldowns = inst.NS:GetModule("Cooldowns")
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()

    Cooldowns.watched = { [100] = {}, [200] = {} }
    local base = inst.NS.DebugLog:BufferSize()
    Cooldowns:_logRebuild("MAGE", "FIRE", 2, 0)
    assertEqual(inst.NS.DebugLog:BufferSize() - base, 1, "first rebuild logs")

    Cooldowns:_logRebuild("MAGE", "FIRE", 2, 0)
    assertEqual(inst.NS.DebugLog:BufferSize() - base, 1,
        "an identical rebuild (cosmetic reactor pass) must be silent")

    Cooldowns.watched = { [100] = {} }
    Cooldowns:_logRebuild("MAGE", "FIRE", 1, 0)
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
