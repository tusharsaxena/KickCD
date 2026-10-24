-- settings/Icons.lua
--
-- The Grid page's Icons entry (KickCD#33). Pure schema: every widget is a row in
-- KickCD.Settings.Schema; the Grid page (settings/Grid.lua) draws it through
-- Helpers.RenderGridPage, which pins the Unit picker into the band, draws the rail, and hands the rows to
-- Helpers.RenderTabbedSchema -- four tabs (Size and layout, Appearance,
-- Annotations, Ready glow; item 020 merged Sizing with Layout and Visual states
-- with Border), partitioned from `group` in declaration order (options-ui-§13). Adding an option means adding one row INSIDE the run
-- its group already owns: a row filed after the array has left that group
-- prints the tab a second time further down.
--
-- The border block, the annotation font block and all three color swatches are
-- COMPOSED (libs/LibKa0s/OptionsCompose.lua), not written out: options-ui-§16
-- and options-ui-§17 make the row set, its order and the class-color companion the
-- collection's rather than this page's. H.AddComposed stamps the host's own
-- `panel` / `section` / `unit` onto what comes back and appends it in place.

local _, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Store  = NS.Settings.Store

-- Through the seam's registry (settings/SchemaSetup.lua), so Store.FindRow
-- indexes the row the moment it lands.
local function add(t) Store.AddRows({ t }) end

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

-- Size and layout ----------------------------------------------------
-- ONE TAB since item 020 (KIC-L08): how big the block is and where it sits is
-- one question, and the Cast bar entry already answers its own version on one
-- "Size and position" tab. Two subjects, so two subsection headings
-- (options-ui-§7):
--     Size             [Primary size (px)]          | [Secondary size (fraction of primary)]
--                      [Gap (px)]                   | [Icon zoom]
--     Secondary block  [Primary icon anchor point]  | [Growth direction]
--                      [Rows]                       | [Columns]
--                      [X offset (px)]              | [Y offset (px, positive = down)]
-- The Secondary block heading carries the context the two long labels used to
-- spell out in parentheses (KIC-L09).
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Size"],
    path  = "units."..unit..".icons.primarySize", type = "number",
    label = L["Primary size (px)"],
    desc = L["Pixel size of the primary interrupt icon."],
    default = 64, min = 24, max = 96, step = 2, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Size"],
    path  = "units."..unit..".icons.secondarySize", type = "number",
    label = L["Secondary size (fraction of primary)"],
    desc = L["Secondary icon size as a fraction of the primary."],
    default = 0.5, min = 0.4, max = 1.0, step = 0.05, fmt = "%.2f",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Size"],
    path  = "units."..unit..".icons.gap", type = "number",
    label = L["Gap (px)"],
    desc = L["Pixel gap between adjacent icons."],
    default = 0, min = 0, max = 24, step = 1, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Size"],
    path  = "units."..unit..".icons.zoom", type = "number",
    label = L["Icon zoom"],
    desc = L["Crop the inner area of each icon (0 = no crop, 0.25 = aggressive crop to remove the Blizzard border)."],
    default = 0.10, min = 0.0, max = 0.25, step = 0.01, fmt = "%.2f",
}

