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
    "silence", "root", "fear", "displace", "racial", "other",
}

-- Status-glyph textures for the "known to the player?" indicator on each
-- row. Matches the In-bags / Not-in-bags glyphs ConsumableMaster uses
-- (Interface\RaidFrame\ReadyCheck-Ready / -NotReady) so the visual
-- vocabulary is consistent across the user's addons.
local SPELL_KNOWN_ICON     = [[Interface\RaidFrame\ReadyCheck-Ready]]
local SPELL_NOT_KNOWN_ICON = [[Interface\RaidFrame\ReadyCheck-NotReady]]

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

-- Build the set of spellIDs the Blizzard Cooldown Manager would surface for
-- the currently selected (class, spec). Walks every CooldownViewerCategory
-- enum value and unions the spellIDs they expose. Returns nil when the API
-- is unavailable (older clients) so callers can fall back to lenient
-- validation.
local function getCooldownManagerSpellSet()
    if not C_CooldownViewer then return nil end
    local getCategorySet = C_CooldownViewer.GetCooldownViewerCategorySet
    local getInfo        = C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not (getCategorySet and getInfo and Enum and Enum.CooldownViewerCategory) then
        return nil
    end

    local set = {}
    local seenAny = false
    for _, category in pairs(Enum.CooldownViewerCategory) do
        local ok, ids = pcall(getCategorySet, category)
        if ok and type(ids) == "table" then
            for _, cdID in ipairs(ids) do
                local ok2, info = pcall(getInfo, cdID)
                if ok2 and type(info) == "table" and info.spellID then
                    set[info.spellID] = true
                    seenAny = true
                end
            end
        end
    end

    if not seenAny then return nil end
    return set
end

-- ---------------------------------------------------------------------------
-- Throttled commit pipeline
-- ---------------------------------------------------------------------------
--
-- Throttle (not debounce) is the right semantic here: the editor
-- coalesces a burst of edits (e.g. holding the spinner button,
-- toggling several rows in quick succession) into a single bus
-- dispatch per 50 ms window — we want a steady cadence during the
-- burst, not a quiet-period wait that delays the first commit
-- indefinitely.

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

if Util.Throttle then
    commitSoon = Util.Throttle(50, doCommit)
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
        local id, resolvedName = validateSpellInput(input)
        if not id then
            if KickCD.Util and KickCD.Util.print then
                KickCD.Util.print(L["Invalid spell"] .. ": " .. tostring(input))
            end
            return
        end

        local cmSet = getCooldownManagerSpellSet()
        if cmSet then
            if not cmSet[id] then
                local name = resolvedName or getSpellName(id) or tostring(id)
                if KickCD.Util and KickCD.Util.print then
                    KickCD.Util.print(("Spell %s (#%d) is not tracked by the Blizzard Cooldown Manager for this specialization."):format(name, id))
                end
                return
            end
        elseif KickCD._debugLog and KickCD.Util and KickCD.Util.print then
            KickCD.Util.print("C_CooldownViewer unavailable; skipping cooldown-manager validation for spell " .. tostring(id))
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
            spells[selectedClass][selectedSpec] = Util.DeepCopy(source)
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

-- Builds a row action button (Move up / Move down / Remove) as an AceGUI Icon
-- widget so the row matches ConsumableMaster's iconography rather than the
-- old "Up" / "Dn" / "X" text labels. opts.image is a texture path; opts.atlas
-- swaps in a Blizzard atlas via the inner texture's SetAtlas — needed for
-- transmog-icon-remove (the red "no entry" glyph) which has no plain path.
local function makeRowIconBtn(AceGUI, opts)
    local btn = AceGUI:Create("Icon")
    btn:SetImageSize(22, 22)
    btn:SetWidth(30)
    btn:SetHeight(26)
    if opts.atlas and btn.image and btn.image.SetAtlas then
        btn.image:SetAtlas(opts.atlas)
    elseif opts.image then
        btn:SetImage(opts.image)
    end
    if opts.disabled then
        if btn.image then
            if btn.image.SetDesaturated then btn.image:SetDesaturated(true) end
            if btn.image.SetVertexColor then btn.image:SetVertexColor(0.45, 0.45, 0.45) end
        end
    else
        if btn.image then
            if btn.image.SetDesaturated then btn.image:SetDesaturated(false) end
            if btn.image.SetVertexColor then btn.image:SetVertexColor(1, 1, 1) end
        end
        btn:SetCallback("OnClick", opts.onClick)
    end
    if opts.tooltip then
        btn:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltip)
            GameTooltip:Show()
        end)
        btn:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    end
    return btn
