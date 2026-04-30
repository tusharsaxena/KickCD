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

-- Layout helpers ----------------------------------------------------
--
-- Layout is built up in three independent steps, picked from three
-- dropdowns/sliders below in order:
--   1. Anchor point — which side+alignment of the primary the secondary
--      block attaches to (12 options).
--   2. Grow direction — fill order inside the block as a compound
--      "<primary>_<secondary>" enum (8 options, all 8 always available).
--   3. Rows × Cols — vertical/horizontal extent of the block.
-- Anchor and grow are orthogonal: any anchor works with any grow.

local ANCHOR_VALUES = {
    { value = "TOP_CENTER",    label = L["Top center"]    },
    { value = "TOP_LEFT",      label = L["Top left"]      },
    { value = "TOP_RIGHT",     label = L["Top right"]     },
    { value = "BOTTOM_CENTER", label = L["Bottom center"] },
    { value = "BOTTOM_LEFT",   label = L["Bottom left"]   },
    { value = "BOTTOM_RIGHT",  label = L["Bottom right"]  },
    { value = "LEFT_CENTER",   label = L["Left center"]   },
    { value = "LEFT_TOP",      label = L["Left top"]      },
    { value = "LEFT_BOTTOM",   label = L["Left bottom"]   },
    { value = "RIGHT_CENTER",  label = L["Right center"]  },
    { value = "RIGHT_TOP",     label = L["Right top"]     },
    { value = "RIGHT_BOTTOM",  label = L["Right bottom"]  },
}

local GROW_VALUES = {
    { value = "right_down", label = L["First right then down"] },
    { value = "right_up",   label = L["First right then up"]   },
    { value = "left_down",  label = L["First left then down"]  },
    { value = "left_up",    label = L["First left then up"]    },
    { value = "down_right", label = L["First down then right"] },
    { value = "down_left",  label = L["First down then left"]  },
    { value = "up_right",   label = L["First up then right"]   },
    { value = "up_left",    label = L["First up then left"]    },
}

-- Sizing -------------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Sizing"],
    path  = "icons.primarySize", type = "number",
    label = L["Primary size (in px)"],
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
    label = L["Gap (in px)"],
    tooltip = L["Pixel gap between adjacent icons."],
    default = 4, min = 0, max = 24, step = 1, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", group = L["Sizing"],
    path  = "icons.zoom", type = "number",
    label = L["Icon zoom"],
    tooltip = L["Crop the inner area of each icon (0 = no crop, 0.25 = aggressive crop to remove the Blizzard border)."],
    default = 0.08, min = 0.0, max = 0.25, step = 0.01, fmt = "%.2f",
}

