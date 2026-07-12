-- settings/Castbar.lua
--
-- Castbar canvas panel. Pure schema: every widget is a row in
-- KickCD.Settings.Schema; the builder just calls Helpers.RenderSchema.
-- Adding a new castbar option means adding one schema row here.

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

-- Visibility ---------------------------------------------------------
add{
    panel = "castbar", section = "castbar", group = L["Visibility"],
    path  = "castbar.enabled", type = "bool",
    label = L["Enable cast bar"],
    tooltip = L["Show the target cast bar."],
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

-- Position layout produces:
--     [Anchor mode]                                        (solo)
--     [Anchor on primary icon] | [Anchor on cast bar]
--     [X offset]               | [Y offset]
-- anchor mode is a higher-level pivot than the two attach-point
-- dropdowns it controls, hence the row of its own.
add{
    panel = "castbar", section = "castbar", group = L["Position"],
    path  = "castbar.anchorMode", type = "string",
    label = L["Anchor mode"],
    tooltip = L["Free: drag the bar anywhere. Anchored to primary icon: the bar follows the icon grid's primary icon at the configured anchor points and offsets."],
    default = "PRIMARY",
    values  = {
        { value = "FREE",    label = L["Free (drag to move)"]      },
        { value = "PRIMARY", label = L["Anchored to primary icon"] },
    },
    solo    = true,
}
add{
    panel = "castbar", section = "castbar", group = L["Position"],
    path  = "castbar.anchorPoint", type = "string",
    label = L["Anchor on primary icon"],
    tooltip = L["Which point on the primary icon the cast bar attaches to (only used when Anchor mode is set to Anchored to primary icon)."],
    default = "TOP_LEFT",
    values  = POSITION_ANCHOR_VALUES,
}
add{
    panel = "castbar", section = "castbar", group = L["Position"],
    path  = "castbar.castbarPoint", type = "string",
    label = L["Anchor on cast bar"],
    tooltip = L["Which point on the cast bar attaches to the primary icon (only used when Anchor mode is set to Anchored to primary icon)."],
    default = "BOTTOM_LEFT",
    values  = POSITION_ANCHOR_VALUES,
}
add{
    panel = "castbar", section = "castbar", group = L["Position"],
    path  = "castbar.anchorOffsetX", type = "number",
    label = L["X offset (in px)"],
    tooltip = L["Horizontal pixel offset between the cast bar's anchor point and the icon's anchor point."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", group = L["Position"],
    path  = "castbar.anchorOffsetY", type = "number",
    label = L["Y offset (in px)"],
    tooltip = L["Vertical pixel offset between the cast bar's anchor point and the icon's anchor point."],
    default = 1, min = -200, max = 200, step = 1, fmt = "%d px",
}

-- Orientation --------------------------------------------------------
-- Per-orientation default fill direction. Used by:
--   * `castbar.orientation`'s onChange to reset growDirection when
--     the user flips orientation (so a stale "UP" doesn't linger
--     after switching from Vertical to Horizontal).
--   * `castbar.growDirection`'s default — when the user resets the
--     panel to defaults the value falls back to the horizontal one;
--     a vertical profile picks up "UP" via the orientation reset.
local GROW_DEFAULT_FOR_ORIENTATION = {
    HORIZONTAL = "RIGHT",
    VERTICAL   = "UP",
}

add{
    panel = "castbar", section = "castbar", group = L["Orientation"],
    path  = "castbar.orientation", type = "string",
    label = L["Orientation"],
    tooltip = L["Horizontal: bar stretches across width. Vertical: bar runs up/down."],
    default = "HORIZONTAL",
    values  = {
        { value = "HORIZONTAL", label = L["Horizontal"] },
        { value = "VERTICAL",   label = L["Vertical"]   },
    },
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
            H.Set("castbar.growDirection", "castbar", newGrow)
        end
        H.RefreshAllPanels()
    end,
}
add{
    panel = "castbar", section = "castbar", group = L["Orientation"],
    path  = "castbar.growDirection", type = "string",
    label = L["Growth direction"],
    tooltip = L["Which side the cast bar fills toward. Options change with Orientation: horizontal → Right / Left, vertical → Up / Down."],
    default = "RIGHT",
    -- valueGate names the OTHER setting whose current value gates the
    -- options this dropdown returns. The slash command's invalid-value
    -- error appends `(depends on <gate> = <current>)` so a user who
    -- types `/kcd set castbar.growDirection LEFT` while orientation is
    -- VERTICAL gets a hint about why the value list is UP/DOWN.
    valueGate = "castbar.orientation",
    -- Function so the dropdown re-evaluates its options every time
    -- it refreshes (Panel.lua's makeDropdown re-runs `applyList`
    -- inside its refresh closure). Pulled together with the
    -- orientation onChange above this gives the dropdown a single
    -- valid pair of options at all times — no "(horizontal)" /
    -- "(vertical)" disambiguation suffixes needed in the labels.
    values  = function()
        local profile = NS.db and NS.db.profile
        local orientation = profile and profile.castbar
                            and profile.castbar.orientation
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
    panel = "castbar", section = "castbar", group = L["Orientation"],
    path  = "castbar.autoSize", type = "bool",
    label = L["Auto-size to icon grid"],
    tooltip = L["When on, a horizontal bar's width matches the icon grid's width and a vertical bar's height matches the icon grid's height. The orthogonal dimension stays as configured below."],
    default = true,
}

-- Sizing and Layout --------------------------------------------------
-- Merged from the previous two-subsection split (Sizing + Layout) so
-- everything that determines the bar's dimensions and icon placement
-- lives in one section. Order produces:
--     [Cast bar width] | [Cast bar height]
--     [Icon size]      | [Icon position]
--     [Show spark]                                  (alone — last in
--                                                    section, group
--                                                    transition flushes
--                                                    the row).
add{
    panel = "castbar", section = "castbar", group = L["Sizing and Layout"],
    path  = "castbar.width", type = "number",
    label = L["Cast bar width (in px)"],
    tooltip = L["Cast bar width in pixels."],
    default = 250, min = 100, max = 500, step = 5, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", group = L["Sizing and Layout"],
    path  = "castbar.height", type = "number",
    label = L["Cast bar height (in px)"],
    tooltip = L["Cast bar height in pixels."],
    default = 24, min = 10, max = 60, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", group = L["Sizing and Layout"],
    path  = "castbar.iconSize", type = "number",
    label = L["Icon size (in px)"],
    tooltip = L["Spell icon size in pixels (0 hides the icon)."],
    default = 24, min = 0, max = 60, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", group = L["Sizing and Layout"],
    path  = "castbar.iconPosition", type = "string",
    label = L["Icon position"],
    tooltip = L["Where to place the spell icon, or hide it entirely."],
    default = "OFF",
    values  = {
        { value = "LEFT",  label = L["Left"]  },
        { value = "RIGHT", label = L["Right"] },
        { value = "OFF",   label = L["Off"]   },
    },
}
add{
    panel = "castbar", section = "castbar", group = L["Sizing and Layout"],
    path  = "castbar.showSpark", type = "bool",
    label = L["Show spark"],
    tooltip = L["Render the leading-edge spark on the bar."],
    default = true,
}

-- Text -----------------------------------------------------------------
-- Just the typography (font / size / flags). The "Show spell name" and
-- "Show cast time" toggles each used to live here too, but now sit
-- alongside their own anchor + offset controls under the Spell name and
-- Cast time sections below — reads more naturally per-element than as a
-- pair of show-toggles separated from their position controls. Order:
--     [Font]       | [Font size]
--     [Font flags] |                                      (alone — group
--                                                          break flushes
--                                                          the row).
local TEXT_POSITION_VALUES = {
    { value = "INSIDE_LEFT",   label = L["Inside left"]   },
    { value = "INSIDE_RIGHT",  label = L["Inside right"]  },
    { value = "CENTER",        label = L["Center"]        },
    { value = "OUTSIDE_LEFT",  label = L["Outside left"]  },
    { value = "OUTSIDE_RIGHT", label = L["Outside right"] },
}

add{
    panel = "castbar", section = "castbar", group = L["Text"],
    path  = "castbar.font", type = "string",
    label = L["Font"],
    tooltip = L["Font for the spell name and cast time text."],
    default = "Friz Quadrata TT",
    lsm     = "font",
    values  = function() return H.LSMValues("font") end,
}
add{
    panel = "castbar", section = "castbar", group = L["Text"],
    path  = "castbar.fontSize", type = "number",
    label = L["Font size"],
    tooltip = L["Cast-bar text size in pixels."],
    default = 10, min = 8, max = 24, step = 1, fmt = "%d",
}
add{
    panel = "castbar", section = "castbar", group = L["Text"],
    path  = "castbar.fontFlags", type = "string",
    label = L["Font flags"],
    tooltip = L["Outline / monochrome flags applied to cast-bar text."],
    default = "OUTLINE",
    values  = {
        { value = "NONE",         label = L["None"]          },
        { value = "OUTLINE",      label = L["Outline"]       },
        { value = "THICKOUTLINE", label = L["Thick outline"] },
        { value = "MONOCHROME",   label = L["Monochrome"]    },
    },
}

-- Spell name -----------------------------------------------------------
-- Renamed from "Spell name position" — now bundles the show-toggle with
-- the anchor + offsets so a user looking for "where does the spell name
-- go?" finds the on/off switch alongside the placement controls. Order:
--     [Show spell name] | [Anchor]
--     [X offset]        | [Y offset]
add{
    panel = "castbar", section = "castbar", group = L["Spell name"],
    path  = "castbar.showName", type = "bool",
    label = L["Show spell name"],
    tooltip = L["Display the cast spell's name on the bar."],
    default = true,
}
add{
    panel = "castbar", section = "castbar", group = L["Spell name"],
    path  = "castbar.namePosition", type = "string",
    label = L["Anchor"],
    tooltip = L["Where to anchor the spell name relative to the bar."],
    default = "CENTER",
    values  = TEXT_POSITION_VALUES,
}
add{
    panel = "castbar", section = "castbar", group = L["Spell name"],
    path  = "castbar.nameOffsetX", type = "number",
    label = L["X offset (in px)"],
    tooltip = L["Horizontal pixel shift on top of the anchor (positive = right, negative = left)."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", group = L["Spell name"],
    path  = "castbar.nameOffsetY", type = "number",
    label = L["Y offset (in px)"],
    tooltip = L["Vertical pixel shift on top of the anchor (positive = up, negative = down)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", group = L["Spell name"],
    path  = "castbar.nameTruncate", type = "number",
    label = L["Truncate after (characters)"],
    tooltip = L["Maximum visible characters in the spell name before replacing the tail with an ellipsis. 0 disables truncation."],
    default = 0, min = 0, max = 60, step = 1, fmt = "%d",
}

-- Cast time ------------------------------------------------------------
-- Renamed from "Cast time position". Same shape as Spell name: the show-
-- toggle joins the placement controls so they're configured together.
-- Order:
--     [Show cast time] | [Anchor]
--     [X offset]       | [Y offset]
add{
    panel = "castbar", section = "castbar", group = L["Cast time"],
    path  = "castbar.showTime", type = "bool",
    label = L["Show cast time"],
    tooltip = L["Display the remaining / total cast time on the bar."],
    default = true,
}
add{
    panel = "castbar", section = "castbar", group = L["Cast time"],
    path  = "castbar.timePosition", type = "string",
    label = L["Anchor"],
    tooltip = L["Where to anchor the remaining-time text relative to the bar."],
    default = "CENTER",
    values  = TEXT_POSITION_VALUES,
}
add{
    panel = "castbar", section = "castbar", group = L["Cast time"],
    path  = "castbar.timeOffsetX", type = "number",
    label = L["X offset (in px)"],
    tooltip = L["Horizontal pixel shift on top of the anchor (positive = right, negative = left)."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
}
add{
    panel = "castbar", section = "castbar", group = L["Cast time"],
    path  = "castbar.timeOffsetY", type = "number",
    label = L["Y offset (in px)"],
    tooltip = L["Vertical pixel shift on top of the anchor (positive = up, negative = down)."],
    default = 22, min = -100, max = 100, step = 1, fmt = "%d px",
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
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.statusBarTexture", type = "string",
    label = L["Bar texture"],
    tooltip = L["LibSharedMedia statusbar texture used for interruptible casts."],
    default = "Blizzard",
    lsm     = "statusbar",
    values  = function() return H.LSMValues("statusbar") end,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.barColor", type = "color",
    label = L["Bar color"],
    tooltip = L["RGBA bar fill color when the target's cast is interruptible."],
    default = { 1, 0.85, 0.05, 1 },
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.bgColor", type = "color",
    label = L["Background color"],
    tooltip = L["RGBA color drawn behind the bar."],
    default = { 0, 0, 0, 0.5 },
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.nameTextColor", type = "color",
    label = L["Spell name color"],
    tooltip = L["RGBA color of the spell-name text."],
    default = { 1, 1, 1, 1 },
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.borderShow", type = "bool",
    label = L["Show border"],
    tooltip = L["Draw a border around the cast bar for interruptible casts."],
    default = true,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.borderTexture", type = "string",
    label = L["Border style"],
    tooltip = L["LibSharedMedia border texture (edge style) for interruptible casts."],
    default = "Blizzard Tooltip",
    lsm     = "border",
    values  = function() return H.LSMValues("border") end,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.borderColor", type = "color",
    label = L["Border color"],
    tooltip = L["RGBA border color for interruptible casts."],
    default = { 0, 0, 0, 1 },
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.borderSize", type = "number",
    label = L["Border thickness (in px)"],
    tooltip = L["Border edge size in pixels."],
    default = 2, min = 1, max = 16, step = 1, fmt = "%d px",
}

-- Uninterruptible appearance ------------------------------------------
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.statusBarTexture", type = "string",
    label = L["Bar texture"],
    tooltip = L["LibSharedMedia statusbar texture used for non-interruptible casts."],
    default = "Blizzard",
    lsm     = "statusbar",
    values  = function() return H.LSMValues("statusbar") end,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.barColor", type = "color",
    label = L["Bar color"],
    tooltip = L["RGBA bar fill color when the target's cast cannot be interrupted."],
    default = { 0.85, 0.10, 0.10, 1 },
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.bgColor", type = "color",
    label = L["Background color"],
    tooltip = L["RGBA color drawn behind the bar."],
    default = { 0, 0, 0, 0.5 },
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.nameTextColor", type = "color",
    label = L["Spell name color"],
    tooltip = L["RGBA color of the spell-name text."],
    default = { 1, 1, 1, 1 },
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.borderShow", type = "bool",
    label = L["Show border"],
    tooltip = L["Draw a border around the cast bar for non-interruptible casts."],
    default = true,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.borderTexture", type = "string",
    label = L["Border style"],
    tooltip = L["LibSharedMedia border texture (edge style) for non-interruptible casts."],
    default = "Blizzard Tooltip",
    lsm     = "border",
    values  = function() return H.LSMValues("border") end,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.borderColor", type = "color",
    label = L["Border color"],
    tooltip = L["RGBA border color for non-interruptible casts."],
    default = { 0, 0, 0, 1 },
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.borderSize", type = "number",
    label = L["Border thickness (in px)"],
    tooltip = L["Border edge size in pixels."],
    default = 2, min = 1, max = 16, step = 1, fmt = "%d px",
}

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
    if ctx.panel.defaultsBtn then
        ctx.panel.defaultsBtn:SetCallback("OnClick", function()
            H.RestoreDefaults("castbar", ctx)
        end)
    end

    -- Defer the AceGUI render until the panel becomes visible — same
    -- zero-width caveat as the General / Icons tabs.
    local rendered = false
    ctx.panel:SetScript("OnShow", function()
        if rendered then return end
        rendered = true
        H.RenderSchema(ctx, "castbar")
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Cast bar"])
end

if NS.Settings and NS.Settings.RegisterTab then
    NS.Settings.RegisterTab("castbar", Build)
end

