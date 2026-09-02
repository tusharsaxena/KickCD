-- settings/Castbar.lua
--
-- Castbar canvas panel. Pure schema: every widget is a row in
-- KickCD.Settings.Schema; the builder just calls Helpers.RenderUnitPanel,
-- which draws the Unit picker as the page banner and then hands the rows to
-- Helpers.RenderTabbedSchema. Adding a new castbar option means adding one
-- schema row here -- into the run of rows its `group` already owns, because
-- the strip is partitioned by group in declaration order (options-ui-§13) and
-- a row filed after the page has left its group prints that tab twice.
--
-- EIGHT TABS: General, Size and position, Icon, Font, Spell name, Cast time,
-- Interruptible, Non-interruptible. The middle two are new and General is five
-- rows lighter for it -- see the comment on each.
--
-- The font block and both per-state appearance blocks are COMPOSED
-- (libs/LibKa0s/OptionsCompose.lua): options-ui-§16 makes the bar, border and
-- font row sets the collection's rather than this page's, and §17 makes the
-- class-color companion beside every swatch non-optional. H.AddComposed stamps
-- this addon's `panel` / `section` / `unit` onto what comes back.

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

-- What every composed block on this page takes: where its stored paths hang,
-- and the host row fields H.AddComposed stamps onto what comes back
-- (settings/Panel.lua). The two per-state blocks prefix further, off PREFIX.
local PREFIX = "units." .. unit .. ".castbar."
local STAMP  = { panel = "castbar", section = "castbar", unit = unit }

