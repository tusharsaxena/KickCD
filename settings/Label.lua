-- settings/Label.lua
--
-- The Units page's "Text label" entry (KickCD#33). One identity label per unit (target/focus),
-- rendered by modules/UnitLabel.lua. Pure schema: every widget is a row in
-- KickCD.Settings.Schema, generated once per NS.Units.LIST entry with a
-- unit-scoped path (units.<unit>.label.*). label.show FOLLOWS the styling link
-- (spec 2b, resolved via NS.Units.LabelShow) — a linked Focus mirrors Target's
-- show, so the show row is a normal styled row and correctly collapses into the
-- "Linked to Target" note when linked. label.text stays per-unit (spec 2a), and
-- since item 020 (KIC-L05) its row is `alwaysPerUnit`: a linked Focus still
-- draws it, on General above the note, so renaming Focus's label no longer means
-- unlinking (which forks Focus's whole look). The flag changes the UI only --
-- Units.CopyStyling copies by path prefix and leaves label.text out, and only
-- Helpers.PartitionUnitRows reads alwaysPerUnit. Uses the shared Unit band + tab
-- strip via RenderUnitPanel, under the Units page's rail.

local _, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Store  = NS.Settings.Store

-- Through the seam's registry (settings/SchemaSetup.lua), so Store.FindRow
-- indexes the row the moment it lands.
local function add(t) Store.AddRows({ t }) end

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
-- The first used to be called "Label" on a page called Text label, which told
-- the reader nothing the page had not already said; it is General now, the way
-- every first tab in this addon is.
--
-- Orientation used to be a tab of its own — horizontal alignment, vertical
-- alignment, rotation. It is inside Placement now, under its own heading. Two tabs next to each other,
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
         default = (unit == "target" and "Target" or "Focus"),
         alwaysPerUnit = true }

    -- Placement -------------------------------------------------------------
    -- Two subjects since item 020 (KIC-L23), so two headings (options-ui-§7):
    --     Position   [Attach to]                                          (solo)
    --                [Attached widget anchor point] | [Label anchor point]
    --                [X offset (px)]                | [Y offset (px)]
    --     Alignment  [Horizontal alignment]         | [Vertical alignment]
    --                [Rotation (degrees)]
    --
    -- `attach` is solo because it is a genuine pivot rather than spacing: which
    -- widget the label hangs off decides what the two anchor points underneath
    -- it even refer to. Below it every line is a pair read ACROSS -- the two
    -- anchor points, the two offsets, the two alignments -- because in each case
    -- the reader's question is how the two compare, not what one of them is on
    -- its own. The anchor pair names both elements, target first (XC-32,
    -- KIC-L24): the attached widget's point, then the label's own.
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         subgroup = L["Position"],
         path = "units." .. unit .. ".label.style.attach", type = "string",
         label = L["Attach to"],
         desc = L["Which widget the label anchors to."],
         default = "icons", values = ATTACH_VALUES, sorting = ATTACH_VALUES_ORDER,
         solo = true }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         subgroup = L["Position"],
         path = "units." .. unit .. ".label.style.relPoint", type = "string",
         label = L["Attached widget anchor point"],
         desc = L["Which point of the widget chosen in Attach to the label attaches to."],
         default = "TOP", values = POINT_VALUES, sorting = POINT_VALUES_ORDER }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         subgroup = L["Position"],
         path = "units." .. unit .. ".label.style.point", type = "string",
         label = L["Label anchor point"],
         desc = L["Which point of the label attaches."],
         default = "BOTTOM", values = POINT_VALUES, sorting = POINT_VALUES_ORDER }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         subgroup = L["Position"],
         path = "units." .. unit .. ".label.style.offsetX", type = "number",
         label = L["X offset (px)"],
         desc = L["Horizontal pixel shift (positive = right)."],
         default = 0, min = -200, max = 200, step = 1, fmt = "%d px" }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         subgroup = L["Position"],
         path = "units." .. unit .. ".label.style.offsetY", type = "number",
         label = L["Y offset (px)"],
         desc = L["Vertical pixel shift (positive = up)."],
         default = 12, min = -200, max = 200, step = 1, fmt = "%d px" }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         subgroup = L["Alignment"],
         path = "units." .. unit .. ".label.style.justifyH", type = "string",
         label = L["Horizontal alignment"],
         desc = L["Horizontal text alignment."],
         default = "CENTER", values = JUSTIFY_H_VALUES, sorting = JUSTIFY_H_VALUES_ORDER }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         subgroup = L["Alignment"],
         path = "units." .. unit .. ".label.style.justifyV", type = "string",
         label = L["Vertical alignment"],
         desc = L["Vertical text alignment."],
         default = "MIDDLE", values = JUSTIFY_V_VALUES, sorting = JUSTIFY_V_VALUES_ORDER }
    -- "deg", never the degree SIGN. U+00B0 is not ASCII, and a glyph the
    -- settings-panel font does not carry renders as an empty box in game and
    -- nowhere else — it cannot fail in a test.
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         subgroup = L["Alignment"],
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
        -- "Use the skin's font" (`label.style.fontFromSkin`, default true, X3): the face only.
        fromSkin = true,
        defaults = {
            font       = "Friz Quadrata TT",
            fontSize   = 14,
            fontColor  = { r = 1, g = 0.82, b = 0, a = 1 },
            fontFlags  = "OUTLINE",
            fontShadow = false,
            fontFromSkin = true,
        },
        classColor = { source = "unit", unit = unit },
    }, { panel = "label", section = "label", unit = unit })
end

for _, u in ipairs(NS.Units.LIST) do addUnitRows(u) end

-- The Text label entry of the Units page (KickCD#33). Sentence case (KIC-L07).
H.RegisterGridSection("label", L["Text label"], {
    tooltip = L["The unit's identity label: what it says, where it sits and its font."],
})
