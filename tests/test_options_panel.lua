-- tests/test_options_panel.lua
-- LibKa0s-Options-1.0 wiring, and the schema -> widget -> write loop.
--
-- Until this milestone the AceGUI mock handed back a bare frame, so SetCallback
-- was a no-op and NOT ONE widget callback in this addon was reachable. The read
-- -> write -> refresh path — the largest area of the addon by line count — had
-- never been exercised headlessly at all. That is why the adoption prompt gates
-- this module on a fireable widget mock, and it is what most of this file is.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil, assertNear =
    T.test, T.assertEqual, T.assertTrue, T.assertNil, T.assertNear
local NS = T.NS
local H  = NS.Settings.Helpers

-- ── the Blizzard canvas contract (Options minor 5) ──────────────────────────
--
-- The Settings window calls OnCommit on apply, OnRefresh on re-show, and
-- OnDefault from its own FOOTER control — a different widget from the header
-- Defaults button this addon builds, and not per-page. LibKa0s stamps all three
-- in CreatePanel as of minor 5, so all five of this addon's pages
-- (settings/General.lua:129, Icons.lua:393, Castbar.lua:537, Label.lua:178,
-- Spells.lua:941) gained a working footer control without a line of their own
-- changing. Nothing in this repo would notice losing it again: the header
-- Defaults button keeps working and looks equivalent to the user.
--
-- RAWGET, not `type(panel.OnDefault)`. The frame mock synthesises a no-op for
-- any PascalCase key, so the type check is true whether or not anything set it.

test("the canvas frame carries OnCommit, OnDefault and OnRefresh from the library", function()
    local ctx = H.CreatePanel("KickCDCanvasPanel1", "Canvas 1", { defaultsButton = true })
    assertEqual(type(rawget(ctx.panel, "OnCommit")),  "function", "OnCommit")
    assertEqual(type(rawget(ctx.panel, "OnDefault")), "function", "OnDefault")
    assertEqual(type(rawget(ctx.panel, "OnRefresh")), "function", "OnRefresh")
end)

test("OnDefault reaches a defaultsOnClick parked AFTER the panel is built", function()
    -- Every page here parks its handler after CreatePanel returns, because the
    -- button does not exist until first OnShow. A re-vendor that turned the
    -- library's forwarder back into an assignment would capture nil on all five
    -- pages at once, and only the footer control would show it — in game.
    local ctx = H.CreatePanel("KickCDCanvasPanel2", "Canvas 2", { defaultsButton = true })
    local ran = 0
    ctx.panel.defaultsOnClick = function() ran = ran + 1 end
    rawget(ctx.panel, "OnDefault")()
    assertEqual(ran, 1, "the footer control must reach the page's parked defaults action")
end)

test("a page that parks no defaults action still has a callable, inert OnDefault", function()
    local ctx = H.CreatePanel("KickCDCanvasPanel3", "Canvas 3", {})
    assertNil(rawget(ctx.panel, "defaultsOnClick"))
    rawget(ctx.panel, "OnDefault")()   -- must not raise
end)

local panelSeq = 0
--- Render one schema row into a throwaway ctx and hand back the widget, so a
--- case can drive it the way a click would.
local function renderRow(path)
    panelSeq = panelSeq + 1
    local ctx = H.CreatePanel("KickCDTestPanel" .. panelSeq, "T", { pageKey = "test" })
    local row = H.FindSchema(path)
    assertTrue(row ~= nil, "no schema row at " .. path)
    local widget = H.RenderField(ctx, row, nil, 0.5)
    assertTrue(widget ~= nil, "RenderField returned nothing for " .. path)
    return widget, row, ctx
end

-- ── the instance ────────────────────────────────────────────────────────────

test("NS.Settings.Helpers IS the library instance, decorated in place", function()
    -- options-ui-§1. A host page helper added later has to call
    -- Helpers.RenderRows like any other page does, and a suite that swaps a
    -- member out to spy on it must be swapping the one the library's own callers
    -- see. A copy-across gives the test a member nobody calls.
    for _, m in ipairs({ "RenderField", "RenderRows", "RenderSchema", "CreatePanel",
                         "EnsureScroll", "ClearScroll", "Section", "AddSpacer",
                         "AttachTooltip", "InlineButtonPair", "SessionCheckbox",
                         "RefreshAllPanels", "RestoreDefaults", "RestoreAllDefaults",
                         "PatchAlwaysShowScrollbar", "__panels", "__panelFor" }) do
        assertEqual(type(H[m]), "function", "library member missing: " .. m)
    end
    -- ...and the host's own decorations sit on the SAME table.
    for _, m in ipairs({ "InlinePair", "SessionToggle", "SetAndRefresh", "ResetAll",
                         "RenderUnitPanel", "PartitionUnitRows", "ResetAllPositions",
                         "RestoreUnitLinks", "AnchorValues", "AnchorOrder",
                         "BuildMainContent", "ValidateSchema", "SchemaForPanel" }) do
        assertEqual(type(H[m]), "function", "host decoration missing: " .. m)
    end
end)

