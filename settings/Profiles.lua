-- settings/Profiles.lua
--
-- Profiles canvas panel. Uses the unified header (no Defaults button —
-- profile management has its own destructive controls inside the
-- AceDBOptions UI). The body hosts an AceGUI SimpleGroup container
-- into which AceConfigDialog renders the AceDBOptions options table
-- on first show.

local addonName, NS = ...

local L = NS.L or setmetatable({}, { __index = function(_, k) return k end })

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
    if not (NS.db and NS.db.profile) then return nil end

    local H = NS.Settings and NS.Settings.Helpers
    if not (H and H.CreatePanel) then return nil end

    -- Register the AceConfig options once. AceDBOptions returns a fully
    -- formed options table covering create / switch / copy / reset /
    -- delete plus per-character / per-class / per-realm / per-faction /
    -- default scope dropdowns.
    local opts = AceDBOptions:GetOptionsTable(NS.db)
    AceConfig:RegisterOptionsTable("KickCD-Profiles", opts)

    local ctx = H.CreatePanel("KickCDProfilesPanel", L["Profiles"], {
        pageKey        = "profiles",
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
    --
    -- Through H.SetRenderer rather than a parked OnShow (options-ui-§11,
    -- CX03), for the guard and not for the timing: the Blizzard AddOns
    -- sidebar reaches a canvas panel without going through
    -- OpenOptionsPanel, so a hand-parked handler is the one path into this
    -- page with no combat refusal in front of it -- and it is the path a
    -- player takes mid-fight. The library also builds the Defaults button
    -- here, which is inert on this page (defaultsButton = false above).
    --
    -- The library re-runs a renderer on first show and on the next show
    -- after the page was marked dirty, so "every show" is stated rather
    -- than assumed: H.RefreshPanel on a hidden ctx is exactly the
    -- published way to say "this page's contents changed" (a host that
    -- guessed at the private flag instead is the failure that member was
    -- added for), and the OnHide below arms it. Declaring a renderer does
    -- put this page on H.RefreshAllPanels' fan-out for the first time, but
    -- nothing fires that on a profile switch -- Database:OnProfileChanged
    -- publishes the message bus and stops -- so the OnHide is what actually
    -- keeps the promise in the paragraph above.
    H.SetRenderer(ctx, function()
        AceConfigDialog:Open("KickCD-Profiles", container)
    end)
    ctx.panel:SetScript("OnHide", function()
        H.RefreshPanel(ctx, true)
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Profiles"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("profiles", L["Profiles"], Build)
end
