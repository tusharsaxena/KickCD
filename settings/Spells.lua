-- settings/Spells.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §5.3, docs/REQUIREMENTS.md FR-6.2.4 + FR-7
--
-- Per-class+spec spell-list editor. Registered as a Settings *canvas* sub-
-- category under KickCD.Settings.main (built by Agent C1) because the row UI
-- (icon | name+ID | enabled toggle | category dropdown | up | down | x) is
-- too custom for native Settings widgets. We embed AceGUI inside a plain
-- canvas frame and rebuild the AceGUI widget tree on each show.
--
-- Top of panel:
--   * Class dropdown   — defaults to player's class
--   * Spec  dropdown   — populated from KickCD.DefaultSpells[class]
--   * "Add spell..."   — StaticPopup with EditBox; validates via Compat.GetSpellInfo
--   * "Reset to defaults" — StaticPopup confirmation; deep-copies defaults
--
-- Writes go through a 50ms debounced setter that mutates the profile,
-- re-renders the rows, and fires KickCD_CONFIG_CHANGED { section = "spells" }.

local KickCD = LibStub and LibStub("AceAddon-3.0", true)
                  and LibStub("AceAddon-3.0"):GetAddon("KickCD", true)
                  or _G.KickCD
KickCD = KickCD or {}

local L      = KickCD.L or setmetatable({}, { __index = function(_, k) return k end })
local Compat = KickCD.Compat or {}
local Util   = KickCD.Util   or {}

local Spells = {}
KickCD.SettingsSpells = Spells

-- The closed category set per FR-7.6. Keep insertion order stable so the
-- dropdown reads top-to-bottom in a predictable order.
local CATEGORIES = {
    "interrupt", "stun", "knockback", "incapacitate",
    "silence", "root", "fear", "racial", "other",
}

-- ---------------------------------------------------------------------------
-- State (module-private)
-- ---------------------------------------------------------------------------

local panel              -- the canvas Frame registered with Settings
local container          -- AceGUI ScrollFrame (re-created on each show)
local headerWidgets      -- { classDD, specDD, addBtn, resetBtn } — released on hide
local fallbackLabel      -- shown when AceGUI isn't available
local emptyLabel         -- shown when the spec list is empty
local selectedClass
local selectedSpec
local rebuildScheduled   -- guards against re-entrant Refresh during write

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

--- Resolve the active list for the dropdown selection, creating the
--- class/spec table along the way so subsequent edits land somewhere.
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
    if Compat.GetSpellTexture then
        return Compat.GetSpellTexture(id)
    end
    return nil
end

--- Validate a user-typed spell input (numeric ID first, then name).
-- Returns (spellID, name) on success, nil on failure.
local function validateSpellInput(input)
    if not input or input == "" then return nil end
    local id = tonumber(input)
    if id then
        local name = getSpellName(id)
        if name then return id, name end
        return nil
    end
    -- Try as name. C_Spell.GetSpellInfo accepts a name string and returns
    -- the resolved spellID in the .spellID field on success.
    if Compat.GetSpellInfo then
        local name, _, _, _, _, resolvedID = Compat.GetSpellInfo(input)
        if name and resolvedID then return resolvedID, name end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Debounced write pipeline
-- ---------------------------------------------------------------------------
--
-- Every row mutation (toggle, category change, reorder, remove) collapses
-- through this single function. Util.Debounce coalesces rapid keystrokes
-- into one re-render + one message dispatch.

local function FireConfigChanged()
    if KickCD and KickCD.SendMessage then
        KickCD:SendMessage("KickCD_CONFIG_CHANGED", { section = "spells" })
    end
end

local commitSoon  -- forward decl so RefreshRows can call it via closures

local function doCommit()
    -- Re-render and notify modules. Both are cheap; the debounce keeps
    -- them from running per-keystroke.
    if panel and panel:IsShown() then
        Spells:RefreshRows()
    end
    FireConfigChanged()
end

if Util.Debounce then
    commitSoon = Util.Debounce(50, doCommit)
else
    -- Defensive fallback if core/Util.lua failed to load — synchronous
    -- commit still keeps the UI consistent, just without coalescing.
    commitSoon = doCommit
end