test("the host ships no widget maker, flow engine or layout constant of its own", function()
    -- red under: restoring makeCheckbox to settings/Panel_Widgets.lua
    -- anti-patterns #47, and options-ui-§8 on the constants: a host copy of a
    -- library constant is the copy that goes stale.
    local fh = assert(io.open(T.root .. "/settings/Panel_Widgets.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match('AceGUI:Create%("CheckBox"%)'), "a checkbox maker came back")
    assertNil(src:match('AceGUI:Create%("Slider"%)'), "a slider maker came back")
    assertNil(src:match('AceGUI:Create%("ColorPicker"%)'), "a colour maker came back")
    assertNil(src:match("SnapToStep"), "step snapping is the library's now")
    assertNil(src:match("BUTTON_PAIR_REL%s*="), "a copied layout constant came back")
end)

-- ── schema -> widget ────────────────────────────────────────────────────────

test("a bool row renders a checkbox labelled from the row", function()
    local w, row = renderRow("locked")
    assertEqual(w.type, "CheckBox")
    assertEqual(w.labelText, row.label)
    -- `desc`, not `tooltip`: the library's makers read desc, which is why all 98
    -- rows were renamed. An unmapped field is not an error — it is a tooltip
    -- that silently stops rendering.
    assertTrue(row.desc ~= nil, "the row must carry a desc for the tooltip")
end)

test("a number row renders a slider carrying the row's range", function()
    local w, row = renderRow("units.target.icons.primarySize")
    assertEqual(w.type, "Slider")
    assertEqual(w.min, row.min)
    assertEqual(w.max, row.max)
end)

test("a string row renders a dropdown listing the KEYED options in declared order", function()
    -- The dropdown migration's whole point. Under the old array-of-records shape
    -- the library's maker would have handed SetList a list keyed by INDEX, so
    -- the panel would have offered "1, 2, 3 ..." — silently, and only in game.
    local w, row = renderRow("units.target.icons.anchor")
    assertEqual(w.type, "Dropdown")
    assertEqual(type(w.list), "table", "SetList must have received the values hash")
    for k, v in pairs(w.list) do
        assertEqual(type(k), "string", "values must be keyed by option token")
        assertEqual(type(v), "string")
    end
    assertEqual(type(w.order), "table", "the declared order must reach SetList")
    assertEqual(w.order[1], row.sorting[1], "and must be the row's own sorting")
    assertEqual(w.order[1], "TOP_LEFT", "the anchor list must not alphabetise")
end)

test("a colour row renders a picker with alpha and the decoded colour", function()
    local w = renderRow("units.target.icons.borderColor")
    assertEqual(w.type, "ColorPicker")
    assertEqual(w.hasAlpha, true, "hasAlpha is row-driven now and must be declared")
    assertEqual(type(w.color), "table")
    assertEqual(type(w.color.r), "number", "colorDecode must have run")
end)

-- ── widget -> write ─────────────────────────────────────────────────────────

test("ticking a checkbox writes through the addon's single write seam", function()
    -- red under: pointing the descriptor's `set` at a bare table write
    --
    -- SetAndRefresh is what fires CONFIG_CHANGED with the row's section and runs
    -- the row's onChange — the same path `/kcd set locked true` takes. Two write
    -- paths is two behaviours, and only one of them gets tested.
    local before = H.Get("locked")
    local w = renderRow("locked")
    w:__fire("OnValueChanged", not before)
    assertEqual(H.Get("locked"), not before, "the click must reach the profile")
    H.SetAndRefresh("locked", before)
end)

test("a checkbox write fires CONFIG_CHANGED with the row's section", function()
    -- The half a bare table write would silently skip: without the message the
    -- modules never repaint, so the setting "works" and nothing moves on screen.
    local seen
    local target = NS.NewBusTarget()
    target:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED", function(_, payload)
        seen = payload and payload.section
    end)
    local before = H.Get("locked")
    local w = renderRow("locked")
    w:__fire("OnValueChanged", not before)
    target:UnregisterMessage("Ka0s_KickCD_CONFIG_CHANGED")
    H.SetAndRefresh("locked", before)
    assertEqual(seen, H.FindSchema("locked").section,
        "the panel write must publish the row's own section")
end)

test("dragging a slider commits on mouse-up", function()
    local path = "units.target.icons.primarySize"
    local before = H.Get(path)
    local w, row = renderRow(path)
    w:__fire("OnMouseUp", row.min + (row.step or 1))
    assertNear(H.Get(path), row.min + (row.step or 1), 1e-6)
    H.SetAndRefresh(path, before)
end)

test("choosing a dropdown option stores the option KEY, never its index", function()
    local path = "units.target.icons.anchor"
    local before = H.Get(path)
    local w, row = renderRow(path)
    local target = row.sorting[2]
    w:__fire("OnValueChanged", target)
    assertEqual(H.Get(path), target)
    H.SetAndRefresh(path, before)
end)

test("confirming a colour stores the keyed shape the modules read", function()
    local path = "units.target.icons.borderColor"
    local before = H.Get(path)
    local w = renderRow(path)
    w:__fire("OnValueConfirmed", 0.25, 0.5, 0.75, 0.5)
    local stored = H.Get(path)
    assertNear(stored.r, 0.25, 1e-9)
    assertNear(stored.a, 0.5, 1e-9, "alpha must survive the picker")
    assertNil(stored[1], "colorEncode must produce the keyed shape")
    H.SetAndRefresh(path, before)
end)

test("an external write re-syncs an open widget through its refresher", function()
    -- options-ui-§11: scalar widgets refresh IN PLACE via a per-widget updater
    -- closure. A refresh does not rebuild the page.
    local before = H.Get("locked")
    local w, _, ctx = renderRow("locked")
    H.SetAndRefresh("locked", not before)
    for _, fn in ipairs(ctx.refreshers) do pcall(fn) end
    assertEqual(w.value, not before, "the widget must have re-read the new value")
    H.SetAndRefresh("locked", before)
end)

test("releasing a page's widgets drops that page's refreshers", function()
    -- options-ui-§11: keep them and every later write pcalls an ever-growing
    -- pile of dead closures capturing released widgets.
    local _, _, ctx = renderRow("locked")
    assertTrue(#ctx.refreshers > 0, "rendering must register a refresher")
    H.ClearScroll(ctx)
    assertEqual(#ctx.refreshers, 0, "ClearScroll must reset the refresher list")
end)

-- ── the two host survivors ──────────────────────────────────────────────────

test("InlinePair puts both caller-supplied widgets in ONE row", function()
    panelSeq = panelSeq + 1
    local ctx = H.CreatePanel("KickCDTestPanelIP" .. panelSeq, "T", { pageKey = "test" })
    local left, right
    local row = H.InlinePair(ctx,
        function(c, r) left  = H.RenderField(c, H.FindSchema("locked"), r, 0.5) end,
        function(c, r) right = H.RenderField(c, H.FindSchema("scale"), r, 0.5) end)
    assertTrue(row ~= nil, "InlinePair must return its row")
    assertTrue(left ~= nil and right ~= nil, "both halves must render")
    assertEqual(#row.children, 2, "both must land in the SAME row")
end)

test("SessionToggle adapts this addon's argument order onto the library's", function()
    -- Host order (ctx, spec, parent, relativeWidth) -> library order
    -- (ctx, parent, relWidth, spec). Getting it wrong hands the library a spec
    -- where it expects a parent, and fails on a page the user opens rather than
    -- in the suite.
    -- red under: swapping the two arguments in Helpers.SessionToggle
    panelSeq = panelSeq + 1
    local ctx = H.CreatePanel("KickCDTestPanelST" .. panelSeq, "T", { pageKey = "test" })
    local flipped
    local cb = H.SessionToggle(ctx, {
        label = "Debug console",
        get   = function() return false end,
        set   = function(v) flipped = v end,
    })
    assertEqual(cb.type, "CheckBox")
    assertEqual(cb.labelText, "Debug console")
    cb:__fire("OnValueChanged", true)
    assertEqual(flipped, true, "the session setter must have been called")
end)

test("a session toggle never becomes a saved setting", function()
    -- It is runtime-only state (the console's visibility). Through a schema path
    -- it would persist, which is exactly what it must not do.
    panelSeq = panelSeq + 1
    local ctx = H.CreatePanel("KickCDTestPanelST2" .. panelSeq, "T", { pageKey = "test" })
    local schemaBefore = #NS.Settings.Schema
    local cb = H.SessionToggle(ctx, {
        label = "Debug console",
        get   = function() return false end,
        set   = function() end,
    })
    cb:__fire("OnValueChanged", true)
    assertEqual(#NS.Settings.Schema, schemaBefore, "no schema row may appear")
end)

-- ── reset ───────────────────────────────────────────────────────────────────

test("the Profiles page is vetoed from a global reset", function()
    -- options-ui-§3: Profiles rows are AceDBOptions-supplied and resetting them
    -- deletes user data, which is not what "restore defaults" means to anyone.
    local fh = assert(io.open(T.root .. "/settings/OptionsSetup.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertTrue(src:find('row.panel == "profiles"', 1, true) ~= nil,
        "the veto must be declared once and shared with the stub")
end)

test("a global reset also clears the state no schema row owns", function()
    -- Anchors, the per-unit `link` flag and the spell lists are not schema rows,
    -- so applyDefault never reaches them. afterRestoreAll is how the library's
    -- RestoreAllDefaults gets there — and it runs BEFORE the refresh, or the
    -- panel would paint the pre-hook values.
    local inst = T.load(true, true)
    local H2 = inst.NS.Settings.Helpers
    inst.NS.db.profile.units.target.anchors.icons =
        { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 999, y = 999 }
    H2.RestoreAllDefaults()
    local a = inst.NS.db.profile.units.target.anchors.icons
    assertTrue(a.x ~= 999, "afterRestoreAll must have cleared the dragged position")
end)

-- ── the degraded path ───────────────────────────────────────────────────────

test("with LibKa0s absent the schema still loads COMPLETE", function()
    -- THE case options-ui-§1's degradation rule exists for, and the reason this
    -- stub is load-completing rather than member-answering: page files call
    -- Helpers.LSMValues and Helpers.AnchorValues inside schema-row literals AT
    -- FILE LOAD. With either nil the page file raises, its rows never register,
    -- and `/kcd list`, `get`, `set`, `reset` and the profile defaults all break
    -- with it — silently.
    -- red under: deleting Helpers.LSMValues or Helpers.AnchorValues from the stub
    local full     = T.load(true)
    local degraded = T.load(true, false, nil, { libFiles = {} })
    assertNil(degraded.mocks.LibStub("LibKa0s-Options-1.0", true),
        "sanity: the degraded load must not have the major")
    assertEqual(#degraded.NS.Settings.Schema, #full.NS.Settings.Schema,
        "the degraded load must register EVERY schema row")
end)

test("the degraded stub keeps the global reset real", function()
    -- options-ui-§1: a user whose panel will not open is exactly the user who
    -- needs "reset everything", and the schema loaded fine, so it still works.
    local inst = T.load(true, false, nil, { libFiles = {} })
    local H2 = inst.NS.Settings.Helpers
    assertEqual(type(H2.RestoreAllDefaults), "function")
    inst.NS.Settings.Helpers.SetAndRefresh("locked", true)
    H2.RestoreAllDefaults()
    assertEqual(H2.Get("locked"), inst.NS.Settings.Helpers.FindSchema("locked").default,
        "the reset must still reach the profile with no panel at all")
end)

test("the degraded stub opens no panel and says so once", function()
    local inst = T.load(true, false, nil, { libFiles = {} })
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    inst.NS.OpenOptionsPanel()
    frame.AddMessage = orig
    assertTrue(#lines > 0 and table.concat(lines, "\n"):find("LibKa0s", 1, true) ~= nil,
        "the stub must name the missing library")
end)

test("the degraded stub carries no widget maker or layout constant", function()
    -- options-ui-§1 is explicit: MUST NOT carry a copy of a widget maker, the
    -- flow engine, the header, or any of the library's layout constants.
    local fh = assert(io.open(T.root .. "/settings/OptionsSetup.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match('AceGUI:Create'), "the stub reaches for AceGUI")
    assertNil(src:match("ROW_VSPACER%s*="), "the stub copies a layout constant")
    assertNil(src:match("0%.492"), "the stub copies BUTTON_PAIR_REL")
end)

-- ── the L trap ──────────────────────────────────────────────────────────────
--
-- Options is the odd major of the five: libs/LibKa0s/Options.lua declares a
-- lib.STRINGS table but NEVER reads `d.L` — grep it — so the descriptor in
-- settings/OptionsSetup.lua has no locale hook to hand NS.L to, and the classic
-- `L = NS.L` mistake is not expressible here at all.
--
-- What IS expressible is the same failure by the other route, and it is the one
-- a user of THIS addon would actually hit: every label and tooltip the panel
-- renders comes from NS.L, whose metatable answers an unknown key WITH THE KEY
-- (locales/enUS.lua:15). One `L["ENABLE_KICKCD"]` typo in a schema file and the
-- panel renders that key, silently, in game only. So the assertion is on the
-- string the library actually pushed into the widget — `w.labelText`, set by
-- the library's own maker via SetLabel — reached through a real render.

test("every schema row the panel renders is labelled with prose, not with a key", function()
    -- red under: changing any schema `label` to a key NS.L does not hold,
    -- e.g. settings/General.lua's `label = L["Enable KickCD"]` ->
    -- `label = L["ENABLE_KICKCD"]`
    local rendered, keyish = 0, {}
    for _, row in ipairs(NS.Settings.Schema) do
        if not row.skipRender then
            local w = select(1, renderRow(row.path))
            assertTrue(w ~= nil, "no widget for " .. row.path)
            local label = w.labelText
            assertEqual(type(label), "string",
                row.path .. " reached the widget with no label at all")
            rendered = rendered + 1
            -- SCREAMING_SNAKE, which no English label in this addon ever is.
            if label:match("^[A-Z][A-Z0-9]*_[A-Z0-9_]*$") then
                keyish[#keyish + 1] = row.path .. " -> " .. label
            end
            -- The tooltip goes the same way and is the same locale table.
            if row.desc ~= nil then
                assertEqual(type(row.desc), "string", row.path .. " has a non-string desc")
                if row.desc:match("^[A-Z][A-Z0-9]*_[A-Z0-9_]*$") then
                    keyish[#keyish + 1] = row.path .. ".desc -> " .. row.desc
                end
            end
        end
    end
    -- No `if rendered > 0 then` guard anywhere above: a sweep that renders
    -- nothing must fail loudly rather than pass vacuously.
    assertTrue(rendered > 20,
        "only " .. rendered .. " rows rendered; the sweep is not reaching the schema")
    assertEqual(#keyish, 0, "rows rendered raw keys: " .. table.concat(keyish, ", "))
end)

test("the panel's group and section headings are prose too", function()
    -- The other half of what a user reads on a page: the group headers the
    -- library's Section() renders, which are also NS.L lookups.
    -- red under: `group = L["MASTER_CONTROLS"]` in settings/General.lua
    local seen = 0
    for _, row in ipairs(NS.Settings.Schema) do
        if row.group ~= nil then
            assertEqual(type(row.group), "string", row.path .. " has a non-string group")
            seen = seen + 1
            assertNil(row.group:match("^[A-Z][A-Z0-9]*_[A-Z0-9_]*$"),
                row.path .. " sits under a raw-key heading: " .. row.group)
        end
    end
    assertTrue(seen > 10, "only " .. seen .. " grouped rows found; the sweep proved nothing")
end)

test("libs/LibKa0s/Options.lua takes no locale override, so none can be mis-passed", function()
    -- Pins the reason the pair above is shaped the way it is. If a future
    -- Options minor grows a `d.L` hook, this case reddens and whoever bumps the
    -- minor has to write the same fall-through assertion Slash, DebugLog and
    -- Perf carry — rather than quietly inheriting a trap.
    -- red under: adding `local strings = type(d.L) == "table" and d.L or nil`
    -- to libs/LibKa0s/Options.lua
    --
    -- All THREE files of the major, not just the shell. OptionsWidgets.lua is
    -- where the rendered labels actually come from, so an `L` hook growing there
    -- is the more likely of the two and the one that would show on screen first.
    local lib = T.mocks.LibStub("LibKa0s-Options-1.0", true)
    assertTrue(type(rawget(lib, "STRINGS")) == "table",
        "Options owning its own strings is why this tripwire is not shaped like "
        .. "the Core one in test_coresetup.lua — asserting lib.STRINGS is absent "
        .. "would fail here against a module behaving as designed")
    assertTrue(type(rawget(lib, "LAYOUT")) == "table",
        "and `local L = lib.LAYOUT` inside Options.lua is geometry, not a locale table")

    for _, rel in ipairs({ "Options.lua", "OptionsWidgets.lua", "OptionsScroll.lua" }) do
        local fh0 = assert(io.open(T.root .. "/libs/LibKa0s/" .. rel, "r"))
        local src0 = fh0:read("*a")
        fh0:close()
        assertNil(src0:match("d%.L%b()"), rel .. " now reads a descriptor L")
        assertNil(src0:match("d%.L[^%w_]"), rel .. " now reads a descriptor L")
    end

    local fh = assert(io.open(T.root .. "/libs/LibKa0s/Options.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    -- ...and the descriptor this addon passes must not pretend otherwise.
    local fh2 = assert(io.open(T.root .. "/settings/OptionsSetup.lua", "r"))
    local src2 = fh2:read("*a")
    fh2:close()
    assertNil(src2:match("\n%s*L%s*="), "the Options descriptor grew an L the library never reads")
end)
