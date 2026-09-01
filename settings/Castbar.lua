-- settings/Castbar.lua
--
-- Castbar canvas panel. Pure schema: every widget is a row in
-- KickCD.Settings.Schema; the builder just calls Helpers.RenderUnitPanel,
-- which draws the Unit picker as the page banner and then hands the rows to
-- Helpers.RenderTabbedSchema. Adding a new castbar option means adding one
-- schema row here -- into the run of rows its `group` already owns, because
-- the strip is partitioned by group in declaration order (options-ui-§13) and
-- a row filed after the page has left its group prints that tab twice.

local addonName, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Schema = NS.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

-- Every schema row's write goes through Helpers.Set, which fires
-- Ka0s_KickCD_CONFIG_CHANGED { section = "castbar" }; the Castbar module
-- subscribes and re-applies its config from the bus listener. So no
-- row in this file needs an onChange purely for "redraw the live
-- frame" — the bus is the single dispatch path. Rows below only set
-- onChange when there's *additional* work beyond the bus dispatch
-- (e.g. the orientation row also writes through to growDirection and
-- refreshes the panel widgets).

-- Per-unit row generation ---------------------------------------------
-- Every row below is built once per unit in NS.Units.LIST (target,
-- focus): the row's `path` is prefixed with "units.<unit>." and tagged
-- `unit = unit` so Helpers.SchemaForPanel/RenderSchema can filter to
-- only the currently-selected unit's rows (Panel.lua). `section` stays
-- "castbar" for every row — both bars react to a `castbar`
-- CONFIG_CHANGED and resolve their own unit's data via
-- NS.Units.Castbar(unit).
local function addUnitRows(unit)

-- General --------------------------------------------------------------
-- The page's master toggle, the axis the bar runs on, and how big it is.
--
-- FOUR SECTIONS BECAME THIS ONE. "Visibility" held a single row -- the enable
-- -- and one control is not a subject, it is a drawer. "Orientation" and
-- "Sizing and Layout" were two halves of one question and the schema itself
-- said so: `autoSize` decides whether `width` and `height` are read at all, and
-- WHICH of the two it overrides depends on `orientation`. Three tabs to answer
-- "how big is this bar" is three clicks to find the one that is actually in
-- charge.
--
-- Order produces:
--     [Enable cast bar]                                (solo)
--     [Orientation]           | [Growth direction]
--     [Auto-size to icon grid]| [Show spark]
--     [Cast bar width]        | [Cast bar height]
--     [Icon position]         | [Icon size]
--
-- The enable is solo because everything under it is inert without it. Then the
-- mode beside the thing it modes (growth direction's option list IS orientation's
-- axis), the master toggle immediately above the two sliders it can override,
-- and the icon's placement leading its size.
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.enabled", type = "bool",
    label = L["Enable cast bar"],
    desc = L["Show the target cast bar."],
    default = true,
    solo    = true,
}