end

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
    if icon.image and icon.image.SetDesaturated then
        icon.image:SetDesaturated(entry.enabled == false)
    end
    local function showSpellTooltip(widget)
        if not entry.spellID then return end
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(entry.spellID)
        GameTooltip:Show()
    end
    local function hideSpellTooltip() GameTooltip:Hide() end
    icon:SetCallback("OnEnter", showSpellTooltip)
    icon:SetCallback("OnLeave", hideSpellTooltip)
    row:AddChild(icon)

    local label = AceGUI:Create("Label")
    local name = getSpellName(entry.spellID) or ("#" .. tostring(entry.spellID))
    label:SetText(name)
    -- Was 190 (trimmed from 220 to make room for the known/unknown
    -- status glyph). Bumped 25% to 238 to take advantage of the empty
    -- space on the right of each row — long spell names like
    -- "Counterspell" or "Shockwave (talented)" no longer truncate.
    label:SetWidth(238)
    row:AddChild(label)
    if label.frame and label.frame.HookScript then
        label.frame:EnableMouse(true)
        label.frame:HookScript("OnEnter", function() showSpellTooltip(label) end)
        label.frame:HookScript("OnLeave", hideSpellTooltip)
    end

    local check = AceGUI:Create("CheckBox")
    check:SetLabel("")
    check:SetValue(entry.enabled ~= false)
    check:SetWidth(40)
    check:SetCallback("OnValueChanged", function(_, _, value)
        entry.enabled = value and true or false
        if icon.image and icon.image.SetDesaturated then
            icon.image:SetDesaturated(not value)
        end
        commitSoon()
    end)
    row:AddChild(check)

    -- "Known to the player?" status glyph. Reads Compat.IsSpellAvailable
    -- (the same predicate IconGrid:BuildActiveList and Cooldowns:PollSpell
    -- use to decide whether to render the spell), so the green check ↔
    -- red X toggle is the user-facing reflection of "this row will / will
    -- not appear on the icon grid right now."
    --
    -- The check is global to the logged-in player, not scoped to the
    -- selected (class, spec) in the dropdown — so when the user is
    -- browsing another class's spec list, every spell will read as red,
    -- which is the correct fact ("you can't cast any of these"). The
    -- glyph is informational only; it doesn't gate enable/disable.
    local known = Compat.IsSpellAvailable
        and Compat.IsSpellAvailable(entry.spellID) or false
    local statusIcon = AceGUI:Create("Icon")
    statusIcon:SetImage(known and SPELL_KNOWN_ICON or SPELL_NOT_KNOWN_ICON)
    statusIcon:SetImageSize(20, 20)
    -- Box width hugs the 20 px image (1 px padding each side instead of 4).
    -- AceGUI's Icon widget anchors the texture to TOP center, so a narrower
    -- box pulls the visible glyph closer to the checkbox on its left —
    -- which is the "reduce spacing before the icon" half of the request.
    statusIcon:SetWidth(22)
    statusIcon:SetHeight(24)
    -- No OnClick — the glyph is purely informational. AceGUI's Icon
    -- still renders a clickable region without a callback, but the
    -- click is a no-op which matches what we want.
    local statusTooltip = known and L["Spell known"] or L["Spell not known"]
    statusIcon:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(statusTooltip)
        GameTooltip:Show()
    end)
    statusIcon:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    row:AddChild(statusIcon)

    -- Empty-text Label as a fixed-width spacer — the "increase spacing after
    -- the icon" half. AceGUI's Flow layout has no inter-widget gap of its
    -- own, so the canonical way to inject horizontal whitespace between two
    -- adjacent widgets is an invisible filler. Width covers the lost
    -- padding from the narrowed icon box plus the requested extra gap
    -- before the category dropdown.
    local statusSpacer = AceGUI:Create("Label")
    statusSpacer:SetText("")
    statusSpacer:SetWidth(14)
    row:AddChild(statusSpacer)

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
    if dd.frame and dd.frame.HookScript then
        dd.frame:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Category for future filtering. Currently informational only."])
            GameTooltip:Show()
        end)
        dd.frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row:AddChild(dd)

    local upBtn = makeRowIconBtn(AceGUI, {
        image    = [[Interface\ChatFrame\UI-ChatIcon-ScrollUp-Up]],
        tooltip  = L["Move up"],
        disabled = index == 1,
        onClick  = function()
            if index <= 1 then return end
            list[index], list[index - 1] = list[index - 1], list[index]
            commitSoon()
        end,
    })
    row:AddChild(upBtn)

    local downBtn = makeRowIconBtn(AceGUI, {
        image    = [[Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up]],
        tooltip  = L["Move down"],
        disabled = index == #list,
        onClick  = function()
            if index >= #list then return end
            list[index], list[index + 1] = list[index + 1], list[index]
            commitSoon()
        end,
    })
    row:AddChild(downBtn)

    local rmBtn = makeRowIconBtn(AceGUI, {
        atlas   = "transmog-icon-remove",
        tooltip = L["Remove"],
        onClick = function()
            table.remove(list, index)
            commitSoon()
        end,
    })
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

