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
    for _, m in ipairs({ "SessionToggle", "SetAndRefresh", "ResetAll", "AddComposed",
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
    assertNil(src:match('AceGUI:Create%("ColorPicker"%)'), "a color maker came back")
    assertNil(src:match("SnapToStep"), "step snapping is the library's now")
    assertNil(src:match("BUTTON_PAIR_REL%s*="), "a copied layout constant came back")
end)

-- ── page registration (one registry, six pages, once each) ──────────────────

--- The six pages, in the order the TOC loads settings/<page>.lua — which is the
--- order they call NS.RegisterOptionsPage in, and therefore the order the
--- library drains its queue in. It used to be spelled a second time in
--- NS.Settings.order.
local PAGE_KEYS  = { "general", "icons", "castbar", "label", "spells", "profiles" }
local PAGE_FILES = { "General", "Icons", "Castbar", "Label", "Spells", "Profiles" }

test("every page registers exactly once, through the library's registry", function()
    -- The acceptance criterion for KCD-R-03 / KCD-A-09 stated headlessly: the
    -- Blizzard options list gets ONE parent category and SIX subcategories.
    -- With the private registry in settings/Panel.lua still present alongside
    -- the library's, whichever one ran won and the other's guarantees applied to
    -- nothing; wiring the library forwarders WITHOUT deleting the private path
    -- would have registered both, and the user would see every page twice.
    -- red under: restoring NS.Settings.RegisterTab + RegisterPanel + the private
    -- bootstrap frame to settings/Panel.lua.
    local parents, subs = 0, 0
    local inst = T.load(true, true, function(mocks)
        local S = mocks.Settings
        local realParent = S.RegisterCanvasLayoutCategory
        local realSub    = S.RegisterCanvasLayoutSubcategory
        S.RegisterCanvasLayoutCategory =
            function(...) parents = parents + 1; return realParent(...) end
        S.RegisterCanvasLayoutSubcategory =
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
    -- registry itself; the six page tails for how they enter it.
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

test("confirming a color stores the keyed shape the modules read", function()
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

test("with LibKa0s absent the schema loads complete BAR the composed blocks", function()
    -- THE case options-ui-§1's degradation rule exists for, and the reason this
    -- stub is load-completing rather than member-answering: page files call
    -- Helpers.LSMValues, Helpers.AnchorValues AND the five schema composers
    -- inside schema-row literals AT FILE LOAD. With any of them nil the page
    -- file raises, its rows never register, and `/kcd list`, `get`, `set`,
    -- `reset` and the profile defaults all break with it — silently.
    --
    -- WHAT CHANGED, AND WHY IT IS NOT A WEAKENING. This used to assert the two
    -- row counts were EQUAL, which they were while the host declared 100% of its
    -- rows by hand. The canonical font / border / bar / color-pair /
    -- master-controls blocks live in libs/LibKa0s/OptionsCompose.lua now
    -- (options-ui-§16, §17), and a host copy of them in the stub is precisely
    -- the drift the composers were extracted to end (anti-pattern #73) — the
    -- same argument options-ui-§1 already makes against copying a widget maker
    -- or a layout constant into this stub. So the stub's composers are hollow,
    -- and the degraded schema is short by EXACTLY the composed rows.
    --
    -- The delta is pinned by its own fingerprint rather than by a number typed
    -- here: every composed row carries an `order`, which no hand-written row in
    -- this addon sets. So this says three things the old equality could not —
    -- how many rows the library composes, that every surviving degraded row is
    -- host-declared, and that nothing ELSE went missing.
    -- red under: deleting Helpers.LSMValues, Helpers.AnchorValues or any
    -- composer from settings/OptionsSetup.lua's stub, which takes a whole page
    -- file's rows with it rather than just that block's
    local full     = T.load(true)
    local degraded = T.load(true, false, nil, { libFiles = {} })
    assertNil(degraded.mocks.LibStub("LibKa0s-Options-1.0", true),
        "sanity: the degraded load must not have the major")

    local composed, hostDeclared = 0, 0
    for _, row in ipairs(full.NS.Settings.Schema) do
        if row.order ~= nil then composed = composed + 1 else hostDeclared = hostDeclared + 1 end
    end
    assertTrue(composed > 0, "sanity: this addon must actually compose something")

    assertEqual(#degraded.NS.Settings.Schema, hostDeclared,
        "the degraded load must register every row the HOST declares")
    for _, row in ipairs(degraded.NS.Settings.Schema) do
        assertNil(row.order,
            "a composed row survived the library's absence: " .. tostring(row.path))
    end
    assertEqual(#full.NS.Settings.Schema - #degraded.NS.Settings.Schema, composed,
        "the degraded load is short by more than the composed blocks")
end)

test("the hollow composers cost the degraded path no CLI reach it otherwise has",
function()
    -- THE BLAST RADIUS OF THE options-ui-§1 DEVIATION, measured rather than
    -- argued -- and it is smaller than the deviation row used to claim.
    --
    -- §1's stated harm is that a short schema takes `list`, `get`, `set`, `reset`
    -- and the profile defaults down with it, silently. Neither half is reachable
    -- here, and this case is what says so rather than a paragraph:
    --
    --   1. THE SCHEMA CLI IS NOT RUNNING ON THIS LOAD AT ALL. LibKa0s-Slash-1.0
    --      lives in the same libs/LibKa0s/ folder as LibKa0s-Options-1.0, which
    --      options-ui-§1 requires be vendored WHOLE (anti-pattern #48), so the
    --      load that loses the composers loses the CLI in the same breath.
    --      settings/Slash.lua's stub answers `set`/`get`/`list`/`reset` with one
    --      "is unavailable" line each -- for a HOST-DECLARED row exactly as for a
    --      composed one. There is no state of this addon in which a composed path
    --      is addressable-but-missing.
    --   2. The profile defaults are defaults/Profile.lua's, merged by AceDB in
    --      core/Database.lua's aceDBDefaults, and never read off the schema. A
    --      composed setting a player already made keeps being honored.
    --
    -- What the deviation does cost is #NS.Settings.Schema being short by 116 rows
    -- on a load where the only three things that read it -- the CLI, the panel and
    -- RestoreAllDefaults' sessionOnly walk -- are respectively absent, absent, and
    -- looking for `state.debugConsole`, whose console window is unavailable on
    -- this path too (core/DebugLogSetup.lua:70-72).
    --
    -- red under: settings/Slash.lua's stub gaining a real CliSet, which would
    -- make the composed rows genuinely unreachable-but-asked-for and turn the
    -- deviation into the regression it was reported as
    local inst = T.load(true, false, nil, { libFiles = {} })
    assertNil(inst.mocks.LibStub("LibKa0s-Slash-1.0", true),
        "sanity: the degraded load must not have the slash major either")

    -- A row that SURVIVES the library's absence, so the only thing under test is
    -- whether the CLI can reach anything at all.
    local path = "units.target.enabled"
    assertTrue(inst.NS.Settings.Helpers.FindSchema(path) ~= nil,
        "precondition: this witness must be a host-declared row, present on both paths")

    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    inst.NS:OnSlashCommand("set " .. path .. " false")
    frame.AddMessage = orig

    assertEqual(inst.NS.Settings.Helpers.Get(path), true,
        "the degraded `/kcd set` must not write -- for a surviving row either")
    local said = false
    for _, line in ipairs(lines) do
        if tostring(line):find("unavailable", 1, true) then said = true end
    end
    assertTrue(said, "the degraded `/kcd set` must name the missing library, not go quiet")
end)

test("the degraded stub keeps the global reset real", function()
    -- options-ui-§1: a user whose panel will not open is exactly the user who
    -- needs "reset everything", and the schema loaded fine, so it still works.
    local inst = T.load(true, false, nil, { libFiles = {} })
    local H2 = inst.NS.Settings.Helpers
    assertEqual(type(H2.RestoreAllDefaults), "function")
    -- A HOST-DECLARED row, deliberately: `locked` used to be the witness here and
    -- is a COMPOSED row now, so it does not exist on the degraded path at all
    -- (see the case above for why that is the measured cost rather than a bug).
    -- The per-unit enable is hand-written in settings/General.lua and is present
    -- on both paths, which is what makes it a witness for the reset itself.
    local path = "units.target.enabled"
    inst.NS.Settings.Helpers.SetAndRefresh(path, false)
    assertEqual(H2.Get(path), false, "precondition: the write landed")
    H2.RestoreAllDefaults()
    assertEqual(H2.Get(path), inst.NS.Settings.Helpers.FindSchema(path).default,
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

-- The link note draws NO hover highlight, and that is a fix rather than a
-- preference: it shipped with `SetHighlight(1, 1, 1, 0.12)`, which AceGUI forwards
-- to Texture:SetTexture -- whose four-number form is the deprecated colour API --
-- and the client painted a solid BRIGHT GREEN block over the whole line on
-- mouseover. The line stays clickable; it simply does not light up.
--
-- red under: re-adding SetHighlight in any form, or dropping the OnClick with it.
test("the linked-Focus note has no hover highlight but is still clickable", function()
    local NS = T.NS
    local cfg = NS.Units.Config("focus")
    local before = cfg and cfg.link
    if cfg then cfg.link = true end
    local H = NS.Settings.Helpers
    local wasUnit = H.ViewedUnit()

    local AceGUI = T.mocks.LibStub("AceGUI-3.0")
    local ctx = H.CreatePanel("KickCDNoteHL", "castbar", { pageKey = "castbar" })
    ctx.scroll = AceGUI:Create("ScrollFrame")
    H.SetViewedUnit("focus")
    H.RenderUnitPanel(ctx, "castbar")

    local note
    for _, child in ipairs(ctx.scroll.children) do
        if type(child.text) == "string"
           and child.text:find("Linked to Target", 1, true) then note = child end
    end
    assertTrue(note ~= nil, "the linked page must draw the note")
    assertNil(note.__highlight,
        "the note must set no hover highlight; AceGUI paints a solid green block for one")
    assertTrue(note.callbacks and note.callbacks.OnClick ~= nil,
        "…and it must still be clickable")

    H.SetViewedUnit(wasUnit)
    if cfg then cfg.link = before end
end)

-- The link note GOES somewhere. Naming a destination and not being able to reach
-- it is the failure this replaced -- the note named a control and a page and left
-- the reader to find both by hand, two categories away in Blizzard's list.
--
-- Driven through the real click: the assertion is that Blizzard's category switch
-- is called with the General page's OWN category id, and that the page is put on
-- the Units tab BEFORE the switch rather than a frame later.
--
-- red under: dropping the OpenPageTab wiring, opening the parent category instead
-- of the page's own, or setting the tab after the switch.
test("the linked-Focus note opens General on its Units tab", function()
    local opened
    local inst = T.load(true, true, function(mocks)
        local S = mocks.Settings
        S.OpenToCategory = function(id) opened = id end
    end)
    local NS = inst.NS
    local H  = NS.Settings.Helpers

    local general = NS.Settings.categoryFor and NS.Settings.categoryFor.general
    assertTrue(general ~= nil, "the General page's category must be recorded")

    local cfg = NS.Units.Config("focus")
    if cfg then cfg.link = true end
    H.SetViewedUnit("focus")

    local ctx = H.__panelFor("castbar")
    assertTrue(ctx ~= nil, "the Cast bar page must be registered")
    ctx.panel:Show()
    H.RefreshPanel(ctx, true)

    local note
    for _, child in ipairs((ctx.scroll and ctx.scroll.children) or {}) do
        if type(child.text) == "string"
           and child.text:find("Linked to Target", 1, true) then note = child end
    end
    assertTrue(note ~= nil, "the linked page must draw the note")

    note:__fire("OnClick")

    assertEqual(opened, general:GetID(),
        "the click must open the General page's own category")
    local generalCtx = H.__panelFor("general")
    assertEqual(generalCtx and generalCtx.activeTab, NS.L["Units"],
        "…already on the Units tab, not on whatever it was last left on")

    if cfg then cfg.link = false end
    H.SetViewedUnit("target")
end)

-- The Focus link's two controls are ONE LINE: [Use same styling as Target]
-- [Copy styling from Target]. They were two -- a half-width tick, then a button
-- pair holding a single button -- and a button on its own line reads as belonging
-- to whatever follows it rather than to the tick above.
--
-- Driven through a real render rather than scanned, because the claim is about
-- LAYOUT: both must land in ONE Flow row, which is a fact about the widget tree
-- and not about the source.
--
-- red under: going back to SessionToggle + InlineButtonPair (two rows), or
-- dropping either cell's `make` return, which leaves RenderGrid counting the row
-- half-filled and puts the next item beside the tick.
test("the Focus link's tick and its Copy button share one row", function()
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    local ctx = H.__panelFor("general")
    assertTrue(ctx ~= nil, "the General page must be registered")

    ctx.activeTab = inst.NS.L["Units"]
    ctx.panel:Show()            -- the body is built lazily, on first OnShow
    H.RefreshPanel(ctx, true)

    local tickLabel = inst.NS.L["Use same styling as Target"]
    local btnLabel  = inst.NS.L["Copy styling from Target"]
    local paired
    for _, child in ipairs((ctx.scroll and ctx.scroll.children) or {}) do
        local sawTick, sawBtn = false, false
        for _, w in ipairs(child.children or {}) do
            if w.labelText == tickLabel then sawTick = true end
            if w.text == btnLabel then sawBtn = true end
        end
        if sawTick and sawBtn then paired = child end
    end
    assertTrue(paired ~= nil,
        "the tick and the Copy button must be two children of ONE row")
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

test("the degraded stub carries no widget maker or layout constant", function()
    -- options-ui-§1 is explicit: MUST NOT carry a copy of a widget maker, the
    -- flow engine, the header, or any of the library's layout constants.
    local fh = assert(io.open(T.root .. "/settings/OptionsSetup.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match('AceGUI:Create'), "the stub reaches for AceGUI")
    assertNil(src:match("ROW_VSPACER%s*="), "the stub copies a layout constant")
    assertNil(src:match("0%.492"), "the stub copies BUTTON_PAIR_REL")
    -- The three constants the tabbed page and the banner added (options-ui-§13 / §14). They are
    -- exempted from the surface-parity sweep in tests/test_surface_parity.lua PRECISELY because
    -- copying them here is forbidden, so the exemption and this scan are two halves of one rule:
    -- without the scan, "exempt" would read as "optional".
    assertNil(src:match("BANNER_H%s*="), "the stub copies the banner height")
    assertNil(src:match("CHROME_GAP%s*="), "the stub copies the chrome gap")
    assertNil(src:match("TAB_H%s*="), "the stub copies the tab height")
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
