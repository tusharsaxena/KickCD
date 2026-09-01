-- settings/General.lua
--
-- General canvas panel. Declares its schema entries (master enable,
-- visibility, lock, master scale/alpha) and registers a builder that renders
-- them via Helpers.RenderTabbedSchema -- two tabs, Master controls and Units,
-- partitioned from the `group` field in declaration order (options-ui-§13).
-- The "Reset position" action is injected as a button after the Master
-- controls schema rows via the afterGroup callback (anchors live outside the
-- simple key=value space the schema covers, so they can't be a schema row
-- themselves), and the Units tab's afterGroup carries the Focus styling link.
--
-- WHY TWO TABS AND NOT THREE. "Appearance" used to be a section of its own,
-- holding master scale and master alpha. Two rows whose LABELS both say Master
-- is not a second subject, it is the same subject broken over a click: enable,
-- visibility, lock, scale and alpha are all the addon-as-a-whole. Units is the
-- one genuinely different question on this page -- which grids exist, and
-- whether Focus is its own thing -- and it is what a player sets once, so it
-- sits last.
--
-- Every schema entry here is automatically wired into /kcd get|set,
-- so adding a new General option = one row in this file.

local addonName, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Schema = NS.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

-- Master controls — deliberately ordered so the flow engine's pair-into-lines
-- pass produces:
--     [Enable KickCD]   | [General visibility]
--     [Master scale]    | [Master alpha]
-- followed by the afterGroup's two bespoke lines:
--     [Lock frame]      | [Debug console]
--     [Reset position]  | [Reset all settings]
--
-- The group's rows MUST stay contiguous: RenderTabbedSchema partitions by
-- `group` in declaration order, and a row filed under a group the array has
-- already left prints that tab a second time. `locked` is skipRender and still
-- has to sit inside the run for that reason.
add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "enabled",  type    = "bool",
    label    = L["Enable KickCD"],
    desc  = L["Master enable for the addon."],
    default  = true,
}

add{
    panel    = "general",   section = "general", group = L["Master controls"],
    path     = "visibility", type    = "string",
    label    = L["General visibility"],
    desc  = L["When the addon (icon grid + cast bar) should be visible. Master enable still wins — disabled hides everything."],
    default  = "target_casting_interruptible",
    values   = {
        ["always"] = L["Always"],
        ["in_combat"] = L["In combat"],
        ["target_casting"] = L["When target is casting"],
        ["target_casting_interruptible"] = L["When target is casting an interruptible spell"],
    },
    sorting = { "always", "in_combat", "target_casting", "target_casting_interruptible" },
}

-- Master scale and master alpha were the whole of a separate "Appearance"
-- section until the tab strip landed. They read across one line as a pair --
-- how big, how solid -- and both are the MASTER value their labels say they
-- are, so they belong beside the master enable rather than behind a tab of
-- their own.
add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "scale",    type    = "number",
    label    = L["Master scale"],
    desc  = L["Scale multiplier applied to the entire icon grid."],
    default  = 1.0,
    min = 0.5, max = 2.0, step = 0.05, fmt = "%.2fx",
}

add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "alpha",    type    = "number",
    label    = L["Master alpha"],
    desc  = L["Global opacity for the icon grid."],
    default  = 1.0,
    min = 0.0, max = 1.0, step = 0.05, fmt = "%.2f",
}

add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "locked",   type    = "bool",
    label    = L["Lock frame"],
    desc  = L["When unlocked, you can drag the icon grid to reposition it."],
    default  = false,
    -- Rendered manually by the Master-controls afterGroup so it can pair on
    -- one row with the bespoke session-only Debug console toggle (InlinePair).
    -- Still a normal schema row for /kcd get|set and Defaults.
    skipRender = true,
}

-- Debug logging is a SESSION-ONLY flag (KickCD.State.debug), never persisted
-- to SavedVariables (debug-logging-§5), so it is deliberately NOT a schema row here.
-- Toggle it via the debug console's header button or `/kcd debug on|off|toggle`.

-- Per-unit ENABLE toggles (§Task 6). One row per NS.Units.LIST entry, driving
-- `/kcd set units.<unit>.enabled` and (via Helpers.Set firing
-- Ka0s_KickCD_CONFIG_CHANGED{section="units"}) IconGrid/Castbar's
-- ReconcileUnits. The label/selector/link/copy UI (Task 8) lives in its own
-- panel; this is deliberately just the enable bool so both rows render
-- under SchemaForPanel("general") regardless of which unit is "selected".
for _, u in ipairs(NS.Units.LIST) do
    add{
        panel   = "general", section = "units", group = L["Units"],
        path    = "units." .. u .. ".enabled", unit = u, type = "bool",
        label   = (u == "target" and L["Enable Target grid"] or L["Enable Focus grid"]),
        default = true,
    }
end

-- ---------------------------------------------------------------------
-- Builder
-- ---------------------------------------------------------------------

