-- tests/test_castbar_skin.lua — modules/Castbar_Skin.lua, the config-driven
-- re-skin peeled out of Castbar.lua (KCD-19) and split structural-vs-color
-- (F-015).
--
-- The split is a performance change with a correctness trap: a guarded half
-- that skips too eagerly stops honoring config edits, and the failure is
-- invisible headlessly unless something asserts the widget actually moved. So
-- these cases assert on BOTH sides of the guard — that a structural edit still
-- lands, and that a pure color edit no longer pays for the structural pass.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local assertFalse, assertNear = T.assertFalse, T.assertNear

--- A fully enabled instance per test — Reskin writes to per-instance state
--- (inst.structureSig), so sharing one across cases would make them
--- order-dependent in exactly the way this feature is sensitive to.
local function enabled()
    local inst = T.load(true, true)
    return inst.NS, inst.NS:GetModule("Castbar")
end

--- The live `castbar` config table for a unit, straight out of the profile.
local function castbarCfg(NS, unit)
    return NS.db.profile.units[unit or "target"].castbar
end

-- ── Signature ───────────────────────────────────────────────────────────────

test("StructureSignature is stable for identical inputs", function()
    local NS, Castbar = enabled()
    local c = castbarCfg(NS)
    local i, u = Castbar.INT_FALLBACK, Castbar.UNINT_FALLBACK
    assertEqual(Castbar.StructureSignature(c, i, u, 250, 24),
                Castbar.StructureSignature(c, i, u, 250, 24),
                "same inputs must produce the same key or nothing is ever skipped")
end)

test("StructureSignature moves when a structural field moves", function()
    local NS, Castbar = enabled()
    local c = castbarCfg(NS)
    local i, u = Castbar.INT_FALLBACK, Castbar.UNINT_FALLBACK
    local before = Castbar.StructureSignature(c, i, u, 250, 24)
    c.iconPosition = (c.iconPosition == "RIGHT") and "LEFT" or "RIGHT"
    assertTrue(Castbar.StructureSignature(c, i, u, 250, 24) ~= before,
        "an iconPosition flip must invalidate the structure signature")
end)

test("StructureSignature moves when the RESOLVED size moves", function()
    -- Auto-size tracks the icon grid's footprint, which changes on
    -- Ka0s_KickCD_GRID_LAYOUT while the config table sits perfectly still.
    -- Signing the resolved dimensions is what keeps auto-size working.
    local NS, Castbar = enabled()
    local c = castbarCfg(NS)
    local i, u = Castbar.INT_FALLBACK, Castbar.UNINT_FALLBACK
    assertTrue(Castbar.StructureSignature(c, i, u, 250, 24)
            ~= Castbar.StructureSignature(c, i, u, 300, 24),
        "a different resolved long axis must invalidate the signature")
end)

test("StructureSignature ignores pure color fields", function()
    -- This is the whole point of F-015: a color-picker drag commits every
    -- 50 ms, and none of those commits may trigger the structural pass.
    local NS, Castbar = enabled()
    local c = castbarCfg(NS)
    local i = { borderTexture = "Blizzard Tooltip", borderSize = 1,
                barColor = { 1, 1, 1, 1 } }
    local u = { borderTexture = "Blizzard Tooltip", borderSize = 2,
                barColor = { 1, 1, 1, 1 } }
    local before = Castbar.StructureSignature(c, i, u, 250, 24)
    i.barColor = { 0, 0, 0, 1 }
    u.barColor = { 0.5, 0.5, 0.5, 1 }
    assertEqual(Castbar.StructureSignature(c, i, u, 250, 24), before,
        "bar colors must not appear in the structure signature")
end)

