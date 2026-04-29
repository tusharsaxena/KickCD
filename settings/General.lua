-- settings/General.lua — KickCD v0.1
--
-- General canvas panel. Declares its schema entries (master enable,
-- lock, master scale/alpha, debug log) and registers a builder that
-- renders them via Helpers.RenderSchema. The "Reset position" action
-- is appended manually because anchors live outside the simple
-- key=value space the schema covers.
--
-- Every schema entry here is automatically wired into /kcd get|set,
-- so adding a new General option = one row in this file.

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L
local H      = KickCD.Settings.Helpers
local Schema = KickCD.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "enabled",  type    = "bool",
    label    = L["Enable KickCD"],
    tooltip  = L["Master enable for the addon."],
    default  = true,
}

add{
    panel    = "general",  section = "general",  group = L["Master controls"],
    path     = "locked",   type    = "bool",
    label    = L["Lock frame"],
    tooltip  = L["When unlocked, you can drag the icon grid to reposition it."],
    default  = true,
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

add{
    panel    = "general",  section = "general",  group = L["Debug"],
    path     = "debugLog", type    = "bool",
    label    = L["Internal-message logging"],
    tooltip  = L["Print every internal message to chat. Useful for diagnosing module wiring."],
    default  = false,
    onChange = function(v) KickCD._debugLog = v and true or false end,
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
        ctx.panel.defaultsBtn:SetScript("OnClick", function()
            H.RestoreDefaults("general", ctx)
        end)
    end

    H.RenderSchema(ctx, "general")

    H.Section(ctx, L["Position"])
    H.Button(ctx,
        L["Reset position"], L["Reset"],
        L["Restore the icon grid to its default screen position."],
        resetPosition)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["General"])
end

if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("general", Build)
end
