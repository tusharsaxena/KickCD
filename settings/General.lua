-- settings/General.lua — KickCD v0.1
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

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L
local H      = KickCD.Settings.Helpers
local Schema = KickCD.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

-- Master controls — deliberately ordered so the schema's pair-into-rows
-- renderer produces:
--     [Enable KickCD]   | [General visibility]
--     [Lock frame]      | [Debug]
-- followed by an InlineButtonPair afterGroup row:
--     [Reset position]  | [Reset all settings]
--
-- debugLog used to live under its own "Debug" subsection; the lone
-- checkbox didn't justify a header, so it joins Master controls instead.
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
    default  = "always",
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
    default  = true,
}

add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "debugLog", type    = "bool",
    label    = L["Debug"],
    tooltip  = L["Print every internal message to chat. Useful for diagnosing module wiring."],
    default  = false,
    onChange = function(v) KickCD._debugLog = v and true or false end,
}

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

-- ---------------------------------------------------------------------
-- Builder
-- ---------------------------------------------------------------------

local function resetPosition()
    if not (KickCD.db and KickCD.db.profile) then return end
    KickCD.db.profile.anchors = KickCD.db.profile.anchors or {}
    KickCD.db.profile.anchors.icons =
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }
    H.FireConfigChanged("general")
    H.FireConfigChanged("icons")
end

-- StaticPopup for "Reset all settings" — irreversible, so confirm
-- before wiping. Helpers.RestoreAllDefaults walks every schema-driven
-- panel and resets each row to def.default; Database:ResetAllSpells
-- additionally rebuilds the per-class+spec spell lists from the addon
-- defaults so the user actually gets a "true" reset across every spec
-- (not just the one selected in the Spells editor). Profiles are still
-- left alone — they have their own destructive controls.
StaticPopupDialogs["KICKCD_RESET_ALL"] = {
    text         = L["Reset every schema-driven setting (General, Icons, Cast bar) AND every spec's spell list to addon defaults? The active profile is the only one affected."],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function()
        H.RestoreAllDefaults()
        if KickCD.Database and KickCD.Database.ResetAllSpells then
            KickCD.Database:ResetAllSpells()
        end
    end,
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
                H.InlineButtonPair(ctxRef,
                    {
                        text    = L["Reset position"],
                        tooltip = L["Restore the icon grid to its default screen position."],
                        onClick = resetPosition,
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

if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("general", Build)
end