test("StructureSignature DOES move for border size/texture", function()
    -- Border thickness and texture are a SetBackdrop — a table allocation and
    -- a texture load — so they belong on the guarded side even though the
    -- border's color does not.
    local NS, Castbar = enabled()
    local c = castbarCfg(NS)
    local i = { borderTexture = "Blizzard Tooltip", borderSize = 1 }
    local u = { borderTexture = "Blizzard Tooltip", borderSize = 2 }
    local before = Castbar.StructureSignature(c, i, u, 250, 24)
    i.borderSize = 4
    assertTrue(Castbar.StructureSignature(c, i, u, 250, 24) ~= before,
        "borderSize is structural (SetBackdrop), not a color")
end)

-- ── Reskin through the guard ────────────────────────────────────────────────

test("Reskin stamps a structure signature on the instance", function()
    local _NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    assertTrue(inst.structureSig ~= nil,
        "EnableUnit's Reskin must record the signature it applied")
end)

test("a structural config change re-sizes the frame", function()
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.autoSize = false
    c.width, c.height = 300, 30
    Castbar:Reskin(inst)
    assertEqual(inst.frame:GetWidth(),  300, "width must follow the config")
    assertEqual(inst.frame:GetHeight(), 30,  "height must follow the config")
end)

test("a SECOND structural change still lands (the guard is not one-shot)", function()
    -- A signature guard that latches after its first hit would leave the bar
    -- frozen at whatever size it happened to be built with.
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.autoSize = false
    c.width = 300
    Castbar:Reskin(inst)
    c.width = 420
    Castbar:Reskin(inst)
    assertEqual(inst.frame:GetWidth(), 420, "the guard must re-open on each new signature")
end)

test("re-skinning with no config change leaves the signature untouched", function()
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    castbarCfg(NS).autoSize = false
    Castbar:Reskin(inst)
    local sig = inst.structureSig
    Castbar:Reskin(inst)
    assertEqual(inst.structureSig, sig, "an unchanged config must not churn the signature")
end)

test("a color-only change does NOT move the structure signature", function()
    -- The load-bearing assertion for F-015: this is the 50 ms color-drag path.
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.autoSize = false
    Castbar:Reskin(inst)
    local sig = inst.structureSig

    c.interruptible = c.interruptible or {}
    c.interruptible.barColor = { 0.1, 0.2, 0.3, 1 }
    Castbar:Reskin(inst)

    assertEqual(inst.structureSig, sig,
        "a bar color edit must not invalidate the structural signature")
end)

test("a color-only change still repaints the bar", function()
    -- Skipping the structural half must not skip the color half with it.
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.autoSize = false
    Castbar:Reskin(inst)

    c.interruptible = c.interruptible or {}
    c.interruptible.barColor = { 0.25, 0.5, 0.75, 1 }
    Castbar:Reskin(inst)

    local r, g, b = inst.frame.bar.interruptible:GetStatusBarColor()
    assertEqual(r, 0.25, "red channel must follow the config")
    assertEqual(g, 0.5,  "green channel must follow the config")
    assertEqual(b, 0.75, "blue channel must follow the config")
end)

test("force rebuilds the geometry even when the signature matches", function()
    -- EnableUnit passes force=true because EnsureFrame may have just built
    -- fresh widgets with no geometry while the instance still carries a
    -- matching signature.
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.autoSize = false
    c.width, c.height = 300, 30
    Castbar:Reskin(inst)

    -- Scribble over the geometry behind Reskin's back, then re-skin with the
    -- signature deliberately unchanged.
    inst.frame:SetSize(1, 1)
    Castbar:Reskin(inst)
    assertEqual(inst.frame:GetWidth(), 1, "without force, a matching signature must skip")

    Castbar:Reskin(inst, true)
    assertEqual(inst.frame:GetWidth(), 300, "force must rebuild regardless of the signature")
end)

test("Reskin is safe before the frame has ever been built", function()
    local _NS, Castbar = enabled()
    Castbar:Reskin({ unit = "target", frame = nil })
end)

-- ── Per-unit independence ───────────────────────────────────────────────────