add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Secondary block"],
    path  = "units."..unit..".icons.anchor", type = "string",
    label = L["Primary icon anchor point"],
    desc = L["Side and alignment of the primary icon the secondary block attaches to."],
    default = "RIGHT_MIDDLE",
    values  = ANCHOR_VALUES, sorting = ANCHOR_VALUES_ORDER,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Secondary block"],
    path  = "units."..unit..".icons.secondaryGrow", type = "string",
    label = L["Growth direction"],
    desc = L["Fill order inside the secondary block. The first axis is the within-line direction; the second axis picks which way the next row/column wraps."],
    default = "down_right",
    values  = GROW_VALUES, sorting = GROW_VALUES_ORDER,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Secondary block"],
    path  = "units."..unit..".icons.secondaryRows", type = "number",
    label = L["Rows"],
    desc = L["Vertical extent of the secondary block — number of horizontal lines stacked up/down."],
    default = 2, min = 1, max = 6, step = 1, fmt = "%d",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Secondary block"],
    path  = "units."..unit..".icons.secondaryCols", type = "number",
    label = L["Columns"],
    desc = L["Horizontal extent of the secondary block — number of vertical lines arranged left/right."],
    default = 3, min = 1, max = 12, step = 1, fmt = "%d",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Secondary block"],
    path  = "units."..unit..".icons.secondaryOffsetX", type = "number",
    label = L["X offset (px)"],
    desc = L["Horizontal pixel shift applied to the secondary block (positive = right, negative = left)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Size and layout"],
    subgroup = L["Secondary block"],
    path  = "units."..unit..".icons.secondaryOffsetY", type = "number",
    -- The sign is the opposite of every other Y slider in the addon
    -- (IconGrid_Layout.lua: positive = down), and only the label can warn
    -- without a behavior change (KIC-L11).
    label = L["Y offset (px, positive = down)"],
    desc = L["Vertical pixel shift applied to the secondary block (positive = down, negative = up)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
}

-- Appearance -----------------------------------------------------------
-- ONE TAB since item 020 (KIC-L12): Visual states and Border were two five-row
-- tabs about how one icon looks. Two subjects, two headings (options-ui-§7):
--     States  [Ready opacity]  | [Cooldown opacity]
--             [Cooldown tint]  | [Use class color]
--             [Suppress GCD swipe and text]
--     Border  the composed block, unchanged
add{
    panel = "icons", section = "icons", unit = unit, group = L["Appearance"],
    subgroup = L["States"],
    path  = "units."..unit..".icons.readyAlpha", type = "number",
    label = L["Ready opacity"],
    desc = L["Icon alpha when the spell is off cooldown."],
    default = 1.0, min = 0.0, max = 1.0, step = 0.05, fmt = "%.2f",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Appearance"],
    subgroup = L["States"],
    path  = "units."..unit..".icons.cooldownAlpha", type = "number",
    label = L["Cooldown opacity"],
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
    prefix     = PREFIX,   page  = "icons", group = L["Appearance"],
    subgroup   = L["States"],
    key        = "cooldownTint", label = L["Cooldown tint"],
    defaults   = { cooldownTint = { r = 1, g = 0.4, b = 0.4, a = 1 } },
    classColor = { source = "player" },
}, STAMP)
add{
    panel = "icons", section = "icons", unit = unit, group = L["Appearance"],
    subgroup = L["States"],
    path  = "units."..unit..".icons.suppressGCDSwipe", type = "bool",
    label = L["Suppress GCD swipe and text"],
    desc = L["Hide the cooldown swipe and countdown text during the global cooldown period (1.6s remaining or less). The icon body still pops back to ready alpha/tint regardless of this setting."],
    default = true,
}

-- Appearance > Border ---------------------------------------------------
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
    prefix   = PREFIX, page = "icons", group = L["Appearance"],
    subgroup = L["Border"],
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
-- hover tooltip. Three subjects on one tab, so each carries a subsection heading
-- (options-ui-§7) -- the tab label names the section, the headings name what
-- each block is (item 020, KIC-L14: the font heading names the text it styles,
-- and that text's switch heads its own block):
--     Cooldown text  [Show cooldown text]                       (solo)
--                    [Font]               | [Font size]
--                    [Font color]         | [Use class color]
--                    [Font flags]         | [Font shadow]
--     Charges        [Show charges]                             (solo)
--                    [Charges X offset]   | [Charges Y offset]
--     Tooltip        [Show tooltip on hover]
-- The font block styles the countdown only: the charges badge is
-- NumberFontNormal (modules/IconGrid_Render.lua).
--
-- The font block is R1d's canonical six (options-ui-§16), so it brings a font
-- COLOR and a font SHADOW this addon did not have. Both are honored:
-- modules/IconGrid_Render.lua's ApplyTextConfig paints and shadows the countdown
-- FontString from them.
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    subgroup = L["Cooldown text"],
    path  = "units."..unit..".icons.showCooldownText", type = "bool",
    label = L["Show cooldown text"],
    desc = L["Render numeric seconds remaining on each icon."],
    default = true,
    solo    = true,
}

