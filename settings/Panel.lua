-- settings/Panel.lua — KickCD v0.1
--
-- Settings UI framework. Every tab — General, Icons, Spells, Profiles —
-- is registered as a canvas-layout subcategory and shares one header
-- design: title (left) + Defaults button (right) + divider, all built
-- by Helpers.CreatePanel. Below the header each tab lays out its own
-- body.
--
-- General and Icons are driven entirely from a declarative schema
-- (KickCD.Settings.Schema). The same schema feeds the
-- /kcd list|get|set slash commands (see core/KickCD.lua), so adding a
-- new option is one row that auto-wires both UI and CLI.

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L

KickCD.Settings = KickCD.Settings or {}
KickCD.Settings.main      = nil
KickCD.Settings.sub       = {}
KickCD.Settings.builders  = {}
KickCD.Settings.order     = { "general", "icons", "spells", "profiles" }
KickCD.Settings.Schema    = KickCD.Settings.Schema or {}
KickCD.Settings._panels   = KickCD.Settings._panels or {}

local Helpers = {}
KickCD.Settings.Helpers = Helpers

-- ---------------------------------------------------------------------
-- db.profile path helpers
-- ---------------------------------------------------------------------

local function Resolve(path)
    if not (KickCD.db and KickCD.db.profile) then return nil, nil end
    local segments = {}
    for part in string.gmatch(path, "[^.]+") do
        segments[#segments + 1] = part
    end
    if #segments == 0 then return nil, nil end
    local parent = KickCD.db.profile
    for i = 1, #segments - 1 do
        parent = parent[segments[i]]
        if type(parent) ~= "table" then return nil, nil end
    end
    return parent, segments[#segments]
end
Helpers.Resolve = Resolve

function Helpers.Get(path)
    local parent, key = Resolve(path)
    if not parent then return nil end
    return parent[key]
end

function Helpers.FireConfigChanged(section)
    if KickCD and KickCD.SendMessage then
        KickCD:SendMessage("KickCD_CONFIG_CHANGED", { section = section })
    end
end

function Helpers.Set(path, section, value)
    local parent, key = Resolve(path)
    if not parent then return end
    parent[key] = value
    Helpers.FireConfigChanged(section)
end

-- ---------------------------------------------------------------------
-- Schema query helpers
-- ---------------------------------------------------------------------

function Helpers.SchemaForPanel(panelKey)
    local out = {}
    for _, def in ipairs(KickCD.Settings.Schema) do
        if def.panel == panelKey then out[#out + 1] = def end
    end
    return out
end

function Helpers.FindSchema(path)
    for _, def in ipairs(KickCD.Settings.Schema) do
        if def.path == path then return def end
    end
end

--- Build the option list for a LibSharedMedia media type.
function Helpers.LSMValues(mediaType)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM or not LSM.List then
        return { { value = "Default", label = "Default" } }
    end
    local list = LSM:List(mediaType) or {}
    local out = {}
    for i, key in ipairs(list) do
        out[i] = { value = key, label = key }
    end
    if #out == 0 then
        out[1] = { value = "Default", label = "Default" }
    end
    return out
end

-- ---------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------

local PADDING_X       = 16
local HEADER_HEIGHT   = 42
local HEADER_BTN_W    = 110
local HEADER_BTN_H    = 26
local SECTION_GAP     = 14
local SECTION_HEIGHT  = 22
local ROW_GAP         = 8
local CHECKBOX_H      = 24
local SLIDER_H        = 36
local DROPDOWN_H      = 28
local COLOR_H         = 24
local BUTTON_H        = 26
local CONTROL_W       = 200

-- ---------------------------------------------------------------------
-- Tooltip helper
-- ---------------------------------------------------------------------

local function attachTooltip(widget, label, tooltip)
    if not (widget and widget.HookScript) then return end
    widget:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if label and label ~= "" then
            GameTooltip:SetText(label, 1, 1, 1)
        end
        if tooltip and tooltip ~= "" then
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
Helpers.AttachTooltip = attachTooltip

-- ---------------------------------------------------------------------
-- Header (title + Defaults button + divider) — see KCD001.png
-- ---------------------------------------------------------------------

local function buildHeader(parent, title, opts)
    opts = opts or {}

    local titleFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFS:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, -8)
    titleFS:SetText(title)

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOPLEFT",  parent, "TOPLEFT",   PADDING_X, -HEADER_HEIGHT)
    divider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING_X, -HEADER_HEIGHT)

    local defaultsBtn
    if opts.defaultsButton then
        defaultsBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        defaultsBtn:SetSize(HEADER_BTN_W, HEADER_BTN_H)
        defaultsBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING_X, -8)
        defaultsBtn:SetText(L["Defaults"])
        attachTooltip(defaultsBtn, L["Defaults"], opts.defaultsTooltip)
    end

    return titleFS, divider, defaultsBtn