test("target and focus carry independent structure signatures", function()
    -- Both instances re-skin off their own resolved config; one unit's guard
    -- must never suppress the other's rebuild.
    local NS, Castbar = enabled()
    NS.db.profile.units.focus.enabled = true
    NS.db.profile.units.focus.link    = false
    Castbar:ReconcileUnits()

    local tInst = Castbar:GetInstance("target")
    local fInst = Castbar:GetInstance("focus")

    castbarCfg(NS, "target").autoSize = false
    castbarCfg(NS, "focus").autoSize  = false
    castbarCfg(NS, "target").width    = 300
    castbarCfg(NS, "focus").width     = 500

    Castbar:Reskin(tInst)
    Castbar:Reskin(fInst)

    assertTrue(tInst.structureSig ~= fInst.structureSig,
        "an unlinked focus with a different width must not share target's signature")
    assertEqual(tInst.frame:GetWidth(), 300, "target keeps its own width")
    assertEqual(fInst.frame:GetWidth(), 500, "focus keeps its own width")
end)

-- ── ResolveBarSize ──────────────────────────────────────────────────────────

test("ResolveBarSize floors the long and thick axes", function()
    -- A degenerate config (or a corrupt saved-var) must not produce a
    -- zero-sized frame that the user can never find again to fix.
    local _NS, Castbar = enabled()
    local long, thick = Castbar.ResolveBarSize(
        { unit = "target" }, { width = 1, height = 1 }, false)
    assertEqual(long,  40, "long axis floors at 40")
    assertEqual(thick, 8,  "thick axis floors at 8")
end)

test("ResolveBarSize returns the configured size when auto-size is off", function()
    local _NS, Castbar = enabled()
    local long, thick = Castbar.ResolveBarSize(
        { unit = "target" }, { width = 320, height = 18, autoSize = false }, false)
    assertEqual(long,  320)
    assertEqual(thick, 18)
end)

test("ResolveBarSize leaves thickness alone in vertical orientation", function()
    -- Vertical swaps which PHYSICAL axis each semantic dimension maps to, but
    -- the semantic values themselves don't change — the caller does the swap.
    local _NS, Castbar = enabled()
    local long, thick = Castbar.ResolveBarSize(
        { unit = "target" }, { width = 320, height = 18, autoSize = false }, true)
    assertEqual(long,  320)
    assertEqual(thick, 18)
end)

-- ── Icon / bar layout matrix ────────────────────────────────────────────────
--
-- The 2x2 of iconPosition x orientation is pure in-game geometry with nothing
-- else asserting it: a transposed anchor is invisible headlessly and obvious to
-- every user. These cases pin all four arms plus the OFF arm and the clamp.

--- Re-skin target with `fields` merged over its castbar config and hand back
--- the instance. autoSize is forced off so the resolved size is the configured
--- one; force is passed so each case rebuilds regardless of the signature.
--- `clear` names keys to remove outright — a nil in `fields` would be invisible
--- to pairs(), so the unset-field defaults need their own channel.
local function skinned(fields, clear)
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.autoSize = false
    c.width, c.height = 250, 24
    for k, v in pairs(fields) do c[k] = v end
    for _, k in ipairs(clear or {}) do c[k] = nil end
    Castbar:Reskin(inst, true)
    return inst
end

--- The i-th anchor of `region` as a flat string, for one-line comparison.
local function pointAt(region, i)
    local point, _relativeTo, relativePoint, x, y = region:GetPoint(i)
    return ("%s/%s/%s/%s"):format(tostring(point), tostring(relativePoint),
                                 tostring(x), tostring(y))
end

test("HORIZONTAL + iconPosition LEFT insets the bar from the left", function()
    local inst = skinned({ orientation = "HORIZONTAL", iconPosition = "LEFT", iconSize = 20 })
    assertTrue(inst.frame.icon:IsShown(), "the icon must be shown")
    assertEqual(inst.frame.icon:GetWidth(), 20, "the icon is square at iconSize")
    assertEqual(pointAt(inst.frame.icon, 1), "LEFT/LEFT/0/0")
    assertEqual(pointAt(inst.frame.bar, 1), "TOPLEFT/TOPLEFT/20/0")
    assertEqual(pointAt(inst.frame.bar, 2), "BOTTOMRIGHT/BOTTOMRIGHT/0/0")
end)

