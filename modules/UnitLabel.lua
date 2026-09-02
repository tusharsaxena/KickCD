-- modules/UnitLabel.lua
--
-- One identity label per unit (target/focus). A holder frame is created on
-- UIParent, then on Apply is REPARENTED to the unit's ICON GRID — the frame
-- that honors General visibility on the visibility mode alone — so it
-- inherits the grid's shown state and effective alpha for free (i.e. it
-- follows the addon's General visibility, without being cast-gated by a
-- cast bar that hides itself between casts). Its POSITION still tracks the
-- chosen attach frame (cast bar or grid) live via SetPoint, independent of
-- the visibility parent, with no per-frame bookkeeping.
-- Appearance is link-resolved for a linked Focus via NS.Units.LabelStyle, and
-- visibility (show) via NS.Units.LabelShow; only the text stays per-unit
-- (NS.Units.Label). Replaces the two labels the dual-tracking work put on the
-- grid and cast bar directly.
--
-- The label text is a plain addon string (NS.Units.Label(unit).text), never
-- a 12.0 secret value, so SetText/SetFont on it are safe.

local addonName, NS = ...
local UnitLabel = NS:NewModule("UnitLabel", "AceEvent-3.0")

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- OUTLINE-family flag string fed to FontString:SetFont. The library's canonical
-- set spells "no flags" as the EMPTY STRING, which is a real stored value and
-- has to map to itself -- `FLAG_MAP[""] or "OUTLINE"` would otherwise fall
-- through to an outline nobody asked for. "NONE" is the pre-v5 token and stays
-- mapped for the frame or two before core/Database.lua's migration lands.
local FLAG_MAP = {
    [""] = "", NONE = "",
    OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", MONOCHROME = "MONOCHROME",
    ["OUTLINE, MONOCHROME"] = "OUTLINE, MONOCHROME",
}

-- Fallback for every style field Apply reads, in one place. `flags` is
-- deliberately absent: it defaults through FLAG_MAP above, which maps the
-- stored token rather than the field itself.
local STYLE_DEFAULTS = {
    font     = "Friz Quadrata TT",
    size     = 14,
    justifyH = "CENTER",
    justifyV = "MIDDLE",
    rotation = 0,
    attach   = "castbar",
    point    = "BOTTOM",
    relPoint = "TOP",
    offsetX  = 0,
    offsetY  = 0,
}

--- One style field with its fallback applied. Truthiness, not `== nil`, so
--- this reads exactly like the `style.x or default` chain it replaces — an
--- unset field and a falsy one both land on the default, as before.
local function sv(style, key)
    local v = style[key]
    if v then return v end
    return STYLE_DEFAULTS[key]
end

local instances = {}   -- [unit] = { unit, frame, text, enabled }

local function titleCase(unit) return unit:sub(1, 1):upper() .. unit:sub(2) end

function UnitLabel:GetInstance(unit)
    unit = unit or "target"
    local inst = instances[unit]
    if not inst then inst = { unit = unit, frame = nil, text = nil, enabled = false }; instances[unit] = inst end
    return inst
end

-- The frame this unit's label anchors to, or nil if that widget isn't live.
local function attachFrame(unit, attach)
    if attach == "icons" then
        local m = NS:GetModule("IconGrid", true)
        return m and m:GetGridFrame(unit) or nil
    end
    local m = NS:GetModule("Castbar", true)
    return m and m:GetCastbarFrame(unit) or nil
end

--- Font face, size and outline flags. LSM is optional (the addon runs without
--- it), and its Fetch can still miss, so the client's own font is the last
--- resort.
local function applyLabelFont(fs, style)
    local fontPath
    if LSM and LSM.Fetch then
        fontPath = LSM:Fetch("font", sv(style, "font"), true)
    end
    fs:SetFont(fontPath or STANDARD_TEXT_FONT, sv(style, "size"), FLAG_MAP[style.flags] or "OUTLINE")

    -- The drop shadow (options-ui-§16's sixth font row). SET OR CLEARED on every
    -- apply: the FontString outlives a config change, so leaving the old offset
    -- in place is how a shadow the user just turned off stays on screen.
    if style.shadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(0, 0, 0, 0)
    end
end

--- Text color, when the user picked one — otherwise the font template's own.
---
--- Through NS.ResolveColor (LibKa0s-Core-1.0), so the "Use class color"
--- companion beside the swatch is honored here in the one place, with the
--- collection's rules: the stored ALPHA always applies, and an unresolvable
--- class falls through to the stored swatch rather than to a substitute hue.
---
--- `unit` IS THE UNIT BEING DRAWN, not the unit the style table came from. A
--- linked Focus reads Target's `label.style` (NS.Units.LabelStyle resolves the
--- link) and still draws beside the FOCUS frame, so the class a reader expects
--- to see is their focus's — options-ui-§17's "the unit the surface describes".
local function applyLabelColor(fs, style, unit)
    local c = style.color
    if c then
        fs:SetTextColor(NS.ResolveColor(c, style.useClassColor, unit))
    end
