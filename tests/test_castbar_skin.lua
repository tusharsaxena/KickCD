-- tests/test_castbar_skin.lua — modules/Castbar_Skin.lua, the config-driven
-- re-skin peeled out of Castbar.lua (KCD-19) and split structural-vs-colour
-- (F-015).
--
-- The split is a performance change with a correctness trap: a guarded half
-- that skips too eagerly stops honouring config edits, and the failure is
-- invisible headlessly unless something asserts the widget actually moved. So
-- these cases assert on BOTH sides of the guard — that a structural edit still
-- lands, and that a pure colour edit no longer pays for the structural pass.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

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

test("StructureSignature ignores pure colour fields", function()
    -- This is the whole point of F-015: a colour-picker drag commits every
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
        "bar colours must not appear in the structure signature")
end)

test("StructureSignature DOES move for border size/texture", function()
    -- Border thickness and texture are a SetBackdrop — a table allocation and
    -- a texture load — so they belong on the guarded side even though the
    -- border's colour does not.
    local NS, Castbar = enabled()
    local c = castbarCfg(NS)
    local i = { borderTexture = "Blizzard Tooltip", borderSize = 1 }
    local u = { borderTexture = "Blizzard Tooltip", borderSize = 2 }
    local before = Castbar.StructureSignature(c, i, u, 250, 24)
    i.borderSize = 4
    assertTrue(Castbar.StructureSignature(c, i, u, 250, 24) ~= before,
        "borderSize is structural (SetBackdrop), not a colour")
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

test("a colour-only change does NOT move the structure signature", function()
    -- The load-bearing assertion for F-015: this is the 50 ms colour-drag path.
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
        "a bar colour edit must not invalidate the structural signature")
end)

test("a colour-only change still repaints the bar", function()
    -- Skipping the structural half must not skip the colour half with it.
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