test("HORIZONTAL + iconPosition RIGHT insets the bar from the right", function()
    local inst = skinned({ orientation = "HORIZONTAL", iconPosition = "RIGHT", iconSize = 20 })
    assertEqual(pointAt(inst.frame.icon, 1), "RIGHT/RIGHT/0/0")
    assertEqual(pointAt(inst.frame.bar, 1), "TOPLEFT/TOPLEFT/0/0")
    assertEqual(pointAt(inst.frame.bar, 2), "BOTTOMRIGHT/BOTTOMRIGHT/-20/0")
end)

test("VERTICAL remaps iconPosition LEFT to the TOP of the bar", function()
    -- Literal left/right makes no sense for a tall bar, so LEFT reads as TOP.
    local inst = skinned({ orientation = "VERTICAL", iconPosition = "LEFT", iconSize = 20 })
    assertEqual(pointAt(inst.frame.icon, 1), "TOP/TOP/0/0")
    assertEqual(pointAt(inst.frame.bar, 1), "TOPLEFT/TOPLEFT/0/-20")
    assertEqual(pointAt(inst.frame.bar, 2), "BOTTOMRIGHT/BOTTOMRIGHT/0/0")
end)

test("VERTICAL remaps iconPosition RIGHT to the BOTTOM of the bar", function()
    local inst = skinned({ orientation = "VERTICAL", iconPosition = "RIGHT", iconSize = 20 })
    assertEqual(pointAt(inst.frame.icon, 1), "BOTTOM/BOTTOM/0/0")
    assertEqual(pointAt(inst.frame.bar, 1), "TOPLEFT/TOPLEFT/0/0")
    assertEqual(pointAt(inst.frame.bar, 2), "BOTTOMRIGHT/BOTTOMRIGHT/0/20")
end)

test("iconPosition OFF hides the icon and gives the bar the whole frame", function()
    local inst = skinned({ orientation = "HORIZONTAL", iconPosition = "OFF", iconSize = 20 })
    assertFalse(inst.frame.icon:IsShown(), "OFF must hide the icon")
    assertEqual(inst.frame.bar:GetNumPoints(), 0, "the bar takes SetAllPoints, not an inset")
end)

test("a zero iconSize hides the icon as surely as OFF does", function()
    local inst = skinned({ orientation = "HORIZONTAL", iconPosition = "LEFT", iconSize = 0 })
    assertFalse(inst.frame.icon:IsShown(), "a zero-size icon must not be shown")
end)

test("iconSize is clamped to the bar's thickness", function()
    -- The icon sits on the short axis; an oversized one would overflow the bar.
    local inst = skinned({ orientation = "HORIZONTAL", iconPosition = "LEFT", iconSize = 100 })
    assertEqual(inst.frame.icon:GetWidth(), 24, "the icon clamps to the bar height")
    assertEqual(pointAt(inst.frame.bar, 1), "TOPLEFT/TOPLEFT/24/0",
        "the bar inset must follow the CLAMPED size, not the configured one")
end)

-- ── Spark ───────────────────────────────────────────────────────────────────
--
-- The spark rides the fill edge, and which edge that is depends on orientation
-- AND reverse fill. Four combinations, all in-game-only without these.

--- Re-skin with a rotation recorder on the spark and return the instance plus
--- the last rotation applied. The mock's PascalCase fallback makes SetRotation
--- a silent no-op otherwise, so the vertical 90-degree turn would go unseen.
local function skinnedSpark(fields, clear)
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local rotation
    inst.frame.spark.SetRotation = function(_, r) rotation = r end
    local c = castbarCfg(NS)
    c.autoSize = false
    c.width, c.height = 250, 24
    for k, v in pairs(fields) do c[k] = v end
    for _, k in ipairs(clear or {}) do c[k] = nil end
    Castbar:Reskin(inst, true)
    return inst, rotation
