-- settings/Castbar.lua — KickCD v0.2
--
-- Castbar canvas panel. Pure schema: every widget is a row in
-- KickCD.Settings.Schema; the builder just calls Helpers.RenderSchema.
-- Adding a new castbar option means adding one schema row here.

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L
local H      = KickCD.Settings.Helpers
local Schema = KickCD.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

-- Re-skin shortcut: every row's onChange routes through a single hook so
-- the live frame redraws without waiting on the AceMessage round-trip.
local function reskin()
    if KickCD.Castbar and KickCD.Castbar.ApplyConfig then
        KickCD.Castbar:ApplyConfig()
    end
end

-- Visibility ---------------------------------------------------------
add{
    panel = "castbar", section = "castbar", group = L["Visibility"],
    path  = "castbar.enabled", type = "bool",
    label = L["Enable cast bar"],
    tooltip = L["Show the target cast bar."],
    default = true,
    onChange = function()
        if KickCD.Castbar and KickCD.Castbar.OnConfigChanged then
            KickCD.Castbar:OnConfigChanged(nil, { section = "castbar" })
        end
    end,
}

-- Sizing -------------------------------------------------------------
add{
    panel = "castbar", section = "castbar", group = L["Sizing"],
    path  = "castbar.width", type = "number",
    label = L["Width (in px)"],
    tooltip = L["Cast bar width in pixels."],
    default = 250, min = 100, max = 500, step = 5, fmt = "%d px",
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Sizing"],
    path  = "castbar.height", type = "number",
    label = L["Height (in px)"],
    tooltip = L["Cast bar height in pixels."],
    default = 24, min = 10, max = 60, step = 1, fmt = "%d px",
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Sizing"],
    path  = "castbar.iconSize", type = "number",
    label = L["Icon size (in px)"],
    tooltip = L["Spell icon size in pixels (0 hides the icon)."],
    default = 24, min = 0, max = 60, step = 1, fmt = "%d px",
    onChange = reskin,
}

-- Layout -------------------------------------------------------------
add{
    panel = "castbar", section = "castbar", group = L["Layout"],
    path  = "castbar.iconPosition", type = "string",
    label = L["Icon position"],
    tooltip = L["Where to place the spell icon, or hide it entirely."],
    default = "LEFT",
    values  = {
        { value = "LEFT",  label = L["Left"]  },
        { value = "RIGHT", label = L["Right"] },
        { value = "OFF",   label = L["Off"]   },
    },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Layout"],
    path  = "castbar.showSpark", type = "bool",
    label = L["Show spark"],
    tooltip = L["Render the leading-edge spark on the bar."],
    default = true,
    onChange = reskin,
}

-- Text -----------------------------------------------------------------
local TEXT_POSITION_VALUES = {
    { value = "INSIDE_LEFT",   label = L["Inside left"]   },
    { value = "INSIDE_RIGHT",  label = L["Inside right"]  },
    { value = "CENTER",        label = L["Center"]        },
    { value = "OUTSIDE_LEFT",  label = L["Outside left"]  },
    { value = "OUTSIDE_RIGHT", label = L["Outside right"] },
}

add{
    panel = "castbar", section = "castbar", group = L["Text"],
    path  = "castbar.showName", type = "bool",
    label = L["Show spell name"],
    tooltip = L["Display the cast spell's name on the bar."],
    default = true,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Text"],
    path  = "castbar.showTime", type = "bool",
    label = L["Show cast time"],
    tooltip = L["Display the remaining / total cast time on the bar."],
    default = true,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Text"],
    path  = "castbar.font", type = "string",
    label = L["Font"],
    tooltip = L["Font for the spell name and cast time text."],
    default = "Friz Quadrata TT",
    values  = function() return H.LSMValues("font") end,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Text"],
    path  = "castbar.fontSize", type = "number",
    label = L["Font size"],
    tooltip = L["Cast-bar text size in pixels."],
    default = 12, min = 8, max = 24, step = 1, fmt = "%d",
    onChange = reskin,
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
    onChange = reskin,
}

