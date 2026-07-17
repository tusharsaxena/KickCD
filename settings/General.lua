-- settings/General.lua
--
-- General canvas panel. Declares its schema entries (master enable,
-- lock, master scale/alpha, debug log) and registers a builder that
-- renders them via Helpers.RenderSchema. The "Reset position" action
-- is injected as a button after the Master controls schema rows via
-- the afterGroup callback (anchors live outside the simple key=value
-- space the schema covers, so they can't be a schema row themselves).
--
-- Every schema entry here is automatically wired into /kcd get|set,
-- so adding a new General option = one row in this file.

local addonName, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Schema = NS.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

-- Master controls — deliberately ordered so the schema's pair-into-rows
-- renderer produces:
--     [Enable KickCD]   | [General visibility]
--     [Lock frame]      |
-- followed by an InlineButtonPair afterGroup row:
--     [Reset position]  | [Reset all settings]
add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "enabled",  type    = "bool",
    label    = L["Enable KickCD"],
    tooltip  = L["Master enable for the addon."],
    default  = true,
}

add{
    panel    = "general",   section = "general", group = L["Master controls"],
    path     = "visibility", type    = "string",
    label    = L["General visibility"],
    tooltip  = L["When the addon (icon grid + cast bar) should be visible. Master enable still wins — disabled hides everything."],
    default  = "target_casting_interruptible",
    values   = {
        { value = "always",                       label = L["Always"]                                   },
        { value = "in_combat",                    label = L["In combat"]                                },
        { value = "target_casting",               label = L["When target is casting"]                   },
        { value = "target_casting_interruptible", label = L["When target is casting an interruptible spell"] },
    },
}

add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "locked",   type    = "bool",
    label    = L["Lock frame"],
    tooltip  = L["When unlocked, you can drag the icon grid to reposition it."],
    default  = false,
}

-- Debug logging is a SESSION-ONLY flag (KickCD.State.debug), never persisted
-- to SavedVariables (§12.5), so it is deliberately NOT a schema row here.
-- Toggle it via the debug console's header button or `/kcd debug on|off|toggle`.

add{
    panel    = "general",  section = "general",  group = L["Appearance"],
    path     = "scale",    type    = "number",
    label    = L["Master scale"],
    tooltip  = L["Scale multiplier applied to the entire icon grid."],
    default  = 1.0,
    min = 0.5, max = 2.0, step = 0.05, fmt = "%.2fx",
}

add{
    panel    = "general",  section = "general",  group = L["Appearance"],
    path     = "alpha",    type    = "number",
    label    = L["Master alpha"],
    tooltip  = L["Global opacity for the icon grid."],
    default  = 1.0,
    min = 0.0, max = 1.0, step = 0.05, fmt = "%.2f",
}

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
    text         = L["Reset every schema-driven setting (General, Icons, Cast bar) AND every spec's spell list to addon defaults? The active profile is the only one affected."],
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
    if ctx.panel.defaultsBtn then
        ctx.panel.defaultsBtn:SetCallback("OnClick", function()
            H.RestoreDefaults("general", ctx)
        end)
    end

    -- Defer the AceGUI render until the panel becomes visible: build-time
    -- happens at PLAYER_LOGIN when ctx.body has 0 width, and AceGUI lays
    -- children out against the container's current width.
    local rendered = false
    ctx.panel:SetScript("OnShow", function()
        if rendered then return end
        rendered = true
        H.RenderSchema(ctx, "general", {
            [L["Master controls"]] = function(ctxRef)
                -- Debug console toggle — SESSION-ONLY (§12.5), so it is a
                -- bespoke checkbox driving DebugLog:SetEnabled rather than a
                -- schema row (a schema row would persist to SavedVariables).
                -- Mirrors the console header button and `/kcd debug toggle`.
                H.SessionToggle(ctxRef, {
                    label   = L["Debug console"],
                    tooltip = L["Show the on-screen debug console for this session. Not saved — resets off on reload."],
                    get     = function() return NS.State and NS.State.debug end,
                    set     = function(on) if NS.DebugLog then NS.DebugLog:SetEnabled(on) end end,
                })
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
        })
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["General"])
end

if NS.Settings and NS.Settings.RegisterTab then
    NS.Settings.RegisterTab("general", Build)
end