-- ---------------------------------------------------------------------------
-- StaticPopup dialogs (Add spell / Reset to defaults)
-- ---------------------------------------------------------------------------
--
-- We use StaticPopupDialogs rather than an AceGUI modal so the inputs feel
-- native to the rest of Blizzard's settings UI and so the popup survives
-- the AceGUI tree being torn down on hide.

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
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local input = self.editBox:GetText()
        local id, name = validateSpellInput(input)
        if not id then
            -- Surface the error inline; we don't have a header label
            -- so re-popping the dialog with the localized message gives
            -- the user a clear "try again" affordance.
            if KickCD.Util and KickCD.Util.print then
                KickCD.Util.print(L["Invalid spell"] .. ": " .. tostring(input))
            end
            return
        end
        local list = getActiveList()
        if not list then return end
        -- Avoid duplicate entries — toggle the existing one back on instead.
        for _, e in ipairs(list) do
            if e.spellID == id then
                e.enabled = true
                commitSoon()
                return
            end
        end
        list[#list + 1] = {
            spellID  = id,
            category = "other",
            enabled  = true,
        }
        commitSoon()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then
            parent.button1:Click()
        end
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
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
            -- Deep-copy so subsequent edits don't mutate the shared default
            -- list (a subtle bug if reset, then edited, then reset again).
            spells[selectedClass][selectedSpec] = deepCopy(source)
            -- Make sure each entry has the named-field shape Database expects.
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
-- AceGUI row construction
-- ---------------------------------------------------------------------------

local function buildRow(AceGUI, parent, list, index)
    local entry = list[index]
    if not entry then return end

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(28)

    -- Icon
    local icon = AceGUI:Create("Icon")
    icon:SetImage(getSpellIcon(entry.spellID) or 134400)
    icon:SetImageSize(20, 20)
    icon:SetWidth(28)
    icon:SetHeight(24)
    icon:SetCallback("OnClick", function() end)  -- non-interactive but must be set
    row:AddChild(icon)

    -- Name + ID label
    local label = AceGUI:Create("Label")
    local name = getSpellName(entry.spellID) or ("#" .. tostring(entry.spellID))
    label:SetText(name .. "  (#" .. tostring(entry.spellID) .. ")")
    label:SetWidth(220)
    row:AddChild(label)

    -- Enabled checkbox
    local check = AceGUI:Create("CheckBox")
    check:SetLabel("")
    check:SetValue(entry.enabled ~= false)
    check:SetWidth(40)
    check:SetCallback("OnValueChanged", function(_, _, value)
        entry.enabled = value and true or false
        commitSoon()
    end)
    row:AddChild(check)

    -- Category dropdown
    local dd = AceGUI:Create("Dropdown")
    local items, order = {}, {}
    for i, cat in ipairs(CATEGORIES) do
        items[cat] = L[cat] or cat
        order[i] = cat
    end
    dd:SetList(items, order)
    dd:SetValue(entry.category or "other")
    dd:SetWidth(120)
    dd:SetCallback("OnValueChanged", function(_, _, value)
        entry.category = value
        commitSoon()
    end)
    row:AddChild(dd)

    -- Up button
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

    -- Down button
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

    -- Remove button
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
-- Build / refresh
-- ---------------------------------------------------------------------------

local function releaseAceGUITree()
    -- Release the scroll container (it cascades to children) and then any
    -- header widgets we created. This returns widgets to AceGUI's pool so
    -- subsequent Show calls don't leak.
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

