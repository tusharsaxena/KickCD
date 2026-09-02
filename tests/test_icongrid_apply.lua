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
    -- the gate must not swallow that or a glow/type/color change would need
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

-- ── the composed Annotations font block and the icon Border (options-ui-§16/§17)
--
-- THE ICON GRID IS PLAYER-SCOPED and the path does not say so: every one of
-- these settings is stored under `units.<unit>.icons.` and every one of them
-- paints the PLAYER'S OWN interrupt cooldowns. modules/Cooldowns.lua's
-- ResolveClassSpec and modules/IconGrid.lua's getActiveSpecKey both key the
-- watched list on UnitClass("player"), which is what makes that true rather
-- than a preference — so the resolver is handed a nil unit token here, on the
-- Focus grid exactly as on the Target one.

--- An icon on `unit`'s grid, in a world where the player and the tracked units
--- are different classes, so a test can tell which class the resolver used.
local function classyIcon(unit)
    local inst = T.load(true, true, function(mocks)
        mocks.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 0.9, b = 0.8 },
                                    SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
        mocks.UnitClass = function(u)
            if u == "player" then return "Priest", "PRIEST", 5 end
            return "Shaman", "SHAMAN", 7
        end
    end)
    local icon = makeIcon(inst)
    icon.unit = unit or "target"
    icon.border = inst.mocks.CreateFrame("Frame")
    return inst, icon, inst.NS.db.profile.units[icon.unit].icons
end

test("the countdown takes its configured color, which it never had before", function()
    -- red under: deleting the SetTextColor call from Icon:ApplyTextConfig
    local _, icon, cfg = classyIcon("target")
    cfg.cooldownTextColor = { r = 0.25, g = 0.5, b = 0.75, a = 0.6 }
    cfg.useClassColorCooldownText = false
    icon:ApplyTextConfig(cfg)
    local r, g, b, a = icon.cooldownText:GetTextColor()
    assertEqual(r, 0.25); assertEqual(g, 0.5); assertEqual(b, 0.75); assertEqual(a, 0.6)
end)

test("the countdown's class color is the PLAYER's, on the Focus grid too", function()
    -- red under: passing self.unit instead of nil into the resolver in
    -- ApplyTextConfig -- which would paint a Focus grid in the focus's class
    -- while it counts down the player's own interrupt.
    for _, unit in ipairs({ "target", "focus" }) do
        local _, icon, cfg = classyIcon(unit)
        cfg.cooldownTextColor = { r = 0, g = 0, b = 0, a = 0.5 }
        cfg.useClassColorCooldownText = true
        icon:ApplyTextConfig(cfg)
        local r, g, b, a = icon.cooldownText:GetTextColor()
        assertEqual(r, 1, unit .. ": the PLAYER's class red")
        assertEqual(g, 0.9, unit .. ": the PLAYER's class green")
        assertEqual(b, 0.8, unit .. ": the PLAYER's class blue")
        assertEqual(a, 0.5, unit .. ": the stored alpha survives the mode")
    end
end)

test("the countdown's drop shadow is applied, and CLEARED again", function()
    -- red under: making the shadow branch a one-way `if cfg.cooldownTextShadow then`
    local _, icon, cfg = classyIcon("target")
    cfg.cooldownTextShadow = true
    icon:ApplyTextConfig(cfg)
    local x, y = icon.cooldownText:GetShadowOffset()
    assertTrue(x ~= 0 or y ~= 0, "a shadow that is on must have an offset")

    cfg.cooldownTextShadow = false
    icon:ApplyTextConfig(cfg)
    local x2, y2 = icon.cooldownText:GetShadowOffset()
    assertEqual(x2, 0); assertEqual(y2, 0)
    local _, _, _, a2 = icon.cooldownText:GetShadowColor()
    assertEqual(a2, 0)
end)

