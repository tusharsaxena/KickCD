-- settings/Icons.lua
--
-- Icons canvas panel. Pure schema: every widget is a row in
-- KickCD.Settings.Schema; the builder calls Helpers.RenderUnitPanel, which
-- pins the Unit picker into the page's chrome band and hands the rows to
-- Helpers.RenderTabbedSchema -- six tabs (Sizing, Layout, Visual states,
-- Border, Annotations, Ready glow), partitioned from `group` in declaration
-- order (options-ui-§13). Adding an option means adding one row INSIDE the run
-- its group already owns: a row filed after the array has left that group
-- prints the tab a second time further down.
--
-- The border block, the annotation font block and all three color swatches are
-- COMPOSED (libs/LibKa0s/OptionsCompose.lua), not written out: options-ui-§16
-- and §17 make the row set, its order and the class-color companion the
-- collection's rather than this page's. H.AddComposed stamps the host's own
-- `panel` / `section` / `unit` onto what comes back and appends it in place.

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

-- The two arguments every composed block on this page takes: where its stored
-- paths hang, and the host row fields H.AddComposed stamps onto what comes back
-- (settings/Panel.lua). Hoisted per unit so no composer call restates them.
local PREFIX = "units." .. unit .. ".icons."
local STAMP  = { panel = "icons", section = "icons", unit = unit }

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
-- The cooldown tint and its class-color companion (options-ui-§17). Composed
-- rather than hand-paired, because the composer sets `startsLine` on the swatch:
-- the pair then cannot be split across two lines by an odd number of widgets
-- above it, which is what "immediately to its right" actually requires.
--
-- classColorSource = "player", and THE PATH DOES NOT DECIDE THAT. Every icon on
-- this grid lives under `units.<unit>.` and draws the PLAYER'S OWN interrupt
-- cooldowns -- modules/Cooldowns.lua's ResolveClassSpec and
-- modules/IconGrid.lua's getActiveSpecKey both key the watched list on
-- UnitClass("player") -- so the class this tint means is the player's, on the
-- Focus page exactly as on the Target one.
H.AddComposed(H.ColorPair{
    prefix     = PREFIX,   page  = "icons", group = L["Visual states"],
    key        = "cooldownTint", label = L["Cooldown tint"],
    defaults   = { cooldownTint = { r = 1, g = 0.4, b = 0.4, a = 1 } },
    classColor = { source = "player" },
}, STAMP)
add{
    panel = "icons", section = "icons", unit = unit, group = L["Visual states"],
    path  = "units."..unit..".icons.suppressGCDSwipe", type = "bool",
    label = L["Suppress GCD swipe + text"],
    desc = L["Hide the cooldown swipe and countdown text during the global cooldown period (1.6s remaining or less). The icon body still pops back to ready alpha/tint regardless of this setting."],
    default = true,
}

-- Border -------------------------------------------------------------
-- The canonical border block (options-ui-§16), composed. Four mandated rows,
-- led by this addon's own Show-border toggle (`spec.show`):
--     [Show border]
--     [Border style]  | [Border thickness (px)]
--     [Border color]  | [Use class color]
--
-- `keys` keeps the SHIPPED path: this addon has always stored the edge texture
-- at `icons.borderTexture`, and the composer must not change what is stored.
-- The border is drawn around the player's own cooldown icons, so it is
-- player-scoped for the same reason the cooldown tint above is.
H.AddComposed(H.BorderGroup{
    prefix   = PREFIX, page = "icons", group = L["Border"],
    show     = true,
    keys     = { borderStyle = "borderTexture" },
    defaults = {
        borderShow  = true,
        borderStyle = "Blizzard Tooltip",
        borderSize  = 2,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
    },
    classColor = { source = "player" },
}, STAMP)

-- Annotations --------------------------------------------------------
-- Everything drawn ON TOP of an icon: the countdown, the charges badge and the
-- hover tooltip. Three kinds of control on one tab, so each carries a subsection
-- heading (options-ui-§7) -- the tab label names the section, the headings name
-- what each block is:
--     Icon     [Show cooldown text] | [Show tooltip on hover]
--     Font     [Font]               | [Font size]
--              [Font color]         | [Use class color]
--              [Font flags]         | [Font shadow]
--     Charges  [Show charges]
--              [Charges X offset]   | [Charges Y offset]
--
-- The font block is R1d's canonical six (options-ui-§16), so it brings a font
-- COLOR and a font SHADOW this addon did not have. Both are honored:
-- modules/IconGrid_Render.lua's ApplyTextConfig paints and shadows the countdown
-- FontString from them.
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    subgroup = L["Icon"],
    path  = "units."..unit..".icons.showCooldownText", type = "bool",
    label = L["Show cooldown text"],
    desc = L["Render numeric seconds remaining on each icon."],
    default = true,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    subgroup = L["Icon"],
    path  = "units."..unit..".icons.showTooltip", type = "bool",
    label = L["Show tooltip on hover"],
    desc = L["Show the in-game spell tooltip when hovering over an icon. Only active while the grid is locked — unlock to drag."],
    default = false,
}