-- `keys` on all six leaves, because every one of them already had a stored name
-- on this page and the composer must not change what is stored. Two are NEW
-- settings rather than renames -- cooldownTextColor and cooldownTextShadow --
-- and they are the reason the block is contiguous and complete rather than the
-- five rows the screenshot showed.
H.AddComposed(H.FontGroup{
    prefix = PREFIX, page = "icons", group = L["Annotations"],
    subgroup = L["Cooldown text"],
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
    label = L["Charges X offset (px)"],
    desc = L["Horizontal pixel shift of the charges badge from the icon's bottom-right corner (positive = right)."],
    default = -2, min = -32, max = 32, step = 1, fmt = "%d px",
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    subgroup = L["Charges"],
    path  = "units."..unit..".icons.chargesOffsetY", type = "number",
    label = L["Charges Y offset (px)"],
    desc = L["Vertical pixel shift of the charges badge from the icon's bottom-right corner (positive = up)."],
    default = 2, min = -32, max = 32, step = 1, fmt = "%d px",
}
-- Interaction rather than something drawn on the icon, so its own heading
-- rather than a pairing with the cooldown text's switch (KIC-L14).
add{
    panel = "icons", section = "icons", unit = unit, group = L["Annotations"],
    subgroup = L["Tooltip"],
    path  = "units."..unit..".icons.showTooltip", type = "bool",
    label = L["Show tooltip on hover"],
    desc = L["Show the in-game spell tooltip when hovering over an icon. Only active while the grid is locked — unlock to drag."],
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
-- get their own trigger + type + color, and their own copy of every
-- style's knobs (core/Constants.lua's Const.GLOW_KNOBS), only the chosen
-- style's read.

local GLOW_TRIGGER_VALUES = {
    ["never"] = L["Never"],
    ["always"] = L["Always"],
    ["target_casting"] = L["When the tracked unit is casting"],
    ["target_casting_interruptible"] = L["When the tracked unit is casting an interruptible spell"],
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
-- secondary slot. The tab mixes kinds of control -- what fires the glow,
-- then each style's own knobs -- so every row carries a subsection
-- heading (options-ui-§7), and each style's heading is that style's own
-- name in the Style dropdown:
--
--   Effect                  Primary glow trigger | Secondary glow trigger
--                           Primary glow style   | Secondary glow style
--                           Primary glow color   | Use class color
--                           Secondary glow color | Use class color
--   Button (rotating rays)  Primary frequency    | Secondary frequency
--   Proc (flipbook)         duration, start animation
--   Pixel border            lines, frequency, length, thickness, border
--   Auto cast sparkles      particles, frequency, scale
--   Offset                  X offset, Y offset (pixel, auto cast and proc)

-- A slot's own trigger and style, read live, for its rows' `disabledIf`
-- predicates. The panel re-runs them on every write, so a style or trigger
-- change re-dims the tab on the same frame.
local function slotGlow(slot)
    local get = Store.Get
    return get(PREFIX .. slot .. "GlowTrigger"), get(PREFIX .. slot .. "GlowType")
end

--- The style row is dimmed while its slot's trigger is Never: nothing glows.
local function styleOff(slot)
    return function() return (slotGlow(slot)) == "never" end
end

--- A knob row is dimmed while its slot glows not at all, or in a style the
--- knob does not apply to (Const.GLOW_KNOBS' `styles`).
local function knobOff(slot, styles)
    return function()
        local trigger, kind = slotGlow(slot)
        return trigger == "never" or not styles[kind]
    end
end

-- Trigger row -----------------------------------------------------
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    subgroup = L["Effect"],
    path  = "units."..unit..".icons.primaryGlowTrigger", type = "string",
    label = L["Primary glow trigger"],
    desc = L["When to show the glow on the primary icon."],
    default = "never",
    values  = GLOW_TRIGGER_VALUES, sorting = GLOW_TRIGGER_VALUES_ORDER,
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    subgroup = L["Effect"],
    path  = "units."..unit..".icons.secondaryGlowTrigger", type = "string",
    label = L["Secondary glow trigger"],
    desc = L["When to show the glow on secondary icons."],
    default = "never",
    values  = GLOW_TRIGGER_VALUES, sorting = GLOW_TRIGGER_VALUES_ORDER,
}

-- Style row -------------------------------------------------------
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    subgroup = L["Effect"],
    path  = "units."..unit..".icons.primaryGlowType", type = "string",
    label = L["Primary glow style"],
    desc = L["Visual style of the primary-icon glow. Inert when the trigger is set to Never."],
    default = "pixel",
    values  = GLOW_TYPE_VALUES, sorting = GLOW_TYPE_VALUES_ORDER,
    disabledIf = styleOff("primary"),
}
add{
    panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
    subgroup = L["Effect"],
    path  = "units."..unit..".icons.secondaryGlowType", type = "string",
    label = L["Secondary glow style"],
    desc = L["Visual style of secondary-icon glow. Inert when the trigger is set to Never."],
    default = "pixel",
    values  = GLOW_TYPE_VALUES, sorting = GLOW_TYPE_VALUES_ORDER,
    disabledIf = styleOff("secondary"),
}

-- Color rows ------------------------------------------------------
-- The two swatches STOP mirroring each other across a line here, and that is
-- the rule rather than a slip: options-ui-§17 puts the class-color companion
-- IMMEDIATELY to the swatch's right, so each glow color takes a line of its own
-- with its companion beside it:
--     [Primary glow color]   | [Use class color]
--     [Secondary glow color] | [Use class color]
--
-- Never dimmed, even under trigger Never: a color pair carries no
-- `disabledIf`, on either half (options-ui-§17, the composer's rule).
--
-- Player-scoped, for the reason the cooldown tint above gives: a ready glow
-- fires on the PLAYER'S OWN interrupt being off cooldown. The tracked unit's
-- class has nothing to do with it, whichever unit's page you are on.
H.AddComposed(H.ColorPair{
    prefix     = PREFIX, page = "icons", group = L["Ready glow"],
    subgroup   = L["Effect"],
    key        = "primaryGlowColor", label = L["Primary glow color"],
    defaults   = { primaryGlowColor = { r = 1, g = 1, b = 0, a = 1 } },
    classColor = { source = "player" },
}, STAMP)
H.AddComposed(H.ColorPair{
    prefix     = PREFIX, page = "icons", group = L["Ready glow"],
    subgroup   = L["Effect"],
    key        = "secondaryGlowColor", label = L["Secondary glow color"],
    defaults   = { secondaryGlowColor = { r = 1, g = 1, b = 0, a = 1 } },
    classColor = { source = "player" },
}, STAMP)

-- Style knobs -----------------------------------------------------
-- One row per Const.GLOW_KNOBS entry per slot, primary then secondary, so
-- each knob reads across one line. The ranges, steps and defaults are the
-- constant's; the words are here. `heading` names the subsection a knob
-- opens under (the style's dropdown label, or Offset for the two offsets
-- three styles share).
local KNOB_TEXT = {
    ButtonFrequency = {
        heading = L["Button (rotating rays)"], fmt = "%.3f",
        labels  = { L["Primary frequency"], L["Secondary frequency"] },
        desc    = L["How fast the rays turn. Higher is faster. Button style only."],
    },
    ProcDuration = {
        heading = L["Proc (flipbook)"], fmt = "%.2f s",
        labels  = { L["Primary duration (seconds)"], L["Secondary duration (seconds)"] },
        desc    = L["Seconds one loop of the flipbook takes. Proc style only."],
    },
    ProcStartAnim = {
        heading = L["Proc (flipbook)"],
        labels  = { L["Primary start animation"], L["Secondary start animation"] },
        desc    = L["Play the burst that opens the proc glow when it starts. Proc style only."],
    },
    PixelLines = {
        heading = L["Pixel border"], fmt = "%d",
        labels  = { L["Primary lines"], L["Secondary lines"] },
        desc    = L["Number of lines running around the icon. Pixel style only."],
    },
    PixelFrequency = {
        heading = L["Pixel border"], fmt = "%.2f",
        labels  = { L["Primary frequency"], L["Secondary frequency"] },
        desc    = L["How fast the lines run around the icon. Higher is faster. Pixel style only."],
    },
    PixelLength = {
        heading = L["Pixel border"], fmt = "%d px",
        labels  = { L["Primary line length (0 = automatic)"], L["Secondary line length (0 = automatic)"] },
        desc    = L["Length of each line in pixels. 0 sizes the lines from the icon. Pixel style only."],
    },
    PixelThickness = {
        heading = L["Pixel border"], fmt = "%d px",
        labels  = { L["Primary thickness (px)"], L["Secondary thickness (px)"] },
        desc    = L["Thickness of each line in pixels. Pixel style only."],
    },
    PixelBorder = {
        heading = L["Pixel border"],
        labels  = { L["Primary dark border"], L["Secondary dark border"] },
        desc    = L["Draw a dark border inside the lines. Pixel style only."],
    },
    AutocastParticles = {
        heading = L["Auto cast sparkles"], fmt = "%d",
        labels  = { L["Primary particles"], L["Secondary particles"] },
        desc    = L["Number of sparkles in each ring. Auto cast style only."],
    },
    AutocastFrequency = {
        heading = L["Auto cast sparkles"], fmt = "%.3f",
        labels  = { L["Primary frequency"], L["Secondary frequency"] },
        desc    = L["How fast the sparkles circle the icon. Higher is faster. Auto cast style only."],
    },
    AutocastScale = {
        heading = L["Auto cast sparkles"], fmt = "%.1f",
        labels  = { L["Primary scale"], L["Secondary scale"] },
        desc    = L["Size of the sparkles. Auto cast style only."],
    },
    XOffset = {
        heading = L["Offset"], fmt = "%d px",
        labels  = { L["Primary X offset (px)"], L["Secondary X offset (px)"] },
        desc    = L["How far the glow reaches past the icon's sides, in pixels. Pixel, Proc and Auto cast styles."],
    },
    YOffset = {
        heading = L["Offset"], fmt = "%d px",
        labels  = { L["Primary Y offset (px)"], L["Secondary Y offset (px)"] },
        desc    = L["How far the glow reaches past the icon's top and bottom, in pixels. Pixel, Proc and Auto cast styles."],
    },
}

for _, knob in ipairs(NS.Const.GLOW_KNOBS) do
    local text = KNOB_TEXT[knob.leaf]
    for i, slot in ipairs({ "primary", "secondary" }) do
        add{
            panel = "icons", section = "icons", unit = unit, group = L["Ready glow"],
            subgroup = text.heading,
            path  = PREFIX .. slot .. "Glow" .. knob.leaf, type = knob.kind,
            label = text.labels[i],
            desc  = text.desc,
            default = knob.default,
            min = knob.min, max = knob.max, step = knob.step, fmt = text.fmt,
            disabledIf = knobOff(slot, knob.styles),
        }
    end
end

end

for _, u in ipairs(NS.Units.LIST) do addUnitRows(u) end

-- The Icons entry of the Units page (KickCD#33). The tooltip names the tabs as
-- they stand after item 020's merges (KIC-L32).
H.RegisterGridSection("icons", L["Icons"], {
    tooltip = L["The interrupt icons: size and layout, appearance, annotations and ready glow."],
})
