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
local AceGUI  = LibStub("AceGUI-3.0")
local Helpers = NS.Settings.Helpers

-- Framework helpers published by settings/Panel.lua, rebound to
-- file-locals so the moved code below reads exactly as it did in place.
local ensureScroll      = Helpers.EnsureScroll
local addSpacer         = Helpers.AddSpacer
local ROW_VSPACER       = Helpers.ROW_VSPACER

-- Re-render a per-unit schema panel (Icons / Castbar) after the unit
-- selector switches ctx.unit: clears the panel's scroll frame (via
-- Helpers.ClearScroll) and re-runs RenderSchema, which re-filters
-- SchemaForPanel(panelKey, ctx.unit) for the newly-selected unit.
function Helpers.RerenderUnitPanel(ctx, panelKey, afterGroup)
    Helpers.ClearScroll(ctx)
    Helpers.RenderSchema(ctx, panelKey, afterGroup)
end

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
-- Per-unit panel header — unit selector + focus link/copy row (Task 8).
-- Shared by the Icons and Castbar builders, which are otherwise
-- pure-schema panels; this is the one bit of hand-built AceGUI markup
-- both need, so it lives here once rather than being duplicated.
-- ---------------------------------------------------------------------
--
-- Full rebuild on every call rather than a "persistent, never-released"
-- header widget: ensureScroll's ScrollFrame anchors flush to ctx.body, so
-- there's no free real estate above it to park a truly persistent
-- dropdown without further surgery on that anchor. AceGUI's widget pool
-- exists exactly to make release-and-recreate cheap and safe, so each
-- call here clears ctx.scroll and rebuilds the selector (and, for Focus,
-- the link checkbox + copy button) from scratch — visually identical to
-- a persistent widget, and far simpler to reason about than partially
-- clearing around a surviving header row.
function Helpers.RenderUnitPanel(ctx, panelKey, afterGroup)
    ctx.unit = ctx.unit or "target"
    Helpers.ClearScroll(ctx)
    local scroll = ensureScroll(ctx)

    -- Unit selector -----------------------------------------------------
    local dd = AceGUI:Create("Dropdown")
    dd:SetLabel(L["Unit"])
    dd:SetFullWidth(true)
    local items, order = {}, {}
    for i, u in ipairs(NS.Units.LIST) do
        items[u] = (u == "target") and L["Target"] or L["Focus"]
        order[i] = u
    end
    dd:SetList(items, order)
    dd:SetValue(ctx.unit)
    dd:SetCallback("OnValueChanged", function(_, _, value)
        ctx.unit = value
        Helpers.RenderUnitPanel(ctx, panelKey, afterGroup)
    end)
    scroll:AddChild(dd)
    addSpacer(scroll, ROW_VSPACER)

    -- Focus link + copy header ------------------------------------------
    if ctx.unit == "focus" then
        local cfg = NS.Units.Config("focus")
        local linked = cfg ~= nil and cfg.link == true

        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)

        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(L["Use same styling as Target"])
        cb:SetRelativeWidth(0.5)
        cb:SetValue(linked)
        cb:SetCallback("OnValueChanged", function(_, _, value)
            local c = NS.Units.Config("focus")
            if c then c.link = value and true or false end
            Helpers.FireConfigChanged("units")
            Helpers.RenderUnitPanel(ctx, panelKey, afterGroup)
        end)
        row:AddChild(cb)

        local btn = AceGUI:Create("Button")
        btn:SetText(L["Copy styling from Target"])
        btn:SetRelativeWidth(0.5)
        btn:SetCallback("OnClick", function()
            NS.Units.CopyStyling("target", "focus")
            Helpers.FireConfigChanged("units")
            Helpers.RenderUnitPanel(ctx, panelKey, afterGroup)
        end)
        row:AddChild(btn)

        scroll:AddChild(row)
        addSpacer(scroll, ROW_VSPACER)

        if linked then
            -- Editable-but-ignored appearance widgets are worse than none:
            -- a linked Focus renders with Target's tables, so any styled row
            -- here would write to a table nothing reads. But alwaysPerUnit
            -- rows (label show/text) ARE per-unit even while linked, so they
            -- stay editable; only the appearance rows are replaced by a note.
            local perUnit = Helpers.PartitionUnitRows(
                Helpers.SchemaForPanel(panelKey, ctx.unit))
            Helpers.RenderRows(ctx, perUnit, afterGroup)

            local note = AceGUI:Create("Label")
            note:SetFullWidth(true)
            note:SetText(L["Linked to Target — uncheck to customize."])
            scroll:AddChild(note)
            if scroll.DoLayout then scroll:DoLayout() end
            return
        end
    end

    Helpers.RenderSchema(ctx, panelKey, afterGroup)
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
    Helpers.RefreshAllPanels()
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