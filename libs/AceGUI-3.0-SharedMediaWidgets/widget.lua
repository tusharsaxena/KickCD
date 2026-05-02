-- AceGUI-3.0-SharedMediaWidgets (minimal, in-tree)
--
-- Registers AceGUI widget types LSM30_Statusbar, LSM30_Border and LSM30_Font
-- so AceConfigDialog renders LibSharedMedia dropdowns with an inline preview
-- swatch beside each entry. Names match the upstream AceGUI-3.0-Shared
-- MediaWidgets project so dropping in the real lib later is a clean swap.
--
-- Self-contained: builds the dropdown out of Blizzard frames, doesn't
-- subclass AceGUI's Dropdown widget (avoids polluting the shared widget
-- pool with overridden SetList behavior).

local MAJOR, MINOR = "AceGUISharedMediaWidgets-1.0", 1
if not LibStub then return end
local AceGUI = LibStub("AceGUI-3.0", true); if not AceGUI then return end
local LSM    = LibStub("LibSharedMedia-3.0", true); if not LSM then return end

local CreateFrame, UIParent = CreateFrame, UIParent
local min, max = math.min, math.max

-- One shared click-catcher closes any open dropdown when the user clicks
-- elsewhere. Lazy-created on first dropdown open.
local clickCatcher
local activeClose

local function getClickCatcher()
    if clickCatcher then return clickCatcher end
    clickCatcher = CreateFrame("Button", nil, UIParent)
    clickCatcher:SetAllPoints(UIParent)
    clickCatcher:SetFrameStrata("FULLSCREEN")
    clickCatcher:SetFrameLevel(0)
    clickCatcher:Hide()
    clickCatcher:SetScript("OnClick", function()
        if activeClose then activeClose() end
    end)
    return clickCatcher
end

-- ---------------------------------------------------------------------
-- Swatch renderers — one per media type. Each receives the swatch frame
-- (which contains a .tex texture and a .text font string) and the
-- LSM media name to preview.
-- ---------------------------------------------------------------------

local function renderStatusbarSwatch(swatch, name)
    swatch.tex:Show()
    swatch.text:Hide()
    swatch.tex:SetTexture(LSM:Fetch("statusbar", name) or "")
    swatch.tex:SetVertexColor(1, 1, 1, 1)
    swatch.tex:SetTexCoord(0, 1, 0, 1)
end

local function renderBorderSwatch(swatch, _name)
    -- No swatch preview for borders — every reasonable LSM border is a
    -- tile sheet and the corner art either reads as a hollow box (when
    -- shown at scale) or as a meaningless smudge (when stretched to the
    -- swatch's aspect ratio), neither of which helps a user pick. The
    -- dropdown's text label identifies the choice; the live in-game
    -- border on the icons / cast bar is the real preview.
    swatch.tex:Hide()
    swatch.text:Hide()
end

local function renderFontSwatch(swatch, name)
    swatch.tex:Hide()
    swatch.text:Show()
    local font = LSM:Fetch("font", name)
    if font then
        swatch.text:SetFont(font, 12, "OUTLINE")
    end
    swatch.text:SetText("Aa")
end

-- ---------------------------------------------------------------------
-- Item button (one row in the popup list)
-- ---------------------------------------------------------------------

local ITEM_HEIGHT = 22
local SWATCH_W    = 40
local SWATCH_H    = 14

local function createItemButton(parent, renderSwatch)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ITEM_HEIGHT)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.3, 0.3, 0.7, 0.4)

    local check = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check:SetPoint("LEFT", 4, 0)
    check:SetWidth(10)
    btn.check = check

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 16, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -(SWATCH_W + 8), 0)
    label:SetJustifyH("LEFT")
    btn.label = label

    local swatch = CreateFrame("Frame", nil, btn)
    swatch:SetSize(SWATCH_W, SWATCH_H)
    swatch:SetPoint("RIGHT", -4, 0)

    local swatchTex = swatch:CreateTexture(nil, "OVERLAY")
    swatchTex:SetAllPoints()
    swatch.tex = swatchTex

    local swatchText = swatch:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    swatchText:SetAllPoints()
    swatchText:SetJustifyH("CENTER")
    swatch.text = swatchText

    btn.swatch = swatch
    btn.renderSwatch = renderSwatch
    return btn
end

-- ---------------------------------------------------------------------
-- Constructor factory — returns an AceGUI widget Constructor for the
-- given media type and swatch renderer.
-- ---------------------------------------------------------------------