-- StaticPopup for "Reset all settings" — irreversible, so confirm
-- before wiping. The OnAccept body lives in Helpers.ResetAll so the
-- popup, the General > "Reset all settings" button, and the
-- `/kcd resetall` slash command all share a single implementation —
-- no chance of the popup and the slash diverging.
StaticPopupDialogs["KICKCD_RESET_ALL"] = {
    -- THE COLLECTION'S ONE WORDING (options-ui-§12), verbatim. Addon-agnostic on
    -- purpose: no addon enumerates its own nouns, and eight phrasings of one act
    -- is how a collection reads as eight addons.
    text         = L["Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded \226\128\148 your other profiles are not affected."],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function() H.ResetAll() end,
}

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end

    local ctx
    ctx = H.CreatePanel("KickCDGeneralPanel", L["General"], {
        panelKey       = "general",
        defaultsButton = true,
    })
    -- Parked, not wired: the Defaults button doesn't exist until the
    -- panel's first OnShow (H.EnsureDefaultsButton).
    ctx.panel.defaultsOnClick = function()
        H.RestoreDefaults("general", ctx)
    end

    -- The library owns WHEN this draws (H.SetRenderer): first show, and again
    -- when a refresh marked it dirty while it was hidden. Building at
    -- registration time would lay the widgets out against a zero-width body,
    -- because registration happens at PLAYER_LOGIN.
    H.SetRenderer(ctx, function(c)
        H.ClearScroll(c)
        H.RenderTabbedSchema(c, "general", {
            [L["Master controls"]] = function(ctxRef)
                -- Lock frame (schema bool, skipRender) pairs on one row with a
                -- bespoke, SESSION-ONLY Debug console toggle. The Debug checkbox
                -- shows/hides the console WINDOW (DebugLog:Show/Hide) — it does
                -- NOT touch the debug capture flag (debug-logging-§5); that stays on the
                -- in-window "Debug: ON/OFF" button and `/kcd debug on|off`. It's
                -- bespoke (not a schema row) so it never persists to SV and
                -- never appears in /kcd get|set|list.
                H.InlinePair(ctxRef,
                    function(c2, row) H.RenderField(c2, H.FindSchema("locked"), row, 0.5) end,
                    function(c2, row)
                        H.SessionToggle(c2, {
                            label   = L["Debug console"],
                            tooltip = L["Show or hide the on-screen debug console window. Session-only; does not change debug logging on/off."],
                            get     = function() return NS.DebugLog and NS.DebugLog:IsShown() end,
                            set     = function(on)
                                if not NS.DebugLog then return end
                                if on then NS.DebugLog:Show() else NS.DebugLog:Hide() end
                            end,
                        }, row, 0.5)
                    end)
                H.InlineButtonPair(ctxRef,
                    {
                        text    = L["Reset position"],
                        tooltip = L["Restore the icon grid to its default screen position."],
                        onClick = function() H.ResetIconPosition() end,
                    },
                    {
                        text    = L["Reset all settings"],
                        tooltip = L["Reset every General, Icons, and Cast bar setting to its default, and rebuild every spec's spell list from the addon defaults. Profiles are left alone."],
                        onClick = function() StaticPopup_Show("KICKCD_RESET_ALL") end,
                    })
            end,
            -- The Focus styling link. It used to be drawn three times over, once
            -- in each unit page's hand-built header, and there is exactly one of
            -- it: whether Focus keeps its own appearance or mirrors Target's.
            -- Neither control is a schema row — `link` is a plain profile field
            -- with no path in the schema, and the copy is an action — so both
            -- hang off the Units group rather than becoming rows.
            --
            -- The write is STRUCTURAL, and that is the whole reason it can live
            -- on another page at all: H.RefreshAllPanels re-renders every page
            -- that declared a renderer, and marks the hidden ones dirty so they
            -- repaint on their next OnShow. Ticking this here really does change
            -- what Icons / Cast bar / Text Label draw.
            [L["Units"]] = function(ctxRef)
                H.SessionToggle(ctxRef, {
                    label = L["Use same styling as Target"],
                    tooltip = L["Focus mirrors Target's icon grid, cast bar and label appearance. Untick to give Focus its own."],
                    get   = function()
                        local cfg = NS.Units.Config("focus")
                        return cfg ~= nil and cfg.link == true
                    end,
                    set   = function(on)
                        local cfg = NS.Units.Config("focus")
                        if cfg then cfg.link = on and true or false end
                        H.FireConfigChanged("units")
                        H.RefreshAllPanels()
                    end,
                }, nil, 0.5)
                H.InlineButtonPair(ctxRef,
                    {
                        text    = L["Copy styling from Target"],
                        tooltip = L["Copy Target's current appearance onto Focus once, and unlink so the two can drift apart from here."],
                        onClick = function()
                            NS.Units.CopyStyling("target", "focus")
                            H.FireConfigChanged("units")
                            H.RefreshAllPanels()
                        end,
                    })
            end,
        })
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["General"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("general", L["General"], Build)
end