end

--- The relativePoint of the spark's single anchor — the fill edge it rides.
local function sparkAnchor(inst)
    local _point, _relativeTo, relativePoint = inst.frame.spark:GetPoint(1)
    return relativePoint
end

test("HORIZONTAL grow RIGHT puts the spark on the bar's RIGHT fill edge", function()
    local inst = skinnedSpark({ orientation = "HORIZONTAL", growDirection = "RIGHT" })
    assertEqual(sparkAnchor(inst), "RIGHT")
end)

test("HORIZONTAL grow LEFT reverses the fill and the spark rides LEFT", function()
    local inst = skinnedSpark({ orientation = "HORIZONTAL", growDirection = "LEFT" })
    assertEqual(sparkAnchor(inst), "LEFT")
end)

test("VERTICAL grow UP puts the spark on the TOP fill edge", function()
    local inst = skinnedSpark({ orientation = "VERTICAL", growDirection = "UP" })
    assertEqual(sparkAnchor(inst), "TOP")
end)

test("VERTICAL grow DOWN reverses the fill and the spark rides BOTTOM", function()
    local inst = skinnedSpark({ orientation = "VERTICAL", growDirection = "DOWN" })
    assertEqual(sparkAnchor(inst), "BOTTOM")
end)

test("the spark is sized across the bar and rotated 90 degrees when vertical", function()
    local inst, rotation = skinnedSpark({ orientation = "VERTICAL", growDirection = "UP" })
    local w, h = inst.frame.spark:GetSize()
    assertEqual(w, 30, "vertical spans the bar thickness (24) plus 6")
    assertEqual(h, 20)
    assertNear(rotation, math.pi / 2, 1e-9, "the vertical spark is a horizontal slash")
end)

test("the spark is unrotated and tall when horizontal", function()
    local inst, rotation = skinnedSpark({ orientation = "HORIZONTAL", growDirection = "RIGHT" })
    local w, h = inst.frame.spark:GetSize()
    assertEqual(w, 20)
    assertEqual(h, 30, "horizontal spans the bar thickness (24) plus 6")
    assertEqual(rotation, 0)
end)

test("showSpark=false hides the spark outright", function()
    local inst = skinnedSpark({ showSpark = false })
    assertFalse(inst.frame.spark:IsShown(), "an explicit false must hide the spark")
end)

test("showSpark defaults to shown when unset", function()
    -- The guard is `~= false`, so nil means shown.
    local inst = skinnedSpark({}, { "showSpark" })
    assertTrue(inst.frame.spark:IsShown(), "only an explicit false hides the spark")
end)

-- ── Fonts, text anchors and label visibility ────────────────────────────────

test("both labels share the config font, and NONE flags normalize to empty", function()
    local inst = skinned({ font = "Friz Quadrata TT", fontSize = 16, fontFlags = "NONE" })
    local _p, size, flags = inst.frame.nameText:GetFont()
    assertEqual(size, 16)
    assertEqual(flags, "", "NONE must reach SetFont as the empty string")
    local _p2, size2 = inst.frame.timeText:GetFont()
    assertEqual(size2, 16, "the time label shares the name label's font")
end)

test("absent fontFlags normalize to empty too", function()
    local inst = skinned({}, { "fontFlags" })
    local _p, _s, flags = inst.frame.nameText:GetFont()
    assertEqual(flags, "")
end)

test("showName / showTime false hide their labels, and only theirs", function()
    local inst = skinned({ showName = false, showTime = true })
    assertFalse(inst.frame.nameText:IsShown())
    assertTrue(inst.frame.timeText:IsShown())
end)

