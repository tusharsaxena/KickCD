-- settings/Label.lua
--
-- "Text Label" canvas panel. One identity label per unit (target/focus),
-- rendered by modules/UnitLabel.lua. Pure schema: every widget is a row in
-- KickCD.Settings.Schema, generated once per NS.Units.LIST entry with a
-- unit-scoped path (units.<unit>.label.*). label.show FOLLOWS the styling link
-- (spec 2b, resolved via NS.Units.LabelShow) — a linked Focus mirrors Target's
-- show, so the show row is a normal styled row and correctly collapses into the
-- "Linked to Target" note when linked. label.text stays per-unit (spec 2a);
-- while linked its row also collapses (unlink to edit the text — the stored
-- per-unit text still renders). Uses the shared Unit banner + tab strip via
-- RenderUnitPanel.

local addonName, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Schema = NS.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

local POINT_VALUES = {
    ["TOPLEFT"] = L["Top left"],
    ["TOP"] = L["Top"],
    ["TOPRIGHT"] = L["Top right"],
    ["LEFT"] = L["Left"],
    ["CENTER"] = L["Center"],
    ["RIGHT"] = L["Right"],
    ["BOTTOMLEFT"] = L["Bottom left"],
    ["BOTTOM"] = L["Bottom"],
    ["BOTTOMRIGHT"] = L["Bottom right"],
}
local POINT_VALUES_ORDER = {
    "TOPLEFT",
    "TOP",
    "TOPRIGHT",
    "LEFT",
    "CENTER",
    "RIGHT",
    "BOTTOMLEFT",
    "BOTTOM",
    "BOTTOMRIGHT",
}

local JUSTIFY_H_VALUES = {
    ["LEFT"] = L["Left"],
    ["CENTER"] = L["Center"],
    ["RIGHT"] = L["Right"],
}
local JUSTIFY_H_VALUES_ORDER = {
    "LEFT",
    "CENTER",
    "RIGHT",
}
local JUSTIFY_V_VALUES = {
    ["TOP"] = L["Top"],
    ["MIDDLE"] = L["Middle"],
    ["BOTTOM"] = L["Bottom"],
}
local JUSTIFY_V_VALUES_ORDER = {
    "TOP",
    "MIDDLE",
    "BOTTOM",
}
local ATTACH_VALUES = {
    ["castbar"] = L["Cast bar"],
    ["icons"] = L["Icon grid"],
}
local ATTACH_VALUES_ORDER = {
    "castbar",
    "icons",
}

