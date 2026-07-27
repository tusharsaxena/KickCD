-- tests/test_castbar_helpers.lua — the pure helpers behind modules/Castbar.lua.
--
-- Castbar is the largest module in the addon and, until these helpers were
-- published, only its auto-size math was reachable headlessly. Everything
-- here decides what the user actually sees: which colour a bar state resolves
-- to, how a spell name is clipped, which SetPoint token an anchor setting
-- maps to, and which texture path a missing LibSharedMedia key degrades to.
--
-- truncateName carries a 12.0 secret-value rule as well — `rec.name` can be
-- secret-tainted in combat for protected casts, and `#name` / string.sub on a
-- secret error in tainted scope. Losing truncation for a frame is the correct
-- degradation; throwing is not.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

local inst    = T.load(true)
local mocks   = inst.mocks
local Castbar = inst.NS:GetModule("Castbar")

test("the Castbar pure helpers are published for testing", function()
    for _, name in ipairs({ "UnpackColor", "TruncateName", "StateConfig", "ToSetPoint",
                            "FetchStatusBarTexture", "FetchBorderTexture", "FetchFont" }) do
        assertTrue(type(Castbar[name]) == "function", name .. " must be published")
    end
end)

-- ── unpackColor ─────────────────────────────────────────────────────────────

test("UnpackColor reads an array-style colour", function()
    local r, g, b, a = Castbar.UnpackColor({ 0.2, 0.4, 0.6, 0.8 })
    assertEqual(r, 0.2); assertEqual(g, 0.4); assertEqual(b, 0.6); assertEqual(a, 0.8)
end)

test("UnpackColor reads a hash-style colour", function()
    -- Both shapes exist in the wild: schema defaults are arrays, Blizzard
    -- colour objects are hashes.
    local r, g, b, a = Castbar.UnpackColor({ r = 1, g = 0, b = 0, a = 0.5 })
    assertEqual(r, 1); assertEqual(g, 0); assertEqual(b, 0); assertEqual(a, 0.5)
end)

test("UnpackColor uses the CALLER's fallback for a nil colour", function()
    -- The module-specific fallback is why this wraps Util.Unpack at all —
    -- a missing bar colour must not silently become white.
    local r, g, b, a = Castbar.UnpackColor(nil, 0.85, 0.1, 0.1, 1)
    assertEqual(r, 0.85); assertEqual(g, 0.1); assertEqual(b, 0.1); assertEqual(a, 1)
end)

test("UnpackColor falls back to opaque white when the caller gives no fallback", function()
    local r, g, b, a = Castbar.UnpackColor(nil)
    assertEqual(r, 1); assertEqual(g, 1); assertEqual(b, 1); assertEqual(a, 1)
end)

test("UnpackColor defaults a missing alpha to fully opaque", function()
    -- A three-element colour row must not render the bar invisible.
    local _, _, _, a = Castbar.UnpackColor({ 0.2, 0.4, 0.6 })
    assertEqual(a, 1)
end)

-- ── truncateName ────────────────────────────────────────────────────────────

test("TruncateName leaves a name shorter than the cap alone", function()
    assertEqual(Castbar.TruncateName("Kick", 20), "Kick")
end)

test("TruncateName leaves a name EXACTLY at the cap alone", function()
    -- Off-by-one here would put an ellipsis on names that already fit.
    assertEqual(Castbar.TruncateName("Chaos", 5), "Chaos")
end)

test("TruncateName clips and appends an ellipsis past the cap", function()
    assertEqual(Castbar.TruncateName("Chaos Bolt", 5), "Chaos…")
end)

test("TruncateName treats 0 and nil as 'no truncation'", function()
    -- 0 is the schema's "off" value for the cap slider.
    assertEqual(Castbar.TruncateName("Chaos Bolt", 0), "Chaos Bolt")
    assertEqual(Castbar.TruncateName("Chaos Bolt", nil), "Chaos Bolt")
end)

test("TruncateName treats a negative cap as 'no truncation'", function()
    assertEqual(Castbar.TruncateName("Chaos Bolt", -3), "Chaos Bolt")
end)

test("TruncateName returns an empty string for a nil name", function()
    -- The result goes straight into FontString:SetText.
    assertEqual(Castbar.TruncateName(nil, 10), "")
end)

