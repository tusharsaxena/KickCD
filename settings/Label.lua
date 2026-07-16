-- settings/Label.lua
--
-- "Text Label" canvas panel. One identity label per unit (target/focus),
-- rendered by modules/UnitLabel.lua. Pure schema: every widget is a row in
-- KickCD.Settings.Schema, generated once per NS.Units.LIST entry with a
-- unit-scoped path (units.<unit>.label.*). show/text stay per-unit in the
-- DB, but no row here sets alwaysPerUnit, so a linked Focus page collapses
-- to just the "Linked to Target" note like Icons/Cast bar — unlink to edit
-- show/text (the label still renders per-unit while linked, just not
-- editable on this page).
-- Uses the shared unit-selector header via Helpers.RenderUnitPanel.

local addonName, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Schema = NS.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

local POINT_VALUES = {
    { value = "TOPLEFT",     label = L["Top left"]     },
    { value = "TOP",         label = L["Top"]          },
    { value = "TOPRIGHT",    label = L["Top right"]    },
    { value = "LEFT",        label = L["Left"]         },
    { value = "CENTER",      label = L["Center"]       },
    { value = "RIGHT",       label = L["Right"]        },
    { value = "BOTTOMLEFT",  label = L["Bottom left"]  },
    { value = "BOTTOM",      label = L["Bottom"]       },
    { value = "BOTTOMRIGHT", label = L["Bottom right"] },
}

local JUSTIFY_H_VALUES = {
    { value = "LEFT",   label = L["Left"]   },
    { value = "CENTER", label = L["Center"] },
    { value = "RIGHT",  label = L["Right"]  },
}
local JUSTIFY_V_VALUES = {
    { value = "TOP",    label = L["Top"]    },
    { value = "MIDDLE", label = L["Middle"] },
    { value = "BOTTOM", label = L["Bottom"] },
}
local FLAG_VALUES = {
    { value = "NONE",         label = L["None"]          },
    { value = "OUTLINE",      label = L["Outline"]       },
    { value = "THICKOUTLINE", label = L["Thick outline"] },
    { value = "MONOCHROME",   label = L["Monochrome"]    },
}
local ATTACH_VALUES = {
    { value = "castbar", label = L["Cast bar"]  },
    { value = "icons",   label = L["Icon grid"] },
}

local function addUnitRows(unit)
    -- Identity (per-unit even when linked) --------------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["Label"],
         path = "units." .. unit .. ".label.show", type = "bool",
         label = L["Show label"],
         tooltip = L["Show this unit's identity label."],
         default = true }
    add{ panel = "label", section = "label", unit = unit, group = L["Label"],
         path = "units." .. unit .. ".label.text", type = "string",
         label = L["Label text"],
         tooltip = L["Text shown on this unit's label."],
         default = (unit == "target" and "Target" or "Focus") }

    -- Placement -----------------------------------------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.attach", type = "string",
         label = L["Attach to"],
         tooltip = L["Which widget the label anchors to."],
         default = "castbar", values = ATTACH_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.point", type = "string",
         label = L["Label anchor point"],
         tooltip = L["Which point of the label attaches."],
         default = "BOTTOM", values = POINT_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.relPoint", type = "string",
         label = L["Attach point"],
         tooltip = L["Which point of the target widget the label attaches to."],
         default = "TOP", values = POINT_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.offsetX", type = "number",
         label = L["X offset (in px)"],
         tooltip = L["Horizontal pixel shift (positive = right)."],
         default = 0, min = -200, max = 200, step = 1, fmt = "%d px" }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.offsetY", type = "number",
         label = L["Y offset (in px)"],
         tooltip = L["Vertical pixel shift (positive = up)."],
         default = 12, min = -200, max = 200, step = 1, fmt = "%d px" }

    -- Orientation ---------------------------------------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["Orientation"],
         path = "units." .. unit .. ".label.style.justifyH", type = "string",
         label = L["Horizontal justify"],
         tooltip = L["Horizontal text alignment."],
         default = "CENTER", values = JUSTIFY_H_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Orientation"],
         path = "units." .. unit .. ".label.style.justifyV", type = "string",
         label = L["Vertical justify"],
         tooltip = L["Vertical text alignment."],
         default = "MIDDLE", values = JUSTIFY_V_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Orientation"],
         path = "units." .. unit .. ".label.style.rotation", type = "number",
         label = L["Rotation (degrees)"],
         tooltip = L["Rotate the label. 0 = upright."],
         default = 0, min = -180, max = 180, step = 5, fmt = "%d°" }

    -- Font ----------------------------------------------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["Font"],
         path = "units." .. unit .. ".label.style.font", type = "string",
         label = L["Font"],
         tooltip = L["LSM font for the label."],
         default = "Friz Quadrata TT", lsm = "font",
         values = function() return H.LSMValues("font") end }
    add{ panel = "label", section = "label", unit = unit, group = L["Font"],
         path = "units." .. unit .. ".label.style.size", type = "number",
         label = L["Font size"],
         tooltip = L["Label font size in pixels."],
         default = 14, min = 6, max = 48, step = 1, fmt = "%d" }
    add{ panel = "label", section = "label", unit = unit, group = L["Font"],
         path = "units." .. unit .. ".label.style.flags", type = "string",
         label = L["Font flags"],
         tooltip = L["Outline / monochrome flags."],
         default = "OUTLINE", values = FLAG_VALUES }
end

for _, u in ipairs(NS.Units.LIST) do addUnitRows(u) end

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end
    local ctx
    ctx = H.CreatePanel("KickCDLabelPanel", L["Text Label"], {
        panelKey       = "label",
        defaultsButton = true,
    })
    if ctx.panel.defaultsBtn then
        ctx.panel.defaultsBtn:SetCallback("OnClick", function()
            H.RestoreDefaults("label", ctx)
        end)
    end
    local rendered = false
    ctx.panel:SetScript("OnShow", function()
        if rendered then return end
        rendered = true
        H.RenderUnitPanel(ctx, "label")
    end)
    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Text Label"])
end

if NS.Settings and NS.Settings.RegisterTab then
    NS.Settings.RegisterTab("label", Build)
end