-- Title-cases a SCREAMING_TOKEN like "DEATHKNIGHT" or "BLOOD" into "Deathknight"
-- / "Blood". Splits compound class tokens that appear glued together
-- ("DEATHKNIGHT" -> "Death Knight", "DEMONHUNTER" -> "Demon Hunter") so the
-- merged dropdown reads naturally.
local CLASS_DISPLAY_OVERRIDES = {
    DEATHKNIGHT = "Death Knight",
    DEMONHUNTER = "Demon Hunter",
}

local function titleCaseToken(token)
    if not token then return "" end
    local s = token:lower():gsub("^%l", string.upper)
    return s
end

local function classDisplayName(classFile)
    if CLASS_DISPLAY_OVERRIDES[classFile] then return CLASS_DISPLAY_OVERRIDES[classFile] end
    if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] then
        return LOCALIZED_CLASS_NAMES_MALE[classFile]
    end
    return titleCaseToken(classFile)
end

local function classColorHex(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return "ffffffff" end
    if c.colorStr then return c.colorStr end
    return ("ff%02x%02x%02x"):format(
        math.floor((c.r or 1) * 255 + 0.5),
        math.floor((c.g or 1) * 255 + 0.5),
        math.floor((c.b or 1) * 255 + 0.5))
end

local function classIconMarkup(classFile)
    if CreateAtlasMarkup then
        local atlas = "classicon-" .. classFile:lower()
        local ok, markup = pcall(CreateAtlasMarkup, atlas, 16, 16)
        if ok and markup then return markup end
    end
    return ("|TInterface\\Icons\\ClassIcon_%s:16:16:0:0|t"):format(classFile:lower())
end

-- [classFile] = { [specToken] = iconFileID }. Built lazily from
-- GetSpecializationInfoForClassID; spec tokens are normalized to match the
-- keys used in defaults/Spells.lua (uppercased, spaces stripped, so "Beast
-- Mastery" -> "BEASTMASTERY").
local specIconCache

local function buildSpecIconCache()
    local cache = {}
    if not (GetNumClasses and GetClassInfo
            and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID) then
        return cache
    end
    for classID = 1, GetNumClasses() do
        local _, classFile = GetClassInfo(classID)
        if classFile then
            cache[classFile] = {}
            local nSpecs = GetNumSpecializationsForClassID(classID) or 0
            for i = 1, nSpecs do
                local _, specName, _, icon = GetSpecializationInfoForClassID(classID, i)
                if specName and icon then
                    local token = Util.NormalizeSpecToken(specName)
                    cache[classFile][token] = icon
                end
            end
        end
    end
    return cache
end

local function specIconMarkup(classFile, specToken)
    if not specIconCache then specIconCache = buildSpecIconCache() end
    local byClass = specIconCache[classFile]
    local icon = byClass and byClass[specToken]
    if icon then
        return ("|T%s:16:16:0:0|t"):format(tostring(icon))
    end
    return ""
end

local function buildSpecEntries()
    local entries = {}
    if type(KickCD.DefaultSpells) ~= "table" then return entries end

    local classOrder = sortedKeys(KickCD.DefaultSpells)
    for _, classFile in ipairs(classOrder) do
        local specs = sortedKeys(KickCD.DefaultSpells[classFile])
        local hex       = classColorHex(classFile)
        local cIcon     = classIconMarkup(classFile)
        local className = classDisplayName(classFile)
        for _, specToken in ipairs(specs) do
            local specName = titleCaseToken(specToken)
            local sIcon    = specIconMarkup(classFile, specToken)
            local label    = ("%s %s |c%s%s %s|r"):format(cIcon, sIcon, hex, className, specName)
            entries[#entries + 1] = {
                value     = classFile .. "/" .. specToken,
                label     = label,
                classFile = classFile,
                specToken = specToken,
            }
        end
    end
    return entries
end

local function buildSpellsHeader(AceGUI, parent)
    headerWidgets = {}

    local entries = buildSpecEntries()
    local items, order = {}, {}
    for i, e in ipairs(entries) do
        items[e.value] = e.label
        order[i]       = e.value
    end

    local specDD = AceGUI:Create("Dropdown")
    specDD:SetLabel(L["Specialization"])
    specDD:SetList(items, order)
    if selectedClass and selectedSpec then
        specDD:SetValue(selectedClass .. "/" .. selectedSpec)
    end
    specDD:SetWidth(280)
    specDD:SetCallback("OnValueChanged", function(_, _, value)
        local classFile, specToken = value:match("^([^/]+)/(.+)$")
        if classFile and specToken then
            selectedClass = classFile
            selectedSpec  = specToken
            Spells:RefreshRows()
        end
    end)
    specDD.frame:SetParent(parent)
    specDD.frame:ClearAllPoints()
    specDD.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
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
    -- Anchor LEFT…RIGHT against specDD.dropdown (the inner UIDropDownMenu
    -- frame) instead of specDD.frame (the outer AceGUI frame that
    -- includes the "Specialization" label above the dropdown control).
    -- The outer frame is 40 px tall when labelled (label 18 + dropdown
    -- 26) so a vertical-center anchor against it landed the button on
    -- the seam between the two — visually misaligned. Anchoring against
    -- the inner dropdown puts the button's vertical center on the
    -- dropdown control itself, ignoring the label. The -5 X offset
    -- restores the original ~12 px gap from the frame's right edge:
    -- the inner dropdown extends +17 px past the outer frame's right
    -- (decorative texture overhang), so -5 nets back to +12.
    addBtn.frame:SetPoint("LEFT", specDD.dropdown, "RIGHT", -5, 0)
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

    buildSpellsHeader(AceGUI, body)

    container = AceGUI:Create("ScrollFrame")
    container:SetLayout("List")
    container.frame:SetParent(body)
    container.frame:ClearAllPoints()
    container.frame:SetPoint("TOPLEFT",     body, "TOPLEFT",     16, -56)
    container.frame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -16, 16)
    container.frame:Show()

    -- Always render the scrollbar so this panel's right-edge gutter
    -- matches the schema-driven panels (General / Icons / Cast bar)
    -- regardless of how many spell rows the active class+spec has.
    -- The patch is restored on widget release, so the AceGUI pool
    -- stays clean for any other addon.
    local PanelHelpers = KickCD.Settings and KickCD.Settings.Helpers
    if PanelHelpers and PanelHelpers.PatchAlwaysShowScrollbar then
        PanelHelpers.PatchAlwaysShowScrollbar(container)
    end

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

    -- Talent / spellbook changes flip the per-row known/unknown glyph.
    -- Refresh while the panel is open so the indicators stay in sync
    -- with what IconGrid is rendering. Only registered once (ensurePanel
    -- short-circuits on subsequent calls).
    if KickCD.RegisterEvent then
        local function refreshIfShown()
            if panel and panel:IsShown() then Spells:RefreshRows() end
        end
        KickCD:RegisterEvent("SPELLS_CHANGED",       refreshIfShown)
        KickCD:RegisterEvent("TRAIT_CONFIG_UPDATED", refreshIfShown)
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