test("TruncateName passes a SECRET name through without measuring it", function()
    -- `#name` and string.sub on a secret error in tainted scope. Dropping the
    -- truncation for that frame is the documented degradation.
    local secret = setmetatable({}, {
        __len      = function() error("# on a secret cast name", 0) end,
        __tostring = function() error("tostring() on a secret cast name", 0) end,
        __concat   = function() error("concat on a secret cast name", 0) end,
    })
    local prev = mocks.issecretvalue
    mocks.issecretvalue = function(v) return rawequal(v, secret) end
    local out = Castbar.TruncateName(secret, 5)
    mocks.issecretvalue = prev
    assertTrue(rawequal(out, secret), "a secret name must be returned verbatim")
end)

-- ── stateConfig ─────────────────────────────────────────────────────────────

test("StateConfig returns the configured per-state table when present", function()
    local cfg = { interruptible = { barColor = { 1, 1, 0, 1 } } }
    assertTrue(rawequal(Castbar.StateConfig(cfg, "interruptible", {}), cfg.interruptible))
end)

test("StateConfig falls back when the state key is missing", function()
    -- A profile from before the per-state colours shipped has no key at all;
    -- without the fallback every colour read would nil-index.
    local fb = Castbar.INT_FALLBACK
    assertTrue(rawequal(Castbar.StateConfig({}, "interruptible", fb), fb))
end)

test("StateConfig rejects a non-table value stored under the state key", function()
    -- A legacy profile stored a bare colour string here; treating that as the
    -- config table would nil-index on every field.
    local fb = Castbar.UNINT_FALLBACK
    assertTrue(rawequal(Castbar.StateConfig({ uninterruptible = "red" }, "uninterruptible", fb), fb))
    assertTrue(rawequal(Castbar.StateConfig({ uninterruptible = false }, "uninterruptible", fb), fb))
end)

test("the interruptible fallback is gold with no border, the uninterruptible red with one", function()
    -- These are the shipped visual defaults and the reason the two states are
    -- distinguishable at a glance; a silent change here is a UX regression.
    local i, u = Castbar.INT_FALLBACK, Castbar.UNINT_FALLBACK
    assertFalse(i.borderShow, "an interruptible cast needs no warning border")
    assertTrue(u.borderShow, "an uninterruptible cast is flagged with a border")
    assertTrue(u.borderSize > i.borderSize)
    assertTrue(i.barColor[1] > 0.9 and i.barColor[2] > 0.5, "interruptible reads as gold")
    assertTrue(u.barColor[1] > 0.5 and u.barColor[2] < 0.3, "uninterruptible reads as red")
end)

test("both state fallbacks carry every field the reskin path reads", function()
    -- A field present in one fallback but not the other produces a state that
    -- renders with a nil where the other has a value.
    for key in pairs(Castbar.INT_FALLBACK) do
        assertTrue(Castbar.UNINT_FALLBACK[key] ~= nil,
            "uninterruptible fallback is missing " .. key)
    end
    for key in pairs(Castbar.UNINT_FALLBACK) do
        assertTrue(Castbar.INT_FALLBACK[key] ~= nil,
            "interruptible fallback is missing " .. key)
    end
end)

-- ── toSetPoint ──────────────────────────────────────────────────────────────

test("ToSetPoint maps every schema anchor token to a real SetPoint token", function()
    -- The settings dropdown stores readable tokens (TOP_LEFT); SetPoint wants
    -- Blizzard's (TOPLEFT). An unmapped token reaches SetPoint and errors.
    local cases = {
        TOP_LEFT = "TOPLEFT", TOP_MIDDLE = "TOP", TOP_RIGHT = "TOPRIGHT",
        BOTTOM_LEFT = "BOTTOMLEFT", BOTTOM_MIDDLE = "BOTTOM", BOTTOM_RIGHT = "BOTTOMRIGHT",
        LEFT_TOP = "TOPLEFT", LEFT_MIDDLE = "LEFT", LEFT_BOTTOM = "BOTTOMLEFT",
        RIGHT_TOP = "TOPRIGHT", RIGHT_MIDDLE = "RIGHT", RIGHT_BOTTOM = "BOTTOMRIGHT",
        CENTER = "CENTER",
    }
    for token, expected in pairs(cases) do
        assertEqual(Castbar.ToSetPoint(token), expected, "token " .. token)
    end
end)