test("the icon border honors its class-color companion, player-scoped", function()
    -- red under: reverting Icon:ApplyAppearance to safeUnpackColor, which
    -- ignores the companion entirely
    local _, icon, cfg = classyIcon("focus")
    cfg.borderShow  = true
    cfg.borderColor = { r = 0, g = 0, b = 0, a = 1 }
    cfg.useClassColorBorder = true
    icon:ApplyAppearance(cfg)
    local r, g, b = icon.border:GetBackdropBorderColor()
    assertEqual(r, 1); assertEqual(g, 0.9); assertEqual(b, 0.8)
end)

test("the ready glow's class color is the player's, and a toggle restarts it",
function()
    -- UnpackGlowColor is what the glow path resolves through, and the
    -- idempotency gate in StartGlow compares the RESOLVED numbers -- so a
    -- class-color toggle restarts the glow exactly as moving the swatch does.
    -- red under: passing a unit token into unpackGlowColor
    local inst = T.load(true, true, function(mocks)
        mocks.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 0.9, b = 0.8 } }
        mocks.UnitClass = function() return "Priest", "PRIEST", 5 end
    end)
    local IconGrid = inst.NS:GetModule("IconGrid")
    local stored = { r = 0.1, g = 0.2, b = 0.3, a = 0.7 }

    local r, g, b, a = IconGrid.UnpackGlowColor(stored, false)
    assertEqual(r, 0.1); assertEqual(g, 0.2); assertEqual(b, 0.3); assertEqual(a, 0.7)

    local cr, cg, cb, ca = IconGrid.UnpackGlowColor(stored, true)
    assertEqual(cr, 1); assertEqual(cg, 0.9); assertEqual(cb, 0.8)
    assertEqual(ca, 0.7, "the stored alpha survives the mode")
end)

test("toggling the cooldown tint's companion rebuilds the alpha/tint curves",
function()
    -- The tint feeds a CURVE that is only rebuilt when its signature moves, so a
    -- companion missing from that signature is a setting that appears to do
    -- nothing until some unrelated field happens to change.
    -- red under: dropping useClassColorCooldownTint from curveSignature
    local inst = T.load(true, true, function(mocks)
        mocks.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 0.9, b = 0.8 } }
        mocks.UnitClass = function() return "Priest", "PRIEST", 5 end
    end)
    local NS = inst.NS
    local IconGrid = NS:GetModule("IconGrid")
    local cfg = NS.db.profile.units.target.icons
    cfg.cooldownTint = { r = 0.1, g = 0.2, b = 0.3, a = 1 }
    cfg.useClassColorCooldownTint = false
    IconGrid.BuildCurves("target")
    local before = IconGrid.CurvesFor("target").sig
    assertTrue(before ~= nil, "sanity: the curves must have been built")

    cfg.useClassColorCooldownTint = true
    IconGrid.BuildCurves("target")
    assertTrue(IconGrid.CurvesFor("target").sig ~= before,
        "the companion must be part of what shapes a curve")
end)

-- ── the two master rows that were already here (options-ui-§15) ─────────────
--
-- `scale` and `alpha` did not move pages and did not change shape in the
-- settings-revamp-v2 pass — they were already the addon-wide values §15 asks
-- for, on the tab §15 asks for. What was missing is a case saying the drawing
-- code reads them, which is what makes them settings rather than declarations.

test("master scale and master alpha reach the grid frame", function()
    -- red under: dropping either SetScale/SetAlpha from IconGrid:ApplyGeneral
    local inst = T.load(true, true)
    local NS = inst.NS
    local IconGrid = NS:GetModule("IconGrid")
    NS.db.profile.scale = 1.4
    NS.db.profile.alpha = 0.35
    local gi = IconGrid:GetInstance("target")
    IconGrid:ApplyGeneral(gi)
    local grid = IconGrid:GetGridFrame("target")
    assertTrue(grid ~= nil, "the target grid must exist on an enabled instance")
    assertEqual(grid:GetScale(), 1.4, "master scale must reach the grid")
    assertEqual(grid:GetAlpha(), 0.35, "master alpha must reach the grid")
end)
