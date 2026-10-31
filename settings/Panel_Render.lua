-- settings/Panel_Render.lua
--
-- Schema-driven render + reset/orchestration layer for the settings
-- panel, peeled out of settings/Panel.lua (KCD-24, layout-§1) so each file
-- stays under the LOC cap. Turns schema rows into two-column Flow rows
-- (RenderRows / RenderSchema / RenderUnitPanel) and owns the Defaults /
-- reset-all / reset-position helpers. Loads AFTER settings/Panel.lua
-- (it uses the library's makers via Helpers.RenderField)
-- and BEFORE the per-tab files that call RenderSchema / Restore* / Reset*.

local _, NS = ...
local L       = NS.L
local Helpers = NS.Settings.Helpers

-- Framework helpers published by settings/Panel.lua, rebound to a file-local so
-- the moved code below reads exactly as it did in place.
--
-- Helpers.AddSpacer and Helpers.ROW_VSPACER used to be bound here too. They were
-- the old hand-built unit-selector header's gaps. The band is one library
-- PageHeader block now (below), whose height is the library's BANNER_H, so this
-- file measures no gap of its own.
local ensureScroll      = Helpers.EnsureScroll

-- (Helpers.RerenderUnitPanel is GONE. It cleared the scroll and re-ran
-- RenderSchema, which is the untabbed render; a unit page draws a tab strip in
-- its chrome band now (options-ui-§13) and RenderUnitPanel below is the one
-- entry point that puts the banner, the strip and the rows back in the right
-- order. It had no callers -- the unit dropdown always re-entered
-- RenderUnitPanel directly -- so what it left behind was a second, wrong answer
-- to "how does this page redraw?".)

-- Split a unit panel's rows into those that stay editable even when Focus
-- is linked (alwaysPerUnit — the label's text, which is per-unit by design)
-- and the appearance rows the link hides. Pure; unit-tested.
function Helpers.PartitionUnitRows(rows)
    local perUnit, styled = {}, {}
    for _, def in ipairs(rows) do
        if def.alwaysPerUnit then
            perUnit[#perUnit + 1] = def
        else
            styled[#styled + 1] = def
        end
    end
    return perUnit, styled
end

-- ---------------------------------------------------------------------
-- Per-unit page chrome -- the Unit band, and what a linked Focus shows
-- ---------------------------------------------------------------------
--
-- THE BAND IS ONE PageHeader BLOCK (options-ui-§14), pinned in the chrome band
-- ABOVE the tab strip rather than added to the scroll. That is not a cosmetic
-- move. The strip's own re-render on a tab click clears the SCROLL and redraws
-- the rows; anything a page parks in the scroll ahead of the strip is gone the
-- first time the reader clicks a tab. The chrome band survives it, and the
-- picker scopes the whole page -- every tab on it edits the selected unit -- so
-- the band is where it belongs.
--
-- ONE ROW, four cells (KIC-L01, item 020):
--     [Unit] [Enable this unit] [Link to Target]* [Copy from Target]*
-- (* while Focus is the unit in the band). Everything about one unit sits on
-- the page that picks it; the enable and the link used to be a trip to the
-- General page's Units tab. The library's PageBanner draws exactly one Dropdown
-- (and at most one action), so a picker with acts beside it is a PageHeader
-- block with the picker inside it -- "at most one such block" per page. The
-- cells' widths are fixed, so the band is the same height and the picker sits
-- in the same place for both units.
--
-- The picker is still the ONLY picker on the page, which is the other half of
-- options-ui-§14: two controls over one piece of state is a synchronization
-- problem invented by the design and owned forever. There is one value, read at
-- render time, and the re-render the selection triggers repaints everything
-- below it.
--
-- The enable and the link are SCHEMA ROWS (settings/General.lua, skipRender,
-- stamped to the General page) drawn through the library's RenderField, so they
-- write through the one seam and refresh like any row. The copy is an act.
--
-- Full rebuild on every call rather than persistent widgets: AceGUI's pool
-- exists to make release-and-recreate cheap. The block's frame is the library's
-- (one per page); the AceGUI widgets inside it are ours, so the previous
-- render's are released once the new ones exist.

-- The four cells' shares of the band's width.
local BAND_CELLS = { picker = 0.30, enable = 0.23, link = 0.21, copy = 0.26 }

--- Which unit every Grid entry is editing, and the only writer of it.
---
--- ONE value for the three entries rather than one per ctx, which is what it was:
--- flipping the picker to Focus on Icons and walking to Cast bar landed back on
--- Target, because each page's ctx carried its own. The picker names which half
--- of the addon you are configuring, and that is a property of the reader's
--- session, not of the page they happen to have open.
---
--- Session-only (core/State.lua) and never persisted: see the note there.
--- Validated on read, so a value that is not a real unit -- an old field, a hand
--- edit -- falls back to Target rather than rendering a page for nothing.
function Helpers.ViewedUnit()
    local want = NS.State and NS.State.viewedUnit
    for _, u in ipairs(NS.Units.LIST) do
        if u == want then return u end
    end
    return NS.Units.LIST[1] or "target"
end

function Helpers.SetViewedUnit(unit)
    if NS.State then NS.State.viewedUnit = unit end
end

--- The "Copy from Target" act, built into the band's flow host. Refused in
--- combat as the picker is: it rewrites a whole unit's rows.
local function copyFromTargetButton(AceGUI, host)
    local btn = AceGUI:Create("Button")
    btn:SetText(L["Copy from Target"])
    btn:SetRelativeWidth(BAND_CELLS.copy)
    -- CopyStyling is the whole act: every row through the helper, the bus
    -- announced once per section, and the one structural refresh from the link
    -- row it writes last.
    btn:SetCallback("OnClick", function()
        if Helpers.__combatRefused and Helpers.__combatRefused("button", "copy") then return end
        NS.Units.CopyStyling("target", "focus")
    end)
    Helpers.AttachTooltip(btn, L["Copy from Target"],
        L["Copy Target's current appearance onto Focus once, and unlink so the two can drift apart from here."])
    host:AddChild(btn)
    return btn
end

--- The Unit picker, built into the band's flow host.
local function unitPicker(ctx, AceGUI, host)
    local items, order = {}, {}
    for i, u in ipairs(NS.Units.LIST) do
        items[u] = (u == "target") and L["Target"] or L["Focus"]
        order[i] = u
    end
    local dd = AceGUI:Create("Dropdown")
    dd:SetLabel(L["Unit"])
    dd:SetList(items, order)
    dd:SetValue(ctx.unit)
    dd:SetRelativeWidth(BAND_CELLS.picker)
    dd:SetCallback("OnValueChanged", function(_, _, value)
        -- A change of subject, so refused in combat and put back, as the
        -- library's own banner refuses it.
        if Helpers.__combatRefused and Helpers.__combatRefused("select", value) then
            dd:SetValue(ctx.unit)
            return
        end
        if not value or value == ctx.unit then return end
        Helpers.SetViewedUnit(value)
        -- STRUCTURAL, not a re-render of this page alone. The selection is
        -- shared, so the Units page must redraw on the new unit;
        -- RefreshAllPanels re-renders the ones on screen and marks the hidden
        -- ones dirty so they repaint on their next OnShow.
        Helpers.RefreshAllPanels()
    end)
    Helpers.AttachTooltip(dd, L["Unit"],
        L["Which unit every tab on this page is editing. Target and Focus are configured independently, except that Focus follows Target while Link to Target, beside this picker, is ticked."])
    host:AddChild(dd)
    return dd
end

--- Draw the band's cells into the PageHeader frame `frame`.
local function buildUnitBand(ctx, frame)
    local AceGUI = Helpers.AceGUI or NS.AceGUI
    if not (AceGUI and frame) then return end
    local Store = NS.Settings.Store
    local stale = ctx.__unitBand

    local host = AceGUI:Create("SimpleGroup")
    host:SetLayout("Flow")
    host.frame:SetParent(frame)
    host.frame:ClearAllPoints()
    host.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    host.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    host.frame:Show()
    ctx.__unitBand = host

    -- Parked on the ctx so a suite can drive the selection the way a click
    -- would; the band's widgets are otherwise private to this function.
    ctx.__bannerWidget = unitPicker(ctx, AceGUI, host)
    local enableRow = Store.FindRow("units." .. ctx.unit .. ".enabled")
    if enableRow then Helpers.RenderField(ctx, enableRow, host, BAND_CELLS.enable) end
    if ctx.unit == "focus" then
        local linkRow = Store.FindRow("units.focus.link")
        if linkRow then Helpers.RenderField(ctx, linkRow, host, BAND_CELLS.link) end
        copyFromTargetButton(AceGUI, host)
    end
    if host.DoLayout then host:DoLayout() end

    -- After the new band exists, never before: the picker's own callback may be
    -- what is re-rendering, and its widget must outlive the call.
    if stale and stale.Release then stale:Release() end
end

function Helpers.RenderUnitPanel(ctx, panelKey, afterGroup, chrome)
    -- Read, never defaulted from the ctx: the shared value is the source of
    -- truth, and a ctx that kept its own would be the second copy this exists to
    -- remove. It is still written onto the ctx because everything below -- the
    -- schema partition, the link check, the tests -- reads ctx.unit.
    ctx.unit = Helpers.ViewedUnit()
    Helpers.ClearScroll(ctx)

    Helpers.PageHeader(ctx, {
        height = Helpers.BANNER_H,
        build  = function(c, frame) buildUnitBand(c, frame) end,
    })

    -- The Units page's nav rail (KickCD#33) goes in HERE: after the band, whose
    -- height it reads for its top, and before EITHER strip path below, which reads
    -- the inset it records. So a linked Focus keeps the rail too. A caller that
    -- passes no chrome draws exactly what it drew before.
    if chrome then chrome(ctx) end

    -- A tab click redraws the WHOLE panel, band included, on both strip paths.
    -- The band is chrome and outlives a strip-only redraw, but its Enable and
    -- Link ticks register their refreshers through RenderField, and ClearScroll
    -- reassigns ctx.refreshers: a strip-only redraw would leave the band's ticks
    -- on screen with no refresher, so a `/kcd set units.<u>.enabled` typed after
    -- any tab click left them stale. Pinned by tests/test_grid.lua ("the band's
    -- ticks still follow a scalar write after a tab click").
    local function rerender(c) Helpers.RenderUnitPanel(c, panelKey, afterGroup, chrome) end

    if NS.Units.IsLinked(ctx.unit) then
        Helpers.RenderLinkedUnit(ctx, panelKey, afterGroup, rerender)
        return
    end

    Helpers.RenderTabbedSchema(ctx, panelKey, afterGroup, nil, { rerender = rerender })
end

--- A linked Focus: the STRIP FIRST, always, and the link note as content.
---
--- This used to return before the strip was drawn, on the argument that "a tab
--- strip over a note is chrome for its own sake". That argument is about one
--- page and it is the wrong rule for a panel (options-ui-§13): a reader who
--- flips the Unit picker to Focus watched the whole page shape change under
--- them, and the page that lost its strip is the one that looks broken. The
--- link state is a STATE OF THE PAGE, so it belongs inside the page.
---
--- Editable-but-ignored appearance widgets are still worse than none -- a linked
--- Focus renders with Target's tables, so a styled row here would write to a
--- table nothing reads -- so the tab's CONTENT is still only its alwaysPerUnit
--- rows plus the note. What changed is that the strip is above them. One row is
--- alwaysPerUnit since item 020 (KIC-L05): Text label > General's Label text,
--- which is per-unit by design and still renders while linked.
---
--- The strip is drawn by hand rather than by RenderTabbedSchema because that
--- function renders the active tab's rows itself, and the whole point here is
--- that most of them must not be rendered. Tab selection, the stale-pointer
--- heal and the re-render on click are the same three things it does.
---
--- The library's RenderTabbedSchema `opts` (OptionsTabs minor 4, LibKa0s v1.56.0)
--- were evaluated for this page and DECLINED (KC-20, issue #23, closed as
--- will-not-do). The gap: `disabledFor` draws `disabledNotice` ABOVE the rows and
--- still draws every row disabled, where this page must show the note INSTEAD of
--- them (and, since KIC-L05, the alwaysPerUnit rows beside it). The strip is not
--- made inert by the library either, and `chrome(ctx)` could reach its buttons
--- only through the private `ctx.__tabLayout`. Pinned by
--- tests/test_options_panel_degraded.lua ("a linked Focus page draws the full
--- strip and only the link note, plus its alwaysPerUnit rows").
--- Make a drawn strip inert: every button disabled, every one of its textures
--- desaturated.
---
--- ONLY for a linked-Focus entry whose tabs have nothing to switch BETWEEN: no
--- row of any of its tabs is `alwaysPerUnit`, so every group's linked content is
--- the same, the note and nothing else. A strip you can click that redraws the
--- identical page is a control that appears to do something and does not -- the
--- same defect the up/down arrows had before the reorder lists took a drag. The
--- strip still draws, because the page must not change shape when the picker
--- flips (options-ui-§13); it just cannot be operated, and the desaturation is
--- what makes that read as deliberate rather than broken.
---
--- An entry with an alwaysPerUnit row on any tab (Text label, whose General tab
--- holds Label text: KIC-L05) keeps a LIVE strip, or the row would be
--- unreachable from any other tab of the entry -- and a unit switch must leave
--- the entry's tab alone (options-ui-§14), so the page cannot jump to it.
---
--- Done on the buttons TabStrip returns rather than through a flag on the tab
--- spec, because the spec has no such flag: the library owns the strip and this is
--- one page in one addon. If a second page ever needs it, that is the moment it
--- becomes `disabled` on the spec and moves into LibKa0s, not before.
local function deadenStrip(buttons)
    for _, b in ipairs(buttons or {}) do
        if b.SetEnabled then b:SetEnabled(false) end
        -- The art is created by the library and kept in no named field, so it is
        -- reached the way the client offers it. A FontString answers no
        -- SetDesaturated, hence the guard rather than a blanket call.
        if b.GetRegions then
            for _, region in ipairs({ b:GetRegions() }) do
                if region and region.SetDesaturated then region:SetDesaturated(true) end
            end
        end
    end
end

--- `rerender` (optional) is RenderUnitPanel's whole-panel redraw, which a tab
--- click calls in place of the strip-only redraw below, for the band's sake.
function Helpers.RenderLinkedUnit(ctx, panelKey, afterGroup, rerender)
    local rows = Helpers.SchemaForPanel(panelKey, ctx.unit)

    local groups, seen, perUnitTabs = {}, {}, false
    for _, def in ipairs(rows) do
        if def.group and not seen[def.group] then
            seen[def.group] = true
            groups[#groups + 1] = def.group
        end
        if def.alwaysPerUnit then perUnitTabs = true end
    end
    -- A tab pointing at a group this page no longer has renders a blank page
    -- under a strip, so a stale pointer heals to the first rather than being
    -- trusted -- the same heal RenderTabbedSchema does, for the same reason.
    if not (ctx.activeTab and seen[ctx.activeTab]) then ctx.activeTab = groups[1] end

    local tabs = {}
    for i, name in ipairs(groups) do tabs[i] = { key = name, label = name } end
    local buttons = Helpers.TabStrip(ctx, {
        tabs  = tabs,
        value = ctx.activeTab,
        onSelect = function(key)
            if key == ctx.activeTab then return end
            ctx.activeTab = key
            if rerender then return rerender(ctx) end
            Helpers.ClearScroll(ctx)
            Helpers.RenderLinkedUnit(ctx, panelKey, afterGroup)
        end,
    })
    if not perUnitTabs then deadenStrip(buttons) end

    local active = {}
    for _, def in ipairs(rows) do
        if def.group == ctx.activeTab then active[#active + 1] = def end
    end
    local perUnit = Helpers.PartitionUnitRows(active)
    -- noHeadings, because the tab label already carries the section's name and
    -- drawing a Heading under it is the same label twice (options-ui-§7).
    Helpers.RenderRows(ctx, perUnit, afterGroup, nil, { noHeadings = true })
    -- PLAIN TEXT, no link (KIC-L04, item 020). The tick it names is in this
    -- page's own band now, a few pixels up, so there is nowhere to go: the note
    -- used to be a link to the General page's Units tab, two categories away.
    Helpers.TextRow(ctx, L["Linked to Target. Untick Link to Target above to give this unit its own look."])
    local scroll = ensureScroll(ctx)
    if scroll and scroll.DoLayout then scroll:DoLayout() end
end

-- ---------------------------------------------------------------------
-- The Units page: the Unit band, the nav rail, the selected entry (#33)
-- ---------------------------------------------------------------------
--
-- Icons, Cast bar and Text label are one page (settings/Grid.lua). The Unit
-- picker is the band, a nav rail (LibKa0s-Options' O.NavRail, options-ui-§13)
-- chooses the entry, and each entry keeps the tab strip its own page had. An
-- entry IS the old page key: every row keeps `panel`, `section`, `unit` and its
-- `units.<unit>.<page>.*` path, so /kcd, the defaults, profiles and
-- SchemaForPanel never see the rail. The entry and each entry's tab are session
-- state on the ctx, never persisted; the band stays the only picker, and a unit
-- switch leaves both alone (options-ui-§14). AuraMaster's Containers page (#6) is
-- the pattern.
--
-- Host code on BOTH arms: settings/OptionsSetup.lua's stub returns before this
-- file loads, so a library-absent build still has the registry the page files
-- call at load, and the stub owes nothing but O.NavRail's no-op.

local gridEntries = {}
-- The rail's order, fixed here rather than taken from the TOC.
local GRID_ORDER = { "icons", "castbar", "label" }
-- The Units page's ctx, bound by its builder: the one page SelectSection moves.
local gridCtx

--- Register one entry of the Units page. Called at FILE LOAD by settings/Icons.lua,
--- Castbar.lua and Label.lua.
--- @param key string    the entry's page key: the `panel` its schema rows carry
--- @param label string  the rail entry's label
--- @param spec table    { tooltip = the rail entry's tooltip }
function Helpers.RegisterGridSection(key, label, spec)
    spec = spec or {}
    gridEntries[key] = { key = key, label = label, tooltip = spec.tooltip }
end

--- The registered entry `key`, or nil.
--- A read of one entry, for the headless suites: no shipped code calls it.
function Helpers.GridSection(key) return gridEntries[key] end

--- The entries the rail lists, in rail order. Every unit has all three.
local function railEntries()
    local out = {}
    for _, key in ipairs(GRID_ORDER) do
        if gridEntries[key] then out[#out + 1] = gridEntries[key] end
    end
    return out
end

--- The entry to draw: the one the page holds while the rail lists it, else the first.
local function settleEntry(ctx, list)
    for _, e in ipairs(list) do
        if e.key == ctx.activeSection then return e end
    end
    return list[1]
end

--- Keep the tab the page is on for the entry it last drew. Called before ANYTHING
--- moves the entry: the library's own strip click never calls back here
--- (RenderTabbedSchema re-renders the strip and the rows itself), so leaving is the
--- one moment the host sees the tab.
local function stashTab(ctx)
    local drawn = ctx.__renderedSection
    if drawn then ctx.sectionTabs[drawn] = ctx.activeTab end
    ctx.__renderedSection = nil
end

--- Bind the Units page's ctx (settings/Grid.lua's builder). The page opens on Icons.
function Helpers.__bindGridPage(ctx)
    gridCtx = ctx
    ctx.sectionTabs = {}
    ctx.activeSection = GRID_ORDER[1]
end

--- Render the Units page: the Unit band, the nav rail, then the entry's strip and
--- rows -- the library's draw order, PageBanner, NavRail, TabStrip. The band and
--- both strip paths are Helpers.RenderUnitPanel's; the rail goes in through its
--- chrome hook.
function Helpers.RenderGridPage(ctx)
    ctx.sectionTabs = ctx.sectionTabs or {}
    stashTab(ctx)
    local list = railEntries()
    local entry = settleEntry(ctx, list)
    if not entry then return end
    ctx.activeSection = entry.key
    ctx.activeTab = ctx.sectionTabs[entry.key]
    local entries = {}
    for i, e in ipairs(list) do entries[i] = { key = e.key, label = e.label, tooltip = e.tooltip } end
    Helpers.RenderUnitPanel(ctx, entry.key, nil, function(c)
        Helpers.NavRail(c, {
            entries  = entries,
            value    = entry.key,
            onSelect = function(key)
                stashTab(c)
                c.activeSection = key
                Helpers.RefreshPanel(c, true)
            end,
        })
    end)
    ctx.__renderedSection = entry.key
end

--- The Units page's Defaults: the active entry's rows FOR THE UNIT IN THE BAND, and
--- no other unit's. The owner's ruling for KickCD#33, and a documented deviation
--- (docs/ARCHITECTURE.md, options-ui-§13): the library's O.RestoreDefaults resets
--- every unit of a page on purpose, and it still does when called directly.
---
--- The library's own bracket, driven by hand: one `reset <entry>` act, so the
--- console logs one `[Set] reset <entry>: N rows` line and no line per row
--- (debug-logging-§10). Refused in combat, as the library's page reset is, and
--- named in the library's one `[Cfg] defaults grid/<entry> refused (in combat)` line.
function Helpers.RestoreGridSection(ctx)
    if Helpers.__combatRefused
        and Helpers.__combatRefused("defaults", "grid", ctx and ctx.activeSection or "?") then return end
    local entry = gridEntries[ctx and ctx.activeSection]
    if not entry then return end
    local Store = NS.Settings.Store
    local rows = Helpers.SchemaForPanel(entry.key, Helpers.ViewedUnit())
    Store.BulkBegin("reset", entry.key)
    local ok, err = pcall(function()
        for _, row in ipairs(rows) do Store.ApplyDefault(row) end
    end)
    Store.BulkEnd("reset", entry.key, nil, err)
    if not ok then error(err, 0) end
    if Helpers.RefreshScalars then Helpers.RefreshScalars() end
end

--- Select entry `key` on the Units page, and optionally its tab: the one seam a
--- link or a suite moves the entry through. A hidden page is marked
--- owed a render and draws the entry on its next show. Refused in combat, as a tab
--- switch is (options-ui-§2, §13), and named in the library's one
--- `[Cfg] section <key> refused (in combat)` line.
--- @return boolean  whether the entry was selected
function Helpers.SelectSection(key, tabKey)
    if Helpers.__combatRefused and Helpers.__combatRefused("section", key) then return false end
    local ctx = gridCtx
    if not (ctx and gridEntries[key]) then return false end
    stashTab(ctx)
    ctx.activeSection = key
    if tabKey ~= nil then ctx.sectionTabs[key] = tabKey end
    Helpers.RefreshPanel(ctx, true)
    return true
end

-- The library's SelectTab moves one PAGE's tab. An entry key is no page of its own
-- (KickCD#33): it routes to SelectSection, so a caller using the old page
-- keys still lands. Any other key -- General, Spells -- is the library's.
local selectTab = Helpers.SelectTab
function Helpers.SelectTab(pageKey, tabKey)
    if gridEntries[pageKey] then return Helpers.SelectSection(pageKey, tabKey) end
    return selectTab(pageKey, tabKey)
end

--- Write one schema row through the seam and repaint any open panel's values.
---
--- NS.Settings.Store.Set is the write (settings/SchemaSetup.lua): the refusal of
--- an unknown path, the store, the row's onChange and the CONFIG_CHANGED for the
--- row's section. This adds the one thing a panel needs on top, and only when
--- the write landed. Answers the seam's own `ok, err, why`, so both descriptors'
--- `set` hand a refusal straight back to the library that prints it.
---
--- SCALAR, never structural. A value write changes what a widget SHOWS; it
--- does not make a row appear or vanish. A structural sweep here would clear
--- and rebuild every rendered page on each committed change -- including the
--- page holding the slider or the color swatch the user is still dragging,
--- which is released back to AceGUI's pool mid-gesture. Structural refreshes
--- have their own callers: NS.RefreshOptionsPanel on a profile switch, and
--- the `units.focus.link` row's onChange (settings/General.lua), because the
--- link really does change what the Grid entries draw.
function Helpers.SetAndRefresh(path, value)
    local ok, err, why = NS.Settings.Store.Set(path, value)
    if ok then Helpers.RefreshScalars() end
    return ok, err, why
end

-- (The host's row-batch helper is gone, and writeRow with it. A batch is Store.SetMany now
-- -- all or nothing, one bracket line with `act`, every onChange after every
-- store, and one announcement per section -- and core/Units.lua's CopyStyling,
-- its one caller, calls it directly.)

-- Put every unit's icon grid back where it starts, then tell the icon module
-- to re-anchor. The General page's "Reset position" button and
-- `/kcd resetposition` both land here. It walks NS.Units.LIST, so target and
-- focus both come home; before KICKCD-R-14 it reached target alone and a focus
-- grid dragged off screen had no way back short of a full reset.
--
-- Only the grids move. A cast bar set to move freely keeps its own spot
-- (units.<unit>.anchors.castbar); an anchored bar follows its grid anyway.
--
-- Each unit's coordinate comes from NS.DEFAULT_PROFILE.units.<unit>.anchors
-- .icons, the one place it is written down. A unit with no default there is
-- skipped rather than given a made-up coordinate: an earlier fallback number
-- disagreed with defaults/Profile.lua by 300 px, and leaving the grid where
-- the user dragged it is the least surprising result. With no defaults tree
-- at all nothing is written and nothing is published.
--
-- The anchor is named non-setting state owned by NS.Units (architecture-§5).
-- This writes it directly rather than through NS.Units.SetAnchor, and
-- docs/ARCHITECTURE.md -> Settings schema lists it as one of that state's
-- writers, which is what makes the direct write compliant.
local function defaultGridAnchor(unit)
    local u = NS.DEFAULT_PROFILE and NS.DEFAULT_PROFILE.units
              and NS.DEFAULT_PROFILE.units[unit]
    return u and u.anchors and u.anchors.icons
end

function Helpers.ResetIconPosition()
    if not (NS.db and NS.db.profile) then return end
    local profile, moved = NS.db.profile, false
    for _, unit in ipairs(NS.Units.LIST) do
        local d = defaultGridAnchor(unit)
        if d then
            profile.units = profile.units or {}
            local u = profile.units[unit] or {}
            profile.units[unit] = u
            u.anchors = u.anchors or {}
            u.anchors.icons =
                { point = d.point, relativePoint = d.relativePoint, x = d.x, y = d.y }
            moved = true
        end
    end
    -- One "general" fire covers every unit: IconGrid:OnConfigChanged's
    -- general branch re-anchors each enabled grid from its own
    -- units.<unit>.anchors.icons.
    if moved then Helpers.FireConfigChanged("general") end
end

-- (Helpers.ResetAllPositions is gone. It put every unit's icon-grid and
-- cast-bar anchor back to DEFAULT_PROFILE, and nothing had called it since
-- Reset all became a profile reset, which restores the anchors with the rest
-- of the profile.)
--
-- (Helpers.RestoreUnitLinks is gone. It restored each unit's `link` flag
-- because `link` had no schema row, and nothing had called it since Reset all
-- became a profile reset. `units.focus.link` is a row now (settings/General.lua),
-- so the General page's Defaults and `/kcd reset` restore it like any other, and
-- the profile reset restores it with the rest of the profile.)

-- Reset every schema-driven panel AND every spec's spell list to addon
-- defaults. The active profile is the only one affected. Used by the
-- General tab's "Reset all settings" popup and the `/kcd resetall`
-- slash command — both go through this single helper so the two paths
-- never diverge.
--
-- The old ResetAllPositions and RestoreUnitLinks (both gone) are NOT called here.
-- They used to be, and RestoreAllDefaults had already done both by the time it returned: the
-- descriptor's `resetProfile` hook (settings/OptionsSetup.lua) empties the
-- active profile and merges NS.DEFAULT_PROFILE back over it, anchors and every
-- unit's `link` flag included, and libs/LibKa0s/Options.lua's
-- O.RestoreAllDefaults fires it before the refresh — deliberately before, so
-- the refresh paints the post-hook values. Repeating them here re-ran two
-- whole-profile writes and two CONFIG_CHANGED fan-outs per reset, and, worse,
-- made the hook look optional: delete `resetProfile` and this path still worked,
-- while `/kcd resetall`'s other caller (the library's own Defaults button)
-- silently stopped clearing anchors (KCD-R-04). One caller, one place.
--
-- What is genuinely NOT the library's is the spell lists: they are not schema
-- rows and not positions, so nothing upstream can reach them.
function Helpers.ResetAll()
    -- ONE CALL, because RestoreAllDefaults is a PROFILE reset now
    -- (options-ui-§12, settings/OptionsSetup.lua's resetProfile). The spell
    -- lists live at `db.profile.spells`, so emptying the profile clears them and
    -- Database:OnProfileChanged re-seeds them through BuildSpells on the way back
    -- — the same path a profile switch takes. The explicit ResetAllSpells call
    -- that used to follow was doing that work a second time.
    --
    -- Database:ResetAllSpells is untouched and still backs `/kcd spells resetall`.
    Helpers.RestoreAllDefaults()
end


-- (RenderRows, RenderSchema, ClearScroll, RefreshAllPanels, RestoreDefaults and
-- RestoreAllDefaults are LibKa0s-Options-1.0's now: the two-column flow engine,
-- the refresher fan-out and the reset trio. What stays above is the per-unit
-- rendering and the reset paths that touch state no schema row owns.)