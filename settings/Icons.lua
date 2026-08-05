-- settings/Icons.lua
--
-- Icons canvas panel. Pure schema: every widget is a row in
-- KickCD.Settings.Schema; the builder just calls Helpers.RenderSchema.
-- Adding a new icons-section option means adding one schema row here.

local addonName, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Schema = NS.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

-- Per-unit row generation ---------------------------------------------
-- Every row below is built once per unit in NS.Units.LIST (target,
-- focus): the row's `path` is prefixed with "units.<unit>." and tagged
-- `unit = unit` so Helpers.SchemaForPanel/RenderSchema can filter to
-- only the currently-selected unit's rows (Panel.lua). `section` stays
-- "icons" for every row — both grids react to an `icons` CONFIG_CHANGED
-- and resolve their own unit's data via NS.Units.Icons(unit).
local function addUnitRows(unit)

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

-- Frame-anchor dropdown options. Sourced from H.AnchorValues so the
-- Icons grid anchor and the Cast bar position anchors share an
-- identical 13-option list. The IconGrid's parseAnchor / placeBlock
-- accept both the new `_MIDDLE` value tokens and legacy `_CENTER`
-- tokens (older saved profiles).
local ANCHOR_VALUES = H.AnchorValues()
local ANCHOR_VALUES_ORDER = H.AnchorOrder()

local GROW_VALUES = {
    ["right_down"] = L["First right then down"],
    ["right_up"] = L["First right then up"],
    ["left_down"] = L["First left then down"],
    ["left_up"] = L["First left then up"],
    ["down_right"] = L["First down then right"],
    ["down_left"] = L["First down then left"],
    ["up_right"] = L["First up then right"],
    ["up_left"] = L["First up then left"],
}
local GROW_VALUES_ORDER = {
    "right_down",
    "right_up",
    "left_down",
    "left_up",
    "down_right",
    "down_left",
    "up_right",
    "up_left",
}

-- Sizing -------------------------------------------------------------
add{
    panel = "icons", section = "icons", unit = unit, group = L["Sizing"],
    path  = "units."..unit..".icons.primarySize", type = "number",
    label = L["Primary size (in px)"],
    desc = L["Pixel size of the primary interrupt icon."],
    default = 64, min = 24, max = 96, step = 2, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Sizing"],
    path  = "units."..unit..".icons.secondarySize", type = "number",
    label = L["Secondary size"],
    desc = L["Secondary icon size as a fraction of the primary."],
    default = 0.5, min = 0.4, max = 1.0, step = 0.05, fmt = "%.2f",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Sizing"],
    path  = "units."..unit..".icons.gap", type = "number",
    label = L["Gap (in px)"],
    desc = L["Pixel gap between adjacent icons."],
    default = 0, min = 0, max = 24, step = 1, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Sizing"],
    path  = "units."..unit..".icons.zoom", type = "number",
    label = L["Icon zoom"],
    desc = L["Crop the inner area of each icon (0 = no crop, 0.25 = aggressive crop to remove the Blizzard border)."],
    default = 0.10, min = 0.0, max = 0.25, step = 0.01, fmt = "%.2f",
}