-- `keys` on all six leaves, because every one of them already had a stored name
-- on this page and the composer must not change what is stored. Two are NEW
-- settings rather than renames -- cooldownTextColor and cooldownTextShadow --
-- and they are the reason the block is contiguous and complete rather than the
-- five rows the screenshot showed.
H.AddComposed(H.FontGroup{
    prefix = PREFIX, page = "icons", group = L["Annotations"],
    subgroup = L["Font"],
    keys = {
        font              = "cooldownTextFont",
        fontSize          = "cooldownTextSize",
        fontColor         = "cooldownTextColor",
        useClassColorFont = "useClassColorCooldownText",
        fontFlags         = "cooldownTextFlags",
        fontShadow        = "cooldownTextShadow",
    },
    defaults = {
        font       = "Friz Quadrata TT",
        fontSize   = 14,
        fontColor  = { r = 1, g = 1, b = 1, a = 1 },
        fontFlags  = "OUTLINE",
        fontShadow = false,
    },
    classColor = { source = "player" },
}, STAMP)

-- The charges badge's inset from the icon's bottom-right corner. Promoted out
-- of modules/IconGrid_Render.lua, where it was the hardcoded
-- `SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)` and nothing else. The
-- defaults ARE those two numbers, so a profile that touches neither row draws
-- exactly the badge it drew before; a border or an aggressive icon zoom is
-- what makes the stock inset wrong, and both of those are settings on this
-- same page. Two literals, two questions, two rows — collapsing them into one
-- "badge inset" slider would answer neither.
--
-- `solo` on the toggle so the two offsets read ACROSS one line rather than the
-- first of them pairing with the toggle that governs whether the badge exists.
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    subgroup = L["Charges"],
    path  = "units."..unit..".icons.showCharges", type = "bool",
    label = L["Show charges"],
    desc = L["Render a charges badge for spells with charges."],
    default = true,
    solo    = true,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    subgroup = L["Charges"],
    path  = "units."..unit..".icons.chargesOffsetX", type = "number",
    label = L["Charges X offset (in px)"],
    desc = L["Horizontal pixel shift of the charges badge from the icon's bottom-right corner (positive = right)."],
    default = -2, min = -32, max = 32, step = 1, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    subgroup = L["Charges"],
    path  = "units."..unit..".icons.chargesOffsetY", type = "number",
    label = L["Charges Y offset (in px)"],
    desc = L["Vertical pixel shift of the charges badge from the icon's bottom-right corner (positive = up)."],
    default = 2, min = -32, max = 32, step = 1, fmt = "%d px",
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

-- Color rows ------------------------------------------------------
-- The two swatches STOP mirroring each other across a line here, and that is
-- the rule rather than a slip: options-ui-§17 puts the class-color companion
-- IMMEDIATELY to the swatch's right, so each glow color takes a line of its own
-- with its companion beside it:
--     [Primary glow color]   | [Use class color]
--     [Secondary glow color] | [Use class color]
--
-- Player-scoped, for the reason the cooldown tint above gives: a ready glow
-- fires on the PLAYER'S OWN interrupt being off cooldown. The tracked unit's
-- class has nothing to do with it, whichever unit's page you are on.
H.AddComposed(H.ColorPair{
    prefix     = PREFIX, page = "icons", group = L["Ready glow"],
    key        = "primaryGlowColor", label = L["Primary glow color"],
    defaults   = { primaryGlowColor = { r = 1, g = 1, b = 0, a = 1 } },
    classColor = { source = "player" },
}, STAMP)
H.AddComposed(H.ColorPair{
    prefix     = PREFIX, page = "icons", group = L["Ready glow"],
    key        = "secondaryGlowColor", label = L["Secondary glow color"],
    defaults   = { secondaryGlowColor = { r = 1, g = 1, b = 0, a = 1 } },
    classColor = { source = "player" },
}, STAMP)

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
        pageKey        = "icons",
        defaultsButton = true,
    })
    -- Parked, not wired: the Defaults button doesn't exist until the
    -- panel's first OnShow (H.EnsureDefaultsButton).
    ctx.panel.defaultsOnClick = function()
        H.RestoreDefaults("icons", ctx)
    end

    -- The library owns WHEN this draws (H.SetRenderer): first show, and again
    -- when a refresh marked it dirty while it was hidden — which is what makes
    -- the General page's Focus styling link reach this page at all. Building at
    -- registration time would lay the widgets out against a zero-width body,
    -- because registration happens at PLAYER_LOGIN.
    --
    -- H.RenderUnitPanel (not RenderTabbedSchema directly) pins the Unit picker
    -- into the page's chrome band ABOVE the tab strip and then hands over
    -- (settings/Panel_Render.lua).
    H.SetRenderer(ctx, function(c) H.RenderUnitPanel(c, "icons") end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Icons"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("icons", L["Icons"], Build)
end