test("the labels default to shown when the flags are unset", function()
    local inst = skinned({}, { "showName", "showTime" })
    assertTrue(inst.frame.nameText:IsShown())
    assertTrue(inst.frame.timeText:IsShown())
end)

test("name and time labels anchor per their independent position settings", function()
    local inst = skinned({ namePosition = "OUTSIDE_LEFT", nameOffsetX = 3, nameOffsetY = -2,
                           timePosition = "CENTER",       timeOffsetX = 1, timeOffsetY = 4 })
    assertEqual(inst.frame.nameText:GetJustifyH(), "RIGHT",
        "OUTSIDE_LEFT grows the text away from the bar's left edge")
    assertEqual(pointAt(inst.frame.nameText, 1), "RIGHT/LEFT/-1/-2",
        "the 4px outside inset carries the user's offsetX")
    assertEqual(inst.frame.timeText:GetJustifyH(), "CENTER")
    assertEqual(pointAt(inst.frame.timeText, 1), "CENTER/CENTER/1/4")
end)

-- ── Peel integrity ──────────────────────────────────────────────────────────

test("Reskin survived the peel as a method on the Castbar module", function()
    -- Castbar_Skin.lua re-opens the module rather than forking it; if the TOC
    -- ever loses the file, this is the case that says so out loud.
    local _NS, Castbar = enabled()
    assertTrue(type(Castbar.Reskin) == "function",
        "modules/Castbar_Skin.lua must be loaded and must attach Castbar:Reskin")
end)

test("the skin sibling reads its helpers off the module, not a private copy", function()
    -- The peel deliberately did NOT duplicate the pure helpers; they are
    -- published on the module table and consumed from there.
    local _NS, Castbar = enabled()
    for _, name in ipairs({ "UnpackColor", "StateConfig", "FetchFont",
                            "FetchBorderTexture", "FetchStatusBarTexture",
                            "AutoSizeLong", "ResolveGridFrame" }) do
        assertTrue(type(Castbar[name]) == "function",
            "Castbar." .. name .. " must stay published for Castbar_Skin.lua")
    end
end)

test("modules/Castbar.lua sits under the 1500-LOC hard cap (layout-§1)", function()
    -- The reason the peel happened. Asserting it keeps the file from creeping
    -- back over the cap between standards audits.
    local function loc(path)
        local f = assert(io.open(T.root .. "/" .. path, "r"))
        local n = 0
        for _ in f:lines() do n = n + 1 end
        f:close()
        return n
    end
    for _, path in ipairs({ "modules/Castbar.lua", "modules/Castbar_Skin.lua" }) do
        local n = loc(path)
        assertTrue(n < 1500, path .. " is " .. n .. " LOC, over the 1500 hard cap")
    end
end)

-- ── the composed Bar / Background / Border blocks (options-ui-§16, §17) ─────
--
-- Three settings arrived with them that the cast bar did not have: bar opacity,
-- a cast-time color and a "use class color" companion beside every swatch. Each
-- is asserted where it lands on a widget, because a setting that is declared and
-- not honored is worse than one that is absent.

--- An enabled instance whose player and target are DIFFERENT classes, so a
--- class-color test can tell which of the two the resolver picked.
local function classy()
    local inst = T.load(true, true, function(mocks)
        mocks.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 },
                                    SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
        mocks.UnitClass = function(unit)
            if unit == "player" then return "Priest", "PRIEST", 5 end
            return "Shaman", "SHAMAN", 7
        end
    end)
    return inst.NS, inst.NS:GetModule("Castbar")
end

