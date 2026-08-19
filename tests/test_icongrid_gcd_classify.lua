-- tests/test_icongrid_gcd_classify.lua — GCD vs real cooldown is a question
-- about the cooldown's TOTAL length, never about how much of it is left.
--
-- Reported from the field: the icon reads "ready" a second or two before the
-- interrupt actually comes off cooldown. The cause was structural — every
-- step curve (alpha, tint, GCD-swipe suppression) was evaluated against
-- :EvaluateRemainingDuration, so the last GCD_UPPER seconds of a real 15s
-- cooldown were indistinguishable from a 1.5s GCD lockout and rendered as
-- fully ready, swipe and countdown hidden. On an interrupt that is exactly
-- the window the player is watching.
--
-- :EvaluateTotalDuration answers the question the curves were always asking:
-- a GCD-only lockout totals ~1.5s, a real cooldown totals 15s+, and neither
-- classification drifts as the cooldown winds down.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local READY_ALPHA    = 0.95
local COOLDOWN_ALPHA = 0.25

-- A real interrupt cooldown with less than one GCD left to run: the exact
-- state the field report is about.
local REAL_CD_TOTAL, REAL_CD_LEFT = 15, 0.8
-- A GCD-only lockout: the player pressed something else, this spell is
-- momentarily uncastable but is NOT on its own cooldown.
local GCD_TOTAL, GCD_LEFT = 1.5, 1.4

local function loaded()
    local inst = T.load(true, true)
    local NS = inst.NS
    local icons = NS.db.profile.units.target.icons
    icons.readyAlpha    = READY_ALPHA
    icons.cooldownAlpha = COOLDOWN_ALPHA
    NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "icons" })
    return inst, NS
end

--- An icon carrying the real mixin, with the swipe/text alpha calls recorded.
local function makeIcon(inst)
    local IconGrid = inst.NS:GetModule("IconGrid")
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
    inst.mocks.Mixin(icon, IconGrid.Icon)
    icon.UpdateGlow = function() end

    local seen = {}
    icon.SetAlphaFromBoolean = function(self, _, a) self._alpha = a end
    icon.cooldown.SetAlphaFromBoolean     = function(_, _, a) seen.swipe = a end
    icon.cooldownText.SetAlphaFromBoolean = function(_, _, a) seen.text  = a end
    return icon, seen
end

--- Render one cooldown of a given (total, remaining) shape.
local function render(inst, total, remaining)
    local icon, seen = makeIcon(inst)
    icon:Apply({
        spellID = 192058, ready = false, isActive = true,
        cdObject = inst.mocks.__makeDurationObject(remaining, total),
    })
    return icon._alpha or icon:GetAlpha(), seen
end

test("a real cooldown in its final second still renders as ON cooldown", function()
    local inst = loaded()
    local alpha = render(inst, REAL_CD_TOTAL, REAL_CD_LEFT)
    assertEqual(alpha, COOLDOWN_ALPHA,
        "with 0.8s left of a 15s cooldown the icon must stay dimmed, not read ready")
end)

test("a GCD-only lockout still renders as READY", function()
    local inst = loaded()
    local alpha = render(inst, GCD_TOTAL, GCD_LEFT)
    assertEqual(alpha, READY_ALPHA,
        "a 1.5s GCD lockout must keep the icon at ready alpha")
end)

test("the swipe stays visible through a real cooldown's final second", function()
    local inst, NS = loaded()
    NS.db.profile.units.target.icons.suppressGCDSwipe = true
    NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "icons" })
    local _, seen = render(inst, REAL_CD_TOTAL, REAL_CD_LEFT)
    assertEqual(seen.swipe, 1, "the swipe must not be suppressed on a real cooldown")
    assertEqual(seen.text,  1, "the countdown must not be suppressed on a real cooldown")
end)

test("the swipe is still suppressed for a GCD-only lockout", function()
    local inst, NS = loaded()
    NS.db.profile.units.target.icons.suppressGCDSwipe = true
    NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "icons" })
    local _, seen = render(inst, GCD_TOTAL, GCD_LEFT)
    assertEqual(seen.swipe, 0, "a GCD lockout must not draw a swipe")
    assertEqual(seen.text,  0, "a GCD lockout must not draw a countdown")
end)

test("classification falls back to remaining on a client without the total API", function()
    -- docs/midnight-quirks.md warns the measured DurationObject surface is a
    -- 12.0.7 snapshot, not a contract. If EvaluateTotalDuration is absent the
    -- icon must still render, on the old remaining-based approximation.
    local inst = loaded()
    local icon = makeIcon(inst)
    local cd = inst.mocks.__makeDurationObject(REAL_CD_LEFT, REAL_CD_TOTAL)
    cd.EvaluateTotalDuration = nil
    icon:Apply({ spellID = 192058, ready = false, isActive = true, cdObject = cd })
    assertTrue(icon._alpha ~= nil, "the icon must still be given an alpha")
end)