local GROW_DEFAULT_FOR_ORIENTATION = {
    HORIZONTAL = "RIGHT",
    VERTICAL   = "UP",
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.orientation", type = "string",
    label = L["Orientation"],
    desc = L["Horizontal: bar stretches across width. Vertical: bar runs up/down."],
    default = "HORIZONTAL",
    values  = {
        ["HORIZONTAL"] = L["Horizontal"],
        ["VERTICAL"] = L["Vertical"],
    },
    sorting = { "HORIZONTAL", "VERTICAL" },
    -- Reset growDirection to the new orientation's canonical default
    -- so we can never end up with an inconsistent pair (e.g. a
    -- horizontal bar with growDirection="UP"). H.Set fires
    -- Ka0s_KickCD_CONFIG_CHANGED a second time, which re-runs ApplyConfig
    -- with both fields consistent — the transient state from the
    -- orientation write alone is overwritten before any frame
    -- renders. RefreshAllPanels then re-evaluates the growDirection
    -- dropdown's `values` function so its option list rebuilds for
    -- the new axis and shows the freshly-reset selection.
    --
    -- No manual ApplyConfig / Reskin call here: Helpers.Set has
    -- already fired Ka0s_KickCD_CONFIG_CHANGED { section = "castbar" } for
    -- the orientation write, and the secondary H.Set above fires it
    -- a second time for growDirection. Castbar:OnConfigChanged
    -- subscribes and reapplies — adding a direct call would just
    -- triple-dispatch the same work.
    onChange = function(value)
        local newGrow = GROW_DEFAULT_FOR_ORIENTATION[value]
        if newGrow then
            H.Set("units."..unit..".castbar.growDirection", "castbar", newGrow)
        end
        -- SCALAR, not structural, and the difference now matters. The library's
        -- dropdown refresher re-runs its `values` function before re-reading
        -- the value (libs/LibKa0s/OptionsWidgets.lua's makeDropdown/applyList),
        -- so a scalar sweep is already enough to rebuild the growth-direction
        -- option list on the new axis. A structural one would clear the scroll
        -- and rebuild the page from inside this dropdown's own OnValueChanged,
        -- releasing the widget mid-callback for no gain.
        H.RefreshScalars()
    end,
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.growDirection", type = "string",
    label = L["Growth direction"],
    desc = L["Which side the cast bar fills toward. Options change with Orientation: horizontal gives Right / Left, vertical gives Up / Down."],
    default = "RIGHT",
    -- valueGate names the OTHER setting whose current value gates the
    -- options this dropdown returns. The slash command's invalid-value
    -- error appends `(depends on <gate> = <current>)` so a user who
    -- types `/kcd set castbar.growDirection LEFT` while orientation is
    -- VERTICAL gets a hint about why the value list is UP/DOWN.
    valueGate = "units."..unit..".castbar.orientation",
    -- Function so the dropdown re-evaluates its options every time
    -- it refreshes (Panel.lua's makeDropdown re-runs `applyList`
    -- inside its refresh closure). Pulled together with the
    -- orientation onChange above this gives the dropdown a single
    -- valid pair of options at all times — no "(horizontal)" /
    -- "(vertical)" disambiguation suffixes needed in the labels.
    values  = function()
        local profile = NS.db and NS.db.profile
        local unitProfile = profile and profile.units and profile.units[unit]
        local orientation = unitProfile and unitProfile.castbar
                            and unitProfile.castbar.orientation
        if orientation == "VERTICAL" then
            return {
                { value = "UP",   label = L["Up"]   },
                { value = "DOWN", label = L["Down"] },
            }
        end
        return {
            { value = "RIGHT", label = L["Right"] },
            { value = "LEFT",  label = L["Left"]  },
        }
    end,
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.autoSize", type = "bool",
    label = L["Auto-size to icon grid"],
    desc = L["When on, a horizontal bar's width matches the icon grid's width and a vertical bar's height matches the icon grid's height. The orthogonal dimension stays as configured below."],
    default = true,
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.showSpark", type = "bool",
    label = L["Show spark"],
    desc = L["Render the leading-edge spark on the bar."],
    default = true,
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.width", type = "number",
    label = L["Cast bar width (in px)"],
    desc = L["Cast bar width in pixels."],
    default = 250, min = 100, max = 500, step = 5, fmt = "%d px",
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.height", type = "number",
    label = L["Cast bar height (in px)"],
    desc = L["Cast bar height in pixels."],
    default = 24, min = 10, max = 60, step = 1, fmt = "%d px",
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.iconPosition", type = "string",
    label = L["Icon position"],
    desc = L["Where to place the spell icon, or hide it entirely."],
    default = "OFF",
    values  = {
        ["LEFT"] = L["Left"],
        ["RIGHT"] = L["Right"],
        ["OFF"] = L["Off"],
    },
    sorting = { "LEFT", "RIGHT", "OFF" },
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["General"],
    path  = "units."..unit..".castbar.iconSize", type = "number",
    label = L["Icon size (in px)"],
    desc = L["Spell icon size in pixels (0 hides the icon)."],
    default = 24, min = 0, max = 60, step = 1, fmt = "%d px",
}


-- Position ------------------------------------------------------------
-- Frame-anchor values for the "anchor on primary icon" and "anchor on
-- cast bar" dropdowns. Sourced from H.AnchorValues so this list stays
-- in lockstep with the Icons → Layout → Anchor point dropdown — both
-- expose the same 13 options (12 side+alignment + CENTER).
--
-- Runtime translation to SetPoint-compatible names happens in
-- modules/Castbar.lua's ApplyAnchor; legacy 9-point tokens (TOPLEFT,
-- TOP, BOTTOM, etc.) saved by older profiles still work because the
-- translator passes unrecognized values through unchanged.
local POSITION_ANCHOR_VALUES = H.AnchorValues()
local POSITION_ANCHOR_VALUES_ORDER = H.AnchorOrder()