test("bar opacity folds into the per-state alpha, and is not a second SetAlpha",
function()
    -- It has to ride the CURVE: modules/Castbar.lua's ApplyState alpha-switches
    -- the two stacked bars off the secret notInterruptible flag, so an alpha
    -- applied anywhere else is either overwritten on the next cast or, worse,
    -- arithmetic on a secret value.
    -- red under: dropping barAlpha from the EvaluateColorValueFromBoolean call
    -- and doing frame.bar.interruptible:SetAlpha(barAlpha(intCfg)) in ReskinColors
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.interruptible.barAlpha = 0.4
    Castbar:Reskin(inst)
    Castbar:ApplyState(inst)   -- the no-cast preview arm
    assertNear(inst.frame.bar.interruptible:GetAlpha(), 0.4, 1e-6,
        "the visible bar must be drawn at the configured opacity")
end)

test("a bar opacity outside 0..1 is clamped rather than passed through", function()
    -- SavedVariables are hand-editable, and an alpha of 7 is not an error the
    -- player can see -- it is a bar that is simply opaque forever.
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.interruptible.barAlpha = 7
    Castbar:ApplyState(inst)
    assertEqual(inst.frame.bar.interruptible:GetAlpha(), 1)
    c.interruptible.barAlpha = -3
    Castbar:ApplyState(inst)
    assertEqual(inst.frame.bar.interruptible:GetAlpha(), 0)
end)

test("the cast time text takes its own color, which it never had before", function()
    -- The spell NAME keeps its two per-state swatches; this governs the cast
    -- TIME, which modules/Castbar_Skin.lua hardcoded to white.
    -- red under: restoring `frame.timeText:SetTextColor(1, 1, 1, 1)`
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.textColor = { r = 0.25, g = 0.5, b = 0.75, a = 0.6 }
    c.useClassColorText = false
    Castbar:Reskin(inst)
    local r, g, b, a = inst.frame.timeText:GetTextColor()
    assertEqual(r, 0.25); assertEqual(g, 0.5); assertEqual(b, 0.75); assertEqual(a, 0.6)
end)

test("the font shadow is applied, and CLEARED again", function()
    -- red under: making the shadow branch a one-way `if c.fontShadow then`
    local NS, Castbar = enabled()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.fontShadow = true
    Castbar:Reskin(inst, true)
    local x, y = inst.frame.nameText:GetShadowOffset()
    assertTrue(x ~= 0 or y ~= 0, "a shadow that is on must have an offset")

    c.fontShadow = false
    Castbar:Reskin(inst, true)
    local x2, y2 = inst.frame.nameText:GetShadowOffset()
    assertEqual(x2, 0); assertEqual(y2, 0)
    local _, _, _, a2 = inst.frame.timeText:GetShadowColor()
    assertEqual(a2, 0, "both text elements share the setting")
end)

test("the font shadow is part of the structure signature", function()
    -- Fonts are the guarded half, so a shadow toggle that is not in the
    -- signature simply never takes effect until something else structural moves.
    -- red under: removing tostring(c.fontShadow) from structureSignature
    local NS, Castbar = enabled()
    local c = castbarCfg(NS)
    local i, u = Castbar.INT_FALLBACK, Castbar.UNINT_FALLBACK
    local before = Castbar.StructureSignature(c, i, u, 250, 24)
    c.fontShadow = not c.fontShadow
    assertTrue(Castbar.StructureSignature(c, i, u, 250, 24) ~= before,
        "a font-shadow flip must invalidate the structure signature")
end)

-- ── which class the cast bar means (options-ui-§17) ─────────────────────────