-- Spell name position --------------------------------------------------
add{
    panel = "castbar", section = "castbar", group = L["Spell name position"],
    path  = "castbar.namePosition", type = "string",
    label = L["Anchor"],
    tooltip = L["Where to anchor the spell name relative to the bar."],
    default = "INSIDE_LEFT",
    values  = TEXT_POSITION_VALUES,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Spell name position"],
    path  = "castbar.nameOffsetX", type = "number",
    label = L["X offset (in px)"],
    tooltip = L["Horizontal pixel shift on top of the anchor (positive = right, negative = left)."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Spell name position"],
    path  = "castbar.nameOffsetY", type = "number",
    label = L["Y offset (in px)"],
    tooltip = L["Vertical pixel shift on top of the anchor (positive = up, negative = down)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
    onChange = reskin,
}

-- Cast time position ---------------------------------------------------
add{
    panel = "castbar", section = "castbar", group = L["Cast time position"],
    path  = "castbar.timePosition", type = "string",
    label = L["Anchor"],
    tooltip = L["Where to anchor the remaining-time text relative to the bar."],
    default = "INSIDE_RIGHT",
    values  = TEXT_POSITION_VALUES,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Cast time position"],
    path  = "castbar.timeOffsetX", type = "number",
    label = L["X offset (in px)"],
    tooltip = L["Horizontal pixel shift on top of the anchor (positive = right, negative = left)."],
    default = 0, min = -200, max = 200, step = 1, fmt = "%d px",
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Cast time position"],
    path  = "castbar.timeOffsetY", type = "number",
    label = L["Y offset (in px)"],
    tooltip = L["Vertical pixel shift on top of the anchor (positive = up, negative = down)."],
    default = 0, min = -100, max = 100, step = 1, fmt = "%d px",
    onChange = reskin,
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
    values  = function() return H.LSMValues("statusbar") end,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.barColor", type = "color",
    label = L["Bar color"],
    tooltip = L["RGBA bar fill color when the target's cast is interruptible."],
    default = { 1, 0.85, 0.05, 1 },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.bgColor", type = "color",
    label = L["Background color"],
    tooltip = L["RGBA color drawn behind the bar."],
    default = { 0, 0, 0, 0.5 },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.nameTextColor", type = "color",
    label = L["Spell name color"],
    tooltip = L["RGBA color of the spell-name text."],
    default = { 1, 1, 1, 1 },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.borderShow", type = "bool",
    label = L["Show border"],
    tooltip = L["Draw a border around the cast bar for interruptible casts."],
    default = false,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.borderTexture", type = "string",
    label = L["Border style"],
    tooltip = L["LibSharedMedia border texture (edge style) for interruptible casts."],
    default = "Blizzard Tooltip",
    values  = function() return H.LSMValues("border") end,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.borderColor", type = "color",
    label = L["Border color"],
    tooltip = L["RGBA border color for interruptible casts."],
    default = { 0, 0, 0, 1 },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Interruptible casts"],
    path  = "castbar.interruptible.borderSize", type = "number",
    label = L["Border thickness (in px)"],
    tooltip = L["Border edge size in pixels."],
    default = 1, min = 1, max = 16, step = 1, fmt = "%d px",
    onChange = reskin,
}

-- Uninterruptible appearance ------------------------------------------
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.statusBarTexture", type = "string",
    label = L["Bar texture"],
    tooltip = L["LibSharedMedia statusbar texture used for non-interruptible casts."],
    default = "Blizzard",
    values  = function() return H.LSMValues("statusbar") end,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.barColor", type = "color",
    label = L["Bar color"],
    tooltip = L["RGBA bar fill color when the target's cast cannot be interrupted."],
    default = { 0.85, 0.10, 0.10, 1 },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.bgColor", type = "color",
    label = L["Background color"],
    tooltip = L["RGBA color drawn behind the bar."],
    default = { 0, 0, 0, 0.5 },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.nameTextColor", type = "color",
    label = L["Spell name color"],
    tooltip = L["RGBA color of the spell-name text."],
    default = { 1, 1, 1, 1 },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.borderShow", type = "bool",
    label = L["Show border"],
    tooltip = L["Draw a border around the cast bar for non-interruptible casts."],
    default = true,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.borderTexture", type = "string",
    label = L["Border style"],
    tooltip = L["LibSharedMedia border texture (edge style) for non-interruptible casts."],
    default = "Blizzard Tooltip",
    values  = function() return H.LSMValues("border") end,
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.borderColor", type = "color",
    label = L["Border color"],
    tooltip = L["RGBA border color for non-interruptible casts."],
    default = { 1, 0.20, 0.20, 1 },
    onChange = reskin,
}
add{
    panel = "castbar", section = "castbar", group = L["Non-interruptible casts"],
    path  = "castbar.uninterruptible.borderSize", type = "number",
    label = L["Border thickness (in px)"],
    tooltip = L["Border edge size in pixels."],
    default = 2, min = 1, max = 16, step = 1, fmt = "%d px",
    onChange = reskin,
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

if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("castbar", Build)
end