-- General --------------------------------------------------------------
-- The page's master toggle and the axis the bar runs on. NINE ROWS BECAME
-- FIVE: this tab had grown into the drawer everything landed in, and four of
-- its rows were two other subjects wearing its name. The two size sliders went
-- to the tab that already held the bar's placement -- which is now "Size and
-- position", because that is what it answers -- and the two icon rows became a
-- tab of their own, since the spell icon is a piece of the bar you can turn off
-- entirely rather than a property of the bar's geometry.
--
-- Order produces:
--     [Enable cast bar]                                (solo)
--     [Orientation]           | [Growth direction]
--     [Auto-size to icon grid]| [Show spark]
--
-- The enable is solo because everything under it is inert without it. Then the
-- mode beside the thing it modes (growth direction's option list IS
-- orientation's axis), and the auto-size toggle beside the other bar-wide
-- boolean. `autoSize` still governs the two width/height sliders a tab away,
-- and its own tooltip is where that is said.
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

-- "Size and position" -- renamed from "Position", because the two width/height
-- sliders moved here from the overloaded General tab and the tab now answers
-- both halves of "how big is this bar and where does it sit". Two kinds of
-- control on one tab, so each block carries a subsection heading
-- (options-ui-§7); neither heading repeats the tab's own name.
--
-- Layout produces:
--     Size      [Cast bar width]         | [Cast bar height]
--     Position  [Anchor mode]                                (solo)
--               [Anchor on primary icon] | [Anchor on cast bar]
--               [X offset]               | [Y offset]
--
-- Anchor mode is a higher-level pivot than the two attach-point dropdowns it
-- controls, hence the row of its own.
--
-- NOTHING re-keyed an afterGroup over this rename: this page renders through
-- H.RenderUnitPanel with no afterGroup at all, so there was no hook to detach.
-- Renaming a group that DOES carry one detaches it silently, because the group
-- name IS the hook key.
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Size and position"],
    subgroup = L["Size"],
    path  = "units."..unit..".castbar.width", type = "number",
    label = L["Cast bar width (in px)"],
    desc = L["Cast bar width in pixels. Overridden by Auto-size to icon grid while the bar is horizontal."],
    default = 250, min = 100, max = 500, step = 5, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Size and position"],
    subgroup = L["Size"],
    path  = "units."..unit..".castbar.height", type = "number",
    label = L["Cast bar height (in px)"],
    desc = L["Cast bar height in pixels. Overridden by Auto-size to icon grid while the bar is vertical."],
    default = 24, min = 10, max = 60, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Size and position"],
    subgroup = L["Position"],
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
    panel = "castbar", section = "castbar", unit = unit, group = L["Size and position"],
    subgroup = L["Position"],
    path  = "units."..unit..".castbar.anchorPoint", type = "string",
    label = L["Anchor on primary icon"],
    desc = L["Which point on the primary icon the cast bar attaches to (only used when Anchor mode is set to Anchored to primary icon)."],
    default = "BOTTOM_LEFT",
    values  = POSITION_ANCHOR_VALUES, sorting = POSITION_ANCHOR_VALUES_ORDER,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Size and position"],
    subgroup = L["Position"],
    path  = "units."..unit..".castbar.castbarPoint", type = "string",
    label = L["Anchor on cast bar"],
    desc = L["Which point on the cast bar attaches to the primary icon (only used when Anchor mode is set to Anchored to primary icon)."],
    default = "TOP_LEFT",
    values  = POSITION_ANCHOR_VALUES, sorting = POSITION_ANCHOR_VALUES_ORDER,
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Size and position"],
    subgroup = L["Position"],
    path  = "units."..unit..".castbar.anchorOffsetX", type = "number",
    label = L["X offset (in px)"],
    desc = L["Horizontal pixel offset between the cast bar's anchor point and the icon's anchor point."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Size and position"],
    subgroup = L["Position"],
    path  = "units."..unit..".castbar.anchorOffsetY", type = "number",
    label = L["Y offset (in px)"],
    desc = L["Vertical pixel offset between the cast bar's anchor point and the icon's anchor point."],
    default = -1, min = -200, max = 200, step = 1, fmt = "%d px",
}

-- Icon -----------------------------------------------------------------
-- The spell icon beside the bar: whether it is drawn at all, on which side, and
-- how big. A tab rather than two more rows on General, because "Off" makes the
-- whole thing vanish -- the icon is a piece of the cast bar you can turn off,
-- not a property of the bar's own geometry, and it was the pair that pushed
-- General to nine rows.
add{
    panel = "castbar", section = "castbar", unit = unit, group = L["Icon"],
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
    panel = "castbar", section = "castbar", unit = unit, group = L["Icon"],
    path  = "units."..unit..".castbar.iconSize", type = "number",
    label = L["Icon size (in px)"],
    desc = L["Spell icon size in pixels (0 hides the icon). Capped at the bar's short axis so the icon never overflows it."],
    default = 24, min = 0, max = 60, step = 1, fmt = "%d px",
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
-- COMPOSED (options-ui-§16), which is what brings the two rows this tab did not
-- have: a color and a font shadow.
--     [Font]            | [Font size]
--     [Cast time color] | [Use class color]
--     [Font flags]      | [Font shadow]
--
-- WHY THE COLOR IS LABELLED "Cast time color" AND NOT "Font color". The spell
-- name already has two writers, one per cast state -- the `nameTextColor`
-- swatches on the Interruptible and Non-interruptible tabs, which have to be
-- per-state because the flag driving the choice can be a 12.0 secret value and
-- the switch is a curve evaluation. A third control over the same FontString
-- would be a control that loses every argument it has with those two. The cast
-- TIME text is the half of this tab's typography that had no color at all --
-- it was hardcoded white in modules/Castbar_Skin.lua -- so `castbar.textColor`
-- is what the composed swatch governs, and its label says so.
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


H.AddComposed(H.FontGroup{
    prefix = PREFIX, page = "castbar", group = L["Font"],
    keys = {
        fontColor         = "textColor",
        useClassColorFont = "useClassColorText",
    },
    labels   = { fontColor = L["Cast time color"] },
    defaults = {
        font       = "Friz Quadrata TT",
        fontSize   = 10,
        fontColor  = { r = 1, g = 1, b = 1, a = 1 },
        fontFlags  = "OUTLINE",
        fontShadow = false,
    },
    -- The bar DESCRIBES the tracked unit, so its text takes that unit's class
    -- (options-ui-§17). Against an NPC boss -- which is most of the time -- the
    -- class is unresolvable and the stored swatch is what renders; that is the
    -- library's rule 2, it is intended, and the swatch's tooltip says so.
    classColor = { source = "unit", unit = unit },
}, STAMP)

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
--
-- FOUR KINDS OF CONTROL ON ONE TAB, so each block carries a subsection heading
-- (options-ui-§7) and each is COMPOSED (options-ui-§16, §17):
--     Bar         [Bar texture]        | [Bar opacity]
--                 [Bar color]          | [Use class color]
--     Background  [Background color]   | [Use class color]
--     Text        [Spell name color]   | [Use class color]
--     Border      [Show border]
--                 [Border style]       | [Border thickness (px)]
--                 [Border color]       | [Use class color]
--
-- The BACKGROUND is not a bar group and gets no texture picker: it is a
-- SetColorTexture with no fill, so a texture control there would be wired to
-- nothing (options-ui-§16).
--
-- `Bar opacity` is NEW. It folds into the per-state alpha CURVE rather than
-- being a SetAlpha of its own — modules/Castbar.lua's ApplyState already
-- alpha-switches the two stacked bars off the secret flag, and a second
-- multiplication afterwards would either be overwritten or, worse, arithmetic
-- on a secret value.
--
-- The two composer calls per block differ only in their prefix. Called twice
-- rather than hand-duplicated, which is the rule and also the only way the two
-- states cannot drift apart.

-- Interruptible appearance --------------------------------------------
H.AddComposed(H.BarGroup{
    prefix   = PREFIX .. "interruptible.", page = "castbar", group = L["Interruptible"],
    subgroup = L["Bar"],
    keys     = { barTexture = "statusBarTexture" },
    defaults = { barTexture = "Blizzard Raid Bar", barAlpha = 1,
                 barColor = { r = 1, g = 0.85, b = 0.05, a = 1 } },
    classColor = { source = "unit", unit = unit },
}, STAMP)
H.AddComposed(H.ColorPair{
    prefix   = PREFIX .. "interruptible.", page = "castbar", group = L["Interruptible"],
    subgroup = L["Background"],
    key      = "bgColor", label = L["Background color"],
    defaults = { bgColor = { r = 0, g = 0, b = 0, a = 0.5 } },
    classColor = { source = "unit", unit = unit },
}, STAMP)
H.AddComposed(H.ColorPair{
    prefix   = PREFIX .. "interruptible.", page = "castbar", group = L["Interruptible"],
    subgroup = L["Text"],
    key      = "nameTextColor", label = L["Spell name color"],
    defaults = { nameTextColor = { r = 1, g = 1, b = 1, a = 1 } },
    classColor = { source = "unit", unit = unit },
}, STAMP)
H.AddComposed(H.BorderGroup{
    prefix   = PREFIX .. "interruptible.", page = "castbar", group = L["Interruptible"],
    subgroup = L["Border"],
    show     = true,
    keys     = { borderStyle = "borderTexture" },
    defaults = { borderShow = true, borderStyle = "Blizzard Tooltip",
                 borderSize = 2, borderColor = { r = 0, g = 0, b = 0, a = 1 } },
    classColor = { source = "unit", unit = unit },
}, STAMP)

-- Uninterruptible appearance ------------------------------------------
H.AddComposed(H.BarGroup{
    prefix   = PREFIX .. "uninterruptible.", page = "castbar", group = L["Non-interruptible"],
    subgroup = L["Bar"],
    keys     = { barTexture = "statusBarTexture" },
    defaults = { barTexture = "Blizzard Raid Bar", barAlpha = 1,
                 barColor = { r = 0.85, g = 0.10, b = 0.10, a = 1 } },
    classColor = { source = "unit", unit = unit },
}, STAMP)
H.AddComposed(H.ColorPair{
    prefix   = PREFIX .. "uninterruptible.", page = "castbar", group = L["Non-interruptible"],
    subgroup = L["Background"],
    key      = "bgColor", label = L["Background color"],
    defaults = { bgColor = { r = 0, g = 0, b = 0, a = 0.5 } },
    classColor = { source = "unit", unit = unit },
}, STAMP)
H.AddComposed(H.ColorPair{
    prefix   = PREFIX .. "uninterruptible.", page = "castbar", group = L["Non-interruptible"],
    subgroup = L["Text"],
    key      = "nameTextColor", label = L["Spell name color"],
    defaults = { nameTextColor = { r = 1, g = 1, b = 1, a = 1 } },
    classColor = { source = "unit", unit = unit },
}, STAMP)
H.AddComposed(H.BorderGroup{
    prefix   = PREFIX .. "uninterruptible.", page = "castbar", group = L["Non-interruptible"],
    subgroup = L["Border"],
    show     = true,
    keys     = { borderStyle = "borderTexture" },
    defaults = { borderShow = true, borderStyle = "Blizzard Tooltip",
                 borderSize = 2, borderColor = { r = 0, g = 0, b = 0, a = 1 } },
    classColor = { source = "unit", unit = unit },
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
    ctx = H.CreatePanel("KickCDCastbarPanel", L["Cast bar"], {
        pageKey        = "castbar",
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