-- Position layout produces:
--     [Anchor mode]                                        (solo)
--     [Anchor on primary icon] | [Anchor on cast bar]
--     [X offset]               | [Y offset]
-- anchor mode is a higher-level pivot than the two attach-point
-- dropdowns it controls, hence the row of its own.
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Position"],
    path  = "units."..unit..".castbar.anchorMode", type = "string",
    label = L["Anchor mode"],
    desc = L["Free: drag the bar anywhere. Anchored to primary icon: the bar follows the icon grid's primary icon at the configured anchor points and offsets."],
    default = "PRIMARY",
    values  = {
        ["FREE"] = L["Free (drag to move)"],
        ["PRIMARY"] = L["Anchored to primary icon"],
    },
    sorting = { "FREE", "PRIMARY" },
    solo    = true,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Position"],
    path  = "units."..unit..".castbar.anchorPoint", type = "string",
    label = L["Anchor on primary icon"],
    desc = L["Which point on the primary icon the cast bar attaches to (only used when Anchor mode is set to Anchored to primary icon)."],
    default = "BOTTOM_LEFT",
    values  = POSITION_ANCHOR_VALUES, sorting = POSITION_ANCHOR_VALUES_ORDER,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Position"],
    path  = "units."..unit..".castbar.castbarPoint", type = "string",
    label = L["Anchor on cast bar"],
    desc = L["Which point on the cast bar attaches to the primary icon (only used when Anchor mode is set to Anchored to primary icon)."],
    default = "TOP_LEFT",
    values  = POSITION_ANCHOR_VALUES, sorting = POSITION_ANCHOR_VALUES_ORDER,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Position"],
    path  = "units."..unit..".castbar.anchorOffsetX", type = "number",
    label = L["X offset (in px)"],
    desc = L["Horizontal pixel offset between the cast bar's anchor point and the icon's anchor point."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Position"],
    path  = "units."..unit..".castbar.anchorOffsetY", type = "number",
    label = L["Y offset (in px)"],
    desc = L["Vertical pixel offset between the cast bar's anchor point and the icon's anchor point."],
    default = -1, min = -200, max = 200, step = 1, fmt = "%d px",
}

-- Font -----------------------------------------------------------------
-- The typography the spell name and the cast time SHARE. Named Font rather
-- than Text so it agrees with the Text Label page's Font tab and so it is not
-- mistaken for the two tabs beside it, which are the text ELEMENTS. The "Show
-- spell name" and "Show cast time" toggles each sit with their own anchor and
-- offsets on those tabs -- that decision is older than the strip and it holds:
-- a reader asking "where does the spell name go?" wants the on/off switch in
-- front of the placement controls, not on a third tab.
--
-- Order produces:
--     [Font]       | [Font size]
--     [Font flags]                                     (last in the tab)
local TEXT_POSITION_VALUES = {
    ["INSIDE_LEFT"] = L["Inside left"],
    ["INSIDE_RIGHT"] = L["Inside right"],
    ["CENTER"] = L["Center"],
    ["OUTSIDE_LEFT"] = L["Outside left"],
    ["OUTSIDE_RIGHT"] = L["Outside right"],
}
local TEXT_POSITION_VALUES_ORDER = {
    "INSIDE_LEFT",
    "INSIDE_RIGHT",
    "CENTER",
    "OUTSIDE_LEFT",
    "OUTSIDE_RIGHT",
}

add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Font"],
    path  = "units."..unit..".castbar.font", type = "string",
    label = L["Font"],
    desc = L["Font for the spell name and cast time text."],
    default = "Friz Quadrata TT",
    lsm     = "font",
    values  = function() return H.LSMValues("font") end,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Font"],
    path  = "units."..unit..".castbar.fontSize", type = "number",
    label = L["Font size"],
    desc = L["Cast-bar text size in pixels."],
    default = 10, min = 8, max = 24, step = 1, fmt = "%d",
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Font"],
    path  = "units."..unit..".castbar.fontFlags", type = "string",
    label = L["Font flags"],
    desc = L["Outline / monochrome flags applied to cast-bar text."],
    default = "OUTLINE",
    values  = {
        ["NONE"] = L["None"],
        ["OUTLINE"] = L["Outline"],
        ["THICKOUTLINE"] = L["Thick outline"],
        ["MONOCHROME"] = L["Monochrome"],
    },
    sorting = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROME" },
}

