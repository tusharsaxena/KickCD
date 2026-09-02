-- settings/Panel_Render.lua
--
-- Schema-driven render + reset/orchestration layer for the settings
-- panel, peeled out of settings/Panel.lua (KCD-24, layout-§1) so each file
-- stays under the LOC cap. Turns schema rows into two-column Flow rows
-- (RenderRows / RenderSchema / RenderUnitPanel) and owns the Defaults /
-- reset-all / reset-position helpers. Loads AFTER settings/Panel.lua and
-- settings/Panel_Widgets.lua (it uses the makers via Helpers.RenderField)
-- and BEFORE the per-tab files that call RenderSchema / Restore* / Reset*.

local addonName, NS = ...
local L       = NS.L
local Helpers = NS.Settings.Helpers

-- Framework helpers published by settings/Panel.lua, rebound to a file-local so
-- the moved code below reads exactly as it did in place.
--
-- AceGUI, Helpers.AddSpacer and Helpers.ROW_VSPACER used to be bound here too.
-- They were the hand-built unit-selector header's: the dropdown, the Focus
-- link/copy row, and the gap under each. The picker is the library's PageBanner
-- now and the link controls moved to the General page, so this file creates no
-- widget of its own and measures no gap of its own.
local ensureScroll      = Helpers.EnsureScroll

-- (Helpers.RerenderUnitPanel is GONE. It cleared the scroll and re-ran
-- RenderSchema, which is the untabbed render; a unit page draws a tab strip in
-- its chrome band now (options-ui-§13) and RenderUnitPanel below is the one
-- entry point that puts the banner, the strip and the rows back in the right
-- order. It had no callers -- the unit dropdown always re-entered
-- RenderUnitPanel directly -- so what it left behind was a second, wrong answer
-- to "how does this page redraw?".)