-- Layout -------------------------------------------------------------
add{
    panel = "icons", section = "icons", unit = unit, group = L["Layout"],
    path  = "units."..unit..".icons.anchor", type = "string",
    label = L["Anchor point (of secondary icons relative to primary)"],
    desc = L["Side and alignment of the primary icon the secondary block attaches to."],
    default = "RIGHT_MIDDLE",
    values  = ANCHOR_VALUES, sorting = ANCHOR_VALUES_ORDER,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Layout"],
    path  = "units."..unit..".icons.secondaryGrow", type = "string",
    label = L["Growth direction (of secondary icons)"],
    desc = L["Fill order inside the secondary block. The first axis is the within-line direction; the second axis picks which way the next row/column wraps."],
    default = "down_right",
    values  = GROW_VALUES, sorting = GROW_VALUES_ORDER,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Layout"],
    path  = "units."..unit..".icons.secondaryRows", type = "number",
    label = L["Rows"],
    desc = L["Vertical extent of the secondary block — number of horizontal lines stacked up/down."],
    default = 2, min = 1, max = 6, step = 1, fmt = "%d",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Layout"],
    path  = "units."..unit..".icons.secondaryCols", type = "number",
    label = L["Columns"],
    desc = L["Horizontal extent of the secondary block — number of vertical lines arranged left/right."],
    default = 3, min = 1, max = 12, step = 1, fmt = "%d",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Layout"],
    path  = "units."..unit..".icons.secondaryOffsetX", type = "number",
    label = L["X offset (in px)"],
    desc = L["Horizontal pixel shift applied to the secondary block (positive = right, negative = left)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Layout"],
    path  = "units."..unit..".icons.secondaryOffsetY", type = "number",
    label = L["Y offset (in px)"],
    desc = L["Vertical pixel shift applied to the secondary block (positive = down, negative = up)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
}

-- Visual states ------------------------------------------------------
add{
    panel = "icons", section = "icons", unit = unit, group = L["Visual states"],
    path  = "units."..unit..".icons.readyAlpha", type = "number",
    label = L["Ready alpha"],
    desc = L["Icon alpha when the spell is off cooldown."],
    default = 1.0, min = 0.0, max = 1.0, step = 0.05, fmt = "%.2f",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Visual states"],
    path  = "units."..unit..".icons.cooldownAlpha", type = "number",
    label = L["Cooldown alpha"],
    desc = L["Icon alpha while the spell is on cooldown."],
    default = 0.25, min = 0.0, max = 1.0, step = 0.05, fmt = "%.2f",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Visual states"],
    path  = "units."..unit..".icons.cooldownTint", type = "color", hasAlpha = true,
    label = L["Cooldown tint"],
    desc = L["RGB tint applied to icons during cooldown."],
    default = { r = 1, g = 0.4, b = 0.4, a = 1 },
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Visual states"],
    path  = "units."..unit..".icons.suppressGCDSwipe", type = "bool",
    label = L["Suppress GCD swipe + text"],
    desc = L["Hide the cooldown swipe and countdown text during the global cooldown period (≤1.6s remaining). The icon body still pops back to ready alpha/tint regardless of this setting."],
    default = true,
}

-- Border -------------------------------------------------------------
-- Order produces:
--     [Show border] | [Border color]
--     [Border style] | [Border thickness]
add{
    panel = "icons", section = "icons", unit = unit, group = L["Border"],
    path  = "units."..unit..".icons.borderShow", type = "bool",
    label = L["Show border"],
    desc = L["Draw a thin border around each icon."],
    default = true,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Border"],
    path  = "units."..unit..".icons.borderColor", type = "color", hasAlpha = true,
    label = L["Border color"],
    desc = L["Border color (RGBA)."],
    default = { r = 0, g = 0, b = 0, a = 1 },
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Border"],
    path  = "units."..unit..".icons.borderTexture", type = "string",
    label = L["Border style"],
    desc = L["LibSharedMedia border texture (edge style) used to draw each icon's border."],
    default = "Blizzard Tooltip",
    lsm     = "border",
    -- Function so we re-query LSM at click time (more borders may register
    -- after the schema is declared).
    values  = function() return H.LSMValues("border") end,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Border"],
    path  = "units."..unit..".icons.borderSize", type = "number",
    label = L["Border thickness (in px)"],
    desc = L["Border thickness in pixels."],
    default = 2, min = 0, max = 4, step = 1, fmt = "%d px",
}

-- Annotations --------------------------------------------------------
-- Order produces:
--     [Font]               | [Font size]
--     [Font flags]         | [Show tooltip on hover]
--     [Show cooldown text] | [Show charges]
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    path  = "units."..unit..".icons.cooldownTextFont", type = "string",
    label = L["Font"],
    desc = L["Font for the cooldown text overlay."],
    default = "Friz Quadrata TT",
    lsm     = "font",
    -- Function so we re-query LSM at click time (more fonts may register
    -- after the schema is declared).
    values  = function() return H.LSMValues("font") end,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    path  = "units."..unit..".icons.cooldownTextSize", type = "number",
    label = L["Font size"],
    desc = L["Cooldown text size in pixels."],
    default = 14, min = 8, max = 24, step = 1, fmt = "%d",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    path  = "units."..unit..".icons.cooldownTextFlags", type = "string",
    label = L["Font flags"],
    desc = L["Outline / monochrome flags applied to cooldown text."],
    default = "OUTLINE",
    values  = {
        ["NONE"] = L["None"],
        ["OUTLINE"] = L["Outline"],
        ["THICKOUTLINE"] = L["Thick outline"],
        ["MONOCHROME"] = L["Monochrome"],
    },
    sorting = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROME" },
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    path  = "units."..unit..".icons.showTooltip", type = "bool",
    label = L["Show tooltip on hover"],
    desc = L["Show the in-game spell tooltip when hovering over an icon. Only active while the grid is locked — unlock to drag."],
    default = false,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    path  = "units."..unit..".icons.showCooldownText", type = "bool",
    label = L["Show cooldown text"],
    desc = L["Render numeric seconds remaining on each icon."],
    default = true,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    path  = "units."..unit..".icons.showCharges", type = "bool",
    label = L["Show charges"],
    desc = L["Render a charges badge for spells with charges."],
    default = true,
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
    ["never"] = L["Never"],
    ["always"] = L["Always"],
    ["target_casting"] = L["When target is casting"],
    ["target_casting_interruptible"] = L["When target is casting an interruptible spell"],
}
local GLOW_TRIGGER_VALUES_ORDER = {
    "never",
    "always",
    "target_casting",
    "target_casting_interruptible",
}