-- Spell name -----------------------------------------------------------
-- Renamed from "Spell name position" — now bundles the show-toggle with
-- the anchor + offsets so a user looking for "where does the spell name
-- go?" finds the on/off switch alongside the placement controls. Order:
--     [Show spell name] | [Anchor]
--     [X offset]        | [Y offset]
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Spell name"],
    path  = "units."..unit..".castbar.showName", type = "bool",
    label = L["Show spell name"],
    desc = L["Display the cast spell's name on the bar."],
    default = true,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Spell name"],
    path  = "units."..unit..".castbar.namePosition", type = "string",
    label = L["Anchor"],
    desc = L["Where to anchor the spell name relative to the bar."],
    default = "CENTER",
    values  = TEXT_POSITION_VALUES, sorting = TEXT_POSITION_VALUES_ORDER,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Spell name"],
    path  = "units."..unit..".castbar.nameOffsetX", type = "number",
    label = L["X offset (in px)"],
    desc = L["Horizontal pixel shift on top of the anchor (positive = right, negative = left)."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Spell name"],
    path  = "units."..unit..".castbar.nameOffsetY", type = "number",
    label = L["Y offset (in px)"],
    desc = L["Vertical pixel shift on top of the anchor (positive = up, negative = down)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Spell name"],
    path  = "units."..unit..".castbar.nameTruncate", type = "number",
    label = L["Truncate after (characters)"],
    desc = L["Maximum visible characters in the spell name before replacing the tail with an ellipsis. 0 disables truncation."],
    default = 0, min = 0, max = 60, step = 1, fmt = "%d",
}

-- Cast time ------------------------------------------------------------
-- Renamed from "Cast time position". Same shape as Spell name: the show-
-- toggle joins the placement controls so they're configured together.
-- Order:
--     [Show cast time] | [Anchor]
--     [X offset]       | [Y offset]
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Cast time"],
    path  = "units."..unit..".castbar.showTime", type = "bool",
    label = L["Show cast time"],
    desc = L["Display the remaining / total cast time on the bar."],
    default = true,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Cast time"],
    path  = "units."..unit..".castbar.timePosition", type = "string",
    label = L["Anchor"],
    desc = L["Where to anchor the remaining-time text relative to the bar."],
    default = "CENTER",
    values  = TEXT_POSITION_VALUES, sorting = TEXT_POSITION_VALUES_ORDER,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Cast time"],
    path  = "units."..unit..".castbar.timeOffsetX", type = "number",
    label = L["X offset (in px)"],
    desc = L["Horizontal pixel shift on top of the anchor (positive = right, negative = left)."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Cast time"],
    path  = "units."..unit..".castbar.timeOffsetY", type = "number",
    label = L["Y offset (in px)"],
    desc = L["Vertical pixel shift on top of the anchor (positive = up, negative = down)."],
    default = -20, min = -100, max = 100, step = 1, fmt = "%d px",
}

-- Per-state appearance (interruptible vs uninterruptible casts) -------
--
-- Switching between the two states uses
-- C_CurveUtil.EvaluateColorValueFromBoolean on the cast's secret
-- notInterruptible bool — see modules/Castbar.lua:ApplyState. Each row
-- below targets one nested path (castbar.interruptible.* or
-- castbar.uninterruptible.*); the addon stacks two widgets and
-- alpha-curve-switches between them so a single cast renders only the
-- relevant half.