-- Layout -------------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Layout"],
    path  = "icons.anchor", type = "string",
    label = L["Anchor point"],
    tooltip = L["Side and alignment of the primary icon the secondary block attaches to."],
    default = "RIGHT_CENTER",
    values  = ANCHOR_VALUES,
}
add{
    panel = "icons", section = "icons", group = L["Layout"],
    path  = "icons.secondaryGrow", type = "string",
    label = L["Grow direction"],
    tooltip = L["Fill order inside the secondary block. The first axis is the within-line direction; the second axis picks which way the next row/column wraps."],
    default = "right_down",
    values  = GROW_VALUES,
}
add{
    panel = "icons", section = "icons", group = L["Layout"],
    path  = "icons.secondaryRows", type = "number",
    label = L["Rows"],
    tooltip = L["Vertical extent of the secondary block — number of horizontal lines stacked up/down."],
    default = 1, min = 1, max = 6, step = 1, fmt = "%d",
}
add{
    panel = "icons", section = "icons", group = L["Layout"],
    path  = "icons.secondaryCols", type = "number",
    label = L["Columns"],
    tooltip = L["Horizontal extent of the secondary block — number of vertical lines arranged left/right."],
    default = 6, min = 1, max = 12, step = 1, fmt = "%d",
}
add{
    panel = "icons", section = "icons", group = L["Layout"],
    path  = "icons.secondaryOffsetX", type = "number",
    label = L["X offset (in px)"],
    tooltip = L["Horizontal pixel shift applied to the secondary block (positive = right, negative = left)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", group = L["Layout"],
    path  = "icons.secondaryOffsetY", type = "number",
    label = L["Y offset (in px)"],
    tooltip = L["Vertical pixel shift applied to the secondary block (positive = down, negative = up)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
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

-- Border -------------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Border"],
    path  = "icons.borderShow", type = "bool",
    label = L["Show border"],
    tooltip = L["Draw a thin border around each icon."],
    default = false,
}
add{
    panel = "icons", section = "icons", group = L["Border"],
    path  = "icons.borderColor", type = "color",
    label = L["Border color"],
    tooltip = L["Border color (RGBA)."],
    default = { 0, 0, 0, 1 },
}
add{
    panel = "icons", section = "icons", group = L["Border"],
    path  = "icons.borderSize", type = "number",
    label = L["Border thickness (in px)"],
    tooltip = L["Border thickness in pixels."],
    default = 1, min = 0, max = 4, step = 1, fmt = "%d px",
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
    path  = "icons.cooldownTextFlags", type = "string",
    label = L["Font flags"],
    tooltip = L["Outline / monochrome flags applied to cooldown text."],
    default = "OUTLINE",
    values  = {
        { value = "NONE",         label = L["None"]          },
        { value = "OUTLINE",      label = L["Outline"]       },
        { value = "THICKOUTLINE", label = L["Thick outline"] },
        { value = "MONOCHROME",   label = L["Monochrome"]    },
    },
}
add{
    panel = "icons", section = "icons", group = L["Annotations"],
    path  = "icons.showCharges", type = "bool",
    label = L["Show charges"],
    tooltip = L["Render a charges badge for spells with charges."],
    default = true,
}
add{
    panel = "icons", section = "icons", group = L["Annotations"],
    path  = "icons.showTooltip", type = "bool",
    label = L["Show tooltip on hover"],
    tooltip = L["Show the in-game spell tooltip when hovering over an icon. Only active while the grid is locked — unlock to drag."],
    default = false,
}

-- Ready glow ---------------------------------------------------------
-- Per-slot glow with two orthogonal dropdowns:
--
--   * Trigger — WHEN the glow fires:
--       - "never"                       : glow off
--       - "always"                      : whenever the spell is ready
--       - "target_casting"              : ready AND target is casting
--       - "target_casting_interruptible": ready AND target is casting
--                                         an interruptible spell
--
--   * Type — WHICH visual is rendered (LibCustomGlow effects):
--       - "button"   : Blizzard rotating rays + spark
--       - "proc"     : Modern Blizzard proc flipbook
--       - "pixel"    : Animated pixel-art border
--       - "autocast" : Pet auto-cast sparkle particles
--
-- Color is a single RGBA tuple shared across types (each LCG function
-- accepts the same {r,g,b,a} shape). Primary and secondary icons each
-- get their own trigger + type + color.

local GLOW_TRIGGER_VALUES = {
    { value = "never",                       label = L["Never"]                                       },
    { value = "always",                      label = L["Always"]                                      },
    { value = "target_casting",              label = L["When target is casting"]                      },
    { value = "target_casting_interruptible", label = L["When target is casting an interruptible spell"] },
}

local GLOW_TYPE_VALUES = {
    { value = "button",   label = L["Button (rotating rays)"] },
    { value = "proc",     label = L["Proc (flipbook)"]        },
    { value = "pixel",    label = L["Pixel border"]           },
    { value = "autocast", label = L["Auto cast sparkles"]     },
}

-- Schema rows are interleaved primary/secondary so the two-column
-- renderer in settings/Panel.lua (Helpers.RenderSchema, pairs adjacent
-- entries into a Flow row) produces a layout where the left column is
-- the primary slot's controls and the right column mirrors it on the
-- secondary slot:
--
--   Primary glow trigger | Secondary glow trigger
--   Primary glow style   | Secondary glow style
--   Primary glow color   | Secondary glow color

-- Trigger row -----------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Ready glow"],
    path  = "icons.primaryGlowTrigger", type = "string",
    label = L["Primary glow trigger"],
    tooltip = L["When to show the glow on the primary icon."],
    default = "never",
    values  = GLOW_TRIGGER_VALUES,
}
add{
    panel = "icons", section = "icons", group = L["Ready glow"],
    path  = "icons.secondaryGlowTrigger", type = "string",
    label = L["Secondary glow trigger"],
    tooltip = L["When to show the glow on secondary icons."],
    default = "never",
    values  = GLOW_TRIGGER_VALUES,
}

-- Style row -------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Ready glow"],
    path  = "icons.primaryGlowType", type = "string",
    label = L["Primary glow style"],
    tooltip = L["Visual style of the primary-icon glow. Inert when the trigger is set to Never."],
    default = "proc",
    values  = GLOW_TYPE_VALUES,
}
add{
    panel = "icons", section = "icons", group = L["Ready glow"],
    path  = "icons.secondaryGlowType", type = "string",
    label = L["Secondary glow style"],
    tooltip = L["Visual style of secondary-icon glow. Inert when the trigger is set to Never."],
    default = "proc",
    values  = GLOW_TYPE_VALUES,
}

-- Color row -------------------------------------------------------
add{
    panel = "icons", section = "icons", group = L["Ready glow"],
    path  = "icons.primaryGlowColor", type = "color",
    label = L["Primary glow color"],
    tooltip = L["Glow color on the primary icon."],
    default = { 0.95, 0.95, 0.32, 1 },
}
add{
    panel = "icons", section = "icons", group = L["Ready glow"],
    path  = "icons.secondaryGlowColor", type = "color",
    label = L["Secondary glow color"],
    tooltip = L["Glow color on secondary icons."],
    default = { 0.95, 0.95, 0.32, 1 },
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
