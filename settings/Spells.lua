-- settings/Spells.lua — KickCD v0.1
--
-- Per-class+spec spell-list editor. Uses the unified canvas panel
-- header (title + Defaults button + divider) from Panel.lua, then
-- hosts the AceGUI editor (class/spec dropdowns, Add spell button,
-- scrollable row list) inside ctx.body. The "Defaults" button in the
-- header runs the existing reset-to-defaults StaticPopup for the
-- currently selected class+spec.
--
-- Writes go through a 50ms debounced setter that mutates the profile,
-- re-renders the rows, and fires KickCD_CONFIG_CHANGED { section = "spells" }.

local KickCD = LibStub and LibStub("AceAddon-3.0", true)
                  and LibStub("AceAddon-3.0"):GetAddon("KickCD", true)
                  or _G.KickCD
KickCD = KickCD or {}

local L      = KickCD.L      or setmetatable({}, { __index = function(_, k) return k end })
local Compat = KickCD.Compat or {}
local Util   = KickCD.Util   or {}

local Spells = {}
KickCD.SettingsSpells = Spells

-- The closed category set per FR-7.6.
local CATEGORIES = {
    "interrupt", "stun", "knockback", "incapacitate",
    "silence", "root", "fear", "racial", "other",
}

-- ---------------------------------------------------------------------------
-- Module-private state
-- ---------------------------------------------------------------------------

local ctx              -- the H.CreatePanel context (panel + body + cursor + ...)
local panel            -- ctx.panel — the canvas Frame
local body             -- ctx.body — frame below the unified header
local container        -- AceGUI ScrollFrame (re-created on each show)
local headerWidgets    -- AceGUI dropdowns/button — released on hide
local fallbackLabel    -- shown when AceGUI isn't available
local selectedClass
local selectedSpec
local rebuildScheduled

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = deepCopy(vv) end
    return out
end

local function sortedKeys(t)
    local keys = {}
    if type(t) == "table" then
        for k in pairs(t) do keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

local function getProfileSpells()
    if not (KickCD.db and KickCD.db.profile) then return nil end
    KickCD.db.profile.spells = KickCD.db.profile.spells or {}
    return KickCD.db.profile.spells
end

local function getActiveList()
    local spells = getProfileSpells()
    if not spells then return nil end
    if not selectedClass then return nil end
    spells[selectedClass] = spells[selectedClass] or {}
    if not selectedSpec then return nil end
    spells[selectedClass][selectedSpec] = spells[selectedClass][selectedSpec] or {}
    return spells[selectedClass][selectedSpec]
end

local function getSpellName(id)
    if not id then return nil end
    if Compat.GetSpellInfo then
        local name = Compat.GetSpellInfo(id)
        if name then return name end
    end
    return nil
end

local function getSpellIcon(id)
    if not id then return nil end
    if Compat.GetSpellTexture then return Compat.GetSpellTexture(id) end
    return nil
end

local function validateSpellInput(input)
    if not input or input == "" then return nil end
    local id = tonumber(input)
    if id then
        local name = getSpellName(id)
        if name then return id, name end
        return nil
    end
    if Compat.GetSpellInfo then
        local name, _, _, _, _, resolvedID = Compat.GetSpellInfo(input)
        if name and resolvedID then return resolvedID, name end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Debounced commit pipeline
-- ---------------------------------------------------------------------------

local function FireConfigChanged()
    if KickCD and KickCD.SendMessage then
        KickCD:SendMessage("KickCD_CONFIG_CHANGED", { section = "spells" })
    end
end

local commitSoon

local function doCommit()
    if panel and panel:IsShown() then Spells:RefreshRows() end
    FireConfigChanged()
end

if Util.Debounce then
    commitSoon = Util.Debounce(50, doCommit)
else
    commitSoon = doCommit
end

-- ---------------------------------------------------------------------------
-- StaticPopups (Add spell / Reset to defaults)
-- ---------------------------------------------------------------------------

