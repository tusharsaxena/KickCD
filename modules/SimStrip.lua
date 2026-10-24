local _, NS = ...
-- modules/SimStrip.lua — the simulation strip over the icon grids (KickCD#38, KC-09; OWNER_SCOPE B2).
--
-- While a simulation runs, every icon grid it plays on carries LibKa0s-Widgets-1.0's mode strip in
-- its sim flavor (`W.TestStrip(parent, { kind = "sim", ... })`, Widgets minor 14): a cyan band that
-- says the cooldowns under it are not the player's. It is the session's marker (the Sim major's
-- preview-mode rule, H8). The library's step panel marks the session too; the strip marks the
-- thing a player actually looks at, which is the grid.
--
-- ONE STRIP PER ENABLED GRID. KickCD draws a target grid and a focus grid, and both play the
-- simulation, so each enabled unit gets its own strip, BOTTOM to the grid's TOP, 2 px clear. When the
-- unit's label sits above the grid (the default), the strip goes above the LABEL instead: the same
-- rule the unlocked drag strip follows (modules/IconGrid_Handle.lua anchorHandle), through the same
-- UnitLabel:FrameAbove call, because the label is what tells the two grids apart. With both units
-- disabled mid-session there is no grid to mark, so the target's strip floats at UIParent CENTER
-- 0, 180 rather than vanish while the session still runs.
--
-- PARENTED TO UIParent, NOT THE GRID. The visibility mode hides a grid between casts
-- (`target_casting`), and a strip parented to it would vanish with it, so a running simulation
-- would look like no simulation. The strip copies the grid's effective scale instead, so it still
-- lines up with a scaled grid, and is as wide as the grid with a 220 px floor (its text must fit).
--
-- BUILT LAZILY, on the first start: an idle addon holds no strip frame and no bus registration
-- (tests/test_disabled.lua's registration set). While shown it re-places on GRID_LAYOUT and
-- CONFIG_CHANGED; on hide it releases both. Without the library's sim flavor (Widgets absent or
-- older than minor 14) there is no strip and no error, and the session runs marked by its panel.

local L = NS.L

local WIDGETS, SIM_FLAVOR_MINOR = "LibKa0s-Widgets-1.0", 14
local STRIP_MIN_W, STRIP_GAP = 220, 2
local FLOAT_Y = 180
local UNITS = { "target", "focus" }

NS.SimStrip = NS.SimStrip or {}
local SimStrip = NS.SimStrip

--- The strips, built on first use: { [unit] = frame }. `__frame` is the primary one (the target's
--- while target is enabled, else the focus's, else the floating target strip).
SimStrip.__frames = SimStrip.__frames or {}

--- The library's strip constructor when it carries the sim flavor, else nil.
local function constructor()
    if not LibStub then return nil end
    local W, minor = LibStub(WIDGETS, true)
    if not (W and type(W.TestStrip) == "function" and (minor or 0) >= SIM_FLAVOR_MINOR) then return nil end
    return W
end

--- The running scenario's label (its def's `label`, else its name).
local function scenarioLabel()
    local status = NS.Sim and NS.Sim.Status and NS.Sim:Status() or {}
    local name = status.scenario
    local defs = NS.SimHost and NS.SimHost.SCENARIOS and NS.SimHost.SCENARIOS.defs
    local def = defs and name and defs[name]
    return tostring(def and def.label or name or "?")
end

--- This unit's strip, built on first use; nil when the library cannot draw one.
local function stripFor(unit)
    local frame = SimStrip.__frames[unit]
    if frame then return frame end
    local W = constructor()
    if not W then return nil end
    frame = W.TestStrip(UIParent, {
        kind = "sim",
        text = "",
        icon = NS.Icon and NS.Icon("info") or nil,
    })
    if not frame then return nil end
    -- The HUD's strata, at the top of the HUD band (HUD.MARKER): the marker that
    -- the display under it is fake never draws under that display, the floating
    -- case included (KIC-Z08). It shares the handles' slot only because the two
    -- never show together (modules/Sim.lua refuses a sim unlocked, stops on unlock).
    frame:SetFrameStrata(NS.Const.LAYERS.STRATA.HUD)
    frame:SetFrameLevel(UIParent:GetFrameLevel() + NS.Const.LAYERS.LEVEL.HUD.MARKER)
    if frame.EnableMouse then frame:EnableMouse(false) end
    SimStrip.__frames[unit] = frame
    return frame
end

--- Anchor one strip over `unit`'s grid (above its label when the label sits there), or float it.
local function placeOne(frame, unit)
    local IconGrid = NS:GetModule("IconGrid", true)
    local grid = unit and IconGrid and IconGrid:GetGridFrame(unit) or nil
    local lbl = NS:GetModule("UnitLabel", true)
    local above = unit and lbl and lbl.FrameAbove and lbl:FrameAbove(unit, "icons") or nil
    local anchor = above or grid
    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("BOTTOM", anchor, "TOP", 0, STRIP_GAP)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, FLOAT_Y)
        anchor = UIParent
    end
    local gridScale = grid and grid.GetEffectiveScale and grid:GetEffectiveScale()
    local rootScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    if gridScale and rootScale and rootScale > 0 then frame:SetScale(gridScale / rootScale) end
    frame:SetWidth(math.max(STRIP_MIN_W, grid and grid:GetWidth() or 0))
    frame.__anchorTo = anchor
    frame:Show()
end

--- Place every strip: one per enabled unit's grid, the rest hidden; with no unit enabled, the
--- target's strip floats. No-op while no simulation runs.
function SimStrip:Place()
    if not (NS.Sim and NS.Sim:IsActive()) then return end
    local enabled, primary = {}, nil
    for _, unit in ipairs(UNITS) do
        enabled[unit] = NS.Units.IsEnabled(unit)
        if enabled[unit] and not primary then primary = unit end
    end
    for _, unit in ipairs(UNITS) do
        local floating = (primary == nil and unit == "target")
        if enabled[unit] or floating then
            local frame = stripFor(unit)
            if frame then placeOne(frame, enabled[unit] and unit or nil) end
        elseif self.__frames[unit] then
            self.__frames[unit]:Hide()
        end
    end
    self.__frame = self.__frames[primary or "target"]
end

local function onBus() SimStrip:Place() end

--- Show the strips iff a simulation runs: set their text, place them and subscribe; else hide.
function SimStrip:Refresh()
    if not (NS.Sim and NS.Sim:IsActive()) then return self:Hide() end
    if not constructor() then return end   -- no sim flavor: the panel marks the session
    local text = L["Simulation: %s - /kcd sim stop ends it."]:format(scenarioLabel())
    for _, unit in ipairs(UNITS) do
        local frame = stripFor(unit)
        if frame then frame.text:SetText(text) end
    end
    self:Place()
    self.__bus = self.__bus or NS.NewBusTarget()
    if self.__bus then
        self.__bus:RegisterMessage(NS.MSG.GRID_LAYOUT, onBus)
        self.__bus:RegisterMessage(NS.MSG.CONFIG_CHANGED, onBus)
    end
end

--- Hide every strip and release the bus subscriptions.
function SimStrip:Hide()
    for _, frame in pairs(self.__frames) do frame:Hide() end
    if self.__bus then self.__bus:UnregisterAllMessages() end
end
