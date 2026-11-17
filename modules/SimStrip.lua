local addonName, NS = ...
-- modules/SimStrip.lua — the simulation strip on each HUD display a session plays on (AD-88-KC of
-- Ka0sAddonsCommonTasks docs/2026-11-17-LIBKA0S_V1_105_ADOPTION, ruling 2; LibKa0s#88;
-- WowAddonStandards v2.110.0, preview-mode's *Where the strip sits*).
--
-- While a simulation runs, every icon grid it plays on, and every cast bar the player positions on
-- its own, carries LibKa0s-Widgets-1.0's mode strip in its sim flavor: a cyan band that says the
-- cooldowns and casts under it are not the player's. The library places it (`dock = "hud"`, Widgets
-- minor 27): on the display's top edge, outside it, spanning its width, flipped under its bottom
-- edge when the top would leave the screen, with no mouse and one chrome level band over the
-- display. Nothing here anchors it. The step panel stays up as well (modules/Sim.lua's
-- Host.PinPanel): the strip does not replace it.
--
-- THIS REVERSES RULING D-13 (KC-02 of the 2026-10-30 skin fonts run, image-46), which removed
-- KC-09's floating strip: it was parented to UIParent, so while the grid hid between casts
-- (`target_casting`) it was a cyan bar over nothing. A docked strip is PARENTED TO ITS DISPLAY and
-- hides with it; the panel marks the session while no display shows.
--
-- WHICH DISPLAYS. One strip per enabled unit's grid (`<unit>:icons`). A cast bar on `anchorMode`
-- FREE is a display of its own and carries its own (`<unit>:castbar`); one anchored to its grid's
-- primary icon (PRIMARY, the default) is part of the grid's display, so the grid's strip marks both.
-- THE CLEAR FRAME. A grid's strip stacks beyond the unit's label when the label sits above the grid
-- (UnitLabel:FrameAbove, the default), else beyond an anchored cast bar, which may sit above it; a
-- free bar's strip stacks beyond a label above the bar. The drag handles never show during a
-- session (modules/Sim.lua refuses a sim unlocked and stops one on unlock), so no strip meets one.
--
-- BUILT LAZILY, on the first start: an idle addon holds no strip frame and no bus registration
-- (tests/test_disabled.lua's registration set). While a session runs the strips re-dock on
-- GRID_LAYOUT and CONFIG_CHANGED (a unit enabled, a label moved, a bar set free); the stop hides
-- them and releases both. Without the library's strip there is no strip and no error, and the
-- session runs marked by its panel.

local L = NS.L

local WIDGETS = "LibKa0s-Widgets-1.0"
local GAP = 2   -- px between the strip and what it stacks on

NS.SimStrip = NS.SimStrip or {}
local SimStrip = NS.SimStrip

--- The strips, built on first use: { ["<unit>:icons" | "<unit>:castbar"] = strip }.
SimStrip.__strips = SimStrip.__strips or {}

--- The library's Widgets when it can dock a strip (minor 27), else nil.
local function widgets()
    local W = LibStub and LibStub(WIDGETS, true)
    if W and type(W.TestStrip) == "function" and type(W.DockTestStrip) == "function" then return W end
    return nil
end

local function module(name) return NS.GetModule and NS:GetModule(name, true) or nil end

--- The running scenario's label (its def's `label`, else its name).
local function scenarioLabel()
    local status = NS.Sim and NS.Sim.Status and NS.Sim:Status() or {}
    local name = status.scenario
    local defs = NS.SimHost and NS.SimHost.SCENARIOS and NS.SimHost.SCENARIOS.defs
    local def = defs and name and defs[name]
    return tostring(def and def.label or name or "?")
end

local function anchored(unit) return (NS.Units.Castbar(unit).anchorMode or "PRIMARY") == "PRIMARY" end

local function labelAbove(unit, attach)
    local lbl = module("UnitLabel")
    return lbl and lbl.FrameAbove and lbl:FrameAbove(unit, attach) or nil
end

--- The displays `unit` shows a strip on, as { key, frame, clear } rows; empty while it is disabled.
local function displaysOf(unit)
    if not NS.Units.IsEnabled(unit) then return {} end
    local IconGrid, Castbar = module("IconGrid"), module("Castbar")
    local grid = IconGrid and IconGrid:GetGridFrame(unit) or nil
    local bar = Castbar and Castbar.GetCastbarFrame and Castbar:GetCastbarFrame(unit) or nil
    local rows = {}
    if grid then
        local clear = labelAbove(unit, "icons") or (anchored(unit) and bar) or nil
        rows[#rows + 1] = { key = unit .. ":icons", frame = grid, clear = clear }
    end
    if bar and not anchored(unit) then
        rows[#rows + 1] = { key = unit .. ":castbar", frame = bar, clear = labelAbove(unit, "castbar") }
    end
    return rows
end

--- Dock `row`'s strip on its display, building it on first use; nil when the library cannot.
local function dock(W, row)
    local strip = SimStrip.__strips[row.key]
    local spec = { dock = "hud", target = row.frame, gap = GAP, clear = row.clear }
    if strip and strip:GetParent() == row.frame then
        W.DockTestStrip(strip, spec)
        return strip
    end
    strip = W.TestStrip(row.frame, {
        kind = "sim",
        -- The skin owner (skinning-§1): the strip's legibility follows KickCD's skin; cyan stays
        -- the library's meaning color under every skin (skinning-§7).
        owner = addonName,
        text = "",
        icon = NS.Icon and NS.Icon("info") or nil,
        dock = spec.dock, target = spec.target, gap = spec.gap, clear = spec.clear,
    })
    SimStrip.__strips[row.key] = strip
    return strip
end

--- Dock and show a strip on every display the session plays on; hide the rest. No-op while idle.
function SimStrip:Place()
    if not (NS.Sim and NS.Sim:IsActive()) then return end
    local W = widgets()
    if not W then return end
    local text = L["Simulation: %s - /kcd sim stop ends it."]:format(scenarioLabel())
    local live = {}
    for _, unit in ipairs(NS.Units.LIST) do
        for _, row in ipairs(displaysOf(unit)) do
            local strip = dock(W, row)
            if strip then
                strip.text:SetText(text)
                strip:Show()
                live[row.key] = true
            end
        end
    end
    for key, strip in pairs(self.__strips) do
        if not live[key] then strip:Hide() end
    end
end

local function onBus() SimStrip:Place() end

--- Show the strips iff a simulation runs (and subscribe), else hide them.
function SimStrip:Refresh()
    if not (NS.Sim and NS.Sim:IsActive()) then return self:Hide() end
    if not widgets() then return end   -- no docking strip: the panel marks the session
    self:Place()
    self.__bus = self.__bus or NS.NewBusTarget()
    if self.__bus then
        self.__bus:RegisterMessage(NS.MSG.GRID_LAYOUT, onBus)
        self.__bus:RegisterMessage(NS.MSG.CONFIG_CHANGED, onBus)
    end
end

--- Hide every strip and release the bus subscriptions.
function SimStrip:Hide()
    for _, strip in pairs(self.__strips) do strip:Hide() end
    if self.__bus then self.__bus:UnregisterAllMessages() end
end