local function buildConstructor(widgetType, mediaType, renderSwatch)
    return function()
        local self = {}
        self.type = widgetType

        -- Container frame the widget anchors against. AceGUI expects
        -- self.frame at a minimum, plus self.alignoffset for label-aware
        -- positioning. The frame is a sized Blizzard frame; AceGUI sizes
        -- it via SetWidth/SetHeight.
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:Hide()
        frame:SetHeight(44)
        self.frame = frame
        frame.obj = self

        -- Label above the dropdown button
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, 0)
        label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetHeight(16)
        self.label = label

        -- Closed-state button
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -16)
        btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -16)
        btn:SetHeight(24)
        btn:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        self.button = btn

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btnText:SetPoint("LEFT", 8, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", -(SWATCH_W + 24), 0)
        btnText:SetJustifyH("LEFT")
        self.buttonText = btnText

        -- Closed-state swatch (mirrors the item-row swatch design)
        local btnSwatch = CreateFrame("Frame", nil, btn)
        btnSwatch:SetSize(SWATCH_W, SWATCH_H)
        btnSwatch:SetPoint("RIGHT", -22, 0)
        local btnSwatchTex = btnSwatch:CreateTexture(nil, "OVERLAY")
        btnSwatchTex:SetAllPoints()
        btnSwatch.tex = btnSwatchTex
        local btnSwatchText = btnSwatch:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btnSwatchText:SetAllPoints()
        btnSwatchText:SetJustifyH("CENTER")
        btnSwatch.text = btnSwatchText
        self.buttonSwatch = btnSwatch

        local arrow = btn:CreateTexture(nil, "ARTWORK")
        arrow:SetPoint("RIGHT", -5, 0)
        arrow:SetSize(16, 16)
        arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

        -- Popup list (top-strata, parented to UIParent so it can extend
        -- past the settings panel's clip rect)
        local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        list:SetFrameStrata("FULLSCREEN")
        list:SetFrameLevel(2)
        list:SetClampedToScreen(true)
        list:EnableMouse(true)
        list:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        list:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
        list:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        list:Hide()

        local scroll = CreateFrame("ScrollFrame", nil, list)
        scroll:SetPoint("TOPLEFT", 6, -6)
        local content = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(content)

        local SCROLLBAR_W = 14
        local scrollBar = CreateFrame("Slider", nil, list, "BackdropTemplate")
        scrollBar:SetPoint("TOPRIGHT", -6, -6)
        scrollBar:SetPoint("BOTTOMRIGHT", -6, 6)
        scrollBar:SetWidth(SCROLLBAR_W)
        scrollBar:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        scrollBar:SetBackdropColor(0, 0, 0, 0.4)
        scrollBar:SetValueStep(ITEM_HEIGHT)
        scrollBar:SetObeyStepOnDrag(true)
        local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(SCROLLBAR_W - 4, 24)
        thumb:SetColorTexture(0.5, 0.5, 0.5, 0.7)
        scrollBar:SetThumbTexture(thumb)
        scrollBar:SetScript("OnValueChanged", function(_, value)
            scroll:SetVerticalScroll(value)
        end)

        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function(_, delta)
            if not scrollBar:IsShown() then return end
            local cur = scrollBar:GetValue()
            local _, mx = scrollBar:GetMinMaxValues()
            local step = ITEM_HEIGHT * 2
            scrollBar:SetValue(delta > 0 and max(0, cur - step) or min(mx, cur + step))
        end)

        local itemPool = {}

        -- Internal state. Set via SetList() and SetValue().
        self.list  = nil   -- map: key -> displayName
        self.order = nil   -- ordered keys
        self.value = nil

        local function closeList()
            list:Hide()
            getClickCatcher():Hide()
            activeClose = nil
        end

        local function openList()
            if activeClose then activeClose() end

            local order = self.order or {}
            local n = #order
            if n == 0 then return end

            local MAX_VISIBLE = 10
            local visible     = min(n, MAX_VISIBLE)
            local needsScroll = n > MAX_VISIBLE
            local listW       = max(220, btn:GetWidth())
            local listH       = visible * ITEM_HEIGHT + 12

            list:SetSize(listW, listH)
            list:ClearAllPoints()
            list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)

            local rightInset = needsScroll and -(SCROLLBAR_W + 8) or -6
            scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", rightInset, 6)
            local contentW = needsScroll and (listW - SCROLLBAR_W - 14) or (listW - 12)
            content:SetSize(contentW, n * ITEM_HEIGHT)

            for i, key in ipairs(order) do
                local item = itemPool[i]
                if not item then
                    item = createItemButton(content, renderSwatch)
                    itemPool[i] = item
                end
                item:SetParent(content)
                item:ClearAllPoints()
                item:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_HEIGHT)
                item:SetPoint("RIGHT", content, "RIGHT", 0, 0)

                local display = self.list and self.list[key] or key
                item.label:SetText(display)
                item.check:SetText(key == self.value and "|cFF00FF00>|r" or "")
                renderSwatch(item.swatch, key)

                local itemKey = key
                item:SetScript("OnClick", function()
                    closeList()
                    self:SetValue(itemKey)
                    self:Fire("OnValueChanged", itemKey)
                end)
                item:Show()
            end
            for i = n + 1, #itemPool do itemPool[i]:Hide() end

            if needsScroll then
                scrollBar:Show()
                local mx = (n - visible) * ITEM_HEIGHT
                scrollBar:SetMinMaxValues(0, mx)
                local target = 0
                for i, key in ipairs(order) do
                    if key == self.value then
                        target = max(0, min(mx, (i - 1) * ITEM_HEIGHT - math.floor(visible / 2) * ITEM_HEIGHT))
                        break
                    end
                end
                scrollBar:SetValue(target)
                scroll:SetVerticalScroll(target)
            else
                scrollBar:Hide()
                scroll:SetVerticalScroll(0)
            end

            activeClose = closeList
            getClickCatcher():Show()
            list:Show()
        end

        btn:SetScript("OnClick", function()
            if list:IsShown() then closeList() else openList() end
        end)

        -- Hide the list when the parent panel hides (e.g. the user
        -- closes Blizzard Settings while the dropdown is open).
        frame:SetScript("OnHide", function()
            if list:IsShown() then closeList() end
        end)

        -- Tooltip hover hooks — AceConfigDialog wires SetCallback("OnEnter")
        -- and ("OnLeave") to its tooltip helper, which expects the widget
        -- to fire those events when the dropdown button is hovered.
        btn:SetScript("OnEnter", function() self:Fire("OnEnter") end)
        btn:SetScript("OnLeave", function() self:Fire("OnLeave") end)

        -- ----- AceGUI widget interface -----

        function self:OnAcquire()
            self.frame:SetWidth(200)
            self.frame:SetHeight(44)
            self:SetLabel()
            self:SetDisabled(false)
            self.value = nil
        end

        function self:OnRelease()
            if list:IsShown() then closeList() end
            self.list  = nil
            self.order = nil
            self.value = nil
        end

        function self:SetLabel(text)
            self.label:SetText(text or "")
        end

        function self:SetDisabled(disabled)
            self.disabled = disabled
            if disabled then
                btn:Disable()
                btnText:SetTextColor(0.5, 0.5, 0.5)
            else
                btn:Enable()
                btnText:SetTextColor(1, 1, 1)
            end
        end

        function self:SetText(text)
            btnText:SetText(text or "")
        end

        function self:SetList(list_, order)
            self.list  = list_
            -- AceConfigDialog passes the order as a list of keys; if
            -- absent, fall back to an iteration of list_'s pairs (matches
            -- LSM registration order in practice).
            if order then
                self.order = order
            else
                local keys = {}
                if list_ then
                    for k in pairs(list_) do keys[#keys + 1] = k end
                end
                self.order = keys
            end
            -- Refresh the closed-state preview if a value is already
            -- selected (re-feeding SetList shouldn't drop the swatch).
            if self.value then self:SetValue(self.value) end
        end

        function self:SetValue(value)
            self.value = value
            local display = (self.list and self.list[value]) or value or ""
            self:SetText(display)
            if value then
                renderSwatch(self.buttonSwatch, value)
            end
        end

        -- AceConfigDialog calls these on dropdowns. For LSM-style
        -- single-select we no-op the multiselect surface.
        function self:SetMultiselect() end
        function self:SetItemValue(_, _) end
        function self:SetItemDisabled(_, _) end

        -- AceGUI's WidgetBase reads alignoffset to align this widget
        -- with neighbours sharing a row. Set to label height (16) +
        -- a small gap so dropdowns line up with checkboxes.
        self.alignoffset = 30

        -- Hand the widget to AceGUI for the standard treatment:
        -- installs widget.events (for SetCallback/Fire), widget.userdata,
        -- the WidgetBase metatable (SetParent/SetWidth/SetPoint/...) and
        -- the OnSizeChanged hook AceGUI uses for layout.
        AceGUI:RegisterAsWidget(self)
        return self
    end
end

-- ---------------------------------------------------------------------
-- Register
-- ---------------------------------------------------------------------

AceGUI:RegisterWidgetType("LSM30_Statusbar",
    buildConstructor("LSM30_Statusbar", "statusbar", renderStatusbarSwatch), MINOR)
AceGUI:RegisterWidgetType("LSM30_Border",
    buildConstructor("LSM30_Border", "border", renderBorderSwatch), MINOR)
AceGUI:RegisterWidgetType("LSM30_Font",
    buildConstructor("LSM30_Font", "font", renderFontSwatch), MINOR)
