-- core/LSMPatch.lua — third-party widget fixup for AceGUI-3.0-SharedMediaWidgets
--
-- Upstream AceGUI-3.0-SharedMediaWidgets' LSM30_Border widget pins a
-- 42x42 displayButton border-preview tile to the widget's TOPLEFT
-- (see AGSMW:GetBaseFrameWithWindow in
-- libs/AceGUI-3.0-SharedMediaWidgets/prototypes.lua). Inside our
-- canvas-layout settings panel that tile leaves a 42px gap to the
-- right of the closed dropdown's left edge and looks misaligned next
-- to neighboring sliders / checkboxes.
--
-- After PLAYER_LOGIN — by which point every addon's libs have run
-- and the LSM30_Border registry slot is stable — wrap whatever
-- constructor AceGUI currently holds, register the wrapper at
-- currentVersion + 1 to win the version race, and per-instance hide
-- the displayButton plus re-anchor frame.label and frame.DLeft to
-- the frame's left edge so the empty 42px slot collapses. The
-- popup's per-row hover preview (upstream's ContentOnEnter swaps the
-- popup backdrop's edgeFile to the hovered border) is unaffected.
--
-- LSM30_Font / LSM30_Statusbar use AGSMW:GetBaseFrame (no
-- displayButton), so this fixup is Border-specific.
--
-- Lives in core/ (addon code), not in libs/, so future refreshes of
-- the vendored AceGUI-3.0-SharedMediaWidgets lib don't blow it away.

-- luacheck: ignore 211/NS
local addonName, NS = ...  -- standard bootstrap header (§4.1); this file is a
                           -- standalone LSM widget fixup and doesn't use NS,
                           -- so the unused-variable warning is suppressed
                           -- rather than the header being trimmed.

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local registry = AceGUI.WidgetRegistry
    local current = registry and registry["LSM30_Border"]
    if not current then return end

    local currentVer = AceGUI:GetWidgetVersion("LSM30_Border") or 1

    AceGUI:RegisterWidgetType("LSM30_Border", function()
        local widget = current()
        local f = widget and widget.frame
        if f and f.displayButton then
            f.displayButton:Hide()
            if f.label then
                f.label:ClearAllPoints()
                f.label:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
                f.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            end
            -- DLeft is the left cap of the CharacterCreate-LabelFrame
            -- dropdown bar. Upstream AGSMW:GetBaseFrameWithWindow
            -- repositions it to displayButton.BOTTOMRIGHT; restore
            -- the original GetBaseFrame anchor so the bar starts at
            -- the frame's left edge again.
            if f.DLeft then
                f.DLeft:ClearAllPoints()
                f.DLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -17, -21)
            end
        end
        return widget
    end, currentVer + 1)
end)
