-- settings/Panel.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §5.1, §5.2 and docs/REQUIREMENTS.md FR-6.1, FR-6.2
--
-- Panel.lua is the entry point for the Blizzard Settings integration. It:
--   1. Registers the top-level "Ka0s KickCD" category once `Settings` is
--      available, defensively retrying on ADDON_LOADED("Blizzard_Settings")
--      if the table doesn't exist at file-load time.
--   2. Stamps KickCD.SettingsCategoryID so core/KickCD.lua's OpenSettings()
--      can find us (see EXECUTION_PLAN §6 / contract).
--   3. Exposes a small `KickCD.Settings` table that per-tab files
--      (General/Icons/Spells/Profiles) push their subcategories
--      into, in display order.
--   4. Provides widget helpers reused by every tab so each settings file
--      stays focused on its widget list rather than boilerplate.
--
-- Per the TOC, all settings/* files load AFTER every module — by the time
-- this file runs, KickCD is a fully-initialized AceAddon, KickCD.db is
-- live, and modules are listening for KickCD_CONFIG_CHANGED.

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local L      = KickCD.L

-- ---------------------------------------------------------------------------
-- Public state
-- ---------------------------------------------------------------------------
--
-- KickCD.Settings is the shared mailbox between Panel.lua and the per-tab
-- files. Each tab file calls KickCD.Settings.RegisterTab(key, fn) at file
-- load time. Panel.lua collects those callbacks and invokes them once the
-- main category is wired (which may be deferred until ADDON_LOADED if the
-- Settings global isn't ready yet).

KickCD.Settings = KickCD.Settings or {
    main      = nil,
    sub       = {},      -- { general=, icons=, spells=, profiles= }
    builders  = {},      -- { general=fn, icons=fn, ... }
    -- Display order; the Settings panel renders subcategories in registration
    -- order, so we walk this list when invoking builders.
    order     = { "general", "icons", "spells", "profiles" },
}

-- ---------------------------------------------------------------------------
-- Widget helpers (shared by all settings/* files)
-- ---------------------------------------------------------------------------

local Helpers = {}
KickCD.Settings.Helpers = Helpers

--- Add a section header initializer to a vertical-layout subcategory.
-- Mirrors the Blizzard pattern shown in RESEARCH.md §4.2:
--   layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
-- We resolve the layout via Settings.GetCategoryLayout so callers don't have
-- to track their layout reference separately.
-- @param sub  Settings subcategory object
-- @param name string  Header text (already localized by caller)
function Helpers.AddSectionHeader(sub, name)
    if not sub or not name then return end
    if not _G.CreateSettingsListSectionHeaderInitializer then return end
    local layout
    if Settings and Settings.GetCategoryLayout then
        layout = Settings.GetCategoryLayout(sub)
    end
    if not layout or not layout.AddInitializer then return end
    layout:AddInitializer(_G.CreateSettingsListSectionHeaderInitializer(name))
end

--- Send the closed KickCD_CONFIG_CHANGED message. Centralized so we can
--- skip-fire when the addon's Settings layer isn't fully wired yet.
-- @param section "general"|"icons"|"spells"
function Helpers.FireConfigChanged(section)
    if KickCD and KickCD.SendMessage then
        KickCD:SendMessage("KickCD_CONFIG_CHANGED", { section = section })
    end
end

-- Walk a dotted path inside db.profile and return (parent, finalKey) so
-- the caller can read/write `parent[finalKey]`. Returns (nil, nil) on any
-- missing intermediate node. Two-pass to keep the loop simple.
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

--- Get a value at a dotted path inside db.profile.
function Helpers.Get(path)
    local parent, key = Resolve(path)
    if not parent then return nil end
    return parent[key]
end

--- Set a value at a dotted path inside db.profile and fire CONFIG_CHANGED.
function Helpers.Set(path, section, value)
    local parent, key = Resolve(path)
    if not parent then return end
    parent[key] = value
    Helpers.FireConfigChanged(section)
end

--- Create a checkbox bound to db.profile[<path>].
-- Returns the Setting object (nil if the API rejected our shape — caller
-- should treat nil as "skip this widget", not error).
-- @param sub      subcategory
-- @param variable unique string id ("KickCD_general_enabled")
-- @param label    localized display name
-- @param tooltip  localized tooltip (may be nil)
-- @param section  "general"|"icons" — for CONFIG_CHANGED
-- @param path     dotted profile path ("enabled", "icons.showCharges", ...)
-- @param onChange optional extra side-effect callback(value) run AFTER the
--                 db write + message fire.
function Helpers.CreateCheckbox(sub, variable, label, tooltip, section, path, onChange)
    if not Settings or not Settings.CreateCheckbox then return nil end
    local current = Helpers.Get(path)
    if current == nil then current = false end

    local setting = KickCD.Compat.RegisterAddOnSetting(
        sub, variable, label, current, Settings.VarType.Boolean)
    if not setting then return nil end

    setting:SetValueChangedCallback(function(_, value)
        Helpers.Set(path, section, value and true or false)
        if onChange then onChange(value) end
    end)
    Settings.CreateCheckbox(sub, setting, tooltip)
    return setting
end

--- Create a slider bound to db.profile[<path>].
-- Uses Settings.CreateSliderOptions(min, max, step) per RESEARCH.md §4.2.
-- @param min, max, step  numeric range
-- @param fmt   optional string-format pattern (e.g. "%.2f") for label suffix
function Helpers.CreateSlider(sub, variable, label, tooltip, section, path,
                              min, max, step, fmt)
    if not Settings or not Settings.CreateSlider or not Settings.CreateSliderOptions then
        return nil
    end
    local current = Helpers.Get(path)
    if type(current) ~= "number" then current = min end

    local setting = KickCD.Compat.RegisterAddOnSetting(
        sub, variable, label, current, Settings.VarType.Number)
    if not setting then return nil end

    setting:SetValueChangedCallback(function(_, value)
        Helpers.Set(path, section, value)
    end)

    local opts = Settings.CreateSliderOptions(min, max, step)
    if fmt and opts and opts.SetLabelFormatter and _G.MinimalSliderWithSteppersMixin then
        opts:SetLabelFormatter(
            _G.MinimalSliderWithSteppersMixin.Label.Right,
            function(v) return fmt:format(v) end)
    end
    Settings.CreateSlider(sub, setting, opts, tooltip)
    return setting
end

--- Create a dropdown bound to db.profile[<path>].
-- @param values  array of { value=, label= } pairs
-- @param varType optional Settings.VarType.* (defaults to String)
function Helpers.CreateDropdown(sub, variable, label, tooltip, section, path,
                                values, varType)
    if not Settings or not Settings.CreateDropdown then return nil end
    local current = Helpers.Get(path)
    if current == nil and values[1] then current = values[1].value end

    local setting = KickCD.Compat.RegisterAddOnSetting(
        sub, variable, label, current, varType or Settings.VarType.String)
    if not setting then return nil end

    setting:SetValueChangedCallback(function(_, value)
        Helpers.Set(path, section, value)
    end)

    local function getOptions()
        if not Settings.CreateControlTextContainer then return nil end
        local c = Settings.CreateControlTextContainer()
        for _, item in ipairs(values) do
            c:Add(item.value, item.label)
        end
        return c:GetData()
    end
    Settings.CreateDropdown(sub, setting, getOptions, tooltip)
    return setting
end

--- Build the option list for a LibSharedMedia media type.
-- Returns an array of { value=key, label=key } where each `key` is a name
-- registered with LSM. Falls back to a single "Default" entry when LSM
-- isn't loaded so the dropdown still renders without erroring.
-- @param mediaType "statusbar"|"font"|"border"
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

--- Create a color picker entry on the layout.
-- Per EXECUTION_PLAN §6, we prefer Settings.SetupCVarColorPicker if it's
-- present; that helper is bound to CVars not addon settings, so calling
-- it with our identifier will typically fail. We pcall it anyway so a
-- future build that genericizes the API "just works", and otherwise fall
-- through to a hand-rolled button + ColorPickerFrame pattern via a custom
-- initializer. If even that path is unavailable (very old Settings build),
-- we silently drop the widget — the variable still lives in db.profile
-- and is editable via SavedVariables.
-- @param sub      subcategory
-- @param variable unique string id
-- @param label    localized label
-- @param tooltip  localized tooltip
-- @param section  "icons"
-- @param path     dotted profile path to a {r,g,b,a} array
function Helpers.CreateColorPicker(sub, variable, label, tooltip, section, path)
    local current = Helpers.Get(path)
    if type(current) ~= "table" then current = { 1, 1, 1, 1 } end

    -- Path 1: try Settings.SetupCVarColorPicker if it exists (TWW+ exposed
    -- this name on some builds for CVar-bound colors). Pcall for safety so
    -- a wrong-shape signature doesn't error out the addon.
    if Settings and Settings.SetupCVarColorPicker then
        local ok = pcall(Settings.SetupCVarColorPicker,
            sub, variable, variable, label, tooltip,
            current[1], current[2], current[3], current[4],
            function(r, g, b, a)
                Helpers.Set(path, section, { r, g, b, a or 1 })
            end)
        if ok then return end
    end

    -- Path 2: hand-rolled custom initializer hosting a button that opens
    -- the global ColorPickerFrame. We build this only when possible; if
    -- the canvas APIs aren't there, we no-op (FR-6 is best-effort per
    -- setting, not all-or-nothing).
    if not (Settings and Settings.GetCategoryLayout
            and CreateFrame and _G.ColorPickerFrame) then
        return
    end
    local layout = Settings.GetCategoryLayout(sub)
    if not layout or not layout.AddInitializer then return end

    -- Wrap the click in a small object so each color picker keeps its own
    -- swatch + opener button without a closure-per-widget.
    local function openPicker()
        local cur = Helpers.Get(path) or { 1, 1, 1, 1 }
        local info = {
            swatchFunc = function()
                local r, g, b
                if _G.ColorPickerFrame.GetColorRGB then
                    r, g, b = _G.ColorPickerFrame:GetColorRGB()
                else
                    r, g, b = _G.ColorPickerFrame.r, _G.ColorPickerFrame.g, _G.ColorPickerFrame.b
                end
                local a = 1 - (_G.OpacitySliderFrame and _G.OpacitySliderFrame:GetValue() or 0)
                Helpers.Set(path, section, { r, g, b, a })
            end,
            opacityFunc = function()
                local a = 1 - (_G.OpacitySliderFrame and _G.OpacitySliderFrame:GetValue() or 0)
                local cc = Helpers.Get(path) or { 1, 1, 1, 1 }
                Helpers.Set(path, section, { cc[1], cc[2], cc[3], a })
            end,
            cancelFunc = function(prev)
                if prev then
                    Helpers.Set(path, section,
                        { prev.r or prev[1], prev.g or prev[2],
                          prev.b or prev[3], 1 - (prev.opacity or 0) })
                end
            end,
            hasOpacity = true,
            opacity    = 1 - (cur[4] or 1),
            r          = cur[1] or 1,
            g          = cur[2] or 1,
            b          = cur[3] or 1,
        }
        if _G.OpenColorPicker then
            _G.OpenColorPicker(info)
        end
    end

    -- Some Midnight builds ship CreateSettingsButtonInitializer; use it when
    -- available so the swatch lives in the same vertical layout as native
    -- widgets. Otherwise we drop the picker silently — the variable still
    -- exists in db.profile and is editable via /reload + SV file.
    if _G.CreateSettingsButtonInitializer then
        layout:AddInitializer(
            _G.CreateSettingsButtonInitializer(label, label, openPicker, tooltip))
    end
end

-- ---------------------------------------------------------------------------
-- Tab registration API
-- ---------------------------------------------------------------------------

--- A per-tab file calls this to register its builder. The builder receives
--- the main category and returns the subcategory it created. We invoke
--- builders in the canonical KickCD.Settings.order so layout is stable
--- regardless of TOC load order surprises.
function KickCD.Settings.RegisterTab(key, builder)
    if type(key) ~= "string" or type(builder) ~= "function" then return end
    KickCD.Settings.builders[key] = builder
    -- If the main category already exists (i.e. Panel.lua was deferred and
    -- registered the panel after a later tab loaded), build this tab now.
    if KickCD.Settings.main and not KickCD.Settings.sub[key] then
        local ok, sub = pcall(builder, KickCD.Settings.main)
        if ok and sub then
            KickCD.Settings.sub[key] = sub
        end
    end
end

-- ---------------------------------------------------------------------------
-- Top-level category registration
-- ---------------------------------------------------------------------------

--- Register the "Ka0s KickCD" category and dispatch each tab builder.
-- Idempotent — calling twice is a no-op.
local function RegisterPanel()
    if KickCD.Settings.main then return end
    if not Settings or not Settings.RegisterVerticalLayoutCategory
       or not Settings.RegisterAddOnCategory then
        return  -- caller will retry on ADDON_LOADED("Blizzard_Settings")
    end

    local mainCategory = Settings.RegisterVerticalLayoutCategory(L["Ka0s KickCD"])
    Settings.RegisterAddOnCategory(mainCategory)

    KickCD.Settings.main = mainCategory
    KickCD.SettingsCategoryID = mainCategory:GetID()

    -- Build each tab in the canonical order. Missing builders (e.g. a tab
    -- file failed to register) are skipped silently — the panel still loads
    -- and the surviving tabs work.
    for _, key in ipairs(KickCD.Settings.order) do
        local fn = KickCD.Settings.builders[key]
        if type(fn) == "function" and not KickCD.Settings.sub[key] then
            local ok, sub = pcall(fn, mainCategory)
            if ok and sub then
                KickCD.Settings.sub[key] = sub
            elseif not ok and KickCD.Util then
                KickCD.Util.print(
                    "settings tab '" .. key .. "' failed to build: " .. tostring(sub))
            end
        end
    end
end
KickCD.Settings.Register = RegisterPanel

-- ---------------------------------------------------------------------------
-- Bootstrap timing
-- ---------------------------------------------------------------------------
--
-- Because the TOC loads Panel.lua first among settings/* and tab files
-- register their builders during their own file-load, we don't try to
-- register the panel synchronously here — instead we defer the actual
-- Settings.* calls until PLAYER_LOGIN, by which time:
--   * Every tab file has run and registered its builder.
--   * Blizzard_Settings has fully initialized.
-- We still attempt early registration if Settings is already there, in
-- case a future build loads Settings even earlier.

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
