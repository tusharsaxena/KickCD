-- modules/UnitLabel.lua
--
-- One identity label per unit (target/focus). A holder frame parented to
-- UIParent (so the label's show state + alpha are INDEPENDENT of the attach
-- target's visibility) is SetPoint-anchored to the chosen attach frame —
-- the unit's cast bar or icon grid — so it tracks that frame's position
-- live with no per-frame bookkeeping. Appearance is link-resolved for a
-- linked Focus via NS.Units.LabelStyle; show/text stay per-unit via
-- NS.Units.Label. Replaces the two labels the dual-tracking work put on the
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

function UnitLabel:EnsureFrame(inst)
    if inst.frame then return end
    local f = CreateFrame("Frame", "KickCDUnitLabel" .. titleCase(inst.unit), UIParent)
    f:SetSize(1, 1)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    inst.frame, inst.text = f, fs
end

--- Resolve + apply this unit's label: text (per-unit), appearance (link-
--- resolved), and position (anchored to the chosen attach frame). Shown
--- only when the unit is enabled, label.show is on, AND an attach frame
--- exists — independent of whether that frame is currently drawn.
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
    fs:SetJustifyH(style.justifyH or "CENTER")
    fs:SetJustifyV(style.justifyV or "MIDDLE")
    if fs.SetRotation then
        fs:SetRotation(((style.rotation or 0) * math.pi) / 180)
    end

    local target = attachFrame(inst.unit, style.attach or "castbar")
    f:ClearAllPoints()
    if target then
        f:SetPoint(style.point or "BOTTOM", target, style.relPoint or "TOP",
                   style.offsetX or 0, style.offsetY or 0)
    end

    inst.enabled = NS.Units.IsEnabled(inst.unit)
    f:SetShown(inst.enabled and lbl.show == true and target ~= nil)
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