test("ToSetPoint defaults a nil anchor to CENTER", function()
    assertEqual(Castbar.ToSetPoint(nil), "CENTER")
end)

test("ToSetPoint passes an already-valid SetPoint token straight through", function()
    -- Older profiles stored the raw Blizzard token; re-mapping would break them.
    assertEqual(Castbar.ToSetPoint("TOPLEFT"), "TOPLEFT")
    assertEqual(Castbar.ToSetPoint("BOTTOM"), "BOTTOM")
end)

-- ── LibSharedMedia fetches ──────────────────────────────────────────────────

test("FetchStatusBarTexture returns the LSM path when the key resolves", function()
    local prev = mocks.__libs["LibSharedMedia-3.0"].Fetch
    mocks.__libs["LibSharedMedia-3.0"].Fetch = function() return "Interface\\Custom\\Bar" end
    assertEqual(Castbar.FetchStatusBarTexture("Blizzard Raid Bar"), "Interface\\Custom\\Bar")
    mocks.__libs["LibSharedMedia-3.0"].Fetch = prev
end)

test("FetchStatusBarTexture degrades to a client-shipped path for an unknown key", function()
    -- A profile naming a texture from an addon the user has since removed
    -- must not produce a nil texture path.
    local prev = mocks.__libs["LibSharedMedia-3.0"].Fetch
    mocks.__libs["LibSharedMedia-3.0"].Fetch = function() return nil end
    local path = Castbar.FetchStatusBarTexture("No Such Texture")
    assertTrue(type(path) == "string" and #path > 0)
    assertTrue(path:find("Interface", 1, true) == 1, "must be a client-shipped path")
    mocks.__libs["LibSharedMedia-3.0"].Fetch = prev
end)

test("FetchBorderTexture degrades to a client-shipped border", function()
    local prev = mocks.__libs["LibSharedMedia-3.0"].Fetch
    mocks.__libs["LibSharedMedia-3.0"].Fetch = function() return nil end
    local path = Castbar.FetchBorderTexture(nil)
    assertTrue(type(path) == "string" and path:find("Interface", 1, true) == 1)
    mocks.__libs["LibSharedMedia-3.0"].Fetch = prev
end)

test("FetchFont always yields a usable font path", function()
    -- A nil font path is one of the few things that hard-errors a SetFont
    -- call, taking the whole cast bar build with it.
    local prev = mocks.__libs["LibSharedMedia-3.0"].Fetch
    mocks.__libs["LibSharedMedia-3.0"].Fetch = function() return nil end
    local path = Castbar.FetchFont("No Such Font")
    assertTrue(type(path) == "string" and #path > 0)
    mocks.__libs["LibSharedMedia-3.0"].Fetch = prev
end)

-- ── AutoSizeLong at real frame scales ───────────────────────────────────────

test("AutoSizeLong matches on-screen extents for frames at different scales", function()
    -- The published helper already has direct coverage; this drives it from
    -- the scales two REAL frames report, which is how the module calls it.
    local grid = mocks.CreateFrame("Frame")
    local bar  = mocks.CreateFrame("Frame")
    grid:SetSize(250, 40)
    grid:SetScale(0.6)
    bar:SetScale(1)
    local long = Castbar.AutoSizeLong(grid:GetWidth(), grid:GetEffectiveScale(),
                                      bar:GetEffectiveScale(), 99)
    assertEqual(long, 150)
end)

test("AutoSizeLong accounts for scale INHERITED from a parent frame", function()
    -- Effective scale is the product down the parent chain; a bar parented
    -- onto a scaled grid inherits that factor and must not double-apply it.
    local grid = mocks.CreateFrame("Frame")
    grid:SetScale(2)
    grid:SetSize(100, 20)
    local bar = mocks.CreateFrame("Frame", nil, grid)
    assertEqual(bar:GetEffectiveScale(), 2, "the bar inherits the grid's scale")
    assertEqual(Castbar.AutoSizeLong(grid:GetWidth(), grid:GetEffectiveScale(),
                                     bar:GetEffectiveScale(), 99), 100)
end)