end

--- Position comes from the chosen attach frame; VISIBILITY comes from the
--- icon grid. The grid is the frame that honors General visibility
--- (IconGrid:RefreshVisibility Show/Hides it on the visibility mode alone),
--- whereas the cast bar additionally hides itself whenever there is no
--- active cast — so parenting to the cast bar would make the label
--- cast-gated instead of visibility-gated. Reparenting the label onto the
--- grid makes it inherit exactly the grid's shown state + effective alpha,
--- i.e. follow General visibility, with no extra event wiring; SetPoint to
--- the attach frame keeps position independent of the parent.
--- Returns the anchor frame (nil when that widget isn't live), which also
--- gates visibility.
local function applyLabelPlacement(f, unit, style)
    local anchorFrame = attachFrame(unit, sv(style, "attach"))
    local gridModule  = NS:GetModule("IconGrid", true)
    local visFrame    = gridModule and gridModule:GetGridFrame(unit) or nil

    f:ClearAllPoints()
    if anchorFrame then
        f:SetParent(visFrame or anchorFrame)  -- grid drives visibility; fall back to the anchor only if the grid isn't up yet
        f:SetPoint(sv(style, "point"), anchorFrame, sv(style, "relPoint"),
                   sv(style, "offsetX"), sv(style, "offsetY"))
    end
    return anchorFrame
end

-- Created on UIParent as a placeholder parent; Apply() reparents it to the
-- unit's icon grid once one exists, so its live parent (and therefore its
-- General-visibility show/hide + alpha) tracks the grid, not whichever
-- widget it's positionally anchored to.
function UnitLabel:EnsureFrame(inst)
    if inst.frame then return end
    local f = CreateFrame("Frame", "KickCDUnitLabel" .. titleCase(inst.unit), UIParent)
    f:SetSize(1, 1)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    inst.frame, inst.text = f, fs
end

--- Resolve + apply this unit's label: text (per-unit), appearance + show
--- (both link-resolved), and position (anchored to the chosen attach frame).
--- Shown only when the unit is enabled, the link-resolved show is on, AND an
--- attach frame exists. The holder frame is reparented to the unit's ICON GRID (not the
--- attach frame), so it inherits the grid's own shown state + alpha — i.e.
--- the label follows the addon's General visibility, while its position
--- still tracks the chosen attach frame.
function UnitLabel:Apply(inst)
    self:EnsureFrame(inst)
    local lbl   = NS.Units.Label(inst.unit)
    local style = NS.Units.LabelStyle(inst.unit)
    local fs, f = inst.text, inst.frame

    fs:SetText(lbl.text or "")

    applyLabelFont(fs, style)
    applyLabelColor(fs, style, inst.unit)
    fs:SetJustifyH(sv(style, "justifyH"))
    fs:SetJustifyV(sv(style, "justifyV"))
    if fs.SetRotation then
        fs:SetRotation((sv(style, "rotation") * math.pi) / 180)
    end

    local anchorFrame = applyLabelPlacement(f, inst.unit, style)

    -- Visibility follows the styling link (spec 2b): a linked focus mirrors
    -- target's label.show, so hiding the target label hides a linked focus too.
    -- (Text above stays per-unit.) IsEnabled + an attach frame still gate it.
    inst.enabled = NS.Units.IsEnabled(inst.unit)
    f:SetShown(inst.enabled and NS.Units.LabelShow(inst.unit) and anchorFrame ~= nil)
end

function UnitLabel:ApplyAll()
    for _, u in ipairs(NS.Units.LIST) do
        self:Apply(self:GetInstance(u))
    end
end

-- A label edit, a per-unit enable toggle, or — for a linked Focus — an
-- icons/castbar edit can all change the resolved label or its anchor, so
-- re-apply on any CONFIG_CHANGED. Cheap: two SetText/SetPoint passes.
function UnitLabel:OnConfigChanged() self:ApplyAll() end
function UnitLabel:OnProfileChanged() self:ApplyAll() end
-- A grid (re)created after we first anchored needs a fresh SetPoint target.
function UnitLabel:OnGridLayout() self:ApplyAll() end
function UnitLabel:OnPlayerEnteringWorld() self:ApplyAll() end

function UnitLabel:OnEnable()
    self:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", "OnProfileChanged")
    self:RegisterMessage("Ka0s_KickCD_GRID_LAYOUT",     "OnGridLayout")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")
    self:ApplyAll()
end

function UnitLabel:OnDisable()
    self:UnregisterAllMessages()
    self:UnregisterAllEvents()
    for _, inst in pairs(instances) do
        if inst.frame then inst.frame:Hide() end
    end
end
