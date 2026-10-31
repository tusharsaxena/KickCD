-- tests/test_switched_sections.lua — sections a selector does not pick (options-ui-§22, LibKa0s#67).
--
-- Two groups of rows belong to a dropdown: each glow style's knobs on Icons -> Ready glow, picked by
-- the two style dropdowns, and the anchor rows on Cast bar -> Size and position, picked by Anchor
-- mode. Each case drives the real dropdown through a real render on a page with a renderer, and
-- reads what the scroll draws: the group goes, heading included, and comes back on the next frame.
-- A column inside a shown group keeps `disabledIf` (§22, "Hidden is not disabled").
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

--- A shown page of the Units entry `page` for Target, open on `tab`.
local function shownPage(page, tab)
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    H.SetViewedUnit("target")
    local ctx = H.CreatePanel("KickCDSwitch" .. page, page, { pageKey = page })
    ctx.scroll = inst.mocks.LibStub("AceGUI-3.0"):Create("ScrollFrame")
    ctx.activeTab = inst.NS.L[tab]
    H.SetRenderer(ctx, function(c) H.RenderUnitPanel(c, page) end)
    ctx.panel:Show()
    H.RefreshPanel(ctx, true)
    return inst, ctx
end

--- Every widget under `w`, depth first.
local function walk(w, out)
    for _, child in ipairs(w.children or {}) do
        out[#out + 1] = child
        walk(child, out)
    end
    return out
end

--- The widget labeled `label` in the page's scroll, or nil.
local function drawn(inst, ctx, label)
    for _, w in ipairs(walk(ctx.scroll, {})) do
        if w.labelText == inst.NS.L[label] or w.text == inst.NS.L[label] then return w end
    end
end

--- Move a dropdown the way a click does, then run the next frame.
local function pick(inst, ctx, label, value)
    local dd = drawn(inst, ctx, label)
    assertTrue(dd ~= nil, label .. " must be drawn")
    dd:__fire("OnValueChanged", value)
    inst.mocks.__flushTimers()
end

test("Ready glow draws only the styles a dropdown picks, and a hidden one comes back", function()
    -- red under: a knob row carrying disabledIf alone, drawn dimmed for a style nobody chose
    local inst, ctx = shownPage("icons", "Ready glow")
    local S = inst.NS.Settings.Store
    S.Set("units.target.icons.primaryGlowTrigger", "always")
    S.Set("units.target.icons.primaryGlowType", "pixel")
    S.Set("units.target.icons.secondaryGlowType", "pixel")
    inst.NS.Settings.Helpers.RefreshPanel(ctx, true)
    assertTrue(drawn(inst, ctx, "Primary lines") ~= nil, "both pick Pixel border: drawn")
    assertTrue(drawn(inst, ctx, "Pixel border") ~= nil, "with its heading")
    assertTrue(drawn(inst, ctx, "Primary X offset (px)") ~= nil, "Offset belongs to Pixel border too")
    assertFalse(drawn(inst, ctx, "Primary particles") ~= nil, "nobody picks Auto cast sparkles")
    assertFalse(drawn(inst, ctx, "Auto cast sparkles") ~= nil, "its heading goes with it")
    assertFalse(drawn(inst, ctx, "Primary duration (seconds)") ~= nil, "nobody picks Proc")

    -- red under: the single form on one slot's dropdown alone
    pick(inst, ctx, "Secondary glow style", "autocast")
    assertTrue(drawn(inst, ctx, "Primary particles") ~= nil, "the secondary dropdown picks it: back")
    assertTrue(drawn(inst, ctx, "Primary lines") ~= nil, "two styles picked, both drawn")

    pick(inst, ctx, "Primary glow style", "button")
    assertFalse(drawn(inst, ctx, "Primary lines") ~= nil, "no dropdown picks Pixel border now")
    assertTrue(drawn(inst, ctx, "Primary X offset (px)") ~= nil, "auto cast still holds Offset")

    pick(inst, ctx, "Secondary glow style", "button")
    assertFalse(drawn(inst, ctx, "Primary X offset (px)") ~= nil, "Button uses no offset")
    assertTrue(drawn(inst, ctx, "Primary frequency") ~= nil, "both on Button: its group once")
end)

test("a column inside a shown glow group keeps dimming, and Never keeps its picked group", function()
    -- red under: moving the column to shownWhen, or hiding a group because its feature is off
    local inst = T.load(true, true)
    local Store, H = inst.NS.Settings.Store, inst.NS.Settings.Helpers
    local P = "units.target.icons."
    local rows = {}
    for _, def in ipairs(H.SchemaForPanel("icons", "target")) do rows[def.path] = def end
    Store.Set(P .. "primaryGlowTrigger", "always")
    Store.Set(P .. "secondaryGlowTrigger", "always")
    Store.Set(P .. "primaryGlowType", "pixel")
    Store.Set(P .. "secondaryGlowType", "autocast")
    assertTrue(rows[P .. "secondaryGlowPixelLines"].disabledIf() and true or false,
        "Pixel border is shown for the primary, and its secondary column dims")
    assertFalse(rows[P .. "primaryGlowPixelLines"].disabledIf() and true or false, "its primary is live")

    local again, ctx = shownPage("icons", "Ready glow")
    again.NS.Settings.Store.Set(P .. "primaryGlowTrigger", "never")
    again.NS.Settings.Store.Set(P .. "secondaryGlowTrigger", "never")
    again.NS.Settings.Helpers.RefreshPanel(ctx, true)
    assertTrue(drawn(again, ctx, "Primary lines") ~= nil, "Hidden is not disabled: the picked style stays")
end)

test("Anchor mode draws the anchor rows only while the bar is anchored", function()
    -- red under: the anchor rows always drawn, which do nothing under Free
    local inst, ctx = shownPage("castbar", "Size and position")
    assertTrue(drawn(inst, ctx, "Anchor on primary icon") ~= nil, "Anchored, the shipped mode: drawn")
    pick(inst, ctx, "Anchor mode", "FREE")
    assertFalse(drawn(inst, ctx, "Anchor on primary icon") ~= nil, "Free uses no anchor point")
    assertFalse(drawn(inst, ctx, "Anchor on cast bar") ~= nil, "nor the bar's")
    assertFalse(drawn(inst, ctx, "Y offset (px)") ~= nil, "nor the offsets")
    assertTrue(drawn(inst, ctx, "Anchor mode") ~= nil, "the selector itself stays")
    pick(inst, ctx, "Anchor mode", "PRIMARY")
    assertTrue(drawn(inst, ctx, "Anchor on cast bar") ~= nil, "and they come back")
end)

test("a switched row stays reachable while hidden", function()
    -- red under: filtering the schema rather than the render (options-ui-§6)
    local inst = T.load(true, true)
    local Store = inst.NS.Settings.Store
    Store.Set("units.target.castbar.anchorMode", "FREE")
    assertTrue(Store.FindRow("units.target.castbar.anchorPoint") ~= nil, "the row stays in the schema")
    Store.Set("units.target.castbar.anchorOffsetX", 7)
    assertEqual(Store.Get("units.target.castbar.anchorOffsetX"), 7, "and a write still lands")
end)
