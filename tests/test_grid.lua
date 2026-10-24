-- tests/test_grid.lua
--
-- The Units page (KickCD#33; key `grid`, labeled "Grid" until item 020): Icons, Cast bar and Text
-- label as one page. The Unit band across the top (one PageHeader block since KIC-L01), the nav rail
-- (Icons, Cast bar, Text label), each entry's own tab strip, the tab each entry
-- keeps, and a linked Focus under the rail -- and, from NR-KC-03, Defaults for the unit in the band
-- and the deep links. The pattern is AuraMaster's Containers page (#6) on LibKa0s v1.61.0's
-- O.NavRail. Pinned from the outside: a fresh instance per case, the page shown the way Blizzard
-- shows it, the rail clicked through the library's own entry buttons.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

local RAIL_ORDER = "icons,castbar,label"

--- A fresh instance with spies on the three chrome calls, recording each page's last rail and strip,
--- and handles on its Grid page. `mutate` goes to T.load (it runs on the mock before any file loads).
local function env(mutate)
    local inst = T.load(true, true, mutate)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local rails, strips, calls = {}, {}, {}
    local navRail, tabStrip, pageHeader = H.NavRail, H.TabStrip, H.PageHeader
    H.NavRail = function(ctx, spec, ...)
        calls[#calls + 1] = "NavRail"
        rails[ctx] = spec
        return navRail(ctx, spec, ...)
    end
    H.TabStrip = function(ctx, spec, ...)
        calls[#calls + 1] = "TabStrip"
        strips[ctx] = spec
        return tabStrip(ctx, spec, ...)
    end
    H.PageHeader = function(ctx, spec, ...)
        calls[#calls + 1] = "PageHeader"
        return pageHeader(ctx, spec, ...)
    end

    local P = { inst = inst, NS = NS, H = H, L = NS.L, calls = calls }

    function P.ctx() return H.__panelFor("grid") end

    --- Show the Grid page the way Blizzard does, driving the genuine deferred render.
    function P.show()
        local ctx = P.ctx()
        assertTrue(ctx ~= nil, "no Grid page registered")
        ctx.panel:Hide()
        ctx.panel:Show()
        -- The render is pcall'd by the library, so a raise shows up as no rail, not as an error.
        assertTrue(rails[ctx] ~= nil, "the Grid page drew no rail (its renderer raised)")
        return ctx
    end

    function P.railKeys()
        local out = {}
        for i, e in ipairs((rails[P.ctx()] or {}).entries or {}) do out[i] = e.key end
        return table.concat(out, ",")
    end

    function P.railValue() return (rails[P.ctx()] or {}).value end

    function P.tabLabels()
        local out = {}
        for i, t in ipairs((strips[P.ctx()] or {}).tabs or {}) do out[i] = t.label end
        return table.concat(out, "|")
    end

    --- The library's own rail button for entry `key` (ctx.__railKids is the rail's ledger, in order).
    function P.railButton(key)
        local ctx = P.ctx()
        for i, e in ipairs((rails[ctx] or {}).entries or {}) do
            if e.key == key then return ctx.__railKids[i] end
        end
        error("the rail drew no entry " .. tostring(key), 2)
    end

    --- Click rail entry `key` the way the player does (KickCD's frame mock runs a script with
    --- `_run`), and answer the page's ctx.
    function P.rail(key)
        local ctx = P.ctx()
        P.railButton(key):_run("OnClick")
        ctx.panel:Hide()
        ctx.panel:Show()
        return ctx
    end

    return P
end

--- The groups of one entry's rows for one unit, in declaration order: the strip it draws.
local function groupsOf(H, page, unit)
    local out, seen = {}, {}
    for _, def in ipairs(H.SchemaForPanel(page, unit)) do
        if def.group and not seen[def.group] then
            seen[def.group] = true
            out[#out + 1] = def.group
        end
    end
    return out
end

--- Link or unlink Focus's styling to Target's on this instance.
local function focusLink(P, linked)
    local cfg = P.NS.Units.Config("focus")
    assertTrue(cfg ~= nil, "sanity: Focus has a config")
    cfg.link = linked
end

-- ── the registry ─────────────────────────────────────────────────────────────────────────────

test("grid: Icons, Cast bar and Text label register as Units entries under their page keys, on both builds", function()
    local L = T.NS.L
    local LABELS = { icons = "Icons", castbar = "Cast bar", label = "Text label" }
    local builds = {
        live = T.NS.Settings.Helpers,
        ["library-absent"] = T.load(true, false, nil, { libFiles = {} }).NS.Settings.Helpers,
    }
    for build, H in pairs(builds) do
        for key, label in pairs(LABELS) do
            -- red under: a page file registering no entry, or the registry kept behind the fork
            local s = H.GridSection and H.GridSection(key)
            assertTrue(s ~= nil, build .. ": " .. key .. " registered no entry")
            assertEqual(s.key, key, build .. ": " .. key .. " keeps its page key, so every row path is unchanged")
            assertEqual(s.label, L[label], build .. ": " .. key .. "'s rail label")
            assertEqual(type(s.tooltip), "string", build .. ": " .. key .. " carries a rail tooltip")
        end
        assertFalse(H.GridSection("general") ~= nil, build .. ": General is a page of its own, not a Grid entry")
    end
end)

-- ── the page ─────────────────────────────────────────────────────────────────────────────────

test("grid: the Unit band, then the rail Icons, Cast bar, Text label, 120 wide, opening on Icons", function()
    local P = env()
    local ctx = P.show()
    -- red under: the rail in TOC order or missing an entry, or the page opening elsewhere
    assertEqual(P.railKeys(), RAIL_ORDER)
    assertEqual(ctx.activeSection, "icons")
    assertEqual(P.railValue(), "icons")
    assertEqual(ctx.railWidth, 120)
    assertEqual(ctx.__bannerWidget and ctx.__bannerWidget.labelText, P.L["Unit"], "the band is the Unit picker")
    assertEqual(P.tabLabels(), table.concat(groupsOf(P.H, "icons", "target"), "|"))
end)

test("grid: the draw order is PageHeader, NavRail, TabStrip", function()
    local P = env()
    P.show()
    -- red under: the rail drawn before the band (its top ignores the band) or after the strip (the
    -- strip places itself with no inset)
    assertEqual(table.concat({ P.calls[1], P.calls[2], P.calls[3] }, ","), "PageHeader,NavRail,TabStrip")
end)

test("grid: a rail click draws that entry's own strip under the same band", function()
    local P = env()
    P.show()
    local ctx = P.rail("castbar")
    local want = groupsOf(P.H, "castbar", "target")
    assertEqual(ctx.activeSection, "castbar")
    assertEqual(P.railValue(), "castbar")
    -- red under: every entry rendered under one fixed page key (Icons' strip on Cast bar)
    assertEqual(P.tabLabels(), table.concat(want, "|"))
    assertEqual(want[3], P.L["Text"], "sanity: Cast bar's third tab is Text")
    assertEqual(ctx.__bannerWidget.labelText, P.L["Unit"], "the band is drawn with the entry")
    assertEqual(ctx.unit, "target")
end)

-- Review Focus 3.
test("grid: each entry keeps its own tab, including one chosen by the library's own strip click", function()
    local P = env()
    P.show()
    local L = P.L
    local ctx = P.rail("castbar")
    ctx.__tabKids[3]:_run("OnClick")                -- the library's own strip click: no host render
    assertEqual(ctx.activeTab, L["Text"])
    P.rail("label")
    assertEqual(ctx.activeTab, L["General"], "Text label opens on its first tab")
    ctx.__tabKids[2]:_run("OnClick")
    assertEqual(ctx.activeTab, L["Placement"])
    P.rail("icons")
    P.rail("castbar")
    -- red under: one scalar activeTab for the page, or a stash only on host renders (the strip
    -- click above never reaches the host)
    assertEqual(ctx.activeTab, L["Text"])
    P.rail("label")
    assertEqual(ctx.activeTab, L["Placement"])
end)

test("grid: choosing the other unit in the band keeps the entry and its tab", function()
    local P = env()
    focusLink(P, false)
    P.show()
    local ctx = P.rail("castbar")
    ctx.__tabKids[3]:_run("OnClick")
    assertEqual(ctx.activeTab, P.L["Text"])
    ctx.__bannerWidget:__fire("OnValueChanged", "focus")
    assertEqual(P.H.ViewedUnit(), "focus")
    -- red under: a unit switch resetting the entry or the tab (options-ui-§14: the rail is not a picker)
    assertEqual(ctx.activeSection, "castbar")
    assertEqual(ctx.activeTab, P.L["Text"])
    assertEqual(ctx.unit, "focus", "the page now edits Focus")
end)

test("grid: a linked Focus keeps the rail; each entry draws its full strip over the link note, inert unless it has a per-unit row", function()
    local P = env()
    focusLink(P, true)
    P.H.SetViewedUnit("focus")
    local ctx = P.show()
    -- red under: the rail drawn after RenderUnitPanel's linked branch has returned (a linked Focus
    -- with no rail), or drawn only on the RenderTabbedSchema path
    assertEqual(P.railKeys(), RAIL_ORDER)
    for _, key in ipairs({ "icons", "castbar", "label" }) do
        if ctx.activeSection ~= key then P.rail(key) end
        assertEqual(ctx.activeSection, key)
        local buttons = (ctx.__tabLayout or {}).buttons or {}
        assertEqual(#buttons, #groupsOf(P.H, key, "focus"), key .. ": one tab per schema group")
        -- Text label keeps a live strip: its General tab holds Label text, alwaysPerUnit (KIC-L05).
        if key ~= "label" then
            for i, b in ipairs(buttons) do
                assertEqual(b.__enabled, false, key .. ": tab " .. i .. " is operable on a linked Focus")
            end
        end
        local notes = 0
        for _, child in ipairs(ctx.scroll and ctx.scroll.children or {}) do
            if type(child.text) == "string" and child.text:find("Linked to Target", 1, true) then
                notes = notes + 1
            end
        end
        assertEqual(notes, 1, key .. ": the link note, once")
    end
end)

-- ── Defaults, deep links, SelectTab (NR-KC-03) ─────────────────────────────────────────────

--- The first stored boolean row of `panel` for `unit`: one to move off its default.
local function boolRow(H, panel, unit)
    for _, row in ipairs(H.SchemaForPanel(panel, unit)) do
        if row.type == "bool" and row.default ~= nil and not row.sessionOnly and row.path then return row end
    end
end

-- Review Focus 4.
test("grid: Defaults restores only the active entry's rows, for the unit in the band", function()
    local P = env()
    local H, S = P.H, P.NS.Settings.Store
    focusLink(P, false)
    P.show()
    local ctx = P.rail("castbar")
    local tc, fc, ti = boolRow(H, "castbar", "target"), boolRow(H, "castbar", "focus"), boolRow(H, "icons", "target")
    for _, row in ipairs({ tc, fc, ti }) do
        assertTrue(row ~= nil, "sanity: a boolean row to move")
        assertTrue(S.Set(row.path, not row.default))
    end

    local brackets = {}
    local begin = S.BulkBegin
    S.BulkBegin = function(act, scope, ...)
        brackets[#brackets + 1] = tostring(act) .. " " .. tostring(scope)
        return begin(act, scope, ...)
    end
    local ok, err = pcall(ctx.panel.defaultsOnClick)
    S.BulkBegin = begin
    assertTrue(ok, tostring(err))

    -- red under: the library's page walk (Focus's row reset too), or a closure that fixed the entry
    -- when the page was built (Icons' rows reset from Cast bar)
    assertEqual(S.Get(tc.path), tc.default, "Target's cast bar row is back")
    assertEqual(S.Get(fc.path), not fc.default, "Focus's cast bar row is not the unit in the band's")
    assertEqual(S.Get(ti.path), not ti.default, "Target's icons row is not the active entry's")
    assertEqual(table.concat(brackets, "|"), "reset castbar", "one bulk bracket, scoped to the entry")

    ctx.__bannerWidget:__fire("OnValueChanged", "focus")
    ctx.panel.defaultsOnClick()
    assertEqual(S.Get(fc.path), fc.default, "with Focus in the band, Focus's row")
end)

test("grid: the Defaults tooltip names the rail entry, the unit in the band, and who resets the band", function()
    local P = env()
    local ctx = P.show()
    -- red under: the old "section on screen" wording, or dropping the WS-33 sentence that says the
    -- band's General-stamped rows are reset by the General page's Defaults
    assertEqual(ctx.panel.defaultsTooltip,
        P.L["Restore every tab of the entry selected on the left, for the unit in the band, to its defaults. The other unit keeps its own. The band's Enable this unit and Link to Target are reset by the General page's Defaults."])
    local general = P.H.__panelFor("general")
    general.panel:Show()
    assertTrue(tostring(general.panel.defaultsTooltip):find("Enable this unit", 1, true) ~= nil,
        "the General page's Defaults says it resets the band's rows too")
end)

--- A fresh Grid page whose subcategories answer GetID (KickCD's mock categories do not), recording
--- by tree label the category every OpenToCategory lands on.
local function recordingOpens()
    local byId, opened, count = {}, {}, 0
    local P = env(function(mocks)
        local register = mocks.Settings.RegisterCanvasLayoutSubcategory
        mocks.Settings.RegisterCanvasLayoutSubcategory = function(parent, panel, name)
            local cat = register(parent, panel, name)
            count = count + 1
            local id = 100 + count
            byId[id] = name
            cat.GetID = function() return id end
            return cat
        end
        mocks.Settings.OpenToCategory = function(id) opened[#opened + 1] = byId[id] or "main" end
    end)
    return P, opened
end

-- Review Focus 5.
test("grid: a former page key opens Units on that entry and tab, drawn on its next show", function()
    local P, opened = recordingOpens()
    local ctx = P.show()
    ctx.panel:Hide()                                -- the settings window is closed
    -- red under: OpenPageTab looking "castbar" up in NS.Settings.categoryFor alone (the Cast bar
    -- page today, nothing once it retires)
    assertTrue(P.H.OpenPageTab("castbar", P.L["Text"]))
    assertEqual(opened[#opened], P.L["Units"])
    assertEqual(ctx.activeSection, "castbar", "selected before the show")
    ctx.panel:Show()
    assertEqual(P.railValue(), "castbar", "and drawn on it")
    assertEqual(ctx.activeTab, P.L["Text"], "on the named tab")
    assertTrue(P.H.OpenPageTab("general", P.H.MASTER_GROUP), "a General page key is the library's page")
    assertEqual(opened[#opened], P.L["General"])
end)

test("grid: SelectTab on an entry key selects the entry and its tab; other pages stay the library's", function()
    local P = env()
    local ctx = P.show()
    local H, L = P.H, P.L
    -- red under: the call reaching the library's SelectTab, which moves the page's one scalar tab
    -- (or finds no page once the three retire)
    assertTrue(H.SelectTab("label", L["Placement"]))
    assertEqual(ctx.activeSection, "label")
    assertEqual(ctx.activeTab, L["Placement"])
    assertTrue(H.SelectTab("general", H.MASTER_GROUP), "the General page is the library's")
    assertEqual(H.__panelFor("general").activeTab, H.MASTER_GROUP)
end)

test("grid: selecting an entry is refused in combat and moves nothing", function()
    local P = env()
    local ctx = P.show()
    local D = P.inst.NS.DebugLog
    D:SetEnabled(true)
    D:Clear()
    P.inst.mocks.InCombatLockdown = function() return true end
    -- red under: SelectSection without the library's refusal (a structural render in combat)
    local ok = P.H.SelectSection("label")
    P.H.SelectSection("label")
    P.H.RestoreGridSection(ctx)
    P.inst.mocks.InCombatLockdown = function() return false end
    assertFalse(ok)
    assertEqual(ctx.activeSection, "icons")
    -- The library's combat-lock line (Options minor 27), naming what was refused,
    -- once per combat per act; the host writes none of its own.
    -- red under: either call passing no kind (the line reads `change refused`)
    local n = 0
    for _, line in ipairs(D.buffer) do if tostring(line):find("refused (in combat)", 1, true) then n = n + 1 end end
    assertTrue(D:FindLine("[Cfg] section label refused (in combat)"), "the section switch is named")
    assertTrue(D:FindLine("[Cfg] defaults grid/icons refused (in combat)"), "the Grid Defaults is named")
    assertEqual(n, 2, "one line per refused act, not one per attempt")
    D:SetEnabled(false)
end)