-- Three tabs, partitioned from `group` in declaration order (options-ui-§13):
-- General, Placement, Font. The Font tab is COMPOSED
-- (libs/LibKa0s/OptionsCompose.lua), which is what brings the class-color
-- companion beside the label color and the font shadow this page did not have.
--
-- The first used to be called "Label" on a page called Text Label, which told
-- the reader nothing the page had not already said; it is General now, the way
-- every first tab in this addon is.
--
-- Orientation used to be a tab of its own — horizontal justify, vertical
-- justify, rotation. It is inside Placement now. Two tabs next to each other,
-- both answering "where does this text sit and which way does it face", is the
-- reader crossing the same question twice to find out which half holds the
-- control they want.
local function addUnitRows(unit)
    -- General (identity: per-unit even when linked) --------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["General"],
         path = "units." .. unit .. ".label.show", type = "bool",
         label = L["Show label"],
         desc = L["Show this unit's identity label."],
         default = true }
    -- FREE TEXT, and it has to SAY so. This row shipped as `type = "string"`
    -- with no `values` and no `dialogControl`, and LibKa0s' RenderField sends
    -- every string row that is not an EditBox to makeDropdown -- which then
    -- called SetList({}, {}), because enumList answers an empty table for a nil
    -- `values`. The result was a dropdown that opened on nothing, in game only.
    -- The library does not INFER free text from a missing `values` (inference
    -- would silently turn a row whose values function returned empty into a
    -- text box -- the LSM-before-registration case), so the opt-in is explicit
    -- and this is it. The re-vendored library now warns on the bad shape, so the
    -- next one announces itself the first time its page is opened.
    add{ panel = "label", section = "label", unit = unit, group = L["General"],
         path = "units." .. unit .. ".label.text", type = "string",
         dialogControl = "EditBox", maxLetters = 32,
         label = L["Label text"],
         desc = L["Text shown on this unit's label."],
         default = (unit == "target" and "Target" or "Focus") }

    -- Placement -------------------------------------------------------------
    -- Order produces:
    --     [Attach to]                                (solo)
    --     [Label anchor point]  | [Attach point]
    --     [X offset]            | [Y offset]
    --     [Horizontal justify]  | [Vertical justify]
    --     [Rotation]
    --
    -- `attach` is solo because it is a genuine pivot rather than spacing: which
    -- widget the label hangs off decides what the two anchor points underneath
    -- it even refer to. Below it every line is a pair read ACROSS — the two
    -- anchor points, the two offsets, the two justifications — because in each
    -- case the reader's question is how the two compare, not what one of them
    -- is on its own.
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.attach", type = "string",
         label = L["Attach to"],
         desc = L["Which widget the label anchors to."],
         default = "icons", values = ATTACH_VALUES, sorting = ATTACH_VALUES_ORDER,
         solo = true }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.point", type = "string",
         label = L["Label anchor point"],
         desc = L["Which point of the label attaches."],
         default = "BOTTOM", values = POINT_VALUES, sorting = POINT_VALUES_ORDER }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.relPoint", type = "string",
         label = L["Attach point"],
         desc = L["Which point of the target widget the label attaches to."],
         default = "TOP", values = POINT_VALUES, sorting = POINT_VALUES_ORDER }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.offsetX", type = "number",
         label = L["X offset (in px)"],
         desc = L["Horizontal pixel shift (positive = right)."],
         default = 0, min = -200, max = 200, step = 1, fmt = "%d px" }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.offsetY", type = "number",
         label = L["Y offset (in px)"],
         desc = L["Vertical pixel shift (positive = up)."],
         default = 12, min = -200, max = 200, step = 1, fmt = "%d px" }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.justifyH", type = "string",
         label = L["Horizontal justify"],
         desc = L["Horizontal text alignment."],
         default = "CENTER", values = JUSTIFY_H_VALUES, sorting = JUSTIFY_H_VALUES_ORDER }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.justifyV", type = "string",
         label = L["Vertical justify"],
         desc = L["Vertical text alignment."],
         default = "MIDDLE", values = JUSTIFY_V_VALUES, sorting = JUSTIFY_V_VALUES_ORDER }
    -- "deg", never the degree SIGN. U+00B0 is not ASCII, and a glyph the
    -- settings-panel font does not carry renders as an empty box in game and
    -- nowhere else — it cannot fail in a test.
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.rotation", type = "number",
         label = L["Rotation (degrees)"],
         desc = L["Rotate the label. 0 = upright."],
         default = 0, min = -180, max = 180, step = 5, fmt = "%d deg" }

    -- Font ------------------------------------------------------------------
    -- The canonical font block (options-ui-§16), COMPOSED. `keys` keeps every
    -- shipped path -- this addon has always stored the label's typography flat
    -- under `label.style` (font/size/flags/color), and the composer must not
    -- change what is stored:
    --     [Font]         | [Font size]
    --     [Label color]  | [Use class color]
    --     [Font flags]   | [Font shadow]
    --
    -- Font shadow is new here and is honored by modules/UnitLabel.lua's
    -- applyLabelFont. The label NAMES the tracked unit, so its color is
    -- unit-scoped -- and on a linked Focus the style table read is Target's
    -- while the unit drawn is Focus, so modules/UnitLabel.lua resolves on the
    -- RENDERING unit, never on the source of the table.
    H.AddComposed(H.FontGroup{
        prefix = "units." .. unit .. ".label.style.",
        page   = "label", group = L["Font"],
        keys   = {
            font              = "font",
            fontSize          = "size",
            fontColor         = "color",
            useClassColorFont = "useClassColor",
            fontFlags         = "flags",
            fontShadow        = "shadow",
        },
        labels   = { fontColor = L["Label color"] },
        defaults = {
            font       = "Friz Quadrata TT",
            fontSize   = 14,
            fontColor  = { r = 1, g = 0.82, b = 0, a = 1 },
            fontFlags  = "OUTLINE",
            fontShadow = false,
        },
        classColor = { source = "unit", unit = unit },
    }, { panel = "label", section = "label", unit = unit })
end

for _, u in ipairs(NS.Units.LIST) do addUnitRows(u) end

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end
    local ctx
    ctx = H.CreatePanel("KickCDLabelPanel", L["Text Label"], {
        pageKey        = "label",
        defaultsButton = true,
    })
    -- Parked, not wired: the Defaults button doesn't exist until the
    -- panel's first OnShow (H.EnsureDefaultsButton).
    ctx.panel.defaultsOnClick = function()
        H.RestoreDefaults("label", ctx)
    end
    -- The library owns WHEN this draws (H.SetRenderer) and H.RenderUnitPanel
    -- pins the Unit picker into the chrome band above the tab strip; see
    -- settings/Icons.lua's builder for the long form.
    H.SetRenderer(ctx, function(c) H.RenderUnitPanel(c, "label") end)
    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Text Label"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("label", L["Text Label"], Build)
end
