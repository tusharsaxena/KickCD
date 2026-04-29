-- settings/Icons.lua — KickCD v0.1
--
-- Icons canvas panel. Pure schema: every widget is a row in
-- KickCD.Settings.Schema; the builder just calls Helpers.RenderSchema.
-- Adding a new icons-section option means adding one schema row here.

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L
local H      = KickCD.Settings.Helpers
local Schema = KickCD.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

-- Sizing -------------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Sizing"],
    path  = "icons.primarySize", type = "number",
    label = L["Primary size"],
    tooltip = L["Pixel size of the primary interrupt icon."],
    default = 48, min = 24, max = 96, step = 2, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", group = L["Sizing"],
    path  = "icons.secondarySize", type = "number",
    label = L["Secondary size"],
    tooltip = L["Secondary icon size as a fraction of the primary."],
    default = 0.7, min = 0.4, max = 1.0, step = 0.05, fmt = "%.2f",
}
add{
    panel = "icons", section = "icons", group = L["Sizing"],
    path  = "icons.gap", type = "number",
    label = L["Gap"],
    tooltip = L["Pixel gap between adjacent icons."],
    default = 4, min = 0, max = 24, step = 1, fmt = "%d px",
}

-- Layout -------------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Layout"],
    path  = "icons.layout", type = "string",
    label = L["Layout"],
    tooltip = L["Arrange icons horizontally or vertically."],
    default = "horizontal",
    values  = {
        { value = "horizontal", label = L["Horizontal"] },
        { value = "vertical",   label = L["Vertical"]   },
    },
}
add{
    panel = "icons", section = "icons", group = L["Layout"],
    path  = "icons.primaryAnchor", type = "string",
    label = L["Primary anchor"],
    tooltip = L["Where the primary icon sits relative to the secondaries."],
    default = "left",
    values  = {
        { value = "left",   label = L["Left"]   },
        { value = "right",  label = L["Right"]  },
        { value = "top",    label = L["Top"]    },
        { value = "bottom", label = L["Bottom"] },
    },
}

-- Visual states ------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Visual states"],
    path  = "icons.readyAlpha", type = "number",
    label = L["Ready alpha"],
    tooltip = L["Icon alpha when the spell is off cooldown."],
    default = 1.0, min = 0.0, max = 1.0, step = 0.05, fmt = "%.2f",
}
add{
    panel = "icons", section = "icons", group = L["Visual states"],
    path  = "icons.cooldownAlpha", type = "number",
    label = L["Cooldown alpha"],
    tooltip = L["Icon alpha while the spell is on cooldown."],
    default = 0.4, min = 0.0, max = 1.0, step = 0.05, fmt = "%.2f",
}
add{
    panel = "icons", section = "icons", group = L["Visual states"],
    path  = "icons.cooldownTint", type = "color",
    label = L["Cooldown tint"],
    tooltip = L["RGB tint applied to icons during cooldown."],
    default = { 1, 0.4, 0.4, 1 },
}

-- Annotations --------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Annotations"],
    path  = "icons.showCooldownText", type = "bool",
    label = L["Show cooldown text"],
    tooltip = L["Render numeric seconds remaining on each icon."],
    default = false,
}
add{
    panel = "icons", section = "icons", group = L["Annotations"],
    path  = "icons.cooldownTextFont", type = "string",
    label = L["Font"],
    tooltip = L["Font for the cooldown text overlay."],
    default = "Friz Quadrata TT",
    -- Function so we re-query LSM at click time (more fonts may register
    -- after the schema is declared).
    values  = function() return H.LSMValues("font") end,
}
add{
    panel = "icons", section = "icons", group = L["Annotations"],
    path  = "icons.cooldownTextSize", type = "number",
    label = L["Font size"],
    tooltip = L["Cooldown text size in pixels."],
    default = 14, min = 8, max = 24, step = 1, fmt = "%d",
}
add{
    panel = "icons", section = "icons", group = L["Annotations"],
    path  = "icons.showCharges", type = "bool",
    label = L["Show charges"],
    tooltip = L["Render a charges badge for spells with charges."],
    default = true,
}

-- ---------------------------------------------------------------------
-- Builder
-- ---------------------------------------------------------------------

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end

    local ctx
    ctx = H.CreatePanel("KickCDIconsPanel", L["Icons"], {
        panelKey       = "icons",
        defaultsButton = true,
    })
    if ctx.panel.defaultsBtn then
        ctx.panel.defaultsBtn:SetCallback("OnClick", function()
            H.RestoreDefaults("icons", ctx)
        end)
    end

    -- Defer the AceGUI render until the panel becomes visible: build-time
    -- happens at PLAYER_LOGIN when ctx.body has 0 width, and AceGUI lays
    -- children out against the container's current width.
    local rendered = false
    ctx.panel:SetScript("OnShow", function()
        if rendered then return end
        rendered = true
        H.RenderSchema(ctx, "icons")
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Icons"])
end

if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("icons", Build)
end
