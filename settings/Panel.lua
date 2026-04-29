-- settings/Panel.lua — KickCD v0.2
--
-- Settings UI framework. Every tab — General, Icons, Spells, Profiles —
-- is registered as a canvas-layout subcategory and shares one header
-- design: title (left) + Defaults button (right) + divider, all built
-- by Helpers.CreatePanel. Below the header each tab lays out its own
-- body.
--
-- General and Icons are driven entirely from a declarative schema
-- (KickCD.Settings.Schema). Schema rows render as AceGUI widgets
-- (CheckBox / Slider / Dropdown / ColorPicker / Heading) inside an
-- AceGUI ScrollFrame parented to ctx.body, so the visual style matches
-- the AceGUI-driven Spells / Profiles tabs and other AceGUI-using
-- addons (e.g. Consumable Master).
--
-- The same schema feeds /kcd list|get|set (see core/KickCD.lua), so
-- adding a new option = one row that auto-wires UI and CLI.

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L
local AceGUI = LibStub("AceGUI-3.0")

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

local PADDING_X     = 16
local HEADER_HEIGHT = 42
local DEFAULTS_W    = 110

-- ---------------------------------------------------------------------
-- Tooltip helper — works on AceGUI widgets (via SetCallback) and plain
-- Blizzard frames (via HookScript). Anchors on widget.frame when the
-- target is an AceGUI widget.
-- ---------------------------------------------------------------------

local function attachTooltip(widget, label, tooltip)
    if not widget then return end
    local anchor = widget.frame or widget
    if not anchor then return end

    local function show()
        if not GameTooltip then return end
        GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
        if label and label ~= "" then
            GameTooltip:SetText(label, 1, 1, 1)
        end
        if tooltip and tooltip ~= "" then
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end
    local function hide() if GameTooltip then GameTooltip:Hide() end end

    if widget.SetCallback then
        widget:SetCallback("OnEnter", show)
        widget:SetCallback("OnLeave", hide)
    elseif widget.HookScript then
        widget:HookScript("OnEnter", show)
        widget:HookScript("OnLeave", hide)
    end
end
Helpers.AttachTooltip = attachTooltip

-- ---------------------------------------------------------------------
-- Header (title + Defaults button + divider)
-- ---------------------------------------------------------------------

local function buildHeader(panel, title, opts)
    local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING_X, -8)
    titleFS:SetText(title)

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOPLEFT",  panel, "TOPLEFT",   PADDING_X, -HEADER_HEIGHT)
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING_X, -HEADER_HEIGHT)

    local defaultsBtn
    if opts.defaultsButton then
        defaultsBtn = AceGUI:Create("Button")
        defaultsBtn:SetText(L["Defaults"])
        defaultsBtn:SetWidth(DEFAULTS_W)
        defaultsBtn.frame:SetParent(panel)
        defaultsBtn.frame:ClearAllPoints()
        defaultsBtn.frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT",
                                   -PADDING_X, -8)
        defaultsBtn.frame:Show()
        attachTooltip(defaultsBtn, L["Defaults"], opts.defaultsTooltip)
    end

    return titleFS, divider, defaultsBtn
end

-- ---------------------------------------------------------------------
-- CreatePanel — Frame compatible with RegisterCanvasLayoutSubcategory
-- with the unified header stamped on top. Returns a `ctx` table the
-- caller threads through Section / RenderField / RenderSchema /
-- Button / RestoreDefaults.
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
        panel       = panel,
        body        = body,
        scroll      = nil,           -- lazy AceGUI ScrollFrame
        refreshers  = {},
        lastGroup   = nil,
        panelKey    = opts.panelKey,
    }
    KickCD.Settings._panels[#KickCD.Settings._panels + 1] = ctx
    return ctx
end

-- ---------------------------------------------------------------------
-- Lazy AceGUI scroll container. Tabs that drive ctx.body directly
-- (Spells, Profiles) never trigger this; they place their own AceGUI
-- containers on top of ctx.body.
-- ---------------------------------------------------------------------

local function ensureScroll(ctx)
    if ctx.scroll then return ctx.scroll end
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll.frame:SetParent(ctx.body)
    scroll.frame:ClearAllPoints()
    scroll.frame:SetPoint("TOPLEFT",     ctx.body, "TOPLEFT",      PADDING_X - 4, -8)
    scroll.frame:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -(PADDING_X - 4), 8)
    scroll.frame:Show()
    ctx.scroll = scroll
    return scroll
end

local function fireOnChange(def, value)
    if def.onChange then
        local ok, err = pcall(def.onChange, value)
        if not ok and KickCD.Util then
            KickCD.Util.print("onChange for " .. tostring(def.path) .. " failed: " .. tostring(err))
        end
    end
end

-- ---------------------------------------------------------------------
-- Section header — AceGUI Heading (full-width label flanked by side
-- divider textures, matches AceConfigDialog group separators).
-- ---------------------------------------------------------------------

function Helpers.Section(ctx, label)
    local scroll = ensureScroll(ctx)
    local h = AceGUI:Create("Heading")
    h:SetText(label)
    h:SetFullWidth(true)
    scroll:AddChild(h)
    return h
end

-- ---------------------------------------------------------------------
-- Widget creators — each binds directly to db.profile via
-- Helpers.Get/Set, registers a refresher closure so the widget can
-- re-sync after a Defaults reset or a /kcd set, and adds itself to
-- the panel's AceGUI ScrollFrame container.
-- ---------------------------------------------------------------------

