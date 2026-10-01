-- settings/Spells_Header.lua
--
-- The Spells page's chrome-block builders, peeled out of settings/Spells.lua (#28,
-- layout-§1), mirroring settings/Spells_Rows.lua: the class display name, color
-- and icon, the spec icon cache, the merged spec entries, and buildSpellsHeader
-- (the Specialization picker and the add box). Publishes Spells.BuildHeader,
-- which the page's renderRows calls at render time, never at file load, plus the
-- TitleCaseToken / ClassDisplayName test exports.
--
-- The page's own file-locals the builder used reach it through
-- Spells.__headerDeps, which settings/Spells.lua fills at its file end, read at
-- CALL time through the forwarders below. Its mutable state is never copied: the
-- selection is read through Spells:GetSelection and written through
-- deps().setSelection, and the header-widget list the page releases is the one
-- deps().newHeaderWidgets() hands back. The only load order this file needs is
-- its TOC line's: after settings/Spells.lua, whose Spells table it takes as a
-- file-scope upvalue.

local _, NS = ...

local L      = NS.L      or setmetatable({}, { __index = function(_, k) return k end })

local Spells = NS.Settings.SpellsPanel

-- Forwarders onto the page's file-locals, rebound under their old names so the
-- moved code below reads as it did in place.
local function deps() return Spells.__headerDeps end
local function sortedKeys(t) return deps().sortedKeys(t) end
local function specOrder(classFile) return deps().specOrder(classFile) end
local function currentSpellIds(...) return deps().currentSpellIds(...) end
local function addFromBox(...) return deps().addFromBox(...) end

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

-- [classFile] = { [specID] = iconFileID }. Built lazily from
-- GetSpecializationInfoForClassID, which hands back the specID directly --
-- no name round-trip, so nothing here depends on the client's locale.
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
                local specID, _, _, icon = GetSpecializationInfoForClassID(classID, i)
                if specID and icon then
                    cache[classFile][specID] = icon
                end
            end
        end
    end
    return cache
end

local function specIconMarkup(classFile, specID)
    if not specIconCache then specIconCache = buildSpecIconCache() end
    local byClass = specIconCache[classFile]
    local icon = byClass and byClass[specID]
    if icon then
        return ("|T%s:16:16:0:0|t"):format(tostring(icon))
    end
    return ""
end

local function buildSpecEntries()
    local entries = {}
    if type(NS.DefaultSpells) ~= "table" then return entries end

    local classOrder = sortedKeys(NS.DefaultSpells)
    for _, classFile in ipairs(classOrder) do
        local hex       = classColorHex(classFile)
        local cIcon     = classIconMarkup(classFile)
        local className = classDisplayName(classFile)
        for _, specID in ipairs(specOrder(classFile)) do
            -- The dropdown VALUE carries the numeric specID (locale-free);
            -- the LABEL is the spec's name in the player's own language, so
            -- a French user reads "Élémentaire" while the key stays 262.
            local specName = NS.Util.SpecDisplayName(specID)
            local sIcon    = specIconMarkup(classFile, specID)
            local label    = ("%s %s |c%s%s %s|r"):format(cIcon, sIcon, hex, className, specName)
            entries[#entries + 1] = {
                value     = classFile .. "/" .. specID,
                label     = label,
                classFile = classFile,
                specID    = specID,
            }
        end
    end
    return entries
end

