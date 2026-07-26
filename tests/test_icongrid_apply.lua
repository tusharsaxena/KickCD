-- tests/test_icongrid_apply.lua — Icon:Apply state-work vs time-work split
--
-- C_Spell.GetSpellCooldownDuration mints a fresh handle per call, and in
-- combat every getter on it is secret (see docs/midnight-quirks.md), so
-- Cooldowns:StateChanged has no choice but to re-emit ~10x/sec for a spell
-- parked on an unchanged cooldown. Icon:Apply therefore runs on every one of
-- those.
--
-- Some of that work is genuinely time-varying (the alpha/tint/GCD curves step
-- at GCD_UPPER, the swipe handle, the countdown text) and MUST keep running.
-- The rest depends only on plain state fields that did not move — glow,
-- charges badge, Show calls — and is pure waste. These cases pin the split.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

--- Build a standalone icon: a mock frame with the sub-widgets Apply touches,
--- carrying the real Icon mixin. Returns (icon, counters).
local function makeIcon(inst)
    local NS = inst.NS
    local IconGrid = NS:GetModule("IconGrid")
    local Icon = IconGrid.Icon
    assertTrue(Icon ~= nil, "IconGrid.Icon mixin must be published for testing")

    local mk = inst.mocks.CreateFrame
    local icon = mk("Button")
    icon.icon         = mk("Frame")
    icon.cooldown     = mk("Frame")
    icon.cooldownText = mk("Frame")
    icon.chargesText  = mk("Frame")
    icon.glow         = mk("Frame")
    icon.unit         = "target"
    icon.spellID      = 192058
    icon._isPrimary   = true
    inst.mocks.Mixin(icon, Icon)

    local counts = { glow = 0, swipe = 0, badge = 0 }
    icon.UpdateGlow = function() counts.glow = counts.glow + 1 end
    icon.cooldown.SetCooldownFromDurationObject = function()
        counts.swipe = counts.swipe + 1
    end
    icon.chargesText.SetFormattedText = function() counts.badge = counts.badge + 1 end
    icon.chargesText.Hide = function() counts.badge = counts.badge + 1 end
    return icon, counts
end

--- A distinct-but-equivalent state table, mimicking a fresh poll of an
--- unchanged cooldown: same plain fields, brand-new cdObject handle (which is
--- exactly what the live API hands back — see docs/midnight-quirks.md).
local function onCooldownState(inst)
    return { spellID = 192058, ready = false, isActive = true,
             cdObject = inst.mocks.__makeDurationObject(30),
             chargeCdObject = nil, charges = nil }
end

test("Icon:Apply skips glow work when no plain state field moved", function()
    local inst = T.load(true, true)
    local icon, counts = makeIcon(inst)
    icon:Apply(onCooldownState(inst))
    assertEqual(counts.glow, 1, "the first apply must do the state work")
    icon:Apply(onCooldownState(inst))
    assertEqual(counts.glow, 1,
        "a repeat apply for the same logical state must not redo glow work")
end)

test("Icon:Apply STILL re-arms the swipe when only the handle changed", function()
    -- The time-varying half must not be gated: the curves step at GCD_UPPER
    -- and the swipe needs the fresh handle, so both run on every apply.
    local inst = T.load(true, true)
    local icon, counts = makeIcon(inst)
    icon:Apply(onCooldownState(inst))
    icon:Apply(onCooldownState(inst))
    assertEqual(counts.swipe, 2,
        "the swipe must be re-armed from the fresh handle on every apply")
end)

test("Icon:Apply redoes glow work when `ready` actually flips", function()
    local inst = T.load(true, true)
    local icon, counts = makeIcon(inst)
    icon:Apply(onCooldownState(inst))
    local ready = onCooldownState(inst)
    ready.ready, ready.isActive, ready.cdObject = true, false, nil
    icon:Apply(ready)
    assertEqual(counts.glow, 2, "a real ready transition must re-run the glow")
end)

test("Icon:Apply redoes glow work when the cooldown ends", function()
    local inst = T.load(true, true)
    local icon, counts = makeIcon(inst)
    icon:Apply(onCooldownState(inst))
    local off = onCooldownState(inst)
    off.cdObject = nil
    icon:Apply(off)
    assertEqual(counts.glow, 2,
        "losing the cooldown handle changes the render branch — glow must re-run")
end)

test("Icon:Apply forced re-apply redoes state work even when nothing moved", function()
    -- ApplyTextConfig re-applies the SAME state table after a config change;
    -- the gate must not swallow that or a glow/type/colour change would need
    -- a state transition before it showed up.
    local inst = T.load(true, true)
    local icon, counts = makeIcon(inst)
    local state = onCooldownState(inst)
    icon:Apply(state)
    icon:Apply(state, true)
    assertEqual(counts.glow, 2, "a forced apply must always redo the state work")
end)

test("Icon:Apply keeps the charges badge live when charges are secret", function()
    -- Secret charges cannot be compared, so the badge must be refreshed
    -- regardless — SetFormattedText renders a secret C-side, and freezing it
    -- would strand a stale count on screen for the whole fight.
    local inst = T.load(true, true)
    local SECRET = setmetatable({}, {})
    inst.mocks.issecretvalue = function(v) return v == SECRET end
    local icon, counts = makeIcon(inst)
    icon.cfg = { showCharges = true, readyAlpha = 1 }

    local a = onCooldownState(inst); a.charges = SECRET
    local b = onCooldownState(inst); b.charges = SECRET
    icon:Apply(a)
    local afterFirst = counts.badge
    icon:Apply(b)
    assertTrue(counts.badge > afterFirst,
        "a secret charge count must be re-rendered, not gated out")
end)
