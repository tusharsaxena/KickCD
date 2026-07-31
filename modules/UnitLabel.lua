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

-- OUTLINE-family flag string fed to FontString:SetFont. "NONE" -> "".
local FLAG_MAP = {
    NONE = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", MONOCHROME = "MONOCHROME",
}

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

    local fontPath
    if LSM and LSM.Fetch then
        fontPath = LSM:Fetch("font", style.font or "Friz Quadrata TT", true)
    end
    fs:SetFont(fontPath or STANDARD_TEXT_FONT, style.size or 14, FLAG_MAP[style.flags] or "OUTLINE")
    -- Through Util.Unpack, not by index. Colours are stored keyed now
    -- ({ r =, g =, b =, a = }); a positional read would have found nil on
    -- every channel and rendered the fallback gold no matter what the user
    -- picked — silently, and only in game.
    local c = style.color
    if c then
        local r, g, b, a = NS.Util.Unpack(c)
        fs:SetTextColor(r, g, b, a)
    end
    fs:SetJustifyH(style.justifyH or "CENTER")
    fs:SetJustifyV(style.justifyV or "MIDDLE")
    if fs.SetRotation then
        fs:SetRotation(((style.rotation or 0) * math.pi) / 180)
    end

    -- Position comes from the chosen attach frame; VISIBILITY comes from the
    -- icon grid. The grid is the frame that honors General visibility
    -- (IconGrid:RefreshVisibility Show/Hides it on the visibility mode alone),
    -- whereas the cast bar additionally hides itself whenever there is no
    -- active cast — so parenting to the cast bar would make the label
    -- cast-gated instead of visibility-gated. Reparenting the label onto the
    -- grid makes it inherit exactly the grid's shown state + effective alpha,
    -- i.e. follow General visibility, with no extra event wiring; SetPoint to
    -- the attach frame keeps position independent of the parent.
    local anchorFrame = attachFrame(inst.unit, style.attach or "castbar")
    local gridModule  = NS:GetModule("IconGrid", true)
    local visFrame    = gridModule and gridModule:GetGridFrame(inst.unit) or nil

    f:ClearAllPoints()
    if anchorFrame then
        f:SetParent(visFrame or anchorFrame)  -- grid drives visibility; fall back to the anchor only if the grid isn't up yet
        f:SetPoint(style.point or "BOTTOM", anchorFrame, style.relPoint or "TOP",
                   style.offsetX or 0, style.offsetY or 0)
    end

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