test("every cast-bar swatch takes the TRACKED unit's class, not the player's",
function()
    -- The bar DESCRIBES the tracked unit. The player is a Priest (white) and the
    -- target a Shaman (blue) in this fixture, so a resolver that reached for the
    -- player would be white on every channel and indistinguishable from the
    -- stored swatch only by luck.
    -- red under: passing nil instead of inst.unit into ReskinColors' resolver calls
    local NS, Castbar = classy()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.interruptible.barColor          = { r = 1, g = 0, b = 0, a = 0.5 }
    c.interruptible.useClassColorBar  = true
    c.interruptible.bgColor           = { r = 1, g = 0, b = 0, a = 0.25 }
    c.interruptible.useClassColorBgColor = true
    c.interruptible.borderColor       = { r = 1, g = 0, b = 0, a = 1 }
    c.interruptible.useClassColorBorder = true
    Castbar:Reskin(inst, true)

    local br, bg, bb, ba = inst.frame.bar.interruptible:GetStatusBarColor()
    assertEqual(br, 0); assertNear(bg, 0.44, 1e-6); assertNear(bb, 0.87, 1e-6)
    assertEqual(ba, 0.5, "the stored alpha survives the mode")

    local kr, kg, kb, ka = inst.frame.bgInterruptible:GetColorTexture()
    assertEqual(kr, 0); assertNear(kg, 0.44, 1e-6); assertNear(kb, 0.87, 1e-6)
    assertEqual(ka, 0.25, "the background keeps its own alpha too")

    local er, eg, eb = inst.frame.borderInterruptible:GetBackdropBorderColor()
    assertEqual(er, 0); assertNear(eg, 0.44, 1e-6); assertNear(eb, 0.87, 1e-6)
end)

test("the spell name takes the tracked unit's class, per state", function()
    -- Resolved BEFORE the curve, never inside it: the resolver reads plain addon
    -- values and hands the curve four plain numbers to switch between.
    local NS, Castbar = classy()
    local inst = Castbar:GetInstance("target")
    local c = castbarCfg(NS)
    c.interruptible.nameTextColor = { r = 1, g = 0, b = 0, a = 1 }
    c.interruptible.useClassColorNameTextColor = true
    Castbar:ApplyState(inst)   -- preview arm: interruptible visuals
    local r, g, b = inst.frame.nameText:GetTextColor()
    assertEqual(r, 0); assertNear(g, 0.44, 1e-6); assertNear(b, 0.87, 1e-6)
end)

test("an NPC target falls through to the stored swatch, which is the common case",
function()
    -- Most of what this addon watches is a boss. The fall-through is intended,
    -- and the swatch's own tooltip is where it is said to the player.
    local inst = T.load(true, true, function(mocks)
        mocks.RAID_CLASS_COLORS = {}
        mocks.UnitClass = function() return "Boss", nil, nil end
    end)
    local NS = inst.NS
    local Castbar = NS:GetModule("Castbar")
    local ci = Castbar:GetInstance("target")
    local c = NS.db.profile.units.target.castbar
    c.interruptible.barColor         = { r = 0.25, g = 0.5, b = 0.75, a = 1 }
    c.interruptible.useClassColorBar = true
    Castbar:Reskin(ci, true)
    local r, g, b = ci.frame.bar.interruptible:GetStatusBarColor()
    assertEqual(r, 0.25); assertEqual(g, 0.5); assertEqual(b, 0.75)
end)

test("a LINKED Focus paints in the FOCUS's class, not the linked-from target's",
function()
    -- The appearance table is Target's; the bar on screen is Focus's.
    -- red under: resolving on the config table's source unit
    local inst = T.load(true, true, function(mocks)
        mocks.RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 },
                                    ROGUE  = { r = 1, g = 0.96, b = 0.41 } }
        mocks.UnitClass = function(unit)
            if unit == "focus" then return "Rogue", "ROGUE", 4 end
            return "Shaman", "SHAMAN", 7
        end
    end)
    local NS = inst.NS
    local Castbar = NS:GetModule("Castbar")
    NS.Units.Config("focus").link = true
    local c = NS.db.profile.units.target.castbar
    c.interruptible.barColor         = { r = 1, g = 0, b = 0, a = 1 }
    c.interruptible.useClassColorBar = true

    local fi = Castbar:GetInstance("focus")
    Castbar:EnableUnit("focus")
    Castbar:Reskin(fi, true)
    local r, g, b = fi.frame.bar.interruptible:GetStatusBarColor()
    assertEqual(r, 1, "the FOCUS's class")
    assertNear(g, 0.96, 1e-6)
    assertNear(b, 0.41, 1e-6)
end)