-- Interruptible appearance --------------------------------------------
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Interruptible"],
    path  = "units."..unit..".castbar.interruptible.statusBarTexture", type = "string",
    label = L["Bar texture"],
    desc = L["LibSharedMedia statusbar texture used for interruptible casts."],
    default = "Blizzard Raid Bar",
    lsm     = "statusbar",
    values  = function() return H.LSMValues("statusbar") end,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Interruptible"],
    path  = "units."..unit..".castbar.interruptible.barColor", type = "color", hasAlpha = true,
    label = L["Bar color"],
    desc = L["RGBA bar fill color when the target's cast is interruptible."],
    default = { r = 1, g = 0.85, b = 0.05, a = 1 },
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Interruptible"],
    path  = "units."..unit..".castbar.interruptible.bgColor", type = "color", hasAlpha = true,
    label = L["Background color"],
    desc = L["RGBA color drawn behind the bar."],
    default = { r = 0, g = 0, b = 0, a = 0.5 },
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Interruptible"],
    path  = "units."..unit..".castbar.interruptible.nameTextColor", type = "color", hasAlpha = true,
    label = L["Spell name color"],
    desc = L["RGBA color of the spell-name text."],
    default = { r = 1, g = 1, b = 1, a = 1 },
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Interruptible"],
    path  = "units."..unit..".castbar.interruptible.borderShow", type = "bool",
    label = L["Show border"],
    desc = L["Draw a border around the cast bar for interruptible casts."],
    default = true,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Interruptible"],
    path  = "units."..unit..".castbar.interruptible.borderTexture", type = "string",
    label = L["Border style"],
    desc = L["LibSharedMedia border texture (edge style) for interruptible casts."],
    default = "Blizzard Tooltip",
    lsm     = "border",
    values  = function() return H.LSMValues("border") end,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Interruptible"],
    path  = "units."..unit..".castbar.interruptible.borderColor", type = "color", hasAlpha = true,
    label = L["Border color"],
    desc = L["RGBA border color for interruptible casts."],
    default = { r = 0, g = 0, b = 0, a = 1 },
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Interruptible"],
    path  = "units."..unit..".castbar.interruptible.borderSize", type = "number",
    label = L["Border thickness (in px)"],
    desc = L["Border edge size in pixels."],
    default = 2, min = 1, max = 16, step = 1, fmt = "%d px",
}

-- Uninterruptible appearance ------------------------------------------
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Non-interruptible"],
    path  = "units."..unit..".castbar.uninterruptible.statusBarTexture", type = "string",
    label = L["Bar texture"],
    desc = L["LibSharedMedia statusbar texture used for non-interruptible casts."],
    default = "Blizzard Raid Bar",
    lsm     = "statusbar",
    values  = function() return H.LSMValues("statusbar") end,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Non-interruptible"],
    path  = "units."..unit..".castbar.uninterruptible.barColor", type = "color", hasAlpha = true,
    label = L["Bar color"],
    desc = L["RGBA bar fill color when the target's cast cannot be interrupted."],
    default = { r = 0.85, g = 0.10, b = 0.10, a = 1 },
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Non-interruptible"],
    path  = "units."..unit..".castbar.uninterruptible.bgColor", type = "color", hasAlpha = true,
    label = L["Background color"],
    desc = L["RGBA color drawn behind the bar."],
    default = { r = 0, g = 0, b = 0, a = 0.5 },
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Non-interruptible"],
    path  = "units."..unit..".castbar.uninterruptible.nameTextColor", type = "color", hasAlpha = true,
    label = L["Spell name color"],
    desc = L["RGBA color of the spell-name text."],
    default = { r = 1, g = 1, b = 1, a = 1 },
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Non-interruptible"],
    path  = "units."..unit..".castbar.uninterruptible.borderShow", type = "bool",
    label = L["Show border"],
    desc = L["Draw a border around the cast bar for non-interruptible casts."],
    default = true,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Non-interruptible"],
    path  = "units."..unit..".castbar.uninterruptible.borderTexture", type = "string",
    label = L["Border style"],
    desc = L["LibSharedMedia border texture (edge style) for non-interruptible casts."],
    default = "Blizzard Tooltip",
    lsm     = "border",
    values  = function() return H.LSMValues("border") end,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Non-interruptible"],
    path  = "units."..unit..".castbar.uninterruptible.borderColor", type = "color", hasAlpha = true,
    label = L["Border color"],
    desc = L["RGBA border color for non-interruptible casts."],
    default = { r = 0, g = 0, b = 0, a = 1 },
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Non-interruptible"],
    path  = "units."..unit..".castbar.uninterruptible.borderSize", type = "number",
    label = L["Border thickness (in px)"],
    desc = L["Border edge size in pixels."],
    default = 2, min = 1, max = 16, step = 1, fmt = "%d px",
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
    ctx = H.CreatePanel("KickCDCastbarPanel", L["Cast bar"], {
        panelKey       = "castbar",
        defaultsButton = true,
    })
    -- Parked, not wired: the Defaults button doesn't exist until the
    -- panel's first OnShow (H.EnsureDefaultsButton).
    ctx.panel.defaultsOnClick = function()
        H.RestoreDefaults("castbar", ctx)
    end

    -- The library owns WHEN this draws (H.SetRenderer) and H.RenderUnitPanel
    -- pins the Unit picker into the chrome band above the tab strip; see
    -- settings/Icons.lua's builder for the long form.
    H.SetRenderer(ctx, function(c) H.RenderUnitPanel(c, "castbar") end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Cast bar"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("castbar", L["Cast bar"], Build)
end

