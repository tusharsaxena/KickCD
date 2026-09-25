-- settings/Spells_Rows.lua
--
-- The Spells page's AceGUI row builders, peeled out of settings/Spells.lua
-- (layout-§1) so the page file sits back down in the 1000-1500 band. The move
-- is mechanical: every body and every comment below reads as it did in place.
-- Publishes Spells.BuildRow and Spells.ROW_HEIGHT on NS.Settings.SpellsPanel;
-- the page reads both at render time, never at file load.
--
-- The page's own file-locals the builders used (writer, commitSoon,
-- getSpellName, getSpellIcon, categoryList) reach them through
-- Spells.__rowDeps, which settings/Spells.lua fills at its file end. Each is
-- read at CALL time through the thin forwarders below, so the only order this
-- file needs is the one its TOC line states: after settings/Spells.lua, whose
-- Spells table it takes as a file-scope upvalue.

local _, NS = ...

local L      = NS.L      or setmetatable({}, { __index = function(_, k) return k end })
local Compat = NS.Compat or {}

local Spells = NS.Settings.SpellsPanel

-- Forwarders onto the page's file-locals, rebound under their old names so the
-- moved code below reads exactly as it did in place.
local function deps() return Spells.__rowDeps end
local function writer(verb, ...) return deps().writer(verb, ...) end
local function commitSoon() return deps().commitSoon() end
local function getSpellName(id) return deps().getSpellName(id) end
local function getSpellIcon(id) return deps().getSpellIcon(id) end
local function categoryList() return deps().categoryList() end

-- Status-glyph textures for the "known to the player?" indicator on each
-- row. Matches the In-bags / Not-in-bags glyphs ConsumableMaster uses
-- (Interface\RaidFrame\ReadyCheck-Ready / -NotReady) so the visual
-- vocabulary is consistent across the user's addons.
local SPELL_KNOWN_ICON     = [[Interface\RaidFrame\ReadyCheck-Ready]]
local SPELL_NOT_KNOWN_ICON = [[Interface\RaidFrame\ReadyCheck-NotReady]]

-- ---------------------------------------------------------------------------
-- AceGUI rows
-- ---------------------------------------------------------------------------