end

-- ---------------------------------------------------------------------
-- CreatePanel — Frame compatible with RegisterCanvasLayoutSubcategory
-- with the unified header stamped on top. Returns a `ctx` table the
-- caller threads through Section/RenderField/RenderSchema etc.
-- ---------------------------------------------------------------------

function Helpers.CreatePanel(name, title, opts)
    opts = opts or {}

    local panel = CreateFrame("Frame", name)
    panel.name = title
    panel:Hide()

    local titleFS, divider, defaultsBtn = buildHeader(panel, title, opts)
    panel.title       = titleFS
    panel.divider     = divider
    panel.defaultsBtn = defaultsBtn

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -(HEADER_HEIGHT + 8))
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.body = body

    local ctx = {
        panel      = panel,
        body       = body,
        cursor     = { y = -8 },
        refreshers = {},
        lastGroup  = nil,
        panelKey   = opts.panelKey,
    }
    KickCD.Settings._panels[#KickCD.Settings._panels + 1] = ctx
    return ctx
end

-- ---------------------------------------------------------------------
-- Section header (sub-section grouping inside a panel body)
-- ---------------------------------------------------------------------

function Helpers.Section(ctx, label)
    ctx.cursor.y = ctx.cursor.y - SECTION_GAP
    local header = CreateFrame("Frame", nil, ctx.body)
    header:SetHeight(SECTION_HEIGHT)
    header:SetPoint("TOPLEFT",  ctx.body, "TOPLEFT",   PADDING_X, ctx.cursor.y)
    header:SetPoint("TOPRIGHT", ctx.body, "TOPRIGHT", -PADDING_X, ctx.cursor.y)

    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", header, "LEFT", 0, 4)
    fs:SetText(label)

    local div = header:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    div:SetHeight(1)
    div:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT",  0, 0)
    div:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)

    ctx.cursor.y = ctx.cursor.y - SECTION_HEIGHT - 4
    return header
end

-- ---------------------------------------------------------------------
-- Widget creators — bound directly to db.profile via Helpers.Get/Set.
-- Each creator advances ctx.cursor.y and registers a refresher closure
-- so the widget can re-sync its display after a Defaults reset or a
-- /kcd set issued from chat.
-- ---------------------------------------------------------------------

local function rowFrame(ctx, height)
    local row = CreateFrame("Frame", nil, ctx.body)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT",  ctx.body, "TOPLEFT",   PADDING_X, ctx.cursor.y)
    row:SetPoint("TOPRIGHT", ctx.body, "TOPRIGHT", -PADDING_X, ctx.cursor.y)
    ctx.cursor.y = ctx.cursor.y - height - ROW_GAP
    return row
end

local function fireOnChange(def, value)
    if def.onChange then
        local ok, err = pcall(def.onChange, value)
        if not ok and KickCD.Util then
            KickCD.Util.print("onChange for " .. tostring(def.path) .. " failed: " .. tostring(err))
        end
    end
end

local function makeCheckbox(ctx, def)
    local row = rowFrame(ctx, CHECKBOX_H)
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(CHECKBOX_H, CHECKBOX_H)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)
    cb.text:SetText(def.label or def.path)
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 1)

    local function refresh()
        cb:SetChecked(Helpers.Get(def.path) and true or false)
    end
    refresh()

    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        Helpers.Set(def.path, def.section, v)
        fireOnChange(def, v)
    end)

    attachTooltip(cb, def.label, def.tooltip)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cb
end

local function snapToStep(value, min, step)
    if not (step and step > 0) then return value end
    return math.floor((value - min) / step + 0.5) * step + min