local function buildHeader(AceGUI, parent, classes)
    headerWidgets = {}

    -- Class dropdown
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
        -- Reset the spec to the first one of the new class; otherwise the
        -- spec dropdown points at a key that doesn't exist.
        local specs = sortedKeys(KickCD.DefaultSpells and KickCD.DefaultSpells[value])
        selectedSpec = specs[1]
        Spells:RefreshRows()
    end)
    classDD.frame:SetParent(parent)
    classDD.frame:ClearAllPoints()
    classDD.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    classDD.frame:Show()
    headerWidgets[#headerWidgets + 1] = classDD

    -- Spec dropdown
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

    -- Add button
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

    -- Reset button
    local resetBtn = AceGUI:Create("Button")
    resetBtn:SetText(L["Reset to defaults"])
    resetBtn:SetWidth(160)
    resetBtn:SetCallback("OnClick", function()
        StaticPopup_Show("KICKCD_RESET_SPELLS")
    end)
    resetBtn.frame:SetParent(parent)
    resetBtn.frame:ClearAllPoints()
    resetBtn.frame:SetPoint("LEFT", addBtn.frame, "RIGHT", 12, 0)
    resetBtn.frame:Show()
    headerWidgets[#headerWidgets + 1] = resetBtn
end

--- Re-render the AceGUI tree from the current profile state. Cheap to call
--- repeatedly; AceGUI pools widgets so we're not allocating per refresh.
function Spells:RefreshRows()
    if not panel or not panel:IsShown() then return end
    if rebuildScheduled then return end
    rebuildScheduled = true

    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then
        rebuildScheduled = false
        if not fallbackLabel then
            fallbackLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fallbackLabel:SetPoint("CENTER", panel, "CENTER", 0, 0)
            fallbackLabel:SetText("AceGUI not loaded")
        end
        fallbackLabel:Show()
        return
    end

    -- Tear down any previous tree first so we don't double-render.
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

    buildHeader(AceGUI, panel, classes)

    -- Scroll container for the row list. Anchored below the header bar.
    container = AceGUI:Create("ScrollFrame")
    container:SetLayout("List")
    container.frame:SetParent(panel)
    container.frame:ClearAllPoints()
    container.frame:SetPoint("TOPLEFT",     panel, "TOPLEFT",     16, -64)
    container.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    container.frame:Show()

    local list = getActiveList()
    if not list or #list == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText("No spells tracked. Click " .. L["Add spell..."] .. " or " .. L["Reset to defaults"] .. ".")
        lbl:SetFullWidth(true)
        container:AddChild(lbl)
    else
        for i = 1, #list do
            local row = buildRow(AceGUI, panel, list, i)
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

    panel = CreateFrame("Frame", "KickCDSpellsPanel")
    panel.name = L["Spells"]
    panel:Hide()  -- Settings will Show() it on category select

    panel:SetScript("OnShow", function() Spells:RefreshRows() end)
    panel:SetScript("OnHide", function()
        releaseAceGUITree()
        if fallbackLabel then fallbackLabel:Hide() end
    end)

    -- Re-render after a profile switch (which may wipe profile.spells back
    -- to whatever the new profile contains). Only re-renders when shown —
    -- otherwise the OnShow handler will rebuild lazily on next visit.
    if KickCD.RegisterMessage then
        KickCD:RegisterMessage("KickCD_PROFILE_CHANGED", function()
            if panel and panel:IsShown() then
                Spells:RefreshRows()
            end
        end)
    end

    return panel
end

--- Public entry point. Called from settings/Panel.lua (Agent C1) once the
--- main category exists. Safe to call multiple times — re-registration is
--- idempotent because Settings.RegisterCanvasLayoutSubcategory dedupes by
--- frame identity (and we keep a single panel instance).
function Spells:Register()
    if self._registered then return end
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return
    end
    if not (KickCD.Settings and KickCD.Settings.main) then
        -- Panel C1 hasn't built the parent category yet. Try again shortly.
        C_Timer.After(0.1, function() Spells:Register() end)
        return
    end

    ensurePanel()

    -- Seed the dropdown selection from the player's class so the editor
    -- opens on the user's "current" list by default.
    local _, classFile = UnitClass("player")
    if classFile and KickCD.DefaultSpells and KickCD.DefaultSpells[classFile] then
        selectedClass = selectedClass or classFile
        local specs = sortedKeys(KickCD.DefaultSpells[classFile])
        selectedSpec = selectedSpec or specs[1]
    end

    local sub = Settings.RegisterCanvasLayoutSubcategory(
        KickCD.Settings.main, panel, L["Spells"])
    KickCD.Settings.sub = KickCD.Settings.sub or {}
    KickCD.Settings.sub.spells = sub
    self._registered = true
end

-- Defer registration until PLAYER_LOGIN so KickCD.db, KickCD.Settings.main,
-- and AceGUI are all available. PLAYER_LOGIN fires after every addon's
-- OnInitialize/OnEnable, so the dependency chain is safe.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() Spells:Register() end)