--- Line an Icon's ART up with the other controls in its row, not its FRAME.
---
--- AceGUI's Flow stacks a row's children on one alignment line: each child is placed so that
--- `child.alignoffset` -- or half its frame height when it names none -- lands on that line
--- (AceGUI-3.0.lua's Flow layout). For a CheckBox that is the right answer, because its art fills
--- its frame from the top (`checkbg:SetPoint("TOPLEFT")` at the frame's own height), so half the
--- frame IS the middle of the art.
---
--- An Icon is different, and it is the difference that made these rows look crooked: its texture is
--- hung 5px below the frame's top (`image:SetPoint("TOP", 0, -5)`, widgets/AceGUIWidget-Icon.lua)
--- and is SMALLER than the frame, so the art's middle sits at `5 + art/2` -- 15 in a 24px frame
--- carrying 20px of art, where the frame's own middle is 12. Every Icon in the row therefore rode
--- three pixels lower than the checkbox and the dropdown beside it.
---
--- Naming that point as the alignoffset puts the ART on the line instead of the frame. It changes
--- no size, so nothing has to fit a taller row: the library's own rule for this is a frame of
--- art + 10, which would want 30px in a 28px row.
local function alignIconArt(widget, artHeight)
    widget.alignoffset = 5 + artHeight / 2
    return widget
end

-- Builds a row action button (today only Remove) as an AceGUI Icon widget, so
-- the row matches the other Ka0s list editors' iconography rather than a text
-- "X". opts.image is a texture path -- normally a LibKa0s catalog mark through
-- NS.Icon -- and wins when given. opts.atlas is a Blizzard atlas drawn through
-- the inner texture's SetAtlas, for the degraded install only, where NS.Icon
-- answers nil (library-stack-§8, AP #63). opts.tint {r, g, b} colors an enabled
-- button's art: catalog marks are white in the alpha and carry no color of
-- their own.
local WHITE = { 1, 1, 1 }

local function makeRowIconBtn(AceGUI, opts)
    local btn = AceGUI:Create("Icon")
    alignIconArt(btn, 22)
    btn:SetImageSize(22, 22)
    btn:SetWidth(30)
    btn:SetHeight(26)
    if opts.image then
        btn:SetImage(opts.image)
    elseif opts.atlas and btn.image and btn.image.SetAtlas then
        btn.image:SetAtlas(opts.atlas)
    end
    if opts.disabled then
        if btn.image then
            if btn.image.SetDesaturated then btn.image:SetDesaturated(true) end
            if btn.image.SetVertexColor then btn.image:SetVertexColor(0.45, 0.45, 0.45) end
        end
    else
        if btn.image then
            if btn.image.SetDesaturated then btn.image:SetDesaturated(false) end
            local tint = opts.tint or WHITE
            if btn.image.SetVertexColor then btn.image:SetVertexColor(tint[1], tint[2], tint[3]) end
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

-- One builder per row widget, below. buildRow itself then reads as the column
-- order it renders — and AddChild ORDER *is* that column order, spacer
-- included, so the sequence of calls at the bottom is the layout.

-- The spell icon, plus the two tooltip closures the name label reuses so
-- hovering either one shows the same spell tooltip.
local function rowSpellIcon(AceGUI, entry)
    local icon = AceGUI:Create("Icon")
    icon:SetImage(getSpellIcon(entry.spellID) or 134400)
    alignIconArt(icon, 20)
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
    return icon, showSpellTooltip, hideSpellTooltip
end

-- An InteractiveLabel, not a Label with hooks on its frame: AceGUI pools that
-- frame process-wide and a hook cannot be taken off, so the hooks the name
-- used to lay on label.frame followed the frame into other addons' panels as a
-- stray KickCD spell tooltip and a label that ate clicks (KICKCD-R-02). Widget
-- callbacks are cleared by Release.
local function rowNameLabel(AceGUI, entry, showSpellTooltip, hideSpellTooltip)
    local label = AceGUI:Create("InteractiveLabel")
    local name = getSpellName(entry.spellID) or ("#" .. tostring(entry.spellID))
    label:SetText(name)
    -- Was 190 (trimmed from 220 to make room for the known/unknown
    -- status glyph). Bumped 25% to 238 to take advantage of the empty
    -- space on the right of each row — long spell names like
    -- "Counterspell" or "Shockwave (talented)" no longer truncate.
    label:SetWidth(238)
    -- No hover highlight: the name is not a button.
    label:SetHighlight(nil)
    label:SetCallback("OnEnter", function(w) showSpellTooltip(w) end)
    label:SetCallback("OnLeave", hideSpellTooltip)
    return label
end

-- The enable checkbox. It desaturates the icon it was handed, which is why the
-- icon has to be built first.
local function rowEnableCheck(AceGUI, entry, icon)
    local check = AceGUI:Create("CheckBox")
    check:SetLabel("")
    check:SetValue(entry.enabled ~= false)
    check:SetWidth(40)
    check:SetCallback("OnValueChanged", function(_, _, value)
        writer("SetSpellEnabled", entry.spellID, value)
        if icon.image and icon.image.SetDesaturated then
            icon.image:SetDesaturated(not value)
        end
        commitSoon()
    end)
    return check
end

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
local function rowKnownGlyph(AceGUI, entry)
    local known = Compat.IsSpellAvailable
        and Compat.IsSpellAvailable(entry.spellID) or false
    local statusIcon = AceGUI:Create("Icon")
    statusIcon:SetImage(known and SPELL_KNOWN_ICON or SPELL_NOT_KNOWN_ICON)
    alignIconArt(statusIcon, 20)
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
    return statusIcon
end

-- Empty-text Label as a fixed-width spacer — the "increase spacing after
-- the icon" half. AceGUI's Flow layout has no inter-widget gap of its
-- own, so the canonical way to inject horizontal whitespace between two
-- adjacent widgets is an invisible filler. Width covers the lost
-- padding from the narrowed icon box plus the requested extra gap
-- before the category dropdown.
local function rowSpacer(AceGUI, width)
    local spacer = AceGUI:Create("Label")
    spacer:SetText("")
    spacer:SetWidth(width)
    return spacer
end

local function rowCategoryDropdown(AceGUI, entry)
    local dd = AceGUI:Create("Dropdown")
    dd:SetList(categoryList())
    dd:SetValue(entry.category or "other")
    dd:SetWidth(120)
    dd:SetCallback("OnValueChanged", function(_, _, value)
        if writer("SetSpellCategory", entry.spellID, value) then commitSoon() end
    end)
    -- Through the widget's callbacks, not a hook on dd.frame: that frame is
    -- pooled, and AceGUI never mouse-enables it, so the old hook both leaked
    -- and never fired (KICKCD-R-02).
    local H = NS.Settings and NS.Settings.Helpers
    if H and H.AttachTooltip then
        H.AttachTooltip(dd, L["Category"],
            L["Category for future filtering. Currently informational only."])
    end
    return dd
end

-- The catalog's white "close" mark, tinted red so it still reads as "remove".
-- The Blizzard atlas is the degraded install's fallback only, and it is red
-- already, so it takes no tint.
local REMOVE_TINT = { 1, 0.3, 0.3 }

local function rowRemoveButton(AceGUI, list, index)
    local mark = NS.Icon and NS.Icon("close")
    return makeRowIconBtn(AceGUI, {
        image   = mark,
        atlas   = not mark and "transmog-icon-remove" or nil,
        tint    = mark and REMOVE_TINT or nil,
        tooltip = L["Remove"],
        -- By the spellID the row showed, read at click time. `index` is only
        -- valid until the next rebuild, so a stale click past the end of a list
        -- that has since shrunk reads nil and removes nothing.
        onClick = function()
            local removedId = list[index] and list[index].spellID
            if writer("RemoveSpell", removedId) then commitSoon() end
        end,
    })
end

-- Every row in this list is the SAME height, and that is a requirement rather
-- than a tidy coincidence: ReorderList computes the drop position as arithmetic
-- on the stride, never as a hit test, so a list of unequal rows drops in the
-- wrong place (options-ui-§18).
local ROW_HEIGHT = 28

local function buildRow(AceGUI, list, index)
    local entry = list[index]
    if not entry then return end

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(ROW_HEIGHT)

    -- The drag handle owns a fixed gutter at the row's FAR LEFT and the row's
    -- contents start beyond it (options-ui-§8's `handle gutter`). The width is
    -- read off the library rather than restated, for the reason every layout
    -- constant is: a host copy is the copy that goes stale.
    local W = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
    row:AddChild(rowSpacer(AceGUI, (W and W.ROW_BOX and W.ROW_BOX.HANDLE_W) or 30))

    local icon, showSpellTooltip, hideSpellTooltip = rowSpellIcon(AceGUI, entry)
    row:AddChild(icon)
    row:AddChild(rowNameLabel(AceGUI, entry, showSpellTooltip, hideSpellTooltip))
    row:AddChild(rowEnableCheck(AceGUI, entry, icon))
    row:AddChild(rowKnownGlyph(AceGUI, entry))
    row:AddChild(rowSpacer(AceGUI, 14))
    row:AddChild(rowCategoryDropdown(AceGUI, entry))
    row:AddChild(rowRemoveButton(AceGUI, list, index))

    return row
end
Spells.BuildRow   = buildRow
Spells.ROW_HEIGHT = ROW_HEIGHT