local function makeCheckbox(ctx, def)
    local scroll = ensureScroll(ctx)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(def.label or def.path)
    cb:SetFullWidth(true)
    cb:SetValue(Helpers.Get(def.path) and true or false)

    local function refresh()
        cb:SetValue(Helpers.Get(def.path) and true or false)
    end

    cb:SetCallback("OnValueChanged", function(_, _, value)
        local v = value and true or false
        Helpers.Set(def.path, def.section, v)
        fireOnChange(def, v)
    end)

    attachTooltip(cb, def.label, def.tooltip)
    scroll:AddChild(cb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cb
end

-- AceGUI's Slider writes its raw numeric value into the editbox via
-- UpdateText() inside the C-side OnValueChanged handler. To honour
-- def.fmt ("%.2fx", "%d px"), we PostHook the inner slider's
-- OnValueChanged so our formatted text overwrites UpdateText's, and we
-- also re-format after each SetValue() (refresh path).
local function snapToStep(value, mn, step)
    if not (step and step > 0) then return value end
    return math.floor((value - mn) / step + 0.5) * step + mn
end

local function makeSlider(ctx, def)
    local scroll = ensureScroll(ctx)
    local s = AceGUI:Create("Slider")
    s:SetLabel(def.label or def.path)
    s:SetSliderValues(def.min or 0, def.max or 1, def.step or 1)
    s:SetIsPercent(false)
    s:SetFullWidth(true)

    local function applyFormat(value)
        if not (def.fmt and s.editbox) then return end
        local snapped = snapToStep(value, def.min or 0, def.step or 0)
        local ok, str = pcall(string.format, def.fmt, snapped)
        if ok then s.editbox:SetText(str) end
    end

    -- HookScript runs after AceGUI's Slider_OnValueChanged (which calls
    -- UpdateText), so our formatted text wins.
    if s.slider then
        s.slider:HookScript("OnValueChanged", function(slider, newvalue)
            if slider.setup then return end
            applyFormat(newvalue)
        end)
    end

    local function refresh()
        local v = Helpers.Get(def.path)
        if type(v) ~= "number" then v = def.default or def.min or 0 end
        s:SetValue(v)
        applyFormat(v)
    end

    s:SetCallback("OnMouseUp", function(_, _, value)
        local snapped = snapToStep(value, def.min or 0, def.step or 0)
        Helpers.Set(def.path, def.section, snapped)
        fireOnChange(def, snapped)
        applyFormat(snapped)
    end)

    attachTooltip(s, def.label, def.tooltip)
    scroll:AddChild(s)
    refresh()
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return s
end

local function makeDropdown(ctx, def)
    local scroll = ensureScroll(ctx)
    local dd = AceGUI:Create("Dropdown")
    dd:SetLabel(def.label or def.path)
    dd:SetFullWidth(true)

    local function valuesList()
        if type(def.values) == "function" then return def.values() or {} end
        return def.values or {}
    end

    local function applyList()
        local items, order = {}, {}
        for i, item in ipairs(valuesList()) do
            items[item.value] = item.label or tostring(item.value)
            order[i] = item.value
        end
        dd:SetList(items, order)
    end
    applyList()
    dd:SetValue(Helpers.Get(def.path))

    local function refresh()
        applyList()                            -- LSM lists may grow over time
        dd:SetValue(Helpers.Get(def.path))
    end

    dd:SetCallback("OnValueChanged", function(_, _, value)
        Helpers.Set(def.path, def.section, value)
        fireOnChange(def, value)
    end)

    attachTooltip(dd, def.label, def.tooltip)
    scroll:AddChild(dd)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return dd
end

local function makeColorPicker(ctx, def)
    local scroll = ensureScroll(ctx)
    local cp = AceGUI:Create("ColorPicker")
    cp:SetLabel(def.label or def.path)
    cp:SetHasAlpha(true)
    cp:SetFullWidth(true)

    local function readColor()
        local c = Helpers.Get(def.path)
        if type(c) ~= "table" then c = { 1, 1, 1, 1 } end
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end

    cp:SetColor(readColor())

    local function refresh()
        cp:SetColor(readColor())
    end

    cp:SetCallback("OnValueConfirmed", function(_, _, r, g, b, a)
        Helpers.Set(def.path, def.section, { r, g, b, a or 1 })
        fireOnChange(def, { r, g, b, a or 1 })
    end)

    attachTooltip(cp, def.label, def.tooltip)
    scroll:AddChild(cp)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cp
end

-- Generic field renderer — dispatches by def.type.
function Helpers.RenderField(ctx, def)
    if def.type == "bool"   then return makeCheckbox(ctx, def)    end
    if def.type == "number" then return makeSlider(ctx, def)      end
    if def.type == "string" then return makeDropdown(ctx, def)    end
    if def.type == "color"  then return makeColorPicker(ctx, def) end
end

-- Inline action button (label on the left, button on the right).
-- Used for "Reset position" et al. — not a setting.
function Helpers.Button(ctx, labelText, buttonText, tooltip, onClick)
    local scroll = ensureScroll(ctx)

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(28)

    local lbl = AceGUI:Create("Label")
    lbl:SetText(labelText or "")
    lbl:SetWidth(280)
    row:AddChild(lbl)

    local btn = AceGUI:Create("Button")
    btn:SetText(buttonText or "")
    btn:SetWidth(140)
    btn:SetCallback("OnClick", function()
        if not onClick then return end
        local ok, err = pcall(onClick)
        if not ok and KickCD.Util then
            KickCD.Util.print("button onClick failed: " .. tostring(err))
        end
    end)
    row:AddChild(btn)

    attachTooltip(btn, labelText, tooltip)
    scroll:AddChild(row)
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
    if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
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