StaticPopupDialogs["KICKCD_ADD_SPELL"] = {
    text         = L["Spell ID or name"],
    button1      = L["OK"],
    button2      = L["Cancel"],
    hasEditBox   = true,
    maxLetters   = 64,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnShow = function(self)
        local edit = self.EditBox or self.editBox
        edit:SetText("")
        edit:SetFocus()
    end,
    OnAccept = function(self)
        local edit = self.EditBox or self.editBox
        local input = edit:GetText()
        local id = validateSpellInput(input)
        if not id then
            if KickCD.Util and KickCD.Util.print then
                KickCD.Util.print(L["Invalid spell"] .. ": " .. tostring(input))
            end
            return
        end
        local list = getActiveList()
        if not list then return end
        for _, e in ipairs(list) do
            if e.spellID == id then
                e.enabled = true
                commitSoon()
                return
            end
        end
        list[#list + 1] = { spellID = id, category = "other", enabled = true }
        commitSoon()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then parent.button1:Click() end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["KICKCD_RESET_SPELLS"] = {
    text         = L["Reset all spells for this spec to addon defaults?"],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept = function()
        local spells = getProfileSpells()
        if not (spells and selectedClass and selectedSpec) then return end
        local source = KickCD.DefaultSpells
                       and KickCD.DefaultSpells[selectedClass]
                       and KickCD.DefaultSpells[selectedClass][selectedSpec]
        spells[selectedClass] = spells[selectedClass] or {}
        if source then
            spells[selectedClass][selectedSpec] = deepCopy(source)
            for _, e in ipairs(spells[selectedClass][selectedSpec]) do
                e.spellID  = e.spellID  or e[1]
                e.category = e.category or e[2] or "other"
                if e.enabled == nil then e.enabled = true end
            end
        else
            spells[selectedClass][selectedSpec] = {}
        end
        commitSoon()
    end,
}

-- ---------------------------------------------------------------------------
-- AceGUI rows
-- ---------------------------------------------------------------------------

local function buildRow(AceGUI, parent, list, index)
    local entry = list[index]
    if not entry then return end

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(28)

    local icon = AceGUI:Create("Icon")
    icon:SetImage(getSpellIcon(entry.spellID) or 134400)
    icon:SetImageSize(20, 20)
    icon:SetWidth(28)
    icon:SetHeight(24)
    icon:SetCallback("OnClick", function() end)
    row:AddChild(icon)

    local label = AceGUI:Create("Label")
    local name = getSpellName(entry.spellID) or ("#" .. tostring(entry.spellID))
    label:SetText(name .. "  (#" .. tostring(entry.spellID) .. ")")
    label:SetWidth(220)
    row:AddChild(label)

    local check = AceGUI:Create("CheckBox")
    check:SetLabel("")
    check:SetValue(entry.enabled ~= false)
    check:SetWidth(40)
    check:SetCallback("OnValueChanged", function(_, _, value)
        entry.enabled = value and true or false
        commitSoon()
    end)
    row:AddChild(check)

    local dd = AceGUI:Create("Dropdown")
    local items, order = {}, {}
    for i, cat in ipairs(CATEGORIES) do
        items[cat] = L[cat] or cat
        order[i]   = cat
    end
    dd:SetList(items, order)
    dd:SetValue(entry.category or "other")
    dd:SetWidth(120)
    dd:SetCallback("OnValueChanged", function(_, _, value)
        entry.category = value
        commitSoon()
    end)
    row:AddChild(dd)

    local upBtn = AceGUI:Create("Button")
    upBtn:SetText(L["Move up"] == "Move up" and "Up" or L["Move up"])
    upBtn:SetWidth(50)
    upBtn:SetDisabled(index == 1)
    upBtn:SetCallback("OnClick", function()
        if index <= 1 then return end
        list[index], list[index - 1] = list[index - 1], list[index]
        commitSoon()
    end)
    row:AddChild(upBtn)

    local downBtn = AceGUI:Create("Button")
    downBtn:SetText(L["Move down"] == "Move down" and "Dn" or L["Move down"])
    downBtn:SetWidth(50)
    downBtn:SetDisabled(index == #list)
    downBtn:SetCallback("OnClick", function()
        if index >= #list then return end
        list[index], list[index + 1] = list[index + 1], list[index]
        commitSoon()
    end)
    row:AddChild(downBtn)

    local rmBtn = AceGUI:Create("Button")
    rmBtn:SetText("X")
    rmBtn:SetWidth(40)
    rmBtn:SetCallback("OnClick", function()
        table.remove(list, index)
        commitSoon()
    end)
    row:AddChild(rmBtn)

    return row
end

-- ---------------------------------------------------------------------------
-- Rebuild
-- ---------------------------------------------------------------------------

local function releaseAceGUITree()
    if container then
        container:ReleaseChildren()
        if container.Release then container:Release() end
        container = nil
    end
    if headerWidgets then
        for _, w in ipairs(headerWidgets) do
            if w and w.Release then w:Release() end
        end
        headerWidgets = nil
    end
end

local function buildSpellsHeader(AceGUI, parent, classes)
    headerWidgets = {}

    local classDD = AceGUI:Create("Dropdown")
    local classItems, classOrder = {}, {}
    for i, c in ipairs(classes) do
        classItems[c] = c
        classOrder[i] = c
    end
    classDD:SetLabel(L["Class"])
    classDD:SetList(classItems, classOrder)
    classDD:SetValue(selectedClass)
    classDD:SetWidth(160)
    classDD:SetCallback("OnValueChanged", function(_, _, value)
        selectedClass = value
        local specs = sortedKeys(KickCD.DefaultSpells and KickCD.DefaultSpells[value])
        selectedSpec = specs[1]
        Spells:RefreshRows()
    end)
    classDD.frame:SetParent(parent)
    classDD.frame:ClearAllPoints()
    classDD.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    classDD.frame:Show()
    headerWidgets[#headerWidgets + 1] = classDD

    local specDD = AceGUI:Create("Dropdown")
    local specs = sortedKeys(KickCD.DefaultSpells and KickCD.DefaultSpells[selectedClass])
    local specItems, specOrder = {}, {}
    for i, s in ipairs(specs) do
        specItems[s] = s
        specOrder[i] = s
    end
    specDD:SetLabel(L["Specialization"])
    specDD:SetList(specItems, specOrder)
    specDD:SetValue(selectedSpec)
    specDD:SetWidth(160)
    specDD:SetCallback("OnValueChanged", function(_, _, value)
        selectedSpec = value
        Spells:RefreshRows()
    end)
    specDD.frame:SetParent(parent)
    specDD.frame:ClearAllPoints()
    specDD.frame:SetPoint("LEFT", classDD.frame, "RIGHT", 12, 0)
    specDD.frame:Show()
    headerWidgets[#headerWidgets + 1] = specDD

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText(L["Add spell..."])
    addBtn:SetWidth(140)
    addBtn:SetCallback("OnClick", function()
        StaticPopup_Show("KICKCD_ADD_SPELL")
    end)
    addBtn.frame:SetParent(parent)
    addBtn.frame:ClearAllPoints()
    addBtn.frame:SetPoint("LEFT", specDD.frame, "RIGHT", 12, 0)
    addBtn.frame:Show()
    headerWidgets[#headerWidgets + 1] = addBtn
end

function Spells:RefreshRows()
    if not panel or not panel:IsShown() then return end
    if rebuildScheduled then return end
    rebuildScheduled = true

    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then
        rebuildScheduled = false
        if not fallbackLabel then
            fallbackLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fallbackLabel:SetPoint("CENTER", body, "CENTER", 0, 0)
            fallbackLabel:SetText("AceGUI not loaded")
        end
        fallbackLabel:Show()
        return
    end

    releaseAceGUITree()

    local classes = sortedKeys(KickCD.DefaultSpells)
    if not selectedClass or not (KickCD.DefaultSpells and KickCD.DefaultSpells[selectedClass]) then
        local _, classFile = UnitClass("player")
        if classFile and KickCD.DefaultSpells and KickCD.DefaultSpells[classFile] then
            selectedClass = classFile
        else
            selectedClass = classes[1]
        end
    end
    if selectedClass and not selectedSpec then
        local specs = sortedKeys(KickCD.DefaultSpells and KickCD.DefaultSpells[selectedClass])
        selectedSpec = specs[1]
    end

    buildSpellsHeader(AceGUI, body, classes)

    container = AceGUI:Create("ScrollFrame")
    container:SetLayout("List")
    container.frame:SetParent(body)
    container.frame:ClearAllPoints()
    container.frame:SetPoint("TOPLEFT",     body, "TOPLEFT",     16, -56)
    container.frame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -16, 16)
    container.frame:Show()

    local list = getActiveList()
    if not list or #list == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText("No spells tracked. Click " .. L["Add spell..."] .. " or " .. L["Defaults"] .. ".")
        lbl:SetFullWidth(true)
        container:AddChild(lbl)
    else
        for i = 1, #list do
            local row = buildRow(AceGUI, body, list, i)
            if row then container:AddChild(row) end
        end
    end

    rebuildScheduled = false
end

-- ---------------------------------------------------------------------------
-- Panel registration
-- ---------------------------------------------------------------------------

local function ensurePanel()
    if panel then return panel end

    local H = KickCD.Settings and KickCD.Settings.Helpers
    if not (H and H.CreatePanel) then return nil end

    ctx = H.CreatePanel("KickCDSpellsPanel", L["Spells"], {
        panelKey       = "spells",
        defaultsButton = true,
    })
    panel = ctx.panel
    body  = ctx.body

    if panel.defaultsBtn then
        panel.defaultsBtn:SetCallback("OnClick", function()
            StaticPopup_Show("KICKCD_RESET_SPELLS")
        end)
    end

    panel:SetScript("OnShow", function() Spells:RefreshRows() end)
    panel:SetScript("OnHide", function()
        releaseAceGUITree()
        if fallbackLabel then fallbackLabel:Hide() end
    end)

    if KickCD.RegisterMessage then
        KickCD:RegisterMessage("KickCD_PROFILE_CHANGED", function()
            if panel and panel:IsShown() then Spells:RefreshRows() end
        end)
    end

    return panel
end

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end
    if not ensurePanel() then return nil end

    -- Seed dropdowns from the player's class so the editor opens to the
    -- user's "current" list by default.
    local _, classFile = UnitClass("player")
    if classFile and KickCD.DefaultSpells and KickCD.DefaultSpells[classFile] then
        selectedClass = selectedClass or classFile
        local specs = sortedKeys(KickCD.DefaultSpells[classFile])
        selectedSpec = selectedSpec or specs[1]
    end

    return Settings.RegisterCanvasLayoutSubcategory(mainCategory, panel, L["Spells"])
end

if KickCD.Settings and KickCD.Settings.RegisterTab then
    KickCD.Settings.RegisterTab("spells", Build)
end

-- Back-compat shim: earlier code paths called Spells:Register() directly.
function Spells:Register()
    if KickCD.Settings and KickCD.Settings.main then
        Build(KickCD.Settings.main)
    end
end
