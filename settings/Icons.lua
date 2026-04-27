-- settings/Icons.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §5.2 and docs/REQUIREMENTS.md FR-6.2.2
--
-- "Icons" subcategory under "Ka0s KickCD". Sections:
--   * Sizing          — primary size, secondary % of primary, gap
--   * Layout          — direction, primary anchor
--   * Visual states   — ready alpha, cooldown alpha, cooldown tint
--   * Annotations     — cooldown text on/off + font + size, charges on/off
--
-- Every setter writes to db.profile.icons and fires
--   KickCD_CONFIG_CHANGED { section = "icons" }
-- so IconGrid live-updates (modules/IconGrid.lua handles section=="icons" by
-- calling :Layout() + :ApplyLock(); see EXECUTION_PLAN §5).

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L

local function Build(mainCategory)
    if not (Settings and Settings.RegisterVerticalLayoutSubcategory) then
        return nil
    end

    local H = KickCD.Settings.Helpers
    local sub = Settings.RegisterVerticalLayoutSubcategory(mainCategory, L["Icons"])

    -- ---------------------------------------------------------------
    -- Section: Sizing
    -- ---------------------------------------------------------------
    H.AddSectionHeader(sub, L["Primary size"])

    H.CreateSlider(sub, "KickCD_icons_primarySize",
        L["Primary size"],
        L["Pixel size of the primary interrupt icon."],
        "icons", "icons.primarySize",
        24, 96, 2, "%d px")

    H.CreateSlider(sub, "KickCD_icons_secondarySize",
        L["Secondary size"],
        L["Secondary icon size as a fraction of the primary."],
        "icons", "icons.secondarySize",
        0.4, 1.0, 0.05, "%.2f")

    H.CreateSlider(sub, "KickCD_icons_gap",
        L["Gap"],
        L["Pixel gap between adjacent icons."],
        "icons", "icons.gap",
        0, 24, 1, "%d px")

    -- ---------------------------------------------------------------
    -- Section: Layout
    -- ---------------------------------------------------------------
    H.AddSectionHeader(sub, L["Layout"])

    H.CreateDropdown(sub, "KickCD_icons_layout",
        L["Layout"],
        L["Arrange icons horizontally or vertically."],
        "icons", "icons.layout",
        {
            { value = "horizontal", label = L["Horizontal"] },
            { value = "vertical",   label = L["Vertical"]   },
        })

    H.CreateDropdown(sub, "KickCD_icons_primaryAnchor",
        L["Primary anchor"],
        L["Where the primary icon sits relative to the secondaries."],
        "icons", "icons.primaryAnchor",
        {
            { value = "left",   label = L["Left"]   },
            { value = "right",  label = L["Right"]  },
            { value = "top",    label = L["Top"]    },
            { value = "bottom", label = L["Bottom"] },
        })

    -- ---------------------------------------------------------------
    -- Section: Visual states
    -- ---------------------------------------------------------------
    H.AddSectionHeader(sub, L["Ready alpha"])

    H.CreateSlider(sub, "KickCD_icons_readyAlpha",
        L["Ready alpha"],
        L["Icon alpha when the spell is off cooldown."],
        "icons", "icons.readyAlpha",
        0.0, 1.0, 0.05, "%.2f")

    H.CreateSlider(sub, "KickCD_icons_cooldownAlpha",
        L["Cooldown alpha"],
        L["Icon alpha while the spell is on cooldown."],
        "icons", "icons.cooldownAlpha",
        0.0, 1.0, 0.05, "%.2f")

    H.CreateColorPicker(sub, "KickCD_icons_cooldownTint",
        L["Cooldown tint"],
        L["RGB tint applied to icons during cooldown."],
        "icons", "icons.cooldownTint")

    -- ---------------------------------------------------------------
    -- Section: Annotations
    -- ---------------------------------------------------------------
    H.AddSectionHeader(sub, L["Show cooldown text"])

    H.CreateCheckbox(sub, "KickCD_icons_showCooldownText",
        L["Show cooldown text"],
        L["Render numeric seconds remaining on each icon."],
        "icons", "icons.showCooldownText")

    -- LibSharedMedia font dropdown — values are LSM-registered font keys.
    -- The IconGrid module looks the key up via LSM:Fetch("font", key) when
    -- it applies the config; we just store the string.
    H.CreateDropdown(sub, "KickCD_icons_cooldownTextFont",
        L["Font"],
        L["Font for the cooldown text overlay."],
        "icons", "icons.cooldownTextFont",
        H.LSMValues("font"))

    H.CreateSlider(sub, "KickCD_icons_cooldownTextSize",
        L["Font size"],
        L["Cooldown text size in pixels."],
        "icons", "icons.cooldownTextSize",
        8, 24, 1, "%d")

    H.CreateCheckbox(sub, "KickCD_icons_showCharges",
        L["Show charges"],
        L["Render a charges badge for spells with charges."],
        "icons", "icons.showCharges")

    return sub
end

if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("icons", Build)
end