local GLOW_TYPE_VALUES = {
    ["button"] = L["Button (rotating rays)"],
    ["proc"] = L["Proc (flipbook)"],
    ["pixel"] = L["Pixel border"],
    ["autocast"] = L["Auto cast sparkles"],
}
local GLOW_TYPE_VALUES_ORDER = {
    "button",
    "proc",
    "pixel",
    "autocast",
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
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    path  = "units."..unit..".icons.primaryGlowTrigger", type = "string",
    label = L["Primary glow trigger"],
    desc = L["When to show the glow on the primary icon."],
    default = "never",
    values  = GLOW_TRIGGER_VALUES, sorting = GLOW_TRIGGER_VALUES_ORDER,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    path  = "units."..unit..".icons.secondaryGlowTrigger", type = "string",
    label = L["Secondary glow trigger"],
    desc = L["When to show the glow on secondary icons."],
    default = "never",
    values  = GLOW_TRIGGER_VALUES, sorting = GLOW_TRIGGER_VALUES_ORDER,
}

-- Style row -------------------------------------------------------
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    path  = "units."..unit..".icons.primaryGlowType", type = "string",
    label = L["Primary glow style"],
    desc = L["Visual style of the primary-icon glow. Inert when the trigger is set to Never."],
    default = "pixel",
    values  = GLOW_TYPE_VALUES, sorting = GLOW_TYPE_VALUES_ORDER,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    path  = "units."..unit..".icons.secondaryGlowType", type = "string",
    label = L["Secondary glow style"],
    desc = L["Visual style of secondary-icon glow. Inert when the trigger is set to Never."],
    default = "pixel",
    values  = GLOW_TYPE_VALUES, sorting = GLOW_TYPE_VALUES_ORDER,
}

-- Color row -------------------------------------------------------
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    path  = "units."..unit..".icons.primaryGlowColor", type = "color", hasAlpha = true,
    label = L["Primary glow color"],
    desc = L["Glow color on the primary icon."],
    default = { r = 1, g = 1, b = 0, a = 1 },
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    path  = "units."..unit..".icons.secondaryGlowColor", type = "color", hasAlpha = true,
    label = L["Secondary glow color"],
    desc = L["Glow color on secondary icons."],
    default = { r = 1, g = 1, b = 0, a = 1 },
}

end

for _, u in ipairs(NS.Units.LIST) do addUnitRows(u) end

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
    -- Parked, not wired: the Defaults button doesn't exist until the
    -- panel's first OnShow (H.EnsureDefaultsButton).
    ctx.panel.defaultsOnClick = function()
        H.RestoreDefaults("icons", ctx)
    end

    -- Defer the AceGUI render until the panel becomes visible: build-time
    -- happens at PLAYER_LOGIN when ctx.body has 0 width, and AceGUI lays
    -- children out against the container's current width.
    --
    -- H.RenderUnitPanel (not RenderSchema directly) draws the unit
    -- selector + Focus link/copy header above the schema body and
    -- re-renders the whole thing on every unit switch (Task 8).
    local rendered = false
    ctx.panel:SetScript("OnShow", function()
        H.EnsureDefaultsButton(ctx.panel)
        if rendered then return end
        rendered = true
        H.RenderUnitPanel(ctx, "icons")
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Icons"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("icons", L["Icons"], Build)
end