end

local function makeSlider(ctx, def)
    local row = rowFrame(ctx, SLIDER_H)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(def.label or def.path)

    local valueFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueFS:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
    slider:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 4)
    slider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 4)
    slider:SetMinMaxValues(def.min or 0, def.max or 1)
    slider:SetValueStep(def.step or 1)
    slider:SetObeyStepOnDrag(true)
    if slider.Low  then slider.Low:SetText("")  end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end

    local function format(v)
        if def.fmt then return def.fmt:format(v) end
        return tostring(v)
    end

    local function refresh()
        local v = Helpers.Get(def.path)
        if type(v) ~= "number" then v = def.default or def.min or 0 end
        slider:SetValue(v)
        valueFS:SetText(format(v))
    end
    refresh()

    slider:SetScript("OnValueChanged", function(self, value, userInput)
        local snapped = snapToStep(value, def.min or 0, def.step or 0)
        valueFS:SetText(format(snapped))
        if userInput then
            Helpers.Set(def.path, def.section, snapped)
            fireOnChange(def, snapped)
        end
    end)

    attachTooltip(label,  def.label, def.tooltip)
    attachTooltip(slider, def.label, def.tooltip)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return slider
end

local function makeDropdown(ctx, def)
    local row = rowFrame(ctx, DROPDOWN_H)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetText(def.label or def.path)

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(CONTROL_W, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    local function valuesList()
        if type(def.values) == "function" then return def.values() or {} end
        return def.values or {}
    end

    local function labelFor(value)
        for _, item in ipairs(valuesList()) do
            if item.value == value then return item.label end
        end
        return tostring(value)
    end

    local function refresh()
        btn:SetText(labelFor(Helpers.Get(def.path)))
    end
    refresh()

    btn:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, item in ipairs(valuesList()) do
                    local val = item.value
                    root:CreateRadio(item.label,
                        function() return Helpers.Get(def.path) == val end,
                        function()
                            Helpers.Set(def.path, def.section, val)
                            fireOnChange(def, val)
                            refresh()
                        end)
                end
            end)
        end
    end)

    attachTooltip(label, def.label, def.tooltip)
    attachTooltip(btn,   def.label, def.tooltip)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return btn
end

local function makeColorPicker(ctx, def)
    local row = rowFrame(ctx, COLOR_H)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetText(def.label or def.path)

    local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
    swatch:SetSize(60, COLOR_H - 4)
    swatch:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    if swatch.SetBackdrop then
        swatch:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        swatch:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    end
    local bg = swatch:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",     swatch, "TOPLEFT",     1, -1)
    bg:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)

    local function readColor()
        local c = Helpers.Get(def.path)
        if type(c) ~= "table" then c = { 1, 1, 1, 1 } end
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end

    local function applyColor(r, g, b, a)
        Helpers.Set(def.path, def.section, { r, g, b, a })
        bg:SetColorTexture(r, g, b, a)
        fireOnChange(def, { r, g, b, a })
    end

    local function refresh()
        local r, g, b, a = readColor()
        bg:SetColorTexture(r, g, b, a)
    end
    refresh()

    swatch:SetScript("OnClick", function()
        local r, g, b, a = readColor()
        local info = {
            swatchFunc = function()
                local nr, ng, nb
                if ColorPickerFrame.GetColorRGB then
                    nr, ng, nb = ColorPickerFrame:GetColorRGB()
                else
                    nr, ng, nb = ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b
                end
                local na = 1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
                applyColor(nr, ng, nb, na)
            end,
            opacityFunc = function()
                local na = 1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
                local cr, cg, cb = readColor()
                applyColor(cr, cg, cb, na)
            end,
            cancelFunc = function(prev)
                if not prev then return end
                local pr = prev.r or prev[1] or 1
                local pg = prev.g or prev[2] or 1
                local pb = prev.b or prev[3] or 1
                local pa = 1 - (prev.opacity or 0)
                applyColor(pr, pg, pb, pa)
            end,
            hasOpacity = true,
            opacity    = 1 - (a or 1),
            r = r, g = g, b = b,
        }
        if OpenColorPicker then OpenColorPicker(info) end
    end)

    attachTooltip(label,  def.label, def.tooltip)
    attachTooltip(swatch, def.label, def.tooltip)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return swatch