--- The page-wide chrome block's contents: which spec is being edited, and the
--- act of adding a spell to it (options-ui-§14).
---
--- IT IS DRAWN ABOVE THE STRIP, not in the scroll, and that is the rule rather
--- than a preference: choosing which thing the page edits and creating a new one
--- both apply to every tab, so a control for either that sits under one tab
--- reads as belonging to that tab and vanishes the moment the reader clicks a
--- different one. `parent` is the frame H.PageHeader hands over; the block owns
--- everything inside it and the library owns the band it occupies.
local function buildSpellsHeader(AceGUI, headerCtx, parent)
    local H = NS.Settings and NS.Settings.Helpers
    local headerWidgets = deps().newHeaderWidgets()
    local selectedClass, selectedSpec = Spells:GetSelection()

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
    -- Width comes from the anchors below, not from here: the picker owns its whole row.
    specDD:SetCallback("OnValueChanged", function(_, _, value)
        local classFile, specID = value:match("^([^/]+)/(%d+)$")
        if classFile and specID then
            deps().setSelection(classFile, tonumber(specID))
            Spells:RefreshRows()
        end
    end)
    specDD.frame:SetParent(parent)
    specDD.frame:ClearAllPoints()
    specDD.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    specDD.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    specDD.frame:Show()
    headerWidgets[#headerWidgets + 1] = specDD

    -- THE LIBRARY'S ADD CONTROL, where a Button and a StaticPopup used to be. What the popup
    -- could not do, and this does: resolve a typed NAME through the client, take a shift-clicked
    -- spell link, suggest as the player types (the spellbook, plus the ids this spec already
    -- lists), tell two spells of one name apart by rank, and answer a bad entry on a status line
    -- under the box instead of a chat line behind the dialog.
    --
    -- IT NEEDS AN AceGUI CONTAINER, because O.IdInput ends in `parent:AddChild(group)` -- the
    -- band hands over a raw frame, so a SimpleGroup bridges the two.
    --
    -- STACKED UNDER THE PICKER, NOT BESIDE IT (owner, from the live panel, 2026-09-22). Side by
    -- side, the two blocks could not be made to line up: each is a caption over a control, and the
    -- two controls are different heights, so aligning the captions left the controls off and
    -- aligning the controls left the captions off. Stacking removes the question -- each block
    -- owns a full row and has nothing to line up with -- and it gives the box the whole width,
    -- which is what a box for typing names wants anyway. The band pays one more row for it.
    local addHost = AceGUI:Create("SimpleGroup")
    addHost:SetLayout("Flow")
    addHost.frame:SetParent(parent)
    addHost.frame:ClearAllPoints()
    -- Anchor LEFT…RIGHT against specDD.dropdown (the inner UIDropDownMenu
    -- frame) instead of specDD.frame (the outer AceGUI frame that
    -- includes the "Specialization" label above the dropdown control).
    -- The outer frame is 40 px tall when labeled (label 18 + dropdown
    -- 26) so a vertical-center anchor against it landed the button on
    -- the seam between the two — visually misaligned. Anchoring against
    -- the inner dropdown puts the button's vertical center on the
    -- dropdown control itself, ignoring the label. The -5 X offset
    -- restores the original ~12 px gap from the frame's right edge:
    -- the inner dropdown extends +17 px past the outer frame's right
    -- (decorative texture overhang), so -5 nets back to +12.
    -- AGAINST THE OUTER FRAME, NOT THE INNER DROPDOWN. The button this replaced had no label, so
    -- it anchored to specDD.dropdown -- the control below the "Specialization" caption -- to sit on
    -- the control's own vertical center. The add box HAS a label, so anchoring it there started its
    -- caption where the dropdown control starts and pushed its box a whole caption lower than the
    -- dropdown beside it. Aligned frame to frame, the two captions share a line and the two
    -- controls share a line. The +12 is the gap the old -5 was computing the long way round: the
    -- inner dropdown overhangs the outer frame's right by 17px of decorative texture.
    addHost.frame:SetPoint("TOPLEFT", specDD.frame, "BOTTOMLEFT", 0, -deps().HEADER_ROW_GAP)
    addHost.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    -- Which block it hangs off, and on which edge, for a harness that cannot read frame points:
    -- the AceGUI fake builds its widget frames itself rather than through the mocked CreateFrame,
    -- so `__points` is empty on them however the real client would have recorded it. Same reason
    -- the library records `__helpTint` on its help mark.
    addHost.__stackedUnder = "BOTTOMLEFT"
    addHost.frame:Show()
    headerWidgets[#headerWidgets + 1] = addHost

    H.IdInput(headerCtx, addHost, {
        -- THE LIBRARY'S OWN SPELL KIND, by name rather than a host table. A named kind needs no
        -- `base` because it IS the base: it comes with the spellbook as its suggestion source, the
        -- rank rows that tell two spells of one name apart, the client tooltip, and the name
        -- lookup. A host table would have to declare `base = "spell"` to get any of that back, and
        -- this page needs nothing a host table is for.
        kind       = "spell",
        -- WARN BEFORE THE CLICK. The Cooldown Manager refusal below fires at the ADD, in chat --
        -- correct, but after the player has chosen. This marks the row while they are still
        -- choosing. It works here precisely because the spells in question ARE in the spellbook,
        -- so they appear as suggestions; the same tag on a page whose ids are typed as digits
        -- would cover almost nothing.
        suggestTag = Spells.SuggestTag,
        label      = L["Add a spell"],
        tooltip    = L["Type a spell id or a name and pick from the list, or shift-click a spell link into the box, then press Enter or Add."],
        strings    = deps().ADD_STRINGS,
        -- What this spec already lists, so a player retyping a spell they disabled sees it
        -- offered rather than hunting the id. The spellbook comes with `kind = "spell"` and is
        -- not repeated here.
        candidates = currentSpellIds,
        onAdd      = addFromBox,
    })
end

Spells.BuildHeader       = buildSpellsHeader
Spells.TitleCaseToken    = titleCaseToken
Spells.ClassDisplayName  = classDisplayName
