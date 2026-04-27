-- settings/General.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §5.2 and docs/REQUIREMENTS.md FR-6.2.1, FR-8
--
-- General widgets live directly on the top-level "Ka0s KickCD" category
-- (no "General" subcategory). Three sections:
--   * Master controls — enable, lock, test mode
--   * Appearance      — global scale + alpha
--   * Position        — reset position button
--
-- Every setter writes to db.profile and fires
--   KickCD_CONFIG_CHANGED { section = "general" }
-- so that IconGrid / Castbar live-update without a /reload (FR-6.4).

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
        L["When unlocked, you can drag the icon grid and castbar."],
        "general", "locked")

    -- Test mode is special: in addition to writing the db value (so the
    -- setting persists), we call KickCD:ToggleTestMode() so the UI flips
    -- immediately. ToggleTestMode is wired in modules/TestMode.lua and
    -- is safe to invoke when the module is missing (it prints a warning).
    H.CreateCheckbox(mainCategory, "KickCD_general_testMode",
        L["Test mode"],
        L["Show a fake cast on a 5-second loop for previewing layout. Auto-disables in combat."],
        "general", "testMode",
        function(value)
            -- The TestMode module already syncs db.profile.testMode in its
            -- Enable/Disable methods, so we only call ToggleTestMode when
            -- the desired state diverges from current. Otherwise a
            -- programmatic write (e.g. combat-auto-disable) that fires
            -- the callback would loop us back into a toggle.
            if KickCD.ToggleTestMode then
                local m = KickCD.GetModule and KickCD:GetModule("TestMode", true)
                local active = m and m.enabled
                if (value and not active) or (not value and active) then
                    KickCD:ToggleTestMode()
                end
            end
        end)

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
        L["Global alpha for icons + castbar."],
        "general", "alpha",
        0.0, 1.0, 0.05, "%.2f")

    -- ---------------------------------------------------------------
    -- Section: Position
    -- ---------------------------------------------------------------
    H.AddSectionHeader(mainCategory, L["Reset position"])

    -- Reset button: restores both anchors to the documented defaults
    -- (TECHNICAL_DESIGN §4 / REQUIREMENTS FR-8.1) and fires a general
    -- CONFIG_CHANGED so IconGrid + Castbar re-apply their anchors.
    -- The IconGrid module listens for "general" and re-runs ApplyLock();
    -- it also re-applies the anchor on PROFILE_CHANGED, which we don't
    -- emit here — but a general reset to defaults isn't a profile event,
    -- so we add a defensive direct anchor write here as well.
    local function resetPosition()
        if not (KickCD.db and KickCD.db.profile) then return end
        KickCD.db.profile.anchors = KickCD.db.profile.anchors or {}
        KickCD.db.profile.anchors.icons =
            { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }
        KickCD.db.profile.anchors.castbar =
            { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 }
        H.FireConfigChanged("general")
        -- A second message under the "icons"/"castbar" sections so each
        -- module's per-section listener also fires (IconGrid only re-anchors
        -- on its own section paths in some implementations). Closed-set
        -- compliant — these are existing sections, not new messages.
        H.FireConfigChanged("icons")
        H.FireConfigChanged("castbar")
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
