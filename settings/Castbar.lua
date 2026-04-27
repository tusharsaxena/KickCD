-- settings/Castbar.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §5.2 and docs/REQUIREMENTS.md FR-6.2.3, FR-3
--
-- "Castbar" subcategory under "Ka0s KickCD". This is the SETTINGS-tab file,
-- NOT modules/Castbar.lua (the runtime castbar). Sections:
--   * Dimensions   — width, height
--   * Appearance   — texture, border, font + font size (LSM-backed)
--   * Colors       — interruptible color, not-interruptible color
--   * Decorations  — show spark, show icon
--
-- Every setter writes to db.profile.castbar and fires
--   KickCD_CONFIG_CHANGED { section = "castbar" }
-- so modules/Castbar.lua restyles live (it listens for that section and
-- runs :ApplyConfig() without recreating frames — see TECHNICAL_DESIGN §3.7).

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L

local function Build(mainCategory)
    if not (Settings and Settings.RegisterVerticalLayoutSubcategory) then
        return nil
    end

    local H = KickCD.Settings.Helpers
    local sub = Settings.RegisterVerticalLayoutSubcategory(mainCategory, L["Castbar"])

    -- ---------------------------------------------------------------
    -- Section: Dimensions
    -- ---------------------------------------------------------------
    H.AddSectionHeader(sub, L["Width"] .. " / " .. L["Height"])

    H.CreateSlider(sub, "KickCD_castbar_width",
        L["Width"],
        L["Castbar width in pixels."],
        "castbar", "castbar.width",
        100, 500, 5, "%d px")

    H.CreateSlider(sub, "KickCD_castbar_height",
        L["Height"],
        L["Castbar height in pixels."],
        "castbar", "castbar.height",
        8, 48, 1, "%d px")

    -- ---------------------------------------------------------------
    -- Section: Appearance
    -- ---------------------------------------------------------------
    H.AddSectionHeader(sub, L["Texture"])

    H.CreateDropdown(sub, "KickCD_castbar_texture",
        L["Texture"],
        L["Status-bar texture (LibSharedMedia)."],
        "castbar", "castbar.texture",
        H.LSMValues("statusbar"))

    H.CreateDropdown(sub, "KickCD_castbar_border",
        L["Border"],
        L["Border style (LibSharedMedia)."],
        "castbar", "castbar.border",
        H.LSMValues("border"))

    H.CreateDropdown(sub, "KickCD_castbar_font",
        L["Font"],
        L["Font for spell name + time-remaining text."],
        "castbar", "castbar.font",
        H.LSMValues("font"))

    H.CreateSlider(sub, "KickCD_castbar_fontSize",
        L["Font size"],
        L["Castbar text size in pixels."],
        "castbar", "castbar.fontSize",
        8, 24, 1, "%d")

    -- ---------------------------------------------------------------
    -- Section: Colors
    -- ---------------------------------------------------------------
    H.AddSectionHeader(sub, L["Interruptible color"])

    H.CreateColorPicker(sub, "KickCD_castbar_interruptibleColor",
        L["Interruptible color"],
        L["Bar color while the cast can be kicked."],
        "castbar", "castbar.interruptibleColor")

    -- Kept for forward-compat per EXECUTION_PLAN §6 even though v0.1 only
    -- shows interruptible casts (FR-1 / FR-3.2). Future toggles to surface
    -- shielded casts will read this value already.
    H.CreateColorPicker(sub, "KickCD_castbar_notInterruptibleColor",
        L["Not-interruptible color"],
        L["Bar color when the cast is shielded (reserved for future use)."],
        "castbar", "castbar.notInterruptibleColor")

    -- ---------------------------------------------------------------
    -- Section: Decorations
    -- ---------------------------------------------------------------
    H.AddSectionHeader(sub, L["Show spark"])

    H.CreateCheckbox(sub, "KickCD_castbar_showSpark",
        L["Show spark"],
        L["Render a moving spark at the cast's current progress (FR-3.5)."],
        "castbar", "castbar.showSpark")

    H.CreateCheckbox(sub, "KickCD_castbar_showIcon",
        L["Show icon"],
        L["Render the cast's spell icon on the castbar."],
        "castbar", "castbar.showIcon")

    return sub
end

if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("castbar", Build)
end
