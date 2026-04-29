-- settings/General.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §5.2 and docs/REQUIREMENTS.md FR-6.2.1, FR-8
--
-- General widgets live directly on the top-level "Ka0s KickCD" category
-- (no "General" subcategory). Three sections:
--   * Master controls — enable, lock
--   * Appearance      — global scale + alpha
--   * Position        — reset position button
--
-- Every setter writes to db.profile and fires
--   KickCD_CONFIG_CHANGED { section = "general" }
-- so that IconGrid live-updates without a /reload (FR-6.4).

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L

-- Builder is invoked by Panel.lua once the main Settings category exists.
local function Build(mainCategory)
    if not Settings then return nil end

    local H = KickCD.Settings.Helpers

    -- ---------------------------------------------------------------
    -- Section: Master controls
    -- ---------------------------------------------------------------
    H.CreateCheckbox(mainCategory, "KickCD_general_enabled",
        L["Enable KickCD"],
        L["Master enable for the addon."],
        "general", "enabled")

    H.CreateCheckbox(mainCategory, "KickCD_general_locked",
        L["Lock frame"],
        L["When unlocked, you can drag the icon grid to reposition it."],
        "general", "locked")

    -- ---------------------------------------------------------------
    -- Section: Appearance
    -- ---------------------------------------------------------------
    H.AddSectionHeader(mainCategory, L["Scale"] .. " / " .. L["Alpha"])

    H.CreateSlider(mainCategory, "KickCD_general_scale",
        L["Scale"],
        L["Master scale for the entire addon."],
        "general", "scale",
        0.5, 2.0, 0.05, "%.2fx")

    H.CreateSlider(mainCategory, "KickCD_general_alpha",
        L["Alpha"],
        L["Global alpha for the icon grid."],
        "general", "alpha",
        0.0, 1.0, 0.05, "%.2f")

    -- ---------------------------------------------------------------
    -- Section: Position
    -- ---------------------------------------------------------------
    H.AddSectionHeader(mainCategory, L["Reset position"])

    -- Reset button: restores the icon grid anchor to the documented default
    -- (TECHNICAL_DESIGN §4 / REQUIREMENTS FR-8.1) and fires a general
    -- CONFIG_CHANGED + an "icons" CONFIG_CHANGED so IconGrid re-applies the
    -- anchor and re-runs ApplyLock().
    local function resetPosition()
        if not (KickCD.db and KickCD.db.profile) then return end
        KickCD.db.profile.anchors = KickCD.db.profile.anchors or {}
        KickCD.db.profile.anchors.icons =
            { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }
        H.FireConfigChanged("general")
        H.FireConfigChanged("icons")
    end
    H.AddButton(mainCategory, L["Reset position"],
        L["Reset position"], resetPosition)

    return mainCategory
end

-- Register the builder with Panel.lua. Panel will invoke it when the main
-- category is ready (immediately if Settings is already initialized, or
-- on PLAYER_LOGIN / ADDON_LOADED("Blizzard_Settings") otherwise).
if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("general", Build)
end
