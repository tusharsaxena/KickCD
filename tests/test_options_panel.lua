-- tests/test_options_panel.lua
-- LibKa0s-Options-1.0 wiring, and the schema -> widget -> write loop.
--
-- Until this milestone the AceGUI mock handed back a bare frame, so SetCallback
-- was a no-op and NOT ONE widget callback in this addon was reachable. The read
-- -> write -> refresh path — the largest area of the addon by line count — had
-- never been exercised headlessly at all. That is why the adoption prompt gates
-- this module on a fireable widget mock, and it is what most of this file is.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil, assertNear, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertNil, T.assertNear, T.assertFalse
local NS = T.NS
local H  = NS.Settings.Helpers
local S  = NS.Settings.Store

-- ── the Blizzard canvas contract (Options minor 5) ──────────────────────────
--
-- The Settings window calls OnCommit on apply, OnRefresh on re-show, and
-- OnDefault from its own FOOTER control — a different widget from the header
-- Defaults button this addon builds, and not per-page. LibKa0s stamps all three
-- in CreatePanel as of minor 5, so every page this addon builds a canvas for
-- (settings/General.lua, Grid.lua and Spells.lua) gained a working footer
-- control without a line of their own changing. Nothing in this repo would
-- notice losing it again: the header Defaults button keeps working and looks
-- equivalent to the user.
--
-- RAWGET, not `type(panel.OnDefault)`. The frame mock synthesizes a no-op for
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
    local row = S.FindRow(path)
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
    for _, m in ipairs({ "SessionToggle", "SetAndRefresh", "ResetAll", "AddComposed",
                         "RenderUnitPanel", "PartitionUnitRows", "AnchorValues", "AnchorOrder",
                         "BuildMainContent", "SchemaForPanel", "FireConfigChanged",
                         "RegisterGridSection", "GridSection", "RenderGridPage" }) do
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
    assertNil(src:match('AceGUI:Create%("ColorPicker"%)'), "a color maker came back")
    assertNil(src:match("SnapToStep"), "step snapping is the library's now")
    assertNil(src:match("BUTTON_PAIR_REL%s*="), "a copied layout constant came back")
end)

-- ── page registration (one registry, every page, once each) ─────────────────

--- The pages, in the order the TOC loads settings/<page>.lua — which is the
--- order they call NS.RegisterOptionsPage in, and therefore the order the
--- library drains its queue in. It used to be spelled a second time in
--- NS.Settings.order.
local PAGE_KEYS  = { "general", "grid", "spells", "profiles" }
local PAGE_FILES = { "General", "Grid", "Spells", "Profiles" }