end

-- Generic field renderer — dispatches by def.type.
function Helpers.RenderField(ctx, def)
    if def.type == "bool"   then return makeCheckbox(ctx, def)    end
    if def.type == "number" then return makeSlider(ctx, def)      end
    if def.type == "string" then return makeDropdown(ctx, def)    end
    if def.type == "color"  then return makeColorPicker(ctx, def) end
end

-- Inline action button (not a setting — used for "Reset position" etc.)
function Helpers.Button(ctx, label, buttonText, tooltip, onClick)
    local row = rowFrame(ctx, BUTTON_H)
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
    lbl:SetText(label)

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(120, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    btn:SetText(buttonText)
    btn:SetScript("OnClick", function() if onClick then onClick() end end)
    attachTooltip(btn, label, tooltip)
    return btn
end

-- ---------------------------------------------------------------------
-- Schema-driven render
-- ---------------------------------------------------------------------

function Helpers.RenderSchema(ctx, panelKey)
    for _, def in ipairs(Helpers.SchemaForPanel(panelKey)) do
        if def.group and def.group ~= ctx.lastGroup then
            Helpers.Section(ctx, def.group)
            ctx.lastGroup = def.group
        end
        Helpers.RenderField(ctx, def)
    end
end

-- Refresh every widget on every panel ctx — called after a slash-cmd
-- /kcd set so an open panel reflects the new value immediately.
function Helpers.RefreshAllPanels()
    for _, ctx in ipairs(KickCD.Settings._panels) do
        for _, fn in ipairs(ctx.refreshers) do pcall(fn) end
    end
end

-- Reset every Schema entry for `panelKey` back to its default; fire
-- CONFIG_CHANGED for each unique section. Used by the per-panel
-- Defaults button.
function Helpers.RestoreDefaults(panelKey, ctx)
    local sections = {}
    for _, def in ipairs(Helpers.SchemaForPanel(panelKey)) do
        if def.default ~= nil then
            local parent, key = Resolve(def.path)
            if parent then
                local v = def.default
                if type(v) == "table" then
                    local copy = {}
                    for i, vv in ipairs(v) do copy[i] = vv end
                    v = copy
                end
                parent[key] = v
                fireOnChange(def, v)
                sections[def.section or panelKey] = true
            end
        end
    end
    for s in pairs(sections) do Helpers.FireConfigChanged(s) end
    if ctx and ctx.refreshers then
        for _, fn in ipairs(ctx.refreshers) do pcall(fn) end
    end
end

-- ---------------------------------------------------------------------
-- Tab + main-category registration
-- ---------------------------------------------------------------------

function KickCD.Settings.RegisterTab(key, builder)
    if type(key) ~= "string" or type(builder) ~= "function" then return end
    KickCD.Settings.builders[key] = builder
    if KickCD.Settings.main and not KickCD.Settings.sub[key] then
        local ok, sub = pcall(builder, KickCD.Settings.main)
        if ok and sub then
            KickCD.Settings.sub[key] = sub
        end
    end
end

local function RegisterPanel()
    if KickCD.Settings.main then return end
    if not (Settings and Settings.RegisterVerticalLayoutCategory
            and Settings.RegisterAddOnCategory) then
        return
    end

    local main = Settings.RegisterVerticalLayoutCategory(L["Ka0s KickCD"])
    Settings.RegisterAddOnCategory(main)
    KickCD.Settings.main = main
    KickCD.SettingsCategoryID = main:GetID()

    for _, key in ipairs(KickCD.Settings.order) do
        local fn = KickCD.Settings.builders[key]
        if type(fn) == "function" and not KickCD.Settings.sub[key] then
            local ok, sub = pcall(fn, main)
            if ok and sub then
                KickCD.Settings.sub[key] = sub
            elseif not ok and KickCD.Util then
                KickCD.Util.print("settings tab '" .. key .. "' failed: " .. tostring(sub))
            end
        end
    end
end
KickCD.Settings.Register = RegisterPanel

-- bootstrap: defer until Blizzard_Settings is ready
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "Blizzard_Settings" then return end
    RegisterPanel()
    if KickCD.Settings.main then
        self:UnregisterAllEvents()
    end
end)
