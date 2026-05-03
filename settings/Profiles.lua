-- settings/Profiles.lua
--
-- Profiles canvas panel. Uses the unified header (no Defaults button —
-- profile management has its own destructive controls inside the
-- AceDBOptions UI). The body hosts an AceGUI SimpleGroup container
-- into which AceConfigDialog renders the AceDBOptions options table
-- on first show.

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")

local L = KickCD.L or setmetatable({}, { __index = function(_, k) return k end })

local Profiles = {}

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end
    if not LibStub then return nil end

    local AceDBOptions    = LibStub("AceDBOptions-3.0",    true)
    local AceConfig       = LibStub("AceConfig-3.0",       true)
    local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
    local AceGUI          = LibStub("AceGUI-3.0",          true)
    if not (AceDBOptions and AceConfig and AceConfigDialog and AceGUI) then
        return nil
    end
    if not (KickCD.db and KickCD.db.profile) then return nil end

    local H = KickCD.Settings and KickCD.Settings.Helpers
    if not (H and H.CreatePanel) then return nil end

    -- Register the AceConfig options once. AceDBOptions returns a fully
    -- formed options table covering create / switch / copy / reset /
    -- delete plus per-character / per-class / per-realm / per-faction /
    -- default scope dropdowns.
    local opts = AceDBOptions:GetOptionsTable(KickCD.db)
    AceConfig:RegisterOptionsTable("KickCD-Profiles", opts)

    local ctx = H.CreatePanel("KickCDProfilesPanel", L["Profiles"], {
        panelKey       = "profiles",
        defaultsButton = false,    -- explicit: per spec, no Defaults here
    })

    -- AceGUI SimpleGroup parented to our body. AceConfigDialog:Open
    -- accepts any AceGUI container as the rendering target; we point
    -- it at this group so the AceDBOptions widgets land inside our
    -- canvas frame instead of opening their own window.
    local container = AceGUI:Create("SimpleGroup")
    container:SetLayout("Fill")
    container.frame:SetParent(ctx.body)
    container.frame:ClearAllPoints()
    container.frame:SetPoint("TOPLEFT",     ctx.body, "TOPLEFT",      8, -8)
    container.frame:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -8, 8)

    -- Open lazily on first show. Re-Open()ing on every show is cheap
    -- (AceConfigDialog reuses the existing widget tree if one exists)
    -- and ensures the UI reflects the current profile after a switch.
    ctx.panel:SetScript("OnShow", function()
        AceConfigDialog:Open("KickCD-Profiles", container)
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Profiles"])
end

if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("profiles", Build)
end