-- Split a unit panel's rows into those that stay editable even when Focus
-- is linked (alwaysPerUnit — e.g. label show/text, which are per-unit by
-- design) and the appearance rows the link hides. Pure; unit-tested.
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
-- Per-unit page chrome -- the Unit picker, and what a linked Focus shows
-- ---------------------------------------------------------------------
--
-- THE UNIT DROPDOWN IS THE PAGE BANNER (options-ui-§14), pinned in the chrome
-- band ABOVE the tab strip rather than added to the scroll. That is not a
-- cosmetic move. The strip's own re-render on a tab click clears the SCROLL and
-- redraws the rows; anything a page parks in the scroll ahead of the strip is
-- gone the first time the reader clicks a tab. The chrome band survives it, and
-- the picker scopes the whole page -- every tab on it edits the selected unit --
-- so the band is where it belongs.
--
-- It is also the ONLY picker on the page, which is the other half of §14: two
-- controls over one piece of state is a synchronisation problem invented by the
-- design and owned forever. There is one value, read at render time, and the
-- re-render the selection triggers repaints everything below it.
--
-- Full rebuild on every call rather than a persistent widget: AceGUI's pool
-- exists to make release-and-recreate cheap, and PageBanner drains both chrome
-- ledgers (the banner's and the strip's) before it draws, so a unit switch
-- cannot leave the previous unit's tabs stranded under the new one's.
--
-- The Focus "Use same styling as Target" tick and the "Copy styling from
-- Target" button used to be drawn here, once per unit page. They are on the
-- General page's Units tab now (settings/General.lua): they are one relationship
-- between two units rather than three per-page copies of it, and the scroll --
-- the only place left to draw them -- is cleared out from under them by every
-- tab click.
function Helpers.RenderUnitPanel(ctx, panelKey, afterGroup)
    ctx.unit = ctx.unit or "target"
    Helpers.ClearScroll(ctx)

    local items, order = {}, {}
    for i, u in ipairs(NS.Units.LIST) do
        items[u] = (u == "target") and L["Target"] or L["Focus"]
        order[i] = u
    end

    local dd = Helpers.PageBanner(ctx, {
        label   = L["Unit"],
        tooltip = L["Which unit every tab on this page is editing. Target and Focus are configured independently unless Focus is set to use Target's styling."],
        list    = items,
        order   = order,
        value   = ctx.unit,
        onSelect = function(value)
            if not value or value == ctx.unit then return end
            ctx.unit = value
            Helpers.RenderUnitPanel(ctx, panelKey, afterGroup)
        end,
    })
    -- Parked on the ctx so a suite can drive the selection the way a click
    -- would; the library keeps its own chrome widgets private.
    ctx.__bannerWidget = dd

    if NS.Units.IsLinked(ctx.unit) then
        Helpers.RenderLinkedUnit(ctx, panelKey, afterGroup)
        return
    end

    Helpers.RenderTabbedSchema(ctx, panelKey, afterGroup)
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
--- rows plus the note. What changed is that the strip is above them.
---
--- The strip is drawn by hand rather than by RenderTabbedSchema because that
--- function renders the active tab's rows itself, and the whole point here is
--- that most of them must not be rendered. Tab selection, the stale-pointer
--- heal and the re-render on click are the same three things it does.
function Helpers.RenderLinkedUnit(ctx, panelKey, afterGroup)
    local rows = Helpers.SchemaForPanel(panelKey, ctx.unit)

    local groups, seen = {}, {}
    for _, def in ipairs(rows) do
        if def.group and not seen[def.group] then
            seen[def.group] = true
            groups[#groups + 1] = def.group
        end
    end
    -- A tab pointing at a group this page no longer has renders a blank page
    -- under a strip, so a stale pointer heals to the first rather than being
    -- trusted -- the same heal RenderTabbedSchema does, for the same reason.
    if not (ctx.activeTab and seen[ctx.activeTab]) then ctx.activeTab = groups[1] end

    local tabs = {}
    for i, name in ipairs(groups) do tabs[i] = { key = name, label = name } end
    Helpers.TabStrip(ctx, {
        tabs  = tabs,
        value = ctx.activeTab,
        onSelect = function(key)
            if key == ctx.activeTab then return end
            ctx.activeTab = key
            Helpers.ClearScroll(ctx)
            Helpers.RenderLinkedUnit(ctx, panelKey, afterGroup)
        end,
    })

    local active = {}
    for _, def in ipairs(rows) do
        if def.group == ctx.activeTab then active[#active + 1] = def end
    end
    local perUnit = Helpers.PartitionUnitRows(active)
    -- noHeadings, because the tab label already carries the section's name and
    -- drawing a Heading under it is the same label twice (options-ui-§7).
    Helpers.RenderRows(ctx, perUnit, afterGroup, nil, { noHeadings = true })
    Helpers.TextRow(ctx, L["Linked to Target. Untick 'Use same styling as Target' on the General page's Units tab to give Focus its own."])
    local scroll = ensureScroll(ctx)
    if scroll and scroll.DoLayout then scroll:DoLayout() end
end

-- Look up `path` in the schema and write `value` through the same
-- path the schema widgets use: Helpers.Set (which fires CONFIG_CHANGED
-- with def.section), then def.onChange, then RefreshAllPanels so any
-- open settings tab reflects the new value. Returns true on success,
-- false if no schema row matches `path`.
--
-- Lets slash commands that mutate schema-backed fields (e.g. `/kcd
-- lock`, `/kcd debug log`) share a single write/notify/refresh code
-- path with `/kcd set <path> <value>` and the panel widgets — so a
-- future onChange added to a row doesn't silently diverge between
-- code paths.
function Helpers.SetAndRefresh(path, value)
    local def = Helpers.FindSchema(path)
    if not def then return false end
    Helpers.Set(def.path, def.section, value)
    if def.onChange then
        local ok, err = pcall(def.onChange, value)
        if not ok and NS.Util then
            NS.Util.print("onChange for " .. tostring(def.path)
                              .. " failed: " .. tostring(err))
        end
    end
    -- SCALAR, never structural. A value write changes what a widget SHOWS; it
    -- does not make a row appear or vanish. A structural sweep here would clear
    -- and rebuild every rendered page on each committed change -- including the
    -- page holding the slider or the color swatch the user is still dragging,
    -- which is released back to AceGUI's pool mid-gesture. Structural refreshes
    -- have their own callers: NS.RefreshOptionsPanel on a profile switch, and
    -- the Units tab's link toggle, which really does change what the unit pages
    -- draw.
    Helpers.RefreshScalars()
    return true
end

-- Restore the TARGET icon grid to its default screen position and notify
-- the icon module so it re-anchors immediately. Used by the General tab's
-- "Reset position" button and the `/kcd resetposition` slash command —
-- both are legacy "reset the grid" affordances that predate Focus (Task
-- 8), so they deliberately only touch Target; a Focus position reset is
-- out of scope here (Focus already gets its own screen offset from
-- DEFAULT_PROFILE so the two grids don't overlap on first enable).
--
-- The default coords come from KickCD.DEFAULT_PROFILE.units.target.
-- anchors.icons so we don't duplicate magic numbers across UI / CLI /
-- Database layers. (Task 1 moved anchors from the profile's top level to
-- units.target/.focus — this helper previously read/wrote the stale
-- top-level path and was a silent no-op ever since.)
function Helpers.ResetIconPosition()
    if not (NS.db and NS.db.profile) then return end
    local d = NS.DEFAULT_PROFILE
              and NS.DEFAULT_PROFILE.units
              and NS.DEFAULT_PROFILE.units.target
              and NS.DEFAULT_PROFILE.units.target.anchors
              and NS.DEFAULT_PROFILE.units.target.anchors.icons
    NS.db.profile.units = NS.db.profile.units or {}
    NS.db.profile.units.target = NS.db.profile.units.target or {}
    NS.db.profile.units.target.anchors = NS.db.profile.units.target.anchors or {}
    NS.db.profile.units.target.anchors.icons = d
        and { point = d.point, relativePoint = d.relativePoint,
              x = d.x, y = d.y }
        or  { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }
    -- "general" alone is sufficient: IconGrid:OnConfigChanged's general
    -- branch re-anchors every enabled unit's grid from its own
    -- units.<unit>.anchors.icons. The previous "icons" fire was
    -- redundant work — no row in the icons section actually changed,
    -- and the general branch already owns the re-anchor pass.
    Helpers.FireConfigChanged("general")
end

-- Reset every unit's icon-grid AND cast-bar anchor to its DEFAULT_PROFILE
-- screen position. Anchors aren't schema rows, so RestoreAllDefaults skips
-- them — this is why /kcd resetall (and the "Reset all settings" popup)
-- historically left the grids where the user dragged them. ResetAll calls
-- this so a full reset restores positions too. Fires "general" (for icon grids
-- and PRIMARY-mode cast bars) then "castbar" (for FREE-mode cast bars) so
-- every unit's anchor re-applies and every frame snaps to its default position.
function Helpers.ResetAllPositions()
    if not (NS.db and NS.db.profile and NS.DEFAULT_PROFILE and NS.DEFAULT_PROFILE.units) then return end
    NS.db.profile.units = NS.db.profile.units or {}
    for _, unit in ipairs({ "target", "focus" }) do
        local du = NS.DEFAULT_PROFILE.units[unit]
        if du and du.anchors then
            local pu = NS.db.profile.units[unit] or {}
            NS.db.profile.units[unit] = pu
            pu.anchors = pu.anchors or {}
            for _, which in ipairs({ "icons", "castbar" }) do
                local a = du.anchors[which]
                if a then
                    pu.anchors[which] = { point = a.point, relativePoint = a.relativePoint, x = a.x, y = a.y }
                end
            end
        end
    end
    Helpers.FireConfigChanged("general")
    Helpers.FireConfigChanged("castbar")
end

-- Restore every unit's `link` flag to its DEFAULT_PROFILE value (target=false,
-- focus=true). `link` is NOT a schema row — it's driven by the bespoke checkbox
-- in RenderUnitPanel — so RestoreAllDefaults can't reach it. Without this, an
-- unlinked Focus (link=false) survives a full reset: its appearance tables get
-- reset to defaults so it LOOKS default, but it silently loses the mirror-Target
-- relationship, diverging from AceDB's Reset Profile (which restores the whole
-- DEFAULT_PROFILE, link included). Fires "units" so IconGrid/Castbar reconcile.
function Helpers.RestoreUnitLinks()
    if not (NS.db and NS.db.profile and NS.DEFAULT_PROFILE
            and NS.DEFAULT_PROFILE.units and NS.Units) then
        return
    end
    local p = NS.db.profile
    p.units = p.units or {}
    for _, unit in ipairs(NS.Units.LIST) do
        local du = NS.DEFAULT_PROFILE.units[unit]
        if du then
            p.units[unit] = p.units[unit] or {}
            p.units[unit].link = du.link and true or false
        end
    end
    Helpers.FireConfigChanged("units")
end

-- Reset every schema-driven panel AND every spec's spell list to addon
-- defaults. The active profile is the only one affected. Used by the
-- General tab's "Reset all settings" popup and the `/kcd resetall`
-- slash command — both go through this single helper so the two paths
-- never diverge.
--
-- ResetAllPositions and RestoreUnitLinks are NOT called here. They used to be,
-- and RestoreAllDefaults had already run both by the time it returned: the
-- descriptor's `afterRestoreAll` hook (settings/OptionsSetup.lua) is exactly
-- those two calls, and libs/LibKa0s/Options.lua's O.RestoreAllDefaults fires it
-- before the refresh — deliberately before, so the refresh paints the
-- post-hook values. Repeating them here re-ran two whole-profile writes and two
-- CONFIG_CHANGED fan-outs per reset, and, worse, made the hook look optional:
-- delete `afterRestoreAll` and this path still worked, while `/kcd resetall`'s
-- other caller (the library's own Defaults button) silently stopped clearing
-- anchors (KCD-R-04). One caller, one place.
--
-- What is genuinely NOT the library's is the spell lists: they are not schema
-- rows and not positions, so nothing upstream can reach them.
function Helpers.ResetAll()
    -- ONE CALL, because RestoreAllDefaults is a PROFILE reset now
    -- (options-ui-§12, settings/OptionsSetup.lua's afterRestoreAll). The spell
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