test("every page registers exactly once, through the library's registry", function()
    -- The acceptance criterion for KCD-R-03 / KCD-A-09 stated headlessly: the
    -- Blizzard options list gets ONE parent category and one subcategory per page.
    -- With the private registry in settings/Panel.lua still present alongside
    -- the library's, whichever one ran won and the other's guarantees applied to
    -- nothing; wiring the library forwarders WITHOUT deleting the private path
    -- would have registered both, and the user would see every page twice.
    -- red under: restoring NS.Settings.RegisterTab + RegisterPanel + the private
    -- bootstrap frame to settings/Panel.lua.
    local parents, subs = 0, 0
    local inst = T.load(true, true, function(mocks)
        local Stg = mocks.Settings
        local realParent = Stg.RegisterCanvasLayoutCategory
        local realSub    = Stg.RegisterCanvasLayoutSubcategory
        Stg.RegisterCanvasLayoutCategory =
            function(...) parents = parents + 1; return realParent(...) end
        Stg.RegisterCanvasLayoutSubcategory =
            function(...) subs = subs + 1; return realSub(...) end
    end)

    assertEqual(parents, 1, "exactly one parent category may be registered")
    assertEqual(subs, #PAGE_KEYS, "one Blizzard subcategory per page, no more")

    local seen = {}
    local built = inst.NS.Settings.Helpers.__pages()
    assertEqual(#built, #PAGE_KEYS, "the library must have built every page and no page twice")
    for i, page in ipairs(built) do
        assertEqual(page.key, PAGE_KEYS[i], "page " .. i .. " out of TOC order")
        assertNil(seen[page.key], "page registered twice: " .. tostring(page.key))
        seen[page.key] = true
    end
end)

test("no page file reaches a registry other than the library's", function()
    -- The other half of the same finding, pinned at the source so a new page
    -- cannot quietly reintroduce the private path. Panel.lua is checked for the
    -- registry itself; the page tails for how they enter it.
    -- red under: putting `NS.Settings.RegisterTab("general", Build)` back into
    -- settings/General.lua.
    local function read(rel)
        local fh = assert(io.open(T.root .. "/" .. rel, "r"))
        local src = fh:read("*a")
        fh:close()
        return src
    end

    local panel = read("settings/Panel.lua")
    assertNil(panel:match("function NS%.Settings%.RegisterTab"),
        "the private tab registry came back")
    assertNil(panel:match("Settings%.RegisterCanvasLayoutCategory%("),
        "a second parent-category registration came back")

    for i, key in ipairs(PAGE_KEYS) do
        local file = "settings/" .. PAGE_FILES[i] .. ".lua"
        local src  = read(file)
        assertTrue(src:find(('NS.RegisterOptionsPage("%s"'):format(key), 1, true) ~= nil,
            file .. " must register through the library forwarder")
        assertNil(src:match("NS%.Settings%.RegisterTab"), file .. " reaches the private registry")
    end
end)

-- ── schema -> widget ────────────────────────────────────────────────────────

test("a bool row renders a checkbox labeled from the row", function()
    local w, row = renderRow("locked")
    assertEqual(w.type, "CheckBox")
    assertEqual(w.labelText, row.label)
    -- EITHER KEY, because the library's tooltipBody() reads `row.tooltip or
    -- row.desc` and both are in the tree now: this addon's hand-written rows key
    -- it `desc`, the composed ones key it `tooltip`. What is not acceptable is
    -- NEITHER — an unmapped field is not an error, it is a tooltip that silently
    -- stops rendering.
    assertTrue((row.tooltip or row.desc) ~= nil, "the row must carry a tooltip body")
end)

test("every schema row in the addon carries a tooltip body under one key or the other",
function()
    -- The case above proves one row; this proves there is no row anywhere the
    -- library would render with an empty body.
    -- red under: dropping `desc` from any hand-written row
    local missing = {}
    for _, def in ipairs(NS.Settings.Schema) do
        if (def.tooltip or def.desc) == nil then missing[#missing + 1] = tostring(def.path) end
    end
    assertEqual(#missing, 0, "rows with no tooltip body: " .. table.concat(missing, ", "))
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
    assertEqual(w.order[1], "TOP_LEFT", "the anchor list must not alphabetize")
end)

test("a color row renders a picker with alpha and the decoded color", function()
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
    -- paths is two behaviors, and only one of them gets tested.
    local before = S.Get("locked")
    local w = renderRow("locked")
    w:__fire("OnValueChanged", not before)
    assertEqual(S.Get("locked"), not before, "the click must reach the profile")
    H.SetAndRefresh("locked", before)
end)

test("a checkbox write fires CONFIG_CHANGED with the row's section", function()
    -- The half a bare table write would silently skip: without the message the
    -- modules never repaint, so the setting "works" and nothing moves on screen.
    local seen
    local target = NS.NewBusTarget()
    target:RegisterMessage(T.NS.MSG.CONFIG_CHANGED, function(_, payload)
        seen = payload and payload.section
    end)
    local before = S.Get("locked")
    local w = renderRow("locked")
    w:__fire("OnValueChanged", not before)
    target:UnregisterMessage(T.NS.MSG.CONFIG_CHANGED)
    H.SetAndRefresh("locked", before)
    assertEqual(seen, S.FindRow("locked").section,
        "the panel write must publish the row's own section")
end)

test("dragging a slider commits on mouse-up", function()
    local path = "units.target.icons.primarySize"
    local before = S.Get(path)
    local w, row = renderRow(path)
    w:__fire("OnMouseUp", row.min + (row.step or 1))
    assertNear(S.Get(path), row.min + (row.step or 1), 1e-6)
    H.SetAndRefresh(path, before)
end)

test("choosing a dropdown option stores the option KEY, never its index", function()
    local path = "units.target.icons.anchor"
    local before = S.Get(path)
    local w, row = renderRow(path)
    local target = row.sorting[2]
    w:__fire("OnValueChanged", target)
    assertEqual(S.Get(path), target)
    H.SetAndRefresh(path, before)
end)

test("confirming a color stores the keyed shape the modules read", function()
    local path = "units.target.icons.borderColor"
    local before = S.Get(path)
    local w = renderRow(path)
    w:__fire("OnValueConfirmed", 0.25, 0.5, 0.75, 0.5)
    local stored = S.Get(path)
    assertNear(stored.r, 0.25, 1e-9)
    assertNear(stored.a, 0.5, 1e-9, "alpha must survive the picker")
    assertNil(stored[1], "colorEncode must produce the keyed shape")
    H.SetAndRefresh(path, before)
end)

-- ── the color drag throttle (KICKCD-R-04) ───────────────────────────────────
--
-- The descriptor's scheduleTimer backs the picker's 50 ms drag throttle. It
-- used to wrap C_Timer.After, which answers nil, and until LibKa0s v1.56.0
-- (OptionsWidgets minor 31) the library used that return value as its armed
-- flag -- so every ~60 Hz drag tick committed and fanned CONFIG_CHANGED out.

test("the descriptor's scheduleTimer answers a cancelable handle", function()
    -- red under: `return _G.C_Timer.After(delay, fn)` in settings/OptionsSetup.lua
    local ran = false
    local handle = NS.Settings.ScheduleTimer(function() ran = true end, 0.05)
    assertTrue(handle ~= nil, "scheduleTimer must hand back a handle, not nil")
    assertEqual(type(handle.Cancel), "function", "the handle must be cancelable")
    handle:Cancel()
    T.mocks.__flushTimers()
    assertFalse(ran, "a canceled handle must not fire")

    -- ...and it is the function the library actually calls: a drag tick
    -- queues a timer, and that queued entry is the cancelable handle.
    local w = renderRow("units.target.icons.borderColor")
    local before = #T.mocks.__timers
    w:__fire("OnValueChanged", 0.1, 0.2, 0.3, 1)
    local queued = T.mocks.__timers[before + 1]
    assertTrue(queued ~= nil, "a drag tick must schedule the throttle timer")
    assertEqual(type(queued.Cancel), "function",
        "the descriptor must route the throttle through ScheduleTimer")
    queued:Cancel()
end)

test("a color drag commits once per throttle window", function()
    -- Characterization: green behind v1.56.0's own armed flag, red under a
    -- pre-minor-31 payload paired with a nil-returning scheduleTimer.
    local path = "units.target.icons.borderColor"
    local before = S.Get(path)
    local w = renderRow(path)
    T.mocks.__flushTimers()
    local real, commits = H.SetAndRefresh, 0
    H.SetAndRefresh = function(p, ...)
        if p == path then commits = commits + 1 end
        return real(p, ...)
    end
    local ok, err = pcall(function()
        for i = 1, 10 do w:__fire("OnValueChanged", i / 10, 0.5, 0.5, 1) end
        assertEqual(commits, 0, "no drag tick may commit before the window closes")
        T.mocks.__flushTimers()
    end)
    H.SetAndRefresh = real
    assert(ok, err)
    assertEqual(commits, 1, "ten drag ticks inside one window must commit exactly once")
    assertNear(S.Get(path).r, 1.0, 1e-9, "the commit must carry the LAST drag value")
    H.SetAndRefresh(path, before)
end)

test("an external write re-syncs an open widget through its refresher", function()
    -- options-ui-§11: scalar widgets refresh IN PLACE via a per-widget updater
    -- closure. A refresh does not rebuild the page.
    local before = S.Get("locked")
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

-- ── the one host survivor ───────────────────────────────────────────────────
--
-- (InlinePair went with the bespoke Debug-console toggle it existed for: that
-- line is H.MasterControls' now and both halves are ordinary schema rows, which
-- the flow engine pairs by itself. A host widget maker with no caller is the
-- thing options-ui-§1 says must not sit in this addon.)

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

-- ── the Profiles page draws ─────────────────────────────────────────────────

test("the Profiles page SHOWS the container AceConfigDialog fills, even a pooled (hidden) one", function()
    -- AceGUI:Release hides a widget's frame before pooling it, and neither
    -- AceGUI:Create nor AceConfigDialog:Open shows it again. settings/Profiles.lua
    -- creates its SimpleGroup at build time, when AceGUI's pool is usually still
    -- empty -- but any addon or page that released a SimpleGroup first hands it
    -- a pooled, hidden one, AceConfigDialog fills that hidden frame, and the page
    -- reads as blank under its header. The Create wrap below hands out every
    -- SimpleGroup hidden, which is exactly the pooled case.
    --
    -- The harness's AceConfigDialog is a no-op lib, so Open is replaced with a
    -- recorder in the `mutate` hook, before any source loads.
    -- red under: the renderer not calling container.frame:Show().
    local opened = {}
    local inst = T.load(true, true, function(m)
        m.__libs["AceConfigDialog-3.0"].Open = function(_, app, container)
            opened[#opened + 1] = { app = app, container = container }
        end
        local AceGUI = m.__libs["AceGUI-3.0"]
        local create = AceGUI.Create
        AceGUI.Create = function(self, wtype)
            local w = create(self, wtype)
            if wtype == "SimpleGroup" then w.frame:Hide() end
            return w
        end
    end)

    local ctx = inst.NS.Settings.Helpers.__panelFor("profiles")
    assertTrue(ctx ~= nil, "the Profiles page registered")
    ctx.panel:Hide()
    ctx.panel:Show()
    assertEqual(#opened, 1, "the first show opens the AceDBOptions table once")
    assertEqual(opened[1].app, "KickCD-Profiles")
    local frame = opened[1].container and opened[1].container.frame
    assertTrue(frame ~= nil, "AceConfigDialog is handed an AceGUI container")
    assertTrue(frame:IsShown(), "the container AceConfigDialog fills is shown")
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

test("General's bespoke controls key their tooltip body `tooltip`, not `desc`", function()
    -- The library reads a SCHEMA row's body through tooltipBody(), which accepts
    -- either key. Its bespoke makers do NOT: O.SessionCheckbox reads
    -- `spec.tooltip` directly, so a spec that says `desc` renders the label with
    -- an EMPTY body -- silently, and only in game. ONE spec in
    -- settings/General.lua's builder is affected: "Use same styling as Target".
    -- The other three — the Debug console toggle and the two reset buttons — are
    -- H.MasterControls' (options-ui-§15), so their bodies are the composer's and
    -- are keyed correctly there by construction.
    --
    -- "Copy styling from Target" left this count when it moved onto the tick's
    -- line: it is no longer an InlineButtonPair spec but a button built by
    -- `copyStylingButton`, above Build, whose body goes to H.AttachTooltip
    -- POSITIONALLY -- a call that cannot key it wrongly. That it still HAS a body
    -- is asserted separately below, so the move cannot have quietly dropped it.
    --
    -- Scanned rather than driven because the failure is the absence of a
    -- tooltip line, which no widget mock can distinguish from a spec that
    -- deliberately has none. The builder is the whole region after `local
    -- function Build` -- every schema row on this page is declared above it, so
    -- a `desc` key below that line is always a bespoke spec.
    -- red under: reverting the key to `desc`, or dropping either body.
    local fh = assert(io.open(T.root .. "/settings/General.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    local at = src:find("local function Build", 1, true)
    assertTrue(at ~= nil, "settings/General.lua must still declare Build")
    local builder = src:sub(at)
    assertNil(builder:match("desc%s*="),
        "a bespoke spec in General's builder keys its tooltip `desc`; the library reads `tooltip` and draws no body")
    -- ...and the bodies are really there, so the rule above cannot be satisfied
    -- by deleting them instead.
    local n = 0
    for _ in builder:gmatch("tooltip%s*=") do n = n + 1 end
    assertEqual(n, 1, "General's builder must carry the surviving bespoke tooltip body")
    assertTrue(src:find("H.AttachTooltip(btn", 1, true) ~= nil,
        "the Copy styling button must still attach a tooltip body of its own")
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

test("every schema row the panel renders is labeled with prose, not with a key", function()
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
    -- EVERY file of the major, not just the shell, and the list is DERIVED from
    -- the vendored XML rather than typed (testing-§9). It was typed once --
    -- Options.lua, OptionsWidgets.lua, OptionsScroll.lua -- and the major grew
    -- two more files underneath it: OptionsCompose.lua, and OptionsTabs.lua at
    -- LibKa0s v1.39.0. A typed list does not redden when a file joins the major,
    -- it just stops covering it. OptionsWidgets.lua is still where the rendered
    -- labels come from, so an `L` hook growing there is the likeliest and the one
    -- that would show on screen first.
    local lib = T.mocks.LibStub("LibKa0s-Options-1.0", true)
    assertTrue(type(rawget(lib, "STRINGS")) == "table",
        "Options owning its own strings is why this tripwire is not shaped like "
        .. "the Core one in test_coresetup.lua — asserting lib.STRINGS is absent "
        .. "would fail here against a module behaving as designed")
    assertTrue(type(rawget(lib, "LAYOUT")) == "table",
        "and `local L = lib.LAYOUT` inside Options.lua is geometry, not a locale table")

    local scanned = 0
    for _, rel in ipairs(T.libFiles) do
        if rel:match("/Options[%w]*%.lua$") then
            local fh0 = assert(io.open(rel, "r"))
            local src0 = fh0:read("*a")
            fh0:close()
            assertNil(src0:match("d%.L%b()"), rel .. " now reads a descriptor L")
            assertNil(src0:match("d%.L[^%w_]"), rel .. " now reads a descriptor L")
            scanned = scanned + 1
        end
    end
    assertEqual(scanned, 10,
        "the major is ten files at LibKa0s v1.62.0 -- a count that moved means a file "
        .. "joined or left it, and this case is where that is noticed")

    -- ...and the descriptor this addon passes must not pretend otherwise.
    local fh2 = assert(io.open(T.root .. "/settings/OptionsSetup.lua", "r"))
    local src2 = fh2:read("*a")
    fh2:close()
    assertNil(src2:match("\n%s*L%s*="), "the Options descriptor grew an L the library never reads")
end)

-- ── the LSM30_Border fixup, promoted out of core/LSMPatch.lua ────────────────

test("the live wiring patches LSM30_Border through the library, not a private copy", function()
    -- AceGUI's WidgetRegistry is PROCESS-GLOBAL: one slot named "LSM30_Border"
    -- shared by every addon in the client. This addon and four siblings each
    -- carried the same wrapper in their own core/LSMPatch.lua, each registering
    -- at whatever version it found plus one, so a session running all five
    -- stacked five wrappers and the outermost belonged to whichever addon the
    -- loader reached last. No suite in any of the five could see that — each one
    -- loads a single copy, registers once and passes, which is exactly what this
    -- addon's own test_options_panel.lua did through the whole defect.
    --
    -- lib.__PatchLSM30Border (LibKa0s-Options-1.0 minor 15) is that wrapper
    -- published once, behind lib.__lsmBorderPatched. LibStub hands five vendored
    -- copies the same instance, so five callers make one registration.
    --
    -- WHY A FRESH INSTANCE WITH A SEEDED REGISTRY. The mock's WidgetRegistry
    -- starts empty, which models AGSMW being absent; the call then finds nothing
    -- to wrap, returns false without arming the sentinel, and proves nothing. The
    -- `mutate` hook runs BEFORE any source loads, which is the only window in
    -- which a stand-in constructor can be in the slot when settings/OptionsSetup
    -- .lua's live arm executes.
    -- red under: dropping the lib.__PatchLSM30Border() call from the live wiring.
    local upstream = function() return { frame = {} } end
    local inst = T.load(true, false, function(m)
        m.LibStub("AceGUI-3.0"):RegisterWidgetType("LSM30_Border", upstream, 20)
    end)

    local AceGUI = inst.mocks.LibStub("AceGUI-3.0")
    assertTrue(AceGUI.WidgetRegistry["LSM30_Border"] ~= upstream,
        "the live wiring never called lib.__PatchLSM30Border(): the slot still holds "
        .. "the constructor the registry was seeded with")
    assertEqual(AceGUI:GetWidgetVersion("LSM30_Border"), 21,
        "the wrapper must register one version above what it wrapped, to win the race")

    -- The sentinel is armed, so a sibling addon's copy of the library — the same
    -- instance, as far as LibStub is concerned — registers nothing on top.
    local lib = inst.mocks.LibStub("LibKa0s-Options-1.0")
    assertFalse(lib.__PatchLSM30Border(), "a second call must be a no-op")
    assertEqual(AceGUI:GetWidgetVersion("LSM30_Border"), 21,
        "and must leave the one registration alone")
end)

-- The Reset all settings tooltip names Profiles → Reset Profile.
--
-- options-ui-§12: the global reset IS a profile reset here (the descriptor
-- supplies resetProfile) and this addon ships a Profiles page, so the button's
-- tooltip SHOULD name the equivalence. The composer is the only writer of that
-- text; it picks the wording from the descriptor (LibKa0s-Options-1.0 minor 18),
-- and `profilesPage = true` is how the host says the page exists. Read the way
-- AttachTooltip shows it: the real button's OnEnter, GameTooltip:AddLine spied.
--
-- red under: dropping `profilesPage = true` from settings/OptionsSetup.lua.
local RESET_ALL_TIP = "Reset the current profile to its defaults \226\128\148 the same thing "
    .. "Profiles -> Reset Profile does. Your other profiles are not affected."

local function findButton(w, text, depth)
    depth = depth or 0
    if type(w) ~= "table" or depth > 8 then return nil end
    if w.text == text and w.callbacks then return w end
    for _, child in ipairs(w.children or {}) do
        local hit = findButton(child, text, depth + 1)
        if hit then return hit end
    end
    return nil
end

test("General's Reset all settings tooltip says it is the same act as Profiles -> Reset Profile", function()
    local inst = T.load(true, true)
    local iH = inst.NS.Settings.Helpers
    local ctx = iH.__panelFor("general")
    assertTrue(ctx ~= nil, "the General page must be registered")
    ctx.activeTab = iH.MASTER_GROUP
    ctx.panel:Show()
    iH.RefreshPanel(ctx, true)
    local btn = findButton(ctx.scroll, "Reset all settings")
    assertTrue(btn ~= nil, "the Master controls tab draws a Reset all settings button")
    assertTrue(btn.callbacks.OnEnter ~= nil, "the button carries a tooltip")

    local tip, lines = inst.mocks.GameTooltip, {}
    local saved = rawget(tip, "AddLine")
    rawset(tip, "AddLine", function(_, text) lines[#lines + 1] = text end)
    local ok, err = pcall(btn.callbacks.OnEnter)
    rawset(tip, "AddLine", saved)
    assertTrue(ok, tostring(err))
    assertEqual(#lines, 1, "one tooltip body line")
    assertEqual(lines[1], RESET_ALL_TIP)
end)

-- ── the reader, and the stored FALSE it must not fold away ──────────────────

test("the panel's schema reader hands back a stored FALSE as false, not nil", function()
    -- THE PIN FOR THIS FILE'S HALF of a fix that shipped in two files at once.
    -- Both host descriptors read a value as `H and H.Get and H.Get(path) or nil`,
    -- and the trailing `or nil` folds a stored false to nil. settings/Slash.lua's
    -- copy was loud — the library prints nil as the literal "nil", so `/kcd get`
    -- reported a value the addon does not hold — and tests/test_slash.lua pins
    -- that one. THIS copy was silent and would be silent still: every consumer of
    -- the descriptor's `get` inside libs/LibKa0s/OptionsWidgets.lua folds the
    -- answer to a boolean before anything can observe it (`read(row) and true or
    -- false` for a checkbox, a truthiness test for `disabledIf`), so false and
    -- nil draw the same tick and no input through the panel can tell them apart.
    -- That is exactly how one wrong spelling came to live in two files, and why
    -- one case is not enough.
    --
    -- Called on the NAMED reader, which settings/OptionsSetup.lua hands to the
    -- descriptor by reference, so this is the function the panel actually reads
    -- through rather than a parallel copy of it.
    -- red under: restoring `H and H.Get and H.Get(path) or nil` in OptionsSetup.lua
    local read = NS.Settings.ReadForPanel
    assertEqual(type(read), "function", "the reader must be published to be pinnable")
    local before = S.Get("locked")
    H.SetAndRefresh("locked", false)
    local v = read("locked")
    H.SetAndRefresh("locked", before)
    assertTrue(v ~= nil, "a stored false must not read back as nil")
    assertEqual(v, false, "and it must be the boolean false, not a coerced truthy value")
end)
